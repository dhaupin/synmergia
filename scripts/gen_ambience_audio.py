#!/usr/bin/env python3
"""Generate the ambience loop WAVs for AudioService's weather hookup.

Model-pipeline convention (see gen_door_open_audio.py): assets are
deterministic products of a script, not hand-recorded files. Every run
produces byte-identical output (fixed seed) so the committed .wav files
are reproducible.

Loops are seamless by construction: a base layer is built from summed
sines whose frequencies are integer multiples of 1/T (T = loop length),
so the end meets the beginning exactly. Transients (thunder) are
one-shot, not looped -- they fire stochastically from storm state at
runtime.

Outputs (game/audio/ambience/):
    wind_loop.wav     8.0 s  pink-ish noise bed, band-limited
    rain_loop.wav     8.0 s  dense droplet patter
    aurora_pad.wav   12.0 s  high shimmer drone (integer harmonics)
    birds_1..3.wav    0.4 s  species chirp one-shots (chorus law)
    whistler.wav      1.5 s  dispersive chirp (storm accent)
    thunder.wav       3.0 s  one-shot rumble

All 22050 Hz mono 16-bit, peak-normalized to 0.85.
"""

import math
import os
import random
import struct
import wave

SR = 22050
PEAK = 0.85
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "game", "audio", "ambience")


def write_wav(path: str, samples: list[float]) -> None:
    peak = max(abs(s) for s in samples) or 1.0
    scale = PEAK / peak
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767.0)) for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print(f"  wrote {path} ({len(samples) / SR:.2f}s)")


def loop_samples(duration_s: float) -> tuple[int, float]:
    """Sample count + 1/T fundamental so all harmonics loop seamlessly."""
    n = int(SR * duration_s)
    return n, 1.0 / (n / SR)


def gen_wind(seed: int = 1101) -> list[float]:
    rng = random.Random(seed)
    n, f0 = loop_samples(8.0)
    out = [0.0] * n
    # The seam fade below trims `fade` samples; compute the loop
    # fundamental from the TRIMMED length so harmonics still meet
    # exactly at the loop point.
    fade = n // 20
    f0 = 1.0 / ((n - fade) / SR)
    # Gusty bed: overlapping slow sines with random phases (integer
    # harmonics of 1/T => seamless), plus a filtered noise shimmer.
    for k in range(1, 14):
        amp = (1.0 / k) * (0.4 + 0.6 * rng.random())
        phase = rng.random() * math.tau
        freq = f0 * k * (1 + 7)  # 7-91 Hz gust band
        for i in range(n):
            out[i] += amp * math.sin(phase + math.tau * freq * i / SR)
    # Noise shimmer, loop-wrapped (difference fades the seam).
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    fade = n // 20
    for i in range(fade):
        a = i / fade
        noise[i] = noise[i] * a + noise[n - fade + i] * (1 - a)
    body = noise[: n - fade]
    out = out[: n - fade]
    out = [s * 0.6 + b * 0.35 for s, b in zip(out, body)]
    return out


def gen_rain(seed: int = 2202) -> list[float]:
    rng = random.Random(seed)
    n, _ = loop_samples(8.0)
    out = [0.0] * n
    # ~40 droplets/sec: short decaying noise ticks scattered in the
    # loop; drops near the seam wrap their tail to the start.
    drops = int(8.0 * 40)
    for _ in range(drops):
        start = rng.randrange(n)
        length = rng.randrange(60, 220)
        amp = rng.uniform(0.05, 0.25)
        for j in range(length):
            env = (1.0 - j / length) ** 2.2
            out[(start + j) % n] += amp * env * rng.uniform(-1, 1)
    return out


def gen_aurora_pad(seed: int = 3303) -> list[float]:
    rng = random.Random(seed)
    n, f0 = loop_samples(12.0)
    out = [0.0] * n
    # Shimmer: a high minor-ish chord of integer harmonics with slow
    # detune-beating partners (also integer harmonics => still loops).
    for k, base_amp in [(16, 0.5), (20, 0.35), (24, 0.4), (30, 0.25), (32, 0.2)]:
        phase = rng.random() * math.tau
        beat = rng.uniform(0.5, 2.0)
        for i in range(n):
            t = i / SR
            lfo = 0.7 + 0.3 * math.sin(math.tau * beat * f0 * t)  # 1/T multiple
            out[i] += base_amp * lfo * math.sin(phase + math.tau * f0 * k * i / SR)
    return out


