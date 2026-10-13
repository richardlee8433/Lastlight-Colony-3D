class_name Fields
extends Node3D
## Farm fields: each farmhouse owns a painted set of cells (same 0.5 m grid as zones).
## Wheat grows in rows across the field, the ground turns to furrowed soil, grass is cleared,
## and the harvest per trip grows with the field size.

signal changed(farm_id: int)

@export var build_path: NodePath = ^"../BuildController"
@export var nav_path: NodePath = ^"../Nav"
@export var scatter_path: NodePath = ^"../Scatter"
@export var wear_path: NodePath = ^"../PathWear"

const ROW := 0.6                 # furrow spacing (m)

var owner_map := PackedInt32Array()       # cell -> farm id (0 = none)
var editing := -1                         # farm whose field is being painted
var _mask_img: Image
var _mask_tex: ImageTexture
var _ang_img: Image
var _ang_tex: ImageTexture
var _wheat := {}                          # farm id -> MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	var w: int = Defs.ZONE["w"]
	owner_map.resize(w * w)
	_mask_img = Image.create(w, w, false, Image.FORMAT_L8)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	_ang_img = Image.create(w, w, false, Image.FORMAT_L8)
	_ang_tex = ImageTexture.create_from_image(_ang_img)
	Game.building_added.connect(_on_added)
	Game.building_removed.connect(_on_removed)
	Game.reset.connect(_on_reset)
	call_deferred("_init_existing")

func _init_existing() -> void:
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("set_ground_param"):
		var w: int = Defs.ZONE["w"]; var o: Vector2 = Defs.ZONE["origin"]
		wear.set_ground_param("field_tex", _mask_tex)
		wear.set_ground_param("field_ang_tex", _ang_tex)
		wear.set_ground_param("field_rect", Vector4(o.x, o.y, w * Defs.ZONE["cell"], w * Defs.ZONE["cell"]))
	_rebuild_owner_map()
	for b in Game.buildings:
		if b["type"] == "farm":
			if not b.has("field") or (b["field"] as Array).is_empty():
				auto_field(b)            # saves from before painted fields
			else:
				_refresh_farm(b["id"])
	_refresh_textures()

# ---------------- grid helpers ----------------

func _w() -> int: return Defs.ZONE["w"]

func cell_of(p: Vector2) -> int:
	var o: Vector2 = Defs.ZONE["origin"]; var c: float = Defs.ZONE["cell"]
	var x := floori((p.x - o.x) / c); var z := floori((p.y - o.y) / c)
	if x < 0 or z < 0 or x >= _w() or z >= _w(): return -1
	return z * _w() + x

func cell_center(i: int) -> Vector2:
	var o: Vector2 = Defs.ZONE["origin"]; var c: float = Defs.ZONE["cell"]
	return o + Vector2(i % _w() + 0.5, i / _w() + 0.5) * c

func field_of(id: int) -> Array:
	var b := Game.get_building(id)
	if b.is_empty(): return []
	if not b.has("field"): b["field"] = []
	return b["field"]

func is_field(p: Vector2) -> bool:
	var i := cell_of(p)
	return i >= 0 and owner_map[i] != 0

# ---------------- rules ----------------

## Why a cell can't be part of this farm's field ("" = it can).
func cell_problem(farm: Dictionary, i: int) -> String:
	if i < 0: return Loc.t("out of range")
	var p := cell_center(i)
	if not Defs.BUILD_BOUNDS.has_point(p): return Loc.t("out of range")
	if p.distance_to(farm["pos"]) > Defs.FIELD["range"]: return Loc.t("too far from the farmhouse")
	if owner_map[i] != 0 and owner_map[i] != farm["id"]: return Loc.t("another farm's field")
	if Game.zones.size() > i and Game.zones[i] == 1: return Loc.t("housing zone")
	var forest := get_node_or_null(^"../Forest")
	if forest and forest.owner_map[i] != 0: return Loc.t("forest area")
	var nav := get_node_or_null(nav_path)
	if nav and nav.scenery_at(p): return Loc.t("obstacle")
	for b in Game.buildings:
		var l := Defs.to_local(b, p)
		var h := Defs.half_extents(b["type"]) + Vector2(0.1, 0.1)
		if absf(l.x) <= h.x and absf(l.y) <= h.y: return Loc.t("building")
	return ""

