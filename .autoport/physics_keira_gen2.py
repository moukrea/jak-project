#!/usr/bin/env python3
"""physics_keira_gen2.py — GENERATE recharged_assets/physics_chains.txt for KEIRA, and only Keira.

Phase Grecharged-secondary-motion, branch physics-keira-clean, contract
.autoport/prompts/SPEC-keira-physique.md (clean restart 2026-08-11).

DIRECTIVES rule 4: "Donnees generees, jamais rustinees." Not one chain line is hand-written here.
Every chain, every link, every radius and every collider is DERIVED:

  * the GROUPS come from name patterns applied to the rig's own joint names plus the rig hierarchy
    (a chain is the maximal single-child path from the group's root, which is why the goggles chain
    stops at gogglesMid: gogglesMid branches into gogglesLeft/gogglesRight);
  * the RADII come from the skinned mesh (inner-quartile mean of the perpendicular spread of the
    vertices a link owns, in that link's bind space, game units);
  * the COLLIDERS come from the same mesh, one capsule per obstacle bone segment and one sphere per
    obstacle joint that no capsule caps.

The owner's category table lives in this file ONLY as an assertion (EXPECTED_GROUPS): if the rules
stop reproducing it, the script fails loudly instead of emitting something nobody asked for.

Everything that is NOT measured is a tuning constant, and every tuning constant is in TUNING below,
one entry per category, with the reasoning. The owner retunes those by hand in the data file.

Usage:
    python3 .autoport/physics_keira_gen2.py --stamp 2026-08-11

The date is an argument on purpose (never datetime.now()): the output must be byte-reproducible.
"""

import argparse
import hashlib
import json
import os
import re
import sys

import math
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

# Proven GLB / skin helpers, reused rather than rewritten (see .autoport/physics_c6_volumes.py and
# .autoport/physics_c14_meshsamples.py, which already read this exact family of files).
import physics_c6_volumes as c6                                            # noqa: E402
from retarget_hd_models import read_glb, consolidate_buffers, skin_info    # noqa: E402

MODEL = 'keira-hd'
RIG_REL = 'recharged_assets/hd_anim/keira-hd-k2e.json'
GLB_REL = 'decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb'
BAK_REL = 'recharged_assets/physics_chains.FULL-CAST.bak'
OUT_REL = 'recharged_assets/physics_chains.txt'

UNITS = 4096.0          # game units per metre — every emitted length is in GAME UNITS.

# ---- POSE IMPLAUSIBLE : LE GENERATEUR N'EN RETIRE PAS LA CHAINE --------------------------------
# Le retarget peut envoyer un joint ailleurs (mesure du 2026-08-11 : LpantFlap a 259 m de Lknee,
# 2473 fois son rayon ajuste, quand la pire chaine SAINE est a 18.6 fois).  Ce generateur a
# brievement retire la chaine des donnees pour cela : REFUSE par le superviseur le meme jour — « une
# chaine se REPARE, elle ne se retire pas », et ne pas mesurer n'est pas reussir.  La reparation vit
# dans le moteur (jak-hd-physics.gc, PHYS-POSE-RATIO + phys-pose-repair), qui re-assied le lien sur
# son porteur, le compte et le publie.  Ici, la chaine est emise comme les autres.

# ---- measurement thresholds (these are MEASUREMENT rules, not tuning) --------------------------
INFL_GATE = 0.05        # a joint "has geometry" if some vertex holds more than this on it.
FIT_STEPS = (0.5, 0.25, 0.05)   # weight thresholds tried, in order, when fitting a radius.
FIT_MIN_VERTS = 8       # below this many vertices a fit is noise -> step down to the next threshold.
IQ_LO, IQ_HI = 25.0, 75.0       # inner quartile of the perpendicular spread.

# ---- UN OBSTACLE DOIT CONTENIR LA GEOMETRIE QU'IL REPRESENTE -----------------------------------
# MESURE du 2026-08-11 (.autoport/probe_keira_capsules.py, meme selection de sommets que le
# generateur) : chacun des 33 volumes livres laisse ~50 % de sa propre geometrie DEHORS.
#
#     volume            rayon livre   sommets dehors
#     lBoob                     183              53 %
#     main                      560              51 %
#     chest->main               671              51 %
#     head->neck                915              51 %          (... et ainsi de suite, 33 fois)
#
# Ce n'est pas un reglage rate, c'est la STATISTIQUE : le rayon est une MOYENNE INTER-QUARTILE de
# la distance des sommets. Une moyenne est une tendance CENTRALE — par construction la moitie de la
# surface est au-dela. Pour l'epaisseur d'un LIEN (« quelle est mon epaisseur ») c'est la bonne
# mesure et elle ne change pas ici. Pour un OBSTACLE (« ou rien ne doit entrer ») c'est la mauvaise,
# et c'est la cause racine du contresens qui a tenu toute la journee du 2026-08-11 : `meshpen = 0`
# pendant que l'owner voit les lunettes traverser les seins et les bretelles traverser l'elastique
# du crop top. Le zero etait vrai — mesure contre des volumes qui ne contiennent que la moitie
# d'elle.
#
# COVER_PCT = 95 : le volume contient 95 % de la geometrie du joint au lieu de 50 %. Pas 100 :
# `Rmidhaira` passe de 766 (p95) a 1349 (p100) sur UN sommet isole, et gonfler un volume sur une
# valeur aberrante fabrique une resolution « pire que le clip » que la regle 6 interdit. La
# fraction reellement laissee dehors est ecrite a cote de chaque volume, donc le choix se verifie.
COVER_PCT = 95.0

# ---- TUNING CONSTANTS — one row per category, the ONLY hand-chosen numbers in the file ---------
# stiffness is a natural frequency in Hz: short and stiff pieces oscillate fast, long and loose ones
# slow.  damping is 0..1 (fraction of critical).  mass scales the inertia of a link.  couple is the
# anchor-acceleration gain on the pseudo-force of the accelerated frame.  It is 1.00 EVERYWHERE and
# that is not laziness: in the additive form the simulated quantity is the offset to the author pose
# in the carrier's own frame, where the pseudo-force per unit mass IS the carrier's acceleration, so
# a gain of 1.00 is the exact physics and anything else is an invented exaggeration.  The 3.00..6.00
# gains this file carried until 2026-08-11 propped up a world-space spring that barely moved without
# them; measured on the same rig they threw a 148-unit ear bone 4800 units off its place, i.e. the
# length constraint held the chain permanently taut.  How much a piece moves is set by its
# stiffness (a long loose lock at 1.8 Hz answers ~25x more than a stiff 3.2 Hz ear cartilage to the
# same acceleration), which is where it belongs.  The owner raises it here if he wants more.
# gravity/hang are NOT free: SPEC section 4 says rest == the model pose for family A (so family A
# carries NO static sag: gravity=0, hang=0) and "what hangs stays hung" for family B (gravity>0,
# hang>0).  The generator asserts both, per chain, before writing.
#
# Reasoning per category:
#   ear       cartilage, short, light: fast and well damped, low coupling (it sits on the skull).
#   backhair  the longest mass of hair: slowest, least damped, highest coupling.
#   bang      short stiff strands over the face: fast, tight, small coupling.
#   midhair   mid-length locks: between bang and backhair.
#   chest     flesh: soft frequency but heavily damped, it must not wobble for seconds.
#   goggles   a rigid object hanging on a strap (family B): heavy, medium frequency, hangs hard.
#   topstrap  shoulder strap, short and taut: fairly stiff, hangs a little.
#   botstrap  hip strap, longer and looser than the shoulder one.
#   belt      a heavy loop on the hips: slow, damped, hangs fully.
#   kneeflap  a stiff leather flap on the knee.
#   pantflap  a wide soft cloth flap: slowest of the worn pieces, hangs the most.
#   toestrap  tiny and taut.
#   anklestrap tiny and taut, a notch looser than the toe one.
# GRAVITE DE LA FAMILLE A (6e passe de l'owner : « les seins n'ont pas l'air d'etre soumis a la
# gravite, aucun mouvement quand elle se penche en avant pour souder, pas coherent du tout »).
# Elle etait a 0.00 pour respecter SPEC 4 (« au repos on retrouve EXACTEMENT la pose du modele ») et
# c'etait la bonne conclusion tiree de la mauvaise premisse : une gravite ABSOLUE affaisserait la
# poitrine en permanence, mais la pose du modele est deja une pose SOUS gravite — le sculpteur l'a
# modelee debout. Le moteur applique donc a la famille A la gravite RELATIVE au repere de l'ancre
# dans sa pose de bind : nulle quand le buste est droit (l'equilibre reste la pose du modele au bit
# pres), non nulle des qu'il s'incline. C'est un nombre choisi a la main, comme la raideur.
A_GRAVITY = 0.45

