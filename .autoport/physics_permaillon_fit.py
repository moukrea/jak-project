#!/usr/bin/env python3
"""physics_permaillon_fit.py — SPEC 24, MESUREE PAR MAILLON, ET L'INSTRUMENT DECLARE SA PROPRE
RESOLUTION.

POURQUOI CET INSTRUMENT (cycle 31)
==================================
Le cycle 30 a grade SPEC 24 « TENUE, 12 canaux sur 12 » sur une VERIFICATION ARITHMETIQUE
(`f = stiffness/sqrt(mass) * sqrt(1/mobilite)`), et il l'a lui-meme assortie d'une reserve ecrite.
Les DIRECTIVES sont pourtant explicites, troisieme rappel : « une section n'est TENUE que si sa
valeur est LUE A L'EXECUTION sur le mecanisme arme ». Une conformite calculee n'est pas mesuree.

ET L'INSTRUMENT QUI DEVRAIT LA CONSTATER N'EXISTAIT PAS, PARCE QUE LES DEUX QUI EXISTENT SONT
CHACUN AVEUGLE A UNE MOITIE DE LA CHAINE — et jamais cote a cote, donc jamais confrontes :

    ROOM-RINGFIT (le verdict DANS/SOUS du tableau)  physics_room_table.py:4106  `if l != 0: continue`
                                                     -> ne voit QUE le maillon RACINE
    RINGAXIS     (le bloc SPEC 24 du ringdown)       physics_ringdown.py:521     `tip = max(l ...)`
                                                     -> ne voit QUE le maillon de POINTE

La trace, elle, porte `l=` depuis toujours (`phys-room.gc:1621` boucle sur tous les maillons).
Rien ne manquait dans la donnee : ce sont les DEUX lecteurs qui jetaient, chacun, la moitie que
l'autre gardait.

LES TROIS QUESTIONS DE SPEC-keira-physique 7, REPONDUES AVANT D'ECRIRE LE CHIFFRE
=================================================================================
  NATURE  : une FREQUENCE PROPRE (Hz) et un rapport d'amortissement, par (chaine, MAILLON, axe).
            Pas une amplitude, pas une variance : la periode d'une oscillation libre.
  REPERE  : le triedre de l'ANCRE (torse). La trace `PHYSRINGA`/`PHYSRINGAX` publie deja la
            deviation projetee sur ce triedre (`jak-hd-physics.gc:3366-3379`), et c'est le seul
            repere ou les trois axes de SPEC 24 sont separables.
  ABSENT  : une serie plate. Le fit rend alors un residu proche de 1.0 et la ligne se declare
            NON LISIBLE au lieu de rendre une frequence inventee.

CE QUE CET INSTRUMENT FAIT QUE LES DEUX AUTRES NE FONT PAS
===========================================================
  1. IL PUBLIE LES DEUX MAILLONS COTE A COTE. C'est tout l'objet.
  2. IL DECLARE SA PROPRE RESOLUTION ET REFUSE DE CONCLURE QUAND ELLE EST PLUS GROSSE QUE LA
     BANDE. `df` = demi-largeur de l'intervalle des frequences dont le residu reste sous 1.10x le
     minimum (meme convention que ROOM-RINGFIT, donc les deux chiffres se comparent). Si
     `df >= demi-largeur de la bande SPEC 24`, la ligne sort NON CONCLUANT — un instrument plus
     grossier que la bande ne peut pas dire DANS, et l'ecrire quand meme serait un faux vert.
  3. IL LIT LES DEUX FENETRES D'EXCITATION, ET LES CONFRONTE.
       `lacher`    : PHYSRINGA — apres l'arret d'un pilotage SINUSOIDAL A 2.500 Hz
                     (`phys-room.gc:550`, periode 24 frames). Cette frequence est EXACTEMENT la
                     cible AP de SPEC 24 et le centre de ses trois bandes : une frequence propre
                     ajustee sur ce lacher peut etre biaisee VERS le pilotage. Le risque est reel
                     et il n'etait mesure nulle part.
       `impulsion` : PHYSRINGAX/AX2 — demi-cosinus de 10 frames (`phys-room.gc:593-597`), large
                     bande, un axe a la fois. C'est le protocole que SPEC 27 decrit mot pour mot
                     (« after ONE STRONG ISOLATED IMPULSE ») et aucun fitteur ne le lisait.
     UN ECART SYSTEMATIQUE ENTRE LES DEUX FENETRES EST LA MESURE DU BIAIS DE STIMULUS.
  4. IL PUBLIE DEUX ESTIMATEURS (moindres carres sur grille, et croisements de zero). Leur
     desaccord n'est pas un defaut de presentation : c'est un resultat.

USAGE : python3 .autoport/physics_permaillon_fit.py [log]
"""
import math
import os
import re
import sys

