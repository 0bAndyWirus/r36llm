#!/usr/bin/env python3
"""Generate the U-Boot splash images (logo.bmp, battery_0..5.bmp, battery_fail.bmp).

U-Boot on the R36S shows logo.bmp while booting and battery_*.bmp while charging powered off.
The images are drawn with the Spleen 12x24 font from app/src/font.h, so no extra assets are needed.

Usage: python tools/make_boot_images.py [output_dir]   (default: out/boot)
"""

import re
import struct
import sys
from pathlib import Path

WIDTH, HEIGHT = 640, 480
ROOT = Path(__file__).resolve().parent.parent

BLACK = (0, 0, 0)
CYAN = (64, 224, 240)
WHITE = (235, 235, 235)
GREY = (120, 120, 120)
GREEN = (80, 220, 110)
YELLOW = (240, 200, 60)
RED = (230, 70, 60)


def load_font():
    """Parse the generated font table: 224 glyphs (codepoints 32-255), 24 rows of 12 bits."""
    text = (ROOT / "app" / "src" / "font.h").read_text(encoding="utf-8")
    body = text[text.index("font[224][24]") :]
    rows = [int(v, 16) for v in re.findall(r"0x([0-9a-fA-F]{4})", body)]
    if len(rows) < 224 * 24:
        raise SystemExit("font.h: unexpected table size")
    return [rows[i * 24 : (i + 1) * 24] for i in range(224)]


class Canvas:
    def __init__(self):
        self.px = [[BLACK] * WIDTH for _ in range(HEIGHT)]

    def rect(self, x, y, w, h, color):
        for yy in range(max(0, y), min(HEIGHT, y + h)):
            row = self.px[yy]
            for xx in range(max(0, x), min(WIDTH, x + w)):
                row[xx] = color

    def text(self, font, s, y, scale, color):
        """Draw s horizontally centred with its top at y, each font pixel scaled to scale x scale."""
        x0 = (WIDTH - len(s) * 12 * scale) // 2
        for i, ch in enumerate(s):
            code = ord(ch)
            glyph = font[code - 32] if 32 <= code <= 255 else font[ord("?") - 32]
            for gy, bits in enumerate(glyph):
                for gx in range(12):
                    if bits & (0x8000 >> gx):
                        self.rect(x0 + (i * 12 + gx) * scale, y + gy * scale, scale, scale, color)

    def save_bmp(self, path):
        """24-bit bottom-up BMP with a BITMAPINFOHEADER, the format U-Boot's bmp loader expects."""
        stride = (WIDTH * 3 + 3) & ~3
        pixels = bytearray()
        for row in reversed(self.px):
            line = bytearray()
            for r, g, b in row:
                line += bytes((b, g, r))
            line += b"\0" * (stride - len(line))
            pixels += line
        header = struct.pack("<2sIHHI", b"BM", 54 + len(pixels), 0, 0, 54)
        info = struct.pack("<IiiHHIIiiII", 40, WIDTH, HEIGHT, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
        path.write_bytes(header + info + pixels)


def battery(c, level, color):
    """Battery outline centred on screen with `level` of 5 segments filled."""
    w, h, t = 120, 200, 8
    x, y = (WIDTH - w) // 2, 110
    c.rect(x + w // 2 - 25, y - 20, 50, 20, WHITE)  # terminal cap
    c.rect(x, y, w, t, WHITE)
    c.rect(x, y + h - t, w, t, WHITE)
    c.rect(x, y, t, h, WHITE)
    c.rect(x + w - t, y, t, h, WHITE)
    seg_h = (h - 2 * t - 6 * 6) // 5
    for i in range(level):
        sy = y + h - t - 6 - (i + 1) * seg_h - i * 6
        c.rect(x + t + 6, sy, w - 2 * t - 12, seg_h, color)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "out" / "boot"
    out.mkdir(parents=True, exist_ok=True)
    font = load_font()

    logo = Canvas()
    logo.text(font, "R36LLM", 120, 5, CYAN)
    logo.text(font, "a tiny AI in your pocket", 270, 2, WHITE)
    logo.text(font, "booting...", 400, 1, GREY)
    logo.save_bmp(out / "logo.bmp")

    for level in range(6):
        c = Canvas()
        color = RED if level <= 1 else YELLOW if level <= 2 else GREEN
        battery(c, level, color)
        c.text(font, "R36LLM - charging", 380, 1, GREY)
        c.save_bmp(out / f"battery_{level}.bmp")

    fail = Canvas()
    battery(fail, 0, RED)
    fail.text(font, "!", 150, 5, RED)
    fail.text(font, "Battery too low - please charge", 380, 1, RED)
    fail.save_bmp(out / "battery_fail.bmp")

    print(f"wrote 8 images to {out}")


if __name__ == "__main__":
    main()
