extends SceneTree
## Headless regression test for the combat slice.
##
##   godot --headless --path . --script res://tools/smoke_test.gd
##
## Boots Main.tscn for real and drives it a physics frame at a time, asserting
## on the things that are easy to break by accident: landing, movement, the
## stamina economy, the attack hitbox, roll i-frames and the death handoff.
## Exits non-zero when anything fails, so it works as a CI gate.

var _main: Node
var _player: Player
var _fails: Array[String] = []
var _checks := 0
var _step := 0
var _phase := 0
var _phase_frame := -1     # incremented at the top of each step -> first step is 0

# scratch state carried between phases
var _x0 := 0.0
var _stamina0 := 0.0
var _hollow: Hollow
var _hollow_hp0 := 0.0
var _souls0 := 0
var _died := false
var _iframe_seen := false
var _iframe_gap_seen := false
var _windup_seen := false
var _strike_seen := false
var _old_main: Node


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	# mirror how the engine boots the main scene, so reload_current_scene()
	# (the respawn path) behaves here exactly as it does in a real run
	current_scene = _main
	print("— Ashen Hollow smoke test —")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ok    %s" % label)
	else:
		var line := label if detail.is_empty() else "%s  (%s)" % [label, detail]
		print("  FAIL  %s" % line)
		_fails.append(line)


func _press(action: String) -> void:
	Input.action_press(action)


func _release(action: String) -> void:
	Input.action_release(action)


func _release_all() -> void:
	for a in ["left", "right", "jump", "attack", "dodge"]:
		Input.action_release(a)


## Advances to the next phase and resets that phase's frame counter.
func _next() -> void:
	_phase += 1
	_phase_frame = -1        # about to be incremented back to 0


func _physics_process(_delta: float) -> bool:
	_step += 1
	_phase_frame += 1
	if _step > 3000:
		_ok("test completed within frame budget", false, "phase %d stalled" % _phase)
		return _finish()

	match _phase:
		0: _phase_boot()
		1: _phase_move()
		2: _phase_attack_costs_stamina()
		3: _phase_attack_hits()
		4: _phase_kill_and_reward()
		5: _phase_roll_iframes()
		6: _phase_hollow_attack_loop()
		7: _phase_damage_and_death()
		8: _phase_respawn()
		_: return _finish()
	return false


# --------------------------------------------------------------- phases ------
func _phase_boot() -> void:
	if _phase_frame == 0:
		_player = _main.player
		_ok("player spawned", _player != null)
		if _player == null:
			_phase = 99
			return
		var enemies := get_nodes_in_group("enemy")
		_ok("two hollows spawned", enemies.size() == 2, "got %d" % enemies.size())
		_ok("HUD built", _main.hud != null)
		_ok("input actions registered", InputMap.has_action("attack") and InputMap.has_action("dodge"))
		return
	if _phase_frame >= 40:
		_ok("player lands on the floor", _player.is_on_floor(),
				"y=%.1f on_floor=%s" % [_player.global_position.y, _player.is_on_floor()])
		_ok("player starts at full health", is_equal_approx(_player.health, Player.HEALTH_MAX))
		_next()


func _phase_move() -> void:
	if _phase_frame == 0:
		_x0 = _player.global_position.x
		_press("right")
		return
	if _phase_frame == 20:
		_ok("holding right moves the player right",
				_player.global_position.x > _x0 + 8.0,
				"moved %.1f px" % (_player.global_position.x - _x0))
		_ok("player faces right while running", _player.facing == 1)
		_ok("player enters RUN state", _player.state == Player.State.RUN)
		_release_all()
		return
	if _phase_frame >= 34:
		_ok("player returns to IDLE after release", _player.state == Player.State.IDLE)
		_next()


