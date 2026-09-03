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
		3: _phase_start_game()
		4: _phase_pause()
		5: _phase_quit_to_menu()
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
	_ok("menu offers three entries", _list._labels.size() == 3,
			"got %d" % _list._labels.size())
	_ok("first entry starts selected", _list.index == 0)
	_ok("a cursor skull is present", _list._cursor != null)
	_ok("the backdrop art loaded", UiTheme.tex("menu_bg.png") != null)
	_ok("the bone font loaded", PixelLabel.font() != null)
	_next()


func _phase_navigate() -> void:
	match _phase_frame:
		0: _key(KEY_DOWN)
		2: _ok("DOWN moves the selection", _list.index == 1, "index=%d" % _list.index)
		3: _key(KEY_S)
		5: _ok("S also moves the selection", _list.index == 2, "index=%d" % _list.index)
		6: _key(KEY_DOWN)
		8: _ok("selection wraps past the last entry", _list.index == 0,
				"index=%d" % _list.index)
		9: _key(KEY_UP)
		11:
			_ok("UP wraps back to the last entry", _list.index == 2,
					"index=%d" % _list.index)
			_next()


func _phase_controls_panel() -> void:
	var panel: CanvasLayer = _menu_scene._controls
	match _phase_frame:
		0:
			_ok("the controls panel starts hidden", not panel.visible)
			_list.index = 1                 # CONTROLS
			_key(KEY_ENTER)
		2:
			_ok("ENTER on CONTROLS opens the panel", panel.visible)
			_key(KEY_ESCAPE)
		4:
			_ok("ESC closes the controls panel", not panel.visible)
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


func _phase_quit_to_menu() -> void:
	# current_scene is briefly null while the scene swaps, so only reach for the
	# pause menu inside the steps that actually need it
	match _phase_frame:
		0:
			_key(KEY_ESCAPE)
		2:
			current_scene.pause_menu._menu.index = 2      # QUIT TO MENU
			_key(KEY_ENTER)
	if _phase_frame < 14:
		return
	var scn := current_scene
	_ok("QUIT TO MENU returns to the title screen",
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
