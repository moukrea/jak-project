#!/usr/bin/env python3
"""Fabrique les entrees de composition d'ACCENTS MINUSCULES pour jak1.

Pourquoi il en faut
-------------------
jak1 n'a AUCUN glyphe accentue precompose (sauf Ç Æ Œ ß). Une capitale accentuee est
composee a l'execution : `replace_info_jak1` remplace "É" par "E~Y~-22H~-5V'~Z", soit
« dessine E, sauvegarde la plume, recule de 22, descends de 5, dessine l'accent aigu,
restaure la plume ». Le corpus emploie 49 capitales accentuees et ZERO minuscule
accentuee (mesure : 11 994 entrees, seule `ö` apparait, 7 fois, et c'est une coquille).
Passer le jeu en casse mixte demande donc de creer les 49 entrees minuscules.

L'unite des decalages, MESUREE et non supposee
----------------------------------------------
Le decalage `~NNH` est ajoute BRUT a la plume (font.gc cfg-109 : `.itof.vf` sans
echelle). En ajustant le modele « centre de l'encre de l'accent = centre de l'encre de
la lettre » sur les 50 entrees livrees :
    - lu dans le repere de la GRANDE police : k = 1.000 (mediane), 0.816..1.119
    - lu dans le repere de la PETITE police : k = 0.411 (mediane)
Les decalages livres sont donc exprimes en PIXELS ECRAN DE LA GRANDE POLICE. Comme ils
sont appliques sans mise a l'echelle, ils sont FAUX d'un facteur ~2.4 en petite police.
C'est un defaut du jeu d'origine, il n'est pas corrige ici et il est publie tel quel
dans le rapport de phase.

Ce que ce script fait
---------------------
1. Il AJOUTE les entrees minuscules, calculees en ABSOLU sur l'atlas Urbanist genere.
2. Il RECALE les 60 entrees majuscules livrees par Naughty Dog, par DIFFERENCE MESUREE
   entre les deux geometries, jamais par un modele absolu.

Pourquoi le recalage des majuscules est devenu obligatoire
----------------------------------------------------------
L'atlas Urbanist ramene l'avance moyenne A-Z de la GRANDE police de 19,885 a 15,880
texels (x0,799 ; ligne de base 29,00 -> 23,61, hauteur de capitale 27,00 -> 21,39).
Un « E~Y~-22H~-5V'~Z » regle pour un E qui avance de 19 recule trop pour un E qui
avance de 15 : les entrees livrees sont fausses tant qu'elles ne sont pas recalees.

Pourquoi une DIFFERENCE et pas un modele absolu
-----------------------------------------------
Le modele « centre de l'encre de l'accent = centre de l'encre de la lettre », evalue
sur la geometrie LIVREE, se trompe de -6 a +7 px sur les valeurs reglees a la main par
Naughty Dog. Sa DIFFERENCE entre deux geometries annule ce biais : le reglage a la main
est CONSERVE, seul l'effet du changement de chasse est applique. Le controle chiffre est
publie dans .autoport/reports/Gfont-urbanist/accent-rebase.txt.

Gel de la reference
-------------------
Meme piege que celui deja paye par `stock-tables.json` : ce script LIT les entrees
majuscules et les REECRIT. Une seconde course lirait donc ses propres valeurs comme
reference et appliquerait le delta DEUX FOIS. La reference est figee une fois pour
toutes dans `recharged_assets/font/stock-accents.json`, et relue ensuite.
"""
import io
import json
import os
import re
import statistics
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONTDIR = os.path.dirname(os.path.abspath(__file__))
if FONTDIR not in sys.path:
    sys.path.insert(0, FONTDIR)
# Lecture des atlas LIVRES (zstd + serialisation tfrag3) et boite d'encre a l'echelle 1 :
# on IMPORTE le code du generateur d'atlas, on ne le duplique pas — une seconde copie
# divergerait en silence de celle qui a servi a fabriquer le nouvel atlas.
from gen_game_atlas import FR3, ink_box, read_stock_atlases  # noqa: E402

ATLAS = os.path.join(ROOT, "custom_assets", "jak1", "recharged_textures",
                     "gamefontnew", "ascii.24lo.png")
DB = os.path.join(ROOT, "common", "util", "font", "dbs", "font_db_jak1.cpp")
STOCK_TABLES = os.path.join(FONTDIR, "stock-tables.json")   # avances LIVREES (gelees)
STOCK_ACCENTS = os.path.join(FONTDIR, "stock-accents.json")  # entrees MAJUSCULES gelees
REPORTDIR = os.path.join(ROOT, ".autoport", "reports", "Gfont-urbanist")

