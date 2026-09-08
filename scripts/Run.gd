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


# --- the map ----------------------------------------------------------------
## One byte per tile: 0 never seen, 1 walked past. Sixteen screens of keep with
## no map at all is the single most-repeated complaint about this whole genre,
## and at 384x128 tiles the map is exactly one pixel per tile — it fits the
## screen at 1:1 without scaling anything.
static var explored := PackedByteArray()


static func map_ready() -> void:
	if explored.size() != LevelMap.W * LevelMap.H:
		explored = PackedByteArray()
		explored.resize(LevelMap.W * LevelMap.H)


static func is_explored(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= LevelMap.W or ty >= LevelMap.H:
		return false
	return explored[ty * LevelMap.W + tx] != 0


## Reveal a disc around him. Returns how many tiles were NEW, so the caller can
## skip rebuilding anything when nothing changed.
static func see_tiles(cx: int, cy: int, radius: int) -> int:
	map_ready()
	var found := 0
	var r2 := radius * radius
	for dy in range(-radius, radius + 1):
		var ty := cy + dy
		if ty < 0 or ty >= LevelMap.H:
			continue
		for dx in range(-radius, radius + 1):
			var tx := cx + dx
			if tx < 0 or tx >= LevelMap.W or dx * dx + dy * dy > r2:
				continue
			var i := ty * LevelMap.W + tx
			if explored[i] == 0:
				explored[i] = 1
				found += 1
	return found


## Only the tiles that are actually part of the keep count, so the percentage
## does not stall at 30% because most of the map is solid rock.
static func explored_fraction() -> float:
	map_ready()
	var open := 0
	var seen := 0
	for ty in LevelMap.H:
		var row: String = LevelMap.MAP[ty]
		for tx in LevelMap.W:
			if row[tx] == "#" or row[tx] == "X":
				continue
			open += 1
			if explored[ty * LevelMap.W + tx] != 0:
				seen += 1
	return 0.0 if open == 0 else float(seen) / float(open)


# --- what has been seen -----------------------------------------------------
static var lit_bonfires := {}              # "tx,ty" -> true
static var seen_areas := {}                # area name -> true
static var read_runes := {}                # "tx,ty" -> true
static var slain := 0
## Set once the last inscription has been read: the run has an end, and the
## title screen says so afterwards.
static var finished := false
static var play_time := 0.0
## Counted, not hidden. A souls game that will not tell you how many times it
## killed you is being coy about the only number that describes the run.
static var deaths := 0


# --- persistence -------------------------------------------------------------
## The whole run, in user://save.cfg. Everything above this line is static so it
## survives a scene reload; this is what makes it survive closing the game.
##
## Written at the only two moments that matter in a souls game — resting at a
## fire, and dying — so a save is always at a checkpoint and never mid-fall.
## A static var rather than a const so the test suites can point it at their own
## file — a test run must never eat the player's actual save.
static var SAVE_PATH := "user://save.cfg"
const SAVE_VERSION := 1


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "version", SAVE_VERSION)
	cfg.set_value("run", "checkpoint", checkpoint)
	cfg.set_value("run", "has_checkpoint", has_checkpoint)
	cfg.set_value("run", "souls", souls)
	cfg.set_value("run", "flask", flask)
	cfg.set_value("run", "stats", stats)
	cfg.set_value("run", "slain", slain)
	cfg.set_value("run", "deaths", deaths)
	cfg.set_value("run", "finished", finished)
	cfg.set_value("run", "play_time", play_time)
	cfg.set_value("drop", "has_drop", has_drop)
	cfg.set_value("drop", "pos", drop_pos)
	cfg.set_value("drop", "souls", dropped_souls)
	cfg.set_value("armoury", "weapons", weapons.keys())
	cfg.set_value("armoury", "equipped", weapon)
	cfg.set_value("seen", "bonfires", lit_bonfires.keys())
	cfg.set_value("seen", "areas", seen_areas.keys())
	cfg.set_value("seen", "runes", read_runes.keys())
	# 49152 bytes of fog; base64 keeps the config file a text file
	map_ready()
	cfg.set_value("seen", "explored", Marshalls.raw_to_base64(explored))
	cfg.save(SAVE_PATH)


static func load_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	if int(cfg.get_value("run", "version", 0)) != SAVE_VERSION:
		return false                 # a save from another build is not a save
	reset()
	has_checkpoint = bool(cfg.get_value("run", "has_checkpoint", false))
	checkpoint = cfg.get_value("run", "checkpoint", Vector2.ZERO)
	souls = int(cfg.get_value("run", "souls", 0))
	flask = int(cfg.get_value("run", "flask", 3))
	stats = cfg.get_value("run", "stats", [0, 0, 0, 0, 0]).duplicate()
	slain = int(cfg.get_value("run", "slain", 0))
	deaths = int(cfg.get_value("run", "deaths", 0))
	finished = bool(cfg.get_value("run", "finished", false))
	play_time = float(cfg.get_value("run", "play_time", 0.0))
	has_drop = bool(cfg.get_value("drop", "has_drop", false))
	drop_pos = cfg.get_value("drop", "pos", Vector2.ZERO)
	dropped_souls = int(cfg.get_value("drop", "souls", 0))
	weapons = _set_of(cfg.get_value("armoury", "weapons", [Weapons.START]))
	weapon = int(cfg.get_value("armoury", "equipped", 0))
	lit_bonfires = _set_of(cfg.get_value("seen", "bonfires", []))
	seen_areas = _set_of(cfg.get_value("seen", "areas", []))
	read_runes = _set_of(cfg.get_value("seen", "runes", []))
	var fog := Marshalls.base64_to_raw(String(cfg.get_value("seen", "explored", "")))
	if fog.size() == LevelMap.W * LevelMap.H:
		explored = fog
	else:
		map_ready()
	return true


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func _set_of(keys) -> Dictionary:
	var d := {}
	for k in keys:
		d[k] = true
	return d


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
	deaths = 0
	finished = false
	play_time = 0.0
	explored = PackedByteArray()
	map_ready()


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


## Everything the stats have cost so far, so a respec can hand it all back.
static func spent_souls() -> int:
	var total := 0
	for i in level() - 1:
		total += COST_BASE + i * COST_STEP
	return total


## Wipe the build and refund every soul it cost. Free and unlimited on purpose:
## the complaint that keeps coming up about this genre is that you cannot afford
## to TRY the weapon you just found, and six weapons that all want different
## stats are worth nothing if the first ten points lock you out of five of them.
static func respec() -> int:
	var back := spent_souls()
	stats = [0, 0, 0, 0, 0]
	souls += back
	return back


# --- discovery --------------------------------------------------------------
static func key(tx: int, ty: int) -> String:
	return "%d,%d" % [tx, ty]


## Which region a tile belongs to, for naming bonfires on the travel list.
static func region_of(tx: int, ty: int) -> String:
	for a in LevelMap.AREAS:
		if tx >= int(a["x"]) and tx < int(a["x"]) + int(a["w"]) \
				and ty >= int(a["y"]) and ty < int(a["y"]) + int(a["h"]):
			return a["name"]
	return "THE KEEP"


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
