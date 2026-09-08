extends Node2D
## Ashen Hollow — playable combat slice.
## Builds the level, the lighting, the HUD and the actors entirely in code, so
## the project runs without depending on pre-generated .import/.uid files.

const TW := LevelMap.TILE
const S := "res://assets/sprites/"

const RUNE_READ_RANGE := 26.0        # how close you must stand to read a stone
const BONFIRE_RANGE := 28.0          # how close you must stand to rest
const SOUL_PICKUP_RANGE := 20.0
const PICKUP_RANGE := 22.0           # how close you must stand to take a weapon
const SHAKE_DECAY := 7.0

## How far the map fills in around him, and how often. A screen is 24 tiles
## across, so 13 reveals a little less than he can actually see — the map should
## lag behind the room, not run ahead of it.
const REVEAL_RADIUS := 13
const REVEAL_EVERY := 0.20

## Frame order in assets/sprites/deco.png (see DECO_NAMES in tools/gen_art.py).
const DECO_FRAMES := ["chain", "pillar", "bones", "roots", "icicles", "banner",
		"skull_spike", "arch"]
const DECO_W := 16
const DECO_H := 32

## What hangs in the air in each region. One particle field follows the camera
## and is reconfigured on crossing a border, rather than eight fields simulating
## a whole map's worth of motes nobody is looking at.
##
## This is the cheapest atmosphere in the game and close to the most effective:
## still air reads as a diagram, moving air reads as a place.
const AMBIENCE := {
	"gate": {"n": 42, "grav": Vector2(7, 16), "vel": 5.0, "life": 5.0,
			"col": Color(0.74, 0.70, 0.64), "size": 0.16, "amb": "amb_stone"},
	"descent": {"n": 38, "grav": Vector2(2, 24), "vel": 6.0, "life": 4.0,
			"col": Color(0.62, 0.62, 0.72), "size": 0.14, "amb": "amb_deep"},
	"ossuary": {"n": 34, "grav": Vector2(3, 9), "vel": 4.0, "life": 6.5,
			"col": Color(0.80, 0.76, 0.64), "size": 0.15, "amb": "amb_stone"},
	"cistern": {"n": 44, "grav": Vector2(0, -18), "vel": 5.0, "life": 4.5,
			"col": Color(0.55, 0.86, 0.92), "size": 0.17, "amb": "amb_water"},
	"rootworks": {"n": 48, "grav": Vector2(-3, -5), "vel": 6.0, "life": 7.0,
			"col": Color(0.55, 0.95, 0.58), "size": 0.18, "amb": "amb_deep"},
	"forge": {"n": 58, "grav": Vector2(4, -34), "vel": 14.0, "life": 3.2,
			"col": Color(1.0, 0.60, 0.24), "size": 0.20, "amb": "amb_forge"},
	"vault": {"n": 54, "grav": Vector2(6, 20), "vel": 6.0, "life": 5.0,
			"col": Color(0.86, 0.93, 1.0), "size": 0.18, "amb": "amb_wind"},
	"ramparts": {"n": 52, "grav": Vector2(-30, 12), "vel": 10.0, "life": 4.0,
			"col": Color(0.72, 0.74, 0.84), "size": 0.15, "amb": "amb_wind"},
}

var level: Level
var world_w := float(LevelMap.W * TW)
var world_h := float(LevelMap.H * TW)
var floor_top := 0.0                 # y the player spawns standing on

var _lights: Array = []
var _runes: Array = []               # [{node, pos, text}]
var _bonfires: Array = []            # [{pos, key, sprite, light, embers, lit}]
var bonfire_menu                     # BonfireMenu.gd instance
var _soul_orb: Node2D = null
var _pickups: Array = []             # [{node, pos, id, idx}]
var _near_bonfire: Dictionary = {}
var _camera: Camera2D
var _shake := 0.0
var _sparks: CPUParticles2D
var _motes: CPUParticles2D           # the region's airborne dust, ash or embers
var _dust: CPUParticles2D            # kicked up where he lands
var _t := 0.0
var _reveal_t := 0.0
var _area := ""
var hud                     # HUD.gd instance (untyped: it has no class_name)
var pause_menu              # PauseMenu.gd instance
var player: Player


