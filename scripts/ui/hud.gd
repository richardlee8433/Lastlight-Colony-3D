extends CanvasLayer
## In-game UI, built in code: resource bar, build menu, quest card, selection panel, toasts.

@export var controller_path: NodePath = ^"../BuildController"

const BG := Color(0.13, 0.10, 0.07, 0.86)
const BG_LIGHT := Color(0.24, 0.18, 0.12, 0.92)
const EDGE := Color(0.55, 0.42, 0.25, 0.9)
const TEXT := Color(0.96, 0.91, 0.80)
const MUTED := Color(0.78, 0.70, 0.58)
const GOLD := Color(1.0, 0.82, 0.38)

var _ctl: Node
var _root: Control
var _res_labels := {}
var _pop_label: Label
var _day_label: Label
var _day_bar: ProgressBar
var _build_buttons := {}
var _speed_buttons := {}
var _quest_title: Label
var _quest_progress: Label
var _quest_reward: Label
var _info: PanelContainer
var _info_title: Label
var _info_body: Label
var _del_button: Button
var _field_button: Button
var _brush_bar: PanelContainer
var _brush_title: Label
var _erase_button: Button
var _clear_button: Button
var _toasts: VBoxContainer
var _hint: Label

func _ready() -> void:
	_ctl = get_node(controller_path)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_top_bar()
	_build_speed()
	_build_quest()
	_build_menu()
	_build_info()
	_build_toasts()
	_build_hint()
	_build_brush_bar()
	_ctl.brush_changed.connect(_refresh_brush)
	Game.changed.connect(_refresh)
	Game.quest_changed.connect(_refresh_quest)
	Game.toast.connect(show_toast)
	_ctl.mode_changed.connect(_on_mode)
	_ctl.selection_changed.connect(_on_selection)
	_refresh(); _refresh_quest(); _on_mode("")

func _process(_d: float) -> void:
	_day_bar.value = Game.day_progress()
	if _info.visible and _ctl.selected >= 0:
		_fill_info(_ctl.selected)

# ---------------- layout ----------------

func _build_top_bar() -> void:
	var panel := _panel()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 12
	_root.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	panel.add_child(hb)
	for r in Defs.RESOURCES:
		var l := _label("", 20, Defs.RESOURCES[r]["color"].lightened(0.15))
		hb.add_child(l)
		_res_labels[r] = l
	hb.add_child(VSeparator.new())
	_pop_label = _label("", 20, TEXT)
	hb.add_child(_pop_label)
	hb.add_child(VSeparator.new())
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 2)
	_day_label = _label("", 18, GOLD)
	dv.add_child(_day_label)
	_day_bar = ProgressBar.new()
	_day_bar.max_value = 1.0
	_day_bar.show_percentage = false
	_day_bar.custom_minimum_size = Vector2(90, 6)
	dv.add_child(_day_bar)
	hb.add_child(dv)

func _build_speed() -> void:
	var panel := _panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-12, 12)
	_root.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	panel.add_child(hb)
	for s in [[0.0, "暫停"], [1.0, "1x"], [2.0, "2x"], [4.0, "4x"]]:
		var b := Button.new()
		b.text = s[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(46, 0)
		var sp: float = s[0]
		b.pressed.connect(func(): Game.set_speed(sp))
		hb.add_child(b)
		_speed_buttons[sp] = b
	var restart := Button.new()
	restart.text = "重新開始"
	restart.focus_mode = Control.FOCUS_NONE
	restart.pressed.connect(_confirm_restart)
	hb.add_child(restart)

func _build_quest() -> void:
	var panel := _panel()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(260, 0)
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(_label("任務", 15, MUTED))
	_quest_title = _label("", 20, TEXT)
	_quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_quest_title)
	_quest_progress = _label("", 17, GOLD)
	vb.add_child(_quest_progress)
	_quest_reward = _label("", 15, MUTED)
	vb.add_child(_quest_reward)

