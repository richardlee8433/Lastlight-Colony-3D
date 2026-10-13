class_name NavGrid
extends Node
## Walkable grid for villagers (0.5 m cells). Static scenery comes from data/world.json
## (exported from Blender); buildings add/remove blocked cells at runtime.
## Worn roads get a lower path cost so villagers converge on them.

signal changed

var cell := 0.5
var origin := Vector2(-17, -17)
var w := 68
var h := 68
var astar := AStarGrid2D.new()
var trees: Array[Vector3] = []          # (x, trunk_radius, z)

var _static := PackedByteArray()
var _dyn := PackedInt32Array()          # how many buildings block each cell
var _height := PackedFloat32Array()
var _building_cells := {}               # building id -> PackedInt32Array

func _ready() -> void:
	var f := FileAccess.open("res://data/world.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	cell = float(data["cell"])
	origin = Vector2(data["origin"][0], data["origin"][1])
	w = int(data["w"]); h = int(data["h"])
	_static.resize(w * h); _dyn.resize(w * h)
	_height = PackedFloat32Array(data["height"])
	for i in data["blocked"]:
		_static[int(i)] = 1
	for t in data["trees"]:
		trees.append(Vector3(t[0], t[2], t[1]))
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(cell, cell)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for i in w * h:
		if _static[i]:
			astar.set_point_solid(Vector2i(i % w, i / w), true)
	Game.building_added.connect(block_building)
	Game.building_removed.connect(unblock_building)
	Game.reset.connect(_on_reset)
	for b in Game.buildings:
		block_building(b, false)

# ---------------- coordinates ----------------

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell), floori((p.z - origin.y) / cell))

func cell_center(c: Vector2i) -> Vector3:
	var x := origin.x + (c.x + 0.5) * cell
	var z := origin.y + (c.y + 0.5) * cell
	return Vector3(x, height_at(x, z), z)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h

func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not astar.is_point_solid(c)

func height_at(x: float, z: float) -> float:
	var fx := (x - origin.x) / cell - 0.5
	var fz := (z - origin.y) / cell - 0.5
	var x0 := clampi(floori(fx), 0, w - 2); var z0 := clampi(floori(fz), 0, h - 2)
	var tx := clampf(fx - x0, 0.0, 1.0); var tz := clampf(fz - z0, 0.0, 1.0)
	var a := lerpf(_height[z0 * w + x0], _height[z0 * w + x0 + 1], tx)
	var b := lerpf(_height[(z0 + 1) * w + x0], _height[(z0 + 1) * w + x0 + 1], tx)
	return lerpf(a, b, tz)

func on_ground(p: Vector2) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y), p.y)

## Closest walkable cell to c (spiral search), or (-1,-1).
func nearest_walkable(c: Vector2i, max_r := 12) -> Vector2i:
	c = Vector2i(clampi(c.x, 0, w - 1), clampi(c.y, 0, h - 1))
	if is_walkable(c): return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1); var best_d := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r: continue
				var n := c + Vector2i(dx, dz)
				if is_walkable(n):
					var d := float(dx * dx + dz * dz)
					if d < best_d: best_d = d; best = n
		if best.x >= 0: return best
	return Vector2i(-1, -1)

## A walkable world point near p (p itself if its cell is free).
func walkable_point(p: Vector2) -> Vector2:
	var c := cell_of(Vector3(p.x, 0, p.y))
	if is_walkable(c): return p
	var n := nearest_walkable(c)
	if n.x < 0: return p
	var cc := cell_center(n)
	return Vector2(cc.x, cc.z)

# ---------------- paths ----------------

