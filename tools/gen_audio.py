"""
Procedural sound generator for Ashen Hollow.

Run:  python3 tools/gen_audio.py
Output: assets/audio/*.wav

Same principle as tools/gen_art.py: nothing is downloaded, sampled or licensed
from anywhere — every sound in the game is synthesised here from oscillators and
noise, so the whole soundtrack is a few hundred lines of Python that anyone can
read and change. Pure standard library; no numpy, no SciPy.

The palette is deliberately narrow, because a dark-fantasy game wants one:
  * low sine/triangle bodies for weight
  * filtered noise for steel, cloth and stone
  * a single minor scale (D natural minor) for anything tonal, so the menu
    chimes, the bonfire and the music are all in the same key
"""
import math
import os
import random
import struct
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
os.makedirs(OUT, exist_ok=True)

RATE = 22050          # plenty for this material, and a quarter the file size

# D natural minor, the key everything tonal in the game sits in.
ROOT_HZ = 146.83      # D3
SCALE = [0, 2, 3, 5, 7, 8, 10, 12, 14, 15, 17, 19]


def hz(step):
    """Frequency of a scale degree above the root."""
    return ROOT_HZ * (2.0 ** (SCALE[step % len(SCALE)] / 12.0)) * \
        (2 ** (step // len(SCALE)))


# ------------------------------------------------------------- primitives ---
def buf(seconds):
    return [0.0] * int(RATE * seconds)


def add(dst, src, at=0.0, gain=1.0):
    i0 = int(at * RATE)
    for i, v in enumerate(src):
        j = i0 + i
        if 0 <= j < len(dst):
            dst[j] += v * gain
    return dst


def env(n, attack, decay, sustain=0.0, release=0.0, hold=0.0):
    """A plain ADSR over n samples, as a list of gains."""
    a = int(attack * RATE)
    h = int(hold * RATE)
    d = int(decay * RATE)
    r = int(release * RATE)
    out = []
    for i in range(n):
        if i < a:
            out.append(i / max(1, a))
        elif i < a + h:
            out.append(1.0)
        elif i < a + h + d:
            t = (i - a - h) / max(1, d)
            out.append(1.0 + (sustain - 1.0) * t)
        elif i < a + h + d + r:
            t = (i - a - h - d) / max(1, r)
            out.append(sustain * (1.0 - t))
        else:
            out.append(0.0)
    return out


def tone(seconds, f0, f1=None, kind="sine", detune=0.0):
    """One oscillator, optionally gliding from f0 to f1."""
    n = int(RATE * seconds)
    f1 = f0 if f1 is None else f1
    out = []
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 * (f1 / f0) ** t if f0 > 0 else 0.0
        f += detune * math.sin(i / RATE * 5.0 * math.tau)
        phase += f / RATE
        p = phase % 1.0
        if kind == "sine":
            out.append(math.sin(p * math.tau))
        elif kind == "tri":
            out.append(4.0 * abs(p - 0.5) - 1.0)
        elif kind == "saw":
            out.append(2.0 * p - 1.0)
        else:                                  # square
            out.append(1.0 if p < 0.5 else -1.0)
    return out


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(RATE * seconds))]


def lowpass(sig, cutoff):
    """One-pole low-pass. Crude, and exactly right for this: it is what turns
    white noise into cloth, stone or a distant roar."""
    a = 1.0 - math.exp(-math.tau * cutoff / RATE)
    out = []
    y = 0.0
    for x in sig:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(sig, cutoff):
    return [x - y for x, y in zip(sig, lowpass(sig, cutoff))]


def apply(sig, gains):
    return [s * g for s, g in zip(sig, gains)]


def sweep_filter(sig, f0, f1):
    """Low-pass whose cutoff glides — a swing is a filter sweep more than it is
    a pitch."""
    out = []
    y = 0.0
    n = max(1, len(sig) - 1)
    for i, x in enumerate(sig):
        c = f0 * (f1 / f0) ** (i / n)
        a = 1.0 - math.exp(-math.tau * c / RATE)
        y += a * (x - y)
        out.append(y)
    return out


