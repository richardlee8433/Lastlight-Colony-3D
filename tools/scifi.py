"""Hard sci-fi models for Lastlight Colony, baked like the village houses (tools/house_variants.py).

Run: python3 tools/scifi.py <models_dir> [preview] [name ...]
Writes <models_dir>/<name>.glb at game scale (1 unit = 1 m), front = -Y (Godot +Z).
Models: pod (the crashed escape pod with the survivors' camp around it).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
import house_variants as hv

OUT_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "models")
PREVIEW = "preview" in sys.argv
ONLY = [a for a in sys.argv[2:] if a != "preview"]

# ---------------- materials ----------------
def mat_panels(name, base, seam, grime=0.25, scale=3.0):
    """Hull plating: panels with dark seams, a little grime."""
    m, nt, b = hv.new_mat(name)
    vec = hv.mapping(nt, (scale, scale, scale))
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.inputs["Mortar Size"].default_value = 0.018; br.inputs["Scale"].default_value = 1.0
    br.inputs["Color1"].default_value = (*base, 1); br.inputs["Color2"].default_value = (*[c * 0.92 for c in base], 1)
    br.inputs["Mortar"].default_value = (*seam, 1)
    br.offset = 0.0; br.squash = 1.0
    nt.links.new(vec, br.inputs["Vector"])
    n = hv.noise_tex(nt, 6, 6, 0.65, vec)
    dirt = hv.ramp(nt, [(0.45, (1, 1, 1)), (0.75, (0.6, 0.55, 0.5))], n.outputs["Fac"])
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = grime
    nt.links.new(br.outputs["Color"], mul.inputs[6]); nt.links.new(dirt.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.45; b.inputs["Metallic"].default_value = 0.3
    hv.bump(nt, b, br.outputs["Fac"], 0.25, 0.02)
    return m

def mat_charred():
    m, nt, b = hv.new_mat("charred")
    n = hv.noise_tex(nt, 9, 8, 0.75, hv.mapping(nt))
    r = hv.ramp(nt, [(0.35, (0.02, 0.018, 0.017)), (0.6, (0.07, 0.055, 0.05)), (0.78, (0.25, 0.12, 0.05))], n.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.9
    hv.bump(nt, b, n.outputs["Fac"], 0.6, 0.05)
    return m

def mat_stripes(name, a, c, scale=8.0):
    """Hazard stripes."""
    m, nt, b = hv.new_mat(name)
    w = nt.nodes.new("ShaderNodeTexWave"); w.wave_type = "BANDS"; w.bands_direction = "DIAGONAL"
    w.inputs["Scale"].default_value = scale; w.inputs["Distortion"].default_value = 0.0
    nt.links.new(hv.mapping(nt), w.inputs["Vector"])
    r = hv.ramp(nt, [(0.49, a), (0.51, c)], w.outputs["Fac"])
    r.color_ramp.interpolation = "CONSTANT"
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.6
    return m

def mat_solar():
    """Photovoltaic cells: dark blue squares with thin silver gaps, smooth (no fabric-like bump)."""
    m, nt, b = hv.new_mat("solar_cells")
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.inputs["Mortar Size"].default_value = 0.04; br.inputs["Scale"].default_value = 1.0
    br.inputs["Color1"].default_value = (0.03, 0.06, 0.16, 1); br.inputs["Color2"].default_value = (0.04, 0.075, 0.19, 1)
    br.inputs["Mortar"].default_value = (0.55, 0.58, 0.62, 1)
    br.offset = 0.0; br.squash = 1.0
    br.inputs["Brick Width"].default_value = 1.0; br.inputs["Row Height"].default_value = 1.0
    nt.links.new(hv.mapping(nt, (8, 8, 8)), br.inputs["Vector"])
    nt.links.new(br.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.2; b.inputs["Metallic"].default_value = 0.2
    return m

def mats():
    return {
        "hull": mat_panels("hull", (0.74, 0.74, 0.72), (0.18, 0.18, 0.19), 0.35, 1.1),
        "hull_dark": mat_panels("hull_dark", (0.24, 0.26, 0.29), (0.05, 0.05, 0.06), 0.2, 3.0),
        "charred": mat_charred(),
        "orange": hv.mat_flat("orange", (0.85, 0.36, 0.08), 0.5),
        "glass": hv.mat_flat("glass", (0.05, 0.12, 0.18), 0.1),
        "metal": hv.mat_flat("metal", (0.35, 0.37, 0.40), 0.35),
        "dark": hv.mat_flat("darkmetal", (0.06, 0.065, 0.07), 0.5),
        "crate": mat_panels("crate", (0.30, 0.36, 0.42), (0.08, 0.09, 0.10), 0.25, 5.0),
        "hazard": mat_stripes("hazard", (0.9, 0.68, 0.08), (0.05, 0.05, 0.05)),
        "solar": mat_solar(),
        "foil": hv.mat_flat("foil", (0.85, 0.66, 0.25), 0.25),
        "foil2": hv.mat_flat("foil2", (0.75, 0.76, 0.78), 0.25),
        "regolith": hv.mat_wood("regolith", (0.22, 0.13, 0.08), (0.42, 0.27, 0.17), (5, 5, 5)),
        "scorch": hv.mat_wood("scorch", (0.03, 0.025, 0.02), (0.14, 0.09, 0.06), (4, 4, 4)),
        "rubber": hv.mat_flat("rubber", (0.04, 0.04, 0.04), 0.9),
    }

def cyl(col, r1, r2, depth, loc, m, rot=(0, 0, 0), verts=16):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object; o.data.materials.append(m)
    bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    for p in o.data.polygons: p.use_smooth = True
    return o

def sphere(col, r, loc, m, scale=(1, 1, 1), segs=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=r, location=loc)
    o = bpy.context.object; o.data.materials.append(m); o.scale = scale
    bpy.context.scene.collection.objects.unlink(o); col.objects.link(o)
    for p in o.data.polygons: p.use_smooth = True
    return o

def crate(col, M, loc, s=0.5, rot=0.0):
    x, y, z = loc
    hv.cube(col, (s, s * 0.8, s * 0.7), (x, y, z + s * 0.35), M["crate"], rot=(0, 0, rot), bevel=0.02)
    hv.cube(col, (s * 1.02, s * 0.82, 0.06), (x, y, z + s * 0.52), M["hazard"], rot=(0, 0, rot), bevel=0.005)
    for dx in (-1, 1):
        hv.cube(col, (0.04, s * 0.84, s * 0.1), (x + dx * s * 0.35 * math.cos(rot), y + dx * s * 0.35 * math.sin(rot), z + s * 0.2),
                M["dark"], rot=(0, 0, rot), bevel=0.005)

# ---------------- the escape pod camp ----------------
def pod(col):
    seed = 5; rnd = random.Random(seed)
    M = mats()
    # scorched impact crater with a regolith rim
    cyl(col, 2.3, 2.3, 0.02, (-0.4, 0.25, 0.005), M["scorch"], verts=40)
    for k in range(26):
        a = k / 26 * math.tau
        rr = rnd.uniform(1.9, 2.4)
        o = hv.blob(col, (-0.4 + math.cos(a) * rr, 0.25 + math.sin(a) * rr * 0.85, 0.02), rnd.uniform(0.18, 0.35),
                    M["regolith"], 2, 0.45, 0.4, seed + k)
        o.scale = (1.4, 1.0, 0.7)
    # the capsule: lying along X, nose dug in at +X, tilted
    body = bpy.data.collections.new("body"); bpy.context.scene.collection.children.link(body)
    L = 2.0; R = 0.72
    cyl(body, R, R, L, (0, 0, 0), M["hull"], rot=(0, math.pi / 2, 0), verts=24)
    sphere(body, R, (-L / 2, 0, 0), M["hull"], (0.75, 1, 1))
    nose = cyl(body, R * 1.02, R * 0.35, 0.65, (L / 2 + 0.3, 0, 0), M["charred"], rot=(0, math.pi / 2, 0), verts=24)
    cyl(body, R * 1.06, R * 1.06, 0.12, (L / 2 - 0.05, 0, 0), M["dark"], rot=(0, math.pi / 2, 0), verts=24)
    for x in (-0.55, 0.15):                                   # panel rings
        cyl(body, R * 1.015, R * 1.015, 0.05, (x, 0, 0), M["hull_dark"], rot=(0, math.pi / 2, 0), verts=24)
    # orange stripe and lettering band
    cyl(body, R * 1.01, R * 1.01, 0.16, (-0.85, 0, 0), M["orange"], rot=(0, math.pi / 2, 0), verts=24)
    # portholes on the top
    for x in (-0.35, 0.45):
        cyl(body, 0.13, 0.13, 0.06, (x, -0.25, R - 0.02), M["dark"], rot=(0.35, 0, 0))
        cyl(body, 0.1, 0.1, 0.07, (x, -0.255, R - 0.01), M["glass"], rot=(0.35, 0, 0))
    # open hatch on the front (-Y): dark opening, door swung down as a ramp
    hv.cube(body, (0.62, 0.08, 0.72), (-0.35, -R + 0.03, 0.0), M["dark"], bevel=0.02)
    door = hv.cube(body, (0.62, 0.06, 0.74), (-0.35, -R - 0.4, -0.42), M["hull"], rot=(1.25, 0, 0), bevel=0.02)
    # RCS thruster blocks and a bent antenna stub
    for a in (0.6, 2.5, 4.0):
        hv.cube(body, (0.16, 0.16, 0.12), (-0.2, math.cos(a) * R, math.sin(a) * R), M["hull_dark"], rot=(a, 0, 0), bevel=0.01)
    hv.beam(body, (-0.7, 0.2, R - 0.05), (-0.95, 0.35, R + 0.45), 0.03, M["metal"], seed)
    # place the capsule: tilted nose-down, sunk a little
    for o in list(body.objects):
        o.matrix_world = Matrix.Translation((-0.45, 0.2, 0.52)) @ Matrix.Rotation(0.22, 4, "Y") @ Matrix.Rotation(0.08, 4, "X") @ o.matrix_world
        body.objects.unlink(o); col.objects.link(o)
    bpy.data.collections.remove(body)
    # parachute lines and a crumpled chute behind
    sphere(col, 0.6, (-2.1, 0.95, 0.12), M["foil2"], (1.4, 1.0, 0.22))
    for k in range(3):
        hv.beam(col, (-1.95, 0.8 + k * 0.12, 0.2), (-1.35, 0.3 + k * 0.06, 0.65), 0.012, M["rubber"], seed + k)
    # supply crates (back right)
    crate(col, M, (1.25, 0.85, 0), 0.55, 0.15)
    crate(col, M, (1.75, 0.95, 0), 0.5, -0.2)
    crate(col, M, (1.45, 0.9, 0.39), 0.48, 0.4)
    # antenna mast with a dish (back left)
    hv.beam(col, (-1.65, 1.05, 0), (-1.65, 1.05, 1.9), 0.06, M["metal"], seed + 20)
    for a in (0.0, 2.1, 4.2):
        hv.beam(col, (-1.65 + math.cos(a) * 0.45, 1.05 + math.sin(a) * 0.45, 0), (-1.65, 1.05, 0.9), 0.025, M["metal"], seed + 21)
    dish = sphere(col, 0.32, (-1.55, 0.9, 1.65), M["hull"], (1, 1, 0.35))
    dish.rotation_euler = (0.9, 0.4, 0)
    cyl(col, 0.05, 0.05, 0.12, (-1.65, 1.05, 1.95), M["dark"])          # the beacon sits here (lit in Godot)
    # solar array on a stand (front left)
    hv.beam(col, (-1.9, -0.95, 0), (-1.9, -0.95, 0.7), 0.06, M["metal"], seed + 30)
    hv.cube(col, (1.3, 0.85, 0.04), (-1.9, -0.95, 0.85), M["solar"], rot=(0.5, 0, 0.3), bevel=0.01)
    hv.cube(col, (1.34, 0.89, 0.02), (-1.9, -0.95, 0.83), M["metal"], rot=(0.5, 0, 0.3), bevel=0.005)
    # the camp: a portable heater (glows in Godot) with foil blankets and cases around it
    fx, fy = 1.3, -1.0
    cyl(col, 0.2, 0.17, 0.35, (fx, fy, 0.175), M["hull_dark"], verts=16)
    cyl(col, 0.15, 0.15, 0.04, (fx, fy, 0.37), M["orange"], verts=16)
    for e in [[2.0, -1.6, 0.4], [0.55, -1.85, -0.3], [2.05, -0.35, 1.2]]:
        hv.cube(col, (0.55, 0.95, 0.05), (e[0], e[1], 0.03), M["foil"] if rnd.random() < 0.6 else M["foil2"], rot=(0, 0, e[2]), bevel=0.01, wobble=0.015, seed=seed)
        hv.cube(col, (0.5, 0.25, 0.12), (e[0] - math.sin(e[2]) * 0.0, e[1] + math.cos(e[2]) * 0.42, 0.06), M["crate"], rot=(0, 0, e[2]), bevel=0.03)
    crate(col, M, (0.55, -0.95, 0), 0.4, 0.5)
    return 5.0, 4.6

# ---------------- weathering ----------------
CLEAN = ("glass", "window", "lamp", "solar_cells", "glassgreen", "interior", "fibre", "plant", "plant2",
         "regolith", "scorch", "charred", "ore", "basalt", "palerock", "rubber")

def weather(col, strength=1.0):
    """Dust, rust streaks, edge scratches and grime in the creases, added to every material of the collection
    before baking (the bake keeps them in the diffuse texture). Dust settles low and on upward faces; rust
    runs down from seams in vertical streaks; worn edges show brighter bare metal."""
    done = set()
    for o in col.objects:
        if o.type != "MESH": continue
        for m in o.data.materials:
            if m is None or m.name in done or not m.use_nodes: continue
            done.add(m.name)
            if m.name.split(".")[0] in CLEAN: continue
            nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
            if b is None: continue
            bc = b.inputs["Base Color"]
            if bc.is_linked: src = bc.links[0].from_socket
            else:
                rgb = nt.nodes.new("ShaderNodeRGB"); rgb.outputs[0].default_value = bc.default_value; src = rgb.outputs[0]
            geo = nt.nodes.new("ShaderNodeNewGeometry")
            sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(geo.outputs["Position"], sep.inputs[0])
            sepn = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(geo.outputs["Normal"], sepn.inputs[0])
            def math_(op, a, b_=None, v=None):
                n = nt.nodes.new("ShaderNodeMath"); n.operation = op; n.use_clamp = op in ("MULTIPLY", "ADD", "SUBTRACT")
                for i, x in enumerate((a, b_)):
                    if x is None: continue
                    if isinstance(x, (int, float)): n.inputs[i].default_value = x
                    else: nt.links.new(x, n.inputs[i])
                return n.outputs[0]
            def noise(scale, sc=(1, 1, 1), detail=6):
                mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = sc
                nt.links.new(geo.outputs["Position"], mp.inputs["Vector"])
                t = nt.nodes.new("ShaderNodeTexNoise"); t.inputs["Scale"].default_value = scale; t.inputs["Detail"].default_value = detail
                t.inputs["Roughness"].default_value = 0.65
                nt.links.new(mp.outputs["Vector"], t.inputs["Vector"]); return t.outputs["Fac"]
            def ramp_(fac, a, c):
                r = nt.nodes.new("ShaderNodeMapRange"); r.inputs["From Min"].default_value = a; r.inputs["From Max"].default_value = c
                nt.links.new(fac, r.inputs["Value"]); return r.outputs["Result"]
            def mix_(fac, a, c, mode="MIX"):
                mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = mode; mx.clamp_result = True
                if isinstance(fac, (int, float)): mx.inputs["Factor"].default_value = fac
                else: nt.links.new(fac, mx.inputs["Factor"])
                for sock, v in ((6, a), (7, c)):
                    if isinstance(v, tuple): mx.inputs[sock].default_value = (*v, 1)
                    else: nt.links.new(v, mx.inputs[sock])
                return mx.outputs[2]
            # grime in the creases (ambient occlusion)
            ao = nt.nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.25
            grime = math_("SUBTRACT", 1.0, ao.outputs["AO"])
            c = mix_(math_("MULTIPLY", grime, 0.75 * strength), src, (0.10, 0.07, 0.05), "MULTIPLY")
            # rust: vertical streaks running down, patchy
            streak = ramp_(noise(9.0, (1.0, 1.0, 0.12), 4), 0.5, 0.68)
            patch = ramp_(noise(2.5), 0.38, 0.62)
            rust = math_("MULTIPLY", math_("MULTIPLY", streak, patch), 0.8 * strength)
            rustc = mix_(noise(30.0), (0.30, 0.13, 0.05), (0.52, 0.26, 0.10))
            c = mix_(rust, c, rustc)
            # scratches and worn edges: brighter bare material
            edge = ramp_(geo.outputs["Pointiness"], 0.52, 0.62)
            scratch = ramp_(noise(60.0, (1.0, 6.0, 1.0), 2), 0.62, 0.7)
            wear = math_("MULTIPLY", math_("ADD", math_("MULTIPLY", edge, noise(14.0)), math_("MULTIPLY", scratch, 0.5)), 0.6 * strength)
            c = mix_(wear, c, mix_(0.5, c, (0.72, 0.70, 0.66), "SCREEN"))
            # dust: settles near the ground and on upward faces, in drifts
            low = ramp_(sep.outputs[2], 1.2, 0.0)
            up = ramp_(sepn.outputs[2], 0.4, 0.95)
            drift = ramp_(noise(3.5), 0.35, 0.75)
            dust = math_("MULTIPLY", math_("ADD", math_("MULTIPLY", low, 0.8), math_("MULTIPLY", up, 0.55)), drift)
            c = mix_(math_("MULTIPLY", dust, 0.75 * strength), c, (0.58, 0.40, 0.28))
            c = mix_(0.12 * strength, c, (0.50, 0.38, 0.30))       # a film of fine dust over everything
            nt.links.new(c, bc)

JOBS = [("pod", pod)]

if __name__ == "__main__":
    for name, fn in JOBS:
        if ONLY and name not in ONLY: continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        col = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(col)
        sx, sy = fn(col)
        weather(col)
        hv.finish(col, name, sx, sy, fit_w=sx, fit_d=sy, out_dir=OUT_DIR)
        if PREVIEW:
            hv.render_preview(os.path.join(OUT_DIR, f"_{name}_preview.png"))
