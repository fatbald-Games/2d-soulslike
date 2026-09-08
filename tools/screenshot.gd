extends SceneTree
## Captures real in-engine screenshots into tools/shots/.
##
##   xvfb-run -a godot --path . --script res://tools/screenshot.gd
##
## Needs an actual display (headless draws nothing), so it runs under Xvfb in
## CI. Walks the same path a player takes and grabs a frame at each stop, which
## is the only way to confirm the UI really looks the way it was designed
## instead of the way the Python mock-up predicted.

const DIR := "res://tools/shots/"

var _f := 0
var _scene: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_scene = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	print("— capturing screenshots —")


func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _grab(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := DIR + name + ".png"
	var err := img.save_png(path)
	print("  %s  %s  %s" % ["ok " if err == OK else "FAIL", name, img.get_size()])


func _find(node: Node, script_name: String) -> Node:
	var s: Script = node.get_script()
	if s != null and s.resource_path.get_file() == script_name + ".gd":
		return node
	for c in node.get_children():
		var hit := _find(c, script_name)
		if hit != null:
			return hit
	return null


func _process(_delta: float) -> bool:
	_f += 1
	match _f:
		45:
			_grab("01_title")
		48:
			(_find(_scene, "MenuList") as MenuList).index = 1     # CONTROLS
			_key(KEY_ENTER)
		56:
			_grab("02_controls")
		58:
			_key(KEY_ESCAPE)
		62:
			(_find(_scene, "MenuList") as MenuList).index = 2     # OPTIONS
			_key(KEY_ENTER)
		70:
			_grab("08_options")
		72:
			_key(KEY_ESCAPE)
		76:
			(_find(_scene, "MenuList") as MenuList).index = 0     # NEW GAME
			_key(KEY_ENTER)
		120:
			# take a couple of hits first, so the health bar and its ghost show
			current_scene.player.take_damage(34.0, Vector2(400, 0))
			current_scene.player.add_souls(1240)
		124:
			current_scene.player.stamina = 46.0
			current_scene.player.stamina_changed.emit(46.0, 100.0)
		126:
			current_scene.player.flask = 2
			current_scene.player.flask_changed.emit(2, Player.FLASK_MAX)
		130:
			_grab("03_hud")
		134:
			_key(KEY_ESCAPE)
		142:
			_grab("04_pause")
		146:
			_key(KEY_ESCAPE)
		150:
			_warp(64, 51)         # the descent shaft, ladder and ledges
		174:
			_grab("05_descent")
		178:
			_warp(112, 76)        # the ossuary, under its stepped beams
		202:
			_grab("06_ossuary")
		206:
			_warp(200, 92)        # the flooded cistern
		230:
			_grab("10_cistern")
		234:
			_warp(272, 108)       # the rootworks, lit by fungus
		258:
			_grab("11_rootworks")
		262:
			_warp(330, 124)       # the ember forge
		286:
			_grab("12_forge")
		290:
			_warp(352, 84)        # the frozen vault
		314:
			_grab("13_vault")
		318:
			_warp(200, 26)        # the ramparts, high above everything
		342:
			_grab("07_ramparts")
		346:
			# stand at the gate bonfire so the REST prompt shows
			_warp(9, 46)
		370:
			_grab("09_bonfire")
		374:
			# a few levels bought, so the bars show their growth
			Run.souls = 4000
			Run.stats[Run.VIGOR] = 4
			Run.stats[Run.ENDURANCE] = 3
			Run.stats[Run.AGILITY] = 2
			current_scene.player.apply_stats(true)
			current_scene.hud.refresh_stats()
			current_scene.hud.set_souls(Run.souls)
			Run.seen_areas["THE ASHEN GATE"] = true
			Run.seen_areas["THE OSSUARY"] = true
			Run.seen_areas["THE FLOODED CISTERN"] = true
			Run.read_runes["1"] = true
			Run.read_runes["2"] = true
			Run.slain = 17
		378:
			# hold the ACTION across a frame: pressing and releasing a raw key in
			# the same frame can slip past is_action_just_pressed entirely
			Input.action_press("interact")
		381:
			Input.action_release("interact")
		386:
			_key(KEY_DOWN)
		390:
			_key(KEY_ENTER)                # LEVEL UP
		398:
			_grab("14_levelup")
		402:
			_key(KEY_ESCAPE)               # back to the bonfire's own menu
		406:
			# three weapons found, so the armoury shows both halves of it:
			# what is in hand, and what is still out there
			Run.weapons["axe"] = true
			Run.weapons["spear"] = true
			Run.weapons["bow"] = true
			current_scene.bonfire_menu._refresh_armoury()
			_key(KEY_DOWN)                 # LEVEL UP -> ARMOURY
		410:
			_key(KEY_ENTER)
		418:
			_grab("16_armoury")
		422:
			_key(KEY_ESCAPE)
		426:
			_key(KEY_ESCAPE)
		432:
			_key(KEY_ESCAPE)               # pause
		438:
			_key(KEY_DOWN)
		442:
			_key(KEY_ENTER)                # PROGRESS
		450:
			_grab("15_progress")
		454:
			_key(KEY_ESCAPE)
		458:
			_key(KEY_ESCAPE)
		462:
			# the great axe still lying in the ossuary, waiting to be taken
			_warp(94, 76)
		486:
			_grab("17_weapon_pickup")
		490:
			# and the same knight with the shield up, guarding
			Run.weapons["shield"] = true
			current_scene.player.equip(Weapons.SHIELD)
			_warp(112, 76)
		500:
			Input.action_press("block")
		512:
			_grab("18_guard")
		516:
			Input.action_release("block")
			current_scene.player.equip(Weapons.AXE)
		528:
			_grab("19_great_axe")
		532:
			print("done.")
			quit(0)
			return true
	return false


## Drop the knight at a tile so a shot can be taken somewhere specific.
func _warp(tx: int, ty: int) -> void:
	var p = current_scene.player
	p.global_position = Vector2((tx + 0.5) * LevelMap.TILE,
			float((ty + 1) * LevelMap.TILE))
	p.velocity = Vector2.ZERO
	# parked next to a hollow for twenty-odd frames per shot, he was arriving at
	# the last few screens already dead
	p.health = p.health_max
	p.stamina = p.stamina_max
	p.health_changed.emit(p.health, p.health_max)
	for c in p.get_children():
		if c is Camera2D:
			(c as Camera2D).reset_smoothing()   # otherwise the shot is mid-pan
