class_name Forest
extends Node3D
## Every tree inside the map, and the woodcutters' painted forest areas.
## Game.trees holds the tree state (saved with the game); this node owns the visuals and the
## life cycle: a woodcutter fells grown trees inside its area (a few trips each), the tree falls
## and leaves a stump, the stump sprouts again, and empty area cells slowly fill with saplings.
## Trees outside every area are scenery and are never cut.

signal changed(lodge_id: int)

@export var nav_path: NodePath = ^"../Nav"
@export var fields_path: NodePath = ^"../Fields"
@export var wear_path: NodePath = ^"../PathWear"

const BASE_H := 5.5                       # the baked trees are 5.5 m tall
const MODELS := {
	0: ["res://models/trees/broadleaf_0.glb", "res://models/trees/broadleaf_1.glb", "res://models/trees/broadleaf_2.glb"],
	1: ["res://models/trees/pine_0.glb", "res://models/trees/pine_1.glb"],
}
const STUMPS := {0: "res://models/trees/stump_broadleaf.glb", 1: "res://models/trees/stump_pine.glb"}
const FOLIAGE_SHADER := preload("res://scripts/world/foliage.gdshader")
const LEAF_TEX := {"leaves_broad": "res://models/trees/leaf_broad.png", "leaves_pine": "res://models/trees/leaf_pine.png"}

static var _mesh_cache := {}              # model path -> Mesh with the foliage shader on its leaf cards

## The tree model's mesh with its "leaves_*" surface switched to the foliage shader.
static func tree_mesh(path: String) -> Mesh:
	if _mesh_cache.has(path): return _mesh_cache[path]
	var src: Node = (load(path) as PackedScene).instantiate()
	var mesh: Mesh = _find_mesh_static(src)
	src.queue_free()
	if mesh == null: return null
	mesh = mesh.duplicate()
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var key := ""
		for k in LEAF_TEX:
			if m and m.resource_name.begins_with(k): key = k
		if key != "":
			var sm := ShaderMaterial.new()
			sm.shader = FOLIAGE_SHADER
			sm.set_shader_parameter("leaf_tex", load(LEAF_TEX[key]))
			mesh.surface_set_material(i, sm)
		elif m is StandardMaterial3D:
			(m as StandardMaterial3D).vertex_color_use_as_albedo = true
	_mesh_cache[path] = mesh
	return mesh

static func _find_mesh_static(n: Node) -> Mesh:
	if n is MeshInstance3D: return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh_static(c)
		if m: return m
	return null

## A gentle colour variation per tree (greener, yellower, darker).
static func tree_tint(id: int, kind: int) -> Color:
	var r := RandomNumberGenerator.new(); r.seed = id * 7919 + 13
	if kind == 1:
		return Color(r.randf_range(0.9, 1.05), r.randf_range(0.98, 1.1), r.randf_range(0.88, 1.0))
	var fresh := Color(0.88, 1.02, 0.72); var warm := Color(1.06, 0.98, 0.62); var deep := Color(0.74, 0.86, 0.66)
	var a := r.randf()
	return fresh.lerp(warm, a * 0.8) if r.randf() < 0.6 else fresh.lerp(deep, a)

var owner_map := PackedInt32Array()       # cell -> woodcutter id (0 = none)
var editing := -1                         # woodcutter whose area is being painted
var _nodes := {}                          # tree id -> Node3D (tree or stump)
var _next_id := 1
var _sprout_acc := {}                     # woodcutter id -> seconds since the last sapling check
var _mask_img: Image
var _mask_tex: ImageTexture
var _rng := RandomNumberGenerator.new()
var _ready_done := false
var _border: Array[MultiMeshInstance3D] = []   # the forest around the map (scenery, instanced)
var chops_done := 0                       # work sessions that gave wood (stats / tests)
var _hl_mat: StandardMaterial3D           # tint on trees inside the area being painted

