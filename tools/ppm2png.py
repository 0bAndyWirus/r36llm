#!/usr/bin/env python3
"""Convert binary P6 PPM images to PNG without external dependencies.

Usage: python tools/ppm2png.py "out/render/*.ppm"
"""

import argparse
import glob
import os
import struct
import sys
import zlib


_WHITESPACE = b" \t\r\n\v\f"


def _token(data, position):
    while position < len(data):
        if data[position] in _WHITESPACE:
            position += 1
        elif data[position] == ord("#"):
            end = data.find(b"\n", position)
            if end < 0:
                raise ValueError("unterminated PPM header comment")
            position = end + 1
        else:
            break
    start = position
    while position < len(data) and data[position] not in _WHITESPACE and data[position] != ord("#"):
        position += 1
    if start == position:
        raise ValueError("incomplete PPM header")
    return data[start:position], position


def _chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def convert(path):
    with open(path, "rb") as source:
        data = source.read()

    position = 0
    tokens = []
    for _ in range(4):
        token, position = _token(data, position)
        tokens.append(token)
    if tokens[0] != b"P6":
        raise ValueError("not a binary P6 PPM")
    try:
        width, height, maximum = (int(token) for token in tokens[1:])
    except ValueError as error:
        raise ValueError("invalid PPM dimensions or maximum value") from error
    if width <= 0 or height <= 0 or not 1 <= maximum <= 65535:
        raise ValueError("invalid PPM dimensions or maximum value")
    if position >= len(data) or data[position] not in _WHITESPACE:
        raise ValueError("missing PPM raster separator")
    # Treat CRLF as a single header separator, without consuming raster bytes.
    if data[position : position + 2] == b"\r\n":
        position += 2
    else:
        position += 1

    sample_bytes = 1 if maximum < 256 else 2
    row_bytes = width * 3 * sample_bytes
    raster_size = row_bytes * height
    raster = data[position : position + raster_size]
    if len(raster) != raster_size:
        raise ValueError("truncated PPM raster")

    bit_depth = 8 if sample_bytes == 1 else 16
    full_scale = (1 << bit_depth) - 1
    if maximum != full_scale:
        scaled = bytearray(raster_size)
        for offset in range(0, raster_size, sample_bytes):
            sample = int.from_bytes(raster[offset : offset + sample_bytes], "big")
            if sample > maximum:
                raise ValueError("PPM sample exceeds maximum value")
            value = (sample * full_scale + maximum // 2) // maximum
            scaled[offset : offset + sample_bytes] = value.to_bytes(sample_bytes, "big")
        raster = scaled

    compressor = zlib.compressobj()
    compressed = bytearray()
    for row in range(height):
        start = row * row_bytes
        compressed.extend(compressor.compress(b"\0" + raster[start : start + row_bytes]))
    compressed.extend(compressor.flush())
    header = struct.pack(">IIBBBBB", width, height, bit_depth, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", compressed)
        + _chunk(b"IEND", b"")
    )
    output_path = os.path.splitext(path)[0] + ".png"
    with open(output_path, "wb") as output:
        output.write(png)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", help="P6 PPM files or glob patterns")
    args = parser.parse_args()
    failed = False
    for pattern in args.files:
        paths = [pattern] if os.path.isfile(pattern) else sorted(glob.glob(pattern))
        if not paths:
            print(f"{pattern}: no matching files", file=sys.stderr)
            failed = True
            continue
        for path in paths:
            try:
                convert(path)
            except (OSError, ValueError, OverflowError, struct.error) as error:
                print(f"{path}: {error}", file=sys.stderr)
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
