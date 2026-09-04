class_name UiTheme
extends RefCounted
## One place for the bone-and-ember palette and the UI geometry, so the menus,
## the HUD and the pause screen cannot drift apart.

const UI := "res://assets/ui/"

# --- palette (mirrors UIPAL in tools/gen_art.py) ---
const BONE := Color(0.870, 0.843, 0.760)        # label ivory
const BONE_BRIGHT := Color(0.945, 0.925, 0.855) # selected entry
const BONE_DIM := Color(0.478, 0.439, 0.392)    # unselected entry
const BONE_FAINT := Color(0.353, 0.322, 0.290)  # hints, footnotes
const EMBER := Color(0.925, 0.345, 0.227)       # socket glow, accents
const BLOOD := Color(0.588, 0.102, 0.094)       # health fill
const BLOOD_HI := Color(0.769, 0.173, 0.141)    # health fill top edge
const BLOOD_GHOST := Color(0.404, 0.129, 0.118) # the drain trailing a hit
const STAMINA := Color(0.424, 0.494, 0.275)
const STAMINA_HI := Color(0.549, 0.620, 0.361)
const TITLE_SHADOW := Color(0.408, 0.086, 0.063)

# --- menu layout (mirrors the constants in tools/gen_art.py; the backdrop
# bakes the big skull relative to these, so they must not drift) ---
const VIEW := Vector2(384, 216)
const TITLE_Y := 20
const SUB_Y := 50
const PANEL_Y := 66
const MENU_Y0 := 80          # first entry INSIDE the panel
const MENU_STEP := 18

# Panel geometry, mirrored by menu_panel_metrics() in tools/gen_art.py.
const CURSOR_GUTTER := 30    # cursor skull + air, left of the entry text
const PANEL_PAD_X := 12
const PANEL_PAD_BOTTOM := 12
const VALUE_GAP := 24        # between an option's name and its value column
## Row pitch for the dense two-column tables (controls, progress). Ten control
## rows at 12 ran the panel straight through the footer band; 11 is the most
## that fits between PANEL_Y and the footer.
const ROW_STEP := 11


## Panel size for a list of entries, sized to its longest line rather than a
## magic constant — that is what keeps a four-item menu and a two-item one
## looking like the same design.
static func menu_panel_size(items: Array, scale_px: int = 2,
		step: int = MENU_STEP, values: Array = []) -> Vector2:
	var longest := 0.0
	for i in items.size():
		var line := PixelLabel.measure(items[i], scale_px).x
		if i < values.size():
			line += VALUE_GAP + PixelLabel.measure(str(values[i]), scale_px).x
		longest = maxf(longest, line)
	return Vector2(CURSOR_GUTTER + longest + PANEL_PAD_X,
			(MENU_Y0 - PANEL_Y) + (items.size() - 1) * step
			+ PixelLabel.GLYPH_H * scale_px + PANEL_PAD_BOTTOM)


## The one control table, shared by the title screen and the pause screen —
## two copies drift the moment a key is rebound.
const CONTROL_ROWS := [
	["MOVE", "A  D"],
	["JUMP", "SPACE"],
	["CLIMB", "W  S"],
	["DROP THROUGH", "S + SPACE"],
	["ATTACK", "J"],
	["DODGE ROLL", "K"],
	["SWAP WEAPON", "TAB"],
	["GUARD", "L"],
	["USE  TAKE", "E"],
	["PAUSE", "ESC"],
]


## Centres a panel sized to its contents on `parent`. Returns [origin, size].
static func add_panel(parent: Node, items: Array, scale_px: int = 2,
		step: int = MENU_STEP, values: Array = [],
		min_w: float = 0.0) -> Array:
	var size := menu_panel_size(items, scale_px, step, values)
	size.x = maxf(size.x, min_w)
	var origin := Vector2(roundf((VIEW.x - size.x) * 0.5), PANEL_Y)
	var p := panel(size)
	p.position = origin
	parent.add_child(p)
	return [origin, size]


## Lays out a name/key table inside a panel: names left, keys right.
static func add_rows(parent: Node, rows: Array, origin: Vector2,
		panel_w: float, step: int = ROW_STEP) -> void:
	for i in rows.size():
		var y := origin.y + (MENU_Y0 - PANEL_Y) + i * step
		var name_label := PixelLabel.make(rows[i][0], 1, BONE)
		name_label.position = Vector2(origin.x + 16, y)
		parent.add_child(name_label)
		var key := PixelLabel.make(rows[i][1], 1, EMBER)
		key.position = Vector2(origin.x + panel_w - PANEL_PAD_X - key.size.x, y)
		parent.add_child(key)


## The footer every menu ends with: a dark band, a hair-line rule, and the key
## hints. The band is not decoration — without it whatever is behind the menu
## (the bone heap on the title screen, the HUD's own hint in game) shows through
## the text and neither is readable.
static func add_footer(parent: Node, hint: String) -> void:
	var band := ColorRect.new()
	band.color = Color(0.02, 0.018, 0.03, 0.90)
	band.position = Vector2(0, VIEW.y - 17)
	band.size = Vector2(VIEW.x, 17)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(band)

	var rule := ColorRect.new()
	rule.color = Color(0.36, 0.33, 0.30, 0.55)
	rule.position = Vector2(0, VIEW.y - 17)
	rule.size = Vector2(VIEW.x, 1)
	parent.add_child(rule)

	var tip := PixelLabel.make(hint, 1, BONE_FAINT)
	tip.center_on(VIEW.x * 0.5, VIEW.y - 12)
	parent.add_child(tip)


## A bone-framed box. NinePatchRect keeps the border crisp at any size.
static func panel(size: Vector2) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = tex("panel.png")
	p.patch_margin_left = 8
	p.patch_margin_top = 8
	p.patch_margin_right = 8
	p.patch_margin_bottom = 8
	p.size = size
	return p

# --- bar geometry: twin fangs flank a small recessed plate; the channel the
# fill is drawn into is inset by the fang length + the plate's own rim (see
# spiked_bar_frame() in tools/gen_art.py, cap = spike + 1) ---
const HP_FRAME := Vector2(76, 10)
const HP_CAP := 7
const SP_FRAME := Vector2(64, 9)
const SP_CAP := 6
const CHANNEL_INSET_Y := 2


static func channel_size(frame: Vector2, cap: int) -> Vector2:
	return Vector2(frame.x - cap * 2, frame.y - CHANNEL_INSET_Y * 2)


static func tex(name: String) -> Texture2D:
	return load(UI + name) as Texture2D


## One frame out of a horizontal sheet anywhere in the project — the weapon
## icons are world art, not UI art, so they do not live under assets/ui.
static func frame_tex_from(path: String, index: int, fw: int, fh: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load(path) as Texture2D
	at.region = Rect2(index * fw, 0, fw, fh)
	return at


## One frame out of a horizontal sheet (the skull sheet is dim / ember-eyed).
static func frame_tex(name: String, index: int, fw: int, fh: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex(name)
	at.region = Rect2(index * fw, 0, fw, fh)
	return at
