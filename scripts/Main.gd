extends Node2D
## Ashen Hollow — playable combat slice.
## Builds the level, the lighting, the HUD and the actors entirely in code, so
## the project runs without depending on pre-generated .import/.uid files.

const TW := LevelMap.TILE
const S := "res://assets/sprites/"

const RUNE_READ_RANGE := 26.0        # how close you must stand to read a stone
const BONFIRE_RANGE := 28.0          # how close you must stand to rest
const SOUL_PICKUP_RANGE := 20.0
const SHAKE_DECAY := 7.0

var level: Level
var world_w := float(LevelMap.W * TW)
var world_h := float(LevelMap.H * TW)
var floor_top := 0.0                 # y the player spawns standing on

var _lights: Array = []
var _runes: Array = []               # [{node, pos, text}]
var _bonfires: Array = []            # world positions
var _soul_orb: Node2D = null
var _camera: Camera2D
var _shake := 0.0
var _sparks: CPUParticles2D
var _t := 0.0
var _area := ""
var hud                     # HUD.gd instance (untyped: it has no class_name)
var pause_menu              # PauseMenu.gd instance
var player: Player


func _ready() -> void:
	_setup_input()
	level = Level.new()
	add_child(level)
	_build_lighting_root()
	hud = _build_hud()
	pause_menu = _build_pause_menu()
	_spawn_entities()
	_place_at_checkpoint()
	_build_sparks()
	_wire_hud()
	_build_camera()
	_spawn_soul_orb()


# ------------------------------------------------------------------ input ----
func _setup_input() -> void:
	_action("left", [KEY_A, KEY_LEFT])
	_action("right", [KEY_D, KEY_RIGHT])
	# up/down drive the ladders, so jump keeps SPACE to itself — sharing W with
	# "jump" would make every climb start with a hop
	_action("up", [KEY_W, KEY_UP])
	_action("down", [KEY_S, KEY_DOWN])
	_action("jump", [KEY_SPACE])
	_action("attack", [KEY_J], MOUSE_BUTTON_LEFT)
	_action("dodge", [KEY_K, KEY_SHIFT])
	_action("heal", [KEY_Q])
	_action("interact", [KEY_E])


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


## Everything in the dungeon is placed from LevelMap.ENTITIES, so moving a
## bonfire is a change to the generator — and therefore something the
## reachability check gets a say in — rather than a stray constant in here.
func _spawn_entities() -> void:
	for e in LevelMap.ENTITIES:
		var kind: String = e["kind"]
		var tx: int = e["x"]
		var ty: int = e["y"]
		# entity rows name the tile the actor STANDS IN, so its feet belong on
		# the bottom edge of that tile
		var foot := Vector2((tx + 0.5) * TW, float((ty + 1) * TW))
		match kind:
			"player":
				floor_top = foot.y
				player = _spawn_player(foot)
			"hollow":
				_spawn_hollow(foot)
			"bonfire":
				_bonfires.append(foot)
				_bonfire(foot)
			"torch":
				_torch(Vector2((tx + 0.5) * TW, (ty + 0.5) * TW))
			"mushroom":
				_glow_prop("mushroom.png", 7, 7, foot + Vector2(0, -4),
						Color(0.52, 1.0, 0.60), 0.85, 0.5)
			"brazier":
				_glow_prop("brazier.png", 9, 9, foot + Vector2(0, -5),
						Color(1.0, 0.52, 0.20), 1.5, 0.85)
			"rune":
				_rune(foot, e["text"])


