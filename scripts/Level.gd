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

var _tex: Dictionary = {}
var _theme_floor: Array[Texture2D] = []
var _theme_wall: Array[Texture2D] = []
var _theme_of: PackedByteArray          # one theme index per tile


func _ready() -> void:
	add_to_group("level")
	_tex = {
		BEAM: load("res://assets/sprites/tile_beam.png"),
		LADDER: load("res://assets/sprites/tile_ladder.png"),
		WATER: load("res://assets/sprites/tile_water.png"),
	}
	_load_themes()
	_build_collision()


## Each region has its own stone. The lookup is baked into a byte per tile once,
## rather than asking "which area rect is this in?" 49152 times inside _draw().
func _load_themes() -> void:
	for a in LevelMap.AREAS:
		var theme: String = a["theme"]
		_theme_floor.append(load("res://assets/sprites/tile_floor_%s.png" % theme))
		_theme_wall.append(load("res://assets/sprites/tile_wall_%s.png" % theme))

	_theme_of = PackedByteArray()
	_theme_of.resize(LevelMap.W * LevelMap.H)
	for i in _theme_of.size():
		_theme_of[i] = 0
	for ai in LevelMap.AREAS.size():
		var a: Dictionary = LevelMap.AREAS[ai]
		var ax: int = a["x"]
		var ay: int = a["y"]
		for ty in range(ay, mini(ay + int(a["h"]), LevelMap.H)):
			for tx in range(ax, mini(ax + int(a["w"]), LevelMap.W)):
				_theme_of[ty * LevelMap.W + tx] = ai


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
			if ch == SOLID:
				draw_texture_rect(_theme_floor[th], Rect2(at, cell), false)
			else:
				# every open tile shows the wall behind it first
				draw_texture_rect(_theme_wall[th], Rect2(at, cell), false)
				if ch != AIR:
					draw_texture_rect(_tex[ch], Rect2(at, cell), false)
