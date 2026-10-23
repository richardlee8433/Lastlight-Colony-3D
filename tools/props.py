"""Bakes small props that make the village look lived-in, in the house style (tools/house_variants.py).

Run: python3 tools/props.py <models_dir> [name ...]
Writes <models_dir>/props/<name>.glb at game scale (1 unit = 1 m), origin at the base centre,
front = -Y (Godot +Z). The game places them around finished buildings (scripts/world/clutter.gd).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import house_variants as hv

OUT_DIR = os.path.abspath(os.path.join(sys.argv[1] if len(sys.argv) > 1 else "models", "props"))
ONLY = sys.argv[2:]
os.makedirs(OUT_DIR, exist_ok=True)

def M_():
    return {
        "plank": hv.mat_wood("plank", (0.09, 0.06, 0.035), (0.24, 0.16, 0.09)),
        "dark": hv.mat_wood("darkwood", (0.05, 0.035, 0.02), (0.14, 0.09, 0.05)),
        "log": hv.mat_wood("log", (0.08, 0.05, 0.03), (0.25, 0.16, 0.08), (6, 6, 1)),
        "cut": hv.mat_wood("cut", (0.30, 0.20, 0.10), (0.55, 0.40, 0.22), (20, 20, 20)),
        "iron": hv.mat_flat("iron", (0.04, 0.04, 0.045), 0.45),
        "burlap": hv.mat_wood("burlap", (0.30, 0.22, 0.11), (0.52, 0.40, 0.22), (8, 8, 8)),
        "hay": hv.mat_thatch("golden"),
        "soil": hv.mat_wood("soil", (0.10, 0.06, 0.03), (0.22, 0.14, 0.08), (6, 6, 6)),
        "leaf": hv.mat_flat("leaf", (0.10, 0.30, 0.05)),
        "leaf2": hv.mat_flat("leaf2", (0.25, 0.42, 0.10)),
        "rope": hv.mat_flat("rope", (0.45, 0.36, 0.2), 0.9),
        "stone": hv.mat_stone(),
    }

def cyl(col, r, h, loc, m, rot=(0, 0, 0), v=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=v, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.object; o.data.materials.append(m)
    bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    return o

def crate(col, M, loc=(0, 0, 0), s=0.5, rot=0.0):
    x, y, z = loc
    hv.cube(col, (s, s, s), (x, y, z + s / 2), M["plank"], rot=(0, 0, rot), bevel=0.02)
    for dz in (0.06, s - 0.06):
        hv.cube(col, (s + 0.02, s + 0.02, 0.06), (x, y, z + dz), M["dark"], rot=(0, 0, rot), bevel=0.01)

def barrel(col, M, loc=(0, 0, 0)):
    x, y, z = loc
    cyl(col, 0.26, 0.72, (x, y, z + 0.36), M["plank"], v=14)
    for dz in (0.12, 0.6):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.265, minor_radius=0.018, location=(x, y, z + dz))
        o = bpy.context.object; o.data.materials.append(M["iron"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    cyl(col, 0.24, 0.02, (x, y, z + 0.725), M["dark"], v=14)

def sack(col, M, loc, seed):
    o = hv.blob(col, (loc[0], loc[1], loc[2] + 0.24), 0.25, M["burlap"], 2, 1.2, 0.18, seed)
    o.scale = (0.85, 0.72, 1.0)
    hv.cube(col, (0.14, 0.14, 0.05), (loc[0], loc[1], loc[2] + 0.5), M["burlap"], bevel=0.02)

def build(name, col, M):
    rnd = random.Random(hash(name) & 0xffff)
    if name == "crate":
        crate(col, M)
    elif name == "crates":
        crate(col, M, (-0.28, 0, 0), 0.5, 0.1); crate(col, M, (0.3, 0.05, 0), 0.48, -0.15); crate(col, M, (0.0, 0.0, 0.5), 0.46, 0.35)
    elif name == "barrels":
        barrel(col, M, (-0.3, 0, 0)); barrel(col, M, (0.3, 0.1, 0))
    elif name == "barrel":
        barrel(col, M)
    elif name == "sacks":
        for i, (x, y, z) in enumerate([(-0.3, 0, 0), (0.05, 0.05, 0), (0.38, -0.02, 0), (-0.12, 0.02, 0.38)]):
            sack(col, M, (x, y, z), 50 + i)
    elif name == "firewood":
        for row in range(3):
            for k in range(6 - row):
                o = cyl(col, 0.09, 0.55, (-0.5 + (k + row * 0.5) * 0.19, 0, 0.09 + row * 0.16), M["log"], rot=(math.pi / 2, 0, 0), v=8)
                cyl(col, 0.085, 0.01, (-0.5 + (k + row * 0.5) * 0.19, -0.28, 0.09 + row * 0.16), M["cut"], rot=(math.pi / 2, 0, 0), v=8)
        for x in (-0.65, 0.65):
            hv.beam(col, (x, 0, 0), (x, 0, 0.6), 0.06, M["dark"], 3)
    elif name == "fence":
        for x in (-1.0, 0.0, 1.0):
            hv.beam(col, (x, 0, 0), (x + rnd.uniform(-0.03, 0.03), 0, 0.85), 0.09, M["dark"], int(x * 10) + 5)
        for z in (0.35, 0.68):
            hv.beam(col, (-1.05, 0, z + rnd.uniform(-0.03, 0.03)), (1.05, 0, z + rnd.uniform(-0.03, 0.03)), 0.06, M["plank"], int(z * 100))
    elif name == "laundry":
        for x in (-1.2, 1.2):
            hv.beam(col, (x, 0, 0), (x, 0, 1.6), 0.08, M["dark"], 7)
            hv.beam(col, (x - 0.15, 0, 1.45), (x + 0.15, 0, 1.6), 0.05, M["dark"], 8)
        hv.beam(col, (-1.2, 0, 1.52), (1.2, 0, 1.47), 0.015, M["rope"], 9)
        cloths = [(0.85, 0.82, 0.72), (0.55, 0.62, 0.78), (0.82, 0.55, 0.45), (0.9, 0.88, 0.8)]
        for i, x in enumerate([-0.75, -0.2, 0.3, 0.8]):
            c = hv.mat_flat(f"cloth{i}", cloths[i], 0.95)
            w = rnd.uniform(0.35, 0.55); h = rnd.uniform(0.45, 0.75)
            hv.cube(col, (w, 0.02, h), (x, 0, 1.49 - h / 2), c, rot=(rnd.uniform(-0.1, 0.1), 0, rnd.uniform(-0.05, 0.05)), bevel=0.005, wobble=0.01, seed=i)
    elif name == "garden":
        hv.cube(col, (1.7, 1.0, 0.18), (0, 0, 0.09), M["soil"], bevel=0.02, wobble=0.01, seed=3)
        for sx in (-1, 1):
            hv.cube(col, (1.8, 0.06, 0.22), (0, sx * 0.53, 0.11), M["plank"], bevel=0.01)
            hv.cube(col, (0.06, 1.1, 0.22), (sx * 0.88, 0, 0.11), M["plank"], bevel=0.01)
        for row in range(2):
            for k in range(5):
                x = -0.62 + k * 0.31; y = -0.22 + row * 0.44
                if row == 0:
                    o = hv.blob(col, (x, y, 0.27), 0.13, M["leaf2"], 2, 0.8, 0.35, 70 + k)
                else:
                    for j in range(3):
                        hv.beam(col, (x + (j - 1) * 0.05, y, 0.18), (x + (j - 1) * 0.08, y, 0.45), 0.025, M["leaf"], 80 + k * 3 + j)
    elif name == "bench":
        hv.cube(col, (1.1, 0.32, 0.06), (0, 0, 0.42), M["plank"], bevel=0.01)
        for x in (-0.42, 0.42):
            hv.cube(col, (0.08, 0.28, 0.4), (x, 0, 0.2), M["dark"], bevel=0.01)
    elif name == "flowerbox":
        hv.cube(col, (0.7, 0.28, 0.24), (0, 0, 0.12), M["plank"], bevel=0.015)
        petals = [hv.mat_flat("pA", (0.75, 0.18, 0.15)), hv.mat_flat("pB", (0.9, 0.75, 0.2)), hv.mat_flat("pC", (0.55, 0.3, 0.7))]
        for k in range(7):
            x = -0.27 + k * 0.09
            hv.blob(col, (x, rnd.uniform(-0.05, 0.05), 0.3), 0.07, M["leaf"], 1, 0.8, 0.3, 90 + k)
            hv.blob(col, (x, rnd.uniform(-0.05, 0.05), 0.37), 0.045, petals[k % 3], 1, 0.9, 0.2, 100 + k)
    elif name == "haybales":
        for i, (x, y, z, r) in enumerate([(-0.4, 0, 0, 0.1), (0.42, 0.05, 0, -0.08), (0.0, 0.0, 0.42, 0.3)]):
            hv.cube(col, (0.75, 0.48, 0.42), (x, y, z + 0.21), M["hay"], rot=(0, 0, r), bevel=0.07, wobble=0.02, seed=i)
            hv.cube(col, (0.02, 0.5, 0.44), (x - 0.18, y, z + 0.21), M["rope"], rot=(0, 0, r))
            hv.cube(col, (0.02, 0.5, 0.44), (x + 0.18, y, z + 0.21), M["rope"], rot=(0, 0, r))
    elif name == "wheelbarrow":
        hv.cube(col, (0.55, 0.75, 0.25), (0, 0.05, 0.42), M["plank"], rot=(0.12, 0, 0), bevel=0.02)
        cyl(col, 0.17, 0.06, (0, -0.42, 0.17), M["dark"], rot=(0, math.pi / 2, 0), v=12)
        for x in (-0.22, 0.22):
            hv.beam(col, (x, -0.35, 0.2), (x, 0.85, 0.48), 0.04, M["dark"], 11)
            hv.beam(col, (x, 0.35, 0.3), (x, 0.35, 0.0), 0.04, M["dark"], 12)
        for k in range(3):
            hv.blob(col, (rnd.uniform(-0.15, 0.15), rnd.uniform(-0.1, 0.25), 0.58), 0.12, M["stone"], 1, 0.8, 0.3, 120 + k)
    elif name == "bucket":
        cyl(col, 0.15, 0.26, (0, 0, 0.13), M["plank"], v=12)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.153, minor_radius=0.012, location=(0, 0, 0.2))
        o = bpy.context.object; o.data.materials.append(M["iron"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
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
    M = M_()
    sx, sy = build(name, col, M)
    hv.TEX = 512
    hv.finish(col, name, sx, sy, fit_w=sx, fit_d=sy, out_dir=OUT_DIR)
