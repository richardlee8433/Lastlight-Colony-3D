extends SceneTree
## Headless test of the utility pipe network between finished buildings:
##   godot --headless --path . --script res://tests/test_utilities.gd

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

func spot(ctl, type: String, near: Vector2) -> Vector2:
	for r in range(0, 40):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16), sin(k * TAU / 16)) * r * 0.5
			if ctl.can_place(type, p, 0.0): return p
	return near

func _run() -> void:
	var game = root.get_node("Game")
	var s = current_scene
	var ctl = s.get_node("BuildController")
	var util = s.get_node("Utilities")
	game._autosave = false; game.instant_build = true
	game.delete_save(); game.new_game(); game.speed = 0.0
	game.resources["wood"] = 500; game.resources["stone"] = 500
	util._refresh()
	check(util.links.is_empty(), "only the pod: no pipes yet")
	var ids := []
	for e in [["storehouse", Vector2(5, 5)], ["farm", Vector2(-4, 8)], ["storehouse", Vector2(8, 11)]]:
		ids.append(ctl.try_place(e[0], spot(ctl, e[0], e[1]), 0.0))
	util._refresh()
	var built := 0
	for b in game.buildings:
		if game.is_built(b): built += 1
	check(util.links.size() == built - 1, "finished buildings are linked into one network (%d links, %d buildings)" % [util.links.size(), built])
	check(util.get_child_count() >= util.links.size(), "pipe runs built")
	# no link passes through a third building
	var crossing := 0
	for l in util.links:
		var a = game.get_building(l[0]); var b = game.get_building(l[1])
		if not util._clear(a, b, game.buildings): crossing += 1
	check(crossing == 0, "no pipe runs through a building")
	# links stay within reach
	var too_long := 0
	for l in util.links:
		if (game.get_building(l[0])["pos"] as Vector2).distance_to(game.get_building(l[1])["pos"]) > util.MAX_LINK: too_long += 1
	check(too_long == 0, "links are at most %d m" % int(util.MAX_LINK))
	# demolishing updates the network
	var n0: int = util.links.size()
	game.demolish(ids[2])
	util._refresh()
	check(util.links.size() == n0 - 1, "a demolished building's pipes go (%d -> %d)" % [n0, util.links.size()])
	game.delete_save()
	_done = true