func _ready() -> void:
	_rng.seed = 5150
	var w: int = Defs.ZONE["w"]
	owner_map.resize(w * w)
	_mask_img = Image.create(w, w, false, Image.FORMAT_L8)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	Game.building_added.connect(_on_added)
	Game.building_removed.connect(_on_removed)
	Game.reset.connect(_on_reset)
	call_deferred("_init_existing")

func _process(delta: float) -> void:
	var dt := delta * Game.speed
	if dt > 0.0: tick(dt)

func _nav() -> Node: return get_node_or_null(nav_path)

## (Re)builds everything from Game state: tree visuals, area ownership, ground overlay.
func _init_existing() -> void:
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("set_ground_param"):
		wear.set_ground_param("forest_tex", _mask_tex)
	for id in _nodes: _nodes[id].queue_free()
	_nodes.clear()
	if Game.trees.is_empty():
		_seed_from_map()
	_next_id = 1
	for t in Game.trees: _next_id = maxi(_next_id, int(t["id"]) + 1)
	var nav := _nav()
	for t in Game.trees:
		_make_visual(t)
		if nav and not t["wild"] and (t["growth"] >= 0.5 or t["stump"] > 0.0): nav.block_tree(t["pos"])
	_rebuild_owner_map()
	_ready_done = true
	if _border.is_empty(): _build_border()
	for b in Game.buildings:
		if b["type"] == "woodcutter" and area_of(b["id"]).is_empty():
			auto_area(b)               # saves from before forest areas
	_refresh_texture()
	set_editing(editing)

## The map's own trees (from world.json), all fully grown.
func _seed_from_map() -> void:
	Game.trees.clear()
	var nav := _nav()
	if nav == null: return
	var id := 1
	for row in nav.tree_data:
		var kind: int = int(row[3]) if row.size() > 3 else 0
		Game.trees.append({"id": id, "pos": Vector2(row[0], row[1]), "kind": kind,
			"var": id % MODELS[kind].size(), "h": float(row[4]) if row.size() > 4 else BASE_H,
			"r": float(row[2]), "growth": 1.0, "chops": Defs.FOREST["chops_per_tree"], "stump": 0.0, "wild": true})
		id += 1

# ---------------- grid helpers (same 0.5 m grid as zones and fields) ----------------

func _w() -> int: return Defs.ZONE["w"]

func cell_of(p: Vector2) -> int:
	var o: Vector2 = Defs.ZONE["origin"]; var c: float = Defs.ZONE["cell"]
	var x := floori((p.x - o.x) / c); var z := floori((p.y - o.y) / c)
	if x < 0 or z < 0 or x >= _w() or z >= _w(): return -1
	return z * _w() + x

func cell_center(i: int) -> Vector2:
	var o: Vector2 = Defs.ZONE["origin"]; var c: float = Defs.ZONE["cell"]
	return o + Vector2(i % _w() + 0.5, i / _w() + 0.5) * c

func area_of(id: int) -> Array:
	var b := Game.get_building(id)
	if b.is_empty(): return []
	if not b.has("area"): b["area"] = []
	return b["area"]

func is_area(p: Vector2) -> bool:
	var i := cell_of(p)
	return i >= 0 and owner_map[i] != 0

func area_owner_at(p: Vector2) -> int:
	var i := cell_of(p)
	return owner_map[i] if i >= 0 else 0

func tree_by_id(id: int) -> Dictionary:
	for t in Game.trees:
		if t["id"] == id: return t
	return {}

func is_grown(t: Dictionary) -> bool:
	return t["growth"] >= 1.0 and t["stump"] <= 0.0 and t["chops"] > 0

## {"ready", "growing", "stumps"} for the trees inside a woodcutter's area
func counts(id: int) -> Dictionary:
	var out := {"ready": 0, "growing": 0, "stumps": 0}
	for t in Game.trees:
		if area_owner_at(t["pos"]) != id: continue
		if t["stump"] > 0.0: out["stumps"] += 1
		elif t["growth"] < 1.0: out["growing"] += 1
		else: out["ready"] += 1
	return out

