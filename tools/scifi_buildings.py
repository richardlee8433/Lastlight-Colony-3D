"""Hard sci-fi buildings for Lastlight Colony, baked like tools/scifi.py (which holds the shared materials).

Run: python3 tools/scifi_buildings.py <models_dir> [preview] [name ...]
Names: hab_0..hab_5 (-> houses/house_<i>.glb), storehouse, woodcutter, farmhouse, quarry,
site_0, site_1, deposit_0, deposit_1, bridge.
All are built at game scale (1 unit = 1 m), centred on the footprint, front = -Y (Godot +Z); the layouts
match the nav_block / door / drop / work spots in scripts/game/defs.gd.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
import house_variants as hv
import scifi as sf

OUT_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "models")
PREVIEW = "preview" in sys.argv
ONLY = [a for a in sys.argv[2:] if a != "preview"]

ACCENTS = [(0.85, 0.36, 0.08), (0.10, 0.52, 0.55), (0.88, 0.66, 0.10), (0.62, 0.12, 0.10), (0.16, 0.28, 0.62), (0.80, 0.80, 0.78)]

# ---------------- extra materials ----------------
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

def mat_concrete(name="concrete", c0=(0.30, 0.29, 0.28), c1=(0.46, 0.45, 0.43)):
    m, nt, b = hv.new_mat(name)
    n = hv.noise_tex(nt, 14, 6, 0.65, hv.mapping(nt))
    r = hv.ramp(nt, [(0.3, c0), (0.75, c1)], n.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.9
    hv.bump(nt, b, n.outputs["Fac"], 0.15, 0.02)
    return m

def mat_basalt():
    m, nt, b = hv.new_mat("basalt")
    n = hv.noise_tex(nt, 4, 6, 0.7, hv.mapping(nt))
    r = hv.ramp(nt, [(0.3, (0.05, 0.045, 0.05)), (0.6, (0.12, 0.10, 0.11)), (0.8, (0.22, 0.16, 0.14))], n.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.85
    hv.bump(nt, b, n.outputs["Fac"], 0.5, 0.1)
    return m

def mat_ore():
    """Copper-green metallic ore veins."""
    m, nt, b = hv.new_mat("ore")
    n = hv.noise_tex(nt, 18, 4, 0.6, hv.mapping(nt))
    r = hv.ramp(nt, [(0.35, (0.10, 0.32, 0.30)), (0.65, (0.55, 0.36, 0.16))], n.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.35
    b.inputs["Metallic"].default_value = 0.6
    return m

def mat_fibre():
    """Compressed alien-fibre bales: teal/violet strands."""
    m, nt, b = hv.new_mat("fibre")
    w = nt.nodes.new("ShaderNodeTexWave"); w.wave_type = "BANDS"; w.bands_direction = "X"
    w.inputs["Scale"].default_value = 30; w.inputs["Distortion"].default_value = 8; w.inputs["Detail"].default_value = 3
    nt.links.new(hv.mapping(nt), w.inputs["Vector"])
    r = hv.ramp(nt, [(0.0, (0.06, 0.16, 0.16)), (0.5, (0.18, 0.38, 0.36)), (1.0, (0.32, 0.22, 0.42))], w.outputs["Fac"])
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.9
    hv.bump(nt, b, w.outputs["Fac"], 0.4, 0.02)
    return m

def mats_all(accent=(0.85, 0.36, 0.08)):
    M = sf.mats()
    M.update({
        "accent": hv.mat_flat("accent", accent, 0.5),
                "concrete": mat_concrete(),
        "window": hv.mat_flat("window", (0.95, 0.72, 0.38), 0.2),     # warm interior light
        "glass_green": hv.mat_flat("glassgreen", (0.36, 0.62, 0.52), 0.15),
        "grating": sf.mat_panels("grating", (0.26, 0.27, 0.29), (0.04, 0.04, 0.045), 0.15, 12.0),
        "interior": hv.mat_flat("interior", (0.03, 0.03, 0.035), 0.8),
        "fibre": mat_fibre(),
        "ore": mat_ore(),
        "basalt": mat_basalt(),
        "strap": hv.mat_flat("strap", (0.08, 0.08, 0.09), 0.6),
        "plant": hv.mat_flat("plant", (0.12, 0.38, 0.34), 0.8),
        "plant2": hv.mat_flat("plant2", (0.36, 0.22, 0.48), 0.8),
        "light": hv.mat_flat("lamp", (1.0, 0.92, 0.75), 0.2),
    })
    return M

# ---------------- geometry helpers ----------------
def link(o, col):
    for c in o.users_collection: c.objects.unlink(o)
    col.objects.link(o); return o

def tube(col, r, p0, p1, m, verts=16, r2=None):
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=d.length, location=(p0 + p1) / 2)
    o = bpy.context.object; o.data.materials.append(m)
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = d.to_track_quat("Z", "Y")
    for p in o.data.polygons: p.use_smooth = True
    return link(o, col)

def ring(col, R, r, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot, major_segments=32, minor_segments=8)
    o = bpy.context.object; o.data.materials.append(m)
    return link(o, col)

def arch(col, R, a0, a1, c, z0, m, along="y", segs=20, caps=(False, False), thick=0.04, cap_m=None, squash=1.0):
    """Half cylinder (an arch / quonset / tunnel). along="y": runs from y=a0 to a1 at x=c;
    along="x": runs from x=a0 to a1 at y=c. Base at z0. Optional flat end caps."""
    bm = bmesh.new()
    rows = []
    for a in (a0, a1):
        row = []
        for i in range(segs + 1):
            t = math.pi * i / segs
            u = R * math.cos(t); h = z0 + R * math.sin(t) * squash
            row.append(bm.verts.new((c + u, a, h) if along == "y" else (a, c + u, h)))
        rows.append(row)
    for i in range(segs):
        bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    o = hv.mesh_obj("arch", bm, m, col)
    for p in o.data.polygons: p.use_smooth = True
    if thick:
        s = o.modifiers.new("s", "SOLIDIFY"); s.thickness = thick
    for k, on in enumerate(caps):
        if not on: continue
        bm = bmesh.new()
        a = (a0, a1)[k]
        vs = []
        for i in range(segs + 1):
            t = math.pi * i / segs
            u = R * math.cos(t); h = z0 + R * math.sin(t) * squash
            vs.append(bm.verts.new((c + u, a, h) if along == "y" else (a, c + u, h)))
        bm.faces.new(vs)
        hv.mesh_obj("cap", bm, cap_m or m, col)
    return o

def lattice(col, M, base, top, w, levels, m=None, t=0.05):
    """Square lattice tower (derrick / mast) from base to top height."""
    m = m or M["metal"]
    x, y = base[0], base[1]
    cs = [(-w, -w), (w, -w), (w, w), (-w, w)]
    for cx, cy in cs:
        hv.beam(col, (x + cx, y + cy, 0), (x + cx * 0.6, y + cy * 0.6, top), t, m, 1)
    for k in range(levels):
        z0 = top * k / levels; z1 = top * (k + 1) / levels
        f0 = 1 - 0.4 * k / levels; f1 = 1 - 0.4 * (k + 1) / levels
        for i in range(4):
            a = cs[i]; b = cs[(i + 1) % 4]
            hv.beam(col, (x + a[0] * f1, y + a[1] * f1, z1), (x + b[0] * f1, y + b[1] * f1, z1), t * 0.7, m, 2)
            hv.beam(col, (x + a[0] * f0, y + a[1] * f0, z0), (x + b[0] * f1, y + b[1] * f1, z1), t * 0.5, m, 3)

def solar_panel(col, M, loc, w, d, tilt=0.45, yaw=0.0, post=0.6):
    x, y, z = loc
    hv.beam(col, (x, y, z), (x, y, z + post), 0.05, M["metal"], 4)
    hv.cube(col, (w, d, 0.035), (x, y, z + post + 0.05), M["solar"], rot=(tilt, 0, yaw), bevel=0.005)
    hv.cube(col, (w + 0.04, d + 0.04, 0.02), (x, y, z + post + 0.03), M["metal"], rot=(tilt, 0, yaw), bevel=0.003)

def sandbags(col, M, pts, seed, r=0.16):
    for k, (x, y, z) in enumerate(pts):
        o = hv.blob(col, (x, y, z + r * 0.5), r, M["regolith"], 2, 0.55, 0.2, seed + k)
        o.scale = (1.5, 1.0, 1.0)

def bale(col, M, loc, rot=0.0, s=(0.6, 0.42, 0.36)):
    x, y, z = loc
    hv.cube(col, s, (x, y, z + s[2] / 2), M["fibre"], rot=(0, 0, rot), bevel=0.04, wobble=0.01, seed=int(x * 100 + y * 10))
    for dx in (-0.2, 0.2):
        c, sn = math.cos(rot), math.sin(rot)
        hv.cube(col, (0.03, s[1] + 0.02, s[2] + 0.02), (x + dx * s[0] / 0.6 * c, y + dx * s[0] / 0.6 * sn, z + s[2] / 2), M["strap"], rot=(0, 0, rot), bevel=0.0)

# ---------------- habitat modules (houses) ----------------
def hab(col, k):
    """Six variants: even = horizontal cylinder module on a cradle, odd = regolith-bermed dome.
    Footprint ~2.7 x 2.0 m (nav_block), airlock door towards -Y (door spot at y = -1.45)."""
    rnd = random.Random(300 + k * 13)
    M = mats_all(ACCENTS[k])
    if k % 2 == 0:
        R = 0.74 + 0.04 * (k // 2); L = 2.1 + 0.1 * (k // 2); zc = 0.98
        tube(col, R, (-L / 2, 0, zc), (L / 2, 0, zc), M["hull"], 28)
        for sx in (-1, 1):
            o = sf.sphere(col, R, (sx * L / 2, 0, zc), M["hull"], (0.38, 1, 1), 24)
            tube(col, R * 1.02, (sx * (L / 2 - 0.05), 0, zc), (sx * (L / 2 + 0.03), 0, zc), M["hull_dark"], 28)
        for x in (-L / 4, L / 4):                                               # seam rings
            tube(col, R * 1.012, (x - 0.025, 0, zc), (x + 0.025, 0, zc), M["hull_dark"], 28)
        tube(col, R * 1.01, (-0.12, 0, zc), (0.12, 0, zc), M["accent"], 28)      # accent band
        # cradle
        for x in (-L / 2 + 0.35, L / 2 - 0.35):
            hv.cube(col, (0.22, R * 1.7, 0.32), (x, 0, 0.16), M["hull_dark"], bevel=0.02)
            for sy in (-1, 1):
                hv.beam(col, (x, sy * R * 0.8, 0.0), (x, sy * R * 0.5, zc - R * 0.6), 0.07, M["metal"], 5)
        # windows along the front, warm light inside
        for x in ([-0.55, 0.55] if k != 2 else [-0.7, -0.25, 0.55]):
            a = -0.55
            p = Vector((x, R * math.cos(a + math.pi / 2) * -1, zc + R * math.sin(-a) * 0.0))
            yy = -R * math.cos(0.45); zz = zc + R * math.sin(0.45)
            hv.cube(col, (0.3, 0.06, 0.2), (x, yy, zz), M["dark"], rot=(0.45, 0, 0), bevel=0.02)
            hv.cube(col, (0.24, 0.07, 0.14), (x, yy - 0.005, zz), M["window"], rot=(0.45, 0, 0), bevel=0.01)
        # airlock to the front with a door and a step
        al = 0.42
        tube(col, al, (0.0, -R * 0.5, 0.82), (0.0, -1.12, 0.82), M["hull"], 20)
        tube(col, al * 1.05, (0.0, -1.06, 0.82), (0.0, -1.16, 0.82), M["hull_dark"], 20)
        hv.cube(col, (0.46, 0.04, 0.62), (0.0, -1.17, 0.8), M["dark"], bevel=0.02)
        hv.cube(col, (0.4, 0.05, 0.08), (0.0, -1.18, 1.05), M["accent"], bevel=0.01)
        hv.cube(col, (0.06, 0.05, 0.06), (0.17, -1.19, 0.85), M["light"], bevel=0.01)
        hv.cube(col, (0.6, 0.22, 0.42), (0.0, -1.24, 0.21), M["hull_dark"], bevel=0.02)
        hv.cube(col, (0.62, 0.24, 0.03), (0.0, -1.24, 0.43), M["grating"], bevel=0.005)
        # roof kit
        if k == 0:
            solar_panel(col, M, (-0.45, 0.1, zc + R - 0.05), 0.9, 0.55, 0.35, 0.0, 0.25)
            solar_panel(col, M, (0.55, 0.1, zc + R - 0.05), 0.9, 0.55, 0.35, 0.0, 0.25)
        elif k == 2:
            for x in (-0.6, -0.3, 0.0):                                         # radiator fins
                hv.cube(col, (0.04, 0.7, 0.3), (x, 0.2, zc + R + 0.1), M["foil2"], bevel=0.005)
            hv.beam(col, (0.6, 0.0, zc + R - 0.05), (0.6, 0.0, zc + R + 0.75), 0.04, M["metal"], 7)
            sf.sphere(col, 0.2, (0.6, -0.05, zc + R + 0.8), M["hull"], (1, 1, 0.35)).rotation_euler = (0.7, 0, 0)
        else:
            hv.cube(col, (0.7, 0.5, 0.25), (0.35, 0.15, zc + R + 0.05), M["hull_dark"], bevel=0.04)
            for x in (0.15, 0.55):
                tube(col, 0.1, (x, 0.15, zc + R + 0.17), (x, 0.15, zc + R + 0.22), M["dark"], 12)
            solar_panel(col, M, (-0.5, 0.1, zc + R - 0.05), 0.8, 0.5, 0.3, 0.0, 0.2)
        # water/oxygen tank at the back corner, conduit to the hull
        tube(col, 0.2, (L / 2 - 0.05, 0.78, 0.0), (L / 2 - 0.05, 0.78, 0.95), M["foil2"] if k != 4 else M["accent"], 16)
        sf.sphere(col, 0.2, (L / 2 - 0.05, 0.78, 0.95), M["foil2"] if k != 4 else M["accent"], (1, 1, 0.5))
        hv.beam(col, (L / 2 - 0.05, 0.6, 0.6), (L / 2 - 0.35, 0.35, 0.6), 0.04, M["metal"], 8)
    else:
        # dome on a ring wall, regolith berm, airlock tunnel to the front
        R = 0.95 + 0.04 * (k // 2); sx_ = 1.28
        cyl = sf.cyl(col, R, R, 0.42, (0, 0, 0.21), M["hull_dark"], verts=40); cyl.scale = (sx_, 1, 1)
        d = sf.sphere(col, R, (0, 0, 0.42), M["hull"], (sx_, 1, 0.78), 36)
        # cut the dome's lower half away (keep it as a cap)
        bm = bmesh.new(); bm.from_mesh(d.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
        bm.to_mesh(d.data); bm.free()
        ring(col, R * 1.005, 0.035, (0, 0, 0.43), M["metal"]).scale = (sx_, 1, 1)
        ring(col, R * 0.72, 0.03, (0, 0, 0.42 + R * 0.78 * 0.69), M["hull_dark"]).scale = (sx_, 1, 1)
        ring(col, R * 0.94, 0.03, (0, 0, 0.42 + R * 0.78 * 0.33), M["accent"]).scale = (sx_, 1, 1)
        # porthole ring
        n = 6
        for i in range(n):
            a = -math.pi / 2 + (i - (n - 1) / 2) * 0.55
            if abs(a + math.pi / 2) < 0.2: continue
            px = math.cos(a) * R * sx_ * 0.93; py = math.sin(a) * R * 0.93
            o = sf.cyl(col, 0.11, 0.11, 0.05, (px, py, 0.62), M["window"], verts=14)
            o.rotation_mode = "QUATERNION"; o.rotation_quaternion = Vector((px / sx_, py, 0.25)).to_track_quat("Z", "Y")
        # hatch and mast on top
        top = 0.42 + R * 0.78
        sf.cyl(col, 0.22, 0.2, 0.12, (0, 0, top - 0.01), M["hull_dark"], verts=20)
        hv.beam(col, (0.15, 0.1, top), (0.15, 0.1, top + 0.8), 0.04, M["metal"], 9)
        hv.cube(col, (0.05, 0.05, 0.05), (0.15, 0.1, top + 0.82), M["accent"], bevel=0.01)
        if k == 3:
            solar_panel(col, M, (-R * sx_ - 0.05, 0.55, 0.0), 0.7, 0.5, 0.6, 0.6, 0.55)
        # airlock tunnel
        hv.cube(col, (0.62, 0.65, 0.92), (0, -R - 0.12, 0.46), M["hull"], bevel=0.06)
        hv.cube(col, (0.66, 0.08, 0.96), (0, -R - 0.42, 0.48), M["hull_dark"], bevel=0.03)
        hv.cube(col, (0.44, 0.04, 0.7), (0, -R - 0.47, 0.42), M["dark"], bevel=0.02)
        hv.cube(col, (0.5, 0.05, 0.07), (0, -R - 0.47, 0.84), M["accent"], bevel=0.01)
        hv.cube(col, (0.05, 0.05, 0.05), (0.27, -R - 0.48, 0.6), M["light"], bevel=0.01)
        hv.cube(col, (0.6, 0.3, 0.06), (0, -R - 0.62, 0.03), M["grating"], bevel=0.01)
        # regolith berm around the back half
        pts = []
        for i in range(16):
            a = 0.15 + i / 15 * (math.pi - 0.3)
            pts.append((math.cos(a) * (R * sx_ + 0.05), math.sin(a) * (R + 0.05), 0.0))
        for i in range(10):
            a = 0.45 + i / 9 * (math.pi - 0.9)
            pts.append((math.cos(a) * (R * sx_ + 0.0), math.sin(a) * (R + 0.0), 0.22))
        sandbags(col, M, pts, 400 + k)
        # equipment locker by the airlock
        hv.cube(col, (0.4, 0.3, 0.55), (0.75, -0.95, 0.28), M["crate"], rot=(0, 0, 0.25), bevel=0.02)
        hv.cube(col, (0.42, 0.32, 0.05), (0.75, -0.95, 0.5), M["hazard"], rot=(0, 0, 0.25), bevel=0.005)
    return 3.0, 3.0

# ---------------- supply depot (storehouse) ----------------
def depot(col):
    """Quonset-style storage hangar open to the front (-Y): crates and drums inside, a loading pad.
    nav_block y in [-1.0, 1.35] (Blender), goods are dropped at y = -1.55."""
    M = mats_all((0.88, 0.62, 0.1)); rnd = random.Random(47)
    y0, y1 = -0.95, 1.35; R = 1.28; z0 = 0.18
    hv.cube(col, (2.85, 2.5, z0), (0, 0.18, z0 / 2), M["concrete"], bevel=0.03)
    arch(col, R, y0, y1, 0.0, z0, M["hull"], "y", 24, caps=(False, True), thick=0.05, cap_m=M["hull_dark"])
    arch(col, R - 0.06, y0 + 0.08, y1 - 0.05, 0.0, z0, M["interior"], "y", 24, thick=0.0)
    for y in [y0 + 0.02 + i * (y1 - y0 - 0.04) / 5 for i in range(6)]:          # ribs
        arch(col, R + 0.04, y - 0.04, y + 0.04, 0.0, z0, M["hull_dark"], "y", 24, thick=0.06)
    # front frame, half-open roller door
    arch(col, R + 0.06, y0 - 0.06, y0 + 0.02, 0.0, z0, M["accent"], "y", 24, thick=0.08)
    hv.cube(col, (1.9, 0.08, 0.55), (0, y0 + 0.02, z0 + 1.1), M["hull_dark"], bevel=0.01)
    for i in range(5):
        hv.cube(col, (1.9, 0.09, 0.02), (0, y0 + 0.02, z0 + 0.88 + i * 0.1), M["dark"], bevel=0.0)
    for sx in (-1, 1):
        hv.cube(col, (0.08, 0.1, 1.15), (sx * 0.97, y0, z0 + 0.58), M["hazard"], bevel=0.005)
    hv.cube(col, (0.5, 0.05, 0.06), (0, y0 - 0.06, z0 + 1.43), M["light"], bevel=0.01)
    # goods inside
    for i in range(3):
        sf.crate(col, M, (-0.75 + i * 0.5, 0.95, z0), 0.5, rnd.uniform(-0.1, 0.1))
    sf.crate(col, M, (-0.5, 0.95, z0 + 0.36), 0.46, 0.2)
    for i in range(2):
        tube(col, 0.2, (0.75, 0.25 + i * 0.45, z0), (0.75, 0.25 + i * 0.45, z0 + 0.6), M["accent"], 16)
        tube(col, 0.205, (0.75, 0.25 + i * 0.45, z0 + 0.45), (0.75, 0.25 + i * 0.45, z0 + 0.5), M["dark"], 16)
    for i in range(3):
        bale(col, M, (-0.6 + i * 0.0, 0.1 + i * 0.0, z0 + i * 0.36), 0.0, (0.55, 0.4, 0.34)) if i < 2 else None
    # loading pad in front with a pallet
    hv.cube(col, (1.6, 0.5, 0.03), (0, -1.25, 0.015), M["hazard"], bevel=0.0)
    hv.cube(col, (1.5, 0.42, 0.04), (0, -1.25, 0.035), M["concrete"], bevel=0.0)
    # beacon light pole and a small terminal
    hv.beam(col, (1.3, -1.15, 0), (1.3, -1.15, 1.3), 0.05, M["metal"], 10)
    hv.cube(col, (0.12, 0.12, 0.1), (1.3, -1.15, 1.35), M["accent"], bevel=0.02)
    hv.cube(col, (0.3, 0.22, 0.6), (-1.3, -1.12, 0.3), M["hull_dark"], bevel=0.03)
    hv.cube(col, (0.22, 0.03, 0.16), (-1.3, -1.24, 0.48), M["glass"], rot=(0.3, 0, 0), bevel=0.01)
    return 3.0, 3.0

# ---------------- fibre harvester (woodcutter) ----------------
def harvester(col):
    """Prefab workshop with an open service bay (baler inside), fibre bales stacked behind and a shredder
    hopper at the back corner. Blocks: main y in [-0.75, 0.75], x in [-1.05, 1.05]; bales x [-0.55, 0.7],
    y [0.85, 1.3]; hopper x [0.8, 1.3], y [0.75, 1.25]."""
    M = mats_all((0.10, 0.52, 0.55)); rnd = random.Random(31)
    W, D, H = 2.05, 1.45, 1.45; z0 = 0.12
    hv.cube(col, (W + 0.1, D + 0.1, z0), (0, 0, z0 / 2), M["concrete"], bevel=0.02)
    # back + side walls and roof (front bay open)
    hv.cube(col, (W, 0.1, H), (0, D / 2 - 0.05, z0 + H / 2), M["hull"], bevel=0.04)
    for sx in (-1, 1):
        hv.cube(col, (0.1, D, H), (sx * (W / 2 - 0.05), 0, z0 + H / 2), M["hull"], bevel=0.04)
    hv.cube(col, (W + 0.1, D + 0.35, 0.12), (0, -0.12, z0 + H + 0.06), M["hull_dark"], bevel=0.03)
    hv.cube(col, (W - 0.15, 0.06, H - 0.05), (0, D / 2 - 0.12, z0 + H / 2), M["interior"], bevel=0.0)
    hv.cube(col, (W + 0.12, 0.08, 0.12), (0, -D / 2 - 0.25, z0 + H - 0.02), M["accent"], bevel=0.01)
    for sx in (-1, 1):
        hv.cube(col, (0.1, 0.12, H), (sx * (W / 2 - 0.02), -D / 2 + 0.02, z0 + H / 2), M["hazard"], bevel=0.01)
    hv.cube(col, (0.5, 0.05, 0.05), (0, -D / 2 - 0.27, z0 + H - 0.1), M["light"], bevel=0.01)
    # baler machine inside
    hv.cube(col, (0.8, 0.7, 0.85), (-0.35, 0.15, z0 + 0.43), M["accent"], bevel=0.05)
    hv.cube(col, (0.6, 0.08, 0.5), (-0.35, -0.22, z0 + 0.4), M["dark"], bevel=0.02)
    tube(col, 0.08, (-0.35, 0.15, z0 + 0.85), (-0.35, 0.15, z0 + 1.35), M["metal"], 12)
    bale(col, M, (0.5, -0.1, z0), 0.1)
    bale(col, M, (0.55, 0.3, z0), -0.05)
    bale(col, M, (0.52, 0.1, z0 + 0.36), 0.2)
    # roof vents
    for x in (-0.5, 0.4):
        tube(col, 0.16, (x, 0.2, z0 + H + 0.12), (x, 0.2, z0 + H + 0.26), M["hull_dark"], 16)
        tube(col, 0.13, (x, 0.2, z0 + H + 0.26), (x, 0.2, z0 + H + 0.28), M["dark"], 16)
    # bales stacked behind
    for row in range(2):
        for i in range(3 - row):
            bale(col, M, (-0.35 + i * 0.42 + row * 0.21, 1.07, row * 0.36), math.pi / 2, (0.4, 0.42, 0.36))
    # shredder hopper on legs at the back corner
    for dx in (-0.18, 0.18):
        for dy in (-0.18, 0.18):
            hv.beam(col, (1.05 + dx, 1.0 + dy, 0), (1.05 + dx, 1.0 + dy, 0.6), 0.05, M["metal"], 11)
    tube(col, 0.12, (1.05, 1.0, 0.45), (1.05, 1.0, 0.65), M["dark"], 12, r2=0.28)
    tube(col, 0.28, (1.05, 1.0, 0.65), (1.05, 1.0, 1.05), M["hull_dark"], 16)
    hv.cube(col, (0.06, 0.06, 0.4), (1.3, 1.0, 0.85), M["accent"], bevel=0.01)
    # cutter tool rack on the left wall outside
    hv.cube(col, (0.04, 0.5, 0.6), (-W / 2 - 0.04, -0.2, z0 + 0.7), M["metal"], bevel=0.01)
    return 3.0, 3.0

# ---------------- agri station (farmhouse) ----------------
def agri(col):
    """Greenhouse tunnel with plant beds glowing through frosted panels, an entry module to the front,
    a water tank. nav_block x [-1.2, 1.2], y [-0.75, 0.95]."""
    M = mats_all((0.30, 0.62, 0.30)); rnd = random.Random(71)
    x0, x1 = -1.15, 0.65; R = 0.78; cy = 0.12; z0 = 0.1
    hv.cube(col, (x1 - x0 + 0.1, 2 * R + 0.1, z0), ((x0 + x1) / 2, cy, z0 / 2), M["concrete"], bevel=0.02)
    arch(col, R, x0, x1, cy, z0, M["glass_green"], "x", 22, caps=(True, True), thick=0.03, cap_m=M["glass_green"])
    for x in [x0 + i * (x1 - x0) / 5 for i in range(6)]:
        arch(col, R + 0.03, x - 0.03, x + 0.03, cy, z0, M["hull"], "x", 22, thick=0.05)
    hv.cube(col, (x1 - x0, 0.06, 0.06), ((x0 + x1) / 2, cy, z0 + R + 0.02), M["hull"], bevel=0.0)
    # grow lights stripe and plants visible at the base
    for i in range(7):
        x = x0 + 0.15 + i * 0.24
        for sy in (-1, 1):
            hv.blob(col, (x, cy + sy * (R - 0.08), z0 + 0.12), 0.12, M["plant"] if i % 2 else M["plant2"], 1, 0.9, 0.3, 700 + i)
    # entry module in front
    hv.cube(col, (0.62, 0.42, 0.85), (-0.25, cy - R - 0.12, 0.45), M["hull"], bevel=0.05)
    hv.cube(col, (0.42, 0.04, 0.66), (-0.25, cy - R - 0.34, 0.42), M["dark"], bevel=0.02)
    hv.cube(col, (0.5, 0.05, 0.06), (-0.25, cy - R - 0.35, 0.82), M["accent"], bevel=0.01)
    # water tank and pump on the right
    tube(col, 0.32, (0.95, 0.35, 0.0), (0.95, 0.35, 1.05), M["hull"], 20)
    sf.sphere(col, 0.32, (0.95, 0.35, 1.05), M["hull"], (1, 1, 0.4))
    tube(col, 0.33, (0.95, 0.35, 0.55), (0.95, 0.35, 0.65), M["accent"], 20)
    hv.beam(col, (0.95, 0.05, 0.35), (0.62, 0.05, 0.35), 0.05, M["metal"], 12)
    hv.cube(col, (0.35, 0.3, 0.4), (0.95, -0.35, 0.2), M["hull_dark"], bevel=0.03)
    tube(col, 0.04, (0.95, -0.35, 0.4), (0.95, -0.35, 0.7), M["metal"], 8)
    # small solar panel
    solar_panel(col, M, (-0.9, -0.55, 0.0), 0.55, 0.4, 0.55, 0.0, 0.45)
    return 3.0, 3.0

# ---------------- mining rig (quarry) ----------------
def rig(col):
    """Drill derrick at the back left with a boom and drill string into the deposit (centre), an ore hopper on
    the right, stacked ore bins front right, an ore hauler front left. Game scale 4 x 4 m."""
    M = mats_all((0.88, 0.62, 0.1)); rnd = random.Random(61)
    bx, by = -1.45, 1.05
    hv.cube(col, (0.85, 0.8, 0.12), (bx, by, 0.06), M["concrete"], bevel=0.02)
    lattice(col, M, (bx, by), 2.9, 0.32, 5, M["accent"], 0.06)
    top = Vector((bx, by, 2.9))
    hv.cube(col, (0.35, 0.35, 0.2), top + Vector((0, 0, 0.05)), M["hull_dark"], bevel=0.02)
    tip = Vector((-0.15, 0.15, 2.55))
    hv.beam(col, top + Vector((0.1, -0.05, -0.1)), tip, 0.1, M["accent"], 13)
    hv.beam(col, top + Vector((0.1, -0.05, -0.65)), tip + Vector((-0.1, 0.05, -0.15)), 0.06, M["metal"], 14)
    # drill head and string down into the rock
    hv.cube(col, (0.36, 0.36, 0.5), tip + Vector((0, 0, -0.35)), M["hull"], bevel=0.04)
    hv.cube(col, (0.38, 0.38, 0.06), tip + Vector((0, 0, -0.18)), M["hazard"], bevel=0.005)
    tube(col, 0.06, tip + Vector((0, 0, -0.6)), Vector((tip.x, tip.y, 0.9)), M["metal"], 12)
    tube(col, 0.1, (tip.x, tip.y, 0.9), (tip.x, tip.y, 1.15), M["dark"], 12)
    for k in range(3):
        hv.beam(col, tip + Vector((0.1, 0, -0.3)), Vector((bx + 0.3, by - 0.2, 0.6 - k * 0.15)), 0.025, M["rubber"], 15 + k)
    # power unit by the derrick
    hv.cube(col, (0.55, 0.4, 0.45), (bx + 0.05, by - 0.55, 0.23), M["hull_dark"], bevel=0.04)
    for i in range(3):
        hv.cube(col, (0.02, 0.3, 0.3), (bx + 0.33, by - 0.55 + (i - 1) * 0.1, 0.25), M["metal"], bevel=0.0)
    # ore hopper (right): x [1.4, 1.9], y [-0.23, 0.72]
    for dx in (-0.2, 0.2):
        for dy in (-0.38, 0.38):
            hv.beam(col, (1.65 + dx, 0.25 + dy, 0), (1.65 + dx, 0.25 + dy, 0.55), 0.05, M["metal"], 16)
    hv.cube(col, (0.5, 0.95, 0.4), (1.65, 0.25, 0.75), M["accent"], bevel=0.03)
    for k in range(9):
        hv.blob(col, (1.65 + rnd.uniform(-0.18, 0.18), 0.25 + rnd.uniform(-0.38, 0.38), 0.95), rnd.uniform(0.06, 0.1), M["ore"], 1, 0.8, 0.4, 900 + k)
    tube(col, 0.1, (1.45, 0.25, 0.6), (1.2, 0.25, 0.35), M["dark"], 10)
    # ore bins front right: x [0.85, 1.9], y [-1.4, -1.0]
    for i in range(2):
        hv.cube(col, (0.48, 0.38, 0.32), (1.12 + i * 0.52, -1.2, 0.16), M["crate"], bevel=0.02)
        for k in range(4):
            hv.blob(col, (1.12 + i * 0.52 + rnd.uniform(-0.15, 0.15), -1.2 + rnd.uniform(-0.1, 0.1), 0.34), 0.07, M["ore"], 1, 0.7, 0.4, 950 + i * 5 + k)
    hv.cube(col, (0.46, 0.36, 0.3), (1.38, -1.2, 0.47), M["crate"], rot=(0, 0, 0.1), bevel=0.02)
    # ore hauler front left: x [-1.7, -1.0], y [-1.6, -0.85]
    hv.cube(col, (0.6, 0.65, 0.18), (-1.35, -1.22, 0.24), M["hull_dark"], bevel=0.03)
    hv.cube(col, (0.55, 0.45, 0.25), (-1.35, -1.12, 0.45), M["accent"], bevel=0.03)
    for k in range(4):
        hv.blob(col, (-1.35 + rnd.uniform(-0.15, 0.15), -1.12 + rnd.uniform(-0.1, 0.1), 0.6), 0.08, M["ore"], 1, 0.7, 0.4, 980 + k)
    for sx in (-1, 1):
        for sy in (-1, 1):
            tube(col, 0.12, (-1.35 + sx * 0.3, -1.22 + sy * 0.22, 0.12), (-1.35 + sx * 0.36, -1.22 + sy * 0.22, 0.12), M["rubber"], 14)
    hv.beam(col, (-1.35, -1.55, 0.3), (-1.35, -1.85, 0.12), 0.04, M["metal"], 17)
    # cables on the ground
    for k in range(2):
        hv.beam(col, (bx + 0.3, by - 0.6, 0.03 + k * 0.02), (0.9, 0.0 + k * 0.1, 0.03), 0.03, M["rubber"], 18 + k)
    return 4.0, 4.0


# ---------------- construction sites ----------------
def site(col, stage):
    """3 x 3 m site, stretched to each footprint by the game.
    stage 0: levelled pad, survey stakes with tape, panel bundles and cases.
    stage 1: foundation slab, steel frame, a jib crane, cladding panels waiting."""
    M = mats_all((0.88, 0.62, 0.1)); rnd = random.Random(500 + stage)
    hx, hy = 1.15, 0.95
    hv.cube(col, (2.9, 2.6, 0.04), (0, 0, 0.0), M["scorch"] if False else M["regolith"], bevel=0.01, wobble=0.02, seed=5)
    # panel bundles (front right) and cases (back right)
    for k in range(4 if stage == 0 else 2):
        hv.cube(col, (1.0, 0.5, 0.04), (0.75, -1.15, 0.03 + k * 0.045), M["hull"], rot=(0, 0, rnd.uniform(-0.05, 0.05)), bevel=0.005)
    sf.crate(col, M, (1.2, 1.05, 0), 0.45, 0.2)
    if stage == 0: sf.crate(col, M, (0.75, 1.1, 0), 0.4, -0.15)
    # beams stacked on the left
    for row in range(2):
        for k in range(3 - row):
            hv.cube(col, (0.1, 1.1, 0.1), (-1.3 + (k + row * 0.5) * 0.14, -0.15, 0.06 + row * 0.11), M["accent"], bevel=0.01)
    if stage == 0:
        corners = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
        for (x, y) in corners:
            hv.beam(col, (x, y, 0), (x, y, 0.45), 0.04, M["metal"], 1)
            hv.cube(col, (0.05, 0.05, 0.05), (x, y, 0.47), M["accent"], bevel=0.01)
        for i in range(4):
            a = corners[i]; b = corners[(i + 1) % 4]
            hv.beam(col, (a[0], a[1], 0.38), (b[0], b[1], 0.38), 0.012, M["hazard"], 2)
        # first anchor plates
        for k in range(3):
            hv.cube(col, (0.25, 0.25, 0.05), (-hx + 0.3 + k * 0.85, hy - 0.2, 0.04), M["concrete"], bevel=0.01)
        # a survey tripod
        for a in (0.0, 2.1, 4.2):
            hv.beam(col, (0.2 + math.cos(a) * 0.25, -0.1 + math.sin(a) * 0.25, 0), (0.2, -0.1, 0.9), 0.025, M["metal"], 3)
        hv.cube(col, (0.15, 0.12, 0.12), (0.2, -0.1, 0.96), M["accent"], bevel=0.02)
    else:
        hv.cube(col, (2 * hx + 0.2, 2 * hy + 0.2, 0.16), (0, 0, 0.08), M["concrete"], bevel=0.02)
        H = 1.7; top = 0.16 + H
        for sx in (-1, 1):
            for sy in (-1, 1):
                hv.beam(col, (sx * hx, sy * hy, 0.16), (sx * hx, sy * hy, top), 0.1, M["accent"], 4)
            hv.beam(col, (sx * hx, 0, 0.16), (sx * hx, 0, top), 0.08, M["accent"], 5)
        for sy in (-1, 1):
            hv.beam(col, (-hx, sy * hy, top), (hx, sy * hy, top), 0.09, M["accent"], 6)
            hv.beam(col, (-hx, sy * hy, 0.95), (hx, sy * hy, 0.95), 0.06, M["metal"], 7)
        for sx in (-1, 1):
            hv.beam(col, (sx * hx, -hy, top), (sx * hx, hy, top), 0.09, M["accent"], 8)
            hv.beam(col, (sx * hx, -hy, 0.2), (sx * hx, 0, top - 0.05), 0.04, M["metal"], 9)    # diagonal brace
        # cladding started on the back wall
        hv.cube(col, (2 * hx, 0.05, 0.9), (0, hy + 0.04, 0.6), M["hull"], bevel=0.01)
        hv.cube(col, (hx, 0.05, 0.6), (-hx / 2, hy + 0.04, 1.35), M["hull"], bevel=0.01)
        # jib crane at the front left with a panel hanging
        hv.beam(col, (-hx - 0.25, -hy - 0.3, 0), (-hx - 0.25, -hy - 0.3, top + 0.6), 0.08, M["hazard"], 10)
        hv.beam(col, (-hx - 0.25, -hy - 0.3, top + 0.55), (0.2, -hy - 0.3, top + 0.55), 0.06, M["hazard"], 11)
        hv.beam(col, (0.0, -hy - 0.3, top + 0.55), (0.0, -hy - 0.3, 1.3), 0.012, M["rubber"], 12)
        hv.cube(col, (0.8, 0.04, 0.5), (0.0, -hy - 0.3, 1.05), M["hull"], bevel=0.005)
    return 3.0, 3.0

# ---------------- ore deposits ----------------
def deposit(col, variant):
    """Basalt outcrop with copper-green ore veins and pale fresh drill faces, ~2.6 m across."""
    seed = 900 + variant * 37; rnd = random.Random(seed)
    M = mats_all()
    pale = sf.hv.mat_wood("palerock", (0.30, 0.27, 0.27), (0.48, 0.44, 0.43), (14, 14, 14))
    if variant == 0:
        big = [(0.0, 0.1, 0.85, 1.35), (-0.75, 0.45, 0.6, 0.95), (0.7, 0.5, 0.62, 0.9), (0.45, -0.45, 0.5, 0.7),
               (-0.6, -0.35, 0.48, 0.6), (0.05, 0.85, 0.5, 0.7), (1.05, -0.05, 0.4, 0.5)]
    else:
        big = [(0.1, 0.05, 0.8, 1.2), (-0.65, -0.3, 0.55, 0.8), (0.65, 0.45, 0.58, 0.85), (-0.45, 0.6, 0.48, 0.65),
               (0.75, -0.45, 0.4, 0.5)]
    for k, (x, y, r, h) in enumerate(big):
        o = hv.blob(col, (x, y, h * 0.4), r, M["basalt"], 2, h / r * 0.55, 0.5, seed + k)
        o.scale = (rnd.uniform(1.0, 1.25), rnd.uniform(0.9, 1.15), 1.0)
        o.rotation_euler = (rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25), rnd.uniform(0, 3))
        # ore nodules breaking the surface
        for j in range(4):
            a = rnd.uniform(0, math.tau); e = rnd.uniform(0.2, 0.9)
            hv.blob(col, (x + math.cos(a) * r * 0.8, y + math.sin(a) * r * 0.7, h * 0.4 + e * h * 0.45),
                    rnd.uniform(0.08, 0.16), M["ore"], 1, 0.7, 0.5, seed + 100 + k * 5 + j)
    for k in range(3):
        w_ = 1.2 - k * 0.25
        hv.cube(col, (w_, 0.42, 0.26), (0.0, -0.62 + k * 0.22, 0.13 + k * 0.26), pale,
                rot=(0, 0, rnd.uniform(-0.06, 0.06)), bevel=0.03, wobble=0.02, seed=seed + 20 + k)
    for k in range(26):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(1.05, 1.55)
        sz = rnd.uniform(0.07, 0.2)
        hv.blob(col, (math.cos(a) * d, math.sin(a) * d, sz * 0.35), sz, [M["basalt"], pale, M["ore"]][k % 3], 1, 0.7, 0.35, seed + 50 + k)
    return 3.1, 3.1

# ---------------- bridge ----------------
def bridge(col):
    """Steel truss footbridge, 6 m along Y, deck ~1.8 m wide, deck top at z = 0.05 at the ends and ~0.23 mid."""
    M = mats_all((0.88, 0.62, 0.1))
    L = 6.0; W = 1.8
    def arc(y): return 0.05 + 0.18 * (1.0 - (2.0 * y / L) ** 2)
    n = 12
    for k in range(n):
        y = -L / 2 + (k + 0.5) * L / n
        hv.cube(col, (W, L / n * 0.96, 0.05), (0, y, arc(y) - 0.025), M["grating"], bevel=0.005)
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.02)
        pts = [(-L / 2 + i * L / 8) for i in range(9)]
        for i in range(8):
            a, b = pts[i], pts[i + 1]
            hv.beam(col, (x, a, arc(a) - 0.06), (x, b, arc(b) - 0.06), 0.1, M["accent"], 30 + i)
            hv.beam(col, (x, a, arc(a) + 0.8), (x, b, arc(b) + 0.8), 0.06, M["accent"], 40 + i)
            hv.beam(col, (x, a, arc(a) - 0.04), (x, b, arc(b) + 0.78), 0.035, M["metal"], 50 + i)
        for y in pts:
            hv.beam(col, (x, y, arc(y) - 0.2), (x, y, arc(y) + 0.82), 0.05, M["metal"], 60)
        for y in (-L / 2 + 0.1, L / 2 - 0.1):
            hv.cube(col, (0.3, 0.3, 0.4), (x, y, -0.1), M["concrete"], bevel=0.02)
    for x in (-0.5, 0.5):
        pts = [Vector((x, -L / 2 + i * L / 6, arc(-L / 2 + i * L / 6) - 0.12)) for i in range(7)]
        for i in range(6):
            hv.beam(col, pts[i], pts[i + 1], 0.1, M["hull_dark"], 70 + i)
    for y in (-L / 2 + 0.15, L / 2 - 0.15):
        hv.cube(col, (0.08, 0.08, 0.08), (W / 2 + 0.02, y, arc(y) + 0.87), M["light"], bevel=0.01)
    return W + 0.4, L

JOBS = [(f"hab_{k}", (lambda kk: (lambda c: hab(c, kk)))(k), f"houses/house_{k}") for k in range(6)] + [
    ("storehouse", depot, "storehouse"), ("woodcutter", harvester, "woodcutter"), ("farmhouse", agri, "farmhouse"),
    ("quarry", rig, "quarry"),
    ("site_0", lambda c: site(c, 0), "site_0"), ("site_1", lambda c: site(c, 1), "site_1"),
    ("deposit_0", lambda c: deposit(c, 0), "deposit_0"), ("deposit_1", lambda c: deposit(c, 1), "deposit_1"),
    ("bridge", bridge, "bridge"),
]

if __name__ == "__main__":
    for name, fn, out in JOBS:
        if ONLY and name not in ONLY: continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        col = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(col)
        sx, sy = fn(col)
        od = os.path.join(OUT_DIR, os.path.dirname(out))
        base = os.path.basename(out)
        # fit = own size -> scale 1 (everything is modelled at game scale)
        big = 1000.0
        sf.weather(col, 0.8 if name.startswith("site") else 1.0)
        hv.finish(col, base, big, big, fit_w=big, fit_d=big, out_dir=od)
        if PREVIEW:
            hv.render_preview(os.path.join(OUT_DIR, f"_{name}_preview.png"))
