class_name Player
extends CharacterBody2D
## The Ashen One. Deliberate, committed souls-like combat:
## every action costs stamina, attacks and rolls cannot be cancelled, and the
## dodge-roll grants a window of invulnerability (i-frames) in its middle.

signal health_changed(cur: float, maxv: float)
signal stamina_changed(cur: float, maxv: float)
signal souls_changed(amount: int)
signal flask_changed(cur: int, maxv: int)
signal hit_landed(at: Vector2)
signal shot(from: Vector2, dir: int, damage: float, weapon: int)
signal weapon_changed(idx: int)
signal guarded(at: Vector2, broke: bool)
signal died

# --- tuning ------------------------------------------------------------------
const SPEED_BASE := 78.0
const SPEED_PER_AGILITY := 4.0
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

const ATTACK_TIME_BASE := 0.36
const ATTACK_TIME_PER_FINESSE := 0.011   # 10 points takes a swing to 0.25s
const ATTACK_HIT_FRACTION := 0.42        # where in the swing the blow lands
const ATTACK_REACH := 30.0               # the longsword's reach; see Weapons.gd

# Guarding, with the shield equipped. It is deliberately not a free "no" to
# every attack: it eats stamina per blow, and running out mid-block breaks the
# guard and lets the whole hit through.
const BLOCK_SPEED := 0.40                # how much of his walk he keeps up
const BLOCK_COST_PER_DAMAGE := 2.1       # stamina burnt per point absorbed

# Bases, before anything is spent at a bonfire. The three stats in Run.gd move
# these, and each one shows on the HUD immediately: VIGOR and ENDURANCE make
# their bars physically longer, STRENGTH lands harder.
const HEALTH_BASE := 100.0
const HEALTH_PER_VIGOR := 12.0
const STAMINA_BASE := 100.0
const STAMINA_PER_ENDURANCE := 10.0
const ATTACK_BASE := 34.0
const ATTACK_PER_STRENGTH := 5.0
const STAMINA_REGEN := 38.0
const STAMINA_REGEN_DELAY := 0.45
const ROLL_COST := 22.0

const HURT_TIME := 0.28
const INVULN_AFTER_HIT := 0.65

# The flask heals a lot but locks him in place for the better part of a second
# and grants no i-frames — drinking in front of a winding-up hollow should be
# the wrong call, not a free reset.
const FLASK_MAX := 3
const FLASK_HEAL := 45.0
const DRINK_TIME := 0.75
const DRINK_HEAL_AT := 0.45

enum State { IDLE, RUN, ATTACK, ROLL, HURT, DEAD, CLIMB, DRINK, BLOCK }

var state: State = State.IDLE
var facing := 1                    # +1 right, -1 left
var health_max := HEALTH_BASE
var stamina_max := STAMINA_BASE
var attack_damage := ATTACK_BASE
var speed := SPEED_BASE
var attack_time := ATTACK_TIME_BASE

var health := HEALTH_BASE
var stamina := STAMINA_BASE
var souls := 0
var flask := FLASK_MAX

var _t := 0.0                      # time inside the current state
var _regen_block := 0.0
var _invuln := 0.0
var _hit_done := false
var _drank := false
var _drop_thru := 0.0              # >0 while falling through a one-way beam
var _shot_done := false           # one arrow per pull, not one per frame
var _level: Node = null            # asked whether a ladder is under him

@onready var sprite: AnimatedSprite2D = $Sprite


## Reads the three stats out of Run and turns them into the numbers that matter.
## Called on spawn and again the moment a level is bought.
func apply_stats(top_up: bool = false) -> void:
	health_max = HEALTH_BASE + Run.stats[Run.VIGOR] * HEALTH_PER_VIGOR
	stamina_max = STAMINA_BASE + Run.stats[Run.ENDURANCE] * STAMINA_PER_ENDURANCE
	speed = SPEED_BASE + Run.stats[Run.AGILITY] * SPEED_PER_AGILITY
	attack_damage = ATTACK_BASE + Run.stats[Run.STRENGTH] * ATTACK_PER_STRENGTH
	attack_time = (ATTACK_TIME_BASE - Run.stats[Run.FINESSE] * ATTACK_TIME_PER_FINESSE) \
			* float(weapon()["speed"])
	if top_up:
		health = health_max
		stamina = stamina_max
	else:
		health = minf(health, health_max)
		stamina = minf(stamina, stamina_max)
	health_changed.emit(health, health_max)
	stamina_changed.emit(stamina, stamina_max)


