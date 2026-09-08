class_name Keys
extends RefCounted
## The control scheme, in one place.
##
## Every action the game listens for is declared here once, with a default key,
## an alternate, and a gamepad binding. Main asks for the InputMap, the options
## screen asks for the labels, and a rebind writes back here — so there is no
## second copy of the control list to fall out of date with the first.
##
## Only the PRIMARY key is rebindable. The alternates (arrow keys, the second
## dodge key) and the pad bindings stay put: they exist so the game is playable
## before anyone opens a menu, and letting them be reassigned turns a two-minute
## options screen into a support burden.

## id, the name shown to the player, the default key, an alternate, and how it
## sits on a controller. `axis` is [axis, direction] for stick movement.
const ACTIONS := [
	{"id": "left", "name": "MOVE LEFT", "key": KEY_A, "alt": KEY_LEFT,
		"pad": JOY_BUTTON_DPAD_LEFT, "axis": [JOY_AXIS_LEFT_X, -1.0]},
	{"id": "right", "name": "MOVE RIGHT", "key": KEY_D, "alt": KEY_RIGHT,
		"pad": JOY_BUTTON_DPAD_RIGHT, "axis": [JOY_AXIS_LEFT_X, 1.0]},
	{"id": "up", "name": "CLIMB UP", "key": KEY_W, "alt": KEY_UP,
		"pad": JOY_BUTTON_DPAD_UP, "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	{"id": "down", "name": "CLIMB DOWN", "key": KEY_S, "alt": KEY_DOWN,
		"pad": JOY_BUTTON_DPAD_DOWN, "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	{"id": "jump", "name": "JUMP", "key": KEY_SPACE, "alt": KEY_NONE,
		"pad": JOY_BUTTON_A, "axis": []},
	{"id": "attack", "name": "ATTACK", "key": KEY_J, "alt": KEY_NONE,
		"pad": JOY_BUTTON_X, "axis": [], "mouse": MOUSE_BUTTON_LEFT},
	{"id": "dodge", "name": "DODGE ROLL", "key": KEY_K, "alt": KEY_SHIFT,
		"pad": JOY_BUTTON_B, "axis": []},
	{"id": "block", "name": "GUARD", "key": KEY_L, "alt": KEY_NONE,
		"pad": JOY_BUTTON_RIGHT_SHOULDER, "axis": [], "mouse": MOUSE_BUTTON_RIGHT},
	{"id": "swap", "name": "SWAP WEAPON", "key": KEY_TAB, "alt": KEY_R,
		"pad": JOY_BUTTON_LEFT_SHOULDER, "axis": []},
	{"id": "heal", "name": "DRINK FLASK", "key": KEY_Q, "alt": KEY_NONE,
		"pad": JOY_BUTTON_Y, "axis": []},
	{"id": "interact", "name": "USE  TAKE", "key": KEY_E, "alt": KEY_NONE,
		"pad": JOY_BUTTON_RIGHT_STICK, "axis": []},
]

## Actions the menus handle themselves, listed so the controls page can show
## them even though they are not rebindable.
const FIXED := [
	["OPEN MAP", "M"],
	["PAUSE", "ESC"],
	["DROP THROUGH", "DOWN + JUMP"],
]

const DEADZONE := 0.45

## id -> keycode, only for actions the player has actually changed.
static var bound := {}


static func default_key(id: String) -> int:
	for a in ACTIONS:
		if a["id"] == id:
			return int(a["key"])
	return KEY_NONE


static func key_of(id: String) -> int:
	return int(bound.get(id, default_key(id)))


## What to print on the controls page. Godot's own keycode names are
## title-case and occasionally punctuated; the bone font is upper-case only.
static func label(id: String) -> String:
	return key_name(key_of(id))


static func key_name(code: int) -> String:
	if code == KEY_NONE:
		return "-"
	var raw := OS.get_keycode_string(code).to_upper()
	var out := ""
	for i in raw.length():
		out += raw[i] if PixelLabel.CHARS.find(raw[i]) >= 0 else " "
	return out.strip_edges()


## True if this key is already doing something else — the options screen refuses
## a duplicate rather than silently leaving two actions on one key.
static func conflict(id: String, code: int) -> String:
	for a in ACTIONS:
		if a["id"] == id:
			continue
		if key_of(a["id"]) == code or int(a["alt"]) == code:
			return String(a["name"])
	if code in [KEY_ESCAPE, KEY_M, KEY_ENTER, KEY_KP_ENTER]:
		return "THE MENUS"
	return ""


static func rebind(id: String, code: int) -> void:
	bound[id] = code
	apply()


static func reset() -> void:
	bound = {}
	apply()


## Rebuild the whole InputMap from the table. Called on boot and after any
## rebind, so there is exactly one code path that decides what a key does.
static func apply() -> void:
	for a in ACTIONS:
		var id: String = a["id"]
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, DEADZONE)
		_add_key(id, key_of(id))
		_add_key(id, int(a["alt"]))
		if a.has("mouse"):
			var mb := InputEventMouseButton.new()
			mb.button_index = int(a["mouse"])
			InputMap.action_add_event(id, mb)
		var jb := InputEventJoypadButton.new()
		jb.button_index = int(a["pad"])
		InputMap.action_add_event(id, jb)
		var axis: Array = a["axis"]
		if not axis.is_empty():
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(axis[0])
			jm.axis_value = float(axis[1])
			InputMap.action_add_event(id, jm)


static func _add_key(id: String, code: int) -> void:
	if code == KEY_NONE:
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	InputMap.action_add_event(id, ev)


# --- persistence -------------------------------------------------------------
static func write(cfg: ConfigFile) -> void:
	for id in bound:
		cfg.set_value("keys", id, bound[id])


static func read(cfg: ConfigFile) -> void:
	bound = {}
	for a in ACTIONS:
		var id: String = a["id"]
		if cfg.has_section_key("keys", id):
			bound[id] = int(cfg.get_value("keys", id))
