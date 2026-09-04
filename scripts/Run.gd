class_name Run
extends RefCounted
## Everything the player has to show for the time spent: levels, which fires are
## lit, where they have been, what they have read.
##
## It also has to outlive a scene reload — dying calls reload_current_scene(),
## which destroys every node in the level, so none of this can live on the
## player. Static vars survive both a reload and a change_scene; NEW GAME wipes
## them with reset().

static var has_checkpoint := false
static var checkpoint := Vector2.ZERO      # world position of the last bonfire

## Souls dropped where you fell. Dying again before you collect them replaces
## the pile — the old one is gone for good, which is the whole point.
static var has_drop := false
static var drop_pos := Vector2.ZERO
static var dropped_souls := 0

static var souls := 0
static var flask := 3

# --- what the souls are FOR -------------------------------------------------
## Souls with nothing to spend them on are just a score. Five things to buy,
## and every one of them is felt within a second of buying it: two lengthen
## their HUD bar, three change how the knight moves and hits.
const VIGOR := 0
const ENDURANCE := 1
const AGILITY := 2
const STRENGTH := 3
const FINESSE := 4

const STAT_NAMES := ["VIGOR", "ENDURANCE", "AGILITY", "STRENGTH", "FINESSE"]
## What each one actually does, spelled out on the progress screen — a stat
## whose effect you have to guess is not progress you can plan around.
const STAT_EFFECTS := ["HEALTH", "STAMINA", "MOVE SPEED", "DAMAGE", "ATTACK SPEED"]
const STAT_MAX := 10
const COST_BASE := 80
const COST_STEP := 40

static var stats := [0, 0, 0, 0, 0]        # indexes match STAT_NAMES

# --- the armoury ------------------------------------------------------------
## Which weapons have been found, and which one is in his hands. Finding one is
## the only progress in the game that changes how it PLAYS rather than how big
## a number is — so it lives here with the rest of the run, and survives death.
static var weapons := {Weapons.START: true}     # id -> true
static var weapon := 0                          # index into Weapons.DEFS


static func has_weapon(id: String) -> bool:
	return weapons.has(id)


## True only the FIRST time — Main uses that to decide whether to announce it.
static func find_weapon(id: String) -> bool:
	if weapons.has(id):
		return false
	weapons[id] = true
	return true


## Indices of everything found, in armoury order.
static func owned() -> Array:
	var out: Array = []
	for i in Weapons.DEFS.size():
		if weapons.has(Weapons.DEFS[i]["id"]):
			out.append(i)
	return out


static func equip(idx: int) -> bool:
	if idx < 0 or idx >= Weapons.DEFS.size():
		return false
	if not weapons.has(Weapons.DEFS[idx]["id"]) or idx == weapon:
		return false
	weapon = idx
	return true


## Step to the next weapon he actually owns, wrapping. Unfound weapons are not
## in the cycle at all — swapping should never land on an empty hand.
static func cycle_weapon(dir: int) -> int:
	var own := owned()
	if own.size() < 2:
		return weapon
	var at := own.find(weapon)
	if at < 0:
		at = 0
	weapon = own[posmod(at + dir, own.size())]
	return weapon


# --- what has been seen -----------------------------------------------------
static var lit_bonfires := {}              # "tx,ty" -> true
static var seen_areas := {}                # area name -> true
static var read_runes := {}                # "tx,ty" -> true
static var slain := 0


static func reset() -> void:
	has_checkpoint = false
	checkpoint = Vector2.ZERO
	has_drop = false
	drop_pos = Vector2.ZERO
	dropped_souls = 0
	souls = 0
	flask = Player.FLASK_MAX
	stats = [0, 0, 0, 0, 0]
	weapons = {Weapons.START: true}
	weapon = Weapons.index_of(Weapons.START)
	lit_bonfires = {}
	seen_areas = {}
	read_runes = {}
	slain = 0


static func rest_at(pos: Vector2) -> void:
	has_checkpoint = true
	checkpoint = pos


## Called on death: bank what the knight was carrying, then empty his pockets.
static func drop(at: Vector2, amount: int) -> void:
	has_drop = amount > 0
	drop_pos = at
	dropped_souls = amount
	souls = 0


static func collect() -> int:
	var n := dropped_souls
	has_drop = false
	dropped_souls = 0
	return n


## Level 1 at the gate; every point spent anywhere is one more level.
static func level() -> int:
	var n := 1
	for v in stats:
		n += v
	return n


## The price climbs with total level, so the tenth point costs far more than the
## first — the usual souls curve, and it keeps a farmed bonfire from trivialising
## the run.
static func next_cost() -> int:
	return COST_BASE + (level() - 1) * COST_STEP


static func can_afford() -> bool:
	return souls >= next_cost()


static func can_raise(stat: int) -> bool:
	return stat >= 0 and stat < stats.size() and stats[stat] < STAT_MAX and can_afford()


static func raise_stat(stat: int) -> bool:
	if not can_raise(stat):
		return false
	souls -= next_cost()
	stats[stat] += 1
	return true


# --- discovery --------------------------------------------------------------
static func key(tx: int, ty: int) -> String:
	return "%d,%d" % [tx, ty]


static func light_bonfire(k: String) -> bool:
	if lit_bonfires.has(k):
		return false
	lit_bonfires[k] = true
	return true


static func see_area(name: String) -> bool:
	if name.is_empty() or seen_areas.has(name):
		return false
	seen_areas[name] = true
	return true


static func read_rune(k: String) -> bool:
	if read_runes.has(k):
		return false
	read_runes[k] = true
	return true


## Totals for the progress screen, counted from the map so they cannot go stale.
static func totals() -> Dictionary:
	var bonfires := 0
	var runes := 0
	for e in LevelMap.ENTITIES:
		if e["kind"] == "bonfire":
			bonfires += 1
		elif e["kind"] == "rune":
			runes += 1
	return {"areas": LevelMap.AREAS.size(), "bonfires": bonfires, "runes": runes,
			"weapons": Weapons.count()}
