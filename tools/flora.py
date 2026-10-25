"""Alien flora for Lastlight Colony, replacing the village trees under the same file names.

Run: python3 tools/flora.py <models_dir> [preview]
Writes <models_dir>/trees/{broadleaf_0..2, pine_0..1, stump_broadleaf, stump_pine}.glb
  broadleaf_0  umbrella fungus: a leaning pale stalk under a broad cap, glowing spore bulbs under the rim
  broadleaf_1  tube cluster: hollow tubes of different heights with glowing throats
  broadleaf_2  frond stalk: a ringed stalk with drooping ribbon fronds and hanging glow pods
  pine_0       spire: a twisted, ribbed spire with glowing nodules along the ribs
  pine_1       disc stack: a thin stalk with stacked plates, glowing rims
Flora is built 5.5 m tall at the origin (the game scales it per plant). Two materials: "flora" (shaded by
vertex colour x a per-plant tint in scripts/world/alien_flora.gdshader) and "flora_glow" (emissive parts).
Stumps use plain materials (they are instanced as scenes).
"""
import os, sys, math, random
import bpy, bmesh
from mathutils import Vector, Matrix

OUT = os.path.abspath(os.path.join(sys.argv[1] if len(sys.argv) > 1 else "models", "trees"))
PREVIEW = "preview" in sys.argv
os.makedirs(OUT, exist_ok=True)
H = 5.5

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def material(name, rgb=(0.8, 0.8, 0.8), emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = 0.6
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1); b.inputs["Emission Strength"].default_value = emit
    return m

def part(bm, mat, color_fn):
    """bmesh -> object with a per-corner colour attribute from color_fn(world co)."""
    me = bpy.data.meshes.new("p"); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("p", me); bpy.context.scene.collection.objects.link(o)
    me.materials.append(mat)
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    me.color_attributes.active_color = ca
    for poly in me.polygons:
        poly.use_smooth = True
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            c = color_fn(co)
            ca.data[li].color = (*c, 1.0)
    return o

def lerp3(a, b, t):
    t = max(0.0, min(1.0, t)); return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