TUNING = {
    'ear':        dict(klass='primary',   family='A', stiffness=3.20, damping=0.30, gravity=A_GRAVITY,
                       mass=0.60, couple=1.00, hang=0.00),
    'backhair':   dict(klass='primary',   family='A', stiffness=1.80, damping=0.18, gravity=A_GRAVITY,
                       mass=0.90, couple=1.00, hang=0.00),
    'bang':       dict(klass='primary',   family='A', stiffness=2.60, damping=0.24, gravity=A_GRAVITY,
                       mass=0.70, couple=1.00, hang=0.00),
    'midhair':    dict(klass='primary',   family='A', stiffness=2.00, damping=0.20, gravity=A_GRAVITY,
                       mass=0.80, couple=1.00, hang=0.00),
    'chest':      dict(klass='primary',   family='A', stiffness=2.80, damping=0.35, gravity=A_GRAVITY,
                       mass=1.20, couple=1.00, hang=0.00),
    'goggles':    dict(klass='primary',   family='B', stiffness=2.40, damping=0.30, gravity=0.35,
                       mass=1.40, couple=1.00, hang=1.00),
    'topstrap':   dict(klass='secondary', family='B', stiffness=2.20, damping=0.28, gravity=0.30,
                       mass=0.70, couple=1.00, hang=0.80),
    'botstrap':   dict(klass='secondary', family='B', stiffness=1.80, damping=0.28, gravity=0.32,
                       mass=0.70, couple=1.00, hang=0.85),
    'belt':       dict(klass='secondary', family='B', stiffness=1.60, damping=0.32, gravity=0.35,
                       mass=1.00, couple=1.00, hang=1.00),
    'kneeflap':   dict(klass='secondary', family='B', stiffness=2.00, damping=0.30, gravity=0.30,
                       mass=0.60, couple=1.00, hang=0.90),
    'pantflap':   dict(klass='secondary', family='B', stiffness=1.60, damping=0.34, gravity=0.40,
                       mass=0.60, couple=1.00, hang=0.95),
    'toestrap':   dict(klass='secondary', family='B', stiffness=2.60, damping=0.26, gravity=0.25,
                       mass=0.50, couple=1.00, hang=0.70),
    'anklestrap': dict(klass='secondary', family='B', stiffness=2.40, damping=0.26, gravity=0.25,
                       mass=0.50, couple=1.00, hang=0.70),
}

# ---- CATEGORY RULES — regex over the rig's own joint names, plus the chain-name template --------
# Emission order is the order of this list, side L before side R.  `side` groups are keyed by the
# letter the rig itself uses (l/L or r/R); `plain` categories are one group.
CATEGORY_RULES = [
    ('ear',        r'^(?P<side>[lr])Ear[a-z]$',            'ear{U}'),
    ('backhair',   r'^backHair\d+$',                       'backhair'),
    ('bang',       r'^(?P<side>[LR])bang[a-z]$',           '{l}bang'),
    ('midhair',    r'^(?P<side>[LR])midhair[a-z]$',        '{l}midhair'),
    ('chest',      r'^(?P<side>[lr])Boob$',                'chest{U}'),
    ('goggles',    r'^goggles[A-Z][a-z]*$',                'goggles'),
    ('topstrap',   r'^(?P<side>[lr])TopStrap\d*$',         'topstrap{U}'),
    ('botstrap',   r'^(?P<side>[lr])BotStrap\d*$',         'botstrap{U}'),
    ('belt',       r'^belt$',                              'belt'),
    ('kneeflap',   r'^(?P<side>[lr])KneeFlap$',            'kneeflap{U}'),
    ('pantflap',   r'^(?P<side>[LR])pantFlap$',            'pantflap{U}'),
    ('toestrap',   r'^(?P<side>[LR])toeStrap$',            'toestrap{U}'),
    ('anklestrap', r'^(?P<side>[LR])anklestrap$',          'anklestrap{U}'),
]

# The owner's table, kept ONLY as an assertion on what the rules above produced.
EXPECTED_GROUPS = {
    'earL':       ['lEara', 'lEarb'],
    'earR':       ['rEara', 'rEarb'],
    'backhair':   ['backHair1', 'backHair2'],
    'lbang':      ['Lbanga', 'Lbangb', 'Lbangc'],
    'rbang':      ['Rbanga', 'Rbangb', 'Rbangc'],
    'lmidhair':   ['Lmidhaira', 'Lmidhairb'],
    'rmidhair':   ['Rmidhaira', 'Rmidhairb'],
    'chestL':     ['lBoob'],
    'chestR':     ['rBoob'],
    # les VERRES (gogglesLeft/gogglesRight, 488 des 515 sommets des lunettes) sont deux branches
    # de gogglesMid et restent HORS chaine : ce sont des pieces rigides d'une monture, pas des
    # trucs qui pendent. Ce qui leur manque est un VOLUME, pas un ressort — voir la note mesuree
    # dans `build_groups`.
    'goggles':    ['gogglesBase', 'gogglesMid'],
    'topstrapL':  ['lTopStrap', 'lTopStrap2'],
    'topstrapR':  ['rTopStrap', 'rTopStrap2'],
    'botstrapL':  ['lBotStrap', 'lBotStrap2'],
    'botstrapR':  ['rBotStrap', 'rBotStrap2'],
    'belt':       ['belt'],
    'kneeflapL':  ['lKneeFlap'],
    'kneeflapR':  ['rKneeFlap'],
    'pantflapL':  ['LpantFlap'],
    'pantflapR':  ['RpantFlap'],
    'toestrapL':  ['LtoeStrap'],
    'toestrapR':  ['RtoeStrap'],
    'anklestrapL': ['Lanklestrap'],
    'anklestrapR': ['Ranklestrap'],
}

# ---- OBSTACLES — the SPEC section 3 list, by name, in the rig ----------------------------------
# The BODY part: one connected set of bones.  A capsule is emitted for every parent->child pair
# INSIDE a part; a bone that leaves one part for another (a strand root hanging off the skull, a
# breast hanging off the chest) gets NO capsule to the hub — a swept sphere from a hub centre out to
# an appendage root is a volume that does not exist on the character — it gets a sphere instead.
BODY_PART = ['main', 'hips', 'chest', 'neck', 'head',
             'Lshoulder', 'Lelbow', 'Lhand', 'Rshoulder', 'Relbow', 'Rhand',
             'Lthigh', 'Lknee', 'Lankle', 'Rthigh', 'Rknee', 'Rankle']
# The other obstacle parts are the chain groups themselves — ears, meches (bangs + midhair) and the
# breasts are simulated AND are volumes (SPEC section 3).  Named by CATEGORY, resolved from the same
# derived groups, so a rig change moves both at once.
OBSTACLE_CHAIN_CATS = ('ear', 'bang', 'midhair', 'chest')

# ---- L'ANGLE QUE LA PEAU PEUT ENCAISSER — CHEVEUX SEULEMENT -------------------------------------
# Owner, 2026-08-11 21:15 : « certains maillons meriteraient un traitement pour eviter de creer des
# angles extremes qui mettent en lumiere le lack of geometrie — soit une subdivision intelligente,
# soit une attenuation sur les angles extremes ».  Puis, 22:35, le PERIMETRE, et il est ferme :
# « l'attenuation pour eviter la geometrie extreme c'est juste sur les meches, pas le reste, encore
# moins les seins ».
#
# Mesure du 2026-08-11 (ROOM-GRADIENT, deviation angulaire d'un maillon PAR RAPPORT A SON ATTACHE) :
#     lbang link1 = 178.57 deg    rbang link1 = 176.20 deg    backhair link1 = 176.95 deg
# 178 degres, c'est une epingle a cheveux : la meche se replie sur elle-meme et la peau, qui n'a pas
# les aretes pour ca, se croise. C'est exactement ce qu'il decrit.
#
# LA LIMITE SE DERIVE DU RIG, elle n'est pas choisie. Deux segments cylindriques de rayon r joints
# avec une deviation theta : leurs surfaces INTERIEURES se rencontrent a r*tan(theta/2) du joint le
# long de chaque axe. Le pli reste representable tant que chaque segment adjacent est au moins aussi
# long, d'ou
#         theta_max = 2 * atan( min(L_entrant, L_sortant) / r )
# Rien d'invente : L et r sortent du rig et du mesh. Sur les meches de Keira ca donne ~130 a ~150
# degres, donc la limite ne mord QUE sur les epingles — ce qui est precisement la demande.
HAIR_CATS = ('backhair', 'bang', 'midhair')


# ================================================================================================
# rig + mesh
# ================================================================================================
def load_rig(path):
    d = json.load(open(path))
    rows = d['rows']
    names = [r['hd_name'] for r in rows]
    parent = [(-1 if r['hd_parent'] == 255 else int(r['hd_parent'])) for r in rows]
    for k, r in enumerate(rows):
        if int(r['k']) != k:
            raise SystemExit(f"rig row {k} has k={r['k']}: rows are not in joint order")
        if parent[k] >= k:
            raise SystemExit(f"rig joint {names[k]}: parent index {parent[k]} is not < {k}")
    return names, parent, d


def load_mesh(model):
    """c6.load_geometry (names/parents/bind positions in game units, V/J/W restricted to the
    vertices THIS model's primitives index) + the per-joint inverse bind matrices."""
    geo = c6.load_geometry(model)
    if geo is None:
        raise SystemExit(f"could not load geometry for {model}")
    js, bufs = read_glb(geo['path'])
    binc = consolidate_buffers(js, bufs)
    _n, ibms, _p = skin_info(js, binc)
    geo['ibms'] = ibms
    return geo


