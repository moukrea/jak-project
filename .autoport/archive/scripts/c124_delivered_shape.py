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


# ---- CYCLE 125 : LE MEME CALCUL, RENDU APPELABLE PAR LE PRODUCTEUR DU TABLEAU ------------------
# Regle du 2026-08-19 23:50 : « un correctif d'instrument s'arrete quand la LIGNE DE VERDICT lit la
# nouvelle donnee — pas quand la donnee existe ». `physics_room_table.py` doit donc appeler CE
# calcul-ci et pas une copie : deux implementations d'une meme mesure finissent par diverger, et le
# dossier a deja paye ca. `main()` ne change pas d'un caractere de sortie ; seule la DESTINATION de
# ses lignes devient redirigeable, et le controle qui l'atteste est le md5 de sa sortie autonome.
_SINK = None
RESULT = {}


def _P(s):
    if _SINK is None:
        print(s)
    else:
        _SINK.append(s)


def measure(txt):
    """(lignes, rows, rc) ; rows = {(chaine, frontiere, '10'|'11', axe) ->
    (livree_sigma, livree_maxmin, commandee, verdict_sigma, livree_deciles)}.

    CYCLE 131b — LE CINQUIEME CHAMP EST AJOUTE EN QUEUE, JAMAIS EN TETE. Les quatre premiers
    gardent leur rang et leur sens exacts : `c125_repro.py` et `c128_verify.py` lisent `[0]`,
    `[2]` et `[3]` et continuent de lire la meme chose. `livree_deciles` est la distance
    racine->apex entre centroides de DECILE, rapportee a la cellule i=0 — l'instrument que le
    cycle 126 a ARBITRE pour la clause « Root-to-apex LENGTH » de §11.

    CYCLE 143 — ELLE EXISTE DESORMAIS SUR LES TROIS AXES. Le motif « une distance n'a pas de
    composante » valait pour une PROJECTION ; la grandeur construite ici est la DISTANCE entre
    les centroides de deux populations de decile, et trier la population sur l'axe `out` (resp.
    `up`) rend la LARGEUR (resp. l'EPAISSEUR / l'ENVELOPPE VERTICALE) de l'organe — les
    grandeurs que §10 et §11 NOMMENT sur ces deux axes. Le chemin de l'axe `fwd` est inchange :
    memes quantiles, memes poids, meme nuage, controle de portage D1 a l'identite.

    `verdict_sigma` reste le verdict lu sur l'ECART-TYPE PONDERE : c'est ce que la ligne de
    verdict publiait avant ce cycle, et le garder ici permet le retour arriere a une ligne
    (`LEN_VERDICT_DECILES` dans `physics_room_table.py`). Le verdict PUBLIE est choisi la-bas,
    pas ici."""
    global _SINK
    old, _SINK = _SINK, []
    try:
        RESULT.clear()
        rc = main(txt=txt)
        return list(_SINK), dict(RESULT.get('rows', {})), rc
    finally:
        _SINK = old


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