def lathe(profile, segs=14, bend=(0.0, 0.0), twist=0.0, ribs=0, rib_amp=0.0, center=(0, 0, 0), close=(True, True)):
    """profile [(z, r)] bottom -> top. bend: (x, y) offset at the top (quadratic); ribs: radius ripples."""
    bm = bmesh.new(); rings = []
    ztop = max(z for z, _ in profile) or 1.0
    for z, r in profile:
        ring = []
        f = (z / ztop) ** 2 if ztop else 0
        for i in range(segs):
            a = math.tau * i / segs + twist * z
            rr = r * (1 + rib_amp * math.cos(ribs * (math.tau * i / segs))) if ribs else r
            ring.append(bm.verts.new((center[0] + math.cos(a) * rr + bend[0] * f, center[1] + math.sin(a) * rr + bend[1] * f, center[2] + z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    if close[0]: bm.faces.new(list(reversed(rings[0])))
    if close[1]: bm.faces.new(rings[-1])
    return bm

def sphere(r, c, scale=(1, 1, 1), segs=10):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs // 2 + 1), radius=r)
    for v in bm.verts: v.co = Vector((v.co.x * scale[0] + c[0], v.co.y * scale[1] + c[1], v.co.z * scale[2] + c[2]))
    return bm

def strip(points, widths, normal_fn, thick=0.03):
    """A ribbon along points (list of Vector) with the given half widths; normal_fn(i) -> side vector."""
    bm = bmesh.new(); left = []; right = []
    for i, p in enumerate(points):
        s = normal_fn(i) * widths[i]
        left.append(bm.verts.new(p - s)); right.append(bm.verts.new(p + s))
    for i in range(len(points) - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    return bm

def finish(name, flora=True):
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object; o.name = name
    # normalise to H tall (flora) so the game's scale = height / 5.5 holds
    if flora:
        top = max((o.matrix_world @ v.co).z for v in o.data.vertices)
        s = H / top; o.scale = (s, s, s)
        bpy.ops.object.transform_apply(scale=True)
    me = o.data
    if "Col" in me.color_attributes:
        me.color_attributes.active_color = me.color_attributes["Col"]
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False)
    print("exported", name, len(me.polygons), "faces")
    if PREVIEW: preview(os.path.join(OUT, f"_{name}_preview.png"))

def preview(path):
    scene = bpy.context.scene
    for m in bpy.data.materials:            # show vertex colours in the preview
        if not m.use_nodes or m.name.startswith("stump"): continue
        nt = m.node_tree; b = nt.nodes["Principled BSDF"]
        a = nt.nodes.new("ShaderNodeVertexColor"); a.layer_name = "Col"
        nt.links.new(a.outputs["Color"], b.inputs["Base Color"])
    w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.42, 0.38, 1)
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30))); bpy.context.object.data.energy = 3.5
    bpy.ops.mesh.primitive_plane_add(size=20); bpy.context.object.data.materials.append(material("g", (0.35, 0.18, 0.1)))
    bpy.ops.object.camera_add(location=(7, -9, 4.5)); cam = bpy.context.object; scene.camera = cam
    cam.rotation_euler = (Vector((0, 0, 2.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.engine = "CYCLES"; scene.cycles.samples = 16; scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 420, 420
    scene.view_settings.view_transform = "AgX"; scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

# ---------------- the plants ----------------
STALK_LO, STALK_HI = (0.42, 0.40, 0.46), (0.80, 0.78, 0.82)

def umbrella(seed=1):
    rnd = random.Random(seed)
    F = material("flora"); G = material("flora_glow", (0.6, 1.0, 0.9), 2.0)
    bend = (0.45, 0.15)
    prof = [(0.0, 0.34), (0.15, 0.26), (0.5, 0.2), (1.5, 0.17), (2.8, 0.15), (3.9, 0.14), (4.15, 0.2)]
    part(lathe(prof, 12, bend), F, lambda co: lerp3(STALK_LO, STALK_HI, co.z / 4.0))
    cx, cy = bend
    top = [(3.9, 1.85), (4.1, 1.75), (4.45, 1.45), (4.85, 1.0), (5.15, 0.5), (5.3, 0.05)]
    part(lathe(top, 24, center=(cx, cy, 0), close=(False, True)), F, lambda co: lerp3((0.82, 0.82, 0.86), (1.0, 1.0, 1.0), (co.z - 3.9) / 1.4))
    under = [(4.17, 0.2), (4.05, 0.9), (3.92, 1.6), (3.9, 1.85)]
    part(lathe(under, 24, center=(cx, cy, 0), close=(True, False)), F, lambda co: (0.30, 0.26, 0.34))
    # gill ridges under the cap
    for k in range(16):
        a = k * math.tau / 16
        p0 = Vector((cx + math.cos(a) * 0.25, cy + math.sin(a) * 0.25, 4.12)); p1 = Vector((cx + math.cos(a) * 1.75, cy + math.sin(a) * 1.75, 3.9))
        part(strip([p0, p1], [0.02, 0.02], lambda i: Vector((0, 0, 1)) * 2.0), F, lambda co: (0.22, 0.2, 0.26))
    # glowing spore bulbs hanging under the rim
    for k in range(9):
        a = k * math.tau / 9 + rnd.uniform(-0.2, 0.2); rr = rnd.uniform(1.2, 1.6)
        part(sphere(rnd.uniform(0.07, 0.11), (cx + math.cos(a) * rr, cy + math.sin(a) * rr, 3.75 - rnd.uniform(0, 0.25)), (1, 1, 1.3), 8), G, lambda co: (1, 1, 1))
    # a few young caps at the foot
    for k, (x, y, h, r) in enumerate([(0.55, -0.35, 0.7, 0.35), (-0.45, 0.4, 1.1, 0.45), (0.2, 0.6, 0.45, 0.22)]):
        part(lathe([(0, 0.07), (h * 0.9, 0.05), (h, 0.07)], 8, center=(x, y, 0)), F, lambda co: STALK_HI)
        part(lathe([(h * 0.92, r), (h * 1.05, r * 0.8), (h * 1.2, r * 0.4), (h * 1.26, 0.02)], 12, center=(x, y, 0)), F, lambda co: (0.95, 0.95, 0.97))

def tubes(seed=2):
    rnd = random.Random(seed)
    F = material("flora"); G = material("flora_glow", (0.6, 1.0, 0.9), 2.0)
    n = 8
    for k in range(n):
        a = k * math.tau / n + rnd.uniform(-0.3, 0.3); d = 0.0 if k == 0 else rnd.uniform(0.3, 0.75)
        x, y = math.cos(a) * d, math.sin(a) * d
        h = 5.5 if k == 0 else rnd.uniform(2.0, 4.8); r = rnd.uniform(0.14, 0.24) * (1.25 if k == 0 else 1.0)
        lean = (x * 0.5, y * 0.5)
        prof = [(0, r * 1.3), (0.2, r), (h * 0.5, r * 0.9), (h * 0.92, r * 1.05), (h, r * 1.45), (h - 0.02, r * 1.2)]
        part(lathe(prof, 12, lean, center=(x, y, 0), close=(True, False)), F,
             lambda co, h=h: lerp3((0.36, 0.33, 0.40), (0.98, 0.98, 1.0), co.z / h))
        # rings along the tube
        for z in [h * f for f in (0.3, 0.55, 0.75)]:
            f = (z / h) ** 2
            part(lathe([(z - 0.04, r * 1.12), (z + 0.04, r * 1.12)], 12, center=(x + lean[0] * f, y + lean[1] * f, 0)), F, lambda co: (0.5, 0.48, 0.55))
        part(lathe([(h - 0.25, r * 0.95), (h - 0.05, r * 1.1)], 12, center=(x + lean[0], y + lean[1], 0)), G, lambda co: (1, 1, 1))

def fronds(seed=3):
    rnd = random.Random(seed)
    F = material("flora"); G = material("flora_glow", (0.6, 1.0, 0.9), 2.0)
    bend = (-0.3, 0.2); h = 3.9
    prof = [(0, 0.3), (0.2, 0.22), (h * 0.5, 0.17), (h, 0.14)]
    part(lathe(prof, 10, bend), F, lambda co: lerp3(STALK_LO, STALK_HI, co.z / h))
    for z in [0.5 + i * 0.45 for i in range(7)]:
        f = (z / h) ** 2
        part(lathe([(z - 0.05, 0.2), (z + 0.03, 0.2)], 10, center=(bend[0] * f, bend[1] * f, 0)), F, lambda co: (0.35, 0.32, 0.38))
    top = Vector((bend[0], bend[1], h))
    for k in range(8):
        a = k * math.tau / 8 + rnd.uniform(-0.2, 0.2); L = rnd.uniform(2.0, 2.7)
        dirv = Vector((math.cos(a), math.sin(a), 0))
        pts = []; ws = []
        for i in range(10):
            t = i / 9
            pts.append(top + dirv * (t * L) + Vector((0, 0, 0.9 * math.sin(t * math.pi * 0.8) - 1.1 * t * t + 0.05)))
            ws.append(0.04 + 0.22 * math.sin(t * math.pi) * (1 - 0.3 * t))
        side = Vector((-math.sin(a), math.cos(a), 0))
        part(strip(pts, ws, lambda i: side), F, lambda co: (0.95, 0.95, 0.97))
    part(sphere(0.25, (top.x, top.y, top.z + 0.1), (1, 1, 0.8), 10), F, lambda co: (0.5, 0.46, 0.55))
    for k in range(6):
        a = k * math.tau / 6 + 0.3
        p = top + Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, -0.55 - rnd.uniform(0, 0.4)))
        part(strip([top + Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, -0.05)), p], [0.012, 0.012], lambda i: Vector((1, 0, 0))), F, lambda co: (0.4, 0.38, 0.42))
        part(sphere(0.11, (p.x, p.y, p.z - 0.08), (1, 1, 1.35), 8), G, lambda co: (1, 1, 1))

