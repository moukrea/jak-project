#!/usr/bin/env python3
"""c124_delivered_shape.py — LA FORME QUE LA PEAU RECOIT, CONTRE LA FORME QUE LE SOLVEUR COMMANDE.

POURQUOI CE FICHIER EXISTE. La directive du 2026-08-23 16:00 pose en PRIORITE 1 les six cellules
d'echelle de §10 et §11 : « leur verdict doit se mesurer contre une grandeur INDEPENDANTE de
l'entree du solveur, ou la section repasse NON ETABLI ». Le cycle 120 a pris la seconde branche —
les six cellules ne portent plus de verdict — et le cycle 123 a ecrit noir sur blanc que « aucune
grandeur independante ne remplace encore ce que ces six cellules pretendaient mesurer, a savoir la
FORME ». Ce fichier attaque la premiere branche.

CE QUI ETAIT MESURE, ET POURQUOI C'ETAIT UN MIROIR. `PHYSORI2 sx/sy/sz` publie les trois echelles
que le solveur COMMANDE a la racine du sein. Le fichier livre les lui INJECTE
(`pk SupineProjectionScale 0.7`), et la bande de verdict de la spec est CENTREE sur ce meme
nombre (« Forward projection: -25 to -35%, nominal -30% »). Un tel verdict ne peut pas echouer :
c'est la definition du miroir, et descendre la constante du moteur vers le fichier ne l'a pas
retire (registre : `mirror-is-the-couple-not-the-location`).

CE QUI EST MESURE ICI. La forme du NUAGE DE PEAU, c'est-a-dire ce que l'owner voit : les sommets
du mesh LIVRE, deplaces par SKINNING LINEAIRE avec les matrices d'os REELLEMENT ECRITES au
squelette (`PHYSORIM`, emis par phys-room.gc au cycle 124). Entre la commande et ce nuage il y a
le melange de deux maillons aux matrices differentes, la rotation squelettique, la contrainte de
longueur, `phys-skin-chain` et la collision. Le cycle 90 a deja mesure que les deux ne tombent pas
dans les memes bandes (13/16 cellules contre 8/16 sur le produit que la peau recoit).

CE QUE CE FICHIER NE PRETEND PAS. Il ne DEMONTRE pas a lui seul que la clause cesse d'etre un
miroir : c'est le RENDEMENT publie (forme livree / echelle commandee) qui le dit. Un rendement
identiquement 1.000 voudrait dire que la peau rend exactement ce qu'on injecte, et alors la clause
resterait un miroir malgre le changement de grandeur. Le fichier publie donc le rendement A COTE
du verdict, toujours, et le cycle qui le lit doit trancher sur lui.

NATURE / REPERE / LIGNE DE BASE (les trois questions obligatoires du contrat) :
  NATURE  : trois ETENDUES sans dimension (rapports a la cellule debout), une par axe. Pas une
            amplitude, pas une variance de mouvement : un equilibre tenu ne bouge plus.
            L'etendue primaire est l'ECART-TYPE PONDERE PAR LA MASSE le long de l'axe (lisse,
            porte par tous les sommets) ; l'etendue max-min est publiee A COTE comme sensibilite,
            parce qu'elle ne repose que sur DEUX sommets.
  REPERE  : le triedre de §7 (`out` lateral sortant / `up` haut / `fwd` avant), MESURE sur le rig
            (`breast-com-mass.json` -> `axes`), exprime dans la base de l'ANCRE `chest` prise a
            CHAQUE cellule — donc la rotation d'ensemble du personnage sort de la mesure.
  LIGNE DE BASE : la cellule i=0 est la pose debout d'auteur, ou §9 exige la forme exacte du
            modele. Elle est la REFERENCE des rapports ; ce qui en tient lieu de controle est le
            test de convention de skinning ci-dessous, qui echoue bruyamment si le portage est
            faux.
"""
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
MASSJSON = '.autoport/reports/Grecharged-secondary-motion/breast-com-mass.json'
CHAINS = {'chestL': ['lBoob', 'lBooc'], 'chestR': ['rBoob', 'rBooc']}
ANCHOR = 'chest'

