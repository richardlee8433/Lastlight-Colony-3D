class_name VillagerManager
extends Node3D
## Keeps one Villager per person in Game.population, gives them homes and jobs,
## and answers "where do I work / drop goods" questions for them.

@export var nav_path: NodePath = ^"../Nav"
@export var wear_path: NodePath = ^"../PathWear"

var villagers: Array[Villager] = []
var leaving: Array[Villager] = []
var _next_id := 1
var _started := false
var _rng := RandomNumberGenerator.new()
var _field_rows := {}            # building id -> next row index (farmers walk the rows)

@onready var nav: NavGrid = get_node(nav_path)
@onready var wear: PathWear = get_node_or_null(wear_path)

func _ready() -> void:
	_rng.seed = 4242
	Game.changed.connect(_sync)
	Game.reset.connect(_on_reset)
	nav.changed.connect(_on_nav_changed)
	call_deferred("_first_sync")

func _first_sync() -> void:
	_started = false
	_sync()
	_started = true

func _process(delta: float) -> void:
	var dt := delta * Game.speed
	if dt > 0.0:
		tick(dt)

## Advances every villager by dt game seconds (tests call this directly).
func tick(dt: float) -> void:
	for v in villagers: v.tick(dt)
	for v in leaving.duplicate(): v.tick(dt)

# ---------------- population / homes / jobs ----------------

func _sync() -> void:
	var target := Game.population
	while villagers.size() < target:
		_spawn(_started)
	while villagers.size() > target:
		_send_away(_pick_to_remove())
	_assign_homes()
	_assign_jobs()

func _spawn(arriving: bool) -> void:
	var v := Villager.new()
	v.name = "Villager%d" % _next_id
	add_child(v)
	v.setup(_next_id, self, nav, wear)
	_next_id += 1
	villagers.append(v)
	if arriving:
		var sp: Vector2 = Defs.SPAWN_POINTS[_rng.randi() % Defs.SPAWN_POINTS.size()]
		v.arrive_from(sp)
	else:
		var p := Defs.STORAGE_POINT + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-0.5, 3.0))
		v.place_at(p)
		v.clear_job()

func _pick_to_remove() -> Villager:
	for v in villagers:
		if v.job_id < 0: return v
	return villagers[-1]

func _send_away(v: Villager) -> void:
	villagers.erase(v)
	leaving.append(v)
	var exit: Vector2 = Defs.SPAWN_POINTS[0]
	v.leave(exit)

func villager_left(v: Villager) -> void:
	leaving.erase(v)
	v.queue_free()

func homes() -> Array[Vector2]:
	## one entry per bed: the starter cottage, then every house
	var out: Array[Vector2] = []
	for i in Defs.STARTER_HOUSING: out.append(Defs.STORAGE_POINT)
	for b in Game.buildings:
		var d: Dictionary = Defs.BUILDINGS[b["type"]]
		if d.has("housing"):
			var door := Defs.to_world(b, d.get("door", Vector2.ZERO))
			for i in int(d["housing"]): out.append(door)
	return out

func _assign_homes() -> void:
	var beds := homes()
	for i in villagers.size():
		villagers[i].home = beds[i] if i < beds.size() else Defs.STORAGE_POINT

func _assign_jobs() -> void:
	# open positions = staffed producer buildings (Game decides how many are staffed)
	var open := {}
	for b in Game.buildings:
		if Game.is_active(b):          # staffed, and when starving only food jobs keep going
			open[b["id"]] = true
	# release villagers whose job disappeared
	var taken := {}
	for v in villagers:
		if v.job_id >= 0:
			if open.has(v.job_id) and not taken.has(v.job_id):
				taken[v.job_id] = true
			else:
				v.clear_job()
	# fill open jobs with the nearest unemployed villager
	for id in open:
		if taken.has(id): continue
		var c := building_center(id)
		var best: Villager = null; var best_d := INF
		for v in villagers:
			if v.job_id >= 0 or v.state == Villager.S.ARRIVE: continue
			var d := Vector2(v.position.x, v.position.z).distance_to(c)
			if d < best_d: best_d = d; best = v
		if best == null:
			for v in villagers:
				if v.job_id < 0: best = v; break
		if best:
			best.job_id = id      # set before assign_job so job_of() works
			best.assign_job(id)
			taken[id] = true

