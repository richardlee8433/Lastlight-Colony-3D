extends SceneTree
## Balance check: plays a simple build order for 30 in-game days and prints the economy per day.
##   godot --headless --path . --script res://tests/sim_balance.gd
var f := 0
func _initialize(): change_scene_to_file("res://main.tscn")
func spot(ctl, type, near, angle := 0.0):
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
	var plan = [["woodcutter", Vector2(-6, 7)], ["farm", Vector2(2, 8)], ["quarry", Vector2(8, 8)], ["house", Vector2(6, 3)],
		["farm", Vector2(-2, 11)], ["house", Vector2(-7, 2)], ["storehouse", Vector2(-4, 10)], ["woodcutter", Vector2(-9, -6)], ["house", Vector2(6, -4)], ["farm", Vector2(3, 13)]]
	var i := 0
	for day in 30:
		for k in 300:
			game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
			if i < plan.size() and game.can_afford(Defs.BUILDINGS[plan[i][0]]["cost"]):
				var p = spot(ctl, plan[i][0], plan[i][1])
				if p != null and ctl.try_place(plan[i][0], p) > 0:
					print("  day %d built %s" % [game.day, plan[i][0]])
				i += 1
		print("day %2d  wood %3d stone %3d food %3d  pop %d/%d  income w%d s%d f%d %s" % [game.day, game.resources["wood"], game.resources["stone"], game.resources["food"], game.population, game.housing(), game.income_per_day("wood"), game.income_per_day("stone"), game.income_per_day("food"), "STARVING" if game.starving else ""])
	game.delete_save(); wear.clear(); quit()
	return false
