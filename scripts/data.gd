extends Node
## 全局数据表：地块 / 偏旁 / 汉字 / 结局。
##
## 数值来自策划的《汉字组合效果.xlsx》。
## 标注「代策划」的条目是策划缺席时补的实现方案，待复核。

enum Tile { FLOOR, THORN, TREE, WALL, FIRE, WATER, EXIT }

# ---------------------------------------------------------------- 配色

var C_BG := Color("#0a0a10")
var C_SIDE := Color("#12121c")
var C_SLOT_BG := Color("#141420")
var C_LINE := Color("#2c2c40")
var C_TEXT := Color("#d8d4e8")
var C_DIM := Color("#7a789a")
var C_FAINT := Color("#4a4860")
var C_ACCENT := Color("#d8b13a")
var C_GOOD := Color("#8fd8a0")
var C_BAD := Color("#e0705a")
var C_FOG := Color("#16161f")
var C_PLAYER := Color("#f2ead6")
var C_PLAYER_TEXT := Color("#12121c")

# ---------------------------------------------------------------- 地块

var TILE_NAME := {
	Tile.FLOOR: "地面",
	Tile.THORN: "荆棘",
	Tile.TREE: "树木",
	Tile.WALL: "障碍物",
	Tile.FIRE: "火",
	Tile.WATER: "水",
	Tile.EXIT: "出口",
}

var TILE_GLYPH := {
	Tile.FLOOR: "",
	Tile.THORN: "棘",
	Tile.TREE: "树",
	Tile.WALL: "障",
	Tile.FIRE: "火",
	Tile.WATER: "水",
	Tile.EXIT: "门",
}

var TILE_COLOR := {
	Tile.FLOOR: Color("#20202e"),
	Tile.THORN: Color("#33512f"),
	Tile.TREE: Color("#255c39"),
	Tile.WALL: Color("#454558"),
	Tile.FIRE: Color("#9e3619"),
	Tile.WATER: Color("#1f5590"),
	Tile.EXIT: Color("#8a6f1c"),
}

var TILE_GLYPH_COLOR := {
	Tile.THORN: Color("#9fd08a"),
	Tile.TREE: Color("#8ce0a8"),
	Tile.WALL: Color("#b4b4cc"),
	Tile.FIRE: Color("#ffc79a"),
	Tile.WATER: Color("#a8d8ff"),
	Tile.EXIT: Color("#ffe9a0"),
}

# ---------------------------------------------------------------- 偏旁（Sheet2）
## 偏旁 = 决定结局的核心道具：主动效果 + 携带代价。
## 「active」是主动使用（消耗 1 步），「passive」是携带期间的持续代价。

var RADICAL_ORDER := ["huo", "dao", "bing", "gong", "shi", "feng", "cao"]

var RADICALS := {
	"huo": {
		"char": "火",
		"name": "火",
		"active": "烧掉相邻成片的荆棘和树",
		"passive": "被烧的地块 30% 概率变成火地块",
		"ending": "焚",
		"color": Color("#e0603a"),
	},
	"dao": {
		"char": "刂",
		"name": "立刀旁",
		"active": "清除朝向一侧、宽一格的所有荆棘",
		"passive": "携带时每回合步数 −1",
		"ending": "刃",
		"color": Color("#b8c4d8"),
	},
	"bing": {
		"char": "冫",
		"name": "两点水",
		"active": "浇灭周围一片火地块，变为普通地面",
		"passive": "用后沿随机方向被推 1d4 格（遇障碍停止）",
		"ending": "冰",
		"color": Color("#6fc0e8"),
	},
	"gong": {
		"char": "工",
		"name": "工",
		"active": "破坏周围八格内任意一格的障碍物",
		# 代策划：原文「走过地块提前一轮消失」依赖未定义的地块寿命机制，
		# 改为「走过的地块留下瓦砾，再经过需多花 1 步」。
		"passive": "携带时走过的地块留下瓦砾（再经过多花 1 步）",
		"ending": "筑",
		"color": Color("#c8a870"),
	},
	"shi": {
		"char": "石",
		"name": "石",
		"active": "本回合可自由通过火、水地块",
		"passive": "携带时每回合被迫向右走一格（遇障碍停止）",
		"ending": "磐",
		"color": Color("#a0a0b0"),
	},
	"feng": {
		"char": "风",
		"name": "风",
		"active": "获得周围八格内任意一格的道具",
		"passive": "携带时背包容量 −1（拾取时若已满则随机替换）",
		"ending": "漂",
		"color": Color("#8fd8c0"),
	},
	"cao": {
		"char": "艹",
		"name": "草字头",
		"active": "本回合可自由通过树木和水",
		"passive": "周围八格出现火地块时，对你造成 1 点伤害",
		"ending": "野",
		"color": Color("#7fc86a"),
	},
}

