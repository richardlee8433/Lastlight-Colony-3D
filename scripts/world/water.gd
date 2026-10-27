class_name Water
extends Node3D
## The stream and the pond. The static part (shape, carve profile, nav changes) is used by NavGrid
## while it loads; the node builds the water surfaces, the bridges and hooks the carve into the ground
## shader. The same profile lowers the ground mesh (shader) and the walk-grid heights, so both agree.

@export var nav_path: NodePath = ^"../Nav"
@export var wear_path: NodePath = ^"../PathWear"

const WATER_SHADER := preload("res://scripts/world/water.gdshader")
const BRIDGE_MODEL := "res://models/bridge.glb"
const RES := 0.25                   # carve texture: metres per pixel
const ORIGIN := Vector2(-40, -40)   # covers the ground including the border forest
const SIZE := 320

static var _img: Image
static var _tex: ImageTexture
static var _samples := PackedVector2Array()     # smoothed river centre line
static var _levels := PackedFloat32Array()      # water surface height per sample
static var _pond_level := 0.0
static var bridges: Array = []                  # [{"pos", "dir" (across the stream), "half_len", "deck_y"}]

# ---------------- shape ----------------

static func river_samples() -> PackedVector2Array:
	if not _samples.is_empty(): return _samples
	var cp: Array = Defs.WATER["river"]
	for i in cp.size() - 1:
		var p0: Vector2 = cp[maxi(i - 1, 0)]; var p1: Vector2 = cp[i]
		var p2: Vector2 = cp[i + 1]; var p3: Vector2 = cp[mini(i + 2, cp.size() - 1)]
		var n := maxi(2, ceili(p1.distance_to(p2) / 0.75))
		for k in n:
			var t := float(k) / n
			_samples.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	_samples.append(cp[cp.size() - 1])
	return _samples

## The pond's outline: radius by direction, a few lobes so it reads as a natural pond (2.4 - 4.4 m).
static func pond_radius(a: float) -> float:
	var pond: Dictionary = Defs.WATER["pond"]
	var r: float = pond["radius"]; var ph: float = pond.get("phase", 0.0)
	return r * (1.0 + 0.15 * cos(a - 0.5 + ph) + 0.17 * cos(2.0 * a + 1.1 + ph * 2.0)
		+ 0.08 * cos(3.0 * a - 0.7 + ph * 3.0) + 0.04 * sin(5.0 * a + 0.3))

## signed distance to the pond's edge (negative inside)
static func pond_distance(p: Vector2) -> float:
	var pc: Vector2 = Defs.WATER["pond"]["pos"]
	var d := p - pc
	return d.length() - pond_radius(atan2(d.y, d.x))

## Carve profile from the signed distance to the water edge (negative = in the water):
## x = how far the ground is lowered (0..1 of bed_depth), y = bank (wet sand / mud) 0..1
static func profile(s: float) -> Vector2:
	var carve := smoothstep(0.6, -1.3, s)
	var bank := 1.0 - smoothstep(0.1, 1.5, s)
	return Vector2(carve, bank)

## Builds the carve texture (R = carve, G = bank): only pixels near each segment are visited.
static func image() -> Image:
	if _img: return _img
	var data := PackedByteArray(); data.resize(SIZE * SIZE * 2)
	var best := PackedFloat32Array(); best.resize(SIZE * SIZE); best.fill(99.0)
	var hw: float = Defs.WATER["river_width"]
	var reach := hw + 2.0
	var pts := river_samples()
	for i in pts.size() - 1:
		var a := pts[i]; var b := pts[i + 1]
		var lo := a.min(b) - Vector2(reach, reach); var hi := a.max(b) + Vector2(reach, reach)
		for py in range(maxi(0, floori((lo.y - ORIGIN.y) / RES)), mini(SIZE, ceili((hi.y - ORIGIN.y) / RES))):
			for px in range(maxi(0, floori((lo.x - ORIGIN.x) / RES)), mini(SIZE, ceili((hi.x - ORIGIN.x) / RES))):
				var p := ORIGIN + Vector2(px + 0.5, py + 0.5) * RES
				var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - hw
				var j := py * SIZE + px
				if d < best[j]: best[j] = d
	var pond: Dictionary = Defs.WATER["pond"]
	var pc: Vector2 = pond["pos"]; var pr: float = float(pond["radius"]) * 1.45
	for py in range(floori((pc.y - pr - 2.5 - ORIGIN.y) / RES), ceili((pc.y + pr + 2.5 - ORIGIN.y) / RES)):
		for px in range(floori((pc.x - pr - 2.5 - ORIGIN.x) / RES), ceili((pc.x + pr + 2.5 - ORIGIN.x) / RES)):
			if px < 0 or py < 0 or px >= SIZE or py >= SIZE: continue
			var p := ORIGIN + Vector2(px + 0.5, py + 0.5) * RES
			var d := pond_distance(p)
			var j := py * SIZE + px
			if d < best[j]: best[j] = d
	for j in SIZE * SIZE:
		if best[j] < 90.0:
			var pr2 := profile(best[j])
			data[j * 2] = int(pr2.x * 255.0); data[j * 2 + 1] = int(pr2.y * 255.0)
	_img = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RG8, data)
	return _img

