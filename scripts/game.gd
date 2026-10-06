class_name Game
extends RefCounted
## 《莫下面一个空》的全部游戏规则。
## 只依赖 Data（autoload），不依赖任何 UI —— 便于用 --selftest 无头跑。

const W := 11
const H := 11

const BASE_HP := 3
const BASE_STEPS := 3

enum State { PLAYING, WON, DEAD }

var rng := RandomNumberGenerator.new()

# 地图数据：都是 [y][x] 的二维数组
var map: Array = []      # -> Data.Tile
var explored: Array = [] # -> bool
var visible: Array = []  # -> bool
var items: Array = []    # -> Array[Dictionary]，地上可叠放
var rubble: Array = []   # -> bool，工 留下的瓦砾

# 玩家
var player := Vector2i(1, 1)
var facing := Vector2i(0, 1)
var hp := BASE_HP
var max_hp := BASE_HP
var turn := 1
var steps := 0
var bag: Array = []      # 偏旁 id，按拾取顺序；bag[0] 决定结局
var buffs: Array = []    # 已获得的汉字 id

var revive_used := false
var pass_fire_water := false  # 石：本回合
var pass_tree_water := false  # 艹：本回合

var state := State.PLAYING
var ending: Dictionary = {}
var log_lines: Array = []
var seed_used := 0

# 四方向 / 八方向
var FOUR: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
var EIGHT: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


# ============================================================ 开局

func new_game(p_seed: int = -1) -> void:
	if p_seed < 0:
		p_seed = randi() & 0x7fffffff
	seed_used = p_seed
	rng.seed = p_seed

	hp = BASE_HP
	max_hp = BASE_HP
	turn = 1
	bag = []
	buffs = []
	revive_used = false
	pass_fire_water = false
	pass_tree_water = false
	state = State.PLAYING
	ending = {}
	log_lines = []

	_generate_map()
	update_vision()
	steps = max_steps()

	_log("你在迷宫的左上角醒来。出口「门」在右下角，活着走出去。")
	_log("地上散落着偏旁与汉字，踩上去按 F 拾取。")
	_log("带哪个偏旁走到出口，结局就定格成哪个字；空手走出去则是「空」。")


# ============================================================ 派生数值

func has_buff(id: String) -> bool:
	return buffs.has(id)


func vision_extent() -> int:
	return 3 if has_buff("mo_ri") else 2   # 5×5 → 7×7


func max_steps() -> int:
	var s := BASE_STEPS
	if has_buff("mo_ma"):
		s += 2
	if bag.has("dao"):
		s -= 1
	return maxi(1, s)


func bag_capacity() -> int:
	return 1 if bag.has("feng") else 2


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H


func tile_at(p: Vector2i) -> int:
	return map[p.y][p.x]


func update_vision() -> void:
	for y in H:
		for x in W:
			visible[y][x] = false
	var e := vision_extent()
	for y in range(maxi(0, player.y - e), mini(H, player.y + e + 1)):
		for x in range(maxi(0, player.x - e), mini(W, player.x + e + 1)):
			visible[y][x] = true
			explored[y][x] = true


# ============================================================ 移动

