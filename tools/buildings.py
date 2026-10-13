"""Bakes the woodcutter's lodge and the storehouse in the village house style (tools/house_variants.py):
thatched roofs, timber frames, plaster, stone plinths.

Run: python3 tools/buildings.py <models_dir> [preview]
Writes <models_dir>/woodcutter.glb and <models_dir>/storehouse.glb. Front (door / open side) = -Y (Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import house_variants as hv

OUT_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "models")
PREVIEW = "preview" in sys.argv

def mats(seed, thatch="golden", plaster=0, beam=0):
    return {
        "thatch": hv.mat_thatch(thatch), "thatch_dark": hv.mat_thatch(thatch, True),
        "plaster": hv.mat_plaster(hv.PLASTERS[plaster]),
        "beam": hv.mat_wood("beam", *hv.BEAMS[beam]),
        "plank": hv.mat_wood("plank", (0.07, 0.045, 0.025), (0.20, 0.13, 0.07)),
        "stone": hv.mat_stone(),
        "log": hv.mat_wood("log", (0.08, 0.05, 0.03), (0.25, 0.16, 0.08), (6, 6, 1)),
        "cut": hv.mat_wood("cut", (0.30, 0.20, 0.10), (0.55, 0.40, 0.22), (20, 20, 20)),
        "iron": hv.mat_flat("iron", (0.04, 0.04, 0.045), 0.45),
        "burlap": hv.mat_wood("burlap", (0.30, 0.22, 0.11), (0.52, 0.40, 0.22), (8, 8, 8)),
    }

def log(col, M, loc, length, r, axis="x", end_caps=True):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r, depth=length, location=loc, rotation=rot)
    o = bpy.context.object; o.data.materials.append(M["log"])
    bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    if end_caps:
        d = Vector({"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis])
        for s in (-1, 1):
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r * 0.9, depth=0.01, location=Vector(loc) + d * s * (length / 2 + 0.004), rotation=rot)
            c = bpy.context.object; c.data.materials.append(M["cut"])
            bpy.context.scene.collection.objects.unlink(c); col.objects.link(c)
    return o

def gables(col, M, rp, W, D, wall_top, B, t):
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.02); zt = rp(-1, W / 2 - 0.02, 1.0).z
        import bmesh
        bm = bmesh.new()
        a = bm.verts.new((x, -D / 2, wall_top)); b_ = bm.verts.new((x, D / 2, wall_top)); c = bm.verts.new((x, 0, zt))
        bm.faces.new((a, b_, c))
        g = hv.mesh_obj("gable", bm, M["plaster"], col); s = g.modifiers.new("s", "SOLIDIFY"); s.thickness = 0.12
        B((sx * (W / 2 + 0.03), 0, wall_top), (sx * (W / 2 + 0.03), 0, zt - 0.1), t * 0.85)

def woodcutter(col):
    """Open-fronted lodge: back and side walls, logs stacked inside, a log pile and chopping block behind."""
    seed = 31; rnd = random.Random(seed)
    M = mats(seed, "weathered", 1, 1)
    W, D, H = 3.4, 2.3, 1.85
    BASE = 0.18; wall_top = BASE + H
    hv.cube(col, (W + 0.15, D + 0.15, BASE), (0, 0, BASE / 2), M["plank"], bevel=0.02)
    for k in range(int(W / 0.4)):
        x = -W / 2 + 0.2 + k * 0.4
        hv.blob(col, (x, -D / 2 - 0.08, 0.06), 0.13, M["stone"], 2, 0.7, 0.3, seed + k).scale = (1.3, 1, 1)
    t = 0.15; kk = [0]
    def B(p0, p1, tt=t):
        kk[0] += 1; return hv.beam(col, p0, p1, tt, M["beam"], seed * 100 + kk[0])
    hx, hy = W / 2, D / 2
    # back wall (+Y) and left wall plaster with timber frame; right side and front open
    hv.cube(col, (W, 0.12, H), (0, hy, BASE + H / 2), M["plaster"], bevel=0.02, wobble=0.02, seed=seed)
    hv.cube(col, (0.12, D, H), (-hx, 0, BASE + H / 2), M["plaster"], bevel=0.02, wobble=0.02, seed=seed + 1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            B((sx * hx, sy * hy, BASE), (sx * hx, sy * hy, wall_top + 0.05))
    B((0.15, -hy, BASE), (0.15, -hy, wall_top))
    for sy in (-1, 1):
        B((-hx - 0.2, sy * hy, wall_top), (hx + 0.2, sy * hy, wall_top), t * 1.1)
    for sx in (-1, 1):
        B((sx * hx, -hy - 0.2, wall_top), (sx * hx, hy + 0.2, wall_top), t * 1.1)
    B((-hx, hy + 0.01, BASE + 1.0), (hx, hy + 0.01, BASE + 1.0), t * 0.7)
    B((-hx, hy + 0.01, BASE + 0.1), (0, hy + 0.01, wall_top - 0.05), t * 0.7)
    B((-hx - 0.01, -hy, BASE + 1.0), (-hx - 0.01, hy, BASE + 1.0), t * 0.7)
    # knee braces on the open front
    for x in (-hx, 0.15, hx):
        for s in ((-1, 1) if x == 0.15 else ((1,) if x < 0 else (-1,))):
            B((x, -hy, wall_top - 0.45), (x + s * 0.45, -hy, wall_top - 0.02), t * 0.6)
    rp = hv.thatch_roof(col, M, -W / 2, W / 2, D, wall_top - 0.35, 1.55, 0.55, 0.6, True, seed, sag=0.07)
    gables(col, M, rp, W, D, wall_top, B, t)
    # firewood stacked against the back wall inside
    for row in range(4):
        for k in range(9 - row):
            log(col, M, (-hx + 0.35 + (k + row * 0.5) * 0.3, hy - 0.42, BASE + 0.14 + row * 0.25), 0.7, 0.13, "y")
    # sawhorse with a log
    for x in (0.9, 1.5):
        B((x, -0.45, BASE), (x, -0.15, BASE + 0.65), 0.07); B((x, 0.15, BASE), (x, -0.15, BASE + 0.65), 0.07)
    log(col, M, (1.2, -0.15, BASE + 0.8), 1.3, 0.14, "x")
    # outside, behind: log pile and chopping block with an axe
    for row in range(3):
        for k in range(5 - row):
            log(col, M, (-0.9 + (k + row * 0.5) * 0.36, hy + 0.75, 0.18 + row * 0.3), 1.4, 0.17, "x")
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.32, depth=0.5, location=(1.35, hy + 0.75, 0.25))
    o = bpy.context.object; o.data.materials.append(M["log"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.3, depth=0.01, location=(1.35, hy + 0.75, 0.505))
    o = bpy.context.object; o.data.materials.append(M["cut"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    B((1.35, hy + 0.75, 0.5), (1.6, hy + 0.55, 1.15), 0.05)
    hv.cube(col, (0.06, 0.24, 0.18), (1.35, hy + 0.75, 0.6), M["iron"], rot=(0.5, 0, 0.3), bevel=0.01)
    for k in range(4):
        a = rnd.uniform(0, math.tau)
        hv.cube(col, (0.22, 0.08, 0.06), (1.35 + math.cos(a) * 0.55, hy + 0.75 + math.sin(a) * 0.45, 0.03), M["cut"], rot=(0, 0, a), bevel=0.01)
    return W + 1.1, D + 2.0

def storehouse(col):
    """Barn on a stone plinth, open front with a wide doorway, goods stacked inside."""
    seed = 47; rnd = random.Random(seed)
    M = mats(seed, "golden", 4, 0)
    W, D, H = 4.4, 3.4, 2.15
    BASE = 0.3; wall_top = BASE + H
    hv.cube(col, (W + 0.25, D + 0.25, BASE), (0, 0, BASE / 2), M["stone"], bevel=0.05)
    i = 0
    for side in range(4):
        L = W + 0.35 if side % 2 == 0 else D + 0.35
        n = int(L / 0.45)
        for k in range(n):
            f = (k + 0.5) / n - 0.5
            p = [(f * L, -(D + 0.35) / 2), ((W + 0.35) / 2, f * L), (-f * L, (D + 0.35) / 2), (-(W + 0.35) / 2, -f * L)][side]
            s = rnd.uniform(0.17, 0.24)
            hv.blob(col, (p[0], p[1], s * 0.75), s, M["stone"], 2, 0.75, 0.3, seed * 50 + i).scale = (1.3, 1.1, 1.0)
            i += 1
    t = 0.17; kk = [0]
    def B(p0, p1, tt=t):
        kk[0] += 1; return hv.beam(col, p0, p1, tt, M["beam"], seed * 100 + kk[0])
    hx, hy = W / 2, D / 2
    hv.cube(col, (W, 0.12, H), (0, hy, BASE + H / 2), M["plaster"], bevel=0.02, wobble=0.02, seed=seed)
    for sx in (-1, 1):
        hv.cube(col, (0.12, D, H), (sx * hx, 0, BASE + H / 2), M["plaster"], bevel=0.02, wobble=0.02, seed=seed + sx)
    # front: plaster either side of a wide open doorway
    door = 2.3
    for sx in (-1, 1):
        w_ = (W - door) / 2
        hv.cube(col, (w_, 0.12, H), (sx * (door / 2 + w_ / 2), -hy, BASE + H / 2), M["plaster"], bevel=0.02, wobble=0.02, seed=seed + 5 + sx)
    hv.cube(col, (door, 0.12, 0.45), (0, -hy, wall_top - 0.22), M["plaster"], bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            B((sx * (hx + 0.03), sy * (hy + 0.03), BASE), (sx * (hx + 0.03), sy * (hy + 0.03), wall_top + 0.05))
        B((sx * door / 2, -hy - 0.03, BASE), (sx * door / 2, -hy - 0.03, wall_top), t)
        B((sx * (hx + 0.04), -hy - 0.2, wall_top), (sx * (hx + 0.04), hy + 0.2, wall_top), t * 1.1)
        B((sx * (hx + 0.04), -hy, BASE + 1.1), (sx * (hx + 0.04), hy, BASE + 1.1), t * 0.7)
        B((sx * (hx + 0.04), 0, BASE), (sx * (hx + 0.04), 0, wall_top), t * 0.8)
    for sy in (-1, 1):
        B((-hx - 0.25, sy * (hy + 0.03), wall_top), (hx + 0.25, sy * (hy + 0.03), wall_top), t * 1.1)
    B((-door / 2 - 0.1, -hy - 0.04, wall_top - 0.45), (door / 2 + 0.1, -hy - 0.04, wall_top - 0.45), t)
    for x in (-hx * 0.5, hx * 0.5):
        B((x, hy + 0.04, BASE), (x, hy + 0.04, wall_top), t * 0.8)
    B((-hx, hy + 0.04, BASE + 1.1), (hx, hy + 0.04, BASE + 1.1), t * 0.7)
    rp = hv.thatch_roof(col, M, -W / 2, W / 2, D, wall_top - 0.4, 2.1, 0.7, 0.7, True, seed, sag=0.1)
    gables(col, M, rp, W, D, wall_top, B, t)
    # goods inside: crates, barrels, sacks, a log stack
    for k in range(3):
        hv.cube(col, (0.55, 0.5, 0.48), (-1.45 + k * 0.6, hy - 0.45, BASE + 0.24), M["plank"], rot=(0, 0, rnd.uniform(-0.1, 0.1)), bevel=0.03)
    hv.cube(col, (0.52, 0.48, 0.46), (-1.15, hy - 0.45, BASE + 0.71), M["plank"], rot=(0, 0, 0.25), bevel=0.03)
    for k in range(2):
        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.27, depth=0.7, location=(1.3 + k * 0.6, hy - 0.5, BASE + 0.35))
        o = bpy.context.object; o.data.materials.append(M["plank"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
        for z in (0.12, 0.58):
            bpy.ops.mesh.primitive_torus_add(major_radius=0.275, minor_radius=0.02, location=(1.3 + k * 0.6, hy - 0.5, BASE + z))
            o = bpy.context.object; o.data.materials.append(M["iron"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    for k in range(4):
        o = hv.blob(col, (-1.6 + k * 0.38, 0.1 + (k % 2) * 0.15, BASE + 0.26), 0.25, M["burlap"], 2, 1.2, 0.18, seed + 70 + k)
        o.scale = (0.85, 0.75, 1.0)
    for row in range(3):
        for k in range(4 - row):
            log(col, M, (0.9 + (k + row * 0.5) * 0.3, 0.2, BASE + 0.15 + row * 0.26), 0.9, 0.13, "y")
    # sign by the door
    B((door / 2 + 0.45, -hy - 0.45, 0), (door / 2 + 0.45, -hy - 0.45, 1.3), 0.08)
    hv.cube(col, (0.6, 0.06, 0.36), (door / 2 + 0.45, -hy - 0.5, 1.2), M["plank"], bevel=0.02)
    return W + 1.6, D + 1.6

if __name__ == "__main__":
    for name, fn, fit_w, fit_d in [("woodcutter", woodcutter, 2.9, 2.9), ("storehouse", storehouse, 3.6, 3.0)]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        col = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(col)
        sx, sy = fn(col)
        hv.finish(col, name, sx, sy, fit_w=fit_w, fit_d=fit_d, out_dir=OUT_DIR)
        if PREVIEW:
            hv.render_preview(os.path.join(OUT_DIR, f"_{name}_preview.png"))
