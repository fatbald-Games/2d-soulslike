class_name MenuList
extends Control
## A vertical list of entries with a skull for a cursor. Shared by the title
## screen and the pause screen so selection behaves identically in both.

signal activated(index: int)
signal selection_changed(index: int)

const SKULL_W := 11
const SKULL_H := 9

var index := 0
var wrap := true

var _labels: Array[PixelLabel] = []
var _cursor: TextureRect
var _t := 0.0
var _center_x := 0.0


func build(items: Array, center_x: float, y0: float,
		scale_px: int = 2, step: int = UiTheme.MENU_STEP) -> void:
	for c in get_children():
		c.queue_free()
	_labels.clear()
	_center_x = center_x

	for i in items.size():
		var l := PixelLabel.make(items[i], scale_px, UiTheme.BONE_DIM)
		l.center_on(center_x, y0 + i * step)
		add_child(l)
		_labels.append(l)

	_cursor = TextureRect.new()
	_cursor.texture = UiTheme.frame_tex("skull.png", 1, SKULL_W, SKULL_H)
	_cursor.size = Vector2(SKULL_W, SKULL_H)
	add_child(_cursor)

	index = clampi(index, 0, maxi(0, _labels.size() - 1))
	_apply()


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


func activate() -> void:
	if not _labels.is_empty():
		activated.emit(index)


func _apply() -> void:
	for i in _labels.size():
		_labels[i].tint = UiTheme.BONE_BRIGHT if i == index else UiTheme.BONE_DIM
	if _cursor != null and index < _labels.size():
		var l := _labels[index]
		_cursor.position = Vector2(l.position.x - SKULL_W - 6,
				l.position.y + roundf((l.size.y - SKULL_H) * 0.5))


func _process(delta: float) -> void:
	# the cursor's sockets breathe, so the skull reads as watching you
	_t += delta
	if _cursor != null:
		var pulse: float = 0.72 + 0.28 * (0.5 + 0.5 * sin(_t * 4.2))
		_cursor.modulate = Color(1, 1, 1, pulse)