func _ready() -> void:
	_setup_input()
	Audio.boot(get_tree())
	Settings.apply_all()
	level = Level.new()
	add_child(level)
	_build_lighting_root()
	hud = _build_hud()
	pause_menu = _build_pause_menu()
	bonfire_menu = _build_bonfire_menu()
	_spawn_entities()
	_place_at_checkpoint()
	_build_sparks()
	_build_dust()
	_wire_hud()
	_build_camera()
	_build_ambience()
	Audio.music("music_keep")
	_spawn_soul_orb()


# ------------------------------------------------------------------ input ----
func _setup_input() -> void:
	Settings.load_once()
	Keys.apply()


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
				_bonfire(foot, Run.key(tx, ty))
			"torch":
				_torch(Vector2((tx + 0.5) * TW, (ty + 0.5) * TW))
			"mushroom":
				_glow_prop("mushroom.png", 7, 7, foot + Vector2(0, -4),
						Color(0.52, 1.0, 0.60), 0.85, 0.5)
			"brazier":
				_glow_prop("brazier.png", 9, 9, foot + Vector2(0, -5),
						Color(1.0, 0.52, 0.20), 1.5, 0.85)
			"rune":
				_rune(foot, e["text"], Run.key(tx, ty))
			"weapon":
				_weapon_pickup(foot, e["weapon"])
			"deco":
				_deco(tx, ty, e["deco"], int(e["stand"]) == 1)


## A chain, a pillar, a pile of bones. Drawn between the back wall and the
## stone (Level.DECO_Z), tinted with the region's own light, so it reads as
## something standing in the middle distance rather than a sticker on the wall.
##
## Eight regions that differ only in colour still look like one corridor
## repainted; shape in the middle distance is what makes them feel like places.
func _deco(tx: int, ty: int, kind: String, standing: bool) -> void:
	var idx := DECO_FRAMES.find(kind)
	if idx < 0:
		return
	var s := Sprite2D.new()
	s.texture = SpriteUtil.frame_of(_tex("deco.png"), idx, DECO_W, DECO_H)
	s.centered = false
	# hanging props start at the ceiling; standing ones end on the floor
	s.position = Vector2(tx * TW, float(ty * TW) if not standing
			else float((ty + 1) * TW - DECO_H))
	s.z_index = Level.DECO_Z
	s.modulate = level.theme_tint(tx, ty)
	add_child(s)