import numpy as np

FPS = 60.0
SKIP = 12                    # meme saut de transitoire que ROOM-RINGFIT (physics_room_table.py:4045)
RES_UNREADABLE = 0.08        # meme seuil de lisibilite que ROOM-RINGFIT
CI_FACTOR = 1.10             # meme convention d'intervalle que ROOM-RINGFIT

AXES = ('v', 'ap', 'lat')
# SPEC-breast-softbody.md 24, recopiee sans retouche.
BAND = {'v': (2.10, 2.50), 'ap': (2.30, 2.70), 'lat': (2.40, 2.90)}
NOMINAL = {'v': 2.30, 'ap': 2.50, 'lat': 2.65}
CHAIN_NAME = {0: 'chestL', 1: 'chestR'}

# La prediction ARITHMETIQUE du correctif F (rapport du cycle 30, section 13, tableau F1). Elle
# est la MEME sur les deux maillons — c'est precisement ce que ce cycle vient verifier.
ARITH = {(0, 'v'): 2.3000, (0, 'ap'): 2.4244, (0, 'lat'): 2.5400,
         (1, 'v'): 2.3904, (1, 'ap'): 2.5197, (1, 'lat'): 2.6398}

RE_A = re.compile(r'^PHYSRINGA c=(\d+) f=(\d+) l=(\d+) v=(\S+) ap=(\S+) lat=(\S+)')
RE_AX = re.compile(r'^PHYSRINGAX c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=(\S+)')
RE_AX2 = re.compile(r'^PHYSRINGAX2 c=(\d+) f=(\d+) ax=(\d+) l=(\d+) ap=(\S+) lat=(\S+)')
RE_CX = re.compile(r'^PHYSRINGCX c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=(\S+)')

ZMAX = 0.70          # borne haute de la grille : un fit qui s'y colle n'a pas converge


def load(path):
    """Rend deux dicts de series. `rel[(c,l,axe)]` = fenetre de LACHER ; `imp[(c,l,axe)]` =
    fenetre d'IMPULSION, restreinte a l'axe REELLEMENT excite (ax == axe) : sur les deux autres
    la serie est de la diaphonie, pas un mode propre."""
    rel, imp, rad = {}, {}, {}
    with open(path, errors='ignore') as fh:
        for line in fh:
            if not line.startswith('PHYSRING'):
                continue
            m = RE_A.match(line)
            if m:
                c, f, l = int(m.group(1)), int(m.group(2)), int(m.group(3))
                for i, ax in enumerate(AXES):
                    rel.setdefault((c, l, ax), []).append((f, float(m.group(4 + i))))
                continue
            m = RE_AX.match(line)
            if m:
                c, f, l, ax = (int(m.group(i)) for i in (1, 2, 3, 4))
                if ax == 0:                       # ax 0 = axe vertical excite
                    imp.setdefault((c, l, 'v'), []).append((f, float(m.group(5))))
                continue
            m = RE_AX2.match(line)
            if m:
                c, f, ax, l = (int(m.group(i)) for i in (1, 2, 3, 4))
                if ax == 1:
                    imp.setdefault((c, l, 'ap'), []).append((f, float(m.group(5))))
                elif ax == 2:
                    imp.setdefault((c, l, 'lat'), []).append((f, float(m.group(6))))
                continue
            m = RE_CX.match(line)
            if m:
                c, f, l, ax = (int(m.group(i)) for i in (1, 2, 3, 4))
                rad.setdefault((c, l, ax), []).append((f, float(m.group(5))))
    for d in (rel, imp, rad):
        for k in d:
            d[k] = [v for _f, v in sorted(d[k])]
    return rel, imp, rad