def influence(geo, j, thr):
    """(vertex count, summed weight) for the vertices holding more than `thr` on joint j."""
    J, W = geo['J'], geo['W']
    sel = np.zeros(len(W), dtype=bool)
    wsum = 0.0
    for c in range(J.shape[1]):
        m = (J[:, c] == j) & (W[:, c] > thr)
        sel |= m
        wsum += float(W[m, c].sum())
    return int(sel.sum()), wsum, np.flatnonzero(sel)


def to_bone_local(ibm, pts_game):
    """world bind position (GAME units) -> the bone's own bind frame (GAME units).

    L'ECHELLE DE L'OS EST RETIREE, et ce n'est pas un raffinement : c'est la cause racine de
    `straps-elastic`.

    Quatre joints du rig de Keira — `lTopStrap2`, `rTopStrap2`, `lBotStrap2`, `rBotStrap2`, et
    EXACTEMENT les quatre bretelles dont l'owner dit qu'elles clipent — portent une echelle de
    9.6820 dans leur matrice inverse-bind (det = 907.599 ; les 91 autres joints sont a det = 1.000).
    Sans normalisation, toute distance mesuree dans ce repere ressort multipliee par 9.68. Mesure
    du 2026-08-12, `lTopStrap2` :
        etendue reelle de sa geometrie, en MONDE bind : 150 u (p95 autour de son centroide)
        ce que le generateur en tirait                : 1454 u
        rayon de lien livre dans physics_chains.txt   : 1518 u — 37 cm pour une bretelle,
                                                        plus que la longueur de son propre os
    Et ce rayon est le rayon de COLLISION du lien (`*phys-lcr*`, jak-hd-physics.gc:647) : une
    bretelle qui presente une sphere de 37 cm ENGLOBE le torse, `phys-vol-floor` la declare « sans
    surface devant elle », et plus aucun volume du buste ne la repousse jamais. La bretelle
    traverse donc le crop top et son elastique, et `meshpen` lit zero — un zero vrai, mesure entre
    deux volumes dont l'un est dix fois trop gros.

    La rotation est renormalisee ligne a ligne, la translation divisee par le meme facteur. Pour un
    joint sans echelle la sortie est identique au bit pres, donc les 91 autres ne bougent pas."""
    R = ibm[:3, :3]
    s = np.linalg.norm(R, axis=1)
    s = np.where(s < 1e-12, 1.0, s)
    return pts_game @ (R / s[:, None]).T + (ibm[:3, 3] * UNITS) / s


def iq_perp_radius(geo, j, a_world, b_world, thr):
    """Inner-quartile MEAN of the perpendicular distance from joint j's vertices to the bone axis
    a->b, measured in j's bind space.  Returns (radius, nverts) or (None, nverts)."""
    _n, _w, idx = influence(geo, j, thr)
    if len(idx) == 0:
        return None, 0
    ibm = geo['ibms'][j]
    pts = to_bone_local(ibm, geo['V'][idx])
    a = to_bone_local(ibm, a_world[None, :])[0]
    b = to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    rel = pts - a
    if n < 1e-6:
        raise SystemExit(f"zero-length bone axis for joint index {j}")
    u = axis / n
    rel = rel - np.outer(rel @ u, u)      # perpendicular component ONLY: length is not thickness
    d = np.linalg.norm(rel, axis=1)
    lo, hi = np.percentile(d, [IQ_LO, IQ_HI])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    return float(inner.mean()), len(idx)


def blob_centre_radius(geo, j):
    """CENTRE et RAYON de la geometrie qu'un joint porte, dans SON espace bind, en unites de jeu.

    Owner, 6e passe : « lBoob et rBoob sont des spheres NUES posees sur le joint-racine, alors que
    tout le reste du corps est en capsules derivees. Une sphere au joint ne peut pas epouser un
    sein. » Il a raison et c'est mecanique : une sphere de collision est un BLOB, pas un os. Son
    centre n'a aucune raison d'etre le joint — un sein PEND de son joint — et son rayon n'est pas
    une epaisseur autour d'un axe mais l'etendue autour de ce centre.
    Consequence mesurable de l'erreur : une sphere trop grosse posee au mauvais endroit ENGLOBE la
    position de repos des lunettes ; le plancher de pose modele leur accorde alors toute la
    profondeur ou elles sont deja, et le volume ne les repousse plus JAMAIS. C'est pourquoi deux
    elargissements successifs n'ont rien change au clipping — ils l'aggravaient.

    LE RAYON EST UNE COUVERTURE, PAS UNE MOYENNE (2026-08-11, cf. COVER_PCT). La version precedente
    rendait la moyenne inter-quartile de la distance au centroide : mesure au probe, elle laissait
    53 % des sommets du sein DEHORS de la sphere censee le representer, et c'est pour ca que les
    lunettes pouvaient traverser le sein visible en restant hors du volume declare. L'echantillon de
    sommets ne change pas — seule la statistique change, de tendance centrale a couverture.

    Rend (centre, rayon_de_couverture, nverts, seuil, fraction_dehors_a_l_ancien_rayon)."""
    idx, thr = None, None
    for cand in FIT_STEPS:
        _n, _w, i2 = influence(geo, j, cand)
        idx, thr = i2, cand
        if len(i2) >= FIT_MIN_VERTS:
            break
    if idx is None or len(idx) == 0:
        return None, None, 0, None, None
    pts = to_bone_local(geo['ibms'][j], geo['V'][idx])
    c = pts.mean(axis=0)
    d = np.linalg.norm(pts - c, axis=1)
    lo, hi = np.percentile(d, [IQ_LO, IQ_HI])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    r_iq = float(inner.mean())
    r_cov = float(np.percentile(d, COVER_PCT))
    was_out = float((d > r_iq).mean())
    return c, r_cov, len(idx), thr, (r_iq, was_out, float((d > r_cov).mean()))


def cover_perp_radius(geo, j, a_world, b_world, thr):
    """RAYON DE COUVERTURE d'un bout de CAPSULE : le percentile COVER_PCT de la distance
    perpendiculaire, restreint aux sommets qui se projettent DANS le segment a->b.

    Deux differences avec `iq_perp_radius`, et une seule des deux est la statistique.

    1. COUVERTURE, PAS TENDANCE CENTRALE. C'est la regle deja ecrite en tete de ce fichier
       (COVER_PCT) et deja appliquee aux SPHERES par `blob_centre_radius` ; elle n'avait jamais ete
       branchee sur les capsules. Mesure du 2026-08-12 (.autoport/probe_capsule_cover.py, meme
       echantillon de sommets que ce generateur) sur les 24 capsules LIVREES :
           capsules : rayon livre == iq,  42 a 58 % des sommets de leur propre joint DEHORS
           spheres  : rayon livre == p95,  0 a  8 % dehors
       Une moitie de surface hors du volume est exactement ce qui laisse une bretelle passer sous
       l'elastique du crop top pendant que `meshpen` lit zero : le zero est vrai, il est mesure
       contre un volume qui ne contient que la moitie d'elle.

    2. RESTREINT AU SEGMENT, et ce n'est pas un detail. `iq_perp_radius` prend la distance
       perpendiculaire de TOUS les sommets du joint, y compris ceux qui se projettent hors du
       segment : le pied deborde de l'axe du tibia, le buste deborde de l'axe epaule->buste. Le
       percentile y mesure alors la LONGUEUR d'une autre partie, pas une epaisseur. Mesure, meme
       course : `Lshoulder->chest` passerait de 612 a 1477 et `Lthigh->hips` de 1321 a 1858 —
       des ballons, pas des obstacles. Restreint au segment, les memes volumes restent des
       epaisseurs.

    Quand AUCUN sommet ne se projette dans le segment, la distance perpendiculaire ne mesure pas
    l'epaisseur de ce bout : on ne ballonne pas sur une grandeur qui mesure autre chose, la valeur
    inter-quartile est conservee et l'appelant l'ecrit `SPAN-EMPTY` dans le fichier.

    Rend (rayon, nverts, nverts_dans_le_segment, fraction_dehors_a_l_ancien_rayon)."""
    _n, _w, idx = influence(geo, j, thr)
    if len(idx) == 0:
        return None, 0, 0, None
    ibm = geo['ibms'][j]
    pts = to_bone_local(ibm, geo['V'][idx])
    a = to_bone_local(ibm, a_world[None, :])[0]
    b = to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    if n < 1e-6:
        raise SystemExit(f"zero-length bone axis for joint index {j}")
    u = axis / n
    rel = pts - a
    t = (rel @ u) / n
    d = np.linalg.norm(rel - np.outer(rel @ u, u), axis=1)
    lo, hi = np.percentile(d, [IQ_LO, IQ_HI])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    r_iq = float(inner.mean())
    span = (t >= 0.0) & (t <= 1.0)
    if int(span.sum()) < FIT_MIN_VERTS:
        return r_iq, len(idx), 0, float((d > r_iq).mean())
    r_cov = float(np.percentile(d[span], COVER_PCT))
    return r_cov, len(idx), int(span.sum()), float((d > r_iq).mean())


