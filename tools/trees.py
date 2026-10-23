"""Builds the trees used in the game: broadleaf and pine variants with leaf-card crowns
(textures from tools/leaf_textures.py, drawn by the game's foliage shader) plus matching stumps.

Run: python3 tools/trees.py <models_dir> [stumps]     (add "stumps" to rebuild the stumps too; slow)
Writes <models_dir>/trees/{broadleaf_0..2, pine_0..1, stump_broadleaf, stump_pine}.glb
Trees are built 5.5 m tall at the origin; the game scales them to each tree's height.
"""
import os, sys, math, random, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
TREES_OUT = os.path.abspath(os.path.join(sys.argv[1] if len(sys.argv) > 1 else "models", "trees"))
os.makedirs(TREES_OUT, exist_ok=True)
STUMPS = "stumps" in sys.argv          # stumps reuse hut2's bark material: building that scene takes long
if STUMPS:
    sys.argv = ["hut2.py", tempfile.mkdtemp(), "build_only", "empty"]
    exec(compile(open(os.path.join(HERE, "hut2.py")).read(), "hut2.py", "exec"))
import bpy, bmesh
from mathutils import Vector
if not STUMPS:
    bpy.ops.wm.read_factory_settings(use_empty=True)

BASE_H = 5.5
scene = bpy.context.scene
scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"; scene.cycles.samples = 4

def clear_meshes():
    for o in list(bpy.data.objects):
        if o.type == "MESH": bpy.data.objects.remove(o)

def cut_wood():
    m = bpy.data.materials.new("cutwood"); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Object"], sep.inputs[0])
    ln = nt.nodes.new("ShaderNodeVectorMath"); ln.operation = "LENGTH"
    cmb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sep.outputs[0], cmb.inputs[0]); nt.links.new(sep.outputs[1], cmb.inputs[1])
    nt.links.new(cmb.outputs[0], ln.inputs[0])
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 60.0
    nt.links.new(ln.outputs["Value"], mul.inputs[0])
    sn = nt.nodes.new("ShaderNodeMath"); sn.operation = "SINE"; nt.links.new(mul.outputs[0], sn.inputs[0])
    rmp = nt.nodes.new("ShaderNodeValToRGB")
    rmp.color_ramp.elements[0].color = (0.42, 0.28, 0.13, 1); rmp.color_ramp.elements[1].color = (0.62, 0.45, 0.24, 1)
    nt.links.new(sn.outputs[0], rmp.inputs[0]); nt.links.new(rmp.outputs[0], b.inputs["Base Color"])
    return m

def stump(radius, seed):
    rr = random.Random(seed)
    h = 0.32
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=9, radius1=radius * 1.25, radius2=radius, depth=h)
    for v in bm.verts:
        if v.co.z > 0: v.co.z += rr.uniform(-0.03, 0.03)
    o = mesh_obj("trunk", bm, M["bark"]); o.location = (0, 0, h / 2)
    # cut face
    bm = bmesh.new(); bmesh.ops.create_circle(bm, cap_ends=True, segments=9, radius=radius * 0.93)
    c = mesh_obj("cut", bm, cut_wood()); c.location = (0, 0, h + 0.005)
    # roots
    for k in range(5):
        a = k * math.tau / 5 + rr.uniform(-0.3, 0.3)
        p0 = Vector((math.cos(a) * radius * 0.7, math.sin(a) * radius * 0.7, 0.14))
        p1 = Vector((math.cos(a) * radius * 2.3, math.sin(a) * radius * 2.3, -0.04))
        bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius * 0.32, radius2=radius * 0.1, depth=(p1 - p0).length)
        r = mesh_obj("root", bm, M["bark"])
        r.location = (p0 + p1) / 2
        r.rotation_euler = (p1 - p0).to_track_quat("Z", "Y").to_euler()

def finish(name):
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in scene.objects if o.type == "MESH"]
    for o in objs:
        if o.name.startswith("crown"):
            d = o.modifiers.new("dec", "DECIMATE"); d.ratio = 0.35
        o.hide_viewport = False; o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH"); bpy.ops.object.join()
    o = bpy.context.object; o.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for poly in o.data.polygons: poly.use_smooth = True
    ca = o.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER"); o.data.color_attributes.active_color = ca
    scene.render.bake.target = "VERTEX_COLORS"
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    vm = bpy.data.materials.new(name + "_vcol"); vm.use_nodes = True
    vb = vm.node_tree.nodes["Principled BSDF"]; vb.inputs["Roughness"].default_value = 0.85
    vc = vm.node_tree.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Col"
    vm.node_tree.links.new(vc.outputs["Color"], vb.inputs["Base Color"])
    o.data.materials.clear(); o.data.materials.append(vm)
    for poly in o.data.polygons: poly.material_index = 0
    bpy.ops.export_scene.gltf(filepath=os.path.join(TREES_OUT, name + ".glb"), export_format="GLB", use_selection=True, export_apply=True)
    print("exported", name, len(o.data.polygons), "faces")
    bpy.data.objects.remove(o)