def grid_fit(x):
    """Moindres carres sur grille (f, zeta) d'une sinusoide amortie, plus une constante.
    Rend (fn, zeta, residu, fmin, fmax). Meme grille et meme convention d'intervalle que
    ROOM-RINGFIT, pour que les deux chiffres soient comparables sans conversion."""
    x = np.asarray(x, dtype=float)
    n = len(x)
    if n < 20:
        return None
    t = np.arange(n) / FPS
    var = float(((x - x.mean()) ** 2).sum())
    if var < 1e-18:
        return None
    best, grid = None, []
    for fn in np.arange(1.20, 6.0001, 0.005):
        wn = 2.0 * math.pi * fn
        for z in np.arange(0.10, 0.7001, 0.01):
            wd = wn * math.sqrt(max(1e-9, 1.0 - z * z))
            env = np.exp(-z * wn * t)
            B = np.column_stack([env * np.sin(wd * t), env * np.cos(wd * t), np.ones(n)])
            try:
                coef, *_ = np.linalg.lstsq(B, x, rcond=None)
            except np.linalg.LinAlgError:
                continue
            r = float(((x - B @ coef) ** 2).sum())
            grid.append((fn, r))
            if best is None or r < best[2]:
                best = (fn, z, r)
    if best is None:
        return None
    fn, z, r = best
    res = math.sqrt(r / var)
    rmin = min(g[1] for g in grid)
    inside = [g[0] for g in grid if g[1] <= CI_FACTOR * rmin]
    return fn, z, res, min(inside), max(inside)


def zc_fit(x):
    """Croisements de zero + demi-periodes — le second estimateur. Il ne partage aucune hypothese
    de FORME avec le fit sur grille (ni exponentielle, ni sinusoide) : leur desaccord est donc
    informatif, et c'est pour ca qu'il est publie a cote.

    Le plancher de bruit se juge sur l'EXTREMUM ENTRE deux croisements, jamais sur la valeur AU
    croisement — au croisement le signal vaut zero par definition, et un plancher applique la
    rejette tous. (Defaut trouve et corrige dans ce cycle : la colonne rendait `n/a` partout.)"""
    x = np.asarray(x, dtype=float)
    x = x - x.mean()
    if len(x) < 8:
        return None
    amp = float(np.abs(x).max())
    if amp < 1e-12:
        return None
    floor = 0.05 * amp
    raw = []
    for i in range(1, len(x)):
        a, b = x[i - 1], x[i]
        if a == 0.0 or (a < 0) == (b < 0):
            continue
        raw.append((i - 1) + abs(a) / max(1e-12, abs(a - b)))
    if len(raw) < 3:
        return None
    # ne garder que les croisements separes par une vraie alternance : l'extremum du demi-cycle
    # qui les separe doit depasser le plancher.
    keep = [raw[0]]
    for j in range(1, len(raw)):
        i0, i1 = int(math.ceil(raw[j - 1])), int(math.floor(raw[j])) + 1
        seg = x[max(0, i0):max(i0 + 1, i1)]
        if len(seg) and float(np.abs(seg).max()) >= floor:
            keep.append(raw[j])
    if len(keep) < 4:
        return None
    halves = np.diff(keep)
    hm = float(halves.mean())
    if hm <= 0:
        return None
    fd = FPS / (2.0 * hm)
    sem = float(halves.std(ddof=1) / math.sqrt(len(halves))) if len(halves) > 1 else 0.0
    return fd, fd * sem / hm, len(halves)


def verdict(fn, res, df, ax, zeta=None):
    lo, hi = BAND[ax]
    if zeta is not None and zeta >= ZMAX - 1e-9:
        return 'NON CONVERGE (zeta au bord)'
    if res is None or res > RES_UNREADABLE:
        return 'NON LISIBLE (residu)'
    if df >= 0.5 * (hi - lo):
        return 'NON CONCLUANT (df>=demi-bande)'
    return 'DANS' if lo <= fn <= hi else ('HORS (>)' if fn > hi else 'HORS (<)')