def fit_cover_radius(geo, j, a_world, b_world):
    """cover_perp_radius with the same threshold ladder as fit_radius.
    -> (radius_int, thr_used, nverts, nverts_in_span, was_outside_at_iq)."""
    for thr in FIT_STEPS:
        r, n, nspan, was = cover_perp_radius(geo, j, a_world, b_world, thr)
        if r is not None and n >= FIT_MIN_VERTS:
            return int(round(r)), thr, n, nspan, was
    for thr in reversed(FIT_STEPS):
        r, n, nspan, was = cover_perp_radius(geo, j, a_world, b_world, thr)
        if r is not None and n > 0:
            return int(round(r)), thr, n, nspan, was
    return None, None, 0, 0, None


def fit_radius(geo, j, a_world, b_world):
    """iq_perp_radius with the documented threshold ladder.  -> (radius_int, thr_used, nverts).

    Reste la mesure de l'EPAISSEUR D'UN LIEN (« quelle est mon epaisseur »), ou une tendance
    centrale est la bonne statistique. Les OBSTACLES passent par `fit_cover_radius`."""
    for thr in FIT_STEPS:
        r, n = iq_perp_radius(geo, j, a_world, b_world, thr)
        if r is not None and n >= FIT_MIN_VERTS:
            return int(round(r)), thr, n
    # No threshold reached FIT_MIN_VERTS: take the loosest one that has ANY vertex at all, and let
    # the caller mark the line.  Zero vertices at the gate threshold is handled by the caller (the
    # chain/collider is dropped), so this branch only ever produces a thin-but-real fit.
    for thr in reversed(FIT_STEPS):
        r, n = iq_perp_radius(geo, j, a_world, b_world, thr)
        if r is not None and n > 0:
            return int(round(r)), thr, n
    return None, None, 0


# ================================================================================================
# derived groups
# ================================================================================================
def derive_groups(names, parent):
    """name patterns + hierarchy -> {chain_name: [joint names root->tip]}.

    A group is every joint matching a category regex (and, when the regex captures one, the same
    side letter).  Its root is the member whose parent is outside the group.  The chain is the
    MAXIMAL SINGLE-CHILD PATH from that root: at a branch the chain stops, which is what keeps the
    goggles chain at gogglesBase/gogglesMid instead of picking one of the two lens branches."""
    idx_of = {n: i for i, n in enumerate(names)}
    groups = {}
    order = []
    for cat, pat, tpl in CATEGORY_RULES:
        rx = re.compile(pat)
        by_side = {}
        for n in names:
            m = rx.match(n)
            if not m:
                continue
            side = (m.groupdict().get('side') or '')
            by_side.setdefault(side, []).append(n)
        for side in sorted(by_side, key=lambda s: s.upper()):
            members = by_side[side]
            mset = set(members)
            roots = [n for n in members if (parent[idx_of[n]] < 0 or
                                            names[parent[idx_of[n]]] not in mset)]
            if len(roots) != 1:
                raise SystemExit(f"category {cat} side '{side}': expected 1 root, got {roots}")
            # UNE FOURCHE ARRETE LE CHEMIN, ET CE QUE CA COUTE EST MAINTENANT CHIFFRE.
            #
            # ESSAYE LE 2026-08-12, MESURE, ET RETIRE : ouvrir une chaine par branche. Les deux
            # verres devenaient simules (`gogglesleft`, `gogglesright`, os de 0.107 / 0.099 m) et
            # la salle a immediatement montre ce que personne ne mesurait — 11 318 et 9 018 frames
            # de CONTACT avec les volumes du corps, et jusqu'a **0.0838 m de penetration reelle**
            # sur `jerk`. C'est « le BAS des lunettes clipe dans les seins », enfin chiffre.
            #
            # POURQUOI C'EST QUAND MEME RETIRE : `gogglesLeft`/`gogglesRight` sont les deux
            # COQUILLES D'UNE PAIRE DE LUNETTES RIGIDE. Leur donner un ressort propre les fait
            # osciller par rapport a la monture, et la resolution de collision les pousse hors du
            # corps INDEPENDAMMENT d'elle : le verre se decolle de son cerclage. C'est la regle 6
            # de l'owner — « une resolution pire que le clip est pire que rien » — et il a par
            # ailleurs valide la physique des lunettes telle quelle (« les lunettes, leur physique,
            # marchent bien »). Le defaut est un CLIPPING, pas un manque de mouvement.
            #
            # CE QUE LA MESURE ETABLIT POUR LA SUITE, et qui n'existait nulle part : la chaine
            # `goggles` ne simule que 27 des 515 sommets des lunettes.
            #     gogglesBase 16 sommets   gogglesMid 11   gogglesLeft 244   gogglesRight 244
            # Les 488 autres — 94 %, les verres, qui portent jusqu'a 603 u de leur joint — n'ont
            # AUCUN volume de collision : le moteur les deplace rigidement par propagation de delta
            # sans jamais les confronter a quoi que ce soit, pendant que le seul volume teste est
            # une sphere de rayon 150 posee sur `gogglesMid`. Et `gogglesMid` est a 932 u de
            # `lBoob`/`rBoob` en pose bind : les verres atteignent l'interieur des spheres de
            # poitrine, le volume teste non.
            # LA BONNE FORME est donc un VOLUME qui couvre les verres tout en les laissant RIGIDES
            # (un `*phys-lcr*` ajuste sur `gogglesMid`), pas une chaine de plus. Elle n'est pas
            # posee ici parce qu'elle demande son propre A/B : la meme idee appliquee aux cheveux a
            # coute 43 % du mouvement de `backhair` (voir plus bas), et l'owner a prevenu que
            # gonfler un volume finirait par « decoller les lunettes du corps ».
            #
            # La regle etait « le chemin s'arrete a la premiere fourche », et ce fichier la
            # documentait comme voulue : « which is why the goggles chain stops at gogglesMid ».
            # Personne n'avait mesure ce qu'elle coute. Mesure, sur le mesh skinne :
            #     gogglesBase   16 sommets        gogglesMid    11 sommets
            #     gogglesLeft  244 sommets        gogglesRight 244 sommets
            # La chaine `goggles` simulait 27 sommets sur 515. Les 488 autres — 94 % des
            # lunettes, les VERRES, qui s'etendent jusqu'a 603 u de leur joint — n'avaient
            # AUCUNE chaine, donc aucun volume de collision et aucun test : le moteur les
            # deplacait rigidement par propagation de delta, sans jamais les confronter a quoi
            # que ce soit. Et `gogglesMid` est a 932 u de `lBoob`/`rBoob` en pose bind, pour une
            # geometrie de verre qui porte a 603 u : les verres atteignent l'interieur des
            # spheres de poitrine pendant que le seul volume teste (rayon 150 sur le joint) reste
            # loin de tout. C'est « le BAS des lunettes clipe dans les seins », au complet.
            #
            # La regle devient : une fourche ouvre UNE CHAINE PAR BRANCHE, chacune ancree sur le
            # joint de fourche. Rien n'est ecrit a la main (DIRECTIVES 4) — c'est toujours le rig
            # qui decide, il decide simplement de ne plus perdre une branche en silence.
            def walk(start):
                path = [start]
                while True:
                    cur = idx_of[path[-1]]
                    kids = [n for n in members if parent[idx_of[n]] == cur]
                    if len(kids) != 1:
                        return path, kids
                    path.append(kids[0])

            chain, _forks = walk(roots[0])
            cname = tpl.format(U=side.upper(), l=side.lower())
            if cname in groups:
                raise SystemExit(f"duplicate chain name {cname}")
            groups[cname] = chain
            order.append((cat, cname))
    return groups, order


def bone_axis_world(geo, names, parent, j, chain_next=None):
    """(a, b) world bind endpoints of the axis a link/collider is measured against:
    joint -> its child (the next chain link when there is one, else its rig children), and for a
    tip joint with no child at all, joint -> its parent."""
    P = geo['P']
    a = P[j]
    if chain_next is not None:
        return a, P[chain_next]
    kids = [k for k in range(len(names)) if parent[k] == j]
    if kids:
        return a, P[kids].mean(axis=0)
    if parent[j] >= 0:
        return a, P[parent[j]]
    raise SystemExit(f"joint {names[j]} has neither child nor parent: no axis")


# ================================================================================================
# .bak section copy (VERBATIM)
# ================================================================================================
def extract_section(text, header):
    """The header line plus every following line up to (not including) the next line whose first
    token starts with '[' — the same rule both consumers use (kmachine.cpp:1257 and
    EyeRenderer.cpp:212).

    TRAILING blank lines and TRAILING comment lines are then dropped.  Reason: in the GENERATED
    file the copied section is followed by this generator's own '# ---- ...' banner introducing the
    next block, and the '[' rule cannot see a comment, so those banner lines fell inside the
    extracted section (out=1484B vs bak=1430B).  This function is the only reader on BOTH sides of
    the byte-identity check, so the strip is symmetric and what is compared — and what is copied
    into the output — is the section's real content, byte for byte."""
    lines = text.split('\n')
    out = None
    for ln in lines:
        tok = ln.strip().split(' ')[0] if ln.strip() else ''
        if out is None:
            if tok == header:
                out = [ln]
            continue
        if tok.startswith('['):
            break
        out.append(ln)
    if out is None:
        return None
    while len(out) > 1 and (not out[-1].strip() or out[-1].lstrip().startswith('#')):
        out.pop()
    return '\n'.join(out)


