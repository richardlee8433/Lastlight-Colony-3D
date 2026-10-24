extends Node
## Autoload "Game": the simulation state (resources, people, buildings, quests, saving).
## Goods are produced by villagers and only count once they are carried into a storage
## (see Villager / VillagerManager, which call deliver()).

signal changed                                   # any resource / population / building change
signal delivered(res: String, amount: int, at: Vector2)
signal building_added(b: Dictionary)
signal building_removed(b: Dictionary)
signal toast(text: String)
signal quest_changed
signal day_passed(day: int)
signal reset                                     # new game started (paths, villagers clear)
signal zones_changed
signal language_changed
signal building_completed(b: Dictionary)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2

var resources := {}
var population := 0
var day := 1
var speed := 1.0                 # 0 = paused
## building: {"id", "type", "pos": Vector2 (world x,z centre), "angle": float (radians), "staffed"}
var buildings: Array[Dictionary] = []
var quest_index := 0
var starving := false
## residential zone mask (Defs.ZONE grid), 1 = zoned
var zones := PackedByteArray()
## every tree inside the map (Forest owns the visuals): {"id", "pos": Vector2, "kind", "var", "h", "r",
## "growth" 0..1, "chops" left, "stump" seconds left (0 = not a stump), "wild" (one of the map's own trees)}
var trees: Array[Dictionary] = []
## fish stock per water body ("0" = the pond, "1".. = stretches of the stream), 0..1; missing = full
var fish := {}

var _next_id := 1
var fresh_start := false         # true right after new_game (settlers walk in)
var instant_build := false       # tests: buildings are finished the moment they are placed
var _day_timer := 0.0
var _autosave := true
var _today := {}                 # goods delivered today
var _yesterday := {}             # goods delivered during the previous full day

func _ready() -> void:
	Loc.load_settings()
	_clear_zones()
	if not load_game():
		new_game()

func new_game() -> void:
	resources = Defs.START["resources"].duplicate()
	population = Defs.START["population"]
	day = 1
	quest_index = 0
	starving = false
	_day_timer = 0.0
	_today = {}; _yesterday = {}
	_clear_zones()
	trees.clear()
	for b in buildings.duplicate():
		buildings.erase(b)
		building_removed.emit(b)
	_next_id = 1
	fresh_start = true
	reset.emit()                     # listeners clear paths / villagers / nav blocks first
	add_building("cart", Defs.CART_SPOT, Defs.CART_ANGLE, false)
	_assign_workers()
	changed.emit(); quest_changed.emit()

# ---------------- zones ----------------

func _clear_zones() -> void:
	zones = PackedByteArray()
	zones.resize(Defs.ZONE["w"] * Defs.ZONE["w"])
	zones_changed.emit()

func zone_count() -> int:
	var n := 0
	for v in zones: n += v
	return n

func set_zone(index: int, on: bool) -> void:
	if index >= 0 and index < zones.size():
		zones[index] = 1 if on else 0

# ---------------- queries ----------------

## Beds in finished buildings (planned = also count houses still under construction).
func housing(planned := false) -> int:
	var h: int = Defs.START["housing"]
	for b in buildings:
		if planned or is_built(b):
			h += int(Defs.BUILDINGS[b["type"]].get("housing", 0))
	return h

## A placed building stays a construction site until its "build" progress reaches 1.
func is_built(b: Dictionary) -> bool:
	return float(b.get("build", 1.0)) >= 1.0

func build_progress(b: Dictionary) -> float:
	return clampf(float(b.get("build", 1.0)), 0.0, 1.0)

## 0 = foundation, 1 = timber frame, 2 = finished
func build_stage(b: Dictionary) -> int:
	if is_built(b): return 2
	return 1 if build_progress(b) >= Defs.CONSTRUCTION["stage2"] else 0

## jobs: one builder per construction site, plus the workers of finished workplaces
func _jobs_of(b: Dictionary) -> int:
	if not is_built(b): return 1
	return int(Defs.BUILDINGS[b["type"]].get("workers", 0))