def block(title, ser, why):
    print()
    print("== %s" % title)
    print("   %s" % why)
    print("   %-8s %-4s %-4s %5s %7s %7s %6s %7s %7s   %-28s %s"
          % ('chaine', 'l', 'axe', 'n', 'f(Hz)', 'df(Hz)', 'zeta', 'residu', 'f_zc', 'verdict SPEC 24', 'arith. F'))
    rows = []
    for c in sorted({k[0] for k in ser}):
        for l in sorted({k[1] for k in ser if k[0] == c}):
            for ax in AXES:
                s = ser.get((c, l, ax))
                if not s or len(s) <= SKIP + 20:
                    print("   %-8s %-4d %-4s      -- serie absente ou trop courte (%d)"
                          % (CHAIN_NAME.get(c, c), l, ax, 0 if not s else len(s)))
                    continue
                x = s[SKIP:]
                g = grid_fit(x)
                z = zc_fit(x)
                if g is None:
                    print("   %-8s %-4d %-4s %5d  -- serie plate, aucun mode" % (CHAIN_NAME.get(c, c), l, ax, len(x)))
                    continue
                fn, zeta, res, flo, fhi = g
                df = 0.5 * (fhi - flo)
                v = verdict(fn, res, df, ax, zeta)
                fzc = ('%.3f' % z[0]) if z else 'n/a'
                print("   %-8s %-4d %-4s %5d %7.3f %7.3f %6.2f %7.3f %7s   %-28s %.4f"
                      % (CHAIN_NAME.get(c, c), l, ax, len(x), fn, df, zeta, res, fzc, v, ARITH[(c, ax)]))
                rows.append(dict(c=c, l=l, ax=ax, fn=fn, df=df, zeta=zeta, res=res, v=v,
                                 fzc=(z[0] if z else None)))
    return rows


def _stamp(p):
    import datetime
    return datetime.datetime.fromtimestamp(os.path.getmtime(p)).strftime('%Y-%m-%d %H:%M:%S')