def _fz_sense(txt):
    """LE SENS DU `+Z` DU TRIEDRE DE §7, **DERIVE D'UNE MESURE** ET PLUS PORTE PAR UNE CONSTANTE.

    Rend `(zf, isup, ipro, why)`. `zf = +1` si `gz > 0` designe la cellule PRONE (la convention que
    §7 l.130 ecrit, « +Z = forward from chest », posee dans le moteur au cycle 141) ; `zf = -1` si
    `gz > 0` designe SUPINE (la convention d'AVANT, celle de [NOTE-408]). `None` si la mesure ne
    tranche pas — et alors aucune cellule n'est nommee, plutot qu'une nommee au hasard.

    POURQUOI CETTE FONCTION EXISTE, ET CE QUE SON ABSENCE A COUTE (cycle 142).
    `_roles()` portait la regle « `gz > 0` = SUPINE » ECRITE EN DUR. Le cycle 141 a remis `fz` dans
    le sens de §7 : `gz` a change de signe (`PHYSORI`/`PHYSSYM5`, seule la composante `gz`, `gx` et
    `gy` identiques au bit), les deux cellules se sont echangees, et le verdict de la clause de COM
    de §11 est passe de DANS (0.2010/0.2039 B0) a AU-DESSUS (0.3434/0.3046 B0) SANS QU'UN SEUL BIT
    DU MOTEUR AIT BOUGE sur ces grandeurs. Le cycle 69 avait ecrit que ca arriverait : « un
    consommateur neuf qui lit `gz` comme "avant" inverserait §10 et §11 ». Le consommateur neuf
    etait a nous. Une constante de convention dans un instrument est une bombe a retardement ; on
    ne la deplace pas, on la remplace par une mesure.

    CE QUI DISCRIMINE, ET C'EST INDEPENDANT DU TRIEDRE QU'ON CHERCHE A DATER. La designation passe
    d'abord par la base de l'ANCRE, qui est une AUTRE base que le triedre de §7 — le cycle 141 l'a
    etabli par mesure et pas par lecture : `PHYSORI4` (gravite en base d'ancre) et `PHYSURST` (l'os
    de racine dans la meme base) sont IDENTIQUES AU BIT entre les deux courses, la ou `PHYSORI gz`
    a bascule. Dans cette base-la le sens de la ligne 2 se mesure sur l'ANATOMIE : un sein FAIT
    SAILLIE, donc l'os racine y a une composante non nulle et son signe dit ou pointe la ligne.
    On nomme donc PRONE = la cellule ou la gravite pointe le plus vers l'AVANT en base d'ancre,
    SUPINE = celle ou elle pointe le plus vers l'ARRIERE, puis on LIT le signe que `gz` prend sur la
    cellule PRONE : ce signe EST le sens du `+Z` de §7, mesure sur cette course-la.

    REFUS (aucun nommage plutot qu'un nommage devine) : saillie trop faible (< 0.03) ; les deux
    chaines en desaccord de signe (le rig ne serait pas symetrique) ; `PHYSORI4` absent ; les deux
    chaines en desaccord sur le signe de `gz` a la cellule prone ; ou une marge insuffisante entre
    la cellule retenue et la suivante (seuil declare `_FZ_MARGE`).

    NATURE : un SIGNE, sans dimension. LIGNE DE BASE : sur une trace d'AVANT le cycle 141 la
    fonction doit rendre `-1`, sur une trace d'APRES `+1` — c'est ce test a deux traces qui prouve
    qu'elle MESURE au lieu de porter une convention."""
    # --- le sens de la ligne 2 de la base de l'ANCRE, sur l'anatomie du rig livre ---------------
    roots = {}
    for m in re.finditer(r'^PHYSURST c=(\d+) l=0 ux=([-\d.e+]+) uy=([-\d.e+]+)'
                         r' uz=([-\d.e+]+)', txt, re.M):
        roots[int(m.group(1))] = float(m.group(4))
    if not roots:
        return None, None, None, 'aucune ligne PHYSURST : le sens de la base d\'ancre est indecidable'
    if min(abs(x) for x in roots.values()) < 0.03:
        return None, None, None, ('la saillie du sein sur la ligne 2 de l\'ancre est trop faible'
                                  ' (%.5f) pour designer un sens' % min(abs(x) for x in roots.values()))
    if len({(1 if x > 0 else -1) for x in roots.values()}) != 1:
        return None, None, None, 'les chaines ne s\'accordent pas sur le signe : rig non symetrique'
    zs = 1.0 if next(iter(roots.values())) > 0 else -1.0

    # --- les cellules, nommees dans la base de l'ANCRE ------------------------------------------
    g4 = {}
    for m in re.finditer(r'^PHYSORI4 c=(\d+) i=(\d+) r0=([-\d.e+]+) r1=([-\d.e+]+)'
                         r' r2=([-\d.e+]+)', txt, re.M):
        g4[(int(m.group(1)), int(m.group(2)))] = float(m.group(5))
    if not g4:
        return None, None, None, 'aucune ligne PHYSORI4 : les cellules ne peuvent pas etre nommees'
    fwd = {}
    for i in sorted({i for (_c, i) in g4}):
        if i == 0 or i > 8:          # i=0 est la pose debout ; au-dela on sort du balayage a 9 cellules
            continue
        v = [g4[(c, i)] * zs for c in (0, 1) if (c, i) in g4]
        if v:
            fwd[i] = float(np.mean(v))
    if len(fwd) < 2:
        return None, None, None, 'moins de deux cellules d\'orientation exploitables'
    ordre = sorted(fwd, key=lambda i: fwd[i])
    ipro, isup = ordre[-1], ordre[0]          # gravite la plus AVANT / la plus ARRIERE
    if fwd[ipro] <= 0.0 or fwd[isup] >= 0.0:
        return None, None, None, ('aucune cellule ne porte une gravite franchement avant ou'
                                  ' arriere (avant %.4f, arriere %.4f)' % (fwd[ipro], fwd[isup]))
    m_pro = fwd[ipro] - fwd[ordre[-2]]
    m_sup = fwd[ordre[1]] - fwd[isup]
    if min(m_pro, m_sup) < _FZ_MARGE:
        return None, None, None, ('marge insuffisante entre la cellule retenue et la suivante'
                                  ' (prone %.4f, supine %.4f, seuil %.2f)'
                                  % (m_pro, m_sup, _FZ_MARGE))

    # --- LE SENS DE `+Z` DE §7, LU SUR LA CELLULE AINSI NOMMEE ---------------------------------
    gz = {}
    for m in re.finditer(r'^PHYSORI c=(\d+) i=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+)'
                         r' gz=([-\d.e+]+)', txt, re.M):
        gz[(int(m.group(1)), int(m.group(2)))] = float(m.group(5))
    v = [gz[(c, ipro)] for c in (0, 1) if (c, ipro) in gz]
    if not v:
        return None, None, None, 'aucune ligne PHYSORI a la cellule prone : `gz` n\'est pas lisible'
    if len({(1 if x > 0 else -1) for x in v}) != 1:
        return None, None, None, ('les deux chaines donnent a `gz` des signes opposes a la cellule'
                                  ' prone : le triedre n\'est pas commun, rien n\'est nomme')
    if min(abs(x) for x in v) < 0.5:
        return None, None, None, ('`gz` est trop petit a la cellule prone (%.4f) pour porter un'
                                  ' signe' % min(abs(x) for x in v))
    return (1.0 if v[0] > 0 else -1.0), isup, ipro, ''


