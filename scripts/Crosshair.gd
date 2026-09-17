class_name Crosshair
extends CanvasLayer
## The pixel cursor.
##
## The system pointer is a smooth 32-pixel arrow drawn on top of a game whose
## smallest meaningful unit is one fat square pixel — the single thing on screen
## that is not made of the same stuff as everything else. So while the knight is
## on his feet the system cursor is hidden and this is drawn in its place, at
## the viewport's own resolution.
##
## It is a CanvasLayer of its own rather than a node in the world for one
## concrete reason: the dungeon is lit, and the world canvas carries a
## CanvasModulate that takes it down to a fifth of its brightness. A crosshair
## in there is drawn perfectly correctly and is, in a dark room, black on black.
##
## It appears only once the mouse has actually been moved (Player.aim_active),
## which is what keeps a pad player from being handed a crosshair he never asked
## for, and it steps aside — pointer back — the moment a menu is open, so the
## menus can still be used.

const TEX := "res://assets/sprites/crosshair.png"

var player: Player = null

var _sprite: Sprite2D
var _cursor_hidden := false


func _ready() -> void:
	# it keeps running while the tree is paused: otherwise opening the pause
	# menu would leave a stale crosshair frozen on the last frame of play
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15                       # over the HUD, under the pause screen
	_sprite = Sprite2D.new()
	_sprite.texture = load(TEX) as Texture2D
	_sprite.centered = true
	add_child(_sprite)
	visible = false


func _process(_delta: float) -> void:
	var want := wanted()
	visible = want
	if want:
		# snapped to whole viewport pixels, or the crosshair lands between two
		# of the screen's fat pixels and shimmers
		_sprite.position = get_viewport().get_mouse_position().round()
	_hide_system_cursor(want)


## Drawn only while he is actually playing. Paused, dead, aiming switched off in
## OPTIONS, or no mouse touched yet — every one of those wants the ordinary
## pointer back.
func wanted() -> bool:
	if not Settings.mouse_aim:
		return false
	if is_inside_tree() and get_tree().paused:
		return false
	return player != null and is_instance_valid(player) \
			and player.state != Player.State.DEAD and player.aim_active()


## Swapping the mouse mode every frame would fight the window manager, so it is
## only touched on the change. Headless has no cursor to hide and complains if
## asked, and the test suites run headless.
func _hide_system_cursor(hide_it: bool) -> void:
	if hide_it == _cursor_hidden:
		return
	_cursor_hidden = hide_it
	if DisplayServer.get_name() == "headless":
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if hide_it
			else Input.MOUSE_MODE_VISIBLE)


## Leaving the scene — quitting to the title screen, or dying into a reload —
## must not leave the player without a pointer.
func _exit_tree() -> void:
	_hide_system_cursor(false)
