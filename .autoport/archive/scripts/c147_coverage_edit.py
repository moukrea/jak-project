#!/usr/bin/env python3
"""c147_coverage_edit.py — pose le paragraphe d'un cycle dans SPEC-COVERAGE.md.

Le registre est un ETAT : on PREPEND le paragraphe du cycle dans la colonne `Preuve` des sections
touchees, et on insere la ligne d'etat en tete de tableau. Les blocs viennent d'un fichier separe
par des lignes `@@ <cle>` : `ETAT`, puis `S<NN>` par section.

DEFAUT PAYE ET CORRIGE ICI (cycle 147) : un `split('|')` naif coupe la ligne de §21 en plein
milieu de sa citation, parce que la colonne « ce que la section exige » contient des barres
ECHAPPEES (`\\|D_linear + D_angular\\|`). On ne decoupe donc que sur les barres NON ECHAPPEES.
La table avait ete ecrite cassee une fois ; elle a ete restauree depuis git avant d'etre reecrite.
"""
import io, re, sys

COV = ".autoport/SPEC-COVERAGE.md"
SRC = sys.argv[1] if len(sys.argv) > 1 else ".autoport/c147-coverage.txt"
ANCHOR = sys.argv[2] if len(sys.argv) > 2 else "**ETAT AU CYCLE 145 (2026-08-28)**"

blocks, key, buf = {}, None, []
for line in io.open(SRC, encoding="utf-8"):
    m = re.match(r'^@@ (\S+)\s*$', line)
    if m:
        if key: blocks[key] = "".join(buf).strip()
        key, buf = m.group(1), []
    else:
        buf.append(line)
if key: blocks[key] = "".join(buf).strip()

txt = io.open(COV, encoding="utf-8").read()
if "ETAT" in blocks:
    assert txt.count(ANCHOR) == 1, "ancre d'etat introuvable ou multiple"
    txt = txt.replace(ANCHOR, blocks["ETAT"] + "\n\n" + ANCHOR, 1)
    print("ETAT insere")

UNESC = re.compile(r'(?<!\\)\|')
out, todo = [], {int(k[1:]) for k in blocks if k.startswith("S")}
for line in txt.split("\n"):
    m = re.match(r'^\|\s*(\d+)\s*\|', line)
    if m and int(m.group(1)) in todo:
        n = int(m.group(1))
        pos = [mm.start() for mm in UNESC.finditer(line)]
        assert len(pos) >= 5, "ligne §%d : seulement %d barres non echappees" % (n, len(pos))
        cut = pos[3] + 1
        line = line[:cut] + " " + blocks["S%d" % n] + " " + line[cut:].lstrip()
        todo.discard(n)
        print("§%d ok" % n)
    out.append(line)
assert not todo, "sections non trouvees : %s" % todo
io.open(COV, "w", encoding="utf-8").write("\n".join(out))
print("ecrit", COV)
