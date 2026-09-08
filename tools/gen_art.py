"""
Pixel-art generator for the 2D soulslike ("Ashen Hollow").
Hand-authored sprite grids + procedural stone tiles, rendered to PNGs.

Run:  python tools/gen_art.py
Output: assets/sprites/*.png  and  tools/preview.png (mood shot for inspection)

Everything is authored at native (tiny) resolution and meant to be shown with
nearest-neighbour scaling (see project.godot -> import defaults).
"""
import os
import math
import random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")
os.makedirs(OUT, exist_ok=True)

T = (0, 0, 0, 0)  # transparent

# ---------------------------------------------------------------- palette ----
# A tight, muted dark-fantasy palette with warm firelight + a soul-cyan accent.
PAL = {
    '.': T,
    'o': (13, 11, 18, 255),     # near-black outline
    # cloak
    'k': (31, 27, 41, 255),     # cloak darkest
    'c': (49, 43, 63, 255),     # cloak mid
    'h': (76, 68, 94, 255),     # cloak highlight
    'H': (112, 98, 128, 255),   # cloak rim (fire-lit)
    # face
    'f': (20, 17, 27, 255),     # face cavity (near-black, darker than cloak)
    'e': (150, 230, 214, 255),  # eye glow (soul cyan)
    # steel / sword
    'd': (58, 64, 76, 255),     # steel dark
    's': (128, 138, 154, 255),  # steel mid
    'S': (196, 205, 220, 255),  # steel light
    'g': (150, 120, 66, 255),   # brass guard
    # leather
    'l': (58, 42, 34, 255),     # leather
    'L': (92, 66, 48, 255),     # leather light
    # boots / metal-dark
    'b': (24, 21, 30, 255),
    # bone
    'n': (70, 66, 74, 255),     # bone dark
    'N': (150, 146, 150, 255),  # bone light
    # fire
    'r': (120, 30, 20, 255),    # ember deep
    'R': (224, 96, 42, 255),    # fire orange
    'a': (255, 159, 67, 255),   # fire amber
    'y': (255, 233, 168, 255),  # fire core (light)
    # slash / highlight
    'W': (232, 240, 252, 255),   # blade flash
    # --- the dark knight ---
    'A': (26, 28, 36, 255),      # armour darkest (reads as its own outline)
    'B': (44, 48, 60, 255),      # armour dark
    'C': (68, 74, 90, 255),      # armour mid
    'D': (100, 108, 128, 255),   # armour light (plate highlight)
    'E': (142, 150, 172, 255),   # armour rim, lit by the fire on the right
    'm': (48, 24, 28, 255),      # cape dark
    'M': (76, 36, 38, 255),      # cape mid
    'Z': (255, 74, 58, 255),     # glowing red eye — the only warm accent
    'z': (168, 34, 28, 255),     # eye halo
    # enemy "hollow"
    'p': (138, 128, 112, 255),   # dead pale flesh
    'P': (172, 162, 144, 255),   # pale highlight
    'q': (44, 46, 40, 255),      # rag dark
    'Q': (70, 74, 60, 255),      # rag mid
    'x': (104, 66, 42, 255),     # rusted steel
    'X': (146, 100, 60, 255),    # rust highlight
    'v': (104, 30, 26, 255),     # wound / ember eye
    # stone (also used procedurally below)
    '1': (24, 22, 32, 255),
    '2': (40, 39, 54, 255),
    '3': (58, 56, 78, 255),
    '4': (82, 80, 106, 255),
}


def grid_to_img(rows, pal=PAL):
    """rows: list[str] of equal length -> RGBA Image."""
    w = max(len(r) for r in rows)
    h = len(rows)
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            col = pal.get(ch, T)
            if col[3]:
                px[x, y] = col
    return img


def hsheet(frames):
    """Combine equal-size frames horizontally into one sheet Image."""
    w = frames[0].width
    h = frames[0].height
    sheet = Image.new("RGBA", (w * len(frames), h), T)
    for i, f in enumerate(frames):
        sheet.paste(f, (i * w, 0))
    return sheet


def shift(rows, dy):
    """Shift a grid vertically by dy (down positive), padding with '.'."""
    w = len(rows[0])
    blank = '.' * w
    if dy > 0:
        return [blank] * dy + rows[:-dy]
    if dy < 0:
        return rows[-dy:] + [blank] * (-dy)
    return list(rows)


# ================================================================ PLAYER =====
# The Dark Knight — side view facing RIGHT. 24 wide x 28 tall, feet on row 27.
#
# Silhouette (what makes it read at this size):
#   * a visored helm with TWO glowing red eyes — the only warm accent anywhere
#   * broad angular pauldrons, so the shape says "knight", not "robed figure"
#   * a cinched waist, flared tassets, and armoured legs that split cleanly
#   * a dark cape trailing behind (left), giving the silhouette some motion
#
# The ARMOUR is centred on column 11 so that pasting it at BODY_OX makes the
# body sit exactly on the frame anchor — mirroring for "facing left" then keeps
# the knight in place instead of sliding him sideways.
# No sword here: the blade is drawn procedurally in every animation so the
# idle, run and attack poses all share one consistent weapon.
PLAYER = [
    "..........oAAo",          # 0  helm crown
    ".........oABBAo",         # 1
    "........oABBCCAo",        # 2
    "........oABCCCBo",        # 3
    ".......oABCCCCBEo",       # 4
    ".......oAffZfZfBEo",      # 5  visor slit — two red eyes
    ".......oABffffBEo",       # 6
    "........oABCCBEo",        # 7
    ".........oABBEo",         # 8  gorget
    ".....oAABBBCBBBAAo",      # 9  pauldrons flare out
    "...moAABBBCCCBBBAAo",     # 10 widest point + cape begins
    "..mMoABBBCCCCCBBBEo",     # 11
    "..mMmoABBCCDDCCBBEo",     # 12 breastplate highlight
    "..mMMmoABCCDDCCBEo",      # 13
    ".mMMMmoABCCDDCCBEo",      # 14
    ".mMMMmoABBCCCCBBEo",      # 15
    ".mMMMMmoABCCCCBEo",       # 16 waist narrows
    ".mMMMMmoABgggBBEo",       # 17 belt
    ".mMMMmoABBCCCCBBEo",      # 18 tassets flare
    "..mMMmoABCCCCCCBEo",      # 19
    "..mMMmoABCCCCCCBEo",      # 20
    "...mMMmoABCCCCBEo",       # 21
    "...mMMoBCCo..oBCCEo",     # 22 legs split — the gap must be TRANSPARENT,
    "....mMoBCCo..oBCCEo",     # 23    outline pixels vanish on a dark ground
    ".....moBCCo..oBCCEo",     # 24
    "......oABCo..oABCo",      # 25
    ".....oAABBo..oAABBo",     # 26 sabatons
    ".....oAAAAo..oAAAAo",     # 27
]


# ================================================================ TILES =======
def stone_floor(seed=1):
    random.seed(seed)
    img = Image.new("RGBA", (16, 16), PAL['2'])
    px = img.load()
    shades = [PAL['1'], PAL['2'], PAL['2'], PAL['3']]
    for y in range(16):
        for x in range(16):
            px[x, y] = random.choice(shades)
    # subtle flagstone seams (cross grid, offset)
    for x in range(16):
        px[x, 0] = PAL['1']
        px[x, 8] = PAL['1']
    for y in range(16):
        px[0, y] = PAL['1']
        px[8, y] = PAL['1']
    # a few lighter chips + moss speckle
    for _ in range(10):
        x, y = random.randint(1, 15), random.randint(1, 15)
        px[x, y] = PAL['3']
    for _ in range(4):
        x, y = random.randint(1, 15), random.randint(1, 15)
        px[x, y] = (46, 62, 50, 255)  # moss
    return img


# ========================================================== THEMED TILES ======
# Each region gets its own stone. At 16x16 in a dark palette the thing that
# actually reads as "somewhere else" is the COLOUR RAMP plus one signature
# speckle — piling on extra detail at this size just turns into noise.
#
# The matching torch colour lives in tools/gen_level.py (THEME_LIGHT) — that is
# level data, not art. It is half the effect either way: cold blue stone lit
# warm orange still reads as the same room you just left.

## How many variants of each stone tile get generated. Level.gd must agree.
TILE_VARIANTS = 4

THEMES = {
    "gate": {
        "ramp": [(24, 22, 32), (40, 39, 54), (58, 56, 78), (82, 80, 106)],
        "detail": "moss"},
    "descent": {
        "ramp": [(18, 18, 28), (32, 34, 48), (48, 50, 68), (68, 72, 94)],
        "detail": "none"},
    "ossuary": {
        "ramp": [(34, 31, 27), (54, 50, 43), (76, 71, 60), (104, 98, 84)],
        "detail": "bone"},
    "cistern": {
        "ramp": [(16, 26, 30), (26, 44, 50), (38, 64, 70), (56, 90, 96)],
        "detail": "algae"},
    "rootworks": {
        "ramp": [(24, 18, 30), (40, 30, 48), (56, 44, 66), (78, 62, 88)],
        "detail": "spore", "speck": 0.5},
    "forge": {
        # pulled back from a full-saturation red: a whole screen of it was one
        # loud colour with the knight lost somewhere inside it
        "ramp": [(30, 21, 19), (50, 34, 28), (72, 48, 38), (98, 64, 46)],
        # sparse on purpose: at full density the embers stopped being sparks in
        # the stone and became the stone
        "detail": "ember", "speck": 0.35},
    "vault": {
        "ramp": [(28, 34, 44), (46, 56, 72), (68, 82, 102), (96, 116, 140)],
        "detail": "ice", "speck": 0.7},
    "ramparts": {
        "ramp": [(22, 24, 34), (36, 40, 54), (52, 58, 76), (74, 82, 104)],
        "detail": "none"},
}

DETAIL_COLOURS = {
    "moss": (46, 62, 50), "bone": (150, 143, 124), "algae": (44, 96, 78),
    "spore": (110, 176, 104), "ember": (198, 88, 36), "ice": (168, 200, 224),
}


def _rgba(c):
    return (c[0], c[1], c[2], 255)


def _speckle(px, rng, kind, count, w=16, h=16):
    """The one flourish that names a region: moss, bone chips, algae, spores,
    ember cracks or frost."""
    if kind == "none":
        return
    col = _rgba(DETAIL_COLOURS[kind])
    for _ in range(count):
        x, y = rng.randint(1, w - 2), rng.randint(1, h - 2)
        px[x, y] = col
        if kind == "ember":                    # cracks run downward
            px[x, min(h - 1, y + 1)] = _rgba((132, 48, 20))
        elif kind == "bone":                   # chips catch the light on top
            px[x, max(0, y - 1)] = _rgba((92, 86, 74))
        elif kind == "spore":                  # a bright core inside a halo
            px[min(w - 1, x + 1), y] = _rgba((60, 108, 64))
        elif kind == "ice":
            px[min(w - 1, x + 1), min(h - 1, y + 1)] = _rgba((116, 150, 178))


