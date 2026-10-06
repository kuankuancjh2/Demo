class_name Game
extends RefCounted
## 《莫下面一个空》v2 全部规则。只依赖 Data（autoload），不依赖任何 UI。
##
## 核心：
##   1. 走过即消失 —— 一格只能踩一次，不能回头。
##   2. 总步数预算 —— 不是每回合刷新，是用来花光的资源。
##   3. 门只认填好的字 —— 空手走到门口不算通关。
##
## 于是每一关都变成：在会消失的纸面上，画一条不自交的笔画，
## 起点 → 偏旁 → 门，一笔画完。

const FOUR: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const EIGHT: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

enum State { PLAYING, WON, DEAD, STUCK }

var W := 9
var H := 9
var rng := RandomNumberGenerator.new()

var map: Array = []      # [y][x] -> Data.Tile
var walked: Array = []   # [y][x] -> bool，踩过就消失
var items: Array = []    # [y][x] -> Array[{kind,id}]

var start := Vector2i(1, 1)
var exitp := Vector2i(7, 1)
var player := Vector2i(1, 1)
var facing := Vector2i(0, 1)

var hp := 3
var max_hp := 3
var steps_left := -1     # -1 = 不限
var steps_total := -1
var steps_used := 0

var bag: Array = []      # 偏旁 id，按拾取顺序；bag[0] 决定结局
var buffs: Array = []

var revive_used := false
var shi_active := false
var cao_active := false
var since_shi := 0
var since_cao := 0

var trail: Array = []    # 落笔顺序，画出来就是「你写的那一笔」
var state := State.PLAYING
var ending: Dictionary = {}
var log_lines: Array = []
var undo_stack: Array = []

var level_name := ""
var hint := ""
var level_index := -1
var is_random := false
var seed_used := 0
var solution_path: Array = []   # 随机关卡的保底解（一定是合法的自避路线）


# ============================================================ 开局

func load_level(idx: int) -> void:
	var lv: Dictionary = Levels.LEVELS[idx]
	level_index = idx
	is_random = false
	level_name = lv["name"]
	hint = lv["hint"]
	steps_total = lv["steps"]
	max_hp = lv["hp"]
	_build_from_ascii(lv["map"])
	_reset_runtime()


func new_random(p_seed: int = -1) -> void:
	is_random = true
	level_index = -1
	if p_seed < 0:
		p_seed = randi() & 0x7fffffff
	seed_used = p_seed
	rng.seed = p_seed
	W = 11
	H = 11
	steps_total = -1
	max_hp = 3
	level_name = "随机 · 第 %d 号" % (p_seed % 10000)
	hint = "全图可见。画一条不自交的笔画：先拿偏旁，再进门。"
	_generate_random()
	_reset_runtime()


func _reset_runtime() -> void:
	hp = max_hp
	steps_left = steps_total
	steps_used = 0
	bag = []
	buffs = []
	revive_used = false
	shi_active = false
	cao_active = false
	since_shi = 0
	since_cao = 0
	state = State.PLAYING
	ending = {}
	log_lines = []
	undo_stack = []
	trail = [start]
	facing = Vector2i(0, 1)
	_log("「%s」" % level_name)
	if hint != "":
		_log(hint)
	_log("走过的地面会消失。门只对带着偏旁的莫打开。")


func _build_from_ascii(rows: Array) -> void:
	H = rows.size()
	W = 0
	for r in rows:
		W = maxi(W, String(r).length())
	map = []
	walked = []
	items = []
	start = Vector2i(1, 1)
	exitp = Vector2i(W - 2, H - 2)
	for y in H:
		var line := String(rows[y])
		var mr: Array = []
		var wr: Array = []
		var ir: Array = []
		for x in W:
			var ch := "." if x >= line.length() else line[x]
			var cell := Data.Tile.FLOOR
			if Data.CH_LEGEND.has(ch):
				cell = Data.CH_LEGEND[ch]
			mr.append(cell)
			wr.append(false)
			ir.append([])
			match ch:
				"S":
					start = Vector2i(x, y)
				"E":
					exitp = Vector2i(x, y)
				_:
					if Data.CH_RADICAL.has(ch):
						ir[-1].append({"kind": "radical", "id": Data.CH_RADICAL[ch]})
					elif Data.CH_HANZI.has(ch):
						ir[-1].append({"kind": "hanzi", "id": Data.CH_HANZI[ch]})
		map.append(mr)
		walked.append(wr)
		items.append(ir)
	player = start