def normalise(sig, peak=0.86):
    m = max((abs(v) for v in sig), default=0.0)
    if m < 1e-9:
        return sig
    k = peak / m
    return [v * k for v in sig]


def fade_edges(sig, ms=4.0):
    """Kill the click at both ends. Every single sound needs this."""
    n = int(RATE * ms / 1000.0)
    for i in range(min(n, len(sig))):
        g = i / max(1, n)
        sig[i] *= g
        sig[-1 - i] *= g
    return sig


def crossfade_loop(sig, ms=180.0):
    """Fold the tail back over the head so the loop point is inaudible."""
    n = min(int(RATE * ms / 1000.0), len(sig) // 3)
    out = sig[:len(sig) - n]
    for i in range(n):
        g = i / max(1, n)
        out[i] = out[i] * g + sig[len(sig) - n + i] * (1.0 - g)
    return out


def save(sig, name, loop=False):
    if loop:
        sig = crossfade_loop(sig)
    else:
        sig = fade_edges(sig)
    sig = normalise(sig)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000)) for v in sig))
    print("  wrote %s  %.2fs" % (name + ".wav", len(sig) / RATE))


# =================================================================== SFX =====
# Each sound is built from the weapon or action it belongs to, not from a
# generic "hit" recycled six times: the axe is heavier and slower than the
# sword because its envelope IS heavier and slower.

def swing(seconds, f0, f1, cut0, cut1, body_hz, rng):
    """A weapon moving through air: a noise sweep with a low body under it."""
    n = int(RATE * seconds)
    air = sweep_filter(noise(seconds, rng), cut0, cut1)
    air = apply(air, env(n, seconds * 0.18, seconds * 0.82, 0.0))
    low = tone(seconds, f0, f1, "sine")
    low = apply(low, env(n, seconds * 0.05, seconds * 0.55, 0.0))
    out = buf(seconds)
    add(out, air, 0.0, 0.9)
    add(out, low, 0.0, 0.35)
    if body_hz:
        ring = apply(tone(seconds * 0.7, body_hz, body_hz * 0.94, "tri"),
                     env(int(RATE * seconds * 0.7), 0.004, seconds * 0.6, 0.0))
        add(out, ring, seconds * 0.12, 0.18)
    return out


def impact(seconds, thud_hz, bright, rng, crunch=0.5):
    """Something landing on something. thud_hz is the weight of it."""
    n = int(RATE * seconds)
    out = buf(seconds)
    body = apply(tone(seconds, thud_hz, thud_hz * 0.45, "sine"),
                 env(n, 0.002, seconds * 0.75, 0.0))
    add(out, body, 0.0, 0.9)
    grit = lowpass(noise(seconds * 0.5, rng), bright)
    grit = apply(grit, env(int(RATE * seconds * 0.5), 0.001, seconds * 0.4, 0.0))
    add(out, grit, 0.0, crunch)
    return out


def chime(steps, seconds, kind="sine", spread=0.0, rng=None):
    """A tonal cluster from the scale — menus, runes, souls."""
    out = buf(seconds)
    for i, st in enumerate(steps):
        f = hz(st)
        s = tone(seconds, f, f, kind)
        s = apply(s, env(int(RATE * seconds), 0.006, seconds * 0.9, 0.0))
        at = 0.0 if spread == 0.0 else i * spread
        add(out, s, at, 0.7 / max(1, len(steps)) * 2.0)
    return out


