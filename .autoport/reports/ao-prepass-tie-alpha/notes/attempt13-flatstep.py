#!/usr/bin/env python3
"""DIRECTIVES v775512c234 — reimplementation FIDELE de flat_step (AmbientOcclusion.cpp:1153).

C'est la grandeur qui arme `ao_pattern_over_ceiling` (acquis owner « plus de damier ni
pixelisation »), plafond 10 pour 1000. Memes constantes que le moteur : kPlanarRel=0.02,
kPlanarAbs=1e-5, kAoStep=8, ciel a z<=1e-9, bord exclu. Diagnostic LOCAL : il ne remplace
aucune mesure appareil et ne publie aucune cle de proof.txt.

  usage: attempt13-flatstep.py <rejeu1> [<rejeu2> ...]
         chaque rejeu est un dossier notes/attempt11-a13-* (ou attempt11-reference)
"""
import sys, pathlib
import numpy as np

N = pathlib.Path(__file__).resolve().parent
ARCHIVE = N / 'attempt10-04-ssao-after/ao-hut-archive-22160-600/prepass-depth.f32'
W, H = 800, 600


def flat_step(ao, z):
    """Rend (pop, step) : population PLANE et marches d'AO, les deux axes cumules."""
    pop = step = 0
    for dy, dx in ((0, 1), (1, 0)):
        sl = (slice(1, -1), slice(1, -1))
        z0 = z[sl]
        zm = np.roll(np.roll(z, dy, 0), dx, 1)[sl]
        zp = np.roll(np.roll(z, -dy, 0), -dx, 1)[sl]
        a0 = ao[sl].astype(np.int32)
        am = np.roll(np.roll(ao, dy, 0), dx, 1)[sl].astype(np.int32)
        ap = np.roll(np.roll(ao, -dy, 0), -dx, 1)[sl].astype(np.int32)
        usable = (z0 > 1e-9) & (zm > 1e-9) & (zp > 1e-9)
        d1, d2 = z0 - zm, zp - z0
        planar = usable & (np.abs(d2 - d1) <= 0.02 * (np.abs(d1) + np.abs(d2)) + 1e-5)
        pop += int(planar.sum())
        step += int((planar & (np.abs(ap - 2 * a0 + am) > 8)).sum())
    return pop, step


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    z = np.fromfile(ARCHIVE, dtype='<f4').astype(np.float64).reshape(H, W)
    for name in argv[1:]:
        base = pathlib.Path(name)
        if not base.is_absolute():
            base = N / base
        for mode in ('ssao', 'hbao', 'gtao'):
            path = base / mode / 'ridge-3.r8'
            if not path.exists():
                print(f'{base.name} {mode} ABSENT {path}')
                continue
            ao = np.fromfile(path, dtype=np.uint8).reshape(H, W)
            pop, stp = flat_step(ao, z)
            # Le plafond est celui du moteur : 10 pour 1000. On le NOMME, on ne le deplace pas.
            x1000 = round(1000 * stp / pop) if pop else None
            print(f'{base.name:26s} {mode} pop={pop} step={stp} x1000={x1000} '
                  f'plafond=10 verdict={"AU-DESSUS" if x1000 and x1000 > 10 else "sous"}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
