class_name Level
extends Node2D
## The dungeon itself: terrain drawing, collision and tile queries.
##
## The map comes from LevelMap.gd, which tools/gen_level.py generates and — more
## importantly — proves reachable before it writes. Actors are NOT spawned here;
## Main does that from LevelMap.ENTITIES, so terrain and cast stay separable.
##
## Three things keep 49152 tiles cheap:
##   * drawing happens in one _draw() on a single canvas item rather than one
##     Sprite2D per tile.
##   * rock with no opening near it is marked BURIED by the generator and never
##     drawn. Working that out per tile in GDScript would be a load-time stall,
##     and it never changes, so it is decided once in Python.
##   * collision is a few dozen merged rectangles, not a body per tile.

const TILE := LevelMap.TILE
const SOLID := "#"
const BURIED := "X"      # solid, but no opening within reach — never drawn
const AIR := "."
const BEAM := "="
const LADDER := "H"
const WATER := "w"

const WORLD_LAYER := 1
const BEAM_LAYER := 2

## Must match TILE_VARIANTS in tools/gen_art.py: each stone sheet is this many
## 16px tiles side by side, and a positional hash picks one per tile.
const VARIANTS := 4

## How dark the wall BEHIND the player is drawn relative to the ground he
## stands on. This one number does more for readability than any texture:
## before it, solid rock and empty air were the same brightness and the whole
## screen read as one field of noise.
const BACK_DIM := 0.62
## Contact shadow: open tiles touching stone are darkened, most under an
## overhang. Cheap ambient occlusion, and the thing that makes ledges look like
## they have a thickness.
const AO_STEP := 0.085
const AO_MAX := 0.40
## Rock gets darker the further it is from daylight. Without it the mass under
## a floor is one flat slab the height of the screen; with it the ledge you are
## standing on has a body that fades away underneath you.
const DEPTH_STEP := 0.075
const DEPTH_MAX := 7

var _tex: Dictionary = {}
var _theme_floor: Array[Texture2D] = []
var _theme_wall: Array[Texture2D] = []
var _theme_cap: Array[Texture2D] = []
var _theme_tint: Array[Color] = []
var _theme_of: PackedByteArray          # one theme index per tile
var _back: Node2D                       # the wall layer, behind the deco props


func _ready() -> void:
	add_to_group("level")
	z_index = TERRAIN_Z
	_tex = {
		BEAM: load("res://assets/sprites/tile_beam.png"),
		LADDER: load("res://assets/sprites/tile_ladder.png"),
		WATER: load("res://assets/sprites/tile_water.png"),
	}
	_load_themes()
	_build_collision()
	_build_back_layer()


## The back wall gets its own canvas item BELOW this one, so the deco props can
## be hung between the two: in front of the brickwork, behind the ledges.
func _build_back_layer() -> void:
	_back = BackLayer.new()
	(_back as BackLayer).level = self
	_back.z_as_relative = false          # absolute, so it cannot drift with us
	_back.z_index = BACK_Z
	add_child(_back)


class BackLayer extends Node2D:
	var level: Level

	func _draw() -> void:
		level.draw_back(self)


## Each region has its own stone. The lookup is baked into a byte per tile once,
## rather than asking "which area rect is this in?" 49152 times inside _draw().
func _load_themes() -> void:
	for a in LevelMap.AREAS:
		var theme: String = a["theme"]
		_theme_floor.append(load("res://assets/sprites/tile_floor_%s.png" % theme))
		_theme_wall.append(load("res://assets/sprites/tile_wall_%s.png" % theme))
		_theme_cap.append(load("res://assets/sprites/tile_cap_%s.png" % theme))
		var rgb: Array = a["light"]
		# the deco silhouettes are drawn grey and tinted per region, so one
		# sheet of chains and pillars dresses all eight
		_theme_tint.append(Color(0.70 + rgb[0] * 0.30, 0.70 + rgb[1] * 0.30,
				0.70 + rgb[2] * 0.30))

	# The generator already worked out which stone every tile is cut from,
	# including the rock between the rooms — doing it here would be 400k
	# distance tests at load for an answer that never changes.
	_theme_of = PackedByteArray()
	_theme_of.resize(LevelMap.W * LevelMap.H)
	for ty in LevelMap.H:
		var row: String = LevelMap.THEME_OF[ty]
		for tx in LevelMap.W:
			_theme_of[ty * LevelMap.W + tx] = row.unicode_at(tx) - 48


