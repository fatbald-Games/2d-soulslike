extends CanvasLayer
## What the run has to show for itself, and who made it.
##
## Reaching the last inscription is the end of the route: it sits at the far west
## of the ramparts, above the gate you walked in through, and it is the only
## stone that is about you. So that is where the game ends.
##
## No boss, no cutscene. The epilogue is the same bone-and-ember furniture as
## every other screen, because a game that changes its font for the ending is
## telling you the ending belongs to a different game.

signal dismissed

const HOLD := 1.2                # before anything can be pressed

var _armed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20                   # over absolutely everything
	_build()
	var tw := create_tween()
	tw.tween_interval(HOLD)
	tw.tween_callback(func() -> void: _armed = true)


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.018, 0.03, 0.0)
	shade.size = UiTheme.VIEW
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	create_tween().tween_property(shade, "color:a", 0.96, 1.6)

	var title := PixelLabel.make("THE ASH REMEMBERS", 3, UiTheme.BONE_BRIGHT)
	title.shadow_tint = UiTheme.TITLE_SHADOW
	title.shadow_offset = Vector2(2, 2)
	title.center_on(UiTheme.VIEW.x * 0.5, 22)
	_fade_in(title, 0.6)
	add_child(title)

	var line := PixelLabel.make("YOU CAME IN THROUGH THAT GATE. SO DID I.", 1,
			UiTheme.BONE_FAINT)
	line.center_on(UiTheme.VIEW.x * 0.5, 46)
	_fade_in(line, 1.0)
	add_child(line)

	# --- what the run cost ---
	var t := Run.totals()
	var rows := [
		["TIME", _clock(Run.play_time)],
		["LEVEL", "%d" % Run.level()],
		["DEATHS", "%d" % Run.deaths],
		["HOLLOWS SLAIN", "%d" % Run.slain],
		["WEAPONS FOUND", "%d / %d" % [Run.owned().size(), t["weapons"]]],
		["BONFIRES LIT", "%d / %d" % [Run.lit_bonfires.size(), t["bonfires"]]],
		["INSCRIPTIONS READ", "%d / %d" % [Run.read_runes.size(), t["runes"]]],
		["KEEP EXPLORED", "%d%%" % int(round(Run.explored_fraction() * 100.0))],
	]
	var x0 := 92.0
	var x1 := UiTheme.VIEW.x - 92.0
	for i in rows.size():
		var y := 62 + i * 10
		var name_label := PixelLabel.make(rows[i][0], 1, UiTheme.BONE)
		name_label.position = Vector2(x0, y)
		_fade_in(name_label, 1.2 + i * 0.08)
		add_child(name_label)
		var val := PixelLabel.make(rows[i][1], 1, UiTheme.EMBER)
		val.position = Vector2(x1 - val.size.x, y)
		_fade_in(val, 1.2 + i * 0.08)
		add_child(val)

	# --- credits ---
	var credits := [
		"EVERY PIXEL AND EVERY SOUND HERE WAS GENERATED FROM CODE",
		"ART  TOOLS/GEN-ART.PY      LEVEL  TOOLS/GEN-LEVEL.PY",
		"SOUND  TOOLS/GEN-AUDIO.PY      ENGINE  GODOT 4",
	]
	for i in credits.size():
		var c := PixelLabel.make(credits[i], 1, UiTheme.BONE_DIM)
		c.center_on(UiTheme.VIEW.x * 0.5, 150 + i * 10)
		_fade_in(c, 2.2 + i * 0.25)
		add_child(c)

	var any := PixelLabel.make("PRESS ANY KEY", 1, UiTheme.BONE_FAINT)
	any.center_on(UiTheme.VIEW.x * 0.5, UiTheme.VIEW.y - 24)
	_fade_in(any, 3.2)
	add_child(any)


func _fade_in(node: CanvasItem, at: float) -> void:
	node.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_interval(at)
	tw.tween_property(node, "modulate:a", 1.0, 0.7)


## Hours only appear once there are some, so a forty-minute run does not read
## as "0:41:12".
func _clock(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


func _unhandled_input(event: InputEvent) -> void:
	if not _armed:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		_leave()
	elif event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).pressed:
		_leave()


func _leave() -> void:
	_armed = false
	dismissed.emit()
