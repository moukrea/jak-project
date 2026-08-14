#!/usr/bin/env python3
"""ldb_axsel.py — SPEC 24 relue sur un instrument qui porte les trois degres de liberte.

Phase Grecharged-secondary-motion, branche physics-keira-clean. Cycle du 2026-08-14.

CE QUE CE FICHIER TRANCHE, ET POURQUOI IL EXISTE
------------------------------------------------
Le cycle 8 a publie « un seul axe sur trois est isolable » (`ROOM-AXSEL` : pousser le sein le long
de son propre axe vertical ne met que 17.7 % de la reponse sur cet axe, 47.4 % part en AP), puis a
teste deux explications et les a REFUTEES toutes les deux : le triedre desoriente (`PHYSAXW` le
montre a 12 degres du monde) et la contrainte de longueur (`ROOM-AXSEL-NOLEN` : la lever DEGRADE
la selectivite). Il a conclu, honnetement, « la cause reste INCONNUE ».

La cause est dans la MESURE, pas dans le solveur. `phys-link-dev-anc` projette
`u/|u| - m/|m|` : une difference de deux vecteurs UNITAIRES, donc une grandeur TANGENTE a `m` au
premier ordre. Sa composante RADIALE est nulle PAR CONSTRUCTION, quelle que soit la physique.

Ce script publie le controle qui le demontre (`ROOM-AXPLANE`) et refait les mesures de SPEC 24 sur
la serie non normalisee que le moteur emet desormais a cote (`PHYSRINGBX`, tableau `*phys-ldb*`).

    serie              tag           grandeur projetee            degres de liberte
    normalisee         PHYSRINGAX    u/|u| - m/|m|  (sans dim.)   2 (tangente a m)
    NON normalisee     PHYSRINGBX    u - m          (unites u)    3

Les deux sortent du MEME instant de la MEME course : leur ecart est la mesure de l'aveuglement,
pas une seconde opinion qui pourrait contredire la premiere.

NATURE / REPERE / LIGNE DE BASE (les trois questions de SPEC 7, pour chaque grandeur publiee)
  ROOM-AXPLANE   : NATURE  un rapport de valeurs singulieres, sans dimension, et une DIRECTION.
                   REPERE  le triedre de l'ancre (torse), ordre (v, ap, lat).
                   ABSENT  une serie qui porte vraiment trois degres de liberte rend s3/s1 de
                           l'ordre de la dispersion des trois modes, jamais ~1 %.
  ROOM-AXSEL-ABS : NATURE  une part d'energie, sans dimension (valeur efficace d'une projection
                           rapportee a la somme des trois), moyenne RETIREE (une decroissance
                           libre est une grandeur alternative ; le residu statique n'en est pas).
                   REPERE  idem. ABSENT 33 % partout = aucune selectivite.
  ROOM-AXFIT-ABS : NATURE  une frequence (Hz) et un rapport d'amortissement, meme estimateur que
                           `ROOM-AXFIT` (sinusoide amortie + constante, balayage f x zeta).
                   REPERE  idem. ABSENT aucune ligne PHYSRINGBX (emetteurs non tires).
"""
import math
import re
import sys

try:
    import numpy as _np
except ImportError:
    _np = None

AXN = {0: 'v', 1: 'ap', 2: 'lat'}
# Les cibles de SPEC 24, nominal et plage. La verticale est LA PLUS LENTE, et c'est le point que le
# cycle 8 voyait a l'envers — sur des fenetres non isolees, donc sans pouvoir conclure.
TGT = {'v': (2.30, 2.1, 2.5), 'ap': (2.50, 2.3, 2.7), 'lat': (2.65, 2.4, 2.9)}