def spire(seed=4):
    rnd = random.Random(seed)
    F = material("flora"); G = material("flora_glow", (0.6, 1.0, 0.9), 2.0)
    prof = [(0, 0.75), (0.3, 0.62), (1.2, 0.5), (2.4, 0.38), (3.6, 0.25), (4.6, 0.14), (5.3, 0.05), (5.5, 0.01)]
    part(lathe(prof, 32, (0.15, -0.1), twist=0.55, ribs=7, rib_amp=0.22), F, lambda co: lerp3((0.38, 0.36, 0.44), (0.95, 0.95, 1.0), co.z / 5.0))
    # glowing nodules spiralling up along a rib
    for k in range(11):
        z = 0.5 + k * 0.42; r = 0.72 - z * 0.125
        a = 0.55 * z + (k % 2) * math.pi
        f = (z / 5.5) ** 2
        part(sphere(0.06 + 0.03 * (1 - z / 5.5), (math.cos(a) * r * 1.1 + 0.15 * f, math.sin(a) * r * 1.1 - 0.1 * f, z), (1, 1, 1), 8), G, lambda co: (1, 1, 1))
    # broken shards at the foot
    for k in range(4):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(0.7, 1.0)
        part(lathe([(0, 0.12), (rnd.uniform(0.5, 1.1), 0.01)], 6, (math.cos(a) * 0.2, math.sin(a) * 0.2), center=(math.cos(a) * d, math.sin(a) * d, 0)),
             F, lambda co: (0.6, 0.58, 0.66))

