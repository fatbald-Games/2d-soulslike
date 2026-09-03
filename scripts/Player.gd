class_name Player
extends CharacterBody2D
## The Ashen One. Deliberate, committed souls-like combat:
## every action costs stamina, attacks and rolls cannot be cancelled, and the
## dodge-roll grants a window of invulnerability (i-frames) in its middle.

signal health_changed(cur: float, maxv: float)
signal stamina_changed(cur: float, maxv: float)
signal souls_changed(amount: int)
signal died

# --- tuning ------------------------------------------------------------------
const SPEED := 78.0
const GRAVITY := 900.0
# Apex is v^2/2g = 40.5px, a hair over two 16px tiles. The level generator
# builds every step against exactly this number (see REACH_AT_RISE in
# tools/gen_level.py) -- changing it without regenerating the level will strand
# the knight under ledges he used to reach.
const JUMP_VELOCITY := -270.0

const CLIMB_SPEED := 52.0
const LADDER_HOP := -180.0         # pushing off a ladder
const DROP_THRU_TIME := 0.28       # how long beams are ignored after down+jump
const BEAM_LAYER := 2              # one-way beams live on their own layer

const ROLL_SPEED := 168.0
const ROLL_TIME := 0.42
const ROLL_IFRAME_FROM := 0.07     # i-frames start
const ROLL_IFRAME_TO := 0.30       # i-frames end  -> ~55% of the roll is safe

const ATTACK_TIME := 0.36
const ATTACK_HIT_AT := 0.15        # the strike frame
const ATTACK_REACH := 30.0
const ATTACK_DAMAGE := 34.0

const HEALTH_MAX := 100.0
const STAMINA_MAX := 100.0
const STAMINA_REGEN := 38.0
const STAMINA_REGEN_DELAY := 0.45
const ATTACK_COST := 28.0
const ROLL_COST := 22.0

const HURT_TIME := 0.28
const INVULN_AFTER_HIT := 0.65

enum State { IDLE, RUN, ATTACK, ROLL, HURT, DEAD, CLIMB }

var state: State = State.IDLE
var facing := 1                    # +1 right, -1 left
var health := HEALTH_MAX
var stamina := STAMINA_MAX
var souls := 0

var _t := 0.0                      # time inside the current state
var _regen_block := 0.0
var _invuln := 0.0
var _hit_done := false
var _drop_thru := 0.0              # >0 while falling through a one-way beam
var _level: Node = null            # asked whether a ladder is under him

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("player")
	_level = get_tree().get_first_node_in_group("level")
	sprite.play("idle")
	health_changed.emit(health, HEALTH_MAX)
	stamina_changed.emit(stamina, STAMINA_MAX)
	souls_changed.emit(souls)


## True where a ladder tile covers him — checked at the chest, not the feet, so
## he still counts as on the ladder while standing on the floor at its foot.
func _on_ladder() -> bool:
	if _level == null or not _level.has_method("is_ladder"):
		return false
	return _level.is_ladder(global_position + Vector2(0, -12))


func is_invulnerable() -> bool:
	if _invuln > 0.0:
		return true
	return state == State.ROLL and _t >= ROLL_IFRAME_FROM and _t <= ROLL_IFRAME_TO


func _physics_process(delta: float) -> void:
	_t += delta
	_invuln = maxf(0.0, _invuln - delta)
	_tick_stamina(delta)
	_tick_drop_thru(delta)

	# climbing hangs off the wall: no gravity while he has hold of a rung
	if not is_on_floor() and state != State.CLIMB:
		velocity.y += GRAVITY * delta

	match state:
		State.IDLE, State.RUN:
			_ground_state(delta)
		State.ATTACK:
			_attack_state(delta)
		State.ROLL:
			_roll_state(delta)
		State.CLIMB:
			_climb_state(delta)
		State.HURT:
			_decelerate(delta, 420.0)
			if _t >= HURT_TIME:
				_enter(State.IDLE)
		State.DEAD:
			_decelerate(delta, 600.0)

	move_and_slide()
	_update_flash()


## One-way beams are their own collision layer, so dropping through one is just
## a matter of not looking at that layer for a moment.
func _tick_drop_thru(delta: float) -> void:
	if _drop_thru <= 0.0:
		return
	_drop_thru -= delta
	if _drop_thru <= 0.0:
		set_collision_mask_value(BEAM_LAYER, true)


