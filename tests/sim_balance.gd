extends SceneTree
## Balance check: plays a simple build order for 30 in-game days and prints the economy per day.
##   godot --headless --path . --script res://tests/sim_balance.gd
var f := 0
func _initialize(): change_scene_to_file("res://main.tscn")
func spot(ctl, type, near, angle := 0.0):
	if Defs.BUILDINGS[type].get("on_deposit", false):     # quarries go on a free stone deposit
		var dep: int = current_scene.get_node("Deposits").free_near(near, 99.0)
		return Defs.DEPOSITS[dep]["pos"] if dep >= 0 else Vector2(999, 999)
	for r in range(0, 40):
		for k in 16:
			var p = near + Vector2(cos(k * TAU / 16), sin(k * TAU / 16)) * r * 0.5
			if ctl.can_place(type, p, angle): return p
	return null
func _process(_d):
	if current_scene == null: return false
	f += 1
	if f != 4: return false
	var game = root.get_node("Game"); var s = current_scene
	var vm = s.get_node("Villagers"); var wear = s.get_node("PathWear"); var ctl = s.get_node("BuildController")
	game._autosave = false; game.delete_save(); game.new_game(); game.speed = 0.0; vm._first_sync()
	var zones = s.get_node("Zones")
	var forest = s.get_node("Forest")
	for x in range(-9, -2):
		for z in range(4, 10):
			zones.paint(Vector2(x, z), true)
	var plan = [["woodcutter", Vector2(-6, -4)], ["farm", Vector2(3, 6)], ["quarry", Vector2(8, 3)],
		["farm", Vector2(4, 11)], ["storehouse", Vector2(5, -2)], ["woodcutter", Vector2(-9, -8)], ["farm", Vector2(-1, 12)]]
	var i := 0
	for day in 30:
		for k in 300:
			game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5); zones.tick(0.1); forest.tick(0.1)
			if i < plan.size() and game.can_afford(Defs.BUILDINGS[plan[i][0]]["cost"]):
				var p = spot(ctl, plan[i][0], plan[i][1])
				if p != null and ctl.try_place(plan[i][0], p) > 0:
					print("  day %d built %s" % [game.day, plan[i][0]])
				i += 1
		var trees := ""
		for b in game.buildings:
			if b["type"] == "woodcutter":
				var c: Dictionary = forest.counts(b["id"])
				trees += " [trees %d/%d/%d]" % [c["ready"], c["growing"], c["stumps"]]
		print(trees)
		print("day %2d  wood %3d stone %3d food %3d  pop %d/%d  income w%d s%d f%d %s" % [game.day, game.resources["wood"], game.resources["stone"], game.resources["food"], game.population, game.housing(), game.income_per_day("wood"), game.income_per_day("stone"), game.income_per_day("food"), "STARVING" if game.starving else ""])
	game.delete_save(); wear.clear(); quit()
	return false
