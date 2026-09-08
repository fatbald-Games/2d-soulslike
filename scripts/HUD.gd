extends CanvasLayer
## Souls-style HUD in bone and iron: health over stamina in carved bone troughs,
## a skull counting the souls, and YOU DIED.
##
## The bars are frame textures with a dark channel; the fill is drawn inside
## that channel (see UiTheme.channel_size). Health also carries a "ghost" bar —
## a paler smear that lags behind the real value for a beat after a hit, so you
## can see how much that mistake actually cost.

const GHOST_DELAY := 0.35        # how long the ghost hangs before it drains
const GHOST_SPEED := 0.55        # fraction of the bar it sheds per second
const HINT_HOLD := 7.0           # seconds the control hint stays up

## Each point of VIGOR / ENDURANCE makes its bar this much wider. The bar
## GROWING is the point — a number going up in a menu is bookkeeping, a bar that
## visibly reaches further across the screen is progress you feel.
const W_PER_POINT := 4.0
const TICK_GAP := 9.0
const MAX_TICKS := 24

var _hp_fill: ColorRect
var _hp_edge: ColorRect
var _hp_ghost: ColorRect
var _st_fill: ColorRect
var _st_edge: ColorRect
var _hp_frame: NinePatchRect    # kept so tests can assert the draw order
var _sp_frame: NinePatchRect
var _hp_ticks: Array[ColorRect] = []
var _sp_ticks: Array[ColorRect] = []
var _level: PixelLabel
var _weapon: PixelLabel
var _weapon_icon: TextureRect
var _souls: PixelLabel
var _fade: ColorRect
var _died: PixelLabel
var _area: PixelLabel
var _inscription: PixelLabel
var _area_tween: Tween
var _hint: PixelLabel
var _flask_row: Control
var _prompt: PixelLabel
var _shown_prompt := ""
var _shown_text := ""

var _hp_ratio := 1.0
var _ghost_ratio := 1.0
var _ghost_hold := 0.0
var _hp_channel: Vector2
var _sp_channel: Vector2


