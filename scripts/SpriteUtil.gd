class_name SpriteUtil
extends RefCounted
## Slices horizontal sprite sheets into named animations.
## Every character sheet uses 44x32 frames with the anchor on the feet
## (frame pixel 22,31), so all of them are drawn with offset (-22,-31).
## The canvas is symmetric about that anchor, so flip_h mirrors in place.

const FRAME_W := 44
const FRAME_H := 32
const ANCHOR := Vector2(-22, -31)


static func add_anim(sf: SpriteFrames, anim: String, tex: Texture2D,
		indices: Array, fps: float, loop: bool,
		fw: int = FRAME_W, fh: int = FRAME_H) -> void:
	if not sf.has_animation(anim):
		sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for i in indices:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(int(i) * fw, 0, fw, fh)
		sf.add_frame(anim, at)


static func make_sprite() -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.centered = false
	s.offset = ANCHOR          # symmetric canvas -> flip_h mirrors in place
	return s
