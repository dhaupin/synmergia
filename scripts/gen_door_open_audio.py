#!/usr/bin/env python3
# ============================================================================
# gen_door_open_audio.py -- Synmergia's first generated audio
#
# The repo has no recorded audio assets; following the model-pipeline
# convention (gen_blacksmith_model.py), sounds are GENERATED here --
# deterministic pure-math synthesis, no samples, no external deps.
# Run:  python3 scripts/gen_door_open_audio.py
#
# Outputs (committed):
#   game/audio/ancient_door_open.wav   -- the shard-wide door payoff:
#       a struck ceremonial bell (inharmonic partials, like a real
#       bell) over a low earth-rumble.
#   game/audio/mystery_solved.wav      -- two-note rise + sparkle for
#       puzzle solves.
#   game/audio/ui_click.wav            -- short soft tick for UI.
#
# Format: 16-bit PCM mono WAV (stdlib `wave` module), 22050 Hz.
# Deterministic: no randomness anywhere; same input -> byte-identical.
# ============================================================================
import math
import os
import struct
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "audio")


def write_wav(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    peak = max(abs(s) for s in samples) or 1.0
    norm = 0.85 / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)  # 16-bit
        w.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s * norm)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print("wrote %s (%.2fs, %d samples)" % (path, len(samples) / SAMPLE_RATE, len(samples)))


def env_exp(t, decay):
    return math.exp(-t / decay)


def soft_attack(t, attack):
    if t >= attack:
        return 1.0
    return 0.5 - 0.5 * math.cos(math.pi * t / attack) if attack > 0 else 1.0


def bell(freq, dur, decay, partials, amp=1.0):
    """A struck bell: inharmonic partials, exponential decay, soft attack."""
    out = []
    n = int(dur * SAMPLE_RATE)
    for i in range(n):
        t = i / SAMPLE_RATE
        e = env_exp(t, decay) * soft_attack(t, 0.012)
        s = 0.0
        for ratio, p_amp in partials:
            s += p_amp * math.sin(2.0 * math.pi * freq * ratio * t) * env_exp(t, decay / (1.0 + ratio))
        out.append(amp * e * s)
    return out


def mix_at(base, addition, offset_sec):
    start = int(offset_sec * SAMPLE_RATE)
    while len(base) < start + len(addition):
        base.append(0.0)
    for i, s in enumerate(addition):
        base[start + i] += s
    return base


def gen_door_open():
    """The payoff: G3 bell (f0 196) with classic inharmonic partials over
    a 55 Hz earth-rumble. Long tail (~4s) so it reads as CEREMONY."""
    bell_partials = [(1.0, 1.0), (2.01, 0.5), (2.99, 0.25), (4.42, 0.12), (5.43, 0.07)]
    ring = bell(196.0, 4.2, 1.15, bell_partials, amp=0.9)
    # Low rumble: 55 Hz + 41 Hz beat, slower decay, delayed 0.15s (the
    # stone grinding before the bell blooms).
    rumble = []
    n = int(3.8 * SAMPLE_RATE)
    for i in range(n):
        t = i / SAMPLE_RATE
        e = env_exp(t, 1.1) * soft_attack(t - 0.15, 0.35)
        rumble.append(0.5 * e * (math.sin(2.0 * math.pi * 55.0 * t) + 0.6 * math.sin(2.0 * math.pi * 41.0 * t)))
    out = mix_at(rumble, ring, 0.3)
    write_wav("ancient_door_open.wav", out)


def gen_mystery_solved():
    """Two-note rise E5 -> A5 with a small sparkle: 'the record opens'."""
    partials = [(1.0, 1.0), (2.0, 0.35), (3.01, 0.12)]
    n1 = bell(659.26, 0.9, 0.32, partials, amp=0.7)
    n2 = bell(880.0, 1.3, 0.45, partials, amp=0.75)
    out = mix_at(list(n1), n2, 0.22)
    # Sparkle: three tiny high sines after the rise.
    for k, (f, dt) in enumerate([(2637.0, 0.55), (3520.0, 0.65), (4400.0, 0.72)]):
        spark = []
        n = int(0.35 * SAMPLE_RATE)
        for i in range(n):
            t = i / SAMPLE_RATE
            spark.append(0.10 * math.sin(2.0 * math.pi * f * t) * env_exp(t, 0.08))
        out = mix_at(out, spark, dt + k * 0.04)
    write_wav("mystery_solved.wav", out)


def gen_ui_click():
    """A 45ms soft tick: fast-attack, fast-decay, slight pitch drop."""
    out = []
    n = int(0.05 * SAMPLE_RATE)
    for i in range(n):
        t = i / SAMPLE_RATE
        f = 1900.0 - 600.0 * (t / 0.05)
        e = env_exp(t, 0.011) * soft_attack(t, 0.002)
        out.append(0.8 * e * math.sin(2.0 * math.pi * f * t))
    write_wav("ui_click.wav", out)


if __name__ == "__main__":
    gen_door_open()
    gen_mystery_solved()
    gen_ui_click()
    print("GEN_DOOR_OPEN_AUDIO_DONE -> " + OUT_DIR)