# --- the armoury -------------------------------------------------------------
## What is in his hands right now. Everything about a swing — how far it
## reaches, how long it takes, what it costs, whether it even makes contact or
## looses an arrow — comes off this one dictionary.
func weapon() -> Dictionary:
	return Weapons.def(Run.weapon)


## The damage this weapon actually deals, STRENGTH included.
func swing_damage() -> float:
	return attack_damage * float(weapon()["damage"])


func attack_cost() -> float:
	return float(weapon()["stamina"])


## Put a different weapon in his hands. Returns true if anything changed, so
## Main only rebuilds the sprite sheets when it has to.
func equip(idx: int) -> bool:
	if not Run.equip(idx):
		return false
	apply_stats()
	weapon_changed.emit(Run.weapon)
	return true


func swap_weapon(dir: int) -> bool:
	var before := Run.weapon
	Run.cycle_weapon(dir)
	if Run.weapon == before:
		return false
	apply_stats()
	weapon_changed.emit(Run.weapon)
	return true


func is_blocking() -> bool:
	return state == State.BLOCK


func _ready() -> void:
	add_to_group("player")
	# top_up: a freshly spawned knight starts at his FULL maximum. Without this
	# he respawns on the base 100 while VIGOR has already raised the cap.
	apply_stats(true)
	_level = get_tree().get_first_node_in_group("level")
	sprite.play("idle")
	health_changed.emit(health, health_max)
	stamina_changed.emit(stamina, stamina_max)
	souls_changed.emit(souls)
	flask_changed.emit(flask, FLASK_MAX)


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
		State.DRINK:
			_drink_state(delta)
		State.BLOCK:
			_block_state(delta)
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
	if Input.is_action_just_pressed("swap") and swap_weapon(1):
		return
	if Input.is_action_just_pressed("attack") and _spend(attack_cost()):
		_enter(State.ATTACK)
		return
	# raising the shield is not an action with a cost — the cost lands when
	# something actually hits it
	if Weapons.can_block(Run.weapon) and Input.is_action_pressed("block") \
			and is_on_floor():
		_enter(State.BLOCK)
		return
	if Input.is_action_just_pressed("dodge") and _spend(ROLL_COST):
		_enter(State.ROLL)
		return

	if Input.is_action_just_pressed("heal") and flask > 0 and is_on_floor():
		_enter(State.DRINK)
		return

	# up/down on a ladder takes hold of it
	var vert := Input.get_axis("up", "down")
	if vert != 0.0 and _on_ladder():
		_enter(State.CLIMB)
		return

	var dir := Input.get_axis("left", "right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		velocity.x = dir * speed
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


## Guarding: he can shuffle, slowly, and do nothing else. Coming off the shield
## is instant, which is what makes it worth raising at all.
func _block_state(delta: float) -> void:
	if not Input.is_action_pressed("block") or not Weapons.can_block(Run.weapon):
		_enter(State.IDLE)
		return
	var dir := Input.get_axis("left", "right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		sprite.flip_h = facing < 0
		velocity.x = dir * speed * BLOCK_SPEED
	else:
		_decelerate(delta, 700.0)


func _drink_state(delta: float) -> void:
	_decelerate(delta, 600.0)
	if not _drank and _t >= DRINK_HEAL_AT:
		_drank = true
		flask -= 1
		health = minf(health_max, health + FLASK_HEAL)
		health_changed.emit(health, health_max)
		flask_changed.emit(flask, FLASK_MAX)
	if _t >= DRINK_TIME:
		_enter(State.IDLE)


## Sitting at a bonfire: full health, full flask.
func rest() -> void:
	health = health_max
	stamina = stamina_max
	flask = FLASK_MAX
	health_changed.emit(health, health_max)
	stamina_changed.emit(stamina, stamina_max)
	flask_changed.emit(flask, FLASK_MAX)


func _climb_state(_delta: float) -> void:
	# stepping off sideways, or running out of ladder, puts him back on his feet
	var dir := Input.get_axis("left", "right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		velocity.x = dir * speed
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
	if not _hit_done and _t >= attack_time * ATTACK_HIT_FRACTION:
		_hit_done = true
		_swing()

	if _t >= attack_time:
		_enter(State.IDLE)


func _roll_state(_delta: float) -> void:
	velocity.x = facing * ROLL_SPEED
	if _t >= ROLL_TIME:
		_enter(State.IDLE)


func _enter(next: State) -> void:
	state = next
	_t = 0.0
	_hit_done = false
	_drank = false
	_shot_done = false
	sprite.speed_scale = 1.0
	match next:
		State.IDLE:
			sprite.play("idle")
		State.RUN:
			sprite.play("run")
		State.ATTACK:
			sprite.play("attack")
			# the swing sheet is authored at ATTACK_TIME_BASE, so a faster swing
			# has to play back proportionally faster or the blow lands after the
			# animation has already finished
			sprite.speed_scale = ATTACK_TIME_BASE / attack_time
		State.ROLL:
			sprite.play("roll")
		State.CLIMB:
			sprite.play("roll")   # the tucked frames read as a scramble
		State.DRINK:
			sprite.play("idle")
		State.BLOCK:
			sprite.play("block")
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
## The moment of contact. A bow or crossbow looses instead — Main puts the
## arrow in the world, because the projectile has to outlive this frame and the
## player is not the right owner for it.
func _swing() -> void:
	var w := weapon()
	if w["kind"] == Weapons.RANGED:
		_loose()
		return
	var box := _hit_rect(float(w["reach"]), float(w["height"]))
	var knock := float(w["knock"])
	var dmg := swing_damage()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if box.has_point(e.global_position + Vector2(0, -12)):
			if e.has_method("take_damage"):
				e.take_damage(dmg, global_position, knock)
			# sparks and a kick of the camera, so contact READS as contact
			hit_landed.emit((e.global_position + global_position) * 0.5
					+ Vector2(0, -14))


func _loose() -> void:
	if _shot_done:
		return
	_shot_done = true
	shot.emit(global_position + Vector2(facing * 10.0, -16.0), facing,
			swing_damage(), Run.weapon)


func _hit_rect(reach: float, height: float) -> Rect2:
	var x := global_position.x if facing > 0 else global_position.x - reach
	return Rect2(x, global_position.y - height - 2.0, reach, height)


func take_damage(amount: float, from: Vector2) -> void:
	if state == State.DEAD or is_invulnerable():
		return
	amount = _absorb(amount, from)
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, health_max)
	_invuln = INVULN_AFTER_HIT
	var away := 1.0 if global_position.x >= from.x else -1.0
	velocity.x = away * 110.0
	velocity.y = -90.0
	if health <= 0.0:
		_enter(State.DEAD)
		died.emit()
	else:
		_enter(State.HURT)


## What the shield takes off an incoming hit. Only blows arriving from the side
## he is facing count — turning your back on something with the guard up should
## not save you. Running the stamina out mid-block BREAKS the guard: the rest of
## that blow lands in full, and he is wide open for the recovery.
func _absorb(amount: float, from: Vector2) -> float:
	if state != State.BLOCK:
		return amount
	var toward := 1.0 if from.x >= global_position.x else -1.0
	if int(toward) != facing:
		return amount
	var soak: float = float(weapon().get("block", 0.0))
	var cost := amount * soak * BLOCK_COST_PER_DAMAGE
	if stamina < cost:
		stamina = 0.0
		stamina_changed.emit(stamina, stamina_max)
		guarded.emit(global_position, true)
		return amount                       # guard break: the whole blow lands
	stamina -= cost
	_regen_block = STAMINA_REGEN_DELAY
	stamina_changed.emit(stamina, stamina_max)
	guarded.emit(global_position, false)
	var through := amount * (1.0 - soak)
	if through <= 0.0:
		var away := 1.0 if global_position.x >= from.x else -1.0
		velocity.x = away * 40.0            # shoved, not staggered
		return 0.0
	return through


func add_souls(n: int) -> void:
	souls += n
	souls_changed.emit(souls)


# --- helpers -----------------------------------------------------------------
func _spend(cost: float) -> bool:
	if stamina < cost:
		return false
	stamina -= cost
	_regen_block = STAMINA_REGEN_DELAY
	stamina_changed.emit(stamina, stamina_max)
	return true


func _tick_stamina(delta: float) -> void:
	if state == State.DEAD:
		return
	if _regen_block > 0.0:
		_regen_block -= delta
		return
	if stamina < stamina_max:
		stamina = minf(stamina_max, stamina + STAMINA_REGEN * delta)
		stamina_changed.emit(stamina, stamina_max)


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
