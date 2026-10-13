"""Generates baked variants of the village house (same style as the starter cottage).

Run: python3 tools/house_variants.py <models_dir> [count] [preview]
Writes <models_dir>/houses/house_<i>.glb (textures embedded) and, with "preview", house_<i>.png renders.

Each variant differs in size, roof height, thatch colour (golden / weathered / mossy), plaster colour,
chimney position, door/window layout, a side lean-to and flower boxes.
Output is sized to fit the in-game house footprint (about 2.7 x 1.9 m of walls), front door = -Y (Godot +Z).
"""
import bpy, bmesh, math, random, sys, os, tempfile
from mathutils import Vector, noise

args = sys.argv[1:]
OUT = os.path.abspath(os.path.join(args[0] if args else ".", "houses"))
COUNT = int(args[1]) if len(args) > 1 and args[1].isdigit() else 6
PREVIEW = "preview" in args
TEX = 1024
os.makedirs(OUT, exist_ok=True)

# ---------------- materials ----------------
def new_mat(name):
    m = bpy.data.materials.new(name); m.use_nodes = True
    return m, m.node_tree, m.node_tree.nodes["Principled BSDF"]

def ramp(nt, colors, fac_out):
    r = nt.nodes.new("ShaderNodeValToRGB"); els = r.color_ramp.elements
    while len(els) < len(colors): els.new(0.5)
    for e, (pos, c) in zip(els, colors): e.position = pos; e.color = (*c, 1)
    nt.links.new(fac_out, r.inputs["Fac"]); return r

def noise_tex(nt, scale, detail=4, rough=0.6, vec=None, dist=0.0):
    t = nt.nodes.new("ShaderNodeTexNoise")
    t.inputs["Scale"].default_value = scale; t.inputs["Detail"].default_value = detail
    t.inputs["Roughness"].default_value = rough; t.inputs["Distortion"].default_value = dist
    if vec is not None: nt.links.new(vec, t.inputs["Vector"])
    return t

def bump(nt, b, h, strength=0.3, dist=0.1):
    bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = strength; bp.inputs["Distance"].default_value = dist
    nt.links.new(h, bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])

def mapping(nt, scale=(1, 1, 1)):
    tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale; nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    return mp.outputs["Vector"]

def mix(nt, fac, a, b_):
    mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"
    if isinstance(fac, float): mx.inputs["Factor"].default_value = fac
    else: nt.links.new(fac, mx.inputs["Factor"])
    nt.links.new(a, mx.inputs[6]); nt.links.new(b_, mx.inputs[7]); return mx.outputs[2]

THATCH_TONES = {
    "golden":    ([(0.0, (0.09, 0.05, 0.012)), (0.42, (0.30, 0.18, 0.045)), (0.68, (0.46, 0.30, 0.08)), (1.0, (0.58, 0.42, 0.15))], (0.16, 0.12, 0.06), 0.2),
    "weathered": ([(0.0, (0.06, 0.045, 0.025)), (0.42, (0.17, 0.13, 0.07)), (0.68, (0.26, 0.21, 0.13)), (1.0, (0.34, 0.29, 0.19))], (0.12, 0.11, 0.09), 0.35),
    "mossy":     ([(0.0, (0.05, 0.035, 0.012)), (0.42, (0.18, 0.12, 0.04)), (0.68, (0.29, 0.20, 0.07)), (1.0, (0.38, 0.28, 0.11))], (0.05, 0.09, 0.02), 0.55),
}