DOTLESS = 0x19                     # cellule reaffectee au « i sans point »
CW, CH, SCALE = 24, 32, 2          # cellule du grand atlas, et son surechantillonnage
QUAD_H_RATIO = 0.5                 # quad 24 x 16 ecran pour une cellule 24 x 32 texels

MARK_CODE = {"ˇ": 0x10, "`": 0x11, "'": 0x12, "^": 0x13, "<TIL>": 0x14,
             "¨": 0x15, "º": 0x16, ",": 0x2C, "-": 0x2D, "/": 0x2F}

# Classement des marques. "-" est ambigu : macron AU-DESSUS dans Ū (V = -10), barre
# TRAVERSANTE dans Đ (V = -1). On tranche sur l'amplitude de V livree.
ABOVE = {"ˇ", "`", "'", "^", "<TIL>", "¨", "º"}
BELOW = {","}
THROUGH = {"/"}


def classify(mark, v_ref):
    """above / below / through. Une marque inconnue est traitee en traversante."""
    if mark == "-":
        return "above" if abs(v_ref) >= 6 else "through"
    if mark in ABOVE:
        return "above"
    if mark in BELOW:
        return "below"
    return "through"


# Une entree de composition : `{"<lettre>~Y~<H>H~<V>V<marque>[~<H2>H<marque2>]~Z", "<res>"}`
# Le groupe `raw` couvre EXACTEMENT la chaine d'echappement : la reecriture ne touche
# que lui, le reste de la ligne (espaces, commentaire) est preserve octet pour octet.
ENTRY = re.compile(
    r'\{"(?P<raw>(?P<base>[A-Za-z])~Y~(?P<H>[-+]?\d+)H~(?P<V>[-+]?\d+)V'
    r'(?P<mark><TIL>|[^~])(?:~(?P<H2>[-+]?\d+)H(?P<mark2>.))?~Z)",'
    r'\s*"(?P<res>.+?)"\}')


def cx(b):
    return (b[0] + b[2]) / 2.0


def mid(b):
    return (b[1] + b[3]) / 2.0


