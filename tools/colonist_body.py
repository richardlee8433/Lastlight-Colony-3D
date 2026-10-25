# ---------------- colonist body (realistic proportions, EVA-style pressure suit) ----------------
# Included by tools/colonist.py after the shared helpers from tools/villager.py.
# About 1.3 m tall in game units (the world is built at this scale). Same node names and pivots as the
# old villager, so scripts/world/villager.gd animates and tints it unchanged:
#   Torso (pivot hips), Head (pivot neck), ArmL/ArmR (shoulders), LegL/LegR (hips), tools on ArmR at the
#   grip, Carry in front of the chest, optional pieces shown per look / job.
M["dark"] = mat("dark", (0.06, 0.065, 0.07), 0.5)
M["joint"] = mat("joint", (0.42, 0.43, 0.45), 0.4)
M["gold"] = mat("gold", (0.85, 0.62, 0.22), 0.15)
HIP = 0.628
root = empty("Villager")

def ring(r, z, sy=1.0, thick=0.012, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=segs, radius1=r, radius2=r * 0.98, depth=thick * 2)
    for v in bm.verts: v.co.y *= sy; v.co.z += z
    return bm

def torus(R, r, center=(0, 0, 0), axis="Z", sy=1.0):
    bm = bmesh.new()
    segs, ring_n = 20, 8
    rows = []
    for i in range(segs):
        a = math.tau * i / segs; row = []
        for j in range(ring_n):
            b = math.tau * j / ring_n
            x = (R + r * math.cos(b)) * math.cos(a); y = (R + r * math.cos(b)) * math.sin(a) * sy; z = r * math.sin(b)
            row.append(bm.verts.new((x, y, z)))
        rows.append(row)
    for i in range(segs):
        for j in range(ring_n):
            bm.faces.new((rows[i][j], rows[(i + 1) % segs][j], rows[(i + 1) % segs][(j + 1) % ring_n], rows[i][(j + 1) % ring_n]))
    if axis == "X": bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    if axis == "Y": bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(center))
    return bm

# legs: suit trousers with a knee bearing and pad, chunky EVA boots (pivot at the hip joint)
for side, name in ((1, "LegL"), (-1, "LegR")):
    leg = obj(name, lathe([(-0.47, 0.050), (-0.40, 0.050), (-0.33, 0.056), (-0.30, 0.060), (-0.27, 0.058),
                           (-0.17, 0.064), (-0.06, 0.072), (0.0, 0.076)], 14), "pants", root, (0.078 * side, 0, HIP))
    obj("Knee" + name[-1], merge(sphere(0.045, (0, 0.045, -0.30), (1.0, 0.6, 1.1), 10, 7),
                                 torus(0.061, 0.007, (0, 0, -0.22))), "belt", leg)
    boot = merge(lathe([(-0.585, 0.064), (-0.55, 0.062), (-0.50, 0.061), (-0.465, 0.058)], 14),
                 box((0.105, 0.20, 0.075), (0, 0.035, -0.58), bevel=0.03),
                 box((0.115, 0.215, 0.025), (0, 0.035, -0.616), bevel=0.008),
                 torus(0.06, 0.008, (0, 0, -0.47)))
    obj("Shoe" + name[-1], boot, "shoe", leg)

# torso (pivot at the hips): suit body, hard upper-torso shell, waist bearing, belt
torso = obj("Torso", lathe([(-0.06, 0.128), (0.0, 0.124), (0.06, 0.118), (0.12, 0.120), (0.20, 0.135), (0.27, 0.148),
                            (0.32, 0.150), (0.36, 0.140), (0.39, 0.112), (0.41, 0.075)], 24, sy=0.72), "tunic",
            root, (0, 0, HIP))
