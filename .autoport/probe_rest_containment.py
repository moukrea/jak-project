#!/usr/bin/env python3
"""probe_rest_containment.py — LE VOLUME RECLAME-T-IL LA PLACE QUE LE MODELE OCCUPE DEJA ?

Ce script ne genere rien et ne modifie rien. Il lit `recharged_assets/physics_chains.txt` (le fichier
LIVRE) et le mesh/rig d'ou il a ete derive, et repond a UNE question, hors moteur et hors build :

    pour chaque couple (maillon de chaine, volume de collision), le maillon est-il DEJA a
    l'interieur de ce volume dans la POSE DE BIND DU MODELE ?

POURQUOI CETTE QUESTION. La course du 2026-08-13 publie des compteurs SATURES :

    ROOM-CONTACT-VOL: chain=chestL  total=271  Rshoulder->chest 90 · Lshoulder->chest 90 · neck->chest 63
    ROOM-CONTACT-VOL: chain=kneeflapL total=180  Lankle->Lknee 90 · Lknee->Lthigh 90
    ROOM-CONTACT-VOL: chain=backhair total=439  head->neck 180 · ...

`chestL` n'a qu'UN maillon. Un volume qui lui demande une correction sur 90 echantillons sur 90 ne
le garde pas : il le POUSSE en permanence. L'en-tete du tableau le dit deja pour un autre
instrument : « Un mur qui mord des milliers de fois n'est pas un garde-fou, c'est le regime de
fonctionnement ; aucun reglage de raideur, de masse ou de couplage ne deplace un lien plaque contre
une butee dure. »

Un volume ajuste par UN rayon p95 sur un joint qui possede une partie du corps allongee ou
irreguliere SUR-COUVRE dans toutes les directions sauf celle qui a fixe le rayon. La tete est
ajustee a 915 u (22 cm de RAYON) parce que sa geometrie va jusqu'au sommet du crane ; ce meme rayon
s'applique donc aussi VERS L'ARRIERE, la ou sont les cheveux de nuque.

LES TROIS QUESTIONS DE LA SPEC 7, REPONDUES AVANT D'ECRIRE LA MESURE :

  NATURE  : une DISTANCE SIGNEE (jeu radial), en unites de jeu, dans la pose de bind. Ce n'est ni
            une variance ni une amplitude : le defaut vise est un etat STATIQUE du modele au repos.
            Negatif = le maillon est DEDANS au repos.
  REPERE  : celui du volume lui-meme (distance a son axe pour une capsule, a son centre pour une
            sphere), pose de bind du modele. Aucun repere monde anime n'intervient : la pose de bind
            est la seule pose que le modele possede sans animation.
  ABSENT  : pour un volume bien forme, la valeur est POSITIVE (le maillon est dehors au repos). Un
            volume dont le jeu est negatif reclame une place que le modele occupe deja.

CONTROLE INTEGRE (le zero doit pouvoir tirer) : le script verifie d'abord qu'il sait replacer un
joint a partir de sa matrice inverse-bind — `P[j]` recalcule depuis l'ibm doit retomber sur `P[j]`
livre par le mesh. Si ce controle ne passe pas, tout le reste est faux et le script s'arrete.
"""
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402

UNITS = G.UNITS
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')


# ------------------------------------------------------------------------------------------------
# LECTURE DU FICHIER LIVRE — on mesure ce qui est LIVRE, jamais ce que le generateur croit produire.
# ------------------------------------------------------------------------------------------------
def parse_chains(path):
    chains, capsules, spheres = [], [], []
    cur = None
    for raw in open(path):
        line = raw.strip()
        if not line or line.startswith('#') or line.startswith('['):
            continue
        tok = line.split()
        if tok[0] == 'chain':
            kv = dict(t.split('=', 1) for t in tok[2:] if '=' in t)
            radii = [float(x) for x in kv['radii'].split(',')] if 'radii' in kv else []
            cur = dict(name=tok[1], joints=[], radii=radii,
                       radius=float(kv.get('radius', 0.0)),
                       rootlock=int(kv.get('rootlock', 0)))
            chains.append(cur)
        elif tok[0] == 'j' and cur is not None:
            cur['joints'].append(tok[1])
        elif tok[0] == 'capsule':
            kv = dict(t.split('=', 1) for t in tok[3:] if '=' in t)
            capsules.append(dict(a=tok[1], b=tok[2],
                                 ra=float(kv['radius']), rb=float(kv['radius2'])))
        elif tok[0] == 'collider':
            kv = dict(t.split('=', 1) for t in tok[2:] if '=' in t)
            off = [float(x) for x in kv.get('offset', '0,0,0').split(',')]
            spheres.append(dict(j=tok[1], r=float(kv['radius']), off=np.array(off, dtype=float)))
    return chains, capsules, spheres


