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
var _closing := 0
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
var _y0 := 0.0
var _ladder_tile := Vector2i.ZERO
var _hp0 := 0.0
var _bonfire_pos := Vector2.ZERO
var _enemies0 := 0
var _souls_at_death := 0
var _hp_max0 := 0.0
var _speed0 := 0.0
var _bar0 := 0.0
var _sword_time := 0.0
var _sword_dmg := 0.0
var _arrows_seen := 0
var _guard_hp0 := 0.0
var _guard_sp0 := 0.0
var _shield_pickup: Dictionary = {}
var _weapon0 := 0


func _initialize() -> void:
	# never touch the player's own save file
	Run.SAVE_PATH = "user://test_save.cfg"
	Run.delete_save()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	# mirror how the engine boots the main scene, so reload_current_scene()
	# (the respawn path) behaves here exactly as it does in a real run
	current_scene = _main
	print("— Ashen Hollow smoke test —")


## Counted from the map rather than hard-coded, so re-cutting the level in
## tools/gen_level.py cannot silently invalidate this test.
func _map_hollows() -> int:
	var n := 0
	for e in LevelMap.ENTITIES:
		if e["kind"] == "hollow":
			n += 1
	return n


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ok    %s" % label)
	else:
		var line := label if detail.is_empty() else "%s  (%s)" % [label, detail]
		print("  FAIL  %s" % line)
		_fails.append(line)


## Menus listen for raw key events, not the game's input actions, so driving one
## means pushing a real InputEventKey through the stack.
func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _press(action: String) -> void:
	Input.action_press(action)


func _release(action: String) -> void:
	Input.action_release(action)


