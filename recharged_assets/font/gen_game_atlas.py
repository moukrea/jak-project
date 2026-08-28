#!/usr/bin/env python3
"""Genere les atlas de police du JEU (jak1) en Urbanist, sur la grille EXACTE du moteur.

Pourquoi ce fichier remplace `gen_atlas.py` (qui reste, il sert de previsualisation)
------------------------------------------------------------------------------------
`gen_atlas.py` produisait un atlas a cellules VARIABLES avec des rects UV serres sur
l'encre. Le moteur de jak1 ne sait pas lire ca : `draw-string` ne lit qu'un COIN (u,v)
par glyphe dans `*font12-table*` / `*font24-table*` et ajoute une taille CONSTANTE
(`size-st1/2/3` de `font-work`). La grille est donc imposee, et un atlas hors grille
n'est pas branchable.

Grille MESUREE dans le moteur (goal_src/jak1/engine/gfx/font.gc + font-h.gc)
---------------------------------------------------------------------------
  index de glyphe = octet - 16                (font.gc:1091 `.sll t5-17 t4-21 4`
                                               puis `(.lvf vf5 (+ t5-18 -256))`)
  colonne = index % 10, ligne = index // 10   (verifie sur les 250/289 entrees)
  pas horizontal  = 12/128 = 0.09375          (u de la table)
  pas vertical    = 16/256 = 0.0625           (v de la table)
  premier coin    = (0.5/128, 0.5/256)
  etendue du quad = size-st1.x 0.08985 = 11.5/128 ; size-st2.y 0.06153846 ~ 15.75/256

  octet >= 128 -> gabarit "hi" (`(logand t4-21 128)` font.gc:1146) : les deux atlas
  `ascii.12hi` / `ascii.24hi` portent les KANA et ne sont PAS touches ici.

  avance = w * size1-small.w (0.5) pour le petit, * size1-large.w (1.0) pour le grand.

Ecrasement 2:1 du rendu — ce qui impose la forme des glyphes
------------------------------------------------------------
Le quad fait 12 x 8 unites ecran pour une cellule de 12 x 16 texels (jak2 fait
12 x 14.857 pour la meme cellule : jak1 est bien ecrase d'un facteur 2 en vertical).
Un glyphe dessine « droit » dans l'atlas sortirait donc ECRASE a l'ecran. On dessine
Urbanist avec une echelle VERTICALE double de son echelle horizontale, ce qui est
exactement la convention du jeu — c'est pourquoi ses capitales font 8 texels de large
pour 13 de haut.

Ce qui est ECRASE et ce qui est CONSERVE
----------------------------------------
On ne remplace QUE les cellules dont on sait, par mesure, qu'elles portent du latin.
Toute cellule qui porte un kana, un kanji ou une piece de BOUTON MANETTE garde ses
pixels d'origine — sauf les 26 cellules 0x61-0x7a du GRAND atlas, qui portent des
kanji et que l'on REAFFECTE aux minuscules a-z : c'est le seul moyen d'avoir des
minuscules en grande police, il n'existe aucune cellule libre atteignable.

Consequence : les pixels d'origine (kana, kanji, boutons) sont recopies depuis
`out/jak1/fr3/GAME.fr3`, donc l'atlas produit contient des pixels Naughty Dog. Il est
GENERE LOCALEMENT et n'est jamais commite (cf. .gitignore), exactement comme les
modeles HD.

Sortie
------
  custom_assets/jak1/recharged_textures/gamefontnew/ascii.12lo.png   (256x512)
  custom_assets/jak1/recharged_textures/gamefontnew/ascii.24lo.png   (512x1024)
  recharged_assets/font/urbanist-tables.json                          (avances + audit)

Licence : Urbanist est sous SIL Open Font License 1.1 ; NotoSansJP-Medium (utilisee
uniquement si un glyphe manque a Urbanist) l'est aussi.
"""

import json
import os
import re
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONTDIR = os.path.join(ROOT, "recharged_assets", "font")
FR3 = os.path.join(ROOT, "out", "jak1", "fr3", "GAME.fr3")
OUTDIR = os.path.join(ROOT, "custom_assets", "jak1", "recharged_textures", "gamefontnew")

