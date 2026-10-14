"""Build the hut scene, bake procedural materials to textures, export a Godot-ready set.
Run: python3 bake_export.py <godot_project_dir>
"""
import sys, os, json, math, bpy
from mathutils import Matrix, Vector

PROJ = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "godot_hut")
MODELS = os.path.join(PROJ, "models"); TEX = os.path.join(PROJ, "textures"); DATA = os.path.join(PROJ, "data")
for d in (MODELS, TEX, DATA): os.makedirs(d, exist_ok=True)
FAST = "fast" in sys.argv

EMPTY_MAP = "empty" in sys.argv
NATURE_ONLY_FLAG = "nature_only" in sys.argv     # only re-export nature.glb (skip hut/props/ground bakes)
sys.argv = ["hut2.py", os.path.join(PROJ, "_tmp"), "build_only"] + (["empty"] if EMPTY_MAP else [])
exec(compile(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "hut2.py")).read(), "hut2.py", "exec"))

scene = bpy.context.scene
C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))   # Blender Z-up -> glTF/Godot Y-up

# ---------- 1. scatter instances -> JSON for Godot MultiMesh ----------
srcs = {tuft.data.name: "tuft"}
for o in bpy.data.objects:
    if o.name.startswith("flower_src_"):
        srcs[o.data.name] = o.name.replace("flower_src_", "flower_")
dg = bpy.context.evaluated_depsgraph_get()
scatter = {k: [] for k in srcs.values()}
for inst in dg.object_instances:
    if not inst.is_instance: continue
    key = srcs.get(getattr(inst.object.data, "name", None))
    if not key: continue
    m = C @ inst.matrix_world @ C.transposed()
    cols = [m.col[i][:3] for i in range(3)]
    row = [round(v, 3) for col in cols for v in col] + [round(v, 3) for v in m.translation]
    scatter[key].append(row)
with open(os.path.join(DATA, "scatter.json"), "w") as f:
    json.dump(scatter, f, separators=(",", ":"))
print({k: len(v) for k, v in scatter.items()})

# scene info: sun direction, camera
sun_obj = [o for o in scene.objects if o.type == "LIGHT"][0]
sun_dir_b = (sun_obj.matrix_world.to_3x3() @ Vector((0, 0, -1))).normalized()
sun_dir_g = (C.to_3x3() @ sun_dir_b)
with open(os.path.join(DATA, "scene.json"), "w") as f:
    json.dump({"sun_dir": list(sun_dir_g)}, f)

# ---------- 2. export scatter source meshes with simple flat materials ----------
def flat(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    return m
def export_single(obj, path):
    obj.hide_viewport = False; obj.hide_render = False; obj.location = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)

g_blade = flat("blade_flat", (1, 1, 1))
tuft.data.materials.clear(); tuft.data.materials.append(g_blade)
export_single(tuft, os.path.join(MODELS, "tuft.glb"))
stem_mat = flat("stem_flat", (0.07, 0.13, 0.02))
for o in [o for o in bpy.data.objects if o.name.startswith("flower_src_")]:
    for i, sl in enumerate(o.material_slots):
        if sl.material and sl.material.name.startswith("blade"): sl.material = stem_mat
    export_single(o, os.path.join(MODELS, o.name.replace("flower_src_", "flower_") + ".glb"))

# remove scatter modifiers and sources so they don't get baked
for md in list(ground.modifiers):
    if md.type == "NODES": ground.modifiers.remove(md)
for o in list(bpy.data.objects):
    if o.name.startswith("flower_src_") or o.name == "tuft_src" or o.name.startswith("fl_"):
        bpy.data.objects.remove(o)

# ---------- 3. group objects ----------
NATURE_PREFIX = ("trunk", "crown", "pine", "bush", "Icosphere", "rock")
hut_objs = [o for o in hut_col.objects if o.type == "MESH"]
others = [o for o in scene.objects if o.type == "MESH" and o not in hut_objs and o != ground]
nature = [o for o in others if o.name.startswith(NATURE_PREFIX)]
# trees inside the playable map are separate models in the game (tools/trees.py) so they can be chopped
def in_map_tree(o):
    # every tree is drawn by the game: choppable trees inside the map (tools/trees.py models) and the
    # border forest outside it (instanced from the same models, positions in world.json)
    return o.get("tree") is not None