def themed_floor(theme, seed):
    t = THEMES[theme]
    r = t["ramp"]
    rng = random.Random(seed)
    img = Image.new("RGBA", (16, 16), _rgba(r[1]))
    px = img.load()
    shades = [_rgba(r[0]), _rgba(r[1]), _rgba(r[1]), _rgba(r[2])]
    for y in range(16):
        for x in range(16):
            px[x, y] = rng.choice(shades)
    for x in range(16):                        # flagstone seams
        px[x, 0] = _rgba(r[0])
        px[x, 8] = _rgba(r[0])
    for y in range(16):
        px[0, y] = _rgba(r[0])
        px[8, y] = _rgba(r[0])
    for _ in range(10):
        px[rng.randint(1, 15), rng.randint(1, 15)] = _rgba(r[2])
    _speckle(px, rng, t["detail"], int(round(5 * t.get("speck", 1.0))))
    return img


def themed_wall(theme, seed):
    t = THEMES[theme]
    r = t["ramp"]
    rng = random.Random(seed)
    dark = _rgba((max(0, r[0][0] - 6), max(0, r[0][1] - 6), max(0, r[0][2] - 8)))
    img = Image.new("RGBA", (16, 16), _rgba(r[0]))
    px = img.load()
    base = [_rgba(r[0]), _rgba(r[1]), _rgba(r[1])]
    for y in range(16):
        for x in range(16):
            px[x, y] = rng.choice(base)
    for y in (0, 5, 10, 15):                   # brick courses
        for x in range(16):
            px[x, y] = dark
    for band, y in enumerate((2, 7, 12)):      # staggered head joints
        off = 0 if band % 2 == 0 else 8
        for vx in (off % 16, (off + 8) % 16):
            for yy in range(y - 2, y + 3):
                if 0 <= yy < 16:
                    px[vx, yy] = dark
    for y in (1, 6, 11):                       # lit top of each course
        for x in range(16):
            if px[x, y] != dark:
                px[x, y] = _rgba(r[2])
    _speckle(px, rng, t["detail"], int(round(3 * t.get("speck", 1.0))))
    return img


# --- the lit top surface of solid ground -------------------------------------
# Without this every region was one flat field of noise: you could not see where
# the floor you stand on ENDED and the wall behind it began. A crust on the top
# face — ash, bone chips, wet algae, roots, embers, frost — is what turns a
# tiled texture back into ground.
CAP_COLOURS = {
    "gate":      [(96, 92, 104), (62, 59, 74)],     # ash dust
    "descent":   [(76, 80, 100), (46, 48, 66)],     # bare lit lip
    "ossuary":   [(164, 156, 136), (110, 103, 88)],  # bone chips
    "cistern":   [(70, 126, 102), (34, 76, 68)],    # wet algae
    "rootworks": [(104, 158, 96), (52, 94, 58)],    # moss and rootlets
    "forge":     [(186, 92, 40), (112, 46, 22)],    # cooling embers
    "vault":     [(196, 220, 238), (130, 162, 192)],  # frost
    "ramparts":  [(204, 208, 220), (134, 142, 162)],  # wind-blown ash
}


def themed_cap(theme, seed):
    """A floor tile with its top face crusted over and lit.

    The crust is 2-3px of ragged material, then a dark seam a couple of rows
    down. The seam matters as much as the crust: it is the shadow that makes
    the lip read as an edge you could stand on rather than a change of colour.
    """
    img = themed_floor(theme, seed)
    px = img.load()
    hi, lo = [_rgba(c) for c in CAP_COLOURS[theme]]
    dark = _rgba(THEMES[theme]["ramp"][0])
    rng = random.Random(seed * 31 + 7)
    for x in range(16):
        h = 2 + (1 if rng.random() < 0.42 else 0)
        for y in range(h):
            px[x, y] = hi if y == 0 else lo
        if rng.random() < 0.24:                 # material dribbling down the face
            px[x, h] = lo
    for x in range(16):                         # the shadow under the crust
        if rng.random() < 0.72:
            px[x, 4] = dark
    return img


# ================================================================== DECO ======
# Silhouettes hung in the open space in front of the back wall. They are drawn
# almost black on purpose: the point is to break up a flat brick field with
# SHAPE, not to add another competing texture. Level.gd tints each one with its
# region's stone colour, so one sheet dresses all eight.
#
# 16x32 frames, anchored top-left; things that hang use the top rows, things
# that stand use the bottom.
# Pitched to sit in the same range as the stone ramps: the props are darkened
# twice over on the way to the screen (the region's ambient, then their own
# tint), and at true silhouette values they simply vanished.
DECO_PAL = {
    '.': T,
    'o': (26, 24, 33, 255),      # silhouette core
    'd': (52, 49, 64, 255),      # body
    'm': (84, 80, 100, 255),     # lit side
    'l': (124, 118, 140, 255),   # rim highlight
    'b': (132, 126, 112, 255),   # bone / pale
    'B': (186, 178, 160, 255),
}

DECO_CHAIN = [
    "......dm........", "......om........", "......dm........", ".....odmo.......",
    ".....o..o.......", ".....odmo.......", "......dm........", "......om........",
    "......dm........", ".....odmo.......", ".....o..o.......", ".....odmo.......",
    "......dm........", "......om........", "......dm........", ".....odmo.......",
    ".....o..o.......", ".....odmo.......", "......dm........", "......om........",
    "......dm........", ".....odmo.......", ".....o..o.......", ".....odmo.......",
    "......dm........", "......om........", "....oodmoo......", "...od....do.....",
    "...o.dmmm.o.....", "....o.dm.o......", ".....oooo.......", "................",
]

DECO_PILLAR = [
    "..oddmmmmlddo...", "..od........do..", "..oddmmmmlddo...", "...odmmmmld o...",
    "...od mmmml do..", "....odmmmmldo...", "....od mmml do..", "....odmmmmldo...",
    "....o.dmmml.o...", "....odmmmmldo...", "....od.mml..o...", "....odmmmmldo...",
    "....odmmm.ldo...", "....odmmmmldo...", "....o..mml..o...", "....odmmmmldo...",
    "....odmmmmldo...", "....od.mmml.o...", "....odmmmmldo...", "....odmm.mldo...",
    "....odmmmmldo...", "....o.dmmml.o...", "....odmmmmldo...", "....odmmmmldo...",
    "...odmmmmmmldo..", "...od........do.", "..oddmmmmmmlddo.", "..od.........do.",
    "..oddmmmmmmlddo.", "...o.........o..", "................", "................",
]

DECO_BONES = [
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    "................", "................", "..........bo....", ".........obBbo..",
    ".....bo...ob.bo.", "....obBbo..obbo.", "...ob...bo..oo..", "..bo.bo..b......",
    ".obBbo.obBbo....", "ob...bo....bo...", ".....b..bo...b..", "obbo..obBbo.obo.",
    "o..bo.b...bo.b..", "obbbo.obbbbo.bo.", "oooooooooooooooo", "................",
]

DECO_ROOTS = [
    ".......dm.......", "......odmo......", "......dm.o......", ".....odm..o.....",
    ".....dm...dm....", "....odmo..om....", "....dm.....dm...", "...odm..o..om...",
    "...dm...dm..dm..", "..odmo..om..om..", "..dm.....dm.dm..", ".odm..o..om.om..",
    ".dm...dm..dm.dm.", "odmo..om..om.om.", "dm.....dm.dm.dm.", "m..o...om.om.om.",
    "...dm...dm.dm.m.", "...om...om.om...", "....dm...dm.m...", "....om...om.....",
    ".....dm...m.....", ".....om.........", "......m.........", "................",
    "................", "................", "................", "................",
    "................", "................", "................", "................",
]

DECO_ICICLES = [
    "oBbo.obBbo.oBbo.", "oBbo.obBbo.oBbo.", ".Bbo.obBbo.oBb..", ".Bb..obBbo..Bb..",
    ".Bb..obBbo..Bb..", ".b...obBb...b...", ".b....bBb...b...", ".b....bBb...b...",
    "......bBb.......", "......bBb.......", "......bB........", "......bB........",
    ".......b........", ".......b........", "................", "................",
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    "................", "................", "................", "................",
]

DECO_BANNER = [
    "oooooooooooooooo", "od############do", ".od##########do.", ".od##########do.",
    ".od##########do.", ".od##########do.", ".od##########do.", ".od####@#####do.",
    ".od###@@@####do.", ".od##@@@@@###do.", ".od###@@@####do.", ".od####@#####do.",
    ".od##########do.", ".od##########do.", ".od##########do.", ".od##########do.",
    ".od##########do.", ".od##########do.", ".od##########do.", ".od##########do.",
    ".od#########do..", ".od########do...", "..od######do....", "...od####do.....",
    "....od##do......", ".....odo........", "................", "................",
    "................", "................", "................", "................",
]

DECO_SKULL_SPIKE = [
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    "................", "......bBb.......", ".....obBBbo.....", ".....bB..Bb.....",
    ".....bo..ob.....", ".....bBbbBb.....", "......bBBb......", ".......dm.......",
    ".......dm.......", ".......dm.......", ".......dm.......", ".......dm.......",
    ".......dm.......", ".......dm.......", ".......dm.......", ".......dm.......",
    ".......dm.......", ".......dm.......", ".......dm.......", ".......dm.......",
    "......odmo......", ".....od..do.....", "....o......o....", "................",
]

DECO_ARCH = [
    "oooooooooooooooo", "od############do", "odm##########mdo", "odmm########mmdo",
    "odmmm######mmmdo", "odmmml####lmmmdo", "odmmm.l##l.mmmdo", "odmm...ll...mmdo",
    "odm..........mdo", "od............do", "od............do", "od............do",
    "od............do", "od............do", "od............do", "od............do",
    "od............do", "od............do", "od............do", "od............do",
    "od............do", "od............do", "od............do", "od............do",
    "od............do", "od............do", "od............do", "od............do",
    "od############do", "oooooooooooooooo", "................", "................",
]

DECO_NAMES = ["chain", "pillar", "bones", "roots", "icicles", "banner",
              "skull_spike", "arch"]
DECO_GRIDS = [DECO_CHAIN, DECO_PILLAR, DECO_BONES, DECO_ROOTS, DECO_ICICLES,
              DECO_BANNER, DECO_SKULL_SPIKE, DECO_ARCH]


def deco_frames():
    pal = dict(DECO_PAL)
    pal['#'] = (92, 42, 44, 255)      # banner cloth
    pal['@'] = (156, 70, 56, 255)     # its faded device
    out = []
    for g in DECO_GRIDS:
        rows = [r.ljust(16, '.')[:16] for r in g]
        while len(rows) < 32:
            rows.append('.' * 16)
        out.append(grid_to_img(rows[:32], pal))
    return out