# marge minimale, en composante avant/arriere de gravite unitaire, entre la cellule retenue et la
# suivante. DECLAREE, et volontairement lache : le balayage a neuf cellules place prone/supine a
# +-0.99 et leurs voisines a +-0.77 (penche 45), soit une marge naturelle de ~0.22. Le seuil refuse
# un balayage qui n'aurait pas de cellule franchement couchee, pas un balayage bruite.
_FZ_MARGE = 0.10


def _roles(txt):
    """La cellule SUPINE et la cellule PRONE, designees par la GRAVITE MESUREE et non par le
    triplet d'echelles — le triplet est un argmin contre les nombres qu'on injecte, donc
    tautologique (meme regle qu'au bloc `_spec10_block`, cycle 123).

    CYCLE 142 — LA CONVENTION DE SIGNE N'EST PLUS ECRITE ICI, ELLE EST MESUREE PAR `_fz_sense()`.
    Voir la docstring de cette fonction pour ce que l'ancienne constante a coute. `gz * zf > 0`
    designe PRONE et `< 0` SUPINE, ou `zf` est le sens du `+Z` de §7 MESURE sur cette course. On
    garde l'argmax de |gz| dans chaque signe, comme avant, pour que le reste du fichier soit
    inchange ; et les cellules ainsi obtenues doivent coincider avec celles que `_fz_sense` a
    nommees en base d'ancre — si elles divergent, les deux bases se contredisent et on ne nomme
    rien."""
    g = {}
    for m in re.finditer(r'^PHYSORI c=(\d+) i=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+)'
                         r' gz=([-\d.e+]+)', txt, re.M):
        g[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                 float(m.group(5)))
    zf, isup_a, ipro_a, _why = _fz_sense(txt)
    if zf is None:
        return None, None, g
    cells = sorted({i for (_c, i) in g})
    sup = pro = None
    for i in cells:
        if i == 0:
            continue
        gz = np.mean([g[(c, i)][2] for c in (0, 1) if (c, i) in g]) * zf
        if gz < 0 and (sup is None or gz < sup[1]):
            sup = (i, gz)
        if gz > 0 and (pro is None or gz > pro[1]):
            pro = (i, gz)
    isup = sup[0] if sup else None
    ipro = pro[0] if pro else None
    # LES DEUX BASES DOIVENT S'ACCORDER. C'est le controle qui aurait attrape le cycle 141 tout
    # seul : la base d'ancre et le triedre de §7 nomment ici la MEME paire, ou personne n'est nomme.
    if (isup, ipro) != (isup_a, ipro_a):
        return None, None, g
    return isup, ipro, g


