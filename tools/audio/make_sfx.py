"""Synthesises every FLOWLINE sound effect from scratch (pure Python, no
samples), so all audio is original and needs no licence.

    python tools/audio/make_sfx.py

Writes mono 16-bit 44.1 kHz WAVs to assets/audio/.
Loops (engine_*, wind, scrape) contain a whole number of cycles and are
cross-faded at the seam so they loop without clicks.
"""

import math
import os
import random
import struct
import wave

RATE = 44100
TAU = 2 * math.pi
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


def write(name, samples, gain=0.9):
    peak = max(1e-6, max(abs(s) for s in samples))
    k = gain / peak
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))
    print("wrote", path, "%.2fs" % (len(samples) / RATE))


class OnePole:
    def __init__(self, cutoff):
        self.set(cutoff)
        self.y = 0.0

    def set(self, cutoff):
        self.a = 1.0 - math.exp(-TAU * cutoff / RATE)

    def __call__(self, x):
        self.y += self.a * (x - self.y)
        return self.y


def bandpass(lo, hi):
    low = OnePole(hi)
    high = OnePole(lo)

    def f(x):
        y = low(x)
        return y - high(y)
    return f


def seam(samples, fade=0.05):
    """Cross-fade the tail into the head so a loop is seamless."""
    n = int(fade * RATE)
    body = samples[:-n]
    tail = samples[-n:]
    for i in range(n):
        t = i / n
        body[i] = body[i] * t + tail[i] * (1 - t)
    return body


def engine(base_hz, seconds, resonances, bright, rough, seed):
    """Firing-pulse engine model. base_hz = firing frequency of the loop."""
    rng = random.Random(seed)
    n = int(seconds * RATE)
    out = [0.0] * n
    period = RATE / base_hz
    pulses = int(round(seconds * base_hz))
    for p in range(pulses):
        start = int(p * period)
        amp = 1.0 + rng.uniform(-rough, rough)
        cyl = p % 4  # slight per-cylinder character
        amp *= (1.0, 0.92, 1.06, 0.95)[cyl]
        for fr, tau, g in resonances:
            fr2 = fr * (1 + rng.uniform(-0.03, 0.03))
            length = int(tau * 6 * RATE)
            for i in range(length):
                j = start + i
                if j >= n:
                    j -= n  # wrap so the loop stays continuous
                t = i / RATE
                out[j] += amp * g * math.exp(-t / tau) * math.sin(TAU * fr2 * t)
    # body: fundamental + 2nd harmonic of the firing rate
    for i in range(n):
        t = i / RATE
        out[i] += 0.55 * math.sin(TAU * base_hz * t) + 0.25 * math.sin(TAU * base_hz * 2 * t + 0.6)
    # intake/exhaust hiss modulated by the firing rate
    bp = bandpass(300, 2500 * bright)
    for i in range(n):
        t = i / RATE
        mod = 0.6 + 0.4 * math.sin(TAU * base_hz * t)
        out[i] += bp(rng.uniform(-1, 1)) * 0.5 * bright * mod
    lp = OnePole(1800 + 2600 * bright)
    return [lp(s) for s in out]


