#!/usr/bin/env python3
"""Phase Gtext-tone — lit une banque `*COMMON.TXT` DEJA CONSTRUITE et en publie, par id :
la chaine REELLE et sa LARGEUR RENDUE.

POURQUOI CET OUTIL EXISTE
-------------------------
Le dossier a paye le piege de l'artefact perime : l'APK a livre pendant 17 jours une COPIE
GELEE du texte (commit a137796a4a) — PC juste, telephone faux, MEME commit. Lire le JSON
source ne prouve donc rien sur ce que le programme utilise. Cet outil lit les OCTETS que le
jeu chargera, jamais la source.

DEUX MESURES, SUR LES MEMES OCTETS
----------------------------------
1. `--dump`  : id -> chaine, decodee depuis la banque binaire.
2. `--width` : largeur rendue, en reproduisant `get-string-length`
   (`goal_src/jak1/engine/gfx/font.gc:1531`) sur ces memes octets.

FORMAT DE LA BANQUE (goalc/data_compiler/game_text_common.cpp:54-82,
DataObjectGenerator.cpp:121-148, common/link_types.h:43-47)
  0x00 type_tag u32 (0xFFFFFFFF) · 0x04 length u32 (= offset du debut de la section DATA)
  0x08 version u32 (= 2)         · 0x0C..length table de liens (ignoree en lecture)
  DATA (mots LE 32 bits, offsets relatifs au debut de DATA) :
    mot0 tag de type · mot1 nombre d'entrees · mot2 language-id · mot3 ptr "common"
    puis n paires (id u32, ptr u32). Un ptr est un offset EN OCTETS depuis le debut de DATA
    et vise le champ `length` d'une `string` : les octets utiles commencent a ptr+4, NUL final.

DECODAGE : LA REGLE QUI EVITE LES KANJI
---------------------------------------
`encode_info_jak1_v2` (common/util/font/dbs/font_db_jak1.cpp:443) revendique 0x5c-0x7d pour
des KANJI. Or l'encodeur laisse passer les minuscules ASCII telles quelles
(`encode_utf8_to_game`, common/util/font/font_utils.cpp) : decoder une banque OCCIDENTALE
avec la table entiere rend « P出行闇闇 » au lieu de « Press ». Regle appliquee ici pour les
langues 0-4 et 6 : la table ne sert que pour octet < 0x20 ou octet >= 0x7F ; 0x20-0x7E est de
l'ASCII. La langue 5 (ja-JP) exige la table entiere — elle est donc decodee autrement.

LARGEUR : CE QUI EST MODELISE ET CE QUI NE L'EST PAS
----------------------------------------------------
Modelise fidelement : ~Y/~Z (pile de plume), ~+nH/~-nH/~nH (deplacements), ~nN (bascule de
police), ~kK (kerning), ~L ~W ~J ~V (avance nulle), et le cas de repli — une lettre d'echappement
non reconnue (`~D`) avance de la chasse de CETTE lettre, exactement comme font.gc:1616-1625.
NON modelise : l'octet 0x03 (`_`, l'espace large des chaines Sony `MEMORY_CARD_(PS2)`). Son
index de table est 3-16 = -13, une lecture HORS BORNES que font.gc fait reellement ; on lui
donne la valeur nominale W_UNDERSCORE. Toutes les chaines de ce lot gardent le MEME nombre de
`_` avant et apres, donc cette approximation s'annule exactement dans le DELTA publie.

BUDGET DE BOITE : la condition de tenue sur une ligne est
    somme(chasses) <= width / relative-x-scale
`relative-x-scale` vaut 1.0 en 4:3 et 0.75 en 16:9 (goal_src/jak1/engine/gfx/hw/video.gc:66-69),
donc une boite `width=352` offre 352 en 4:3 et 469.33 en 16:9.
"""
import argparse
import json
import os
import re
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FONT_GC = os.path.join(ROOT, "goal_src", "jak1", "engine", "gfx", "font.gc")
FONT_DB = os.path.join(ROOT, "common", "util", "font", "dbs", "font_db_jak1.cpp")
W_UNDERSCORE = 24.0   # octet 0x03, index -13 : lecture hors bornes, valeur nominale


