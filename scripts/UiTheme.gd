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
const TITLE_Y := 24
const SUB_Y := 58
const MENU_Y0 := 78
const MENU_STEP := 18

# --- bar geometry: the channel the fill is drawn into, inset inside the
# bone frame by its end caps (see bone_bar_frame() in tools/gen_art.py) ---
const HP_FRAME := Vector2(112, 13)
const HP_CAP := 5
const SP_FRAME := Vector2(96, 11)
const SP_CAP := 4
const CHANNEL_INSET_Y := 2


static func channel_size(frame: Vector2, cap: int) -> Vector2:
	return Vector2(frame.x - cap * 2, frame.y - CHANNEL_INSET_Y * 2)


static func tex(name: String) -> Texture2D:
	return load(UI + name) as Texture2D


## One frame out of a horizontal sheet (the skull sheet is dim / ember-eyed).
static func frame_tex(name: String, index: int, fw: int, fh: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex(name)
	at.region = Rect2(index * fw, 0, fw, fh)
	return at
