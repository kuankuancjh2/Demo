extends Control
## 《莫下面一个空》主控制器：标题/选关、游戏界面、输入、调试参数。
##
## 调试参数（写在 `--` 之后）：
##   --levels               求解所有手设计关卡，验证每一关可通
##   --selftest=200         随机关卡跑 200 次随机操作，检查不崩
##   --autoshot=x.png       截图后退出（配 --scenario / --keys）
##   --scenario=title|play|win|fail|select
##   --keys=right,right,f   把合成按键推进真实输入管线

const VIEW_W := 1240.0
const VIEW_H := 760.0
const BOARD_AREA := Rect2(24, 24, 656, 672)
const SIDE := Rect2(700, 24, 516, 712)
const COLS_PER_ROW := 3

enum Screen { TITLE, PLAY }

var game: Game
var board: Board
var font: Font
var screen := Screen.TITLE
var completed := {}
var progress_path := "user://mozu_progress.cfg"

# --- UI ---
var title_root: Control
var play_root: Control
var level_buttons: Array = []
var lbl_level: Label
var lbl_hint: Label
var lbl_hp: Label
var lbl_steps: Label
var lbl_buffs: Label
var lbl_bag: Label
var combo_slot: Label
var combo_slot2: Label
var combo_note: Label
var slots: Array = []
var log_view: RichTextLabel
var lbl_prompt: Label
var overlay: Control
var ov_glyph: Label
var ov_title: Label
var ov_text: Label
var ov_hint: Label
var sel_level := 0

# --- 选择模式 ---
var targeting := false
var target_slot := -1
var target_list: Array = []
var target_idx := 0

# --- 调试 ---
var autoshot := ""
var shot_frames := 34
var scenario := ""
var pending_keys: Array = []
var trace_input := false
var selftest_n := 0
var run_levels_test := false
var random_seed_arg := -1
var dev_mode := false      # 带任何调试参数时为 true：不写存档
var dump_random := false
var random_solve_n := 0

const KEY_NAMES := {
	"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
	"w": KEY_W, "a": KEY_A, "s": KEY_S, "d": KEY_D,
	"f": KEY_F, "q": KEY_Q, "e": KEY_E, "r": KEY_R, "z": KEY_Z, "n": KEY_N,
	"1": KEY_1, "2": KEY_2, "escape": KEY_ESCAPE,
	"space": KEY_SPACE, "enter": KEY_ENTER,
}


func _ready() -> void:
	font = _make_font()
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 15
	theme = th

	_parse_args()
	_load_progress()

	game = Game.new()
	game.load_level(0)

	_build_title()
	_build_play()
	_build_overlay()
	_show_title()

	if dump_random:
		_dump_random()
	elif random_solve_n > 0:
		_test_random_solve(random_solve_n)
	elif run_levels_test:
		_test_levels()
	elif selftest_n > 0:
		_run_selftest(selftest_n)
	else:
		_apply_scenario()


func _process(_d: float) -> void:
	if not pending_keys.is_empty() and shot_frames <= 26:
		var k: Array = pending_keys
		pending_keys = []
		_push_keys(k)
		if autoshot == "":
			get_tree().quit()
			return
	if autoshot == "":
		return
	shot_frames -= 1
	if shot_frames > 0:
		return
	var path := autoshot
	autoshot = ""
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[autoshot] ", path, " err=", err)
	get_tree().quit()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "Microsoft YaHei UI", "SimHei", "黑体",
		"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "sans-serif",
	])
	f.allow_system_fallback = true
	return f


# ============================================================ 命令行 / 调试

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		dev_mode = true
		if a.begins_with("--autoshot="):
			autoshot = a.substr(11)
		elif a.begins_with("--shot-frames="):
			shot_frames = int(a.substr(14))
		elif a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--selftest="):
			selftest_n = int(a.substr(11))
		elif a.begins_with("--seed="):
			random_seed_arg = int(a.substr(7))
		elif a.begins_with("--level="):
			sel_level = clampi(int(a.substr(8)), 0, Levels.LEVELS.size() - 1)
		elif a == "--levels":
			run_levels_test = true
		elif a == "--dump-random":
			dump_random = true
		elif a.begins_with("--random-solve="):
			random_solve_n = int(a.substr(15))
		elif a == "--trace-input":
			trace_input = true
		elif a.begins_with("--keys="):
			for n in a.substr(7).split(",", false):
				pending_keys.append(n.strip_edges())


