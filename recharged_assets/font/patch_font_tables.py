#!/usr/bin/env python3
"""Rebranche la colonne d'AVANCE de `*font12-table*` / `*font24-table*` sur Urbanist.

Les coordonnees UV (x, y) ne bougent PAS : l'atlas est genere sur la grille du moteur,
donc la grille reste celle du jeu. Ce qui change est la 4e composante `w`, l'avance,
qui doit suivre la nouvelle chasse des glyphes — sinon le texte se chevauche ou s'espace.

  avance ecran = w * size1-small.w (0.5)  en petite police
               = w * size1-large.w (1.0)  en grande police

Seules les entrees 0..111 (octets 0x10..0x7f) sont touchees : au-dela, la table sert les
octets >= 0x80, qui vivent dans les atlas `hi` (kana) que l'on ne remplace pas.

Idempotent : la reference livree est figee dans stock-tables.json par gen_game_atlas.py.
"""
import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONTGC = os.path.join(ROOT, "goal_src", "jak1", "engine", "gfx", "font.gc")
TABLES = os.path.join(os.path.dirname(__file__), "urbanist-tables.json")


def fmt(v):
    s = "%g" % v
    return s if "." in s or "e" in s else s + ".0"


def main():
    tab = json.load(open(TABLES))
    src = open(FONTGC, encoding="utf-8").read()
    total = 0
    for name, key in (("font12-table", "w_font12"), ("font24-table", "w_font24")):
        i = src.index("(define *%s*" % name)
        d = 0
        for j in range(i, len(src)):
            if src[j] == "(":
                d += 1
            elif src[j] == ")":
                d -= 1
                if d == 0:
                    end = j + 1
                    break
        blk = src[i:end]
        ws = tab[key]
        n = [0, 0]

        def fix(m):
            idx = n[0]
            n[0] += 1
            code = idx + 16
            if code > 0x7F:
                return m.group(0)
            body = m.group(1)
            new = fmt(ws[str(code)])
            n[1] += 1
            if re.search(r":w [-0-9.]+", body):
                body = re.sub(r":w [-0-9.]+", ":w " + new, body)
            else:
                body = body.rstrip() + " :w " + new
            return "(new 'static 'vector" + body + ")"

        blk = re.sub(r"\(new 'static 'vector([^)]*)\)", fix, blk)
        print("%s : %d entrees, %d avances rebranchees" % (name, n[0], n[1]))
        total += n[1]
        src = src[:i] + blk + src[end:]
    open(FONTGC, "w").write(src)
    print("total %d" % total)


if __name__ == "__main__":
    main()