static func texture() -> ImageTexture:
	if _tex == null: _tex = ImageTexture.create_from_image(image())
	return _tex

## (carve 0..1, bank 0..1) at a world point
static func sample(p: Vector2) -> Vector2:
	var px := int((p.x - ORIGIN.x) / RES); var py := int((p.y - ORIGIN.y) / RES)
	if px < 0 or py < 0 or px >= SIZE or py >= SIZE: return Vector2.ZERO
	var c := image().get_pixel(px, py)
	return Vector2(c.r, c.g)

static func is_water(p: Vector2) -> bool:
	return sample(p).x > 0.42

# ---------------- walk grid ----------------

## Called by NavGrid while it loads: lowers the heights like the ground shader does, blocks the
## water, records the water levels and lays the bridge decks (walkable, at bank height).
static func apply_to_nav(nav) -> void:
	bridges.clear()
	var depth: float = Defs.WATER["bed_depth"]
	var below: float = Defs.WATER["level_below"]
	# water levels from the original (uncarved) ground along the centre line, smoothed
	var pts := river_samples()
	var raw := PackedFloat32Array(); raw.resize(pts.size())
	for i in pts.size():
		var q := pts[i]
		raw[i] = nav.height_at(clampf(q.x, -33.9, 33.9), clampf(q.y, -33.9, 33.9)) - below
	_levels = PackedFloat32Array(); _levels.resize(pts.size())
	for i in pts.size():
		var sum := 0.0; var n := 0
		for k in range(maxi(0, i - 6), mini(pts.size(), i + 7)):
			sum += raw[k]; n += 1
		_levels[i] = sum / n
	var pc: Vector2 = Defs.WATER["pond"]["pos"]
	_pond_level = nav.height_at(pc.x, pc.y) - below
	# bridges: snap to the stream, across it
	var hw: float = Defs.WATER["river_width"]
	for bp in Defs.WATER["bridges"]:
		var bi := 0; var bd := INF
		for i in pts.size():
			var d := pts[i].distance_to(bp)
			if d < bd: bd = d; bi = i
		var tangent := (pts[mini(bi + 1, pts.size() - 1)] - pts[maxi(bi - 1, 0)]).normalized()
		var across := Vector2(-tangent.y, tangent.x)
		var half_len := hw + 1.6
		var e0: Vector2 = pts[bi] - across * half_len; var e1: Vector2 = pts[bi] + across * half_len
		var deck := maxf(nav.height_at(e0.x, e0.y), nav.height_at(e1.x, e1.y)) + 0.05
		bridges.append({"pos": pts[bi], "dir": across, "half_len": half_len, "deck_y": deck})
	# carve the walk-grid heights and block the water (bridge decks stay walkable)
	for z in nav.h:
		for x in nav.w:
			var c: Vector3 = nav.cell_center(Vector2i(x, z))
			var p := Vector2(c.x, c.z)
			var f := sample(p)
			if f.x <= 0.0: continue
			var i: int = z * nav.w + x
			nav._height[i] -= depth * f.x
			var bridge := _bridge_at(p)
			if not bridge.is_empty():
				var t: float = absf((p - bridge["pos"]).dot(bridge["dir"])) / bridge["half_len"]
				nav._height[i] = bridge["deck_y"] + 0.18 * (1.0 - t * t)
				nav._static[i] = 0                     # the deck is walkable, whatever stood there before
			elif f.x > 0.42:
				nav._static[i] = 1

static func _bridge_at(p: Vector2) -> Dictionary:
	var bw: float = Defs.WATER["bridge_width"]
	for b in bridges:
		var l: Vector2 = p - b["pos"]
		var along: float = l.dot(b["dir"])
		var side: float = l.dot(Vector2(-b["dir"].y, b["dir"].x))
		if absf(along) <= b["half_len"] and absf(side) <= bw: return b
	return {}