def mat_thatch(tone, dark=False):
    base, patch, amount = THATCH_TONES[tone]
    m, nt, b = new_mat("thatch_" + tone + ("_d" if dark else ""))
    n1 = noise_tex(nt, 1.0, 6, 0.7, mapping(nt, (70, 3.5, 3.5)), dist=0.6)
    if dark: base = [(p, (c[0] * 0.45, c[1] * 0.45, c[2] * 0.45)) for p, c in base]
    r1 = ramp(nt, base, n1.outputs["Fac"])
    n2 = noise_tex(nt, 2.5, 3, 0.5, mapping(nt))
    r2 = ramp(nt, [(0.45, (0, 0, 0)), (0.75, (1, 1, 1))], n2.outputs["Fac"])
    pc = nt.nodes.new("ShaderNodeRGB"); pc.outputs[0].default_value = (*patch, 1)
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = amount
    nt.links.new(r2.outputs["Color"], mul.inputs[0])
    nt.links.new(mix(nt, mul.outputs[0], r1.outputs["Color"], pc.outputs[0]), b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    bump(nt, b, n1.outputs["Fac"], 0.9, 0.08)
    return m

def mat_plaster(c):
    m, nt, b = new_mat("plaster")
    n = noise_tex(nt, 5, 6, 0.65, mapping(nt))
    r = ramp(nt, [(0.3, tuple(x * 0.5 for x in c)), (0.55, tuple(x * 0.82 for x in c)), (0.75, c)], n.outputs["Fac"])
    geo = nt.nodes.new("ShaderNodeNewGeometry"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    n3 = noise_tex(nt, 3, 3, 0.5)
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "MULTIPLY_ADD"
    nt.links.new(n3.outputs["Fac"], add.inputs[0]); add.inputs[1].default_value = 0.5
    nt.links.new(sep.outputs["Z"], add.inputs[2])
    rz = ramp(nt, [(0.45, (1, 1, 1)), (1.0, (0, 0, 0))], add.outputs[0])
    dirt = nt.nodes.new("ShaderNodeRGB"); dirt.outputs[0].default_value = (0.10, 0.075, 0.045, 1)
    nt.links.new(mix(nt, rz.outputs["Color"], r.outputs["Color"], dirt.outputs[0]), b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    bump(nt, b, n.outputs["Fac"], 0.25, 0.05)
    return m

def mat_wood(name, c_dark, c_light, scale=(1, 1, 12)):
    m, nt, b = new_mat(name)
    w = nt.nodes.new("ShaderNodeTexWave"); w.wave_type = "BANDS"; w.bands_direction = "Z"
    w.inputs["Scale"].default_value = 1.5; w.inputs["Distortion"].default_value = 6; w.inputs["Detail"].default_value = 3
    nt.links.new(mapping(nt, scale), w.inputs["Vector"])
    r = ramp(nt, [(0.0, c_dark), (1.0, c_light)], w.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.8
    bump(nt, b, w.outputs["Fac"], 0.35, 0.02)
    return m

def mat_stone():
    m, nt, b = new_mat("stone")
    n = noise_tex(nt, 4, 6, 0.7, mapping(nt))
    r = ramp(nt, [(0.3, (0.06, 0.055, 0.045)), (0.6, (0.14, 0.13, 0.11)), (0.8, (0.21, 0.19, 0.16))], n.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.9
    bump(nt, b, n.outputs["Fac"], 0.5, 0.1)
    return m

def mat_flat(name, c, rough=0.8):
    m, nt, b = new_mat(name); b.inputs["Base Color"].default_value = (*c, 1); b.inputs["Roughness"].default_value = rough
    return m

# ---------------- geometry helpers ----------------
def mesh_obj(name, bm, m, col):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); col.objects.link(o)
    if m: me.materials.append(m)
    return o

def cube(col, size, loc, m, rot=(0, 0, 0), bevel=0.02, wobble=0.0, seed=0):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    rnd = random.Random(seed)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if wobble: v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * wobble
    o = mesh_obj("box", bm, m, col); o.location = loc; o.rotation_euler = rot
    if bevel:
        bv = o.modifiers.new("bev", "BEVEL"); bv.width = bevel; bv.segments = 2; bv.limit_method = "ANGLE"
    return o

def beam(col, p0, p1, t, m, seed=0):
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    rnd = random.Random(seed)
    o = cube(col, (t * rnd.uniform(.9, 1.1), t * rnd.uniform(.9, 1.1), d.length), (p0 + p1) / 2, m, bevel=0.015, wobble=t * 0.06, seed=seed)
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return o

def blob(col, loc, r, m, subd=2, squash=1.0, rough=0.25, seed=0):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=subd, radius=r)
    for v in bm.verts:
        v.co *= 1 + rough * noise.noise(v.co * (2.2 / r) + Vector((seed * 3.1, seed, 0))); v.co.z *= squash
    o = mesh_obj("blob", bm, m, col); o.location = loc
    for p in o.data.polygons: p.use_smooth = True
    return o

def thatch_roof(col, M, x0, x1, d, z_eave, rise, ox, oy, roll_ends, seed, sag=0.10, one_sided=False):
    """Gable (or single-pitch lean-to) thatch roof spanning x0..x1, depth d (y), eaves at z_eave."""
    hx0, hx1 = x0 - ox, x1 + ox
    hd = d / 2 + oy
    cx = (x0 + x1) / 2; half = (x1 - x0) / 2
    def rp(side, x, f, lift=0.0):
        if one_sided:   # single slope from y=+hd (high) to y=-hd (low)
            y = hd - 2 * hd * (1 - f) if side < 0 else hd
            y = -hd + 2 * hd * f
            z = z_eave + rise * f
            n = Vector((0, -rise, 2 * hd)).normalized()
        else:
            y = side * hd * (1 - f); z = z_eave + rise * f
            n = Vector((0, side * rise, hd)).normalized()
        if roll_ends:
            ex = max(0.0, (abs(x - cx) - (half + 0.1)) / ox); z -= 0.35 * ex ** 2.2
        z -= sag * (1 - ((x - cx) / (half + ox)) ** 2) * f
        return Vector((x, y, z)) + n * lift
    sides = (-1,) if one_sided else (-1, 1)
    # dark under-shell
    bm = bmesh.new(); NX, NF = 30, 10; grid = {}
    for side in sides:
        for j in range(NF + 1):
            for i in range(NX + 1):
                key = (side, i, j) if (j < NF or one_sided) else ("r", i)
                if key in grid: continue
                grid[key] = bm.verts.new(rp(side, hx0 + (hx1 - hx0) * i / NX, j / NF))
    def gk(side, i, j): return grid[(side, i, j) if (j < NF or one_sided) else ("r", i)]
    for side in sides:
        for j in range(NF):
            for i in range(NX):
                q = [gk(side, i, j), gk(side, i + 1, j), gk(side, i + 1, j + 1), gk(side, i, j + 1)]
                if side == 1: q.reverse()
                bm.faces.new(q)
    sh = mesh_obj("roof_shell", bm, M["thatch_dark"], col)
    s = sh.modifiers.new("solid", "SOLIDIFY"); s.thickness = 0.3; s.offset = -1
    for p in sh.data.polygons: p.use_smooth = True
    # courses
    R = 7 if not one_sided else 4
    for side in sides:
        for c in range(R):
            f_lo = c / R * 0.97; f_hi = min(1.0, f_lo + 1.9 / R)
            lip = (0.34 if c == 0 else 0.10) * (1 - 0.3 * c / R)
            bm = bmesh.new(); nx = 48; rows = []
            rr = random.Random(seed * 1000 + side * 100 + c)
            xs = [hx0 - 0.08 + (hx1 - hx0 + 0.16) * i / nx for i in range(nx + 1)]
            rag = [0.5 * rr.uniform(0, 1) + 0.5 * (0.5 + 0.5 * noise.noise(Vector((x * 1.3, c * 3.7 + seed, side)))) for x in xs]
            for (u, lift, ragw) in [(0.0, lip, 1.0), (0.12, lip * 0.85, 0.5), (0.45, lip * 0.45, 0.15), (1.0, 0.04, 0.0)]:
                row = []
                for i, x in enumerate(xs):
                    ff = f_lo + (f_hi - f_lo) * u - ragw * rag[i] * (0.55 / R)
                    ex = max(0.0, (abs(x - cx) - (half + ox) + 0.25) / 0.33)
                    row.append(bm.verts.new(rp(side, x, max(0.0, ff), lift * (1 - 0.6 * min(1, ex)) * (0.75 + 0.5 * rag[i]))))
                rows.append(row)
            for r_ in range(len(rows) - 1):
                for i in range(nx):
                    q = [rows[r_][i], rows[r_][i + 1], rows[r_ + 1][i + 1], rows[r_ + 1][i]]
                    if side == 1: q.reverse()
                    bm.faces.new(q)
            o = mesh_obj("course", bm, M["thatch"], col)
            so = o.modifiers.new("solid", "SOLIDIFY"); so.thickness = 0.08; so.offset = 1
            o.modifiers.new("sub", "SUBSURF").levels = 1
            for p in o.data.polygons: p.use_smooth = True
    if not one_sided:
        bm = bmesh.new(); rings = []
        for i in range(31):
            x = hx0 - 0.05 + (hx1 - hx0 + 0.1) * i / 30
            base = rp(-1, x, 1.0); ring = []
            for j in range(10):
                a = 2 * math.pi * j / 10
                r_ = 0.22 * (1 + 0.12 * noise.noise(Vector((x * 2, a, seed))))
                ring.append(bm.verts.new((x, math.cos(a) * r_ * 1.25, base.z + 0.02 + math.sin(a) * r_ * 0.75)))
            rings.append(ring)
        for i in range(30):
            for j in range(10):
                bm.faces.new([rings[i][j], rings[i][(j + 1) % 10], rings[i + 1][(j + 1) % 10], rings[i + 1][j]])
        bmesh.ops.contextual_create(bm, geom=rings[0]); bmesh.ops.contextual_create(bm, geom=rings[-1])
        rg = mesh_obj("ridge", bm, M["thatch"], col); rg.modifiers.new("sub", "SUBSURF").levels = 1
        for p in rg.data.polygons: p.use_smooth = True
    return rp

# ---------------- one house ----------------
def build_house(v, col):
    rnd = random.Random(v["seed"])
    M = {
        "thatch": mat_thatch(v["thatch"]), "thatch_dark": mat_thatch(v["thatch"], True),
        "plaster": mat_plaster(v["plaster"]),
        "beam": mat_wood("beam", v["beam"][0], v["beam"][1]),
        "plank": mat_wood("plank", (0.07, 0.045, 0.025), (0.20, 0.13, 0.07)),
        "stone": mat_stone(),
        "dark": mat_flat("dark", (0.01, 0.008, 0.006)),
        "iron": mat_flat("iron", (0.03, 0.03, 0.03), 0.5),
        "flower": mat_flat("flower", v["flowers"]) if v["flowers"] else None,
        "leaf": mat_flat("leaf", (0.04, 0.10, 0.02)),
        "log": mat_wood("log", (0.08, 0.05, 0.03), (0.25, 0.16, 0.08), (6, 6, 1)),
    }
    W, D, H = v["W"], v["D"], v["H"]
    BASE = 0.3; wall_top = BASE + H
    # foundation stones
    cube(col, (W + 0.2, D + 0.2, BASE), (0, 0, BASE / 2), M["stone"], bevel=0.04)
    i = 0
    for side in range(4):
        L = W + 0.3 if side % 2 == 0 else D + 0.3
        n = int(L / 0.42)
        for k in range(n):
            f = (k + 0.5) / n - 0.5
            p = [(f * L, -(D + 0.3) / 2), ((W + 0.3) / 2, f * L), (-f * L, (D + 0.3) / 2), (-(W + 0.3) / 2, -f * L)][side]
            s = rnd.uniform(0.16, 0.23)
            o = blob(col, (p[0], p[1], s * 0.75), s, M["stone"], 2, 0.75, 0.3, v["seed"] * 50 + i); o.scale = (1.3, 1.1, 1.0)
            i += 1
    # walls
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    for vv in bm.verts:
        vv.co.x *= W; vv.co.y *= D; vv.co.z = BASE + (vv.co.z + 0.5) * H
        if vv.co.z > BASE + 0.1:
            vv.co.x += 0.03 * rnd.uniform(-1, 1); vv.co.y += 0.025 * rnd.uniform(-1, 1)
    w = mesh_obj("walls", bm, M["plaster"], col)
    bv = w.modifiers.new("bev", "BEVEL"); bv.width = 0.03; bv.segments = 2
    # timber frame
    t = 0.16; kk = [0]
    def B(p0, p1, tt=t):
        kk[0] += 1; return beam(col, p0, p1, tt, M["beam"], v["seed"] * 100 + kk[0])
    hx, hy = W / 2 + 0.03, D / 2 + 0.03
    for sx in (-1, 1):
        for sy in (-1, 1):
            B((sx * hx, sy * hy, BASE), (sx * hx, sy * hy, wall_top + 0.05))
    for sy in (-1, 1):
        B((-hx - 0.1, sy * hy, BASE + 0.08), (hx + 0.1, sy * hy, BASE + 0.08))
        B((-hx - 0.25, sy * hy, wall_top), (hx + 0.25, sy * hy, wall_top), t * 1.1)
    for sx in (-1, 1):
        B((sx * hx, -hy - 0.1, BASE + 0.08), (sx * hx, hy + 0.1, BASE + 0.08))
        B((sx * hx, -hy - 0.25, wall_top), (sx * hx, hy + 0.25, wall_top), t * 1.1)
    door_w = 0.95; dx = v["door_x"]; fy = -hy - 0.01
    for x in (dx - door_w / 2 - 0.09, dx + door_w / 2 + 0.09):
        B((x, fy, BASE), (x, fy, wall_top), t * 0.9)
    B((dx - door_w / 2 - 0.15, fy, BASE + 1.65), (dx + door_w / 2 + 0.15, fy, BASE + 1.65), t * 0.9)
    if v["braces"]:
        for sx in (-1, 1):
            edge = sx * hx; inner = dx + sx * (door_w / 2 + 0.09)
            if abs(edge - inner) > 0.5:
                B((inner, fy, BASE + 0.1), (edge * 0.98, fy, BASE + 1.1), t * 0.72)
                B((edge * 0.98, fy, BASE + 1.1), (inner, fy, wall_top - 0.05), t * 0.72)
    else:
        B((-hx, fy, BASE + 1.05), (hx, fy, BASE + 1.05), t * 0.7)
    for x in (-W / 6, W / 6):
        B((x, hy + 0.01, BASE), (x, hy + 0.01, wall_top), t * 0.8)
    B((-hx, hy + 0.01, BASE + 1.05), (hx, hy + 0.01, BASE + 1.05), t * 0.7)
    for sx in (-1, 1):
        B((sx * (hx + 0.01), -hy, BASE + 1.05), (sx * (hx + 0.01), hy, BASE + 1.05), t * 0.7)
        B((sx * (hx + 0.01), 0, BASE), (sx * (hx + 0.01), 0, wall_top), t * 0.8)
    # door
    cube(col, (door_w + 0.02, 0.08, 1.58), (dx, -hy + 0.02, BASE + 0.79), M["dark"], bevel=0)
    for i in range(4):
        w_ = door_w / 4
        cube(col, (w_ * 0.97, 0.06, 1.54 + rnd.uniform(-0.03, 0.02)), (dx - door_w / 2 + w_ * (i + 0.5), -hy - 0.02, BASE + 0.77),
             M["plank"], bevel=0.012, wobble=0.006, seed=v["seed"] + i)
    for z in (0.35, 1.2):
        cube(col, (door_w * 0.8, 0.02, 0.06), (dx + 0.05, -hy - 0.06, BASE + z), M["iron"], bevel=0.005)
    blob(col, (dx, -hy - 0.42, 0.06), 0.5, M["stone"], 2, 0.22, 0.1, v["seed"] + 77).scale = (1.4, 0.8, 1)
    # windows
    def window(cx, cz, front=True, side_x=0.0):
        w_, h_ = 0.55, 0.5
        if front:
            cy = -hy + 0.02
            cube(col, (w_, 0.1, h_), (cx, cy, cz), M["dark"], bevel=0)
            cube(col, (w_ + 0.22, 0.2, 0.08), (cx, cy - 0.08, cz - h_ / 2 - 0.04), M["beam"])
            cube(col, (w_ + 0.22, 0.15, 0.1), (cx, cy - 0.04, cz + h_ / 2 + 0.05), M["beam"])
            for s in (-1, 1):
                o = cube(col, (w_ / 2, 0.05, h_ + 0.02), (cx + s * (w_ / 2 + w_ / 4 + 0.02), cy - 0.08, cz), M["plank"]); o.rotation_euler.z = s * 0.35
            cube(col, (0.04, 0.04, h_), (cx, cy - 0.03, cz), M["beam"], bevel=0.005)
            if M["flower"]:
                cube(col, (w_ + 0.1, 0.16, 0.14), (cx, cy - 0.17, cz - h_ / 2 - 0.13), M["plank"])
                for j in range(6):
                    blob(col, (cx - w_ / 2 + 0.06 + j * (w_ - 0.12) / 5, cy - 0.18, cz - h_ / 2 - 0.03), 0.055,
                         M["flower"] if j % 2 == 0 else M["leaf"], 1, 0.9, 0.2, v["seed"] * 7 + j)
        else:
            sgn = 1 if side_x > 0 else -1
            cube(col, (0.1, w_, h_), (side_x, cx, cz), M["dark"], bevel=0)
            cube(col, (0.2, w_ + 0.22, 0.08), (side_x + sgn * 0.08, cx, cz - h_ / 2 - 0.04), M["beam"])
            cube(col, (0.15, w_ + 0.22, 0.1), (side_x + sgn * 0.04, cx, cz + h_ / 2 + 0.05), M["beam"])
    for wx in v["windows"]:
        window(wx, BASE + 1.2)
    if v["side_window"]:
        window(-0.6, BASE + 1.2, False, hx - 0.02)
    # main roof
    ox, oy = 0.7, 0.72
    rp = thatch_roof(col, M, -W / 2, W / 2, D, wall_top - 0.4, v["rise"], ox, oy, True, v["seed"], sag=v["sag"])
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.02); zt = rp(-1, W / 2 - 0.02, 1.0).z
        bm = bmesh.new()
        a = bm.verts.new((x, -D / 2, wall_top)); b_ = bm.verts.new((x, D / 2, wall_top)); c = bm.verts.new((x, 0, zt))
        bm.faces.new((a, b_, c))
        g = mesh_obj("gable", bm, M["plaster"], col); s = g.modifiers.new("s", "SOLIDIFY"); s.thickness = 0.12
        B((sx * hx, 0, wall_top), (sx * hx, 0, zt - 0.1), t * 0.85)
    # chimney
    if v["chimney"]:
        cx = v["chimney"] * (W / 2 - 0.75); cy = 0.5
        cube(col, (0.56, 0.56, 2.4), (cx, cy, wall_top + 0.85), M["stone"], bevel=0.05, wobble=0.02, seed=v["seed"])
        for lvl in range(10):
            for j in range(4):
                a = j * math.pi / 2 + (lvl % 2) * math.pi / 4
                blob(col, (cx + 0.27 * math.cos(a), cy + 0.27 * math.sin(a), wall_top + lvl * 0.24), 0.16, M["stone"], 1, 0.7, 0.25, v["seed"] + lvl * 9 + j)
        cube(col, (0.72, 0.72, 0.12), (cx, cy, wall_top + 2.1), M["stone"], bevel=0.03, wobble=0.02, seed=v["seed"] + 1)
    # lean-to shed on one side
    if v["lean_to"]:
        s = v["lean_to"]; lw = 1.1
        x_in = s * W / 2; x_out = s * (W / 2 + lw)
        for y in (-D / 2 + 0.2, D / 2 - 0.2):
            beam(col, (x_out, y, 0), (x_out, y, BASE + 1.08), 0.12, M["beam"], v["seed"] + int(y * 10))
        # sloping plank roof: high against the wall, low at the posts
        z_hi, z_lo = BASE + 1.6, BASE + 1.05
        run = lw + 0.35
        ang = math.atan2(z_hi - z_lo, run) * (1 if s > 0 else -1)
        mid = Vector(((x_in + x_out) / 2 + s * 0.17, 0, (z_hi + z_lo) / 2 + 0.05))
        cube(col, (math.hypot(run, z_hi - z_lo) + 0.1, D + 0.25, 0.07), mid, M["plank"], rot=(0, ang, 0), bevel=0.01)
        for k in range(7):
            yy = -D / 2 + 0.05 + k * (D + 0.15) / 6
            cube(col, (math.hypot(run, z_hi - z_lo) + 0.12, 0.05, 0.04), mid + Vector((0, yy, 0.05)), M["beam"], rot=(0, ang, 0), bevel=0.005)
        if v.get("hay"):
            # hay bales stacked under it (farmhouse)
            for k in range(3):
                cube(col, (0.62, 0.42, 0.36), ((x_in + x_out) / 2 + s * 0.05, -D / 2 + 0.45 + k * 0.62, 0.2), M["thatch"],
                     rot=(0, 0, rnd.uniform(-0.12, 0.12)), bevel=0.06, wobble=0.02, seed=v["seed"] + 300 + k)
            for k in range(2):
                cube(col, (0.62, 0.42, 0.34), ((x_in + x_out) / 2 + s * 0.05, -D / 2 + 0.75 + k * 0.62, 0.56), M["thatch"],
                     rot=(0, 0, rnd.uniform(-0.15, 0.15)), bevel=0.06, wobble=0.02, seed=v["seed"] + 310 + k)
        # firewood stacked under it
        for row in range(0 if v.get("hay") else 3):
            for k in range(5 - row):
                bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.1, depth=D * 0.7,
                    location=((x_in + x_out) / 2 + (k - (4 - row) / 2) * 0.19 * (1 if s > 0 else -1) * 0.9, 0.1, 0.12 + row * 0.17),
                    rotation=(math.pi / 2, 0, 0))
                o = bpy.context.object; o.data.materials.append(M["log"])
                bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    # little extras by the door
    if v["barrel"]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.22, depth=0.55, location=(dx + 0.95, -hy - 0.35, 0.28))
        o = bpy.context.object; o.data.materials.append(M["plank"]); bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    return W + (1.1 if v["lean_to"] else 0.0) + 2 * 0.2, D + 0.6

