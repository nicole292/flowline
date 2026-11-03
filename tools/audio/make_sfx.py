"""Synthesises every FLOWLINE sound effect from scratch (pure Python, no
samples), so all audio is original and needs no licence.

    python tools/audio/make_sfx.py [name ...]   (no names = all sounds)

Writes mono 16-bit 44.1 kHz WAVs to assets/audio/.
Loops (engine_*, wind, scrape) contain a whole number of cycles and are
cross-faded at the seam so they loop without clicks.
"""

import math
import os
import random
import struct
import sys
import wave

RATE = 44100
TAU = 2 * math.pi
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


ONLY = set(sys.argv[1:])


def write(name, samples, gain=0.9, rate=RATE):
    peak = max(1e-6, max(abs(s) for s in samples))
    k = gain / peak
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))
    print("wrote", path, "%.2fs" % (len(samples) / rate))



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


def car_engine(fire_hz, seconds, resonances, cutoff, seed, cyl=(1.0, 0.86, 0.95, 0.82), rumble=0.35):
    """Engine as an exhaust note: one pulse per cylinder firing, each ringing
    through a few damped exhaust resonances (`resonances`: Hz, decay/s, gain),
    with a fixed per-cylinder level pattern for the burble of a 4-cylinder.
    Pulses wrap around the loop end and the filters run over the loop twice,
    so it repeats seamlessly; fire_hz * seconds must be a multiple of 4."""
    rng = random.Random(seed)
    n = int(seconds * RATE)
    out = [0.0] * n
    firings = int(round(fire_hz * seconds))
    plen = int(2.5 * RATE / fire_hz)
    pulse = []
    for i in range(plen):
        t = i / RATE
        pulse.append(sum(g * math.exp(-t * d) * math.sin(TAU * f * t) for f, d, g in resonances))
    for k in range(firings):
        s0 = int(round(k * RATE / fire_hz))
        a = cyl[k % len(cyl)]
        for i, v in enumerate(pulse):
            out[(s0 + i) % n] += a * v
    # A little low rumble (loop-periodic noise) so it isn't a pure tone.
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    rl = OnePole(220)
    lp = OnePole(cutoff)
    lp2 = OnePole(cutoff)
    res = []
    for i in range(2 * n):
        x = out[i % n] + rumble * rl(noise[i % n])
        y = lp2(lp(x))
        if i >= n:
            res.append(y)
    return res


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
        c = 250 + 1300 * math.exp(-((t - 0.35) / 0.16) ** 2)
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
    lp = OnePole(700)
    lp_c = OnePole(2200)
    for i in range(n):
        t = i / RATE
        thump = math.sin(TAU * (55 + 40 * math.exp(-t * 20)) * t) * math.exp(-t * 7) * 1.6
        burst = lp(rng.uniform(-1, 1)) * math.exp(-t * 6.5) * 1.3
        crunch = lp_c(rng.uniform(-1, 1)) * math.exp(-t * 16) * 0.5
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


def horn(seconds=0.5):
    """Twin electric car horn (two buzzy notes a major third apart). Every
    partial fits a whole number of cycles in `seconds`, so it loops cleanly."""
    n = int(seconds * RATE)
    lp = OnePole(2600)
    out = []
    for i in range(2 * n):  # first pass settles the filter, second is kept
        t = (i % n) / RATE
        v = 0.0
        for f, a in ((420, 1.0), (500, 0.85)):
            ph = (f * t) % 1.0
            saw = 2.0 * ph - 1.0
            v += a * math.tanh(3.0 * (saw + 0.6 * math.sin(TAU * f * t)))
        y = lp(v)
        if i >= n:
            out.append(y)
    return out


# ---------------------------------------------------------------------------
# Background music: a mellow, looping lo-fi groove (pads, electric piano,
# bass, soft drums). Rendered at a lower rate; it sits quietly under the game.
# ---------------------------------------------------------------------------