# GRAISSE : Urbanist Bold (700). La regle a ete posee par le superviseur sur une mesure
# ("Hamburgefonstiv 123" a 48 px : 500 -> 4567 px d'encre, 600 -> 5532, 700 -> 6337,
# soit +14,6 %) mais le fichier n'etait pas dans l'arbre et ce generateur pointait encore
# sur le 600 : la regle etait ECRITE, pas CABLEE. Le TTF est desormais livre ici.
URBANIST = os.path.join(FONTDIR, "Urbanist-700.ttf")
NOTOJP = os.path.join(ROOT, "game", "assets", "fonts", "NotoSansJP-Medium.ttf")

ST1_X = 0.08985     # size-st1.x (font-h.gc:297) : part VISIBLE de la cellule en u
ST2_Y = 0.06153846  # size-st2.y (font-h.gc:299) : part VISIBLE de la cellule en v
VMARGIN = 0.5       # marge verticale totale laissee dans la cellule, en texels
HMARGIN = 0.25      # idem horizontalement
SCALE = 2  # facteur de suréchantillonnage de l'atlas (UV inchangés, ils sont normalisés)

# ---------------------------------------------------------------------------------------
# Plan des cellules. None = on GARDE les pixels d'origine.
# Etabli par MESURE des atlas livres (voir le rapport de phase), pas par supposition.
# ---------------------------------------------------------------------------------------
MARKS = {
    0x10: "ˇ",  # caron
    0x11: "`",       # accent grave
    0x12: "´",  # accent aigu (sert aussi d'apostrophe : "'" est encode en 0x12)
    0x13: "ˆ",  # circonflexe
    0x14: "˜",  # tilde
    0x15: "¨",  # trema
    0x16: "°",  # rond en chef / degre
    0x17: "¡",
    0x18: "¿",
}


def base_plan():
    """Cellules communes aux deux atlas."""
    p = dict(MARKS)
    # 0x19 n'est produit par AUCUNE entree d'encodage ni de remplacement, et le corpus
    # ne contient aucun echappement \cXX : la cellule est donc inatteignable par le
    # texte. On la REAFFECTE au « i sans point », base obligatoire des minuscules
    # accentuees (sinon i + accent aigu dessine un point ET un accent).
    p[0x19] = "ı"
    p[0x1B] = "Æ"
    p[0x1D] = "Ç"
    p[0x1F] = "ß"
    p[0x20] = " "
    p[0x21] = "!"
    p[0x22] = '"'
    p[0x25] = "%"
    p[0x28] = "("
    p[0x29] = ")"
    p[0x2B] = "+"
    p[0x2C] = ","
    p[0x2D] = "-"
    p[0x2E] = "."
    p[0x2F] = "/"
    for i in range(10):
        p[0x30 + i] = chr(ord("0") + i)
    p[0x3A] = ":"
    p[0x3D] = "="
    p[0x3F] = "?"
    for i in range(26):
        p[0x41 + i] = chr(ord("A") + i)
    p[0x7C] = "Œ"  # Œ
    # kana presents dans l'atlas latin : gardes tels quels
    for c in (0x24, 0x26, 0x27, 0x60, 0x7B, 0x7D):
        p[c] = None
    return p


def plan_small():
    p = base_plan()
    # Dans le PETIT atlas ces cellules portent de la vraie ponctuation (mesure), pas
    # des pieces de bouton : on peut les remplacer.
    p[0x1A] = "©"  # ©
    p[0x1C] = "æ"  # æ
    p[0x1E] = "ç"  # ç
    p[0x23] = "#"
    p[0x2A] = "*"
    p[0x3B] = ";"
    p[0x3C] = "<"
    p[0x3E] = ">"
    p[0x40] = None      # glyphe rond : bouton CERCLE en petite police aussi -> garde
    p[0x5B] = "["
    p[0x5C] = "\\"
    p[0x5D] = "]"
    p[0x5E] = "œ"  # œ
    p[0x5F] = "_"
    for i in range(26):
        p[0x61 + i] = chr(ord("a") + i)
    p[0x7E] = "~"
    p[0x7F] = "™"  # ™
    return p