# ---------------- node: surfaces, bridges, ground hook ----------------

func _ready() -> void:
	_fish_rng.seed = 2024
	call_deferred("_build")

func _build() -> void:
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("set_ground_param"):
		wear.set_ground_param("water_tex", texture())
		wear.set_ground_param("water_rect", Vector4(ORIGIN.x, ORIGIN.y, SIZE * RES, SIZE * RES))
		wear.set_ground_param("bed_depth", float(Defs.WATER["bed_depth"]))
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	for k in ["ripples_a", "ripples_b"]:
		var n := FastNoiseLite.new()
		n.seed = 21 if k == "ripples_a" else 77
		n.frequency = 0.02 if k == "ripples_a" else 0.035
		n.fractal_octaves = 3
		var nt := NoiseTexture2D.new()
		nt.noise = n; nt.seamless = true; nt.as_normal_map = true; nt.bump_strength = 6.0
		nt.width = 256; nt.height = 256; nt.generate_mipmaps = true
		mat.set_shader_parameter(k, nt)
	var fnz := FastNoiseLite.new()
	fnz.seed = 9; fnz.noise_type = FastNoiseLite.TYPE_CELLULAR; fnz.frequency = 0.03
	fnz.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var ft := NoiseTexture2D.new()
	ft.noise = fnz; ft.seamless = true; ft.width = 256; ft.height = 256; ft.generate_mipmaps = true
	mat.set_shader_parameter("foam_noise", ft)
	# stream: a strip along the centre line at the smoothed water level
	var pts := river_samples()
	var hw: float = Defs.WATER["river_width"] + 0.45
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vdist := 0.0
	for i in pts.size():
		var tangent := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var across := Vector2(-tangent.y, tangent.x)
		if i > 0: vdist += pts[i].distance_to(pts[i - 1])
		var y: float = _levels[i] if i < _levels.size() else 0.0
		var l := pts[i] - across * hw; var r := pts[i] + across * hw
		if i > 0:
			var pl := pts[i - 1] - _across(i - 1) * hw; var pr := pts[i - 1] + _across(i - 1) * hw
			var py: float = _levels[i - 1] if i - 1 < _levels.size() else 0.0
			for v in [[pl, py, 0.0, vdist - pts[i].distance_to(pts[i - 1])], [pr, py, 1.0, vdist - pts[i].distance_to(pts[i - 1])], [r, y, 1.0, vdist],
					[pl, py, 0.0, vdist - pts[i].distance_to(pts[i - 1])], [r, y, 1.0, vdist], [l, y, 0.0, vdist]]:
				st.set_uv(Vector2(v[2], v[3] * 0.25))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(v[0].x, v[1], v[0].y))
	var river := MeshInstance3D.new()
	river.name = "Stream"
	river.mesh = st.commit()
	river.material_override = mat
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)
	# pond: a disc
	var pond: Dictionary = Defs.WATER["pond"]
	var pc: Vector2 = pond["pos"]
	var sp := SurfaceTool.new()
	sp.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 72:
		var a0 := k / 72.0 * TAU; var a1 := (k + 1) / 72.0 * TAU
		for q in [Vector2.ZERO, Vector2(cos(a1), sin(a1)) * (pond_radius(a1) + 0.5), Vector2(cos(a0), sin(a0)) * (pond_radius(a0) + 0.5)]:
			sp.set_uv(q * 0.1 + Vector2(0.5, 0.5)); sp.set_normal(Vector3.UP)
			sp.add_vertex(Vector3(pc.x + q.x, _pond_level, pc.y + q.y))
	var pond_mi := MeshInstance3D.new()
	pond_mi.name = "Pond"
	pond_mi.mesh = sp.commit()
	var pm := mat.duplicate()
	pm.set_shader_parameter("flow", 0.0)
	pm.set_shader_parameter("foam_amount", 0.45)
	pond_mi.material_override = pm
	pond_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pond_mi)
	_life()
	# bridges
	for b in bridges:
		var node: Node3D
		if ResourceLoader.exists(BRIDGE_MODEL):
			node = (load(BRIDGE_MODEL) as PackedScene).instantiate()
			DayNight.dress(node)
		else:
			var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.8, 0.12, 6.0); mi.mesh = bm; node = mi
		var d: Vector2 = b["dir"]
		node.position = Vector3(b["pos"].x, b["deck_y"] - 0.05, b["pos"].y)
		node.rotation.y = atan2(d.x, d.y)                 # model length runs along local +Z
		node.scale = Vector3(1, 1, b["half_len"] * 2.0 / 6.0)
		add_child(node)