func _phase_attack_costs_stamina() -> void:
	if _phase_frame == 0:
		_player.stamina = Player.STAMINA_MAX
		_stamina0 = _player.stamina
		_press("attack")
		return
	if _phase_frame == 2:
		_release("attack")
		_ok("attack enters ATTACK state", _player.state == Player.State.ATTACK,
				"state=%d" % _player.state)
		_ok("attack drains stamina",
				_player.stamina <= _stamina0 - Player.ATTACK_COST + 0.01,
				"%.1f -> %.1f" % [_stamina0, _player.stamina])
		return
	# ATTACK_TIME is 0.36s -> ~22 physics frames at 60 Hz
	if _phase_frame == 24:
		_ok("attack ends and returns to a ground state",
				_player.state == Player.State.IDLE or _player.state == Player.State.RUN,
				"state=%d" % _player.state)
		# with no stamina an attack must be refused outright
		_player.stamina = 1.0
		_press("attack")
		return
	if _phase_frame == 26:
		_release("attack")
		_ok("attack is refused without stamina", _player.state != Player.State.ATTACK,
				"state=%d" % _player.state)
		_ok("a refused attack does not go negative on stamina", _player.stamina >= 0.0,
				"stamina=%.1f" % _player.stamina)
		return
	if _phase_frame >= 28:
		_next()


func _phase_attack_hits() -> void:
	if _phase_frame == 0:
		_release_all()
		# park the player just inside reach of the first hollow
		var enemies := get_nodes_in_group("enemy")
		_hollow = enemies[0]
		_player.global_position = _hollow.global_position - Vector2(20, 0)
		_player.velocity = Vector2.ZERO
		_player.facing = 1
		_player.stamina = Player.STAMINA_MAX
		_hollow_hp0 = _hollow.health
		return
	if _phase_frame == 3:
		_press("attack")
		return
	if _phase_frame == 5:
		_release("attack")
		return
	# the strike lands at ATTACK_HIT_AT = 0.15s -> ~9 frames after the press
	if _phase_frame >= 20:
		_ok("attack damages a hollow in reach",
				_hollow.health <= _hollow_hp0 - Player.ATTACK_DAMAGE + 0.01,
				"%.1f -> %.1f" % [_hollow_hp0, _hollow.health])
		_next()


func _phase_kill_and_reward() -> void:
	if _phase_frame == 0:
		_souls0 = _player.souls
		return
	# beat it down directly: the hitbox is already covered by the previous phase
	if _phase_frame == 2:
		if is_instance_valid(_hollow):
			_hollow.take_damage(1000.0, _player.global_position)
		return
	if _phase_frame >= 6:
		_ok("killing a hollow awards souls",
				_player.souls >= _souls0 + Hollow.SOULS_REWARD,
				"%d -> %d" % [_souls0, _player.souls])
		_ok("dead hollow stops fighting",
				not is_instance_valid(_hollow) or _hollow.state == Hollow.State.DEAD)
		_next()


func _phase_roll_iframes() -> void:
	if _phase_frame == 0:
		# somewhere quiet, so a hollow cannot interrupt the roll
		_player.global_position = Vector2(72.0, _main.floor_top)
		_player.velocity = Vector2.ZERO
		_player.health = Player.HEALTH_MAX
		_player._invuln = 0.0
		_player.stamina = Player.STAMINA_MAX
		_stamina0 = _player.stamina
		return
	if _phase_frame == 6:
		_x0 = _player.global_position.x
		_press("dodge")
		return
	if _phase_frame == 8:
		_release("dodge")
		_ok("dodge enters ROLL state", _player.state == Player.State.ROLL,
				"state=%d" % _player.state)
		_ok("dodge drains stamina",
				_player.stamina <= _stamina0 - Player.ROLL_COST + 0.01,
				"%.1f -> %.1f" % [_stamina0, _player.stamina])
		return
	if _phase_frame > 8 and _phase_frame < 34:
		# sample invulnerability across the roll
		if _player.state == Player.State.ROLL:
			if _player.is_invulnerable():
				_iframe_seen = true
			elif _iframe_seen:
				_iframe_gap_seen = true      # i-frames ended before the roll did
		return
	if _phase_frame >= 34:
		_ok("roll grants i-frames", _iframe_seen)
		_ok("i-frames end before the roll does (punishable recovery)", _iframe_gap_seen)
		_ok("roll covers ground", absf(_player.global_position.x - _x0) > 20.0,
				"moved %.1f px" % absf(_player.global_position.x - _x0))
		_ok("roll ends", _player.state != Player.State.ROLL)
		_next()