def main():
    path = (sys.argv[1] if len(sys.argv) > 1
            else '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log')
    if not os.path.exists(path):
        raise SystemExit("trace absente : %s" % path)
    rel, imp, rad = load(path)
    print("SPEC 24 PAR MAILLON — trace : %s" % path)
    print("NATURE frequence propre (Hz) + zeta, par (chaine, MAILLON, axe) · REPERE triedre de")
    print("l'ANCRE (torse) · ABSENT serie plate -> la ligne se declare NON LISIBLE")
    print("bandes SPEC 24 : v [2.10,2.50] · ap [2.30,2.70] · lat [2.40,2.90]   (nominal %s)"
          % ", ".join("%s %.2f" % (a, NOMINAL[a]) for a in AXES))
    print("`df` = demi-intervalle des frequences dont le residu reste sous %.2fx le minimum —" % CI_FACTOR)
    print("       C'EST LA RESOLUTION DE L'INSTRUMENT. df >= demi-largeur de bande -> NON CONCLUANT.")

    r1 = block("FENETRE DE LACHER (PHYSRINGA) — apres un pilotage SINUSOIDAL A 2.500 Hz", rel,
               "phys-room.gc:550 : periode 24 frames = 2.500 Hz, soit EXACTEMENT la cible AP de "
               "SPEC 24\n   et le centre de ses trois bandes. Un biais vers 2.5 Hz est possible ici, "
               "et c'est\n   la raison d'etre du bloc suivant.")
    r2 = block("FENETRE D'IMPULSION (PHYSRINGAX/AX2) — demi-cosinus 10 frames, LARGE BANDE", imp,
               "phys-room.gc:593-597, le protocole que SPEC 27 decrit (« one strong isolated "
               "impulse »).\n   Aucun fitteur du depot ne lisait ces tags. Un axe a la fois : seule "
               "la serie dont\n   l'axe MESURE est l'axe EXCITE est retenue, les autres sont de la "
               "diaphonie.")

    # --- VALIDATION CROISEE : MES LIGNES l=0 DOIVENT REPRODUIRE ROOM-RINGFIT AU CHIFFRE PRES ----
    # C'est ce qui rend les lignes l=1 credibles. `ROOM-RINGFIT` ne lit QUE le maillon 0
    # (physics_room_table.py:4106) : si mon ajustement rend les MEMES six nombres sur ces six
    # canaux, alors ce n'est pas un estimateur neuf avec des biais neufs — c'est le MEME
    # estimateur, applique a la moitie de la donnee qui etait jetee. Sinon, c'est MOI qui derive,
    # et les lignes l=1 ne valent rien tant que l'ecart n'est pas explique.
    # argv[2] permet de designer un AUTRE tableau — c'est ce qui rend le controle positif de la
    # garde d'appariement possible (pointer le tableau d'une autre course DOIT rendre REFUSE).
    tbl = (sys.argv[2] if len(sys.argv) > 2
           else os.path.join(os.path.dirname(path), 'keira-room-table.txt'))
    print()
    print("== VALIDATION CROISEE — MES LIGNES l=0 CONTRE `ROOM-RINGFIT` (qui ne lit QUE l=0)")
    # GARDE DE PROVENANCE — ET ELLE NE PEUT PAS ETRE UN HORODATAGE.
    # Le tableau est derive d'UNE course precise ; le comparer a une AUTRE course rend un
    # « DIVERGE » qui n'accuse pas l'instrument mais l'appariement. Je m'y suis pris les pieds dans
    # ce cycle meme, en lancant la sonde sur une course d'ablation pendant que le tableau venait
    # encore de la reference.
    # PREMIERE VERSION DE CETTE GARDE : comparer les dates. ELLE ETAIT FAUSSE, et c'est le piege
    # « un chemin n'est pas un horodatage » du registre, dans sa version miroir — une trace RESTAUREE
    # par copie porte la date de la copie, donc la garde refusait l'appariement CORRECT.
    # CE QUI IDENTIFIE UNE COURSE EST SON CONTENU. Le tableau, lui, ne cite sa source que par
    # CHEMIN (sa ligne 3 : « depuis .../keira-room-x86.log »), et ce chemin est le meme a toutes les
    # courses : il n'identifie rien. La sonde ne peut donc pas VERIFIER l'appariement ; elle le
    # DECLARE non verifiable et publie l'empreinte de la trace qu'elle a lue, pour que la
    # comparaison soit refaisable. Le vrai correctif est en amont : que le tableau grave l'empreinte
    # de sa trace au point de production. C'est signale au rapport, pas bricole ici.
    import hashlib
    _h = hashlib.md5(open(path, 'rb').read()).hexdigest() if os.path.exists(path) else 'n/a'
    print("   trace lue : %s" % path)
    print("   empreinte : md5 %s" % _h)
    # DEPUIS LE CYCLE 32 LE TABLEAU GRAVE L'EMPREINTE DE SA TRACE (physics_room_table.py:1829).
    # L'appariement devient donc VERIFIABLE, et cette sonde le verifie au lieu de le declarer
    # impossible. Sur un tableau plus ancien la ligne est absente : on retombe sur l'ancien
    # avertissement, ecrit tel quel.
    _tbl_md5 = None
    if os.path.exists(tbl):
        for _ln in open(tbl, errors='ignore'):
            _m = re.match(r'^empreinte de la trace lue : md5 ([0-9a-f]{32})', _ln)
            if _m:
                _tbl_md5 = _m.group(1)
                break
    if _tbl_md5 is None:
        print("   APPARIEMENT NON VERIFIABLE : ce tableau ne grave pas l'empreinte de sa trace (il est")
        print("   anterieur au cycle 32) et ne cite sa source que par CHEMIN, identique a toutes les")
        print("   courses. Un `DIVERGE` ci-dessous veut donc dire `l'instrument derive OU le tableau")
        print("   vient d'une autre course` — les deux se lisent pareil.")
    elif _tbl_md5 == _h:
        print("   APPARIEMENT VERIFIE : le tableau declare la MEME trace (md5 %s)." % _tbl_md5)
        print("   Un `DIVERGE` ci-dessous ne peut donc plus etre un defaut d'appariement.")
    else:
        print("   APPARIEMENT REFUSE : le tableau a ete genere depuis une AUTRE course")
        print("   (tableau md5 %s, ma trace md5 %s)." % (_tbl_md5, _h))
        print("   La comparaison ci-dessous ne vaut RIEN — regenere le tableau depuis cette trace.")
    if not os.path.exists(tbl):
        print("   tableau absent (%s) : validation non faite, et je le declare." % tbl)
    else:
        ref = {}
        rr = re.compile(r'^ROOM-RINGFIT: repos\s+(\S+)\s+(\S+)\s+\d+\s+([0-9.]+)')
        for line in open(tbl, errors='ignore'):
            m = rr.match(line)
            if m:
                ref[(m.group(1), m.group(2))] = float(m.group(3))
        d1 = {(r['c'], r['l'], r['ax']): r for r in r1}
        nok = ntot = 0
        for (c, l, ax), r in sorted(d1.items()):
            if l != 0:
                continue
            k = (CHAIN_NAME.get(c, c), ax)
            if k not in ref:
                continue
            ntot += 1
            same = abs(ref[k] - r['fn']) < 1e-9
            nok += 1 if same else 0
            print("   %-8s %-4s   ROOM-RINGFIT %7.3f   moi %7.3f   ecart %+.4f   %s"
                  % (k[0], ax, ref[k], r['fn'], r['fn'] - ref[k],
                     'IDENTIQUE' if same else 'DIVERGE'))
        if ntot:
            print("   -> %d canaux sur %d reproduits au chiffre pres." % (nok, ntot))
            if nok == ntot:
                print("      L'estimateur est donc le meme ; la seule chose que ce cycle ajoute est")
                print("      la MOITIE DE LA DONNEE QUE LES DEUX LECTEURS EXISTANTS JETAIENT.")

    # --- LE CANAL RADIAL : CELUI QUE LE TABLEAU DESIGNE COMME SOURCE DU VERDICT VERTICAL -------
    # `physics_room_table.py:4026-4039` corrige explicitement l'instrument : la colonne `v` de
    # PHYSRINGA/AX mesure la FUITE des modes tangentiels et non le mode vertical, parce que `u` et
    # `m` sont unitaires (la composante radiale est nulle PAR CONSTRUCTION) et que l'os est
    # vertical a 84.5 %. Le verdict SPEC 24-v doit donc se lire sur le canal RADIAL, `PHYSRINGCX`.
    # AVANT d'en tirer une frequence par maillon, on verifie qu'il EN PORTE une : une grandeur
    # etiquetee `l=` qui ne depend pas de `l` ne peut pas rendre un verdict par maillon.
    print()
    print("== CANAL RADIAL (PHYSRINGCX) — LE VERDICT VERTICAL DE SPEC 24 DEVRAIT SE LIRE ICI")
    print("   CONTROLE PREALABLE, ET IL EST ELIMINATOIRE : la serie du maillon 0 et celle du")
    print("   maillon 1 sont-elles DIFFERENTES ? Une trace qui imprime `l=` sur une grandeur qui")
    print("   ne depend pas de `l` donne l'apparence d'une mesure par maillon sans en etre une.")
    deg = ok = 0
    for c in sorted({k[0] for k in rad}):
        for ax in sorted({k[2] for k in rad if k[0] == c}):
            a, b = rad.get((c, 0, ax)), rad.get((c, 1, ax))
            if not a or not b:
                continue
            n = min(len(a), len(b))
            dmax = max(abs(x - y) for x, y in zip(a[:n], b[:n]))
            same = dmax == 0.0
            # DEUX FACONS DE N'AVOIR AUCUNE INFORMATION PAR MAILLON, ET IL FAUT LES DEUX CONTROLES.
            # (a) les deux series sont IDENTIQUES -> l'index est decoratif.
            # (b) une des deux est IDENTIQUEMENT NULLE -> elles « different » bien, mais le maillon
            #     mort n'a rien a mesurer. Un controle qui ne teste que (a) passe au VERT sur (b),
            #     et c'est exactement ce qui vient d'arriver a cette sonde : apres le correctif
            #     d'instrument du cycle 31 elle imprimait « differentes » sur six canaux dont le
            #     maillon distal etait a zero sur 150 echantillons.
            nz0 = sum(1 for x in a[:n] if x != 0.0)
            nz1 = sum(1 for x in b[:n] if x != 0.0)
            dead = (nz0 == 0) or (nz1 == 0)
            deg += 1 if (same or dead) else 0
            ok += 1
            if same:
                verd = 'IDENTIQUES -> AUCUNE information par maillon'
            elif dead:
                verd = ('MAILLON MORT : l=%d identiquement nul sur %d echantillons -> le canal '
                        'n\'existe pas sur ce maillon' % (0 if nz0 == 0 else 1, n))
            else:
                verd = 'differentes ET les deux vivantes'
            print("   %-8s ax=%d  n=%3d   max|l0-l1| = %-10.6g  non-nuls l0=%3d l1=%3d   %s"
                  % (CHAIN_NAME.get(c, c), ax, n, dmax, nz0, nz1, verd))
    if ok and deg == ok:
        print("   -> AUCUNE des %d combinaisons ne porte d'information exploitable par maillon." % ok)
        print("      Le canal que le tableau designe comme SEULE source valide du verdict SPEC 24-v")
        print("      ne permet donc PAS de verdict vertical par maillon, et cette sonde n'en publie")
        print("      pas. Si le motif est `MAILLON MORT`, ce n'est meme pas un emetteur qui manque :")
        print("      c'est le DEGRE DE LIBERTE qui n'est arme que sur un maillon")
        print("      (`jak-hd-physics.gc:2829`, `(= l rlk)`). Un emetteur ne peut pas publier une")
        print("      grandeur que le solveur ne calcule pas.")

    # --- LE FIT DU CANAL RADIAL, PAR MAILLON — SPEC 24 VERTICALE ------------------------------
    # Il ne s'ecrit QUE si le controle ci-dessus a montre les deux maillons VIVANTS. Ajuster une
    # serie identiquement nulle rend un residu et une frequence parfaitement formates : c'est ainsi
    # qu'un maillon mort se publie comme une conformite.
    # BANDE : celle de l'axe VERTICAL [2.10, 2.50] quelle que soit la fenetre d'excitation, comme
    # `ROOM-AXFIT-RAD` (physics_room_table.py:4493-4520) — le canal radial EST le mode vertical
    # (l'os de poitrine est vertical a 84.5 %), la fenetre ne fait que l'exciter.
    print()
    print("== FIT DU CANAL RADIAL PAR MAILLON — LE VERDICT VERTICAL DE SPEC 24")
    print("   ESTIMATEUR : le meme `grid_fit` que les deux blocs ci-dessus (meme skip=%d, meme"
          % SKIP)
    print("   grille, meme intervalle a %.2fx le residu minimum). BANDE : [%.2f, %.2f] (verticale),"
          % (CI_FACTOR, BAND['v'][0], BAND['v'][1]))
    print("   cible %.2f. `ax` designe la FENETRE d'excitation, pas une projection : cette serie"
          % NOMINAL['v'])
    print("   n'a qu'une composante, l'elongation radiale du tissu.")
    _AXW = {0: 'v', 1: 'ap', 2: 'lat'}
    print("   %-8s %-4s %-6s %5s %7s %7s %6s %7s   %s"
          % ('chaine', 'l', 'fenetre', 'n', 'f(Hz)', 'df(Hz)', 'zeta', 'residu', 'verdict SPEC 24-v'))
    radrows = []
    for c in sorted({k[0] for k in rad}):
        for ax in sorted({k[2] for k in rad if k[0] == c}):
            for l in sorted({k[1] for k in rad if k[0] == c and k[2] == ax}):
                sr = rad.get((c, l, ax))
                nzs = 0 if not sr else sum(1 for x in sr if x != 0.0)
                if not sr or len(sr) <= SKIP + 20 or nzs == 0:
                    print("   %-8s %-4d %-6s %5s   -- %s"
                          % (CHAIN_NAME.get(c, c), l, _AXW.get(ax, ax),
                             0 if not sr else len(sr),
                             'serie absente ou trop courte' if not sr or len(sr) <= SKIP + 20
                             else 'serie IDENTIQUEMENT NULLE : le degre de liberte n\'est pas arme '
                                  'sur ce maillon, aucun fit ne se publie'))
                    continue
                x = sr[SKIP:]
                g = grid_fit(x)
                if g is None:
                    print("   %-8s %-4d %-6s %5d   -- serie plate, aucun mode"
                          % (CHAIN_NAME.get(c, c), l, _AXW.get(ax, ax), len(x)))
                    continue
                fn, zeta, res, flo, fhi = g
                df = 0.5 * (fhi - flo)
                v = verdict(fn, res, df, 'v', zeta)
                print("   %-8s %-4d %-6s %5d %7.3f %7.3f %6.2f %7.3f   %s"
                      % (CHAIN_NAME.get(c, c), l, _AXW.get(ax, ax), len(x), fn, df, zeta, res, v))
                radrows.append(dict(c=c, l=l, ax=_AXW.get(ax, ax), fn=fn, df=df, zeta=zeta,
                                    res=res, v=v))
    # LE DELTA RACINE/DISTAL, EXPLICITEMENT — c'est la prediction I3 du cycle 32, et elle ne doit
    # pas se lire en soustrayant deux lignes a la main.
    _d = {(r['c'], r['ax'], r['l']): r for r in radrows}
    if _d:
        print("   -- ecart racine/distal (prediction I3 du cycle 32 : <= 0.20 Hz) --")
        for c in sorted({k[0] for k in _d}):
            for axn in ('v', 'ap', 'lat'):
                a, b = _d.get((c, axn, 0)), _d.get((c, axn, 1))
                if not a or not b:
                    continue
                print("   %-8s fenetre=%-4s  l0=%.3f  l1=%.3f  |ecart|=%.3f Hz  %s"
                      % (CHAIN_NAME.get(c, c), axn, a['fn'], b['fn'], abs(a['fn'] - b['fn']),
                         'DANS I3' if abs(a['fn'] - b['fn']) <= 0.20 else 'HORS I3'))

    # --- LA CONFRONTATION DES DEUX FENETRES : c'est elle qui mesure le biais de stimulus --------
    print()
    print("== BIAIS DE STIMULUS — LES DEUX FENETRES SUR LES MEMES CANAUX")
    print("   Si le lacher a 2.500 Hz tire la mesure vers lui, l'ecart `lacher - impulsion` est")
    print("   SYSTEMATIQUEMENT dirige vers 2.500 Hz. ABSENT : un ecart de signe aleatoire.")
    print("   %-8s %-4s %-4s %9s %9s %9s  %s" % ('chaine', 'l', 'axe', 'lacher', 'impulsion', 'ecart', 'vers 2.500 ?'))
    d1 = {(r['c'], r['l'], r['ax']): r for r in r1}
    d2 = {(r['c'], r['l'], r['ax']): r for r in r2}
    toward = same = 0
    for k in sorted(set(d1) & set(d2)):
        a, b = d1[k]['fn'], d2[k]['fn']
        # le lacher est-il plus proche de 2.500 que l'impulsion ne l'est ?
        t = abs(a - 2.500) < abs(b - 2.500)
        toward += 1 if t else 0
        same += 1
        print("   %-8s %-4d %-4s %9.3f %9.3f %+9.3f  %s"
              % (CHAIN_NAME.get(k[0], k[0]), k[1], k[2], a, b, a - b, 'oui' if t else 'non'))
    if same:
        print("   -> le lacher est plus proche de 2.500 Hz que l'impulsion sur %d canaux sur %d."
              % (toward, same))
        print("      Un biais de stimulus predit ~%d/%d ; l'absence de biais en predit ~%d/%d."
              % (same, same, same // 2, same))
    return 0


if __name__ == '__main__':
    sys.exit(main())
