#!/usr/bin/env python3
"""lib/scope_from_commits.py — LE PERIMETRE D'UN ITEM, DERIVE DE CE QU'IL A REELLEMENT LIVRE.

POURQUOI (signalement 8 du 12/09). `code_scope` fait foi depuis le 12/09 : GATE 1 le lit avant
tout le reste, et sans lui la porte DEVINE le perimetre dans la prose de l'item — six tournures
francaises reconnues, le reste passe en « perimetre muet » et la porte redemande du code. La
mesure du matin rendait `vd_live_scope_explicit=0` sur 228 items. Le champ ne peut donc pas etre
rempli a la main pour tout le monde : le remplir en DEVINANT ne ferait que blanchir la devinette
qu'on veut voir.

CE QUE CE MODULE FAIT, ET CE QU'IL REFUSE DE FAIRE. Il ne lit aucune prose. Il lit les COMMITS
de l'item — ceux dont le sujet porte `[autoport/<id>]` — et regarde QUEL TERRITOIRE ils ont
touche. Un item qui a livre du `game/ common/ android/ goal_src/ goalc/` a, de fait, un
perimetre moteur : c'est une grandeur, pas une lecture de phrase. Un item qui n'a touche que
`.autoport/` a un perimetre de harnais. Tout le reste — aucun commit, ou des commits hors de ces
deux territoires — reste MUET et est NOMME : on ne devine pas, on dit qui on n'a pas su classer.

Usage :  python3 lib/scope_from_commits.py [--ecrire]
Sans `--ecrire`, il n'ecrit rien : il publie `cle=valeur`, et c'est tout.
"""
from __future__ import annotations

import collections
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent

# LES DEUX TERRITOIRES. Celui du moteur est celui que l'orchestrateur nomme deja dans
# `engine_prefixes()` ; on le recopie ici a la lettre plutot que d'importer l'orchestrateur, qui
# bouge tous les jours et dont l'import a des effets de bord.
MOTEUR = ("game/", "common/", "android/", "goal_src/", "goalc/")
HARNAIS = (".autoport/",)


def commits_par_item(ids):
    """{id: {territoire: set(chemins), 'n': nb de commits}} — lu du journal, pas de la prose."""
    out = collections.defaultdict(lambda: {"moteur": set(), "harnais": set(),
                                           "autre": set(), "n": 0})
    try:
        journal = subprocess.run(
            ["git", "-C", str(REPO), "log", "--all", "--name-only",
             "--pretty=format:@@%H %s"],
            capture_output=True, text=True, errors="replace", timeout=600).stdout
    except (OSError, subprocess.SubprocessError):
        return out
    courant = None
    for ligne in journal.splitlines():
        if ligne.startswith("@@"):
            m = re.search(r"\[autoport/([A-Za-z0-9._-]+)\]", ligne)
            courant = m.group(1) if m and m.group(1) in ids else None
            if courant:
                out[courant]["n"] += 1
            continue
        chemin = ligne.strip()
        if not courant or not chemin:
            continue
        if chemin.startswith(HARNAIS):
            out[courant]["harnais"].add(chemin)
        elif chemin.startswith(MOTEUR):
            out[courant]["moteur"].add(chemin)
        else:
            out[courant]["autre"].add(chemin)
    return out


def decider(t):
    """Le perimetre MESURE, ou `("", raison)` quand rien ne le tranche sans deviner."""
    if not t or t["n"] == 0:
        return "", "aucun-commit"
    if t["moteur"]:
        return "jeu", "a-livre-du-moteur:%d" % len(t["moteur"])
    if t["harnais"] and not t["autre"]:
        return "harnais", "n-a-touche-que-le-harnais:%d" % len(t["harnais"])
    return "", "commits-hors-des-deux-territoires:%d" % len(t["autre"])


def main(argv):
    ecrire = "--ecrire" in argv
    sys.path.insert(0, str(AP / "lib"))
    import backlog as B                                             # noqa: E402
    bk = B.load()
    ids = {it.get("id") for it in bk.items if it.get("id")}
    mesure = commits_par_item(ids)

    pose, muets, deja = [], [], []
    for it in bk.items:
        iid = it.get("id")
        if not iid:
            continue
        if it.get("code_scope"):
            deja.append(iid)
            continue
        scope, raison = decider(mesure.get(iid))
        if scope:
            pose.append((iid, scope, raison))
        else:
            muets.append((iid, raison))

    if ecrire:
        poses_ok = 0
        for iid, scope, raison in pose:
            try:
                bk.set_scope(iid, scope, source="commits:%s" % raison)
                poses_ok += 1
            except Exception as exc:                                # noqa: BLE001
                print("scope_ecriture_echec_%s=%s" % (iid, type(exc).__name__))
        print("scope_ecrits=%d" % poses_ok)

    print("scope_total=%d" % len(ids))
    print("scope_deja_explicite=%d" % len(deja))
    print("scope_mesurables=%d" % len(pose))
    print("scope_mesurables_jeu=%d" % sum(1 for _i, s, _r in pose if s == "jeu"))
    print("scope_mesurables_harnais=%d" % sum(1 for _i, s, _r in pose if s == "harnais"))
    print("scope_muets=%d" % len(muets))
    # LES MUETS SONT NOMMES, PAS COMPTES EN SILENCE : un item dont le perimetre reste devine
    # doit pouvoir etre tranche par un humain, et pour ca il faut le lire.
    par_raison = collections.Counter(r for _i, r in muets)
    for raison, n in sorted(par_raison.items()):
        print("scope_muets_%s=%d" % (re.sub(r"[^a-z0-9]+", "_", raison.split(":")[0]), n))
    print("scope_muets_liste=%s" % (",".join(i for i, _r in muets[:60]) or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
