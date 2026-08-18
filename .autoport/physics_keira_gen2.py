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
# The mesh actually read, resolved from the rig json at generate() time. GLB_REL is the BASE donor;
# when joints are injected the rig records the derived donor and this carries it into the header,
# so the emitted file never misstates its own input.
RESOLVED_GLB = GLB_REL
# LE MESH QUE LE JEU RECOIT — et donc la SEULE ponderation de peau qui existe a l'ecran.
# `<char>-k2e.json` designe l'INTERMEDIAIRE (pre-prep, pre-reskin) : c'est le bon fichier pour la
# HIERARCHIE (il porte les 107 joints du rig, `align` compris) et le mauvais pour les POIDS.
# `graft_shipped_weights` prend donc la hierarchie chez l'un et les poids chez l'autre.
SHIPPED_REL = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
# La source de peau reellement lue, resolue a l'execution et recopiee dans l'en-tete emis, pour que
# le fichier livre ne puisse pas se tromper sur sa propre entree.
RESOLVED_SKIN = SHIPPED_REL
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

# ---- COQUES : `shell=` — UN FOURREAU N'EST PAS UNE SPHERE DE POUSSEE ---------------------------
# DEFAUT OUVERT `pant-calf`, signale par l'owner a chaque passe : « le bas du pantacourt est
# toujours a l'interieur des mollets, comme si son pantacourt s'arretait aux genoux ».
#
# CAUSE MESUREE. Le pan de pantacourt est une COQUE FERMEE autour du mollet. Son rayon livre (429 a
# gauche, 443 a droite) est le rayon du FOURREAU autour de la jambe, et le moteur s'en sert comme
# rayon d'une SPHERE DE POUSSEE centree sur le lien. Le centroide du pan etant a 95 u de l'axe du
# mollet — c'est-a-dire SUR l'axe — la resolution de collision lit ~700 u de penetration et ejecte
# le pan lateralement a chaque frame : la moitie du tissu finit dans la jambe. Pousser un fourreau
# « hors » du membre qu'il entoure n'a aucun sens geometrique ; la contrainte due a un tel lien est
# la CONCENTRICITE, et le moteur a besoin de savoir QUELS liens sont des fourreaux. `shell=` est ce
# renseignement, et c'est la seule chose que ce generateur en fait.
#
# LA REGLE EST MESUREE, ELLE N'EST PAS CHOISIE — et deux formulations plus evidentes ont ete
# essayees et REFUSEES par la mesure, sur les 37 liens de chaine du rig :
#   * couverture angulaire autour de l'axe DU JOINT LUI-MEME : NE DISCRIMINE PAS. Une meche est un
#     tube autour de son propre os exactement comme un fourreau (`Lbanga` 12/12, `backHair1` 10/12,
#     `lEarb` 10/12, comme `LpantFlap` 10/12).
#   * repli sur la direction principale (PCA) : PIRE. Il fait passer `lKneeFlap` — la languette
#     PLATE, controle negatif de l'owner — de 5/12 a 10/12.
# CE QUI DISCRIMINE : la couverture angulaire des sommets du joint autour de l'axe d'un volume
# ETRANGER, c.-a-d. une capsule dont NI l'un NI l'autre de ses deux joints n'appartient a la chaine
# testee (meme exclusion structurelle que `phys-col-own?`, jak-hd-physics.gc). Un lien n'enroule un
# os qui n'est pas le sien que s'il en est le fourreau.
#
#     12 secteurs de 30 degres autour de l'axe du volume, en espace bind MONDE,
#     SUR LES SEULS SOMMETS DONT L'ABSCISSE TOMBE DANS LE SEGMENT (t dans [0,1]).
#     gap = (plus long run de secteurs vides + 1) * 30 degres.
#     COQUE  <=>  il existe un volume etranger avec  secteurs >= 10/12  ET  gap <= 60 deg.
#
# ---- CORRECTION DU CYCLE 22 : LE TEST ANGULAIRE PRENAIT UNE DROITE POUR UN SEGMENT -------------
# Le detecteur de derive ci-dessous (`SHELL_EXPECTED`) a TIRE des que le generateur a cesse de lire
# le donneur pour lire le mesh LIVRE (`graft_shipped_weights`) : il classait alors COQUE
# `lmidhair` et `rmidhair` EN PLUS des deux pans, et la POITRINE arrivait a 10/12 secteurs / 90 deg
# — a un cran de gap d'etre declaree fourreau, c'est-a-dire de casser l'acquis que l'owner a
# valide dessus. La regle avait donc cesse de DISCRIMINER (SPEC 7 : « une mesure doit
# discriminer »), et ce n'est pas le repesage qui l'a cassee : il l'a REVELEE. Les poids diffus du
# donneur masquaient le defaut ; les poids concentres du mesh livre l'ont fait sortir.
#
# LE DEFAUT, ET IL EST GEOMETRIQUE, PAS STATISTIQUE. La couverture etait calculee autour de la
# DROITE INFINIE portant l'axe du volume, sans exiger que les sommets soient LE LONG du segment.
# Or la droite du tibia prolongee vers le haut passe pres du torse et de la tete : tout ce qui est
# un tube autour de la verticale « enroulait » le mollet. Mesure sur le mesh LIVRE, fraction des
# sommets du lien dont l'abscisse tombe dans le segment `Lankle->Lknee` :
#     LpantFlap   t 0.49..0.65   100 %   <- vrai fourreau, il gaine le tibia
#     RpantFlap   t 0.49..0.65   100 %   <- vrai fourreau
#     Lmidhaira   t 3.60..3.92     0 %   <- des cheveux, 3.8 longueurs de tibia au-dessus du genou
#     Rmidhaira   t 3.60..3.92     0 %
#     lBoob       t 2.65..2.82     0 %   <- la POITRINE, a 10/12 secteurs d'un axe qui ne la
#     rBoob       t 2.66..2.84     0 %      traverse jamais
# `shell_rr_at` bornait DEJA `t0` a [0,1] « COMME LE MOTEUR LE FAIT » (`phys-collide-depth`) : le
# test angulaire etait le seul endroit du fichier qui traitait un volume BORNE comme une droite
# INFINIE. La correction aligne les deux. AUCUN SEUIL NOUVEAU N'EST INTRODUIT.
#
# CE QUE LA CORRECTION DONNE, AVEC SES DEUX CONTROLES :
#     pantflapL/R  10/12 / 60 deg, 100 % dans le segment      COQUE   (inchange — la regle tient)
#     lmidhair/rmidhair  leur meilleur volume n'est meme plus le mollet : 7/12 / 180 deg
#     chestL/chestR  10/12 / 90 deg  ->  3/12 / 300 deg       la marge passe d'un cran a huit
#     kneeflapL/R (controle NEGATIF de l'owner)  2/12 / 330 deg        inchange
# CONTROLE POSITIF, la regle DOIT encore tirer — la PEAU autour de SON PROPRE os (l'exclusion
# « etranger » est levee expres), axe = la capsule EMISE qui porte le joint, car la chair de
# `Lknee` gaine le TIBIA et non la cuisse :
#     Lknee 12/12 / 30 deg (94 % dans le segment) · Rknee 12/12 / 30 · Lthigh 12/12 / 30 (89 %)
#     chest 12/12 / 30 (87 %) · main 12/12 / 30 (100 %) · Lelbow 11/12 / 60 (98 %)
# soit exactement les valeurs que ce bloc documentait avant la correction. La regle designe donc
# toujours ce qu'elle doit designer, et ne designe plus ce qu'elle n'aurait jamais du.
#
# RESULTAT MESURE (table complete journalisee a chaque generation, section COQUES) :
#     LpantFlap -> Lankle->Lknee   10/12,  60 deg    COQUE
#     RpantFlap -> Rankle->Rknee   10/12,  60 deg    COQUE
#     les 33 autres liens          AUCUN — le meilleur non-pan est `Rmidhairb` 8/12 / 150 deg,
#                                  puis `lBoob`/`rBoob` 8/12 / 120 deg ; `lKneeFlap`/`rKneeFlap`
#                                  (le controle negatif de l'owner) 2/12 / 330 deg.
# CONTROLE POSITIF, la regle DOIT tirer : appliquee a la PEAU — qui est litteralement un fourreau
# autour de l'os — elle classe coque `Lknee`, `Rknee`, `Lthigh`, `chest`, `head`, `main` a 12/12 /
# 30 deg et `Lelbow` a 11/12 / 60 deg.
#
# PIEGE MESURE, A NE PAS REPRODUIRE : la classification n'est PAS invariante au seuil de poids de
# skinning. Evaluee a `w>0.05` pour TOUT LE MONDE, elle classerait coques `Lmidhaira` (12/12),
# `Rmidhaira` (12/12), `lBoob` (11/12) et `rBoob` (11/12) — la poitrine deviendrait un fourreau et
# l'acquis que l'owner a valide dessus serait casse. La regle est donc evaluee sur EXACTEMENT la
# selection de sommets que ce generateur utilise deja pour ses rayons : l'echelle FIT_STEPS avec
# FIT_MIN_VERTS (`shell_select` ci-dessous est la meme echelle que `fit_radius`). Les pantflaps sont
# les SEULS joints dont l'echelle descend jusqu'a 0.05. TOUT CHANGEMENT DE `FIT_STEPS` OU DE
# `FIT_MIN_VERTS` CHANGE CETTE CLASSIFICATION : la self-check COQUES est ce qui le fera echouer au
# lieu de livrer silencieusement une poitrine declaree fourreau.
SHELL_NSEC = 12
SHELL_SECW = 360.0 / SHELL_NSEC
SHELL_SECT_MIN = 10             # secteurs occupes exiges sur 12
SHELL_GAP_MAX = 60.0            # plus grand trou angulaire tolere, en degres
# Les seules chaines que la regle doit designer sur CE rig. C'est une ASSERTION sur ce que la regle
# produit, pas une liste qui la remplace : le classement est calcule pour les 37 liens et publie.
SHELL_EXPECTED = ('pantflapL', 'pantflapR')

