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

W, H = 384, 128
TILE = 16

SOLID, AIR, PLAT, LADDER, WATER = '#', '.', '=', 'H', 'w'
## Rock with open space nowhere near it. Collides exactly like SOLID, but the
## engine skips drawing it — at 49152 tiles, working that out per frame in
## GDScript is a load-time stall, and it never changes, so it is decided here.
BURIED = 'X'
PASSABLE = (AIR, PLAT, LADDER, WATER)
FOOTING = (SOLID, PLAT, BURIED)
ROCK_DEPTH = 6                      # how deep rock is still drawn near an opening

# --- player movement envelope, derived from scripts/Player.gd ----------------
# GRAVITY 900, JUMP_VELOCITY -270, SPEED 78  ->  apex 40.5px (2.5 tiles), and
# while the knight is 2 tiles up he has only carried ~13..34px sideways. So a
# two-tile step is only reachable if it is at most 2 tiles across; a one-tile
# step gets the full 3. These numbers are what validate() enforces.
## The colour the torches burn in each region. Paired with the stone palettes in
## tools/gen_art.py (THEMES) — the same room lit differently reads as a
## different place, so these carry as much of the theming as the tiles do.
THEME_LIGHT = {
    "gate":      (1.00, 0.70, 0.40),
    "descent":   (1.00, 0.66, 0.36),
    "ossuary":   (1.00, 0.86, 0.62),
    "cistern":   (0.55, 0.90, 0.95),
    "rootworks": (0.62, 1.00, 0.66),
    "forge":     (1.00, 0.52, 0.20),
    "vault":     (0.70, 0.86, 1.00),
    "ramparts":  (0.72, 0.82, 1.00),
}

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

    def water(self, x, y):
        """Standing water: drawn over the floor, walked straight through."""
        if 0 <= x < W and 0 <= y < H and self.g[y][x] == AIR:
            self.g[y][x] = WATER

    def at(self, x, y):
        if 0 <= x < W and 0 <= y < H:
            return self.g[y][x]
        return SOLID

    # --- content ---
    def ent(self, kind, x, y, **kw):
        e = {"kind": kind, "x": x, "y": y}
        e.update(kw)
        self.entities.append(e)

    # --- dressing ---
    # Props are hung off the geometry rather than at hand-typed pixel heights:
    # ask for a chain at column x and it finds the ceiling itself, so re-cutting
    # a room cannot leave a chain floating in the middle of it.
    def ceiling_above(self, x, y):
        """Row of the first solid tile above (x, y)."""
        yy = y
        while yy > 0 and self.at(x, yy) in PASSABLE:
            yy -= 1
        return yy

    def floor_below(self, x, y):
        """Last open row above the floor under (x, y)."""
        yy = y
        while yy < H - 1 and self.at(x, yy + 1) in PASSABLE:
            yy += 1
        return yy

    def hang(self, deco, x, y, span=1, step=1):
        for xx in range(x, x + span * step, step):
            self.ent("deco", xx, self.ceiling_above(xx, y) + 1, deco=deco)

    def stand(self, deco, x, y, span=1, step=1):
        for xx in range(x, x + span * step, step):
            self.ent("deco", xx, self.floor_below(xx, y), deco=deco, stand=1)

    def torches(self, x0, x1, y, step):
        for x in range(x0, x1 + 1, step):
            self.ent("torch", x, y)

    def area(self, name, x, y, w, h, theme):
        self.areas.append({"name": name, "x": x, "y": y, "w": w, "h": h,
                           "theme": theme})