func _box(parent: Node, pos: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	cs.position = pos
	parent.add_child(cs)


## A bonfire you have not reached yet sits cold and dark. Lighting it is the
## clearest progress marker in the game — you can see it from across a room, and
## it stays lit for the rest of the run.
func _bonfire(foot: Vector2, key: String) -> void:
	var lit: bool = Run.lit_bonfires.has(key)
	var a := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	SpriteUtil.add_anim(sf, "burn", _tex("bonfire.png"), [0, 1, 2, 3], 8.0, true, 24, 24)
	SpriteUtil.add_anim(sf, "cold", _tex("bonfire.png"), [4], 1.0, false, 24, 24)
	a.sprite_frames = sf
	a.centered = true
	a.position = foot + Vector2(0, -12)
	a.play("burn" if lit else "cold")
	add_child(a)

	var em := _embers(foot + Vector2(0, -16))
	em.emitting = lit
	var l := _light(self, foot + Vector2(0, -14), Color(1.0, 0.72, 0.42),
			1.55, 0.95, 0.13)
	l.visible = lit
	_bonfires.append({"pos": foot, "key": key, "sprite": a, "light": l,
			"embers": em, "lit": lit})


func _light_bonfire(b: Dictionary) -> void:
	if b["lit"]:
		return
	b["lit"] = true
	Run.light_bonfire(b["key"])
	var a: AnimatedSprite2D = b["sprite"]
	a.play("burn")
	(b["embers"] as CPUParticles2D).emitting = true
	var l: PointLight2D = b["light"]
	l.visible = true
	l.energy = 5.0                       # a flare, settling back to normal
	create_tween().tween_property(l, "energy", 1.55, 0.9)
	_add_shake(2.0)
	Audio.play("bonfire_light", 0.02)
	hud.show_area("BONFIRE LIT")


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
func _rune(foot: Vector2, text: String, key: String) -> void:
	var s := Sprite2D.new()
	s.texture = SpriteUtil.frame_of(_tex("rune.png"), 0, 7, 7)
	s.position = foot + Vector2(0, -5)
	add_child(s)
	_runes.append({"node": s, "pos": s.position, "text": text, "key": key})


## A weapon lying where its owner dropped it. Not a chest and not a shop: you
## find it by going somewhere you have not been, which is the whole point — it
## is the one kind of progress that changes how the game PLAYS.
func _weapon_pickup(foot: Vector2, id: String) -> void:
	if Run.has_weapon(id):
		return                           # already carried; nothing left to find
	var idx := Weapons.index_of(id)
	if idx < 0:
		return
	var s := Sprite2D.new()
	s.texture = SpriteUtil.frame_of(_tex("weapon_icons.png"), idx, 14, 14)
	var base := foot + Vector2(0, -13)
	s.position = base
	add_child(s)
	_light(s, Vector2.ZERO, Color(0.92, 0.84, 0.56), 0.85, 0.40, 0.0)

	# It hovers: a weapon lying flat on a dark floor is invisible from a screen
	# away. The tween is created FROM the sprite, so taking the weapon (and
	# freeing it) kills the tween with it — a looping tween whose target is gone
	# spins forever and the engine says so.
	var tw := s.create_tween().set_loops()
	tw.tween_property(s, "position:y", base.y - 3.0, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(s, "position:y", base.y, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_pickups.append({"node": s, "pos": base, "id": id, "idx": idx})


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


func _embers(pos: Vector2) -> CPUParticles2D:
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
	return p


## Only the darkness itself — every actual light rides along with the torch or
## bonfire that casts it, placed from the map.
func _build_lighting_root() -> void:
	RenderingServer.set_default_clear_color(Color(0.03, 0.028, 0.045))
	var cm := CanvasModulate.new()
	# a big level needs a higher ambient floor than one flat corridor did,
	# or the stretches between torches read as solid black nothing
	# Raised from 0.30 once the back wall started drawing at BACK_DIM: the two
	# multiply, and at 0.30 everything behind the player fell to near black.
	# The readability now comes from the CONTRAST between wall and stone, so
	# the floor itself can afford to be lit.
	cm.color = Color(0.53, 0.51, 0.60)
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
	s.sprite_frames = _weapon_frames(Run.weapon)
	s.animation = "idle"
	p.add_child(s)

	# a faint personal glow so the hero stays readable away from the fires
	_light(p, Vector2(0, -16), Color(0.72, 0.80, 1.0), 0.42, 0.34, 0.0)
	add_child(p)
	return p


## Idle, run and attack all come off the equipped weapon's own sheets, so the
## knight is visibly holding the axe while standing still — not only mid-swing.
## The roll is a tucked ball with no weapon in it, so every weapon shares it.
func _weapon_frames(idx: int) -> SpriteFrames:
	var id: String = Weapons.def(idx)["id"]
	var sf := SpriteFrames.new()
	SpriteUtil.add_anim(sf, "idle", _tex("hero_idle_%s.png" % id), [0, 1, 2, 3], 6.0, true)
	SpriteUtil.add_anim(sf, "run", _tex("hero_run_%s.png" % id),
			[0, 1, 2, 3, 4, 5], 10.0, true)
	SpriteUtil.add_anim(sf, "attack", _tex("hero_attack_%s.png" % id), [0, 1, 2, 3],
			4.0 / Player.ATTACK_TIME_BASE, false)
	SpriteUtil.add_anim(sf, "roll", _tex("hero_roll.png"), [0, 1, 2, 3],
			4.0 / Player.ROLL_TIME, false)
	SpriteUtil.add_anim(sf, "block", _tex("hero_block.png"), [0, 1], 2.5, true)
	return sf


func _on_weapon_changed(idx: int) -> void:
	var s: AnimatedSprite2D = player.sprite
	var playing := s.animation
	s.sprite_frames = _weapon_frames(idx)
	s.play(playing if s.sprite_frames.has_animation(playing) else "idle")
	hud.set_weapon(idx)


## An arrow or a bolt, put into the WORLD rather than parented to the player —
## it has to keep flying after he has rolled away or died.
func _on_shot(from: Vector2, dir: int, damage: float, widx: int) -> void:
	var w := Weapons.def(widx)
	if not w.has("shot"):
		return
	var spec: Dictionary = w["shot"]
	var pr := Projectile.new()
	pr.dir = dir
	pr.speed = float(spec["speed"])
	pr.drop = float(spec["drop"])
	pr.life = float(spec["life"])
	pr.damage = damage
	pr.knock = float(w["knock"])
	pr.position = from
	var s := Sprite2D.new()
	s.texture = _tex(spec["sprite"])
	s.centered = true
	s.flip_h = dir < 0
	pr.add_child(s)
	pr.struck.connect(_on_hit_landed)
	add_child(pr)
	_add_shake(0.6)


## A blow turned on the shield: sparks, and a much harder jolt if the guard
## actually broke, because that is the moment you need to notice.
func _on_guarded(at: Vector2, broke: bool) -> void:
	_on_hit_landed(at + Vector2(player.facing * 10.0, -14.0))
	if broke:
		_add_shake(3.0)
		hud.show_area("GUARD BROKEN")


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


func _build_bonfire_menu() -> CanvasLayer:
	var b: CanvasLayer = load("res://scripts/BonfireMenu.gd").new()
	add_child(b)
	b.rested.connect(_on_rested)
	b.levelled.connect(_on_levelled)
	b.equipped.connect(_on_equipped)
	b.travelled.connect(_on_travelled)
	return b


## Warp to another lit fire. It also becomes the fire you respawn at, because
## arriving somewhere and then dying back to where you left would be worse than
## not having travelled at all.
func _on_travelled(to: Vector2) -> void:
	player.global_position = to
	player.velocity = Vector2.ZERO
	Run.rest_at(to)
	_respawn_hollows()
	player.rest()
	_area = ""                       # so the new region announces itself
	if _camera != null:
		_camera.reset_smoothing()
	Audio.play("rest", 0.02)
	hud.show_area("TRAVELLED")


## Swapping at the fire goes through the same path as swapping in the field, so
## there is only one place that can forget to rebuild the sprite sheets.
func _on_equipped(idx: int) -> void:
	player.equip(idx)


func _on_levelled() -> void:
	player.apply_stats(true)             # a bought level heals you to the new max
	hud.refresh_stats()
	hud.set_souls(Run.souls)
	player.souls = Run.souls
	_add_shake(1.5)


func _build_pause_menu() -> CanvasLayer:
	var p: CanvasLayer = load("res://scripts/PauseMenu.gd").new()
	add_child(p)
	p.quit_to_menu.connect(_on_quit_to_menu)
	return p


func _on_quit_to_menu() -> void:
	Run.save_game()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _wire_hud() -> void:
	player.health_changed.connect(hud.set_health)
	player.stamina_changed.connect(hud.set_stamina)
	player.souls_changed.connect(hud.set_souls)
	player.souls_changed.connect(func(n: int) -> void: Run.souls = n)
	player.flask_changed.connect(func(c: int, _m: int) -> void: Run.flask = c)
	player.flask_changed.connect(hud.set_flask)
	player.hit_landed.connect(_on_hit_landed)
	player.weapon_changed.connect(_on_weapon_changed)
	player.shot.connect(_on_shot)
	player.guarded.connect(_on_guarded)
	player.landed.connect(_on_landed)
	player.died.connect(_on_player_died)
	hud.set_health(player.health, player.health_max)
	hud.set_stamina(player.stamina, player.stamina_max)
	hud.set_souls(player.souls)
	hud.set_flask(player.flask, Player.FLASK_MAX)
	hud.set_weapon(Run.weapon)


func _on_player_died() -> void:
	Run.deaths += 1
	Run.drop(player.global_position, player.souls)
	Run.save_game()                  # so the pile you dropped is still there
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


## One field of motes, parented to the knight so it is always exactly where the
## camera is looking, and re-dressed whenever he crosses into a new region.
func _build_ambience() -> void:
	var p := CPUParticles2D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	# a screen and a half wide, so motes are already in flight at the edges
	p.emission_rect_extents = Vector2(280, 150)
	p.position = Vector2(0, -20)
	var dot := AtlasTexture.new()
	dot.atlas = _tex("light_soft.png")
	dot.region = Rect2(120, 120, 16, 16)
	p.texture = dot
	p.spread = 40.0
	p.z_index = -2                   # behind the knight, in front of the stone
	player.add_child(p)
	_motes = p
	_set_ambience(level.theme_name_at(player.global_position))


func _set_ambience(theme: String) -> void:
	if _motes == null or not AMBIENCE.has(theme):
		return
	var a: Dictionary = AMBIENCE[theme]
	Audio.ambience(String(a["amb"]))
	_motes.amount = int(a["n"])
	_motes.lifetime = float(a["life"])
	_motes.gravity = a["grav"]
	_motes.direction = (a["grav"] as Vector2).normalized()
	_motes.initial_velocity_min = 0.0
	_motes.initial_velocity_max = float(a["vel"])
	_motes.scale_amount_min = float(a["size"]) * 0.6
	_motes.scale_amount_max = float(a["size"])
	var col: Color = a["col"]
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	# fade in and back out, so nothing ever pops into or out of existence
	g.add_point(0.25, Color(col.r, col.g, col.b, 0.72))
	g.add_point(0.75, Color(col.r, col.g, col.b, 0.72))
	_motes.color_ramp = g
	_motes.restart()


## Grit kicked out sideways where he lands. Tinted with the region's own light
## so the forge throws sparks and the cistern throws spray.
func _build_dust() -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 12
	p.lifetime = 0.42
	p.local_coords = false
	var dot := AtlasTexture.new()
	dot.atlas = _tex("light_soft.png")
	dot.region = Rect2(120, 120, 16, 16)
	p.texture = dot
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(5, 1)
	p.direction = Vector2(1, -0.35)
	p.spread = 62.0
	p.gravity = Vector2(0, 220)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 54.0
	p.scale_amount_min = 0.10
	p.scale_amount_max = 0.20
	add_child(p)
	_dust = p


func _on_landed(at: Vector2, force: float) -> void:
	if _dust == null or force <= 0.0:
		return
	var col := level.light_at(at)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.55 + 0.35 * force))
	g.set_color(1, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.0))
	_dust.color_ramp = g
	_dust.amount = 6 + int(round(10 * force))
	_dust.position = at
	_dust.restart()
	_dust.emitting = true
	_add_shake(1.2 * force)


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
	# Look UP a little. Centred on the knight, a third of every frame was the
	# rock under the floor he is standing on; the room he is walking into is
	# the half worth seeing.
	cam.position = Vector2(0, -16)
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
	Run.play_time += delta
	for e in _lights:
		var n: PointLight2D = e["node"]
		var a: float = e["amp"]
		n.energy = e["base"] * (1.0 + a * sin(_t * 7.0 + e["phase"])
				+ a * 0.5 * sin(_t * 17.0 + e["phase"]))
	_tick_shake(delta)
	if player != null and is_instance_valid(player):
		_track_map(delta)
		_track_area()
		_track_runes()
		# one prompt line, and several things that might want it: the fire wins,
		# then whatever is lying on the floor
		var claimed := _track_bonfire()
		if _track_pickups(claimed):
			claimed = true
		if not claimed:
			hud.show_prompt("")
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
func _track_bonfire() -> bool:
	_near_bonfire = {}
	for b in _bonfires:
		if player.global_position.distance_to(b["pos"]) < BONFIRE_RANGE:
			_near_bonfire = b
			break
	if _near_bonfire.is_empty():
		return false
	hud.show_prompt("E   BONFIRE" if _near_bonfire["lit"] else "E   LIGHT BONFIRE")
	if Input.is_action_just_pressed("interact") and player.state != Player.State.DEAD:
		_light_bonfire(_near_bonfire)
		Run.rest_at(_near_bonfire["pos"])
		hud.show_prompt("")
		bonfire_menu.open()
		return false
	return true