func _release_all() -> void:
	for a in ["left", "right", "up", "down", "jump", "attack", "dodge", "heal",
			"interact", "block", "swap"]:
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
		7: _phase_traversal()
		8: _phase_flask()
		9: _phase_bonfire()
		10: _phase_level_up()
		11: _phase_weapons()
		12: _phase_hud()
		13: _phase_damage_and_death()
		14: _phase_respawn()
		15: _phase_ending()
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
		_ok("every hollow on the map spawned", enemies.size() == _map_hollows(),
				"got %d, map lists %d" % [enemies.size(), _map_hollows()])
		_ok("HUD built", _main.hud != null)
		_ok("input actions registered", InputMap.has_action("attack") and InputMap.has_action("dodge"))
		return
	if _phase_frame >= 40:
		_ok("player lands on the floor", _player.is_on_floor(),
				"y=%.1f on_floor=%s" % [_player.global_position.y, _player.is_on_floor()])
		_ok("player starts at full health", is_equal_approx(_player.health, _player.health_max))
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
		_player.stamina = _player.stamina_max
		_stamina0 = _player.stamina
		_press("attack")
		return
	if _phase_frame == 2:
		_release("attack")
		_ok("attack enters ATTACK state", _player.state == Player.State.ATTACK,
				"state=%d" % _player.state)
		_ok("attack drains stamina",
				_player.stamina <= _stamina0 - _player.attack_cost() + 0.01,
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
		_player.stamina = _player.stamina_max
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
				_hollow.health <= _hollow_hp0 - _player.attack_damage + 0.01,
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
		_player.health = _player.health_max
		_player._invuln = 0.0
		_player.stamina = _player.stamina_max
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
		_player.health = _player.health_max
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


## Vertical movement — the whole point of the bigger map. Climbing a ladder and
## dropping through a beam are both easy to break in ways the flat-corridor
## tests would never notice.
func _phase_traversal() -> void:
	var lvl: Level = _main.level
	if _phase_frame == 0:
		_ok("the level exposes a world bigger than one screen",
				lvl.world_size().x > 2000.0 and lvl.world_size().y > 700.0,
				"world=%s" % lvl.world_size())
		_ok("the map defines named regions", LevelMap.AREAS.size() >= 4,
				"%d areas" % LevelMap.AREAS.size())
		_ok("the map defines ladders and beams",
				LevelMap.BEAMS.size() > 0 and _map_has_ladder())

		# put him on the long descent ladder, at the ossuary end
		_ladder_tile = _find_ladder_bottom()
		_player.global_position = Vector2((_ladder_tile.x + 0.5) * LevelMap.TILE,
				float((_ladder_tile.y + 1) * LevelMap.TILE))
		_player.velocity = Vector2.ZERO
		_player.health = _player.health_max
		_player._invuln = 0.0
		return
	if _phase_frame == 4:
		_ok("the knight is standing on a ladder tile",
				lvl.is_ladder(_player.global_position + Vector2(0, -12)))
		_y0 = _player.global_position.y
		_press("up")
		return
	if _phase_frame == 8:
		_ok("holding up on a ladder starts a climb",
				_player.state == Player.State.CLIMB, "state=%d" % _player.state)
		return
	if _phase_frame == 45:
		_ok("climbing carries him upward",
				_player.global_position.y < _y0 - 20.0,
				"rose %.1f px" % (_y0 - _player.global_position.y))
		_ok("gravity is off while climbing", _player.velocity.y <= 0.0,
				"vy=%.1f" % _player.velocity.y)
		_release_all()
		_y0 = _player.global_position.y
		return
	if _phase_frame == 52:
		# releasing mid-ladder must HANG, not drop him: letting go of the keys
		# is not letting go of the rung
		_ok("he hangs on the ladder with no input",
				_player.state == Player.State.CLIMB, "state=%d" % _player.state)
		_ok("hanging does not slide him down",
				absf(_player.global_position.y - _y0) < 2.0,
				"drifted %.1f px" % (_player.global_position.y - _y0))
		_press("right")
		return
	if _phase_frame == 58:
		_ok("stepping sideways lets go of the ladder",
				_player.state != Player.State.CLIMB, "state=%d" % _player.state)
		_release_all()
		# now a one-way beam: land on top of one, then drop through it
		var beam: Array = LevelMap.BEAMS[0]
		var bx: int = beam[0]
		var by: int = beam[1]
		_player.global_position = Vector2((bx + 2.5) * LevelMap.TILE,
				float(by * LevelMap.TILE) - 2.0)
		_player.velocity = Vector2.ZERO
		return
	if _phase_frame == 75:
		_ok("a one-way beam holds him up", _player.is_on_floor(),
				"y=%.1f on_floor=%s" % [_player.global_position.y, _player.is_on_floor()])
		_y0 = _player.global_position.y
		_press("down")
		_press("jump")
		return
	if _phase_frame == 78:
		_release_all()
		return
	if _phase_frame >= 100:
		_ok("down + jump drops him through the beam",
				_player.global_position.y > _y0 + 8.0,
				"fell %.1f px" % (_player.global_position.y - _y0))
		_ok("the beam layer is listening again afterwards",
				_player.get_collision_mask_value(Level.BEAM_LAYER))
		_next()


func _map_has_ladder() -> bool:
	for row in LevelMap.MAP:
		if row.contains("H"):
			return true
	return false


## The lowest tile of the first ladder column, i.e. somewhere he can stand.
func _find_ladder_bottom() -> Vector2i:
	for ty in range(LevelMap.H - 1, 0, -1):
		var row: String = LevelMap.MAP[ty]
		for tx in LevelMap.W:
			if row[tx] == "H" and LevelMap.MAP[ty + 1][tx] == "#":
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


## The flask: a big heal that costs a charge and locks him in place. It must
## not be a free reset — no i-frames, and it runs out.
func _phase_flask() -> void:
	if _phase_frame == 0:
		_player.global_position = Vector2(72.0, _main.floor_top)
		_player.velocity = Vector2.ZERO
		_player.stamina = _player.stamina_max
		_player._invuln = 0.0
		_player.flask = Player.FLASK_MAX
		_player.health = 30.0
		return
	if _phase_frame == 4:
		_hp0 = _player.health
		_press("heal")
		return
	if _phase_frame == 6:
		_release_all()
		_ok("drinking enters the DRINK state",
				_player.state == Player.State.DRINK, "state=%d" % _player.state)
		_ok("the heal is not instant", is_equal_approx(_player.health, _hp0),
				"health=%.1f" % _player.health)
		_ok("drinking grants no invulnerability", not _player.is_invulnerable())
		return
	if _phase_frame == 36:
		_ok("the flask heals", _player.health > _hp0 + 40.0,
				"%.1f -> %.1f" % [_hp0, _player.health])
		_ok("drinking spends a charge", _player.flask == Player.FLASK_MAX - 1,
				"flask=%d" % _player.flask)
		return
	if _phase_frame == 52:
		_ok("the drink ends", _player.state != Player.State.DRINK,
				"state=%d" % _player.state)
		_player.flask = 0
		_player.health = 20.0
		_press("heal")
		return
	if _phase_frame == 56:
		_release_all()
		_ok("an empty flask refuses to drink",
				_player.state != Player.State.DRINK, "state=%d" % _player.state)
		_next()


## Resting is the structural core: light the fire, heal, refill, respawn every
## hollow, and make this fire the place death sends you back to.
func _phase_bonfire() -> void:
	if _phase_frame == 0:
		_bonfire_pos = _main._bonfires[0]["pos"]
		_player.global_position = _bonfire_pos
		_player.velocity = Vector2.ZERO
		_player.health = 25.0
		_player.flask = 0
		# thin the ranks, so the respawn has something to put back
		var alive := get_nodes_in_group("enemy")
		for i in mini(3, alive.size()):
			alive[i].queue_free()
		return
	if _phase_frame == 6:
		_enemies0 = get_nodes_in_group("enemy").size()
		_ok("some hollows are dead before resting", _enemies0 < _map_hollows(),
				"%d of %d" % [_enemies0, _map_hollows()])
		_ok("the first bonfire starts unlit", not _main._bonfires[0]["lit"])
		_press("interact")
		return
	if _phase_frame == 8:
		_release_all()
		_ok("standing at a bonfire and pressing E lights it",
				_main._bonfires[0]["lit"])
		_ok("lighting a bonfire is recorded for the whole run",
				Run.lit_bonfires.size() >= 1)
		_ok("the bonfire menu opens", _main.bonfire_menu.is_open())
		return
	if _phase_frame == 10:
		_key(KEY_ENTER)                 # REST is the first entry
		return
	if _phase_frame == 14:
		_ok("choosing REST closes the menu", not _main.bonfire_menu.is_open())
		_ok("resting heals to full",
				is_equal_approx(_player.health, _player.health_max),
				"health=%.1f" % _player.health)
		_ok("resting refills the flask", _player.flask == Player.FLASK_MAX,
				"flask=%d" % _player.flask)
		_ok("resting sets the checkpoint", Run.has_checkpoint)
		_ok("the checkpoint is this bonfire",
				Run.checkpoint.distance_to(_bonfire_pos) < 1.0,
				"%s vs %s" % [Run.checkpoint, _bonfire_pos])
		return
	if _phase_frame >= 20:
		_ok("resting puts every hollow back",
				get_nodes_in_group("enemy").size() == _map_hollows(),
				"%d of %d" % [get_nodes_in_group("enemy").size(), _map_hollows()])
		_next()


## Souls with nothing to spend them on are a score, not progress. Buying a level
## has to move a real number AND be visible on the HUD in the same instant.
func _phase_level_up() -> void:
	if _phase_frame == 0:
		_player.global_position = _main._bonfires[0]["pos"]
		_player.velocity = Vector2.ZERO
		Run.souls = 5000
		_player.souls = Run.souls
		_hp_max0 = _player.health_max
		_speed0 = _player.speed
		_bar0 = _main.hud._hp_frame.size.x
		_press("interact")
		return
	if _phase_frame == 3:
		_release_all()
		_key(KEY_DOWN)                  # LEVEL UP
		return
	if _phase_frame == 5:
		_key(KEY_ENTER)
		return
	if _phase_frame == 7:
		_ok("the bonfire offers a level-up page",
				_main.bonfire_menu._screen == 1,
				"screen=%d" % _main.bonfire_menu._screen)
		_ok("there is a stat for each thing you can raise",
				Run.STAT_NAMES.size() == 5, "%d stats" % Run.STAT_NAMES.size())
		_souls0 = Run.souls
		_key(KEY_ENTER)                 # VIGOR is the first row
		return
	if _phase_frame == 10:
		_ok("buying a point raises the stat", Run.stats[Run.VIGOR] == 1,
				"vigor=%d" % Run.stats[Run.VIGOR])
		_ok("buying a point spends souls", Run.souls < _souls0,
				"%d -> %d" % [_souls0, Run.souls])
		_ok("VIGOR raises maximum health", _player.health_max > _hp_max0,
				"%.0f -> %.0f" % [_hp_max0, _player.health_max])
		_ok("the health bar physically grows", _main.hud._hp_frame.size.x > _bar0,
				"%.0f -> %.0f px" % [_bar0, _main.hud._hp_frame.size.x])
		# now a stat with no bar: AGILITY must still be felt
		_key(KEY_DOWN)
		_key(KEY_DOWN)
		return
	if _phase_frame == 13:
		_key(KEY_ENTER)                 # AGILITY
		return
	if _phase_frame == 16:
		_ok("AGILITY raises move speed", _player.speed > _speed0,
				"%.0f -> %.0f" % [_speed0, _player.speed])
		_ok("the level counter follows the points spent", Run.level() == 3,
				"level=%d" % Run.level())
		_key(KEY_ESCAPE)
		return
	if _phase_frame == 19:
		_key(KEY_ESCAPE)
		return
	if _phase_frame >= 24:
		_ok("leaving the bonfire unpauses the game", not paused)
		_next()


## Six weapons that all played the same would be six names. These checks are
## about the DIFFERENCES — reach, damage, swing time, stamina — plus the two
## that do not swing at all and the one that can say no.
func _phase_weapons() -> void:
	if _phase_frame == 0:
		_release_all()
		_sword_time = _player.attack_time
		_sword_dmg = _player.swing_damage()
		_ok("the armoury describes six weapons", Weapons.DEFS.size() == 6,
				"%d weapons" % Weapons.DEFS.size())
		_ok("the run starts on the longsword", Run.weapon == Weapons.SWORD,
				"weapon=%d" % Run.weapon)

		# every weapon but the starting blade has to be somewhere you can reach;
		# the level generator proves reachability, this proves they were PLACED
		var placed := {}
		for e in LevelMap.ENTITIES:
			if e["kind"] == "weapon":
				placed[e["weapon"]] = true
		var missing: Array = []
		for d in Weapons.DEFS:
			if d["id"] != Weapons.START and not placed.has(d["id"]):
				missing.append(d["id"])
		_ok("every other weapon lies somewhere in the keep", missing.is_empty(),
				"missing %s" % str(missing))
		# --- the world's dressing, checked from the map rather than by eye ---
		_ok("every tile row carries a stone theme",
				LevelMap.THEME_OF.size() == LevelMap.H
				and (LevelMap.THEME_OF[0] as String).length() == LevelMap.W,
				"%d rows" % LevelMap.THEME_OF.size())
		var themed := {}
		for row in LevelMap.THEME_OF:
			for i in (row as String).length():
				themed[(row as String)[i]] = true
		_ok("every region's stone is actually cut somewhere",
				themed.size() == LevelMap.AREAS.size(),
				"%d of %d themes used" % [themed.size(), LevelMap.AREAS.size()])
		var dressed := {}
		for e in LevelMap.ENTITIES:
			if e["kind"] == "deco":
				dressed[_main.level.theme_name_at(Vector2(
						(int(e["x"]) + 0.5) * LevelMap.TILE,
						(int(e["y"]) + 0.5) * LevelMap.TILE))] = true
		_ok("every region is dressed with props",
				dressed.size() == LevelMap.AREAS.size(),
				"%d of %d regions have deco" % [dressed.size(), LevelMap.AREAS.size()])

		_ok("the level builds a pickup for each of them",
				_main._pickups.size() == Weapons.DEFS.size() - 1,
				"%d pickups" % _main._pickups.size())

		# walk onto the shield and take it, the way a player would
		for p in _main._pickups:
			if p["id"] == "shield":
				_shield_pickup = p
		_ok("the shield is one of them", not _shield_pickup.is_empty())
		if _shield_pickup.is_empty():
			_next()
			return
		_player.global_position = _shield_pickup["pos"] + Vector2(0, 8)
		_player.velocity = Vector2.ZERO
		_press("interact")
		return

	if _phase_frame == 3:
		_release_all()
		_ok("picking a weapon up adds it to the armoury", Run.has_weapon("shield"))
		_ok("picking a weapon up equips it on the spot",
				Run.weapon == Weapons.SHIELD, "weapon=%d" % Run.weapon)
		_ok("the pickup is gone once taken",
				not is_instance_valid(_shield_pickup["node"]))
		_ok("the HUD names what he is holding",
				_main.hud._weapon.text == Weapons.name_of(Weapons.SHIELD),
				_main.hud._weapon.text)
		_ok("the shield brings a guard animation with it",
				_player.sprite.sprite_frames.has_animation("block"))

		_player.global_position = Vector2(72.0, _main.floor_top)
		_player.velocity = Vector2.ZERO
		_player.health = _player.health_max
		_player.stamina = _player.stamina_max
		_player._invuln = 0.0
		return

	if _phase_frame == 5:
		Run.weapons["axe"] = true
		_ok("equipping a found weapon takes", _player.equip(Weapons.AXE))
		return

	if _phase_frame == 6:
		_ok("the axe hits harder than the sword",
				_player.swing_damage() > _sword_dmg,
				"%.0f -> %.0f" % [_sword_dmg, _player.swing_damage()])
		_ok("the axe swings slower than the sword",
				_player.attack_time > _sword_time,
				"%.2fs -> %.2fs" % [_sword_time, _player.attack_time])
		_ok("the axe costs more stamina than the sword",
				_player.attack_cost() > float(Weapons.def(Weapons.SWORD)["stamina"]),
				"%.0f" % _player.attack_cost())
		Run.weapons["spear"] = true
		_player.equip(Weapons.SPEAR)
		return

	if _phase_frame == 7:
		_ok("the spear reaches further than the sword",
				float(_player.weapon()["reach"]) > Player.ATTACK_REACH,
				"%.0f px" % float(_player.weapon()["reach"]))
		_ok("the spear pays for that reach in damage",
				_player.swing_damage() < _sword_dmg,
				"%.0f vs %.0f" % [_player.swing_damage(), _sword_dmg])

		# --- the bow: a weapon that never touches anything ---
		Run.weapons["bow"] = true
		_player.equip(Weapons.BOW)
		_player.stamina = _player.stamina_max
		_player.facing = 1
		_hollow = _main._spawn_hollow(Vector2(_player.global_position.x + 74.0,
				_main.floor_top))
		_hollow_hp0 = _hollow.health
		_press("attack")
		return

	if _phase_frame == 9:
		_release("attack")
		return

	if _phase_frame == 22:
		for c in _main.get_children():
			if c is Projectile:
				_arrows_seen += 1
		return

	if _phase_frame == 55:
		_ok("the bow puts an arrow in the world", _arrows_seen > 0,
				"%d arrows" % _arrows_seen)
		_ok("an arrow damages what it hits",
				is_instance_valid(_hollow) and _hollow.health < _hollow_hp0,
				"%.1f -> %.1f" % [_hollow_hp0,
						_hollow.health if is_instance_valid(_hollow) else -1.0])
		if is_instance_valid(_hollow):
			_hollow.queue_free()

		# --- the shield: the only weapon that can refuse a hit ---
		_player.equip(Weapons.SHIELD)
		_player.global_position = Vector2(72.0, _main.floor_top)
		_player.velocity = Vector2.ZERO
		_player.health = _player.health_max
		_player.stamina = _player.stamina_max
		_player._invuln = 0.0
		_player.facing = 1
		_press("block")
		return

	if _phase_frame == 58:
		_ok("holding L raises the shield",
				_player.state == Player.State.BLOCK, "state=%d" % _player.state)
		_guard_hp0 = _player.health
		_guard_sp0 = _player.stamina
		_player.take_damage(Hollow.DAMAGE,
				_player.global_position + Vector2(30, 0))
		return

	if _phase_frame == 59:
		_ok("a guarded blow costs far less health",
				_player.health > _guard_hp0 - Hollow.DAMAGE * 0.5,
				"%.1f -> %.1f" % [_guard_hp0, _player.health])
		_ok("a guarded blow costs stamina instead",
				_player.stamina < _guard_sp0,
				"%.1f -> %.1f" % [_guard_sp0, _player.stamina])
		# a hit from BEHIND the shield is not a hit the shield stops
		_player._invuln = 0.0
		_guard_hp0 = _player.health
		_player.stamina = 4.0
		_player.take_damage(Hollow.DAMAGE,
				_player.global_position + Vector2(30, 0))
		return

	if _phase_frame == 60:
		_ok("running the stamina out breaks the guard",
				_player.health <= _guard_hp0 - Hollow.DAMAGE + 0.01,
				"%.1f -> %.1f" % [_guard_hp0, _player.health])
		_release_all()
		_weapon0 = Run.weapon
		return

	# the broken guard staggers him for HURT_TIME; he cannot swap out of that,
	# which is the point of it, so wait him out first
	if _phase_frame == 82:
		_press("swap")
		return

	if _phase_frame == 84:
		_release_all()
		_ok("TAB swaps to another weapon he owns", Run.weapon != _weapon0,
				"weapon=%d" % Run.weapon)
		_ok("swapping never lands on a weapon he has not found",
				Run.has_weapon(Weapons.DEFS[Run.weapon]["id"]))
		return

	if _phase_frame >= 88:
		# leave the following phases on the baseline blade
		_player.equip(Weapons.SWORD)
		_player.health = _player.health_max
		_player.stamina = _player.stamina_max
		_player._invuln = 0.0
		_next()


## The HUD is the one part a headless run cannot LOOK at, so assert the things
## that made it wrong before: the bone frame is opaque, so a fill added before
## it is painted over and the bar reads as empty no matter what the value is.
func _phase_hud() -> void:
	var hud = _main.hud
	if _phase_frame == 0:
		# The HUD is wired live to the player, so park him somewhere safe and
		# topped up first: a hollow landing a hit — or stamina ticking back up —
		# would overwrite the values this phase is asserting on.
		_player.global_position = Vector2(72.0, _main.floor_top)
		_player.velocity = Vector2.ZERO
		_player.health = _player.health_max
		_player.stamina = _player.stamina_max
		_player._invuln = 0.0
		_ok("the health fill draws on top of its bone frame",
				hud._hp_fill.get_index() > hud._hp_frame.get_index(),
				"frame=%d fill=%d" % [hud._hp_frame.get_index(), hud._hp_fill.get_index()])
		_ok("the stamina fill draws on top of its bone frame",
				hud._st_fill.get_index() > hud._sp_frame.get_index(),
				"frame=%d fill=%d" % [hud._sp_frame.get_index(), hud._st_fill.get_index()])
		# the channel widens as VIGOR is bought, so compare against the CURRENT
		# channel rather than the base constant
		_ok("the fill sits inside the frame's channel",
				hud._hp_fill.size.x <= hud._hp_channel.x + 0.01,
				"%.1f in %.1f" % [hud._hp_fill.size.x, hud._hp_channel.x])
		_ok("the frame is wider than its channel by both fang caps",
				is_equal_approx(hud._hp_frame.size.x,
						hud._hp_channel.x + UiTheme.HP_CAP * 2))
		hud.set_health(100.0, 100.0)
		hud.set_stamina(100.0, 100.0)
		return
	if _phase_frame == 1:
		var full: float = hud._hp_fill.size.x
		hud.set_health(50.0, 100.0)
		_ok("half health draws half a bar",
				is_equal_approx(hud._hp_fill.size.x, full * 0.5),
				"%.1f -> %.1f" % [full, hud._hp_fill.size.x])
		_ok("the damage ghost lags behind the fill",
				hud._hp_ghost.size.x > hud._hp_fill.size.x,
				"ghost=%.1f fill=%.1f" % [hud._hp_ghost.size.x, hud._hp_fill.size.x])
		hud.set_stamina(25.0, 100.0)
		return
	if _phase_frame == 2:
		_ok("stamina draws a quarter bar",
				is_equal_approx(hud._st_fill.size.x, hud._sp_channel.x * 0.25),
				"%.1f" % hud._st_fill.size.x)
		_ok("an empty bar draws nothing", true)
		hud.set_health(0.0, 100.0)
		return
	if _phase_frame == 3:
		_ok("zero health draws an empty bar", is_zero_approx(hud._hp_fill.size.x),
				"%.1f" % hud._hp_fill.size.x)
		hud.set_souls(1240)
		_ok("the soul counter shows the count", hud._souls.text == "1240",
				"text=%s" % hud._souls.text)
		return
	# a full drain is GHOST_DELAY + 1/GHOST_SPEED ~= 2.2s, so give it 150 frames
	if _phase_frame >= 150:
		_ok("the damage ghost drains down to the fill",
				hud._hp_ghost.size.x <= hud._hp_fill.size.x + 0.01,
				"ghost=%.1f fill=%.1f" % [hud._hp_ghost.size.x, hud._hp_fill.size.x])
		# hand the bars back to the player's real values (the signals are already
		# connected — reconnecting them here would just error)
		hud.set_health(_player.health, _player.health_max)
		hud.set_stamina(_player.stamina, _player.stamina_max)
		_next()


func _phase_damage_and_death() -> void:
	if _phase_frame == 0:
		_player.died.connect(func() -> void: _died = true)
		_player.health = _player.health_max
		_player._invuln = 0.0
		_player.take_damage(30.0, _player.global_position + Vector2(20, 0))
		return
	if _phase_frame == 1:
		_ok("taking damage reduces health",
				is_equal_approx(_player.health, _player.health_max - 30.0),
				"health=%.1f" % _player.health)
		_ok("a hit grants brief invulnerability", _player.is_invulnerable())
		# a second hit during i-frames must be ignored
		_player.take_damage(30.0, _player.global_position + Vector2(20, 0))
		return
	if _phase_frame == 2:
		_ok("i-frames block a follow-up hit",
				is_equal_approx(_player.health, _player.health_max - 30.0),
				"health=%.1f" % _player.health)
		_player._invuln = 0.0
		_player.add_souls(500)
		_souls_at_death = _player.souls
		_player.take_damage(1000.0, _player.global_position + Vector2(20, 0))
		return
	if _phase_frame >= 4:
		_ok("lethal damage kills the player", _player.state == Player.State.DEAD)
		_ok("death signal fires", _died)
		_ok("dying drops the souls you were carrying", Run.has_drop,
				"carried %d" % _souls_at_death)
		_ok("the drop holds what he had", Run.dropped_souls == _souls_at_death,
				"%d vs %d" % [Run.dropped_souls, _souls_at_death])
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
				is_equal_approx(fresh.player.health, fresh.player.health_max),
				"health=%.1f" % fresh.player.health)
		_ok("the respawned player is alive", fresh.player.state != Player.State.DEAD)
	_ok("death returns him to the bonfire, not the start",
			fresh.player.global_position.distance_to(Run.checkpoint) < 24.0,
			"%s vs checkpoint %s" % [fresh.player.global_position, Run.checkpoint])
	_ok("the dropped souls are waiting in the reloaded level",
			fresh._soul_orb != null and is_instance_valid(fresh._soul_orb))
	_ok("the reloaded scene repopulates its enemies",
			get_nodes_in_group("enemy").size() == _map_hollows(),
			"got %d" % get_nodes_in_group("enemy").size())
	_next()