def build():
    L = Level()

    # ================================================================ carve ===
    # One continuous route: west to east and steadily downward, then back up the
    # east side and west again along the ramparts. Everything is cut first, so a
    # later slab or ladder cannot be erased by a room carved afterwards.
    L.carve(3, 40, 57, 46)          # THE ASHEN GATE          floor 47
    L.carve(58, 40, 78, 76)         # THE LONG DESCENT (shaft down to the bones)
    L.carve(58, 70, 168, 76)        # THE OSSUARY gallery      floor 77
    L.carve(92, 58, 152, 76)        #   its tall hall, full of beams
    L.carve(156, 70, 174, 92)       #   shaft down to the water
    L.carve(168, 84, 252, 92)       # THE FLOODED CISTERN      floor 93
    L.carve(240, 84, 258, 108)      #   shaft down into the roots
    L.carve(252, 100, 312, 108)     # THE ROOTWORKS            floor 109
    L.carve(296, 100, 312, 124)     #   shaft down to the fires
    L.carve(300, 116, 382, 124)     # THE EMBER FORGE          floor 125

    # THE FROZEN VAULT: the way back up is a stair of chambers, not one endless
    # ladder — 80 tiles of unbroken climbing is a held key, not a level.
    L.carve(340, 102, 382, 114)     # V1  floor 115
    L.carve(316, 86, 358, 100)      # V2  floor 101
    L.carve(340, 70, 382, 84)       # V3  floor 85
    L.carve(316, 54, 358, 68)       # V4  floor 69
    L.carve(340, 38, 382, 52)       # V5  floor 53
    L.carve(316, 28, 358, 36)       # V6  floor 37

    L.carve(90, 19, 339, 26)        # THE RAMPARTS             floor 27

    # ================================================================ slabs ===
    L.slab(24, 28, 46)              # a knee-high step in the gate hall
    L.slab(36, 42, 45, 46)          # and a two-tile one: this needs a jump
    # Ledges down the descent. They start at x=60 so they touch the ladder at
    # x=58/59 — pulled further right they are islands nobody can step onto.
    L.slab(60, 78, 52)
    L.slab(60, 70, 60)
    L.slab(60, 78, 68)

    # Stepped beams climbing the ossuary's tall hall. Each sits two rows above
    # the last and OVERLAPS it — at two tiles of rise the knight has only ~2
    # tiles of sideways reach, so a clean gap here would be unjumpable.
    # floor is 77, so the first beam sits at 75 (stand 74, two rows up) and each
    # one after it steps another two — three rows would be unjumpable
    for x0, x1, y in [(96, 106, 75), (104, 114, 73), (112, 122, 71),
                      (120, 130, 69), (128, 138, 67), (136, 148, 65)]:
        L.plat(x0, x1, y)

    # Cistern: stepping stones over the water, and a sunken basin.
    for x0, x1, y in [(184, 196, 91), (194, 206, 89), (204, 216, 91),
                      (226, 238, 91)]:
        L.plat(x0, x1, y)

    # Rootworks: shelves of fungus to climb between.
    for x0, x1, y in [(262, 272, 107), (270, 280, 105), (286, 296, 107)]:
        L.plat(x0, x1, y)

    # Forge: catwalks over the floor.
    for x0, x1, y in [(310, 324, 123), (320, 334, 121), (344, 358, 123)]:
        L.plat(x0, x1, y)

    # Ramparts: the odd broken section, so the long walk is not flat.
    L.slab(150, 156, 25, 26)
    L.slab(232, 238, 25, 26)

    # ============================================================== ladders ===
    L.ladder(58, 46, 76)            # gate hall  <-> ossuary floor
    L.ladder(158, 76, 92)           # ossuary    <-> cistern
    L.ladder(242, 92, 108)          # cistern    <-> rootworks
    L.ladder(298, 108, 124)         # rootworks  <-> forge
    L.ladder(370, 114, 124)         # forge      <-> vault V1
    L.ladder(346, 100, 114)         # V1 <-> V2
    L.ladder(350, 84, 100)          # V2 <-> V3
    L.ladder(346, 68, 84)           # V3 <-> V4
    L.ladder(350, 52, 68)           # V4 <-> V5
    L.ladder(346, 36, 52)           # V5 <-> V6
    L.ladder(330, 26, 36)           # V6 <-> the ramparts

    # ================================================================ water ===
    # Standing water on the cistern floor. Passable — you wade through it.
    for x in range(168, 252):
        L.water(x, 92)

    # ================================================================ areas ===
    # Disjoint rects: area_at() returns the first match, so overlapping regions
    # would make the banner depend on declaration order.
    L.area("THE ASHEN GATE", 0, 33, 58, 17, "gate")
    L.area("THE LONG DESCENT", 58, 33, 20, 45, "descent")
    L.area("THE OSSUARY", 78, 55, 90, 24, "ossuary")
    L.area("THE FLOODED CISTERN", 168, 80, 84, 15, "cistern")
    L.area("THE ROOTWORKS", 252, 96, 62, 15, "rootworks")
    L.area("THE EMBER FORGE", 300, 111, 84, 17, "forge")
    L.area("THE FROZEN VAULT", 314, 28, 70, 83, "vault")
    L.area("THE RAMPARTS", 90, 16, 250, 12, "ramparts")

    # =============================================================== people ===
    L.ent("player", 6, 46)
    L.ent("bonfire", 9, 46)         # the gate
    L.ent("bonfire", 120, 76)       # the ossuary
    L.ent("bonfire", 350, 124)      # the forge

    for x, y in [(40, 44), (62, 51), (68, 59), (74, 76), (86, 76), (100, 76),
                 (116, 70), (130, 76), (146, 76), (150, 76),
                 (176, 92), (200, 92), (222, 92), (234, 92),
                 (258, 108), (276, 104), (286, 108), (272, 108),
                 (306, 124), (326, 124), (344, 124), (364, 124),
                 (352, 114), (330, 100), (360, 84), (330, 68), (360, 52),
                 (120, 26), (180, 26), (250, 26), (300, 26)]:
        L.ent("hollow", x, y)

    # ============================================================== lighting ==
    L.torches(6, 54, 42, 6)                                    # gate
    for x, y in [(62, 43), (74, 48), (64, 56), (72, 64)]:       # descent
        L.ent("torch", x, y)
    L.torches(80, 166, 73, 11)                                 # ossuary gallery
    L.torches(96, 148, 61, 12)                                 #   tall hall
    L.torches(172, 250, 87, 11)                                # cistern
    L.torches(256, 312, 103, 11)                               # rootworks
    L.torches(304, 380, 119, 11)                               # forge
    L.torches(94, 336, 21, 14)                                 # ramparts
    for x, y in [(344, 106), (322, 90), (346, 74), (322, 58), (346, 42), (322, 31)]:
        L.ent("torch", x, y)                                    # vault chambers

    # Region flavour: fungus lights the roots, braziers roar in the forge.
    for x in range(256, 295, 7):        # past 295 the floor is the forge shaft
        L.ent("mushroom", x, 108)
    for x, y in [(268, 106), (276, 104), (290, 106)]:
        L.ent("mushroom", x, y)
    for x in range(306, 380, 12):
        L.ent("brazier", x, 124)

    # ============================================================== dressing ==
    # Eight regions that differ only in hue still look like eight repaints of
    # one corridor. What actually says "somewhere else" is SHAPE in the middle
    # distance: chains in the shaft, bones in the ossuary, icicles in the vault.
    # These hang between the back wall and the stone, so they read as depth.
    L.hang("banner", 14, 44, 3, 18)                     # the gate
    L.stand("pillar", 26, 46, 2, 20)
    L.hang("arch", 34, 44)
    L.hang("chain", 60, 50, 4, 5)                       # the descent shaft
    L.hang("chain", 62, 66, 3, 6)
    L.stand("bones", 82, 76, 7, 12)                     # the ossuary
    L.stand("skull_spike", 88, 76, 5, 17)
    L.hang("chain", 100, 62, 4, 14)
    L.stand("pillar", 108, 76, 3, 22)
    L.hang("arch", 130, 74)
    L.hang("chain", 174, 92, 5, 16)                     # the cistern
    L.stand("pillar", 186, 92, 3, 24)
    L.hang("arch", 214, 90)
    L.hang("roots", 256, 108, 8, 7)                     # the rootworks
    L.stand("bones", 262, 108, 3, 15)
    L.hang("chain", 306, 124, 5, 15)                    # the forge
    L.hang("banner", 314, 122, 3, 22)
    L.stand("pillar", 322, 124, 3, 20)
    L.hang("icicles", 318, 100, 10, 6)                  # the frozen vault
    L.hang("icicles", 320, 68, 8, 7)
    L.stand("bones", 330, 84, 2, 24)
    L.hang("banner", 100, 26, 5, 40)                    # the ramparts
    L.stand("pillar", 118, 26, 6, 38)
    L.stand("skull_spike", 136, 26, 5, 44)

    # ============================================================== armoury ===
    # Five weapons, one per region, each of them a detour off the main route.
    # Placing them here rather than in Main means the reachability proof below
    # has to agree that you can actually get to every one of them — a weapon you
    # can see and never reach would be the worst possible version of this.
    L.ent("weapon", 96, 76, weapon="axe")          # the ossuary
    L.ent("weapon", 212, 92, weapon="spear")       # the flooded cistern
    L.ent("weapon", 264, 108, weapon="shield")     # the rootworks
    L.ent("weapon", 338, 68, weapon="crossbow")    # the frozen vault
    L.ent("weapon", 210, 26, weapon="bow")         # the ramparts

    # ================================================================= lore ===
    # Environmental storytelling only - no cutscenes, no NPCs. One voice: the
    # last keeper, who stayed behind to tend the fires and kept carving further
    # in. The stones read in the order you physically reach them, and the route
    # loops back west along the ramparts, so the last one you find is the one
    # that turns the whole thing around on you.
    L.ent("rune", 18, 46, text="REST HERE. THE DARK BELOW DOES NOT.")
    L.ent("rune", 30, 46,
          text="WE SEALED IT FROM WITHIN. I HAVE HAD TIME TO CONSIDER THAT.")
    L.ent("rune", 46, 46,
          text="THE HOLLOWS WERE ALREADY INSIDE WHEN THE GATE CAME DOWN.")
    L.ent("rune", 62, 59,
          text="COUNT THE RUNGS ON THE WAY DOWN. THERE ARE FEWER GOING UP.")
    L.ent("rune", 92, 76,
          text="THEY LAID THE DEAD IN ROWS UNTIL THERE WERE NO MORE ROWS.")
    L.ent("rune", 140, 76,
          text="I KNEW EVERY NAME DOWN HERE. I STOPPED WRITING AT FOUR HUNDRED.")
    L.ent("rune", 144, 64, text="CLIMB HIGH ENOUGH AND THE ASH LOOKS LIKE SNOW.")
    L.ent("rune", 190, 92,
          text="THE CISTERN FED THE KEEP. NOW IT ONLY KEEPS THINGS.")
    L.ent("rune", 222, 92,
          text="SOMETHING TURNED THE WATER. I LOOKED FOR YEARS. NEVER SAW IT.")
    L.ent("rune", 234, 92, text="DO NOT DRINK. WE LEARNED THAT ONE TOGETHER.")
    L.ent("rune", 266, 108,
          text="THE ROOTS CAME UP THROUGH THE FLOOR AND NOBODY PULLED THEM OUT.")
    L.ent("rune", 280, 108, text="SOMETHING DOWN HERE STILL GROWS. NOTHING ELSE DOES.")
    L.ent("rune", 286, 108,
          text="IF YOU FOUND THE SPEAR, THE MAN WHO CARRIED IT GOT THIS FAR.")
    L.ent("rune", 306, 124, text="I TEND THE FIRES. THAT IS THE WHOLE OF IT NOW.")
    L.ent("rune", 320, 124,
          text="THE FIRES WERE NEVER BANKED. WHOEVER TENDS THEM HAS NOT SLEPT.")
    L.ent("rune", 370, 124, text="EVERY DOOR OUT OF HERE OPENS INWARD.")
    L.ent("rune", 330, 68,
          text="WE PUT THE ARMOURY IN THE COLD SO IT WOULD OUTLAST US. IT HAS.")
    L.ent("rune", 356, 84, text="THE COLD KEEPS THEM. THAT IS ALL IT IS FOR.")
    L.ent("rune", 358, 52,
          text="I COUNTED THE FLOORS ON THE WAY DOWN. THE NUMBER HAS CHANGED.")
    L.ent("rune", 300, 26, text="FROM HERE YOU CAN SEE HOW FAR YOU FELL.")
    L.ent("rune", 250, 26, text="THE ASH ON THIS WALL IS NOT FROM THE FORGE.")
    L.ent("rune", 180, 26, text="I WALKED THIS WALL EVERY NIGHT. IT HELPED, FOR A WHILE.")
    L.ent("rune", 112, 26,
          text="THE GATE AHEAD OPENS FROM THE OTHER SIDE. NOTHING HERE DOES.")
    # The last stone on the route, and the only one that is about you. Reading
    # it ends the run - marked here rather than hard-coded in Main, so moving it
    # moves the ending with it.
    L.ent("rune", 96, 26, text="YOU CAME IN THROUGH THAT GATE. SO DID I.", final=1)
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
        if e["kind"] in ("torch", "deco"):
            continue                # both are mounted on the geometry, not stood on
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


