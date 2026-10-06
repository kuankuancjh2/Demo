class_name Solver
extends RefCounted
## 关卡求解器：验证每一关真的可通，并给出大致最少步数。
##
## 建模了所有确定性规则：自避路线、偏旁拾取与丢弃、工砸墙（双倍步耗，扔了就不耗）、
## 艹过树、石渡火水、火（烧相邻荆棘树木，自己 −1 血）、刂（清朝向一条线的荆棘），
## 以及刂拾取 −3 步、石每 3 格 +1 步。
## 「冫」有随机位移，不建模——依赖「冫」的关卡本求解器不作保证。

var W := 0
var H := 0
var start := Vector2i.ZERO
var exitp := Vector2i.ZERO
var step_budget := -1
var max_hp := 3

var base_map: Array = []
var base_rad: Array = []
var has_gong_somewhere := false
var has_cao_somewhere := false

var nodes := 0
var node_budget := 600000
var best: Array = []
var best_steps := 0
var budget_hit := false

# --- 搜索中的可变状态 ---
var cur_map: Array = []
var cur_pos := Vector2i.ZERO
var cur_facing := Vector2i(0, 1)
var visited: Array = []
var moves: Array = []
var cur_hp := 3
var cur_steps := 0
var since_shi := 0
var rad_count := 0
var has_gong := false
var has_cao := false
var has_shi := false
var has_huo := false
var has_dao := false
var cao_on := false
var shi_on := false


func setup_from_level(lv: Dictionary) -> void:
	var rows: Array = lv["map"]
	H = rows.size()
	W = 0
	for r in rows:
		W = maxi(W, String(r).length())
	step_budget = lv["steps"]
	max_hp = lv["hp"]
	base_map = []
	base_rad = []
	has_gong_somewhere = false
	has_cao_somewhere = false
	start = Vector2i(1, 1)
	exitp = Vector2i(W - 2, H - 2)
	for y in H:
		var line := String(rows[y])
		var mr: Array = []
		var rr: Array = []
		for x in W:
			var ch := "." if x >= line.length() else line[x]
			var cell: int = Data.Tile.FLOOR
			if Data.CH_LEGEND.has(ch):
				cell = Data.CH_LEGEND[ch]
			mr.append(cell)
			if ch == "S":
				start = Vector2i(x, y)
			elif ch == "E":
				exitp = Vector2i(x, y)
			var rid: String = Data.CH_RADICAL.get(ch, "")
			rr.append(rid)
			if rid == "gong":
				has_gong_somewhere = true
			elif rid == "cao":
				has_cao_somewhere = true
		base_map.append(mr)
		base_rad.append(rr)


func setup_from_game(g: Game) -> void:
	## 直接从一局随机关卡建题。步数不限，血量照抄。
	W = g.W
	H = g.H
	step_budget = -1
	max_hp = g.max_hp
	base_map = g.map.duplicate(true)
	base_rad = []
	has_gong_somewhere = false
	has_cao_somewhere = false
	start = g.start
	exitp = g.exitp
	for y in H:
		var rr: Array = []
		for x in W:
			var rid := ""
			for it in g.items[y][x]:
				if it["kind"] == "radical":
					rid = it["id"]
					break
			rr.append(rid)
			if rid == "gong":
				has_gong_somewhere = true
			elif rid == "cao":
				has_cao_somewhere = true
		base_rad.append(rr)


func solve() -> Dictionary:
	nodes = 0
	budget_hit = false
	best = []
	best_steps = 0
	cur_map = base_map.duplicate(true)
	visited = []
	for y in H:
		var row: Array = []
		for x in W:
			row.append(false)
		visited.append(row)
	cur_pos = start
	cur_facing = Vector2i(0, 1)
	visited[start.y][start.x] = true
	moves = []
	cur_hp = max_hp
	cur_steps = 0
	since_shi = 0
	rad_count = 0
	has_gong = false
	has_cao = false
	has_shi = false
	has_huo = false
	has_dao = false
	cao_on = false
	shi_on = false
	_grab(cur_pos, [])
	var ok := _dfs()
	return {"found": ok, "moves": best.duplicate(), "steps": best_steps,
		"nodes": nodes, "budget_hit": budget_hit}


