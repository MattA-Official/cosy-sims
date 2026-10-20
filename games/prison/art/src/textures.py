"""Flat painted detail textures for the prison game.

Each texture is near-white greyscale and covers exactly one metre, so the
game tints it with the style's own colour (FloorDef, WallDef and so on keep
deciding the colour) and maps it one repeat per metre. They only add the
pattern: mortar lines, plank joins, grout, a little soft mottling.

Run from this folder (needs numpy and pillow):
    python3 textures.py ../textures
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = 512  # pixels per metre
RNG = np.random.default_rng(7)


def soft_noise(scale, size=SIZE, seed=None):
    """Smooth noise that tiles, by filtering white noise in frequency space.
    `scale` is the blob size in pixels. Returns values in about -1..1."""
    rng = np.random.default_rng(seed) if seed is not None else RNG
    white = rng.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    falloff = np.exp(-((fx ** 2 + fy ** 2) * (scale ** 2)))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * falloff))
    return out / (np.abs(out).max() + 1e-9)


def line_mask(coord, period, width):
    """1 near each multiple of `period` (in pixels), fading over `width`."""
    d = np.abs(((coord + period / 2) % period) - period / 2)
    return np.clip(1.0 - d / width, 0.0, 1.0) ** 1.5


def grid():
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    return x, y


def courses(rows, cols, mortar, offset=0.5, mortar_dark=0.8, face_jitter=0.025, seed=1):
    """Blocks or bricks in running bond: `rows` courses and `cols` units a
    metre, each unit a touch lighter or darker than its neighbours."""
    x, y = grid()
    rh, cw = SIZE / rows, SIZE / cols
    row = np.floor(y / rh)
    shifted = x + (row % 2) * cw * offset
    col = np.floor(shifted / cw) % cols
    rng = np.random.default_rng(seed)
    jitter = rng.uniform(-face_jitter, face_jitter, (rows, cols))
    face = 0.97 + jitter[row.astype(int), col.astype(int)]
    face += soft_noise(14, seed=seed + 10) * 0.012
    # Soft bevel: a little shade along the bottom of each unit.
    in_row = (y % rh) / rh
    face -= np.clip((in_row - 0.82) / 0.18, 0, 1) * 0.02
    lines = np.maximum(line_mask(y, rh, mortar), line_mask(shifted, cw, mortar))
    return face * (1 - lines) + mortar_dark * lines


def planks(count, mortar=2.2, seed=3, grain=0.02, length_breaks=1):
    """Boards running along x, `count` across a metre, with staggered ends."""
    x, y = grid()
    ph = SIZE / count
    board = np.floor(y / ph)
    rng = np.random.default_rng(seed)
    offsets = rng.uniform(0, SIZE, count)
    shifted = x + offsets[board.astype(int)]
    piece = np.floor(shifted / (SIZE / length_breaks))
    tone = rng.uniform(-0.03, 0.03, (count, length_breaks + 2))
    face = 0.96 + tone[board.astype(int), (piece % length_breaks).astype(int)]
    # Long soft grain streaks.
    streak = soft_noise(3, seed=seed + 1)
    streak = np.roll(streak, 0, axis=0)
    stretched = np.repeat(streak[:, ::8], 8, axis=1)  # stretch along x
    face += stretched * grain
    lines = np.maximum(line_mask(y, ph, mortar), line_mask(shifted, SIZE / length_breaks, mortar))
    return face * (1 - lines) + 0.8 * lines


def tiles(count, grout=2.0, seed=4):
    x, y = grid()
    t = SIZE / count
    rng = np.random.default_rng(seed)
    tone = rng.uniform(-0.012, 0.012, (count, count))
    face = 0.975 + tone[np.floor(y / t).astype(int), np.floor(x / t).astype(int)]
    face += soft_noise(30, seed=seed) * 0.008
    lines = np.maximum(line_mask(x, t, grout), line_mask(y, t, grout))
    return face * (1 - lines) + 0.86 * lines


def car_park(seed=15):
    """Tarmac with a white bay line along one x edge of every metre, so
    each tile is one bay: the floor colour tints it, and the lines are as
    bright as the texture gets."""
    x, _ = grid()
    out = 0.58 + soft_noise(50, seed=seed) * 0.02 + soft_noise(2.5, seed=seed + 1) * 0.015
    lines = line_mask(x, SIZE, 7.0) ** 0.35
    return out * (1 - lines) + 0.98 * lines


def mottled(blob, amount, base=0.95, fine=0.0, seed=5):
    out = base + soft_noise(blob, seed=seed) * amount
    if fine:
        out += soft_noise(2.5, seed=seed + 1) * fine
    return out


def speckle(density, dark=0.12, light=0.06, seed=6, size=1.6, base=0.95):
    """Grit: little dots, some darker and some lighter."""
    out = mottled(40, 0.025, base, seed=seed)
    rng = np.random.default_rng(seed)
    dots = soft_noise(size, seed=seed + 2)
    out -= np.clip(dots - (1 - density), 0, 1) / density * dark
    out += np.clip(-dots - (1 - density), 0, 1) / density * light
    return out


def leaves(seed=8):
    """Hedge: clumps of leaves with darker gaps."""
    out = 0.9 + soft_noise(9, seed=seed) * 0.12 + soft_noise(3, seed=seed + 1) * 0.06
    return out


def lawn(seed=9):
    """Mown grass: broad soft patches and faint mowing stripes."""
    x, _ = grid()
    stripes = (np.floor(x / (SIZE / 2)) % 2) * 0.025
    return 0.94 + soft_noise(60, seed=seed) * 0.03 + soft_noise(4, seed=seed + 1) * 0.02 + stripes


def ground(seed=10):
    """Terrain grass, mapped over several metres by the ground shader: only
    soft blotches, so the grid lines stay the main pattern."""
    return 0.95 + soft_noise(70, seed=seed) * 0.05 + soft_noise(8, seed=seed + 1) * 0.02


TEXTURES = {
    # Indoor walls
    "wall_blocks": lambda: courses(6, 2, 2.4, mortar_dark=0.84),  # chunky breeze blocks
    "wall_brick": lambda: courses(12, 4, 2.6, mortar_dark=0.86, face_jitter=0.05, seed=2),
    # Floors
    "floor_tiles": lambda: tiles(4),
    "floor_concrete": lambda: mottled(50, 0.035, fine=0.012, seed=11),
    "floor_wood": lambda: planks(5, length_breaks=1),
    "floor_paving": lambda: courses(2, 2, 3.2, offset=0.5, mortar_dark=0.82, face_jitter=0.03, seed=12),
    "floor_lawn": lawn,
    "floor_car_park": car_park,
    # Outdoor walls
    "wood_fence": lambda: planks(4, mortar=1.2, grain=0.035, seed=13),
    "hedge": leaves,
    # Paths and ground
    "path_grit": lambda: speckle(0.25, seed=14),
    "ground_grass": ground,
}


def save(arr, path):
    arr = np.clip(arr, 0, 1) ** (1 / 1.0)
    Image.fromarray((arr * 255).astype(np.uint8), "L").convert("RGB").save(path, optimize=True)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "textures")
    os.makedirs(out, exist_ok=True)
    for name, make in TEXTURES.items():
        save(make(), os.path.join(out, name + ".png"))
        print("wrote", name)
