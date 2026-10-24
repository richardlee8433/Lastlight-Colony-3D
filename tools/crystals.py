"""Small crystal clusters that replace the meadow flowers on the alien world.

Run: python3 tools/crystals.py models
Writes models/crystal_a.glb (cyan) and models/crystal_b.glb (violet): 5-8 hexagonal shards with
pointed tips, slightly emissive, about 0.2-0.35 m tall. Origin at the base, Y up in Godot.
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "models")

def shard(bm, base, axis, length, r):
    axis = axis.normalized()
    t = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(t).normalized(); v = axis.cross(u).normalized()
    ring0 = []; ring1 = []
    for k in range(6):
        a = k / 6 * math.tau
        o = (u * math.cos(a) + v * math.sin(a)) * r
        ring0.append(bm.verts.new(base + o))
        ring1.append(bm.verts.new(base + o * 0.92 + axis * length * 0.78))
    tip = bm.verts.new(base + axis * length)
    for k in range(6):
        j = (k + 1) % 6
        bm.faces.new((ring0[k], ring0[j], ring1[j], ring1[k]))
        bm.faces.new((ring1[k], ring1[j], tip))
    bm.faces.new(list(reversed(ring0)))

def make(name, color, seed):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rnd = random.Random(seed)
    bm = bmesh.new()
    for k in range(rnd.randint(5, 8)):
        base = Vector((rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06), -0.02))
        axis = Vector((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 1.0))
        shard(bm, base, axis, rnd.uniform(0.12, 0.34), rnd.uniform(0.018, 0.035))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 0.15
    b.inputs["Emission Color"].default_value = (*color, 1)
    b.inputs["Emission Strength"].default_value = 0.6
    me.materials.append(m)
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True)
    print("exported", name)

make("crystal_a", (0.35, 0.85, 0.95), 1)
make("crystal_b", (0.62, 0.42, 0.95), 2)
