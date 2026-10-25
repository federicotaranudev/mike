#!/usr/bin/env python3
"""Pixel-verify the keyboard dismissal screenshots.

Compares the bottom region (where the software keyboard lives) of each
capture against the keyboard-closed baseline kb0-closed.png.
PASS criteria:
  kb1-open / kb3-reopened differ strongly from baseline (keyboard up)
  kb2-tap-dismissed / kb4-drag-dismissed are close to baseline (keyboard down)
"""
import sys
from PIL import Image, ImageChops

def bottom_mean_diff(a, b):
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB").resize(ia.size)
    w, h = ia.size
    box = (0, int(h * 0.60), w, h)
    d = ImageChops.difference(ia.crop(box), ib.crop(box))
    data = list(d.getdata())[::53]  # sample
    return sum(sum(p) for p in data) / (len(data) * 3)

def main(d):
    base = f"{d}/kb0-closed.png"
    opened = bottom_mean_diff(base, f"{d}/kb1-open.png")
    tap = bottom_mean_diff(base, f"{d}/kb2-tap-dismissed.png")
    reopened = bottom_mean_diff(base, f"{d}/kb3-reopened.png")
    drag = bottom_mean_diff(base, f"{d}/kb4-drag-dismissed.png")
    print(f"diffs vs closed baseline: open={opened:.2f} tap={tap:.2f} reopened={reopened:.2f} drag={drag:.2f}")
    ok = True
    def check(name, cond):
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name)
        ok = ok and cond
    check("keyboard opened on composer tap", opened > 4)
    check("tap-outside dismissed keyboard", tap < max(3, opened * 0.35))
    check("keyboard reopened on second tap", reopened > 4)
    check("drag-down dismissed keyboard", drag < max(3, reopened * 0.35))
    print("KEYBOARD-UITEST " + ("ALL PASS" if ok else "FAILED"))
    sys.exit(0 if ok else 1)

main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/kbshots")
