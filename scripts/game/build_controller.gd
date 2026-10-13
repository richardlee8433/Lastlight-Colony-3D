extends Node3D
## World side of building: free placement (any position, any angle), placement ghost,
## building nodes, selection, delivery pop-ups.

signal mode_changed(type: String)        # "" when not placing
signal selection_changed(id: int)        # -1 when nothing selected
signal brush_changed                     # erase toggle / field farm changed

const ROTATE_STEP := PI / 12.0           # 15°

@export var camera_path: NodePath = ^"../Camera"
@export var scatter_path: NodePath = ^"../Scatter"
@export var nav_path: NodePath = ^"../Nav"
@export var zones_path: NodePath = ^"../Zones"
@export var fields_path: NodePath = ^"../Fields"
@export var forest_path: NodePath = ^"../Forest"
@export var deposits_path: NodePath = ^"../Deposits"

var placing := ""
var ghost_angle := 0.0
var selected := -1

var _nodes := {}              # building id -> Node3D
var _ghost: Node3D
var _ghost_pad: MeshInstance3D
var _ghost_pos := Vector2.ZERO
var _ghost_ok := false
var _select_pad: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _ghost_mat: StandardMaterial3D
var _brush: MeshInstance3D
var _brush_mat: StandardMaterial3D
var _painting := 0                     # 0 none, 1 painting, -1 erasing
## brush modes: placing == "zone" (residential), "field" (farm `area_owner`'s field)
## or "forest" (woodcutter `area_owner`'s forest area)
var erase_mode := false                # erase toggle (Shift inverts it while held)
var area_owner := -1

@onready var _cam: Camera3D = get_node(camera_path)
@onready var _scatter: Node = get_node_or_null(scatter_path)
@onready var _nav: Node = get_node_or_null(nav_path)

func _ready() -> void:
	_ok_mat = _pad_mat(Color(0.35, 0.95, 0.4, 0.35))
	_bad_mat = _pad_mat(Color(1.0, 0.25, 0.2, 0.4))
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.45)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select_pad = _make_pad(_pad_mat(Color(1.0, 0.85, 0.3, 0.45)))
	_select_pad.visible = false
	Game.building_added.connect(_on_added)
	Game.building_removed.connect(_on_removed)
	Game.delivered.connect(_on_delivered)
	Game.changed.connect(_refresh_status)
	# scatter and nav finish loading in their own _ready, which runs after ours
	call_deferred("_spawn_existing")

func _spawn_existing() -> void:
	for b in Game.buildings:
		_on_added(b, false)
	_refresh_status()

# ---------------- placement rules ----------------