def plan_large():
    p = base_plan()
    # Dans le GRAND atlas ces cellules portent l'art des BOUTONS MANETTE (mesure :
    # 0x23 carre, 0x2a croix, 0x3b triangle, 0x3c corps du bouton, 0x3e reflet,
    # 0x40 cercle, 0x5b reflet) et des KANJI (0x1a 0x1c 0x1e 0x5c-0x5f 0x7e 0x7f).
    for c in (0x23, 0x2A, 0x3B, 0x3C, 0x3E, 0x40,
              0x5B, 0x5C, 0x5D, 0x5F, 0x7E, 0x7F):
        p[c] = None
    # REAFFECTES depuis des kanji, parce que les langues latines en ont besoin et que
    # le PETIT atlas les porte deja aux memes octets : sans ca les deux polices n'ont
    # pas la meme page de codes et « ca » s'ecrit « 学a » en grande police.
    p[0x1A] = "©"  # portait 海
    p[0x1C] = "æ"  # portait 界
    p[0x1E] = "ç"  # portait 学
    p[0x5E] = "œ"  # portait 空 — le francais en a besoin.
    # REAFFECTATION ASSUMEE : 26 kanji -> minuscules latines. Sans elle la grande
    # police ne peut PAS ecrire en casse mixte, ce qui est la demande de l'owner.
    for i in range(26):
        p[0x61 + i] = chr(ord("a") + i)
    return p


ATLASES = [
    # nom, largeur, hauteur, cellule w, cellule h, hauteur du quad ECRAN, plan
    ("ascii.12lo", 128, 256, 12, 16, 8, plan_small),
    ("ascii.24lo", 256, 512, 24, 32, 16, plan_large),
]


# ---------------------------------------------------------------------------------------
# Lecture des atlas livres dans GAME.fr3 (zstd + serialisation tfrag3)
# ---------------------------------------------------------------------------------------
def read_stock_atlases():
    import subprocess

    raw = open(FR3, "rb").read()
    dec = subprocess.run(["zstd", "-d", "-c"], input=raw[8:], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, check=True).stdout
    out = {}
    for m in re.finditer(rb"ascii\.\d\d(?:hi|lo)", dec):
        name = m.group(0).decode()
        p = m.start()
        if struct.unpack_from("<Q", dec, p - 8)[0] != len(name):
            continue
        dend = p - 8
        for nwords in (128 * 256, 256 * 512):
            ds = dend - nwords * 4 - 8
            if ds > 0 and struct.unpack_from("<Q", dec, ds)[0] == nwords:
                h = struct.unpack_from("<H", dec, ds - 6)[0]
                w = struct.unpack_from("<H", dec, ds - 8)[0]
                out[name] = Image.frombytes(
                    "RGBA", (w, h), dec[ds + 8: ds + 8 + nwords * 4])
                break
    return out