func can_enter(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	return tile_at(p) != Data.Tile.WALL


func step_cost(p: Vector2i) -> int:
	var c := 1
	if tile_at(p) == Data.Tile.TREE and not pass_tree_water:
		c = 2
	if rubble[p.y][p.x]:
		c += 1
	return c


func move(dir: Vector2i) -> bool:
	if state != State.PLAYING:
		return false
	var np := player + dir
	if not can_enter(np):
		_log("那里过不去。")
		return false
	var cost := step_cost(np)
	if steps < cost:
		_log("步数不够（需要 %d 步，剩 %d）。" % [cost, steps])
		return false

	facing = dir
	steps -= cost
	player = np
	_on_enter_cell()
	update_vision()
	if state == State.PLAYING and steps <= 0:
		begin_next_turn()
	return true


func _on_enter_cell() -> void:
	# 工：走过的地块留下瓦砾
	if bag.has("gong") and tile_at(player) != Data.Tile.EXIT and not rubble[player.y][player.x]:
		rubble[player.y][player.x] = true
		_log("「工」在脚下留下了瓦砾（再次经过需多花 1 步）。")

	_apply_tile_damage(player)

	if state == State.PLAYING and tile_at(player) == Data.Tile.EXIT:
		_win()


func _apply_tile_damage(p: Vector2i) -> void:
	match tile_at(p):
		Data.Tile.THORN:
			if has_buff("mo_jin"):
				return
			_damage(1, "荆棘划伤了你")
		Data.Tile.FIRE:
			if has_buff("mo_shui") or pass_fire_water:
				return
			_damage(1, "火焰灼伤了你")
		Data.Tile.WATER:
			if pass_fire_water or pass_tree_water:
				return
			_damage(1, "寒水冻伤了你")


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


# ============================================================ 回合

func begin_next_turn() -> void:
	if state != State.PLAYING:
		return
	turn += 1
	pass_fire_water = false
	pass_tree_water = false
	_apply_passives()
	if state != State.PLAYING:
		return
	steps = max_steps()
	update_vision()


func end_turn_early() -> void:
	if state != State.PLAYING:
		return
	_log("你停下脚步。")
	begin_next_turn()


func _apply_passives() -> void:
	# 石：每回合被迫向右走一格
	if bag.has("shi"):
		_forced_step(Vector2i(1, 0))
		if state != State.PLAYING:
			return

	# 艹：周围八格有火就受伤
	if bag.has("cao") and _fire_nearby():
		_damage(1, "「艹」引火烧身")
		if state != State.PLAYING:
			return

	# 模：每 3 回合复制一个背包道具
	if has_buff("mo_mu") and turn % 3 == 0:
		_duplicate_item()


func _fire_nearby() -> bool:
	for d in EIGHT:
		var p := player + d
		if in_bounds(p) and tile_at(p) == Data.Tile.FIRE:
			return true
	return false


func _forced_step(dir: Vector2i) -> void:
	var np := player + dir
	if not in_bounds(np) or tile_at(np) == Data.Tile.WALL or tile_at(np) == Data.Tile.TREE:
		_log("「石」拖着你向右，但被挡住了。")
		return
	player = np
	_log("「石」拖着你向右走了一格。")
	_apply_tile_damage(player)
	if state == State.PLAYING and tile_at(player) == Data.Tile.EXIT:
		_win()


func _duplicate_item() -> void:
	if bag.is_empty():
		return
	if bag.size() >= bag_capacity():
		_log("「模」想复制道具，但背包已满。")
		return
	var id: String = bag[rng.randi() % bag.size()]
	bag.append(id)
	_log("「模」复制了一个「%s」。" % Data.RADICALS[id]["char"])


# ============================================================ 拾取 / 丢弃

func ground_items(p: Vector2i) -> Array:
	return items[p.y][p.x]


func pickup() -> bool:
	if state != State.PLAYING:
		return false
	var stack: Array = items[player.y][player.x]
	if stack.is_empty():
		_log("这里没有可以拾取的东西。")
		return false

	var it: Dictionary = stack.back()
	if it["kind"] == "hanzi":
		stack.pop_back()
		_gain_hanzi(it["id"])
		return true

	if bag.size() >= bag_capacity():
		_log("背包满了（容量 %d）。按 Q / E 丢掉一个再来。" % bag_capacity())
		return false

	stack.pop_back()
	bag.append(it["id"])
	var d: Dictionary = Data.RADICALS[it["id"]]
	_log("拾取偏旁「%s」——%s。" % [d["char"], d["active"]])
	_log("代价：%s。带着它走到出口，结局将定格为「%s」。" % [d["passive"], d["ending"]])
	if it["id"] == "feng":
		_log("「风」收紧了你的背包：容量降为 1。")
	return true


func drop_item(slot: int) -> bool:
	if state != State.PLAYING or slot < 0 or slot >= bag.size():
		return false
	var id: String = bag[slot]
	bag.remove_at(slot)
	items[player.y][player.x].append({"kind": "radical", "id": id})
	_log("丢下了「%s」。" % Data.RADICALS[id]["char"])
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
			steps += 2
			_log("步数上限提升，本回合立即 +2 步。")
		"mo_ri":
			update_vision()
		_:
			pass


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
	if steps <= 0:
		_log("本回合没有步数了。")
		return false

	var id: String = bag[slot]
	if needs_target(slot) and target == Vector2i(-1, -1):
		return false   # 交给 UI 进选择模式

	steps -= 1
	match id:
		"huo": _eff_huo()
		"dao": _eff_dao()
		"bing": _eff_bing()
		"gong": _eff_gong(target)
		"shi": _eff_shi()
		"feng": _eff_feng(target)
		"cao": _eff_cao()

	if state == State.PLAYING and steps <= 0:
		begin_next_turn()
	return true


func _eff_huo() -> void:
	var affected: Array = []
	for d in EIGHT:
		var p := player + d
		if in_bounds(p) and (tile_at(p) == Data.Tile.THORN or tile_at(p) == Data.Tile.TREE):
			affected.append(p)
	if affected.is_empty():
		_log("「火」烧了个空——周围没有荆棘或树木。")
		return
	var burnt := 0
	var sparked := 0
	for p in affected:
		map[p.y][p.x] = Data.Tile.FLOOR
		burnt += 1
		if rng.randf() < 0.3:
			map[p.y][p.x] = Data.Tile.FIRE
			sparked += 1
	_log("「火」烧掉了 %d 格荆棘/树木，其中 %d 格燃成了新的火地块。" % [burnt, sparked])
	if sparked > 0:
		_log("火势不会认人——小心别把自己围进去。")
	update_vision()


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
	update_vision()


func _eff_bing() -> void:
	var out := 0
	for y in range(maxi(0, player.y - 2), mini(H, player.y + 3)):
		for x in range(maxi(0, player.x - 2), mini(W, player.x + 3)):
			if map[y][x] == Data.Tile.FIRE:
				map[y][x] = Data.Tile.FLOOR
				out += 1
	if out > 0:
		_log("「冫」浇灭了 %d 格火，地面恢复如常。" % out)
	else:
		_log("「冫」浇了个空——附近没有火。")

	# 代价：随机方向被推 1d4 格
	var dir: Vector2i = FOUR[rng.randi() % FOUR.size()]
	var dist := rng.randi_range(1, 4)
	var moved := 0
	for i in dist:
		var np := player + dir
		if not in_bounds(np):
			break
		if tile_at(np) == Data.Tile.WALL or tile_at(np) == Data.Tile.TREE:
			break
		player = np
		moved += 1
	facing = dir
	if moved > 0:
		_log("反噬：你被朝%s推了 %d 格。" % [dir_name(dir), moved])
		_apply_tile_damage(player)
		if state == State.PLAYING and tile_at(player) == Data.Tile.EXIT:
			_win()
	update_vision()


func _eff_gong(target: Vector2i) -> void:
	if not in_bounds(target) or tile_at(target) != Data.Tile.WALL:
		_log("「工」需要指定一格障碍物。")
		return
	map[target.y][target.x] = Data.Tile.FLOOR
	_log("「工」砸碎了 (%d, %d) 的障碍物。" % [target.x, target.y])
	update_vision()


func _eff_shi() -> void:
	pass_fire_water = true
	_log("「石」生效：本回合可以自由通过火与水。")


func _eff_cao() -> void:
	pass_tree_water = true
	_log("「艹」生效：本回合可以自由通过树木与水。")


func _eff_feng(target: Vector2i) -> void:
	if not in_bounds(target) or items[target.y][target.x].is_empty():
		_log("「风」需要指定一格有道具的地方。")
		return
	var stack: Array = items[target.y][target.x]
	var it: Dictionary = stack.back()

	if it["kind"] == "hanzi":
		stack.pop_back()
		_log("「风」卷来了汉字。")
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


# ============================================================ 胜负

func _win() -> void:
	state = State.WON
	ending = _build_ending()
	_log("你走到了出口。")

func force_ending() -> void:
	## 调试用：直接结算当前背包的结局。
	state = State.WON
	ending = _build_ending()


func _build_ending() -> Dictionary:
	var key := "kong"
	if not bag.is_empty():
		key = bag[0]
	var e: Dictionary = Data.ENDINGS[key].duplicate(true)
	e["glyph"] = Data.ENDINGS[key]["glyph"]
	e["pair"] = bag.size() > 1
	if bag.size() > 1:
		e["pair_char"] = Data.RADICALS[bag[1]]["char"]
	return e


func _die() -> void:
	state = State.DEAD
	var e: Dictionary = Data.ENDINGS["dead"].duplicate(true)
	e["glyph"] = "" if bag.is_empty() else Data.RADICALS[bag[0]]["char"]
	e["pair"] = false
	ending = e
	_log("你倒下了。")


# ============================================================ 地图生成

func _generate_map() -> void:
	map = []
	explored = []
	visible = []
	items = []
	rubble = []
	for y in H:
		var mr: Array = []
		var er: Array = []
		var vr: Array = []
		var ir: Array = []
		var rr: Array = []
		for x in W:
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				mr.append(Data.Tile.WALL)
			else:
				mr.append(Data.Tile.FLOOR)
			er.append(false)
			vr.append(false)
			ir.append([])
			rr.append(false)
		map.append(mr)
		explored.append(er)
		visible.append(vr)
		items.append(ir)
		rubble.append(rr)

	var start := Vector2i(1, 1)
	var exitp := Vector2i(W - 2, H - 2)
	player = start
	facing = Vector2i(0, 1)

	# 1) 随机散布地形
	var weights := [
		[Data.Tile.FLOOR, 30],
		[Data.Tile.THORN, 18],
		[Data.Tile.TREE, 7],
		[Data.Tile.WALL, 14],
		[Data.Tile.FIRE, 8],
		[Data.Tile.WATER, 13],
	]
	var pool: Array = []
	for w in weights:
		for i in w[1]:
			pool.append(w[0])
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var p := Vector2i(x, y)
			if p == exitp:
				continue
			if (p - start).length_squared() < 4:
				continue          # 出生点周围留空
			map[y][x] = pool[rng.randi() % pool.size()]

	# 2) 随机游走挖通一条从出生点到出口的路
	var cur := start
	var guard := 0
	while cur != exitp and guard < 3000:
		guard += 1
		map[cur.y][cur.x] = Data.Tile.FLOOR
		var dx := _sgn(exitp.x - cur.x)
		var dy := _sgn(exitp.y - cur.y)
		var choices: Array = []
		if dx != 0:
			choices.append(Vector2i(dx, 0))
			choices.append(Vector2i(dx, 0))
		if dy != 0:
			choices.append(Vector2i(0, dy))
			choices.append(Vector2i(0, dy))
		for i in 3:
			choices.append(FOUR[rng.randi() % FOUR.size()])
		var nxt: Vector2i = cur + choices[rng.randi() % choices.size()]
		nxt.x = clampi(nxt.x, 1, W - 2)
		nxt.y = clampi(nxt.y, 1, H - 2)
		cur = nxt

	map[start.y][start.x] = Data.Tile.FLOOR
	map[exitp.y][exitp.x] = Data.Tile.EXIT
	# 出口周围别被墙围死
	for d in EIGHT:
		var p := exitp + d
		if in_bounds(p) and tile_at(p) == Data.Tile.WALL:
			map[p.y][p.x] = Data.Tile.FLOOR

	# 3) 在「可达且不是出生点/出口」的地面上放道具
	var reach := reachable_from(start)
	var spots: Array = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if not reach[y][x]:
				continue
			var p := Vector2i(x, y)
			if p == start or p == exitp:
				continue
			if tile_at(p) != Data.Tile.FLOOR:
				continue
			if (p - start).length_squared() < 5:
				continue
			spots.append(p)
	_shuffle(spots)

	# 保证出口本身一定可达（挖路已保证，这里只是双保险）
	if not reach[exitp.y][exitp.x]:
		map[exitp.y][exitp.x] = Data.Tile.FLOOR
	# 兜底：万一一个空位都没有，就地铺几格
	if spots.is_empty():
		for y in range(1, H - 1):
			for x in range(1, W - 1):
				if map[y][x] == Data.Tile.WALL:
					map[y][x] = Data.Tile.FLOOR
					spots.append(Vector2i(x, y))

	var rad_ids: Array = Data.RADICAL_ORDER.duplicate()
	_shuffle(rad_ids)
	for i in mini(4, rad_ids.size()):
		if spots.is_empty():
			break
		var p: Vector2i = spots.pop_back()
		items[p.y][p.x].append({"kind": "radical", "id": rad_ids[i]})

	var hz_ids: Array = Data.HANZI_ORDER.duplicate()
	_shuffle(hz_ids)
	for i in mini(2, hz_ids.size()):
		if spots.is_empty():
			break
		var p: Vector2i = spots.pop_back()
		items[p.y][p.x].append({"kind": "hanzi", "id": hz_ids[i]})


func find_path(from: Vector2i, to: Vector2i) -> Array:
	## 四方向 BFS，只把障碍物当墙。返回不含起点的格子序列；不可达则返回空。
	var prev := {}
	var seen := {from: true}
	var q: Array = [from]
	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		if p == to:
			break
		for d in FOUR:
			var n: Vector2i = p + d
			if not in_bounds(n) or seen.has(n):
				continue
			if tile_at(n) == Data.Tile.WALL:
				continue
			seen[n] = true
			prev[n] = p
			q.append(n)
	if not seen.has(to):
		return []
	var path: Array = []
	var cur := to
	while cur != from:
		path.append(cur)
		cur = prev[cur]
	path.reverse()
	return path


func tile_danger(p: Vector2i) -> int:
	## 走这一格的「痛感」，只用于寻路评估（不参与实际结算）。
	match tile_at(p):
		Data.Tile.THORN:
			return 0 if has_buff("mo_jin") else 12
		Data.Tile.FIRE:
			return 0 if has_buff("mo_shui") else 12
		Data.Tile.WATER:
			return 12
		Data.Tile.TREE:
			return 3
		_:
			return 1


func find_safe_path(from: Vector2i, to: Vector2i) -> Array:
	## 会绕开火/水/荆棘的路径。用来评估「认真玩的玩家」的通关率。
	var INF := 99999
	var dist := {}
	var prev := {}
	for y in H:
		for x in W:
			dist[Vector2i(x, y)] = INF
	dist[from] = 0
	var changed := true
	var guard := 0
	while changed and guard < 500:
		guard += 1
		changed = false
		for y in H:
			for x in W:
				var p := Vector2i(x, y)
				if dist[p] >= INF:
					continue
				for d in FOUR:
					var n: Vector2i = p + d
					if not in_bounds(n) or tile_at(n) == Data.Tile.WALL:
						continue
					var nd: int = dist[p] + tile_danger(n)
					if nd < dist[n]:
						dist[n] = nd
						prev[n] = p
						changed = true
	if dist[to] >= INF:
		return []
	var path: Array = []
	var cur := to
	while cur != from:
		path.append(cur)
		if not prev.has(cur):
			return []
		cur = prev[cur]
	path.reverse()
	return path


func reachable_from(start: Vector2i) -> Array:
	var seen: Array = []
	for y in H:
		var row: Array = []
		for x in W:
			row.append(false)
		seen.append(row)
	var q: Array = [start]
	seen[start.y][start.x] = true
	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		for d in FOUR:
			var n := p + d
			if not in_bounds(n) or seen[n.y][n.x]:
				continue
			if tile_at(n) == Data.Tile.WALL:
				continue
			seen[n.y][n.x] = true
			q.append(n)
	return seen


func _sgn(v: int) -> int:
	if v > 0:
		return 1
	if v < 0:
		return -1
	return 0


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _log(s: String) -> void:
	log_lines.append("[%d] %s" % [turn, s])
	if log_lines.size() > 400:
		log_lines = log_lines.slice(log_lines.size() - 400)


func dir_name(d: Vector2i) -> String:
	if d == Vector2i(0, -1):
		return "上"
	if d == Vector2i(0, 1):
		return "下"
	if d == Vector2i(-1, 0):
		return "左"
	if d == Vector2i(1, 0):
		return "右"
	return "?"
