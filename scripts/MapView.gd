class_name MapView
extends TextureRect
## The keep, one pixel per tile.
##
## 384x128 tiles is exactly the width of the viewport, so the whole map fits on
## screen at 1:1 with nothing scaled, rotated or scrolled — which is the only
## reason a map this cheap is also readable.
##
## It is rebuilt into a raw byte buffer rather than drawn: 49152 draw_rect calls
## would cost more than the pause it appears during. Only rebuilt when the page
## is opened, so walking around never pays for it.

const UNSEEN := [14, 13, 18, 255]        # fog: near black, but not the void
const WATER := [46, 104, 124, 255]
const CLIMB := [150, 122, 74, 255]       # ladders and beams: how you get around

## Markers, drawn over the terrain afterwards.
const LIT := Color(1.0, 0.62, 0.26)
const COLD := Color(0.42, 0.40, 0.44)
const FIND := Color(0.92, 0.84, 0.52)
const HERE := Color(1.0, 1.0, 1.0)


func _init() -> void:
	# the map is authored at exactly one pixel per tile; anything but nearest
	# would smear the whole thing
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(LevelMap.W, LevelMap.H)
	size = custom_minimum_size


## `player_tile` may be (-1,-1) to leave the marker off.
func refresh(player_tile: Vector2i) -> void:
	var img := _terrain()
	_markers(img, player_tile)
	texture = ImageTexture.create_from_image(img)


## One colour per region, taken from the torch colour that region burns in, so
## the map is coloured the same way the rooms are.
func _palette() -> Array:
	var out: Array = []
	for a in LevelMap.AREAS:
		var rgb: Array = a["light"]
		var solid := [int(rgb[0] * 128.0) + 18, int(rgb[1] * 128.0) + 18,
				int(rgb[2] * 128.0) + 22, 255]
		var open := [int(solid[0] * 0.34), int(solid[1] * 0.34),
				int(solid[2] * 0.34), 255]
		out.append([solid, open])
	return out


func _terrain() -> Image:
	Run.map_ready()
	var w := LevelMap.W
	var h := LevelMap.H
	var pal := _palette()
	var buf := PackedByteArray()
	buf.resize(w * h * 4)
	for ty in h:
		var row: String = LevelMap.MAP[ty]
		var themes: String = LevelMap.THEME_OF[ty]
		var base := ty * w
		for tx in w:
			var i := (base + tx) * 4
			var col: Array = UNSEEN
			if Run.explored[base + tx] != 0:
				var ch := row[tx]
				var p: Array = pal[themes.unicode_at(tx) - 48]
				if ch == "#" or ch == "X":
					col = p[0]
				elif ch == "w":
					col = WATER
				elif ch == "H" or ch == "=":
					col = CLIMB
				else:
					col = p[1]
			buf[i] = col[0]
			buf[i + 1] = col[1]
			buf[i + 2] = col[2]
			buf[i + 3] = col[3]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf)


## Everything worth walking to: fires you have lit, fires you have only found,
## and weapons still lying where their owner dropped them.
func _markers(img: Image, player_tile: Vector2i) -> void:
	for e in LevelMap.ENTITIES:
		var tx: int = e["x"]
		var ty: int = e["y"]
		if not Run.is_explored(tx, ty):
			continue
		match e["kind"]:
			"bonfire":
				_blot(img, tx, ty, LIT if Run.lit_bonfires.has(Run.key(tx, ty))
						else COLD, 1)
			"weapon":
				if not Run.has_weapon(e["weapon"]):
					_blot(img, tx, ty, FIND, 0)
	if player_tile.x >= 0:
		_blot(img, player_tile.x, player_tile.y, HERE, 1)


func _blot(img: Image, tx: int, ty: int, col: Color, halo: int) -> void:
	for dy in range(-halo, halo + 1):
		for dx in range(-halo, halo + 1):
			var x := tx + dx
			var y := ty + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			# the halo is the marker at half strength, so a 3x3 blot still
			# reads as a point rather than a square
			img.set_pixel(x, y, col if dx == 0 and dy == 0
					else Color(col.r * 0.45, col.g * 0.45, col.b * 0.45))