## Three layers of world, back to front. The props sit BETWEEN the wall and the
## stone on purpose: a chain then disappears into the ceiling it hangs from
## instead of being painted over it.
const BACK_Z := -20
const DECO_Z := -12
const TERRAIN_Z := -9


## Which stone this point is cut from — the region's LOOK, which extends into
## the rock between the rooms, unlike area_at() which names only the rooms.
func theme_name_at(world_pos: Vector2) -> String:
	var t := to_tile(world_pos)
	return LevelMap.AREAS[theme_index(t.x, t.y)]["theme"]


func theme_tint(tx: int, ty: int) -> Color:
	return _theme_tint[theme_index(tx, ty)]


func theme_index(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= LevelMap.W or ty >= LevelMap.H:
		return 0
	return _theme_of[ty * LevelMap.W + tx]


func world_size() -> Vector2:
	return Vector2(LevelMap.W * TILE, LevelMap.H * TILE)


func tile_at(tx: int, ty: int) -> String:
	if tx < 0 or ty < 0 or tx >= LevelMap.W or ty >= LevelMap.H:
		return SOLID
	return LevelMap.MAP[ty][tx]


func to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / TILE)), int(floor(world_pos.y / TILE)))


func is_ladder(world_pos: Vector2) -> bool:
	var t := to_tile(world_pos)
	return tile_at(t.x, t.y) == LADDER


func is_solid(tx: int, ty: int) -> bool:
	var ch := tile_at(tx, ty)
	return ch == SOLID or ch == BURIED


## The torch colour for wherever this point is — half of what makes a region
## feel like somewhere else (see THEME_LIGHT in tools/gen_level.py).
func light_at(world_pos: Vector2) -> Color:
	var t := to_tile(world_pos)
	var a: Dictionary = LevelMap.AREAS[theme_index(t.x, t.y)]
	var rgb: Array = a["light"]
	return Color(rgb[0], rgb[1], rgb[2])


## Name of the region a point falls in, or "" between regions.
func area_at(world_pos: Vector2) -> String:
	var t := to_tile(world_pos)
	for a in LevelMap.AREAS:
		var ax: int = a["x"]
		var ay: int = a["y"]
		var aw: int = a["w"]
		var ah: int = a["h"]
		if t.x >= ax and t.x < ax + aw and t.y >= ay and t.y < ay + ah:
			return a["name"]
	return ""


# ------------------------------------------------------------- collision ----
func _build_collision() -> void:
	var solid := StaticBody2D.new()
	solid.collision_layer = 1 << (WORLD_LAYER - 1)
	solid.collision_mask = 0
	add_child(solid)
	for r in LevelMap.SOLIDS:
		_add_box(solid, r, false)

	# One-way beams get their own body and layer, which is what lets the player
	# drop through them by muting that single layer for a moment.
	var beams := StaticBody2D.new()
	beams.collision_layer = 1 << (BEAM_LAYER - 1)
	beams.collision_mask = 0
	add_child(beams)
	for r in LevelMap.BEAMS:
		_add_box(beams, r, true)


func _add_box(body: StaticBody2D, r: Array, one_way: bool) -> void:
	var tx: int = r[0]
	var ty: int = r[1]
	var tw: int = r[2]
	var th: int = r[3]
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tw * TILE, th * TILE)
	cs.shape = rect
	cs.position = Vector2((tx + tw * 0.5) * TILE, (ty + th * 0.5) * TILE)
	cs.one_way_collision = one_way
	body.add_child(cs)