# ---------------- area rules ----------------

## Why a cell can't be part of this woodcutter's area ("" = it can). Trees and rocks are fine.
func cell_problem(lodge: Dictionary, i: int) -> String:
	if i < 0: return Loc.t("out of range")
	var p := cell_center(i)
	if not Defs.BUILD_BOUNDS.has_point(p): return Loc.t("out of range")
	if p.distance_to(lodge["pos"]) > Defs.FOREST["range"]: return Loc.t("too far from the lodge")
	if owner_map[i] != 0 and owner_map[i] != lodge["id"]: return Loc.t("another woodcutter's area")
	if Game.zones.size() > i and Game.zones[i] == 1: return Loc.t("housing zone")
	var fields := get_node_or_null(fields_path)
	if fields and fields.owner_map[i] != 0: return Loc.t("farm field")
	for b in Game.buildings:
		var l := Defs.to_local(b, p)
		var h := Defs.half_extents(b["type"]) + Vector2(0.1, 0.1)
		if absf(l.x) <= h.x and absf(l.y) <= h.y: return Loc.t("building")
	return ""

## Paint (on) or erase a disc of a woodcutter's area. Returns cells changed.
func paint(lodge_id: int, p: Vector2, on: bool, radius := -1.0) -> int:
	var lodge := Game.get_building(lodge_id)
	if lodge.is_empty(): return 0
	if radius < 0: radius = Defs.ZONE["brush_radius"]
	var cells: Array = area_of(lodge_id)
	var ci := cell_of(p)
	if ci < 0: return 0
	var steps := ceili(radius / Defs.ZONE["cell"])
	var cx := ci % _w(); var cz := ci / _w()
	var n := 0
	for dz in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			var x := cx + dx; var z := cz + dz
			if x < 0 or z < 0 or x >= _w() or z >= _w(): continue
			var i := z * _w() + x
			if cell_center(i).distance_to(p) > radius: continue
			if on:
				if owner_map[i] == lodge_id: continue
				if cells.size() >= Defs.FOREST["max_cells"]: break
				if cell_problem(lodge, i) != "": continue
				cells.append(i); owner_map[i] = lodge_id; n += 1
			elif owner_map[i] == lodge_id:
				cells.erase(i); owner_map[i] = 0; n += 1
	if n > 0: _area_changed(lodge_id)
	return n

## Erase a woodcutter's whole area (the trees stay).
func clear(lodge_id: int) -> int:
	var cells := area_of(lodge_id)
	var n := cells.size()
	for i in cells: owner_map[int(i)] = 0
	cells.clear()
	_area_changed(lodge_id)
	return n

## Starter area for a new lodge: a disc over the nearest trees, or in front of the lodge.
func auto_area(lodge: Dictionary) -> int:
	var near: Array = []
	for t in Game.trees:
		var d: float = (t["pos"] as Vector2).distance_to(lodge["pos"])
		if d <= Defs.FOREST["range"] - Defs.FOREST["auto_radius"] and area_owner_at(t["pos"]) == 0:
			near.append([d, t["pos"]])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var centre: Vector2
	if near.is_empty():
		centre = Defs.to_world(lodge, Vector2(0, 1.5 + Defs.FOREST["auto_radius"]))
	else:
		var sum := Vector2.ZERO; var k := mini(4, near.size())
		for j in k: sum += near[j][1]
		centre = sum / k
		# keep the disc clear of the lodge itself
		var away: Vector2 = centre - lodge["pos"]
		if away.length() < Defs.FOREST["auto_radius"] + 1.6:
			centre = lodge["pos"] + (away.normalized() if away.length() > 0.01 else Vector2(0, 1)) * (Defs.FOREST["auto_radius"] + 1.6)
	paint(lodge["id"], centre, true, Defs.FOREST["auto_radius"])
	return area_of(lodge["id"]).size()

