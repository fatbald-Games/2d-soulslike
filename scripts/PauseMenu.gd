extends CanvasLayer
## ESC brings up the pause screen over a dimmed, frozen dungeon.
##
## The tree is paused while this is open, so the node runs in ALWAYS mode —
## otherwise it would freeze along with the game and never process the keypress
## that closes it again.
##
## Same panel, cursor and footer as the title screen: a pause menu that looks
## like a different game is the fastest way to make a UI feel unfinished.

signal resumed
signal quit_to_menu

const ITEMS := ["RESUME", "PROGRESS", "CONTROLS", "OPTIONS", "QUIT TO TITLE"]
## Twelve rows is the most that fits between the panel top and the footer band
## at this pitch — see PROGRESS_STEP.
const PROGRESS_ROWS := 12
const PROGRESS_STEP := 9
const OPTION_ITEMS := ["WINDOW", "SCREEN SHAKE", "HUD HINTS", "BACK"]

enum Screen { MAIN, PROGRESS, CONTROLS, OPTIONS }

var _screen: Screen = Screen.MAIN
var _menu: MenuList
var _options: MenuList
var _pages: Dictionary = {}
var _shade: ColorRect
var _progress_rows: Array = []
var _progress_origin := Vector2.ZERO
var _progress_w := 0.0
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10                       # above the HUD
	Settings.load_once()
	_build()
	visible = false


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0.02, 0.018, 0.03, 0.80)
	_shade.size = UiTheme.VIEW
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)

	_pages[Screen.MAIN] = _build_main()
	_pages[Screen.PROGRESS] = _build_progress()
	_pages[Screen.CONTROLS] = _build_controls()
	_pages[Screen.OPTIONS] = _build_options()
	_show(Screen.MAIN)


func _page(heading: String, hint: String) -> Control:
	var page := Control.new()
	page.size = UiTheme.VIEW
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

	var head := PixelLabel.make(heading, 3, UiTheme.BONE_BRIGHT)
	head.shadow_tint = UiTheme.TITLE_SHADOW
	head.shadow_offset = Vector2(2, 2)
	head.center_on(UiTheme.VIEW.x * 0.5, 28)
	page.add_child(head)

	UiTheme.add_footer(page, hint)
	return page


func _build_main() -> Control:
	var page := _page("PAUSED", "UP DOWN  SELECT      ENTER  CONFIRM")
	var box := UiTheme.add_panel(page, ITEMS, 2, UiTheme.MENU_STEP, [], 190.0)
	var origin: Vector2 = box[0]
	var size: Vector2 = box[1]

	_menu = MenuList.new()
	page.add_child(_menu)
	_menu.build(ITEMS, origin, size.x)
	_menu.activated.connect(_on_activated)
	return page


## Everything the run has to show for itself, on one page. The stats say what
## the souls bought; the counters say how much of the keep has actually been
## seen — the two halves of "am I getting anywhere".
func _build_progress() -> Control:
	var page := _page("PROGRESS", "ESC  BACK")
	_progress_rows = []
	# sized for EVERY row: passing one placeholder makes a panel one row tall
	var sizing: Array = []
	for i in PROGRESS_ROWS:
		sizing.append("INSCRIPTIONS READ")
	var box := UiTheme.add_panel(page, sizing, 1, PROGRESS_STEP, ["00 / 00"], 230.0)
	_progress_origin = box[0]
	_progress_w = (box[1] as Vector2).x
	# five stats, a rule, then the counters
	for i in PROGRESS_ROWS:
		var y := _progress_origin.y + (UiTheme.MENU_Y0 - UiTheme.PANEL_Y) \
				+ i * PROGRESS_STEP
		var name_label := PixelLabel.make("", 1, UiTheme.BONE)
		name_label.position = Vector2(_progress_origin.x + 14, y)
		page.add_child(name_label)
		var val := PixelLabel.make("", 1, UiTheme.EMBER)
		val.position = Vector2(_progress_origin.x + _progress_w - 14, y)
		page.add_child(val)
		_progress_rows.append([name_label, val])
	return page