def load(txt, tag1, tag2):
    """Les deux lignes d'une meme fenetre, reunies par (axe excite, chaine, frame).

    `ax` est repete sur la seconde ligne parce que les trois fenetres repartent chacune a la
    frame 0 : `f` seule ne designe pas une fenetre.
    """
    S = {}
    for m in re.finditer(r'^%s c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)' % tag1, txt, re.M):
        S.setdefault((int(m.group(4)), int(m.group(1))), {}) \
         .setdefault(int(m.group(2)), [0.0, 0.0, 0.0])[0] = float(m.group(5))
    for m in re.finditer(r'^%s c=(\d+) f=(\d+) ax=(\d+) l=(\d+) ap=([-\d.e+]+) lat=([-\d.e+]+)'
                         % tag2, txt, re.M):
        d = S.setdefault((int(m.group(3)), int(m.group(1))), {}) \
             .setdefault(int(m.group(2)), [0.0, 0.0, 0.0])
        d[1] = float(m.group(5))
        d[2] = float(m.group(6))
    return S


def pca(rows):
    """Valeurs singulieres et vecteurs propres de la covariance des vecteurs (v, ap, lat).

    Sur une serie qui ne porte que deux degres de liberte, la troisieme valeur s'effondre et son
    vecteur propre EST la direction que l'instrument ne peut pas voir.
    """
    A = _np.array(rows, dtype=float)
    A = A - A.mean(axis=0)
    C = (A.T @ A) / max(1, len(rows))
    w, V = _np.linalg.eigh(C)
    order = _np.argsort(-w)
    w = w[order]
    V = V[:, order]
    # Le SIGNE d'un vecteur propre est arbitraire : sans convention, la meme direction s'imprime
    # tantot (+0.92,-0.36,+0.18) tantot (-0.92,+0.36,-0.18) et se lit comme DEUX directions. On
    # fixe le signe sur la composante de plus grand module.
    out = []
    for i in range(3):
        v = V[:, i].tolist()
        if v[max(range(3), key=lambda j: abs(v[j]))] < 0:
            v = [-x for x in v]
        out.append(v)
    return [math.sqrt(max(0.0, x)) for x in w], out


def fitseries(vals, skip=12):
    """Le MEME estimateur que `ROOM-AXFIT` de physics_room_table.py — recopie a l'identique.

    Sinusoide amortie PLUS une constante : le residu statique est absorbe par la colonne de 1,
    donc un eventuel offset ne peut pas se faire passer pour de l'oscillation. `skip` ecarte le
    transitoire : la loi est APRES lui, pas dedans.
    """
    y = _np.array(vals[skip:], dtype=float)
    n = len(y)
    if n < 20:
        return None
    t = _np.arange(n) / 60.0
    sy = float(_np.sum(y * y))
    if sy <= 0:
        return None
    best, keep = None, []
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


_FITCACHE = {}


def fit_axis(S, lbl, k, c):
    """`fitseries` sur la projection de l'axe EXCITE, MEMOISE.

    Le balayage f x zeta coute ~58 000 moindres carres par serie : le refaire pour `ROOM-AXORDER`
    apres l'avoir fait pour `ROOM-AXFIT-ABS` doublait le temps du tableau pour un resultat
    identique — et deux calculs du meme nombre sont surtout deux occasions de diverger.
    """
    key = (lbl, k, c)
    if key not in _FITCACHE:
        if (k, c) not in S:
            _FITCACHE[key] = None
        else:
            _FITCACHE[key] = fitseries([S[(k, c)][f][k] for f in sorted(S[(k, c)])])
    return _FITCACHE[key]


def selectivity(S, k, c):
    """Part de la reponse tombant sur chaque projection, moyenne retiree."""
    r = {}
    for i, ax in AXN.items():
        if (k, c) not in S:
            return None
        vals = [S[(k, c)][f][i] for f in sorted(S[(k, c)])]
        mu = sum(vals) / len(vals)
        r[ax] = math.sqrt(sum((x - mu) ** 2 for x in vals) / len(vals))
    return r