def water_tile():
    """Standing water in the cistern: you wade through it, so it is drawn over
    the floor rather than replacing it, and it never collides.

    Level.gd draws a lit surface line on whichever tiles have air above them,
    so the body of water gets one edge instead of a stripe per tile.
    """
    img = Image.new("RGBA", (16, 16), T)
    px = img.load()
    rng = random.Random(404)
    for y in range(16):
        for x in range(16):
            px[x, y] = (30, 74, 92, 118)
    for _ in range(14):                       # a little silt and movement
        x, y = rng.randint(0, 15), rng.randint(2, 15)
        px[x, y] = (44, 96, 114, 130)
    for x in range(16):
        px[x, 0] = (96, 168, 180, 190)         # the surface catches the light
        px[x, 1] = (52, 108, 126, 150)
    for x in range(0, 16, 5):
        px[x, 3] = (70, 132, 150, 140)
    return img


def mushroom_frames():
    """Glowing caps in the rootworks — the only light source down there that is
    not a torch."""
    grid = [
        "..ooo..",
        ".oZZZo.",
        "oZZZZZo",
        ".oZZZo.",
        "..oIo..",
        "..oIo..",
        "..ooo..",
    ]
    dim = [r.replace('Z', 'n') for r in grid]
    return [grid_to_img(grid, UIPAL), grid_to_img(dim, UIPAL)]


def brazier_frames():
    """An iron fire-basket for the forge. Burns, but you cannot rest at it."""
    frames = []
    for phase in (0, 1):
        rows = [
            "...aya..." if phase == 0 else "..ayya...",
            "..aRya..." if phase == 0 else "..aRRa...",
            ".aRRRa..." if phase == 0 else ".aRRya...",
            "ooooooooo",
            "odddddddo",
            ".od...do.",
            "..o...o..",
            "..o...o..",
            ".ooo.ooo.",
        ]
        frames.append(grid_to_img(rows, PAL))
    return frames


def beam_tile():
    """A one-way beam: bone-pale plank across the top of the tile, hollow below
    so you can see it is something you stand ON rather than a wall."""
    img = Image.new("RGBA", (16, 16), T)
    px = img.load()
    for x in range(16):
        px[x, 0] = (12, 11, 16, 255)
        px[x, 1] = (176, 168, 148, 255)
        px[x, 2] = (140, 132, 114, 255)
        px[x, 3] = (92, 86, 74, 255)
        px[x, 4] = (12, 11, 16, 255)
    for x in (0, 5, 10, 15):            # peg ends / grain
        px[x, 2] = (74, 68, 58, 255)
    return img


def ladder_tile():
    """Two rails and a rung. Tiles vertically, so a shaft of these reads as one
    continuous ladder."""
    img = Image.new("RGBA", (16, 16), T)
    px = img.load()
    RAIL = (150, 140, 118, 255)
    RAIL_D = (86, 78, 64, 255)
    for y in range(16):
        for x in (3, 4):
            px[x, y] = RAIL if x == 3 else RAIL_D
        for x in (11, 12):
            px[x, y] = RAIL if x == 11 else RAIL_D
    for y in (4, 5):                     # the rung
        for x in range(4, 12):
            px[x, y] = RAIL if y == 4 else RAIL_D
    return img


def rune_frames():
    """An inscribed stone that catches the light — dim, then lit when the
    knight is close enough to read it."""
    grid = [
        "..ooo..",
        ".oIWIo.",
        "oIWeWIo",
        "oIeeeIo",
        "oIWeWIo",
        ".oIWIo.",
        "..ooo..",
    ]
    dim = grid_to_img(grid, UIPAL)
    lit = grid_to_img(_swap(grid, 'e', 'Z'), UIPAL)
    return [dim, lit]


def stone_wall(seed=7):
    random.seed(seed)
    img = Image.new("RGBA", (16, 16), PAL['1'])
    px = img.load()
    base = [PAL['1'], PAL['2'], PAL['2']]
    for y in range(16):
        for x in range(16):
            px[x, y] = random.choice(base)
    # brick courses (offset every other row band)
    for y in (0, 5, 10, 15):
        for x in range(16):
            px[x, y] = (18, 16, 24, 255)
    for band, y in enumerate((2, 7, 12)):
        off = 0 if band % 2 == 0 else 8
        vx = (off) % 16
        for yy in range(y - 2, y + 3):
            if 0 <= yy < 16:
                px[vx, yy] = (18, 16, 24, 255)
        vx2 = (off + 8) % 16
        for yy in range(y - 2, y + 3):
            if 0 <= yy < 16:
                px[vx2, yy] = (18, 16, 24, 255)
    # top highlight on each brick course
    for y in (1, 6, 11):
        for x in range(16):
            if px[x, y] != (18, 16, 24, 255):
                px[x, y] = PAL['3']
    return img


# ================================================================ BONFIRE =====
# A pile of ash + bones with a broken sword upright; animated flame.
# 24 wide x 24 tall.
BONFIRE_BASE = [
    "........................",  # 0
    "........................",  # 1
    "........................",  # 2
    "........................",  # 3
    "........................",  # 4
    "...........SS...........",  # 5  sword tip
    "...........SS...........",  # 6
    "...........dS...........",  # 7
    "...........dS...........",  # 8
    "...........dS...........",  # 9
    "...........dS...........",  # 10
    "..........gddg..........",  # 11 crossguard
    "..........sLLs..........",  # 12 grip
    ".......n...LL...n.......",  # 13
    "......nNn..LL..nNn......",  # 14 bones in ash
    ".....nNNnn.LL.nnNn......",  # 15
    "....onNNNnnnnnnNNno.....",  # 16 ash pile top
    "...on1NnNnNnNnNnNn1no...",  # 17
    "..on11nNnNnNnNnNn11no...",  # 18
    "..o1111nnNnNnNn1111o....",  # 19
    ".o111111nnnnnn1111o.....",  # 20 ash base
    ".oo1111111111111oo......",  # 21
    "...oooooooooooooo.......",  # 22
    "........................",  # 23
]

# Flame frames drawn ABOVE / around the sword base (rows ~5-16). Only fire glyphs.
FLAME_A = [
    "...........y............",
    "..........ya............",
    "..........yay...........",
    ".........yaay...........",
    ".........RaayR..........",
    "........RaaayR..........",
    "........RRaaRR..........",
    ".......rRRaaRRr.........",
    "......rRRRRRRRr.........",
    ".....rrRRRRRRrr.........",
]
FLAME_B = [
    "..........ya............",
    "..........yay...........",
    ".........yaay...........",
    ".........yaayy..........",
    "........RaaayR..........",
    "........RaayaR..........",
    ".......RRaaaRR.........",
    ".......rRRaaRRr........",
    "......rRRRRRRRr........",
    ".....rrRRRRRRRr........",
]
FLAME_C = [
    "...........y............",
    "..........aya...........",
    "..........yaa...........",
    ".........yaayR..........",
    ".........Raaay..........",
    "........RaaayR..........",
    "........RRaaRR.........",
    ".......rRRaaRRr........",
    ".......rRRRRRRr........",
    "......rrRRRRRRr........",
]


def _overlay(base_img, flame_rows, top):
    """Paste flame glyphs (skip transparent) onto a copy of base_img at row=top."""
    img = base_img.copy()
    fimg = grid_to_img(flame_rows)
    img.alpha_composite(fimg, (0, top))
    return img


def bonfire_frames():
    """Four burning frames, then a fifth: the cold pile before you light it.
    An unlit bonfire you can see from across a room is a promise, and lighting
    it is the clearest progress marker the game has."""
    base = grid_to_img(BONFIRE_BASE)
    flames = [FLAME_A, FLAME_B, FLAME_C, FLAME_B]
    frames = [_overlay(base, fl, 3) for fl in flames]
    cold = base.copy()
    px = cold.load()
    for y in range(cold.height):          # drained of all warmth
        for x in range(cold.width):
            r, g, b, a = px[x, y]
            if a:
                # keep some value in it: at true luminance the dead fire was
                # invisible against the floor, and you cannot walk toward
                # something you cannot see
                v = int(min(255, (r * 0.30 + g * 0.42 + b * 0.28) * 1.22 + 8))
                px[x, y] = (v, v, int(min(255, v * 1.15)), a)
    frames.append(cold)
    return frames


# ================================================================ TORCH =======
TORCH_BASE = [
    "....yy..",
    "...RaaR.",
    "...RaaR.",
    "....rr..",
    "....LL..",
    "....LL..",
    "...oLLo.",
    "....LL..",
    "....LL..",
    "....LL..",
]
TORCH_B = [
    "....ay..",
    "...RayR.",
    "...RaaR.",
    "....rr..",
    "....LL..",
    "....LL..",
    "...oLLo.",
    "....LL..",
    "....LL..",
    "....LL..",
]


def torch_frames():
    return [grid_to_img(TORCH_BASE), grid_to_img(TORCH_B)]


# ================================================== COMBAT ANIMATION FRAMES ===
# All in-game hero frames share a 32x32 canvas with a fixed anchor so the body
# never shifts between animations:
#   body art (20x28) is pasted at (BODY_OX, BODY_OY) -> feet land on row ~30,
#   body centre is column 16.  Godot draws it with offset (-16, -31).
# The canvas is symmetric about the anchor column so that flipping the sprite
# horizontally (facing left) mirrors it in place without shifting the body.
FR_W = 44
FR_H = 32
ANCHOR = (22, 31)          # feet centre, in frame pixels -> Godot offset (-22,-31)
BODY_OX = 11               # armour centred on grid col 11 -> frame col 22 = anchor
BODY_OY = 3                # 28-tall body -> rows 3..30, feet on row 30

HAND = (28, 17)            # where the knight grips his sword, in frame pixels
REST_HAND = (30, 18)       # resting grip: just clear of the right pauldron
REST_ANGLE = 1.25          # blade resting point-down at his side

PLAYER_UPPER = PLAYER[0:22]   # armour without the legs (drawn per run frame)


def frame40(src, ox=BODY_OX, oy=BODY_OY):
    f = Image.new("RGBA", (FR_W, FR_H), T)
    f.alpha_composite(src, (ox, oy))
    return f


def putp(img, x, y, col):
    if 0 <= x < img.width and 0 <= y < img.height and col[3]:
        img.putpixel((x, y), col)


def _line(img, x0, y0, x1, y1, col):
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        putp(img, x0, y0, col)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def _blade(img, px, py, ang, length):
    """Sword from the hand at (px,py) along `ang`.

    The 2px thickness is offset along whichever axis is *across* the blade, so
    diagonals come out as clean double lines instead of a hatched mess.
    """
    tx = px + int(round(math.cos(ang) * length))
    ty = py + int(round(math.sin(ang) * length))
    if abs(math.cos(ang)) >= abs(math.sin(ang)):
        ox, oy = 0, 1          # mostly horizontal -> thicken vertically
    else:
        ox, oy = 1, 0          # mostly vertical -> thicken horizontally
    _line(img, px, py, tx, ty, PAL['S'])                        # lit core
    _line(img, px + ox, py + oy, tx + ox, ty + oy, PAL['s'])    # shaded side
    for g in (-1, 0, 1):                                        # crossguard
        putp(img, px + g * oy, py + g * ox, PAL['g'])


