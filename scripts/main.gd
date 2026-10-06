extends Control
## 《莫下面一个空》主控制器：UI 构建、输入、渲染驱动。
##
## 调试参数（写在 `--` 之后）：
##   --selftest=200          无头跑 200 局随机模拟，检查不崩、地图连通
##   --autoshot=out.png      截图后退出
##   --shot-frames=30        截图前的等待帧数
##   --scenario=target       截图前摆好场景：target / ending / items / status

const BOARD_X := 24.0
const BOARD_Y := 24.0
const SIDE_X := 642.0
const SIDE_Y := 24.0
const SIDE_W := 514.0
const SIDE_H := 672.0
const VIEW_W := 1180.0

var game: Game
var board: Board
var font: Font

# --- UI 引用 ---
var lbl_hp: Label
var lbl_steps: Label
var lbl_turn: Label
var lbl_buffs: Label
var lbl_bag_title: Label
var combo_mo: Label
var combo_slot: Label
var combo_slot2: Label
var combo_note: Label
var slots: Array = []          # [{panel, name, info, end}]
var log_view: RichTextLabel
var lbl_prompt: Label
var overlay: Control
var ov_glyph: Label
var ov_title: Label
var ov_text: Label
var ov_hint: Label

# --- 选择模式 ---
var targeting := false
var target_slot := -1
var target_list: Array = []
var target_idx := 0

# --- 调试 ---
var autoshot := ""
var shot_frames := 30
var scenario := ""


func _ready() -> void:
	font = _make_font()
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 15
	theme = th

	_parse_args()

	game = Game.new()
	game.new_game()

	_build_ui()
	refresh()
	board.queue_redraw()

	if _unit:
		_run_unittest()
	elif _selftest_n > 0:
		_run_selftest(_selftest_n)
	elif scenario != "":
		_apply_scenario()


func _process(_d: float) -> void:
	if not _pending_keys.is_empty() and shot_frames <= 25:
		var keys: Array = _pending_keys
		_pending_keys = []
		_push_keys(keys)
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
	print("[state] pos=%s steps=%d/%d turn=%d hp=%d bag=%s buffs=%s state=%d ending=%s"
		% [game.player, game.steps, game.max_steps(), game.turn, game.hp,
			game.bag, game.buffs, game.state, game.ending.get("title", "-")])


# ============================================================ 字体

func _make_font() -> Font:
	# 走系统字体，避免往仓库里塞字体文件；Windows 上必然是微软雅黑。
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "Microsoft YaHei UI", "SimHei", "黑体",
		"Microsoft JhengHei", "SimSun", "宋体", "Noto Sans CJK SC",
		"Source Han Sans SC", "PingFang SC", "sans-serif",
	])
	f.allow_system_fallback = true
	return f


# ============================================================ 命令行

var _selftest_n := 0
var _unit := false
var _pending_keys: Array = []
var _keys_done := false
var _trace_input := false

const KEY_NAMES := {
	"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
	"w": KEY_W, "a": KEY_A, "s": KEY_S, "d": KEY_D,
	"f": KEY_F, "q": KEY_Q, "e": KEY_E, "r": KEY_R,
	"1": KEY_1, "2": KEY_2,
	"space": KEY_SPACE, "enter": KEY_ENTER, "esc": KEY_ESCAPE,
}

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			autoshot = a.substr(11)
		elif a.begins_with("--shot-frames="):
			shot_frames = int(a.substr(14))
		elif a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--selftest="):
			_selftest_n = int(a.substr(11))
		elif a == "--unittest":
			_unit = true
		elif a == "--trace-input":
			_trace_input = true
		elif a.begins_with("--keys="):
			# 把合成按键推进真实的输入管线，用来验证 事件→viewport→_unhandled_input→游戏状态
			for name in a.substr(7).split(",", false):
				_pending_keys.append(name.strip_edges())


