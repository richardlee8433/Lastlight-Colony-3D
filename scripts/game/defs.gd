class_name Defs
## Static game data: resources, buildings, quests, tuning. Tweak balance here.

const RESOURCES := {
	"wood": {"name": "Wood", "color": Color(0.80, 0.58, 0.32)},
	"stone": {"name": "Stone", "color": Color(0.72, 0.74, 0.78)},
	"food": {"name": "Food", "color": Color(0.92, 0.42, 0.36)},
}

## the settlers arrive with a supply cart (storage + camp beds) and these goods
const START := {
	"resources": {"wood": 60, "stone": 20, "food": 40},
	"population": 3,
	"housing": 0,
}
const CART_SPOT := Vector2(0.0, 1.0)
const CART_ANGLE := 0.25

## seconds of game time per in-game day (at 1x speed)
const DAY_LENGTH := 30.0
## food eaten per villager per day
const FOOD_PER_VILLAGER := 1
## a new villager arrives each day if there is free housing and at least this much food
const GROWTH_FOOD_MIN := 10

## size = square footprint side in metres. Producers have one worker; "yield" is what the
## worker carries to the nearest storage after each work session — so distance matters.
## Layout keys use building-local (x, z) metres, front of the building = +z:
##   nav_block  rects villagers can't walk through
##   work_spot / work_look   where the worker stands and what they face ("spot" jobs)
##   door       where residents rest (houses)     drop   where goods are delivered (storehouses)
const BUILDINGS := {
	"woodcutter": {
		"name": "Woodcutter", "desc": "Paint a forest area after building it. The woodcutter fells the grown trees inside and carries the logs to storage; stumps regrow and saplings sprout",
		"cost": {"wood": 15}, "size": 3, "build_time": 16,
		"workers": 1, "yield": {"wood": 8},
		"nav_block": [Rect2(-1.05, -0.75, 2.1, 1.5), Rect2(-0.55, -1.3, 1.25, 0.45), Rect2(0.8, -1.25, 0.5, 0.5)],
		"job": {"anim": "chop", "tool": "Axe", "carry": "CarryLog", "hat": "Hood", "target": "tree"},
	},
	"farm": {
		"name": "Farmhouse", "desc": "After building it, paint its field. The farmer tends the wheat and carries the harvest to storage; bigger fields give more per trip",
		"cost": {"wood": 20, "stone": 5}, "size": 3, "build_time": 16,
		"workers": 1, "yield": {"food": 5},        # real per-trip yield comes from the field size (Fields)
		"nav_block": [Rect2(-1.2, -0.95, 2.4, 1.7)],
		"job": {"anim": "hoe", "tool": "Hoe", "carry": "CarrySack", "hat": "HatStraw", "target": "field"},
	},
	"quarry": {
		"name": "Quarry", "desc": "Built on a stone deposit. The mason breaks off stone and hauls it to storage",
		"cost": {"wood": 25}, "size": 4, "build_time": 20, "on_deposit": true,
		"workers": 1, "yield": {"stone": 6},
		# the rock itself is the deposit (blocked in NavGrid); these are the crane, bench, block stack, sledge
		"nav_block": [Rect2(-1.85, -1.45, 0.8, 0.75), Rect2(1.4, -0.72, 0.5, 0.95), Rect2(0.85, 1.0, 1.05, 0.4), Rect2(-1.7, 0.85, 0.7, 0.75)],
		"work_spot": Vector2(0.0, 1.5), "work_look": Vector2(0.0, 0.2),
		"job": {"anim": "mine", "tool": "Pick", "carry": "CarryStone", "hat": "HatCap", "target": "spot"},
	},
	"house": {
		"name": "House", "desc": "Room for 4 villagers",
		"cost": {"wood": 20, "stone": 15}, "size": 3, "build_time": 20,
		"workers": 0, "housing": 4,
		"nav_block": [Rect2(-1.35, -1.0, 2.7, 2.0)],
		"door": Vector2(0.0, 1.45),
	},
	"cart": {
		"name": "Supply cart", "desc": "The settlers' supply cart: temporary storage, with 4 bedrolls by the campfire",
		"cost": {}, "size": 3, "permanent": true,
		"workers": 0, "storage": true, "housing": 4,
		"nav_block": [Rect2(-1.45, -0.62, 2.4, 1.24), Rect2(1.02, 0.72, 0.56, 0.56)],
		"drop": Vector2(-0.5, 1.05), "door": Vector2(1.3, 1.75),
	},
	"storehouse": {
		"name": "Storehouse", "desc": "Villagers haul goods to the nearest storage. Build one near production to shorten trips",
		"cost": {"wood": 30, "stone": 10}, "size": 3, "build_time": 24,
		"workers": 0, "storage": true,
		"nav_block": [Rect2(-1.35, -1.35, 2.7, 2.35)],
		"drop": Vector2(0.0, 1.55),
	},
}

