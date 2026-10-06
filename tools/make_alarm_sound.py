#!/usr/bin/env python3
"""Generates Sleep/Resources/gentle-alarm.wav: a ~28 s melodic, marimba-like alarm.

AlarmKit plays custom sounds from the app bundle (reports say they stop around 30 s and don't
loop) and can't ramp volume, so the file carries its own gentle crescendo. Melodic alarms were
associated with lower reported sleep inertia than plain tones (McFarlane et al. 2020).
Stdlib only; run:  python3 tools/make_alarm_sound.py
"""
import math
import os
import struct
import wave

RATE = 22050
LENGTH = 28.0

# Rising pentatonic phrases (MIDI note numbers), one phrase every 3.5 s.
PHRASES = [
    [67, 72, 76, 79],
    [69, 74, 77, 81],
    [67, 72, 76, 84],
    [72, 76, 79, 84],
]


def freq(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def marimba(t, f):
    # Fundamental plus a quickly decaying 4x partial, like a struck bar.
    env = math.exp(-t * 3.2)
    attack = min(1.0, t / 0.004)
    return attack * env * (math.sin(2 * math.pi * f * t) + 0.35 * math.exp(-t * 12) * math.sin(2 * math.pi * f * 4 * t))


def main():
    n = int(RATE * LENGTH)
    buf = [0.0] * n
    phrase_len = 3.5
    note_gap = 0.32
    t0 = 0.0
    i = 0
    while t0 < LENGTH - 2.0:
        phrase = PHRASES[i % len(PHRASES)]
        for k, note in enumerate(phrase):
            start = t0 + k * note_gap
            f = freq(note)
            s0 = int(start * RATE)
            for s in range(s0, min(n, s0 + int(RATE * 2.0))):
                buf[s] += marimba((s - s0) / RATE, f)
        t0 += phrase_len
        i += 1
    peak = max(abs(x) for x in buf) or 1.0
    out = []
    for s, x in enumerate(buf):
        t = s / RATE
        crescendo = 0.45 + 0.55 * min(1.0, t / (LENGTH * 0.8))
        fade = min(1.0, (LENGTH - t) / 0.5)
        out.append(int(max(-1.0, min(1.0, x / peak * 0.9 * crescendo * fade)) * 32767))
    path = os.path.join(os.path.dirname(__file__), "..", "Sleep", "Resources", "gentle-alarm.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack("<%dh" % len(out), *out))
    print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
