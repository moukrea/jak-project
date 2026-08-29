#!/usr/bin/env python3
"""Gloading-screen — production des assets de l'ecran de chargement.

Rejouable : ecrase ses sorties a chaque execution, ne modifie aucune source.

Entrees (jamais modifiees) :
  .autoport/design/loading-screen-owner-mockup.png     (maquette owner, 1672x941 RGB)
  recharged_assets/font/precursor/precursor-atlas.png  (atlas 8 bits 512x512)
  recharged_assets/font/precursor/precursor.json       (metriques des 26 glyphes)

Sorties :
  recharged_assets/loading_jak.png                     (silhouette RGBA, blanc + alpha)
  recharged_assets/loading_precursor.png               (atlas RGBA, blanc + alpha)
  .autoport/reports/Gloading-screen/assets.txt         (mesures publiees)
  .autoport/reports/Gloading-screen/precursor-uv.txt   (table UV pour GOAL)
"""

import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCKUP = os.path.join(ROOT, ".autoport", "design", "loading-screen-owner-mockup.png")
ATLAS = os.path.join(ROOT, "recharged_assets", "font", "precursor", "precursor-atlas.png")
PRECURSOR_JSON = os.path.join(ROOT, "recharged_assets", "font", "precursor", "precursor.json")

OUT_JAK = os.path.join(ROOT, "recharged_assets", "loading_jak.png")
OUT_PRECURSOR = os.path.join(ROOT, "recharged_assets", "loading_precursor.png")
REPORT_DIR = os.path.join(ROOT, ".autoport", "reports", "Gloading-screen")
OUT_ASSETS_TXT = os.path.join(REPORT_DIR, "assets.txt")
OUT_UV_TXT = os.path.join(REPORT_DIR, "precursor-uv.txt")

# Moitie gauche de la maquette : le texte « Loading... » et la ligne de glyphes
# vivent a droite de cette colonne et ne doivent pas entrer dans le decoupage.
LEFT_HALF_X = 836
INK_THRESHOLD = 40  # luminance > 40 (sur 255) = encre

lines = []


def emit(s):
    print(s)
    lines.append(s)


def task1_silhouette():
    src = Image.open(MOCKUP)
    mock_w, mock_h = src.size
    emit("MOCKUP_SRC_MODE=%s" % src.mode)
    emit("MOCKUP_SRC_SIZE=%dx%d" % (mock_w, mock_h))

    lum = src.convert("L")
    px = lum.load()

    x0 = y0 = None
    x1 = y1 = None  # bornes INCLUSIVES pendant le balayage
    ink = 0
    for y in range(mock_h):
        for x in range(LEFT_HALF_X):
            if px[x, y] > INK_THRESHOLD:
                ink += 1
                if x0 is None or x < x0:
                    x0 = x
                if x1 is None or x > x1:
                    x1 = x
                if y0 is None or y < y0:
                    y0 = y
                if y1 is None or y > y1:
                    y1 = y

    if x0 is None:
        raise SystemExit("ERREUR: aucun pixel d'encre dans la moitie gauche")

    # convention publiee : x1/y1 EXCLUSIFS (comme PIL.crop)
    bx1 = x1 + 1
    by1 = y1 + 1
    W = bx1 - x0
    H = by1 - y0

    emit("SILHOUETTE_INK_THRESHOLD=%d" % INK_THRESHOLD)
    emit("SILHOUETTE_SEARCH_X_MAX=%d" % LEFT_HALF_X)
    emit("SILHOUETTE_INK_PIXELS=%d" % ink)
    emit("SILHOUETTE_BBOX=(%d,%d,%d,%d)  # x0,y0,x1,y1 avec x1/y1 EXCLUSIFS" % (x0, y0, bx1, by1))
    emit("SILHOUETTE_BBOX_INCLUSIVE=(%d,%d,%d,%d)" % (x0, y0, x1, y1))
    emit("SILHOUETTE_W=%d" % W)
    emit("SILHOUETTE_H=%d" % H)
    emit("SILHOUETTE_WH_RATIO=%.4f" % (W / float(H)))
    emit("SILHOUETTE_H_FRAC=%.6f" % (H / float(mock_h)))
    emit("SILHOUETTE_CX_FRAC=%.6f" % (((x0 + bx1) / 2.0) / float(mock_w)))
    emit("SILHOUETTE_CY_FRAC=%.6f" % (((y0 + by1) / 2.0) / float(mock_h)))

    alpha = lum.crop((x0, y0, bx1, by1))
    white = Image.new("L", alpha.size, 255)
    out = Image.merge("RGBA", (white, white, white, alpha))
    out.save(OUT_JAK)
    emit("SILHOUETTE_OUT=%s %dx%d %s" % (OUT_JAK, out.size[0], out.size[1], out.mode))


def task2_precursor():
    src = Image.open(ATLAS)
    emit("PRECURSOR_SRC_MODE=%s" % src.mode)
    emit("PRECURSOR_SRC_SIZE=%dx%d" % (src.size[0], src.size[1]))

    if src.mode == "RGBA":
        alpha = src.split()[3]
    elif src.mode == "LA":
        alpha = src.split()[1]
    elif src.mode == "L":
        alpha = src
    else:
        alpha = src.convert("L")

    hist = alpha.histogram()
    nonzero = sum(hist[1:])
    emit("PRECURSOR_ALPHA_NONZERO=%d" % nonzero)
    emit("PRECURSOR_ALPHA_TOTAL=%d" % (alpha.size[0] * alpha.size[1]))

    white = Image.new("L", alpha.size, 255)
    out = Image.merge("RGBA", (white, white, white, alpha))
    out.save(OUT_PRECURSOR)
    emit("PRECURSOR_OUT=%s %dx%d %s" % (OUT_PRECURSOR, out.size[0], out.size[1], out.mode))


def task4_uv_table():
    with open(PRECURSOR_JSON, "r") as f:
        d = json.load(f)
    glyphs = {g["char"]: g for g in d["glyphs"]}
    out = []
    for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        g = glyphs[c]
        out.append(
            "%s %.6f %.6f %.6f %.6f %.6f %.6f %.6f"
            % (c, g["u0"], g["v0"], g["u1"], g["v1"], g["w"], g["h"], g["adv"])
        )
    out.append("SIZE_PX %s" % d["size_px"])
    with open(OUT_UV_TXT, "w") as f:
        f.write("\n".join(out) + "\n")
    emit("PRECURSOR_UV_OUT=%s (%d glyphes)" % (OUT_UV_TXT, len(out) - 1))


def main():
    os.makedirs(REPORT_DIR, exist_ok=True)
    emit("# Gloading-screen — assets produits par .autoport/mk_loading_assets.py")
    task1_silhouette()
    emit("")
    task2_precursor()
    emit("")
    task4_uv_table()
    with open(OUT_ASSETS_TXT, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