# Les bandes viennent du texte, recopiees avec leur ligne. `sx/sy/sz` = (out, up, fwd), la
# convention de `PHYSORI2` etablie au cycle 90 et reprise telle quelle.
BANDS = {
    '10': dict(cite='l.165-167 « Forward projection: -25 to -35% · Width: +18 to +28% ·'
                    ' Vertical envelope: +5 to +12% »',
               out=(1.18, 1.28), up=(1.05, 1.12), fwd=(0.65, 0.75),
               nom=dict(out=1.23, up=1.09, fwd=0.70)),
    '11': dict(cite='l.179-182 « Root-to-apex length: +18 to +26% · Width: -7 to -13% ·'
                    ' Thickness: -6 to -12% »',
               out=(0.87, 0.93), up=(0.88, 0.94), fwd=(1.18, 1.26),
               nom=dict(out=0.90, up=0.91, fwd=1.23)),
}


def _read_matrices(txt):
    """PHYSORIM -> {(cell, jointslot): 4x4 lignes}, PHYSORIMN -> {slot: nom}."""
    names = {}
    # `~S` de GOAL ecrit la chaine SANS guillemets (verifie sur `PHYSJTWN name=lBoob` dans la
    # trace archivee) : un motif avec guillemets ne matcherait rien et la table serait vide.
    for m in re.finditer(r'^PHYSORIMN j=(\d+) idx=(\d+) name=(\S+)', txt, re.M):
        names[int(m.group(1))] = m.group(3)
    rows = {}
    for m in re.finditer(r'^PHYSORIM i=(\d+) j=(\d+) row=(\d+)'
                         r' x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)', txt, re.M):
        rows.setdefault((int(m.group(1)), int(m.group(2))), {})[int(m.group(3))] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))
    # une matrice n'existe que COMPLETE : quatre lignes, sinon elle n'entre pas.
    mats = {}
    for k, v in rows.items():
        if len(v) == 4:
            M = np.zeros((4, 4))
            for r in range(4):
                M[r, :3] = v[r]
            M[3, 3] = 1.0
            mats[k] = M
    miss = len(re.findall(r'^PHYSORIMMISS ', txt, re.M))
    return names, mats, miss


def _ori2(txt):
    """PHYSORI2 -> {(c,i): (sx,sy,sz)} — les echelles COMMANDEES, pour le rendement."""
    d = {}
    for m in re.finditer(r'^PHYSORI2 c=(\d+) i=(\d+) sx=([-\d.e+]+) sy=([-\d.e+]+)'
                         r' sz=([-\d.e+]+)', txt, re.M):
        d[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                 float(m.group(5)))
    return d


