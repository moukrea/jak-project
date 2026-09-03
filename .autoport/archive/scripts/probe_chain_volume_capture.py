#!/usr/bin/env python3
"""probe_chain_volume_capture.py — QUELLE CHAINE EST ENFERMEE DANS QUEL VOLUME, ET DE COMBIEN ?

D'OU VIENT LA QUESTION. La course de la salle compte `contact_frames` par chaine
(reports/Grecharged-secondary-motion/keira-room-table.C22-B.txt) : six chaines sont a
17893/17893, soit 100 % des frames en contact — `backhair`, `lbang`, `rbang`, `chestL`,
`chestR`, `kneeflapR`, `pantflapL`... quand `earL` en compte 25 et `lmidhair` 609. Une
chaine qui ne quitte JAMAIS un volume n'est plus posee par sa dynamique mais par la
resolution de collision : pour `backhair` c'est deja prouve en forme close par
`probe_head_volume_selfinclusion.py` (portee 820 u contre un rayon de capsule de 915 u) et
verifie par la course (multiplier par 1.89 la reponse de son ressort deplace son angle de
0.1 %). Ce script generalise la preuve a TOUTES les chaines contre TOUS les volumes.

NATURE de la grandeur : une MARGE D'EVASION, en unites de jeu (4096 u = 1 m). Ce n'est ni
une variance ni une amplitude : c'est la plus grande distance dont le volume porte par un
maillon peut depasser la surface d'un obstacle, prise sur TOUT ce que ce maillon peut
atteindre. Elle repond a une question binaire — « sortir est-il seulement possible ? » —
pas a « bouge-t-il ».

REPERE : le monde, a la POSE DE BIND du rig (`geo['P']`, les positions issues des matrices
inverse-bind du GLB, en unites de jeu), qui est le repere ou le generateur mesure ses rayons
et ou le moteur pose ses volumes quand aucune animation ne joue.

LECTURE QUAND LE DEFAUT EST ABSENT : marge > 0. Une chaine libre a, quelque part sur sa
sphere atteignable, une position ou son volume ne recouvre plus l'obstacle ; la collision
n'est alors qu'un evenement, et c'est sa dynamique qui la pose. Marge < 0 = CAPTURE
PERMANENTE : aucune valeur de raideur, de masse ou de couple ne peut l'en sortir.

LA GEOMETRIE EST EXACTE, PAS APPROCHEE.
* Le moteur impose la longueur d'os : le maillon tourne autour de son attache `A` (le joint
  du maillon precedent, ou le parent rig pour le maillon 0 — `*phys-anchor*`, pose a
  jak-hd-physics.gc:855-858).
* Le volume qu'un maillon porte est centre en `C = J + R.off`, `off` etant le decalage de la
  ligne `collider <J>` quand elle existe (jak-hd-physics.gc:947-968 : un maillon dont le
  joint declare une SPHERE prend SON rayon ET SON centre), et `R` la rotation SIMULEE du
  maillon (`phys-link-off-sim!`, jak-hd-physics.gc:1589-1614).
* Cette rotation est, par construction, la rotation minimale qui amene la direction d'os du
  modele `m` sur la direction simulee `u` : elle verifie `R.m = u`, donc
  `C - A = R.[(J - A) + off]` et **`Rc = |(J - A) + off|` est une CONSTANTE**. L'ensemble
  atteignable par `C` est la sphere de centre `A` et de rayon `Rc`.

SENS DE L'INFERENCE, ET IL EST SUR. La sphere de rayon `Rc` est un SUR-ensemble de ce que le
maillon atteint reellement (l'angle max et les autres contraintes ne font que le reduire).
Donc « meme le meilleur point de la sphere est dedans » ⟹ CAPTURE. A l'inverse `FREE` ne veut
pas dire « il en sort », seulement « rien ici ne l'en empeche ».

DEUX PORTEES, ET LA DIFFERENCE CHANGE UN VERDICT — elle est donc publiee, pas choisie en
silence. La portee ci-dessus prend l'attache A A SA POSE DE MODELE ; pour un maillon dont
l'attache est un joint SIMULE, l'attache bouge elle aussi. La section COMPOSEE reprend le
calcul depuis la derniere attache NON simulee (le parent rig, ou le dernier maillon
`rootlock` — jak-hd-physics.gc:2828-2839 : les maillons `l < rlk` ne sont ni integres ni
ecrits, la pose retargetee reste au bit pres) avec la somme des portees. La boule qu'elle
decrit contient tout ce que la chaine peut faire, donc une CAPTURE composee est
INCONDITIONNELLE. La coupe d'une boule a l'abscisse `s` etant un disque de meme rayon que
celle de sa sphere, le maximum est le meme sur la boule et sur sa sphere exterieure : le
balayage reste valable.

Ce script ne modifie rien, ne construit rien, ne joue aucune course. Il imprime des nombres.

Rejeu :  python3 .autoport/probe_chain_volume_capture.py
"""
import glob
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_keira_gen2 as g            # noqa: E402  (le generateur EST la source du rig)