obj("Hem", lathe([(-0.13, 0.122), (-0.07, 0.131), (-0.03, 0.130)], 24, sy=0.76), "tunic", torso)        # pelvis / brief
obj("HemTrim", ring(0.132, -0.045, 0.76, 0.01, 24), "trim", torso)
hut = lathe([(0.19, 0.142), (0.25, 0.156), (0.31, 0.160), (0.355, 0.150), (0.385, 0.124)], 28, sy=0.76)
obj("Chest", hut, "case", torso)                                                                       # hard upper torso
belt = bmesh.new()
bmesh.ops.create_cone(belt, cap_ends=False, segments=24, radius1=0.127, radius2=0.125, depth=0.035)
for v in belt.verts: v.co.y *= 0.74
obj("Belt", belt, "belt", torso, (0, 0, 0.05))
obj("Buckle", merge(box((0.05, 0.015, 0.03), (0, 0.094, 0.05), 0.004), box((0.035, 0.02, 0.045), (0.07, 0.085, 0.05), 0.006),
                    box((0.035, 0.02, 0.045), (-0.07, 0.085, 0.05), 0.006)), "metal", torso)                # tool pouches
obj("Collar", merge(torus(0.078, 0.014, (0, 0, 0.41)), ring(0.092, 0.398, 0.95, 0.008, 20)), "trim", torso)  # neck ring
obj("Waist", torus(0.121, 0.008, (0, 0, 0.12), sy=0.72), "joint", torso)
# optional layers: chest display (Apron), harness straps (Vest), life-support pack (Satchel)
dcm = merge(box((0.15, 0.05, 0.085), (0, 0.13, 0.24), 0.012), box((0.12, 0.012, 0.05), (0, 0.157, 0.245), 0.004))
obj("Apron", dcm, "case", torso)
obj("ApronKeys", merge(*[box((0.016, 0.01, 0.012), (-0.04 + i * 0.027, 0.164, 0.235 - (i % 2) * 0.018), 0.003) for i in range(4)]), "orange", torso)
straps = merge(box((0.035, 0.012, 0.30), (0.06, 0.112, 0.24), 0.004), box((0.035, 0.012, 0.30), (-0.06, 0.112, 0.24), 0.004),
               box((0.035, 0.012, 0.30), (0.06, -0.112, 0.24), 0.004), box((0.035, 0.012, 0.30), (-0.06, -0.112, 0.24), 0.004),
               box((0.18, 0.012, 0.03), (0, 0.113, 0.17), 0.004))
obj("Vest", straps, "vest", torso)
plss = merge(box((0.25, 0.12, 0.33), (0, -0.175, 0.25), 0.03), box((0.21, 0.10, 0.06), (0, -0.175, 0.44), 0.02),
             cyl(0.03, 0.03, 0.12, 0.40, 10, "Z", (0.115, -0.24, 0)), cyl(0.03, 0.03, 0.12, 0.40, 10, "Z", (-0.115, -0.24, 0)))
satchel = obj("Satchel", plss, "case", torso)
obj("SatchelLight", merge(box((0.05, 0.012, 0.02), (0.06, -0.237, 0.36), 0.004), box((0.05, 0.012, 0.02), (-0.06, -0.237, 0.36), 0.004)), "orange", satchel)
obj("SatchelHose", merge(cyl(0.012, 0.012, -0.12, 0.10, 8, "Y", (-0.135, 0.0, 0.30)),
                         cyl(0.012, 0.012, -0.12, 0.10, 8, "Y", (0.135, 0.0, 0.30))), "dark", satchel)

# head (pivot at the neck): adult proportions, a calm face (eyes blink), short hair under the helmet
neck = obj("Neck", cyl(0.042, 0.040, 0.0, 0.06, 12), "skin", torso)
head = obj("Head", sphere(0.082, (0, 0.006, 0.115), (0.88, 0.97, 1.12), 22, 16), "skin", torso, (0, 0, 0.41))
obj("Jaw", sphere(0.062, (0, 0.028, 0.072), (0.95, 0.9, 0.8), 14, 10), "skin", head)
for s_, n in ((1, "EyeL"), (-1, "EyeR")):
    e = obj(n, sphere(0.0105, (0, 0, 0), (1.15, 0.5, 0.75), 10, 8), "eye", head, (0.029 * s_, 0.078, 0.128))
    obj("Glint" + n[-1], sphere(0.003, (0.003, 0.004, 0.003), (1, 0.6, 1), 6, 5), "white", e)