func _grab(p: Vector2i, changed: Array) -> void:
	var id: String = base_rad[p.y][p.x]
	if id == "":
		return
	changed.append(p)
	rad_count += 1
	match id:
		"gong": has_gong = true
		"cao": has_cao = true
		"shi": has_shi = true
		"huo": has_huo = true
		"dao":
			has_dao = true
			cur_steps += 3      # 刂：拾取时 −3 步
		_:
			pass


func _ungrab(changed: Array) -> void:
	for i in range(changed.size() - 1, -1, -1):
		var p: Vector2i = changed[i]
		var id: String = base_rad[p.y][p.x]
		rad_count -= 1
		match id:
			"gong": has_gong = false
			"cao": has_cao = false
			"shi": has_shi = false
			"huo": has_huo = false
			"dao":
				has_dao = false
				cur_steps -= 3
			_:
				pass


func _move_cost() -> int:
	return 2 if has_gong else 1


# ---------------------------------------------------------- DFS

func _dfs() -> bool:
	nodes += 1
	if nodes > node_budget:
		budget_hit = true
		return false
	if cur_pos == exitp and rad_count > 0:
		best = moves.duplicate()
		best_steps = cur_steps
		return true
	if not _prune_ok():
		return false
	for d in _order_dirs():
		if _try_move(d):
			return true
	if _try_huo():
		return true
	if _try_dao():
		return true
	if _try_gong():
		return true
	if _try_cao():
		return true
	if _try_shi():
		return true
	if _try_drop_gong():
		return true
	return false


func _order_dirs() -> Array:
	var tgt := exitp
	if rad_count == 0:
		var r := _nearest_radical()
		if r.x >= 0:
			tgt = r
	var out: Array = []
	for d in Game.FOUR:
		out.append({"d": d, "k": (cur_pos + d - tgt).length_squared()})
	out.sort_custom(func(a, b): return a["k"] < b["k"])
	var ds: Array = []
	for o in out:
		ds.append(o["d"])
	return ds


