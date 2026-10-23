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
	var pc: Vector2 = pond["pos"]; var pr: float = pond["radius"]
	for py in range(floori((pc.y - pr - 2.5 - ORIGIN.y) / RES), ceili((pc.y + pr + 2.5 - ORIGIN.y) / RES)):
		for px in range(floori((pc.x - pr - 2.5 - ORIGIN.x) / RES), ceili((pc.x + pr + 2.5 - ORIGIN.x) / RES)):
			if px < 0 or py < 0 or px >= SIZE or py >= SIZE: continue
			var p := ORIGIN + Vector2(px + 0.5, py + 0.5) * RES
			var d := p.distance_to(pc) - pr
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
	var pc: Vector2 = pond["pos"]; var pr: float = pond["radius"] + 0.5
	var sp := SurfaceTool.new()
	sp.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 48:
		var a0 := k / 48.0 * TAU; var a1 := (k + 1) / 48.0 * TAU
		for q in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:
			sp.set_uv(q * 0.5 + Vector2(0.5, 0.5)); sp.set_normal(Vector3.UP)
			sp.add_vertex(Vector3(pc.x + q.x * pr, _pond_level, pc.y + q.y * pr))
	var pond_mi := MeshInstance3D.new()
	pond_mi.name = "Pond"
	pond_mi.mesh = sp.commit()
	var pm := mat.duplicate()
	pm.set_shader_parameter("flow", 0.0)
	pond_mi.material_override = pm
	pond_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pond_mi)
	# bridges
	for b in bridges:
		var node: Node3D
		if ResourceLoader.exists(BRIDGE_MODEL):
			node = (load(BRIDGE_MODEL) as PackedScene).instantiate()
		else:
			var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.8, 0.12, 6.0); mi.mesh = bm; node = mi
		var d: Vector2 = b["dir"]
		node.position = Vector3(b["pos"].x, b["deck_y"] - 0.05, b["pos"].y)
		node.rotation.y = atan2(d.x, d.y)                 # model length runs along local +Z
		node.scale = Vector3(1, 1, b["half_len"] * 2.0 / 6.0)
		add_child(node)

func _across(i: int) -> Vector2:
	var pts := river_samples()
	var tangent := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
	return Vector2(-tangent.y, tangent.x)
