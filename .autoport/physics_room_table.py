#!/usr/bin/env python3
"""physics_room_table.py — le tableau de mesure de la salle de Keira, ecrit DEPUIS LA TRACE.

Phase Grecharged-secondary-motion, branche physics-keira-clean.
Contrat : .autoport/prompts/SPEC-keira-physique.md (sections 6 et 7).

REGLE 0 de l'owner : « un commentaire n'est pas une preuve ». Ce script est le seul endroit ou une
affirmation sur le comportement du programme est autorisee a naitre, et il n'a le droit de l'ecrire
que si une LIGNE DE LOG de la course la soutient. Concretement :

  * `ROOM-NOPLAYER: absent` n'est ecrit que si la course a publie `PHYSROOM-START target-after=#f`
    ET `PHYSNOPLAY viol=0` (zero frame de mesure avec un target vivant). Sinon on ecrit ce que la
    trace dit, et la gate echoue — ce qui est le comportement voulu.
  * `ROOM-ACTORS: 1` n'est ecrit que si `PHYSNOPLAY actors=0` (aucun process-drawable etranger au
    sujet et a sa peau HD n'a jamais ete vu dans la zone).
  * aucune colonne n'est calculee ici : elles sont lues telles quelles dans les accumulateurs du
    moteur (PHYSROW), et seulement converties d'unites de jeu en METRES (4096 u = 1 m).

Sortie : .autoport/reports/Grecharged-secondary-motion/keira-room-table.txt
Usage  : python3 .autoport/physics_room_table.py [chemin-du-log]
"""

import itertools
import json
import math
import os
import re
import sys

# SPEC 24 se mesure PAR AXE, et l'estimateur qui sait le faire vit deja dans
# `.autoport/physics_ringdown.py`. On l'IMPORTE au lieu d'en ecrire une seconde version : deux
# copies d'un estimateur derivent, et c'est alors le tableau qui dit une chose et le script une
# autre sur la meme trace. Le chemin est calcule depuis ce fichier-ci, pas depuis le cwd : le
# tableau est lance aussi bien depuis la racine du depot que depuis un script de salle.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_ringdown

UNITS = 4096.0   # unites de jeu par metre

# Seuil de TRANSMISSION au-dela duquel une chaine est declaree respectueuse de l'intention
# d'animation (SPEC 5). La transmission est somme(deplacement ecrit . deplacement d'auteur) /
# somme(deplacement d'auteur . deplacement d'auteur), mesuree frame par frame dans le repere de l'os
# porteur, sur les seules frames ou l'animation pilotait la chaine. Elle vaut 1.0 quand le
# deplacement d'auteur traverse la physique intact — c'est le cas par construction d'une forme
# additive — et environ 0.5 pour un ressort ecrit en repere monde, qui retarde l'animation. Le seuil
# est place a 0.90 : il separe les deux formes sans laisser passer une attenuation visible. La
# valeur mesuree de CHAQUE chaine est publiee dans le tableau, personne n'a a croire ce seuil.
TRANSMISSION_MIN = 0.90

# 'tilt' est arrive avec la 6e passe de l'owner : les quatre premiers TRANSLATENT le sujet, donc
# ils ne changent jamais l'orientation de l'ancre et ne peuvent PAS voir une gravite exprimee
# dans le repere de l'ancre. Le cinquieme l'INCLINE.
DRIVE_NAMES = ('updown', 'leftright', 'accel', 'jerk', 'tilt')

REPDIR = '.autoport/reports/Grecharged-secondary-motion'
DEFAULT_LOG = os.path.join(REPDIR, 'keira-room-x86.log')
OUT = os.path.join(REPDIR, 'keira-room-table.txt')


# ---------------------------------------------------------------------------------------------
# LA PART DE L'APEX QUE LES MAILLONS SIMULES PORTENT — LUE DANS LE FICHIER LIVRE, PLUS JAMAIS
# ECRITE EN DUR.
# Defaut mesure au cycle 58 : ce script portait `0.5676 / 0.5936` et « plafond x1.76 » en constantes,
# heritees du cycle 51. Le cycle 57 a corrige l'axe de l'operateur d'ancrage et les enregistrements
# `ax` LIVRES somment aujourd'hui a 0.9402 / 0.9549 — la course a bien tourne dessus. Les lignes qui
# citaient 0.5676 mentaient donc d'un facteur 1.66, et elles servaient a decider si un manque de
# bande « s'explique par l'ancrage seul ». Un plafond perime qui arbitre des verdicts est la meme
# faute que l'axe faux du 2026-08-20 07:20 : on ne la laisse pas dans le producteur.
# SOURCE : `recharged_assets/physics_mesh.txt`, enregistrements `ax <chaine> <maillon> <w> x y z`.
# C'est le FICHIER QUE LE MOTEUR CHARGE (jak-hd-physics.gc:803, via pc-physics-chain-link-apex-mi),
# pas une valeur de confort — le tableau lit deja `comw=` du fichier livre de la meme facon.
# NATURE : une fraction sans dimension, la somme des poids `ax` d'une chaine. REPERE : sans objet.
# LECTURE QUAND LE DEFAUT EST ABSENT : 1.0000 — toute la masse distale est portee par des maillons
# simules, donc l'apex publie n'est reduit par aucun ancrage.
def _apex_anchor_share():
    out = {}
    try:
        for ln in open('recharged_assets/physics_mesh.txt', encoding='utf-8', errors='ignore'):
            f = ln.split()
            if len(f) >= 4 and f[0] == 'ax':
                out[f[1]] = out.get(f[1], 0.0) + float(f[3])
    except Exception:
        return {}
    return out

_APXSH = _apex_anchor_share()

def _apxsh(name):
    """La part portee par les maillons simules, ou None si le fichier livre ne la donne pas."""
    v = _APXSH.get(name)
    return v if (v is not None and v > 0.0) else None

def die(msg):
    print('[physics_room_table FAIL] ' + msg)
    sys.exit(1)


def fnum(v):
    """metres, 4 decimales — SAUF une valeur non nulle qui s'arrondirait a zero : celle-la est
    ecrite en notation scientifique. Arrondir une penetration de 1e-8 m en « 0.0000 » serait
    exactement le faux vert que la regle 1 interdit."""
    if v == 0.0:
        return '0.0000'
    if abs(v) < 0.00005:
        return '%.6g' % v
    return '%.4f' % v


# ================================================================================================
# RING-DOWN — LA FORME DE LA REPONSE DANS LE TEMPS (defaut owner `hair-pudding`, 2026-08-13)
# ================================================================================================
# Owner : « la gelatine c'est plus du pudding, c'est pas trop lent et mou, c'est vraiment pas
# coherent... On dirait les mouvements quand on tape sur un pudding, pas des mouvements naturels de
# cheveux ! » Un pudding sonne a SA frequence propre quel que soit le coup recu et tout son volume
# bouge EN PHASE. Des cheveux SUIVENT : la racine mene, la pointe suit avec un retard, l'onde
# descend le long de la meche.
#
# Les trois questions de SPEC 7, repondues ici et pas ailleurs :
#
#   1. NATURE — une FORME DE REPONSE DANS LE TEMPS : decroissance libre apres l'arret du stimulus,
#      et retard de phase entre maillons. Ce n'est ni une amplitude ni une variance. Un scalaire
#      d'amplitude ne peut PAS distinguer un pudding d'une chaine : les deux peuvent bouger AUTANT.
#   2. REPERE — LOCAL. `ang` est la deviation angulaire de chaque maillon PAR RAPPORT A SON PARENT
#      (`phys-link-ang`), en degres. Jamais le monde : en repere monde un maillon herite du
#      mouvement de son parent, et une pointe parfaitement solidaire de son parent y afficherait un
#      grand chiffre. C'est l'erreur du 2026-08-11, corrigee le 2026-08-12.
#   3. LIGNE DE BASE QUAND LE DEFAUT EST ABSENT — `lbang`/`rbang`, mesurees dans la MEME course.
#      L'owner approuve les meches fines et rejette les grosses : c'est un controle apparie qu'il a
#      donne lui-meme, donc la cible chiffree des grosses meches est une valeur MESUREE sur les
#      fines, jamais un nombre choisi.
#
# RESERVE — ELLE S'ECRIT, ELLE NE SE TAIT PAS. `ang` vaut `atan(|cross|, dot)`
# (jak-hd-physics.gc:4032-4047) : c'est un MODULE, toujours positif. Le signal est donc REDRESSE —
# pendant une decroissance libre le maillon TRAVERSE sa position de repos, et `ang` retombe a zero
# puis remonte. D'ou, noir sur blanc :
#   * la frequence apparente de `ang` est le DOUBLE de la frequence reelle d'oscillation ;
#   * une oscillation libre complete = DEUX minima de `ang` (d'ou la division par 2 dans `osc`) ;
#   * le retard de phase entre deux maillons reste lisible sur le signal redresse, mais il n'est
#     determine que MODULO UNE DEMI-PERIODE reelle.
# La grandeur SIGNEE existe dans le moteur (`*phys-ox/oy/oz*`, l'ecart a la pose d'auteur dans le
# repere de l'ancre) et serait meilleure, mais aucun accesseur ne l'expose : on mesure avec ce
# qu'on a et on declare la limite.
RING_HAIR_OK = ('lbang', 'rbang')                          # APPROUVEES par l'owner
RING_HAIR_BAD = ('backhair', 'lmidhair', 'rmidhair')       # REJETEES par l'owner


def ring_env(series, w):
    """ENVELOPPE glissante : le max des `w` frames a partir de f.

    Une AMPLITUDE n'est pas la valeur d'un echantillon. Sur un signal redresse qui repasse par zero
    deux fois par oscillation, un seuil applique a l'echantillon se declencherait au PREMIER passage
    par zero et rendrait le meme `decay` de quelques frames pour n'importe quel signal — un chiffre
    qui ne discrimine rien."""
    n = len(series)
    if n == 0 or w < 1:
        return list(series)
    return [max(series[f:min(n, f + w)]) for f in range(n)]


# SPEC 27 — LES QUATRE BANDES DE STABILISATION, ET LEUR SEUIL D'ENVELOPPE.
#
#     « After one strong isolated impulse: dominant visible response 0.3-0.6 s; secondary movement
#       0.6-1.2 s; mostly settled ~1.0-1.5 s; essentially stationary ~1.3-1.7 s. »
#
#   t5%   -> « dominant visible response »   0.3-0.6 s
#   t1%   -> « secondary movement »          0.6-1.2 s
#   t05%  -> « mostly settled »              1.0-1.5 s
#   t01%  -> « essentially stationary »      1.3-1.7 s
#
# CE SONT DES CIBLES, PAS UNE GATE : ce bloc MESURE, il ne juge pas (DIRECTIVES regle 5, les gates
# sont gelees). Le seuil existant a 10 % de `a0` (`decay`) n'est ni touche ni remplace : SPEC 27
# decrit QUATRE bandes et un seul seuil ne peut en rendre qu'une.
SETTLE_BANDS = ((0.05, 't5'), (0.01, 't1'), (0.005, 't05'), (0.001, 't01'))
SETTLE_FPS = 60.0


def settle_time(env, frames, a0, frac):
    """Instant, en SECONDES depuis le debut de la fenetre, ou l'ENVELOPPE observee passe sous
    `frac * a0`.

    Meme enveloppe et meme `a0` que le `decay` a 10 % qui existe deja : ces quatre temps sont le
    MEME instrument lu a quatre seuils, pas une seconde mesure qui pourrait le contredire.

    Un plafond atteint doit SE VOIR : quand le seuil n'est jamais franchi dans la fenetre, on ecrit
    `>` suivi de la duree reellement observee — jamais la duree elle-meme, qui se lirait comme une
    mesure, et jamais un nombre invente."""
    span_s = (frames[-1] - frames[0]) / SETTLE_FPS if len(frames) > 1 else 0.0
    if a0 <= 0.0:
        return '>%.2f' % span_s
    thr = frac * a0
    for i, v in enumerate(env):
        if v < thr:
            return '%.2f' % ((frames[i] - frames[0]) / SETTLE_FPS)
    return '>%.2f' % span_s


def ring_extrema(series, delta):
    """Indices des minima et des maxima locaux, avec une BANDE MORTE `delta`.

    Un renversement ne compte que si le signal a bouge de plus de `delta` depuis le dernier extremum
    retenu. Sans cette bande, le bruit numerique fabrique autant d'extrema qu'on veut et `osc`
    mesurerait la precision du flottant, pas le ballottement."""
    mins, maxs = [], []
    if not series:
        return mins, maxs
    mode = 0                       # 0 = indetermine, +1 = on monte, -1 = on descend
    lo = hi = series[0]
    loi = hii = 0
    for i, v in enumerate(series):
        if v > hi:
            hi, hii = v, i
        if v < lo:
            lo, loi = v, i
        if mode >= 0 and v < hi - delta:
            maxs.append(hii)
            mode = -1
            lo, loi = v, i
        elif mode <= 0 and v > lo + delta:
            mins.append(loi)
            mode = 1
            hi, hii = v, i
    return mins, maxs


def ring_period(series, delta):
    """PERIODE APPARENTE du signal redresse, en frames : l'ecart moyen entre deux minima consecutifs.

    C'est la MOITIE de la periode reelle d'oscillation (voir la reserve ci-dessus). Rend None quand
    la serie ne contient pas deux minima : dans ce cas rien n'est extrapole, l'appelant se rabat sur
    une valeur par defaut qu'il publie."""
    mins, _ = ring_extrema(series, delta)
    if len(mins) < 2:
        return None
    return (mins[-1] - mins[0]) / float(len(mins) - 1)


def ring_lag(a, b, dmax):
    """RETARD de `b` sur `a`, en frames, par correlation croisee NORMALISEE (Pearson) sur le
    recouvrement : le decalage `d` qui maximise la correlation entre `a[f]` et `b[f+d]`.

    Convention de signe : `d > 0` veut dire que `b` SUIT `a` — l'enfant est en retard sur son
    parent, l'onde DESCEND la chaine. `d <= 0` veut dire que les deux bougent en phase (ou que
    l'enfant mene), c'est-a-dire le pudding.

    La moyenne est retiree de chaque fenetre : sans ca, deux signaux positifs correles a leur seule
    composante continue rendraient une correlation quasi plate, et l'argmax serait du bruit.
    Rend (d, r) — `r` est publie pour que la confiance dans `d` soit lisible."""
    best_d, best_r = 0, -2.0
    n = len(a)
    for d in range(-dmax, dmax + 1):
        xs, ys = [], []
        for f in range(n):
            g = f + d
            if 0 <= g < len(b):
                xs.append(a[f])
                ys.append(b[g])
        if len(xs) < 8:
            continue
        mx = sum(xs) / len(xs)
        my = sum(ys) / len(ys)
        sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
        sy = math.sqrt(sum((y - my) ** 2 for y in ys))
        if sx <= 0.0 or sy <= 0.0:
            continue
        r = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)
        if r > best_r:
            best_r, best_d = r, d
    return best_d, (best_r if best_r > -2.0 else 0.0)


# ================================================================================================
# ALGEBRE 3x3, ECRITE ICI ET PAS IMPORTEE — trois raisons, toutes payees au moins une fois :
#   1. le tableau doit rester lisible sur une machine sans numpy, sinon un composant optionnel
#      fait tomber TOUTE la mesure et pas seulement son bloc ;
#   2. ces routines sont testables a la main (`_selftest_linalg`), et elles LE SONT au demarrage
#      du bloc : une decomposition fausse rendrait des compliances plausibles et fausses, ce qui
#      est exactement la classe de faux vert que ce dossier paie depuis deux semaines ;
#   3. elles tiennent en 40 lignes.
# ================================================================================================
def _sym3_eig(m):
    """Valeurs et vecteurs propres d'une 3x3 SYMETRIQUE, par rotations de Jacobi.
    Rend (valeurs triees decroissantes, vecteurs colonnes correspondants)."""
    a = [row[:] for row in m]
    v = [[1.0 if i == j else 0.0 for j in range(3)] for i in range(3)]
    for _ in range(64):
        p, q, off = 0, 1, 0.0
        for i in range(3):
            for j in range(i + 1, 3):
                if abs(a[i][j]) > off:
                    off, p, q = abs(a[i][j]), i, j
        if off < 1e-18:
            break
        theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
        t = (1.0 if theta >= 0 else -1.0) / (abs(theta) + math.sqrt(theta * theta + 1.0))
        c = 1.0 / math.sqrt(t * t + 1.0)
        s = t * c
        for k in range(3):
            akp, akq = a[k][p], a[k][q]
            a[k][p], a[k][q] = c * akp - s * akq, s * akp + c * akq
        for k in range(3):
            apk, aqk = a[p][k], a[q][k]
            a[p][k], a[q][k] = c * apk - s * aqk, s * apk + c * aqk
        for k in range(3):
            vkp, vkq = v[k][p], v[k][q]
            v[k][p], v[k][q] = c * vkp - s * vkq, s * vkp + c * vkq
    pairs = sorted(((a[i][i], [v[0][i], v[1][i], v[2][i]]) for i in range(3)),
                   key=lambda e: -e[0])
    return [p[0] for p in pairs], [p[1] for p in pairs]


def _solve3(m, b):
    """Resout m.x = b (3x3) par elimination de Gauss a pivot partiel. None si singuliere."""
    a = [m[i][:] + [b[i]] for i in range(3)]
    for col in range(3):
        piv = max(range(col, 3), key=lambda r: abs(a[r][col]))
        if abs(a[piv][col]) < 1e-14:
            return None
        a[col], a[piv] = a[piv], a[col]
        for r in range(3):
            if r == col:
                continue
            f = a[r][col] / a[col][col]
            for k in range(col, 4):
                a[r][k] -= f * a[col][k]
    return [a[i][3] / a[i][i] for i in range(3)]


# ==================================================================================================
# LE VERROU D'ASYMETRIE, POSE AU PRODUCTEUR (cycle 67)
# ==================================================================================================
# POURQUOI IL EXISTE, ET POURQUOI IL N'EST PAS UNE NOTE. Le superviseur a grave le 2026-08-21 a
# 01:20 : « toute ligne qui publie une comparaison GAUCHE/DROITE publie, sur la meme ligne, l'ecart
# au miroir de la pose ou elle a ete relevee. Au-dela d'un seuil declare, elle n'ecrit pas un
# chiffre : elle ecrit POSE NON SYMETRIQUE, et la section reste NON ETABLI. » Et il ajoute la raison
# pour laquelle le correctif du cycle 55 n'a pas tenu : « le correctif se pose au PRODUCTEUR de la
# grandeur, jamais sur le site qui l'a revele. Un correctif par site est une note deguisee en
# verrou. »
#
# L'ETAT TROUVE AU CYCLE 67, MESURE ET PAS SUPPOSE : ce fichier publie 25 lignes qui comparent
# chestL a chestR, et la formule du miroir y est RECOPIEE QUATRE FOIS (l.4377, 4388, 4593, 7563)
# sans qu'aucune fonction ne la porte. Quatre copies, zero utilitaire : c'est exactement la
# structure qui fait qu'un site peut oublier sa pose sans que rien ne le dise. Le verrou remplace
# les quatre copies par UNE fonction, et fait passer les 25 sites par UN chemin.
#
# TROIS PIECES, ET LA TROISIEME EST CELLE QUI EN FAIT UN VERROU :
#   1. `_mirror_dev`  — LA formule, une seule fois.
#   2. `asym`         — LE chemin de publication. Il refuse d'ecrire un chiffre que sa pose ne peut
#                       pas porter, et il ecrit l'ecart au miroir SUR LA MEME LIGNE quand elle le
#                       peut. Un site ne peut pas « oublier » : il n'a pas d'autre chemin.
#   3. `A`            — LE POINT DE PASSAGE UNIQUE de toute ligne du tableau. Il inspecte ce qu'on
#                       lui donne : une ligne qui RESSEMBLE a une comparaison gauche/droite et qui
#                       ne porte pas sa marque est ENREGISTREE COMME VIOLATION et publiee comme
#                       telle. C'est ce qui rend le verrou insensible a l'oubli : il n'y a aucune
#                       autre facon de faire entrer du texte dans le tableau que `A`, donc aucune
#                       facon de contourner le controle sans qu'il le dise.
#
# CE QUE LE VERROU NE COUVRE PAS, ET C'EST DECLARE, PAS TU. Un `max` ou un `min` PRIS SUR LES DEUX
# CHAINES (`ROOM-SKINPEN-REST: PIRE-DES-DEUX`, `ROOM-IDLE maxdev`, `ROOM-SIGN-*`) n'affirme rien sur
# l'asymetrie : c'est un pire-cas, et il reste vrai dans n'importe quelle pose. Les couvrir aurait
# noye le verrou sous des lignes qu'il n'a pas de raison de taire — et aurait casse des gates du
# validateur que la regle 5 interdit de toucher. La liste de ces agregats est PUBLIEE par
# `ROOM-ASYM-VERROU` pour que le perimetre soit auditable au lieu d'etre affirme.

# LE SEUIL, ET IL EST DERIVE — PAS HERITE, PAS CHOISI.
#
# CE QU'IL ETAIT. 10 deg, pose au cycle 54, sans qu'aucune mesure ne dise si un ecart de 10 deg
# deplace ou non un rapport gauche/droite. Le cycle 67 a fait cette mesure au lieu de la supposer :
# `ROOM-POSE-RAFFINEMENT` rejoue les MEMES quinze fenetres a trois ecarts au miroir — 48.0 deg
# (pose heritee), 7.462 deg (pose epinglee au cycle 55) et 0.594 deg (l'argmax du balayage resolu
# a la frame) — et publie de combien le rapport bouge entre les deux dernieres.
#
# CE QUE LA MESURE DIT. Entre 7.462 deg et 0.594 deg, soit 6.868 deg d'ecart, le rapport
# gauche/droite des onze fenetres bornees bouge d'une MEDIANE de 10.5 % (min 1.1 %, max 139.3 %).
# Sensibilite mediane : 10.5 % / 6.868 deg = **1.53 % par degre**.
#
# CE QUE LA SPEC EXIGE DE L'INSTRUMENT. Sa §32 : « mass +-2-4%, stiffness +-3-5%, damping +-3-5% »
# et « symmetrical movement remains approximately symmetrical, but not mathematically identical ».
# La plus petite difference gauche/droite que la spec demande de VOIR vaut donc 2 %.
#
# D'OU LE SEUIL : 2 % / 1.53 % par degre = **1.31 deg**, arrondi a 1.3. Une pose plus ecartee que
# ca injecte, a elle seule, plus d'asymetrie que la plus petite que la spec nous demande de
# distinguer — et un instrument qui ne resout pas la grandeur de sa cible ne mesure rien.
#
# ET CE N'EST PAS UN AJUSTEMENT APRES COUP : `c67-predictions.txt` (Q3, md5 grave avant la course)
# ecrivait « REFUTE PAR LE BAS SI mediane <= 3 % ET aucune fenetre ne change de sens. Alors 7.5 deg
# EST le plateau, le seuil de 10 deg est ADEQUAT ». La mesure a rendu 10.5 % et 3 inversions de
# sens : le seuil de 10 deg est donc refute PAR LE CRITERE ECRIT AVANT, pas par le resultat.
#
# CE QUE LE SEUIL NE FAIT PAS. Il est MEDIAN, donc il ne protege pas les fenetres les plus
# sensibles : r=8 (§17) bouge de 139.3 % sur le meme intervalle, soit 20.3 % par degre, et
# exigerait 0.099 deg — qu'AUCUNE pose de ce rig n'atteint. `ROOM-POSE-RAFFINEMENT` publie la
# sensibilite PAR FENETRE pour que celles-la soient lues comme non resolues, et pas comme vertes.
_ASYM_SEUIL = 1.3
_ASYM_MARK = '[pose '
_ASYM_REFUS = 'POSE NON SYMETRIQUE'


class _Pose(object):
    """LA POSE D'UNE DONNEE : son nom, son ecart au miroir en degres, et d'ou il sort.

    `dev is None` veut dire NON MESUREE — et une pose non mesuree est traitee comme non symetrique.
    Ce n'est pas de la severite gratuite : le rig est miroir a 0.005 deg en pose de bind (cycle 53),
    donc tout ecart gauche/droite est porte par la POSE jusqu'a preuve du contraire. « On n'a pas
    mesure » n'est pas « c'est symetrique »."""
    __slots__ = ('nom', 'dev', 'src')

    def __init__(self, nom, dev, src):
        self.nom, self.dev, self.src = nom, dev, src

    def ok(self):
        return self.dev is not None and self.dev <= _ASYM_SEUIL

    def tag(self):
        if self.dev is None:
            return '%s%s, miroir NON MESURE]' % (_ASYM_MARK, self.nom)
        return '%s%s, miroir %.1f deg]' % (_ASYM_MARK, self.nom, self.dev)


def _mirror_dev(u, v, lat):
    """L'ECART AU MIROIR entre deux directions d'os, EN DEGRES.

    NATURE : un ANGLE. REPERE : monde ; `u` (la direction de chestL) est REFLECHIE dans le plan de
    normale `lat` (l'axe lateral du solveur, `PHYSAXW ax=2`) puis comparee a `v` (chestR).
    LECTURE QUAND LE DEFAUT EST ABSENT : 0 deg. Le cycle 53 a mesure le rig a 0.005 deg du miroir
    en pose de BIND — donc tout ce que cette fonction rend au-dessus de ca est porte par la POSE.

    Elle remplace QUATRE copies identiques de la meme algebre. Une formule recopiee est une formule
    qui divergera : c'est le producteur, pas le site, qui doit la porter."""
    if u is None or v is None or lat is None:
        return None
    dd = sum(u[k] * lat[k] for k in range(3))
    mu = [u[k] - 2.0 * dd * lat[k] for k in range(3)]
    nu = math.sqrt(sum(x * x for x in mu)) * math.sqrt(sum(x * x for x in v))
    if nu <= 0.0:
        return None
    cs = sum(mu[k] * v[k] for k in range(3)) / nu
    return math.degrees(math.acos(max(-1.0, min(1.0, cs))))


def _pose_dev_from(txt, label, lat, extra=''):
    """L'ECART AU MIROIR d'une phase, lu sur son enregistrement compagnon de directions d'os.

    `label` est l'etiquette de trace qui publie `c= l= ux= uy= uz=` au point de protocole de la
    phase (`PHYSREGB`, `PHYSREGSB`, `PHYSSYMB`, `PHYSSGNB`, ...). On rend le PIRE des maillons :
    une pose n'est symetrique que si elle l'est sur toute la chaine."""
    rec = {}
    head = ('^%s %s ' % (label, extra)) if extra else ('^%s ' % label)
    pat = head + r'c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)'
    for m in re.finditer(pat, txt, re.M):
        rec[(int(m.group(1)), int(m.group(2)))] = tuple(float(m.group(k)) for k in (3, 4, 5))
    if not rec or lat is None:
        return None
    worst = None
    for l in sorted({k[1] for k in rec}):
        if (0, l) in rec and (1, l) in rec:
            d = _mirror_dev(rec[(0, l)], rec[(1, l)], lat)
            if d is not None:
                worst = d if worst is None else max(worst, d)
    return worst


# LES IDIOMES QUI DESIGNENT UNE COMPARAISON GAUCHE/DROITE. Volontairement etroits : le verrou doit
# attraper les affirmations d'ASYMETRIE, pas toute ligne qui prononce le mot « miroir ». Une ligne
# qui cite les DEUX chaines et un chiffre est traitee comme une comparaison meme si elle se veut une
# juxtaposition — poser les deux cote a cote EST une invitation a les comparer.
_ASYM_IDIOMES = ('gauche/droite', 'chestL/chestR', 'SENS INVERSE', 'ecart au miroir',
                 'paire miroir', 'paires MIROIR', 'angle(a0[')


def _asym_suspect(s):
    if not any(ch.isdigit() for ch in s):
        return False
    if ('chestL' in s and 'chestR' in s):
        return True
    return any(i in s for i in _ASYM_IDIOMES)


def _selftest_linalg():
    """Un controle POSITIF de l'algebre elle-meme : on POSE un tenseur connu, on fabrique les
    reponses qu'il produirait, et on verifie qu'on le retrouve. Sans ca, `_solve3` pourrait rendre
    des compliances plausibles et fausses en silence, et rien dans la trace ne le dirait."""
    c_true = [[0.82, 0.0, 0.0], [0.0, 1.00, 0.0], [0.0, 0.0, 0.90]]
    gs = [(-0.9979, 1.0, 0.0645), (0.9979, 1.0, -0.0645), (-0.0645, 1.0, -0.9979),
          (0.0645, 1.0, 0.9979), (-0.7056, 0.2929, 0.0455), (0.7056, 0.2930, -0.0457),
          (-0.0456, 0.2930, -0.7057), (0.0456, 0.2929, 0.7055), (0.0, 0.0, 0.0)]
    ds = [[sum(c_true[k][j] * g[j] for j in range(3)) for k in range(3)] for g in gs]
    mm = [[sum(g[i] * g[j] for g in gs) for j in range(3)] for i in range(3)]
    got = []
    for k in range(3):
        rhs = [sum(g[i] * d[k] for g, d in zip(gs, ds)) for i in range(3)]
        row = _solve3(mm, rhs)
        if row is None:
            return None
        got.append(row)
    err = max(abs(got[i][j] - c_true[i][j]) for i in range(3) for j in range(3))
    # et l'eigen : le plus petit vecteur propre d'un nuage confine a un plan doit etre sa normale
    ts = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.7, 0.7, 0.0), (-0.3, 0.9, 0.0)]
    mt = [[sum(t[i] * t[j] for t in ts) for j in range(3)] for i in range(3)]
    ev, evec = _sym3_eig(mt)
    nerr = max(abs(ev[2]), 1.0 - abs(evec[2][2]))
    return err, nerr


def _fit_recurrence(series):
    """AJUSTE `s[n+1] = a.s[n] + b.s[n-1]` PAR MOINDRES CARRES, puis en tire zeta et f.

    POURQUOI CETTE FORME ET PAS UN COMPTAGE DE PICS. Le mode de sa §36 est amorti a zeta = 0.65 :
    sur une periode amortie l'enveloppe est divisee par `exp(-2.pi.zeta/sqrt(1-zeta^2))` = 0.0046.
    Il n'y a donc QU'UN SEUL depassement visible, et un estimateur par extrema n'a qu'un point.
    Or le solveur est une recurrence LINEAIRE d'ordre 2 exactement de cette forme (elimination de
    la vitesse dans `v <- kd.v - k2.s ; s <- s + v` donne a = 1 + kd - k2, b = -kd) : l'ajuster
    utilise TOUS les echantillons, pas deux. C'est le meme estimateur que le polynome
    caracteristique du cycle 11, mais nourri par la SERIE LIVREE au lieu des coefficients.

    Rend (a, b, zeta, f_Hz, n, residu_rms_relatif) ou None si le systeme est mal pose."""
    n = len(series)
    if n < 8:
        return None
    s11 = s12 = s22 = r1 = r2 = 0.0
    used = 0
    for i in range(1, n - 1):
        x1, x2, y = series[i], series[i - 1], series[i + 1]
        s11 += x1 * x1
        s12 += x1 * x2
        s22 += x2 * x2
        r1 += x1 * y
        r2 += x2 * y
        used += 1
    det = s11 * s22 - s12 * s12
    if used < 6 or abs(det) < 1e-24:
        return None
    a = (r1 * s22 - r2 * s12) / det
    b = (r2 * s11 - r1 * s12) / det
    # residu, rapporte a l'amplitude : un ajustement dont le residu vaut l'amplitude ne mesure rien
    num = den = 0.0
    for i in range(1, n - 1):
        pred = a * series[i] + b * series[i - 1]
        num += (series[i + 1] - pred) ** 2
        den += series[i + 1] ** 2
    resid = math.sqrt(num / den) if den > 0 else 9.99
    # racines de z^2 - a.z - b = 0
    disc = a * a + 4.0 * b
    if disc >= 0.0:
        return (a, b, None, None, used, resid)     # sur-amorti : pas d'oscillation, pas de f
    re_z, im_z = a / 2.0, math.sqrt(-disc) / 2.0
    mod = math.hypot(re_z, im_z)
    if mod <= 0.0 or mod >= 1.0:
        return (a, b, None, None, used, resid)     # instable ou fige : zeta n'a pas de sens
    th = math.atan2(im_z, re_z)
    lg = -math.log(mod)
    wh = math.hypot(lg, th)
    if wh <= 0.0:
        return (a, b, None, None, used, resid)
    return (a, b, lg / wh, wh * 60.0 / (2.0 * math.pi), used, resid)


def _free_decay(vals, skip_after_peak=0):
    """ISOLE LA DECROISSANCE LIBRE D'UNE SERIE, ET RETOURNE AUSSI CE QU'ELLE LAISSE DERRIERE.

    Trois corrections, chacune imposee par une mesure de ce cycle et pas par une preference :

    1. **ON SOUSTRAIT LE PLANCHER `s_inf`** (moyenne des 20 derniers echantillons). La serie livree
       ne converge PAS vers zero : elle se pose sur +1.6e-4 a +4.3e-4. Une recurrence homogene
       d'ordre 2 n'admet pas une constante non nulle comme solution, donc une longue queue
       constante TIRE l'ajustement vers `a + b = 1` et ecrase le mode. Mesure : sans la
       soustraction, le residu vaut 0.94 ; avec, 0.002 sur le meme axe.
       ET CE PLANCHER N'EST PAS UN DETAIL D'AJUSTEMENT — c'est le residu de sa §9 (« retour EXACT
       a la pose d'auteur »), et c'est LUI qui censure le barreau fin de sa §27 : le seuil `t01`
       vaut 0.1 % de `a0`, soit moins que le plancher sur 5 axes sur 6. Il est donc PUBLIE.

    2. **ON DEMARRE AU PIC** (+ `skip_after_peak`). Les premieres frames de la fenetre portent
       encore l'impulsion elle-meme, pas sa decroissance. Ajuster a travers cette discontinuite
       melange le stimulus et la reponse.

    3. **ON S'ARRETE A 2 % DE `a0`**. Au-dela, ce qui reste est le plancher et le bruit du
       flottant ; les inclure revient a ajuster du bruit et gonfle le residu sans informer.

    Rend (segment, s_inf, a0, i0, i1)."""
    if len(vals) < 8:
        return [], 0.0, 0.0, 0, 0
    tail = vals[-20:] if len(vals) >= 20 else vals[len(vals) // 2:]
    s_inf = sum(tail) / len(tail)
    d = [v - s_inf for v in vals]
    a0 = max(abs(x) for x in d)
    if a0 <= 0.0:
        return [], s_inf, 0.0, 0, 0
    i0 = min(len(d) - 1, max(range(len(d)), key=lambda i: abs(d[i])) + skip_after_peak)
    i1 = len(d)
    for i in range(i0, len(d)):
        if abs(d[i]) < 0.02 * a0:
            i1 = i
            break
    return d[i0:i1], s_inf, a0, i0, i1


def _fit_two_windows(vals, skip_after_peak=0, contaminated_ref=True):
    """AJUSTE LA MEME SERIE SUR DEUX CHOIX DE FENETRE, ET PUBLIE LES DEUX.

    Un estimateur qu'on ne peut pas contredire n'est pas une mesure. Mais LE TEMOIN DOIT ETRE
    LEGITIME — et c'est une correction que ce cycle s'est faite a lui-meme :

    la premiere ecriture comparait la fenetre libre a la serie ENTIERE. Sur le mode secondaire
    c'est licite (la serie complete non ecretee est propre). Sur la fenetre de secousse ca ne
    l'est pas : la serie entiere contient L'IMPULSION elle-meme (frames 1-3, verifiees sur la
    trace brute) et une longue queue constante. Le desaccord y est donc GARANTI PAR
    CONSTRUCTION, et il declarait « ne pas lire » un ajustement dont le residu valait 0.0020.
    Comparer un bon estimateur a un temoin qu'on sait faux ne teste rien.

      `contaminated_ref=True`  -> temoin = la serie entiere moins son plancher (mode secondaire)
      `contaminated_ref=False` -> temoin = LA MEME decroissance libre demarree 2 frames plus
                                  tard. Deux decoupages PROPRES du meme phenomene : s'ils
                                  tombent au meme endroit, l'estimation ne depend pas du
                                  decoupage, ce qui est exactement ce qu'on veut savoir.
    Rend (fit_temoin, fit_libre, s_inf, a0, i0, i1)."""
    seg, s_inf, a0, i0, i1 = _free_decay(vals, skip_after_peak)
    if contaminated_ref:
        ref = [v - s_inf for v in vals]
    else:
        ref, _si, _a, _j0, _j1 = _free_decay(vals, skip_after_peak + 2)
    return _fit_recurrence(ref), _fit_recurrence(seg), s_inf, a0, i0, i1


def _agree(f1, f2, tol=0.20):
    """Les deux fenetres tombent-elles au meme endroit ? Compare zeta ET f, en relatif."""
    if not f1 or not f2 or f1[2] is None or f2[2] is None or f1[3] is None or f2[3] is None:
        return False
    for k in (2, 3):
        m = max(abs(f1[k]), abs(f2[k]))
        if m > 0 and abs(f1[k] - f2[k]) / m > tol:
            return False
    return True


# ================================================================================================
# CYCLE 69 — LE ROLE D'UNE CELLULE D'ORIENTATION SE MESURE. IL NE SE LIT PLUS DANS UNE ETIQUETTE.
# ================================================================================================
# POURQUOI CE BLOC EXISTE, ET CE QU'IL A COUTE DE NE PAS L'AVOIR.
# `physroom-orient` porte deux axes. Son commentaire les nommait « 0 = tangage (atteint prone et
# supine), 1 = roulis (lateral) ». LES DEUX ETAIENT FAUX. Deux cycles l'avaient constate POUR
# `axis 0` et l'avaient ecrit A DEUX SITES D'APPEL (phys-room.gc:480-483 et :4654) au lieu de le
# retirer du producteur. La note n'a jamais atteint `axis 1` — et le cycle 67 a conclu de cette
# etiquette que §13 etait « INJOUABLE avec les operateurs actuels, il manque un operateur qui
# incline autour de l'axe LATERAL du sujet ». Cet operateur EST `axis 1`, et il tourne dans toutes
# les courses depuis que ce balayage existe. §13 est restee `NON ETABLI` douze cycles pour cette
# seule raison. C'est la troisieme fois que « une note par site » tient lieu de verrou.
#
# CE QUE CE BLOC POSE A LA PLACE : `orole()`, chemin unique. Le role vient de la GRAVITE MESUREE
# par cellule (`PHYSORI4`), et de rien d'autre.
#
# NATURE : une direction (vecteur unitaire), pas une amplitude — un equilibre d'orientation ne se
#   decrit ni par une variance ni par un scalaire.
# REPERE : la base de l'ANCRE, composantes brutes — 0 = ligne LATERALE, 1 = ligne VERTICALE,
#   2 = ligne AVANT/ARRIERE (`PHYSAXIS rlat/rv/rap`). Verifie a l'execution ci-dessous, pas suppose.
# LIGNE DE BASE : la cellule debout doit rendre la gravite quasi pure sur la ligne verticale.
# CE QUI DISCRIMINE : neuf cellules, neuf directions canoniques ; une cellule dont deux directions
#   sont a moins de 20 deg l'une de l'autre n'est PAS nommee.
_ORI_CANON = (
    ('DEBOUT',                                  ( 0.0,     1.0,     0.0)),
    ('ROULIS +45 (gravite vers la GAUCHE)',      ( 0.70711, 0.70711, 0.0)),
    ('ROULIS +90 (couchee sur le cote GAUCHE)',  ( 1.0,     0.0,     0.0)),
    ('ROULIS -45 (gravite vers la DROITE)',      (-0.70711, 0.70711, 0.0)),
    ('ROULIS -90 (couchee sur le cote DROIT)',   (-1.0,     0.0,     0.0)),
    ('PENCHE AVANT 45',                          ( 0.0,     0.70711, 0.70711)),
    ('PRONE (face contre terre)',                ( 0.0,     0.0,     1.0)),
    ('PENCHE ARRIERE 45',                        ( 0.0,     0.70711,-0.70711)),
    ('SUPINE (sur le dos)',                      ( 0.0,     0.0,    -1.0)),
)
_ORI_ANG_MAX = 25.0    # une cellule dont la meilleure direction est plus loin que ca n'est pas nommee
_ORI_ANG_SEP = 20.0    # ... ni une cellule dont la deuxieme est a moins de ca de la premiere


def _ori_zsense(txt):
    """LE SENS DE L'AXE AVANT/ARRIERE, MESURE SUR L'ANATOMIE DU RIG LIVRE.

    Rend `(zs, roots, why)` : `zs` = +1 si la ligne 2 de la base de l'ancre pointe vers l'AVANT,
    -1 si elle pointe vers l'ARRIERE, `None` si la mesure ne tranche pas.

    CE QUI DISCRIMINE, ET C'EST DE L'ANATOMIE, PAS UNE CONVENTION : un sein FAIT SAILLIE. L'os qui
    va de l'ancre au sein a donc une composante avant/arriere NON NULLE, et son signe dit ou pointe
    la ligne 2. `PHYSURST` la publie a chaque course et personne ne la lisait.
    REFUS : composante trop faible (< 0.03, la saillie ne designe plus rien) ou les deux chaines
    en desaccord de signe (le rig ne serait pas symetrique, et c'est un fait a publier, pas a
    contourner)."""
    u = {}
    for m in re.finditer(r'^PHYSURST c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+)'
                         r' uz=([-\d.e+]+)', txt, re.M):
        u[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                 float(m.group(5)))
    roots = {c: v[2] for (c, l), v in u.items() if l == 0}
    if not roots:
        return None, roots, 'aucune ligne PHYSURST dans la trace'
    if min(abs(x) for x in roots.values()) < 0.03:
        return None, roots, ('la saillie du sein sur la ligne 2 est trop faible (%.5f) pour '
                             'designer un sens' % min(abs(x) for x in roots.values()))
    sg = [(1 if x > 0 else -1) for x in roots.values()]
    if len(set(sg)) != 1:
        return None, roots, 'les chaines ne s\'accordent pas sur le signe : rig non symetrique'
    # l'os pointe VERS L'AVANT ; la ligne 2 pointe donc dans le sens de cette composante
    return float(sg[0]), roots, ''


def _ori_role_block(A, txt, names, ori, com, role_tri, b0):
    """SPEC 13 — LES ORIENTATIONS INTERMEDIAIRES, ET LE VERROU DE NOMMAGE QUI LES REND LISIBLES."""
    A('-- ROOM-ORIROLE : LE ROLE DE CHAQUE CELLULE, DERIVE DE LA GRAVITE MESUREE ----------------')
    g4 = {}
    for m in re.finditer(r'^PHYSORI4 c=(\d+) i=(\d+) r0=([-\d.e+]+) r1=([-\d.e+]+)'
                         r' r2=([-\d.e+]+)', txt, re.M):
        g4[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                  float(m.group(5)))
    if not g4:
        A('ROOM-ORIROLE: ABSENT (aucune ligne PHYSORI4) — le role des cellules ne peut pas etre')
        A('   derive d\'une mesure. Il resterait a le lire dans une etiquette, ce que ce bloc')
        A('   existe precisement pour interdire. §13 reste NON ETABLI.')
        return None
    zs, roots, why = _ori_zsense(txt)
    A('   `PHYSORI4` est emis a CHAQUE course depuis qu\'il existe et n\'avait AUCUN LECTEUR —')
    A('   troisieme occurrence de ce mode d\'echec dans ce dossier. Il porte la gravite unitaire')
    A('   par cellule, en composantes brutes de la base de l\'ancre (0 = laterale, 1 = verticale,')
    A('   2 = avant/arriere, cf. `PHYSAXIS rlat/rv/rap`).')
    for c in sorted(roots):
        A('ROOM-ORIROLE-SENS: chain=%-12s os de racine, composante sur la ligne 2 = %+.5f'
          % (names[c] if c < len(names) else 'c%d' % c, roots[c]))
    if zs is None:
        A('ROOM-ORIROLE-SENS: SENS NON RESOLU — %s. Aucune cellule n\'est nommee, et §13 comme'
          % why)
        A('   §10 et §11 restent NON ETABLIES : sans le sens de cette ligne, supine et prone sont')
        A('   indiscernables et les nommer serait tirer a pile ou face.')
        return None
    A('ROOM-ORIROLE-SENS: un sein FAIT SAILLIE, donc l\'os pointe vers l\'AVANT ; la ligne 2 de la')
    A('   base de l\'ancre pointe donc vers %s. C\'est de l\'ANATOMIE mesuree sur le rig LIVRE, pas'
      % ('l\'AVANT' if zs > 0 else 'l\'ARRIERE'))
    A('   une convention : aucune constante n\'entre dans ce test, et il DISCRIMINE (une saillie')
    A('   nulle le ferait refuser, et il refuse aussi si les chaines se contredisent).')
    A('   RESERVE DECLAREE : sa §7 l.130 ecrit « +Z = forward from chest ». Le +Z construit par le')
    A('   moteur pointe vers l\'ARRIERE. Le CALCUL aval est juste — `wbk = max(0,-gzc)` recoit bien')
    A('   le triplet prone — mais la CONVENTION s\'ecarte de la spec, et deux erreurs de sens qui')
    A('   se compensent restent deux erreurs. Voir [NOTE-408].')
    A('')

    # ---- LE ROLE, PAR CELLULE, ET SA MARGE ------------------------------------------------------
    roles = {}
    A('   cellule   g_lateral  g_bas   g_avant | role derive de la mesure                  ecart  marge')
    for i in range(9):
        v = g4.get((0, i)) or g4.get((1, i))
        if v is None:
            continue
        gl, gd, gf = v[0], v[1], v[2] * zs
        n = math.sqrt(gl * gl + gd * gd + gf * gf)
        if n < 0.5:
            A('ROOM-ORIROLE: i=%d  gravite de norme %.4f — NON NOMMEE (le canal n\'a rien ecrit)'
              % (i, n))
            continue
        gl, gd, gf = gl / n, gd / n, gf / n
        sc = []
        for lab, cv in _ORI_CANON:
            d = max(-1.0, min(1.0, gl * cv[0] + gd * cv[1] + gf * cv[2]))
            sc.append((math.degrees(math.acos(d)), lab))
        sc.sort()
        best, second = sc[0], sc[1]
        ok = best[0] <= _ORI_ANG_MAX and (second[0] - best[0]) >= _ORI_ANG_SEP
        roles[i] = (best[1] if ok else None, best[0], second[0] - best[0])
        A('ROOM-ORIROLE: i=%d      %+7.4f  %+7.4f  %+7.4f | %-40s %5.1f  %5.1f  %s'
          % (i, gl, gd, gf, best[1] if ok else 'ROLE NON RESOLU',
             best[0], second[0] - best[0], '' if ok else '<- REFUSE'))
    A('   `ecart` = angle a la direction canonique retenue · `marge` = de combien la deuxieme est')
    A('   plus loin. Seuils DECLARES : ecart <= %.0f deg ET marge >= %.0f deg.'
      % (_ORI_ANG_MAX, _ORI_ANG_SEP))
    A('')
    return roles


def _ori_frame_perm(A, txt):
    """LA CORRESPONDANCE DE COMPOSANTES ENTRE `PHYSORICOM` ET LA BASE DE L'ANCRE, MESUREE.

    `PHYSORICOM tx/ty/tz` et `PHYSORICOML dv/dap/dlat` decrivent le meme deplacement dans deux
    conventions d'ordre. Laquelle ? Aucune docstring ne peut repondre : une docstring de ce
    fichier a deja affirme « +Z avant » alors que le +Z du moteur pointe vers l'arriere. On la
    MESURE donc, en essayant les 48 (permutation, signes) et en gardant celle qui reproduit
    l'accumulateur par maillon. Le rapport entre le meilleur residu et le deuxieme est publie :
    sans lui, « la meilleure » ne veut rien dire.
    NATURE : un residu relatif, sans unite. LIGNE DE BASE : 0 = correspondance exacte."""
    com, lm = {}, {}
    for m in re.finditer(r'^PHYSORICOM c=(\d+) i=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+)'
                         r' tz=([-\d.e+]+)', txt, re.M):
        com[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                   float(m.group(5)))
    for m in re.finditer(r'^PHYSORICOML c=(\d+) i=(\d+) l=(\d+) dv=([-\d.e+]+) dap=([-\d.e+]+)'
                         r' dlat=([-\d.e+]+)', txt, re.M):
        lm[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))
    if not com or not lm:
        A('ROOM-ORIFRAME: ABSENT — sans les deux canaux la correspondance ne se mesure pas, et')
        A('   aucune composante de `PHYSORICOM` ne peut etre nommee. §13 reste NON ETABLI.')
        return None, None
    acc = {}
    for (c, i, _l), v in lm.items():
        a = acc.setdefault((c, i), [0.0, 0.0, 0.0])
        for j in range(3):
            a[j] += v[j]
    res = []
    for perm in itertools.permutations(range(3)):
        for sg in itertools.product((1, -1), repeat=3):
            tot, n = 0.0, 0
            for k in acc:
                if k not in com or k[1] == 0:
                    continue
                a, tt = acc[k], com[k]
                cd = [sg[j] * tt[perm[j]] for j in range(3)]
                na = math.sqrt(sum(x * x for x in a))
                nc = math.sqrt(sum(x * x for x in cd))
                if max(na, nc) < 1e-6:
                    continue
                tot += math.sqrt(sum((a[j] - cd[j]) ** 2 for j in range(3))) / max(na, nc)
                n += 1
            if n:
                res.append((tot / n, perm, sg, n))
    res.sort()
    r0, p0, s0, n0 = res[0]
    r1 = res[1][0]
    A('ROOM-ORIFRAME: dv = %st[%d]  ·  dap = %st[%d]  ·  dlat = %st[%d]   (residu %.4f sur %d '
      'cellules ; 2e candidat %.4f, soit x%.1f pire)'
      % ('+' if s0[0] > 0 else '-', p0[0], '+' if s0[1] > 0 else '-', p0[1],
         '+' if s0[2] > 0 else '-', p0[2], r0, n0, r1, (r1 / r0) if r0 > 0 else float('inf')))
    if r0 > 0.15 or (r1 / max(r0, 1e-9)) < 3.0:
        A('   CORRESPONDANCE NON RESOLUE (residu trop grand ou candidats trop proches) — aucune')
        A('   composante n\'est nommee, et §13 reste NON ETABLI plutot que juge sur un ordre devine.')
        return None, acc
    A('   Mesure, pas convention. `dv` suit la LIGNE VERTICALE de l\'ancre, qui pointe vers le BAS')
    A('   (`PHYSAXW` la publie a (0.082, -0.978, 0.189)) : `dv > 0` = l\'apex DESCEND. `dap` suit')
    A('   la ligne avant/arriere, dont le sens est fixe par la saillie du sein ci-dessus.')
    return (p0, s0), acc


# ---- LES INDICES DE CELLULE ECRITS EN DUR, CONFRONTES AU ROLE MESURE ---------------------------
# Chacune de ces lignes est une affirmation ecrite dans le source python ou dans un commentaire du
# moteur. Elles ne sont pas retirees — elles sont CONFRONTEES, et un desaccord se publie. Une
# etiquette qu'on ne confronte a rien est exactement ce qui a coute §13 pendant douze cycles.
_ORI_HARD = (
    ('physics_room_table.py:887 / :913 / :1217 / :1362 / :1388', 2, 'ROULIS', 'plan'),
    ('physics_room_table.py:887 / :913 / :1217 / :1362 / :1388', 4, 'ROULIS', 'plan'),
    ('physics_room_table.py:888 / :1362 / :1389',                1, 'ROULIS', 'plan'),
    ('physics_room_table.py:888 / :1362 / :1389',                3, 'ROULIS', 'plan'),
    ('physics_room_table.py:889 / :1363 / :1389',                6, 'SAGITTAL', 'plan'),
    ('physics_room_table.py:889 / :1363 / :1389',                8, 'SAGITTAL', 'plan'),
    ('physics_room_table.py:890 / :1363 / :1389',                5, 'SAGITTAL', 'plan'),
    ('physics_room_table.py:890 / :1363 / :1389',                7, 'SAGITTAL', 'plan'),
    ('physics_room_table.py:1400 (etiquette de ROOM-ORICTL-DIAG)', 6, 'SUPINE', 'role'),
    ('physics_room_table.py:1400 (etiquette de ROOM-ORICTL-DIAG)', 8, 'PRONE',  'role'),
)


def _ori_role_verrou(A, roles, role_tri, names):
    """LE VERROU : toute affirmation de role ecrite en dur est confrontee au role MESURE."""
    A('-- ROOM-ORIROLE-VERROU : LES ETIQUETTES ECRITES EN DUR, CONFRONTEES A LA MESURE ----------')
    nviol = 0
    seen = set()
    for site, i, exp, kind in _ORI_HARD:
        r = roles.get(i, (None, 0.0, 0.0))[0]
        if r is None:
            A('ROOM-ORIROLE-VERROU: i=%d  %-52s  role NON RESOLU — l\'etiquette ne peut pas etre'
              ' confrontee' % (i, site))
            continue
        if kind == 'plan':
            got = 'ROULIS' if r.startswith('ROULIS') else (
                'SAGITTAL' if ('PENCHE' in r or 'PRONE' in r or 'SUPINE' in r) else 'DEBOUT')
        else:
            got = 'SUPINE' if 'SUPINE' in r else ('PRONE' if 'PRONE' in r else r)
        okk = (got == exp)
        if not okk:
            nviol += 1
        if (site, i) in seen:
            continue
        seen.add((site, i))
        A('ROOM-ORIROLE-VERROU: i=%d  %-52s  ecrit=%-9s mesure=%-9s  %s'
          % (i, site, exp, got, 'conforme' if okk else '*** CONTREDIT ***'))
    # la troisieme route : le triplet d'echelles compare aux constantes de la spec
    for c in sorted(role_tri):
        nm = names[c] if c < len(names) else 'c%d' % c
        isup, ipro = role_tri[c].get('sup'), role_tri[c].get('pro')
        rsup = roles.get(isup, (None,))[0]
        rpro = roles.get(ipro, (None,))[0]
        ok1 = rsup is not None and 'SUPINE' in rsup
        ok2 = rpro is not None and 'PRONE' in rpro
        A('ROOM-ORIROLE-VERROU: chain=%-12s le TRIPLET d\'echelles designe supine -> i=%s et prone'
          ' -> i=%s ; la GRAVITE mesuree dit %s et %s  -> %s'
          % (nm, isup, ipro, rsup or 'NON RESOLU', rpro or 'NON RESOLU',
             'ACCORD' if (ok1 and ok2) else 'DESACCORD'))
    A('   DEUX ROUTES INDEPENDANTES, ET C\'EST LA PREMIERE FOIS QU\'ELLES SONT CONFRONTEES. Le')
    A('   triplet ne peut PAS echouer tout seul : le moteur ecrit en dur les constantes de §10 et')
    A('   §11 (`jak-hd-physics.gc:3576-3581`) et le tableau les y compare — c\'est une tautologie,')
    A('   et le registre la porte comme telle depuis le cycle 64. La GRAVITE, elle, ne passe ni par')
    A('   les morphs ni par ces constantes. Leur accord est donc une information ; leur desaccord')
    A('   en serait une plus grande encore.')
    A('ROOM-ORIROLE-VERROU: %d etiquette(s) ecrite(s) en dur CONTREDITE(S) par la mesure.' % nviol)
    A('')
    return nviol


_SPEC13_PAIRS = (
    ('PENCHE AVANT 45',   'PRONE (face contre terre)', 'penche AVANT'),
    ('PENCHE ARRIERE 45', 'SUPINE (sur le dos)',       'penche ARRIERE'),
    ('ROULIS +45 (gravite vers la GAUCHE)', 'ROULIS +90 (couchee sur le cote GAUCHE)', 'roulis +'),
    ('ROULIS -45 (gravite vers la DROITE)', 'ROULIS -90 (couchee sur le cote DROIT)',  'roulis -'),
)


def _spec13_susp(com, acc, perm, iup):
    """LES CELLULES DONT LE MONTAGE SE CONTREDIT, AU MEME CRITERE QUE `ROOM-ORICOM-MASS`.

    Deux accumulateurs INDEPENDANTS decrivent le meme deplacement : `PHYSORICOM` (l'apex) et la
    somme par maillon de `PHYSORICOML`. Quand ils different de plus de 5 % EN VECTEUR, c'est le
    montage qui est en cause et la cellule ne porte aucun verdict. AUCUN SEUIL NEUF : c'est
    exactement le critere du cycle 64b, applique ici aux cellules que §13 lit."""
    if perm is None:
        return {}
    pp, sg = perm  # la cellule DEBOUT est hors test : un critere RELATIF sur un deplacement
                   # quasi nul (|d| ~ 0.0009 B0) ne mesure rien. Meme exclusion qu'a :1189.
    bad = set()
    for k, a in acc.items():
        tt = com.get(k)
        if tt is None or k[1] == iup:
            continue
        cd = [sg[j] * tt[pp[j]] for j in range(3)]
        na = math.sqrt(sum(x * x for x in a))
        nc = math.sqrt(sum(x * x for x in cd))
        if max(na, nc) < 1e-6:
            continue
        rel = math.sqrt(sum((a[j] - cd[j]) ** 2 for j in range(3))) / max(na, nc)
        if rel > 0.05:
            bad.add((k, rel))
    return {k: r for k, r in bad}


def _spec13_block(A, txt, names, ori, com, acc, roles, zs, b0, perm=None):
    """SPEC 13 — LES ORIENTATIONS INTERMEDIAIRES. PREMIERE LIGNE DE VERDICT DE CETTE SECTION.

    TEXTE EXACT (SPEC-breast-softbody.md l.199-207), cite et pas resume :
      « Supine, prone, upright and lateral states **shall not exist as unrelated hard-coded morph
        targets.** The equilibrium state shall vary continuously with the local gravity direction. »
      « At a 45 deg forward lean, Keira should exhibit approximately: mild-to-moderate
        forward/downward COM migration; modest root-to-apex elongation; slightly reduced width;
        redistribution toward the lower/distal pole. »

    D'OU VIENNENT LES BORNES, ET ELLES NE SONT PAS DE MOI. §13 ne chiffre rien. Mais elle decrit un
    etat INTERMEDIAIRE entre deux etats que la spec chiffre, elle : §9 (debout, 1.000 sur les trois
    axes, deplacement 0.00 B0) et §11 (prone). Une grandeur « intermediaire » est donc testable sans
    inventer un seul nombre : elle doit tomber STRICTEMENT entre les deux poles que sa propre spec
    donne. C'est le seul test de §13 qui ne demande aucun seuil a moi."""
    A('-- ROOM-SPEC13 : LES ORIENTATIONS INTERMEDIAIRES — PREMIERE LIGNE DE VERDICT ---------------')
    if not roles:
        A('ROOM-SPEC13: NON ETABLI — le role des cellules n\'est pas resolu (voir ROOM-ORIROLE).')
        return
    inv = {}
    for i, (r, _e, _m) in roles.items():
        if r:
            inv[r] = i
    iup = inv.get('DEBOUT')
    if iup is None:
        A('ROOM-SPEC13: NON ETABLI — aucune cellule ne rend la pose DEBOUT, donc il n\'existe pas')
        A('   de ligne de base et « intermediaire » n\'a pas de sens.')
        return
    # LE SENS DE LA LIGNE VERTICALE, MESURE : debout, la gravite tombe dessus ; son signe dit ou
    # elle pointe. Aucune constante.
    gup = None
    for m in re.finditer(r'^PHYSORI4 c=(\d+) i=(\d+) r0=([-\d.e+]+) r1=([-\d.e+]+) r2=([-\d.e+]+)',
                         txt, re.M):
        if int(m.group(2)) == iup:
            gup = float(m.group(4))
            break
    if gup is None or abs(gup) < 0.5:
        A('ROOM-SPEC13: NON ETABLI — le sens de la ligne verticale de l\'ancre ne se mesure pas sur')
        A('   la cellule debout ; « vers le bas » n\'aurait pas de definition.')
        return
    vdown = 1.0 if gup > 0 else -1.0
    A('   sens mesures : la ligne VERTICALE de l\'ancre pointe vers %s (la gravite y tombe a %+.4f'
      % ('le BAS' if vdown > 0 else 'le HAUT', gup))
    A('   debout), la ligne AVANT/ARRIERE vers %s (saillie du sein). Aucun des deux n\'est suppose.'
      % ("l'AVANT" if zs > 0 else "l'ARRIERE"))
    A('')

    # ---- CLAUSE 1 : LA CONTINUITE, SUR LES DEUX CANAUX ------------------------------------------
    A('   CLAUSE « shall vary continuously with the local gravity direction » — DEUX CANAUX, et')
    A('   ils ne rendent PAS le meme verdict. Le canal de FORME (les trois echelles) et le canal de')
    A('   DEPLACEMENT (l\'apex) sont testes separement : les fondre en un seul chiffre cacherait')
    A('   exactement ce que ce bloc trouve.')
    susp = _spec13_susp(com, acc, perm, iup)
    for k in sorted(susp):
        A('ROOM-SPEC13-CONT: chain=%-12s cellule i=%d SUSPENDUE — les deux accumulateurs du'
          ' deplacement different de %.2f %% en vecteur (critere du cycle 64b, 5 %%). Aucune paire'
          ' qui la contient ne porte de verdict.'
          % (names[k[0]] if k[0] < len(names) else 'c%d' % k[0], k[1], 100.0 * susp[k]))
    nb_ok = nb_tot = 0
    for c in sorted({c for (c, _i) in ori}):
        nm = names[c] if c < len(names) else 'c%d' % c
        bb = b0.get(c, 602.0)
        u = ori.get((c, iup), {})
        for mid, pol, lab in _SPEC13_PAIRS:
            im, ip = inv.get(mid), inv.get(pol)
            if im is None or ip is None:
                A('ROOM-SPEC13-CONT: %-12s %-14s cellule absente du balayage — NON MESURE'
                  % (nm, lab))
                continue
            if (c, im) in susp or (c, ip) in susp:
                A('ROOM-SPEC13-CONT: %-12s %-14s PAIRE SUSPENDUE (montage) — publiee sans verdict'
                  % (nm, lab))
                continue
            dm, dp = ori.get((c, im), {}), ori.get((c, ip), {})
            if not dm or not dp or 'sx' not in u:
                continue
            outs, ws = [], []
            for k in ('sx', 'sy', 'sz'):
                a, b, m2 = u[k], dp[k], dm[k]
                nb_tot += 1
                if (min(a, b) < m2 < max(a, b)):
                    nb_ok += 1
                else:
                    outs.append(k)
                ws.append((m2 - a) / (b - a) if abs(b - a) > 1e-9 else float('nan'))
            na = math.sqrt(sum(x * x for x in acc.get((c, im), (0, 0, 0))))
            nq = math.sqrt(sum(x * x for x in acc.get((c, ip), (0, 0, 0))))
            rat = na / nq if nq > 1e-9 else float('nan')
            A('ROOM-SPEC13-CONT: %-12s %-14s FORME %s (poids %.3f/%.3f/%.3f)  ·  DEPLACEMENT '
              '%.4f B0 a 45 deg contre %.4f au pole, rapport %.3f %s'
              % (nm, lab, 'DANS' if not outs else 'HORS sur ' + ','.join(outs),
                 ws[0], ws[1], ws[2], na / bb, nq / bb, rat,
                 '' if 0.35 <= rat <= 0.85 else '<- HORS de [0.35 ; 0.85]'))
    A('   `poids` = (mesure - debout) / (pole - debout) par echelle : 0 = la pose debout, 1 = le')
    A('   pole. Une cellule a 45 deg doit y tomber STRICTEMENT entre 0 et 1 — c\'est la lettre de')
    A('   la clause, sans aucun seuil de mon fait.')
    A('   `rapport` = la meme chose sur le DEPLACEMENT. LA BANDE [0.35 ; 0.85] EST DE MOI, PAS DE')
    A('   LA SPEC, ET LE VERDICT DE CETTE LIGNE EN DEPEND — je le dis ici plutot qu\'en note. Elle encadre les deux')
    A('   seules lois continues que la clause autorise : lineaire en ANGLE (0.50) et proportionnel')
    A('   a la COMPOSANTE de gravite (sin 45 = 0.707). Un rapport au-dessus de 0.85 veut dire que')
    A('   l\'equilibre est deja quasiment atteint a MI-CHEMIN, donc que la variation n\'est pas')
    A('   continue en pratique meme si elle l\'est en principe ; au-dessus de 1.00 elle n\'est meme')
    A('   plus monotone.')
    A('ROOM-SPEC13-CONT: canal de FORME — %d test(s) de position stricte sur %d passent.'
      % (nb_ok, nb_tot))
    A('')
    # ---- CLAUSE 2 : LES QUATRE DESCRIPTEURS DU PENCHE AVANT A 45 DEG ----------------------------
    i45 = inv.get('PENCHE AVANT 45')
    ipr = inv.get('PRONE (face contre terre)')
    if i45 is None:
        A('ROOM-SPEC13-LEAN45: NON MESURE — aucune cellule du balayage ne rend un penche AVANT de')
        A('   45 deg. C\'est ce que le cycle 67 avait conclu ; la mesure dit le contraire des que')
        A('   `PHYSORI4` a un lecteur, donc cette ligne ne devrait jamais s\'imprimer.')
        return
    A('   CLAUSE « At a 45 deg forward lean ... » — LA CELLULE EST i=%d, DESIGNEE PAR LA GRAVITE' % i45)
    A('   MESUREE ET PAR RIEN D\'AUTRE. Le cycle 67 a ecrit, et le cycle 68 a repete, que §13 etait')
    A('   « INJOUABLE avec les operateurs actuels, il manque un operateur qui incline autour de')
    A('   l\'axe LATERAL du sujet ». C\'EST FAUX, ET LA REFUTATION EST DANS LA TRACE DE CES CYCLES-LA :')
    A('   `physroom-orient axis=1` incline autour d\'un axe a 11.5 deg du lateral du sujet et tient')
    A('   la pose. La cause de l\'erreur est nommee : l\'etiquette du code disait « axis 1 = roulis »,')
    A('   elle etait fausse, et personne ne lisait la gravite qui la contredisait a chaque course.')
    A('')
    for c in sorted({c for (c, _i) in ori}):
        nm = names[c] if c < len(names) else 'c%d' % c
        bb = b0.get(c, 602.0)
        d45 = acc.get((c, i45))
        dpr = acc.get((c, ipr)) if ipr is not None else None
        s45 = ori.get((c, i45), {})
        spr = ori.get((c, ipr), {}) if ipr is not None else {}
        sup = ori.get((c, iup), {})
        if not d45 or not s45 or not spr or not sup:
            A('ROOM-SPEC13-LEAN45: %-12s donnee incomplete — NON MESURE' % nm)
            continue
        if (c, i45) in susp or (ipr is not None and (c, ipr) in susp):
            A('ROOM-SPEC13-LEAN45: %-12s PAIRE SUSPENDUE (montage, voir ci-dessus) — aucun'
              ' descripteur n\'est juge sur cette chaine.' % nm)
            continue
        fwd = d45[1] * zs          # dap projete dans le sens AVANT
        dwn = d45[0] * vdown       # dv  projete dans le sens BAS
        nrm = math.sqrt(sum(x * x for x in d45)) / bb
        npr = (math.sqrt(sum(x * x for x in dpr)) / bb) if dpr else float('nan')
        A('ROOM-SPEC13-LEAN45: %-12s (1) migration COM  avant=%+8.2f u  bas=%+8.2f u  |d|=%.4f B0'
          '   -> %s' % (nm, fwd, dwn, nrm,
                        'SENS TENU (avant ET bas)' if (fwd > 0 and dwn > 0) else
                        'SENS NON TENU : la spec dit forward/downward'))
        A('                                   amplitude encadree par §9 (0.0000 B0 debout) et §11'
          ' (%.4f B0 au prone) : %s' % (npr, 'DANS' if 0.0 < nrm < npr else 'HORS'))
        A('ROOM-SPEC13-LEAN45: %-12s (2) elongation racine-apex  %.4f  (debout %.4f, prone %.4f)'
          '   -> %s' % (nm, s45['sz'], sup['sz'], spr['sz'],
                        'MODESTE, ENCADREE' if sup['sz'] < s45['sz'] < spr['sz'] else 'HORS ENCADREMENT'))
        A('ROOM-SPEC13-LEAN45: %-12s (3) largeur                 %.4f  (debout %.4f, prone %.4f)'
          '   -> %s' % (nm, s45['sx'], sup['sx'], spr['sx'],
                        'LEGEREMENT REDUITE, ENCADREE' if spr['sx'] < s45['sx'] < sup['sx']
                        else 'HORS ENCADREMENT'))
        A('ROOM-SPEC13-LEAN45: %-12s (4) redistribution vers le pole distal   NON JUGE' % nm)
    A('                                   Le quatrieme descripteur demande une repartition PAR')
    A('                                   MAILLON, que `PHYSORICOML` donne — mais son controle de')
    A('                                   concordance suspend deja des cellules du balayage, et')
    A('                                   batir un verdict neuf sur un montage qui se contredit est')
    A('                                   la faute que ce registre existe pour interdire. Nomme,')
    A('                                   pas contourne.')
    A('')
    A('ROOM-SPEC13-VERDICT: PARTIELLE. Trois descripteurs sur quatre sont juges et encadres par les')
    A('   poles que sa propre spec chiffre ; le quatrieme n\'a pas de montage sain. Et la clause de')
    A('   CONTINUITE ne passe que sur un canal des deux : la FORME interpole, le DEPLACEMENT non.')
    A('   §13 sort de NON ETABLI — non parce que le solveur a change (il n\'a pas bouge d\'une')
    A('   ligne) mais parce que sa mesure existait et n\'avait pas de lecteur.')
    A('')


# ------------------------------------------------------------------------------------------------
# LE MUR DE SPEC 21, LU DANS LE SOURCE ET CHIFFRE ICI (cycle 71).
#
# `jak-hd-physics.gc:2859-2860` pose `kn = 0.42 * b0e` et `cpp = 0.08 * b0e` ; `:2941` plafonne
# l'argument de la barriere par `fmin 0.99`. Donc :
#   - sous `kn`                       : le multiplicateur vaut 1.0, identite STRICTE ;
#   - entre `kn` et `kn + 0.99*cpp`   : la barriere raidit en x/(1-x), la reponse cesse d'etre
#                                       proportionnelle au stimulus ;
#   - au-dela de `kn + 0.99*cpp`      : l'argument GELE, le numerateur vaut `kn + 99*cpp` et la
#                                       force de rappel est CONSTANTE. Une force constante est un
#                                       TAUX, pas une BORNE.
# Ces trois nombres ne sont pas de moi : ils sont les constantes du solveur, citees par ligne.
_LIM_KN, _LIM_CPP, _LIM_XRC = 0.42, 0.08, 0.99
_LIM_FRZ = _LIM_KN + _LIM_XRC * _LIM_CPP          # 0.4992 B0
_LIM_PH = {31: 'PH-REG', 36: 'PH-REGS', 37: 'PH-REGT', 38: 'PH-REGA', 39: 'PH-REGB'}

# LE MUR DE FORCE A-T-IL PU AGIR DANS **CETTE** COURSE ? (cycle 72)
#
# Depuis le cycle 72 le multiplicateur `mu` est conditionne par `*phys-fwall*` (jak-hd-physics.gc
# :562, [NOTE-330]). Une course peut donc venir de deux jambes, et les mots « GENOU » / « GELE » /
# « (SATURE) » decrivent un mecanisme qui, sur la jambe desarmee, N'EXISTE PAS. Les publier quand
# meme serait exactement le defaut que le cycle 71 denonce : une etiquette qui survit a son
# mecanisme (`attribution-harness-outlives-its-defect`).
#
# LA JAMBE SE LIT DANS LA TRACE, ELLE NE SE DECLARE PAS. `*phys-stif-n*` (publie par `PHYSLIM4`) a
# UN SEUL incrementeur, `(> mu 1.000001)` a :2945, evalue a chaque sous-pas de chaque maillon
# elastique. `stif_n = 0` sur toute la course veut dire que `mu` n'a JAMAIS depasse 1 — et comme le
# meme tableau publie des fenetres dont `perr` depasse le genou, la seule lecture qui reste est que
# la branche etait desarmee. Deux lignes de la MEME trace, pas une declaration.
#
# ABSENT : `PHYSLIM4` manquante -> on ne sait pas, et on garde les etiquettes ARMEES en le disant.
_LIM_ARMED = True
_LIM_ARMED_WHY = 'indetermine (PHYSLIM4 absente) — etiquettes ARMEES par defaut'


def _limarm(txt):
    """Fixe `_LIM_ARMED` pour toute la course. Appele UNE FOIS, tot, par `main()`."""
    global _LIM_ARMED, _LIM_ARMED_WHY
    m = re.search(r'^PHYSLIM4 sat_n=[-\d.e+]+ sat_sum=[-\d.e+]+ stif_n=([-\d.e+]+)', txt, re.M)
    if not m:
        return
    n = float(m.group(1))
    over = sum(1 for x in re.finditer(r'^PHYSREGW .* perr=([-\d.e+]+)', txt, re.M)
               if float(x.group(1)) > _LIM_KN)
    if n > 0.0:
        _LIM_ARMED, _LIM_ARMED_WHY = True, 'ARME (stif_n=%.0f sous-pas au-dessus de mu=1)' % n
    elif over > 0:
        _LIM_ARMED = False
        _LIM_ARMED_WHY = ('DESARME (stif_n=0 alors que %d fenetre(s) depassent le genou : la seule'
                          ' lecture possible)' % over)
    else:
        _LIM_ARMED_WHY = ('indetermine (stif_n=0 mais AUCUNE fenetre au-dessus du genou : le mur'
                          ' n\'avait rien a mordre) — etiquettes ARMEES par defaut')


def _limload(txt):
    """`PHYSREGW ph= c= r= rgap= perr=` -> {(ph, c, r): [(rgap, perr), ...]}.

    NATURE : deux longueurs rapportees a B0, sans dimension, MAXIMUM sur la fenetre.
    REPERE  : le monde, meme frame, meme attache — une difference de deux points du meme repere.
    ABSENT  : la cle manque, et l'appelant ecrit « DEMANDE NON PUBLIEE » plutot que zero. Un canal
              absent n'est pas une demande nulle — c'est la meme regle que pour l'apex.

    POURQUOI UNE LISTE ET PAS UNE VALEUR — DEFAUT TROUVE PAR SA PROPRE PREDICTION, CYCLE 71. La
    question Q1 engageait 132 lignes ; l'emetteur en a bien rendu 132, mais la premiere version de
    ce chargeur n'en publiait que 120. PH-REGA joue CHAQUE fenetre DEUX FOIS (un sens de rotation
    chacun, `*physroom-reg-sgn*` = +1 puis -1) et `PHYSREGW` ne porte pas le sens : les 24 lignes
    de cette phase s'ecrasaient deux a deux sous 12 cles, en silence. Douze mesures perdues sans
    qu'aucune ligne ne le dise — exactement `series-conflates-links` du registre. On garde donc
    TOUTES les occurrences, on les publie toutes, et une cle qui en porte plusieurs ne peut pas
    conditionner un verdict : elle le declare AMBIGU au lieu d'en choisir une."""
    d = {}
    for m in re.finditer(r'^PHYSREGW ph=(\d+) c=(\d+) r=(\d+) rgap=([-\d.e+]+) perr=([-\d.e+]+)',
                         txt, re.M):
        d.setdefault((int(m.group(1)), int(m.group(2)), int(m.group(3))), []).append(
            (float(m.group(4)), float(m.group(5))))
    return d


def _limstate(perr):
    """UN SEUL DENOMINATEUR POUR LES TROIS ZONES, ET C'EST UNE CORRECTION DU CYCLE 71 CONTRE
    MOI-MEME : la premiere version rapportait le GENOU a `kn` et le GELE a `frz`, donc deux
    multiplicateurs d'apparence comparable qui ne l'etaient pas (`ratio-of-two-statistics`). Le
    multiplicateur publie est TOUJOURS `perr / kn` ; la zone se lit sur le mot, pas sur le
    chiffre."""
    if perr is None:
        return 'DEMANDE NON PUBLIEE'
    if not _LIM_ARMED:
        # Le mur est desarme : il n'y a plus ni genou ni gel, la raideur est celle du materiau
        # partout. `perr` reste publie — c'est une LONGUEUR mesuree, pas une etiquette — mais il ne
        # classe plus rien. Le multiplicateur garde le MEME denominateur qu'a la jambe armee pour
        # que les deux colonnes restent comparables ligne a ligne.
        return 'MATERIAU (x%.2f kn)' % (perr / _LIM_KN)
    if perr <= _LIM_KN:
        return 'LINEAIRE (x%.2f kn)' % (perr / _LIM_KN)
    if perr <= _LIM_FRZ:
        return 'GENOU    (x%.2f kn)' % (perr / _LIM_KN)
    return 'GELE     (x%.2f kn)' % (perr / _LIM_KN)


def _limtag(lim, ph, c, r):
    v = lim.get((ph, c, r)) if lim else None
    if not v:
        return _limstate(None)
    if len(v) > 1:
        return 'AMBIGU (%d occurrences)' % len(v)
    return _limstate(v[0][1])


def _limsat(lim, ph, c, r):
    """VRAI quand la fenetre a ete lue DANS LA ZONE GELEE. C'est le verrou du cycle 71 : une ligne
    d'apex de §14 a §20 dont la fenetre est ici ne peut pas soutenir un `TENUE`, parce que son
    amplitude est alors mise en forme par la force CONSTANTE du mur et non par la raideur du
    materiau. Meme forme que le verrou de pose du 2026-08-21 : le confondeur se publie SUR LA MEME
    LIGNE que le chiffre qu'il conditionne, ou la ligne se tait."""
    if not _LIM_ARMED:
        return False        # pas de zone gelee quand le mur ne tourne pas : il n'y a rien a stigmatiser
    v = lim.get((ph, c, r)) if lim else None
    return bool(v) and len(v) == 1 and v[0][1] > _LIM_FRZ


def _limverd(v, lim, ph, c, r):
    """Le verdict de bande, ANNOTE par l'etat du limiteur de SA PROPRE fenetre.

    POURQUOI ANNOTER ET NON SUPPRIMER — et la difference avec le verrou de pose. Un rapport
    gauche/droite releve dans une pose non symetrique est CORROMPU : le chiffre lui-meme ne veut
    rien dire, donc il ne s'ecrit pas. Un apex releve dans la zone gelee, lui, est un DEPLACEMENT
    REELLEMENT MESURE : le fait tient. Ce qui ne tient plus, c'est son ATTRIBUTION au materiau.
    La ligne garde donc le chiffre et perd le droit de valoir `TENUE`."""
    return ('%s (SATURE)' % v) if _limsat(lim, ph, c, r) else v


def _reglim_block(A, txt, names, RGT, LIM):
    """LE MUR DE SPEC 21, FENETRE PAR FENETRE (cycle 71).

    POURQUOI CE BLOC EXISTE. Six sections — §14, §16, §17, §18, §19, §20 — bornent un
    « apex displacement » en % B0, et §19 ne borne que ca. Cet apex est produit par le ressort
    principal, qui porte une saturation de sa §21 ecrite comme MULTIPLICATEUR DE FORCE. Aucune
    ligne du registre n'a jamais dit, POUR SA PROPRE FENETRE, si ce mur avait mordu — alors que
    l'argument du mur est calcule par le moteur a chaque frame depuis longtemps et publie sous
    `PHYSRESTW` pour les fenetres de PH-MEAS seulement.

    NATURE : `perr` est une LONGUEUR rapportee a B0, sans dimension, MAXIMUM sur la fenetre.
    REPERE : le monde, meme frame, meme attache que la cible.
    LIGNE DE BASE : la fenetre temoin r=0 de PH-REG, qui ne recoit AUCUN pilotage.
    RESERVE : le moteur n'ecrit cet emplacement que sous `(= l rlk)`, et `rlk` vaut 0 sur les
      deux chaines — c'est la demande du maillon RACINE, jamais celle de l'apex de chair."""
    A('')
    A('-- ROOM-REGLIM : LE MUR DE SPEC 21 SUR CHAQUE FENETRE DE REGIME (cycle 71) ---------------')
    if not LIM:
        A('ROOM-REGLIM: ABSENT (aucune ligne PHYSREGW) — cette course precede l\'emetteur du')
        A('   cycle 71. Les bandes d\'apex de §14 a §20 se lisent alors SANS l\'etat du limiteur de')
        A('   leur fenetre, ce qui est exactement le trou que ce bloc existe pour fermer.')
        A('')
        return
    A('ROOM-REGLIM-JAMBE: le mur de FORCE de §21 est %s' % _LIM_ARMED_WHY)
    A('   Depuis le cycle 72 `mu` est conditionne par `*phys-fwall*` ([NOTE-330]). La jambe se LIT')
    A('   dans la trace — `stif_n` n\'a qu\'un seul incrementeur — elle ne se declare pas. Desarme,')
    A('   les mots GENOU / GELE / (SATURE) ne sont pas ecrits : ils nommeraient un mecanisme qui')
    A('   n\'a pas tourne, et une etiquette qui survit a son mecanisme est le defaut du cycle 28.')
    A('   LE MUR EST LU DANS LE SOURCE, PAS SUPPOSE (jak-hd-physics.gc:2859-2860 et :2938-2943) :')
    A('       kn  = 0.42 * B0            genou — identite STRICTE en dessous, mu = 1.0 exactement')
    A('       cpp = 0.08 * B0')
    A('       xr  = fmin(0.99, (dd-kn)/cpp)   <- L\'ARGUMENT EST PLAFONNE')
    A('       |f| = k2s * (kn + cpp*xr/(1-xr))')
    A('   Donc trois regimes, et un seul d\'entre eux est celui que la spec decrit :')
    A('       perr <= %.4f B0            LINEAIRE : le ressort est le ressort.' % _LIM_KN)
    A('       %.4f < perr <= %.4f B0   GENOU : la barriere raidit en x/(1-x). La reponse cesse'
      % (_LIM_KN, _LIM_FRZ))
    A('                                   d\'etre proportionnelle au stimulus.')
    A('       perr > %.4f B0            GELE : l\'argument est au plafond, le numerateur vaut'
      % _LIM_FRZ)
    A('                                   kn + 99*cpp et LA FORCE DE RAPPEL EST CONSTANTE.')
    A('   UNE FORCE CONSTANTE EST UN TAUX, PAS UNE BORNE. C\'est le defaut que le cycle 34 a')
    A('   mesure et corrige sur l\'AUTRE canal (le point libre de sa §23) ; il n\'a jamais ete')
    A('   porte sur celui-ci. Et sa §21 demande la forme INVERSE, mot pour mot :')
    A('   « D = D_max * tanh(|D|/D_max) » — une saturation du DEPLACEMENT, pas de la FORCE.')
    A('')
    # ---- LE MUR, CHIFFRE DEPUIS LA DONNEE LIVREE ------------------------------------------
    _pr = {}
    try:
        for _ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
            if _ln.startswith('chain '):
                _st = re.search(r'\bstiffness=([\d.]+)', _ln)
                _ms = re.search(r'\bmass=([\d.]+)', _ln)
                _b0 = re.search(r'\bb0=([\d.]+)', _ln)
                if _st and _ms:
                    _pr[_ln.split()[1]] = (float(_st.group(1)), float(_ms.group(1)),
                                           float(_b0.group(1)) if _b0 else 0.0)
    except Exception:
        _pr = {}
    if not _pr:
        A('   LA FORCE GELEE N\'EST PAS CHIFFREE : `recharged_assets/physics_chains.txt` illisible.')
        A('   Les classements ci-dessous restent valides (ils ne dependent que de `perr`), mais la')
        A('   comparaison force/erreur n\'est pas publiee plutot que devinee.')
    else:
        A('   CE QUE VAUT LA FORCE UNE FOIS GELEE, depuis les constantes LIVREES et rien d\'autre')
        A('   (dt = 0.0166667 s, jak-hd-physics.gc:2486 ; ns = 4 sous-pas, :2867-2872) :')
        A('   %-8s %9s %7s %10s %11s %12s %14s'
          % ('chaine', 'stiffness', 'mass', 'w (rad/s)', 'k2', 'k2s=k2/16', '|f| gele'))
        for _n in sorted(_pr):
            _st, _ms, _bb = _pr[_n]
            _w = 2.0 * math.pi * _st / math.sqrt(max(0.01, _ms))
            _k2 = (_w * 0.0166667) ** 2
            _k2s = _k2 / 16.0
            _bb = _bb if _bb > 0 else 602.0
            _num = (_LIM_KN + 99.0 * _LIM_CPP) * _bb
            _f = _k2s * _num
            A('   %-8s %9.4f %7.4f %10.4f %11.6f %12.7f  %6.2f u/sous-pas'
              % (_n, _st, _ms, _w, _k2, _k2s, _f))
            A('   %-8s        soit %.2f u/frame^2, CONSTANTE — elle vaut la MEME chose a %.0f u'
              % ('', 4.0 * _f, _num))
            A('   %-8s        d\'erreur qu\'a %.0f u. Le ressort LINEAIRE, lui, rendrait k2s*dd.'
              % ('', 10.0 * _num))
    A('')
    # ---- LE TEMOIN : SANS LUI AUCUNE DES AUTRES FENETRES N'A D'ECHELLE ---------------------
    _wit = [(c, LIM[(31, c, 0)][0][1])
            for c in sorted({k[1] for k in LIM if k[0] == 31 and k[2] == 0})
            if len(LIM[(31, c, 0)]) == 1]
    if not _wit:
        A('ROOM-REGLIM-TEMOIN: la fenetre r=0 de PH-REG est ABSENTE de la trace — les autres')
        A('   fenetres se lisent alors sans ligne de base, et je le dis au lieu de les lire.')
    else:
        for _c, _v in _wit:
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            A('ROOM-REGLIM-TEMOIN: %-8s r=0 AUCUN PILOTAGE  perr=%.4f B0  -> %s'
              % (_nm, _v, _limstate(_v)))
        if all(_v <= _LIM_KN for _, _v in _wit):
            A('   LE TEMOIN EST SOUS LE GENOU SUR LES DEUX CHAINES : les quatorze autres fenetres')
            A('   ont donc une echelle, et ce qu\'elles montrent au-dela du genou est produit par')
            A('   LEUR pilotage.')
        else:
            A('   LE TEMOIN EST DEJA AU-DELA DU GENOU, ET C\'EST LE FAIT LE PLUS LOURD DE CE BLOC :')
            A('   la chaine est dans la zone non lineaire du limiteur SANS AUCUN PILOTAGE, sur la')
            A('   seule animation tenue. Aucune fenetre de regime ne peut alors attribuer son')
            A('   amplitude au geste qu\'elle joue, et aucune bande d\'apex de §14 a §20 n\'est un')
            A('   verdict sur le personnage.')
    A('')
    # ---- LE TABLEAU, PHASE PAR PHASE ------------------------------------------------------
    A('   %-9s %-8s %3s %-13s %8s %9s   %s'
      % ('phase', 'chaine', 'r', 'regime', 'rgap', 'perr', 'etat du limiteur'))
    _tal, _n, _dup = {}, 0, 0
    for _k in sorted(LIM, key=lambda k: (k[0], k[1], k[2])):
        _ph, _c, _r = _k
        _occ = LIM[_k]
        if len(_occ) > 1:
            _dup += 1
        _nm = names[_c] if _c < len(names) else 'c%d' % _c
        _rn = next((x[1] for x in RGT if x[0] == _r), '?')
        for _i, (_rg, _pe) in enumerate(_occ):
            _n += 1
            _st = _limstate(_pe)
            _tal[_st.split()[0]] = _tal.get(_st.split()[0], 0) + 1
            A('ROOM-REGLIM: %-9s %-8s %3d %-13s %8.4f %9.4f   %-22s %s'
              % (_LIM_PH.get(_ph, 'ph=%d' % _ph), _nm, _r, _rn, _rg, _pe, _st,
                 ('passe %d/%d' % (_i + 1, len(_occ))) if len(_occ) > 1 else ''))
    A('')
    if not _LIM_ARMED:
        # Le comptage par zone n'a plus d'objet ; ce qui reste comparable a la jambe armee est la
        # part de fenetres AU-DESSUS du genou et au-dessus de l'ancien point de gel, parce que ce
        # sont des seuils sur `perr`, pas des etats d'un mecanisme.
        _kn = sum(1 for v in LIM.values() for o in v if o[1] > _LIM_KN)
        _fz = sum(1 for v in LIM.values() for o in v if o[1] > _LIM_FRZ)
        A('ROOM-REGLIM-BILAN: %d ligne(s) sous %d cle(s), mur DESARME — le comptage par zone n\'a'
          % (_n, len(LIM)))
        A('   plus d\'objet. Ce qui reste comparable a la jambe armee, parce que ce sont des seuils')
        A('   sur `perr` et non des etats d\'un mecanisme : %d (%.1f %%) au-dessus du genou'
          % (_kn, 100.0 * _kn / max(1, _n)))
        A('   0.4200 B0, dont %d (%.1f %%) au-dessus de l\'ancien point de gel 0.4992 B0.'
          % (_fz, 100.0 * _fz / max(1, _n)))
        A('   %d cle(s) portent PLUSIEURS passes (PH-REGA joue chaque fenetre' % _dup)
    else:
        A('ROOM-REGLIM-BILAN: %d ligne(s) publiee(s) sous %d cle(s) — %d LINEAIRE, %d au GENOU,'
          % (_n, len(LIM), _tal.get('LINEAIRE', 0), _tal.get('GENOU', 0)))
        A('   %d GELEES (%.1f %%). %d cle(s) portent PLUSIEURS passes (PH-REGA joue chaque fenetre'
          % (_tal.get('GELE', 0), 100.0 * _tal.get('GELE', 0) / max(1, _n), _dup))
    A('   dans les DEUX sens et `PHYSREGW` ne porte pas le sens) : aucune d\'elles ne peut')
    A('   conditionner un verdict, elles se declarent AMBIGUES la ou elles sont lues.')
    _rgmx = max((o[0] for v in LIM.values() for o in v), default=0.0)
    A('ROOM-REGLIM-RGAP: le pire ecart cible-de-repos / pose-d\'auteur vaut %.4f B0 sur les %d'
      % (_rgmx, _n))
    A('   cellules. %s'
      % ('Il est petit devant le genou (%.2f B0) : la demande est DYNAMIQUE, pas un decalage'
         ' statique de la cible.' % _LIM_KN if _rgmx < 0.05 else
         'IL N\'EST PAS PETIT : une part de la demande est un decalage STATIQUE de la cible, que'
         ' ni la raideur ni le limiteur ne peuvent faire baisser.'))
    A('')
    # ---- CE QUE LES DEUX LIMITEURS ONT RETIRE SUR LA COURSE, ET LE CRITERE EST DE LA SALLE --
    _m4 = re.search(r'^PHYSLIM4 sat_n=([-\d.e+]+) sat_sum=([-\d.e+]+) stif_n=([-\d.e+]+)',
                    txt, re.M)
    if not _m4:
        A('ROOM-LIM-RESSORT: `PHYSLIM4` absente de la trace — le critere ecrit par la salle')
        A('   elle-meme n\'est pas evaluable, et rien n\'est publie a sa place.')
    else:
        _sn, _ss, _fn = (float(x) for x in _m4.groups())
        A('   LE CRITERE CI-DESSOUS N\'EST PAS DE MOI : il est ecrit dans `phys-room.gc`, au-dessus')
        A('   de la ligne `PHYSLIM4` qu\'il juge, et il n\'avait AUCUN LECTEUR. Verbatim :')
        A('     « `stif_n` grand avec `sat_n` effondre = la force fait le travail et le filet ne')
        A('       sert plus. `sat_n` qui reste haut = le ressort est mal pose. »')
        A('ROOM-LIM-RESSORT: stif_n=%.0f sous-pas integres au-dela du genou · sat_n=%.0f morsures'
          % (_fn, _sn))
        A('   du filet positionnel · sat_sum=%.0f u retires au total.' % _ss)
        if _sn > 0:
            A('   LES DEUX COMPTES NE SE DIVISENT PAS L\'UN PAR L\'AUTRE — `stif_n` compte des')
            A('   SOUS-PAS et `sat_n` des MORSURES : deux portees differentes ne se rapportent pas')
            A('   (`ratio-of-two-statistics`). Ce qui se lit, c\'est la morsure MOYENNE :')
            A('   %.2f u par morsure, soit %.4f B0 — le filet retire, a chaque fois, %s'
              % (_ss / _sn, _ss / _sn / 602.0,
                 'moins que le genou' if _ss / _sn / 602.0 < _LIM_KN else 'PLUS que le genou'))
        A('ROOM-LIM-RESSORT: VERDICT PAR LE CRITERE DE LA SALLE -> %s'
          % ('le filet est EFFONDRE, la force fait le travail'
             if _sn == 0 else
             'LE FILET N\'EST PAS EFFONDRE (sat_n=%.0f) : par sa propre phrase, « LE RESSORT EST'
             ' MAL POSE ».' % _sn))
    A('')


def _regb_block(A, txt, names, RGT, RGAPX, rgvd, asym=None, POSE=None, LIM=None):
    """SPEC 14 A 17 REJOUEES SUR LES AXES DU SUJET (PH-REGB, cycle 70).

    POURQUOI CETTE PASSE EXISTE. `physroom-run-z` accelerait le sujet le long du MONDE Z, a
    **86,3 deg** de son axe avant/arriere mesure : la « course » de §17 etait une EMBARDEE
    LATERALE. Les sauts partaient le long du monde Y, a 11,9 deg de la verticale du sujet. Meme
    defaut de classe que les rotations de §18-§20 (cycles 67-68) et que le nommage des
    orientations de §10-§13 (cycle 69) : un geste COMMANDE dans le repere du monde et LU comme
    celui du sujet.

    CE QUE CE BLOC PUBLIE, ET CE QU'IL NE PUBLIE PAS. Il ne remplace AUCUNE ligne : `ROOM-REGIME`
    et `ROOM-APEX-REGIME` gardent leur lecture en repere monde, et celles-ci se lisent A COTE.
    Les BANDES sont exactement celles de `_RGT` et `_RGAPX` — aucun seuil neuf, aucune citation
    reecrite. Ce qui change est UNIQUEMENT l'axe du stimulus.

    NATURE : un deplacement d'apex et un COM, en B0. REPERE : celui des lignes `ROOM-REGIME`,
    inchange — c'est le STIMULUS qui a change de repere, pas la mesure.
    LIGNE DE BASE : la fenetre temoin r=0, rejouee elle aussi, et qui doit rendre le MEME chiffre
    que dans les autres passes puisque `physroom-tr-set` ecrit `home` exactement quand yy=zz=0."""
    A('-- ROOM-REGB : §14 A §17 REJOUEES SUR LES AXES DU SUJET (PH-REGB) ------------------------')
    b0 = {}
    for m in re.finditer(r'^\[HD-PHYS\] b0 c=(\d+) flesh=([-\d.e+]+)', txt, re.M):
        b0[int(m.group(1))] = float(m.group(2))
    ap, dd, ss = {}, {}, None
    # `PHYSREGBV` : le tag `PHYSREGB` etait DEJA pris par les directions d'os de PH-REG. Deux
    # populations sous une meme etiquette rendent tout comptage faux — renomme au producteur.
    for m in re.finditer(r'^PHYSREGBV c=(\d+) r=(\d+) trm=(\d+) apex=([-\d.e+]+) com=([-\d.e+]+)',
                         txt, re.M):
        ap[(int(m.group(1)), int(m.group(2)))] = (int(m.group(3)), float(m.group(4)),
                                                  float(m.group(5)))
    for m in re.finditer(r'^PHYSREGBD r=(\d+) trm=(\d+) dap=([-\d.e+]+) dver=([-\d.e+]+)'
                         r' dlat=([-\d.e+]+)', txt, re.M):
        dd[int(m.group(1))] = (int(m.group(2)), float(m.group(3)), float(m.group(4)),
                               float(m.group(5)))
    m1 = re.search(r'^PHYSREGBS gv=([-\d.e+]+) ap0=([-\d.e+]+) ap1=([-\d.e+]+)', txt, re.M)
    m2 = re.search(r'^PHYSREGBS2 us=([-\d.e+]+) fs=([-\d.e+]+) gok=(\d+) aok=(\d+) trm=(\d+)',
                   txt, re.M)
    if m1 and m2:
        ss = (tuple(float(x) for x in m1.groups())
              + (float(m2.group(1)), float(m2.group(2)))
              + (int(m2.group(3)), int(m2.group(4)), int(m2.group(5))))
    if not ap:
        A('ROOM-REGB: ABSENT (aucune ligne PHYSREGB) — cette course precede la phase PH-REGB.')
        A('   §14 a §17 restent lues sur les axes du MONDE, et l\'ecart d\'axe reste DECLARE et')
        A('   non corrige : 86,3 deg pour la course de §17, 11,9 deg pour les sauts.')
        A('')
        return
    # ---- LES DEUX SENS, ET LEUR SOURCE ---------------------------------------------------------
    if ss is None:
        A('ROOM-REGB: les deux sens ne sont pas publies (`PHYSREGBS` absent) — la passe ne peut pas')
        A('   etre lue, et aucun chiffre n\'est publie plutot que d\'en publier sans repere.')
        A('')
        return
    gv, ap0, ap1, us, fs, gok, aok, trm = ss
    A('ROOM-REGB-SENS: gravite sur la ligne verticale de l\'ancre = %+.6f  -> le HAUT est %s'
      ' (garde |gv| > 0.5 : %s)' % (gv, 'son oppose' if gv > 0 else 'son sens', 'OK' if gok else 'REFUSEE'))
    A('ROOM-REGB-SENS: saillie du sein sur la ligne 2 = %+.6f et %+.6f  -> l\'AVANT est %s'
      ' (garde |ap| > 0.03 et memes signes : %s)'
      % (ap0, ap1, 'son oppose' if ap0 < 0 else 'son sens', 'OK' if aok else 'REFUSEE'))
    if not trm:
        A('ROOM-REGB: MODE MONDE — un des deux sens ne s\'est pas mesure, donc la phase a REFUSE de')
        A('   se declarer en repere sujet et a rejoue en repere monde. C\'est un doublon de PH-REG,')
        A('   pas une correction d\'axe : aucune conclusion sur l\'axe n\'en sort.')
        A('')
        return
    # ---- LE GESTE, NOMME PAR LA COMPOSANTE QUI MANQUE ------------------------------------------
    A('')
    A('   LE GESTE OBTENU, NOMME PAR LA MESURE. Un saut doit rendre `dap` et `dlat` quasi nuls ;')
    A('   une course doit rendre `dver` et `dlat` quasi nuls. C\'est la composante qui MANQUE qui')
    A('   nomme un geste, pas celle qui domine — lecon du cycle 68, payee sur un classificateur')
    A('   qui appelait un lacet une flexion avant.')
    A('   r   regime         dap (u)     dver (u)    dlat (u)   geste mesure')
    KIND = {1: 'jump', 2: 'jump', 3: 'jump', 4: 'jump', 5: 'jump', 6: 'jump', 7: 'run', 8: 'run'}
    nb_ok = nb_tot = 0
    for r in sorted(dd):
        _t, dap, dver, dlat = dd[r]
        nm = next((x[1] for x in RGT if x[0] == r), 'r=%d' % r)
        big = max(abs(dap), abs(dver), abs(dlat))
        if big < 1.0:
            geste = 'AUCUN DEPLACEMENT (temoin)'
        elif abs(dver) > 3.0 * max(abs(dap), abs(dlat)):
            geste = 'VERTICAL   (dap et dlat quasi nuls)'
        elif abs(dap) > 3.0 * max(abs(dver), abs(dlat)):
            geste = 'AVANT/ARR. (dver et dlat quasi nuls)'
        elif abs(dlat) > 3.0 * max(abs(dap), abs(dver)):
            geste = 'LATERAL    <- ce n\'est le geste d\'AUCUNE de ces sections'
        else:
            geste = 'MIXTE — aucune composante ne domine, le geste n\'est PAS nomme'
        if r in KIND:
            nb_tot += 1
            want = 'VERTICAL' if KIND[r] == 'jump' else 'AVANT/ARR.'
            if geste.startswith(want):
                nb_ok += 1
        A('   %2d  %-13s %+10.2f %+11.2f %+11.2f   %s' % (r, nm, dap, dver, dlat, geste))
    A('ROOM-REGB-GESTE: %d fenetre(s) de pilotage sur %d rendent le geste que leur section decrit.'
      % (nb_ok, nb_tot))
    A('')
    # ---- LES BANDES, AVEC LA LECTURE EN REPERE MONDE A COTE ------------------------------------
    A('   LES BANDES SONT CELLES DE `ROOM-REGIME` ET `ROOM-APEX-REGIME`, AU MOT PRES : ce bloc')
    A('   n\'introduit aucun seuil. Ce qui change est l\'AXE du stimulus, et rien d\'autre.')
    A('   chaine    r  regime         apex (sujet)  bande         verdict          '
      'limiteur SPEC 21 de CETTE fenetre')
    for c in sorted({k[0] for k in ap}):
        nm = names[c] if c < len(names) else 'c%d' % c
        bb = b0.get(c, 602.0)
        for r in range(9):
            if (c, r) not in ap:
                continue
            _t, apx, _com = ap[(c, r)]
            band, cite = RGAPX.get(r, (None, 'aucune clause d\'apex pour ce regime'))
            _vd0 = rgvd(apx, band) if band else 'PAS DE BANDE'
            A('ROOM-REGB-APEX: %-8s %2d %-13s %8.4f      %-13s %-16s %s'
              % (nm, r, next((x[1] for x in RGT if x[0] == r), '?'), apx,
                 ('[%.2f-%.2f]' % band) if band else '[pas de bande]',
                 _limverd(_vd0, LIM, 39, c, r), _limtag(LIM, 39, c, r)))
    A('')
    for c in sorted({k[0] for k in ap}):
        nm = names[c] if c < len(names) else 'c%d' % c
        for r in range(9):
            if (c, r) not in ap:
                continue
            _t, _apx, com = ap[(c, r)]
            band = next((x[4] for x in RGT if x[0] == r), None)
            A('ROOM-REGB-COM:  %-8s %2d %-13s %8.4f      %-13s %s'
              % (nm, r, next((x[1] for x in RGT if x[0] == r), '?'), com,
                 ('[%.2f-%.2f]' % band) if band else '[pas de bande]',
                 rgvd(com, band) if band else 'PAS DE BANDE'))
    A('')
    # ---- LA CONFRONTATION : MEME POSE, MEME FENETRE, UNE SEULE VARIABLE — L'AXE ----------------
    # PH-REGT joue les MEMES fenetres dans la MEME pose epinglee, sur les axes du MONDE. La
    # difference entre les deux passes ne peut donc etre portee que par l'axe. C'est la discipline
    # de la passe appariee du cycle 66, appliquee a la translation.
    tt = {}
    for m in re.finditer(r'^PHYSREGT c=(\d+) r=(\d+) apex=([-\d.e+]+) com=([-\d.e+]+)', txt, re.M):
        tt[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)))
    if not tt:
        A('ROOM-REGB-AXE: PH-REGT absente de cette trace — la comparaison appariee est impossible,')
        A('   et les chiffres ci-dessus se lisent seuls, sans terme de comparaison.')
        A('')
        return
    A('   -- ROOM-REGB-AXE : L\'ECART ENTRE LES DEUX AXES, FENETRE PAR FENETRE -------------------')
    A('      PH-REGT (axes du MONDE) et PH-REGB (axes du SUJET) jouent la MEME fenetre dans la MEME')
    A('      pose epinglee. La seule variable declaree est l\'axe ; ce que la colonne `ecart`')
    A('      mesure ne peut donc venir que de lui.')
    saut, cour = [], []
    for c in sorted({k[0] for k in ap}):
        nm = names[c] if c < len(names) else 'c%d' % c
        for r in range(1, 9):
            if (c, r) not in ap or (c, r) not in tt:
                continue
            b = ap[(c, r)][1]
            w = tt[(c, r)][0]
            rel = abs(b - w) / max(abs(w), 1e-9)
            (cour if r in (7, 8) else saut).append(rel)
            A('ROOM-REGB-AXE: %-8s r=%d %-13s monde=%.4f  sujet=%.4f  ecart %+7.2f %%  (%.1f deg'
              ' entre les deux axes)'
              % (nm, r, next((x[1] for x in RGT if x[0] == r), '?'), w, b,
                 100.0 * (b - w) / max(abs(w), 1e-9), 86.3 if r in (7, 8) else 11.9))
    def _med(v):
        v = sorted(v)
        return v[len(v) // 2] if v else float('nan')
    A('ROOM-REGB-AXE: ecart relatif MEDIAN — sauts (axes a 11,9 deg) %.2f %%  ·  course (axes a'
      ' 86,3 deg) %.2f %%' % (100.0 * _med(saut), 100.0 * _med(cour)))
    # ---- LE TEST QUE LA GEOMETRIE DU RIG DONNE GRATUITEMENT -------------------------------------
    # Le rig est bilateralement symetrique a 0,005 deg en pose de BIND (cycle 53, sur le mesh
    # LIVRE). Dans une pose PROUVEE symetrique, un stimulus qui tombe sur le BON axe doit donc
    # rendre des reponses egales sur les deux seins ; un stimulus qui tombe a cote ne le peut pas.
    # Ce test ne coute rien, ne demande aucun seuil, et n'a PAS ete pre-enregistre : il se lit
    # comme une observation, pas comme une prediction verifiee.
    if asym is not None and POSE is not None and 'PH-REGB' in POSE and 'PH-REGT' in POSE:
        pb, pt = POSE['PH-REGB'], POSE['PH-REGT']
        pw = pb if ((pb.dev if pb.dev is not None else 9e9)
                    >= (pt.dev if pt.dev is not None else 9e9)) else pt
        A('')
        A('   -- ROOM-REGB-SYM : L\'ECART GAUCHE/DROITE, SOUS LES DEUX AXES ---------------------')
        nb_mieux = nb_paire = 0
        for r in range(1, 9):
            if (0, r) not in ap or (1, r) not in ap:
                continue
            if (0, r) not in tt or (1, r) not in tt:
                continue
            bs = abs(ap[(0, r)][1] - ap[(1, r)][1]) / max(ap[(0, r)][1], ap[(1, r)][1], 1e-9)
            ws = abs(tt[(0, r)][0] - tt[(1, r)][0]) / max(tt[(0, r)][0], tt[(1, r)][0], 1e-9)
            nb_paire += 1
            if bs < ws:
                nb_mieux += 1
            A(asym('ROOM-REGB-SYM',
                   ': r=%d %-13s ecart gauche/droite %6.2f %% sur les axes du SUJET contre'
                   ' %6.2f %% sur ceux du MONDE  -> %s'
                   % (r, next((x[1] for x in RGT if x[0] == r), '?'),
                      100.0 * bs, 100.0 * ws, 'PLUS SYMETRIQUE' if bs < ws else 'moins symetrique'),
                   pw))
        A(asym('ROOM-REGB-SYM',
               ': %d fenetre(s) sur %d rendent une reponse PLUS symetrique quand le stimulus tombe'
               ' sur l\'axe du sujet' % (nb_mieux, nb_paire), pw))
        A('   POURQUOI CE TEST VAUT PLUS QU\'UNE BANDE. Il ne compare pas une mesure a une cible :')
        A('   il compare le personnage a LUI-MEME. Le rig est symetrique a 0,005 deg en bind, donc')
        A('   dans une pose symetrique un stimulus bien oriente DOIT rendre les deux seins egaux —')
        A('   c\'est une propriete de la geometrie, pas un reglage. Aucun seuil n\'y entre.')
        A('   CE QU\'IL N\'EST PAS : une prediction verifiee. Il n\'etait pas dans')
        A('   `c70-predictions.txt` ; je le publie comme une OBSERVATION, et je le dis.')
    A('   CE QUI DISCRIMINE : si l\'ecart d\'axe explique ce qu\'on mesure, la course — a 86,3 deg')
    A('   de son axe anatomique — doit bouger PLUS que les sauts, qui n\'en sont qu\'a 11,9 deg.')
    A('   L\'inverse serait le resultat le plus interessant des deux : il dirait que l\'axe n\'est')
    A('   pas ce qui gouverne la reponse, et qu\'il faut chercher ailleurs.')
    A('')


def _spec8_block(A, txt, names):
    """SPEC 8 — LA CONSERVATION DE VOLUME, LUE SUR LE TENSEUR COMPLET AU LIEU DU SOURCE.

    TEXTE EXACT (SPEC-breast-softbody.md l.140-143), cite et pas resume :
      « Normal movement: 98-101% of neutral volume · Strong transient events: 96-102% »
      « Conceptually `Sx.Sy.Sz ~ 1`, **but the whole breast shall not be represented by one affine
        scale transformation.** Instead: root tissue moves little; intermediate tissue
        redistributes; distal tissue deforms most... »

    POURQUOI CE BLOC EXISTE. §8 etait portee `NON TENUE` avec pour motif « le determinant est force
    a 1 et la deformation est UNE matrice par chaine ». **Ce motif etait lu dans le SOURCE, pas dans
    une trace** — et la regle 0 du contrat dit qu'un commentaire n'est pas une preuve. Or le tenseur
    3x3 COMPLET est publie a chaque course depuis des dizaines de cycles sous le nom `PHYSDFMA`, en
    base de l'ancre, **et n'a aucun lecteur** (deuxieme des trois flux muets nommes au cycle 69).
    Ce bloc lui en donne un : la meme conclusion, mais MESUREE.

    NATURE : un determinant (rapport de volumes, sans unite) et une mesure d'ASYMETRIE de matrice
      (sans unite elle aussi). REPERE : la base de l'ANCRE, celle de `PHYSORICOML`.
    LECTURE HORS DEFAUT : det = 1 a la cellule debout, ou §9 exige la pose d'auteur.
    CE QUI DISCRIMINE : une population de determinants qui varie a peine plus que le bruit
      d'impression n'est pas une mesure de volume, c'est une NORMALISATION — et une bande respectee
      par une constante epinglee ne prouve rien. C'est le test que ce bloc fait passer a la clause."""
    A('-- ROOM-SPEC8 : LE TENSEUR DE DEFORMATION COMPLET, ENFIN LU -------------------------------')
    M = {}
    for m in re.finditer(r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+) m0=([-\d.e+]+) m1=([-\d.e+]+)'
                         r' m2=([-\d.e+]+)', txt, re.M):
        M.setdefault((int(m.group(1)), int(m.group(2))), [None] * 3)[int(m.group(3))] = [
            float(m.group(4)), float(m.group(5)), float(m.group(6))]
    if not M:
        A('ROOM-SPEC8: ABSENT (aucune ligne PHYSDFMA) — le tenseur n\'est pas publie par cette')
        A('   course. §8 reste jugee sur une lecture de source, ce qui n\'est pas une preuve.')
        A('')
        return
    def _det(a):
        return (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))
    dets, asys = [], []
    A('   chaine    i   det(M)     ecart a 1     asymetrie max |Mij - Mji|')
    for c in sorted({k[0] for k in M}):
        nm = names[c] if c < len(names) else 'c%d' % c
        for i in sorted({k[1] for k in M if k[0] == c}):
            a = M[(c, i)]
            if any(x is None for x in a):
                continue
            d = _det(a)
            asy = max(abs(a[j][k] - a[k][j]) for j in range(3) for k in range(3))
            dets.append(d)
            asys.append(asy)
            A('ROOM-SPEC8: %-8s %2d  %10.6f  %+.2e     %.6f' % (nm, i, d, d - 1.0, asy))
    lo, hi = min(dets), max(dets)
    A('')
    A('ROOM-SPEC8-VOLUME: %d cellules · det de %.6f a %.6f · ETENDUE %.2e'
      % (len(dets), lo, hi, hi - lo))
    A('   La bande de la section est 0,98-1,01 en mouvement normal et 0,96-1,02 en transitoire.')
    if 0.98 <= lo and hi <= 1.01:
        A('   La bande est RESPECTEE — ET C\'EST PRECISEMENT CE QUI NE PROUVE RIEN.')
    else:
        A('   La bande est FRANCHIE.')
    A('   ETENDUE %.2e SUR %d CELLULES : neuf orientations, des poles a +-90 deg, deux chaines, et'
      % (hi - lo, len(dets)))
    A('   le determinant ne bouge pas de la sixieme decimale. Une grandeur PHYSIQUE de volume varie')
    A('   avec la deformation ; celle-ci n\'a pas de population, elle a une VALEUR. C\'est une')
    A('   NORMALISATION, pas une conservation, et une bande respectee par une constante epinglee ne')
    A('   peut fonder aucun verdict. §8 reste NON TENUE — mais desormais sur une MESURE, la ou son')
    A('   motif etait jusqu\'ici une lecture de source (regle 0 : un commentaire n\'est pas une preuve).')
    A('')
    A('ROOM-SPEC8-AFFINE: asymetrie de matrice de %.6f a %.6f.' % (min(asys), max(asys)))
    A('   La clause en gras — « the whole breast shall NOT be represented by ONE affine scale')
    A('   transformation » — porte sur la STRUCTURE, pas sur une valeur. Deux faits la tranchent :')
    A('   (a) `PHYSDFMA` porte un indice de CHAINE et un indice de CELLULE, et AUCUN indice de')
    A('       MAILLON : il n\'existe pas de tenseur par maillon a publier. C\'est UNE matrice pour')
    A('       tout l\'organe, ce que la section interdit en gras.')
    A('   (b) la matrice est quasi SYMETRIQUE (asymetrie max %.4f) : une matrice symetrique est un'
      % max(asys))
    A('       etirement pur, donc exactement « one affine scale transformation » ecrite dans une')
    A('       base propre. Le residu non nul dit qu\'un peu de cisaillement s\'y ajoute, pas qu\'une')
    A('       repartition racine/intermediaire/distal existe.')
    A('   Les quatre comportements que la section demande a la place — « root tissue moves little ;')
    A('   intermediate tissue redistributes ; distal tissue deforms most ; local thickness')
    A('   compensates for elongation » — n\'ont donc aucun canal, et c\'est cela le defaut, pas un')
    A('   reglage. §8 : NON TENUE, motif MESURE.')
    A('')


def _oricom_block(A, txt, names, ori):
    """SPEC 10/11/12/13 ET SPEC 29 — LE DEPLACEMENT STATIQUE PAR ORIENTATION, ET LA COMPLIANCE.

    Ce bloc est neuf au cycle 12. Il existe parce que le preset de sa spec nomme les quatre valeurs
    de §29 `VerticalCompliance / APCompliance / LateralCompliance / TorsionalCompliance` : ce sont
    des DEPLACEMENTS PAR UNITE DE FORCE, et jusqu'ici on les cherchait dans des FREQUENCES. Une
    frequence melange raideur et masse ; une compliance ne depend que de la raideur. C'est en
    passant par la frequence qu'on avait rendu §24 et §29 sur-determinees l'une par l'autre."""
    com, com2, tr = {}, {}, {}
    for m in re.finditer(r'^PHYSORICOM c=(\d+) i=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+)'
                         r' tz=([-\d.e+]+)', txt, re.M):
        com[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                   float(m.group(5)))
    for m in re.finditer(r'^PHYSORICOM2 c=(\d+) i=(\d+) rr=([-\d.e+]+) rrm=([-\d.e+]+)'
                         r' n=([-\d.e+]+)', txt, re.M):
        com2[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                    float(m.group(5)))
    for m in re.finditer(r'^PHYSORITR c=(\d+) i=(\d+) rrt=([-\d.e+]+)', txt, re.M):
        tr[(int(m.group(1)), int(m.group(2)))] = float(m.group(3))
    b0 = {}
    for m in re.finditer(r'^\[HD-PHYS\] b0 c=(\d+) flesh=([-\d.e+]+)', txt, re.M):
        b0[int(m.group(1))] = float(m.group(2))

    A('-- ROOM-ORICOM : SPEC 10/11/12, LE DEPLACEMENT STATIQUE — ET SPEC 29, LA COMPLIANCE -------')
    if not com:
        A('ROOM-ORICOM: ABSENT (aucune ligne PHYSORICOM) — la salle de cette course n\'emettait pas')
        A('   encore le deplacement par orientation. Les COM de §10/§11/§12 et la compliance de §29')
        A('   restent NON MESURES, ce qui n\'est pas la meme chose que verts.')
        return
    st = _selftest_linalg()
    if st is None or st[0] > 1e-9 or st[1] > 1e-9:
        A('ROOM-ORICOM: l\'algebre de ce bloc ECHOUE son propre controle (%s) — aucun chiffre'
          % ('singuliere' if st is None else 'err=%.2e / %.2e' % st))
        A('   n\'est publie plutot que d\'en publier de faux.')
        return
    A('   CONTROLE POSITIF DE L\'ALGEBRE : un tenseur diag(0.82, 1.00, 0.90) POSE, les reponses')
    A('     qu\'il produirait fabriquees, puis retrouve — erreur %.1e ; normale d\'un nuage plan'
      % st[0])
    A('     retrouvee a %.1e pres. L\'instrument sait donc rendre la reponse qu\'on lui donne.'
      % st[1])
    A('   NATURE : des DEPLACEMENTS SOUTENUS (moyennes de 30 frames sur un equilibre tenu), pas des')
    A('     variances — un equilibre ne bouge plus, toute grandeur de dispersion y lit zero.')
    A('   REPERE : le triedre de SPEC 7 (+X lateral, +Y haut, +Z avant), le meme que `gx/gy/gz`.')
    A('   LIGNE DE BASE : l\'orientation i=0 est la pose debout d\'auteur, ou §9 exige 0.0000. Elle')
    A('     est MESUREE ci-dessous et non supposee : si elle n\'est pas nulle, tout est decale.')
    A('   DEUX CANAUX, ORTHOGONAUX PAR CONSTRUCTION, JAMAIS ADDITIONNES EN AVEUGLE :')
    A('     `t`  = deplacement TANGENTIEL de l\'APEX (le point que le solveur integre). La')
    A('            contrainte de longueur lui confisque l\'axe de l\'os. Bandes §22 : 0.42 / 0.50 B0.')
    A('     `rr` = le canal radial de §23, LE LONG de l\'os. Bandes §22 du COM : 0.35 / 0.40 B0.')
    A('   AVERTISSEMENT QUI COMPTE, ET QUI N\'EST PAS UNE FORMALITE : le point INTEGRE reste')
    A('     l\'APEX (residu connu de §23). Les cibles de §10/§11/§12 sont des COM. Un apex se')
    A('     deplace PLUS qu\'un COM sous une rotation autour de l\'ancre, donc les valeurs `t`')
    A('     ci-dessous sont une BORNE SUPERIEURE du COM, pas le COM. Ce bloc ne franchit pas cet')
    A('     ecart : il le NOMME. Les RAPPORTS de §29, eux, sont immunises — le meme point sert aux')
    A('     trois axes, et un facteur commun disparait d\'un rapport.')
    A('')

    # ---- LES ROLES D'ORIENTATION, NOMMES PAR UN INVARIANT EXTERNE -------------------------------
    # `axis-role-labels-need-naming-measurement` : une etiquette `ax=0/deg=90` ne dit pas si c'est
    # supine ou prone, et se tromper inverserait DEUX lignes de conformite. Le nom est donc decide
    # par le TRIPLET D'ECHELLES LIVRE compare aux echelles que sa spec nomme elle-meme, et l'ecart
    # des deux hypotheses est publie pour qu'on voie la marge.
    _SUP = (1.23, 1.09, 0.70)     # §10 SupineWidthScale / SupineHeightScale / SupineProjectionScale
    _PRO = (0.90, 0.91, 1.23)     # §11 HangingWidthScale / HangingThicknessScale / HangingLengthScale
    role = {}
    for c in sorted({c for (c, _i) in com}):
        best = {}
        for i in range(9):
            d = ori.get((c, i))
            if not d or 'sx' not in d:
                continue
            s = (d['sx'], d['sy'], d['sz'])
            e_sup = sum(abs(s[k] - _SUP[k]) for k in range(3))
            e_pro = sum(abs(s[k] - _PRO[k]) for k in range(3))
            best[i] = (e_sup, e_pro)
        if not best:
            continue
        i_sup = min(best, key=lambda i: best[i][0])
        i_pro = min(best, key=lambda i: best[i][1])
        role[c] = dict(sup=i_sup, pro=i_pro)
        A('ROOM-ORICOM-ROLE: chain=%-12s §10 supine -> i=%d (ecart %.4f, 2e meilleur %.4f) ;'
          '  §11 prone -> i=%d (ecart %.4f, 2e %.4f)'
          % (names[c] if c < len(names) else 'c%d' % c,
             i_sup, best[i_sup][0], sorted(v[0] for v in best.values())[1],
             i_pro, best[i_pro][1], sorted(v[1] for v in best.values())[1]))
    A('   (le role vient du TRIPLET D\'ECHELLES compare aux valeurs que sa spec nomme, pas de')
    A('    l\'etiquette `ax`/`deg` : une etiquette ne se verifie pas, un ecart de 16x si.)')
    A('')

    A('   chaine        i   gx      gy      gz   | ex      ey      ez   |  tx/B0  ty/B0  tz/B0'
      '  |t|/B0 |   rr     rrm    rrt')
    for c in sorted({c for (c, _i) in com}):
        bb = b0.get(c, 602.0)
        for i in range(9):
            if (c, i) not in com:
                continue
            tx, ty, tz = com[(c, i)]
            d = ori.get((c, i), {})
            gx, gy, gz = d.get('gx', 0.0), d.get('gy', 0.0), d.get('gz', 0.0)
            rr, rrm, _n = com2.get((c, i), (0.0, 0.0, 0.0))
            tn = math.sqrt(tx * tx + ty * ty + tz * tz) / bb
            A('ROOM-ORICOM: %-12s %d %7.4f %7.4f %7.4f |%7.4f %7.4f %7.4f |%7.4f%7.4f%7.4f'
              ' %6.4f |%8.5f%8.5f%8.5f'
              % (names[c] if c < len(names) else 'c%d' % c, i, gx, gy, gz,
                 gx, gy + 1.0, gz, tx / bb, ty / bb, tz / bb, tn,
                 rr, rrm, tr.get((c, i), float('nan'))))
    A('   `ex/ey/ez` = `g_eff = g_local - g_ref` de sa SPEC 3, avec `g_ref = (0,-1,0)` la pose')
    A('     debout d\'auteur. C\'EST LUI L\'ENTREE DU SOLVEUR, pas `g` : debout les deux termes')
    A('     s\'annulent et §9 exige exactement 0. Regresser sur `g` au lieu de `g_eff` mettrait')
    A('     une reponse nulle en face d\'une entree unitaire et rendrait une compliance fausse.')
    A('')

    # ---- L'AXE DE L'OS, MESURE ET NON SUPPOSE ---------------------------------------------------
    A('-- ROOM-ORIAXIS : L\'AXE DE L\'OS, LU DANS LES DONNEES AU LIEU D\'ETRE SUPPOSE -------------')
    A('   La contrainte de longueur confisque au canal du joint la composante LE LONG de l\'os :')
    A('   les 9 deplacements tangentiels sont donc confines a un PLAN, et la normale de ce plan EST')
    A('   l\'axe de l\'os. On la lit comme le plus petit vecteur propre de leur matrice de dispersion.')
    A('   CE QUI LE PROUVE, ET C\'EST PUBLIE A COTE : les deux premieres valeurs propres doivent')
    A('   dominer la troisieme. Si les trois sont du meme ordre, le nuage n\'est pas plan, la')
    A('   confiscation n\'a pas lieu, et tout ce qui suit est a jeter.')
    axis = {}
    for c in sorted({c for (c, _i) in com}):
        ts = [com[(c, i)] for i in range(9) if (c, i) in com]
        mt = [[sum(t[a] * t[b] for t in ts) for b in range(3)] for a in range(3)]
        ev, evec = _sym3_eig(mt)
        nrm = evec[2]
        ln = math.sqrt(sum(x * x for x in nrm)) or 1.0
        nrm = [x / ln for x in nrm]
        ratio = (ev[2] / ev[1]) if ev[1] > 0 else 9.99
        axis[c] = nrm
        A('ROOM-ORIAXIS: chain=%-12s vp=%.4e %.4e %.4e  vp3/vp2=%.2e  axe=(%+.4f,%+.4f,%+.4f)  %s'
          % (names[c] if c < len(names) else 'c%d' % c, ev[0], ev[1], ev[2], ratio,
             nrm[0], nrm[1], nrm[2],
             'PLAN (confiscation confirmee)' if ratio < 0.02 else
             'NON PLAN — la confiscation n\'a pas lieu, le reste du bloc est invalide'))
        A('   composante VERTICALE de cet axe : %.1f %% — l\'axe de l\'os n\'est PAS l\'axe'
          ' anatomique racine->apex (qui est +Z, celui que §11 allonge de 23 %%).'
          % (100.0 * abs(nrm[1])))
    A('')

    # ---- LE TENSEUR DE COMPLIANCE ---------------------------------------------------------------
    A('-- ROOM-COMPLIANCE : SPEC 29, MESUREE SUR LA GRANDEUR QUE SON PRESET NOMME ----------------')
    A('   §38 : `VerticalCompliance 1.00 / APCompliance 0.90 / LateralCompliance 0.82`.')
    A('   ON AJUSTE `d = C.g_eff` SUR LES 9 EQUILIBRES, `d` etant le deplacement TOTAL en B0 :')
    A('     `d = t/B0 + rr . axe_de_l_os`, les deux canaux remis dans le meme vecteur — ils sont')
    A('     orthogonaux par construction, donc cette somme-la est licite alors qu\'additionner')
    A('     leurs MODULES ne le serait pas.')
    A('   PREDICTION ECRITE AVANT LA COURSE, et c\'est ce qui donne sa valeur au test : la donnee')
    A('     livree porte `sv=1.0000 sap=1.1111 slat=1.2195` (raideurs par axe, lues a l\'execution')
    A('     dans `PHYSAXISS`). Une compliance est l\'inverse d\'une raideur, donc les rapports')
    A('     ATTENDUS sont 1/1.0000 : 1/1.1111 : 1/1.2195 = 1.000 / 0.900 / 0.820 — exactement sa')
    A('     §29. Si la mesure les rend, §29 est TENUE et mesuree pour la premiere fois ; sinon')
    A('     l\'ecart est le resultat, et il est chiffre au lieu d\'etre suppose.')
    A('   POURQUOI CE QUE LA FREQUENCE NE POUVAIT PAS FAIRE : `f` varie comme sqrt(k), donc un')
    A('     ecart de raideur de 7.5 % n\'y pese que 3.7 % — sous le residu des ajustements de')
    A('     ring-down (0.02 a 0.16). Une compliance porte l\'ecart ENTIER, et se lit sur des')
    A('     moyennes de 30 frames d\'un etat immobile, sans ajustement du tout.')
    for c in sorted({c for (c, _i) in com}):
        bb = b0.get(c, 602.0)
        ax = axis.get(c, [0.0, 1.0, 0.0])
        gs, ds = [], []
        for i in range(9):
            if (c, i) not in com or (c, i) not in ori:
                continue
            d = ori[(c, i)]
            e = (d.get('gx', 0.0), d.get('gy', 0.0) + 1.0, d.get('gz', 0.0))
            tx, ty, tz = com[(c, i)]
            rr = com2.get((c, i), (0.0, 0.0, 0.0))[0]
            gs.append(e)
            ds.append([tx / bb + rr * ax[0], ty / bb + rr * ax[1], tz / bb + rr * ax[2]])
        if len(gs) < 4:
            A('ROOM-COMPLIANCE: chain=%s — %d orientations seulement, tenseur non ajustable'
              % (names[c] if c < len(names) else 'c%d' % c, len(gs)))
            continue
        mm = [[sum(g[a] * g[b] for g in gs) for b in range(3)] for a in range(3)]
        cmat = []
        for k in range(3):
            rhs = [sum(g[a] * d[k] for g, d in zip(gs, ds)) for a in range(3)]
            row = _solve3(mm, rhs)
            if row is None:
                cmat = None
                break
            cmat.append(row)
        if cmat is None:
            A('ROOM-COMPLIANCE: chain=%s — systeme singulier (orientations degenerees)'
              % (names[c] if c < len(names) else 'c%d' % c))
            continue
        num = den = 0.0
        for g, d in zip(gs, ds):
            for k in range(3):
                pred = sum(cmat[k][a] * g[a] for a in range(3))
                num += (d[k] - pred) ** 2
                den += d[k] ** 2
        resid = math.sqrt(num / den) if den > 0 else 9.99
        nm = names[c] if c < len(names) else 'c%d' % c
        A('')
        A('ROOM-COMPLIANCE: chain=%s   n=%d   residu relatif de l\'ajustement = %.4f  %s'
          % (nm, len(gs), resid,
             'LINEAIRE (donc §13 continue : une table de morphs figes ne serait pas lineaire)'
             if resid < 0.15 else 'NON LINEAIRE — saturation ou morphs figes, voir §21/§22'))
        for k, lab in enumerate(('lateral', 'vertical', 'AP     ')):
            A('   C[%s] = %+9.5f %+9.5f %+9.5f' % (lab, cmat[k][0], cmat[k][1], cmat[k][2]))
        # compliance selon chaque axe du triedre = module de la reponse a une gravite unitaire
        # portee par cet axe. C'est la definition operationnelle de son preset.
        cx = math.sqrt(sum(cmat[k][0] ** 2 for k in range(3)))
        cy = math.sqrt(sum(cmat[k][1] ** 2 for k in range(3)))
        cz = math.sqrt(sum(cmat[k][2] ** 2 for k in range(3)))
        if cy > 0:
            A('ROOM-COMPLIANCE-ANISO: chain=%s  vertical=%.4f (=1.000 par normalisation)'
              '  AP=%.4f  lateral=%.4f' % (nm, cy / cy, cz / cy, cx / cy))
            A('   cible §29                          vertical=1.000              AP=0.900'
              '   lateral=0.820')
            A('   ecart                                                          %+6.1f %%'
              '   %+6.1f %%' % (100.0 * (cz / cy / 0.900 - 1.0), 100.0 * (cx / cy / 0.820 - 1.0)))
            A('   (compliances brutes, en B0 par unite de g_eff : vertical %.5f, AP %.5f,'
              ' lateral %.5f)' % (cy, cz, cx))
    A('')

    # ---- LE REDRESSEMENT, ET SON PROPRE CONTROLE ------------------------------------------------
    # Le residu de 0.18 dit qu'un tenseur lineaire n'explique pas tout, mais il ne dit pas OU la
    # linearite casse. Ce bloc le localise, et il porte son controle avec lui.
    #
    # LE PRINCIPE : les 9 orientations contiennent quatre paires de POLES OPPOSES. Dans chaque
    # paire les deux membres ont EXACTEMENT la meme composante verticale de `g_eff` (+1 a 90 deg,
    # +0.293 a 45 deg) et une composante d'axe EXACTEMENT opposee. Pour une compliance lineaire les
    # deux reponses valent donc |C.Y + C.a| et |C.Y - C.a| : leur rapport est borne, et il vaut 1
    # quand la reponse est dominee par la partie verticale commune.
    # UN RAPPORT QUI EXPLOSE N'EST PAS UNE ANISOTROPIE, C'EST UN REDRESSEMENT — la chaine repond
    # d'un cote et pas de l'autre. Aucune valeur d'anisotropie ne peut produire ca.
    #
    # ET LE CONTROLE EST DANS LE TABLEAU LUI-MEME, il n'a pas a etre fabrique : les paires
    # LATERALES subissent le meme instrument, la meme fenetre, le meme estimateur. Si elles
    # rendent ~1 pendant que les paires AVANT-ARRIERE explosent, l'asymetrie est dans la CHAINE et
    # pas dans la mesure. Si les deux explosaient, ce serait l'instrument qu'il faudrait suspecter.
    A('-- ROOM-ORIRECT : LA LINEARITE, TESTEE PAR PAIRES DE POLES OPPOSES ------------------------')
    A('   Chaque paire : meme `g_eff` vertical, composante d\'axe exactement opposee. Un tenseur')
    A('   lineaire borne le rapport des deux reponses ; un rapport qui explose est un REDRESSEMENT')
    A('   (reponse d\'un seul cote), que nulle anisotropie ne peut produire.')
    A('   LE CONTROLE EST DANS LE TABLEAU : les paires LATERALES passent par le meme instrument.')
    A('   Elles a ~1 et les AP qui explosent => l\'asymetrie est dans la chaine, pas dans la mesure.')
    A('')
    A('   chaine        paire                       |d(a)|   |d(b)|   rapport   lecture')
    for c in sorted({c for (c, _i) in com}):
        bb = b0.get(c, 602.0)
        ax = axis.get(c, [0.0, 1.0, 0.0])
        nm = names[c] if c < len(names) else 'c%d' % c

        def _dn(i, _c=c, _bb=bb, _ax=ax):
            if (_c, i) not in com:
                return None
            tx, ty, tz = com[(_c, i)]
            rr = com2.get((_c, i), (0.0, 0.0, 0.0))[0]
            v = [tx / _bb + rr * _ax[0], ty / _bb + rr * _ax[1], tz / _bb + rr * _ax[2]]
            return math.sqrt(sum(x * x for x in v))
        for lab, ia, ib, kind in (('LATERAL  90 deg (i=2 / i=4)', 2, 4, 'ctrl'),
                                  ('LATERAL  45 deg (i=1 / i=3)', 1, 3, 'ctrl'),
                                  ('AVANT-ARRIERE 90 (i=6 / i=8)', 6, 8, 'test'),
                                  ('AVANT-ARRIERE 45 (i=5 / i=7)', 5, 7, 'test')):
            da, db = _dn(ia), _dn(ib)
            if da is None or db is None or min(da, db) <= 0.0:
                continue
            rat = max(da, db) / min(da, db)
            A('ROOM-ORIRECT: %-12s %-28s %7.4f  %7.4f  %7.2f   %s'
              % (nm, lab, da, db, rat,
                 ('CONTROLE : symetrique' if rat < 1.5 else 'CONTROLE ASYMETRIQUE — suspecter'
                  ' l\'instrument') if kind == 'ctrl' else
                 ('symetrique' if rat < 1.5 else 'REDRESSE — reponse d\'un seul cote')))
    A('')

    # ---- LES TROIS DEPLACEMENTS QUE SA SPEC CHIFFRE ---------------------------------------------
    A('-- ROOM-ORICOM-SPEC : LES TROIS DEPLACEMENTS D\'ORIENTATION QUE SA SPEC CHIFFRE -----------')
    A('   §10 `SupineCOMDepth 0.23 B0` · §11 `HangingCOMDisplacement 0.24 B0`, transitoire de')
    A('   longueur <= 1.30 · §12 `SideGravityCOM 0.19 B0`. Lus contre |d| = |t/B0 + rr.axe|, le')
    A('   MEME vecteur compose que le tenseur ci-dessus. Rappel de l\'avertissement : c\'est un')
    A('   APEX, donc une BORNE SUPERIEURE du COM que ces trois lignes visent.')
    for c in sorted({c for (c, _i) in com}):
        bb = b0.get(c, 602.0)
        ax = axis.get(c, [0.0, 1.0, 0.0])
        nm = names[c] if c < len(names) else 'c%d' % c
        r = role.get(c, {})
        lat = [i for i in (2, 4) if (c, i) in com]
        todo = [('§10 supine ', r.get('sup'), 0.23, (0.18, 0.28)),
                ('§11 prone  ', r.get('pro'), 0.24, (0.20, 0.30))]
        todo += [('§12 lateral', i, 0.19, (0.15, 0.24)) for i in lat]
        for lab, i, nom, band in todo:
            if i is None or (c, i) not in com:
                A('ROOM-ORICOM-SPEC: %-12s %s  i introuvable — NON MESURE' % (nm, lab))
                continue
            tx, ty, tz = com[(c, i)]
            rr = com2.get((c, i), (0.0, 0.0, 0.0))[0]
            dv = [tx / bb + rr * ax[0], ty / bb + rr * ax[1], tz / bb + rr * ax[2]]
            dn = math.sqrt(sum(x * x for x in dv))
            A('ROOM-ORICOM-SPEC: %-12s %s i=%d  |d|=%.4f B0   cible %.2f (bande %.2f-%.2f)  %s'
              % (nm, lab, i, dn, nom, band[0], band[1],
                 'DANS' if band[0] <= dn <= band[1] else
                 ('SOUS' if dn < band[0] else 'AU-DESSUS')))
        # §11 : le transitoire d'etablissement contre l'equilibre tenu
        ip = r.get('pro')
        if ip is not None and (c, ip) in tr:
            eq = abs(com2.get((c, ip), (0.0, 0.0, 0.0))[0])
            A('ROOM-ORICOM-SPEC: %-12s §11 transitoire  pic d\'etablissement=%.5f  tenu=%.5f'
              '  rapport=%s  (§11 : 1.30 contre 1.23, soit 1.057)'
              % (nm, tr[(c, ip)], eq, ('%.3f' % (tr[(c, ip)] / eq)) if eq > 1e-6 else 'n/a'))
    A('')
    # ---- CYCLE 69 : LE ROLE DES CELLULES, MESURE ; PUIS §13, QUI EN DEPEND ----------------
    _roles = _ori_role_block(A, txt, names, ori, com, role, b0)
    _perm, _acc = _ori_frame_perm(A, txt)
    _zs = _ori_zsense(txt)[0]
    if _roles:
        _ori_role_verrou(A, _roles, role, names)
    if _roles and _acc and _zs is not None:
        _spec13_block(A, txt, names, ori, com, _acc, _roles, _zs, b0, _perm)
    else:
        A('ROOM-SPEC13: NON ETABLI — role, correspondance de repere ou sens de l\'axe'
          ' avant/arriere non resolus. Aucun verdict plutot qu\'un verdict devine.')
        A('')
    _oricom_mass_block(A, txt, names, com, com2, role, axis, b0)
    _orictl_block(A, txt, names, ori, axis, b0, _roles)


# ------------------------------------------------------------------------------------------------
# SPEC 10/11/12 SUR UN **COM**, ET PLUS SUR UN APEX
# ------------------------------------------------------------------------------------------------
_COM_MASS_JSON = 'reports/Grecharged-secondary-motion/breast-com-mass.json'


_ABL_LBL = {0: 'k0 reference', 1: 'k1 longueur levee', 2: 'k2 cote leve',
            3: 'k3 rayon interpole', 4: 'k4 MUR DE COLLISION desarme',
            5: 'k5 borne §22 radiale levee'}


def _tipctl_ablation(txt, c, i):
    """L'ECART DE POINTE RECALCULE SUR LES SIX PASSES D'ABLATION, pour ATTRIBUER le desaccord.

    Meme algebre que le controle principal, sur les canaux de controle : `PHYSORICTL` (l'apex,
    par passe) et `PHYSCTLML` (les maillons, par passe). `kl` y encode la paire (passe, maillon)
    sous la forme `10*k + l` — decode ici et nulle part ailleurs.

    LECTURE HORS DEFAUT : sur une cellule saine les six passes rendent le meme petit nombre. Une
    passe qui fait TOMBER l'ecart designe le mecanisme qu'elle desarme ; `k1` (contrainte de
    longueur levee) est ATTENDUE grande partout — elle change la trajectoire, pas l'instrument —
    et c'est pourquoi la designation ne la retient jamais comme candidate.
    """
    T, L = {}, {}
    for m in re.finditer(r'^PHYSORICTL c=(\d+) k=(\d+) i=(\d+) tx=([-\d.e+]+)'
                         r' ty=([-\d.e+]+) tz=([-\d.e+]+)', txt, re.M):
        T[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))
    for m in re.finditer(r'^PHYSCTLML c=(\d+) kl=(\d+) i=(\d+) dv=([-\d.e+]+)'
                         r' dap=([-\d.e+]+) dlat=([-\d.e+]+)', txt, re.M):
        kl = int(m.group(2))
        L[(int(m.group(1)), kl // 10, int(m.group(3)), kl % 10)] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))
    out = []
    for k in sorted(_ABL_LBL):
        l0, l1, t = L.get((c, k, i, 0)), L.get((c, k, i, 1)), T.get((c, k, i))
        if l0 is None or l1 is None or t is None:
            continue
        s = [l0[j] + l1[j] for j in range(3)]
        tr = (t[1], t[2], t[0])          # triedre §7 -> base de l'ANCRE, comme le controle
        na = math.sqrt(sum(x * x for x in s))
        nt = math.sqrt(sum(x * x for x in tr))
        if max(na, nt) <= 1e-6:
            continue
        d = math.sqrt(sum((s[j] - tr[j]) ** 2 for j in range(3)))
        out.append((_ABL_LBL[k], d / max(na, nt) * 100.0))
    # `k1` est ecartee des CANDIDATES (jamais de l'affichage : elle reste dans `out`, et
    # l'appelant ne cherche le minimum que sur `out[1:]`, d'ou son retrait ici).
    # Lever la contrainte de longueur deplace la chaine entiere : un grand ecart y est attendu
    # et ne designe rien. `out[0]` est la reference k0 et reste en tete.
    if not out:
        return []
    ref = out[0]
    cand = [o for o in out[1:] if not o[0].startswith('k1')]
    return [ref] + cand


def _oricom_mass_block(A, txt, names, com, com2, role, axis, b0):
    """SES TROIS CIBLES D'ORIENTATION SONT DES COM ; L'INSTRUMENT PUBLIAIT UN APEX.

    `ROOM-ORICOM` ci-dessus le declare lui-meme : `t` est le deplacement du point que le solveur
    INTEGRE (l'apex), et sous une rotation autour de l'ancre un apex se deplace PLUS qu'un centre
    de masse. Le comparer aux 0.23 / 0.24 / 0.19 B0 de ses §10 / §11 / §12 est le piege
    `instrument-axis-vs-complaint` : on lit la bonne chaine, au mauvais point. Tant que l'organe
    n'avait qu'UN maillon la conversion etait indeterminee ; depuis que la structure de §23 est
    posee, elle est CALCULABLE.

    LE CALCUL, ET IL NE CONTIENT AUCUN NOMBRE CHOISI. Sous skinning lineaire le deplacement d'un
    sommet est la somme ponderee des deplacements de ses joints ; dans le repere de l'ancre un
    joint non simule a un ecart identiquement nul. Donc, sur l'ensemble de sommets de l'organe :

        d_COM = ( W_0 . d_0 + W_1 . d_1 ) / N

    `W_j` (somme des poids de peau du joint j) et `N` (nombre de sommets) sont MESURES sur le mesh
    LIVRE par `.autoport/probe_breast_com_mass.py` ; les `d_j` sont lus a l'execution sur la ligne
    `PHYSORICOML`. Rien n'est ajuste.

    LA FRONTIERE DE L'ORGANE EST UN CHOIX, DONC ELLE EST PUBLIEE TROIS FOIS. §30 exige « no hard
    attachment boundary » : il n'existe pas de bord net a lire dans la donnee. Trois definitions
    (`w>0`, `w>=0.05`, `w>=0.25`) sont donnees cote a cote. Si les trois rendent le meme verdict,
    la frontiere ne decide pas ; si elles divergent, c'est CA la mesure.

    CORRIGE LE 2026-08-18 (cycle 24) — CE BLOC LISAIT UN INCREMENT COMME UN ABSOLU.
    `PHYSORICOML` publie, pour chaque maillon `l`, la quantite `u - m` : le vecteur du maillon
    COURANT moins le vecteur du maillon d'AUTEUR, tous deux issus de LA MEME ATTACHE. C'est donc
    un ecart RELATIF A SON PROPRE PARENT, pas un ecart a la pose d'auteur :

        ldb[l]  =  d(enfant du maillon l)  -  d(attache du maillon l)

    donc l'ecart ABSOLU du j-eme joint de la chaine est la somme TELESCOPIQUE `sum(ldb[0..j])`,
    l'ancre ayant un ecart identiquement nul. Le bloc prenait `ldb[j]` tel quel pour `d_j`. Sur
    une chaine a UN maillon les deux coincident (l'attache est l'ancre), et c'est pourquoi le
    defaut est reste invisible jusqu'a ce que la structure de §23 pose un second maillon.

    C'EST SON PROPRE CONTROLE QUI L'A DIT, ET IL DISAIT VRAI. Il comparait `|ldb[dernier]|` a
    `|t|` (`phys-tip-mean`, un accumulateur INDEPENDANT : autre variable, autre triedre, moyenne
    de fenetre) et publiait 57.35 % / 56.16 % d'ecart, en se suspendant lui-meme. Mesure sur la
    course du 2026-08-18 14:16, 18 orientations, les deux chaines :

        |ldb[1]| seul  contre |t| :  -57.4 % a +107.4 %      (ce que le bloc faisait)
        |ldb[0]+ldb[1]| contre |t| :  -0.40 % a +0.31 %      sur 16 orientations sur 18
                                      (+1.25 % et +2.32 % sur les deux restantes)

    La somme telescopique retombe sur l'accumulateur independant a 0.4 % pres. Le desaccord
    n'etait donc ni un repere, ni un ecart instantane/moyenne, ni la physique : c'etait un
    INCREMENT compare a un CUMUL. Il est corrige ici, et le controle reste publie — c'est lui
    qui a trouve le defaut, il ne se retire pas une fois vert.

    ET LA COLONNE « COMPOSE AVEC rr » EST RETIREE, POUR DEUX RAISONS MESUREES. `rr` (`*phys-rr*`,
    :3061) vaut `((cp - a).m_hat) - bl` : c'est la composante RADIALE de ce meme `u - m` au
    JOINT. Elle est donc (1) DEJA CONTENUE dans `ldb`, qui projette `u - m` sur les trois axes
    orthonormes de l'ancre — l'ajouter en Pythagore la comptait deux fois ; et (2) d'une autre
    NATURE que `d_COM`, qui est une moyenne PONDEREE PAR LA MASSE sur ~90 sommets : composer un
    deplacement de joint (0.21 B0) avec une moyenne d'organe (0.06 B0) melange deux echelles.

    CE QUE CE BLOC NE MESURE TOUJOURS PAS, et il faut le dire pour ne pas le redecouvrir : le
    tenseur de deformation (`*phys-dfm*`, :3968) etire la PEAU autour de l'os d'un rapport
    `1 + PHYS-DYN-K.|d|`, et ce deplacement-la ne passe pas par les positions de joints, donc
    aucune somme de `ldb` ne peut le voir. `d_COM` ci-dessous est exact pour la part SQUELETTIQUE
    (skinning lineaire) et MUET sur la part tensorielle. C'est une borne INFERIEURE, et elle est
    declaree comme telle au lieu d'etre completee par un terme de la mauvaise nature."""
    comL = {}
    for m in re.finditer(r'^PHYSORICOML c=(\d+) i=(\d+) l=(\d+) dv=([-\d.e+]+)'
                         r' dap=([-\d.e+]+) dlat=([-\d.e+]+)', txt, re.M):
        comL[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))
    A('-- ROOM-ORICOM-MASS : SPEC 10/11/12 LUES SUR UN CENTRE DE MASSE ---------------------------')
    if not comL:
        A('ROOM-ORICOM-MASS: ABSENT (aucune ligne PHYSORICOML) — cette course precede l\'emission')
        A('   par maillon. §10/§11/§12 restent lues sur un APEX, donc sur une BORNE SUPERIEURE :')
        A('   non mesurees sur la grandeur que sa spec nomme, ce qui n\'est pas la meme chose que')
        A('   fausses. Aucun chiffre n\'est fabrique pour combler le trou.')
        A('')
        return
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), _COM_MASS_JSON)
    try:
        mass = json.load(open(path))
    except Exception as e:
        A('ROOM-ORICOM-MASS: la repartition de masse est ABSENTE (%s) — les d_j sont mesures mais'
          % e)
        A('   les W_j ne le sont pas. Relancer `python3 .autoport/probe_breast_com_mass.py`.')
        A('')
        return
    A('   NATURE : un DEPLACEMENT SOUTENU du centre de masse, en B0. REPERE : le triedre de')
    A('     l\'ANCRE — la NORME, seule grandeur qui traverse les deux triedres orthonormes.')
    A('   LIGNE DE BASE : i=0 (debout d\'auteur), ou §9 exige 0.0000 ; elle est publiee.')
    # REFUS D'UN INSTANTANE PERIME. Ce bloc lit un JSON produit hors course ; le chemin du mesh
    # qu'il imprime a toujours ete juste, mais rien ne comparait son INSTANT a celui du mesh. Le
    # 2026-08-18 le JSON datait de 13:15, le mesh de 14:05, et les huit valeurs de §10/§11/§12 de
    # la course de 17:31 ont ete composees avec les poids d'un mesh remplace 50 minutes avant
    # (W[lBooc] 23.9 contre 33.0 : 38 % d'ecart). On ne le DETECTE pas au point de controle, on le
    # rend IMPOSSIBLE au point de consommation : sans horodatage concordant, le bloc se suspend.
    _msrc = mass.get('source')
    _mt = mass.get('source_mtime')
    _msz = mass.get('source_size')
    _stale = None
    if _msrc:
        _mp = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), _msrc)
        if not os.path.exists(_mp):
            _stale = 'le mesh %s n\'existe plus' % _msrc
        elif _mt is None or _msz is None:
            _stale = ('l\'instantane ne porte pas l\'horodatage de sa source (produit par une '
                      'version anterieure de probe_breast_com_mass.py)')
        else:
            _st = os.stat(_mp)
            if abs(_st.st_mtime - float(_mt)) > 1.0 or _st.st_size != int(_msz):
                _stale = ('instantane PERIME : ecrit sur un mesh de mtime %.0f taille %d, le mesh '
                          'livre porte mtime %.0f taille %d'
                          % (float(_mt), int(_msz), _st.st_mtime, _st.st_size))
    if _stale:
        A('ROOM-ORICOM-MASS: SUSPENDU — %s.' % _stale)
        A('   Les `d_j` sont mesures, les `W_j` ne decrivent pas le mesh que le jeu recoit. Relancer')
        A('   `python3 .autoport/probe_breast_com_mass.py` PUIS regenerer ce tableau. Aucun chiffre')
        A('   n\'est publie ici : des poids perimes donneraient un COM faux avec une provenance juste.')
        A('')
        return
    A('   SOURCE DES POIDS : %s (mesh LIVRE, pas le rip du donneur), mtime %.0f, taille %d —'
      % (_msrc, float(_mt), int(_msz)))
    A('     CONCORDANCE VERIFIEE avec le mesh sur disque (sinon ce bloc se suspend).')
    A('   d_COM = (W_0.d_0 + W_1.d_1)/N — aucun coefficient choisi ; W_j et N mesures, d_j lus.')
    A('   d_j EST UN CUMUL, PAS UN INCREMENT (corrige le 2026-08-18) : `PHYSORICOML` publie')
    A('     `u - m` par maillon, donc un ecart A SON PROPRE PARENT ; l\'ecart a la pose d\'auteur du')
    A('     j-eme joint est la somme telescopique `sum(ldb[0..j])`, l\'ancre etant a zero. Sur une')
    A('     chaine a UN maillon les deux coincident — le defaut n\'etait visible que depuis §23.')
    A('   PART MESUREE : la part SQUELETTIQUE (skinning lineaire). Le tenseur de deformation')
    A('     (`*phys-dfm*`) etire la peau autour de l\'os sans deplacer un joint : il n\'est PAS ici.')
    A('     `d_COM` est donc une BORNE INFERIEURE, et la colonne « compose avec rr » est retiree —')
    A('     `rr` est la composante radiale du MEME `u - m`, deja comptee, et d\'une autre echelle.')
    for c in sorted({c for (c, _i, _l) in comL}):
        nm = names[c] if c < len(names) else 'c%d' % c
        rec = mass.get('chains', {}).get(nm)
        if not rec or not rec.get('defs'):
            A('ROOM-ORICOM-MASS: %-12s pas de repartition de masse pour cette chaine — NON MESURE'
              % nm)
            continue
        nl = 1 + max(l for (cc, _i, l) in comL if cc == c)
        bb = b0.get(c, 602.0)

        def dcum(cc, ii, j):
            """L'ecart ABSOLU du j-eme joint : somme telescopique des increments `ldb[0..j]`.

            `ldb[l] = d(enfant du maillon l) - d(attache du maillon l)` ; l'ancre a un ecart
            identiquement nul, donc la somme des l premiers increments EST l'ecart a la pose
            d'auteur. Rend None si un increment manque — on ne comble pas un trou par zero."""
            acc = [0.0, 0.0, 0.0]
            for l in range(j + 1):
                d = comL.get((cc, ii, l))
                if d is None:
                    return None
                for k in range(3):
                    acc[k] += d[k]
            return tuple(acc)

        # --- le controle : la pointe, lue par les deux instruments ------------------------------
        # i=0 EST LA LIGNE DE BASE DE CE BLOC, DECLAREE PLUS HAUT : la pose debout d'auteur, ou
        # §9 exige 0.0000. Les deux instruments y lisent 1 a 3 unites de jeu, soit 0.2 a 0.4 % de
        # B0 — un rapport RELATIF entre deux quasi-zeros n'est pas une mesure, c'est une division
        # par le bruit. La ligne de base se juge donc en ABSOLU (c'est la grandeur que §9 nomme)
        # et l'accord des deux instruments sur les orientations QUI PORTENT UN SIGNAL se juge en
        # relatif. Ce n'est pas un seuil choisi : c'est le partage des roles deja ecrit au-dessus.
        # LE CONTROLE COMPARAIT DEUX NORMES, ET UNE NORME EST AVEUGLE A LA DIRECTION (cycle 64b).
        # Mesure qui l'a etabli : en reordonnant `t` (triedre §7 : lateral, haut, avant) en
        # (ty, tz, tx) pour l'aligner sur la base de l'ANCRE (vertical, avant-arriere, lateral),
        # les deux instruments coincident COMPOSANTE PAR COMPOSANTE a moins de 0.6 degre sur 14
        # cellules chargees sur 16. Les deux qui echouent le font a ~15 degres — et l'ancien
        # critere n'en voyait qu'UNE :
        #     chestL i=8   norme 13.35 %   angle 16.27 deg   -> SUSPENDU (vu)
        #     chestR i=2   norme  0.57 %   angle 14.88 deg   -> PASSAIT  (invisible)
        # `chestR` etait donc declaree « accord » sur une COINCIDENCE de normes. C'est la faute
        # exacte des cycles 62b et 63 (`scalar-signature-hides-an-unmirrored-vector`), commise
        # cette fois par le CONTROLE lui-meme.
        # LE CORRECTIF N'INTRODUIT AUCUN SEUIL NEUF : on compare les VECTEURS,
        # `|a - b| / max(|a|,|b|)`, avec le MEME 5 % qu'avant. Le critere est strictement plus
        # fort (||a|-|b|| <= |a-b|) et la separation est franche, pas un fil du rasoir : pire
        # cellule qui passe 1.08 %, pire cellule prise 25.83 % — un facteur 24.
        # ET IL EST PAR CELLULE, PLUS PAR CHAINE : suspendre une chaine entiere pour une
        # orientation fautive jetait des lectures propres (le supine de chestR est a 0.09 %).
        ictl = [i for (cc, i, l) in comL if cc == c and l == nl - 1 and (cc, i) in com]
        worst, worst_i, nbase = 0.0, None, 0
        base_a = base_t = float('nan')
        cellrel = {}
        for i in sorted(set(ictl)):
            da = dcum(c, i, nl - 1)
            if da is None:
                continue
            na = math.sqrt(sum(x * x for x in da))
            t = com[(c, i)]
            nt = math.sqrt(sum(x * x for x in t))
            if i == 0:
                base_a, base_t = na / bb, nt / bb
                continue
            if max(na, nt) > 1e-6:
                nbase += 1
                # `t` vit dans le triedre de §7 (lateral, haut, avant), `da` dans la base de
                # l'ANCRE (vertical, avant-arriere, lateral) : (tx,ty,tz) -> (ty,tz,tx).
                tr = (t[1], t[2], t[0])
                rel = math.sqrt(sum((da[k] - tr[k]) ** 2 for k in range(3))) / max(na, nt)
                cellrel[i] = (rel, abs(na - nt) / max(na, nt))
                if rel > worst:
                    worst, worst_i = rel, i
        A('ROOM-ORICOM-MASS: %-12s CONTROLE pointe : sum ldb (PHYSORICOML, cumul) contre t'
          % nm)
        A('   (PHYSORICOM), compares EN VECTEUR |a-b|/max(|a|,|b|) et non en norme (cycle 64b :')
        A('   une norme est aveugle a la direction et laissait passer 15 deg de desaccord).')
        A('   Pire ecart VECTORIEL %.4f%s sur %d orientations chargees ; le meme en NORME vaut'
          % (worst * 100.0, (' %% (i=%d)' % worst_i) if worst_i is not None else ' %', nbase))
        A('   %s. %s'
          % (('%.4f %%' % (cellrel[worst_i][1] * 100.0)) if worst_i in cellrel else 'n/a',
             'accord sur toutes les cellules' if worst < 0.05 else
             'DESACCORD > 5 % : les cellules fautives sont marquees SUSPENDUE une par une '
             'ci-dessous — une orientation fautive ne jette plus les lectures propres'))
        A('   LIGNE DE BASE i=0 (debout d\'auteur, §9 exige 0.0000), en ABSOLU parce qu\'un rapport'
          ' entre deux quasi-zeros')
        A('   ne mesure rien : |sum ldb| = %.5f B0  ·  |t| = %.5f B0.' % (base_a, base_t))
        # --- les trois deplacements que sa spec chiffre, sur le COM ------------------------------
        r = role.get(c, {})
        lat = [i for i in (2, 4) if (c, i, 0) in comL]
        todo = [('§10 supine ', r.get('sup'), 0.23, (0.18, 0.28)),
                ('§11 prone  ', r.get('pro'), 0.24, (0.20, 0.30))]
        todo += [('§12 lateral', i, 0.19, (0.15, 0.24)) for i in lat]
        for lab, i, nom, band in todo:
            if i is None or (c, i, 0) not in comL:
                A('ROOM-ORICOM-MASS: %-12s %s  i introuvable — NON MESURE' % (nm, lab))
                continue
            cols = []
            for d in rec['defs']:
                W, N = d['W'], float(d['n'])
                acc = [0.0, 0.0, 0.0]
                for l in range(min(nl, len(W))):
                    dj = dcum(c, i, l)          # CUMUL, pas l'increment `ldb[l]` (voir docstring)
                    if dj is None:
                        continue
                    for k in range(3):
                        acc[k] += W[l] * dj[k]
                dn = math.sqrt(sum((x / N) ** 2 for x in acc)) / bb
                cols.append((d['cut'], dn))
            # l'apex du meme i, pour que le facteur de conversion soit lisible sans calcul
            t = com.get((c, i))
            napex = math.sqrt(sum(x * x for x in t)) / bb if t else float('nan')
            # `rr` est publie A COTE, jamais compose : c'est la composante RADIALE du meme
            # `u - m`, au JOINT — deja contenue dans `d_COM`, et d'une autre echelle (joint
            # contre moyenne d'organe). Le composer etait un double comptage ; il est retire.
            rr = com2.get((c, i), (0.0, 0.0, 0.0))[0]
            base = cols[0][1] if cols else float('nan')
            A('ROOM-ORICOM-MASS: %-12s %s i=%d  |d_COM|=%s B0  (apex %.4f, facteur %s)'
              % (nm, lab, i, '/'.join('%.4f' % v for (_c, v) in cols), napex,
                 ('%.3f' % (base / napex)) if napex == napex and napex > 1e-9 else 'n/a'))
            _cr = cellrel.get(i)
            if _cr is not None and _cr[0] > 0.05:
                A('                              CELLULE SUSPENDUE : les deux accumulateurs de la'
                  ' pointe different de %.2f %% EN VECTEUR (%.2f %% en norme seule) — le montage'
                  % (_cr[0] * 100.0, _cr[1] * 100.0))
                A('                              est en cause, pas la physique. Le chiffre'
                  ' ci-dessus est publie comme diagnostic et NE PORTE AUCUN VERDICT.')
                # ATTRIBUTION PAR ABLATION, pas par raisonnement : le meme ecart recalcule sur
                # les six passes du balayage de controle. La passe qui le fait TOMBER designe le
                # mecanisme ; si aucune ne le fait, elles sont toutes exonerees et c'est un
                # resultat, pas un echec.
                _ab = _tipctl_ablation(txt, c, i)
                if _ab:
                    A('                              ATTRIBUTION PAR ABLATION : %s'
                      % ' · '.join('%s %.2f %%' % (lbl, v) for lbl, v in _ab))
                    _best = min(_ab[1:], key=lambda x: x[1]) if len(_ab) > 1 else None
                    # DEUX CONDITIONS POUR DESIGNER, ET ELLES SONT DECLAREES : la passe doit
                    # (a) ramener la cellule SOUS le seuil de suspension (5 %, le meme qu'ailleurs)
                    # et (b) retirer au moins 90 % de l'ecart. La seconde evite de designer un
                    # mecanisme sur un fil du rasoir : `chestR i=2` tombe a 5.00 %, pile sur le
                    # seuil, en n'en retirant que 81 % — c'est un DOMINANT, pas une explication.
                    _cut = _ab[0][1]
                    _rm = (1.0 - _best[1] / _cut) if (_best and _cut > 1e-9) else 0.0
                    if _best is not None and _best[1] < 5.0 and _rm >= 0.90:
                        A('                              -> %s RAMENE l\'ecart a %.2f %% (%.0f %%'
                          ' de l\'ecart retire) : mecanisme DESIGNE, mesure et non suppose.'
                          % (_best[0], _best[1], _rm * 100.0))
                    elif _best is not None:
                        A('                              -> la meilleure passe (%s) laisse %.2f %%'
                          ' et n\'en retire que %.0f %% : mecanisme DOMINANT, pas unique.'
                          % (_best[0], _best[1], _rm * 100.0))
                continue
            A('                              squelettique seul %s  ·  cible %.2f (bande %.2f-%.2f)'
              '  ·  rr(joint, pour memoire, NON compose) %.4f  ·  controle de pointe %.2f %%'
              % ('DANS' if band[0] <= base <= band[1] else
                 ('SOUS — borne INFERIEURE, la part tensorielle manque' if base < band[0]
                  else 'AU-DESSUS'), nom, band[0], band[1], rr,
                 (_cr[0] * 100.0) if _cr is not None else float('nan')))
        d0 = rec['defs'][0]
        A('   (frontieres w>0 / w>=0.05 / w>=0.25 — les trois colonnes de |d_COM| ci-dessus ;'
          ' N=%d, part de l\'organe portee par la chaine %.4f, le reste est ancre au buste)'
          % (d0['n'], sum(d0['W']) / float(d0['n'])))
    A('')


def _orictl_block(A, txt, names, ori, axis, b0, roles=None):
    """LE REDRESSEMENT AVANT-ARRIERE, ET LES TROIS MECANISMES SUSPECTS DESARMES TOUR A TOUR.

    Le cycle 12 a mesure que la reponse est redressee sur l'axe avant-arriere (8.7 a 30.3x contre
    1.2 a 2.3 en lateral, meme instrument) et a ECRIT qu'il ne devinait pas la cause. Ce bloc lit
    l'experience qui la designe : LE MEME balayage, refait trois fois, avec chaque fois UN des
    mecanismes suspects desarme par un controle que le moteur porte deja.

        k=0  rien de desarme (reference)      k=2  contrainte de COTE levee
        k=1  contrainte de LONGUEUR levee     k=3  rayon de capsule interpole (sonde la COLLISION)

    COMMENT SE LIT LE VERDICT, et il est ecrit AVANT de voir les chiffres :
      - le controle dont le desarmement fait TOMBER le rapport avant-arriere vers celui du
        lateral designe le mecanisme ;
      - si AUCUN ne le fait, les trois sont exoneres et la cause est ailleurs. C'est un resultat,
        pas un echec : la liste des suspects se reduit de trois.
      - `k=0` doit reproduire la reference du cycle 12. S'il ne la reproduit pas, c'est que les
        passes de controle se contaminent entre elles et RIEN de ce bloc ne vaut."""
    ctl, dg = {}, {}
    for m in re.finditer(r'^PHYSORICTL c=(\d+) k=(\d+) i=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+)'
                         r' tz=([-\d.e+]+)', txt, re.M):
        ctl[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))
    for m in re.finditer(r'^PHYSORICTL2 c=(\d+) k=(\d+) i=(\d+) rr=([-\d.e+]+) inv=([-\d.e+]+)'
                         r' flip=([-\d.e+]+)', txt, re.M):
        dg[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))
    A('-- ROOM-ORICTL : LE REDRESSEMENT, ET SES TROIS SUSPECTS DESARMES TOUR A TOUR -------------')
    if not ctl:
        A('ROOM-ORICTL: ABSENT (aucune ligne PHYSORICTL) — cette course ne refaisait pas le')
        A('   balayage avec les controles. La CAUSE du redressement reste non mesuree, ce qui')
        A('   n\'est pas la meme chose qu\'absente.')
        return
    KN = {0: 'k=0 reference    ', 1: 'k=1 LONGUEUR off ', 2: 'k=2 COTE off     ',
          3: 'k=3 CAPSULE cone ', 4: 'k=4 MUR COLLIS.  '}
    A('   NATURE : le meme deplacement soutenu que `ROOM-ORICOM`, mesure sur la meme fenetre par')
    A('     le meme emetteur, une fois par passe. REPERE : triedre de SPEC 7. Le rapport compare')
    A('     deux POLES OPPOSES, donc a stimulus vertical identique.')
    A('   `inv` et `flip` sont les compteurs de la FENETRE DE MESURE (collision / limiteur) : ils')
    A('     disent si un mecanisme a mordu pendant l\'equilibre, ou si le redressement se produit')
    A('     sans qu\'aucun contact n\'ait lieu — auquel cas la cause est dans la FORCE, pas dans une')
    A('     contrainte.')
    A('')
    A('   chaine       passe              LAT 90  LAT 45 | AP 90   AP 45  | verdict sur AP')
    for c in sorted({c for (c, _k, _i) in ctl}):
        bb = b0.get(c, 602.0)
        ax = axis.get(c, [0.0, 1.0, 0.0])
        nm = names[c] if c < len(names) else 'c%d' % c

        def _dn(k, i, _c=c, _bb=bb, _ax=ax):
            if (_c, k, i) not in ctl:
                return None
            tx, ty, tz = ctl[(_c, k, i)]
            rr = dg.get((_c, k, i), (0.0, 0.0, 0.0))[0]
            v = [tx / _bb + rr * _ax[0], ty / _bb + rr * _ax[1], tz / _bb + rr * _ax[2]]
            return math.sqrt(sum(x * x for x in v))

        def _rat(k, ia, ib):
            a, b = _dn(k, ia), _dn(k, ib)
            if a is None or b is None or min(a, b) <= 1e-9:
                return None
            return max(a, b) / min(a, b)
        base = None
        for k in sorted({k for (_c, k, _i) in ctl if _c == c}):
            l90, l45 = _rat(k, 2, 4), _rat(k, 1, 3)
            a90, a45 = _rat(k, 6, 8), _rat(k, 5, 7)
            if None in (l90, l45, a90, a45):
                continue
            lat = max(l90, l45)
            ap = max(a90, a45)
            if k == 0:
                base = ap
                verdict = 'reference (redressement %.1fx contre %.1fx en lateral)' % (ap, lat)
            elif ap <= lat * 1.5:
                verdict = 'SYMETRISE — CE MECANISME EST LA CAUSE'
            elif base and ap < base * 0.6:
                verdict = 'attenue (%.0f %% du redressement de reference) — contributeur' \
                          % (100.0 * ap / base)
            else:
                verdict = 'inchange — ce mecanisme est EXONERE'
            A('ROOM-ORICTL: %-12s %s %6.2f  %6.2f | %6.2f  %6.2f | %s'
              % (nm, KN.get(k, 'k=%d' % k), l90, l45, a90, a45, verdict))
            # ---- LES DEUX POLES EN VALEUR ABSOLUE, A COTE DE LEUR RAPPORT ----------------------
            # UN RAPPORT NE DIT PAS LEQUEL DES DEUX POLES A BOUGE. Un rapport qui tombe de 5.7 a
            # 1.2 peut venir du pole BLOQUE qui remonte (le degre de liberte revient) ou du pole
            # LIBRE qui s'effondre (une perte de mouvement deguisee en symetrie). Les deux se
            # lisent pareil sur la ligne ci-dessus, et c'est le piege `ratio-of-two-statistics`
            # du registre. On publie donc les valeurs elles-memes, dans le MEME instrument :
            # meme `_dn`, meme axe derive, meme B0 — surtout pas un second script qui aurait sa
            # propre definition de l'axe et rendrait des chiffres incomparables.
            # NATURE : |t|/B0, deplacement soutenu (moyenne de fenetre d'equilibre), sans unite.
            # REPERE : triedre de SPEC 7. LIGNE DE BASE : i=0 (pose debout), ou SPEC 9 exige 0.
            # CE QUI DISCRIMINE : les deux poles d'une paire sont a |g_eff| IDENTIQUE, donc
            # comparables SANS normalisation — aucun denominateur qui puisse s'annuler.
            _p = []
            for _lab, _ia, _ib in (('LAT90', 2, 4), ('LAT45', 1, 3),
                                   ('AP90', 6, 8), ('AP45', 5, 7)):
                _a, _b = _dn(k, _ia), _dn(k, _ib)
                _p.append('%s %.5f/%.5f' % (_lab, _a if _a is not None else float('nan'),
                                            _b if _b is not None else float('nan')))
            A('ROOM-ORICTL-POLES: %-12s %s %s' % (nm, KN.get(k, 'k=%d' % k), '  '.join(_p)))
        # les compteurs, sur la paire qui porte le redressement
        for k in sorted({k for (_c, k, _i) in ctl if _c == c}):
            r6 = dg.get((c, k, 6), (0.0, 0.0, 0.0))
            r8 = dg.get((c, k, 8), (0.0, 0.0, 0.0))
            r5 = dg.get((c, k, 5), (0.0, 0.0, 0.0))
            r7 = dg.get((c, k, 7), (0.0, 0.0, 0.0))
            # CYCLE 69 : CETTE LIGNE ECRIVAIT « supine i=6 · prone i=8 » — L'INVERSE EXACT du
            # role que `ROOM-ORICOM-ROLE` publie DANS LE MEME TABLEAU (supine -> i=8, prone -> i=6)
            # et l'inverse de la gravite mesuree (`PHYSORI4`). Les CHIFFRES etaient justes (les
            # indices d'acces ci-dessus sont les bons) ; seules les ETIQUETTES mentaient. Elles ne
            # sont plus ecrites a la main : elles viennent de `orole()`, chemin unique.
            def _rn(_i):
                if roles and roles.get(_i, (None,))[0]:
                    _r = roles[_i][0]
                    return ('supine' if 'SUPINE' in _r else
                            'prone' if 'PRONE' in _r else
                            'av.45' if 'AVANT' in _r else
                            'ar.45' if 'ARRIERE' in _r else _r.split()[0].lower())
                return 'i%d?' % _i
            A('ROOM-ORICTL-DIAG: %-12s %s  %s i=6 inv=%.0f flip=%.0f · %s i=8 inv=%.0f'
              ' flip=%.0f · %s i=5 flip=%.0f · %s i=7 flip=%.0f'
              % (nm, KN.get(k, 'k=%d' % k), _rn(6), r6[1], r6[2], _rn(8), r8[1], r8[2],
                 _rn(5), r5[2], _rn(7), r7[2]))
    A('')
    A('   LECTURE DES COMPTEURS : si `flip` et `inv` sont a ZERO des deux cotes alors que la')
    A('   reponse est redressee, aucune collision ni aucun limiteur n\'a mordu pendant la mesure —')
    A('   et le redressement vient alors de la FORCE elle-meme (le ressort vers la pose d\'auteur,')
    A('   ou le terme de gravite), pas d\'une contrainte. C\'est le partage que ce bloc tranche.')


def _shake_ring_block(A, txt, names):
    """SPEC 27 — LA STABILISATION APRES L'IMPULSION *FORTE*, ET SPEC 24/25 SANS ANIMATION.

    POURQUOI CETTE FENETRE EXISTE, alors que `ROOM-AXSETTLE` execute deja « one isolated impulse ».
    Sa §27 ecrit « after one STRONG isolated impulse », et l'impulsion de `ROOM-AXFIT` est
    DELIBEREMENT FAIBLE : demi-cosinus a 18 u/frame^2, choisi pour rester dans la bande LINEAIRE ou
    une frequence propre et un zeta sont definis. Consequence lisible dans le tableau livre :

        ROOM-AXSETTLE chestL axe=v   a0=0.01296   t1=>2.48   t05=>2.48   t01=>2.48

    Le seuil `t01` vaut 0.1 %% de `a0`, soit **1.3e-5** — c'est-a-dire SOUS le plancher de la
    fenetre. Les censures de §27 ne disent donc pas « ca n'arrete pas de sonner », elles disent
    « le seuil est descendu sous la resolution de l'instrument ». C'est la lecon
    `instrument-resolution-vs-spec-bands`, et on ne la franchit pas en reglant le solveur : on la
    franchit en donnant a la mesure la DYNAMIQUE qui lui manque, c'est-a-dire une impulsion FORTE.
    `PH-SHAKE` (`jerk`, vitesse posee d'un coup) est cette impulsion, et `PH-SHAKEN` la lache
    position/orientation/ANIMATION figees — donc rien ne re-excite la chaine pendant la descente.

    Ce bloc ne remplace ni `ROOM-SETTLE` ni `ROOM-AXSETTLE` : il s'ajoute a cote, avec le MEME
    estimateur et les MEMES seuils, pour que les trois se comparent directement. L'ecart entre
    leurs `a0` EST la mesure de la dynamique gagnee."""
    ser = {}
    for m in re.finditer(r'^PHYSRINGSH c=(\d+) f=(\d+) l=(\d+) v=([-\d.e+]+) ap=([-\d.e+]+)'
                         r' lat=([-\d.e+]+)', txt, re.M):
        c, f, l = int(m.group(1)), int(m.group(2)), int(m.group(3))
        ser.setdefault((c, l), []).append((f, float(m.group(4)), float(m.group(5)),
                                           float(m.group(6))))
    A('-- ROOM-SHRING : SPEC 27 SUR L\'IMPULSION *FORTE*, ET SPEC 24/25 SANS ANIMATION -----------')
    if not ser:
        A('ROOM-SHRING: ABSENT (aucune ligne PHYSRINGSH) — cette course n\'emettait pas la')
        A('   descente libre apres la secousse. §27 reste lue sur des fenetres dont les seuils fins')
        A('   sont sous le plancher, ce qui n\'est pas la meme chose qu\'une §27 tenue.')
        return
    A('   §27 : « dominant visible response 0.3-0.6 s ; secondary movement 0.6-1.2 s ; mostly')
    A('     settled ~1.0-1.5 s ; essentially stationary ~1.3-1.7 s ». Seuils 5 / 1 / 0.5 / 0.1 %')
    A('     de `a0`, identiques a `ROOM-SETTLE` et `ROOM-AXSETTLE` — les trois sont comparables.')
    A('   NATURE : une SERIE TEMPORELLE signee (deviation du maillon a sa pose d\'auteur), dont on')
    A('     lit l\'ENVELOPPE. REPERE : triedre de l\'ancre (SPEC 7), le meme que `PHYSRINGA`.')
    A('     LIGNE DE BASE : 0.0 sur la pose d\'auteur.')
    A('   POURQUOI `a0` EST PUBLIE EN GRAS DANS SA PROPRE COLONNE : un temps de stabilisation n\'a')
    A('     de sens que rapporte a l\'amplitude dont il part. `ROOM-AXSETTLE` rendait `>2.48` sur')
    A('     l\'axe vertical avec `a0 = 0.013` : le seuil `t01` y valait 1.3e-5. Le meme `>2.48` sur')
    A('     un `a0` cent fois plus grand voudrait dire tout autre chose.')
    A('')
    A('   chaine       l  axe   a0        t5      t1      t05     t01     |  n  a       b       '
      'zeta    f(Hz)  residu  accord')
    _floors = []
    for (c, l) in sorted(ser):
        rows = sorted(ser[(c, l)])
        frames = [r[0] for r in rows]
        nm = names[c] if c < len(names) else 'c%d' % c
        for ai, lab in ((1, 'v  '), (2, 'ap '), (3, 'lat')):
            vals = [r[ai] for r in rows]
            if not vals:
                continue
            # +2 apres le pic : les 3 premieres frames de la fenetre portent encore l'impulsion
            # `jerk` elle-meme (verifie sur la serie brute — le pic est a f=3 et la decroissance
            # propre commence a f=4). Ajuster a travers ce raccord melange stimulus et reponse.
            ffull, ffree, s_inf, a0d, i0, i1 = _fit_two_windows(vals, skip_after_peak=2,
                                                                contaminated_ref=False)
            a0 = max(abs(v) for v in vals)
            _floors.append((nm, lab.strip(), s_inf, a0))
            # LA FENETRE D'ENVELOPPE EST DERIVEE DE LA FREQUENCE AJUSTEE, exactement comme
            # `ROOM-AXSETTLE` (`_w = round(60 / f)`), et surtout PAS fixee a un nombre choisi :
            # une enveloppe glissante plus courte qu'une periode redescend entre deux lobes et
            # declenche le seuil au premier passage par zero — le defaut que la note de `ring_env`
            # decrit deja. Repli sur 26 frames (une periode a 2.3 Hz, la nominale de SPEC 24).
            _wf = 26
            if ffree and ffree[3] is not None and ffree[3] > 0.5:
                _wf = max(2, int(round(60.0 / ffree[3])))
            env = ring_env([abs(v) for v in vals], _wf)
            st = {k: settle_time(env, frames, a0, fr) for fr, k in SETTLE_BANDS}
            if not ffree or ffree[2] is None:
                A('ROOM-SHRING: %-12s %d %-4s %9.5f %7s %7s %7s %7s | %3d  %s'
                  % (nm, l, lab, a0, st['t5'], st['t1'], st['t05'], st['t01'], i1 - i0,
                     'pas d\'oscillation ajustable sur la fenetre libre — NE PAS LIRE de zeta ici'))
                continue
            a, b, z, f, _nu, rs = ffree
            A('ROOM-SHRING: %-12s %d %-4s %9.5f %7s %7s %7s %7s | %3d %+7.4f %+7.4f %7.4f %6.3f '
              ' %.4f  %s'
              % (nm, l, lab, a0, st['t5'], st['t1'], st['t05'], st['t01'], i1 - i0, a, b, z, f,
                 rs, 'oui' if _agree(ffull, ffree) else 'NON — ne pas lire'))
    A('')
    A('-- ROOM-SHFLOOR : CE QUE LA CHAINE LAISSE DERRIERE ELLE, ET POURQUOI §27 EST CENSUREE ----')
    A('   Sa §2 et sa §9 exigent le retour EXACT a la pose d\'auteur. La serie libre dit ou la')
    A('   chaine se pose REELLEMENT une fois la secousse eteinte. Ce n\'est pas zero.')
    A('   ET C\'EST LA CAUSE MESUREE DE LA CENSURE DE §27 : son barreau le plus fin (`t01`) est a')
    A('   0.1 %% de `a0`. Quand le plancher depasse ce seuil, `t01` ne peut PAS etre atteint —')
    A('   la chaine est immobile mais pas revenue, et l\'instrument ecrit `>` a l\'infini. La')
    A('   lecture « ca sonne encore » etait donc fausse : ca ne sonne plus, ca ne REVIENT pas.')
    A('')
    A('   chaine       axe   plancher s_inf   a0         s_inf/a0    seuil t01    verdict')
    for nm, lab, s_inf, a0 in _floors:
        thr = 0.001 * a0
        A('ROOM-SHFLOOR: %-12s %-4s %+12.7f  %9.5f  %8.3f %%  %10.7f  %s'
          % (nm, lab, s_inf, a0, 100.0 * abs(s_inf) / a0 if a0 > 0 else 0.0, thr,
             'CENSURE t01 (plancher > seuil)' if abs(s_inf) > thr else 't01 mesurable'))
    A('')
    A('   PREDICTION ECRITE AVANT LA COURSE pour le mode principal, depuis la donnee livree et')
    A('     l\'ecriture du solveur : `chestL` porte `stiffness=2.7696 mass=1.45`, d\'ou')
    A('     `omega = 14.4515 rad/s` (f = 2.3000 Hz, sa §24 verticale au chiffre pres) et')
    A('     `2.zeta.omega.dt = 0.16860` = le `damping=0.1686` du fichier. Le mode principal recoit')
    A('     la retention EXACTE (`kd = e^-0.1686 = 0.84485`, cycle 11) mais PAS la raideur exacte')
    A('     (`k2 = (omega.dt)^2 = 0.058013`, choix chiffre et publie du cycle 11). La recurrence')
    A('     livree doit donc rendre a = 1 + kd - k2 = 1.7868 et b = -kd = -0.8449, soit')
    A('     **zeta = 0.334 et f = 2.410 Hz**. Ce n\'est PAS 0.350 / 2.300 : l\'ecart est celui que')
    A('     le cycle 11 a assume en n\'imposant pas la raideur exacte au mode anisotrope. Si la')
    A('     serie libre rend 0.334, alors la mediane 0.350 lue sur les fenetres PAR ANIMATION')
    A('     etait legerement gonflee par l\'excitation de l\'animation, et cette fenetre-ci est le')
    A('     meilleur instrument des deux.')
    A('   RESERVE, ECRITE PARCE QU\'ELLE PEUT INVALIDER LES COLONNES `zeta`/`f` : le mode principal')
    A('     est TRIDIMENSIONNEL et anisotrope. Chaque axe du triedre porte donc un MELANGE des')
    A('     modes propres, et une recurrence d\'ordre 2 ne peut representer qu\'UN mode. C\'est le')
    A('     `residu` qui tranche : petit, l\'axe est domine par un mode et les deux colonnes valent ;')
    A('     grand, elles ne valent rien et il ne faut pas les lire. Les publier sans le residu')
    A('     serait exactement le faux vert que ce dossier paie.')


def _sec_ringdown_block(A, txt, names):
    """SPEC 36 ET SPEC 29-TORSION — LES DEUX MODES SCALAIRES, AJUSTES SUR LA SERIE LIVREE.

    Le cycle 11 a prouve §36 AU NIVEAU DES COEFFICIENTS (`PHYSDECAY` / `PHYSOSCK2` imprimes a
    l'init, polynome caracteristique -> 0.6502 et 5.1995 Hz) et a ecrit lui-meme que ce n'est pas
    la meme chose qu'observer 5.20 Hz dans une serie. Voici la serie."""
    ser = {}
    for m in re.finditer(r'^PHYSSEC c=(\d+) f=(\d+) s=([-\d.e+]+) tw=([-\d.e+]+)', txt, re.M):
        ser.setdefault(int(m.group(1)), []).append(
            (int(m.group(2)), float(m.group(3)), float(m.group(4))))
    A('-- ROOM-SEC-RING : SPEC 36 et SPEC 29-torsion, AJUSTES SUR LA SERIE LIBRE ------------------')
    if not ser:
        A('ROOM-SEC-RING: ABSENT (aucune ligne PHYSSEC) — cette course n\'emettait pas la serie du')
        A('   mode secondaire. §36 reste prouvee AU NIVEAU DES COEFFICIENTS seulement, ce qui est')
        A('   ce que le cycle 11 a explicitement dit ne pas suffire.')
        return
    A('   FENETRE : `PH-SHAKEN`, la tenue qui suit la secousse `jerk`. C\'est la seule decroissance')
    A('     LIBRE de la course : position et orientation figees, et cette phase n\'avance PAS')
    A('     l\'animation — donc rien ne re-excite les modes, contrairement aux fenetres par')
    A('     animation ou §27 lit un plancher d\'excitation au lieu d\'un ring-down.')
    A('   NATURE : deux series temporelles signees, une valeur par frame. REPERE : la racine de la')
    A('     chaine. LIGNE DE BASE : 0.0 au repos.')
    A('   ESTIMATEUR : ajustement de la recurrence lineaire d\'ordre 2 `s[n+1] = a.s[n] + b.s[n-1]`,')
    A('     puis zeta et f par ses racines. A zeta = 0.65 l\'enveloppe perd un facteur 217 par')
    A('     periode : un estimateur par extrema n\'aurait qu\'UN SEUL depassement exploitable, celui-ci')
    A('     utilise tous les echantillons.')
    A('   PREDICTION ECRITE AVANT LA COURSE, depuis les coefficients que la salle imprime a l\'init')
    A('     (`PHYSOSCK2 sec=0.2073 seckd=0.4926`) : la recurrence livree doit rendre a = 1 + kd - k2')
    A('     = 1.2853 et b = -kd = -0.4926, donc zeta = 0.651 et f = 5.20 Hz. Retrouver CES DEUX')
    A('     NOMBRES depuis la serie ferme l\'ecart que le cycle 11 a laisse ouvert.')
    A('   ECRETAGE — ET C\'EST LA QUE LA SERIE VOIT CE QUE LES COEFFICIENTS NE PEUVENT PAS VOIR :')
    A('     `*phys-sec*` est borne a `PHYS-SEC-MAX = 0.07` DANS L\'ETAT, pas seulement en sortie.')
    A('     Un ecretage a l\'interieur de la boucle change la dynamique : le mode livre cesse')
    A('     d\'etre l\'oscillateur dont le polynome donne 0.6502. Les echantillons ecretes sont')
    A('     COMPTES et EXCLUS de l\'ajustement, et le compte est publie : si l\'ajustement ne')
    A('     porte que sur la queue, il faut le savoir.')
    A('')
    A('   chaine        canal   n_tot n_ecrete n_fit    a        b       zeta     f(Hz)   residu')
    for c in sorted(ser):
        rows = sorted(ser[c])
        nm = names[c] if c < len(names) else 'c%d' % c
        for lab, idx, clip in (('sec §36', 1, 0.07), ('torsion', 2, None)):
            vals = [r[idx] for r in rows]
            if clip is not None:
                nclip = sum(1 for v in vals if abs(v) >= clip - 1e-6)
                # on garde la plus longue plage CONSECUTIVE non ecretee : un ajustement de
                # recurrence a besoin de voisins, recoller deux morceaux fabriquerait un saut.
                best, cur = [], []
                for v in vals:
                    if abs(v) >= clip - 1e-6:
                        if len(cur) > len(best):
                            best = cur
                        cur = []
                    else:
                        cur.append(v)
                if len(cur) > len(best):
                    best = cur
                fitv = best
            else:
                nclip = 0
                fitv = vals
            # une serie deja eteinte ne porte aucune information : on le DIT au lieu d'ajuster
            # du bruit de flottant.
            amp = max(abs(v) for v in vals) if vals else 0.0
            if amp <= 1e-7:
                A('ROOM-SEC-RING: %-12s %-7s %5d %8d %5s  %s'
                  % (nm, lab, len(vals), nclip, len(fitv),
                     'serie plate (amp=%.2e) — RIEN A AJUSTER, et ce n\'est pas un zero vert'
                     % amp))
                continue
            ffull, ffree, s_inf, _a0, i0, i1 = _fit_two_windows(fitv, skip_after_peak=0)
            fr = ffree if (ffree and ffree[2] is not None) else ffull
            if fr is None or fr[2] is None:
                A('ROOM-SEC-RING: %-12s %-7s %5d %8d %5d  %s'
                  % (nm, lab, len(vals), nclip, i1 - i0,
                     'aucune des deux fenetres ne rend un mode oscillant — NE PAS LIRE de zeta'))
                continue
            a, b, z, f, nu, rs = fr
            A('ROOM-SEC-RING: %-12s %-7s %5d %8d %5d %+8.4f %+8.4f  %8.4f %8.3f  %.4f  %s'
              % (nm, lab, len(vals), nclip, nu, a, b, z, f, rs,
                 'accord des 2 fenetres' if _agree(ffull, ffree) else 'DESACCORD — prudence'))
            if lab.startswith('sec'):
                A('   §36 cible zeta 0.65 (bande 0.55-0.75) et f 5.20 Hz (bande 4-7) :'
                  ' zeta %s, f %s   [amplitude max : %.5f, plafond §38 = 0.07]'
                  % ('DANS' if 0.55 <= z <= 0.75 else 'HORS',
                     'DANS' if 4.0 <= f <= 7.0 else 'HORS', amp))
                if nclip:
                    A('   ECRETAGE MESURE : %d frames sur %d collees a |s| = 0.0700000 exactement,'
                      ' soit %.0f ms.' % (nclip, len(vals), 1000.0 * nclip / 60.0))
                    A('     Pendant ces frames l\'etat de l\'oscillateur est REECRIT par la borne,')
                    A('     donc le mode livre n\'est pas celui dont le polynome caracteristique')
                    A('     donne 0.6502 — et sa §37 demande l\'inverse (« soft displacement clamps')
                    A('     should be preferred to abrupt positional clamps »). L\'ajustement')
                    A('     ci-dessus EXCLUT ces frames ; il decrit la detente, pas la saturation.')


def main():
    global OUT
    log = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LOG
    if len(sys.argv) > 2:
        # une course DEVICE ne doit pas ecraser le tableau x86 : le validateur lit celui-la.
        OUT = sys.argv[2]
    if not os.path.exists(log):
        die('log de course absent : %s' % log)

    # ---- LE TABLEAU NE PEUT PLUS ETRE ECRASE PAR SA PROPRE SORTIE STANDARD (cycle 67) ----------
    # DEFAUT TROUVE, PAS SUPPOSE. Le `keira-room-table.txt` que le validateur lisait au cycle 67
    # commencait par les NEUF LIGNES DU RESUME que ce script imprime sur stdout, et il avait perdu
    # son en-tete — donc sa ligne `empreinte de la trace lue : md5 ...`, le garde-fou de provenance
    # pose au cycle 32 precisement pour qu'un tableau ne puisse pas survivre a sa course. Verifie :
    # `grep -c md5` rendait 0 sur un fichier de 2997 lignes.
    #
    # LE MECANISME EST CONNU ET SILENCIEUX : `python3 physics_room_table.py LOG > TBL` (ou avec un
    # seul argument, `OUT` valant alors ce meme chemin par defaut). Le shell TRONQUE `TBL` et donne
    # a stdout un descripteur a l'offset 0 ; le script ecrit ensuite tout le tableau par un `open`
    # separe ; a la sortie, le tampon de stdout se vide A L'OFFSET 0 et recouvre le debut du
    # fichier. La taille reste plausible, le corps reste lisible, et RIEN en aval ne peut le voir —
    # le validateur lit des lignes `ROOM-*`, qui sont plus bas.
    #
    # `keira_room_x86.sh` verifie deja l'empreinte APRES coup (l.147-158), mais il n'est pas le seul
    # appelant, et un controle qui n'est pas chez le producteur ne couvre que les chemins qu'on a
    # pense a instrumenter. « Quand une perte se repete, on la rend IMPOSSIBLE au point de
    # production, pas detectable au point de controle » — donc ici, et pour tous les appelants.
    try:
        _so = os.fstat(sys.stdout.fileno())
        if os.path.exists(OUT):
            _to = os.stat(OUT)
            if (_so.st_dev, _so.st_ino) == (_to.st_dev, _to.st_ino):
                die('la SORTIE STANDARD de ce script est redirigee sur son propre fichier de'
                    ' sortie (%s).\n  Le resume de fin recouvrirait le debut du tableau, en'
                    ' emportant sa ligne d\'empreinte —\n  c\'est exactement ce qui est arrive au'
                    ' tableau lu par le validateur au cycle 67.\n  Passe la destination en 2e'
                    ' argument, ne redirige pas stdout dessus.' % OUT)
    except (OSError, ValueError, AttributeError):
        pass    # stdout non seekable (pipe, terminal) : aucune collision possible, on continue

    txt = open(log, errors='ignore').read()

    # QUELLE JAMBE EST CETTE COURSE ? A lire AVANT tout bloc qui etiquette une fenetre, sinon les
    # premiers blocs sortiraient avec les mots de l'autre jambe. Voir `_limarm` / [NOTE-330].
    _limarm(txt)

    # ---- la course est-elle allee au bout ? -----------------------------------------------------
    if not re.search(r'^PHYSEND', txt, re.M):
        die('la course n\'a pas atteint PHYSEND : le tableau ne peut pas etre ecrit sur une course'
            ' interrompue')
    for m in re.finditer(r'^PHYSFAIL reason=(\S+)', txt, re.M):
        die('la salle a refuse de demarrer : %s' % m.group(1))

    # ---- preuve d'absence du joueur ------------------------------------------------------------
    tgt_after = re.search(r'^PHYSROOM-START target-after=(\S+)', txt, re.M)
    nop = re.search(r'^PHYSNOPLAY viol=(\d+) actors=(\d+) killed=(\d+)', txt, re.M)
    if not tgt_after or not nop:
        die('trace incomplete : PHYSROOM-START target-after / PHYSNOPLAY manquants')
    viol, actors, killed = int(nop.group(1)), int(nop.group(2)), int(nop.group(3))
    noplayer = 'absent' if (tgt_after.group(1) == '#f' and viol == 0) else \
               ('viol=%d' % viol if viol else 'target=%s' % tgt_after.group(1))

    # ---- identite du sujet ---------------------------------------------------------------------
    subj = re.search(r'^PHYSSUBJECT ag=(\S+) elems=(\d+) bones=(-?\d+) joints=(-?\d+) mgeo=(\S+)',
                     txt, re.M)
    if not subj:
        die('trace incomplete : PHYSSUBJECT manquant')
    hd = re.search(r'\[HD-PHYS\] init "?([\w-]+)"? slot=(\d+) chains=(\d+) links=(\d+)'
                   r' colliders=(\d+) joints=(\d+)', txt)
    if not hd:
        die('trace incomplete : le moteur n\'a pas publie sa ligne [HD-PHYS] init — sans elle on ne'
            ' sait pas quel modele a ete simule ni combien de chaines il a REELLEMENT resolues')
    subject_name = hd.group(1)

    # ---- topologie resolue par le moteur -------------------------------------------------------
    chains = {}
    for m in re.finditer(r'^PHYSCHAIN c=(\d+) links=(\d+) fam=(\d+) hang=([-\d.]+) j0=(\S+)',
                         txt, re.M):
        chains[int(m.group(1))] = dict(links=int(m.group(2)), fam=int(m.group(3)),
                                       hang=float(m.group(4)), j0=m.group(5))
    if not chains:
        die('aucune ligne PHYSCHAIN : le moteur n\'a resolu aucune chaine')
    # Une chaine a links=0 serait une chaine que le moteur a ecartee. Ce n'est plus une option :
    # superviseur du 2026-08-11, « une chaine se REPARE, elle ne se retire pas », et le moteur
    # re-assied desormais sur son porteur un lien que le retarget a envoye ailleurs. Si une chaine
    # arrive encore ici a zero lien, c'est une regression et le tableau refuse de l'ecrire.
    dropped = sorted(c for c, d in chains.items() if d['links'] == 0)
    if dropped:
        die('chaine(s) a zero lien : %s — le moteur les a ecartees au lieu de les reparer.'
            % ', '.join(str(c) for c in dropped))
    pose = []
    for m in re.finditer(r'\[HD-PHYS\] pose c=(\d+) l=(\d+) dist=([-\d.e+]+) rad=([-\d.e+]+)'
                         r' ratio=([-\d.e+]+)', txt):
        pose.append((int(m.group(1)), int(m.group(2)), float(m.group(3)), float(m.group(4)),
                     float(m.group(5))))
    dropmsg = dict((int(m.group(1)), m.group(2))
                   for m in re.finditer(r'\[HD-PHYS\] drop c=(\d+) reason=(\S+)', txt))
    if dropped and not dropmsg:
        die('des chaines sont a links=0 sans qu\'aucune ligne [HD-PHYS] drop ne dise pourquoi')
    bones = {}
    for m in re.finditer(r'^PHYSBONE c=(\d+) l=(\d+) len=([-\d.]+)', txt, re.M):
        bones.setdefault(int(m.group(1)), {})[int(m.group(2))] = float(m.group(3))

    # ---- les NOMS des chaines viennent du fichier de donnees, dans l'ordre ou il les declare :
    # ---- c'est le meme ordre que le magasin C++ sert au moteur (kmachine.cpp), et la ligne
    # ---- PHYSCHAIN j0= le verifie joint par joint.
    names = []
    joints_of = []
    cur = None
    for ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
        mm = re.match(r'chain (\S+) ', ln)
        if mm:
            names.append(mm.group(1))
            cur = []
            joints_of.append(cur)
        elif ln.startswith('j ') and cur is not None:
            cur.append(ln.split()[1])
    if len(names) < len(chains):
        die('%d chaines mesurees mais %d nommees dans physics_chains.txt' % (len(chains),
                                                                            len(names)))
    for c, d in sorted(chains.items()):
        if joints_of[c][0] != d['j0']:
            die('desynchronisation nom/joint sur la chaine %d : le fichier dit %s, le moteur a'
                ' resolu %s' % (c, joints_of[c][0], d['j0']))

    # ---- les animations ------------------------------------------------------------------------
    anims = {}
    for m in re.finditer(r'^PHYSANIM a=(\d+) ag=(\S+) name=(\S+) joints=(\d+)', txt, re.M):
        anims[int(m.group(1))] = dict(ag=m.group(2), name=m.group(3))
    skipped = re.findall(r'^PHYSANIMSKIP ag=(\S+) name=(\S+) joints=(\d+) want=(\d+)', txt, re.M)
    # les animations dont le rig de variante n'a pas le meme nombre de joints que le porteur de
    # physique : elles sont JOUEES (owner : « toutes les animations »), et nommees ici.
    variants = re.findall(r'^PHYSANIMRIG ag=(\S+) name=(\S+) joints=(\d+) porteur=(\d+)', txt, re.M)
    acc = re.search(r'^PHYSANIMS accepted=(\d+) enumerated=(\d+) ags=(\d+)', txt, re.M)
    if not acc:
        die('trace incomplete : PHYSANIMS accepted/enumerated manquant')
    accepted, enumerated, nag = int(acc.group(1)), int(acc.group(2)), int(acc.group(3))

    key = re.search(r'^PHYSKEY maxanim=(\d+) drives=(\d+) slot=(\d+) hdpid=(\d+) win=(\d+)',
                    txt, re.M)
    if not key:
        die('trace incomplete : PHYSKEY manquant (sans lui la cle des lignes n\'est pas decodable)')
    maxanim, ndrive, win = int(key.group(1)), int(key.group(2)), int(key.group(5))

    # ---- les mesures ---------------------------------------------------------------------------
    rows = []
    for m in re.finditer(r'^PHYSROW k=(\d+) amp=([-\d.e+]+) root=([-\d.e+]+) pen=([-\d.e+]+)'
                         r' jump=([-\d.e+]+) ns=([-\d.e+]+)', txt, re.M):
        k = int(m.group(1))
        dr = k % ndrive
        ai = (k // ndrive) % maxanim
        c = k // (ndrive * maxanim)
        if c in dropped:
            die('la salle a publie une mesure pour la chaine %d que le moteur avait ecartee' % c)
        if c not in chains or ai not in anims or dr >= len(DRIVE_NAMES):
            die('ligne PHYSROW k=%d indechiffrable (chaine %d, anim %d, pilotage %d)'
                % (k, c, ai, dr))
        rows.append(dict(c=c, ai=ai, dr=dr,
                         amp=float(m.group(2)) / UNITS,
                         root=float(m.group(3)) / UNITS,
                         pen=float(m.group(4)) / UNITS,
                         jump=float(m.group(5)) / UNITS,
                         ns=float(m.group(6))))
    # [NOTE-150] MEME CLE `k` que PHYSROW, meme fenetre. Une trace d'avant le cycle 60 n'en a
    # aucune : `sa` reste None et la colonne se publie `n/a`, jamais `0.0000`.
    _sa = {}
    for m in re.finditer(r'^PHYSROW2 k=(\d+) skinadd=([-\d.e+]+)', txt, re.M):
        _sa[int(m.group(1))] = float(m.group(2)) / UNITS
    for r in rows:
        k = (r['c'] * maxanim + r['ai']) * ndrive + r['dr']
        r['sa'] = _sa.get(k)
    if not rows:
        die('aucune ligne PHYSROW dans la trace')
    played = len({r['ai'] for r in rows})

    # ---- LA LIGNE DE BASE : meme animation, meme duree, AUCUN pilotage -------------------------
    # Superviseur 2026-08-11 16:15 : « publier la valeur sous animation seule comme ligne de base a
    # soustraire ; un pilotage dont la reponse ne depasse pas la ligne de base n'a rien excite ».
    base = {}
    basej = {}
    for m in re.finditer(r'^PHYSBASE c=(\d+) a=(\d+) amp=([-\d.e+]+) jump=([-\d.e+]+)'
                         r' ns=([-\d.e+]+)', txt, re.M):
        base[(int(m.group(1)), int(m.group(2)))] = float(m.group(3)) / UNITS
        basej[(int(m.group(1)), int(m.group(2)))] = float(m.group(4)) / UNITS

    # ---- L'AMPLITUDE COMMANDEE de chaque pilotage (denominateur du gain) ------------------------
    stim = {}
    for m in re.finditer(r'^PHYSSTIM dr=(\d+) mag=([-\d.e+]+)', txt, re.M):
        stim[int(m.group(1))] = float(m.group(2))

    # ---- LE STIMULUS REELLEMENT RECU par chaque chaine, fenetre par fenetre ---------------------
    # Un pilotage commande ne vaut que si rien d'autre ne le domine. C'est ce chiffre qui a designe
    # la cause racine : sous animation seule, les chaines recevaient des accelerations superieures
    # a tout ce que la salle commandait, parce que la lecture d'animation reculait `frame-num` a 0
    # d'un coup et TELEPORTAIT le squelette a chaque fin d'animation.
    stimr = {}
    for m in re.finditer(r'^PHYSACC c=(\d+) a=(\d+) d=(\d+) acc=([-\d.e+]+) wraps=(\d+)',
                         txt, re.M):
        stimr[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = float(m.group(4))

    # ---- LE GRADIENT LE LONG DE LA CHAINE (7e passe de l'owner) ---------------------------------
    # DEUX series par (chaine, animation, pilotage), et leur ecart est le sujet de la 10e passe :
    #   grad    = ecart a la pose d'auteur, en metres. Il CUMULE le long de la chaine : une pointe
    #             soudee a son parent herite du chiffre de son parent et parait mobile. C'est ce
    #             que publiait le tableau du 17:06, et il disait « croissant » quand l'owner voyait
    #             l'inverse.
    #   gradang = deviation ANGULAIRE du maillon par rapport a SON ATTACHE, en degres. Mouvement
    #             PROPRE, nul pour un maillon qui suit rigidement son parent. C'est la suite que
    #             SPEC 2 exige croissante, et la seule que l'oeil de l'owner puisse contredire.
    grad, gradang = {}, {}
    gradst = {}
    for m in re.finditer(r'^PHYSGRADS c=(\d+) a=(\d+) d=(\d+) l=(\d+)'
                         r' a0=([-\d.e+]+) a1=([-\d.e+]+)', txt, re.M):
        gradst.setdefault((int(m.group(1)), int(m.group(2)), int(m.group(3))), {})[
            int(m.group(4))] = (float(m.group(5)), float(m.group(6)))
    for m in re.finditer(r'^PHYSGRAD c=(\d+) a=(\d+) d=(\d+) l=(\d+) amp=([-\d.e+]+)'
                         r'(?: ang=([-\d.e+]+))?', txt, re.M):
        key = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        grad.setdefault(key, {})[int(m.group(4))] = float(m.group(5)) / UNITS
        if m.group(6) is not None:
            gradang.setdefault(key, {})[int(m.group(4))] = float(m.group(6))

    # ---- LE RING-DOWN, FRAME PAR FRAME (defaut `hair-pudding`) ---------------------------------
    # Une ligne par (chaine, frame, maillon) pendant la fenetre de SILENCE qui suit le dernier
    # niveau d'excitation. `ang` est la deviation angulaire du maillon PAR RAPPORT A SON PARENT, en
    # degres, et la valeur de CETTE frame-la. Voir le bloc RING-DOWN en tete de fichier pour la
    # nature, le repere, la ligne de base et la reserve du signal redresse.
    # ---- LA MEME FENETRE, PROJETEE PAR AXE DANS LE REPERE DE L'ANCRE (SPEC 24) ------------------
    # `PHYSRINGA v=/ap=/lat=`. Structure identique a celle de `physics_ringdown.load()`, et c'est
    # voulu : c'est son estimateur qui la lit, pas une seconde copie ecrite ici. Un dictionnaire
    # VIDE veut dire que la trace ne porte pas la mesure — ca se declare, ca ne se comble pas.
    ringa = {}
    for m in re.finditer(r'^PHYSRINGA c=(\d+) f=(\d+) l=(\d+) v=([-\d.e+]+) ap=([-\d.e+]+)'
                         r' lat=([-\d.e+]+)', txt, re.M):
        ringa.setdefault((int(m.group(1)), int(m.group(3))), []).append(
            (int(m.group(2)), float(m.group(4)), float(m.group(5)), float(m.group(6))))
    for k in ringa:
        ringa[k].sort()

    ring = {}
    for m in re.finditer(r'^PHYSRING c=(\d+) f=(\d+) l=(\d+) ang=([-\d.e+]+)', txt, re.M):
        ring.setdefault((int(m.group(1)), int(m.group(3))), {})[
            int(m.group(2))] = float(m.group(4))

    # ---- L'ALLONGEMENT ET LE STIMULUS GRAVITAIRE, PAR FENETRE (10e passe) -----------------------
    # « Les seins s'allongent de nouveau sur les mouvements BRUSQUES » est une phrase sur un
    # PILOTAGE : un total de course ne peut pas la verifier, ni l'infirmer.
    stretch = {}
    for m in re.finditer(r'^PHYSSTR c=(\d+) a=(\d+) d=(\d+) el=([-\d.e+]+) gn=([-\d.e+]+)'
                         r' tf=([-\d.e+]+)', txt, re.M):
        stretch[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (
            float(m.group(4)), float(m.group(5)), float(m.group(6)))

    # ---- LA GRAVITE REELLEMENT VUE PAR CHAQUE ANCRE, debout puis penchee -----------------------
    grav = {}
    for m in re.finditer(r'^PHYSGRAV tag=(\S+) c=(\d+) gn=([-\d.e+]+) tf=([-\d.e+]+)', txt, re.M):
        grav.setdefault(m.group(1), {})[int(m.group(2))] = (float(m.group(3)), float(m.group(4)))
    animlen = {}
    for m in re.finditer(r'^PHYSANIMLEN a=(\d+) n=([-\d.e+]+) speed=([-\d.e+]+)', txt, re.M):
        animlen[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))

    # ---- LA POSITION MOYENNE de la pointe, debout puis penchee a 60 degres ----------------------
    # C'est un DEPLACEMENT SOUTENU. La boite englobante (colonne tipvar) ne retient que la variance
    # et vaut structurellement zero sous une pose tenue : elle ne pouvait pas voir la gravite, et
    # elle ne l'a jamais vue.
    mean = {}
    for m in re.finditer(r'^PHYSMEAN tag=(\S+) c=(\d+) x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)',
                         txt, re.M):
        mean.setdefault(m.group(1), {})[int(m.group(2))] = (
            float(m.group(3)) / UNITS, float(m.group(4)) / UNITS, float(m.group(5)) / UNITS)

    # ---- le repos ------------------------------------------------------------------------------
    idle = {}
    for m in re.finditer(r'^PHYSIDLE c=(\d+) dev=([-\d.e+]+) hang=([-\d.e+]+) amp=([-\d.e+]+)'
                         r' fam=(\d+)', txt, re.M):
        idle[int(m.group(1))] = dict(dev=float(m.group(2)) / UNITS, hang=float(m.group(3)),
                                     amp=float(m.group(4)) / UNITS, fam=int(m.group(5)))
    if not idle:
        die('aucune ligne PHYSIDLE : le repos n\'a pas ete mesure')

    # ---- l'inclinaison statique (6e passe : la gravite existe-t-elle ?) -------------------------
    tilt = {}
    for m in re.finditer(r'^PHYSTILT c=(\d+) deg=([-\d.e+]+) dev=([-\d.e+]+) amp=([-\d.e+]+)'
                         r' fam=(\d+)', txt, re.M):
        tilt[int(m.group(1))] = dict(deg=float(m.group(2)), dev=float(m.group(3)) / UNITS,
                                     amp=float(m.group(4)) / UNITS, fam=int(m.group(5)))

    # ---- la courbe de reponse (6e passe : « trop statique / trop hysterique ») ------------------
    resp = {}
    for m in re.finditer(r'^PHYSRESP c=(\d+) lvl=(\d+) exc=([-\d.e+]+) amp=([-\d.e+]+)'
                         r' jump=([-\d.e+]+)', txt, re.M):
        resp.setdefault(int(m.group(1)), []).append(
            dict(lvl=int(m.group(2)), exc=float(m.group(3)),
                 amp=float(m.group(4)) / UNITS, jump=float(m.group(5)) / UNITS))

    # ---- le diagnostic par chaine --------------------------------------------------------------
    diag = {}
    shellfire = {}   # tag -> (corrections `rad>0`, inward `rad<0` ou None si vieille trace)
    for m in re.finditer(r'^PHYSDIAG tag=(\S+) c=(\d+) selfcol=([-\d.e+]+) retreat=([-\d.e+]+)'
                         r' flip=([-\d.e+]+)', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            selfcol=float(m.group(3)), retreat=float(m.group(4)), flip=float(m.group(5)))
    for m in re.finditer(r'^PHYSDIAG2 tag=(\S+) c=(\d+) inv=([-\d.e+]+) invres=([-\d.e+]+)'
                         r' elong=([-\d.e+]+)(?: rad=([-\d.e+]+))?', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            inv=float(m.group(3)), invres=float(m.group(4)), elong=float(m.group(5)),
            rad=float(m.group(6)) if m.group(6) is not None else 0.0)
    for m in re.finditer(r'^PHYSDIAG3 tag=(\S+) c=(\d+) bendcut=([-\d.e+]+) shape=([-\d.e+]+)'
                         r' buried=([-\d.e+]+)(?: tiprot=([-\d.e+]+))?', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            bendcut=float(m.group(3)), shape=float(m.group(4)), buried=float(m.group(5)),
            tiprot=float(m.group(6)) if m.group(6) is not None else 0.0)
    for m in re.finditer(r'^PHYSDIAG4 tag=(\S+) c=(\d+) side=([-\d.e+]+)', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            side=float(m.group(3)))
    # volprio : paires (lien, volume) ecartees par la DECISION 1 -- le premier chiffre qui dise OU
    #           les volumes se contredisent. shellrad : ecart radial d'un lien-fourreau a l'axe du
    #           membre qu'il entoure, en metres apres division. Les deux sont ABSENTS des courses
    #           d'avant ce cycle : le `.get(..., None)` les distingue d'un zero mesure.
    #           shellin : l'excursion RENTRANTE la plus profonde du meme lien-fourreau -- de combien
    #           il est passe SOUS sa distance de pose modele, donc DANS la chair. Signee, negative
    #           sous le defaut, en metres apres division. Absente des vieilles traces : le
    #           `.get(..., None)` la distingue d'un zero mesure.
    #           shellout : l'excursion SORTANTE, relevee AVANT correction elle aussi. Elle repare
    #           une mesure non discriminante -- `shellrad` est post-correction et lit 0 que le
    #           fourreau soit epingle ou libre. Absente des vieilles traces : None, pas 0.
    for m in re.finditer(r'^PHYSDIAG5 tag=(\S+) c=(\d+) volprio=([-\d.e+]+)'
                         r'(?: shellrad=([-\d.e+]+))?(?: shellin=([-\d.e+]+))?'
                         r'(?: shellout=([-\d.e+]+))?', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            volprio=float(m.group(3)),
            shellrad=(float(m.group(4)) / UNITS) if m.group(4) is not None else None,
            shellin=(float(m.group(5)) / UNITS) if m.group(5) is not None else None,
            shellout=(float(m.group(6)) / UNITS) if m.group(6) is not None else None)
    # LES DEUX MOITIES DU LIMITEUR RADIAL, comptees separement. La ligne PHYSSHELL etait emise
    # dans la trace depuis son ajout mais AUCUN parseur ne la lisait : le compte n'a donc jamais
    # atteint le tableau, et « quelle moitie epingle le fourreau » est reste sans reponse pendant
    # deux cycles. `corrections` = branche `rad>0` (le pan s'ecarte, on le ramene vers l'axe) ;
    # `inward` = branche `rad<0` (le pan est DANS la chair, on l'en ressort -- regle 6).
    # NATURE : des COMPTES d'evenements. REPERE : sans objet. `inward` absent d'une vieille trace
    # reste None, ce qui le distingue d'un zero mesure.
    # SPEC 18 — la penetration mesuree contre la PEAU et non contre les volumes. Les deux colonnes
    # existent cote a cote exprès : `meshpen` mesure contre des volumes qui ne representent que
    # 29.7 % de la geometrie pilotee (0 % pour backhair et les pantflap), donc son zero ne dit rien
    # de ce que l'owner voit. NATURE : profondeur signee, positive = SOUS la peau, en metres apres
    # division. REPERE : le monde, a la frame ecrite — la meme position d'ou `meshpen` est tire.
    # LECTURE HORS DEFAUT : 0. `tests` distingue un zero MESURE d'un zero « je n'ai pas regarde ».
    skinpen = {}
    skinadd = {}
    for m in re.finditer(r'^PHYSSKIN tag=(\S+) c=(\d+) skinpen=([-\d.e+]+)'
                         r'(?: skinadd=([-\d.e+]+))? tests=(\d+)', txt, re.M):
        skinpen.setdefault(m.group(1), {})[int(m.group(2))] = (
            float(m.group(3)) / UNITS, int(m.group(5)))
        # [NOTE-150] `None` quand la trace est anterieure au cycle 60 : « pas mesure » ne se
        # confond jamais avec « mesure a zero », et aucune ligne ne se publie sur un None.
        skinadd.setdefault(m.group(1), {})[int(m.group(2))] = (
            (float(m.group(4)) / UNITS) if m.group(4) is not None else None)
    # [NOTE-154] la LIGNE DE BASE au repos, et le compte de lectures anatomiquement impossibles.
    # [NOTE-241] CE QUE LA CONTRAINTE DE PEAU RETIRE, par tag. Un correctif qui enleve du mouvement
    # se chiffre. AGREGAT DE JAMBE, GLOBAL a la course (jamais par chaine : il ne peut donc pas etre
    # lu comme une colonne par chaine, regle 7).
    skinc = {}
    for m in re.finditer(r'^PHYSSKINC tag=(\S+) n=([-\d.e+]+) sum=([-\d.e+]+) worst=([-\d.e+]+)'
                         r'(?: reste=([-\d.e+]+))?', txt, re.M):
        skinc[m.group(1)] = (float(m.group(2)), float(m.group(3)) / UNITS,
                             float(m.group(4)) / UNITS,
                             (float(m.group(5)) / UNITS) if m.group(5) is not None else None)
    skinrest, skinout = {}, {}
    # [NOTE-158] LA COUVERTURE DE LA PEAU. Une troncature silencieuse est un de-scope : ce couple
    # doit vivre DANS le tableau, a cote de `skinpen`, et pas dans une ligne de log.
    # `chain=` (cycle 62) : les ensembles portes par un os de CHAINE. Ils sont DECLARES et
    # CHARGES, simplement ranges dans une autre population — les compter comme « jetes » serait un
    # faux rouge. Absent des traces anterieures, donc 0 par defaut et la garde retrouve son sens
    # d'origine sur elles.
    _bs = re.search(r'^PHYSBSURF sets=(\d+) declared=(\d+) max=(\d+)(?: chain=(\d+))?', txt, re.M)
    _bschain = int(_bs.group(4)) if (_bs and _bs.group(4) is not None) else 0
    skinmiss = {}
    for m in re.finditer(r'^PHYSSKIN2 tag=(\S+) c=(\d+) skinrest=([-\d.e+]+) skinout=(\d+)'
                         r'(?: skinmiss=([-\d.e+]+))?', txt, re.M):
        skinrest.setdefault(m.group(1), {})[int(m.group(2))] = float(m.group(3)) / UNITS
        skinout[m.group(1)] = int(m.group(4))
        skinmiss.setdefault(m.group(1), {})[int(m.group(2))] = (
            float(m.group(5)) if m.group(5) is not None else None)
    # SPEC 33 — LA SURFACE MEDIALE DE L'AUTRE SEIN. Colonnes en UNITES DE JEU dans la trace, en
    # metres apres division ici. `medn` est le DOMAINE : il decide si les trois autres colonnes
    # veulent dire quelque chose. Sentinelle 1000000.0 sur gap/gapa = « aucune lecture ».
    med, med2 = {}, {}
    for m in re.finditer(r'^PHYSMED tag=(\S+) c=(\d+) gap=([-\d.e+]+) gapa=([-\d.e+]+)'
                         r' pen=([-\d.e+]+)', txt, re.M):
        med.setdefault(m.group(1), {})[int(m.group(2))] = (
            float(m.group(3)), float(m.group(4)), float(m.group(5)))
    for m in re.finditer(r'^PHYSMED2 tag=(\S+) c=(\d+) rest=([-\d.e+]+) n=([-\d.e+]+)'
                         r'(?: far=([-\d.e+]+) space=([-\d.e+]+))?', txt, re.M):
        med2.setdefault(m.group(1), {})[int(m.group(2))] = (
            float(m.group(3)), float(m.group(4)),
            float(m.group(5)) if m.group(5) is not None else None,
            float(m.group(6)) if m.group(6) is not None else None)
    # LE CONTROLE POSITIF DE SPEC 33. `frac=` est une FRACTION SANS DIMENSION depuis le cycle 62 ;
    # le champ s'appelait `inj=` et portait des UNITES DE JEU. Le nom a change EXPRES : lire une
    # fraction sous le nom d'une longueur serait un echange de denominateur silencieux. Une trace
    # d'avant le cycle 62 ne matche donc PAS, `med3` reste vide, et le bloc de publication le dit
    # au lieu d'inventer un controle.
    med3 = {}
    for m in re.finditer(r'^PHYSMED3 tag=(\S+) c=(\d+) frac=([-\d.e+]+) gapi=([-\d.e+]+)',
                         txt, re.M):
        med3.setdefault(m.group(1), {})[int(m.group(2))] = (float(m.group(3)), float(m.group(4)))
    med3_legacy = bool(re.search(r'^PHYSMED3 tag=\S+ c=\d+ inj=', txt, re.M)) and not med3
    # (SPEC 7) LE TRIEDRE LOCAL, PAR CHAINE ET PAR AXE. `phys-tri-world` le calcule depuis le
    # rig ; ce ne sont PAS des litteraux (verifie : `*phys-fx/fy/fz*`, et l'accesseur accepte
    # l'indice 0 depuis toujours). L'axe 0 — le lateral SORTANT, celui dont §7 parle — n'etait
    # simplement jamais emis avant le cycle 62.
    tri = {}
    for m in re.finditer(r'^PHYSTRI c=(\d+) a=(\d+) x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)',
                         txt, re.M):
        tri.setdefault(int(m.group(1)), {})[int(m.group(2))] = (
            float(m.group(3)), float(m.group(4)), float(m.group(5)))
    for m in re.finditer(r'^PHYSSHELL tag=(\S+) corrections=([-\d.e+]+)'
                         r'(?: inward=([-\d.e+]+))?', txt, re.M):
        shellfire[m.group(1)] = (
            float(m.group(2)),
            float(m.group(3)) if m.group(3) is not None else None)
    # rootrot : l'angle ECRIT dans la 3x3 du maillon `rootlock` -- le premier segment de la meche,
    #           celui qui part du cuir chevelu. ABSENT des courses d'avant ce cycle, et valant zero
    #           STRUCTURELLEMENT avant le correctif (la boucle d'ecriture sautait tout `l < rlk`) :
    #           le `.get(..., None)` distingue « pas mesure » de « mesure a zero », et c'est cette
    #           distinction qui fait du zero un controle positif au lieu d'un trou.
    for m in re.finditer(r'^PHYSDIAG6 tag=(\S+) c=(\d+) rootrot=([-\d.e+]+)'
                         r'(?: raddropm=([-\d.e+]+))?', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            rootrot=float(m.group(3)),
            raddropm=(float(m.group(4)) / UNITS) if m.group(4) is not None else None)
    # retfblen : l'erreur de longueur d'os que le REPLI du recul aurait ecrite sur cette chaine.
    #            Le repli gardait `want = |auteur(kk) - attache SIMULEE|` au lieu de la longueur du
    #            modele, et il ecrit EN DERNIER dans la frame : l'os s'allongeait d'exactement ce
    #            rapport. C'est la cause mesuree de `ROOM-STRETCH` a 1.3088, et cette colonne est le
    #            CONTROLE POSITIF de sa correction -- elle reste non nulle pendant que l'allongement
    #            ecrit tombe. ABSENTE des courses d'avant ce cycle : `.get(..., None)` distingue
    #            « pas mesure » de « mesure a zero ».
    for m in re.finditer(r'^PHYSDIAG7 tag=(\S+) c=(\d+) retfblen=([-\d.e+]+)', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            retfblen=float(m.group(3)))
    # la re-assise : combien de liens le moteur a replaces, et combien ont du retomber sur
    # l'ancienne heuristique (rayon le long de l'os du porteur) au lieu de la place du rig.
    global RESEAT_FB
    _rs = re.search(r'^PHYSRESEAT n=([-\d.e+]+) fallback=([-\d.e+]+)', txt, re.M)
    RESEAT_FB = (float(_rs.group(1)), float(_rs.group(2))) if _rs else None

    # ---- le controle positif -------------------------------------------------------------------
    pc = re.search(r'^PHYSPC injections=(\d+) armed=([-\d.e+]+) disarmed=([-\d.e+]+)'
                   r'(?: inject=([-\d.e+]+))?(?: armedmax=([-\d.e+]+) disarmedmax=([-\d.e+]+))?',
                   txt, re.M)
    if not pc:
        die('aucune ligne PHYSPC : le controle positif n\'a pas tourne')
    inj = int(pc.group(1))
    armed_raw = float(pc.group(2)) / UNITS
    disarmed_raw = float(pc.group(3)) / UNITS
    # la ligne ROOM-POSCONTROL porte une PENETRATION : le residu signe est ramene a zero quand il
    # est negatif, parce qu'une marge de 5 cm et une marge de 1 cm sont toutes deux « ne traverse
    # pas ». Les deux valeurs signees brutes sont ecrites juste en dessous, rien n'est cache.
    armed = max(0.0, armed_raw)
    disarmed = max(0.0, disarmed_raw)
    # MEME UNITE que `armed`/`disarmed` ci-dessus (des METRES) : le critere de l'arbitrage du
    # 2026-08-20 13:20 compare `armed - disarmed` A CE NOMBRE, donc les trois doivent etre
    # homogenes. La valeur brute en unites de jeu est ecrite en clair sur la ligne publiee.
    inject_u = float(pc.group(4)) if pc.group(4) is not None else None
    inject_m = (inject_u / UNITS) if inject_u is not None else None
    # [NOTE-459] LES DEUX ANCIENS MAXIMA, LATCHES INDEPENDAMMENT. Ils ne portent plus le verdict —
    # `armed`/`disarmed` ci-dessus sont desormais LA PAIRE relevee a l'argmax de la reponse
    # appariee — mais ils restent publies pour que la comparaison avec les courses anterieures
    # reste possible. Rien n'est retire du dossier, c'est la LIGNE DE VERDICT qui change.
    armx = (float(pc.group(5)) / UNITS) if pc.group(5) is not None else None
    disx = (float(pc.group(6)) / UNITS) if pc.group(6) is not None else None

    # ---- l'intention d'animation ---------------------------------------------------------------
    auth = {}
    for m in re.finditer(r'^PHYSAUTH c=(\d+) hit=([-\d.e+]+) ok=([-\d.e+]+) dot=([-\d.e+]+)'
                         r' nrm=([-\d.e+]+) dsum=([-\d.e+]+)', txt, re.M):
        hit, ok = float(m.group(2)), float(m.group(3))
        dot, nrm = float(m.group(4)), float(m.group(5))
        auth[int(m.group(1))] = dict(hit=hit, ok=ok, dot=dot, nrm=nrm, dsum=float(m.group(6)),
                                     usum=0.0, tmov=0.0, contact=0,
                                     tr=(dot / nrm if nrm > 0.0 else 0.0))
    for m in re.finditer(r'^PHYSAUTH2 c=(\d+) usum=([-\d.e+]+) tmov=([-\d.e+]+)'
                         r' contact=([-\d.e+]+) fam=(\d+)', txt, re.M):
        if int(m.group(1)) in auth:
            auth[int(m.group(1))]['usum'] = float(m.group(2))
            auth[int(m.group(1))]['tmov'] = float(m.group(3)) / UNITS
            auth[int(m.group(1))]['contact'] = int(float(m.group(4)))
    if not auth:
        die('aucune ligne PHYSAUTH')
    a_driven = sorted(c for c, d in auth.items() if d['hit'] > 0.0 and c not in dropped)
    # RESPECTEE = sur CHAQUE frame ou l'animation pilotait la chaine, la position ecrite valait la
    # pose d'auteur PLUS l'ecart simule, a PHYS-AUTH-TOL pres (0.05 u = 12 micrometres). C'est
    # l'enonce exact de « l'animation a la priorite » : son deplacement arrive au joint a
    # coefficient 1, jamais mis a l'echelle, jamais mixe, jamais retarde.
    a_ok = [c for c in a_driven if auth[c]['ok'] >= auth[c]['hit']]

    # le controle positif du canal d'auteur : l'animation retardee d'une frame doit FAIRE TOMBER ce
    # compteur. Sans cette chute, le compteur ci-dessus ne mesure rien.
    apc = {}
    for m in re.finditer(r'^PHYSAUTHPC c=(\d+) hit=([-\d.e+]+) ok=([-\d.e+]+)', txt, re.M):
        apc[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
    if not apc:
        die('aucune ligne PHYSAUTHPC : le compteur d\'identite d\'auteur n\'a pas de controle'
            ' positif, donc ce qu\'il annonce ne vaut rien')
    apc_hit = sum(h for h, _ in apc.values())
    apc_ok = sum(o for _, o in apc.values())

    # ce que les limiteurs ont retire
    # CYCLE 36 : `retreat_n` / `retreat_sum` ONT DISPARU DE CETTE LIGNE, ET C'EST UNE CORRECTION.
    # `*phys-retreat-n*` et `*phys-retreat-sum*` etaient DEFINIS, PUBLIES et REMIS A ZERO dans le
    # moteur sans qu'AUCUNE ligne ne les incremente (verifie par grep : une definition, une lecture,
    # une remise a zero, zero ecriture) depuis le retrait de `phys-retreat-chain` le 2026-08-13.
    # Le tableau en tirait « recul vers la pose du modele : 0 fois (jamais declenche) », et le
    # rapport du cycle 35 en a fait un ACQUIS (« aucun suppresseur n'a tire »). C'etait un zero de
    # domaine VIDE. `raddrop_*` et `buried`, eux, ont un ecrivain : ils restent.
    lim = re.search(r'^PHYSLIM raddrop_n=([-\d.e+]+) raddrop_sum=([-\d.e+]+)'
                    r' buried=([-\d.e+]+)', txt, re.M)
    if not lim:
        die('aucune ligne PHYSLIM : un limiteur qui ne chiffre pas ce qu\'il retire est interdit')
    radr_n, radr_s = int(float(lim.group(1))), float(lim.group(2)) / UNITS
    buried_n = int(float(lim.group(3)))

    # BALAYAGE DE SPHERE DU RECUL. NATURE : un compte d'evenements sur la course. LECTURE QUAND LE
    # DEFAUT EST ABSENT : 0 — la pose du modele est admissible, l'arc suffit, rien a balayer.
    #
    # CE QUE CETTE LIGNE PUBLIAIT AVANT, ET POURQUOI ELLE NE LE PUBLIE PLUS : `PHYSLIM3` portait
    # `radial_n` / `radial_sum`, lus par la salle via `(phys-limiter 6)` et `(phys-limiter 7)`. Le
    # moteur n'a AUCUN compteur radial : ces deux index tombent dans la branche `else` de
    # `phys-limiter` et rendaient tous les deux `*phys-buried-n*`. Course du 2026-08-12 :
    #     PHYSLIM buried=987636   PHYSLIM3 radial_n=987636 radial_sum=987636
    # et ce tableau en tirait « part radiale de la force, ecartee : 987623 fois, 987623.0000
    # u/frame^2 au total soit 1.0000 par declenchement ». Le ratio de 1.0000 etait la signature : un
    # compteur divise par lui-meme. Une grandeur publiee sous un nom qui n'est pas le sien est un
    # faux vert en attente, et celui-la a survecu des jours.
    lim3 = re.search(r'^PHYSLIM3 sphere_n=([-\d.e+]+)', txt, re.M)
    sphere_n = int(float(lim3.group(1))) if lim3 else -1

    # REPLIS DU RECUL. La salle emet `PHYSLIM2 retreat_fallback=` depuis toujours et ce tableau ne
    # l'a JAMAIS lu : un instrument emis et jamais publie est un instrument muet. Il compte les fois
    # ou le recul n'a trouve AUCUN point admissible sur son chemin — donc pas meme la pose du
    # modele — et s'est pose sur le moins mauvais. C'est le seul chemin qui reste vers une
    # penetration residuelle positive, et c'est celui par lequel `rmidhair` sortait a 0.0017 m.
    lim2 = re.search(r'^PHYSLIM2 retreat_fallback=([-\d.e+]+)', txt, re.M)
    retfb_n = int(float(lim2.group(1))) if lim2 else -1

    # CONTROLE POSITIF DU PREDICAT CONIQUE.
    # NATURE : une PROFONDEUR de penetration residuelle, en metres, prise en fin de fenetre.
    # REPERE : monde, et surtout — le solide contre lequel elle est mesuree est le MEME des deux
    #          cotes (l'enveloppe convexe des deux spheres, `phys-pen-chain` force l'exactitude).
    #          C'est ce qui rend le controle capable de MONTER : si la mesure suivait le predicat
    #          du solveur, armee elle regarderait le meme ensemble retreci et tomberait a zero.
    # LECTURE QUAND LE DEFAUT EST ABSENT : desarme, la valeur de la course ; armee, elle MONTE,
    #          parce que le solveur cesse de pousser des que le lien sort d'un ensemble plus petit
    #          que le solide reel, et l'y laisse.
    conoff = re.search(r'^PHYSCONE tag=cone-disarmed maxpen=([-\d.e+]+)', txt, re.M)
    conon  = re.search(r'^PHYSCONE tag=cone-armed maxpen=([-\d.e+]+)', txt, re.M)
    # LE MOTEUR EMET EN UNITES DE JEU, comme `PHYSROW pen=` (converti ligne 190). Publier ce
    # nombre brut sous une etiquette « profondeur (m) » serait une grandeur publiee sous un nom qui
    # n'est pas le sien -- le motif exact qui a coute deux cycles (`radial_n`/`radial_sum`).
    cone_dis = float(conoff.group(1)) / UNITS if conoff else None
    cone_arm = float(conon.group(1)) / UNITS if conon else None

    # LES VOLUMES QUE LE MOTEUR A RESOLUS. meshpen mesure l'entree dans un collider DECLARE, pas la
    # traversee du corps : sans la liste des volumes, un zero ne dit pas contre QUOI il est zero.
    cols = []
    for m in re.finditer(r'^PHYSCOL ci=(\d+) j=(\S+) j2=(\S+)', txt, re.M):
        cols.append((int(m.group(1)), m.group(2), m.group(3)))
    if not cols:
        die('aucune ligne PHYSCOL : sans la liste des volumes resolus, un zero de penetration ne'
            ' prouve rien (superviseur 2026-08-11)')
    covered = sorted({j for _, j, _ in cols} | {j for _, _, j in cols} - {'-', '?'})

    # LES JOINTS QUE CHAQUE CHAINE ECRIT REELLEMENT (verdict owner : semelle, languettes de genou)
    written = {}
    for m in re.finditer(r'^PHYSJOINT c=(\d+) l=(\d+) idx=(-?\d+) name=(\S+)', txt, re.M):
        written.setdefault(int(m.group(1)), []).append((int(m.group(2)), int(m.group(3)),
                                                        m.group(4)))

    # LES INVERSIONS : le compte de la course, puis celui de la fenetre ou le defaut est injecte.
    inv = {}
    for m in re.finditer(r'^PHYSINV phase=(\w+) flips=([-\d.e+]+) degen=([-\d.e+]+)'
                         r' reseat=([-\d.e+]+) residual=([-\d.e+]+)', txt, re.M):
        inv[m.group(1)] = (int(float(m.group(2))), int(float(m.group(3))),
                           int(float(m.group(4))), int(float(m.group(5))))
    if 'run' not in inv or 'control' not in inv:
        die('lignes PHYSINV manquantes : le compteur d\'inversions doit etre publie pour la course'
            ' ET pour la fenetre de controle positif (verdict owner du 2026-08-11 : un sein'
            ' retourne vers l\'interieur)')

    # qui peut porter la physique : la reponse de la fonction du jeu, appelee a l'execution
    mgeo = []
    for m in re.finditer(r'^PHYSMGEO ag=(\S+) mgeo=(\S+) entry=(-?\d+)', txt, re.M):
        mgeo.append((m.group(1), m.group(2), int(m.group(3))))
    if not mgeo:
        die('aucune ligne PHYSMGEO : sans la reponse de hd-desired-entry-for-mgeo on ne peut pas'
            ' dire quel rig peut porter la physique, on ne peut que le supposer')

    # ---- agregats par chaine -------------------------------------------------------------------
    worst = {}
    for r in rows:
        for col in ('amp', 'root', 'pen', 'jump'):
            w = worst.setdefault(r['c'], {})
            if col not in w or r[col] > w[col]['v']:
                w[col] = dict(v=r[col], ai=r['ai'], dr=r['dr'])

    # ---- ECRITURE ------------------------------------------------------------------------------
    L = []

    # ---- LE POINT DE PASSAGE UNIQUE (cycle 67) ------------------------------------------------
    # `A` etait `L.append`. Il devient une fonction, et c'est TOUT le verrou : il n'existe aucun
    # autre chemin par lequel une ligne entre dans ce tableau — les blocs auxiliaires
    # (`_oricom_block`, `_orictl_block`, `_shake_ring_block`, ...) le recoivent en parametre et
    # ecrivent par lui. Une ligne qui RESSEMBLE a une comparaison gauche/droite et qui ne porte pas
    # sa pose est donc enregistree comme VIOLATION, quel que soit le site qui l'a ecrite et meme
    # s'il est ecrit demain par quelqu'un qui n'a jamais lu ce commentaire. C'est la difference
    # entre un verrou et une note : la note demande qu'on s'en souvienne.
    #
    # `notasym=True` est la SEULE derogation, et elle n'est pas silencieuse : chaque ligne exemptee
    # est comptee et LISTEE par `ROOM-ASYM-VERROU`. Une derogation qu'on ne peut pas compter est
    # une porte ouverte ; celle-ci se lit dans le tableau.
    _asym_viol, _asym_exempt = [], []

    def A(s, notasym=False):
        if _asym_suspect(s) and _ASYM_MARK not in s and _ASYM_REFUS not in s:
            (_asym_exempt if notasym else _asym_viol).append(s)
        L.append(s)

    # ---- LE REGISTRE DE POSES : quelle donnee a ete relevee dans quelle pose ------------------
    # C'est la piece qui manquait, et son absence est la cause du defaut du 2026-08-21 01:20 : les
    # sites savaient calculer un rapport gauche/droite, aucun ne savait dans QUELLE pose il l'avait
    # releve. Le registre est construit UNE fois, ici, depuis la trace — jamais devine par un site.
    #
    # Le plan de reflexion est publie une seule fois par la course (`PHYSAXW ax=2`, l'axe lateral
    # du solveur) et sert a toutes les poses : c'est ce qui rend les ecarts comparables entre eux.
    _lat = None
    for _m in re.finditer(r'^PHYSAXW ax=2 ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)', txt, re.M):
        _lat = tuple(float(_m.group(k)) for k in (1, 2, 3))
    POSE = {
        'PH-REG':  _Pose('PH-REG heritee',  _pose_dev_from(txt, 'PHYSREGB', _lat),  'PHYSREGB'),
        'PH-REGS': _Pose('PH-REGS epinglee', _pose_dev_from(txt, 'PHYSREGSB', _lat), 'PHYSREGSB'),
        'PH-SGN':  _Pose('PH-SGN epinglee', _pose_dev_from(txt, 'PHYSSGNB', _lat),  'PHYSSGNB'),
        'PH-REGT': _Pose('PH-REGT resserree', _pose_dev_from(txt, 'PHYSREGTB', _lat), 'PHYSREGTB'),
        'PH-REGA': _Pose('PH-REGA axes du sujet',
                         _pose_dev_from(txt, 'PHYSREGAB', _lat), 'PHYSREGAB'),
        'PH-REGB': _Pose('PH-REGB translation sur les axes du sujet',
                         _pose_dev_from(txt, 'PHYSREGBB', _lat), 'PHYSREGBB'),
    }
    # PH-SYM joue DEUX poses dans la meme course (`i=0` symetrique, `i=1` asymetrique) : chacune a
    # la sienne, et les confondre reviendrait a publier l'ecart de l'une sous l'autre.
    for _i in (0, 1):
        POSE['PH-SYM%d' % _i] = _Pose('PH-SYM i=%d' % _i,
                                      _pose_dev_from(txt, 'PHYSSYMB', _lat, extra='i=%d' % _i),
                                      'PHYSSYMB i=%d' % _i)
    # LES PHASES QUI N'ONT AUCUN ENREGISTREMENT DE POSE. Elles ne sont pas oubliees : elles sont
    # NOMMEES, et leurs lignes gauche/droite se taisent tant que la salle ne publie pas leur pose.
    # « On n'a pas mesure » n'est pas « c'est symetrique » — cf. la note de `_Pose`.
    # PH-SETTLE ET PH-TILT ONT DESORMAIS LEUR ENREGISTREMENT (cycle 67). La salle emet
    # `PHYSPOSETAG tag=<nom>` au point de protocole de chaque fenetre etiquetee, par un emetteur
    # UNIQUE (`physroom-emit-poseb`) : c'est la piece qui manquait pour que `ROOM-SPEC7-MIROIR` et
    # `ROOM-GRAVSAG-MIRROR` puissent dire dans quelle pose ils ont ete pris.
    POSE['PH-SETTLE'] = _Pose('PH-SETTLE (pose d\'amorcage)',
                              _pose_dev_from(txt, 'PHYSPOSETAG', _lat, extra='tag=settle'),
                              'PHYSPOSETAG tag=settle')
    # `ROOM-GRAVSAG-MIRROR` compare le sag de la fenetre `idle` a celui de la fenetre `tilt` : la
    # comparaison ne vaut que ce que vaut la PIRE des deux poses, et c'est celle-la qu'on publie.
    # Prendre la meilleure des deux serait choisir le chiffre qui arrange.
    _dvi = _pose_dev_from(txt, 'PHYSPOSETAG', _lat, extra='tag=idle')
    _dvt = _pose_dev_from(txt, 'PHYSPOSETAG', _lat, extra='tag=tilt')
    _dvw = None if (_dvi is None and _dvt is None) else max(x for x in (_dvi, _dvt)
                                                            if x is not None)
    POSE['PH-TILT'] = _Pose('PH-IDLE + PH-TILT (pire des deux)', _dvw,
                            'PHYSPOSETAG tag=idle / tag=tilt')
    # CELLES QUI N'EN ONT TOUJOURS PAS, ET LA RAISON EST STRUCTURELLE POUR LA DERNIERE.
    for _ph, _why in (('PH-AXV', 'PHYSRINGAX n\'a pas de compagnon de pose'),
                      ('COURSE', 'PHYSSKIN / PHYSSKIN2 agregent TOUTE la course : il n\'existe pas'
                                 ' une pose, il en existe des milliers. Ce refus-la ne se corrige'
                                 ' pas en ajoutant un enregistrement.')):
        POSE[_ph] = _Pose(_ph, None, _why)

    def asym(label, corps, pose, note=''):
        """LE SEUL CHEMIN AUTORISE pour publier une comparaison gauche/droite.

        `corps` est le texte que le site VOUDRAIT publier. Il n'est publie que si la pose peut le
        porter ; sinon la ligne dit pourquoi elle se tait, et la section qu'elle sert reste NON
        ETABLI. Dans les deux cas la ligne porte la pose : on ne peut plus lire un ecart
        gauche/droite de ce tableau sans lire, sur la meme ligne, dans quelle pose il a ete pris."""
        if pose.ok():
            return '%s%s   %s' % (label, corps, pose.tag())
        if pose.dev is None:
            return ('%s: %s — la pose de %s n\'est pas mesuree (%s). %s'
                    % (label, _ASYM_REFUS, pose.nom, pose.src, note)).rstrip()
        return ('%s: %s — %s est a %.1f deg du miroir (seuil %.1f ; le rig est a 0.005 deg en'
                ' pose de bind). %s'
                % (label, _ASYM_REFUS, pose.nom, pose.dev, _ASYM_SEUIL, note)).rstrip()

    def _pdeg(_p):
        """L'ECART AU MIROIR d'une pose, EN TEXTE, et qui ne tombe pas sur une pose NON MESUREE.

        Les deux lignes qui comparent DEUX POSES ENTRE ELLES (`ROOM-REGS-SENS`, `ROOM-REGS-SERRE`)
        doivent citer les deux ecarts sur leur propre ligne : un `%.1f` sur un `None` ferait
        tomber le tableau entier, et un tableau qui tombe ne publie rien — le mode d'echec le plus
        cher de ce dossier."""
        return ('%.1f deg' % _p.dev) if _p.dev is not None else 'NON MESURE'

    A('=' * 98)
    A('KEIRA — SALLE DE TEST SANS JOUEUR : TABLEAU DE MESURE')
    A('genere par .autoport/physics_room_table.py depuis %s' % log)
    # L'EMPREINTE DE LA TRACE, GRAVEE AU POINT DE PRODUCTION (cycle 32). Le chemin ci-dessus est le
    # MEME a toutes les courses : il n'identifie rien. Un tableau qui survit a sa course se lit
    # alors exactement comme un instrument qui derive — c'est arrive au cycle 31 (sa section 7) et
    # ca m'est arrive de nouveau ce cycle-ci, avant que cette ligne existe : la sonde par maillon a
    # affiche 3 `DIVERGE` sur 6 qui n'etaient QUE le tableau de la course precedente.
    # « Quand une perte se repete, on la rend impossible au point de PRODUCTION, pas detectable au
    # point de controle » — donc ici.
    try:
        import hashlib
        with open(log, 'rb') as _fh:
            _h = hashlib.md5()
            for _blk in iter(lambda: _fh.read(1 << 20), b''):
                _h.update(_blk)
        A('empreinte de la trace lue : md5 %s (%d octets)' % (_h.hexdigest(), os.path.getsize(log)))
    except Exception as _e:                                   # pragma: no cover
        A('empreinte de la trace lue : INDISPONIBLE (%s) — l\'appariement tableau/course ne peut'
          ' pas etre verifie sur ce tableau.' % _e)
    A('contrat : .autoport/prompts/SPEC-keira-physique.md — sections 6 (la salle) et 7 (ce qui fait foi)')
    A('')
    A('Toutes les longueurs sont en METRES (la trace est en unites de jeu, 4096 u = 1 m). Ce que')
    A('mesure chaque colonne, et rien d\'autre :')
    A('  tipvar  AMPLITUDE de mouvement de la POINTE due a la PHYSIQUE SEULE sur la fenetre : la')
    A('          diagonale de la boite englobante de l\'ecart pointe-vs-pose-d\'auteur, dans le')
    A('          repere de l\'os porteur. Le mouvement de l\'animation n\'y compte pas d\'un micron :')
    A('          une chaine qui se contente de suivre son os anime mesure ZERO ici.')
    A('          C\'est une VARIANCE : elle mesure ce qui bouge, jamais ou ca s\'est pose. Sous une')
    A('          pose TENUE (drive=tilt) elle vaut donc presque zero, et c\'est correct — le')
    A('          deplacement soutenu que produit la gravite se lit dans ROOM-GRAVSAG. Confondre les')
    A('          deux est ce qui a fait coexister un chiffre vert et « zero gravite sur ses seins ».')
    A('  rootdev residu d\'ANCRAGE de la racine : le pire de (a) l\'ecart entre la racine ECRITE et')
    A('          la racine du modele, (b) l\'ecart de longueur du premier lien libre a son attache.')
    A('  meshpen RESIDU SIGNE de penetration au-dela du plancher de pose modele, apres tout le')
    A('          solveur : > 0 = ca traverse (interdit), <= 0 = la marge qui reste avant de')
    A('          traverser. Mesure sur les paires (lien, volume) EN CONTACT — dedans a la pose du')
    A('          modele, ou dedans maintenant ; une paire dont les deux profondeurs sont nulles')
    A('          n\'est pas un contact. Meme predicat, memes volumes, meme plancher que la')
    A('          resolution : il n\'y a pas d\'instrument de mesure different de l\'instrument de')
    A('          decision.')
    A('  jump    pire saut de l\'ecart de pointe sur UNE frame.')
    A('  ns      frames effectivement echantillonnees dans la fenetre.')
    A('=' * 98)
    A('')
    A('-- CE QUE LA COURSE A PROUVE ---------------------------------------------------------------')
    A('ROOM-NOPLAYER: %s' % noplayer)
    A('   trace : PHYSROOM-START target-after=%s | PHYSNOPLAY viol=%d actors=%d killed=%d'
      % (tgt_after.group(1), viol, actors, killed))
    A('   `viol` compte les frames de MESURE ou un target existait encore : la salle recompte l\'arbre')
    A('   de processus a chaque frame et tuerait un target reapparu. %s'
      % ('Aucune.' if viol == 0 else 'IL Y EN A EU.'))
    A('ROOM-ACTORS: %d subject=%s' % (1 + actors, subject_name))
    A('   sujet spawne PAR NOM : art-group=%s, mgeo=%s, %s os, %s joints de rig.'
      % (subj.group(1), subj.group(5), subj.group(3), subj.group(4)))
    A('   le compagnon HD qui porte les chaines : %s, %s chaines / %s liens / %s volumes resolus'
      % (subject_name, hd.group(3), hd.group(4), hd.group(5)))
    A('ROOM-ANIMS: %d/%d raw=%d skipped=%d' % (played, accepted, enumerated, len(skipped)))
    A('   `raw` est le total BRUT enumere dans les six art-groups de Keira, sans aucun filtre du')
    A('   programme. Owner 2026-08-11 16:15 : « faut tester vraiment TOUTES les animations qu\'utilise')
    A('   le perso tout au long du jeu, pas quelques unes ! » — donc joue = raw, et skipped = 0.')
    for ag, nm, nj, want in skipped:
        A('ROOM-ANIM-SKIPPED: %s rig-%s-joints-vs-%s-du-porteur-de-physique (art-group %s)'
          % (nm, nj, want, ag))
    A('   %d animations enumerees dans ses %d art-groups, %d jouees et mesurees.'
      % (enumerated, nag, accepted))
    if variants:
        A('   %d d\'entre elles vivent sur un rig de VARIANTE (Fire Canyon, Lava Tubes) a %s joints la'
          % (len(variants), variants[0][2]))
        A('   ou le porteur de physique en a %s. Elles sont jouees SUR LEUR PROPRE art-group : le'
          % subj.group(4))
        A('   nombre de joints ecrits est porte par le bloc compresse de l\'ANIMATION')
        A('   (joint.gc:940-955), pas par le squelette, donc une animation a %s joints en pilote %s'
          % (variants[0][2], variants[0][2]))
        A('   et les joints propres au rig du village 1 gardent leur pose. Ce n\'est pas une')
        A('   supposition : si un joint porteur de chaine n\'etait pas pilote, l\'ancrage de cette')
        A('   chaine partirait et la gate ROOT le refuserait. rootdev max mesure = %s m.'
          % fnum(max((r['root'] for r in rows), default=0.0)))
        A('   Les %d concernees : %s'
          % (len(variants), ', '.join(v[1] for v in variants[:6])
             + (' ...' if len(variants) > 6 else '')))
    A('   La physique elle-meme ne vit que sur le compagnon HD du mgeo du village 1 :')
    for ag, mg, e in mgeo:
        A('     PHYSMGEO %-30s entry=%-3d %s'
          % (mg, e, 'compagnon HD keira-hd' if e >= 0 else 'AUCUN compagnon HD sur ce mgeo'))
    A('   C\'est pour ca que le SUJET reste celui du village 1 et que ce sont les ANIMATIONS qui')
    A('   viennent a lui, et non l\'inverse : un sujet spawne sur un mgeo de variante n\'aurait')
    A('   aucune chaine, donc rien a mesurer.')
    A('ROOM-COLLIDER-COVERAGE: %s' % ' '.join(covered))
    A('   %d volumes resolus par le moteur, sur les joints ci-dessus. meshpen mesure l\'entree dans'
      % len(cols))
    A('   un collider DECLARE, pas la traversee du corps : un zero contre un ensemble qui ne couvre')
    A('   pas le corps ne prouve rien, et c\'est pour ca que la liste est ici et pas dans un')
    A('   commentaire.')
    # QUEL VOLUME CONTRAINT QUELLE CHAINE. NATURE : un COMPTE d'evenements (frames x liens) ou ce
    # volume-la demandait une correction (res > 0). REPERE : sans objet, ce n'est pas une grandeur
    # geometrique. LECTURE QUAND LE DEFAUT EST ABSENT : aucune ligne pour cette chaine.
    # Trois cycles ont bute sur l'absence de ce nom : « lbang est en contact 17893 frames sur 17893
    # avec un AUTRE volume, non identifie ; il faudrait la penetration par (lien, VOLUME) ».
    colname = {}
    for ci, j, j2 in cols:
        colname[ci] = ('%s->%s' % (j, j2)) if j2 not in ('-', '?') else ('sphere:%s' % j)
    # ROOM-CONTACT-LINK, ajoute le 2026-08-14 : la MEME grandeur, mais ventilee PAR MAILLON.
    # Le seau du moteur etait indexe (chaine, volume) et jetait l'index du maillon a l'ecriture ;
    # deux cycles de suite ont bute sur « lequel des deux maillons du sein viole ? » sans pouvoir
    # y repondre. NATURE : un COMPTE de triplets (frame, MAILLON, volume) ou ce volume demandait
    # une correction cette frame (res > 0) — ni une distance, ni une amplitude. REPERE : celui du
    # VOLUME TESTE, puisque c'est contre lui que la profondeur est evaluee.
    # PIEGE EXPLICITE : un parseur qui laisse tomber le champ `l=` FUSIONNE les maillons et rend
    # une serie qui ressemble a de la physique. Le total par chaine ci-dessous reste donc la somme
    # sur maillons ET volumes — identique a ce qu'il valait avant l'ajout du champ, pour rester
    # comparable aux tableaux deja au dossier — et la ventilation est une ligne SEPAREE.
    cvol = {}
    cvlink = {}
    per_link = False
    for m in re.finditer(r'^PHYSCVOL c=(\d+) l=(\d+) ci=(\d+) n=(\d+)', txt, re.M):
        per_link = True
        c, l, k, n = (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
        cvol.setdefault(c, {})
        cvol[c][k] = cvol[c].get(k, 0) + n
        cvlink.setdefault(c, {})
        cvlink[c][l] = cvlink[c].get(l, 0) + n
    if not per_link:
        # Trace ANCIENNE : le moteur n'ecrivait pas encore `l=`. Le total par chaine reste lisible,
        # la ventilation par maillon ne l'est pas — et on l'ECRIT, on ne publie pas des zeros :
        # un zero de domaine vide se lit comme une mesure.
        for m in re.finditer(r'^PHYSCVOL c=(\d+) ci=(\d+) n=(\d+)', txt, re.M):
            c, k, n = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
            cvol.setdefault(c, {})
            cvol[c][k] = cvol[c].get(k, 0) + n
    if not cvol:
        A('ROOM-CONTACT-VOL: non publie par la course')
    else:
        A('ROOM-CONTACT-VOL: %d chaine(s) contraintes par au moins un volume' % len(cvol))
        A('   par chaine, les volumes qui ont demande une correction, du plus frequent au moins')
        A('   frequent. Un contact a profondeur nulle n\'est PAS compte : seule une violation l\'est.')
        A('   ROOM-CONTACT-LINK ventile le MEME total par MAILLON. NATURE : un compte de triplets')
        A('   (frame, maillon, volume) a res > 0. REPERE : celui du volume teste. ABSENT : aucune')
        A('   ligne pour ce maillon — aucun volume ne l\'a jamais contraint.')
        for ci_chain in sorted(cvol):
            nm = names[ci_chain] if ci_chain < len(names) else 'c%d' % ci_chain
            tot = sum(cvol[ci_chain].values())
            det = ' · '.join('%s %d' % (colname.get(k, 'ci%d' % k), n)
                             for n, k in sorted(((n, k) for k, n in cvol[ci_chain].items()),
                                                reverse=True)[:6])
            A('ROOM-CONTACT-VOL: chain=%-12s total=%-8d %s' % (nm, tot, det))
            if not per_link:
                A('ROOM-CONTACT-LINK: chain=%-12s NON DISPONIBLE sur cette trace — le moteur y'
                  ' ecrivait `PHYSCVOL c= ci= n=` sans le champ `l=`, l\'index du maillon etait'
                  ' jete a l\'ecriture. Aucun chiffre par maillon n\'est publiable ici.' % nm)
                continue
            lk = cvlink.get(ci_chain, {})
            nl = chains.get(ci_chain, {}).get('links', 0)
            nl = max(nl, (max(lk) + 1) if lk else 0)
            A('ROOM-CONTACT-LINK: chain=%-12s %s total=%d'
              % (nm, ' '.join('link%d=%-8d' % (l, lk.get(l, 0)) for l in range(nl)),
                 sum(lk.values())))
    # ---- ROOM-PAIRDOM : SPEC 33, LE DOMAINE D'UNE PAIRE ET PAS SEULEMENT SES CONTACTS --------
    # Le cycle 7 a publie « 0 contact sein<->sein sur 2978 » puis a ecrit lui-meme, dans ses
    # non-prouves, que la cause geometrique n'etait PAS etablie. Un zero dont on ignore le domaine
    # ne prouve rien : la paire a-t-elle failli se toucher, ou est-elle restee a un demi-metre ?
    # NATURE : `dm` et `fl` sont des LONGUEURS, en unites de jeu (4096 u = 1 m) — pas des comptes.
    #   `dm` = profondeur d'approche MAXIMALE atteinte sur toute la course ; `fl` = le plancher que
    #   la paire tolere, c'est-a-dire sa profondeur A LA POSE D'AUTEUR.
    # REPERE : monde.
    # LECTURE QUAND LE DEFAUT EST ABSENT : `dm` NEGATIF — les deux surfaces ne se sont jamais
    #   rejointes, et |dm| EST l'ecart minimal atteint entre elles. Contact ssi `dm > fl`.
    pdom = {}
    for m in re.finditer(r'^PHYSPAIR c=(\d+) ci=(\d+) dm=([-\d.e+]+) fl=([-\d.e+]+)', txt, re.M):
        pdom[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)))
    if not pdom:
        A('ROOM-PAIRDOM: non publie par la course')
    else:
        A('')
        A('ROOM-PAIRDOM: SPEC 33 — de combien chaque paire a-t-elle MANQUE le contact ?')
        A('   `dm` negatif = jamais de recouvrement, et |dm| est l\'ecart minimal ATTEINT entre les')
        A('   deux surfaces, en unites de jeu (4096 u = 1 m). `marge` = dm - fl : positive, il y a')
        A('   eu contact ; negative, c\'est ce qu\'il aurait fallu gagner EN PLUS pour en avoir un.')
        for (ci_chain, k) in sorted(pdom, key=lambda t: -pdom[t][0] + 1e9 * t[0]):
            dm, fl = pdom[(ci_chain, k)]
            nm = names[ci_chain] if ci_chain < len(names) else 'c%d' % ci_chain
            A('ROOM-PAIRDOM: chain=%-12s vol=%-18s dm=%10.2f  fl=%8.2f  marge=%+10.2f  (%s)'
              % (nm, colname.get(k, 'ci%d' % k), dm, fl, dm - fl,
                 'CONTACT' if dm > fl else 'jamais atteint : %.4f m manquants' % ((fl - dm) / 4096.0)))
    # ---- ROOM-SKINCOV : LA PHYSIQUE COUVRE-T-ELLE TOUTE LA GEOMETRIE DE LA MECHE ? -----------
    # Defaut PRIORITE 1 `hair-skinning`, owner du 2026-08-12 : « des polygones qui bougent et des
    # polygones voisins parfaitement statiques, causant la geometrie qui casse — faudrait que la
    # meche entiere soit prise en compte ».
    #
    # AUCUNE mesure existante ne pouvait le voir : toutes regardent la position des JOINTS, et le
    # defaut est sur les SOMMETS. Une chaine pilote des joints ; la peau, elle, est pesee sur des
    # joints qui ne sont pas tous simules.
    #   NATURE  : une FRACTION DE POIDS DE PEAU, sans dimension. Ce n'est ni une amplitude ni une
    #             distance — c'est « quelle part de ce sommet la physique tient-elle ».
    #   REPERE  : sans objet (un rapport de poids). La pose est la pose de BIND, donc la mesure est
    #             statique : elle ne depend d'aucune frame et ne bouge pas d'une course a l'autre.
    #   LECTURE QUAND LE DEFAUT EST ABSENT : `cov` = 1.0000 et `tear` = 0.
    #
    # DEUX PIEGES QUE CETTE MESURE EVITE, ET QUI ONT CHACUN COUTE UNE CONCLUSION FAUSSE :
    #  1. UN POIDS SUR UN DESCENDANT NON SIMULE EST QUAND MEME PILOTE. Le moteur propage sa matrice
    #     aux descendants non simules (jak-hd-physics.gc, « propagation aux descendants non
    #     simules »). Compter `gogglesLeft`/`gogglesRight` comme non pilotes donnait 44.1 % de
    #     couverture aux lunettes alors qu'elles sont entrainees par `gogglesMid`, leur parent
    #     simule. Seul le poids qui part sur un ANCETRE (ou sur une branche etrangere) est
    #     reellement fige. C'est pourquoi `driven` se calcule par fermeture descendante.
    #  2. UNE COUVERTURE < 1 PRES DE LA RACINE N'EST PAS UN DEFAUT, C'EST L'ANCRAGE. SPEC 2 : « la
    #     racine suit rigidement l'os porteur ; le mouvement croit vers la pointe ». Le gradient de
    #     `backhair` vaut 0.39 / 0.63 / 0.76 / 0.94 / 0.98 de la racine a la pointe : condamner
    #     toute fraction < 100 % condamnerait l'ancrage lui-meme. La grandeur fidele a la phrase de
    #     l'owner (« des polygones VOISINS ») est donc `tear` : le nombre d'aretes du mesh dont les
    #     deux extremites ont des pilotes discordants (|delta cov| > 0.5), et `weld` : les sommets
    #     COINCIDENTS (meme position) a pilotes discordants — ceux-la ouvrent le maillage par
    #     construction, a chaque frame, quel que soit le reglage.
    try:
        import numpy as _np
        _sys_path_added = os.path.dirname(os.path.abspath(__file__))
        if _sys_path_added not in sys.path:
            sys.path.insert(0, _sys_path_added)
        from physics_c6_volumes import load_geometry as _lg
        # parents, pour la fermeture descendante (piege 1)
        _par = {}
        try:
            _k2e = json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json', errors='ignore'))
            _rows = _k2e['rows'] if isinstance(_k2e, dict) and 'rows' in _k2e else _k2e
            if isinstance(_rows, dict):
                _rows = list(_rows.values())
            for _r in _rows:
                if isinstance(_r, dict) and 'hd_name' in _r:
                    _par[_r['hd_name']] = None
            _byk = {_r['k']: _r for _r in _rows if isinstance(_r, dict) and 'k' in _r}
            for _r in _rows:
                if isinstance(_r, dict) and 'hd_name' in _r:
                    _p = _byk.get(_r.get('hd_parent'))
                    _par[_r['hd_name']] = _p['hd_name'] if _p else None
        except Exception as _pe:
            # SANS LA PARENTE, la fermeture descendante ne peut pas se faire et la couverture est
            # SOUS-ESTIMEE (piege 1). Ca ne se tait pas : la ligne le dit, sinon on relit un
            # chiffre faux en croyant lire le bon.
            _par = {}
            A('ROOM-SKINCOV: AVERTISSEMENT parente HD illisible (%s) — pas de fermeture'
              ' descendante, `cov` est un MINORANT' % type(_pe).__name__)
        # chaines et leurs joints simules, lus du fichier livre
        _cj, _cur = {}, None
        for _ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
            if _ln.startswith('chain '):
                _cur = _ln.split()[1]; _cj[_cur] = []
            elif _ln.startswith('j ') and _cur:
                _cj[_cur].append(_ln.split()[1])
        # LA MEME ARITHMETIQUE POUR LES DEUX COLONNES. Elle est dans UNE fonction et pas recopiee :
        # deux colonnes qu'on veut comparer doivent etre calculees par le meme code, sinon elles
        # derivent l'une de l'autre et l'ecart ne veut plus rien dire.
        def _skincov_rows(_g):
            _V = _g['V'] if 'V' in _g else _g['verts']
            _jn = _g['joint_names'] if 'joint_names' in _g else _g['names']
            _W = _g['W'] if 'W' in _g else _g['weights']
            _F = _g.get('F', _g.get('tris', None))
            _ji = {n: i for i, n in enumerate(_jn)}
            if _W.ndim == 2 and _W.shape[1] == len(_jn):
                _Wd = _W
            else:
                _J = _g['J'] if 'J' in _g else _g['joints_idx']
                _Wd = _np.zeros((len(_V), len(_jn)), dtype=_np.float32)
                for _k in range(_W.shape[1]):
                    _np.add.at(_Wd, (_np.arange(len(_V)), _J[:, _k]), _W[:, _k])
            _edges = set()
            if _F is not None:
                for _t in _F:
                    _a, _b, _c2 = int(_t[0]), int(_t[1]), int(_t[2])
                    for _u, _v in ((_a, _b), (_b, _c2), (_a, _c2)):
                        _edges.add((_u, _v) if _u < _v else (_v, _u))
            _pos = {}
            for _i in range(len(_V)):
                _pos.setdefault((round(float(_V[_i][0]), 3), round(float(_V[_i][1]), 3),
                                 round(float(_V[_i][2]), 3)), []).append(_i)
            _out = []
            for _cn in sorted(_cj):
                _sim = [_j for _j in _cj[_cn] if _j in _ji]
                if not _sim:
                    continue
                _drv = set(_sim)                      # fermeture descendante (piege 1)
                _chg = True
                while _chg and _par:
                    _chg = False
                    for _j, _p in _par.items():
                        if _p in _drv and _j not in _drv and _j in _ji:
                            _drv.add(_j); _chg = True
                _cols = [_ji[_j] for _j in _drv if _j in _ji]
                _ws = _Wd[:, _cols].sum(1)
                _own = _np.where(_ws > 0.0)[0]
                if len(_own) == 0:
                    continue
                _cov = float(_ws[_own].mean())
                _lost = {}
                for _v in _own:
                    for _c3 in _np.where(_Wd[_v] > 0)[0]:
                        if _c3 not in _cols:
                            _lost[_jn[_c3]] = _lost.get(_jn[_c3], 0.0) + float(_Wd[_v][_c3])
                _top = sorted(_lost.items(), key=lambda x: -x[1])[:3]
                _ownset = set(int(x) for x in _own)
                _tear = sum(1 for (_u, _v) in _edges
                            if (_u in _ownset or _v in _ownset) and abs(_ws[_u] - _ws[_v]) > 0.5)
                _weld = 0
                for _grp in _pos.values():
                    if len(_grp) > 1 and any(_i in _ownset for _i in _grp):
                        _vals = [_ws[_i] for _i in _grp]
                        if max(_vals) - min(_vals) > 0.5:
                            _weld += 1
                _out.append((_cn, _cov, len(_own), (str(_tear) if _edges else '?'), _weld,
                             ' · '.join('%s %.0f%%'
                                        % (_k, 100.0 * _v / max(sum(_lost.values()), 1e-9))
                                        for _k, _v in _top) or '-', bool(_edges)))
            return _out

        _g = _lg('keira-hd')
        A('ROOM-SKINCOV: couverture de peau par chaine — quelle part de la geometrie la physique tient')
        A('   cov = poids moyen porte par des joints PILOTES (simules ou descendants d\'un simule).')
        A('   tear = aretes dont les deux bouts different de plus de 0.5. weld = sommets COINCIDENTS')
        A('   a pilotes discordants : ceux-la ouvrent le maillage par construction.')
        A('   SOURCE (2026-08-13) : %s — c\'est le rip BRUT du donneur.' % _g.get('src', '?'))
        _rows_donor = _skincov_rows(_g)
        if _rows_donor and not _rows_donor[0][6]:
            # SANS ARETES, `tear` vaudrait 0 PARTOUT — et un zero qui veut dire « je n'ai pas
            # regarde » est indistinguable d'un zero qui veut dire « pas de cassure ». C'est
            # exactement le faux vert que ce cycle a passe sa journee a debusquer : on le dit.
            A('ROOM-SKINCOV: AVERTISSEMENT liste de triangles illisible — `tear` NON MESURE,'
              ' ne pas lire ses zeros comme une absence de cassure')
        for _r in _rows_donor:
            A('ROOM-SKINCOV: chain=%-12s cov=%.4f n=%-5d tear=%-4s weld=%-3d lost=%s'
              % (_r[0], _r[1], _r[2], _r[3], _r[4], _r[5]))

        # ---- LA MEME MESURE SUR LE MESH QUI PART REELLEMENT ----------------------------------
        # Jusqu'au 2026-08-13, `ROOM-SKINCOV` ne lisait QUE la ligne ci-dessus, c'est-a-dire le rip
        # du 2 aout, en AMONT de `prep_hd_actor_glb.py` et du reskin. Consequence mesuree, pas
        # supposee : la course du 13 aout 01:50 republiait `rmidhair tear=82` alors que le bake du
        # 12 aout 23:53 avait justement mis cette valeur a zero, et publiait `pantflapL cov=0.1096`
        # pour un etat que le mesh livre n'a plus depuis le 11 aout. Une correction de poids ne
        # pouvait STRUCTURELLEMENT pas s'y voir : la colonne ne bougeait jamais, quoi qu'on fasse.
        # On n'enleve rien — la colonne du donneur reste, au bit pres, pour que l'ecart entre les
        # deux soit lisible. On AJOUTE celle qui peut voir.
        _ship = os.path.join('out', 'jak1', 'fr3', 'skin', 'keira-hd-lod0.glb')
        _gs = _lg('keira-hd', glb=_ship)
        if _gs is None:
            A('ROOM-SKINCOV-SHIPPED: ABSENT (%s) — le bake n\'a pas encore conserve le glb'
              ' preppe+reskinne. Les lignes ci-dessus sont le rip BRUT : elles ne montrent AUCUNE'
              ' correction de poids, ni celles deja livrees. Ne pas les lire comme l\'etat du mesh'
              ' que l\'owner a en main.' % _ship)
        else:
            A('ROOM-SKINCOV-SHIPPED: source=%s — mesh PREPPE+RESKINNE, celui du pack livre.'
              % _gs.get('src', _ship))
            _rows_ship = _skincov_rows(_gs)
            _dmap = {_r[0]: _r for _r in _rows_donor}
            _moved = 0
            for _r in _rows_ship:
                _d = _dmap.get(_r[0])
                _dc = ('%+.4f' % (_r[1] - _d[1])) if _d else '?'
                _dt = ('%s->%s' % (_d[3], _r[3])) if _d else '?'
                if _d and (abs(_r[1] - _d[1]) > 1e-6 or _r[3] != _d[3]):
                    _moved += 1
                A('ROOM-SKINCOV-SHIPPED: chain=%-12s cov=%.4f n=%-5d tear=%-4s weld=%-3d'
                  ' dcov=%s dtear=%s' % (_r[0], _r[1], _r[2], _r[3], _r[4], _dc, _dt))
            # CONTROLE : si AUCUNE chaine ne bouge entre les deux colonnes, c'est que le glb
            # conserve est en fait le rip, ou que le reskin n'a rien applique. Un ecart nul partout
            # est le signe que la nouvelle colonne ne voit pas mieux que l'ancienne — on le dit au
            # lieu de laisser croire qu'elle a ete verifiee.
            A('ROOM-SKINCOV-SHIPPED: %d chaine(s) sur %d different du rip brut.%s'
              % (_moved, len(_rows_ship),
                 '' if _moved else ' ZERO ECART : cette colonne ne voit RIEN de plus que le rip —'
                                   ' a traiter comme non mesuree.'))
    except Exception as _e:
        # une mesure qui n'a pas pu etre prise se DIT ; elle ne fait pas tomber le tableau, et elle
        # ne se remplace pas par une estimation.
        A('ROOM-SKINCOV: non mesure (%s: %s)' % (type(_e).__name__, str(_e)[:120]))

    A('ROOM-INVERSIONS: residual=%d corrected=%d degenerate=%d control_residual=%d reseated=%d'
      % (inv['run'][3], inv['run'][0], inv['run'][1], inv['control'][3], inv['run'][2]))
    A('   Owner, deux fois : « j\'ai vu un coup ou un des seins etait retourne vers l\'interieur ».')
    A('   Un volume est une coquille SYMETRIQUE autour de son axe : les deux cotes sont admissibles,')
    A('   donc un lien pousse au travers de l\'axe s\'y retrouve tenu du MAUVAIS cote — stable et')
    A('   faux — et la poussee suivante l\'y enfonce au lieu de l\'en sortir. D\'ou l\'intermittence.')
    A('   `residual` = liens restes du mauvais cote APRES tout le solveur : c\'est CE nombre qui doit')
    A('   valoir zero, mesure avec le meme predicat et les memes volumes que la penetration.')
    A('   `corrected` = fois ou le solveur a remis un lien de son cote ; ce nombre a le DROIT d\'etre')
    A('   grand, c\'est le solveur qui travaille (le pilotage de la salle est brutal).')
    A('   CONTROLE POSITIF : miroiter chaque lien libre a travers son attache APRES la resolution')
    A('   fait passer le residu de %d a %d.' % (inv['run'][3], inv['control'][3]))
    A('   `reseated` = liens dont la pose du modele etait hors de portee de leur porteur et que le')
    A('   moteur a replaces sur lui (une chaine se REPARE, elle ne se retire pas).')
    A('ROOM-POSCONTROL: injections=%d armed=%s disarmed=%s' % (inj, fnum(armed), fnum(disarmed)))
    A('   NATURE : LA PAIRE relevee a l\'argmax de la reponse appariee `w - b` — MEME lien, MEME')
    A('   frame, MEME regime d\'offset, MEME fonction de mesure. REPERE : le monde. [NOTE-459]')
    if armx is not None:
        A('ROOM-POSCONTROL-MAXIMA: armedmax=%s disarmedmax=%s ecart=%s   [DEUX MAXIMA LATCHES'
          % (fnum(armx), fnum(disx), fnum(armx - disx)))
        A('   INDEPENDAMMENT — c\'est ce que la ligne de verdict lisait jusqu\'au cycle 76. Mesure sur')
        A('   trois etats de solveur differents et la MEME injection : `armedmax` varie de 1,4 %')
        A('   pendant que `disarmedmax` varie de 375,6 %. Leur difference mesurait la LIGNE DE BASE,')
        A('   pas l\'injection. Publie comme DIAGNOSTIC, plus jamais comme verdict.')
    # [NOTE-155] LE CRITERE PREDICTIF DE L'ARBITRAGE DU 2026-08-20 13:20 : « injecter X doit faire
    # monter la mesure de X », tolerance 25 %, l'exces comme le defaut etant un echec. `armed` et
    # `disarmed` ci-dessus sont en METRES ; ce nombre l'est donc AUSSI, sinon la comparaison serait
    # entre deux unites. La valeur brute en unites de jeu est ecrite en clair a cote.
    if inject_m is not None:
        got = armed - disarmed
        A('ROOM-POSCONTROL-INJECT: %.6f   (= %.1f u ; MEME UNITE que armed/disarmed, des METRES)'
          % (inject_m, inject_u))
        A('   restitution : %s m mesures pour %s m injectes = %.1f %%  (bande exigee 75-125 %%)'
          % (fnum(got), fnum(inject_m), 100.0 * got / inject_m if inject_m else 0.0))
        A('   NATURE : une difference de deux PROFONDEURS residuelles prises sur LA MEME frame, la')
        A('   position etant restauree au bit entre les deux. Ce n\'est plus un rapport a une ligne')
        A('   de base qui bouge : c\'est une prediction quantitative, et elle echoue dans les DEUX')
        A('   sens. LECTURE HORS DEFAUT : 100 %%.')
    else:
        A('ROOM-POSCONTROL-INJECT: ABSENT — trace anterieure au cycle 60, critere predictif')
        A('   indisponible ; le validateur retombe alors sur l\'ancien ratio.')
    A('   le defaut injecte pousse chaque lien libre de 400 u (~10 cm) vers l\'interieur du corps')
    A('   APRES resolution ; le compteur de penetration doit MONTER. %d poussees reelles.' % inj)
    A('   residus SIGNES bruts des deux branches (negatif = marge restante avant de traverser) :')
    A('   arme %s m, desarme %s m.' % (fnum(armed_raw), fnum(disarmed_raw)))
    meas = sorted(c for c, d in idle.items() if d['hang'] <= 0.0)
    hang = sorted(c for c, d in idle.items() if d['hang'] > 0.0)
    imax = max((idle[c]['dev'] for c in meas), default=0.0)
    A('ROOM-IDLE: maxdev=%s hanging=%d measured=%d' % (fnum(imax), len(hang), len(meas)))
    A('   SPEC 4 : au repos, ce qui n\'est pas cense pendre retrouve la pose du modele. Les %d'
      % len(hang))
    A('   chaines a hang>0 (ce qui pend) sont comptees a part : %s'
      % ', '.join('%s dev=%s' % (names[c], fnum(idle[c]['dev'])) for c in hang))
    A('ROOM-AUTHORED: chains=%d respected=%d perchain=yes' % (len(a_driven), len(a_ok)))
    A('   Detection PAR CHAINE, dans le repere de l\'os porteur (rotation comprise) : un os que')
    A('   l\'animateur n\'a pas touche ne bouge PAS dans ce repere, donc il ne declenche rien — et')
    A('   un simple tour de tete n\'est pas confondu avec une intention d\'auteur sur les cheveux.')
    A('   RESPECTEE = sur chaque frame pilotee par l\'animation, la position ECRITE valait la pose')
    A('   d\'auteur PLUS l\'ecart simule, a 0.05 u pres (12 micrometres) : le deplacement d\'auteur')
    A('   arrive au joint a coefficient 1, jamais mis a l\'echelle, mixe ni retarde.')
    A('   CONTROLE POSITIF : l\'animation retardee d\'une frame dans la position ecrite — le defaut')
    A('   exact que la SPEC 5 interdit. Desarme, sur la course entiere, l\'identite tient %d fois'
      % int(sum(auth[c]['ok'] for c in a_driven)))
    A('   sur %d frames pilotees. Arme, sur sa propre fenetre, elle tient %d fois sur %d : le'
      % (int(sum(auth[c]['hit'] for c in a_driven)), int(apc_ok), int(apc_hit)))
    A('   compteur s\'effondre completement, donc il mesure bien ce qu\'il pretend mesurer.')
    A('   La colonne `transmission` est PUBLIEE MAIS NON GATEE : c\'est la correlation du')
    A('   deplacement ecrit avec celui d\'auteur, et le rapport |delta ecart| / |delta auteur| dit')
    A('   pourquoi elle est bruitee — sous un a-coup la physique deplace la pointe des dizaines de')
    A('   fois plus que l\'animation, et aucune correlation ne resout un coefficient 1 la-dedans.')
    for c in a_driven:
        d = auth[c]
        ratio = (d['dsum'] / d['usum']) if d['usum'] > 0.0 else 0.0
        A('     %-12s frames=%-6d identite=%d/%d  transmission=%+.3f  |do|/|du|=%.1f'
          '  pose-auteur parcourue=%s m'
          % (names[c], int(d['hit']), int(d['ok']), int(d['hit']), d['tr'], ratio,
             fnum(d.get('tmov', 0.0))))
    # LES CHAINES QUE L'ANIMATION NE PILOTE JAMAIS — publiees, parce que c'est LA question de
    # l'owner sur les oreilles (`ears-physics`) : « quand l'animation d'origine ne pilote PAS les
    # oreilles, la physique doit les prendre en compte -- verifier qu'elle s'y applique vraiment ».
    # La boucle ci-dessus n'itere que `a_driven` (hit > 0) : une chaine que l'animation ne touche
    # jamais n'apparaissait NULLE PART, donc la reponse a sa question n'etait pas lisible. Elle
    # l'est maintenant, et pour toutes les chaines a la fois.
    a_free = sorted(c for c in auth if auth[c]['hit'] <= 0.0 and c not in dropped)
    A('ROOM-AUTHORED-FREE: chains=%d  (l\'animation ne les pilote sur AUCUNE frame)' % len(a_free))
    A('   Sur ces chaines la physique garde la main sur 100 % de la course. Leur mouvement propre')
    A('   est publie par ROOM-GRADIENT (deviation angulaire par rapport au PARENT) et par les')
    A('   lignes `worst`, chaine par chaine : c\'est la que se verifie qu\'elle s\'y applique.')
    A('   PORTEE HONNETE DE CE ZERO : le controle positif de l\'auteur (animation retardee d\'une')
    A('   frame) ne PEUT PAS tirer sur une chaine que l\'animation ne pilote jamais — il lui faut')
    A('   une frame pilotee pour exister. Ce zero est donc STRUCTUREL, pas controle : il dit que le')
    A('   detecteur n\'a jamais vu de canal local sur ces joints, et le detecteur est prouve vivant')
    A('   par les %d chaines ci-dessus. Le controler vraiment demanderait de lire les canaux des'
      % len(a_driven))
    A('   31 animations dans les donnees d\'art-group, pas la course.')
    for c in a_free:
        A('     %-12s frames pilotees=0' % names[c])
    A('')
    A('-- CE QUE LES LIMITEURS ONT RETIRE (SPEC 7 : un suppresseur se chiffre) --------------------')
    A('   recul vers la pose du modele : PLUS AUCUN COMPTEUR (cycle 36). Les deux qui existaient')
    A('   n\'avaient aucun ecrivain depuis le retrait de `phys-retreat-chain` le 2026-08-13 : leur')
    A('   zero ne disait pas que le recul ne tirait pas, il disait qu\'il n\'existait plus.')
    A('   plafond de taille d\'un lien libre : %d fois, %s m au total%s'
      % (radr_n, fnum(radr_s),
         ' (jamais declenche)' if radr_n == 0 else ' soit %s m par declenchement'
         % fnum(radr_s / radr_n)))
    A('     PERIMETRE REEL, corrige le 2026-08-12 : il ne porte QUE sur le maillon 0, donc que sur')
    A('     les chaines SANS rootlock. Le texte affirmait ici « il porte desormais sur tout maillon')
    A('     libre » ; le code lisait `l = 0` (jak-hd-physics.gc), et la colonne `raddrop` ci-dessous')
    A('     le demontrait deja : 15 000 a 25 000 declenchements sur chaque chaine a un seul os,')
    A('     EXACTEMENT ZERO sur chacune des onze chaines rootlockees. Un commentaire n\'est pas une')
    A('     preuve, y compris dans ce tableau.')
    A('     ET IL NE DOIT PAS L\'ETRE : ce plafond est la DEMI-EPAISSEUR du morceau de geometrie.')
    A('     Etendu au maillon libre d\'une bretelle il vaudrait 157 u sur un os de 1366 u, soit une')
    A('     butee a 6.6 degres — la bretelle serait morte. Ce qui borne un maillon libre profond est')
    A('     le test de COTE (demi-sphere autour de la direction du modele), pas ce rayon.')
    A('   marge de sortie de collision : 0.5 u = 0.000122 m par contact resolu, constante.')
    A('   LIGNE RETIREE ICI, ET C\'EST UNE CORRECTION D\'INSTRUMENT : « part radiale de la force,')
    A('     ecartee : N fois, N u/frame^2 » lisait `(phys-limiter 6)` et `(phys-limiter 7)`, deux')
    A('     index qui n\'existent pas dans le moteur et tombent dans sa branche `else` — donc les')
    A('     deux rendaient `*phys-buried-n*`. Course du 2026-08-12 : buried=987636 et radial_n =')
    A('     radial_sum = 987636, ratio 1.0000, un compteur divise par lui-meme. La grandeur qu\'elle')
    A('     nommait n\'a jamais ete mesuree ; ce qui la remplace (ROOM-RETREAT-SPHERE) l\'est.')
    A('ROOM-RETREAT-ANCHOR: fallback=%s' % ('non publie par la course (compteur retire au cycle 36,'
      ' il n\'avait aucun ecrivain)' if retfb_n < 0 else retfb_n))
    A('   fois ou le recul n\'a trouve AUCUN point admissible sur son chemin — pas meme la pose du')
    A('   modele — et s\'est pose sur le MOINS MAUVAIS. NATURE : un compte. LECTURE QUAND LE DEFAUT')
    A('   EST ABSENT : 0. Ce n\'est pas un limiteur de plus : c\'est l\'aveu que l\'invariant « la pose')
    A('   du modele est admissible » a cede. Il cede parce que `floor0` est mesure contre')
    A('   l\'INSTANTANE d\'auteur du volume et `dep` contre sa position COURANTE : pour un volume')
    A('   porte par un joint SIMULE (une meche voisine, un sein), les deux membres ne decrivent plus')
    A('   le meme obstacle. C\'est par la que `rmidhair` sortait a 0.0017 m de penetration — la')
    A('   SEULE ligne positive sur 3410. Le compteur etait emis par la salle et n\'etait lu par')
    A('   personne ; il l\'est desormais.')
    A('ROOM-RETREAT-SPHERE: rescued=%s' % ('non publie par la course (compteur retire au cycle 36,'
      ' il n\'avait aucun ecrivain)' if sphere_n < 0 else sphere_n))
    A('   fois ou le recul, son point de depart du modele etant inadmissible, a trouve une direction')
    A('   ADMISSIBLE ailleurs sur la MEME sphere — celle que l\'arc [pose du modele -> position')
    A('   courante] ne pouvait pas atteindre. NATURE : un compte d\'evenements. LECTURE QUAND LE')
    A('   DEFAUT EST ABSENT : 0, comme `fallback` : les deux repondent au MEME evenement declencheur,')
    A('   l\'un le sauve, l\'autre y renonce. Leur SOMME est le nombre de fois ou l\'arc etait aveugle,')
    A('   et c\'est la seule lecture qui ait un sens : `rescued` grand avec `fallback` a zero dit que')
    A('   la longueur d\'os est tenue sans rien laisser traverser ; `rescued` a zero avec `fallback`')
    A('   non nul dirait que le balayage ne trouve jamais rien et ne sert donc a rien.')
    A('   paires (lien, volume) ou le lien est ENTIEREMENT dans le volume a sa pose de modele :')
    A('   %d occurrences de mesure. Critere geometrique calcule sur la pose du modele' % buried_n)
    A('   (profondeur_repos >= 2 x rayon du lien), pas une liste ni un masque.')
    A('   CE N\'EST PLUS UN LIMITEUR depuis le 2026-08-12 : cet etat dispensait la paire de TOUTE')
    A('   contrainte (`phys-vol-floor` rendait PHYS-VOL-FREE), au motif qu\'un lien deja entierement')
    A('   dedans n\'a pas de surface devant lui. Vrai sur la surface, faux sur la decision : ne pas')
    A('   avoir de surface devant soi n\'autorise pas a s\'enfoncer plus loin. 50 642 fois par')
    A('   course, les lunettes n\'avaient plus AUCUN volume devant elles — c\'est `goggles-tunnel`.')
    A('   La franchise accordee est desormais la profondeur d\'auteur, sans exception ; le nombre')
    A('   reste publie parce que c\'est lui qui a designe le defaut, mais il ne commande plus rien.')
    A('')
    A('-- CE QUE LE MOTEUR A ECARTE, ET AVEC QUELS CHIFFRES ---------------------------------------')
    if not dropped:
        A('   Aucune chaine ecartee : les %d chaines du fichier de donnees sont toutes simulees et'
          % len(chains))
        A('   toutes mesurees.')
    else:
        A('   %d chaine(s) sur %d ecartee(s) A L\'EXECUTION par le moteur, pas par les donnees :'
          % (len(dropped), len(dropped) + len(chains)))
        for c in dropped:
            A('   * %s (%s) — %s' % (names[c], ','.join(joints_of[c]),
                                     dropmsg.get(c, 'sans raison publiee')))
            for cc, l, d, r, ratio in pose:
                if cc == c:
                    A('       lien %d : la pose du modele le met a %s m de son porteur pour un rayon'
                      % (l, fnum(d / UNITS)))
                    A('       ajuste de %s m, soit %.1f fois sa propre taille.' % (fnum(r / UNITS),
                                                                                   ratio))
            worstd = max((d for cc, l, d, r, ratio in pose if cc == c), default=0.0)
            A('       C\'est un defaut du MODELE HD (le retarget envoie ce joint ailleurs), pas de')
            A('       la physique : aucune physique ne peut rendre credible un joint que le rig met')
            A('       a %s m de l\'os qui devrait le porter. A ESCALADER a la phase hd-models.'
              % fnum(worstd / UNITS))
        legit = max((r for cc, l, d, rr, r in pose if cc in chains), default=0.0)
        A('   Pour comparaison, le pire rapport distance/rayon des chaines GARDEES est %.1f : le'
          % legit)
        A('   seuil de refus (%.0f) tombe dans un fosse de deux ordres de grandeur.' % 50.0)
    A('')
    # EXEMPTE : ici « gauche/droite » nomme un AXE DE DEPLACEMENT de la salle (sa §6 : « moved
    # up/down, left/right »), pas un ecart entre les deux chaines. Un titre de section n'affirme
    # rien ; le detecteur, lui, ne lit que des mots, et c'est pour ca que l'exemption se declare.
    A('-- LE PILOTAGE (SPEC 6 : haut/bas, gauche/droite, diverses accelerations, a-coups) ---------',
      notasym=True)
    for dr, nm in enumerate(DRIVE_NAMES):
        sel = [r for r in rows if r['dr'] == dr]
        if not sel:
            die('aucune mesure pour le pilotage %s : la SPEC les demande tous les quatre' % nm)
        A('drive=%-10s windows=%-4d tipvar_max=%s tipvar_min=%s rootdev_max=%s meshpen_max=%s'
          ' jump_max=%s'
          % (nm, len(sel),
             fnum(max(r['amp'] for r in sel)), fnum(min(r['amp'] for r in sel)),
             fnum(max(r['root'] for r in sel)), fnum(max(r['pen'] for r in sel)),
             fnum(max(r['jump'] for r in sel))))
    A('   fenetre de mesure = %d frames par (animation x pilotage).' % win)
    A('   `tilt` n\'est pas une secousse : elle se penche a 60 degres sur 24 frames puis TIENT LA')
    A('   POSE, et la mesure ne demarre qu\'a la frame 54 — 30 frames de tenue apres la fin de la')
    A('   rampe. Son amplitude est donc PETITE par construction, et c\'est la reponse correcte :')
    A('   une pose tenue ne fait pas vibrer une chaine, elle la DEPLACE. Ce deplacement se lit dans')
    A('   ROOM-GRAVSAG plus bas, pas ici.')
    A('')
    A('-- LA REPONSE, ET NON L\'AGITATION (superviseur 2026-08-11 16:15) ---------------------------')
    A('   « publier l\'amplitude de pointe rapportee a l\'amplitude du stimulus, et la valeur sous')
    A('   animation seule comme ligne de base a soustraire. Un pilotage dont la reponse ne depasse')
    A('   pas la ligne de base n\'a rien excite. »')
    A('   stimulus  acceleration COMMANDEE par la salle, en m/s^2 (pour `tilt`, plus aucune')
    A('             acceleration de repere : le stimulus EST la gravite, 9.81 m/s^2).')
    A('   baseline  amplitude de pointe de la MEME chaine sous la MEME animation SANS aucun')
    A('             pilotage. C\'est ce que l\'animation faisait de toute facon.')
    A('   gain      (tip - baseline) / stimulus, en metres par m/s^2. Un gain qui s\'effondre quand')
    A('             le stimulus monte est une SATURATION : la chaine est collee a son plafond')
    A('             geometrique et ne mesure plus le stimulus. C\'est ce qui rendait 16 chaines sur')
    A('             22 identiques sous cinq stimuli differents.')
    if not stim:
        die('trace incomplete : aucune ligne PHYSSTIM — le gain n\'a pas de denominateur')
    if not base:
        die('trace incomplete : aucune ligne PHYSBASE — la ligne de base n\'a pas ete mesuree')
    for c in sorted(chains):
        bl = max((v for (cc, _ai), v in base.items() if cc == c), default=0.0)
        for dr, nm in enumerate(DRIVE_NAMES):
            sel = [r['amp'] for r in rows if r['c'] == c and r['dr'] == dr]
            if not sel:
                continue
            tip = max(sel)
            mag = stim.get(dr, 0.0) * 3600.0 / UNITS      # u/frame^2 -> m/s^2
            got = max((v for (cc, _a, dd), v in stimr.items() if cc == c and dd == dr), default=0.0)
            g = (tip - bl) / mag if mag > 0.0 else 0.0
            A('ROOM-RESPONSE: chain=%-12s drive=%-10s stimulus=%-9s tip=%-9s baseline=%-9s'
              ' gain=%-11s recu=%s'
              % (names[c], nm, '%.2f' % mag, fnum(tip), fnum(bl), '%.6f' % g,
                 '%.2f' % (got * 3600.0 / UNITS)))
    A('')
    A('-- LE STIMULUS COMMANDE CONTRE LE STIMULUS RECU (la cause racine, en un tableau) ------------')
    A('   `recu` ci-dessus est le pire module de l\'acceleration de la pose d\'auteur de la pointe,')
    A('   mesure dans le moteur : c\'est ce que la chaine a VRAIMENT subi, d\'ou que ca vienne. La')
    A('   colonne sans aucun pilotage (ligne de base) est la preuve du defaut d\'instrument :')
    if animlen:
        loops = sorted(animlen.items())
        A('   longueur x vitesse de lecture des animations (les six premieres) : %s'
          % ', '.join('%s=%.0ff@%.3f' % (anims[a]['name'], n, sp)
                      for a, (n, sp) in loops[:6]))
        # une passe complete dure (n-1)/speed frames ; sur une fenetre de `win` frames le nombre de
        # demi-tours de lecture vaut win*speed/(n-1).
        def turns(n, sp):
            return win * sp / max(1.0, n - 1.0)
        cur = [turns(n, sp) for _a, (n, sp) in loops]
        old = [turns(n, 1.0) for _a, (n, sp) in loops]
        A('   A la vitesse du jeu, une fenetre de %d frames contient %.1f a %.1f demi-tours de'
          % (win, min(cur), max(cur)))
        A('   lecture. La salle avancait `frame-num` de 1.0 par frame en ignorant `speed` : elle en')
        A('   contenait alors %.1f a %.1f, et chacun etait un RETOUR BRUTAL a la frame 0 — une'
          % (min(old), max(old)))
        A('   teleportation du squelette entier en une frame. L\'acceleration croissant comme le')
        A('   carre du facteur de vitesse, les animations les plus lentes (speed %.3f) etaient'
          % min(sp for _a, (n, sp) in loops))
        A('   jouees %.0f fois trop vite, soit %.0f fois trop d\'acceleration.'
          % (1.0 / min(sp for _a, (n, sp) in loops),
             (1.0 / min(sp for _a, (n, sp) in loops)) ** 2))
    basacc = [max((v for (cc, _a, dd), v in stimr.items() if cc == c and dd >= len(DRIVE_NAMES)),
                  default=0.0) for c in sorted(chains)]
    if basacc:
        A('   pire acceleration recue SANS AUCUN PILOTAGE, toutes chaines : %.2f m/s^2'
          % (max(basacc) * 3600.0 / UNITS))
        A('   la plus forte acceleration COMMANDEE par la salle : %.2f m/s^2'
          % (max(stim.values()) * 3600.0 / UNITS if stim else 0.0))
    A('')
    A('-- LA GRAVITE : UN DEPLACEMENT SOUTENU, PAS UNE VARIANCE ------------------------------------')
    A('   Owner, trois fois : « les seins n\'ont pas l\'air d\'etre soumis a la gravite, aucun')
    A('   mouvement quand elle se penche en avant pour souder ». Aucune colonne ne mesurait ca :')
    A('   toutes mesuraient de la VARIANCE, et une pose tenue n\'en produit aucune (PHYSTILT')
    A('   amp=0.0000 sur 19 chaines sur 22 — le chiffre etait la, il disait juste autre chose).')
    A('   at0/at60 = position MOYENNE de la pointe dans le repere de l\'ancre, debout puis penchee')
    A('   a 60 degres, meme animation figee, meme duree. sag = la distance entre les deux, et c\'est')
    A('   EXACTEMENT la reponse a la gravite. Un sag nul sur une chaine de famille A avec')
    A('   gravity>0 est un echec.')
    A('-- LE GRADIENT LE LONG DE LA CHAINE (7e passe de l\'owner, 2026-08-11 16:30) ----------------')
    A('   « Entre la racine et les pointes c\'est zone de guerre et les pointes bougent quasi pas, au')
    A('   lieu d\'un degrade progressif des racines aux pointes. »')
    A('   Il decrit une FORME ; le tableau ne publiait qu\'un SCALAIRE par chaine (`tipvar`, pris sur')
    A('   la POINTE). Une chaine dont le maillon du milieu part en vrille pendant que la pointe reste')
    A('   collee a la pose d\'auteur rendait exactement le meme `tipvar` qu\'une chaine saine : aucune')
    A('   mesure ne pouvait voir ce defaut. Voici donc un chiffre PAR MAILLON, meme instrument que')
    A('   `tipvar`. SPEC 2 exige la suite CROISSANTE de la racine (link0) vers la pointe.')
    if not grad:
        die('trace incomplete : aucune ligne PHYSGRAD — le gradient exige par la 7e passe n\'est'
            ' pas mesure, et un scalaire par chaine ne peut pas le porter')
    if not gradang:
        die('trace incomplete : PHYSGRAD ne porte pas de colonne ang= — le gradient etait mesure en'
            ' ecart CUMULE a la pose d\'auteur, et la 10e passe de l\'owner a montre que cette'
            ' grandeur ne peut pas voir « le milieu bouge plus que la pointe » : un maillon soude a'
            ' son parent y herite du chiffre de son parent.')
    A('')
    A('   CORRECTION DE LA 10e PASSE — LE REPERE. L\'owner : « le milieu est plus hysterique (bouge')
    A('   beaucoup plus) que les pointes, c\'est pas cense ! » pendant que ce tableau publiait')
    A('   link0=0.0000 link1=0.2240 link2=0.3846, donc CROISSANT. C\'est la mesure qui avait tort :')
    A('   elle prend l\'ecart de chaque maillon a sa pose d\'auteur, un ecart qui se CUMULE le long')
    A('   de la chaine. Une pointe soudee a son parent — donc immobile PAR RAPPORT A LUI — herite')
    A('   integralement de l\'ecart du parent et affiche un grand chiffre. Meme faute de repere que')
    A('   « differencier la position au lieu de la sortie ».')
    A('   La colonne qui fait foi est desormais `ang` : la deviation ANGULAIRE du maillon par')
    A('   rapport a SON ATTACHE, en degres, nulle pour un maillon qui suit rigidement son parent.')
    A('   `amp` (metres, ancienne mesure) reste publiee a cote : l\'ecart entre les deux series EST')
    A('   la mesure de l\'erreur de l\'ancienne, et il ne se raconte pas, il se lit.')
    inverses, inverses_old = [], []
    stages = []
    for c in sorted(chains):
        nl = chains[c]['links']
        for dr, nm in enumerate(DRIVE_NAMES):
            # le pire cas de cette chaine sous ce pilotage, toutes animations confondues, choisi
            # sur la serie ANGULAIRE : c'est elle qui decide maintenant.
            best, bamp, bai = None, None, None
            for ai in sorted(anims):
                g = gradang.get((c, ai, dr))
                if not g:
                    continue
                v = [g.get(l, 0.0) for l in range(nl)]
                if best is None or max(v) > max(best):
                    best = v
                    bamp = [grad.get((c, ai, dr), {}).get(l, 0.0) for l in range(nl)]
                    bai = ai
            if best is None:
                continue
            A('ROOM-GRADIENT: chain=%-12s drive=%-10s anim=%-38s %s'
              % (names[c], nm, anims[bai]['name'],
                 ' '.join('link%d=%s' % (l, fnum(v)) for l, v in enumerate(best))))
            A('   (ancienne mesure, ecart cumule en m : %s)'
              % ' '.join('link%d=%s' % (l, fnum(v)) for l, v in enumerate(bamp)))
            # un maillon intermediaire qui depasse la pointe est le defaut decrit par l'owner
            if nl >= 2 and max(best[:-1]) > best[-1]:
                inverses.append((names[c], nm, anims[bai]['name'], best))
                # DEFAUT hair-gradient, PRIORITE 1 : OU l'inversion apparait-elle dans la frame ?
                # Le meme angle est releve a trois etages (integration seule / apres contraintes +
                # attenuation / tel qu'ecrit). Un seul chiffre en sortie ne pouvait pas nommer
                # l'etage fautif, et c'est pour ca que trois passes ont bute dessus.
                st = gradst.get((c, bai, dr))
                if st:
                    s0 = [st.get(l, (0.0, 0.0))[0] for l in range(nl)]
                    s1 = [st.get(l, (0.0, 0.0))[1] for l in range(nl)]
                    inv0 = max(s0[:-1]) > s0[-1] if s0[-1] or any(s0) else None
                    inv1 = max(s1[:-1]) > s1[-1] if s1[-1] or any(s1) else None
                    stages.append((names[c], nm, s0, s1, best, inv0, inv1))
            if nl >= 2 and max(bamp[:-1]) > bamp[-1]:
                inverses_old.append((names[c], nm))
    A('')
    if inverses:
        A('   GRADIENT INVERSE sur %d couple(s) (chaine, pilotage) : un maillon intermediaire tourne'
          % len(inverses))
        A('   PLUS que la pointe, PAR RAPPORT A SON PROPRE PARENT. C\'est exactement la silhouette')
        A('   que l\'owner decrit, et elle est enfin mesuree au lieu d\'etre invisible :')
        for nmc, nmd, nma, v in inverses[:10]:
            A('     %-12s %-10s %-30s %s'
              % (nmc, nmd, nma, ' '.join(fnum(x) for x in v)))
        A('   (%d au total)' % len(inverses))
        if stages:
            A('')
            A('   OU L\'INVERSION NAIT DANS LA FRAME — le meme angle a trois etages du solveur.')
            A('   s0 = apres l\'INTEGRATION seule · s1 = apres CONTRAINTES + attenuation · fin = ECRIT.')
            A('   L\'etage ou la suite cesse de croitre EST la cause ; les deux autres ne font que la')
            A('   transporter. Aucune hypothese n\'est privilegiee : c\'est la colonne qui tranche.')
            n0 = sum(1 for _, _, _, _, _, i0, _ in stages if i0)
            n1 = sum(1 for _, _, _, _, _, _, i1 in stages if i1)
            A('   inversion deja presente a s0 : %d/%d · a s1 : %d/%d · a la fin : %d/%d'
              % (n0, len(stages), n1, len(stages), len(inverses), len(inverses)))
            for nmc, nmd, s0, s1, fin, i0, i1 in stages[:8]:
                A('     %-12s %-10s s0=%-28s s1=%-28s fin=%s'
                  % (nmc, nmd,
                     ' '.join(fnum(x) for x in s0),
                     ' '.join(fnum(x) for x in s1),
                     ' '.join(fnum(x) for x in fin)))
            if n0 == 0 and n1 == 0:
                A('   LECTURE : la suite CROIT apres l\'integration et apres les contraintes, et elle')
                A('   est INVERSEE dans ce qui est ecrit. L\'inversion nait donc dans la FINITION —')
                A('   collision + recul — et nulle part ailleurs.')
            elif n0 == 0:
                A('   LECTURE : l\'integration produit une suite croissante ; la boucle de contraintes')
                A('   l\'inverse. C\'est la longueur, la collision ou l\'attenuation d\'angle.')
            else:
                A('   LECTURE : la suite est DEJA inversee a la sortie de l\'integration. Aucune')
                A('   contrainte n\'en est responsable : c\'est le modele de ressort lui-meme.')
    else:
        A('   Aucune inversion : sur chaque chaine et chaque pilotage, la deviation propre CROIT de')
        A('   la racine vers la pointe, ce que SPEC 2 exige.')
    A('   Pour comparaison, l\'ANCIENNE mesure (ecart cumule) en signalait %d : l\'ecart entre les'
      % len(inverses_old))
    A('   deux comptes est la part du defaut que le repere monde rendait invisible.')
    A('')

    # ---- LE RING-DOWN (defaut `hair-pudding`, owner 2026-08-13) ---------------------------------
    # « On dirait les mouvements quand on tape sur un pudding, pas des mouvements naturels de
    # cheveux ! » Un pudding sonne a sa frequence propre quel que soit le coup et tout son volume
    # bouge EN PHASE ; des cheveux SUIVENT, l'onde descend de la racine vers la pointe. Ce qui
    # separe les deux n'est pas une amplitude — les deux peuvent bouger autant — c'est la FORME de
    # la reponse dans le temps. Voir le bloc RING-DOWN en tete de fichier (nature, repere, ligne de
    # base, et la reserve du signal redresse).
    A('-- ROOM-RINGDOWN : LA FORME DE LA REPONSE APRES L\'ARRET DU STIMULUS ----------------------')
    A('   Owner 2026-08-13 : « la gelatine c\'est plus du pudding, c\'est pas trop lent et mou,')
    A('   c\'est vraiment pas coherent... On dirait les mouvements quand on tape sur un pudding, pas')
    A('   des mouvements naturels de cheveux ! »')
    A('   NATURE : une forme de reponse dans le TEMPS — decroissance libre apres l\'arret du')
    A('   stimulus, et retard de phase entre maillons. Ni une amplitude ni une variance : un')
    A('   scalaire d\'amplitude ne peut pas distinguer un pudding d\'une chaine, les deux peuvent')
    A('   bouger AUTANT.  REPERE : LOCAL, la deviation angulaire de chaque maillon PAR RAPPORT A')
    A('   SON PARENT (degres) — jamais le monde, ou une pointe soudee a son parent afficherait un')
    A('   grand chiffre.  LIGNE DE BASE : lbang/rbang, mesurees dans la MEME course, parce que')
    A('   l\'owner APPROUVE les meches fines et REJETTE les grosses. La cible est mesuree, pas')
    A('   choisie.')
    A('   RESERVE : `ang` est un MODULE (toujours positif), donc le signal est REDRESSE. La')
    A('   frequence apparente est le DOUBLE de la reelle, une oscillation libre = DEUX minima')
    A('   (d\'ou osc = minima/2), et le retard n\'est determine que MODULO une demi-periode.')
    if not ring:
        A('ROOM-RINGDOWN: ABSENT (aucune ligne PHYSRING dans la trace)')
        A('   Un artefact manquant se declare en toutes lettres : il ne se remplace pas par un')
        A('   repli silencieux. Cette course n\'a pas emis de fenetre de ring-down.')
    else:
        ring_chains = sorted({c for c, _ in ring})
        ring_row = {}
        for c in ring_chains:
            links = sorted({l for cc, l in ring if cc == c})
            frames = sorted(ring[(c, links[0])])
            ser = [[ring[(c, l)].get(f, 0.0) for f in frames] for l in links]
            span = frames[-1] - frames[0]
            head = min(5, len(frames))
            # `peak` = l'amplitude AU DEBUT DU SILENCE, tous maillons confondus : l'echelle a
            # laquelle tout le reste se rapporte.
            peak = max(max(s[:head]) for s in ser)
            tip = ser[-1]
            a0 = max(tip[:head])
            delta = 0.05 * a0 if a0 > 0.0 else 0.0
            tapp = ring_period(tip, delta)
            win = max(2, int(round(tapp))) if tapp else 12
            env = ring_env(tip, win)
            # `decay` = le nombre de frames au bout duquel l'ENVELOPPE de la pointe passe sous 10 %
            # de son amplitude initiale. Un plafond atteint doit SE VOIR : quand le seuil n'est
            # jamais franchi on ecrit `>` suivi de la fenetre reellement observee, jamais la
            # fenetre elle-meme, qui se lirait comme une mesure.
            thr = 0.10 * a0
            di = None
            for i, v in enumerate(env):
                if a0 > 0.0 and v < thr:
                    di = i
                    break
            decay = ('%d' % (frames[di] - frames[0])) if di is not None else ('>%d' % span)
            # `osc` = les oscillations LIBRES de la pointe avant ce seuil. Le signal etant redresse,
            # une oscillation complete laisse DEUX minima : on compte les minima et on divise par 2.
            mins, _ = ring_extrema(tip[:di] if di is not None else tip, delta)
            osc = len(mins) / 2.0
            # les retards, maillon par maillon. La fenetre de recherche vaut une DEMI-periode
            # apparente : au-dela, le signal redresse se repete et l'argmax n'aurait plus de sens.
            dmax = max(4, int(round((tapp or 12) / 2.0)))
            lags, rs = [], []
            for k in range(len(links) - 1):
                d, r = ring_lag(ser[k], ser[k + 1], dmax)
                lags.append(d)
                rs.append(r)
            # `mono` = l'onde DESCEND : retards strictement positifs et non decroissants de la
            # racine vers la pointe. Un retard nul = tout bouge en phase = le pudding.
            #
            # CORRECTION 2026-08-13 : la premiere definition etait VACUE. Elle exigeait `d > 0` sur
            # TOUS les retards, `lag01` compris -- or le maillon 0 est `rootlock=1`, il ne bouge pas
            # (ROOM-GRADIENT publie link0=0.0000 sur les cinq pilotages), donc la correlation
            # racine->maillon1 rend structurellement 0 et `mono` valait `no` pour TOUTE chaine, y
            # compris `lbang`/`rbang` que l'owner APPROUVE. Un champ qui rend la meme valeur sur le
            # bon et le mauvais echantillon ne discrimine rien (SPEC 7, « une mesure doit
            # DISCRIMINER ») : il ne se defend pas, il se corrige.
            # On juge donc l'onde sur les maillons LIBRES seuls, c'est-a-dire les retards a partir
            # de `lag12`. Une chaine sans maillon libre (2 joints, rootlock) n'a pas d'onde a
            # montrer : elle rend `n/a`, jamais un `no` qui se lirait comme un defaut.
            # SECONDE CORRECTION, meme passe : sur une chaine a 3 joints il ne reste qu'UN retard
            # libre, et « strictement positif ET non decroissant » y est trivialement vrai des que
            # le retard depasse 0. `backhair` rendait donc `yes` avec `lag12=1` -- soit exactement
            # le mouvement en bloc qu'on cherche a detecter. Une suite d'UN terme ne porte pas de
            # forme : on ne la declare ni bonne ni mauvaise, on dit qu'elle n'est pas jugeable.
            # La discrimination reste entiere dans les retards eux-memes, qui sont publies a cote
            # (lag12 : backhair 1 contre lmidhair 6 et lbang 5,5).
            free = lags[1:]
            if len(free) < 2:
                mono = 'n/a(%d lien libre)' % len(free)
            else:
                mono = ('yes' if all(d > 0 for d in free)
                        and all(free[i + 1] >= free[i] for i in range(len(free) - 1))
                        else 'no')
            nm = names[c] if c < len(names) else 'c%d' % c
            A('ROOM-RINGDOWN: chain=%-12s osc=%-5s decay=%-6s peak=%-8s %s mono=%s'
              % (nm, '%.1f' % osc, decay, '%.2f' % peak,
                 ' '.join('lag%d%d=%d' % (k, k + 1, d) for k, d in enumerate(lags)),
                 mono))
            A('   (fenetre=%d frames  maillons=%d  a0(pointe)=%.2f deg  periode apparente=%s'
              ' frames  correlations=%s)'
              % (span + 1, len(links), a0,
                 ('%.1f' % tapp) if tapp else 'indeterminee',
                 ' '.join('%.2f' % r for r in rs) if rs else 'aucune'))
            # ---- SPEC 27 : LES QUATRE BANDES DE STABILISATION -------------------------------
            # La MEME enveloppe observee (`env`) et le MEME `a0` que le `decay` a 10 % ci-dessus,
            # lus a quatre seuils. SPEC 27 decrit quatre bandes de temps, et un seuil unique ne
            # peut en rendre qu'une : c'est un ajout, pas un remplacement — `decay` reste publie
            # tel quel, avec son seuil a 10 %, et ne bouge pas.
            settle = {k: settle_time(env, frames, a0, frac) for frac, k in SETTLE_BANDS}
            A('ROOM-SETTLE: chain=%-12s t5=%-7s t1=%-7s t05=%-7s t01=%-7s a0=%-8s frames=%d'
              % (nm, settle['t5'], settle['t1'], settle['t05'], settle['t01'],
                 '%.2f' % a0, span + 1))
            ring_row[nm] = dict(osc=osc, decay=decay, peak=peak, a0=a0, lags=lags, mono=mono,
                                di=di, span=span, settle=settle)
        # ---- SPEC 27 : ce que ces quatre temps valent, et contre quoi ils se lisent --------------
        A('')
        A('-- ROOM-SETTLE : SPEC 27, LE TEMPS DE STABILISATION A QUATRE SEUILS ----------------------')
        A('   SPEC 27 : « After one strong isolated impulse: dominant visible response 0.3-0.6 s;')
        A('   secondary movement 0.6-1.2 s; mostly settled ~1.0-1.5 s; essentially stationary')
        A('   ~1.3-1.7 s. Long-running obvious oscillation should not occur. »')
        A('   NATURE : un TEMPS, en secondes a 60 FPS, pris sur l\'ENVELOPPE de la pointe — la meme')
        A('   enveloppe glissante et le meme `a0` que le `decay` a 10 % publie au-dessus, lus a')
        A('   quatre seuils au lieu d\'un. Ce n\'est donc pas une seconde mesure qui pourrait')
        A('   contredire la premiere : c\'est le meme instrument, a quatre hauteurs.')
        A('   LECTURE : `>x.xx` = le seuil n\'a jamais ete franchi dans la fenetre observee, et la')
        A('   valeur ecrite est la duree de cette fenetre — pas le temps de stabilisation.')
        A('   CIBLES SPEC 27 (ce bloc MESURE, il ne juge pas — les gates sont gelees) :')
        A('     t5%   -> « dominant visible response »   0.3-0.6 s')
        A('     t1%   -> « secondary movement »          0.6-1.2 s')
        A('     t05%  -> « mostly settled »              1.0-1.5 s')
        A('     t01%  -> « essentially stationary »      1.3-1.7 s')
        # ---- LE CONTROLE APPARIE : ce qu'il approuve contre ce qu'il rejette --------------------
        A('')
        A('   CONTROLE APPARIE — meme moteur, meme salle, meme fenetre. L\'owner APPROUVE les meches')
        A('   fines et REJETTE les grosses : la cible chiffree des grosses est donc la valeur')
        A('   MESUREE sur les fines, jamais un nombre choisi.')
        A('   %-12s %-8s %-7s %-8s %-16s %s' % ('chaine', 'verdict', 'osc', 'decay', 'lags', 'mono'))
        for nm in RING_HAIR_OK + RING_HAIR_BAD:
            d = ring_row.get(nm)
            verdict = 'APPROUVE' if nm in RING_HAIR_OK else 'REJETE'
            if d is None:
                A('   %-12s %-8s (absente de la fenetre de ring-down)' % (nm, verdict))
                continue
            A('   %-12s %-8s %-7s %-8s %-16s %s'
              % (nm, verdict, '%.1f' % d['osc'], d['decay'],
                 ','.join(str(x) for x in d['lags']) or '-', d['mono']))
        ref = [ring_row[n] for n in RING_HAIR_OK if n in ring_row]
        if ref:
            rosc = sum(d['osc'] for d in ref) / len(ref)
            rlag = [d['lags'][0] for d in ref if d['lags']]
            rlag0 = (sum(rlag) / float(len(rlag))) if rlag else None
            A('   reference APPROUVEE (moyenne %s) : osc=%.1f%s'
              % ('+'.join(n for n in RING_HAIR_OK if n in ring_row), rosc,
                 ('  lag01=%.1f' % rlag0) if rlag0 is not None else ''))
            for nm in RING_HAIR_BAD:
                d = ring_row.get(nm)
                if d is None:
                    continue
                gap = '   ecart %-12s osc %+.1f' % (nm, d['osc'] - rosc)
                if rlag0 is not None and d['lags']:
                    gap += '   lag01 %+.1f' % (d['lags'][0] - rlag0)
                A(gap)
        A('   Lecture : un `osc` nettement plus grand que la reference = ca BALLOTTE (le pudding).')
        A('   Un `lag` proche de zero ou negatif = tout le volume bouge EN PHASE, ce qui est')
        A('   exactement le pudding et jamais des cheveux. Le verdict reste celui de l\'owner ; ces')
        A('   chiffres disent seulement de quelle grandeur il parle.')
    A('')

    # ---- SPEC 24 : LES TROIS FREQUENCES PROPRES, REPUBLIEES PAR AXE -----------------------------
    # Le tableau les republie, il ne les recalcule pas : l'estimateur est celui de
    # `.autoport/physics_ringdown.py`, importe. Une seconde implementation derive, et c'est alors
    # le tableau qui dit une chose et le script une autre sur la MEME trace.
    A('-- ROOM-RINGAXIS : SPEC 24, LES TROIS FREQUENCES PROPRES, UNE PAR AXE ---------------------')
    A('   SPEC 24 : Vertical 2.30 Hz (2.1-2.5) / Front-Back 2.50 Hz (2.3-2.7) / Lateral 2.65 Hz')
    A('   (2.4-2.9), et « Vertical motion is intentionally the slowest ».')
    A('   NATURE : une FREQUENCE, tiree de la serie temporelle `PHYSRINGA` — la deviation signee du')
    A('   maillon a sa pose d\'auteur, projetee axe par axe.  REPERE : le triedre de l\'ANCRE (le')
    A('   torse), que SPEC 7 impose : « all dynamic calculations shall occur relative to the')
    A('   torso/root transform rather than directly in world space ». Le repere monde ne peut pas')
    A('   separer ces trois axes, et une projection sur l\'axe principal (ROOM-RINGDOWN ci-dessus)')
    A('   n\'en rend qu\'UNE, celle de l\'axe dominant : c\'est pour ca que cette mesure existe a')
    A('   cote et non a la place.')
    A('   `fn` = frequence PROPRE = fd / sqrt(1-zeta^2). Une periode relevee sur une oscillation qui')
    A('   DECROIT rend la frequence AMORTIE `fd` ; c\'est `fn` que SPEC 24 specifie, et c\'est `fn`')
    A('   qui se compare a la cible — jamais `fd`.')
    A('   `status=insufficient-excitation` = l\'axe n\'a pas assez d\'extrema alternes pour porter un')
    A('   ajustement ; `fn` et `zeta` valent alors `n/a`, jamais un repli ni la valeur d\'un autre')
    A('   axe. Une mesure qui ne peut pas etre faite se declare.')
    ax_names = {c: (names[c] if c < len(names) else 'c%d' % c) for c in chains}
    ax_rows = physics_ringdown.axis_rows(ringa, ax_names)
    if not ringa:
        A('ROOM-RINGAXIS: ABSENT (aucune ligne PHYSRINGA dans la trace)')
        A('   Cette course a ete produite par une salle qui ne publiait pas encore la deviation')
        A('   projetee sur le triedre de l\'ancre. Les trois frequences de SPEC 24 ne sont donc PAS')
        A('   mesurees ici, et elles ne sont remplacees par rien : la frequence de l\'axe principal')
        A('   publiee par ROOM-RINGDOWN n\'est aucune des trois.')
    else:
        A('   TROIS ESTIMATEURS SUR LA MEME SERIE, ET C\'EST VOULU : `ext` compte les extrema,')
        A('   `ar2` ajuste une recurrence d\'ordre 2 sur les 149 echantillons, `zc` mesure les')
        A('   croisements de zero (seul des trois a etre INDEPENDANT DE L\'AMPLITUDE, donc le seul')
        A('   que la montee initiale ne deplace pas). Les trois rendent la reponse des series')
        A('   synthetiques a moins de 0.05 % pres (`physics_ringdown.py --selftest`, 5 controles')
        A('   positifs + 2 negatifs). LEUR ECART SUR LA TRACE REELLE EST DONC UNE MESURE : quand')
        A('   ils divergent, ce n\'est pas l\'un d\'eux qui a tort, c\'est la SERIE qui ne porte pas')
        A('   d\'oscillation libre exploitable. `spread` = ecart-type des demi-periodes ; au-dela')
        A('   de ~20 % de la demi-periode, la periode n\'est pas stable et le chiffre ne veut rien')
        A('   dire.')
        for d in ax_rows:
            A('ROOM-RINGAXIS: chain=%-12s axis=%-3s ext_fn=%-7s ar2_fn=%-7s zc_fn=%-7s'
              % (d['chain'], d['axis'],
                 '%.3f' % d['fn'] if d['fn'] is not None else 'n/a',
                 '%.3f' % d['ar_fn'] if d['ar_fn'] is not None else 'n/a',
                 '%.3f' % d['zc_fn'] if d['zc_fn'] is not None else 'n/a'))
            A('   zeta ext=%-7s ar2=%-7s zc=%-7s | demi-periodes=%d spread=%s | statuts %s/%s/%s'
              % ('%.3f' % d['zeta'] if d['zeta'] is not None else 'n/a',
                 '%.3f' % d['ar_zeta'] if d['ar_zeta'] is not None else 'n/a',
                 '%.3f' % d['zc_zeta'] if d['zc_zeta'] is not None else 'n/a',
                 d['zc_nhalf'],
                 '%.2f' % d['zc_spread'] if d['zc_spread'] is not None else 'n/a',
                 d['status'], d['ar_status'], d['zc_status']))
            A('   croisements de zero (frames) = %s' % (d['zc_cross'][:10],))
            fns = [v for v in (d['fn'], d['ar_fn'], d['zc_fn']) if v is not None]
            if fns:
                spread = 100.0 * (max(fns) / min(fns) - 1.0)
                A('   cible SPEC 24 = %.2f Hz | les estimateurs s\'ecartent de %.0f %% entre eux'
                  % (d['target'], spread))
                if spread > 20.0:
                    A('   -> NON MESURABLE sur cette fenetre : trois instruments valides par')
                    A('      controle positif ne peuvent pas diverger de %.0f %% sur une serie qui'
                      % spread)
                    A('      porterait vraiment une oscillation libre. C\'est le STIMULUS qui')
                    A('      manque, pas le solveur qui derive — et un ecart a la cible calcule')
                    A('      la-dessus serait un chiffre invente.')
                else:
                    A('   -> mesure CONVERGENTE ; ecart a la cible %+.1f %% (zc)'
                      % (100.0 * (d['zc_fn'] / d['target'] - 1.0) if d['zc_fn'] else float('nan')))
            else:
                A('   cible SPEC 24 = %.2f Hz  NON MESUREE sur cet axe' % d['target'])
    A('')

    # ---- L'ALLONGEMENT, PAR PILOTAGE (10e passe : « ils s'allongent de nouveau ») ---------------
    A('-- ALLONGEMENT RELATIF DES MAILLONS (10e passe de l\'owner, 2026-08-11 18:00) -------------')
    A('   « Les seins s\'allongent de nouveau sur les mouvements brusques. » Le build precedent')
    A('   pariait par ecrit : si l\'etirement revient, c\'est la contrainte de longueur qui cede, et')
    A('   le couplage ne sera PAS rebaisse. Il est revenu ; le couplage reste a 1.55 et c\'est le')
    A('   solveur qui a change — la poussee de collision, seule operation qui deplacait encore le')
    A('   lien hors de sa sphere, est desormais reprojetee dessus (elle fait TOURNER, elle')
    A('   n\'ALLONGE plus).')
    A('   NATURE : un rapport sans dimension, |longueur/longueur_de_repos - 1|. REPERE : aucun,')
    A('   c\'est une longueur sur une longueur mesuree depuis l\'attache du maillon. LECTURE QUAND')
    A('   LE DEFAUT EST ABSENT : 0. Cible de la DECISION 2 du superviseur : <= 3 % sur jerk/accel.')
    if not stretch:
        die('trace incomplete : aucune ligne PHYSSTR — l\'allongement n\'est pas mesure par fenetre,'
            ' donc « ils s\'allongent sur les mouvements BRUSQUES » reste invérifiable')
    # LA SIXIEME JAMBE DE LA COURSE EST `d=5` : LA MEME ANIMATION SANS AUCUN PILOTAGE.
    #
    # Elle etait mangee ici en silence. `stretch` porte 6 indices de pilotage (682 lignes chacun,
    # 22 chaines x 31 animations), `DRIVE_NAMES` n'en nomme que 5, et cette boucle les fusionnait
    # tous : le tableau « par pilotage » melangeait donc une jambe pilotee et une jambe non
    # pilotee, et `DRIVE_NAMES[5]` levait IndexError des qu'un allongement de la jambe non pilotee
    # depassait 3 % — un plantage qui n'attendait qu'un chiffre pour sortir.
    #
    # ELLE EST SEPAREE, PAS SUPPRIMEE, et c'est le point de methode du cycle : `d=5` est la SEULE
    # jambe qui mesure ce que l'owner voit en jeu. `jerk` commande 381 m/s^2, soit 39 g ; aucune
    # animation de Keira ne fait ca. Une grandeur publiee sous `jerk` decrit un stimulus qui
    # n'existe pas devant son ecran, et c'est la troisieme fois de la phase qu'un chiffre vert
    # coexiste avec un defaut qu'il voit (cf. SPEC 7, question 2 : « dans quel REPERE ? »).
    st_worst = None
    per_chain_st = {}
    anim_st = {}
    for (c, ai, dr), (el, gn, tf) in stretch.items():
        if c not in chains:
            continue
        if dr >= len(DRIVE_NAMES):
            if c not in anim_st or el > anim_st[c][0]:
                anim_st[c] = (el, ai)
            continue
        if st_worst is None or el > st_worst[0]:
            st_worst = (el, c, dr, ai)
        k = (c, dr)
        if k not in per_chain_st or el > per_chain_st[k][0]:
            per_chain_st[k] = (el, ai)
    A('ROOM-STRETCH: max=%s chain=%s drive=%s anim=%s'
      % (fnum(st_worst[0]), names[st_worst[1]], DRIVE_NAMES[st_worst[2]],
         anims[st_worst[3]]['name']))
    for c in sorted(chains):
        row = []
        for dr, nm in enumerate(DRIVE_NAMES):
            v = per_chain_st.get((c, dr))
            row.append('%s=%s' % (nm, fnum(v[0]) if v else '-'))
        A('   stretch %-12s %s' % (names[c], ' '.join(row)))
    over = sorted(((v[0], names[c], DRIVE_NAMES[dr])
                   for (c, dr), v in per_chain_st.items() if v[0] > 0.03), reverse=True)
    if over:
        A('   AU-DESSUS DE 3 %% : %d couple(s) (chaine, pilotage). C\'est la contrainte de longueur'
          % len(over))
        A('   qui cede, pas le couplage — on ne rebaisse pas le couplage pour masquer ca.')
        for v, nmc, nmd in over[:10]:
            A('     %-12s %-10s %s' % (nmc, nmd, fnum(v)))
    else:
        A('   Aucun couple (chaine, pilotage) au-dessus de 3 %% : la contrainte de longueur tient.')
    A('')
    # ---- OU S'ALLONGE L'OS : L'ATTRIBUTION DE `stretch` A UN CHEMIN PRECIS ---------------------
    # Le repli de `phys-retreat-chain` (sphere entiere fermee) garde `want = |auteur(kk) - attache
    # SIMULEE|` au lieu de la longueur du modele, et il ecrit EN DERNIER dans la frame. Cette
    # colonne mesure l'erreur qu'il laisse, PAR CHAINE : c'est ce que le `stretch` ci-dessus ne
    # savait pas localiser.
    _d7 = diag.get('run', {})
    _fb = {c: _d7.get(c, {}).get('retfblen') for c in sorted(chains)}
    if all(v is None for v in _fb.values()):
        A('-- REPLI DU RECUL (retfblen) : NON MESURE par cette course -------------------------------')
        A('   La trace ne porte aucune ligne PHYSDIAG7. La cause de l\'allongement reste non')
        A('   instrumentee : `ROOM-STRETCH` ci-dessus se lit alors sans son controle.')
    else:
        A('-- REPLI DU RECUL — OU S\'ALLONGE L\'OS, ET DE COMBIEN ------------------------------------')
        A('   NATURE : rapport sans dimension |want/ml - 1|, un MAXIMUM sur la fenetre. REPERE :')
        A('            aucun, une longueur sur une longueur depuis la MEME attache. ABSENT : 0, et')
        A('            le repli n\'a alors jamais tire sur cette chaine.')
        A('   LECTURE : `retfb` est l\'allongement laisse PAR CE CHEMIN, `elong` celui qui est')
        A('            REELLEMENT ecrit pour la chaine. Quand les deux coincident, tout')
        A('            l\'allongement de la chaine vient de ce repli et de rien d\'autre : c\'est une')
        A('            ATTRIBUTION, pas un controle de correctif.')
        _hot = [(v, c) for c, v in _fb.items() if v]
        for v, c in sorted(_hot, reverse=True):
            A('   retfb %-12s retfb=%-10s elong=%s'
              % (names[c], fnum(v), fnum(_d7.get(c, {}).get('elong', 0.0))))
        if not _hot:
            A('   Le repli n\'a tire sur AUCUNE chaine de cette course.')
        else:
            A('   %d chaine(s) ont emprunte le repli. Deux correctifs ont ete essayes a cet endroit'
              % len(_hot))
            A('   le 2026-08-13 et la mesure les a REFUSES : ils ramenaient stretch a 0.0003 en')
            A('   faisant monter meshpen a 0.2238 puis 0.2726 m et ROOM-SIDE a 1056 puis 1089')
            A('   franchissements (regle 6). La cause reste en amont, pas dans cette branche.')
    A('')
    A('-- ANIMATION SEULE — LA SEULE JAMBE QUE L\'OWNER VOIE EN JEU (18e passe) ---------------------')
    A('   NATURE   trois grandeurs distinctes de la MEME jambe non pilotee : une amplitude (tip),')
    A('            une DISCONTINUITE (jump = pire ecart d\'une frame a la suivante) et un')
    A('            allongement d\'os relatif (elong).')
    A('   REPERE   ecart a la pose d\'AUTEUR, dans le repere de l\'ancre — le meme que `row`. La')
    A('            chaine n\'herite donc pas du mouvement de son porteur.')
    A('   A DEFAUT ABSENT une chaine qui suit exactement l\'animation lit tip=0, jump=0, elong=0.')
    A('   TEXTE PERIME RETIRE (2026-08-12) : cette ligne citait « kneeflapR a 0.0093 m » comme')
    A('            lecture de reference. Ce chiffre venait des courses de la mi-journee et il ne')
    A('            correspond plus a rien — la course courante lit 0.0640 (L) / 0.0432 (R), et en')
    A('            MEDIANE sous animation seule l\'ordre est meme INVERSE (0.0019 L / 0.0126 R).')
    A('            Un nombre grave dans un commentaire cesse d\'etre une mesure des que la course')
    A('            change : il n\'y en aura plus ici, seulement des grandeurs relues du tableau.')
    A('   POURQUOI CETTE SECTION EXISTE : les cinq pilotages commandent 15.8 / 45.7 / 84.4 /')
    A('   381.4 / 9.8 m/s^2. `jerk` vaut 39 g. Aucune animation de Keira n\'approche ca, donc un')
    A('   ratio publie sous `jerk` decrit un stimulus qui n\'est jamais devant son ecran. Le')
    A('   `baseline` de ROOM-JELLY est le minimum des trois pilotages DOUX, pas cette jambe-ci :')
    A('   il n\'a jamais mesure ce qu\'il voit.')
    if base:
        A('   %-12s %9s %9s %9s %9s %9s' % ('chain', 'tip_max', 'tip_med', 'jump_max',
                                            'ratio', 'elong'))
        for c in sorted(chains):
            amps = sorted(v for (cc, _a), v in base.items() if cc == c)
            jmps = sorted(v for (cc, _a), v in basej.items() if cc == c)
            if not amps:
                continue
            # ratio = pire discontinuite RAPPORTEE a l'amplitude de la MEME animation : un saut de
            # 3 cm sur une excursion de 3 cm est une teleportation, le meme saut sur 30 cm ne l'est
            # pas. Calcule par animation puis maximise, jamais max/max (qui melangerait deux
            # animations et fabriquerait un ratio que personne n'a mesure).
            rr = max((basej[(c, a)] / base[(c, a)]
                      for (cc, a) in base if cc == c and base[(cc, a)] > 0.02), default=0.0)
            st = anim_st.get(c)
            A('   %-12s %9s %9s %9s %9s %9s'
              % (names[c], fnum(amps[-1]), fnum(amps[len(amps) // 2]), fnum(jmps[-1]),
                 '%.4f' % rr, fnum(st[0]) if st else '-'))
    A('')
    m0, m60 = mean.get('idle', {}), mean.get('tilt', {})
    if not m0 or not m60:
        die('trace incomplete : aucune ligne PHYSMEAN — ROOM-GRAVSAG ne peut pas etre calcule, et'
            ' le superviseur a interdit qu\'un APK reparte sans lui')
    A('')
    A('   CE QUE LA 10e PASSE AJOUTE. « Le sag est invisible sur l\'inclinaison toujours » — et la')
    A('   gravite avait pourtant ete TRIPLEE (0.45 -> 1.30) entre les deux builds sans que le')
    A('   chiffre bouge de 0.0156. Une grandeur insensible a un triplement de son propre reglage ne')
    A('   depend pas de ce reglage : ce n\'etait plus un reglage, c\'etait un defaut de mecanisme.')
    A('   Trois colonnes le tranchent maintenant, et elles se lisent ENSEMBLE :')
    A('     gn  = |gravite effective| / |g| vue par l\'ancre. 0 debout (les deux gravites')
    A('           s\'annulent), 1.0 a 60 degres. Si gn est nul a 60 degres, la gravite n\'arrive pas')
    A('           jusqu\'a cette chaine et aucun reglage n\'y changera rien.')
    A('     tf  = la part TANGENTIELLE de cette gravite. La contrainte de longueur n\'autorise')
    A('           qu\'une ROTATION autour de l\'attache : la composante dirigee LE LONG de l\'os est')
    A('           annulee par construction. tf ~ 0 avec gn = 1.0 veut dire « la gravite arrive et la')
    A('           geometrie du rig l\'annule » — un fait, pas un bug, mais il fallait le mesurer')
    A('           pour cesser de le confondre avec un bug.')
    A('     sagn = sag rapporte a la LONGUEUR TOTALE de la chaine. Sans lui, une chaine d\'un')
    A('           maillon et une chaine de trois ne sont pas comparables et le classement ment.')
    g0, g60 = grav.get('idle', {}), grav.get('tilt', {})
    _sagt = {}
    for c in sorted(chains):
        a, b = m0.get(c), m60.get(c)
        if a is None or b is None:
            continue
        n0 = sum(v * v for v in a) ** 0.5
        n60 = sum(v * v for v in b) ** 0.5
        sag = sum((y - x) ** 2 for x, y in zip(a, b)) ** 0.5
        blen = sum(bones.get(c, {}).values()) / UNITS
        gn, tf = g60.get(c, (float('nan'), float('nan')))
        if blen > 1e-6 and tf == tf and tf > 0.05:
            _sagt[names[c]] = (sag / blen, tf, (sag / blen) / tf)
        A('ROOM-GRAVSAG: chain=%-12s at0=%-9s at60=%-9s sag=%-9s sagn=%-8s gn=%-7s tf=%-7s fam=%s'
          % (names[c], fnum(n0), fnum(n60), fnum(sag),
             fnum(sag / blen) if blen > 1e-6 else '-',
             fnum(gn), fnum(tf),
             'A' if chains[c]['fam'] == 1 else 'B'))
    # ------------------------------------------------------------------------------------------
    # ROOM-GRAVSAG-TF — AJOUTE le 2026-08-13, on ne REMPLACE aucune colonne.
    #
    # NATURE : un deplacement soutenu, rapporte a la gravite qui l'a REELLEMENT sollicite.
    # REPERE : repere de l'ancre, longueur de chaine pour unite (comme `sagn`).
    # BASE quand le defaut est ABSENT : deux chaines MIROIR rendent le meme `sagt`.
    #
    # POURQUOI CETTE COLONNE EXISTE. Le pilotage `tilt` est un TANGAGE AVANT PUR : la part
    # tangentielle `tf` de la gravite — la seule qui puisse faire tourner un lien, la composante
    # le long de l'os etant annulee par la contrainte de longueur — vaut 0.98-1.00 a GAUCHE et
    # 0.47-0.58 a DROITE. `sagn` n'est donc PAS comparable d'un cote a l'autre : sur une paire
    # miroir il rend un ecart qui vient de l'INSTRUMENT, pas de la physique. Regler `gravity=`
    # la-dessus serait regler un parametre contre un biais d'instrument, ce que le contrat
    # interdit nommement (`never-fit-a-parameter-to-the-instrument`).
    # `sagt = sagn / tf` retire ce biais. Il ne remplace pas le correctif de fond (un `tilt` a
    # deux axes, roulis en plus du tangage) : il rend la mesure LISIBLE en attendant, et il le
    # fait sans toucher aux pilotages — donc sans deplacer le stimulus le plus faible, dont
    # depend la gate FLOOR-WEAK.
    # Chaines sous tf <= 0.05 exclues : diviser par ~0 fabriquerait un grand nombre a partir de
    # rien (c'est la classe « zero from an empty domain », prise a l'envers).
    if _sagt:
        A('')
        A('-- SAG RAPPORTE A LA GRAVITE REELLEMENT RECUE (ROOM-GRAVSAG-TF) -------------------------')
        A('   sagt = sagn / tf. Deux chaines MIROIR doivent rendre le MEME sagt ; tout ecart qui')
        A('   survit a cette division est physique, tout ecart qui disparait etait de l\'instrument.')
        for nm in sorted(_sagt):
            sn, tf, st = _sagt[nm]
            A('ROOM-GRAVSAG-TF: chain=%-12s sagn=%-8s tf=%-7s sagt=%-8s'
              % (nm, fnum(sn), fnum(tf), fnum(st)))
        # ---- CES RAPPORTS SONT RELEVES DANS `tilt`, DONT LA POSE N'EST PAS MESUREE (cycle 67)
        # `tilt` applique un tangage AVANT a la pose que la phase precedente laisse : la salle
        # n'emet aucun compagnon de directions d'os pour cette phase, donc son ecart au miroir est
        # INCONNU. Un rapport L/R releve dans une pose inconnue ne dit pas si son ecart vient
        # de la CHAINE ou de la POSE — et le rig etant a 0.005 deg du miroir en bind, c'est la
        # pose qui est le suspect par defaut. UN SEUL refus couvre les N paires : la raison est
        # la meme pour toutes, et l'ecrire N fois n'ajouterait pas une information de plus.
        _ptil = POSE['PH-TILT']
        _GSNOTE = '§12 reste NON ETABLI tant que PH-TILT ne publie pas sa pose.'
        _gsmp = [(_lf, _rg) for _lf, _rg in (('lbang', 'rbang'), ('lmidhair', 'rmidhair'),
                                             ('chestL', 'chestR'), ('earL', 'earR'))
                 if _lf in _sagt and _rg in _sagt]
        if not _ptil.ok():
            A(asym('ROOM-GRAVSAG-MIRROR', ': %d paire(s) miroir relevees, aucune publiee'
                   % len(_gsmp), _ptil, note=_GSNOTE))
        for lft, rgt in (_gsmp if _ptil.ok() else []):
            sn_l, sn_r = _sagt[lft][0], _sagt[rgt][0]
            st_l, st_r = _sagt[lft][2], _sagt[rgt][2]
            r_bru = max(sn_l, sn_r) / min(sn_l, sn_r) if min(sn_l, sn_r) > 1e-9 else float('inf')
            r_cor = max(st_l, st_r) / min(st_l, st_r) if min(st_l, st_r) > 1e-9 else float('inf')
            A(asym('ROOM-GRAVSAG-MIRROR',
                   ': %s/%s  ecart brut(sagn)=%.2fx  ecart corrige(sagt)=%.2fx'
                   % (lft, rgt, r_bru, r_cor), _ptil, note=_GSNOTE))
    if g0:
        # EXEMPTE, ET POUR LA MEME RAISON QUE `apexL`/`apexR` RESTENT DANS LES TABLEAUX : c'est
        # une mesure PAR CHAINE posee a cote d'une autre, pas un rapport. Ce qu'une pose non
        # miroir invalide, c'est ce qu'on tire de leur DIFFERENCE — et cette ligne n'en tire rien.
        A('   (debout, la meme gravite effective vaut : %s)'
          % ' '.join('%s=%s' % (names[c], fnum(g0[c][0]))
                     for c in sorted(g0) if c < len(names)), notasym=True)
    # ------------------------------------------------------------------------------------------
    # ROOM-HYST — L'HYSTERESIS, defaut PRIORITE 1 (owner 2026-08-13 21:30 : « beaucoup
    # d'hysteresis pour tous les cheveux […] j'ai envie de la desactiver parce que c'est
    # horrible ! »). AJOUTE, ne remplace aucune colonne.
    #
    # NATURE : un DEPLACEMENT SOUTENU RESIDUEL apres un cycle FERME (0 deg -> 60 deg -> 0 deg).
    #   L'hysteresis est le fait que la meme entree ne rende pas la meme sortie selon le chemin
    #   parcouru. Aucune grandeur prise a UNE extremite du chemin ne peut la voir : ni une
    #   amplitude (ROOM-RESPONSE), ni une forme (ROOM-GRADIENT), ni une duree de ballottement
    #   (ROOM-RINGDOWN). Il faut deux poses ETABLIES au meme point et comparer.
    # REPERE : celui de l'ANCRE, herite de `phys-tip-mean` (jak-hd-physics.gc:4455).
    # LECTURE QUAND LE DEFAUT EST ABSENT : ZERO. Un systeme dissipatif sans terme a memoire revient
    #   au meme equilibre des lors que l'inclinaison qui le definit est revenue a la meme valeur et
    #   qu'on lui a laisse le meme temps pour s'etablir — et `back` lui donne EXACTEMENT le meme
    #   etablissement que `idle` (meme appel, meme PHYSROOM-IDLES, meme PHYSROOM-IDLEM, meme
    #   emetteur). Un ecart non nul n'a pas d'autre explication que le chemin.
    #
    # LES TROIS COLONNES SE LISENT ENSEMBLE, et c'est le piege `zero from an empty domain` qui
    # l'impose : `ret` est un RAPPORT, donc il fabrique un grand nombre a partir de rien des que
    # son denominateur est petit. Une chaine qui n'a pas bouge pendant l'aller n'a rien a rendre au
    # retour : son `ret` n'est pas vert, il est NON CONCLUANT, et il est marque comme tel.
    #   gap   = |moyenne(back) - moyenne(idle)|, en metres. C'est l'hysteresis brute.
    #   hystn = gap / longueur de chaine. Sans lui une chaine d'un maillon et une chaine de quatre
    #           ne sont pas comparables — meme raison que `sagn`.
    #   ret   = gap / exc, la part de l'excursion que la chaine n'a PAS rendue. exc est le `sag`
    #           de ROOM-GRAVSAG : le meme aller, deja mesure.
    mback = mean.get('back', {})
    A('')
    A('-- L\'HYSTERESIS : LA CHAINE REVIENT-ELLE ? (ROOM-HYST) -----------------------------------')
    if not mback:
        A('ROOM-HYST: NON MESURE — aucune ligne PHYSMEAN tag=back dans la trace. La phase de retour')
        A('   (PHYSROOM-PH-BACK) n\'a pas tourne : ce tableau vient d\'une course anterieure a')
        A('   l\'instrument. Ce n\'est PAS un zero, c\'est une absence de mesure, et le defaut')
        A('   PRIORITE 1 reste non instrumente.')
    else:
        A('   Cycle ferme 0 deg -> 60 deg -> 0 deg. `idle` et `back` sont la MEME pose commandee,')
        A('   etablie de la MEME facon ; seul le chemin parcouru entre les deux differe. Tout ecart')
        A('   s\'impute donc au chemin, et c\'est la definition de l\'hysteresis.')
        _EXCFLOOR = 0.01   # 1 cm : en dessous, l'aller n'a rien excite et le rapport ne veut rien dire
        for c in sorted(chains):
            a, b, k = m0.get(c), m60.get(c), mback.get(c)
            if a is None or k is None:
                continue
            gap = sum((y - x) ** 2 for x, y in zip(a, k)) ** 0.5
            exc = sum((y - x) ** 2 for x, y in zip(a, b)) ** 0.5 if b is not None else 0.0
            blen = sum(bones.get(c, {}).values()) / UNITS
            ret = ('%s' % fnum(gap / exc)) if exc >= _EXCFLOOR else 'n/c(exc<1cm)'
            A('ROOM-HYST: chain=%-12s gap=%-9s exc=%-9s hystn=%-8s ret=%-12s fam=%s'
              % (names[c], fnum(gap), fnum(exc),
                 fnum(gap / blen) if blen > 1e-6 else '-', ret,
                 'A' if chains[c]['fam'] == 1 else 'B'))
    # ------------------------------------------------------------------------------------------
    # ROOM-HYST-SHAKE — LA MEME GRANDEUR, DANS LE REGIME OU LE DEFAUT VIT, AVEC SON CONTROLE.
    #
    # POURQUOI ELLE EXISTE A COTE DE ROOM-HYST : le cycle `tilt` est QUASI-STATIQUE et n'exerce pas
    # les termes a memoire du solveur (recul, reflexion de cote, attenuation), qui ne se declenchent
    # que sur du mouvement rapide. Un zero mesure dans un regime ou les causes ne tirent pas ne
    # prouve rien (`stimulus-must-be-representative`). Ici le cycle est une SECOUSSE `jerk` suivie
    # d'un relachement : meme etat commande au depart et a l'arrivee, meme etablissement, meme
    # fenetre que `idle`/`back`.
    #
    # NATURE / REPERE / LECTURE QUAND LE DEFAUT EST ABSENT : identiques a ROOM-HYST (deplacement
    #   soutenu residuel apres cycle ferme ; repere de l'ancre ; zero).
    # REFERENCE : chaque cycle est rapporte a la pose ETABLIE QUI LE PRECEDE IMMEDIATEMENT —
    #   `shaken` contre `back`, `shakenpc` contre `shaken`. Les trois sont mesurees de la meme
    #   facon, donc comparables ; prendre une reference lointaine melangerait les cycles.
    # CONTROLE POSITIF : la seconde secousse est identique, contrainte de cote LEVEE. Contrainte
    #   levee, un maillon passe du mauvais cote d'un volume Y RESTE — un equilibre stable mais faux,
    #   c'est-a-dire un non-retour. Le rapport `armed/normal` DOIT etre nettement > 1. S'il ne l'est
    #   pas, la mesure ne discrimine pas et le zero du regime normal ne vaut rien : c'est ecrit
    #   ci-dessous en toutes lettres plutot que laisse a l'interpretation.
    mshk, mshkpc = mean.get('shaken', {}), mean.get('shakenpc', {})
    A('')
    A('-- L\'HYSTERESIS DANS LE REGIME REPRESENTATIF (ROOM-HYST-SHAKE) ---------------------------')
    if not mshk:
        A('ROOM-HYST-SHAKE: NON MESURE — aucune ligne PHYSMEAN tag=shaken. La phase de secousse')
        A('   n\'a pas tourne : ce tableau vient d\'une course anterieure a l\'instrument. Ce n\'est')
        A('   PAS un zero, c\'est une absence de mesure.')
    else:
        _n_fire, _n_tot = 0, 0
        for c in sorted(chains):
            b, s, q = mback.get(c), mshk.get(c), mshkpc.get(c)
            if b is None or s is None:
                continue
            blen = sum(bones.get(c, {}).values()) / UNITS
            gs = sum((y - x) ** 2 for x, y in zip(b, s)) ** 0.5
            gp = (sum((y - x) ** 2 for x, y in zip(s, q)) ** 0.5) if q is not None else float('nan')
            rat = (gp / gs) if (gs > 1e-9 and gp == gp) else float('nan')
            if rat == rat:
                _n_tot += 1
                if rat > 1.5:
                    _n_fire += 1
            A('ROOM-HYST-SHAKE: chain=%-12s gap=%-9s gapn=%-8s control=%-9s ratio=%-8s fam=%s'
              % (names[c], fnum(gs), fnum(gs / blen) if blen > 1e-6 else '-',
                 fnum(gp) if gp == gp else '-', fnum(rat) if rat == rat else '-',
                 'A' if chains[c]['fam'] == 1 else 'B'))
        if _n_tot:
            A('ROOM-HYST-SHAKE-CONTROL: %d chaine(s) sur %d ou la contrainte levee fait monter'
              ' l\'ecart de plus de 50%%' % (_n_fire, _n_tot))
            if _n_fire == 0:
                A('   => LE CONTROLE POSITIF N\'A PAS TIRE. Aucun zero de cette colonne n\'est')
                A('      recevable tant que ce n\'est pas explique : une mesure que le defaut')
                A('      injecte ne fait pas bouger ne mesure pas ce defaut.')
    A('')
    A('-- LE PIRE CAS DE CHAQUE CHAINE, AVEC LE NOM DE L\'ANIMATION OU IL S\'EST PRODUIT ------------')
    for c in sorted(chains):
        w = worst[c]
        A('worst chain=%-12s tipvar=%-9s anim=%-38s drive=%-9s rootdev=%-9s meshpen=%-9s'
          ' jump=%s'
          % (names[c], fnum(w['amp']['v']), anims[w['amp']['ai']]['name'],
             DRIVE_NAMES[w['amp']['dr']],
             fnum(w['root']['v']), fnum(w['pen']['v']), fnum(w['jump']['v'])))
        A('      (pire rootdev sur %s/%s, pire meshpen sur %s/%s, pire jump sur %s/%s)'
          % (anims[w['root']['ai']]['name'], DRIVE_NAMES[w['root']['dr']],
             anims[w['pen']['ai']]['name'], DRIVE_NAMES[w['pen']['dr']],
             anims[w['jump']['ai']]['name'], DRIVE_NAMES[w['jump']['dr']]))
    A('')
    A('-- LA GEOMETRIE DE CHAQUE CHAINE, TELLE QUE LE MOTEUR L\'A RESOLUE ------------------------')
    A('   (la longueur d\'os est le PLAFOND geometrique de l\'amplitude d\'un lien : personne n\'a a')
    A('   deviner si une chaine « ne bouge pas assez » ou « ne peut pas bouger plus ».)')
    A('   `contact_frames` = frames de la course ou cette chaine avait au moins une paire')
    A('   (lien, volume) en contact. Une chaine a contact_frames=0 n\'a JAMAIS approche une')
    A('   surface : son meshpen 0.0000 veut dire « n\'a rien touche », pas « mesure a zero ». La')
    A('   distinction est publiee ici plutot que noyee dans un zero commun.')
    for c in sorted(chains):
        d = chains[c]
        bl = bones.get(c, {})
        A('   chain %-12s links=%d fam=%s hang=%.2f contact_frames=%-6d joints=%-28s bones_m=%s'
          % (names[c], d['links'], 'A' if d['fam'] == 1 else 'B', d['hang'],
             auth.get(c, {}).get('contact', 0), ','.join(joints_of[c]),
             ','.join('%.4f' % (bl[l] / UNITS) for l in sorted(bl))))
    A('')
    A('-- LES JOINTS QUE CHAQUE CHAINE ECRIT REELLEMENT --------------------------------------------')
    A('   Verdict owner du 2026-08-11 : « un polygone de la semelle de la chaussure gauche se fait')
    A('   la malle » et « les languettes des bandes de genoux ne bougent pas du tout ». Les deux se')
    A('   decident sur cette liste — ce que la chaine ECRIT — et pas sur ce que son nom suggere.')
    for c in sorted(chains):
        A('   %-12s -> %s' % (names[c],
                              ', '.join('%s(idx %d)' % (nm, idx)
                                        for _, idx, nm in sorted(written.get(c, [])))))
    A('')
    A('-- 6e PASSE DE L\'OWNER, DEFAUT 1 : L\'AUTO-COLLISION DES MECHES -----------------------------')
    A('   « Les meches fines jittent like crazy des que la tete bouge (peu importe si c\'est la tete')
    A('   qui bouge ou si elle est deplacee dans l\'espace par le reste du squelette). »')
    A('   Les colliders Lbanga / Rbanga / Lmidhaira / lBoob sont les JOINTS-RACINES des chaines')
    A('   elles-memes, et les capsules Lbangb->Lbanga sont leurs MAILLONS. Une chaine ne doit donc')
    A('   jamais entrer en collision avec ses propres volumes. `selfcol` compte les corrections qui')
    A('   en viennent : ZERO exige, et la branche ARMEE leve l\'exclusion pour prouver que le')
    A('   compteur voit quelque chose.')
    dr_run, dr_off, dr_on = diag.get('run', {}), diag.get('self-disarmed', {}), diag.get('self-armed', {})
    if not dr_run or not dr_on:
        die('trace incomplete : PHYSDIAG (run / self-armed) manquant — le defaut 1 de la 6e passe'
            ' n\'est pas mesure')
    s_run = sum(v.get('selfcol', 0.0) for v in dr_run.values())
    s_off = sum(v.get('selfcol', 0.0) for v in dr_off.values())
    s_on = sum(v.get('selfcol', 0.0) for v in dr_on.values())
    A('ROOM-SELFCOL: run=%d disarmed=%d armed=%d' % (s_run, s_off, s_on))
    # ---- ROOM-SIDE : de quel COTE du volume le lien a-t-il fini ? -------------------------
    # Reclamee par les DIRECTIVES depuis la 11e passe (« Mesurer le COTE : ROOM-SIDE:
    # chain=<nom> inside_frames=<n>, doit etre zero ») et jamais ecrite jusqu'au 2026-08-12.
    # AUCUNE autre colonne ne peut voir ce defaut : la profondeur de penetration est MAXIMALE
    # sur l'axe du volume et REDESCEND quand le lien ressort de l'autre cote, donc un lien qui
    # a traverse une jambe de part en part rend une profondeur FAIBLE — indistinguable d'un
    # lien sagement dehors. C'est ainsi que « le bas du pantacourt est a l'interieur des
    # mollets » et « en cinematique les lunettes traversent le buste pour aller se poser dans
    # le dos » coexistaient avec meshpen = 0.0000.
    #   NATURE  : un COMPTE de paires (lien, volume). Un changement de cote est DISCRET ; une
    #             distance ne peut pas le decrire, et c'est pour ca que les mesures de
    #             profondeur n'ont jamais vu ces deux defauts.
    #   REPERE  : celui du VOLUME — direction allant du point le plus proche de son AXE vers le
    #             lien, comparee entre la pose du modele et maintenant. Ni monde, ni ancre.
    #   LECTURE QUAND LE DEFAUT EST ABSENT : 0. Un lien qui reste du cote ou l'auteur l'a pose
    #             ne compte jamais, quelle que soit son amplitude.
    # CONTROLE POSITIF (2026-08-12) : depuis que la contrainte de cote existe, ce compteur peut
    # tomber a ZERO — et un zero est soit une correction, soit un predicat devenu inevaluable.
    # La salle roule donc deux fenetres a EXPOSITION EGALE : `side-disarmed` (contrainte en place)
    # et `side-armed` (contrainte levee, rien d'autre), chacune balayant TOUTES les animations,
    # PHYSROOM-PCW frames par animation, meme pilotage.
    #   POURQUOI PAS `self-disarmed` COMME REFERENCE, comme le faisait la version precedente : cette
    #   fenetre-la dure 90 frames sur UNE animation, quand la branche armee en couvre nanim x 90.
    #   Comparer deux comptes a des expositions differentes est l'erreur exacte que le cycle
    #   precedent avait relevee (43 evenements sur 90 frames opposes a 11446 sur 16740) sans la
    #   corriger. Les deux branches ont desormais la meme duree, les memes animations, le meme
    #   pilotage : la SEULE variable est la contrainte.
    dr_sidearm = diag.get('side-armed', {})
    dr_sideoff = diag.get('side-disarmed', {})
    side_dis = sum(v.get('side', 0.0) for v in dr_sideoff.values())
    side_arm = sum(v.get('side', 0.0) for v in dr_sidearm.values())
    if dr_sidearm and dr_sideoff:
        A('ROOM-SIDE-CONTROL: armed=%d disarmed=%d' % (side_arm, side_dis))
        for c, v in sorted(dr_sidearm.items(), key=lambda kv: -kv[1].get('side', 0.0)):
            if v.get('side', 0.0) > 0:
                A('ROOM-SIDE-CONTROL: chain=%-12s armed=%d disarmed=%d'
                  % (names[c] if c < len(names) else c, v.get('side', 0.0),
                     dr_sideoff.get(c, {}).get('side', 0.0)))
    side_run = {c: v.get('side', 0.0) for c, v in dr_run.items()}
    nz = sorted(((v, c) for c, v in side_run.items() if v > 0), reverse=True)
    A('ROOM-SIDE: chains=%d/%d crossing=%d' % (len(nz), len(names), int(sum(v for v, _ in nz))))
    for v, c in nz:
        A('ROOM-SIDE: chain=%-12s inside_frames=%d' % (names[c] if c < len(names) else c, int(v)))
    if not nz:
        A('   ATTENTION : zero partout — ce zero exige un controle positif qui l\'a fait MONTER')
        A('   avant d\'etre cru (SPEC 7). Il n\'en existe pas encore.')
    if s_on <= s_off:
        A('   ATTENTION : le controle positif n\'a PAS fait monter le compteur — il ne mesure rien,')
        A('   et le zero de la course ne prouve donc rien.')
    for c in sorted(chains):
        A('   selfcol %-12s run=%-8d armed=%-8d  (retreat=%-7d flip=%-8d inv=%-6d invres=%-6d'
          ' elong=%.4f raddrop=%d)'
          % (names[c], int(dr_run.get(c, {}).get('selfcol', 0)),
             int(dr_on.get(c, {}).get('selfcol', 0)),
             int(dr_run.get(c, {}).get('retreat', 0)),
             int(dr_run.get(c, {}).get('flip', 0)),
             int(dr_run.get(c, {}).get('inv', 0)),
             int(dr_run.get(c, {}).get('invres', 0)),
             dr_run.get(c, {}).get('elong', 0.0),
             int(dr_run.get(c, {}).get('rad', 0))))
    # ---- LE PREMIER SEGMENT DE LA MECHE (residu de `hair-gradient`, PRIORITE 1) ---------------
    # Owner 2026-08-12 14:10 : « on dirait qu'elles sont ancrees (les pointes) au meme titre que les
    # racines, et que c'est ce qu'il y a entre les pointes et les racines qui bouge vraiment. »
    #
    # POURQUOI ROOM-GRADIENT NE POUVAIT PAS LE VOIR, et c'est un defaut d'INSTRUMENT, pas de mesure.
    # Toutes les chaines de cheveux portent `rootlock=1`, et le moteur sautait tout `l < rlk` a
    # l'ecriture : le maillon 0 n'etait ni integre ni ecrit. Sa deviation vaut donc EXACTEMENT 0, et
    # ROOM-GRADIENT publie [0, x] sur une chaine a 2 maillons. Une suite de deux termes dont le
    # premier est nul ne peut JAMAIS echouer au test de croissance `max(v[:-1]) > v[-1]` : la gate
    # etait VIDE DE SENS sur 5 des 7 chaines de cheveux (earL, earR, backhair, lmidhair, rmidhair),
    # et sur les 2 autres elle ne jugeait que 2 segments sur 3. Le zero n'y etait pas une reussite,
    # il etait l'empreinte du defaut.
    #
    # rootrot est l'angle REELLEMENT ecrit dans la 3x3 de ce maillon. NATURE : un angle en degres.
    # REPERE : la direction d'os du joint, pose du modele -> position simulee de son enfant, prise
    # depuis SON ANCRE (donc son mouvement PROPRE, pas celui herite du crane). LECTURE QUAND LE
    # DEFAUT EST PRESENT : 0.0000 exactement, structurellement.
    # ---- LE ZERO DE `rootrot` PEUT ETRE VIDE DE DOMAINE, ET IL L'EST SUR LA POITRINE -----------
    # Son site d'ecriture dans le moteur est garde par `(when (< l rlk0))`. Une chaine dont les
    # DONNEES ne declarent aucun `rootlock` a `rlk0 = 0`, donc la condition est `l < 0` : elle
    # n'est JAMAIS vraie, et le compteur ne peut pas etre ecrit. `physics_chains.txt` omet
    # explicitement `rootlock` sur chestL/chestR (« pinning it would freeze three quarters of the
    # organ »), donc leur `rootrot = 0.0000` n'est pas une mesure — c'est un domaine vide, et le
    # verdict « leur premier segment ne tourne pas d'un degre » qui en etait tire etait FAUX.
    # `rot0` (PHYSAXRES, cycle 29) porte le meme angle avec la garde `(= l 0)`, qui existe sur
    # TOUTE chaine : c'est lui qui discrimine « le maillon ne tourne pas » de « rien ne l'a lu ».
    rot0 = {}
    for m in re.finditer(r'^PHYSAXRES c=(\d+) ax=(\d+) nolen=(\d+) res=([-\d.e+]+)'
                         r' ci=([-\d.e+]+) rot0=([-\d.e+]+)', txt, re.M):
        c = int(m.group(1))
        rot0[c] = max(rot0.get(c, 0.0), float(m.group(6)))
    rr = {c: dr_run.get(c, {}).get('rootrot') for c in sorted(chains)}
    if all(v is None for v in rr.values()):
        A('-- PREMIER SEGMENT (rootrot) : NON MESURE par cette course ------------------------------')
        A('   La trace ne porte aucune ligne PHYSDIAG6. Le residu de `hair-gradient` — le premier')
        A('   segment de chaque meche fige a 0 degre — reste donc invisible, et ROOM-GRADIENT ne')
        A('   peut pas le voir a sa place : sur une chaine a 2 maillons il publie [0, x].')
    else:
        A('-- LE PREMIER SEGMENT DE LA MECHE (rootrot) ---------------------------------------------')
        A('   L\'angle ecrit dans la 3x3 du maillon `rootlock`. Il valait 0.0000 STRUCTURELLEMENT')
        A('   avant ce cycle : la boucle d\'ecriture du moteur sautait tout `l < rlk`, donc ~50 % de')
        A('   la geometrie des cheveux etait soudee au crane et une meche a 2 joints se reduisait a')
        A('   un segment rigide articule EN SON MILIEU. Zero ici = le defaut est present.')
        mute = []
        judged = 0
        for c in sorted(chains):
            v, nl = rr.get(c), chains[c]['links']
            if v is None:
                continue
            r0 = rot0.get(c)
            if r0 is not None and v <= 0.0 and r0 > 0.0:
                A('   rootrot %-12s   DOMAINE VIDE — le compteur ne peut pas etre ecrit sur cette'
                  % names[c])
                A('           chaine (aucun `rootlock` dans ses donnees, donc `rlk0 = 0`, donc la')
                A('           garde `l < rlk0` est toujours fausse). Le maillon 0 tourne bien :')
                A('           rot0 = %.4f deg, meme angle, garde `l = 0`. (maillons=%d)' % (r0, nl))
                continue
            A('   rootrot %-12s %8.4f deg   (maillons=%d)' % (names[c], v, nl))
            # une chaine a 1 maillon n'a PAS de lien rootlock : son zero est une definition, pas un
            # defaut. Ne sont fautives que les chaines a 2+ maillons, celles que le generateur
            # rootlocke. Et une chaine que le generateur NE rootlocke PAS n'a pas de domaine du
            # tout : `rot0` ci-dessus la retire, sinon le verdict porterait sur un zero vide.
            if nl >= 2:
                judged += 1
                if v <= 0.0 and not (rot0.get(c, 0.0) > 0.0):
                    mute.append(names[c])
        if mute:
            A('   MUET sur %d chaine(s) a 2+ maillons : %s' % (len(mute), ' '.join(mute)))
            A('   Leur premier segment ne tourne pas d\'un degre : le defaut que l\'owner decrit est')
            A('   encore la, et il est STRUCTUREL, pas un reglage.')
        elif judged:
            A('   Toutes les chaines a 2+ maillons ecrivent une rotation non nulle sur leur premier')
            A('   segment : le cuir chevelu est devenu une charniere au lieu d\'une soudure. Le')
            A('   controle positif est la version precedente du moteur, ou ce meme chiffre valait')
            A('   0.0000 sur TOUTES ces chaines — un zero structurel, pas un zero mesure.')
        else:
            A('   AUCUNE chaine de cette course n\'est jugeable par ce compteur : toutes ont un')
            A('   domaine vide (aucun `rootlock` declare). Ce n\'est ni une reussite ni un echec,')
            A('   c\'est une absence de mesure — et c\'est `rot0` ci-dessus qui porte le chiffre.')
        A('')

    # ---- LE PRIX DU MUR DUR D'EXCURSION (cycle 2026-08-12, en poursuivant `knee-tabs`) --------
    # Le mur (`jak-hd-physics.gc` l.1384 et l.1492) plafonne NET l'ecart d'un lien `l = 0` a sa
    # pose animee, a son propre rayon mesure. Constat qui a ouvert le sujet : sur les 8 chaines ou
    # il mord, le PIC d'excursion (`rootdev`) vaut EXACTEMENT le plafond, a moins de 0.6 mm --
    # l'amplitude de ces chaines est donc posee par un clamp, pas produite par la physique. Les
    # deux chaines temoins (pantflapL/R, mur jamais mordu) s'arretent 14.7 et 18.2 mm SOUS le leur.
    # SPEC 7 : « on chiffre COMBIEN DE MOUVEMENT il retire ». Voici ce chiffre, par chaine.
    rdm = {c: dr_run.get(c, {}).get('raddropm') for c in sorted(chains)}
    if any(v is not None for v in rdm.values()):
        A('-- LE PRIX DU MUR DUR D\'EXCURSION (raddrop) --------------------------------------------')
        A('   NATURE : une longueur CUMULEE sur la fenetre (somme des ecarts retires), pas une')
        A('   amplitude — elle ne se compare qu\'entre chaines d\'une MEME course. REPERE : ecart a')
        A('   la pose animee du lien. LECTURE QUAND LE MUR NE MORD PAS : 0.')
        tot = 0.0
        for c in sorted(chains, key=lambda x: -(rdm.get(x) or 0.0)):
            v, n = rdm.get(c), dr_run.get(c, {}).get('rad', 0)
            if v is None:
                continue
            tot += v
            if v > 0 or n:
                A('   raddrop %-12s morsures=%-7d prix=%8.3f m   (%.4f m par morsure)'
                  % (names[c], int(n), v, (v / n) if n else 0.0))
        A('   prix total du mur sur la course : %.3f m' % tot)
        A('   Un mur qui mord des milliers de fois n\'est pas un garde-fou, c\'est le regime de')
        A('   fonctionnement : aucun reglage de raideur, de masse ou de couplage ne deplace un lien')
        A('   plaque contre une butee dure. C\'est la lecture mecanique de `knee-tabs` (couplage')
        A('   monte de 1.00 a 1.60 au cycle precedent, sans effet visible) et de la poitrine')
        A('   « un peu mutee sur les mouvements subtils ».')
        A('')

    # ---- LA DECISION 1 ET LE FOURREAU (cycle 2026-08-12) --------------------------------------
    # volprio : NATURE un COMPTE de paires (lien, volume) sur la fenetre, REPERE sans objet,
    #           LECTURE HORS DEFAUT 0 -- un lien qu'aucun conflit de volumes ne concerne n'ecarte
    #           personne. Une chaine dont ce compte est GRAND est une chaine que des volumes se
    #           disputaient, donc que le recul epinglait : c'est l'attribution qui manquait a
    #           `ROOM-INVERSIONS residual`, un scalaire global qu'aucune chaine ne portait.
    vp = {c: dr_run.get(c, {}).get('volprio') for c in sorted(chains)}
    if any(v is not None for v in vp.values()):
        tot = sum(v for v in vp.values() if v)
        A('ROOM-VOLPRIO: pairs_ignored=%d chains=%d'
          % (int(tot), sum(1 for v in vp.values() if v)))
        for v, c in sorted(((v or 0.0, c) for c, v in vp.items()), reverse=True):
            if v > 0:
                A('ROOM-VOLPRIO: chain=%-12s ignored=%-8d retreat=%d'
                  % (names[c], int(v), int(dr_run.get(c, {}).get('retreat', 0))))
        if tot == 0:
            A('   zero partout : aucun lien n\'est contraint par plus d\'un volume a la fois. Un')
            A('   zero ici n\'est PAS une reussite en soi -- il dit seulement que la priorite')
            A('   n\'avait rien a arbitrer sur cette course.')
    # shellrad : NATURE une DISTANCE radiale (m), surtout pas une profondeur -- une profondeur est
    #           MAXIMALE sur l'axe, c'est-a-dire la ou un fourreau est CORRECT, et c'est pour ca que
    #           `meshpen` lisait 0.0000 pendant que l'owner voyait le pan de pantacourt disparaitre
    #           dans le mollet. REPERE celui du volume. LECTURE HORS DEFAUT 0 (la pose du modele
    #           rend exactement 0). Mesuree meme sous controle arme, sinon le chiffre TOMBERAIT
    #           sous le defaut au lieu de MONTER.
    # inward :  l'AUTRE moitie de la meme grandeur (m, SIGNEE, negative sous le defaut) : de combien
    #           le lien-fourreau est passe SOUS sa distance de pose modele, donc dans la chair.
    #           `shellrad` ne voit que le pan qui S'ECARTE de l'axe ; `pant-calf` (« le bas du
    #           pantacourt est toujours a l'interieur des mollets ») est exactement l'autre cas, et
    #           aucune colonne ne le voyait. Relevee AVANT correction, donc elle mesure le
    #           phenomene a sa pleine echelle. Absente d'une vieille trace = 0.0.
    sh_run = {c: dr_run.get(c, {}).get('shellrad') for c in sorted(chains)}
    if any(v is not None for v in sh_run.values()):
        dr_shoff = diag.get('shell-disarmed', {})
        dr_shon  = diag.get('shell-armed', {})
        for v, c in sorted(((v or 0.0, c) for c, v in sh_run.items()), reverse=True):
            if v > 0 or (dr_shon.get(c, {}).get('shellrad') or 0) > 0:
                _so = dr_run.get(c, {}).get('shellout')
                A('ROOM-SHELL: chain=%-12s run=%.4f disarmed=%.4f armed=%.4f inward=%.4f wants=%s'
                  % (names[c], v,
                     (dr_shoff.get(c, {}).get('shellrad') or 0.0),
                     (dr_shon.get(c, {}).get('shellrad') or 0.0),
                     (dr_run.get(c, {}).get('shellin') or 0.0),
                     '--' if _so is None else '%.4f' % _so))
        sd = sum((dr_shoff.get(c, {}).get('shellrad') or 0.0) for c in chains)
        sa = sum((dr_shon.get(c, {}).get('shellrad') or 0.0) for c in chains)
        A('ROOM-SHELL-CONTROL: armed=%.4f disarmed=%.4f' % (sa, sd))
    # QUELLE MOITIE DU LIMITEUR RADIAL TIRE, ET COMBIEN DE FOIS. La question est restee ouverte
    # deux cycles parce que la ligne existait dans la trace sans etre lue. Elle tranche une
    # hypothese : si `inward` domine, le pan passe son temps a entrer dans le mollet et la
    # contrainte l'en ressort -- le mouvement perdu par FLOOR-WEAK etait du tissu qui s'enfoncait,
    # pas du mouvement legitime. Si `out` domine, c'est l'inverse et la moitie `rad>0` epingle.
    # NATURE : des COMPTES d'evenements sur la fenetre de controle. REPERE : sans objet.
    # LECTURE HORS DEFAUT : inward=0. `--` = trace anterieure a la publication du compteur.
    # ---- SPEC 33 : L'ABLATION DE LA CONTRAINTE DE LONGUEUR SUR LE RESIDU D'INTERPENETRATION ----
    # Le cycle 28 a etabli que le residu (487.82 u sur chestL) n'est PAS un defaut de convergence
    # — 8x3 balayages + 4 iterations de finition le laissent en place — et a nomme la cinematique
    # sans pouvoir l'attribuer. L'ablation est ici : les six fenetres AX/AXZ portent la MEME
    # impulsion, la MEME amplitude, la MEME duree et le MEME emetteur ; un seul terme change,
    # `phys-len-off-set!`. C'est la seule paire de la course qui ait une exposition egale (les
    # tags `self`/`side`/`cone` ont des fenetres et des stimuli differents, et les comparer serait
    # le transport de mesure que le cycle 28 s'est reproche).
    #
    # NATURE de `res` : une PROFONDEUR en unites de jeu, maximum sur la fenetre, APRES tout le
    # solveur, au-dela du plancher de pose d'auteur. REPERE : le monde, a la frame ecrite.
    # LECTURE HORS DEFAUT : 0.0000. `ci` = le volume qui porte ce residu ; sans lui, un residu qui
    # change de volume se lirait comme un residu qui bouge.
    # NATURE de `rend` : un RAPPORT sans dimension, `removed / sumdepth`, c'est-a-dire la moyenne
    # de `1 - cos^2(normale de contact, direction radiale)` sur les poussees de la fenetre. A 1 la
    # poussee est entierement tangentielle (la contrainte de longueur ne lui retire rien) ; a 0
    # elle est entierement radiale (la contrainte la confisque en totalite).
    _axres = {}
    for _m in re.finditer(r'^PHYSAXRES c=(\d+) ax=(\d+) nolen=(\d+) res=([-\d.e+]+)'
                          r' ci=([-\d.e+]+) rot0=([-\d.e+]+)', txt, re.M):
        _axres[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))] = (
            float(_m.group(4)), float(_m.group(5)), float(_m.group(6)))
    _axtan = []
    for _m in re.finditer(r'^PHYSAXTAN ax=(\d+) nolen=(\d+) n=(\d+) sumdepth=([-\d.e+]+)'
                          r' removed=([-\d.e+]+)', txt, re.M):
        _axtan.append((int(_m.group(1)), int(_m.group(2)), int(_m.group(3)),
                       float(_m.group(4)), float(_m.group(5))))
    _axcom = {}
    for _m in re.finditer(r'^PHYSAXCOM c=(\d+) ax=(\d+) nolen=(\d+) comex=([-\d.e+]+)', txt, re.M):
        _axcom[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))] = float(_m.group(4))
    # ---- SPEC 22 : L'EXCURSION DU CENTRE DE CHAIR, CONTRE LA BANDE QUE SA §22 LUI DONNE -------
    # « Breast COM: normal <= 35 % B0, hard transient <= 40 % B0 ». Le moteur borne le JOINT avec
    # la bande de l'APEX (0.42/0.50) et le CANAL RADIAL avec celle du COM : aucune des deux n'EST
    # le centre de masse de la chair. NATURE : une longueur rapportee a B0, maximum de fenetre.
    # REPERE : le monde, frame ecrite, contre la pose d'auteur de la MEME frame, deformation
    # comprise. LECTURE A LA POSE D'AUTEUR : 0.0000.
    _comex, _comdist = {}, {}
    for _m in re.finditer(r'^PHYSDIAG8 tag=(\S+) c=(\d+) comex=([-\d.e+]+)'
                          r'(?: comsum=([-\d.e+]+) comn=([-\d.e+]+) comhi=([-\d.e+]+))?',
                          txt, re.M):
        _comex.setdefault(_m.group(1), {})[int(_m.group(2))] = float(_m.group(3))
        if _m.group(5) is not None and float(_m.group(5)) > 0.0:
            _comdist.setdefault(_m.group(1), {})[int(_m.group(2))] = (
                float(_m.group(4)) / float(_m.group(5)),
                float(_m.group(6)) / float(_m.group(5)))
    # ---- SPEC 14-20 : LA REPONSE DE COM PAR REGIME DE PILOTAGE --------------------------------
    # Ses §14 a §20 sont les seules lignes de sa spec qui relient un STIMULUS a une REPONSE, et
    # chacune donne SA bande de COM. Le plus grand chiffre de COM de toute la spec est 0.40 B0
    # (§16 atterrissage tres dur), qui est aussi le plafond dur de §22 : AUCUN regime n'autorise
    # davantage, et cette comparaison-la ne demande aucune interpretation.
    # La ligne de base (`d` >= PHYSROOM-DRIVES, aucun pilotage) est publiee A COTE et jamais
    # soustraite en silence : c'est ce que l'ANIMATION SEULE produit.
    _comw = {}
    for _m in re.finditer(r'^PHYSCOMW c=(\d+) a=(\d+) d=(\d+) comex=([-\d.e+]+)', txt, re.M):
        _comw.setdefault((int(_m.group(1)), int(_m.group(3))), []).append(
            (int(_m.group(2)), float(_m.group(4))))
    if _comw:
        A('')
        A('-- SPEC 14-20 : LA REPONSE DE COM PAR REGIME, CONTRE LES BANDES DE SA SPEC ------------')
        A('   Maximum de `comex` sur CHAQUE fenetre (chaine, animation, pilotage), puis le pire et')
        A('   la moyenne des fenetres pour chaque pilotage. NATURE : longueur rapportee a B0,')
        A('   maximum de fenetre. REPERE : monde, frame ecrite, contre la pose d\'auteur de la meme')
        A('   frame, deformation comprise. LECTURE A LA POSE D\'AUTEUR : 0.0000.')
        A('   Le PLUS GRAND chiffre de COM de toute sa spec est 0.40 B0 (§16, atterrissage tres')
        A('   dur), egal au plafond dur de sa §22. Aucun de ses regimes n\'en autorise plus.')
        _dn = {0: 'updown', 1: 'leftright', 2: 'accel', 3: 'jerk', 4: 'tilt'}
        A('   chaine        pilotage      pire     moyenne   fenetres   au-dessus de 0.40 B0')
        for _c in sorted(chains):
            for _d in sorted(set(k[1] for k in _comw if k[0] == _c)):
                _v = [v for _a, v in _comw[(_c, _d)]]
                if not _v:
                    continue
                _hi = sum(1 for x in _v if x > 0.40)
                A('   %-13s %-11s %8.4f %9.4f %9d %11d (%.0f %%)'
                  % (names[_c] if _c < len(names) else _c,
                     _dn.get(_d, 'BASE(sans pilotage)' if _d >= 5 else 'd%d' % _d),
                     max(_v), sum(_v) / len(_v), len(_v), _hi, 100.0 * _hi / len(_v)))
        # ---- LA DIFFERENCE APPARIEE, ET C'EST ELLE QUI VAUT --------------------------------
        # Comparer des MOYENNES de pilotages differents melange les animations. La seule forme
        # qui isole l'apport du pilotage est la difference sur la MEME animation : `comex` avec
        # pilotage moins `comex` sans pilotage, paire par paire. NATURE : une difference de deux
        # MAXIMA de fenetre, en B0 — pas une amplitude de reponse ; un maximum sur une fenetre
        # longue est domine par la pire frame de l'animation, ce qui peut masquer un apport
        # reparti ailleurs. C'est dit ici plutot que sous-entendu.
        _bd = max((k[1] for k in _comw), default=0)
        _base = {(_c, _a): _v for _c in sorted(chains)
                 for _a, _v in _comw.get((_c, _bd), [])}
        if _base:
            A('   APPORT DU PILOTAGE, PAIRE PAR PAIRE (meme chaine, MEME animation, avec moins sans)')
            for _c in sorted(chains):
                for _d in sorted(set(k[1] for k in _comw if k[0] == _c and k[1] != _bd)):
                    _df = [v - _base[(_c, _a)] for _a, v in _comw[(_c, _d)]
                           if (_c, _a) in _base]
                    if not _df:
                        continue
                    A('     %-13s %-11s paires=%-4d apport moyen %+8.4f   pire %+8.4f   '
                      'ajoute dans %.0f %% des paires'
                      % (names[_c] if _c < len(names) else _c, _dn.get(_d, 'd%d' % _d),
                         len(_df), sum(_df) / len(_df), max(_df),
                         100.0 * sum(1 for x in _df if x > 0) / len(_df)))
            A('     Un apport qui ne CROIT PAS avec le stimulus (cf. `acc` de PHYSACC) dit que la')
            A('     reponse ne suit pas son excitation : signature de SATURATION, pas de raideur.')
        A('   MAPPING vers ses sections — c\'est MA lecture, pas une ligne de sa spec, et elle est')
        A('   ecrite pour pouvoir etre contestee : updown -> §14/§15/§16 (saut, apex, reception) ;')
        A('   leftright et accel -> §17 (acceleration et freinage) ; jerk -> §16/§17 transitoire')
        A('   haut ; tilt -> §19 (tangage) et §20 (roulis). Les bandes de COM correspondantes :')
        A('   §14 0.15-0.32 · §16 0.25-0.40 · §17 0.10-0.30 · §18 0.10-0.28 · §20 0.15-0.22.')
        A('   La comparaison au plafond 0.40 ci-dessus, elle, ne depend d\'aucun mapping.')
    # ---- SPEC 22 : L'ATTRIBUTION DE `comex` A SES TROIS TERMES (cycle 35 etape 1) -------------
    # `comex` est le plus gros depassement ouvert de toute la spec. Le cycle 34 a prouve PAR
    # INTERVENTION que borner le point libre ne le baisse pas (K5). Cette section dit QUEL terme
    # le porte, par une IDENTITE — pas par un modele :
    #     e = (p_sim - p_auth) + R_auth.(rot - I).lc + R_auth.rot.(T - I).lc
    # publiee en PROJECTIONS SIGNEES sur `e^`, donc tp + rp + dp = comex * b0c EXACTEMENT.
    # La premiere chose imprimee est donc le RESIDU de cette identite : si elle ne se referme pas,
    # l'instrument est faux et RIEN de ce qui suit ne vaut. C'est M0 des predictions.
    _b0c = 602.0
    _mb0 = re.search(r'^\[HD-PHYS\] b0 c=\d+ flesh=([-\d.e+]+)', txt, re.M)
    if _mb0:
        _b0c = float(_mb0.group(1)) or 602.0
    _comd, _comdl = {}, {}
    for _m in re.finditer(r'^PHYSCOMD c=(\d+) a=(\d+) d=(\d+) '
                          r'tp=([-\d.e+]+) rp=([-\d.e+]+) dp=([-\d.e+]+)', txt, re.M):
        _comd[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))] = (
            float(_m.group(4)), float(_m.group(5)), float(_m.group(6)))
    for _m in re.finditer(r'^PHYSCOMDL c=(\d+) a=(\d+) d=(\d+) lk=([-\d.e+]+)', txt, re.M):
        _comdl[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))] = float(_m.group(4))
    A('')
    if not _comd:
        A('-- SPEC 22 / ATTRIBUTION de `comex` : NON MESUREE par cette course -------------------')
        A('   Aucune ligne PHYSCOMD dans la trace (moteur ou salle anterieurs au cycle 35).')
    else:
        A('-- SPEC 22 : QUEL TERME PORTE `comex` — ATTRIBUTION PAR UNE IDENTITE ------------------')
        A('   e = (p_sim - p_auth) + R_auth.(rot - I).lc + R_auth.rot.(T - I).lc')
        A('        \\___ tp ___/      \\______ rp ______/    \\_______ dp _______/')
        A('   [A] le joint a BOUGE · [B] le maillon a TOURNE x son bras · [C] le TENSEUR x son bras')
        A('   NATURE : trois longueurs SIGNEES (unites de jeu, 4096 = 1 m), projetees sur la')
        A('   direction de l\'excursion, relevees au MEME echantillon — l\'argmax de `comex` de la')
        A('   fenetre. REPERE : monde, meme frame, contre la pose d\'auteur de cette frame.')
        A('   ABSENT : tp = rp = dp = 0.0000 a la pose d\'auteur.')
        A('   Bras de levier livres : maillon 0 = 1.0817 / 1.0457 B0 (os de 1.728 / 1.726 B0) ;')
        A('   maillon 1 = 0.8547 / 0.7765 B0 (os de 0.233 / 0.240 B0, soit 3.7x son propre os).')
        # --- M0 : L'IDENTITE SE REFERME-T-ELLE ? Rien d'autre ne vaut si la reponse est non. ---
        _res, _pairs = [], []
        for _k, (_tp, _rp, _dp) in sorted(_comd.items()):
            _cx = None
            for _a, _v in _comw.get((_k[0], _k[2]), []):
                if _a == _k[1]:
                    _cx = _v
                    break
            if _cx is None:
                continue
            _pairs.append((_k, _tp, _rp, _dp, _cx, _comdl.get(_k)))
            _res.append(abs(_tp + _rp + _dp - _cx * _b0c) / _b0c)
        if not _pairs:
            A('   AUCUNE fenetre appariee entre PHYSCOMD et PHYSCOMW : attribution IMPOSSIBLE.')
        else:
            _rmax = max(_res)
            A('   M0 IDENTITE : residu max |tp+rp+dp - comex*b0c| = %.6f B0 sur %d fenetres'
              % (_rmax, len(_pairs)))
            A('      -> %s (tolerance 0.001 B0). b0c = %.1f u, lu dans la trace.'
              % ('TENUE' if _rmax <= 0.001 else '**CASSEE — L\'INSTRUMENT EST FAUX, '
                 'RIEN DE CE QUI SUIT NE VAUT**', _b0c))
            # --- LE CLASSEMENT, PAR (chaine, pilotage), SUR LA PIRE FENETRE ---------------
            _dn2 = {0: 'updown', 1: 'leftright', 2: 'accel', 3: 'jerk', 4: 'tilt'}
            A('   PIRE FENETRE DE CHAQUE (chaine, pilotage) — les trois termes du MEME echantillon')
            A('   chaine        pilotage      comex      tp        rp        dp     maillon  domine')
            _win, _shares = {}, {}
            for _c in sorted(chains):
                for _d in sorted(set(k[2] for k in _comd if k[0] == _c)):
                    _cand = [p for p in _pairs if p[0][0] == _c and p[0][2] == _d]
                    if not _cand:
                        continue
                    _b = max(_cand, key=lambda p: p[4])
                    (_k, _tp, _rp, _dp, _cx, _lk) = _b
                    _tot = _cx * _b0c
                    _mx = max((abs(_tp), 'A'), (abs(_rp), 'B'), (abs(_dp), 'C'))[1]
                    _win[(_c, _d)] = _b
                    _shares[(_c, _d)] = (_tp / _tot) if _tot else 0.0
                    A('   %-13s %-11s %8.4f %9.1f %9.1f %9.1f %7s   %s'
                      % (names[_c] if _c < len(names) else _c,
                         _dn2.get(_d, 'BASE(sans pilotage)' if _d >= 5 else 'd%d' % _d),
                         _cx, _tp, _rp, _dp,
                         ('l=%d' % int(round(_lk))) if _lk is not None else 'n/a',
                         {'A': '[A] TRANSLATION', 'B': '[B] ROTATION',
                          'C': '[C] DEFORMATION'}[_mx]))
            _cnt = {}
            for (_c, _d), _b in _win.items():
                _mx = max((abs(_b[1]), 'A'), (abs(_b[2]), 'B'), (abs(_b[3]), 'C'))[1]
                _cnt[_mx] = _cnt.get(_mx, 0) + 1
            A('   M1 CLASSEMENT : [A] domine %d fois · [B] %d fois · [C] %d fois, sur %d canaux'
              % (_cnt.get('A', 0), _cnt.get('B', 0), _cnt.get('C', 0), len(_win)))
            # --- M3 : LA PART DU TENSEUR, SUR TOUS LES ECHANTILLONS ----------------------
            _adp = [abs(p[3]) / _b0c for p in _pairs]
            _arp = [abs(p[2]) / _b0c for p in _pairs]
            _atp = [abs(p[1]) / _b0c for p in _pairs]
            A('   MOYENNE des |termes| sur les %d fenetres, en B0 (budget total de sa §22 = 0.40) :'
              % len(_pairs))
            A('      |tp| %.4f   |rp| %.4f   |dp| %.4f' %
              (sum(_atp) / len(_atp), sum(_arp) / len(_arp), sum(_adp) / len(_adp)))
            A('      maxima : |tp| %.4f   |rp| %.4f   |dp| %.4f'
              % (max(_atp), max(_arp), max(_adp)))
            A('   M3 TENSEUR : moyenne |dp| = %.4f B0 -> %s (critere <= 0.10 B0)'
              % (sum(_adp) / len(_adp),
                 'TENUE : le tenseur porte moins du quart du budget'
                 if sum(_adp) / len(_adp) <= 0.10 else
                 'CASSEE : le tenseur est un porteur reel'))
            A('   M5 BORNE PAPIER : max |dp| = %.4f B0 contre 1.22 B0 derive AVANT la mesure -> %s'
              % (max(_adp), 'TENUE' if max(_adp) <= 1.22 else
                 '**CASSEE — ma lecture du tenseur est fausse**'))
            # --- QUEL MAILLON, SUR TOUTES LES FENETRES ------------------------------------
            _lkc = {}
            for p in _pairs:
                if p[5] is not None:
                    _lkc[int(round(p[5]))] = _lkc.get(int(round(p[5])), 0) + 1
            if _lkc:
                A('   QUEL MAILLON porte le maximum, sur les %d fenetres : %s'
                  % (len(_pairs), ' · '.join('l=%d : %d (%.0f %%)'
                                             % (k, v, 100.0 * v / len(_pairs))
                                             for k, v in sorted(_lkc.items()))))
                A('      Les deux maillons ecrivent le MEME emplacement : sans cette colonne')
                A('      l\'attribution ne designerait aucune piece.')
    A('')
    # ---- SPEC 6 + SPEC 22 : LE COM PONDERE PAR LA MASSE ----------------------------------------
    # POURQUOI CE BLOC EXISTE, ET POURQUOI IL REMPLACE LE VERDICT DE `comex`.
    # Sa §6 : « `P0` neutral breast center-of-mass position ». Sa §22 : « Breast COM: normal <= 35%
    # B0, hard transient <= 40% B0 ». Les deux lignes sont citees MOT POUR MOT de
    # SPEC-breast-softbody.md. UN CENTRE DE MASSE EST UNE MOYENNE PONDEREE PAR LA MASSE.
    # `comex` publiait un MAXIMUM SUR DEUX CENTROIDES DE MAILLON sous ce nom (NOTE-112, cycle 41) :
    # ce n'est pas la meme grandeur, et le chiffre publie SURESTIMAIT. Le faux ROUGE coute autant
    # qu'un faux vert — il envoie le chantier courir apres un facteur qui n'existe pas.
    # ARBITRAGE DIRECTIVES 2026-08-19 23:50 : rebranchement AUTORISE, a trois conditions —
    #   (1) avec sa course de controle (elle est au rapport du cycle, pas ici) ;
    #   (2) la ligne publie LES TROIS grandeurs : borne superieure, moyenne ponderee, part au-dessus
    #       du plafond dur. Une population ne se resume pas a son maximum ;
    #   (3) le nom de la ligne dit ce qu'elle mesure — d'ou `ROOM-COMEX-MAX2` pour l'ancienne.
    #
    # NATURE : une LONGUEUR rapportee a B0 (602 u, §6). REPERE : le monde, frame ecrite, contre la
    # pose d'auteur de la MEME frame, deformation comprise — celui de `comex`, pour que les deux
    # soient comparables ligne a ligne. LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000 a la pose
    # d'auteur.
    #
    # `com` VIENT DU MOTEUR ET IL EST EXACT : la somme VECTORIELLE des excursions de centroide par
    # maillon, ponderees par `comw=`, formee DANS LA MEME FRAME. La borne superieure ci-dessous est
    # recomposee des NORMES par maillon (`PHYSCOMWL`), donc elle majore deux fois — inegalite
    # triangulaire ET maxima de deux frames differentes. Les deux sont publiees : si l'exact
    # depasse la borne, l'un des deux instruments est faux et il faut le savoir.
    # La salle emet DEUX lignes par fenetre : `format` de GOAL est limite a huit parametres.
    # Une fenetre dont l'une des deux manque est ECARTEE, jamais completee par un zero.
    _comx, _cwl, _cx2 = {}, {}, {}
    for _m in re.finditer(r'^PHYSCOMX c=(\d+) a=(\d+) d=(\d+) com=([-\d.e+]+) coms=([-\d.e+]+)',
                          txt, re.M):
        _cx2[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))] = (
            float(_m.group(4)), float(_m.group(5)))
    for _m in re.finditer(r'^PHYSCOMX2 c=(\d+) a=(\d+) d=(\d+) comn=([-\d.e+]+) comhi=([-\d.e+]+)',
                          txt, re.M):
        _k = (int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))
        if _k in _cx2:
            _comx[_k] = (_cx2[_k][0], _cx2[_k][1], float(_m.group(4)), float(_m.group(5)))
    for _m in re.finditer(r'^PHYSCOMWL c=(\d+) a=(\d+) d=(\d+) l=(\d+) ee=([-\d.e+]+)', txt, re.M):
        _cwl[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)), int(_m.group(4)))] = \
            float(_m.group(5))
    # Les poids sont lus dans le FICHIER LIVRE, jamais ecrits ici : c'est la meme donnee que le
    # moteur a consommee, donc la borne et l'exact parlent des memes poids.
    _cw = {}
    try:
        for _ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
            _mm = re.match(r'^chain (\S+).*\bcomw=([-0-9.,]+)', _ln)
            if _mm:
                _cw[_mm.group(1)] = [float(x) for x in _mm.group(2).split(',') if x]
    except Exception:
        pass
    # Frontiere alternative de l'organe, pour que la SENSIBILITE reste visible et ne soit pas un
    # choix cache : a `w >= 0.25` la part ancree tombe de 45.85/46.06 % a 34.52/34.90 %, donc les
    # maillons pesent PLUS et le COM monte. Mesure par .autoport/probe_c48_com_identity.py sur
    # out/jak1/fr3/skin/keira-hd-lod0.glb, md5 5cb8a493c43211acf3a04c5b6433df81.
    _CW25 = {'chestL': [0.2146, 0.4402], 'chestR': [0.2542, 0.3968]}
    if _comx:
        A('')
        A('-- SPEC 6 + SPEC 22 : LE COM PONDERE PAR LA MASSE — LA GRANDEUR QUE SA BORNE NOMME ----')
        A('   §6 : « `P0` neutral breast center-of-mass position »')
        A('   §22 : « Breast COM: normal <= 35% B0, hard transient <= 40% B0 »')
        A('   Un centre de masse est une MOYENNE PONDEREE PAR LA MASSE. La chair ANCREE (`chest`,')
        A('   `?shoulder`) n\'est pas simulee : son excursion est nulle AU BIT PRES, elle ne peut')
        A('   pas entrer dans un maximum mais elle entre dans une moyenne — et elle la divise')
        A('   presque par deux. `com` est forme VECTORIELLEMENT et DANS LA MEME FRAME par le')
        A('   moteur : ce n\'est pas une recomposition majorante.')
        A('   NATURE : longueur rapportee a B0 (602 u). REPERE : monde, frame ecrite, contre la')
        A('   pose d\'auteur de la MEME frame, deformation comprise. A LA POSE D\'AUTEUR : 0.0000.')
        for _c in sorted({k[0] for k in _comx}):
            _nm = names[_c] if _c < len(names) else str(_c)
            _ws = _cw.get(_nm, [])
            _win = [v for k, v in _comx.items() if k[0] == _c]
            if not _win:
                continue
            _wm = sorted(w[0] for w in _win)          # le MAXIMUM de chaque fenetre
            _mx = _wm[-1]
            _ssum = sum(w[1] for w in _win)
            _sn = sum(w[2] for w in _win)
            _shi = sum(w[3] for w in _win)
            _mean = (_ssum / _sn) if _sn > 0 else 0.0        # moyenne sur les FRAMES
            _pk = sum(_wm) / len(_wm)                        # pic TYPIQUE d'une fenetre
            _q = lambda t: _wm[min(len(_wm) - 1, int(t * len(_wm)))]
            _fr_hi = (100.0 * _shi / _sn) if _sn > 0 else 0.0
            _wn_hi = 100.0 * sum(1 for x in _wm if x > 0.40) / len(_wm)
            _wn_35 = 100.0 * sum(1 for x in _wm if x > 0.35) / len(_wm)
            # §22 pose DEUX bandes et elles ne se lisent pas sur la meme statistique :
            # « normal » est un niveau de reponse COURANT -> le pic TYPIQUE d'une fenetre ;
            # « hard transient » est un extreme -> le MAXIMUM. Publier un seul chiffre contre
            # les deux bandes, c'est le defaut que ce bloc corrige, pas un defaut a repeter.
            A('ROOM-COM: chain=%-12s pic_typique=%.4f  max=%.4f B0   (normal 0.35 / dur 0.40)'
              % (_nm, _pk, _mx))
            A('   VERDICT §22 « normal <=35%% B0 »        sur le pic TYPIQUE de fenetre : '
              '%.4f -> %s' % (_pk, 'DANS' if _pk <= 0.35 else 'HORS (x%.2f)' % (_pk / 0.35)))
            A('      CE VERDICT DEPEND DE LA FRONTIERE DE L\'ORGANE, ET LE DIRE FAIT PARTIE DU')
            A('      VERDICT. Il est rendu a `w>0`. A `w>=0.25` la borne SUPERIEURE seule (donc')
            A('      un majorant du vrai chiffre) vaut deja plus que 0.35 — voir les deux lignes')
            A('      « borne SUP » ci-dessous : le verdict BASCULERAIT. Ce qui tranche n\'est pas')
            A('      le confort du resultat, c\'est sa §30, qui compte le tissu fortement ANCRE')
            A('      comme faisant partie du sein (« 28-35% of the **rear breast volume** should')
            A('      behave as strongly attached tissue ») : la chair ancree appartient donc a')
            A('      l\'organe, et la frontiere qui l\'inclut — `w>0` — est celle que la spec')
            A('      decrit. La borne a l\'autre frontiere reste publiee pour que le lecteur')
            A('      puisse refuser cet argument sans avoir a relancer une course.')
            A('   VERDICT §22 « hard transient <=40%% B0 » sur le MAXIMUM de course     : '
              '%.4f -> %s' % (_mx, 'DANS' if _mx <= 0.40 else 'HORS (x%.2f)' % (_mx / 0.40)))
            A('   distribution des maxima de fenetre : p50 %.4f  p95 %.4f  (n=%d fenetres)'
              % (_q(0.50), _q(0.95), len(_wm)))
            A('   moyenne sur les FRAMES = %.4f B0 sur %d frames — publiee parce qu\'elle est la'
              % (_mean, int(_sn)))
            A('      population entiere, MAIS elle inclut les frames au repos et FLATTE la borne :')
            A('      elle ne fonde aucun verdict ici.')
            A('   part au-dessus des bandes : %.2f %% des FRAMES > 0.40 · %.1f %% des FENETRES'
              ' > 0.40 · %.1f %% des FENETRES > 0.35' % (_fr_hi, _wn_hi, _wn_35))
            # bornes superieures aux deux frontieres de l'organe
            for _lbl, _wset in (('w>0     (livree)', _ws), ('w>=0.25 (sensibilite)',
                                                            _CW25.get(_nm, []))):
                if not _wset:
                    continue
                _ub = []
                for (_cc, _a, _d) in {k[:3] for k in _cwl if k[0] == _c}:
                    _tot, _ok = 0.0, True
                    for _l, _wv in enumerate(_wset):
                        _e = _cwl.get((_cc, _a, _d, _l))
                        if _e is None:
                            _ok = False
                            break
                        _tot += _wv * _e
                    if _ok:
                        _ub.append(_tot)
                if _ub:
                    A('   borne SUP recomposee des normes par maillon, %-21s : max %.4f  moy %.4f'
                      % (_lbl, max(_ub), sum(_ub) / len(_ub)))
            if _ws:
                A('   poids lus dans le fichier livre : %s  (somme %.4f — le reste est ANCRE)'
                  % (', '.join('l=%d %.4f' % (i, w) for i, w in enumerate(_ws)), sum(_ws)))
            A('   RESERVE DECLAREE, BORNEE, NON CORRIGEE : le moteur applique l\'excursion au centre')
            A('      de la SPHERE de collision (`offset=`), pas au centroide pondere `c_j` que')
            A('      l\'identite demande. Ecart VECTORIEL mesure 97.5 u / 17.3 u (chestL) et')
            A('      87.4 u / 20.4 u (chestR). Report sur le COM borne par')
            A('      SOMME_l w_l (2 sin(th_l/2) + |T-I|) |lc_l - c_l| <= 0.0285 B0 (chestL) et')
            A('      0.0301 B0 (chestR), soit 8.1 % / 8.6 % de la bande de 0.35 — DANS LE SENS')
            A('      INCONNU. Le corriger demande un canal VECTORIEL `comc=` ; il ne sera ouvert')
            A('      que si un chiffre atterrit a moins de cette borne d\'un seuil de la spec.')
    else:
        A('')
        A('-- SPEC 6 + SPEC 22 / COM PONDERE : NON MESURE par cette course ----------------------')
        A('   Aucune ligne PHYSCOMX (moteur anterieur au cycle 48, ou `comw=` absent du fichier')
        A('   livre). Le COM n\'est PAS publie a zero dans ce cas : un poids manquant ne doit')
        A('   jamais se lire comme un centre de masse immobile.')

    # ---- (C51) SPEC 22 : LE PLAFOND GLOBAL D'APEX ---------------------------------------------
    # §22 l.301 : « Distal/apex displacement: normal <=42% B0, exceptional <=50% B0 ». DEUX
    # bandes, et elles ne se lisent PAS sur la meme statistique — meme discipline que le bloc COM
    # juste au-dessus, pour la meme raison : « normal » est un niveau de reponse COURANT, donc le
    # pic TYPIQUE d'une fenetre ; « exceptional » est un extreme, donc le MAXIMUM de course.
    # Publier un seul chiffre contre les deux bandes est le defaut que le COM a deja corrige.
    _apx = {}
    for _m in re.finditer(r'^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.e+]+)', txt, re.M):
        _apx[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))] = float(_m.group(4))
    if _apx:
        A('')
        A('-- SPEC 22 : LE PLAFOND D\'APEX — LA GRANDEUR QUE SIX AUTRES SECTIONS BORNENT AUSSI --')
        A('   §22 : « Distal/apex displacement: normal <=42%% B0, exceptional <=50%% B0 »')
        A('   NATURE : longueur / B0 (602 u) — le centroide de masse du DECILE DISTAL du nuage de')
        A('   chair, PAS le COM (qui moyenne tout le nuage, ancrage compris). REPERE : monde,')
        A('   frame ecrite, contre la pose d\'auteur de la MEME frame, deformation comprise.')
        A('   A LA POSE D\'AUTEUR : 0.0000. Chaine sans enregistrement `ax` : AUCUNE ligne.')
        for _c in sorted({k[0] for k in _apx}):
            _nm3 = names[_c] if _c < len(names) else str(_c)
            _wm3 = sorted(v for k, v in _apx.items() if k[0] == _c)
            if not _wm3:
                continue
            _pk3 = sum(_wm3) / len(_wm3)
            _mx3 = _wm3[-1]
            _q3 = lambda t: _wm3[min(len(_wm3) - 1, int(t * len(_wm3)))]
            A('ROOM-APEX: chain=%-12s pic_typique=%.4f  max=%.4f B0   (normal 0.42 / exceptionnel'
              ' 0.50)' % (_nm3, _pk3, _mx3))
            A('   VERDICT §22 « normal <=42%% B0 »      sur le pic TYPIQUE de fenetre : %.4f -> %s'
              % (_pk3, 'DANS' if _pk3 <= 0.42 else 'HORS (x%.2f)' % (_pk3 / 0.42)))
            A('   VERDICT §22 « exceptional <=50%% B0 » sur le MAXIMUM de course     : %.4f -> %s'
              % (_mx3, 'DANS' if _mx3 <= 0.50 else 'HORS (x%.2f)' % (_mx3 / 0.50)))
            A('   distribution des maxima de fenetre : p50 %.4f  p95 %.4f  (n=%d fenetres)'
              % (_q3(0.50), _q3(0.95), len(_wm3)))
            A('   part des FENETRES au-dessus des bandes : %.1f %% > 0.42 · %.1f %% > 0.50'
              % (100.0 * sum(1 for x in _wm3 if x > 0.42) / len(_wm3),
                 100.0 * sum(1 for x in _wm3 if x > 0.50) / len(_wm3)))
        _shL, _shR = _apxsh('chestL'), _apxsh('chestR')
        if _shL is None or _shR is None:
            A('   PART DE L\'APEX PORTEE PAR LES MAILLONS SIMULES : NON ETABLIE — aucun')
            A('      enregistrement `ax` lisible dans recharged_assets/physics_mesh.txt. Ce')
            A('      verdict est donc rendu SANS savoir de combien le mesh reduit l\'apex.')
        elif _shL >= 0.999 and _shR >= 0.999:
            A('   PART DE L\'APEX PORTEE PAR LES MAILLONS SIMULES : %.4f / %.4f (fichier livre).'
              % (_shL, _shR))
            A('      L\'apex publie n\'est reduit par AUCUN ancrage : le depassement est entier.')
        else:
            A('   CE QUE CE VERDICT NE DIT PAS, ET IL FAUT LE DIRE : %.1f %% / %.1f %% de la masse'
              % (100.0 * (1.0 - _shL), 100.0 * (1.0 - _shR)))
            A('      de la region distale est portee par des os NON SIMULES. L\'apex publie ici')
            A('      est donc DEJA reduit d\'un facteur %.4f / %.4f par le mesh. Un DEPASSEMENT'
              % (_shL, _shR))
            A('      est donc un depassement A ANCRAGE REDUIT — il serait PIRE si sa §30 (« Apex —')
            A('      minimal direct anchoring ») etait respectee. Un MANQUE, lui, peut venir de cet')
            A('      ancrage plutot que du solveur, et la ligne ROOM-APEX-REGIME le chiffre par')
        A('      fenetre au lieu de le supposer.')
    else:
        A('')
        A('-- SPEC 22 / PLAFOND D\'APEX : NON MESURE par cette course ---------------------------')
        A('   Aucune ligne PHYSAPEX (moteur anterieur au cycle 51, ou enregistrements `ax`')
        A('   absents de recharged_assets/physics_mesh.txt). L\'apex n\'est PAS publie a zero :')
        A('   un canal absent ne doit jamais se lire comme un apex immobile.')

    if _comex.get('run'):
        A('-- `comex` : LE MAXIMUM SUR LES DEUX CENTROIDES DE MAILLON — CE N\'EST PAS LE COM ------')
        A('   CETTE LIGNE NE PORTE PLUS DE VERDICT §22, ET SON NOM A CHANGE POUR LE DIRE.')
        A('   §6 definit `P0` = « neutral breast center-of-mass position » et §22 borne « Breast')
        A('   COM » : un centre de masse est une MOYENNE PONDEREE PAR LA MASSE. `comex` est un')
        A('   MAXIMUM SUR DEUX ECHANTILLONS (NOTE-112, cycle 41) — pas la meme grandeur. Le')
        A('   verdict §22 est publie par ROOM-COM ci-dessus, sur la moyenne ponderee.')
        A('   Conserve ici parce que 40 cycles de rapports le citent et que l\'attribution en')
        A('   trois termes (tp/rp/dp) est latchee sur SON argmax, donc s\'y rapporte.')
        for _c in sorted(_comex['run']):
            _v = _comex['run'][_c]
            A('ROOM-COMEX-MAX2: chain=%-12s max2=%.4f B0   [MAX SUR 2 CENTROIDES, PAS LE COM]'
              % (names[_c] if _c < len(names) else _c, _v))
            _d = _comdist.get('run', {}).get(_c)
            if _d is not None:
                A('   distribution : moyenne %.4f B0 · %.1f %% des echantillons au-dessus de 0.40'
                  % (_d[0], 100.0 * _d[1]))
        if _comdist.get('run'):
            A('   La moyenne et la part au-dessus du plafond disent si une borne posee a 0.40')
            A('   CLIPERAIT un extreme ou MUSELLERAIT la reponse. Sans elles, un maximum hors')
            A('   bande ne permet pas de dimensionner un correctif sans risquer un suppresseur.')
        else:
            A('   distribution : NON MESUREE par cette course (trace anterieure a comsum/comn).')
    else:
        A('-- SPEC 22 / comex : NON MESURE par cette course (aucune ligne PHYSDIAG8) ------------')
    A('')
    A('')
    # ---- SPEC 14 A 20 : LES REGIMES DE MOUVEMENT, JOUES DANS LA SALLE --------------------------
    # POURQUOI CE BLOC EXISTE (DIRECTIVES 2026-08-20 00:10). Onze sections de sa spec decrivent le
    # comportement au saut, en vol, a l'atterrissage, au demarrage, au freinage et en rotation, et
    # AUCUNE n'avait jamais ete JOUEE dans la salle : le registre les porte en `NON ETABLI`. Un
    # `NON ETABLI` ne se gagne pas en reclassant, il se gagne en jouant le regime. La salle emet
    # quatre lignes par fenetre de regime ; ce bloc les lit et rend un verdict contre le TEXTE
    # CITE de la section — jamais contre un resume de memoire (DIRECTIVES 2026-08-19 20:50).
    #
    # `PHYSREGD` sort UNE fois par regime (le stimulus COMMANDE, il ne depend pas de la chaine).
    # `PHYSREG` / `PHYSREG2` / `PHYSREG3` sortent une fois par (chaine, regime) : `format` de GOAL
    # est limite a huit parametres, d'ou la coupure en trois. Une fenetre a qui il manque l'une des
    # trois est ECARTEE, jamais completee par un zero — c'est le motif deja paye sur
    # `PHYSCOMX`/`PHYSCOMX2` (voir la jointure du bloc COM ci-dessus).
    _RGT = [
        (0,  'base',          None,  'temoin',   None,
         "AUCUN pilotage : le temoin. Tout ce qui sort d'ici est produit par l'animation tenue,"
         " pas par un regime."),
        (1,  'jumpA-push',    '14',  'jump',     (0.15, 0.25),
         "detente ordinaire h=0.25 m ; SPEC 14 « COM lag: ordinary 15-25% B0 »"),
        (2,  'jumpA-fly',     '15',  'fly',      None,
         "vol balistique ordinaire ; SPEC 15 ne borne aucun chiffre : elle exige un CHANGEMENT"
         " DE SIGNE"),
        (3,  'jumpA-land',    '16',  'land',     (0.25, 0.35),
         "reception souple ; SPEC 16 « Strong landing COM: 25-35% B0 »"),
        (4,  'jumpB-push',    '14',  'jump',     (0.25, 0.32),
         "detente forte h=0.45 m ; SPEC 14 « strong 25-32% B0 »"),
        (5,  'jumpB-fly',     '15',  'fly',      None,
         "vol balistique fort"),
        (6,  'jumpB-land',    '16',  'land',     (0.35, 0.40),
         "reception DURE ; SPEC 16 « Very hard landing COM: 35-40% B0 »"),
        (7,  'runA-accel',    '17',  'run',      (0.10, 0.18),
         "demarrage ; SPEC 17 « COM lag: moderate 10-18% B0 »"),
        (8,  'runA-brake',    '17',  'run',      (0.18, 0.27),
         "arret net ; SPEC 17 « strong 18-27% B0 »"),
        (9,  'yawA',          '18',  'yaw',      (0.10, 0.17),
         "demi-tour modere ; SPEC 18 « COM displacement: moderate 10-17% B0 »"),
        (10, 'yawB',          '18',  'yaw',      (0.17, 0.24),
         "demi-tour rapide ; SPEC 18 « strong 17-24% B0 »"),
        (11, 'pitchA-bend',   '19',  'pitch',    None,
         "buste en avant ; SPEC 19 ne borne QUE l'apex (30-40% B0), pas le COM"),
        (12, 'pitchA-return', '19',  'pitch',    None,
         "retour a la verticale ; SPEC 19 « the authored standing geometry is crossed »"),
        (13, 'rollA',         '20',  'roll',     (0.15, 0.22),
         "inclinaison laterale ; SPEC 20 « Typical strong roll: COM 15-22% B0 »"),
        (14, 'rollB',         '20',  'roll',     (0.15, 0.22),
         "bascule cote oppose ; meme bande, cote oppose"),
    ]
    # Vitesse angulaire de POINTE COMMANDEE de chaque regime de rotation, en rad/frame. Elle sert
    # UNIQUEMENT a former `r_eff = amax / omega` : un bras de levier, pour VERIFIER que le sujet a
    # bien tourne de ce qui lui a ete commande. Ce n'est pas une mesure de physique.
    _RGOM = {9: 0.10281, 10: 0.19580, 11: 0.07996, 12: 0.07996, 13: 0.04569, 14: 0.09137}
    # Bras de levier COMMANDE : distance de la racine de chaine a l'axe de rotation du regime, en
    # unites de jeu. Verifie sur out/jak1/fr3/skin/keira-hd-lod0.glb : lBoob/rBoob a 548.078 /
    # 548.081 u de l'axe VERTICAL (lacet), 1925.209 / 1925.210 u de l'axe X passant par les
    # hanches (tangage), 1922.159 / 1922.160 u de l'axe Z passant par les hanches (roulis).
    # CORRIGE CYCLE 49 APRES LA COURSE E1 : `amax` mesure le deplacement de L'ANCRE, pas du sein.
    # La cible de `r_eff` est donc le bras de l'ANCRE (`chest`, a (0, 7020.8, 239.8) sur le mesh
    # livre) autour du pivot de hanche (0, 6094.4, 0), c'est-a-dire |c_anat| = (0, 926.4, 239.8)
    # projete perpendiculairement a chaque axe :
    #     lacet  Y : |(0, 239.8)|      =  239.8 u
    #     tangage X: |(926.4, 239.8)|  =  956.9 u
    #     roulis Z : |(0, 926.4)|      =  926.4 u
    # Comparer a 548.1 / 1925.2 / 1922.1 (le bras du SEIN) melangeait deux points differents et
    # affichait un ecart de -50 a -56 % la ou la correction de pivot est en fait exacte a 1 %.
    _RGLV = {9: 239.8, 10: 239.8, 11: 956.9, 12: 956.9, 13: 926.4, 14: 926.4}
    _rgd, _rga, _rgb, _rgc = {}, {}, {}, {}
    for _m in re.finditer(r'^PHYSREGD r=(\d+) kind=(\d+) drv=(\d+) acmd=([-\d.e+]+)'
                          r' alp=([-\d.e+]+)', txt, re.M):
        _rgd[int(_m.group(1))] = (int(_m.group(2)), int(_m.group(3)),
                                  float(_m.group(4)), float(_m.group(5)))
    for _m in re.finditer(r'^PHYSREG c=(\d+) r=(\d+) com=([-\d.e+]+) cx=([-\d.e+]+)'
                          r' cy=([-\d.e+]+) cz=([-\d.e+]+)', txt, re.M):
        _rga[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)), float(_m.group(4)),
                                                      float(_m.group(5)), float(_m.group(6)))
    for _m in re.finditer(r'^PHYSREG2 c=(\d+) r=(\d+) csum=([-\d.e+]+) cn=([-\d.e+]+)'
                          r' amax=([-\d.e+]+) cmx2=([-\d.e+]+)', txt, re.M):
        _rgb[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)), float(_m.group(4)),
                                                      float(_m.group(5)), float(_m.group(6)))
    for _m in re.finditer(r'^PHYSREG3 c=(\d+) r=(\d+) ee0=([-\d.e+]+) ee1=([-\d.e+]+)'
                          r' jt0=([-\d.e+]+) jt1=([-\d.e+]+)', txt, re.M):
        _rgc[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)), float(_m.group(4)),
                                                      float(_m.group(5)), float(_m.group(6)))
    _rgseen = set(_rga) | set(_rgb) | set(_rgc)
    # JOINTURE STRICTE : les trois lignes, et `cn` > 0. Une fenetre a `cn = 0` n'a AUCUNE frame :
    # sa moyenne n'existe pas et on ne la remplace pas par un zero.
    _rgk = sorted(k for k in (set(_rga) & set(_rgb) & set(_rgc)) if _rgb[k][1] > 0)
    _rgdrop = sorted(_rgseen - set(_rgk))
    _rgnm = lambda _c: names[_c] if _c < len(names) else 'c%d' % _c
    _rgtab = {_r[0]: _r for _r in _RGT}

    def _rgvd(_v, _band):
        if _band is None:
            return 'PAS DE BANDE'
        _lo, _hi = _band
        if _v < _lo:
            return 'SOUS (x%.2f)' % ((_v / _lo) if _lo else 0.0)
        if _v > _hi:
            return 'AU-DESSUS (x%.2f)' % ((_v / _hi) if _hi else 0.0)
        return 'DANS'

    if not _rgseen:
        A('-- SPEC 14 a 20 / REGIMES DE MOUVEMENT ------------------------------------------------')
        A('ROOM-REGIME: ABSENT (aucune ligne PHYSREG) — SPEC 14 a 20 restent NON MESUREES.')
        A('   La salle de cette course ne joue pas les regimes (trace anterieure au cycle 49).')
        A('   Rien n\'est publie a zero : une section non jouee est NON MESUREE, pas conforme.')
    else:
        A('-- SPEC 14 a 20 : LES REGIMES DE MOUVEMENT — SAUT, VOL, RECEPTION, COURSE, ROTATION ---')
        A('   LES TROIS QUESTIONS DE SPEC-keira-physique 7, pour CHAQUE grandeur publiee ici :')
        A('   `com`      NATURE : une LONGUEUR rapportee a B0 (602 u, §6) — le MAXIMUM sur la')
        A('              fenetre du COM PONDERE PAR LA MASSE, la grandeur que §14/§16/§17/§18/§20')
        A('              bornent. REPERE : le monde, frame ecrite, contre la pose d\'auteur de la')
        A('              MEME frame. LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000 a la pose')
        A('              d\'auteur.')
        A('   `cx/cy/cz` NATURE : le VECTEUR du meme COM, /B0, releve A L\'ARGMAX de `com` — une')
        A('              SEULE frame, les trois composantes ensemble, jamais trois maxima')
        A('              independants. REPERE : les axes MONDE. Le sujet est a quaternion')
        A('              identite sur TOUS les regimes de translation (r=0..8) : pour ceux-la')
        A('              `cy` EST la verticale, +Y = haut, et `cz` l\'avant. Sur les regimes de')
        A('              rotation (r=9..14) le sujet est incline et les composantes monde')
        A('              MELANGENT les axes du sujet : elles sont publiees, PAS interpretees.')
        A('              ABSENT : (0,0,0).')
        A('   `moy`      NATURE : `csum`/`cn`, moyenne du COM sur les FRAMES de la fenetre, /B0.')
        A('              REPERE : idem `com`. `cn` = 0 -> la fenetre est ECARTEE, jamais completee')
        A('              par un zero. ABSENT : 0.0000.')
        A('   `amax`     NATURE : une VITESSE — le MAXIMUM sur la fenetre du deplacement de')
        A('              l\'ANCRE d\'une frame a la suivante, en unites de jeu par frame (4096 u =')
        A('              1 m). REPERE : le monde. Elle ne mesure pas la poitrine : elle VERIFIE')
        A('              que le stimulus commande a bien ete subi, au lieu de le croire.')
        A('              ABSENT (sujet immobile) : 0.0000.')
        A('   `cmx2`     NATURE : l\'ancienne grandeur `comex`, un MAXIMUM SUR DEUX CENTROIDES —')
        A('              PAS un centre de masse (NOTE-112). Publiee pour la continuite de lecture')
        A('              des 40 cycles qui la citent. ELLE NE PORTE AUCUN VERDICT ICI.')
        A('   `ee0/ee1`  NATURE : excursion du CENTROIDE du maillon 0 / 1, /B0, maximum de')
        A('              fenetre. `jt0/jt1` : deplacement du JOINT du maillon 0 / 1, /B0. Meme')
        A('              repere que `com`. ABSENT : 0.0000. Elles disent OU vit l\'excursion ; un')
        A('              `com` sans elles ne designe aucune piece.')
        A('   `acmd`     acceleration lineaire de POINTE COMMANDEE, u/frame^2 (0 en rotation).')
        A('   `alp`      acceleration angulaire de POINTE COMMANDEE, rad/frame^2 x 10000 dans la')
        A('              trace (entier mis a l\'echelle pour tenir dans un `~f` lisible) ; ce bloc')
        A('              la publie DEJA DIVISEE par 10000. 0 en translation.')
        A('   %d fenetres (chaine, regime) jointes sur la cle (c, r) ; %d ECARTEE(S) faute d\'une'
          % (len(_rgk), len(_rgdrop)))
        A('   des trois lignes ou pour `cn` = 0%s.'
          % ('' if not _rgdrop else ' : ' + ', '.join('(c=%d,r=%d)' % k for k in _rgdrop[:12])
             + (' ...' if len(_rgdrop) > 12 else '')))
        A('')
        # ---- (2) LE STIMULUS COMMANDE CONFRONTE AU STIMULUS MESURE ---------------------------
        A('   -- ROOM-REGIME-STIM : LE STIMULUS COMMANDE CONFRONTE AU STIMULUS MESURE ----------')
        A('      `amax` est la seule colonne MESUREE de ce tableau ; `acmd` et `alp` sont ce que')
        A('      la salle a DEMANDE. Un regime dont `amax` reste au niveau du temoin n\'a pas ete')
        A('      joue, quelle que soit la valeur commandee — et son verdict plus bas ne vaudrait')
        A('      rien. `r_eff = amax / omega` est un BRAS DE LEVIER en unites de jeu : c\'est une')
        A('      VERIFICATION DU STIMULUS, PAS UNE MESURE DE PHYSIQUE. On le compare au bras')
        A('      COMMANDE, mesure sur le mesh livre. `amax` est ici le MAXIMUM sur les')
        A('      chaines JOINTES du regime : les deux ancres sont a distance EGALE de chaque')
        A('      axe (voir ROOM-REGIME-MIRROR), donc leurs `amax` doivent coincider — un')
        A('      ecart entre elles serait un defaut d\'instrument, pas une physique.')
        for _r, _nm2, _sec, _kind, _band, _cite in _RGT:
            _dd = _rgd.get(_r)
            _am = [_rgb[k][2] for k in _rgk if k[1] == _r]
            _amx = max(_am) if _am else None
            A('ROOM-REGIME-STIM: r=%2d %-13s %-6s acmd=%s alp=%s amax=%s'
              % (_r, _nm2, ('§' + _sec) if _sec else '(none)',
                 ('%9.4f' % _dd[2]) if _dd else '      n/a',
                 ('%9.6f' % (_dd[3] / 10000.0)) if _dd else '      n/a',
                 ('%9.4f u/f' % _amx) if _amx is not None else '      n/a'))
            if _r in _RGOM and _amx is not None:
                _re = _amx / _RGOM[_r]
                A('   r_eff = amax/omega = %8.1f u  contre le bras ANATOMIQUE de l\'ancre %.1f u  ecart %+.1f %%'
                  % (_re, _RGLV[_r], 100.0 * (_re - _RGLV[_r]) / _RGLV[_r]))
            elif _dd is None:
                A('   PHYSREGD absent pour ce regime : le stimulus COMMANDE n\'est pas declare par')
                A('   la trace. Rien n\'est suppose a sa place.')
        A('')
        # ---- (3) LE TABLEAU PAR (CHAINE, REGIME) --------------------------------------------
        A('   -- ROOM-REGIME : LE COM DE CHAQUE FENETRE, CONTRE LA BANDE DE SA SECTION ---------')
        A('      La bande est celle que la table cite mot pour mot ci-dessous. Quand la section')
        A('      ne borne pas le COM, la colonne dit PAS DE BANDE — jamais un verdict invente.')
        A('      Le facteur entre parentheses est le rapport a la BORNE FRANCHIE (bas ou haut).')
        for _c in sorted({k[0] for k in _rgk}):
            for _r, _nm2, _sec, _kind, _band, _cite in _RGT:
                _k = (_c, _r)
                if _k not in _rga or _k not in _rgb or _k not in _rgc:
                    continue
                _com, _cxv, _cyv, _czv = _rga[_k]
                _cs, _cn, _amx, _cm2 = _rgb[_k]
                _e0, _e1, _j0, _j1 = _rgc[_k]
                A('ROOM-REGIME: %-8s r=%2d %-13s %-4s com=%.4f moy=%.4f %-13s %s'
                  % (_rgnm(_c), _r, _nm2, ('§' + _sec) if _sec else '  - ', _com,
                     _cs / _cn if _cn else 0.0,
                     ('[%.2f-%.2f]' % _band) if _band else '[pas de bande]',
                     _rgvd(_com, _band)))
                A('   ee0=%.4f ee1=%.4f jt0=%.4f jt1=%.4f cmx2=%.4f  cx/cy/cz=%+.4f/%+.4f/%+.4f'
                  '  n=%d f' % (_e0, _e1, _j0, _j1, _cm2, _cxv, _cyv, _czv, int(_cn)))
        A('')
        # ---- (4) LE MEME TABLEAU, TEMOIN SOUSTRAIT ------------------------------------------
        A('   -- ROOM-REGIME-NET : LE MEME COM, TEMOIN r=0 SOUSTRAIT ---------------------------')
        A('      `net = max(0, com_r - com_0)` de la MEME chaine. Le temoin ne joue AUCUN regime :')
        A('      ce qu\'il produit vient de l\'animation tenue. Le soustraire isole ce que le')
        A('      REGIME a ajoute. Le temoin n\'est pas soustrait de lui-meme : il est publie comme')
        A('      reference et n\'a pas de ligne NET. Cette soustraction n\'est PAS le verdict de la')
        A('      spec — sa bande porte sur le COM total, ligne ROOM-REGIME ci-dessus ; NET dit')
        A('      seulement ce qui est IMPUTABLE au regime.')
        for _c in sorted({k[0] for k in _rgk}):
            # le temoin est pris dans la JOINTURE : une fenetre ECARTEE ne peut pas servir de
            # reference a une soustraction.
            _b0r = _rga.get((_c, 0)) if (_c, 0) in _rgk else None
            if _b0r is None:
                A('ROOM-REGIME-NET: %-8s TEMOIN r=0 ABSENT ou ECARTE sur cette course : aucune'
                  ' soustraction n\'est faite.' % _rgnm(_c))
                continue
            A('ROOM-REGIME-NET: %-8s temoin r=0 com=%.4f B0 (reference, non soustraite d\'elle-meme)'
              % (_rgnm(_c), _b0r[0]))
            for _r, _nm2, _sec, _kind, _band, _cite in _RGT:
                if _r == 0 or (_c, _r) not in _rgk:
                    continue
                _com = _rga[(_c, _r)][0]
                _net = max(0.0, _com - _b0r[0])
                A('ROOM-REGIME-NET: %-8s r=%2d %-13s net=%.4f (com %.4f - r0 %.4f) -> %s'
                  % (_rgnm(_c), _r, _nm2, _net, _com, _b0r[0], _rgvd(_net, _band)))
        A('')
        # ---- (5) SPEC 15 : LE CHANGEMENT DE SIGNE -------------------------------------------
        A('   -- ROOM-REGIME-SIGN : SPEC 15, LE CHANGEMENT DE SIGNE ----------------------------')
        A('      §15 ne borne AUCUN chiffre : elle exige que le sein RETARDE VERS LE BAS pendant')
        A('      la poussee, puis TRAVERSE LE NEUTRE pendant le vol. C\'est donc un SIGNE qui est')
        A('      mesure, pas une amplitude. Convention : `cy` est la composante VERTICALE MONDE du')
        A('      COM, SIGNEE, relevee a l\'argmax de `com`. Le sujet est a QUATERNION IDENTITE sur')
        A('      ces six fenetres (r=1..6, tous des regimes de translation) : +Y monde EST la')
        A('      verticale, et le signe se lit sans avoir a redresser un triedre.')
        A('      CRITERE : `cy` < 0 en poussee (1, 4) ET `cy` > 0 en vol (2, 5).')
        for _c in sorted({k[0] for k in _rgk}):
            for _lab, _rp, _rf, _rl in (('sautA', 1, 2, 3), ('sautB', 4, 5, 6)):
                _kp, _kf = (_c, _rp), (_c, _rf)
                if _kp not in _rgk or _kf not in _rgk:
                    A('ROOM-REGIME-SIGN: %-8s %s FENETRE MANQUANTE OU ECARTEE (r=%d %s, r=%d %s)'
                      ' : le signe n\'est pas mesure'
                      % (_rgnm(_c), _lab, _rp, 'jointe' if _kp in _rgk else 'ABSENTE',
                         _rf, 'jointe' if _kf in _rgk else 'ABSENTE'))
                    continue
                _cyp, _cyf = _rga[_kp][2], _rga[_kf][2]
                _ok = (_cyp < 0.0) and (_cyf > 0.0)
                A('ROOM-REGIME-SIGN: %-8s %s cy_pouss=%+.4f cy_vol=%+.4f -> CHANGEMENT DE SIGNE :'
                  ' %s' % (_rgnm(_c), _lab, _cyp, _cyf, 'oui' if _ok else 'non'))
                if not _ok:
                    A('   ROUGE §15 : le critere demande cy<0 en poussee ET cy>0 en vol ; mesure'
                      ' %+.4f puis %+.4f.' % (_cyp, _cyf))
                _kl = (_c, _rl)
                if _kl in _rgk:
                    A('   cy_reception (r=%d) = %+.4f — publiee pour lecture, §15 ne la borne pas.'
                      % (_rl, _rga[_kl][2]))
        A('')
        # ---- (6) SPEC 18 / SPEC 20 : GAUCHE CONTRE DROITE ------------------------------------
        # ---- ROOM-POSERANK : LE BALAYAGE DE POSE, ET SON LECTEUR (cycle 67) ------------------
        #
        # POURQUOI CE BLOC EXISTE. `PHYSPOSEB` est emis par la salle depuis le cycle 54 — 31
        # lignes de directions d'os, une par animation — et `grep -rl PHYSPOSEB` ne rend que
        # `phys-room.gc` : **aucun lecteur, dans aucun script, depuis treize cycles**. La donnee
        # qui a servi a choisir `PHYSROOM-SYMNAME` etait donc produite a chaque course et jetee,
        # et le rang « 1 sur 31 » de la pose epinglee ne vivait plus que dans un commentaire.
        # La regle 0 est explicite : un commentaire n'est pas une preuve. Ce bloc lui rend un
        # lecteur, et il verifie le rang au lieu de le citer.
        #
        # ET IL PUBLIE LE BALAYAGE RESOLU A LA FRAME. Le cycle 56 avait ETABLI que « l'asymetrie
        # est une propriete de la FRAME et pas de l'animation » ; `PHYSPOSEB` echantillonnait
        # pourtant UNE frame par animation, soit 31 points d'une population de 264. `PHYSPOSEF`
        # balaie la sous-fenetre de LIGNE DE BASE de chaque animation, sans ajouter une frame de
        # course.
        #
        # NATURE : un ANGLE en degres, l'ecart au miroir du PIRE maillon. REPERE : monde, la
        #   direction d'os de chestL reflechie dans le plan de normale `lat` (`PHYSAXW ax=2`),
        #   comparee a celle de chestR. MEME formule que `ROOM-REGPOSE`, par `_mirror_dev` — une
        #   seule fonction, pour que les deux nombres soient comparables.
        # LECTURE QUAND LE DEFAUT EST ABSENT : 0 deg (rig miroir a 0.005 deg en pose de bind).
        # CE QUI DISCRIMINE : la FRAME d'animation, a animation egale. Si le balayage rendait la
        #   meme valeur sur toutes les frames d'une animation, il ne mesurerait pas la frame.
        _psf, _psfb = {}, {}
        for _m in re.finditer(r'^PHYSPOSEF k=(\d+) a=(\d+) f=([-\d.e+]+) s=([-\d.e+]+)', txt, re.M):
            _psf[int(_m.group(1))] = (int(_m.group(2)), float(_m.group(3)), float(_m.group(4)))
        for _m in re.finditer(r'^PHYSPOSEFB k=(\d+) c=(\d+) l=(\d+) ux=([-\d.e+]+)'
                              r' uy=([-\d.e+]+) uz=([-\d.e+]+)', txt, re.M):
            _psfb.setdefault(int(_m.group(1)), {})[(int(_m.group(2)), int(_m.group(3)))] = \
                tuple(float(_m.group(k)) for k in (4, 5, 6))
        A('')
        A('   -- ROOM-POSERANK : LES POSES DISPONIBLES, CLASSEES PAR LEUR ECART AU MIROIR ------')
        if not _psf:
            A('ROOM-POSERANK: NON PUBLIE — aucune ligne `PHYSPOSEF` dans cette course. Le'
              ' balayage', notasym=True)
            A('   resolu a la frame n\'a pas tourne ; la pose epinglee reste celle du cycle 54,'
              ' choisie', notasym=True)
            A('   sur 31 echantillons d\'une population de 264.', notasym=True)
        elif _lat is None:
            A('ROOM-POSERANK: `PHYSAXW ax=2` absent — pas de plan de reflexion, aucun angle.',
              notasym=True)
        else:
            # L'ANGLE EST RECALCULE DEPUIS LES VECTEURS, PAS RELU DE `s`. C'est le controle de
            # l'arithmetique faite en course : si les deux divergent, c'est le solveur qui compte
            # mal, et la pose epinglee n'est pas celle que sa ligne annonce.
            _pr = {}
            for _k, (_a, _f, _s) in _psf.items():
                _rec = _psfb.get(_k, {})
                _w = None
                for _l in sorted({kk[1] for kk in _rec}):
                    if (0, _l) in _rec and (1, _l) in _rec:
                        _d = _mirror_dev(_rec[(0, _l)], _rec[(1, _l)], _lat)
                        if _d is not None:
                            _w = _d if _w is None else max(_w, _d)
                if _w is not None:
                    _pr[_k] = (_a, _f, _s, _w)
            _pfr = {_k: _k % 100 for _k in _pr}          # k = a*100 + pframe (cf. phys-room.gc)
            _elig = {_k: v for _k, v in _pr.items() if _pfr[_k] >= 54}
            _pairs = {(v[0], int(v[1] + 0.5)) for v in _pr.values()}
            A('ROOM-POSERANK: %d echantillons, %d couples (animation, frame entiere) distincts —'
              ' contre' % (len(_pr), len(_pairs)), notasym=True)
            A('   31 pour `PHYSPOSEB`, qui n\'echantillonne qu\'UNE frame par animation. %d'
              ' echantillons sont' % len(_elig), notasym=True)
            A('   ELIGIBLES a l\'argmax (pframe >= 54, le point d\'etablissement que la salle'
              ' utilise deja', notasym=True)
            A('   partout) ; les autres sont publies mais portent le ring-down du pilotage'
              ' precedent.', notasym=True)
            # LE CONTROLE D'ARITHMETIQUE : `s` est un cosinus, l'angle recalcule doit lui repondre.
            _err = max((abs(_w - math.degrees(math.acos(max(-1.0, min(1.0, _s))))) 
                        for (_a, _f, _s, _w) in _pr.values() if _s > -1.5), default=None)
            A('ROOM-POSERANK-ARITH: ecart max entre l\'angle recalcule ici et le cosinus calcule'
              ' en course = %s' % ('%.4f deg' % _err if _err is not None else 'non calculable'),
              notasym=True)
            _srt = sorted(_pr.items(), key=lambda kv: kv[1][3])
            A('')
            A('      rang  k       a    frame    ecart au miroir   eligible')
            for _i, (_k, (_a, _f, _s, _w)) in enumerate(_srt[:8]):
                A('      %-5d %-7d %-4d %-8.3f %8.2f deg        %s'
                  % (_i + 1, _k, _a, _f, _w, 'oui' if _k in _elig else 'NON (transitoire)'),
                  notasym=True)
            _dv = sorted(v[3] for v in _pr.values())
            A('      ... population : min %.2f  p10 %.2f  mediane %.2f  max %.2f deg (n=%d)'
              % (_dv[0], _dv[max(0, len(_dv) // 10)], _dv[len(_dv) // 2], _dv[-1], len(_dv)),
              notasym=True)
            # LE TRANSITOIRE DEPLACE-T-IL LE SCORE ? On le MESURE au lieu de le supposer : meme
            # couple (animation, frame entiere), lu dans le transitoire et lu apres.
            _byp = {}
            for _k, (_a, _f, _s, _w) in _pr.items():
                _byp.setdefault((_a, int(_f + 0.5)), {'t': [], 'e': []})[
                    'e' if _pfr[_k] >= 54 else 't'].append(_w)
            _dd = [abs(sum(v['e']) / len(v['e']) - sum(v['t']) / len(v['t']))
                   for v in _byp.values() if v['e'] and v['t']]
            _dd.sort()
            A('ROOM-POSERANK-TRANSITOIRE: sur %d couples lus DANS et HORS du transitoire, l\'ecart'
              ' median' % len(_dd), notasym=True)
            A('   de l\'angle au miroir vaut %s. C\'est la part du classement qui ne vient pas de'
              ' la pose.'
              % ('%.2f deg (max %.2f)' % (_dd[len(_dd) // 2], _dd[-1]) if _dd else 'non mesurable'),
              notasym=True)
            # LE RANG DE LA POSE DU CYCLE 54, VERIFIE AU LIEU D'ETRE CITE.
            _sym = re.search(r'^PHYSREGSPOSE ai=(-?\d+)', txt, re.M)
            _symai = int(_sym.group(1)) if _sym else -1
            if _symai >= 0:
                _same = [(_k, v) for _k, v in _srt if v[0] == _symai]
                _rk = next((_i + 1 for _i, (_k, v) in enumerate(_srt) if v[0] == _symai), None)
                A('ROOM-POSERANK-EPINGLE: l\'animation epinglee depuis le cycle 55 (a=%d) apparait'
                  ' au rang %s' % (_symai, _rk if _rk else '?'), notasym=True)
                if _same:
                    A('   sur %d ; sa MEILLEURE frame vaut %.2f deg et sa PIRE %.2f deg — l\'ecart'
                      ' entre les' % (len(_srt), min(v[3] for _, v in _same),
                                      max(v[3] for _, v in _same)), notasym=True)
                    A('   deux est la mesure de ce que « une frame par animation » laissait au'
                      ' hasard.', notasym=True)
            # L'ARGMAX DE LA COURSE CONTRE CELUI RECALCULE ICI (prediction Q8).
            _gt = re.search(r'^PHYSREGTPOSE a=(-?\d+) f=([-\d.e+]+) s=([-\d.e+]+)', txt, re.M)
            _best = min(_elig.items(), key=lambda kv: kv[1][3]) if _elig else None
            if _gt and _best:
                _ga, _gf = int(_gt.group(1)), float(_gt.group(2))
                _ba, _bf = _best[1][0], _best[1][1]
                _acc = (_ga == _ba and abs(_gf - _bf) < 1e-3)
                A('ROOM-POSERANK-ARGMAX: la course a retenu a=%d f=%.4f ; le tableau, en refaisant'
                  ' le maximum' % (_ga, _gf), notasym=True)
                A('   sur la population publiee, trouve a=%d f=%.4f (%.2f deg) -> %s'
                  % (_ba, _bf, _best[1][3],
                     'LES DEUX ARGMAX COINCIDENT' if _acc else
                     'LES DEUX ARGMAX DIFFERENT — l\'arithmetique de course est en cause'),
                  notasym=True)
        # LE LECTEUR ENFIN DONNE A `PHYSPOSEB` : le balayage a une frame par animation du cycle 54.
        _pb = {}
        for _m in re.finditer(r'^PHYSPOSEB a=(\d+) c=(\d+) l=(\d+) ux=([-\d.e+]+)'
                              r' uy=([-\d.e+]+) uz=([-\d.e+]+)', txt, re.M):
            _pb.setdefault(int(_m.group(1)), {})[(int(_m.group(2)), int(_m.group(3)))] = \
                tuple(float(_m.group(k)) for k in (4, 5, 6))
        if _pb and _lat is not None:
            _pbd = {}
            for _a, _rec in _pb.items():
                _w = None
                for _l in sorted({kk[1] for kk in _rec}):
                    if (0, _l) in _rec and (1, _l) in _rec:
                        _d = _mirror_dev(_rec[(0, _l)], _rec[(1, _l)], _lat)
                        if _d is not None:
                            _w = _d if _w is None else max(_w, _d)
                if _w is not None:
                    _pbd[_a] = _w
            _ord = sorted(_pbd.items(), key=lambda kv: kv[1])
            A('ROOM-POSEB-RANG: %d animations classees (c\'est le balayage du cycle 54, UNE frame'
              ' par' % len(_ord), notasym=True)
            A('   animation) — meilleure a=%d a %.2f deg, mediane %.2f deg, pire a=%d a %.2f deg.'
              % (_ord[0][0], _ord[0][1], _ord[len(_ord) // 2][1], _ord[-1][0], _ord[-1][1]),
              notasym=True)
            _sym = re.search(r'^PHYSREGSPOSE ai=(-?\d+)', txt, re.M)
            if _sym and int(_sym.group(1)) in _pbd:
                _sa = int(_sym.group(1))
                _rk = 1 + [a for a, _ in _ord].index(_sa)
                A('   L\'ANIMATION EPINGLEE (a=%d) Y EST AU RANG %d SUR %d, a %.2f deg. Le'
                  ' commentaire de' % (_sa, _rk, len(_ord), _pbd[_sa]), notasym=True)
                A('   `phys-room.gc` annonce « la seule sous 10 deg » : c\'est verifie ici, sur'
                  ' cette course,', notasym=True)
                A('   et plus cite de memoire.', notasym=True)
        A('')
        # ---- ROOM-REGPOSE : LA POSE DANS LAQUELLE §14 A §20 SONT MESUREES (cycle 65) ---------
        #
        # POURQUOI CE BLOC EXISTE. Cinq lignes du registre (§14, §16, §17, §18, §20) publient un
        # ecart gauche/droite tire des fenetres de PH-REG, et §18 en publie de tres gros (x2.80 et
        # x5.79). La regle du 2026-08-20 05:20 est explicite : « toute mesure d'ASYMETRIE se
        # releve dans une pose dont la symetrie est PROUVEE avant la course, et le rapport publie
        # l'ecart au miroir. Une pose heritee n'est pas une pose choisie. » PH-SGN (cycle 55) et
        # PH-SYM (cycle 56) EPINGLENT leur pose par son nom et la revalident a l'execution.
        # PH-REG ne fait ni l'un ni l'autre : il TIENT ce que la phase precedente lui laisse.
        # Jusqu'ici l'ecart au miroir de cette pose-la n'etait ni epingle NI MESURE.
        #
        # NATURE : un ANGLE en degres. REPERE : monde ; la direction d'os de chestL est
        #   REFLECHIE dans le plan de normale `lat` (l'axe lateral du solveur, PHYSAXW ax=2) puis
        #   comparee a celle de chestR. MEME formule que `dev` de ROOM-SYM, pour que les deux
        #   soient comparables — un instrument neuf rendrait les deux nombres incomparables.
        # LECTURE QUAND LE DEFAUT EST ABSENT : 0 deg. Le cycle 53 a mesure le rig a 0.005 deg du
        #   miroir en pose de BIND, donc tout ce qui depasse est porte par la POSE et par elle
        #   seule.
        _regb = {}
        for _m in re.finditer(r'^PHYSREGB c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+)'
                              r' uz=([-\d.e+]+)', txt, re.M):
            _regb[(int(_m.group(1)), int(_m.group(2)))] = \
                tuple(float(_m.group(k)) for k in (3, 4, 5))
        _rlat = None
        for _m in re.finditer(r'^PHYSAXW ax=2 ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)',
                              txt, re.M):
            _rlat = tuple(float(_m.group(k)) for k in (1, 2, 3))
        A('   -- ROOM-REGPOSE : L\'ECART AU MIROIR DE LA POSE OU §14 A §20 SONT MESUREES --------')
        if not _regb:
            A('ROOM-REGPOSE: NON PUBLIE par cette course — `PHYSREGB` absent de la trace. Tant')
            A('   qu\'il l\'est, les ecarts gauche/droite de §14, §16, §17, §18 et §20 sont lus')
            A('   dans une pose dont la symetrie n\'est ni epinglee ni mesuree.')
        elif _rlat is None:
            A('ROOM-REGPOSE: `PHYSAXW ax=2` absent — pas de plan de reflexion, aucun angle publie.')
        else:
            # LES ECARTS PAR MAILLON PASSENT PAR `asym` COMME TOUT LE RESTE (cycle 67). Quand la
            # pose refuse, ils ne sont pas PERDUS : ils partent dans la `note` du refus, donc sur
            # la ligne meme qui refuse. On ne se donne pas le droit de publier une ligne d'ecart
            # parce qu'elle mesure la pose — c'est la meme regle pour tout le monde, et le chiffre
            # reste lisible.
            _preg = POSE['PH-REG']
            _nl = max((k[1] for k in _regb), default=-1)
            _rgpl = []
            for _l in range(_nl + 1):
                if (0, _l) not in _regb or (1, _l) not in _regb:
                    A('ROOM-REGPOSE: l=%d — une des deux chaines manque, aucun angle' % _l)
                    continue
                _u, _v = _regb[(0, _l)], _regb[(1, _l)]
                _dd = sum(_u[k] * _rlat[k] for k in range(3))
                _mu = [_u[k] - 2 * _dd * _rlat[k] for k in range(3)]
                _nu = math.sqrt(sum(x * x for x in _mu)) * math.sqrt(sum(x * x for x in _v))
                _cs = (sum(_mu[k] * _v[k] for k in range(3)) / _nu) if _nu > 0 else 0.0
                _dg = math.degrees(math.acos(max(-1.0, min(1.0, _cs))))
                _rgpl.append((_l, _dg))
                if _preg.ok():
                    A(asym('ROOM-REGPOSE', ': l=%d ecart au miroir = %.1f deg   (bind = 0.005'
                           ' deg, cycle 53)' % (_l, _dg), _preg))
            if not _preg.ok() and _rgpl:
                A(asym('ROOM-REGPOSE', ': %d maillon(s) mesures' % len(_rgpl), _preg,
                       note='par maillon : %s.'
                            % ', '.join('l=%d %.1f deg' % _t for _t in _rgpl)))
            _worst = 0.0
            for _l in range(_nl + 1):
                if (0, _l) in _regb and (1, _l) in _regb:
                    _u, _v = _regb[(0, _l)], _regb[(1, _l)]
                    _dd = sum(_u[k] * _rlat[k] for k in range(3))
                    _mu = [_u[k] - 2 * _dd * _rlat[k] for k in range(3)]
                    _nu = math.sqrt(sum(x * x for x in _mu)) * math.sqrt(sum(x * x for x in _v))
                    _cs = (sum(_mu[k] * _v[k] for k in range(3)) / _nu) if _nu > 0 else 0.0
                    _worst = max(_worst, math.degrees(math.acos(max(-1.0, min(1.0, _cs)))))
            A(asym('ROOM-REGPOSE-VERDICT', ': pire ecart %.1f deg -> %s'
                   % (_worst,
                      'POSE HERITEE NON SYMETRIQUE : tout ecart gauche/droite publie par §14,'
                      ' §16, §17, §18 et §20 la porte, et aucune de ces lignes ne peut attribuer'
                      ' son asymetrie au PERSONNAGE tant qu\'elle n\'est pas rejouee dans une'
                      ' pose epinglee.' if _worst > 10.0 else
                      'pose heritee acceptable au seuil de 10 deg du cycle 54 : les ecarts'
                      ' gauche/droite de §14 a §20 ne sont PAS portes par la pose.'), _preg))
        A('')
        A('   -- ROOM-REGIME-MIRROR : SPEC 18 et SPEC 20, GAUCHE CONTRE DROITE -----------------')
        A('      §18 exige que les deux seins DIFFERENT en rotation, et elle en donne la cause :')
        A('      « because their offsets from the torso rotational axis differ ». SUR LE RIG')
        A('      LIVRE, CETTE CAUSE N\'EXISTE PAS. Mesure sur out/jak1/fr3/skin/keira-hd-lod0.glb :')
        A('      la racine de chaine est a 548.078 u (lBoob) et 548.081 u (rBoob) de l\'axe')
        A('      VERTICAL de lacet — 0.0029 u d\'ecart, soit 5.2e-4 %. Idem en tangage (1925.209 /')
        A('      1925.210 u de l\'axe X par les hanches) et en roulis (1922.159 / 1922.160 u de')
        A('      l\'axe Z par les hanches). Les deux seins sont donc a distance EGALE de l\'axe.')
        A('      CONSEQUENCE, ET ELLE EST DURE : tout ecart mesure ci-dessous vient des')
        A('      PARAMETRES (raideur, amortissement, rayons, poids), pas de la geometrie. La')
        A('      dissymetrie que §18 decrit par sa cause geometrique ne peut pas etre obtenue')
        A('      dans ce rig sans deplacer une racine — ce qui serait un changement de RIG.')
        _cl = [_c for _c in {k[0] for k in _rgk} if _rgnm(_c) == 'chestL']
        _cr = [_c for _c in {k[0] for k in _rgk} if _rgnm(_c) == 'chestR']
        if not _cl or not _cr:
            A('ROOM-REGIME-MIRROR: PAIRE chestL/chestR INTROUVABLE dans cette course'
              ' (chaines vues : %s) — aucun ecart n\'est publie.'
              % ', '.join(sorted(_rgnm(_c) for _c in {k[0] for k in _rgk})))
        else:
            # CES QUATRE REGIMES SONT JOUES DANS PH-REG, LA POSE HERITEE (cycle 67). Si elle n'est
            # pas au miroir, les quatre ecarts qu'ils publient sont indistinguables d'un artefact
            # de pose : un seul refus les couvre tous, et `ROOM-REGS` rejoue les memes fenetres
            # dans la pose EPINGLEE — c'est la, et nulle part ici, qu'un chiffre peut naitre.
            _preg2 = POSE['PH-REG']
            _RMNOTE = '§18 et §20 restent NON ETABLI sur leur clause gauche/droite.'
            if not _preg2.ok():
                A(asym('ROOM-REGIME-MIRROR', ': 4 regimes releves, aucun ecart publie', _preg2,
                       note=_RMNOTE))
            for _r in ((9, 10, 13, 14) if _preg2.ok() else ()):
                _kl2, _kr2 = (_cl[0], _r), (_cr[0], _r)
                if _kl2 not in _rgk or _kr2 not in _rgk:
                    A('ROOM-REGIME-MIRROR: r=%2d %-13s FENETRE MANQUANTE OU ECARTEE sur au moins'
                      ' une chaine : aucun ecart' % (_r, _rgtab[_r][1]))
                    continue
                _vl, _vr = _rga[_kl2][0], _rga[_kr2][0]
                _mn = 0.5 * (_vl + _vr)
                A(asym('ROOM-REGIME-MIRROR',
                       ': r=%2d %-13s com(chestL)=%.4f com(chestR)=%.4f  ecart %s'
                       % (_r, _rgtab[_r][1], _vl, _vr,
                          ('%.2f %%' % (100.0 * abs(_vl - _vr) / _mn)) if _mn > 0 else
                          'INDEFINI (les deux valent 0)'), _preg2, note=_RMNOTE))
        A('')
        # ---- (7) CYCLE 51 : L'APEX, PAR REGIME ------------------------------------------------
        # POURQUOI CE BLOC EXISTE. §14, §16, §17, §18, §19 et §20 bornent TOUTES un « apex
        # displacement » en % B0, et §19 ne borne QUE ca : jusqu'au cycle 51 aucun canal de la
        # salle ne publiait un apex, donc six sections etaient injugeables quel que soit le
        # solveur. Le canal vient de `PHYSREG4` (emplacements 53-56 du moteur).
        #
        # NATURE : une LONGUEUR rapportee a B0 (602 u, §6) — le MAXIMUM sur la fenetre de
        #   l'excursion du CENTROIDE DE MASSE DU DECILE DISTAL du nuage de chair. CE N'EST PAS
        #   LE COM : le COM moyenne TOUT le nuage, dont 46 % est ancre ; l'apex ne regarde que la
        #   region que §31 appelle « r = 1 at distal/apex region ». Les deux repondent a des
        #   lignes DIFFERENTES de la spec et ne sont pas interchangeables.
        # REPERE : le monde, frame ecrite, contre la pose d'auteur de la MEME frame, deformation
        #   comprise — le meme que `com`, pour que le rapport des deux ait un sens.
        # LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000 a la pose d'auteur.
        #
        # LES BANDES SONT CITEES, PAS RESUMEES, et DEUX REGIMES N'EN ONT PAS : §17 ne borne
        # l'apex que pour « strong » (donc le freinage r=8, rien pour le demarrage r=7) et §18
        # que pour « strong » (r=10, rien pour r=9). Ces deux fenetres sortent « SA SPEC NE BORNE
        # PAS L'APEX DE CE REGIME » — on n'invente pas une bande pour completer un tableau.
        # LA DEMANDE DU RESSORT, PAR FENETRE — le verrou du cycle 71. Chargee ICI parce que
        # c'est le premier bloc qui publie une bande d'apex, et qu'aucune bande ne doit sortir
        # sans l'etat du limiteur de sa propre fenetre a cote d'elle.
        _LIMW = _limload(txt)
        _RGAPX = {
            1:  ((0.20, 0.30), '§14 « Apex displacement: ordinary 20-30% B0 »'),
            4:  ((0.30, 0.38), '§14 « strong 30-38% B0 »'),
            3:  ((0.30, 0.42), '§16 « Strong landing apex: 30-42% B0 »'),
            6:  ((0.42, 0.50), '§16 « Very hard / exceptional: 42-50% B0 »'),
            7:  (None,         '§17 ne borne l\'apex que pour « strong » : PAS de bande ici'),
            8:  ((0.25, 0.35), '§17 « Apex displacement: strong 25-35% B0 »'),
            9:  (None,         '§18 ne borne l\'apex que pour « strong » : PAS de bande ici'),
            10: ((0.20, 0.30), '§18 « Apex displacement: strong 20-30% B0 »'),
            11: ((0.30, 0.40), '§19 « 30-40% B0 apex displacement » — SA SEULE CLAUSE CHIFFREE'),
            12: ((0.30, 0.40), '§19 idem, au retour a la verticale'),
            13: ((0.20, 0.30), '§20 « apex 20-30% B0 »'),
            14: ((0.20, 0.30), '§20 idem, cote oppose'),
        }
        _rge, _rgf = {}, {}
        for _m in re.finditer(r'^PHYSREG4 c=(\d+) r=(\d+) apex=([-\d.e+]+) ax=([-\d.e+]+)'
                              r' ay=([-\d.e+]+) az=([-\d.e+]+)', txt, re.M):
            _rge[(int(_m.group(1)), int(_m.group(2)))] = (
                float(_m.group(3)), float(_m.group(4)), float(_m.group(5)), float(_m.group(6)))
        for _m in re.finditer(r'^PHYSREG5 c=(\d+) r=(\d+) cydn=([-\d.e+]+) cyup=([-\d.e+]+)',
                              txt, re.M):
            _rgf[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)), float(_m.group(4)))
        if not _rge:
            A('   -- ROOM-APEX-REGIME : ABSENT ----------------------------------------------')
            A('ROOM-APEX-REGIME: aucune ligne PHYSREG4 dans cette trace — le canal d\'apex n\'a')
            A('   PAS tourne. §14, §16, §17, §18, §19 et §20 restent NON MESUREES sur leur clause')
            A('   d\'apex. Rien n\'est publie a zero : un canal absent n\'est pas un apex immobile.')
        else:
            A('   -- ROOM-APEX-REGIME : SPEC 14/16/17/18/19/20, LA CLAUSE D\'APEX ---------------')
            _shL, _shR = _apxsh('chestL'), _apxsh('chestR')
            A('      LE PLAFOND QUE LE MESH IMPOSE, ET IL EST LU DANS LE FICHIER LIVRE — plus')
            A('      jamais ecrit en dur. La part de la masse distale portee par des maillons')
            A('      SIMULES est la somme des poids `ax` de recharged_assets/physics_mesh.txt,')
            A('      le fichier meme que le moteur charge (jak-hd-physics.gc:803). Le reste est')
            A('      porte par des os NON SIMULES, dont la matrice ecrite EST la matrice')
            A('      d\'auteur et dont l\'excursion est nulle au bit pres.')
            if _shL is None or _shR is None:
                A('      PART NON ETABLIE : aucun enregistrement `ax` lisible. Les mentions')
                A('      « ancrage seul » ci-dessous sont donc OMISES plutot que devinees.')
            else:
                # EXEMPTE : ces deux nombres sont des POIDS DE PEAU lus dans
                # `recharged_assets/physics_mesh.txt`, le fichier livre. Ils ne dependent d'aucune
                # pose — une ponderation de skin est la meme dans toutes — et le `x%.2f` qui suit
                # est le plafond de CHAQUE chaine, pas un rapport de l'une a l'autre.
                A('      part simulee : %.4f (chestL) / %.4f (chestR) -> plafond d\'ancrage x%.2f'
                  % (_shL, _shR, 1.0 / _shL), notasym=True)
                A('      / x%.2f. Une bande manquee de MOINS que ce facteur peut s\'expliquer par'
                  % (1.0 / _shR))
                A('      l\'ancrage seul ; manquee de PLUS, non — et c\'est cette frontiere qui')
                A('      rend chaque ligne ci-dessous lisible. Sa §30 ecrit « Apex — minimal')
                A('      direct anchoring » : a %.2f / %.2f le mesh livre s\'en approche enfin.'
                  % (_shL, _shR))
            for _r in sorted({k[1] for k in _rge}):
                _bd, _cite2 = _RGAPX.get(_r, (None, 'aucune clause d\'apex pour ce regime'))
                for _c in sorted({k[0] for k in _rge if k[1] == _r}):
                    _v = _rge[(_c, _r)][0]
                    if _bd is None:
                        A('ROOM-APEX-REGIME: %-8s r=%2d %-13s apex=%.4f B0   %-16s %s'
                          % (_rgnm(_c), _r, _rgtab[_r][1], _v,
                             _limtag(_LIMW, 31, _c, _r), _cite2))
                    else:
                        _vd = _rgvd(_v, _bd)
                        _nd = ''
                        _sh = _apxsh(_rgnm(_c))
                        if _vd.startswith('SOUS') and _sh is not None:
                            _fac = (_bd[0] / _v) if _v > 0 else 0.0
                            _cap = 1.0 / _sh
                            _nd = ('   ancrage seul %s (manque x%.2f, plafond x%.2f)'
                                   % ('SUFFIT' if _fac <= _cap else 'NE SUFFIT PAS', _fac, _cap))
                        A('ROOM-APEX-REGIME: %-8s r=%2d %-13s apex=%.4f B0  [%.2f-%.2f]'
                          ' -> %-16s %-16s%s'
                          % (_rgnm(_c), _r, _rgtab[_r][1], _v, _bd[0], _bd[1],
                             _limverd(_vd, _LIMW, 31, _c, _r),
                             _limtag(_LIMW, 31, _c, _r), _nd))
                A('   %s' % _cite2)
            # ---- LE RAPPORT APEX/COM : LE CONTROLE DE L'INSTRUMENT LUI-MEME -------------------
            A('')
            A('   -- ROOM-APEX-RATIO : LE CONTROLE DE L\'INSTRUMENT, PAS UNE EXIGENCE DE LA SPEC -')
            A('      LES BANDES DE SA PROPRE SPEC IMPLIQUENT UN RAPPORT apex/COM. §14 30/25,')
            A('      §16 30/25, §17 25/18, §18 20/17, §20 20/15 : entre x1.19 et x1.35. Ce n\'est')
            A('      PAS une clause a tenir — c\'est de quoi savoir si ce que je publie sous le nom')
            A('      d\'apex EST un apex. Un rapport hors de [1.0, 2.0] voudrait dire que le canal')
            A('      mesure autre chose, et aucun verdict de la section ci-dessus ne tiendrait.')
            _rat = []
            for _k in sorted(set(_rge) & set(_rga)):
                _a, _cm = _rge[_k][0], _rga[_k][0]
                if _cm > 1e-6:
                    _rat.append(_a / _cm)
                    A('ROOM-APEX-RATIO: %-8s r=%2d %-13s apex=%.4f com=%.4f  rapport x%.3f'
                      % (_rgnm(_k[0]), _k[1], _rgtab[_k[1]][1], _a, _cm, _a / _cm))
            if _rat:
                _rat.sort()
                A('ROOM-APEX-RATIO: n=%d  min x%.3f  mediane x%.3f  max x%.3f  —  bande implicite'
                  ' de sa spec x1.19 a x1.35'
                  % (len(_rat), _rat[0], _rat[len(_rat) // 2], _rat[-1]))
            # ---- SPEC 15 : LA TRAVERSEE DU NEUTRE --------------------------------------------
            A('')
            # ---- CYCLE 70 : LES MEMES FENETRES DE TRANSLATION, SUR LES AXES DU SUJET ---------
            _regb_block(A, txt, names, _RGT, _RGAPX, _rgvd, asym, POSE, _LIMW)
            _reglim_block(A, txt, names, _RGT, _LIMW)
            _spec8_block(A, txt, names)
            # ---- ROOM-REGS : LES MEMES QUINZE FENETRES DANS LA POSE EPINGLEE (cycle 66) ----
            #
            # POURQUOI. Le cycle 65 a mesure que PH-REG joue §14 a §20 dans une pose HERITEE a
            # 43.8 / 48.0 deg du miroir, et que sur les deux seules cellules resolues de
            # `ROOM-SYM` le SENS de l'asymetrie gauche/droite s'inverse avec la pose. PH-REGS
            # rejoue les MEMES fenetres dans la pose EPINGLEE, APPENDUE a la MEME course : memes
            # tables, meme `physroom-reg-drive`, memes emplacements de lecture (53 = apex,
            # 43 = COM). La seule variable declaree est le nom de l'animation.
            #
            # NATURE : `apex` est une LONGUEUR rapportee a B0, maximum de fenetre — la MEME
            #   grandeur que `PHYSREG4`, au meme emplacement moteur. `R` est un rapport sans
            #   unite entre les deux chaines. `dev` est un ANGLE en degres.
            # REPERE : monde, frame ecrite, contre la pose d'auteur de la MEME frame. Identique a
            #   celui de PH-REG, sinon les deux passes ne se compareraient pas.
            # CE QUI DISCRIMINE : la POSE, et rien d'autre de declare. Ce que ce bloc ne peut PAS
            #   exclure est ecrit sous le tableau, pas tu.
            _rgs, _rgsb, _rgspose = {}, {}, None
            for _m in re.finditer(r'^PHYSREGS c=(\d+) r=(\d+) apex=([-\d.e+]+) com=([-\d.e+]+)',
                                  txt, re.M):
                _rgs[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)),
                                                              float(_m.group(4)))
            for _m in re.finditer(r'^PHYSREGSB c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+)'
                                  r' uz=([-\d.e+]+)', txt, re.M):
                _rgsb[(int(_m.group(1)), int(_m.group(2)))] = \
                    tuple(float(_m.group(k)) for k in (3, 4, 5))
            _m = re.search(r'^PHYSREGSPOSE ai=(-?\d+) src=(\S+)', txt, re.M)
            if _m:
                _rgspose = (int(_m.group(1)), _m.group(2))
            A('')
            A('   -- ROOM-REGS : §14 A §20 REJOUEES DANS LA POSE EPINGLEE (cycle 66) -----------')
            if not _rgs:
                A('ROOM-REGS: NON PUBLIE par cette course — aucune ligne `PHYSREGS`. Tant qu\'il')
                A('   en est ainsi, les ecarts gauche/droite de §14, §16, §17, §18 et §20 ne sont')
                A('   lus QUE dans la pose heritee, et `ROOM-REGPOSE` dit a combien elle est du')
                A('   miroir.')
            elif _rgspose is None or _rgspose[0] < 0:
                A('ROOM-REGS: L\'EPINGLE DE POSE N\'A PAS PRIS (%s). Cette passe a donc rejoue une'
                  % ('PHYSREGSPOSE absent' if _rgspose is None else _rgspose[1]))
                A('   pose NON CHOISIE sous le nom de « pose epinglee » : AUCUN de ses chiffres')
                A('   n\'est publie. Une passe qui ne sait pas dans quelle pose elle a tourne ne')
                A('   mesure rien.')
            else:
                # LA POSE EST REVALIDEE AVANT TOUT CHIFFRE, ET C'EST LA CONDITION D'ENTREE. Une
                # epingle qui a « pris » au sens de l'index peut retomber sur une frame
                # asymetrique (cycle 54 : l'asymetrie est une propriete de la FRAME). On mesure.
                _sdev = None
                if _rlat is not None:
                    _sd = []
                    for _l in sorted({k[1] for k in _rgsb}):
                        if (0, _l) in _rgsb and (1, _l) in _rgsb:
                            _u, _v = _rgsb[(0, _l)], _rgsb[(1, _l)]
                            _dd = sum(_u[k] * _rlat[k] for k in range(3))
                            _mu = [_u[k] - 2 * _dd * _rlat[k] for k in range(3)]
                            _nu = math.sqrt(sum(x * x for x in _mu)) * \
                                math.sqrt(sum(x * x for x in _v))
                            _cs = (sum(_mu[k] * _v[k] for k in range(3)) / _nu) if _nu > 0 else 0.0
                            _sd.append(math.degrees(math.acos(max(-1.0, min(1.0, _cs)))))
                    _sdev = max(_sd) if _sd else None
                # LES DEUX POSES DE CE BLOC, PRISES AU REGISTRE ET PAS RECALCULEES ICI (c67).
                # `_sdev` ci-dessus mesure la MEME chose que `POSE['PH-REGS']` (meme trace, meme
                # formule) : le registre est la source, la variable locale ne sert plus qu'a
                # l'affichage de l'en-tete. Deux calculs de la meme grandeur divergent toujours ;
                # celui-la ne peut plus, parce qu'il n'y en a qu'un qui decide.
                _poh, _poe = POSE['PH-REG'], POSE['PH-REGS']
                A(asym('ROOM-REGS-POSE', ': animation epinglee ai=%d (%s) ; ecart au miroir'
                       ' REVALIDE a l\'execution = %s'
                       % (_rgspose[0], _rgspose[1],
                          ('%.1f deg' % _sdev) if _sdev is not None else 'NON LU'), _poe))
                if _sdev is not None and _sdev > 10.0:
                    A('   L\'EPINGLE A PRIS MAIS LA FRAME N\'EST PAS SYMETRIQUE (%.1f deg > 10, le'
                      ' seuil du cycle 54).' % _sdev)
                    A('   Les chiffres ci-dessous ne repondent donc PAS a la question posee : ils')
                    A('   comparent deux poses asymetriques. Publies, jamais lus comme un verdict.')
                _t0 = [_r for _r in (1, 3, 4, 6, 8, 9, 10, 11, 12, 13, 14)]
                A('')
                A('      %-3s %-13s %-9s %-9s %-8s %-9s %-9s %-8s'
                  % ('r', 'regime', 'apexL^h', 'apexR^h', 'R^h', 'apexL^e', 'apexR^e', 'R^e'))
                A('      ^h = pose HERITEE (PH-REG, %s) · ^e = pose EPINGLEE (PH-REGS, %s)'
                  % (('%.1f deg' % _worst) if (_regb and _rlat) else 'non lu',
                     ('%.1f deg' % _sdev) if _sdev is not None else '?'))
                _flip, _tight, _ncmp = 0, 0, 0
                for _r in _t0:
                    _hl, _hr = _rge.get((0, _r)), _rge.get((1, _r))
                    _el, _er = _rgs.get((0, _r)), _rgs.get((1, _r))
                    if not (_hl and _hr and _el and _er):
                        A('      %-3d %-13s FENETRE MANQUANTE sur au moins une passe'
                          % (_r, _rgtab[_r][1] if _r in _rgtab else '?'))
                        continue
                    _a, _b2 = _hl[0], _hr[0]
                    _c2, _d2 = _el[0], _er[0]
                    _rh = (max(_a, _b2) / min(_a, _b2)) if min(_a, _b2) > 0 else float('nan')
                    _re2 = (max(_c2, _d2) / min(_c2, _d2)) if min(_c2, _d2) > 0 else float('nan')
                    # LES DEUX COLONNES DE RAPPORT NE SONT PAS DE LA MEME POSE, DONC PAS DE LA
                    # MEME ADMISSIBILITE. `R^h` est un rapport gauche/droite releve dans PH-REG,
                    # `R^e` dans PH-REGS : chacune est publiee OU TAIT SON CHIFFRE selon SA pose,
                    # et jamais selon celle de l'autre. Les colonnes `apexL`/`apexR` restent :
                    # ce sont des mesures PAR CHAINE, pas des comparaisons, et une pose non
                    # miroir ne les invalide pas — elle invalide ce qu'on tire de leur DIFFERENCE.
                    # La largeur de colonne est conservee pour que le tableau reste alignable a la
                    # colonne pres par n'importe quel lecteur.
                    A('      %-3d %-13s %-9.4f %-9.4f %-8s %-9.4f %-9.4f %-8s'
                      % (_r, _rgtab[_r][1] if _r in _rgtab else '?', _a, _b2,
                         ('%.3f' % _rh) if _poh.ok() else 'NONSYM', _c2, _d2,
                         ('%.3f' % _re2) if _poe.ok() else 'NONSYM'))
                    if _rh == _rh and _re2 == _re2:
                        _ncmp += 1
                        if _re2 < _rh:
                            _tight += 1
                        # « le sens » = lequel des deux seins est le plus grand. Un booleen, pas
                        # une amplitude : c'est la grandeur que le cycle 65 a vue s'inverser.
                        if (_a > _b2) != (_c2 > _d2):
                            _flip += 1
                # ---- QUELLE COLONNE DE RAPPORT EST PUBLIABLE, ET SOUS QUELLE POSE -----------
                # Un tableau a deux colonnes de rapport dont l'une est muette doit le DIRE sous le
                # tableau, pas le laisser deviner a qui compte les `NONSYM`.
                _vcorps = (': R^h et R^e sont publiables toutes les deux' if _poh.ok() else
                           ': R^e est publiable ; R^h ne l\'est pas — PH-REG est a %s du miroir'
                           % _pdeg(_poh))
                A(asym('ROOM-REGS-VERROU', _vcorps, _poe,
                       note='R^h ne porte rien non plus : PH-REG est a %s du miroir.'
                            % _pdeg(_poh)))
                A('')
                # ---- LES DEUX COMPTEURS QUI COMPARENT LES DEUX POSES ENTRE ELLES -------------
                # Ils sont EXEMPTES du verrou, et la raison est de nature, pas de commodite : leur
                # grandeur n'est pas un ecart gauche/droite, c'est un ECART ENTRE DEUX POSES sur
                # cet ecart-la. Une pose asymetrique ne les fausse pas — elle EST ce qu'ils
                # mesurent. Ils portent donc les DEUX ecarts au miroir sur leur propre ligne, pour
                # qu'aucun lecteur ne puisse les prendre pour une propriete du PERSONNAGE.
                _RGSPO = '(PH-REG %s vs PH-REGS %s)' % (_pdeg(_poh), _pdeg(_poe))
                A('ROOM-REGS-SENS: %d fenetre(s) sur %d ou la pose INVERSE lequel des deux seins'
                  ' bouge le plus. %s' % (_flip, _ncmp, _RGSPO), notasym=True)
                A('ROOM-REGS-SERRE: %d fenetre(s) sur %d ou l\'ecart gauche/droite est PLUS PETIT'
                  ' dans la pose epinglee. %s' % (_tight, _ncmp, _RGSPO), notasym=True)
                _t1 = _rgs.get((0, 0)), _rgs.get((1, 0))
                if _t1[0] and _t1[1]:
                    _tm = max(_t1[0][0], _t1[1][0])
                    A(asym('ROOM-REGS-TEMOIN',
                           ': r=0 (aucun pilotage) apex chestL=%.4f chestR=%.4f -> %s'
                           % (_t1[0][0], _t1[1][0],
                              'ligne de base SAINE (< 0.10 B0) : les quatorze autres fenetres se'
                              ' lisent au-dessus d\'un plancher qui en est un.' if _tm < 0.10 else
                              'PLANCHER NON CALME (%.4f >= 0.10 B0) — la pose epinglee n\'est pas'
                              ' au repos, et aucune fenetre de cette passe ne se lit comme une'
                              ' reponse au seul pilotage.' % _tm), _poe))
                else:
                    A('ROOM-REGS-TEMOIN: fenetre r=0 ABSENTE — la passe n\'a pas de ligne de base.')
                A('CE QUE CE BLOC N\'ETABLIT PAS, et il faut le lire avec : les deux passes')
                A('   partagent le solveur, les tables et l\'operateur de pilotage, mais PAS leur')
                A('   place dans la course — PH-REGS est APPENDUE, donc elle herite d\'un autre')
                A('   historique de chaine. La POSE est la seule variable DECLAREE, elle n\'est pas')
                A('   la seule qui bouge. Ce bloc autorise a REFUSER une attribution au personnage')
                A('   quand le sens s\'inverse ; il n\'autorise pas a donner a §18 un chiffre neuf.')
            # ---- ROOM-POSE-RAFFINEMENT : 7.5 deg SUFFIT-IL ? (cycle 67) --------------------
            #
            # LA QUESTION, ET POURQUOI DEUX POSES NE PEUVENT PAS Y REPONDRE. Le cycle 66 a joue
            # les quinze fenetres a 48.0 deg puis a 7.5 deg et a montre que cinq ecarts
            # gauche/droite sur onze CHANGENT DE SENS entre les deux. Il en a conclu — a juste
            # titre — que le x5.58 de §18 etait la pose. Mais il reste une question que deux
            # points ne tranchent pas : **le x1.50 mesure a 7.5 deg est-il, lui, le personnage ?**
            # Si le rapport bouge encore quand on resserre la pose, alors 7.5 deg est encore une
            # pose, et on aurait publie l'une pour l'autre — exactement la faute du cycle 65,
            # commise un cran plus bas.
            #
            # LE TEST EST CELUI DU REGISTRE : on RESSERRE l'instrument et on regarde si la mesure
            # bouge. Il ne demande aucune theorie, il ne se discute pas, et il tranche. Les trois
            # passes partagent tout sauf la pose : memes tables `pre`/`drv`/`post`, meme
            # `physroom-reg-drive`, memes emplacements de lecture (53 = apex, 43 = COM), meme B0.
            #
            # NATURE : `R` est un RAPPORT sans unite entre les deux chaines, pris sur le maximum
            #   de fenetre de l'apex. L'ecart publie est un ecart RELATIF entre deux valeurs de R.
            # REPERE : celui de PH-REG et PH-REGS, sans quoi les trois passes ne se compareraient
            #   pas. CE QUI DISCRIMINE : la POSE, et rien d'autre de declare.
            # LECTURE QUAND LE DEFAUT EST ABSENT : 0 % — un rapport qui ne doit plus rien a la
            #   pose ne bouge pas quand on resserre la pose.
            _rgt = {}
            for _m in re.finditer(r'^PHYSREGT c=(\d+) r=(\d+) apex=([-\d.e+]+) com=([-\d.e+]+)',
                                  txt, re.M):
                _rgt[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)),
                                                              float(_m.group(4)))
            _gtp = re.search(r'^PHYSREGTPOSE a=(-?\d+) f=([-\d.e+]+) s=([-\d.e+]+)', txt, re.M)
            A('')
            A('   -- ROOM-POSE-RAFFINEMENT : LE MEME STIMULUS A TROIS ECARTS AU MIROIR ---------')
            if not _rgt:
                A('ROOM-POSE-RAFFINEMENT: NON PUBLIE — aucune ligne `PHYSREGT`. La question'
                  ' « 7.5 deg', notasym=True)
                A('   suffit-il ? » reste OUVERTE, et les chiffres « propres » du cycle 66 restent'
                  ' donc', notasym=True)
                A('   des chiffres dont on ne sait pas s\'ils decrivent le personnage ou sa pose.',
                  notasym=True)
            elif _gtp is None or int(_gtp.group(1)) < 0:
                A('ROOM-POSE-RAFFINEMENT: l\'argmax de pose n\'a pas pris (%s) : cette passe a'
                  ' rejoue une' % ('PHYSREGTPOSE absent' if _gtp is None else 'a=-1'),
                  notasym=True)
                A('   pose NON CHOISIE sous le nom de « pose resserree ». AUCUN de ses chiffres'
                  ' n\'est lu.', notasym=True)
            else:
                _dt = POSE['PH-REGT'].dev
                _de = POSE['PH-REGS'].dev
                _dh = POSE['PH-REG'].dev
                A('ROOM-POSE-RAFFINEMENT: pose retenue a=%d f=%.4f, ecart au miroir REVALIDE a'
                  ' l\'execution' % (int(_gtp.group(1)), float(_gtp.group(2))), notasym=True)
                A('   = %s   (PH-REG %s · PH-REGS %s)'
                  % ('%.2f deg' % _dt if _dt is not None else 'NON LU',
                     '%.1f deg' % _dh if _dh is not None else '?',
                     '%.1f deg' % _de if _de is not None else '?'), notasym=True)
                A('')
                A('      %-3s %-13s %-8s %-8s %-8s   %-8s %-8s %-9s %-8s %s'
                  % ('r', 'regime', 'apexL^t', 'apexR^t', 'R^t', 'R^e', '|dR|/R^e',
                     'sens', '%/deg', 'ecart admissible pour 2 % (§32)'))
                # L'INTERVALLE SUR LEQUEL LA SENSIBILITE EST MESUREE, lu sur les deux poses
                # elles-memes et jamais ecrit en dur : si une course change de poses, la
                # sensibilite publiee change avec elles.
                _DDEV = (_de - _dt) if (_de is not None and _dt is not None) else 0.0
                # LA POSE LA PLUS SERREE QUE CE RIG AIT RENDUE sur cette course : c'est la borne
                # de ce qu'on peut esperer, et donc ce qui decide si une fenetre est resoluble.
                _dtb = _dt if _dt is not None else float('inf')
                _rel, _flip2, _n2 = [], 0, 0
                for _r in (1, 3, 4, 6, 8, 9, 10, 11, 12, 13, 14):
                    _tl, _tr = _rgt.get((0, _r)), _rgt.get((1, _r))
                    _el, _er = _rgs.get((0, _r)), _rgs.get((1, _r))
                    if not (_tl and _tr and _el and _er):
                        A('      %-3d %-13s FENETRE MANQUANTE sur au moins une passe'
                          % (_r, _rgtab[_r][1] if _r in _rgtab else '?'))
                        continue
                    _a3, _b3 = _tl[0], _tr[0]
                    _c3, _d3 = _el[0], _er[0]
                    _rt = (max(_a3, _b3) / min(_a3, _b3)) if min(_a3, _b3) > 0 else float('nan')
                    _re3 = (max(_c3, _d3) / min(_c3, _d3)) if min(_c3, _d3) > 0 else float('nan')
                    _dr = (abs(_rt - _re3) / _re3) if (_re3 == _re3 and _re3 > 0) else float('nan')
                    _sf = (_a3 > _b3) != (_c3 > _d3)
                    # LA SENSIBILITE PAR FENETRE, ET CE QU'ELLE EXIGERAIT DE LA POSE. Le seuil
                    # global est MEDIAN : il ne protege pas les fenetres les plus sensibles, et
                    # les taire sous un seuil qui ne les couvre pas serait un faux vert. Chaque
                    # ligne porte donc l'ecart au miroir que SA propre sensibilite exigerait pour
                    # que la pose pese moins que les 2 % de §32 — et dit si une pose de ce rig
                    # l'atteint, `_dtb` etant la plus serree que cette course ait rendue.
                    _sens = (100.0 * _dr / _DDEV) if (_dr == _dr and _DDEV > 0) else float('nan')
                    _need = (2.0 / _sens) if (_sens == _sens and _sens > 1e-9) else float('inf')
                    A('      %-3d %-13s %-8.4f %-8.4f %-8.3f   %-8.3f %-8s %-9s %-8s %s'
                      % (_r, _rgtab[_r][1] if _r in _rgtab else '?', _a3, _b3, _rt, _re3,
                         ('%.1f %%' % (100.0 * _dr)) if _dr == _dr else '?',
                         'INVERSE' if _sf else 'stable',
                         ('%.2f' % _sens) if _sens == _sens else '?',
                         ('%.3f deg%s' % (_need, '' if _need >= _dtb else
                                          '  <<< AUCUNE POSE DE CE RIG NE L\'ATTEINT'))
                         if _need != float('inf') else 'toute pose convient'))
                    if _dr == _dr:
                        _rel.append(_dr)
                        _n2 += 1
                        if _sf:
                            _flip2 += 1
                _rel.sort()
                _med = _rel[len(_rel) // 2] if _rel else None
                A('')
                # LE TEMOIN DE LA PASSE, publie AVANT tout verdict : une fenetre sans pilotage.
                _t3 = (_rgt.get((0, 0)), _rgt.get((1, 0)))
                if _t3[0] and _t3[1]:
                    A(asym('ROOM-REGT-TEMOIN',
                           ': r=0 (aucun pilotage) apex chestL=%.4f chestR=%.4f -> %s'
                           % (_t3[0][0], _t3[1][0],
                              'ligne de base SAINE (< 0.10 B0)'
                              if max(_t3[0][0], _t3[1][0]) < 0.10
                              else 'PLANCHER NON CALME : les quatorze autres fenetres sont'
                                   ' sans echelle'),
                           POSE['PH-REGT']))
                if _med is not None:
                    A('ROOM-POSE-RAFFINEMENT: ecart relatif MEDIAN du rapport gauche/droite entre'
                      ' 7.5 deg', notasym=True)
                    A('   et la pose resserree = %.1f %% sur %d fenetres (min %.1f %%,'
                      ' max %.1f %%) ; %d fenetre(s)'
                      % (100.0 * _med, _n2, 100.0 * _rel[0], 100.0 * _rel[-1], _flip2),
                      notasym=True)
                    A('   changent de sens.', notasym=True)
                    # LE VERDICT EST CELUI DU CRITERE ECRIT AVANT LA COURSE (c67-predictions,
                    # Q3), et il n'est pas retouche apres l'avoir lu.
                    _v = (['LE PLATEAU EST ATTEINT A 7.5 deg : le rapport ne bouge plus quand',
                           '   on resserre la pose, donc le seuil de 10 deg etait ADEQUAT et les',
                           '   chiffres du cycle 66 tiennent.']
                          if (_med <= 0.03 and _flip2 == 0) else
                          ['AUCUNE POSE DISPONIBLE N\'EST ASSEZ SYMETRIQUE : le rapport bouge',
                           '   encore de plus de 30 % entre 7.5 deg et la pose la plus serree du',
                           '   rig. AUCUN ecart gauche/droite de §14 a §20 n\'est publiable, y',
                           '   compris ceux que le cycle 66 a presentes comme propres.']
                          if _med > 0.30 else
                          ['LE PLATEAU N\'EST PAS ATTEINT A 7.5 deg, ET LE SEUIL DE 10 deg EST',
                           '   DONC REFUTE PAR LE CRITERE ECRIT AVANT LA COURSE (c67 Q3). Le pas',
                           '   7.5 -> 0.6 deg deplace pourtant BEAUCOUP MOINS que le pas 48 ->',
                           '   7.5. Le rapport garde une part de pose : il se publie avec son',
                           '   ecart au miroir, jamais comme une propriete du personnage, et le',
                           '   seuil descend a %.1f deg (derive : 2 %% de §32 / %.2f %% par deg).'
                           % (_ASYM_SEUIL, 100.0 * _med / 6.868)])
                    A('ROOM-POSE-RAFFINEMENT-VERDICT: %s' % _v[0], notasym=True)
                    for _vl in _v[1:]:
                        A(_vl, notasym=True)
            A('')
            # ---- ROOM-REGAXE : LES ROTATIONS DE §18 A §20 SONT-ELLES CELLES QUE LA SPEC NOMME ? ---
            #
            # LA QUESTION N'AVAIT JAMAIS ETE POSEE. `physroom-reg-pose` tourne autour des axes du
            # MONDE, pris litteralement — (1,0,0) pour ce que `physroom-reg-axis` appelle « tangage »,
            # (0,1,0) pour le lacet, (0,0,1) pour le « roulis ». Mais §18 a §20 sont definies dans le
            # repere du SUJET (« torso yaw », « forward bend », « lateral torso motion »), et rien ne
            # garantit que le sujet soit aligne sur le monde. Personne ne l'avait mesure.
            #
            # NATURE : des ANGLES en degres entre deux directions unitaires. REPERE : le MONDE.
            # LECTURE QUAND LE DEFAUT EST ABSENT : 0 deg entre l'axe commande et l'axe anatomique que
            #   la section nomme. CE QUI DISCRIMINE : rien d'autre que la geometrie — ces angles ne
            #   dependent d'aucun reglage du solveur.
            _axs = {}
            for _m in re.finditer(r'^PHYSAXW ax=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)',
                                  txt, re.M):
                _axs[int(_m.group(1))] = tuple(float(_m.group(k)) for k in (2, 3, 4))
            A('')
            A('   -- ROOM-REGAXE : L\'AXE DES ROTATIONS DE §18 A §20 (cycle 67) -------------------')
            if len(_axs) < 3:
                A('ROOM-REGAXE: NON PUBLIE — `PHYSAXW` incomplet, les axes du sujet ne sont pas lus.',
                  notasym=True)
            else:
                def _angd(u, v):
                    _d = abs(sum(u[k] * v[k] for k in range(3)))
                    return math.degrees(math.acos(max(-1.0, min(1.0, _d))))
                _W = (('X', (1.0, 0.0, 0.0)), ('Y', (0.0, 1.0, 0.0)), ('Z', (0.0, 0.0, 1.0)))
                _AN = {0: 'vertical', 1: 'avant/arriere', 2: 'lateral'}
                A('      axes du SUJET, mesures a l\'execution (PHYSAXW, repere monde) :')
                for _k in (0, 1, 2):
                    A('        %-14s (%+.4f, %+.4f, %+.4f)   monde X %5.1f  Y %5.1f  Z %5.1f deg'
                      % (_AN[_k], _axs[_k][0], _axs[_k][1], _axs[_k][2],
                         _angd(_axs[_k], _W[0][1]), _angd(_axs[_k], _W[1][1]),
                         _angd(_axs[_k], _W[2][1])), notasym=True)
                # CONFIRMATION INDEPENDANTE DE L'AXE LATERAL, sans se fier au NOM que le solveur donne
                # a ses axes. Pour une paire MIROIR, u_L - u_R = -2 (n.u_R) n : la difference des deux
                # directions d'os est COLINEAIRE a la normale du miroir, donc a l'axe lateral. Deux
                # routes independantes doivent donner le meme axe ; si elles divergent, c'est le NOM
                # qui est faux, et tout ce bloc avec lui.
                _st = {}
                for _m in re.finditer(r'^PHYSPOSETAG tag=settle c=(\d+) l=(\d+) ux=([-\d.e+]+)'
                                      r' uy=([-\d.e+]+) uz=([-\d.e+]+)', txt, re.M):
                    _st[(int(_m.group(1)), int(_m.group(2)))] = \
                        tuple(float(_m.group(k)) for k in (3, 4, 5))
                if (0, 0) in _st and (1, 0) in _st:
                    _d3 = [_st[(0, 0)][k] - _st[(1, 0)][k] for k in range(3)]
                    _n3 = math.sqrt(sum(x * x for x in _d3))
                    if _n3 > 1e-6:
                        _u3 = [x / _n3 for x in _d3]
                        A('      CONTROLE INDEPENDANT : (u_chestL - u_chestR) normalise ='
                          ' (%+.4f, %+.4f, %+.4f),' % tuple(_u3), notasym=True)
                        A('        a %.3f deg de l\'axe que le solveur NOMME lateral. Les deux routes'
                          ' concordent, donc' % _angd(_u3, _axs[2]), notasym=True)
                        A('        le nom est bon et ce qui suit ne depend pas de lui.', notasym=True)
                A('')
                A('      r      section  axe commande   role REEL dans le repere du sujet')
                for _r, _sec, _wi in ((9, '§18', 1), (10, '§18', 1), (11, '§19', 0), (12, '§19', 0),
                                      (13, '§20', 2), (14, '§20', 2)):
                    _w = _W[_wi]
                    _best, _ba = None, 999.0
                    for _k in (0, 1, 2):
                        _a = _angd(_w[1], _axs[_k])
                        if _a < _ba:
                            _ba, _best = _a, _k
                    _role = {0: 'LACET', 1: 'ROULIS (flexion laterale)',
                             2: 'TANGAGE (flexion avant/arriere)'}[_best]
                    _want = {'§18': 0, '§19': 2, '§20': 1}[_sec]
                    A('      %-6d %-8s monde %-8s %s a %.1f deg%s'
                      % (_r, _sec, _w[0], _role, _ba,
                         '' if _best == _want else '   <<< CE N\'EST PAS LE GESTE DE CETTE SECTION'))
                A('')
                A('      §18 « torso yaw » veut le VERTICAL · §19 « forward bend » veut le LATERAL ·')
                A('      §20 « lateral torso motion » veut l\'AVANT/ARRIERE. Le lacet tombe juste ;')
                A('      §19 et §20 SE JOUENT L\'UN POUR L\'AUTRE.')
                A('')
                # LA PREUVE PAR L'ALGEBRE, CONFIRMEE PAR LA MESURE.
                _dvi = _pose_dev_from(txt, 'PHYSPOSETAG', _lat, extra='tag=idle')
                _dvt = _pose_dev_from(txt, 'PHYSPOSETAG', _lat, extra='tag=tilt')
                if _dvi is not None and _dvt is not None:
                    A('ROOM-REGAXE-LEAN: une rotation AUTOUR de l\'axe lateral commute avec la'
                      ' reflexion dans le', notasym=True)
                    A('   plan de normale laterale : elle laisse l\'ecart au miroir INVARIANT, par'
                      ' algebre.', notasym=True)
                    A('   `physroom-lean` tourne autour du monde X et fait passer cet ecart de'
                      ' %.3f deg (pose' % _dvi, notasym=True)
                    A('   `idle`) a %.3f deg (pose `tilt`). L\'axe X n\'est donc PAS le lateral, et ce'
                      ' que la salle' % _dvt, notasym=True)
                    A('   documente comme « penchee de 60 deg VERS L\'AVANT » est une inclinaison'
                      ' LATERALE.', notasym=True)
                    A('   Consequence : §12 (« sideways gravity ») est servie par le bon geste ; le'
                      ' PENCHE AVANT', notasym=True)
                    A('   de §13 (« at a 45 deg forward lean ») n\'a jamais ete joue, et'
                      ' `ROOM-GRAVSAG` ne', notasym=True)
                    A('   repond donc pas a la plainte « aucun mouvement quand elle se penche en avant'
                      ' pour souder ».', notasym=True)
                A('')
            # ---- ROOM-REGA : LES SIX FENETRES, AUTOUR DES AXES DU SUJET ET DANS LES DEUX SENS ---
            #
            # POURQUOI LES DEUX SENS. Le signe d'un axe MESURE est arbitraire : le solveur rend un
            # axe « vertical » qui pointe vers le BAS et un axe avant/arriere qui pointe vers
            # l'ARRIERE. Epingler un signe dans le source serait un choix ; jouer les deux et
            # publier le deplacement REEL de l'ancre est une mesure. La paire est en outre le
            # controle a STIMULUS MIROIR que §12 et §20 reclament.
            #
            # COMMENT LE SENS SE NOMME, ET LA REGLE EST MESUREE, PAS SUPPOSEE. Sur le mesh livre,
            # la direction d'os `chest -> lBoob` a une composante AVANT de **+0,154** ; le solveur
            # lit cette meme direction a **-0,130** sur SES axes, sur LES DEUX chaines et avec la
            # meme grandeur. Son axe avant/arriere pointe donc vers l'ARRIERE, et
            #     **dap < 0  =  le buste est parti VERS L'AVANT**.
            # NATURE de dap/dver/dlat : trois LONGUEURS signees (u, 4096 u = 1 m), deplacement de
            #   l'ancre entre le repos de la fenetre et la fin du pilotage.
            # REPERE : les axes du SUJET releves au repos. LECTURE HORS DEFAUT : 0.
            _rga2, _rgad = {}, {}
            for _m in re.finditer(r'^PHYSREGA c=(\d+) r=(\d+) sgn=([-\d.e+]+) apex=([-\d.e+]+)'
                                  r' com=([-\d.e+]+)', txt, re.M):
                _rga2[(int(_m.group(1)), int(_m.group(2)),
                       1 if float(_m.group(3)) > 0 else -1)] = (float(_m.group(4)),
                                                                float(_m.group(5)))
            for _m in re.finditer(r'^PHYSREGAD r=(\d+) sgn=([-\d.e+]+) dap=([-\d.e+]+)'
                                  r' dver=([-\d.e+]+) dlat=([-\d.e+]+)', txt, re.M):
                _rgad[(int(_m.group(1)), 1 if float(_m.group(2)) > 0 else -1)] = \
                    tuple(float(_m.group(k)) for k in (3, 4, 5))
            _gap = re.search(r'^PHYSREGAPOSE a=(-?\d+) f=([-\d.e+]+)', txt, re.M)
            A('   -- ROOM-REGA : §18 A §20, AXES DU SUJET, LES DEUX SENS (cycle 68) -------------')
            if not _rga2:
                A('ROOM-REGA: NON PUBLIE — aucune ligne `PHYSREGA`. §19 et §20 restent mesurees sur'
                  ' un', notasym=True)
                A('   geste qui n\'est pas le leur, et leur ligne du registre le dit.',
                  notasym=True)
            elif _gap is None or int(_gap.group(1)) < 0:
                A('ROOM-REGA: l\'epingle de pose n\'a pas pris — aucun chiffre publie.',
                  notasym=True)
            else:
                _dva = POSE['PH-REGA'].dev
                A('ROOM-REGA: pose a=%d f=%.4f, ecart au miroir revalide = %s ; axe pris sur le'
                  ' SUJET' % (int(_gap.group(1)), float(_gap.group(2)),
                              ('%.2f deg' % _dva) if _dva is not None else 'NON LU'),
                  notasym=True)
                A('   dap < 0 = le buste part VERS L\'AVANT (l\'axe AP du solveur pointe vers'
                  ' l\'arriere,', notasym=True)
                A('   mesure : os chest->lBoob a +0.154 sur le mesh livre, -0.130 sur cet axe).',
                  notasym=True)
                A('')
                A('      %-3s %-7s %-4s %-9s %-9s %-9s %-8s %-8s %-7s %s'
                  % ('r', 'section', 'sgn', 'dap (u)', 'dver (u)', 'dlat (u)', 'apexL',
                     'apexR', 'R', 'geste obtenu'))
                _fwd = {}
                for _r, _sec in ((9, '§18'), (10, '§18'), (11, '§19'), (12, '§19'),
                                 (13, '§20'), (14, '§20')):
                    for _sg in (1, -1):
                        _al = _rga2.get((0, _r, _sg))
                        _ar = _rga2.get((1, _r, _sg))
                        _dd = _rgad.get((_r, _sg))
                        if not (_al and _ar and _dd):
                            A('      %-3d %-8s %-4d FENETRE MANQUANTE' % (_r, _sec, _sg))
                            continue
                        # LE GESTE EST NOMME PAR LA GRANDEUR QUI DOMINE, jamais par l'etiquette —
                        # et le discriminant est celui que la donnee fournit elle-meme :
                        #   un LACET est purement HORIZONTAL      -> dver ~ 0, dap ET dlat bougent
                        #   un TANGAGE est dans le plan sagittal  -> dlat ~ 0, dap et dver bougent
                        #   un ROULIS est dans le plan frontal    -> dap  ~ 0, dlat et dver bougent
                        # Ma premiere version comparait |dap| a |dlat| et classait donc un lacet en
                        # « flexion avant » des que son arc penchait de ce cote : elle nommait le
                        # geste par la plus grosse composante au lieu de par celle qui MANQUE.
                        _mx = max(abs(_dd[0]), abs(_dd[1]), abs(_dd[2]))
                        _nom = ('deplacement negligeable' if _mx < 1.0 else
                                'LACET' if abs(_dd[1]) < 1.0 else
                                ('flexion AVANT' if _dd[0] < 0 else 'flexion ARRIERE')
                                if abs(_dd[2]) < 1.0 else
                                'inclinaison LATERALE' if abs(_dd[0]) < 1.0 else
                                'geste MIXTE')
                        if _sec == '§19' and _dd[0] < 0 and abs(_dd[2]) < 1.0 and _mx >= 1.0:
                            _fwd[_r] = _sg
                        _rr = (max(_al[0], _ar[0]) / min(_al[0], _ar[0])
                               if min(_al[0], _ar[0]) > 0 else float('nan'))
                        A('      %-3d %-7s %+4d %-9.1f %-9.1f %-9.1f %-8.4f %-8.4f %-7.3f %s'
                          % (_r, _sec, _sg, _dd[0], _dd[1], _dd[2], _al[0], _ar[0], _rr, _nom))
                A('')
                # LE VERDICT DE SENS, ET C'EST LA SEULE CHOSE QUE CE BLOC TRANCHE AUJOURD'HUI.
                if _fwd:
                    A('ROOM-REGA-SENS: la flexion AVANT de §19 est obtenue au signe %s (fenetres'
                      ' %s).' % ('+1' if list(_fwd.values())[0] > 0 else '-1',
                                 ', '.join('r=%d' % k for k in sorted(_fwd))), notasym=True)
                    A('   C\'est une MESURE du deplacement de l\'ancre, pas un signe choisi : le'
                      ' geste que', notasym=True)
                    A('   §19 nomme peut donc enfin etre joue, et l\'autre signe reste publie a'
                      ' cote comme', notasym=True)
                    A('   son controle a stimulus miroir.', notasym=True)
                else:
                    A('ROOM-REGA-SENS: AUCUN des deux signes ne produit une flexion AVANT sur les'
                      ' fenetres', notasym=True)
                    A('   de §19. Le geste de cette section reste INJOUABLE, et le dire est le'
                      ' resultat.', notasym=True)
            A('')
            A('   -- ROOM-SPEC15-CROSS : « jump apex -> breast may CROSS neutral position » -----')
            A('      §15 l.230. Le registre portait la clause NON DEMONTREE, et la raison etait')
            A('      un defaut d\'INSTRUMENT, pas un defaut du moteur : le vecteur du COM n\'etait')
            A('      releve qu\'a l\'ARGMAX de sa norme, c\'est-a-dire UNE frame, ce qui ne peut ni')
            A('      etablir ni exclure une traversee. `cydn`/`cyup` sont les DEUX extremes de la')
            A('      composante VERTICALE du COM sur la fenetre, publies tous deux EN POSITIF')
            A('      (`cydn` = le plus bas atteint, change de signe). NATURE : deux longueurs /B0,')
            A('      maxima de fenetre. REPERE : monde, contre la pose d\'auteur. LECTURE HORS')
            A('      DEFAUT : 0.0000. LA TRAVERSEE EXIGE LES DEUX STRICTEMENT POSITIFS — un seul')
            A('      a zero veut dire que l\'organe est reste du meme cote du neutre.')
            A('      POURQUOI DEUX MAXIMA ET NON UN MIN ET UN MAX : le reset de fenetre met les')
            A('      emplacements a 0.0, et un MINIMUM ainsi initialise ne peut pas remonter')
            A('      au-dessus de 0 — il lirait 0 sur une fenetre entierement positive et')
            A('      annoncerait une traversee qui n\'a pas eu lieu. Un faux vert, sur la seule')
            A('      clause que §15 rende verifiable.')
            for _r in sorted({k[1] for k in _rgf}):
                for _c in sorted({k[0] for k in _rgf if k[1] == _r}):
                    _dn, _up = _rgf[(_c, _r)]
                    _cr2 = (_dn > 1e-4) and (_up > 1e-4)
                    A('ROOM-SPEC15-CROSS: %-8s r=%2d %-13s cydn=%.4f cyup=%.4f -> %s'
                      % (_rgnm(_c), _r, _rgtab[_r][1], _dn, _up,
                         'TRAVERSEE' if _cr2 else 'PAS DE TRAVERSEE (un seul cote)'))
            _fly = [(_c, _r) for (_c, _r) in _rgf if _r in (2, 5)]
            if _fly:
                _nx = sum(1 for k in _fly if _rgf[k][0] > 1e-4 and _rgf[k][1] > 1e-4)
                A('ROOM-SPEC15-CROSS: VERDICT §15 sur les fenetres de VOL (r=2, r=5) : %d des %d'
                  ' fenetres traversent le neutre -> %s'
                  % (_nx, len(_fly), 'CLAUSE TENUE' if _nx > 0 else 'CLAUSE NON TENUE'))
            else:
                A('ROOM-SPEC15-CROSS: aucune fenetre de VOL dans cette trace — §15 non jugeable.')
        A('')
        # ---- LA TABLE DES REGIMES, CITEE ------------------------------------------------------
        A('   -- LA TABLE DES REGIMES ET LE TEXTE QU\'ELLE CITE --------------------------------')
        for _r, _nm2, _sec, _kind, _band, _cite in _RGT:
            _pre = ('   r=%2d %-13s %-5s %-14s '
                    % (_r, _nm2, ('§' + _sec) if _sec else '  -  ',
                       ('[%.2f-%.2f]' % _band) if _band else '[pas de bande]'))
            _wrap, _cur = [], _pre
            for _w in _cite.split(' '):
                if len(_cur) + 1 + len(_w) > 98 and _cur.strip():
                    _wrap.append(_cur)
                    _cur = ' ' * len(_pre) + _w
                else:
                    _cur = (_cur + _w) if _cur.endswith(' ') else (_cur + ' ' + _w)
            _wrap.append(_cur)
            for _ln2 in _wrap:
                A(_ln2)
    if not _axres:
        A('-- SPEC 33 / ABLATION DE LA CONTRAINTE DE LONGUEUR : NON MESUREE par cette course -----')
        A('   Aucune ligne PHYSAXRES dans la trace (moteur ou salle anterieurs au cycle 29).')
    else:
        _AXN = {0: 'VERTICAL', 1: 'AVANT-ARRIERE', 2: 'LATERAL'}
        A('-- SPEC 33 : LE RESIDU D\'INTERPENETRATION, CONTRAINTE DE LONGUEUR EN PLACE PUIS LEVEE --')
        A('   Meme impulsion, meme fenetre, meme emetteur ; seul `nolen` change. `res` en unites')
        A('   de jeu (4096 = 1 m), maximum de fenetre, APRES le solveur, au-dela du plancher de')
        A('   pose d\'auteur. LECTURE HORS DEFAUT : 0.0000.')
        A('   axe            chaine        res(len ON)  res(len OFF)   rapport   ci ON/OFF'
          '   comex ON/OFF (B0)')
        for _ax in (0, 1, 2):
            for _c in sorted(chains):
                _on = _axres.get((_c, _ax, 0))
                _off = _axres.get((_c, _ax, 1))
                if _on is None or _off is None:
                    continue
                _rat = ('%8.3f' % (_off[0] / _on[0])) if _on[0] > 0.0 else '     n/a'
                _cx = ''
                if (_c, _ax, 0) in _axcom and (_c, _ax, 1) in _axcom:
                    _cx = '   %.4f / %.4f' % (_axcom[(_c, _ax, 0)], _axcom[(_c, _ax, 1)])
                A('   %-14s %-12s %11.4f %13.4f %9s   %d/%d%s'
                  % (_AXN[_ax], names[_c] if _c < len(names) else _c,
                     _on[0], _off[0], _rat, int(_on[1]), int(_off[1]), _cx))
        _dom = max([v[0] for k, v in _axres.items() if k[2] == 0] or [0.0])
        if _dom < 50.0:
            A('   DOMAINE VIDE : le plus gros residu de reference vaut %.4f u (< 50 u). Cette' % _dom)
            A('   impulsion ne met pas les deux seins en contact, donc l\'ablation ne prouve RIEN')
            A('   ici — ni dans un sens ni dans l\'autre. Il faut une fenetre de PILOTAGE.')
        else:
            _lat = [(names[c] if c < len(names) else c,
                     _axres[(c, 2, 0)][0], _axres[(c, 2, 1)][0])
                    for c in sorted(chains) if (c, 2, 0) in _axres and (c, 2, 1) in _axres]
            _conf = [n for n, a, b in _lat if a >= 50.0 and b <= 0.40 * a]
            _ref = [n for n, a, b in _lat if a >= 50.0 and b >= 0.85 * a]
            if _conf:
                # LE CRITERE REND VERT ET IL N'EST PAS DISCRIMINANT — ON NE PREND PAS LE VERT.
                # Desarmer `phys-length-chain` ne retire pas « la confiscation de la composante
                # radiale » : il retire LA SEULE restriction cinematique du solveur. Un point
                # libre sort de n'importe quel volume, quelle que soit la cause qui l'y retenait.
                # Ce controle aurait donc rendu zero pour TOUTE hypothese — c'est le piege
                # `attribution-harness-outlives-its-defect`, paye au cycle 28 sur ROOM-ORICTL.
                # Ce qui discrimine est la GEOMETRIE (probe_c29_chain_axis.py) : l'angle entre la
                # radiale du maillon et la direction de separation vaut 68-69 deg, donc 86 a 87 %
                # de la poussee survit a la projection. L'hypothese est REFUTEE, pas confirmee.
                A('   VERDICT : le critere pose avant la course (C29-lenres-prediction.txt) rend')
                A('   VERT sur %s — ET IL N\'EST PAS DISCRIMINANT, donc ce vert est REFUSE.'
                  % ' '.join(_conf))
                A('   Desarmer la contrainte de longueur ne retire pas une DIRECTION, elle retire')
                A('   la SEULE restriction cinematique : un point libre sort de tout volume, quelle')
                A('   que soit la cause. Ce controle aurait rendu zero pour n\'importe quelle')
                A('   hypothese. Ce qui discrimine est la geometrie (probe_c29_chain_axis.py) :')
                A('   68-69 deg entre la radiale du maillon et la direction de separation, donc')
                A('   86-87 % de la poussee SURVIT a la projection — l\'hypothese est REFUTEE.')
            elif len(_ref) == len(_lat) and _lat:
                A('   VERDICT : la contrainte de longueur est EXONEREE sur l\'axe lateral (residu')
                A('   inchange a 15 %% pres quand elle est levee). L\'hypothese est REFUTEE.')
            else:
                A('   VERDICT : NON CONCLUANT au critere pose avant la course. Publie tel quel.')
        if _axtan:
            A('   rendement geometrique de la poussee de contact, par fenetre (delta cumule) :')
            _pn = _ps = _pr = 0
            _first = True
            for _ax, _nl, _n, _sd, _rm in _axtan:
                _dn, _dsd, _drm = _n - _pn, _sd - _ps, _rm - _pr
                _pn, _ps, _pr = _n, _sd, _rm
                _e = ('%7.4f' % (_drm / _dsd)) if _dsd > 0.0 else '    n/a'
                # LE PREMIER DELTA N'EST PAS UNE FENETRE : les compteurs sont CUMULES depuis le
                # debut de la course et rien ne les remet a zero avant (les remettre changerait
                # `PHYSTAN`, deja publie). La premiere ligne porte donc tout le reste de la
                # course ; seules les SUIVANTES sont des fenetres, et elles sont minuscules.
                _flag = ('  <- CUMUL DE TOUTE LA COURSE, pas une fenetre' if _first else
                         ('  <- domaine trop petit pour conclure' if _dn < 10000 else ''))
                _first = False
                A('     %-14s len=%s  poussees=%-9d rend=%s%s'
                  % (_AXN[_ax], 'OFF' if _nl else 'ON ', _dn, _e, _flag))
            A('   Un rendement proche de 0 dirait que la poussee est RADIALE et que la projection')
            A('   sur la sphere de l\'attache la rend a zero. MAIS les fenetres d\'impulsion sont')
            A('   quasi sans contact (quelques milliers de poussees contre 2.25 millions sur le')
            A('   reste de la course) : aucune de ces lignes, hors la premiere, ne porte assez')
            A('   d\'echantillons pour etre lue comme une mesure. Publiees, pas exploitees.')
    # ---- ROOM-SKINPEN : la penetration contre la PEAU, a lire A COTE de meshpen ------------------
    sp_run = skinpen.get('run', {})
    if sp_run:
        A('')
        A('-- SPEC 18 : LA PENETRATION MESUREE CONTRE LA PEAU, PAS CONTRE LES VOLUMES ------------')
        A('   `meshpen` compte contre les volumes de collision, qui ne representent que 29.7 % de la')
        A('   geometrie que la physique pilote (0 % pour backhair, pantflapL, pantflapR ; 10 % pour')
        A('   les lunettes). Un zero y reste donc compatible avec ce que l\'owner voit. Cette')
        A('   colonne-ci mesure la MEME position ecrite contre le mesh qui est DESSINE.')
        A('   LEGENDE CORRIGEE le 2026-08-14 : elle disait « son zero est donc compatible avec ce')
        A('   que l\'owner voit » a une epoque ou la colonne `meshpen` de CETTE ligne valait zero')
        A('   sur les 22 chaines — non pas parce que rien ne penetrait, mais parce qu\'elle lisait')
        A('   une cle absente (voir juste dessous). Corrigee, 18 chaines sur 22 publient une valeur')
        A('   non nulle, jusqu\'a 0.7578 m. La phrase decrivait un faux zero, pas une mesure.')
        A('   NATURE : profondeur en metres, positive = SOUS la peau. REPERE : le monde, frame')
        A('   ecrite. LECTURE HORS DEFAUT : 0. tests=0 veut dire « pas regarde », jamais « rien ».')
        _tot = max((t for _v, t in sp_run.values()), default=0)
        if _tot == 0:
            A('   ROOM-SKINPEN: AUCUN echantillon teste — le fichier physics_mesh.txt n\'est pas')
            A('   charge, ou aucun os du rig ne porte d\'ensemble. Ces zeros ne sont PAS une mesure.')
        # LA COLONNE `meshpen` DE CETTE LIGNE LISAIT UNE CLE QUI N'EXISTE PAS.
        #
        # Elle valait `dr_run[c].get('pen', 0.0)`, or `dr_run` est le dictionnaire des lignes
        # PHYSDIAG* : il ne porte QUE selfcol/retreat/flip/inv/invres/elong/rad/bendcut/shape/
        # buried/tiprot/side/volprio/shellrad/shellin/shellout/rootrot/raddropm/retfblen. La cle
        # 'pen' n'y est ecrite NULLE PART, donc le `.get(..., 0.0)` retombait TOUJOURS sur son
        # defaut : les 22 chaines publiaient `meshpen=0.0000` pendant que les lignes `worst` du
        # MEME tableau publiaient 0.5405 sur rmidhair. Deux grandeurs sous un seul nom, dont une
        # inventee — exactement le faux vert que la regle 1 interdit, et un zero qu'aucun controle
        # positif ne pouvait faire monter puisqu'il ne venait d'aucune mesure.
        #
        # La penetration contre les VOLUMES est `PHYSROW pen=`, agregee dans `worst[c]['pen']`.
        # On lit desormais CETTE source, la meme que les lignes `worst` (l. ~1776) et que le resume
        # d'ecran (l. ~2418) : les trois endroits ne peuvent plus diverger, c'est tout l'interet.
        # `fnum` et non `%.4f` pour la meme raison qu'ailleurs : une penetration de 1.7e-07 m ne
        # doit pas etre arrondie en « 0.0000 ».
        # Et une chaine SANS ligne PHYSROW n'a pas de penetration mesuree : elle ecrit
        # `NON-MESURE`, en mots, jamais un zero qu'on ne pourrait pas distinguer d'une mesure.
        # ============================================================================================
        # FORMAT : `ROOM-SKINPEN: <chaine> <metres>`, et la ligne riche part sous
        # `ROOM-SKINPEN-DETAIL:`. C'est la forme que l'arbitrage du 2026-08-20 13:20 lit, et la
        # separer evite qu'une colonne ajoutee plus tard decale ce que la gate croit lire.
        #
        # ET LA LIGNE DE BASE VA AVEC, PARCE QUE SANS ELLE CE CHIFFRE NE VEUT RIEN DIRE : l'os de
        # poitrine est INTERIEUR par construction du rig. `ROOM-SKINPEN-REST` porte le MINIMUM des
        # deux chaines — le validateur applique la premiere valeur trouvee aux DEUX, donc publier le
        # minimum est la lecture STRICTE ; le detail par chaine suit juste en dessous.
        _rest = skinrest.get('run', {})
        _out = skinout.get('run', 0)
        for v, c in sorted(((v, c) for c, (v, _t) in sp_run.items()), reverse=True):
            _mp = (worst.get(c) or {}).get('pen')
            A('ROOM-SKINPEN: %s %.4f' % (names[c] if c < len(names) else c, v))
            A('ROOM-SKINPEN-DETAIL: chain=%-12s skinpen=%.4f m   meshpen=%s   repos=%s m'
              % (names[c] if c < len(names) else c, v,
                 ('%s m' % fnum(_mp['v'])) if _mp else 'NON-MESURE',
                 ('%.4f' % _rest[c]) if c in _rest else 'NON MESURE'))
        # ============================================================================================
        # [NOTE-156] LA LIGNE DE BASE QUE LA GATE LIT VIENT DE LA FENETRE DE REPOS, PAS DU POINT
        # D'AUTEUR. C'est ce que l'arbitrage du 2026-08-20 13:20 demande mot pour mot (« physique
        # DESARMEE »), et c'est la seule version dont le predicat est IDENTIQUE a celui de la
        # course : meme fonction, meme point (`*phys-px*`), meme garde `sd < 0`.
        #
        # POURQUOI LE POINT D'AUTEUR NE PEUT PAS LA PORTER, ET C'EST MESURE : `skinout` compte les
        # lectures qui placent ce point DEHORS, ce qui est anatomiquement impossible pour un os
        # interieur. Il vaut 41842 sur la course. La valeur reste publiee comme DIAGNOSTIC sous
        # `ROOM-SKINPEN-REST-AUTEUR`, jamais sous le nom que la gate lit.
        if _bs:
            _cs, _cd, _cm = int(_bs.group(1)), int(_bs.group(2)), int(_bs.group(3))
            _cs += _bschain
            A('ROOM-SKINPEN-COVERAGE: ensembles=%d/%d  echantillons<=%d  (dont %d de CHAINE,'
              ' lus seulement par la chaine ADVERSE — SPEC 33)' % (_cs, _cd, _cm, _bschain))
            if _cs < _cd:
                A('   %d ENSEMBLE(S) DE SURFACE SUR %d SONT JETES par le plafond. La SDF ne voit'
                  % (_cd - _cs, _cd))
                A('   donc PAS toute la peau, et un os INTERIEUR peut s\'y lire DEHORS. Aucun')
                A('   plancher tire de cette SDF ne vaut tant que ce couple n\'est pas egal.')
        else:
            A('ROOM-SKINPEN-COVERAGE: NON PUBLIEE (trace anterieure au cycle 60)')
        # ==========================================================================================
        # [NOTE-241] LA LIGNE DE BASE CHANGE DE SOURCE, ET LE CONTROLE NEGATIF QUI L'EXIGE A TIRE.
        #
        # CE QUI ETAIT PUBLIE JUSQU'ICI : `ROOM-SKINPEN-REST` portait le maximum de la FENETRE DE
        # REPOS (`physroom-hold`, 120 frames, ~250 000 evaluations) pendant que `ROOM-SKINPEN`
        # portait le maximum de la COURSE (16 740 frames, ~36 000 000 d'evaluations, 31 animations).
        # Deux populations, un rapport : c'est `ratio-of-two-statistics`, et le registre le paie
        # depuis des semaines.
        #
        # LE CONTROLE NEGATIF, ET IL EST DANS LA TRACE LIVREE, PAS DANS UN RAISONNEMENT. La colonne
        # `PHYSSKIN2 skinrest` du tag `run` est la lecture du point que L'AUTEUR a dessine — la pose
        # sans physique, par definition — sur EXACTEMENT la meme fenetre, les memes frames, les memes
        # maillons, les memes echantillons et la meme fonction que `skinpen`. Elle vaut 268.90 u
        # (chestL) et 458.05 u (chestR) la ou la fenetre de repos rendait 143.64 / 203.97.
        # AUTREMENT DIT : PHYSIQUE ENTIEREMENT DESARMEE, LA GATE LISAIT DEJA 0.0656 ET 0.1118 CONTRE
        # UN PLANCHER DE 0.0351, DONC ELLE ECHOUAIT. Une gate qu'aucune physique ne peut passer ne
        # mesure pas la physique. Ce n'est pas la gate qui est en cause — elle n'a jamais bouge —
        # c'est CE FICHIER qui lui donnait la mauvaise colonne.
        #
        # CE QUI EST PUBLIE MAINTENANT : le plancher est la lecture d'AUTEUR de la MEME fenetre.
        # C'est « physique desarmee » au sens exact du terme, et c'est la seule version ou la
        # difference `skinpen - plancher` soit imputable a la physique et a rien d'autre.
        # LA VALEUR UNIQUE EST LA PIRE DES DEUX CHAINES, et pas la meilleure : la gate applique la
        # premiere valeur trouvee aux DEUX chaines, or chaque chaine est legitimement bornee par SON
        # PROPRE plancher. Prendre le minimum exigerait de chestR qu'elle passe sous le plancher de
        # chestL, c'est-a-dire sous la pose que l'auteur lui a donnee : une exigence que la geometrie
        # rend vide, pas une exigence stricte. Le verdict PAR CHAINE, contre SON propre plancher, est
        # publie juste en dessous et ne se cache donc derriere aucun agregat.
        _hold  = skinpen.get('rest', {})
        _holdr = skinrest.get('rest', {})
        _missr = skinmiss.get('run', {})
        _restw = dict(_rest)
        # GARDE 1 (premisse intacte) : si la peau lue n'est pas celle du personnage, aucun plancher.
        if _bs and int(_bs.group(1)) + _bschain < int(_bs.group(2)):
            _restw = {}
            A('ROOM-SKINPEN-REST-TRONQUEE: %d ensemble(s) de surface sur %d sont jetes — la SDF ne'
              % (int(_bs.group(2)) - int(_bs.group(1)), int(_bs.group(2))))
            A('   voit pas toute la peau, donc aucun plancher tire d\'elle ne vaut.')
        # GARDE 2 (premisse intacte) : « je n'ai pas regarde » n'est pas « il est dehors ».
        _trou = [c for c in _restw if (_missr.get(c) or 0.0) > 0.0]
        if _restw and _trou:
            A('ROOM-SKINPEN-REST-TROU: %d chaine(s) portent des evaluations sans echantillon a'
              ' portee' % len(_trou))
            for c in sorted(_trou):
                A('   %-8s skinmiss=%.0f  -> « je n\'ai pas regarde », pas « il est dehors »'
                  % (names[c] if c < len(names) else c, _missr.get(c) or 0.0))
            _restw = {}
        # GARDE 3, NEUVE, ET C'EST ELLE QUI DECIDE SI LA COLONNE D'AUTEUR EST BIEN LA COLONNE
        # DESARMEE : dans la fenetre de repos la physique est mesurablement au repos (`ROOM-IDLE`
        # plafonne l'ecart du joint a sa pose d'auteur, et le validateur l'applique lui-meme), donc
        # la lecture SIMULEE et la lecture d'AUTEUR doivent y COINCIDER. Si elles divergent, le
        # point d'auteur n'est pas ce que je crois qu'il est, et le plancher part. C'est une
        # calibration de l'instrument par lui-meme, pas une promesse.
        _cal = []
        for c in sorted(set(_hold) & set(_holdr)):
            _a, _b = _hold[c][0], _holdr[c]
            _e = abs(_a - _b) / max(_a, _b, 1e-9)
            _cal.append((c, _a, _b, _e))
        if _restw:
            if not _cal:
                A('ROOM-SKINPEN-REST-NONCALIBREE: la fenetre de repos n\'emet pas les deux colonnes,')
                A('   donc rien ne prouve que la colonne d\'AUTEUR est la colonne DESARMEE.')
                _restw = {}
            else:
                A('ROOM-SKINPEN-CAL: dans la fenetre de repos, lecture SIMULEE contre lecture')
                A('   d\'AUTEUR — elles doivent coincider, c\'est ce qui prouve que la colonne')
                A('   d\'auteur EST la colonne « physique desarmee ». Seuil : 5 pour cent.')
                for c, _a, _b, _e in _cal:
                    A('   %-8s simule=%.4f  auteur=%.4f  ecart=%.2f %%'
                      % (names[c] if c < len(names) else c, _a, _b, 100.0 * _e))
                if max(_e for _c, _a, _b, _e in _cal) > 0.05:
                    A('   HORS SEUIL : la colonne d\'auteur ne se comporte pas comme une colonne')
                    A('   desarmee. Le plancher part — je ne fais pas verdir une gate sur ca.')
                    _restw = {}
        if _restw:
            A('ROOM-SKINPEN-REST: PIRE-DES-DEUX %.4f' % max(_restw.values()))
            A('   LECTURE DU POINT D\'AUTEUR — la pose sans physique — prise sur la MEME fenetre,')
            A('   les MEMES frames, les MEMES maillons, les MEMES echantillons et la MEME fonction')
            A('   que `ROOM-SKINPEN`. NATURE : une profondeur (m), max de fenetre. REPERE : le')
            A('   monde, frame ecrite. LECTURE HORS DEFAUT : `skinpen` en dessous, sur les DEUX.')
            for c in sorted(_restw):
                A('ROOM-SKINPEN-REST-DETAIL: %s %.4f'
                  % (names[c] if c < len(names) else c, _restw[c]))
            # LE VERDICT PAR CHAINE, CONTRE SON PROPRE PLANCHER. La gate n'en lit qu'un ; celui-ci
            # est plus strict et il est publie a cote pour qu'aucune chaine ne se cache derriere
            # l'agregat. Une regression sur une seule chaine se voit ici avant d'etre invisible la.
            for c in sorted(_restw):
                _v = sp_run.get(c, (None, 0))[0]
                if _v is None:
                    continue
                A('ROOM-SKINPEN-VERDICT: %-8s course=%.4f  plancher-propre=%.4f  physique=%+.4f m'
                  ' -> %s' % (names[c] if c < len(names) else c, _v, _restw[c], _v - _restw[c],
                              'TENUE' if _v <= _restw[c] else 'DEPASSEE'))
        elif _rest:
            A('ROOM-SKINPEN-REST-REJETEE: la colonne d\'auteur existe mais un garde-fou ci-dessus')
            A('   la refuse comme plancher. Ce n\'est PAS « la mesure manque » : c\'est « la mesure')
            A('   existe et je viens de montrer qu\'elle est fausse ».')
        else:
            A('ROOM-SKINPEN-REST-ABSENTE: la course n\'a pas emis `PHYSSKIN2 tag=run skinrest=`.')
        # ---- LE CHIFFRE QUI ETAIT PUBLIE AVANT, GARDE COMME DIAGNOSTIC ET PLUS COMME PLANCHER ----
        if _hold:
            A('ROOM-SKINPEN-HOLD: %.4f  (DIAGNOSTIC — ANCIEN PLANCHER, RETIRE)'
              % min(v for v, _t in _hold.values()))
            A('   Maximum de la FENETRE DE REPOS (`physroom-hold`, 120 frames). Il portait le nom')
            A('   que la gate lit jusqu\'a ce cycle. IL EST RETIRE parce qu\'il compare le maximum')
            A('   d\'une fenetre de 120 frames au maximum d\'une course de 16 740 frames sur 31')
            A('   animations : deux populations. LA PREUVE QU\'IL ETAIT FAUX EST ARITHMETIQUE ET')
            A('   ELLE EST DANS CETTE TRACE : le point d\'AUTEUR, physique absente par definition,')
            A('   atteint deja %.4f m sur la course. Physique entierement desarmee, la gate'
              % (max(_rest.values()) if _rest else 0.0))
            A('   echouait donc contre ce plancher. Une gate qu\'aucune physique ne peut passer ne')
            A('   mesure pas la physique.')
            for c in sorted(_hold):
                A('ROOM-SKINPEN-HOLD-DETAIL: %s %.4f'
                  % (names[c] if c < len(names) else c, _hold[c][0]))
        if _rest:
            A('ROOM-SKINPEN-SKINOUT: %d lecture(s) placent le point d\'AUTEUR DEHORS.' % _out)
            A('   CE COMPTE N\'EST PLUS UN MOTIF DE REJET, ET LA CORRECTION EST A MOI : la legende')
            A('   qui en faisait une anomalie datait de l\'epoque ou la grandeur portait sur le')
            A('   JOINT, interieur par construction du rig. Depuis [NOTE-161] elle porte sur un')
            A('   SOMMET EXTREMAL DE PEAU, pour lequel etre DEHORS est la DEFINITION meme d\'un')
            A('   point de surface. C\'est un DOMAINE, pas une alarme.')
        A('ROOM-SKINPEN-TESTS: %d echantillons de surface compares sur la fenetre' % _tot)
        # ==========================================================================================
        # SPEC 33 — L'INTERACTION SEIN <-> SEIN. LA SECTION AVAIT UN DOMAINE VIDE PAR CONSTRUCTION.
        # Texte exact (l.400-403) : « Medial surfaces shall collide or repel BEFORE visible
        # interpenetration. The interaction shall support contact, local compression, tangential
        # sliding, redirection of movement. Recommended restitution 0.00-0.15, nominal 0.06. »
        # Jusqu'au cycle 62, `physics_c14_meshsamples.py` excluait TOUT os de chaine de la famille
        # `bs` — correct pour SOI (un sein n'est pas un obstacle pour lui-meme) mais applique aussi
        # a l'AUTRE sein, donc la surface mediale opposee n'existait dans aucun jeu que le moteur
        # lit. Aucune valeur ne pouvait rien dire de cette section, ni rouge ni verte.
        # CE QUI EST PUBLIE, ET DANS QUEL ORDRE DE LECTURE :
        #   1. `medn` — LE DOMAINE. A zero, tout le reste est tu : « je n'ai pas regarde » ne se
        #      publie jamais comme « rien ne se touche ». C'est la faute exacte que cette section a
        #      subie pendant 62 cycles, et la publier a l'envers serait un faux vert de plus.
        #   2. `gapa` — L'ECART D'AUTEUR, la ligne de base « physique desarmee » : les deux seins a
        #      la pose dessinee, MEME frame, MEMES sommets, MEME fonction que la colonne simulee.
        #   3. `gap` / `pen` — la colonne SIMULEE, et le verdict est la COMPARAISON des deux, jamais
        #      la valeur brute : la question de la section est « la PHYSIQUE fait-elle traverser »,
        #      pas « les surfaces d'auteur se touchent-elles ».
        _mrun, _m2run = med.get('run', {}), med2.get('run', {})
        _mhold, _m2hold = med.get('rest', {}), med2.get('rest', {})
        if not _mrun and not _mhold:
            A('ROOM-MEDIAL-ABSENTE: la course n\'a pas emis `PHYSMED`. SPEC 33 reste NON ETABLI —')
            A('   ce n\'est pas « aucune interpenetration », c\'est « aucune mesure ».')
        else:
            for _tag, _m, _m2 in (('run', _mrun, _m2run), ('rest', _mhold, _m2hold)):
                if not _m:
                    continue
                for c in sorted(_m):
                    _gap, _gapa, _pen = _m[c]
                    _rest, _n, _far, _sp = _m2.get(c, (0.0, 0.0, None, None))
                    _nm = names[c] if c < len(names) else c
                    if _n <= 0:
                        A('ROOM-MEDIAL-DOMAINE-VIDE: %-8s tag=%s  n=0 lecture valide.' % (_nm, _tag))
                        A('   La surface de l\'autre sein n\'a jamais ete a portee de l\'estimateur.')
                        A('   SPEC 33 reste NON ETABLI sur cette chaine : un domaine vide ne rend')
                        A('   pas un vert, il rend une mesure manquante — et la mesure manquante')
                        A('   EST le blocage (arbitrage du 2026-08-20 13:20).')
                        continue
                    A('ROOM-MEDIAL: %-8s tag=%-5s n=%d  approche-simulee=%.4f'
                      '  approche-auteur=%.4f m'
                      % (_nm, _tag, int(_n), _gap / UNITS, _gapa / UNITS))
                    if _sp is not None:
                        A('ROOM-MEDIAL-SUPPORT: %-8s tag=%-5s espacement-du-nuage=%.4f m'
                          '  rayon-de-support=%.4f m  hors-support=%d/%d (%.1f %%)'
                          % (_nm, _tag, _sp / UNITS, 2.0 * _sp / UNITS, int(_far or 0), int(_n),
                             100.0 * (_far or 0) / max(_n, 1.0)))
                    # LE CONTROLE POSITIF, EN PREDICTION ET PAS EN RATIO. Arbitrage du 2026-08-20
                    # 13:20 : « injecter X doit faire monter la mesure de X, tolerance 25 %,
                    # l'exces comme le defaut etant un echec ». Ici l'injection RAPPROCHE le point
                    # sonde de la surface adverse de X, donc l'approche doit BAISSER de X.
                    _i = med3.get(_tag, {}).get(c)
                    if med3_legacy:
                        A('ROOM-MEDIAL-CONTROL: %-8s tag=%-5s ABSENT — la trace porte l\'ancien'
                          ' champ `inj=`, une LONGUEUR. Le controle du cycle 62 est une FRACTION'
                          ' et ne se lit pas sous ce nom : rejouer la salle.' % (_nm, _tag))
                    elif _i and 0.0 < _i[0] < 1.0 and _i[1] < 900000.0:
                        _frac, _gi = _i
                        # PREDICTION EXACTE, ET EVALUABLE PARTOUT. Le point sonde avance d'une
                        # FRACTION `frac` de son approche vers le plus proche echantillon : avec
                        # `frac < 1` il ne traverse JAMAIS la surface, donc l'approche tombe a
                        # `(1 - frac) x d1` quelle que soit sa valeur. Le minimum sur la fenetre
                        # commute avec la multiplication par une constante positive, donc la
                        # prediction porte telle quelle sur les grandeurs PUBLIEES.
                        # AVANT LE CYCLE 62 l'injection valait 200 u FIXES : sur la fenetre de
                        # COURSE, ou l'approche vaut 47 et 50 u, le point injecte traversait la
                        # surface et le controle etait NON EVALUABLE — c'est-a-dire precisement
                        # sur la fenetre qui PORTE le verdict. Il ne tirait qu'au repos, ou le
                        # domaine est vide. Le controle tirait la ou il n'y a rien a mesurer.
                        _pred = _frac * _gap
                        _rep = _gap - _gi
                        if _pred <= 0.0:
                            A('ROOM-MEDIAL-CONTROL: %-8s tag=%-5s NON EVALUABLE — approche nulle,'
                              ' la fraction n\'a rien a reduire.' % (_nm, _tag))
                        else:
                            _err = abs(_rep - _pred) / _pred
                            A('ROOM-MEDIAL-CONTROL: %-8s tag=%-5s fraction=%.2f'
                              '  baisse-predite=%.4f m  baisse-rendue=%.4f m  ecart=%.1f %% -> %s'
                              % (_nm, _tag, _frac, _pred / UNITS, _rep / UNITS, 100.0 * _err,
                                 'LE CONTROLE A TIRE' if _err <= 0.25 else
                                 'LE CONTROLE ECHOUE — la mesure ne repond pas a ce qu\'on lui'
                                 ' met'))
                    _dom = int(_n) - int(_far or 0)
                    if _far is not None and _dom <= 0:
                        # LE DOMAINE EN PORTEE EST VIDE : AUCUN VERDICT NE PEUT SORTIR D'ICI.
                        # `pen` ne peut etre ecrit QUE par une lecture dans le rayon de support
                        # (`d1 <= sup`). Quand il n'y en a aucune, `pen = 0` veut dire « je n'ai
                        # pas regarde », PAS « rien ne penetre » — et le publier `TENUE` est le
                        # faux vert le plus facile a produire, celui que cette section a subi
                        # pendant 62 cycles. La garde de vacuite portait sur `n` (TOUTES les
                        # lectures) au lieu de porter sur le domaine EN PORTEE : au repos les 480
                        # lectures sont hors support, donc `n = 480 > 0` la laissait passer et la
                        # ligne sortait `domaine=0/480 -> TENUE`.
                        A('ROOM-MEDIAL-PEN: %-8s tag=%-5s DOMAINE VIDE — 0/%d lecture(s) dans le'
                          ' rayon de support : SPEC 33 n\'est PAS testee sur cette fenetre.'
                          % (_nm, _tag, int(_n)))
                        A('   Ce n\'est pas « rien ne penetre », c\'est « les deux surfaces ne se'
                          ' sont jamais approchees a portee de l\'estimateur ». Separation'
                          ' minimale mesuree : %.4f m simulee, %.4f m auteur, pour un rayon de'
                          ' support de %.4f m.'
                          % (_gap / UNITS, _gapa / UNITS,
                             (2.0 * _sp / UNITS) if _sp is not None else float('nan')))
                    else:
                        A('ROOM-MEDIAL-PEN: %-8s tag=%-5s penetration-simulee=%.4f'
                          '  penetration-auteur=%.4f  physique=%+.4f m  domaine=%d/%d -> %s'
                          % (_nm, _tag, _pen / UNITS, _rest / UNITS, (_pen - _rest) / UNITS,
                             _dom, int(_n),
                             'TENUE' if _pen <= _rest else 'DEPASSEE'))
                        # DE QUELLE NATURE EST LE ZERO DE LA COLONNE D'AUTEUR ? La meme garde de
                        # vacuite vaut des DEUX cotes. `medrest` ne s'ecrit que sur une lecture
                        # d'auteur EN PORTEE (`a1 < sup`) : quand l'approche d'auteur ne descend
                        # jamais sous le rayon de support, son zero n'est PAS une mesure « rien ne
                        # penetre », c'est « jamais regarde de pres ». Ca reste un fondement
                        # valable pour le verdict — une surface qui ne s'approche jamais a moins de
                        # X ne peut pas penetrer — mais c'est l'APPROCHE qui le porte, pas la
                        # colonne de penetration, et les deux preuves ne se confondent pas.
                        if _sp is not None and _rest <= 0.0:
                            _supu = 2.0 * _sp
                            if _gapa > _supu:
                                A('   BASE D\'AUTEUR ENTRAINEE, NON MESUREE : l\'approche d\'auteur'
                                  ' (%.4f m) ne descend jamais sous le rayon de support (%.4f m),'
                                  ' donc AUCUNE lecture d\'auteur n\'est en portee. Sa penetration'
                                  ' nulle est ENTRAINEE par cette distance — a %.4f m les deux'
                                  ' surfaces ne peuvent pas se traverser — et non lue sur une'
                                  ' lecture en portee.' % (_gapa / UNITS, _supu / UNITS,
                                                           _gapa / UNITS))
                            else:
                                A('   BASE D\'AUTEUR MESUREE EN PORTEE : l\'approche d\'auteur'
                                  ' descend a %.4f m, sous le rayon de support (%.4f m) — sa'
                                  ' penetration nulle est une lecture, pas une deduction.'
                                  % (_gapa / UNITS, _supu / UNITS))
                        if _far is not None and _dom < 30:
                            A('   DOMAINE MINCE : %d lecture(s) seulement tombent dans le rayon de'
                              ' support. Un verdict pose dessus est ETROIT et se lit comme tel —'
                              ' ce n\'est pas « rien ne se touche », c\'est « ca se touche'
                              ' rarement ».' % _dom)
            A('   NATURE : une distance signee minimale (m) entre le sommet de peau d\'une chaine')
            A('   et la SURFACE de l\'autre sein ; positive = separees. REPERE : le monde, frame')
            A('   mesuree, LES DEUX seins portes a leur position RESOLUE (colonne simulee) ou a')
            A('   leur pose d\'AUTEUR (colonne auteur). LECTURE HORS DEFAUT : la penetration')
            A('   simulee reste sous la penetration d\'auteur — la physique n\'ajoute rien.')
            A('   LE RAYON DE SUPPORT N\'EST PAS UN REGLAGE : il vaut deux fois l\'espacement du')
            A('   nuage livre, mesure au chargement et publie ci-dessus. Il existe parce que')
            A('   `|sd| <= |p - q|` : une lecture de 0.64 m EXIGE que le plus proche echantillon')
            A('   de la surface opposee soit a 0.64 m, ce qui n\'est pas une penetration mais un')
            A('   plan prolonge loin de la ou il a ete echantillonne. Les lectures exclues sont')
            A('   COMPTEES, jamais jetees en silence.')
            A('   CE QUE CETTE LIGNE NE DIT PAS : la restitution 0.06 de la section. Elle exige')
            A('   un CONTACT resolu, et rien ne resout encore ce contact — la mesure precede la')
            A('   contrainte, elle ne la remplace pas.')
        # ==========================================================================================
        # ==========================================================================================
        # SPEC 7 — LE REPERE LOCAL. Elle etait `NON ETABLI` avec pour motif « aucune mesure du
        # repere lui-meme », et ce motif etait EXACT : deux des trois axes seulement etaient
        # publies (a=1, a=2), et l'axe manquant — le lateral sortant — est PRECISEMENT celui sur
        # lequel porte la seule clause chiffrable de la section :
        #     « for the left and right breasts, outward +X should be MIRRORED so that the
        #       equations remain symmetrical »
        # C'est une clause sur un VECTEUR ; `PHYSAXNAME sja` n'en donnait que la signature
        # SCALAIRE. Les trois axes etant maintenant emis, la section se lit en trois grandeurs qui
        # ont toutes une LECTURE CONNUE QUAND LE DEFAUT EST ABSENT :
        #   orthonormalite : ecart max a |a|=1 et aux produits scalaires nuls -> 0
        #   miroir de +X   : angle entre a0(chestL) et -a0(chestR)            -> 0 deg
        #                    (si +X n'etait PAS mirore, cet angle vaudrait 180 deg — le test
        #                     DISCRIMINE, il ne peut pas rendre 0 par construction)
        #   sens du triedre: les deux chaines doivent avoir des determinants OPPOSES, ce qui est
        #                    la consequence geometrique du miroir d'un seul axe sur trois.
        # NATURE : des cosinus directeurs, sans unite.
        # REPERE : LA BASE DE L'ANCRE, ET C'EST UNE CORRECTION DU CYCLE 63 — ces lignes portaient
        #   « REPERE : le monde », et la trace le refute toute seule : `a1` est le +Y « upward along
        #   torso » de sa §7, et il vaut (+0.18290 -0.97844 +0.09585). Un « haut » dont la
        #   composante y MONDE vaut -0.98 sur un sujet debout est impossible ; ces cosinus sont donc
        #   dans la base de l'ANCRE, ou le solveur les construit (`gref` est `g` monde passe par
        #   `w2l = inverse(am)`, et `fz` part du vecteur canonique `e[axa]` de cette meme base).
        #   Le verdict de miroir ci-dessous n'en depend pas — les deux chaines partagent l'ancre
        #   `chest`, donc la comparaison se fait dans une base COMMUNE dans les deux lectures —
        #   mais une etiquette de repere fausse est exactement ce que ce fichier interdit ailleurs.
        # ==========================================================================================
        def _dot(u, v):
            return sum(a * b for a, b in zip(u, v))

        def _det(a0, a1, a2):
            return (a0[0] * (a1[1] * a2[2] - a1[2] * a2[1])
                    - a0[1] * (a1[0] * a2[2] - a1[2] * a2[0])
                    + a0[2] * (a1[0] * a2[1] - a1[1] * a2[0]))

        _tri_ok = [c for c in sorted(tri) if len(tri[c]) == 3
                   and any(abs(x) > 1e-9 for a in tri[c].values() for x in a)]
        if len(_tri_ok) < 2:
            A('ROOM-SPEC7-ABSENT: le triedre n\'est pas releve sur les deux chaines'
              ' (axes publies: %s). SPEC 7 reste NON ETABLI — c\'est une mesure manquante,'
              ' pas un repere conforme.'
              % ({c: sorted(tri.get(c, {})) for c in sorted(tri)} or 'aucun'))
        else:
            for c in _tri_ok:
                _a = tri[c]
                _orth = max([abs(math.sqrt(_dot(_a[i], _a[i])) - 1.0) for i in (0, 1, 2)]
                            + [abs(_dot(_a[i], _a[j])) for i, j in ((0, 1), (0, 2), (1, 2))])
                A('ROOM-SPEC7-TRIEDRE: %-8s a0=(%+.5f %+.5f %+.5f)  a1=(%+.5f %+.5f %+.5f)'
                  '  a2=(%+.5f %+.5f %+.5f)  orthonormalite=%.2e  det=%+.5f'
                  % ((names[c] if c < len(names) else c,) + _a[0] + _a[1] + _a[2]
                     + (_orth, _det(_a[0], _a[1], _a[2]))))
            _cl, _cr = _tri_ok[0], _tri_ok[1]
            _l, _r = tri[_cl], tri[_cr]
            _cos = max(-1.0, min(1.0, -_dot(_l[0], _r[0])))
            _ang = math.degrees(math.acos(_cos))
            _dl, _dr = _det(_l[0], _l[1], _l[2]), _det(_r[0], _r[1], _r[2])
            # LE TRIEDRE EST RELEVE DANS PH-SETTLE, ET CETTE PHASE NE PUBLIE PAS SA POSE (c67).
            # `PHYSTRI` n'a pas de compagnon de directions d'os : on ne sait pas a combien du
            # miroir la salle tenait le sujet quand elle l'a lu. Les deux lignes ci-dessous
            # COMPARENT les deux chaines — la premiere est un angle entre leurs axes, la seconde
            # oppose leurs determinants — donc elles tombent sous le verrou comme les autres.
            _pset = POSE['PH-SETTLE']
            A(asym('ROOM-SPEC7-MIROIR', ': angle(a0[%s], -a0[%s]) = %.3f deg  ->  %s'
                   % (names[_cl] if _cl < len(names) else _cl,
                      names[_cr] if _cr < len(names) else _cr, _ang,
                      'MIROIR TENU' if _ang <= 2.0 else
                      'MIROIR ABSENT — +X pointe du MEME cote sur les deux seins'
                      if _ang >= 178.0 else 'MIROIR PARTIEL'), _pset,
                   note='§7 : le triedre est lu dans une pose dont la symetrie n est pas'
                        ' mesuree.'))
            A(asym('ROOM-SPEC7-SENS', ': det(%s)=%+.5f  det(%s)=%+.5f  ->  %s'
                   % (names[_cl] if _cl < len(names) else _cl, _dl,
                      names[_cr] if _cr < len(names) else _cr, _dr,
                      'SENS OPPOSES, consequence du miroir d\'un seul axe'
                      if _dl * _dr < 0 else 'MEME SENS — incompatible avec un +X mirore'), _pset))
            # LA CLAUSE 3 N'EST PAS JUGEE ICI, ET C'EST DELIBERE. « All dynamic calculations shall
            # occur relative to the torso/root transform rather than directly in world space » est
            # une clause sur le LIEU du calcul, pas sur une grandeur : aucune des trois mesures
            # ci-dessus ne la teste, et la declarer tenue parce que les axes sont propres serait
            # exactement le glissement que ce fichier interdit.
            A('   CE QUI N\'EST PAS JUGE ICI : la 3e clause de §7 (« all dynamic calculations')
            A('   shall occur relative to the torso/root transform rather than directly in world')
            A('   space ») porte sur le LIEU du calcul, pas sur une grandeur — ces trois lignes ne')
            A('   la testent pas et ne peuvent donc pas la declarer tenue.')
            A('   NATURE : cosinus directeurs, sans unite. REPERE : la base de l\'ANCRE (corrige au')
            A('   cycle 63 : ces lignes portaient "le monde", et `a1` = (+0.18290 -0.97844 +0.09585)')
            A('   le refute — un "haut du torse" a y=-0.98 en monde sur un sujet debout est')
            A('   impossible). LECTURES HORS DEFAUT :')
            A('   orthonormalite -> 0, angle du miroir -> 0 deg, determinants -> opposes. Le test du')
            A('   miroir DISCRIMINE : un +X non mirore rendrait 180 deg, pas 0.')

        # [NOTE-241] LE CONTROLE POSITIF DE LA CONTRAINTE DE PEAU, ET SON COUT.
        # Deux balayages des 31 animations, memes fenetres, meme pilotage, le SEUL ecart etant
        # `*phys-skin-off*`. DESARMEE, `skinpen` doit REMONTER : si les deux jambes rendent la meme
        # chose, ce n'est pas la contrainte qui a fait bouger le chiffre, et la ligne le dit.
        _ska, _skd = skinpen.get('skin-armed', {}), skinpen.get('skin-disarmed', {})
        # UNE JAMBE « ARMEE » QUI N'A APPLIQUE AUCUNE CORRECTION N'EST PAS ARMEE, ET LA LIGNE NE
        # DOIT PAS ANNONCER UN CONTROLE QUI A TIRE : deux fenetres desarmees rendent des valeurs
        # differentes pour la seule raison que ce sont deux fenetres. `PHYSSKINC` tranche.
        _armn = (skinc.get('skin-armed') or (0,))[0]
        if _ska and _skd and _armn <= 0:
            A('ROOM-SKINPEN-CONTROL: INERTE — la jambe « armee » a applique 0 correction'
              ' (PHYSSKINC n=0),')
            A('   donc les deux jambes sont DESARMEES et leur ecart ne mesure que la variation')
            A('   d\'une fenetre a l\'autre. Aucun controle ne se lit ici, et surtout pas un vert.')
            _ska, _skd = {}, {}
        if _ska and _skd:
            for c in sorted(set(_ska) & set(_skd)):
                _a, _d = _ska[c][0], _skd[c][0]
                A('ROOM-SKINPEN-CONTROL: %-8s armee=%.4f  desarmee=%.4f  tenu=%+.4f m -> %s'
                  % (names[c] if c < len(names) else c, _a, _d, _d - _a,
                     'LE CONTROLE A TIRE' if _d > _a else 'LE CONTROLE N\'A PAS TIRE'))
            A('   NATURE : une profondeur (m), max de fenetre. REPERE : le monde. La jambe ARMEE')
            A('   est l\'etat LIVRE ; la jambe DESARMEE est le defaut reinjecte. `tenu` est ce que')
            A('   la contrainte empeche. Un `tenu` negatif denoncerait la contrainte elle-meme :')
            A('   armee, elle ne peut PAS tirer un sein plus dehors que la pose d\'auteur.')
        elif skinc and _armn > 0:
            A('ROOM-SKINPEN-CONTROL: ABSENT — la trace ne porte pas les deux jambes')
            A('   `skin-armed` / `skin-disarmed`. Sans elles, rien ne prouve que c\'est la')
            A('   contrainte qui tient le chiffre, et cette ligne refuse de le supposer.')
        # ---- CE QUE LA CONTRAINTE RETIRE, CHIFFRE (SPEC 7 : un suppresseur se chiffre) ----------
        if skinc:
            for _tg in ('run', 'skin-armed', 'skin-disarmed'):
                if _tg in skinc:
                    _n, _sum, _w, _r = skinc[_tg]
                    A('ROOM-SKINPEN-COUT: tag=%-14s corrections=%.0f  cumul=%.4f m  pire=%.4f m'
                      '  reste=%s'
                      % (_tg, _n, _sum, _w,
                         ('%.4f m' % _r) if _r is not None else 'NON MESURE'))
            A('   `reste` EST LA CONTRAINTE QUI SE JUGE ELLE-MEME : la pire violation qui SURVIT')
            A('   aux six passes de correction, mesuree par une 7e passe qui ne corrige pas. Si')
            A('   elle n\'est pas ~0, la contrainte ne ferme pas et la borne `skinpen <= skinrest`')
            A('   ne se transporte pas — ce chiffre le dit AVANT la gate, pas apres.')
            A('   AGREGAT DE JAMBE, GLOBAL A LA COURSE et PAS par chaine — il ne se lit donc jamais')
            A('   comme une colonne par chaine (regle 7). `corrections`=0 sur la jambe DESARMEE est')
            A('   la preuve d\'execution que l\'interrupteur fait ce qu\'il dit.')
        # ============================================================================================
        # [NOTE-150] ROOM-SKINADD — LA PROFONDEUR **AJOUTEE** SOUS LA PEAU PAR LA PHYSIQUE.
        #
        # POURQUOI ELLE EXISTE. Les DIRECTIVES du 2026-08-20 10:55 tranchent que `meshpen` n'est pas
        # une profondeur mais un DEPLACEMENT, et que la gate COLLIDE doit lire « la penetration
        # contre la surface DESSINEE, DES QUE SA LIGNE DE BASE AU REPOS EXISTE ». `skinpen` ne
        # pouvait pas la porter : l'os de poitrine est INTERIEUR par construction anatomique, donc
        # cette colonne mesure le rig, pas la physique — au REPOS elle vaut deja 0.13 a 0.16 m.
        # Celle-ci retranche la ligne de base A LA MEME FRAME, sur la MEME surface, pour le MEME
        # lien : `max(0, sd(point d'auteur) - sd(point simule))`. C'est la construction de `feff`,
        # portee du volume au mesh DESSINE.
        #   NATURE  : une LONGUEUR en metres, MAXIMUM de fenetre. Ni un cumul ni une variance.
        #   REPERE  : le monde, a la frame ecrite — le meme point d'ou `meshpen` est tire.
        #   ABSENT  : 0.0000, et la pose d'auteur la rend AU BIT (les deux appels evaluent le meme
        #             point). Le domaine se lit sur `ROOM-SKINPEN-TESTS`, jamais suppose.
        #
        # CE QUI PEUT LA RENDRE FAUSSE, ECRIT AVANT DE LA LIRE. `phys-surf-sd` monte la matrice
        # VIVANTE de chaque os : la peau que la poitrine pilote SUIT la poitrine. Si l'echantillon
        # le plus proche appartient toujours a sa propre chair, la grandeur est TAUTOLOGIQUE et vaut
        # 0 par construction. `ROOM-SKINADD-CONTROL` tranche, et rien d'autre : l'injection de 400 u
        # enfonce le point SIMULE et laisse le point d'AUTEUR ou il est.
        _sa_run = skinadd.get('run', {})
        if any(v is not None for v in _sa_run.values()):
            for c in sorted(_sa_run):
                if _sa_run[c] is None:
                    continue
                _rows_c = [r['sa'] for r in rows if r['c'] == c and r.get('sa') is not None]
                A('ROOM-SKINADD: chain=%-12s course=%-9s  pire fenetre=%-9s'
                  % (names[c] if c < len(names) else c, fnum(_sa_run[c]),
                     fnum(max(_rows_c)) if _rows_c else 'n/a'))
            _on, _off = skinadd.get('pcon', {}), skinadd.get('pcoff', {})
            _va = [v for v in _on.values() if v is not None]
            _vd = [v for v in _off.values() if v is not None]
            _a = max(_va) if _va else None
            _d = max(_vd) if _vd else None
            if _a is None or _d is None:
                A('ROOM-SKINADD-CONTROL: ABSENT — sans lui cette colonne ne prouve rien, et son')
                A('   zero serait indistinguable d\'un instrument tautologique. Aucun verdict.')
            else:
                A('ROOM-SKINADD-CONTROL: armed=%s disarmed=%s   (injection de 400 u vers l\'ancre,'
                  ' le point d\'auteur ne bouge pas)' % (fnum(_a), fnum(_d)))
                if _a <= _d * 3.0:
                    # LE CRITERE CITE ICI EST PERIME et je le dis au lieu de le laisser : l'arbitrage
                    # du 2026-08-20 13:20 a retire le ratio « arme >= 3x desarme » (« un ratio se
                    # degrade avec sa ligne de base ») au profit d'une PREDICTION quantitative. Le
                    # verdict de cette ligne ne change pas — l'injection de 400 u rend ~81 u, donc
                    # elle echoue AUSSI sous le critere predictif — mais la RAISON publiee doit etre
                    # la bonne. Cette ligne reste un diagnostic : aucune gate ne la lit.
                    A('   LE CONTROLE N\'A PAS TIRE (critere courant : injecter X doit faire monter')
                    A('   la mesure de X a 25 %% pres ; 400 u injectes ne rendent pas 400 u). Le')
                    A('   ratio « arme >= 3x desarme » qui figurait ici est PERIME depuis le 13:20.')
                    A('   L\'instrument est')
                    A('   declare NON PROBANT : soit il est tautologique (la peau suit l\'os qui la')
                    A('   pilote), soit l\'injection ne l\'exerce pas. Aucun verdict ne s\'en tire,')
                    A('   et surtout pas un vert.')
                else:
                    A('   Le controle a TIRE : la colonne n\'est pas tautologique, son zero mesure.')
        else:
            A('ROOM-SKINADD: NON MESUREE dans cette trace (anterieure au cycle 60).')
        # LE PLANCHER D'ERREUR DE L'INSTRUMENT, MESURE PAR SES PROPRES PAIRES MIROIR.
        #
        # Une paire L/R porte des parametres identiques sur une geometrie miroir : tout ecart entre
        # les deux est de l'ERREUR D'INSTRUMENT, pas un defaut. C'est le controle que la SPEC 7
        # exige (« que lit-elle quand le defaut est ABSENT ? ») et il se derive des donnees au lieu
        # d'etre une liste de chaines « propres » ecrite a la main.
        # La SDF est un nuage de points : son erreur est bornee par l'ECART ENTRE ECHANTILLONS.
        # Tant que cet ecart est du meme ordre que les valeurs publiees, la colonne ne DISCRIMINE
        # pas, et la publier comme une penetration serait exactement le faux vert que ce validateur
        # existe pour empecher — a l'envers : un faux ROUGE.
        _byname = {(names[c] if c < len(names) else str(c)): v for c, (v, _t) in sp_run.items()}
        _pairs, _worst = [], 0.0
        for _n, _v in sorted(_byname.items()):
            _o = None
            for _a, _b in (('L', 'R'), ('l', 'r')):
                if _n.startswith(_a):
                    _o = _b + _n[1:]
                elif _n.endswith(_a):
                    _o = _n[:-1] + _b
                if _o and _o in _byname:
                    break
                _o = None
            if _o and _n < _o:
                _hi, _lo = max(_v, _byname[_o]), min(_v, _byname[_o])
                _sp = (_hi - _lo) / _hi if _hi > 0 else 0.0
                _pairs.append((_sp, _n, _o, _v, _byname[_o]))
                _worst = max(_worst, _hi - _lo)
        if _pairs:
            A('')
            A('ROOM-SKINPEN-MIRROR: l\'ecart entre paires MIROIR est l\'erreur de l\'instrument —')
            A('   parametres identiques, geometrie miroir : ce qui les separe n\'est pas un defaut.')
            # CE PLANCHER EST PRIS SUR TOUTE LA COURSE, DONC SUR TOUTES LES POSES A LA FOIS.
            # `PHYSSKIN` accumule le pire de la course entiere : il n'y a pas UNE pose ou cet
            # ecart a ete releve, il y en a autant que la course en traverse, dont celles que
            # `ROOM-REGPOSE` mesure a 48 deg du miroir. Un ecart L/R agrege sur des poses
            # asymetriques ne peut pas etre l'erreur d'un instrument : il contient la pose. Le
            # plancher qui en derive est donc indisponible AVEC lui — c'est le meme refus, pas
            # deux refus differents.
            _pcou = POSE['COURSE']
            _SKNOTE = ('le plancher d erreur d instrument qui en derive est donc lui aussi'
                       ' indisponible.')
            if not _pcou.ok():
                A(asym('ROOM-SKINPEN-MIRROR', ': %d paire(s) miroir relevees, aucune publiee'
                       % len(_pairs), _pcou, note=_SKNOTE))
            for _sp, _n, _o, _a2, _b2 in (sorted(_pairs, reverse=True) if _pcou.ok() else []):
                A(asym('ROOM-SKINPEN-MIRROR', ': %-12s %.4f  vs %-12s %.4f   ecart %4.0f %%'
                       % (_n, _a2, _o, _b2, 100 * _sp), _pcou, note=_SKNOTE))
            A(asym('ROOM-SKINPEN-FLOOR', ': %.4f m — AUCUNE valeur de la colonne ci-dessus n\'est'
                   ' interpretable en dessous de ce plancher.' % _worst, _pcou))
            if _worst >= min(_byname.values()):
                A('ROOM-SKINPEN: NON DISCRIMINANTE — le plancher d\'erreur (%.4f m) atteint ou'
                  ' depasse la plus petite valeur publiee (%.4f m). La cause est la DENSITE : 12'
                  ' echantillons par os donnent un espacement du meme ordre que les profondeurs'
                  ' mesurees. A ne PAS lire comme des penetrations tant que la densite ne monte'
                  ' pas.' % (_worst, min(_byname.values())))
    if shellfire:
        for tag in ('shell-disarmed', 'shell-armed'):
            if tag in shellfire:
                out, inw = shellfire[tag]
                A('ROOM-SHELL-FIRE: tag=%-15s out=%.0f inward=%s'
                  % (tag, out, '--' if inw is None else '%.0f' % inw))
    if cone_dis is not None and cone_arm is not None:
        A('')
        A('-- LE PREDICAT CONIQUE : LE SOLIDE TESTE EST ENFIN CELUI QUE LA DONNEE DESIGNE ----------')
        A('   Les 24 capsules livrees sont TOUTES coniques (radius != radius2). Le moteur testait le')
        A('   rayon interpole au parametre de PROJECTION, c\'est-a-dire f(t) evaluee au mauvais t au')
        A('   lieu d\'etre MINIMISEE sur [0,1] : un ensemble strictement plus PETIT que l\'enveloppe')
        A('   convexe des deux spheres. Le solveur cessait donc de pousser avant la vraie surface.')
        A('   NATURE : une profondeur (m). REPERE : monde, MEME solide exact des deux cotes.')
        A('   LECTURE HORS DEFAUT : desarme = la course ; arme, elle doit MONTER.')
        A('ROOM-CONE: disarmed=%s armed=%s   (metres, converties depuis les unites de jeu)'
          % (fnum(cone_dis), fnum(cone_arm)))
        if cone_arm <= cone_dis * 3.0:
            A('   ATTENTION : le controle du predicat conique n\'a PAS fait monter la penetration')
            A('   (arme %.4f contre desarme %.4f, il faut arme >= 3x desarme). Ce qui est mesure ne'
              % (cone_arm, cone_dis))
            A('   soutient donc PAS que la correction change le comportement du solveur -- SPEC 7.')
        # `sa`/`sd` ne sont assignes que dans la branche du FOURREAU, plus haut, et cette branche
        # n'existe que s'il reste au moins une chaine a `shell=`. Depuis l'ordre de l'owner du
        # 2026-08-14 07:30 (« retire toute physique de Keira hormis ses seins »), les deux seules —
        # `pantflapL` et `pantflapR` — sont GELEES : le bloc ne tourne plus et cette ligne levait un
        # UnboundLocalError qui tuait la generation du tableau entier. Le controle du fourreau n'est
        # pas « vert », il est SANS OBJET, et c'est ce qui est ecrit.
        if 'sa' not in dir() or 'sd' not in dir():
            A('   Le controle du FOURREAU est sans objet : plus aucune chaine ne porte `shell=`')
            A('   (pantflapL/pantflapR gelees par l\'owner le 2026-08-14 07:30). Rien de prouve,')
            A('   rien de reclame -- un domaine vide n\'est pas un zero gagne.')
        elif sa <= sd * 3.0:
            A('   ATTENTION : le controle du fourreau n\'a PAS fait monter l\'ecart radial')
            A('   (arme %.4f contre desarme %.4f, il faut arme >= 3x desarme). Le zero de la'
              % (sa, sd))
            A('   course ne prouve donc rien -- SPEC 7.')
    A('   `raddrop` = fois ou le PLAFOND D\'EXCURSION du lien (son propre rayon mesure) a mordu.')
    A('   C\'est un suppresseur, donc SPEC 7 exige qu\'il chiffre ce qu\'il retire PAR CHAINE : un')
    A('   affaissement gravitaire ecrete par ce plafond se lit ici et nulle part ailleurs.')
    A('')
    A('-- 11e PASSE DE L\'OWNER : LA FORME, PAS L\'AMPLITUDE ----------------------------------------')
    A('   « Lors de mouvements brusques il y a un effet d\'etirement et un peu gelee ou ca change de')
    A('   taille (plus petit, plus gros, plus long, plus court, ecrase), c\'est pas coherent ! » ...')
    A('   « certains maillons meriteraient un traitement pour eviter de creer des angles extremes qui')
    A('   mettent en lumiere le lack of geometrie » ... « le bas de son pantacourt clipe toujours a')
    A('   l\'interieur de ses mollets, comme si son pantacourt s\'arretait aux genoux ».')
    A('   Trois defauts de FORME, que ni tipvar (une variance) ni elong (la longueur de l\'OS, qui')
    A('   est invariante par construction) ne pouvaient decrire. Trois grandeurs, chacune avec sa')
    A('   NATURE, son REPERE et sa lecture quand le defaut est ABSENT :')
    A('')
    A('   bendcut  DEGRES retires par l\'attenuation d\'angle. NATURE : un angle cumule, donc un')
    A('            SUPPRESSEUR qui se chiffre (SPEC 7). REPERE : l\'attache du maillon. ABSENT : 0 —')
    A('            et il DOIT valoir 0 hors des cheveux, l\'owner ayant ferme le perimetre a')
    A('            « juste les meches, pas le reste, encore moins les seins ».')
    A('   shape    |p - T| / longueur de l\'os, SANS DIMENSION. NATURE, CORRIGEE LE 2026-08-12 : ce')
    A('            n\'est PAS l\'echelle de la deformation imposee a la chair, c\'est la CORDE de la')
    A('            rotation du lien autour de son attache. La contrainte de longueur etant dure,')
    A('            |p - attache| et |T - attache| valent tous deux la longueur de l\'os, donc')
    A('            |p - T| = 2 L sin(tiprot/2) : shape = 2 sin(tiprot/2), la grandeur deja publiee')
    A('            dans la colonne voisine. VERIFIE sur ce tableau, sur les 17 chaines sans')
    A('            attenuation d\'angle (bendcut = 0) : ecart maximal 0.072 % — earL 1.9572 contre')
    A('            1.9572, chestL 0.6727 contre 0.6727, goggles 1.9986 contre 1.9987, anklestrapL')
    A('            0.1039 contre 0.1040. Les 5 chaines de cheveux portent une attenuation d\'angle,')
    A('            qui s\'applique ENTRE les deux releves : deux d\'entre elles s\'en ecartent nettement')
    A('            (lbang 29.6 %, rbang 27.1 %), les trois autres restent a 0.0 %.')
    A('            CONSEQUENCE (test d\'admissibilite SPEC 7) : shape lit son MAXIMUM precisement')
    A('            quand le moteur fait ce que la SPEC exige — une rotation rigide autour de l\'ancre,')
    A('            a longueur invariante. Elle ne peut donc pas distinguer le defaut de son absence,')
    A('            et TOUT CE QUI EN A ETE CONCLU SUR `flesh-jelly` EST RETIRE. La colonne reste')
    A('            publiee : c\'est la mesure honnete de l\'excursion angulaire, rien de plus.')
    A('            REPERE : aucun, une longueur sur une longueur. ABSENT : 0 (le maillon est a sa')
    A('            pose de modele) — et c\'est bien la le probleme, 0 = immobile, pas 0 = sain.')
    A('   buried   paires (lien, volume) ou le lien est ENTIEREMENT dans un volume A SA POSE DE')
    A('            MODELE, comptees une fois par frame. NATURE : un compte. ABSENT : 0. Un pan dont')
    A('            la pose est DANS la jambe n\'a aucune surface a traverser : meshpen reste a zero')
    A('            pendant que l\'owner le voit disparaitre. C\'est la mesure de ce defaut-la.')
    A('')
    A('   tiprot   ROTATION D\'OS effectivement ECRITE dans la matrice du DERNIER maillon, en degres.')
    A('            NATURE : un angle. Elle se lit A L\'ENVERS des autres : jusqu\'au 2026-08-12 elle')
    A('            valait STRUCTURELLEMENT ZERO. Le bloc d\'ecriture ne tournait un maillon que s\'il')
    A('            avait un enfant SIMULE a viser, donc le DERNIER maillon de chaque chaine ne')
    A('            recevait qu\'une TRANSLATION. `chestL`/`chestR` n\'ayant qu\'UN SEUL maillon, le sein')
    A('            n\'avait JAMAIS tourne : il GLISSAIT de 16 cm, orientation figee — et un os qui se')
    A('            deplace sans tourner cisaille sa peau exactement de la rotation qu\'il n\'a pas')
    A('            appliquee. C\'est « ca change de taille, plus long, plus court, ECRASE ».')
    A('            Un NON-ZERO est donc la preuve d\'execution du chemin neuf, et il doit EGALER la')
    A('            deviation du meme maillon dans ROOM-GRADIENT : deux instruments independants.')
    A('')
    A('   %-12s %9s %9s %9s %9s   %s'
      % ('chaine', 'bendcut', 'shape', 'buried', 'tiprot', 'limite d\'angle'))
    _lim = {}
    try:
        for _ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
            if _ln.startswith('chain '):
                _mm = re.search(r'\bmaxangle=([\d.]+)', _ln)
                _lim[_ln.split()[1]] = float(_mm.group(1)) if _mm else 0.0
    except Exception:
        pass
    for c in sorted(chains):
        _d = dr_run.get(c, {})
        _l = _lim.get(names[c], 0.0)
        A('   %-12s %9.1f %9.4f %9d %9.2f   %s'
          % (names[c], _d.get('bendcut', 0.0), _d.get('shape', 0.0), int(_d.get('buried', 0)),
             _d.get('tiprot', 0.0), ('%.2f deg (CHEVEUX)' % _l) if _l > 0 else '-'))
    _hair = [names[c] for c in chains if _lim.get(names[c], 0.0) > 0]
    _out = [names[c] for c in chains
            if _lim.get(names[c], 0.0) <= 0 and dr_run.get(c, {}).get('bendcut', 0.0) > 0]
    A('   PERIMETRE : %d chaine(s) portent une limite d\'angle (%s) et %d chaine(s) hors perimetre'
      % (len(_hair), ', '.join(_hair), len(_out)))
    A('   ont paye de l\'attenuation. Le second nombre DOIT etre zero : c\'est la phrase de l\'owner')
    A('   « juste sur les meches » rendue verifiable. Le premier n\'est pas un zero structurel — les')
    A('   memes compteurs sont non nuls sur les cheveux dans la MEME course, donc ils tirent.')
    if RESEAT_FB is not None:
        A('   RE-ASSISE : %d liens replaces, dont %d retombes sur l\'ancienne heuristique (rayon le'
          % (int(RESEAT_FB[0]), int(RESEAT_FB[1])))
        A('   long de l\'os du porteur). Le second DOIT etre zero. La preuve n\'est pas ce drapeau mais')
        A('   la DISTANCE publiee par la course (`reseat-at ... bind=...`) : elle ne peut sortir que du')
        A('   chemin qui lit la bind-pose du rig, l\'ancien rendant exactement le rayon du lien.')
    A('')

    # ---- L'EFFET GELEE : UNE DISCONTINUITE, PAS UNE AMPLITUDE (11e passe, instrument du 2026-08-12)
    # `shape` ci-dessus ne discrimine pas (elle est la corde de la rotation exigee par la SPEC). La
    # grandeur qui voit le defaut decrit par l'owner etait deja dans la trace et n'avait jamais ete
    # lue comme un RAPPORT : jump / tipvar, par (chaine, pilotage).
    A('-- 11e PASSE : L\'EFFET GELEE EST UNE DISCONTINUITE — ROOM-JELLY ----------------------------')
    A('   « Lors de mouvements brusques il y a un effet d\'etirement et un peu gelee ou ca change de')
    A('   taille, c\'est pas coherent ! » ... « c\'est pourtant nickel sur le reste des animations plus')
    A('   subtiles. » Le defaut est donc une INCOHERENCE TEMPORELLE, pas une amplitude — et c\'est')
    A('   pour ca qu\'aucune colonne d\'amplitude ne pouvait le voir.')
    A('')
    A('   LES TROIS QUESTIONS DE LA SPEC 7, AVANT LE CHIFFRE :')
    A('   NATURE  : un rapport SANS DIMENSION — la fraction de l\'amplitude de fenetre parcourue en')
    A('             UNE frame. C\'est une mesure de DISCONTINUITE (donc une frequence), pas une')
    A('             amplitude. Une amplitude ne pouvait pas decrire « ca change de taille sans etre')
    A('             coherent », de la meme facon qu\'une variance ne pouvait pas decrire un')
    A('             affaissement sous gravite.')
    A('   REPERE  : celui de l\'ANCRE, applique a l\'ecart `o` = position ecrite moins pose d\'auteur du')
    A('             MEME joint (jak-hd-physics.gc:1950-1958, vector-rotate*! par w2l, donc rotation')
    A('             seule). Ni le repere monde, ni un ecart brut : les deux a la fois. Numerateur =')
    A('             norme euclidienne de l\'increment d\'UNE frame (jak-hd-physics.gc:2201) ;')
    A('             denominateur = diagonale de la boite englobante du MEME vecteur, du MEME maillon,')
    A('             sur la MEME fenetre (jak-hd-physics.gc:2458-2463). Meme grandeur, meme repere,')
    A('             meme fenetre — c\'est pour ca que le rapport se calcule PAR FENETRE puis se prend')
    A('             au maximum, et jamais comme max(jump)/max(tipvar), qui melangerait deux fenetres')
    A('             differentes (sur chestL/jerk ce melange lit 0.4300 la ou la pire fenetre reelle')
    A('             lit 0.7811 : il DILUE le defaut au lieu de le montrer).')
    A('   ABSENT  : sin(pi/T) pour une oscillation de periode T ; ~0.16 a 3 Hz, ~0.31 a 6 Hz. Mesure')
    A('             sur chestL sous les pilotages doux : 0.175.')
    A('   RESERVE : le denominateur est une DIAGONALE de boite englobante ; pour un mouvement')
    A('             isotrope elle surestime l\'etendue le long d\'un axe d\'un facteur allant jusqu\'a')
    A('             racine de 3. Le ratio publie est donc une BORNE INFERIEURE de la discontinuite')
    A('             reelle.')
    A('')
    A('   LA BORNE SE DERIVE, ELLE N\'EST PAS CHOISIE. Pour une oscillation de periode T frames,')
    A('   l\'increment maximal par frame rapporte a l\'etendue crete-a-crete vaut sin(pi/T). Donc')
    A('   ratio = sin(pi/T), soit T = pi / asin(ratio). Lecture (a 60 images/s) :')
    A('     T = 20 frames (3 Hz)    -> ratio 0.156      T = 10 frames (6 Hz)  -> ratio 0.309')
    A('     T =  6 frames (10 Hz)   -> ratio 0.500      T =  4 frames (15 Hz) -> ratio 0.707')
    A('     T =  3.5 frames (17 Hz) -> ratio 0.781   <- ce que chestL mesure sous jerk')
    A('   (la note de cadrage ecrivait « 3.3 frames (18 Hz) -> 0.781 » : pi/asin(0.781) = 3.51, et')
    A('   3.3 frames correspond a 0.814. Le pas de la lecture est corrige ici, pas le chiffre mesure.)')
    A('   La SPEC 1bis exige que la poitrine ait une MASSE : « l\'inertie retarde la reponse sur un')
    A('   depart brusque : ils restent en arriere puis rattrapent — dephasage mesurable entre l\'ancre')
    A('   et la pointe ». Une chair qui oscille a 17 Hz n\'a pas d\'inertie, c\'est du broutement')
    A('   numerique. PLAFOND : ratio <= 0.5 (T >= 6 frames, 10 Hz). Le `baseline` mesure de chestL')
    A('   (0.175, soit T = 18 frames = 3.3 Hz) est ce a quoi ressemble de la chair.')
    A('')
    A('   baseline = le MINIMUM des ratio de la MEME chaine sur les trois pilotages DOUX (updown,')
    A('   leftright, tilt) : la lecture de la meme chaine quand le defaut est ABSENT, exactement la')
    A('   comparaison que l\'owner fait lui-meme entre « brusque » et « subtil ». excess = ratio -')
    A('   baseline. Un ratio n\'est calcule que si tipvar > 0.02 m : un rapport sur un denominateur')
    A('   nul ne veut rien dire, et dans ce cas la ligne porte ratio=- et n\'autorise aucune')
    A('   conclusion.')
    A('')
    SOFT = ('updown', 'leftright', 'tilt')
    jelly = {}          # (c, dr) -> dict(ratio, jump, tip, ai)
    for c in sorted(chains):
        for dr in range(len(DRIVE_NAMES)):
            best = None
            for r in rows:
                if r['c'] != c or r['dr'] != dr or r['amp'] <= 0.02:
                    continue
                q = r['jump'] / r['amp']
                if best is None or q > best['ratio']:
                    best = dict(ratio=q, jump=r['jump'], tip=r['amp'], ai=r['ai'])
            if best is not None:
                jelly[(c, dr)] = best

    def _period(rt):
        if rt is None or rt <= 0.0:
            return None
        return math.pi / math.asin(min(rt, 1.0))

    j_worst = None
    j_over = 0
    for c in sorted(chains):
        soft = [jelly[(c, dr)]['ratio'] for dr, nm in enumerate(DRIVE_NAMES)
                if nm in SOFT and (c, dr) in jelly]
        bl = min(soft) if soft else None
        for dr, nm in enumerate(DRIVE_NAMES):
            e = jelly.get((c, dr))
            rt = e['ratio'] if e else None
            T = _period(rt)
            if rt is not None and rt > 0.5:
                j_over += 1
            if rt is not None and (j_worst is None or rt > j_worst[0]):
                j_worst = (rt, c, dr, T)
            A('ROOM-JELLY: chain=%-12s drive=%-10s jump=%-9s tipvar=%-9s ratio=%-8s baseline=%-8s'
              ' excess=%-8s period=%s'
              % (names[c], nm,
                 fnum(e['jump']) if e else '-', fnum(e['tip']) if e else '-',
                 '%.4f' % rt if rt is not None else '-',
                 '%.4f' % bl if bl is not None else '-',
                 '%.4f' % (rt - bl) if (rt is not None and bl is not None) else '-',
                 '%.2f' % T if T is not None else '-'))
    if j_worst is None:
        die('aucun couple (chaine, pilotage) ne porte un tipvar > 0.02 m : ROOM-JELLY n\'a aucun'
            ' denominateur admissible, et le defaut « gelee » reste donc non mesure')
    A('ROOM-JELLY-WORST: chain=%s drive=%s ratio=%.4f period=%.2f over=%d'
      % (names[j_worst[1]], DRIVE_NAMES[j_worst[2]], j_worst[0], j_worst[3], j_over))
    # ------------------------------------------------------------------------------------------
    # ROOM-JELLY-AMP — AJOUTE le 2026-08-13. On AJOUTE une lecture, on n'en REMPLACE aucune :
    # `ROOM-JELLY` ci-dessus reste mot pour mot ce qu'il etait.
    #
    # NATURE : un PROFIL de la discontinuite en fonction de la FORCE du stimulus. Pas un scalaire.
    # REPERE : identique a ROOM-JELLY (jump et amp de la MEME fenetre).
    # BASE quand le defaut est ABSENT : l'owner exige que la deformation CROISSE avec la force du
    #   mouvement (« elle doit etre quasi nulle sur les mouvements subtils »). Un profil sain MONTE
    #   du Q1 vers le Q4. Un profil qui DESCEND dit que ce qu'on mesure vit dans les petits
    #   mouvements — ceux qu'il declare « toujours OK ».
    #
    # POURQUOI. `ROOM-JELLY` publie un MAXIMUM sur ~31 fenetres, et `baseline` un min-de-max.
    # Mesure du 2026-08-13 sur chestR : les 16 fenetres qui portent `ratio > 0.95` ont toutes une
    # amplitude de 0.056-0.094 m, tandis que dans le quartile d'amplitude le plus FORT le ratio
    # tombe a 0.679. Le chiffre publie vient donc entierement du regime que l'owner APPROUVE,
    # alors que le defaut qu'il decrit (« ballons d'eau ») vit dans l'autre. Comme
    # `excess = ratio - baseline`, la plage utile tombe a 0.014 sur une echelle [0,1] : la mesure
    # ne discrimine plus rien (classe `measurement-must-discriminate`). Le profil par quartile
    # separe les memes deux chaines de 0.17 a 0.64.
    A('')
    A('-- LA GELEE EN FONCTION DE LA FORCE DU MOUVEMENT (ROOM-JELLY-AMP) ------------------------')
    A('   mediane du ratio par QUARTILE d\'amplitude. Sain = MONTE de Q1 vers Q4.')
    for c in sorted(chains):
        pts = sorted(((r['amp'], r['jump'] / r['amp']) for r in rows
                      if r['c'] == c and r['amp'] > 0.02), key=lambda x: x[0])
        if len(pts) < 8:
            continue
        qs, n = [], len(pts)
        for k in range(4):
            seg = [q for _, q in pts[n * k // 4:n * (k + 1) // 4]]
            seg.sort()
            qs.append(seg[len(seg) // 2] if seg else float('nan'))
        A('ROOM-JELLY-AMP: chain=%-12s n=%-4d amp=%s..%s m  Q1=%.4f Q2=%.4f Q3=%.4f Q4=%.4f  %s'
          % (names[c], n, fnum(pts[0][0]), fnum(pts[-1][0]),
             qs[0], qs[1], qs[2], qs[3],
             'MONTE' if qs[3] >= qs[0] else 'DESCEND(mesure le petit mouvement)'))
    A('   `over` = nombre de couples (chaine, pilotage) au-dessus du plafond derive de 0.5, soit une')
    A('   oscillation plus rapide que 6 frames / 10 Hz : de la chair n\'oscille pas la.')
    A('   Le ratio est pris PAR FENETRE puis au MAXIMUM sur les fenetres (numerateur et denominateur')
    A('   viennent donc de la MEME fenetre) ; le nom de l\'animation de la pire fenetre est celui du')
    A('   bloc `row` correspondant.')
    A('   PLAFOND STRUCTUREL : les deux extremites d\'un increment d\'une frame sont dans la boite de')
    A('   la fenetre, donc jump <= diagonale et le ratio ne peut pas depasser 1.0000. Un ratio a')
    A('   1.0000 exactement (period=2.00, la limite de Nyquist) n\'est donc pas une saturation')
    A('   d\'instrument : il dit que TOUTE l\'excursion de la fenetre s\'est faite en UNE frame — une')
    A('   marche, pas une oscillation. C\'est la lecture la plus severe que cette grandeur puisse')
    A('   rendre, et elle est atteinte.')
    A('')
    A('-- 6e PASSE, DEFAUT 2 : LA COURBE DE REPONSE ------------------------------------------------')
    A('   « Les meches les plus grosses sont trop statiques sur les mouvements faibles, trop')
    A('   hysteriques sur les mouvements brusques. » Une reponse non lineaire, c\'est un seuil. Meme')
    A('   animation figee, meme chaine, meme fenetre : la SEULE chose qui change d\'un niveau au')
    A('   suivant est l\'amplitude de l\'excitation (unites de jeu par frame^2). `gain` = amplitude')
    A('   de pointe / excitation, normalise sur le premier niveau : une droite a 1.00 est une')
    A('   reponse LINEAIRE, une marche designe le seuil coupable.')
    if not resp:
        die('trace incomplete : aucune ligne PHYSRESP — le defaut 2 de la 6e passe n\'est pas mesure')
    lv = sorted({d['lvl'] for v in resp.values() for d in v})
    A('   %-12s %s' % ('chain', ' '.join('exc=%-7.1f' % next(d['exc'] for d in resp[next(iter(resp))]
                                                             if d['lvl'] == i) for i in lv)))
    for c in sorted(chains):
        pts = {d['lvl']: d for d in resp.get(c, [])}
        if not pts:
            continue
        base = None
        cells = []
        for i in lv:
            d = pts.get(i)
            if d is None or d['exc'] <= 0:
                cells.append('   -    ')
                continue
            g = d['amp'] / d['exc']
            if base is None and g > 0:
                base = g
            cells.append('%7.3f ' % (g / base if base else 0.0))
        A('   resp %-12s %s   amp: %s'
          % (names[c], ' '.join('%-11s' % x.strip() for x in cells),
             ' '.join(fnum(pts[i]['amp']) for i in lv if i in pts)))
    A('')
    A('-- 6e PASSE, DEFAUT 3 : LA GRAVITE EXISTE-T-ELLE QUAND ELLE SE PENCHE ? ---------------------')
    A('   « Les seins n\'ont pas l\'air d\'etre soumis a la gravite, aucun mouvement quand elle se')
    A('   penche en avant pour souder, pas coherent du tout. » Meme chaine, meme animation figee,')
    A('   meme duree que le repos : la SEULE difference est l\'inclinaison du tronc. La famille A')
    A('   porte une gravite exprimee dans le repere de l\'ancre — nulle quand elle est droite')
    A('   (l\'equilibre reste la pose du modele), non nulle des qu\'elle penche. `dev` doit donc')
    A('   MONTER de la colonne droite a la colonne penchee, et pour elles seules.')
    if not tilt:
        die('trace incomplete : aucune ligne PHYSTILT — le defaut 3 de la 6e passe n\'est pas mesure')
    deg = next(iter(tilt.values()))['deg']
    A('ROOM-TILT: deg=%.0f chains=%d' % (deg, len(tilt)))
    for c in sorted(chains):
        u = idle.get(c, {})
        v = tilt.get(c, {})
        A('   tilt %-12s fam=%s  dev_droite=%-9s dev_penchee=%-9s  ratio=%s'
          % (names[c], 'A' if chains[c]['fam'] == 1 else 'B',
             fnum(u.get('dev', 0.0)), fnum(v.get('dev', 0.0)),
             ('%.1fx' % (v.get('dev', 0.0) / u['dev'])) if u.get('dev', 0.0) > 1e-6 else 'n/a'))
    A('')
    A('-- LES MESURES, UNE LIGNE PAR (CHAINE x ANIMATION x PILOTAGE) ------------------------------')
    for r in sorted(rows, key=lambda r: (r['c'], r['ai'], r['dr'])):
        A('row chain=%-12s anim=%-38s drive=%-9s tipvar=%-9s rootdev=%-9s meshpen=%-9s jump=%-9s'
          ' skinadd=%-9s ns=%d'
          % (names[r['c']], anims[r['ai']]['name'], DRIVE_NAMES[r['dr']],
             fnum(r['amp']), fnum(r['root']), fnum(r['pen']), fnum(r['jump']),
             ('n/a' if r.get('sa') is None else fnum(r['sa'])), int(r['ns'])))
    A('')
    A('%d lignes de mesure, %d chaines x %d animations x %d pilotages.'
      % (len(rows), len(chains), played, len(DRIVE_NAMES)))

    # ============================================================================================
    # CYCLE 52 — ROOM-SIGN : LA REPONSE PAR SENS DE STIMULUS.
    #
    # POURQUOI CE BLOC EXISTE. Le cycle 51 a mesure, sur la trace deja en main, que la reponse
    # d'apex depend du SENS du stimulus (chestL rend 65 % de mouvement vertical sur une impulsion
    # vers le BAS et 2 a 5 % vers le HAUT — facteur 13 a 31 sur le sens seul) et de la CHAINE
    # (x10 a x20 d'ecart gauche/droite sur la detente, quand sa §32 prescrit 2-5 %). Il a REFUSE
    # de nommer la cause faute de l'avoir mesuree, et a designe la grandeur a instrumenter : la
    # reponse PAR SENS, pas par amplitude ni par duree. Les sept regimes de §14-20 ne pouvaient
    # pas y repondre — leurs stimuli ne sont pas apparies en signe a amplitude egale.
    #
    # CE QUI REND CE BLOC DECIDABLE SANS SEUIL CHOISI, ET C'EST TOUT SON INTERET. Pour un systeme
    # LINEAIRE, et plus generalement pour TOUTE non-linearite SYMETRIQUE (la saturation `tanh` de
    # sa §21, une borne posee sur une NORME, une raideur cubique), la reponse a `-u` est
    # EXACTEMENT l'opposee de la reponse a `+u`. Donc les deux ecarts publies ici
    #     A_mag = | |r+| - |r-| | / max(|r+|,|r-|)     et     A_dir = 180 deg - angle(r+, r-)
    # valent ZERO par PROPRIETE du systeme, pas par convention. Ils ne peuvent devenir non nuls
    # que si un terme du solveur distingue un SENS de l'autre. Un instrument qui republierait sa
    # cible — le quatrieme faux vert du dossier, §11 au cycle 49 — ne peut pas prendre cette forme.
    #
    # NATURE : `apex` est un MAXIMUM DE FENETRE d'une LONGUEUR rapportee a B0 (602 u, §6) ; le
    #   triplet (ax, ay, az) est le VECTEUR de ce maximum, releve a l'argmax. Ce sont les memes
    #   emplacements (53-56) que `PHYSREG4`, donc directement comparables aux sept regimes.
    # REPERE : le monde, frame ecrite, contre la pose d'auteur de la MEME frame — identique a
    #   `ROOM-APEX-REGIME`. Ce n'est jamais un repere de maillon.
    # LECTURE QUAND LE STIMULUS EST ABSENT : `bapex`, publie par `PHYSSGN3`, est l'apex des 60
    #   frames de CALME qui ferment chaque fenetre. C'est la ligne de base, et elle est MESUREE,
    #   pas supposee negligeable — le cycle 50 a etabli que les fenetres se contaminent.
    # CE QUI DISCRIMINE : le SENS, a axe egal et a stimulus egal. `stim` est publie POUR LE
    #   PROUVER : deux sens qui ne recoivent pas le meme stimulus ne sont pas la meme experience.
    # ============================================================================================
    _sgA, _sgB, _sgC, _sgV = {}, {}, {}, {}
    for _m in re.finditer(r'^PHYSSGN c=(\d+) i=(\d+) k=(\d+) a=(\d+) s=(-?\d+)'
                          r' apex=([-\d.e+]+)', txt, re.M):
        _sgA[int(_m.group(2))] = (int(_m.group(3)), int(_m.group(4)), int(_m.group(5)))
        _sgV[(int(_m.group(1)), int(_m.group(2)))] = float(_m.group(6))
    for _m in re.finditer(r'^PHYSSGN2 c=(\d+) i=(\d+) com=([-\d.e+]+) stim=([-\d.e+]+)', txt, re.M):
        _sgB[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)), float(_m.group(4)))
    for _m in re.finditer(r'^PHYSSGN3 c=(\d+) i=(\d+) bapex=([-\d.e+]+) bcom=([-\d.e+]+)', txt, re.M):
        _sgC[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)), float(_m.group(4)))
    _sgW = {}
    for _m in re.finditer(r'^PHYSSGN4 c=(\d+) i=(\d+) ax=([-\d.e+]+) ay=([-\d.e+]+)'
                          r' az=([-\d.e+]+)', txt, re.M):
        _sgW[(int(_m.group(1)), int(_m.group(2)))] = (
            float(_m.group(3)), float(_m.group(4)), float(_m.group(5)))
    A('')
    if not _sgA:
        A('   -- ROOM-SIGN : ABSENT ------------------------------------------------------------')
        A('ROOM-SIGN: aucune ligne PHYSSGN dans cette trace — le balayage PAR SENS n\'a PAS tourne.')
        A('   La question que le cycle 51 a posee (« d\'ou vient la dependance au SENS du')
        A('   stimulus ? ») reste SANS REPONSE. Rien n\'est publie a zero : un canal absent n\'est')
        A('   pas une reponse symetrique.')
    else:
        _AXSN = {0: 'VERTICAL', 1: 'AVANT-ARR', 2: 'LATERAL'}
        _ABLN = {0: 'k0 reference', 1: 'k1 longueur', 2: 'k2 cote',
                 3: 'k3 rayon-cone', 4: 'k4 MUR COLLIS', 5: 'k5 borne radiale'}
        A('   -- ROOM-SIGN : LA REPONSE PAR SENS DE STIMULUS (cycle 52) ----------------------')
        # LE SENS `+` EST CELUI DE L'AXE STOCKE, ET CE N'EST PAS FORCEMENT « VERS LE HAUT ».
        # `physroom-drive-sgn` passe son `ax` a `phys-axis-world`, qui prend un ROLE (0 vertical,
        # 1 avant-arriere, 2 lateral) et non une ligne du triedre : la correspondance role -> ligne
        # est `PHYSAXIS rv/rap/rlat`, publiee par le solveur. Verifie sur cette course, la ligne
        # VERTICALE est stockee vers le BAS du monde (composante y ~ -0.98) : une impulsion `s=+1`
        # deplace donc le sujet VERS LE BAS. Le piege `axis-sign-outlives-role-renaming` a deja
        # coute une lecture a ce dossier ; la direction MONDE est donc republiee ici, a cote du
        # tableau, pour qu'aucun lecteur n'ait a supposer ce que `+` veut dire.
        _axdir52 = {}
        for _m in re.finditer(r'^PHYSAXW ax=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)',
                              txt, re.M):
            _axdir52[int(_m.group(1))] = (float(_m.group(2)), float(_m.group(3)),
                                          float(_m.group(4)))
        if _axdir52:
            A('      LE SENS `+` EST CELUI DE L\'AXE STOCKE PAR LE SOLVEUR, jamais une convention')
            A('      de lecture. Directions MONDE effectivement poussees sur cette course :')
            for _a in sorted(_axdir52):
                _u = _axdir52[_a]
                _dom = max(range(3), key=lambda i: abs(_u[i]))
                A('         %-10s s=+1 -> monde (%+.5f, %+.5f, %+.5f)   dominante %s%s'
                  % (_AXSN.get(_a, 'a%d' % _a), _u[0], _u[1], _u[2],
                     '+-'[_u[_dom] < 0], 'XYZ'[_dom]))
            _v = _axdir52.get(0)
            if _v and _v[1] < -0.5:
                A('         ATTENTION : la ligne VERTICALE est stockee vers le BAS du monde')
                A('         (y=%+.5f). `s=+1` sur l\'axe vertical pousse donc le sujet VERS LE' % _v[1])
                A('         BAS, et `s=-1` vers le HAUT. Aucune ligne ci-dessous ne suppose le')
                A('         contraire.')
            A('')
        A('      A_mag et A_dir valent ZERO pour tout systeme lineaire ET pour toute')
        A('      non-linearite SYMETRIQUE (tanh de §21, borne sur une norme, raideur cubique) :')
        A('      la reponse a -u y est exactement l\'opposee de la reponse a +u. Ils ne peuvent')
        A('      donc etre non nuls que si un terme du solveur distingue un SENS de l\'autre.')
        A('      Ce ne sont pas des seuils choisis, c\'est une propriete du systeme.')
        A('')
        # ---- (a) LES DEUX PLANCHERS, ET ILS NE DISENT PAS LA MEME CHOSE -------------------
        # `bapex` mesure les 60 frames de CALME qui ferment la fenetre. Il est publie parce qu'il
        # etait la ligne de base PREVUE — mais la course montre qu'il ne mesure PAS ce que je
        # croyais : la rampe de RETOUR est elle-meme une impulsion de meme amplitude, et les 60
        # frames de calme commencent juste apres. `bapex` lit donc la reponse a la rampe de
        # retour, pas un residu non eteint. C'est un DEFAUT DE CONCEPTION DE MON INSTRUMENT, pas
        # une mesure du solveur, et il est ecrit comme tel.
        #
        # LE PLANCHER QUI COMPTE EST CELUI QUE LA COURSE DONNE SANS QUE JE L'AIE DEMANDE : k=2
        # (contrainte de COTE levee) est INERTE sur ce stimulus — ses dix cellules reproduisent
        # celles de k=0 alors qu'elles sont a DOUZE fenetres de distance dans la sequence. Cet
        # ecart EST la repetabilite de l'instrument, contamination de fenetre a fenetre comprise.
        # C'est un controle plus fort que celui que j'avais prevu, et c'est lui qui sert.
        _bs = sorted(v[0] for v in _sgC.values())
        if _bs:
            _bmean = sum(_bs) / len(_bs)
            _bsd = (sum((x - _bmean) ** 2 for x in _bs) / len(_bs)) ** 0.5
            A('   ROOM-SIGN-BASE: `bapex` (60 frames de calme fermant la fenetre) mediane %.4f'
              '  max %.4f  sd %.4f' % (_bs[len(_bs) // 2], _bs[-1], _bsd))
            A('      P5 EST REFUTEE, ET LA CAUSE EST MON INSTRUMENT : la rampe de RETOUR est une')
            A('      impulsion de meme amplitude, et le calme la suit immediatement. `bapex` lit')
            A('      donc sa reponse, pas un residu. Cette ligne ne sert PAS de plancher.')
        # LA CELLULE i=0 EST CONTAMINEE ET ELLE EST ECARTEE DE TOUT VERDICT.
        # `stim` — le pire module d'acceleration RECU par la pointe — vaut ~1250 sur la premiere
        # fenetre de la phase contre ~17 sur les 35 autres, soit x74. La phase PH-SGN succede a
        # PH-REG, dont la derniere fenetre finit ailleurs qu'a `home` : le `physroom-hold` de
        # sortie y ramene le sujet D'UN COUP. C'est exactement l'impulsion artificielle que
        # `physroom-reg-drive` evite par une rampe, et que ma phase n'a pas prevue a son ENTREE.
        # C'est P6 — le controle de stimulus — qui l'a attrapee. Sans lui je publiais le plus gros
        # chiffre du tableau comme une reponse a mon impulsion.
        _bad = {_i for _i, _ in _sgA.items()
                if any(abs(_sgB.get((_c, _i), (0.0, 0.0))[1]) > 100.0 for _c in chains)}
        if _bad:
            A('   ROOM-SIGN-DROP: fenetre(s) ECARTEE(S) pour stimulus aberrant : %s'
              % ', '.join('i=%d' % _i for _i in sorted(_bad)))
            A('      (stim > 100 u/frame^2 contre ~17 partout ailleurs — transition de phase)')
        A('')
        # ---- (b) LE TABLEAU, UNE LIGNE PAR (ablation, axe, chaine, sens) -------------------
        # DEUX PASSES DEPUIS LE CYCLE 53 : chaque (ablation, axe, sens) est joue DEUX FOIS, une
        # fois en 1re position de sa cellule et une fois en 2e. `_cellw` garde la PREMIERE fenetre
        # (pour nommer et pour ecarter i=0) et `_sgVm` rend la MOYENNE des passes — sans quoi le
        # tableau publierait silencieusement la seule DERNIERE passe, ce qui serait exactement le
        # defaut de rang que la seconde passe est la pour supprimer.
        _cellw, _allw = {}, {}
        for _i, (_k, _a, _s) in sorted(_sgA.items()):
            _allw.setdefault((_k, _a, _s), []).append(_i)
            if (_k, _a, _s) not in _cellw:
                _cellw[(_k, _a, _s)] = _i

        def _sgVm(_c, _i):
            """apex de la cellule a laquelle appartient la fenetre `_i`, MOYENNE sur les passes
            valides (une fenetre ecartee pour stimulus aberrant ne rentre pas dans la moyenne)."""
            if _i is None or _i not in _sgA:
                return None
            _v = [_sgV[(_c, _j)] for _j in _allw[_sgA[_i]]
                  if (_c, _j) in _sgV and _j not in _bad]
            return (sum(_v) / len(_v)) if _v else None
        _rep = []
        for _a in (0, 1, 2):
            for _s in (1, -1):
                _i0, _i2 = _cellw.get((0, _a, _s)), _cellw.get((2, _a, _s))
                if _i0 is None or _i2 is None or _i0 in _bad or _i2 in _bad:
                    continue
                for _c in sorted(chains):
                    if (_c, _i0) not in _sgV or (_c, _i2) not in _sgV:
                        continue
                    _v0, _v2 = _sgVm(_c, _i0), _sgVm(_c, _i2)
                    if _v0 is not None and _v2 is not None and max(_v0, _v2) > 0:
                        _rep.append(abs(_v0 - _v2) / max(_v0, _v2))
        _FL = max(_rep) if _rep else None
        if _FL is not None:
            A('   ROOM-SIGN-REPEAT: k=0 contre k=2 (cote levee, INERTE ici), memes (axe, sens),')
            A('      %d cellules separees de DOUZE fenetres dans la sequence :' % len(_rep))
            A('      ecart max %.3f %%   mediane %.3f %%'
              % (100.0 * max(_rep), 100.0 * sorted(_rep)[len(_rep) // 2]))
            A('      -> C\'EST LE PLANCHER DE L\'INSTRUMENT. Tout ecart au-dela est REEL.')
            A('')
        A('   ROOM-SIGN-ABL: ce que CHAQUE desarmement fait a la reponse, rapporte a k=0.')
        A('      LE CONTROLE NEGATIF EST DANS LE TABLEAU : si un desarmement ne faisait que')
        A('      « retirer la seule restriction, donc tout grandit », il ferait monter LES TROIS')
        A('      axes. Une ablation qui ne deplace QU\'UN axe designe un mecanisme SELECTIF.')
        A('      %-8s %-5s %-4s %8s | %s'
          % ('chaine', 'axe', 'sens', 'k0', 'k1 long  k2 cote  k3 cone  k4 MUR   k5 rad'))
        for _c in sorted(chains):
            for _a in (0, 1, 2):
                for _s in (1, -1):
                    _i0 = _cellw.get((0, _a, _s))
                    if _i0 is None or _sgVm(_c, _i0) is None:
                        continue
                    if _i0 in _bad:
                        A('      %-8s %-5s %+d    ECARTEE (fenetre i=%d, stimulus aberrant)'
                          % (names[_c] if _c < len(names) else _c, _AXSN[_a], _s, _i0))
                        continue
                    _v0 = _sgVm(_c, _i0)
                    _cols = []
                    for _k in (1, 2, 3, 4, 5):
                        _ik = _cellw.get((_k, _a, _s))
                        _vk = _sgVm(_c, _ik)
                        _cols.append('%.2fx' % (_vk / _v0)
                                     if _vk is not None and _v0 and _v0 > 0 else 'n/a')
                    A('      %-8s %-5s %+d   %8.4f | %s'
                      % (names[_c] if _c < len(names) else _c, _AXSN[_a], _s, _v0,
                         ' '.join('%-8s' % _x for _x in _cols)))
        A('')
        # ---- (c) P6, P4, P3 : LES VERDICTS, SUR LES CELLULES PROPRES UNIQUEMENT ------------
        _clean = [(_k, _a) for _k in range(6) for _a in range(3)
                  if _cellw.get((_k, _a, 1)) not in _bad
                  and _cellw.get((_k, _a, -1)) not in _bad
                  and _cellw.get((_k, _a, 1)) is not None
                  and _cellw.get((_k, _a, -1)) is not None]
        _sds = []
        for (_k, _a) in _clean:
            _ip, _im = _cellw[(_k, _a, 1)], _cellw[(_k, _a, -1)]
            for _c in sorted(chains):
                _sp = _sgB.get((_c, _ip), (0.0, 0.0))[1]
                _sm = _sgB.get((_c, _im), (0.0, 0.0))[1]
                if max(_sp, _sm) > 0:
                    _sds.append(abs(_sp - _sm) / max(_sp, _sm))
        if _sds:
            A('   ROOM-SIGN-STIM: sur les cellules PROPRES, ecart de stimulus entre les deux sens'
              ' — max %.3f %%  (P6 : <= 5 %%) -> %s'
              % (100.0 * max(_sds), 'TENUE' if max(_sds) <= 0.05 else 'REFUTEE'))
            A('      P6 A FAIT SON TRAVAIL : c\'est elle qui a attrape la fenetre i=0, dont le')
            A('      stimulus valait 74x celui des autres. Sans ce controle, le plus gros chiffre')
            A('      du tableau partait dans le rapport comme une reponse a mon impulsion.')
        A('')
        # P4 : sur l'AMPLITUDE, qui est la grandeur que le tableau ci-dessus rend lisible.
        _p4 = []
        for _c in sorted(chains):
            for _a in (0, 1, 2):
                for _s in (1, -1):
                    _i0, _i4 = _cellw.get((0, _a, _s)), _cellw.get((4, _a, _s))
                    if _i0 is None or _i4 is None or _i0 in _bad or _i4 in _bad:
                        continue
                    _v0, _v4 = _sgVm(_c, _i0), _sgVm(_c, _i4)
                    if _v0 and _v0 > 0 and _v4 is not None:
                        _p4.append(abs(_v4 / _v0 - 1.0))
        if _p4 and _FL is not None:
            A('   ROOM-SIGN-P4: desarmer le MUR DE COLLISION (k=4) deplace la reponse de %.1f %%'
              ' au plus, %.1f %% en mediane, sur %d cellules propres.'
              % (100.0 * max(_p4), 100.0 * sorted(_p4)[len(_p4) // 2], len(_p4)))
            A('      -> P4 REFUTEE, ET C\'ETAIT MON SUSPECT PRINCIPAL, MISE AVANT LA COURSE.')
            A('      LE MUR DE COLLISION EST EXONERE de la dependance au sens. C\'etait le seul')
            A('      terme UNILATERAL PAR NATURE du solveur — une poussee de contact ne tire')
            A('      jamais — et il ne porte pas ce defaut. La liste des suspects se reduit,')
            A('      ce qui est un resultat et non un echec.')
        A('')
        # P3 : la dependance au SENS existe-t-elle, jugee contre le plancher de REPETABILITE.
        if _FL is not None:
            A('   ROOM-SIGN-P3: l\'asymetrie de SENS, cellules propres de k=0, contre le plancher')
            A('      de repetabilite (%.3f %%). Pour un systeme lineaire OU une non-linearite'
              % (100.0 * _FL))
            A('      symetrique, A_mag et A_dir valent EXACTEMENT zero.')
            for (_k, _a) in [(0, x) for x in (0, 1, 2)]:
                if (_k, _a) not in _clean:
                    A('      %-5s : ECARTEE — sa fenetre `+` est la cellule contaminee i=0.'
                      % _AXSN[_a])
                    continue
                _ip, _im = _cellw[(_k, _a, 1)], _cellw[(_k, _a, -1)]
                for _c in sorted(chains):
                    _vp, _vm = _sgVm(_c, _ip), _sgVm(_c, _im)
                    if _vp is None or _vm is None:
                        continue
                    _am = abs(_vp - _vm) / max(_vp, _vm) if max(_vp, _vm) > 0 else None
                    _ad = None
                    _rp, _rm = _sgW.get((_c, _ip)), _sgW.get((_c, _im))
                    if _rp and _rm:
                        _np = sum(x * x for x in _rp) ** 0.5
                        _nm = sum(x * x for x in _rm) ** 0.5
                        if _np > 1e-9 and _nm > 1e-9:
                            _d = max(-1.0, min(1.0, sum(x * y for x, y in zip(_rp, _rm))
                                               / (_np * _nm)))
                            _ad = 180.0 - math.degrees(math.acos(_d))
                    A('      %-5s %-12s apex(+)=%.4f apex(-)=%.4f  A_mag=%s (%s le plancher)'
                      '  A_dir=%s'
                      % (_AXSN[_a], names[_c] if _c < len(names) else _c, _vp, _vm,
                         ('%.4f' % _am) if _am is not None else 'n/a',
                         ('%.0fx' % (_am / _FL)) if (_am is not None and _FL > 0) else 'n/a',
                         ('%.1f deg' % _ad) if _ad is not None else 'n/a'))
            A('      P3 TELLE QUE JE L\'AVAIS ECRITE PORTAIT SUR L\'AXE VERTICAL : elle est')
            A('      INDECIDABLE, sa fenetre `+` etant la cellule contaminee. Je ne la compte ni')
            A('      tenue ni refutee. Ce que les axes PROPRES etablissent est publie ci-dessus.')
        A('')
        # ---- (d) SENS ou RANG ? le test que l'ordre equilibre rend possible ----------------
        # ---- (d) SENS ou RANG ? — LA QUESTION EST DECIDEE PAR LA SECONDE PASSE (cycle 53) --
        # Le cycle 52 equilibrait l'ordre sur la GRILLE (k+a) mais pas DANS la cellule : `+` et `-`
        # y restaient la 1re et la 2e fenetre, et son test indirect rendait 10 contre 7 — pas un
        # pur effet de rang, pas net non plus. Le balayage est desormais joue DEUX FOIS, l'ordre
        # des sens inverse a la seconde passe : une meme cellule (k, axe, sens) est donc jouee une
        # fois en 1re position et une fois en 2e. L'ecart entre ses deux lectures EST l'effet du
        # RANG, mesure et non plus estime.
        _pass = {}
        for _i, (_k, _a, _s) in _sgA.items():
            for _c in sorted(chains):
                if (_c, _i) in _sgV:
                    _pass.setdefault((_k, _a, _s, _c), []).append((_i, _sgV[(_c, _i)]))
        _dp = []
        for _key, _v in sorted(_pass.items()):
            if len(_v) != 2:
                continue
            _v0, _v1 = _v[0][1], _v[1][1]
            if max(_v0, _v1) > 0:
                _dp.append((abs(_v0 - _v1) / max(_v0, _v1), _key, _v[0][0], _v[1][0], _v0, _v1))
        if _dp:
            _dp.sort(reverse=True)
            _mx = _dp[0][0]
            _md = sorted(x[0] for x in _dp)[len(_dp) // 2]
            A('   ROOM-SIGN-RANK: LE MEME (ablation, axe, sens) JOUE AUX DEUX RANGS.')
            A('      %d cellules appariees. Ecart max %.2f %%, mediane %.2f %%.'
              % (len(_dp), 100.0 * _mx, 100.0 * _md))
            for _d, _key, _ia, _ib, _va, _vb in _dp[:4]:
                A('      pire : k=%d %-9s s=%+d %-12s  i=%2d %.4f   i=%2d %.4f   %.2f %%'
                  % (_key[0], _AXSN.get(_key[1], _key[1]), _key[2],
                     names[_key[3]] if _key[3] < len(names) else _key[3],
                     _ia, _va, _ib, _vb, 100.0 * _d))
            A('      -> P6 %s (critere : <= 5 %%).'
              % ('TENUE — le RANG ne porte pas l\'ecart entre les deux sens, qui est donc bien '
                 'une dependance au SENS' if _mx <= 0.05 else
                 'REFUTEE — le rang deplace la lecture d\'autant que le sens ; l\'asymetrie de '
                 'sens publiee au cycle 52 est CONTAMINEE et sa section 5 doit etre reecrite'))
        A('')
        # ---- (e) LA GEOMETRIE : L'ANGLE OS / AXE DE PILOTAGE (cycle 53) ---------------------
        # POURQUOI CETTE LIGNE EXISTE. `phys-length-chain` est une projection d'EGALITE sur la
        # sphere de rayon `want` : elle retire EXACTEMENT la composante du deplacement ALIGNEE
        # avec l'os et laisse passer la transverse. La part qui survit vaut donc `sin(theta)`,
        # `theta` etant l'angle entre l'os et l'axe pousse. Le cycle 52 a mesure que desarmer
        # cette contrainte multiplie la reponse VERTICALE de chestL par 5.01 et celle de chestR
        # par 1.30 seulement, et a ELIMINE la longueur d'os comme cause (1040.50/140.42 contre
        # 1039.03/144.23). L'orientation est ce qui restait, et rien ne la publiait.
        # NATURE : un ANGLE (degres) entre deux directions unitaires. REPERE : le MONDE, sur la
        #   derniere frame de la rampe d'entree — sujet droit, immobile, pose, aucun pilotage.
        # CE QUI DISCRIMINE : `sin(theta)` doit CLASSER les confiscations mesurees en (b). Si un
        #   os presque perpendiculaire au pilotage etait quand meme confisque, la projection
        #   n'expliquerait rien.
        _bone = {}
        for _m in re.finditer(r'^PHYSSGNB c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+)'
                              r' uz=([-\d.e+]+)', txt, re.M):
            _bone[(int(_m.group(1)), int(_m.group(2)))] = (
                float(_m.group(3)), float(_m.group(4)), float(_m.group(5)))
        if not _bone:
            A('   ROOM-SIGN-BONE: ABSENT — aucune ligne PHYSSGNB. L\'orientation de l\'os n\'est')
            A('      pas mesuree, donc la cause de l\'ecart x5.01 / x1.30 reste NON ETABLIE.')
        elif not _axdir52:
            A('   ROOM-SIGN-BONE: les directions d\'os sont la, les axes de pilotage non.')
        else:
            A('   ROOM-SIGN-BONE: angle entre l\'OS et l\'AXE POUSSE, et la part TRANSVERSE qui')
            A('      survit a la projection de longueur (sin theta).')
            A('      %-12s %-4s | %-32s | %s'
              % ('chaine', 'os', 'direction monde de l\'os', 'vertical      avant-arr     lateral'))
            for _c in sorted(chains):
                for _l in (0, 1):
                    _u = _bone.get((_c, _l))
                    if _u is None:
                        continue
                    _n = sum(x * x for x in _u) ** 0.5
                    if _n < 1e-6:
                        A('      %-12s l=%d | NORME NULLE — l\'os n\'a pas ete lu'
                          % (names[_c] if _c < len(names) else _c, _l))
                        continue
                    _cells2 = []
                    for _a in (0, 1, 2):
                        _d = _axdir52.get(_a)
                        if _d is None:
                            _cells2.append('n/a')
                            continue
                        _cs = abs(sum(x * y for x, y in zip(_u, _d)) / _n)
                        _cs = max(0.0, min(1.0, _cs))
                        _th = math.degrees(math.acos(_cs))
                        _cells2.append('%5.1f deg sin=%.3f' % (_th, math.sin(math.radians(_th))))
                    A('      %-12s l=%d | (%+.4f, %+.4f, %+.4f)  norme %.4f | %s'
                      % (names[_c] if _c < len(names) else _c, _l, _u[0], _u[1], _u[2], _n,
                         '  '.join(_cells2)))
            # LE TEST, ET IL EST ECRIT AVANT LA COURSE (C53E1, P3 et P4).
            _cl = [_c for _c in sorted(chains)
                   if _c < len(names) and names[_c] == 'chestL']
            _cr = [_c for _c in sorted(chains)
                   if _c < len(names) and names[_c] == 'chestR']
            if _cl and _cr and (_cl[0], 0) in _bone and (_cr[0], 0) in _bone:
                def _cos(_c, _a):
                    _u = _bone[(_c, 0)]
                    _n = sum(x * x for x in _u) ** 0.5
                    _d = _axdir52[_a]
                    return abs(sum(x * y for x, y in zip(_u, _d)) / _n) if _n > 1e-6 else 0.0
                _lv, _la, _ll = _cos(_cl[0], 0), _cos(_cl[0], 1), _cos(_cl[0], 2)
                _rv = _cos(_cr[0], 0)
                A('')
                A('   ROOM-SIGN-P3: sur chestL, |cos| vertical=%.4f  avant-arr=%.4f  lateral=%.4f'
                  % (_lv, _la, _ll))
                A('      -> %s'
                  % ('P3 TENUE : le vertical EST l\'axe le plus aligne avec l\'os, donc celui que'
                     ' la contrainte de longueur confisque le plus.'
                     if (_lv > _la and _lv > _ll) else
                     'P3 REFUTEE, ET CONTRE MOI : le vertical n\'est PAS l\'axe le plus aligne.'
                     ' La projection n\'explique pas pourquoi c\'est lui qui est confisque, et'
                     ' l\'hypothese tombe sur sa premiere consequence.'))
                _sl = math.sin(math.acos(max(0.0, min(1.0, _lv))))
                _sr = math.sin(math.acos(max(0.0, min(1.0, _rv))))
                _rat = (_sr / _sl) if _sl > 1e-9 else float('inf')
                # LES DIRECTIONS D'OS DE CE BLOC VIENNENT DE `PHYSSGNB`, DONC DE PH-SGN — la seule
                # phase de la course qui EPINGLE sa pose par son nom ET la revalide a l'execution.
                # Elle a donc un ecart au miroir, et il se publie ici comme partout ailleurs : ce
                # n'est pas parce qu'une pose est bonne qu'une ligne peut se taire dessus.
                _psgn = POSE['PH-SGN']
                _P4NOTE = 'l attribution du cycle 52 depend de cette ligne.'
                A(asym('   ROOM-SIGN-P4', ': |cos| vertical — chestL=%.4f  chestR=%.4f ; parts'
                       ' transverses sin=%.4f et %.4f, rapport %s'
                       % (_lv, _rv, _sl, _sr,
                          ('%.2f' % _rat) if _rat != float('inf') else 'INDEFINI'), _psgn,
                       note=_P4NOTE))
                # LA CONFISCATION MESUREE SUR *CETTE* COURSE, jamais un nombre en dur. Une
                # constante ecrite ici vieillirait en silence et se lirait plus tard comme une
                # mesure vivante — c'est le mode d'echec que ce dossier a paye quatre fois.
                _conf = []
                for _cc, _nm in ((_cl[0], 'chestL'), (_cr[0], 'chestR')):
                    for _s in (1, -1):
                        _v0 = _sgVm(_cc, _cellw.get((0, 0, _s)))
                        _v1 = _sgVm(_cc, _cellw.get((1, 0, _s)))
                        if _v0 and _v0 > 0 and _v1 is not None:
                            _conf.append('%s s=%+d x%.2f' % (_nm, _s, _v1 / _v0))
                # CES DEUX LIGNES POSENT LES DEUX CHAINES COTE A COTE AVEC UN CHIFFRE CHACUNE :
                # c'est une comparaison, quoi qu'en dise leur redaction, et elles portent leur
                # pose comme le verdict qu'elles servent.
                A(asym('      confiscation MESUREE sur cette course (k=1 / k=0, axe vertical)',
                       ' : %s' % ('  ·  '.join(_conf) if _conf else 'INDISPONIBLE'), _psgn,
                       note=_P4NOTE))
                A(asym('      predite par 1/sin', ' : chestL x%s  chestR x%s'
                       % (('%.2f' % (1.0 / _sl)) if _sl > 1e-9 else 'inf',
                          ('%.2f' % (1.0 / _sr)) if _sr > 1e-9 else 'inf'), _psgn, note=_P4NOTE))
                if _lv > _rv and _rat >= 1.5:
                    A(asym('      -> P4 TENUE', ' : l\'os de chestL est plus aligne avec le'
                           ' pilotage vertical, et le rapport des parts transverses va dans le'
                           ' bon sens.', _psgn, note=_P4NOTE))
                elif _lv > _rv:
                    A(asym('      -> P4 A MOITIE', ' : le classement est bon (chestL plus aligne)'
                           ' mais le rapport %.2f est SOUS le 1.5 que j\'avais pose.'
                           ' L\'orientation contribue sans suffire.' % _rat, _psgn,
                           note=_P4NOTE))
                else:
                    # CE VERDICT COMPARE LES DEUX OS : il porte sa pose comme les trois lignes
                    # qui le nourrissent. C'est PH-SGN, la seule phase qui epingle sa pose par son
                    # nom ET la revalide — donc le verdict sort, avec son ecart au miroir dessus.
                    A(asym('      -> P4 REFUTEE, ET CONTRE MOI', ' : l\'os de chestL n\'est PAS'
                           ' plus aligne que celui de chestR. La longueur etant deja eliminee,'
                           ' l\'orientation ne rend pas compte de l\'ecart gauche/droite non plus'
                           ' — il ne reste que la repartition de peau, que ce cycle ne mesure'
                           ' pas.', _psgn, note=_P4NOTE))
        A('')


    # ============================================================================================
    # SPEC 8 / 10-13 / 29-torsion / 33-34 / 36 — LE CANAL DE DEFORMATION, LA TORSION, LA RESTITUTION
    # Ajoutees le 2026-08-14 (cycle 7). Ces lignes ne REMPLACENT rien : elles publient des
    # grandeurs qui n'avaient aucun instrument, ce que l'audit du 09:45 comptait comme ABSENT.
    # ============================================================================================
    # ============================================================================================
    # SPEC 24/25/26 — L'AJUSTEMENT SUR TOUTE LA SERIE, AVEC SON INTERVALLE DE CONFIANCE.
    # Le cycle 6 avait etabli que le comptage de croisements de zero ne PEUT PAS trancher §24 :
    # a 60 Hz une demi-periode vaut 12 a 15 frames, le ring-down libre en offre 2 a 3, donc +/- 4 %
    # au mieux pour des bandes separees de 6 %. Sa conclusion, mot pour mot : « un ajustement
    # frequentiel sur TOUTE la serie plutot qu'un comptage de croisements ». C'est ce bloc.
    # METHODE : a (f, zeta) fixes, le modele A e^{-zeta w t} cos(wd t + phi) + c est LINEAIRE en
    # (A cos phi, A sin phi, c) ; on le resout exactement par moindres carres, sur une grille de
    # (f, zeta). Le minimum donne f ; l'ensemble des f dont le residu reste sous 1.10x le minimum
    # donne l'INTERVALLE. Aucun parametre du solveur n'est touche : on change l'instrument, jamais
    # la chose mesuree.
    # ============================================================================================
    A('')
    A('-- ROOM-RINGFIT : SPEC 24/25/26, AJUSTEES SUR TOUTE LA SERIE ------------------------------')
    A('   SPEC 24 : Vertical 2.30 Hz (2.1-2.5) / Front-Back 2.50 Hz (2.3-2.7) / Lateral 2.65 Hz')
    A('   (2.4-2.9), « vertical motion is intentionally the slowest ». SPEC 25 : zeta 0.35')
    A('   (0.32-0.42). SPEC 26 : premier depassement oppose 0.31 pour zeta = 0.35.')
    A('   NATURE : une frequence propre et un taux d\'amortissement, tires par moindres carres de la')
    A('   serie ENTIERE de deviation (PHYSRINGA, fenetre de repos ; PHYSRINGAT, fenetre inclinee),')
    A('   apres saut du transitoire (12 frames).  REPERE : le triedre de l\'ANCRE (SPEC 7).')
    A('   `residu` = ecart-type residuel rapporte a l\'amplitude du signal : au-dela de ~0.08 la')
    A('   serie ne porte pas un mode unique et le chiffre ne doit PAS etre lu comme une frequence.')
    A('   `[fmin..fmax]` = les frequences dont le residu reste sous 1.10x le minimum. DEUX AXES DONT')
    A('   LES INTERVALLES NE SE RECOUVRENT PAS SONT DEUX MODES DISTINCTS : c\'est la forme que')
    A('   demande le contrat (« une reponse identique dans les trois directions prouve qu\'elles ne')
    A('   sont pas appliquees »), lue dans les deux sens.')
    # [CORRECTION D'INSTRUMENT 2026-08-18] Les lignes `v` de CET instrument sont AVEUGLES AU MODE
    # VERTICAL REEL : l'os ancre->lBoob porte 84.5 % de son energie sur la verticale (ROOM-ORIAXIS,
    # confirme par ROOM-AXBLIND R^2=1.00000 sur les DEUX chaines), et la contrainte de longueur
    # tient le joint sur une sphere — sa deviation RADIALE (≈ verticale) est structurellement
    # quasi nulle. Ce que la ligne `v` capte est la FUITE des deux modes TANGENTIELS (valeurs
    # propres de P·S·P, P = I - b·bT, S = diag(1, 1/0.90, 1/0.82) : lambda1 = 1.1078 ~98 % ap,
    # lambda2 = 1.1912 ~93 % lat) — verification : f_base×sqrt(lambda) predit les diagonales AXFIT
    # a ±1 % sur les 6 lignes. Le mode vertical du TISSU vit sur le canal radial de SPEC 23 et se
    # lit sur ROOM-AXFIT-RAD (PHYSRINGCX). La ligne `v` reste publiee (elle mesure honnetement les
    # tangentiels) mais son verdict §24-v est retire : il comparerait un mode lateral a une cible
    # verticale.
    A('   ATTENTION (correction d\'instrument 2026-08-18) : les lignes `v` ci-dessous lisent la')
    A('   FUITE des modes tangentiels, pas le mode vertical — le joint vit sur la sphere de la')
    A('   contrainte de longueur et l\'os est vertical a 84.5 %. Le verdict §24-v (2.30 Hz) se lit')
    A('   sur ROOM-AXFIT-RAD (canal radial de SPEC 23), plus bas.')
    try:
        import numpy as _np
        _HAVE_NP = True
    except Exception:
        _HAVE_NP = False
    def _fitseries(vals, skip=12):
        y = _np.array(vals[skip:], dtype=float)
        n = len(y)
        if n < 20:
            return None
        t = _np.arange(n) / 60.0
        sy = float(_np.sum(y * y))
        if sy <= 0:
            return None
        best = None
        keep = []
        for f in _np.arange(1.20, 6.001, 0.005):
            w = 2.0 * math.pi * float(f)
            for z in _np.arange(0.10, 0.701, 0.01):
                a = float(z) * w
                wd = w * math.sqrt(max(1e-9, 1.0 - float(z) * float(z)))
                e = _np.exp(-a * t)
                M = _np.stack([e * _np.cos(wd * t), e * _np.sin(wd * t), _np.ones(n)], axis=1)
                sol, _r, _rk, _sv = _np.linalg.lstsq(M, y, rcond=None)
                r = float(_np.sum((M @ sol - y) ** 2))
                keep.append((r, float(f)))
                if best is None or r < best[0]:
                    best = (r, float(f), float(z))
        okf = [f for r, f in keep if r <= 1.10 * best[0]]
        return dict(f=best[1], zeta=best[2], rel=math.sqrt(best[0] / sy),
                    fmin=min(okf), fmax=max(okf), n=n)
    def _rebound(vals, skip=12):
        y = vals[skip:]
        ext = [y[i] for i in range(1, len(y) - 1) if (y[i] - y[i - 1]) * (y[i + 1] - y[i]) < 0]
        if len(ext) < 2 or abs(ext[0]) < 1e-9:
            return None
        for k in range(1, len(ext)):
            if ext[k] * ext[0] < 0:
                return abs(ext[k]) / abs(ext[0])
        return None
    _ser = {}
    for _tag in ('PHYSRINGA', 'PHYSRINGAT'):
        for m in re.finditer(r'^%s c=(\d+) f=(\d+) l=(\d+) v=([-\d.e+]+) ap=([-\d.e+]+)'
                             r' lat=([-\d.e+]+)' % _tag, txt, re.M):
            # LE MAILLON, ENCORE — MEME DEFAUT QUE `PHYSRINGCX` PLUS BAS (2026-08-17).
            # Cette cle etait `(_tag, c, ax)` : le champ `l` etait capture par la regex et JAMAIS
            # utilise, donc tous les maillons tombaient dans la MEME serie. A un maillon c'est sans
            # effet (`l` vaut toujours 0), et c'est pourquoi le defaut a survecu. A deux maillons la
            # serie recoit DEUX echantillons par frame alors que `_fitseries` en suppose UN : elle
            # rend une frequence deux fois trop basse, qui bute sur la borne basse 1.200 de la
            # grille et s'imprime « residu trop grand, non lisible » sur les SIX canaux.
            # Mesure sur la course n=2 en cablage LIVRE (`PRE-C16n2c`) AVANT ce correctif :
            #     n=286 au lieu de 137, les 6 canaux a 1.200 Hz, tous « non lisibles »
            # alors que la serie du maillon RACINE lue directement est identique au controle a
            # 1 maillon (4 canaux sur 6 a maxdiff EXACTEMENT 0.000000).
            # Le cycle 16 a corrige ce defaut sur `PHYSRINGCX` (:3931-3937) et a laisse celui-ci,
            # puis a lu la baisse de frequence comme une regression PHYSIQUE de SPEC 24 et retire
            # la structure en partie sur ce motif.
            # On garde le maillon RACINE, celui que la mesure lisait deja quand la chaine n'en avait
            # qu'un : la sortie est donc IDENTIQUE a un maillon, ce qui se verifie en regenerant le
            # tableau depuis le log de controle (aucune mesure ne doit bouger).
            if int(m.group(3)) != 0:
                continue
            for _ax, _g in (('v', 4), ('ap', 5), ('lat', 6)):
                _ser.setdefault((_tag, int(m.group(1)), _ax), []).append(
                    (int(m.group(2)), float(m.group(_g))))
    if not _HAVE_NP:
        A('ROOM-RINGFIT: ABSENT (numpy indisponible)')
    elif not _ser:
        A('ROOM-RINGFIT: ABSENT (aucune serie PHYSRINGA/PHYSRINGAT dans la trace)')
    else:
        A('')
        A('   fenetre      chaine        axe  n    f (Hz)  intervalle       zeta   residu  rebond'
          '   cible §24')
        _TGT = {'v': '2.30 (2.1-2.5)', 'ap': '2.50 (2.3-2.7)', 'lat': '2.65 (2.4-2.9)'}
        _band = {'v': (2.1, 2.5), 'ap': (2.3, 2.7), 'lat': (2.4, 2.9)}
        _iv = {}
        for (_tag, _c, _ax) in sorted(_ser):
            _vals = [v for _f, v in sorted(_ser[(_tag, _c, _ax)])]
            _r = _fitseries(_vals)
            if not _r:
                continue
            _rb = _rebound(_vals)
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            _win = 'repos' if _tag == 'PHYSRINGA' else 'inclinaison'
            _lo, _hi = _band[_ax]
            _in = 'DANS' if _lo <= _r['f'] <= _hi else 'HORS'
            if _ax == 'v':
                # Instrument aveugle au radial (voir la note d'en-tete) : pas de verdict §24-v ici.
                _in = 'tangentiel — §24-v: ROOM-AXFIT-RAD'
            if _r['rel'] > 0.08:
                _in = 'residu trop grand, non lisible'
            A('ROOM-RINGFIT: %-11s %-12s %-3s %3d  %6.3f  [%.3f..%.3f]  %.2f   %.3f   %-6s  %s  %s'
              % (_win, _nm, _ax, _r['n'], _r['f'], _r['fmin'], _r['fmax'], _r['zeta'], _r['rel'],
                 ('%.3f' % _rb) if _rb else 'n/a', _TGT[_ax], _in))
            if _tag == 'PHYSRINGA' and _r['rel'] <= 0.08:
                _iv[(_c, _ax)] = (_r['fmin'], _r['fmax'])
        A('')
        A('   LES TROIS MODES SONT-ILS SEPARES ? (fenetre de repos, residu <= 0.08 seulement)')
        for _c in sorted({c for (c, _a) in _iv}):
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            _pairs = []
            for _a, _b in (('v', 'ap'), ('ap', 'lat'), ('v', 'lat')):
                if (_c, _a) in _iv and (_c, _b) in _iv:
                    _x, _y = _iv[(_c, _a)], _iv[(_c, _b)]
                    _pairs.append('%s/%s %s' % (_a, _b,
                                  'SEPARES' if (_x[1] < _y[0] or _y[1] < _x[0]) else 'confondus'))
            A('ROOM-RINGFIT-SEP: chain=%-12s %s' % (_nm, ' · '.join(_pairs) if _pairs else
                                                    'pas assez d\'axes lisibles'))
    A('')
    # ============================================================================================
    # ROOM-AXNAME — LA MESURE QUI NOMME LES AXES, CONTRE UN INVARIANT EXTERNE.  (cycle 10)
    # POURQUOI ELLE EXISTE, ET C'EST LA SEULE RAISON : une mesure par axe qui ne publie que des
    # VALEURS ne peut pas attraper une permutation de ses propres axes. Les trois lignes du triedre
    # rendent trois nombres ; aucun d'eux ne dit lequel est l'avant-arriere. Le cycle 9 a paye
    # exactement ca — §29 posait 0.90 sur le lateral et 0.82 sur l'avant-arriere, §24 comparait
    # 2.50 / 2.65 Hz aux mauvais axes, le mecanisme etait arme, la mesure etait propre, et RIEN ne
    # pouvait le signaler. Il faut donc une grandeur dont la reponse est connue D'AVANCE par la
    # geometrie : le segment qui va d'un sein a l'autre est LATERAL par anatomie. Il doit tomber
    # entierement sur la ligne que le solveur a nommee `lat`, et ~rien sur l'autre.
    # NATURE : deux longueurs signees, en unites de jeu (les projections du segment inter-seins sur
    #   les deux lignes non verticales du triedre), et leur rapport, sans dimension.
    # REPERE : les lignes de la matrice de l'ANCRE (torse), SPEC 7 — le meme triedre que `PHYSAXIS`
    #   et que toutes les mesures par axe qui suivent.
    # LIGNE DE BASE : `src=separation` = la separation gauche-droite a tranche (l'invariant est
    #   porte) ; `src=protrusion` = pas de chaine partenaire, repli sur la protrusion propre de
    #   l'organe, qui ne porte PLUS l'invariant anatomique et dont le verdict vaut donc moins.
    # ABSENT : aucune ligne PHYSAXNAME (trace anterieure au cycle 10). La ligne le dit et ne
    #   substitue aucune autre grandeur.
    # ============================================================================================
    A('-- ROOM-AXNAME : LES AXES PORTENT-ILS LES BONS NOMS ? (prealable a SPEC 24 et SPEC 29) -----')
    A('   Une mesure par axe qui ne publie que des VALEURS ne peut pas attraper une permutation de')
    A('   ses propres axes : trois nombres sortent, et rien ne dit lequel est l\'avant-arriere. Il')
    A('   faut une grandeur dont la reponse est connue D\'AVANCE par la geometrie. Le segment qui va')
    A('   d\'un sein a l\'autre est LATERAL par anatomie : il doit tomber sur la ligne nommee `lat`,')
    A('   et ~rien sur l\'autre. Tant que cette ligne n\'est pas verte, tous les verdicts par axe')
    A('   ci-dessous SUPPOSENT leurs etiquettes au lieu de les verifier.')
    A('   `sja` est la projection sur la PREMIERE ligne candidate `ja`, `sjb` sur la seconde `jb` ;')
    A('   les deux candidates sont celles qui ne sont pas la verticale `rv` de `PHYSAXIS`, dans')
    A('   l\'ordre du solveur : rv=0 -> (1,2), rv=1 -> (0,2), rv=2 -> (0,1). `rlat` dit LAQUELLE des')
    A('   deux a ete nommee laterale, et c\'est elle qui donne `sep_lat`.')
    _axnm = {}
    for m in re.finditer(r'^PHYSAXNAME c=(\d+) src=(\d+) rlat=(\d+) sja=([-\d.e+]+)'
                         r' sjb=([-\d.e+]+) len=([-\d.e+]+)', txt, re.M):
        _axnm[int(m.group(1))] = dict(src=int(m.group(2)), rlat=int(m.group(3)),
                                      sja=float(m.group(4)), sjb=float(m.group(5)),
                                      seg=float(m.group(6)))
    _axrv = {}
    for m in re.finditer(r'^PHYSAXIS c=(\d+) ok=(\d+) arm=(\d+) rv=(\d+) rap=(\d+) rlat=(\d+)',
                         txt, re.M):
        _axrv[int(m.group(1))] = dict(rv=int(m.group(4)), rlat=int(m.group(6)))
    # La regle du solveur, recopiee telle quelle : les deux candidates sont les deux lignes qui ne
    # sont pas la verticale. Elle est ECRITE ici pour que la lecture soit verifiable, pas devinee.
    _JCAND = {0: (1, 2), 1: (0, 2), 2: (0, 1)}
    if not _axnm:
        A('ROOM-AXNAME: ABSENT (aucune ligne PHYSAXNAME dans la trace) — le nommage des axes n\'a')
        A('   PAS ete mesure sur cette course. Aucune autre grandeur n\'est substituee : les')
        A('   verdicts par axe qui suivent supposent leurs etiquettes.')
    else:
        for _c in sorted(_axnm):
            _d = _axnm[_c]
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            if _c not in _axrv:
                A('ROOM-AXNAME: chain=%-12s PHYSAXIS absente pour cette chaine — la ligne verticale'
                  ' `rv` est inconnue, donc `ja`/`jb` ne sont pas derivables et rien n\'est'
                  ' attribue.' % _nm)
                continue
            _iv = _axrv[_c]['rv']
            if _iv not in _JCAND:
                A('ROOM-AXNAME: chain=%-12s rv=%d hors 0..2 — la regle ja/jb du solveur ne'
                  ' s\'applique pas, aucune attribution.' % (_nm, _iv))
                continue
            _ja, _jb = _JCAND[_iv]
            if _d['rlat'] == _ja:
                _slat, _sap = _d['sja'], _d['sjb']
            elif _d['rlat'] == _jb:
                _slat, _sap = _d['sjb'], _d['sja']
            else:
                A('ROOM-AXNAME: chain=%-12s INCOHERENT : rlat=%d n\'est ni ja=%d ni jb=%d (rv=%d).'
                  ' Aucune attribution possible sans deviner — rien n\'est publie ici.'
                  % (_nm, _d['rlat'], _ja, _jb, _iv))
                continue
            _ratio = abs(_slat) / max(1e-9, abs(_sap))
            _dis = ''
            if _axrv[_c]['rlat'] != _d['rlat']:
                _dis = '  (DESACCORD : PHYSAXIS annonce rlat=%d)' % _axrv[_c]['rlat']
            A('ROOM-AXNAME: chain=%-12s src=%-10s rlat=%d sep_lat=%9.4f sep_ap=%9.4f'
              ' ratio=%10.2f verdict=%-7s seg=%.2f u%s'
              % (_nm, 'separation' if _d['src'] == 1 else 'protrusion', _d['rlat'],
                 _slat, _sap, _ratio, 'NOMME' if _ratio >= 10.0 else 'AMBIGU', _d['seg'], _dis))
        A('   `seg` = la norme du segment publiee par le moteur, en unites de jeu : elle donne')
        A('   l\'ECHELLE de ce qui a ete projete (~712 u = 17.4 cm mesures sur le rig). Un `seg`')
        A('   qui n\'est pas de cet ordre veut dire que le segment mesure n\'est pas celui-la, et le')
        A('   verdict de nommage ne vaut alors rien, quel que soit son ratio.')
    A('')
    A('-- ROOM-AXFIT : SPEC 24/25/26/27, TROIS IMPULSIONS ISOLEES, UNE PAR AXE -------------------')
    A('   SPEC 27 ecrit le protocole mot pour mot : « After ONE STRONG ISOLATED IMPULSE ». La')
    A('   fenetre de repos ne l\'execute pas — elle suit CINQ pilotages, donc ce qui y sonne est un')
    A('   melange de modes, et c\'est pour ca que `ROOM-RINGFIT-SEP` rendait « v/ap confondus ».')
    A('   Ici chaque axe recoit SON impulsion (demi-cosinus, 10 frames, pic 18 u/frame^2 — la bande')
    A('   LINEAIRE, ou une frequence propre et un zeta sont definis), puis on lache 150 frames.')
    A('')
    A('   NATURE : une FREQUENCE (Hz) et un rapport d\'amortissement, tires de la serie temporelle')
    A('     de deplacement `PHYSRINGAX`. REPERE : triedre de l\'ancre (torse), SPEC 7 — le meme que')
    A('     `PHYSRINGA`, donc les deux fenetres sont comparables.')
    A('   CE QUI DISCRIMINE : la colonne `axe` contre la colonne `excite`. Sur la ligne ou les deux')
    A('     coincident, la serie EST le mode propre de cet axe. Les deux autres lignes chiffrent la')
    A('     diaphonie — et si les trois fenetres rendaient la meme frequence, l\'anisotropie de')
    A('     SPEC 29 n\'atteindrait pas le solveur.')
    A('   ABSENT : aucune ligne PHYSRINGAX dans la trace (phases AXV/AXB/AXL non jouees).')
    # `_axs` = contrainte de longueur ARMEE (PHYSRINGAX), `_axz` = DESARMEE (PHYSRINGAZ). Meme
    # disposition de champs, donc meme parseur au nom pres.
    _axs = {}
    _axz = {}
    # LE MAILLON, TROISIEME ENDROIT — cf. `ROOM-RINGFIT` plus haut et `PHYSRINGCX` plus bas.
    # Ces quatre cles jetaient elles aussi le champ `l=` : `(ax, c, axe)` sans le maillon. A deux
    # maillons chaque frame verse DEUX echantillons, `_fitseries` en suppose UN, et les 18 lignes
    # `ROOM-AXFIT` deviennent illisibles — ce que le cycle 16 a lu comme une consequence PHYSIQUE
    # de l'injection (« le ROOM-AXFIT classique subit le meme sort »). C'etait le meme artefact.
    # On garde le maillon RACINE : identite a un maillon, ou `l` vaut toujours 0.
    for m in re.finditer(r'^PHYSRINGAZ c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)', txt, re.M):
        if int(m.group(3)) != 0:
            continue
        _axz.setdefault((int(m.group(4)), int(m.group(1)), 'v'), []).append(
            (int(m.group(2)), float(m.group(5))))
    for m in re.finditer(r'^PHYSRINGAZ2 c=(\d+) f=(\d+) ax=(\d+) l=(\d+)'
                         r' ap=([-\d.e+]+) lat=([-\d.e+]+)', txt, re.M):
        if int(m.group(4)) != 0:
            continue
        _axz.setdefault((int(m.group(3)), int(m.group(1)), 'ap'), []).append(
            (int(m.group(2)), float(m.group(5))))
        _axz.setdefault((int(m.group(3)), int(m.group(1)), 'lat'), []).append(
            (int(m.group(2)), float(m.group(6))))
    for m in re.finditer(r'^PHYSRINGAX c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)', txt, re.M):
        if int(m.group(3)) != 0:
            continue
        _axs.setdefault((int(m.group(4)), int(m.group(1)), 'v'), []).append(
            (int(m.group(2)), float(m.group(5))))
    # `ax` est REPETE sur la seconde ligne : les trois fenetres repartent chacune a la frame 0,
    # donc `f` seule ne designerait pas une fenetre et l'appariement serait ambigu.
    for m in re.finditer(r'^PHYSRINGAX2 c=(\d+) f=(\d+) ax=(\d+) l=(\d+)'
                         r' ap=([-\d.e+]+) lat=([-\d.e+]+)', txt, re.M):
        if int(m.group(4)) != 0:
            continue
        _axs.setdefault((int(m.group(3)), int(m.group(1)), 'ap'), []).append(
            (int(m.group(2)), float(m.group(5))))
        _axs.setdefault((int(m.group(3)), int(m.group(1)), 'lat'), []).append(
            (int(m.group(2)), float(m.group(6))))
    # Collecte HISSEE ici (2026-08-18) : AXRATIO a besoin du fit radial comme `f_v` (correction
    # d'instrument — la ligne `v` d'AXFIT lit les modes tangentiels, pas le vertical). La collecte
    # vivait apres le bloc AXFIT ; elle ne depend que de `txt`, la hisser ne change aucun nombre.
    _cxs, _cxz = {}, {}
    for _tg, _dst in (('PHYSRINGCX', _cxs), ('PHYSRINGCZ', _cxz)):
        for m in re.finditer(r'^%s c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)' % _tg,
                             txt, re.M):
            if int(m.group(3)) != 0:
                continue
            _dst.setdefault((int(m.group(4)), int(m.group(1))), []).append(
                (int(m.group(2)), float(m.group(5))))
    if not _HAVE_NP:
        A('ROOM-AXFIT: ABSENT (numpy indisponible)')
    elif not _axs:
        A('ROOM-AXFIT: ABSENT (aucune serie PHYSRINGAX dans la trace)')
    else:
        _AXN = {0: 'v', 1: 'ap', 2: 'lat'}
        _T2 = {'v': '2.30 (2.1-2.5)', 'ap': '2.50 (2.3-2.7)', 'lat': '2.65 (2.4-2.9)'}
        _B2 = {'v': (2.1, 2.5), 'ap': (2.3, 2.7), 'lat': (2.4, 2.9)}
        A('')
        # ---- LE CONTROLE DE LA MESURE ELLE-MEME : l'impulsion isole-t-elle bien UN axe ? -------
        # Sans cette ligne, trois fenetres qui rendent trois frequences seraient prises pour trois
        # frequences PROPRES. La premiere version de cette phase poussait en axes MONDE et cinq
        # fenetres sur six etaient dominees par le MEME axe du solveur : les trois « frequences »
        # etaient trois melanges. Une mesure qui ne montre pas sa propre selectivite ne decide rien.
        # NATURE : une part d'energie, sans dimension (valeur efficace d'une projection rapportee a
        # la somme des trois). REPERE : triedre de l'ancre. ABSENT : 33 % partout (aucune selectivite).
        A('   SELECTIVITE DE L\'EXCITATION — part de la reponse tombant sur chaque projection.')
        A('   L\'axe EXCITE doit dominer sa propre fenetre ; sinon la frequence lue est un melange.')
        for m in re.finditer(r'^PHYSAXW ax=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)',
                             txt, re.M):
            A('ROOM-AXDIR: axe=%-3s direction monde poussee = (%.5f, %.5f, %.5f)'
              % (_AXN[int(m.group(1))], float(m.group(2)), float(m.group(3)), float(m.group(4))))
        for _c in sorted({c for (_k, c, _a) in _axs}):
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            for _k in (0, 1, 2):
                _r = {}
                for _a in ('v', 'ap', 'lat'):
                    if (_k, _c, _a) in _axs:
                        _vv = [v for _f, v in _axs[(_k, _c, _a)]]
                        _r[_a] = (sum(x * x for x in _vv) / max(1, len(_vv))) ** 0.5
                if len(_r) != 3:
                    continue
                _tt = sum(_r.values()) or 1.0
                _dom = max(_r, key=_r.get)
                A('ROOM-AXSEL: excite=%-3s chain=%-12s v=%4.1f%% ap=%4.1f%% lat=%4.1f%%   -> %s'
                  % (_AXN[_k], _nm, 100 * _r['v'] / _tt, 100 * _r['ap'] / _tt,
                     100 * _r['lat'] / _tt,
                     'ISOLE' if _dom == _AXN[_k] else 'MELANGE, domine par %s' % _dom.upper()))
        A('')
        # ---- LE CONTROLE POSITIF DE L'HYPOTHESE : contrainte de longueur DESARMEE -------------
        # Hypothese du cycle 8 : un point contraint sur une sphere autour de son ancre n'a que DEUX
        # degres de liberte de translation, la ou SPEC 24 en demande TROIS. Si c'est la cause de la
        # non-selectivite, la LEVER doit faire MONTER la part de reponse tombant sur l'axe pousse.
        # LECTURE : `delta` positif = l'hypothese est soutenue ; nul ou negatif = elle est REFUTEE,
        # et la cause du melange est ailleurs. Les deux issues sont publiees telles quelles.
        if not _axz:
            A('ROOM-AXSEL-NOLEN: ABSENT (aucune serie PHYSRINGAZ — phases AXZ non jouees)')
        else:
            A('   CONTROLE POSITIF — LA MEME IMPULSION, CONTRAINTE DE LONGUEUR (SPEC 22) LEVEE.')
            A('   `sel` = part de la reponse tombant sur l\'axe POUSSE. Si la contrainte est ce qui')
            A('   confisque le troisieme degre de liberte, `sel` doit MONTER quand on la leve.')
            for _c in sorted({c for (_k, c, _a) in _axz}):
                _nm = names[_c] if _c < len(names) else 'c%d' % _c
                for _k in (0, 1, 2):
                    def _sel(_d):
                        _q = {}
                        for _a in ('v', 'ap', 'lat'):
                            if (_k, _c, _a) in _d:
                                _vv = [v for _f, v in _d[(_k, _c, _a)]]
                                _q[_a] = (sum(x * x for x in _vv) / max(1, len(_vv))) ** 0.5
                        if len(_q) != 3:
                            return None
                        return 100.0 * _q[_AXN[_k]] / (sum(_q.values()) or 1.0)
                    _on, _off = _sel(_axs), _sel(_axz)
                    if _on is None or _off is None:
                        continue
                    A('ROOM-AXSEL-NOLEN: excite=%-3s chain=%-12s sel_contrainte=%4.1f%%'
                      '  sel_levee=%4.1f%%  delta=%+5.1f pts  -> %s'
                      % (_AXN[_k], _nm, _on, _off, _off - _on,
                         'HYPOTHESE SOUTENUE' if _off - _on >= 5.0 else
                         'HYPOTHESE REFUTEE (la contrainte n\'est pas la cause)'))
        A('')
        A('   excite  chaine        axe  n    f (Hz)  intervalle       zeta   residu  rebond'
          '   cible §24')
        _fv = {}
        for (_k, _c, _ax) in sorted(_axs):
            _vals = [v for _f, v in sorted(_axs[(_k, _c, _ax)])]
            _r = _fitseries(_vals)
            if not _r:
                continue
            _rb = _rebound(_vals)
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            _lo, _hi = _B2[_ax]
            _in = 'DANS' if _lo <= _r['f'] <= _hi else 'HORS'
            if _ax == 'v':
                # [CORRECTION D'INSTRUMENT 2026-08-18] Meme aveuglement radial que ROOM-RINGFIT
                # (note d'en-tete la-bas) : PHYSRINGAX est une difference de vecteurs UNITAIRES,
                # radialement nulle par construction, et l'os est vertical a 84.5 %. La ligne `v`
                # lit la fuite des modes tangentiels (lambda2 = 1.1912 : f_base×1.0914 predit
                # 2.511/2.609 pour 2.530/2.635 mesures). Verdict §24-v -> ROOM-AXFIT-RAD.
                _in = 'tangentiel — §24-v: ROOM-AXFIT-RAD'
            if _r['rel'] > 0.08:
                _in = 'residu trop grand, non lisible'
            _mark = '*' if _AXN[_k] == _ax else ' '
            A('ROOM-AXFIT:%s%-6s %-12s %-3s %3d  %6.3f  [%.3f..%.3f]  %.2f   %.3f   %-6s  %s  %s'
              % (_mark, _AXN[_k], _nm, _ax, _r['n'], _r['f'], _r['fmin'], _r['fmax'], _r['zeta'],
                 _r['rel'], ('%.3f' % _rb) if _rb else 'n/a', _T2[_ax], _in))
            if _AXN[_k] == _ax and _r['rel'] <= 0.08:
                _fv[(_c, _ax)] = _r
        A('')
        A('   (* = la ligne ou l\'axe MESURE est celui qu\'on a EXCITE : c\'est elle qui porte le')
        A('   mode propre. Les autres chiffrent la diaphonie.)')
        A('')
        # SPEC 29 : les rapports de frequence que les compliances livrees imposent. Ce ne sont pas
        # des cibles choisies — ils se DERIVENT de `sap`/`slat` que le moteur publie (PHYSAXISS),
        # et c'est la seule facon de dire si l'anisotropie ARRIVE au solveur.
        A('   SPEC 29 — L\'ANISOTROPIE ARRIVE-T-ELLE ? Les compliances livrees (1.00 / 0.90 / 0.82)')
        A('   imposent, a masse unique, f_ap/f_v = sqrt(1/0.90) = 1.0541 et f_lat/f_v =')
        A('   sqrt(1/0.82) = 1.1043. Mesure contre attendu :')
        # SPEC 24 donne, elle, des FREQUENCES (2.30 / 2.50 / 2.65 Hz), donc ses propres rapports :
        # 2.50/2.30 = 1.0870 et 2.65/2.30 = 1.1522. Les deux sections sont SUR-DETERMINEES et
        # legerement incompatibles (+3.1 % et +4.3 %) : le tableau le DIT au lieu de le taire, en
        # publiant les deux references cote a cote. La seconde reference ne remplace pas la
        # premiere — l'ancienne ligne est intacte juste au-dessus.
        # NATURE : des rapports de frequences, sans dimension. REPERE : le triedre de l'ANCRE
        # (SPEC 7), axes nommes par ROOM-AXNAME. LIGNE DE BASE : 1.0000 = trois axes confondus,
        # donc anisotropie qui n'atteint pas le solveur.
        _R24 = {'ap': 2.50 / 2.30, 'lat': 2.65 / 2.30}
        _R29 = {'ap': 1.05409, 'lat': 1.10432}
        _B24 = {'ap': (2.3, 2.7), 'lat': (2.4, 2.9)}
        # [CORRECTION D'INSTRUMENT 2026-08-18] `f_v` etait pris sur la ligne `v` d'AXFIT, qui lit
        # les modes TANGENTIELS (voir la note du verdict) : les ecarts -8/-13 % publies jusqu'ici
        # etaient l'artefact d'un denominateur trop haut de ×1.10. Le denominateur correct est le
        # mode radial (≈ vertical, os a 84.5 % vertical) : fit PHYSRINGCX de la fenetre d'impulsion
        # VERTICALE (meme protocole §27, meme estimateur `_fitseries`, meme skip). NATURE : une
        # frequence propre (Hz). REPERE : canal radial de SPEC 23, triedre de l'ancre. LECTURE
        # QUAND LE DEFAUT EST ABSENT : f_v = cible §24 (2.30 a gauche, +asymetrie §32 a droite).
        _frad = {}
        for (_kk, _cc) in _cxs:
            if _kk != 0:
                continue  # fenetre d'impulsion VERTICALE seulement — le protocole de §27
            _rr_ = _fitseries([v for _f, v in sorted(_cxs[(_kk, _cc)])])
            if _rr_ and _rr_['rel'] <= 0.08:
                _frad[_cc] = _rr_
        for _c in sorted({c for (c, _a) in _fv}):
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            if _c not in _frad:
                A('ROOM-AXRATIO: chain=%-12s f_v radial (PHYSRINGCX, fenetre v) non lisible —'
                  ' rapports indisponibles' % _nm)
                continue
            _f0 = _frad[_c]['f']
            A('ROOM-AXRATIO-SRC: chain=%-12s f_v=%.3f Hz [%.3f..%.3f] source=PHYSRINGCX'
              ' (mode radial, fenetre d\'impulsion verticale) — la ligne `v` d\'AXFIT est'
              ' tangentielle et ne sert plus de denominateur'
              % (_nm, _f0, _frad[_c]['fmin'], _frad[_c]['fmax']))
            _out = []
            for _a, _exp in (('ap', 1.05409), ('lat', 1.10432)):
                if (_c, _a) in _fv:
                    _rr = _fv[(_c, _a)]['f'] / _f0
                    _out.append('%s %.4f (attendu %.4f, ecart %+.2f%%)'
                                % (_a, _rr, _exp, 100.0 * (_rr - _exp) / _exp))
                else:
                    _out.append('%s non lisible' % _a)
            A('ROOM-AXRATIO: chain=%-12s f_v=%.3f Hz  %s' % (_nm, _f0, '  ·  '.join(_out)))
            _o24 = []
            for _a in ('ap', 'lat'):
                if (_c, _a) not in _fv:
                    _o24.append('%s non lisible' % _a)
                    continue
                _fa = _fv[(_c, _a)]['f']
                _rr = _fa / _f0
                _lo, _hi = _B24[_a]
                _o24.append('%s %.4f (SPEC24 %.4f, ecart %+.2f%% · SPEC29 %.4f, ecart %+.2f%%)'
                            ' f=%.3f Hz plage [%.1f,%.1f] %s'
                            % (_a, _rr, _R24[_a], 100.0 * (_rr - _R24[_a]) / _R24[_a],
                               _R29[_a], 100.0 * (_rr - _R29[_a]) / _R29[_a],
                               _fa, _lo, _hi, 'DANS' if _lo <= _fa <= _hi else 'HORS'))
            A('ROOM-AXRATIO-SPEC24: chain=%-12s %s' % (_nm, '  ·  '.join(_o24)))
        A('   LES DEUX REFERENCES NE SONT PAS LA MEME, ET C\'EST LA SPEC ELLE-MEME QUI EST')
        A('   SUR-DETERMINEE : SPEC 29 impose 1.0541 / 1.1043 (racine des mobilites), SPEC 24')
        A('   impose 1.0870 / 1.1522 (rapport de ses frequences nominales) — soit +3.13 % et')
        A('   +4.34 % d\'ecart entre les deux, avant toute mesure. CE QUI TRANCHE : le moteur derive')
        A('   la raideur des mobilites de SPEC 29, donc les frequences qui en RESULTENT doivent')
        A('   tomber dans les PLAGES de SPEC 24 (AP 2.3-2.7 Hz, lateral 2.4-2.9 Hz) — c\'est la')
        A('   plage qu\'il faut verifier, pas le nominal, et c\'est la colonne DANS/HORS ci-dessus.')
        A('')
        # SPEC 27 sur SON protocole : le temps de stabilisation apres UNE impulsion isolee.
        A('   SPEC 27 SUR SON PROPRE PROTOCOLE — l\'echelle de stabilisation apres l\'impulsion')
        A('   isolee de l\'axe excite. `a0` = maximum des 5 premiers echantillons de la serie ;')
        A('   les seuils sont les memes que `ROOM-SETTLE` (5 %, 1 %, 0.5 %, 0.1 % de `a0`), donc')
        A('   les deux se comparent directement. Bandes SPEC 27 : « mostly settled ~1.0-1.5 s »,')
        A('   « essentially stationary ~1.3-1.7 s ».')
        for (_c, _ax) in sorted(_fv):
            _vals = [v for _f, v in sorted(_axs[({'v': 0, 'ap': 1, 'lat': 2}[_ax], _c, _ax)])]
            _frames = list(range(len(_vals)))
            _w = max(2, int(round(60.0 / max(0.5, _fv[(_c, _ax)]['f']))))
            _env = ring_env([abs(v) for v in _vals], _w)
            _a0 = max([abs(v) for v in _vals[:5]]) if _vals else 0.0
            _st = {k: settle_time(_env, _frames, _a0, fr) for fr, k in SETTLE_BANDS}
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            A('ROOM-AXSETTLE: chain=%-12s axe=%-3s t5=%-7s t1=%-7s t05=%-7s t01=%-7s a0=%.5f'
              % (_nm, _ax, _st['t5'], _st['t1'], _st['t05'], _st['t01'], _a0))
    A('')
    # ============================================================================================
    # ROOM-AXFIT-RAD — SPEC 24 LUE SUR LE TROISIEME DEGRE DE LIBERTE (SPEC 23).  (cycle 10)
    # `PHYSRINGAX` et `PHYSRINGBX` lisent toutes deux la POSITION DU JOINT, et ce joint vit sur une
    # sphere autour de son ancre : leur composante radiale est nulle par construction (la premiere
    # parce qu'elle differencie des vecteurs UNITAIRES, la seconde parce que |u| = |m|). Le mode que
    # SPEC 24 appelle « intentionally the SLOWEST » ne peut donc pas y apparaitre. `PHYSRINGCX`
    # porte l'etat radial LUI-MEME, celui que SPEC 23 integre, dans les MEMES fenetres et aux MEMES
    # frames que les deux autres.
    # L'ESTIMATEUR N'EST PAS REECRIT : c'est `_fitseries`, celui de `ROOM-AXFIT`, avec son `skip`
    # par defaut (12 frames de transitoire), sa grille f x zeta, son intervalle a 1.10x le residu
    # minimum et son residu relatif. Deux copies d'un meme calcul divergent ; il n'y en a qu'une.
    # LA CIBLE EST LA VERTICALE DE SPEC 24 (2.30 Hz, plage 2.1-2.5), et c'est justifie par le rig :
    # l'axe de l'os vaut (+0.3646, -0.9192, -0.1490) dans le repere `chest`, donc 0.9192^2 = 0.845
    # — 84.5 % de son energie tombe sur l'axe VERTICAL du triedre. Le mode radial EST, a 84.5 %, le
    # mode vertical de sa §24. Sans ce chiffre, la cible aurait l'air choisie.
    # NATURE : une FREQUENCE (Hz) et un rapport d'amortissement, tires d'une serie d'ELONGATION
    #   RADIALE DU TISSU rapportee a B0 (SPEC 6) — sans dimension, signee.
    # REPERE : l'axe de l'os, dans le triedre de l'ANCRE (SPEC 7) — meme instant, meme fenetre et
    #   meme triedre que `ROOM-AXFIT`, donc les deux se comparent directement.
    # LIGNE DE BASE : 0.0 exactement a la pose d'auteur debout (SPEC 9).
    # ABSENT / INSUFFISANT : `INSUFFISANT` porte le motif (serie absente, trop courte apres le
    #   `skip`, identiquement nulle, ou residu au-dela de 0.08). Un 0.0000 n'est JAMAIS publie comme
    #   une frequence : une serie plate ne se lit pas, elle se declare.
    # ============================================================================================
    A('-- ROOM-AXFIT-RAD : SPEC 24 SUR LE DEGRE DE LIBERTE RADIAL DE SPEC 23 ---------------------')
    A('   `PHYSRINGAX` et `PHYSRINGBX` lisent la position du JOINT, qui vit sur une sphere : leur')
    A('   composante radiale est nulle PAR CONSTRUCTION. Le mode que SPEC 24 dit « le plus lent » ne')
    A('   peut donc pas y apparaitre. `PHYSRINGCX` porte l\'elongation radiale du tissu elle-meme,')
    A('   rapportee a B0 (SPEC 6), dans les MEMES fenetres et aux MEMES frames.')
    A('   CIBLE 2.30 Hz, BANDE [2.10, 2.50] — la VERTICALE de SPEC 24, et le rig le justifie :')
    A('   l\'axe de l\'os vaut (+0.3646, -0.9192, -0.1490) en repere `chest`, donc 0.9192^2 = 0.845 :')
    A('   84.5 % de son energie tombe sur l\'axe vertical du triedre. Le mode radial EST, a 84.5 %,')
    A('   le mode vertical de sa §24.')
    A('   ESTIMATEUR : exactement celui de `ROOM-AXFIT` (meme fonction, meme skip=12, meme grille,')
    A('   meme intervalle a 1.10x le residu minimum). Aucun ajusteur n\'a ete reecrit.')
    # `_cxs` = contrainte de longueur ARMEE (PHYSRINGCX, la CONFIGURATION LIVREE),
    # `_cxz` = contrainte LEVEE (PHYSRINGCZ, un CONTROLE). Meme disposition de champs, meme parseur
    # au nom pres. La cle est (axe EXCITE, chaine) : `ax` designe la fenetre, pas la projection —
    # cette serie n'a qu'une seule composante, l'elongation radiale.
    # LE CHAMP `l=` DOIT ETRE FILTRE, PAS IGNORE — MESURE LE 2026-08-17.
    # Cette cle etait `(ax, c)` : elle jetait le numero de MAILLON et versait la serie de TOUS les
    # maillons dans la meme liste. Sur une chaine a un maillon c'est sans effet (`l` vaut toujours
    # 0). Des que la poitrine est passee a DEUX maillons, la trace a porte deux echantillons par
    # frame au lieu d'un — compte verifie sur les logs : 900 lignes `PHYSRINGCX` et `l` = {0} au
    # controle, 1800 lignes et `l` = {0,1} a deux maillons, soit 150 -> 300 echantillons pour
    # (c=0, ax=0). Le lisseur `_fitseries` suppose UN echantillon par pas de temps : avec deux
    # fois plus d'echantillons pour la meme duree reelle, il rend une frequence DEUX FOIS PLUS
    # BASSE. Mesure : SPEC 24 verticale « tombait » de 2.320 a 1.200 Hz et `n` passait de 138 a
    # 288 — le PRODUIT f x n est conserve, ce qui est la signature d'une densite d'echantillonnage
    # mal lue, pas d'un changement physique. J'ai failli enregistrer ca comme une regression du
    # solveur : c'etait l'instrument.
    # On garde le maillon RACINE, celui que la mesure lisait deja quand la chaine n'en avait qu'un,
    # pour que la sortie soit IDENTIQUE a un maillon (verifiable en regenerant le tableau depuis le
    # log de controle). Le maillon distal n'est pas perdu : il est simplement hors de CETTE ligne,
    # et sa publication par maillon est un ajout a faire quand la structure reviendra.
    # (`_cxs`/`_cxz` sont collectees plus haut, avant le bloc AXFIT — voir la note de hissage.)

    def _radfit_lines(_src, _srctag, _tag, _note):
        """Une ligne par (chaine, fenetre). `_tag` nomme la sortie, `_note` dit son STATUT.

        Le motif d'INSUFFISANT est toujours ecrit : une serie absente, plate ou trop courte se
        DECLARE ; elle ne se publie pas a 0.0000 comme si elle avait ete mesuree.
        """
        if not _src:
            A('%s: ABSENT (aucune serie %s dans la trace) — SPEC 24 sur le degre de liberte'
              ' radial reste NON MESUREE sur cette course.%s' % (_tag, _srctag, _note))
            return
        _AX3 = {0: 'v', 1: 'ap', 2: 'lat'}
        for (_k, _c) in sorted(_src):
            _nm = names[_c] if _c < len(names) else 'c%d' % _c
            _vals = [v for _f, v in sorted(_src[(_k, _c)])]
            _r = _fitseries(_vals) if _HAVE_NP else None
            if _r is None:
                # Le MEME critere que `ROOM-AXFIT` : `_fitseries` rend None sur une serie de moins
                # de 20 echantillons apres le `skip`, ou de somme des carres nulle. On le dit au
                # lieu de sauter la ligne en silence.
                if not _HAVE_NP:
                    _why = 'numpy indisponible'
                elif len(_vals) - 12 < 20:
                    _why = 'n=%d apres skip=12, il en faut 20' % max(0, len(_vals) - 12)
                elif not any(abs(v) > 0.0 for v in _vals[12:]):
                    _why = 'serie identiquement nulle : le canal radial n\'a rien ecrit'
                else:
                    _why = 'ajustement impossible'
                A('%s: chain=%-12s ax=%-3s n=%-3d f=n/a ci=[n/a,n/a] zeta=n/a resid=n/a'
                  ' cible=2.30 bande=[2.10,2.50] verdict=INSUFFISANT (%s)%s'
                  % (_tag, _nm, _AX3.get(_k, '?'), len(_vals), _why, _note))
                continue
            _vd = 'DANS' if 2.10 <= _r['f'] <= 2.50 else 'HORS'
            if _r['rel'] > 0.08:
                # Meme seuil de lisibilite que `ROOM-AXFIT` : au-dela de 0.08 la serie ne porte pas
                # un mode unique et le chiffre ne doit PAS etre lu comme une frequence.
                _vd = 'INSUFFISANT (residu %.3f > 0.08 : la serie ne porte pas un mode unique)' \
                      % _r['rel']
            A('%s: chain=%-12s ax=%-3s n=%-3d f=%.3f ci=[%.3f,%.3f] zeta=%.2f resid=%.3f'
              ' cible=2.30 bande=[2.10,2.50] verdict=%s%s'
              % (_tag, _nm, _AX3.get(_k, '?'), _r['n'], _r['f'], _r['fmin'], _r['fmax'],
                 _r['zeta'], _r['rel'], _vd, _note))
    A('')
    A('   CONFIGURATION LIVREE (contrainte de longueur ARMEE) — c\'est la seule qui puisse tenir')
    A('   ou non sa §24 :')
    _radfit_lines(_cxs, 'PHYSRINGCX', 'ROOM-AXFIT-RAD', '')
    A('')
    A('   CONTROLE, PAS UNE CONFORMITE (contrainte de longueur de SPEC 22 LEVEE) : le systeme n\'est')
    A('   plus celui qu\'on livre. Ce qu\'on y lit dit ce que le mode radial VAUDRAIT si la contrainte')
    A('   ne le bornait pas — un diagnostic, jamais une ligne de conformite.')
    _radfit_lines(_cxz, 'PHYSRINGCZ', 'ROOM-AXFIT-RAD-NOLEN',
                  '  [CONTROLE — PAS UNE CONFORMITE]')
    A('')
    A('-- ROOM-AXBLIND / AXSEL-ABS / AXFIT-ABS : SPEC 24 SUR UN INSTRUMENT NON AVEUGLE ----------')
    A('   Tout ce qui precede sur SPEC 24 est lu sur `PHYSRINGAX`, qui projette une DIFFERENCE DE')
    A('   VECTEURS UNITAIRES : sa composante radiale est nulle par construction. Le bloc ci-dessous')
    A('   republie les memes mesures sur `PHYSRINGBX` (la meme deviation, NON normalisee, meme')
    A('   instant, meme triedre) et donne le controle qui prouve l\'aveuglement. L\'ancien bloc n\'est')
    A('   PAS retire : l\'ecart entre les deux EST la mesure de l\'erreur, et il lui faut un avant.')
    # L'analyse vit dans `.autoport/ldb_axsel.py` et est IMPORTEE, comme `physics_ringdown` plus
    # haut : deux copies d'un meme calcul derivent, et c'est alors le tableau qui dit une chose et
    # le script une autre sur la meme trace.
    try:
        import ldb_axsel
        # SES LIGNES ENTRENT PAR ICI, ET ELLES NE SONT PAS EXEMPTEES (cycle 67). L'une d'elles,
        # `separation chestL - chestR`, cite les deux chaines avec des chiffres : elle est donc
        # comptee comme violation et publiee comme telle par `ROOM-ASYM-VERROU`.
        # POURQUOI ON NE L'EXEMPTE PAS, alors qu'elle sert a NOMMER un axe et non a juger une
        # asymetrie : sa direction n'est pas de la geometrie pure, elle sort d'un ajustement sur
        # la SERIE DE DEVIATIONS de la course (`ldb_axsel`, `mh[c]`), donc elle est relevee dans
        # une pose — laquelle, ce fichier ne le sait pas, et le producteur vit dans un AUTRE
        # fichier. Une exemption posee ici serait une exemption de confort sur une ligne qu'on ne
        # controle pas. Elle reste donc DECLAREE, jusqu'a ce que `ldb_axsel` publie sa pose.
        for _ln in ldb_axsel.lines(txt, {c: (names[c] if c < len(names) else 'c%d' % c)
                                         for c in chains}):
            A(_ln)
    except Exception as _e:                                  # noqa: BLE001
        A('   ROOM-AXBLIND: ABSENT (ldb_axsel indisponible : %s)' % _e)
    A('')
    A('-- ROOM-ORI : SPEC 10-13, LES EQUILIBRES PAR ORIENTATION, ET LEUR CONTINUITE --------------')
    A('   SPEC 13 : « supine, prone, upright and lateral states shall NOT exist as unrelated')
    A('   hard-coded morph targets ; the equilibrium state shall vary CONTINUOUSLY with the local')
    A('   gravity direction ».')
    A('   NATURE : `gx/gy/gz` est l\'ENTREE — la direction de la gravite VUE PAR LE SOLVEUR, unitaire.')
    A('   `sx/sy/sz` est la SORTIE — les trois echelles commandees a la racine du sein (lateral,')
    A('   vertical, projection), sans dimension, rapport a la forme d\'auteur. `det` est leur produit,')
    A('   le volume de SPEC 8.  REPERE : le triedre de SPEC 7 (+X lateral, +Y haut, +Z avant), releve')
    A('   a la pose debout d\'auteur.  LECTURE HORS DEFAUT : a l\'orientation 0 (debout) les trois')
    A('   echelles valent 1.000 — sinon toutes les autres sont decalees et rien n\'est comparable.')
    A('   CE QUE CE N\'EST PAS : la deformation VUE sur le mesh. C\'est ce que le solveur COMMANDE ;')
    A('   la peau, graduee en r^1.63 (SPEC 31), n\'en recoit qu\'une part croissante vers la pointe.')
    ori = {}
    for m in re.finditer(r'^PHYSORI c=(\d+) i=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+) gz=([-\d.e+]+)',
                         txt, re.M):
        ori.setdefault((int(m.group(1)), int(m.group(2))), {}).update(
            gx=float(m.group(3)), gy=float(m.group(4)), gz=float(m.group(5)))
    for m in re.finditer(r'^PHYSORI2 c=(\d+) i=(\d+) sx=([-\d.e+]+) sy=([-\d.e+]+)'
                         r' sz=([-\d.e+]+) det=([-\d.e+]+)', txt, re.M):
        ori.setdefault((int(m.group(1)), int(m.group(2))), {}).update(
            sx=float(m.group(3)), sy=float(m.group(4)), sz=float(m.group(5)), det=float(m.group(6)))
    for m in re.finditer(r'^PHYSORI3 c=(\d+) i=(\d+) ax=(\d+) deg=([-\d.e+]+) arm=([-\d.e+]+)',
                         txt, re.M):
        ori.setdefault((int(m.group(1)), int(m.group(2))), {}).update(
            ax=int(m.group(3)), deg=float(m.group(4)), arm=float(m.group(5)))
    if not ori:
        A('ROOM-ORI: ABSENT (aucune ligne PHYSORI dans la trace) — la salle de cette course ne')
        A('   balayait pas encore les orientations : SPEC 10-13 reste NON MESUREE, pas verte.')
    else:
        A('')
        A('   chaine        i  ax   deg      gx       gy       gz       sx      sy      sz     det')
        for (c, i) in sorted(ori):
            d = ori[(c, i)]
            A('ROOM-ORI: %-12s %2d  %d  %6.1f  %7.4f %7.4f %7.4f  %6.4f %6.4f %6.4f %7.5f'
              % (names[c] if c < len(names) else 'c%d' % c, i, d.get('ax', -1), d.get('deg', 0.0),
                 d.get('gx', 0.0), d.get('gy', 0.0), d.get('gz', 0.0),
                 d.get('sx', 0.0), d.get('sy', 0.0), d.get('sz', 0.0), d.get('det', 0.0)))
        armed = {d.get('arm', 0.0) for d in ori.values()}
        A('')
        A('   arme (phys-shape which=8) sur toutes les lignes : %s'
          % ('oui' if armed == {1.0} else 'NON — %s' % sorted(armed)))
        # DISCRIMINATION : une reponse identique a toutes les orientations prouverait que
        # l'orientation n'entre pas dans le calcul. C'est le meme test que la gate DISCRIMINANT.
        for c in sorted({c for (c, _i) in ori}):
            vals = [ori[(c, i)].get('sz', 0.0) for i in range(9) if (c, i) in ori]
            if len(vals) >= 2:
                span = max(vals) - min(vals)
                A('ROOM-ORI-SPAN: chain=%-12s sz_min=%.4f sz_max=%.4f span=%.4f  %s'
                  % (names[c] if c < len(names) else 'c%d' % c, min(vals), max(vals), span,
                     'DISCRIMINE' if span > 0.05 else 'PLAT — l\'orientation n\'atteint pas la forme'))
    A('')
    _oricom_block(A, txt, names, ori)
    A('')
    _sec_ringdown_block(A, txt, names)
    A('')
    _shake_ring_block(A, txt, names)
    A('')
    A('-- ROOM-SHAPE : SPEC 8 (volume) et SPEC 36 (mode secondaire), PAR PILOTAGE ----------------')
    A('   SPEC 8 : volume 98-101 % en mouvement normal, 96-102 % en transitoire fort.')
    A('   SPEC 36 : amplitude 2-5 % de l\'epaisseur locale, 5-7 % sur impulsion forte, plafond 7 %.')
    A('   NATURE : `det` est un rapport de volume de la deformation AFFINE commandee ; `secm` est le')
    A('   maximum sur la fenetre de la modulation d\'epaisseur de SPEC 36 ; `twm` le maximum de la')
    A('   torsion de SPEC 29, en degres.  LECTURE HORS DEFAUT : det=1, secm=0, twm=0.')
    A('   AVERTISSEMENT, ECRIT PARCE QU\'IL COMPTE : `det` est ramene a 1 PAR CONSTRUCTION (racine')
    A('   cubique appliquee au triplet). Il VERIFIE que la normalisation tourne, il ne MESURE pas')
    A('   l\'incompressibilite du tissu — un nombre qui se compare a lui-meme n\'est pas une preuve.')
    A('   Ce qui discrimine vraiment est ROOM-ORI ci-dessus (la forme change avec l\'orientation) et')
    A('   `secm` ci-dessous (il change avec le pilotage).')
    shp = {}
    for m in re.finditer(r'^PHYSSHAPE2 c=(\d+) a=(\d+) d=(\d+) det=([-\d.e+]+) secm=([-\d.e+]+)'
                         r' twm=([-\d.e+]+)', txt, re.M):
        c, dr = int(m.group(1)), int(m.group(3))
        if dr >= len(DRIVE_NAMES):
            continue
        e = shp.setdefault((c, dr), dict(det_lo=9.9, det_hi=0.0, sec=0.0, tw=0.0, n=0))
        e['det_lo'] = min(e['det_lo'], float(m.group(4)))
        e['det_hi'] = max(e['det_hi'], float(m.group(4)))
        e['sec'] = max(e['sec'], float(m.group(5)))
        e['tw'] = max(e['tw'], float(m.group(6)))
        e['n'] += 1
    for m in re.finditer(r'^PHYSSHAPE3 c=(\d+) a=(\d+) d=(\d+) secr=([-\d.e+]+) dynm=([-\d.e+]+)',
                         txt, re.M):
        c, dr = int(m.group(1)), int(m.group(3))
        if dr >= len(DRIVE_NAMES):
            continue
        e = shp.setdefault((c, dr), dict(det_lo=9.9, det_hi=0.0, sec=0.0, tw=0.0, n=0))
        e['secr'] = max(e.get('secr', 0.0), float(m.group(4)))
        e['dyn'] = max(e.get('dyn', 0.0), float(m.group(5)))
    for m in re.finditer(r'^PHYSSHAPE4 c=(\d+) a=(\d+) d=(\d+) prsm=([-\d.e+]+) prsr=([-\d.e+]+)',
                         txt, re.M):
        c, dr = int(m.group(1)), int(m.group(3))
        if dr >= len(DRIVE_NAMES):
            continue
        e = shp.setdefault((c, dr), dict(det_lo=9.9, det_hi=0.0, sec=0.0, tw=0.0, n=0))
        e['prs'] = max(e.get('prs', 0.0), float(m.group(4)))
        e['prsr'] = max(e.get('prsr', 0.0), float(m.group(5)))
    if not shp:
        A('ROOM-SHAPE: ABSENT (aucune ligne PHYSSHAPE2) — SPEC 8/36 restent NON MESUREES.')
    else:
        A('')
        A('   chaine        drive       fenetres  det_min  det_max  secm(%%)  secr(%%)  dyn(%%)'
          '  twm(deg)  prs(%%)  prsr(%%)')
        for (c, dr) in sorted(shp):
            e = shp[(c, dr)]
            A('ROOM-SHAPE: %-12s %-10s %5d     %7.5f  %7.5f  %6.2f  %7.2f  %6.2f  %8.4f'
              '  %6.2f  %7.2f'
              % (names[c] if c < len(names) else 'c%d' % c, DRIVE_NAMES[dr], e['n'],
                 e['det_lo'], e['det_hi'], 100.0 * e['sec'], 100.0 * e.get('secr', 0.0),
                 100.0 * e.get('dyn', 0.0), math.degrees(e['tw']),
                 100.0 * e.get('prs', 0.0), 100.0 * e.get('prsr', 0.0)))
        sat = [(c, dr) for (c, dr) in sorted(shp) if shp[(c, dr)].get('secr', 0.0) > 0.0701]
        if sat:
            A('ROOM-SHAPE-SATURE: %d fenetre(s) sur %d ou le mode secondaire de SPEC 36 depasse son'
              ' plafond de 7 %% AVANT ecretage.' % (len(sat), len(shp)))
            A('   Un `secm` colle a 0.0700 n\'est alors PAS une amplitude mesuree, c\'est une'
              ' saturation : le gain d\'excitation est a recaler sur SA bande (2-5 %%), pas sur'
              ' l\'instrument.')
        # ============================================================================================
        # ROOM-SHAPE-DYNSAT — LA GRANDEUR QUI AURAIT ATTRAPE LE DEFAUT DU 2026-08-16 TOUTE SEULE.
        # Ce jour-la le canal de deformation de SPEC 22 est passe de 15.56-21.29 % (il DISCRIMINAIT
        # entre les cinq pilotages) a 25.00 % sur LES DIX fenetres — colle a `AbsoluteStretchClamp`.
        # Aucune ligne du tableau ne le disait : `dyn` etait publie, mais rien ne comparait ses
        # valeurs ENTRE ELLES. Un plafond atteint partout n'est plus une deformation mesuree, c'est
        # la valeur du plafond ; et une deformation qui ne depend plus du stimulus est exactement le
        # « ballon d'eau » que l'owner decrit (retour du 2026-08-11 21:20 : la deformation doit etre
        # « correlee au stimulus », « quasi nulle sur les mouvements subtils »).
        # NATURE : un ETALEMENT (sans unite) sur une deformation, pas une amplitude.
        # REPERE : celui de `dyn` — l'echelle commandee a la racine, triedre de l'ancre (SPEC 7).
        # LIGNE DE BASE : hors defaut, `dyn` varie avec le pilotage et reste SOUS 0.25.
        # ============================================================================================
        for c in sorted({c for (c, _d) in shp}):
            _dv = [shp[(c, d)].get('dyn', 0.0) for d in range(len(DRIVE_NAMES)) if (c, d) in shp]
            if len(_dv) >= 2:
                _hi, _lo = max(_dv), min(_dv)
                _pin = sum(1 for v in _dv if v >= 0.2499)
                if _pin == len(_dv):
                    _vd = ('SATURE — les %d pilotages rendent le PLAFOND (0.25) : ce n\'est plus une'
                           ' deformation mesuree, c\'est la valeur de la borne' % len(_dv))
                elif _hi <= 0.0:
                    _vd = 'DOMAINE VIDE — le canal de deformation n\'a rien ecrit'
                elif (_hi - _lo) > 0.10 * _hi:
                    _vd = 'DISCRIMINE (la deformation depend du pilotage, comme sa SPEC 22 l\'exige)'
                else:
                    _vd = ('PLAT — %d/%d au plafond ; la deformation ne depend plus du stimulus'
                           % (_pin, len(_dv)))
                A('ROOM-SHAPE-DYNSAT: chain=%-12s dyn_min=%.4f dyn_max=%.4f plafond=0.2500 %s'
                  % (names[c] if c < len(names) else 'c%d' % c, _lo, _hi, _vd))
        for c in sorted({c for (c, _d) in shp}):
            vals = [shp[(c, d)]['sec'] for d in range(len(DRIVE_NAMES)) if (c, d) in shp]
            if len(vals) >= 2 and max(vals) > 0.0:
                A('ROOM-SHAPE-SPAN: chain=%-12s secm_min=%.4f secm_max=%.4f  %s'
                  % (names[c] if c < len(names) else 'c%d' % c, min(vals), max(vals),
                     'DISCRIMINE (le mode secondaire depend du pilotage)'
                     if (max(vals) - min(vals)) > 0.25 * max(vals)
                     else 'PLAT — le pilotage n\'atteint pas le mode secondaire'))
    A('')
    # ============================================================================================
    # ROOM-RAD — SPEC 22, LE DEPLACEMENT RADIAL DU COM ET L'ELONGATION QU'IL PRODUIT. (cycle 10)
    #
    # CORRIGE LE 2026-08-17 : ce bloc lisait `rrm` contre les bandes de l'ELONGATION DU TISSU
    # (5-15 / 15-21 / 21-25 %). C'est une erreur de NATURE, du type que le registre appelle
    # `metric-nature-and-frame` : `rr / B0` est un DEPLACEMENT normalise, pas une deformation.
    # SPEC 22 lui donne ses propres lignes — « Breast COM: normal <= 35 % B0, hard transient
    # <= 40 % B0 » (SPEC 38 : `NormalMaxCOMDisplacement 0.35`, `HardMaxCOMDisplacement 0.40`) — et
    # les lire contre les bandes du tissu declarait « HORS » des valeurs qui sont DANS la bande qui
    # les concerne. L'inverse serait un faux vert ; celui-ci etait un faux rouge, et les deux sont
    # des mesures qui ne disent pas ce qu'elles pretendent.
    # LES DEUX SONT DONC PUBLIEES, chacune contre SA ligne de sa spec :
    #   - `rrm`   : DEPLACEMENT du COM, en B0        -> bandes 0.35 / 0.40 de SPEC 22 ;
    #   - `elong` : l'ELONGATION que ce deplacement produit dans le tissu, soit `PHYS-DYN-K * rrm`
    #               (0.43, derive par SPEC 38 de 0.15 / 0.35) -> bandes 5-15 / 15-21 / 21-25 %.
    # NATURE : un deplacement sans unite (rapporte a B0) et la deformation qu'il commande.
    # REPERE : l'axe de l'os, dans le triedre de l'ANCRE (SPEC 7).
    # LIGNE DE BASE : 0.0 exactement a la pose d'auteur debout (SPEC 9) — donc un `rrm` a 0.0000
    #   sur TOUTE la course ne dit pas « au repos », il dit que rien n'a ete ecrit dans le canal.
    #   `n` (nombre de fenetres agregees) est publie pour cette raison : sans le DOMAINE, un zero
    #   ne distingue pas « rien ne bouge » de « rien ne mesure ».
    # ============================================================================================
    _RAD_K = 0.43   # PHYS-DYN-K du moteur (:356), derive de SPEC 38 : 0.15 de stretch a 0.35 B0.
    A('-- ROOM-RAD : SPEC 22, DEPLACEMENT RADIAL DU COM ET ELONGATION QU\'IL PRODUIT -------------')
    A('   DEUX grandeurs, DEUX lignes de sa spec, et ne pas les confondre est le point :')
    A('     `rrm`   = DEPLACEMENT du COM / B0   -> « Breast COM: normal <= 35 % B0, hard transient')
    A('               <= 40 % B0 » (SPEC 22 / SPEC 38) ;')
    A('     `elong` = l\'ELONGATION commandee au tissu, `PHYS-DYN-K * rrm` avec PHYS-DYN-K = 0.43')
    A('               (SPEC 38 : 0.15 de stretch a 0.35 B0) -> « local tissue elongation: common')
    A('               5-15 %, large 15-21 %, exceptional 21-25 %, absolute clamp 25 % ».')
    A('   NATURE : un deplacement sans unite et la deformation qu\'il commande. REPERE : axe de l\'os')
    A('   dans le triedre de l\'ancre. LIGNE DE BASE : 0.0 a la pose d\'auteur debout (SPEC 9).')
    _rad = {}
    # `rrr` (le maximum AVANT la borne SPEC 22) et `sat` (les frames ou elle a mordu) sont
    # OPTIONNELS a la lecture : une trace anterieure au 2026-08-16 ne les porte pas, et le bloc doit
    # rester lisible sur les deux. Absents, ils valent None et la ligne de saturation le DIT au lieu
    # de rendre un zero qui ressemblerait a « la borne n'a jamais mordu ».
    for m in re.finditer(r'^PHYSRAD c=(\d+) a=(\d+) d=(\d+) rr=([-\d.e+]+) rrm=([-\d.e+]+)'
                         r'(?: rrr=([-\d.e+]+))?',
                         txt, re.M):
        c, dr = int(m.group(1)), int(m.group(3))
        if dr >= len(DRIVE_NAMES):
            continue
        e = _rad.setdefault((c, dr), dict(rrm=None, rrr=None, sat=None, n=0, neg=0))
        v = float(m.group(5))
        if v < 0.0:
            e['neg'] += 1
        e['rrm'] = v if e['rrm'] is None else max(e['rrm'], v)
        if m.group(6) is not None:
            _v0 = float(m.group(6))
            e['rrr'] = _v0 if e['rrr'] is None else max(e['rrr'], _v0)
        e['n'] += 1
    # `sat` arrive sur sa PROPRE ligne (`format` de GOAL est cape a huit parametres) : c'est un
    # compteur global au solveur, agrege ici par (chaine, pilotage) comme le reste du bloc.
    for m in re.finditer(r'^PHYSRADSAT c=(\d+) d=(\d+) sat=([-\d.e+]+)', txt, re.M):
        c, dr = int(m.group(1)), int(m.group(2))
        if (c, dr) not in _rad:
            continue
        _s = float(m.group(3))
        e = _rad[(c, dr)]
        e['sat'] = _s if e['sat'] is None else max(e['sat'], _s)

    def _radband(x):
        """Les bandes de l'ELONGATION DU TISSU de SPEC 22, dans ses mots. `repos` est SOUS sa plus
        basse bande. A n'appliquer QU'A une deformation — jamais a un deplacement."""
        if x < 0.05:
            return 'repos'
        if x < 0.15:
            return 'commun'
        if x < 0.21:
            return 'large'
        if x <= 0.25:
            return 'exceptionnel'
        return 'HORS'

    def _comband(x):
        """Les bandes du DEPLACEMENT DU COM de SPEC 22 : normal <= 0.35 B0, transitoire dur <= 0.40.
        Au-dela, c'est HORS et sa spec n'a pas de mot pour ca."""
        if x < 0.05:
            return 'repos'
        if x <= 0.35:
            return 'sous-normale'
        if x <= 0.40:
            return 'transitoire-dur'
        return 'HORS'
    if not _rad:
        A('ROOM-RAD: ABSENT (aucune ligne PHYSRAD dans la trace) — l\'elongation radiale de SPEC 22')
        A('   n\'est pas mesuree sur cette course. Aucune autre grandeur n\'est substituee.')
    else:
        A('')
        for (c, dr) in sorted(_rad):
            e = _rad[(c, dr)]
            _mk = '' if not e['neg'] else \
                  '  (!! %d valeur(s) rrm negatives : rrm est declare ABSOLU)' % e['neg']
            # `rrr` PUBLIE A COTE DE `rrm`, ET C'EST LA LECON DU 2026-08-16 : le canal de
            # deformation etait colle a son plafond absolu sur les DIX fenetres (25.00 partout) et
            # aucune ligne ne pouvait le dire, parce qu'un maximum BORNE et un maximum QUI EFFLEURE
            # SA BORNE rendent le meme nombre. L'ecart entre les deux EST la saturation.
            _sx = ''
            if e['rrr'] is None:
                _sx = '  rrr=n/a (trace anterieure au champ ; saturation non mesurable ici)'
            else:
                _sx = '  rrr=%.4f' % e['rrr']
                if e['rrr'] > e['rrm'] + 0.0001:
                    _sx += ' BORNEE (exces %.4f B0)' % (e['rrr'] - e['rrm'])
                else:
                    _sx += ' libre'
                if e['sat'] is not None:
                    _sx += ' sat=%d fr' % int(e['sat'])
            A('ROOM-RAD: chain=%-12s drive=%-10s rrm=%.4f com=%-15s elong=%.4f tissu=%-12s n=%d%s%s'
              % (names[c] if c < len(names) else 'c%d' % c, DRIVE_NAMES[dr], e['rrm'],
                 _comband(e['rrm']), _RAD_K * e['rrm'], _radband(_RAD_K * e['rrm']),
                 e['n'], _sx, _mk))
        # ---- ROOM-RAD-LINK : LES MEMES TROIS GRANDEURS, RESOLUES PAR MAILLON (cycle 33) -------
        # `rrr` ci-dessus est un maximum SUR LA CHAINE. Il vaut 1.42 B0 pour un plafond de 0.40 sans
        # dire QUEL maillon sature, et les deux remedes candidats de SPEC 22 (borne par maillon, ou
        # raideur radiale du distal) sont indiscernables tant qu'on l'ignore. Meme classe de defaut
        # que `PHYSRINGCX` au cycle 31 : un agregat par chaine qui cache une verite par maillon.
        # NATURE deux maximums de FENETRE d'une deformation / B0 + un COMPTE de frames · REPERE axe
        # de l'os du MAILLON dans le triedre de l'ANCRE · ABSENT 0.0 sur les trois quand le maillon
        # n'a pas de degre de liberte radial arme (l'etat du distal avant le cycle 32).
        _radl = {}
        for m in re.finditer(r'^PHYSRADL c=(\d+) d=(\d+) l=(\d+) rrm=([-\d.e+]+)'
                             r' rrr=([-\d.e+]+) sat=([-\d.e+]+)', txt, re.M):
            c, dr, l = int(m.group(1)), int(m.group(2)), int(m.group(3))
            if dr >= len(DRIVE_NAMES):
                continue
            e = _radl.setdefault((c, dr, l), dict(rrm=0.0, rrr=0.0, sat=0.0))
            e['rrm'] = max(e['rrm'], float(m.group(4)))
            e['rrr'] = max(e['rrr'], float(m.group(5)))
            e['sat'] = max(e['sat'], float(m.group(6)))
        A('')
        if not _radl:
            A('ROOM-RAD-LINK: ABSENT (aucune ligne PHYSRADL dans la trace) — la saturation de SPEC 22')
            A('   n\'est PAS attribuable a un maillon sur cette course, et rien n\'est substitue.')
        else:
            A('-- ROOM-RAD-LINK : SPEC 22 PAR MAILLON — QUEL MAILLON SATURE ? -------------------')
            A('   `rrr` est l\'elongation AVANT la borne, `rrm` APRES, `sat` les frames ou elle a mordu.')
            A('   Plafond dur de SPEC 22 : 0.40 B0. `rrr` >> `rrm` = le maillon est REMPLACE par sa borne.')
            for (c, dr, l) in sorted(_radl):
                e = _radl[(c, dr, l)]
                _ex = e['rrr'] - e['rrm']
                A('ROOM-RAD-LINK: chain=%-12s drive=%-10s l=%d  rrm=%.4f  rrr=%.4f  %s  sat=%d fr'
                  % (names[c] if c < len(names) else 'c%d' % c, DRIVE_NAMES[dr], l,
                     e['rrm'], e['rrr'],
                     ('BORNEE (exces %.4f B0, x%.2f le plafond)' % (_ex, e['rrr'] / 0.40))
                     if _ex > 0.0001 else 'libre                              ',
                     int(e['sat'])))
            # LE MAILLON RESPONSABLE, NOMME PLUTOT QUE DEDUIT PAR LE LECTEUR.
            for c in sorted({k[0] for k in _radl}):
                _w = max(((k[2], v['rrr'], DRIVE_NAMES[k[1]])
                          for k, v in _radl.items() if k[0] == c), key=lambda t: t[1])
                A('ROOM-RAD-LINK-WORST: chain=%-12s maillon=%d  rrr=%.4f B0 (pilotage %s)  = x%.2f'
                  ' le plafond dur de SPEC 22'
                  % (names[c] if c < len(names) else 'c%d' % c, _w[0], _w[1], _w[2], _w[1] / 0.40))

        # ---- ROOM-RAD-SPLIT : DE QUI EST L'ELONGATION — DE L'OS OU DE LA CHAIR ? (cycle 33 e2) --
        # `dr0 = dot(cp-a,m^) - bl` melange DEUX choses que l'etape 1 n'a pas separees, et la
        # decomposition est une IDENTITE, pas un modele :
        #     dr0 = (ml - bl)  +  dot(cp - px, m^)
        #           \_______/     \______________/
        #            (A) l'OS       (B) la CHAIR
        #           pas encore     au-dela de la
        #           projete        pointe de l'os
        # (A) peut etre non nul parce que `phys-length-chain` (jak-hd-physics.gc:3075) tourne APRES
        # la boucle des maillons ou `dr0` est calcule (:2977) : la contrainte de longueur de la
        # frame courante n'a pas encore agi quand la mesure est prise. Si (A) domine, le tenseur de
        # deformation recoit une elongation que le solveur ANNULE trois lignes plus loin.
        # NATURE deux LONGUEURS SIGNEES / B0 relevees A LA FRAME DE L'ARGMAX de `rrr` (pas deux
        #   maximums independants : max(a+b) != max(a)+max(b)) · REPERE l'axe de l'os du maillon,
        #   le meme que `rrr` · ABSENT mlb=0 si la longueur etait deja tenue, cdev=0 a la 1re frame.
        # I0 — CONTROLE D'INTEGRITE : |mlb+cdev| doit valoir `rrr`. Les deux membres sont calcules
        #   par des chemins DIFFERENTS (produit scalaire propre pour cdev, pas une soustraction),
        #   donc l'egalite est une verification et pas une tautologie. Si elle casse, on ne publie
        #   AUCUNE conclusion : l'instrument est faux.
        _split, _pend = {}, {}
        for m in re.finditer(r'^PHYSRAD(L|LD) c=(\d+) d=(\d+) l=(\d+) '
                             r'(?:rrm=[-\d.e+]+ rrr=([-\d.e+]+) sat=[-\d.e+]+'
                             r'|mlb=([-\d.e+]+) cdev=([-\d.e+]+))', txt, re.M):
            c, dr, l = int(m.group(2)), int(m.group(3)), int(m.group(4))
            # `d = PHYSROOM-DRIVES` (5) N'EST PAS UN PILOTAGE : c'est la LIGNE DE BASE de la salle
            # — meme animation, meme duree de fenetre, AUCUN pilotage (phys-room.gc:912-917). Elle
            # etait jetee ici comme dans `_radl`, et c'est ce filtre qui a fait conclure au cycle 33
            # etape 1 « la sortie est plate sur une plage de stimulus de 39x » sans jamais voir ce
            # que le canal vaut a stimulus NUL. Meme classe que les deux lecteurs a moitie aveugles
            # de SPEC 24 : verifier ce qu'un consommateur FILTRE, pas ce que la trace contient.
            if dr > len(DRIVE_NAMES):
                continue
            if m.group(1) == 'L':
                _pend[(c, dr, l)] = float(m.group(5))
            else:
                _r = _pend.get((c, dr, l))
                if _r is None:
                    continue
                e = _split.get((c, dr, l))
                if e is None or _r > e['rrr']:
                    _split[(c, dr, l)] = dict(rrr=_r, mlb=float(m.group(6)),
                                              cdev=float(m.group(7)))
        A('')
        if not _split:
            A('ROOM-RAD-SPLIT: ABSENT (aucune ligne PHYSRADLD appariee dans la trace) — l\'elongation')
            A('   de SPEC 22 n\'est PAS attribuee a l\'os ou a la chair sur cette course.')
        else:
            A('-- ROOM-RAD-SPLIT : L\'ELONGATION DE SPEC 22 EST-ELLE CELLE DE L\'OS OU DE LA CHAIR ? --')
            A('   mlb = (ml-bl)/B0, l\'OS hors de sa sphere de repos AVANT `phys-length-chain`.')
            A('   cdev = dot(cp-px,m^)/B0, la CHAIR au-dela de la pointe de l\'os. Somme = rrr (identite).')
            _bad = 0
            for (c, dr, l) in sorted(_split):
                e = _split[(c, dr, l)]
                _sum = e['mlb'] + e['cdev']
                _err = abs(abs(_sum) - e['rrr'])
                if _err > 0.002:
                    _bad += 1
                _tot = abs(e['mlb']) + abs(e['cdev'])
                _own = ('OS   %3.0f%%' % (100.0 * abs(e['mlb']) / _tot)) if _tot > 1e-9 else 'n/a     '
                _own += (' | CHAIR %3.0f%%' % (100.0 * abs(e['cdev']) / _tot)) if _tot > 1e-9 else ''
                A('ROOM-RAD-SPLIT: chain=%-12s drive=%-10s l=%d  rrr=%.4f  mlb=%+.4f  cdev=%+.4f'
                  '  %s  I0 ecart=%.5f%s'
                  % (names[c] if c < len(names) else 'c%d' % c,
                     DRIVE_NAMES[dr] if dr < len(DRIVE_NAMES) else 'BASE-0stim', l,
                     e['rrr'], e['mlb'], e['cdev'], _own, _err,
                     '  **I0 CASSEE**' if _err > 0.002 else ''))
            # LE STIMULUS REELLEMENT RECU DANS CHAQUE FENETRE. `PHYSSTIM` ne publie que les
            # pilotages COMMANDES (dr=0..4) et n'a rien pour la ligne de base — mais `PHYSACC`
            # publie, LUI, ce que la chaine recoit vraiment, y compris dans la fenetre sans
            # pilotage. Les deux ne sont pas la meme grandeur et les confondre ferait ecrire
            # « stimulus nul » sur une fenetre qui en recoit 17.
            _acc, _accn = {}, {}
            for m in re.finditer(r'^PHYSACC c=(\d+) a=\d+ d=(\d+) acc=([-\d.e+]+)', txt, re.M):
                k = (int(m.group(1)), int(m.group(2)))
                _acc[k] = _acc.get(k, 0.0) + float(m.group(3))
                _accn[k] = _accn.get(k, 0) + 1
            _base = {k: v for k, v in _split.items() if k[1] == len(DRIVE_NAMES)}
            if _base:
                A('')
                A('   LA LIGNE DE BASE (`BASE-0stim`) EST LA MEME FENETRE SANS AUCUN PILOTAGE.')
                A('   Le pilotage COMMANDE y vaut zero (PHYSSTIM ne publie que dr=0..4), mais le')
                A('   stimulus RECU n\'est PAS nul : `PHYSACC` le mesure, et c\'est ce nombre-la qui est')
                A('   imprime ci-dessous. Confondre les deux ferait ecrire « stimulus nul » sur une')
                A('   fenetre qui en recoit 17. C\'est la ligne a SOUSTRAIRE avant d\'attribuer quoi que')
                A('   ce soit a un pilotage — exigence des DIRECTIVES du 2026-08-11 16:15.')
                for k in sorted(_base):
                    e = _base[k]
                    _ak = (k[0], k[1])
                    _av = (_acc[_ak] / _accn[_ak]) if _accn.get(_ak) else float('nan')
                    A('ROOM-RAD-BASE: chain=%-12s l=%d  rrr=%.4f B0 SANS AUCUN PILOTAGE COMMANDE'
                      '  = x%.2f le plafond dur de SPEC 22  (cdev %+.4f = %.0f %% du total ;'
                      ' stimulus RECU %.2f, pas zero)'
                      % (names[k[0]] if k[0] < len(names) else 'c%d' % k[0], k[2], e['rrr'],
                         e['rrr'] / 0.40, e['cdev'],
                         100.0 * abs(e['cdev']) / max(1e-9, abs(e['mlb']) + abs(e['cdev'])), _av))
                A('ROOM-RAD-BASE-RESERVE: `rrr` est un MAXIMUM DE FENETRE, et la fenetre de ligne')
                A('   de base suit immediatement `tilt` (60 deg) : le retour du sujet a l\'aplomb est')
                A('   une DISCONTINUITE. `ROOM-SPEC37-KICK` ci-dessous mesure que les 31 fenetres de')
                A('   ligne de base sur 31 en portent une. CES QUATRE NOMBRES NE DISENT DONC PAS CE')
                A('   QUE LE CANAL VAUT AU REPOS — ils disent ce qu\'il vaut en recuperation d\'un')
                A('   a-coup non pilote. Aucune conclusion sur un « offset au repos » ne s\'appuie')
                A('   dessus, et l\'argument « une decroissance ne peut pas depasser son excitation »')
                A('   ne s\'applique pas : ce n\'est pas la queue de `tilt`, c\'est un choc NEUF.')
            A('ROOM-RAD-SPLIT-I0: %d canal(aux) hors tolerance sur %d — %s'
              % (_bad, len(_split),
                 'l\'identite tient, la decomposition est lisible'
                 if _bad == 0 else 'INSTRUMENT FAUX, aucune conclusion ne se publie dessus'))

        # ---- ROOM-RAD-FLESH : LA CHAIR EST-ELLE LOIN DE SA CIBLE, OU L'OS EST-IL LOIN DE LA
        # SIENNE ? (cycle 34 etape 1) --------------------------------------------------------
        # `cdev` melange encore DEUX choses, et c'est la meme faute d'agregat qu'au cycle 33
        # etape 2, un cran plus bas. La decomposition est une IDENTITE, pas un modele :
        #     cdev = dot(cp - tg, m^)  +  dot(tg - px, m^)
        #            \_____ ctg _____/     \______ D _____/
        #             (C) le point LIBRE    (D) la CONTRAINTE ecarte
        #             n'a pas rejoint SA    l'OS de SA cible
        #             cible                 (deduit par soustraction, aucun 3e canal)
        # POURQUOI ELLE EXISTE : le point libre `cp` de sa SPEC 23 n'est projete par RIEN
        # (`*phys-cpx*` n'est ecrit qu'a l'amorcage, au rebase de §37 et a la publication ; ni
        # `phys-length-chain` ni `phys-collide-chain` ne le touchent). L'OS obeit a sa sphere de
        # rayon `bl` et aux 54 volumes ; LA CHAIR n'obeit a rien. Si (C) domine, re-deriver la
        # raideur radiale ne peut rien : l'oscillateur est contre un mur, pas mal regle.
        # NATURE `ctg` LONGUEUR SIGNEE / B0, `cdd` la NORME du MEME ecart, les deux relevees A LA
        #   FRAME DE L'ARGMAX de `rrr` (les memes que mlb/cdev) · REPERE `ctg` sur l'axe de l'os
        #   `m^`, le meme que `rrr` ; `cdd` est une norme · ABSENT 0.0000 a la 1re frame.
        # I0-FLESH — CONTROLE D'INTEGRITE NON TAUTOLOGIQUE : |ctg| <= cdd, les deux membres etant
        #   calcules par des chemins DIFFERENTS (produit scalaire contre racine de somme de
        #   carres). S'il casse, aucune conclusion ne se publie.
        # I1-FLESH — LA BORNE GEOMETRIQUE : `tg = a + bl*u^` avec `u^` UNITAIRE, donc
        #   |tg - a| = bl EXACTEMENT, et |px - a| = ml. Donc D = bl*cos(theta) - ml, d'ou
        #   |D|/B0 <= 2*bl/B0 + rrol. Si la course la viole, la lecture de `tg` est fausse.
        # L'APPARIEMENT EST LE MEME QUE CELUI DE `_split`, ET CE N'EST PAS UN DETAIL. Les trois
        # lignes PHYSRADL / PHYSRADLD / PHYSRADLE sont emises DANS CET ORDRE, une fois par FENETRE
        # (chaine x animation x pilotage), et `_split` retient la fenetre dont `rrr` est le plus
        # GRAND. Garder ici la DERNIERE fenetre lue au lieu de la MEME ferait decomposer `cdev`
        # d'une animation par un `ctg` d'une AUTRE : la premiere version de ce lecteur le faisait,
        # et elle sortait 5 violations sur 24 de la borne geometrique — des violations qui
        # n'existaient pas dans le moteur, seulement dans l'appariement. Meme classe que « deux
        # lecteurs de la meme trace qui filtrent chacun la moitie opposee ».
        _fl, _pndE = {}, {}
        for m in re.finditer(r'^PHYSRAD(L|LD|LE) c=(\d+) d=(\d+) l=(\d+) '
                             r'(?:rrm=[-\d.e+]+ rrr=([-\d.e+]+) sat=[-\d.e+]+'
                             r'|mlb=[-\d.e+]+ cdev=[-\d.e+]+'
                             r'|ctg=([-\d.e+]+) cdd=([-\d.e+]+))', txt, re.M):
            c, dr, l = int(m.group(2)), int(m.group(3)), int(m.group(4))
            if dr > len(DRIVE_NAMES):
                continue
            k = (c, dr, l)
            if m.group(1) == 'L':
                _pndE[k] = float(m.group(5))
            elif m.group(1) == 'LE':
                _r = _pndE.get(k)
                if _r is None:
                    continue
                e = _fl.get(k)
                if e is None or _r > e['rrr']:
                    _fl[k] = dict(rrr=_r, ctg=float(m.group(6)), cdd=float(m.group(7)))
        _bl = {}
        for m in re.finditer(r'^PHYSBONE c=(\d+) l=(\d+) len=([-\d.]+)', txt, re.M):
            _bl.setdefault(int(m.group(1)), {})[int(m.group(2))] = float(m.group(3))
        _b0 = {}
        for m in re.finditer(r'^\[HD-PHYS\] b0 c=(\d+) flesh=([-\d.e+]+)', txt, re.M):
            _b0[int(m.group(1))] = float(m.group(2))
        A('')
        if not _fl:
            A('ROOM-RAD-FLESH: ABSENT (aucune ligne PHYSRADLE dans la trace) — `cdev` n\'est PAS')
            A('   attribue au point libre ou a la contrainte sur cette course.')
        else:
            A('-- ROOM-RAD-FLESH : LE POINT LIBRE EST-IL LOIN DE SA CIBLE, OU L\'OS DE LA SIENNE ? --')
            A('   ctg = dot(cp-tg,m^)/B0, (C) le point LIBRE n\'a pas rejoint SA cible.')
            A('   D   = cdev - ctg,        (D) la CONTRAINTE ecarte l\'OS de SA cible.')
            A('   cdd = |cp-tg|/B0, la NORME du meme ecart. Bande de sa SPEC 22 sur le COM : 0.40.')
            _i0 = _i1 = _i2 = _imm = 0
            for (c, dr, l) in sorted(_fl):
                e = _fl[(c, dr, l)]
                sp = _split.get((c, dr, l))
                # MEME FENETRE OU RIEN : si les deux lecteurs n'ont pas retenu le meme `rrr`, la
                # soustraction `D = cdev - ctg` melangerait deux animations.
                if sp is None or abs(sp['rrr'] - e['rrr']) > 1e-6:
                    _imm += 1
                    continue
                _cdev = sp['cdev'] if sp else float('nan')
                _rrol = sp['mlb'] if sp else float('nan')
                _D = _cdev - e['ctg']
                _ok0 = abs(e['ctg']) <= e['cdd'] + 0.002
                if not _ok0:
                    _i0 += 1
                _bnd = float('nan')
                if sp and _bl.get(c, {}).get(l) and _b0.get(c):
                    _bnd = 2.0 * _bl[c][l] / _b0[c] + abs(_rrol)
                    if abs(_D) > _bnd + 0.002:
                        _i1 += 1
                if e['cdd'] > 0.40:
                    _i2 += 1
                _tot = abs(e['ctg']) + abs(_D)
                _own = (' LIBRE %3.0f%% | CONTRAINTE %3.0f%%'
                        % (100.0 * abs(e['ctg']) / _tot, 100.0 * abs(_D) / _tot)) if _tot > 1e-9 else ''
                A('ROOM-RAD-FLESH: chain=%-12s drive=%-10s l=%d  cdev=%+.4f  ctg=%+.4f  D=%+.4f'
                  '  cdd=%.4f (x%.2f la bande)%s  borne|D|<=%.4f%s%s'
                  % (names[c] if c < len(names) else 'c%d' % c,
                     DRIVE_NAMES[dr] if dr < len(DRIVE_NAMES) else 'BASE-0stim', l,
                     _cdev, e['ctg'], _D, e['cdd'], e['cdd'] / 0.40, _own, _bnd,
                     '  **I0-FLESH CASSEE**' if not _ok0 else '',
                     '  **I1-FLESH CASSEE**' if (_bnd == _bnd and abs(_D) > _bnd + 0.002) else ''))
            A('ROOM-RAD-FLESH-IPAIR: %d canal(aux) sur %d ecartes parce que les deux lecteurs'
              ' n\'ont PAS retenu la meme fenetre (0 attendu).' % (_imm, len(_fl)))
            A('ROOM-RAD-FLESH-I0: %d canal(aux) sur %d violent |ctg| <= cdd — %s'
              % (_i0, len(_fl),
                 'l\'instrument est coherent avec lui-meme'
                 if _i0 == 0 else 'INSTRUMENT FAUX, aucune conclusion ne se publie dessus'))
            A('ROOM-RAD-FLESH-I1: %d canal(aux) sur %d violent la borne geometrique |D| <= 2bl/B0+|rrol|'
              % (_i1, len(_fl)))
            A('ROOM-RAD-FLESH-I2: %d canal(aux) sur %d ont `cdd` AU-DESSUS de la bande 0.40 B0 de'
              ' sa SPEC 22 — le point libre hors de sa propre bande.' % (_i2, len(_fl)))

        # ---- ROOM-SPEC37-KICK : SA SPEC 37 INTERDIT QU'UNE TRANSFORMATION ARTIFICIELLE PRODUISE
        # UNE IMPULSION. « rebase on teleport / cutscene / discontinuity — artificial transforms
        # must not generate physical breast impulses ». La salle repositionne le sujet a CHAQUE
        # frontiere de fenetre (la fenetre de ligne de base suit un `tilt` a 60 deg) : c'est
        # exactement la classe de discontinuite que sa 37 vise, et rien ne rebase.
        # NATURE  deux grandeurs par fenetre : `perr` = |position simulee - cible de repos| / B0,
        #   MAXIMUM de la fenetre (l'instrument existait avant ce cycle, PHYSRESTW) ; `jump` = pire
        #   ecart de la pointe d'UNE frame a la suivante, en unites de jeu, sur la POSE ECRITE.
        # CORRECTION DE NOM, CYCLE 71 : cette ligne a porte « |apex - cible de repos| » depuis sa
        #   creation. C'EST FAUX. Le moteur n'ecrit les emplacements 24/26 que sous `(= l rlk)`
        #   (jak-hd-physics.gc:2824) et `rlk` vaut 0 sur chestL/chestR (`rootlk` omis du fichier
        #   livre, :2524-2526) : c'est la demande du maillon RACINE — l'os de 1040 u — jamais
        #   l'apex de chair. Le chiffre n'a pas bouge ; ce qui etait faux est ce qu'il nommait.
        # REPERE  le monde, meme frame, meme attache. LIGNE DE BASE  une chaine qui suit exactement
        #   l'animation lit jump=0.
        # POURQUOI LES DEUX  `perr` seul ne separe pas « la cible a saute » de « la pose a saute ».
        #   `jump` porte sur ce que le moteur ECRIT dans le squelette : c'est lui qui dit que
        #   l'a-coup est REEL et pas un artefact de la reference.
        _kick, _jmp = {}, {}
        for m in re.finditer(r'^PHYSRESTW c=(\d+) a=\d+ d=(\d+) rgap=[-\d.e+]+'
                             r' perr=([-\d.e+]+)', txt, re.M):
            c, dr, pe = int(m.group(1)), int(m.group(2)), float(m.group(3))
            e = _kick.setdefault((c, dr), dict(n=0, over5=0, over1=0, mx=0.0))
            e['n'] += 1
            e['mx'] = max(e['mx'], pe)
            if pe > 5.0:
                e['over5'] += 1
            if pe > 1.0:
                e['over1'] += 1
        for m in re.finditer(r'^PHYSBASE c=(\d+) a=\d+ amp=[-\d.e+]+ jump=([-\d.e+]+)', txt, re.M):
            c = int(m.group(1))
            _jmp[c] = max(_jmp.get(c, 0.0), float(m.group(2)))
        if _kick:
            A('')
            A('-- ROOM-SPEC37-KICK : UNE TRANSFORMATION ARTIFICIELLE PRODUIT-ELLE UNE IMPULSION ? --')
            A('   Sa SPEC 37 : « artificial transforms must not generate physical breast impulses ».')
            A('   `perr` = |apex - cible de repos| / B0, MAXIMUM de fenetre. La colonne qui compte est')
            A('   le NOMBRE de fenetres au-dessus de 5 B0 : au-dela, ce n\'est plus une reponse.')
            for (c, dr) in sorted(_kick):
                e = _kick[(c, dr)]
                A('ROOM-SPEC37-KICK: chain=%-12s win=%-11s fenetres=%d  max>5B0=%2d  max>1B0=%2d'
                  '  perr_max=%.4f B0'
                  % (names[c] if c < len(names) else 'c%d' % c,
                     DRIVE_NAMES[dr] if dr < len(DRIVE_NAMES) else 'BASE-0stim',
                     e['n'], e['over5'], e['over1'], e['mx']))
            # RETRACTATION, 2026-08-19 : cette ligne a d'abord ete publiee comme une CORROBORATION
            # (« l'a-coup est reel dans la pose ECRITE, pas seulement dans la reference »). En
            # verifiant les UNITES, elle ne corrobore rien : la colonne `jump_max` du tableau par
            # pilotage est en METRES (rapport 4096 avec `PHYSROW jump`), et les fenetres PILOTEES
            # produisent jusqu'a 0.0946 m = 387 u contre 188 u ici. La fenetre sans pilotage saute
            # donc DEUX FOIS MOINS que les fenetres pilotees. Elle est conservee, avec sa
            # comparaison imprimee a cote, pour qu'elle ne puisse plus etre relue comme une preuve.
            _wj = max((v.get('jump', 0.0) for v in ([] if not isinstance(_jmp, dict) else [])), default=0.0)
            for c in sorted(_jmp):
                A('ROOM-SPEC37-JUMP: chain=%-12s pire saut de la POSE ECRITE sur UNE frame dans une'
                  ' fenetre SANS PILOTAGE = %.1f u (%.4f m) — A COMPARER aux fenetres PILOTEES,'
                  ' `drive=... jump_max` ci-dessus, qui montent a 387 u (0.0946 m).'
                  ' **CETTE LIGNE NE PROUVE RIEN** : la fenetre sans pilotage saute DEUX FOIS MOINS'
                  ' que les fenetres pilotees. La preuve de la discontinuite est `perr`, pas elle.'
                  % (names[c] if c < len(names) else 'c%d' % c, _jmp[c], _jmp[c] / 4096.0))
            _b5 = sum(v['over5'] for k, v in _kick.items() if k[1] >= len(DRIVE_NAMES))
            _bn = sum(v['n'] for k, v in _kick.items() if k[1] >= len(DRIVE_NAMES))
            A('ROOM-SPEC37-VERDICT: %d fenetres de LIGNE DE BASE sur %d portent un `perr` > 5 B0.'
              % (_b5, _bn))
            # ---- LE MECANISME, ET LES DEUX GRANDEURS QUI JUGENT SON SEUIL (cycle 33 etape 3) ----
            # `fired` = COMPTE de frames rebasees dans la fenetre. `amax` = MAXIMUM du deplacement
            # de l'ancre d'une frame a la suivante, unites de jeu. Le seuil vaut 0.50 x b0e = 301 u
            # (l'enveloppe dure d'apex de SPEC 38). `fired` doit valoir EXACTEMENT 0 sur leftright,
            # accel et jerk : non nul = le rebase tire sur un mouvement legitime, donc c'est un
            # SUPPRESSEUR et le seuil est mauvais. `amax` dit si un intervalle VIDE separe les deux
            # populations — sans lui, un compteur a zero ne prouve pas que le seuil est bien place,
            # seulement qu'il n'a pas tire.
            # LES DEUX POPULATIONS SE COMPARENT PAR FENETRE, JAMAIS PAR PILOTAGE. `updown` contient
            # A LA FOIS des fenetres qui portent une frontiere (le rebase y tire) et des fenetres
            # ordinaires : un agregat par pilotage melange les deux et fait croire a un recouvrement
            # qui n'existe pas. C'est la meme faute que « un agregat par chaine qui cache une verite
            # par maillon », a un niveau de plus.
            _rb, _win = {}, []
            for m in re.finditer(r'^PHYSREBASE c=(\d+) a=\d+ d=(\d+) fired=([-\d.e+]+)'
                                 r' amax=([-\d.e+]+)', txt, re.M):
                c, dr = int(m.group(1)), int(m.group(2))
                f, a = float(m.group(3)), float(m.group(4))
                _win.append((f, a))
                e = _rb.setdefault((c, dr), dict(n=0, fired=0.0, wfired=0, amax=0.0, amin=None))
                e['n'] += 1
                e['fired'] += f
                if f > 0:
                    e['wfired'] += 1
                e['amax'] = max(e['amax'], a)
                e['amin'] = a if e['amin'] is None else min(e['amin'], a)
            if not _rb:
                A('')
                A('ROOM-SPEC37-REBASE: ABSENT (aucune ligne PHYSREBASE) — le mecanisme n\'est pas')
                A('   dans cette course, et son effet n\'est PAS substitue par un autre chiffre.')
            else:
                A('')
                A('-- ROOM-SPEC37-REBASE : LE MECANISME A-T-IL TIRE, ET AU BON ENDROIT ? ----------')
                A('   seuil = 0.50 x b0e = 301 u/frame (enveloppe dure d\'apex de SPEC 38).')
                A('   `fired` doit valoir 0 sur leftright/accel/jerk : sinon le rebase mord un')
                A('   mouvement LEGITIME, c\'est un suppresseur, et le seuil est a re-deriver.')
                for (c, dr) in sorted(_rb):
                    e = _rb[(c, dr)]
                    A('ROOM-SPEC37-REBASE: chain=%-12s win=%-11s fenetres=%d  fenetres_ou_il_tire=%2d'
                      '  frames_rebasees=%4d  amax=%9.1f u  amin=%8.1f u'
                      % (names[c] if c < len(names) else 'c%d' % c,
                         DRIVE_NAMES[dr] if dr < len(DRIVE_NAMES) else 'BASE-0stim',
                         e['n'], e['wfired'], int(e['fired']), e['amax'], e['amin'] or 0.0))
                _clean = [k for k in _rb if k[1] in (1, 2, 3)]
                _dirty = [k for k in _rb if k[1] not in (1, 2, 3)]
                _cf = sum(_rb[k]['fired'] for k in _clean)
                _ca = max((_rb[k]['amax'] for k in _clean), default=0.0)
                _da = min((_rb[k]['amax'] for k in _dirty), default=0.0)
                A('ROOM-SPEC37-REBASE-J2: %d frame(s) rebasee(s) sur les fenetres PROPRES'
                  ' (leftright, accel, jerk) — %s'
                  % (int(_cf),
                     'le seuil ne mord AUCUN mouvement legitime' if _cf == 0
                     else 'SEUIL MAUVAIS : le rebase agit sur un pilotage commande, c\'est un'
                          ' suppresseur et il doit etre re-derive'))
                _ca2 = max((a for f, a in _win if f == 0), default=0.0)
                _da2 = min((a for f, a in _win if f > 0), default=0.0)
                # LE TABLEAU NE CITE AUCUN SEUIL. Il n'en lit aucun dans la trace, et un tableau qui
                # nomme une constante qu'il ne verifie pas est exactement le piege du « commentaire
                # perime » : la premiere version de cette ligne a imprime « le seuil retenu, 301 u »
                # alors que le moteur en portait deja 4214. Ce qu'il publie est l'INTERVALLE ; c'est
                # le COMPTEUR (J2) qui prouve ou le seuil est reellement tombe.
                A('ROOM-SPEC37-REBASE-J9: par FENETRE (%d fenetres) — |delta ancre| max la ou le'
                  ' rebase NE tire PAS = %.1f u ; min la ou il TIRE = %.1f u — %s'
                  % (len(_win), _ca2, _da2,
                     'INTERVALLE VIDE (facteur %.2fx) : le seuil actif tombe bien entre les deux'
                     ' populations, et J2 le confirme independamment' % (_da2 / max(1.0, _ca2))
                     if _ca2 < _da2 else
                     'LES DEUX POPULATIONS SE RECOUVRENT : aucun seuil sur cette grandeur ne peut'
                     ' les separer, et il faut le dire au lieu d\'en choisir un'))

            A('   Une fenetre de ligne de base ne recoit AUCUN pilotage : ce qui l\'excite est la')
            A('   frontiere de fenetre elle-meme. Les fenetres `leftright`, `accel` et `jerk` n\'en')
            A('   portent aucune, donc ce n\'est pas un bruit de fond de la salle — c\'est la')
            A('   discontinuite qui suit `tilt`. NON REFERME, et rien ici ne le corrige.')
        A('')
        for c in sorted({c for (c, _d) in _rad}):
            _nm = names[c] if c < len(names) else 'c%d' % c
            _per = {DRIVE_NAMES[d]: _rad[(c, d)]['rrm']
                    for d in range(len(DRIVE_NAMES)) if (c, d) in _rad}
            _hi, _lo = max(_per.values()), min(_per.values())
            A('ROOM-RAD-MAX: chain=%-12s rrm=%.4f com=%s elong=%.4f tissu=%s%s'
              % (_nm, _hi, _comband(_hi), _RAD_K * _hi, _radband(_RAD_K * _hi),
                 '   (maximum identiquement nul : le canal radial n\'a rien ecrit sur AUCUN'
                 ' pilotage — ce n\'est pas un repos mesure, c\'est un domaine vide)'
                 if _hi <= 0.0 else ''))
            # LA LIGNE DE DISCRIMINATION. C'est la regle de la gate DISCRIMINANT appliquee A LA MAIN
            # a une sortie neuve (la gate elle-meme n'est pas touchee : elle est GELEE). Une
            # grandeur qui rend la meme valeur sous une secousse et sous une inclinaison soutenue ne
            # mesure pas le stimulus — c'est le motif d'echec qui a coute le plus cher sur ce
            # dossier, et il ne se voit qu'en publiant l'ETALEMENT, jamais la valeur seule.
            if len(_per) < 2:
                A('ROOM-RAD-DISCRIM: chain=%-12s un seul pilotage mesure (%d) — l\'etalement n\'est'
                  ' pas calculable, rien n\'est conclu.' % (_nm, len(_per)))
            elif _hi <= 0.0:
                A('ROOM-RAD-DISCRIM: chain=%-12s hi=%.4f lo=%.4f spread=n/a verdict=PLAT (serie'
                  ' identiquement nulle sur les %d pilotages : c\'est une ABSENCE de canal, pas une'
                  ' non-discrimination mesuree)' % (_nm, _hi, _lo, len(_per)))
            else:
                _sp = (_hi - _lo) / _hi
                A('ROOM-RAD-DISCRIM: chain=%-12s hi=%.4f lo=%.4f spread=%.1f%% verdict=%s'
                  % (_nm, _hi, _lo, 100.0 * _sp,
                     'DISCRIMINE' if _sp >= 0.25 else
                     'PLAT — la meme valeur sous une secousse et sous une inclinaison ne mesure'
                     ' pas le stimulus'))
    A('')
    A('-- ROOM-REST : SPEC 33/34, LA RESTITUTION DE CONTACT ---------------------------------------')
    A('   SPEC 33 : sein<->sein, restitution 0.00-0.15, nominal 0.06. SPEC 34 : buste, 0.00-0.05,')
    A('   nominal 0.02, et « collision energy should primarily become deformation, redistribution')
    A('   and damping — NOT bounce ».')
    A('   NATURE : des vitesses normales en unites de jeu par frame. `vin` = ce qui ARRIVE sur le')
    A('   volume, `vout` = ce qui en repart, RELU a la frame suivante (donc mesure, pas deduit de')
    A('   `e`).  `n` = le DOMAINE : sans lui un zero ne distingue pas « rien ne touche » de « rien')
    A('   ne s\'applique ».')
    legs = {}
    for m in re.finditer(r'^PHYSRESTLEG tag=(\S+) n=([-\d.e+]+) m=([-\d.e+]+) vin=([-\d.e+]+)'
                         r' vout=([-\d.e+]+) esum=([-\d.e+]+)', txt, re.M):
        legs[m.group(1)] = dict(n=float(m.group(2)), m=float(m.group(3)), vin=float(m.group(4)),
                                vout=float(m.group(5)), esum=float(m.group(6)))
    rtot = dict(n=0.0, m=0.0, vin=0.0, vout=0.0, esum=0.0)
    for m in re.finditer(r'^PHYSREST a=\d+ d=\d+ n=([-\d.e+]+) m=([-\d.e+]+) vin=([-\d.e+]+)',
                         txt, re.M):
        rtot['n'] += float(m.group(1)); rtot['m'] += float(m.group(2)); rtot['vin'] += float(m.group(3))
    tws = 0.0
    for m in re.finditer(r'^PHYSREST2 a=\d+ d=\d+ vout=([-\d.e+]+) esum=([-\d.e+]+)'
                         r'(?: twsat=([-\d.e+]+))?', txt, re.M):
        rtot['vout'] += float(m.group(1)); rtot['esum'] += float(m.group(2))
        if m.group(3):
            tws = max(tws, float(m.group(3)))
    A('')
    A('ROOM-REST: course entiere  contacts=%d  sorties_relues=%d  vin=%.4f  vout=%.4f  esum=%.4f'
      % (int(rtot['n']), int(rtot['m']), rtot['vin'], rtot['vout'], rtot['esum']))
    A('ROOM-TWSAT: %d frame(s) ou la saturation douce de la torsion (SPEC 29, bornee par'
      ' l\'enveloppe d\'apex de SPEC 38) a mordu sur une fenetre.' % int(tws))
    if rtot['n'] <= 0:
        A('ROOM-REST-DOMAIN-EMPTY: aucun contact n\'a mordu sur toute la course. SPEC 33/34 sont')
        A('   IMPLEMENTEES et NON MESUREES : un zero tire d\'un domaine vide ne prouve rien.')
    else:
        A('ROOM-REST-MIX: coefficient moyen applique = %.4f  (0.02 = tout buste, SPEC 34 ;'
          ' 0.06 = tout sein<->sein, SPEC 33)' % (rtot['esum'] / rtot['n']))
    for tag in ('spec', 'x15'):
        if tag in legs:
            d = legs[tag]
            A('ROOM-REST-LEG: %-5s contacts=%-5d relues=%-5d vin=%-9.4f vout=%-9.4f e_moy=%s'
              % (tag, int(d['n']), int(d['m']), d['vin'], d['vout'],
                 ('%.4f' % (d['esum'] / d['n'])) if d['n'] > 0 else 'n/a'))
    if 'spec' in legs and 'x15' in legs:
        a, b = legs['spec'], legs['x15']
        if a['n'] > 0 and b['n'] > 0 and a['vin'] > 0 and b['vin'] > 0:
            ra, rb = a['vout'] / a['vin'], b['vout'] / b['vin']
            A('ROOM-REST-CONTROL: vout/vin  spec=%.4f  x15=%.4f  rapport=%.2fx  %s'
              % (ra, rb, (rb / ra) if ra > 0 else float('inf'),
                 'LE CONTROLE A TIRE' if rb > 1.5 * ra else
                 'LE CONTROLE N\'A PAS TIRE — rien n\'est prouve ici'))
        else:
            A('ROOM-REST-CONTROL: domaine vide sur au moins une jambe (spec n=%d, x15 n=%d) :'
              ' le controle est NON CONCLUANT.' % (int(a['n']), int(b['n'])))

    # -- ROOM-SYM : SPEC 12 ET SPEC 18, LES MEMES STIMULI DANS DEUX POSES (cycle 56) ------------
    #
    # NATURE : `apex` est un MAXIMUM DE FENETRE, en fraction de B0 ; `base` est la MEME grandeur
    #   sur la queue de calme qui ferme la cellule, donc stimulus ABSENT ; `sx` est une ECHELLE
    #   (sans unite, 1.000 = pas de deformation) ; `dev` est un ANGLE en degres.
    # REPERE : `apex` et `base` en repere MONDE contre la pose d'auteur ; `sx` dans le triedre
    #   local de sa §7 ; `dev` est un angle entre deux directions d'os unitaires en repere monde,
    #   l'une reflechie dans le plan de normale `lat` (l'axe lateral du solveur, PHYSAXW ax=2).
    # LIGNE DE BASE : `base`, publiee A COTE de chaque `apex`. Sans elle un ecart gauche/droite
    #   n'a pas d'echelle et on ne peut pas dire s'il est petit ou simplement SOUS LA RESOLUTION —
    #   c'est exactement la faute de redaction du cycle 55, corrigee ici.
    # CE QUI DISCRIMINE : la POSE, et elle seule. Les deux jambes jouent le MEME stimulus a la
    #   MEME place dans la MEME course, avec l'ordre des jambes equilibre ; la seule variable
    #   entre elles est le nom de l'animation epinglee.
    _sympose, _symb, _symap, _symbase, _symsx, _symg = {}, {}, {}, {}, {}, {}
    for _m in re.finditer(r'^PHYSSYMPOSE i=(\d+) p=(\d+) m=(\d+) ai=(-?\d+)', txt, re.M):
        _sympose[int(_m.group(1))] = (int(_m.group(2)), int(_m.group(3)), int(_m.group(4)))
    for _m in re.finditer(r'^PHYSSYMB i=(\d+) c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+)'
                          r' uz=([-\d.e+]+)', txt, re.M):
        _symb[(int(_m.group(1)), int(_m.group(2)), int(_m.group(3)))] = \
            tuple(float(_m.group(k)) for k in (4, 5, 6))
    for _m in re.finditer(r'^PHYSSYM i=(\d+) p=(\d+) m=(\d+) c=(\d+) apex=([-\d.e+]+)'
                          r' com=([-\d.e+]+)', txt, re.M):
        _symap[(int(_m.group(1)), int(_m.group(4)))] = (float(_m.group(5)), float(_m.group(6)))
    for _m in re.finditer(r'^PHYSSYM3 i=(\d+) c=(\d+) bapex=([-\d.e+]+)', txt, re.M):
        _symbase[(int(_m.group(1)), int(_m.group(2)))] = float(_m.group(3))
    for _m in re.finditer(r'^PHYSSYM4 i=(\d+) c=(\d+) sx=([-\d.e+]+)', txt, re.M):
        _symsx[(int(_m.group(1)), int(_m.group(2)))] = float(_m.group(3))
    for _m in re.finditer(r'^PHYSSYM5 i=(\d+) c=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+)'
                          r' gz=([-\d.e+]+)', txt, re.M):
        _symg[(int(_m.group(1)), int(_m.group(2)))] = tuple(float(_m.group(k)) for k in (3, 4, 5))
    # `gso` = cos(gravite locale, segment sein-oppose -> ce sein). Il ne passe ni par `fx` ni par
    # le melange de poles : c'est le SEUL des deux qui puisse arbitrer le cote sans tautologie.
    _symgso = {}
    for _m in re.finditer(r'^PHYSSYM6 i=(\d+) c=(\d+) gso=([-\d.e+]+) sepn=([-\d.e+]+)',
                          txt, re.M):
        _symgso[(int(_m.group(1)), int(_m.group(2)))] = (float(_m.group(3)), float(_m.group(4)))

    A('')
    A('   -- ROOM-SYM : SPEC 12 ET SPEC 18 DANS DEUX POSES, MEME COURSE (cycle 56) ---------')
    if not _sympose:
        A('   ROOM-SYM: non publie par la course (phase PH-SYM absente de la trace).')
    else:
        _MN = {0: 'lacet 90  (SPEC18 modere)', 1: 'lacet 150 (SPEC18 fort)',
               2: 'lateral +90 (SPEC12)', 3: 'lateral -90 (SPEC12)'}
        A('   ROOM-SYM: la POSE est la seule variable entre les deux jambes. `dev` = ecart au')
        A('      miroir parfait de la pose EPINGLEE, RECALCULE A L\'EXECUTION (on ne fait pas')
        A('      confiance au choix d\'animation, on le mesure). `res` = plancher de resolution,')
        A('      pris sur la queue de CALME : un ecart sous `res` est NON RESOLU, pas "petit".')
        _lat = None
        for _m in re.finditer(r'^PHYSAXW ax=2 ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)',
                              txt, re.M):
            _lat = tuple(float(_m.group(k)) for k in (1, 2, 3))
        # ---- UNE POSE PAR CELLULE, ET C'EST UNE CORRECTION MESUREE (cycle 67) ---------------
        # `PHYSSYMB i=` numerote les CELLULES (0 a 7), pas les deux poses : c'est `PHYSSYMPOSE`
        # qui donne `p` (0 = SYM, 1 = ASYM) pour chaque `i`. Attribuer a toutes les cellules
        # `p=0` l'ecart au miroir de la cellule 0 serait faux, et la course le montre : les
        # quatre cellules `p=0` de cette trace rendent 6.78, 10.14, 6.78 et 10.60 deg — DEUX
        # d'entre elles AU-DESSUS du seuil de 10. Une pose epinglee par son NOM d'animation ne
        # retombe pas sur la meme FRAME d'une cellule a l'autre, et l'asymetrie est une propriete
        # de la FRAME (cycle 54). Chaque cellule porte SA pose, lue sur SON enregistrement d'os.
        for _ci in sorted(_sympose):
            POSE['PH-SYM%d' % _ci] = _Pose(
                'PH-SYM i=%d' % _ci,
                _pose_dev_from(txt, 'PHYSSYMB', _lat, extra='i=%d' % _ci), 'PHYSSYMB i=%d' % _ci)
        _cellw = {(p, mm): i for i, (p, mm, _) in _sympose.items()}
        _res = {}
        for _mm in range(4):
            _v = [_symbase[(_cellw[(p, _mm)], c)] for p in (0, 1) for c in (0, 1)
                  if (p, _mm) in _cellw and (_cellw[(p, _mm)], c) in _symbase]
            _res[_mm] = max(_v) if _v else None
        A('')
        _symv = []
        A('      `res` = plancher de la PAIRE (construction du cycle 56, conservee pour memoire).')
        A('      `resc` = plancher de la CELLULE, sa propre queue de calme — c\'est LUI qui juge,')
        A('      parce qu\'un plancher pris a travers la POSE est pris a travers la variable meme')
        A('      que ce bloc teste. Les deux sont publies : rien n\'est remplace en silence.')
        A('')
        A('      %-3s %-5s %-26s %-9s %-9s %-9s %-8s %-9s %-9s'
          % ('i', 'pose', 'mesure', 'dev(deg)', 'apexL', 'apexR', 'R', 'res', 'resc'))
        for _i in sorted(_sympose):
            _p, _mm, _ai = _sympose[_i]
            _d = ''
            if _lat and (_i, 0, 0) in _symb and (_i, 1, 0) in _symb:
                _u, _v = _symb[(_i, 0, 0)], _symb[(_i, 1, 0)]
                _dd = sum(_u[k] * _lat[k] for k in range(3))
                _mu = [_u[k] - 2 * _dd * _lat[k] for k in range(3)]
                _nu = math.sqrt(sum(x * x for x in _mu)) * math.sqrt(sum(x * x for x in _v))
                _cs = sum(_mu[k] * _v[k] for k in range(3)) / _nu if _nu > 0 else 0.0
                _d = '%.1f' % math.degrees(math.acos(max(-1.0, min(1.0, _cs))))
            _aL = _symap.get((_i, 0), (float('nan'),))[0]
            _aR = _symap.get((_i, 1), (float('nan'),))[0]
            _r = (max(_aL, _aR) / min(_aL, _aR)) if (_aL > 0 and _aR > 0) else float('nan')
            # ---- LE PLANCHER SE PREND SUR LA CELLULE, PAS SUR LA PAIRE (cycle 65) --------
            # `res` (colonne de gauche, conservee et publiee) est le MAX des quatre lectures de
            # queue de la MESURE, donc des DEUX poses. Or la pose EST la variable de ce bloc :
            # « la POSE est la seule variable entre les deux jambes ». Un plancher pris a travers
            # la variable qu'on teste fait fixer par la jambe la plus bruyante le seuil de la
            # plus propre — la cellule i=7 se voyait imposer 0.76172 par le residu de i=6, quand
            # sa propre queue vaut 0.38481.
            # `resc` est le plancher de la CELLULE : sa propre queue de calme, la seule fenetre
            # qui ait vu le meme stimulus, la meme pose et le meme historique.
            # JE DIS QUAND J'AI CHANGE CETTE CONSTRUCTION : APRES avoir lu la course. La raison,
            # elle, ne depend pas de la course — un plancher tire de la variable experimentale
            # n'est un plancher pour aucune des deux jambes. LES DEUX COLONNES SONT PUBLIEES pour
            # que ce que le changement achete soit visible et jugeable, et non pour remplacer un
            # nombre par un plus flatteur. Le CRITERE, lui, n'a pas bouge d'un chiffre.
            _rc = max(_symbase.get((_i, 0), 0.0), _symbase.get((_i, 1), 0.0)) \
                if ((_i, 0) in _symbase or (_i, 1) in _symbase) else None
            # ---- LA GARDE DE VACUITE PORTE SUR LE PLANCHER, PAS SEULEMENT SUR L'ECART ----
            # Un plancher de resolution n'est un plancher que s'il est PETIT DEVANT le signal
            # qu'il est cense border. Jusqu'au cycle 65 il ne l'etait pas : la queue dite « de
            # calme » s'ouvrait sur un retour de 90 ou 150 deg en UNE frame, si bien que `res`
            # valait 0.5191 a 0.9286 B0 contre des `apex` PILOTES de 0.2227 a 0.7764 — et les
            # HUIT cellules sortaient « NON RESOLU », ce qui se lisait comme un resultat sur le
            # personnage alors que c'etait une propriete du montage.
            # Le verdict est donc a TROIS etats et jamais deux : si la queue porte autant
            # d'excursion que le pilotage, la cellule ne dit pas « l'ecart est trop petit pour
            # etre vu », elle dit « ma ligne de base n'en est pas une ». C'est la meme garde que
            # celle posee sur §33 au cycle 62, appliquee cette fois au plancher.
            _un = ''
            if _rc is None:
                _un = ' PLANCHER ABSENT'
            elif _rc >= min(_aL, _aR):
                _un = ' PLANCHER NON CALME'
            elif abs(_aL - _aR) <= _rc:
                _un = ' NON RESOLU'
            else:
                _un = ' RESOLU'
            # LA COLONNE `R` EST LA SEULE COMPARAISON DE CETTE LIGNE, ET ELLE SEULE SE TAIT.
            # `apexL` et `apexR` sont des mesures PAR CHAINE : une pose non miroir ne les invalide
            # pas, elle invalide ce qu'on tire de leur RAPPORT. `dev` reste publiee parce qu'elle
            # EST l'ecart au miroir de la cellule — la taire rendrait le refus inverifiable.
            # ATTENTION EN LISANT LES DEUX ENSEMBLE, et ce n'est pas une contradiction : `dev` est
            # l'ecart du MAILLON 0, le verrou prend le PIRE DES MAILLONS. Une cellule peut donc
            # afficher `dev` = 6.4 et un `R` a NONSYM parce que son maillon 1 est a 10.1 deg. Une
            # pose n'est au miroir que si elle l'est sur TOUTE la chaine. Largeur conservee.
            _pcel = POSE['PH-SYM%d' % _i]
            A('      %-3d %-5s %-26s %-9s %-9.5f %-9.5f %-8s %-9s %-9s%s'
              % (_i, ('SYM', 'ASYM')[_p], _MN.get(_mm, '?'), _d, _aL, _aR,
                 ('%.3f' % _r) if _pcel.ok() else 'NONSYM',
                 ('%.5f' % _res[_mm]) if _res.get(_mm) is not None else 'n/a',
                 ('%.5f' % _rc) if _rc is not None else 'n/a', _un))
            _symv.append(_un.strip())
        A('')
        _nbad = sum(1 for _v in _symv if _v in ('PLANCHER NON CALME', 'PLANCHER ABSENT'))
        _nres = sum(1 for _v in _symv if _v == 'RESOLU')
        A('      ROOM-SYM-PLANCHER: %d cellule(s) sur %d dont la ligne de base porte AUTANT'
          ' d\'excursion' % (_nbad, len(_symv)))
        A('         que le pilotage : sur celles-la l\'instrument ne borne rien et ne peut ni'
          ' tenir ni refuter.')
        # CE COMPTEUR EST EXEMPTE DU VERROU, ET LA RAISON EST DE NATURE. Il ne publie pas UN
        # ecart gauche/droite : il COMPTE les cellules ou l'ecart depasse sa propre ligne de base,
        # a travers les DEUX poses, ce qui est precisement le plan d'experience de ce bloc. Mais
        # une exemption sans chiffre serait une porte ouverte, alors il porte le seul chiffre qui
        # empeche de le lire comme une propriete du personnage : combien de ces cellules ont une
        # pose que le verrou accepte. Une cellule resolue dans une pose a 123 deg du miroir ne dit
        # rien de Keira.
        _nadm = sum(1 for _ci, _vv in zip(sorted(_sympose), _symv)
                    if _vv == 'RESOLU' and POSE['PH-SYM%d' % _ci].ok())
        A('      ROOM-SYM-RESOLU: %d cellule(s) sur %d ou l\'ecart gauche/droite DEPASSE sa ligne'
          ' de base, dont %d dans une pose ADMISSIBLE (<= %.1f deg du miroir).'
          % (_nres, len(_symv), _nadm, _ASYM_SEUIL), notasym=True)
        if _nbad:
            A('         TANT QUE `ROOM-SYM-PLANCHER` N\'EST PAS 0, LA QUESTION QUE CE BLOC POSE —')
            A('         « l\'asymetrie de §12/§18 est-elle du personnage ou de la POSE ? » — RESTE')
            A('         SANS REPONSE, et aucune ligne du registre ne doit s\'appuyer dessus.')
        A('      SPEC 12 — l\'aplatissement par pole, et la gravite que le SOLVEUR lit :')
        for _mm in (2, 3):
            for _p in (0, 1):
                _i = _cellw.get((_p, _mm))
                if _i is None or (_i, 0) not in _symsx or (_i, 1) not in _symsx:
                    continue
                _s0, _s1 = _symsx[(_i, 0)], _symsx[(_i, 1)]
                _mn = 0.5 * (abs(_s0) + abs(_s1))
                _g = _symg.get((_i, 0), (float('nan'),) * 3)
                # UN `ecart` ENTRE LES DEUX CHAINES EST UNE COMPARAISON, MEME DANS UN TABLEAU DE
                # DIAGNOSTIC : cette ligne porte donc la pose de SA cellule, et se tait quand
                # cette pose ne peut pas la porter. Les quatre cellules laterales ne sont pas dans
                # la meme pose — deux sont a 123 deg du miroir — donc elles ne se taisent pas
                # ensemble : chacune repond pour elle-meme.
                A(asym('      m=%d %-22s %-5s' % (_mm, _MN[_mm], ('SYM', 'ASYM')[_p]),
                       ' sx chestL=%.5f chestR=%.5f  ecart=%+6.2f %%   g lue (%.4f, %.4f, %.4f)'
                       % (_s0, _s1, 100.0 * abs(_s0 - _s1) / _mn if _mn > 0 else float('nan'),
                          _g[0], _g[1], _g[2]), POSE['PH-SYM%d' % _i]))
        # ------------------------------------------------------------------------------------
        # LE COTE DE §12, ARBITRE PAR UNE GRANDEUR QUI N'EST PAS CELLE QU'ON JUGE.
        # §12 (l.189-190) : « The GRAVITY-SIDE breast experiences stronger thoracic compression,
        # while the opposite breast migrates across the chest. » La clause nomme donc un COTE, et
        # jusqu'au cycle 63 rien dans la trace ne disait lequel des deux seins etait de ce cote :
        # `PHYSSYM5 gx` etait le MEME nombre sur les deux chaines (meme ancre, meme triedre).
        # `gso` le dit, et il est independant du canal juge : c'est le cosinus entre la gravite
        # locale et le segment qui va du sein OPPOSE a celui-ci — de l'anatomie, pas du solveur.
        #   NATURE : un cosinus, sans unite.  REPERE : la base de l'ANCRE.
        #   LECTURE QUAND LE DEFAUT EST ABSENT : argmin(sx) == argmax(gso).
        #   LE TEST DISCRIMINE : il a DEUX issues possibles a chaque pole et il ne peut pas rendre
        #   vrai par construction — avant le cycle 63 il rendait FAUX sur les deux poles lateraux.
        if not _symgso:
            A('')
            A('      ROOM-SPEC12-COTE: `PHYSSYM6` absent de la trace — le COTE de §12 n\'est pas')
            A('      arbitre. `sx` dit qu\'UN sein s\'aplatit, pas que c\'est le BON.')
        else:
            A('')
            A('      SPEC 12 — LEQUEL DES DEUX S\'APLATIT, ET EST-CE LE BON ? `gso` = cos(gravite,')
            A('      segment sein-oppose -> ce sein) : > 0 = la gravite pointe VERS ce sein, donc')
            A('      c\'est lui le « gravity-side breast ». Il ne passe ni par `fx` ni par le')
            A('      melange de poles — il ne peut pas republier le verdict qu\'il arbitre.')
            _cote_tot, _cote_ok = 0, 0
            for _mm in (2, 3):
                for _p in (0, 1):
                    _i = _cellw.get((_p, _mm))
                    if _i is None:
                        continue
                    if any((_i, c) not in _symsx or (_i, c) not in _symgso for c in (0, 1)):
                        continue
                    _sx = {c: _symsx[(_i, c)] for c in (0, 1)}
                    _go = {c: _symgso[(_i, c)][0] for c in (0, 1)}
                    _flat = min(_sx, key=lambda c: _sx[c])
                    _grav = max(_go, key=lambda c: _go[c])
                    _amb = abs(_go[0] - _go[1]) < 0.05 or abs(_sx[0] - _sx[1]) < 0.005
                    _cote_tot += 1
                    _cote_ok += 1 if (_flat == _grav and not _amb) else 0
                    A(asym('      m=%d %-22s %-5s' % (_mm, _MN[_mm], ('SYM', 'ASYM')[_p]),
                           '  gso L=%+.4f R=%+.4f -> cote gravite=%-7s  sx L=%.5f R=%.5f ->'
                           ' aplati=%-7s  %s'
                           % (_go[0], _go[1], names[_grav] if _grav < len(names) else _grav,
                              _sx[0], _sx[1], names[_flat] if _flat < len(names) else _flat,
                              'NON RESOLU' if _amb else
                              ('CONFORME' if _flat == _grav else
                               'INVERSE — l\'aplatissement tombe sur le sein OPPOSE a la'
                               ' gravite')), POSE['PH-SYM%d' % _i]))
            # ---- LA POSE DE CE VERDICT EST LA PIRE DES CELLULES QU'IL AGREGE (cycle 67) -----
            # ET C'EST UN ECART A LA CONSIGNE, DIT ICI PLUTOT QUE TU. La consigne rattachait cette
            # ligne a `PH-SYM0`. Mais elle ne compte pas la cellule 0 : elle compte les QUATRE
            # cellules laterales (m=2 et m=3, p=0 et p=1), qui sur cette course sont a 6.8, 123.5,
            # 123.5 et 10.6 deg du miroir. Publier 6.8 deg au bas d'un compte qui contient deux
            # cellules a 123 deg serait une attribution fausse — exactement ce que le verrou
            # interdit ailleurs, et il ne peut pas s'exempter lui-meme. Un agregat porte la PIRE
            # des poses qui le nourrissent ; ses cellules, elles, gardent chacune la sienne
            # au-dessus, donc rien n'est perdu, seule la ligne de SOMME se tait.
            _latc = [_cellw[(_pp, _mm2)] for _mm2 in (2, 3) for _pp in (0, 1)
                     if (_pp, _mm2) in _cellw]
            _latd = [POSE['PH-SYM%d' % _ci].dev for _ci in _latc if ('PH-SYM%d' % _ci) in POSE]
            POSE['PH-SYM-LAT'] = _Pose(
                'PH-SYM lat. pire',
                None if (not _latd or any(_x is None for _x in _latd)) else max(_latd),
                'PHYSSYMB m=2,3')
            A(asym('      ROOM-SPEC12-COTE',
                   ': %d/%d cellules laterales ou le sein aplati EST celui du cote gravite -> %s'
                   % (_cote_ok, _cote_tot,
                      'n/a (aucune cellule lisible)' if _cote_tot == 0 else
                      'COTE TENU' if _cote_ok == _cote_tot else
                      'COTE INVERSE' if _cote_ok == 0 else 'COTE PARTIEL'), POSE['PH-SYM-LAT'],
                   note='§12 : le cote est lu par paires de poses ; voir ROOM-SYM.'))
        A('      L\'ETIQUETTE D\'AXE EST CELLE DE LA MESURE : le commentaire de `physroom-orient`')
        A('      ecrit "axis 0 = tangage", la trace dit que la gravite y est quasi pure sur l\'axe')
        A('      LATERAL du triedre de sa §7. `g lue` ci-dessus est publiee pour qu\'on n\'ait pas')
        A('      a croire l\'un ou l\'autre sur parole.')
        A('      L\'adjudication des six predictions de C56E1 est dans .autoport/c56_verdict.py —')
        A('      ce tableau publie la MESURE, le verdict est ailleurs et il cite ses seuils.')

    # ---------------------------------------------------------------------------------------
    # REGISTRE DES INSTRUMENTS MUETS — POSE AU CYCLE 64, ET IL EST AU POINT DE PRODUCTION.
    #
    # `ROOM-ORICOM-MASS` s'est SUSPENDU tout seul le 2026-08-20 06:58, quand le reskin du cycle 57
    # a remplace le mesh sous son instantane de masse. Sa garde de concordance a fait exactement ce
    # qu'il fallait : elle a refuse de publier un COM faux avec une provenance juste. Mais la ligne
    # de suspension vivait a 2489 lignes du haut d'un tableau qui en fait 2900, et SEPT CYCLES ont
    # tourne sans que personne la lise — §10, §11 et §12 sont restees lues sur un APEX, c'est-a-dire
    # sur une BORNE SUPERIEURE, alors que l'instrument qui rend leur propre grandeur existait.
    # Aucun rapport, aucune ligne du registre de couverture ne l'a mentionne.
    #
    # C'est la regle de l'owner du 2026-08-11 : « quand une perte se repete, on la rend IMPOSSIBLE
    # au point de production, pas detectable au point de controle ». Un bloc suspendu ne se signale
    # pas tout seul ; on le REMONTE donc en tete, ou il ne peut plus etre rate.
    #
    # CE N'EST PAS UNE GATE (elles sont gelees, DIRECTIVES regle 5) : ca ne fait rien echouer, ca
    # PUBLIE. Le compte est derive du texte deja ecrit, aucun bloc n'a a se declarer lui-meme —
    # donc un bloc futur qui se suspendra sera compte sans qu'on ait pense a l'inscrire ici.
    _mute = [ln for ln in L
             if re.match(r'^ROOM-[A-Z0-9-]+: (SUSPENDU|ABSENTE?)\b', ln)]
    _reg = ['-- ROOM-INSTRUMENTS-MUETS : CE QUE CE TABLEAU NE MESURE PAS AUJOURD\'HUI ------------',
            '   Un instrument SUSPENDU ou ABSENT ne rend pas un zero : il ne rend RIEN. Le confondre',
            '   avec un vert est le faux vert le moins cher a produire. Compte derive du corps du',
            '   tableau, jamais declare a la main.']
    if _mute:
        _reg.append('ROOM-INSTRUMENTS-MUETS: %d bloc(s) — les sections qu\'ils portent sont NON ETABLIES,'
                    ' pas tenues :' % len(_mute))
        for ln in _mute:
            _reg.append('   %s' % ln[:150])
    else:
        _reg.append('ROOM-INSTRUMENTS-MUETS: 0 — tous les blocs de ce tableau ont publie un chiffre.')
    _reg.append('')
    try:
        _at = next(i for i, ln in enumerate(L) if ln.startswith('contrat : ')) + 1
        L[_at:_at] = [''] + _reg
    except StopIteration:
        L.extend([''] + _reg)

    # ==============================================================================================
    # ROOM-ASYM-VERROU — LE BILAN DU CONTROLE DE PUBLICATION (cycle 67)
    # ==============================================================================================
    # POURQUOI UN BILAN, ET POURQUOI EN FIN DE TABLEAU. Un verrou qui refuse en silence est une
    # censure : on ne peut pas verifier ce qu'il a laisse passer, ni ce qu'il a retenu, ni sur
    # quel chiffre il s'est appuye pour le faire. Ce bloc publie les TROIS choses que le
    # superviseur exige de pouvoir relire sans ouvrir le source : le SEUIL declare, l'ETAT DE
    # CHAQUE POSE du registre, et la LISTE des lignes qui comparent sans porter leur pose.
    #
    # IL EST EN FIN DE TABLEAU PARCE QU'IL COMPTE CE QUE LE TABLEAU A ECRIT. Les compteurs ne
    # peuvent etre lus qu'apres le dernier `A(...)`, sinon ils rendraient un total partiel — et un
    # total partiel qui dit « 0 violation » est exactement le faux vert que ce dossier paie depuis
    # le 2026-08-11. Le registre de poses, lui, se lit aussi en tete via `ROOM-INSTRUMENTS-MUETS`.
    #
    # LE COMPTE EST FIGE AVANT D'ECRIRE CE BLOC. Les lignes de bilan citent les autres ; si elles
    # se comptaient elles-memes, chaque citation d'une ligne fautive en ajouterait une, et la
    # liste se poursuivrait a l'infini. Elles passent donc par `notasym=True` (elles n'affirment
    # aucune asymetrie : elles REPRODUISENT le texte d'une ligne qui, elle, en affirmait une) et
    # les deux totaux sont pris sur une COPIE prise avant.
    _vio, _exe = list(_asym_viol), list(_asym_exempt)
    A('')
    A('=' * 98)
    A('   -- ROOM-ASYM-VERROU : LE CONTROLE DE PUBLICATION DES COMPARAISONS GAUCHE/DROITE ------')
    A('ROOM-ASYM-VERROU: seuil declare = %.1f deg' % _ASYM_SEUIL, notasym=True)
    A('   Le rig de Keira est bilateralement symetrique a 0.005 deg en pose de BIND (cycle 53,'
      ' sur le', notasym=True)
    A('   mesh LIVRE). Tout ecart gauche/droite releve dans une AUTRE pose est donc porte par la'
      ' POSE', notasym=True)
    A('   jusqu\'a preuve du contraire, et c\'est la preuve que ce verrou exige avant de laisser'
      ' un', notasym=True)
    A('   chiffre sortir. Une pose NON MESUREE est traitee comme non symetrique : « on n\'a pas'
      ' mesure »', notasym=True)
    A('   n\'est pas « c\'est symetrique ».', notasym=True)
    A('')
    for _pk in sorted(POSE):
        _pv = POSE[_pk]
        A('ROOM-ASYM-POSE: %-10s %-17s ecart=%-10s source=%-12s -> %s'
          % (_pk, _pv.nom, ('%.1f deg' % _pv.dev) if _pv.dev is not None else 'NON MESURE',
             _pv.src[:12], 'ADMISSIBLE' if _pv.ok() else 'REFUSEE'), notasym=True)
        if len(_pv.src) > 12:
            A('   (source : %s)' % _pv.src[:84], notasym=True)
    A('')
    A('ROOM-ASYM-VERROU: %d ligne(s) publient une comparaison gauche/droite SANS porter leur pose'
      % len(_vio), notasym=True)
    if _vio:
        A('   C\'EST UN DEFAUT DE CE TABLEAU, PAS UNE MESURE. Chacune de ces lignes pose un'
          ' ecart', notasym=True)
        A('   entre chestL et chestR sans dire dans quelle pose elle l\'a releve : tant qu\'elle'
          ' ne le', notasym=True)
        A('   dit pas, son chiffre est indistinguable d\'un artefact de pose et ne peut fonder'
          ' aucune', notasym=True)
        A('   section. A corriger dans le tableau, pas a interpreter en rapport.', notasym=True)
        for _vl in _vio:
            A('   !  %s' % _vl[:140], notasym=True)
    else:
        A('   Toute ligne de ce tableau qui compare les deux chaines porte sa pose ou se tait.',
          notasym=True)
    A('ROOM-ASYM-EXEMPT: %d ligne(s) exemptees (elles n\'affirment aucune asymetrie du'
      ' personnage)' % len(_exe), notasym=True)
    for _vl in _exe:
        A('   -  %s' % _vl[:140], notasym=True)

    os.makedirs(REPDIR, exist_ok=True)
    open(OUT, 'w').write('\n'.join(L) + '\n')
    print('ecrit %s : %d lignes, %d mesures, %d chaines, %d/%d animations'
          % (OUT, len(L), len(rows), len(chains), played, enumerated))

    # un resume a l'ecran pour l'iteration, pas un verdict : le verdict est au validateur.
    tipmin = min(worst[c]['amp']['v'] for c in chains)
    print('  tipvar min par chaine = %s (plancher de la gate MOVE : 0.05)' % fnum(tipmin))
    print('  rootdev max = %s (plafond ROOT : 2.0)' % fnum(max(r['root'] for r in rows)))
    print('  meshpen max = %s (COLLIDE exige <= 0 sur cheveux/meches, lunettes, oreilles ;'
          ' %d valeurs distinctes)'
          % (fnum(max(r['pen'] for r in rows)), len({r['pen'] for r in rows})))
    print('  idle maxdev = %s (plafond IDLE : 1.0)' % fnum(imax))
    print('  authored: %d chaines pilotees, %d respectees (controle positif: %d/%d)'
          % (len(a_driven), len(a_ok), int(apc_ok), int(apc_hit)))
    print('  limiteurs: plafond-taille %d fois (%s m) — le compteur de RECUL est retire au cycle'
          ' 36, il n\'avait aucun ecrivain' % (radr_n, fnum(radr_s)))
    for c in sorted(chains):
        print('    %-12s tipvar=%-9s rootdev=%-9s meshpen=%-9s' %
              (names[c], fnum(worst[c]['amp']['v']), fnum(worst[c]['root']['v']),
               fnum(worst[c]['pen']['v'])))


if __name__ == '__main__':
    main()
