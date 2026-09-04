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
			_warp(56, 50)         # the descent shaft, ladder and ledges
		174:
			_grab("05_descent")
		178:
			_warp(96, 57)         # the ossuary, under its stepped beams
		202:
			_grab("06_ossuary")
		206:
			_warp(120, 27)        # the ramparts, high above everything
		230:
			_grab("07_ramparts")
		234:
			# stand at the gate bonfire so the REST prompt shows
			_warp(9, 45)
		258:
			_grab("09_bonfire")
		262:
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
	for c in p.get_children():
		if c is Camera2D:
			(c as Camera2D).reset_smoothing()   # otherwise the shot is mid-pan
