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
    base = grid_to_img(BONFIRE_BASE)
    flames = [FLAME_A, FLAME_B, FLAME_C, FLAME_B]
    frames = []
    for fl in flames:
        frames.append(_overlay(base, fl, 3))
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


# ------------------------------------------------------------------ idle -----
def hero_idle32():
    body = grid_to_img(PLAYER)
    frames = []
    for bob in (0, 1, 1, 0):        # slow armoured breathing
        f = frame40(body, BODY_OX, BODY_OY + bob)
        _blade(f, REST_HAND[0], REST_HAND[1] + bob, REST_ANGLE, 12)
        frames.append(f)
    return frames


# ------------------------------------------------------------------- run -----
def hero_run32():
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
        _blade(f, REST_HAND[0], REST_HAND[1] + bob, REST_ANGLE + 0.15, 11)
        frames.append(f)
    return frames


# ---------------------------------------------------------------- attack -----
def hero_attack32():
    body = grid_to_img(PLAYER)
    frames = []
    # (blade angle, blade length, slash arc?, body lunge in px)
    specs = [(-2.15, 12, False, 0),   # 0 wind-up, blade back over the shoulder
             (-1.05, 13, False, 0),   # 1 raised
             (0.30, 14, True, 2),     # 2 strike — full extension + slash arc
             (1.15, 12, False, 1)]    # 3 recovery
    for ang, length, slash, lunge in specs:
        f = frame40(body, BODY_OX + lunge, BODY_OY)
        px, py = HAND[0] + lunge, HAND[1] - 1
        if slash:
            _arc(f, px, py, 13, -0.55, 0.95, PAL['W'], inner=PAL['S'])
        _blade(f, px, py, ang, length)
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

    # --- in-game combat animation sheets (44x32 frames, shared anchor) ---
    hi = hero_idle32()
    pf = hi                      # the idle frames double as the mood-shot hero
    hr = hero_run32()
    ha = hero_attack32()
    hl = hero_roll32()
    ho = hollow_frames()
    save(hsheet(hi), "hero_idle.png")
    save(hsheet(hr), "hero_run.png")
    save(hsheet(ha), "hero_attack.png")
    save(hsheet(hl), "hero_roll.png")
    save(hsheet(ho), "hollow.png")

    # inspection previews (upscaled) — not used by the game
    tools_dir = os.path.dirname(os.path.abspath(__file__))

    # combat contact sheet: one animation per row
    anim_rows = [hi, hr, ha, hl, ho]
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

    build_mood_gif(pf, bf, torch_frames(), floor, wall)
    print("Done.")


if __name__ == "__main__":
    main()