# ---------------- variants ----------------
PLASTERS = [(0.34, 0.27, 0.16), (0.46, 0.43, 0.36), (0.40, 0.27, 0.12), (0.42, 0.30, 0.25), (0.38, 0.33, 0.22)]
BEAMS = [((0.04, 0.022, 0.01), (0.12, 0.07, 0.035)), ((0.06, 0.04, 0.025), (0.17, 0.11, 0.06)), ((0.03, 0.025, 0.02), (0.09, 0.07, 0.05))]
FLOWERS = [None, (0.55, 0.08, 0.06), (0.35, 0.18, 0.55), (0.75, 0.55, 0.08)]
PRESETS = [
    dict(W=4.2, D=3.1, H=1.95, rise=2.2, thatch="golden", plaster=0, beam=0, chimney=1, door_x=0.0, windows=[-1.25, 1.25], side_window=True, lean_to=0, braces=True, flowers=1, barrel=False, sag=0.10),
    dict(W=3.7, D=3.0, H=1.85, rise=2.0, thatch="weathered", plaster=1, beam=2, chimney=-1, door_x=-0.6, windows=[0.8], side_window=False, lean_to=1, braces=False, flowers=0, barrel=True, sag=0.06),
    dict(W=4.5, D=3.3, H=2.05, rise=2.5, thatch="mossy", plaster=2, beam=1, chimney=0, door_x=0.0, windows=[-1.35, 1.35], side_window=True, lean_to=0, braces=True, flowers=2, barrel=False, sag=0.16),
    dict(W=3.9, D=3.0, H=1.9, rise=2.15, thatch="golden", plaster=3, beam=1, chimney=-1, door_x=0.5, windows=[-0.9], side_window=True, lean_to=-1, braces=False, flowers=3, barrel=False, sag=0.08),
    dict(W=4.3, D=3.2, H=2.0, rise=2.3, thatch="weathered", plaster=4, beam=0, chimney=1, door_x=0.0, windows=[-1.3, 1.3], side_window=False, lean_to=0, braces=True, flowers=0, barrel=True, sag=0.12),
    dict(W=3.6, D=2.9, H=1.8, rise=1.95, thatch="mossy", plaster=0, beam=2, chimney=0, door_x=-0.45, windows=[0.75], side_window=True, lean_to=1, braces=True, flowers=1, barrel=False, sag=0.05),
]