func _build_menu() -> void:
	var panel := _panel()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position.y = -12
	_root.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)
	var i := 1
	for type in Defs.BUILD_ORDER:
		var d: Dictionary = Defs.TOOLS[type] if Defs.TOOLS.has(type) else Defs.BUILDINGS[type]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 64)
		b.text = "%d  %s\n%s" % [i, d["name"], d["label"] if d.has("label") else Defs.cost_text(d["cost"])]
		b.tooltip_text = d["desc"]
		var t: String = type
		b.pressed.connect(func():
			if _ctl.placing == t: _ctl.cancel_place()
			else: _ctl.begin_place(t))
		hb.add_child(b)
		_build_buttons[type] = b
		i += 1

func _build_info() -> void:
	_info = _panel()
	_info.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_info.grow_vertical = Control.GROW_DIRECTION_BOTH
	_info.position.x = -12
	_info.custom_minimum_size = Vector2(240, 0)
	_root.add_child(_info)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_info.add_child(vb)
	_info_title = _label("", 22, GOLD)
	vb.add_child(_info_title)
	_info_body = _label("", 16, TEXT)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info_body)
	_field_button = Button.new()
	_field_button.text = "編輯田地"
	_field_button.focus_mode = Control.FOCUS_NONE
	_field_button.pressed.connect(func(): _ctl.begin_field(_ctl.selected))
	vb.add_child(_field_button)
	var del := Button.new()
	_del_button = del
	del.text = "拆除（退回一半資源）"
	del.focus_mode = Control.FOCUS_NONE
	del.pressed.connect(func(): _ctl.demolish_selected())
	vb.add_child(del)
	_info.visible = false

## Toolbar shown while painting a zone or a field: paint / erase toggle, clear, done.
func _build_brush_bar() -> void:
	_brush_bar = _panel()
	_brush_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_brush_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_brush_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_brush_bar.position.y = -128
	_root.add_child(_brush_bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_brush_bar.add_child(hb)
	_brush_title = _label("", 18, GOLD)
	_brush_title.custom_minimum_size = Vector2(170, 0)
	_brush_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_brush_title)
	var paint := Button.new()
	paint.text = "畫"
	paint.toggle_mode = true
	paint.focus_mode = Control.FOCUS_NONE
	paint.custom_minimum_size = Vector2(70, 40)
	paint.pressed.connect(func(): _ctl.set_erase(false))
	hb.add_child(paint)
	_erase_button = Button.new()
	_erase_button.text = "擦除 (X)"
	_erase_button.toggle_mode = true
	_erase_button.focus_mode = Control.FOCUS_NONE
	_erase_button.custom_minimum_size = Vector2(90, 40)
	_erase_button.pressed.connect(func(): _ctl.set_erase(true))
	hb.add_child(_erase_button)
	_erase_button.set_meta("paint", paint)
	_clear_button = Button.new()
	_clear_button.focus_mode = Control.FOCUS_NONE
	_clear_button.custom_minimum_size = Vector2(90, 40)
	_clear_button.pressed.connect(func(): _ctl.clear_brush_area())
	hb.add_child(_clear_button)
	var done := Button.new()
	done.text = "完成"
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(70, 40)
	done.pressed.connect(func(): _ctl.cancel_place())
	hb.add_child(done)
	_brush_bar.visible = false

func _refresh_brush() -> void:
	var on: bool = _ctl.is_brush()
	_brush_bar.visible = on
	if not on: return
	_erase_button.button_pressed = _ctl.erase_mode
	(_erase_button.get_meta("paint") as Button).button_pressed = not _ctl.erase_mode
	if _ctl.placing == "field":
		var f := get_node_or_null(^"../Fields")
		var n: int = f.field_of(_ctl.field_farm).size() if f else 0
		var y: int = f.yield_for(_ctl.field_farm) if f else 0
		_brush_title.text = "田地 %.0f m²  每趟 %d 食物" % [n * 0.25, y]
		_clear_button.text = "清空田地"
	else:
		_brush_title.text = "住宅區 %.0f m²" % (Game.zone_count() * 0.25)
		_clear_button.text = "全部清除"

