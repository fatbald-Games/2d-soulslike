extends Node2D
## Ashen Hollow — playable combat slice.
## Builds the level, the lighting, the HUD and the actors entirely in code, so
## the project runs without depending on pre-generated .import/.uid files.

const TW := 16
const COLS := 64
const ROWS := 14
const FLOOR_ROWS := 5

const S := "res://assets/sprites/"

var floor_top := float((ROWS - FLOOR_ROWS) * TW)     # y of the walkable surface
var world_w := float(COLS * TW)
var world_h := float(ROWS * TW)

var _lights: Array = []
var _t := 0.0
var hud                     # HUD.gd instance (untyped: it has no class_name)
var player: Player


func _ready() -> void:
	_setup_input()
	_build_ground()
	_build_collision()
	_build_props()
	_build_lighting()
	hud = _build_hud()
	player = _spawn_player(Vector2(72, floor_top))
	_spawn_hollow(Vector2(430, floor_top))
	_spawn_hollow(Vector2(760, floor_top))
	_wire_hud()
	_build_camera()


# ------------------------------------------------------------------ input ----
func _setup_input() -> void:
	_action("left", [KEY_A, KEY_LEFT])
	_action("right", [KEY_D, KEY_RIGHT])
	_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_action("attack", [KEY_J], MOUSE_BUTTON_LEFT)
	_action("dodge", [KEY_K, KEY_SHIFT])


func _action(action_name: String, keys: Array, mouse: int = -1) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)
	if mouse >= 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse
		InputMap.action_add_event(action_name, mb)


# ------------------------------------------------------------------ level ----
func _tex(tex_name: String) -> Texture2D:
	return load(S + tex_name) as Texture2D


func _build_ground() -> void:
	RenderingServer.set_default_clear_color(Color(0.03, 0.028, 0.045))
	var floor_tex := _tex("tile_floor.png")
	var wall_tex := _tex("tile_wall.png")
	for cy in ROWS:
		for cx in COLS:
			var s := Sprite2D.new()
			s.texture = floor_tex if cy >= ROWS - FLOOR_ROWS else wall_tex
			s.centered = false
			s.position = Vector2(cx * TW, cy * TW)
			add_child(s)


func _build_collision() -> void:
	var body := StaticBody2D.new()
	add_child(body)
	_box(body, Vector2(world_w * 0.5, floor_top + (world_h - floor_top) * 0.5),
			Vector2(world_w, world_h - floor_top))          # the floor
	_box(body, Vector2(-8, world_h * 0.5), Vector2(16, world_h))   # left wall
	_box(body, Vector2(world_w + 8, world_h * 0.5), Vector2(16, world_h))


func _box(parent: Node, pos: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	cs.position = pos
	parent.add_child(cs)


func _build_props() -> void:
	_anim_prop("bonfire.png", 24, 24, [0, 1, 2, 3], 8.0, Vector2(120, floor_top - 6))
	for x in [56, 300, 560, 820, 980]:
		_anim_prop("torch.png", 8, 10, [0, 1], 7.0, Vector2(float(x), 5 * TW))
	_embers(Vector2(120, floor_top - 10))


func _anim_prop(anim_name: String, fw: int, fh: int, idx: Array, fps: float, pos: Vector2) -> void:
	var a := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	SpriteUtil.add_anim(sf, "default", _tex(anim_name), idx, fps, true, fw, fh)
	a.sprite_frames = sf
	a.animation = "default"
	a.centered = true
	a.position = pos
	a.play("default")
	add_child(a)


func _embers(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = 18
	p.lifetime = 1.9
	p.local_coords = false
	var dot := AtlasTexture.new()
	dot.atlas = _tex("light_soft.png")
	dot.region = Rect2(116, 116, 24, 24)
	p.texture = dot
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 5.0
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.gravity = Vector2(0, -10)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.28
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.45, 0.9))
	g.set_color(1, Color(0.85, 0.25, 0.10, 0.0))
	p.color_ramp = g
	add_child(p)


