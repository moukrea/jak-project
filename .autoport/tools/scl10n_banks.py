#!/usr/bin/env python3
"""Relit les `<n>COMMON.TXT` LIVRES (out/jak1/iso) exactement comme
`game/system/settings_case_l10n.cpp:read_bank`, et applique les memes juges.

Outil de labo. Aucune porte ne le lit : la porte est `proof.txt`, ecrit par le moteur.
Il sert a savoir, SANS relancer une course, ce qu'un elargissement du recensement
compterait.
"""
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scl10n_check as C  # noqa: E402

ISO = os.path.join(ROOT, "out", "jak1", "iso")


def read_bank(path):
    with open(path, "rb") as f:
        d = f.read()
    if len(d) < 12:
        return None
    tag, ln, ver = struct.unpack_from("<III", d, 0)
    if ver != 2 or ln < 12 or ln >= len(d):
        return None
    body = ln
    count, lang = struct.unpack_from("<I", d, body + 4)[0], struct.unpack_from("<I", d, body + 8)[0]
    if count > 100000:
        return None
    lines = {}
    for i in range(count):
        tid, ref = struct.unpack_from("<II", d, body + 16 + 8 * i)
        if ref == 0 or body + ref + 4 > len(d):
            continue
        start = body + ref + 4
        end = d.index(b"\0", start)
        lines[tid] = d[start:end].decode("latin-1")
    return lang, lines


def all_banks():
    out = {}
    for lang in range(0, 33):
        p = os.path.join(ISO, "%dCOMMON.TXT" % lang)
        if not os.path.exists(p):
            continue
        r = read_bank(p)
        if r and r[0] == lang and r[1]:
            out[lang] = r[1]
    return out


def translated(banks):
    """Meme mesure que le C++ : une langue est traduite si elle differe de l'anglais
    sur plus de la moitie des entrees stock partagees."""
    en = banks.get(0, {})
    res = set()
    for lang, b in banks.items():
        if lang == 0:
            continue
        common = diff = 0
        for tid, line in b.items():
            if tid >= 0x1700:
                continue
            e = en.get(tid)
            if not e or not line:
                continue
            common += 1
            if line != e:
                diff += 1
        if common >= 50 and diff * 2 > common:
            res.add(lang)
    return res


def audit(ids):
    banks = all_banks()
    tr = translated(banks)
    en = banks.get(0, {})
    caps, missing, same = [], [], []
    for tid in ids:
        e = en.get(tid, "")
        for lang, b in sorted(banks.items()):
            s = b.get(tid)
            if s is None:
                if lang in tr:
                    missing.append((tid, lang))
                continue
            if C.shouting(s):
                caps.append((tid, lang, s))
            if lang in tr and e and s == e and not C.language_neutral(e):
                same.append((tid, lang, s))
    return banks, tr, caps, missing, same


if __name__ == "__main__":
    ids = [int(a, 16) for a in sys.argv[1:]]
    banks, tr, caps, missing, same = audit(ids)
    print("langs=%d translated=%d" % (len(banks), len(tr)))
    for tid, lang, s in caps:
        print("caps   %04x @%-2d %r" % (tid, lang, s))
    for tid, lang in missing:
        print("missing %04x @%-2d" % (tid, lang))
    for tid, lang, s in same:
        print("same   %04x @%-2d %r" % (tid, lang, s))
    print("---- caps=%d missing=%d same=%d" % (len(caps), len(missing), len(same)))