for s_, n in ((1, "BrowL"), (-1, "BrowR")):
    br = box((0.028, 0.008, 0.006), (0, 0, 0), 0.002)
    bmesh.ops.rotate(br, verts=br.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-0.1 * s_, 3, "Y"))
    obj(n, br, "hair", head, (0.03 * s_, 0.082, 0.146))
obj("Nose", merge(sphere(0.013, (0, 0.088, 0.108), (0.85, 0.9, 1.5), 8, 6), sphere(0.011, (0, 0.091, 0.094), (1.2, 0.9, 0.8), 8, 6)), "skin", head)
obj("Mouth", box((0.03, 0.006, 0.004), (0, 0.083, 0.072), 0.002), "mouth", head)
obj("EarL", sphere(0.018, (0.074, 0.0, 0.115), (0.45, 0.8, 1.2), 8, 6), "skin", head)
obj("EarR", sphere(0.018, (-0.074, 0.0, 0.115), (0.45, 0.8, 1.2), 8, 6), "skin", head)

def hair_cap(extra=None):
    bm = sphere(0.088, (0, -0.004, 0.124), (0.92, 1.0, 1.1), 20, 14)
    bm = delete_verts(bm, lambda c: (c.z < 0.15 and c.y > 0.035) or c.z < 0.07 or (c.z < 0.11 and abs(c.x) > 0.06 and c.y > -0.02))
    return merge(bm, extra) if extra else bm
obj("Hair0", hair_cap(), "hair", head)                                                       # short
obj("Hair1", hair_cap(sphere(0.03, (0, -0.085, 0.15), (1, 1, 1), 10, 7)), "hair", head)       # tied back
for k in (2, 3, 4):
    obj(f"Hair{k}", hair_cap(), "hair", head)
curls = hair_cap()
for k in range(14):
    a = k / 14 * math.tau
    if math.sin(a) > 0.5: continue
    curls = merge(curls, sphere(0.022, (math.cos(a) * 0.075, math.sin(a) * 0.08 - 0.005, 0.15 + 0.02 * math.cos(a * 3)), (1, 1, 1), 6, 5))
obj("Hair5", curls, "hair", head)                                                            # curly
bald = sphere(0.086, (0, -0.006, 0.115), (0.93, 1.0, 1.0), 18, 10)
delete_verts(bald, lambda c: c.z > 0.13 or c.y > 0.02 or c.z < 0.07)
obj("Hair6", bald, "hair", head)                                                             # cropped sides
beard = sphere(0.058, (0, 0.04, 0.065), (1.0, 0.75, 0.85), 12, 8)
delete_verts(beard, lambda c: c.z > 0.08 and c.y > 0.07)
obj("Beard0", beard, "hair", head)
obj("Beard1", merge(sphere(0.012, (0.012, 0.087, 0.083), (1.4, 0.6, 0.55), 8, 6), sphere(0.012, (-0.012, 0.087, 0.083), (1.4, 0.6, 0.55), 8, 6)), "hair", head)

# EVA helmet: hard shell with ear pods and a wide visor opening, glass bubble (transparent in Godot)
HC = (0, 0.008, 0.118)
shell = sphere(0.135, (0, -0.004, 0.118), (1.0, 1.02, 1.05), 26, 18)
delete_verts(shell, lambda c: c.y > 0.035 and 0.03 < c.z < 0.205 and abs(c.x) < 0.112)
shell = merge(shell, cyl(0.035, 0.035, -0.02, 0.02, 14, "X", (0.13, -0.01, 0.12)), cyl(0.035, 0.035, -0.02, 0.02, 14, "X", (-0.13, -0.01, 0.12)),
              torus(0.128, 0.012, (0, 0, -0.005)))
