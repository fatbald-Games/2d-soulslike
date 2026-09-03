extends Node2D
## The title screen: a crypt lit by two guttering torches, a skull rising out of
## the bone heap, and three ways in.
##
## The backdrop PNG bakes the stonework, the skull and the pile; everything that
## should MOVE (torch flames, their light, drifting embers) is layered on here,
## so the screen breathes instead of sitting there as a still image.

const ITEMS := ["NEW GAME", "CONTROLS", "QUIT"]
const TORCH_XS := [34.0, 350.0]
const TORCH_Y := 62.0

var _menu: MenuList
var _controls: CanvasLayer
var _lights: Array = []
var _t := 0.0
var _leaving := false


func _ready() -> void:
	_build_scene()
	_build_ui()
	_controls = _build_controls_panel()
	_controls.visible = false


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
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	var title := PixelLabel.make("ASHEN HOLLOW", 4, UiTheme.BONE_BRIGHT)
	title.shadow_tint = UiTheme.TITLE_SHADOW
	title.shadow_offset = Vector2(2, 2)
	title.center_on(UiTheme.VIEW.x * 0.5, UiTheme.TITLE_Y)
	ui.add_child(title)

	var sub := PixelLabel.make("THE ASH REMEMBERS", 1, UiTheme.BONE_FAINT)
	sub.center_on(UiTheme.VIEW.x * 0.5, UiTheme.SUB_Y)
	ui.add_child(sub)

	_menu = MenuList.new()
	ui.add_child(_menu)
	_menu.build(ITEMS, UiTheme.VIEW.x * 0.5, UiTheme.MENU_Y0)
	_menu.activated.connect(_on_activated)

	# the bone heap runs right along the bottom, so the hint needs its own dark
	# band or it disappears into the bones
	var footer := ColorRect.new()
	footer.color = Color(0.02, 0.018, 0.03, 0.78)
	footer.position = Vector2(0, UiTheme.VIEW.y - 17)
	footer.size = Vector2(UiTheme.VIEW.x, 17)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(footer)

	var hint := PixelLabel.make("ARROWS / W S  SELECT     ENTER  CONFIRM", 1,
			UiTheme.BONE_FAINT)
	hint.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 12)
	ui.add_child(hint)


func _build_controls_panel() -> CanvasLayer:
	var layer := CanvasLayer.new()
	add_child(layer)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.018, 0.03, 0.88)
	shade.size = UiTheme.VIEW
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)

	var head := PixelLabel.make("CONTROLS", 3, UiTheme.BONE_BRIGHT)
	head.shadow_tint = UiTheme.TITLE_SHADOW
	head.center_on(UiTheme.VIEW.x * 0.5, 26)
	layer.add_child(head)

	var rows := [
		["A  D", "MOVE"],
		["SPACE", "JUMP"],
		["J", "ATTACK"],
		["K  SHIFT", "DODGE ROLL"],
		["ESC", "PAUSE"],
	]
	for i in rows.size():
		var y := 62 + i * 16
		var key := PixelLabel.make(rows[i][0], 2, UiTheme.EMBER)
		key.position = Vector2(96, y)
		layer.add_child(key)
		var act := PixelLabel.make(rows[i][1], 2, UiTheme.BONE)
		act.position = Vector2(196, y)
		layer.add_child(act)

	var tip := PixelLabel.make("THE ROLL IS INVULNERABLE IN ITS MIDDLE - TIME IT", 1,
			UiTheme.BONE_FAINT)
	tip.center_on(UiTheme.VIEW.x * 0.5, 158)
	layer.add_child(tip)

	var back := PixelLabel.make("ESC  BACK", 1, UiTheme.BONE_FAINT)
	back.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 14)
	layer.add_child(back)
	return layer


# ------------------------------------------------------------------ input ----
func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return

	if _controls.visible:
		if k.physical_keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_controls.visible = false
		return

	match k.physical_keycode:
		KEY_UP, KEY_W:
			_menu.move(-1)
		KEY_DOWN, KEY_S:
			_menu.move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_menu.activate()
		KEY_ESCAPE:
			pass


func _on_activated(idx: int) -> void:
	match idx:
		0:
			_start_game()
		1:
			_controls.visible = true
		2:
			get_tree().quit()


func _start_game() -> void:
	_leaving = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _process(delta: float) -> void:
	_t += delta
	for e in _lights:
		var n: PointLight2D = e["node"]
		n.energy = e["base"] * (1.0 + 0.16 * sin(_t * 7.0 + e["phase"])
				+ 0.08 * sin(_t * 17.0 + e["phase"]))