def bury(L):
    """Replace rock that no opening comes within ROCK_DEPTH of with BURIED, so
    the engine can skip drawing it. Runs after validate(), which therefore only
    ever sees plain SOLID."""
    buried = 0
    for y in range(H):
        for x in range(W):
            if L.g[y][x] != SOLID:
                continue
            exposed = False
            for dy in range(-ROCK_DEPTH, ROCK_DEPTH + 1):
                for dx in range(-ROCK_DEPTH, ROCK_DEPTH + 1):
                    if L.at(x + dx, y + dy) not in (SOLID, BURIED):
                        exposed = True
                        break
                if exposed:
                    break
            if not exposed:
                L.g[y][x] = BURIED
                buried += 1
    return buried


def theme_map(L):
    """One theme index per tile, by NEAREST area rather than only inside one.

    The area rects only cover the rooms themselves, so every tile between them
    - all the rock, and the shafts joining one region to the next - used to
    fall back to area 0 and get drawn in the gate's blue stone. That put a hard
    seam of the wrong colour under half the map. Nearest-rect instead lets each
    region's stone bleed outward until it meets the next one's.
    """
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            best, best_d = 0, None
            for i, a in enumerate(L.areas):
                dx = max(a["x"] - x, 0, x - (a["x"] + a["w"] - 1))
                dy = max(a["y"] - y, 0, y - (a["y"] + a["h"] - 1))
                d = dx * dx + dy * dy
                if best_d is None or d < best_d:
                    best, best_d = i, d
            row.append(str(best))
        rows.append("".join(row))
    return rows