MRATE = 22050


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def music():
    rng = random.Random(21)
    bpm = 84.0
    beat = 60.0 / bpm
    bar = beat * 4
    # Two bars per chord, 4 chords, played twice (the arp varies).
    chords = [  # (bass root, chord tones) as MIDI notes
        (48, [60, 64, 67, 71, 74]),   # Cmaj9
        (45, [57, 60, 64, 67, 71]),   # Am9
        (41, [57, 60, 64, 65, 69]),   # Fmaj7 (add9 feel)
        (43, [55, 59, 62, 65, 69]),   # G9
    ]
    bars = 16
    n = int(bars * bar * MRATE)
    out = [0.0] * n

    def add(start_s, samples):  # wraps around: notes ringing past the end loop to the start
        s0 = int(start_s * MRATE)
        for i, v in enumerate(samples):
            out[(s0 + i) % n] += v

    def note(freq, dur, attack, release, gain, partials=((1, 1.0),), detune=0.0, decay=None):
        m = int((dur + release) * MRATE)
        res = []
        for i in range(m):
            t = i / MRATE
            env = min(1.0, t / attack) if attack > 0 else 1.0
            if decay:
                env *= math.exp(-t / decay)
            if t > dur:
                env *= max(0.0, 1.0 - (t - dur) / release)
            v = 0.0
            for h, g in partials:
                v += g * math.sin(TAU * freq * h * t)
                if detune:
                    v += g * 0.7 * math.sin(TAU * freq * h * (1 + detune) * t + 1.3)
            res.append(v * env * gain)
        return res

    for b in range(0, bars, 2):
        root, tones = chords[(b // 2) % 4]
        t0 = b * bar
        # Pad: soft, slowly swelling chord.
        for m in tones[:4]:
            add(t0, note(midi_hz(m), 2 * bar - 0.2, 0.9, 1.2, 0.09,
                         ((1, 1.0), (2, 0.18)), detune=0.0025))
        # Bass: root on 1 and 3, a passing fifth before the change.
        for k, (beat_i, m) in enumerate([(0, root), (2, root), (4, root), (6, root), (7.5, root + 7)]):
            add(t0 + beat_i * beat, note(midi_hz(m - 12 if m > 45 else m), beat * 0.9, 0.01, 0.15, 0.32,
                                          ((1, 1.0), (2, 0.25)), decay=0.7))
        # Electric piano: lazy eighth-note arpeggio, a different pattern on the repeat.
        pattern = [0, 2, 4, 1, 3, 2, 4, 3] if b < 8 else [4, 2, 3, 1, 2, 0, 3, 4]
        for e in range(16):
            if rng.random() < 0.18:
                continue  # leave some space
            m = tones[pattern[e % 8]] + 12
            swing = 0.06 * beat if e % 2 else 0.0
            add(t0 + e * beat * 0.5 + swing,
                note(midi_hz(m), 0.25, 0.004, 0.5, 0.11 * rng.uniform(0.7, 1.0),
                     ((1, 1.0), (2, 0.35), (3, 0.08)), decay=0.45))
    # Soft drums: kick on 1 and 3, rim on 2 and 4, quiet hats on the off-beats.
    for b in range(bars):
        t0 = b * bar
        for k in (0, 2):
            m = int(0.3 * MRATE)
            add(t0 + k * beat, [math.sin(TAU * (48 + 70 * math.exp(-i / MRATE * 30)) * i / MRATE)
                                * math.exp(-i / MRATE * 11) * 0.5 for i in range(m)])
        for k in (1, 3):
            hp = OnePole(1200)
            add(t0 + k * beat, [(lambda x: x - hp(x))(rng.uniform(-1, 1)) * math.exp(-i / MRATE * 40) * 0.12
                                for i in range(int(0.12 * MRATE))])
        for k in range(4):
            hp = OnePole(5000)
            add(t0 + (k + 0.5) * beat + 0.05 * beat,
                [(lambda x: x - hp(x))(rng.uniform(-1, 1)) * math.exp(-i / MRATE * 90) * 0.05
                 for i in range(int(0.05 * MRATE))])
    # Warm it up: gentle low-pass and soft saturation (two passes so the filter is settled at the seam).
    lp = OnePole(3200)
    for i in range(n):
        lp(out[i])
    return [math.tanh(lp(v) * 1.4) for v in out]


def click():
    out = tone([1500, 3000], 0.05, 0.012, attack=0.001)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    sounds = {
        # Engine layers: a warm low hum and a smoother high voice. The game
        # crossfades and pitches them by RPM. 60 Hz firing ~ 1800 rpm (4-cyl).
        # Engine layers: a deep idle/low-rev note and a tighter high-rev note.
        # The game pitches each only within about 0.6x-1.8x and crossfades.
        # Long-ringing pulses and nearly even cylinders: shorter rings and a
        # strong per-cylinder pattern made a rattle at low revs.
        "engine_low": lambda: (car_engine(60, 1.0, [(140, 28, 1.0), (330, 60, 0.4), (720, 160, 0.08)],
                                          800, 1, cyl=(1.0, 0.96, 0.99, 0.95), rumble=0.15), 0.8),
        "engine_high": lambda: (car_engine(140, 1.0, [(260, 70, 1.0), (560, 140, 0.4), (1150, 300, 0.08)],
                                           1500, 2, cyl=(1.0, 0.95, 0.98, 0.94), rumble=0.2), 0.8),
        "wind": lambda: (noise_loop(2.0, 70, 520, 3, flutter=0.15, flutter_hz=0.5), 0.6),
        "scrape": lambda: (noise_loop(1.0, 600, 2200, 5, flutter=0.3, flutter_hz=8), 0.55),
        "whoosh": lambda: (whoosh(), 0.85),
        "crash": lambda: (crash(), 0.95),
        "click": lambda: (click(), 0.6),
        "horn": lambda: (horn(), 0.75),
        # Near-miss chimes, brighter per tier.
        "near_0": lambda: (tone([1320, 2640], 0.35, 0.10), 0.5),
        "near_1": lambda: (concat_notes([([1320, 2640], 0.3, 0.09), ([1760, 3520], 0.35, 0.1)], 0.06), 0.55),
        "near_2": lambda: (concat_notes([([1320, 2640], 0.3, 0.08), ([1760, 3520], 0.3, 0.08),
                                         ([2217, 4434], 0.4, 0.12)], 0.055), 0.6),
        "flow_start": lambda: (concat_notes([([523, 1046, 1569], 0.6, 0.25), ([659, 1318, 1977], 0.6, 0.25),
                                             ([784, 1568, 2352], 0.7, 0.3), ([1046, 2092, 3138], 1.0, 0.45)],
                                            0.09), 0.7),
    }
    for name, make in sounds.items():
        if not ONLY or name in ONLY:
            samples, gain = make()
            write(name, samples, gain)
    if not ONLY or "music" in ONLY:
        write("music", music(), 0.8, rate=MRATE)


main()
