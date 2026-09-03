class_name PixelLabel
extends Control
## Draws text with the generated bone font (assets/ui/font_5x7.png).
##
## Godot's default font would wreck the look at 384x216 — it is anti-aliased and
## vector-shaped, next to art that is authored pixel by pixel. This blits glyphs
## straight out of the sheet instead, so every letter lands on the pixel grid.
##
## The sheet is pure white, so one texture serves every colour the UI needs:
## ivory labels, ember-red "YOU DIED", sickly green stamina.

## Must stay in sync with FONT_CHARS in tools/gen_art.py — a glyph is found
## purely by its index in this string.
const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:!?'-()/ "
const CELL := 6          # glyph cell pitch in the sheet
const GLYPH_W := 5
const GLYPH_H := 7
const FONT_PATH := "res://assets/ui/font_5x7.png"

static var _font: Texture2D

var text: String = "":
	set(v):
		text = v
		_refit()
var px_scale: int = 1:
	set(v):
		px_scale = maxi(1, v)
		_refit()
var tracking: int = 1:
	set(v):
		tracking = v
		_refit()
var tint: Color = Color(0.87, 0.84, 0.76):
	set(v):
		tint = v
		queue_redraw()
var shadow_tint: Color = Color(0, 0, 0, 0):
	set(v):
		shadow_tint = v
		queue_redraw()
var shadow_offset: Vector2 = Vector2(1, 1):
	set(v):
		shadow_offset = v
		queue_redraw()


static func font() -> Texture2D:
	if _font == null:
		_font = load(FONT_PATH) as Texture2D
	return _font


## Pixel size of a string without building a node for it.
static func measure(t: String, scale_px: int = 1, track: int = 1) -> Vector2:
	var n := t.length()
	if n == 0:
		return Vector2.ZERO
	return Vector2(n * (GLYPH_W + track) * scale_px - track * scale_px,
			GLYPH_H * scale_px)


static func make(t: String, scale_px: int = 1,
		col: Color = Color(0.87, 0.84, 0.76)) -> PixelLabel:
	var l := PixelLabel.new()
	l.px_scale = scale_px
	l.tint = col
	l.text = t
	return l


## Place the label so it is horizontally centred on `cx`.
func center_on(cx: float, y: float) -> void:
	position = Vector2(roundf(cx - size.x * 0.5), y)


func _refit() -> void:
	size = measure(text, px_scale, tracking)
	custom_minimum_size = size
	queue_redraw()


func _draw() -> void:
	var tex := font()
	if tex == null:
		return
	if shadow_tint.a > 0.0:
		_blit(tex, shadow_offset, shadow_tint)
	_blit(tex, Vector2.ZERO, tint)


func _blit(tex: Texture2D, off: Vector2, col: Color) -> void:
	var x := 0.0
	var step := float((GLYPH_W + tracking) * px_scale)
	for i in text.length():
		var idx := CHARS.find(text[i].to_upper())
		if idx < 0:
			idx = CHARS.find(" ")
		draw_texture_rect_region(tex,
				Rect2(off.x + x, off.y, GLYPH_W * px_scale, GLYPH_H * px_scale),
				Rect2(idx * CELL, 0, GLYPH_W, GLYPH_H),
				col)
		x += step
