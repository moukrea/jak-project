#!/usr/bin/env python3
"""c96_axc_pair.py — SPEC 24/25/26/27 : LES TROIS IMPULSIONS, CONTAMINEE contre PROPRE.

Phase Grecharged-secondary-motion, branche physics-keira-clean. Cycle 96 (2026-08-22).

CE QUE CE FICHIER TRANCHE
-------------------------
`physroom-drive-imp` TIENT le sujet a `home + 365 u` jusqu'a la fin de sa fenetre, et la fenetre
suivante repart a `home + 8.93 u` : entre deux fenetres AX l'ancre saute de **365 unites en UNE
frame** le long de l'axe de la fenetre PRECEDENTE. Le rebase de translation de sa §37 ne l'absorbe
pas (seuil 7*B0 = 4214 u, `jak-hd-physics.gc:2712`). Cinq des six fenetres AX/AXZ sont donc
excitees deux fois ; seule AXV, qui entre depuis PH-BACK, est propre.

PH-AXC rejoue les MEMES trois impulsions avec un retour en demi-cosinus et 60 frames de calme.
Ce script fait passer LES DEUX JEUX DANS LE MEME CODE, et publie la paire.

NATURE / REPERE / LIGNE DE BASE (SPEC 7, pour chaque grandeur publiee)
  C96-PRE    NATURE  une LONGUEUR (unites de jeu, 4096 u = 1 m) : le residu de la chaine a la
                     premiere frame de la fenetre, avant que l'impulsion ait agi.
             REPERE  le triedre de l'ancre (v, ap, lat).
             LIGNE DE BASE  0 = la chaine est exactement sur la pose d'auteur. C'est la grandeur
                     dont l'ABSENCE de publication est tout le defaut : une fenetre qui commence
                     a 60 % de son amplitude de reponse ne mesure pas une impulsion isolee.
  C96-AMP    NATURE  une LONGUEUR : |dev| a f=1 et son maximum de fenetre.
             REPERE  idem.  LIGNE DE BASE  0 hors reponse.
  C96-DIR    NATURE  une DIRECTION unitaire (1er vecteur propre de la covariance de la serie) et
                     des ANGLES en degres.  REPERE  idem.
             CE QUI DISCRIMINE  l'angle ENTRE les reponses des trois axes : sa §24 demande trois
                     frequences par direction, donc trois directions separables. 10 deg entre deux
                     d'entre elles = une seule direction, quelle que soit la frequence lue.
  C96-FREQ   NATURE  une FREQUENCE en Hz.  DEUX estimateurs independants (passages par zero et
                     pic d'autocorrelation) sont publies COTE A COTE : s'ils divergent, c'est la
                     mesure, pas une moyenne a faire.
  C96-CTRL   le TEMOIN NEGATIF : `ax=0` etait deja propre dans les deux jeux. Les deux fenetres
                     doivent donc coincider. Si elles ne coincident pas, l'entree n'explique pas
                     l'ecart des deux autres et ce cycle tombe — c'est dit, pas contourne.
"""
import re, sys, math
import numpy as np

NAMES = {0: 'chestL', 1: 'chestR'}
AXN   = {0: 'v', 1: 'ap', 2: 'lat'}


def load(txt, t1, t2):
    S = {}
    for m in re.finditer(r'^%s c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+)' % t1, txt, re.M):
        S.setdefault((int(m.group(1)), int(m.group(3)), int(m.group(4))), {}) \
         .setdefault(int(m.group(2)), [0.0, 0.0, 0.0])[0] = float(m.group(5))
    for m in re.finditer(r'^%s c=(\d+) f=(\d+) ax=(\d+) l=(\d+) ap=([-\d.e+]+) lat=([-\d.e+]+)'
                         % t2, txt, re.M):
        d = S.setdefault((int(m.group(1)), int(m.group(4)), int(m.group(3))), {}) \
             .setdefault(int(m.group(2)), [0.0, 0.0, 0.0])
        d[1] = float(m.group(5)); d[2] = float(m.group(6))
    return {k: np.array([v[f] for f in sorted(v)]) for k, v in S.items()}


def pca_dir(X, n):
    Y = X[:n]
    w, Q = np.linalg.eigh(Y.T @ Y)
    i = int(np.argmax(w))
    u = Q[:, i]
    if u[np.argmax(np.abs(u))] < 0:
        u = -u
    return u, float(w[i] / max(1e-30, w.sum()))