UNITS = 4096.0                            # unites de jeu par metre
MODEL_SECTION = '[model keira-hd]'
CHAINS_REL = 'recharged_assets/physics_chains.txt'
OUT_REL = '.autoport/reports/Grecharged-secondary-motion/chain-volume-capture.txt'
ROOM_GLOB = '.autoport/reports/Grecharged-secondary-motion/keira-room-table*.txt'

# Echantillonnage de la sphere atteignable, comme la spec l'exige (spirale de Fibonacci,
# >= 4096 points). Le verdict n'en depend pas : il est double par une reduction EXACTE
# (axisymetrie, voir `capsule_margin_exact`) et les deux sont compares, ecart publie.
NFIB = 16384
NSCAN = 200001
BONE_TOL = 0.03          # au-dela, la longueur d'os bind et celle mesuree par le moteur divergent


# ==================================================================================================
# 1. LE FICHIER DE DONNEES, LU TEL QU'IL EST LIVRE (aucune valeur en dur)
# ==================================================================================================
def strip_comment(line):
    i = line.find('#')
    return line if i < 0 else line[:i]


def kvs(tokens):
    out = {}
    for t in tokens:
        if '=' in t:
            k, v = t.split('=', 1)
            out[k] = v
    return out


def parse_chains(path):
    """-> (chains, volumes) pour la seule section [model keira-hd].

    chains : liste de dicts {name, joints[], radii[], rootlock, shell}
    volumes: liste de dicts {kind, ja, jb, ra, rb, off}
    """
    chains, volumes = [], []
    inside = False
    cur = None
    for raw in open(path, encoding='utf-8'):
        line = strip_comment(raw).strip()
        if not line:
            continue
        if line.startswith('['):
            inside = (line == MODEL_SECTION)
            continue
        if not inside:
            continue
        tok = line.split()
        head = tok[0]
        if head == 'chain':
            kv = kvs(tok[2:])
            cur = dict(name=tok[1], joints=[],
                       radii=[float(x) for x in kv['radii'].split(',')] if 'radii' in kv else [],
                       rootlock=int(kv.get('rootlock', '0')),
                       shell=float(kv.get('shell', '0')))
            chains.append(cur)
        elif head == 'j':
            if cur is None:
                raise SystemExit('ligne `j` hors chaine dans ' + path)
            cur['joints'].append(tok[1])
        elif head == 'capsule':
            kv = kvs(tok[3:])
            volumes.append(dict(kind='capsule', ja=tok[1], jb=tok[2],
                                ra=float(kv['radius']), rb=float(kv['radius2']),
                                off=tuple(float(x) for x in kv['offset'].split(','))
                                if 'offset' in kv else (0.0, 0.0, 0.0)))
        elif head == 'collider':
            kv = kvs(tok[2:])
            volumes.append(dict(kind='sphere', ja=tok[1], jb=None,
                                ra=float(kv['radius']), rb=float(kv['radius']),
                                off=tuple(float(x) for x in kv['offset'].split(','))
                                if 'offset' in kv else (0.0, 0.0, 0.0)))
    return chains, volumes


def vol_label(v):
    return ('%s->%s' % (v['ja'], v['jb'])) if v['kind'] == 'capsule' else ('sphere:' + v['ja'])


ROOM_RX = re.compile(r'^\s*chain\s+(\S+)\s+links=(\d+).*?contact_frames=(\d+).*?'
                     r'bones_m=([0-9.,]+)\s*$')