# ============================================================ 派生数值

func has_buff(id: String) -> bool:
	return buffs.has(id)


func bag_capacity() -> int:
	return 1 if bag.has("feng") else 2


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H


func tile_at(p: Vector2i) -> int:
	return map[p.y][p.x]


func ground_items(p: Vector2i) -> Array:
	return items[p.y][p.x]


func walkable(p: Vector2i) -> bool:
	## 不考虑步数与血量，只看「能不能落脚」
	if not in_bounds(p) or walked[p.y][p.x]:
		return false
	var t := tile_at(p)
	if t == Data.Tile.WALL:
		return false
	if t == Data.Tile.TREE and not cao_active:
		return false
	return true


func step_cost(p: Vector2i) -> int:
	var c := 1
	if bag.has("gong"):
		c *= 2      # 工：翻倍
	return c


func fire_adjacent() -> bool:
	for d in EIGHT:
		var p := player + d
		if in_bounds(p) and tile_at(p) == Data.Tile.FIRE:
			return true
	return false


# ============================================================ 移动

func move(dir: Vector2i) -> bool:
	if state != State.PLAYING:
		return false
	var np := player + dir
	if not in_bounds(np):
		return false
	if walked[np.y][np.x]:
		_log("那一格已经写过了，纸空着。")
		return false
	var t := tile_at(np)
	if t == Data.Tile.WALL:
		_log("障碍物挡路。用「工」砸开，或者绕开。")
		return false
	if t == Data.Tile.TREE and not cao_active:
		_log("树木挡路。需要「艹」，或者绕开。")
		return false

	var cost := step_cost(np)
	if bag.has("shi"):
		since_shi += 1
		if since_shi % 3 == 0:
			cost += 1
			_log("「石」拖慢了你（额外 −1 步）。")
	if steps_left >= 0 and cost > steps_left:
		_log("步数不够了：需要 %d 步，只剩 %d。" % [cost, steps_left])
		return false

	push_undo()
	facing = dir
	if steps_left >= 0:
		steps_left -= cost
	steps_used += cost
	player = np
	walked[np.y][np.x] = true
	trail.append(np)

	# 艹：每走 4 格，若旁边有火就烧到
	if bag.has("cao"):
		since_cao += 1
		if since_cao % 4 == 0 and fire_adjacent():
			_damage(1, "「艹」被旁边的火引燃")

	if state == State.PLAYING:
		_on_enter(np)

	if state == State.PLAYING and not has_any_move():
		_stuck("没有可以落笔的地方了。")
	return true


func _on_enter(p: Vector2i) -> void:
	var t := tile_at(p)

	# 先结算地形伤害
	match t:
		Data.Tile.THORN:
			if not has_buff("mo_jin"):
				_damage(1, "荆棘划伤了你")
		Data.Tile.FIRE:
			if not (has_buff("mo_shui") or shi_active):
				_damage(1, "火焰灼伤了你")
		Data.Tile.WATER:
			if not (shi_active or cao_active):
				_damage(1, "寒水冻伤了你")
	if state != State.PLAYING:
		return

	# 门
	if t == Data.Tile.EXIT:
		if bag.is_empty():
			state = State.STUCK
			var e: Dictionary = Data.ENDINGS["kong"].duplicate(true)
			e["glyph"] = "空"
			e["pair"] = false
			ending = e
			_log("门纹丝不动。莫下面还空着——你没有填上任何一个字。")
		else:
			_win()


func has_any_move() -> bool:
	for d in FOUR:
		if walkable(player + d):
			return true
	return false


func _damage(n: int, reason: String) -> void:
	if state != State.PLAYING or n <= 0:
		return
	hp -= n
	_log("%s（−%d 生命，剩 %d）。" % [reason, n, maxi(hp, 0)])
	if hp <= 0:
		if has_buff("mo_tu") and not revive_used:
			revive_used = true
			hp = 1
			_log("「墓」发作了——你从死亡边缘被拽了回来。生命恢复至 1。")
		else:
			hp = 0
			_die()