def _arc(img, px, py, r, a0, a1, col, inner=None):
    """A solid crescent sweeping a0..a1 — the slash trail."""
    steps = max(24, int(r * 5))
    for i in range(steps):
        a = a0 + (a1 - a0) * i / float(steps - 1)
        ca, sa = math.cos(a), math.sin(a)
        putp(img, px + int(round(ca * r)), py + int(round(sa * r)), col)
        putp(img, px + int(round(ca * (r - 1))), py + int(round(sa * (r - 1))), col)
        if inner is not None:
            putp(img, px + int(round(ca * (r - 2))),
                 py + int(round(sa * (r - 2))), inner)


# =============================================================== WEAPONS =====
# Six weapons, every one of them drawn procedurally out of the knight's hand so
# that idle, run and attack all carry the SAME piece of steel.
#
# At 44x32 there are maybe twenty pixels to characterise a weapon with, so what
# separates them is silhouette, not detail: the axe is a crescent on a stick,
# the spear is longer than the knight is tall, the bow is a curve, the crossbow
# is a cross, the shield is a slab. You should be able to tell what he is
# holding from across the room, at 1x.

WEAPON_KINDS = ["sword", "axe", "spear", "bow", "crossbow", "shield"]


def _across(ang):
    """The 1px offset that thickens a line ACROSS its own direction, so
    diagonals come out as clean double lines instead of a hatched mess."""
    if abs(math.cos(ang)) >= abs(math.sin(ang)):
        return 0, 1            # mostly horizontal -> thicken vertically
    return 1, 0                # mostly vertical   -> thicken horizontally


def _perp(ang):
    """True perpendicular, as floats — for limbs that must stay square to the
    aim at any angle rather than snapping to the pixel grid."""
    return -math.sin(ang), math.cos(ang)


def _tip(px, py, ang, length):
    return (px + int(round(math.cos(ang) * length)),
            py + int(round(math.sin(ang) * length)))


def _shaft(img, px, py, ang, length, col, hi):
    """Two-pixel haft from the hand outward. Returns the tip."""
    tx, ty = _tip(px, py, ang, length)
    ox, oy = _across(ang)
    _line(img, px, py, tx, ty, hi)
    _line(img, px + ox, py + oy, tx + ox, ty + oy, col)
    return tx, ty


def _paste_grid(img, rows, x, y, pal=PAL):
    """Blit a character grid at (x,y), clipped — the weapon poses swing things
    right up to the edge of the frame and off it."""
    for gy, row in enumerate(rows):
        for gx, ch in enumerate(row):
            col = pal.get(ch, T)
            if col[3]:
                putp(img, x + gx, y + gy, col)


def _axe(img, px, py, ang, length):
    """Great axe: a heavy crescent head on a short wooden haft."""
    tx, ty = _shaft(img, px, py, ang, length, PAL['l'], PAL['L'])
    hx, hy = _tip(px, py, ang, length - 3)
    _arc(img, hx, hy, 5, ang - 0.95, ang + 0.95, PAL['S'], inner=PAL['s'])
    putp(img, tx, ty, PAL['s'])                  # a spike past the head
    ox, oy = _across(ang)
    for g in (-1, 1):                            # brass collar at the grip
        putp(img, px + g * oy, py + g * ox, PAL['g'])


def _spear(img, px, py, ang, length):
    """Winged spear: reach at the cost of everything else."""
    _shaft(img, px, py, ang, length, PAL['l'], PAL['L'])
    ox, oy = _across(ang)
    for k in range(4):                           # slim leaf head
        hx, hy = _tip(px, py, ang, length - k)
        putp(img, hx, hy, PAL['S'])
        if k:
            putp(img, hx + ox, hy + oy, PAL['s'])
    wx, wy = _tip(px, py, ang, length - 5)       # the wings that name it
    putp(img, wx + ox * 2, wy + oy * 2, PAL['s'])
    putp(img, wx - ox, wy - oy, PAL['s'])


def _bow(img, px, py, ang, pull=0.0, arrow=True):
    """Hunting bow: the stave bows away from the archer, the string behind it.
    `pull` is how far back the nock is drawn, in pixels."""
    cx, cy = _tip(px, py, ang, 2)
    _arc(img, cx, cy, 7, ang - 1.25, ang + 1.25, PAL['L'], inner=PAL['l'])
    limbs = [(cx + int(round(math.cos(ang + s * 1.25) * 7)),
              cy + int(round(math.sin(ang + s * 1.25) * 7))) for s in (-1, 1)]
    nock = _tip(px, py, ang, -pull)
    for lx, ly in limbs:
        _line(img, lx, ly, nock[0], nock[1], PAL['N'])
    if arrow:
        ax, ay = _tip(nock[0], nock[1], ang, 13)
        _line(img, nock[0], nock[1], ax, ay, PAL['s'])
        putp(img, ax, ay, PAL['S'])


def _crossbow(img, px, py, ang, loaded=True, flash=False):
    """Iron crossbow: a stock along the aim, short steel limbs square to it."""
    tx, ty = _shaft(img, px, py, ang, 11, PAL['l'], PAL['L'])
    fx, fy = _tip(px, py, ang, 8)
    ux, uy = _perp(ang)
    limbs = []
    for s in (-1, 1):
        ex = fx + int(round(ux * 5 * s))
        ey = fy + int(round(uy * 5 * s))
        _line(img, fx, fy, ex, ey, PAL['d'])
        putp(img, ex, ey, PAL['s'])
        limbs.append((ex, ey))
    # drawn back over the nut when loaded, snapped forward once it has fired
    sx, sy = _tip(px, py, ang, 4 if loaded else 7)
    for lx, ly in limbs:
        _line(img, lx, ly, sx, sy, PAL['N'])
    if loaded:
        bx, by = _tip(px, py, ang, 15)
        _line(img, sx, sy, bx, by, PAL['S'])
    if flash:
        _arc(img, tx, ty, 3, ang - 0.9, ang + 0.9, PAL['y'])


# A heater shield, seen edge-on-ish from the side: a slab with a brass boss.
SHIELD_GRID = [
    ".oooooo.",
    "oDDDDDDo",
    "oDCCCCDo",
    "oDCgCCDo",
    "oDCCCCDo",
    "oDDDDDDo",
    ".oDDDDo.",
    ".oDDDDo.",
    "..oDDo..",
    "...oo...",
]


def _shield(img, px, py, forward=0, raised=False):
    _paste_grid(img, SHIELD_GRID, px - 2 + forward, py - (6 if raised else 3))


def _draw_weapon(img, kind, px, py, ang, length):
    """Whichever weapon, swung the same way — one call site for every pose."""
    if kind == "axe":
        _axe(img, px, py, ang, length)
    elif kind == "spear":
        _spear(img, px, py, ang, length)
    else:
        _blade(img, px, py, ang, length)


def _carry(f, kind, hx, hy, moving=False):
    """The weapon as it is CARRIED, in the idle and run frames."""
    if kind == "sword":
        _blade(f, hx, hy, REST_ANGLE + (0.15 if moving else 0.0), 12 if moving else 11)
    elif kind == "axe":
        _axe(f, hx, hy, REST_ANGLE + (0.20 if moving else 0.05), 10)
    elif kind == "spear":
        # shouldered upright: the one weapon you can spot by its silhouette
        _spear(f, hx - 1, hy - 1, -1.45 + (0.12 if moving else 0.0), 16)
    elif kind == "bow":
        _bow(f, hx, hy - 1, 1.30, pull=0.0, arrow=False)
    elif kind == "crossbow":
        _crossbow(f, hx - 2, hy, 0.55, loaded=True)
    elif kind == "shield":
        _shield(f, hx, hy, forward=0, raised=False)


# ------------------------------------------------------------------ idle -----
def hero_idle_w(kind):
    body = grid_to_img(PLAYER)
    frames = []
    for bob in (0, 1, 1, 0):        # slow armoured breathing
        f = frame40(body, BODY_OX, BODY_OY + bob)
        _carry(f, kind, REST_HAND[0], REST_HAND[1] + bob)
        frames.append(f)
    return frames


def hero_idle32():
    return hero_idle_w("sword")


# ------------------------------------------------------------------- run -----
def hero_run_w(kind):
    upper = grid_to_img(PLAYER_UPPER)
    frames = []
    N = 6
    cx = ANCHOR[0]
    for i in range(N):
        ph = i / float(N) * math.tau
        bob = -1 if i in (1, 4) else 0
        f = Image.new("RGBA", (FR_W, FR_H), T)
        f.alpha_composite(upper, (BODY_OX, BODY_OY + bob))
        # two striding armoured legs — greaves over sabatons
        for base_x, phase in ((cx - 4, 0.0), (cx + 3, math.pi)):
            sw = math.sin(ph + phase)
            lx = base_x + int(round(sw * 2))
            lift = 1 if math.cos(ph + phase) > 0.5 else 0
            top = 25 + bob
            for yy in range(top, top + 4 - lift):
                putp(f, lx, yy, PAL['B'])
                putp(f, lx + 1, yy, PAL['C'])
                putp(f, lx + 2, yy, PAL['C'])
            by = top + 4 - lift
            for bxo in (0, 1, 2):
                putp(f, lx + bxo, by, PAL['B'])
                putp(f, lx + bxo, by + 1, PAL['A'])
        _carry(f, kind, REST_HAND[0], REST_HAND[1] + bob, moving=True)
        frames.append(f)
    return frames


def hero_run32():
    return hero_run_w("sword")


# ---------------------------------------------------------------- attack -----
# (blade angle, blade length, trail: 0 none / 1 crescent / 2 straight, lunge px)
ATTACK_SPECS = {
    # overhead cut: wind up behind the shoulder, come down through the target
    "sword": [(-2.15, 12, 0, 0), (-1.05, 13, 0, 0), (0.30, 14, 1, 2), (1.15, 12, 0, 1)],
    # the axe winds up FURTHER and lands HARDER — the extra frame of travel is
    # what the animation has to sell in place of the damage number
    "axe": [(-2.60, 11, 0, -1), (-1.75, 11, 0, -1), (0.55, 12, 1, 4), (1.30, 11, 0, 2)],
    # the spear does not swing at all: it retracts, then goes straight out
    "spear": [(0.14, 10, 0, -1), (0.10, 8, 0, -2), (0.00, 20, 2, 4), (0.06, 15, 0, 1)],
}


