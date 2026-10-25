"""Small colony props, replacing the village ones under the same names (scripts/world/clutter.gd places them).

Run: python3 tools/scifi_props.py <models_dir> [name ...]
Writes <models_dir>/props/<name>.glb at game scale, origin at the base centre, front = -Y (Godot +Z).
  crate / crates     sealed cargo cases          barrel / barrels   gas cylinders / drums
  sacks              regolith sandbags           firewood           stacked fibre bales
  fence              marker posts with cable     laundry            weather / comm mast
  garden             hydroponic planter          bench              metal bench
  flowerbox          small planter of alien plants   haybales       big fibre bales
  wheelbarrow        hand trolley                bucket             sample canister
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import house_variants as hv
import scifi_buildings as sb
import scifi as sf

OUT_DIR = os.path.abspath(os.path.join(sys.argv[1] if len(sys.argv) > 1 else "models", "props"))
ONLY = sys.argv[2:]
os.makedirs(OUT_DIR, exist_ok=True)

def case(col, M, loc=(0, 0, 0), s=0.5, rot=0.0):
    sf.crate(col, M, loc, s, rot)

def cylinder_tank(col, M, loc, m, r=0.16, h=0.75):
    x, y, z = loc
    sb.tube(col, r, (x, y, z), (x, y, z + h), m, 16)
    sf.sphere(col, r, (x, y, z + h), m, (1, 1, 0.45), 16)
    sb.tube(col, 0.04, (x, y, z + h + 0.05), (x, y, z + h + 0.14), M["metal"], 8)
    sb.tube(col, r * 1.03, (x, y, z + h * 0.7), (x, y, z + h * 0.76), M["dark"], 16)

def build(name, col, M):
    rnd = random.Random(hash(name) & 0xffff)
    if name == "crate":
        case(col, M)
    elif name == "crates":
        case(col, M, (-0.28, 0, 0), 0.5, 0.1); case(col, M, (0.3, 0.05, 0), 0.48, -0.15); case(col, M, (0.0, 0.0, 0.36), 0.46, 0.35)
    elif name == "barrels":
        cylinder_tank(col, M, (-0.22, 0, 0), M["accent"]); cylinder_tank(col, M, (0.2, 0.08, 0), M["foil2"])
        cylinder_tank(col, M, (0.0, -0.22, 0), M["hull"], 0.14, 0.65)
    elif name == "barrel":
        cylinder_tank(col, M, (0, 0, 0), M["accent"], 0.2, 0.7)
    elif name == "sacks":
        sb.sandbags(col, M, [(-0.3, 0, 0), (0.05, 0.05, 0), (0.38, -0.02, 0), (-0.12, 0.02, 0.2), (0.22, 0.03, 0.2)], 50, 0.17)
    elif name == "firewood":
        for row in range(2):
            for k in range(3 - row):
                sb.bale(col, M, (-0.42 + k * 0.42 + row * 0.21, 0, row * 0.3), 0.0, (0.4, 0.34, 0.3))
    elif name == "fence":
        for x in (-1.0, 0.0, 1.0):
            sb.tube(col, 0.03, (x, 0, 0), (x, 0, 0.8), M["metal"], 8)
            hv.cube(col, (0.07, 0.07, 0.07), (x, 0, 0.82), M["accent"], bevel=0.01)
            hv.cube(col, (0.07, 0.04, 0.12), (x, 0, 0.6), M["hazard"], bevel=0.005)
        hv.beam(col, (-1.0, 0, 0.7), (1.0, 0, 0.7), 0.012, M["rubber"], 1)
    elif name == "laundry":
        # weather mast: lattice pole, anemometer cups, a small dish, a sensor box
        sb.lattice(col, M, (0.0, 0.0), 1.7, 0.08, 4, M["metal"], 0.025)
        hv.cube(col, (0.22, 0.16, 0.25), (0.0, -0.12, 0.45), M["hull_dark"], bevel=0.02)
        hv.cube(col, (0.12, 0.02, 0.06), (0.0, -0.205, 0.5), M["light"], bevel=0.005)
        for k in range(3):
            a = k * math.tau / 3
            hv.beam(col, (0, 0, 1.75), (math.cos(a) * 0.15, math.sin(a) * 0.15, 1.75), 0.012, M["metal"], 2)
            sf.sphere(col, 0.035, (math.cos(a) * 0.15, math.sin(a) * 0.15, 1.75), M["hull"], (1, 1, 1), 8)
        d = sf.sphere(col, 0.18, (0.12, -0.05, 1.35), M["hull"], (1, 1, 0.3), 16); d.rotation_euler = (1.0, 0, 0.4)
        for sx in (-1, 1):
            hv.beam(col, (0, 0, 1.2), (sx * 0.7, 0.2, 0), 0.008, M["rubber"], 3)
    elif name == "garden":
        hv.cube(col, (1.7, 1.0, 0.3), (0, 0, 0.15), M["hull"], bevel=0.03)
        hv.cube(col, (1.6, 0.9, 0.04), (0, 0, 0.29), M["interior"], bevel=0.0)
        for row in range(2):
            for k in range(5):
                x = -0.62 + k * 0.31; y = -0.22 + row * 0.44
                hv.blob(col, (x, y, 0.38), 0.12, M["plant"] if (k + row) % 2 else M["plant2"], 2, 0.8, 0.35, 70 + k + row * 5)
        for sx in (-1, 1):
            sb.tube(col, 0.02, (sx * 0.82, 0, 0.3), (sx * 0.82, 0, 0.8), M["metal"], 8)
        hv.cube(col, (1.7, 0.12, 0.04), (0, 0, 0.82), M["light"], bevel=0.01)
        hv.cube(col, (1.75, 0.16, 0.03), (0, 0, 0.85), M["hull_dark"], bevel=0.005)
    elif name == "bench":
        hv.cube(col, (1.1, 0.34, 0.05), (0, 0, 0.42), M["grating"], bevel=0.008)
        for x in (-0.42, 0.42):
            hv.cube(col, (0.06, 0.3, 0.4), (x, 0, 0.2), M["hull_dark"], bevel=0.01)
    elif name == "flowerbox":
        hv.cube(col, (0.7, 0.3, 0.24), (0, 0, 0.12), M["hull_dark"], bevel=0.02)
        for k in range(7):
            x = -0.27 + k * 0.09
            hv.blob(col, (x, rnd.uniform(-0.05, 0.05), 0.3), 0.07, M["plant"], 1, 0.8, 0.3, 90 + k)
            hv.blob(col, (x, rnd.uniform(-0.05, 0.05), 0.37), 0.04, [M["plant2"], M["light"], M["accent"]][k % 3], 1, 0.9, 0.2, 100 + k)
    elif name == "haybales":
        for i, (x, y, z, r) in enumerate([(-0.4, 0, 0, 0.1), (0.42, 0.05, 0, -0.08), (0.0, 0.0, 0.42, 0.3)]):
            sb.bale(col, M, (x, y, z), r, (0.75, 0.48, 0.42))
    elif name == "wheelbarrow":
        hv.cube(col, (0.5, 0.7, 0.05), (0, 0, 0.18), M["hull_dark"], bevel=0.01)
        for sx in (-1, 1):
            for sy in (-1, 1):
                sb.tube(col, 0.07, (sx * 0.2, sy * 0.25, 0.08), (sx * 0.26, sy * 0.25, 0.08), M["rubber"], 12)
        hv.beam(col, (-0.2, 0.33, 0.18), (-0.2, 0.42, 0.95), 0.03, M["metal"], 4)
        hv.beam(col, (0.2, 0.33, 0.18), (0.2, 0.42, 0.95), 0.03, M["metal"], 4)
        hv.beam(col, (-0.22, 0.42, 0.95), (0.22, 0.42, 0.95), 0.035, M["accent"], 5)
        case(col, M, (0.0, -0.02, 0.2), 0.4, 0.05)
    elif name == "bucket":
        sb.tube(col, 0.1, (0, 0, 0), (0, 0, 0.3), M["hull"], 14)
        sb.tube(col, 0.105, (0, 0, 0.26), (0, 0, 0.32), M["accent"], 14)
        sb.tube(col, 0.105, (0, 0, 0.08), (0, 0, 0.11), M["dark"], 14)
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in col.objects if o.type == "MESH"]
    mn = Vector((1e9, 1e9, 1e9)); mx = -mn
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c); mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    return max(0.01, mx.x - mn.x), max(0.01, mx.y - mn.y)

NAMES = ["crate", "crates", "barrel", "barrels", "sacks", "firewood", "fence", "laundry", "garden", "bench",
         "flowerbox", "haybales", "wheelbarrow", "bucket"]
for name in NAMES:
    if ONLY and name not in ONLY: continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    col = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(col)
    M = sb.mats_all(sb.ACCENTS[NAMES.index(name) % len(sb.ACCENTS)])
    sx, sy = build(name, col, M)
    hv.TEX = 512
    sf.weather(col, 0.9)
    hv.finish(col, name, sx, sy, fit_w=sx, fit_d=sy, out_dir=OUT_DIR)