def chain_names(txt, chains_file='recharged_assets/physics_chains.txt'):
    """Les NOMS, depuis le fichier de donnees, dans l'ordre ou il les declare.

    La meme source que physics_room_table.py, pour que les deux sorties nomment la meme chaine
    pareil. La ligne `PHYSCHAIN j0=` de la trace donne le joint racine : elle VERIFIE l'appariement
    au lieu de le supposer, et un desaccord est SIGNALE dans le nom plutot qu'absorbe en silence.
    """
    decl = []
    cur = None
    try:
        fh = open(chains_file, errors='ignore')
    except OSError:
        return {}
    with fh:
        for ln in fh:
            mm = re.match(r'chain (\S+) ', ln)
            if mm:
                decl.append([mm.group(1), None])
                cur = decl[-1]
            elif ln.startswith('j ') and cur is not None and cur[1] is None:
                cur[1] = ln.split()[1]
    names = {}
    for m in re.finditer(r'^PHYSCHAIN c=(\d+) links=\d+ fam=\d+ hang=[-\d.]+ j0=(\S+)', txt, re.M):
        c, j0 = int(m.group(1)), m.group(2)
        if c < len(decl):
            names[c] = decl[c][0]
            if decl[c][1] and decl[c][1] != j0:
                names[c] = '%s(!j0=%s)' % (decl[c][0], j0)
        else:
            names[c] = 'c%d' % c
    return names