def ink(img, code):
    idx = code - 16
    x0, y0 = (idx % 10) * CW * SCALE, (idx // 10) * CH * SCALE
    a = img.split()[3].crop((x0, y0, x0 + CW * SCALE, y0 + CH * SCALE))
    bb = a.point(lambda v: 255 if v > 8 else 0).getbbox()
    if bb is None:
        return None
    return tuple(v / SCALE for v in bb)   # (l, t, r, b) en texels de la cellule


def ink_stock(img, code):
    """Boite d'encre de la cellule d'un octet dans l'atlas LIVRE (echelle 1)."""
    bb = ink_box(img, CW, CH, code)
    return None if bb is None else tuple(float(v) for v in bb)


def shipped_span(src):
    """(debut, fin) de la region des entrees LIVREES : le vecteur `replace_info_jak1`
    PRIVE du bloc GENERE (les minuscules, qui sont fabriquees en absolu plus bas)."""
    a = src.index("std::vector<ReplaceInfo> replace_info_jak1 = {")
    b = src.index("\n};", a)
    end_marker = "    // ==== FIN GENERE ====\n"
    if end_marker in src[a:b]:
        a = src.index(end_marker, a) + len(end_marker)
    return a, b


def freeze_stock_accents(src):
    """Gele les entrees MAJUSCULES telles qu'elles sont AUJOURD'HUI, a la premiere
    course seulement. Sans ce gel, la seconde course lirait ses propres valeurs comme
    reference et appliquerait le delta DEUX FOIS (piege deja paye par stock-tables)."""
    if os.path.exists(STOCK_ACCENTS):
        return json.load(open(STOCK_ACCENTS, encoding="utf-8"))
    lo, hi = shipped_span(src)
    ent = []
    for m in ENTRY.finditer(src[lo:hi]):
        if not m.group("base").isupper():
            continue
        ent.append({"raw": m.group("raw"), "res": m.group("res"),
                    "base": m.group("base"), "mark": m.group("mark"),
                    "H": int(m.group("H")), "V": int(m.group("V")),
                    "H2": None if m.group("H2") is None else int(m.group("H2")),
                    "mark2": m.group("mark2")})
    with io.open(STOCK_ACCENTS, "w", encoding="utf-8") as f:
        json.dump(ent, f, ensure_ascii=False, indent=1)
    return ent


def rebase_uppercase(src, img_new, adv_new):
    """Recale les decalages des entrees MAJUSCULES sur la nouvelle geometrie.

    Le delta est une DIFFERENCE entre deux geometries mesurees (livree / nouvelle) :
    le reglage a la main de Naughty Dog est conserve, seul l'effet du changement de
    chasse et de hauteur d'oeil est applique. Rend (src reecrit, lignes de rapport)."""
    stock_img = read_stock_atlases()["ascii.24lo"]
    t24 = json.load(open(STOCK_TABLES, encoding="utf-8"))["font24"]
    adv_stock = {c: t24[c - 16][3] for c in range(0x10, 0x80)}
    ent = freeze_stock_accents(src)

    lo, hi = shipped_span(src)
    region = src[lo:hi]
    parts, pos, i = [], 0, 0
    rows, control, skipped = [], [], []
    for m in ENTRY.finditer(region):
        if not m.group("base").isupper():
            continue
        if i >= len(ent):
            raise SystemExit("stock-accents.json : %d entrees gelees, le fichier en "
                             "porte davantage — reference perimee" % len(ent))
        e = ent[i]
        i += 1
        if (m.group("base"), m.group("mark"), m.group("res")) != \
                (e["base"], e["mark"], e["res"]):
            raise SystemExit("stock-accents.json desynchronise a l'entree %d : "
                             "fichier %r / gel %r" % (i, m.group("raw"), e["raw"]))
        L, M = e["base"], e["mark"]
        if M not in MARK_CODE:
            skipped.append((e["res"], "marque inconnue %r" % M))
            continue
        cL, cM = ord(L), MARK_CODE[M]
        bLn, bMn = ink(img_new, cL), ink(img_new, cM)
        bLs, bMs = ink_stock(stock_img, cL), ink_stock(stock_img, cM)
        manque = [n for n, b in (("lettre livree", bLs), ("marque livree", bMs),
                                 ("lettre nouvelle", bLn), ("marque nouvelle", bMn))
                  if b is None]
        if manque:
            skipped.append((e["res"], "encre absente : " + ", ".join(manque)))
            continue
        # HORIZONTAL : la plume est deja avancee de adv(L) quand la marque est dessinee,
        # et on veut centre d'encre de la marque = centre d'encre de la lettre.
        term_new = cx(bLn) - adv_new[cL] - cx(bMn)
        term_stock = cx(bLs) - adv_stock[cL] - cx(bMs)
        H = int(round(e["H"] + (term_new - term_stock)))
        # VERTICAL : y croit vers le BAS, et le quad fait 16 px ecran pour 32 texels.
        kind = classify(M, e["V"])
        if kind == "above":      # on conserve l'ecart bas de la marque / haut de lettre
            d = (bLn[1] - bLs[1]) - (bMn[3] - bMs[3])
        elif kind == "below":    # ... bas de la lettre / haut de la marque
            d = (bLn[3] - bLs[3]) - (bMn[1] - bMs[1])
        else:                    # traversante : on suit le MILIEU de la lettre
            d = (mid(bLn) - mid(bLs)) - (mid(bMn) - mid(bMs))
        V = int(round(e["V"] + QUAD_H_RATIO * d))
        # SIGNE OBLIGATOIRE : sans signe, l'analyseur d'echappement FIXE la plume au
        # lieu de la decaler (font.gc cfg-113).
        if e["H2"] is None:
            raw = "%s~Y~%+dH~%+dV%s~Z" % (L, H, V, M)
        else:
            # le second `~NNH` est un deplacement entre DEUX MARQUES : il ne depend pas
            # de la chasse de la lettre, il reste tel quel.
            raw = "%s~Y~%+dH~%+dV%s~%+dH%s~Z" % (L, H, V, M, e["H2"], e["mark2"])
        a, b = m.span("raw")
        parts.append(region[pos:a])
        parts.append(raw)
        pos = b
        rows.append((e["res"], L, M, kind, e["H"], H, e["V"], V))
        control.append((e["res"], L, M, e["H"], term_stock))
    if i != len(ent):
        raise SystemExit("stock-accents.json : %d entrees gelees, %d retrouvees dans le "
                         "fichier — reference perimee" % (len(ent), i))
    parts.append(region[pos:])
    src = src[:lo] + "".join(parts) + src[hi:]

    hs, hn = ink_stock(stock_img, ord("H")), ink(img_new, ord("H"))
    caps = range(0x41, 0x5B)
    rep = ["recalage des entrees d'accents MAJUSCULES livrees par Naughty Dog",
           "=" * 66,
           "geometrie LIVREE   : %s -> ascii.24lo (cellule %dx%d, echelle 1)"
           % (os.path.relpath(FR3, ROOT), CW, CH),
           "                     avances : stock-tables.json cle font24, colonne w",
           "geometrie NOUVELLE : %s (surechantillonnee x%d)"
           % (os.path.relpath(ATLAS, ROOT), SCALE),
           "                     avances : urbanist-tables.json cle w_font24",
           "reference gelee    : %s (%d entrees)"
           % (os.path.relpath(STOCK_ACCENTS, ROOT), len(ent)),
           "",
           "ce qui impose le recalage (mesure sur les deux atlas, en texels) :",
           "  avance moyenne A-Z   %8.3f -> %8.3f   (x%.3f)"
           % (sum(adv_stock[c] for c in caps) / 26.0,
              sum(adv_new[c] for c in caps) / 26.0,
              (sum(adv_new[c] for c in caps) / 26.0)
              / (sum(adv_stock[c] for c in caps) / 26.0)),
           "  ligne de base (H)    %8.2f -> %8.2f" % (hs[3], hn[3]),
           "  hauteur de capitale  %8.2f -> %8.2f" % (hs[3] - hs[1], hn[3] - hn[1]),
           "",
           "a. RECALAGE — une ligne par entree",
           "   res base marque classe    H livre -> recale    V livre -> recale"]
    for r in rows:
        rep.append("   %-3s %-4s %-6s %-9s %4d -> %-4d %9d -> %-4d"
                   % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]))
    rep += ["",
            "b. CONTROLE — ce que le modele ABSOLU aurait predit, contre la valeur",
            "   REGLEE A LA MAIN par Naughty Dog. Le modele absolu est `cx(L) - adv(L)",
            "   - cx(M)` evalue sur la geometrie LIVREE : s'il etait juste, il rendrait",
            "   le H livre. C'est son ecart qui justifie d'appliquer une DIFFERENCE.",
            "   res base marque   H(ND)   H(modele absolu)   ecart"]
    gaps = []
    for c in control:
        g = int(round(c[4])) - c[3]
        gaps.append(g)
        rep.append("   %-3s %-4s %-6s %6d %12.2f %+14d"
                   % (c[0], c[1], c[2], c[3], c[4], g))
    if gaps:
        rep += ["",
                "   ecart (modele absolu - ND) : mediane %+.1f px, min %+d, max %+d,"
                % (statistics.median(gaps), min(gaps), max(gaps)),
                "   |mediane| %.1f px, ecart-type %.2f px, n = %d"
                % (statistics.median([abs(g) for g in gaps]),
                   statistics.pstdev(gaps), len(gaps)),
                "   VERDICT : %s" % ("mediane < 2 px, le modele absolu est BON en "
                                     "mediane ; ses extremes (%+d / %+d px) restent le "
                                     "motif d'employer la difference."
                                     % (min(gaps), max(gaps))
                                     if statistics.median([abs(g) for g in gaps]) < 2
                                     else "mediane >= 2 px, le modele absolu est refute, "
                                          "la difference est obligatoire.")]
    rep += ["", "c. COMPTES", "   recalees : %d" % len(rows),
            "   ignorees : %d" % len(skipped)]
    for s2 in skipped:
        rep.append("     %s : %s" % s2)
    return src, rep