def gen_whistler(seed: int = 4404) -> list[float]:
    rng = random.Random(seed)
    n = int(SR * 1.5)
    out = [0.0] * n
    # Dispersive falling chirp: frequency sweeps 4 kHz -> 300 Hz with a
    # dispersive envelope, plus a faint echo.
    for i in range(n):
        t = i / SR
        prog = t / 1.5
        freq = 300.0 + 3700.0 * (1.0 - prog) ** 1.6
        env = math.sin(math.pi * prog) ** 1.5
        out[i] = env * math.sin(math.tau * freq * t)
    echo_delay = int(SR * 0.22)
    for i in range(echo_delay, n):
        out[i] += 0.35 * out[i - echo_delay]
    return out


def gen_thunder(seed: int = 5505) -> list[float]:
    rng = random.Random(seed)
    n = int(SR * 3.0)
    out = [0.0] * n
    # Crack + rumble: an impulse train low-pass shaped by decay, with
    # slow sub-bass wobble.
    crack_at = int(SR * 0.05)
    for j in range(600):
        env = (1.0 - j / 600.0) ** 3.0
        out[crack_at + j] += 0.9 * env * rng.uniform(-1, 1)
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 1.4) * (1.0 - math.exp(-t * 40.0))
        wobble = math.sin(math.tau * 55.0 * t) + 0.5 * math.sin(math.tau * 37.0 * t)
        out[i] += 0.7 * env * wobble * (0.6 + 0.4 * rng.uniform(-1, 1))
    return out


def gen_birds(seed: int = 6606, chirps: int = 3) -> list[float]:
    """One species' chirp call (AudioService's birds_1..3 one-shots).

    Birds are not a loop: the ambience law fires short stochastic
    calls on the accent tick, spaced by chorus_density. Each variant
    is ~0.4 s of 2-5 kHz syllables (fast sweeps with a soft harmonic
    overtone, rounded attack/decay so they never click); the three
    committed variants differ in sweep shape and rhythm via the seed.
    """
    rng = random.Random(seed)
    length_s = 0.38
    n = int(SR * length_s)
    out = [0.0] * n
    # Syllables: non-overlapping, quick upsweeps or downsweeps.
    cursor = int(0.02 * SR)
    for _ in range(chirps):
        syll_n = int(SR * rng.uniform(0.06, 0.12))
        if cursor + syll_n >= n:
            break
        f_start = rng.uniform(1800.0, 2800.0)
        f_end = rng.uniform(3000.0, 5000.0)
        rising = rng.random() < 0.65
        loud = rng.uniform(0.6, 1.0)
        # Rounded envelope: raised-cosine attack/decay per syllable.
        for j in range(syll_n):
            prog = j / syll_n
            freq = f_start + (f_end - f_start) * (prog if rising else 1.0 - prog)
            env = math.sin(math.pi * prog) ** 1.4
            s = loud * env * (
                math.sin(math.tau * freq * j / SR)
                + 0.3 * math.sin(math.tau * freq * 2.0 * j / SR)
            )
            out[cursor + j] += s
        cursor += syll_n + int(SR * rng.uniform(0.03, 0.1))
    # Faint dawn-chorus companions a fifth above, low-pass soft.
    for i in range(n):
        out[i] += 0.15 * out[i] if i > 0 else 0.0  # simple smearing tail
    return out


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generating ambience loops ->", os.path.abspath(OUT_DIR))
    write_wav(os.path.join(OUT_DIR, "wind_loop.wav"), gen_wind())
    write_wav(os.path.join(OUT_DIR, "rain_loop.wav"), gen_rain())
    write_wav(os.path.join(OUT_DIR, "aurora_pad.wav"), gen_aurora_pad())
    write_wav(os.path.join(OUT_DIR, "whistler.wav"), gen_whistler())
    # Bird one-shots: three species variants for the chorus law
    # (AudioService fires them stochastically from clear/cloudy skies).
    for i in range(3):
        write_wav(
            os.path.join(OUT_DIR, "birds_%d.wav" % (i + 1)),
            gen_birds(seed=6606 + i * 111, chirps=2 + (i % 2)),
        )
    write_wav(os.path.join(OUT_DIR, "thunder.wav"), gen_thunder())
    print("Done.")


if __name__ == "__main__":
    main()
