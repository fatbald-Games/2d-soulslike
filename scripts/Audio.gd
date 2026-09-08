class_name Audio
extends Node
## Every sound in the game, on three buses.
##
## All of it is synthesised by tools/gen_audio.py — nothing sampled, nothing
## licensed — for the same reason the art is: the whole soundtrack is a few
## hundred lines anyone can read and change.
##
## This node lives on the SceneTree root rather than inside a scene, so the
## music keeps playing across the title screen, the run, and the reload that
## follows a death. Everything else in the project is built in code and this is
## no exception: the buses are created here, not in a .tscn.

const DIR := "res://assets/audio/"

## Bus layout. SFX and MUSIC feed Master; AMBIENCE is its own so a player can
## turn the dripping down without turning the sword down.
const BUS_SFX := "SFX"
const BUS_MUSIC := "MUSIC"
const BUS_AMBIENCE := "AMBIENCE"

const VOICES := 12                # simultaneous one-shots before stealing
const FADE := 1.2                 # crossfade between loops, seconds

static var _me: Audio
static var _cache := {}
## Set by shutdown(). Once the streams have been released nothing may start a
## new one — a scene change during teardown would otherwise boot the whole
## thing back up and leave a stream live at exit.
static var _closed := false

var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _ambience_b: AudioStreamPlayer
var _music_now := ""
var _ambience_now := ""


## Idempotent: every scene calls it on boot and only the first one does work.
static func boot(tree: SceneTree) -> void:
	if _closed or (_me != null and is_instance_valid(_me)):
		return
	_me = Audio.new()
	_me.name = "Audio"
	tree.root.call_deferred("add_child", _me)
	_me._build_buses()
	apply_volumes()


static func ready() -> bool:
	return not _closed and _me != null and is_instance_valid(_me) \
			and _me.is_inside_tree()


func _build_buses() -> void:
	for bus in [BUS_SFX, BUS_MUSIC, BUS_AMBIENCE]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # menus pause the tree
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_voices.append(p)
	_music = _loop_player(BUS_MUSIC)
	_music_b = _loop_player(BUS_MUSIC)
	_ambience = _loop_player(BUS_AMBIENCE)
	_ambience_b = _loop_player(BUS_AMBIENCE)


## The stream cache is static, so it outlives the tree unless it is emptied
## here — otherwise the engine reports leaked resources at exit, which the test
## runner (rightly) treats as a failure.
## The tree is tearing us down: release the streams, but reparent nothing — the
## parent is mid-removal at this point and says so, loudly.
func _exit_tree() -> void:
	_closed = true
	_release()
	_cache.clear()


## Stop everything and drop every cached stream. A player that is still PLAYING
## holds its stream inside the audio server, so stopping has to come first —
## nulling the reference alone leaves the resource live and the engine reports
## a leak at exit, which the test runner treats as a failure (correctly).
static func shutdown() -> void:
	_closed = true
	if _me != null and is_instance_valid(_me):
		_me._release()
		# free() rather than queue_free(): the audio server only lets go of a
		# stopped playback when the player is actually gone, and waiting a few
		# frames for that made the leak check pass about half the time. Taking
		# the node out of the tree and freeing it here makes it deterministic.
		# queue_free() rather than free(): shutdown can be called from a frame
		# on which the tree is mid scene-swap, and reparenting anything then is
		# an error. The node is gone by the end of the frame either way, and
		# that is what finally makes the audio server let go of the streams.
		_me.queue_free()
	_me = null
	_cache.clear()


## Silence every voice and drop its stream. Safe at any time; frees nothing, so
## it is also what runs from _exit_tree, where the parent is mid-removal and
## reparenting anything is an error.
func _release() -> void:
	var all: Array = _voices.duplicate()
	all.append_array([_music, _music_b, _ambience, _ambience_b])
	for p in all:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
	_voices.clear()
	_music = null
	_music_b = null
	_ambience = null
	_ambience_b = null
	_music_now = ""
	_ambience_now = ""


func _loop_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


## Loaded once and kept: these are small, and a disk hit on the frame a sword
## lands is exactly the wrong moment for one.
static func stream(name: String, loop: bool) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s := load(DIR + name + ".wav") as AudioStream
	if s is AudioStreamWAV and loop:
		# set here rather than in the .import file: those are generated on the
		# player's machine and are not in version control
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = (s as AudioStreamWAV).data.size() / 2
	_cache[name] = s
	return s


# --- one-shots ---------------------------------------------------------------
## `pitch` is a spread, not a value: every call varies the pitch a little, or
## twenty sword swings in a row start sounding like a machine.
static func play(name: String, spread: float = 0.06, db: float = 0.0) -> void:
	if not ready():
		return
	_me._play(name, spread, db)


func _play(name: String, spread: float, db: float) -> void:
	if _voices.is_empty():
		return
	var s := Audio.stream(name, false)
	if s == null:
		return
	var p := _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = s
	p.pitch_scale = 1.0 + randf_range(-spread, spread)
	p.volume_db = db
	p.play()


# --- loops -------------------------------------------------------------------
static func music(name: String) -> void:
	if ready():
		_me._swap("_music", "_music_b", name)


static func ambience(name: String) -> void:
	if ready():
		_me._swap("_ambience", "_ambience_b", name)


## Crossfade rather than cut: walking from the cistern into the rootworks should
## not sound like someone changed the record.
func _swap(a: String, b: String, name: String) -> void:
	var now := "_music_now" if a == "_music" else "_ambience_now"
	if get(now) == name:
		return
	set(now, name)
	var front: AudioStreamPlayer = get(a)
	var back: AudioStreamPlayer = get(b)
	if front == null or back == null:
		return
	set(a, back)
	set(b, front)

	back.stream = Audio.stream(name, true)
	back.volume_db = -40.0
	back.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(back, "volume_db", 0.0, FADE)
	if front.playing:
		tw.tween_property(front, "volume_db", -40.0, FADE)
		tw.chain().tween_callback(front.stop)


static func stop_music() -> void:
	if not ready():
		return
	_me._music_now = ""
	_me._music.stop()
	_me._music_b.stop()


# --- volumes -----------------------------------------------------------------
static func apply_volumes() -> void:
	_set_bus("Master", Settings.vol_master)
	_set_bus(BUS_SFX, Settings.vol_sfx)
	_set_bus(BUS_MUSIC, Settings.vol_music)
	_set_bus(BUS_AMBIENCE, Settings.vol_ambience)


static func _set_bus(name: String, notches: int) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, notches <= 0)
	# a linear slider sounds wrong: -30dB..0dB across ten notches tracks how
	# loudness is actually perceived
	AudioServer.set_bus_volume_db(i, -30.0 + 30.0 * (float(notches) / 10.0))