func _stuck(msg: String) -> void:
	state = State.STUCK
	var e: Dictionary = Data.ENDINGS["stuck"].duplicate(true)
	e["glyph"] = "" if bag.is_empty() else Data.RADICALS[bag[0]]["char"]
	e["pair"] = false
	ending = e
	_log(msg)


func _die() -> void:
	state = State.DEAD
	var e: Dictionary = Data.ENDINGS["dead"].duplicate(true)
	e["glyph"] = "" if bag.is_empty() else Data.RADICALS[bag[0]]["char"]
	e["pair"] = false
	ending = e
	_log("你倒下了。")


func _win() -> void:
	state = State.WON
	ending = _build_ending()
	_log("门开了。")


func _build_ending() -> Dictionary:
	var key := "kong"
	if not bag.is_empty():
		key = bag[0]
	var e: Dictionary = Data.ENDINGS[key].duplicate(true)
	e["pair"] = bag.size() > 1
	if bag.size() > 1:
		e["pair_char"] = Data.RADICALS[bag[1]]["char"]
	return e


# ============================================================ 拾取 / 丢弃

func pickup() -> bool:
	if state != State.PLAYING:
		return false
	var stack: Array = items[player.y][player.x]
	if stack.is_empty():
		_log("这里没有可以拾取的东西。")
		return false

	var it: Dictionary = stack.back()
	if it["kind"] == "hanzi":
		push_undo()
		stack.pop_back()
		_gain_hanzi(it["id"])
		if state == State.PLAYING and not has_any_move():
			_stuck("没有可以落笔的地方了。")
		return true

	var cap := bag_capacity()
	if bag.size() >= cap:
		_log("背包满了（容量 %d）。按 Q / E 抹掉一个再来。" % cap)
		return false

	push_undo()
	stack.pop_back()
	bag.append(it["id"])
	var d: Dictionary = Data.RADICALS[it["id"]]
	_log("拾取偏旁「%s」——%s。" % [d["char"], d["active"]])
	_log("代价：%s。带着它走到门，结局将定格为「%s」。" % [d["passive"], d["ending"]])

	if it["id"] == "dao":
		steps_used += 3
		if steps_left >= 0:
			steps_left = maxi(0, steps_left - 3)
		_log("「刂」压得你少走了 3 步。")
	if it["id"] == "feng":
		_log("「风」收窄了你的背包：容量降为 1。")
	if state == State.PLAYING and not has_any_move():
		_stuck("没有可以落笔的地方了。")
	return true


func drop_item(slot: int) -> bool:
	if state != State.PLAYING or slot < 0 or slot >= bag.size():
		return false
	push_undo()
	var id: String = bag[slot]
	bag.remove_at(slot)
	_log("抹掉了「%s」——再也拿不回来了。" % Data.RADICALS[id]["char"])
	if bag.has("feng") == false and id == "feng":
		pass
	return true


func _gain_hanzi(id: String) -> void:
	if buffs.has(id):
		_log("「%s」的效果你已经拥有了。" % Data.HANZI[id]["char"])
		return
	buffs.append(id)
	var h: Dictionary = Data.HANZI[id]
	_log("获得汉字「%s」（%s + 莫）：%s" % [h["char"], h["part"], h["effect"]])
	match id:
		"mo_ma":
			if steps_left >= 0:
				steps_left += 5
			_log("本关步数 +5。")
		"mo_mu":
			if not bag.is_empty() and bag.size() < bag_capacity():
				var d: String = bag[rng.randi() % bag.size()]
				bag.append(d)
				_log("「模」复制了一个「%s」。" % Data.RADICALS[d]["char"])
			else:
				_log("「模」想复制，但背包里没地方。")
		"mo_ri":
			if steps_left >= 0:
				steps_left += 1


# ============================================================ 偏旁主动效果

func needs_target(slot: int) -> bool:
	if slot < 0 or slot >= bag.size():
		return false
	return bag[slot] == "gong" or bag[slot] == "feng"


func target_cells(slot: int) -> Array:
	var out: Array = []
	if slot < 0 or slot >= bag.size():
		return out
	var id: String = bag[slot]
	match id:
		"gong":
			for d in EIGHT:
				var p := player + d
				if in_bounds(p) and tile_at(p) == Data.Tile.WALL:
					out.append(p)
		"feng":
			for d in EIGHT:
				var p := player + d
				if in_bounds(p) and not items[p.y][p.x].is_empty():
					out.append(p)
		_:
			pass
	return out