## Highlight the area being edited.
func set_editing(lodge_id: int) -> void:
	editing = lodge_id
	_refresh_texture()
	_update_highlight()
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("set_ground_param"):
		wear.set_ground_param("forest_strength", 1.0 if lodge_id >= 0 else 0.35)

func _area_changed(lodge_id: int) -> void:
	_refresh_texture()
	_update_highlight()
	changed.emit(lodge_id)
	Game.changed.emit()

func _rebuild_owner_map() -> void:
	owner_map.fill(0)
	for b in Game.buildings:
		if b["type"] == "woodcutter" and b.has("area"):
			for i in b["area"]: owner_map[int(i)] = b["id"]

func _refresh_texture() -> void:
	var w := _w()
	var m := PackedByteArray(); m.resize(w * w)
	for i in owner_map.size():
		if owner_map[i] != 0:
			m[i] = 255 if (editing < 0 or owner_map[i] == editing) else 170
	_mask_img.set_data(w, w, false, Image.FORMAT_L8, m); _mask_tex.update(_mask_img)

# ---------------- felling (used by VillagerManager) ----------------

## The grown tree in this woodcutter's area closest to `from`, skipping `taken` tree ids. {} if none.
func pick_tree(lodge_id: int, from: Vector2, taken := {}) -> Dictionary:
	var best := {}; var best_d := INF
	for t in Game.trees:
		if not is_grown(t) or taken.has(t["id"]) or area_owner_at(t["pos"]) != lodge_id: continue
		var d := from.distance_squared_to(t["pos"])
		if d < best_d: best_d = d; best = t
	return best

## One work session on a tree: returns true if it gave wood. The last chop fells it.
func chop(tree_id: int, cutter_pos := Vector2.ZERO) -> bool:
	var t := tree_by_id(tree_id)
	if t.is_empty() or not is_grown(t): return false
	t["chops"] -= 1
	chops_done += 1
	if t["chops"] <= 0:
		_fell(t, (t["pos"] as Vector2) - cutter_pos)
	return true

func _fell(t: Dictionary, away: Vector2) -> void:
	t["stump"] = Defs.FOREST["stump_days"] * Defs.DAY_LENGTH
	t["growth"] = 0.0
	var old: Node3D = _nodes.get(t["id"])
	_nodes.erase(t["id"])
	if old and is_inside_tree():
		# the tree tips over away from the woodcutter, then sinks out of sight
		var dir := Vector3(away.x, 0, away.y)
		if dir.length() < 0.01: dir = Vector3(1, 0, 0)
		var axis := Vector3.UP.cross(dir.normalized()).normalized()
		var base := old.basis
		var tw := old.create_tween()
		tw.tween_method(func(a: float): old.basis = Basis(axis, a) * base, 0.0, 1.45, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(2.5)                    # the felled log lies there for a moment
		tw.tween_property(old, "position:y", old.position.y - 1.2, 1.5)
		tw.tween_callback(old.queue_free)
	elif old:
		old.queue_free()
	_make_visual(t)
	changed.emit(area_owner_at(t["pos"]))

# ---------------- growth ----------------

## Advances growth, stumps and sapling sprouting by dt game seconds (tests call this directly).
func tick(dt: float) -> void:
	if not _ready_done: return
	var nav := _nav()
	var rate: float = dt / (Defs.FOREST["grow_days"] * Defs.DAY_LENGTH)
	for t in Game.trees:
		if t["stump"] > 0.0:
			t["stump"] -= dt
			if t["stump"] <= 0.0:
				# the stump sprouts: a sapling at the same spot
				t["stump"] = 0.0; t["growth"] = 0.05; t["chops"] = Defs.FOREST["chops_per_tree"]
				_make_visual(t)
		elif t["growth"] < 1.0:
			var was: float = t["growth"]
			t["growth"] = minf(1.0, was + rate)
			if _nodes.has(t["id"]): _apply_scale(t, _nodes[t["id"]])
			if nav and not t["wild"] and was < 0.5 and t["growth"] >= 0.5: nav.block_tree(t["pos"])
			if was < 1.0 and t["growth"] >= 1.0: changed.emit(area_owner_at(t["pos"]))
	for b in Game.buildings:
		if b["type"] != "woodcutter": continue
		var acc: float = _sprout_acc.get(b["id"], 0.0) + dt
		while acc >= Defs.FOREST["sprout_check"]:
			acc -= Defs.FOREST["sprout_check"]
			_try_sprout(b)
		_sprout_acc[b["id"]] = acc

## A new sapling on a free spot of the area, if it has fewer trees than it can hold.
func _try_sprout(lodge: Dictionary) -> bool:
	var cells := area_of(lodge["id"])
	if cells.size() < Defs.FOREST["min_cells"]: return false
	var target := maxi(1, cells.size() / int(Defs.FOREST["cells_per_tree"]))
	var have := 0
	for t in Game.trees:
		if area_owner_at(t["pos"]) == lodge["id"]: have += 1
	if have >= target: return false
	for attempt in 16:
		var p := cell_center(cells[_rng.randi() % cells.size()]) + Vector2(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.2, 0.2))
		if can_grow_at(p):
			plant(p)
			return true
	return false

