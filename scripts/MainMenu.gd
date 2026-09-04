extends Node2D
## The title screen: a crypt lit by two guttering torches, a skull rising out of
## the bone heap, and a panel with the way in.
##
## The backdrop PNG bakes the stonework, the skull and the pile; everything that
## should MOVE (torch flames, their light, drifting embers) is layered on here,
## so the screen breathes instead of sitting there as a still image.
##
## Three screens share one input handler and one panel style: MAIN, CONTROLS and
## OPTIONS. Only one is visible at a time.

enum Screen { MAIN, CONTROLS, OPTIONS }

const ITEMS := ["NEW GAME", "CONTROLS", "OPTIONS", "QUIT"]
const OPTION_ITEMS := ["WINDOW", "SCREEN SHAKE", "HUD HINTS", "BACK"]
const TORCH_XS := [34.0, 350.0]
const TORCH_Y := 62.0

var _screen: Screen = Screen.MAIN
var _menu: MenuList
var _options: MenuList
var _pages: Dictionary = {}
var _lights: Array = []
var _t := 0.0
var _leaving := false


func _ready() -> void:
	Settings.load_once()
	Settings.apply_window()
	_build_scene()
	_pages[Screen.MAIN] = _build_main_page()
	_pages[Screen.CONTROLS] = _build_controls_page()
	_pages[Screen.OPTIONS] = _build_options_page()
	_show(Screen.MAIN)


# ------------------------------------------------------------------ scene ----
func _build_scene() -> void:
	RenderingServer.set_default_clear_color(Color(0.03, 0.028, 0.045))

	var bg := Sprite2D.new()
	bg.texture = UiTheme.tex("menu_bg.png")
	bg.centered = false
	add_child(bg)

	var cm := CanvasModulate.new()
	cm.color = Color(0.46, 0.43, 0.52)
	add_child(cm)

	for x in TORCH_XS:
		_torch(x, TORCH_Y)
		_ember_column(x, TORCH_Y)


func _torch(x: float, y: float) -> void:
	var a := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	SpriteUtil.add_anim(sf, "burn", load("res://assets/sprites/torch.png"),
			[0, 1], 7.0, true, 8, 10)
	a.sprite_frames = sf
	a.animation = "burn"
	a.centered = true
	a.position = Vector2(x, y)
	a.play("burn")
	add_child(a)

	var l := PointLight2D.new()
	l.texture = load("res://assets/sprites/light_soft.png")
	l.color = Color(1.0, 0.68, 0.38)
	l.energy = 2.0
	l.texture_scale = 1.15
	l.position = Vector2(x, y + 4)
	add_child(l)
	_lights.append({"node": l, "base": 2.0, "phase": randf() * TAU})


func _ember_column(x: float, y: float) -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(x, y - 4)
	p.amount = 10
	p.lifetime = 2.6
	p.local_coords = false
	var dot := AtlasTexture.new()
	dot.atlas = load("res://assets/sprites/light_soft.png")
	dot.region = Rect2(116, 116, 24, 24)
	p.texture = dot
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.direction = Vector2(0, -1)
	p.spread = 24.0
	p.gravity = Vector2(4, -12)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 0.10
	p.scale_amount_max = 0.22
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.82, 0.42, 0.85))
	g.set_color(1, Color(0.8, 0.22, 0.08, 0.0))
	p.color_ramp = g
	add_child(p)


# --------------------------------------------------------------------- ui ----
## A screen: its own CanvasLayer, with ONE heading in a fixed spot and a footer.
## Sub-pages replace the game title rather than stacking a second heading under
## it — two headings at once is what made the options screen look crowded.
func _page(heading: String, scale_px: int, hint: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := PixelLabel.make(heading, scale_px, UiTheme.BONE_BRIGHT)
	title.shadow_tint = UiTheme.TITLE_SHADOW
	title.shadow_offset = Vector2(2, 2)
	title.center_on(UiTheme.VIEW.x * 0.5,
			UiTheme.TITLE_Y + (0 if scale_px >= 4 else 6))
	layer.add_child(title)

	# the bone heap runs right along the bottom, so the hint needs its own dark
	# band or it disappears into the bones
	var footer := ColorRect.new()
	footer.color = Color(0.02, 0.018, 0.03, 0.82)
	footer.position = Vector2(0, UiTheme.VIEW.y - 17)
	footer.size = Vector2(UiTheme.VIEW.x, 17)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(footer)

	var rule := ColorRect.new()
	rule.color = Color(0.36, 0.33, 0.30, 0.55)
	rule.position = Vector2(0, UiTheme.VIEW.y - 17)
	rule.size = Vector2(UiTheme.VIEW.x, 1)
	layer.add_child(rule)

	var tip := PixelLabel.make(hint, 1, UiTheme.BONE_FAINT)
	tip.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 12)
	layer.add_child(tip)
	return layer


