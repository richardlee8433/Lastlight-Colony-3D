class_name Utilities
extends Node3D
## The colony's utility lines: finished buildings are linked by elevated pipe runs on slim trestles,
## like the pipe networks between domes in Surviving Mars. Purely visual — they are routed high enough
## for colonists to walk underneath and never block walking or building.
## The network is a minimum spanning tree over the finished buildings (shortest links first); a link is
## skipped when it would pass through another building or run longer than MAX_LINK.

const MAX_LINK := 16.0          # metres
const HEIGHT := 1.6             # pipe height above the ground (colonists are ~1.3 m tall)
const SUPPORT_EVERY := 2.6      # metres between trestles
const LAMP_EVERY := 3           # every n-th trestle carries a small marker light

@export var nav_path: NodePath = ^"../Nav"

var links: Array = []           # [[id_a, id_b], ...] of the current network (tests)
var _sig := ""
var _mats := {}

func _ready() -> void:
	Game.building_completed.connect(func(_b): _refresh())
	Game.building_removed.connect(func(_b): _refresh.call_deferred())
	Game.changed.connect(_refresh)
	Game.reset.connect(_refresh.call_deferred)
	_refresh.call_deferred()

func _mat(key: String) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		match key:
			"pipe": m.albedo_color = Color(0.86, 0.86, 0.84); m.roughness = 0.35; m.metallic = 0.2
			"accent": m.albedo_color = Color(0.86, 0.56, 0.70); m.roughness = 0.45
			"support": m.albedo_color = Color(0.32, 0.33, 0.36); m.roughness = 0.6; m.metallic = 0.4
			"collar": m.albedo_color = Color(0.20, 0.21, 0.23); m.roughness = 0.5
		_mats[key] = m
	return _mats[key]

## Rebuild when the set of finished buildings changes.
func _refresh() -> void:
	var ids: Array = []
	for b in Game.buildings:
		if Game.is_built(b): ids.append("%d@%.1f,%.1f" % [b["id"], b["pos"].x, b["pos"].y])
	var sig := ",".join(ids)
	if sig == _sig: return
	_sig = sig
	rebuild()

func rebuild() -> void:
	for c in get_children(): c.queue_free()
	links.clear()
	var built: Array = []
	for b in Game.buildings:
		if Game.is_built(b): built.append(b)
	if built.size() < 2: return
	# Prim's minimum spanning tree with blocked links left out
	var in_tree := {built[0]["id"]: true}
	var guard := 0
	while in_tree.size() < built.size() and guard < 400:
		guard += 1
		var best_d := INF; var best: Array = []
		for a in built:
			if not in_tree.has(a["id"]): continue
			for b in built:
				if in_tree.has(b["id"]): continue
				var d: float = (a["pos"] as Vector2).distance_to(b["pos"])
				if d < best_d and d <= MAX_LINK and _clear(a, b, built):
					best_d = d; best = [a, b]
		if best.is_empty(): break                       # the rest are too far away or walled off
		in_tree[best[1]["id"]] = true
		links.append([best[0]["id"], best[1]["id"]])
		_build_link(best[0], best[1])

## Edge point of building b's footprint facing point p (world x, z).
static func edge_point(b: Dictionary, p: Vector2) -> Vector2:
	var h := Defs.half_extents(b["type"]) * 0.82
	var l := Defs.to_local(b, p)
	if l.length() < 0.01: return b["pos"]
	var k := 1.0 / maxf(absf(l.x) / h.x, absf(l.y) / h.y)
	return Defs.to_world(b, l * k)

func _clear(a: Dictionary, b: Dictionary, built: Array) -> bool:
	var p0 := edge_point(a, b["pos"]); var p1 := edge_point(b, a["pos"])
	var n := int(p0.distance_to(p1) / 0.5) + 1
	for o in Game.buildings:
		if o["id"] == a["id"] or o["id"] == b["id"]: continue
		var h := Defs.half_extents(o["type"]) + Vector2(0.4, 0.4)
		for i in n + 1:
			var q := p0.lerp(p1, float(i) / n)
			var l := Defs.to_local(o, q)
			if absf(l.x) < h.x and absf(l.y) < h.y: return false
	return true

func _ground(p: Vector2) -> float:
	var nav := get_node_or_null(nav_path)
	return nav.height_at(p.x, p.y) if nav else 0.0

func _build_link(a: Dictionary, b: Dictionary) -> void:
	var p0 := edge_point(a, b["pos"]); var p1 := edge_point(b, a["pos"])
	var y0 := _ground(p0); var y1 := _ground(p1)
	var top0 := Vector3(p0.x, y0 + HEIGHT, p0.y); var top1 := Vector3(p1.x, y1 + HEIGHT, p1.y)
	var side := Vector3(-(p1 - p0).normalized().y, 0, (p1 - p0).normalized().x)
	var root := Node3D.new(); root.name = "Link_%d_%d" % [a["id"], b["id"]]
	add_child(root)
	# two pipes side by side: a large white one and a thin pastel one
	_tube(root, top0 + side * 0.07, top1 + side * 0.07, 0.065, "pipe")
	_tube(root, top0 - side * 0.09 + Vector3(0, -0.03, 0), top1 - side * 0.09 + Vector3(0, -0.03, 0), 0.035, "accent")
	# risers down into each building
	for e in [[top0, y0], [top1, y1]]:
		var t: Vector3 = e[0]
		_tube(root, t + side * 0.07, Vector3(t.x, e[1] + 0.25, t.z) + side * 0.07, 0.065, "pipe")
		_tube(root, t + side * 0.07 + Vector3(0, 0.08, 0), t + side * 0.07 - Vector3(0, 0.08, 0), 0.085, "collar")
	# trestles
	var len := p0.distance_to(p1)
	var n := maxi(1, int(len / SUPPORT_EVERY))
	for i in range(1, n):
		var q := p0.lerp(p1, float(i) / n)
		var gy := _ground(q)
		var y := lerpf(top0.y, top1.y, float(i) / n)
		var base := Vector3(q.x, gy, q.y)
		_tube(root, base, Vector3(q.x, y - 0.08, q.y), 0.03, "support")
		_box(root, Vector3(q.x, y - 0.08, q.y), Vector3(0.08, 0.04, 0.36), atan2(side.x, side.z), "support")
		_box(root, base + Vector3(0, 0.03, 0), Vector3(0.16, 0.06, 0.16), 0.0, "collar")
		if i % LAMP_EVERY == 0:
			var lamp := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.035; sm.height = 0.07
			lamp.mesh = sm; lamp.material_override = DayNight.material("glow_lamp")
			lamp.position = Vector3(q.x, y + 0.1, q.y)
			root.add_child(lamp)

func _tube(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: String) -> void:
	var d := b - a
	if d.length() < 0.01: return
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = d.length(); c.radial_segments = 10; c.rings = 1
	mi.mesh = c; mi.material_override = _mat(mat)
	var up := d.normalized()
	var ref := Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(ref).normalized(); var z := x.cross(up).normalized()
	mi.transform = Transform3D(Basis(x, up, z), (a + b) * 0.5)
	parent.add_child(mi)

func _box(parent: Node3D, pos: Vector3, size: Vector3, yaw: float, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = _mat(mat)
	mi.position = pos; mi.rotation.y = yaw
	parent.add_child(mi)
