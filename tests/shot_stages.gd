extends SceneTree
## Renders the construction stages (foundation, frame, finished) and the wheat stages
## (tilled, young, ripe) side by side — needs a display / xvfb:
##   godot --path . --script res://tests/shot_stages.gd
## Saves _stages_build.png and _stages_wheat.png.

var f := 0
var game; var vm; var wear; var cam; var ctl; var fields

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _spot(type: String, near: Vector2, ang := 0.0) -> Vector2:
	for r in range(0, 40):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * r * 0.5
			if ctl.can_place(type, p, ang): return p
	return near

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); vm = current_scene.get_node("Villagers"); wear = current_scene.get_node("PathWear")
		cam = current_scene.get_node("Camera"); ctl = current_scene.get_node("BuildController"); fields = current_scene.get_node("Fields")
		game._autosave = false; game.instant_build = false
		game.delete_save(); game.new_game(); game.speed = 0.0
		game.resources["wood"] = 500; game.resources["stone"] = 300; game.population = 0
		vm._first_sync()
		# three houses: foundation, timber frame, finished
		var progress := [0.15, 0.65, 1.0]
		for i in 3:
			var id: int = ctl.try_place("house", _spot("house", Vector2(-4.0 + i * 3.6, 6.5)), 0.0)
			if id >= 0 and progress[i] > 0.0: game.add_build_progress(id, progress[i])
		# three farms: tilled, young, ripe
		var crops := [0.0, 0.45, 1.0]
		for i in 3:
			var id: int = ctl.try_place("farm", _spot("farm", Vector2(-5.5 + i * 5.5, 12.0)), 0.0)
			if id < 0: continue
			game.add_build_progress(id, 1.0)
			var b: Dictionary = game.get_building(id)
			b["crop"] = crops[i]
			if crops[i] >= 1.0: b["harvest"] = Defs.FIELD["harvest_trips"]
			fields._update_crop(b)
		cam.target = Vector3(-0.4, 0.5, 6.5); cam._dist = 12.0; cam._pitch = 0.6; cam._yaw = 0.0; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_stages_build.png")
		cam.target = Vector3(2.5, 0.3, 13.0); cam._dist = 21.0; cam._pitch = 0.85; cam._yaw = 0.0; cam._apply()
	if f == 22:
		root.get_viewport().get_texture().get_image().save_png("res://_stages_wheat.png")
		game.delete_save(); wear.clear()
		quit()
	return false