func _apply_scenario() -> void:
	match scenario:
		"target":
			game.bag = ["gong"]
			game.steps = 3
			_use_slot(0)
		"target2":
			var p := _first_wall_near()
			game.player = p
			game.bag = ["gong"]
			game.steps = 3
			game.update_vision()
			_use_slot(0)
		"ending":
			game.bag = ["huo", "shi"]
			game.force_ending()
			_show_overlay()
		"ending2":
			game.bag = ["cao"]
			game.force_ending()
			_show_overlay()
		"items":
			var spot := _first_item_spot()
			if spot.x >= 0:
				game.player = spot
				game.update_vision()
		"status":
			game.bag = ["shi", "cao"]
			game.buffs = ["mo_ma", "mo_ri", "mo_tu", "mo_mu"]
			game.hp = 2
			game.steps = 4
			game.turn = 7
			game.update_vision()
		_:
			pass
	refresh()
	board.queue_redraw()


func _first_wall_near() -> Vector2i:
	for y in range(1, Game.H - 1):
		for x in range(1, Game.W - 1):
			if game.map[y][x] == Data.Tile.WALL:
				# 找一个四周有障碍的落脚点，让选择模式有目标
				for d in game.FOUR:
					var p := Vector2i(x, y) + d
					if game.in_bounds(p) and game.map[p.y][p.x] != Data.Tile.WALL:
						return p
	return Vector2i(1, 1)


func _first_item_spot() -> Vector2i:
	for y in Game.H:
		for x in Game.W:
			if not game.items[y][x].is_empty():
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# ============================================================ UI 构建

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Data.C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	board = Board.new()
	board.game = game
	board.font = font
	board.position = Vector2(BOARD_X, BOARD_Y)
	board.size = Vector2(Game.W * Board.CELL, Game.H * Board.CELL)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)

	_build_help()
	_build_side()
	_build_overlay()
	_build_prompt()


func _build_help() -> void:
	var l := _mk_label("", 12, Data.C_FAINT)
	l.position = Vector2(BOARD_X, BOARD_Y + Game.H * Board.CELL + 40)
	l.size = Vector2(Game.W * Board.CELL, 60)
	l.text = ("移动 ←↑→↓ / WASD　·　F 拾取　·　1 / 2 使用偏旁（1 步）　·　Q / E 丢弃　·　空格 结束回合　·　R 重开\n"
		+ "地形：棘 荆棘（受伤）· 树 树木（2 步）· 障 障碍物（不可通过）· 火 / 水（受伤）· 门 出口")
	add_child(l)


func _build_side() -> void:
	var side := ColorRect.new()
	side.color = Data.C_SIDE
	side.position = Vector2(SIDE_X, SIDE_Y)
	side.size = Vector2(SIDE_W, SIDE_H)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side)

	var box := VBoxContainer.new()
	box.position = Vector2(SIDE_X + 16, SIDE_Y + 12)
	box.size = Vector2(SIDE_W - 32, SIDE_H - 24)
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	# 标题
	var title := _mk_label("莫下面一个空", 22, Data.C_ACCENT)
	box.add_child(title)
	var sub := _mk_label("回合制 · 汉字 Roguelike —— 带哪个偏旁走到出口，结局就定格成哪个字", 11, Data.C_FAINT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)

	# 组合面板
	var combo := PanelContainer.new()
	combo.add_theme_stylebox_override("panel", _panel_style(Data.C_SLOT_BG, Data.C_LINE, 8))
	box.add_child(combo)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	combo.add_child(cv)

	combo_mo = _mk_label("莫", 44, Data.C_PLAYER)
	combo_mo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(combo_mo)

	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 10)
	cv.add_child(slot_row)

	combo_slot = _mk_label("空", 26, Data.C_FAINT)
	combo_slot.custom_minimum_size = Vector2(64, 64)
	combo_slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_row.add_child(_boxed(combo_slot))

	combo_slot2 = _mk_label("空", 18, Data.C_FAINT)
	combo_slot2.custom_minimum_size = Vector2(44, 44)
	combo_slot2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_slot2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_row.add_child(_boxed(combo_slot2))

	combo_note = _mk_label("", 12, Data.C_DIM)
	combo_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(combo_note)

	# 状态行
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24)
	box.add_child(stats)
	lbl_hp = _mk_label("", 15, Data.C_TEXT)
	lbl_steps = _mk_label("", 15, Data.C_TEXT)
	lbl_turn = _mk_label("", 15, Data.C_TEXT)
	stats.add_child(lbl_hp)
	stats.add_child(lbl_steps)
	stats.add_child(lbl_turn)

	lbl_buffs = _mk_label("", 12, Data.C_GOOD)
	lbl_buffs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl_buffs)

	lbl_bag_title = _mk_label("", 13, Data.C_DIM)
	box.add_child(lbl_bag_title)

	for i in 2:
		var sp := _mk_slot_panel()
		slots.append(sp)
		box.add_child(sp["panel"])

	# 日志
	var log_title := _mk_label("—— 记录 ——", 12, Data.C_FAINT)
	log_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(log_title)

	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(0, 96)
	log_view.add_theme_font_override("normal_font", font)
	log_view.add_theme_font_size_override("normal_font_size", 12)
	log_view.add_theme_font_override("bold_font", font)
	log_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(log_view)


