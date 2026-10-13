"""Bakes the farmhouse in the same style as the village houses (tools/house_variants.py):
a small thatched cottage with a hay shed on the side, grain sacks and a pitchfork by the door.

Run: python3 tools/farmhouse.py <models_dir> [preview]
Writes <models_dir>/farmhouse.glb, sized for the 3 m farmhouse footprint, door = -Y (Godot +Z, facing the field).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import house_variants as hv

OUT_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "models")
PREVIEW = "preview" in sys.argv

PRESET = dict(W=3.5, D=2.8, H=1.8, rise=2.0, thatch="golden", plaster=3, beam=0, chimney=0, door_x=0.4,
              windows=[-0.85], side_window=False, lean_to=1, hay=True, braces=True, flowers=0, barrel=False, sag=0.09)

def extras(p, col):
    rnd = random.Random(p["seed"] + 5)
    W, D = p["W"], p["D"]; hy = D / 2 + 0.03; dx = p["door_x"]
    burlap = hv.mat_wood("burlap", (0.30, 0.22, 0.11), (0.52, 0.40, 0.22), (8, 8, 8))
    handle = hv.mat_wood("handle", (0.10, 0.06, 0.03), (0.26, 0.17, 0.09))
    iron = hv.mat_flat("iron2", (0.05, 0.05, 0.05), 0.45)
    # grain sacks by the door
    spots = [(-0.55, -0.45, 0.0), (-0.95, -0.4, 0.0), (-0.75, -0.48, 0.42)]
    for i, (ox, oy, oz) in enumerate(spots):
        o = hv.blob(col, (dx - 0.35 + ox, -hy + oy, 0.24 + oz), 0.27, burlap, 2, 1.25, 0.18, p["seed"] + 40 + i)
        o.scale = (0.85, 0.75, 1.0); o.rotation_euler.z = rnd.uniform(-0.5, 0.5)
        hv.cube(col, (0.16, 0.16, 0.05), (dx - 0.35 + ox, -hy + oy, 0.52 + oz), burlap, bevel=0.02)
    # pitchfork leaning on the wall next to the door
    x = dx + 0.75
    hv.beam(col, (x, -hy - 0.55, 0.0), (x + 0.12, -hy - 0.06, 1.75), 0.06, handle, p["seed"] + 60)
    for k in range(3):
        hv.beam(col, (x - 0.02 + (k - 1) * 0.07, -hy - 0.62, -0.25), (x - 0.01 + (k - 1) * 0.06, -hy - 0.5, 0.15), 0.025, iron, p["seed"] + 61 + k)
    # a little fenced corner with a water trough on the other side
    s = -1
    for k in range(3):
        hv.beam(col, (s * (W / 2 + 0.35), -D / 2 + k * D / 2, 0), (s * (W / 2 + 0.35), -D / 2 + k * D / 2, 0.75), 0.09, handle, p["seed"] + 70 + k)
    for z in (0.35, 0.65):
        hv.beam(col, (s * (W / 2 + 0.35), -D / 2 - 0.05, z), (s * (W / 2 + 0.35), D / 2 + 0.05, z), 0.06, handle, p["seed"] + 80 + int(z * 10))
    hv.cube(col, (0.4, 1.0, 0.3), (s * (W / 2 + 0.05), -0.2, 0.15), hv.mat_wood("trough", (0.07, 0.045, 0.025), (0.20, 0.13, 0.07)), bevel=0.03)
    return 0.45   # extra width on the fence side

if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    p = hv.variant(PRESET, 777)
    col = bpy.data.collections.new("Farmhouse"); bpy.context.scene.collection.children.link(col)
    size_x, size_y = hv.build_house(p, col)
    size_x += extras(p, col)
    hv.finish(col, "farmhouse", size_x, size_y + 0.3, fit_w=2.85, fit_d=2.0, out_dir=OUT_DIR)
    if PREVIEW:
        hv.render_preview(os.path.join(OUT_DIR, "farmhouse.png"))
