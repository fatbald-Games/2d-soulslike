class_name Run
extends RefCounted
## State that has to outlive a scene reload: the bonfire you last rested at, and
## the souls lying where you died.
##
## Dying calls reload_current_scene(), which destroys every node in the level —
## so none of this can live on the player. Static vars survive both a reload and
## a change_scene, and NEW GAME wipes them with reset().

static var has_checkpoint := false
static var checkpoint := Vector2.ZERO      # world position of the last bonfire

## Souls dropped where you fell. Dying again before you collect them replaces
## the pile — the old one is gone for good, which is the whole point.
static var has_drop := false
static var drop_pos := Vector2.ZERO
static var dropped_souls := 0

static var souls := 0
static var flask := 3


static func reset() -> void:
	has_checkpoint = false
	checkpoint = Vector2.ZERO
	has_drop = false
	drop_pos = Vector2.ZERO
	dropped_souls = 0
	souls = 0
	flask = Player.FLASK_MAX


static func rest_at(pos: Vector2) -> void:
	has_checkpoint = true
	checkpoint = pos


## Called on death: bank what the knight was carrying, then empty his pockets.
static func drop(at: Vector2, amount: int) -> void:
	has_drop = amount > 0
	drop_pos = at
	dropped_souls = amount
	souls = 0


static func collect() -> int:
	var n := dropped_souls
	has_drop = false
	dropped_souls = 0
	return n
