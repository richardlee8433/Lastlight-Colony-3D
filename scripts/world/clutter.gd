class_name Clutter
extends Node3D
## Lived-in props around finished buildings: gardens, fences, laundry, firewood, flower boxes,
## crates, barrels, hay... Each building type has a set of candidate spots (building-local, front = +Z);
## a deterministic dice roll per building picks which appear. Spots on paths, doorsteps, fields,
## scenery or other buildings are skipped. Larger props block walking.

@export var nav_path: NodePath = ^"../Nav"
@export var wear_path: NodePath = ^"../PathWear"
@export var fields_path: NodePath = ^"../Fields"
@export var forest_path: NodePath = ^"../Forest"
@export var scatter_path: NodePath = ^"../Scatter"

const DIR := "res://models/props/%s.glb"
## [prop, side, along, out, angle (deg), chance, block half-size (Vector2.ZERO = walk-through)]
## side: "front" / "back" / "left" / "right"; along: position along that side (-1..1 of the half size);
## out: metres beyond the footprint edge (negative = against the wall)
const SETS := {
	"house": [
		["garden", "back", -0.4, 0.75, 0, 0.7, Vector2(0.9, 0.55)],
		["fence", "back", 0.5, 1.9, 0, 0.6, Vector2(1.05, 0.12)],
		["fence", "back", -0.5, 1.9, 0, 0.5, Vector2(1.05, 0.12)],
		["laundry", "left", -0.1, 1.1, 90, 0.45, Vector2(1.25, 0.15)],
		["firewood", "right", -0.3, 0.3, 90, 0.7, Vector2(0.7, 0.3)],
		["flowerbox", "front", -0.55, 0.15, 0, 0.75, Vector2.ZERO],
		["bench", "front", 0.6, 0.4, 0, 0.5, Vector2.ZERO],
		["barrel", "left", 0.75, 0.35, 0, 0.4, Vector2(0.3, 0.3)],
		["bucket", "front", 0.35, 0.35, 0, 0.3, Vector2.ZERO],
	],
	"storehouse": [
		["crates", "right", 0.4, 0.55, 90, 0.9, Vector2(0.6, 0.4)],
		["barrels", "left", 0.4, 0.5, 90, 0.8, Vector2(0.6, 0.35)],
		["sacks", "front", 0.75, 0.3, 0, 0.7, Vector2.ZERO],
		["wheelbarrow", "front", -0.8, 0.6, 20, 0.6, Vector2.ZERO],
		["crate", "back", 0.3, 0.4, 15, 0.5, Vector2(0.3, 0.3)],
	],
	"farm": [
		["haybales", "left", 0.0, 0.6, 90, 0.85, Vector2(0.7, 0.45)],
		["wheelbarrow", "right", 0.4, 0.6, -60, 0.6, Vector2.ZERO],
		["sacks", "back", 0.3, 0.4, 0, 0.5, Vector2.ZERO],
		["fence", "back", -0.4, 1.3, 0, 0.4, Vector2(1.05, 0.12)],
	],
	"woodcutter": [
		["firewood", "left", 0.0, 0.5, 90, 0.8, Vector2(0.7, 0.3)],
		["crate", "right", 0.5, 0.5, 20, 0.5, Vector2(0.3, 0.3)],
		["wheelbarrow", "front", 0.7, 0.6, -20, 0.4, Vector2.ZERO],
	],
	"quarry": [
		["bucket", "front", -0.3, 0.2, 0, 0.6, Vector2.ZERO],
		["barrel", "left", 0.6, 0.2, 0, 0.5, Vector2(0.3, 0.3)],
	],
}

var _props := {}          # building id -> Array of {"node", "key" (nav block key or null), "pos"}
var _scenes := {}

func _ready() -> void:
	Game.building_added.connect(_on_added)
	Game.building_completed.connect(func(b): _dress.call_deferred(b))
	Game.building_removed.connect(_on_removed)
	Game.reset.connect(_on_reset)
	call_deferred("_init_existing")

func _init_existing() -> void:
	for b in Game.buildings:
		if Game.is_built(b): _dress(b)

func _on_added(b: Dictionary) -> void:
	# a new building (or site) clears props in its way
	var h := Defs.half_extents(b["type"]) + Vector2(0.4, 0.4)
	for id in _props.keys():
		if id == b["id"]: continue
		for p in (_props[id] as Array).duplicate():
			var l := Defs.to_local(b, p["pos"])
			if absf(l.x) <= h.x + p["r"] and absf(l.y) <= h.y + p["r"]:
				_remove_prop(p); (_props[id] as Array).erase(p)
	if Game.is_built(b): _dress.call_deferred(b)     # finished right away (instant build, loading)

func _on_removed(b: Dictionary) -> void:
	for p in _props.get(b["id"], []): _remove_prop(p)
	_props.erase(b["id"])

func _on_reset() -> void:
	for id in _props:
		for p in _props[id]: _remove_prop(p)
	_props.clear()