## Smoothed world-space path from a to b (both snapped to walkable cells). Empty if unreachable.
## lane offsets the route sideways a little so villagers don't walk in single file.
func find_path(from: Vector3, to: Vector3, lane := 0.0) -> PackedVector3Array:
	var a := nearest_walkable(cell_of(from))
	var b := nearest_walkable(cell_of(to))
	var out := PackedVector3Array()
	if a.x < 0 or b.x < 0: return out
	var ids := astar.get_id_path(a, b)
	if ids.is_empty(): return out
	var pts: Array[Vector2] = []
	pts.append(Vector2(from.x, from.z))
	for i in range(1, ids.size() - 1):
		var c := cell_center(ids[i])
		pts.append(Vector2(c.x, c.z))
	var end := Vector2(to.x, to.z) if is_walkable(cell_of(to)) else Vector2(cell_center(b).x, cell_center(b).z)
	pts.append(end)
	pts = _simplify(pts)
	pts = _chaikin(_chaikin(pts))
	if lane != 0.0 and pts.size() > 2:
		var shifted: Array[Vector2] = [pts[0]]
		for i in range(1, pts.size() - 1):
			var d := (pts[i + 1] - pts[i - 1]).normalized()
			var cand := pts[i] + Vector2(-d.y, d.x) * lane
			shifted.append(cand if is_walkable(cell_of(Vector3(cand.x, 0, cand.y))) else pts[i])
		shifted.append(pts[-1])
		pts = shifted
	for p in pts:
		out.append(Vector3(p.x, height_at(p.x, p.y), p.y))
	return out

func _simplify(pts: Array[Vector2]) -> Array[Vector2]:
	if pts.size() < 3: return pts
	var out: Array[Vector2] = [pts[0]]
	for i in range(1, pts.size() - 1):
		var d1 := (pts[i] - out[-1]).normalized()
		var d2 := (pts[i + 1] - pts[i]).normalized()
		if d1.dot(d2) < 0.999: out.append(pts[i])
	out.append(pts[-1])
	return out

func _chaikin(pts: Array[Vector2]) -> Array[Vector2]:
	if pts.size() < 3: return pts
	var out: Array[Vector2] = [pts[0]]
	for i in range(pts.size() - 1):
		var a := pts[i]; var b := pts[i + 1]
		if i > 0: out.append(a.lerp(b, 0.25))
		if i < pts.size() - 2: out.append(a.lerp(b, 0.75))
	out.append(pts[-1])
	return out

## Lower cost on worn roads (called by PathWear). weight: 1 = grass, < 1 = road.
func set_cell_weight(c: Vector2i, weight: float) -> void:
	if in_bounds(c): astar.set_point_weight_scale(c, weight)

# ---------------- buildings ----------------

func block_building(b: Dictionary, notify := true) -> void:
	var d: Dictionary = Defs.BUILDINGS[b["type"]]
	var cells := PackedInt32Array()
	for r in d.get("nav_block", []):
		var rect: Rect2 = r
		# rotate the rect's corners into world space (rotations are multiples of 90°)
		var p0 := Defs.to_world(b, rect.position)
		var p1 := Defs.to_world(b, rect.end)
		var wr := Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), (p1 - p0).abs())
		var c0 := cell_of(Vector3(wr.position.x, 0, wr.position.y))
		var c1 := cell_of(Vector3(wr.end.x, 0, wr.end.y))
		for x in range(c0.x, c1.x + 1):
			for z in range(c0.y, c1.y + 1):
				var c := Vector2i(x, z)
				if not in_bounds(c): continue
				var cc := cell_center(c)
				if wr.grow(0.2).has_point(Vector2(cc.x, cc.z)):
					var i := z * w + x
					_dyn[i] += 1
					cells.append(i)
					astar.set_point_solid(c, true)
	_building_cells[b["id"]] = cells
	if notify: changed.emit()

func unblock_building(b: Dictionary) -> void:
	var cells: PackedInt32Array = _building_cells.get(b["id"], PackedInt32Array())
	_building_cells.erase(b["id"])
	for i in cells:
		_dyn[i] = maxi(0, _dyn[i] - 1)
		if _dyn[i] == 0 and not _static[i]:
			astar.set_point_solid(Vector2i(i % w, i / w), false)
	changed.emit()

func _on_reset() -> void:
	for id in _building_cells.keys():
		unblock_building({"id": id})
	changed.emit()