def main(txt=None):
    if txt is None:
        log = sys.argv[1] if len(sys.argv) > 1 else \
            '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
        txt = open(os.path.join(REPO, log) if not os.path.isabs(log) else log,
                   'r', errors='replace').read()
    jn, mats, nmiss = _read_matrices(txt)
    if not mats:
        _P('C124-SHAPE: SUSPENDU — aucune ligne `PHYSORIM` dans cette trace. Rien n\'est'
              ' publie (course anterieure au cycle 124, ou emission absente).')
        return 1
    if nmiss:
        _P('C124-SHAPE: SUSPENDU — %d ligne(s) `PHYSORIMMISS` : un joint nomme est introuvable'
              ' dans le rig porte. Un skinning incomplet donnerait une forme plausible et fausse.'
              % nmiss)
        return 1
    slot = {v: k for k, v in jn.items()}
    _P('C124-SHAPE: table nom -> slot lue dans la trace : %s'
          % ' '.join('%s=%d' % (v, k) for k, v in sorted(jn.items())))

    # CYCLE 143 : le PLANCHER DE BRUIT de l'estimateur de decile, par axe, MESURE sur la lecture
    # hors defaut (i=9 / i=0, deux cellules DEBOUT que rien ne relie dans le balayage). Il est
    # publie et consomme par `physics_room_table.py` : un plancher mesure sur l'ECART-TYPE ne dit
    # rien du bruit d'un autre estimateur, et en choisir un serait ajuster l'instrument.
    bruit = {}

    g = c6.load_geometry('keira-hd', glb=SHIPPED)
    if g is None:
        _P('C124-SHAPE: SUSPENDU — mesh livre absent (%s).' % SHIPPED)
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
    _P('C124-SHAPE: CONVENTION DE SKINNING, TRANCHEE PAR MESURE et non supposee — 24 sommets'
          ' peses a %.3f sur `chest` (donc RIGIDEMENT lies a lui) :' % float(np.median(wch[top])))
    _P('C124-SHAPE:   A  la matrice porte deja la pose de bind (p = v . M) : ecart median %.5f'
          % verdict['A'])
    _P('C124-SHAPE:   C  il faut passer en local de bind d\'abord           : ecart median %.5f'
          % verdict['C'])
    _P('C124-SHAPE:   Critere : la distance du sommet a la TRANSLATION de son joint doit valoir'
          ' sa distance de BIND au joint (mediane %.1f u). RETENUE : %s (x%.0f mieux).'
          % (float(np.median(dbind)), conv,
             max(verdict.values()) / max(min(verdict.values()), 1e-9)))
    if verdict[conv] > 0.02:
        _P('C124-SHAPE: SUSPENDU — MEME la meilleure convention rend %.5f d\'ecart (seuil'
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

    def world_cloud(i, sel):
        """Le nuage de peau DEFORME de `sel`, en coordonnees MONDE.

        CYCLE 131b — POURQUOI CE NUAGE-CI EXISTE SEPAREMENT DE `cloud()`. La longueur
        racine->apex de §11 est une DISTANCE, et une distance ne se lit pas dans la base
        d'ancre rendue par `frame()` : ses trois colonnes sont normalisees UNE A UNE mais
        JAMAIS orthogonalisees, donc `E` ne conserve pas la norme. Les etendues par axe, elles,
        sont des PROJECTIONS et restent justes dans cette base. C'est exactement le piege que
        `c126_rotation_vs_stretch.py` evite en calculant ses centroides de decile sur le nuage
        MONDE, et ce portage le reproduit a l'identique."""
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
        return acc

    def cloud(i, sel):
        """Le nuage de peau DEFORME de `sel`, en base d'ANCRE de la cellule `i`."""
        acc = world_cloud(i, sel)
        if acc is None or isinstance(acc, tuple):
            return acc
        o, E = frame(i)
        return (acc - o) @ E          # colonnes de E = axes -> coordonnees dans la base d'ancre

    isup, ipro, gdir = _roles(txt)
    o2 = _ori2(txt)
    _P('C124-SHAPE: cellules, designees par la GRAVITE MESUREE (jamais par le triplet'
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
            # ---- CYCLE 131b : LES DEUX POPULATIONS DE DECILE, FIXEES A LA POSE DE BIND --------
            # PORTAGE VERBATIM de `c126_rotation_vs_stretch.py:286-289` (repris tel quel par
            # `c131_anchor_dof.py:189-196`, dont la SECTION 1 reproduit les quatre longueurs
            # publiees a 0,003 %) : on trie les sommets sur la coordonnee `fwd` de la POSE DE
            # BIND relative a l'ancre, et les deciles 10 % / 90 % designent la population
            # PROXIMALE et la population DISTALE. Elles sont fixees UNE FOIS et les MEMES indices
            # servent a toutes les cellules — un argmax recalcule par cellule repondrait DANS la
            # cellule et ne serait pas une population (registre : `argmax-anchor-is-not-a-
            # population`).
            # CYCLE 143 : LA MEME CONSTRUCTION, PORTEE AUX DEUX AUTRES AXES. Le tri se fait sur
            # la coordonnee de BIND de l'AXE CONSIDERE ; tout le reste est inchange, et l'axe
            # `fwd` passe par le meme code qu'avant (meme `np.quantile`, meme ordre) — le
            # controle de portage D1 exige l'identite au dernier chiffre publie.
            POP = {}
            for _a in ('fwd', 'out', 'up'):
                _xb = (V[sel] - P[ai]) @ R @ AX[_a]
                _qlo, _qhi = np.quantile(_xb, 0.10), np.quantile(_xb, 0.90)
                POP[_a] = (_xb <= _qlo, _xb >= _qhi)
            prox, dist = POP['fwd']
            ext, dec = {}, {}
            for i in cells:
                aw = world_cloud(i, sel)
                if aw is None:
                    _P('C124-SHAPE: %-8s %s cellule i=%d ABSENTE (matrice manquante)'
                          % (cname, lbl, i))
                    continue
                if isinstance(aw, tuple):
                    _P('C124-SHAPE: SUSPENDU — le skinning ne se referme pas a 1 (ecart %.4f) :'
                          ' un joint pesant n\'est pas emis. Aucune forme publiee.' % aw[1])
                    return 1
                o_, E_ = frame(i)
                cl = (aw - o_) @ E_
                e = {}
                for a, v in AX.items():
                    x = cl @ v
                    mu = float((wv * x).sum() / wv.sum())
                    e[a] = (math.sqrt(float((wv * (x - mu) ** 2).sum() / wv.sum())),
                            float(x.max() - x.min()))
                ext[i] = e
                # LA GRANDEUR QUE §11 NOMME : une DISTANCE entre deux centroides ponderes, lue
                # sur le nuage MONDE (invariante par rotation ET par translation), jamais dans
                # la base d'ancre qui n'est pas orthogonale.
                dec[i] = {}
                for _a in ('fwd', 'out', 'up'):
                    _p, _d = POP[_a]
                    cp = (wv[_p, None] * aw[_p]).sum(0) / wv[_p].sum()
                    cd = (wv[_d, None] * aw[_d]).sum(0) / wv[_d].sum()
                    dec[i][_a] = float(np.linalg.norm(cd - cp))
            if 0 not in ext:
                _P('C124-SHAPE: %-8s %s SUSPENDU — pas de cellule i=0 (ligne de base).'
                      % (cname, lbl))
                continue
            for sec, cell in (('10', isup), ('11', ipro)):
                if cell is None or cell not in ext:
                    continue
                b = BANDS[sec]
                cmd = o2.get((ci, cell))
                _P('C124-SHAPE: %-8s %s §%s  %s' % (cname, lbl, sec, b['cite']))
                for a, kk in (('fwd', 2), ('out', 0), ('up', 1)):
                    lo, hi = b[a]
                    r_s = ext[cell][a][0] / ext[0][a][0]
                    r_m = ext[cell][a][1] / ext[0][a][1]
                    # LA TROISIEME LECTURE, SUR LES TROIS AXES DEPUIS LE CYCLE 143. Elle etait
                    # limitee a `fwd` au motif qu'« une distance n'a pas de composante » — vrai
                    # pour une PROJECTION, faux pour ce qui est construit ici : c'est la DISTANCE
                    # entre deux centroides de decile, et changer l'axe qui TRIE la population
                    # rend la LARGEUR (`out`) et l'EPAISSEUR / ENVELOPPE VERTICALE (`up`), qui
                    # sont exactement les grandeurs que §10 l.166-167 et §11 l.181-182 NOMMENT.
                    # Aucune convention nouvelle : meme quantile, memes poids, meme nuage MONDE.
                    r_d = (dec[cell][a] / dec[0][a]) if (0 in dec and cell in dec) else None
                    vd = 'SOUS' if r_s < lo else ('DANS' if r_s <= hi else 'AU-DESSUS')
                    y = (r_s / cmd[kk]) if cmd else float('nan')
                    _P('C124-SHAPE: %-8s %s §%s  %-3s  LIVREE %.4f (max-min %.4f, deciles'
                          ' %s)  bande %.2f-%.2f  %-9s | COMMANDEE %.4f  rendement %.4f'
                          % (cname, lbl, sec, a, r_s, r_m,
                             ('%.4f' % r_d) if r_d is not None else 'n/a',
                             lo, hi, vd, (cmd[kk] if cmd else float('nan')), y))
                    out.setdefault((cname, lbl, sec, a),
                                   (r_s, r_m, cmd[kk] if cmd else None, vd, r_d))
            # ---- LES DEUX CONTROLES QUI NE SONT PAS TRIVIAUX -------------------------------
            # P6 — LECTURE HORS DEFAUT. Rapporter i=0 a lui-meme rendrait 1.000 par definition et
            # ne prouverait rien. La cellule i=9 est une SECONDE cellule DEBOUT (ajoutee au cycle
            # 120 pour jouer l'echelon debout->prone) : meme gravite que i=0, rien ne les relie
            # dans le balayage. Leur rapport est donc ce que l'instrument lit quand le defaut est
            # ABSENT, et il est MESURE.
            if 9 in ext:
                _P('C124-SHAPE: %-8s %s LECTURE HORS DEFAUT — i=9 (2e cellule DEBOUT) / i=0 :'
                      ' %s   (seuil declare 1 %%)'
                      % (cname, lbl, ' · '.join('%s %.4f' % (a, ext[9][a][0] / ext[0][a][0])
                                                for a in ('fwd', 'out', 'up'))))
                # CYCLE 143 : LE MEME HORS-DEFAUT SUR L'ESTIMATEUR QUI PORTE LE VERDICT. Un
                # plancher de bruit mesure sur l'ECART-TYPE ne dit rien du bruit de la distance
                # de decile ; le publier ici le rend MESURE par axe, jamais choisi.
                if 9 in dec and 0 in dec:
                    _P('C124-SHAPE: %-8s %s LECTURE HORS DEFAUT (DECILES) — i=9 / i=0 : %s'
                          % (cname, lbl,
                             ' · '.join('%s %.6f' % (a, dec[9][a] / dec[0][a])
                                        for a in ('fwd', 'out', 'up'))))
                    for a in ('fwd', 'out', 'up'):
                        bruit[a] = max(bruit.get(a, 0.0), abs(dec[9][a] / dec[0][a] - 1.0))
            # P7 — CONTROLE DE MONTAGE. i=10 est une seconde cellule PRONE, atteinte par un autre
            # chemin du balayage. Deux cellules que rien ne relie doivent rendre la meme forme.
            if 10 in ext and ipro in ext:
                _P('C124-SHAPE: %-8s %s CONTROLE DE MONTAGE — i=10 (2e cellule PRONE) contre'
                      ' i=%s : %s   (seuil declare 3 %%)'
                      % (cname, lbl, ipro,
                         ' · '.join('%s %+.2f %%'
                                    % (a, (ext[10][a][0] / ext[ipro][a][0] - 1.0) * 100.0)
                                    for a in ('fwd', 'out', 'up'))))
    # ---- LES DEUX TESTS QUI DECIDENT SI CETTE MESURE VAUT QUELQUE CHOSE -----------------------
    ys = [abs(v[0] / v[2] - 1.0) for v in out.values() if v[2]]
    vds = [v[3] for v in out.values()]
    _P('C124-SHAPE: ------------------------------------------------------------------')
    _P('C124-SHAPE: TEST DE MIROIR (P3) — ecart du rendement a 1 : median %.4f  max %.4f'
          ' sur %d cellules.' % (float(np.median(ys)), float(np.max(ys)), len(ys)))
    _P('C124-SHAPE:   Un rendement identiquement 1.000 voudrait dire que la peau rend'
          ' exactement l\'echelle injectee : la clause resterait un MIROIR malgre le changement')
    _P('C124-SHAPE:   de grandeur. Seuil declare AVANT la course : > 3 %% sur au moins une'
          ' cellule.  -> %s' % ('TENUE' if max(ys) > 0.03 else 'REFUTEE'))
    _P('C124-SHAPE: TEST DE FALSIFIABILITE (P4) — verdicts rendus : %s'
          % ' '.join('%s=%d' % (k, vds.count(k)) for k in ('SOUS', 'DANS', 'AU-DESSUS')))
    _P('C124-SHAPE:   Un instrument qui ne peut pas echouer ne vaut rien. Seuil declare AVANT'
          ' la course : au moins une cellule HORS bande.  -> %s'
          % ('TENUE' if any(v != 'DANS' for v in vds) else 'REFUTEE'))
    if bruit:
        _P('C124-SHAPE: PLANCHER DE BRUIT DE L\'ESTIMATEUR DE DECILE, MESURE (pire cas sur les'
              ' 2 chaines et les 2 frontieres) : %s'
              % ' · '.join('%s %.4f %%' % (a, bruit.get(a, 0.0) * 100.0)
                           for a in ('fwd', 'out', 'up')))
    RESULT['rows'] = out
    RESULT['bruit_dec'] = dict(bruit)
    return 0


if __name__ == '__main__':
    sys.exit(main())
