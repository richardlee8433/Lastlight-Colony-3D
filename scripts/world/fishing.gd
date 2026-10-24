class_name Fishing
extends Node
## Fishing huts and fish stocks. Water bodies: the pond (0) and stretches of the stream (1, 2, ...).
## Game.fish holds the stock of each body (0..1, saved); catching uses it up, it slowly comes back.
## Also provides the bank ("shore") spots used by fishers and by villagers strolling to the water.

@export var nav_path: NodePath = ^"../Nav"

const STREAM_STRETCH := 20                 # river samples per water body (~15 m)
static var _shore := PackedVector2Array()   # walkable cells next to water
static var _shore_look := PackedVector2Array()

func _ready() -> void:
	Game.reset.connect(func(): Game.fish.clear())

func _process(delta: float) -> void:
	var dt := delta * Game.speed
	if dt > 0.0: tick(dt)

## Fish come back over time (tests call this directly).
func tick(dt: float) -> void:
	var rate: float = dt * Defs.FISHING["regen_per_day"] / Defs.DAY_LENGTH
	for k in Game.fish.keys():
		Game.fish[k] = minf(1.0, float(Game.fish[k]) + rate)

# ---------------- water bodies ----------------

static func body_at(p: Vector2) -> int:
	var pond: Dictionary = Defs.WATER["pond"]
	if p.distance_to(pond["pos"]) < float(pond["radius"]) + 3.0: return 0
	var pts := Water.river_samples()
	var bi := 0; var bd := INF
	for i in pts.size():
		var d := pts[i].distance_squared_to(p)
		if d < bd: bd = d; bi = i
	return 1 + bi / STREAM_STRETCH

static func stock(body: int) -> float:
	return float(Game.fish.get(str(body), 1.0))

## Food from one fishing trip by the hut (0 when the fish are scarce).
static func catch_fish(b: Dictionary) -> int:
	var body := body_of(b)
	var s := stock(body)
	if s < Defs.FISHING["scarce"]: return 0
	Game.fish[str(body)] = maxf(0.0, s - float(Defs.FISHING["deplete"]))
	return maxi(1, roundi(Defs.FISHING["catch"] * s))

static func body_of(b: Dictionary) -> int:
	var h := Defs.half_extents(b["type"])
	return body_at(Defs.to_world(b, Vector2(0, h.y + 1.0)))

static func huts_on(body: int, except_id := -1) -> int:
	var n := 0
	for b in Game.buildings:
		if b["id"] != except_id and Defs.BUILDINGS[b["type"]].get("on_shore", false) and body_of(b) == body: n += 1
	return n

# ---------------- placement ----------------

## Closest water point within max_d of p (searched on the carve texture), or Vector2.INF.
static func nearest_water(p: Vector2, max_d: float) -> Vector2:
	var best := Vector2.INF; var bd := max_d
	var step := 0.25
	var n := ceili(max_d / step)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var q := p + Vector2(i, j) * step
			var d := q.distance_to(p)
			if d < bd and Water.is_water(q):
				bd = d; best = q
	return best

## Snap a shore building to the water near p: {"pos", "angle"} facing the water, or {}.
static func snap(type: String, p: Vector2) -> Dictionary:
	var w := nearest_water(p, Defs.FISHING["snap"])
	if w == Vector2.INF: return {}
	var dir := (w - p)
	if dir.length() < 0.01: return {}
	dir = dir.normalized()
	# the front edge ends ~0.6 m before the water, so the jetty reaches out over it
	var back := Defs.half_extents(type).y + 0.6
	var pos := w - dir * back
	# step back further if the footprint still touches water
	for k in 8:
		var wet := false
		for c in Defs.footprint_corners(type, pos, atan2(dir.x, dir.y), 0.1):
			if Water.sample(c).x > 0.3: wet = true
		if not wet: break
		pos -= dir * 0.25
	return {"pos": pos, "angle": atan2(dir.x, dir.y)}

## Why a shore building can't go here ("" = it can).
static func shore_problem(type: String, pos: Vector2, angle: float) -> String:
	var h := Defs.half_extents(type)
	var front := pos + Defs.rot2(Vector2(0, h.y + 1.3), angle)
	if not Water.is_water(front) and not Water.is_water(pos + Defs.rot2(Vector2(0, h.y + 0.7), angle)):
		return Loc.t("must face the water")
	var body := body_at(front)
	if huts_on(body) >= int(Defs.FISHING["huts_per_body"]): return Loc.t("this water already has enough fishing huts")
	return ""

# ---------------- bank spots ----------------

static func _build_shore(nav) -> void:
	_shore = PackedVector2Array(); _shore_look = PackedVector2Array()
	for z in nav.h:
		for x in nav.w:
			var c := Vector2i(x, z)
			if not nav.is_walkable(c): continue
			var cc: Vector3 = nav.cell_center(c)
			var p := Vector2(cc.x, cc.z)
			if not Defs.BUILD_BOUNDS.has_point(p): continue
			var wsum := Vector2.ZERO
			for d in [Vector2(0.6, 0), Vector2(-0.6, 0), Vector2(0, 0.6), Vector2(0, -0.6)]:
				if Water.is_water(p + d): wsum += d
			if wsum != Vector2.ZERO:
				_shore.append(p); _shore_look.append(p + wsum.normalized() * 1.5)

static func shore_spots(nav) -> PackedVector2Array:
	if _shore.is_empty(): _build_shore(nav)
	return _shore

## A bank spot near p within r: {"pos": Vector2, "look": Vector2}, or {}.
static func shore_near(nav, p: Vector2, r: float, rng: RandomNumberGenerator, body := -1) -> Dictionary:
	var spots := shore_spots(nav)
	var cand: Array[int] = []
	for i in spots.size():
		if spots[i].distance_to(p) <= r and (body < 0 or body_at(_shore_look[i]) == body) and nav.is_walkable(nav.cell_of(Vector3(spots[i].x, 0, spots[i].y))):
			cand.append(i)
	if cand.is_empty(): return {}
	var i: int = cand[rng.randi() % cand.size()]
	return {"pos": spots[i], "look": _shore_look[i]}
