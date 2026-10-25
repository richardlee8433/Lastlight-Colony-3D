class_name VillagerManager
extends Node3D
## Keeps one Villager per person in Game.population, gives them homes and jobs,
## and answers "where do I work / drop goods" questions for them.

@export var nav_path: NodePath = ^"../Nav"
@export var wear_path: NodePath = ^"../PathWear"
@export var fields_path: NodePath = ^"../Fields"
@export var forest_path: NodePath = ^"../Forest"

var villagers: Array[Villager] = []
var leaving: Array[Villager] = []
var _next_id := 1
var _started := false
var _rng := RandomNumberGenerator.new()

@onready var nav: NavGrid = get_node(nav_path)
@onready var wear: PathWear = get_node_or_null(wear_path)
@onready var fields: Node = get_node_or_null(fields_path)
@onready var forest: Node = get_node_or_null(forest_path)
var _chop := {}                  # villager id -> tree id being felled
var _was_site := {}              # villager id -> whether their job was a construction site when assigned
const BUILDER_JOB := {"anim": "chop", "tool": "Axe", "carry": "", "hat": "HatCap", "target": "site"}

func _ready() -> void:
	_rng.seed = 4242
	Game.changed.connect(_sync)
	Game.reset.connect(_on_reset)
	nav.changed.connect(_on_nav_changed)
	call_deferred("_first_sync")

func _first_sync() -> void:
	_started = Game.fresh_start          # a new game: the settlers walk in with the cart
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
	if arriving or Game.fresh_start:
		var sp: Vector2 = Defs.SPAWN_POINTS[_rng.randi() % Defs.SPAWN_POINTS.size()]
		if Game.fresh_start:
			# the first settlers walk in together, a step apart
			sp = Defs.SPAWN_POINTS[0] + Vector2(_rng.randf_range(-0.8, 0.8), villagers.size() * 0.9)
		v.arrive_from(sp)
	else:
		var p := Game.center() + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(1.0, 3.5))
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
	for b in Game.buildings:
		var d: Dictionary = Defs.BUILDINGS[b["type"]]
		if d.has("housing") and Game.is_built(b):
			var door := Defs.to_world(b, d.get("door", Vector2.ZERO))
			for i in int(d["housing"]): out.append(door)
	return out

func _assign_homes() -> void:
	var beds := homes()
	for i in villagers.size():
		villagers[i].home = beds[i] if i < beds.size() else Game.center()

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
				# the site this builder worked on is finished: same building, new job (outfit, target)
				var site_now := not Game.is_built(Game.get_building(v.job_id))
				if _was_site.get(v.vid, site_now) != site_now:
					_was_site[v.vid] = site_now
					v.assign_job(v.job_id)
			else:
				v.clear_job()
				_chop.erase(v.vid)
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
			_was_site[best.vid] = not Game.is_built(Game.get_building(id))
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
	if not Game.is_built(b): return BUILDER_JOB
	return Defs.BUILDINGS[b["type"]].get("job", {})

func building_center(id: int) -> Vector2:
	var b := Game.get_building(id)
	return Vector2.ZERO if b.is_empty() else Defs.building_center(b)

## goods produced by one work session of this villager's job
func yield_of(v: Villager) -> Dictionary:
	var b := Game.get_building(v.job_id)
	if b.is_empty(): return {}
	if not Game.is_built(b):
		# a builder's work session: progress on the site, nothing to carry
		Game.add_build_progress(b["id"], float(Defs.VILLAGER["work_time"]) / float(Defs.BUILDINGS[b["type"]].get("build_time", 10.0)))
		return {}
	if b["type"] == "farm" and fields:
		# food only from a ripe field; while the wheat grows the farmer tends it
		var n: int = fields.harvest(b["id"])
		return {"food": n} if n > 0 else {}
	if b["type"] == "woodcutter" and forest:
		# wood only if the tree this villager worked on was still standing
		var tid: int = _chop.get(v.vid, -1)
		_chop.erase(v.vid)
		if tid < 0 or not forest.chop(tid, Vector2(v.position.x, v.position.z)): return {}
	return Defs.BUILDINGS[b["type"]].get("yield", {}).duplicate()

## every place goods can be delivered: the starting cottage + storehouses
func storages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in Game.buildings:
		var d: Dictionary = Defs.BUILDINGS[b["type"]]
		if d.get("storage", false) and Game.is_built(b):
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
	var job: Dictionary = job_of(v)
	var c := Defs.building_center(b)
	match job.get("target", "spot"):
		"site":
			# somewhere just outside the footprint, facing the middle
			var h := Defs.half_extents(b["type"])
			var side := _rng.randi() % 4
			var t := _rng.randf_range(-0.7, 0.7)
			var local: Vector2 = [Vector2(t * h.x, h.y + 0.45), Vector2(t * h.x, -h.y - 0.45), Vector2(h.x + 0.45, t * h.y), Vector2(-h.x - 0.45, t * h.y)][side]
			var p := nav.walkable_point(Defs.to_world(b, local))
			return {"pos": nav.on_ground(p), "look": nav.on_ground(b["pos"])}
		"tree":
			# the closest grown tree in the lodge's forest area, approached from the lodge side
			if forest == null: return {}
			var taken := {}
			for vid in _chop:
				if vid != v.vid: taken[_chop[vid]] = true
			var t: Dictionary = forest.pick_tree(b["id"], Vector2(v.position.x, v.position.z), taken)
			if t.is_empty():
				_chop.erase(v.vid)
				return {}
			_chop[v.vid] = t["id"]
			var tp: Vector2 = t["pos"]
			var dir := (c - tp).normalized()
			var stand := nav.walkable_point(tp + dir * (float(t["r"]) * t["h"] / 5.5 + 0.45))
			return {"pos": nav.on_ground(stand), "look": nav.on_ground(tp)}
		"field":
			# a random spot in the painted field (no field -> nothing to do)
			if fields == null or fields.yield_for(b["id"]) <= 0: return {}
			var spot: Dictionary = fields.work_spot(b["id"], _rng)
			if spot.is_empty(): return {}
			return {"pos": nav.on_ground(nav.walkable_point(spot["pos"])), "look": nav.on_ground(spot["look"])}
		_:
			var p := nav.walkable_point(Defs.to_world(b, d.get("work_spot", Vector2.ZERO)))
			return {"pos": nav.on_ground(p), "look": nav.on_ground(Defs.to_world(b, d.get("work_look", Vector2.ZERO)))}

func count_working() -> int:
	var n := 0
	for v in villagers:
		if v.state == Villager.S.WORK: n += 1
	return n