func can_grow_at(p: Vector2) -> bool:
	var nav := _nav()
	if nav:
		if nav.scenery_at(p): return false
		if not nav.is_walkable(nav.cell_of(Vector3(p.x, 0, p.y))): return false
	var wear := get_node_or_null(wear_path)
	if wear and wear.has_method("wear_at") and wear.wear_at(Vector3(p.x, 0, p.y)) > 0.2: return false     # not on a path
	for t in Game.trees:
		if (t["pos"] as Vector2).distance_to(p) < Defs.FOREST["spacing"]: return false
	for b in Game.buildings:
		var l := Defs.to_local(b, p)
		var h := Defs.half_extents(b["type"]) + Vector2(0.9, 0.9)
		if absf(l.x) <= h.x and absf(l.y) <= h.y: return false
	return true

## Adds a sapling (growth 0.05) at p. Returns the tree.
func plant(p: Vector2, growth := 0.05) -> Dictionary:
	var kind := 1 if _rng.randf() < 0.35 else 0
	var t := {"id": _next_id, "pos": p, "kind": kind, "var": _rng.randi() % MODELS[kind].size(),
		"h": _rng.randf_range(4.6, 6.4), "r": 0.2, "growth": growth, "chops": Defs.FOREST["chops_per_tree"],
		"stump": 0.0, "wild": false}
	_next_id += 1
	Game.trees.append(t)
	_make_visual(t)
	var nav := _nav()
	if nav and growth >= 0.5: nav.block_tree(p)
	changed.emit(area_owner_at(p))
	return t

# ---------------- visuals ----------------

func _make_visual(t: Dictionary) -> void:
	if _nodes.has(t["id"]):
		_nodes[t["id"]].queue_free(); _nodes.erase(t["id"])
	var path: String = STUMPS[t["kind"]] if t["stump"] > 0.0 else MODELS[t["kind"]][int(t["var"]) % MODELS[t["kind"]].size()]
	if not ResourceLoader.exists(path): return
	var n: Node3D
	if t["stump"] > 0.0:
		n = (load(path) as PackedScene).instantiate()
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = tree_mesh(path)
		mi.set_instance_shader_parameter("tint", tree_tint(int(t["id"]), int(t["kind"])))
		n = mi
	var nav := _nav()
	var p: Vector2 = t["pos"]
	n.position = Vector3(p.x, (nav.height_at(p.x, p.y) if nav else 0.0) - 0.04, p.y)
	n.rotation.y = fposmod(float(t["id"]) * 2.39996, TAU)
	_apply_scale(t, n)
	add_child(n)
	_nodes[t["id"]] = n
	if editing >= 0: _highlight_node(n, area_owner_at(p) == editing)