# --- states ------------------------------------------------------------------
func _ground_state(delta: float) -> void:
	if Input.is_action_just_pressed("attack") and _spend(ATTACK_COST):
		_enter(State.ATTACK)
		return
	if Input.is_action_just_pressed("dodge") and _spend(ROLL_COST):
		_enter(State.ROLL)
		return

	# up/down on a ladder takes hold of it
	var vert := Input.get_axis("up", "down")
	if vert != 0.0 and _on_ladder():
		_enter(State.CLIMB)
		return

	var dir := Input.get_axis("left", "right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		velocity.x = dir * SPEED
		_set_state_anim(State.RUN)
	else:
		_decelerate(delta, 700.0)
		_set_state_anim(State.IDLE)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		# down + jump drops through a beam instead of hopping off it
		if Input.is_action_pressed("down"):
			_begin_drop_thru()
		else:
			velocity.y = JUMP_VELOCITY


func _begin_drop_thru() -> void:
	_drop_thru = DROP_THRU_TIME
	set_collision_mask_value(BEAM_LAYER, false)
	velocity.y = 40.0                 # a nudge, so he clears the beam at once


func _climb_state(_delta: float) -> void:
	# stepping off sideways, or running out of ladder, puts him back on his feet
	var dir := Input.get_axis("left", "right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		velocity.x = dir * SPEED
		_enter(State.IDLE)
		return
	if not _on_ladder():
		_enter(State.IDLE)
		return
	if Input.is_action_just_pressed("jump"):
		velocity.y = LADDER_HOP
		_enter(State.IDLE)
		return

	velocity.x = 0.0
	var vert := Input.get_axis("up", "down")
	velocity.y = vert * CLIMB_SPEED
	# the roll frames read as a climbing scramble; freeze them when he stops
	sprite.speed_scale = 1.0 if vert != 0.0 else 0.0


func _attack_state(delta: float) -> void:
	_decelerate(delta, 500.0)
	if not _hit_done and _t >= ATTACK_HIT_AT:
		_hit_done = true
		_swing()
	if _t >= ATTACK_TIME:
		_enter(State.IDLE)


func _roll_state(_delta: float) -> void:
	velocity.x = facing * ROLL_SPEED
	if _t >= ROLL_TIME:
		_enter(State.IDLE)


func _enter(next: State) -> void:
	state = next
	_t = 0.0
	_hit_done = false
	sprite.speed_scale = 1.0
	match next:
		State.IDLE:
			sprite.play("idle")
		State.RUN:
			sprite.play("run")
		State.ATTACK:
			sprite.play("attack")
		State.ROLL:
			sprite.play("roll")
		State.CLIMB:
			sprite.play("roll")   # the tucked frames read as a scramble
		State.HURT:
			sprite.play("idle")
		State.DEAD:
			sprite.play("roll")   # crumples forward
	sprite.flip_h = facing < 0


func _set_state_anim(next: State) -> void:
	# stay inside the ground states without restarting the animation each frame
	if state != next:
		state = next
		_t = 0.0
		sprite.play("run" if next == State.RUN else "idle")
	sprite.flip_h = facing < 0


# --- combat ------------------------------------------------------------------
func _swing() -> void:
	var box := _hit_rect(ATTACK_REACH, 26.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if box.has_point(e.global_position + Vector2(0, -12)):
			if e.has_method("take_damage"):
				e.take_damage(ATTACK_DAMAGE, global_position)


func _hit_rect(reach: float, height: float) -> Rect2:
	var x := global_position.x if facing > 0 else global_position.x - reach
	return Rect2(x, global_position.y - height - 2.0, reach, height)


func take_damage(amount: float, from: Vector2) -> void:
	if state == State.DEAD or is_invulnerable():
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, HEALTH_MAX)
	_invuln = INVULN_AFTER_HIT
	var away := 1.0 if global_position.x >= from.x else -1.0
	velocity.x = away * 110.0
	velocity.y = -90.0
	if health <= 0.0:
		_enter(State.DEAD)
		died.emit()
	else:
		_enter(State.HURT)


func add_souls(n: int) -> void:
	souls += n
	souls_changed.emit(souls)


# --- helpers -----------------------------------------------------------------
func _spend(cost: float) -> bool:
	if stamina < cost:
		return false
	stamina -= cost
	_regen_block = STAMINA_REGEN_DELAY
	stamina_changed.emit(stamina, STAMINA_MAX)
	return true


func _tick_stamina(delta: float) -> void:
	if state == State.DEAD:
		return
	if _regen_block > 0.0:
		_regen_block -= delta
		return
	if stamina < STAMINA_MAX:
		stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN * delta)
		stamina_changed.emit(stamina, STAMINA_MAX)


func _decelerate(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)


func _update_flash() -> void:
	# blink while invulnerable from a hit; steady cyan tint during roll i-frames
	if state == State.ROLL and is_invulnerable():
		sprite.modulate = Color(0.75, 1.0, 1.0)
	elif _invuln > 0.0:
		var on := int(_invuln * 20.0) % 2 == 0
		sprite.modulate = Color(1, 0.6, 0.6) if on else Color(1, 1, 1)
	else:
		sprite.modulate = Color(1, 1, 1)
