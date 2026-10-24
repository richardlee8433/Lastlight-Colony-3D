extends SceneTree
## Renders the stream with the east-road bridge and the pond — needs a display / xvfb:
##   godot --path . --script res://tests/shot_water.gd
## Saves _water_bridge.png and _water_pond.png.

var f := 0
var game; var cam; var sc

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); cam = current_scene.get_node("Camera"); sc = current_scene.get_node("Scatter")
		game._autosave = false; game.delete_save(); game.new_game(); game.speed = 0.0
		sc.grow_around(Vector2(19, 1), 20.0); sc.grow_around(Defs.WATER["pond"]["pos"], 14.0)
		var b: Dictionary = load("res://scripts/world/water.gd").bridges[0]
		cam.target = Vector3(b["pos"].x, 0.3, b["pos"].y); cam._dist = 13.0; cam._pitch = 0.62; cam._yaw = -0.9; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_water_bridge.png")
		var pc: Vector2 = Defs.WATER["pond"]["pos"]
		cam.target = Vector3(pc.x, 0.0, pc.y); cam._dist = 16.0; cam._pitch = 1.0; cam._yaw = -2.4; cam._apply()
	if f == 22:
		root.get_viewport().get_texture().get_image().save_png("res://_water_pond.png")
		game.delete_save()
		quit()
	return false
