#!/usr/bin/env python3
"""CYCLE 141 — VERIFICATION DES DEUX LOTS, CONTRE LES PREDICTIONS ECRITES AVANT LA COURSE.

DIRECTIVES vd9e8b66782

    usage: c141_verify.py <trace-reference> <trace-neuve>

LOT A — le `+Z` de §7 remis dans le sens que la section ecrit (passe APPARIEE).
  La prediction A1 est une IDENTITE AU BIT : la trace neuve doit reproduire la reference sur TOUT
  type d'enregistrement, sauf une liste ENUMEREE A L'AVANCE. Ce script ne cherche pas a confirmer
  A1 ; il cherche a la REFUTER, en listant tout type qui differe et qui n'est pas dans la liste.

LOT B — l'echelon de lacet statique (PH-YAW), 3e clause de §7.
  NATURE des grandeurs comparees : `PHYSMEAN` est une position MOYENNE de pointe sur la fenetre
  (un deplacement SOUTENU, pas une variance) ; `PHYSPOSETAG` est une direction unitaire.
  REPERES : `PHYSMEAN` est dans la base de l'ANCRE (invariance attendue), `PHYSPOSETAG` dans le
  MONDE (il DOIT bouger — c'est le controle de discrimination).
  Le verdict est un RAPPORT a la cellule de controle positif, jamais un seuil absolu.
"""
import re
import sys
import math

# LES SEULES DIFFERENCES ADMISES PAR LA PREDICTION B8, ECRITES AVANT LA COURSE.
# Toute autre difference REFUTE, et le script la publie telle quelle.
EXCEPTIONS_ATTENDUES = {
    'PHYSTRI':                 'lot A — `a=2` doit etre EXACTEMENT negue (A2), `a=0` intact (A3)',
    'PHYSROOM-PHASEGUARD':     'lot B — renumerotation report=43 done=44 (B1)',
    'PHYSROOM-PHASEVISITED':   'lot B — maxvisited 41 -> 42 (B2)',
    'PHYSNOPLAY':              'lot B — compteurs accumules par frame, PH-YAW en ajoute 1020 (B8d)',
}
# Types NES de ce cycle : ils n'existent pas dans la reference, donc « different » n'a pas de sens.
TYPES_NEUFS = {'PHYSYAWC', 'PHYSYAWR'}


def charge(path):
    """Groupe les enregistrements par TAG, en gardant l'ORDRE et TOUTES les lignes.

    Indexer par cle dans un dict ne garderait que la DERNIERE ligne de chaque cle — le defaut que
    le cycle 140 a trouve dans son propre outil, ou 101 fenetres etaient declarees « inchangees »
    parce que seule leur derniere ligne l'etait. On compare des LISTES COMPLETES.
    """
    par_tag = {}
    with open(path, errors='ignore') as fh:
        for ln in fh:
            ln = ln.rstrip('\n')
            m = re.match(r'^(?:\[HD-PHYS\] )?(PHYS[A-Z0-9-]*)\b', ln)
            if not m:
                continue
            par_tag.setdefault(m.group(1), []).append(ln)
    return par_tag


def preconditions(ref, neuf, out):
    """LES CONDITIONS INITIALES, AVANT TOUT VERDICT D'IDENTITE.

    `room-run-not-frame-reproducible` : la salle n'est deterministe QU'A ETAT DE DEPART PARTAGE.
    Sept courses sur huit attrapent la cible en `target-title` et font spawner le sujet a
    1061328.6250 u de l'origine ; la huitieme l'attrape en `target-title-wait` et spawne a
    1230225.1250, ce qui fait diverger 79 % de la trace QUEL QUE SOIT le lot teste. Sans ce
    controle, une divergence de spawn se lirait comme « l'audit de `*phys-fz*` est incomplet ».
    """
    def spawn(par_tag):
        for ln in par_tag.get('PHYSPOSED', []):
            m = re.search(r'dist-from-origin=([-\d.e+]+)', ln)
            if m:
                return float(m.group(1))
        return None

    def cible(par_tag):
        for ln in par_tag.get('PHYSROOM-START', []):
            m = re.search(r':state (\S+)', ln)
            if m:
                return m.group(1)
        return None

    sa, sb, ca, cb = spawn(ref), spawn(neuf), cible(ref), cible(neuf)
    out('PRECONDITION  conditions initiales : reference spawn=%s cible=%s | neuve spawn=%s cible=%s'
        % (sa, ca, sb, cb))
    ok = (sa is not None and sa == sb)
    out('PRECONDITION  %s' % ('PARTAGEES — la comparaison au bit a un sens' if ok else
                             '*** DIFFERENTES *** — toute divergence en aval est INATTRIBUABLE,'
                             ' A1 n\'est PAS testable sur cette paire'))
    out('')
    return ok


