#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gcs_ink.py -- BANDE D'ENCRE de l'indice « maintenir CERCLE pour passer », et marges de
centrage de sa cartouche, pour les 23 langues de l'id #x17af (`pc-text-cutscene-skip`).

    python3 .autoport/gcs_ink.py [chemin/vers/x86-run.log] [--glyphes]

Phase Gcutscene-skip-polish. LECTURE SEULE : ce script n'ecrit aucun fichier.

===========================================================================================
1. CORRESPONDANCE GLYPHE -> CELLULE D'ATLAS -- CE QUE J'EMPLOIE, ET D'OU CA VIENT
===========================================================================================

Ce script ne devine RIEN de la correspondance : elle est LUE dans le depot, et chaque
maillon porte sa citation. La chaine complete, d'un octet de la banque de texte jusqu'aux
texels de l'atlas, tient en cinq faits verifiables :

  (a) UN OCTET -> UNE LIGNE DE `*font24-table*`, A L'INDICE `octet - 16`.
      - table :        goal_src/jak1/engine/gfx/font.gc:296   `(define *font24-table* ... 289 entrees)`
      - dans le DESSIN : goal_src/jak1/engine/gfx/font.gc:1146-1147
            (.addu t5-18 t5-17 font-table-to-use)     ; t5-17 = octet << 4  (font.gc:1143)
            (.lvf  vf5   (+ t5-18 -256))              ; -256 octets = -16 vecteurs
        soit `table[octet - 16]`.
      - dans la MESURE : goal_src/jak1/engine/gfx/font.gc:1621
            (.lvf vf5 (&-> kerning-table (- cur-char 16) quad))
      - et dans la sonde deja livree : goal_src/jak1/engine/gfx/font.gc:625
            (row (-> tbl (- c 16)))
      Les trois sites disent la MEME chose. C'est la correspondance, elle n'est pas devinee.

  (b) LE BIT 7 DE L'OCTET CHOISIT LA TEXTURE, PAS LA LIGNE DE TABLE.
      goal_src/jak1/engine/gfx/font.gc:1193-1197
            (let ((t4-28 (logand t4-21 128))) ... (.movn-128 t5-23 q-hi-tmpl t4-28 t5-22))
      octet < 0x80 -> gabarit `large-font-lo-tmpl` -> texture `ascii.24lo`
      octet >= 0x80 -> gabarit `large-font-hi-tmpl` -> texture `ascii.24hi`
      (gabarits : goal_src/jak1/engine/gfx/font-h.gc:200-203, charges en font.gc:863-864)
      Les deux textures partagent la MEME grille de coordonnees ; seule la page change.

  (c) LA LIGNE DE TABLE DONNE LE COIN HAUT-GAUCHE DE LA CELLULE, EN COORDONNEES NORMALISEES.
      `x` = s du bord gauche, `y` = t du bord haut, `w` = AVANCE en unites de police.
      Verifie par la sonde du depot (font.gc:621-633), qui publie `(-> row y)` comme
      « coordonnee de texture NORMALISEE (x hauteur de texture = ligne de texel) ».

  (d) LA TAILLE DE LA CELLULE EST FIXE, LA MEME POUR TOUS LES GLYPHES.
      - en TEXELS (fraction de la texture) :
          size-st1.x = 0.08985     goal_src/jak1/engine/gfx/font-h.gc:297-298
          size-st2.y = 0.06153846  goal_src/jak1/engine/gfx/font-h.gc:299-300
        chargees en vf16/vf17 (font.gc:847-848) et ajoutees au coin (font.gc:1149-1152).
      - en UNITES DE POLICE :
          size1-large = (24,0,0,1.0)   goal_src/jak1/engine/gfx/font-h.gc:291-292
          size2-large = (0,16,0,16)    goal_src/jak1/engine/gfx/font-h.gc:293-294
        les quatre coins du quad valent plume+vf0, plume+vf13, plume+vf14, plume+vf15
        (font.gc:1153-1156 et 1132) : la cellule fait 24 x 16 unites de police et son coin
        HAUT-GAUCHE est la plume elle-meme (`pos0 = plume + vf0`, vf0 = (0,0,0,1)).
      Donc : 1 texel = 24/(0.08985*larg_texture) en x, 16/(0.06153846*haut_texture) en y.

  (e) LES ATLAS LUS.
      lo : custom_assets/jak1/recharged_textures/gamefontnew/ascii.24lo.png   512 x 1024
           (le pack livre, deux fois la definition du stock -- meilleure resolution de mesure
            pour un mapping NORMALISE donc invariant d'echelle)
      hi : extracted_textures/jak1/gamefontnew/ascii.24hi.png                 256 x 512
           (le pack `recharged_textures` ne remplace QUE `ascii.24lo` et `ascii.12lo` :
            `ls custom_assets/jak1/recharged_textures/gamefontnew/` -> 2 fichiers.
            Les octets >= 0x80, employes par le japonais, tapent donc le STOCK.)

  CONTROLE DE CETTE CHAINE, calcule a chaque execution et publie en `CUTINK-VERIF` :
  la bande d'encre du fond de bouton `<` doit retomber sur les constantes deja livrees
  `CS_INK_TOP 0.01` / `CS_INK_BOT 12.46` (goal_src/jak1/pc/cutscene-skip-draw.gc:86-87),
  et le `p` doit descendre a 15.50. Si ces trois nombres ne sortent pas, la correspondance
  est fausse et il ne faut RIEN croire de ce que le script publie ensuite.

  CE QUE CETTE CORRESPONDANCE N'EST PAS : une correspondance CARACTERE -> cellule. Le
  caractere n'entre nulle part dans le rendu, seul l'octet compte. Le passage
  « texte UTF-8 -> octets » est fait plus bas par une re-implementation de la banque
  (common/util/font/font_utils.cpp:112-156), elle-meme CONFRONTEE aux octets que le jeu a
  lui-meme imprimes dans le journal de course (ligne `CUTINK-VERIF encodage=`).

===========================================================================================
2. AVANCE ET ECHAPPEMENTS -- MEME REGLE QUE `get-string-length`
===========================================================================================
  goal_src/jak1/engine/gfx/font.gc:1531-1628 (GOAL lisible), recoupe avec le chemin de
  DESSIN font.gc:1050-1125 (mips2c) :
    octet 0        : fin de chaine
    octet 1        : forme deux octets, glyphe = (octet2 & 127) + 255, page = bit 7 d'octet2
    `~Y` / `~y`    : SAUVE la plume (x et y)          font.gc:1578-1580 / dessin cfg-119
    `~Z` / `~z`    : RESTAURE la plume                font.gc:1581-1583 / dessin cfg-120
    `~[+-]<n>H`    : plume.x += / -= / = n            font.gc:1607-1613 / dessin cfg-109
    `~[+-]<n>V`    : plume.y += / -= / = n            dessin cfg-114-118 (IGNORE par
                     get-string-length, qui ne mesure que l'horizontale -- mais PAS par le
                     dessin : c'est ce qui pose les accents, `Ü` = U + umlaut a -2V)
    `~<n>L`,`~<n>J`: sans effet geometrique           font.gc:1604
    `~<n>K`        : drapeau `kerning`                font.gc:1605-1606
    `~<n>N`        : bascule grande/petite police     font.gc:1592-1603  (NON SUPPORTE ICI :
                     le script le signale et refuse de publier la langue concernee)
    autre lettre   : le caractere est DESSINE tel quel (dessin cfg-122)
    octet 10 / 13  : retour a l'origine x, +16 en y   font.gc:1622
    glyphe normal  : plume.x += table[c-16].w * size1-large.w  si `kerning` (font.gc:1622)
                                 sinon size2-large.w (= 16)
  Le drapeau employe par la cartouche est `(font-flags shadow kerning middle large)`
  (goal_src/jak1/pc/cutscene-skip-draw.gc:661) : kerning ACTIF, k = size1-large.w = 1.0.

===========================================================================================
3. DE L'UNITE DE POLICE A L'UNITE DE TOILE (512 x 224)
===========================================================================================
  largeur rendue = avance * CS_TEXT_SCALE * relative-x-scale     (cutscene-skip-draw.gc:360-362)
  hauteur rendue = f      * CS_TEXT_SCALE * relative-y-scale     (cutscene-skip-draw.gc:376-378)
  relative-x-scale = 1.0 en 4:3 / 0.75 en 16:9 (video.gc:66-69) -- PRIS DANS LE JOURNAL.
  relative-y-scale = 1.0 en NTSC (video.gc:15,37), 1.1428572 en PAL (video.gc:26).
  RESERVE HONNETE : le journal ne publie que `rxs`. Toutes les marges VERTICALES ci-dessous
  supposent donc NTSC (rys = 1.0), ce qui est le cas de la course lue. En PAL l'ancre du
  texte (`origin.y`, non multipliee par rys) et celle de la cartouche (multipliee par rys,
  cutscene-skip-draw.gc:208-209) ne vivraient PAS dans le meme repere -- defaut reel, hors
  perimetre de cet instrument, mais signale plutot que tu.

  Le drapeau `middle` (bit 2, font-h.gc:58) place la plume a X - largeur_rendue/2 :
  font.gc:1027 `(b! (logtest? flags 16) ...)` puis cfg-71 font.gc:1034-1036
      (.mul.w.vf.x vf1 vf1 vf16)   ; vf16.w = size-st1.w = 0.5   (font-h.gc:297-298)
      (.sub.vf.x   vf23 vf24 vf1)  ; plume = origine - largeur/2

  L'OMBRE (`shadow`) est EXCLUE de la mesure : elle est un second passage decale, et le
  verdict de centrage porte sur le texte.
===========================================================================================
"""

import os
import re
import sys
import math
import zlib
import struct
import glob
import time
import hashlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# --- seuil d'encre, PUBLIE et unique -------------------------------------------------------
# Les deux atlas sont des masques ALPHA (rgb=255 partout, l'encre est dans alpha). L'opacite
# maximale relevee vaut 128 sur le stock (convention PS2) et 156 sur le pack livre : le seuil
# est donc bas volontairement. Il est le SEUL parametre libre de la mesure.
ALPHA_MIN = 16

# --- constantes du moteur, toutes citees dans l'en-tete ------------------------------------
ST_W = 0.08985      # font-h.gc:297-298  size-st1.x
ST_H = 0.06153846   # font-h.gc:299-300  size-st2.y
CELL_W_FU = 24.0    # font-h.gc:291-292  size1-large.x
CELL_H_FU = 16.0    # font-h.gc:293-294  size2-large.y
ADV_K = 1.0         # font-h.gc:291-292  size1-large.w  (grande police)
NOKERN_ADV = 16.0   # font-h.gc:293-294  size2-large.w

# --- constantes de la cartouche (goal_src/jak1/pc/cutscene-skip-draw.gc:67-87) --------------
CS_MARGIN_X = 16
CS_MARGIN_Y = 12
CS_PAD_X = 11
CS_PAD_Y = 6.0
CS_TEXT_SCALE = 0.8
CS_INK_TOP = 0.01
CS_INK_BOT = 12.46
CS_BOX_H_C1 = 22    # cycle 1 : hauteur CHOISIE (git 86a5f9af44, ligne 42)
CS_TEXT_DY_C1 = 2   # cycle 1 : descente du texte (git 86a5f9af44, ligne 44)
CANVAS_W = 512
CANVAS_H = 224
DEFAULT_RYS = 1.0   # NTSC (video.gc:15,37)

ATLAS_LO = os.path.join(ROOT, "custom_assets/jak1/recharged_textures/gamefontnew/ascii.24lo.png")
ATLAS_HI = os.path.join(ROOT, "extracted_textures/jak1/gamefontnew/ascii.24hi.png")
FONT_GC = os.path.join(ROOT, "goal_src/jak1/engine/gfx/font.gc")
FONT_DB = os.path.join(ROOT, "common/util/font/dbs/font_db_jak1.cpp")
TEXT_GP = os.path.join(ROOT, "game/assets/jak1/game_text.gp")
TEXT_DIR = os.path.join(ROOT, "game/assets/jak1/text")
DEFAULT_LOG = os.path.join(ROOT, ".autoport/reports/Gcutscene-skip-all/x86-run.log")
TEXT_ID = "17af"


# ==========================================================================================
#  PNG -- Pillow s'il est la, sinon zlib+struct a la main (les deux donnent le meme octet)
# ==========================================================================================
def _png_manual(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "pas un PNG: " + path
    off, idat, ihdr, trns, plte = 8, [], None, None, None
    while off < len(d):
        ln = struct.unpack(">I", d[off:off + 4])[0]
        typ = d[off + 4:off + 8]
        dat = d[off + 8:off + 8 + ln]
        if typ == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", dat)
        elif typ == b"IDAT":
            idat.append(dat)
        elif typ == b"PLTE":
            plte = dat
        elif typ == b"tRNS":
            trns = dat
        elif typ == b"IEND":
            break
        off += 12 + ln
    w, h, bd, ct, cm, fm, il = ihdr
    if bd != 8 or il != 0:
        raise RuntimeError("PNG non gere (bitdepth=%d interlace=%d): %s" % (bd, il, path))
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(b"".join(idat))
    stride = w * nch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos + stride]); pos += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    alpha = bytearray(w * h)
    if ct == 6:
        for i in range(w * h):
            alpha[i] = out[i * 4 + 3]
    elif ct == 4:
        for i in range(w * h):
            alpha[i] = out[i * 2 + 1]
    elif ct == 3 and trns:
        for i in range(w * h):
            idx = out[i]
            alpha[i] = trns[idx] if idx < len(trns) else 255
    else:
        raise RuntimeError("PNG sans canal alpha, mesure impossible: " + path)
    return w, h, bytes(alpha)


def read_png_alpha(path):
    if not os.path.exists(path):
        raise RuntimeError("atlas absent: " + path)
    try:
        from PIL import Image
        im = Image.open(path).convert("RGBA")
        w, h = im.size
        return w, h, bytes(im.split()[3].tobytes()), "Pillow"
    except ImportError:
        w, h, a = _png_manual(path)
        return w, h, a, "zlib+struct"


# ==========================================================================================
#  *font24-table*  (goal_src/jak1/engine/gfx/font.gc:296)
# ==========================================================================================
def read_font24_table():
    src = open(FONT_GC, encoding="utf-8").read()
    i = src.index("(define *font24-table*")
    j = src.index("\n\n", i)
    rows = [tuple(map(float, m)) for m in re.findall(
        r"new 'static 'vector :x ([-\d.]+) :y ([-\d.]+) :z ([-\d.]+) :w ([-\d.]+)", src[i:j])]
    if len(rows) != 289:
        raise RuntimeError("*font24-table* : %d entrees au lieu de 289" % len(rows))
    return rows


# ==========================================================================================
#  BANQUE DE TEXTE -- re-implementation de convert_utf8_to_game pour jak1-v2.
#  Les tables ne sont PAS recopiees a la main : elles sont analysees dans le .cpp livre.
#     common/util/font/dbs/font_db_jak1.cpp : encode_info_jak1_v2 / replace_info_jak1
#     common/util/font/font_utils.cpp:112-156 : replace_to_game puis encode_utf8_to_game
#     common/util/font/font_utils.cpp:86-92 : jak1 emploie la version V2
# ==========================================================================================
def _strip_cpp_comments(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            out.append(c); i += 1
            while i < n:
                out.append(s[i])
                if s[i] == "\\":
                    i += 1
                    if i < n:
                        out.append(s[i]); i += 1
                    continue
                if s[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            i = s.index("*/", i) + 2
            continue
        out.append(c); i += 1
    return "".join(out)


_HEX = "0123456789abcdefABCDEF"


def _cpp_literal_bytes(lit):
    """Decode un litteral C++ (contenu entre guillemets) en OCTETS, regle \\x gourmande."""
    b = bytearray()
    i, n = 0, len(lit)
    while i < n:
        c = lit[i]
        if c != "\\":
            b.extend(c.encode("utf-8")); i += 1
            continue
        i += 1
        e = lit[i]; i += 1
        if e == "x":
            h = ""
            while i < n and lit[i] in _HEX:
                h += lit[i]; i += 1
            b.append(int(h, 16) & 0xFF)
        elif e == "n":
            b.append(10)
        elif e == "t":
            b.append(9)
        elif e == "r":
            b.append(13)
        elif e == "0":
            b.append(0)
        elif e in ('"', "\\", "'"):
            b.extend(e.encode("utf-8"))
        else:
            raise RuntimeError("echappement C++ non gere: \\" + e)
    return bytes(b)


def _parse_cpp_vector(src, name):
    i = src.index(name)
    i = src.index("{", i)
    depth, j = 0, i
    while True:
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    body = src[i + 1:j]
    entries = []
    for m in re.finditer(r"\{([^{}]*)\}", body):
        lits = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
        if len(lits) >= 2:
            entries.append([_cpp_literal_bytes(x) for x in lits])
    return entries


class Jak1Bank(object):
    def __init__(self):
        src = _strip_cpp_comments(open(FONT_DB, encoding="utf-8").read())
        enc = _parse_cpp_vector(src, "std::vector<EncodeInfo> encode_info_jak1_v2")
        rep = _parse_cpp_vector(src, "std::vector<ReplaceInfo> replace_info_jak1")
        # EncodeInfo{utf8, game_bytes} ; trie encode_to_game keye par utf8 (font_utils.cpp:63)
        self.enc = {}
        for e in enc:
            self.enc[e[0]] = e[1]
        # ReplaceInfo{game_encoding, utf8_string, utf8_alternative} ; trie replace_to_game
        # keye par utf8_string, emet utf8_alternative si non vide sinon game_encoding
        # (font_utils.cpp:66 et 112-130)
        self.rep = {}
        for r in rep:
            self.rep[r[1]] = r[2] if len(r) > 2 and r[2] else r[0]
        self.enc_max = max(len(k) for k in self.enc)
        self.rep_max = max(len(k) for k in self.rep)
        self.n_enc, self.n_rep = len(self.enc), len(self.rep)

    @staticmethod
    def _pass(s, table, kmax):
        out, i, n = bytearray(), 0, len(s)
        while i < n:
            hit = None
            for L in range(min(kmax, n - i), 0, -1):
                k = s[i:i + L]
                if k in table:
                    hit = (k, table[k]); break
            if hit is None:
                out.append(s[i]); i += 1
            else:
                out.extend(hit[1]); i += len(hit[0])
        return bytes(out)

    def convert(self, utf8_text):
        s = utf8_text.encode("utf-8")
        s = self._pass(s, self.rep, self.rep_max)
        return self._pass(s, self.enc, self.enc_max)


# ==========================================================================================
#  MESURE D'ENCRE, par octet et par page
# ==========================================================================================
class Atlas(object):
    def __init__(self, path):
        self.path = path
        self.w, self.h, self.a, self.reader = read_png_alpha(path)

    def cell_ink(self, sx, sy):
        """Boite d'encre d'une cellule, en unites de police relatives au coin haut-gauche."""
        L = sx * self.w
        T = sy * self.h
        WT = ST_W * self.w
        HT = ST_H * self.h
        # texels dont le CENTRE (tx+0.5) tombe dans la fenetre [L, L+WT[ x [T, T+HT[
        x0 = max(0, int(math.ceil(L - 0.5)))
        x1 = min(self.w - 1, int(math.floor(L + WT - 0.5)))
        y0 = max(0, int(math.ceil(T - 0.5)))
        y1 = min(self.h - 1, int(math.floor(T + HT - 0.5)))
        cmin = cmax = rmin = rmax = None
        a = self.a
        for ty in range(y0, y1 + 1):
            base = ty * self.w
            row_hit = False
            for tx in range(x0, x1 + 1):
                if a[base + tx] > ALPHA_MIN:
                    row_hit = True
                    if cmin is None or tx < cmin:
                        cmin = tx
                    if cmax is None or tx > cmax:
                        cmax = tx
            if row_hit:
                if rmin is None:
                    rmin = ty
                rmax = ty
        if cmin is None:
            return None
        return ((cmin - L) / WT * CELL_W_FU,
                (cmax + 1 - L) / WT * CELL_W_FU,
                (rmin - T) / HT * CELL_H_FU,
                (rmax + 1 - T) / HT * CELL_H_FU)


class Font(object):
    def __init__(self):
        self.table = read_font24_table()
        self.lo = Atlas(ATLAS_LO)
        self.hi = Atlas(ATLAS_HI)
        self.cache = {}
        self.snap_worst = 0.0

    def entry(self, idx):
        if idx < 0 or idx >= len(self.table):
            raise RuntimeError("indice de table hors bornes: %d" % idx)
        return self.table[idx]

    def ink(self, idx, page):
        key = (idx, page)
        if key not in self.cache:
            x, y, _z, _w = self.entry(idx)
            at = self.hi if page == "hi" else self.lo
            # residu de calage sur la grille 48 x 64 texels de l'atlas 512x1024, publie
            gx = (x * 512.0 - 2.0) / 48.0
            gy = (y * 1024.0 - 2.0) / 64.0
            self.snap_worst = max(self.snap_worst,
                                  abs(gx - round(gx)) * 48.0, abs(gy - round(gy)) * 64.0)
            self.cache[key] = at.cell_ink(x, y)
        return self.cache[key]

    def adv(self, idx):
        return self.entry(idx)[3]


# ==========================================================================================
#  SIMULATION DE `draw-string` : avance + boite d'encre, en unites de police
# ==========================================================================================
class Layout(object):
    def __init__(self):
        self.adv = 0.0
        self.l = self.r = self.t = self.b = None
        self.glyphs = []
        self.problem = None
        self.newline = False

    def add(self, x, y, box):
        if box is None:
            return
        l, r, t, b = box
        self.l = x + l if self.l is None else min(self.l, x + l)
        self.r = x + r if self.r is None else max(self.r, x + r)
        self.t = y + t if self.t is None else min(self.t, y + t)
        self.b = y + b if self.b is None else max(self.b, y + b)


def layout_string(font, bs, kerning=True):
    """Rejoue `draw-string` sur une chaine DEJA ENCODEE. Retourne un Layout."""
    lay = Layout()
    x = y = 0.0
    sx = sy = 0.0
    i, n = 0, len(bs)
    large = True

    def draw(c_index, page):
        box = font.ink(c_index, page)
        lay.add(x, y, box)
        lay.glyphs.append((c_index, page, x, y, box))

    while i < n:
        c = bs[i]; i += 1
        if c == 0:
            break
        if c == 1:                                   # forme deux octets (font.gc:1567-1571)
            if i >= n:
                break
            b2 = bs[i]; i += 1
            idx = (b2 & 127) + 255 - 16
            page = "hi" if (b2 & 128) else "lo"
            draw(idx, page)
            x += font.adv(idx) * ADV_K if kerning else NOKERN_ADV
            continue
        if c == 0x7E:                                # '~'
            if i >= n:
                break
            e = bs[i]; i += 1
            if e in (0x59, 0x79):                    # Y y : sauve
                sx, sy = x, y
                continue
            if e in (0x5A, 0x7A):                    # Z z : restaure
                x, y = sx, sy
                continue
            sign = e if e in (0x2B, 0x2D) else 0
            if sign or (0x30 <= e <= 0x39):
                val = (e - 0x30) if (0x30 <= e <= 0x39) else 0
                done = False
                while True:
                    if i >= n:
                        done = True; break
                    e = bs[i]; i += 1
                    if 0x30 <= e <= 0x39:
                        val = val * 10 + (e - 0x30); continue
                    if e in (0x6E, 0x4E):            # n N : taille de police
                        if val == 0:
                            lay.problem = "PETITE-POLICE-NON-SUPPORTEE"
                        large = (val != 0)
                        done = True; break
                    if e in (0x6C, 0x4C, 0x77, 0x57, 0x6A, 0x4A):   # l L w W j J
                        done = True; break
                    if e in (0x6B, 0x4B):            # k K : kerning
                        kerning = (val != 0)
                        done = True; break
                    if e in (0x68, 0x48):            # h H : horizontal
                        x = (x + val) if sign == 0x2B else ((x - val) if sign == 0x2D else float(val))
                        done = True; break
                    if e in (0x76, 0x56):            # v V : vertical
                        y = (y + val) if sign == 0x2B else ((y - val) if sign == 0x2D else float(val))
                        done = True; break
                    break                            # lettre inconnue -> dessinee (cfg-122)
                if done:
                    continue
            # ici : `e` est un caractere a dessiner tel quel (cfg-122)
            c = e
        if c in (10, 13):
            lay.newline = True
            x = 0.0
            y += NOKERN_ADV
            continue
        idx = c - 16
        page = "hi" if (c & 128) else "lo"
        draw(idx, page)
        x += font.adv(idx) * ADV_K if kerning else NOKERN_ADV

    lay.adv = x
    if not large:
        lay.problem = "PETITE-POLICE-NON-SUPPORTEE"
    return lay


# ==========================================================================================
#  ENTREES : langues (game_text.gp), textes (json), journal de course
# ==========================================================================================
def read_languages():
    src = open(TEXT_GP, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"\(file-json\s+(\d+)\s+\S+\s+\"\w+\"\s+'\(([^)]*)\)", src):
        lid = int(m.group(1))
        files = re.findall(r'"([^"]+)"', m.group(2))
        for f in files:
            if "game_custom_text_" in f:
                out[lid] = os.path.basename(f).replace("game_custom_text_", "").replace(".json", "")
    return out


def read_texts(langs):
    import json
    out = {}
    for lid, loc in sorted(langs.items()):
        p = os.path.join(TEXT_DIR, "game_custom_text_%s.json" % loc)
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        if TEXT_ID in d:
            out[lid] = (loc, d[TEXT_ID])
    return out


def parse_log(path):
    """Lit le journal en OCTETS (il contient des octets non-ASCII : `grep -a` obligatoire)."""
    res = {"box": None, "textpos": None, "fit": {}, "path": path, "present": False,
           "md5": "", "mtime": 0.0, "size": 0, "age_s": -1.0, "n_box": 0, "n_fit": 0}
    if not path or not os.path.exists(path):
        return res
    res["present"] = True
    data = open(path, "rb").read()
    st = os.stat(path)
    res["md5"] = hashlib.md5(data).hexdigest()
    res["mtime"] = st.st_mtime
    res["size"] = len(data)
    res["age_s"] = time.time() - st.st_mtime
    def kv(line):
        d = {}
        m = re.search(rb"\btexte=", line)
        if m:
            d["texte"] = line[m.end():]
            line = line[:m.start()]
        for k, v in re.findall(rb"([A-Za-z_]+)=([^\s]+)", line):
            d[k.decode("ascii")] = v.decode("ascii", "replace")
        return d
    for line in data.split(b"\n"):
        line = line.rstrip(b"\r")
        if line.startswith(b"CUTHINT-BOX "):
            res["box"] = kv(line)        # un journal peut porter PLUSIEURS courses : la DERNIERE
            res["n_box"] += 1
        elif line.startswith(b"CUTHINT-TEXTPOS "):
            res["textpos"] = kv(line)
        elif line.startswith(b"CUTFIT "):
            d = kv(line)
            res["n_fit"] += 1
            if "langue" in d:
                res["fit"][int(d["langue"])] = d
    return res


# ==========================================================================================
#  GEOMETRIES
# ==========================================================================================
def geom_apres(wr, rys):
    """Geometrie du cycle 2 (cutscene-skip-draw.gc:369-389, 578-582, 656-662)."""
    raw = int(wr + 0.5) + 2 * CS_PAD_X
    bw = 2 * ((raw + 1) // 2)                       # arrondi a la valeur PAIRE superieure
    bh = int(0.5 + (CS_INK_BOT - CS_INK_TOP) * (CS_TEXT_SCALE * rys) + 2.0 * CS_PAD_Y)
    bx = CANVAS_W - CS_MARGIN_X - bw
    by = CANVAS_H - CS_MARGIN_Y - bh
    tx = bx + bw // 2
    ty = int(0.5 + (by + 0.5 * bh) - (0.5 * (CS_INK_TOP + CS_INK_BOT)) * (CS_TEXT_SCALE * rys))
    return bx, by, bw, bh, tx, ty


def geom_avant(wr):
    """Geometrie du cycle 1 (git 86a5f9af44 : lignes 263-265 et 306-309)."""
    bw = int(wr) + 2 * CS_PAD_X                     # TRONCATURE, pas d'arrondi
    bh = CS_BOX_H_C1
    bx = CANVAS_W - CS_MARGIN_X - bw
    by = CANVAS_H - CS_MARGIN_Y - bh
    tx = bx + CS_PAD_X                              # pas de drapeau `middle` : plume = tx
    ty = by + CS_TEXT_DY_C1
    return bx, by, bw, bh, tx, ty


def margins(lay, bx, by, bw, bh, pen_x, pen_y, sx, sy):
    il = pen_x + lay.l * sx
    ir = pen_x + lay.r * sx
    it = pen_y + lay.t * sy
    ib = pen_y + lay.b * sy
    return (il - bx, (bx + bw) - ir, it - by, (by + bh) - ib)


# ==========================================================================================
#  PROGRAMME
# ==========================================================================================
def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    want_glyphs = "--glyphes" in sys.argv[1:]
    log_path = args[0] if args else DEFAULT_LOG
    log = parse_log(log_path)
    simule = not log["present"]
    tag = "GEOMETRIE-SIMULEE-JOURNAL-ABSENT" if simule else "journal"

    font = Font()
    bank = Jak1Bank()
    langs = read_languages()
    texts = read_texts(langs)

    # ---------------- controles de la chaine de mesure ------------------------------------
    print("CUTINK-VERIF atlas_lo=%s %dx%d lecteur=%s" % (
        os.path.relpath(ATLAS_LO, ROOT), font.lo.w, font.lo.h, font.lo.reader))
    print("CUTINK-VERIF atlas_hi=%s %dx%d lecteur=%s" % (
        os.path.relpath(ATLAS_HI, ROOT), font.hi.w, font.hi.h, font.hi.reader))
    print("CUTINK-VERIF seuil_alpha=%d table=289 entrees indice=octet-16 page=bit7" % ALPHA_MIN)
    bt = font.ink(ord("<") - 16, "lo")
    bp = font.ink(ord("p") - 16, "lo")
    ok_ancre = (abs(bt[2] - CS_INK_TOP) < 0.02 and abs(bt[3] - CS_INK_BOT) < 0.02
                and abs(bp[3] - 15.50) < 0.02)
    print("CUTINK-VERIF ancre_bouton haut=%.3f bas=%.3f (attendu %.2f / %.2f) p_bas=%.3f "
          "(attendu 15.50) accord=%d" % (bt[2], bt[3], CS_INK_TOP, CS_INK_BOT, bp[3], 1 if ok_ancre else 0))
    print("CUTINK-VERIF banque=jak1-v2 encode=%d replace=%d residu_grille_texels=%.2f"
          % (bank.n_enc, bank.n_rep, font.snap_worst))
    if log["present"]:
        print("CUTINK-VERIF journal=%s octets=%d md5=%s age_s=%.0f boites=%d "
              "(la DERNIERE est retenue, langue=%s) lignes_cutfit=%d"
              % (log["path"], log["size"], log["md5"], log["age_s"], log["n_box"],
                 (log["box"] or {}).get("langue", "-"), log["n_fit"]))
        if log["age_s"] < 180.0:
            print("CUTINK-JOURNAL-CHAUD le journal a ete ecrit il y a %.0f s : une COURSE EST "
                  "PROBABLEMENT EN VOL et le fichier bouge sous la lecture. Toute valeur "
                  "ci-dessous est a rejeter tant que `CUTINK-JOURNAL-STABLE` ne vaut pas 1."
                  % log["age_s"])
    else:
        print("CUTINK-VERIF journal=%s ABSENT" % log["path"])
    if not ok_ancre:
        print("CUTINK-ARRET la correspondance octet->cellule ne reproduit pas les constantes "
              "livrees CS_INK_TOP/CS_INK_BOT/p : AUCUNE mesure publiee.")
        return 2

    # ---------------- encodage : JSON confronte aux octets du jeu -------------------------
    encoded, mismatch, checked = {}, 0, 0
    for lid, (loc, txt) in sorted(texts.items()):
        bs = bank.convert(txt)
        src_txt = "json"
        if lid in log["fit"] and "texte" in log["fit"][lid]:
            checked += 1
            ref = log["fit"][lid]["texte"]
            if ref != bs:
                mismatch += 1
                print("CUTINK-DESACCORD langue=%d %s json=%s journal=%s"
                      % (lid, loc, bs.hex(), ref.hex()))
                bs = ref
                src_txt = "journal"
        encoded[lid] = (loc, txt, bs, src_txt)
    print("CUTINK-VERIF encodage=json_vs_journal compares=%d desaccords=%d%s"
          % (checked, mismatch,
             "" if checked else "  (NON CONFRONTE : aucune ligne CUTFIT lisible dans le journal)"))

    # ---------------- rxs et rys ---------------------------------------------------------
    rxs = None
    if log["box"] is None and log["fit"]:
        any_fit = sorted(log["fit"].items())[0][1]
        rxs = float(any_fit.get("rxs", "1.0"))
    elif log["fit"]:
        any_fit = sorted(log["fit"].items())[0][1]
        rxs = float(any_fit.get("rxs", "1.0"))
    if rxs is None:
        rxs = 1.0
    rys = DEFAULT_RYS
    sx = CS_TEXT_SCALE * rxs
    sy = CS_TEXT_SCALE * rys

    run_lang = int(log["box"]["langue"]) if (log["box"] and "langue" in log["box"]) else None

    # ---------------- glyphes ------------------------------------------------------------
    used = {}
    lays = {}
    for lid, (loc, txt, bs, src_txt) in sorted(encoded.items()):
        lay = layout_string(font, bs)
        lays[lid] = lay
        for (idx, page, gx, gy, box) in lay.glyphs:
            used[(idx, page)] = box
    if want_glyphs:
        for (idx, page), box in sorted(used.items()):
            c = idx + 16
            nm = chr(c) if 32 <= c < 127 else "0x%02x" % c
            if box is None:
                print("CUTINK-GLYPHE octet=0x%02x page=%s nom=%s encre=aucune avance=%.4f"
                      % (c & 0xFF, page, nm, font.adv(idx)))
            else:
                print("CUTINK-GLYPHE octet=0x%02x page=%s nom=%s g=%.3f d=%.3f h=%.3f b=%.3f avance=%.4f"
                      % (c & 0xFF, page, nm, box[0], box[1], box[2], box[3], font.adv(idx)))
    else:
        for ch in "<@>[":
            box = font.ink(ord(ch) - 16, "lo")
            print("CUTINK-GLYPHE octet=0x%02x page=lo nom=%s g=%.3f d=%.3f h=%.3f b=%.3f avance=%.4f"
                  % (ord(ch), ch, box[0], box[1], box[2], box[3], font.adv(ord(ch) - 16)))

    # ---------------- verdicts par langue ------------------------------------------------
    lines = []
    worst_h = (-1.0, None)
    worst_v = (-1.0, None)
    avant_rows = []
    for lid, (loc, txt, bs, src_txt) in sorted(encoded.items()):
        lay = lays[lid]
        if lay.problem or lay.l is None:
            print("CUTCENTER-LANG langue=%d NON-MESUREE raison=%s texte=%s"
                  % (lid, lay.problem or "aucune-encre", txt))
            continue
        wr_calc = lay.adv * sx
        # geometrie : le journal d'abord, la simulation sinon
        bx, by, bw, bh, tx, ty = geom_apres(wr_calc, rys)
        src_geo = tag
        if lid in log["fit"]:
            f = log["fit"][lid]
            wr_log = int(f["largeur_texte_millu"]) / 1000.0
            bw_log = int(f["largeur_cartouche"])
            bh_log = int(f["hauteur_cartouche"])
            if abs(wr_log - wr_calc) > 0.002:
                print("CUTINK-DESACCORD langue=%d avance journal=%.3f calcul=%.3f"
                      % (lid, wr_log, wr_calc))
            wr_calc = wr_log
            bx, by, bw, bh, tx, ty = geom_apres(wr_calc, rys)
            if bw != bw_log or bh != bh_log:
                print("CUTINK-DESACCORD langue=%d cartouche journal=%dx%d calcul=%dx%d"
                      % (lid, bw_log, bh_log, bw, bh))
                bw, bh = bw_log, bh_log
                bx = CANVAS_W - CS_MARGIN_X - bw
                by = CANVAS_H - CS_MARGIN_Y - bh
                tx = bx + bw // 2
        if run_lang is not None and lid == run_lang and log["box"]:
            b = log["box"]
            bx, by, bw, bh = int(b["x"]), int(b["y"]), int(b["w"]), int(b["h"])
            if log["textpos"]:
                tx, ty = int(log["textpos"]["tx"]), int(log["textpos"]["ty"])
            elif "tx" in b:
                tx, ty = int(b["tx"]), int(b["ty"])
        pen_x = tx - wr_calc / 2.0            # drapeau `middle`
        pen_y = float(ty)
        mg, md, mh, mb = margins(lay, bx, by, bw, bh, pen_x, pen_y, sx, sy)
        lines.append((lid, loc, mg, md, mh, mb, txt, src_geo))
        if abs(mg - md) > worst_h[0]:
            worst_h = (abs(mg - md), (lid, loc, mg, md))
        if abs(mh - mb) > worst_v[0]:
            worst_v = (abs(mh - mb), (lid, loc, mh, mb))
        # controle : la meme mesure sur la geometrie du CYCLE 1
        bx1, by1, bw1, bh1, tx1, ty1 = geom_avant(wr_calc)
        mg1, md1, mh1, mb1 = margins(lay, bx1, by1, bw1, bh1, float(tx1), float(ty1), sx, sy)
        avant_rows.append((lid, loc, mg1, md1, mh1, mb1))

    # ---------------- sortie -------------------------------------------------------------
    if run_lang is None and lines:
        run_lang = lines[0][0]
    head = [r for r in lines if r[0] == run_lang]
    if head:
        lid, loc, mg, md, mh, mb, txt, src_geo = head[0]
        print("CUTCENTER marge_g=%.3f marge_d=%.3f marge_h=%.3f marge_b=%.3f metrique=encre "
              "langue=%d rxs=%.4f rys=%.4f source=%s" % (mg, md, mh, mb, lid, rxs, rys, src_geo))
    for lid, loc, mg, md, mh, mb, txt, src_geo in lines:
        print("CUTCENTER-LANG langue=%d nom=%s marge_g=%.3f marge_d=%.3f marge_h=%.3f "
              "marge_b=%.3f source=%s texte=%s" % (lid, loc, mg, md, mh, mb, src_geo, txt))
    av = [r for r in avant_rows if r[0] == run_lang] or avant_rows[:1]
    if av:
        lid, loc, mg1, md1, mh1, mb1 = av[0]
        print("CUTCENTER-AVANT marge_g=%.3f marge_d=%.3f marge_h=%.3f marge_b=%.3f "
              "metrique=encre langue=%d source=%s" % (mg1, md1, mh1, mb1, lid, "cycle1-reconstruit"))
    pire_av_v = max((abs(r[4] - r[5]) for r in avant_rows), default=0.0)
    pire_av_h = max((abs(r[2] - r[3]) for r in avant_rows), default=0.0)
    print("CUTCENTER-CONTROLE pire_ecart_vertical_avant=%.3f pire_ecart_vertical_apres=%.3f "
          "pire_ecart_horizontal_avant=%.3f instrument_discriminant=%d"
          % (pire_av_v, worst_v[0], pire_av_h, 1 if pire_av_v >= 2.0 else 0))
    if pire_av_v < 2.0:
        print("CUTCENTER-CONTROLE-ALERTE la geometrie du cycle 1 rend un ecart haut/bas de %.3f "
              "unite seulement : l'instrument ne discrimine pas, NE PAS croire les lignes "
              "ci-dessus." % pire_av_v)
    if worst_h[1]:
        lid, loc, mg, md = worst_h[1]
        print("CUTCENTER-PIRE axe=horizontal ecart=%.3f langue=%d nom=%s marge_g=%.3f marge_d=%.3f"
              % (worst_h[0], lid, loc, mg, md))
    if worst_v[1]:
        lid, loc, mh, mb = worst_v[1]
        print("CUTCENTER-PIRE axe=vertical ecart=%.3f langue=%d nom=%s marge_h=%.3f marge_b=%.3f"
              % (worst_v[0], lid, loc, mh, mb))
    stable = 1
    if log["present"]:
        try:
            after = hashlib.md5(open(log["path"], "rb").read()).hexdigest()
        except OSError:
            after = ""
        stable = 1 if after == log["md5"] else 0
        print("CUTINK-JOURNAL-STABLE %d md5_avant=%s md5_apres=%s"
              % (stable, log["md5"], after))
        if not stable:
            print("CUTINK-JOURNAL-INSTABLE le journal a CHANGE pendant la mesure : les ancres "
                  "lues ne decrivent aucune course entiere. RIEN de ce qui precede ne compte, "
                  "relancer une fois la course terminee.")
    print("CUTCENTER-VERDICT langues=%d horizontal_sous_1u=%d vertical_sous_1u=%d source=%s journal_stable=%d"
          % (len(lines), 1 if worst_h[0] < 1.0 else 0, 1 if worst_v[0] < 1.0 else 0, tag, stable))
    if simule:
        print("CUTCENTER-VERDICT-RESERVE journal absent (%s) : toutes les lignes ci-dessus sont "
              "en GEOMETRIE SIMULEE, aucune ancre n'a ete lue sur une course." % log_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