# ---------------------------------------------------------------- 汉字（Sheet1）
## 汉字 = 拾取即得的永久增益，不占背包、不影响结局。

var HANZI_ORDER := ["mo_mu", "mo_shui", "mo_ma", "mo_tu", "mo_ri", "mo_jin"]

var HANZI := {
	"mo_mu": {
		"char": "模",
		"part": "木",
		"effect": "背包没满时，每 3 回合复制一个背包中的道具",
	},
	"mo_shui": {
		"char": "漠",
		"part": "氵",
		"effect": "能在火地块上行走（火不再造成伤害）",
	},
	"mo_ma": {
		"char": "蟆",
		"part": "虫",
		"effect": "每回合步数 +2",
	},
	"mo_tu": {
		"char": "墓",
		"part": "土",
		"effect": "生命值第一次归零时继续游戏",
	},
	"mo_ri": {
		"char": "暮",
		"part": "日",
		"effect": "视野范围长宽各加两格（5×5 → 7×7）",
	},
	"mo_jin": {
		"char": "幕",
		"part": "巾",
		# 代策划：原文「走过地块存在时间加一回合」依赖未定义的地块寿命机制，
		# 改为「帷幕遮住尖刺，荆棘不再造成伤害」。
		"effect": "帷幕遮住尖刺：荆棘不再对你造成伤害",
	},
}

# ---------------------------------------------------------------- 结局

var ENDINGS := {
	"kong": {
		"title": "空",
		"glyph": "空",
		"text": "你把一路捡到的偏旁都留在了路上。\n站在出口，莫还是莫——下面那个空，始终空着。\n你没有变成任何字，所以你还是你自己。",
	},
	"huo": {
		"title": "焚",
		"glyph": "火",
		"text": "火陪了你一路：烧开荆棘，也烧出新的火。\n出口处，莫的脚下腾起烈焰，把来路烧成一片通红。\n有人记得一个在火里行走、最后自己也成了火的人。",
	},
	"dao": {
		"title": "刃",
		"glyph": "刂",
		"text": "立刀旁在你身侧悬了一路，每走一步都削去一点力气。\n最后一刀落下，划开的却是自己的名字。\n莫从此有了锋芒，也有了伤口。",
	},
	"bing": {
		"title": "冰",
		"glyph": "冫",
		"text": "两点水教你冷。\n你走过的路一寸寸结霜，连呼吸都变轻。\n终点是一片冰封的湖，你走上去，湖面没有裂——它认得你。",
	},
	"gong": {
		"title": "筑",
		"glyph": "工",
		"text": "工在你脚下留下瓦砾，也在瓦砾上架起通路。\n你凿开障碍、铺平地面，最后把莫砌进了一座城。\n城很结实，只是没有门。",
	},
	"shi": {
		"title": "磐",
		"glyph": "石",
		"text": "石让你沉重，也让你不倒。\n你被它拖着走了一路，最后干脆不再挣扎。\n出口处，莫化作一块磐石：风吹不动，雨打不穿，也没人能挪走。",
	},
	"feng": {
		"title": "漂",
		"glyph": "风",
		"text": "风给了你自由，也拿走了停留的权利。\n你收集了四面八方，最后没有一面可以靠。\n莫随风而去——从此没有归途，也不必再找。",
	},
	"cao": {
		"title": "野",
		"glyph": "艹",
		"text": "草字头是万物生长。\n你穿过荆棘与树丛，脚下就冒出春天。\n终点不是终点，是一片荒野。荒野记住了莫的名字，然后继续长。",
	},
	"dead": {
		"title": "殁",
		"glyph": "",
		"text": "莫字未成。\n你倒在半路，偏旁散落了一地。\n下面那个空，空到了最后。",
	},
}

const PAIR_LINE := "两枚偏旁在你掌心相碰，最终只刻下一个名字——另一个悄然滑落。\n同一个「莫」，只能填一次。"