# ---------------------------------------------------------------- drawing ---
## Which of the four stone variants this tile uses. Two constants that share no
## factors keep neighbours off the same variant, so the shuffle does not settle
## into a visible pattern of its own.
func _variant(tx: int, ty: int) -> int:
	return absi((tx * 73856093) ^ (ty * 19349663)) % VARIANTS


## A hair of brightness jitter per tile. Identical tiles at identical brightness
## are what made the grid itself the most visible thing on screen.
func _jitter(tx: int, ty: int) -> float:
	return 0.93 + 0.14 * (float(absi((tx * 92837111) ^ (ty * 689287499)) % 5) / 4.0)


## Contact shadow for an OPEN tile: darkest with rock overhead, then for each
## side it touches.
func _ao(tx: int, ty: int) -> float:
	var n := 0
	if is_solid(tx, ty - 1):
		n += 2
	if is_solid(tx - 1, ty):
		n += 1
	if is_solid(tx + 1, ty):
		n += 1
	if is_solid(tx, ty + 1):
		n += 1
	return 1.0 - minf(AO_MAX, n * AO_STEP)


## How many solid tiles are stacked above this one, capped. Counted at load,
## once, into a texture that never changes.
func _depth(tx: int, ty: int) -> int:
	var d := 0
	while d < DEPTH_MAX and is_solid(tx, ty - 1 - d):
		d += 1
	return d


func _src(v: int) -> Rect2:
	return Rect2(v * TILE, 0, TILE, TILE)


## The wall behind everything, on its own canvas item (see BackLayer).
func draw_back(ci: CanvasItem) -> void:
	var cell := Vector2(TILE, TILE)
	for ty in LevelMap.H:
		var row: String = LevelMap.MAP[ty]
		var base := ty * LevelMap.W
		for tx in LevelMap.W:
			var ch := row[tx]
			if ch == BURIED or ch == SOLID:
				continue                  # stone covers its own tile
			var th := _theme_of[base + tx]
			var d := BACK_DIM * _jitter(tx, ty) * _ao(tx, ty)
			ci.draw_texture_rect_region(_theme_wall[th],
					Rect2(Vector2(tx * TILE, ty * TILE), cell),
					_src(_variant(tx, ty)), Color(d, d, d))


## The stone you actually stand on, plus the beams, ladders and water. Anything
## with air above it gets the crusted cap tile instead of plain floor — that
## lit lip is what separates ground from background at a glance.
func _draw() -> void:
	var cell := Vector2(TILE, TILE)
	for ty in LevelMap.H:
		var row: String = LevelMap.MAP[ty]
		var base := ty * LevelMap.W
		for tx in LevelMap.W:
			var ch := row[tx]
			if ch == BURIED:
				continue          # rock with no opening near it: never seen
			var th := _theme_of[base + tx]
			var at := Vector2(tx * TILE, ty * TILE)
			var v := _variant(tx, ty)
			if ch == SOLID:
				var j := _jitter(tx, ty) * (1.0 - DEPTH_STEP * _depth(tx, ty))
				var tex := _theme_floor[th]
				if not is_solid(tx, ty - 1):
					tex = _theme_cap[th]
					j += 0.06                 # the lip catches the light
				draw_texture_rect_region(tex, Rect2(at, cell), _src(v),
						Color(j, j, j))
			elif ch != AIR:
				draw_texture_rect_region(_tex[ch], Rect2(at, cell),
						Rect2(0, 0, TILE, TILE))
				# one lit line along the top of the body of water, not one per
				# tile — a stripe every 16px would read as a ladder, not a pool
				if ch == WATER and tile_at(tx, ty - 1) != WATER:
					draw_rect(Rect2(at, Vector2(TILE, 1)),
							Color(0.62, 0.88, 0.94, 0.72))
