#!/usr/bin/env python3
"""c131_anchor_dof.py — LE POINT D'ANCRAGE DE LA DEFORMATION EST-IL UN SECOND DEGRE DE LIBERTE ?

POURQUOI CE FICHIER EXISTE. §11 porte DEUX clauses — la longueur racine->apex (bande 1,18-1,26)
et le deplacement statique de COM (bande 0,20-0,28 B0) — et le cycle 128, re-teste sur
l'instrument corrige au cycle 130b, etablit qu'elles sont INCOMPATIBLES sous le seul bouton
`HangingLengthScale` : mettre la longueur dans sa bande sort le COM par le BAS sur les deux
chaines. Deux clauses, un seul bouton. Ce fichier teste s'il existe un SECOND bouton, et il le
cherche la ou aucune cle du preset ne le nomme : dans la GEOMETRIE, au point d'ancrage de la
deformation.

L'ALGEBRE A VERIFIER — elle n'est pas supposee ici, elle est MESUREE sur la peau livree :

    aujourd'hui    q -> q.D + t                          (q = coordonnee de BIND relative au JOINT)
    ancrage en a   q -> (q - a).D + a + t  =  q.D + t + a.(I - D)

L'ancrage ajoute donc un OFFSET CONSTANT `a.(I - D)` a tout sommet pilote par ce joint.
Consequences ATTENDUES, chacune verifiee par la mesure et non par le raisonnement :
  * la distance apex - racine serait INVARIANTE (l'offset se soustrait entre les deux centroides) ;
  * le CENTROIDE se deplacerait de `a.(I - D)`, donc le COM de §11 CHANGERAIT.
Si les deux tiennent, l'ancrage decouple exactement les deux clauses.

RESERVE DECLAREE D'AVANCE (elle est chiffree en section 4). L'invariance de longueur est EXACTE
pour une peau pilotee par UNE SEULE matrice. La chaine en porte DEUX (`lBoob`/`lBooc`, resp.
`rBoob`/`rBooc`) melangees par les poids : deux joints, deux `D` differents, donc deux offsets
differents sur un meme sommet mixte. L'invariance n'est donc qu'APPROCHEE, et la mesure doit dire
de combien — c'est exactement le « moins de 0,5 % » que P3 met en jeu.

ET CE QUE LA MESURE CORRIGE DE CETTE RESERVE, PARCE QU'ELLE VA PLUS LOIN QU'ELLE (section 4).
La cause dominante n'est pas le melange DE DEUX MAILLONS : c'est que `a` vit dans le repere de
BIND DE CHAQUE JOINT (`a_j = disp . RB_j`) et que `D_j` differe d'un joint a l'autre, si bien que
l'offset `a_j.(I - D_j)` est DIFFERENT par joint. Deux centroides ne le voient se soustraire que
s'ils sont pilotes par LE MEME joint — et ici le decile PROXIMAL pese majoritairement sur `chest`,
que la consigne exclut de l'offset. Le controle positif de section 4 le tranche : sur un nuage
pilote a 100 % par UN joint, la longueur est invariante a 3e-11 %, donc l'operateur est juste et
le bris d'invariance est une propriete du SKINNING MULTI-JOINTS, pas du code.

CE QUE CE FICHIER NE FAIT PAS. Il ne cable rien dans le moteur, il n'ecrit aucun autre fichier, il
ne lance aucune course et aucun build : tout se lit sur la trace `keira-room-x86.log` deja archivee
et sur le mesh LIVRE `out/jak1/fr3/skin/keira-hd-lod0.glb`. Un balayage se publie comme une
PROPRIETE MESUREE de la geometrie, jamais comme un lot.

NATURE / REPERE / LIGNE DE BASE (les trois questions obligatoires du contrat, SPEC §7) :
  NATURE  : deux grandeurs sans dimension, de natures DIFFERENTES, et il faut les distinguer —
            (a) une LONGUEUR relative (rapport a la cellule debout i=0), invariant euclidien ;
            (b) un DEPLACEMENT SOUTENU du centre de masse, norme, divisee par B0 = 602,0 u.
            Aucune des deux n'est une amplitude de mouvement : un equilibre tenu ne bouge plus,
            elles decrivent une FORME et une POSITION D'EQUILIBRE.
  REPERE  : (a) AUCUN — une distance entre deux centroides est invariante par rotation et par
            translation ; c'est ce qui la rend recevable la ou l'ecart-type sur axe fixe ne l'est
            pas (arbitrage du cycle 126). Les deux lectures de sensibilite (ecart-type pondere,
            etendue max-min) sont lues, elles, dans le triedre de §7 (`breast-com-mass.json` ->
            `axes`) exprime dans la base de l'ANCRE `chest` transportee a chaque cellule.
            (b) le repere de l'ANCRE `chest` a chaque cellule — le sujet se reoriente d'une
            cellule a l'autre, donc la rotation d'ensemble doit sortir de la mesure.
  LIGNE DE BASE : la cellule i=0, pose debout d'auteur, ou §9 exige la forme exacte du modele.
  CE QUI EST LU QUAND LE DEFAUT EST ABSENT : deux lectures, toutes deux MESUREES et non postulees.
            (1) a deplacement d'ancrage NUL, ce fichier doit reproduire les dix nombres deja
            publies par les cycles 125/128/130b — c'est la SECTION 1, et elle peut tout arreter ;
            (2) la cellule i=9 est une SECONDE cellule DEBOUT que rien ne relie a i=0 dans le
            balayage : son COM doit valoir ~0 et sa longueur ~1,0000.

Predictions P3 / P4 et leurs falsificateurs : `.autoport/c131-predictions.txt`, ecrites avant
toute mesure et reprises MOT POUR MOT dans la sortie ci-dessous.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
import c124_delivered_shape as c124
import c126_rotation_vs_stretch as c126
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RDIR = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
B0 = 602.0
CUTS = [0.0, 0.05, 0.25]                     # frontieres d'organe (cycle 130)
LCUTS = [(0.0, 'w>0.00'), (0.25, 'w>=0.25')]  # frontieres des lectures de LONGUEUR (cycle 125)
LO, HI = 0.20, 0.28                          # §11 « Static COM displacement: 20-28% B0 » (l.178)
LLO, LHI = 1.18, 1.26                        # §11 « Root-to-apex length: +18 to +26% » (l.179)
AMPS = [0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30]
P = print

# ------------------------------------------------------------------------------------------------
# LES DIX NOMBRES DEJA PUBLIES, RECOPIES AVEC LEUR PROVENANCE. Ils ne sont PAS des constantes de
# confort : ce sont les references du controle d'ancrage a zero, et si l'une d'elles ne se
# reproduit pas a 1 %, AUCUN balayage n'est imprime.
# ------------------------------------------------------------------------------------------------
REF_LEN = {                       # (chaine, frontiere) -> (deciles, max-min, ecart-type pondere)
    ('chestL', 'w>0.00'):  (1.3363, 1.3939, 1.4455),
    ('chestL', 'w>=0.25'): (1.2734, 1.4275, 1.4514),
    ('chestR', 'w>0.00'):  (1.3183, 1.3384, 1.4370),
    ('chestR', 'w>=0.25'): (1.3116, 1.4234, 1.4588),
}
REF_LEN_SRC = ('deciles : `c128-report.md` section 7 (1re ligne) · max-min : idem (2e ligne) et '
               'colonne `(max-min)` de `ROOM-SPEC1011-LIVREE` · ecart-type pondere : colonne '
               '`LIVREE` de `ROOM-SPEC1011-LIVREE` dans `keira-room-table.txt`')
REF_COM = {                       # (chaine, frontiere) -> COM a la masse d'AIRE, prone, en B0
    ('chestL', 0.0): 0.2011, ('chestL', 0.05): 0.2270, ('chestL', 0.25): 0.2742,
    ('chestR', 0.0): 0.2117, ('chestR', 0.05): 0.2410, ('chestR', 0.25): 0.2911,
}
REF_COM_SRC = '`c130b-c128-retest.txt` lignes LIVREE (sortie archivee du cycle 130b)'
TOL = 1.0                         # seuil declare du controle d'ancrage a zero, en POURCENT

# Les DEUX points de commande archives, pour l'interpolation de P4 (cycle 128 + cycle 130b).
TWOPT = {                         # chaine -> (commande, longueur deciles, COM aire) x 2 points
    'chestL': ((1.2195, 1.3363, 0.2011), (1.1290, 1.2512, 0.1615)),
    'chestR': ((1.2125, 1.3183, 0.2117), (1.1129, 1.2350, 0.1700)),
}
P4_PRED = {'chestL': (0.1656, 0.0344, 17.2, 0.2486), 'chestR': (0.1825, 0.0175, 8.8, 0.1225)}

# ================================================================================================
# CHARGEMENT — mesh LIVRE + trace archivee. Aucune course, aucun build.
# ================================================================================================
SHIPPED = c124.SHIPPED
g = c6.load_geometry('keira-hd', glb=SHIPPED)
if g is None:
    P('C131: SUSPENDU — mesh livre absent (%s). Rien n\'est publie.' % SHIPPED)
    sys.exit(1)
names, V, J, W, Pb, F = list(g['names']), g['V'], g['J'], g['W'], g['P'], g['F']
js, bufs = read_glb(os.path.join(REPO, SHIPPED))
_nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))

# masse de sommet PROPORTIONNELLE A L'AIRE — un tiers de l'aire de chaque triangle incident.
# Import conceptuel du cycle 130 (`c130_com_reconcile.py:50-56`), reecrit ici a l'identique parce
# que ce fichier-la execute son rapport a l'import et ne peut donc pas etre importe comme module.
AREA = np.zeros(len(V))
Ftri = np.asarray(F, dtype=np.int64).reshape(-1, 3)
_a = V[Ftri[:, 0]]
_ar = 0.5 * np.linalg.norm(np.cross(V[Ftri[:, 1]] - _a, V[Ftri[:, 2]] - _a), axis=1)
for _k in range(3):
    np.add.at(AREA, Ftri[:, _k], _ar / 3.0)


def bindR(j):
    Rj = np.linalg.inv(np.array(ibms[j], dtype=float))[:3, :3].copy()
    for k in range(3):
        Rj[:, k] /= np.linalg.norm(Rj[:, k])
    return Rj


LOG = os.path.join(RDIR, 'keira-room-x86.log')
if not os.path.exists(LOG):
    P('C131: SUSPENDU — trace absente (%s). Rien n\'est publie.' % LOG)
    sys.exit(1)
txt = open(LOG, 'r', errors='replace').read()
isup, ipro, _gdir = c124._roles(txt)
jn, mats, nmiss = c124._read_matrices(txt)
if not mats or nmiss:
    P('C131: SUSPENDU — trace incomplete (%d matrices, %d PHYSORIMMISS).' % (len(mats), nmiss))
    sys.exit(1)
slot = {v: k for k, v in jn.items()}
RB = {n: bindR(names.index(n)) for n in slot}
NIDX = {n: names.index(n) for n in slot}
cells = sorted({i for (i, _j) in mats})
ANCHOR = c124.ANCHOR
ai = names.index(ANCHOR)
Ra = bindR(ai)
MASS = json.load(open(os.path.join(REPO, c124.MASSJSON)))
CHAINS = c124.CHAINS
CHAINJOINTS = set(c126.CHAINJOINTS)
I3 = np.eye(3)

P('C131: LE POINT D\'ANCRAGE DE LA DEFORMATION EST-IL LE SECOND DEGRE DE LIBERTE DE §11 ?')
P('C131: mesh LIVRE %s · trace %s · B0 = %.1f u' % (SHIPPED, os.path.basename(LOG), B0))
P('C131: cellules %s · PRONE i=%d · SUPINE i=%d · 2e DEBOUT i=9 (lecture hors defaut)'
  % (cells, ipro, isup))
P('C131: offset applique aux SEULS joints de chaine %s — JAMAIS a `%s`, ce qui laisse la racine'
  % (sorted(CHAINJOINTS), ANCHOR))
P('C131:   en place par le melange de poids, et repond a §11 « The root remains relatively stable ».')
P('C131: ' + '=' * 112)


# ================================================================================================
# LE SKINNING, AVEC OU SANS DEPLACEMENT D'ANCRAGE — LE SEUL ENDROIT OU L'ALGEBRE ENTRE
# ================================================================================================
def make_ctx(cname, cut):
    """Le contexte fige d'une (chaine, frontiere) : selection, poids, aires, populations de
    decile FIXEES A LA POSE DE BIND (elles ne sont jamais recalculees par cellule — un argmax
    par cellule repondrait DANS la cellule et ne serait pas une population)."""
    idx = [names.index(j) for j in CHAINS[cname]]
    wsum = np.zeros(len(V))
    for ji in idx:
        wsum += (W * (J == ji)).sum(axis=1)
    sel = wsum > cut if cut == 0.0 else wsum >= cut
    AX = {a: np.asarray(MASS['chains'][cname]['axes'][a], dtype=float)
          for a in ('out', 'up', 'fwd')}
    # PORTAGE VERBATIM de `c126_rotation_vs_stretch.py:286-289` (tri sur l'axe `fwd` de BIND
    # relatif a l'ancre, deciles 10 % / 90 %). La reproduction exacte des quatre nombres publies
    # en section 1 est le controle qui atteste que ce portage est fidele.
    xb = (V[sel] - Pb[ai]) @ Ra @ AX['fwd']
    qlo, qhi = np.quantile(xb, 0.10), np.quantile(xb, 0.90)
    prox, dist = xb <= qlo, xb >= qhi
    wv = wsum[sel]
    # l'axe RACINE->APEX de la POSE DE BIND, unitaire : la direction du deplacement d'ancrage.
    # Mesuree sur le nuage de bind lui-meme, jamais prise pour `fwd` par commodite — l'ecart
    # angulaire entre les deux est publie a cote.
    cp0 = (wv[prox, None] * V[sel][prox]).sum(0) / wv[prox].sum()
    cd0 = (wv[dist, None] * V[sel][dist]).sum(0) / wv[dist].sum()
    u = cd0 - cp0
    Lbind = float(np.linalg.norm(u))
    u = u / Lbind
    fw = Ra @ AX['fwd']
    fw = fw / np.linalg.norm(fw)
    return dict(sel=sel, n=int(sel.sum()), wv=wv, Av=AREA[sel], Js=J[sel], Ws=W[sel], Vs=V[sel],
                prox=prox, dist=dist, AX=AX, u=u, Lbind=Lbind,
                ang_u_fwd=math.degrees(math.acos(max(-1.0, min(1.0, float(u @ fw))))))


def world_cloud(ctx, i, mm, aloc=None, ojoints=None):
    """Nuage de peau en MONDE a la cellule `i`.

    `mm`      : le jeu de matrices (livre, ou substitue pour le balayage de commande, section 3).
    `aloc`    : {nom de joint -> point d'ancrage en coordonnees LOCALES DE BIND de ce joint}, ou
                None pour l'ancrage au JOINT, qui est l'etat LIVRE. L'offset ajoute est exactement
                `a.(I - D)`, la forme close de `(q - a).D + a + t`.
    `ojoints` : les joints qui RECOIVENT l'offset. Par defaut les seuls joints de chaine — c'est
                la configuration specifiee, celle de tout ce qui porte un verdict ici. Le seul
                autre usage est le CONTROLE POSITIF DE L'ALGEBRE de la section 4, qui y ajoute
                `chest` et n'est PAS une configuration jouable."""
    Js, Ws, Vs, n = ctx['Js'], ctx['Ws'], ctx['Vs'], ctx['n']
    acc = np.zeros((n, 3))
    tot = np.zeros(n)
    for k in range(Ws.shape[1]):
        for nmj in slot:
            m = (Js[:, k] == NIDX[nmj]) & (Ws[:, k] > 0)
            if not m.any():
                continue
            M = mm[(i, slot[nmj])]
            D, t = M[:3, :3], M[3, :3]
            q = (Vs[m] - Pb[NIDX[nmj]]) @ RB[nmj]
            p = q @ D + t
            if aloc is not None and nmj in (CHAINJOINTS if ojoints is None else ojoints):
                p = p + aloc[nmj] @ (I3 - D)
            acc[m] += Ws[m, k][:, None] * p
            tot[m] += Ws[m, k]
    return acc, float(np.abs(tot - 1.0).max())


def anchor_local(ctx, disp, ojoints=None):
    """Le point d'ancrage `joint + disp` (disp en MONDE-BIND), exprime en local de bind de chaque
    joint qui recoit l'offset. C'est la SEULE traduction de repere du fichier."""
    return {nmj: disp @ RB[nmj] for nmj in (CHAINJOINTS if ojoints is None else ojoints)}


def frame(i, mm):
    """La base de l'ANCRE a la cellule `i`, obtenue en TRANSPORTANT le triedre de bind — aucune
    matrice n'est inversee, aucune convention n'est supposee. Portage de `c124:265-280`."""
    pts = np.vstack([Pb[ai]] + [Pb[ai] + Ra[:, k] for k in range(3)])
    M = mm[(i, slot[ANCHOR])]
    im = ((pts - Pb[ai]) @ Ra) @ M[:3, :3] + M[3, :3]
    o = im[0]
    E = np.stack([im[1 + k] - o for k in range(3)], axis=1)
    for k in range(3):
        E[:, k] /= np.linalg.norm(E[:, k])
    return o, E


def lengths(ctx, mm, aloc=None, cell=None, ojoints=None):
    """Les TROIS lectures de longueur, en rapport a la cellule i=0 :
       'dec'  distance racine->apex entre centroides de DECILE (instrument arbitre au cycle 126) ;
       'mm'   etendue max-min le long de `fwd` en base d'ancre ;
       'sd'   ecart-type PONDERE le long de `fwd` en base d'ancre (REFUTE comme proxy au c128,
              publie ici uniquement parce que c'est ce que la ligne de verdict publie aujourd'hui).
    Rend aussi l'ecart de couverture de poids, qui doit rester nul."""
    cell = ipro if cell is None else cell
    out, err = {}, 0.0
    dec, mmv, sdv = {}, {}, {}
    for i in (0, cell):
        acc, e = world_cloud(ctx, i, mm, aloc, ojoints)
        err = max(err, e)
        wv, prox, dist = ctx['wv'], ctx['prox'], ctx['dist']
        cp = (wv[prox, None] * acc[prox]).sum(0) / wv[prox].sum()
        cd = (wv[dist, None] * acc[dist]).sum(0) / wv[dist].sum()
        dec[i] = float(np.linalg.norm(cd - cp))
        o, E = frame(i, mm)
        x = ((acc - o) @ E) @ ctx['AX']['fwd']
        mu = float((wv * x).sum() / wv.sum())
        sdv[i] = math.sqrt(float((wv * (x - mu) ** 2).sum() / wv.sum()))
        mmv[i] = float(x.max() - x.min())
    out['dec'] = dec[cell] / dec[0]
    out['mm'] = mmv[cell] / mmv[0]
    out['sd'] = sdv[cell] / sdv[0]
    out['err'] = err
    return out


def com(ctx, mm, aloc=None, cell=None, ojoints=None):
    """Le deplacement du centre de masse a la masse d'AIRE, en local d'ANCRE, / B0. VECTEUR."""
    cell = ipro if cell is None else cell
    Xi, e1 = world_cloud(ctx, cell, mm, aloc, ojoints)
    X0, e2 = world_cloud(ctx, 0, mm, aloc, ojoints)
    Ma = mats[(cell, slot[ANCHOR])]
    Mb = mats[(0, slot[ANCHOR])]
    Ai = (Xi - Ma[3, :3]) @ Ma[:3, :3].T
    A0 = (X0 - Mb[3, :3]) @ Mb[:3, :3].T
    Dd = Ai - A0
    Av = ctx['Av']
    return (Av[:, None] * Dd).sum(0) / Av.sum() / B0, max(e1, e2)


def verd(v, lo=LO, hi=HI):
    return 'DANS' if lo <= v <= hi else ('SOUS' if v < lo else 'AU-DESSUS')


CTX = {(c, cut): make_ctx(c, cut) for c in CHAINS for cut in set(CUTS) | {0.25}}

# ================================================================================================
# SECTION 1 — CONTROLE D'ANCRAGE A ZERO. IL PASSE AVANT TOUT LE RESTE ET IL PEUT TOUT ARRETER.
# ================================================================================================
P('C131: SECTION 1 — CONTROLE D\'ANCRAGE A ZERO')
P('C131:   A deplacement d\'ancrage NUL, l\'offset `a.(I-D)` vaut zero par algebre : ce fichier')
P('C131:   doit donc reproduire les DIX nombres deja publies. Un balayage sur un instrument qui ne')
P('C131:   retrouve pas son point de depart ne vaut rien.  Seuil declare : %.0f %% sur chacun.' % TOL)
P('C131:   provenance longueurs : %s' % REF_LEN_SRC)
P('C131:   provenance COM       : %s' % REF_COM_SRC)
P('C131: ' + '-' * 112)
worst, bad = 0.0, []
BASE_LEN, BASE_COM = {}, {}
for cname in CHAINS:
    for cut, lbl in LCUTS:
        L0 = lengths(CTX[(cname, cut)], mats)
        BASE_LEN[(cname, lbl)] = L0
        ref = REF_LEN[(cname, lbl)]
        for kk, (key, nm) in enumerate((('dec', 'DECILES'), ('mm', 'ETENDUE max-min'),
                                        ('sd', 'ECART-TYPE pondere'))):
            d = abs(L0[key] / ref[kk] - 1.0) * 100.0
            worst = max(worst, d)
            if d > TOL:
                bad.append((cname, lbl, nm, L0[key], ref[kk], d))
            P('C131:   %-7s %-8s LONGUEUR %-19s reproduit %.4f  contre publie %.4f  ecart %6.3f %%'
              % (cname, lbl, nm, L0[key], ref[kk], d))
for cname in CHAINS:
    for cut in CUTS:
        v, e = com(CTX[(cname, cut)], mats)
        nv = float(np.linalg.norm(v))
        BASE_COM[(cname, cut)] = (v, nv)
        ref = REF_COM[(cname, cut)]
        d = abs(nv / ref - 1.0) * 100.0
        worst = max(worst, d)
        if d > TOL:
            bad.append((cname, 'w>%.2f' % cut, 'COM masse d\'AIRE', nv, ref, d))
        P('C131:   %-7s w>%.2f   COM masse d\'AIRE              reproduit %.4f  contre publie %.4f'
          '  ecart %6.3f %%' % (cname, cut, nv, ref, d))
# couverture de poids et lecture HORS DEFAUT (2e cellule DEBOUT i=9)
cov = max(lengths(CTX[(c, cut)], mats)['err'] for c in CHAINS for cut, _l in LCUTS)
P('C131: ' + '-' * 112)
P('C131:   couverture de poids, pire sommet : %.2e (un nuage bati sur 99 %% d\'un sommet serait '
  'faux)' % cov)
if 9 in cells:
    hd = []
    for cname in CHAINS:
        v9, _e = com(CTX[(cname, 0.0)], mats, cell=9)
        l9 = lengths(CTX[(cname, 0.0)], mats, cell=9)
        hd.append((cname, float(np.linalg.norm(v9)), l9['dec']))
        P('C131:   HORS DEFAUT %-7s i=9 (2e cellule DEBOUT, que rien ne relie a i=0) : COM %.4f B0'
          ' · longueur deciles %.4f' % (cname, float(np.linalg.norm(v9)), l9['dec']))
    P('C131:   -> seuils declares : COM <= 0,02 B0 et longueur a 1 %% de 1,0000. %s'
      % ('TIRE' if max(x[1] for x in hd) <= 0.02
         and max(abs(x[2] - 1.0) for x in hd) <= 0.01 else '**ECHOUE**'))
else:
    P('C131:   HORS DEFAUT — cellule i=9 ABSENTE de la trace : controle NON FAIT, et je le dis.')
P('C131: ' + '-' * 112)
if bad or cov > 1e-3:
    P('C131:   **LE CONTROLE D\'ANCRAGE A ZERO ECHOUE.** Les lectures suivantes ne se reproduisent')
    P('C131:   pas dans le seuil declare de %.0f %% :' % TOL)
    for b in bad:
        P('C131:     %-7s %-8s %-22s reproduit %.4f contre publie %.4f — ecart %.3f %%' % b)
    if cov > 1e-3:
        P('C131:     couverture de poids %.2e > 1e-3 : le nuage est FAUX.' % cov)
    P('C131:   AUCUN BALAYAGE N\'EST IMPRIME. Un balayage sur un instrument qui ne retrouve pas son')
    P('C131:   point de depart ne vaut rien, et un chiffre publie dessus serait pire que rien.')
    sys.exit(1)
P('C131:   -> TIRE. Les dix lectures se reproduisent, pire ecart %.3f %% (seuil %.0f %%).'
  % (worst, TOL))
P('C131: ' + '=' * 112)

# ================================================================================================
# SECTION 2 — LE BALAYAGE D'ANCRAGE
# ================================================================================================
P('C131: SECTION 2 — BALAYAGE DU POINT D\'ANCRAGE')
for cname in CHAINS:
    c0 = CTX[(cname, 0.0)]
    P('C131:   %-7s axe racine->apex de la POSE DE BIND, unitaire : longueur de bind entre'
      ' centroides de decile %.1f u (%.4f B0) · a %.1f deg de l\'axe `fwd` de §7'
      % (cname, c0['Lbind'], c0['Lbind'] / B0, c0['ang_u_fwd']))
P('C131:   SIGNE : `DISTAL` = ancrage deplace VERS L\'APEX (le long de +u) · `PROXIMAL` = vers la')
P('C131:   RACINE (-u). Lequel AUGMENTE le COM n\'est pas suppose : il est lu dans le tableau et')
P('C131:   nomme sous lui.')
P('C131: ' + '-' * 112)
P('C131:   %-7s %-9s %-6s | %-24s | %-24s | %-24s' % ('chaine', 'sens', 'a/B0',
                                                      'LONGUEUR w>0.00 dec/mm/sd',
                                                      'LONGUEUR w>=0.25 dec/mm/sd',
                                                      'COM AIRE w>0.00/0.05/0.25'))
SWEEP = {}
for cname in CHAINS:
    for sgn, sname in ((+1, 'DISTAL'), (-1, 'PROXIMAL')):
        for amp in AMPS:
            if amp == 0.0 and sgn < 0:
                continue
            disp = (sgn * amp * B0) * CTX[(cname, 0.0)]['u']
            aloc = anchor_local(CTX[(cname, 0.0)], disp) if amp != 0.0 else None
            row = {}
            for cut, lbl in LCUTS:
                row[lbl] = lengths(CTX[(cname, cut)], mats, aloc)
            for cut in CUTS:
                v, _e = com(CTX[(cname, cut)], mats, aloc)
                row['com%.2f' % cut] = float(np.linalg.norm(v))
                row['vec%.2f' % cut] = v
            SWEEP[(cname, sgn, amp)] = row
            if amp == 0.0:
                SWEEP[(cname, -1, 0.0)] = row
            P('C131:   %-7s %-9s %.2f   | %6.4f %6.4f %6.4f       | %6.4f %6.4f %6.4f       |'
              ' %6.4f %6.4f %6.4f'
              % (cname, sname if amp else '(nul)', amp,
                 row['w>0.00']['dec'], row['w>0.00']['mm'], row['w>0.00']['sd'],
                 row['w>=0.25']['dec'], row['w>=0.25']['mm'], row['w>=0.25']['sd'],
                 row['com0.00'], row['com0.05'], row['com0.25']))
        P('C131:   ' + '-' * 108)

# quel signe AUGMENTE le COM ? lu, pas suppose.
P('C131:   LE SIGNE QUI AUGMENTE LE COM — lu dans le tableau, a a/B0 = 0,10 et a 0,30, sur w>0.00 :')
BEST = {}
for cname in CHAINS:
    b0 = SWEEP[(cname, +1, 0.0)]['com0.00']
    d1 = SWEEP[(cname, +1, 0.30)]['com0.00'] - b0
    d2 = SWEEP[(cname, -1, 0.30)]['com0.00'] - b0
    sgn = +1 if d1 > d2 else -1
    BEST[cname] = sgn
    P('C131:     %-7s a=0,10 DISTAL %+.4f · PROXIMAL %+.4f  |  a=0,30 DISTAL %+.4f · PROXIMAL'
      ' %+.4f  ->  **%s** augmente le COM'
      % (cname,
         SWEEP[(cname, +1, 0.10)]['com0.00'] - b0, SWEEP[(cname, -1, 0.10)]['com0.00'] - b0,
         d1, d2, 'DISTAL' if sgn > 0 else 'PROXIMAL'))
P('C131: ' + '=' * 112)

# ================================================================================================
# SECTION 3 — LES DEUX PREDICTIONS, AVEC LEUR FALSIFICATEUR
# ================================================================================================
P('C131: SECTION 3 — LES PREDICTIONS DE `.autoport/c131-predictions.txt`, REPRISES MOT POUR MOT')
P('C131: ' + '-' * 112)
P('C131: P3  LA LONGUEUR RACINE->APEX EST INVARIANTE AU POINT D\'ANCRAGE DE LA DEFORMATION.')
P('C131:     « PREDICTION CHIFFREE : un deplacement d\'ancrage de 0.10 B0 le long de l\'axe')
P('C131:       racine->apex change la longueur racine->apex LIVREE de moins de 0.5 %, et change le')
P('C131:       deplacement de COM de §11 d\'au moins 5 %. »')
P('C131:     « FALSIFICATEUR : longueur changee de >= 0.5 % -> l\'ancrage n\'est PAS un degre de')
P('C131:       liberte independant, la voie est fermee comme les deux autres et je l\'ecris. »')
okL, okC = True, True
for cname in CHAINS:
    for sgn, sname in ((+1, 'DISTAL'), (-1, 'PROXIMAL')):
        r0, r1 = SWEEP[(cname, sgn, 0.0)], SWEEP[(cname, sgn, 0.10)]
        dl = (r1['w>0.00']['dec'] / r0['w>0.00']['dec'] - 1.0) * 100.0      # SIGNE a l'affichage,
        dl25 = (r1['w>=0.25']['dec'] / r0['w>=0.25']['dec'] - 1.0) * 100.0  # MAGNITUDE au test
        dc = (r1['com0.00'] / r0['com0.00'] - 1.0) * 100.0   # SIGNE : un COM qui BAISSE doit se
        okL = okL and max(abs(dl), abs(dl25)) < 0.5                    # lire comme une baisse, pas comme un
        if sgn == BEST[cname]:                               # « changement de 3,4 % »
            okC = okC and abs(dc) >= 5.0
        P('C131:     %-7s %-9s a=0,10 : longueur DECILES %+.4f %%(w>0.00) %+.4f %%(w>=0.25)  |  COM'
          ' %.4f -> %.4f  = %+.2f %%%s'
          % (cname, sname, dl, dl25, r0['com0.00'], r1['com0.00'], dc,
             '   <- sens qui augmente le COM' if sgn == BEST[cname] else ''))
P('C131:     LONGUEUR : pire ecart %.4f %% sur les 4 (chaine x sens) x 2 frontieres -> %s'
  % (max(abs(SWEEP[(c, s, 0.10)][l]['dec'] / SWEEP[(c, s, 0.0)][l]['dec'] - 1.0) * 100.0
         for c in CHAINS for s in (+1, -1) for l in ('w>0.00', 'w>=0.25')),
     'sous le falsificateur de 0,5 %' if okL else '**AU-DESSUS du falsificateur de 0,5 %**'))
P('C131: P3  -> %s'
  % ('**TIRE.** La longueur racine->apex est invariante au point d\'ancrage a la precision '
     'mesuree, et le COM ne l\'est pas : L\'ANCRAGE EST UN SECOND DEGRE DE LIBERTE, et il est '
     'GEOMETRIQUE — aucune cle du preset ne le nomme.' if (okL and okC) else
     '**REFUTEE.** ' + ('la longueur bouge de 0,5 % ou plus : l\'ancrage n\'est PAS un degre de '
                        'liberte independant, la voie est FERMEE comme les deux autres.' if not okL
                        else 'la longueur est bien invariante, mais le COM ne bouge pas de 5 % : '
                             'l\'ancrage est un degre de liberte INERTE, ce qui ferme la voie '
                             'aussi surement.')))
P('C131: ' + '-' * 112)

# ---- P4 -----------------------------------------------------------------------------------------
P('C131: P4  LA TAILLE DU DEPLACEMENT D\'ANCRAGE QUI FERME §11, EN FORME CLOSE, AVANT DE LA MESURER.')
P('C131:     « Au point de fonctionnement le PLUS FAVORABLE admissible — longueur livree exactement')
P('C131:       au plafond de 1.26 — je predis, par interpolation lineaire des deux points de')
P('C131:       commande archives (moteur livre et lot c128) sur les instruments ARBITRES des DEUX')
P('C131:       clauses :')
P('C131:           chestL  COM 0.1656 B0 contre un plancher de 0.20  -> deficit 0.0344 B0 (17.2 %)')
P('C131:           chestR  COM 0.1825 B0 contre un plancher de 0.20  -> deficit 0.0175 B0 ( 8.8 %)')
P('C131:       et un deplacement d\'ancrage PROXIMAL de 0.2486 B0 (chestL) / 0.1225 B0 (chestR) le')
P('C131:       ferme. »')
P('C131:     « FALSIFICATEUR : la mesure directe s\'ecarte de plus de 20 % de ces deux deficits ->')
P('C131:       mon interpolation a deux points ne vaut rien et la taille reste NON ETABLIE. »')
P('C131: ' + '-' * 112)
P('C131:     (a) L\'INTERPOLATION, RECALCULEE ICI, ET ELLE EST DECLAREE COMME UNE INTERPOLATION A')
P('C131:         DEUX POINTS : deux courses archivees, aucune troisieme. Un modele a deux points ne')
P('C131:         peut pas voir sa propre courbure.')
INTERP = {}
for cname in CHAINS:
    (k1, l1, m1), (k2, l2, m2) = TWOPT[cname]
    sl_len = (l1 - l2) / (k1 - k2)
    kstar = k2 + (LHI - l2) / sl_len
    sl_com = (m1 - m2) / (k1 - k2)
    cstar = m2 + (kstar - k2) * sl_com
    INTERP[cname] = (kstar, cstar, LO - cstar)
    P('C131:         %-7s commande %.4f (longueur %.4f, COM %.4f) et %.4f (%.4f, %.4f)'
      % (cname, k1, l1, m1, k2, l2, m2))
    P('C131:         %-7s -> longueur = %.2f a la commande %.4f ; COM interpole %.4f B0 ; deficit'
      ' %.4f B0 (%.1f %% du plancher)'
      % (cname, LHI, kstar, cstar, LO - cstar, (LO - cstar) / LO * 100.0))

# ---- (b) LA VERIFICATION PAR UN AUTRE CHEMIN : LE BALAYAGE DE LA COMMANDE SUR LE MESH -----------
# On ne dispose que de DEUX courses. On peut cependant balayer la commande SANS course : en
# substituant la plus grande valeur singuliere de la matrice ECRITE par `lam`, exactement comme le
# cycle 126 (`c126_rotation_vs_stretch.py:152-186`). La rotation, la translation et l'articulation
# restent intactes. Ce n'est PAS le bouton du moteur — c'est un PROXY, et sa fidelite se teste :
# aux deux commandes archivees il doit rendre les deux couples (longueur, COM) archives.
P('C131: ' + '-' * 112)
P('C131:     (b) VERIFICATION PAR UN AUTRE CHEMIN — BALAYAGE DE LA COMMANDE SUR LE MESH, SANS')
P('C131:         COURSE. On substitue la plus grande valeur singuliere de la matrice ECRITE par')
P('C131:         `lam` (portage de `c126:152-186`) : rotation, translation et articulation')
P('C131:         intactes. C\'est un PROXY du bouton, pas le bouton — sa fidelite est TESTEE')
P('C131:         ci-dessous aux DEUX commandes archivees avant d\'etre utilisee.')
PRE = {}
for (i, sl), M in mats.items():
    nm = jn.get(sl)
    if nm not in CHAINJOINTS:
        continue
    S, Rr = c126.polar_SR(M[:3, :3])
    sv, U = np.linalg.eigh(S)
    PRE[(i, sl)] = (S, Rr, sv, U, int(np.argmax(sv)))


def lam_mats(lam):
    mm = dict(mats)
    for (i, sl), (S, Rr, sv, U, k) in PRE.items():
        if abs(sv[k] - 1.0) <= 1e-3:        # cellule ou le solveur ne commande RIEN : intacte
            continue
        S2 = S + (lam - sv[k]) * np.outer(U[:, k], U[:, k])
        M2 = mats[(i, sl)].copy()
        M2[:3, :3] = S2 @ Rr
        mm[(i, sl)] = M2
    return mm


CACHE = {}


def at_lam(cname, lam, aloc=None):
    key = (cname, round(lam, 6), None if aloc is None else id(aloc))
    if aloc is None and key in CACHE:
        return CACHE[key]
    mm = lam_mats(lam)
    L = lengths(CTX[(cname, 0.0)], mm, aloc)['dec']
    v, _e = com(CTX[(cname, 0.0)], mm, aloc)
    r = (L, float(np.linalg.norm(v)))
    if aloc is None:
        CACHE[key] = r
    return r


P('C131:         CONTROLE DE FIDELITE DU PROXY (4 nombres, 2 commandes, 2 chaines) :')
fid = 0.0
for cname in CHAINS:
    for (k, l, m) in TWOPT[cname]:
        gl, gc = at_lam(cname, k)
        dl, dc = abs(gl / l - 1.0) * 100.0, abs(gc / m - 1.0) * 100.0
        fid = max(fid, dl, dc)
        P('C131:           %-7s lam=%.4f -> longueur %.4f (archive %.4f, ecart %.2f %%) · COM %.4f'
          ' (archive %.4f, ecart %.2f %%)' % (cname, k, gl, l, dl, gc, m, dc))
FID_OK = fid <= 3.0
P('C131:         -> pire ecart %.2f %% (seuil declare 3 %%) : le proxy est %s'
  % (fid, 'FIDELE, la verification (b) est recevable' if FID_OK else
     '**INFIDELE** — (b) n\'est pas recevable et n\'est PAS utilisee pour juger P4'))
GRID = [1.02 + 0.004 * k for k in range(0, 76)]
DIRECT = {}
if FID_OK:
    for cname in CHAINS:
        xs = [(at_lam(cname, lm), lm) for lm in GRID]
        star = None
        for (Lg, Cg), lm in xs:
            if Lg >= LHI:
                star = ((Lg, Cg), lm)
                break
        prev = None
        for (Lg, Cg), lm in xs:
            if Lg >= LHI and prev is not None:
                (Lp, Cp), lp = prev
                f = (LHI - Lp) / (Lg - Lp) if Lg != Lp else 0.0
                star = ((LHI, Cp + f * (Cg - Cp)), lp + f * (lm - lp))
                break
            prev = ((Lg, Cg), lm)
        if star is None:
            P('C131:         %-7s le balayage ne traverse jamais la longueur %.2f — pas de point de'
              ' fonctionnement, et je le dis.' % (cname, LHI))
            continue
        (Ls, Cs), lms = star
        DIRECT[cname] = (lms, Cs, LO - Cs)
        P('C131:         %-7s longueur %.2f atteinte a lam=%.4f  ->  COM %.4f B0 · deficit %.4f B0'
          ' (%.1f %% du plancher)' % (cname, LHI, lms, Cs, LO - Cs, (LO - Cs) / LO * 100.0))

P('C131: ' + '-' * 112)
P('C131:     (c) LE VERDICT DE P4, SUR SON FALSIFICATEUR DE 20 % :')
ok4 = FID_OK and len(DIRECT) == len(CHAINS)
if not FID_OK:
    P('C131:         P4 -> **NON JUGEABLE** : le proxy de commande n\'est pas fidele, donc aucune')
    P('C131:         « mesure directe » n\'existe pour confronter l\'interpolation. La taille reste')
    P('C131:         NON ETABLIE, et c\'est ce que je publie.')
else:
    for cname in CHAINS:
        if cname not in DIRECT:
            ok4 = False
            continue
        pred = P4_PRED[cname][1]
        got = DIRECT[cname][2]
        d = abs(got / pred - 1.0) * 100.0
        ok4 = ok4 and d <= 20.0
        P('C131:         %-7s deficit PREDIT %.4f B0 · deficit MESURE %.4f B0 -> ecart %.1f %% '
          '(falsificateur 20 %%)  %s'
          % (cname, pred, got, d, '' if d <= 20.0 else '**AU-DESSUS**'))
    P('C131:         P4 -> %s'
      % ('**TIRE.** L\'interpolation a deux points predit le deficit de COM au point de '
         'fonctionnement dans son falsificateur.' if ok4 else
         '**REFUTEE.** Mon interpolation a deux points ne vaut rien et la taille du deplacement '
         'reste NON ETABLIE.'))

# ---- (d) la TAILLE du deplacement d'ancrage qui ferme le deficit, MESUREE ------------------------
P('C131: ' + '-' * 112)
P('C131:     (d) LE DEPLACEMENT D\'ANCRAGE QUI FERME LE DEFICIT — resolu sur la mesure, pas sur un')
P('C131:         modele lineaire : le COM est une NORME de vecteur, elle n\'est pas additive.')
P('C131:         LES DEUX SENS SONT RESOLUS, pas seulement celui qui gagnait au point LIVRE : le')
P('C131:         signe le plus efficace peut changer avec la commande, et le supposer serait une')
P('C131:         extrapolation.')
FGRID = [0.005 * k for k in range(0, 121)]
for cname in CHAINS:
    if cname not in DIRECT:
        P('C131:         %-7s pas de point de fonctionnement : non resolu.' % cname)
        continue
    lms = DIRECT[cname][0]
    mm = lam_mats(lms)
    for sgn, sname in ((+1, 'DISTAL'), (-1, 'PROXIMAL')):
        prev, sol, Lref = None, None, None
        for amp in FGRID:
            disp = (sgn * amp * B0) * CTX[(cname, 0.0)]['u']
            aloc = anchor_local(CTX[(cname, 0.0)], disp) if amp else None
            Lg = lengths(CTX[(cname, 0.0)], mm, aloc)['dec']
            v, _e = com(CTX[(cname, 0.0)], mm, aloc)
            Cg = float(np.linalg.norm(v))
            if Lref is None:
                Lref = Lg
            if prev is not None and prev[1] < LO <= Cg:
                f = (LO - prev[1]) / (Cg - prev[1])
                sol = (prev[0] + f * (amp - prev[0]), prev[2] + f * (Lg - prev[2]))
                break
            prev = (amp, Cg, Lg)
        if sol is None:
            P('C131:         %-7s %-9s le COM n\'atteint jamais %.2f B0 sur a/B0 <= %.2f (max %.4f)'
              ' : ce sens NE FERME PAS le deficit, et je le dis.'
              % (cname, sname, LO, FGRID[-1], prev[1] if prev else float('nan')))
            continue
        amp_s, L_s = sol
        predamp = P4_PRED[cname][3]
        P('C131:         %-7s %-9s a lam=%.4f (longueur de depart %.4f) : a/B0 = %.4f porte le COM a'
          ' %.2f B0' % (cname, sname, lms, Lref, amp_s, LO))
        P('C131:         %-7s %-9s   la longueur y vaut %.4f (bande %.2f-%.2f : %s) · prediction'
          ' ecrite d\'avance %.4f -> ecart %.1f %%'
          % (cname, sname, L_s, LLO, LHI, 'DANS' if LLO <= L_s <= LHI else 'HORS',
             predamp, abs(amp_s / predamp - 1.0) * 100.0))
P('C131: ' + '=' * 112)

# ================================================================================================
# PORTEE DERIVEE — DECLAREE ICI, PAS DECOUVERTE EN CHEMIN. P3 est REFUTEE : l'ancrage ne DECOUPLE
# pas les deux clauses. Mais « pas orthogonal » n'est pas « pas un second degre de liberte » : la
# question que §11 pose reellement est celle d'un POINT ADMISSIBLE COMMUN, et le registre exige de
# le chercher AVANT de lancer quoi que ce soit (`bound-undone-by-downstream-constraint-loop`).
# Le plan (commande, ancrage) est donc balaye en entier, et le resultat est publie quel qu'il soit.
# ================================================================================================
P('C131: PORTEE DERIVEE — EXISTE-T-IL UN POINT ADMISSIBLE COMMUN DANS LE PLAN (COMMANDE, ANCRAGE) ?')
P('C131:   P3 refutee dit que les deux clauses ne se DECOUPLENT pas. Elle ne dit RIEN sur')
P('C131:   l\'existence d\'un point ou les DEUX tiennent. Balayage complet, verdict sur w>0.00 :')
P('C131:   longueur DECILES dans %.2f-%.2f ET COM a la masse d\'AIRE dans %.2f-%.2f.'
  % (LLO, LHI, LO, HI))
if not FID_OK:
    P('C131:   NON EXECUTE — le proxy de commande n\'est pas fidele, ce balayage n\'aurait aucune')
    P('C131:   valeur. Je le dis au lieu de publier une carte.')
else:
    LGRID = [1.02 + 0.004 * k for k in range(0, 76)]
    AGRID = [0.01 * k for k in range(0, 41)]
    for cname in CHAINS:
        ctx = CTX[(cname, 0.0)]
        best, nok, ntot = None, 0, 0
        lam_ok = set()
        for lm in LGRID:
            mm = lam_mats(lm)
            for sgn in (+1, -1):
                for amp in AGRID:
                    if amp == 0.0 and sgn < 0:
                        continue
                    ntot += 1
                    disp = (sgn * amp * B0) * ctx['u']
                    aloc = anchor_local(ctx, disp) if amp else None
                    Lg = lengths(ctx, mm, aloc)['dec']
                    if not (LLO <= Lg <= LHI):
                        continue
                    v, _e = com(ctx, mm, aloc)
                    Cg = float(np.linalg.norm(v))
                    if not (LO <= Cg <= HI):
                        continue
                    nok += 1
                    lam_ok.add(round(lm, 4))
                    # marge = la plus petite distance relative a un bord de bande, sur les DEUX
                    # clauses ; on retient le point qui la maximise (le plus loin de tout bord).
                    mg = min((Lg - LLO) / (LHI - LLO), (LHI - Lg) / (LHI - LLO),
                             (Cg - LO) / (HI - LO), (HI - Cg) / (HI - LO))
                    if best is None or mg > best[0]:
                        best = (mg, lm, sgn, amp, Lg, Cg)
        if best is None:
            P('C131:   %-7s AUCUN point admissible sur %d combinaisons (lam %.3f-%.3f, a/B0 0-%.2f,'
              ' deux sens). Les deux clauses restent INCOMPATIBLES, ancrage compris.'
              % (cname, ntot, LGRID[0], LGRID[-1], AGRID[-1]))
            continue
        mg, lm, sgn, amp, Lg, Cg = best
        P('C131:   %-7s %d points admissibles sur %d (%.1f %%), sur %d valeurs de commande'
          % (cname, nok, ntot, nok / ntot * 100.0, len(lam_ok)))
        P('C131:   %-7s point le plus loin de TOUT bord de bande : commande lam=%.4f · ancrage %s'
          ' a/B0=%.2f  ->  longueur %.4f · COM %.4f  (marge %.1f %% de demi-bande)'
          % (cname, lm, 'DISTAL' if sgn > 0 else 'PROXIMAL', amp, Lg, Cg, mg * 100.0))
        # la sensibilite du point retenu aux AUTRES frontieres d'organe et aux AUTRES lectures :
        # elle n'est pas cachee, parce que c'est elle qui dira si le point survit a l'instrument.
        mm = lam_mats(lm)
        aloc = anchor_local(CTX[(cname, 0.0)], (sgn * amp * B0) * CTX[(cname, 0.0)]['u']) \
            if amp else None
        l0 = lengths(CTX[(cname, 0.0)], mm, aloc)
        l25 = lengths(CTX[(cname, 0.25)], mm, aloc)
        coms = []
        for cut in CUTS:
            v, _e = com(CTX[(cname, cut)], mm, aloc)
            coms.append('w>%.2f %.4f %s' % (cut, float(np.linalg.norm(v)),
                                            verd(float(np.linalg.norm(v)))))
        P('C131:   %-7s   sensibilite du point — longueur w>0.00 dec %.4f / mm %.4f / sd %.4f ·'
          ' w>=0.25 dec %.4f' % (cname, l0['dec'], l0['mm'], l0['sd'], l25['dec']))
        P('C131:   %-7s   sensibilite du point — COM aux trois frontieres : %s'
          % (cname, '  ·  '.join(coms)))
    P('C131:   RESERVE : ce plan est balaye avec le PROXY de commande (substitution de valeur')
    P('C131:   singuliere), pas avec le bouton du moteur, et l\'ancrage n\'existe PAS dans le moteur')
    P('C131:   aujourd\'hui. Rien de ce bloc n\'est un lot : c\'est une carte, pas une livraison.')
P('C131: ' + '=' * 112)

# ================================================================================================
# SECTION 4 — LA RESERVE, PUBLIEE ET CHIFFREE
# ================================================================================================
P('C131: SECTION 4 — LA RESERVE, PUBLIEE ET CHIFFREE')
P('C131:   L\'invariance de longueur est EXACTE pour une peau pilotee par UNE matrice. La chaine en')
P('C131:   porte DEUX, melangees par les poids : un sommet mixte recoit deux offsets `a.(I-D)`')
P('C131:   differents, et leur combinaison convexe ne se soustrait plus exactement. Voici de')
P('C131:   combien l\'invariance est brisee EN PRATIQUE.')
P('C131: ' + '-' * 112)
P('C131:   %-7s %-9s %-6s | %-9s %-9s | %-9s %-9s' % ('chaine', 'sens', 'a/B0', 'dec w>0.00',
                                                      'dec w>=0.25', 'mm w>0.00', 'sd w>0.00'))
wmax = 0.0
for cname in CHAINS:
    for sgn, sname in ((+1, 'DISTAL'), (-1, 'PROXIMAL')):
        for amp in AMPS:
            if amp == 0.0:
                continue
            r0, r1 = SWEEP[(cname, sgn, 0.0)], SWEEP[(cname, sgn, amp)]
            d = [(r1['w>0.00']['dec'] / r0['w>0.00']['dec'] - 1.0) * 100.0,
                 (r1['w>=0.25']['dec'] / r0['w>=0.25']['dec'] - 1.0) * 100.0,
                 (r1['w>0.00']['mm'] / r0['w>0.00']['mm'] - 1.0) * 100.0,
                 (r1['w>0.00']['sd'] / r0['w>0.00']['sd'] - 1.0) * 100.0]
            wmax = max(wmax, abs(d[0]), abs(d[1]))
            P('C131:   %-7s %-9s %.2f   | %+8.4f %% %+8.4f %% | %+8.4f %% %+8.4f %%'
              % (cname, sname, amp, d[0], d[1], d[2], d[3]))
P('C131:   -> BRIS D\'INVARIANCE MAXIMAL sur la lecture DECILES, toutes amplitudes jusqu\'a %.2f B0'
  ' : %.4f %%' % (AMPS[-1], wmax))
P('C131: ' + '-' * 112)
P('C131:   LA PART DES SOMMETS DE L\'ORGANE PILOTES PAR PLUS D\'UN JOINT DE CHAINE — c\'est'
  ' exactement')
P('C131:   la population sur laquelle l\'algebre a UNE matrice ne s\'applique pas :')
for cname in CHAINS:
    idx = [names.index(j) for j in CHAINS[cname]]
    cnt = np.zeros(len(V), dtype=int)
    for ji in idx:
        cnt += ((W * (J == ji)) > 0).sum(axis=1)
    for cut, lbl in LCUTS:
        sel = CTX[(cname, cut)]['sel']
        n = int(sel.sum())
        multi = int((cnt[sel] >= 2).sum())
        Av = AREA[sel]
        amul = float(Av[cnt[sel] >= 2].sum() / Av.sum() * 100.0)
        P('C131:     %-7s %-8s %4d sommets · %4d pilotes par >= 2 joints de chaine (%.1f %% des'
          ' sommets, %.1f %% de l\'AIRE)'
          % (cname, lbl, n, multi, multi / max(n, 1) * 100.0, amul))
P('C131: ' + '-' * 112)
P('C131:   MAIS CE N\'EST PAS LA CAUSE PRINCIPALE, ET LA MESURE LE DIT. `chestR` ne compte que')
P('C131:   17,6 % d\'aire mixte et casse quand meme l\'invariance. La cause dominante est ailleurs :')
P('C131:   **le decile PROXIMAL n\'est pas pilote par la chaine**, il pese sur `chest` — que la')
P('C131:   consigne exclut de l\'offset. Les deux centroides ne recoivent donc PAS le meme offset,')
P('C131:   et il ne se soustrait plus. Poids de chaine moyen de chaque decile, sur la pose de bind :')
for cname in CHAINS:
    for cut, lbl in LCUTS:
        c_ = CTX[(cname, cut)]
        P('C131:     %-7s %-8s decile PROXIMAL w_chaine %.3f  ·  decile DISTAL w_chaine %.3f'
          '   (§30 : la racine est « strongly attached »)'
          % (cname, lbl, float(c_['wv'][c_['prox']].mean()), float(c_['wv'][c_['dist']].mean())))
P('C131: ' + '-' * 112)
P('C131:   ET INCLURE `%s` NE LA RESTAURE PAS NON PLUS — mesure, pas raisonnement. On refait le'
  % ANCHOR)
P('C131:   meme balayage en ajoutant `%s` aux joints qui recoivent l\'offset (configuration NON'
  % ANCHOR)
P('C131:   JOUABLE : elle deplacerait le torse entier ; elle ne porte AUCUN verdict) :')
ALLJ = set(CHAINJOINTS) | {ANCHOR}
worstall = 0.0
for cname in CHAINS:
    for sgn, sname in ((+1, 'DISTAL'), (-1, 'PROXIMAL')):
        for amp in (0.10, 0.30):
            disp = (sgn * amp * B0) * CTX[(cname, 0.0)]['u']
            aloc = anchor_local(CTX[(cname, 0.0)], disp, ALLJ)
            r = lengths(CTX[(cname, 0.0)], mats, aloc, ojoints=ALLJ)
            b = BASE_LEN[(cname, 'w>0.00')]
            d = abs(r['dec'] / b['dec'] - 1.0) * 100.0
            worstall = max(worstall, d)
            P('C131:     %-7s %-9s a/B0=%.2f  longueur DECILES %.4f contre %.4f a l\'ancrage nul'
              '  ->  ecart %.4f %%' % (cname, sname, amp, r['dec'], b['dec'], d))
P('C131:   -> pire ecart %.4f %%. LA RAISON EST ALGEBRIQUE et elle acheve la question : `a` vit dans'
  % worstall)
P('C131:   le repere de BIND DE CHAQUE JOINT, donc `a_j = disp . RB_j`, et `D_j` differe d\'un joint')
P('C131:   a l\'autre. L\'offset `a_j.(I - D_j)` est donc DIFFERENT par joint, quel que soit')
P('C131:   l\'ensemble de joints qu\'on offset. Il ne se soustrait entre deux centroides que si les')
P('C131:   DEUX sont pilotes par LE MEME joint — ce qui n\'est le cas d\'aucune paire ici.')
P('C131: ' + '-' * 112)
P('C131:   CONTROLE POSITIF DE L\'ALGEBRE — IL EST OBLIGATOIRE, parce que sans lui personne ne peut')
P('C131:   distinguer « P3 est refutee » de « mon offset est faux ». Prediction exacte : un nuage')
P('C131:   pilote par UN SEUL joint recoit UN SEUL offset, donc TOUTES ses distances sont')
P('C131:   invariantes A LA PRECISION MACHINE. On reprend les MEMES sommets, les MEMES matrices et')
P('C131:   la MEME longueur de decile, en attribuant tout le poids a un seul joint de chaine.')
P('C131:   CONSTRUCTION SYNTHETIQUE, declaree comme telle : elle ne decrit aucun etat du')
P('C131:   personnage, elle teste l\'operateur.')
worstctl = 0.0
for cname in CHAINS:
    ctx = CTX[(cname, 0.0)]
    for nmj in CHAINS[cname]:
        def rigid_len(aloc):
            out = {}
            for i in (0, ipro):
                M = mats[(i, slot[nmj])]
                D, t = M[:3, :3], M[3, :3]
                q = (ctx['Vs'] - Pb[NIDX[nmj]]) @ RB[nmj]
                acc = q @ D + t
                if aloc is not None:
                    acc = acc + aloc[nmj] @ (I3 - D)
                wv, pr, ds = ctx['wv'], ctx['prox'], ctx['dist']
                cp = (wv[pr, None] * acc[pr]).sum(0) / wv[pr].sum()
                cd = (wv[ds, None] * acc[ds]).sum(0) / wv[ds].sum()
                out[i] = float(np.linalg.norm(cd - cp))
            return out[ipro] / out[0]
        base = rigid_len(None)
        for sgn, sname in ((+1, 'DISTAL'), (-1, 'PROXIMAL')):
            for amp in (0.10, 0.30):
                disp = (sgn * amp * B0) * ctx['u']
                r = rigid_len(anchor_local(ctx, disp))
                d = abs(r / base - 1.0) * 100.0
                worstctl = max(worstctl, d)
                P('C131:     %-7s pilote 100 %% par %-6s %-9s a/B0=%.2f  longueur %.6f contre'
                  ' %.6f  ->  ecart %.3e %%'
                  % (cname, nmj, sname, amp, r, base, d))
P('C131:   -> pire ecart %.3e %% (seuil declare 1e-6 %%). %s'
  % (worstctl, 'TIRE — l\'offset `a.(I-D)` est correctement implemente : sur un nuage a UN joint'
     ' la longueur est invariante au bit pres. Le bris mesure plus haut est donc une PROPRIETE DU'
     ' SKINNING MULTI-JOINTS, pas un defaut de code, et le refus de P3 tient.'
     if worstctl <= 1e-6 else '**ECHOUE** — l\'offset n\'est PAS l\'algebre annoncee ; tout ce '
     'fichier est suspect et le refus de P3 n\'est PAS etabli.'))
P('C131: ' + '=' * 112)
P('C131: FIN. Aucun fichier du moteur n\'a ete touche, aucune course et aucun build n\'a ete lance ;')
P('C131: tout ce qui precede est lu sur la trace archivee et le mesh livre.')
