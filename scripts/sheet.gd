extends Control
## 开发工具：把 textures/ 下所有素材铺成一张联络表，方便挑图 / 给美术替换时对照。
##
##   Tools\Godot_console.exe res://scenes/sheet.tscn -- --autoshot=res://_shots/sheet.png

const CELL := 88.0
const COLS := 12
const ROWS_PER_PAGE := 5

var font: Font
var shots: Array = []
var frames := 30
var path := ""
var page := 0


func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Consolas", "sans-serif"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			path = a.substr(11)
		elif a.begins_with("--shot-frames="):
			frames = int(a.substr(14))
		elif a.begins_with("--page="):
			page = int(a.substr(7))

	var dir := DirAccess.open("res://textures")
	var names: Array = []
	if dir:
		for f in dir.get_files():
			if f.ends_with(".png"):
				names.append(f.get_basename())
	names.sort()

	var start := page * COLS * ROWS_PER_PAGE
	var end := mini(names.size(), start + COLS * ROWS_PER_PAGE)
	size = Vector2(COLS * CELL, ROWS_PER_PAGE * CELL)
	for i in range(start, end):
		shots.append({"name": names[i], "tex": load("res://textures/%s.png" % names[i])})
	print("[sheet] page=%d 共 %d 张，本页 %d 张（总 %d）" % [page, end - start, shots.size(), names.size()])


func _process(_d: float) -> void:
	if path == "":
		return
	frames -= 1
	if frames > 0:
		return
	var p := path
	path = ""
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(p)
	print("[sheet] ", p, " textures=", shots.size())
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f4f1e8"))
	for i in shots.size():
		var col := i % COLS
		var row := i / COLS
		var o := Vector2(col * CELL, row * CELL)
		var tex: Texture2D = shots[i]["tex"]
		if tex:
			draw_texture_rect(tex, Rect2(o + Vector2(14, 6), Vector2(72, 72)), false)
		draw_string(font, o + Vector2(6, 96), String(shots[i]["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, CELL - 8, 11, Color("#333"))