# ---------------- lake life: alien reeds, float pads, gas bubbles ----------------

var _jump_timer := 2.0
var _fish_rng := RandomNumberGenerator.new()

static func _reed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	for k in 9:
		var a := rng.randf() * TAU; var r := rng.randf_range(0.0, 0.12)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(0.7, 1.25)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var side := Vector3(-sin(a), 0, cos(a)) * 0.022
		var lo := Color(0.22, 0.20, 0.26); var hi := Color(0.62, 0.58, 0.70)      # pale alien stalks
		for tri in [[base - side, base + side, base + lean + Vector3(0, h, 0)]]:
			st.set_color(lo); st.add_vertex(tri[0])
			st.set_color(lo); st.add_vertex(tri[1])
			st.set_color(hi); st.add_vertex(tri[2])
		if k % 3 == 0:
			# a cattail head on some stems
			var top := base + lean * 0.8 + Vector3(0, h * 0.8, 0)
			var brown := Color(0.45, 0.95, 0.85)                  # glowing seed heads
			for j in 6:
				var a0 := j / 6.0 * TAU; var a1 := (j + 1) / 6.0 * TAU
				var p0 := top + Vector3(cos(a0), 0, sin(a0)) * 0.03; var p1 := top + Vector3(cos(a1), 0, sin(a1)) * 0.03
				var q0 := p0 + Vector3(0, 0.14, 0); var q1 := p1 + Vector3(0, 0.14, 0)
				for v in [p0, p1, q1, p0, q1, q0]:
					st.set_color(brown); st.add_vertex(v)
	st.generate_normals()
	return st.commit()

static func _lily_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := Color(0.16, 0.36, 0.40)                          # teal float pads
	for k in 14:
		var a0 := 0.35 + k / 14.0 * (TAU - 0.35); var a1 := 0.35 + (k + 1) / 14.0 * (TAU - 0.35)
		st.set_color(g.lightened(0.15)); st.add_vertex(Vector3.ZERO)
		st.set_color(g); st.add_vertex(Vector3(cos(a1), 0, sin(a1)) * 0.22)
		st.set_color(g); st.add_vertex(Vector3(cos(a0), 0, sin(a0)) * 0.22)
	st.generate_normals()
	return st.commit()

static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := k / 6.0 * TAU
		var tip := Vector3(cos(a) * 0.07, 0.05, sin(a) * 0.07)
		var l := Vector3(cos(a - 0.4) * 0.025, 0.01, sin(a - 0.4) * 0.025)
		var r := Vector3(cos(a + 0.4) * 0.025, 0.01, sin(a + 0.4) * 0.025)
		for v in [Vector3(0, 0.02, 0), r, tip, Vector3(0, 0.02, 0), tip, l]:
			st.set_color(Color(0.62, 1.0, 0.92)); st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _life() -> void:
	var nav := get_node_or_null(nav_path)
	if nav == null: return
	var rng := RandomNumberGenerator.new(); rng.seed = 808
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true; mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# reeds along the banks: dense around the pond, in clumps along the stream
	var reeds: Array[Transform3D] = []
	var pond: Dictionary = Defs.WATER["pond"]
	var pc: Vector2 = pond["pos"]
	for k in 90:
		var a := rng.randf() * TAU
		var p := pc + Vector2(cos(a), sin(a)) * (pond_radius(a) + rng.randf_range(-0.2, 0.7))
		if rng.randf() < 0.3: continue        # gaps where the shore is open
		reeds.append(_ground_xf(nav, p, rng, rng.randf_range(0.8, 1.2)))
	var pts := river_samples()
	for i in range(0, pts.size(), 2):
		if rng.randf() > 0.35: continue
		var tangent := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var across := Vector2(-tangent.y, tangent.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var base := pts[i] + across * (float(Defs.WATER["river_width"]) + rng.randf_range(-0.1, 0.5))
		if not _bridge_at(base).is_empty() or absf(base.x) > 33 or absf(base.y) > 33: continue
		for j in rng.randi_range(2, 5):
			reeds.append(_ground_xf(nav, base + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)), rng, rng.randf_range(0.7, 1.1)))
	_multimesh("Reeds", _reed_mesh(), reeds, mat, true)
	# lily pads and a few flowers on the pond
	var pads: Array[Transform3D] = []; var flowers: Array[Transform3D] = []
	for k in 26:
		var a := rng.randf() * TAU; var r := sqrt(rng.randf()) * (pond_radius(a) - 0.6)
		var p := pc + Vector2(cos(a), sin(a)) * r
		var s := rng.randf_range(0.7, 1.4)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s)), Vector3(p.x, _pond_level + 0.012, p.y))
		pads.append(xf)
		if rng.randf() < 0.25: flowers.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), xf.origin + Vector3(0, 0.005, 0)))
	_multimesh("LilyPads", _lily_mesh(), pads, mat, false)
	var fmat := mat.duplicate()
	_multimesh("Lilies", _flower_mesh(), flowers, fmat, false)
	# a few stones breaking the surface of the stream (the water foams around them)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.46, 0.45, 0.42); stone.roughness = 0.85
	var rocks: Array[Transform3D] = []
	var hw: float = Defs.WATER["river_width"]
	for i in range(6, pts.size() - 6, 5):
		if rng.randf() > 0.55: continue
		var q := pts[i]
		if absf(q.x) > 32 or absf(q.y) > 32 or not _bridge_at(q).is_empty(): continue
		var tangent := (pts[i + 1] - pts[i - 1]).normalized()
		var across := Vector2(-tangent.y, tangent.x)
		for j in rng.randi_range(1, 3):
			var rp := q + across * rng.randf_range(-hw * 0.75, hw * 0.75) + tangent * rng.randf_range(-0.6, 0.6)
			var sz := rng.randf_range(0.18, 0.38)
			var y: float = _levels[i] - sz * 0.35
			rocks.append(Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(sz * 1.3, sz, sz * 1.1)), Vector3(rp.x, y, rp.y)))
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0; rock_mesh.height = 1.6; rock_mesh.radial_segments = 7; rock_mesh.rings = 4
	_multimesh("StreamRocks", rock_mesh, rocks, stone, false)