func _on_reset() -> void:
	for v in villagers + leaving: v.queue_free()
	villagers.clear(); leaving.clear()
	_started = false
	call_deferred("_first_sync")

func _on_nav_changed() -> void:
	for v in villagers + leaving: v.repath()

# ---------------- queries used by villagers ----------------

func job_of(v: Villager) -> Dictionary:
	if v.job_id < 0: return {}
	var b := Game.get_building(v.job_id)
	if b.is_empty(): return {}
	return Defs.BUILDINGS[b["type"]].get("job", {})

func building_center(id: int) -> Vector2:
	var b := Game.get_building(id)
	return Vector2.ZERO if b.is_empty() else Defs.building_center(b)

## goods produced by one work session of this villager's job
func yield_of(v: Villager) -> Dictionary:
	var b := Game.get_building(v.job_id)
	if b.is_empty(): return {}
	return Defs.BUILDINGS[b["type"]].get("yield", {}).duplicate()

## every place goods can be delivered: the starting cottage + storehouses
func storages() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"drop": Defs.STORAGE_POINT, "look": Defs.STORAGE_LOOK}]
	for b in Game.buildings:
		var d: Dictionary = Defs.BUILDINGS[b["type"]]
		if d.get("storage", false):
			out.append({"drop": Defs.to_world(b, d["drop"]), "look": b["pos"]})
	return out

## closest storage by walking distance (falls back to straight-line distance)
func nearest_storage(from: Vector2) -> Dictionary:
	var best := {}; var best_d := INF
	for s in storages():
		var p := nav.find_path(nav.on_ground(from), nav.on_ground(s["drop"]))
		var d := 0.0
		if p.size() >= 2:
			for i in range(1, p.size()): d += p[i - 1].distance_to(p[i])
		else:
			d = from.distance_to(s["drop"]) * 3.0
		if d < best_d: best_d = d; best = s
	return best

## {"pos": Vector3, "look": Vector3} for the villager's next work spot, or {} if none.
func work_target(v: Villager) -> Dictionary:
	var b := Game.get_building(v.job_id)
	if b.is_empty(): return {}
	var d: Dictionary = Defs.BUILDINGS[b["type"]]
	var job: Dictionary = d.get("job", {})
	var c := Defs.building_center(b)
	match job.get("target", "spot"):
		"tree":
			# one of the three closest trees, approached from the lodge side
			var trees := nav.trees.duplicate()
			trees.sort_custom(func(a, bb): return Vector2(a.x, a.z).distance_squared_to(c) < Vector2(bb.x, bb.z).distance_squared_to(c))
			if trees.is_empty(): return {}
			var t: Vector3 = trees[_rng.randi() % mini(3, trees.size())]
			var tp := Vector2(t.x, t.z)
			var dir := (c - tp).normalized()
			var stand := nav.walkable_point(tp + dir * (t.y + 0.45))
			return {"pos": nav.on_ground(stand), "look": nav.on_ground(tp)}
		"field":
			var row: int = _field_rows.get(b["id"], 0)
			_field_rows[b["id"]] = (row + 1) % 5
			var local := Vector2(_rng.randf_range(-1.3, 1.3), -1.2 + row * 0.6)
			var p := Defs.to_world(b, local)
			var look := Defs.to_world(b, local + Vector2(0.6, 0.0))
			return {"pos": nav.on_ground(nav.walkable_point(p)), "look": nav.on_ground(look)}
		_:
			var p := nav.walkable_point(Defs.to_world(b, d.get("work_spot", Vector2.ZERO)))
			return {"pos": nav.on_ground(p), "look": nav.on_ground(Defs.to_world(b, d.get("work_look", Vector2.ZERO)))}

func count_working() -> int:
	var n := 0
	for v in villagers:
		if v.state == Villager.S.WORK: n += 1
	return n
