extends Node
## 全局数据表：地块 / 偏旁 / 汉字 / 结局 / 美术资源映射。
##
## 汉字与偏旁的效果来自策划的《汉字组合效果.xlsx》；
## 因为 v2 改成「走过即消失 + 总步数预算」的关卡解谜，代价部分做了重做，
## 标注「v2」的条目是重做后的版本。

enum Tile { FLOOR, THORN, TREE, WALL, FIRE, WATER, EXIT }

# ---------------------------------------------------------------- 纸面配色
# 美术是「黑线手绘 + 白纸」风格（Kenney Scribble），所以整体走纸面主题。

var C_PAPER := Color("#f4f1e8")      # 纸
var C_PAPER_DIM := Color("#e2ddd0")  # 走掉的格子（纸，但空着）
var C_INK := Color("#2b2a28")        # 墨
var C_INK_SOFT := Color("#6b6862")
var C_INK_FAINT := Color("#b3aea4")
var C_ACCENT := Color("#c8892a")     # 赭石（标题、强调）
var C_GOOD := Color("#4a7c3f")
var C_BAD := Color("#b23a2e")
var C_GOLD := Color("#c9a227")

var TILE_NAME := {
	Tile.FLOOR: "地面", Tile.THORN: "荆棘", Tile.TREE: "树木",
	Tile.WALL: "障碍物", Tile.FIRE: "火", Tile.WATER: "水", Tile.EXIT: "门",
}

# 每种地块的底色。素材本身都是「黑线方块」，光看线条分不出来，
# 所以地形主要靠颜色区分——颜色浓淡就是这里的唯一语义通道，别调得太接近。
var TILE_TINT := {
	Tile.FLOOR: Color("#f3edda"),
	Tile.THORN: Color("#cfe2a6"),
	Tile.TREE: Color("#a3cd8c"),
	Tile.WALL: Color("#8d8778"),
	Tile.FIRE: Color("#f4b673"),
	Tile.WATER: Color("#a5caea"),
	Tile.EXIT: Color("#f0d284"),
}

# 美术素材（textures/ 下，之后由美术替换同名文件即可）。
# 地面刻意不贴图：留白就是「可以落笔的纸」，也让危险地形一眼跳出来。
var TILE_TEX := {
	Tile.FLOOR: "",
	Tile.THORN: "tile_spikes",
	Tile.TREE: "tile_tree",
	Tile.WALL: "tile_crate",
	Tile.FIRE: "pole_lantern",
	Tile.WATER: "tile_water",
	Tile.EXIT: "tile_door",
}
var TEX_PLAYER := "character_squareYellow"
var TEX_ITEM := "ui_box"
var TEX_HEART := "tile_heart"

# ---------------------------------------------------------------- 偏旁（决定结局）
## 主动效果：消耗 1 步发动一次；携带代价：只要在背包里就生效。

var RADICAL_ORDER := ["huo", "dao", "bing", "gong", "shi", "feng", "cao"]

var RADICALS := {
	"huo": {
		"char": "火", "name": "火",
		"active": "烧掉相邻的荆棘和树木，清出通路",
		"passive": "引火烧身：使用后自己 −1 生命",
		"ending": "焚",
		"color": Color("#c2452a"),
	},
	"dao": {
		"char": "刂", "name": "立刀旁",
		"active": "清除朝向一侧、一整条线上的所有荆棘",
		"passive": "沉：拾取时立刻 −3 步",
		"ending": "刃",
		"color": Color("#4a5568"),
	},
	"bing": {
		"char": "冫", "name": "两点水",
		"active": "浇灭周围两格内的所有火",
		"passive": "反噬：用后被随机方向推 1d4 格（撞墙或已走过的路才停）",
		"ending": "冰",
		"color": Color("#3a7fa8"),
	},
	"gong": {
		"char": "工", "name": "工",
		"active": "砸开相邻一格的障碍物",
		"passive": "重：携带时每走 1 格多花 1 步（翻倍）",
		"ending": "筑",
		"color": Color("#9a7b3f"),
	},
	"shi": {
		"char": "石", "name": "石",
		"active": "激活后，本关剩余时间内免疫火与水",
		"passive": "滞：携带时每走 3 格额外 −1 步",
		"ending": "磐",
		"color": Color("#6e6e78"),
	},
	"feng": {
		"char": "风", "name": "风",
		"active": "取走周围八格内任意一格的道具（远程拾取）",
		"passive": "窄：携带时背包容量降为 1",
		"ending": "漂",
		"color": Color("#3f8f78"),
	},
	"cao": {
		"char": "艹", "name": "草字头",
		"active": "激活后，本关剩余时间内可通过树木与水",
		"passive": "易燃：每走 4 格，若相邻有火则 −1 生命",
		"ending": "野",
		"color": Color("#5a8f47"),
	},
}

