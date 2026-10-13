"""Exports navigation data for the scene built by hut2.py (Godot coordinates).

Run: python3 tools/export_world_data.py data/world.json

Output:
  cell, origin, w, h   walk grid (0.5 m cells, x/z)
  blocked              indices of cells blocked by scenery (walls, fences, trunks, rocks, bushes...)
  height               ground height per cell
  trees                [[x, z, trunk_radius], ...]  (targets for woodcutters)
"""
import sys, os, json, math
from collections import defaultdict
import bpy
from mathutils import Vector

OUT_PATH = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "world.json")
HERE = os.path.dirname(os.path.abspath(__file__))
import tempfile
sys.argv = ["hut2.py", tempfile.mkdtemp(), "build_only"] + (["empty"] if "empty" in sys.argv else [])
exec(compile(open(os.path.join(HERE, "hut2.py")).read(), "hut2.py", "exec"))

CELL = 0.5
HALF = 17.0
W = H = int(2 * HALF / CELL)
BAND = (0.12, 1.25)          # only geometry at walking height blocks
SKIP = ("ground", "tuft_src", "flower_src", "fl_", "crown", "Camera", "Light")

def to_g(v):  # blender -> godot (x, y_up, z)
    return (v.x, v.z, -v.y)

def cell_of(x, z):
    i = int(math.floor((x + HALF) / CELL)); j = int(math.floor((z + HALF) / CELL))
    if 0 <= i < W and 0 <= j < H: return j * W + i
    return None

blocked = set()
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.context.scene.objects:
    if o.type != "MESH" or o.name.startswith(SKIP) or o.hide_render:
        continue
    eo = o.evaluated_get(dg)
    me = eo.to_mesh()
    mw = o.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    for e in me.edges:
        a, b = verts[e.vertices[0]], verts[e.vertices[1]]
        L = (b - a).length
        n = max(1, int(L / 0.12))
        for k in range(n + 1):
            p = a.lerp(b, k / n)
            if BAND[0] <= p.z <= BAND[1]:
                c = cell_of(p.x, -p.y)
                if c is not None: blocked.add(c)
    # faces: sample centres too, so wide flat-ish shapes (rocks, step stones) block
    for poly in me.polygons:
        p = mw @ poly.center
        if BAND[0] <= p.z <= BAND[1]:
            c = cell_of(p.x, -p.y)
            if c is not None: blocked.add(c)
    eo.to_mesh_clear()

# ground heights
hs = defaultdict(float); hn = defaultdict(int)
gw = ground.matrix_world
for v in ground.data.vertices:
    p = gw @ v.co
    c = cell_of(p.x, -p.y)
    if c is not None:
        hs[c] += p.z; hn[c] += 1
height = [round(hs[c] / hn[c], 3) if hn[c] else 0.0 for c in range(W * H)]

trees = []
for o in bpy.context.scene.objects:
    if o.name.startswith("trunk"):
        x, _, z = to_g(o.location)
        if abs(x) < HALF - 0.5 and abs(z) < HALF - 0.5:
            trees.append([round(x, 2), round(z, 2), round(o.dimensions.x / 2, 2)])

data = {"cell": CELL, "origin": [-HALF, -HALF], "w": W, "h": H,
        "blocked": sorted(blocked), "height": height, "trees": trees}
with open(OUT_PATH, "w") as f:
    json.dump(data, f, separators=(",", ":"))
print("blocked", len(blocked), "of", W * H, "trees", len(trees))
# ascii map for a quick sanity check
for j in range(0, H, 2):
    print("".join("#" if (j * W + i) in blocked else "." for i in range(0, W)))
