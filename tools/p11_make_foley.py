#!/usr/bin/env python3
"""Rebuild the original shrine foley. Standard-library authoring, no runtime dependency."""

import math
import random
import sys
import wave
from array import array
from pathlib import Path

RATE = 32_000
DEST = Path(__file__).resolve().parent.parent / "assets/audio/p11"
RNG = random.Random(1907)


def track(seconds):
    return [0.0] * round(RATE * seconds)


def put(mix, start, sound, gain=1.0, loop=False):
    offset = round(start * RATE)
    for i, value in enumerate(sound):
        index = offset + i
        if loop:
            index %= len(mix)
        if index >= len(mix):
            break
        mix[index] += value * gain


def resonances(length, modes, rise=0.003, bend=0.0):
    """A decaying body excited at several inharmonic frequencies."""
    mix = track(length)
    for freq, gain, decay in modes:
        phase = RNG.uniform(-math.pi, math.pi)
        for i in range(len(mix)):
            t = i / RATE
            fade = min(1.0, t / rise, (length - t) / 0.018)
            angle = math.tau * freq * (t + bend * 0.04 * (1.0 - math.exp(-t / 0.04)))
            mix[i] += gain * fade * math.exp(-t / decay) * math.sin(angle + phase)
    return mix


def grain(length, low, high, rise=0.004, decay=0.09):
    """Band-shaped friction, with an independent envelope for each contact."""
    lower = 1.0 - math.exp(-math.tau * low / RATE)
    upper = 1.0 - math.exp(-math.tau * high / RATE)
    a = b = 0.0
    mix = track(length)
    for i in range(len(mix)):
        source = RNG.uniform(-1.0, 1.0)
        a += (source - a) * lower
        b += (source - b) * upper
        t = i / RATE
        mix[i] = (b - a) * min(1.0, t / rise, (length - t) / 0.012) * math.exp(-t / decay)
    return mix


def drum():
    mix = track(0.96)
    for start, strength, scale in [(0.014, 0.85, 1.03), (0.245, 1.0, 1.0)]:
        put(mix, start, resonances(0.62, [
            (78 * scale, 0.9, 0.15), (129 * scale, 0.48, 0.084),
            (186 * scale, 0.23, 0.058), (307 * scale, 0.16, 0.025)
        ], bend=0.12), strength)
        put(mix, start, grain(0.10, 220, 3400, decay=0.021), strength * 0.9)
    return mix


def door_split():
    mix = track(0.55)
    for start, strength in [(0.016, 1.0), (0.070, 0.43), (0.093, 0.73), (0.190, 0.26)]:
        put(mix, start, grain(0.11, 470, 9400, decay=0.017), strength * 2.0)
        put(mix, start, resonances(0.19, [(173, 0.24, 0.04), (283, 0.42, 0.048),
                                          (743, 0.17, 0.03)], bend=-0.06), strength)
    return mix


def beam():
    mix = track(0.78)
    for start, strength in [(0.02, 0.35), (0.135, 1.0), (0.214, 0.57)]:
        put(mix, start, resonances(0.40, [(142, 0.46, 0.14), (510, 0.42, 0.088),
                                         (923, 0.28, 0.081)], 0.024, -0.31), strength)
        put(mix, start, grain(0.23, 490, 3200, 0.025, 0.080), 1.2 * strength)
    return mix


def water():
    mix = track(0.87)
    put(mix, 0.029, grain(0.52, 320, 8100, 0.07, 0.14), 1.25)
    put(mix, 0.044, grain(0.28, 80, 610, 0.023, 0.086), 1.6)
    for i in range(30):
        freq = RNG.uniform(490, 3070)
        put(mix, 0.045 + (i / 30) ** 1.54 * 0.56, resonances(0.09, [
            (freq, RNG.uniform(0.05, 0.26) * (1.0 - i / 37.0), 0.018),
            (freq * 1.84, 0.09, 0.012)
        ], 0.002, 0.39))
    return mix


def page():
    mix = track(0.68)
    for start, duration, strength in [(0.036, 0.20, 0.65), (0.175, 0.28, 1.0), (0.37, 0.12, 0.43)]:
        put(mix, start, grain(duration, 440, 8700, duration * 0.42, duration * 0.42), strength)
    put(mix, 0.31, resonances(0.16, [(619, 0.22, 0.035), (1339, 0.14, 0.02)]))
    return mix


def steps():
    mix = track(3.72)
    for i in range(22):
        start = i * 3.72 / 22 + RNG.uniform(-0.12, 0.12)
        strength = RNG.uniform(0.24, 0.95)
        put(mix, start, resonances(0.24, [(RNG.uniform(69, 101), 0.42, 0.053),
                                         (RNG.uniform(156, 239), 0.21, 0.038)]), strength, True)
        put(mix, start, grain(0.26, 170, 3700, 0.010, 0.066), strength * 1.35, True)
    return mix


def brush(finish=False):
    mix = track(0.40 if finish else 0.32)
    for start, strength in [(0.01, 0.45), (0.078, 1.0), (0.141, 0.58)]:
        put(mix, start, grain(0.14, 1350, 6800, 0.017, 0.046), strength)
    if finish:
        put(mix, 0.168, resonances(0.22, [(428, 0.57, 0.035), (1051, 0.32, 0.022),
                                         (2090, 0.19, 0.018)]), 0.7)
    return mix


