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

## id, the name shown to the player, the default key, an alternate, the mouse
## buttons it also answers to, and how it sits on a controller. `axis` is
## [axis, direction] for stick movement.
##
## The layout is the one a mouse-and-keyboard player already has in their hands:
## the left hand never leaves WASD, and the right hand fights. W jumps AND
## climbs — which of the two you get depends on whether there is a ladder in
## front of you, and that is never ambiguous in practice. SPACE jumps as well,
## so the ladder can still be hopped off (see Player._climb_state).
const ACTIONS := [
	{"id": "left", "name": "MOVE LEFT", "key": KEY_A, "alt": KEY_LEFT,
		"pad": JOY_BUTTON_DPAD_LEFT, "axis": [JOY_AXIS_LEFT_X, -1.0]},
	{"id": "right", "name": "MOVE RIGHT", "key": KEY_D, "alt": KEY_RIGHT,
		"pad": JOY_BUTTON_DPAD_RIGHT, "axis": [JOY_AXIS_LEFT_X, 1.0]},
	{"id": "up", "name": "UP  CLIMB", "key": KEY_W, "alt": KEY_UP,
		"pad": JOY_BUTTON_DPAD_UP, "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	{"id": "down", "name": "DOWN  CLIMB", "key": KEY_S, "alt": KEY_DOWN,
		"pad": JOY_BUTTON_DPAD_DOWN, "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	{"id": "jump", "name": "JUMP", "key": KEY_W, "alt": KEY_SPACE,
		"pad": JOY_BUTTON_A, "axis": []},
	{"id": "attack", "name": "ATTACK", "key": KEY_J, "alt": KEY_NONE,
		"pad": JOY_BUTTON_X, "axis": [], "mouse": [MOUSE_BUTTON_LEFT]},
	{"id": "block", "name": "GUARD", "key": KEY_L, "alt": KEY_NONE,
		"pad": JOY_BUTTON_RIGHT_SHOULDER, "axis": [],
		"mouse": [MOUSE_BUTTON_RIGHT]},
	{"id": "dodge", "name": "DODGE ROLL", "key": KEY_SHIFT, "alt": KEY_K,
		"pad": JOY_BUTTON_B, "axis": []},
	{"id": "swap", "name": "SWAP WEAPON", "key": KEY_TAB, "alt": KEY_R,
		"pad": JOY_BUTTON_LEFT_SHOULDER, "axis": [],
		"mouse": [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]},
	{"id": "heal", "name": "DRINK FLASK", "key": KEY_Q, "alt": KEY_NONE,
		"pad": JOY_BUTTON_Y, "axis": []},
	{"id": "interact", "name": "USE  TAKE", "key": KEY_E, "alt": KEY_NONE,
		"pad": JOY_BUTTON_RIGHT_STICK, "axis": []},
]

## Printed next to the key on the controls page. The bone font has no lowercase
## and no symbols beyond a handful, so these are spelled out.
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "WHEEL",
	MOUSE_BUTTON_WHEEL_DOWN: "WHEEL",
}

## Actions the menus handle themselves, listed so the controls page can show
## them even though they are not rebindable.
const FIXED := [
	["OPEN MAP", "M"],
	["PAUSE", "ESC"],
	["DROP THROUGH", "S + SPACE"],
]

const DEADZONE := 0.45

## id -> keycode, only for actions the player has actually changed.
static var bound := {}


static func default_key(id: String) -> int:
	for a in ACTIONS:
		if a["id"] == id:
			return int(a["key"])
	return KEY_NONE


## The alternate the action also answers to, which is never rebindable — the
## arrow keys, SPACE for jump, K for the roll.
static func alt_key(id: String) -> int:
	for a in ACTIONS:
		if a["id"] == id:
			return int(a["alt"])
	return KEY_NONE


static func key_of(id: String) -> int:
	return int(bound.get(id, default_key(id)))


## What to print on the controls page: the key, plus the mouse button it also
## answers to. Leaving the mouse out of a scheme built around the mouse is how
## a player ends up never discovering that the left button swings.
static func label(id: String) -> String:
	var out := key_name(key_of(id))
	var m := mouse_name(id)
	if not m.is_empty():
		out = "%s  %s" % [m, out] if out != "-" else m
	return out


## Everything the action answers to, for the read-only tables on the title and
## pause screens: mouse button, primary key, and the alternate. The rebinding
## page deliberately shows less (see label) — there only the key you can
## actually change belongs in the column you are about to edit.
static func help_label(id: String) -> String:
	var parts: Array = []
	var m := mouse_name(id)
	if not m.is_empty():
		parts.append(m)
	var k := key_name(key_of(id))
	if k != "-":
		parts.append(k)
	for a in ACTIONS:
		if a["id"] != id:
			continue
		var alt := key_name(int(a["alt"]))
		if alt != "-" and alt != k:
			parts.append(alt)
	return "  ".join(parts)


static func mouse_name(id: String) -> String:
	for a in ACTIONS:
		if a["id"] != id or not a.has("mouse"):
			continue
		var seen: Array = []
		for b in a["mouse"]:
			var n: String = MOUSE_NAMES.get(b, "")
			if not n.is_empty() and not seen.has(n):
				seen.append(n)
		return " ".join(seen)
	return ""


## Godot's own keycode names are title-case and occasionally punctuated; the
## bone font is upper-case only, so anything it cannot draw is dropped rather
## than printed as a blank the player has to guess at.
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
## W is deliberately both UP and JUMP, so those two do not count as clashing
## with each other.
const SHARED := [["up", "jump"]]


static func _shared(a: String, b: String) -> bool:
	for pair in SHARED:
		if pair.has(a) and pair.has(b):
			return true
	return false


static func conflict(id: String, code: int) -> String:
	for a in ACTIONS:
		if a["id"] == id or _shared(id, String(a["id"])):
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
			for b in a["mouse"]:
				var mb := InputEventMouseButton.new()
				mb.button_index = int(b)
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
