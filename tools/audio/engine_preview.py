"""Engine sound candidates, and a preview of each as the game plays it.

    python tools/audio/engine_preview.py            write previews to build/engine_choices/
    python tools/audio/engine_preview.py NAME       install candidate NAME as the game's engine

A preview is a 9 s drive: idle, full throttle up through the gears, then a
steady cruise. It uses the same gearbox, pitch range and crossfade as
scripts/game/audio_director.gd, so it sounds like the car in the game.
"""

import math
import os
import shutil
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(__file__))
import make_sfx as sfx  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "build", "engine_choices")

# name: (label, low layer, high layer); a layer is (base firing Hz, resonances,
# cutoff, cylinder pattern, drive). base Hz x 1 s must divide by the pattern length.
CANDIDATES = {
    "1_v8_muscle": ("V8 muscle: deep, burbly",
                    (80, [(150, 20, 1.0), (300, 34, 0.7), (620, 80, 0.35), (1250, 200, 0.14), (2500, 480, 0.05)],
                     2600, (1.0, 0.78, 0.92, 0.74, 0.97, 0.8, 0.88, 0.76), 2.2),
                    (220, [(330, 40, 1.0), (660, 70, 0.6), (1320, 150, 0.32), (2640, 330, 0.12), (3960, 700, 0.04)],
                     5200, (1.0, 0.97, 0.99, 0.96), 2.6)),
    "2_supercar": ("Supercar: high, smooth scream",
                   (80, [(260, 30, 1.0), (520, 55, 0.6), (1040, 120, 0.3), (2080, 260, 0.1)],
                    5000, (1.0, 0.95, 0.98, 0.94), 1.6),
                   (220, [(470, 50, 1.0), (940, 90, 0.55), (1880, 180, 0.28), (3760, 400, 0.08)],
                    8000, (1.0, 0.99, 1.0, 0.98), 1.8)),
    "3_sport_six": ("Sporty 6-cylinder: smooth, in between",
                    (84, [(200, 24, 1.0), (420, 45, 0.55), (850, 100, 0.25), (1700, 240, 0.08)],
                     3200, (1.0, 0.9, 0.96, 0.88, 0.98, 0.9), 1.3),
                    (216, [(380, 45, 1.0), (760, 80, 0.5), (1520, 170, 0.22), (3040, 380, 0.06)],
                     6000, (1.0, 0.97, 0.99, 0.96, 0.98, 0.97), 1.4)),
}

GEARS = [0.0, 0.17, 0.31, 0.46, 0.62, 0.80, 1.01]
RATE = sfx.RATE


def layer(spec):
    base, res, cut, cyl, drive = spec
    return sfx.sports_engine(base, res, cut, cyl, drive)


def rpm_for(sf, gear):
    lo, hi = GEARS[gear - 1], GEARS[gear]
    r = min(1.0, max(0.0, (sf - lo) / (hi - lo)))
    return (0.25 if gear == 1 else 0.42) + ((1.0 - (0.25 if gear == 1 else 0.42)) * r)


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def preview(low, high, low_base, high_base, seconds=9.0):
    """Renders the drive with the game's mixing (audio_director.update_engine)."""
    n = int(seconds * RATE)
    out = []
    pl = ph = 0.0
    rpm, gear, speed = 0.25, 1, 0.0
    for i in range(n):
        t = i / RATE
        throttle = 1.0 if 1.0 <= t < 7.0 else 0.0
        speed = min(1.0, speed + (0.16 * (1.0 - speed) if throttle else -0.02) / RATE)
        while gear < len(GEARS) - 1 and speed > GEARS[gear]:
            gear += 1
        while gear > 1 and speed < GEARS[gear - 1] - 0.02:
            gear -= 1
        rpm += (rpm_for(speed, gear) - rpm) * (1 - math.exp(-9.0 / RATE))
        fire = 66 + (420 - 66) * rpm
        pl = (pl + min(2.0, max(0.6, fire / low_base))) % len(low)
        ph = (ph + min(2.0, max(0.6, fire / high_base))) % len(high)
        def at(buf, p):
            j = int(p)
            f = p - j
            return buf[j] * (1 - f) + buf[(j + 1) % len(buf)] * f
        mix = smoothstep(120, 190, fire)
        load = 1.0 if throttle else 10 ** (-5 / 20)
        g_lo = (1.0 - 0.7 * mix) * 10 ** (-9 / 20) * load
        g_hi = max(mix, 0.02) * 10 ** (-11 / 20) * load
        out.append(at(low, pl) * g_lo + at(high, ph) * g_hi)
    peak = max(abs(v) for v in out)
    return [v / peak * 0.85 for v in out]


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in samples))


def main():
    if len(sys.argv) > 1:  # install a candidate as the game's engine layers
        name = sys.argv[1]
        _, lo, hi = CANDIDATES[name]
        sfx.write("engine_low", layer(lo), 0.8)
        sfx.write("engine_high", layer(hi), 0.8)
        print("installed", name, "- base Hz", lo[0], hi[0])
        return
    os.makedirs(OUT, exist_ok=True)
    for name, (label, lo, hi) in CANDIDATES.items():
        path = os.path.join(OUT, name + ".wav")
        write(path, preview(layer(lo), layer(hi), lo[0], hi[0]))
        print("wrote", os.path.abspath(path), "-", label)


if __name__ == "__main__":
    main()
