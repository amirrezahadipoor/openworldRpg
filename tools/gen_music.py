#!/usr/bin/env python3
"""Procedural music pack (pure stdlib, deterministic) — Phase 11.

Synthesizes five seamless-loop ambience/combat tracks to assets/audio/music/:
  title, meadow, barrens, frost, combat
22050 Hz mono 16-bit WAV, loop-safe via tail->head crossfade. CC0 by
construction (all generated here; see CREDITS.md).
"""
import math
import os
import random
import struct
import zlib

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")

NOTE_NAMES = {}
_base = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    n = name.strip()
    acc = 0
    if "#" in n:
        acc = 1
    elif "b" in n and len(n) > 2:
        acc = -1
    letter = n[0]
    octave = int(n[-1])
    return 12 * (octave + 1) + _base[letter] + acc


def freq(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


class Buf:
    def __init__(self, n):
        self.n = n
        self.d = [0.0] * n

    def add(self, start, samples, amp):
        s = int(start)
        for i, v in enumerate(samples):
            j = s + i
            if 0 <= j < self.n:
                self.d[j] += v * amp


def one_pole_lowpass(sig, alpha):
    out = []
    y = 0.0
    for x in sig:
        y += alpha * (x - y)
        out.append(y)
    return out


def adsr_env(n, a, d, s_level, r, total):
    """Simple AR-ish envelope: attack, decay to sustain, release at end."""
    env = []
    for i in range(total):
        t = i
        if t < a:
            e = t / max(1, a)
        elif t < a + d:
            e = 1.0 - (1.0 - s_level) * ((t - a) / max(1, d))
        else:
            e = s_level
        rel_start = total - r
        if t > rel_start:
            e *= max(0.0, (total - t) / max(1, r))
        env.append(e)
    return env


def sine(n, f, phase=0.0):
    w = 2 * math.pi * f / SR
    return [math.sin(w * i + phase) for i in range(n)]


def noise(n, rng):
    return [rng.uniform(-1, 1) for _ in range(n)]


def voice_pad(dur, f, rng):
    n = int(dur * SR)
    det = 0.0035
    a = sine(n, f * (1 - det))
    b = sine(n, f * (1 + det), rng.random() * 6.28)
    c = sine(n, f * 2.0, rng.random() * 6.28)
    env = adsr_env(n, int(0.5 * SR), int(0.6 * SR), 0.75, int(0.8 * SR), n)
    return [((a[i] + b[i]) * 0.5 + c[i] * 0.16) * env[i] for i in range(n)]


def voice_pluck(dur, f, rng):
    n = int(dur * SR)
    w = 2 * math.pi * f / SR
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 5.2)
        v = math.sin(w * i) + 0.4 * math.sin(2 * w * i) + 0.12 * math.sin(3 * w * i)
        out.append(v * e * 0.5)
    return out


def voice_bell(dur, f, rng):
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 1.7)
        v = (math.sin(2 * math.pi * f * t)
             + 0.42 * math.sin(2 * math.pi * f * 2.76 * t) * math.exp(-t * 2.6)
             + 0.18 * math.sin(2 * math.pi * f * 5.4 * t) * math.exp(-t * 3.4))
        out.append(v * e * 0.5)
    return out


def voice_bass(dur, f, rng):
    n = int(dur * SR)
    w = 2 * math.pi * f / SR
    out = []
    for i in range(n):
        t = i / SR
        e = min(1.0, t / 0.015) * math.exp(-t * 2.2)
        v = math.sin(w * i) + 0.35 * math.sin(2 * w * i)
        out.append(v * e * 0.6)
    return out


def voice_kick(dur=0.22):
    n = int(dur * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 130.0 * math.exp(-t * 16.0) + 44.0
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase) * math.exp(-t * 9.0) * 0.9)
    return out


def voice_hat(rng, dur=0.06):
    n = int(dur * SR)
    nz = noise(n, rng)
    out = []
    prev = 0.0
    for i in range(n):
        hp = nz[i] - prev  # crude high-pass
        prev = nz[i]
        out.append(hp * math.exp(-(i / SR) * 60.0) * 0.25)
    return out


VOICES = {
    "pad": voice_pad,
    "pluck": voice_pluck,
    "bell": voice_bell,
    "bass": voice_bass,
}


def render_track(events, seconds, filter_alpha, gain=1.0):
    """events: list of (start_s, dur_s, midi_note_or_None, amp, voice)."""
    n = int(seconds * SR)
    buf = Buf(n)
    for (st, dur, note, amp, voice) in events:
        if voice == "kick":
            buf.add(st * SR, voice_kick(), amp)
        elif voice == "hat":
            buf.add(st * SR, voice_hat(random.Random(int(st * 1000))), amp)
        else:
            fn = VOICES[voice]
            buf.add(st * SR, fn(dur, freq(note), random.Random(note * 7 + int(st * 97))), amp)
    sig = one_pole_lowpass(buf.d, filter_alpha)
    # soft clip
    sig = [math.tanh(x * gain) for x in sig]
    return sig