func _build_prompt() -> void:
	lbl_prompt = _mk_label("", 14, Data.C_ACCENT)
	lbl_prompt.position = Vector2(BOARD_X, BOARD_Y + Game.H * Board.CELL + 10)
	lbl_prompt.size = Vector2(Game.W * Board.CELL, 26)
	add_child(lbl_prompt)


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.028, 0.028, 0.05, 0.975)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	ov_glyph = _mk_label("", 52, Data.C_PLAYER)
	ov_glyph.position = Vector2(0, 48)
	ov_glyph.size = Vector2(VIEW_W, 180)
	ov_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(ov_glyph)

	ov_title = _mk_label("", 60, Data.C_ACCENT)
	ov_title.position = Vector2(0, 236)
	ov_title.size = Vector2(VIEW_W, 86)
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(ov_title)

	ov_text = _mk_label("", 19, Data.C_TEXT)
	ov_text.position = Vector2((VIEW_W - 780) * 0.5, 336)
	ov_text.size = Vector2(780, 220)
	ov_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	overlay.add_child(ov_text)

	ov_hint = _mk_label("", 16, Data.C_DIM)
	ov_hint.position = Vector2(0, 620)
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
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _boxed(inner: Label) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color("#0d0d16"), Data.C_LINE, 8))
	pc.add_child(inner)
	return pc


func _mk_slot_panel() -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Data.C_SLOT_BG, Data.C_LINE, 6))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	pc.add_child(vb)

	var name_l := _mk_label("", 15, Data.C_TEXT)
	var info_l := _mk_label("", 11, Data.C_DIM)
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var end_l := _mk_label("", 12, Data.C_ACCENT)

	vb.add_child(name_l)
	vb.add_child(info_l)
	vb.add_child(end_l)
	return {"panel": pc, "name": name_l, "info": info_l, "end": end_l}


# ============================================================ 输入

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var e := event as InputEventKey
	if _trace_input:
		print("[trace] keycode=%d physical=%d pressed=%s echo=%s" % [e.keycode, e.physical_keycode, e.pressed, e.echo])
	if not e.pressed or e.echo:
		return
	_handle_key(e.keycode)
	get_viewport().set_input_as_handled()


func _handle_key(k: int) -> void:
	if game.state != Game.State.PLAYING:
		if k == KEY_R:
			_start_new()
		elif k == KEY_ESCAPE:
			get_tree().quit()
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
			_try_move(Vector2i(0, -1))
		KEY_DOWN, KEY_S:
			_try_move(Vector2i(0, 1))
		KEY_LEFT, KEY_A:
			_try_move(Vector2i(-1, 0))
		KEY_RIGHT, KEY_D:
			_try_move(Vector2i(1, 0))
		KEY_1, KEY_KP_1:
			_use_slot(0)
		KEY_2, KEY_KP_2:
			_use_slot(1)
		KEY_Q:
			_slot_action(0, "drop")
		KEY_E:
			_slot_action(1, "drop")
		KEY_F:
			game.pickup()
		KEY_SPACE:
			game.end_turn_early()
		KEY_R:
			_start_new()
		_:
			pass


func _try_move(d: Vector2i) -> void:
	game.move(d)
	_after_action()


