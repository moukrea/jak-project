#!/usr/bin/env python3
"""fw3_model.py — DIRECTIVES vd9e8b66782 · phase Grecharged-foliage-wind3.

MODELE HORS LIGNE, PAS UNE MESURE. Il reproduit l'arithmetique EXACTE de
  - `update-wind`  (goal_src/jak1/engine/gfx/background/wind.gc:14, version « high fps »)
  - `do_wind_math` (game/graphics/opengl_renderer/background/Tie3.cpp:1864)
pour former une hypothese sur D1 avant de payer un build. Le round 3 a deja paye le prix
d'un modele qui sur-predisait de 70 % : tout chiffre d'ici est une PREDICTION, a confronter
a la course sur le binaire.
"""
import math, random, sys

SCALES = [0x2,0x5,0x2,0x3,0x2,0x2,0x3,0x10,0xa,0x2,0x4,0x2,0x8,0x2,0x2,0x10,
          0x2,0x2,0x8,0x2,0x10,0x2,0x4,0x10,0xa,0x2,0x4,0x2,0x8,0x2,0x2,0x10]

CX, CY, CZ, CW = 0.5, 100.0, 0.0166, -1.0

def run(ratio, frames, stiffness=0.1, wind_idx=7, seed=1234, native60=False):
    """ratio = time-adjust-ratio (1.0 a 60 fps, 4.0 a 15 fps, borne par (fmin 4.0 ...)).
    native60=True : la variante 'ring rempli a 60 Hz sans le facteur ratio' + ressort avance
    autant de fois qu'il y a de ticks 60 Hz dans l'image (ce que ferait une console a 60 fps)."""
    rng = random.Random(seed)
    arr = [(0.0, 0.0)] * 64
    wtime = 0
    wnorm_w = 0.0
    pos = [0.0, 0.0]   # my_vector[0..1]  (vf17 lu, DEJA multiplie par stiffness au pas precedent)
    vel = [0.0, 0.0]   # my_vector[2..3]  (vf18)
    ticks_per_frame = 1 if not native60 else max(1, int(round(ratio)))
    r = ratio if not native60 else 1.0

    shear_hist, sat_hits, samples = [], 0, 0
    raw_hist = []
    for f in range(frames):
        for k in range(ticks_per_frame):
            # ---- update-wind ----
            wnorm_w = wnorm_w + rng.uniform(-1024.0, 1024.0)
            wnorm_w = wnorm_w - float(int(wnorm_w / 65536.0)) * 65536.0
            rad = wnorm_w * (2.0 * math.pi / 65536.0)
            dirx, dirz = math.cos(rad), math.sin(rad)
            wtime += 1
            scaled = int(r * wtime)
            slot = scaled & 63
            f0_4 = rng.uniform(0.0, 100.0)
            v1_5 = scaled // 120
            f1_6 = 0.008333334 * float(scaled % 120)
            f2_4 = 0.0625 * float(SCALES[v1_5 % len(SCALES)])
            f2_n = 0.0625 * float(SCALES[(v1_5 + 1) % len(SCALES)])
            f0_5 = ((f2_n - f2_4) * f1_6 + f2_4) * f0_4
            arr[slot] = (dirx * (r * f0_5), dirz * (r * f0_5))
            # ---- do_wind_math (un pas de ressort par tick) ----
            wv = arr[(wtime + wind_idx) & 63]
            ax = wv[0] - CX * vel[0] - CY * pos[0]
            az = wv[1] - CX * vel[1] - CY * pos[1]
            vel[0] += ax * CZ; vel[1] += az * CZ
            p0 = pos[0] + vel[0] * CZ
            p1 = pos[1] + vel[1] * CZ
            p0 = min(p0, 1.0); p1 = min(p1, 1.0)
            p0 = max(p0, CW);  p1 = max(p1, CW)
            raw = math.hypot(p0, p1)
            if p0 >= 0.999999 or p0 <= CW + 1e-6 or p1 >= 0.999999 or p1 <= CW + 1e-6:
                sat_hits += 1
            samples += 1
            raw_hist.append(raw)
            pos[0] = p0 * stiffness; pos[1] = p1 * stiffness
        shear_hist.append((pos[0], pos[1]))
    return shear_hist, sat_hits / max(1, samples), raw_hist

def stats(hist, raw, sat, label, fps):
    n = len(hist)
    rms = math.sqrt(sum(x*x + z*z for x, z in hist) / n)
    d = [math.hypot(hist[i][0]-hist[i-1][0], hist[i][1]-hist[i-1][1]) for i in range(1, n)]
    drms = math.sqrt(sum(v*v for v in d) / len(d))
    # COHERENCE : deplacement NET sur 1 s / somme des deplacements par image sur la meme seconde.
    # bruit pur -> 1/sqrt(N) ; mouvement coherent -> 1.
    w = max(2, int(round(fps)))
    coh = []
    for i in range(w, n):
        net = math.hypot(hist[i][0]-hist[i-w][0], hist[i][1]-hist[i-w][1])
        tot = sum(d[j-1] for j in range(i-w+1, i+1))
        if tot > 1e-12:
            coh.append(net / tot)
    cohm = sum(coh)/len(coh) if coh else float('nan')
    rawrms = math.sqrt(sum(v*v for v in raw)/len(raw))
    print(f"{label:34s} fps={fps:5.1f} bend_rms={rms:.6f} raw|vf17|_rms={rawrms:.4f} "
          f"sat_frac={sat:.4f} motion/img={drms:.6f} coherence_1s={cohm:.4f} 1/sqrt(N)={1/math.sqrt(w):.4f}")

if __name__ == '__main__':
    SEC = 120
    print("MODELE HORS LIGNE (predictions, PAS des mesures) — palm stiffness=0.1, wind_idx=7\n")
    for fps, ratio in ((60.0, 1.0), (30.0, 2.0), (20.0, 3.0), (15.0, 4.0), (10.0, 4.0)):
        h, s, raw = run(ratio, int(SEC*fps))
        stats(h, raw, s, f"AUJOURD'HUI (ratio={ratio})", fps)
    print()
    for fps, ratio in ((60.0, 1.0), (30.0, 2.0), (20.0, 3.0), (15.0, 4.0), (10.0, 6.0)):
        h, s, raw = run(ratio, int(SEC*fps), native60=True)
        stats(h, raw, s, f"NATIF 60 Hz (ticks={max(1,int(round(ratio)))})", fps)
