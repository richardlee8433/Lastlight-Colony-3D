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

var _next_id := 1
var _day_timer := 0.0
var _autosave := true
var _today := {}                 # goods delivered today
var _yesterday := {}             # goods delivered during the previous full day

func _ready() -> void:
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
	for b in buildings.duplicate():
		buildings.erase(b)
		building_removed.emit(b)
	_next_id = 1
	_assign_workers()
	reset.emit()
	changed.emit(); quest_changed.emit()

# ---------------- queries ----------------

func housing() -> int:
	var h: int = Defs.START["housing"]
	for b in buildings:
		h += int(Defs.BUILDINGS[b["type"]].get("housing", 0))
	return h

func workers_needed() -> int:
	var n := 0
	for b in buildings:
		n += int(Defs.BUILDINGS[b["type"]].get("workers", 0))
	return n

func workers_used() -> int:
	var n := 0
	for b in buildings:
		if b["staffed"]:
			n += int(Defs.BUILDINGS[b["type"]].get("workers", 0))
	return n

func count_of(type: String) -> int:
	var n := 0
	for b in buildings:
		if b["type"] == type: n += 1
	return n

func can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if int(resources.get(r, 0)) < int(cost[r]): return false
	return true

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
			toast.emit("資源不足：需要 " + Defs.cost_text(d["cost"]))
			return {}
		for r in d["cost"]:
			resources[r] -= int(d["cost"][r])
	var b := {"id": _next_id, "type": type, "pos": pos, "angle": angle, "staffed": false}
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
	for r in d["cost"]:
		resources[r] += int(d["cost"][r] / 2.0)
	buildings.erase(b)
	population = min(population, housing())
	_assign_workers()
	building_removed.emit(b)
	toast.emit("已拆除%s，退回一半資源" % d["name"])
	changed.emit()

## A villager carried goods into a storage at world point `at`.
func deliver(res: String, amount: int, at := Vector2.ZERO) -> void:
	if amount <= 0 or not resources.has(res): return
	resources[res] += amount
	_today[res] = int(_today.get(res, 0)) + amount
	delivered.emit(res, amount, at)
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
	_yesterday = _today
	_today = {}
	var eat := population * Defs.FOOD_PER_VILLAGER
	if resources["food"] >= eat:
		resources["food"] -= eat
		if starving:
			toast.emit("村民吃飽了，恢復工作")
		starving = false
		if population < housing() and resources["food"] >= Defs.GROWTH_FOOD_MIN:
			population += 1
			toast.emit("一位新村民搬進村子！")
	else:
		resources["food"] = 0
		if not starving:
			toast.emit("食物不足！只剩農夫還在工作")
		starving = true
	_assign_workers()
	day_passed.emit(day)
	changed.emit()
	_check_quest()
	if _autosave:
		save_game()

func _assign_workers() -> void:
	var free := population
	for b in buildings:
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
		toast.emit("任務完成：%s%s" % [q["text"], ("  獎勵 " + reward_txt) if reward_txt != "" else ""])
		quest_index += 1
		quest_changed.emit()
		changed.emit()
		if current_quest().is_empty():
			toast.emit("所有任務完成！繼續自由建造吧")

# ---------------- save / load ----------------

func save_game() -> void:
	var list := []
	for b in buildings:
		list.append({"type": b["type"], "x": snappedf(b["pos"].x, 0.001), "z": snappedf(b["pos"].y, 0.001),
			"angle": snappedf(b["angle"], 0.0001)})
	var data := {
		"version": SAVE_VERSION, "resources": resources, "population": population, "day": day,
		"quest_index": quest_index, "starving": starving, "day_timer": _day_timer, "buildings": list,
		"today": _today, "yesterday": _yesterday,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

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
		buildings.append({"id": _next_id, "type": e["type"], "pos": pos, "angle": angle, "staffed": false})
		_next_id += 1
	_assign_workers()
	return true

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _autosave:
		save_game()
