class_name Weapons
extends RefCounted
## The armoury. One table, read by the player (how it fights), the HUD (what it
## is called), the bonfire menu (what it costs you) and the level generator
## (where it is found).
##
## Every weapon has to be a real trade, not a straight upgrade — otherwise
## finding a new one just retires the old one and the choice evaporates. So:
##
##   LONGSWORD   the baseline. Nothing it does is best; nothing it does is bad.
##   GREAT AXE   almost twice the damage, and slow enough to get you killed.
##   WINGED SPEAR reaches half a body further than anything else, hits soft.
##   HUNTERS BOW kills at range, but each arrow is barely a scratch up close.
##   IRON CROSSBOW one heavy bolt, then a long, ugly reload.
##   HERALDS SHIELD hardly hurts anyone, and is the only thing that BLOCKS.

const MELEE := 0
const RANGED := 1
const GUARD := 2

const SWORD := 0
const AXE := 1
const SPEAR := 2
const BOW := 3
const CROSSBOW := 4
const SHIELD := 5

## damage / speed are MULTIPLIERS on the stats bought at the bonfire, so a
## levelled STRENGTH or FINESSE still matters whatever you are holding.
## speed multiplies the swing TIME: above 1.0 is slower.
const DEFS := [
	{"id": "sword", "name": "LONGSWORD", "kind": MELEE,
		"damage": 1.00, "speed": 1.00, "stamina": 28.0,
		"reach": 30.0, "height": 26.0, "knock": 110.0,
		"desc": "EVEN IN EVERY WAY. THE BLADE YOU CAME IN WITH."},
	{"id": "axe", "name": "GREAT AXE", "kind": MELEE,
		"damage": 1.90, "speed": 1.60, "stamina": 42.0,
		"reach": 27.0, "height": 32.0, "knock": 230.0,
		"desc": "SPLITS THEM IN ONE. COMMITS YOU FOR A LONG SECOND."},
	{"id": "spear", "name": "WINGED SPEAR", "kind": MELEE,
		"damage": 0.80, "speed": 0.92, "stamina": 24.0,
		"reach": 46.0, "height": 16.0, "knock": 80.0,
		"desc": "HITS FROM OUTSIDE THEIR SWING. A NARROW THRUST - AIM IT."},
	{"id": "bow", "name": "HUNTERS BOW", "kind": RANGED,
		"damage": 0.62, "speed": 1.25, "stamina": 20.0,
		"reach": 0.0, "height": 0.0, "knock": 60.0,
		"shot": {"sprite": "arrow.png", "w": 11, "h": 3,
			"speed": 300.0, "drop": 110.0, "life": 1.8},
		"desc": "THINS THEM OUT BEFORE THEY EVER REACH YOU. ARROWS DROP."},
	{"id": "crossbow", "name": "IRON CROSSBOW", "kind": RANGED,
		"damage": 1.55, "speed": 2.10, "stamina": 32.0,
		"reach": 0.0, "height": 0.0, "knock": 150.0,
		"shot": {"sprite": "bolt.png", "w": 8, "h": 3,
			"speed": 470.0, "drop": 0.0, "life": 1.4},
		"desc": "ONE BOLT, FLAT AND HEAVY. THEN A RELOAD YOU WILL FEEL."},
	{"id": "shield", "name": "HERALDS SHIELD", "kind": GUARD,
		"damage": 0.45, "speed": 1.05, "stamina": 16.0,
		"reach": 22.0, "height": 26.0, "knock": 260.0,
		"block": 0.80, "block_cost": 46.0,
		"desc": "HOLD L TO GUARD. A BASH BARELY HURTS - IT MOVES THEM."},
]

## Where each one is waiting. The starting blade has no pickup: everything else
## is somewhere you have to physically get to, which is what makes finding one
## read as progress rather than a menu unlock.
const START := "sword"


static func count() -> int:
	return DEFS.size()


static func index_of(id: String) -> int:
	for i in DEFS.size():
		if DEFS[i]["id"] == id:
			return i
	return -1


static func def(idx: int) -> Dictionary:
	return DEFS[clampi(idx, 0, DEFS.size() - 1)]


static func name_of(idx: int) -> String:
	return def(idx)["name"]


static func is_ranged(idx: int) -> bool:
	return def(idx)["kind"] == RANGED


static func can_block(idx: int) -> bool:
	return def(idx)["kind"] == GUARD
