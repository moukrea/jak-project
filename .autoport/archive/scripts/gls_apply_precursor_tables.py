#!/usr/bin/env python3
"""Gloading-screen — reporter les tables de glyphes precurseurs MESUREES dans le moteur.

Ecrit pour la meme raison que .autoport/gls_apply_silhouette_constants.py : une transcription a la
main de 26 x 8 nombres est un endroit ou perdre une valeur sans que rien ne le signale, et le
dossier a deja paye ce prix (« audit par SITE » : une liste ecrite a la main rend ZERO des qu'on
convertit ce qu'elle nomme).

Source de verite : recharged_assets/font/precursor/precursor.json, produit par
.autoport/mk_precursor_atlas.py. Ce script ne calcule RIEN : il recopie.

Il pose aussi `LS_PRECURSOR_EM`, qui doit valoir `size_px` du json — c'est l'em dans lequel les
metriques sont exprimees, et un desaccord entre les deux ferait sortir la ligne de glyphes de la
largeur du texte sans qu'aucune gate ne le voie.
"""
import json
import re
import sys

JSON = "recharged_assets/font/precursor/precursor.json"
SRC = "goal_src/jak1/pc/loading-screen-pc.gc"
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

d = json.load(open(JSON, encoding="utf-8"))
g = {x["char"]: x for x in d["glyphs"]}
if sorted(g) != sorted(LETTERS):
    sys.exit("ERREUR: le json ne porte pas les 26 lettres")

uv = ["(define *ls-precursor-uv*", "  (new 'static 'inline-array vector 26"]
me = ["(define *ls-precursor-metrics*", "  (new 'static 'inline-array vector 26"]
for c in LETTERS:
    x = g[c]
    uv.append("       (new 'static 'vector :x %.6f :y %.6f :z %.6f :w %.6f) ;; %s"
              % (x["u0"], x["v0"], x["u1"], x["v1"], c))
    me.append("       (new 'static 'vector :x %.1f :y %.1f :z %.2f :w %.1f) ;; %s"
              % (x["w"], x["h"], x["adv"], x["by"], c))
uv.append("       ))")
me.append("       ))")

s = open(SRC, encoding="utf-8").read()

pat_uv = re.compile(r"\(define \*ls-precursor-uv\*\n.*?\n       \)\)", re.S)
pat_me = re.compile(r"\(define \*ls-precursor-metrics\*\n.*?\n       \)\)", re.S)
for pat, block, name in ((pat_uv, uv, "*ls-precursor-uv*"), (pat_me, me, "*ls-precursor-metrics*")):
    if not pat.search(s):
        sys.exit("ERREUR: table %s introuvable dans %s" % (name, SRC))
    s = pat.sub(lambda _m, b="\n".join(block): b, s, count=1)

em = float(d["size_px"])
pat_em = re.compile(r"\(defconstant LS_PRECURSOR_EM [0-9.]+\)")
if not pat_em.search(s):
    sys.exit("ERREUR: LS_PRECURSOR_EM introuvable")
s = pat_em.sub("(defconstant LS_PRECURSOR_EM %.1f)" % em, s, count=1)

open(SRC, "w", encoding="utf-8").write(s)
print("POSE 26 glyphes  em=%.1f  atlas=%dx%d  traceur=%s"
      % (em, d["atlas"][0], d["atlas"][1], d.get("tracer", "?")))
print("largeurs min=%d max=%d   hauteurs min=%d max=%d"
      % (min(x["w"] for x in g.values()), max(x["w"] for x in g.values()),
         min(x["h"] for x in g.values()), max(x["h"] for x in g.values())))
