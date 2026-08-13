#!/usr/bin/env python3
"""Per-joint MAJORITY skin ownership along each physics chain, on a shipped mesh.

WHY THIS EXISTS (2026-08-13). `subdiv` gave backhair/lmidhair/rmidhair a fourth joint; the solver
moves it (`PHYSBONE c=2 l=3 len=258.0191`, no NaN) and the ring-down changed. But on the delivered
mesh NO VERTEX followed the new tip: the bone existed and the geometry ignored it. No coverage
profile showed this — a profile answers "how much of this strand is driven by its chain", and the
answer stayed ~0.85 while the whole strand hung off ONE joint of the four.

THE THREE QUESTIONS (SPEC 7), answered before the number is published:
  NATURE  : a DISTRIBUTION of skin along the chain — which joint each vertex actually follows.
            Not an amplitude, not a mean: a mean cannot tell 0/0/124/0 from 94/9/10/36, and those
            are the rejected and the approved sample.
  REPERE  : the vertex belongs to the joint holding the MAJORITY of its weight (w > 0.5). Same
            `WMIN` criterion physics_c14_meshsamples.py uses to decide which vertices a link
            carries, so a link reading 0 here is exactly a link with no `ms` samples.
  ABSENT  : `lbang`/`rbang`, measured on the SAME mesh in the same run. The owner approves the fine
            strands and rejects the big ones, so the good and the bad sample sit side by side.

Measure the PREPPED+RESKINNED mesh that ships (out/jak1/fr3/skin/<model>-lod0.glb), never the donor
rip: the donor is a LEVEL rip whose vertex pool holds other objects.

Usage:  python3 .autoport/probe_skin_ownership.py <glb> [<glb-to-compare-against>]
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info  # noqa: E402

CHAINS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           '..', 'recharged_assets', 'physics_chains.txt')
MAJORITY = 0.5


def parse_chains(path):
    """(chain name -> [joint names]) straight from the shipped chain file, never hand-listed."""
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


def ownership(path, chains):
    js, bufs = read_glb(path)
    binc = consolidate_buffers(js, bufs)
    names, _, _ = skin_info(js, binc)
    idx = {n: i for i, n in enumerate(names)}
    prim = js['meshes'][0]['primitives'][0]
    J = read_accessor(js, binc, prim['attributes']['JOINTS_0'])
    W = read_accessor(js, binc, prim['attributes']['WEIGHTS_0'])
    out = {}
    for cname, joints in chains.items():
        row = []
        for jn in joints:
            if jn not in idx:
                row.append(None)          # a joint absent from THIS mesh is declared, not hidden
                continue
            ji = idx[jn]
            w = np.zeros(len(W))
            for c in range(J.shape[1]):
                w += np.where(J[:, c] == ji, W[:, c], 0.0)
            row.append(int((w > MAJORITY).sum()))
        out[cname] = (joints, row)
    return out


def fmt(row):
    return " ".join("    --" if v is None else "%6d" % v for v in row)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    chains = parse_chains(CHAINS_FILE)
    cur = ownership(sys.argv[1], chains)
    ref = ownership(sys.argv[2], chains) if len(sys.argv) > 2 else None

    print("SOMMETS DONT LE JOINT EST MAJORITAIRE (w > %.2f) — mesh : %s" % (MAJORITY, sys.argv[1]))
    print("NATURE repartition de la peau le long de la chaine · REPERE majorite de poids par sommet")
    print("LIGNE DE BASE lbang/rbang, meme mesh (l'owner approuve les fines, rejette les grosses)")
    if ref:
        print("COMPARE A : %s   (avant -> apres)" % sys.argv[2])
    print()
    print("%-14s %s" % ("chaine", "  racine  ->  pointe"))
    for cname in sorted(cur):
        joints, row = cur[cname]
        if len(joints) < 2:
            continue
        line = "%-14s %s" % (cname, fmt(row))
        if ref and cname in ref:
            old = ref[cname][1]
            if old != row:
                line += "   (etait %s)" % fmt(old).strip()
        print(line)
        orphans = [j for j, v in zip(joints, row) if v == 0]
        if orphans:
            print("%-14s   ^ %d joint(s) sans AUCUN sommet majoritaire : %s"
                  % ("", len(orphans), ", ".join(orphans)))
    print()
    print("LECTURE : un joint a 0 est un os que le solveur bouge et que la geometrie ignore.")
    print("Un maillon a 0 porte aussi zero echantillon `ms` dans physics_mesh.txt (meme seuil),")
    print("donc sa peau n'existe ni pour la collision ni pour le rendu du mouvement.")


if __name__ == '__main__':
    main()