func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.position.y = 80
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)

func _build_hint() -> void:
	_hint = _label("", 14, MUTED)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_left = 14
	_hint.offset_bottom = -96
	_hint.offset_top = -120
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 6)
	_root.add_child(_hint)

# ---------------- refresh ----------------

func _refresh() -> void:
	var fpd := Game.food_per_day()
	for r in _res_labels:
		var txt := "%s  %d" % [Defs.RESOURCES[r]["name"], Game.resources.get(r, 0)]
		if r == "food":
			txt += "  (%s%.0f/天)" % ["+" if fpd >= 0 else "", fpd]
			_res_labels[r].add_theme_color_override("font_color",
				Color(1.0, 0.45, 0.4) if (fpd < 0 or Game.starving) else Defs.RESOURCES[r]["color"].lightened(0.15))
		elif Game.income_per_day(r) > 0:
			txt += "  (+%d/天)" % Game.income_per_day(r)
		_res_labels[r].text = txt
		_res_labels[r].tooltip_text = "昨天搬進倉庫的量（扣掉食物消耗）" if r == "food" else "昨天搬進倉庫的量"
		_res_labels[r].mouse_filter = Control.MOUSE_FILTER_PASS
	_pop_label.text = "人口  %d/%d   工作 %d/%d" % [Game.population, Game.housing(), Game.workers_used(), Game.workers_needed()]
	_day_label.text = "第 %d 天" % Game.day
	for type in _build_buttons:
		var ok: bool = Defs.TOOLS.has(type) or Game.can_afford(Defs.BUILDINGS[type]["cost"])
		_build_buttons[type].modulate = Color.WHITE if ok else Color(1, 1, 1, 0.45)
	for sp in _speed_buttons:
		_speed_buttons[sp].button_pressed = is_equal_approx(Game.speed, sp)
	_refresh_quest()
	if _brush_bar: _refresh_brush()

func _refresh_quest() -> void:
	var q := Game.current_quest()
	if q.is_empty():
		_quest_title.text = "所有任務完成"
		_quest_progress.text = "自由建造你的村莊"
		_quest_reward.text = ""
		return
	_quest_title.text = q["text"]
	var p := Game.quest_progress(q)
	_quest_progress.text = "%d / %d" % [min(p.x, p.y), p.y]
	var rw: String = Defs.cost_text(q["reward"])
	_quest_reward.text = ("獎勵：" + rw) if rw != "" else ""

func _on_mode(type: String) -> void:
	for t in _build_buttons:
		_build_buttons[t].button_pressed = (t == type)
	if type == "":
		_hint.text = "左鍵 選取建築 · 1-5 建造 · 右鍵拖曳 旋轉鏡頭 · WASD / 中鍵 平移 · 滾輪 縮放"
	else:
		if type == "zone":
			_hint.text = "左鍵拖曳 畫住宅區 · X 切換擦除（或按住 Shift 拖曳）· 右鍵 / Esc 完成"
		elif type == "field":
			_hint.text = "左鍵拖曳 畫田地（離農舍 %d 公尺內）· X 切換擦除（或按住 Shift 拖曳）· 右鍵 / Esc 完成" % int(Defs.FIELD["range"])
		else:
			_hint.text = "左鍵 放置%s · R / Shift+R 或 Shift+滾輪 旋轉 · 右鍵 / Esc 取消" % Defs.BUILDINGS[type]["name"]
	_refresh_quest()
	_refresh_brush()

func _on_selection(id: int) -> void:
	_info.visible = id >= 0
	if id >= 0: _fill_info(id)

