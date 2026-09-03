class_name Level
extends Node2D
## The dungeon itself: terrain drawing, collision and tile queries.
##
## The map comes from LevelMap.gd, which tools/gen_level.py generates and — more
## importantly — proves reachable before it writes. Actors are NOT spawned here;
## Main does that from LevelMap.ENTITIES, so terrain and cast stay separable.
##
## Two things keep 12288 tiles cheap:
##   * drawing happens in one _draw() on a single canvas item rather than one
##     Sprite2D per tile, and only tiles that can actually be seen are drawn —
##     rock buried behind other rock is skipped entirely.
##   * collision is a few dozen merged rectangles, not a body per tile.

const TILE := LevelMap.TILE
const SOLID := "#"
const AIR := "."
const BEAM := "="
const LADDER := "H"

const WORLD_LAYER := 1
const BEAM_LAYER := 2

var _tex: Dictionary = {}


func _ready() -> void:
	add_to_group("level")
	_tex = {
		SOLID: load("res://assets/sprites/tile_floor.png"),
		AIR: load("res://assets/sprites/tile_wall.png"),
		BEAM: load("res://assets/sprites/tile_beam.png"),
		LADDER: load("res://assets/sprites/tile_ladder.png"),
	}
	_build_collision()


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
	for ty in LevelMap.H:
		var row: String = LevelMap.MAP[ty]
		for tx in LevelMap.W:
			var ch := row[tx]
			if ch == SOLID and not _is_exposed(tx, ty):
				continue          # buried rock: nothing can ever see it
			var at := Vector2(tx * TILE, ty * TILE)
			if ch != SOLID:
				# every open tile shows the wall behind it first
				draw_texture_rect(_tex[AIR], Rect2(at, Vector2(TILE, TILE)), false)
				if ch != AIR:
					draw_texture_rect(_tex[ch], Rect2(at, Vector2(TILE, TILE)), false)
			else:
				draw_texture_rect(_tex[SOLID], Rect2(at, Vector2(TILE, TILE)), false)


## Solid rock is only worth drawing near an opening. Two tiles deep rather than
## one, so a floor reads as a mass of rock with darkness beyond it instead of a
## single lit course with a hard edge into nothing.
const ROCK_DEPTH := 2


func _is_exposed(tx: int, ty: int) -> bool:
	for dy in range(-ROCK_DEPTH, ROCK_DEPTH + 1):
		for dx in range(-ROCK_DEPTH, ROCK_DEPTH + 1):
			if dx == 0 and dy == 0:
				continue
			if tile_at(tx + dx, ty + dy) != SOLID:
				return true
	return false
