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
HIP = 0.40
root = empty("Villager")

# legs (pivot at hip joint)
for side, name in ((1, "LegL"), (-1, "LegR")):
    leg = obj(name, lathe([(-0.36, 0.044), (-0.18, 0.05), (0.0, 0.06)], 10), "pants",
              root, (0.068 * side, 0, HIP))
    shoe = box((0.085, 0.14, 0.055), (0, 0.025, -0.375), bevel=0.02)
    obj("Shoe" + name[-1], shoe, "shoe", leg)

# torso / tunic (pivot at hips so it can lean forward)
torso = obj("Torso", lathe([(-0.10, 0.165), (-0.02, 0.152), (0.10, 0.125), (0.24, 0.14),
                            (0.33, 0.13), (0.38, 0.10), (0.42, 0.05)], 18, sy=0.78), "tunic",
            root, (0, 0, HIP))
belt = bmesh.new()
bmesh.ops.create_cone(belt, cap_ends=False, segments=18, radius1=0.132, radius2=0.128, depth=0.035)
for v in belt.verts: v.co.y *= 0.8
obj("Belt", belt, "belt", torso, (0, 0, 0.09))

# head (pivot at neck)
head = obj("Head", sphere(0.14, (0, 0.0, 0.13), (1.0, 0.97, 0.95), 18, 12), "skin", torso, (0, 0, 0.42))
for s, n in ((1, "EyeL"), (-1, "EyeR")):
    obj(n, sphere(0.017, (0.052 * s, 0.128, 0.145), (1, 0.6, 1.25), 8, 6), "eye", head)
obj("Nose", sphere(0.024, (0, 0.142, 0.112), (1, 0.8, 1), 8, 6), "skin", head)
obj("EarL", sphere(0.03, (0.137, 0.0, 0.125), (0.5, 0.8, 1), 8, 6), "skin", head)
obj("EarR", sphere(0.03, (-0.137, 0.0, 0.125), (0.5, 0.8, 1), 8, 6), "skin", head)

def hair_cap():
    bm = sphere(0.152, (0, -0.012, 0.145), (1.0, 1.0, 0.98), 18, 12)
    return delete_verts(bm, lambda c: (c.z < 0.15 and c.y > 0.04) or c.z < 0.045 or (c.z < 0.11 and abs(c.x) > 0.11 and c.y > -0.02))
obj("Hair0", hair_cap(), "hair", head)                                    # short
obj("Hair1", merge(hair_cap(), sphere(0.065, (0, -0.13, 0.20), (1, 1, 1), 12, 8)), "hair", head)   # bun
obj("Hair2", merge(hair_cap(), sphere(0.06, (0.11, -0.06, 0.06), (0.8, 1, 1.6), 10, 7),
                   sphere(0.06, (-0.11, -0.06, 0.06), (0.8, 1, 1.6), 10, 7)), "hair", head)          # side braids

# job headwear
straw = merge(cyl(0.255, 0.255, 0.0, 0.012, 20), cyl(0.12, 0.07, 0.0, 0.11, 16))
obj("HatStraw", straw, "straw", head, (0, -0.005, 0.215))
cap = merge(delete_verts(sphere(0.158, (0, 0, 0.0), (1, 1, 0.75), 16, 10), lambda c: c.z < 0.0),
            box((0.17, 0.10, 0.012), (0, 0.15, 0.005)))
obj("HatCap", cap, "cloth", head, (0, -0.01, 0.175))
hood = delete_verts(sphere(0.175, (0, -0.02, 0.14), (1, 1.05, 1.05), 18, 12),
                    lambda c: c.y > 0.09 and c.z < 0.25 and c.z > 0.0)
hood = merge(hood, lathe([(-0.06, 0.16), (0.0, 0.12)], 16, sy=0.85))
obj("Hood", hood, "cloth", head, (0, 0, 0.0))

# arms (pivot at shoulder) with hands
arms = {}
for side, name in ((1, "ArmL"), (-1, "ArmR")):
    arm = obj(name, merge(lathe([(-0.27, 0.036), (-0.12, 0.041), (0.0, 0.046)], 12),
                          sphere(0.05, (0, 0, 0.0), (1, 1, 1), 12, 8)), "tunic",
              torso, (0.152 * side, 0, 0.345))
    obj("Hand" + name[-1], sphere(0.042, (0, 0.0, -0.30), (1, 1, 1.1), 10, 7), "skin", arm)
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

# carried goods (held in front with both arms)
carry = empty("Carry", torso, (0, 0.20, 0.20))
obj("CarryLog", merge(cyl(0.065, 0.06, -0.28, 0.28, 10, "X"),
                      cyl(0.045, 0.045, -0.20, 0.20, 9, "X", (0, 0.0, 0.10))), "log", carry)
obj("CarryStone", box((0.20, 0.17, 0.15), (0, 0, 0.02), 0.025), "stone", carry)
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
    hide = {"Hair1", "Hair2", "HatStraw", "HatCap", "Hood", "Axe", "Pick", "Hoe", "CarryLog", "CarryStone", "CarrySack"}
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