func _use_slot(slot: int) -> void:
	if slot < 0 or slot >= game.bag.size():
		game._log("这一格是空的。")
		_after_action()
		return
	if game.needs_target(slot):
		var cells := game.target_cells(slot)
		if cells.is_empty():
			var what := "障碍物" if game.bag[slot] == "gong" else "道具"
			game._log("周围八格内没有可选的%s。" % what)
			_after_action()
			return
		targeting = true
		target_slot = slot
		target_list = cells
		target_idx = 0
		_sync_cursor()
		_after_action()
		return
	game.use_item(slot)
	_after_action()


func _slot_action(slot: int, act: String) -> void:
	if act == "drop":
		game.drop_item(slot)
	_after_action()


func _target_step(delta: int) -> void:
	if target_list.is_empty():
		return
	target_idx = wrapi(target_idx + delta, 0, target_list.size())
	_sync_cursor()
	refresh()
	board.queue_redraw()


func _sync_cursor() -> void:
	board.cursor_cell = target_list[target_idx] if targeting else Vector2i(-1, -1)


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


func _after_action() -> void:
	if game.state != Game.State.PLAYING and not overlay.visible:
		_show_overlay()
	refresh()
	board.queue_redraw()


func _start_new() -> void:
	targeting = false
	target_slot = -1
	target_list = []
	board.cursor_cell = Vector2i(-1, -1)
	overlay.visible = false
	game.new_game()
	refresh()
	board.queue_redraw()


# ============================================================ 刷新 UI

func refresh() -> void:
	# 状态
	lbl_hp.text = "生命 %s %d/%d" % [_hearts(), game.hp, game.max_hp]
	lbl_hp.add_theme_color_override("font_color",
		Data.C_BAD if game.hp <= 1 else Data.C_TEXT)
	lbl_steps.text = "步数 %d/%d" % [maxi(game.steps, 0), game.max_steps()]
	lbl_turn.text = "回合 %d" % game.turn

	# 汉字 buff
	if game.buffs.is_empty():
		lbl_buffs.text = "汉字：尚未获得"
		lbl_buffs.add_theme_color_override("font_color", Data.C_FAINT)
	else:
		var parts: Array = []
		for id in game.buffs:
			parts.append("%s(%s+莫)" % [Data.HANZI[id]["char"], Data.HANZI[id]["part"]])
		lbl_buffs.text = "汉字：" + "  ".join(parts)
		lbl_buffs.add_theme_color_override("font_color", Data.C_GOOD)

	# 组合面板
	var primary := ""
	var secondary := ""
	if game.bag.size() > 0:
		primary = Data.RADICALS[game.bag[0]]["char"]
	if game.bag.size() > 1:
		secondary = Data.RADICALS[game.bag[1]]["char"]

	combo_slot.text = primary if primary != "" else "空"
	combo_slot.add_theme_color_override("font_color",
		Data.RADICALS[game.bag[0]]["color"] if primary != "" else Data.C_FAINT)
	combo_slot2.text = secondary if secondary != "" else "空"
	combo_slot2.add_theme_color_override("font_color",
		Data.RADICALS[game.bag[1]]["color"] if secondary != "" else Data.C_FAINT)

	if primary == "":
		combo_note.text = "莫下面空着 —— 走出去，结局是「空」"
		combo_note.add_theme_color_override("font_color", Data.C_FAINT)
	else:
		var d: Dictionary = Data.RADICALS[game.bag[0]]
		var s := "结局 →「%s」" % d["ending"]
		if secondary != "":
			s += "　（副：%s）" % Data.RADICALS[game.bag[1]]["ending"]
		combo_note.text = s
		combo_note.add_theme_color_override("font_color", Data.C_ACCENT)

	# 背包
	lbl_bag_title.text = "背包 %d/%d　（1 / 2 使用，Q / E 丢弃）" % [game.bag.size(), game.bag_capacity()]

	for i in slots.size():
		var sp: Dictionary = slots[i]
		var name_l: Label = sp["name"]
		var info_l: Label = sp["info"]
		var end_l: Label = sp["end"]
		if i < game.bag.size():
			var id: String = game.bag[i]
			var rd: Dictionary = Data.RADICALS[id]
			if rd["name"] == rd["char"]:
				name_l.text = "[%d] %s" % [i + 1, rd["char"]]
			else:
				name_l.text = "[%d] %s　%s" % [i + 1, rd["char"], rd["name"]]
			name_l.add_theme_color_override("font_color", rd["color"])
			info_l.text = "用：%s\n罚：%s" % [rd["active"], rd["passive"]]
			end_l.text = "结局 →「%s」" % rd["ending"]
		else:
			name_l.text = "[%d] ——" % [i + 1]
			name_l.add_theme_color_override("font_color", Data.C_FAINT)
			info_l.text = "空"
			end_l.text = ""

	# 脚下道具提示
	var stack: Array = game.ground_items(game.player)
	if game.state == Game.State.PLAYING and not stack.is_empty():
		var it: Dictionary = stack.back()
		if it["kind"] == "radical":
			var rd: Dictionary = Data.RADICALS[it["id"]]
			lbl_prompt.text = "按 F 拾取「%s」——用：%s｜罚：%s｜结局 →「%s」" % [
				rd["char"], rd["active"], rd["passive"], rd["ending"]]
		else:
			var hd: Dictionary = Data.HANZI[it["id"]]
			lbl_prompt.text = "按 F 拾取汉字「%s」（%s + 莫）：%s" % [hd["char"], hd["part"], hd["effect"]]
	else:
		lbl_prompt.text = ""

	if targeting:
		var cell: Vector2i = target_list[target_idx]
		lbl_prompt.text = "选择目标 (%d, %d)　←↑ 上一个 ｜ →↓ 下一个 ｜ Enter 确认 ｜ Esc 取消　[%d/%d]" % [
			cell.x, cell.y, target_idx + 1, target_list.size()]

	_refresh_log()