## areas where nothing can be built (world x, z): the starting cottage and its doorstep
const NO_BUILD := []
## buildable area (world x, z)
const BUILD_BOUNDS := Rect2(-15.5, -15.5, 31.0, 31.0)
## gap kept between buildings (metres)
const BUILD_GAP := 0.25

## ---- villagers & paths ----
const VILLAGER := {
	"speed": 1.5,            # m/s of game time
	"work_time": 4.0,         # seconds working before carrying the yield to storage
	"rest_every": 3,          # go home to rest every N deliveries
	"rest_time": 4.0,
	"drop_time": 0.7,
}
## villagers arrive along the existing dirt roads
const SPAWN_POINTS := [Vector2(0.2, 16.3), Vector2(16.3, 0.9)]

const PATHS := {
	"deposit": 0.16,          # wear added per second of walking (at the centre of the footprint)
	"decay": 0.0012,          # wear removed per second everywhere (an unused road fades in ~10 game minutes)
	"road_weight": 0.45,      # path-finding cost on a well-worn road (1 = grass) — villagers prefer roads
	"trample_start": 0.28,    # grass starts shrinking
	"trample_full": 0.6,      # grass gone
}

static func building_center(b: Dictionary) -> Vector2:
	return b["pos"]

## rotate a local (x, z) vector by a building angle (same as Node3D.rotation.y = angle)
static func rot2(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) + v.y * sin(a), -v.x * sin(a) + v.y * cos(a))

## building-local (x, z) -> world (x, z)
static func to_world(b: Dictionary, local: Vector2) -> Vector2:
	return b["pos"] + rot2(local, b["angle"])

## world (x, z) -> building-local (x, z)
static func to_local(b: Dictionary, world: Vector2) -> Vector2:
	return rot2(world - b["pos"], -b["angle"])

static func half_extents(type: String) -> Vector2:
	var s: float = BUILDINGS[type]["size"]
	return Vector2(s, s) * 0.5

## corners of an oriented footprint (world x, z)
static func footprint_corners(type: String, pos: Vector2, angle: float, grow := 0.0) -> PackedVector2Array:
	var h := half_extents(type) + Vector2(grow, grow)
	var out := PackedVector2Array()
	for c in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		out.append(pos + rot2(c, angle))
	return out

## separating-axis test for two convex quads
static func quads_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly in [a, b]:
		for i in 4:
			var e: Vector2 = poly[(i + 1) % 4] - poly[i]
			var axis := Vector2(-e.y, e.x)
			var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
			for p in a:
				var d := axis.dot(p); amin = minf(amin, d); amax = maxf(amax, d)
			for p in b:
				var d := axis.dot(p); bmin = minf(bmin, d); bmax = maxf(bmax, d)
			if amax < bmin or bmax < amin: return false
	return true

## build menu: building types plus the residential-zone brush ("zone")
const BUILD_ORDER := ["woodcutter", "farm", "quarry", "zone", "storehouse"]
const TOOLS := {
	"zone": {"name": "Housing zone", "desc": "Paint where people may live. When the village needs beds and can pay, villagers build houses there themselves (each: Wood 20, Stone 15)",
		"label": "Paint area"},
}

## construction: a placed building is a site until builders have worked "build_time" seconds on it;
## each work session adds VILLAGER.work_time. Sites are staffed before workplaces.
const CONSTRUCTION := {"stage2": 0.5}     # progress where the site turns from foundation to timber frame

