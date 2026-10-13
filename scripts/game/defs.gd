class_name Defs
## Static game data: resources, buildings, quests, tuning. Tweak balance here.

const RESOURCES := {
	"wood": {"name": "木材", "color": Color(0.80, 0.58, 0.32)},
	"stone": {"name": "石材", "color": Color(0.72, 0.74, 0.78)},
	"food": {"name": "食物", "color": Color(0.92, 0.42, 0.36)},
}

const START := {
	"resources": {"wood": 40, "stone": 15, "food": 30},
	"population": 3,
	"housing": 4,   # the starter cottage
}

## seconds of real time per in-game day at 1x speed
const DAY_LENGTH := 8.0
## food eaten per villager per day
const FOOD_PER_VILLAGER := 1
## a new villager arrives each day if there is free housing and at least this much food
const GROWTH_FOOD_MIN := 10

## size = footprint in grid cells (square), cycle = seconds per production at 1x
const BUILDINGS := {
	"woodcutter": {
		"name": "伐木場", "desc": "工人砍樹產出木材",
		"cost": {"wood": 15}, "size": 3,
		"workers": 1, "produces": {"wood": 3}, "cycle": 4.0,
		"nav_block": [Rect2(-1.05, -0.75, 2.1, 1.5), Rect2(-0.55, -1.3, 1.25, 0.45), Rect2(0.8, -1.25, 0.5, 0.5)],
		"drop": Vector2(0.0, -1.8),
		"job": {"anim": "chop", "tool": "Axe", "carry": "CarryLog", "hat": "Hood", "target": "tree", "to_storage_every": 3},
	},
	"farm": {
		"name": "農田", "desc": "種植作物產出食物",
		"cost": {"wood": 20, "stone": 5}, "size": 4,
		"workers": 1, "produces": {"food": 4}, "cycle": 5.0,
		"nav_block": [],
		"job": {"anim": "hoe", "tool": "Hoe", "carry": "CarrySack", "hat": "HatStraw", "target": "field"},
	},
	"quarry": {
		"name": "採石場", "desc": "開採石頭產出石材",
		"cost": {"wood": 25}, "size": 3,
		"workers": 1, "produces": {"stone": 2}, "cycle": 5.0,
		"nav_block": [Rect2(-1.2, -1.4, 1.8, 1.5), Rect2(0.5, 0.6, 1.25, 0.45), Rect2(-1.05, 0.75, 0.3, 0.3)],
		"work_spot": Vector2(0.1, 0.5), "work_look": Vector2(-0.2, -0.3),
		"job": {"anim": "mine", "tool": "Pick", "carry": "CarryStone", "hat": "HatCap", "target": "spot"},
	},
	"house": {
		"name": "民房", "desc": "增加 4 人居住空間",
		"cost": {"wood": 20, "stone": 15}, "size": 3,
		"workers": 0, "housing": 4,
		"nav_block": [Rect2(-1.35, -1.0, 2.7, 2.0)],
		"door": Vector2(0.0, 1.45),
	},
}

## ---- villagers & paths ----
const VILLAGER := {
	"speed": 1.35,            # m/s of game time
	"work_time": 5.0,         # seconds working before carrying goods
	"rest_every": 3,          # go home to rest every N deliveries
	"rest_time": 4.0,
	"drop_time": 0.7,
}
## the starting cottage: storage + first home
const STORAGE_POINT := Vector2(0.0, 2.75)
const STORAGE_LOOK := Vector2(0.0, 1.6)
const STARTER_HOUSING := 4
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
	var s: int = BUILDINGS[b["type"]]["size"]
	return Vector2(b["cell"].x + s / 2.0, b["cell"].y + s / 2.0)

## building-local (x, z) -> world (x, z), matching BuildingVisuals rotation (rot * 90° around Y)
static func to_world(b: Dictionary, local: Vector2) -> Vector2:
	var a := int(b["rot"]) * PI / 2.0
	var v := Vector3(local.x, 0, local.y).rotated(Vector3.UP, a)
	return building_center(b) + Vector2(v.x, v.z)

const BUILD_ORDER := ["woodcutter", "farm", "quarry", "house"]

const QUESTS := [
	{"text": "蓋一座伐木場", "type": "build", "building": "woodcutter", "count": 1, "reward": {"food": 10}},
	{"text": "蓋一塊農田", "type": "build", "building": "farm", "count": 1, "reward": {"wood": 15}},
	{"text": "蓋一間民房", "type": "build", "building": "house", "count": 1, "reward": {"stone": 10}},
	{"text": "蓋一座採石場", "type": "build", "building": "quarry", "count": 1, "reward": {"wood": 20}},
	{"text": "人口達到 10 人", "type": "population", "value": 10, "reward": {"food": 30}},
	{"text": "存到 100 木材", "type": "resource", "res": "wood", "value": 100, "reward": {"stone": 30}},
	{"text": "擁有 3 塊農田", "type": "build", "building": "farm", "count": 3, "reward": {"wood": 40}},
	{"text": "人口達到 20 人", "type": "population", "value": 20, "reward": {}},
]

static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r in cost:
		parts.append("%s %d" % [RESOURCES[r]["name"], cost[r]])
	return "  ".join(parts)