## The core soulslike exchange: the hollow must notice the player, commit to a
## readable wind-up, then land a strike that actually costs health.
func _phase_hollow_attack_loop() -> void:
	if _phase_frame == 0:
		_hollow = null
		for e in get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.state != Hollow.State.DEAD:
				_hollow = e
				break
		_ok("a live hollow remains to fight", _hollow != null)
		if _hollow == null:
			_next()
			return
		# stand just inside its reach, facing it, and do nothing
		_player.global_position = _hollow.global_position - Vector2(24, 0)
		_player.velocity = Vector2.ZERO
		_player.health = Player.HEALTH_MAX
		_player._invuln = 0.0
		_hollow_hp0 = _player.health
		return
	if _phase_frame < 4:
		return
	if _phase_frame < 100:
		if _hollow.state == Hollow.State.WINDUP:
			_windup_seen = true
		elif _hollow.state == Hollow.State.STRIKE:
			_strike_seen = true
		return
	_ok("hollow telegraphs before striking", _windup_seen)
	_ok("hollow follows through with a strike", _strike_seen)
	_ok("a landed hollow strike costs the player health",
			_player.health < _hollow_hp0,
			"health %.1f -> %.1f" % [_hollow_hp0, _player.health])
	_ok("the telegraph is long enough to react to",
			Hollow.WINDUP_TIME >= 0.35,
			"windup=%.2fs" % Hollow.WINDUP_TIME)
	_next()


func _phase_damage_and_death() -> void:
	if _phase_frame == 0:
		_player.died.connect(func() -> void: _died = true)
		_player.health = Player.HEALTH_MAX
		_player._invuln = 0.0
		_player.take_damage(30.0, _player.global_position + Vector2(20, 0))
		return
	if _phase_frame == 1:
		_ok("taking damage reduces health",
				is_equal_approx(_player.health, Player.HEALTH_MAX - 30.0),
				"health=%.1f" % _player.health)
		_ok("a hit grants brief invulnerability", _player.is_invulnerable())
		# a second hit during i-frames must be ignored
		_player.take_damage(30.0, _player.global_position + Vector2(20, 0))
		return
	if _phase_frame == 2:
		_ok("i-frames block a follow-up hit",
				is_equal_approx(_player.health, Player.HEALTH_MAX - 30.0),
				"health=%.1f" % _player.health)
		_player._invuln = 0.0
		_player.take_damage(1000.0, _player.global_position + Vector2(20, 0))
		return
	if _phase_frame >= 4:
		_ok("lethal damage kills the player", _player.state == Player.State.DEAD)
		_ok("death signal fires", _died)
		_ok("health floors at zero", _player.health >= 0.0, "health=%.1f" % _player.health)
		_next()


## Dying must hand the player a fresh run: Main waits 2.8s, then reloads the
## scene. This is the loop every player hits, so it has to survive the round trip.
func _phase_respawn() -> void:
	if _phase_frame == 0:
		_old_main = _main
		return
	# 2.8s at 60 Hz is ~168 physics frames; give the reload room to land
	if _phase_frame < 220:
		return
	var fresh: Node = current_scene
	_ok("the scene reloads after death", is_instance_valid(fresh) and fresh != _old_main)
	if not is_instance_valid(fresh) or fresh == _old_main:
		_next()
		return
	_ok("the reloaded scene spawns a fresh player",
			fresh.player != null and is_instance_valid(fresh.player))
	if fresh.player != null and is_instance_valid(fresh.player):
		_ok("the respawned player is back at full health",
				is_equal_approx(fresh.player.health, Player.HEALTH_MAX),
				"health=%.1f" % fresh.player.health)
		_ok("the respawned player is alive", fresh.player.state != Player.State.DEAD)
	_ok("the reloaded scene repopulates its enemies",
			get_nodes_in_group("enemy").size() == 2,
			"got %d" % get_nodes_in_group("enemy").size())
	_next()


func _finish() -> bool:
	print("")
	if _fails.is_empty():
		print("PASS — %d checks" % _checks)
		quit(0)
	else:
		print("FAIL — %d of %d checks failed:" % [_fails.size(), _checks])
		for f in _fails:
			print("   • %s" % f)
		quit(1)
	return true
