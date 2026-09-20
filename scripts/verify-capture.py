#!/usr/bin/env python3
"""Reject a simulator screenshot that caught the device mid-composite.

`xcrun simctl io … screenshot` occasionally returns a frame in which the
Dynamic Island cut-out has not been composited yet, leaving a black bar across
the top of an otherwise correct image. It happened in roughly half of the
captures on an iPhone 17 Pro, which is often enough to bake one into the
committed screenshots.

The game paints its sky edge to edge, so a top strip that is entirely black is
never a real frame. Exits non-zero when it finds one, which tells the capture
script to take the shot again.

    python3 scripts/verify-capture.py img/screens/menu.png
"""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

# The strip to inspect, as a fraction of the image height. Comfortably inside
# the island on every device that has one.
BAND_TOP = 0.02
BAND_BOTTOM = 0.05


def rows_of(path: Path) -> tuple[int, int, list[bytearray]]:
    """Decode an 8-bit RGBA PNG into its rows. No third-party imaging needed."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")

    position, compressed, header = 8, b"", None
    while position < len(data):
        length = struct.unpack(">I", data[position : position + 4])[0]
        kind = data[position + 4 : position + 8]
        chunk = data[position + 8 : position + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"IDAT":
            compressed += chunk
        position += 12 + length

    if header is None:
        raise SystemExit(f"{path} has no IHDR")
    width, height, depth, colour_type = header[0], header[1], header[2], header[3]
    if depth != 8 or colour_type != 6:
        raise SystemExit(f"{path} is not 8-bit RGBA")

    raw = zlib.decompress(compressed)
    stride, bpp = width * 4, 4
    rows: list[bytearray] = []
    previous = bytearray(stride)
    offset = 0

    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset : offset + stride])
        offset += stride
        for index in range(stride):
            left = line[index - bpp] if index >= bpp else 0
            up = previous[index]
            up_left = previous[index - bpp] if index >= bpp else 0
            if filter_type == 1:
                line[index] = (line[index] + left) & 0xFF
            elif filter_type == 2:
                line[index] = (line[index] + up) & 0xFF
            elif filter_type == 3:
                line[index] = (line[index] + (left + up) // 2) & 0xFF
            elif filter_type == 4:
                estimate = left + up - up_left
                d_left, d_up, d_up_left = (
                    abs(estimate - left),
                    abs(estimate - up),
                    abs(estimate - up_left),
                )
                if d_left <= d_up and d_left <= d_up_left:
                    line[index] = (line[index] + left) & 0xFF
                elif d_up <= d_up_left:
                    line[index] = (line[index] + up) & 0xFF
                else:
                    line[index] = (line[index] + up_left) & 0xFF
        rows.append(line)
        previous = line

    return width, height, rows


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    width, height, rows = rows_of(path)

    # Sample only the island's own width. Widening this to the whole strip
    # dilutes the black with the sky either side and the check stops firing.
    x_from, x_to = int(width * 0.43), int(width * 0.57)
    y_from, y_to = int(height * BAND_TOP), int(height * BAND_BOTTOM)

    total = black = 0
    for y in range(y_from, y_to):
        row = rows[y]
        for x in range(x_from, x_to, 4):
            total += 1
            if row[x * 4] < 12 and row[x * 4 + 1] < 12 and row[x * 4 + 2] < 12:
                black += 1

    if total and black == total:
        print(f"✖ {path}: the top strip is entirely black — recomposite", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