func use_item(slot: int, target: Vector2i = Vector2i(-1, -1)) -> bool:
	if state != State.PLAYING:
		return false
	if slot < 0 or slot >= bag.size():
		_log("这一格是空的。")
		return false
	var id: String = bag[slot]
	if needs_target(slot) and target == Vector2i(-1, -1):
		return false

	var cost := 1
	if bag.has("gong"):
		cost = 2
	if steps_left >= 0 and cost > steps_left:
		_log("步数不够发动它。")
		return false

	push_undo()
	steps_used += cost
	if steps_left >= 0:
		steps_left -= cost

	# 先记下发动前的位置，用来判断「有没有实际效果」
	var before := _fingerprint()
	match id:
		"huo": _eff_huo()
		"dao": _eff_dao()
		"bing": _eff_bing()
		"gong": _eff_gong(target)
		"shi": _eff_shi()
		"feng": _eff_feng(target)
		"cao": _eff_cao()
	var after := _fingerprint()
	if before == after:
		# 什么都没发生，把这一动退回去（别浪费玩家的步数）
		undo_stack.pop_back()
		steps_used -= cost
		if steps_left >= 0:
			steps_left += cost
		return false

	if state == State.PLAYING and not has_any_move():
		_stuck("没有可以落笔的地方了。")
	return true


func _fingerprint() -> String:
	return "%s|%s|%s|%s|%s|%s" % [map, stepped_keys(), items, bag, shi_active, cao_active]


func stepped_keys() -> String:
	return str(walked)


func _eff_huo() -> void:
	var n := 0
	for d in EIGHT:
		var p := player + d
		if in_bounds(p) and (tile_at(p) == Data.Tile.THORN or tile_at(p) == Data.Tile.TREE):
			map[p.y][p.x] = Data.Tile.FLOOR
			n += 1
	if n == 0:
		_log("「火」烧了个空——周围没有荆棘或树木。")
		return
	_log("「火」烧掉了周围 %d 格荆棘/树木。" % n)
	_damage(1, "引火烧身")


func _eff_dao() -> void:
	var cleared := 0
	var p := player + facing
	while in_bounds(p) and tile_at(p) != Data.Tile.WALL:
		if tile_at(p) == Data.Tile.THORN:
			map[p.y][p.x] = Data.Tile.FLOOR
			cleared += 1
		p += facing
	if cleared == 0:
		_log("「刂」挥了个空——%s方向没有荆棘。" % dir_name(facing))
	else:
		_log("「刂」清掉了%s方向的 %d 格荆棘。" % [dir_name(facing), cleared])


func _eff_bing() -> void:
	var n := 0
	for y in range(maxi(0, player.y - 2), mini(H, player.y + 3)):
		for x in range(maxi(0, player.x - 2), mini(W, player.x + 3)):
			if map[y][x] == Data.Tile.FIRE:
				map[y][x] = Data.Tile.FLOOR
				n += 1
	if n == 0:
		_log("「冫」浇了个空——附近没有火。")
		return
	_log("「冫」浇灭了 %d 格火。" % n)

	var dir: Vector2i = FOUR[rng.randi() % FOUR.size()]
	var dist := rng.randi_range(1, 4)
	var moved := 0
	for i in dist:
		var np := player + dir
		if not walkable(np):
			break
		player = np
		walked[np.y][np.x] = true
		trail.append(np)
		moved += 1
	facing = dir
	if moved > 0:
		_log("反噬：你被朝%s推了 %d 格。" % [dir_name(dir), moved])
		_on_enter(player)


func _eff_gong(target: Vector2i) -> void:
	if not in_bounds(target) or tile_at(target) != Data.Tile.WALL:
		_log("「工」需要指定一格障碍物。")
		return
	map[target.y][target.x] = Data.Tile.FLOOR
	_log("「工」砸开了 (%d, %d) 的障碍物。" % [target.x, target.y])


func _eff_shi() -> void:
	if shi_active:
		_log("「石」已经生效了。")
		return
	shi_active = true
	_log("「石」生效：本关剩余时间内免疫火与水。")


