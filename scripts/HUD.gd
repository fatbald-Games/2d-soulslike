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

var _hp_fill: ColorRect
var _hp_edge: ColorRect
var _hp_ghost: ColorRect
var _st_fill: ColorRect
var _st_edge: ColorRect
var _hp_frame: TextureRect      # kept so tests can assert the draw order
var _sp_frame: TextureRect
var _souls: PixelLabel
var _fade: ColorRect
var _died: PixelLabel
var _area: PixelLabel
var _inscription: PixelLabel
var _area_tween: Tween
var _hint: PixelLabel
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
	# then the scoring overlay LAST — its ticks sit on top of the fill and
	# read as scored segments instead of one solid smear.
	_hp_frame = _frame(hp_pos, "bar_frame_hp.png")
	var hp_origin := hp_pos + Vector2(UiTheme.HP_CAP, UiTheme.CHANNEL_INSET_Y)
	_hp_ghost = _rect(hp_origin, _hp_channel, UiTheme.BLOOD_GHOST)
	_hp_fill = _rect(hp_origin, _hp_channel, UiTheme.BLOOD)
	_hp_edge = _rect(hp_origin, Vector2(_hp_channel.x, 2), UiTheme.BLOOD_HI)
	_frame(hp_pos, "bar_overlay_hp.png")

	# --- stamina ---
	_sp_frame = _frame(sp_pos, "bar_frame_sp.png")
	var sp_origin := sp_pos + Vector2(UiTheme.SP_CAP, UiTheme.CHANNEL_INSET_Y)
	_st_fill = _rect(sp_origin, _sp_channel, UiTheme.STAMINA)
	_st_edge = _rect(sp_origin, Vector2(_sp_channel.x, 2), UiTheme.STAMINA_HI)
	_frame(sp_pos, "bar_overlay_sp.png")

	# --- souls, counted beside a skull ---
	var skull := TextureRect.new()
	skull.texture = UiTheme.frame_tex("skull.png", 0, MenuList.SKULL_W, MenuList.SKULL_H)
	skull.position = Vector2(8, sp_pos.y + UiTheme.SP_FRAME.y + 4)
	add_child(skull)

	_souls = PixelLabel.make("", 1, Color(0.816, 0.769, 0.588))
	_souls.position = Vector2(22, sp_pos.y + UiTheme.SP_FRAME.y + 5)
	add_child(_souls)
	set_souls(0)

	# The hint used to sit there forever and just added noise. Now it introduces
	# the controls and fades out; OPTIONS can switch it off entirely.
	if Settings.hud_hints:
		_hint = PixelLabel.make("A D MOVE   SPACE JUMP   W S CLIMB   J ATTACK   K ROLL",
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

	# --- the line on whichever inscribed stone he is standing on ---
	_inscription = PixelLabel.make("", 1, Color(0.78, 0.72, 0.60))
	_inscription.shadow_tint = Color(0, 0, 0, 0.9)
	_inscription.modulate = Color(1, 1, 1, 0)
	add_child(_inscription)


func _frame(pos: Vector2, tex_name: String) -> TextureRect:
	var f := TextureRect.new()
	f.texture = UiTheme.tex(tex_name)
	f.position = pos
	add_child(f)
	return f


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


## Fade a region name in over the middle of the screen, hold, fade out.
func show_area(name: String) -> void:
	_area.text = name
	_area.center_on(UiTheme.VIEW.x * 0.5, 58)
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
