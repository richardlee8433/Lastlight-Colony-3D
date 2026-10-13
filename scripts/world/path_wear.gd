class_name PathWear
extends Node
## Organic roads: every step a villager takes wears the ground a little.
## Worn ground turns to dirt (ground shader), grass is flattened, and path-finding
## prefers worn cells — so frequently used routes become roads. Unused roads fade.

const RES := 0.25                       # metres per wear pixel
const ORIGIN := Vector2(-17, -17)
const SIZE := 136                        # 34 m / 0.25
const SAVE_PATH := "user://paths.dat"
const GROUND_SHADER := preload("res://scripts/world/ground_path.gdshader")

@export var ground_path: NodePath = ^"../Ground"
@export var scatter_path: NodePath = ^"../Scatter"
@export var nav_path: NodePath = ^"../Nav"

var wear := PackedFloat32Array()
var _img: Image
var _tex: ImageTexture
var _dirty_tex := false
var _dirty_cells := {}                   # nav/bucket cell index -> true
var _decay_acc := 0.0
var _upload_acc := 0.0
var _cells_acc := 0.0
var _scatter: Node
var _nav: NavGrid

func _ready() -> void:
	wear.resize(SIZE * SIZE)
	_img = Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	_tex = ImageTexture.create_from_image(_img)
	_scatter = get_node_or_null(scatter_path)
	_nav = get_node_or_null(nav_path)
	_setup_ground()
	Game.reset.connect(clear)
	Game.day_passed.connect(func(_d): save())
	if FileAccess.file_exists(Game.SAVE_PATH):
		load_wear()

# ---------------- ground material ----------------

func _setup_ground() -> void:
	var g := get_node_or_null(ground_path)
	if g == null: return
	for mi in _meshes(g):
		var albedo: Texture2D = null
		var m := mi.mesh.surface_get_material(0)
		if m is StandardMaterial3D: albedo = (m as StandardMaterial3D).albedo_texture
		var sm := ShaderMaterial.new()
		sm.shader = GROUND_SHADER
		sm.set_shader_parameter("albedo_tex", albedo)
		sm.set_shader_parameter("wear_tex", _tex)
		sm.set_shader_parameter("wear_rect", Vector4(ORIGIN.x, ORIGIN.y, SIZE * RES, SIZE * RES))
		sm.set_shader_parameter("meadow_tex", Meadow.texture())
		sm.set_shader_parameter("meadow_rect", Vector4(Meadow.ORIGIN.x, Meadow.ORIGIN.y, Meadow.SIZE_M, Meadow.SIZE_M))
		var n := FastNoiseLite.new(); n.frequency = 0.05; n.fractal_octaves = 4
		var nt := NoiseTexture2D.new(); nt.noise = n; nt.seamless = true; nt.width = 256; nt.height = 256
		sm.set_shader_parameter("noise_tex", nt)
		mi.material_override = sm

func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh: out.append(n)
	for c in n.get_children(): out.append_array(_meshes(c))
	return out

# ---------------- wear ----------------

## Adds wear around a world position. amount ~ seconds of walking * rate.
func deposit(p: Vector3, amount: float) -> void:
	var fx := (p.x - ORIGIN.x) / RES
	var fz := (p.z - ORIGIN.y) / RES
	var cx := floori(fx); var cz := floori(fz)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := cx + dx; var z := cz + dz
			if x < 0 or z < 0 or x >= SIZE or z >= SIZE: continue
			var d2 := pow(x + 0.5 - fx, 2) + pow(z + 0.5 - fz, 2)
			var k := exp(-d2 / 1.6)              # ~0.3 m radius footprint
			if k < 0.05: continue
			var i := z * SIZE + x
			wear[i] = minf(1.0, wear[i] + amount * k)
			_dirty_cells[_cell_index(x, z)] = true
	_dirty_tex = true

func wear_at(p: Vector3) -> float:
	var x := floori((p.x - ORIGIN.x) / RES); var z := floori((p.z - ORIGIN.y) / RES)
	if x < 0 or z < 0 or x >= SIZE or z >= SIZE: return 0.0
	return wear[z * SIZE + x]

func max_wear() -> float:
	var m := 0.0
	for v in wear: m = maxf(m, v)
	return m

func _cell_index(px: int, pz: int) -> int:
	return (pz / 2) * (SIZE / 2) + (px / 2)        # 2x2 wear pixels per 0.5 m cell

## Advances decay and pushes changes to the texture, grass and path costs. dt = game seconds.
func tick(dt: float, real_dt: float) -> void:
	_decay_acc += dt
	if _decay_acc >= 1.0:
		var dec := float(Defs.PATHS["decay"]) * _decay_acc
		_decay_acc = 0.0
		for i in wear.size():
			if wear[i] > 0.0:
				wear[i] = maxf(0.0, wear[i] - dec)
				_dirty_cells[_cell_index(i % SIZE, i / SIZE)] = true
		_dirty_tex = true
	_upload_acc += real_dt
	if _dirty_tex and _upload_acc >= 0.15:
		_upload_acc = 0.0
		_upload()
	_cells_acc += real_dt
	if _cells_acc >= 0.4 and not _dirty_cells.is_empty():
		_cells_acc = 0.0
		_update_cells()

func _process(delta: float) -> void:
	tick(delta * Game.speed, delta)

func _upload() -> void:
	_dirty_tex = false
	var bytes := PackedByteArray(); bytes.resize(wear.size())
	for i in wear.size():
		bytes[i] = int(wear[i] * 255.0)
	_img.set_data(SIZE, SIZE, false, Image.FORMAT_L8, bytes)
	_tex.update(_img)

func _update_cells() -> void:
	var t0: float = Defs.PATHS["trample_start"]; var t1: float = Defs.PATHS["trample_full"]
	var road: float = Defs.PATHS["road_weight"]
	var half := SIZE / 2
	for ci in _dirty_cells:
		var cx: int = ci % half; var cz: int = ci / half
		var px := cx * 2; var pz := cz * 2
		var v := (wear[pz * SIZE + px] + wear[pz * SIZE + px + 1] + wear[(pz + 1) * SIZE + px] + wear[(pz + 1) * SIZE + px + 1]) * 0.25
		var t := clampf((v - t0) / (t1 - t0), 0.0, 1.0)
		if _scatter: _scatter.set_trample(ci, 1.0 - t)
		if _nav: _nav.set_cell_weight(Vector2i(cx, cz), lerpf(1.0, road, clampf(v / t1, 0.0, 1.0)))
	_dirty_cells.clear()

# ---------------- persistence ----------------

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	var bytes := PackedByteArray(); bytes.resize(wear.size())
	for i in wear.size(): bytes[i] = int(wear[i] * 255.0)
	f.store_buffer(bytes)

func load_wear() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var bytes := FileAccess.get_file_as_bytes(SAVE_PATH)
	if bytes.size() != wear.size(): return
	for i in wear.size():
		wear[i] = bytes[i] / 255.0
		if wear[i] > 0.0: _dirty_cells[_cell_index(i % SIZE, i / SIZE)] = true
	_upload()
	call_deferred("_update_cells")

func clear() -> void:
	wear.fill(0.0)
	for i in (SIZE / 2) * (SIZE / 2): _dirty_cells[i] = true
	_upload()
	_update_cells()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
