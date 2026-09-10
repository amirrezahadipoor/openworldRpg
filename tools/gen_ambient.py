#!/usr/bin/env python3
"""Synthesises the world's ambience beds.

The game had a score and thirteen one-shot effects but no *place*: no wind, no
water, no fire, no cave. Rather than pull another licence into the project, the
beds are generated here — noise shaped by filters, which is exactly what wind,
rain, fire and water are — so the output is the project's own work (CC0, see
CREDITS.md).

Each bed is a seamless loop: the generator builds N seconds of signal and then
cross-fades the tail into the head, so looping is inaudible.

Output: assets/audio/ambient/amb_<id>.wav  (16-bit mono 16 kHz — beds are
broadband, so a high sample rate buys nothing but megabytes).

Run: python3 tools/gen_ambient.py
"""
import math
import os
import random
import struct
import wave

RATE = 16000
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "..", "assets", "audio", "ambient"))
LOOP_SECONDS = 8.0
FADE_SECONDS = 1.2


# --- building blocks ---------------------------------------------------------

def white(n: int, rng: random.Random) -> list:
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(sig: list, alpha: float) -> list:
    out, y = [], 0.0
    for x in sig:
        y += alpha * (x - y)
        out.append(y)
    return out


def highpass(sig: list, alpha: float) -> list:
    lp = lowpass(sig, alpha)
    return [s - l for s, l in zip(sig, lp)]


def bandpass(sig: list, low: float, high: float) -> list:
    return highpass(lowpass(sig, high), low)


def gain(sig: list, amp: float) -> list:
    return [s * amp for s in sig]


def mix(*layers: list) -> list:
    n = min(len(l) for l in layers)
    out = [0.0] * n
    for l in layers:
        for i in range(n):
            out[i] += l[i]
    return out


def wobble(sig: list, rate: float, depth: float) -> list:
    """Slow amplitude modulation — what makes wind sound like weather."""
    out = []
    for i, s in enumerate(sig):
        t = i / RATE
        out.append(s * (1.0 - depth + depth * (0.5 + 0.5 * math.sin(2 * math.pi * rate * t))))
    return out


def crackles(n: int, rng: random.Random, per_second: float, decay: float) -> list:
    """Sparse pops (fire, drips): a decaying impulse at random positions."""
    out = [0.0] * n
    count = int(per_second * n / RATE)
    for _ in range(count):
        start = rng.randrange(0, max(1, n - 32))
        length = int(RATE * decay)
        amp = rng.uniform(0.25, 1.0)
        for i in range(min(length, n - start)):
            out[start + i] += (amp * math.exp(-i / (RATE * decay * 0.25))
                               * rng.uniform(-1.0, 1.0))
    return out


def tone_bed(n: int, freq: float, amp: float, detune: float = 0.0) -> list:
    out = []
    for i in range(n):
        t = i / RATE
        v = math.sin(2 * math.pi * freq * t)
        if detune:
            v += math.sin(2 * math.pi * (freq * (1.0 + detune)) * t)
        out.append(v * amp)
    return out


# --- the beds ---------------------------------------------------------------

def bed_meadow(rng: random.Random, n: int) -> list:
    wind = wobble(bandpass(white(n, rng), 0.02, 0.16), 0.13, 0.5)
    leaves = wobble(bandpass(white(n, rng), 0.35, 0.8), 0.31, 0.35)
    return mix(gain(wind, 0.55), gain(leaves, 0.10), gain(tone_bed(n, 96.0, 0.015), 1.0))


def bed_frost(rng: random.Random, n: int) -> list:
    wind = wobble(bandpass(white(n, rng), 0.03, 0.30), 0.07, 0.65)
    high = wobble(bandpass(white(n, rng), 0.55, 0.95), 0.19, 0.5)
    return mix(gain(wind, 0.6), gain(high, 0.07))


def bed_lava(rng: random.Random, n: int) -> list:
    rumble = lowpass(white(n, rng), 0.012)
    pops = crackles(n, rng, per_second=3.0, decay=0.09)
    return mix(gain(rumble, 0.75), gain(lowpass(pops, 0.4), 0.18),
               gain(tone_bed(n, 54.0, 0.03), 1.0))


def bed_campfire(rng: random.Random, n: int) -> list:
    hiss = wobble(bandpass(white(n, rng), 0.20, 0.7), 0.9, 0.45)
    pops = crackles(n, rng, per_second=9.0, decay=0.05)
    return mix(gain(hiss, 0.34), gain(highpass(pops, 0.5), 0.22))


def bed_water(rng: random.Random, n: int) -> list:
    flow = bandpass(white(n, rng), 0.06, 0.45)
    burble = wobble(bandpass(white(n, rng), 0.12, 0.22), 1.7, 0.7)
    return mix(gain(flow, 0.5), gain(burble, 0.25))


def bed_cave(rng: random.Random, n: int) -> list:
    drone = tone_bed(n, 62.0, 0.06, detune=0.011)
    air = wobble(lowpass(white(n, rng), 0.05), 0.05, 0.4)
    drips = crackles(n, rng, per_second=0.9, decay=0.16)
    return mix(gain(drone, 1.0), gain(air, 0.35), gain(highpass(drips, 0.25), 0.30))


def bed_town(rng: random.Random, n: int) -> list:
    murmur = wobble(bandpass(white(n, rng), 0.05, 0.35), 0.4, 0.55)
    clatter = crackles(n, rng, per_second=1.6, decay=0.04)
    return mix(gain(murmur, 0.42), gain(highpass(clatter, 0.45), 0.10))


BEDS = {
    "amb_meadow": bed_meadow,
    "amb_frost": bed_frost,
    "amb_lava": bed_lava,
    "amb_campfire": bed_campfire,
    "amb_water": bed_water,
    "amb_cave": bed_cave,
    "amb_town": bed_town,
}


def seamless(sig: list) -> list:
    """Cross-fade the tail over the head so the loop point is inaudible."""
    n = len(sig)
    fade = int(FADE_SECONDS * RATE)
    body = sig[: n - fade]
    tail = sig[n - fade:]
    out = list(body)
    for i in range(fade):
        w = i / fade
        out[i] = out[i] * w + tail[i] * (1.0 - w)
    return out


def normalise(sig: list, peak: float = 0.85) -> list:
    top = max(1e-9, max(abs(s) for s in sig))
    k = peak / top
    return [s * k for s in sig]


def write_wav(path: str, sig: list) -> int:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in sig)
        w.writeframes(frames)
    return os.path.getsize(path)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    n = int(LOOP_SECONDS * RATE)
    for name, fn in BEDS.items():
        rng = random.Random(hash(name) & 0xFFFF)
        sig = normalise(seamless(fn(rng, n)))
        path = os.path.join(OUT_DIR, name + ".wav")
        size = write_wav(path, sig)
        print("  %-14s %5.0f KB  %.1fs loop" % (name, size / 1024, LOOP_SECONDS))
    print("wrote %d ambience beds to %s" % (len(BEDS), OUT_DIR))


if __name__ == "__main__":
    main()
