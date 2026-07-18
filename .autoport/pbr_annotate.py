#!/usr/bin/env python3
"""Grecharged-pbr-materials round-5: annotate a device still for the shadow-attributability
proof (owner acceptance: caster -> shadow visually connected; shadow extends away from the
visible sun).

Usage:
  pbr_annotate.py <in.png> <out.png> <spec> [<spec> ...]
  spec = arrow:x1,y1,x2,y2,label   (arrow from (x1,y1) to (x2,y2) with text label)
       | text:x,y,label
Coordinates in source-image pixels. Yellow annotations with black outline for readability.
"""
import sys
from PIL import Image, ImageDraw, ImageFont
import math


def draw_text(dr, x, y, label, font):
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            dr.text((x + dx, y + dy), label, fill=(0, 0, 0), font=font)
    dr.text((x, y), label, fill=(255, 255, 0), font=font)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    img = Image.open(sys.argv[1]).convert("RGB")
    dr = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/liberation-sans-fonts/LiberationSans-Bold.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for spec in sys.argv[3:]:
        kind, rest = spec.split(":", 1)
        parts = rest.split(",")
        if kind == "arrow":
            x1, y1, x2, y2 = (int(v) for v in parts[:4])
            label = ",".join(parts[4:])
            dr.line((x1, y1, x2, y2), fill=(255, 255, 0), width=3)
            ang = math.atan2(y2 - y1, x2 - x1)
            for da in (math.pi * 5 / 6, -math.pi * 5 / 6):
                hx = x2 + 14 * math.cos(ang + da)
                hy = y2 + 14 * math.sin(ang + da)
                dr.line((x2, y2, hx, hy), fill=(255, 255, 0), width=3)
            if label:
                draw_text(dr, x1, y1 - 24, label, font)
        elif kind == "text":
            x, y = int(parts[0]), int(parts[1])
            draw_text(dr, x, y, ",".join(parts[2:]), font)
    img.save(sys.argv[2])
    print(f"annotated -> {sys.argv[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