# ---------------------------------------------------------------- 汉字（永久增益）
var HANZI_ORDER := ["mo_mu", "mo_shui", "mo_ma", "mo_tu", "mo_ri", "mo_jin"]

var HANZI := {
	"mo_mu": {"char": "模", "part": "木", "effect": "立刻复制背包里的一个偏旁"},
	"mo_shui": {"char": "漠", "part": "氵", "effect": "能在火地块上行走（火不再造成伤害）"},
	"mo_ma": {"char": "蟆", "part": "虫", "effect": "立刻 +5 步"},
	"mo_tu": {"char": "墓", "part": "土", "effect": "生命值第一次归零时继续游戏"},
	"mo_ri": {"char": "暮", "part": "日", "effect": "看清全场地形（本作全程可见，提供 +1 步）"},
	"mo_jin": {"char": "幕", "part": "巾", "effect": "帷幕遮住尖刺：荆棘不再造成伤害"},
}

# ---------------------------------------------------------------- 结局
var ENDINGS := {
	"kong": {
		"title": "空", "glyph": "空",
		"text": "莫下面是空的。\n门纹丝不动——它只认填好的字。\n你把空着的那一格，一路带到了终点。",
	},
	"huo": {
		"title": "焚", "glyph": "火",
		"text": "火陪了你一路：烧开荆棘，也烧出新的火。\n出口处，莫的脚下腾起烈焰，把来路烧成一片通红。\n有人记得一个在火里行走、最后自己也成了火的人。",
	},
	"dao": {
		"title": "刃", "glyph": "刂",
		"text": "立刀旁在你身侧悬了一路，每走一步都削去一点力气。\n最后一刀落下，划开的却是自己的名字。\n莫从此有了锋芒，也有了伤口。",
	},
	"bing": {
		"title": "冰", "glyph": "冫",
		"text": "两点水教你冷。\n你走过的路一寸寸结霜，连呼吸都变轻。\n终点是一片冰封的湖，你走上去，湖面没有裂——它认得你。",
	},
	"gong": {
		"title": "筑", "glyph": "工",
		"text": "工在你手上砸开了一堵墙，也在墙后留下了路。\n你凿开障碍、铺平地面，最后把莫砌进了一座城。\n城很结实，只是没有门。",
	},
	"shi": {
		"title": "磐", "glyph": "石",
		"text": "石让你沉重，也让你不倒。\n你被它拖着走了一路，最后干脆不再挣扎。\n出口处，莫化作一块磐石：风吹不动，雨打不穿，也没人能挪走。",
	},
	"feng": {
		"title": "漂", "glyph": "风",
		"text": "风给了你自由，也拿走了停留的权利。\n你收集了四面八方，最后没有一面可以靠。\n莫随风而去——从此没有归途，也不必再找。",
	},
	"cao": {
		"title": "野", "glyph": "艹",
		"text": "草字头是万物生长。\n你穿过荆棘与树丛，脚下就冒出春天。\n终点不是终点，是一片荒野。荒野记住了莫的名字，然后继续长。",
	},
	"dead": {
		"title": "殁", "glyph": "",
		"text": "莫字未成。\n你倒在半路，偏旁散落了一地。\n下面那个空，空到了最后。",
	},
	"stuck": {
		"title": "尽", "glyph": "",
		"text": "路走完了，笔画也断在这里。\n前面再没有一格可以落笔。\n莫下面那个空，没能填上。",
	},
}

const PAIR_LINE := "两枚偏旁在你掌心相碰，最终只刻下一个名字——另一个悄然滑落。\n同一个「莫」，只能填一次。"

# ---------------------------------------------------------------- 关卡地图字符表
const CH_LEGEND := {
	"#": Tile.WALL, ".": Tile.FLOOR, "^": Tile.THORN, "T": Tile.TREE,
	"F": Tile.FIRE, "W": Tile.WATER, "S": Tile.FLOOR, "E": Tile.EXIT,
}
const CH_RADICAL := {
	"1": "huo", "2": "dao", "3": "bing", "4": "gong", "5": "shi", "6": "feng", "7": "cao",
}
const CH_HANZI := {
	"a": "mo_mu", "b": "mo_shui", "c": "mo_ma", "d": "mo_tu", "e": "mo_ri", "f": "mo_jin",
}
