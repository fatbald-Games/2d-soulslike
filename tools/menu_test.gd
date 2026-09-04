extends SceneTree
## Headless flow test for the menus.
##
##   godot --headless --path . --script res://tools/menu_test.gd
##
## The combat test boots Main.tscn directly, so it kept passing while both menu
## scripts failed to parse. This one boots the real title screen and walks the
## whole path a player takes: navigate, open CONTROLS, start the game, pause,
## and quit back to the title. Exits non-zero on any failure.

var _fails: Array[String] = []
var _checks := 0
var _step := 0
var _phase := 0
var _phase_frame := -1

var _menu_scene: Node
var _list: MenuList
var _scale0 := 0
var _shake0 := true


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/MainMenu.tscn")
	_menu_scene = packed.instantiate()
	root.add_child(_menu_scene)
	current_scene = _menu_scene
	print("— Ashen Hollow menu test —")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ok    %s" % label)
	else:
		var line := label if detail.is_empty() else "%s  (%s)" % [label, detail]
		print("  FAIL  %s" % line)
		_fails.append(line)


## Push a real key event through the input stack, so the scripts' own
## _unhandled_input handlers are what gets exercised.
func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _find(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name or (node.get_script() != null
			and node.get_script().resource_path.get_file() == type_name + ".gd"):
		return node
	for c in node.get_children():
		var hit := _find(c, type_name)
		if hit != null:
			return hit
	return null


func _next() -> void:
	_phase += 1
	_phase_frame = -1


func _process(_delta: float) -> bool:
	_step += 1
	_phase_frame += 1
	if _step > 1200:
		_ok("test completed within frame budget", false, "phase %d stalled" % _phase)
		return _finish()

	match _phase:
		0: _phase_boot()
		1: _phase_navigate()
		2: _phase_controls_panel()
		3: _phase_options()
		4: _phase_start_game()
		5: _phase_pause()
		6: _phase_armoury()
		7: _phase_panels_fit()
		8: _phase_quit_to_menu()
		_: return _finish()
	return false


# --------------------------------------------------------------- phases ------
func _phase_boot() -> void:
	if _phase_frame < 2:
		return
	_list = _find(_menu_scene, "MenuList") as MenuList
	_ok("title screen builds a menu list", _list != null)
	if _list == null:
		_phase = 99
		return
	# counted from the menu's own ITEMS, so adding an entry cannot stale this
	_ok("every title entry is built",
			_list._labels.size() == _menu_scene.ITEMS.size(),
			"got %d of %d" % [_list._labels.size(), _menu_scene.ITEMS.size()])
	_ok("the title screen offers an options entry",
			_menu_scene.ITEMS.has("OPTIONS"))
	# read the constant off the script itself — instantiating a CanvasLayer here
	# and never freeing it leaks a node, which the runner reports at exit
	var pause_script: GDScript = load("res://scripts/PauseMenu.gd")
	var pause_items: Array = pause_script.get_script_constant_map()["ITEMS"]
	_ok("the pause menu offers a progress page", pause_items.has("PROGRESS"))
	_ok("first entry starts selected", _list.index == 0)
	_ok("a cursor skull is present", _list._cursor != null)
	_ok("the backdrop art loaded", UiTheme.tex("menu_bg.png") != null)
	_ok("the bone font loaded", PixelLabel.font() != null)

	# A character the font does not have renders as a blank, silently — that is
	# how "S + SPACE" shipped reading "S   SPACE". Check every string the UI
	# actually shows.
	var missing := _unrenderable()
	_ok("every UI string is fully renderable", missing.is_empty(),
			"missing glyphs: %s" % missing)
	_next()


func _unrenderable() -> String:
	var strings: Array = []
	strings.append_array(_menu_scene.ITEMS)
	strings.append_array(_menu_scene.OPTION_ITEMS)
	for r in UiTheme.CONTROL_ROWS:
		strings.append(r[0])
		strings.append(r[1])
	for a in LevelMap.AREAS:
		strings.append(a["name"])
	# the armoury prints every name and every description straight into a panel,
	# and a character the bone font has no glyph for silently vanishes there
	for d in Weapons.DEFS:
		strings.append(d["name"])
		strings.append(d["desc"])
	strings.append_array(Run.STAT_NAMES)
	strings.append_array(Run.STAT_EFFECTS)
	for e in LevelMap.ENTITIES:
		if e.has("text"):
			strings.append(e["text"])
	var missing := ""
	for s in strings:
		for i in (s as String).length():
			var c: String = (s as String)[i].to_upper()
			if PixelLabel.CHARS.find(c) < 0 and not missing.contains(c):
				missing += c
	return missing


func _phase_navigate() -> void:
	var last: int = _list._labels.size() - 1
	match _phase_frame:
		0: _key(KEY_DOWN)
		2: _ok("DOWN moves the selection", _list.index == 1, "index=%d" % _list.index)
		3: _key(KEY_S)
		5: _ok("S also moves the selection", _list.index == 2, "index=%d" % _list.index)
		6:
			# step to the last entry, then one past it
			for i in range(_list.index, last + 1):
				_key(KEY_DOWN)
		8: _ok("selection wraps past the last entry", _list.index == 0,
				"index=%d" % _list.index)
		9: _key(KEY_UP)
		11:
			_ok("UP wraps back to the last entry", _list.index == last,
					"index=%d" % _list.index)
			_ok("the cursor tracks the selected row",
					absf(_list._cursor.position.y - _list._labels[last].position.y) < 6.0)
			_next()


## Screen enum: 0 MAIN, 1 CONTROLS, 2 OPTIONS.
func _phase_controls_panel() -> void:
	match _phase_frame:
		0:
			_ok("the title starts on the main screen", _menu_scene._screen == 0,
					"screen=%d" % _menu_scene._screen)
			_list.index = 1                 # CONTROLS
			_key(KEY_ENTER)
		2:
			_ok("ENTER on CONTROLS opens the controls screen",
					_menu_scene._screen == 1, "screen=%d" % _menu_scene._screen)
			_ok("only the controls page is visible",
					_menu_scene._pages[1].visible and not _menu_scene._pages[0].visible)
			_key(KEY_ESCAPE)
		4:
			_ok("ESC returns from CONTROLS", _menu_scene._screen == 0,
					"screen=%d" % _menu_scene._screen)
			_next()


func _phase_options() -> void:
	match _phase_frame:
		0:
			_list.index = 2                 # OPTIONS
			_key(KEY_ENTER)
		2:
			_ok("ENTER on OPTIONS opens the options screen",
					_menu_scene._screen == 2, "screen=%d" % _menu_scene._screen)
			_scale0 = Settings.window_scale
			_shake0 = Settings.screen_shake
			_key(KEY_RIGHT)                 # first row is WINDOW
		4:
			_ok("RIGHT changes the window setting",
					Settings.window_scale != _scale0,
					"%d -> %d" % [_scale0, Settings.window_scale])
			_ok("the options row shows its new value",
					_menu_scene._options._values[0].text == Settings.scale_label(),
					"shows %s" % _menu_scene._options._values[0].text)
			_key(KEY_DOWN)
		6:
			_key(KEY_RIGHT)                 # SCREEN SHAKE
		8:
			_ok("RIGHT toggles screen shake",
					Settings.screen_shake != _shake0)
			_ok("changed settings are written to disk",
					FileAccess.file_exists(Settings.PATH))
			_key(KEY_ESCAPE)
		10:
			_ok("ESC returns from OPTIONS", _menu_scene._screen == 0,
					"screen=%d" % _menu_scene._screen)
			# leave the user's settings as we found them
			Settings.window_scale = _scale0
			Settings.screen_shake = _shake0
			Settings.save()
			_next()


func _phase_start_game() -> void:
	if _phase_frame == 0:
		_list.index = 0                     # NEW GAME
		_key(KEY_ENTER)
		return
	if _phase_frame < 12:
		return
	var scn := current_scene
	_ok("NEW GAME loads the combat scene",
			is_instance_valid(scn) and scn.scene_file_path == "res://scenes/Main.tscn",
			"scene=%s" % (scn.scene_file_path if is_instance_valid(scn) else "<freed>"))
	if not is_instance_valid(scn) or scn.scene_file_path != "res://scenes/Main.tscn":
		_phase = 99
		return
	_ok("the started game spawns a player", scn.player != null)
	_ok("the started game builds its HUD", scn.hud != null)
	_ok("the started game builds a pause menu", scn.pause_menu != null)
	_next()


func _phase_pause() -> void:
	var pm = current_scene.pause_menu
	match _phase_frame:
		0:
			_ok("the game does not start paused", not paused)
			_key(KEY_ESCAPE)
		2:
			_ok("ESC opens the pause menu", pm.is_open())
			_ok("opening the pause menu freezes the game", paused)
			_key(KEY_ESCAPE)
		4:
			_ok("ESC closes the pause menu again", not pm.is_open())
			_ok("closing the pause menu unfreezes the game", not paused)
			_next()


## The armoury page: six rows, the ones you have not found marked as such, and
## no way to equip something you are not carrying.
func _phase_armoury() -> void:
	var bm = current_scene.bonfire_menu
	match _phase_frame:
		0:
			bm.open()
		2:
			_ok("the bonfire opens its menu", bm.is_open())
			_ok("the bonfire offers an armoury", bm.ITEMS.has("ARMOURY"))
			bm._menu.index = bm.ITEMS.find("ARMOURY")
			bm._menu._apply()
			_key(KEY_ENTER)
		4:
			_ok("ENTER opens the armoury", bm._screen == 2,
					"screen=%d" % bm._screen)
			_ok("the armoury lists every weapon plus a way out",
					bm._armoury._labels.size() == Weapons.DEFS.size() + 1,
					"%d rows" % bm._armoury._labels.size())
			_ok("a weapon you have not found says so",
					bm._armoury._values[Weapons.AXE].text == "NOT FOUND",
					bm._armoury._values[Weapons.AXE].text)
			_ok("the weapon in your hands says so",
					bm._armoury._values[Weapons.SWORD].text == "IN HAND",
					bm._armoury._values[Weapons.SWORD].text)
			_ok("each row explains what the weapon is for",
					not (bm._blurb.text as String).is_empty())
			bm._armoury.index = Weapons.AXE
			bm._armoury._apply()
			_key(KEY_ENTER)
		6:
			_ok("a weapon you have not found cannot be equipped",
					Run.weapon == Weapons.SWORD, "weapon=%d" % Run.weapon)
			_key(KEY_ESCAPE)
		8:
			_ok("ESC leaves the armoury", bm._screen == 0, "screen=%d" % bm._screen)
			_key(KEY_ESCAPE)
		10:
			_ok("ESC closes the bonfire menu", not bm.is_open())
			_ok("leaving the bonfire unpauses the game", not paused)
			_next()


## Every menu panel is sized from its own contents, so adding a row can quietly
## push one down through the footer band and hide half of it. This is that
## check: nothing is allowed to reach into the footer.
func _phase_panels_fit() -> void:
	var limit := UiTheme.VIEW.y - 17.0
	var over: Array = []
	for root in [current_scene.pause_menu, current_scene.bonfire_menu]:
		for n in _panels(root):
			if n.position.y + n.size.y > limit:
				over.append("%.0f" % (n.position.y + n.size.y))
	_ok("no menu panel reaches into the footer band", over.is_empty(),
			"bottoms at %s, footer starts at %.0f" % [str(over), limit])
	_next()


func _panels(node: Node) -> Array:
	var out: Array = []
	if node is NinePatchRect and (node as NinePatchRect).size.x > 100.0:
		out.append(node)
	for c in node.get_children():
		out.append_array(_panels(c))
	return out


func _phase_quit_to_menu() -> void:
	# current_scene is briefly null while the scene swaps, so only reach for the
	# pause menu inside the steps that actually need it
	match _phase_frame:
		0:
			_key(KEY_ESCAPE)
		2:
			# last entry, so adding a page to the pause menu cannot stale this
			var pm = current_scene.pause_menu
			pm._menu.index = pm.ITEMS.size() - 1          # QUIT TO TITLE
			_key(KEY_ENTER)
	if _phase_frame < 14:
		return
	var scn := current_scene
	_ok("QUIT TO TITLE returns to the title screen",
			is_instance_valid(scn)
			and scn.scene_file_path == "res://scenes/MainMenu.tscn",
			"scene=%s" % (scn.scene_file_path if is_instance_valid(scn) else "<freed>"))
	_ok("leaving the pause menu unfreezes the tree", not paused)
	_next()


func _finish() -> bool:
	print("")
	if _fails.is_empty():
		print("PASS — %d checks" % _checks)
		quit(0)
	else:
		print("FAIL — %d of %d checks failed:" % [_fails.size(), _checks])
		for f in _fails:
			print("   • %s" % f)
		quit(1)
	return true