func _refresh_progress() -> void:
	var t := Run.totals()
	var rows: Array = []
	for i in Run.STAT_NAMES.size():
		rows.append(["%s  (%s)" % [Run.STAT_NAMES[i], Run.STAT_EFFECTS[i]],
				"%d" % Run.stats[i]])
	rows.append(["-", ""])
	rows.append(["LEVEL", "%d" % Run.level()])
	rows.append(["WEAPONS FOUND", "%d / %d" % [Run.owned().size(), t["weapons"]]])
	rows.append(["BONFIRES LIT", "%d / %d" % [Run.lit_bonfires.size(), t["bonfires"]]])
	rows.append(["REGIONS FOUND", "%d / %d" % [Run.seen_areas.size(), t["areas"]]])
	rows.append(["INSCRIPTIONS READ", "%d / %d" % [Run.read_runes.size(), t["runes"]]])
	rows.append(["HOLLOWS SLAIN", "%d" % Run.slain])

	for i in _progress_rows.size():
		var name_label: PixelLabel = _progress_rows[i][0]
		var val: PixelLabel = _progress_rows[i][1]
		if i >= rows.size():
			name_label.text = ""
			val.text = ""
			continue
		var is_rule: bool = rows[i][0] == "-"
		name_label.text = "" if is_rule else rows[i][0]
		name_label.tint = UiTheme.BONE_DIM if i < Run.STAT_NAMES.size() else UiTheme.BONE
		val.text = rows[i][1]
		# right-aligned: the column only lines up if each label is re-placed
		val.position.x = _progress_origin.x + _progress_w - UiTheme.PANEL_PAD_X - val.size.x


func _build_controls() -> Control:
	var page := _page("CONTROLS", "ESC  BACK")
	var names: Array = []
	var keys: Array = []
	for r in UiTheme.CONTROL_ROWS:
		names.append(r[0])
		keys.append(r[1])
	var box := UiTheme.add_panel(page, names, 1, UiTheme.ROW_STEP, keys, 190.0)
	UiTheme.add_rows(page, UiTheme.CONTROL_ROWS, box[0], (box[1] as Vector2).x)
	return page


func _build_options() -> Control:
	var page := _page("OPTIONS", "LEFT RIGHT  CHANGE      ESC  BACK")
	var vals := _option_values()
	var box := UiTheme.add_panel(page, OPTION_ITEMS, 2, UiTheme.MENU_STEP, vals, 190.0)
	var origin: Vector2 = box[0]
	var size: Vector2 = box[1]

	_options = MenuList.new()
	page.add_child(_options)
	_options.build(OPTION_ITEMS, origin, size.x, 2, UiTheme.MENU_STEP, vals)
	_options.activated.connect(_on_option_activated)
	_options.value_changed.connect(_on_option_changed)
	return page


func _option_values() -> Array:
	return [Settings.scale_label(),
			"ON" if Settings.screen_shake else "OFF",
			"ON" if Settings.hud_hints else "OFF",
			""]


func _refresh_options() -> void:
	var vals := _option_values()
	for i in vals.size():
		_options.set_value(i, vals[i])


func _show(s: Screen) -> void:
	_screen = s
	for key in _pages:
		var page: Control = _pages[key]
		page.visible = (key == s)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_menu.index = 0
	_menu._apply()
	_show(Screen.MAIN)
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	resumed.emit()


## Swallow the key so the game underneath does not also act on it. Activating
## QUIT TO TITLE tears this node out of the tree mid-handler, so the viewport can
## be gone by the time we get here — check before reaching for it.
func _consume() -> void:
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return

	if not _open:
		if k.physical_keycode == KEY_ESCAPE:
			open()
			_consume()
		return

	match _screen:
		Screen.MAIN:
			if k.physical_keycode == KEY_ESCAPE:
				close()
			else:
				_input_list(k, _menu)
		Screen.OPTIONS:
			if k.physical_keycode == KEY_ESCAPE:
				_show(Screen.MAIN)
			else:
				_input_list(k, _options)
		Screen.CONTROLS, Screen.PROGRESS:
			if k.physical_keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_show(Screen.MAIN)
	_consume()


func _input_list(k: InputEventKey, list: MenuList) -> void:
	match k.physical_keycode:
		KEY_UP, KEY_W:
			list.move(-1)
		KEY_DOWN, KEY_S:
			list.move(1)
		KEY_LEFT, KEY_A:
			list.nudge(-1)
		KEY_RIGHT, KEY_D:
			list.nudge(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			list.activate()


func _on_activated(idx: int) -> void:
	match idx:
		0:
			close()
		1:
			_refresh_progress()
			_show(Screen.PROGRESS)
		2:
			_show(Screen.CONTROLS)
		3:
			_show(Screen.OPTIONS)
		4:
			get_tree().paused = false
			_open = false
			quit_to_menu.emit()


func _on_option_activated(idx: int) -> void:
	if idx == 3:
		_show(Screen.MAIN)
	else:
		_on_option_changed(idx, 1)


func _on_option_changed(idx: int, dir: int) -> void:
	match idx:
		0:
			Settings.cycle_window(dir)
		1:
			Settings.screen_shake = not Settings.screen_shake
			Settings.save()
		2:
			Settings.hud_hints = not Settings.hud_hints
			Settings.save()
	_refresh_options()
