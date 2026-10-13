extends SceneTree
## Headless woodcutter / forest test:
##   godot --headless --path . --script res://tests/test_forest.gd

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

func find_spot(ctl, type: String, near: Vector2, ang := 0.0) -> Vector2:
	if Defs.BUILDINGS[type].get("on_deposit", false):     # quarries go on a free stone deposit
		var dep: int = current_scene.get_node("Deposits").free_near(near, 99.0)
		return Defs.DEPOSITS[dep]["pos"] if dep >= 0 else Vector2(999, 999)
	for r in range(0, 50):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * r * 0.5
			if ctl.can_place(type, p, ang): return p
	return Vector2.INF

func _run() -> void:
	var game = root.get_node("Game")
	var s = current_scene
	var forest = s.get_node("Forest")
	var ctl = s.get_node("BuildController")
	var nav = s.get_node("Nav")
	var vm = s.get_node("Villagers")
	var zones = s.get_node("Zones")
	var fields = s.get_node("Fields")
	var wear = s.get_node("PathWear")
	game._autosave = false
	game.delete_save(); game.new_game(); game.speed = 0.0
	game.resources["wood"] = 500; game.resources["stone"] = 500; game.resources["food"] = 300

	# --- the map's trees are separate, choppable models ---
	check(game.trees.size() == nav.tree_data.size() and game.trees.size() > 20, "map trees seeded (%d)" % game.trees.size())
	check(forest._nodes.size() == game.trees.size(), "every tree has a model")
	var all_grown := true
	for t in game.trees:
		if not forest.is_grown(t): all_grown = false
	check(all_grown, "all start fully grown")

	# --- a lodge next to the densest group of trees gets a starter area over them ---
	var best: Vector2; var best_n := -1
	for t in game.trees:
		var n := 0
		for u in game.trees:
			if (t["pos"] as Vector2).distance_to(u["pos"]) < 4.5: n += 1
		if n > best_n and absf(t["pos"].x) < 13 and absf(t["pos"].y) < 13: best_n = n; best = t["pos"]
	var spot: Vector2 = find_spot(ctl, "woodcutter", best.lerp(game.center(), 0.25))
	var id: int = ctl.try_place("woodcutter", spot, 0.0)
	check(id >= 0, "woodcutter placed at %s" % spot)
	var area: Array = forest.area_of(id)
	var c: Dictionary = forest.counts(id)
	check(area.size() >= Defs.FOREST["min_cells"], "starter forest area painted (%d cells)" % area.size())
	check(c["ready"] >= 1, "starter area covers grown trees (%d)" % c["ready"])
	var outside := 0
	for t in game.trees:
		if forest.area_owner_at(t["pos"]) == 0: outside += 1
	check(outside > 0, "trees outside the area stay scenery (%d)" % outside)

	# --- felling ---
	var t: Dictionary = forest.pick_tree(id, spot)
	check(not t.is_empty() and forest.area_owner_at(t["pos"]) == id, "picks a grown tree inside the area")
	var chops := 0
	while forest.chop(t["id"], spot): chops += 1
	check(chops == Defs.FOREST["chops_per_tree"], "a tree gives %d trips of wood" % chops)
	check(t["stump"] > 0.0 and not forest.is_grown(t), "then falls and leaves a stump")
	check(forest.counts(id)["stumps"] == 1, "stump counted")
	check(forest.pick_tree(id, spot).get("id", -1) != t["id"], "a stump is not picked again")
	check(not forest.chop(t["id"], spot), "a stump gives no wood")

	# --- regrowth ---
	var day: float = Defs.DAY_LENGTH
	forest.tick(Defs.FOREST["stump_days"] * day + 0.1)
	check(t["stump"] == 0.0 and t["growth"] < 0.2, "the stump sprouts a sapling")
	forest.tick(Defs.FOREST["grow_days"] * day * 0.5)
	check(t["growth"] > 0.4 and t["growth"] < 1.0, "the sapling grows (%.2f)" % t["growth"])
	forest.tick(Defs.FOREST["grow_days"] * day * 0.6)
	check(forest.is_grown(t), "and is a tree again")

	# --- an area in the open meadow fills with saplings ---
	var spot2: Vector2 = find_spot(ctl, "woodcutter", Vector2(5, -3))
	var id2: int = ctl.try_place("woodcutter", spot2, 0.0)
	check(id2 >= 0, "second lodge in the meadow")
	var c2: Dictionary = forest.counts(id2)
	var before: int = game.trees.size()
	for k in 40:
		forest.tick(Defs.FOREST["sprout_check"])
	var sprouted: int = game.trees.size() - before
	var target: int = forest.area_of(id2).size() / int(Defs.FOREST["cells_per_tree"])
	check(sprouted >= 1 and sprouted <= target, "saplings sprout in the area (%d of %d)" % [sprouted, target])
	var spaced := true
	for a in game.trees:
		for b in game.trees:
			if a["id"] < b["id"] and not (a["wild"] and b["wild"]) and (a["pos"] as Vector2).distance_to(b["pos"]) < Defs.FOREST["spacing"] - 0.01:
				spaced = false
	check(spaced, "saplings keep their distance")
	var young: Dictionary = {}
	for a in game.trees:
		if not a["wild"] and a["id"] > before: young = a
	if not young.is_empty():
		var cell = nav.cell_of(Vector3(young["pos"].x, 0, young["pos"].y))
		forest.tick(Defs.FOREST["grow_days"] * day)
		check(forest.is_grown(young) and not nav.is_walkable(cell), "grown planted trees block walking")
		check(ctl.place_problem("storehouse", young["pos"], 0.0) != "", "can't build on a forest area / tree")

	# --- other areas respect forest areas ---
	var fc: Vector2 = forest.cell_center(forest.area_of(id)[forest.area_of(id).size() / 2])
	check(zones.paint(fc, true, 0.3) == 0, "can't zone over a forest area")
	var farm: int = ctl.try_place("farm", find_spot(ctl, "farm", Vector2(-3, 10)), 0.0)
	if farm >= 0:
		check(fields.cell_problem(game.get_building(farm), fields.cell_of(fc)) != "", "fields can't cover a forest area")
	check(forest.paint(id2, fc, true, 0.3) == 0, "one lodge can't paint over another's area")

	# --- brush: paint / erase / clear ---
	ctl.begin_forest(id)
	check(ctl.placing == "forest" and ctl.area_owner == id and forest.editing == id, "forest brush mode")
	var n0: int = forest.area_of(id).size()
	ctl.set_erase(true)
	ctl.brush_at(fc, false)
	check(forest.area_of(id).size() < n0, "erase part of the area")
	ctl.set_erase(false)
	ctl.clear_brush_area()
	check(forest.area_of(id).is_empty() and forest.counts(id)["ready"] == 0, "clear the whole area (trees stay: %d)" % game.trees.size())
	ctl.cancel_place()
	check(ctl.placing == "" and forest.editing == -1, "leave the brush")

	# --- the woodcutter at work ---
	forest.auto_area(game.get_building(id))
	vm._sync()
	var cutter = null
	for v in vm.villagers:
		if v.job_id == id: cutter = v
	check(cutter != null, "the lodge has a woodcutter")
	var wood0: int = game.resources["wood"]
	var chops0: int = forest.chops_done
	var tt := 0.0
	while tt < 150.0:
		game.step(0.1); vm.tick(0.1); forest.tick(0.1); wear.tick(0.1, 0.5)
		tt += 0.1
	var chops1: int = forest.chops_done
	check(game.resources["wood"] > wood0, "logs carried to storage (+%d wood)" % (game.resources["wood"] - wood0))
	check(chops1 > chops0, "trees in the area were chopped (%d chops)" % (chops1 - chops0))

	# --- no trees: the woodcutter waits ---
	forest.clear(id)
	if cutter:
		check(vm.work_target(cutter).is_empty(), "no grown trees in the area -> nothing to do")

	# --- saving ---
	forest.auto_area(game.get_building(id))
	var stump_tree: Dictionary = forest.pick_tree(id, spot)
	if not stump_tree.is_empty():
		while forest.chop(stump_tree["id"], spot): pass
	var saved_area: Array = forest.area_of(id).duplicate()
	var saved_trees: int = game.trees.size()
	game.save_game()
	game.load_game()
	forest._init_existing()
	var lb: Dictionary = {}
	for b in game.buildings:
		if b["type"] == "woodcutter" and b["pos"].distance_to(spot) < 0.01: lb = b
	check(not lb.is_empty() and lb.has("area") and lb["area"].size() == saved_area.size(), "forest area saved (%d cells)" % saved_area.size())
	var st: Dictionary = forest.tree_by_id(stump_tree.get("id", -1))
	check(game.trees.size() == saved_trees and not st.is_empty() and st["stump"] > 0.0, "trees saved, stumps stay stumps")
	check(forest._nodes.size() == game.trees.size(), "models rebuilt after loading")

	# --- a new game brings the original forest back ---
	game.new_game()
	var grown := 0
	for a in game.trees:
		if forest.is_grown(a): grown += 1
	check(game.trees.size() == nav.tree_data.size() and grown == game.trees.size(), "new game: the map's trees are back (%d)" % grown)
	game.delete_save()
	_done = true
