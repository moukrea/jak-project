#!/usr/bin/env python3
"""probe_skin_in_volume.py — LE VOLUME DE COLLISION RECLAME-T-IL LA PLACE OU LA PEAU EST DEJA ?

Ce script ne genere rien et ne modifie rien. Il lit `recharged_assets/physics_chains.txt` (le
fichier LIVRE) et le mesh LIVRE (`out/jak1/fr3/skin/keira-hd-lod0.glb`, celui du pack), et repond a
UNE question, hors moteur et hors build :

    pour chaque chaine, quelle FRACTION DE SA PROPRE PEAU se trouve, DANS LA POSE DE BIND DU
    MODELE, a l'interieur d'un volume de collision qui ne lui appartient pas ?

POURQUOI CETTE QUESTION, ET POURQUOI AUCUNE MESURE EXISTANTE N'Y REPOND.
`probe_rest_containment.py` mesure le MAILLON : un point (le joint) plus un rayon de lien. La
salle mesure la position ECRITE DU JOINT. L'owner, lui, voit la PEAU. Un volume ajuste par un rayon
unique sur un joint dont la geometrie est allongee sur-couvre dans toutes les directions sauf celle
qui a fixe le rayon — et il avale alors le tissu qui pend autour du membre. Le vetement devient
invisible sans qu'aucun compteur de penetration ne bouge : il n'y a pas de traversee, il y a une
ABSORPTION.

C'est exactement la formulation de l'owner (2026-08-11, 12 aout) : « le bas de son pantacourt clipe
a l'interieur de ses mollets au lieu d'etre visible, comme si son pantacourt s'arretait aux
genoux », et sa cause racine designee depuis le debut : « les colliders ne suivent pas la forme du
personnage ». C'est aussi la meme famille que la preuve arithmetique de la nuque (portee de pointe
820 u contre 915 u de rayon de capsule de tete : elle ne peut pas en sortir).

LES TROIS QUESTIONS DE LA SPEC 7, REPONDUES AVANT D'ECRIRE LA MESURE :

  NATURE  : une FRACTION (sans unite) doublee d'une PROFONDEUR SIGNEE en unites de jeu. C'est un
            etat STATIQUE de la pose de bind — ni une amplitude, ni une variance, ni une frequence.
            Le defaut vise n'est pas « ca bouge mal », c'est « la place est deja prise ».
  REPERE  : la POSE DE BIND du modele livre, en unites de jeu (4096/m), le meme repere que celui ou
            `physics_chains.txt` exprime ses rayons. Aucune simulation n'intervient : le resultat
            est independant du solveur, et c'est le but — il dit ce que le solveur ne PEUT PAS
            corriger.
  LECTURE QUAND LE DEFAUT EST ABSENT : 0 %. Le tissu d'une chaine vit DEHORS du volume qui
            represente le membre auquel il pend. Une chaine propre lit `inside=0.0%`; la mesure a
            donc une echelle et un zero qui veulent dire quelque chose.

CE QUE LA MESURE NE DIT PAS. Un recouvrement n'est pas en soi une faute : le moteur TOLERE le
recouvrement au repos (`feff = floor0`), donc un tissu enfoui de `d` garde `d` de laissez-passer et
n'est pas repousse. Ce que la mesure dit, c'est que la SILHOUETTE que le volume presente aux autres
chaines n'est pas celle du personnage — et qu'aucun reglage de raideur ne rendra visible un pan de
tissu dont la place est occupee par le mollet.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

from retarget_hd_models import (read_glb, consolidate_buffers,  # noqa: E402
                                read_accessor, skin_info)

UNITS = 4096.0          # unites de jeu par metre ; le glb est en METRES (echelle 1.0, calibree
                        # dans probe_hair_joint_deficit.py contre les `bones_m` publies par le
                        # moteur lui-meme).
CHAINS_FILE = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
SHIPPED = os.path.join(REPO, 'out', 'jak1', 'fr3', 'skin', 'keira-hd-lod0.glb')
OWN = 0.5               # possession MAJORITAIRE : voir chain_owned() de probe_hair_joint_deficit.
OUT = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion',
                   'skin-in-volume.txt')


def parse_chains(path):
    """Chaines (joints), capsules et spheres, LUES DANS LE FICHIER LIVRE.

    Jamais de liste ecrite a la main ici : la composition des chaines vit deja dans cinq endroits
    de l'arbre et deux defauts du 13 aout etaient exactement cette duplication qui derive.
    """
    chains, capsules, spheres = {}, [], []
    cur = None
    for raw in open(path, errors='ignore'):
        s = raw.strip()
        if not s or s.startswith('#') or s.startswith('['):
            continue
        tok = s.split()
        if tok[0] == 'chain':
            cur = tok[1]
            chains[cur] = []
        elif tok[0] == 'j' and cur:
            chains[cur].append(tok[1])
        elif tok[0] == 'capsule':
            kv = dict(t.split('=', 1) for t in tok[3:] if '=' in t)
            capsules.append((tok[1], tok[2], float(kv['radius']), float(kv['radius2'])))
        elif tok[0] == 'collider':
            kv = dict(t.split('=', 1) for t in tok[2:] if '=' in t)
            off = np.array([float(x) for x in kv.get('offset', '0,0,0').split(',')], dtype=float)
            spheres.append((tok[1], float(kv['radius']), off))
    return {k: v for k, v in chains.items() if v}, capsules, spheres


def gather(js, binc):
    """(noms, transform de bind monde, parents, positions, (joints, poids), normales) — une entree
    par jeu d'attributs DISTINCT.

    Le donneur rippe 28 primitives qui referencent TOUTES les memes accesseurs POSITION/JOINTS_0/
    WEIGHTS_0 : iterer les primitives en aveugle compte chaque sommet 28 fois (mesure — une meche
    de 167 sommets se lisait 36484). Cle sur le triplet d'accesseurs.
    """
    names, ibms, parent = skin_info(js, binc)
    bind = np.array([np.linalg.inv(m) for m in ibms])
    seen, pos_all, jw, nrm_all = set(), [], [], []
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            at = p['attributes']
            if 'JOINTS_0' not in at or 'WEIGHTS_0' not in at:
                continue
            key = (at['POSITION'], at['JOINTS_0'], at['WEIGHTS_0'])
            if key in seen:
                continue
            seen.add(key)
            P = read_accessor(js, binc, at['POSITION']).astype(np.float64)
            J = read_accessor(js, binc, at['JOINTS_0']).astype(np.int32)
            W = read_accessor(js, binc, at['WEIGHTS_0']).astype(np.float64)
            if W.max() > 1.5:
                W = W / W.max()
            N = (read_accessor(js, binc, at['NORMAL']).astype(np.float64)
                 if 'NORMAL' in at else np.zeros_like(P))
            pos_all.append(P)
            jw.append((J, W))
            nrm_all.append(N)
    return names, bind, parent, pos_all, jw, nrm_all


def chain_skin(jw, pos_all, jidx, nrm_all=None):
    """Les sommets que la chaine POSSEDE (poids somme sur ses joints > OWN), en unites de jeu.

    Possession MAJORITAIRE, et le seuil compte : avec 4 influences par sommet, un poids parasite de
    1e-4 sur un joint de racine ramene de la geometrie de l'autre bout du corps. Meme definition
    que `chain_owned` de probe_hair_joint_deficit.py, qui la calibre contre une queue de meche
    mesuree independamment.
    """
    s = set(jidx)
    out, outn = [], []
    for k, ((J, W), P) in enumerate(zip(jw, pos_all)):
        m = np.isin(J, list(s))
        if not m.any():
            continue
        w = np.where(m, W, 0.0).sum(axis=1)
        sel = w > OWN
        if sel.any():
            out.append(P[sel])
            if nrm_all is not None:
                outn.append(nrm_all[k][sel])
    if not out:
        z = np.zeros((0, 3))
        return (z, z) if nrm_all is not None else z
    V = np.concatenate(out) * UNITS
    if nrm_all is None:
        return V
    N = np.concatenate(outn)
    n = np.linalg.norm(N, axis=1)
    N = N / np.where(n[:, None] < 1e-9, 1.0, n[:, None])
    return V, N


def skin_vs_skin(A, B, Bn):
    """DE COMBIEN LA PEAU DE `A` PASSE-T-ELLE SOUS LA SURFACE DE `B`, DANS LA POSE DE BIND ?

    NATURE : une PROFONDEUR signee en unites de jeu, et un COMPTE de sommets. C'est un fait
      geometrique STATIQUE du modele livre — aucune simulation n'intervient.
    REPERE : la pose de bind, coordonnees monde du mesh livre.
    LECTURE QUAND LE DEFAUT EST ABSENT : 0 sommet, profondeur 0. Deux vetements poses l'un sur
      l'autre se TOUCHENT (profondeur ~0) ; ils ne se traversent pas.

    Methode : pour chaque sommet de A on prend le sommet de B le plus proche et la normale de B en
    ce point. Un produit scalaire negatif place le sommet DERRIERE la surface de B ; sa profondeur
    est la composante normale. Pas de booleen de maillage, pas de dependance externe — et la
    normale vient du glb, elle n'est pas reconstruite.
    """
    if len(A) == 0 or len(B) == 0:
        return 0, 0.0, np.zeros(0, dtype=bool)
    # bloc par bloc : 531 x 57 tient large, mais backhair x head monterait a 152 x 1518
    d2 = ((A[:, None, :] - B[None, :, :]) ** 2).sum(-1)
    nb = np.argmin(d2, axis=1)
    delta = A - B[nb]
    depth = (delta * Bn[nb]).sum(axis=1)
    inside = depth < 0.0
    return int(inside.sum()), float(-depth[inside].max()) if inside.any() else 0.0, inside


def seg_clearance(P, a, b, ra, rb):
    """Jeu radial SIGNE de chaque point de `P` a la capsule (a,b,ra,rb) : distance a l'axe borne
    moins le rayon interpole au parametre le plus proche. Negatif = DEDANS."""
    ab = b - a
    L2 = float(ab @ ab)
    if L2 <= 1e-9:
        return np.linalg.norm(P - a, axis=1) - ra
    t = np.clip(((P - a) @ ab) / L2, 0.0, 1.0)
    q = a[None, :] + t[:, None] * ab[None, :]
    return np.linalg.norm(P - q, axis=1) - (ra + t * (rb - ra))


def main():
    if not os.path.exists(SHIPPED):
        print("FAIL: %s absent — le bake n'a pas conserve le glb livre ; rien a mesurer." % SHIPPED)
        return 1
    chains, capsules, spheres = parse_chains(CHAINS_FILE)
    js, bufs = read_glb(SHIPPED)
    binc = consolidate_buffers(js, bufs)
    names, bind, parent, pos_all, jw, nrm_all = gather(js, binc)
    idx = {n: i for i, n in enumerate(names)}
    Pw = {n: bind[i][:3, 3] * UNITS for n, i in idx.items()}

    # fermeture DESCENDANTE : un joint injecte sous un joint simule est pilote lui aussi. Meme
    # regle que ROOM-SKINCOV, sinon les languettes injectees comptent comme non pilotees.
    kids = {}
    for k, p in enumerate(parent):
        if p is not None and p >= 0:
            kids.setdefault(int(p), []).append(k)

    def closure(jn):
        out, stack = set(), [idx[x] for x in jn if x in idx]
        while stack:
            k = stack.pop()
            if k in out:
                continue
            out.add(k)
            stack.extend(kids.get(k, []))
        return out

    lines = []

    def A(s=''):
        lines.append(s)
        print(s)

    A('SKIN-IN-VOLUME — la peau d\'une chaine est-elle DANS un volume qui ne lui appartient pas ?')
    A('  NATURE : fraction + profondeur signee, POSE DE BIND, unites de jeu (4096/m).')
    A('  REPERE : le modele livre %s' % os.path.relpath(SHIPPED, REPO))
    A('  LECTURE HORS DEFAUT : inside=0.0%% — le tissu vit DEHORS du membre auquel il pend.')
    A('  Un recouvrement n\'est pas une traversee : le moteur le TOLERE au repos. Ce qu\'il dit,')
    A('  c\'est que la silhouette presentee aux autres chaines n\'est pas celle du personnage.')
    A('')

    worst = []
    for cn in sorted(chains):
        own = closure(chains[cn])
        skin = chain_skin(jw, pos_all, own)
        if len(skin) == 0:
            A('SKINVOL: chain=%-12s AUCUN sommet possede (>%.2f) — non mesurable' % (cn, OWN))
            continue
        ownnames = {names[k] for k in own}
        rows = []
        for (a, b, ra, rb) in capsules:
            if a in ownnames or b in ownnames:
                continue                      # volume porte par la chaine elle-meme
            if a not in Pw or b not in Pw:
                continue
            cl = seg_clearance(skin, Pw[a], Pw[b], ra, rb)
            frac = float((cl < 0).mean())
            if frac > 0:
                rows.append(('%s->%s' % (a, b), frac, float(cl.min())))
        for (j, r, off) in spheres:
            if j in ownnames or j not in Pw:
                continue
            c = Pw[j] + (bind[idx[j]][:3, :3] @ (off / np.linalg.norm(
                bind[idx[j]][:3, :3], axis=1).clip(1e-12)))
            cl = np.linalg.norm(skin - c[None, :], axis=1) - r
            frac = float((cl < 0).mean())
            if frac > 0:
                rows.append(('sphere:%s' % j, frac, float(cl.min())))
        rows.sort(key=lambda x: -x[1])
        if not rows:
            A('SKINVOL: chain=%-12s n=%-5d inside=0.0%%   — propre' % (cn, len(skin)))
            continue
        # union : un sommet dedans AU MOINS UN volume etranger
        un = np.zeros(len(skin), dtype=bool)
        for (a, b, ra, rb) in capsules:
            if a in ownnames or b in ownnames or a not in Pw or b not in Pw:
                continue
            un |= seg_clearance(skin, Pw[a], Pw[b], ra, rb) < 0
        ufrac = float(un.mean())
        worst.append((ufrac, cn, len(skin), rows[0]))
        A('SKINVOL: chain=%-12s n=%-5d inside=%5.1f%%  (union capsules)  pire: %s %.1f%% jusqu\'a '
          '%.0f u = %.3f m' % (cn, len(skin), 100 * ufrac, rows[0][0], 100 * rows[0][1],
                               rows[0][2], rows[0][2] / UNITS))
        for r in rows[1:4]:
            A('         %-28s %5.1f%%  jusqu\'a %8.0f u = %.3f m' % (r[0], 100 * r[1], r[2],
                                                                     r[2] / UNITS))

    A('')
    A('CLASSEMENT — la peau la plus absorbee par un volume etranger :')
    for uf, cn, n, r0 in sorted(worst, reverse=True):
        A('  SKINVOL-WORST: chain=%-12s inside=%5.1f%%  n=%-5d  vol=%-24s min=%8.0f u = %.3f m'
          % (cn, 100 * uf, n, r0[0], r0[2], r0[2] / UNITS))

    # --------------------------------------------------------------------------------------------
    # PEAU CONTRE PEAU — le modele se traverse-t-il LUI-MEME dans sa propre pose de repos ?
    #
    # Les lignes ci-dessus mesurent la peau contre les VOLUMES. Celle-ci ne parle plus de volumes du
    # tout : elle compare deux morceaux de peau. Elle existe parce que la question « pourquoi les
    # lunettes clipent-elles dans les seins MEME EN IDLE ? » n'a pas de reponse dans le solveur si
    # la reponse est deja dans le mesh. Le repos, c'est la pose du modele (SPEC 4) : si deux pieces
    # s'y traversent, aucun reglage de collision ne peut les separer sans les eloigner de la pose
    # que l'owner veut voir.
    A('')
    A('PEAU CONTRE PEAU — interpenetration DANS LA POSE DE BIND (aucune simulation).')
    A('  NATURE : profondeur signee + compte de sommets. LECTURE HORS DEFAUT : 0 sommet.')
    A('  Deux pieces posees l\'une sur l\'autre se TOUCHENT ; elles ne se traversent pas.')
    skins = {}
    for cn in sorted(chains):
        V, N = chain_skin(jw, pos_all, closure(chains[cn]), nrm_all)
        if len(V):
            skins[cn] = (V, N)
    pairs, seen_pair = [], set()
    for a in sorted(skins):
        for b in sorted(skins):
            if a == b or (b, a) in seen_pair:
                continue
            seen_pair.add((a, b))
            Va, _ = skins[a]
            Vb, Nb = skins[b]
            # eliminatoire pas cher : deux nuages disjoints ne peuvent pas se traverser
            if (Va.min(0) > Vb.max(0)).any() or (Vb.min(0) > Va.max(0)).any():
                continue
            nin, dep, _ = skin_vs_skin(Va, Vb, Nb)
            if nin:
                pairs.append((dep, a, b, nin, len(Va)))
    if not pairs:
        A('  SKINSKIN: aucune interpenetration — le modele ne se traverse pas au repos.')
    for dep, a, b, nin, na in sorted(pairs, reverse=True):
        A('  SKINSKIN: %-12s sous la peau de %-12s : %d/%d sommets, jusqu\'a %5.0f u = %.3f m'
          % (a, b, nin, na, dep, dep / UNITS))

    # --------------------------------------------------------------------------------------------
    # SKINFIT — UN VOLUME CONTIENT-IL LA GEOMETRIE QU'IL EST CENSE REPRESENTER ?
    #
    # C'est la question que l'owner pose depuis le debut sous la forme « les colliders ne suivent
    # pas la forme du personnage », et aucune mesure ne la posait a l'endroit ou elle se decide :
    # un volume qui ne couvre pas sa propre peau laisse entrer les autres chaines JUSQU'A la
    # difference, et aucun compteur de penetration ne s'en plaint — la penetration est comptee
    # contre le VOLUME, pas contre la peau. Un zero peut donc coexister avec un clip visible, ce
    # qui est exactement le motif d'echec de la semaine.
    #
    # NATURE : une fraction (part de la peau contenue) et des RAYONS en unites de jeu.
    # REPERE : pose de bind, repere du volume.
    # LECTURE QUAND LE DEFAUT EST ABSENT : contient=100 %, et r_livre >= r_p100.
    A('')
    A('SKINFIT — le volume contient-il la peau qu\'il represente ? (sinon, on entre par la')
    A('  difference sans qu\'aucun compteur de penetration ne bouge)')
    # L'UNION, jamais un volume isole. Une meche est representee par la sphere de sa racine PLUS la
    # suite de capsules qui la longent : demander a la sphere de racine de contenir toute la meche
    # ferait lire « 10 % » sur une chaine parfaitement couverte. Un instrument injuste ne vaut pas
    # mieux qu'un faux vert — il envoie corriger ce qui n'est pas casse.
    fits = []
    for cn in sorted(chains):
        if cn not in skins:
            continue
        V = skins[cn][0]
        ownnames = {names[k] for k in closure(chains[cn])}
        cov = np.zeros(len(V), dtype=bool)
        dout = np.full(len(V), np.inf)
        nvol = 0
        for (a, b, ra, rb) in capsules:
            if (a in ownnames or b in ownnames) and a in Pw and b in Pw:
                nvol += 1
                cl = seg_clearance(V, Pw[a], Pw[b], ra, rb)
                cov |= cl < 0
                dout = np.minimum(dout, cl)
        for (j, r, off) in spheres:
            if j in ownnames and j in idx:
                nvol += 1
                R3 = bind[idx[j]][:3, :3]
                s = np.linalg.norm(R3, axis=1)
                s = np.where(s < 1e-12, 1.0, s)
                c = Pw[j] + (R3 / s[:, None]) @ off
                cl = np.linalg.norm(V - c[None, :], axis=1) - r
                cov |= cl < 0
                dout = np.minimum(dout, cl)
        if nvol == 0:
            A('  SKINFIT: chain=%-12s AUCUN volume propre — cette chaine ne presente RIEN aux'
              ' autres (n=%d sommets)' % (cn, len(V)))
            continue
        out = dout[~cov]
        fits.append((float(cov.mean()), cn, nvol, len(V),
                     float(out.max()) if len(out) else 0.0))
    for frac, cn, nvol, n, worst in sorted(fits):
        A('  SKINFIT: chain=%-12s %d volume(s) propres couvrent %5.1f%% de sa peau (n=%d)  '
          'le sommet le plus DEHORS est a %5.0f u = %.3f m de la surface'
          % (cn, nvol, 100 * frac, n, worst, worst / UNITS))
    # LE CHIFFRE D'ENSEMBLE. Tous les compteurs de collision du moteur (meshpen, ROOM-SIDE,
    # SELFCOL) surveillent des LIENS ; cette ligne dit quelle part de la geometrie qui BOUGE ces
    # liens representent. C'est le denominateur qui manquait a tous les zeros publies depuis une
    # semaine : un zero sur les liens reste compatible avec ce que l'owner voit tant que ce
    # pourcentage n'est pas 100.
    tot = sum(n for _f, _c, _v, n, _w in fits) + sum(
        len(skins[c][0]) for c in skins
        if c not in {x[1] for x in fits})
    cov_v = sum(f * n for f, _c, _v, n, _w in fits)
    if tot:
        A('  SKINFIT-TOTAL: les volumes representent %.1f%% de la geometrie que la physique pilote'
          ' (%.0f sommets couverts sur %d)' % (100.0 * cov_v / tot, cov_v, tot))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w').write('\n'.join(lines) + '\n')
    A('')
    A('[ecrit] %s' % os.path.relpath(OUT, REPO))
    return 0


if __name__ == '__main__':
    sys.exit(main())