## Picking a weapon up equips it on the spot. Making you walk back to a fire to
## try what you just found would put a menu between you and the only moment this
## game has that feels like a reward.
func _track_pickups(claimed: bool) -> bool:
	var took := false
	for p in _pickups:
		var node: Sprite2D = p["node"]
		if not is_instance_valid(node):
			continue
		if player.global_position.distance_to(p["pos"]) > PICKUP_RANGE:
			continue
		if not claimed and not took:
			hud.show_prompt("E   TAKE  %s" % Weapons.name_of(p["idx"]))
			took = true
		if Input.is_action_just_pressed("interact") \
				and player.state != Player.State.DEAD:
			_take_weapon(p)
			return false
	return took


func _take_weapon(p: Dictionary) -> void:
	Run.find_weapon(p["id"])
	player.equip(p["idx"])
	(p["node"] as Sprite2D).queue_free()
	_pickups.erase(p)
	hud.show_prompt("")
	Audio.play("weapon_found", 0.0)
	hud.show_area("FOUND  %s" % Weapons.name_of(p["idx"]))
	_add_shake(1.5)


func _on_rested() -> void:
	Audio.play("rest", 0.02)
	Run.save_game()                  # a fire is the only place a save belongs
	player.rest()
	_respawn_hollows()
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
	Audio.play("soul", 0.05)
	player.add_souls(Run.collect())
	_soul_orb.queue_free()
	_soul_orb = null


## Fill the map in behind him. Every fifth of a second is plenty: he covers at
## most 20px in that time and the reveal radius is 208.
func _track_map(delta: float) -> void:
	_reveal_t -= delta
	if _reveal_t > 0.0:
		return
	_reveal_t = REVEAL_EVERY
	var t := level.to_tile(player.global_position + Vector2(0, -8))
	Run.see_tiles(t.x, t.y, REVEAL_RADIUS)


## The map is far too big to hold in your head, so crossing into a new region
## announces itself the way a souls game does.
func _track_area() -> void:
	var here := level.area_at(player.global_position + Vector2(0, -12))
	if here != "" and here != _area:
		_area = here
		Run.see_area(here)
		hud.show_area(here)
		_set_ambience(level.theme_name_at(player.global_position))


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
		var close := d < RUNE_READ_RANGE
		if close and Run.read_rune(r["key"]):
			Audio.play("rune", 0.02)
		s.texture = SpriteUtil.frame_of(_tex("rune.png"), 1 if close else 0, 7, 7)
	hud.show_inscription(nearest)