def noise_loop(seconds, lo, hi, seed, flutter=0.0, flutter_hz=0.0):
    rng = random.Random(seed)
    bp = bandpass(lo, hi)
    n = int((seconds + 0.05) * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        m = 1.0 + flutter * math.sin(TAU * flutter_hz * t) * (0.5 + 0.5 * math.sin(TAU * 0.7 * t))
        out.append(bp(rng.uniform(-1, 1)) * m)
    return seam(out)


def whoosh():
    rng = random.Random(4)
    dur = 0.75
    n = int(dur * RATE)
    lp = OnePole(400)
    hp = OnePole(150)
    out = []
    for i in range(n):
        t = i / dur / RATE
        # Doppler-ish sweep: rises to the pass point then falls.
        c = 300 + 2600 * math.exp(-((t - 0.35) / 0.16) ** 2)
        lp.set(c)
        y = lp(rng.uniform(-1, 1))
        y -= hp(y)
        a = math.exp(-((t - 0.35) / 0.2) ** 2)
        out.append(y * a)
    return out


def crash():
    rng = random.Random(9)
    dur = 1.6
    n = int(dur * RATE)
    out = [0.0] * n
    lp = OnePole(1200)
    for i in range(n):
        t = i / RATE
        thump = math.sin(TAU * (55 + 40 * math.exp(-t * 20)) * t) * math.exp(-t * 7) * 1.4
        burst = lp(rng.uniform(-1, 1)) * math.exp(-t * 5.5) * 1.6
        crunch = rng.uniform(-1, 1) * math.exp(-t * 14) * 0.6
        out[i] = thump + burst + crunch
    # metal clanks: inharmonic partials at a few impact times
    for start, scale in ((0.0, 1.0), (0.11, 0.6), (0.27, 0.4), (0.5, 0.25)):
        partials = [rng.uniform(300, 700), rng.uniform(900, 1600), rng.uniform(1900, 3200)]
        s0 = int(start * RATE)
        for i in range(int(0.7 * RATE)):
            j = s0 + i
            if j >= n:
                break
            t = i / RATE
            v = sum(math.sin(TAU * f * t) * math.exp(-t * (6 + k * 4)) for k, f in enumerate(partials))
            out[j] += v * 0.35 * scale
    # glass tinkle
    for _ in range(40):
        s0 = int(rng.uniform(0.05, 0.9) * RATE)
        f = rng.uniform(3000, 7000)
        a = rng.uniform(0.05, 0.15)
        for i in range(int(0.06 * RATE)):
            j = s0 + i
            if j >= n:
                break
            t = i / RATE
            out[j] += math.sin(TAU * f * t) * math.exp(-t * 80) * a
    return out


def tone(freqs, dur, decay, attack=0.004, shimmer=0.0):
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        a = min(1.0, t / attack) * math.exp(-t / decay)
        v = 0.0
        for k, f in enumerate(freqs):
            v += math.sin(TAU * f * t + shimmer * math.sin(TAU * 6 * t)) / (k + 1)
        out.append(v * a)
    return out


def concat_notes(notes, gap):
    out = []
    for k, (freqs, dur, decay) in enumerate(notes):
        note = tone(freqs, dur, decay, shimmer=0.3)
        start = int(k * gap * RATE)
        if len(out) < start + len(note):
            out.extend([0.0] * (start + len(note) - len(out)))
        for i, v in enumerate(note):
            out[start + i] += v
    return out


def click():
    out = tone([1500, 3000], 0.05, 0.012, attack=0.001)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    # Engine layers: low rumble and high, brighter rasp. Game crossfades and
    # pitches them by RPM. Firing freq 60 Hz ~ 1800 rpm on a 4-cylinder.
    write("engine_low", seam(engine(60, 1.05, [(160, 0.006, 1.0), (420, 0.003, 0.4)], 0.5, 0.12, 1)), 0.8)
    write("engine_high", seam(engine(120, 1.05, [(380, 0.004, 1.0), (950, 0.002, 0.5), (1900, 0.0012, 0.25)],
                                     1.0, 0.08, 2)), 0.8)
    write("wind", noise_loop(2.0, 120, 1400, 3, flutter=0.25, flutter_hz=0.9), 0.7)
    write("scrape", noise_loop(1.0, 1800, 5200, 5, flutter=0.6, flutter_hz=13), 0.7)
    write("whoosh", whoosh(), 0.85)
    write("crash", crash(), 0.95)
    write("click", click(), 0.6)
    # Near-miss chimes, brighter per tier.
    write("near_0", tone([1320, 2640], 0.35, 0.10), 0.5)
    write("near_1", concat_notes([([1320, 2640], 0.3, 0.09), ([1760, 3520], 0.35, 0.1)], 0.06), 0.55)
    write("near_2", concat_notes([([1320, 2640], 0.3, 0.08), ([1760, 3520], 0.3, 0.08),
                                  ([2217, 4434], 0.4, 0.12)], 0.055), 0.6)
    write("flow_start", concat_notes([([523, 1046, 1569], 0.6, 0.25), ([659, 1318, 1977], 0.6, 0.25),
                                      ([784, 1568, 2352], 0.7, 0.3), ([1046, 2092, 3138], 1.0, 0.45)], 0.09), 0.7)


main()