## Why a building can't go here ("" = it can).
func place_problem(type: String, pos: Vector2, angle: float) -> String:
	var quad := Defs.footprint_corners(type, pos, angle)
	for c in quad:
		if not Defs.BUILD_BOUNDS.has_point(c): return Loc.t("out of bounds")
	var on_deposit: bool = Defs.BUILDINGS[type].get("on_deposit", false)
	var dep := -1
	if on_deposit:
		dep = Deposits.index_at(pos)
		if dep < 0: return Loc.t("must be built on a stone deposit")
		if Deposits.quarry_on(dep) >= 0: return Loc.t("this deposit already has a quarry")
	for r in Defs.NO_BUILD:
		var rr: Rect2 = r
		var rq := PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)])
		if Defs.quads_overlap(quad, rq): return Loc.t("too close to the village centre")
	var grown := Defs.footprint_corners(type, pos, angle, Defs.BUILD_GAP)
	for b in Game.buildings:
		if Defs.quads_overlap(grown, Defs.footprint_corners(b["type"], b["pos"], b["angle"])):
			return Loc.t("overlaps another building")
	if _nav and dep >= 0:
		# a quarry only needs room for its props (crane, bench, blocks, sledge) and the work spot around its rock
		var spots: Array[Vector2] = [Defs.BUILDINGS[type].get("work_spot", Vector2.ZERO)]
		for r in Defs.BUILDINGS[type].get("nav_block", []):
			var rr: Rect2 = r
			for i in 3:
				for j in 3:
					spots.append(rr.position + rr.size * Vector2(i / 2.0, j / 2.0))
		for l in spots:
			if l.length() <= Defs.DEPOSIT["radius"] + 0.5: continue          # its own rock
			if _nav.scenery_at(pos + Defs.rot2(l, angle)): return Loc.t("trees or obstacles in the way")
	elif _nav:
		var h := Defs.half_extents(type)
		var nx := maxi(2, ceili(h.x * 2 / 0.4)); var nz := maxi(2, ceili(h.y * 2 / 0.4))
		for i in nx + 1:
			for j in nz + 1:
				var l := Vector2(-h.x + 2 * h.x * i / nx, -h.y + 2 * h.y * j / nz)
				if _nav.scenery_at(pos + Defs.rot2(l, angle)): return Loc.t("trees or obstacles in the way")
	var f := _fields()
	if f:
		var h := Defs.half_extents(type)
		var nx := maxi(2, ceili(h.x * 2 / 0.4)); var nz := maxi(2, ceili(h.y * 2 / 0.4))
		for i in nx + 1:
			for j in nz + 1:
				var l := Vector2(-h.x + 2 * h.x * i / nx, -h.y + 2 * h.y * j / nz) * 0.9
				if f.is_field(pos + Defs.rot2(l, angle)): return Loc.t("that's a farm field")
	var fo := _forest()
	if fo:
		var h := Defs.half_extents(type)
		var nx := maxi(2, ceili(h.x * 2 / 0.4)); var nz := maxi(2, ceili(h.y * 2 / 0.4))
		for i in nx + 1:
			for j in nz + 1:
				var l := Vector2(-h.x + 2 * h.x * i / nx, -h.y + 2 * h.y * j / nz) * 0.9
				if fo.is_area(pos + Defs.rot2(l, angle)): return Loc.t("that's a forest area")
	return ""

func can_place(type: String, pos: Vector2, angle := 0.0) -> bool:
	return place_problem(type, pos, angle) == ""

