"""Makes the cosy build sounds from scratch, so they can be tweaked and
remade: python3 sounds.py ../sounds

Everything is soft: rounded sine and triangle tones, filtered noise and
gentle envelopes, nothing sharp. 16-bit mono 44.1 kHz .wav, the loudest
peaking at -3 dB (see GAIN); the game's buses set the overall loudness. Each sound has a few variations
(name_1, name_2, ...) with small changes in pitch and timing."""

import os
import sys
import wave

import numpy as np

RATE = 44100
PEAK = 10 ** (-3 / 20)


def t_of(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def env(t, attack, decay):
    """Quick rise, exponential fall."""
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * a * (3 - 2 * a) * np.exp(-np.maximum(t - attack, 0) / decay)


def sweep(t, f0, f1, time):
    """A sine gliding from f0 to f1 over `time`, then holding f1."""
    f = f1 + (f0 - f1) * np.exp(-t / time)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def biquad(x, kind, freq, q=0.7):
    """RBJ cookbook low-pass, high-pass or band-pass."""
    w = 2 * np.pi * freq / RATE
    alpha = np.sin(w) / (2 * q)
    c = np.cos(w)
    if kind == "low":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == "high":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else:
        b = [alpha, 0, -alpha]
    a = [1 + alpha, -2 * c, 1 - alpha]
    b = [v / a[0] for v in b]
    a1, a2 = a[1] / a[0], a[2] / a[0]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b[0] * xi + b[1] * x1 + b[2] * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def noise(rng, n):
    return rng.uniform(-1, 1, n)


def bell(t, f, decay):
    """A soft FM bell: a sine with a gently fading inharmonic shimmer."""
    mod = np.sin(2 * np.pi * f * 1.41 * t) * 1.2 * np.exp(-t / (decay * 0.4))
    return np.sin(2 * np.pi * f * t + mod) * env(t, 0.004, decay)


def fade_out(x, seconds=0.02):
    n = min(len(x), int(RATE * seconds))
    x[-n:] *= np.linspace(1, 0, n)
    return x


# ---------------------------------------------------------------- sounds
# Each takes a variation number k and a random generator.

def place(k, rng):
    """A soft, round pop, like a cork or a bubble: a short downward glide
    with a breath of noise at the start."""
    t = t_of(0.2)
    f = (520, 470, 580)[k]
    tone = sweep(t, f * 1.6, f, 0.018) * env(t, 0.003, 0.045)
    tone += 0.25 * sweep(t, f * 3.2, f * 2, 0.018) * env(t, 0.002, 0.02)
    puff = biquad(noise(rng, len(t)), "band", 1400, 1.2) * env(t, 0.001, 0.008)
    return tone + 0.35 * puff


def remove(k, rng):
    """A muffled 'fwump' with a few crumbly ticks after it."""
    t = t_of(0.5)
    body = biquad(noise(rng, len(t)), "low", 500 + 80 * k) * env(t, 0.012, 0.09)
    thump = sweep(t, 150 + 15 * k, 70, 0.05) * env(t, 0.004, 0.07)
    crumbs = np.zeros_like(t)
    for _ in range(6):
        at = rng.uniform(0.06, 0.3)
        ct = np.maximum(t - at, 0)
        click = biquad(noise(rng, len(t)), "band", rng.uniform(1800, 3200), 3)
        crumbs += click * (t >= at) * np.exp(-ct / 0.006) * rng.uniform(0.3, 0.6)
    return 1.6 * body + 0.8 * thump + 0.5 * crumbs


def rotate(k, rng):
    """A small wooden click, like turning a dial one notch."""
    t = t_of(0.08)
    f = (1250, 1150, 1350)[k]
    knock = np.sin(2 * np.pi * f * t) * env(t, 0.001, 0.012)
    knock += 0.5 * np.sin(2 * np.pi * f * 2.7 * t) * env(t, 0.0005, 0.005)
    body = np.sin(2 * np.pi * 330 * t) * env(t, 0.001, 0.02)
    return knock + 0.4 * body


def paint(k, rng):
    """A soft brush stroke: a breathy swish rising and falling."""
    t = t_of(0.3 + 0.04 * k)
    swish = biquad(noise(rng, len(t)), "band", 1700 + 200 * k, 0.8)
    shape = np.sin(np.pi * np.clip(t / t[-1], 0, 1)) ** 2
    return biquad(swish, "low", 3200) * shape


def error(k, rng):
    """A gentle two-note 'bonk-bonk' going down, round, not a buzzer."""
    out = np.zeros(int(RATE * 0.38))
    for at, f in ((0.0, (330, 311, 349)[k]), (0.13, (262, 247, 277)[k])):
        t = t_of(0.25)
        tone = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 2 * t)
        tone *= env(t, 0.006, 0.07)
        i = int(at * RATE)
        out[i:i + len(t)] += tone[:len(out) - i]
    return out


def finished(k, rng):
    """A little rising chime of three bell notes for finished building."""
    roots = (523.25, 587.33, 493.88)  # C5, D5, B4
    out = np.zeros(int(RATE * 1.2))
    for n, (at, ratio) in enumerate(((0.0, 1.0), (0.11, 1.26), (0.22, 1.5))):
        t = t_of(1.2 - at)
        tone = bell(t, roots[k] * ratio, 0.35) * (0.8 + 0.1 * n)
        i = int(at * RATE)
        out[i:i + len(t)] += tone
    return out


def wall(k, rng):
    """A soft block set down on another: a low woody knock and a tap."""
    t = t_of(0.22)
    f = (190, 175, 210)[k]
    knock = sweep(t, f * 1.4, f, 0.01) * env(t, 0.002, 0.05)
    tap = biquad(noise(rng, len(t)), "band", 900, 1.5) * env(t, 0.001, 0.015)
    return knock + 0.6 * tap


def floor(k, rng):
    """A soft pat, like a tile laid on a rug."""
    t = t_of(0.16)
    pat = biquad(noise(rng, len(t)), "low", 900 + 100 * k) * env(t, 0.002, 0.03)
    tone = np.sin(2 * np.pi * (240 + 20 * k) * t) * env(t, 0.002, 0.025)
    return 1.5 * pat + 0.5 * tone


SOUNDS = dict(place=place, remove=remove, rotate=rotate, paint=paint, error=error,
              finished=finished, wall=wall, floor=floor)
# Loudness of each against the others, as the peak sits at -3 dB for 1.0:
# small, frequent sounds quieter so they never nag.
GAIN = dict(place=1.0, remove=1.0, rotate=0.55, paint=0.6, error=0.7, finished=0.85,
            wall=0.8, floor=0.65)
VARIATIONS = 3


def save(path, x, gain=1.0):
    x = fade_out(x - np.mean(x))
    n = int(RATE * 0.002)
    x[:n] *= np.linspace(0, 1, n)
    x = x / np.max(np.abs(x)) * PEAK * gain
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "../sounds"
    names = sys.argv[2:] or list(SOUNDS)
    os.makedirs(folder, exist_ok=True)
    for name in names:
        for k in range(VARIATIONS):
            rng = np.random.default_rng(sum(map(ord, name)) * 10 + k)
            path = os.path.join(folder, "build_%s_%d.wav" % (name, k + 1))
            save(path, SOUNDS[name](k, rng), GAIN[name])
            print("made", path)


if __name__ == "__main__":
    main()
