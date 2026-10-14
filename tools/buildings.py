"""Bakes the woodcutter's lodge and the storehouse in the village house style (tools/house_variants.py):
thatched roofs, timber frames, plaster, stone plinths.

Run: python3 tools/buildings.py <models_dir> [preview]
Writes <models_dir>/{woodcutter, storehouse, quarry, deposit_0, deposit_1}.glb (add names to build only those). Front (door / open side) = -Y (Godot +Z).
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

def deposit(col, variant):
    """Stone outcrop: big angular boulders with fresh pale cut faces and rubble, ~2.6 m across.
    Built at game scale (1 unit = 1 m), centred on the origin."""
    seed = 900 + variant * 37; rnd = random.Random(seed)
    stone = hv.mat_stone()
    pale = hv.mat_wood("palestone", (0.36, 0.35, 0.33), (0.58, 0.57, 0.53), (14, 14, 14))
    # layered boulders: (x, y, radius, height)
    if variant == 0:
        big = [(0.0, 0.1, 0.85, 1.35), (-0.75, 0.45, 0.6, 0.95), (0.7, 0.5, 0.62, 0.9), (0.45, -0.45, 0.5, 0.7),
               (-0.6, -0.35, 0.48, 0.6), (0.05, 0.85, 0.5, 0.7), (1.05, -0.05, 0.4, 0.5)]
    else:
        big = [(0.1, 0.05, 0.8, 1.2), (-0.65, -0.3, 0.55, 0.8), (0.65, 0.45, 0.58, 0.85), (-0.45, 0.6, 0.48, 0.65),
               (0.75, -0.45, 0.4, 0.5)]
    for k, (x, y, r, h) in enumerate(big):
        o = hv.blob(col, (x, y, h * 0.4), r, stone, 2, h / r * 0.55, 0.5, seed + k)
        o.scale = (rnd.uniform(1.0, 1.25), rnd.uniform(0.9, 1.15), 1.0)
        o.rotation_euler = (rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25), rnd.uniform(0, 3))
    # stepped quarry face on the front (-Y): pale, freshly cut ledges
    for k in range(3):
        w_ = 1.2 - k * 0.25
        hv.cube(col, (w_, 0.42, 0.26), (0.0, -0.62 + k * 0.22, 0.13 + k * 0.26), pale,
                rot=(0, 0, rnd.uniform(-0.06, 0.06)), bevel=0.03, wobble=0.02, seed=seed + 20 + k)
    # rubble ring
    for k in range(26):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(1.05, 1.55)
        sz = rnd.uniform(0.07, 0.2)
        hv.blob(col, (math.cos(a) * d, math.sin(a) * d, sz * 0.35), sz, stone if k % 3 else pale, 1, 0.7, 0.35, seed + 50 + k)
    return 3.1, 3.1

def quarry(col):
    """Quarry works set around a stone deposit (the outcrop itself is a separate model):
    a timber crane over the rock, stacked cut blocks, a mason's bench, a small sledge."""
    seed = 61; rnd = random.Random(seed)
    M = mats(seed, "weathered", 1, 1)
    pale = hv.mat_wood("palestone", (0.36, 0.35, 0.33), (0.58, 0.57, 0.53), (14, 14, 14))
    rope = hv.mat_flat("rope", (0.35, 0.27, 0.15), 0.9)
    t = 0.12; kk = [0]
    def B(p0, p1, tt=t, m=None):
        kk[0] += 1; return hv.beam(col, p0, p1, tt, m or M["beam"], seed * 100 + kk[0])
    # crane: A-frame at the back-left, boom reaching over the rock
    base = Vector((-1.45, 1.05, 0))
    for dx in (-0.35, 0.35):
        B(base + Vector((dx, -0.3, 0)), base + Vector((0, 0, 2.5)))
        B(base + Vector((dx, 0.35, 0)), base + Vector((0, 0, 2.5)))
    B(base + Vector((-0.4, 0, 0.9)), base + Vector((0.4, 0, 0.9)), 0.08)
    tip = Vector((-0.2, 0.15, 2.2))
    B(base + Vector((0, 0, 0.6)), tip, 0.1)
    B(base + Vector((0, 0, 2.5)), tip, 0.06, rope)
    B(tip, tip + Vector((0, 0, -0.95)), 0.03, rope)
    hv.cube(col, (0.42, 0.34, 0.3), tip + Vector((0, 0, -1.12)), pale, bevel=0.03)
    # windlass drum on the A-frame
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.14, depth=0.72, location=base + Vector((0, 0, 0.9)), rotation=(0, math.pi / 2, 0))
    o = bpy.context.object; o.data.materials.append(M["log"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    # stacked cut blocks, front-right
    for k in range(5):
        x = 1.05 + (k % 3) * 0.36 - (0.18 if k >= 3 else 0.0); z = 0.16 + (k // 3) * 0.32
        hv.cube(col, (0.34, 0.34, 0.3), (x, -1.2, z), pale, rot=(0, 0, rnd.uniform(-0.12, 0.12)), bevel=0.02, wobble=0.01, seed=seed + k)
    # mason's bench with mallet and chisel, right side
    hv.cube(col, (0.5, 0.95, 0.07), (1.65, 0.25, 0.62), M["plank"], bevel=0.01)
    for dy in (-0.38, 0.38):
        for dx in (-0.18, 0.18):
            B((1.65 + dx, 0.25 + dy, 0), (1.65 + dx, 0.25 + dy, 0.6), 0.06)
    hv.cube(col, (0.3, 0.3, 0.24), (1.65, 0.45, 0.78), pale, bevel=0.02)
    B((1.6, -0.05, 0.68), (1.75, -0.35, 0.68), 0.035)
    hv.cube(col, (0.12, 0.09, 0.09), (1.6, -0.03, 0.68), M["plank"], bevel=0.01)
    # sledge with a block, front-left
    for dx in (-0.25, 0.25):
        B((-1.35 + dx, -1.55, 0.05), (-1.35 + dx, -0.85, 0.05), 0.07)
    hv.cube(col, (0.62, 0.72, 0.05), (-1.35, -1.2, 0.12), M["plank"], bevel=0.01)
    hv.cube(col, (0.4, 0.4, 0.3), (-1.35, -1.2, 0.3), pale, rot=(0, 0, 0.2), bevel=0.02)
    # chips on the ground
    for k in range(18):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(1.3, 1.9)
        hv.blob(col, (math.cos(a) * d, math.sin(a) * d, 0.03), rnd.uniform(0.04, 0.08), pale, 1, 0.6, 0.3, seed + 200 + k)
    return 4.0, 4.0

def site(col, stage):
    """Construction site for a 3 x 3 m footprint (the game scales it to each building).
    stage 0: levelled ground, stakes and string, first foundation stones, material piles.
    stage 1: stone plinth, timber frame with rafters, scaffolding, a ladder, thatch bundles."""
    seed = 500 + stage * 11; rnd = random.Random(seed)
    M = mats(seed, "golden", 0, 0)
    soil = hv.mat_wood("soil", (0.16, 0.10, 0.05), (0.30, 0.21, 0.12), (6, 6, 6))
    rope = hv.mat_flat("rope", (0.45, 0.36, 0.2), 0.9)
    t = 0.11; kk = [0]
    def B(p0, p1, tt=t, m=None):
        kk[0] += 1; return hv.beam(col, p0, p1, tt, m or M["beam"], seed * 100 + kk[0])
    hx, hy = 1.15, 0.95
    hv.cube(col, (2.9, 2.6, 0.04), (0, 0, 0.0), soil, bevel=0.01, wobble=0.02, seed=seed)
    # material piles: logs (left), stones (right back), planks (front right)
    for row in range(2 if stage == 1 else 3):
        for k in range(4 - row):
            log(col, M, (-1.3 + (k + row * 0.5) * 0.22, -0.2, 0.1 + row * 0.18), 1.1, 0.1, "y")
    for k in range(9 if stage == 0 else 4):
        hv.blob(col, (1.15 + rnd.uniform(-0.25, 0.25), 1.05 + rnd.uniform(-0.2, 0.2), 0.1 + (k // 5) * 0.12), rnd.uniform(0.11, 0.16), M["stone"], 1, 0.75, 0.3, seed + 40 + k)
    for k in range(4):
        hv.cube(col, (1.1, 0.16, 0.035), (0.9, -1.15, 0.03 + k * 0.04), M["plank"], rot=(0, 0, rnd.uniform(-0.08, 0.08)), bevel=0.005)
    if stage == 0:
        # stakes and string marking the footprint, the first foundation stones along one side
        corners = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
        for (x, y) in corners:
            B((x, y, 0), (x, y, 0.45), 0.05)
        for i in range(4):
            a = corners[i]; b = corners[(i + 1) % 4]
            B((a[0], a[1], 0.38), (b[0], b[1], 0.38), 0.012, rope)
        for k in range(7):
            x = -hx + 0.15 + k * 0.34
            o = hv.blob(col, (x, hy - 0.05, 0.1), 0.15, M["stone"], 2, 0.7, 0.3, seed + k)
            o.scale = (1.3, 1.0, 1.0)
        for k in range(4):
            y = hy - 0.4 - k * 0.34
            o = hv.blob(col, (-hx + 0.05, y, 0.1), 0.15, M["stone"], 2, 0.7, 0.3, seed + 20 + k)
        # a shovel stuck in the ground
        B((0.3, 0.2, 0.0), (0.42, 0.28, 0.95), 0.035)
        hv.cube(col, (0.16, 0.03, 0.2), (0.3, 0.2, 0.06), M["iron"], bevel=0.01)
    else:
        # plinth
        hv.cube(col, (2 * hx + 0.2, 2 * hy + 0.2, 0.25), (0, 0, 0.125), M["stone"], bevel=0.04)
        H = 1.7; top = 0.25 + H
        for sx in (-1, 1):
            for sy in (-1, 1):
                B((sx * hx, sy * hy, 0.25), (sx * hx, sy * hy, top))
            B((sx * hx, 0, 0.25), (sx * hx, 0, top))
        B((0, hy, 0.25), (0, hy, top))
        for sy in (-1, 1):
            B((-hx - 0.15, sy * hy, top), (hx + 0.15, sy * hy, top), t * 1.1)
            B((-hx, sy * hy, 1.05), (hx, sy * hy, 1.05), t * 0.7)
        for sx in (-1, 1):
            B((sx * hx, -hy - 0.15, top), (sx * hx, hy + 0.15, top), t * 1.1)
        # rafters (no thatch yet) and a ridge pole
        ridge = top + 1.2
        for k in range(4):
            x = -hx + k * (2 * hx / 3)
            B((x, -hy - 0.3, top - 0.1), (x, 0, ridge), 0.08)
            B((x, hy + 0.3, top - 0.1), (x, 0, ridge), 0.08)
        B((-hx - 0.2, 0, ridge), (hx + 0.2, 0, ridge), 0.09)
        for k in range(2):
            z = top + 0.35 + k * 0.4; yy = (hy + 0.3) * (1 - (z - top + 0.1) / 1.3)
            for sy in (-1, 1):
                B((-hx - 0.1, sy * yy, z), (hx + 0.1, sy * yy, z), 0.04)
        # scaffolding along the front with a plank deck and a ladder
        for x in (-hx - 0.1, 0.0, hx + 0.1):
            B((x, -hy - 0.55, 0), (x, -hy - 0.55, top + 0.3), 0.06, M["log"])
        B((-hx - 0.2, -hy - 0.55, 1.2), (hx + 0.2, -hy - 0.55, 1.2), 0.05, M["log"])
        hv.cube(col, (2 * hx + 0.3, 0.35, 0.04), (0, -hy - 0.4, 1.26), M["plank"], bevel=0.005)
        for sx in (-1, 1):
            B((hx + 0.35 + sx * 0.17, -hy - 0.9, 0), (hx + 0.2 + sx * 0.17, -hy - 0.6, 1.4), 0.04)
        for k in range(5):
            z = 0.25 + k * 0.25
            B((hx + 0.2, -hy - 0.88 + k * 0.05, z), (hx + 0.52, -hy - 0.88 + k * 0.05, z), 0.03)
        # thatch bundles waiting by the wall
        for k in range(5):
            bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.13, depth=0.8, location=(-0.6 + k * 0.28, hy + 0.5, 0.13 + (k % 2) * 0.1), rotation=(0, math.pi / 2, rnd.uniform(-0.3, 0.3)))
            o = bpy.context.object; o.data.materials.append(M["thatch"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    return 3.0, 3.0

if __name__ == "__main__":
    only = [a for a in sys.argv[2:] if a != "preview"]
    jobs = [("woodcutter", woodcutter, 2.9, 2.9), ("storehouse", storehouse, 3.6, 3.0),
            ("quarry", quarry, None, None),
            ("deposit_0", lambda c: deposit(c, 0), None, None), ("deposit_1", lambda c: deposit(c, 1), None, None),
            ("site_0", lambda c: site(c, 0), None, None), ("site_1", lambda c: site(c, 1), None, None)]
    for name, fn, fit_w, fit_d in jobs:
        if only and name not in only: continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        col = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(col)
        sx, sy = fn(col)
        # quarry and deposits are built at game scale (fit = own size -> scale 1)
        hv.finish(col, name, sx, sy, fit_w=fit_w or sx, fit_d=fit_d or sy, out_dir=OUT_DIR)
        if PREVIEW:
            hv.render_preview(os.path.join(OUT_DIR, f"_{name}_preview.png"))
