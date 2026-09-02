#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gcs_icon.py -- CENTRAGE VERTICAL DE L'ICONE DU BOUTON dans la cartouche de saut.

    python3 .autoport/gcs_icon.py [chemin/vers/x86-run.log]

Phase Gcutscene-skip-polish-2, retour owner du 2026-09-02 : « l'icone de bouton n'est pas centré
verticalement dans la cartouche ça fait tâche ». LECTURE SEULE : ce script n'ecrit rien.

===========================================================================================
CE QUI EST MESURE, ET POURQUOI CE N'EST PAS UN MIROIR
===========================================================================================

Le centrage publie jusqu'ici (`CUTCENTER`) portait sur la CHAINE entiere, par une bande d'encre de
reference (`CS_INK_TOP`/`CS_INK_BOT`) posee en constante dans cutscene-skip-draw.gc. L'icone du
bouton est un element DISTINCT : `<PAD_CIRCLE>` se developpe en QUATRE glyphes superposes
(`<` fond, `@` cercle, `>` reflet haut-gauche, `[` reflet bas-droit ; font_db_jak1.cpp:439), a la
meme plume, et rien ne garantissait que LEUR encre tombe au milieu de la cartouche.

La mesure part de ce que le jeu a REELLEMENT ecrit dans le tampon DMA, releve par `cs-scan-quads!`
(cutscene-skip-draw.gc) sur les quatre premiers paquets de la passe de texte :
  - `CUTICON-QUAD i= haut= bas=` : les deux marges de la CELLULE du glyphe a la cartouche, en
    unites de toile, lues sur les sommets XYZF2 haut-gauche et bas-droit du paquet ;
  - `CUTICON-ST i= s0 t0 s1 t1`  : la FENETRE DE TEXELS que ce quad echantillonne, lue sur le
    registre ST des memes sommets. C'est ce que le GPU lira.
Ici, on DECOUPE l'atlas livre sur cette fenetre-la et on cherche l'encre (alpha > seuil) dedans.
La position de l'encre dans la fenetre, rapportee a la hauteur de la cellule dessinee, donne les
marges HAUT et BAS de l'encre de chaque glyphe a la cartouche ; l'icone est l'UNION des quatre.

Rien ici ne relit `CS_INK_TOP`, `CS_INK_BOT`, `CS_PAD_Y` ni `*font24-table*` : la fenetre vient du
tampon, l'encre vient des pixels. Si la table etait fausse (mauvaise cellule), si l'ancre etait
fausse (mauvaise ordonnee) ou si l'atlas avait change (bouton deplace), l'egalite des deux marges se
casserait. Les deux controles ci-dessous montrent qu'elle SAIT se casser.