# ------------------------------------------------------------------------------------------------
# GEOMETRIE — pose de bind uniquement.
# ------------------------------------------------------------------------------------------------
def bind_frame(ibm):
    """(Rn, tn) tels que  local = world @ Rn.T + tn  — l'echelle d'os retiree, exactement comme
    `to_bone_local` du generateur (4 joints de bretelle portent une echelle de 9.68)."""
    R = ibm[:3, :3]
    s = np.linalg.norm(R, axis=1)
    s = np.where(s < 1e-12, 1.0, s)
    return R / s[:, None], (ibm[:3, 3] * UNITS) / s


def local_to_world(Rn, tn, local):
    return (np.asarray(local, dtype=float) - tn) @ Rn


def seg_clearance(p, a, b, ra, rb):
    """Jeu radial SIGNE entre le point `p` et la capsule (a,b,ra,rb) : distance a l'axe moins le
    rayon interpole au parametre le plus proche. Negatif = dedans."""
    ab = b - a
    L2 = float(ab @ ab)
    t = 0.0 if L2 <= 1e-9 else float(np.clip(((p - a) @ ab) / L2, 0.0, 1.0))
    q = a + t * ab
    return float(np.linalg.norm(p - q) - (ra + t * (rb - ra)))


def main():
    rig_path = os.path.join(REPO, G.RIG_REL)
    names, parent, _ = G.load_rig(rig_path)
    geo = G.load_mesh(G.MODEL)
    P, ibms = geo['P'], geo['ibms']
    idx = {n: k for k, n in enumerate(geo['names'])}

    out = []
    def say(s=''):
        out.append(s)
        print(s)

    # -- CONTROLE POSITIF DU REPERE ---------------------------------------------------------------
    # Si je ne sais pas replacer un joint depuis son ibm, toute distance ci-dessous est fausse.
    worst, worstj = 0.0, None
    for n, k in idx.items():
        if k >= len(ibms):
            continue
        Rn, tn = bind_frame(ibms[k])
        d = float(np.linalg.norm(local_to_world(Rn, tn, [0.0, 0.0, 0.0]) - P[k]))
        if d > worst:
            worst, worstj = d, n
    say(f"CONTROLE-REPERE: pire ecart de replacement d'un joint depuis son ibm = {worst:.4f} u "
        f"(joint {worstj}) sur {len(ibms)} joints")
    if worst > 1.0:
        say("CONTROLE-REPERE: ECHEC — le repere de bind n'est pas reconstruit, rien d'autre ne vaut.")
        return 2
    say()

    chains, capsules, spheres = parse_chains(CHAINS)
    say(f"LU: {len(chains)} chaines, {len(capsules)} capsules, {len(spheres)} spheres "
        f"depuis {os.path.relpath(CHAINS, REPO)}")
    say()

    # centre monde de chaque sphere, en pose de bind
    for s in spheres:
        k = idx[s['j']]
        Rn, tn = bind_frame(ibms[k])
        s['c'] = local_to_world(Rn, tn, s['off'])
        s['owner'] = None
    # a quelle chaine appartient chaque sphere / capsule (exclusion structurelle chaine<->elle-meme)
    jset = {c['name']: set(c['joints']) for c in chains}
    for s in spheres:
        for c in chains:
            if s['j'] in jset[c['name']]:
                s['owner'] = c['name']
    for cp in capsules:
        cp['owner'] = None
        for c in chains:
            if cp['a'] in jset[c['name']] and cp['b'] in jset[c['name']]:
                cp['owner'] = c['name']

    say("REST-IN: jeu radial du maillon a chaque volume, POSE DE BIND. Negatif = le maillon est")
    say("         DEJA dedans quand le modele est au repos, donc le volume le pousse des la")
    say("         premiere frame et a toutes les suivantes. `self` = volume porte par la chaine")
    say("         elle-meme (exclu structurellement par le moteur), montre pour memoire.")
    say()
    say(f"{'chaine':<13}{'maillon':<15}{'r_lien':>7}  {'volume':<26}{'jeu_u':>9}{'jeu_m':>9}  self")
    say('-' * 96)

    # LE VOLUME QUE LE MAILLON PRESENTE, EXACTEMENT COMME LE MOTEUR LE CONSTRUIT.
    # `jak-hd-physics.gc:1032-1042` : par defaut `*phys-lcr*` = le rayon de chaine et `*phys-lcx*` =
    # 0 ; MAIS si le joint du maillon porte un `collider`, les deux sont REMPLACES par le rayon et
    # le decalage de ce collider. Mesurer le maillon a son joint avec `radii=` est donc faux des
    # qu'un collider existe : pour `lBoob` cela donnait -1023 u (25 cm enterres) la ou le moteur
    # voit -57 u. C'est la difference entre un defaut grave et un contact marginal.
    byj0 = {s['j']: s for s in spheres}
    rows = []
    for c in chains:
        for i, jn in enumerate(c['joints']):
            if jn not in idx:
                continue
            # le maillon 0 d'une chaine rootlock est soude a l'os porteur: il ne se deplace pas,
            # donc un volume qui le contient ne produit pas de mouvement. Il reste mesure et marque.
            if jn in byj0:
                p = byj0[jn]['c']
                rlink = byj0[jn]['r']
            else:
                p = P[idx[jn]]
                rlink = c['radii'][i] if i < len(c['radii']) else c['radius']
            for cp in capsules:
                if cp['a'] not in idx or cp['b'] not in idx:
                    continue
                cl = seg_clearance(p, P[idx[cp['a']]], P[idx[cp['b']]], cp['ra'], cp['rb']) - rlink
                own = (cp['owner'] == c['name']) or (cp['a'] in jset[c['name']]) or (cp['b'] in jset[c['name']])
                rows.append((c['name'], jn, i, rlink, f"{cp['a']}->{cp['b']}", cl, own,
                             c['rootlock'] and i == 0))
            for s in spheres:
                cl = float(np.linalg.norm(p - s['c']) - s['r']) - rlink
                own = (s['owner'] == c['name']) or (s['j'] in jset[c['name']])
                rows.append((c['name'], jn, i, rlink, f"sphere:{s['j']}", cl, own,
                             c['rootlock'] and i == 0))

    inside = [r for r in rows if r[5] < 0.0]
    inside.sort(key=lambda r: r[5])
    for (ch, jn, i, rl, vol, cl, own, rl0) in inside:
        say(f"{ch:<13}{jn:<15}{rl:>7.0f}  {vol:<26}{cl:>9.1f}{cl / UNITS:>9.3f}  "
            f"{'self' if own else ''}{' rootlocked' if rl0 else ''}")

    say()
    # -- LA MEME MESURE, MAIS AVEC L'AUTRE REPRESENTATION DU MAILLON ------------------------------
    # Un maillon dont le joint porte un `collider` existe sous DEUX descriptions dans le fichier
    # livre : (a) le joint + le rayon de lien `radii=`, (b) le centre decale + le rayon du collider.
    # Pour `lBoob` : (a) = joint + 656 u, (b) = centre a 662 u du joint + 322 u. Les deux ne disent
    # pas la meme chose du tout, et je ne sais pas encore laquelle le moteur presente aux volumes du
    # corps. Je publie donc LES DEUX : la conclusion ne doit pas dependre de ma supposition.
    say("REST-IN-B: la meme distance, le maillon decrit cette fois par le collider que son joint")
    say("           porte (centre decale + rayon du collider) au lieu de (joint + rayon de lien).")
    say(f"{'chaine':<13}{'maillon':<15}{'volume':<26}{'A:joint+rlien':>15}{'B:collider':>13}")
    say('-' * 82)
    byj = {s['j']: s for s in spheres}
    for c in chains:
        for i, jn in enumerate(c['joints']):
            if jn not in idx or jn not in byj:
                continue
            s = byj[jn]
            rlink = c['radii'][i] if i < len(c['radii']) else c['radius']
            for cp in capsules:
                if cp['a'] not in idx or cp['b'] not in idx:
                    continue
                if cp['a'] in jset[c['name']] or cp['b'] in jset[c['name']]:
                    continue
                a, b = P[idx[cp['a']]], P[idx[cp['b']]]
                ca = seg_clearance(P[idx[jn]], a, b, cp['ra'], cp['rb']) - rlink
                cb = seg_clearance(s['c'], a, b, cp['ra'], cp['rb']) - s['r']
                if min(ca, cb) < 0.0:
                    say(f"{c['name']:<13}{jn:<15}{cp['a'] + '->' + cp['b']:<26}"
                        f"{ca:>15.1f}{cb:>13.1f}")
    say()
    ext = [r for r in inside if not r[6] and not r[7]]
    say(f"BILAN: {len(inside)} couples (maillon, volume) se recouvrent au REPOS ; "
        f"{len(ext)} apres retrait des volumes de la chaine elle-meme et des maillons soudes.")
    say()
    say("PAR CHAINE — profondeur de recouvrement au repos la PIRE, volumes etrangers seulement :")
    per = {}
    for r in ext:
        if r[0] not in per or r[5] < per[r[0]][5]:
            per[r[0]] = r
    for ch in sorted(per, key=lambda k: per[k][5]):
        r = per[ch]
        say(f"  REST-IN-WORST: chain={ch:<13} link={r[1]:<15} vol={r[4]:<24} "
            f"jeu={r[5]:>8.1f} u = {r[5] / UNITS:>7.3f} m")
    say()
    clean = sorted(c['name'] for c in chains if c['name'] not in per)
    say(f"CHAINES SANS AUCUN RECOUVREMENT AU REPOS ({len(clean)}) : {' '.join(clean) or '(aucune)'}")

    dest = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion',
                        'rest-containment.txt')
    open(dest, 'w').write('\n'.join(out) + '\n')
    print(f"\n[ecrit] {os.path.relpath(dest, REPO)}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
