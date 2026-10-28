#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Crée dans un dossier trois fichiers d'essai, sans aucune dépendance :
un PNG et un BMP valides, et un faux RAW (qui doit produire une erreur)."""

import os
import struct
import sys
import zlib


def png(path, w=64, h=48):
    rows = []
    for y in range(h):
        row = bytearray(b"\x00")
        for x in range(w):
            row += bytes((x * 255 // (w - 1), y * 255 // (h - 1), 128))
        rows.append(bytes(row))
    data = zlib.compress(b"".join(rows))

    def chunk(tag, body):
        c = struct.pack(">I", len(body)) + tag + body
        return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", data))
        f.write(chunk(b"IEND", b""))


def bmp(path, w=64, h=48):
    pad = (4 - (w * 3) % 4) % 4
    rows = []
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            row += bytes((128, y * 255 // (h - 1), x * 255 // (w - 1)))  # BGR
        rows.append(bytes(row) + b"\x00" * pad)
    pixels = b"".join(rows)
    header = b"BM" + struct.pack("<IHHI", 54 + len(pixels), 0, 0, 54)
    dib = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    with open(path, "wb") as f:
        f.write(header + dib + pixels)


def main():
    folder = sys.argv[1]
    os.makedirs(folder, exist_ok=True)
    png(os.path.join(folder, "a.png"))
    bmp(os.path.join(folder, "b.bmp"))
    with open(os.path.join(folder, "bad.arw"), "wb") as f:
        f.write(os.urandom(2048))
    print(f"échantillons créés dans {folder}: {sorted(os.listdir(folder))}")


if __name__ == "__main__":
    main()
