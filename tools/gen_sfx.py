#!/usr/bin/env python3
"""DEPRECATED — replaced by real CC0/CC-BY audio (Phase B5).

The placeholder score and SFX are superseded by:
    bash tools/audio/vendor_audio.sh

Music: "Generic 8-bit JRPG Soundtrack" by Avgvst (CC-BY), Kenney SFX (CC0).
See CREDITS.md. Running this script regenerates placeholder audio that the game
no longer loads; it refuses to run without --force.
"""
import sys
if "--force" not in sys.argv:
    sys.exit(
        "refusing to run: superseded by tools/audio/vendor_audio.sh (real audio).\n"
        "  pass --force to regenerate placeholder audio deliberately."
    )

import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")


def env_exp(n: int, k: float = 6.0) -> list:
    return [math.exp(-k * i / max(1, n - 1)) for i in range(n)]


def env_fade(n: int) -> list:
    out = []
    a = max(1, int(n * 0.15))
    for i in range(n):
        if i < a:
            out.append(i / a)
        elif i > n - a:
            out.append((n - i) / a)
        else:
            out.append(1.0)
    return out


def tone(freq: float, dur: float, shape: str = "sine", vol: float = 0.5,
         slide_to: float = None, vibrato: float = 0.0) -> list:
    n = int(dur * RATE)
    out = []
    f = freq
    for i in range(n):
        t = i / RATE
        if slide_to is not None:
            f = freq + (slide_to - freq) * (i / max(1, n - 1))
        vib = 1.0 + vibrato * math.sin(2 * math.pi * 6 * t) if vibrato else 1.0
        ph = 2 * math.pi * f * t * vib
        if shape == "sine":
            v = math.sin(ph)
        elif shape == "square":
            v = 1.0 if math.sin(ph) >= 0 else -1.0
        elif shape == "saw":
            v = 2.0 * ((f * t) % 1.0) - 1.0
        elif shape == "tri":
            v = 2.0 / math.pi * math.asin(math.sin(ph))
        else:
            v = math.sin(ph)
        out.append(v * vol)
    return out


def noise(dur: float, vol: float = 0.5, lowpass: float = 0.0) -> list:
    n = int(dur * RATE)
    out, prev = [], 0.0
    for _ in range(n):
        v = random.uniform(-1, 1)
        if lowpass > 0.0:
            prev += lowpass * (v - prev)
            v = prev
        out.append(v * vol)
    return out


def mix(*parts) -> list:
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    return out


def seq(*parts, gap: float = 0.0) -> list:
    out = []
    g = int(gap * RATE)
    for p in parts:
        out.extend(p)
        out.extend([0.0] * g)
    return out


def write(name: str, samples: list, envelope="exp", k: float = 6.0):
    n = len(samples)
    if envelope == "exp":
        e = env_exp(n, k)
    elif envelope == "fade":
        e = env_fade(n)
    else:
        e = [1.0] * n
    peak = max(1e-6, max(abs(s) for s in samples))
    data = bytearray()
    for s, a in zip(samples, e):
        v = max(-1.0, min(1.0, (s / peak) * 0.72 * a))
        data += struct.pack("<h", int(v * 32767))
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(data))
    print(f"  wrote {name}.wav ({len(data)//1024} KB)")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    random.seed(7)  # deterministic output -> stable repo artifacts

    # Melee swing: airy whoosh
    write("attack_swing", noise(0.14, 0.9, lowpass=0.35), envelope="exp", k=9)
    # Enemy/player hit: thud
    write("hit", mix(tone(110, 0.12, "sine", 0.9, slide_to=55), noise(0.05, 0.4)), envelope="exp", k=10)
    # Player hurt: descending saw
    write("player_hurt", tone(330, 0.25, "saw", 0.55, slide_to=110), envelope="exp", k=6)
    # Dodge: quick filtered whoosh
    write("dodge", noise(0.18, 0.8, lowpass=0.2), envelope="exp", k=8)
    # Pickup: rising two-note blip
    write("pickup", seq(tone(660, 0.07, "sine", 0.5), tone(990, 0.09, "sine", 0.5)), envelope="exp", k=5)
    # UI click
    write("ui_click", tone(1000, 0.045, "square", 0.3), envelope="exp", k=14)
    # Item use: soft chime
    write("item_use", mix(tone(523, 0.16, "sine", 0.4), tone(784, 0.16, "sine", 0.25)), envelope="exp", k=5)
    # Purchase: coin double-blip
    write("purchase", seq(tone(1318, 0.05, "square", 0.25), tone(1760, 0.09, "square", 0.25), gap=0.02), envelope="exp", k=6)
    # Level up: bright rising arpeggio
    write("level_up", seq(tone(523, 0.09, "tri", 0.5), tone(659, 0.09, "tri", 0.5),
                          tone(784, 0.09, "tri", 0.5), tone(1046, 0.18, "tri", 0.5)), envelope="exp", k=3)
    # Enemy cast: dark hum
    write("enemy_cast", mix(tone(150, 0.22, "saw", 0.4, vibrato=0.02), tone(300, 0.22, "sine", 0.2)), envelope="fade")
    # Boss roar: low pitch-drop growl + rumble
    write("boss_roar", mix(tone(90, 0.6, "saw", 0.7, slide_to=45, vibrato=0.04),
                           noise(0.6, 0.35, lowpass=0.12)), envelope="exp", k=2)
    # Whirlwind: swirling whoosh
    write("ability_whirl", noise(0.32, 0.9, lowpass=0.25), envelope="fade")
    # Firebolt: electric zap
    write("ability_bolt", mix(tone(1200, 0.14, "square", 0.3, slide_to=300), noise(0.1, 0.25)), envelope="exp", k=7)

    print("SFX generation complete — all files original, CC0.")


if __name__ == "__main__":
    main()