def _roles(txt):
    """La cellule SUPINE et la cellule PRONE, designees par la GRAVITE MESUREE et non par le
    triplet d'echelles — le triplet est un argmin contre les nombres qu'on injecte, donc
    tautologique (meme regle qu'au bloc `_spec10_block`, cycle 123).

    `PHYSORI gx/gy/gz` est la direction de la gravite dans le triedre de §7. SUPINE = couchee sur
    le DOS, donc la gravite pointe vers l'ARRIERE du thorax : `gz > 0` (NOTE-408). PRONE = a plat
    ventre, seins pendants : `gz < 0`. On prend l'argmax de |gz| dans chaque signe."""
    g = {}
    for m in re.finditer(r'^PHYSORI c=(\d+) i=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+)'
                         r' gz=([-\d.e+]+)', txt, re.M):
        g[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                 float(m.group(5)))
    cells = sorted({i for (_c, i) in g})
    sup = pro = None
    for i in cells:
        if i == 0:
            continue
        gz = np.mean([g[(c, i)][2] for c in (0, 1) if (c, i) in g])
        if gz > 0 and (sup is None or gz > sup[1]):
            sup = (i, gz)
        if gz < 0 and (pro is None or gz < pro[1]):
            pro = (i, gz)
    return (sup[0] if sup else None), (pro[0] if pro else None), g


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else \
        '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
    txt = open(os.path.join(REPO, log) if not os.path.isabs(log) else log,
               'r', errors='replace').read()
    jn, mats, nmiss = _read_matrices(txt)
    if not mats:
        print('C124-SHAPE: SUSPENDU — aucune ligne `PHYSORIM` dans cette trace. Rien n\'est'
              ' publie (course anterieure au cycle 124, ou emission absente).')
        return 1
    if nmiss:
        print('C124-SHAPE: SUSPENDU — %d ligne(s) `PHYSORIMMISS` : un joint nomme est introuvable'
              ' dans le rig porte. Un skinning incomplet donnerait une forme plausible et fausse.'
              % nmiss)
        return 1
    slot = {v: k for k, v in jn.items()}
    print('C124-SHAPE: table nom -> slot lue dans la trace : %s'
          % ' '.join('%s=%d' % (v, k) for k, v in sorted(jn.items())))

    g = c6.load_geometry('keira-hd', glb=SHIPPED)
    if g is None:
        print('C124-SHAPE: SUSPENDU — mesh livre absent (%s).' % SHIPPED)
        return 1
    names = list(g['names'])
    V, J, W, P = g['V'], g['J'], g['W'], g['P']
    js, bufs = read_glb(os.path.join(REPO, SHIPPED))
    _nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))
    ai = names.index(ANCHOR)
    R = np.linalg.inv(np.array(ibms[ai], dtype=float))[:3, :3].copy()
    for k in range(3):
        R[:, k] /= np.linalg.norm(R[:, k])
    mass = json.load(open(os.path.join(REPO, MASSJSON)))
    cells = sorted({i for (i, _j) in mats})

    # ---- LA CONVENTION DE SKINNING EST DETERMINEE PAR MESURE, JAMAIS SUPPOSEE ------------------
    # Deux lectures possibles de `skel bones[idx+1].transform` :
    #   A  la matrice porte DEJA l'inverse-bind : p = v_bind . M
    #   B  elle ne le porte pas                 : p = (v_bind . InvBind) . M
    # Se tromper produit un nuage plausible et faux — exactement le mode d'echec que ce dossier
    # paie a chaque fois. Le discriminant : un sommet pese a ~100 % sur `chest` doit tomber a une
    # distance de la TRANSLATION de `chest` comparable a sa distance de bind au joint `chest`.
    # Sous la mauvaise convention, l'inverse-bind est applique une fois de trop (ou pas assez) et
    # l'ecart explose.
    def bindR(j):
        Rj = np.linalg.inv(np.array(ibms[j], dtype=float))[:3, :3].copy()
        for k in range(3):
            Rj[:, k] /= np.linalg.norm(Rj[:, k])
        return Rj

    RB = {n: bindR(names.index(n)) for n in slot}
    wch = (W * (J == ai)).sum(axis=1)
    top = np.argsort(-wch)[:24]
    dbind = np.linalg.norm(V[top] - P[ai], axis=1)
    i0 = cells[0]
    Mch = mats[(i0, slot[ANCHOR])]
    # PIEGE PAYE ICI, ET PUBLIE : les matrices inverse-bind du glTF sont en METRES (translation
    # 1.7141 pour `chest`) alors que `V` et `P` que rend `load_geometry` sont en UNITES DE JEU
    # (7020.8 = 1.7141 x 4096). Les appliquer telles quelles laisse le point a sa distance de
    # l'ORIGINE DU MESH au lieu de sa distance au JOINT — 8766 u au lieu de 1533 — et rend un
    # nuage plausible et faux. On passe donc en local par la POSE DE BIND en unites de jeu
    # (`(v - P_j) . R_j`), qui ne melange aucune unite.
    verdict = {}
    for tag in ('A', 'C'):
        q = V[top].copy() if tag == 'A' else (V[top] - P[ai]) @ RB[ANCHOR]
        p = q @ Mch[:3, :3] + Mch[3, :3]
        dnow = np.linalg.norm(p - Mch[3, :3], axis=1)
        verdict[tag] = float(np.median(np.abs(dnow - dbind) / np.maximum(dbind, 1e-9)))
    conv = min(verdict, key=verdict.get)
    print('C124-SHAPE: CONVENTION DE SKINNING, TRANCHEE PAR MESURE et non supposee — 24 sommets'
          ' peses a %.3f sur `chest` (donc RIGIDEMENT lies a lui) :' % float(np.median(wch[top])))
    print('C124-SHAPE:   A  la matrice porte deja la pose de bind (p = v . M) : ecart median %.5f'
          % verdict['A'])
    print('C124-SHAPE:   C  il faut passer en local de bind d\'abord           : ecart median %.5f'
          % verdict['C'])
    print('C124-SHAPE:   Critere : la distance du sommet a la TRANSLATION de son joint doit valoir'
          ' sa distance de BIND au joint (mediane %.1f u). RETENUE : %s (x%.0f mieux).'
          % (float(np.median(dbind)), conv,
             max(verdict.values()) / max(min(verdict.values()), 1e-9)))
    if verdict[conv] > 0.02:
        print('C124-SHAPE: SUSPENDU — MEME la meilleure convention rend %.5f d\'ecart (seuil'
              ' declare 0.02). Le portage du skinning n\'est pas etabli ; aucune forme n\'est'
              ' publiee.' % verdict[conv])
        return 1
    use_bind = (conv == 'C')

    def xform(x, nmj, i):
        """L'image, a la cellule `i`, de points de BIND rigidement attaches au joint `nmj`.

        C'est le SEUL endroit ou la convention de skinning entre. Tout le reste du fichier en
        est independant, ce qui evite l'erreur que ce dossier paie a repetition : un repere
        reconstruit avec une convention et un nuage avec l'autre donne des nombres plausibles."""
        M = mats[(i, slot[nmj])]
        q = np.atleast_2d(np.asarray(x, dtype=float))
        if use_bind:
            q = (q - P[names.index(nmj)]) @ RB[nmj]
        return q @ M[:3, :3] + M[3, :3]

    def frame(i):
        """La base de l'ANCRE a la cellule `i`, construite en TRANSPORTANT le triedre de bind.

        On n'inverse aucune matrice et on ne suppose rien de sa convention : on prend l'origine
        de l'ancre et trois points a une unite sur les colonnes de `R` (la base de bind de
        `chest`, celle dans laquelle `breast-com-mass.json` exprime les axes de §7), on les fait
        passer par le MEME transport que la peau, et on lit les trois vecteurs images. A la pose
        de bind ce transport est l'identite, donc la base retombe exactement sur celle de la
        sonde de masse : les deux instruments parlent du meme repere, et c'est verifiable."""
        pts = np.vstack([P[ai]] + [P[ai] + R[:, k] for k in range(3)])
        im = xform(pts, ANCHOR, i)
        o = im[0]
        E = np.stack([im[1 + k] - o for k in range(3)], axis=1)   # colonnes = axes
        for k in range(3):
            E[:, k] /= np.linalg.norm(E[:, k])
        return o, E

    def cloud(i, sel):
        """Le nuage de peau DEFORME de `sel`, en base d'ANCRE de la cellule `i`."""
        n = int(sel.sum())
        acc = np.zeros((n, 3))
        wtot = np.zeros(n)
        Js, Ws, Vs = J[sel], W[sel], V[sel]
        for k in range(Ws.shape[1]):
            for nmj in slot:
                m = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                if not m.any():
                    continue
                if (i, slot[nmj]) not in mats:
                    return None
                acc[m] += Ws[m, k][:, None] * xform(Vs[m], nmj, i)
                wtot[m] += Ws[m, k]
        # tout le poids doit etre couvert par les joints emis, sinon le nuage est faux et le
        # dire vaut mieux que publier une forme construite sur 99 % du sommet.
        if float(np.abs(wtot - 1.0).max()) > 1e-3:
            return ('INCOMPLET', float(np.abs(wtot - 1.0).max()))
        o, E = frame(i)
        return (acc - o) @ E          # colonnes de E = axes -> coordonnees dans la base d'ancre

    isup, ipro, gdir = _roles(txt)
    o2 = _ori2(txt)
    print('C124-SHAPE: cellules, designees par la GRAVITE MESUREE (jamais par le triplet'
          ' d\'echelles, qui est un argmin contre ce qu\'on injecte) : SUPINE i=%s · PRONE i=%s'
          % (isup, ipro))

    out = {}
    for ci, (cname, joints) in enumerate(CHAINS.items()):
        idx = [names.index(j) for j in joints]
        wj = np.zeros((len(V), len(idx)))
        for k, ji in enumerate(idx):
            wj[:, k] = (W * (J == ji)).sum(axis=1)
        wsum = wj.sum(axis=1)
        axr = mass['chains'][cname]['axes']
        AX = {a: np.asarray(axr[a], dtype=float) for a in ('out', 'up', 'fwd')}
        for cut, lbl in ((0.0, 'w>0.00'), (0.25, 'w>=0.25')):
            sel = wsum > cut if cut == 0.0 else wsum >= cut
            wv = wsum[sel]
            ext = {}
            for i in cells:
                cl = cloud(i, sel)
                if cl is None:
                    print('C124-SHAPE: %-8s %s cellule i=%d ABSENTE (matrice manquante)'
                          % (cname, lbl, i))
                    continue
                if isinstance(cl, tuple):
                    print('C124-SHAPE: SUSPENDU — le skinning ne se referme pas a 1 (ecart %.4f) :'
                          ' un joint pesant n\'est pas emis. Aucune forme publiee.' % cl[1])
                    return 1
                e = {}
                for a, v in AX.items():
                    x = cl @ v
                    mu = float((wv * x).sum() / wv.sum())
                    e[a] = (math.sqrt(float((wv * (x - mu) ** 2).sum() / wv.sum())),
                            float(x.max() - x.min()))
                ext[i] = e
            if 0 not in ext:
                print('C124-SHAPE: %-8s %s SUSPENDU — pas de cellule i=0 (ligne de base).'
                      % (cname, lbl))
                continue
            for sec, cell in (('10', isup), ('11', ipro)):
                if cell is None or cell not in ext:
                    continue
                b = BANDS[sec]
                cmd = o2.get((ci, cell))
                print('C124-SHAPE: %-8s %s §%s  %s' % (cname, lbl, sec, b['cite']))
                for a, kk in (('fwd', 2), ('out', 0), ('up', 1)):
                    lo, hi = b[a]
                    r_s = ext[cell][a][0] / ext[0][a][0]
                    r_m = ext[cell][a][1] / ext[0][a][1]
                    vd = 'SOUS' if r_s < lo else ('DANS' if r_s <= hi else 'AU-DESSUS')
                    y = (r_s / cmd[kk]) if cmd else float('nan')
                    print('C124-SHAPE: %-8s %s §%s  %-3s  LIVREE %.4f (max-min %.4f)  bande'
                          ' %.2f-%.2f  %-9s | COMMANDEE %.4f  rendement %.4f'
                          % (cname, lbl, sec, a, r_s, r_m, lo, hi, vd,
                             (cmd[kk] if cmd else float('nan')), y))
                    out.setdefault((cname, lbl, sec, a), (r_s, r_m, cmd[kk] if cmd else None, vd))
            # ---- LES DEUX CONTROLES QUI NE SONT PAS TRIVIAUX -------------------------------
            # P6 — LECTURE HORS DEFAUT. Rapporter i=0 a lui-meme rendrait 1.000 par definition et
            # ne prouverait rien. La cellule i=9 est une SECONDE cellule DEBOUT (ajoutee au cycle
            # 120 pour jouer l'echelon debout->prone) : meme gravite que i=0, rien ne les relie
            # dans le balayage. Leur rapport est donc ce que l'instrument lit quand le defaut est
            # ABSENT, et il est MESURE.
            if 9 in ext:
                print('C124-SHAPE: %-8s %s LECTURE HORS DEFAUT — i=9 (2e cellule DEBOUT) / i=0 :'
                      ' %s   (seuil declare 1 %%)'
                      % (cname, lbl, ' · '.join('%s %.4f' % (a, ext[9][a][0] / ext[0][a][0])
                                                for a in ('fwd', 'out', 'up'))))
            # P7 — CONTROLE DE MONTAGE. i=10 est une seconde cellule PRONE, atteinte par un autre
            # chemin du balayage. Deux cellules que rien ne relie doivent rendre la meme forme.
            if 10 in ext and ipro in ext:
                print('C124-SHAPE: %-8s %s CONTROLE DE MONTAGE — i=10 (2e cellule PRONE) contre'
                      ' i=%s : %s   (seuil declare 3 %%)'
                      % (cname, lbl, ipro,
                         ' · '.join('%s %+.2f %%'
                                    % (a, (ext[10][a][0] / ext[ipro][a][0] - 1.0) * 100.0)
                                    for a in ('fwd', 'out', 'up'))))
    # ---- LES DEUX TESTS QUI DECIDENT SI CETTE MESURE VAUT QUELQUE CHOSE -----------------------
    ys = [abs(v[0] / v[2] - 1.0) for v in out.values() if v[2]]
    vds = [v[3] for v in out.values()]
    print('C124-SHAPE: ------------------------------------------------------------------')
    print('C124-SHAPE: TEST DE MIROIR (P3) — ecart du rendement a 1 : median %.4f  max %.4f'
          ' sur %d cellules.' % (float(np.median(ys)), float(np.max(ys)), len(ys)))
    print('C124-SHAPE:   Un rendement identiquement 1.000 voudrait dire que la peau rend'
          ' exactement l\'echelle injectee : la clause resterait un MIROIR malgre le changement')
    print('C124-SHAPE:   de grandeur. Seuil declare AVANT la course : > 3 %% sur au moins une'
          ' cellule.  -> %s' % ('TENUE' if max(ys) > 0.03 else 'REFUTEE'))
    print('C124-SHAPE: TEST DE FALSIFIABILITE (P4) — verdicts rendus : %s'
          % ' '.join('%s=%d' % (k, vds.count(k)) for k in ('SOUS', 'DANS', 'AU-DESSUS')))
    print('C124-SHAPE:   Un instrument qui ne peut pas echouer ne vaut rien. Seuil declare AVANT'
          ' la course : au moins une cellule HORS bande.  -> %s'
          % ('TENUE' if any(v != 'DANS' for v in vds) else 'REFUTEE'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
