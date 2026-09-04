class_name Projectile
extends Node2D
## An arrow or a bolt in flight.
##
## No physics body: at 300-470 px/s across a 6144px map, a CharacterBody2D per
## arrow buys nothing over stepping the position and asking the level whether
## the point is rock. The hollows are a handful of nodes, so testing them
## directly is cheaper than a collision layer as well.
##
## The two ranged weapons differ in the air, not just on the damage line: an
## arrow droops on the way out, a bolt goes where you pointed it.

signal struck(at: Vector2)

const HIT_PAD := Vector2(6, 12)     # how generously a shot counts as a hit

var dir := 1
var speed := 320.0
var drop := 0.0                     # downward acceleration, px/s^2
var damage := 20.0
var knock := 60.0
var life := 1.6

var _vy := 0.0
var _level: Level


func _ready() -> void:
	_level = get_tree().get_first_node_in_group("level") as Level


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	_vy += drop * delta
	position += Vector2(dir * speed * delta, _vy * delta)
	# a drooping arrow should visibly nose over, not slide sideways
	rotation = atan2(_vy, speed) * float(dir)

	if _hit_enemy() or _hit_world():
		struck.emit(global_position)
		queue_free()


func _hit_world() -> bool:
	if _level == null:
		return false
	var t := _level.to_tile(global_position)
	var ch := _level.tile_at(t.x, t.y)
	return ch == Level.SOLID or ch == Level.BURIED


func _hit_enemy() -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var body: Node2D = e
		if body.has_method("is_dead") and body.is_dead():
			continue
		# hollows are anchored at the feet, so their middle is a body up
		var centre: Vector2 = body.global_position + Vector2(0, -12)
		var d: Vector2 = (global_position - centre).abs()
		if d.x <= HIT_PAD.x and d.y <= HIT_PAD.y:
			if body.has_method("take_damage"):
				body.take_damage(damage, global_position - Vector2(dir * 8.0, 0.0))
			return true
	return false