def parse_room(repo):
    """LA COURSE QUI A POSE LA QUESTION, relue telle qu'elle a ete imprimee.

    Deux choses en sortent, et aucune n'est un commentaire : `contact_frames` — le nombre de
    frames ou la chaine avait au moins une paire (lien, volume) en contact, c'est CE chiffre a
    17893/17893 qui a motive ce probe — et `bones_m`, la longueur d'os que le MOTEUR a mesuree
    sur le squelette retargete. Cette seconde sert de temoin externe a la geometrie lue ici,
    qui vient de la pose de bind du GLB : deux sources independantes de la meme longueur."""
    cands = sorted(glob.glob(os.path.join(repo, ROOM_GLOB)), key=os.path.getmtime)
    if not cands:
        return None, {}
    path = cands[-1]
    rows = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        m = ROOM_RX.match(line)
        if m:
            rows[m.group(1)] = dict(links=int(m.group(2)), contact=int(m.group(3)),
                                    bones=[float(x) for x in m.group(4).split(',')])
    return os.path.relpath(path, repo), rows


# ==================================================================================================
# 2. LE RIG, LU PAR LE GENERATEUR (meme source, memes helpers)
# ==================================================================================================
def bind_rot(ibms, j):
    """Rotation bind du joint `j`, echelle retiree ligne a ligne — EXACTEMENT la convention de
    `physics_keira_gen2.to_bone_local` (dont quatre joints de bretelle portent une echelle de
    9.68). Un decalage local `off` devient `off @ Rn` en monde."""
    R = ibms[j][:3, :3]
    s = np.linalg.norm(R, axis=1)
    s = np.where(s < 1e-12, 1.0, s)
    return R / s[:, None]


def world_off(ibms, j, off):
    if off is None or (off[0] == 0.0 and off[1] == 0.0 and off[2] == 0.0):
        return np.zeros(3)
    return np.asarray(off, dtype=float) @ bind_rot(ibms, j)


# ==================================================================================================
# 3. LA MARGE D'EVASION
# ==================================================================================================
def fib_dirs(n):
    i = np.arange(n) + 0.5
    z = 1.0 - 2.0 * i / n
    r = np.sqrt(np.maximum(0.0, 1.0 - z * z))
    th = np.pi * (1.0 + 5.0 ** 0.5) * i
    return np.stack([r * np.cos(th), r * np.sin(th), z], axis=1)


FIB = fib_dirs(NFIB)


def sphere_margin_closed(A, Rc, S, rv, rl):
    """Obstacle SPHERE : le maximum de |C - S| sur la sphere atteignable vaut |A - S| + Rc."""
    return float(np.linalg.norm(A - S)) + Rc - rv - rl


def capsule_margin_fib(A, Rc, ca, cb, ra, rb, rl):
    """Obstacle CAPSULE, par echantillonnage de la sphere atteignable.

    Reproduit `phys-collide-depth` (jak-hd-physics.gc:1144-1184) A LA LETTRE : parametre
    `t0 = ((pt-ca).ab)/|ab|^2` SERRE sur [0,1] (lignes 1156-1163), point le plus proche
    `ca + t0.ab`, rayon INTERPOLE LINEAIREMENT `rr = ra + (rb-ra).t0` (ligne 1167), puis
    `want = rr + rlink` et penetration `want - d` (ligne 1173). La marge est l'oppose :
    `d - rr - rlink`."""
    P = A[None, :] + Rc * FIB
    ab = cb - ca
    dd = float(ab @ ab)
    if dd < 1e-6:
        d = np.linalg.norm(P - ca[None, :], axis=1)
        return float(np.max(d - ra - rl))
    t0 = np.clip((P - ca[None, :]) @ ab / dd, 0.0, 1.0)
    proj = ca[None, :] + t0[:, None] * ab[None, :]
    d = np.linalg.norm(P - proj, axis=1)
    rr = ra + (rb - ra) * t0
    return float(np.max(d - rr - rl))


