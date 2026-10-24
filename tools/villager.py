"""Procedural villager for the village builder ("puppet" rig: rigid parts with pivots at the joints).
Godot animates the parts in code, so no armature is needed.

Run: python3 tools/villager.py <out_dir> [preview]
Writes <out_dir>/villager.glb (+ villager_preview.png with "preview").

Blender coords: Z up, character faces +Y  ->  glTF/Godot: Y up, faces -Z.
Node names matter: Godot looks parts up by name and tints them per villager.
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

args = sys.argv[1:]
OUT = os.path.abspath(args[0] if args else ".")
PREVIEW = "preview" in args
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------------- materials (neutral; Godot re-tints by node name) ----------------
def mat(name, rgb, rough=0.8):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    return m
M = {
    "skin": mat("skin", (0.80, 0.55, 0.40)),
    "tunic": mat("tunic", (0.42, 0.20, 0.14)),
    "pants": mat("pants", (0.20, 0.15, 0.10)),
    "shoe": mat("shoe", (0.10, 0.06, 0.035)),
    "belt": mat("belt", (0.12, 0.07, 0.035)),
    "hair": mat("hair", (0.18, 0.09, 0.04)),
    "eye": mat("eye", (0.02, 0.015, 0.012), 0.4),
    "straw": mat("straw", (0.75, 0.58, 0.28)),
    "cloth": mat("cloth", (0.30, 0.34, 0.20)),
    "wood": mat("wood", (0.32, 0.20, 0.10)),
    "metal": mat("metal", (0.35, 0.36, 0.38), 0.45),
    "log": mat("log", (0.36, 0.24, 0.13)),
    "stone": mat("stone", (0.45, 0.44, 0.41)),
    "sack": mat("sack", (0.55, 0.43, 0.27)),
    "trim": mat("trim", (0.25, 0.12, 0.08)),
    "apron": mat("apron", (0.80, 0.75, 0.62)),
    "vest": mat("vest", (0.30, 0.20, 0.12)),
    "skirt": mat("skirt", (0.35, 0.25, 0.30)),
    "cheek": mat("cheek", (0.85, 0.42, 0.38), 0.9),
    "mouth": mat("mouth", (0.35, 0.12, 0.10), 0.6),
    "white": mat("white", (0.95, 0.94, 0.9), 0.4),
    "kerchief": mat("kerchief", (0.7, 0.25, 0.2)),
}

def obj(name, bm, material, parent=None, loc=(0, 0, 0), smooth=True):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    if smooth:
        for p in me.polygons: p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    me.materials.append(M[material])
    if parent is not None: o.parent = parent
    o.location = loc
    return o

def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None); scene.collection.objects.link(e)
    if parent is not None: e.parent = parent
    e.location = loc
    return e

def lathe(profile, segs=16, sy=1.0, sx=1.0):
    """profile: [(z, r)] bottom->top. Elliptical cross-section via sx/sy."""
    bm = bmesh.new(); rings = []
    for z, r in profile:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            ring.append(bm.verts.new((math.cos(a) * r * sx, math.sin(a) * r * sy, z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    return bm

def sphere(r, center=(0, 0, 0), scale=(1, 1, 1), segs=14, rings=9):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(center)
    return bm

def box(size, center=(0, 0, 0), bevel=0.0):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(center)
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES")
    return bm

def cyl(r1, r2, z0, z1, segs=10, axis="Z", center=(0, 0, 0)):
    bm = lathe([(z0, r1), (z1, r2)], segs)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(center))
    return bm

def merge(*bms):
    out = bmesh.new()
    for b in bms:
        me = bpy.data.meshes.new("tmp"); b.to_mesh(me); b.free()
        out.from_mesh(me); bpy.data.meshes.remove(me)
    return out

def delete_verts(bm, pred):
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if pred(v.co)], context="VERTS")
    return bm

# ---------------- body ----------------
# A chibi figure about 1.1 m tall. Joint pivots: hips (legs, torso), neck (head), shoulders (arms).
# Every optional piece is its own node; Godot picks a look per villager (hair, beard, skirt,
# apron, vest, satchel, kerchief) and tints the pieces by name.
HIP = 0.40
root = empty("Villager")

def ring(r, z, sy=1.0, thick=0.012, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=segs, radius1=r, radius2=r * 0.97, depth=thick * 2)
    for v in bm.verts: v.co.y *= sy; v.co.z += z
    return bm

# legs: trousers with a knee, boots with a turned-down top and a sole (pivot at the hip joint)
for side, name in ((1, "LegL"), (-1, "LegR")):
    leg = obj(name, lathe([(-0.30, 0.040), (-0.22, 0.044), (-0.17, 0.047), (-0.08, 0.055), (0.0, 0.062)], 12), "pants",
              root, (0.068 * side, 0, HIP))
    boot = merge(lathe([(-0.375, 0.050), (-0.33, 0.047), (-0.27, 0.046), (-0.255, 0.052), (-0.24, 0.052)], 12),
                 box((0.088, 0.15, 0.06), (0, 0.03, -0.36), bevel=0.022),
                 box((0.094, 0.158, 0.016), (0, 0.032, -0.392), bevel=0.006))
    obj("Shoe" + name[-1], boot, "shoe", leg)

# torso: tunic with shoulders and a little chest, pivot at the hips so it can lean
torso = obj("Torso", lathe([(-0.10, 0.160), (-0.03, 0.150), (0.06, 0.133), (0.16, 0.135), (0.26, 0.145),
                            (0.32, 0.142), (0.36, 0.128), (0.395, 0.098), (0.42, 0.058)], 20, sy=0.76), "tunic",
            root, (0, 0, HIP))
# tunic skirt below the belt, flaring a little (legs swing inside it)
obj("Hem", lathe([(-0.19, 0.180), (-0.14, 0.170), (-0.10, 0.161)], 20, sy=0.80), "tunic", torso)
obj("HemTrim", ring(0.182, -0.185, 0.80, 0.013, 20), "trim", torso)
belt = bmesh.new()
bmesh.ops.create_cone(belt, cap_ends=False, segments=20, radius1=0.136, radius2=0.132, depth=0.04)
for v in belt.verts: v.co.y *= 0.79
obj("Belt", belt, "belt", torso, (0, 0, 0.07))
obj("Buckle", box((0.045, 0.012, 0.035), (0, 0.107, 0.07), 0.004), "metal", torso)
obj("Collar", merge(ring(0.070, 0.418, 0.85, 0.016, 16), box((0.03, 0.012, 0.07), (0, 0.105, 0.36), 0.005)), "trim", torso)
# optional layers
# apron: a front panel following the body from the chest down past the hem
apron = lathe([(-0.215, 0.192), (-0.14, 0.181), (-0.10, 0.171), (0.0, 0.160), (0.10, 0.146), (0.21, 0.150)], 28, sy=0.82)
delete_verts(apron, lambda c: c.y < 0.06)
obj("Apron", apron, "apron", torso)
vest = lathe([(0.02, 0.150), (0.16, 0.148), (0.30, 0.152), (0.36, 0.136), (0.385, 0.105)], 20, sy=0.79)
delete_verts(vest, lambda c: c.y > 0.07 and abs(c.x) < 0.05)
obj("Vest", vest, "vest", torso)
skirt = lathe([(-0.32, 0.232), (-0.22, 0.210), (-0.10, 0.180), (0.02, 0.152)], 22, sy=0.82)
obj("Skirt", skirt, "skirt", torso)
obj("SkirtTrim", ring(0.234, -0.315, 0.82, 0.015, 22), "trim", torso)
sat = merge(box((0.12, 0.05, 0.10), (-0.17, 0.01, -0.06), 0.02),
            cyl(0.008, 0.008, -0.04, 0.46, 6, "Z"))
for v in sat.verts:
    if v.co.z > -0.035 and abs(v.co.x) < 0.02:          # the strap: diagonal over the chest
        t = (v.co.z + 0.04) / 0.5
        v.co.x += -0.17 + t * 0.30; v.co.y += 0.115 * math.sin(t * math.pi) + 0.02
obj("Satchel", sat, "belt", torso)

# head (pivot at the neck): face with brows, cheeks, a small smile
neck = obj("Neck", cyl(0.045, 0.042, 0.39, 0.45, 10), "skin", torso)
head = obj("Head", sphere(0.145, (0, 0.0, 0.135), (1.0, 0.96, 0.96), 20, 14), "skin", torso, (0, 0, 0.42))
for s_, n in ((1, "EyeL"), (-1, "EyeR")):
    e = obj(n, sphere(0.019, (0, 0, 0), (1, 0.55, 1.3), 10, 8), "eye", head, (0.054 * s_, 0.130, 0.150))
    obj("Glint" + n[-1], sphere(0.006, (0.006, 0.008, 0.008), (1, 0.6, 1), 6, 5), "white", e)
for s_, n in ((1, "BrowL"), (-1, "BrowR")):
    br = box((0.042, 0.012, 0.011), (0, 0, 0), 0.004)
    bmesh.ops.rotate(br, verts=br.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-0.18 * s_, 3, "Y"))
    obj(n, br, "hair", head, (0.056 * s_, 0.133, 0.196))
for s_, n in ((1, "CheekL"), (-1, "CheekR")):
    obj(n, sphere(0.026, (0, 0, 0), (1, 0.35, 0.7), 10, 7), "cheek", head, (0.085 * s_, 0.112, 0.105))
obj("Nose", sphere(0.025, (0, 0.144, 0.118), (1, 0.85, 0.95), 10, 7), "skin", head)
mouth = bmesh.new()
pts_m = [(-0.028, 0.068), (-0.014, 0.060), (0.0, 0.058), (0.014, 0.060), (0.028, 0.068)]
mouth = merge(*[box((0.016, 0.008, 0.008), (x, 0.140 - abs(x) * 0.5, z), 0.003) for x, z in pts_m])
obj("Mouth", mouth, "mouth", head)
obj("EarL", sphere(0.032, (0.142, 0.0, 0.13), (0.5, 0.8, 1), 8, 6), "skin", head)
obj("EarR", sphere(0.032, (-0.142, 0.0, 0.13), (0.5, 0.8, 1), 8, 6), "skin", head)

def hair_cap(fringe=True):
    bm = sphere(0.157, (0, -0.012, 0.150), (1.0, 1.0, 0.98), 20, 14)
    bm = delete_verts(bm, lambda c: (c.z < 0.165 and c.y > 0.05) or c.z < 0.05 or (c.z < 0.115 and abs(c.x) > 0.11 and c.y > -0.02))
    if fringe:
        # a few locks over the forehead
        for k in range(5):
            x = -0.07 + k * 0.035
            bm = merge(bm, sphere(0.032, (x, 0.118, 0.215 - abs(x) * 0.35), (1.0, 0.6, 0.8), 8, 6))
    return bm
obj("Hair0", hair_cap(), "hair", head)                                                              # short
obj("Hair1", merge(hair_cap(False), sphere(0.068, (0, -0.135, 0.215), (1, 1, 1), 12, 8)), "hair", head)    # bun
obj("Hair2", merge(hair_cap(False), sphere(0.05, (0.115, -0.06, 0.06), (0.8, 1, 1.7), 10, 7),           # braids
                   sphere(0.042, (0.12, -0.06, -0.04), (0.8, 1, 1.6), 10, 7),
                   sphere(0.05, (-0.115, -0.06, 0.06), (0.8, 1, 1.7), 10, 7),
                   sphere(0.042, (-0.12, -0.06, -0.04), (0.8, 1, 1.6), 10, 7)), "hair", head)
long_back = sphere(0.15, (0, -0.06, 0.06), (1.05, 0.7, 1.35), 16, 10)
delete_verts(long_back, lambda c: c.y > 0.02)
obj("Hair3", merge(hair_cap(), long_back), "hair", head)                                            # long
pony = merge(hair_cap(False), sphere(0.04, (0, -0.15, 0.17), (1, 1, 1), 8, 6),
             sphere(0.045, (0, -0.19, 0.08), (0.85, 0.85, 1.6), 10, 7))
obj("Hair4", pony, "hair", head)                                                                    # ponytail
curls = hair_cap(False)
for k in range(18):
    a = k / 18 * math.tau
    y = math.sin(a) * 0.125 - 0.02
    z = 0.17 + 0.04 * math.cos(a * 3)
    if y > 0.06: z = 0.24                   # over the forehead the curls sit high, clear of the eyes
    curls = merge(curls, sphere(0.045, (math.cos(a) * 0.135, y, z), (1, 1, 1), 8, 6))
for k in range(6):
    a = k / 6 * math.tau
    curls = merge(curls, sphere(0.05, (math.cos(a) * 0.07, math.sin(a) * 0.07 - 0.02, 0.28), (1, 1, 1), 8, 6))
obj("Hair5", curls, "hair", head)                                                                   # curly
bald = sphere(0.152, (0, -0.02, 0.10), (1.0, 1.0, 0.75), 18, 10)
delete_verts(bald, lambda c: c.z > 0.12 or c.y > 0.04 or c.z < 0.02)
obj("Hair6", bald, "hair", head)                                                                    # balding, sides only
beard = sphere(0.10, (0, 0.085, 0.045), (1.15, 0.75, 0.95), 14, 9)
delete_verts(beard, lambda c: c.z > 0.085 and c.y > 0.13)
obj("Beard0", beard, "hair", head)                                                                  # full beard
obj("Beard1", merge(sphere(0.03, (0.022, 0.142, 0.085), (1.3, 0.6, 0.6), 8, 6),
                    sphere(0.03, (-0.022, 0.142, 0.085), (1.3, 0.6, 0.6), 8, 6)), "hair", head)     # moustache

# headwear (jobs) and a kerchief (personal)
straw = merge(cyl(0.265, 0.255, 0.0, 0.012, 24), cyl(0.125, 0.075, 0.0, 0.115, 18), ring(0.123, 0.025, 1.0, 0.013, 18))
obj("HatStraw", straw, "straw", head, (0, -0.005, 0.222))
cap = merge(delete_verts(sphere(0.163, (0, 0, 0.0), (1, 1, 0.75), 18, 10), lambda c: c.z < 0.0),
            box((0.17, 0.10, 0.012), (0, 0.155, 0.005)))
obj("HatCap", cap, "cloth", head, (0, -0.01, 0.18))
hood = delete_verts(sphere(0.18, (0, -0.02, 0.14), (1, 1.05, 1.05), 20, 14),
                    lambda c: c.y > 0.09 and c.z < 0.25 and c.z > 0.0)
hood = merge(hood, lathe([(-0.06, 0.165), (0.0, 0.125)], 18, sy=0.85))
obj("Hood", hood, "cloth", head, (0, 0, 0.0))
kerchief = delete_verts(sphere(0.162, (0, -0.012, 0.15), (1, 1, 1), 18, 12), lambda c: c.z < 0.13 or c.y > 0.06)
kerchief = merge(kerchief, sphere(0.04, (0, -0.15, 0.13), (1.2, 0.8, 0.8), 8, 6))
obj("Kerchief", kerchief, "kerchief", head)

# arms (pivot at the shoulder): sleeve with a cuff, hand with a thumb
arms = {}
for side, name in ((1, "ArmL"), (-1, "ArmR")):
    arm = obj(name, merge(lathe([(-0.25, 0.040), (-0.14, 0.042), (-0.05, 0.047), (0.0, 0.050)], 12),
                          sphere(0.049, (0, 0, -0.005), (1, 1, 0.85), 12, 8)), "tunic",
              torso, (0.150 * side, 0, 0.345))
    obj("Cuff" + name[-1], ring(0.043, -0.245, 1.0, 0.014, 12), "trim", arm)
    obj("Hand" + name[-1], merge(sphere(0.042, (0, 0.004, -0.30), (0.9, 1, 1.15), 10, 7),
                                 sphere(0.017, (-0.03 * side, 0.03, -0.285), (1, 1, 1.4), 6, 5)), "skin", arm)
    arms[side] = arm

# tools in the right hand (pivot at the grip, pointing along the arm)
GRIP = (0, 0.0, -0.30)
axe = obj("Axe", cyl(0.014, 0.014, -0.40, 0.06, 8), "wood", arms[-1], GRIP)
obj("AxeHead", merge(box((0.03, 0.12, 0.08), (0, 0.06, -0.37), 0.008),
                     box((0.012, 0.03, 0.12), (0, 0.13, -0.37))), "metal", axe)
pick = obj("Pick", cyl(0.014, 0.014, -0.42, 0.06, 8), "wood", arms[-1], GRIP)
pick_head = bmesh.new()
pts = [(-0.16, 0.035), (-0.05, 0.055), (0.0, 0.06), (0.05, 0.055), (0.16, 0.035)]
pick_head = merge(*[box((0.026, 0.07, 0.03), (0, y, -0.41 + dz * 0.6)) for y, dz in pts])
obj("PickHead", pick_head, "metal", pick)
hoe = obj("Hoe", cyl(0.013, 0.013, -0.55, 0.12, 8), "wood", arms[-1], GRIP)
obj("HoeHead", box((0.11, 0.09, 0.012), (0, 0.045, -0.555), 0.004), "metal", hoe)

rod = obj("Rod", cyl(0.012, 0.006, -0.95, 0.10, 8), "wood", arms[-1], GRIP)
obj("RodLine", cyl(0.0025, 0.0025, -0.95, -0.35, 4, "Z", (0, 0.0, 0.0)), "white", rod)

# carried goods (held in front with both arms)
carry = empty("Carry", torso, (0, 0.20, 0.20))
obj("CarryLog", merge(cyl(0.065, 0.06, -0.28, 0.28, 10, "X"),
                      cyl(0.045, 0.045, -0.20, 0.20, 9, "X", (0, 0.0, 0.10))), "log", carry)
obj("CarryStone", box((0.20, 0.17, 0.15), (0, 0, 0.02), 0.025), "stone", carry)
basket = merge(lathe([(-0.06, 0.10), (0.04, 0.13), (0.06, 0.135)], 14, sy=0.8),
               sphere(0.035, (0.04, 0.0, 0.07), (2.2, 0.8, 0.7), 8, 6),
               sphere(0.035, (-0.04, 0.02, 0.075), (2.2, 0.8, 0.7), 8, 6))
obj("CarryFish", basket, "straw", carry)
sack = sphere(0.12, (0, 0, 0.03), (1.05, 0.85, 1.0), 14, 9)
for v in sack.verts:
    if v.co.z > 0.1: v.co.x *= 0.55; v.co.y *= 0.55
obj("CarrySack", sack, "sack", carry)

# ---------------- export ----------------
bpy.ops.object.select_all(action="SELECT")
glb = os.path.join(OUT, "villager.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_yup=True)
print("exported", glb)

if PREVIEW:
    # lineup of variants for a quick look (posed copies)
    hide = {"Hair1", "Hair2", "Hair3", "Hair4", "Hair5", "Hair6", "Beard0", "Skirt", "SkirtTrim", "Vest", "Satchel", "Kerchief",
            "HatStraw", "HatCap", "Hood", "Axe", "Pick", "Hoe", "CarryLog", "CarryStone", "CarrySack"}
    for o in scene.objects:
        p = o
        while p is not None:
            if p.name in hide: o.hide_render = True
            p = p.parent
    arms[1].rotation_euler.x = -0.25; arms[-1].rotation_euler.x = 0.35
    scene.objects["LegL"].rotation_euler.x = 0.3; scene.objects["LegR"].rotation_euler.x = -0.3
    head.rotation_euler.z = 0.2
    bpy.ops.mesh.primitive_plane_add(size=6)
    g = bpy.context.object; g.data.materials.append(mat("g", (0.25, 0.32, 0.12)))
    w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.65, 0.8, 1)
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30)))
    bpy.context.object.data.energy = 3.5
    bpy.ops.object.camera_add(location=(1.15, 1.9, 1.05))
    cam = bpy.context.object; scene.camera = cam; cam.data.lens = 50
    cam.rotation_euler = (Vector((0, 0, 0.55)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.engine = "CYCLES"; scene.cycles.samples = 24; scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 700, 700
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = os.path.join(OUT, "villager_preview.png")
    bpy.ops.render.render(write_still=True)
