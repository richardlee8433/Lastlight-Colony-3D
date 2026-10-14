extends SceneTree
## Headless residential-zone test:
##   godot --headless --path . --script res://tests/test_zones.gd

var _frame := 0
var _fails := 0
var _done := false

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	_frame += 1
	if _frame == 5:
		_run()
		var ok := _fails == 0 and _done
		print("RESULT: ", "PASS" if ok else "FAIL (%d%s)" % [_fails, "" if _done else ", crashed"])
		quit(0 if ok else 1)
	return false

func check(cond: bool, msg: String) -> void:
	if cond: print("  ok   ", msg)
	else:
		print("  FAIL ", msg); _fails += 1

func _run() -> void:
	var game = root.get_node("Game")
	var s = current_scene
	var zones = s.get_node("Zones")
	var ctl = s.get_node("BuildController")
	game._autosave = false; game.instant_build = true
	game.delete_save(); game.new_game(); game.speed = 0.0

	# --- ground overlay is wired ---
	var wear = s.get_node("PathWear")
	check(wear._ground_mats.size() > 0 and wear._ground_mats[0].get_shader_parameter("zone_tex") != null, "zone overlay hooked into the ground shader")

	# --- painting ---
	var tree: Vector3 = s.get_node("Nav").trees[0]
	check(zones.paint(Vector2(tree.x, tree.z), true, 0.2) == 0, "cannot zone a tree trunk")
	var n: int = 0
	for x in range(-6, 1):
		for z in range(8, 13):
			n += zones.paint(Vector2(x, z), true)
	check(game.zone_count() > 60 and n == game.zone_count(), "painted a residential zone (%d cells)" % game.zone_count())
	check(zones.is_zoned(Vector2(-3, 10)), "zone covers the painted area")
	var before: int = game.zone_count()
	zones.paint(Vector2(0, 12.5), false)
	check(game.zone_count() < before, "shift-drag erases zone cells")

	# --- no growth without need ---
	game.resources["wood"] = 0
	zones._since_last = 999.0
	check(not zones.should_grow(), "no house when the village can't pay")
	game.resources["wood"] = 200; game.resources["stone"] = 200; game.resources["food"] = 100
	game.population = 1
	check(not zones.should_grow(), "no house while there are plenty of free beds")

	# --- growth ---
	game.population = game.housing()
	check(zones.should_grow(), "beds full + resources + zone -> grow")
	zones.tick(Defs.ZONE["grow_check"] + 0.01)
	var houses := []
	for b in game.buildings:
		if b["type"] == "house": houses.append(b)
	check(houses.size() == 1, "a house grew in the zone")
	if houses.size() == 1:
		var hb: Dictionary = houses[0]
		var inside := true
		for c in Defs.footprint_corners("house", hb["pos"], hb["angle"], -0.15):
			if not zones.is_zoned(c): inside = false
		check(inside, "the house sits inside the zone at %s" % hb["pos"])
		var door: Vector2 = Defs.to_world(hb, Vector2(0, 1.5)) - hb["pos"]
		var to_centre: Vector2 = game.center() - hb["pos"]
		check(door.normalized().dot(to_centre.normalized()) > 0.5, "door faces the village (no paths yet)")
		check(game.resources["wood"] == 180 and game.resources["stone"] == 185, "house cost paid")
	check(game.quest_index >= 0, "quests still fine")

	# --- cooldown, then more houses fill the zone ---
	game.population = game.housing()
	zones.tick(Defs.ZONE["grow_check"] + 0.01)
	var count := 0
	for b in game.buildings:
		if b["type"] == "house": count += 1
	check(count == 1, "cooldown between houses")
	for i in 30:
		game.population = game.housing()
		zones.tick(Defs.ZONE["grow_check"] + 0.01)
	count = 0
	for b in game.buildings:
		if b["type"] == "house": count += 1
	check(count >= 3, "zone fills up with several houses (%d)" % count)
	var overlap := false
	for a in game.buildings:
		for b in game.buildings:
			if a["id"] < b["id"] and Defs.quads_overlap(Defs.footprint_corners(a["type"], a["pos"], a["angle"]), Defs.footprint_corners(b["type"], b["pos"], b["angle"])):
				overlap = true
	check(not overlap, "grown houses never overlap")

	# --- saving ---
	var zc: int = game.zone_count()
	game.save_game()
	game._clear_zones()
	check(game.load_game() and game.zone_count() == zc, "zones are saved (%d)" % zc)

	# --- brush mode ---
	ctl.begin_place("zone")
	check(ctl.placing == "zone" and zones.painting, "zone brush mode")
	ctl.cancel_place()
	check(ctl.placing == "" and not zones.painting, "leave brush mode")
	game.delete_save()
	_done = true