# ---------------------------------------------------------------------------------------
# Tables de chasse, lues dans font.gc — la SOURCE que le moteur compile, pas une copie
# ---------------------------------------------------------------------------------------
def load_advance_tables():
    src = open(FONT_GC, encoding="utf-8").read()
    out = {}
    for name in ("*font12-table*", "*font24-table*"):
        i = src.index("(define %s" % name)
        j = src.index("(define ", i + 10) if src.find("(define ", i + 10) > 0 else len(src)
        out[name] = [float(w) for w in re.findall(r":w\s+(-?[\d.]+)\)", src[i:j])]
    return out["*font12-table*"], out["*font24-table*"]


# ---------------------------------------------------------------------------------------
# Tables d'encodage / de remplacement, lues dans font_db_jak1.cpp
# ---------------------------------------------------------------------------------------
def cunescape(lit):
    """Deplie un litteral C -> octets. `unicode_escape` de Python ne sait pas lire `\\x1`
    (un seul chiffre hexa), que font_db_jak1.cpp emploie sur 35 entrees japonaises."""
    out, i, n = bytearray(), 0, len(lit)
    while i < n:
        ch = lit[i]
        if ch != "\\":
            out += ch.encode("utf-8")
            i += 1
            continue
        i += 1
        if i >= n:
            break
        e = lit[i]
        i += 1
        if e == "x":                       # \xH ou \xHH : 1 ou 2 chiffres, comme en C
            h = ""
            while i < n and len(h) < 2 and lit[i] in "0123456789abcdefABCDEF":
                h += lit[i]
                i += 1
            out.append(int(h, 16) if h else 0)
        else:
            out += {"n": b"\n", "t": b"\t", "r": b"\r", "0": b"\x00",
                    "\\": b"\\", '"': b'"', "'": b"'"}.get(e, e.encode("utf-8"))
    return bytes(out)


def load_font_db():
    src = open(FONT_DB, encoding="utf-8").read()

    def block(varname):
        i = src.index(varname)
        depth, j, started = 0, i, False
        while j < len(src):
            if src[j] == "{":
                depth += 1
                started = True
            elif src[j] == "}":
                depth -= 1
                if started and depth == 0:
                    return src[i:j + 1]
            j += 1
        return src[i:]

    pair = re.compile(r'\{\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\}')

    enc = {}   # octet de jeu -> texte utf8
    for utf8, gamebytes in pair.findall(block("encode_info_jak1_v2")):
        raw = cunescape(gamebytes)
        if len(raw) == 1:
            enc.setdefault(raw[0], cunescape(utf8).decode("utf-8", "replace"))

    rep = []   # (sequence de jeu, texte utf8) -- les plus longues d'abord
    for gameseq, utf8 in pair.findall(block("replace_info_jak1")):
        g = cunescape(gameseq).decode("latin-1")
        u = cunescape(utf8).decode("utf-8", "replace")
        rep.append((g, u))
    rep.sort(key=lambda t: -len(t[0]))
    return enc, rep


# ---------------------------------------------------------------------------------------
# Lecture de la banque
# ---------------------------------------------------------------------------------------
def read_bank(path):
    blob = open(path, "rb").read()
    tag, length, version = struct.unpack_from("<III", blob, 0)
    if version != 2:
        raise SystemExit("%s : version d'objet %d, attendu 2" % (path, version))
    data = blob[length:]
    _typ, n, lang, _grp = struct.unpack_from("<IIII", data, 0)
    entries = {}
    for k in range(n):
        ident, ptr = struct.unpack_from("<II", data, 16 + 8 * k)
        end = data.index(b"\x00", ptr + 4)
        entries["%x" % ident] = data[ptr + 4:end]
    return lang, entries


def decode(raw, lang, enc, rep):
    if lang == 5:                       # ja-JP : la table entiere s'applique
        s = "".join(enc.get(b, chr(b)) for b in raw)
    else:                               # 0x20-0x7E est de l'ASCII, pas des kanji
        s = "".join(chr(b) if 0x20 <= b <= 0x7E else enc.get(b, "\\x%02x" % b) for b in raw)
    for g, u in rep:                    # ~Y~22L<~Z... -> <PAD_CIRCLE> ; e~Y~-14H... -> é
        s = s.replace(g, u)
    return s


