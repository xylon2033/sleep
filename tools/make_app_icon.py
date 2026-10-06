#!/usr/bin/env python3
"""Draws the 1024×1024 app icon (night-sky gradient, crescent moon, a few stars). Needs Pillow."""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S))
top, bottom = (24, 20, 64), (70, 52, 160)
draw = ImageDraw.Draw(img)
for y in range(S):
    t = y / (S - 1)
    draw.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))

random.seed(4)
for _ in range(40):
    x, y, r = random.randint(40, S - 40), random.randint(40, int(S * 0.75)), random.choice([2, 3, 3, 4, 5])
    draw.ellipse([x - r, y - r, x + r, y + r], fill=(235, 232, 255))

moon = Image.new("L", (S, S), 0)
m = ImageDraw.Draw(moon)
cx, cy, r = 520, 500, 280
m.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
m.ellipse([cx - r + 150, cy - r - 80, cx + r + 150, cy + r - 80], fill=0)
glow = moon.filter(ImageFilter.GaussianBlur(40))
img.paste(Image.new("RGB", (S, S), (150, 140, 255)), (0, 0), glow.point(lambda v: v // 3))
img.paste(Image.new("RGB", (S, S), (255, 236, 190)), (0, 0), moon)

out = os.path.join(os.path.dirname(__file__), "..", "Sleep", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
img.save(out)
print("wrote", os.path.normpath(out))
