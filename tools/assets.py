#!/usr/bin/env python3
"""Original antialiased white map dot, tinted by native textures at runtime."""
import math
import struct
from pathlib import Path


def dot():
    pixels = bytearray()
    for y in range(16):
        for x in range(16):
            alpha = round(max(0, min(1, 7 - math.hypot(x - 7.5, y - 7.5))) * 255)
            pixels.extend((255, 255, 255, alpha))
    return struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, 16, 16, 32, 0x28) + pixels


if __name__ == "__main__":
    (Path(__file__).resolve().parents[1] / "Media/MapDot.tga").write_bytes(dot())