def lot_a(ref, neuf, out):
    out('=' * 94)
    out('LOT A — §7 l.130 : LE `+Z` DU TRIEDRE, PASSE APPARIEE. PREDICTION = IDENTITE AU BIT.')
    out('=' * 94)

    tags = sorted(set(ref) | set(neuf))
    differents, absents, ajoutes = [], [], []
    for t in tags:
        a, b = ref.get(t), neuf.get(t)
        if a is None:
            ajoutes.append(t)
        elif b is None:
            absents.append(t)
        elif a != b:
            differents.append(t)

    inattendus = [t for t in differents if t not in EXCEPTIONS_ATTENDUES]
    out('A1  types d\'enregistrement : %d dans la reference, %d dans la course neuve'
        % (len(ref), len(neuf)))
    out('A1  IDENTIQUES AU BIT : %d types sur %d' % (len(tags) - len(differents)
                                                     - len(absents) - len(ajoutes), len(tags)))
    for t in differents:
        na, nb = len(ref[t]), len(neuf[t])
        d = sum(1 for x, y in zip(ref[t], neuf[t]) if x != y)
        out('A1    DIFFERE  %-24s lignes %d -> %d, %d lignes appariees differentes   [%s]'
            % (t, na, nb, d, EXCEPTIONS_ATTENDUES.get(t, '*** NON PREDIT ***')))
    for t in ajoutes:
        out('A1    NEUF     %-24s %d lignes%s'
            % (t, len(neuf[t]), '' if t in TYPES_NEUFS else '   *** NON PREDIT ***'))
    for t in absents:
        out('A1    DISPARU  %-24s *** NON PREDIT ***' % t)

    verdict_a1 = (not inattendus
                  and not absents
                  and all(t in TYPES_NEUFS for t in ajoutes))
    out('A1  VERDICT : %s' % ('TENUE — aucune difference hors de la liste ecrite avant la course'
                              if verdict_a1 else
                              'REFUTEE — l\'audit des consommateurs de `*phys-fz*` est incomplet'))

    # ---- A2 / A3 : le triedre, composante par composante -------------------------------------
    def tri(lignes):
        d = {}
        for ln in lignes:
            m = re.match(r'^PHYSTRI c=(\d+) a=(\d+) x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)', ln)
            if m:
                d[(int(m.group(1)), int(m.group(2)))] = tuple(float(m.group(i)) for i in (3, 4, 5))
        return d

    ta, tb = tri(ref.get('PHYSTRI', [])), tri(neuf.get('PHYSTRI', []))
    out('')
    for (c, a) in sorted(set(ta) & set(tb)):
        va, vb = ta[(c, a)], tb[(c, a)]
        neg = all(abs(x + y) <= 1e-9 for x, y in zip(va, vb))
        ident = va == vb
        etiq = {0: 'a=0 lateral sortant `fx`', 1: 'a=1 vertical `fy`', 2: 'a=2 avant/arriere `fz`'}[a]
        att = 'NEGUE' if a == 2 else 'IDENTIQUE'
        got = 'NEGUE' if neg else ('IDENTIQUE' if ident else 'AUTRE')
        out('A2/A3  c=%d %-26s  ref=(%+.5f %+.5f %+.5f)  neuf=(%+.5f %+.5f %+.5f)  attendu %-9s -> %s  %s'
            % (c, etiq, va[0], va[1], va[2], vb[0], vb[1], vb[2], att, got,
               'OK' if att == got else '*** REFUTEE ***'))
    return verdict_a1