func _ready() -> void:
	Settings.load_once()
	# darkens the screen edges; added first so all HUD art draws on top of it
	var vig := TextureRect.new()
	vig.texture = UiTheme.tex("vignette.png")
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)

	var hp_pos := Vector2(8, 8)
	var sp_pos := Vector2(8, 8 + UiTheme.HP_FRAME.y + 2)
	_hp_channel = UiTheme.channel_size(UiTheme.HP_FRAME, UiTheme.HP_CAP)
	_sp_channel = UiTheme.channel_size(UiTheme.SP_FRAME, UiTheme.SP_CAP)

	# Draw order matters: the plate is OPAQUE, so anything added after it is
	# hidden underneath. Frame, then ghost, then fill, then the lit top edge,
	# then the scoring ticks LAST — they sit on top of the fill and read as
	# scored segments instead of one solid smear.
	#
	# The frames are NinePatchRects rather than plain textures so the plate can
	# stretch while the fang caps stay crisp: that is what lets the bar get
	# longer when VIGOR is bought.
	_hp_frame = _patch(hp_pos, "bar_frame_hp.png", UiTheme.HP_CAP)
	var hp_origin := hp_pos + Vector2(UiTheme.HP_CAP, UiTheme.CHANNEL_INSET_Y)
	_hp_ghost = _rect(hp_origin, _hp_channel, UiTheme.BLOOD_GHOST)
	_hp_fill = _rect(hp_origin, _hp_channel, UiTheme.BLOOD)
	_hp_edge = _rect(hp_origin, Vector2(_hp_channel.x, 2), UiTheme.BLOOD_HI)
	_hp_ticks = _tick_pool(hp_origin, _hp_channel.y)

	# --- stamina ---
	_sp_frame = _patch(sp_pos, "bar_frame_sp.png", UiTheme.SP_CAP)
	var sp_origin := sp_pos + Vector2(UiTheme.SP_CAP, UiTheme.CHANNEL_INSET_Y)
	_st_fill = _rect(sp_origin, _sp_channel, UiTheme.STAMINA)
	_st_edge = _rect(sp_origin, Vector2(_sp_channel.x, 2), UiTheme.STAMINA_HI)
	_sp_ticks = _tick_pool(sp_origin, _sp_channel.y)
	refresh_stats()

	# --- flask charges, as pips under the bars ---
	_flask_row = Control.new()
	_flask_row.position = Vector2(8, sp_pos.y + UiTheme.SP_FRAME.y + 3)
	add_child(_flask_row)

	# --- souls, counted beside a skull ---
	var skull := TextureRect.new()
	skull.texture = UiTheme.frame_tex("skull.png", 0, MenuList.SKULL_W, MenuList.SKULL_H)
	skull.position = Vector2(8, sp_pos.y + UiTheme.SP_FRAME.y + 14)
	add_child(skull)

	_souls = PixelLabel.make("", 1, Color(0.816, 0.769, 0.588))
	_souls.position = Vector2(22, sp_pos.y + UiTheme.SP_FRAME.y + 15)
	add_child(_souls)
	set_souls(0)

	_level = PixelLabel.make("LV 1", 1, UiTheme.BONE)
	_level.position = Vector2(8, sp_pos.y + UiTheme.SP_FRAME.y + 24)
	add_child(_level)

	# --- what is in his hands, named and pictured. Six weapons that play
	# nothing like each other are worth nothing if you cannot tell at a glance
	# which one you swapped to. ---
	_weapon_icon = TextureRect.new()
	_weapon_icon.position = Vector2(6, sp_pos.y + UiTheme.SP_FRAME.y + 32)
	add_child(_weapon_icon)

	_weapon = PixelLabel.make("", 1, UiTheme.BONE_DIM)
	_weapon.position = Vector2(21, sp_pos.y + UiTheme.SP_FRAME.y + 37)
	add_child(_weapon)

	# The hint used to sit there forever and just added noise. Now it introduces
	# the controls and fades out; OPTIONS can switch it off entirely.
	if Settings.hud_hints:
		_hint = PixelLabel.make(
				"A D MOVE   SPACE JUMP   J ATTACK   K ROLL   TAB SWAP   L GUARD",
				1, Color(0.353, 0.322, 0.290, 0.60))
		_hint.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 13)
		add_child(_hint)
		var fade := create_tween()
		fade.tween_interval(HINT_HOLD)
		fade.tween_property(_hint, "modulate:a", 0.0, 1.4)

	# --- death overlay, hidden until it is needed ---
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = UiTheme.VIEW
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_died = PixelLabel.make("YOU DIED", 5, Color(0.66, 0.09, 0.08))
	_died.center_on(UiTheme.VIEW.x * 0.5, 92)
	_died.modulate = Color(1, 1, 1, 0)     # faded in by show_died()
	add_child(_died)

	# --- region name, announced on crossing into a new part of the keep ---
	_area = PixelLabel.make("", 2, UiTheme.BONE_BRIGHT)
	_area.shadow_tint = Color(0, 0, 0, 0.85)
	_area.modulate = Color(1, 1, 1, 0)
	add_child(_area)

	# --- "E REST" and the like, shown when something is in reach ---
	_prompt = PixelLabel.make("", 1, UiTheme.EMBER)
	_prompt.shadow_tint = Color(0, 0, 0, 0.9)
	_prompt.modulate = Color(1, 1, 1, 0)
	add_child(_prompt)

	# --- the line on whichever inscribed stone he is standing on ---
	_inscription = PixelLabel.make("", 1, Color(0.78, 0.72, 0.60))
	_inscription.shadow_tint = Color(0, 0, 0, 0.9)
	_inscription.modulate = Color(1, 1, 1, 0)
	add_child(_inscription)


## A bar frame that can be stretched. Only the middle plate moves; the fang
## caps sit inside the fixed patch margins and stay pixel-exact at any width.
func _patch(pos: Vector2, tex_name: String, cap: int) -> NinePatchRect:
	var f := NinePatchRect.new()
	f.texture = UiTheme.tex(tex_name)
	f.patch_margin_left = cap
	f.patch_margin_right = cap
	f.position = pos
	add_child(f)
	return f


## Scoring ticks are drawn as a fixed pool and simply hidden past the current
## bar width, so a growing bar gains segments without rebuilding anything.
func _tick_pool(origin: Vector2, height: float) -> Array[ColorRect]:
	var pool: Array[ColorRect] = []
	for i in MAX_TICKS:
		var t := ColorRect.new()
		t.color = Color(0.035, 0.031, 0.047, 0.51)
		t.position = origin
		t.size = Vector2(1, height)
		t.visible = false
		add_child(t)
		pool.append(t)
	return pool


## Re-reads the stats and stretches both bars to match. Called on spawn and the
## instant a level is bought at a bonfire.
func refresh_stats() -> void:
	_hp_channel.x = UiTheme.HP_FRAME.x - UiTheme.HP_CAP * 2 + Run.stats[0] * W_PER_POINT
	_sp_channel.x = UiTheme.SP_FRAME.x - UiTheme.SP_CAP * 2 + Run.stats[1] * W_PER_POINT
	_hp_frame.size = Vector2(_hp_channel.x + UiTheme.HP_CAP * 2, UiTheme.HP_FRAME.y)
	_sp_frame.size = Vector2(_sp_channel.x + UiTheme.SP_CAP * 2, UiTheme.SP_FRAME.y)
	_lay_ticks(_hp_ticks, _hp_fill.position, _hp_channel.x)
	_lay_ticks(_sp_ticks, _st_fill.position, _sp_channel.x)
	if _level != null:
		_level.text = "LV %d" % Run.level()


