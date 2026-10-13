class_name Zones
extends Node
## Residential zones: the player paints where people may live; when the village needs beds
## (and can pay), villagers put up a house on a free spot inside a zone, door facing a path.

signal house_grown(id: int)

@export var build_path: NodePath = ^"../BuildController"
@export var nav_path: NodePath = ^"../Nav"
@export var wear_path: NodePath = ^"../PathWear"

var painting := false            # brush active (stronger overlay)
var _img: Image
var _tex: ImageTexture
var _check_acc := 0.0
var _since_last := 999.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 99
	var w: int = Defs.ZONE["w"]
	_img = Image.create(w, w, false, Image.FORMAT_L8)
	_tex = ImageTexture.create_from_image(_img)
	Game.zones_changed.connect(_refresh_texture)
	call_deferred("_hook_ground")

func _hook_ground() -> void:
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("set_ground_param"):
		var w: int = Defs.ZONE["w"]
		var o: Vector2 = Defs.ZONE["origin"]
		wear.set_ground_param("zone_tex", _tex)
		wear.set_ground_param("zone_rect", Vector4(o.x, o.y, w * Defs.ZONE["cell"], w * Defs.ZONE["cell"]))
	_refresh_texture()
	set_painting(false)

func set_painting(on: bool) -> void:
	painting = on
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("set_ground_param"):
		wear.set_ground_param("zone_strength", 1.0 if on else 0.45)

# ---------------- grid ----------------

func cell_of(p: Vector2) -> Vector2i:
	var o: Vector2 = Defs.ZONE["origin"]; var c: float = Defs.ZONE["cell"]
	return Vector2i(floori((p.x - o.x) / c), floori((p.y - o.y) / c))

func cell_center(c: Vector2i) -> Vector2:
	var o: Vector2 = Defs.ZONE["origin"]; var s: float = Defs.ZONE["cell"]
	return o + (Vector2(c) + Vector2(0.5, 0.5)) * s

func is_zoned(p: Vector2) -> bool:
	var c := cell_of(p); var w: int = Defs.ZONE["w"]
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= w: return false
	return Game.zones[c.y * w + c.x] == 1

## Paint (or erase) a disc of zone cells. Scenery cells and the village centre are skipped.
func paint(p: Vector2, on: bool, radius := -1.0) -> int:
	if radius < 0: radius = Defs.ZONE["brush_radius"]
	var nav := get_node_or_null(nav_path)
	var w: int = Defs.ZONE["w"]
	var c0 := cell_of(p - Vector2(radius, radius)); var c1 := cell_of(p + Vector2(radius, radius))
	var changed := 0
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			if x < 0 or z < 0 or x >= w or z >= w: continue
			var cc := cell_center(Vector2i(x, z))
			if cc.distance_to(p) > radius: continue
			if on:
				if not Defs.BUILD_BOUNDS.has_point(cc): continue
				var blocked := false
				for r in Defs.NO_BUILD:
					if (r as Rect2).has_point(cc): blocked = true
				if nav and nav.scenery_at(cc): blocked = true
				if blocked: continue
			var i := z * w + x
			if Game.zones[i] != (1 if on else 0):
				Game.set_zone(i, on); changed += 1
	if changed > 0: Game.zones_changed.emit()
	return changed

func _refresh_texture() -> void:
	if _img == null: return
	var w: int = Defs.ZONE["w"]
	var bytes := PackedByteArray(); bytes.resize(w * w)
	for i in mini(bytes.size(), Game.zones.size()):
		bytes[i] = 255 if Game.zones[i] else 0
	_img.set_data(w, w, false, Image.FORMAT_L8, bytes)
	_tex.update(_img)

# ---------------- growth ----------------

func _process(delta: float) -> void:
	tick(delta * Game.speed)

func tick(dt: float) -> void:
	if dt <= 0.0: return
	_since_last += dt
	_check_acc += dt
	if _check_acc < Defs.ZONE["grow_check"]: return
	_check_acc = 0.0
	if should_grow():
		grow()