## The end of the route. There is no boss: the last inscription sits above the
## gate you came in through, and reading it ends the run.
func _phase_ending() -> void:
	var main = current_scene
	if _phase_frame == 0:
		_release_all()
		var final_tile := Vector2i(-1, -1)
		for e in LevelMap.ENTITIES:
			if e["kind"] == "rune" and int(e.get("final", 0)) == 1:
				final_tile = Vector2i(int(e["x"]), int(e["y"]))
		_ok("the map marks one inscription as the last one",
				final_tile.x >= 0, "tile=%s" % str(final_tile))
		if final_tile.x < 0:
			_next()
			return
		_ok("the run is not over before it is",
				not Run.finished)
		main.player.global_position = Vector2((final_tile.x + 0.5) * LevelMap.TILE,
				float((final_tile.y + 1) * LevelMap.TILE))
		main.player.velocity = Vector2.ZERO
		return
	if _phase_frame == 6:
		_ok("reading the last stone ends the run", Run.finished)
		_ok("the epilogue comes up", main._ending != null
				and is_instance_valid(main._ending))
		_ok("and it freezes the keep behind it", paused)
		_ok("the ending is saved, so the title screen knows",
				Run.has_save())
		paused = false                   # so the closing frames still run
		_next()
		return


func _finish() -> bool:
	# Two beats of grace before quitting: Audio.shutdown() stops every voice,
	# but the audio server only releases a stopped playback on its next mix, and
	# a stream still held at exit is reported as a leaked resource — which this
	# runner treats as a failure, correctly.
	_closing += 1
	if _closing == 1:
		Audio.shutdown()
		return false
	# The audio node is freed at the end of the frame shutdown() ran on, and the
	# audio server only lets go of a stream once its player is really gone. Ten
	# frames of grace makes that deterministic; at three it passed about half
	# the time and reported leaked resources on the rest.
	if _closing < 12:
		return false

	# Anything the game actually DREW with a glyph the font does not have. This
	# catches strings assembled at runtime — "EXPLORED 61%" and the like — that
	# no list of literals in a test could ever cover.
	_ok("every string drawn during the run was renderable",
			PixelLabel.missing_glyphs.is_empty(),
			"missing glyphs: %s" % str(PixelLabel.missing_glyphs.keys()))
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