func _lay_ticks(pool: Array[ColorRect], origin: Vector2, width: float) -> void:
	var x := TICK_GAP
	for t in pool:
		t.visible = x < width - 1.0
		if t.visible:
			t.position.x = origin.x + x
		x += TICK_GAP


func _rect(pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = size
	add_child(r)
	return r


func set_health(cur: float, maxv: float) -> void:
	_hp_ratio = clampf(cur / maxv, 0.0, 1.0)
	_hp_fill.size.x = _hp_channel.x * _hp_ratio
	_hp_edge.size.x = _hp_fill.size.x
	if _hp_ratio > _ghost_ratio:
		_ghost_ratio = _hp_ratio          # healed: the ghost catches up at once
	else:
		_ghost_hold = GHOST_DELAY
	_hp_ghost.size.x = _hp_channel.x * _ghost_ratio


func set_stamina(cur: float, maxv: float) -> void:
	var r := clampf(cur / maxv, 0.0, 1.0)
	_st_fill.size.x = _sp_channel.x * r
	_st_edge.size.x = _st_fill.size.x


func set_souls(n: int) -> void:
	_souls.text = "%d" % n


## One pip per charge: filled while you still have it, drained once spent.
func set_flask(cur: int, maxv: int) -> void:
	for c in _flask_row.get_children():
		c.queue_free()
	for i in maxv:
		var pip := TextureRect.new()
		pip.texture = UiTheme.frame_tex("flask.png", 0 if i < cur else 1, 5, 7)
		pip.position = Vector2(i * 7, 0)
		pip.modulate = Color(1, 1, 1, 1.0 if i < cur else 0.45)
		_flask_row.add_child(pip)


## The equipped weapon. Flashes bright and settles back to a quiet label, so a
## swap is unmissable in the moment and then stops shouting.
func set_weapon(idx: int) -> void:
	_weapon.text = Weapons.name_of(idx)
	_weapon_icon.texture = UiTheme.frame_tex_from(
			"res://assets/sprites/weapon_icons.png", idx, 14, 14)
	_weapon.tint = UiTheme.BONE_BRIGHT
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(_weapon, "tint", UiTheme.BONE_DIM, 0.6)


## An action offered by whatever is in reach. Called every frame, so it only
## touches the label when the text actually changes.
func show_prompt(text: String) -> void:
	if text == _shown_prompt:
		return
	_shown_prompt = text
	if text.is_empty():
		_prompt.modulate = Color(1, 1, 1, 0)
		return
	_prompt.text = text
	_prompt.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 44)
	_prompt.modulate = Color(1, 1, 1, 1)


## Fade a region name in over the middle of the screen, hold, fade out.
func show_area(name: String) -> void:
	_area.text = name
	# The one band that is clear of everything: below the left-hand HUD column
	# (which ends at 73), above the knight's head (the camera looks up, so he
	# tops out around 93), and clear of every menu heading at 28-49.
	_area.center_on(UiTheme.VIEW.x * 0.5, 78)
	if _area_tween != null and _area_tween.is_valid():
		_area_tween.kill()
	_area.modulate = Color(1, 1, 1, 0)
	_area_tween = create_tween()
	_area_tween.tween_property(_area, "modulate:a", 1.0, 0.7)
	_area_tween.tween_interval(1.7)
	_area_tween.tween_property(_area, "modulate:a", 0.0, 0.9)


## Show (or clear) the line carved into the stone underfoot. Called every frame,
## so it only touches the label when the text actually changes.
func show_inscription(text: String) -> void:
	if text == _shown_text:
		return
	_shown_text = text
	if text.is_empty():
		_inscription.modulate = Color(1, 1, 1, 0)
		return
	_inscription.text = text
	_inscription.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 30)
	_inscription.modulate = Color(1, 1, 1, 1)


func show_died() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_fade, "color:a", 0.72, 1.2)
	tw.tween_property(_died, "modulate:a", 1.0, 1.4)


func _process(delta: float) -> void:
	if _ghost_ratio <= _hp_ratio:
		return
	if _ghost_hold > 0.0:
		_ghost_hold -= delta
		return
	_ghost_ratio = maxf(_hp_ratio, _ghost_ratio - GHOST_SPEED * delta)
	_hp_ghost.size.x = _hp_channel.x * _ghost_ratio
