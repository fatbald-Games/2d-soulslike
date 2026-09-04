class_name Settings
extends RefCounted
## Player options, kept in user://settings.cfg so they survive a restart.
##
## Static state rather than an autoload: the project builds everything in code
## and has no singletons, and these are read from three different screens.

const PATH := "user://settings.cfg"

## 0 means fullscreen; otherwise the viewport is scaled by this integer, which
## keeps every pixel square. Non-integer scaling is what makes pixel art shimmer.
static var window_scale := 3
static var screen_shake := true
static var hud_hints := true

static var _loaded := false

const SCALE_LABELS := {0: "FULLSCREEN", 2: "2X", 3: "3X", 4: "4X"}
const SCALE_ORDER := [2, 3, 4, 0]


static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	window_scale = int(cfg.get_value("video", "window_scale", window_scale))
	screen_shake = bool(cfg.get_value("game", "screen_shake", screen_shake))
	hud_hints = bool(cfg.get_value("game", "hud_hints", hud_hints))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "window_scale", window_scale)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("game", "hud_hints", hud_hints)
	cfg.save(PATH)


static func scale_label() -> String:
	return SCALE_LABELS.get(window_scale, "3X")


static func cycle_window(dir: int) -> void:
	var i := SCALE_ORDER.find(window_scale)
	if i < 0:
		i = 1
	window_scale = SCALE_ORDER[(i + dir + SCALE_ORDER.size()) % SCALE_ORDER.size()]
	apply_window()
	save()


## No-op under --headless, where DisplayServer is a stub and there is no window
## to resize — the tests run that way.
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if window_scale == 0:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(UiTheme.VIEW.x) * window_scale,
			int(UiTheme.VIEW.y) * window_scale))
