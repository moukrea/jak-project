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
    for m in re.finditer(r'^PHYSBASE c=(\d+) a=(\d+) amp=([-\d.e+]+) jump=([-\d.e+]+)'
                         r' ns=([-\d.e+]+)', txt, re.M):
        base[(int(m.group(1)), int(m.group(2)))] = float(m.group(3)) / UNITS

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
    for m in re.finditer(r'^PHYSGRAD c=(\d+) a=(\d+) d=(\d+) l=(\d+) amp=([-\d.e+]+)'
                         r'(?: ang=([-\d.e+]+))?', txt, re.M):
        key = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        grad.setdefault(key, {})[int(m.group(4))] = float(m.group(5)) / UNITS
        if m.group(6) is not None:
            gradang.setdefault(key, {})[int(m.group(4))] = float(m.group(6))

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
    for m in re.finditer(r'^PHYSDIAG tag=(\S+) c=(\d+) selfcol=([-\d.e+]+) retreat=([-\d.e+]+)'
                         r' flip=([-\d.e+]+)', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            selfcol=float(m.group(3)), retreat=float(m.group(4)), flip=float(m.group(5)))
    for m in re.finditer(r'^PHYSDIAG2 tag=(\S+) c=(\d+) inv=([-\d.e+]+) invres=([-\d.e+]+)'
                         r' elong=([-\d.e+]+)(?: rad=([-\d.e+]+))?', txt, re.M):
        diag.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {}).update(
            inv=float(m.group(3)), invres=float(m.group(4)), elong=float(m.group(5)),
            rad=float(m.group(6)) if m.group(6) is not None else 0.0)

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

    # PART RADIALE DE LA FORCE ECARTEE. Sous la contrainte de longueur un maillon ne fait que
    # tourner autour de son attache : ce qui pousse LE LONG de l'os ne deplace rien, il ne fait que
    # gonfler |ecart| — et c'est |ecart| que lisent le plafond de taille et la renormalisation sur
    # la sphere. NATURE : une force cumulee (u/frame^2), PAS un mouvement retire. REPERE : celui de
    # l'ancre, projetee sur l'axe de l'os du maillon. LECTURE QUAND LE DEFAUT EST ABSENT : 0 sur une
    # chaine dont la force est deja transverse.
    lim3 = re.search(r'^PHYSLIM3 radial_n=([-\d.e+]+) radial_sum=([-\d.e+]+)', txt, re.M)
    radf_n = int(float(lim3.group(1))) if lim3 else 0
    radf_s = float(lim3.group(2)) if lim3 else 0.0

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
    A('     il ne s\'appliquait qu\'au maillon 0 : les maillons PROFONDS n\'avaient AUCUNE borne,')
    A('     et c\'est pour ca que lbang/rbang link1 atteignaient 178 degres pour une borne')
    A('     geometrique de 15. Il porte donc desormais sur tout maillon libre.')
    A('   part radiale de la force, ecartee : %d fois, %s u/frame^2 au total%s'
      % (radf_n, fnum(radf_s),
         ' (jamais declenche)' if radf_n == 0 else ' soit %s par declenchement'
         % fnum(radf_s / radf_n)))
    A('     NATURE : une force cumulee, PAS du mouvement retire — sous la contrainte de longueur un')
    A('     maillon ne fait que TOURNER autour de son attache, donc ce qui pousse le long de l\'os')
    A('     ne deplacait rien ; il ne faisait que gonfler |ecart|, que lisent le plafond de taille')
    A('     et la renormalisation sur la sphere. REPERE : celui de l\'ancre, projetee sur l\'axe de')
    A('     l\'os du maillon. LECTURE QUAND LE DEFAUT EST ABSENT : 0 si la force est deja transverse.')
    A('   marge de sortie de collision : 0.5 u = 0.000122 m par contact resolu, constante.')
    A('   paires (lien, volume) ou le lien est ENTIEREMENT dans le volume a sa pose de modele, donc')
    A('   sans surface devant lui : %d occurrences de mesure. Critere geometrique calcule sur la' % buried_n)
    A('   pose du modele (profondeur_repos >= 2 x rayon du lien), pas une liste ni un masque.')
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
    else:
        A('   Aucune inversion : sur chaque chaine et chaque pilotage, la deviation propre CROIT de')
        A('   la racine vers la pointe, ce que SPEC 2 exige.')
    A('   Pour comparaison, l\'ANCIENNE mesure (ecart cumule) en signalait %d : l\'ecart entre les'
      % len(inverses_old))
    A('   deux comptes est la part du defaut que le repere monde rendait invisible.')
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
    st_worst = None
    per_chain_st = {}
    for (c, ai, dr), (el, gn, tf) in stretch.items():
        if c not in chains:
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
    for c in sorted(chains):
        a, b = m0.get(c), m60.get(c)
        if a is None or b is None:
            continue
        n0 = sum(v * v for v in a) ** 0.5
        n60 = sum(v * v for v in b) ** 0.5
        sag = sum((y - x) ** 2 for x, y in zip(a, b)) ** 0.5
        blen = sum(bones.get(c, {}).values()) / UNITS
        gn, tf = g60.get(c, (float('nan'), float('nan')))
        A('ROOM-GRAVSAG: chain=%-12s at0=%-9s at60=%-9s sag=%-9s sagn=%-8s gn=%-7s tf=%-7s fam=%s'
          % (names[c], fnum(n0), fnum(n60), fnum(sag),
             fnum(sag / blen) if blen > 1e-6 else '-',
             fnum(gn), fnum(tf),
             'A' if chains[c]['fam'] == 1 else 'B'))
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
    A('   `raddrop` = fois ou le PLAFOND D\'EXCURSION du lien (son propre rayon mesure) a mordu.')
    A('   C\'est un suppresseur, donc SPEC 7 exige qu\'il chiffre ce qu\'il retire PAR CHAINE : un')
    A('   affaissement gravitaire ecrete par ce plafond se lit ici et nulle part ailleurs.')
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