def hero_attack_w(kind):
    body = grid_to_img(PLAYER)
    frames = []

    if kind in ATTACK_SPECS:
        for ang, length, trail, lunge in ATTACK_SPECS[kind]:
            f = frame40(body, BODY_OX + lunge, BODY_OY)
            px, py = HAND[0] + lunge, HAND[1] - 1
            if trail == 1:
                _arc(f, px, py, 13 if kind == "sword" else 16,
                     -0.55, 0.95, PAL['W'], inner=PAL['S'])
            elif trail == 2:
                sx, sy = _tip(px, py, ang, length + 3)
                _line(f, px + 9, py - 2, sx, sy - 2, PAL['W'])
            _draw_weapon(f, kind, px, py, ang, length)
            frames.append(f)
        return frames

    if kind == "bow":
        # nock -> draw -> loose (the arrow is gone; it is a real one now) -> re-nock
        for pull, arrow, lunge, flash in ((0, True, 0, False), (4, True, 0, False),
                                          (0, False, 1, True), (0, True, 0, False)):
            f = frame40(body, BODY_OX + lunge, BODY_OY)
            px, py = HAND[0] + lunge - 1, HAND[1] - 3
            _bow(f, px, py, -0.06, pull=pull, arrow=arrow)
            if flash:
                _arc(f, px, py, 9, -0.5, 0.5, PAL['W'])
            frames.append(f)
        return frames

    if kind == "crossbow":
        # levelled -> levelled -> the shot, kicking back -> spanning it again
        for loaded, flash, lunge in ((True, False, 0), (True, False, 1),
                                     (False, True, -2), (False, False, 0)):
            f = frame40(body, BODY_OX + lunge, BODY_OY)
            _crossbow(f, HAND[0] + lunge - 2, HAND[1] - 3, -0.04,
                      loaded=loaded, flash=flash)
            frames.append(f)
        return frames

    # shield bash: brought in tight, then driven forward off the front foot
    for forward, raised, lunge, trail in ((-2, True, -1, False), (-1, True, 0, False),
                                          (5, False, 4, True), (1, True, 1, False)):
        f = frame40(body, BODY_OX + lunge, BODY_OY)
        px, py = HAND[0] + lunge, HAND[1] - 1
        if trail:
            _arc(f, px, py, 12, -0.55, 0.55, PAL['W'])
        _shield(f, px, py, forward, raised)
        frames.append(f)
    return frames


def hero_attack32():
    return hero_attack_w("sword")


# ----------------------------------------------------------------- block -----
def hero_block():
    """Braced behind the shield. Two frames so the guard breathes rather than
    freezing solid the moment you raise it."""
    frames = []
    for bob in (0, 1):
        body = grid_to_img(PLAYER)
        f = frame40(body, BODY_OX - 1, BODY_OY + bob)
        _shield(f, HAND[0] + 1, HAND[1] - 2 + bob, forward=3, raised=True)
        frames.append(f)
    return frames


# ----------------------------------------------------------- projectiles -----
# Fletching at the back, steel at the point, so the direction of travel reads
# even at one pixel of motion blur.
ARROW = [
    "N..sssssssS",
    "NNNsssssssS",
    "N..sssssssS",
]
BOLT = [
    "N.ddddSS",
    "NNddddSS",
    "N.ddddSS",
]


def arrow_sprite():
    return grid_to_img(ARROW)


def bolt_sprite():
    return grid_to_img(BOLT)


# --------------------------------------------------------------- pickups -----
def weapon_icons():
    """One 14x14 icon per weapon, drawn with the same primitives as the poses —
    so what you pick up off the floor is recognisably what you then carry."""
    frames = []
    for kind in WEAPON_KINDS:
        f = Image.new("RGBA", (14, 14), T)
        if kind == "shield":
            _paste_grid(f, SHIELD_GRID, 3, 2)
        elif kind == "bow":
            _bow(f, 4, 10, -0.85, pull=0.0, arrow=False)
        elif kind == "crossbow":
            _crossbow(f, 2, 12, -0.85, loaded=True)
        elif kind == "spear":
            _spear(f, 1, 12, -0.80, 15)
        elif kind == "axe":
            _axe(f, 2, 12, -0.85, 9)
        else:
            _blade(f, 2, 12, -0.85, 13)
        frames.append(f)
    return frames

# ------------------------------------------------------------------ roll -----
# One tucked "wheel" of cloak, rotated 4x -> a readable forward dodge-roll.
# The face + eye act as the orientation marker so the spin reads clearly.
ROLL_BALL = [
    "......oooooo......",
    "....ooAAACEEoo....",
    "...oAABBCDEEEEo...",
    "..oABBBBBCDEEEEo..",
    ".oABBBBBBBCDEEEEo.",
    ".oABBBBBBBBCDEEDo.",
    "oABBBBBBBBBBCDDffo",
    "oAABBBBBBBBBBCffZo",
    "oAABBBBBBBBBBBCffo",
    "oAABBBBBBBBBBBBCAo",
    ".oAABBBBBBBBBBBCAo",
    ".oAABBBBBBBBBBBAo.",
    "..oAABBBBBBBBAo...",
    "...oAAABBBBAAo....",
    "....ooAAAAAoo.....",
    "......oooooo......",
]