func _fill_info(id: int) -> void:
	var b := Game.get_building(id)
	if b.is_empty():
		_info.visible = false
		return
	var d: Dictionary = Defs.BUILDINGS[b["type"]]
	_info_title.text = d["name"]
	_del_button.visible = not d.get("permanent", false)
	var lines: Array[String] = [d["desc"]]
	_field_button.visible = b["type"] == "farm"
	var f := get_node_or_null(^"../Fields")
	if b["type"] == "farm" and f:
		var n: int = f.field_of(id).size()
		var y: int = f.yield_for(id)
		lines.append("田地：%.0f m²（上限 %.0f m²）" % [n * 0.25, Defs.FIELD["max_cells"] * 0.25])
		if y > 0:
			lines.append("每趟搬回：%d 食物（田越大越多，倉庫越近趟數越多）" % y)
		else:
			lines.append("田地太小，至少要 %.0f m² 才有收成" % (Defs.FIELD["min_cells"] * 0.25))
	elif d.has("yield"):
		for r in d["yield"]:
			lines.append("每趟搬回：%d %s（倉庫越近，趟數越多）" % [d["yield"][r], Defs.RESOURCES[r]["name"]])
	if d.has("yield"):
		var state := "工作中"
		if not b["staffed"]: state = "缺工人（需要更多人口）"
		elif not Game.is_active(b): state = "餓肚子，停工中"
		lines.append("狀態：" + state)
	if d.get("storage", false):
		lines.append("附近的工人會把資源搬來這裡")
	if b["type"] == "cart":
		lines.append("營火旁有 %d 個睡鋪，畫住宅區讓村民蓋房子" % d["housing"])
	if d.has("housing"):
		lines.append("提供 %d 人居住" % d["housing"])
	var vm := get_node_or_null(^"../Villagers")
	if vm and d.get("workers", 0) > 0:
		var who := "無"
		for v in vm.villagers:
			if v.job_id == id: who = "%s（%s）" % [v.vname, v.status_text()]
		lines.append("工人：" + who)
	_info_body.text = "\n".join(lines)

# ---------------- toasts ----------------

func show_toast(text: String) -> void:
	var p := _panel()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _label(text, 18, TEXT)
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := p.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

func _confirm_restart() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "確定要清除存檔、重新開始嗎？"
	dlg.ok_button_text = "重新開始"
	dlg.cancel_button_text = "取消"
	dlg.confirmed.connect(func():
		_ctl.cancel_place(); _ctl.select(-1)
		Game.delete_save(); Game.new_game()
		show_toast("新的村莊開始了"))
	dlg.canceled.connect(dlg.queue_free)
	_root.add_child(dlg)
	dlg.popup_centered()

# ---------------- theme helpers ----------------

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

func _label(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box(bg: Color, edge: Color, radius := 10, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad * 0.7; s.content_margin_bottom = pad * 0.7
	s.shadow_color = Color(0, 0, 0, 0.25); s.shadow_size = 6
	return s

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Fonts.cjk()
	t.default_font_size = 17
	t.set_stylebox("panel", "PanelContainer", _box(BG, EDGE))
	t.set_stylebox("normal", "Button", _box(BG_LIGHT, EDGE, 8, 10))
	t.set_stylebox("hover", "Button", _box(BG_LIGHT.lightened(0.12), GOLD, 8, 10))
	t.set_stylebox("pressed", "Button", _box(Color(0.45, 0.32, 0.15, 0.95), GOLD, 8, 10))
	t.set_stylebox("hover_pressed", "Button", _box(Color(0.5, 0.36, 0.17, 0.95), GOLD, 8, 10))
	t.set_stylebox("disabled", "Button", _box(BG, EDGE, 8, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	var bar_bg := StyleBoxFlat.new(); bar_bg.bg_color = Color(0, 0, 0, 0.4); bar_bg.set_corner_radius_all(3)
	var bar_fg := StyleBoxFlat.new(); bar_fg.bg_color = GOLD; bar_fg.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	t.set_stylebox("panel", "TooltipPanel", _box(BG, EDGE, 6, 8))
	return t