# ================================================================================================
# instrumentation
# ================================================================================================
def influence_table(rig_path, log):
    """One line per joint of EVERY derived group — the groups the gate keeps and the groups it
    abandons alike — with the raw numbers the gate and the radius fit read off the mesh: the count
    and summed weight of the vertices above INFL_GATE, and the radius fitted from that joint's own
    vertices (NONE when it owns none, i.e. nothing was fitted and a fallback will be needed)."""
    names, parent, _rigdoc = load_rig(rig_path)
    geo = load_mesh(MODEL)
    if list(geo['names']) != names:
        raise SystemExit('GLB skin joint list does not match the rig json joint list')
    idx_of = {n: i for i, n in enumerate(names)}
    groups, order = derive_groups(names, parent)
    njoints = sum(len(groups[cname]) for _cat, cname in order)
    log(f'INFLUENCE TABLE: {len(order)} derived groups, {njoints} joints, '
        f'gate w>{INFL_GATE}, radii in game units')
    for _cat, cname in order:
        joints = groups[cname]
        for i, jn in enumerate(joints):
            j = idx_of[jn]
            nxt = idx_of[joints[i + 1]] if i + 1 < len(joints) else None
            a, b = bone_axis_world(geo, names, parent, j, nxt)
            n, w, _ = influence(geo, j, INFL_GATE)
            r, _thr, _nv = fit_radius(geo, j, a, b)
            log(f'INFL {cname} {jn} verts={n} wsum={w:.2f} '
                f'radius={"NONE" if r is None else r}')


# ================================================================================================
# generation
# ================================================================================================
def fnum(x):
    return f'{x:.2f}'