===========================================================================================
LES CONTROLES
===========================================================================================

  CUTICON-STOCK   la MEME fenetre, decoupee sur l'atlas D'ORIGINE (extracted_textures/.../ascii.24lo,
                  256x512, les pixels Naughty Dog). C'est l'atlas que l'owner regardait quand il a ecrit
                  sa phrase : la phase Gfont-regression a etabli que son appareil etait retombe sur cet
                  atlas-la (« des glyphs chinois de la font par défaut »). Le fond du bouton y occupe
                  0,5 .. 15,5 des 16 unites de la cellule, la ou l'atlas Urbanist le ramene a 0,01 ..
                  12,46 (les cellules conservees sont remises a la ligne de base du latin par
                  gen_game_atlas.py:346-363). Sous cet atlas l'icone est BASSE dans la cartouche, et
                  la ligne doit le dire.
  CUTICON-CELLULE les marges de la CELLULE (pas de l'encre). C'est ce qu'une mesure naive aurait
                  publie, et elle est asymetrique par construction (la cellule a du vide en bas) :
                  publiee pour qu'on voie de quoi la mesure d'encre se distingue.
  CUTICON-ATLAS   l'atlas que le moteur a LIE pendant la course (`FONTTEX bind`, DirectRenderer.cpp:449)
                  et l'empreinte du fichier decoupe : les deux doivent designer le meme objet, sinon
                  on mesure un fichier que l'ecran n'a pas montre.
"""
import hashlib
import os
import re
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    ROOT, ".autoport", "reports", "Gcutscene-skip-polish-2", "x86-run.log")
ATLAS_LIVRE = os.path.join(ROOT, "custom_assets", "jak1", "recharged_textures", "gamefontnew", "ascii.24lo.png")
ATLAS_STOCK = os.path.join(ROOT, "extracted_textures", "jak1", "gamefontnew", "ascii.24lo.png")
SEUIL_ALPHA = 16          # meme seuil que gcs_ink.py (CUTINK-VERIF seuil_alpha=16)
CW_TEX, CH_TEX = 24.0, 32.0   # cellule du grand atlas, en texels de la texture 256x512 (font-h.gc:291-300)
NOMS = {0x3C: "<", 0x40: "@", 0x3E: ">", 0x5B: "["}
ATTENDU = [0x3C, 0x40, 0x3E, 0x5B]   # ordre d'emission de <PAD_CIRCLE>, font_db_jak1.cpp:439


def kv(line):
    return dict(re.findall(r"(\S+?)=(\S+)", line))


def die(msg):
    print("CUTICON-ERREUR " + msg)
    sys.exit(1)


def ink_rows(img, s0, t0, s1, t1):
    """Lignes d'encre (premiere, derniere+1) dans la fenetre [t0,t1) de l'atlas `img`, en
    fraction de la hauteur de la fenetre. None si aucune encre. Retourne aussi la boite en texels."""
    W, H = img.size
    x0, x1 = int(round(s0 * W)), int(round(s1 * W))
    y0, y1 = int(round(t0 * H)), int(round(t1 * H))
    a = img.split()[3].crop((x0, y0, x1, y1))
    bb = a.point(lambda v: 255 if v > SEUIL_ALPHA else 0).getbbox()
    if not bb:
        return None, (x0, y0, x1, y1), None
    hc = float(y1 - y0)
    return (bb[1] / hc, bb[3] / hc), (x0, y0, x1, y1), bb


def main():
    if not os.path.exists(LOG):
        die("journal absent : %s" % LOG)
    txt = open(LOG, "rb").read().decode("utf-8", "replace")
    boxes = re.findall(r"^CUTHINT-BOX .*$", txt, re.M)
    quads = re.findall(r"^CUTICON-QUAD .*$", txt, re.M)
    sts = re.findall(r"^CUTICON-ST .*$", txt, re.M)
    binds = re.findall(r"^FONTTEX bind .*$", txt, re.M)
    if not boxes:
        die("aucune ligne CUTHINT-BOX dans le journal")
    if len(quads) < 4 or len(sts) < 4:
        die("il faut 4 lignes CUTICON-QUAD et 4 CUTICON-ST (trouve %d / %d) : cs-scan-quads! n'a pas tourne" % (len(quads), len(sts)))
    # `cs-scan-quads!` ne publie qu'UNE fois par lancement (*cutscene-quads-published*), puis le
    # harnais le reamorce avant la cinematique de Geyser Rock : on retient la DERNIERE serie, celle
    # d'une vraie cinematique, et la boite qui la precede immediatement dans le journal.
    q = [kv(l) for l in quads[-4:]]
    s = [kv(l) for l in sts[-4:]]
    ipos = txt.rfind(quads[-4])
    box = kv([b for b in boxes if txt.find(b) < ipos][-1] if any(txt.find(b) < ipos for b in boxes) else boxes[-1])
    by, bh, langue = int(box["y"]), int(box["h"]), int(box.get("langue", -1))

    # --- l'atlas LIE pendant la course, contre le fichier qu'on va decouper -------------------
    b24 = [kv(l) for l in binds if "name=gamefontnew/ascii.24lo" in l]
    for path in (ATLAS_LIVRE, ATLAS_STOCK):
        if not os.path.exists(path):
            die("atlas absent : %s" % path)
    livre = Image.open(ATLAS_LIVRE).convert("RGBA")
    stock = Image.open(ATLAS_STOCK).convert("RGBA")
    md5 = hashlib.md5(open(ATLAS_LIVRE, "rb").read()).hexdigest()[:12]
    if b24:
        last = b24[-1]
        accord = (last.get("source") == "bundled-police"
                  and int(last.get("w", 0)) == livre.size[0] and int(last.get("h", 0)) == livre.size[1])
        print("CUTICON-ATLAS bind_source=%s bind_w=%s bind_h=%s binds=%d fichier=%s taille=%dx%d md5=%s accord=%d"
              % (last.get("source"), last.get("w"), last.get("h"), len(b24),
                 os.path.relpath(ATLAS_LIVRE, ROOT), livre.size[0], livre.size[1], md5, 1 if accord else 0))
    else:
        print("CUTICON-ATLAS bind_source=absent binds=0 fichier=%s taille=%dx%d md5=%s accord=0 note=aucune-ligne-FONTTEX-bind-dans-le-journal"
              % (os.path.relpath(ATLAS_LIVRE, ROOT), livre.size[0], livre.size[1], md5))

    # --- glyphe par glyphe -------------------------------------------------------------------
    res = {"livre": [], "stock": []}
    cell_top_min, cell_bot_min = 1e9, 1e9
    for i in range(4):
        haut, bas = float(q[i]["haut"]), float(q[i]["bas"])
        s0, t0 = int(s[i]["s0_micro"]) / 1e6, int(s[i]["t0_micro"]) / 1e6
        s1, t1 = int(s[i]["s1_micro"]) / 1e6, int(s[i]["t1_micro"]) / 1e6
        # la cellule designee par la fenetre : colonne = s0 / (24/256), rangee = t0 / (32/512)
        col, row = int(round(s0 * 256.0 / CW_TEX)), int(round(t0 * 512.0 / CH_TEX))
        octet = row * 10 + col + 16
        nom = NOMS.get(octet, "?")
        cell_h = bh - haut - bas
        cell_top_min, cell_bot_min = min(cell_top_min, haut), min(cell_bot_min, bas)
        for etiq, img in (("livre", livre), ("stock", stock)):
            fr, win, bb = ink_rows(img, s0, t0, s1, t1)
            if fr is None:
                print("CUTICON-GLYPHE atlas=%s i=%d octet=0x%02x nom=%s encre=aucune fenetre=%s" % (etiq, i, octet, nom, win))
                continue
            mh = haut + fr[0] * cell_h
            mb = bas + (1.0 - fr[1]) * cell_h
            res[etiq].append((mh, mb))
            print("CUTICON-GLYPHE atlas=%s i=%d octet=0x%02x nom=%s cellule_haut=%.3f cellule_bas=%.3f cellule_h=%.3f "
                  "encre_frac=%.4f..%.4f encre_texels=%d..%d/%d marge_h=%.3f marge_b=%.3f"
                  % (etiq, i, octet, nom, haut, bas, cell_h, fr[0], fr[1], bb[1], bb[3], win[3] - win[1], mh, mb))
        if octet != ATTENDU[i]:
            print("CUTICON-ORDRE i=%d attendu=0x%02x lu=0x%02x accord=0" % (i, ATTENDU[i], octet))
    if len(res["livre"]) < 4:
        die("encre manquante sur l'atlas livre pour au moins un glyphe")

    def union(lst):
        return min(m[0] for m in lst), min(m[1] for m in lst)

    mh, mb = union(res["livre"])
    print("CUTICON marge_h=%.3f marge_b=%.3f ecart=%.3f glyphes=%d unite=toile langue=%d source=fenetre-ST-du-tampon+encre-atlas-livre boite_y=%d boite_h=%d"
          % (mh, mb, abs(mh - mb), len(res["livre"]), langue, by, bh))
    if res["stock"]:
        sh, sb = union(res["stock"])
        print("CUTICON-STOCK marge_h=%.3f marge_b=%.3f ecart=%.3f glyphes=%d unite=toile source=meme-fenetre-sur-atlas-origine-256x512 (ce que l'owner voyait, police cassee)"
              % (sh, sb, abs(sh - sb), len(res["stock"])))
    print("CUTICON-CELLULE marge_h=%.3f marge_b=%.3f ecart=%.3f source=cellule-du-quad-sans-encre (la mesure naive)"
          % (cell_top_min, cell_bot_min, abs(cell_top_min - cell_bot_min)))
    # conversion en pixels de sortie, sur la sortie de la course (CUTSMOOTH-SORTIE) : une unite de
    # toile verticale vaut rys.oh/224 pixels.
    sortie = re.findall(r"^CUTSMOOTH-SORTIE .*$", txt, re.M)
    if sortie:
        sk = kv(sortie[-1])
        oh = float(sk.get("scissor_h", 0) if sk.get("letterbox") == "#t" else sk.get("fb_h", 0))
        if oh > 0:
            pxu = oh / 224.0
            print("CUTICON-PX marge_h_px=%.2f marge_b_px=%.2f ecart_px=%.2f out_h=%d ; stock ecart_px=%.2f ; a 1080p ecart_px=%.2f"
                  % (mh * pxu, mb * pxu, abs(mh - mb) * pxu, int(oh),
                     (abs(sh - sb) * pxu) if res["stock"] else -1.0,
                     (abs(sh - sb) * 1080.0 / 224.0) if res["stock"] else -1.0))


def statique():
    """`--statique` : la MEME grandeur SANS course, depuis l'atlas livre et les constantes du
    dessin (CS_INK_TOP/BOT, CS_PAD_Y, CS_TEXT_SCALE lues dans cutscene-skip-draw.gc). C'est le
    controle de derive : l'atlas est GENERE (gen_game_atlas.py) et les constantes sont posees a la
    main ; si l'un des deux bouge sans l'autre, l'icone quitte le milieu et cette ligne le dit en
    trois secondes, avant toute course. Elle ne remplace pas la mesure sur le tampon (elle relit
    les constantes que celle-ci ignore), elle la precede."""
    gc = open(os.path.join(ROOT, "goal_src", "jak1", "pc", "cutscene-skip-draw.gc"), encoding="utf-8").read()
    def const(n):
        m = re.search(r"\(defconstant %s ([0-9.]+)\)" % re.escape(n), gc)
        if not m:
            die("constante %s introuvable" % n)
        return float(m.group(1))
    top, bot, pad, sc = const("CS_INK_TOP"), const("CS_INK_BOT"), const("CS_PAD_Y"), const("CS_TEXT_SCALE")
    rys = 1.0
    bh = int(0.5 + (bot - top) * sc * rys + 2.0 * pad)                   # cs-box-h
    cell_top = int(0.5 + (bh * 0.5 - 0.5 * (top + bot) * sc * rys))     # cs-text-y - by
    cell_h = 16.0 * sc * rys
    # le coin de cellule vient de `*font24-table*` (font.gc:296, entree `octet - 16`), pas d'une
    # grille supposee : la table porte un retrait d'environ un texel (0,2519 la ou 4 x 32/512 =
    # 0,2500), et c'est ce retrait que le registre ST du tampon montre dans la mesure en course.
    fgc = open(os.path.join(ROOT, "goal_src", "jak1", "engine", "gfx", "font.gc"), encoding="utf-8").read()
    blk = fgc[fgc.find("(define *font24-table*"):]
    table = re.findall(r":x ([0-9.]+) :y ([0-9.]+) :z [0-9.]+ :w [0-9.]+", blk)[:289]
    if len(table) != 289:
        die("*font24-table* : %d entrees lues, 289 attendues" % len(table))
    img = Image.open(ATLAS_LIVRE).convert("RGBA")
    out = []
    for octet in ATTENDU:
        s0, t0 = float(table[octet - 16][0]), float(table[octet - 16][1])
        fr, win, bb = ink_rows(img, s0, t0, s0 + 0.08985, t0 + 0.06153846)   # size-st1.x / size-st2.y
        if fr is None:
            die("encre absente pour 0x%02x" % octet)
        out.append((cell_top + fr[0] * cell_h, (bh - cell_top - cell_h) + (1.0 - fr[1]) * cell_h))
    mh, mb = min(o[0] for o in out), min(o[1] for o in out)
    print("CUTICON-STATIQUE marge_h=%.3f marge_b=%.3f ecart=%.3f boite_h=%d cellule_haut=%d cellule_h=%.2f "
          "constantes=ink_top:%g,ink_bot:%g,pad_y:%g,scale:%g atlas_md5=%s source=atlas-livre+constantes-du-dessin-sans-course"
          % (mh, mb, abs(mh - mb), bh, cell_top, cell_h, top, bot, pad, sc,
             hashlib.md5(open(ATLAS_LIVRE, "rb").read()).hexdigest()[:12]))
    return 0 if abs(mh - mb) <= 1.0 else 1


if __name__ == "__main__":
    if "--statique" in sys.argv:
        sys.exit(statique())
    main()
