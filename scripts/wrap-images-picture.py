#!/usr/bin/env python3
"""
Wrap all <img src="asset/*.jpg|png|...">  in <picture> with WebP source.
Also rewrite CSS background-image: url('asset/*.jpg|png') to use .webp.
Idempotent: skips images already wrapped.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HTML = ROOT / "index.html"
ASSET = ROOT / "asset"

content = HTML.read_text(encoding="utf-8")

# Match <img ...> tags whose src is an asset image
IMG_RE = re.compile(
    r'(?P<full><img\s+(?P<attrs>[^>]*?src="(?P<src>asset/[^"]+\.(?:jpg|jpeg|png|JPG|JPEG|PNG))"[^>]*?)\s*/?>)',
    re.IGNORECASE,
)

def webp_exists_for(src: str) -> str | None:
    # Decode HTML-encoded characters in URLs (only space for our case)
    src_decoded = src.replace("%20", " ").replace("%26", "&").replace("%28", "(").replace("%29", ")")
    p = ASSET / Path(src_decoded).relative_to("asset")
    webp = p.with_suffix(".webp")
    if webp.exists():
        # Return the URL form (preserve URL encoding from src)
        webp_url = src.rsplit(".", 1)[0] + ".webp"
        return webp_url
    return None

def wrap_img(m: re.Match) -> str:
    full = m.group("full")
    src = m.group("src")
    # Skip if already inside a <picture> (heuristic: parent context will be caught by surrounding text)
    webp_url = webp_exists_for(src)
    if not webp_url:
        return full
    return f'<picture><source srcset="{webp_url}" type="image/webp">{full}</picture>'

# Avoid double-wrapping: skip <img> already preceded by <source srcset
# Strategy: process file line by line, track whether we're inside an existing <picture>
new_lines = []
inside_picture = False
img_count = 0
wrapped_count = 0

for line in content.splitlines(keepends=True):
    if "<picture>" in line:
        inside_picture = True
    if "</picture>" in line:
        inside_picture = False
        new_lines.append(line)
        continue
    if inside_picture:
        new_lines.append(line)
        continue
    matches = list(IMG_RE.finditer(line))
    if not matches:
        new_lines.append(line)
        continue
    img_count += len(matches)
    new_line = line
    # Replace from end so positions stay valid
    for m in reversed(matches):
        replacement = wrap_img(m)
        if replacement != m.group("full"):
            wrapped_count += 1
        new_line = new_line[:m.start()] + replacement + new_line[m.end():]
    new_lines.append(new_line)

new_content = "".join(new_lines)

# Now rewrite CSS background-image: url('asset/...') to .webp
CSS_URL_RE = re.compile(
    r'url\((?P<quote>["\']?)(?P<src>asset/[^)"\']+\.(?:jpg|jpeg|png|JPG|JPEG|PNG))(?P=quote)\)',
    re.IGNORECASE,
)
css_count = 0

def rewrite_css(m: re.Match) -> str:
    src = m.group("src")
    quote = m.group("quote")
    webp = webp_exists_for(src)
    if not webp:
        return m.group(0)
    nonlocal_count[0] += 1
    return f'url({quote}{webp}{quote})'

nonlocal_count = [0]
new_content = CSS_URL_RE.sub(rewrite_css, new_content)
css_count = nonlocal_count[0]

HTML.write_text(new_content, encoding="utf-8")

print(f"<img> tags found: {img_count}")
print(f"<img> wrapped in <picture>: {wrapped_count}")
print(f"CSS url() rewritten: {css_count}")