def emit(L, solids, plats):
    q = lambda s: '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')
    out = []
    a = out.append
    a("class_name LevelMap")
    a("extends RefCounted")
    a("## GENERATED by tools/gen_level.py -- do not edit by hand.")
    a("##")
    a("## '#' solid   'X' solid but buried (never drawn)   '.' open")
    a("## '=' one-way beam   'H' ladder   'w' water")
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
    a("## One area index per tile, by nearest area rect (see theme_map). This is")
    a("## what stone each tile is drawn in - NOT which region you are standing")
    a("## in, which is AREAS and only covers the named rooms.")
    a("const THEME_OF := [")
    for row in theme_map(L):
        a("\t%s," % q(row))
    a("]")
    a("")
    a("const AREAS := [")
    for ar in L.areas:
        lit = THEME_LIGHT[ar["theme"]]
        a('\t{"name": %s, "x": %d, "y": %d, "w": %d, "h": %d, '
          '"theme": %s, "light": [%.3f, %.3f, %.3f]},'
          % (q(ar["name"]), ar["x"], ar["y"], ar["w"], ar["h"],
             q(ar["theme"]), lit[0], lit[1], lit[2]))
    a("]")
    a("")
    a("const ENTITIES := [")
    for e in L.entities:
        parts = ['"kind": %s' % q(e["kind"]), '"x": %d' % e["x"], '"y": %d' % e["y"]]
        if "text" in e:
            parts.append('"text": %s' % q(e["text"]))
        if "weapon" in e:
            parts.append('"weapon": %s' % q(e["weapon"]))
        if "final" in e:
            parts.append('"final": %d' % e["final"])
        if "deco" in e:
            parts.append('"deco": %s' % q(e["deco"]))
            parts.append('"stand": %d' % e.get("stand", 0))
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

    buried = bury(L)
    print("  %d rock tiles buried (never drawn)" % buried)
    emit(L, solids, plats)
    print("  wrote scripts/LevelMap.gd")
    print("Done.")


if __name__ == "__main__":
    main()
