extends SceneTree
## Renders a few finished houses, a storehouse and a farm with their lived-in props — needs a display:
##   godot --path . --script res://tests/shot_props.gd
## Saves _props.png.

var f := 0
var game; var cam; var ctl; var vm; var wear

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
		game = root.get_node("Game"); cam = current_scene.get_node("Camera"); ctl = current_scene.get_node("BuildController")
		vm = current_scene.get_node("Villagers"); wear = current_scene.get_node("PathWear")
		game._autosave = false; game.instant_build = true
		game.delete_save(); game.new_game(); game.speed = 0.0
		game.resources["wood"] = 900; game.resources["stone"] = 600; game.resources["food"] = 300
		vm._first_sync()
		for i in 3:
			ctl.try_place("house", _spot("house", Vector2(-6.0 + i * 5.2, 9.5)), 0.0)
		ctl.try_place("house", _spot("house", Vector2(-3.5, 15.0)), PI)
		ctl.try_place("storehouse", _spot("storehouse", Vector2(6.5, 4.0), -0.5), -0.5)
		cam.target = Vector3(-1.0, 0.5, 11.0); cam._dist = 14.0; cam._pitch = 0.72; cam._yaw = -0.45; cam._apply()
	if f == 14:
		root.get_viewport().get_texture().get_image().save_png("res://_props.png")
		game.delete_save(); wear.clear()
		quit()
	return false