func _push_keys(names: Array) -> void:
	var sent := ""
	for n in names:
		var kc: int = KEY_NAMES.get(String(n), 0)
		if kc == 0:
			print("[keys] 未知按键名：", n)
			continue
		var ev := InputEventKey.new()
		ev.keycode = kc
		ev.physical_keycode = kc
		ev.pressed = true
		get_viewport().push_input(ev)
		var ev2 := InputEventKey.new()
		ev2.keycode = kc
		ev2.physical_keycode = kc
		ev2.pressed = false
		get_viewport().push_input(ev2)
		sent += String(n) + " "
	print("[keys] 已发送：%s" % sent)
	_dump_state()


func _dump_state() -> void:
	var bag_chars := ""
	for id in game.bag:
		bag_chars += Data.RADICALS[id]["char"]
	print("[state] screen=%d level=%s pos=%s hp=%d/%d steps=%d/%d used=%d bag=[%s] state=%d ending=%s"
		% [screen, game.level_name, game.player, game.hp, game.max_hp,
			game.steps_left, game.steps_total, game.steps_used, bag_chars,
			game.state, game.ending.get("title", "-")])


func _apply_scenario() -> void:
	match scenario:
		"title":
			_show_title()
		"play":
			_start_level(sel_level)
		"play4":
			_start_level(3)
		"win":
			_start_level(sel_level)
			game.bag = ["huo", "shi"]
			game.walked[game.exitp.y][game.exitp.x] = false
			game.player = game.exitp
			game.trail.append(game.exitp)
			game._win()
			_after_action()
		"fail":
			_start_level(sel_level)
			game.bag = ["cao"]
			game._stuck("没有可以落笔的地方了。")
			_after_action()
		"select":
			_show_title()
		_:
			pass


# ============================================================ 存档

func _load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(progress_path) == OK:
		for k in cf.get_section_keys("levels"):
			completed[int(k)] = cf.get_value("levels", k)


func _save_progress() -> void:
	var cf := ConfigFile.new()
	for k in completed.keys():
		cf.set_value("levels", str(k), completed[k])
	cf.save(progress_path)


func _mark_complete(idx: int, steps: int) -> void:
	if idx < 0 or dev_mode:
		return          # 跑测试/截图时不要污染存档
	if not completed.has(idx) or steps < int(completed[idx]):
		completed[idx] = steps
		_save_progress()


# ============================================================ 标题 / 选关

func _build_title() -> void:
	title_root = Control.new()
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_root)

	var bg := ColorRect.new()
	bg.color = Data.C_PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(bg)

	var t := _mk_label("莫下面一个空", 66, Data.C_INK)
	t.position = Vector2(0, 44)
	t.size = Vector2(VIEW_W, 86)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(t)

	var sub := _mk_label("莫 + 一个偏旁 = 一个字 = 一个结局", 19, Data.C_INK_SOFT)
	sub.position = Vector2(0, 128)
	sub.size = Vector2(VIEW_W, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(sub)

	var rule := _mk_label("走过的地面会消失，不能回头。画一条不自交的笔画：起点 → 偏旁 → 门。", 16, Data.C_INK_SOFT)
	rule.position = Vector2(0, 164)
	rule.size = Vector2(VIEW_W, 30)
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(rule)

	# 关卡列表
	var grid := GridContainer.new()
	grid.columns = COLS_PER_ROW
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	grid.position = Vector2((VIEW_W - (COLS_PER_ROW * 290 + (COLS_PER_ROW - 1) * 14)) * 0.5, 216)
	title_root.add_child(grid)

	for i in Levels.LEVELS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(290, 62)
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 16)
		_style_button(b)
		b.pressed.connect(_on_level_button.bind(i))
		grid.add_child(b)
		level_buttons.append(b)

	var rb := Button.new()
	rb.custom_minimum_size = Vector2(290, 62)
	rb.add_theme_font_override("font", font)
	rb.add_theme_font_size_override("font_size", 17)
	_style_button(rb)
	rb.pressed.connect(_on_random_button)
	grid.add_child(rb)
	level_buttons.append(rb)

	var help := _mk_label(
		"移动 ← ↑ → ↓ / WASD　·　F 拾取　·　1 / 2 使用偏旁　·　Q / E 抹掉偏旁　·　Z 撤回一笔　·　R 重来　·　Esc 返回选关",
		15, Data.C_INK_SOFT)
	help.position = Vector2(0, VIEW_H - 62)
	help.size = Vector2(VIEW_W, 26)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(help)

	var tip := _mk_label("方向键选择关卡，Enter 开始。也可以直接用鼠标点。", 13, Data.C_INK_FAINT)
	tip.position = Vector2(0, VIEW_H - 34)
	tip.size = Vector2(VIEW_W, 24)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(tip)

	_refresh_title()