def build_sfx():
    rng = random.Random(1917)

    # --- the six weapons, each with its own weight ---
    save(swing(0.26, 320, 120, 900, 5200, 620, rng), "swing_sword")
    save(swing(0.42, 190, 70, 500, 3000, 300, rng), "swing_axe")
    save(swing(0.22, 420, 180, 1600, 7000, 900, rng), "swing_spear")
    save(swing(0.20, 260, 150, 700, 2600, 0, rng), "swing_shield")

    bow = buf(0.34)
    add(bow, apply(lowpass(noise(0.34, rng), 1800),
                   env(int(RATE * 0.34), 0.002, 0.30, 0.0)), 0.0, 0.5)
    add(bow, apply(tone(0.34, 240, 90, "tri"),
                   env(int(RATE * 0.34), 0.001, 0.26, 0.0)), 0.0, 0.8)
    save(bow, "shoot_bow")

    xb = buf(0.30)
    add(xb, apply(highpass(noise(0.30, rng), 2600),
                  env(int(RATE * 0.30), 0.001, 0.10, 0.0)), 0.0, 0.7)
    add(xb, apply(tone(0.30, 150, 60, "square"),
                  env(int(RATE * 0.30), 0.001, 0.22, 0.0)), 0.0, 0.6)
    save(xb, "shoot_crossbow")

    # --- contact ---
    save(impact(0.30, 150, 3200, rng, 0.55), "hit_flesh")
    blk = impact(0.26, 210, 6000, rng, 0.8)
    add(blk, apply(tone(0.26, 1450, 1180, "tri"),
                   env(int(RATE * 0.26), 0.001, 0.24, 0.0)), 0.0, 0.5)
    save(blk, "hit_block")
    brk = impact(0.55, 110, 2400, rng, 0.9)
    add(brk, apply(tone(0.55, 300, 70, "saw"),
                   env(int(RATE * 0.55), 0.004, 0.5, 0.0)), 0.0, 0.45)
    save(brk, "guard_break")
    save(impact(0.40, 120, 1800, rng, 0.35), "hurt")

    death = buf(1.6)
    add(death, apply(tone(1.6, 190, 44, "tri"), env(int(RATE * 1.6), 0.01, 1.5, 0.0)),
        0.0, 0.9)
    add(death, apply(lowpass(noise(1.6, rng), 700),
                     env(int(RATE * 1.6), 0.05, 1.4, 0.0)), 0.0, 0.4)
    save(death, "death")

    # --- movement ---
    jump = buf(0.20)
    add(jump, apply(lowpass(noise(0.20, rng), 2400),
                    env(int(RATE * 0.20), 0.002, 0.16, 0.0)), 0.0, 0.5)
    add(jump, apply(tone(0.20, 180, 300, "tri"),
                    env(int(RATE * 0.20), 0.004, 0.15, 0.0)), 0.0, 0.5)
    save(jump, "jump")
    save(impact(0.24, 95, 1500, rng, 0.7), "land")
    roll = apply(lowpass(noise(0.34, rng), 1100),
                 env(int(RATE * 0.34), 0.03, 0.28, 0.0))
    save(roll, "roll")

    # --- items and the world ---
    drink = buf(0.62)
    for i in range(3):
        g = apply(tone(0.10, 340 - i * 40, 220 - i * 40, "sine"),
                  env(int(RATE * 0.10), 0.004, 0.09, 0.0))
        add(drink, g, 0.06 + i * 0.16, 0.8)
    save(drink, "drink")

    fire = buf(1.10)
    add(fire, apply(lowpass(noise(1.10, rng), 900),
                    env(int(RATE * 1.10), 0.02, 1.0, 0.0)), 0.0, 0.8)
    add(fire, chime([0, 4, 7], 1.0), 0.05, 0.5)
    save(fire, "bonfire_light")

    save(chime([7, 11, 14], 1.1, "sine", 0.05), "rest")
    save(chime([14, 18], 0.5, "sine", 0.03), "soul")
    save(chime([0, 7, 12, 16], 1.3, "tri", 0.08), "weapon_found")
    save(chime([11, 14], 0.9, "sine", 0.10), "rune")
    save(chime([4, 7, 11, 14, 18], 2.4, "sine", 0.14), "victory")

    # --- interface ---
    save(apply(tone(0.06, 520, 520, "square"), env(int(RATE * 0.06), 0.002, 0.05, 0.0)),
         "menu_move")
    save(chime([7, 14], 0.28, "tri", 0.02), "menu_confirm")
    save(apply(tone(0.14, 300, 190, "tri"), env(int(RATE * 0.14), 0.003, 0.12, 0.0)),
         "menu_back")