# ---------------- leaf-card trees ----------------
# Crowns are built from many textured leaf cards (alpha-cut quads) instead of solid blobs, so the
# silhouette shows leaves and light filters through. Card normals point away from the crown centre,
# which shades the whole crown softly like one volume. The game swaps the "leaves_*" material for its
# foliage shader (wind, per-tree tint, scissor alpha).

def _mat_vcol(name):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]; b.inputs["Roughness"].default_value = 0.9
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    return m

def _basis(n):
    n = n.normalized()
    t = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = n.cross(t).normalized(); v = n.cross(u).normalized()
    return u, v

class CardMesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UV")
        self.col = self.bm.loops.layers.color.new("Col")
        self.normals = {}          # face index -> list of per-loop normals

    def face(self, pts, uvs, cols, nrms, mat):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = mat
        for lp, uv, c in zip(f.loops, uvs, cols):
            lp[self.uv].uv = uv
            lp[self.col] = (c[0], c[1], c[2], 1.0)
        self.normals[len(self.normals)] = (f, nrms)

    def tube(self, p0, p1, r0, r1, sides, col, mat=0, rnd=None):
        d = (p1 - p0); u, v = _basis(d)
        ring0 = []; ring1 = []
        for k in range(sides):
            a = k / sides * math.tau
            o = u * math.cos(a) + v * math.sin(a)
            ring0.append((p0 + o * r0, o)); ring1.append((p1 + o * r1, o))
        for k in range(sides):
            k2 = (k + 1) % sides
            pts = [ring0[k][0], ring0[k2][0], ring1[k2][0], ring1[k][0]]
            nrm = [ring0[k][1], ring0[k2][1], ring1[k2][1], ring1[k][1]]
            shade = 0.85 + 0.15 * (rnd.random() if rnd else 0.5)
            c = tuple(x * shade for x in col)
            self.face(pts, [(0, 0), (1, 0), (1, 1), (0, 1)], [c] * 4, nrm, mat)

    def build(self, name, mats):
        me = bpy.data.meshes.new(name)
        faces = [self.normals[i] for i in range(len(self.normals))]
        self.bm.to_mesh(me); self.bm.free()
        for m in mats: me.materials.append(m)
        if "Col" in me.color_attributes:
            me.color_attributes.active_color = me.color_attributes["Col"]
            me.color_attributes.render_color_index = me.color_attributes.find("Col")
        loop_n = []
        for poly, (f, nrms) in zip(me.polygons, faces):
            loop_n.extend(nrms)
        me.normals_split_custom_set([tuple(n.normalized()) for n in loop_n])
        o = bpy.data.objects.new(name, me); scene.collection.objects.link(o)
        return o

BARK = (0.26, 0.18, 0.11)