# ---- PERIMETRE SIMULE — ORDRE DE L'OWNER DU 2026-08-14 07:30 -----------------------------------
#
#   « Les cheveux, les bretelles, les lunettes sont completement petees, les languettes des genoux
#     sont completement petees... Les languettes sur ses bottines aussi... On voit un peu plus son
#     pantacourt mais c'est aussi pete et toujours dans ses mollets. Tu sais quoi, RETIRE TOUTE
#     PHYSIQUE DE KEIRA HORMIS SES SEINS. Fais la spec de ses seins a 100% comme specifie, on fera
#     le reste apres. »
#
# UNE CHAINE HORS PERIMETRE N'EST PAS EMISE INERTE : ELLE N'EST PAS EMISE DU TOUT. Un `PHYSBONE`
# qui existe et ne bouge pas reste un risque de derive et un cout par frame, et il continuerait a
# faire croire au tableau qu'il mesure quelque chose.
#
# POURQUOI ICI ET NULLE PART AILLEURS. `physics_chains.txt` est GENERE : une desactivation ecrite
# a la main dans le fichier livre serait effacee a la premiere regeneration — piege deja paye trois
# fois (DIRECTIVES, regle de non-destruction du 2026-08-11). La desactivation vit donc au POINT DE
# PRODUCTION, ou elle est impossible a perdre, pas au point de controle ou elle serait seulement
# detectable.
#
# CE QUI N'EST PAS CONCERNE : LES COLLIDERS. Ce sont des OBSTACLES, pas des chaines simulees. La
# poitrine doit continuer a les rencontrer — SPEC-breast-softbody 33 (sein<->sein, restitution
# 0.06) et 34 (sein<->thorax, 0.02) — et SPEC-keira-physique 3 exige que le crane, les epaules et
# les oreilles restent des volumes. Le bloc de colliders lit `order`/`groups`, jamais cette liste :
# il est inchange au chiffre pres par le gel des chaines.
#
# LEVEE DU GEL : c'est l'owner qui la prononce, jamais une mesure verte. Rajouter un nom ici suffit
# a reactiver l'organe ET toutes les gates qui le concernent (le validateur derive son perimetre de
# la liste des chaines DECLAREES, pas d'une liste ecrite en dur de son cote).
SIMULATED_CHAINS = ('chestL', 'chestR')

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
    # `Boo[bc]` et non `Boob` : l'injection du 2026-08-17 ajoute le joint distal `lBooc`/`rBooc`.
    # Meme piege que `lKneeFlap2` documente juste en dessous — sans elargir la regex le joint
    # injecte n'appartient a AUCUN groupe, la chaine reste a UN maillon, et `EXPECTED_GROUPS`
    # serait d'accord avec elle : les deux se tromperaient ensemble, sans que rien ne le dise.
    ('chest',      r'^(?P<side>[lr])Boo[bc]$',             'chest{U}'),
    ('goggles',    r'^goggles[A-Z][a-z]*$',                'goggles'),
    ('topstrap',   r'^(?P<side>[lr])TopStrap\d*$',         'topstrap{U}'),
    ('botstrap',   r'^(?P<side>[lr])BotStrap\d*$',         'botstrap{U}'),
    ('belt',       r'^belt$',                              'belt'),
    # `\d*` comme topstrap/botstrap ci-dessus : le rig utilise DEJA la convention des paires
    # numerotees (lTopStrap/lTopStrap2), et l'injection de joints du 2026-08-13 la reprend pour
    # `lKneeFlap2`. Sans le `\d*` le joint injecte n'appartenait a AUCUN groupe, la chaine restait
    # a un seul maillon, et `EXPECTED_GROUPS` etait d'accord avec elle — les deux se trompaient
    # ensemble, donc l'assertion ne pouvait pas le voir. La table declare desormais l'intention
    # (2 maillons) et c'est elle qui force la regex a suivre.
    ('kneeflap',   r'^(?P<side>[lr])KneeFlap\d*$',         'kneeflap{U}'),
    ('pantflap',   r'^(?P<side>[LR])pantFlap$',            'pantflap{U}'),
    ('toestrap',   r'^(?P<side>[LR])toeStrap$',            'toestrap{U}'),
    ('anklestrap', r'^(?P<side>[LR])anklestrap$',          'anklestrap{U}'),
]