func _eff_cao() -> void:
	if cao_active:
		_log("「艹」已经生效了。")
		return
	cao_active = true
	_log("「艹」生效：本关剩余时间内可以通过树木与水。")


func _eff_feng(target: Vector2i) -> void:
	if not in_bounds(target) or items[target.y][target.x].is_empty():
		_log("「风」需要指定一格有道具的地方。")
		return
	var stack: Array = items[target.y][target.x]
	var it: Dictionary = stack.back()
	if it["kind"] == "hanzi":
		stack.pop_back()
		_log("「风」卷来了一个汉字。")
		_gain_hanzi(it["id"])
		return
	var newc: String = Data.RADICALS[it["id"]]["char"]
	if bag.size() >= bag_capacity():
		var di := rng.randi() % bag.size()
		var lost: String = bag[di]
		bag[di] = it["id"]
		stack.pop_back()
		_log("「风」卷来了「%s」，却把「%s」吹走了。" % [newc, Data.RADICALS[lost]["char"]])
	else:
		stack.pop_back()
		bag.append(it["id"])
		_log("「风」卷来了「%s」。" % newc)


# ============================================================ 撤回

func can_undo() -> bool:
	return not undo_stack.is_empty()


func push_undo() -> void:
	undo_stack.append({
		"map": map.duplicate(true),
		"walked": walked.duplicate(true),
		"items": items.duplicate(true),
		"player": player, "facing": facing, "hp": hp,
		"steps_left": steps_left, "steps_used": steps_used,
		"bag": bag.duplicate(), "buffs": buffs.duplicate(),
		"revive_used": revive_used,
		"shi_active": shi_active, "cao_active": cao_active,
		"since_shi": since_shi, "since_cao": since_cao,
		"state": state, "ending": ending.duplicate(true),
		"trail": trail.duplicate(),
		"log_len": log_lines.size(),
	})
	if undo_stack.size() > 400:
		undo_stack.pop_front()


func undo() -> bool:
	if undo_stack.is_empty():
		_log("没有可以撤回的笔了。")
		return false
	var s: Dictionary = undo_stack.pop_back()
	map = s["map"]
	walked = s["walked"]
	items = s["items"]
	player = s["player"]
	facing = s["facing"]
	hp = s["hp"]
	steps_left = s["steps_left"]
	steps_used = s["steps_used"]
	bag = s["bag"]
	buffs = s["buffs"]
	revive_used = s["revive_used"]
	shi_active = s["shi_active"]
	cao_active = s["cao_active"]
	since_shi = s["since_shi"]
	since_cao = s["since_cao"]
	state = s["state"]
	ending = s["ending"]
	trail = s["trail"]
	log_lines = log_lines.slice(0, s["log_len"])
	_log("撤回一笔。")
	return true


func dir_name(d: Vector2i) -> String:
	if d == Vector2i(0, -1): return "上"
	if d == Vector2i(0, 1): return "下"
	if d == Vector2i(-1, 0): return "左"
	if d == Vector2i(1, 0): return "右"
	return "?"


# ============================================================ 随机关卡生成
## 先随出一条「起点 → 门」的自避骨架并把它永久保留成地面，
## 再把偏旁放在骨架上 —— 于是「沿骨架走」永远是一条合法解，关卡必定可通。

