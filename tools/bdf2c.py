#!/usr/bin/env python3
"""Convert the Spleen 12x24 BDF into the framebuffer's C++ font table.

Usage: python tools/bdf2c.py spleen-12x24.bdf app/src/font.h
"""
import argparse
from pathlib import Path

LICENSE = """/*
 * Spleen 12x24, https://github.com/fcambus/spleen
 * Copyright (c) 2018-2026, Frederic Cambus
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */
"""


def convert(source):
    glyphs = [[0] * 24 for _ in range(224)]
    encoding = None
    box = None
    rows = None
    for line in source.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "STARTCHAR":
            encoding, box, rows = None, None, None
        elif parts[0] == "ENCODING":
            encoding = int(parts[1])
        elif parts[0] == "BBX":
            box = tuple(map(int, parts[1:5]))
        elif parts[0] == "BITMAP":
            rows = []
        elif parts[0] == "ENDCHAR":
            if encoding is not None and 32 <= encoding <= 255:
                if box != (12, 24, 0, -5) or rows is None or len(rows) != 24:
                    raise ValueError(f"unexpected glyph layout for {encoding}")
                glyphs[encoding - 32] = rows
            rows = None
        elif rows is not None:
            rows.append(int(parts[0], 16))
    lines = [
        LICENSE,
        "#pragma once\n#include <cstdint>\n\nnamespace r36 {\n",
        "// Each row uses the high 12 bits, leftmost pixel first.\n",
        "inline constexpr uint16_t font[224][24] = {\n",
    ]
    for code, rows in enumerate(glyphs, 32):
        lines.append("    {" + ", ".join(f"0x{row:04x}" for row in rows) + f"}}, // {code}\n")
    lines.append("};\n} // namespace r36\n")
    return "".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(
        convert(args.input.read_text(encoding="ascii")), encoding="utf-8", newline="\n"
    )


if __name__ == "__main__":
    main()