# ---------------------------------------------------------------------------------------
# Largeur — transcription de get-string-length (font.gc:1531-1630)
# ---------------------------------------------------------------------------------------
def width(raw, t12, t24, large=True, kerning=True):
    table = t24 if large else t12
    size1 = 1.0 if large else 0.5
    size2 = 16.0 if large else 8.0
    pen, saved, i, n = 0.0, 0.0, 0, len(raw)

    def adv(code):
        if code == 3:
            return W_UNDERSCORE
        idx = code - 16
        return table[idx] * size1 if 0 <= idx < len(table) else 0.0

    while i < n:
        c = raw[i]
        i += 1
        if c == 0x7E:                                   # '~'
            if i >= n:
                break
            c = raw[i]
            i += 1
            if c in (0x59, 0x79):                       # ~Y ~y : sauve la plume
                saved = pen
                continue
            if c in (0x5A, 0x7A):                       # ~Z ~z : restaure la plume
                pen = saved
                continue
            sign = c if c in (0x2B, 0x2D) else 0
            val = 0
            if sign or (0x30 <= c <= 0x39):
                while True:
                    if i >= n:
                        return pen
                    c = raw[i]
                    i += 1
                    if c in (0x6E, 0x4E):               # ~nN : bascule de police
                        large = val != 0
                        table = t24 if large else t12
                        size1 = 1.0 if large else 0.5
                        size2 = 16.0 if large else 8.0
                        break
                    if c in (0x6C, 0x4C, 0x77, 0x57, 0x6A, 0x4A, 0x76, 0x56):  # ~L ~W ~J ~V
                        break
                    if c in (0x6B, 0x4B):               # ~kK : kerning
                        kerning = val != 0
                        break
                    if c in (0x68, 0x48):               # ~nH : plume
                        pen = float(val) if not sign else (pen - val if sign == 0x2D else pen + val)
                        break
                    if 0x30 <= c <= 0x39:
                        val = val * 10 + (c - 0x30)
                        continue
                    # lettre d'echappement inconnue (~D) : elle AVANCE, font.gc:1616-1625
                    pen += adv(c) if kerning else size2
                    break
                continue
            # ~D et consorts sans chiffre devant : meme repli
            pen += adv(c) if kerning else size2
            continue
        if c in (10, 13):                               # retour a la ligne : plume a l'origine
            pen = 0.0
            continue
        pen += adv(c) if kerning else size2
    return pen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bank")
    ap.add_argument("--ids", default=None, help="liste d'ids hex separes par des virgules")
    ap.add_argument("--small", action="store_true", help="mesurer en PETITE police")
    ap.add_argument("--budget", type=float, default=None, help="largeur de boite a comparer")
    ap.add_argument("--xscale", type=float, default=1.0, help="relative-x-scale (1.0=4:3, 0.75=16:9)")
    a = ap.parse_args()

    t12, t24 = load_advance_tables()
    enc, rep = load_font_db()
    lang, entries = read_bank(a.bank)
    ids = [x.strip().lower().lstrip("0") or "0" for x in a.ids.split(",")] if a.ids else sorted(entries, key=lambda k: int(k, 16))

    print("# %s  lang=%d  entrees=%d  (police %s, xscale=%.2f)"
          % (a.bank, lang, len(entries), "PETITE" if a.small else "GRANDE", a.xscale))
    if a.budget:
        print("# budget de boite : width=%.0f / xscale=%.2f = %.2f unites" % (a.budget, a.xscale, a.budget / a.xscale))
    for ident in ids:
        raw = entries.get(ident)
        if raw is None:
            print("  #x%-5s ABSENT DE LA BANQUE" % ident)
            continue
        w = width(raw, t12, t24, large=not a.small)
        s = decode(raw, lang, enc, rep)
        verdict = ""
        if a.budget:
            budget = a.budget / a.xscale
            verdict = "  TIENT" if w <= budget else "  DEBORDE (+%.2f)" % (w - budget)
        print("  #x%-5s w=%8.2f%s  %s" % (ident, w, verdict, s))


if __name__ == "__main__":
    main()
