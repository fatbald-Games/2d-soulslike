"""
Level generator for Ashen Hollow.

Run:  python tools/gen_level.py
Out:  scripts/LevelMap.gd  (grid + merged colliders + entities + area rects)

The dungeon is CARVED out of solid rock: the grid starts completely filled and
rooms are cut into it. That way there is never floating geometry, never a hole
into the void, and every wall has something behind it.

The important part is at the bottom: build() only describes the layout, then
validate() proves -- with the player's real jump arc -- that every hollow,
bonfire and inscription can actually be reached from the spawn. Hand-placing a
level this size without that check means shipping a ledge nobody can stand on.
"""
import os
import sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "scripts", "LevelMap.gd")

W, H = 192, 64
TILE = 16

SOLID, AIR, PLAT, LADDER = '#', '.', '=', 'H'
PASSABLE = (AIR, PLAT, LADDER)
FOOTING = (SOLID, PLAT)

# --- player movement envelope, derived from scripts/Player.gd ----------------
# GRAVITY 900, JUMP_VELOCITY -270, SPEED 78  ->  apex 40.5px (2.5 tiles), and
# while the knight is 2 tiles up he has only carried ~13..34px sideways. So a
# two-tile step is only reachable if it is at most 2 tiles across; a one-tile
# step gets the full 3. These numbers are what validate() enforces.
MAX_RISE = 2
REACH_AT_RISE = {0: 3, 1: 3, 2: 2}
FALL_DRIFT = 3


