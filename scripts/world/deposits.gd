class_name Deposits
extends Node3D
## Stone deposits (Defs.DEPOSITS): rock outcrops on the map. A quarry can only be built on a free
## deposit; while placing one, free deposits get a glowing ring and the ghost snaps onto them.

@export var nav_path: NodePath = ^"../Nav"
@export var scatter_path: NodePath = ^"../Scatter"

const MODELS := ["res://models/deposit_0.glb", "res://models/deposit_1.glb"]

var _rocks: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_free: StandardMaterial3D
var _ring_used: StandardMaterial3D

func _ready() -> void:
	Game.building_added.connect(_on_added)
	Game.building_removed.connect(func(_b): _face_quarries())
	Game.reset.connect(func(): call_deferred("_face_quarries"))
	call_deferred("_build")

func _build() -> void:
	var nav := get_node_or_null(nav_path)
	var scatter := get_node_or_null(scatter_path)
	_ring_free = _mat(Color(0.95, 0.85, 0.55, 0.85))
	_ring_used = _mat(Color(0.6, 0.6, 0.6, 0.35))
	for i in Defs.DEPOSITS.size():
		var d: Dictionary = Defs.DEPOSITS[i]
		var p: Vector2 = d["pos"]
		var y: float = nav.height_at(p.x, p.y) if nav else 0.0
		var rock: Node3D
		var path: String = MODELS[int(d["model"]) % MODELS.size()]
		if ResourceLoader.exists(path):
			rock = (load(path) as PackedScene).instantiate()
		else:
			rock = MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 1.1; sm.height = 1.3
			(rock as MeshInstance3D).mesh = sm
		rock.name = "Deposit%d" % i
		rock.position = Vector3(p.x, y - 0.05, p.y)
		rock.rotation.y = d["angle"]
		add_child(rock)
		_rocks.append(rock)
		if scatter and scatter.has_method("clear_area"):
			scatter.clear_area(p, Vector2(1.5, 1.5), 0.0)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.85; tm.outer_radius = 2.0; tm.rings = 48; tm.ring_segments = 6
		ring.mesh = tm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(p.x, y + 0.1, p.y)
		ring.visible = false
		add_child(ring)
		_rings.append(ring)
	_face_quarries()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m

# ---------------- queries (static: usable without the node) ----------------

## Index of the deposit centred within `tol` of p, or -1.
static func index_at(p: Vector2, tol := 0.35) -> int:
	for i in Defs.DEPOSITS.size():
		if (Defs.DEPOSITS[i]["pos"] as Vector2).distance_to(p) <= tol: return i
	return -1

## Id of the quarry built on deposit i, or -1.
static func quarry_on(i: int) -> int:
	var dp: Vector2 = Defs.DEPOSITS[i]["pos"]
	for b in Game.buildings:
		if Defs.BUILDINGS[b["type"]].get("on_deposit", false) and (b["pos"] as Vector2).distance_to(dp) < 0.5:
			return b["id"]
	return -1

## Closest deposit without a quarry within max_d of p, or -1.
static func free_near(p: Vector2, max_d: float) -> int:
	var best := -1; var best_d := max_d
	for i in Defs.DEPOSITS.size():
		var d := (Defs.DEPOSITS[i]["pos"] as Vector2).distance_to(p)
		if d <= best_d and quarry_on(i) < 0:
			best = i; best_d = d
	return best

static func free_count() -> int:
	var n := 0
	for i in Defs.DEPOSITS.size():
		if quarry_on(i) < 0: n += 1
	return n

# ---------------- visuals ----------------

## Rings around the deposits while a quarry is being placed.
func set_highlight(on: bool) -> void:
	for i in _rings.size():
		_rings[i].visible = on
		_rings[i].material_override = _ring_free if quarry_on(i) < 0 else _ring_used

func _on_added(b: Dictionary) -> void:
	if Defs.BUILDINGS[b["type"]].get("on_deposit", false):
		_face_quarries()

## A worked deposit turns its quarried face towards its quarry's work spot.
func _face_quarries() -> void:
	for i in _rocks.size():
		var q := quarry_on(i)
		var b := Game.get_building(q) if q >= 0 else {}
		_rocks[i].rotation.y = b["angle"] if not b.is_empty() else Defs.DEPOSITS[i]["angle"]
