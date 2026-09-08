#!/usr/bin/env python3
"""Synthetic CPU arithmetic only: neither shader execution nor game proof."""
import importlib.util
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
CANDIDATE = Path(__file__).with_name('tonemap-candidate.frag')
source = CANDIDATE.read_text()
spec = importlib.util.spec_from_file_location('preprocess', ROOT / 'game/graphics/opengl_renderer/shaders/preprocess.py')
preprocess = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preprocess)
gles = preprocess.to_gles(source, 'frag')
assert gles.startswith('#version 320 es\nprecision highp float;')
assert gles[gles.index('vec4 display_texel'): ] == source[source.index('vec4 display_texel'): ]


def shoulder(x, knee=.95):
    x = max(x, 0.)
    width = max(1. - knee, 1e-4)
    above = x - knee
    return min(x if x <= knee else 1. if above >= 2. * width else
               knee + above - above * above / (4. * width), 1.)


def interpolate(grid, uv, convert=False):
    height, width = len(grid), len(grid[0])
    px, py = uv[0] * width - .5, uv[1] * height - .5
    x, y = math.floor(px), math.floor(py)
    wx, wy = px - x, py - y
    out = [0.] * 4
    for dy, fy in ((0, 1. - wy), (1, wy)):
        for dx, fx in ((0, 1. - wx), (1, wx)):
            pixel = grid[min(max(y + dy, 0), height - 1)][min(max(x + dx, 0), width - 1)]
            for c in range(4):
                value = shoulder(pixel[c]) if convert and c < 3 else pixel[c]
                out[c] += fx * fy * value
    return out


def same(actual, expected):
    assert all(abs(a-b) < 1e-12 for a,b in zip(actual, expected)), (actual, expected)


grid = [[(.1, .2, .3, .1), (2.890625, .4, .5, .7)],
        [(.8, .7, .6, .3), (.2, .3, .4, .9)]]
for y, row in enumerate(grid):
    for x, pixel in enumerate(row):
        same(interpolate(grid, ((x+.5)/2, (y+.5)/2), True),
             [shoulder(v) for v in pixel[:3]] + [pixel[3]])
for uv, pixel in [((0., 0.), grid[0][0]), ((1., 1.), grid[1][1]),
                  ((-.1, 1.1), grid[1][0]), ((1.1, -.1), grid[0][1])]:
    same(interpolate(grid, uv, True), [shoulder(v) for v in pixel[:3]] + [pixel[3]])
low = [[(.1, .2, .3, .1), (.9, .4, .5, .7)], grid[1]]
for y in range(11):
    for x in range(11):
        uv = (x/10, y/10)
        same(interpolate(low, uv, True), interpolate(low, uv))
        same(interpolate(grid, uv, True)[3:], interpolate(grid, uv)[3:])
peak = [[(.2, .2, .2, .1), (2.890625, 2.890625, 2.890625, .9)]]
old = shoulder(interpolate(peak, (.5, .5))[0])
new = interpolate(peak, (.5, .5), True)[0]
assert old == 1. and abs(new - .6) < 1e-12
for i in range(1, 100):
    assert interpolate(peak, (.25 + .5*i/100, .5), True)[0] < 1.
print('SYNTHETIC_CPU_ONLY: centres/orientation=4 edges=4 subknee_identity=121 alpha=121 peak_weights=99 PASS')
print(f'SYNTHETIC_CPU_ONLY: peak=2.890625 neighbour=.2 midpoint old={old} candidate={new}')
print('PREPROCESS_ONLY: GLES320 highp; display_texel/main preserved PASS; no GPU/compiler/game run')