func _box(parent: Node, pos: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	cs.position = pos
	parent.add_child(cs)


func _bonfire(foot: Vector2) -> void:
	_anim_prop("bonfire.png", 24, 24, [0, 1, 2, 3], 8.0, foot + Vector2(0, -12))
	_embers(foot + Vector2(0, -16))
	_light(self, foot + Vector2(0, -14), Color(1.0, 0.72, 0.42), 1.55, 0.95, 0.13)


## Torches take the colour of the region they burn in — cold blue stone under
## warm orange light still reads as the room you just left.
func _torch(pos: Vector2) -> void:
	_anim_prop("torch.png", 8, 10, [0, 1], 7.0, pos)
	_light(self, pos + Vector2(0, 4), level.light_at(pos), 1.35, 1.05, 0.18)


## A small animated prop that casts its own light: glowing fungus, forge fires.
func _glow_prop(sheet: String, fw: int, fh: int, pos: Vector2,
		col: Color, energy: float, tscale: float) -> void:
	_anim_prop(sheet, fw, fh, [0, 1], 3.5, pos)
	_light(self, pos, col, energy, tscale, 0.22)


## An inscribed stone. It lights up and shows its line when you stand on it —
## the only storytelling in the game, so it has to be readable in passing.
func _rune(foot: Vector2, text: String) -> void:
	var s := Sprite2D.new()
	s.texture = SpriteUtil.frame_of(_tex("rune.png"), 0, 7, 7)
	s.position = foot + Vector2(0, -5)
	add_child(s)
	_runes.append({"node": s, "pos": s.position, "text": text})


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


## Only the darkness itself — every actual light rides along with the torch or
## bonfire that casts it, placed from the map.
func _build_lighting_root() -> void:
	RenderingServer.set_default_clear_color(Color(0.03, 0.028, 0.045))
	var cm := CanvasModulate.new()
	# a big level needs a higher ambient floor than one flat corridor did,
	# or the stretches between torches read as solid black nothing
	cm.color = Color(0.30, 0.28, 0.36)
	add_child(cm)


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
	# collide with the world AND with one-way beams; Player mutes the beam
	# layer on its own for a moment when dropping through one
	p.set_collision_mask_value(Level.WORLD_LAYER, true)
	p.set_collision_mask_value(Level.BEAM_LAYER, true)
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
	h.set_collision_mask_value(Level.WORLD_LAYER, true)
	h.set_collision_mask_value(Level.BEAM_LAYER, true)
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


func _build_pause_menu() -> CanvasLayer:
	var p: CanvasLayer = load("res://scripts/PauseMenu.gd").new()
	add_child(p)
	p.quit_to_menu.connect(_on_quit_to_menu)
	return p


func _on_quit_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _wire_hud() -> void:
	player.health_changed.connect(hud.set_health)
	player.stamina_changed.connect(hud.set_stamina)
	player.souls_changed.connect(hud.set_souls)
	player.souls_changed.connect(func(n: int) -> void: Run.souls = n)
	player.flask_changed.connect(func(c: int, _m: int) -> void: Run.flask = c)
	player.flask_changed.connect(hud.set_flask)
	player.hit_landed.connect(_on_hit_landed)
	player.died.connect(_on_player_died)
	hud.set_health(player.health, Player.HEALTH_MAX)
	hud.set_stamina(player.stamina, Player.STAMINA_MAX)
	hud.set_souls(player.souls)
	hud.set_flask(player.flask, Player.FLASK_MAX)


func _on_player_died() -> void:
	Run.drop(player.global_position, player.souls)
	Run.flask = Player.FLASK_MAX          # the flask is refilled by dying, too
	_add_shake(3.0)
	hud.show_died()
	var t := get_tree().create_timer(2.8)
	t.timeout.connect(func(): get_tree().reload_current_scene())


## Death reloads the scene, so the knight has to be put back at the bonfire he
## last rested at rather than at the map's spawn tile.
func _place_at_checkpoint() -> void:
	if player == null or not Run.has_checkpoint:
		return
	player.global_position = Run.checkpoint
	player.velocity = Vector2.ZERO
	player.souls = Run.souls
	player.flask = Run.flask
	player.souls_changed.emit(player.souls)
	player.flask_changed.emit(player.flask, Player.FLASK_MAX)


## The souls you were carrying when you died, waiting where you fell.
func _spawn_soul_orb() -> void:
	if not Run.has_drop:
		return
	var a := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	SpriteUtil.add_anim(sf, "glow", _tex("soul_orb.png"), [0, 1, 2, 3], 6.0, true, 11, 11)
	a.sprite_frames = sf
	a.animation = "glow"
	a.centered = true
	a.position = Run.drop_pos + Vector2(0, -10)
	a.play("glow")
	add_child(a)
	_light(a, Vector2.ZERO, Color(0.62, 0.95, 0.92), 0.7, 0.35, 0.0)
	_soul_orb = a


func _build_sparks() -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10
	p.lifetime = 0.34
	p.local_coords = false
	var dot := AtlasTexture.new()
	dot.atlas = _tex("light_soft.png")
	dot.region = Rect2(120, 120, 16, 16)
	p.texture = dot
	p.spread = 180.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 0.10
	p.scale_amount_max = 0.24
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.92, 0.72, 1.0))
	g.set_color(1, Color(0.85, 0.20, 0.12, 0.0))
	p.color_ramp = g
	add_child(p)
	_sparks = p


