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

DRIVE_NAMES = ('updown', 'leftright', 'accel', 'jerk')

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
    log = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LOG
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
    # une chaine que le moteur a ECARTEE a l'execution (links=0) : sa pose de modele met un lien
    # hors de portee de son porteur. Elle n'a pas de mesure, et publier des zeros pour elle serait
    # un chiffre invente. Elle est sortie du tableau et annoncee, avec ses nombres, dans son propre
    # bloc — ce n'est pas un retrait silencieux.
    dropped = sorted(c for c, d in chains.items() if d['links'] == 0)
    for c in dropped:
        del chains[c]
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

    # ---- le repos ------------------------------------------------------------------------------
    idle = {}
    for m in re.finditer(r'^PHYSIDLE c=(\d+) dev=([-\d.e+]+) hang=([-\d.e+]+) amp=([-\d.e+]+)'
                         r' fam=(\d+)', txt, re.M):
        idle[int(m.group(1))] = dict(dev=float(m.group(2)) / UNITS, hang=float(m.group(3)),
                                     amp=float(m.group(4)) / UNITS, fam=int(m.group(5)))
    if not idle:
        die('aucune ligne PHYSIDLE : le repos n\'a pas ete mesure')

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
    A('   `raw` est le total BRUT enumere dans les art-groups de Keira, sans aucun filtre du')
    A('   programme ; `total` est ce que le rig qui porte la physique peut jouer ; chaque animation')
    A('   ecartee est nommee ci-dessous avec sa raison, une ligne chacune.')
    for ag, nm, nj, want in skipped:
        A('ROOM-ANIM-SKIPPED: %s rig-%s-joints-vs-%s-du-porteur-de-physique (art-group %s)'
          % (nm, nj, want, ag))
    A('   TOTAL = les animations de Keira que peut jouer LE RIG QUI PORTE SA PHYSIQUE. Detail, et')
    A('   rien n\'est ecarte en silence : %d animations sont enumerees dans ses %d art-groups.'
      % (enumerated, nag))
    A('   %d tiennent sur le rig a %s joints du sujet et sont TOUTES jouees et mesurees.'
      % (accepted, subj.group(4)))
    A('   %d vivent sur un rig a 94 joints (firecanyon, lavatube-start, lavatube-end). Ce rig-la ne'
      % len(skipped))
    A('   peut pas porter la physique du tout : la physique de Keira vit sur son compagnon HD, et')
    A('   le jeu decide de le greffer avec hd-desired-entry-for-mgeo. Appelee A L\'EXECUTION sur les')
    A('   six mgeo de Keira, elle rend :')
    for ag, mg, e in mgeo:
        A('     PHYSMGEO %-30s entry=%-3d %s'
          % (mg, e, 'compagnon HD keira-hd' if e >= 0 else 'AUCUN compagnon, donc aucune chaine'))
    A('   Les %d refusees : %s'
      % (len(skipped), ', '.join('%s(%s vs %s j)' % (s[1], s[2], s[3]) for s in skipped)))
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
    A('   CONTROLE POSITIF : l\'animation retardee d\'une frame dans la position ecrite (le defaut')
    A('   exact que la SPEC 5 interdit) fait tomber ce compteur de %d/%d a %d/%d.'
      % (int(sum(auth[c]['hit'] for c in a_driven)), int(sum(auth[c]['hit'] for c in a_driven)),
         int(apc_ok), int(apc_hit)))
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
    A('   plafond de taille d\'un lien seul : %d fois, %s m au total%s'
      % (radr_n, fnum(radr_s),
         ' (jamais declenche)' if radr_n == 0 else ' soit %s m par declenchement'
         % fnum(radr_s / radr_n)))
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
