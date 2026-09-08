class_name Settings
extends RefCounted
## Everything the options screen can change, kept in user://settings.cfg so it
## survives a restart.
##
## Static state rather than an autoload: the project builds everything in code
## and has no singletons, and these are read from four different screens.
##
## Every setting is a plain value plus an `apply_*` that pushes it at the
## engine. Nothing here reaches into a menu, and no menu reaches past here into
## DisplayServer or AudioServer — that separation is why the same options page
## can be embedded in both the title screen and the pause screen.

const PATH := "user://settings.cfg"

# --- video -------------------------------------------------------------------
## 0 means fullscreen; otherwise the viewport is scaled by this integer, which
## keeps every pixel square. Non-integer scaling is what makes pixel art shimmer.
static var window_scale := 3
static var vsync := 1                  # index into VSYNC_MODES
static var fps_limit := 0              # index into FPS_LIMITS
static var vignette := true
static var screen_shake := true

# --- audio (0..10, shown as a ten-notch bar) ---------------------------------
static var vol_master := 8
static var vol_music := 6
static var vol_sfx := 8
static var vol_ambience := 6

# --- gameplay ----------------------------------------------------------------
static var hud_hints := true
static var region_banners := true
static var auto_equip := true          # a found weapon goes straight in hand

static var _loaded := false

const SCALE_LABELS := {0: "FULLSCREEN", 2: "2X", 3: "3X", 4: "4X"}
const SCALE_ORDER := [2, 3, 4, 0]
const VSYNC_MODES := ["OFF", "ON", "ADAPTIVE"]
const FPS_LIMITS := [0, 60, 120, 144, 240]
const VOL_MAX := 10


static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		Keys.apply()
		return
	window_scale = int(cfg.get_value("video", "window_scale", window_scale))
	vsync = int(cfg.get_value("video", "vsync", vsync))
	fps_limit = int(cfg.get_value("video", "fps_limit", fps_limit))
	vignette = bool(cfg.get_value("video", "vignette", vignette))
	screen_shake = bool(cfg.get_value("video", "screen_shake", screen_shake))
	vol_master = int(cfg.get_value("audio", "master", vol_master))
	vol_music = int(cfg.get_value("audio", "music", vol_music))
	vol_sfx = int(cfg.get_value("audio", "sfx", vol_sfx))
	vol_ambience = int(cfg.get_value("audio", "ambience", vol_ambience))
	hud_hints = bool(cfg.get_value("game", "hud_hints", hud_hints))
	region_banners = bool(cfg.get_value("game", "region_banners", region_banners))
	auto_equip = bool(cfg.get_value("game", "auto_equip", auto_equip))
	Keys.read(cfg)
	Keys.apply()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "window_scale", window_scale)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "vignette", vignette)
	cfg.set_value("video", "screen_shake", screen_shake)
	cfg.set_value("audio", "master", vol_master)
	cfg.set_value("audio", "music", vol_music)
	cfg.set_value("audio", "sfx", vol_sfx)
	cfg.set_value("audio", "ambience", vol_ambience)
	cfg.set_value("game", "hud_hints", hud_hints)
	cfg.set_value("game", "region_banners", region_banners)
	cfg.set_value("game", "auto_equip", auto_equip)
	Keys.write(cfg)
	cfg.save(PATH)


## Back to how the game shipped, keys included.
static func restore_defaults() -> void:
	window_scale = 3
	vsync = 1
	fps_limit = 0
	vignette = true
	screen_shake = true
	vol_master = 8
	vol_music = 6
	vol_sfx = 8
	vol_ambience = 6
	hud_hints = true
	region_banners = true
	auto_equip = true
	Keys.reset()
	apply_all()
	save()


static func apply_all() -> void:
	apply_window()
	apply_vsync()
	apply_fps()
	Audio.apply_volumes()


# --- video -------------------------------------------------------------------
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
static func headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func apply_window() -> void:
	if headless():
		return
	if window_scale == 0:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(UiTheme.VIEW.x) * window_scale,
			int(UiTheme.VIEW.y) * window_scale))


static func vsync_label() -> String:
	return VSYNC_MODES[clampi(vsync, 0, VSYNC_MODES.size() - 1)]


static func cycle_vsync(dir: int) -> void:
	vsync = posmod(vsync + dir, VSYNC_MODES.size())
	apply_vsync()
	save()


static func apply_vsync() -> void:
	if headless():
		return
	match vsync:
		0: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		2: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


static func fps_label() -> String:
	var v: int = FPS_LIMITS[clampi(fps_limit, 0, FPS_LIMITS.size() - 1)]
	return "UNLIMITED" if v == 0 else str(v)


static func cycle_fps(dir: int) -> void:
	fps_limit = posmod(fps_limit + dir, FPS_LIMITS.size())
	apply_fps()
	save()


static func apply_fps() -> void:
	Engine.max_fps = FPS_LIMITS[clampi(fps_limit, 0, FPS_LIMITS.size() - 1)]


# --- audio -------------------------------------------------------------------
static func vol_label(v: int) -> String:
	return "%d%%" % (v * 10)


static func nudge_volume(which: String, dir: int) -> void:
	match which:
		"master": vol_master = clampi(vol_master + dir, 0, VOL_MAX)
		"music": vol_music = clampi(vol_music + dir, 0, VOL_MAX)
		"sfx": vol_sfx = clampi(vol_sfx + dir, 0, VOL_MAX)
		"ambience": vol_ambience = clampi(vol_ambience + dir, 0, VOL_MAX)
	Audio.apply_volumes()
	save()


static func on_off(v: bool) -> String:
	return "ON" if v else "OFF"