func workers_needed() -> int:
	var n := 0
	for b in buildings: n += _jobs_of(b)
	return n

func workers_used() -> int:
	var n := 0
	for b in buildings:
		if b["staffed"]: n += _jobs_of(b)
	return n

func sites() -> int:
	var n := 0
	for b in buildings:
		if not is_built(b): n += 1
	return n

## finished buildings of a type (construction sites don't count)
func count_of(type: String) -> int:
	var n := 0
	for b in buildings:
		if b["type"] == type and is_built(b): n += 1
	return n

func can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if int(resources.get(r, 0)) < int(cost[r]): return false
	return true

## the village centre: where the supply cart stands
func center() -> Vector2:
	for b in buildings:
		if b["type"] == "cart": return b["pos"]
	return Defs.CART_SPOT

func get_building(id: int) -> Dictionary:
	for b in buildings:
		if b["id"] == id: return b
	return {}

## Goods carried into storage during the last full day.
func income_per_day(res: String) -> int:
	return int(_yesterday.get(res, 0))

## Net food per day: yesterday's deliveries minus what the village eats.
func food_per_day() -> float:
	return income_per_day("food") - population * Defs.FOOD_PER_VILLAGER

# ---------------- actions ----------------

## Adds a building at a world position (x, z) with any rotation. Returns the record, or {} if unaffordable.
## The caller (BuildController) is responsible for checking the spot is free.
func add_building(type: String, pos: Vector2, angle := 0.0, pay := true) -> Dictionary:
	var d: Dictionary = Defs.BUILDINGS[type]
	if pay:
		if not can_afford(d["cost"]):
			toast.emit(Loc.t("Not enough resources: need ") + Defs.cost_text(d["cost"]))
			return {}
		for r in d["cost"]:
			resources[r] -= int(d["cost"][r])
	var b := {"id": _next_id, "type": type, "pos": pos, "angle": angle, "staffed": false}
	if pay and not instant_build and d.has("build_time"):
		b["build"] = 0.0                 # a construction site: builders finish it
	_next_id += 1
	buildings.append(b)
	_assign_workers()
	building_added.emit(b)
	changed.emit()
	_check_quest()
	return b

## Removes a building and refunds half its cost.
func demolish(id: int) -> void:
	var b := get_building(id)
	if b.is_empty(): return
	var d: Dictionary = Defs.BUILDINGS[b["type"]]
	if d.get("permanent", false):
		toast.emit(Loc.t("%s can't be demolished") % Loc.t(d["name"]))
		return
	var site := not is_built(b)
	for r in d["cost"]:
		# a construction site that is cancelled gives everything back
		resources[r] += int(d["cost"][r]) if site else int(d["cost"][r] / 2.0)
	buildings.erase(b)
	population = min(population, housing())
	_assign_workers()
	building_removed.emit(b)
	if site: toast.emit(Loc.t("Construction of %s cancelled, materials returned") % Loc.t(d["name"]))
	else: toast.emit(Loc.t("%s demolished, half the cost refunded") % Loc.t(d["name"]))
	changed.emit()

## A villager carried goods into a storage at world point `at`.
func deliver(res: String, amount: int, at := Vector2.ZERO) -> void:
	if amount <= 0 or not resources.has(res): return
	resources[res] += amount
	_today[res] = int(_today.get(res, 0)) + amount
	delivered.emit(res, amount, at)
	changed.emit()
	_check_quest()

## Switch the UI language ("en" / "zh"); remembered in user://settings.cfg.
func set_language(l: String) -> void:
	if not Loc.LANGS.has(l) or l == Loc.lang: return
	Loc.lang = l
	Loc.save_settings()
	language_changed.emit()
	changed.emit(); quest_changed.emit()

## A builder finished a work session on a site (fraction = work time / build time).
func add_build_progress(id: int, fraction: float) -> void:
	var b := get_building(id)
	if b.is_empty() or is_built(b): return
	b["build"] = minf(1.0, float(b["build"]) + fraction)
	if b["build"] >= 1.0:
		b.erase("build")
		_assign_workers()
		toast.emit(Loc.t("%s is finished") % Loc.t(Defs.BUILDINGS[b["type"]]["name"]))
		building_completed.emit(b)
		_check_quest()
	changed.emit()