# ================================================================= LOOPS =====
# Ambience is per region and music is one slow piece, because a game this dark
# wants the room to be louder than the tune.

def build_loops():
    rng = random.Random(70707)

    def drone(seconds, base, partials, breath, cut):
        out = buf(seconds)
        n = int(RATE * seconds)
        for k, gain in partials:
            # each partial detuned a little and drifting, so it never phases
            # into one flat sine
            s = tone(seconds, base * k, base * k * 1.004, "sine", detune=0.4)
            add(out, s, 0.0, gain)
        air = lowpass(noise(seconds, rng), cut)
        # a slow swell on the noise bed reads as a room breathing
        sw = [0.55 + 0.45 * math.sin(i / RATE * math.tau / breath) for i in range(n)]
        add(out, apply(air, sw), 0.0, 0.5)
        return out

    save(drone(9.0, 55.0, [(1, 0.5), (2, 0.22), (3, 0.10)], 5.0, 600), "amb_stone",
         loop=True)
    save(drone(9.0, 41.0, [(1, 0.55), (2, 0.2), (5, 0.06)], 7.0, 420), "amb_deep",
         loop=True)

    water = buf(9.0)
    add(water, drone(9.0, 62.0, [(1, 0.35), (2, 0.15)], 6.0, 380), 0.0, 1.0)
    for _ in range(26):                                # dripping
        f = rng.uniform(700, 1500)
        d = apply(tone(0.09, f, f * 0.55, "sine"), env(int(RATE * 0.09), 0.001, 0.085, 0.0))
        add(water, d, rng.uniform(0.0, 8.6), 0.30)
    save(water, "amb_water", loop=True)

    forge = buf(9.0)
    add(forge, drone(9.0, 48.0, [(1, 0.42), (2, 0.18)], 4.0, 900), 0.0, 1.0)
    roar = lowpass(noise(9.0, rng), 1400)
    n = int(RATE * 9.0)
    sw = [0.4 + 0.6 * (0.5 + 0.5 * math.sin(i / RATE * math.tau / 2.3)) for i in range(n)]
    add(forge, apply(roar, sw), 0.0, 0.55)
    save(forge, "amb_forge", loop=True)

    wind = buf(9.0)
    gust = lowpass(noise(9.0, rng), 700)
    sw = [0.25 + 0.75 * (0.5 + 0.5 * math.sin(i / RATE * math.tau / 3.7 + 1.1))
          for i in range(n)]
    add(wind, apply(gust, sw), 0.0, 1.0)
    add(wind, drone(9.0, 73.0, [(1, 0.20), (3, 0.07)], 8.0, 300), 0.0, 0.7)
    save(wind, "amb_wind", loop=True)

    # --- music: one slow piece in D minor, drone plus a sparse bell line ---
    def music(seconds, degrees, bell_gain, base):
        out = buf(seconds)
        add(out, drone(seconds, base, [(1, 0.45), (2, 0.18), (3, 0.07)], 6.5, 320),
            0.0, 1.0)
        t = 0.0
        i = 0
        while t < seconds - 3.0:
            st = degrees[i % len(degrees)]
            f = hz(st)
            b = apply(tone(2.6, f, f * 0.998, "sine"),
                      env(int(RATE * 2.6), 0.05, 2.4, 0.0))
            add(out, b, t, bell_gain)
            # a fifth above, quieter, one beat later — enough to sound composed
            b2 = apply(tone(2.0, f * 1.5, f * 1.497, "sine"),
                       env(int(RATE * 2.0), 0.08, 1.8, 0.0))
            add(out, b2, t + 0.9, bell_gain * 0.4)
            t += 3.1
            i += 1
        return out

    save(music(34.0, [7, 10, 8, 5, 7, 3], 0.30, 55.0), "music_keep", loop=True)
    save(music(28.0, [14, 12, 11, 7], 0.34, 41.0), "music_title", loop=True)


def main():
    print("Generating audio ->", OUT)
    build_sfx()
    build_loops()
    print("Done.")


if __name__ == "__main__":
    main()
