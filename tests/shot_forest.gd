extends SceneTree
## Renders a woodcutter with its forest area (brush active, then after some felling) — needs a display / xvfb:
##   godot --path . --script res://tests/shot_forest.gd
## Saves _forest_edit.png and _forest.png.

var f := 0
var game; var vm; var wear; var cam; var ctl; var forest
var spot := Vector2.ZERO
var start_lang := "en"

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _sim(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5); forest.tick(0.1)
		t += 0.1

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); vm = current_scene.get_node("Villagers"); wear = current_scene.get_node("PathWear")
		cam = current_scene.get_node("Camera"); ctl = current_scene.get_node("BuildController"); forest = current_scene.get_node("Forest")
		game._autosave = false; game.instant_build = true; game.delete_save(); game.new_game(); game.speed = 0.0
		game.resources["wood"] = 300; game.resources["stone"] = 300
		vm._first_sync()
		# next to the densest group of trees
		var best := Vector2.ZERO; var best_n := -1
		for t in game.trees:
			var n := 0
			for u in game.trees:
				if (t["pos"] as Vector2).distance_to(u["pos"]) < 4.5: n += 1
			if n > best_n and absf(t["pos"].x) < 13 and absf(t["pos"].y) < 13: best_n = n; best = t["pos"]
		spot = best.lerp(game.center(), 0.25)
		var id := -1
		for r in 40:
			for k in 16:
				var p: Vector2 = spot + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * r * 0.5
				if id < 0 and ctl.can_place("woodcutter", p, 0.0):
					id = ctl.try_place("woodcutter", p, 0.0); spot = p
		_sim(70.0)
		ctl.begin_forest(id)
		var mid := Vector2.ZERO
		for i in forest.area_of(id): mid += forest.cell_center(i)
		mid /= maxf(1.0, forest.area_of(id).size())
		spot = (spot + mid) / 2.0
		cam.target = Vector3(spot.x, 0.5, spot.y); cam._dist = 16.0; cam._pitch = 1.0; cam._yaw = 0.3; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_forest_edit.png")
		ctl.cancel_place()
		_sim(60.0)
		for b in game.buildings:
			if b["type"] == "woodcutter": print("counts ", forest.counts(b["id"]))
		var target := spot
		for t in game.trees:
			if t["stump"] > 0.0: target = t["pos"]
		cam.target = Vector3(target.x, 0.4, target.y); cam._dist = 5.0; cam._pitch = 0.32; cam._yaw = -0.5; cam._apply()
	if f == 22:
		root.get_viewport().get_texture().get_image().save_png("res://_forest.png")
		game.delete_save(); wear.clear()
		quit()
	return false