def gate_rush():
    mix = track(1.22)
    put(mix, 0.006, resonances(0.52, [(58, 0.9, 0.16), (104, 0.67, 0.092),
                                     (156, 0.32, 0.054)], bend=0.19))
    put(mix, 0.023, grain(0.47, 110, 3200, 0.008, 0.14), 1.3)
    for start, strength in [(0.09, 0.75), (0.26, 0.54), (0.39, 0.72), (0.62, 0.36), (0.76, 0.29)]:
        put(mix, start, resonances(0.28, [(86, 0.55, 0.082), (267, 0.29, 0.051)]), strength)
        put(mix, start, grain(0.24, 190, 5300, 0.01, 0.056), 2.0 * strength)
    return mix


def pounce():
    mix = track(0.82)
    put(mix, 0.01, grain(0.36, 480, 4700, 0.090, 0.105), 1.4)
    put(mix, 0.19, resonances(0.32, [(91, 0.9, 0.078), (201, 0.42, 0.057),
                                    (484, 0.23, 0.026)], bend=-0.27))
    put(mix, 0.20, grain(0.17, 250, 5700, decay=0.033), 1.4)
    put(mix, 0.35, grain(0.33, 660, 4800, 0.037, 0.080), 0.72)
    return mix


def ember():
    mix = track(1.15)
    put(mix, 0.06, resonances(0.87, [(144, 0.59, 0.26), (212, 0.27, 0.24),
                                     (361, 0.20, 0.17)], 0.077, -0.22))
    put(mix, 0.30, grain(0.60, 390, 4300, 0.10, 0.15), 1.3)
    put(mix, 0.51, resonances(0.55, [(96, 0.47, 0.10), (161, 0.24, 0.13)], 0.037, -0.14))
    return mix


def release():
    mix = track(1.54)
    put(mix, 0.065, grain(0.45, 700, 6600, 0.064, 0.13), 0.63)
    put(mix, 0.18, resonances(1.22, [(622, 0.57, 0.36), (1079, 0.25, 0.24),
                                     (1574, 0.20, 0.11), (2831, 0.12, 0.09)], 0.008))
    put(mix, 0.47, resonances(0.92, [(928, 0.31, 0.29), (1472, 0.16, 0.21),
                                     (2281, 0.08, 0.10)], 0.012))
    return mix


def shoulder():
    mix = track(0.80)
    put(mix, 0.016, resonances(0.34, [(61, 0.95, 0.115), (130, 0.56, 0.073),
                                     (273, 0.30, 0.036)], bend=0.29))
    put(mix, 0.018, grain(0.27, 100, 2200, 0.008, 0.065), 1.75)
    put(mix, 0.099, resonances(0.50, [(412, 0.20, 0.14), (1139, 0.16, 0.087),
                                     (2218, 0.09, 0.079)]))
    put(mix, 0.24, grain(0.32, 180, 1800, 0.023, 0.095), 0.48)
    return mix


def loud(kind, damped):
    source_modes = {
        "gong": [(153, 0.56, 0.57), (263, 0.51, 0.39), (493, 0.4, 0.53),
                 (839, 0.25, 0.33), (1242, 0.24, 0.19), (2319, 0.23, 0.12)],
        "bell": [(289, 0.54, 0.58), (583, 0.48, 0.44), (713, 0.28, 0.4),
                 (1168, 0.25, 0.53), (1671, 0.22, 0.34), (2942, 0.18, 0.15)],
        "cry": [(322, 0.46, 0.21), (512, 0.38, 0.24), (1038, 0.35, 0.22),
                (1470, 0.24, 0.21), (2689, 0.18, 0.15)],
    }
    mix = track(0.30 if damped else 1.42)
    modes = source_modes[kind]
    if damped:
        modes = [(freq * 0.82, gain, decay * 0.13) for freq, gain, decay in modes[:3]]
    rise = 0.047 if kind == "cry" and not damped else 0.006
    put(mix, 0.012, resonances(0.24 if damped else 1.28, modes, rise, -0.64 if kind == "cry" else 0.04))
    put(mix, 0.01, grain(0.16 if damped else 0.49, 560, 5600, rise, 0.059 if damped else 0.19),
        0.9 if kind == "cry" else 0.55)
    return mix


def write(name, source, room=0.12, loop=False):
    left, right = source.copy(), source.copy()
    for channel, reflection in [(left, 0.023), (right, 0.031)]:
        put(channel, reflection, source, room, loop)
        put(channel, reflection * 2.43, source, room * 0.39, loop)
    if not loop:
        for i in range(round(RATE * 0.036)):
            fade = i / (RATE * 0.036)
            left[-i - 1] *= fade
            right[-i - 1] *= fade
    peak = max(abs(value) for channel in (left, right) for value in channel)
    pcm = array("h", (round(v * 0.64 / peak * 32767) for frame in zip(left, right) for v in frame))
    if sys.byteorder == "big":
        pcm.byteswap()
    with wave.open(str(DEST / (name + ".wav")), "wb") as handle:
        handle.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        handle.writeframes(pcm.tobytes())


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for name, samples, room in [
        ("watch_drum", drum(), 0.16), ("door_split", door_split(), 0.10),
        ("beam_creak", beam(), 0.17), ("water_alley", water(), 0.22),
        ("ledger_page", page(), 0.06), ("tide_steps", steps(), 0.14),
        ("register_brush", brush(), 0.04), ("gate_rush", gate_rush(), 0.23),
        ("rope_pounce", pounce(), 0.12), ("dying_ember", ember(), 0.13),
        ("send_off", release(), 0.20), ("iron_shoulder", shoulder(), 0.10),
        ("register_close", brush(True), 0.04),
    ]:
        write(name, samples, room, name == "tide_steps")
    for kind in ["gong", "bell", "cry"]:
        write(kind, loud(kind, False), 0.21)
        write(kind + "_damped", loud(kind, True), 0.05)


if __name__ == "__main__":
    main()