helmet = obj("Helmet", shell, "case", head)
glass = sphere(0.131, HC, (0.97, 1.02, 1.04), 26, 18)
delete_verts(glass, lambda c: c.y < 0.03 or c.z > 0.212 or c.z < 0.022)
obj("HelmetGlass", glass, "visor", helmet)
obj("HelmetRing", merge(torus(0.082, 0.016, (0, 0, 0.432)), ring(0.096, 0.418, 0.95, 0.01, 20)), "joint", torso)
straw = sphere(0.145, (0, -0.004, 0.118), (1.02, 1.1, 1.05), 22, 14)
delete_verts(straw, lambda c: c.z < 0.2 or c.y < -0.04)
straw = merge(straw, cyl(0.004, 0.0025, 0.2, 0.42, 5, "Z", (-0.08, -0.06, 0.0)), sphere(0.009, (-0.08, -0.06, 0.42), (1, 1, 1), 6, 5))
obj("HatStraw", straw, "straw", head)                                                          # sun-shade peak + whip antenna
cap = merge(box((0.035, 0.05, 0.035), (0.1, 0.065, 0.205), 0.008), box((0.035, 0.05, 0.035), (-0.1, 0.065, 0.205), 0.008),
            box((0.026, 0.2, 0.022), (0, -0.01, 0.262), 0.006))
hatcap = obj("HatCap", cap, "cloth", head)                                                     # lamp housings + crest
obj("CapLamp", merge(cyl(0.015, 0.015, 0.0, 0.008, 10, "Y", (0.1, 0.09, 0.205)), cyl(0.015, 0.015, 0.0, 0.008, 10, "Y", (-0.1, 0.09, 0.205))), "white", hatcap)
hood = sphere(0.1355, HC, (0.98, 1.03, 1.05), 26, 18)
delete_verts(hood, lambda c: c.y < 0.03 or c.z > 0.214 or c.z < 0.07)
obj("Hood", hood, "visor", head)                                                               # gold sun visor pulled down
kerchief = merge(box((0.02, 0.035, 0.03), (0.155, -0.03, 0.15), 0.006), cyl(0.0035, 0.002, 0.15, 0.33, 5, "Z", (0.16, -0.04, 0.0)))
obj("Kerchief", kerchief, "kerchief", head)                                                    # comm antenna

# arms (pivot at the shoulder): shoulder bearing, elbow, wrist ring, glove
ARM = 0.50
arms = {}
for side, name in ((1, "ArmL"), (-1, "ArmR")):
    arm = obj(name, merge(lathe([(-0.455, 0.034), (-0.40, 0.037), (-0.30, 0.042), (-0.255, 0.046), (-0.22, 0.048),
                                 (-0.10, 0.053), (0.0, 0.057)], 12),
                          sphere(0.062, (0, 0, -0.005), (1, 1, 0.9), 14, 9)), "tunic", torso, (0.172 * side, 0, 0.35))
    obj("Shoulder" + name[-1], torus(0.06, 0.008, (0, 0, -0.035)), "joint", arm)
    obj("Elbow" + name[-1], torus(0.046, 0.006, (0, 0, -0.255)), "joint", arm)
    obj("Cuff" + name[-1], merge(torus(0.038, 0.009, (0, 0, -0.455)), ring(0.041, -0.44, 1.0, 0.012, 14)), "trim", arm)
    obj("Hand" + name[-1], merge(sphere(0.036, (0, 0.006, -0.495), (0.75, 0.95, 1.2), 12, 8),
                                 sphere(0.014, (-0.024 * side, 0.026, -0.48), (1, 1, 1.5), 6, 5),
                                 lathe([(-0.47, 0.037), (-0.445, 0.039)], 12)), "skin", arm)
    arms[side] = arm