func _hearts() -> String:
	var s := ""
	for i in game.max_hp:
		s += "♥" if i < game.hp else "·"
	return s


func _refresh_log() -> void:
	var lines: Array = game.log_lines
	var start := maxi(0, lines.size() - 16)
	var out := ""
	for i in range(start, lines.size()):
		var s: String = lines[i]
		var c := "#8c8aa6"
		if s.find("结局") >= 0:
			c = "#d8b13a"
		elif s.find("获得") >= 0 or s.find("拾取") >= 0 or s.find("复制") >= 0:
			c = "#8fd8a0"
		elif s.find("伤") >= 0 or s.find("灼") >= 0 or s.find("冻") >= 0 or s.find("倒") >= 0 or s.find("划") >= 0 or s.find("反噬") >= 0:
			c = "#e0705a"
		elif s.find("「") >= 0:
			c = "#c0bcd8"
		out += "[color=%s]%s[/color]\n" % [c, s]
	log_view.text = out


func _show_overlay() -> void:
	var e: Dictionary = game.ending
	var glyph: String = e.get("glyph", "")
	# 竖排：莫 在上，偏旁填在下面那个空里
	ov_glyph.text = "莫\n%s" % (glyph if glyph != "" else "空")
	ov_title.text = "「%s」" % e.get("title", "?")
	var body: String = e.get("text", "")
	if e.get("pair", false):
		body += "\n\n" + Data.PAIR_LINE
	ov_text.text = body
	ov_hint.text = "R 重新开始　｜　Esc 退出"
	overlay.visible = true


# ============================================================ 自检

var _unit_fails: Array = []


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_unit_fails.append(msg)


