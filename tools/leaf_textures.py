"""Draws the foliage textures used on the tree leaf cards (RGBA, transparent background).

Run: python3 tools/leaf_textures.py models/trees
Writes leaf_broad.png (a cluster of rounded leaves) and leaf_pine.png (drooping needle sprigs).
Colours are light and fairly neutral greens: the game tints each tree (vertex colour x per-tree tint).
"""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "models/trees"
os.makedirs(OUT, exist_ok=True)
S = 512

def leaf(draw, cx, cy, length, width, angle, fill, vein):
    pts = []
    for k in range(25):
        t = k / 24.0
        r = math.sin(math.pi * t) ** 0.8 * width / 2
        pts.append((t * length, r))
    for k in range(24, -1, -1):
        t = k / 24.0
        r = math.sin(math.pi * t) ** 0.8 * width / 2
        pts.append((t * length, -r))
    ca, sa = math.cos(angle), math.sin(angle)
    poly = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]
    draw.polygon(poly, fill=fill)
    draw.line([(cx, cy), (cx + length * 0.9 * ca, cy + length * 0.9 * sa)], fill=vein, width=2)

def broad():
    rnd = random.Random(3)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S / 2
    # twigs
    for k in range(7):
        a = rnd.uniform(0, math.tau)
        d.line([(cx, cy), (cx + math.cos(a) * 180, cy + math.sin(a) * 180)], fill=(70, 52, 30, 255), width=4)
    # leaves, back to front: darker first, lighter on top
    for k in range(150):
        a = rnd.uniform(0, math.tau); r = 205 * math.sqrt(rnd.random())
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        if math.hypot(x - cx, y - cy) > 215: continue
        shade = k / 150.0
        g = int(120 + 90 * shade + rnd.uniform(-15, 15))
        fill = (int(g * 0.92), g, int(g * 0.95), 255)          # near neutral: the game tints each tree
        vein = (int(g * 0.72), int(g * 0.78), int(g * 0.76), 255)
        leaf(d, x, y, rnd.uniform(52, 80), rnd.uniform(28, 42), a + rnd.uniform(-0.9, 0.9), fill, vein)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(os.path.join(OUT, "leaf_broad.png"))

def pine():
    rnd = random.Random(5)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # overlapping drooping sprigs, each a stem with dense, irregular needle tufts
    for s in range(9):
        x0 = 40 + s * 54 + rnd.uniform(-15, 15)
        pts = [(x0 + math.sin(t * 2.4 + s) * 22, 6 + t * 480) for t in [i / 40 for i in range(41)]]
        d.line(pts, fill=(58, 42, 26, 255), width=4)
        for i, (px, py) in enumerate(pts[1:], 1):
            t = i / 40
            for k in range(7):
                side = -1 if k % 2 == 0 else 1
                ang = math.radians(rnd.uniform(35, 75))
                ln = rnd.uniform(28, 46) * (1 - t * 0.45)
                g = int(rnd.uniform(140, 215) * (1.0 - 0.18 * t))
                ex = px + side * math.sin(ang) * ln
                ey = py + math.cos(ang) * ln * 0.75
                d.line([(px, py), (ex, ey)], fill=(int(g * 0.9), g, int(g * 0.96), 255), width=5)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(os.path.join(OUT, "leaf_pine.png"))

broad(); pine()
print("leaf textures written to", OUT)
