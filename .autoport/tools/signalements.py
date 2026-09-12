#!/usr/bin/env python3
"""Les chantiers nes d'un signalement de worker, et ou ils en sont.

POURQUOI CE FICHIER. Owner, 2026-09-12, sur la question « la porte des signalements, je l'arme en
bloquant ou elle continue d'alerter ? » : « trouve le meilleur moyen, sachant que j'imagine etre
celui qui doit trancher la dessus, mais faut me le remonter ».

Donc : la porte reste en ALERTE — bloquer une fermeture pour un signalement non trie arreterait le
harnais sur une question qui n'appartient pas au worker. Mais ce qu'un signalement est devenu doit
remonter a l'owner SANS qu'il ait a lire un digest. Ce script le dit en une commande.

LECTURE SEULE. Il n'ecrit rien, ne juge rien, et n'est la source de verdict d'aucun item.

    python3 .autoport/tools/signalements.py            # les ouverts, par priorite
    python3 .autoport/tools/signalements.py --tous     # avec ceux deja fermes
"""
from __future__ import annotations

import os
import sys

AP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(AP, "lib"))
import backlog as B  # noqa: E402

MARQUEUR = "signalement"     # « issu du signalement », « issu des sept signalements », ...
# Le mot entier, pas « issu d » : « issu du PLAN » n'est pas un signalement de worker,
# et hdr-output-regime remontait a tort pour cette raison le 2026-09-12.
OUVERTS = ("open", "blocked", "in-progress", "to-test")


def main(argv) -> int:
    tous = "--tous" in argv
    bl = B.load()
    nes = [x for x in bl.items if MARQUEUR in (x.get("notes") or "")]
    if not tous:
        nes = [x for x in nes if x.get("status") in OUVERTS]
    if not nes:
        print("Aucun chantier ne d'un signalement n'est en attente.")
        return 0

    nes.sort(key=lambda x: (x.get("priority") or 10 ** 6, x.get("id", "")))
    print("## Nes d'un signalement de worker — %d chantier(s)" % len(nes))
    print("Chacun existe parce qu'un worker a trouve quelque chose HORS de son perimetre.")
    print("C'est a l'owner de dire lesquels valent le coup ; le harnais ne les priorise pas seul.\n")
    for x in nes:
        print("p%-3s  %-44s %s" % (x.get("priority"), x.get("id"), x.get("status")))
        f = (x.get("feature") or "").strip()
        if f:
            print("      %s" % f[:96])
    print("\nDetail d'un chantier : ./.autoport/autoport show <id>")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
