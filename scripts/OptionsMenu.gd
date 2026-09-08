class_name OptionsMenu
extends Control
## The settings screen, built once and embedded in both the title screen and the
## pause screen.
##
## It used to be a four-line page duplicated in two files, which is how the two
## copies of the control list drifted apart the first time. Now there is one
## widget: it owns its own sub-pages, its own input handling and its own footer,
## and the menu that hosts it only has to hand it keys and listen for `closed`.
##
## Sub-pages: VIDEO, AUDIO, CONTROLS (rebindable), GAMEPLAY.

signal closed

enum Page { ROOT, VIDEO, AUDIO, CONTROLS, GAMEPLAY }

const ROOT_ITEMS := ["VIDEO", "AUDIO", "CONTROLS", "GAMEPLAY",
		"RESTORE DEFAULTS", "BACK"]
const VIDEO_ITEMS := ["WINDOW", "VSYNC", "FPS LIMIT", "VIGNETTE",
		"SCREEN SHAKE", "BACK"]
const AUDIO_ITEMS := ["MASTER", "MUSIC", "SOUND", "AMBIENCE", "BACK"]
const GAMEPLAY_ITEMS := ["HUD HINTS", "REGION BANNERS", "AUTO EQUIP WEAPONS", "BACK"]

## The controls page is thirteen rows deep, which does not fit under the usual
## panel top — so like the progress page it starts higher, heading and all.
const CTRL_STEP := 9
const CTRL_PANEL_Y := 36.0
const CTRL_HEAD_Y := 12

var _page: Page = Page.ROOT
var _pages: Dictionary = {}
var _lists: Dictionary = {}
var _rebinding := ""              # action id being rebound, "" when not
var _notice: PixelLabel


func _init() -> void:
	size = UiTheme.VIEW
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	Settings.load_once()
	_pages[Page.ROOT] = _build_list(Page.ROOT, "OPTIONS", ROOT_ITEMS,
			"UP DOWN  SELECT      ENTER  CONFIRM", 2, UiTheme.MENU_STEP)
	_pages[Page.VIDEO] = _build_list(Page.VIDEO, "VIDEO", VIDEO_ITEMS,
			"LEFT RIGHT  CHANGE      ESC  BACK", 1, 14)
	_pages[Page.AUDIO] = _build_list(Page.AUDIO, "AUDIO", AUDIO_ITEMS,
			"LEFT RIGHT  CHANGE      ESC  BACK", 1, 14)
	_pages[Page.GAMEPLAY] = _build_list(Page.GAMEPLAY, "GAMEPLAY", GAMEPLAY_ITEMS,
			"LEFT RIGHT  CHANGE      ESC  BACK", 1, 14)
	_pages[Page.CONTROLS] = _build_controls()
	show_page(Page.ROOT)


func _heading(page: Control, text: String, hint: String, y: int = 28) -> void:
	var head := PixelLabel.make(text, 3, UiTheme.BONE_BRIGHT)
	head.shadow_tint = UiTheme.TITLE_SHADOW
	head.shadow_offset = Vector2(2, 2)
	head.center_on(UiTheme.VIEW.x * 0.5, y)
	page.add_child(head)
	UiTheme.add_footer(page, hint)


func _blank_page() -> Control:
	var page := Control.new()
	page.size = UiTheme.VIEW
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	return page


func _build_list(id: Page, title: String, items: Array, hint: String,
		scale_px: int, step: int) -> Control:
	var page := _blank_page()
	_heading(page, title, hint)
	var vals := _values(id)
	var box := UiTheme.add_panel(page, items, scale_px, step, vals, 210.0)
	var list := MenuList.new()
	page.add_child(list)
	list.build(items, box[0], (box[1] as Vector2).x, scale_px, step, vals)
	list.activated.connect(_on_activated.bind(id))
	list.value_changed.connect(_on_changed.bind(id))
	_lists[id] = list
	return page


## Every rebindable action, plus the fixed keys shown greyed so the page is the
## whole control scheme rather than most of it.
func _build_controls() -> Control:
	var page := _blank_page()
	_heading(page, "CONTROLS", "ENTER  REBIND      ESC  BACK", CTRL_HEAD_Y)
	var items := _control_items()
	var vals := _control_values()
	var box := UiTheme.add_panel(page, items, 1, CTRL_STEP, vals, 230.0, CTRL_PANEL_Y)
	var origin: Vector2 = box[0]
	var size_v: Vector2 = box[1]

	var list := MenuList.new()
	page.add_child(list)
	list.build(items, origin, size_v.x, 1, CTRL_STEP, vals)
	list.activated.connect(_on_activated.bind(Page.CONTROLS))
	_lists[Page.CONTROLS] = list

	# The keys the menus own: listed so the page is the whole control scheme
	# rather than most of it, but on one line — thirteen rebindable rows already
	# reach most of the way to the footer, and three more stacked under them ran
	# straight through it.
	var fixed := ""
	for row in Keys.FIXED:
		fixed += "%s  %s      " % [row[1], row[0]]
	var note := PixelLabel.make(fixed.strip_edges(), 1, UiTheme.BONE_FAINT)
	note.center_on(UiTheme.VIEW.x * 0.5, origin.y + size_v.y + 6)
	page.add_child(note)

	_notice = PixelLabel.make("", 1, UiTheme.EMBER)
	_notice.center_on(UiTheme.VIEW.x * 0.5, origin.y + size_v.y + 16)
	page.add_child(_notice)
	return page


