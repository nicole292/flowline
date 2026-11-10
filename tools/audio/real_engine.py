"""Engine sound from real recordings: the CC0 "Dyno Sessions: 190E" loops by
Chippy569 on Freesound (a Mercedes-Benz 190E 2.3-16V on a dynamometer at
full load, ~2550 and ~6200 rpm, three microphones). Sources and licences:
build/engine_real/src/SOURCES.txt (CC0 1.0: no attribution required).

    python tools/audio/real_engine.py           previews -> build/engine_choices/real_*.wav
    python tools/audio/real_engine.py MIX       install mix MIX as assets/audio/engine_{low,high}.wav
    python tools/audio/real_engine.py pops      cut the lift-off exhaust pops into assets/audio/pop_*.wav

Needs the `miniaudio` package (pip install miniaudio) to decode the MP3s.
The game pitches the low loop (~85 Hz firing) and the high loop (~206 Hz)
and crossfades them by RPM: see scripts/game/audio_director.gd.
"""

import math
import os
import struct
import sys
import wave

import miniaudio

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "build", "engine_real", "src")
OUT = os.path.join(ROOT, "build", "engine_choices")
AUDIO = os.path.join(ROOT, "assets", "audio")
RATE = 44100

LOW_FIRE = 85.0    # measured firing frequency of the 2500 rpm loop
HIGH_FIRE = 206.0  # and of the 6500 rpm loop

# mix name: (label, {mic: weight}); mics: D6 exhaust, 4062 engine bay, Distant
MIXES = {
    "exhaust": ("Exhaust mic: loud and raspy", {"D6": 1.0}),
    "engine": ("Engine-bay mic: mechanical, intake", {"4062": 1.0}),
    "blend": ("Blend of all three mics: most natural", {"D6": 0.6, "4062": 0.3, "Distant": 0.25}),
}


def load(name):
    d = miniaudio.decode_file(os.path.join(SRC, name + ".mp3"), output_format=miniaudio.SampleFormat.FLOAT32,
                              nchannels=1, sample_rate=RATE)
    return list(d.samples)


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(1, len(x)))


def make_loop(x, trim=0.04, fade=0.09):
    """Cuts the MP3 padding off both ends, then cross-fades the tail into
    the head (equal power) so the clip repeats without a click or a bump."""
    t = int(trim * RATE)
    x = x[t:len(x) - t]
    n = int(fade * RATE)
    body = x[:len(x) - n]
    tail = x[len(x) - n:]
    for i in range(n):
        a = i / n
        body[i] = body[i] * math.sin(a * math.pi / 2) + tail[i] * math.cos(a * math.pi / 2)
    m = sum(body) / len(body)   # no DC offset
    return [v - m for v in body]


def layer(rpm_tag, mix):
    out = None
    for mic, w in mix.items():
        x = make_loop(load("%s_%s" % (rpm_tag, mic)))
        g = w / max(rms(x), 1e-6)
        x = [v * g for v in x]   # each mic at the same loudness, then weighted
        out = x if out is None else [a + b for a, b in zip(out, x[:len(out)])] + out[len(x):]
    peak = max(abs(v) for v in out)
    return [v / peak * 0.9 for v in out]