def make_loop(sig, fade_s=2.5):
    """Blend the tail into the head so the loop point is seamless."""
    n = len(sig)
    f = int(fade_s * SR)
    for i in range(f):
        t = i / f
        sig[i] = sig[i] * t + sig[n - f + i] * (1.0 - t) * 0.9
    return sig[: n - f // 4]  # trim a little so the blended head owns the loop


def normalize(sig, peak=0.72):
    m = max(abs(x) for x in sig) or 1.0
    k = peak / m
    return [x * k for x in sig]


def write_wav(path, sig):
    data = b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in sig)
    n = len(sig)
    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + len(data)))
        f.write(b"WAVEfmt ")
        f.write(struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16))
        f.write(b"data")
        f.write(struct.pack("<I", len(data)))
        f.write(data)


def beat(bpm):
    return 60.0 / bpm


# ---- track builders --------------------------------------------------------

def track_title(rng):
    bpm = 66
    b = beat(bpm)
    bars = 8
    seconds = bars * 4 * b
    ev = []
    chords = [["D3", "A3", "F#4"], ["A2", "E3", "C#4"], ["B2", "F#3", "D4"], ["G2", "D3", "B3"]]
    for bar in range(bars):
        ch = chords[bar % 4]
        t0 = bar * 4 * b
        for note in ch:
            ev.append((t0, 4 * b, midi(note), 0.16, "pad"))
        for k in range(4):
            if rng.random() < 0.75:
                mel = ["D5", "F#5", "A5", "E5", "B4"][rng.randint(0, 4)]
                ev.append((t0 + k * b + b * 0.5, b * 1.2, midi(mel), 0.12, "pluck"))
    return ev, seconds


def track_meadow(rng):
    bpm = 84
    b = beat(bpm)
    bars = 8
    seconds = bars * 4 * b
    ev = []
    scale = ["G4", "A4", "B4", "D5", "E5", "G5"]
    chords = [["G3", "B3", "D4"], ["C3", "E3", "G3"], ["D3", "F#3", "A3"], ["E3", "G3", "B3"]]
    for bar in range(bars):
        ch = chords[bar % 4]
        t0 = bar * 4 * b
        for note in ch:
            ev.append((t0, 4 * b, midi(note), 0.14, "pad"))
        for k in range(8):
            if rng.random() < 0.6:
                ev.append((t0 + k * b * 0.5, b * 0.9, midi(rng.choice(scale)), 0.10, "pluck"))
        if bar % 2 == 1:
            ev.append((t0 + 3 * b, b * 1.5, midi("D6"), 0.07, "bell"))
    return ev, seconds


def track_barrens(rng):
    bpm = 70
    b = beat(bpm)
    bars = 8
    seconds = bars * 4 * b
    ev = []
    for bar in range(bars):
        t0 = bar * 4 * b
        ev.append((t0, 4 * b, midi("E2"), 0.22, "bass"))
        ev.append((t0, 4 * b, midi("B2"), 0.12, "pad"))
        ev.append((t0 + 2 * b, 2 * b, midi("E3"), 0.10, "pad"))
        for k in range(4):
            if rng.random() < 0.35:
                note = rng.choice(["E4", "G4", "A4", "B4", "D4"])
                ev.append((t0 + k * b + rng.random() * 0.2, b * 1.4, midi(note), 0.09, "pluck"))
        if bar % 2 == 0:
            ev.append((t0 + 3 * b, 0.3, None, 0.5, "kick"))
    return ev, seconds


def track_frost(rng):
    bpm = 60
    b = beat(bpm)
    bars = 8
    seconds = bars * 4 * b
    ev = []
    bells = ["A5", "C6", "E6", "B5", "D6", "G5"]
    for bar in range(bars):
        t0 = bar * 4 * b
        ev.append((t0, 4 * b, midi("A2"), 0.15, "pad"))
        ev.append((t0, 4 * b, midi("E3"), 0.10, "pad"))
        for k in range(4):
            if rng.random() < 0.5:
                ev.append((t0 + k * b + rng.choice([0.0, 0.5 * b]), b * 2.2,
                           midi(rng.choice(bells)), 0.08, "bell"))
    return ev, seconds


def track_combat(rng):
    bpm = 132
    b = beat(bpm)
    bars = 16
    seconds = bars * 2 * b
    ev = []
    riff = ["A2", "A2", "C3", "A2", "G2", "G2", "A2", "E2"]
    for bar in range(bars):
        t0 = bar * 2 * b
        for k in range(2):
            ev.append((t0 + k * b, 0.25, None, 0.6, "kick"))
            ev.append((t0 + k * b + 0.5 * b, 0.05, None, 0.5, "hat"))
        for k in range(4):
            note = riff[(bar * 4 + k) % 8]
            ev.append((t0 + k * b * 0.5, b * 0.45, midi(note), 0.20, "bass"))
        if bar % 4 == 3:
            ev.append((t0 + b, b * 0.9, midi("A4"), 0.10, "pluck"))
            ev.append((t0 + 1.5 * b, b * 0.9, midi("C5"), 0.10, "pluck"))
    return ev, seconds


TRACKS = {
    "title": (track_title, 0.20, 1.0),
    "meadow": (track_meadow, 0.24, 1.0),
    "barrens": (track_barrens, 0.16, 1.1),
    "frost": (track_frost, 0.22, 1.0),
    "combat": (track_combat, 0.30, 1.15),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (builder, alpha, gain) in TRACKS.items():
        rng = random.Random(hash(name) & 0xFFFF)
        ev, seconds = builder(rng)
        sig = render_track(ev, seconds, alpha, gain)
        sig = make_loop(sig, 2.0)
        sig = normalize(sig)
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, sig)
        print(f"{name}: {len(sig) / SR:.1f}s  {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
