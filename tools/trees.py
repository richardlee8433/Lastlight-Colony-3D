"""Bakes the choppable trees used inside the map, in the same style as the scenery trees (hut2.py):
broadleaf and pine variants plus matching stumps. Foliage colour is baked to vertex colours.

Run: python3 tools/trees.py <models_dir>
Writes <models_dir>/trees/{broadleaf_0..2, pine_0..1, stump_broadleaf, stump_pine}.glb
Trees are built 5.5 m tall at the origin; the game scales them to each tree's height.
"""
import os, sys, math, random, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
TREES_OUT = os.path.abspath(os.path.join(sys.argv[1] if len(sys.argv) > 1 else "models", "trees"))
os.makedirs(TREES_OUT, exist_ok=True)
sys.argv = ["hut2.py", tempfile.mkdtemp(), "build_only", "empty"]
exec(compile(open(os.path.join(HERE, "hut2.py")).read(), "hut2.py", "exec"))
import bpy, bmesh
from mathutils import Vector

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

for i, seed in enumerate([611, 624, 637]):
    clear_meshes(); broadleaf((0, 0), BASE_H, seed); finish(f"broadleaf_{i}")
for i, seed in enumerate([652, 669]):
    clear_meshes(); pine((0, 0), BASE_H, seed); finish(f"pine_{i}")
clear_meshes(); stump(0.22 * BASE_H / 5 * 0.82, 5); finish("stump_broadleaf")
clear_meshes(); stump(0.15 * 0.95, 6); finish("stump_pine")