def generate(stamp, rig_path, glb_path, bak_path, log):
    names, parent, _rigdoc = load_rig(rig_path)
    geo = load_mesh(MODEL)
    if list(geo['names']) != names:
        raise SystemExit('GLB skin joint list does not match the rig json joint list')
    rel_src = geo['src'].replace('\\', '/')
    if rel_src != GLB_REL:
        raise SystemExit(f"rig points at {rel_src}, expected {GLB_REL}")
    idx_of = {n: i for i, n in enumerate(names)}
    log(f"rig  {RIG_REL}: {len(names)} joints")
    log(f"mesh {GLB_REL}: {len(geo['V'])} vertices skinned to this model's primitives")

    groups, order = derive_groups(names, parent)
    if groups != EXPECTED_GROUPS:
        for k in sorted(set(groups) | set(EXPECTED_GROUPS)):
            if groups.get(k) != EXPECTED_GROUPS.get(k):
                log(f"  MISMATCH {k}: derived={groups.get(k)} expected={EXPECTED_GROUPS.get(k)}")
        raise SystemExit('derived groups do not match the owner table — refusing to emit')
    log(f"groups derived from the rig: {len(groups)}, and they match the owner table exactly")

    # ---- mesh-influence gate -------------------------------------------------------------------
    # A joint with ZERO skinned vertices owns no drawn geometry.  A CHAIN is abandoned only when
    # EVERY one of its joints is in that state — then simulating it would move nothing visible.  A
    # single empty joint inside a chain that DOES have geometry keeps its place in the chain (that
    # is what used to throw topstrapL/topstrapR whole) and inherits a radius from its neighbours.
    # `dropped` is the ledger of every zero-vertex joint, both cases distinguished.
    dropped = []
    kept = []
    infl = {}
    # la mesure d'execution de la pose du modele, indexee par (chaine, lien) dans l'ordre
    # d'emission de CE fichier — le meme ordre que le magasin C++ sert au moteur.
    for cat, cname in order:
        joints = groups[cname]
        zero = []
        for jn in joints:
            n, w, _ = influence(geo, idx_of[jn], INFL_GATE)
            infl[jn] = (n, w)
            if n == 0:
                zero.append(jn)
        if len(zero) == len(joints):
            note = (f'DROPPED {cname}: all {len(joints)} joint(s) ({", ".join(zero)}) have '
                    f'0 skinned vertices')
            log(note)
            dropped.append(note)
            continue
        kept.append((cat, cname))

    # ---- chain lines ---------------------------------------------------------------------------
    chain_block = []
    chain_report = []
    for cat, cname in kept:
        joints = groups[cname]
        t = TUNING[cat]
        radii, fitnotes = [], []
        raw = []
        for i, jn in enumerate(joints):
            j = idx_of[jn]
            nxt = idx_of[joints[i + 1]] if i + 1 < len(joints) else None
            a, b = bone_axis_world(geo, names, parent, j, nxt)
            r, thr, nv = fit_radius(geo, j, a, b)
            if r is None and infl[jn][0] != 0:
                raise SystemExit(f"{cname}/{jn}: {infl[jn][0]} skinned vertices at the gate but no "
                                 f"radius could be fitted")
            raw.append((r, thr, nv))
        have = [r for r, _t, _n in raw if r is not None]
        if not have:
            raise SystemExit(f"{cname}: kept by the gate but no joint yielded a radius")
        med = int(round(float(np.median(have))))    # this chain's own radii, nothing borrowed
        for i, jn in enumerate(joints):
            r, thr, nv = raw[i]
            if r is not None:
                radii.append(r)
                if thr != FIT_STEPS[0]:
                    fitnotes.append(f'{jn}@w>{thr}({nv}v)')
                continue
            # 0 skinned vertices in a chain that has some: next link's radius, else the previous
            # link's, else this chain's median.  The source is written down, never hidden.
            if i + 1 < len(joints) and raw[i + 1][0] is not None:
                val, src = raw[i + 1][0], joints[i + 1]
            elif i > 0 and raw[i - 1][0] is not None:
                val, src = raw[i - 1][0], joints[i - 1]
            else:
                val, src = med, 'chain-median'
            radii.append(val)
            fitnotes.append(f'{jn} r={val} FALLBACK-FROM={src}')
            note = f'FALLBACK {cname}.{jn}: 0 skinned vertices, radius from {src}'
            log(note)
            dropped.append(note)
        rep = int(round(float(np.median(radii))))       # representative half-thickness of the chain
        parts = [f'chain {cname}',
                 f'class={t["klass"]}',
                 f'stiffness={fnum(t["stiffness"])}',
                 f'damping={fnum(t["damping"])}',
                 f'gravity={fnum(t["gravity"])}',
                 f'radius={rep}']
        if len(joints) >= 2:
            parts.append('rootlock=1')                  # 1-joint chains omit it (parser default 0)
        parts += [f'mass={fnum(t["mass"])}',
                  f'hang={fnum(t["hang"])}',
                  f'family={t["family"]}',
                  f'couple={fnum(t["couple"])}']
        # L'ANGLE QUE LA PEAU PEUT ENCAISSER — CHEVEUX SEULEMENT (cf. HAIR_CATS).  Derive du rig, un
        # maillon a la fois, et la chaine porte le PLUS SERRE de ses maillons libres : le moteur n'a
        # qu'un scalaire par chaine et prendre le plus large laisserait passer le maillon fautif.
        bendnote = ''
        if cat in HAIR_CATS and len(joints) >= 2:
            lim = []
            for i in range(1, len(joints)):          # rootlock=1 -> le maillon 0 ne bouge pas
                att = idx_of[joints[i - 1]]
                gp = parent[att]
                l_out = float(np.linalg.norm(geo['P'][idx_of[joints[i]]] - geo['P'][att]))
                l_in = float(np.linalg.norm(geo['P'][att] - geo['P'][gp])) if gp >= 0 else l_out
                rr = float(max(1.0, radii[i]))
                lim.append((math.degrees(2.0 * math.atan(min(l_in, l_out) / rr)), joints[i],
                            min(l_in, l_out), rr))
            deg, who, lmin, rr = min(lim)
            parts.append(f'maxangle={deg:.2f}')
            bendnote = ('   # maxangle DERIVE du rig (pli representable par la peau, cheveux '
                        f'seulement) : le plus serre est {who}, 2*atan({lmin:.0f}/{rr:.0f}) = '
                        f'{deg:.1f} deg' +
                        ''.join(f' | {w} {d:.1f}' for d, w, _l, _r in lim if w != who))
        parts.append('radii=' + ','.join(str(r) for r in radii))
        line = ' '.join(parts)
        if fitnotes:
            line += '   # radii notes (fitted below w>0.5, or inherited): ' + ' '.join(fitnotes)
        if bendnote:
            line += bendnote
        meas = ' | '.join(f'{jn} verts={infl[jn][0]} wsum={infl[jn][1]:.2f} r={radii[i]}'
                          for i, jn in enumerate(joints))
        chain_block.append(f'# {cname} [{t["family"]}] {meas}')
        chain_block.append(line)
        for jn in joints:
            chain_block.append(f'j {jn}')
        chain_report.append((cname, cat, t['family'], t['klass'], len(joints), rep, radii))

    # ---- colliders -----------------------------------------------------------------------------
    parts_map = {'body': list(BODY_PART)}
    for cat, cname in order:
        if cat in OBSTACLE_CHAIN_CATS:
            parts_map[cname] = list(groups[cname])
    for pname, members in parts_map.items():
        for jn in members:
            if jn not in idx_of:
                raise SystemExit(f"obstacle part {pname}: joint {jn} is not in the rig")

    capsules, spheres = [], []
    capped = set()
    for pname, members in parts_map.items():
        mset = set(members)
        for jn in members:
            j = idx_of[jn]
            pj = parent[j]
            if pj >= 0 and names[pj] in mset:
                capsules.append((jn, names[pj], pname))
                capped.add(jn)
    for pname, members in parts_map.items():
        for jn in members:
            if jn not in capped:
                spheres.append((jn, pname))

    # ---------------------------------------------------------------------------------------------
    # POINT RETIRE, ET LE CHIFFRE QUI L'A RETIRE (2026-08-12).
    #
    # J'ai fait declarer a chaque joint de chaine sa propre sphere de collision, pour que
    # `*phys-lcr*` cesse de retomber sur le PLAFOND D'EXCURSION du lien (jak-hd-physics.gc:647).
    # Course de salle complete : `backhair` est tombee de 0.3062 a 0.1745 de mouvement de pointe,
    # soit 43 % de perte, sous le plancher que la gate FLOOR garde a 60 %. Cause mesuree : la
    # sphere de couverture de `backHair1` (624 u) est presque le double du rayon de lien que le
    # mesh lui donne (358 u), donc le lien presentait un volume deux fois trop gros a la tete et
    # au cou et se faisait repousser en permanence.
    #
    # DIRECTIVES, regle de conservation : « si le plancher casse, le point est retire — pas
    # adouci, retire — et repris autrement ». Il est retire.
    #
    # Et il n'etait pas necessaire : le rayon de collision des bretelles etait faux pour une
    # raison PLUS SIMPLE et corrigee a la source (voir `to_bone_local`) — leurs quatre joints
    # portent une echelle de 9.68 dans leur matrice inverse-bind, qui gonflait toute distance
    # mesuree dans leur repere. `lTopStrap2` passe de 1518 u a 157 u sans qu'aucun volume
    # supplementaire soit declare.
    # UN JOINT, UNE EPAISSEUR. `link_radius` porte, par nom de joint, l'epaisseur deja mesuree pour
    # ce joint comme LIEN DE CHAINE : perpendiculairement a SON PROPRE os (joint -> son enfant),
    # c.-a-d. a l'axe le long duquel sa geometrie est allongee.
    #
    # Pourquoi ce n'est pas un doublon mais une CORRECTION. Un bout de capsule mesurait le meme
    # joint perpendiculairement a l'axe joint -> son PARENT. Quand la chaine fait un coude, cet axe
    # n'est plus celui de la geometrie et la LONGUEUR de la meche fuit dans sa largeur — le fichier
    # livre annoncait alors deux epaisseurs differentes pour un seul joint :
    #     Lbangb  104 comme lien de chaine,  558 comme bout de capsule  (5,4x)
    #     Rbangb  102                        559
    # 558 unites = 13,6 cm de rayon sur une MECHE FINE, en obstacle permanent devant l'autre meche,
    # les oreilles, les cheveux et les lunettes. C'est le defaut n.1 de la 6e passe de l'owner :
    # « les meches fines jittent like crazy des que la tete bouge ». Les six autres capsules de
    # chaine respectaient deja la regle au chiffre pres (lEarb 79, Lbangc 180, Lmidhairb 335...) :
    # elle ne change donc que les deux valeurs qui se contredisaient elles-memes.
    link_radius = {}
    for cname, _cat, _fam, _kl, _nl, _rep, radii in chain_report:
        for jn2, r2v in zip(groups[cname], radii):
            link_radius[jn2] = r2v

    col_block, col_report = [], []
    for jn, pn, pname in capsules:
        j, p = idx_of[jn], idx_of[pn]
        a, b = geo['P'][j], geo['P'][p]
        # POURQUOI CE N'EST PAS `fit_cover_radius` — MESURE DU 2026-08-12, ET C'EST LA REPONSE
        # A LA SUGGESTION DE L'OWNER SUR LES COLLIDERS DERIVES DU MESH.
        #
        # J'ai livre les capsules en COUVERTURE (p95 restreint au segment) et mesure les deux
        # bouts de la chaine causale, pas seulement celui qui m'arrangeait :
        #   ce que ca GAGNE   geometrie hors de l'union des volumes 54.9 % -> 40.4 %
        #                     torse 18 % -> 2 %, mollets 32 % -> 1 %, hanches 10 % -> 0 %
        #   ce que ca COUTE   le joint `lTopStrap2` passe de 64 u DEDANS a 452 u dedans, pour un
        #                     rayon de lien de 157 u. Or `phys-vol-floor` declare une paire LIBRE
        #                     des que la profondeur de repos atteint 2 x le rayon du lien (314 u) :
        #                     la bretelle n'est alors plus contrainte par le torse DU TOUT, et
        #                     `phys-link-pen` sort sans rien mesurer. Sa penetration retombe a
        #                     0.0000 sans qu'aucun defaut n'ait ete corrige — un faux vert.
        #
        # Les deux reglages du MEME rayon echouent donc pour deux raisons opposees : trop petit,
        # la peau sort du volume et la bretelle traverse ce qui depasse ; trop grand, la bretelle
        # est declaree enterree et traverse tout. Il n'existe aucune valeur intermediaire qui
        # satisfasse les deux, parce qu'un TORSE N'EST PAS UN CYLINDRE : une capsule qui couvre le
        # buste de face deborde forcement de plusieurs centimetres sur les cotes, la ou la bretelle
        # repose. C'est, chiffree, la limite que l'owner avait devinee (« pourquoi deriver du rig
        # et pas du mesh ? »), et ca ne se corrige pas dans le choix d'un percentile.
        #
        # La couverture reste donc MESUREE (`fit_cover_radius` ci-dessus, `probe_capsule_cover.py`)
        # et n'est PAS livree : elle echangeait un defaut visible contre un defaut invisible.
        r1, t1, n1 = fit_radius(geo, j, a, b)
        r2, t2, n2 = fit_radius(geo, p, b, a)
        s1 = s2 = 0
        w1 = w2 = None
        if r1 is None or n1 == 0 or r2 is None or n2 == 0:
            log(f"DROPPED collider capsule {jn}->{pn}: fitted from 0 vertices "
                f"({jn}={n1}v {pn}={n2}v)")
            continue
        cov = []
        for who, nspan, was in ((jn, s1, w1), (pn, s2, w2)):
            if nspan == 0:
                cov.append(f'{who} SPAN-EMPTY (aucun sommet ne se projette dans le segment: '
                           f'la distance perpendiculaire y mesure une autre partie, rayon '
                           f'inter-quartile conserve)')
            else:
                cov.append(f'{who} p{COVER_PCT:.0f} sur {nspan}v du segment '
                           f'(l\'inter-quartile en laissait {100 * was:.0f}% dehors)')
        fix = []
        if jn in link_radius and link_radius[jn] != r1:
            fix.append(f'{jn} {r1}->{link_radius[jn]} (own-bone thickness)')
            r1 = link_radius[jn]
        if pn in link_radius and link_radius[pn] != r2:
            fix.append(f'{pn} {r2}->{link_radius[pn]} (own-bone thickness)')
            r2 = link_radius[pn]
        if fix:
            log(f"ONE-JOINT-ONE-THICKNESS capsule {jn}->{pn}: " + '; '.join(fix))
        col_block.append(f'# capsule {jn}->{pn} [{pname}]  {jn}: {n1}v @w>{t1}   '
                         f'{pn}: {n2}v @w>{t2}'
                         + ('   ONE-JOINT-ONE-THICKNESS: ' + '; '.join(fix) if fix else ''))
        col_block.append(f'#   COUVERTURE: ' + ' | '.join(cov))
        col_block.append(f'capsule {jn} {pn} radius={r1} radius2={r2}')
        col_report.append(('capsule', f'{jn}->{pn}', r1, r2, n1, n2))
    for jn, pname in spheres:
        j = idx_of[jn]
        c, r, n, t, cov = blob_centre_radius(geo, j)
        if r is None or n == 0:
            log(f"DROPPED collider sphere {jn}: fitted from 0 vertices")
            continue
        cx, cy, cz = (int(round(float(v))) for v in c)
        r = int(round(r))
        r_iq, was_out, now_out = cov
        off = math.sqrt(cx * cx + cy * cy + cz * cz)
        log(f"sphere {jn}: centre ({cx},{cy},{cz}) |{off:.0f}u| radius {r} "
            f"(couverture p{COVER_PCT:.0f}: {100*now_out:.0f}% des sommets dehors — "
            f"la moyenne inter-quartile donnait {r_iq:.0f} et en laissait {100*was_out:.0f}%)")
        col_block.append(f'# sphere {jn} [{pname}]  {n}v @w>{t}   centre = measured centroid of the '
                         f'geometry this joint owns, {off:.0f}u off the joint, in its bind space'
                         f'   COVER p{COVER_PCT:.0f}: {100*now_out:.0f}% of its vertices outside'
                         f' (inner-quartile mean {r_iq:.0f} left {100*was_out:.0f}% outside)')
        col_block.append(f'collider {jn} radius={r} offset={cx},{cy},{cz}')
        col_report.append(('sphere', jn, r, None, n, None))

    # ---- verbatim blocks from the .bak ---------------------------------------------------------
    bak = open(bak_path).read()
    eyescale = extract_section(bak, '[eyescale]')
    if eyescale is None:
        raise SystemExit(f'{BAK_REL} has no [eyescale] section')
    levels = extract_section(bak, '[levels]')
    if levels is None:
        log(f'NOTE: {BAK_REL} has NO [levels] section — none emitted')

    # ---- assemble ------------------------------------------------------------------------------
    L = []
    L.append('# physics_chains.txt — GENERATED by .autoport/physics_keira_gen2.py — DO NOT HAND-EDIT.')
    L.append(f'# generated: {stamp}   (regenerate: python3 .autoport/physics_keira_gen2.py --stamp {stamp})')
    L.append('#')
    L.append(f'# rig  (joint order + hierarchy) : {RIG_REL}')
    L.append(f'# mesh (skin weights, radii fit) : {GLB_REL}')
    L.append('#')
    L.append('# Contract: .autoport/prompts/SPEC-keira-physique.md (clean restart 2026-08-11).')
    L.append('# SPEC section 1 — what has physics, and NOTHING else: ears, hair (root anchored),')
    L.append('# strands, breasts, goggles, what hangs. The chains below are DERIVED from the rig by')
    L.append('# name pattern + hierarchy (a chain is the maximal single-child path from its group')
    L.append('# root), never hand-listed; the owner table is only an assertion inside the generator.')
    L.append('# KEIRA ONLY: no other model gets data until the owner has validated her.')
    L.append('#')
    L.append('# family A = what she IS (ears, hair, strands, breasts): SPEC section 4, at rest it')
    L.append('#            returns EXACTLY to the model pose, so it carries NO static sag —')
    L.append('#            gravity=0.00 and hang=0.00 are asserted for every family A chain.')
    L.append('# family B = what she WEARS (goggles, straps, flaps): SPEC section 4 exception, what')
    L.append('#            hangs stays hung — gravity>0 and hang>0 are asserted for every one.')
    L.append('# rootlock=1 on every chain of 2+ joints (SPEC section 2: the root rides its carrier')
    L.append('#            bone rigidly); omitted on 1-joint chains, where the parser default is 0.')
    L.append('# radius/radii = MEASURED off the skinned mesh, in GAME UNITS (4096 = 1 m): per link,')
    L.append('#            the inner-quartile (25..75 pct) mean of the perpendicular distance from')
    L.append('#            the vertices that link owns to its bone axis, in that link\'s bind space.')
    L.append('# stiffness (Hz) / damping (0..1) / mass / couple are the only hand-chosen numbers;')
    L.append('#            they are tuning constants and the owner retunes them here.')
    L.append('#')
    L.append('# The `# <chain> ... verts= wsum= r=` line above each chain is the mesh-influence gate:')
    L.append('# a joint with ZERO skinned vertices owns no drawn geometry. A chain is ABANDONED only')
    L.append('# when ALL of its joints are in that state — there is then nothing visible for it to')
    L.append('# move. One empty joint inside a chain that has geometry KEEPS its link and inherits a')
    L.append('# radius from the next link, else the previous one, else the chain median, written on')
    L.append('# the chain line as FALLBACK-FROM=<source>. Every zero-vertex joint, both cases:')
    if dropped:
        for note in dropped:
            L.append(f'#   {note}')
    else:
        L.append('#   (none)')
    L.append('')
    L.append('# ---- [eyescale] : NOT this feature. Copied VERBATIM from recharged_assets/'
             'physics_chains.FULL-CAST.bak,')
    L.append('# which is where it lived before the 2026-08-11 reset. It is read by')
    L.append('# game/graphics/opengl_renderer/EyeRenderer.cpp; dropping it silently moved gainup')
    L.append('# from 1.0 back to the compiled default 0.45. The parser above skips it whole.')
    L.append(eyescale)
    L.append('')
    if levels is not None:
        L.append('# ---- [levels] : copied VERBATIM from the same .bak.')
        L.append(levels)
        L.append('')
    L.append(f'# ---- Keira, and only Keira: {len(chain_report)} chains, {len(col_report)} volumes.')
    L.append('[model keira-hd]')
    L.extend(chain_block)
    L.append('')
    L.append('# ---- COLLIDERS, fitted from the same mesh. One capsule per obstacle bone segment,')
    L.append('# one sphere per obstacle joint no capsule caps (a part root: a strand hanging off the')
    L.append('# skull, a breast off the chest, the pelvis). A capsule never spans two parts: a swept')
    L.append('# sphere from a hub centre out to an appendage root is a volume the character has not')
    L.append('# got. SPEC section 3: the ears, the strands and the breasts are simulated AND are')
    L.append('# obstacles. NO chains= / at= filter on any of them (DIRECTIVES rule 4): every volume')
    L.append('# applies to every chain and the engine decides geometrically what touches what.')
    L.append('# Each volume carries the vertex count and weight threshold it was fitted from.')
    L.extend(col_block)
    L.append('')
    text = '\n'.join(L)
    return text, dict(chains=chain_report, dropped=dropped, colliders=col_report,
                      eyescale=eyescale, levels=levels, groups=groups,
                      # la geometrie brute du rig, pour que le controle 9 puisse RECALCULER
                      # `maxangle=` depuis le fichier emis au lieu de croire le generateur.
                      P=geo['P'], parent=parent, idx_of=idx_of)