def discs(seed=5):
    rnd = random.Random(seed)
    F = material("flora"); G = material("flora_glow", (0.6, 1.0, 0.9), 2.0)
    part(lathe([(0, 0.25), (0.3, 0.14), (5.0, 0.1), (5.5, 0.05)], 10, (0.1, 0.05)), F, lambda co: lerp3(STALK_LO, STALK_HI, co.z / 5.0))
    n = 5
    for k in range(n):
        z = 1.4 + k * 0.9; r = 1.35 - k * 0.2
        f = (z / 5.5) ** 2; cx, cy = 0.1 * f, 0.05 * f
        tilt = rnd.uniform(-0.08, 0.08)
        prof = [(z - 0.06, 0.12), (z + 0.02, r * 0.6), (z + 0.08, r), (z + 0.12, r * 0.97), (z + 0.1, r * 0.55), (z + 0.08, 0.1)]
        o = part(lathe(prof, 26, center=(cx, cy, 0)), F, lambda co, z=z: lerp3((0.6, 0.58, 0.66), (0.98, 0.98, 1.0), (co.z - z + 0.06) / 0.2))
        g = part(lathe([(z + 0.07, r * 1.0), (z + 0.12, r * 1.03)], 26, center=(cx, cy, 0)), G, lambda co: (1, 1, 1))

def stump(name, kind):
    reset()
    S = material("stump_side", (0.30, 0.28, 0.34)); C = material("stump_cut", (0.78, 0.86, 0.80), 0.6)
    rr = random.Random(7 + kind)
    r = 0.22 if kind == 0 else 0.45
    bm = lathe([(0, r * 1.5), (0.1, r * 1.1), (0.3, r)], 12 if kind == 0 else 20, ribs=7 if kind else 0, rib_amp=0.15 if kind else 0, close=(True, False))
    o = part(bm, S, lambda co: (1, 1, 1))
    bm = bmesh.new(); bmesh.ops.create_circle(bm, cap_ends=True, segments=12, radius=r * 0.95)
    for v in bm.verts: v.co.z = 0.3 + rr.uniform(-0.03, 0.03)
    part(bm, C, lambda co: (1, 1, 1))
    finish(name, flora=False)

JOBS = [("broadleaf_0", umbrella), ("broadleaf_1", tubes), ("broadleaf_2", fronds), ("pine_0", spire), ("pine_1", discs)]
if __name__ == "__main__":
    only = [a for a in sys.argv[2:] if a != "preview"]
    for name, fn in JOBS:
        if only and name not in only: continue
        reset(); fn(); finish(name)
    if not only or "stumps" in only:
        stump("stump_broadleaf", 0); stump("stump_pine", 1)
