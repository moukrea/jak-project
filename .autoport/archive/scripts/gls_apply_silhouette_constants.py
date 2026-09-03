#!/usr/bin/env python3
"""Gloading-screen — reporter les constantes MESUREES de la planche dans le moteur.

Ecrit parce qu'une transcription a la main est un endroit ou perdre un facteur : le cycle
precedent a livre une boucle de 32 frames pour une periode mesuree a 20 sans que rien ne le
signale. Ici les quatre constantes sont LUES dans le rapport du montage
(.autoport/reports/Gloading-screen/silhouette.txt) et posees telles quelles.

CONVERSION D'UNITE, ET C'EST LA SEULE : la periode est mesuree en FRAMES DE LOGIQUE (60 Hz) et
`LS_SIL_PERIOD` s'exprime dans l'unite de `loading-screen-clock`, soit le 1/300 s. Facteur 5,
applique ICI et nulle part ailleurs, et la valeur en frames est republiee en commentaire a cote.
"""
import re
import sys

REP = ".autoport/reports/Gloading-screen/silhouette.txt"
SRC = "goal_src/jak1/pc/loading-screen-pc.gc"

rep = open(REP, encoding="utf-8").read()

m = re.search(r"PLANCHE=\S+ (\d+)x(\d+)\s+images=(\d+)[^(]*\((\d+) x (\d+) cellules", rep)
if not m:
    sys.exit("ERREUR: ligne PLANCHE introuvable dans " + REP)
frames, cols, rows = int(m.group(3)), int(m.group(4)), int(m.group(5))

m = re.search(r"LS_SIL_PERIOD_A_POSER=(\d+)", rep)
if not m:
    sys.exit("ERREUR: LS_SIL_PERIOD_A_POSER introuvable")
per_frames = int(m.group(1))
per_ticks = per_frames * 5

m = re.search(r"LS_SIL_H_A_POSER=([0-9.]+)", rep)
if not m:
    sys.exit("ERREUR: LS_SIL_H_A_POSER introuvable")
h = float(m.group(1))

s = open(SRC, encoding="utf-8").read()
subs = [
    (r"\(defconstant LS_SIL_COLS \d+\)", "(defconstant LS_SIL_COLS %d)" % cols),
    (r"\(defconstant LS_SIL_ROWS \d+\)", "(defconstant LS_SIL_ROWS %d)" % rows),
    (r"\(defconstant LS_SIL_FRAMES \d+\)", "(defconstant LS_SIL_FRAMES %d)" % frames),
    (r"\(defconstant LS_SIL_PERIOD [^)]*\)[^\n]*",
     "(defconstant LS_SIL_PERIOD %d)  ;; = %d frames de logique x 5 (unite de "
     "`loading-screen-clock` : 1/300 s), soit %.4f s. MESUREE sur l'animation elle-meme, pas "
     "choisie." % (per_ticks, per_frames, per_frames / 60.0)),
    (r"\(defconstant LS_SIL_H [0-9.]+\)", "(defconstant LS_SIL_H %.6f)" % h),
]
for pat, rep_s in subs:
    if not re.search(pat, s):
        sys.exit("ERREUR: motif introuvable dans %s : %s" % (SRC, pat))
    s = re.sub(pat, rep_s, s, count=1)
open(SRC, "w", encoding="utf-8").write(s)
print("POSE cols=%d rows=%d images=%d periode=%d frames (%d ticks, %.4f s) hauteur=%.6f"
      % (cols, rows, frames, per_frames, per_ticks, per_frames / 60.0, h))
