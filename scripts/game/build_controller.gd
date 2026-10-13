extends Node3D
## World side of the game: grid & occupancy, placement ghost, building nodes, selection.

signal mode_changed(type: String)        # "" when not placing
signal selection_changed(id: int)        # -1 when nothing selected

const CELL := 1.0
const GRID_MIN := -15                    # cells, inclusive
const GRID_MAX := 15                     # cells, exclusive

@export var camera_path: NodePath = ^"../Camera"
@export var scatter_path: NodePath = ^"../Scatter"
@export var blocker_paths: Array[NodePath] = [^"../Hut", ^"../Props", ^"../Nature"]
@export var ground_path: NodePath = ^"../Ground"

var placing := ""
var ghost_rot := 0
var selected := -1

var _blocked := {}            # Vector2i -> true  (scenery)
var _occupied := {}           # Vector2i -> building id
var _height := {}             # Vector2i -> ground height
var _nodes := {}              # building id -> Node3D
var _ghost: Node3D
var _ghost_pad: MeshInstance3D
var _ghost_cell := Vector2i(999, 999)
var _ghost_ok := false
var _select_pad: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _ghost_mat: StandardMaterial3D

@onready var _cam: Camera3D = get_node(camera_path)
@onready var _scatter: Node = get_node_or_null(scatter_path)

func _ready() -> void:
	_ok_mat = _pad_mat(Color(0.35, 0.95, 0.4, 0.35))
	_bad_mat = _pad_mat(Color(1.0, 0.25, 0.2, 0.4))
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.45)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select_pad = _make_pad(_pad_mat(Color(1.0, 0.85, 0.3, 0.45)))
	_select_pad.visible = false
	_scan_scenery()
	_scan_ground()
	Game.building_added.connect(_on_added)
	Game.building_removed.connect(_on_removed)
	Game.produced.connect(_on_produced)
	Game.changed.connect(_refresh_status)
	# scatter builds its multimeshes in its own _ready, which may run after ours
	call_deferred("_spawn_existing")

func _spawn_existing() -> void:
	for b in Game.buildings:
		_on_added(b, false)
	_refresh_status()

# ---------------- grid ----------------

func cells_of(type: String, cell: Vector2i) -> Array[Vector2i]:
	var s: int = Defs.BUILDINGS[type]["size"]
	var out: Array[Vector2i] = []
	for dx in s:
		for dz in s:
			out.append(cell + Vector2i(dx, dz))
	return out

## Grid cell whose footprint is centred under a world point.
func cell_for_point(type: String, p: Vector3) -> Vector2i:
	var s: int = Defs.BUILDINGS[type]["size"]
	return Vector2i(floori(p.x / CELL - s / 2.0 + 0.5), floori(p.z / CELL - s / 2.0 + 0.5))

func center_of(type: String, cell: Vector2i) -> Vector3:
	var s: int = Defs.BUILDINGS[type]["size"]
	var c := Vector2(cell.x + s / 2.0, cell.y + s / 2.0) * CELL
	return Vector3(c.x, _footprint_height(type, cell), c.y)

func rect_of(type: String, cell: Vector2i) -> Rect2:
	var s: int = Defs.BUILDINGS[type]["size"]
	return Rect2(Vector2(cell) * CELL, Vector2(s, s) * CELL)

func can_place(type: String, cell: Vector2i) -> bool:
	for c in cells_of(type, cell):
		if c.x < GRID_MIN or c.y < GRID_MIN or c.x >= GRID_MAX or c.y >= GRID_MAX: return false
		if _blocked.has(c) or _occupied.has(c): return false
	return true

func building_at_point(p: Vector3) -> int:
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	return int(_occupied.get(c, -1))

## Places a building through Game (pays the cost). Returns the id or -1.
func try_place(type: String, cell: Vector2i, rot := 0) -> int:
	if not can_place(type, cell):
		Game.toast.emit("這裡不能蓋")
		return -1
	var b := Game.add_building(type, cell, rot)
	return -1 if b.is_empty() else int(b["id"])

func _footprint_height(type: String, cell: Vector2i) -> float:
	var h := 0.0; var n := 0
	for c in cells_of(type, cell):
		if _height.has(c):
			h += _height[c]; n += 1
	return h / n if n > 0 else 0.0

## Marks grid cells covered by scenery meshes (cottage, props, trees, rocks) as blocked.
func _scan_scenery() -> void:
	for path in blocker_paths:
		var n := get_node_or_null(path)
		if n == null: continue
		var is_nature := String(path).ends_with("Nature")
		var min_y := 0.25 if is_nature else -10.0
		var max_y := 2.4 if is_nature else 100.0   # canopy above roof height doesn't block
		for mi in _meshes(n):
			var xf := mi.global_transform
			for s in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in verts:
					var w := xf * v
					if w.y < min_y or w.y > max_y: continue
					_blocked[Vector2i(floori(w.x / CELL), floori(w.z / CELL))] = true

func _scan_ground() -> void:
	var n := get_node_or_null(ground_path)
	if n == null: return
	var sum := {}; var cnt := {}
	for mi in _meshes(n):
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w := xf * v
				var c := Vector2i(floori(w.x / CELL), floori(w.z / CELL))
				sum[c] = sum.get(c, 0.0) + w.y
				cnt[c] = cnt.get(c, 0) + 1
	for c in sum:
		_height[c] = sum[c] / cnt[c]

func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

# ---------------- placing mode ----------------

