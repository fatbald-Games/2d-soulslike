class_name MenuList
extends Control
## A list of entries inside a panel, with a skull for a cursor and a lit bar
## behind the current row. Shared by the title screen, the pause screen and the
## options screen, so selection behaves identically everywhere.
##
## Entries are LEFT-aligned in a fixed gutter rather than centred: centred text
## makes every row start at a different x, which is what made the old menu read
## as loose text on top of art instead of as a menu.

signal activated(index: int)
signal value_changed(index: int, dir: int)
signal selection_changed(index: int)

const SKULL_W := 11
const SKULL_H := 9

var index := 0
var wrap := true

var _labels: Array[PixelLabel] = []
var _values: Array[PixelLabel] = []
var _cursor: TextureRect
var _bar: ColorRect
var _t := 0.0
var _origin := Vector2.ZERO
var _panel_w := 0.0
var _step := UiTheme.MENU_STEP
var _scale := 2


## `origin` is the panel's top-left corner; rows are laid out relative to it.
func build(items: Array, origin: Vector2, panel_w: float,
		scale_px: int = 2, step: int = UiTheme.MENU_STEP,
		values: Array = []) -> void:
	for c in get_children():
		c.queue_free()
	_labels.clear()
	_values.clear()
	_origin = origin
	_panel_w = panel_w
	_step = step
	_scale = scale_px

	var row_h := PixelLabel.GLYPH_H * scale_px
	# the bar goes in first so every label draws on top of it
	_bar = ColorRect.new()
	_bar.color = Color(0.62, 0.58, 0.52, 0.16)
	_bar.size = Vector2(panel_w - 10, row_h + 6)
	add_child(_bar)

	for i in items.size():
		var l := PixelLabel.make(items[i], scale_px, UiTheme.BONE_DIM)
		l.position = origin + Vector2(UiTheme.CURSOR_GUTTER,
				UiTheme.MENU_Y0 - UiTheme.PANEL_Y + i * step)
		add_child(l)
		_labels.append(l)

		if i < values.size():
			var v := PixelLabel.make(str(values[i]), scale_px, UiTheme.EMBER)
			v.position = Vector2(
					origin.x + panel_w - UiTheme.PANEL_PAD_X - v.size.x,
					l.position.y)
			add_child(v)
			_values.append(v)

	_cursor = TextureRect.new()
	_cursor.texture = UiTheme.frame_tex("skull.png", 1, SKULL_W, SKULL_H)
	_cursor.size = Vector2(SKULL_W, SKULL_H)
	add_child(_cursor)

	index = clampi(index, 0, maxi(0, _labels.size() - 1))
	_apply()


func set_value(i: int, text: String) -> void:
	if i >= _values.size():
		return
	var v := _values[i]
	v.text = text
	v.position.x = _origin.x + _panel_w - UiTheme.PANEL_PAD_X - v.size.x


func move(delta: int) -> void:
	if _labels.is_empty():
		return
	var n := _labels.size()
	if wrap:
		index = (index + delta + n) % n
	else:
		index = clampi(index + delta, 0, n - 1)
	_apply()
	selection_changed.emit(index)


func nudge(dir: int) -> void:
	if not _labels.is_empty():
		value_changed.emit(index, dir)


func activate() -> void:
	if not _labels.is_empty():
		activated.emit(index)


func _apply() -> void:
	for i in _labels.size():
		_labels[i].tint = UiTheme.BONE_BRIGHT if i == index else UiTheme.BONE_DIM
	for i in _values.size():
		_values[i].tint = UiTheme.EMBER if i == index else UiTheme.BONE_DIM
	if index >= _labels.size():
		return
	var row := _labels[index]
	if _bar != null:
		_bar.position = Vector2(_origin.x + 5, row.position.y - 3)
	if _cursor != null:
		_cursor.position = Vector2(_origin.x + 12,
				row.position.y + roundf((row.size.y - SKULL_H) * 0.5))


func _process(delta: float) -> void:
	# the cursor's sockets breathe, so the skull reads as watching you
	_t += delta
	if _cursor != null:
		var pulse: float = 0.72 + 0.28 * (0.5 + 0.5 * sin(_t * 4.2))
		_cursor.modulate = Color(1, 1, 1, pulse)