def lot_b(neuf, out):
    out('')
    out('=' * 94)
    out('LOT B — ECHELON DE LACET STATIQUE (PH-YAW), 3e CLAUSE DE §7')
    out('=' * 94)

    # ---- B1 / B2 : la phase existe et a ete VISITEE -------------------------------------------
    for t in ('PHYSROOM-PHASEGUARD', 'PHYSROOM-PHASEVISITED'):
        for ln in neuf.get(t, []):
            out('B1/B2  %s' % ln)

    # ---- B3 : les cellules ---------------------------------------------------------------------
    cells = {}
    for ln in neuf.get('PHYSYAWC', []):
        m = re.match(r'^PHYSYAWC i=(\d+) ax=(\d+) deg=([-\d.e+]+)', ln)
        if m:
            cells[int(m.group(1))] = (int(m.group(2)), float(m.group(3)))
    out('')
    out('B3  cellules jouees : %d' % len(cells))
    for i in sorted(cells):
        ax, dg = cells[i]
        out('B3    i=%d  axe=%s  angle=%+7.2f deg' % (i, 'MONDE Y (lacet)' if ax == 1 else
                                                      'MONDE X (controle positif)', dg))
    if len(cells) != 5:
        out('B3  *** REFUTEE *** : 5 cellules attendues')

    # ---- B4 : LA GARDE ANTI-MIROIR, ELLE PASSE AVANT TOUTE LECTURE -----------------------------
    out('')
    out('B4  GARDE ANTI-MIROIR — le rebase de §37 est arme a 20 deg/frame. S\'il tire, l\'invariance')
    out('B4  est vraie PAR CONSTRUCTION et aucun verdict de §7 n\'est recevable.')
    reb, garde_ok = [], True
    for ln in neuf.get('PHYSYAWR', []):
        m = re.match(r'^PHYSYAWR i=(\d+) c=(\d+) nrb=([-\d.e+]+) omc=([-\d.e+]+)'
                     r' nrot=([-\d.e+]+) nfr=([-\d.e+]+)', ln)
        if m:
            i, c = int(m.group(1)), int(m.group(2))
            nrb, omc, nrot, nfr = (float(m.group(k)) for k in (3, 4, 5, 6))
            reb.append((i, c, nrb, omc, nrot, nfr))
            if nrb > 0 or nrot > 0 or nfr <= 0:
                garde_ok = False
    for (i, c, nrb, omc, nrot, nfr) in reb:
        out('B4    i=%d c=%d  rebases=%.0f  omc_max=%.6f  franchies=%.0f / evaluees=%.0f  %s'
            % (i, c, nrb, omc, nrot, nfr,
               'OK' if (nrb == 0 and nrot == 0 and nfr > 0) else '*** LE REBASE A TIRE ***'))
    out('B4  VERDICT : %s' % ('TENUE — aucun rebase, l\'invariance ne peut pas venir de la'
                              if garde_ok else
                              'REFUTEE — le verdict de §7 est SUSPENDU ce cycle'))

    # ---- B5 / B7 : la mesure, en repere ANCRE --------------------------------------------------
    mean = {}
    for ln in neuf.get('PHYSMEAN', []):
        m = re.match(r'^PHYSMEAN tag=(\S+) c=(\d+) x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)', ln)
        if m:
            mean[(m.group(1), int(m.group(2)))] = tuple(float(m.group(i)) for i in (3, 4, 5))

    def d(t1, t2, c):
        if (t1, c) not in mean or (t2, c) not in mean:
            return None
        return math.dist(mean[(t1, c)], mean[(t2, c)])

    out('')
    out('B5/B7  `PHYSMEAN` — position MOYENNE de la pointe sur la fenetre, REPERE DE L\'ANCRE.')
    out('B5/B7  NATURE : un deplacement SOUTENU (pas une variance, pas un max).')
    verdict_b5 = None
    for c in sorted({k[1] for k in mean}):
        if ('yaw0', c) not in mean:
            continue
        ctl = d('yaw0', 'yawtiltctl', c)
        ecarts = [(t, d('yaw0', t, c)) for t in ('yaw90', 'yaw180', 'yawm90')]
        ecarts = [(t, v) for t, v in ecarts if v is not None]
        if not ecarts or ctl is None:
            out('B5/B7  c=%d : cellules manquantes, pas de verdict' % c)
            continue
        pire = max(v for _, v in ecarts)
        out('B5/B7  c=%d  yaw0 = (%+.5f %+.5f %+.5f)' % ((c,) + mean[('yaw0', c)]))
        for t, v in ecarts:
            out('B5     c=%d  %-11s ecart au lacet 0 = %.6f u   (%+.5f %+.5f %+.5f)'
                % ((c, t, v) + mean[(t, c)]))
        out('B7     c=%d  %-11s ecart au lacet 0 = %.6f u   <- CONTROLE POSITIF, il doit TIRER'
            % (c, 'yawtiltctl', ctl))
        if ctl <= 0.0:
            out('B5/B7  c=%d  *** CONTROLE MORT *** : la cellule de controle ne bouge pas, donc'
                ' l\'instrument ne discrimine rien et B5 est SANS VALEUR.' % c)
            verdict_b5 = False
            continue
        r = pire / ctl
        ok = r <= 0.10
        out('B5     c=%d  RAPPORT pire_lacet / controle = %.6f  (critere ecrit avant la course :'
            ' <= 0.10)  -> %s' % (c, r, 'INVARIANT' if ok else 'NON INVARIANT'))
        verdict_b5 = ok if verdict_b5 is None else (verdict_b5 and ok)

    # ---- B6 : le controle de DISCRIMINATION, en repere MONDE ------------------------------------
    pose = {}
    for ln in neuf.get('PHYSPOSETAG', []):
        m = re.match(r'^PHYSPOSETAG tag=(\S+) c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+)'
                     r' uz=([-\d.e+]+)', ln)
        if m:
            pose[(m.group(1), int(m.group(2)), int(m.group(3)))] = tuple(
                float(m.group(i)) for i in (4, 5, 6))
    out('')
    out('B6  `PHYSPOSETAG` — direction d\'os, REPERE MONDE. C\'EST LE CONTROLE DE DISCRIMINATION :')
    out('B6  sans lui, « la lecture d\'ancre n\'a pas bouge » et « le lacet n\'a pas eu lieu » sont')
    out('B6  le meme zero.')
    b6_ok = True
    for (c, l) in sorted({(k[1], k[2]) for k in pose}):
        base = pose.get(('yaw0', c, l))
        if not base:
            continue
        for t, att in (('yaw90', 90.0), ('yaw180', 180.0), ('yawm90', 90.0)):
            v = pose.get((t, c, l))
            if not v:
                continue
            dot = max(-1.0, min(1.0, sum(a * b for a, b in zip(base, v))))
            ang = math.degrees(math.acos(dot))
            marque = 'OK' if ang >= 20.0 else '*** LE MONDE N\'A PAS BOUGE ***'
            if ang < 20.0:
                b6_ok = False
            out('B6    c=%d l=%d  %-8s angle(monde) au lacet 0 = %7.3f deg   (commande %.0f)  %s'
                % (c, l, t, ang, att, marque))
    out('B6  VERDICT : %s' % ('TENUE — le lacet a bien eu lieu dans le monde'
                              if b6_ok else 'REFUTEE — B5 ne mesure rien'))

    out('')
    out('=' * 94)
    if not garde_ok or not b6_ok:
        out('§7 3e CLAUSE : AUCUN VERDICT. La garde anti-miroir ou le controle de discrimination')
        out('               a echoue — « on ne peut pas juger » n\'est pas « c\'est bon ».')
    elif verdict_b5 is True:
        out('§7 3e CLAUSE : TENUE. La reponse etablie est invariante par lacet pur dans le repere')
        out('               de l\'ancre, pendant que la meme pose bouge franchement dans le monde,')
        out('               et sans qu\'aucun rebase ait tire.')
    elif verdict_b5 is False:
        out('§7 3e CLAUSE : NON TENUE. La reponse etablie DEPEND de l\'orientation du sujet dans le')
        out('               monde a gravite locale identique.')
    else:
        out('§7 3e CLAUSE : AUCUN VERDICT (donnees manquantes).')
    out('=' * 94)
    return garde_ok, b6_ok, verdict_b5


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    lignes = []
    out = lignes.append
    ref, neuf = charge(sys.argv[1]), charge(sys.argv[2])
    out('reference : %s' % sys.argv[1])
    out('neuve     : %s' % sys.argv[2])
    out('')
    preconditions(ref, neuf, out)
    lot_a(ref, neuf, out)
    lot_b(neuf, out)
    print('\n'.join(lignes))
    return 0


if __name__ == '__main__':
    sys.exit(main())