class Level:
    def __init__(self):
        self.g = [[SOLID] * W for _ in range(H)]
        self.entities = []
        self.areas = []

    # --- terrain ---
    def carve(self, x0, y0, x1, y1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < W and 0 <= y < H:
                    self.g[y][x] = AIR

    def slab(self, x0, x1, y0, y1=None):
        y1 = y0 if y1 is None else y1
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < W and 0 <= y < H:
                    self.g[y][x] = SOLID

    def plat(self, x0, x1, y):
        """A one-way beam: you land on it from above and drop through it."""
        for x in range(x0, x1 + 1):
            if self.g[y][x] == AIR:
                self.g[y][x] = PLAT

    def ladder(self, x, y0, y1):
        """Two tiles wide so the climb is forgiving, and it PUNCHES THROUGH any
        floor slab it crosses -- that hole is what lets the top of a ladder open
        onto the walkway above instead of dead-ending under it."""
        for y in range(y0, y1 + 1):
            for xx in (x, x + 1):
                if 0 <= xx < W and 0 <= y < H:
                    self.g[y][xx] = LADDER

    def at(self, x, y):
        if 0 <= x < W and 0 <= y < H:
            return self.g[y][x]
        return SOLID

    # --- content ---
    def ent(self, kind, x, y, **kw):
        e = {"kind": kind, "x": x, "y": y}
        e.update(kw)
        self.entities.append(e)

    def torches(self, x0, x1, y, step):
        for x in range(x0, x1 + 1, step):
            self.ent("torch", x, y)

    def area(self, name, x, y, w, h):
        self.areas.append({"name": name, "x": x, "y": y, "w": w, "h": h})


def build():
    L = Level()

    # ================================================================ carve ===
    # Everything is cut first, so later slabs/ladders cannot be erased by a
    # room that happens to be carved afterwards.
    L.carve(3, 39, 51, 45)          # the gate hall, floor at y=46
    L.carve(52, 39, 66, 57)         # the descent shaft, gate level -> ossuary
    L.carve(52, 51, 188, 57)        # the ossuary, one long gallery, floor y=58
    L.carve(78, 44, 134, 57)        # its tall central hall
    L.carve(114, 58, 132, 61)       # the cinder well, sunk below the ossuary
    L.carve(172, 29, 184, 50)       # the shaft back up the east side
    L.carve(96, 21, 184, 27)        # the ramparts, floor y=28

    # ================================================================ slabs ===
    L.slab(24, 28, 45)              # a knee-high step in the gate hall
    L.slab(36, 42, 44, 45)          # and a two-tile one: this needs a jump
    # Ledges down the shaft. They start at x=54 so they touch the ladder at
    # x=52/53 -- pulled any further right and they are islands nobody can step
    # onto, which is exactly what validate() caught.
    L.slab(54, 66, 50)
    L.slab(54, 62, 54)
    L.slab(172, 178, 44)            # and the same going back up the east shaft
    L.slab(178, 184, 38)
    L.slab(172, 180, 33)            # reaches x=180 so it meets the ladder at 181

    # Stepped beams climbing the tall hall. Each sits two rows above the last
    # and OVERLAPS it horizontally -- at two tiles of rise the knight has only
    # ~2 tiles of sideways reach, so a clean gap here would be unjumpable.
    for i, (x0, x1, y) in enumerate([
            (82, 92, 56), (90, 100, 54), (98, 108, 52),
            (106, 116, 50), (114, 124, 48), (122, 132, 46)]):
        L.plat(x0, x1, y)

    # ============================================================== ladders ===
    L.ladder(52, 45, 57)            # gate hall <-> ossuary floor
    L.ladder(181, 27, 57)           # ossuary <-> ramparts (punches y=28)
    L.ladder(115, 57, 61)           # out of the cinder well

    # ================================================================ areas ===
    L.area("THE ASHEN GATE", 0, 36, 52, 12)
    L.area("THE LONG DESCENT", 52, 36, 16, 22)
    L.area("THE OSSUARY", 68, 42, 120, 16)
    L.area("THE CINDER WELL", 112, 58, 22, 6)
    L.area("THE RAMPARTS", 96, 20, 92, 9)

    # =============================================================== people ===
    L.ent("player", 6, 45)
    L.ent("bonfire", 9, 45)
    L.ent("bonfire", 124, 61)

    for x, y in [(40, 43), (60, 49), (74, 57), (88, 57), (108, 57),
                 (100, 51), (140, 57), (152, 57), (168, 57),
                 (122, 61), (128, 61), (120, 27), (150, 27)]:
        L.ent("hollow", x, y)

    # ============================================================== lighting ==
    L.torches(8, 50, 41, 10)
    for x, y in [(55, 42), (64, 46), (56, 52)]:
        L.ent("torch", x, y)
    L.torches(80, 132, 46, 10)
    L.torches(138, 186, 53, 10)
    L.torches(100, 182, 23, 11)
    for x, y in [(117, 59), (130, 59)]:
        L.ent("torch", x, y)

    # ================================================================= lore ===
    # Environmental storytelling only -- no cutscenes, no NPCs. Each stone says
    # something about why the keep is empty, and they read in the order you
    # physically reach them.
    L.ent("rune", 18, 45, text="REST HERE. THE DARK BELOW DOES NOT.")
    L.ent("rune", 46, 45,
          text="WE SEALED THE KEEP FROM WITHIN. THE HOLLOWS WERE ALREADY IN IT.")
    L.ent("rune", 58, 53, text="COUNT THE RUNGS. THERE ARE FEWER GOING UP.")
    L.ent("rune", 86, 57,
          text="THEY LAID THE DEAD IN ROWS UNTIL THERE WERE NO MORE ROWS.")
    L.ent("rune", 128, 45, text="CLIMB HIGH ENOUGH AND THE ASH LOOKS LIKE SNOW.")
    L.ent("rune", 127, 61, text="THE SECOND FIRE STILL BURNS. NO ONE LIT IT.")
    L.ent("rune", 160, 57, text="EVERY DOOR OUT OF HERE OPENS INWARD.")
    L.ent("rune", 99, 27,
          text="THE GATE AHEAD OPENS FROM THE OTHER SIDE. NOTHING ON THIS SIDE DOES.")
    return L


# ============================================================== reachability ==
def standable(L, x, y):
    """True if the knight can stand here: solid footing under him, and his
    ~26px body (this tile and the one above) clear."""
    return (L.at(x, y + 1) in FOOTING
            and L.at(x, y) in PASSABLE
            and L.at(x, y - 1) in PASSABLE)


def _fall_from(L, x, y):
    """Where he lands stepping off into column x at row y, or None if that
    column is rock or bottoms out."""
    yy = y
    while yy < H - 1:
        if L.at(x, yy) not in PASSABLE:
            return None
        if standable(L, x, yy):
            return yy
        yy += 1
    return None


def neighbours(L, node):
    kind, x, y = node
    out = []
    if kind == 'L':
        for dy in (-1, 1):
            if L.at(x, y + dy) == LADDER:
                out.append(('L', x, y + dy))
        for dx in (-1, 0, 1):
            if standable(L, x + dx, y):
                out.append(('S', x + dx, y))
        return out

    # --- on foot ---
    for dx in (-1, 1):
        for dy in (-1, 0, 1):                    # step up / along / down
            if standable(L, x + dx, y + dy) and L.at(x + dx, y + dy) in PASSABLE:
                out.append(('S', x + dx, y + dy))

    # jumps, clamped to the real arc (see REACH_AT_RISE)
    for rise in range(0, MAX_RISE + 1):
        # a ceiling stops every higher jump too, so give up on the rest
        if rise and any(L.at(x, y - k) not in PASSABLE for k in range(1, rise + 1)):
            break
        span = REACH_AT_RISE[rise]
        for dx in range(-span, span + 1):
            if standable(L, x + dx, y - rise):
                out.append(('S', x + dx, y - rise))

    # step off an edge and fall, drifting a little on the way down
    for dx in range(-FALL_DRIFT, FALL_DRIFT + 1):
        step = 1 if dx > 0 else -1
        if any(L.at(x + s * step, y) not in PASSABLE
               for s in range(1, abs(dx) + 1)):
            continue                             # walled off before he gets there
        landed = _fall_from(L, x + dx, y)
        if landed is not None:
            out.append(('S', x + dx, landed))

    # grab a ladder next to or through him
    for dx in (-1, 0, 1):
        for dy in (0, -1):
            if L.at(x + dx, y + dy) == LADDER:
                out.append(('L', x + dx, y + dy))
    return out


def reachable_from(L, start):
    seen = {start}
    q = deque([start])
    while q:
        for n in neighbours(L, q.popleft()):
            if n not in seen:
                seen.add(n)
                q.append(n)
    return seen


def validate(L):
    """Prove every placed thing can be walked to. Returns a list of problems."""
    problems = []
    spawn = next(e for e in L.entities if e["kind"] == "player")
    start = ('S', spawn["x"], spawn["y"])
    if not standable(L, spawn["x"], spawn["y"]):
        return ["player spawn at (%d,%d) is not standable" % (spawn["x"], spawn["y"])]

    seen = reachable_from(L, start)
    stand_nodes = {n for n in seen if n[0] == 'S'}

    for e in L.entities:
        if e["kind"] == "torch":
            continue                             # torches are mounted on walls
        x, y = e["x"], e["y"]
        if not standable(L, x, y):
            problems.append("%s at (%d,%d) has no footing" % (e["kind"], x, y))
        elif ('S', x, y) not in stand_nodes:
            problems.append("%s at (%d,%d) is unreachable from spawn"
                            % (e["kind"], x, y))

    # every named area must contain somewhere to actually stand
    for a in L.areas:
        got = any(a["x"] <= n[1] < a["x"] + a["w"] and a["y"] <= n[2] < a["y"] + a["h"]
                  for n in stand_nodes)
        if not got:
            problems.append("area %s has no reachable ground" % a["name"])

    total = sum(1 for y in range(H) for x in range(W) if standable(L, x, y))
    print("  reachable standing tiles: %d of %d (%.0f%%)"
          % (len(stand_nodes), total, 100.0 * len(stand_nodes) / max(1, total)))
    return problems


# ================================================================== colliders ==
def merge_rects(cells):
    """Greedy tile->rectangle merge, so the engine gets a few hundred collision
    shapes instead of twelve thousand."""
    remaining = set(cells)
    rects = []
    while remaining:
        x, y = min(remaining, key=lambda p: (p[1], p[0]))
        w = 1
        while (x + w, y) in remaining:
            w += 1
        h = 1
        while all((x + i, y + h) in remaining for i in range(w)):
            h += 1
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                remaining.discard((xx, yy))
        rects.append((x, y, w, h))
    return rects


def emit(L, solids, plats):
    q = lambda s: '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')
    out = []
    a = out.append
    a("class_name LevelMap")
    a("extends RefCounted")
    a("## GENERATED by tools/gen_level.py -- do not edit by hand.")
    a("##")
    a("## '#' solid  '.' open  '=' one-way beam  'H' ladder")
    a("")
    a("const W := %d" % W)
    a("const H := %d" % H)
    a("const TILE := %d" % TILE)
    a("")
    a("const MAP := [")
    for row in L.g:
        a("\t%s," % q("".join(row)))
    a("]")
    a("")
    a("## [x, y, w, h] in tiles.")
    a("const SOLIDS := [")
    for r in solids:
        a("\t[%d, %d, %d, %d]," % r)
    a("]")
    a("")
    a("const BEAMS := [")
    for r in plats:
        a("\t[%d, %d, %d, %d]," % r)
    a("]")
    a("")
    a("const AREAS := [")
    for ar in L.areas:
        a('\t{"name": %s, "x": %d, "y": %d, "w": %d, "h": %d},'
          % (q(ar["name"]), ar["x"], ar["y"], ar["w"], ar["h"]))
    a("]")
    a("")
    a("const ENTITIES := [")
    for e in L.entities:
        parts = ['"kind": %s' % q(e["kind"]), '"x": %d' % e["x"], '"y": %d' % e["y"]]
        if "text" in e:
            parts.append('"text": %s' % q(e["text"]))
        a("\t{%s}," % ", ".join(parts))
    a("]")
    a("")
    with open(OUT, "w") as f:
        f.write("\n".join(out))


def main():
    print("Building level ->", OUT)
    L = build()

    solid_cells = [(x, y) for y in range(H) for x in range(W) if L.g[y][x] == SOLID]
    plat_cells = [(x, y) for y in range(H) for x in range(W) if L.g[y][x] == PLAT]
    solids = merge_rects(solid_cells)
    plats = merge_rects(plat_cells)

    problems = validate(L)
    print("  %d x %d tiles (%d x %d px), %d solid rects, %d beams, %d entities"
          % (W, H, W * TILE, H * TILE, len(solids), len(plats), len(L.entities)))
    if problems:
        print("\nLAYOUT PROBLEMS:")
        for p in problems:
            print("   x %s" % p)
        sys.exit(1)

    emit(L, solids, plats)
    print("  wrote scripts/LevelMap.gd")
    print("Done.")


if __name__ == "__main__":
    main()
