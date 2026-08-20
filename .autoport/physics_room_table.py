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
    _oricom_mass_block(A, txt, names, com, com2, role, axis, b0)
    _orictl_block(A, txt, names, ori, axis, b0)


# ------------------------------------------------------------------------------------------------
# SPEC 10/11/12 SUR UN **COM**, ET PLUS SUR UN APEX
# ------------------------------------------------------------------------------------------------
_COM_MASS_JSON = 'reports/Grecharged-secondary-motion/breast-com-mass.json'


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
        ictl = [i for (cc, i, l) in comL if cc == c and l == nl - 1 and (cc, i) in com]
        worst, worst_i, nbase = 0.0, None, 0
        base_a = base_t = float('nan')
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
                rel = abs(na - nt) / max(na, nt)
                if rel > worst:
                    worst, worst_i = rel, i
        A('ROOM-ORICOM-MASS: %-12s CONTROLE pointe : |sum ldb| (PHYSORICOML, cumul) contre |t|'
          % nm)
        A('   (PHYSORICOM), pire ecart relatif %.4f%s sur %d orientations chargees — deux'
          % (worst * 100.0, (' %% (i=%d)' % worst_i) if worst_i is not None else ' %', nbase))
        A('   accumulateurs independants, deux triedres, un seul nombre. %s'
          % ('accord' if worst < 0.05 else
             'DESACCORD > 5 % : le montage est en cause, pas la physique — '
             'les lignes ci-dessous sont suspendues a ce constat'))
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
            A('                              squelettique seul %s  ·  cible %.2f (bande %.2f-%.2f)'
              '  ·  rr(joint, pour memoire, NON compose) %.4f'
              % ('DANS' if band[0] <= base <= band[1] else
                 ('SOUS — borne INFERIEURE, la part tensorielle manque' if base < band[0]
                  else 'AU-DESSUS'), nom, band[0], band[1], rr))
        d0 = rec['defs'][0]
        A('   (frontieres w>0 / w>=0.05 / w>=0.25 — les trois colonnes de |d_COM| ci-dessus ;'
          ' N=%d, part de l\'organe portee par la chaine %.4f, le reste est ancre au buste)'
          % (d0['n'], sum(d0['W']) / float(d0['n'])))
    A('')


def _orictl_block(A, txt, names, ori, axis, b0):
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
            A('ROOM-ORICTL-DIAG: %-12s %s  supine i=6 inv=%.0f flip=%.0f · prone i=8 inv=%.0f'
              ' flip=%.0f · i=5 flip=%.0f · i=7 flip=%.0f'
              % (nm, KN.get(k, 'k=%d' % k), r6[1], r6[2], r8[1], r8[2], r5[2], r7[2]))
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
    txt = open(log, errors='ignore').read()

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
    for m in re.finditer(r'^PHYSSKIN tag=(\S+) c=(\d+) skinpen=([-\d.e+]+) tests=(\d+)', txt, re.M):
        skinpen.setdefault(m.group(1), {})[int(m.group(2))] = (
            float(m.group(3)) / UNITS, int(m.group(4)))
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
    pc = re.search(r'^PHYSPC injections=(\d+) armed=([-\d.e+]+) disarmed=([-\d.e+]+)', txt, re.M)
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
    A = L.append
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
    A('-- LE PILOTAGE (SPEC 6 : haut/bas, gauche/droite, diverses accelerations, a-coups) ---------')
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
        for lft, rgt in (('lbang', 'rbang'), ('lmidhair', 'rmidhair'), ('chestL', 'chestR'),
                         ('earL', 'earR')):
            if lft in _sagt and rgt in _sagt:
                sn_l, sn_r = _sagt[lft][0], _sagt[rgt][0]
                st_l, st_r = _sagt[lft][2], _sagt[rgt][2]
                r_bru = max(sn_l, sn_r) / min(sn_l, sn_r) if min(sn_l, sn_r) > 1e-9 else float('inf')
                r_cor = max(st_l, st_r) / min(st_l, st_r) if min(st_l, st_r) > 1e-9 else float('inf')
                A('ROOM-GRAVSAG-MIRROR: %s/%s  ecart brut(sagn)=%.2fx  ecart corrige(sagt)=%.2fx'
                  % (lft, rgt, r_bru, r_cor))
    if g0:
        A('   (debout, la meme gravite effective vaut : %s)'
          % ' '.join('%s=%s' % (names[c], fnum(g0[c][0]))
                     for c in sorted(g0) if c < len(names)))
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
            for _r in (9, 10, 13, 14):
                _kl2, _kr2 = (_cl[0], _r), (_cr[0], _r)
                if _kl2 not in _rgk or _kr2 not in _rgk:
                    A('ROOM-REGIME-MIRROR: r=%2d %-13s FENETRE MANQUANTE OU ECARTEE sur au moins'
                      ' une chaine : aucun ecart' % (_r, _rgtab[_r][1]))
                    continue
                _vl, _vr = _rga[_kl2][0], _rga[_kr2][0]
                _mn = 0.5 * (_vl + _vr)
                A('ROOM-REGIME-MIRROR: r=%2d %-13s com(chestL)=%.4f com(chestR)=%.4f  ecart %s'
                  % (_r, _rgtab[_r][1], _vl, _vr,
                     ('%.2f %%' % (100.0 * abs(_vl - _vr) / _mn)) if _mn > 0 else
                     'INDEFINI (les deux valent 0)'))
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
        for v, c in sorted(((v, c) for c, (v, _t) in sp_run.items()), reverse=True):
            _mp = (worst.get(c) or {}).get('pen')
            A('ROOM-SKINPEN: chain=%-12s skinpen=%.4f m   meshpen=%s'
              % (names[c] if c < len(names) else c, v,
                 ('%s m' % fnum(_mp['v'])) if _mp else 'NON-MESURE'))
        A('ROOM-SKINPEN-TESTS: %d echantillons de surface compares sur la fenetre' % _tot)
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
            for _sp, _n, _o, _a2, _b2 in sorted(_pairs, reverse=True):
                A('ROOM-SKINPEN-MIRROR: %-12s %.4f  vs %-12s %.4f   ecart %4.0f %%'
                  % (_n, _a2, _o, _b2, 100 * _sp))
            A('ROOM-SKINPEN-FLOOR: %.4f m — AUCUNE valeur de la colonne ci-dessus n\'est'
              ' interpretable en dessous de ce plancher.' % _worst)
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
          ' ns=%d'
          % (names[r['c']], anims[r['ai']]['name'], DRIVE_NAMES[r['dr']],
             fnum(r['amp']), fnum(r['root']), fnum(r['pen']), fnum(r['jump']), int(r['ns'])))
    A('')
    A('%d lignes de mesure, %d chaines x %d animations x %d pilotages.'
      % (len(rows), len(chains), played, len(DRIVE_NAMES)))

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
        # NATURE  deux grandeurs par fenetre : `perr` = |apex - cible de repos| / B0, MAXIMUM de la
        #   fenetre (l'instrument existait avant ce cycle, PHYSRESTW) ; `jump` = pire ecart de la
        #   pointe d'UNE frame a la suivante, en unites de jeu, sur la POSE ECRITE.
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
