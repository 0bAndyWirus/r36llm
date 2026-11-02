#!/usr/bin/env python3
"""Convert a raw R36S framebuffer dump (640x480, 32 bpp BGRX) to PNG without dependencies.

Usage: python tools/fb2png.py <dump.raw> <output.png>
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ppm2png  # noqa: E402

WIDTH, HEIGHT, BPP = 640, 480, 4


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    source, target = sys.argv[1], sys.argv[2]
    data = open(source, "rb").read()
    if len(data) < WIDTH * HEIGHT * BPP:
        print(f"{source}: expected {WIDTH * HEIGHT * BPP} bytes, got {len(data)}", file=sys.stderr)
        return 1
    rgb = bytearray(WIDTH * HEIGHT * 3)
    rgb[0::3] = data[2 : WIDTH * HEIGHT * BPP : BPP]
    rgb[1::3] = data[1 : WIDTH * HEIGHT * BPP : BPP]
    rgb[2::3] = data[0 : WIDTH * HEIGHT * BPP : BPP]
    ppm = os.path.splitext(target)[0] + ".ppm"
    with open(ppm, "wb") as out:
        out.write(b"P6\n%d %d\n255\n" % (WIDTH, HEIGHT) + bytes(rgb))
    try:
        ppm2png.convert(ppm)
    finally:
        os.remove(ppm)
    return 0


if __name__ == "__main__":
    sys.exit(main())