func _build_main_page() -> CanvasLayer:
	var layer := _page("ASHEN HOLLOW", 4, "UP DOWN  SELECT      ENTER  CONFIRM")

	var sub := PixelLabel.make("THE ASH REMEMBERS", 1, UiTheme.BONE_FAINT)
	sub.center_on(UiTheme.VIEW.x * 0.5, UiTheme.SUB_Y)
	layer.add_child(sub)

	var box := UiTheme.add_panel(layer, ITEMS)
	var origin: Vector2 = box[0]
	var size: Vector2 = box[1]

	_menu = MenuList.new()
	layer.add_child(_menu)
	_menu.build(ITEMS, origin, size.x)
	_menu.activated.connect(_on_main_activated)
	return layer


func _build_controls_page() -> CanvasLayer:
	var layer := _page("CONTROLS", 3, "ESC  BACK")

	# size the panel to the widest name + key pair, so the two columns line up
	var names: Array = []
	var keys: Array = []
	for r in UiTheme.CONTROL_ROWS:
		names.append(r[0])
		keys.append(r[1])
	var box := UiTheme.add_panel(layer, names, 1, 12, keys, 190.0)
	var origin: Vector2 = box[0]
	var size: Vector2 = box[1]
	UiTheme.add_rows(layer, UiTheme.CONTROL_ROWS, origin, size.x)

	var tip := PixelLabel.make("THE ROLL IS INVULNERABLE IN ITS MIDDLE - TIME IT", 1,
			UiTheme.BONE_FAINT)
	tip.center_on(UiTheme.VIEW.x * 0.5, origin.y + size.y + 8)
	layer.add_child(tip)
	return layer


func _build_options_page() -> CanvasLayer:
	var layer := _page("OPTIONS", 3, "LEFT RIGHT  CHANGE      ESC  BACK")

	var vals := _option_values()
	var box := UiTheme.add_panel(layer, OPTION_ITEMS, 2, UiTheme.MENU_STEP, vals, 190.0)
	var origin: Vector2 = box[0]
	var size: Vector2 = box[1]

	_options = MenuList.new()
	layer.add_child(_options)
	_options.build(OPTION_ITEMS, origin, size.x, 2, UiTheme.MENU_STEP, vals)
	_options.activated.connect(_on_option_activated)
	_options.value_changed.connect(_on_option_changed)
	return layer


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
		var layer: CanvasLayer = _pages[key]
		layer.visible = (key == s)


# ------------------------------------------------------------------ input ----
func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return

	match _screen:
		Screen.MAIN:
			_input_list(k, _menu)
		Screen.OPTIONS:
			if k.physical_keycode == KEY_ESCAPE:
				_show(Screen.MAIN)
			else:
				_input_list(k, _options)
		Screen.CONTROLS:
			if k.physical_keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_show(Screen.MAIN)


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


func _on_main_activated(idx: int) -> void:
	match idx:
		0:
			_start_game()
		1:
			_show(Screen.CONTROLS)
		2:
			_show(Screen.OPTIONS)
		3:
			get_tree().quit()


func _on_option_activated(idx: int) -> void:
	if idx == 3:
		_show(Screen.MAIN)
	else:
		_on_option_changed(idx, 1)      # ENTER toggles, same as pushing right


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


func _start_game() -> void:
	_leaving = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _process(delta: float) -> void:
	_t += delta
	for e in _lights:
		var n: PointLight2D = e["node"]
		n.energy = e["base"] * (1.0 + 0.16 * sin(_t * 7.0 + e["phase"])
				+ 0.08 * sin(_t * 17.0 + e["phase"]))
