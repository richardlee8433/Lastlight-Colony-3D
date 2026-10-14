"""Village thatched hut v2 — procedural, no external assets.
Run: python3 hut2.py <outdir> [preview]
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, noise

args = [a for a in sys.argv[1:]]
OUT = args[0] if args else "."
PREVIEW = "preview" in args
EMPTY = "empty" in args          # no cottage, props or dirt yard: the game's open starting meadow
MAP_HALF = 34.0                  # playable map: x and y in [-34, 34] m (68 x 68 m)
GROUND_HALF = 40.0               # the ground continues a little further under the border forest
os.makedirs(OUT, exist_ok=True)
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
hut_col = bpy.data.collections.new("Hut"); scene.collection.children.link(hut_col)

# ============ material helpers ============
def new_mat(name):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    return m, nt, b

def ramp(nt, colors, fac_out, interp="LINEAR"):
    r = nt.nodes.new("ShaderNodeValToRGB"); r.color_ramp.interpolation = interp
    els = r.color_ramp.elements
    while len(els) < len(colors): els.new(0.5)
    for e, (pos, c) in zip(els, colors):
        e.position = pos; e.color = (*c, 1)
    nt.links.new(fac_out, r.inputs["Fac"])
    return r

def noise_tex(nt, scale, detail=4, rough=0.6, vec=None, dist=0.0):
    t = nt.nodes.new("ShaderNodeTexNoise")
    t.inputs["Scale"].default_value = scale; t.inputs["Detail"].default_value = detail
    t.inputs["Roughness"].default_value = rough; t.inputs["Distortion"].default_value = dist
    if vec is not None: nt.links.new(vec, t.inputs["Vector"])
    return t

def bump(nt, b, height_out, strength=0.3, dist=0.1):
    bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = strength
    bp.inputs["Distance"].default_value = dist
    nt.links.new(height_out, bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])

def mapping(nt, coord="Object", scale=(1, 1, 1)):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = scale
    nt.links.new(tc.outputs[coord], mp.inputs["Vector"])
    return mp.outputs["Vector"]

def mix_color(nt, fac, a, b_):
    mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"
    if isinstance(fac, float): mx.inputs["Factor"].default_value = fac
    else: nt.links.new(fac, mx.inputs["Factor"])
    nt.links.new(a, mx.inputs[6]); nt.links.new(b_, mx.inputs[7])
    return mx.outputs[2]

# --- thatch: straw strands run down the slope, so variation is high-freq along X
def mat_thatch(name, dark=False):
    m, nt, b = new_mat(name)
    v = mapping(nt, "Object", (70, 3.5, 3.5))
    n1 = noise_tex(nt, 1.0, 6, 0.7, v, dist=0.6)
    base = [(0.0, (0.07, 0.037, 0.01)), (0.42, (0.23, 0.13, 0.035)), (0.68, (0.37, 0.23, 0.065)), (1.0, (0.48, 0.33, 0.12))]
    if dark: base = [(p, (c[0]*0.45, c[1]*0.45, c[2]*0.45)) for p, c in base]
    r1 = ramp(nt, base, n1.outputs["Fac"])
    # weathering: large grey-ish patches
    n2 = noise_tex(nt, 2.5, 3, 0.5, mapping(nt, "Object", (1, 1, 1)))
    r2 = ramp(nt, [(0.45, (0, 0, 0)), (0.75, (1, 1, 1))], n2.outputs["Fac"])
    grey = nt.nodes.new("ShaderNodeRGB"); grey.outputs[0].default_value = (0.14, 0.11, 0.07, 1)
    mxw = nt.nodes.new("ShaderNodeMath"); mxw.operation = "MULTIPLY"; mxw.inputs[1].default_value = 0.3
    nt.links.new(r2.outputs["Color"], mxw.inputs[0])
    col = mix_color(nt, mxw.outputs[0], r1.outputs["Color"], grey.outputs[0])
    nt.links.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    bump(nt, b, n1.outputs["Fac"], 0.9, 0.08)
    return m

def mat_plaster():
    m, nt, b = new_mat("plaster")
    n = noise_tex(nt, 5, 6, 0.65, mapping(nt, "Object", (1, 1, 1)))
    r = ramp(nt, [(0.3, (0.17, 0.12, 0.07)), (0.55, (0.28, 0.21, 0.125)), (0.75, (0.34, 0.27, 0.16))], n.outputs["Fac"])
    # dirt creeping up from the ground (world Z)
    tc = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    n3 = noise_tex(nt, 3, 3, 0.5)
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "MULTIPLY_ADD"
    nt.links.new(n3.outputs["Fac"], add.inputs[0]); add.inputs[1].default_value = 0.5
    nt.links.new(sep.outputs["Z"], add.inputs[2])
    rz = ramp(nt, [(0.55, (1, 1, 1)), (1.35, (0, 0, 0))], add.outputs[0])
    rz.color_ramp.elements[0].position = 0.45; rz.color_ramp.elements[1].position = 1.0
    dirt = nt.nodes.new("ShaderNodeRGB"); dirt.outputs[0].default_value = (0.10, 0.075, 0.045, 1)
    col = mix_color(nt, rz.outputs["Color"], r.outputs["Color"], dirt.outputs[0])
    nt.links.new(col, b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.95
    bump(nt, b, n.outputs["Fac"], 0.25, 0.05)
    return m

def mat_wood(name, c_dark, c_light, scale=(1, 1, 12)):
    m, nt, b = new_mat(name)
    v = mapping(nt, "Object", scale)
    w = nt.nodes.new("ShaderNodeTexWave"); w.wave_type = "BANDS"; w.bands_direction = "Z"
    w.inputs["Scale"].default_value = 1.5; w.inputs["Distortion"].default_value = 6; w.inputs["Detail"].default_value = 3
    nt.links.new(v, w.inputs["Vector"])
    r = ramp(nt, [(0.0, c_dark), (1.0, c_light)], w.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.8
    bump(nt, b, w.outputs["Fac"], 0.35, 0.02)
    return m

def mat_stone(name="stone"):
    m, nt, b = new_mat(name)
    n = noise_tex(nt, 4, 6, 0.7, mapping(nt, "Object", (1, 1, 1)))
    r = ramp(nt, [(0.3, (0.06, 0.055, 0.045)), (0.6, (0.14, 0.13, 0.11)), (0.8, (0.21, 0.19, 0.16))], n.outputs["Fac"])
    # moss on top faces
    geo = nt.nodes.new("ShaderNodeNewGeometry"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    n2 = noise_tex(nt, 6, 3, 0.5)
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
    nt.links.new(sep.outputs["Z"], mul.inputs[0]); nt.links.new(n2.outputs["Fac"], mul.inputs[1])
    rm = ramp(nt, [(0.52, (0, 0, 0)), (0.62, (1, 1, 1))], mul.outputs[0])
    moss = nt.nodes.new("ShaderNodeRGB"); moss.outputs[0].default_value = (0.08, 0.12, 0.025, 1)
    col = mix_color(nt, rm.outputs["Color"], r.outputs["Color"], moss.outputs[0])
    nt.links.new(col, b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.9
    bump(nt, b, n.outputs["Fac"], 0.5, 0.1)
    return m

def mat_ground():
    m, nt, b = new_mat("ground")
    att = nt.nodes.new("ShaderNodeAttribute"); att.attribute_name = "dirt"; att.attribute_type = "GEOMETRY"
    n = noise_tex(nt, 0.35, 5, 0.6, mapping(nt, "Object", (1, 1, 1)))
    grass = ramp(nt, [(0.3, (0.05, 0.09, 0.01)), (0.55, (0.10, 0.165, 0.016)), (0.8, (0.17, 0.22, 0.03))], n.outputs["Fac"])
    nd = noise_tex(nt, 3, 6, 0.6)
    dirtc = ramp(nt, [(0.35, (0.12, 0.075, 0.035)), (0.7, (0.25, 0.165, 0.08))], nd.outputs["Fac"])
    # ragged edge between dirt and grass
    ne = noise_tex(nt, 6, 4, 0.6)
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "MULTIPLY_ADD"
    nt.links.new(ne.outputs["Fac"], add.inputs[0]); add.inputs[1].default_value = 0.5
    nt.links.new(att.outputs["Fac"], add.inputs[2])
    edge = ramp(nt, [(0.62, (0, 0, 0)), (0.78, (1, 1, 1))], add.outputs[0])
    col = mix_color(nt, edge.outputs["Color"], grass.outputs["Color"], dirtc.outputs["Color"])
    nt.links.new(col, b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.95
    bump(nt, b, nd.outputs["Fac"], 0.3, 0.1)
    return m

def mat_foliage(name, c1, c2, c3, scale=8):
    m, nt, b = new_mat(name)
    oi = nt.nodes.new("ShaderNodeObjectInfo")
    n = noise_tex(nt, scale, 5, 0.65, mapping(nt, "Object", (1, 1, 1)))
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "MULTIPLY_ADD"
    nt.links.new(oi.outputs["Random"], add.inputs[0]); add.inputs[1].default_value = 0.35
    nt.links.new(n.outputs["Fac"], add.inputs[2])
    r = ramp(nt, [(0.35, c1), (0.65, c2), (0.95, c3)], add.outputs[0])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.8
    try:
        b.inputs["Subsurface Weight"].default_value = 0.05
    except KeyError: pass
    bump(nt, b, n.outputs["Fac"], 0.6, 0.15)
    return m

def mat_flat(name, c, rough=0.8):
    m, nt, b = new_mat(name); b.inputs["Base Color"].default_value = (*c, 1)
    b.inputs["Roughness"].default_value = rough
    return m

M = {
    "thatch": mat_thatch("thatch"), "thatch_dark": mat_thatch("thatch_under", True),
    "plaster": mat_plaster(),
    "beam": mat_wood("beam", (0.04, 0.022, 0.01), (0.12, 0.07, 0.035)),
    "plank": mat_wood("plank", (0.07, 0.045, 0.025), (0.20, 0.13, 0.07)),
    "fence": mat_wood("fence", (0.07, 0.045, 0.025), (0.20, 0.14, 0.08)),
    "stone": mat_stone(), "ground": mat_ground(),
    "leaf": mat_foliage("leaf", (0.012, 0.03, 0.008), (0.04, 0.085, 0.015), (0.11, 0.17, 0.03), 14),
    "pine": mat_foliage("pine", (0.012, 0.035, 0.015), (0.03, 0.07, 0.03), (0.07, 0.12, 0.04)),
    "blade": mat_foliage("blade", (0.05, 0.10, 0.012), (0.11, 0.19, 0.02), (0.20, 0.25, 0.035), 30),
    "dark": mat_flat("dark", (0.01, 0.008, 0.006)),
    "iron": mat_flat("iron", (0.03, 0.03, 0.03), 0.5),
    "petal_v": mat_flat("petal_v", (0.30, 0.30, 0.65)),
    "petal_w": mat_flat("petal_w", (0.75, 0.75, 0.70)),
    "rope": mat_flat("rope", (0.12, 0.08, 0.04)),
    "bark": mat_wood("bark", (0.03, 0.025, 0.02), (0.09, 0.07, 0.05), (6, 6, 1)),
}

# ============ geometry helpers ============
def link(o, col=None):
    (col or scene.collection).objects.link(o); return o

def mesh_obj(name, bm, m, col=None):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); link(o, col)
    if m: me.materials.append(m)
    return o

def add_mods(o, bevel=0.0, segs=2, solid=0.0, sub=0, smooth=False):
    if solid:
        s = o.modifiers.new("solid", "SOLIDIFY"); s.thickness = solid; s.offset = 0
    if bevel:
        b = o.modifiers.new("bev", "BEVEL"); b.width = bevel; b.segments = segs; b.limit_method = "ANGLE"
    if sub:
        o.modifiers.new("sub", "SUBSURF").levels = sub; o.modifiers["sub"].render_levels = sub
    if smooth:
        for p in o.data.polygons: p.use_smooth = True
    return o

def cube(name, size, loc, m, rot=(0, 0, 0), bevel=0.02, col=None, wobble=0.0, seed=0):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    if wobble:
        rnd = random.Random(seed)
        for v in bm.verts: v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * wobble
    o = mesh_obj(name, bm, m, col); o.location = loc; o.rotation_euler = rot
    return add_mods(o, bevel=bevel)

def beam_between(p0, p1, t, m, col=None, seed=0):
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    rnd = random.Random(seed)
    o = cube("beam", (t * rnd.uniform(.9, 1.1), t * rnd.uniform(.9, 1.1), d.length), (p0 + p1) / 2, m, col=col, bevel=0.015, wobble=t * 0.06, seed=seed)
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return o

def blob(name, loc, r, m, subd=2, squash=1.0, rough=0.25, seed=0, col=None):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=subd, radius=r)
    for v in bm.verts:
        n = noise.noise(v.co * (2.2 / r) + Vector((seed * 3.1, seed, 0)))
        v.co *= 1 + rough * n
        v.co.z *= squash
    o = mesh_obj(name, bm, m, col); o.location = loc
    for p in o.data.polygons: p.use_smooth = True
    return o

# ============ ground ============
def dirt_mask(x, y):
    if EMPTY: return 0.0
    # yard ellipse in front of hut + meandering path toward camera-left and to the right
    e = math.hypot(x / 5.0, (y + 1.2) / 3.9)
    yard = max(0.0, 1.0 - e)
    py = y
    path = 0.0
    if py < -2.5:
        cx = -0.4 + 1.1 * math.sin(py * 0.35)
        path = max(0.0, 1.0 - abs(x - cx) / 0.85)
    px = x
    if px > 3.0:
        cy = -1.6 + 0.8 * math.sin(px * 0.4)
        path = max(path, max(0.0, 1.0 - abs(y - cy) / 0.7))
    v = min(1.0, yard * 3.0 + path * 1.6)
    v += 0.25 * noise.noise(Vector((x * 0.6, y * 0.6, 2.0)))
    return max(0.0, min(1.0, v))

def flower_mask(x, y):
    n = noise.noise(Vector((x * 0.28 + 11, y * 0.28 + 5, 0)))
    return max(0.0, (n - 0.18) * 3.0)

bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=400, y_segments=400, size=2 * GROUND_HALF)
for v in bm.verts:
    x, y = v.co.x, v.co.y
    d = math.hypot(x, y + 0.5)
    hill = 0.22 * noise.noise(Vector((x * 0.12, y * 0.12, 0.5))) + 0.05 * noise.noise(Vector((x * 0.8, y * 0.8, 1)))
    # broad, gentle swells further out (the village area stays nearly flat)
    swell = 0.55 * noise.noise(Vector((x * 0.045, y * 0.045, 3.0))) * min(1.0, max(0.0, (d - 12.0) / 10.0))
    v.co.z = hill * min(1.0, max(0.0, (d - 4.5) / 4.0)) + swell - 0.02 * dirt_mask(x, y)
ground = mesh_obj("ground", bm, M["ground"])
for p in ground.data.polygons: p.use_smooth = True
me = ground.data
a_dirt = me.attributes.new("dirt", "FLOAT", "POINT")
a_grass = me.attributes.new("grass", "FLOAT", "POINT")
a_flow = me.attributes.new("flowers", "FLOAT", "POINT")
for i, v in enumerate(me.vertices):
    dm = dirt_mask(v.co.x, v.co.y)
    a_dirt.data[i].value = dm
    near_house = 1.0 if (not EMPTY and abs(v.co.x) < 2.7 and abs(v.co.y) < 2.2) else 0.0
    g = max(0.0, 1.0 - dm * 1.8) * (1 - near_house)
    a_grass.data[i].value = g
    a_flow.data[i].value = flower_mask(v.co.x, v.co.y) * g * (1.0 if math.hypot(v.co.x, v.co.y) > 3.5 else 0.0)

if not EMPTY:
    # ============ hut ============
    W, D, H = 4.4, 3.2, 2.0
    BASE = 0.32
    wall_top = BASE + H
    H_ = hut_col

    # stone foundation: a ring of individual stones + core
    cube("found_core", (W + 0.2, D + 0.2, BASE), (0, 0, BASE / 2), M["stone"], bevel=0.04, col=H_)
    rnd = random.Random(3)
    perim = []
    for side in range(4):
        L = W + 0.3 if side % 2 == 0 else D + 0.3
        n = int(L / 0.42)
        for k in range(n):
            f = (k + 0.5) / n - 0.5
            if side == 0: p = (f * L, -(D + 0.3) / 2)
            elif side == 1: p = ((W + 0.3) / 2, f * L)
            elif side == 2: p = (-f * L, (D + 0.3) / 2)
            else: p = (-(W + 0.3) / 2, -f * L)
            perim.append(p)
    for i, (x, y) in enumerate(perim):
        s = rnd.uniform(0.17, 0.24)
        o = blob("fstone", (x, y, s * 0.75), s, M["stone"], subd=2, squash=0.75, rough=0.3, seed=i, col=H_)
        o.scale = (1.3, 1.1, 1.0)
        o.rotation_euler.z = rnd.uniform(0, 3.14)

    # walls with slight lean
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co.x *= W; v.co.y *= D; v.co.z = BASE + (v.co.z + 0.5) * H
        if v.co.z > BASE + 0.1:
            v.co.x += 0.03 * (1 if v.co.x > 0 else -1) * rnd.uniform(-1, 1)
            v.co.y += 0.025 * rnd.uniform(-1, 1)
    walls = mesh_obj("walls", bm, M["plaster"], H_)
    add_mods(walls, bevel=0.03, segs=2)

    # timber frame
    t = 0.17; k = 0
    def B(p0, p1, tt=t):
        global k; k += 1
        return beam_between(p0, p1, tt, M["beam"], H_, seed=k)
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
    # front: door posts, braces, mid-rail
    door_w = 1.05
    fy = -hy - 0.01
    for x in (-door_w / 2 - 0.09, door_w / 2 + 0.09):
        B((x, fy, BASE), (x, fy, wall_top), t * 0.9)
    B((-door_w / 2 - 0.15, fy, BASE + 1.72), (door_w / 2 + 0.15, fy, BASE + 1.72), t * 0.9)
    for sx in (-1, 1):
        B((sx * (door_w / 2 + 0.09), fy, BASE + 0.1), (sx * hx, fy, BASE + 1.15), t * 0.75)
        B((sx * hx * 0.98, fy, BASE + 1.15), (sx * (door_w / 2 + 0.09), fy, wall_top - 0.05), t * 0.75)
    # back + sides: vertical studs and cross rails
    for x in (-W / 6, W / 6):
        B((x, hy + 0.01, BASE), (x, hy + 0.01, wall_top), t * 0.8)
    B((-hx, hy + 0.01, BASE + 1.1), (hx, hy + 0.01, BASE + 1.1), t * 0.7)
    for sx in (-1, 1):
        B((sx * (hx + 0.01), -hy, BASE + 1.1), (sx * (hx + 0.01), hy, BASE + 1.1), t * 0.7)
        B((sx * (hx + 0.01), 0, BASE), (sx * (hx + 0.01), 0, wall_top), t * 0.8)

    # door: recessed dark frame + planks + iron straps
    cube("door_hole", (door_w + 0.02, 0.08, 1.66), (0, -hy + 0.02, BASE + 0.83), M["dark"], bevel=0, col=H_)
    for i in range(5):
        w_ = door_w / 5
        cube("plank", (w_ * 0.97, 0.06, 1.62 + rnd.uniform(-0.03, 0.02)), (-door_w / 2 + w_ * (i + 0.5), -hy - 0.02, BASE + 0.81),
             M["plank"], bevel=0.012, col=H_, wobble=0.006, seed=40 + i)
    for z in (0.35, 1.3):
        cube("strap", (door_w * 0.8, 0.02, 0.06), (0.05, -hy - 0.06, BASE + z), M["iron"], bevel=0.005, col=H_)
    # step
    blob("step", (0, -hy - 0.45, 0.06), 0.55, M["stone"], 2, 0.22, 0.1, 77, H_).scale = (1.4, 0.8, 1)

    # windows with shutters & sills
    def window(cx, cy, cz, facing):  # facing: 'y' front/back, 'x' sides
        w_, h_ = 0.6, 0.55
        if facing == "y":
            cube("win", (w_, 0.1, h_), (cx, cy, cz), M["dark"], bevel=0, col=H_)
            cube("sill", (w_ + 0.25, 0.22, 0.08), (cx, cy - 0.08, cz - h_ / 2 - 0.04), M["beam"], col=H_)
            cube("lintel", (w_ + 0.25, 0.16, 0.1), (cx, cy - 0.04, cz + h_ / 2 + 0.05), M["beam"], col=H_)
            for s in (-1, 1):
                o = cube("shutter", (w_ / 2, 0.05, h_ + 0.02), (cx + s * (w_ / 2 + w_ / 4 + 0.02), cy - 0.08, cz), M["plank"], col=H_)
                o.rotation_euler.z = s * 0.35
            cube("bar", (0.04, 0.04, h_), (cx, cy - 0.03, cz), M["beam"], bevel=0.005, col=H_)
        else:
            sgn = 1 if cx > 0 else -1
            cube("win", (0.1, w_, h_), (cx, cy, cz), M["dark"], bevel=0, col=H_)
            cube("sill", (0.22, w_ + 0.25, 0.08), (cx + sgn * 0.08, cy, cz - h_ / 2 - 0.04), M["beam"], col=H_)
            cube("lintel", (0.16, w_ + 0.25, 0.1), (cx + sgn * 0.04, cy, cz + h_ / 2 + 0.05), M["beam"], col=H_)
            cube("bar", (0.04, 0.04, h_), (cx + sgn * 0.03, cy, cz), M["beam"], bevel=0.005, col=H_)
    window(1.35, -hy + 0.02, BASE + 1.25, "y")
    window(-1.35, -hy + 0.02, BASE + 1.25, "y")
    window(hx - 0.02, -0.75, BASE + 1.25, "x")

    # ============ thatched roof ============
    OX, OY = 0.75, 0.75                     # overhang
    hw, hd = W / 2 + OX, D / 2 + OY
    z_eave = wall_top - 0.42
    rise = 2.35
    z_ridge = z_eave + rise
    slope_n = Vector((0, 1, 0))
    def roof_point(side, x, f, lift=0.0):
        y = side * hd * (1 - f)
        z = z_eave + rise * f
        n = Vector((0, side * rise, hd)).normalized()
        # gable ends: thatch rolls down over the edge
        ex = max(0.0, (abs(x) - (W / 2 + 0.1)) / OX)
        z -= 0.35 * ex ** 2.2
        # slight sag in the middle of the ridge line (old roof)
        z -= 0.10 * (1 - (x / hw) ** 2) * f
        return Vector((x, y, z)) + n * lift

    # under-layer shell (dark, fills any gaps)
    bm = bmesh.new(); NX, NF = 40, 12; grid = {}
    for side in (-1, 1):
        for j in range(NF + 1):
            for i in range(NX + 1):
                key = (side, i, j) if j < NF else ("r", i)
                if key in grid: continue
                x = -hw + 2 * hw * i / NX
                grid[key] = bm.verts.new(roof_point(side, x, j / NF, 0.0))
    def gk(side, i, j): return grid[(side, i, j) if j < NF else ("r", i)]
    for side in (-1, 1):
        for j in range(NF):
            for i in range(NX):
                q = [gk(side, i, j), gk(side, i + 1, j), gk(side, i + 1, j + 1), gk(side, i, j + 1)]
                if side == 1: q.reverse()
                bm.faces.new(q)
    shell = mesh_obj("roof_shell", bm, M["thatch_dark"], H_)
    s = shell.modifiers.new("solid", "SOLIDIFY"); s.thickness = 0.32; s.offset = -1
    add_mods(shell, smooth=True)

    # overlapping courses with ragged lower edges
    R = 8
    course_objs = []
    for side in (-1, 1):
        for c in range(R):
            f_lo = c / R * 0.97
            f_hi = min(1.0, f_lo + 1.9 / R)
            lip = (0.36 if c == 0 else 0.10) * (1 - 0.3 * c / R)
            bm = bmesh.new(); nx = 64; rows = []
            rr = random.Random(side * 100 + c)
            xs = [-hw - 0.08 + (2 * hw + 0.16) * i / nx for i in range(nx + 1)]
            rag = [rr.uniform(0.0, 1.0) for _ in xs]
            # smooth the raggedness a bit, then add tufts
            rag = [0.5 * rag[i] + 0.5 * (0.5 + 0.5 * noise.noise(Vector((xs[i] * 1.3, c * 3.7, side)))) for i in range(nx + 1)]
            profile = [(0.0, lip, 1.0), (0.12, lip * 0.85, 0.5), (0.45, lip * 0.45, 0.15), (1.0, 0.04, 0.0)]
            for (u, lift, ragw) in profile:
                row = []
                for i, x in enumerate(xs):
                    ff = f_lo + (f_hi - f_lo) * u - ragw * rag[i] * (0.55 / R)
                    ex = max(0.0, (abs(x) - hw + 0.25) / 0.33)   # round the ends of each course
                    p = roof_point(side, x, max(0.0, ff), lift * (1 - 0.6 * min(1, ex)) * (0.75 + 0.5 * rag[i]))
                    row.append(bm.verts.new(p))
                rows.append(row)
            for r_ in range(len(rows) - 1):
                for i in range(nx):
                    q = [rows[r_][i], rows[r_][i + 1], rows[r_ + 1][i + 1], rows[r_ + 1][i]]
                    if side == 1: q.reverse()
                    bm.faces.new(q)
            o = mesh_obj("course", bm, M["thatch"], H_)
            so = o.modifiers.new("solid", "SOLIDIFY"); so.thickness = 0.08; so.offset = 1
            add_mods(o, sub=1, smooth=True)
            course_objs.append(o)

    # ridge: rounded bundle with rope ties
    bm = bmesh.new()
    nseg, nring = 40, 10
    rings = []
    for i in range(nseg + 1):
        x = -hw - 0.05 + (2 * hw + 0.1) * i / nseg
        base = roof_point(-1, x, 1.0, 0.0)
        ring = []
        for j in range(nring):
            a = 2 * math.pi * j / nring
            r_ = 0.24 * (1 + 0.12 * noise.noise(Vector((x * 2, a, 0))))
            ring.append(bm.verts.new((x, math.cos(a) * r_ * 1.25, base.z + 0.02 + math.sin(a) * r_ * 0.75)))
        rings.append(ring)
    for i in range(nseg):
        for j in range(nring):
            bm.faces.new([rings[i][j], rings[i][(j + 1) % nring], rings[i + 1][(j + 1) % nring], rings[i + 1][j]])
    bmesh.ops.contextual_create(bm, geom=rings[0]); bmesh.ops.contextual_create(bm, geom=rings[-1])
    ridge = mesh_obj("ridge", bm, M["thatch"], H_); add_mods(ridge, sub=1, smooth=True)
    for i in range(0):
        x = -hw + 0.35 + (2 * hw - 0.7) * i / 8
        base = roof_point(-1, x, 1.0, 0.0)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.33, minor_radius=0.035, location=(x, 0, base.z + 0.02), rotation=(0, math.pi / 2, 0))
        o = bpy.context.object; o.scale = (0.78, 1.25, 1); o.data.materials.append(M["rope"])
        scene.collection.objects.unlink(o); H_.objects.link(o)

    # gable triangles
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.02)
        bm = bmesh.new()
        zt = roof_point(-1, W / 2 - 0.02, 1.0).z
        ytop = 0.0
        a = bm.verts.new((x, -D / 2, wall_top)); b_ = bm.verts.new((x, D / 2, wall_top))
        c = bm.verts.new((x, 0, zt))
        bm.faces.new((a, b_, c))
        g = mesh_obj("gable", bm, M["plaster"], H_)
        sg = g.modifiers.new("s", "SOLIDIFY"); sg.thickness = 0.12; sg.offset = 0
        B((sx * hx, 0, wall_top), (sx * hx, 0, zt - 0.1), t * 0.85)
        B((sx * hx, -D / 2 + 0.1, wall_top + 0.1), (sx * hx, 0, zt - 0.15), t * 0.7)

    # chimney (stacked stones)
    cx, cy = 1.25, 0.55
    cube("chim_core", (0.62, 0.62, 2.6), (cx, cy, wall_top + 0.9), M["stone"], bevel=0.05, col=H_, wobble=0.02, seed=5)
    for lvl in range(11):
        z = wall_top + 0.0 + lvl * 0.24
        for j in range(4):
            a = j * math.pi / 2 + (lvl % 2) * math.pi / 4
            o = blob("cstone", (cx + 0.29 * math.cos(a) * 1.05, cy + 0.29 * math.sin(a) * 1.05, z), 0.17, M["stone"], 1, 0.7, 0.25, lvl * 9 + j, H_)
    cube("chim_cap", (0.78, 0.78, 0.12), (cx, cy, wall_top + 2.25), M["stone"], bevel=0.03, col=H_, wobble=0.02, seed=6)

    # ============ props ============
    def fence(points, seed, broken=()):
        rr = random.Random(seed)
        pts = [Vector((p[0], p[1], 0)) for p in points]
        for i, p in enumerate(pts):
            h_ = rr.uniform(0.85, 1.0)
            o = cube("fpost", (0.11, 0.11, h_), (p.x, p.y, h_ / 2), M["fence"], bevel=0.02, wobble=0.012, seed=seed + i)
            o.rotation_euler = (rr.uniform(-.07, .07), rr.uniform(-.07, .07), rr.uniform(0, .5))
        for i in range(len(pts) - 1):
            if i in broken: continue
            a, b_ = pts[i], pts[i + 1]
            for z in (0.38, 0.7):
                beam_between(a + Vector((0, 0, z + rr.uniform(-.04, .04))), b_ + Vector((0, 0, z + rr.uniform(-.04, .04))), 0.065, M["fence"], seed=seed * 7 + i * 3 + int(z * 10))

    fence([(-5.6, -4.6), (-4.4, -4.75), (-3.2, -4.7), (-2.0, -4.6), (-1.1, -4.5)], 1)
    fence([(1.0, -4.5), (2.2, -4.6), (3.4, -4.55)], 2)
    fence([(-5.6, -4.6), (-5.75, -3.3), (-5.8, -2.0), (-5.7, -0.7), (-5.75, 0.6)], 3, broken=(2,))
    fence([(4.9, 0.9), (5.0, 2.1), (5.05, 3.3)], 4)

    def barrel(loc, seed):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.3, radius2=0.3, depth=0.8)
        for v in bm.verts:
            z = v.co.z / 0.4
            r = 1 + 0.12 * (1 - z * z)
            v.co.x *= r; v.co.y *= r
        o = mesh_obj("barrel", bm, M["plank"]); o.location = (loc[0], loc[1], 0.4)
        add_mods(o, bevel=0.03, segs=2, smooth=True)
        for z in (0.12, 0.68):
            bpy.ops.mesh.primitive_torus_add(major_radius=0.325, minor_radius=0.022, location=(loc[0], loc[1], z))
            bpy.context.object.data.materials.append(M["iron"])
    barrel((-2.9, -2.35), 1); barrel((-3.45, -2.0), 2)
    cube("crate", (0.6, 0.6, 0.5), (-3.25, -1.25, 0.25), M["plank"], bevel=0.03, wobble=0.01, seed=8, rot=(0, 0, 0.3))

    # woodpile under a mini lean-to by the side wall
    for i in range(15):
        r_ = i // 5; c = i % 5
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.12, depth=1.2,
            location=(W / 2 + 0.35, -0.1 + c * 0.25 + (0.12 if r_ % 2 else 0) + 0.7, 0.13 + r_ * 0.22), rotation=(0, math.pi / 2, 0))
        o = bpy.context.object; o.data.materials.append(M["plank"]); o.rotation_euler.z = random.uniform(-.06, .06)

    # chopping block & axe-less stump, well in the yard
    o = blob("stump", (-1.9, -3.3, 0.18), 0.28, M["bark"], 2, 1.0, 0.08, 9); o.scale = (1, 1, 1.3)
    # well
    for j in range(12):
        a = j * math.tau / 12
        blob("wstone", (-4.0 + 0.6 * math.cos(a), 2.6 + 0.6 * math.sin(a), 0.25), 0.24, M["stone"], 2, 1.6, 0.25, 200 + j)
    for sx in (-1, 1):
        beam_between((-4.0 + sx * 0.6, 2.6, 0.3), (-4.0 + sx * 0.6, 2.6, 1.6), 0.1, M["beam"], seed=300 + sx)
    cube("wroof", (1.6, 1.0, 0.06), (-4.0, 2.6 - 0.25, 1.75), M["plank"], rot=(0.5, 0, 0), bevel=0.01)
    cube("wroof", (1.6, 1.0, 0.06), (-4.0, 2.6 + 0.25, 1.75), M["plank"], rot=(-0.5, 0, 0), bevel=0.01)

# rocks: a few near the village, more scattered over the larger map
for i, (x, y, s_) in enumerate([(-6.8, 1.8, 0.7), (-6.2, 2.5, 0.4), (6.0, -3.0, 0.35), (4.2, -5.3, 0.25), (-7.2, -2.7, 0.5), (7.5, 2.0, 0.9)]):
    blob("rock", (x, y, s_ * 0.15), s_, M["stone"], 3, 0.6, 0.3, 500 + i)

def keep_clear(x, y, margin=0.0):
    """Village start area and the two roads settlers arrive on (south and east edges) stay open."""
    if math.hypot(x, y + 1.0) < 9.5 + margin: return True
    if abs(x - 0.2) < 3.2 + margin and y < -6.0: return True          # south road (game +z)
    if abs(y + 0.9) < 3.2 + margin and x > 6.0: return True           # east road
    return False

rr_rock = random.Random(77)
for i in range(22):
    for _ in range(20):
        x, y = rr_rock.uniform(-MAP_HALF + 2, MAP_HALF - 2), rr_rock.uniform(-MAP_HALF + 2, MAP_HALF - 2)
        if not keep_clear(x, y, 1.0): break
    s_ = rr_rock.uniform(0.25, 0.8)
    blob("rock", (x, y, s_ * 0.15), s_, M["stone"], 3, 0.6, 0.3, 520 + i)

# ============ trees & bushes ============
def broadleaf(loc, h, seed):
    rr = random.Random(seed)
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=7, radius1=0.22 * h / 5, radius2=0.1 * h / 5, depth=h * 0.6)
    o = mesh_obj("trunk", bm, M["bark"]); o.location = (loc[0], loc[1], h * 0.3)
    for k in range(rr.randint(14, 20)):
        off = Vector((rr.uniform(-1, 1), rr.uniform(-1, 1), rr.uniform(-0.6, 1))) * h * 0.24
        r_ = h * rr.uniform(0.11, 0.17)
        o = blob("crown", Vector((loc[0], loc[1], h * 0.66)) + off, r_, M["leaf"], 3, 0.8, 0.45, seed * 13 + k)
        o.rotation_euler = (rr.uniform(0, 3), rr.uniform(0, 3), rr.uniform(0, 3))

def pine(loc, h, seed):
    rr = random.Random(seed)
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.15, radius2=0.08, depth=h * 0.4)
    o = mesh_obj("trunk", bm, M["bark"]); o.location = (loc[0], loc[1], h * 0.2)
    layers = 5
    for k in range(layers):
        f = k / layers
        bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=h * (0.3 - 0.22 * f), radius2=0.02, depth=h * 0.32)
        for v in bm.verts:
            if v.co.z < 0:
                a = math.atan2(v.co.y, v.co.x)
                v.co.z -= 0.15 * abs(math.sin(a * 5 + seed)) * h * 0.1
                v.co.x *= 1 + 0.15 * math.sin(a * 7 + k); v.co.y *= 1 + 0.15 * math.sin(a * 7 + k)
        o = mesh_obj("pine", bm, M["pine"]); o.location = (loc[0], loc[1], h * (0.28 + 0.15 * k))
        add_mods(o, sub=1, smooth=True)

def tree(fn, loc, h, seed):
    """Builds a tree and tags its objects with ["tree"] = [x, y, height, kind (0 broadleaf, 1 pine), seed]
    so the exporters can tell trees apart (in-map trees become separate, choppable models in the game)."""
    before = set(bpy.data.objects.keys())
    fn(loc, h, seed)
    for name in set(bpy.data.objects.keys()) - before:
        bpy.data.objects[name]["tree"] = [loc[0], loc[1], h, 0 if fn is broadleaf else 1, seed]

# --- tree layout for the 68 m map ---
# * groves and single trees inside the map (separate, choppable models in the game)
# * a dense border forest just outside the map (baked into the scenery)
trees_xy = []
def try_tree(fn, x, y, h, seed, spacing=2.2):
    if keep_clear(x, y): return False
    for (tx, ty) in trees_xy:
        if (tx - x) ** 2 + (ty - y) ** 2 < spacing * spacing: return False
    trees_xy.append((x, y))
    tree(fn, (x, y), h, seed)
    return True

rr = random.Random(42)
# a few trees framing the village, as before
for i, (x, y, h) in enumerate([(-8.0, -1.5, 5.5), (8.5, -2.5, 5.0), (-6.8, 5.5, 6.5), (6.5, 6.0, 6.0)]):
    trees_xy.append((x, y)); tree(broadleaf, (x, y), h, 700 + i)
# groves
seed_n = 600
for g in range(10):
    a = g / 10.0 * math.tau + rr.uniform(-0.25, 0.25)
    d = rr.uniform(14.0, 27.0)
    cx, cy = math.cos(a) * d, math.sin(a) * d
    r = rr.uniform(3.5, 6.0)
    pine_share = rr.uniform(0.15, 0.7)
    for k in range(rr.randint(7, 13)):
        for _ in range(8):
            ang = rr.uniform(0, math.tau); rd = r * math.sqrt(rr.random())
            x, y = cx + math.cos(ang) * rd, cy + math.sin(ang) * rd
            if abs(x) < MAP_HALF - 1.5 and abs(y) < MAP_HALF - 1.5 and try_tree(pine if rr.random() < pine_share else broadleaf, x, y, rr.uniform(4.5, 7.0), seed_n):
                seed_n += 1; break
# single trees in the meadow
for i in range(22):
    for _ in range(10):
        x, y = rr.uniform(-MAP_HALF + 2, MAP_HALF - 2), rr.uniform(-MAP_HALF + 2, MAP_HALF - 2)
        if try_tree(broadleaf if rr.random() < 0.7 else pine, x, y, rr.uniform(4.5, 6.8), seed_n, 4.0):
            seed_n += 1; break
# border forest outside the playable map
x = -GROUND_HALF + 1.0
while x < GROUND_HALF - 0.5:
    y = -GROUND_HALF + 1.0
    while y < GROUND_HALF - 0.5:
        jx, jy = x + rr.uniform(-1.0, 1.0), y + rr.uniform(-1.0, 1.0)
        if max(abs(jx), abs(jy)) > MAP_HALF + 0.8:
            trees_xy.append((jx, jy))
            tree(broadleaf if rr.random() < 0.55 else pine, (jx, jy), rr.uniform(5.0, 7.5), seed_n); seed_n += 1
        y += 3.0
    x += 3.0

def bush(loc, s_, seed, flowers=None):
    rr = random.Random(seed)
    for k in range(rr.randint(3, 5)):
        off = Vector((rr.uniform(-1, 1), rr.uniform(-1, 1), rr.uniform(0, .4))) * s_ * 0.7
        o = blob("bush", Vector(loc) + off, s_ * rr.uniform(.55, .85), M["leaf"], 2, 0.8, 0.35, seed * 7 + k)
        if flowers:
            for f in range(12):
                d = Vector((rr.uniform(-1, 1), rr.uniform(-1, 1), rr.uniform(.1, 1))).normalized() * s_ * 0.75
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.045, location=o.location + d)
                bpy.context.object.data.materials.append(M[flowers])
bush((-2.9, 2.1, 0.25), 0.6, 11, "petal_v"); bush((3.0, -2.6, 0.2), 0.45, 12, "petal_w")
bush((-2.7, -0.4, 0.2), 0.45, 13); bush((2.9, 2.2, 0.2), 0.5, 14, "petal_v")
bush((-0.9, 2.3, 0.2), 0.4, 15)
rr_b = random.Random(91)
for i in range(30):
    for _ in range(12):
        x, y = rr_b.uniform(-MAP_HALF + 2, MAP_HALF - 2), rr_b.uniform(-MAP_HALF + 2, MAP_HALF - 2)
        if not keep_clear(x, y, 0.5) and all((tx - x) ** 2 + (ty - y) ** 2 > 2.5 for (tx, ty) in trees_xy): break
    bush((x, y, 0.2), rr_b.uniform(0.4, 0.65), 30 + i, rr_b.choice([None, "petal_v", "petal_w"]))

# ============ scatter: grass tufts + flower clumps (geometry nodes) ============
def make_tuft():
    bm = bmesh.new(); rr = random.Random(1)
    for k in range(9):
        a = rr.uniform(0, math.tau); r0 = rr.uniform(0, 0.05)
        bx, by = math.cos(a) * r0, math.sin(a) * r0
        h = rr.uniform(0.16, 0.32); lean = rr.uniform(0.05, 0.14); la = rr.uniform(0, math.tau)
        w = 0.022
        px, py = -math.sin(la) * w, math.cos(la) * w
        v1 = bm.verts.new((bx - px, by - py, 0)); v2 = bm.verts.new((bx + px, by + py, 0))
        v3 = bm.verts.new((bx + math.cos(la) * lean * 0.5 + px * 0.6, by + math.sin(la) * lean * 0.5 + py * 0.6, h * 0.55))
        v4 = bm.verts.new((bx + math.cos(la) * lean * 0.5 - px * 0.6, by + math.sin(la) * lean * 0.5 - py * 0.6, h * 0.55))
        v5 = bm.verts.new((bx + math.cos(la) * lean, by + math.sin(la) * lean, h))
        bm.faces.new((v1, v2, v3, v4)); bm.faces.new((v4, v3, v5))
    o = mesh_obj("tuft_src", bm, M["blade"]); o.hide_render = True; o.hide_viewport = True
    o.location = (0, 0, -50)
    return o

def make_flowerclump(mat_name, seed):
    bm = bmesh.new(); rr = random.Random(seed)
    for k in range(7):
        x, y = rr.uniform(-0.12, 0.12), rr.uniform(-0.12, 0.12); h = rr.uniform(0.18, 0.32)
        # stem
        s1 = bm.verts.new((x - 0.008, y, 0)); s2 = bm.verts.new((x + 0.008, y, 0)); s3 = bm.verts.new((x, y, h))
        bm.faces.new((s1, s2, s3))
    stems = mesh_obj("fl_stems", bm, M["blade"])
    bm = bmesh.new(); rr = random.Random(seed)
    for k in range(7):
        x, y = rr.uniform(-0.12, 0.12), rr.uniform(-0.12, 0.12); h = rr.uniform(0.18, 0.32)
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.04, matrix=__import__("mathutils").Matrix.Translation((x, y, h)))
    heads = mesh_obj("fl_heads", bm, M[mat_name])
    bpy.ops.object.select_all(action="DESELECT")
    stems.select_set(True); heads.select_set(True); bpy.context.view_layer.objects.active = stems
    bpy.ops.object.join()
    o = bpy.context.object; o.name = "flower_src_" + mat_name
    o.hide_render = True; o.hide_viewport = True; o.location = (0, 0, -50)
    return o

def rv_sock(node, name, typ):
    for sk in node.inputs:
        if sk.name == name and sk.type == typ: return sk
    raise KeyError(name + typ)
def rv_out(node, typ):
    for sk in node.outputs:
        if sk.type == typ: return sk

def scatter(target, src, attr, density, smin, smax, seed, tilt=0.15):
    ng = bpy.data.node_groups.new("scatter_" + src.name, "GeometryNodeTree")
    ng.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    N = ng.nodes; L = ng.links
    gi = N.new("NodeGroupInput"); go = N.new("NodeGroupOutput")
    na = N.new("GeometryNodeInputNamedAttribute"); na.data_type = "FLOAT"; na.inputs["Name"].default_value = attr
    mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = density
    L.new(na.outputs["Attribute"], mul.inputs[0])
    dist = N.new("GeometryNodeDistributePointsOnFaces"); dist.distribute_method = "RANDOM"
    dist.inputs["Seed"].default_value = seed
    L.new(gi.outputs[0], dist.inputs["Mesh"]); L.new(mul.outputs[0], dist.inputs["Density"])
    oi = N.new("GeometryNodeObjectInfo"); oi.inputs["Object"].default_value = src; oi.transform_space = "ORIGINAL"
    inst = N.new("GeometryNodeInstanceOnPoints")
    L.new(dist.outputs["Points"], inst.inputs["Points"]); L.new(oi.outputs["Geometry"], inst.inputs["Instance"])
    rv = N.new("FunctionNodeRandomValue"); rv.data_type = "FLOAT_VECTOR"
    rv_sock(rv, "Min", "VECTOR").default_value = (-tilt, -tilt, 0); rv_sock(rv, "Max", "VECTOR").default_value = (tilt, tilt, math.tau)
    rv.inputs["Seed"].default_value = seed + 1
    try:
        e2r = N.new("FunctionNodeEulerToRotation")
        L.new(rv_out(rv, "VECTOR"), e2r.inputs[0]); L.new(e2r.outputs[0], inst.inputs["Rotation"])
    except Exception:
        L.new(rv_out(rv, "VECTOR"), inst.inputs["Rotation"])
    rs = N.new("FunctionNodeRandomValue"); rs.data_type = "FLOAT"
    rv_sock(rs, "Min", "VALUE").default_value = smin; rv_sock(rs, "Max", "VALUE").default_value = smax; rs.inputs["Seed"].default_value = seed + 2
    L.new(rv_out(rs, "VALUE"), inst.inputs["Scale"])
    join = N.new("GeometryNodeJoinGeometry")
    L.new(gi.outputs[0], join.inputs[0]); L.new(inst.outputs["Instances"], join.inputs[0])
    L.new(join.outputs[0], go.inputs[0])
    md = target.modifiers.new(ng.name, "NODES"); md.node_group = ng

tuft = make_tuft()
fl_v = make_flowerclump("petal_v", 3); fl_w = make_flowerclump("petal_w", 4)
if "build_only" not in args:
    # the game grows its own grass and flowers in chunks (scripts/scatter.gd); these are for renders only
    dens = 10 if PREVIEW else 16
    scatter(ground, tuft, "grass", dens, 0.45, 1.0, 10, 0.08)
    scatter(ground, fl_v, "flowers", 6 if PREVIEW else 14, 0.8, 1.4, 20, 0.1)
    scatter(ground, fl_w, "flowers", 3 if PREVIEW else 7, 0.8, 1.3, 30, 0.1)

# ============ lighting / render ============
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
wn = world.node_tree
sky = wn.nodes.new("ShaderNodeTexSky")
try:
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(42); sky.sun_rotation = math.radians(215)
    sky.sun_disc = False
except Exception:
    pass
wn.links.new(sky.outputs[0], wn.nodes["Background"].inputs["Color"])
wn.nodes["Background"].inputs["Strength"].default_value = 0.28

bpy.ops.object.light_add(type="SUN", rotation=(math.radians(46), 0, math.radians(215 - 180 + 20)))
sun = bpy.context.object.data; sun.energy = 3.8; sun.color = (1.0, 0.88, 0.70); sun.angle = math.radians(6)

scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"
scene.cycles.samples = 20 if PREVIEW else 48
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 4
scene.render.resolution_x, scene.render.resolution_y = (960, 640) if PREVIEW else (1600, 1000)
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.0

# atmospheric haze via compositor-free trick: a big faint volume would be slow, so skip; mist pass not needed.

bpy.ops.object.camera_add(); cam = bpy.context.object; scene.camera = cam
cam.data.dof.use_dof = False

def shoot(pos, target, lens, name):
    cam.location = pos; cam.data.lens = lens
    d = Vector(target) - Vector(pos)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)

shots = sys.argv[-1] if sys.argv[-1].startswith("shots=") else "shots=game,close"
if "build_only" in args: shots = "shots=none"
shots = shots.split("=")[1].split(",")
if "game" in shots: shoot((-9.5, -15.5, 15.0), (0.3, -0.3, 0.8), 38, "game_view.png")
if "close" in shots: shoot((-6.8, -9.2, 5.6), (0.1, 0.0, 1.9), 40, "close_view.png")

# export just the hut collection
if not PREVIEW and "build_only" not in args:
    bpy.ops.object.select_all(action="DESELECT")
    for o in hut_col.objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "thatched_hut_v2.glb"), export_format="GLB", use_selection=True, export_apply=True)
print("done")