func _refresh_title() -> void:
	for i in Levels.LEVELS.size():
		var lv: Dictionary = Levels.LEVELS[i]
		var b: Button = level_buttons[i]
		var mark := "　　已完成 %d 步" % int(completed[i]) if completed.has(i) else ""
		b.text = "%s%s" % [lv["name"], mark]
	var rb: Button = level_buttons[level_buttons.size() - 1]
	rb.text = "随机关卡 · 每局一条新笔画"


func _on_level_button(i: int) -> void:
	_start_level(i)


func _on_random_button() -> void:
	_start_level(-1, random_seed_arg)


func _show_title() -> void:
	screen = Screen.TITLE
	title_root.visible = true
	play_root.visible = false
	overlay.visible = false
	_refresh_title()
	if level_buttons.size() > 0:
		level_buttons[sel_level if sel_level < Levels.LEVELS.size() else 0].grab_focus()


# ============================================================ 游戏界面

func _build_play() -> void:
	play_root = Control.new()
	play_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_root.visible = false
	add_child(play_root)

	var bg := ColorRect.new()
	bg.color = Data.C_PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_root.add_child(bg)

	board = Board.new()
	board.game = game
	board.font = font
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_root.add_child(board)

	var side := ColorRect.new()
	side.color = Color("#eae5d6")
	side.position = SIDE.position
	side.size = SIDE.size
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_root.add_child(side)

	var box := VBoxContainer.new()
	box.position = SIDE.position + Vector2(16, 12)
	box.size = SIDE.size - Vector2(32, 24)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_root.add_child(box)

	lbl_level = _mk_label("", 21, Data.C_INK)
	box.add_child(lbl_level)
	lbl_hint = _mk_label("", 14, Data.C_INK_SOFT)
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl_hint)

	# 莫 + 空槽
	var combo := PanelContainer.new()
	combo.add_theme_stylebox_override("panel", _panel_style(Color("#f7f4ea"), Data.C_INK, 8))
	box.add_child(combo)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	combo.add_child(cv)
	var mo := _mk_label("莫", 40, Data.C_INK)
	mo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(mo)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	cv.add_child(row)
	combo_slot = _mk_label("空", 24, Data.C_INK_FAINT)
	combo_slot.custom_minimum_size = Vector2(58, 58)
	combo_slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_boxed(combo_slot))
	combo_slot2 = _mk_label("空", 17, Data.C_INK_FAINT)
	combo_slot2.custom_minimum_size = Vector2(40, 40)
	combo_slot2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_slot2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_boxed(combo_slot2))
	combo_note = _mk_label("", 13, Data.C_INK_SOFT)
	combo_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(combo_note)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 22)
	box.add_child(stats)
	lbl_hp = _mk_label("", 15, Data.C_INK)
	lbl_steps = _mk_label("", 15, Data.C_INK)
	stats.add_child(lbl_hp)
	stats.add_child(lbl_steps)

	lbl_buffs = _mk_label("", 13, Data.C_GOOD)
	lbl_buffs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl_buffs)

	lbl_bag = _mk_label("", 13, Data.C_INK_SOFT)
	box.add_child(lbl_bag)
	for i in 2:
		var sp := _mk_slot_panel()
		slots.append(sp)
		box.add_child(sp["panel"])

	var log_title := _mk_label("—— 笔画 ——", 12, Data.C_INK_FAINT)
	log_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(log_title)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(0, 92)
	log_view.add_theme_font_override("normal_font", font)
	log_view.add_theme_font_size_override("normal_font_size", 13)
	log_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(log_view)

	lbl_prompt = _mk_label("", 15, Data.C_BAD)
	lbl_prompt.position = Vector2(BOARD_AREA.position.x, BOARD_AREA.position.y + BOARD_AREA.size.y + 6)
	lbl_prompt.size = Vector2(BOARD_AREA.size.x, 26)
	play_root.add_child(lbl_prompt)


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.957, 0.945, 0.910, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	ov_glyph = _mk_label("", 46, Data.C_INK)
	ov_glyph.position = Vector2(0, 66)
	ov_glyph.size = Vector2(VIEW_W, 160)
	ov_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(ov_glyph)

	ov_title = _mk_label("", 56, Data.C_ACCENT)
	ov_title.position = Vector2(0, 234)
	ov_title.size = Vector2(VIEW_W, 82)
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(ov_title)

	ov_text = _mk_label("", 18, Data.C_INK)
	ov_text.position = Vector2((VIEW_W - 820) * 0.5, 330)
	ov_text.size = Vector2(820, 190)
	ov_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(ov_text)

	ov_hint = _mk_label("", 16, Data.C_INK_SOFT)
	ov_hint.position = Vector2(0, 552)
	ov_hint.size = Vector2(VIEW_W, 40)
	ov_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(ov_hint)