# The owner's table, kept ONLY as an assertion on what the rules above produced.
EXPECTED_GROUPS = {
    'earL':       ['lEara', 'lEarb'],
    'earR':       ['rEara', 'rEarb'],
    # 2026-08-13 — the five HAIR chains each gained ONE appended joint
    # (recharged_assets/keira-hd-inject-joints.txt, injected at the point of production by
    # scripts/shell/build_hd_actor_artgroup.sh and build_enhanced_models.sh).
    # Measured cause: 95 % of every strand's skinned mass sat at s = 1.8..2.2 bone lengths while
    # the articulated part reached 1.0, so the whole distal half was carried RIGIDLY by the last
    # joint — the owner's "les pointes sont ancrées au même titre que les racines". It is also why
    # no gradient was representable: with rootlock=1 a 2-joint chain has exactly ONE free link.
    # After injection, s_p95 = 1.000 on all five and the 2-joint chains have TWO free links.
    # The EARS are deliberately NOT extended: same rule would apply (s_p95 2.259) but the owner has
    # reported no geometry break on them, and they are animation-driven (mode 1/3, not glue).
    # Measured and reported, not silently skipped.
    # 2026-08-13, 3e passe — SUBDIVISION du segment dominant de `backhair`/`lmidhair`/`rmidhair`
    # (defaut `hair-pudding`). Ces trois chaines partaient de DEUX joints dans le rig donneur, les
    # bangs de TROIS : apres la passe precedente elles etaient donc a 3 contre 4, soit UN SEUL
    # maillon libre (rootlock verrouille le premier os). Mesure sur le mesh livre, part de la masse
    # pesee de la meche portee par son SEUL segment libre :
    #     backhair 92.9 %   lmidhair 62.4 %   rmidhair 60.2 %
    # contre 35.0 % (lbang) et 36.6 % (rbang), que l'owner APPROUVE. Un segment libre unique qui
    # porte 60 a 93 % de la masse est un BLOC par construction : il n'y a rien derriere lui pour
    # etre en retard, donc aucune valeur d'amortissement ne peut y creer une propagation
    # racine->pointe. C'est le « pudding », et c'est structurel, pas un reglage.
    # L'os N'EST PAS AJOUTE EN BOUT : il n'y a aucune geometrie au-dela de la pointe (orphan
    # 3.8/4.8/4.5 %, tail_m = 0.0000 -- `backhair` est meme MIEUX couvert que `lbang` a 4.9 %), donc
    # un os appendu ne piloterait rien et serait un maillon inerte. Le segment dominant est SUBDIVISE
    # a sa mediane de masse : le joint de pointe recule, un nouveau joint prend sa place, et la
    # rampe lineaire du transfert partage la geometrie exactement 50/50 (mesure a l'execution :
    # backHair4 16.661 sur 33.321, Lmidhaird 29.477 sur 58.954, Rmidhaird 28.207 sur 56.413).
    # Le pire segment libre tombe ainsi a ~46 % (backhair) et ~31/30 % (les deux laterales, soit
    # SOUS le controle approuve). `mono` devient enfin jugeable : il exige DEUX retards libres.
    'backhair':   ['backHair1', 'backHair2', 'backHair3', 'backHair4'],
    'lbang':      ['Lbanga', 'Lbangb', 'Lbangc', 'Lbangd'],
    'rbang':      ['Rbanga', 'Rbangb', 'Rbangc', 'Rbangd'],
    'lmidhair':   ['Lmidhaira', 'Lmidhairb', 'Lmidhairc', 'Lmidhaird'],
    'rmidhair':   ['Rmidhaira', 'Rmidhairb', 'Rmidhairc', 'Rmidhaird'],
    # 2026-08-17, CYCLE 18 — LE JOINT DISTAL EST REMIS, ET LES DEUX MOTIFS DE SON RETRAIT SONT
    # TOMBES. Le cycle 16 l'avait retire sur deux motifs ; le cycle 17 les a repris hors moteur :
    #
    #   MOTIF 1  « SPEC 24 tombe de 2.32 a 1.20 Hz »  ->  ARTEFACT D'INSTRUMENT, a QUATRE
    #            endroits. Le parseur jetait le champ `l=` et versait DEUX echantillons par frame
    #            dans un ajustement qui en suppose UN : la frequence sort deux fois trop basse et
    #            bute sur la borne 1.200 de la grille. Le produit `f x n` conserve (n passait de
    #            137 a 286) est la signature d'une densite d'echantillonnage mal lue, pas d'un
    #            changement physique. Instruments repares, le cablage LIVRE a deux maillons rend
    #            4 canaux sur 6 INCHANGES et DANS leur bande. Et c'est vrai PAR CONSTRUCTION :
    #            pour le maillon racine `r = 0.5/nfr` donne `(1-r^2)/gmean = 1` exactement, quel
    #            que soit `nfr` (jak-hd-physics.gc:2613-2616, 2714-2717) — la frequence de la
    #            racine est invariante au nombre de maillons.
    #   MOTIF 2  « la capsule `lBooc->lBoob` rend meshpen positif »  ->  REEL MAIS MAL IMPUTE.
    #            La course « spheres » qui a suivi son retrait etait PIRE (0.0205 -> 0.0871 m).
    #            La cause est le volume PROXIMAL, re-ajuste parce que `influence()` selectionnait
    #            sur le poids ABSOLU d'UN joint : toute redistribution INTERNE a la chaine
    #            changeait ce que chaque joint « possede », `FIT_STEPS` descendait d'un cran et
    #            ramassait des sommets faiblement tenus contre la paroi du buste (rayon 322 ->
    #            412 u). Corrige au point de production par `chain_influence()` ci-dessus, dont
    #            le seuil porte sur le poids SOMME DE LA CHAINE — invariant par construction a
    #            toute redistribution interne, donc a l'ajout d'une articulation.
    #
    # Les deux correctifs vivent en amont de cette table ; celle-ci ne fait que rendre a l'organe
    # le degre de liberte que sa SPEC 23 exige. La regex de categorie plus haut couvre deja
    # `Boo[bc]`, et `rootlock` est deja exclu pour `cat == 'chest'` (SPEC 30 : l'ancre est dans
    # le TISSU, et epingler le maillon proximal figerait 75 % de la masse de l'organe).
    'chestL':     ['lBoob', 'lBooc'],
    'chestR':     ['rBoob', 'rBooc'],
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
    # 2026-08-13, 2e passe d'injection — `knee-tabs`, defaut ouvert de l'owner.
    # 100 % de la geometrie de la languette etait AU-DELA de son unique joint (s_p50 2.178,
    # s_p95 2.627 sur un os de 0.0802 m) : le joint est entierement en amont de ce qu'il pilote,
    # donc le faire tourner TRANSLATE la languette au lieu de la faire battre — « ca essaie de
    # bouger mais c'est chelou ». Le nouvel os fait 0.1305 m, soit 1.63x l'ancien, ce qui leve
    # aussi le plafond d'amplitude (2 x longueur d'os) que le fichier de reglages avait identifie
    # comme le vrai blocage.
    'kneeflapL':  ['lKneeFlap', 'lKneeFlap2'],
    'kneeflapR':  ['rKneeFlap', 'rKneeFlap2'],
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


def graft_shipped_weights(geo, log=None):
    """GREFFE LES POIDS DU MESH QUE LE JEU RECOIT SUR LA GEOMETRIE DU DONNEUR (espace du rig).

    LE DEFAUT QUE CETTE FONCTION FERME, et il a ete mesure au cycle 21 avant d'etre corrige ici.
    `c6.load_geometry(model)` resout le mesh depuis `<char>-k2e.json`, qui pointe l'INTERMEDIAIRE
    `out/jak1/fr3/skin/keira-hd-donor-injected.glb`. Or la chaine du bake est :

        injection -> keira-hd-donor-injected.glb     <- ce que ce generateur lisait
        stamp     -> keira-hd-stamped.glb
        prep      -> keira-hd-lod0.glb               (compacte, JETTE le joint `align`)
        RESKIN    -> applique recharged_assets/physics_reskin.txt
        copie     -> out/jak1/fr3/skin/keira-hd-lod0.glb   <- CE QUE LE JEU RECOIT

    Le reskin est DEUX ETAPES EN AVAL du fichier lu. Tous les `verts=`, `wsum=`, rayons et volumes
    de physics_chains.txt decrivaient donc une ponderation que le jeu ne recoit jamais. Mesure du
    cycle 21, meme sonde, deux fichiers :

        joint    lu par ce generateur    mesh LIVRE
        lBoob    wsum= 9.162             wsum=20.679    x2.3
        lBooc    wsum= 9.015             wsum=21.569    x2.4
        rBoob    wsum= 8.646             wsum=17.985    x2.1
        rBooc    wsum= 6.817             wsum=18.085    x2.7

    Et la preuve la plus dure est une PREDICTION FALSIFIEE : le cycle 21 predisait que le repesage
    ferait bouger les rayons ; `physics_chains.txt` est ressorti IDENTIQUE AU BIT PRES apres une
    passe qui double la possession du maillon distal. Un generateur qui ne peut pas voir le
    repesage ne peut pas dimensionner un volume autour de la chair qui bouge.
    C'est le meme piege que `ROOM-SKINCOV` le 2026-08-13 : « ce n'est pas une mesure perimee,
    c'est une mesure prise sur une AUTRE entree ».

    POURQUOI CE N'EST PAS UN SIMPLE ECHANGE DE CHEMIN, et c'est ce qui a fait reculer le cycle 21.
    `prep` jette `align`, qui est a l'INDEX 0 du rig : le mesh livre porte 106 joints la ou le rig
    en porte 107, et TOUS les indices sont decales de 1. Lire le mesh livre en croyant lire le rig
    ferait peser chaque sommet contre le MAUVAIS joint — un desastre silencieux, exactement la
    classe d'erreur qu'on corrige. La correspondance est donc etablie PAR NOM, jamais par un
    decalage arithmetique : le `+1` est ici une CONSEQUENCE mesuree et imprimee, jamais une
    hypothese de calcul.

    ET LA GREFFE NE PORTE QUE SUR LES POIDS. Tout le reste — noms, hierarchie, positions de bind,
    matrices inverse-bind, positions de sommets, triangles — reste celui du donneur, en espace de
    rig. Les six egalites ci-dessous le VERIFIENT au lieu de le supposer ; toute violation arrete
    la generation, parce qu'un greffon pose sur une geometrie qui a bouge serait invisible."""
    ship_path = os.path.join(REPO, SHIPPED_REL)
    if not os.path.exists(ship_path):
        # Pas de bake sur cette machine : on garde le donneur, et ON LE DIT. Un repli silencieux
        # serait precisement le defaut qu'on ferme (regle 3 : aucun de-scope silencieux).
        if log:
            log(f'skin ATTENTION: mesh livre absent ({SHIPPED_REL}) — poids lus sur le DONNEUR, '
                f'donc EN AMONT du reskin. Les rayons ne decrivent pas ce que le jeu recoit.')
        return geo, RESOLVED_GLB + '  [MESH LIVRE ABSENT — poids pre-reskin]'
    ship = c6.load_geometry(MODEL, glb=SHIPPED_REL)
    if ship is None:
        raise SystemExit(f'mesh livre illisible : {SHIPPED_REL}')

    dn, sn = list(geo['names']), list(ship['names'])
    if len(set(dn)) != len(dn) or len(set(sn)) != len(sn):
        raise SystemExit('GREFFE: un nom de joint est duplique — la correspondance par nom '
                         'ne serait pas une bijection')
    idx_of = {n: i for i, n in enumerate(dn)}
    missing = [n for n in sn if n not in idx_of]
    if missing:
        raise SystemExit('GREFFE: le mesh livre porte des joints absents du rig : '
                         + ', '.join(missing[:8]))
    lut = np.array([idx_of[n] for n in sn], dtype=np.int64)   # index LIVRE -> index RIG, PAR NOM
    if list(lut) != sorted(lut):
        raise SystemExit('GREFFE: `prep` a REORDONNE les joints, il ne fait pas que supprimer. '
                         'La greffe suppose une sous-suite ; verifier prep_hd_actor_glb.py.')

    # (1) les joints que `prep` jette ne doivent porter AUCUN poids chez le donneur, sans quoi la
    #     greffe perdrait de la chair au lieu de changer sa repartition.
    dropped = [n for n in dn if n not in set(sn)]
    Jd, Wd = geo['J'], geo['W']
    for n in dropped:
        j = idx_of[n]
        w = float(sum(Wd[Jd[:, c] == j, c].sum() for c in range(Jd.shape[1])))
        if w > 1e-6:
            raise SystemExit(f'GREFFE: le joint `{n}`, absent du mesh livre, porte {w:.6f} de '
                             f'poids chez le donneur — la greffe le perdrait en silence')

    # (2) la geometrie doit etre LA MEME, sinon on collerait des poids sur d'autres sommets.
    if geo['V'].shape != ship['V'].shape:
        raise SystemExit(f"GREFFE: {geo['V'].shape[0]} sommets chez le donneur contre "
                         f"{ship['V'].shape[0]} sur le mesh livre — `prep` a change la topologie")
    dv = float(np.abs(geo['V'] - ship['V']).max())
    if dv > 1e-3:
        raise SystemExit(f'GREFFE: les positions de bind des sommets different de {dv:.6f} u — '
                         f'la correspondance sommet a sommet ne tient pas')
    if geo['F'].shape != ship['F'].shape or not bool((geo['F'] == ship['F']).all()):
        raise SystemExit('GREFFE: les triangles different entre le donneur et le mesh livre')

    # (3) meme hierarchie et memes positions d'os pour les joints communs.
    dp = 0.0
    for i, n in enumerate(sn):
        j = int(lut[i])
        dp = max(dp, float(np.linalg.norm(geo['P'][j] - ship['P'][i])))
        pa_s = sn[ship['parent'][i]] if ship['parent'][i] >= 0 else None
        pa_d = dn[geo['parent'][j]] if geo['parent'][j] >= 0 else None
        if pa_s is not None and pa_s != pa_d:
            raise SystemExit(f'GREFFE: parent de `{n}` : `{pa_d}` au rig contre `{pa_s}` au '
                             f'mesh livre')
    if dp > 1e-3:
        raise SystemExit(f'GREFFE: une position de bind differe de {dp:.6f} u entre le rig et '
                         f'le mesh livre')

    # (4) les poids livres doivent etre normalises, comme ceux du donneur.
    rs = ship['W'].sum(1)
    if float(np.abs(rs - 1.0).max()) > 1e-3:
        raise SystemExit('GREFFE: les poids du mesh livre ne somment pas a 1 '
                         f'(ecart max {float(np.abs(rs - 1.0).max()):.6f})')

    offs = sorted({int(lut[i]) - i for i in range(len(sn))})
    geo['J'] = lut[ship['J']]
    geo['W'] = ship['W']
    if log:
        log(f'skin GREFFE: poids lus sur le MESH LIVRE {SHIPPED_REL} '
            f'({len(sn)} joints) et remis en espace de rig ({len(dn)} joints) PAR NOM ; '
            f'joints jettes par prep : {", ".join(dropped) or "aucun"} (poids nul, verifie) ; '
            f'decalage d\'index constate {offs} ; geometrie identique '
            f'(dV={dv:.6f} u, dP={dp:.6f} u, triangles egaux).')
    return geo, SHIPPED_REL


def load_mesh(model, log=None):
    """c6.load_geometry (names/parents/bind positions in game units, V/J/W restricted to the
    vertices THIS model's primitives index) + the per-joint inverse bind matrices.

    Depuis le cycle 22 les POIDS sont ceux du mesh que le jeu recoit : voir
    `graft_shipped_weights`, qui explique le defaut et verifie la greffe."""
    geo = c6.load_geometry(model)
    if geo is None:
        raise SystemExit(f"could not load geometry for {model}")
    js, bufs = read_glb(geo['path'])
    binc = consolidate_buffers(js, bufs)
    _n, ibms, _p = skin_info(js, binc)
    geo['ibms'] = ibms
    geo, skin_src = graft_shipped_weights(geo, log)
    geo['skin_src'] = skin_src
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


def chain_influence(geo, chain_idx, thr):
    """POSSESSION RELATIVE A LA CHAINE, PAS AU JOINT — et c'est la correction du 2026-08-17.

    `influence()` selectionne sur le poids ABSOLU d'UN joint. Tant qu'une chaine n'a qu'un joint
    les deux notions coincident. Des qu'elle en a deux, toute passe de reskin qui repartit le poids
    A L'INTERIEUR de la chaine change ce que CHAQUE joint « possede » — alors que la chair, elle,
    n'a pas bouge d'un sommet.

    CE QUE CA A COUTE, MESURE (course C16 du 2026-08-17, et la mesure est hors moteur et hors
    build : `probe_rest_containment.py` sur la POSE DE BIND, meme rig, sans capsule et sans le
    maillon distal — donc la seule variable est le re-ajustement du volume PROXIMAL) :

        recouvrement au repos            1 maillon      2 maillons      facteur
        lBoob vs Lshoulder->chest         -75.3 u        -202.3 u        x2.7
        rBoob vs Rshoulder->chest         -56.1 u        -206.0 u        x3.7
        rBoob vs neck->chest             +173.5 u          -4.7 u        CONTACT NEUF
        rBoob vs Lshoulder->chest        +198.5 u         -15.3 u        CONTACT NEUF
        couples (maillon, volume) en recouvrement au repos : 2 -> 4

    Le rayon passait de 322 a 412 u et le centre rentrait de 27 u vers le buste, parce que
    l'echelle FIT_STEPS, ne trouvant plus FIT_MIN_VERTS sommets au seuil serre, descendait d'un
    cran et ramassait des sommets FAIBLEMENT tenus contre la paroi du buste. La grandeur cessait
    alors de mesurer une POSSESSION pour mesurer un CONTACT — exactement le piege
    `ownership-not-coverage` du registre, sur l'organe le plus visible de la spec.

    Le cycle 16 a impute ces deux signatures a la capsule `lBooc->lBoob` et l'a retiree ; la course
    « spheres » qui a suivi etait PIRE (meshpen 0.0205 -> 0.0871 m, contacts chestL 23 -> 9525)
    parce que les deux variantes partageaient ce meme volume proximal defectueux. La capsule
    aggravait, elle n'etait pas la cause.

    LA REGLE, ET ELLE EST UN INVARIANT, PAS UN REGLAGE : le seuil se choisit sur le poids SOMME DE
    LA CHAINE — invariant par toute redistribution interne — et la chair ainsi retenue est ensuite
    PARTITIONNEE entre les maillons par argmax. Ajouter une articulation ne peut donc plus changer
    le volume de l'organe : l'union des volumes des maillons couvre exactement les memes sommets.

    -> (indices des sommets retenus, joint argmax par sommet)."""
    J, W = geo['J'], geo['W']
    nv = len(W)
    tot = np.zeros(nv, dtype=float)
    best = np.full(nv, -1, dtype=int)
    bestw = np.zeros(nv, dtype=float)
    for jj in chain_idx:
        wj = np.zeros(nv, dtype=float)
        for c in range(J.shape[1]):
            m = (J[:, c] == jj)
            wj[m] += W[m, c]
        tot += wj
        take = wj > bestw
        bestw[take] = wj[take]
        best[take] = jj
    return np.flatnonzero(tot > thr), best


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


def blob_centre_radius(geo, j, chain_idx=None):
    """CENTRE et RAYON de la geometrie qu'un joint porte, dans SON espace bind, en unites de jeu.

    `chain_idx` (2026-08-17) : les indices des joints de la CHAINE SIMULEE a laquelle `j`
    appartient. Passe uniquement quand cette chaine porte AU MOINS DEUX joints ; la selection des
    sommets se fait alors sur le poids SOMME de la chaine puis par partition argmax
    (`chain_influence`, dont l'en-tete porte la mesure qui l'exige). A UN SEUL joint — l'etat
    LIVRE — l'argument vaut None et pas une ligne de ce qui suit ne change : c'est verifie par
    regeneration, le fichier produit est identique au bit pres hors ligne de date.

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
    if chain_idx is not None and len(chain_idx) > 1:
        # Le seuil est choisi sur le poids SOMME DE LA CHAINE (invariant par redistribution
        # interne), la chair retenue est ensuite partitionnee entre les maillons par argmax.
        for cand in FIT_STEPS:
            sel, best = chain_influence(geo, chain_idx, cand)
            thr = f'{cand}(somme chaine)'
            idx = sel[best[sel] == j]
            if len(sel) >= FIT_MIN_VERTS:
                break
    else:
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


def carried_descendants(names, parent, groups):
    """Par joint de chaine, les joints que le rig lui fait porter RIGIDEMENT.

    Un joint descendant qui n'appartient a AUCUNE chaine n'est jamais simule : le moteur le
    deplace par propagation de delta depuis son porteur. Sa geometrie suit donc le lien au bit
    pres — mais elle n'est confrontee a RIEN, parce que le volume du lien (`*phys-lcr*`) est
    ajuste sur les seuls sommets du joint lui-meme.

    MESURE DU 2026-08-12 QUI CREE CETTE REGLE (defaut owner `goggles-bottom`, « le BAS des
    lunettes clipe dans les seins ») : la chaine `goggles` s'arrete a la fourche `gogglesMid`,
    et les deux verres — `gogglesLeft` 244 sommets, `gogglesRight` 244, soit 94 % des lunettes,
    portes jusqu'a 603 u de leur joint — sont hors chaine. Le volume teste est une sphere de
    rayon 150 sur `gogglesMid` : en pose bind elle laisse 250 u de course libre avant le moindre
    contact, pendant que 28 sommets de verre sont deja 129 u DANS la sphere `lBoob`.

    La regle est donc : LE VOLUME D'UN LIEN COUVRE CE QU'IL PORTE, pas seulement ce qu'il possede.
    Elle est derivee du rig et ne nomme rien a la main (DIRECTIVES 4) ; sur le rig de Keira elle
    ne designe qu'un seul lien, et le generateur ECRIT lequel."""
    idx_of = {n: i for i, n in enumerate(names)}
    in_chain = set()
    for js in groups.values():
        in_chain.update(js)
    kids = {}
    for i, p in enumerate(parent):
        if p >= 0:
            kids.setdefault(p, []).append(i)
    out = {}
    for cname, js in groups.items():
        for jn in js:
            acc, stack = [], list(kids.get(idx_of[jn], []))
            while stack:
                k = stack.pop()
                if names[k] in in_chain:      # une chaine a elle : elle porte son propre volume
                    continue
                acc.append(k)
                stack.extend(kids.get(k, []))
            if acc:
                out[jn] = (cname, acc)
    return out


def carried_centre_radius(geo, j, carried):
    """CENTRE et RAYON de couverture sur l'union {geometrie du joint} u {geometrie qu'il porte},
    dans l'espace bind du joint. Meme statistique que `blob_centre_radius` (COVER_PCT), meme
    echelle d'unites : seul l'echantillon de sommets change.

    Rend (centre, rayon, n_total, n_portes, fraction_dehors)."""
    def pick(jj):
        for cand in FIT_STEPS:
            _n, _w, i2 = influence(geo, jj, cand)
            if len(i2) >= FIT_MIN_VERTS:
                return i2
        return i2
    own = list(pick(j))
    carr = []
    for k in carried:
        carr.extend(pick(k))
    ids = np.array(sorted(set(own) | set(carr)), dtype=int)
    if ids.size == 0:
        return None, None, 0, 0, None
    pts = to_bone_local(geo['ibms'][j], geo['V'][ids])
    c = pts.mean(axis=0)
    d = np.linalg.norm(pts - c, axis=1)
    r = float(np.percentile(d, COVER_PCT))
    return c, r, int(ids.size), len(set(carr)), float((d > r).mean())


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
# coques (`shell=`) — cf. le bloc SHELL_* en tete de fichier pour la regle et ses mesures
# ================================================================================================
def shell_select(geo, j):
    """LA MEME SELECTION DE SOMMETS QUE `fit_radius`, et ce couplage est la regle, pas un detail.

    La classification coque/non-coque n'est pas invariante au seuil de poids : evaluee a w>0.05
    partout, elle declare fourreaux `Lmidhaira`, `Rmidhaira`, `lBoob` et `rBoob`. Elle doit donc
    lire exactement les sommets sur lesquels le rayon du meme lien est ajuste — l'echelle
    FIT_STEPS, premier seuil qui atteint FIT_MIN_VERTS. -> (indices, seuil)."""
    idx = np.array([], dtype=int)
    for thr in FIT_STEPS:
        n, _w, i2 = influence(geo, j, thr)
        if n >= FIT_MIN_VERTS:
            return i2, thr
        idx = i2
    for thr in reversed(FIT_STEPS):
        n, _w, i2 = influence(geo, j, thr)
        if n > 0:
            return i2, thr
    return idx, None


def shell_axis_frame(u):
    """Deux vecteurs unitaires perpendiculaires a `u`, construits de facon deterministe."""
    t = np.array([1.0, 0.0, 0.0])
    if abs(float(u @ t)) > 0.9:
        t = np.array([0.0, 1.0, 0.0])
    e1 = t - float(t @ u) * u
    e1 = e1 / np.linalg.norm(e1)
    return e1, np.cross(u, e1)


def shell_around(pts, a_world, b_world):
    """Distance perpendiculaire, angle (degres, 0..360) et ABSCISSE `t` de chaque sommet autour de
    l'axe a->b, en espace bind MONDE — le repere ou vivent les volumes emis.

    `t` est la projection sur le segment, NON bornee : t<0 ou t>1 designe un sommet situe AU-DELA
    d'un des deux bouts du volume. Il est rendu parce que l'enroulement doit se juger le long du
    SEGMENT, pas de la droite qui le porte — voir `classify_shells`.
    -> (d, angles, t, u)."""
    u = b_world - a_world
    L = float(np.linalg.norm(u))
    if L < 1e-6:
        raise SystemExit('shell: zero-length volume axis')
    u = u / L
    rel = pts - a_world
    t = (rel @ u) / L
    perp = rel - np.outer(rel @ u, u)
    e1, e2 = shell_axis_frame(u)
    ang = np.degrees(np.arctan2(perp @ e2, perp @ e1)) % 360.0
    return np.linalg.norm(perp, axis=1), ang, t, u


def shell_sectors(ang):
    """(secteurs occupes sur SHELL_NSEC, plus grand trou angulaire en degres).

    Le trou est mesure d'un secteur occupe au suivant en tournant : c'est (plus long run de
    secteurs vides + 1) * SHELL_SECW. Un seul secteur occupe -> 360 degres."""
    sec = (ang // SHELL_SECW).astype(int) % SHELL_NSEC
    cnt = np.zeros(SHELL_NSEC, dtype=int)
    for s in sec:
        cnt[s] += 1
    occ = np.flatnonzero(cnt > 0)
    if len(occ) == 0:
        return 0, 360.0
    gaps = []
    for i in range(len(occ)):
        step = int((occ[(i + 1) % len(occ)] - occ[i]) % SHELL_NSEC)
        gaps.append((SHELL_NSEC if step == 0 else step) * SHELL_SECW)
    return int(len(occ)), float(max(gaps))


def shell_rr_at(pt, a_world, b_world, ra, rb):
    """Rayon du volume a->b a la hauteur de `pt`, INTERPOLE COMME LE MOTEUR LE FAIT
    (jak-hd-physics.gc, `phys-collide-depth`) : t0 = projection sur le segment bornee a [0,1],
    puis rr = radius + (radius2 - radius) * t0. -> (rr, t0)."""
    ab = b_world - a_world
    dd = float(ab @ ab)
    t0 = 0.0 if dd < 1e-6 else float(((pt - a_world) @ ab) / dd)
    t0 = min(1.0, max(0.0, t0))
    return float(ra + (rb - ra) * t0), t0


def classify_shells(geo, groups, idx_of, volumes, log):
    """Classe COQUE / non-coque les liens de toutes les chaines et publie la table complete.

    `volumes` : les capsules EMISES, sous la forme (nom_A, nom_B, rayon_en_A, rayon_en_B). Un
    volume est ETRANGER a une chaine quand ni A ni B n'est un de ses joints — l'exclusion
    structurelle de `phys-col-own?`.

    LE NOMBRE LIVRE est le rayon INTERNE du fourreau : r_int = |c - axe| + rr(c), ou `c` est le
    centroide des sommets du lien, |c - axe| sa distance perpendiculaire a l'axe du volume, et
    rr(c) le rayon du volume a cette hauteur. C'est le seul choix qui rende la POSE DU MODELE
    admissible : mesure sur les deux pans, `min`, `p05` et `p10` de la distribution des distances
    passent SOUS le rayon du mollet (-75, -54, -42 u) et `p25` ne laisse que 9 u de jeu, alors que
    le pan est deja decale de 95 u en pose bind.

    Quand plusieurs volumes etrangers qualifient, le PLUS CONTRAIGNANT gagne (r_int le plus petit),
    et lequel est ecrit dans le fichier a cote de la chaine.

    Rend {nom_de_chaine: dict(joint, vol, sect, gap, off, rr, r_int, nv, thr)}."""
    P, V = geo['P'], geo['V']
    log('')
    log(f'COQUES — classification des {sum(len(j) for j in groups.values())} liens de chaine '
        f'(regle mesuree : secteurs >= {SHELL_SECT_MIN}/{SHELL_NSEC} ET gap <= '
        f'{SHELL_GAP_MAX:.0f} deg autour d\'un volume ETRANGER)')
    log(f"  {'chaine/joint':<26}{'nv':>4} {'seuil':>6}  {'meilleur volume ETRANGER':<24}"
        f"{'sect':>6}{'gap':>6}{'in-seg':>7}{'(droite)':>10}{'|c-axe|':>9}{'rr(c)':>7}"
        f"{'r_int':>7}  verdict")
    out = {}
    for cname in groups:
        for jn in groups[cname]:
            j = idx_of[jn]
            idx, thr = shell_select(geo, j)
            if len(idx) == 0:
                log(f'  {cname + "/" + jn:<26}{0:>4} {"-":>6}  '
                    f'-- NON MESURE : 0 sommet skinne, aucune geometrie a entourer')
                continue
            pts = V[idx]
            c = pts.mean(axis=0)
            rows = []
            for (an, bn, ra, rb) in volumes:
                if an in groups[cname] or bn in groups[cname]:
                    continue                      # volume PROPRE a la chaine : jamais un fourreau
                a_w, b_w = P[idx_of[an]], P[idx_of[bn]]
                d, ang, t, u = shell_around(pts, a_w, b_w)
                # UN FOURREAU EST LE LONG DE L'OS QU'IL GAINE, PAS QUELQUE PART SUR LA DROITE QUI
                # LE PORTE. Seuls les sommets dont l'abscisse tombe DANS le segment comptent dans
                # la couverture angulaire. Correction du cycle 22, et ce n'est pas un reglage :
                # `shell_rr_at` borne deja `t0` a [0,1] « COMME LE MOTEUR LE FAIT »
                # (`phys-collide-depth`), donc le test angulaire etait le seul endroit du fichier
                # qui traitait un volume BORNE comme une droite INFINIE.
                #
                # CE QUE LE DEFAUT COUTAIT, mesure sur le mesh LIVRE (fraction des sommets du lien
                # dont l'abscisse tombe dans le segment du mollet) :
                #     LpantFlap -> Lankle->Lknee   t 0.49..0.65   100 %   <- vrai fourreau
                #     RpantFlap -> Rankle->Rknee   t 0.49..0.65   100 %   <- vrai fourreau
                #     Lmidhaira -> Lankle->Lknee   t 3.60..3.92     0 %   <- cheveux, 3.8 tibias
                #     Rmidhaira -> Rankle->Rknee   t 3.60..3.92     0 %      au-dessus du genou
                #     lBoob     -> Lankle->Lknee   t 2.65..2.82     0 %   <- la POITRINE, a 10/12
                #     rBoob     -> Rankle->Rknee   t 2.66..2.84     0 %      secteurs de l'axe
                # La droite du tibia prolongee vers le haut passe pres du torse et de la tete :
                # tout ce qui est un tube autour de la verticale « enroulait » le mollet. Le defaut
                # etait la depuis toujours et restait INVISIBLE tant que le generateur lisait le
                # donneur : ce sont les poids concentres du mesh livre qui l'ont fait sortir.
                # Aucun seuil neuf n'est introduit : les criteres secteurs/gap font le reste, un
                # lien qui ne garde que quelques sommets ne peut pas atteindre 10/12 sous 60 deg.
                ins = (t >= 0.0) & (t <= 1.0)
                nsec, gap = shell_sectors(ang[ins]) if bool(ins.any()) else (0, 360.0)
                nsec_line, gap_line = shell_sectors(ang)      # l'ancienne lecture, publiee
                rel = c - a_w
                off = float(np.linalg.norm(rel - float(rel @ u) * u))
                rr, _t0 = shell_rr_at(c, a_w, b_w, ra, rb)
                rows.append(dict(vol=f'{an}->{bn}', sect=nsec, gap=gap, off=off, rr=rr,
                                 r_int=off + rr, frac_in=float(ins.mean()),
                                 sect_line=nsec_line, gap_line=gap_line))
            if not rows:
                log(f'  {cname + "/" + jn:<26}{len(idx):>4} {thr:>6}  '
                    f'-- NON MESURE : aucun volume etranger a cette chaine')
                continue
            qual = [r for r in rows if r['sect'] >= SHELL_SECT_MIN and r['gap'] <= SHELL_GAP_MAX]
            best = min(qual, key=lambda r: r['r_int']) if qual else \
                sorted(rows, key=lambda r: (-r['sect'], r['gap']))[0]
            r_int = int(round(best['r_int']))
            log(f'  {cname + "/" + jn:<26}{len(idx):>4} {thr:>6}  {best["vol"]:<24}'
                f'{best["sect"]:>4}/{SHELL_NSEC}{best["gap"]:>6.0f}'
                f'{best["frac_in"] * 100:>6.0f}%'
                f'{str(best["sect_line"]) + "/" + str(SHELL_NSEC):>7}'
                f'{best["gap_line"]:>3.0f}'
                f'{best["off"]:>9.0f}'
                f'{best["rr"]:>7.0f}{r_int:>7}  {"COQUE" if qual else "."}')
            if not qual:
                continue
            rec = dict(joint=jn, vol=best['vol'], sect=best['sect'], gap=best['gap'],
                       off=best['off'], rr=best['rr'], r_int=r_int, nv=len(idx), thr=thr,
                       nqual=len(qual))
            # Le moteur ne porte qu'UN scalaire par chaine : si plusieurs liens d'une meme chaine
            # etaient des fourreaux, c'est le plus contraignant qui vaut pour elle, et le lien
            # retenu est ecrit dans le fichier.
            if cname not in out or r_int < out[cname]['r_int']:
                out[cname] = rec
    log(f'  COQUES retenues : ' + (', '.join(f'{k} ({v["joint"]} autour de {v["vol"]}, '
                                             f'shell={v["r_int"]})' for k, v in out.items())
                                   or '(aucune)'))
    return out


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
    geo = load_mesh(MODEL, log)
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
    geo = load_mesh(MODEL, log)
    if list(geo['names']) != names:
        raise SystemExit('GLB skin joint list does not match the rig json joint list')
    rel_src = geo['src'].replace('\\', '/')
    # THE RIG IS THE SINGLE SOURCE OF TRUTH FOR WHICH MESH TO READ.
    # This used to be `rel_src != GLB_REL -> die`, which made the constant below authoritative over
    # the rig. Since 2026-08-13 the donor is augmented with physics joints before the art-group and
    # the bake read it, so <char>-k2e.json legitimately records a DERIVED donor and the hard
    # equality killed every regeneration ("rig points at ... expected ...").
    # Nothing is loosened: the check that actually protects correctness is the joint-list identity
    # immediately above (mesh skin joints == rig joint list), and it is untouched. What this one
    # protected was "don't silently read a different mesh than documented" — so it now RESOLVES
    # from the rig, says so out loud, and the emitted header records the path really read (it used
    # to print GLB_REL unconditionally, i.e. it would have lied about its own input).
    global RESOLVED_GLB, RESOLVED_SKIN
    RESOLVED_GLB = rel_src
    # La peau vient d'un AUTRE fichier que la hierarchie depuis le cycle 22, et l'en-tete doit le
    # dire : c'est le fichier livre qui decide des rayons et des volumes.
    RESOLVED_SKIN = geo['skin_src']
    idx_of = {n: i for i, n in enumerate(names)}
    log(f"rig  {RIG_REL}: {len(names)} joints")
    if rel_src != GLB_REL:
        log(f"mesh OVERRIDE by the rig: {rel_src}  (base donor {GLB_REL})")
    log(f"mesh {rel_src}: {len(geo['V'])} vertices skinned to this model's primitives")

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
    chain_entries = []
    chain_report = []
    # candidats au recentrage du volume de lien (voir le bloc RECENTRAGE plus bas) : collectes ici
    # parce que c'est le seul endroit ou le rayon LIVRE de chaque lien est connu.
    recentre_cand = []
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
        # OU EST REELLEMENT LA GEOMETRIE DE CHAQUE LIEN, par rapport a son joint. Mesure ici et
        # jugee plus bas (bloc RECENTRAGE) ; les cheveux en sont exclus, leur essai est fait.
        if cat not in HAIR_CATS:
            for i, jn in enumerate(joints):
                c, _rcov, nv, _thr, _cov = blob_centre_radius(geo, idx_of[jn])
                if c is None or nv == 0:
                    continue
                cen = tuple(int(round(float(v))) for v in c)
                off = math.sqrt(sum(float(v) * float(v) for v in cen))
                recentre_cand.append((jn, cname, radii[i], cen, off, nv))
        parts = [f'chain {cname}',
                 f'class={t["klass"]}',
                 f'stiffness={fnum(t["stiffness"])}',
                 f'damping={fnum(t["damping"])}',
                 f'gravity={fnum(t["gravity"])}',
                 f'radius={rep}']
        # `rootlock=1` EXPRIME LA SPEC 2 DES CHEVEUX, ET ELLE NE S'APPLIQUE PAS A UN ORGANE MOU.
        # Pour une meche, le joint racine CHEVAUCHE le crane : le verrouiller est l'ancrage que
        # l'owner a valide. Pour la poitrine, l'ancrage n'est PAS un joint epingle, il est dans le
        # TISSU — sa SPEC 30 le met dans un degrade de poids avec le thorax (« Deep root 90-100 %,
        # Rear/intermediate 55-85 %, Mid-volume 25-55 %, Distal 5-30 % ») et interdit ensuite en
        # toutes lettres « There shall be no hard attachment boundary ». Epingler le joint racine
        # EST une frontiere d'attache dure.
        # MESURE QUI TRANCHE (2026-08-17, mesh livre) : apres l'injection du joint distal, 75 % de
        # la masse pesee de la chaine reste sur le maillon RACINE. Le verrouiller rendrait donc les
        # trois quarts de la chair RIGIDES, alors qu'aujourd'hui la totalite suit un maillon libre —
        # une regression franche sur l'acquis que l'owner a valide (« poitrine sur mouvements
        # subtils : toujours OK », 2026-08-12), et precisement sa plainte « on dirait qu'ils ont ete
        # un peu mutes ». L'ancre rigide de la chaine reste `chest`, qui est HORS chaine (`anc=3`).
        if len(joints) >= 2 and cat != 'chest':
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
        radii_part = 'radii=' + ','.join(str(r) for r in radii)
        suffix = ''
        if fitnotes:
            suffix += '   # radii notes (fitted below w>0.5, or inherited): ' + ' '.join(fitnotes)
        if bendnote:
            suffix += bendnote
        meas = ' | '.join(f'{jn} verts={infl[jn][0]} wsum={infl[jn][1]:.2f} r={radii[i]}'
                          for i, jn in enumerate(joints))
        # LES LIGNES DE CHAINE SONT ASSEMBLEES PLUS BAS, PAS ICI. `shell=` se mesure contre les
        # VOLUMES emis, qui dependent eux-memes des rayons de lien ci-dessus (ONE-JOINT-ONE-
        # THICKNESS) : l'ordre de calcul est donc chaines -> volumes -> coques -> ecriture des
        # chaines. Rien d'autre ne change de place.
        chain_entries.append(dict(cname=cname, comment=f'# {cname} [{t["family"]}] {meas}',
                                  parts=parts, radii_part=radii_part, suffix=suffix,
                                  joints=joints))
        chain_report.append((cname, cat, t['family'], t['klass'], len(joints), rep, radii))

    # ---- colliders -----------------------------------------------------------------------------
    parts_map = {'body': list(BODY_PART)}
    cat_of_part = {}                      # la CATEGORIE derriere chaque partie, pour le choix du
    for cat, cname in order:              # volume ci-dessous : jamais une liste ecrite a la main.
        if cat in OBSTACLE_CHAIN_CATS:
            parts_map[cname] = list(groups[cname])
            cat_of_part[cname] = cat
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
            # UNE POITRINE EST UN BLOB, PAS UN SEGMENT DE MEMBRE — PAS DE CAPSULE (2026-08-17).
            # La capsule est une sphere BALAYEE le long d'un os : c'est la bonne abstraction pour un
            # bras ou une meche, pas pour un organe. Des que l'injection du joint distal a donne au
            # sein un second maillon, ce bloc a emis `capsule lBooc lBoob radius=585 radius2=680` —
            # un saucisson de 143 a 166 mm de rayon autour d'un os de 87 mm.
            # ET LA MESURE DIT CE QUE CA COUTE (course C16n2, contre le controle a 1 maillon) :
            #   ROOM-CONTACT-VOL chestL  23 -> 8411 contacts (x366), chestR 38 -> 2822 (x74),
            #   premier contributeur de chaque chaine = la capsule du sein OPPOSE ;
            #   profondeur a la pose modele chestL vs Lshoulder->chest  dm 393 -> 1123,
            #   neck->chest passe de « jamais atteint » a CONTACT ;
            #   meshpen passe de NEGATIF (dehors) a +0.0205 m sur 132 lignes `row` sur 310 — soit
            #   la regle 6 de l'owner, « rien ne traverse le mesh, quelle qu'en soit la raison ».
            # LA CAUSE EST STRUCTURELLE, PAS UN RAYON A REGLER : les spheres passent par la BORNE
            # PERPENDICULAIRE qui les plafonne a l'epaisseur mesuree du mesh, les capsules NON.
            # Emettre des spheres rend donc au sein le volume borne qu'il avait a un maillon, avec
            # une sphere PAR maillon au lieu d'une seule — ce qui est aussi ce dont sa SPEC 33
            # (« medial surfaces shall collide before visible interpenetration ») a besoin.
            if pj >= 0 and names[pj] in mset and cat_of_part.get(pname) != 'chest':
                capsules.append((jn, names[pj], pname))
                capped.add(jn)
    for pname, members in parts_map.items():
        for jn in members:
            if jn not in capped:
                spheres.append((jn, pname))

    # LE VOLUME D'UN LIEN COUVRE CE QU'IL PORTE (cf. `carried_descendants`). Le moteur prend
    # DEJA le rayon ET le centre d'une sphere posee sur le joint d'un lien comme volume de ce
    # lien (jak-hd-physics.gc:667-680) : il n'y a donc rien a changer dans le moteur, la sphere
    # emise ici est lue des deux cotes — volume du lien, et obstacle pour les autres chaines
    # (SPEC 3 : « les lunettes... ce sont des volumes, pas seulement des chaines »).
    # `phys-col-own?` (jak-hd-physics.gc:1271) exclut deja un volume porte par un joint de la
    # chaine elle-meme, donc aucune auto-collision n'est creee.
    # POSE, MESURE, ET RETIRE LE 2026-08-12 — LE CHIFFRE QUI LE RETIRE.
    #
    # Course de salle complete, cette sphere pour SEULE variable (3410 mesures, 31/31 animations) :
    #     goggles   mouvement de pointe 0.5107 -> 0.2281   = -55 %   (plancher FLOOR casse a -40 %)
    #     ROOM-STRETCH max            0.0272 -> 0.3937   = 39 % d'allongement d'os sur `rbang`,
    #                                 treize fois le plafond de 3 %
    #     botstrapR   -17.7 %   chestR   -7.8 %
    #     (au credit : ROOM-SIDE 11446 -> 8222, -28 %)
    # DIRECTIVES, regle de conservation : « si le plancher casse, le point est retire — pas
    # adouci, retire ». Il est retire, et l'owner l'avait annonce : « gonfler un volume finirait
    # par decoller les lunettes du corps ».
    #
    # POURQUOI, ET CE N'EST PAS UN RAYON A REGLER. Les deux verres sont deux paquets separes a
    # x = +/-461 dans l'espace bind de `gogglesMid`. Toute SPHERE qui les couvre tous les deux est
    # centree ENTRE eux, c'est-a-dire sur le visage : mesure en pose bind, r=809 s'enfonce de
    # 206 u dans la capsule `head->neck` et de 397 u dans `neck->chest`. Le volume est donc fait
    # d'air a l'endroit ou se trouve la tete, et il s'appuie en permanence dessus. Une sphere par
    # verre (r=478) ne pousserait rien : `gogglesLeft`/`gogglesRight` ne sont pas des maillons,
    # un volume pose la n'est un obstacle que pour les AUTRES chaines.
    #
    # C'EST LA DEUXIEME MESURE INDEPENDANTE QUI TOMBE AU MEME ENDROIT — la premiere est la
    # bretelle contre le torse, plus haut dans ce fichier (« un TORSE N'EST PAS UN CYLINDRE :
    # aucune valeur intermediaire ne satisfait les deux »). Le jeu de primitives sphere+capsule
    # est epuise pour ces deux defauts, et c'est exactement la suggestion de l'owner (« pourquoi
    # deriver du rig et pas du mesh ? ») qui devient la seule voie mesuree qui reste.
    #
    # La regle et sa mesure restent ecrites (`carried_descendants` ci-dessus) parce que le FAIT
    # qu'elle etablit ne change pas : sur le rig de Keira, UN SEUL lien porte de la geometrie hors
    # chaine — `gogglesMid`, 488 sommets sur 499, soit 94 % des lunettes, confrontees a RIEN.
    carried_spheres = []

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

    # LA MEME REGLE, ETENDUE AUX JOINTS DE CORPS (2026-08-13).
    #
    # `link_radius` ne contient que des joints de CHAINE : un joint de corps n'a jamais beneficie de
    # « un joint, une epaisseur », et son bout de capsule reste mesure perpendiculairement a l'axe
    # joint -> son PARENT. Quand aucun sommet ne se projette dans ce segment (`SPAN-EMPTY`), le
    # generateur ECRIT LUI-MEME que la distance perpendiculaire y mesure une autre partie du corps —
    # puis livre le nombre quand meme. Mesure sur le fichier livre le 2026-08-13 :
    #     Lthigh->hips  rayon 1321 u pour |Lthigh->hips| = 631.5 u, soit rayon/os = 2.09
    #     le volume deborde de 0.17 m au-dela du joint, et attrape la POITRINE et les BRETELLES
    #     (ROOM-CONTACT-VOL : chestR/Rthigh->hips 26 contre chestL 3 ; botstrapR 90 contre 18)
    # Toutes les autres capsules de membre sont a rayon/os <= 0.40.
    #
    # Un bout SPAN-EMPTY est donc remplace par l'EPAISSEUR PROPRE du joint, mesuree par la MEME
    # fonction et la meme echelle de seuils que partout ailleurs, perpendiculairement a l'os
    # joint -> son enfant. L'enfant se lit dans la hierarchie du rig, jamais dans une liste ecrite a
    # la main ; zero enfant, plusieurs enfants (quel os est le sien ?) ou un ajustement vide laissent
    # le rayon INCHANGE, avec la raison journalisee.
    kids_of = {}
    for _k, _pk in enumerate(parent):
        if _pk >= 0:
            kids_of.setdefault(_pk, []).append(_k)

    def own_bone_radius(name):
        """(rayon, raison) — epaisseur du joint perpendiculairement a SON PROPRE os, ou (None, raison)
        quand cet os n'est pas defini de facon univoque par le rig."""
        ji = idx_of[name]
        kids = kids_of.get(ji, [])
        if not kids:
            return None, 'aucun enfant dans le rig: ce joint n a pas d os propre'
        if len(kids) > 1:
            return None, ('%d enfants dans le rig (%s): os propre ambigu'
                          % (len(kids), ', '.join(names[k] for k in kids)))
        rr, _tt, nn = fit_radius(geo, ji, geo['P'][ji], geo['P'][kids[0]])
        if rr is None or nn == 0:
            return None, f'fit_radius ne rend rien sur {name}->{names[kids[0]]}'
        return rr, f'{name}->{names[kids[0]]}, {nn}v'

    col_block, col_report = [], []
    emitted_capsules = []
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
        # LA COUVERTURE EST MESUREE, PAS SUPPOSEE (2026-08-12).
        #
        # `s1 = s2 = 0` etait ECRIT EN DUR ici, et l'annotation qui en decoule — « SPAN-EMPTY :
        # aucun sommet ne se projette dans le segment » — etait donc imprimee sur les VINGT-QUATRE
        # capsules sans qu'aucune mesure ne l'ait jamais soutenue. C'est faux, et mesurable en une
        # ligne : 73 a 802 sommets se projettent dans chaque segment.
        #     Lthigh->hips     204 sommets dans le segment, p95 = 940   (livre 1321)
        #     Lshoulder->chest 802                          p95 = 1290  (livre  612)
        #     Lankle->Lknee    260                          p95 =  568  (livre  411)
        #     head->neck       214                          p95 = 1005  (livre  915)
        # Le fichier livre affirmait donc quelque chose que le generateur n'avait pas mesure, dans
        # l'artefact meme qui sert a juger les volumes — regle 0, appliquee a ma propre sortie.
        # J'ai perdu une partie de ce cycle a raisonner sur cette phrase avant de lire le code qui
        # l'ecrit ; c'est exactement le cout qu'elle fera payer au prochain qui la lira.
        #
        # LES RAYONS NE CHANGENT PAS D'UN BIT : `fit_radius` reste la source (le choix est
        # documente et A/B-teste juste au-dessus). Seule l'annotation devient vraie, et elle publie
        # desormais l'ECART entre le rayon livre et la couverture p95 du segment — c'est ce chiffre
        # qui dit si un volume est trop gros ou trop petit, et il n'existait nulle part.
        cov1 = cover_perp_radius(geo, j, a, b, t1)
        cov2 = cover_perp_radius(geo, p, b, a, t2)
        s1, s2 = cov1[2], cov2[2]
        w1, w2 = cov1[0], cov2[0]
        if r1 is None or n1 == 0 or r2 is None or n2 == 0:
            log(f"DROPPED collider capsule {jn}->{pn}: fitted from 0 vertices "
                f"({jn}={n1}v {pn}={n2}v)")
            continue
        cov = []
        for who, nspan, pcov, rlivre in ((jn, s1, w1, r1), (pn, s2, w2, r2)):
            if nspan == 0:
                cov.append(f'{who} SPAN-EMPTY (aucun sommet ne se projette dans le segment: '
                           f'la distance perpendiculaire y mesure une autre partie, rayon '
                           f'inter-quartile conserve)')
            elif pcov is None:
                cov.append(f'{who} couverture non mesurable')
            else:
                ratio = rlivre / pcov if pcov > 1e-6 else 0.0
                cov.append(f'{who} {nspan}v dans le segment, couverture p{COVER_PCT:.0f}='
                           f'{pcov:.0f} contre {rlivre} livre (x{ratio:.2f})')
        fix = []
        # bout SPAN-EMPTY : le rayon inter-quartile ne mesure pas ce joint, il mesure ce qui passe a
        # cote. On lui substitue son epaisseur propre (os joint -> son enfant), ou rien du tout.
        if s1 == 0:
            nr1, why1 = own_bone_radius(jn)
            if nr1 is None:
                log(f'ONE-JOINT-ONE-THICKNESS capsule {jn}->{pn}: {jn} SPAN-EMPTY, rayon {r1} '
                    f'INCHANGE — {why1}')
            elif nr1 != r1:
                fix.append(f'{jn} {r1}->{nr1} (span-empty -> own-bone thickness {why1})')
                r1 = nr1
            else:
                log(f'ONE-JOINT-ONE-THICKNESS capsule {jn}->{pn}: {jn} SPAN-EMPTY, rayon {r1} deja '
                    f'egal a son epaisseur propre ({why1})')
        if s2 == 0:
            nr2, why2 = own_bone_radius(pn)
            if nr2 is None:
                log(f'ONE-JOINT-ONE-THICKNESS capsule {jn}->{pn}: {pn} SPAN-EMPTY, rayon {r2} '
                    f'INCHANGE — {why2}')
            elif nr2 != r2:
                fix.append(f'{pn} {r2}->{nr2} (span-empty -> own-bone thickness {why2})')
                r2 = nr2
            else:
                log(f'ONE-JOINT-ONE-THICKNESS capsule {jn}->{pn}: {pn} SPAN-EMPTY, rayon {r2} deja '
                    f'egal a son epaisseur propre ({why2})')
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
        # Les rayons EMIS (apres ONE-JOINT-ONE-THICKNESS), dans l'ordre `capsule A B radius=
        # radius2=` : c'est cet axe et ces rayons que la regle des coques interroge, exactement
        # comme le moteur les lira.
        emitted_capsules.append((jn, pn, float(r1), float(r2)))
    # ---------------------------------------------------------------------------------------------
    # UNE SPHERE AJUSTEE SUR UNE GEOMETRIE ALLONGEE MESURE SA LONGUEUR, PAS SON EPAISSEUR.
    #
    # `blob_centre_radius` rend le p95 de la distance AU CENTROIDE. Sur une part compacte (un sein,
    # le moyeu du buste) c'est bien une epaisseur. Sur une MECHE — un tube long et fin — le p95 rend
    # la moitie de sa LONGUEUR, et le volume emis n'a plus rien a voir avec ce que le joint occupe :
    #
    #     Rmidhaira   sphere p95 = 766 u (18.7 cm de RAYON, centre a 745 u du joint)
    #                 alors que la capsule `Rmidhairb->Rmidhaira` mesure 228 u a ce meme joint
    #
    # Ce sont deux mesures de la MEME chose au MEME endroit : l'une perpendiculaire a l'axe de l'os
    # (l'epaisseur), l'autre radiale autour d'un centroide (la longueur). Elles ne peuvent pas etre
    # toutes les deux justes, et c'est la perpendiculaire qui decrit un obstacle.
    #
    # CE QUE LE SUR-DIMENSIONNEMENT COUTE, MESURE PAR `probe_rest_containment.py` sur le fichier
    # LIVRE : les meches FINES reposent DEJA a l'interieur de la sphere de la meche EPAISSE —
    # `Rbangc` a -467 u dedans, `Lbangc` a -267 u. Le moteur accorde ce recouvrement de repos
    # (`feff = floor0`), donc sur cette profondeur le volume ne protege rien ; mais des que la meche
    # fine bouge d'un millimetre vers l'interieur elle rencontre un mur de 18 cm de rayon. C'est la
    # signature exacte de ce que l'owner decrit depuis six passes : « les meches fines sont
    # completement statiques » a cote de « ca part en vrille au milieu ».
    #
    # LA REGLE, DERIVEE DU RIG ET SANS AUCUN FILTRE PAR CHAINE (DIRECTIVES regle 4) : un joint qui
    # est DEJA une extremite de capsule dans sa propre part possede une epaisseur MESUREE
    # perpendiculairement a cet endroit. Sa sphere ne peut pas la depasser. La regle se limite
    # d'elle-meme — `lBoob`/`rBoob`, chaines a un seul maillon, ne sont l'extremite d'aucune capsule
    # et gardent leur blob entier, ce qui est correct : un sein EST compact.
    #
    # ON BORNE, ON NE SUPPRIME PAS. Retirer la ligne `collider` ferait retomber le rayon du LIEN sur
    # `radii=` (jak-hd-physics.gc:1032-1042) et ferait disparaitre un obstacle la ou la capsule ne
    # couvre pas tout (les 45 sommets d'oreille au-dela de `lEarb`, jusqu'a 30 cm, mesures par
    # `probe_skin_profile.py`). Borner retire le sur-dimensionnement sans retirer le volume.
    cap_end_radius = {}
    for _a, _b, _r1, _r2 in emitted_capsules:
        cap_end_radius[_a] = max(cap_end_radius.get(_a, 0.0), float(_r1))
        cap_end_radius[_b] = max(cap_end_radius.get(_b, 0.0), float(_r2))
    log('')
    log('  BORNE PERPENDICULAIRE DES SPHERES (un joint deja porte par une capsule)')

    for jn, pname in spheres:
        j = idx_of[jn]
        # POSSESSION RELATIVE A LA CHAINE des que la chaine SIMULEE porte 2+ joints (cf.
        # `chain_influence`). Le garde-fou est STRUCTUREL, pas un filtre par nom : une partie
        # obstacle (`body`, une oreille, une meche gelee) n'est pas ce que le solveur deplace, et
        # une chaine simulee a UN joint retombe sur `None`, donc sur le chemin d'avant, inchange.
        _members = parts_map.get(pname, [])
        _cidx = ([idx_of[m] for m in _members]
                 if pname in SIMULATED_CHAINS and len(_members) > 1 else None)
        c, r, n, t, cov = blob_centre_radius(geo, j, chain_idx=_cidx)
        if r is None or n == 0:
            log(f"DROPPED collider sphere {jn}: fitted from 0 vertices")
            continue
        cx, cy, cz = (int(round(float(v))) for v in c)
        r = int(round(r))
        r_iq, was_out, now_out = cov
        bound = None
        cap_r = cap_end_radius.get(jn)
        if cap_r is not None and r > int(round(cap_r)):
            bound = (r, int(round(cap_r)))
            log(f'  {jn:<14} p95 {r:>4} > epaisseur perpendiculaire {int(round(cap_r)):>4} '
                f'(capsule) — BORNE')
            r = int(round(cap_r))
        elif cap_r is not None:
            log(f'  {jn:<14} p95 {r:>4} <= epaisseur perpendiculaire {int(round(cap_r)):>4} '
                f'— inchange')
        else:
            log(f'  {jn:<14} p95 {r:>4}, extremite d\'aucune capsule — blob conserve')
        off = math.sqrt(cx * cx + cy * cy + cz * cz)
        log(f"sphere {jn}: centre ({cx},{cy},{cz}) |{off:.0f}u| radius {r} "
            f"(couverture p{COVER_PCT:.0f}: {100*now_out:.0f}% des sommets dehors — "
            f"la moyenne inter-quartile donnait {r_iq:.0f} et en laissait {100*was_out:.0f}%)")
        col_block.append(f'# sphere {jn} [{pname}]  {n}v @w>{t}   centre = measured centroid of the '
                         f'geometry this joint owns, {off:.0f}u off the joint, in its bind space'
                         f'   COVER p{COVER_PCT:.0f}: {100*now_out:.0f}% of its vertices outside'
                         f' (inner-quartile mean {r_iq:.0f} left {100*was_out:.0f}% outside)'
                         + (f'   BORNE PERPENDICULAIRE: p95 {bound[0]} -> {bound[1]} (ce joint est'
                            f' deja une extremite de capsule, qui mesure son epaisseur'
                            f' PERPENDICULAIREMENT ; le p95 d\'une geometrie allongee rend sa'
                            f' LONGUEUR)' if bound else ''))
        col_block.append(f'collider {jn} radius={r} offset={cx},{cy},{cz}')
        col_report.append(('sphere', jn, r, None, n, None))

    # ---------------------------------------------------------------------------------------------
    # LE VOLUME D'UN LIEN EST POSE SUR SON JOINT — MEME QUAND SA GEOMETRIE EST AILLEURS.
    #
    # Sans ligne `collider <joint>`, `phys-link-off!` rend un decalage NUL et le moteur pose la
    # sphere du lien SUR le joint. Pour une languette de genou, le joint est sur l'axe de la jambe
    # et la geometrie qu'il porte est a 716 u (p50) de cet axe : la sphere de collision du lien est
    # donc DANS la cuisse, en contact permanent avec `Rknee->Rthigh` et `Rankle->Rknee` qui se
    # recouvrent — sortir de l'une enfonce dans l'autre, la projection echoue, et le RECUL prend la
    # main. Mesure de la course : `kneeflapR` recule 15 913 fois sur 17 893 frames (89 %), et les
    # languettes sont les DEUX SEULES chaines sur 22 dont la courbe de reponse s'effondre aux
    # faibles excitations (0.36 et 0.21 au niveau 0 contre 28 a 158 pour les vingt autres).
    #
    # LA REGLE, ET SON DECLENCHEUR EST MESURE, PAS CHOISI : un lien dont le CENTROIDE de sa propre
    # geometrie est plus loin de son joint que son propre rayon porte un volume qui ne contient meme
    # pas le centre de ce qu'il represente. Celui-la est recentre ; les autres ne le sont pas, et
    # les deux listes sont journalisees avec leurs nombres.
    #
    # PERIMETRE : PAS LES CHEVEUX. Le recentrage y a ete pose, mesure et retire DEUX FOIS
    # (backhair -41 %, midhair -42/-43 %, 35 a 46 % d'allongement d'os sur `lbang`), une fois en
    # changeant la taille et une fois a taille identique au bit pres. L'hypothese laissee ouverte
    # par ce cycle-la — « les trois chaines qui cassent sont les trois chaines de cheveux, toutes
    # groupees sur le crane ; les chaines qui gagnent sont les spatialement isolees » — n'a jamais
    # ete testee, et son propre A/B portait deja `kneeflapR x1.40` a son credit. C'est cette
    # course-la, et elle est enfin faite.
    #
    # LA TAILLE NE BOUGE PAS D'UN BIT : `radius` est le rayon de lien deja livre, donc `*phys-lcr*`
    # est inchange (jak-hd-physics.gc:933 contre :942) et la SEULE variable est le centre.
    # SECOND EFFET, DECLARE PARCE QU'IL EST INSEPARABLE : le moteur lit cette meme ligne comme un
    # OBSTACLE pour les autres chaines. Un lien recentre devient donc un volume que les autres
    # voient, ce qu'il n'etait pas. C'est la SPEC 3 (« ce sont des volumes, pas seulement des
    # chaines ») et non un effet de bord subi, mais c'est une deuxieme variable et la course doit
    # etre lue en le sachant.
    already = {jn for jn, _p in spheres} | {jn for jn, _c, _a in carried_spheres}
    log('')
    log('  RECENTRAGE DES VOLUMES DE LIEN (chaines hors cheveux) : centroide contre rayon du lien')
    for jn, cname, rlink, cen, off, nv in recentre_cand:
        if jn in already:
            log(f'  {cname + "/" + jn:<26} deja un volume declare — inchange')
            continue
        if off <= rlink:
            log(f'  {cname + "/" + jn:<26} centroide a {off:>5.0f} u <= rayon {rlink:>4} — inchange')
            continue
        cx, cy, cz = cen
        log(f'  {cname + "/" + jn:<26} centroide a {off:>5.0f} u  > rayon {rlink:>4} — RECENTRE '
            f'({cx},{cy},{cz}), {nv} sommets')
        # LE RAYON N'EST PAS AFFIRME ICI. `apply_owner_tuning.py` resynchronise le rayon d'un volume
        # RECENTREE sur le rayon de lien LIVRE (il peut avoir ete retune par l'owner : gogglesMid
        # 79 -> 150). Ecrire un nombre dans ce commentaire le rendrait faux des la premiere retouche
        # de l'owner — c'est la ligne `collider` en dessous qui fait foi, pas ce texte.
        col_block.append(f'# sphere {jn} [{cname}] RECENTREE  {nv}v   le volume de ce lien etait pose'
                         f' sur son joint alors que sa geometrie est a {off:.0f} u de la : la TAILLE'
                         f' ne change pas (le rayon de lien livre, resynchronise par le tuning),'
                         f' seul le CENTRE bouge (centroide mesure, espace bind)')
        col_block.append(f'collider {jn} radius={rlink} offset={cx},{cy},{cz}')
        col_report.append(('sphere', jn, rlink, None, nv, None))

    for jn, cname, acc in carried_spheres:
        j = idx_of[jn]
        c, r, ntot, ncarr, out = carried_centre_radius(geo, j, acc)
        if r is None:
            log(f"DROPPED carried sphere {jn}: fitted from 0 vertices")
            continue
        cx, cy, cz = (int(round(float(v))) for v in c)
        r = int(round(r))
        off = math.sqrt(cx * cx + cy * cy + cz * cz)
        borne = ', '.join(f'{names[k]}({len(influence(geo, k, 0.25)[2])}v)' for k in acc)
        log(f"CARRIED sphere {jn} [{cname}]: {ntot}v dont {ncarr} portes ({borne}) -> "
            f"centre ({cx},{cy},{cz}) |{off:.0f}u| radius {r} ({100*out:.0f}% dehors)")
        col_block.append(f'# sphere {jn} [{cname}] CARRIED  {ntot}v dont {ncarr} portes par des '
                         f'joints HORS CHAINE ({borne}) : le moteur les deplace rigidement et ne '
                         f'les confrontait a RIEN. Le volume du lien couvre desormais ce qu\'il '
                         f'porte.   COVER p{COVER_PCT:.0f}: {100*out:.0f}% des sommets dehors')
        col_block.append(f'collider {jn} radius={r} offset={cx},{cy},{cz}')
        col_report.append(('sphere', jn, r, None, ntot, None))

    # ---- GEL DU PERIMETRE (owner 2026-08-14 07:30) ----------------------------------------------
    # « retire toute physique de Keira hormis ses seins ». Voir SIMULATED_CHAINS en tete de fichier.
    #
    # LE FILTRE EST POSE **ICI**, ET LA POSITION EST LE POINT IMPORTANT : APRES le bloc de
    # colliders, AVANT l'ecriture des chaines. Ce qui precede a donc lu la mesure des 22 chaines
    # et n'est pas altere d'un chiffre :
    #   * `link_radius` (ONE-JOINT-ONE-THICKNESS) garde les 46 rayons de lien mesures, donc les
    #     capsules `Lbangb`/`Rbangb` gardent 104/102 au lieu de remonter a 558/559 — l'inflation
    #     qui EST le defaut « les meches fines jittent des que la tete bouge » ;
    #   * les 15 spheres RECENTREES, collectees dans la boucle de chaines, restent emises : ce sont
    #     des obstacles (oreilles, lunettes, sangles) que SPEC-keira-physique 3 exige et que la gate
    #     ROOM-COLLIDER-COVERAGE verifie.
    # Autrement dit : on retire les SIMULATIONS, on ne retire pas la CONNAISSANCE du corps.
    #
    # `chain_report` est filtre EN MEME TEMPS que `chain_entries` : l'auto-controle n.1 (« every
    # emitted chain parses back ») compare les deux, et les desynchroniser aurait fait echouer la
    # generation avec un message sans rapport avec la cause.
    frozen_chains = [e['cname'] for e in chain_entries if e['cname'] not in SIMULATED_CHAINS]
    chain_entries = [e for e in chain_entries if e['cname'] in SIMULATED_CHAINS]
    chain_report = [r for r in chain_report if r[0] in SIMULATED_CHAINS]
    if frozen_chains:
        log(f'PERIMETRE (owner 07:30) : {len(chain_entries)} chaine(s) simulee(s) '
            f'{list(SIMULATED_CHAINS)}, {len(frozen_chains)} GELEE(S) et NON EMISES : '
            + ', '.join(frozen_chains))
    missing_scope = [c for c in SIMULATED_CHAINS if c not in {e['cname'] for e in chain_entries}]
    if missing_scope:
        # Un perimetre qui se vide en silence est le de-scope que la regle 3 interdit. Si un nom de
        # SIMULATED_CHAINS n'existe pas dans le rig, la generation s'arrete au lieu de livrer moins.
        raise SystemExit('SIMULATED_CHAINS nomme une chaine que le rig ne produit pas : %s'
                         % ', '.join(missing_scope))

    # ---- coques : `shell=` ----------------------------------------------------------------------
    # Mesure contre les volumes qui viennent d'etre emis, puis ecriture des lignes de chaine.
    shells = classify_shells(geo, groups, idx_of, emitted_capsules, log)
    for e in chain_entries:
        sh = shells.get(e['cname'])
        parts = list(e['parts'])
        if sh is not None:
            parts.append(f'shell={sh["r_int"]}')
        parts.append(e['radii_part'])
        chain_block.append(e['comment'])
        if sh is not None:
            chain_block.append(
                f'#   COQUE: {sh["joint"]} entoure le volume ETRANGER {sh["vol"]} — '
                f'{sh["sect"]}/{SHELL_NSEC} secteurs, gap {sh["gap"]:.0f} deg '
                f'(seuils {SHELL_SECT_MIN}/{SHELL_NSEC} et {SHELL_GAP_MAX:.0f} deg, '
                f'{sh["nv"]}v @w>{sh["thr"]}) : |c-axe|={sh["off"]:.0f} u + rr(c)={sh["rr"]:.0f} u '
                f'-> shell={sh["r_int"]} u, le rayon INTERNE du fourreau. Le rayon du lien est '
                f'celui du fourreau, pas celui d\'une sphere de poussee : sans cette cle le moteur '
                f'lit une penetration du membre que le lien ENTOURE et ejecte le tissu dedans.'
                + (f' ({sh["nqual"]} volumes qualifiaient, le plus contraignant est retenu.)'
                   if sh['nqual'] > 1 else ''))
        chain_block.append(' '.join(parts) + e['suffix'])
        for jn in e['joints']:
            chain_block.append(f'j {jn}')

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
    L.append(f'# mesh (hierarchie, pose de bind) : {RESOLVED_GLB}')
    L.append(f'# skin (poids, rayons, volumes)   : {RESOLVED_SKIN}')
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
    L.append('# rootlock=1 on every chain of 2+ joints EXCEPT the breast (SPEC section 2: the root')
    L.append('#            rides its carrier bone rigidly — that is a STRAND, whose root joint')
    L.append('#            overlaps the skull); omitted on 1-joint chains, where the parser default')
    L.append('#            is 0, and omitted on chestL/chestR, where SPEC 30 puts the anchor in the')
    L.append('#            TISSUE ("no hard attachment boundary") and where 75% of the chain mass')
    L.append('#            sits on the root link — pinning it would freeze three quarters of the')
    L.append('#            organ. The rigid anchor there is `chest`, which is OUTSIDE the chain.')
    L.append('# radius/radii = MEASURED off the skinned mesh, in GAME UNITS (4096 = 1 m): per link,')
    L.append('#            the inner-quartile (25..75 pct) mean of the perpendicular distance from')
    L.append('#            the vertices that link owns to its bone axis, in that link\'s bind space.')
    L.append('# stiffness (Hz) / damping (0..1) / mass / couple are the only hand-chosen numbers;')
    L.append('#            they are tuning constants and the owner retunes them here.')
    # `shell=` n'a PAS d'entree dans cet en-tete, et c'est deliberé : la ligne `#   COQUE: ...`
    # emise juste au-dessus de chaque chaine concernee porte deja la regle, ses deux seuils, la
    # mesure (|c-axe|, rr(c)) et le nombre. Documenter la cle ici en plus ferait diverger deux
    # textes pour une seule verite ; le detail complet vit dans le bloc SHELL_* du generateur.
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
    L.append('# ---- PERIMETRE SIMULE — ORDRE DE L\'OWNER DU 2026-08-14 07:30 ------------------')
    L.append('# « Tu sais quoi, retire toute physique de Keira hormis ses seins. Fais la spec de')
    L.append('#   ses seins a 100% comme specifie, on fera le reste apres. »')
    L.append(f'# SIMULEES ({len(chain_report)}) : ' + ', '.join(sorted(SIMULATED_CHAINS)))
    if frozen_chains:
        L.append(f'# GELEES ({len(frozen_chains)}), mesurees puis NON EMISES — une chaine inerte')
        L.append('# resterait un cout et un risque de derive, donc elle n\'existe pas du tout :')
        for i in range(0, len(frozen_chains), 6):
            L.append('#   ' + ', '.join(frozen_chains[i:i + 6]))
        L.append('# Ces organes ne sont pas FERMES, ils sont GELES : leurs defauts restent au')
        L.append('# dossier avec leur mesure et reviennent quand l\'owner le decide. Le gel se leve')
        L.append('# en rajoutant le nom dans SIMULATED_CHAINS (physics_keira_gen2.py), jamais ici.')
    L.append('#')
    L.append('# ---- Les COLLIDERS ci-dessous ne sont PAS geles : ce sont des obstacles, pas des')
    L.append('# chaines. La poitrine doit les rencontrer (SPEC-breast-softbody 33 et 34) et')
    L.append('# SPEC-keira-physique 3 exige que crane, epaules et oreilles restent des volumes.')
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
                      eyescale=eyescale, levels=levels, groups=groups, shells=shells,
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

    # 5. PERIMETRE SIMULE, puis couverture des parties que l'owner a nommees.
    #
    # AVANT LE 2026-08-14 cette check exigeait les CINQ regex de l'owner (ear / hair / bang|strand /
    # chest|breast / goggle) sur les chaines emises. Son ordre du 07:30 retire quatre de ces cinq
    # organes de la simulation : telle quelle, la check EXIGEAIT donc exactement ce qu'il vient
    # d'interdire. Elle n'est pas assouplie, elle est RETOURNEE — et elle attrape desormais deux
    # defauts que l'ancienne ne voyait pas :
    #   * une chaine GELEE qui reviendrait par une regeneration (l'ancienne s'en serait rejouie) ;
    #   * un organe DU perimetre qui disparaitrait en silence (de-scope, regle 3).
    emitted = sorted(c['name'] for c in chains)
    want_scope = sorted(SIMULATED_CHAINS)
    ck(emitted == want_scope,
       'les chaines emises sont EXACTEMENT le perimetre simule (owner 2026-08-14 07:30)',
       f'emises={emitted} perimetre={want_scope}')
    cover = {}
    for pat in ('ear', 'hair', 'bang|strand', 'chest|breast', 'goggle'):
        # GELE = aucun nom du perimetre ne matche : l'organe n'est plus simule, donc l'exiger dans
        # le fichier livre serait exiger sa resurrection. La ligne reste imprimee pour que le gel
        # soit LISIBLE dans le journal de generation, jamais silencieux.
        inscope = [c for c in SIMULATED_CHAINS if re.search(pat, c, re.I)]
        cover[pat] = ([c['name'] for c in chains if re.search(pat, c['name'], re.I)]
                      if inscope else None)
    missing = [p for p, v in cover.items() if v is not None and not v]
    ck(not missing,
       'couverture owner sur les parties DANS le perimetre (les autres sont GELEES, pas oubliees)',
       ' '.join(f'{p}->{"GELE" if v is None else len(v)}' for p, v in cover.items())
       + (f' MISSING {missing}' if missing else ''))

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

    # 6c. COQUES : la regle designe EXACTEMENT les deux pans de pantacourt, ni plus ni moins.
    # Elle n'est pas invariante au seuil de poids de skinning (cf. le bloc SHELL_* en tete) : a
    # w>0.05 pour tout le monde elle declarerait la POITRINE fourreau. Une regle qui derive doit
    # faire ECHOUER la generation, pas produire silencieusement d'autres donnees. La verification
    # porte sur le TEXTE EMIS, pas sur ce que le classement pretend avoir fait.
    # 2026-08-14 : LA REGLE RESTE EVALUEE SUR LES 37 LIENS, ET SON RESULTAT RESTE ASSERTE. Ce qui
    # devient dependant du perimetre, c'est seulement le TEXTE EMIS : `pantflapL`/`pantflapR` sont
    # gelees par l'ordre du 07:30, donc aucune ligne `shell=` ne peut plus etre ecrite pour elles.
    # Le detecteur de derive, lui, est INCHANGE : `classify_shells` designe-t-il toujours exactement
    # ces deux pans ? C'est l'assertion ci-dessous, et elle ne depend d'aucun gel.
    ck(sorted(info['shells']) == sorted(SHELL_EXPECTED),
       'la regle des coques designe toujours EXACTEMENT pantflapL/pantflapR sur les 37 liens',
       f'classees={sorted(info["shells"])} attendu={sorted(SHELL_EXPECTED)}')
    got = sorted(c['name'] for c in chains if 'shell' in c['kv'])
    want = sorted(c for c in SHELL_EXPECTED if c in SIMULATED_CHAINS)
    detail = (f'shell= sur {got} (attendu {want} — perimetre simule {sorted(SIMULATED_CHAINS)})'
              + ''.join(f' | {k}: {v["joint"]} autour de {v["vol"]} {v["sect"]}/{SHELL_NSEC} '
                        f'gap={v["gap"]:.0f} shell={v["r_int"]}'
                        for k, v in sorted(info['shells'].items())))
    bad_val = [(c['name'], c['kv']['shell']) for c in chains
               if 'shell' in c['kv'] and not (c['kv']['shell'].isdigit()
                                              and int(c['kv']['shell']) > 0)]
    ck(got == want and not bad_val,
       'shell= est ecrit sur pantflapL/pantflapR et sur elles seules, valeur entiere > 0',
       detail + (f' VALEURS INVALIDES {bad_val}' if bad_val else ''))

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
            # `--chains args.out` — SANS LUI, UNE GENERATION DE VERIFICATION REECRIT LE LIVRE.
            # Mesure du 2026-08-17 : cet appel n'avait AUCUN argument, donc il reglait toujours
            # `recharged_assets/physics_chains.txt`, y compris quand ce generateur ecrivait vers
            # `/tmp`. Le fichier de verification ressortait NON regle (donc incomparable au
            # livre), et le livre etait reecrit en effet de bord alors que le demon
            # `auto_build_apk` tourne. Les deux fautes tombent avec le meme argument.
            _r = _sp.run(['python3', _os.path.join(_root, '.autoport', 'apply_owner_tuning.py'),
                          '--chains', args.out],
                         capture_output=True, text=True, timeout=120)
            print((_r.stdout or _r.stderr).strip())
            if _r.returncode not in (0,):
                print('[gen] ATTENTION: la reapplication des reglages owner a echoue (%d)'
                      % _r.returncode)
        except Exception as _e:
            print('[gen] ATTENTION: reglages owner NON reappliques: %s' % _e)
        log('')
        # LE SHA ANNONCE EST CELUI DU FICHIER SUR DISQUE, PAS DU TEXTE D'AVANT LES REGLAGES.
        # Cette ligne relisait `text`, c'est-a-dire l'etat AVANT `apply_owner_tuning.py`. Le
        # fichier reellement livre est plus long (les reglages de l'owner s'y ajoutent), donc le
        # journal annoncait une taille et une empreinte que le fichier n'a jamais eues. Le cycle
        # 16 s'est casse les dents dessus : son log de retrait dit « 26309 bytes, sha b5f3387… »
        # alors que le fichier livre en fait 26360, et l'ecart de 51 octets a ete classe « NON
        # RECONSTRUCTIBLE » avec l'hypothese d'une regeneration fantome sur un couple rig/mesh
        # incoherent. Il n'y avait aucun fantome : le journal ne decrivait pas le livrable.
        try:
            _disk = open(args.out, 'rb').read()
            log(f'wrote {args.out}  ({len(_disk)} bytes, '
                f'sha256={hashlib.sha256(_disk).hexdigest()})  [apres reglages owner]')
            if len(_disk) != len(text):
                log(f'      (le generateur seul en produisait {len(text)} ; la difference EST '
                    f'l\'apport de keira-owner-tuning.txt)')
        except OSError as _e:
            log(f'wrote {args.out}  — RELECTURE IMPOSSIBLE ({_e}) ; empreinte du texte genere '
                f'seul : {len(text)} bytes, sha256={hashlib.sha256(text.encode()).hexdigest()}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
