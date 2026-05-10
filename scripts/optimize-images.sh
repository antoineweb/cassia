#!/usr/bin/env bash
# Convert all images in asset/ to WebP, resizing to max 1920px wide.
# Originals are kept untouched. Skips files where .webp already exists and is newer.
#
# Requirements: cwebp (Homebrew: brew install webp), sips (macOS native).
# Usage: bash scripts/optimize-images.sh

set -euo pipefail

ASSET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/asset"
MAX_WIDTH=1920
QUALITY_PHOTO=80
QUALITY_INFOGRAPHIC=90
QUALITY_CERT=85

if ! command -v cwebp >/dev/null 2>&1; then
  echo "ERROR: cwebp not found. Install with: brew install webp"
  exit 1
fi
if ! command -v sips >/dev/null 2>&1; then
  echo "ERROR: sips not found (macOS only)."
  exit 1
fi

total_before=0
total_after=0
count=0

# Quality picker: lossless for logos with alpha, higher quality for infographics/maps.
pick_quality() {
  local file="$1"
  local lower
  lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *logo*.png|*newlogo*.png) echo "lossless" ;;
    *map*.png|*map*.jpg) echo "$QUALITY_INFOGRAPHIC" ;;
    *cover*video*) echo "$QUALITY_INFOGRAPHIC" ;;
    *certificate*) echo "$QUALITY_CERT" ;;
    *) echo "$QUALITY_PHOTO" ;;
  esac
}

# Find images (jpg/jpeg/png), skip already-webp files.
while IFS= read -r -d '' file; do
  rel="${file#$ASSET_DIR/}"
  base="${file%.*}"
  webp_out="${base}.webp"

  # Skip if .webp exists and is newer than the source
  if [ -f "$webp_out" ] && [ "$webp_out" -nt "$file" ]; then
    continue
  fi

  size_before=$(stat -f%z "$file")
  width=$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  quality=$(pick_quality "$file")

  # Always go through sips → temp JPEG/PNG to normalize color space (handles CMYK, etc.)
  ext="${file##*.}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  tmp_input="$(mktemp -t cassia-img).${ext_lower}"
  if [ -n "${width:-}" ] && [ "$width" -gt "$MAX_WIDTH" ]; then
    sips --resampleWidth "$MAX_WIDTH" -s format "$ext_lower" -s formatOptions best "$file" --out "$tmp_input" >/dev/null 2>&1 || cp "$file" "$tmp_input"
  else
    sips -s format "$ext_lower" "$file" --out "$tmp_input" >/dev/null 2>&1 || cp "$file" "$tmp_input"
  fi

  # Convert to WebP (continue on failure)
  if [ "$quality" = "lossless" ]; then
    if ! cwebp -lossless -quiet "$tmp_input" -o "$webp_out" 2>/dev/null; then
      printf "  %-60s  SKIPPED (cwebp error)\n" "$rel"
      rm -f "$tmp_input"
      continue
    fi
  else
    if ! cwebp -q "$quality" -quiet "$tmp_input" -o "$webp_out" 2>/dev/null; then
      printf "  %-60s  SKIPPED (cwebp error)\n" "$rel"
      rm -f "$tmp_input"
      continue
    fi
  fi

  rm -f "$tmp_input"

  size_after=$(stat -f%z "$webp_out")
  saved=$((size_before - size_after))
  ratio=$(awk -v a="$size_before" -v b="$size_after" 'BEGIN{ if (a>0) printf "%.0f", (1-b/a)*100; else print 0 }')

  total_before=$((total_before + size_before))
  total_after=$((total_after + size_after))
  count=$((count + 1))

  printf "  %-60s  %6d KB → %6d KB  (-%s%%)\n" "$rel" $((size_before/1024)) $((size_after/1024)) "$ratio"
done < <(find "$ASSET_DIR" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
  \) ! -path "*/.DS_Store" -print0)

echo ""
echo "============================================"
printf "Converted %d images.\n" "$count"
printf "Total before: %d MB\n" $((total_before/1024/1024))
printf "Total after:  %d MB\n" $((total_after/1024/1024))
if [ "$total_before" -gt 0 ]; then
  ratio=$(awk -v a="$total_before" -v b="$total_after" 'BEGIN{ printf "%.0f", (1-b/a)*100 }')
  printf "Saved: %s%%\n" "$ratio"
fi
echo "============================================"