func begin_place(type: String) -> void:
	cancel_place()
	select(-1)
	placing = type
	_ghost = BuildingVisuals.create(type, 1)
	BuildingVisuals.override_all(_ghost, _ghost_mat)
	_ghost.rotation.y = ghost_rot * PI / 2
	add_child(_ghost)
	_ghost_pad = _make_pad(_ok_mat)
	var s: float = Defs.BUILDINGS[type]["size"] * CELL
	(_ghost_pad.mesh as PlaneMesh).size = Vector2(s, s)
	_ghost_cell = Vector2i(999, 999)
	_update_ghost(get_viewport().get_mouse_position())
	mode_changed.emit(type)

func cancel_place() -> void:
	if placing == "": return
	placing = ""
	if _ghost: _ghost.queue_free()
	if _ghost_pad: _ghost_pad.queue_free()
	_ghost = null; _ghost_pad = null
	mode_changed.emit("")

func _update_ghost(mouse: Vector2) -> void:
	if placing == "" or _ghost == null: return
	var p = _ground_point(mouse)
	if p == null: return
	var cell := cell_for_point(placing, p)
	_ghost_cell = cell
	_ghost_ok = can_place(placing, cell) and Game.can_afford(Defs.BUILDINGS[placing]["cost"])
	var c := center_of(placing, cell)
	_ghost.position = c
	_ghost_pad.position = c + Vector3(0, 0.06, 0)
	_ghost_pad.material_override = _ok_mat if _ghost_ok else _bad_mat

# ---------------- selection ----------------

func select(id: int) -> void:
	selected = id
	if id < 0 or not _nodes.has(id):
		selected = -1
		_select_pad.visible = false
	else:
		var b := Game.get_building(id)
		var s: float = Defs.BUILDINGS[b["type"]]["size"] * CELL
		(_select_pad.mesh as PlaneMesh).size = Vector2(s + 0.2, s + 0.2)
		_select_pad.position = center_of(b["type"], b["cell"]) + Vector3(0, 0.07, 0)
		_select_pad.visible = true
	selection_changed.emit(selected)

func demolish_selected() -> void:
	if selected >= 0:
		var id := selected
		select(-1)
		Game.demolish(id)

# ---------------- input ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_ghost(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if placing != "":
				var p = _ground_point(event.position)
				if p != null:
					var id := try_place(placing, cell_for_point(placing, p), ghost_rot)
					if id >= 0:
						_ghost_cell = Vector2i(999, 999)
						_update_ghost(event.position)
						if not Game.can_afford(Defs.BUILDINGS[placing]["cost"]):
							cancel_place()
				get_viewport().set_input_as_handled()
			else:
				var p = _ground_point(event.position)
				select(building_at_point(p) if p != null else -1)
		elif event.button_index == MOUSE_BUTTON_RIGHT and placing != "":
			cancel_place()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if placing != "": cancel_place()
				else: select(-1)
			KEY_R:
				ghost_rot = (ghost_rot + 1) % 4
				if _ghost: _ghost.rotation.y = ghost_rot * PI / 2
			KEY_DELETE, KEY_BACKSPACE:
				demolish_selected()
			KEY_1, KEY_2, KEY_3, KEY_4:
				var i: int = event.keycode - KEY_1
				if i < Defs.BUILD_ORDER.size(): begin_place(Defs.BUILD_ORDER[i])

func _ground_point(mouse: Vector2) -> Variant:
	var o := _cam.project_ray_origin(mouse)
	var d := _cam.project_ray_normal(mouse)
	if absf(d.y) < 1e-4: return null
	var t := -o.y / d.y
	if t < 0: return null
	return o + d * t

# ---------------- building nodes ----------------

func _on_added(b: Dictionary, animate := true) -> void:
	var type: String = b["type"]
	var node := Node3D.new()
	node.name = "B%d_%s" % [b["id"], type]
	var vis := BuildingVisuals.create(type, int(b["id"]) * 7919)
	vis.rotation.y = int(b["rot"]) * PI / 2
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
	node.position = center_of(type, b["cell"])
	add_child(node)
	_nodes[b["id"]] = node
	for c in cells_of(type, b["cell"]):
		_occupied[c] = b["id"]
	if _scatter and _scatter.has_method("clear_rect"):
		_scatter.clear_rect(rect_of(type, b["cell"]).grow(0.15))
	if animate:
		node.scale = Vector3(1, 0.05, 1)
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_status()

func _on_removed(b: Dictionary) -> void:
	var id: int = b["id"]
	for c in cells_of(b["type"], b["cell"]):
		_occupied.erase(c)
	if _scatter and _scatter.has_method("restore_rect"):
		_scatter.restore_rect(rect_of(b["type"], b["cell"]).grow(0.15))
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
			lbl.text = "缺工人"; lbl.visible = true
		elif d.has("produces") and Game.starving:
			lbl.text = "餓肚子"; lbl.visible = true
		else:
			lbl.visible = false
	if placing != "":
		_ghost_cell = Vector2i(999, 999)
		_update_ghost(get_viewport().get_mouse_position())

func _on_produced(id: int, res: String, amount: int) -> void:
	if not _nodes.has(id): return
	var lbl := Label3D.new()
	lbl.font = Fonts.cjk()
	lbl.text = "+%d %s" % [amount, Defs.RESOURCES[res]["name"]]
	lbl.font_size = 56
	lbl.pixel_size = 0.004
	lbl.outline_size = 12
	lbl.modulate = Defs.RESOURCES[res]["color"].lightened(0.25)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = _nodes[id].position + Vector3(0, 2.2, 0)
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
	m.no_depth_test = false
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
