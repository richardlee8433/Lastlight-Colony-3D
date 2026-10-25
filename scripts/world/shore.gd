class_name Shore
extends Node
## Bank spots along the lake and the stream: walkable cells next to the water, each with a point
## out over the water to look at. Idle colonists sometimes walk down and watch the water.

static var _shore := PackedVector2Array()   # walkable cells next to water
static var _shore_look := PackedVector2Array()

static func _build(nav) -> void:
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

static func spots(nav) -> PackedVector2Array:
	if _shore.is_empty(): _build(nav)
	return _shore

## A bank spot near p within r: {"pos": Vector2, "look": Vector2}, or {}.
static func near(nav, p: Vector2, r: float, rng: RandomNumberGenerator) -> Dictionary:
	var all := spots(nav)
	var cand: Array[int] = []
	for i in all.size():
		if all[i].distance_to(p) <= r and nav.is_walkable(nav.cell_of(Vector3(all[i].x, 0, all[i].y))):
			cand.append(i)
	if cand.is_empty(): return {}
	var i: int = cand[rng.randi() % cand.size()]
	return {"pos": all[i], "look": _shore_look[i]}