## Paint (on) or erase a disc of the farm's field. Returns cells changed.
func paint(farm_id: int, p: Vector2, on: bool, radius := -1.0) -> int:
	var farm := Game.get_building(farm_id)
	if farm.is_empty(): return 0
	if radius < 0: radius = Defs.ZONE["brush_radius"]
	var cells: Array = field_of(farm_id)
	var c: float = Defs.ZONE["cell"]
	var n := 0
	var steps := ceili(radius / c)
	var ci := cell_of(p)
	if ci < 0: return 0
	var cx := ci % _w(); var cz := ci / _w()
	for dz in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			var x := cx + dx; var z := cz + dz
			if x < 0 or z < 0 or x >= _w() or z >= _w(): continue
			var i := z * _w() + x
			if cell_center(i).distance_to(p) > radius: continue
			if on:
				if owner_map[i] == farm_id: continue
				if cells.size() >= Defs.FIELD["max_cells"]: break
				if cell_problem(farm, i) != "": continue
				cells.append(i); owner_map[i] = farm_id; n += 1
			elif owner_map[i] == farm_id:
				cells.erase(i); owner_map[i] = 0; n += 1
	if n > 0:
		_refresh_farm(farm_id)
		_refresh_textures()
		changed.emit(farm_id)
		Game.changed.emit()
	return n

## Erase this farm's whole field.
func clear(farm_id: int) -> int:
	var cells := field_of(farm_id)
	var n := cells.size()
	for i in cells: owner_map[int(i)] = 0
	cells.clear()
	_refresh_farm(farm_id); _refresh_textures()
	changed.emit(farm_id); Game.changed.emit()
	return n

## Highlight the field being edited (the ground shader brightens its outline).
func set_editing(farm_id: int) -> void:
	editing = farm_id
	_refresh_textures()
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("set_ground_param"):
		wear.set_ground_param("field_edit", 1.0 if farm_id >= 0 else 0.0)

## A starter field next to a new farmhouse: tries the front, then the sides and the back.
func auto_field(farm: Dictionary) -> int:
	var best_side := Vector2.ZERO; var best_cells: Array = []
	for side in [Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1)]:
		var cells: Array = []
		var w := 4.0; var d := 4.0
		var along: Vector2 = Vector2(side.y, side.x)         # perpendicular, local
		var start: Vector2 = side * (Defs.half_extents("farm").x + 0.45)
		for i in owner_map.size():
			var p := cell_center(i)
			var l := Defs.to_local(farm, p) - start
			var fwd := l.dot(side); var lat := l.dot(along)
			if fwd >= 0.0 and fwd <= d and absf(lat) <= w / 2.0:
				if cell_problem(farm, i) == "": cells.append(i)
		if cells.size() > best_cells.size():
			best_cells = cells; best_side = side
		if cells.size() >= 56: break
	var f: Array = field_of(farm["id"])
	for i in best_cells:
		if f.size() >= Defs.FIELD["max_cells"]: break
		f.append(i); owner_map[i] = farm["id"]
	_refresh_farm(farm["id"])
	_refresh_textures()
	changed.emit(farm["id"])
	return f.size()

## Food carried home per trip — bigger fields give more, up to a cap.
func yield_for(farm_id: int) -> int:
	var n := field_of(farm_id).size()
	if n < Defs.FIELD["min_cells"]: return 0
	return clampi(roundi(n / float(Defs.FIELD["cells_per_food"])), 1, Defs.FIELD["max_yield"])

## Where the farmer works next: a random spot in the field, facing along the furrows.
func work_spot(farm_id: int, rng: RandomNumberGenerator) -> Dictionary:
	var cells := field_of(farm_id)
	if cells.is_empty(): return {}
	var farm := Game.get_building(farm_id)
	var p := cell_center(cells[rng.randi() % cells.size()])
	var t := Vector2(cos(farm["angle"]), -sin(farm["angle"]))
	return {"pos": p, "look": p + t}

# ---------------- events ----------------

func _on_added(b: Dictionary) -> void:
	if b["type"] == "farm":
		if b.has("field") and not (b["field"] as Array).is_empty():
			for i in b["field"]: owner_map[int(i)] = b["id"]
			_refresh_farm(b["id"]); _refresh_textures()
		elif is_inside_tree() and get_node_or_null(nav_path) != null and get_node(nav_path).w > 0:
			auto_field(b)
	else:
		# a new building takes over any field cells under it
		var touched := {}
		for i in owner_map.size():
			if owner_map[i] == 0: continue
			var l := Defs.to_local(b, cell_center(i))
			var h := Defs.half_extents(b["type"])
			if absf(l.x) <= h.x and absf(l.y) <= h.y:
				var fid := owner_map[i]
				field_of(fid).erase(i); owner_map[i] = 0; touched[fid] = true
		for fid in touched: _refresh_farm(fid)
		if not touched.is_empty(): _refresh_textures()