def hero_roll32():
    ball = grid_to_img(ROLL_BALL)
    frames = []
    for a in (0, -90, -180, -270):
        r = ball.rotate(a, resample=Image.NEAREST, expand=False)
        f = Image.new("RGBA", (FR_W, FR_H), T)
        f.alpha_composite(r, (ANCHOR[0] - ball.width // 2, FR_H - ball.height - 1))
        frames.append(f)
    return frames


# ================================================================== ENEMY =====
# "Hollow" — a husk of a soldier. Faces LEFT (toward the approaching player).
# 16 wide x 24 tall, feet on row 23.
HOLLOW = [
    "....oooo........",  # 0
    "...opppo........",  # 1 skull
    "...opffo........",  # 2 hollow eyes
    "...opvfo........",  # 3 ember eye
    "...opppo........",  # 4
    "....oppo........",  # 5 neck
    "..ooQQQoo.......",  # 6 shoulders
    ".oQQqqqQQo......",  # 7
    "oQqqqqqqqQo.....",  # 8
    "oqqqqqqqqqo.....",  # 9
    "oqqqqqqqqqo.....",  # 10
    ".oqqqqqqqo......",  # 11
    ".oqqqqqqqo......",  # 12
    ".oqqqqqqo.......",  # 13
    ".oqqqqqqo.......",  # 14
    ".oqqqqqo........",  # 15
    ".oqqqqqo........",  # 16
    ".oqqoqqo........",  # 17
    ".oqo.oqo........",  # 18
    ".oNo.oNo........",  # 19 bony shins
    ".oNo.oNo........",  # 20
    ".oNo.oNo........",  # 21
    "ooNo.oNoo.......",  # 22
    "oppo.oppo.......",  # 23 feet
]


def _hollow_base():
    return grid_to_img(HOLLOW)


def _hollow_frame(arm_ang, arm_len, dy=0, lunge=0):
    """Hollow with its rusted blade swung to `arm_ang`. Faces LEFT (angle pi).

    Shares the hero's 40x32 canvas and anchor, so both use offset (-20,-31).
    """
    f = Image.new("RGBA", (FR_W, FR_H), T)
    f.alpha_composite(_hollow_base(), (14 - lunge, 7 + dy))
    px, py = 17 - lunge, 16 + dy
    tx = px + int(round(math.cos(arm_ang) * arm_len))
    ty = py + int(round(math.sin(arm_ang) * arm_len))
    _line(f, px, py, tx, ty, PAL['x'])
    _line(f, px, py - 1, tx, ty - 1, PAL['X'])
    return f


def hollow_frames():
    """[idle0, idle1, windup, strike, hurt, dead] — all 40x32."""
    idle0 = _hollow_frame(2.50, 8)                    # blade hanging down-left
    idle1 = _hollow_frame(2.55, 8, dy=1)              # slow breath
    windup = _hollow_frame(-0.70, 10)                 # raised BACK over shoulder
    strike = _hollow_frame(3.05, 12, lunge=2)         # thrust forward (left)
    hurt = _hollow_frame(2.20, 7, dy=1, lunge=-2)     # recoil
    dead = Image.new("RGBA", (FR_W, FR_H), T)
    fallen = _hollow_frame(2.40, 6).rotate(
        -72, resample=Image.NEAREST, expand=False)
    dead.alpha_composite(fallen, (0, 6))
    return [idle0, idle1, windup, strike, hurt, dead]


# ============================================================ LIGHT TEXTURE ===
def soft_light(size=256):
    """Radial warm-white gradient for PointLight2D (white so it can be tinted)."""
    img = Image.new("RGBA", (size, size), T)
    px = img.load()
    c = size / 2.0
    for y in range(size):
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / c
            if d >= 1:
                continue
            a = (1 - d)
            a = a * a  # soft falloff
            px[x, y] = (255, 255, 255, int(255 * a))
    return img


# =================================================================== UI =======
# Bone-and-iron interface art: a 5x7 pixel font, skull ornaments, carved bar
# frames and the crypt backdrop the menus sit in.
#
# The font is drawn in pure WHITE so the engine can tint one sheet into every
# shade the UI needs — ivory for labels, ember red for "YOU DIED", sickly green
# for stamina — instead of baking a sheet per colour.

UI_OUT = os.path.join(ROOT, "assets", "ui")
os.makedirs(UI_OUT, exist_ok=True)

# Keep this string in sync with PixelLabel.CHARS on the Godot side: the engine
# looks a glyph up purely by its index in here.
# '+' is appended LAST on purpose: a glyph is found by its index in this
# string, so adding to the end leaves every existing index untouched.
FONT_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:!?'-()/ +"
GLYPH_W, GLYPH_H = 5, 7
CELL_W, CELL_H = 6, 8

GLYPHS = {
    'A': [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    'B': ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    'C': [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
    'D': ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    'E': ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    'F': ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    'G': [".###.", "#...#", "#....", "#..##", "#...#", "#...#", ".###."],
    'H': ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    'I': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    'J': ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
    'K': ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    'L': ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    'M': ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    'N': ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
    'O': [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    'P': ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    'Q': [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    'R': ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    'S': [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    'T': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    'U': ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    'V': ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    'W': ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    'X': ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    'Y': ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    'Z': ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    '0': [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    '1': ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    '2': [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    '3': ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    '4': ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    '5': ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    '6': ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    '7': ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    '8': [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    '9': [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
    '.': [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
    ',': [".....", ".....", ".....", ".....", ".##..", ".##..", ".#..."],
    ':': [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
    '!': ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
    '?': [".###.", "#...#", "....#", "..##.", "..#..", ".....", "..#.."],
    "'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
    '-': [".....", ".....", ".....", "####.", ".....", ".....", "....."],
    '(': ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
    ')': [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
    '/': ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
    ' ': [".....", ".....", ".....", ".....", ".....", ".....", "....."],
    '+': [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
}

# Menu layout, shared by the backdrop, the mock-up and MainMenu.gd. The
# backdrop bakes the skull at SKULL_TOP, so the engine must place its text at
# these same coordinates or the composition falls apart.
TITLE_Y = 20
SUB_Y = 50
MENU_Y0 = 80          # first entry INSIDE the panel
MENU_STEP = 18
PANEL_Y = 66
SKULL_TOP = 168       # just its dome above the bones; the panel is the focus now

# --- bone palette -------------------------------------------------------------
UIPAL = {
    '.': T,
    'o': (12, 11, 16, 255),      # carved outline
    'n': (92, 87, 75, 255),      # bone shadow
    'I': (168, 160, 140, 255),   # bone mid (ivory)
    'W': (222, 215, 194, 255),   # bone highlight
    'e': (16, 14, 19, 255),      # empty socket
    'Z': (236, 88, 58, 255),     # socket ember — a skull that is watching you
}

SKULL = [
    "...ooooo...",
    "..oWWIIIo..",
    ".oWIIIIIIo.",
    ".oIeeIeeIo.",
    ".oIeeIeeIo.",
    ".oIIIIIIIo.",
    "..oIIIIIo..",
    "..oInInIo..",
    "...ooooo...",
]

BONE_LONG = [
    ".oo.....oo.",
    "oWIo...oIIo",
    ".oIIIIIIIo.",
    "oWIo...oIIo",
    ".oo.....oo.",
]

BONE_SHORT = [
    ".oo..oo.",
    "oWIooIIo",
    ".oIIIIo.",
    "oWIooIIo",
    ".oo..oo.",
]


def _swap(rows, a, b):
    return [r.replace(a, b) for r in rows]


def font_sheet():
    """All glyphs in one horizontal strip, pure white, one 6x8 cell each."""
    img = Image.new("RGBA", (CELL_W * len(FONT_CHARS), CELL_H), T)
    px = img.load()
    for i, ch in enumerate(FONT_CHARS):
        for y, row in enumerate(GLYPHS[ch]):
            for x, c in enumerate(row):
                if c == '#':
                    px[i * CELL_W + x, y] = (255, 255, 255, 255)
    return img


def skull_frames():
    """[dim, ember-eyed] — the menu cursor lights up on the selected entry."""
    return [grid_to_img(SKULL, UIPAL),
            grid_to_img(_swap(SKULL, 'e', 'Z'), UIPAL)]


def spiked_bar_frame(w, h, spike=6, tick_gap=9):
    """A slender iron-and-bone gauge, not a loading bar: twin fangs flank a
    small recessed plate. Returns (frame, overlay).

    The frame is OPAQUE and drawn first (fangs + plate + empty channel) — this
    is what made the old rounded-knob bar read as generic; a pointed silhouette
    reads as a weapon instead. The overlay is TRANSPARENT scoring drawn AFTER
    the fill (thin ticks only, so it never needs to mask a rectangular
    overflow the way an opaque piece would) — it breaks the fill into scored
    segments instead of one solid smear.

    cap = spike + 1 is the horizontal inset the engine draws the fill at (the
    +1 is the plate's own rim); see UiTheme.HP_CAP / channel_size()."""
    frame = Image.new("RGBA", (w, h), T)
    px = frame.load()
    OUTL = UIPAL['o']
    cy = (h - 1) / 2.0

    for y in range(h):
        for x in range(w):
            if x < spike or x >= w - spike:
                # --- fang: tapers from a single glinting point to the plate ---
                lx = x if x < spike else (w - 1 - x)
                half = (lx / float(spike)) * (h / 2.0)
                d = abs(y - cy)
                if d > half + 0.5:
                    continue
                if d > half - 0.9:
                    px[x, y] = OUTL
                elif lx == 0:
                    px[x, y] = UIPAL['W']            # the tip glints
                else:
                    px[x, y] = UIPAL['I'] if y <= cy else UIPAL['n']
            else:
                # --- plate: recessed channel, corners chamfered ---
                is_edge = (x == spike or x == w - spike - 1 or y == 0 or y == h - 1)
                cut_corner = ((x == spike or x == w - spike - 1)
                              and (y == 0 or y == h - 1))
                if cut_corner:
                    continue
                if is_edge:
                    px[x, y] = OUTL
                elif y == 1 or y == h - 2:
                    px[x, y] = UIPAL['n']
                else:
                    px[x, y] = (18, 16, 22, 255)      # empty channel
    # rivets, just inside the plate's top rim where the fangs meet it
    _put(frame, spike + 1, 1, UIPAL['W'])
    _put(frame, w - spike - 2, 1, UIPAL['W'])

    # --- overlay: scoring ticks over the channel, drawn AFTER the fill ---
    overlay = Image.new("RGBA", (w, h), T)
    opx = overlay.load()
    inner_x0, inner_x1 = spike + 1, w - spike - 1
    x = inner_x0 + tick_gap
    while x < inner_x1 - 1:
        for y in range(2, h - 2):
            opx[x, y] = (9, 8, 12, 130)
        x += tick_gap
    return frame, overlay


def _put(img, x, y, col):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), col)


def _darken(img, f):
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            px[x, y] = (int(r * f), int(g * f), int(b * f), a)
    return img


def draw_text(img, text, x, y, scale=1, col=(222, 215, 194, 255), tracking=1):
    """Blit a string with the pixel font. Mirrors PixelLabel._draw() in Godot."""
    cx = x
    for ch in text.upper():
        rows = GLYPHS.get(ch, GLYPHS[' '])
        for gy, row in enumerate(rows):
            for gx, c in enumerate(row):
                if c != '#':
                    continue
                for sy in range(scale):
                    for sx in range(scale):
                        _put(img, cx + gx * scale + sx, y + gy * scale + sy, col)
        cx += (GLYPH_W + tracking) * scale
    return cx


def text_width(text, scale=1, tracking=1):
    n = len(text)
    if n == 0:
        return 0
    return n * (GLYPH_W + tracking) * scale - tracking * scale


def big_skull(w=112, h=104):
    """A large skull drawn at native resolution — cranium, sockets, nasal
    cavity and a toothed jaw. Scaling the 11px icon up just gives mush, so the
    looming one behind the title gets its own geometry."""
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    BONE = (150, 143, 126, 255)
    SHADE = (108, 102, 89, 255)
    DARK = (10, 9, 13, 255)
    cx = w / 2.0

    def ell(x, y, ex, ey, rx, ry):
        return ((x - ex) / rx) ** 2 + ((y - ey) / ry) ** 2 <= 1.0

    cranium_y, cranium_rx, cranium_ry = h * 0.36, w * 0.43, h * 0.33
    jaw_y, jaw_rx, jaw_ry = h * 0.70, w * 0.27, h * 0.20
    cheek_y, cheek_rx, cheek_ry = h * 0.56, w * 0.36, h * 0.16

    for y in range(h):
        for x in range(w):
            if (ell(x, y, cx, cranium_y, cranium_rx, cranium_ry)
                    or ell(x, y, cx, jaw_y, jaw_rx, jaw_ry)
                    or ell(x, y, cx, cheek_y, cheek_rx, cheek_ry)):
                # light falls from above: shade the lower half
                px[x, y] = BONE if y < h * 0.55 else SHADE

    # eye sockets — deep and slightly angled inward, which reads as menacing
    for sgn in (-1, 1):
        ex = cx + sgn * w * 0.185
        for y in range(h):
            for x in range(w):
                if ell(x, y, ex, h * 0.42, w * 0.135, h * 0.115):
                    px[x, y] = DARK
    # nasal cavity: an inverted triangle
    for y in range(int(h * 0.48), int(h * 0.62)):
        t = (y - h * 0.48) / (h * 0.62 - h * 0.48)
        half = max(1, int(w * 0.055 * (1.0 - t) + w * 0.012))
        for x in range(int(cx - half), int(cx + half) + 1):
            if 0 <= x < w:
                px[x, y] = DARK
    # teeth: vertical gaps across the jaw
    for y in range(int(h * 0.63), int(h * 0.80)):
        for x in range(w):
            if px[x, y][3] and (x - int(cx)) % 7 == 0:
                px[x, y] = DARK
    # a dark seam under the cheekbones separates skull from jaw
    for x in range(w):
        y = int(h * 0.63)
        if px[x, y][3]:
            px[x, y] = DARK
    return img


def menu_backdrop(wall, floor, w=384, h=216):
    """The crypt the menu sits in: dim stonework, a bone pile, a skull looming
    out of the dark, and a heavy vignette so the title reads."""
    img = Image.new("RGBA", (w, h), (10, 9, 14, 255))
    dim_wall = _darken(wall.copy(), 0.62)
    dim_floor = _darken(floor.copy(), 0.55)
    floor_y = h - 46
    for cy in range(0, h, 16):
        for cx in range(0, w, 16):
            img.alpha_composite(dim_wall if cy < floor_y else dim_floor, (cx, cy))

    # A huge skull rising out of the heap at the bottom — placed BELOW the menu
    # entries so its sockets and teeth stay readable instead of hiding behind
    # letters, and drawn before the pile so the bones bury its jaw.
    big = _darken(big_skull(), 0.52)
    img.alpha_composite(big, ((w - big.width) // 2, SKULL_TOP))

    # bone heap along the bottom: larger overlapping pieces, densest at the
    # floor line, thinning upward so it reads as a pile and not as confetti
    rng = random.Random(20240)
    long_b = grid_to_img(BONE_LONG, UIPAL)
    short_b = grid_to_img(BONE_SHORT, UIPAL)
    skull = skull_frames()[0]
    for _ in range(130):
        depth = rng.random() ** 1.7          # 0 = front/low, 1 = back/high
        by = h - 7 - int(depth * 26)
        bx = rng.randint(-8, w - 2)
        piece = rng.choice([long_b, long_b, long_b, short_b, short_b, skull])
        if rng.random() < 0.35:
            piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
        lit = 1.0 - depth * 0.5 + rng.uniform(-0.07, 0.07)
        img.alpha_composite(_darken(piece.copy(), max(0.3, min(1.0, lit))), (bx, by))

    # vignette: push the corners into the dark
    px = img.load()
    cxf, cyf = w / 2.0, h / 2.0
    for y in range(h):
        for x in range(w):
            d = (((x - cxf) / cxf) ** 2 + ((y - cyf) / cyf) ** 2) ** 0.5
            f = max(0.0, 1.0 - 0.72 * max(0.0, d - 0.28) ** 1.5)
            r, g, b, a = px[x, y]
            px[x, y] = (int(r * f), int(g * f), int(b * f), a)
    return img


def ui_panel(size=24):
    """A 9-slice frame for menu boxes: carved bone border over a dark, slightly
    translucent fill, so the crypt behind still shows through faintly.

    Godot stretches this with NinePatchRect; the border pattern is uniform along
    each edge, so stretching never smears a detail. Corner rivets sit inside the
    fixed 8px corner blocks and therefore stay crisp at any size."""
    img = Image.new("RGBA", (size, size), T)
    px = img.load()
    OUTL = (10, 9, 14, 255)
    BONE = (150, 142, 122, 255)
    BONE_HI = (198, 190, 168, 255)
    BONE_LO = (92, 86, 74, 255)
    FILL = (13, 12, 17, 219)          # not fully opaque: the backdrop bleeds in
    for y in range(size):
        for x in range(size):
            d = min(x, y, size - 1 - x, size - 1 - y)
            if d == 0:
                px[x, y] = OUTL
            elif d == 1:
                px[x, y] = BONE_HI if y < size / 2 else BONE_LO
            elif d == 2:
                px[x, y] = BONE
            elif d == 3:
                px[x, y] = OUTL
            else:
                px[x, y] = FILL
    for (cx, cy) in ((5, 5), (size - 6, 5), (5, size - 6), (size - 6, size - 6)):
        px[cx, cy] = BONE_HI            # rivets
    return img


def vignette(w=384, h=216):
    """Darkens the screen edges so the eye settles in the middle. Drawn over the
    world but under the HUD."""
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    cx, cy = w / 2.0, h / 2.0
    for y in range(h):
        for x in range(w):
            d = (((x - cx) / cx) ** 2 + ((y - cy) / cy) ** 2) ** 0.5
            a = max(0.0, (d - 0.55) / 0.85)
            px[x, y] = (4, 3, 7, int(min(1.0, a * a) * 205))
    return img


def flask_frames():
    """The knight's flask: full, then drained. Two frames, HUD sized."""
    grid_full = [
        ".ooo.",
        ".oIo.",
        "ooooo",
        "oZZZo",
        "oZZZo",
        "oZZZo",
        "ooooo",
    ]
    grid_empty = [r.replace('Z', 'n') for r in grid_full]
    return [grid_to_img(grid_full, UIPAL), grid_to_img(grid_empty, UIPAL)]


def soul_orb_frames():
    """The souls you dropped, waiting where you fell. Pulses so it reads as a
    thing to walk into from across a dark room."""
    frames = []
    for i, r in enumerate((3.0, 3.7, 4.3, 3.7)):
        img = Image.new("RGBA", (11, 11), T)
        px = img.load()
        for y in range(11):
            for x in range(11):
                d = ((x - 5) ** 2 + (y - 5) ** 2) ** 0.5
                if d <= r * 0.55:
                    px[x, y] = (232, 246, 255, 255)
                elif d <= r:
                    px[x, y] = (150, 230, 214, 240)
                elif d <= r + 1.4:
                    px[x, y] = (86, 168, 168, 150)
        frames.append(img)
    return frames


def save_ui(img, name):
    img.save(os.path.join(UI_OUT, name))
    print("  wrote ui/%s" % name, img.size)


## Panel size for a menu, derived from its longest entry. Mirrors
## UiTheme.menu_panel_metrics() -- both must agree or the mock-up lies.
CURSOR_GUTTER = 30      # cursor skull + breathing room, left of the text
PANEL_PAD_X = 12
PANEL_PAD_TOP = 14
PANEL_PAD_BOTTOM = 12


def menu_panel_metrics(items, scale_px=2, step=None):
    step = MENU_STEP if step is None else step
    longest = max(text_width(it, scale_px) for it in items)
    panel_w = CURSOR_GUTTER + longest + PANEL_PAD_X
    panel_h = (MENU_Y0 - PANEL_Y) + (len(items) - 1) * step + 7 * scale_px \
        + PANEL_PAD_BOTTOM
    return CURSOR_GUTTER, panel_w, panel_h


def _draw_panel(img, x, y, w, h):
    """The same border ui_panel() bakes, drawn directly for the mock-up."""
    OUTL = (10, 9, 14, 255)
    BONE = (150, 142, 122, 255)
    BONE_HI = (198, 190, 168, 255)
    BONE_LO = (92, 86, 74, 255)
    FILL = (13, 12, 17, 219)
    layer = Image.new("RGBA", (w, h), T)
    px = layer.load()
    for yy in range(h):
        for xx in range(w):
            d = min(xx, yy, w - 1 - xx, h - 1 - yy)
            if d == 0:
                px[xx, yy] = OUTL
            elif d == 1:
                px[xx, yy] = BONE_HI if yy < h / 2 else BONE_LO
            elif d == 2:
                px[xx, yy] = BONE
            elif d == 3:
                px[xx, yy] = OUTL
            else:
                px[xx, yy] = FILL
    for (cx, cy) in ((5, 5), (w - 6, 5), (5, h - 6), (w - 6, h - 6)):
        px[cx, cy] = BONE_HI
    img.alpha_composite(layer, (x, y))


def _composite_bar(img, pos, frame, overlay, cap, frac, fill_col, edge_col):
    """Mirrors HUD.gd's draw order exactly: frame, then fill, then a lit top
    edge, then the scoring overlay on top of everything. Drifting from this
    order is how the fill ended up invisible once already (the frame is
    opaque and was covering it) -- keeping mock-up and engine on one code
    path is cheaper than re-discovering that."""
    ox, oy = pos
    img.alpha_composite(frame, (ox, oy))
    inner_w = frame.width - cap * 2
    inner_h = frame.height - 4
    fw = max(0, int(round(inner_w * frac)))
    px = img.load()
    for y in range(inner_h):
        for x in range(fw):
            px[ox + cap + x, oy + 2 + y] = edge_col if y < 2 else fill_col
    img.alpha_composite(overlay, (ox, oy))


def build_ui_preview(backdrop, hp_bar, sp_bar, skulls, game_tile):
    """A mock-up of the menu and the in-game HUD so the look can be judged
    without opening the engine. hp_bar / sp_bar are (frame, overlay, cap)."""
    w, h = 384, 216
    hp_frame, hp_overlay, hp_cap = hp_bar
    sp_frame, sp_overlay, sp_cap = sp_bar
    shot = backdrop.copy()

    # --- title, with an ember-red drop shadow ---
    title = "ASHEN HOLLOW"
    tw = text_width(title, 4)
    tx = (w - tw) // 2
    draw_text(shot, title, tx + 2, TITLE_Y + 2, 4, (104, 22, 16, 255))
    draw_text(shot, title, tx, TITLE_Y, 4, (226, 219, 199, 255))
    sub = "THE ASH REMEMBERS"
    draw_text(shot, sub, (w - text_width(sub, 1)) // 2, SUB_Y, 1, (128, 116, 104, 255))

    # --- entries, left-aligned inside a panel (mirrors MainMenu.gd) ---
    items = ["NEW GAME", "CONTROLS", "OPTIONS", "QUIT"]
    text_x, panel_w, panel_h = menu_panel_metrics(items)
    panel_x = (w - panel_w) // 2
    _draw_panel(shot, panel_x, PANEL_Y, panel_w, panel_h)
    for i, it in enumerate(items):
        y = MENU_Y0 + i * MENU_STEP
        sel = (i == 0)
        col = (236, 226, 202, 255) if sel else (122, 112, 100, 255)
        ix = panel_x + text_x
        if sel:
            for yy in range(y - 3, y + 17):
                for xx in range(panel_x + 5, panel_x + panel_w - 5):
                    r, g, b, a = shot.getpixel((xx, yy))
                    shot.putpixel((xx, yy), (min(255, r + 26), min(255, g + 22),
                                             min(255, b + 26), a))
            shot.alpha_composite(skulls[1], (panel_x + 12, y + 2))
        draw_text(shot, it, ix, y, 2, col)

    # --- second panel: the in-game HUD over a lit dungeon strip ---
    panel_h = 64
    out = Image.new("RGBA", (w, h + panel_h), (8, 7, 11, 255))
    out.alpha_composite(shot, (0, 0))
    panel = Image.new("RGBA", (w, panel_h), (16, 15, 21, 255))
    for cy in range(0, panel_h, 16):
        for cx in range(0, w, 16):
            panel.alpha_composite(_darken(game_tile.copy(), 0.8), (cx, cy))
    out.alpha_composite(panel, (0, h))

    ox, oy = 8, h + 8
    _composite_bar(out, (ox, oy), hp_frame, hp_overlay, hp_cap, 0.72,
                    (150, 26, 24, 255), (196, 44, 36, 255))
    sy = oy + hp_frame.height + 2
    _composite_bar(out, (ox, sy), sp_frame, sp_overlay, sp_cap, 0.55,
                    (108, 126, 70, 255), (140, 158, 92, 255))
    out.alpha_composite(skulls[0], (ox, sy + sp_frame.height + 4))
    draw_text(out, "1240", ox + 14, sy + sp_frame.height + 7, 1, (208, 196, 150, 255))
    draw_text(out, "IN-GAME HUD", w - text_width("IN-GAME HUD", 1) - 8,
              h + panel_h - 12, 1, (90, 84, 76, 255))
    return out


# ================================================================ SAVE ========
def save(img, name, scale=1):
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(os.path.join(OUT, name))
    print("  wrote", name, img.size)


def build_preview(floor, wall, bonfire0, player0):
    """A composed, upscaled mood shot: torch-lit corridor with hero + bonfire."""
    TW = 16
    cols, rows = 15, 9
    scene = Image.new("RGBA", (cols * TW, rows * TW), (10, 9, 15, 255))
    # floor (bottom 3 rows) + walls (top rows)
    for cy in range(rows):
        for cx in range(cols):
            tile = floor if cy >= rows - 3 else wall
            scene.alpha_composite(tile, (cx * TW, cy * TW))
    # place bonfire on the floor, slightly right of centre
    bx = 8 * TW
    by = (rows - 3) * TW - 24 + 14
    scene.alpha_composite(bonfire0, (bx, by))
    # place hero to the left of the bonfire, feet on the floor line
    floor_line = (rows - 3) * TW
    px_ = 6 * TW - 4
    py_ = floor_line - 30          # frame feet sit on row 30
    scene.alpha_composite(player0, (px_, py_))

    # bake a warm radial light around the bonfire + cool darkness elsewhere
    light = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    lp = light.load()
    lcx, lcy = bx + 12, by + 12
    for y in range(scene.height):
        for x in range(scene.width):
            d = (((x - lcx) ** 2 + (y - lcy) ** 2) ** 0.5) / 120.0
            warm = max(0.0, 1.0 - d)
            warm = warm ** 1.6
            lp[x, y] = (255, 150, 70, int(90 * warm))
    # darkness overlay (multiply-ish): darker far from fire
    dark = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    dp = dark.load()
    for y in range(scene.height):
        for x in range(scene.width):
            d = (((x - lcx) ** 2 + (y - lcy) ** 2) ** 0.5) / 150.0
            a = min(200, int(210 * min(1.0, d)))
            dp[x, y] = (6, 6, 14, a)
    scene.alpha_composite(dark)
    scene.alpha_composite(light)
    return scene


def _apply_lighting(scene, sources):
    """Multiply scene toward ambient darkness, add warm firelight near sources."""
    w, h = scene.size
    px = scene.load()
    amb = 0.18
    fire = (255, 150, 70)
    for y in range(h):
        for x in range(w):
            s = 0.0
            for (lx, ly, rad, strg) in sources:
                dx = x - lx
                dy = y - ly
                d = (dx * dx + dy * dy) ** 0.5 / rad
                if d < 1.0:
                    f = (1.0 - d)
                    s += f * f * strg
            s = min(1.0, s)
            r, g, b, a = px[x, y]
            factor = amb + (1.0 - amb) * s
            nr = min(255, int(r * factor + fire[0] * s * 0.16))
            ng = min(255, int(g * factor + fire[1] * s * 0.16))
            nb = min(255, int(b * factor + fire[2] * s * 0.16))
            px[x, y] = (nr, ng, nb, 255)


def _blend_px(px, x, y, col, a):
    if a <= 0:
        return
    a = min(1.0, a)
    r, g, b, _ = px[x, y]
    px[x, y] = (int(r + (col[0] - r) * a),
                int(g + (col[1] - g) * a),
                int(b + (col[2] - b) * a), 255)


def build_mood_gif(pf, bf, tf, floor, wall):
    """A seamless looping mood shot: torch-lit corridor, flame, hero, embers."""
    N = 24
    cols, rows, TW = 15, 9, 16
    floor_line = (rows - 3) * TW
    bx, by = 8 * TW, floor_line - 24 + 14
    hx, hy = 6 * TW - 12, floor_line - 30
    torch_cells = [(2, 3), (12, 3)]
    lcx, lcy = bx + 12, by + 12
    frames = []
    for t in range(N):
        pl = pf[(t // 6) % 4]
        bo = bf[(t // 6) % 4]
        to = tf[(t // 5) % 2]
        scene = Image.new("RGBA", (cols * TW, rows * TW), (8, 7, 12, 255))
        for cy in range(rows):
            for cx in range(cols):
                scene.alpha_composite(floor if cy >= rows - 3 else wall,
                                      (cx * TW, cy * TW))
        for (cx, cy) in torch_cells:
            scene.alpha_composite(to, (cx * TW + 4, cy * TW + 2))
        scene.alpha_composite(bo, (bx, by))
        scene.alpha_composite(pl, (hx, hy))

        # firelight flicker (periodic -> seamless)
        ph = t / N * math.tau
        flick = 1.0 + 0.10 * math.sin(ph * 2) + 0.06 * math.sin(ph * 3)
        sources = [(lcx, lcy, 88, 1.08 * flick)]
        for (cx, cy) in torch_cells:
            tflick = 1.0 + 0.14 * math.sin(ph * 3 + cx)
            sources.append((cx * TW + 8, cy * TW + 6, 40, 0.75 * tflick))
        _apply_lighting(scene, sources)

        # rising embers (seamless: fade in low, fade out high)
        px = scene.load()
        for i in range(7):
            p = ((t + i * N / 7.0) % N) / N
            ex = int(lcx + math.sin(p * 6.28 + i * 1.7) * 5)
            ey = int((by + 15) - p * 46)
            a = math.sin(p * math.pi) * 0.9
            col = (255, 210 - int(90 * p), 90)
            if 0 <= ex < scene.width and 0 <= ey < scene.height:
                _blend_px(px, ex, ey, col, a)
                if ey + 1 < scene.height:
                    _blend_px(px, ex, ey + 1, col, a * 0.5)
        frames.append(scene.convert("RGB"))

    scale = 4
    big = [f.resize((f.width * scale, f.height * scale), Image.NEAREST)
           for f in frames]
    # quantize to a shared palette, no dithering, to keep pixels crisp
    pal_img = big[0].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    qframes = [im.quantize(palette=pal_img, dither=Image.Dither.NONE)
               for im in big]
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mood.gif")
    qframes[0].save(out, save_all=True, append_images=qframes[1:],
                    duration=90, loop=0, optimize=True, disposal=2)
    print("  wrote tools/mood.gif", big[0].size, N, "frames")


def build_combat_gif(hi, hr, ha, hl, ho, floor):
    """Showcase loop: every combat animation playing side by side."""
    from PIL import ImageDraw
    PW, PH = 48, 60
    panels = [("IDLE", hi, 6.0), ("RUN", hr, 10.0), ("ATTACK", ha, 11.0),
              ("ROLL", hl, 9.5), ("HOLLOW", ho, 0.0)]
    N, FPS = 30, 12.0
    floor_y = 44
    out_frames = []
    for i in range(N):
        t = i / FPS
        scene = Image.new("RGBA", (PW * len(panels), PH), (13, 12, 19, 255))
        for pi, (label, frames, fps) in enumerate(panels):
            ox = pi * PW
            for fx in range(0, PW, 16):                      # floor strip
                scene.alpha_composite(floor, (ox + fx, floor_y))
            if fps > 0.0:
                fr = frames[int(t * fps) % len(frames)]
            else:
                # hollow: idle -> wind up -> strike -> recover, on a timeline
                loop = t % 2.5
                if loop < 0.8:
                    fr = frames[0 if int(loop * 3) % 2 == 0 else 1]
                elif loop < 1.35:
                    fr = frames[2]                            # windup
                elif loop < 1.6:
                    fr = frames[3]                            # strike
                else:
                    fr = frames[0]
            scene.alpha_composite(fr, (ox + (PW - fr.width) // 2, floor_y - 31))
            d = ImageDraw.Draw(scene)
            d.text((ox + 4, 1), label, fill=(150, 140, 120, 255))
        out_frames.append(scene.convert("RGB"))

    scale = 5
    big = [f.resize((f.width * scale, f.height * scale), Image.NEAREST)
           for f in out_frames]
    pal_img = big[0].quantize(colors=96, method=Image.Quantize.MEDIANCUT)
    q = [im.quantize(palette=pal_img, dither=Image.Dither.NONE) for im in big]
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "combat.gif")
    q[0].save(out, save_all=True, append_images=q[1:], duration=int(1000 / FPS),
              loop=0, optimize=True, disposal=2)
    print("  wrote tools/combat.gif", big[0].size, N, "frames")


def main():
    print("Generating sprites ->", OUT)
    floor = stone_floor()
    wall = stone_wall()
    save(floor, "tile_floor.png")
    save(wall, "tile_wall.png")

    bf = bonfire_frames()
    save(hsheet(bf), "bonfire.png")

    tf = torch_frames()
    save(hsheet(tf), "torch.png")

    save(soft_light(), "light_soft.png")

    # --- one stone set per region ---
    # Four variants of each, picked per tile by a positional hash in Level.gd.
    # One tile repeated 24 times across a 384px screen reads as wallpaper; four
    # in a hashed shuffle reads as stone.
    for name in THEMES:
        save(hsheet([themed_floor(name, 11 + i * 37) for i in range(TILE_VARIANTS)]),
             "tile_floor_%s.png" % name)
        save(hsheet([themed_wall(name, 13 + i * 41) for i in range(TILE_VARIANTS)]),
             "tile_wall_%s.png" % name)
        save(hsheet([themed_cap(name, 5 + i * 43) for i in range(TILE_VARIANTS)]),
             "tile_cap_%s.png" % name)
    save(hsheet(deco_frames()), "deco.png")
    save(water_tile(), "tile_water.png")
    save(hsheet(mushroom_frames()), "mushroom.png")
    save(hsheet(brazier_frames()), "brazier.png")

    # --- traversal tiles + the inscribed stones ---
    save(beam_tile(), "tile_beam.png")
    save(ladder_tile(), "tile_ladder.png")
    save(hsheet(rune_frames()), "rune.png")
    # the orb is a thing in the world, not a HUD element
    save(hsheet(soul_orb_frames()), "soul_orb.png")

    # --- in-game combat animation sheets (44x32 frames, shared anchor) ---
    # One idle / run / attack set PER WEAPON: the knight visibly carries what he
    # has found, standing still or running, not only mid-swing.
    for kind in WEAPON_KINDS:
        save(hsheet(hero_idle_w(kind)), "hero_idle_%s.png" % kind)
        save(hsheet(hero_run_w(kind)), "hero_run_%s.png" % kind)
        save(hsheet(hero_attack_w(kind)), "hero_attack_%s.png" % kind)
    save(hsheet(hero_block()), "hero_block.png")
    save(hsheet(weapon_icons()), "weapon_icons.png")
    save(arrow_sprite(), "arrow.png")
    save(bolt_sprite(), "bolt.png")

    hi = hero_idle32()
    pf = hi                      # the idle frames double as the mood-shot hero
    hr = hero_run32()
    ha = hero_attack32()
    hl = hero_roll32()
    ho = hollow_frames()
    save(hsheet(hl), "hero_roll.png")
    save(hsheet(ho), "hollow.png")

    # inspection previews (upscaled) — not used by the game
    tools_dir = os.path.dirname(os.path.abspath(__file__))

    # combat contact sheet: one animation per row, one row per weapon swing
    anim_rows = [hi, hr, hl, ho] + [hero_attack_w(k) for k in WEAPON_KINDS]
    cols = max(len(r) for r in anim_rows)
    cell = 46
    cc = Image.new("RGBA", (cols * cell, len(anim_rows) * cell), (22, 20, 28, 255))
    for ri, row in enumerate(anim_rows):
        for ci, fr in enumerate(row):
            cc.alpha_composite(fr, (ci * cell + 1, ri * cell + 1))
    cc.resize((cc.width * 6, cc.height * 6), Image.NEAREST).save(
        os.path.join(tools_dir, "combat_contact.png"))
    print("  wrote tools/combat_contact.png")
    build_combat_gif(hi, hr, ha, hl, ho, floor)
    preview = build_preview(floor, wall, bf[0], pf[0])
    preview.resize((preview.width * 5, preview.height * 5), Image.NEAREST).save(
        os.path.join(tools_dir, "preview.png"))
    print("  wrote tools/preview.png", preview.size, "(x5)")

    # --- bone-themed interface art ---
    save_ui(ui_panel(), "panel.png")
    save_ui(vignette(), "vignette.png")
    save_ui(hsheet(flask_frames()), "flask.png")
    save_ui(font_sheet(), "font_5x7.png")
    skulls = skull_frames()
    save_ui(hsheet(skulls), "skull.png")
    HP_SPIKE, HP_CAP = 6, 7        # cap = spike + 1 (the plate's own rim)
    SP_SPIKE, SP_CAP = 5, 6
    hp_frame, hp_overlay = spiked_bar_frame(76, 10, spike=HP_SPIKE, tick_gap=9)
    sp_frame, sp_overlay = spiked_bar_frame(64, 9, spike=SP_SPIKE, tick_gap=9)
    save_ui(hp_frame, "bar_frame_hp.png")
    save_ui(hp_overlay, "bar_overlay_hp.png")
    save_ui(sp_frame, "bar_frame_sp.png")
    save_ui(sp_overlay, "bar_overlay_sp.png")
    backdrop = menu_backdrop(wall, floor)
    save_ui(backdrop, "menu_bg.png")

    ui_shot = build_ui_preview(backdrop, (hp_frame, hp_overlay, HP_CAP),
                                (sp_frame, sp_overlay, SP_CAP), skulls, floor)
    ui_shot.resize((ui_shot.width * 3, ui_shot.height * 3), Image.NEAREST).save(
        os.path.join(tools_dir, "ui_preview.png"))
    print("  wrote tools/ui_preview.png", ui_shot.size, "(x3)")

    build_mood_gif(pf, bf, torch_frames(), floor, wall)
    print("Done.")


if __name__ == "__main__":
    main()