# ---------------------------------------------------------- 小工具

func _mk_label(text: String, fsize: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style(bgc: Color, bordc: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bgc
	sb.border_color = bordc
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _boxed(inner: Label) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color("#fffdf6"), Data.C_INK, 8))
	pc.add_child(inner)
	return pc


func _mk_slot_panel() -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color("#f7f4ea"), Data.C_INK_FAINT, 6))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	pc.add_child(vb)
	var name_l := _mk_label("", 15, Data.C_INK)
	var info_l := _mk_label("", 12, Data.C_INK_SOFT)
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var end_l := _mk_label("", 13, Data.C_ACCENT)
	vb.add_child(name_l)
	vb.add_child(info_l)
	vb.add_child(end_l)
	return {"panel": pc, "name": name_l, "info": info_l, "end": end_l}


func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _panel_style(Color("#fffdf6"), Data.C_INK_FAINT, 6))
	b.add_theme_stylebox_override("hover", _panel_style(Color("#fdf6dc"), Data.C_ACCENT, 6))
	b.add_theme_stylebox_override("pressed", _panel_style(Color("#f0e6c0"), Data.C_INK, 6))
	b.add_theme_stylebox_override("focus", _panel_style(Color("#fdf6dc"), Data.C_ACCENT, 6))
	b.add_theme_color_override("font_color", Data.C_INK)
	b.add_theme_color_override("font_hover_color", Data.C_INK)
	b.add_theme_color_override("font_focus_color", Data.C_INK)
	b.add_theme_color_override("font_pressed_color", Data.C_INK)


# ============================================================ 开局 / 结束

func _start_level(idx: int, p_seed: int = -1) -> void:
	targeting = false
	target_slot = -1
	target_list = []
	board.cursor_cell = Vector2i(-1, -1)
	overlay.visible = false
	if idx < 0:
		game.new_random(p_seed)
	else:
		game.load_level(idx)
	screen = Screen.PLAY
	title_root.visible = false
	play_root.visible = true
	get_viewport().gui_release_focus()
	_layout_board()
	refresh()
	if dev_mode:
		_dump_map(game)
		print("[state] W=%d H=%d cell=%.1f board=%s" % [game.W, game.H, board.cell, board.size])


func _layout_board() -> void:
	var cw := floorf(BOARD_AREA.size.x / float(game.W))
	var ch := floorf(BOARD_AREA.size.y / float(game.H))
	board.cell = clampf(minf(cw, ch), 22.0, 74.0)
	board.size = Vector2(game.W, game.H) * board.cell
	board.position = BOARD_AREA.position + (BOARD_AREA.size - board.size) * 0.5


func _after_action() -> void:
	if game.state != Game.State.PLAYING and not overlay.visible:
		_show_overlay()
	refresh()
	board.queue_redraw()