drop = [o for o in others if in_map_tree(o)]
nature = [o for o in nature if o not in drop]
others = [o for o in others if o not in drop]
for o in drop:
    bpy.data.objects.remove(o)
props = [o for o in others if o not in nature]
NATURE_ONLY = NATURE_ONLY_FLAG

def join_group(objs, name, decimate=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        if decimate and o.name.startswith(decimate[0]):
            d = o.modifiers.new("dec", "DECIMATE"); d.ratio = decimate[1]
        o.hide_viewport = False; o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    o = bpy.context.object; o.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # uv unwrap
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    return o

scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"
scene.cycles.samples = 1 if FAST else 4
scene.render.bake.margin = 6

def bake(obj, tex_name, size, kinds=("DIFFUSE", "NORMAL")):
    imgs = {}
    for kind in kinds:
        img = bpy.data.images.new(f"{tex_name}_{kind.lower()}", size, size, alpha=False,
                                  float_buffer=False, is_data=(kind == "NORMAL"))
        if kind == "NORMAL": img.colorspace_settings.name = "Non-Color"
        for sl in obj.material_slots:
            nt = sl.material.node_tree
            for n in [n for n in nt.nodes if n.name.startswith("BAKE")]: nt.nodes.remove(n)
            n = nt.nodes.new("ShaderNodeTexImage"); n.name = "BAKE"; n.image = img
            nt.nodes.active = n
        bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
        if kind == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_clear=True)
        path = os.path.join(TEX, f"{img.name}.png")
        img.filepath_raw = path; img.file_format = "PNG"; img.save()
        imgs[kind] = img
        print("baked", img.name)
    # replace with a single texture material
    m = bpy.data.materials.new(tex_name + "_baked"); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]; b.inputs["Roughness"].default_value = 0.9
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = imgs["DIFFUSE"]; nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if "NORMAL" in imgs:
        tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = imgs["NORMAL"]
        nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    obj.data.materials.clear(); obj.data.materials.append(m)
    for p in obj.data.polygons: p.material_index = 0
    return obj

def export(obj, fname):
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODELS, fname), export_format="GLB", use_selection=True,
                              export_apply=True, export_image_format="AUTO")
    print("exported", fname, len(obj.data.polygons), "faces")

S = 1024 if FAST else 2048
if hut_objs and not NATURE_ONLY:
    hut = join_group(hut_objs, "hut")
    export(bake(hut, "hut", S if FAST else 4096), "hut.glb")
if props and not NATURE_ONLY:
    pr = join_group(props, "props")
    export(bake(pr, "props", S // 2 if FAST else 1024), "props.glb")
na = join_group(nature, "nature", decimate=("crown", 0.35))
for poly in na.data.polygons: poly.use_smooth = True
# foliage: bake to vertex colours (dense meshes, avoids UV bleeding)
ca = na.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
na.data.color_attributes.active_color = ca
scene.render.bake.target = "VERTEX_COLORS"
bpy.ops.object.select_all(action="DESELECT"); na.select_set(True); bpy.context.view_layer.objects.active = na
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
scene.render.bake.target = "IMAGE_TEXTURES"
vm = bpy.data.materials.new("nature_vcol"); vm.use_nodes = True
vb = vm.node_tree.nodes["Principled BSDF"]; vb.inputs["Roughness"].default_value = 0.85
vc = vm.node_tree.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Col"
vm.node_tree.links.new(vc.outputs["Color"], vb.inputs["Base Color"])
na.data.materials.clear(); na.data.materials.append(vm)
for poly in na.data.polygons: poly.material_index = 0
export(na, "nature.glb")

if NATURE_ONLY:
    print("ALL DONE (nature only)"); sys.exit(0)
# ground: planar UVs, diffuse only
for md in list(ground.modifiers): ground.modifiers.remove(md)
me = ground.data
uv = me.uv_layers.new(name="UV")
half = GROUND_HALF
for loop in me.loops:
    co = me.vertices[loop.vertex_index].co
    uv.data[loop.index].uv = (co.x / (2 * half) + 0.5, co.y / (2 * half) + 0.5)
export(bake(ground, "ground", 2 * S, kinds=("DIFFUSE",)), "ground.glb")
print("ALL DONE")
