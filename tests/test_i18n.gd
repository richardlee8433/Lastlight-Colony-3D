extends SceneTree
## Language test: every English UI string has a Chinese entry, the bundled font has every
## glyph, and switching language at runtime updates the UI.
##   godot --headless --path . --script res://tests/test_i18n.gd

var _frame := 0
var _fails := 0
var _done := false

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	_frame += 1
	if _frame == 5:
		_run()
		var ok := _fails == 0 and _done
		print("RESULT: ", "PASS" if ok else "FAIL (%d%s)" % [_fails, "" if _done else ", crashed"])
		quit(0 if ok else 1)
	return false

func check(cond: bool, msg: String) -> void:
	if cond: print("  ok   ", msg)
	else:
		print("  FAIL ", msg); _fails += 1

func _scripts(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"): out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)

func _run() -> void:
	var game = root.get_node("Game")
	var loc = load("res://scripts/game/loc.gd")
	var defs = load("res://scripts/game/defs.gd")
	var fonts = load("res://scripts/ui/fonts.gd") if ResourceLoader.exists("res://scripts/ui/fonts.gd") else null
	var start_lang: String = loc.lang
	game._autosave = false; game.instant_build = true

	# --- every Loc.t("...") literal and every Defs text has a translation ---
	var keys := {}
	var files := []
	_scripts("res://scripts", files)
	var re := RegEx.new()
	re.compile("Loc\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		for m in re.search_all(src):
			keys[m.get_string(1).c_unescape()] = f
	for r in defs.RESOURCES: keys[defs.RESOURCES[r]["name"]] = "defs"
	for t in defs.BUILDINGS:
		keys[defs.BUILDINGS[t]["name"]] = "defs"; keys[defs.BUILDINGS[t]["desc"]] = "defs"
	for t in defs.TOOLS:
		for k in ["name", "desc", "label"]: keys[defs.TOOLS[t][k]] = "defs"
	for q in defs.QUESTS: keys[q["text"]] = "defs"
	var missing := []
	for k in keys:
		if not loc.ZH.has(k): missing.append("%s  (%s)" % [k, keys[k]])
	for m in missing: print("    missing: ", m)
	check(keys.size() > 80 and missing.is_empty(), "all %d UI strings have Chinese text" % keys.size())

	# --- placeholders match between languages ---
	var bad := []
	var ph := RegEx.new(); ph.compile("%[-+0-9.]*[sdf]")
	for k in loc.ZH:
		var a := []; var b := []
		for m in ph.search_all(k): a.append(m.get_string())
		for m in ph.search_all(loc.ZH[k]): b.append(m.get_string())
		if a != b: bad.append(k)
	for b in bad: print("    placeholder mismatch: ", b)
	check(bad.is_empty(), "format placeholders match in every translation")

	# --- the bundled font covers everything ---
	var font: Font = Fonts.cjk()
	check(font is FontFile, "bundled UI font loaded")
	var no_glyph := {}
	var texts: Array = loc.ZH.values() + keys.keys()
	for v in load("res://scripts/world/villager.gd").NAMES_ZH: texts.append(v)
	for t in texts:
		for i in (t as String).length():
			var c := (t as String).unicode_at(i)
			if c > 32 and not (font as FontFile).has_char(c): no_glyph[char(c)] = true
	if not no_glyph.is_empty(): print("    no glyph: ", "".join(no_glyph.keys()))
	check(no_glyph.is_empty(), "font has every character (re-run tools/subset_font.py if not)")

	# --- switching ---
	game.set_language("en")
	check(Defs.label("farm") == "Agri station" and Defs.res_name("wood") == "Fibre", "English names")
	var hud = current_scene.get_node("HUD")
	var lang_btn = hud.find_child("Language", true, false)
	check(lang_btn != null and lang_btn.text == "中文", "language button offers Chinese")
	game.set_language("zh")
	check(Defs.label("farm") == "農業站" and Defs.cost_text({"wood": 20}) == "纖維 20", "Chinese names")
	lang_btn = hud.find_child("Language", true, false)
	check(lang_btn != null and lang_btn.text == "English", "HUD rebuilt in Chinese")
	check(hud._build_buttons["farm"].text.contains("農業站"), "build menu translated")
	var vm = current_scene.get_node("Villagers")
	vm._sync()
	check(vm.villagers.size() > 0 and load("res://scripts/world/villager.gd").NAMES_ZH.has(vm.villagers[0].vname), "villager names follow the language")
	loc.load_settings()
	check(loc.lang == "zh", "language is remembered")
	game.set_language(start_lang)
	_done = true