func _show_overlay() -> void:
	var e: Dictionary = game.ending
	var glyph: String = e.get("glyph", "")
	ov_glyph.text = "莫\n%s" % (glyph if glyph != "" else "空")
	var title: String = e.get("title", "?")
	if game.state == Game.State.WON:
		ov_title.text = "「%s」" % title
		ov_title.add_theme_color_override("font_color", Data.C_ACCENT)
		_mark_complete(game.level_index, game.steps_used)
	else:
		ov_title.text = "「%s」" % title
		ov_title.add_theme_color_override("font_color", Data.C_BAD)
	var body: String = e.get("text", "")
	if e.get("pair", false):
		body += "\n\n" + Data.PAIR_LINE
	if game.state == Game.State.WON:
		var par := ""
		if game.steps_total >= 0:
			par = "用了 %d 步（上限 %d）" % [game.steps_used, game.steps_total]
		else:
			par = "用了 %d 步" % game.steps_used
		body += "\n\n—— %s ——" % par
	ov_text.text = body
	var hint := "R 重来　｜　Esc 返回选关"
	if game.state == Game.State.WON and game.level_index >= 0 and game.level_index + 1 < Levels.LEVELS.size():
		hint = "N 下一关　｜　R 重来　｜　Esc 返回选关"
	ov_hint.text = hint
	overlay.visible = true


# ============================================================ 输入

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var e := event as InputEventKey
	if trace_input:
		print("[trace] keycode=%d pressed=%s" % [e.keycode, e.pressed])
	if not e.pressed or e.echo:
		return
	if screen == Screen.TITLE:
		# 方向键 / Enter 交给按钮的焦点导航，这里只处理它不管的键
		if e.keycode == KEY_N:
			_on_random_button()
		elif e.keycode == KEY_R:
			_start_level(sel_level)
		get_viewport().set_input_as_handled()
		return
	_handle_key(e.keycode)
	get_viewport().set_input_as_handled()