func _on_removed(b: Dictionary) -> void:
	if b["type"] != "farm": return
	for i in owner_map.size():
		if owner_map[i] == b["id"]: owner_map[i] = 0
	if _wheat.has(b["id"]):
		_wheat[b["id"]].queue_free(); _wheat.erase(b["id"])
	if editing == b["id"]: editing = -1
	_update_grass_all()
	_refresh_textures()

func _on_reset() -> void:
	owner_map.fill(0)
	for id in _wheat: _wheat[id].queue_free()
	_wheat.clear()
	_update_grass_all()
	_refresh_textures()

func _rebuild_owner_map() -> void:
	owner_map.fill(0)
	for b in Game.buildings:
		if b["type"] == "farm" and b.has("field"):
			for i in b["field"]: owner_map[int(i)] = b["id"]

# ---------------- visuals ----------------

func _refresh_textures() -> void:
	var w := _w()
	var m := PackedByteArray(); m.resize(w * w)
	var a := PackedByteArray(); a.resize(w * w)
	for i in owner_map.size():
		if owner_map[i] != 0:
			m[i] = 255
			var b := Game.get_building(owner_map[i])
			if not b.is_empty():
				a[i] = int(fposmod(b["angle"], PI) / PI * 255.0)
	_mask_img.set_data(w, w, false, Image.FORMAT_L8, m); _mask_tex.update(_mask_img)
	_ang_img.set_data(w, w, false, Image.FORMAT_L8, a); _ang_tex.update(_ang_img)

func _refresh_farm(farm_id: int) -> void:
	_update_grass_all()
	_build_wheat(farm_id)

func _update_grass_all() -> void:
	var sc := get_node_or_null(scatter_path)
	if sc and sc.has_method("set_field_buckets"):
		var on := {}
		for i in owner_map.size():
			if owner_map[i] != 0: on[i] = true
		sc.set_field_buckets(on)

## Wheat rows: lines at dot(p, n) = k*ROW + ROW/2 in world space, the same lines the
## ground shader draws as ridges, so plants always sit on the furrow ridges.
func _build_wheat(farm_id: int) -> void:
	if _wheat.has(farm_id):
		_wheat[farm_id].queue_free(); _wheat.erase(farm_id)
	var farm := Game.get_building(farm_id)
	var cells := field_of(farm_id)
	if farm.is_empty() or cells.is_empty(): return
	var a: float = fposmod(farm["angle"], PI)
	var n := Vector2(sin(a), cos(a))
	var t := Vector2(cos(a), -sin(a))
	var smin := INF; var smax := -INF; var umin := INF; var umax := -INF
	for i in cells:
		var p := cell_center(i)
		smin = minf(smin, p.dot(n)); smax = maxf(smax, p.dot(n))
		umin = minf(umin, p.dot(t)); umax = maxf(umax, p.dot(t))
	var nav := get_node_or_null(nav_path)
	var rng := RandomNumberGenerator.new(); rng.seed = farm_id * 7177
	var xfs: Array[Transform3D] = []; var cols: Array[Color] = []
	var k0 := floori((smin - 0.5) / ROW); var k1 := ceili((smax + 0.5) / ROW)
	for k in range(k0, k1 + 1):
		var d := k * ROW + ROW / 2.0
		var u := umin - 0.4
		while u <= umax + 0.4:
			for lane: float in [-0.07, 0.07]:
				var p := n * (d + lane + rng.randf_range(-0.025, 0.025)) + t * (u + rng.randf_range(-0.03, 0.03))
				var ci := cell_of(p)
				if ci < 0 or owner_map[ci] != farm_id: continue
				var y: float = nav.height_at(p.x, p.y) if nav else 0.0
				var s := rng.randf_range(0.85, 1.15)
				var bas := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
				xfs.append(Transform3D(bas, Vector3(p.x, y + 0.03, p.y)))
				var g := rng.randf()
				cols.append(Color(1, 1, 1).lerp(Color(0.85, 0.95, 0.7), g * g * 0.6).darkened(rng.randf_range(0.0, 0.1)))
			u += 0.17
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Wheat.clump_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i]); mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Wheat%d" % farm_id
	mmi.multimesh = mm
	mmi.material_override = Wheat.material()
	add_child(mmi)
	_wheat[farm_id] = mmi

func wheat_count(farm_id: int) -> int:
	return _wheat[farm_id].multimesh.instance_count if _wheat.has(farm_id) else 0
