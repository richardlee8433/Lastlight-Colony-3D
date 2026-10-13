extends SceneTree
var f := 0
func _initialize(): change_scene_to_file("res://main.tscn")
func _process(_d):
	if current_scene == null: return false
	f += 1
	var game = root.get_node("Game")
	var ctl = current_scene.get_node("BuildController")
	if f == 3:
		game._autosave = false
		game.delete_save(); game.new_game()
		game.resources["wood"] = 300; game.resources["stone"] = 200
		ctl.try_place("woodcutter", Vector2i(-6, 5))
		ctl.try_place("farm", Vector2i(-1, 6))
		ctl.try_place("house", Vector2i(4, 4))
		ctl.try_place("house", Vector2i(4, 8))
		ctl.try_place("quarry", Vector2i(8, 5))
		game.step(3.9)
		ctl.select(game.buildings[1]["id"])
		ctl.begin_place("house")
		ctl.cancel_place()
		ctl.select(game.buildings[1]["id"])
	if f == 40:
		root.get_viewport().get_texture().get_image().save_png("res://_ui.png")
		game.delete_save()
		quit()
	return false