func _ground_xf(nav, p: Vector2, rng: RandomNumberGenerator, s: float) -> Transform3D:
	var y: float = nav.height_at(clampf(p.x, -33.9, 33.9), clampf(p.y, -33.9, 33.9))
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, y - 0.05, p.y))

func _multimesh(name_: String, mesh: Mesh, xfs: Array[Transform3D], mat: Material, sway: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	if sway:
		var wm := Wheat.material().duplicate() as ShaderMaterial    # wind sway; growth 1 keeps the vertex colours
		wm.set_shader_parameter("growth", 1.0)
		mmi.material_override = wm
	else:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _process(delta: float) -> void:
	if Game.speed <= 0.0 or _levels.is_empty(): return
	_jump_timer -= delta * Game.speed
	if _jump_timer > 0.0: return
	_jump_timer = _fish_rng.randf_range(2.5, 6.0)
	# gas from the lake bed: a bubble swells on the surface and pops (thin air, cold water)
	var p: Vector2; var y: float
	if _fish_rng.randf() < 0.5:
		var pond: Dictionary = Defs.WATER["pond"]
		var a := _fish_rng.randf() * TAU
		p = (pond["pos"] as Vector2) + Vector2(cos(a), sin(a)) * _fish_rng.randf() * (pond_radius(a) - 0.8)
		y = _pond_level
	else:
		var pts := river_samples()
		var i := _fish_rng.randi_range(4, pts.size() - 5)
		p = pts[i]; y = _levels[i]
		if absf(p.x) > 33 or absf(p.y) > 33: return
	vent_bubble(Vector3(p.x, y, p.y))

## A gas bubble swells on the water and pops, leaving a ripple ring.
func vent_bubble(at: Vector3) -> void:
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.1; sm.height = 0.1; sm.is_hemisphere = true
	b.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.75, 0.85, 0.85, 0.35); bm.metallic = 0.4; bm.roughness = 0.05
	b.material_override = bm
	b.position = at
	b.scale = Vector3(0.1, 0.1, 0.1)
	add_child(b)
	var size := _fish_rng.randf_range(0.8, 1.8)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector3(size, size * 0.8, size), _fish_rng.randf_range(0.8, 1.6)).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _splash(at); b.queue_free())

func _splash(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.08; tm.outer_radius = 0.11; tm.rings = 24; tm.ring_segments = 4
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.75)
	ring.material_override = m
	ring.position = at + Vector3(0, 0.02, 0)
	ring.scale = Vector3(1, 0.2, 1)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(4.5, 0.2, 4.5), 1.1)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(ring.queue_free)

func _across(i: int) -> Vector2:
	var pts := river_samples()
	var tangent := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
	return Vector2(-tangent.y, tangent.x)