func _build_lighting() -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.19, 0.18, 0.25)
	add_child(cm)
	_light(self, Vector2(120, floor_top - 8), Color(1.0, 0.72, 0.42), 1.55, 0.95, 0.13)
	for x in [56, 300, 560, 820, 980]:
		_light(self, Vector2(float(x), 5 * TW + 6), Color(1.0, 0.70, 0.40), 1.0, 0.5, 0.18)


func _light(parent: Node, pos: Vector2, color: Color, energy: float,
		tscale: float, amp: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _tex("light_soft.png")
	l.color = color
	l.energy = energy
	l.texture_scale = tscale
	l.position = pos
	parent.add_child(l)
	if amp > 0.0:
		_lights.append({"node": l, "base": energy, "phase": randf() * TAU, "amp": amp})
	return l


# ----------------------------------------------------------------- actors ----
func _spawn_player(pos: Vector2) -> Player:
	var p := Player.new()
	p.position = pos
	_box(p, Vector2(0, -13), Vector2(12, 26))

	var s := SpriteUtil.make_sprite()
	s.name = "Sprite"
	var sf := SpriteFrames.new()
	SpriteUtil.add_anim(sf, "idle", _tex("hero_idle.png"), [0, 1, 2, 3], 6.0, true)
	SpriteUtil.add_anim(sf, "run", _tex("hero_run.png"), [0, 1, 2, 3, 4, 5], 10.0, true)
	SpriteUtil.add_anim(sf, "attack", _tex("hero_attack.png"), [0, 1, 2, 3],
			4.0 / Player.ATTACK_TIME, false)
	SpriteUtil.add_anim(sf, "roll", _tex("hero_roll.png"), [0, 1, 2, 3],
			4.0 / Player.ROLL_TIME, false)
	s.sprite_frames = sf
	s.animation = "idle"
	p.add_child(s)

	# a faint personal glow so the hero stays readable away from the fires
	_light(p, Vector2(0, -16), Color(0.72, 0.80, 1.0), 0.42, 0.34, 0.0)
	add_child(p)
	return p


func _spawn_hollow(pos: Vector2) -> Hollow:
	var h := Hollow.new()
	h.position = pos
	_box(h, Vector2(0, -12), Vector2(12, 24))

	var s := SpriteUtil.make_sprite()
	s.name = "Sprite"
	var tex := _tex("hollow.png")
	var sf := SpriteFrames.new()
	SpriteUtil.add_anim(sf, "idle", tex, [0, 1], 2.5, true)
	SpriteUtil.add_anim(sf, "windup", tex, [2], 1.0, false)
	SpriteUtil.add_anim(sf, "strike", tex, [3], 1.0, false)
	SpriteUtil.add_anim(sf, "hurt", tex, [4], 1.0, false)
	SpriteUtil.add_anim(sf, "dead", tex, [5], 1.0, false)
	s.sprite_frames = sf
	s.animation = "idle"
	h.add_child(s)
	add_child(h)
	return h


# -------------------------------------------------------------------- ui -----
func _build_hud() -> CanvasLayer:
	var h: CanvasLayer = load("res://scripts/HUD.gd").new()
	add_child(h)
	return h


func _wire_hud() -> void:
	player.health_changed.connect(hud.set_health)
	player.stamina_changed.connect(hud.set_stamina)
	player.souls_changed.connect(hud.set_souls)
	player.died.connect(_on_player_died)
	hud.set_health(player.health, Player.HEALTH_MAX)
	hud.set_stamina(player.stamina, Player.STAMINA_MAX)


func _on_player_died() -> void:
	hud.show_died()
	var t := get_tree().create_timer(2.8)
	t.timeout.connect(func(): get_tree().reload_current_scene())


func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(world_w)
	cam.limit_bottom = int(world_h)
	player.add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	_t += delta
	for e in _lights:
		var n: PointLight2D = e["node"]
		var a: float = e["amp"]
		n.energy = e["base"] * (1.0 + a * sin(_t * 7.0 + e["phase"])
				+ a * 0.5 * sin(_t * 17.0 + e["phase"]))
