class_name Hollow
extends CharacterBody2D
## A husk of a soldier. Shambles toward the player, then commits to a slow,
## clearly telegraphed overhead strike — long enough to read and roll through.

const GRAVITY := 900.0
const CHASE_SPEED := 30.0

const DETECT_RANGE := 130.0
const ATTACK_RANGE := 30.0

const WINDUP_TIME := 0.55          # the telegraph — deliberately readable
const STRIKE_TIME := 0.22
const RECOVER_TIME := 0.55
const HURT_TIME := 0.26

const STRIKE_REACH := 28.0
const DAMAGE := 22.0

const HEALTH_MAX := 100.0
const SOULS_REWARD := 60

enum State { IDLE, WINDUP, STRIKE, RECOVER, HURT, DEAD }

var state: State = State.IDLE
var facing := -1                   # the sheet faces LEFT by default
var health := HEALTH_MAX

var _t := 0.0
var _hit_done := false
var _rewarded := false
var _flash_tween: Tween

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("enemy")
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	_t += delta
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	match state:
		State.IDLE:
			_idle_state(delta)
		State.WINDUP:
			_brake(delta)
			if _t >= WINDUP_TIME:
				_enter(State.STRIKE)
		State.STRIKE:
			velocity.x = facing * 40.0        # small committed lunge
			if not _hit_done and _t >= 0.04:
				_hit_done = true
				_strike()
			if _t >= STRIKE_TIME:
				_enter(State.RECOVER)
		State.RECOVER:
			_brake(delta)
			if _t >= RECOVER_TIME:
				_enter(State.IDLE)
		State.HURT:
			_brake(delta)
			if _t >= HURT_TIME:
				_enter(State.IDLE)
		State.DEAD:
			_brake(delta)

	move_and_slide()


func _idle_state(delta: float) -> void:
	var p := _player()
	if p == null:
		_brake(delta)
		_play("idle")
		return
	var dx: float = p.global_position.x - global_position.x
	var dy: float = absf(p.global_position.y - global_position.y)
	if absf(dx) > DETECT_RANGE or dy > 40.0:
		_brake(delta)
		_play("idle")
		return

	facing = 1 if dx > 0.0 else -1
	sprite.flip_h = facing > 0          # sheet faces left, so flip to face right

	if absf(dx) <= ATTACK_RANGE:
		_enter(State.WINDUP)
	else:
		velocity.x = facing * CHASE_SPEED
		_play("idle")


func _play(anim: String) -> void:
	# called every frame — never restart an animation that is already running
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)


func _enter(next: State) -> void:
	state = next
	_t = 0.0
	_hit_done = false
	match next:
		State.IDLE:
			sprite.play("idle")
		State.WINDUP:
			sprite.play("windup")
		State.STRIKE:
			sprite.play("strike")
		State.HURT:
			sprite.play("hurt")
		State.RECOVER:
			sprite.play("idle")
		State.DEAD:
			sprite.play("dead")
	sprite.flip_h = facing > 0


func _strike() -> void:
	var x := global_position.x if facing > 0 else global_position.x - STRIKE_REACH
	var box := Rect2(x, global_position.y - 26.0, STRIKE_REACH, 24.0)
	var p := _player()
	if p != null and box.has_point(p.global_position + Vector2(0, -12)):
		if p.has_method("take_damage"):
			p.take_damage(DAMAGE, global_position)


## `knock` is how hard it throws them: the axe and the shield bash move a hollow
## clean out of its own attack range, which is most of what they are for.
func take_damage(amount: float, from: Vector2, knock: float = 70.0) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_flash()
	Audio.play("hit_flesh")
	var away := 1.0 if global_position.x >= from.x else -1.0
	velocity.x = away * knock
	if knock > 160.0:
		velocity.y = -70.0
	if health <= 0.0:
		_die()
	else:
		_enter(State.HURT)


## A blown-out white frame on contact. Two frames of it is the difference
## between "the number went down" and "that landed".
func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(2.4, 2.2, 2.2)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.16)


func is_dead() -> bool:
	return state == State.DEAD


func _die() -> void:
	_enter(State.DEAD)
	if not _rewarded:
		_rewarded = true
		Run.slain += 1
		var p := _player()
		if p != null and p.has_method("add_souls"):
			p.add_souls(SOULS_REWARD)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)


func _player() -> Node2D:
	var list := get_tree().get_nodes_in_group("player")
	for n in list:
		if is_instance_valid(n) and n is Node2D:
			return n
	return null


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
