extends CanvasLayer
## What a bonfire is for: rest, or spend what you carried out of the dark.
##
## Same panel, cursor and footer as every other menu, and it pauses the tree the
## same way — nothing should be able to hit you while you are reading numbers.
##
## Levelling lives here rather than in the pause menu on purpose: souls are only
## safe at a fire, so the decision to spend them belongs at the fire.

signal rested
signal levelled
signal equipped(idx: int)

const ITEMS := ["REST", "LEVEL UP", "ARMOURY", "LEAVE"]
const ARMOURY_STEP := 13

enum Screen { MAIN, LEVEL, ARMOURY }

var _screen: Screen = Screen.MAIN
var _menu: MenuList
var _levels: MenuList
var _armoury: MenuList
var _pages: Dictionary = {}
var _cost: PixelLabel
var _blurb: PixelLabel
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9                        # above the HUD, below the pause menu
	_build()
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.018, 0.03, 0.74)
	shade.size = UiTheme.VIEW
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_pages[Screen.MAIN] = _build_main()
	_pages[Screen.LEVEL] = _build_level()
	_pages[Screen.ARMOURY] = _build_armoury()
	_show(Screen.MAIN)


func _page(heading: String, hint: String) -> Control:
	var page := Control.new()
	page.size = UiTheme.VIEW
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

	var head := PixelLabel.make(heading, 3, UiTheme.BONE_BRIGHT)
	head.shadow_tint = UiTheme.TITLE_SHADOW
	head.shadow_offset = Vector2(2, 2)
	head.center_on(UiTheme.VIEW.x * 0.5, 26)
	page.add_child(head)

	UiTheme.add_footer(page, hint)
	return page


func _build_main() -> Control:
	var page := _page("BONFIRE", "UP DOWN  SELECT      ENTER  CONFIRM")
	var box := UiTheme.add_panel(page, ITEMS, 2, UiTheme.MENU_STEP, [], 160.0)
	_menu = MenuList.new()
	page.add_child(_menu)
	_menu.build(ITEMS, box[0], (box[1] as Vector2).x)
	_menu.activated.connect(_on_activated)
	return page


func _build_level() -> Control:
	var page := _page("LEVEL UP", "ENTER  SPEND      ESC  BACK")
	var items := _level_items()
	var box := UiTheme.add_panel(page, items, 1, 13, _level_values(), 230.0)
	var origin: Vector2 = box[0]
	var size: Vector2 = box[1]

	_levels = MenuList.new()
	page.add_child(_levels)
	_levels.build(items, origin, size.x, 1, 13, _level_values())
	_levels.activated.connect(_on_level_activated)

	_cost = PixelLabel.make("", 1, UiTheme.EMBER)
	_cost.center_on(UiTheme.VIEW.x * 0.5, origin.y + size.y + 8)
	page.add_child(_cost)
	return page


## Each row names the stat AND what it moves, so the choice can be made without
## remembering which of five words means "swings faster".
func _level_items() -> Array:
	var rows: Array = []
	for i in Run.STAT_NAMES.size():
		rows.append("%s  %s" % [Run.STAT_NAMES[i], Run.STAT_EFFECTS[i]])
	rows.append("BACK")
	return rows


func _level_values() -> Array:
	var vals: Array = []
	for i in Run.STAT_NAMES.size():
		vals.append("%d" % Run.stats[i])
	vals.append("")
	return vals


func _refresh_level() -> void:
	var vals := _level_values()
	for i in vals.size():
		_levels.set_value(i, vals[i])
	if Run.level() >= 1 + Run.STAT_MAX * Run.STAT_NAMES.size():
		_cost.text = "NOTHING LEFT TO RAISE"
	else:
		_cost.text = "LEVEL %d       NEXT COSTS %d       SOULS %d" % [
				Run.level(), Run.next_cost(), Run.souls]
	_cost.center_on(UiTheme.VIEW.x * 0.5, _cost.position.y)