def freqs(X, u, fps=60.0):
    """Deux estimateurs INDEPENDANTS sur la projection principale, publies cote a cote."""
    s = X @ u
    s = s - s.mean()
    # (a) passages par zero, bornes aux frames ou l'amplitude est encore lisible (>= 2 % du max)
    amp = np.abs(s)
    lim = int(np.max(np.nonzero(amp >= 0.02 * amp.max())[0])) + 1 if amp.max() > 0 else 0
    z = s[:lim]
    nz = int(np.sum(np.sign(z[:-1]) * np.sign(z[1:]) < 0)) if lim > 2 else 0
    fz = nz * fps / (2.0 * max(1, lim - 1)) if nz else float('nan')
    # (b) premier pic de l'autocorrelation, sur la meme portion
    fa = float('nan')
    if lim > 8:
        y = z - z.mean()
        ac = np.correlate(y, y, 'full')[len(y) - 1:]
        ac = ac / max(1e-30, ac[0])
        k = 1
        while k + 1 < len(ac) and not (ac[k] > ac[k - 1] and ac[k] >= ac[k + 1] and ac[k] > 0.05):
            k += 1
        if k + 1 < len(ac):
            fa = fps / k
    return fz, fa


def fit_damped(X, u, fps=60.0):
    """TROISIEME estimateur, INDEPENDANT des deux autres : ajustement d'une sinusoide amortie
    A*exp(-sigma*t)*cos(2*pi*f*t + phi) sur la projection principale, par moindres carres.

    (f, sigma) sont balayes sur une grille puis raffines ; (A, phi) sortent lineairement, donc
    aucun parametre n'est ajuste a la main. Rendus : f (Hz), zeta = sigma/sqrt(sigma^2+omega^2)
    — la grandeur que sa §25 fixe a 0.35 — et R^2, pour qu'un mauvais ajustement se VOIE au lieu
    de se lire comme une mesure.
    """
    y = X @ u
    y = y - y.mean()
    n = len(y)
    t = np.arange(n) / fps
    ss = float(y @ y)
    if ss <= 0:
        return float('nan'), float('nan'), float('nan')
    best = (1e30, 0.0, 0.0)
    def probe(fs, sg):
        nonlocal best
        for f in fs:
            w = 2 * math.pi * f
            for sig in sg:
                E = np.exp(-sig * t)
                M = np.column_stack([E * np.cos(w * t), E * np.sin(w * t)])
                coef, res, rank, _ = np.linalg.lstsq(M, y, rcond=None)
                r = float(((M @ coef - y) ** 2).sum())
                if r < best[0]:
                    best = (r, f, sig)
    probe(np.arange(1.20, 4.001, 0.01), np.arange(0.5, 14.01, 0.25))
    _, f0, s0 = best
    probe(np.arange(max(0.5, f0 - 0.02), f0 + 0.0201, 0.001),
          np.arange(max(0.05, s0 - 0.25), s0 + 0.2501, 0.01))
    r, f, sig = best
    w = 2 * math.pi * f
    zeta = sig / math.sqrt(sig * sig + w * w)
    return f, zeta, 1.0 - r / ss


def ringdown(X, u, fps=60.0):
    """SPEC 26 et 27, lues sur la MEME serie propre et sans aucun ajusteur.

    NATURE  des RAPPORTS sans dimension (§26) et des DUREES en secondes (§27).
    REPERE  la projection de la serie sur sa direction principale, dans le triedre de l'ancre.
    LIGNE DE BASE  la decroissance libre s'eteint vers 0 : le solveur ramene l'ecart a la pose
            d'auteur a zero, et c'est ce zero qui sert de reference — pas une moyenne ajustee.
    CE QUI EST A MOI ET PAS A SA SPEC  sa §27 nomme quatre etapes (« dominant visible response »,
            « secondary », « mostly settled », « essentially stationary ») sans donner le SEUIL
            qui les separe. Les seuils 10 % et 2 % du premier extremum sont MON choix ; ils sont
            declares ici et sur la ligne du registre, jamais presentes comme les siens.
    """
    y = X @ u
    n = len(y)
    ex = []                                    # extrema locaux signes
    for i in range(1, n - 1):
        if (y[i] - y[i - 1]) * (y[i + 1] - y[i]) < 0:
            ex.append((i, float(y[i])))
    if not ex:
        return (float('nan'),) * 5
    i1, a1 = ex[0]
    o2 = next((v for _, v in ex if v * a1 < 0), float('nan'))
    o3 = float('nan')
    seen_opp = False
    for _, v in ex:
        if v * a1 < 0:
            seen_opp = True
        elif seen_opp:
            o3 = v
            break
    A = abs(a1)
    def settle(frac):
        thr = frac * A
        k = n
        while k > 0 and abs(y[k - 1]) <= thr:
            k -= 1
        return k / fps
    return (abs(o2) / A if A else float('nan'), abs(o3) / A if A else float('nan'),
            (i1 + 1) / fps, settle(0.10), settle(0.02))


