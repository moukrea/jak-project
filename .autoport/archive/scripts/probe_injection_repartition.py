#!/usr/bin/env python3
"""probe_injection_repartition.py — LA PREUVE QU'UN OS INJECTE PILOTE DE LA CHAIR.

CONTRAT (DIRECTIVES 2026-08-18 08:55, troisieme rappel du meme mode d'echec) :
  « une injection d'os n'existe QUE si le repesage l'accompagne dans la MEME passe, et la preuve
    est la REPARTITION, jamais la presence. Preuve exigee : au moins 30 % des sommets de la chaine
    ont le NOUVEL os pour joint majoritaire (w > 0.5) [...] Publier systematiquement le tableau
    `os / poids total / sommets majoritaires` — c'est la seule grandeur qui discrimine `os present`
    de `os qui pilote`. »

LES TROIS QUESTIONS (SPEC 7), repondues avant d'ecrire le chiffre :
  NATURE  : une REPARTITION — combien de sommets chaque os de la chaine possede en MAJORITE.
            Ni une somme (`cov` vaut 0.85 quand tout pend d'un seul joint), ni une presence.
  REPERE  : le sommet appartient a l'os qui detient la majorite de son poids (w > 0.5), meme
            critere `WMIN` que `physics_c14_meshsamples.py` — un os a 0 ici a zero echantillon
            `ms`, donc sa peau n'existe ni pour la collision ni pour le mouvement.
  ABSENT  : un os injecte sans repesage lit exactement 0. C'est l'etat des cycles 16 et 23.

ET LE PIEGE QUE CETTE SONDE REND IMPOSSIBLE — il a coute TROIS constats faux en six jours.
La cuisson enchaine : inject -> `<char>-donor-injected.glb` -> stamp -> prep -> RESKIN ->
`out/jak1/fr3/skin/<char>-lod0.glb` -> merc swap. **`-donor-injected.glb` est le PREMIER maillon,
en amont du repesage.** Une sonde de repartition pointee dessus lit `0` sur tout os injecte PAR
CONSTRUCTION, pour toujours, quoi que fasse le repesage. Cette sonde REFUSE donc de rendre un
verdict sur un intermediaire : elle le nomme, dit ce qu'il est, et exige `--intermediaire` pour
l'afficher — et meme alors elle l'affiche A COTE du mesh livre, jamais seul.

USAGE :
  python3 .autoport/probe_injection_repartition.py                  # mesh livre (defaut)
  python3 .autoport/probe_injection_repartition.py --intermediaire  # + la colonne d'amont
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info  # noqa: E402
import physics_keira_gen2 as G                                                          # noqa: E402

CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
SHIPPED = os.path.join(REPO, 'out', 'jak1', 'fr3', 'skin', 'keira-hd-lod0.glb')
INTERMEDIATE = os.path.join(REPO, 'out', 'jak1', 'fr3', 'skin', 'keira-hd-donor-injected.glb')
MAJORITY = 0.5
GATE = G.INFL_GATE
BAR = 0.30              # 30 `StrongRootFraction = 0.30`, repris par la directive du 08:55

# Les os INJECTES, lus dans le fichier de specification d'injection — jamais listes a la main.
INJECT_SPEC = os.path.join(REPO, 'recharged_assets', 'keira-hd-inject-joints.txt')


def injected_joints():
    """Les joints que la specification d'injection cree (verbes `append`, `subdiv`, `reroot`)."""
    new = set()
    for ln in open(INJECT_SPEC, errors='ignore'):
        ln = ln.split('#', 1)[0].split()
        if not ln:
            continue
        if ln[0] == 'subdiv' and len(ln) >= 4:
            new.add(ln[3])
        elif ln[0] == 'reroot':
            continue                     # `reroot` DEPLACE un joint existant, il n'en cree aucun
        elif len(ln) >= 3:
            new.add(ln[2])               # forme `chaine parent nouveau x y z`
    return new


def parse_chains(path):
    out, cur = {}, None
    for ln in open(path, errors='ignore'):
        ln = ln.split('#', 1)[0].strip()
        if ln.startswith('chain '):
            cur = ln.split()[1]
            out[cur] = []
        elif ln.startswith('j ') and cur:
            out[cur].append(ln.split()[1])
        elif not ln:
            cur = None
    return {k: v for k, v in out.items() if v}