## Finish every construction site at once (tests, debugging).
func finish_all_construction() -> void:
	for b in buildings:
		if not is_built(b):
			b.erase("build")
			building_completed.emit(b)
	_assign_workers()
	changed.emit()
	_check_quest()

func set_speed(s: float) -> void:
	speed = s
	changed.emit()

# ---------------- simulation ----------------

func _process(delta: float) -> void:
	step(delta * speed)

## Advances the day clock by dt seconds of game time (tests call this directly).
func step(dt: float) -> void:
	if dt <= 0.0: return
	_day_timer += dt
	while _day_timer >= Defs.DAY_LENGTH:
		_day_timer -= Defs.DAY_LENGTH
		_end_of_day()

func day_progress() -> float:
	return _day_timer / Defs.DAY_LENGTH

func _end_of_day() -> void:
	day += 1
	fresh_start = false
	_yesterday = _today
	_today = {}
	var eat := population * Defs.FOOD_PER_VILLAGER
	if resources["food"] >= eat:
		resources["food"] -= eat
		if starving:
			toast.emit(Loc.t("Everyone has eaten. Back to work"))
		starving = false
		if population < housing() and resources["food"] >= Defs.GROWTH_FOOD_MIN:
			population += 1
			toast.emit(Loc.t("A new colonist arrived!"))
	else:
		resources["food"] = 0
		if not starving:
			toast.emit(Loc.t("Out of food! Only agronomists keep working"))
		starving = true
	_assign_workers()
	day_passed.emit(day)
	changed.emit()
	_check_quest()
	if _autosave:
		save_game()

func _assign_workers() -> void:
	var free := population
	# construction sites get their builders first (one each, oldest first)
	for b in buildings:
		if not is_built(b):
			b["staffed"] = free > 0
			if free > 0: free -= 1
	for b in buildings:
		if not is_built(b): continue
		var need := int(Defs.BUILDINGS[b["type"]].get("workers", 0))
		if need == 0:
			b["staffed"] = true
		elif free >= need:
			b["staffed"] = true
			free -= need
		else:
			b["staffed"] = false

## Whether a staffed building is actually working right now (when starving only food jobs continue).
func is_active(b: Dictionary) -> bool:
	if not is_built(b): return b["staffed"]        # builders keep building even when food runs out
	var d: Dictionary = Defs.BUILDINGS[b["type"]]
	if d.get("workers", 0) == 0 or not b["staffed"]: return false
	return not starving or d.get("yield", {}).has("food")

# ---------------- quests ----------------

func current_quest() -> Dictionary:
	if quest_index < Defs.QUESTS.size():
		return Defs.QUESTS[quest_index]
	return {}

func quest_progress(q: Dictionary) -> Vector2i:
	match q.get("type", ""):
		"build": return Vector2i(count_of(q["building"]), q["count"])
		"population": return Vector2i(population, q["value"])
		"resource": return Vector2i(int(resources.get(q["res"], 0)), q["value"])
	return Vector2i(0, 1)

func _check_quest() -> void:
	var guard := 0
	while guard < 10:
		guard += 1
		var q := current_quest()
		if q.is_empty(): return
		var p := quest_progress(q)
		if p.x < p.y: return
		for r in q["reward"]:
			resources[r] += int(q["reward"][r])
		var reward_txt: String = Defs.cost_text(q["reward"])
		toast.emit(Loc.t("Quest complete: %s%s") % [Loc.t(q["text"]), (Loc.t("  Reward: ") + reward_txt) if reward_txt != "" else ""])
		quest_index += 1
		quest_changed.emit()
		changed.emit()
		if current_quest().is_empty():
			toast.emit(Loc.t("All quests complete! Keep building freely"))

# ---------------- save / load ----------------