func _handle_key(k: int) -> void:
	if game.state != Game.State.PLAYING:
		match k:
			KEY_R:
				_start_level(game.level_index, game.seed_used if game.is_random else -1)
			KEY_N:
				if game.level_index >= 0 and game.level_index + 1 < Levels.LEVELS.size():
					_start_level(game.level_index + 1)
			KEY_ESCAPE:
				_show_title()
		return

	if targeting:
		match k:
			KEY_LEFT, KEY_UP, KEY_A, KEY_W:
				_target_step(-1)
			KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S:
				_target_step(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_target_confirm()
			KEY_ESCAPE:
				_target_cancel()
		return

	match k:
		KEY_UP, KEY_W:
			game.move(Vector2i(0, -1))
			_after_action()
		KEY_DOWN, KEY_S:
			game.move(Vector2i(0, 1))
			_after_action()
		KEY_LEFT, KEY_A:
			game.move(Vector2i(-1, 0))
			_after_action()
		KEY_RIGHT, KEY_D:
			game.move(Vector2i(1, 0))
			_after_action()
		KEY_F:
			game.pickup()
			_after_action()
		KEY_1, KEY_KP_1:
			_use_slot(0)
		KEY_2, KEY_KP_2:
			_use_slot(1)
		KEY_Q:
			game.drop_item(0)
			_after_action()
		KEY_E:
			game.drop_item(1)
			_after_action()
		KEY_Z:
			game.undo()
			_after_action()
		KEY_R:
			_start_level(game.level_index, game.seed_used if game.is_random else -1)
		KEY_ESCAPE:
			_show_title()
		_:
			pass


func _use_slot(slot: int) -> void:
	if slot < 0 or slot >= game.bag.size():
		game._log("这一格是空的。")
		_after_action()
		return
	if game.needs_target(slot):
		var cells := game.target_cells(slot)
		if cells.is_empty():
			game._log("周围八格内没有可以下手的格子。")
			_after_action()
			return
		targeting = true
		target_slot = slot
		target_list = cells
		target_idx = 0
		board.cursor_cell = cells[0]
		_after_action()
		return
	game.use_item(slot)
	_after_action()


func _target_step(delta: int) -> void:
	if target_list.is_empty():
		return
	target_idx = wrapi(target_idx + delta, 0, target_list.size())
	board.cursor_cell = target_list[target_idx]
	refresh()
	board.queue_redraw()


func _target_confirm() -> void:
	var cell: Vector2i = target_list[target_idx]
	targeting = false
	board.cursor_cell = Vector2i(-1, -1)
	game.use_item(target_slot, cell)
	_after_action()


func _target_cancel() -> void:
	targeting = false
	target_slot = -1
	target_list = []
	board.cursor_cell = Vector2i(-1, -1)
	game._log("取消选择。")
	_after_action()


# ============================================================ 刷新 HUD

func refresh() -> void:
	lbl_level.text = game.level_name
	lbl_hint.text = game.hint

	lbl_hp.text = "生命　%s" % _hearts()
	lbl_hp.add_theme_color_override("font_color", Data.C_BAD if game.hp <= 1 else Data.C_INK)
	if game.steps_total >= 0:
		lbl_steps.text = "步数　%d / %d" % [maxi(game.steps_left, 0), game.steps_total]
		lbl_steps.add_theme_color_override("font_color",
			Data.C_BAD if game.steps_left <= 2 else Data.C_INK)
	else:
		lbl_steps.text = "步数　已用 %d" % game.steps_used
		lbl_steps.add_theme_color_override("font_color", Data.C_INK)

	if game.buffs.is_empty():
		lbl_buffs.text = "汉字：尚未获得"
		lbl_buffs.add_theme_color_override("font_color", Data.C_INK_FAINT)
	else:
		var parts: Array = []
		for id in game.buffs:
			parts.append(Data.HANZI[id]["char"])
		lbl_buffs.text = "汉字：" + " ".join(parts)
		lbl_buffs.add_theme_color_override("font_color", Data.C_GOOD)

	var primary := ""
	var secondary := ""
	if game.bag.size() > 0:
		primary = Data.RADICALS[game.bag[0]]["char"]
	if game.bag.size() > 1:
		secondary = Data.RADICALS[game.bag[1]]["char"]
	combo_slot.text = primary if primary != "" else "空"
	combo_slot.add_theme_color_override("font_color",
		Data.RADICALS[game.bag[0]]["color"] if primary != "" else Data.C_INK_FAINT)
	combo_slot2.text = secondary if secondary != "" else "空"
	combo_slot2.add_theme_color_override("font_color",
		Data.RADICALS[game.bag[1]]["color"] if secondary != "" else Data.C_INK_FAINT)

	if primary == "":
		combo_note.text = "莫下面空着 —— 这样走到门，结局是「空」"
		combo_note.add_theme_color_override("font_color", Data.C_INK_FAINT)
	else:
		var s := "结局 →「%s」" % Data.RADICALS[game.bag[0]]["ending"]
		if secondary != "":
			s += "　副「%s」" % Data.RADICALS[game.bag[1]]["ending"]
		combo_note.text = s
		combo_note.add_theme_color_override("font_color", Data.C_ACCENT)

	lbl_bag.text = "背包 %d/%d　（1 / 2 使用，Q / E 抹掉）" % [game.bag.size(), game.bag_capacity()]
	for i in slots.size():
		var sp: Dictionary = slots[i]
		var name_l: Label = sp["name"]
		var info_l: Label = sp["info"]
		var end_l: Label = sp["end"]
		if i < game.bag.size():
			var id: String = game.bag[i]
			var rd: Dictionary = Data.RADICALS[id]
			name_l.text = "[%d] %s" % [i + 1, rd["char"]] if rd["name"] == rd["char"] \
				else "[%d] %s　%s" % [i + 1, rd["char"], rd["name"]]
			name_l.add_theme_color_override("font_color", rd["color"])
			info_l.text = "用：%s\n罚：%s" % [rd["active"], rd["passive"]]
			end_l.text = "结局 →「%s」" % rd["ending"]
		else:
			name_l.text = "[%d] ——" % [i + 1]
			name_l.add_theme_color_override("font_color", Data.C_INK_FAINT)
			info_l.text = "空"
			end_l.text = ""

	# 脚下提示
	var stack: Array = game.ground_items(game.player)
	if game.state == Game.State.PLAYING and not stack.is_empty():
		var it: Dictionary = stack.back()
		if it["kind"] == "radical":
			var rd: Dictionary = Data.RADICALS[it["id"]]
			lbl_prompt.text = "F 拾取「%s」　用：%s　｜　罚：%s" % [rd["char"], rd["active"], rd["passive"]]
		else:
			var hd: Dictionary = Data.HANZI[it["id"]]
			lbl_prompt.text = "F 拾取汉字「%s」（%s + 莫）：%s" % [hd["char"], hd["part"], hd["effect"]]
	elif targeting:
		var cell: Vector2i = target_list[target_idx]
		lbl_prompt.text = "选择目标 (%d, %d)　←↑ / →↓ 切换　Enter 确认　Esc 取消　[%d/%d]" % [
			cell.x, cell.y, target_idx + 1, target_list.size()]
	elif game.state == Game.State.PLAYING and not game.has_any_move():
		lbl_prompt.text = "无处落笔 —— Z 撤回，或 R 重来。"
	else:
		lbl_prompt.text = ""

	_refresh_log()


func _hearts() -> String:
	var s := ""
	for i in game.max_hp:
		s += "♥" if i < game.hp else "·"
	return s


func _refresh_log() -> void:
	var lines: Array = game.log_lines
	var start := maxi(0, lines.size() - 20)
	var out := ""
	for i in range(start, lines.size()):
		var s: String = lines[i]
		var c := "#6b6862"
		if s.find("结局") >= 0 or s.find("门") >= 0:
			c = "#c8892a"
		elif s.find("获得") >= 0 or s.find("拾取") >= 0 or s.find("复制") >= 0:
			c = "#4a7c3f"
		elif s.find("伤") >= 0 or s.find("灼") >= 0 or s.find("冻") >= 0 or s.find("倒") >= 0 \
				or s.find("划") >= 0 or s.find("烧") >= 0 or s.find("燃") >= 0:
			c = "#b23a2e"
		elif s.find("「") >= 0:
			c = "#2b2a28"
		out += "[color=%s]%s[/color]\n" % [c, s]
	log_view.text = out


# ============================================================ 测试

func _dump_random() -> void:
	var g := Game.new()
	g.new_random(random_seed_arg if random_seed_arg >= 0 else 9011)
	_dump_map(g)
	get_tree().quit(0)


func _dump_map(g: Game) -> void:
	print("[dump] seed=%d W=%d H=%d 骨架长度=%d" % [g.seed_used, g.W, g.H, g.solution_path.size()])
	var counts := {}
	for y in g.H:
		var line := ""
		for x in g.W:
			var t: int = g.map[y][x]
			counts[t] = int(counts.get(t, 0)) + 1
			var ch := "?"
			match t:
				Data.Tile.FLOOR: ch = "."
				Data.Tile.THORN: ch = "^"
				Data.Tile.TREE: ch = "T"
				Data.Tile.WALL: ch = "#"
				Data.Tile.FIRE: ch = "F"
				Data.Tile.WATER: ch = "W"
				Data.Tile.EXIT: ch = "E"
			if Vector2i(x, y) == g.start:
				ch = "S"
			elif not g.items[y][x].is_empty():
				ch = "*"
			line += ch
		print("  ", line)
	var total := g.W * g.H
	var parts: Array = []
	for t in counts.keys():
		parts.append("%s=%d(%.0f%%)" % [Data.TILE_NAME[t], counts[t], 100.0 * counts[t] / total])
	print("[dump] ", " ".join(parts))


func _test_random_solve(n: int) -> void:
	## 用求解器衡量「会规划的玩家」在随机关卡上的通关率与搜索量。
	var solved := 0
	var stuck_search := 0
	var nodes_total := 0
	var steps_total := 0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var g := Game.new()
		g.new_random(i * 7919 + 11)
		var s := Solver.new()
		s.setup_from_game(g)
		s.node_budget = 40000          # 预算故意压低：这个测量只想知道「好不好解」
		var r := s.solve()
		if r["found"]:
			solved += 1
			nodes_total += r["nodes"]
			steps_total += r["steps"]
		elif r["budget_hit"]:
			stuck_search += 1
		if Time.get_ticks_msec() - t0 > 60000:
			print("[random] 超过 60 秒，提前收工（已跑 %d 张）" % (i + 1))
			break
	var ms := Time.get_ticks_msec() - t0
	print("[random] 解出 %d/%d（搜索预算用尽 %d），用时 %d ms" % [solved, n, stuck_search, ms])
	if solved > 0:
		print("[random] 平均：解法 %d 步，搜索 %d 个节点" % [steps_total / solved, nodes_total / solved])
	print("[random] ", "PASS" if solved == n else "部分未解出")
	get_tree().quit(0 if solved == n else 1)


func _test_levels() -> void:
	var fails := 0
	print("[levels] 共 %d 关" % Levels.LEVELS.size())
	for i in Levels.LEVELS.size():
		var lv: Dictionary = Levels.LEVELS[i]
		var s := Solver.new()
		s.setup_from_level(lv)
		var r := s.solve()
		var st: String = "✓" if r["found"] else "✗"
		var note := ""
		if r["found"]:
			var b: int = lv["steps"]
			if b >= 0 and r["steps"] > b:
				note = "  ⚠ 解法 %d 步 超出上限 %d" % [r["steps"], b]
				fails += 1
		else:
			note = "  ⚠ 无解" + ("（搜索预算用尽，未必真的无解）" if r["budget_hit"] else "")
			fails += 1
		print("  %s %-12s 步数上限 %-4s 解法 %-4s 节点 %d%s"
			% [st, lv["name"], str(lv["steps"]), str(r["steps"]) if r["found"] else "-",
				r["nodes"], note])
	print("[levels] 失败 %d 关。" % fails)
	print("[levels] ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 1)


func _run_selftest(n: int) -> void:
	var fails := 0
	var won := 0
	var stuck := 0
	var dead := 0
	for i in n:
		var g := Game.new()
		g.new_random(i * 7919 + 11)

		# 端到端：沿保底解一字不差地走完，必须判胜
		if g.solution_path.is_empty():
			push_error("selftest: seed %d 没生成保底解" % g.seed_used)
			fails += 1
		else:
			var gb := Game.new()
			gb.new_random(g.seed_used)
			gb.hp = 999
			gb.max_hp = 999
			var broken := ""
			for c in gb.solution_path:
				if gb.state != Game.State.PLAYING:
					break
				var cell: Vector2i = c
				if cell == gb.player:
					continue
				var dir: Vector2i = cell - gb.player
				if absi(dir.x) + absi(dir.y) != 1:
					broken = "路径不连续：%s → %s" % [gb.player, cell]
					break
				if not gb.move(dir):
					broken = "移动被拒：从 %s 走向 %s" % [gb.player, cell]
					break
				if not gb.ground_items(gb.player).is_empty():
					gb.pickup()
			if gb.state != Game.State.WON:
				fails += 1
				if fails <= 3:
					push_error("selftest: seed %d 保底解没走通 state=%d %s | 最后日志：%s"
						% [gb.seed_used, gb.state, broken,
							" / ".join(gb.log_lines.slice(maxi(0, gb.log_lines.size() - 3)))])
			elif gb.ending.is_empty() or gb.ending["title"] == "":
				push_error("selftest: seed %d 通关但没出结局" % gb.seed_used)
				fails += 1

		# 随机行动 500 次，不许崩
		for step in 500:
			if g.state != Game.State.PLAYING:
				break
			var r := g.rng.randi() % 100
			if r < 60:
				g.move(g.FOUR[g.rng.randi() % 4])
			elif r < 72:
				g.pickup()
			elif r < 86:
				if g.bag.size() > 0:
					var slot := g.rng.randi() % g.bag.size()
					if g.needs_target(slot):
						var cells := g.target_cells(slot)
						if not cells.is_empty():
							g.use_item(slot, cells[g.rng.randi() % cells.size()])
					else:
						g.use_item(slot)
			elif r < 90:
				g.drop_item(g.rng.randi() % maxi(1, g.bag.size()))
			elif r < 94:
				g.undo()
			else:
				g.move(g.FOUR[g.rng.randi() % 4])
		if g.hp < 0:
			push_error("selftest: seed %d hp 变负" % g.seed_used)
			fails += 1
		if g.player.x < 0 or g.player.y < 0 or g.player.x >= g.W or g.player.y >= g.H:
			push_error("selftest: seed %d 玩家跑出地图" % g.seed_used)
			fails += 1
		if g.state == Game.State.WON:
			won += 1
		elif g.state == Game.State.STUCK:
			stuck += 1
		elif g.state == Game.State.DEAD:
			dead += 1
	print("[selftest] 跑了 %d 张随机关卡，失败 %d。" % [n, fails])
	print("[selftest] 随机乱走的结果：通关 %d / 卡死 %d / 死亡 %d" % [won, stuck, dead])
	print("[selftest] ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 1)