func building_at_point(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for b in Game.buildings:
		var l := Defs.to_local(b, q)
		var h := Defs.half_extents(b["type"])
		if absf(l.x) <= h.x and absf(l.y) <= h.y: return b["id"]
	return -1

## Places a building through Game (pays the cost). Returns the id or -1.
func try_place(type: String, pos: Vector2, angle := 0.0) -> int:
	var why := place_problem(type, pos, angle)
	if why != "":
		Game.toast.emit(Loc.t("Can't build here: ") + why)
		return -1
	var b := Game.add_building(type, pos, angle)
	return -1 if b.is_empty() else int(b["id"])

func ground_height(type: String, pos: Vector2, angle: float) -> float:
	if _nav == null: return 0.0
	var h := Defs.half_extents(type) * 0.8
	var sum := 0.0
	for l in [Vector2.ZERO, Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		var w: Vector2 = pos + Defs.rot2(l, angle)
		sum += _nav.height_at(w.x, w.y)
	return sum / 5.0

func _world_pos(b: Dictionary) -> Vector3:
	return Vector3(b["pos"].x, ground_height(b["type"], b["pos"], b["angle"]), b["pos"].y)

# ---------------- placing mode ----------------

func begin_place(type: String) -> void:
	cancel_place()
	select(-1)
	if type == "zone":
		_begin_brush("zone")
		return
	placing = type
	if Defs.BUILDINGS[type].get("on_deposit", false):
		var dn := get_node_or_null(deposits_path)
		if dn: dn.set_highlight(true)
		if Deposits.free_count() == 0:
			Game.toast.emit(Loc.t("Every stone deposit already has a quarry"))
	_ghost = BuildingVisuals.create(type, 1)
	BuildingVisuals.override_all(_ghost, _ghost_mat)
	add_child(_ghost)
	_ghost_pad = _make_pad(_ok_mat)
	var h := Defs.half_extents(type) * 2.0
	(_ghost_pad.mesh as PlaneMesh).size = h
	_update_ghost(get_viewport().get_mouse_position())
	mode_changed.emit(type)

func cancel_place() -> void:
	if placing == "": return
	if is_brush():
		_end_brush()
	var dn := get_node_or_null(deposits_path)
	if dn: dn.set_highlight(false)
	placing = ""
	if _ghost: _ghost.queue_free()
	if _ghost_pad: _ghost_pad.queue_free()
	_ghost = null; _ghost_pad = null
	mode_changed.emit("")

# ---------------- area brushes (residential zone / farm field) ----------------

func _zones() -> Node:
	return get_node_or_null(zones_path)

func _fields() -> Node:
	return get_node_or_null(fields_path)

func _forest() -> Node:
	return get_node_or_null(forest_path)

func is_brush() -> bool:
	return placing == "zone" or placing == "field" or placing == "forest"

## Paint / erase the field of a farmhouse.
func begin_field(farm_id: int) -> void:
	var b := Game.get_building(farm_id)
	if b.is_empty() or b["type"] != "farm": return
	cancel_place()
	select(-1)
	area_owner = farm_id
	_begin_brush("field")

## Paint / erase the forest area of a woodcutter's lodge.
func begin_forest(lodge_id: int) -> void:
	var b := Game.get_building(lodge_id)
	if b.is_empty() or b["type"] != "woodcutter": return
	cancel_place()
	select(-1)
	area_owner = lodge_id
	_begin_brush("forest")

func _begin_brush(kind: String) -> void:
	placing = kind
	_painting = 0
	erase_mode = false
	if _brush == null:
		var tm := TorusMesh.new()
		var r: float = Defs.ZONE["brush_radius"]
		tm.inner_radius = r - 0.06; tm.outer_radius = r + 0.06
		tm.rings = 48; tm.ring_segments = 6
		_brush = MeshInstance3D.new()
		_brush.mesh = tm
		_brush_mat = _pad_mat(Color(1.0, 0.92, 0.6, 0.85))
		_brush.material_override = _brush_mat
		_brush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_brush)
	_brush.visible = true
	if kind == "zone" and _zones(): _zones().set_painting(true)
	if kind == "field" and _fields(): _fields().set_editing(area_owner)
	if kind == "forest" and _forest(): _forest().set_editing(area_owner)
	_update_brush(get_viewport().get_mouse_position())
	mode_changed.emit(kind)
	brush_changed.emit()

func _end_brush() -> void:
	_painting = 0
	if _brush: _brush.visible = false
	if _zones(): _zones().set_painting(false)
	if _fields(): _fields().set_editing(-1)
	if _forest(): _forest().set_editing(-1)
	area_owner = -1

## true when the brush currently erases (toggle, inverted while Shift is held)
func erasing() -> bool:
	return erase_mode != Input.is_key_pressed(KEY_SHIFT)

func set_erase(on: bool) -> void:
	erase_mode = on
	_update_brush(get_viewport().get_mouse_position())
	brush_changed.emit()

## Paint or erase at a world point with the active brush (tests call this too).
func brush_at(p: Vector2, on: bool) -> int:
	if placing == "zone" and _zones():
		return _zones().paint(p, on)
	if placing == "field" and _fields():
		return _fields().paint(area_owner, p, on)
	if placing == "forest" and _forest():
		return _forest().paint(area_owner, p, on)
	return 0

## Clears the whole area of the active brush: this farm's field, or every residential zone.
func clear_brush_area() -> void:
	if placing == "field" and _fields():
		_fields().clear(area_owner)
		Game.toast.emit(Loc.t("Field cleared"))
	elif placing == "forest" and _forest():
		_forest().clear(area_owner)
		Game.toast.emit(Loc.t("Area cleared"))
	elif placing == "zone":
		Game._clear_zones()
		Game.toast.emit(Loc.t("All housing zones cleared (built houses stay)"))

func _update_brush(mouse: Vector2) -> void:
	if _brush == null: return
	var p = _ground_point(mouse)
	if p == null: return
	_brush.position = p + Vector3(0, 0.08, 0)
	var er := erasing()
	if placing == "field":
		_brush_mat.albedo_color = Color(1.0, 0.45, 0.35, 0.85) if er else Color(0.95, 0.75, 0.35, 0.9)
	elif placing == "forest":
		_brush_mat.albedo_color = Color(1.0, 0.45, 0.35, 0.85) if er else Color(0.55, 0.95, 0.45, 0.9)
	else:
		_brush_mat.albedo_color = Color(1.0, 0.45, 0.35, 0.85) if er else Color(1.0, 0.92, 0.6, 0.85)
	if _painting != 0:
		brush_at(Vector2(p.x, p.z), not er)

func _update_ghost(mouse: Vector2) -> void:
	if is_brush():
		_update_brush(mouse)
		return
	if placing == "" or _ghost == null: return
	var p = _ground_point(mouse)
	if p != null:
		_ghost_pos = Vector2(p.x, p.z)
		if Defs.BUILDINGS[placing].get("on_deposit", false):
			# quarries snap onto the nearest free stone deposit
			var d := Deposits.free_near(_ghost_pos, Defs.DEPOSIT["snap"])
			if d >= 0: _ghost_pos = Defs.DEPOSITS[d]["pos"]
	_ghost_ok = can_place(placing, _ghost_pos, ghost_angle) and Game.can_afford(Defs.BUILDINGS[placing]["cost"])
	var y := ground_height(placing, _ghost_pos, ghost_angle)
	_ghost.position = Vector3(_ghost_pos.x, y, _ghost_pos.y)
	_ghost.rotation.y = ghost_angle
	_ghost_pad.position = _ghost.position + Vector3(0, 0.06, 0)
	_ghost_pad.rotation.y = ghost_angle
	_ghost_pad.material_override = _ok_mat if _ghost_ok else _bad_mat

func _rotate_ghost(steps: int) -> void:
	ghost_angle = wrapf(ghost_angle + steps * ROTATE_STEP, -PI, PI)
	_update_ghost(get_viewport().get_mouse_position())

# ---------------- selection ----------------

func select(id: int) -> void:
	selected = id
	var b := Game.get_building(id) if id >= 0 else {}
	if b.is_empty() or not _nodes.has(id):
		selected = -1
		_select_pad.visible = false
	else:
		var h := Defs.half_extents(b["type"]) * 2.0 + Vector2(0.2, 0.2)
		(_select_pad.mesh as PlaneMesh).size = h
		_select_pad.position = _world_pos(b) + Vector3(0, 0.07, 0)
		_select_pad.rotation.y = b["angle"]
		_select_pad.visible = true
	selection_changed.emit(selected)

func demolish_selected() -> void:
	if selected >= 0:
		var id := selected
		select(-1)
		Game.demolish(id)

# ---------------- input ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SHIFT and is_brush():
		_update_brush(get_viewport().get_mouse_position())     # press and release recolour the brush
	if is_brush() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = 1 if event.pressed else 0
		_update_brush(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_update_ghost(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if placing != "" and event.shift_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_rotate_ghost(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if placing != "":
				_update_ghost(event.position)
				var id := try_place(placing, _ghost_pos, ghost_angle)
				if id >= 0:
					if placing == "farm":
						# Foundation-style: right after the farmhouse, shape its field
						begin_field(id)
						Game.toast.emit(Loc.t("A starter field is ready. Drag to grow it; X or Shift to erase"))
					elif placing == "woodcutter":
						begin_forest(id)
						var fo := _forest()
						if fo and fo.counts(id)["ready"] == 0:
							Game.toast.emit(Loc.t("No trees here yet. Saplings will sprout in the area, or paint it over a forest"))
						else:
							Game.toast.emit(Loc.t("A forest area is ready. Drag to grow it; X or Shift to erase"))
					else:
						_update_ghost(event.position)
						if not Game.can_afford(Defs.BUILDINGS[placing]["cost"]):
							cancel_place()
				get_viewport().set_input_as_handled()
			else:
				var p = _ground_point(event.position)
				select(building_at_point(p) if p != null else -1)
		elif event.button_index == MOUSE_BUTTON_RIGHT and placing != "":
			cancel_place()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_X and is_brush() and not event.echo:
			set_erase(not erase_mode)
			return
		if event.keycode == KEY_R:
			_rotate_ghost(-1 if event.shift_pressed else 1)
			return
		if event.echo: return
		match event.keycode:
			KEY_ESCAPE, KEY_ENTER:
				if placing != "": cancel_place()
				else: select(-1)
			KEY_DELETE, KEY_BACKSPACE:
				demolish_selected()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var i: int = event.keycode - KEY_1
				if i < Defs.BUILD_ORDER.size(): begin_place(Defs.BUILD_ORDER[i])

func _ground_point(mouse: Vector2) -> Variant:
	var o := _cam.project_ray_origin(mouse)
	var d := _cam.project_ray_normal(mouse)
	if absf(d.y) < 1e-4: return null
	var t := -o.y / d.y
	if t < 0: return null
	var p := o + d * t
	# one refinement step against the actual terrain height
	if _nav:
		var hgt: float = _nav.height_at(p.x, p.z)
		t = (hgt - o.y) / d.y
		if t > 0: p = o + d * t
	return p

# ---------------- building nodes ----------------

func _on_added(b: Dictionary, animate := true) -> void:
	var type: String = b["type"]
	var node := Node3D.new()
	node.name = "B%d_%s" % [b["id"], type]
	var vis := BuildingVisuals.create(type, int(b["id"]) * 7919)
	vis.rotation.y = b["angle"]
	node.add_child(vis)
	var status := Label3D.new()
	status.name = "Status"
	status.font = Fonts.cjk()
	status.font_size = 64
	status.pixel_size = 0.004
	status.outline_size = 14
	status.modulate = Color(1.0, 0.85, 0.35)
	status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status.no_depth_test = true
	status.position = Vector3(0, 2.8, 0)
	status.visible = false
	node.add_child(status)
	node.position = _world_pos(b)
	add_child(node)
	_nodes[b["id"]] = node
	if _scatter and _scatter.has_method("clear_area"):
		_scatter.clear_area(b["pos"], Defs.half_extents(type) + Vector2(0.15, 0.15), b["angle"])
	if animate:
		node.scale = Vector3(1, 0.05, 1)
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_status()

func _on_removed(b: Dictionary) -> void:
	var id: int = b["id"]
	if _scatter and _scatter.has_method("restore_area"):
		_scatter.restore_area(b["pos"], Defs.half_extents(b["type"]) + Vector2(0.15, 0.15), b["angle"])
	if _nodes.has(id):
		var n: Node3D = _nodes[id]
		_nodes.erase(id)
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector3(1, 0.02, 1), 0.25)
		tw.tween_callback(n.queue_free)
	if selected == id: select(-1)

func _refresh_status() -> void:
	for b in Game.buildings:
		if not _nodes.has(b["id"]): continue
		var lbl: Label3D = _nodes[b["id"]].get_node("Status")
		var d: Dictionary = Defs.BUILDINGS[b["type"]]
		if d.get("workers", 0) > 0 and not b["staffed"]:
			lbl.text = Loc.t("No worker"); lbl.visible = true
		elif d.get("workers", 0) > 0 and not Game.is_active(b):
			lbl.text = Loc.t("Hungry"); lbl.visible = true
		else:
			lbl.visible = false
	if placing != "":
		_update_ghost(get_viewport().get_mouse_position())

func _on_delivered(res: String, amount: int, at: Vector2) -> void:
	if not is_inside_tree(): return
	var lbl := Label3D.new()
	lbl.font = Fonts.cjk()
	lbl.text = "+%d %s" % [amount, Defs.res_name(res)]
	lbl.font_size = 56
	lbl.pixel_size = 0.004
	lbl.outline_size = 12
	lbl.modulate = Defs.RESOURCES[res]["color"].lightened(0.25)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	var y: float = _nav.height_at(at.x, at.y) if _nav else 0.0
	lbl.position = Vector3(at.x, y + 1.9, at.y)
	add_child(lbl)
	var tw := create_tween().set_parallel()
	tw.tween_property(lbl, "position:y", lbl.position.y + 1.2, 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.3).set_delay(0.4)
	tw.chain().tween_callback(lbl.queue_free)

# ---------------- helpers ----------------

func _pad_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _make_pad(m: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(3, 3)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