func _control_items() -> Array:
	var out: Array = []
	for a in Keys.ACTIONS:
		out.append(String(a["name"]))
	out.append("RESTORE DEFAULT KEYS")
	out.append("BACK")
	return out


func _control_values() -> Array:
	var out: Array = []
	for a in Keys.ACTIONS:
		out.append(Keys.label(String(a["id"])))
	out.append("")
	out.append("")
	return out


# ------------------------------------------------------------------ values ---
func _values(id: Page) -> Array:
	match id:
		Page.VIDEO:
			return [Settings.scale_label(), Settings.vsync_label(),
					Settings.fps_label(), Settings.on_off(Settings.vignette),
					Settings.on_off(Settings.screen_shake), ""]
		Page.AUDIO:
			return [Settings.vol_label(Settings.vol_master),
					Settings.vol_label(Settings.vol_music),
					Settings.vol_label(Settings.vol_sfx),
					Settings.vol_label(Settings.vol_ambience), ""]
		Page.GAMEPLAY:
			return [Settings.on_off(Settings.hud_hints),
					Settings.on_off(Settings.region_banners),
					Settings.on_off(Settings.auto_equip), ""]
		_:
			return []


func _refresh(id: Page) -> void:
	if id == Page.CONTROLS:
		var vals := _control_values()
		for i in vals.size():
			(_lists[Page.CONTROLS] as MenuList).set_value(i, vals[i])
		return
	var vals := _values(id)
	for i in vals.size():
		(_lists[id] as MenuList).set_value(i, vals[i])


# ------------------------------------------------------------------- input ---
func show_page(p: Page) -> void:
	_page = p
	_rebinding = ""
	if _notice != null:
		_notice.text = ""
	for key in _pages:
		(_pages[key] as Control).visible = (key == p)
	if _lists.has(p):
		_refresh(p)


func open() -> void:
	visible = true
	show_page(Page.ROOT)


## Returns true when the key was used. The host menu closes this widget on the
## `closed` signal rather than second-guessing the page stack.
func handle_key(k: InputEventKey) -> bool:
	if not _rebinding.is_empty():
		return _handle_rebind(k)

	var list: MenuList = _lists.get(_page)
	if k.physical_keycode == KEY_ESCAPE:
		Audio.play("menu_back", 0.02)
		if _page == Page.ROOT:
			closed.emit()
		else:
			show_page(Page.ROOT)
		return true
	if list == null:
		return false
	match k.physical_keycode:
		KEY_UP, KEY_W: list.move(-1)
		KEY_DOWN, KEY_S: list.move(1)
		KEY_LEFT, KEY_A: list.nudge(-1)
		KEY_RIGHT, KEY_D: list.nudge(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: list.activate()
		_: return false
	return true


## While waiting for a new key: anything except ESC is a candidate, and a key
## already doing something else is refused with a reason rather than silently
## leaving two actions on it.
func _handle_rebind(k: InputEventKey) -> bool:
	if k.physical_keycode == KEY_ESCAPE:
		_rebinding = ""
		_notice.text = "CANCELLED"
		_centre_notice()
		return true
	var clash := Keys.conflict(_rebinding, k.physical_keycode)
	if not clash.is_empty():
		_notice.text = "%s IS ALREADY %s" % [Keys.key_name(k.physical_keycode), clash]
		_centre_notice()
		Audio.play("menu_back", 0.02)
		return true
	Keys.rebind(_rebinding, k.physical_keycode)
	Settings.save()
	_rebinding = ""
	_notice.text = ""
	_centre_notice()
	_refresh(Page.CONTROLS)
	Audio.play("menu_confirm", 0.02)
	return true


func _centre_notice() -> void:
	_notice.center_on(UiTheme.VIEW.x * 0.5, _notice.position.y)


func _on_activated(idx: int, id: Page) -> void:
	match id:
		Page.ROOT:
			match idx:
				0: show_page(Page.VIDEO)
				1: show_page(Page.AUDIO)
				2: show_page(Page.CONTROLS)
				3: show_page(Page.GAMEPLAY)
				4:
					Settings.restore_defaults()
					for p in _lists:
						_refresh(p)
				5: closed.emit()
		Page.CONTROLS:
			if idx < Keys.ACTIONS.size():
				_rebinding = String(Keys.ACTIONS[idx]["id"])
				_notice.text = "PRESS A KEY      ESC  CANCEL"
				_centre_notice()
			elif idx == Keys.ACTIONS.size():
				Keys.reset()
				Settings.save()
				_refresh(Page.CONTROLS)
			else:
				show_page(Page.ROOT)
		_:
			var last := (_values(id).size() - 1)
			if idx == last:
				show_page(Page.ROOT)
			else:
				_on_changed(idx, 1, id)     # ENTER steps a value, same as right


func _on_changed(idx: int, dir: int, id: Page) -> void:
	match id:
		Page.VIDEO:
			match idx:
				0: Settings.cycle_window(dir)
				1: Settings.cycle_vsync(dir)
				2: Settings.cycle_fps(dir)
				3:
					Settings.vignette = not Settings.vignette
					Settings.save()
				4:
					Settings.screen_shake = not Settings.screen_shake
					Settings.save()
		Page.AUDIO:
			Settings.nudge_volume(["master", "music", "sfx", "ambience"][
					clampi(idx, 0, 3)], dir)
		Page.GAMEPLAY:
			match idx:
				0: Settings.hud_hints = not Settings.hud_hints
				1: Settings.region_banners = not Settings.region_banners
				2: Settings.auto_equip = not Settings.auto_equip
			Settings.save()
	_refresh(id)