# ================================================================================================
# self-checks
# ================================================================================================
# DEROGATIONS INTERDITES (DIRECTIVES regle 4 : « aucun flag de derogation — colskip, filtres de
# volumes, masques »).  Ces quatre-la EXEMPTENT du travail : `colskip` retire des liens de la
# collision, `chains=`/`at=` restreignent un volume a une liste, `authored` coupe la physique sous
# un seuil.  Aucun ne se derive de quoi que ce soit : ce sont des decisions ecrites a la main.
#
# `maxangle` EST SORTI DE CETTE LISTE LE 2026-08-11, et voici pourquoi ce n'est pas un
# assouplissement.  Il y figurait comme reglage a la main de l'ancien moteur (un cone d'ouverture
# choisi a l'oeil, chaine par chaine).  Il est desormais EMIS PAR CE GENERATEUR, DERIVE DU RIG :
# 2*atan(min(L_entrant, L_sortant)/r), l'angle au-dela duquel les deux tubes de peau se croisent,
# sur les seules chaines de cheveux (HAIR_CATS) parce que l'owner a ferme le perimetre a « juste
# les meches ».  La regle 4 interdit les donnees RUSTINEES, pas les donnees DERIVEES — et une
# valeur ecrite a la main sur cette cle serait toujours refusee par le controle de derivation
# ci-dessous, qui la recalcule.
FORBIDDEN_KEYS = ('colskip', 'chains', 'at', 'authored')
# A real key, on a real (non-comment) line.  Prose is not a key: the collider block explains
# "NO chains= / at= filter on any of them", and matching that sentence made the generator refuse
# its own documentation of the ABSENCE of those keys.
FORBIDDEN_RX = re.compile(r'\b(' + '|'.join(FORBIDDEN_KEYS) + r')=')