def bake(obj, name):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"; scene.cycles.samples = 4
    scene.render.bake.margin = 4
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    imgs = {}
    for kind in ("DIFFUSE", "NORMAL"):
        img = bpy.data.images.new(f"{name}_{kind.lower()}", TEX, TEX, alpha=False, is_data=(kind == "NORMAL"))
        if kind == "NORMAL": img.colorspace_settings.name = "Non-Color"
        for sl in obj.material_slots:
            nt = sl.material.node_tree
            for n in [n for n in nt.nodes if n.name.startswith("BAKE")]: nt.nodes.remove(n)
            n = nt.nodes.new("ShaderNodeTexImage"); n.name = "BAKE"; n.image = img; nt.nodes.active = n
        if kind == "DIFFUSE": bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
        else: bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_clear=True)
        img.pack(); imgs[kind] = img
    m = bpy.data.materials.new(name + "_baked"); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]; b.inputs["Roughness"].default_value = 0.9
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = imgs["DIFFUSE"]; nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = imgs["NORMAL"]
    nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(tn.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    obj.data.materials.clear(); obj.data.materials.append(m)
    for p in obj.data.polygons: p.material_index = 0

def render_preview(path):
    scene = bpy.context.scene
    w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.6, 0.75, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(48), 0, math.radians(35)))
    bpy.context.object.data.energy = 3.5
    bpy.ops.mesh.primitive_plane_add(size=14)
    bpy.context.object.data.materials.append(mat_flat("g", (0.12, 0.2, 0.05)))
    bpy.ops.object.camera_add(location=(-4.5, -6.5, 5.0))
    cam = bpy.context.object; scene.camera = cam; cam.data.lens = 40
    cam.rotation_euler = (Vector((0, 0, 1.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.cycles.samples = 16; scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 520, 420
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

def finish(col, name, size_x, size_y, fit_w=2.75, fit_d=1.95, out_dir=None):
    """Join the collection, scale it to fit fit_w x fit_d metres, bake, export <out_dir>/<name>.glb."""
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in col.objects if o.type == "MESH"]
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    obj = bpy.context.object; obj.name = name
    s = min(fit_w / size_x, fit_d / size_y)
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bake(obj, name)
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True)
    path = os.path.join(out_dir or OUT, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_image_format="JPEG", export_jpeg_quality=82)
    print(f"exported {name}  scale {s:.3f}  faces {len(obj.data.polygons)}")
    return path

def variant(p, seed):
    p = dict(p); p["seed"] = seed
    p["plaster"] = PLASTERS[p["plaster"]]; p["beam"] = BEAMS[p["beam"]]; p["flowers"] = FLOWERS[p["flowers"]]
    return p

if __name__ == "__main__":
    for idx in range(COUNT):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        p = variant(PRESETS[idx % len(PRESETS)], 100 + idx * 17)
        col = bpy.data.collections.new("House"); bpy.context.scene.collection.children.link(col)
        size_x, size_y = build_house(p, col)
        finish(col, f"house_{idx}", size_x, size_y)
        if PREVIEW:
            render_preview(os.path.join(OUT, f"house_{idx}.png"))