func save_game() -> void:
	var list := []
	for b in buildings:
		var e := {"type": b["type"], "x": snappedf(b["pos"].x, 0.001), "z": snappedf(b["pos"].y, 0.001),
			"angle": snappedf(b["angle"], 0.0001)}
		if b.has("field"): e["field"] = (b["field"] as Array).duplicate()
		if b.has("area"): e["area"] = (b["area"] as Array).duplicate()
		if not is_built(b): e["build"] = snappedf(b["build"], 0.001)
		if b.has("crop"): e["crop"] = snappedf(b["crop"], 0.001)
		if b.has("harvest"): e["harvest"] = int(b["harvest"])
		list.append(e)
	var data := {
		"version": SAVE_VERSION, "resources": resources, "population": population, "day": day,
		"quest_index": quest_index, "starving": starving, "day_timer": _day_timer, "buildings": list,
		"today": _today, "yesterday": _yesterday,
		"zones": _zone_list(),
		"trees": _tree_list(),
		"fish": fish,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func _tree_list() -> Array:
	var out := []
	for t in trees:
		out.append([t["id"], snappedf(t["pos"].x, 0.01), snappedf(t["pos"].y, 0.01), t["kind"], t["var"],
			snappedf(t["h"], 0.01), snappedf(t["r"], 0.01), snappedf(t["growth"], 0.001), t["chops"],
			snappedf(t["stump"], 0.01), 1 if t["wild"] else 0])
	return out

func _zone_list() -> Array:
	var out := []
	for i in zones.size():
		if zones[i]: out.append(i)
	return out

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY: return false
	var version := int(data.get("version", 0))
	if version < 1 or version > SAVE_VERSION: return false
	resources = {}
	for r in Defs.RESOURCES:
		resources[r] = int(data["resources"].get(r, 0))
	population = int(data["population"])
	day = int(data["day"])
	quest_index = int(data["quest_index"])
	starving = bool(data.get("starving", false))
	_day_timer = float(data.get("day_timer", 0.0))
	_today = data.get("today", {}); _yesterday = data.get("yesterday", {})
	_clear_zones()
	for i in data.get("zones", []):
		set_zone(int(i), true)
	zones_changed.emit()
	fish = {}
	for k in data.get("fish", {}): fish[str(k)] = float(data["fish"][k])
	trees.clear()           # empty = the map's own trees (Forest seeds them)
	for r in data.get("trees", []):
		trees.append({"id": int(r[0]), "pos": Vector2(r[1], r[2]), "kind": int(r[3]), "var": int(r[4]),
			"h": float(r[5]), "r": float(r[6]), "growth": float(r[7]), "chops": int(r[8]),
			"stump": float(r[9]), "wild": int(r[10]) == 1})
	buildings.clear()
	_next_id = 1
	for e in data["buildings"]:
		if not Defs.BUILDINGS.has(e["type"]): continue
		var pos: Vector2; var angle: float
		if version == 1:
			# grid save: cell is the footprint corner, rot is in quarter turns
			var s: int = Defs.BUILDINGS[e["type"]]["size"]
			pos = Vector2(int(e["x"]) + s / 2.0, int(e["y"]) + s / 2.0)
			angle = int(e.get("rot", 0)) * PI / 2.0
		else:
			pos = Vector2(float(e["x"]), float(e["z"]))
			angle = float(e.get("angle", 0.0))
		var nb := {"id": _next_id, "type": e["type"], "pos": pos, "angle": angle, "staffed": false}
		for key in ["build", "crop"]:
			if e.has(key): nb[key] = float(e[key])
		if e.has("harvest"): nb["harvest"] = int(e["harvest"])
		for key in ["field", "area"]:           # painted farm field / forest area cells
			if e.has(key):
				var cells: Array = []
				for i in e[key]: cells.append(int(i))
				nb[key] = cells
		buildings.append(nb)
		_next_id += 1
	if count_of("cart") == 0:
		# saves from before the supply-cart opening: give them a cart at the village centre
		buildings.append({"id": _next_id, "type": "cart", "pos": Defs.CART_SPOT, "angle": Defs.CART_ANGLE, "staffed": false})
		_next_id += 1
	fresh_start = false
	_assign_workers()
	return true

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _autosave:
		save_game()