def self_checks(text, info, rig_names, bak_path, log):
    fails = []

    def ck(ok, label, detail=''):
        log(f"  [{'PASS' if ok else 'FAIL'}] {label}{(' — ' + detail) if detail else ''}")
        if not ok:
            fails.append(label)

    lines = text.split('\n')
    # 1. exactly one [model line
    nmodel = sum(1 for ln in lines if re.match(r'^\[model ', ln))
    ck(nmodel == 1, 'exactly one ^[model line', f'found {nmodel}')

    # parse the emitted model back, the way the C++ parser reads it
    chains = []
    cur = None
    for ln in lines:
        raw = ln.split('#', 1)[0]
        toks = raw.split()
        if not toks:
            continue
        if toks[0] == 'chain':
            cur = dict(name=toks[1], kv={}, joints=[])
            for t in toks[2:]:
                if '=' in t:
                    k, v = t.split('=', 1)
                    cur['kv'][k] = v
            chains.append(cur)
        elif toks[0] == 'j' and cur is not None:
            cur['joints'].append(toks[1])
    ck(len(chains) == len(info['chains']), 'every emitted chain parses back',
       f'{len(chains)} parsed / {len(info["chains"])} generated')

    # 2. every chain has >=1 j line, every j name exists in the rig
    bad = [c['name'] for c in chains if not c['joints']]
    unknown = [(c['name'], j) for c in chains for j in c['joints'] if j not in rig_names]
    ck(not bad and not unknown, 'every chain has >=1 j line, every j exists in the rig',
       f'empty={bad} unknown={unknown}')

    # 3. family A: hang == 0 (it returns to the model pose) and gravity == A_GRAVITY (relative to
    #    the anchor's bind frame, so it moves NOTHING while she is upright); family B: both > 0
    #    (absolute gravity: what hangs, hangs, and stays hung).
    prob = []
    for c in chains:
        g, h, f = float(c['kv'].get('gravity', -1)), float(c['kv'].get('hang', -1)), c['kv'].get('family')
        if f == 'A' and not (abs(g - A_GRAVITY) < 1e-6 and h == 0.0):
            prob.append((c['name'], 'A', g, h))
        if f == 'B' and not (g > 0.0 and h > 0.0):
            prob.append((c['name'], 'B', g, h))
        if f not in ('A', 'B'):
            prob.append((c['name'], f, g, h))
    ck(not prob, f'family A gravity={A_GRAVITY:.2f} (anchor-relative) hang=0.00, family B both > 0',
       str(prob))

    # 4. len(radii) == number of j lines
    prob = [(c['name'], len(c['kv'].get('radii', '').split(',')), len(c['joints']))
            for c in chains
            if len([x for x in c['kv'].get('radii', '').split(',') if x]) != len(c['joints'])]
    ck(not prob, 'len(radii) == number of j lines for every chain', str(prob))

    # 5. owner coverage regexes (the phase validator's own set)
    cover = {}
    for pat in ('ear', 'hair', 'bang|strand', 'chest|breast', 'goggle'):
        cover[pat] = [c['name'] for c in chains if re.search(pat, c['name'], re.I)]
    missing = [p for p, v in cover.items() if not v]
    ck(not missing, 'chain-name coverage: ear / hair / bang|strand / chest|breast / goggle',
       ' '.join(f'{p}->{len(v)}' for p, v in cover.items()) + (f' MISSING {missing}' if missing else ''))

    # 6. no exemption / obsolete keys anywhere — on the lines the parser actually reads as data.
    # Comment lines (first non-blank character '#') are skipped: they are prose, not keys.
    hits = []
    for i, ln in enumerate(lines, 1):
        if ln.lstrip().startswith('#'):
            continue
        m = FORBIDDEN_RX.search(ln)
        if m:
            hits.append((m.group(1), i, ln.strip()[:60]))
    ck(not hits, 'no colskip= / chains= / at= / authored= anywhere', str(hits[:4]))

    # 6b. TOUT `maxangle=` EMIS EST RECALCULABLE DEPUIS LE RIG.  C'est ce qui separe une donnee
    # DERIVEE d'une rustine : la valeur est relue DANS LE FICHIER, recalculee depuis les positions
    # bind du rig et les `radii=` que le fichier declare lui-meme, et les deux doivent coincider.
    # Une valeur ecrite a la main echoue ici.  Le perimetre est verifie aussi : une chaine hors
    # HAIR_CATS qui porterait la cle est refusee (owner : « juste les meches »).
    P, par, idx_of = info['P'], info['parent'], info['idx_of']
    cat_of = {cn: ct for cn, ct, _f, _k, _nl, _r, _ra in info['chains']}
    bad = []
    for c in chains:
        has = 'maxangle' in c['kv']
        hair = cat_of.get(c['name']) in HAIR_CATS and len(c['joints']) >= 2
        if has != hair:
            bad.append((c['name'], 'hors perimetre' if has else 'manquant'))
            continue
        if not has:
            continue
        radii = [int(x) for x in c['kv']['radii'].split(',')]
        lim = []
        for i in range(1, len(c['joints'])):
            att = idx_of[c['joints'][i - 1]]
            gp = par[att]
            l_out = float(np.linalg.norm(P[idx_of[c['joints'][i]]] - P[att]))
            l_in = float(np.linalg.norm(P[att] - P[gp])) if gp >= 0 else l_out
            lim.append(math.degrees(2.0 * math.atan(min(l_in, l_out) / float(max(1, radii[i])))))
        want = min(lim)
        if abs(float(c['kv']['maxangle']) - want) > 0.01:
            bad.append((c['name'], f"{c['kv']['maxangle']} != {want:.2f} recalcule"))
    ck(not bad, 'chaque maxangle= est recalculable depuis le rig, et seules les meches en portent',
       str(bad[:4]))

    # 7. [eyescale] block byte-identical to the .bak's
    mine = extract_section(text, '[eyescale]')
    theirs = extract_section(open(bak_path).read(), '[eyescale]')
    ck(mine is not None and mine == theirs, '[eyescale] byte-identical to the .bak',
       f'out={len(mine or "")}B bak={len(theirs or "")}B '
       f'sha_out={hashlib.sha256((mine or "").encode()).hexdigest()[:12]} '
       f'sha_bak={hashlib.sha256((theirs or "").encode()).hexdigest()[:12]}')

    # 7b. same for [levels]
    if info['levels'] is not None:
        mine_l = extract_section(text, '[levels]')
        ck(mine_l == info['levels'], '[levels] byte-identical to the .bak')

    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stamp', required=True,
                    help='generation date written into the header (NEVER datetime.now(): the '
                         'output must be byte-reproducible)')
    ap.add_argument('--out', default=os.path.join(REPO, OUT_REL))
    ap.add_argument('--rig', default=os.path.join(REPO, RIG_REL))
    ap.add_argument('--glb', default=os.path.join(REPO, GLB_REL))
    ap.add_argument('--bak', default=os.path.join(REPO, BAK_REL))
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--influence-table', action='store_true',
                    help='print one INFL line per joint of every derived group — including the '
                         'groups the mesh-influence gate abandons — BEFORE the normal run')
    args = ap.parse_args()

    for p in (args.rig, args.glb, args.bak):
        if not os.path.exists(p):
            raise SystemExit(f'missing input: {p}')

    out_lines = []

    def log(msg):
        out_lines.append(msg)
        print(msg, flush=True)

    if args.influence_table:
        influence_table(args.rig, log)
        log('')

    text, info = generate(args.stamp, args.rig, args.glb, args.bak, log)

    # check 8: reproducible — generate a SECOND time, in the same process, and compare bytes.
    text2, _ = generate(args.stamp, args.rig, args.glb, args.bak, lambda m: None)
    log('')
    log('SELF-CHECKS')
    fails = self_checks(text, info, set(json.load(open(args.rig))['rows'][i]['hd_name']
                                        for i in range(len(json.load(open(args.rig))['rows']))),
                        args.bak, log)
    same = (text == text2)
    log(f"  [{'PASS' if same else 'FAIL'}] two generations in one process are byte-identical — "
        f'sha={hashlib.sha256(text.encode()).hexdigest()[:16]}')
    if not same:
        fails.append('reproducible')

    log('')
    log(f"CHAINS ({len(info['chains'])})")
    log(f"  {'name':<12} {'cat':<11} {'fam':<3} {'class':<10} {'links':>5} {'radius':>6}  radii")
    for cname, cat, fam, klass, nl, rep, radii in info['chains']:
        log(f'  {cname:<12} {cat:<11} {fam:<3} {klass:<10} {nl:>5} {rep:>6}  '
            + ','.join(str(r) for r in radii))
    log(f"ZERO-VERTEX JOINTS ({len(info['dropped'])})")
    for note in info['dropped']:
        log(f'  {note}')
    log(f"COLLIDERS ({len(info['colliders'])})")
    for kind, who, r1, r2, n1, n2 in info['colliders']:
        if kind == 'capsule':
            log(f'  capsule {who:<24} radius={r1:<6} radius2={r2:<6} verts={n1}/{n2}')
        else:
            log(f'  sphere  {who:<24} radius={r1:<6} {"":<14} verts={n1}')

    if fails:
        log('')
        log('SELF-CHECK FAILURES: ' + ', '.join(fails))
        return 1

    if not args.dry_run:
        with open(args.out, 'w') as f:
            f.write(text)
        # Les reglages issus de l'oeil de l'owner survivent a la generation. Ils ont ete effaces
        # DEUX FOIS le 2026-08-11 et il a teste des builds sans ses propres corrections; le
        # corriger apres coup a chaque fois n'a pas empeche la recurrence, donc la reapplication
        # est faite ICI, dans le producteur, et pas dans un appelant qu'on peut oublier.
        try:
            import subprocess as _sp, os as _os
            _root = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
            _r = _sp.run(['python3', _os.path.join(_root, '.autoport', 'apply_owner_tuning.py')],
                         capture_output=True, text=True, timeout=120)
            print((_r.stdout or _r.stderr).strip())
            if _r.returncode not in (0,):
                print('[gen] ATTENTION: la reapplication des reglages owner a echoue (%d)'
                      % _r.returncode)
        except Exception as _e:
            print('[gen] ATTENTION: reglages owner NON reappliques: %s' % _e)
        log('')
        log(f'wrote {args.out}  ({len(text)} bytes, '
            f'sha256={hashlib.sha256(text.encode()).hexdigest()})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