# tools in the right hand (pivot at the grip, pointing along the arm)
GRIP = (0, 0.0, -0.495)
axe = obj("Axe", cyl(0.012, 0.012, -0.36, 0.08, 8), "wood", arms[-1], GRIP)                     # fibre cutter
obj("AxeHead", merge(box((0.045, 0.12, 0.08), (0, 0.045, -0.33), 0.01), box((0.01, 0.045, 0.12), (0, 0.125, -0.34))), "orange", axe)
pick = obj("Pick", cyl(0.012, 0.012, -0.38, 0.08, 8), "wood", arms[-1], GRIP)                   # core drill
obj("PickHead", merge(box((0.06, 0.06, 0.1), (0, 0.0, -0.35), 0.01), cyl(0.011, 0.003, -0.56, -0.40, 8)), "orange", pick)
hoe = obj("Hoe", cyl(0.011, 0.011, -0.52, 0.14, 8), "wood", arms[-1], GRIP)                     # soil probe
obj("HoeHead", merge(box((0.1, 0.025, 0.025), (0, 0.0, -0.52), 0.005), box((0.04, 0.035, 0.045), (0, 0.0, -0.47), 0.006)), "orange", hoe)
rod = obj("Rod", cyl(0.010, 0.005, -0.9, 0.12, 8), "metal", arms[-1], GRIP)                     # net pole
obj("RodLine", cyl(0.002, 0.002, -0.9, -0.33, 4, "Z", (0, 0.0, 0.0)), "white", rod)

# carried goods (held in front with both arms)
carry = empty("Carry", torso, (0, 0.27, 0.08))
clog = obj("CarryLog", box((0.34, 0.15, 0.15), (0, 0, 0.02), 0.025), "fibre", carry)
obj("CarryLogStrap", merge(box((0.02, 0.16, 0.16), (0.09, 0, 0.02)), box((0.02, 0.16, 0.16), (-0.09, 0, 0.02))), "belt", clog)
cst = obj("CarryStone", sphere(0.09, (0, 0, 0.03), (1.1, 0.9, 0.8), 10, 7), "ore", carry)
obj("CarryStoneVein", merge(sphere(0.03, (0.045, 0.055, 0.05), (1, 1, 1), 6, 5), sphere(0.026, (-0.05, 0.045, 0.0), (1, 1, 1), 6, 5)), "oregreen", cst)
obj("CarryFish", merge(cyl(0.09, 0.09, -0.05, 0.07, 16), cyl(0.095, 0.095, 0.07, 0.09, 16)), "case", carry)
obj("CarrySack", merge(box((0.24, 0.16, 0.14), (0, 0, 0.02), 0.02), box((0.25, 0.17, 0.025), (0, 0, 0.07))), "case", carry)

# ---------------- export ----------------
bpy.ops.object.select_all(action="SELECT")
glb = os.path.join(OUT, "villager.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_yup=True)
print("exported", glb)

if PREVIEW:
    hide = {"Hair1", "Hair2", "Hair3", "Hair4", "Hair5", "Hair6", "Beard0", "Vest", "HatStraw", "Hood", "Kerchief",
            "Axe", "Pick", "Hoe", "Rod", "CarryLog", "CarryStone", "CarrySack", "CarryFish"}
    for o in scene.objects:
        p = o
        while p is not None:
            if p.name in hide: o.hide_render = True
            p = p.parent
    scene.objects["HelmetGlass"].hide_render = True
    arms[1].rotation_euler.x = -0.25; arms[-1].rotation_euler.x = 0.35
    scene.objects["LegL"].rotation_euler.x = 0.3; scene.objects["LegR"].rotation_euler.x = -0.3
    head.rotation_euler.z = 0.25
    bpy.ops.mesh.primitive_plane_add(size=6)
    g = bpy.context.object; g.data.materials.append(mat("g", (0.35, 0.2, 0.12)))
    w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.5, 0.5, 1)
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30)))
    bpy.context.object.data.energy = 3.5
    bpy.ops.object.camera_add(location=(1.4, 2.4, 1.3))
    cam = bpy.context.object; scene.camera = cam; cam.data.lens = 50
    cam.rotation_euler = (Vector((0, 0, 0.7)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.engine = "CYCLES"; scene.cycles.samples = 24; scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 600, 700
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = os.path.join(OUT, "colonist_preview.png")
    bpy.ops.render.render(write_still=True)
