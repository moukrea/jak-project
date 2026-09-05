#!/usr/bin/env python3
"""refset_compare.py — comparaison HORS LIGNE de deux jeux d'images de reference.

CE QUE CE SCRIPT N'EST PAS. Il ne produit AUCUN champ de preuve. La grandeur qui ferme la
porte (`refset_replay_maxdiff`) est publiee par le MOTEUR, pendant la course, et moissonnee par
.autoport/lib/proof_run.sh. Ce script sert a LOCALISER un ecart quand le moteur en signale un :
il dit quelle image, quel canal, combien de pixels et ou.

Usage :
    refset_compare.py <dir_reference> <dir_candidat> [--json]

Chaque dossier contient des PNG de meme nom (origine/hHH.png, recharged/hHH.png). Sortie : une
ligne par image, `maxdiff` (plus grand ecart absolu par canal, 0..255), `diffpx` (nombre de
pixels differents), la boite englobante des pixels differents, puis une ligne de synthese
`REFSET-COMPARE maxdiff=<n> diffpx=<n> images=<n> manquantes=<n>`.

Code de sortie : 0 si maxdiff == 0 et aucune image manquante, 1 sinon.
"""
import argparse
import json
import os
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover
    print("refset_compare: numpy + Pillow requis (%s)" % exc, file=sys.stderr)
    sys.exit(2)


def load(path):
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), dtype=np.int16)


def walk(root):
    out = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith(".png"):
                full = os.path.join(dirpath, fn)
                out[os.path.relpath(full, root)] = full
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference")
    ap.add_argument("candidate")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    refs = walk(args.reference)
    cands = walk(args.candidate)

    rows = []
    worst = 0
    total_diff = 0
    missing = 0
    for name in sorted(refs):
        if name not in cands:
            missing += 1
            rows.append({"image": name, "status": "absente-du-candidat"})
            print("%-28s MANQUANTE dans %s" % (name, args.candidate))
            continue
        a = load(refs[name])
        b = load(cands[name])
        if a.shape != b.shape:
            missing += 1
            rows.append({"image": name, "status": "taille", "ref": a.shape, "cand": b.shape})
            print("%-28s TAILLE %s != %s" % (name, a.shape, b.shape))
            continue
        d = np.abs(a - b).max(axis=2)
        md = int(d.max())
        npx = int((d > 0).sum())
        box = None
        if npx:
            ys, xs = np.nonzero(d)
            box = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
        worst = max(worst, md)
        total_diff += npx
        rows.append({"image": name, "maxdiff": md, "diffpx": npx, "bbox": box})
        print("%-28s maxdiff=%-4d diffpx=%-8d bbox=%s" % (name, md, npx, box))

    print("REFSET-COMPARE maxdiff=%d diffpx=%d images=%d manquantes=%d"
          % (worst, total_diff, len(refs), missing))
    if args.json:
        print(json.dumps(rows, indent=2))
    return 0 if (worst == 0 and missing == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