func should_grow() -> bool:
	if _since_last < Defs.ZONE["grow_cooldown"]: return false
	if Game.zone_count() == 0: return false
	if Game.housing() - Game.population > int(Defs.ZONE["free_beds_trigger"]): return false
	if Game.starving or int(Game.resources.get("food", 0)) < Defs.GROWTH_FOOD_MIN: return false
	return Game.can_afford(Defs.BUILDINGS["house"]["cost"])

## Builds a house on the best free spot in a zone. Returns the building id or -1.
func grow() -> int:
	var spot := find_house_spot()
	if spot.is_empty(): return -1
	var b := Game.add_building("house", spot["pos"], spot["angle"])
	if b.is_empty(): return -1
	_since_last = 0.0
	Game.toast.emit("村民在住宅區蓋了一間新房子")
	house_grown.emit(b["id"])
	return b["id"]

## Best place for a house fully inside zoned ground: {"pos", "angle"} or {}.
## Houses line up with their neighbours (rows/streets) and turn their door toward a path or the centre.
func find_house_spot() -> Dictionary:
	var ctl := get_node_or_null(build_path)
	if ctl == null: return {}
	var w: int = Defs.ZONE["w"]
	var h := Defs.half_extents("house")
	var best := {}; var best_score := -INF
	var step := PI / 12.0
	for i in Game.zones.size():
		if Game.zones[i] == 0: continue
		var pos := cell_center(Vector2i(i % w, i / w))
		var face := _face_dir(pos)
		var face_angle := atan2(face.x, face.y)
		# candidate angles: aligned with nearby houses first, then facing the path/centre
		var cands: Array[float] = []
		for b in Game.buildings:
			if b["type"] == "house" and b["pos"].distance_to(pos) < 8.0:
				for q in 4:
					cands.append(snappedf(b["angle"] + q * PI / 2.0, 0.0001))
		var fa := snappedf(face_angle, step)
		cands.append_array([fa, fa + step, fa - step, fa + 2 * step, fa - 2 * step])
		for angle in cands:
			if not _footprint_in_zone(pos, h, angle): continue
			if not ctl.can_place("house", pos, angle): continue
			var facing := cos(angle_difference(angle, face_angle))      # 1 = door straight at the path/centre
			if facing < 0.2: continue
			var score := _score(pos) + facing * 2.0
			if score > best_score:
				best_score = score; best = {"pos": pos, "angle": angle}
	return best

func _footprint_in_zone(pos: Vector2, h: Vector2, angle: float) -> bool:
	for i in 5:
		for j in 5:
			var l := Vector2(-h.x + 2 * h.x * i / 4.0, -h.y + 2 * h.y * j / 4.0) * 0.92
			if not is_zoned(pos + Defs.rot2(l, angle)): return false
	return true

## Door direction: toward the nearest worn path within reach, else toward the village centre.
func _face_dir(pos: Vector2) -> Vector2:
	var wear := get_node_or_null(wear_path)
	var best := Vector2.ZERO; var best_d := INF
	if wear:
		for k in 16:
			var a := TAU * k / 16.0
			for r in [2.5, 3.5, 4.5, 6.0]:
				var p: Vector2 = pos + Vector2(cos(a), sin(a)) * r
				if wear.wear_at(Vector3(p.x, 0, p.y)) > 0.35:
					if r < best_d: best_d = r; best = p - pos
					break
	if best == Vector2.ZERO:
		best = Defs.STORAGE_POINT - pos
	return best.normalized() if best.length() > 0.01 else Vector2(0, 1)

## Prefer spots near the village centre and snug against other buildings (tight neighbourhoods).
func _score(pos: Vector2) -> float:
	var s := -pos.distance_to(Defs.STORAGE_POINT) * 0.25
	var nearest := INF
	for b in Game.buildings:
		nearest = minf(nearest, b["pos"].distance_to(pos))
	if nearest < 6.0: s += (6.0 - nearest) * 0.8
	return s + _rng.randf() * 0.3
