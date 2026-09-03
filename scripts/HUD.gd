extends CanvasLayer
## Souls-style HUD: health over stamina, a soul counter, and YOU DIED.

const VIEW := Vector2(384, 216)
const BAR_W := 92.0

var _hp_fill: ColorRect
var _st_fill: ColorRect
var _souls: Label
var _fade: ColorRect
var _died: Label


func _ready() -> void:
	_hp_fill = _bar(Vector2(8, 8), Vector2(BAR_W, 6), Color(0.62, 0.11, 0.12))
	_st_fill = _bar(Vector2(8, 18), Vector2(BAR_W, 5), Color(0.49, 0.58, 0.32))

	_souls = Label.new()
	_souls.add_theme_font_size_override("font_size", 8)
	_souls.modulate = Color(0.85, 0.78, 0.58, 0.85)
	_souls.position = Vector2(8, 27)
	add_child(_souls)
	set_souls(0)

	var hint := Label.new()
	hint.text = "A/D  move    SPACE  jump    J  attack    K / SHIFT  roll"
	hint.add_theme_font_size_override("font_size", 7)
	hint.modulate = Color(0.65, 0.6, 0.52, 0.4)
	hint.position = Vector2(8, VIEW.y - 16)
	add_child(hint)

	# death overlay, hidden until it is needed
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = VIEW
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_died = Label.new()
	_died.text = "YOU DIED"
	_died.add_theme_font_size_override("font_size", 26)
	_died.modulate = Color(0.66, 0.09, 0.08, 0.0)
	_died.size = Vector2(VIEW.x, 30)
	_died.position = Vector2(0, 88)
	_died.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_died)


func _bar(pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.065, 0.85)
	bg.position = pos - Vector2(1, 1)
	bg.size = size + Vector2(2, 2)
	add_child(bg)
	var fill := ColorRect.new()
	fill.color = col
	fill.position = pos
	fill.size = size
	add_child(fill)
	return fill


func set_health(cur: float, maxv: float) -> void:
	_hp_fill.size.x = BAR_W * clampf(cur / maxv, 0.0, 1.0)


func set_stamina(cur: float, maxv: float) -> void:
	_st_fill.size.x = BAR_W * clampf(cur / maxv, 0.0, 1.0)


func set_souls(n: int) -> void:
	_souls.text = "SOULS  %d" % n


func show_died() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_fade, "color:a", 0.72, 1.2)
	tw.tween_property(_died, "modulate:a", 1.0, 1.4)
