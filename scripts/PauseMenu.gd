extends CanvasLayer
## ESC brings up the pause screen over a dimmed, frozen dungeon.
##
## The tree is paused while this is open, so the node runs in ALWAYS mode —
## otherwise it would freeze along with the game and never process the keypress
## that closes it again.

signal resumed
signal quit_to_menu

const ITEMS := ["RESUME", "CONTROLS", "QUIT TO MENU"]

var _menu: MenuList
var _controls: Control
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10                       # above the HUD
	_build()
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.018, 0.03, 0.82)
	shade.size = UiTheme.VIEW
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var head := PixelLabel.make("PAUSED", 4, UiTheme.BONE_BRIGHT)
	head.shadow_tint = UiTheme.TITLE_SHADOW
	head.shadow_offset = Vector2(2, 2)
	head.center_on(UiTheme.VIEW.x * 0.5, 40)
	add_child(head)

	_menu = MenuList.new()
	add_child(_menu)
	_menu.build(ITEMS, UiTheme.VIEW.x * 0.5, 96)
	_menu.activated.connect(_on_activated)

	_controls = _build_controls()
	_controls.visible = false


func _build_controls() -> Control:
	var panel := Control.new()
	panel.size = UiTheme.VIEW
	add_child(panel)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.018, 0.03, 0.94)
	shade.size = UiTheme.VIEW
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shade)

	var head := PixelLabel.make("CONTROLS", 3, UiTheme.BONE_BRIGHT)
	head.center_on(UiTheme.VIEW.x * 0.5, 30)
	panel.add_child(head)

	var rows := [["A  D", "MOVE"], ["SPACE", "JUMP"], ["J", "ATTACK"],
			["K  SHIFT", "DODGE ROLL"], ["ESC", "PAUSE"]]
	for i in rows.size():
		var y := 64 + i * 16
		var key := PixelLabel.make(rows[i][0], 2, UiTheme.EMBER)
		key.position = Vector2(96, y)
		panel.add_child(key)
		var act := PixelLabel.make(rows[i][1], 2, UiTheme.BONE)
		act.position = Vector2(196, y)
		panel.add_child(act)

	var back := PixelLabel.make("ESC  BACK", 1, UiTheme.BONE_FAINT)
	back.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 16)
	panel.add_child(back)
	return panel


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_controls.visible = false
	_menu.index = 0
	_menu._apply()
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	resumed.emit()


## Swallow the key so the game underneath does not also act on it. Activating
## QUIT TO MENU tears this node out of the tree mid-handler, so the viewport can
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

	if _controls.visible:
		if k.physical_keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_controls.visible = false
		_consume()
		return

	match k.physical_keycode:
		KEY_UP, KEY_W:
			_menu.move(-1)
		KEY_DOWN, KEY_S:
			_menu.move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_menu.activate()
		KEY_ESCAPE:
			close()
	_consume()


func _on_activated(idx: int) -> void:
	match idx:
		0:
			close()
		1:
			_controls.visible = true
		2:
			get_tree().paused = false
			_open = false
			quit_to_menu.emit()