func _remove_prop(p: Dictionary) -> void:
	if is_instance_valid(p["node"]): p["node"].queue_free()
	var nav := get_node_or_null(nav_path)
	if nav and p["key"] != null: nav.unblock_building({"id": p["key"]})
	var sc := get_node_or_null(scatter_path)
	if sc and sc.has_method("restore_area") and p.has("grass"): sc.restore_area(p["grass"][0], p["grass"][1], p["grass"][2])

func prop_count(id := -1) -> int:
	if id >= 0: return (_props.get(id, []) as Array).size()
	var n := 0
	for k in _props: n += (_props[k] as Array).size()
	return n

## Places the props of one finished building.
func _dress(b: Dictionary) -> void:
	if b.is_empty() or not Game.get_building(b["id"]) or _props.has(b["id"]): return
	var set: Array = SETS.get(b["type"], [])
	if set.is_empty(): return
	var rng := RandomNumberGenerator.new(); rng.seed = int(b["id"]) * 2654435 + 17
	var h := Defs.half_extents(b["type"])
	var list: Array = []
	_props[b["id"]] = list
	for e in set:
		if rng.randf() > float(e[5]): continue
		var local := _spot(e[1], float(e[2]), float(e[3]), h)
		var angle: float = b["angle"] + deg_to_rad(float(e[4])) + rng.randf_range(-0.12, 0.12)
		var pos := Defs.to_world(b, local)
		var half: Vector2 = e[6]
		var r := maxf(0.35, half.length())
		if not _free(pos, r, b, list): continue
		var node := _make(e[0])
		if node == null: continue
		var nav := get_node_or_null(nav_path)
		node.position = Vector3(pos.x, nav.height_at(pos.x, pos.y) if nav else 0.0, pos.y)
		node.rotation.y = angle
		add_child(node)
		var grass := Vector2(maxf(half.x, 0.3), maxf(half.y, 0.3)) + Vector2(0.1, 0.1)
		var sc := get_node_or_null(scatter_path)
		if sc and sc.has_method("clear_area"): sc.clear_area(pos, grass, angle)       # props sit on short ground
		var key = null
		if half != Vector2.ZERO and nav:
			key = "prop_%d_%d" % [b["id"], list.size()]
			nav.block_rect(key, pos, Vector2(maxf(half.x, 0.26), maxf(half.y, 0.26)), angle)     # at least one walk cell thick
		list.append({"node": node, "key": key, "pos": pos, "r": r, "name": e[0], "grass": [pos, grass, angle]})

func _spot(side: String, along: float, out: float, h: Vector2) -> Vector2:
	match side:
		"front": return Vector2(along * h.x, h.y + out)
		"back": return Vector2(along * h.x, -h.y - out)
		"left": return Vector2(-h.x - out, along * h.y)
		_: return Vector2(h.x + out, along * h.y)

func _free(pos: Vector2, r: float, owner: Dictionary, placed: Array) -> bool:
	if not Defs.BUILD_BOUNDS.has_point(pos): return false
	var nav := get_node_or_null(nav_path)
	var wear := get_node_or_null(wear_path)
	var fields := get_node_or_null(fields_path)
	var forest := get_node_or_null(forest_path)
	for d in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var q: Vector2 = pos + d * 0.5
		if nav and (nav.scenery_at(q) or not nav.is_walkable(nav.cell_of(Vector3(q.x, 0, q.y)))): return false
		if wear and d == Vector2.ZERO and wear.wear_at(Vector3(q.x, 0, q.y)) > 0.3: return false   # not on a path
		if fields and fields.is_field(q): return false
		if forest and forest.is_area(q): return false
	for b in Game.buildings:
		var l := Defs.to_local(b, pos)
		# its own building: only the body itself; others: keep some room
		var grow := 0.05 if b["id"] == owner["id"] else r * 0.6
		var h := Defs.half_extents(b["type"]) + Vector2(grow, grow)
		if absf(l.x) <= h.x and absf(l.y) <= h.y: return false
		# not in front of anyone's door / drop point
		var d: Dictionary = Defs.BUILDINGS[b["type"]]
		var entry: Vector2 = d.get("door", d.get("drop", d.get("work_spot", Vector2(9999, 9999))))
		if entry.x < 9000:
			# keep the strip straight out of the door clear (own door: just the strip itself)
			var lp := Defs.to_local(b, pos) - entry
			var margin := 0.45 if b["id"] == owner["id"] else r + 0.5
			if lp.y > -0.2 and lp.y < 2.2 and absf(lp.x) < margin: return false
	for id in _props:
		for p in _props[id]:
			if (p["pos"] as Vector2).distance_to(pos) < r + p["r"]: return false
	for p in placed:
		if (p["pos"] as Vector2).distance_to(pos) < r + p["r"]: return false
	for t in Game.trees:
		if (t["pos"] as Vector2).distance_to(pos) < r + 0.5: return false
	return true

func _make(name: String) -> Node3D:
	var path: String = DIR % name
	if not ResourceLoader.exists(path): return null
	if not _scenes.has(path): _scenes[path] = load(path)
	var n: Node3D = (_scenes[path] as PackedScene).instantiate()
	DayNight.dress(n)
	return n