func _generate_random() -> void:
	if rng.seed == 0:
		rng.seed = 12345
	map = []
	walked = []
	items = []
	for y in H:
		var mr: Array = []
		var wr: Array = []
		var ir: Array = []
		for x in W:
			mr.append(Data.Tile.FLOOR)
			wr.append(false)
			ir.append([])
		map.append(mr)
		walked.append(wr)
		items.append(ir)

	start = Vector2i(1, 1)
	exitp = Vector2i(W - 2, H - 2)
	player = start

	# 1) 自避骨架。搜索没撞到出口就退化成最短路——两者都是合法的自避路线。
	#    骨架长度要收着点：它全是安全地面，太长关卡就变成一片空地了。
	solution_path = []
	var skeleton := _make_skeleton(int(W * H * 0.18), int(W * H * 0.26))
	if skeleton.is_empty():
		skeleton = _fallback_skeleton()
	var on_skel := {}
	for p in skeleton:
		on_skel[p] = true
	if skeleton.is_empty():
		on_skel[start] = true
		on_skel[exitp] = true

	# 2) 骨架以外的地皮随机铺地形
	var pool: Array = []
	var weights := [
		[Data.Tile.FLOOR, 22], [Data.Tile.WALL, 44], [Data.Tile.THORN, 10],
		[Data.Tile.TREE, 6], [Data.Tile.FIRE, 8], [Data.Tile.WATER, 10],
	]
	for w in weights:
		for i in w[1]:
			pool.append(w[0])

	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			if on_skel.has(p) or p == start or p == exitp:
				map[y][x] = Data.Tile.FLOOR
			else:
				map[y][x] = pool[rng.randi() % pool.size()]
	map[exitp.y][exitp.x] = Data.Tile.EXIT

	# 3) 偏旁至少放一个在骨架上（保证可通），其余散在别处
	var rads: Array = Data.RADICAL_ORDER.duplicate()
	_shuffle(rads)
	var skel_mid: Array = []
	for p in skeleton:
		if p != start and p != exitp:
			skel_mid.append(p)
	var placed_on_skel := 0
	for k in mini(2, rads.size()):
		if skel_mid.is_empty():
			break
		var idx := rng.randi() % skel_mid.size()
		var p: Vector2i = skel_mid[idx]
		skel_mid.remove_at(idx)
		items[p.y][p.x].append({"kind": "radical", "id": rads[k]})
		placed_on_skel += 1
	if placed_on_skel > 0:
		solution_path = skeleton.duplicate()

	var others: Array = []
	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			if on_skel.has(p) or p == start or p == exitp:
				continue
			if map[y][x] == Data.Tile.WALL:
				continue
			others.append(p)
	_shuffle(others)
	# 骨架外再散两个偏旁当诱饵：路线选择才有意义
	for k in range(2, mini(4, rads.size())):
		if others.is_empty():
			break
		var p: Vector2i = others.pop_back()
		items[p.y][p.x].append({"kind": "radical", "id": rads[k]})
	var hz: Array = Data.HANZI_ORDER.duplicate()
	_shuffle(hz)
	for k in mini(2, hz.size()):
		if others.is_empty():
			break
		var p: Vector2i = others.pop_back()
		items[p.y][p.x].append({"kind": "hanzi", "id": hz[k]})


func _make_skeleton(target_len: int, max_len: int) -> Array:
	_sk_best = []
	_sk_nodes = 0
	_sk_target = target_len
	_sk_max = maxi(target_len + 2, max_len)
	var seen := {start: true}
	_sk_dfs(start, [start], seen)
	return _sk_best


var _sk_best: Array = []
var _sk_nodes := 0
var _sk_target := 0
var _sk_max := 0
const SK_NODE_BUDGET := 90000


func _sk_dfs(cur: Vector2i, path: Array, seen: Dictionary) -> void:
	_sk_nodes += 1
	if _sk_nodes > SK_NODE_BUDGET:
		return
	if cur == exitp and path.size() > _sk_best.size():
		_sk_best = path.duplicate()
		return
	if path.size() >= _sk_max:
		return          # 别让骨架把整张图都吃成安全地面
	var opts: Array = []
	for d in FOUR:
		var n: Vector2i = cur + d
		if in_bounds(n) and not seen.has(n):
			opts.append(n)
	_shuffle(opts)
	for n in opts:
		seen[n] = true
		path.append(n)
		_sk_dfs(n, path, seen)
		path.pop_back()
		seen.erase(n)
		if _sk_nodes > SK_NODE_BUDGET:
			return


func _fallback_skeleton() -> Array:
	## 保底：BFS 最短路，绝对是合法的自避路线。
	var prev := {}
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		if p == exitp:
			break
		for d in FOUR:
			var n: Vector2i = p + d
			if not in_bounds(n) or seen.has(n):
				continue
			seen[n] = true
			prev[n] = p
			q.append(n)
	if not seen.has(exitp):
		return []
	var path: Array = []
	var cur := exitp
	while cur != start:
		path.append(cur)
		cur = prev[cur]
	path.reverse()
	return path


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 400:
		log_lines = log_lines.slice(log_lines.size() - 400)
