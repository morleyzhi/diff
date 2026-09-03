#!/bin/zsh
set -euo pipefail

OUT="${1:?usage: make-icon.sh AppIcon.icns}"
TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

python3 - "$TMP/base.png" <<'PY'
from pathlib import Path
import struct
import sys
import zlib

size = 1024
path = Path(sys.argv[1])
pixels = bytearray(size * size * 4)

def set_pixel(x, y, r, g, b, a=255):
    if 0 <= x < size and 0 <= y < size:
        i = (y * size + x) * 4
        pixels[i:i+4] = bytes((r, g, b, a))

def fill_rect(x, y, w, h, color):
    r, g, b, a = color
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            set_pixel(xx, yy, r, g, b, a)

# rounded-ish dark background
fill_rect(0, 0, size, size, (0, 0, 0, 0))
fill_rect(64, 64, 896, 896, (36, 39, 46, 255))
# left / right columns
fill_rect(150, 180, 280, 664, (232, 88, 92, 255))
fill_rect(594, 180, 280, 664, (72, 176, 104, 255))
# center preview
fill_rect(478, 220, 68, 584, (90, 96, 110, 255))
fill_rect(490, 300, 44, 90, (232, 88, 92, 255))
fill_rect(490, 420, 44, 110, (72, 176, 104, 255))

def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

raw = b''.join(b'\x00' + pixels[row*size*4:(row+1)*size*4] for row in range(size))
png = b''.join([
    b'\x89PNG\r\n\x1a\n',
    chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)),
    chunk(b'IDAT', zlib.compress(raw, 9)),
    chunk(b'IEND', b''),
])
path.write_bytes(png)
PY

for dim in 16 32 64 128 256 512 1024; do
  sips -z "$dim" "$dim" "$TMP/base.png" --out "$ICONSET/icon_${dim}x${dim}.png" >/dev/null
done
cp "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png" "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns -o "$OUT" "$ICONSET"
rm -rf "$TMP"
