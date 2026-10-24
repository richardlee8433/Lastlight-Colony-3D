extends SceneTree
## Renders the pond with a fishing hut, a fisher on the bank, reeds and lily pads — needs a display:
##   godot --path . --script res://tests/shot_fishing.gd
## Saves _fishing.png.

var f := 0
var game; var vm; var cam; var wear

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); vm = current_scene.get_node("Villagers"); cam = current_scene.get_node("Camera")
		wear = current_scene.get_node("PathWear")
		var ctl = current_scene.get_node("BuildController"); var fishing = current_scene.get_node("Fishing")
		game._autosave = false; game.instant_build = true
		game.delete_save(); game.new_game(); game.speed = 0.0
		game.resources["wood"] = 300
		vm._first_sync()
		var pond: Vector2 = Defs.WATER["pond"]["pos"]
		var sn: Dictionary = fishing.snap("fishery", pond + Vector2(4.0, 5.5))
		ctl.try_place("fishery", sn["pos"], sn["angle"])
		current_scene.get_node("Scatter").grow_around(pond, 14.0)
		var t := 0.0
		while t < 70.0:
			game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
			t += 0.1
		cam.target = Vector3(pond.x + 1.5, 0.0, pond.y + 2.5); cam._dist = 12.5; cam._pitch = 0.78; cam._yaw = 2.4; cam._apply()
	if f == 14:
		root.get_viewport().get_texture().get_image().save_png("res://_fishing.png")
		game.delete_save(); wear.clear()
		quit()
	return false