def ang(a, b):
    # NORMALISER AVANT : les vecteurs de `PHYSAXW` sont imprimes a 5 decimales, donc leur norme
    # vaut 0.999998 et un `acos` direct rendait 0.12 deg la ou les deux lignes sont IDENTIQUES.
    a = np.asarray(a, float); b = np.asarray(b, float)
    a = a / max(1e-30, np.linalg.norm(a)); b = b / max(1e-30, np.linalg.norm(b))
    return math.degrees(math.acos(max(-1.0, min(1.0, abs(float(np.dot(a, b)))))))


def main(path):
    txt = open(path, errors='replace').read()
    OLD = load(txt, 'PHYSRINGBX', 'PHYSRINGBX2')     # les six fenetres livrees (AXV/AXB/AXL)
    NEW = load(txt, 'PHYSRINGBN', 'PHYSRINGBN2')     # PH-AXC, entree propre
    A = print
    A('== C96 — SPEC 24/25/26/27 : LA MEME IMPULSION, ENTREE CONTAMINEE contre ENTREE PROPRE ==')
    A('   Trace : %s' % path)
    A('   AX  = les trois fenetres livrees (PH-AXV/AXB/AXL) — ax=1 et ax=2 heritent d\'un saut')
    A('         d\'ancre de 365 u en une frame le long de l\'axe de la fenetre precedente.')
    A('   AXC = les trois MEMES impulsions, retour en demi-cosinus + 60 frames de calme.')
    A('')
    if not NEW:
        A('C96: ABSENT — aucune ligne PHYSRINGBN. La phase PH-AXC n\'a pas ete jouee.')
        return 1
    if not OLD:
        A('C96: ABSENT — aucune ligne PHYSRINGBX.')
        return 1

    # ---- l'etat d'entree, publie par la salle -------------------------------------------------
    A('-- C96-PRE : LE RESIDU A LA PREMIERE FRAME DE CHAQUE FENETRE PROPRE (unites de jeu) ------')
    A('   Il n\'existe PAS pour les fenetres livrees : rien ne le publiait, et c\'est le defaut.')
    A('   %-8s %-3s %-4s %10s %10s' % ('chaine', 'l', 'ax', '|pre|', '|pre|/max(AXC)'))
    PRE = {}
    for m in re.finditer(r'^PHYSAXPRE c=(\d+) l=(\d+) ax=(\d+) v=([-\d.e+]+) ap=([-\d.e+]+)'
                         r' lat=([-\d.e+]+)', txt, re.M):
        PRE[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = np.array(
            [float(m.group(4)), float(m.group(5)), float(m.group(6))])
    for k in sorted(PRE):
        n = float(np.linalg.norm(PRE[k]))
        mx = float(np.linalg.norm(NEW[k], axis=1).max()) if k in NEW else float('nan')
        A('   %-8s %-3d %-4s %10.6f %10.6f' % (NAMES[k[0]], k[1], AXN[k[2]], n, n / mx if mx else float('nan')))
    A('')

    # ---- amplitude et direction, les deux jeux dans le meme code ------------------------------
    A('-- C96-AMP/DIR : AMPLITUDE ET DIRECTION PRINCIPALE (PCA sur f=1..40) ---------------------')
    A('   %-8s %-3s %-4s | %9s %9s %6s | %9s %9s %6s | %7s' %
      ('chaine', 'l', 'ax', 'AX f=1', 'AX max', 'AX/ax', 'AXC f=1', 'AXC max', 'AXC/ax', 'dir AX'))
    A('   %-8s %-3s %-4s | %9s %9s %6s | %9s %9s %6s | %7s' %
      ('', '', '', '', '', 'deg', '', '', 'deg', 'vs AXC'))
    D = {}
    for c in (0, 1):
        for l in (0, 1):
            for ax in (0, 1, 2):
                k = (c, l, ax)
                if k not in OLD or k not in NEW:
                    continue
                uo, _ = pca_dir(OLD[k], 40); un, _ = pca_dir(NEW[k], 40)
                D[('AX', c, l, ax)] = uo; D[('AXC', c, l, ax)] = un
                e = np.eye(3)[ax]
                A('   %-8s %-3d %-4s | %9.2f %9.2f %6.1f | %9.2f %9.2f %6.1f | %7.1f' % (
                    NAMES[c], l, AXN[ax],
                    float(np.linalg.norm(OLD[k][0])), float(np.linalg.norm(OLD[k], axis=1).max()),
                    ang(uo, e),
                    float(np.linalg.norm(NEW[k][0])), float(np.linalg.norm(NEW[k], axis=1).max()),
                    ang(un, e), ang(uo, un)))
    A('')

    # ---- LA question de §24 : les trois axes sont-ils separables ? ----------------------------
    A('-- C96-SEP : L\'ANGLE ENTRE LES REPONSES DES TROIS AXES (la question de §24) -------------')
    A('   Sa §24 attache une frequence a chaque DIRECTION. Deux reponses a 10 deg l\'une de')
    A('   l\'autre sont UNE direction : la separation par axe n\'existe pas, quelle que soit la')
    A('   frequence lue sur chacune.')
    A('   %-4s %-8s %-3s | %10s %10s %10s' % ('jeu', 'chaine', 'l', 'ang(v,ap)', 'ang(v,lat)', 'ang(ap,lat)'))
    for leg in ('AX', 'AXC'):
        for c in (0, 1):
            for l in (0, 1):
                try:
                    a0, a1, a2 = (D[(leg, c, l, i)] for i in (0, 1, 2))
                except KeyError:
                    continue
                A('   %-4s %-8s %-3d | %10.1f %10.1f %10.1f' %
                  (leg, NAMES[c], l, ang(a0, a1), ang(a0, a2), ang(a1, a2)))
    A('')

    # ---- frequences ---------------------------------------------------------------------------
    A('-- C96-FREQ : DEUX ESTIMATEURS INDEPENDANTS, COTE A COTE (Hz) ---------------------------')
    A('   Cibles de sa §24 : v 2.30 (2.1-2.5) · ap 2.50 (2.3-2.7) · lat 2.65 (2.4-2.9).')
    A('   Sa §25 fixe zeta = 0.35 (bande 0.30-0.42) ; R^2 dit si l\'ajustement a un sens.')
    A('   tau = 1/(zeta*2*pi*f) est la constante de temps de l\'ENVELOPPE. Le nominal de sa spec')
    A('   (f=2.30, zeta=0.35) donne tau_spec = 0.1976 s : c\'est la grandeur que §27 re-exprime en')
    A('   durees, et la comparer directement evite d\'avoir a choisir un seuil de « settled ».')
    A('   %-4s %-8s %-3s %-4s | %9s %9s | %9s %7s %6s %7s'
      % ('jeu', 'chaine', 'l', 'ax', 'zero-cr', 'autocorr', 'fit f', 'zeta', 'R2', 'tau s'))
    for leg, SS in (('AX', OLD), ('AXC', NEW)):
        for c in (0, 1):
            for l in (0, 1):
                for ax in (0, 1, 2):
                    k = (c, l, ax)
                    if k not in SS:
                        continue
                    u = D[(leg, c, l, ax)]
                    fz, fa = freqs(SS[k], u)
                    ff, zz, r2 = fit_damped(SS[k], u)
                    tau = 1.0 / (zz * 2 * math.pi * ff) if (zz and ff) else float('nan')
                    A('   %-4s %-8s %-3d %-4s | %9.3f %9.3f | %9.3f %7.3f %6.3f %7.4f'
                      % (leg, NAMES[c], l, AXN[ax], fz, fa, ff, zz, r2, tau))
    A('')

    # ---- l'axe pousse, revalide a l'execution -------------------------------------------------
    A('-- C96-POSE : L\'AXE REELLEMENT POUSSE DANS LES DEUX JEUX (revalidation de l\'epingle) ---')
    A('   La pose de PH-AXC est epinglee sur l\'animation 0 frame 0, celle des fenetres AX. Si les')
    A('   deux triedres different, les deux jeux ne sont PAS comparables et il faut le dire.')
    W = {}
    for tag in ('PHYSAXW', 'PHYSAXWN'):
        for m in re.finditer(r'^%s ax=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)' % tag,
                             txt, re.M):
            W.setdefault(tag, {})[int(m.group(1))] = np.array(
                [float(m.group(2)), float(m.group(3)), float(m.group(4))])
    for ax in (0, 1, 2):
        a = W.get('PHYSAXW', {}).get(ax); b = W.get('PHYSAXWN', {}).get(ax)
        if a is None or b is None:
            A('   ax=%s : ABSENT' % AXN[ax]); continue
        A('   ax=%-4s AX (%+.5f,%+.5f,%+.5f)  AXC (%+.5f,%+.5f,%+.5f)  ecart %.4f deg'
          % (AXN[ax], a[0], a[1], a[2], b[0], b[1], b[2], ang(a, b)))
    A('')

    # ---- excursion de chair et stimulus recu --------------------------------------------------
    A('-- C96-COMEX : L\'EXCURSION DU CENTRE DE CHAIR PAR FENETRE (B0), ET LE STIMULUS RECU -----')
    old = {}
    for m in re.finditer(r'^PHYSAXCOM c=(\d+) ax=(\d+) nolen=0 comex=([-\d.e+]+)', txt, re.M):
        old[(int(m.group(1)), int(m.group(2)))] = float(m.group(3))
    new = {}
    for m in re.finditer(r'^PHYSAXCOMN c=(\d+) ax=(\d+) comex=([-\d.e+]+) stim=([-\d.e+]+)',
                         txt, re.M):
        new[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)))
    A('   %-8s %-4s | %9s %9s %8s | %9s' % ('chaine', 'ax', 'AX comex', 'AXC comex', 'AXC/AX', 'AXC stim'))
    for c in (0, 1):
        for ax in (0, 1, 2):
            o = old.get((c, ax)); n = new.get((c, ax))
            if o is None or n is None:
                continue
            A('   %-8s %-4s | %9.4f %9.4f %8.3f | %9.4f' % (NAMES[c], AXN[ax], o, n[0], n[0] / o if o else float('nan'), n[1]))
    A('')
    A('-- C96-RING : SPEC 26 (rebond) ET SPEC 27 (extinction) SUR LA FENETRE PROPRE -----------')
    A('   §26 : rebond oppose ~30-31 %% du precedent, deuxieme retour 4-6 mm pour 50 mm (8-12 %%).')
    A('   §27 : « mostly settled » 1.0-1.5 s, « essentially stationary » 1.3-1.7 s. LES SEUILS')
    A('   10 %% et 2 %% QUI SEPARENT CES ETAPES SONT LES MIENS : sa §27 n\'en donne aucun.')
    A('   %-4s %-8s %-3s %-4s | %8s %8s %7s | %7s %8s %8s'
      % ('jeu', 'chaine', 'l', 'ax', 'reb1/A1', 'reb2/A1', 'z(dec)', 't(A1)s', 't<10%%s', 't<2%%s'))
    for leg, SS in (('AX', OLD), ('AXC', NEW)):
        for c in (0, 1):
            for l in (0, 1):
                for ax in (0, 1, 2):
                    k = (c, l, ax)
                    if k not in SS:
                        continue
                    r1, r2, t1, t10, t02 = ringdown(SS[k], D[(leg, c, l, ax)])
                    # TROISIEME estimateur de zeta, INDEPENDANT de l'ajustement : le decrement
                    # logarithmique sur les DEUX PREMIERS extrema bruts. delta = ln(A1/A2),
                    # zeta = delta/sqrt(pi^2+delta^2). Aucun parametre, aucune fenetre choisie.
                    zl = float('nan')
                    if r1 == r1 and 0 < r1 < 1:
                        dl = math.log(1.0 / r1)
                        zl = dl / math.sqrt(math.pi ** 2 + dl * dl)
                    A('   %-4s %-8s %-3d %-4s | %8.4f %8.4f %7.3f | %7.3f %8.3f %8.3f'
                      % (leg, NAMES[c], l, AXN[ax], r1, r2, zl, t1, t10, t02))
    A('')
    A('-- C96-CTRL : LE TEMOIN NEGATIF (ax=0, propre dans LES DEUX jeux) ------------------------')
    worst = 0.0
    for c in (0, 1):
        for l in (0, 1):
            k = (c, l, 0)
            if k in OLD and k in NEW:
                r = float(np.linalg.norm(NEW[k], axis=1).max()) / max(1e-9, float(np.linalg.norm(OLD[k], axis=1).max()))
                d = ang(D[('AX', c, l, 0)], D[('AXC', c, l, 0)])
                worst = max(worst, abs(r - 1.0))
                A('   %-8s l=%d : amplitude AXC/AX = %.4f, ecart de direction = %.2f deg' % (NAMES[c], l, r, d))
    A('   ECART MAXIMAL DU TEMOIN : %.2f %% en amplitude.' % (100.0 * worst))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'))