def measure(path, chains):
    js, bufs = read_glb(path)
    binc = consolidate_buffers(js, bufs)
    names, _, _ = skin_info(js, binc)
    idx = {n: i for i, n in enumerate(names)}
    prim = js['meshes'][0]['primitives'][0]
    J = read_accessor(js, binc, prim['attributes']['JOINTS_0'])
    W = read_accessor(js, binc, prim['attributes']['WEIGHTS_0'])

    def wof(ji):
        w = np.zeros(len(W))
        for c in range(J.shape[1]):
            w += np.where(J[:, c] == ji, W[:, c], 0.0)
        return w

    out = {}
    for cname, joints in chains.items():
        grp = [idx[j] for j in joints if j in idx]
        if not grp:
            out[cname] = None
            continue
        ws = np.zeros(len(W))
        for g in grp:
            ws += wof(g)
        cloud = np.flatnonzero(ws > GATE)                 # le nuage de la chaine (meme def. que 30)
        rows = []
        for jn in joints:
            if jn not in idx:
                rows.append((jn, None, None))
                continue
            w = wof(idx[jn])
            rows.append((jn, float(w.sum()), int((w[cloud] > MAJORITY).sum())))
        out[cname] = (rows, len(cloud))
    return out


def main():
    show_int = '--intermediaire' in sys.argv
    chains = parse_chains(CHAINS)
    new = injected_joints()
    cur = measure(SHIPPED, chains)
    ref = measure(INTERMEDIATE, chains) if show_int else None

    print("REPARTITION DE LA PEAU PAR OS — la preuve qu'un os injecte PILOTE (directive 08:55)")
    print("NATURE repartition (sommets possedes en MAJORITE) · REPERE w > %.2f par sommet" % MAJORITY)
    print("ABSENT un os injecte sans repesage lit 0 — etat des cycles 16 et 23")
    print()
    print("MESH LU        : %s" % os.path.relpath(SHIPPED, REPO))
    print("  NATURE       : LE MESH LIVRE — sortie de prep + RESKIN, c'est lui que le jeu recoit.")
    if show_int:
        print("MESH COMPARE   : %s" % os.path.relpath(INTERMEDIATE, REPO))
        print("  NATURE       : INTERMEDIAIRE d'AMONT (sortie de l'injecteur, AVANT stamp/prep/reskin).")
        print("                 Tout os injecte y lit 0 PAR CONSTRUCTION : le repesage n'a pas encore")
        print("                 eu lieu. Aucun verdict ne se tire de cette colonne.")
    print()
    hdr = "%-8s %-10s %12s %10s %8s" % ("chaine", "os", "poids total", "sommets maj", "part")
    if show_int:
        hdr += " %14s" % "amont (maj)"
    print(hdr)
    print("-" * len(hdr))
    verdicts = []
    for cname in sorted(cur):
        d = cur[cname]
        if d is None:
            print("%-8s  ABSENT du mesh" % cname)
            continue
        rows, ncloud = d
        for jn, tot, maj in rows:
            tag = " *" if jn in new else "  "
            part = "" if maj is None else "%6.1f%%" % (100.0 * maj / max(1, ncloud))
            line = "%-8s %-10s %12s %10s %8s" % (
                cname, jn + tag,
                "--" if tot is None else "%.3f" % tot,
                "--" if maj is None else "%d" % maj, part)
            if show_int:
                r = ref.get(cname)
                rm = "--"
                if r:
                    for jn2, _t2, m2 in r[0]:
                        if jn2 == jn:
                            rm = "--" if m2 is None else "%d" % m2
                line += " %14s" % rm
            print(line)
            if jn in new and maj is not None:
                verdicts.append((cname, jn, maj, ncloud, maj / max(1, ncloud)))
        print("%-8s nuage de la chaine : %d sommets (poids somme chaine > %.2f)"
              % ("", ncloud, GATE))
    print()
    print("* = os INJECTE par %s" % os.path.relpath(INJECT_SPEC, REPO))
    print()
    print("VERDICT — barre du contrat : le NOUVEL os majoritaire sur >= %.0f %% du nuage" % (100 * BAR))
    bad = 0
    for cname, jn, maj, ncloud, f in verdicts:
        ok = f >= BAR
        bad += 0 if ok else 1
        print("  %-8s %-10s %3d / %3d = %5.1f %%   %s"
              % (cname, jn, maj, ncloud, 100 * f, "TENU" if ok else "NON TENU — injection NON FAITE"))
    if not verdicts:
        print("  aucun os injecte dans les chaines declarees")
    raise SystemExit(1 if bad else 0)


if __name__ == '__main__':
    main()