func _run_unittest() -> void:
	var f: Array = _unit_fails

	# 1) 每种偏旁单独带着走 → 对应结局
	for id in Data.RADICAL_ORDER:
		var g := Game.new()
		g.new_game(4242)
		g.bag = [id]
		g.force_ending()
		_expect(g.ending["title"] == Data.RADICALS[id]["ending"],
			"偏旁 %s 的结局应是「%s」，实际「%s」" % [id, Data.RADICALS[id]["ending"], g.ending["title"]])
		_expect(not g.ending["pair"], "单个偏旁不该标成双生结局（%s）" % id)
		_expect(g.ending["glyph"] == Data.RADICALS[id]["char"],
			"偏旁 %s 的结局字形不对" % id)

	# 2) 空手走到出口 → 「空」
	var g2 := Game.new()
	g2.new_game(4242)
	g2.bag = []
	g2.force_ending()
	_expect(g2.ending["title"] == "空", "空背包结局应是「空」，实际「%s」" % g2.ending["title"])

	# 3) 两个偏旁 → 取先拾取的，并标记双生
	var g3 := Game.new()
	g3.new_game(4242)
	g3.bag = ["cao", "huo"]
	g3.force_ending()
	_expect(g3.ending["title"] == "野", "双偏旁应取先拾取的「野」，实际「%s」" % g3.ending["title"])
	_expect(g3.ending["pair"], "双偏旁未标记 pair")
	_expect(g3.ending.get("pair_char", "") == "火", "双生副偏旁应为「火」")

	# 4) 真的踩上出口 → 判胜
	var g4 := Game.new()
	g4.new_game(99)
	var ep := Vector2i(Game.W - 2, Game.H - 2)
	g4.player = ep + Vector2i(-1, 0)
	g4.map[g4.player.y][g4.player.x] = Data.Tile.FLOOR
	g4.map[ep.y][ep.x] = Data.Tile.EXIT
	g4.steps = 3
	g4.move(Vector2i(1, 0))
	_expect(g4.state == Game.State.WON, "踩到出口应判胜，实际 state=%d" % g4.state)

	# 5) 生命归零 → 判负
	var g5 := Game.new()
	g5.new_game(99)
	g5.hp = 1
	g5.buffs = []
	g5._damage(1, "测试")
	_expect(g5.state == Game.State.DEAD, "生命归零应判负")
	_expect(g5.ending["title"] == "殁", "死亡结局标题应为「殁」")

	# 6) 「墓」只能续命一次
	var g6 := Game.new()
	g6.new_game(99)
	g6.hp = 1
	g6.buffs = ["mo_tu"]
	g6._damage(1, "测试")
	_expect(g6.state == Game.State.PLAYING and g6.hp == 1, "「墓」应把玩家从 0 血救回 1 血")
	g6._damage(1, "测试")
	_expect(g6.state == Game.State.DEAD, "「墓」只该生效一次")

	# 7) 步数 / 背包 / 视野 的派生数值
	var g7 := Game.new()
	g7.new_game(99)
	g7.bag = []
	g7.buffs = []
	_expect(g7.max_steps() == 3, "基础步数应为 3，实际 %d" % g7.max_steps())
	g7.bag = ["dao"]
	_expect(g7.max_steps() == 2, "带「刂」应为 2 步，实际 %d" % g7.max_steps())
	g7.buffs = ["mo_ma"]
	_expect(g7.max_steps() == 4, "带「刂」+「蟆」应为 4 步，实际 %d" % g7.max_steps())
	g7.bag = ["dao", "shi"]
	_expect(g7.bag_capacity() == 2, "不带「风」时背包容量应为 2")
	g7.bag = ["feng", "shi"]
	_expect(g7.bag_capacity() == 1, "带「风」时背包容量应为 1")
	g7.buffs = []
	_expect(g7.vision_extent() == 2, "基础视野应为 5×5")
	g7.buffs = ["mo_ri"]
	_expect(g7.vision_extent() == 3, "带「暮」视野应为 7×7")

	# 8) 「漠」火免、「幕」荆棘免
	var g8 := Game.new()
	g8.new_game(99)
	g8.map[5][5] = Data.Tile.FIRE
	g8.buffs = ["mo_shui"]
	g8.hp = 3
	g8._apply_tile_damage(Vector2i(5, 5))
	_expect(g8.hp == 3, "「漠」应免疫火伤害")
	g8.buffs = []
	g8._apply_tile_damage(Vector2i(5, 5))
	_expect(g8.hp == 2, "无「漠」时踩火应扣 1 血")
	g8.map[5][5] = Data.Tile.THORN
	g8.buffs = ["mo_jin"]
	g8.hp = 3
	g8._apply_tile_damage(Vector2i(5, 5))
	_expect(g8.hp == 3, "「幕」应免疫荆棘伤害")

	print("[unittest] 断言失败 %d 条。" % f.size())
	for msg in f:
		print("  ✗ ", msg)
	print("[unittest] ", "PASS" if f.is_empty() else "FAIL")
	get_tree().quit(0 if f.is_empty() else 1)