def capsule_margin_exact(A, Rc, ca, cb, ra, rb, rl):
    """LA MEME GRANDEUR, SANS ERREUR D'ECHANTILLONNAGE — et ce n'est pas un raffinement de
    confort : un maximum cherche sur une grille est un MINORANT, et un minorant negatif ne
    prouve une capture que si l'erreur de grille est plus petite que la marge. La reduction
    ci-dessous supprime la question.

    Le probleme est AXISYMETRIQUE autour de l'axe de la capsule : `d` et `rr` ne dependent que
    de l'abscisse `s` du point le long de l'axe et de sa distance `rho` a cet axe. A `s` fixe,
    les points de la sphere atteignable forment un cercle de rayon `r_s = sqrt(Rc^2-(s-s_A)^2)`
    centre sur l'axe-projete de A, donc `rho` y decrit `[|rho_A - r_s|, rho_A + r_s]` ; et `d`
    croit avec `rho`. Le maximum est donc atteint en `rho = rho_A + r_s`, ce qui laisse UNE
    variable, balayee finement."""
    ab = cb - ca
    L = float(np.linalg.norm(ab))
    if L < 1e-6:
        return float(np.linalg.norm(A - ca)) + Rc - ra - rl
    u = ab / L
    rel = A - ca
    sA = float(rel @ u)
    rhoA = float(np.linalg.norm(rel - sA * u))
    s = np.linspace(sA - Rc, sA + Rc, NSCAN)
    rs = np.sqrt(np.maximum(0.0, Rc * Rc - (s - sA) ** 2))
    rho = rhoA + rs
    t0 = np.clip(s / L, 0.0, 1.0)
    d = np.sqrt((s - t0 * L) ** 2 + rho ** 2)
    rr = ra + (rb - ra) * t0
    return float(np.max(d - rr - rl))


def dist_to_segment(p, ca, cb):
    ab = cb - ca
    dd = float(ab @ ab)
    if dd < 1e-6:
        return float(np.linalg.norm(p - ca))
    t = min(1.0, max(0.0, float((p - ca) @ ab / dd)))
    return float(np.linalg.norm(p - (ca + t * ab)))


# ==================================================================================================
# 4. LA REGLE D'EXCLUSION DU MOTEUR, COPIEE — PAS INVENTEE
# ==================================================================================================
def col_own(chain_joint_idx, cj, cj2):
    """`phys-col-own?` (jak-hd-physics.gc:1735-1740), a la lettre : le volume est PROPRE des que
    son joint porteur `cj` — ou le second joint `cj2` d'une capsule — est l'un des joints de la
    chaine, quel que soit le maillon. Le moteur ne le teste alors jamais : il ne peut donc pas
    capturer, et il n'apparait pas ici."""
    for k2j in chain_joint_idx:
        if k2j >= 0 and (cj == k2j or cj2 == k2j):
            return True
    return False