func _can_step(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
		return false
	if visited[p.y][p.x]:
		return false
	var t: int = cur_map[p.y][p.x]
	if t == Data.Tile.WALL:
		return false
	if t == Data.Tile.TREE and not cao_on:
		return false
	return true


func _try_move(d: Vector2i) -> bool:
	var np := cur_pos + d
	if not _can_step(np):
		return false
	var t: int = cur_map[np.y][np.x]

	var cost := _move_cost()
	if has_shi and (since_shi + 1) % 3 == 0:
		cost += 1
	if step_budget >= 0 and cur_steps + cost > step_budget:
		return false

	var dmg := 0
	if t == Data.Tile.THORN:
		dmg = 1
	elif t == Data.Tile.FIRE and not shi_on:
		dmg = 1
	elif t == Data.Tile.WATER and not (shi_on or cao_on):
		dmg = 1
	if cur_hp - dmg <= 0:
		return false

	# --- 进入 ---
	var changed: Array = []
	var sc := _save_scalars()
	visited[np.y][np.x] = true
	cur_pos = np
	cur_facing = d
	cur_steps += cost
	if has_shi:
		since_shi += 1
	cur_hp -= dmg
	moves.append(d)
	_grab(np, changed)

	if _dfs():
		return true

	# --- 撤回 ---
	_ungrab(changed)
	moves.pop_back()
	cur_hp += dmg
	if has_shi:
		since_shi -= 1
	cur_steps -= cost
	_restore_scalars(sc)
	visited[np.y][np.x] = false
	return false


func _save_scalars() -> Array:
	return [cur_pos, cur_facing, has_gong, has_cao, has_shi, has_huo, has_dao, cao_on, shi_on, rad_count]


func _restore_scalars(s: Array) -> void:
	cur_pos = s[0]
	cur_facing = s[1]
	has_gong = s[2]
	has_cao = s[3]
	has_shi = s[4]
	has_huo = s[5]
	has_dao = s[6]
	cao_on = s[7]
	shi_on = s[8]
	rad_count = s[9]


func _try_huo() -> bool:
	if not has_huo or cur_hp <= 1:
		return false
	var cost := _move_cost()
	if step_budget >= 0 and cur_steps + cost > step_budget:
		return false
	var hit: Array = []
	for dd in Game.EIGHT:
		var p: Vector2i = cur_pos + dd
		if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
			continue
		var t: int = cur_map[p.y][p.x]
		if t == Data.Tile.THORN or t == Data.Tile.TREE:
			hit.append(p)
	if hit.is_empty():
		return false
	for p in hit:
		cur_map[p.y][p.x] = Data.Tile.FLOOR
	cur_steps += cost
	cur_hp -= 1
	if _dfs():
		return true
	cur_hp += 1
	cur_steps -= cost
	for p in hit:
		cur_map[p.y][p.x] = base_tile(p)
	return false


func base_tile(p: Vector2i) -> int:
	return base_map[p.y][p.x]


func _try_dao() -> bool:
	if not has_dao:
		return false
	var cost := _move_cost()
	if step_budget >= 0 and cur_steps + cost > step_budget:
		return false
	var hit: Array = []
	var p := cur_pos + cur_facing
	while p.x >= 0 and p.y >= 0 and p.x < W and p.y < H and cur_map[p.y][p.x] != Data.Tile.WALL:
		if cur_map[p.y][p.x] == Data.Tile.THORN:
			hit.append(p)
		p += cur_facing
	if hit.is_empty():
		return false
	for q in hit:
		cur_map[q.y][q.x] = Data.Tile.FLOOR
	cur_steps += cost
	if _dfs():
		return true
	cur_steps -= cost
	for q in hit:
		cur_map[q.y][q.x] = base_tile(q)
	return false


func _try_gong() -> bool:
	if not has_gong:
		return false
	var cost := _move_cost()
	if step_budget >= 0 and cur_steps + cost > step_budget:
		return false
	for d in Game.EIGHT:
		var np: Vector2i = cur_pos + d
		if np.x < 0 or np.y < 0 or np.x >= W or np.y >= H:
			continue
		if cur_map[np.y][np.x] != Data.Tile.WALL:
			continue
		cur_map[np.y][np.x] = Data.Tile.FLOOR
		cur_steps += cost
		if _dfs():
			return true
		cur_steps -= cost
		cur_map[np.y][np.x] = base_tile(np)
	return false


func _try_cao() -> bool:
	if not has_cao or cao_on:
		return false
	var cost := _move_cost()
	if step_budget >= 0 and cur_steps + cost > step_budget:
		return false
	cao_on = true
	cur_steps += cost
	if _dfs():
		return true
	cur_steps -= cost
	cao_on = false
	return false


func _try_shi() -> bool:
	if not has_shi or shi_on:
		return false
	var cost := _move_cost()
	if step_budget >= 0 and cur_steps + cost > step_budget:
		return false
	shi_on = true
	cur_steps += cost
	if _dfs():
		return true
	cur_steps -= cost
	shi_on = false
	return false


func _try_drop_gong() -> bool:
	## 关键一手：把「工」扔掉，摆脱它的双倍步耗——但背包里得还有别的字。
	if not has_gong or rad_count < 2:
		return false
	has_gong = false
	rad_count -= 1
	if _dfs():
		return true
	rad_count += 1
	has_gong = true
	return false


# ---------------------------------------------------------- 剪枝

func _passable_prune(p: Vector2i) -> bool:
	if visited[p.y][p.x]:
		return false
	var t: int = cur_map[p.y][p.x]
	# 宁可放宽：只要这一关里还存在「工 / 艹」，就认为墙和树以后打得开
	if t == Data.Tile.WALL:
		return has_gong or has_gong_somewhere
	if t == Data.Tile.TREE:
		return cao_on or has_cao or has_cao_somewhere
	return true


func _prune_ok() -> bool:
	var dist := {}
	var q: Array = [cur_pos]
	dist[cur_pos] = 0
	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		for d in Game.FOUR:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
				continue
			if dist.has(n) or not _passable_prune(n):
				continue
			dist[n] = dist[p] + 1
			q.append(n)

	if not dist.has(exitp):
		return false
	if rad_count == 0:
		var any := false
		for p in dist.keys():
			if base_rad[p.y][p.x] != "":
				any = true
				break
		if not any:
			return false
	if step_budget >= 0:
		var need := 99999
		if rad_count > 0:
			need = dist.get(exitp, 99999)
		else:
			for p in dist.keys():
				if base_rad[p.y][p.x] != "":
					need = mini(need, dist[p])
		if need < 99999 and cur_steps + need > step_budget:
			return false
	return true


func _nearest_radical() -> Vector2i:
	var bp := Vector2i(-1, -1)
	var bd := 99999
	for y in H:
		for x in W:
			if base_rad[y][x] != "" and not visited[y][x]:
				var d: int = absi(x - cur_pos.x) + absi(y - cur_pos.y)
				if d < bd:
					bd = d
					bp = Vector2i(x, y)
	return bp