## The armoury: everything the keep holds, found or not. Naming the ones you
## have NOT found yet is deliberate — five blank rows say "there is nothing out
## there", five named ones say "there are five more places to go".
func _build_armoury() -> Control:
	var page := _page("ARMOURY", "ENTER  EQUIP      ESC  BACK")
	var items := _armoury_items()
	var box := UiTheme.add_panel(page, items, 1, ARMOURY_STEP, _armoury_values(), 250.0)
	var origin: Vector2 = box[0]
	var size: Vector2 = box[1]

	_armoury = MenuList.new()
	page.add_child(_armoury)
	_armoury.build(items, origin, size.x, 1, ARMOURY_STEP, _armoury_values())
	_armoury.activated.connect(_on_armoury_activated)
	_armoury.selection_changed.connect(_on_armoury_moved)

	# what the highlighted weapon actually does. Six damage numbers mean nothing
	# without the sentence that says what the trade is.
	_blurb = PixelLabel.make("", 1, UiTheme.BONE_FAINT)
	_blurb.center_on(UiTheme.VIEW.x * 0.5, origin.y + size.y + 8)
	page.add_child(_blurb)
	return page


func _armoury_items() -> Array:
	var rows: Array = []
	for i in Weapons.DEFS.size():
		rows.append(Weapons.name_of(i))
	rows.append("BACK")
	return rows


func _armoury_values() -> Array:
	var vals: Array = []
	for i in Weapons.DEFS.size():
		if not Run.has_weapon(Weapons.DEFS[i]["id"]):
			vals.append("NOT FOUND")
		elif i == Run.weapon:
			vals.append("IN HAND")
		else:
			vals.append("READY")
	vals.append("")
	return vals


func _refresh_armoury() -> void:
	var vals := _armoury_values()
	for i in vals.size():
		_armoury.set_value(i, vals[i])
	_on_armoury_moved(_armoury.index)


func _on_armoury_moved(idx: int) -> void:
	if idx < 0 or idx >= Weapons.DEFS.size():
		_blurb.text = ""
		return
	if not Run.has_weapon(Weapons.DEFS[idx]["id"]):
		_blurb.text = "SOMEWHERE IN THE KEEP. YOU HAVE NOT FOUND IT YET."
	else:
		_blurb.text = Weapons.def(idx)["desc"]
	_blurb.center_on(UiTheme.VIEW.x * 0.5, _blurb.position.y)


func _on_armoury_activated(idx: int) -> void:
	if idx >= Weapons.DEFS.size():
		_show(Screen.MAIN)
		return
	if Run.has_weapon(Weapons.DEFS[idx]["id"]):
		equipped.emit(idx)
	_refresh_armoury()


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
	_refresh_level()
	_refresh_armoury()
	_show(Screen.MAIN)
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false


func _consume() -> void:
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return

	match _screen:
		Screen.MAIN:
			if k.physical_keycode == KEY_ESCAPE:
				close()
			else:
				_input_list(k, _menu)
		Screen.LEVEL:
			if k.physical_keycode == KEY_ESCAPE:
				_show(Screen.MAIN)
			else:
				_input_list(k, _levels)
		Screen.ARMOURY:
			if k.physical_keycode == KEY_ESCAPE:
				_show(Screen.MAIN)
			else:
				_input_list(k, _armoury)
	_consume()


func _input_list(k: InputEventKey, list: MenuList) -> void:
	match k.physical_keycode:
		KEY_UP, KEY_W:
			list.move(-1)
		KEY_DOWN, KEY_S:
			list.move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			list.activate()


func _on_activated(idx: int) -> void:
	match idx:
		0:
			rested.emit()
			close()
		1:
			_refresh_level()
			_show(Screen.LEVEL)
		2:
			_refresh_armoury()
			_show(Screen.ARMOURY)
		3:
			close()


func _on_level_activated(idx: int) -> void:
	if idx >= Run.STAT_NAMES.size():
		_show(Screen.MAIN)
		return
	if Run.raise_stat(idx):
		levelled.emit()
	_refresh_level()
