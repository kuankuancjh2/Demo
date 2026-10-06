class_name Board
extends Control
## 纸面棋盘：手绘素材 + 你走过的「笔画」。
##
## 走过的格子会变成空白的纸 —— 地形消失了，只留下你画的那一笔。

var game: Game = null
var font: Font = null
var cell := 48.0
var cursor_cell := Vector2i(-1, -1)

var _tex_cache := {}


func _tex(n: String) -> Texture2D:
	if _tex_cache.has(n):
		return _tex_cache[n]
	var path := "res://textures/%s.png" % n
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[n] = t
	return t


func _draw() -> void:
	if game == null or font == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Data.C_PAPER)
	for y in game.H:
		for x in game.W:
			_draw_cell(x, y)
	_draw_trail()
	_draw_player()
	_draw_cursor()
	draw_rect(Rect2(Vector2.ZERO, size), Data.C_INK, false, 3.0)


func _draw_cell(x: int, y: int) -> void:
	var r := Rect2(Vector2(x, y) * cell, Vector2(cell, cell))

	if game.walked[y][x]:
		# 已经写过了：地形没了，只剩一张空纸
		draw_rect(r, Data.C_PAPER_DIM)
		draw_circle(r.get_center(), maxf(1.0, cell * 0.045), Data.C_INK_FAINT)
		return

	var t: int = game.map[y][x]
	var tint: Color = Data.TILE_TINT[t]
	var tex_name: String = Data.TILE_TEX[t]
	var tex := _tex(tex_name) if tex_name != "" else null
	if tex:
		# 素材是「白底黑线」，用 modulate 把白底染成地形色，黑线保持黑
		draw_texture_rect(tex, r.grow(-1.0), false, tint)
	else:
		draw_rect(r, tint)
		# 地面：只留一道极淡的格线，像纸上的暗格
		var g: Color = Data.C_INK_FAINT
		g.a = 0.30
		draw_rect(r, g, false, 1.0)

	if t == Data.Tile.EXIT:
		draw_rect(r.grow(-2.0), Data.C_GOLD, false, 3.0)

	# 地上的道具
	var stack: Array = game.items[y][x]
	if not stack.is_empty():
		var it: Dictionary = stack.back()
		var col: Color
		var glyph: String
		if it["kind"] == "radical":
			col = Data.RADICALS[it["id"]]["color"]
			glyph = Data.RADICALS[it["id"]]["char"]
		else:
			col = Data.C_GOLD
			glyph = Data.HANZI[it["id"]]["char"]
		var box := r.grow(-cell * 0.13)
		draw_rect(box, Color(1, 1, 1, 0.72))
		var ftex := _tex(Data.TEX_ITEM)
		if ftex:
			draw_texture_rect(ftex, box, false)
		_draw_center(glyph, r.get_center(), int(cell * 0.44), col)


func _draw_trail() -> void:
	if game.trail.size() < 2:
		return
	var w := maxf(3.0, cell * 0.17)
	for i in range(game.trail.size() - 1):
		var a: Vector2i = game.trail[i]
		var b: Vector2i = game.trail[i + 1]
		draw_line(_center(a), _center(b), Data.C_INK, w, true)
	var head: Vector2i = game.trail[0]
	draw_circle(_center(head), w * 0.5, Data.C_INK)


func _draw_player() -> void:
	var p := game.player
	var r := Rect2(Vector2(p) * cell, Vector2(cell, cell))
	var tex := _tex(Data.TEX_PLAYER)
	if tex:
		draw_texture_rect(tex, r.grow(-cell * 0.06), false)
	else:
		draw_circle(r.get_center(), cell * 0.34, Data.C_GOLD)
	# 当前落笔处圈一圈墨（描边，不遮住角色）
	draw_arc(r.get_center(), cell * 0.46, 0.0, TAU, 32, Data.C_INK, 3.0, true)


func _draw_cursor() -> void:
	if cursor_cell.x < 0:
		return
	var r := Rect2(Vector2(cursor_cell) * cell, Vector2(cell, cell))
	draw_rect(r.grow(-1.5), Data.C_BAD, false, 4.0)


func _center(p: Vector2i) -> Vector2:
	return Vector2(p) * cell + Vector2(cell, cell) * 0.5


func _draw_center(text: String, center: Vector2, fsize: int, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var asc := font.get_ascent(fsize)
	var desc := font.get_descent(fsize)
	var pos := Vector2(center.x - ts.x * 0.5, center.y - (asc + desc) * 0.5 + asc)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