func _apply_scale(t: Dictionary, n: Node3D) -> void:
	var s: float = t["h"] / BASE_H
	if t["stump"] <= 0.0:
		s *= lerpf(0.12, 1.0, smoothstep(0.0, 1.0, t["growth"]))
	n.scale = Vector3(s, s, s)

## While an area is painted, trees inside it get a light green tint (the canopy hides the ground outline).
func _update_highlight() -> void:
	for t in Game.trees:
		if _nodes.has(t["id"]):
			_highlight_node(_nodes[t["id"]], editing >= 0 and area_owner_at(t["pos"]) == editing)

func _highlight_node(n: Node, on: bool) -> void:
	if _hl_mat == null:
		_hl_mat = StandardMaterial3D.new()
		_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hl_mat.albedo_color = Color(0.6, 1.0, 0.45, 0.38)
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = _hl_mat if on else null
	for c in n.get_children():
		_highlight_node(c, on)

func tree_count() -> int:
	return Game.trees.size()

## The border forest outside the playable map: the same tree models, one instanced batch per model.
func _build_border() -> void:
	var nav := _nav()
	if nav == null or nav.border_data.is_empty(): return
	var groups := {}                       # model path -> Array[Transform3D]
	var rng := RandomNumberGenerator.new(); rng.seed = 4711
	for i in nav.border_data.size():
		var r: Array = nav.border_data[i]
		var kind: int = int(r[2])
		var path: String = MODELS[kind][i % MODELS[kind].size()]
		var s: float = float(r[3]) / BASE_H
		var y: float = float(r[4]) if r.size() > 4 else 0.0
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(r[0], y - 0.1, r[1]))
		if not groups.has(path): groups[path] = []
		groups[path].append(xf)
	for path in groups:
		if not ResourceLoader.exists(path): continue
		var mesh := tree_mesh(path)
		if mesh == null: continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		var list: Array = groups[path]
		mm.instance_count = list.size()
		var pine: bool = (path as String).contains("pine")
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, tree_tint(i * 31 + path.length(), 1 if pine else 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Border_" + path.get_file().get_basename()
		mmi.multimesh = mm
		add_child(mmi)
		_border.append(mmi)

func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D: return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m: return m
	return null

func border_count() -> int:
	var n := 0
	for m in _border: n += m.multimesh.instance_count
	return n

# ---------------- events ----------------

func _on_added(b: Dictionary) -> void:
	if b["type"] == "woodcutter":
		if b.has("area") and not (b["area"] as Array).is_empty():
			for i in b["area"]: owner_map[int(i)] = b["id"]
			_refresh_texture()
		elif _ready_done:
			auto_area(b)
	else:
		# a new building takes over any area cells under it
		var touched := {}
		for i in owner_map.size():
			if owner_map[i] == 0: continue
			var l := Defs.to_local(b, cell_center(i))
			var h := Defs.half_extents(b["type"])
			if absf(l.x) <= h.x and absf(l.y) <= h.y:
				var lid := owner_map[i]
				area_of(lid).erase(i); owner_map[i] = 0; touched[lid] = true
		if not touched.is_empty(): _refresh_texture()

func _on_removed(b: Dictionary) -> void:
	if b["type"] != "woodcutter": return
	for i in owner_map.size():
		if owner_map[i] == b["id"]: owner_map[i] = 0
	_sprout_acc.erase(b["id"])
	if editing == b["id"]: editing = -1
	_refresh_texture()

func _on_reset() -> void:
	owner_map.fill(0)
	_sprout_acc.clear()
	Game.trees.clear()
	_init_existing()