def lines(txt, names=None):
    """Les lignes a publier, pour que physics_room_table.py les APPENDE au tableau.

    On rend une liste au lieu d'imprimer : le tableau reste le seul artefact publie, et il n'existe
    pas deux versions de ces chiffres qui pourraient deriver l'une de l'autre.
    """
    if names is None:
        names = chain_names(txt)
    out = []
    A = out.append

    if _np is None:
        A('ROOM-AXPLANE: ABSENT (numpy indisponible)')
        return out

    NORM = load(txt, 'PHYSRINGAX', 'PHYSRINGAX2')
    RAW = load(txt, 'PHYSRINGBX', 'PHYSRINGBX2')
    NORM_Z = load(txt, 'PHYSRINGAZ', 'PHYSRINGAZ2')
    RAW_Z = load(txt, 'PHYSRINGBZ', 'PHYSRINGBZ2')

    # ---- 1. LE CONTROLE DE L'INSTRUMENT LUI-MEME ------------------------------------------------
    A('   ROOM-AXPLANE — LA SERIE PORTE-T-ELLE TROIS DEGRES DE LIBERTE, OU DEUX ?')
    A('   `s3/s1` est le rapport de la plus petite a la plus grande valeur singuliere du nuage des')
    A('   vecteurs (v, ap, lat). Une serie PLANE (s3/s1 ~ 1 %) ne peut pas porter trois frequences')
    A('   propres : la direction NULLE est celle que la mesure annule, pas celle que la physique')
    A('   interdit. Les fenetres `Z` ont la contrainte de longueur LEVEE — si elles restent planes,')
    A('   la cecite n\'est pas dans le solveur.')
    A('')
    A('   `s2/s3` dit si la direction nulle est DETERMINEE : une reponse quasi 1-D (s2 ~ s3) laisse')
    A('   le couple des deux petites directions libre de tourner dans son plan, et la direction')
    A('   imprimee n\'y veut alors rien dire. On ne lit la colonne de droite que sur les lignes ou')
    A('   `s2/s3` est franchement > 5.')
    A('')
    A('   serie             excite chaine     s1        s2        s3      s3/s1  s2/s3  direction NULLE')
    for lbl, S in (('normalisee', NORM), ('NON normalisee', RAW),
                   ('normalisee/Z', NORM_Z), ('NON normalisee/Z', RAW_Z)):
        if not S:
            A('   %-17s ABSENTE de la trace' % lbl)
            continue
        for c in sorted({c for (_k, c) in S}):
            nm = names.get(c, 'c%d' % c)
            for k in (0, 1, 2):
                if (k, c) not in S:
                    continue
                rows = [S[(k, c)][f] for f in sorted(S[(k, c)])]
                if len(rows) < 20:
                    continue
                s, V = pca(rows)
                _det = s[1] / s[2] if s[2] else float('inf')
                A('   %-17s %-4s  %-10s %.2e %.2e %.2e  %6.4f %5.1f  (%+.3f,%+.3f,%+.3f) %s'
                  % (lbl, AXN[k], nm, s[0], s[1], s[2],
                     s[2] / s[0] if s[0] else 0.0, _det, V[2][0], V[2][1], V[2][2],
                     '' if _det > 5.0 else '<- indeterminee'))
    A('')

    # ---- 1 bis. LA PREUVE ALGEBRIQUE, ET C'EST ELLE QUI TRANCHE ---------------------------------
    # La PCA MONTRE que la serie est plane ; elle ne dit pas POURQUOI. L'identite ci-dessous le dit,
    # et elle est exacte, pas statistique.
    #   `dv = u/|u| - m/|m|` est une difference de DEUX VECTEURS UNITAIRES. Donc
    #        |dv|^2 = 2 - 2 (u.m)   et   dv.m = (u.m) - 1 = -|dv|^2 / 2      EXACTEMENT.
    # On ajuste donc `m` SANS CONTRAINTE (moindres carres sur dv.m = -|dv|^2/2) et on regarde deux
    # choses qu'aucun ajustement ne peut fabriquer :
    #   - le R^2 de l'identite : si la grandeur n'etait pas une difference d'unitaires, il chuterait ;
    #   - la NORME du `m` ajuste : elle doit sortir a 1.0000 alors qu'on ne l'a jamais imposee.
    # Si les deux tiennent, la direction `m` EST la direction d'os du modele, et c'est exactement
    # celle que la mesure annule. Le controle croise gratuit : `chestL` et `chestR` sont une paire
    # miroir du rig, donc leurs `m` doivent sortir opposes sur la composante laterale du triedre.
    A('   ROOM-AXBLIND — POURQUOI LA SERIE EST PLANE : L\'IDENTITE DE LA DIFFERENCE D\'UNITAIRES.')
    A('   `dv.m = -|dv|^2/2` est vraie EXACTEMENT pour une difference de deux vecteurs unitaires, et')
    A('   pour rien d\'autre. `m` est ajuste sans contrainte de norme : s\'il sort a |m|=1, la')
    A('   grandeur mesuree EST une difference de directions, et `m` est la direction AVEUGLE.')
    A('')
    A('   serie             excite chaine     m ajuste (v, ap, lat)        R2        |m|     part_v')
    for lbl, S in (('normalisee', NORM), ('NON normalisee', RAW)):
        if not S:
            A('   %-17s ABSENTE de la trace' % lbl)
            continue
        for c in sorted({c for (_k, c) in S}):
            nm = names.get(c, 'c%d' % c)
            for k in (0, 1, 2):
                if (k, c) not in S:
                    continue
                D = _np.array([S[(k, c)][f] for f in sorted(S[(k, c)])], dtype=float)
                if len(D) < 20:
                    continue
                y = -0.5 * (D * D).sum(axis=1)
                mv, *_ = _np.linalg.lstsq(D, y, rcond=None)
                pred = D @ mv
                den = float(((y - y.mean()) ** 2).sum())
                r2 = 1.0 - float(((pred - y) ** 2).sum()) / den if den > 0 else float('nan')
                nrm = float(_np.linalg.norm(mv))
                u = (mv / nrm) if nrm > 0 else mv
                if u[int(_np.argmax(_np.abs(u)))] < 0:
                    u = -u
                A('   %-17s %-4s  %-10s (%+.4f,%+.4f,%+.4f)  %9.5f  %.4f  %5.1f%%'
                  % (lbl, AXN[k], nm, u[0], u[1], u[2], r2, nrm, 100.0 * u[0] * u[0]))
    A('')
    A('   LECTURE : sur la serie NORMALISEE, R2 = 1 et |m| = 1 -> la grandeur est bien une')
    A('   difference de directions, et `part_v` dit quelle FRACTION de la direction aveugle tombe')
    A('   sur l\'axe VERTICAL — celui dont SPEC 24 dit qu\'il est « le plus lent ». Sur la serie NON')
    A('   normalisee la meme identite doit ECHOUER (R2 loin de 1) : c\'est la preuve qu\'elle porte')
    A('   autre chose qu\'un ecart de directions.')
    A('')

    # ---- 1 ter. LE TRIEDRE PORTE-T-IL LES BONS NOMS ? --------------------------------------------
    # SPEC 29 donne des compliances DIFFERENTES a l'avant-arriere (0.90) et au lateral (0.82), et
    # SPEC 24 des frequences differentes (2.50 / 2.65). Si les deux roles sont intervertis, le
    # mecanisme est arme, la mesure est propre, et les deux sections sont pourtant fausses — sans
    # que rien ne le signale. Il faut donc une mesure qui NOMME les axes, pas qui les suppose.
    # LE DISCRIMINANT, ET IL NE SUPPOSE RIEN D'AUTRE QUE DE L'ANATOMIE : les deux seins sont
    # separes GAUCHE-DROITE. `lBoob` et `rBoob` ont le MEME parent dans le rig (joint 3, `chest`,
    # verifie dans keira-hd-k2e.json), donc leurs deux os partent du meme point et la difference de
    # leurs vecteurs EST le segment qui va d'un sein a l'autre. L'axe qui porte ce segment est le
    # LATERAL, par definition. `m` vient de l'identite ci-dessus, `|m|` de `PHYSBONE`.
    if len(NORM) and len({c for (_k, c) in NORM}) == 2:
        A('   ROOM-AXLABEL — LE TRIEDRE PORTE-T-IL LES BONS NOMS ?')
        A('   Le segment qui separe les deux seins est LATERAL par anatomie. On le reconstruit')
        A('   (meme attache : parent commun joint 3 `chest`) et on regarde sur quel axe il tombe.')
        blen = {}
        for m in re.finditer(r'^PHYSBONE c=(\d+) l=0 len=([-\d.]+)', txt, re.M):
            blen[int(m.group(1))] = float(m.group(2))
        mh = {}
        for c in sorted({c for (_k, c) in NORM}):
            D = _np.array([NORM[(0, c)][f] for f in sorted(NORM[(0, c)])], dtype=float) \
                if (0, c) in NORM else None
            if D is None or len(D) < 20:
                continue
            y = -0.5 * (D * D).sum(axis=1)
            mv, *_ = _np.linalg.lstsq(D, y, rcond=None)
            nr = float(_np.linalg.norm(mv))
            if nr > 0:
                mh[c] = mv / nr
        cs = sorted(mh)
        if len(cs) == 2 and all(c in blen for c in cs):
            sep = blen[cs[0]] * mh[cs[0]] - blen[cs[1]] * mh[cs[1]]
            nrm = float(_np.linalg.norm(sep))
            frac = 100.0 * (sep ** 2) / max(1e-30, float((sep ** 2).sum()))
            dom = AXN[int(_np.argmax(_np.abs(sep)))]
            A('   separation %s - %s = (%+.2f, %+.2f, %+.2f) u   norme %.2f u = %.1f cm'
              % (names.get(cs[0], 'c0'), names.get(cs[1], 'c1'),
                 sep[0], sep[1], sep[2], nrm, nrm / 40.96))
            A('   part d\'energie :  v %5.1f%%   ap %5.1f%%   lat %5.1f%%'
              % (frac[0], frac[1], frac[2]))
            if dom == 'lat':
                A('   -> le segment gauche-droite tombe sur l\'axe nomme `lat`. LES NOMS SONT BONS.')
            else:
                A('   -> le segment gauche-droite tombe sur l\'axe nomme `%s`, PAS sur `lat`.' % dom)
                A('      LES ROLES `ap` ET `lat` SONT INTERVERTIS. Consequence directe : SPEC 29')
                A('      applique la compliance 0.90 (avant-arriere) au LATERAL et 0.82 (lateral) a')
                A('      l\'AVANT-ARRIERE, et les cibles de SPEC 24 (2.50 / 2.65 Hz) sont comparees')
                A('      aux mauvais axes. Le mecanisme est arme et la mesure est propre : c\'est')
                A('      l\'ETIQUETTE qui est fausse, et rien d\'autre ne pouvait le signaler.')
        else:
            A('   ROOM-AXLABEL: ABSENT (il faut 2 chaines avec `PHYSBONE l=0` et une fenetre v)')
        A('')

    # ---- 2. LA SELECTIVITE, SUR LES DEUX INSTRUMENTS ---------------------------------------------
    A('   ROOM-AXSEL-ABS — LA MEME SELECTIVITE, SUR LES QUATRE COMBINAISONS.')
    A('   Deux facteurs se croisent, et le cycle 8 ne pouvait en voir qu\'un :')
    A('     INSTRUMENT  `norm` = difference d\'unitaires (aveugle au radial) · `abs` = non normalise')
    A('     SOLVEUR     contrainte de longueur ARMEE · LEVEE (`*phys-len-off*`, fenetres Z)')
    A('   `sel` = part de la reponse tombant sur l\'axe POUSSE. La case qui decide est `abs/levee` :')
    A('   c\'est la seule ou le degre de liberte radial existe ET peut etre vu. Si la selectivite y')
    A('   monte, la contrainte de longueur EST ce qui confisque le troisieme mode — l\'hypothese que')
    A('   le cycle 8 avait posee puis declaree refutee en la lisant avec l\'instrument aveugle.')
    A('')
    A('   excite chaine        norm/armee   abs/armee    norm/levee   abs/levee    -> dominant (abs/levee)')
    for c in sorted(set().union(*[{c for (_k, c) in S} for S in (NORM, RAW, NORM_Z, RAW_Z) if S])
                    or set()):
        nm = names.get(c, 'c%d' % c)
        for k in (0, 1, 2):
            cells = []
            for S in (NORM, RAW, NORM_Z, RAW_Z):
                r = selectivity(S, k, c) if S else None
                if r is None:
                    cells.append('    --   ')
                    continue
                t = sum(r.values()) or 1.0
                cells.append('  %5.1f%%  ' % (100 * r[AXN[k]] / t))
            # La colonne de verdict lit `abs/levee` ET RIEN D'AUTRE. Un repli silencieux sur une
            # autre serie ferait porter a cette colonne un titre qu'elle ne tient pas — c'est
            # exactement la lecture faussee que ce fichier existe pour retirer.
            _rz = selectivity(RAW_Z, k, c) if RAW_Z else None
            if _rz is None:
                mark = '-- (abs/levee absente)'
            else:
                _d = max(_rz, key=_rz.get)
                mark = 'ISOLE' if _d == AXN[k] else 'melange->%s' % _d.upper()
            A('   %-4s   %-12s %s %s %s %s  %s'
              % (AXN[k], nm, cells[0], cells[1], cells[2], cells[3], mark))
    A('')

    # ---- 3. SPEC 24 : LES TROIS FREQUENCES, SUR L'INSTRUMENT NON AVEUGLE -------------------------
    A('   ROOM-AXFIT-ABS — SPEC 24 : TROIS FREQUENCES PROPRES, UNE PAR AXE.')
    A('   Lue sur la serie NON normalisee, sur la projection de l\'axe EXCITE (la fenetre ou cet')
    A('   axe est le mode, pas la diaphonie). `sel` rappelle la selectivite de cette fenetre : une')
    A('   frequence lue sur une fenetre non isolee reste un MELANGE et le dit.')
    A('')
    A('   ATTENTION AU STATUT DES DEUX BLOCS, ILS NE SE COMPARENT PAS A SA SPEC DE LA MEME FACON :')
    A('     `armee` = LA CONFIGURATION LIVREE. C\'est la seule qui puisse tenir ou non sa §24.')
    A('     `levee` = UN CONTROLE, contrainte de longueur desarmee. Le systeme n\'est plus celui')
    A('        qu\'on livre : la frequence qu\'on y lit dit ce que le mode vertical VAUDRAIT si le')
    A('        degre de liberte existait. C\'est un diagnostic, pas une conformite.')
    A('')
    A('   etat   excite chaine        n    f (Hz)   intervalle        zeta   residu   sel     cible §24')
    for lbl, S in (('armee', RAW), ('levee', RAW_Z)):
        if not S:
            A('   %-6s ABSENTE de la trace' % lbl)
            continue
        for c in sorted({c for (_k, c) in S}):
            nm = names.get(c, 'c%d' % c)
            for k in (0, 1, 2):
                if (k, c) not in S:
                    continue
                ax = AXN[k]
                r = fit_axis(S, lbl, k, c)
                sel = selectivity(S, k, c)
                selp = 100 * sel[ax] / (sum(sel.values()) or 1.0) if sel else 0.0
                if not r:
                    A('   %-6s %-4s   %-12s  serie trop courte ou nulle' % (lbl, ax, nm))
                    continue
                nom, lo, hi = TGT[ax]
                mark = 'DANS' if lo <= r['f'] <= hi else 'HORS'
                # Une frequence lue sur une fenetre non isolee reste un MELANGE, quel que soit son
                # residu d'ajustement : on le dit sur la ligne au lieu de le laisser au lecteur.
                if selp < 40.0:
                    mark += ' (fenetre NON ISOLEE, sel<40% : melange)'
                A('   %-6s %-4s   %-12s %3d  %7.4f  [%6.4f,%6.4f]  %5.3f  %6.4f  %4.1f%%  %.2f (%.1f-%.1f) %s'
                  % (lbl, ax, nm, r['n'], r['f'], r['fmin'], r['fmax'], r['zeta'], r['rel'], selp,
                     nom, lo, hi, mark))
    A('')

    # ---- 4. L'ORDRE QUE SPEC 24 IMPOSE ------------------------------------------------------------
    A('   ROOM-AXORDER — SPEC 24 : « vertical motion is intentionally the SLOWEST ».')
    A('   L\'ordre f_v < f_ap < f_lat est une exigence de SA section, independante des nominaux.')
    for lbl, S in (('armee', RAW), ('levee', RAW_Z)):
        if not S:
            continue
        for c in sorted({c for (_k, c) in S}):
            nm = names.get(c, 'c%d' % c)
            fs, sp = {}, {}
            for k in (0, 1, 2):
                if (k, c) not in S:
                    continue
                r = fit_axis(S, lbl, k, c)
                sel = selectivity(S, k, c)
                if r:
                    fs[AXN[k]] = r['f']
                    sp[AXN[k]] = 100 * sel[AXN[k]] / (sum(sel.values()) or 1.0) if sel else 0.0
            if len(fs) == 3:
                ok = fs['v'] < fs['ap'] < fs['lat']
                # L'ECART RELATIF entre la plus haute et la plus basse : trois frequences a 1 % les
                # unes des autres ne sont pas trois modes, c'est un mode vu trois fois — et ca se
                # dit avec un chiffre, pas avec un adjectif.
                spread = (max(fs.values()) - min(fs.values())) / min(fs.values())
                A('   %-6s %-12s f_v=%.4f  f_ap=%.4f  f_lat=%.4f  etalement=%.1f%%  -> %s'
                  % (lbl, nm, fs['v'], fs['ap'], fs['lat'], 100 * spread,
                     'ORDRE TENU' if ok else 'ORDRE NON TENU'))
                if min(sp.values()) < 40.0:
                    A('   %-6s %-12s   (dont %d fenetre(s) NON ISOLEE(s) : l\'ordre lu dessus ne'
                      ' decide rien)' % (lbl, nm, sum(1 for v in sp.values() if v < 40.0)))
            else:
                A('   %-6s %-12s incomplet (%d axes sur 3 ajustables)' % (lbl, nm, len(fs)))

    return out


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else \
        '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
    txt = open(log, errors='replace').read()
    print('\n'.join(lines(txt)))


if __name__ == '__main__':
    main()