# ==================================================================================================
def main():
    repo = g.REPO
    chains_path = os.path.join(repo, CHAINS_REL)
    out_path = os.path.join(repo, OUT_REL)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    names, parent, _doc = g.load_rig(os.path.join(repo, g.RIG_REL))
    geo = g.load_mesh(g.MODEL)
    if list(geo['names']) != names:
        raise SystemExit('la liste de joints du GLB ne correspond pas au rig json')
    idx_of = {n: i for i, n in enumerate(names)}
    P, ibms = geo['P'], geo['ibms']

    chains, volumes = parse_chains(chains_path)

    out = []

    def emit(s=''):
        out.append(s)
        print(s)

    emit('# chain-volume-capture — quelle chaine est enfermee dans quel volume, en forme close.')
    emit('# rig   : %s (%d joints, pose de bind)' % (g.RIG_REL, len(names)))
    emit('# mesh  : %s' % geo['src'])
    emit('# data  : %s (%d chaines, %d volumes)' % (CHAINS_REL, len(chains), len(volumes)))
    emit('# unite : unite de jeu, 4096 u = 1 m. marge < 0 = le maillon ne peut JAMAIS sortir.')
    emit('# echantillonnage Fibonacci = %d points, verification exacte (axisymetrie) = %d pas.'
         % (NFIB, NSCAN))
    emit('')

    # ---- CONTROLE DE CONVENTION : le decalage est-il lu dans le bon repere ? -------------------
    # Discriminant : le generateur a ecrit chaque `offset` comme le CENTROIDE mesure de la
    # geometrie du joint, dans son espace de bind. Si la convention de repere etait fausse (ou la
    # normalisation d'echelle oubliee sur les quatre joints de bretelle), l'ecart se compterait en
    # centaines d'unites. Il se compte en fractions d'unite.
    worst_c, worst_j = 0.0, '-'
    for v in volumes:
        if v['kind'] != 'sphere':
            continue
        j = idx_of[v['ja']]
        for thr in (0.5, 0.25, 0.05):
            n, _w, ii = g.influence(geo, j, thr)
            if n >= 8:
                break
        if n == 0:
            continue
        c = geo['V'][ii].mean(axis=0)
        e = float(np.linalg.norm(c - (P[j] + world_off(ibms, j, v['off']))))
        if e > worst_c:
            worst_c, worst_j = e, v['ja']
    emit('CHECK repere-decalage: pire ecart centre-calcule / centroide-mesure = %.2f u (%s)'
         % (worst_c, worst_j))
    emit('')

    # ---- geometrie des volumes, une fois -------------------------------------------------------
    vg = []
    for v in volumes:
        cj = idx_of[v['ja']]
        cj2 = idx_of[v['jb']] if v['jb'] is not None else -1
        ca = P[cj] + world_off(ibms, cj, v['off'])
        cb = P[cj2] if cj2 >= 0 else ca
        vg.append(dict(v=v, cj=cj, cj2=cj2, ca=ca, cb=cb, label=vol_label(v)))

    room_path, room = parse_room(repo)
    cap_rows, free_rows, sum_rows, note_rows, shell_rows = [], [], [], [], []
    comp_rows, diff_rows, conf_rows, bone_rows = [], [], [], []
    captured_of = {}
    worst_gap = [0.0, '-']
    worst_bone = [0.0, '-']
    nbone = [0]

    def margins(A, R, rl, jidx, where):
        """(marge, label) contre chaque volume que le moteur testerait pour cette chaine."""
        res = []
        for x in vg:
            if col_own(jidx, x['cj'], x['cj2']):
                continue
            ra, rb = x['v']['ra'], x['v']['rb']
            m_fib = capsule_margin_fib(A, R, x['ca'], x['cb'], ra, rb, rl)
            if x['cj2'] >= 0:
                m_ex = capsule_margin_exact(A, R, x['ca'], x['cb'], ra, rb, rl)
            else:
                m_ex = sphere_margin_closed(A, R, x['ca'], ra, rl)
            gap = abs(m_ex - m_fib)
            if gap > worst_gap[0]:
                worst_gap[0] = gap
                worst_gap[1] = '%s/%s' % (where, x['label'])
            # les deux methodes minorent le vrai maximum : on garde le plus grand, donc une
            # CAPTURE annoncee reste vraie meme si une methode sous-estime.
            res.append((max(m_fib, m_ex), x['label'], x))
        return res

    for ch in chains:
        jidx = [idx_of[j] for j in ch['joints']]
        n = len(jidx)
        rlk = max(0, min(ch['rootlock'], max(0, n - 1)))   # jak-hd-physics.gc:2702
        radii = ch['radii'] if ch['radii'] else [0.0] * n
        excluded = [x['label'] for x in vg if col_own(jidx, x['cj'], x['cj2'])]
        caps_here = []
        cum = 0.0            # somme des portees depuis la derniere attache NON simulee
        A0 = None
        for l, jn in enumerate(ch['joints']):
            kk = jidx[l]
            # attache : maillon precedent, ou parent rig pour le maillon 0 (*phys-anchor*,
            # jak-hd-physics.gc:855-858)
            if l > 0:
                A = P[jidx[l - 1]]
                anchor_name = ch['joints'][l - 1]
            else:
                pa = parent[kk]
                if pa < 0:
                    note_rows.append('NOTE    chain=%s link=0 joint=%s SANS ANCRE (racine rig) — '
                                     'aucune sphere atteignable, maillon ignore' % (ch['name'], jn))
                    continue
                A = P[pa]
                anchor_name = names[pa]
            # rayon et decalage du volume que CE maillon porte (jak-hd-physics.gc:947-968)
            rl = radii[l] if l < len(radii) else 0.0
            off = (0.0, 0.0, 0.0)
            for x in vg:
                if x['v']['kind'] == 'sphere' and x['cj'] == kk:
                    rl = x['v']['ra']
                    off = x['v']['off']
                    break
            offw = world_off(ibms, kk, off)
            C = P[kk] + offw
            Rc = float(np.linalg.norm((P[kk] - A) + offw))
            # temoin externe : la meme longueur d'os, mesuree par le moteur sur le squelette
            # retargete pendant la course de la salle.
            bl = float(np.linalg.norm(P[kk] - A))
            rr = room.get(ch['name'])
            if rr and l < len(rr['bones']) and rr['bones'][l] > 0.001:
                dev = abs(bl / UNITS - rr['bones'][l]) / rr['bones'][l]
                nbone[0] += 1
                if dev > worst_bone[0]:
                    worst_bone[0] = dev
                    worst_bone[1] = '%s/link%d' % (ch['name'], l)
                if dev > BONE_TOL:
                    # ON NE LAISSE PAS LA RESERVE EN L'ETAT : le verdict est REJOUE a la longueur
                    # que le moteur a mesuree, et c'est ce rejeu qui est publie.
                    ralt = Rc * rr['bones'][l] / (bl / UNITS)
                    alt = [(m, lab) for m, lab, _x in
                           margins(A, ralt, rl, jidx, '%s/link%d-alt' % (ch['name'], l))
                           if m < 0.0]
                    bone_rows.append('BONEDEV chain=%s link=%d joint=%s bind=%.4f m '
                                     'mesuree-par-le-moteur=%.4f m ecart=%.1f %% — portee %.0f u '
                                     'ici, %.0f u a la longueur mesuree ; verdict rejoue a cette '
                                     'longueur : %s'
                                     % (ch['name'], l, jn, bl / UNITS, rr['bones'][l],
                                        100.0 * dev, Rc, ralt,
                                        ('CAPTURE par ' + ','.join(lab for _m, lab in alt))
                                        if alt else 'LIBRE, inchange'))
            pinned = (l < rlk)
            tag = '  [fige rootlock]' if pinned else ''
            if l == rlk:
                A0 = A
                cum = 0.0
            if not pinned:
                cum += Rc

            best_free = None
            for m, label, x in margins(A, Rc, rl, jidx, '%s/link%d' % (ch['name'], l)):
                if m < 0.0:
                    shell = (x['cj2'] >= 0 and ch['shell'] > 0.0
                             and dist_to_segment(C, x['ca'], x['cb']) < ch['shell'])
                    if shell:
                        shell_rows.append('SHELL   chain=%s link=%d joint=%s vol=%s — le lien '
                                          'ENTOURE ce volume (shell=%.0f u, |centre-axe|=%.0f u) : '
                                          'le moteur le traite en fourreau (phys-shell-pair?), pas '
                                          'en penetration' %
                                          (ch['name'], l, jn, label, ch['shell'],
                                           dist_to_segment(C, x['ca'], x['cb'])))
                    cap_rows.append((m, 'CAPTURE chain=%s link=%d joint=%s vol=%s reach=%.0f u '
                                        'margin=%.0f (%.4f m)%s%s'
                                     % (ch['name'], l, jn, label, Rc, m, m / UNITS,
                                        '  [fourreau]' if shell else '', tag)))
                    caps_here.append(label)
                if best_free is None or m < best_free[0]:
                    best_free = (m, label)
            # une seule ligne FREE par maillon : le volume le plus serre resume tous les autres,
            # et `best_free[0] >= 0` equivaut a « aucun volume ne le capture ».
            if best_free is not None and best_free[0] >= 0.0:
                free_rows.append('FREE    chain=%s link=%d joint=%s tightest=%s margin=%.0f '
                                 '(%.4f m)  reach=%.0f u anchor=%s%s'
                                 % (ch['name'], l, jn, best_free[1], best_free[0],
                                    best_free[0] / UNITS, Rc, anchor_name, tag))

            # ---- portee COMPOSEE : inconditionnelle, l'attache simulee bouge aussi -------------
            if pinned or A0 is None:
                continue
            comp = [(m, label) for m, label, _x in
                    margins(A0, cum, rl, jidx, '%s/link%d-compose' % (ch['name'], l)) if m < 0.0]
            for m, label in sorted(comp):
                comp_rows.append('COMPOUND chain=%s link=%d joint=%s vol=%s reach=%.0f u '
                                 'margin=%.0f (%.4f m)'
                                 % (ch['name'], l, jn, label, cum, m, m / UNITS))
            got = set(label for _m, label in comp)
            for m, label, _x in margins(A, Rc, rl, jidx, '%s/link%d' % (ch['name'], l)):
                if m < 0.0 and label not in got:
                    diff_rows.append('DIFF    chain=%s link=%d vol=%s : CAPTURE a attache figee, '
                                     'LIBRE quand toute la chaine bouge (portee %.0f u -> %.0f u)'
                                     % (ch['name'], l, label, Rc, cum))
        captured_of[ch['name']] = caps_here
        sum_rows.append('SUMMARY chain=%s links=%d captured=%d volumes=%s'
                        % (ch['name'], n, len(caps_here),
                           ','.join(caps_here) if caps_here else '-'))
        rr = room.get(ch['name'])
        if rr:
            conf_rows.append('CONFRONT chain=%-12s contact_frames=%-6d captured=%d/%d  -> %s'
                             % (ch['name'], rr['contact'], len(caps_here), n,
                                'le contact permanent est GEOMETRIQUE' if caps_here else
                                ('contact permanent SANS capture geometrique : la cause est '
                                 'ailleurs' if rr['contact'] >= 17000 else 'contact episodique')))
        note_rows.append('NOTE    chain=%s rootlock=%d volumes-propres-exclus(phys-col-own?)=%s'
                         % (ch['name'], ch['rootlock'], ','.join(excluded) if excluded else '-'))

    cap_rows.sort(key=lambda r: r[0])
    emit('-- CAPTURES (marge croissante : la plus enfermee d\'abord) --------------------------')
    for _m, s in cap_rows:
        emit(s)
    if not cap_rows:
        emit('(aucune)')
    emit('')
    emit('-- LIBRES (marge du volume le plus serre) -----------------------------------------')
    for s in free_rows:
        emit(s)
    if not free_rows:
        emit('(aucune)')
    emit('')
    if shell_rows:
        emit('-- FOURREAUX : capture geometrique que le moteur traite autrement -----------------')
        for s in shell_rows:
            emit(s)
        emit('')
    emit('-- CAPTURES INCONDITIONNELLES (portee COMPOSEE depuis la derniere attache non simulee,')
    emit('   donc vraies quoi que fasse le reste de la chaine) -----------------------------')
    for s in comp_rows:
        emit(s)
    if not comp_rows:
        emit('(aucune)')
    emit('')
    if diff_rows:
        emit('-- CE QUE LES DEUX PORTEES NE DISENT PAS PAREIL ------------------------------------')
        for s in diff_rows:
            emit(s)
        emit('')
    emit('-- PAR CHAINE ---------------------------------------------------------------------')
    for s in sum_rows:
        emit(s)
    emit('')
    for s in note_rows:
        emit(s)
    emit('')
    if conf_rows:
        emit('-- CONFRONTATION AVEC LA COURSE QUI A POSE LA QUESTION -----------------------------')
        emit('   source : %s' % room_path)
        for s in conf_rows:
            emit(s)
        emit('')
    emit('CHECK fibonacci-vs-exact: pire ecart %.2f u sur %s (les deux minorent le vrai maximum ; '
         'le verdict prend le plus grand des deux)' % (worst_gap[0], worst_gap[1]))
    if room_path:
        emit('CHECK longueur-d-os bind vs mesuree par le moteur: %d/%d liens sous %.0f %%, pire '
             'ecart %.1f %% (%s)'
             % (nbone[0] - len(bone_rows), nbone[0], 100.0 * BONE_TOL,
                100.0 * worst_bone[0], worst_bone[1]))
        for s in bone_rows:
            emit(s)
    else:
        emit('CHECK longueur-d-os : aucune table de salle trouvee, temoin externe indisponible')
    emit('')

    # ---- LES DEUX CONTROLES -------------------------------------------------------------------
    emit('-- CONTROLES ----------------------------------------------------------------------')
    pos_hit = any(r[1].startswith('CAPTURE chain=backhair link=0 ')
                  and 'vol=head->neck ' in r[1] for r in cap_rows)
    neg_free = (len(captured_of.get('earL', ['?'])) == 0)
    emit('CONTROL positive backhair/head->neck = %s (attendu CAPTURE)'
         % ('CAPTURE' if pos_hit else 'FREE'))
    emit('CONTROL negative earL = %s (attendu FREE)'
         % ('FREE' if neg_free else 'CAPTURE'))

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    print('\n-> %s' % out_path)

    if not pos_hit:
        print('CONTROLE POSITIF NON TIRE : `backhair` maillon 0 devrait etre CAPTURE par '
              '`head->neck` (portee 820 u contre rayon 915 u, cf. '
              'probe_head_volume_selfinclusion.py). Le calcul est faux.', file=sys.stderr)
    if not neg_free:
        print('CONTROLE NEGATIF NON TIRE : `earL` est mesuree en contact 25 frames sur 17893, '
              'elle SORT donc ; la declarer capturee rend le calcul faux. Captures trouvees : %s'
              % ','.join(captured_of.get('earL', [])), file=sys.stderr)
    return 0 if (pos_hit and neg_free) else 1


if __name__ == '__main__':
    sys.exit(main())