def main():
    img = Image.open(ATLAS).convert("RGBA")
    adv24 = {int(k): v for k, v in
             json.load(open(os.path.join(FONTDIR, "urbanist-tables.json")))["w_font24"].items()}
    src = open(DB, encoding="utf-8").read()
    # 1) RECALER les majuscules livrees AVANT de lire le bloc : les minuscules derivent
    #    leur V de l'entree majuscule correspondante, elles doivent lire la valeur
    #    recalee, sinon les deux moities de la table decrivent deux geometries.
    src, rebase_report = rebase_uppercase(src, img, adv24)
    blk = src[src.index("replace_info_jak1"):]
    blk = blk[:blk.index("\n};")]

    one = re.compile(r'\{"([A-Za-z])~Y~([-+]?\d+)H~([-+]?\d+)V(<TIL>|[^~])~Z",\s*"(.+?)"\}')
    two = re.compile(r'\{"([A-Za-z])~Y~([-+]?\d+)H~([-+]?\d+)V(<TIL>|[^~])~([-+]?\d+)H(.)~Z",\s*"(.+?)"\}')

    out, skipped, rows = [], [], []
    seen = set()

    def emit(base_up, H_up, V_up, mark, res_up, second=None):
        low = res_up.lower()
        base_lo = base_up.lower()
        # le i accentue se compose sur le i SANS POINT (cellule 0x19), sinon le point
        # du i et l'accent se superposent
        if base_lo == "i":
            base_lo = "ı"
        if len(low) != 1 or low == res_up or low in seen:
            skipped.append((res_up, "pas de minuscule simple"))
            return
        cb_up = ink(img, ord(base_up))
        cb_lo = ink(img, DOTLESS if base_lo == "ı" else ord(base_lo))
        cm = ink(img, MARK_CODE[mark])
        if not (cb_up and cb_lo and cm):
            skipped.append((res_up, "encre absente dans l'atlas"))
            return
        centre = lambda b: (b[0] + b[2]) / 2.0
        # horizontal : meme regle que celle ajustee sur les entrees livrees (k = 1.000)
        H = int(round(centre(cb_lo) - centre(cm)
                      - adv24[DOTLESS if base_lo == "ı" else ord(base_lo)]))
        # vertical : on conserve la RELATION visuelle de l'entree majuscule livree
        kind = classify(mark, V_up)
        if kind == "above":
            # y croit vers le BAS ; une minuscule a son sommet d'encre PLUS BAS, donc le
            # decalage doit etre MOINS negatif pour que l'accent descende avec elle.
            V = V_up + (cb_lo[1] - cb_up[1]) * QUAD_H_RATIO
        elif kind == "below":
            V = V_up
        else:  # traversante : on suit le MILIEU de la lettre
            mid = lambda b: (b[1] + b[3]) / 2.0
            V = V_up + (mid(cb_lo) - mid(cb_up)) * QUAD_H_RATIO
        V = int(round(V))
        seen.add(low)
        # SIGNE OBLIGATOIRE : sans signe, l'analyseur d'echappement FIXE la plume a la
        # valeur absolue au lieu de la decaler (font.gc cfg-113 : `.add.x.vf.x vf23 vf0
        # vf1`). `~0V` remettrait donc y a zero. Les entrees livrees portent toutes leur
        # signe pour cette raison ("~+3V" dans Ą).
        if second is None:
            enc = "%s~Y~%+dH~%+dV%s~Z" % (base_lo, H, V, mark)
        else:
            enc = "%s~Y~%+dH~%+dV%s~%+dH%s~Z" % (base_lo, H, V, mark, second[0], second[1])
        out.append('    {"%s", "%s"},' % (enc, low))
        rows.append((res_up, low, base_lo, mark, H_up, H, V_up, V))

    for m in two.finditer(blk):
        emit(m.group(1), int(m.group(2)), int(m.group(3)), m.group(4), m.group(7),
             second=(int(m.group(5)), m.group(6)))
    for m in one.finditer(blk):
        if m.group(4) not in MARK_CODE:
            skipped.append((m.group(5), "marque inconnue %r" % m.group(4)))
            continue
        emit(m.group(1), int(m.group(2)), int(m.group(3)), m.group(4), m.group(5))

    report = []
    report.append("entrees minuscules fabriquees : %d" % len(out))
    report.append("resultat   base marque   H maj -> H min   V maj -> V min")
    for r in sorted(rows, key=lambda r: r[1]):
        report.append("  %-3s -> %-3s %-2s %-5s %6d -> %-6d %6d -> %-6d"
                      % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]))
    if skipped:
        report.append("ignorees : %d" % len(skipped))
        for s in skipped:
            report.append("  %s : %s" % s)
    print("\n".join(report))

    gen = ("    // ==== GENERE par recharged_assets/font/gen_accent_table.py — NE PAS "
           "EDITER A LA MAIN ====\n"
           "    // Composition des MINUSCULES accentuees. Les decalages sont en pixels\n"
           "    // ecran de la GRANDE police (unite mesuree sur les 50 entrees livrees,\n"
           "    // k = 1.000), et calcules sur l'atlas Urbanist genere.\n"
           + "\n".join(out) + "\n"
           "    // ==== FIN GENERE ====\n")
    marker = "    // ==== GENERE par recharged_assets/font/gen_accent_table.py"
    if marker in src:
        a = src.index(marker)
        b = src.index("    // ==== FIN GENERE ====\n", a) + len("    // ==== FIN GENERE ====\n")
        src = src[:a] + gen + src[b:]
    else:
        anchor = src.index("std::vector<ReplaceInfo> replace_info_jak1 = {")
        anchor = src.index("\n", anchor) + 1
        src = src[:anchor] + gen + src[anchor:]
    open(DB, "w").write(src)

    os.makedirs(REPORTDIR, exist_ok=True)
    open(os.path.join(REPORTDIR, "accent-table.txt"), "w").write("\n".join(report) + "\n")
    with io.open(os.path.join(REPORTDIR, "accent-rebase.txt"), "w",
                 encoding="utf-8") as f:
        f.write("\n".join(l.rstrip() for l in rebase_report) + "\n")
    print("\n".join(rebase_report))


if __name__ == "__main__":
    main()