def _read_wav(path):
    with wave.open(path) as w:
        d = w.readframes(w.getnframes())
    return [v / 32768.0 for v in struct.unpack("<%dh" % (len(d) // 2), d)]


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))


GEARS = [0.0, 0.17, 0.31, 0.46, 0.62, 0.80, 1.01]


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def fire_hz(rpm):
    """Same as AudioDirector: ~1600 rpm to ~7200 rpm, 4 cylinders, in equal musical steps."""
    return 55.0 * (240.0 / 55.0) ** rpm


def preview(low, high, seconds=10.0):
    """A drive with the game's gearbox and mixing: idle, full throttle
    through the gears, lift off."""
    n = int(seconds * RATE)
    out = [0.0] * n
    pl = ph = 0.0
    rpm, gear, speed = 0.25, 1, 0.0
    shift = 0.0
    lifted = False
    for i in range(n):
        t = i / RATE
        throttle = 1.0 if 1.0 <= t < 8.0 else 0.0
        speed = min(1.0, speed + (0.15 * (1.0 - speed) if throttle else -0.03) / RATE)
        was = gear
        while gear < len(GEARS) - 1 and speed > GEARS[gear]:
            gear += 1
        while gear > 1 and speed < GEARS[gear - 1] - 0.02:
            gear -= 1
        if gear != was:
            shift = 0.16
        shift = max(0.0, shift - 1.0 / RATE)
        lo, hi = GEARS[gear - 1], GEARS[gear]
        r = min(1.0, max(0.0, (speed - lo) / (hi - lo)))
        floor = 0.25 if gear == 1 else 0.42
        rpm += (floor + (1 - floor) * r - rpm) * (1 - math.exp(-(30.0 if shift > 0 else 9.0) / RATE))
        f = fire_hz(rpm)
        pl = (pl + min(2.2, max(0.5, f / LOW_FIRE))) % len(low)
        ph = (ph + min(1.3, max(0.5, f / HIGH_FIRE))) % len(high)

        def at(buf, p):
            j = int(p)
            a = p - j
            return buf[j] * (1 - a) + buf[(j + 1) % len(buf)] * a
        mix = smoothstep(115.0, 165.0, f)
        load_g = (1.0 if throttle else 10 ** (-7 / 20)) * 10 ** (-6 * (shift / 0.16) / 20)
        out[i] += (at(low, pl) * math.cos(mix * math.pi / 2) + at(high, ph) * math.sin(mix * math.pi / 2)) * load_g
        if not throttle and t >= 8.0 and not lifted and rpm > 0.6:  # lift-off crackle, as in the game
            lifted = True
            pop = _read_wav(os.path.join(AUDIO, "pop_crackle.wav"))
            for j, v in enumerate(pop):
                if i + j < n:
                    out[i + j] += v * 0.7
    peak = max(abs(v) for v in out)
    return [v / peak * 0.85 for v in out]


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "pops":
        make_pops()
        return
    if len(sys.argv) > 1:
        name = sys.argv[1]
        mix = MIXES[name][1]
        write(os.path.join(AUDIO, "engine_low.wav"), layer("19_2500", mix))
        write(os.path.join(AUDIO, "engine_high.wav"), layer("20_6500", mix))
        print("installed real engine mix", name)
        return
    os.makedirs(OUT, exist_ok=True)
    for i, (name, (label, mix)) in enumerate(MIXES.items(), 1):
        path = os.path.join(OUT, "arcade_%d_%s.wav" % (i, name))
        write(path, preview(layer("19_2500", mix), layer("20_6500", mix)))
        print("wrote", os.path.abspath(path), "-", label)



# --------------------------------------------------------------------------
# Exhaust pops on lift-off (CC0 recordings, build/engine_real/pops/SOURCES.txt):
# "Car Antilag" by modusmogulus (crackle burst + single pops) and
# "S012 Engine Backfire" by Pól.

POPS_SRC = os.path.join(ROOT, "build", "engine_real", "pops")
POP_CUTS = {  # name: (file, start s, end s)
    "pop_crackle": ("Car_Antilag__No_cleanup__32float_", 0.24, 0.74),
    "pop_1": ("Car_Antilag__No_cleanup__32float_", 1.07, 1.30),
    "pop_2": ("Car_Antilag__No_cleanup__32float_", 1.40, 1.66),
    "pop_3": ("S012_Engine_Backfire_Mono.wav", 0.17, 0.48),
}


def make_pops():
    for name, (src, a, b) in POP_CUTS.items():
        d = miniaudio.decode_file(os.path.join(POPS_SRC, src + ".mp3"), output_format=miniaudio.SampleFormat.FLOAT32,
                                  nchannels=1, sample_rate=RATE)
        x = list(d.samples)[int(a * RATE):int(b * RATE)]
        fi, fo = int(0.004 * RATE), int(0.06 * RATE)
        for i in range(fi):
            x[i] *= i / fi
        for i in range(fo):
            x[-1 - i] *= i / fo
        m = sum(x) / len(x)
        x = [v - m for v in x]
        peak = max(abs(v) for v in x)
        write(os.path.join(AUDIO, name + ".wav"), [v / peak * 0.9 for v in x])
        print("wrote pop", name, "%.2fs" % (len(x) / RATE))


if __name__ == "__main__":
    main()
