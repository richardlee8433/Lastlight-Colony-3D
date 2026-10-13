extends SceneTree
## Renders the stone deposits while placing a quarry, then a working quarry — needs a display / xvfb:
##   godot --path . --script res://tests/shot_quarry.gd
## Saves _quarry_place.png and _quarry.png.

var f := 0
var game; var vm; var wear; var cam; var ctl

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _sim(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
		t += 0.1

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	var d0: Vector2 = Defs.DEPOSITS[0]["pos"]
	if f == 3:
		game = root.get_node("Game"); vm = current_scene.get_node("Villagers"); wear = current_scene.get_node("PathWear")
		cam = current_scene.get_node("Camera"); ctl = current_scene.get_node("BuildController")
		game._autosave = false; game.delete_save(); game.new_game(); game.speed = 0.0
		game.resources["wood"] = 300; game.resources["stone"] = 300
		vm._first_sync()
		ctl.begin_place("quarry")
		ctl._ghost_pos = d0
		ctl._ghost.position = Vector3(d0.x, ctl.ground_height("quarry", d0, 0.0), d0.y)
		ctl._ghost_pad.position = ctl._ghost.position + Vector3(0, 0.06, 0)
		cam.target = Vector3(4.0, 0.3, 4.0); cam._dist = 21.0; cam._pitch = 0.95; cam._yaw = -0.6; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_quarry_place.png")
		ctl.cancel_place()
		ctl.try_place("quarry", d0, 2.6)
		_sim(40.0)
		cam.target = Vector3(d0.x, 0.6, d0.y); cam._dist = 8.5; cam._pitch = 0.6; cam._yaw = -0.785; cam._apply()
	if f == 22:
		root.get_viewport().get_texture().get_image().save_png("res://_quarry.png")
		game.delete_save(); wear.clear()
		quit()
	return false