func _run_selftest(n: int) -> void:
	var fails := 0
	var straight_wins := 0
	var straight_deaths := 0
	var careful_wins := 0
	var careful_deaths := 0
	var careful_stuck := 0
	for i in n:
		var g := Game.new()
		g.new_game(i * 7919 + 13)

		# 出口必须可达
		var reach := g.reachable_from(Vector2i(1, 1))
		var exitp := Vector2i(Game.W - 2, Game.H - 2)
		if not reach[exitp.y][exitp.x]:
			push_error("selftest: seed %d 出口不可达" % g.seed_used)
			fails += 1
			continue

		# 端到端：沿 BFS 路径真的一步步走到出口，必须判胜并生成结局
		var gb := Game.new()
		gb.new_game(g.seed_used)
		gb.hp = 999
		gb.max_hp = 999
		var walk: Array = gb.find_path(gb.player, exitp)
		if walk.is_empty():
			push_error("selftest: seed %d 找不到通往出口的路径" % g.seed_used)
			fails += 1
			continue
		var pos: Vector2i = gb.player
		for c in walk:
			var cell: Vector2i = c
			gb.steps = 99
			gb.move(cell - pos)
			pos = cell
			if gb.state != Game.State.PLAYING:
				break
		if gb.state != Game.State.WON:
			push_error("selftest: seed %d 沿路径未走到出口（state=%d）" % [gb.seed_used, gb.state])
			fails += 1
		elif gb.ending.is_empty() or gb.ending["title"] == "":
			push_error("selftest: seed %d 判胜但没生成结局" % gb.seed_used)
			fails += 1

		# 随机操作 600 次，全程不许崩
		for step in 600:
			if g.state != Game.State.PLAYING:
				break
			var r := g.rng.randi() % 100
			if r < 62:
				g.move(g.FOUR[g.rng.randi() % 4])
			elif r < 72:
				g.pickup()
			elif r < 88:
				var slot := g.rng.randi() % maxi(1, g.bag.size())
				if g.bag.size() > 0:
					if g.needs_target(slot):
						var cells := g.target_cells(slot)
						if not cells.is_empty():
							g.use_item(slot, cells[g.rng.randi() % cells.size()])
					else:
						g.use_item(slot)
			elif r < 92:
				g.drop_item(g.rng.randi() % maxi(1, g.bag.size()))
			elif r < 96:
				g.pickup()
			else:
				g.end_turn_early()
		if g.hp < 0:
			push_error("selftest: seed %d hp 变成负数" % g.seed_used)
			fails += 1

		# 平衡参考 A：正常 3 血、不捡任何道具、直接走最短路
		var gc := Game.new()
		gc.new_game(g.seed_used)
		for c in gc.find_path(gc.player, exitp):
			if gc.state != Game.State.PLAYING:
				break
			var cell: Vector2i = c
			gc.steps = maxi(gc.steps, gc.step_cost(cell))
			gc.move(cell - gc.player)
		if gc.state == Game.State.WON:
			straight_wins += 1
		elif gc.state == Game.State.DEAD:
			straight_deaths += 1

		# 平衡参考 B：会绕开火/水/荆棘的玩家（不捡道具，纯走位）
		var gd := Game.new()
		gd.new_game(g.seed_used)
		var safe: Array = gd.find_safe_path(gd.player, exitp)
		if safe.is_empty():
			careful_stuck += 1
		else:
			for c in safe:
				if gd.state != Game.State.PLAYING:
					break
				var cell: Vector2i = c
				gd.steps = maxi(gd.steps, gd.step_cost(cell))
				gd.move(cell - gd.player)
			if gd.state == Game.State.WON:
				careful_wins += 1
			elif gd.state == Game.State.DEAD:
				careful_deaths += 1

	print("[selftest] 跑了 %d 局，失败 %d 局。" % [n, fails])
	print("[selftest] 平衡 A 裸装直冲最短路：通关 %d / 死亡 %d / 未结束 %d"
		% [straight_wins, straight_deaths, n - straight_wins - straight_deaths])
	print("[selftest] 平衡 B 裸装绕开危险：通关 %d / 死亡 %d / 无路可走 %d / 未结束 %d"
		% [careful_wins, careful_deaths, careful_stuck, n - careful_wins - careful_deaths - careful_stuck])
	print("[selftest] ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 1)