## Sparks and a kick of the camera, so a landed blow reads as contact.
func _on_hit_landed(at: Vector2) -> void:
	if _sparks != null:
		_sparks.position = at
		_sparks.restart()
		_sparks.emitting = true
	_add_shake(1.6)


func _add_shake(amount: float) -> void:
	if Settings.screen_shake:
		_shake = minf(4.0, _shake + amount)


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
	_camera = cam


func _process(delta: float) -> void:
	_t += delta
	for e in _lights:
		var n: PointLight2D = e["node"]
		var a: float = e["amp"]
		n.energy = e["base"] * (1.0 + a * sin(_t * 7.0 + e["phase"])
				+ a * 0.5 * sin(_t * 17.0 + e["phase"]))
	_tick_shake(delta)
	if player != null and is_instance_valid(player):
		_track_area()
		_track_runes()
		_track_bonfire()
		_track_soul_orb()


func _tick_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake <= 0.001:
		_camera.offset = Vector2.ZERO
		return
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	# whole pixels only: a fractional camera offset makes the whole pixel-art
	# scene shimmer instead of shaking
	_camera.offset = Vector2(roundf(randf_range(-_shake, _shake)),
			roundf(randf_range(-_shake, _shake)))


## Resting is the whole structure of the game: it heals, refills the flask,
## puts every hollow back, and makes this fire the place you respawn.
func _track_bonfire() -> void:
	var near := Vector2.INF
	for pos in _bonfires:
		if player.global_position.distance_to(pos) < BONFIRE_RANGE:
			near = pos
			break
	if near == Vector2.INF:
		hud.show_prompt("")
		return
	hud.show_prompt("E   REST")
	if Input.is_action_just_pressed("interact") and player.state != Player.State.DEAD:
		_rest_at(near)


func _rest_at(pos: Vector2) -> void:
	Run.rest_at(pos)
	player.rest()
	_respawn_hollows()
	hud.show_prompt("")
	hud.show_area("RESTED")


## Every hollow comes back, exactly where the map put them.
func _respawn_hollows() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	for e in LevelMap.ENTITIES:
		if e["kind"] != "hollow":
			continue
		var tx: int = e["x"]
		var ty: int = e["y"]
		_spawn_hollow(Vector2((tx + 0.5) * TW, float((ty + 1) * TW)))


func _track_soul_orb() -> void:
	if _soul_orb == null or not is_instance_valid(_soul_orb):
		return
	if player.global_position.distance_to(_soul_orb.position) > SOUL_PICKUP_RANGE:
		return
	player.add_souls(Run.collect())
	_soul_orb.queue_free()
	_soul_orb = null


## The map is far too big to hold in your head, so crossing into a new region
## announces itself the way a souls game does.
func _track_area() -> void:
	var here := level.area_at(player.global_position + Vector2(0, -12))
	if here != "" and here != _area:
		_area = here
		hud.show_area(here)


func _track_runes() -> void:
	var nearest := ""
	var best := RUNE_READ_RANGE
	for r in _runes:
		var pos: Vector2 = r["pos"]
		var d := player.global_position.distance_to(pos)
		if d < best:
			best = d
			nearest = r["text"]
		var s: Sprite2D = r["node"]
		s.texture = SpriteUtil.frame_of(_tex("rune.png"),
				1 if d < RUNE_READ_RANGE else 0, 7, 7)
	hud.show_inscription(nearest)
