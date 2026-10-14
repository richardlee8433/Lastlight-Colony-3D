extends SceneTree
## Renders the UI in English and Chinese (farmhouse selected) — needs a display / xvfb:
##   godot --path . --script res://tests/shot_ui.gd
## Saves _ui_en.png and _ui_zh.png.

var f := 0
var game; var vm; var wear; var cam; var ctl
var start_lang := "en"

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); vm = current_scene.get_node("Villagers"); wear = current_scene.get_node("PathWear")
		cam = current_scene.get_node("Camera"); ctl = current_scene.get_node("BuildController")
		start_lang = Loc.lang
		game._autosave = false; game.instant_build = true; game.delete_save(); game.new_game(); game.speed = 0.0
		vm._first_sync()
		var id: int = -1
		var spot := Vector2(-5.5, -4.5)
		for k in 60:
			if ctl.can_place("farm", spot, 0.35):
				id = ctl.try_place("farm", spot, 0.35)
				break
			spot += Vector2(0.5, 0.3)
		print("farm ", id, " at ", spot)
		for k in 60:
			game.step(0.1); vm.tick(0.1)
		ctl.select(id)
		game.set_language("en")
		cam.target = Vector3(spot.x + 1.5, 0.3, spot.y + 2.0); cam._dist = 14.0; cam._pitch = 0.8; cam._yaw = -0.3; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_ui_en.png")
		game.set_language("zh")
	if f == 20:
		root.get_viewport().get_texture().get_image().save_png("res://_ui_zh.png")
		game.set_language(start_lang)
		game.delete_save(); wear.clear()
		quit()
	return false
