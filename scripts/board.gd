class_name Board
extends Control
## 只负责画棋盘：地块、迷雾、道具、玩家、选择光标。

const CELL := 54.0

var game: Game = null
var font: Font = null
var cursor_cell := Vector2i(-1, -1)   # 选择模式下的高亮格


func _draw() -> void:
	if game == null or font == null:
		return
	# 整个棋盘先铺一层底色 + 外框，让迷雾里的迷宫范围看得出来
	draw_rect(Rect2(Vector2.ZERO, size), Data.C_FOG)
	for y in Game.H:
		for x in Game.W:
			_draw_cell(x, y)
	draw_rect(Rect2(Vector2.ZERO, size), Data.C_LINE, false, 2.0)
	_draw_cursor()
	_draw_player()


func _draw_cell(x: int, y: int) -> void:
	var r := Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL))

	if not game.explored[y][x]:
		# 未探索：只留一格虚线感，不透露内容
		var g: Color = Data.C_LINE
		g.a = 0.22
		draw_rect(r, g, false, 1.0)
		return

	var center := r.get_center()

	var vis: bool = game.visible[y][x]
	var dim := 1.0 if vis else 0.32

	var t: int = game.map[y][x]
	draw_rect(r, Data.TILE_COLOR[t] * dim)

	# 网格线
	var line: Color = Data.C_LINE
	line.a = 0.5 * dim
	draw_rect(r, line, false, 1.0)

	# 瓦砾（工 的痕迹）
	if game.rubble[y][x]:
		draw_circle(center, 3.5, Color(0.62, 0.56, 0.44, 0.55 * dim))

	# 地块字
	var g: String = Data.TILE_GLYPH[t]
	if g != "":
		var gc: Color = Data.TILE_GLYPH_COLOR[t]
		gc.a = dim
		_draw_center(g, center, 26, gc)

	# 出口加个描边，远远就能看见
	if t == Data.Tile.EXIT and vis:
		draw_rect(r.grow(-3), Color(1.0, 0.92, 0.62, 0.55), false, 2.0)

	# 道具
	var stack: Array = game.items[y][x]
	if not stack.is_empty() and not (game.player == Vector2i(x, y)):
		var it: Dictionary = stack.back()
		var col: Color
		var glyph: String
		if it["kind"] == "radical":
			col = Data.RADICALS[it["id"]]["color"]
			glyph = Data.RADICALS[it["id"]]["char"]
		else:
			col = Data.C_ACCENT
			glyph = Data.HANZI[it["id"]]["char"]
		var cc := col
		cc.a = dim
		# 底板，让字在杂乱地形上也能看清
		var box := Rect2(center - Vector2(17, 17), Vector2(34, 34))
		draw_rect(box, Color(0.03, 0.03, 0.06, 0.62 * dim), true)
		draw_rect(box, cc, false, 1.5)
		_draw_center(glyph, center, 24, cc)
		if stack.size() > 1:
			_draw_center("+%d" % (stack.size() - 1), center + Vector2(15, 15), 11, cc)


func _draw_player() -> void:
	var p := game.player
	var r := Rect2(Vector2(p) * CELL + Vector2(5, 5), Vector2(CELL - 10, CELL - 10))
	draw_rect(r, Data.C_PLAYER)
	draw_rect(r, Color(1, 1, 1, 0.85), false, 2.0)
	_draw_center("莫", r.get_center(), 30, Data.C_PLAYER_TEXT)
	# 脚下有东西时给个角标，免得被「莫」盖住看不见
	if not game.ground_items(p).is_empty():
		var c := r.position + Vector2(r.size.x - 9, 9)
		draw_circle(c, 6.0, Data.C_ACCENT)


func _draw_cursor() -> void:
	if cursor_cell.x < 0:
		return
	var r := Rect2(Vector2(cursor_cell) * CELL, Vector2(CELL, CELL))
	draw_rect(r.grow(-2), Data.C_ACCENT, false, 3.0)


func _draw_center(text: String, center: Vector2, fsize: int, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var asc := font.get_ascent(fsize)
	var desc := font.get_descent(fsize)
	var pos := Vector2(center.x - ts.x * 0.5, center.y - (asc + desc) * 0.5 + asc)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