def card_broadleaf(seed, h=BASE_H):
    rnd = random.Random(seed)
    cm = CardMesh()
    s = h / 5.5
    trunk_top = 0.6 * h
    lean = Vector((rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25), 0)) * s
    # trunk in 4 segments with a slight bend
    pts = [Vector((0, 0, 0)) + lean * (t / 4) ** 2 + Vector((0, 0, trunk_top * t / 4)) for t in range(5)]
    for k in range(4):
        cm.tube(pts[k], pts[k + 1], 0.26 * s * (1 - 0.45 * k / 4), 0.26 * s * (1 - 0.45 * (k + 1) / 4), 8, BARK, 0, rnd)
    centre = Vector((lean.x, lean.y, 0.7 * h))
    rx, rz = 0.36 * h * rnd.uniform(0.9, 1.1), 0.27 * h
    clumps = []
    for k in range(rnd.randint(11, 14)):
        for _ in range(20):
            d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.8, 1)))
            if d.length <= 1.0: break
        d = d.normalized() * (0.45 + 0.55 * rnd.random() ** 0.5)
        clumps.append(centre + Vector((d.x * rx, d.y * rx, d.z * rz)))
    # branches to the clumps
    for c in clumps:
        t = rnd.uniform(0.6, 0.95)
        start = pts[0].lerp(pts[-1], t)
        end = start.lerp(c, 0.75)
        cm.tube(start, end, 0.08 * s, 0.035 * s, 5, BARK, 0, rnd)
    zmin = centre.z - rz; zmax = centre.z + rz
    for ci, c in enumerate(clumps):
        var = rnd.uniform(0.9, 1.08); hue = rnd.uniform(-0.05, 0.05)
        for k in range(rnd.randint(14, 19)):
            p = c + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.7, 0.7))) * 0.55 * s
            n = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.3, 1.2)))
            u, v = _basis(n)
            sz = rnd.uniform(1.0, 1.45) * s
            corners = [p - u * sz / 2 - v * sz / 2, p + u * sz / 2 - v * sz / 2, p + u * sz / 2 + v * sz / 2, p - u * sz / 2 + v * sz / 2]
            nrms = []; cols = []
            for q in corners:
                off = q - centre
                nn = Vector((off.x / rx, off.y / rx, off.z / rz)).normalized()
                nrms.append((nn * 0.85 + Vector((0, 0, 0.25))).normalized())
                h01 = max(0.0, min(1.0, (q.z - zmin) / (zmax - zmin)))
                inner = min(1.0, Vector((off.x / rx, off.y / rx, off.z / rz)).length)
                b = (0.62 + 0.45 * h01) * (0.72 + 0.28 * inner) * var
                cols.append((b * (1 + hue), b, b * (1 - hue)))
            cm.face(corners, [(0, 1), (1, 1), (1, 0), (0, 0)], cols, nrms, 1)
    return cm

def card_pine(seed, h=BASE_H):
    rnd = random.Random(seed)
    cm = CardMesh()
    s = h / 5.5
    lean = Vector((rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12), 0)) * s
    top = Vector((lean.x, lean.y, 0.98 * h))
    cm.tube(Vector((0, 0, 0)), top * 0.5, 0.17 * s, 0.11 * s, 7, BARK, 0, rnd)
    cm.tube(top * 0.5, top, 0.11 * s, 0.02 * s, 7, BARK, 0, rnd)
    tiers = 7
    for k in range(tiers):
        f = k / (tiers - 1)
        z = (0.2 + 0.72 * f) * h
        R = (0.36 - 0.27 * f) * h * rnd.uniform(0.92, 1.08)
        axis = Vector((lean.x * z / h, lean.y * z / h, z))
        for layer in range(2):
            n = max(7, int(14 - k * 1.2))
            off = rnd.uniform(0, math.tau) + layer * math.pi / n
            for i in range(n):
                a = off + i / n * math.tau + rnd.uniform(-0.1, 0.1)
                out = Vector((math.cos(a), math.sin(a), 0))
                side = Vector((-math.sin(a), math.cos(a), 0))
                w = math.tau * R / n * 1.5
                zz = z + layer * 0.12 * s
                inner = axis + out * 0.05 + Vector((0, 0, zz - z + 0.22 * s))
                outer = axis + out * R * rnd.uniform(0.9, 1.05) + Vector((0, 0, zz - z - 0.42 * R))
                corners = [inner - side * w * 0.18, inner + side * w * 0.18, outer + side * w * 0.5, outer - side * w * 0.5]
                nrm = (out * 0.75 + Vector((0, 0, 0.65))).normalized()
                b0 = (0.85 + 0.3 * f) * rnd.uniform(0.92, 1.06)
                cols = [(b0 * 0.85,) * 3, (b0 * 0.85,) * 3, (b0,) * 3, (b0,) * 3]
                cm.face(corners, [(0, 0), (1, 0), (1, 1), (0, 1)], cols, [nrm] * 4, 1)
    return cm

def finish_cards(cm, name, leaves):
    bark = _mat_vcol("bark")
    lm = _mat_vcol(leaves)            # the game replaces this material with its foliage shader
    o = cm.build(name, [bark, lm])
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=os.path.join(TREES_OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False)
    print("exported", name, len(o.data.polygons), "faces")
    bpy.data.objects.remove(o)

for i, seed in enumerate([611, 624, 637]):
    clear_meshes(); finish_cards(card_broadleaf(seed), f"broadleaf_{i}", "leaves_broad")
for i, seed in enumerate([652, 669]):
    clear_meshes(); finish_cards(card_pine(seed), f"pine_{i}", "leaves_pine")
if STUMPS:
    clear_meshes(); stump(0.22 * BASE_H / 5 * 0.82, 5); finish("stump_broadleaf")
    clear_meshes(); stump(0.15 * 0.95, 6); finish("stump_pine")
