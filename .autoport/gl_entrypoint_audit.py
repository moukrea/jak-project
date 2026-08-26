#!/usr/bin/env python3
"""gl_entrypoint_audit.py — enumere les entrees GL que glad NE CHARGERA PAS sur Android.

POURQUOI CE SCRIPT EXISTE
-------------------------
glad classe chaque pointeur d'entree GL par VERSION DE GL DE BUREAU
(`load_GL_VERSION_x_y`), et ne charge une liste que si la version detectee est
au moins la sienne. Sur Android le contexte est GLES : `glGetString(GL_VERSION)`
rend « OpenGL ES 3.2 ... », glad le lit comme 3.2, et saute donc INTEGRALEMENT
toutes ses listes au-dessus de 3.2. Une entree qui est CORE en GLES mais rangee
par glad dans une de ces listes (glClearDepthf, glVertexAttribDivisor,
glTexStorage2D, ...) reste NULL — et son premier appel est un BLR vers 0, donc
un signal 11 avec pc=0.

Ce mode de defaillance a ete paye TROIS FOIS, une entree a la fois. Le correctif
durable est au PRODUCTEUR : `android/android_gfx.cpp` resout explicitement,
juste apres `gladLoadGLLoader`, toutes les entrees listees ici. Ce script est
l'instrument qui dit CE QU'IL FAUT Y METTRE, au lieu de l'apprendre par un
crash.

USAGE
-----
    python3 .autoport/gl_entrypoint_audit.py            # rapport lisible
    python3 .autoport/gl_entrypoint_audit.py --check    # sortie 1 si une entree
                                                        # manque dans android_gfx.cpp

NATURE / REPERE DE LA MESURE (regle des trois questions)
--------------------------------------------------------
Nature   : un ENSEMBLE de noms de symboles, pas une amplitude.
Repere   : le texte source de l'arbre (statique), pas l'execution.
Sans defaut, il lit : ensemble vide de « non couvertes ».
"""

import argparse
import collections
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLAD_C = os.path.join(ROOT, "third-party", "glad", "src", "glad.c")
ANDROID_GFX = os.path.join(ROOT, "android", "android_gfx.cpp")
SCAN_DIRS = ["game", "common", "android"]

# La version que glad DEDUIT du contexte GLES d'Android. Tout ce qui est range
# au-dessus n'est jamais charge.
PARSED_ES_VERSION = (3, 2)


def glad_owner_table():
    """{nom du symbole GL: nom de la fonction load_* de glad qui le charge}"""
    owner = {}
    cur = None
    with open(GLAD_C, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"static void (load_\w+)\(GLADloadproc load\)", line)
            if m:
                cur = m.group(1)
                continue
            m = re.search(r'glad_(gl\w+)\s*=\s*\(PFN\w+PROC\)load\("(\w+)"\)', line)
            if m and cur:
                owner[m.group(2)] = cur
    return owner


def list_rank(load_fn):
    """(major, minor) pour une liste de version, None pour une liste d'extension."""
    m = re.match(r"load_GL_VERSION_(\d+)_(\d+)$", load_fn)
    return (int(m.group(1)), int(m.group(2))) if m else None


def used_symbols():
    used = set()
    for root in SCAN_DIRS:
        base = os.path.join(ROOT, root)
        for dirpath, _dirnames, filenames in os.walk(base):
            if "third-party" in dirpath:
                continue
            for fn in filenames:
                if not fn.endswith((".cpp", ".c", ".h", ".hpp")):
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    with open(path, encoding="utf-8", errors="replace") as f:
                        text = f.read()
                except OSError:
                    continue
                for m in re.finditer(r"\bgl[A-Z]\w*", text):
                    used.add(m.group(0))
    return used


def covered_in_android_gfx():
    """Symboles deja resolus a la main dans le balayage d'android_gfx.cpp."""
    try:
        with open(ANDROID_GFX, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return set()
    return set(re.findall(r'\{\(void\*\*\)&glad_(gl\w+),\s*"(?:gl\w+)"\}', text))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="sortie 1 si une entree gatee n'est pas couverte")
    args = ap.parse_args()

    owner = glad_owner_table()
    used = used_symbols()
    covered = covered_in_android_gfx()

    gated = collections.defaultdict(list)
    for sym in sorted(used):
        load_fn = owner.get(sym)
        if not load_fn:
            continue  # pas une entree chargee par glad (macro, enum, ...)
        rank = list_rank(load_fn)
        if rank is None or rank > PARSED_ES_VERSION:
            gated[load_fn].append(sym)

    all_gated = sorted(s for syms in gated.values() for s in syms)
    missing = [s for s in all_gated if s not in covered]

    print(f"glad: {len(owner)} entrees GL chargees par version")
    print(f"arbre: {len(used)} symboles gl* references sous {', '.join(SCAN_DIRS)}")
    print(f"version deduite par glad sur GLES: {PARSED_ES_VERSION[0]}.{PARSED_ES_VERSION[1]}")
    print()
    print("=== entrees UTILISEES que glad range AU-DESSUS de la version deduite ===")
    for load_fn in sorted(gated):
        for sym in gated[load_fn]:
            mark = "ok " if sym in covered else "NON COUVERTE"
            print(f"  [{mark}] {sym:32s} {load_fn}")
    print()
    if missing:
        print("NON COUVERTES par le balayage d'android/android_gfx.cpp :")
        for sym in missing:
            print(f"  - {sym}")
        print("Chacune est un appel-vers-0 qui attend son premier appelant.")
    else:
        print("Toutes les entrees gatees sont couvertes par android/android_gfx.cpp.")

    if args.check and missing:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