def ink_box(img, cw, ch, code, thr=8):
    """Boite d'encre (alpha) de la cellule d'un octet, en texels de la cellule."""
    idx = code - 16
    x0, y0 = (idx % 10) * cw, (idx // 10) * ch
    a = img.split()[3].crop((x0, y0, x0 + cw, y0 + ch))
    bbox = a.point(lambda v: 255 if v > thr else 0).getbbox()
    return bbox  # (l, t, r, b) exclusif a droite/en bas, ou None


# ---------------------------------------------------------------------------------------
# Rendu Urbanist
# ---------------------------------------------------------------------------------------
class Renderer:
    """Rend un glyphe avec une echelle verticale DOUBLE de l'horizontale.

    PIL ne sait pas etirer un rendu de texte ; on rend donc a grande taille dans une
    image temporaire puis on redimensionne, ce qui donne un controle exact des deux
    echelles independamment et un anticrenelage propre.
    """

    OVERSAMPLE = 8

    def __init__(self, path_main, path_fallback, em_px):
        self.em = em_px
        self.f_main = ImageFont.truetype(path_main, em_px * self.OVERSAMPLE)
        self.f_fb = ImageFont.truetype(path_fallback, em_px * self.OVERSAMPLE)

    def font_for(self, ch):
        try:
            if self.f_main.getmask(ch).getbbox() is None and ch.strip():
                return self.f_fb
        except Exception:
            return self.f_fb
        return self.f_main

    def metrics(self, ch):
        """(advance, bbox) en unites em_px, mesures a l'oversample puis divises."""
        f = self.font_for(ch)
        o = self.OVERSAMPLE
        adv = f.getlength(ch) / o
        bb = f.getbbox(ch)
        return adv, tuple(v / o for v in bb)

    def render(self, ch, sx, sy):
        """Rend `ch` en une image L, echelles sx (horizontale) et sy (verticale)
        appliquees a l'em. Rend aussi (dx, dy) = position de l'encre par rapport a
        l'origine du texte (gauche, ascendante), dans les memes unites."""
        f = self.font_for(ch)
        o = self.OVERSAMPLE
        bb = f.getbbox(ch)
        if bb is None or bb[2] <= bb[0] or bb[3] <= bb[1]:
            return None, 0.0, 0.0
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        img = Image.new("L", (w + 4, h + 4), 0)
        ImageDraw.Draw(img).text((2 - bb[0], 2 - bb[1]), ch, font=f, fill=255)
        # sx / sy sont exprimes en "px d'em" ; l'image est rendue a em*OVERSAMPLE.
        kx, ky = sx / (self.em * o), sy / (self.em * o)
        nw = max(1, int(round(img.width * kx)))
        nh = max(1, int(round(img.height * ky)))
        return img.resize((nw, nh), Image.LANCZOS), (bb[0] - 2) * kx, (bb[1] - 2) * ky


def build(stock, name, W, H, cw, ch, ch_screen, plan_fn, report):
    plan = plan_fn()
    src = stock[name]
    S = SCALE
    out = src.resize((W * S, H * S), Image.LANCZOS)

    # --- metriques de reference, MESUREES sur l'atlas livre -----------------------------
    hb = ink_box(src, cw, ch, ord("H"))
    cap_top, cap_bot = hb[1], hb[3]          # sommet et base des capitales, en texels
    cap_h = cap_bot - cap_top
    stock_caps = [ink_box(src, cw, ch, 0x41 + i) for i in range(26)]
    stock_capw = sum((b[2] - b[0]) for b in stock_caps if b) / 26.0
    stock_adv = sum(ADV[name][0x41 + i] for i in range(26)) / 26.0

    # LARGEUR VISIBLE de la cellule : le quad ne montre PAS toute la cellule. Elle se
    # DERIVE de la constante du moteur (`size-st1.x` de font-h.gc:297), jamais d'un
    # nombre choisi : 0.08985 * 128 = 11.50 texels (petit), * 256 = 23.00 (grand).
    vu = ST1_X * W
    vh = ST2_Y * H   # 15.75 texels (petit), 31.50 (grand) : le dernier demi-texel de la
                     # cellule n'est JAMAIS affiche, un jambage pose dessus serait coupe.

    r = Renderer(URBANIST, NOTOJP, 64)
    base_em = r.metrics("H")[1][3]           # ligne de base, depuis l'ascendante, a em=64
    urb_cap = base_em - r.metrics("H")[1][1]
    urb_capw = sum((r.metrics(chr(ord("A") + i))[1][2] - r.metrics(chr(ord("A") + i))[1][0])
                   for i in range(26)) / 26.0

    # ------------------------------------------------------------------------------------
    # CALIBRATION — elle sort de DEUX contraintes de place mesurees, pas d'un postulat.
    #
    # Le cycle precedent calait la hauteur de capitale sur celle du jeu (27 texels en
    # grande police). Ca ne peut pas tenir des qu'on ecrit en casse mixte : la police
    # d'origine est TOUT-MAJUSCULES et sa descendante ne fait que 3 texels ; celle
    # d'Urbanist en demande 9,7 a cette taille. Capitale + jambage = 39,1 texels dans une
    # cellule de 32 : les jambages de p y q j g sortaient donc par le bas de la cellule.
    # La cellule est la LIGNE : un quad de 24 x 16 px ecran pour une cellule 24 x 32
    # texels. Donc, sur une ligne de hauteur fixe, des vraies descendantes se paient en
    # hauteur de capitale. C'est une propriete de la police, pas un reglage.
    #
    #   VERTICAL   : ascendante la plus haute -> jambage le plus bas doit tenir dans la
    #                cellule. Fixe sy ET la ligne de base.
    #   HORIZONTAL : la LETTRE la plus large ('M') doit tenir dans la largeur VISIBLE.
    #                Fixe le plafond de sx ; on garde le calage sur la chasse du jeu
    #                quand il est plus serre (c'est le cas en petite police).
    #
    # Les marques combinantes 0x10-0x16 sont exclues du calcul : elles sont posees par
    # les decalages ~NNH/~NNV de la table d'accents, qui les mesure APRES coup.
    # ------------------------------------------------------------------------------------
    free_marks = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16}
    drawn_chars = [(c, v) for c, v in sorted(plan.items())
                   if v is not None and v.strip() and c not in free_marks]
    letters = [v for c, v in drawn_chars if len(v) == 1 and v.isalnum() and ord(v) < 128]
    bbs = {v: r.metrics(v)[1] for _, v in drawn_chars}
    asc_em = base_em - min(b[1] for b in bbs.values())
    desc_em = max(b[3] for b in bbs.values()) - base_em
    right_letters = max(bbs[v][2] for v in letters)

    sy = (vh - VMARGIN) / (asc_em + desc_em) * 64.0
    baseline = VMARGIN * 0.5 + asc_em * sy / 64.0     # ligne de base, en texels de cellule
    sx_stock = stock_capw / urb_capw * 64.0           # calage sur la chasse du jeu
    sx_fit = (vu - HMARGIN) / right_letters * 64.0    # plafond impose par la cellule
    sx = min(sx_stock, sx_fit)

    advances = {}
    drawn, kept, condensed, clamped = 0, 0, [], []
    # transformation appliquee aux cellules CONSERVEES (art des boutons, kana, kanji) :
    # meme changement d'echelle et meme ligne de base que le latin, sinon les icones de
    # manette de `<PAD_X>` resteraient a l'ancienne ligne et pendraient sous le texte.
    fy = (urb_cap * sy / 64.0) / cap_h
    fx = (urb_capw * sx / 64.0) / stock_capw
    for code in range(0x10, 0x80):
        want = plan.get(code, None)
        idx = code - 16
        cx, cy = (idx % 10) * cw * S, (idx // 10) * ch * S
        if want is None:
            kept += 1
            advances[code] = ADV[name][code] * fx
            cell = src.crop(((idx % 10) * cw, (idx // 10) * ch,
                             (idx % 10) * cw + cw, (idx // 10) * ch + ch))
            moved = cell.transform((cw * S, ch * S), Image.AFFINE,
                                   (1.0 / (S * fx), 0.0, 0.0,
                                    0.0, 1.0 / (S * fy), cap_bot - baseline / fy),
                                   Image.BICUBIC)
            # l'interpolation bicubique DEPASSE (mesure : alpha 147 et 153 sur les pieces
            # de bouton, contre 128 = opaque dans la convention PS2 de l'atlas livre). On
            # rabat, sinon ces cellules seraient plus lumineuses que le texte a cote.
            r_, g_, b_, a_ = moved.split()
            moved = Image.merge("RGBA", (r_.point(lambda v: 255), g_.point(lambda v: 255),
                                         b_.point(lambda v: 255),
                                         a_.point(lambda v: min(v, 128))))
            out.paste((0, 0, 0, 0), (cx, cy, cx + cw * S, cy + ch * S))
            out.paste(moved, (cx, cy))
            continue
        # efface la cellule
        out.paste((0, 0, 0, 0), (cx, cy, cx + cw * S, cy + ch * S))
        gsx = sx
        adv_em, gbb = r.metrics(want)
        if want.strip():
            # un glyphe encore trop large pour sa cellule est CONDENSE lui-meme, plutot
            # que de retrecir toute la police pour quatre symboles ; son avance suit le
            # meme facteur, sinon il laisserait un trou derriere lui.
            gr = gbb[2] * sx / 64.0
            if gr > vu:
                k = vu / gr
                gsx = sx * k
                condensed.append((code, want, k))
        advances[code] = adv_em * gsx / 64.0
        drawn += 1
        if not want.strip():
            continue
        # DEFAUT CORRIGE : le glyphe se rasterise DANS le repere de l'atlas
        # sur-echantillonne, donc a l'echelle gsx*S / sy*S. La version precedente le
        # rasterisait a l'echelle 1x et ne multipliait par S que sa POSITION : chaque
        # glyphe sortait a la MOITIE de sa taille, et son decalage a la ligne de base
        # etait double par rapport a son propre corps -- d'ou les trois niveaux
        # d'alignement vus par l'owner (capitales / x-height / hampes) et l'espacement
        # enorme (l'avance, elle, restait celle d'un glyphe pleine taille).
        # Tout est desormais en PIXELS D'ATLAS : dx, dy, base_px et baseline * S.
        glyph, dx, dy = r.render(want, gsx * S, sy * S)
        if glyph is None:
            continue
        base_px = base_em * (sy * S) / 64.0   # ligne de base depuis l'ascendante, px atlas
        px = cx + int(round(dx))
        py = cy + int(round(baseline * S - base_px + dy))
        if code in free_marks and py < cy:
            clamped.append((code, want, cy - py))
            py = cy
        if px < cx:
            px = cx
        out.alpha_composite(
            Image.merge("RGBA", (glyph.point(lambda v: 255),) * 3
                        + (glyph.point(lambda v: v * 128 // 255),)), (px, py))

    report.append("[%s] %dx%d -> %dx%d (x%d)  cellule %dx%d, largeur VISIBLE %.2f texels"
                  % (name, W, H, W * S, H * S, S, cw, ch, vu))
    report.append("  ligne de base : jeu %.2f -> Urbanist %.2f texels (%+.2f texel, soit "
                  "%+.2f px ecran) ; il FAUT la remonter, la police du jeu est "
                  "tout-majuscules et n'a que %.0f texels sous sa base"
                  % (cap_bot, baseline, baseline - cap_bot,
                     (baseline - cap_bot) * (ch_screen / ch), ch - cap_bot))
    report.append("  contrainte VERTICALE : ascendante %.2f + jambage %.2f = %.2f em px "
                  "doivent tenir dans les %.2f texels VISIBLES de la cellule -> sy = %.3f"
                  % (asc_em, desc_em, asc_em + desc_em, vh, sy))
    report.append("  contrainte HORIZONTALE : lettre la plus large %.2f em px dans %.2f "
                  "texels visibles -> sx <= %.3f ; calage sur la chasse du jeu -> %.3f ; "
                  "retenu %.3f" % (right_letters, vu, sx_fit, sx_stock, sx))
    report.append("  hauteur de capitale : jeu %.2f -> Urbanist %.2f texels (x%.3f), soit "
                  "%.2f -> %.2f px ecran. C'est le PRIX des vraies descendantes sur une "
                  "ligne de hauteur fixe." % (cap_h, urb_cap * sy / 64.0,
                                              urb_cap * sy / 64.0 / cap_h,
                                              cap_h * ch_screen / ch,
                                              urb_cap * sy / 64.0 * ch_screen / ch))
    report.append("  cellules redessinees %d, conservees %d (conservees remises a la "
                  "meme echelle x%.3f/x%.3f et a la MEME ligne de base : les pieces de "
                  "<PAD_X> restent solidaires du texte)" % (drawn, kept, fx, fy))
    new_adv = sum(advances[0x41 + i] for i in range(26)) / 26.0
    report.append("  avance moyenne A-Z : livree %.3f, Urbanist %.3f (x%.3f)" %
                  (stock_adv, new_adv, new_adv / stock_adv))
    if condensed:
        report.append("  GLYPHES CONDENSES pour tenir dans la cellule : %d" % len(condensed))
        for c, g, k in condensed:
            report.append("    0x%02x %r x%.3f" % (c, g, k))
    else:
        report.append("  aucun glyphe condense")
    if clamped:
        report.append("  MARQUES COMBINANTES recalees en haut de cellule : %d" % len(clamped))
        for c, g, d in clamped:
            report.append("    0x%02x %r remontee de %d px atlas" % (c, g, d))
    return out, advances


# ---------------------------------------------------------------------------------------
# Table d'avances livree, lue dans font.gc (colonne w)
# ---------------------------------------------------------------------------------------
def read_shipped_tables():
    src = open(os.path.join(ROOT, "goal_src", "jak1", "engine", "gfx", "font.gc"),
               encoding="utf-8").read()

    def grab(n):
        i = src.index("(define *%s*" % n)
        d = 0
        for j in range(i, len(src)):
            if src[j] == "(":
                d += 1
            elif src[j] == ")":
                d -= 1
                if d == 0:
                    return src[i:j + 1]
        raise RuntimeError(n)

    def rows(n):
        out = []
        for e in re.findall(r"\(new 'static 'vector([^)]*)\)", grab(n)):
            d = {k: float(v) for k, v in re.findall(r":(\w+) ([-0-9.]+)", e)}
            out.append((d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0), d.get("w", 0.0)))
        return out

    return rows("font12-table"), rows("font24-table")


def main():
    # PIEGE DEJA PAYE : ce script LIT font.gc pour la table livree, et il ECRIT (via le
    # patcheur) dans font.gc. Une seconde course lisait donc ses propres valeurs comme
    # « reference livree ». La reference est donc figee une fois pour toutes dans
    # stock-tables.json, cree depuis un font.gc INTACT, et relue ensuite.
    stock_path = os.path.join(FONTDIR, "stock-tables.json")
    if os.path.exists(stock_path):
        d = json.load(open(stock_path))
        t12 = [tuple(v) for v in d["font12"]]
        t24 = [tuple(v) for v in d["font24"]]
    else:
        t12, t24 = read_shipped_tables()
        json.dump({"font12": [list(v) for v in t12], "font24": [list(v) for v in t24]},
                  open(stock_path, "w"))
    # avance en TEXELS de la cellule : w * (0.5 pour le petit, 1.0 pour le grand) donne
    # des pixels ecran ; la cellule fait 12 (resp. 24) texels pour 12 (resp. 24) px ecran,
    # donc texels == px ecran horizontalement dans les deux cas.
    global ADV
    ADV = {
        "ascii.12lo": {c: t12[c - 16][3] * 0.5 for c in range(0x10, 0x80)},
        "ascii.24lo": {c: t24[c - 16][3] * 1.0 for c in range(0x10, 0x80)},
    }

    stock = read_stock_atlases()
    missing = [n for n, *_ in ATLASES if n not in stock]
    if missing:
        sys.exit("atlas livre introuvable dans %s : %s" % (FR3, missing))

    os.makedirs(OUTDIR, exist_ok=True)
    report = []
    tables = {}
    for name, W, H, cw, ch, ch_screen, plan_fn in ATLASES:
        img, adv = build(stock, name, W, H, cw, ch, ch_screen, plan_fn, report)
        img.save(os.path.join(OUTDIR, name + ".png"))
        # reconversion en colonne w de la table GOAL
        k = 0.5 if name.startswith("ascii.12") else 1.0
        tables[name] = {"%d" % c: round(adv[c] / k, 4) for c in sorted(adv)}
        report.append("  ecrit %s" % os.path.join(OUTDIR, name + ".png"))

    with open(os.path.join(FONTDIR, "urbanist-tables.json"), "w") as f:
        json.dump({"scale": SCALE, "w_font12": tables["ascii.12lo"],
                   "w_font24": tables["ascii.24lo"]}, f, indent=1)
    print("\n".join(report))
    rp = os.path.join(ROOT, ".autoport", "reports", "Gfont-urbanist")
    os.makedirs(rp, exist_ok=True)
    with open(os.path.join(rp, "atlas-cells.txt"), "w") as f:
        f.write("\n".join(report) + "\n")


if __name__ == "__main__":
    main()