## stone deposits: quarries can only be built on one of these (one quarry each)
const DEPOSITS := [
	{"pos": Vector2(10.5, 5.5), "model": 0, "angle": 2.4},
	{"pos": Vector2(-2.5, -8.5), "model": 1, "angle": 0.6},
	{"pos": Vector2(-12.0, 6.0), "model": 1, "angle": -1.2},
	{"pos": Vector2(-12.0, -6.0), "model": 0, "angle": 1.0},
]
const DEPOSIT := {"radius": 1.15, "snap": 6.0}   # rock blocks walking within radius; the ghost snaps from this far

## farm fields: painted per farmhouse on the zone grid
const FIELD := {
	"range": 10.0,            # max distance from the farmhouse (m)
	"max_cells": 96,          # 24 m²
	"min_cells": 8,           # smaller fields don't produce
	"cells_per_food": 12,     # food per trip = cells / 12 (3 m² per food)
	"max_yield": 8,
	"grow_days": 1.25,        # freshly tilled -> ripe (only once the farmhouse is finished)
	"harvest_trips": 5,       # trips of food a ripe field gives before it is tilled again
}

## woodcutter forest areas and tree growth (times in in-game days)
const FOREST := {
	"range": 12.0,            # max distance of the area from the lodge (m)
	"max_cells": 240,         # 60 m²
	"min_cells": 8,
	"chops_per_tree": 3,      # trips of wood one grown tree gives before it falls
	"stump_days": 1.0,        # a stump sprouts again after this
	"grow_days": 3.0,         # sapling -> grown tree
	"sprout_check": 6.0,      # seconds between sapling checks per area
	"cells_per_tree": 20,     # areas fill up to one tree per 5 m²
	"spacing": 1.7,           # min distance between trunks (m)
	"auto_radius": 3.0,       # starter area: a disc this big over the nearest trees
}

## residential zones: painted on the same 0.5 m grid as the walk grid
const ZONE := {
	"cell": 0.5, "origin": Vector2(-17, -17), "w": 68,
	"brush_radius": 1.3,
	"grow_check": 2.0,        # seconds between growth checks
	"grow_cooldown": 8.0,     # minimum seconds between two new houses
	"free_beds_trigger": 1,   # build when this many beds or fewer are free
}

const QUESTS := [
	{"text": "Build a woodcutter", "type": "build", "building": "woodcutter", "count": 1, "reward": {"food": 10}},
	{"text": "Build a farmhouse and paint its field", "type": "build", "building": "farm", "count": 1, "reward": {"wood": 15}},
	{"text": "Paint a housing zone and wait for a house", "type": "build", "building": "house", "count": 1, "reward": {"stone": 10}},
	{"text": "Build a quarry on a stone deposit", "type": "build", "building": "quarry", "count": 1, "reward": {"wood": 20}},
	{"text": "Build a storehouse near production", "type": "build", "building": "storehouse", "count": 1, "reward": {"food": 20}},
	{"text": "Reach 10 villagers", "type": "population", "value": 10, "reward": {"food": 30}},
	{"text": "Stockpile 100 wood", "type": "resource", "res": "wood", "value": 100, "reward": {"stone": 30}},
	{"text": "Have 3 farmhouses", "type": "build", "building": "farm", "count": 3, "reward": {"wood": 40}},
	{"text": "Reach 20 villagers", "type": "population", "value": 20, "reward": {}},
]

## display name of a building type or tool
static func label(type: String) -> String:
	return Loc.t(TOOLS[type]["name"] if TOOLS.has(type) else BUILDINGS[type]["name"])

## translated description of a building type or tool
static func desc(type: String) -> String:
	return Loc.t(TOOLS[type]["desc"] if TOOLS.has(type) else BUILDINGS[type]["desc"])

## translated resource name
static func res_name(r: String) -> String:
	return Loc.t(RESOURCES[r]["name"])

static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r in cost:
		parts.append("%s %d" % [res_name(r), cost[r]])
	return "  ".join(parts)
