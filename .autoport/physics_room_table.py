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
    lim = re.search(r'^PHYSLIM retreat_n=([-\d.e+]+) retreat_sum=([-\d.e+]+)'
                    r' raddrop_n=([-\d.e+]+) raddrop_sum=([-\d.e+]+) buried=([-\d.e+]+)', txt, re.M)
    if not lim:
        die('aucune ligne PHYSLIM : un limiteur qui ne chiffre pas ce qu\'il retire est interdit')
    retr_n, retr_s = int(float(lim.group(1))), float(lim.group(2)) / UNITS
    radr_n, radr_s = int(float(lim.group(3))), float(lim.group(4)) / UNITS
    buried_n = int(float(lim.group(5)))

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
    cvol = {}
    for m in re.finditer(r'^PHYSCVOL c=(\d+) ci=(\d+) n=(\d+)', txt, re.M):
        cvol.setdefault(int(m.group(1)), []).append((int(m.group(3)), int(m.group(2))))
    if not cvol:
        A('ROOM-CONTACT-VOL: non publie par la course')
    else:
        A('ROOM-CONTACT-VOL: %d chaine(s) contraintes par au moins un volume' % len(cvol))
        A('   par chaine, les volumes qui ont demande une correction, du plus frequent au moins')
        A('   frequent. Un contact a profondeur nulle n\'est PAS compte : seule une violation l\'est.')
        for ci_chain in sorted(cvol):
            nm = names[ci_chain] if ci_chain < len(names) else 'c%d' % ci_chain
            tot = sum(n for n, _ in cvol[ci_chain])
            det = ' · '.join('%s %d' % (colname.get(k, 'ci%d' % k), n)
                             for n, k in sorted(cvol[ci_chain], reverse=True)[:6])
            A('ROOM-CONTACT-VOL: chain=%-12s total=%-8d %s' % (nm, tot, det))
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
    A('   recul vers la pose du modele : %d fois, %s m au total%s'
      % (retr_n, fnum(retr_s),
         ' (jamais declenche)' if retr_n == 0 else ' soit %s m par declenchement'
         % fnum(retr_s / retr_n)))
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
    A('ROOM-RETREAT-ANCHOR: fallback=%s' % ('non publie par la course' if retfb_n < 0 else retfb_n))
    A('   fois ou le recul n\'a trouve AUCUN point admissible sur son chemin — pas meme la pose du')
    A('   modele — et s\'est pose sur le MOINS MAUVAIS. NATURE : un compte. LECTURE QUAND LE DEFAUT')
    A('   EST ABSENT : 0. Ce n\'est pas un limiteur de plus : c\'est l\'aveu que l\'invariant « la pose')
    A('   du modele est admissible » a cede. Il cede parce que `floor0` est mesure contre')
    A('   l\'INSTANTANE d\'auteur du volume et `dep` contre sa position COURANTE : pour un volume')
    A('   porte par un joint SIMULE (une meche voisine, un sein), les deux membres ne decrivent plus')
    A('   le meme obstacle. C\'est par la que `rmidhair` sortait a 0.0017 m de penetration — la')
    A('   SEULE ligne positive sur 3410. Le compteur etait emis par la salle et n\'etait lu par')
    A('   personne ; il l\'est desormais.')
    A('ROOM-RETREAT-SPHERE: rescued=%s' % ('non publie par la course' if sphere_n < 0
                                           else sphere_n))
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
            ring_row[nm] = dict(osc=osc, decay=decay, peak=peak, a0=a0, lags=lags, mono=mono,
                                di=di, span=span)
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
        for c in sorted(chains):
            v, nl = rr.get(c), chains[c]['links']
            if v is None:
                continue
            A('   rootrot %-12s %8.4f deg   (maillons=%d)' % (names[c], v, nl))
            # une chaine a 1 maillon n'a PAS de lien rootlock : son zero est une definition, pas un
            # defaut. Ne sont fautives que les chaines a 2+ maillons, celles que le generateur
            # rootlocke.
            if nl >= 2 and v <= 0.0:
                mute.append(names[c])
        if mute:
            A('   MUET sur %d chaine(s) a 2+ maillons : %s' % (len(mute), ' '.join(mute)))
            A('   Leur premier segment ne tourne pas d\'un degre : le defaut que l\'owner decrit est')
            A('   encore la, et il est STRUCTUREL, pas un reglage.')
        else:
            A('   Toutes les chaines a 2+ maillons ecrivent une rotation non nulle sur leur premier')
            A('   segment : le cuir chevelu est devenu une charniere au lieu d\'une soudure. Le')
            A('   controle positif est la version precedente du moteur, ou ce meme chiffre valait')
            A('   0.0000 sur TOUTES ces chaines — un zero structurel, pas un zero mesure.')
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
    # ---- ROOM-SKINPEN : la penetration contre la PEAU, a lire A COTE de meshpen ------------------
    sp_run = skinpen.get('run', {})
    if sp_run:
        A('')
        A('-- SPEC 18 : LA PENETRATION MESUREE CONTRE LA PEAU, PAS CONTRE LES VOLUMES ------------')
        A('   `meshpen` compte contre les volumes de collision, qui ne representent que 29.7 % de la')
        A('   geometrie que la physique pilote (0 % pour backhair, pantflapL, pantflapR ; 10 % pour')
        A('   les lunettes). Son zero est donc compatible avec ce que l\'owner voit. Cette colonne-ci')
        A('   mesure la MEME position ecrite contre le mesh qui est DESSINE.')
        A('   NATURE : profondeur en metres, positive = SOUS la peau. REPERE : le monde, frame')
        A('   ecrite. LECTURE HORS DEFAUT : 0. tests=0 veut dire « pas regarde », jamais « rien ».')
        _tot = max((t for _v, t in sp_run.values()), default=0)
        if _tot == 0:
            A('   ROOM-SKINPEN: AUCUN echantillon teste — le fichier physics_mesh.txt n\'est pas')
            A('   charge, ou aucun os du rig ne porte d\'ensemble. Ces zeros ne sont PAS une mesure.')
        for v, c in sorted(((v, c) for c, (v, _t) in sp_run.items()), reverse=True):
            A('ROOM-SKINPEN: chain=%-12s skinpen=%.4f m   meshpen=%.4f m'
              % (names[c] if c < len(names) else c, v,
                 (dr_run.get(c, {}) or {}).get('pen', 0.0) if isinstance(dr_run.get(c), dict) else 0.0))
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
        if sa <= sd * 3.0:
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
    print('  limiteurs: recul %d fois (%s m), plafond-taille %d fois (%s m)'
          % (retr_n, fnum(retr_s), radr_n, fnum(radr_s)))
    for c in sorted(chains):
        print('    %-12s tipvar=%-9s rootdev=%-9s meshpen=%-9s' %
              (names[c], fnum(worst[c]['amp']['v']), fnum(worst[c]['root']['v']),
               fnum(worst[c]['pen']['v'])))


if __name__ == '__main__':
    main()
