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
	},
	"farm": {
		"name": "農田", "desc": "種植作物產出食物",
		"cost": {"wood": 20, "stone": 5}, "size": 4,
		"workers": 1, "produces": {"food": 4}, "cycle": 5.0,
	},
	"quarry": {
		"name": "採石場", "desc": "開採石頭產出石材",
		"cost": {"wood": 25}, "size": 3,
		"workers": 1, "produces": {"stone": 2}, "cycle": 5.0,
	},
	"house": {
		"name": "民房", "desc": "增加 4 人居住空間",
		"cost": {"wood": 20, "stone": 15}, "size": 3,
		"workers": 0, "housing": 4,
	},
}

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
