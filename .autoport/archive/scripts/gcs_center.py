#!/usr/bin/env python3
"""Gcutscene-skip-polish — LES MARGES DU TEXTE DANS LA CARTOUCHE, calculees sur les ANCRES QUE LE
JEU A PUBLIEES LUI-MEME pendant la course, jamais sur une intention.

Owner 2026-08-31 : « le texte et le bouton sont même pas centrés dans la cartouche ».

CE QU'ON MESURE, ET DANS QUELLE METRIQUE — les deux axes ne se mesurent pas pareil, et la raison
est dans la police, pas dans un choix de confort :
  - HORIZONTAL : la BOITE D'AVANCE. C'est la boite que le moteur de texte pose, et c'est elle que
    le drapeau `middle` centre (font.gc:1026-1037). Le blanc a droite du dernier glyphe est le
    chasse propre de ce glyphe, pas un decentrage.
  - VERTICAL : la BANDE D'ENCRE, et surtout PAS la cellule. `draw-string` place le HAUT DE LA
    CELLULE a l'ordonnee donnee (font.gc:1153) ; la cellule fait 16 unites de police dont ~3,5 de
    vide en bas, la ligne de base etant cuite dans l'atlas. Centrer la cellule laisse donc le texte
    visiblement trop haut -- c'est LE defaut que l'owner voit, et il valait 8 unites de toile.
    La bande de reference est celle du fond de bouton `<`, premier glyphe des 23 chaines
    localisees : 0,01 .. 12,46 unites de police, relevees sur l'atlas livre
    custom_assets/jak1/recharged_textures/gamefontnew/ascii.24lo.png.

CONTROLE : le meme calcul est applique a la geometrie du CYCLE 1 (texte pose a `bx+11, by+2`,
cartouche `h=22`, largeur `int(w)+22`, sans drapeau `middle`). Il DOIT montrer un ecart haut/bas de
plusieurs unites, sinon l'instrument ne mesure rien.

CONTRE-VERIFICATION INDEPENDANTE : la ligne `CUTCENTER-QUADS` que le JEU publie est un balayage du
tampon DMA -- la boite des quads REELLEMENT emis par `draw-string`. Sa marge HAUTE doit valoir la
marge haute d'encre a 0,01 pres (l'encre du bouton commence a 0,01 sous le haut de la cellule).
Si les deux divergent, c'est le modele d'ancre ci-dessous qui est faux.
"""
import re, sys

LOG = sys.argv[1] if len(sys.argv) > 1 else ".autoport/reports/Gcutscene-skip-all/x86-run.log"
INK_TOP, INK_BOT = 0.01, 12.46          # bande d'encre du fond de bouton, unites de police
SCALE = 0.8                             # CS_TEXT_SCALE
PAD_X_OLD, BOXH_OLD, DY_OLD = 11, 22, 2  # geometrie du cycle 1

def kv(line):
    return dict(re.findall(r"(\w+)=([^\s]+)", line))

box = txt = quads = None
for raw in open(LOG, encoding="utf-8", errors="replace"):
    if raw.startswith("CUTHINT-BOX ") and box is None:      box = kv(raw)
    elif raw.startswith("CUTHINT-TEXTPOS ") and txt is None: txt = kv(raw)
    elif raw.startswith("CUTCENTER-QUADS ") and quads is None: quads = kv(raw)
if not box or not txt:
    sys.exit("pas de CUTHINT-BOX / CUTHINT-TEXTPOS dans " + LOG)

bx, by = int(box["x"]), int(box["y"])
bw, bh = int(box["w"]), int(box["h"])
lang = int(box["langue"])
tx, ty = int(txt["tx"]), int(txt["ty"])
w = int(txt["largeur_texte_millu"]) / 1000.0        # avance RENDUE, unites de toile
s = int(txt["echelle_millu"]) / 1000.0              # CS_TEXT_SCALE * relative-x-scale

# --- geometrie LIVREE : ancres relevees dans la trace ---
g = (tx - w / 2.0) - bx
d = (bx + bw) - (tx + w / 2.0)
h = (ty + INK_TOP * SCALE) - by
b = (by + bh) - (ty + INK_BOT * SCALE)
print(f"CUTCENTER marge_g={g:.3f} marge_d={d:.3f} marge_h={h:.3f} marge_b={b:.3f} "
      f"metrique=avance-h+encre-v langue={lang} rxs={s/SCALE:.4f}")

# --- geometrie du CYCLE 1, meme chaine, meme avance, meme instrument ---
bw0 = int(w) + 2 * PAD_X_OLD
bx0 = 512 - 16 - bw0
by0 = 224 - 12 - BOXH_OLD
ty0 = by0 + DY_OLD
g0 = PAD_X_OLD
d0 = bw0 - PAD_X_OLD - w
h0 = (ty0 + INK_TOP * SCALE) - by0
b0 = (by0 + BOXH_OLD) - (ty0 + INK_BOT * SCALE)
print(f"CUTCENTER-AVANT marge_g={g0:.3f} marge_d={d0:.3f} marge_h={h0:.3f} marge_b={b0:.3f} "
      f"metrique=avance-h+encre-v langue={lang} boite={bw0}x{BOXH_OLD}")

print(f"CUTCENTER-ECART livree_h={abs(g-d):.3f} livree_v={abs(h-b):.3f} "
      f"avant_h={abs(g0-d0):.3f} avant_v={abs(h0-b0):.3f} unite=toile")

if quads:
    qh = float(quads["marge_h"])
    print(f"CUTCENTER-ACCORD quads_marge_h={qh:.3f} encre_marge_h={h:.3f} "
          f"ecart={abs(qh-h):.3f} attendu=~{INK_TOP*SCALE:.3f}")
    print("  (la boite des QUADS inclut le remplissage transparent de la cellule : sa marge DROITE "
          "est structurellement sous-estimee, cf. cs-scan-quads!. Seule la marge HAUTE est "
          "comparable, et c'est elle qui verifie l'ancre.)")
    print(f"CUTCENTER-QUADS-RELU {quads}")
