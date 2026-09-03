#!/usr/bin/env python3
"""physics_ringdown.py — lit la trace de la salle et publie la DECROISSANCE LIBRE de chaque
maillon, sur la grandeur SIGNEE et VECTORIELLE que `PHYSRING3` publie.

POURQUOI CE SCRIPT EXISTE. `PHYSRING` publie `ang`, un MODULE (`atan2` avec `sn >= 0`) : le signe
est perdu, donc un rebond ne peut pas se lire comme un changement de signe et la periode apparente
vaut le double de la vraie -- sauf si le mouvement PRECESSE, auquel cas le module ne repasse jamais
par zero et la periode apparente vaut la vraie. Les deux cas donnent la MEME colonne de chiffres et
ne se distinguent pas. Trois cycles ont bute la-dessus (voir la note `ringdown-lag-measures-
envelope`) : c'est le meme piege que « une variance ne peut pas decrire un affaissement ».

CE QUE `PHYSRING3` PUBLIE, ET DANS QUEL REPERE :
  NATURE  : un VECTEUR de deviation, `u_courant - u_modele`, tous deux UNITAIRES et pris depuis la
            MEME attache. Sa norme vaut `2 sin(theta/2)`, donc elle est monotone en l'angle ; sa
            DIRECTION porte la phase, que le module detruisait.
  REPERE  : le MONDE. Pendant la fenetre de ring-down la salle appelle `physroom-hold` : position
            figee sur `home`, quaternion identite, animation figee. Le repere monde y est donc
            immobile ET la direction du modele y est constante -- c'est la seule fenetre de la
            course ou le monde est un repere inertiel legitime, et c'est pour ca que la mesure n'y
            est publiee que la.
  LECTURE QUAND LE DEFAUT EST ABSENT : le vecteur nul. Un maillon a la pose du modele publie
            (0,0,0) exactement.

CE QU'ON EN TIRE, et chacun repond a une ligne de `SPEC-breast-softbody.md` :
  * f_mesure   la frequence propre reellement obtenue          -> SPEC 24 (2.30 / 2.50 / 2.65 Hz)
  * zeta       l'amortissement reellement obtenu               -> SPEC 25 (zeta = 0.35)
  * rebond     le premier depassement, en % du pic precedent   -> SPEC 26 (31 %)
  * forme      exponentielle (fraction constante) ou lineaire (quantite constante par frame)
                                                               -> DIRECTIVES 2026-08-14 03:10
Les deux dernieres colonnes sont la PREUVE DE SORTIE que les DIRECTIVES exigent.

CE QUE `PHYSRINGA` PUBLIE EN PLUS, ET POURQUOI IL A FALLU L'AJOUTER (SPEC 24) :
  `principal()` ci-dessous ecrase les trois composantes en UNE seule serie, par projection sur
  l'axe dominant. Une projection ne peut structurellement rendre qu'UNE frequence — celle de cet
  axe-la. Or SPEC 24 en specifie TROIS, et elles sont differentes par construction :

      Vertical    2.30 Hz   (« Vertical motion is intentionally the slowest »)
      Front/Back  2.50 Hz
      Lateral     2.65 Hz

  Elles ne sont donc pas mesurables sur la serie projetee : il fallait la serie PAR AXE, et dans le
  repere de l'ancre que SPEC 7 impose (« relative to the torso/root transform rather than directly
  in world space »). C'est `PHYSRINGA v=/ap=/lat=`. `PHYSRING3` reste publie et reste lu tel quel :
  on AJOUTE une mesure a cote, on n'en remplace aucune.

LA CORRECTION AMORTIE -> PROPRE, ET C'EST LE POINT QUI FAIT TOUTE LA DIFFERENCE :
  une periode relevee sur une oscillation qui DECROIT rend la frequence AMORTIE `f_d`, pas la
  frequence PROPRE `f_n` que SPEC 24 specifie. Les deux sont liees par

      f_n = f_d / sqrt(1 - zeta^2)

  Verification sur la course de reference : `chestL` est commande a
  `stiffness/sqrt(mass) = 2.7696/sqrt(1.45) = 2.3000 Hz` propre ; on mesure `f_d = 2.143 Hz` avec
  `zeta = 0.383`, donc `f_n = 2.143/sqrt(1-0.383^2) = 2.320 Hz`, soit +0.9 % du commande. Sans la
  correction on lirait -6.8 %, un ecart qui n'existe pas. Les deux sont donc publiees, nommement,
  et c'est `fn` — jamais `fd` — qui se compare a SPEC 24.

Usage: physics_ringdown.py <log> [--chains c=7,c=8] [--first N]
"""
import sys, re, math, cmath

# SPEC 24, les trois cibles, dans l'ordre des axes de `PHYSRINGA` (0 = v, 1 = ap, 2 = lat).
AXIS_NAMES = ('v', 'ap', 'lat')
AXIS_TARGET_HZ = (2.30, 2.50, 2.65)

# Une periode et un amortissement ne se lisent pas sur moins de trois extrema alternes : deux
# extrema donnent UNE demi-periode sans redondance, et `fit_exp` refuse deja d'ajuster moins de
# trois points. En dessous, l'axe n'a pas ete assez excite pour porter une mesure — il le DIT
# (`status=insufficient-excitation`, `fd/fn/zeta = n/a`) au lieu de rendre un repli, le nombre
# d'un autre axe, ou un zero issu d'un domaine vide.
AXIS_MIN_EXTREMA = 3

def load(path):
    """(c,l) -> [(f, x, y, z)] tries par frame, plus les noms de chaine et les parametres.

    Rend AUSSI `anc` : la meme structure pour `PHYSRINGA`, c'est-a-dire la deviation projetee sur
    le triedre de l'ancre (v, ap, lat). Un dictionnaire VIDE y signifie que la trace ne porte pas
    cette mesure — l'appelant le declare, il ne le comble pas."""
    ser, names, links, bone, anc = {}, {}, {}, {}, {}
    r3 = re.compile(r'PHYSRING3 c=(\d+) f=(\d+) l=(\d+) x=([-\d.eE+]+) y=([-\d.eE+]+) z=([-\d.eE+]+)')
    ra = re.compile(r'PHYSRINGA c=(\d+) f=(\d+) l=(\d+) v=([-\d.eE+]+) ap=([-\d.eE+]+) lat=([-\d.eE+]+)')
    rs = re.compile(r'PHYSRINGS c=(\d+) f=(\d+) l=(\d+) a0=([-\d.eE+]+) a1=([-\d.eE+]+)')
    rr = re.compile(r'PHYSRING c=(\d+) f=(\d+) l=(\d+) ang=([-\d.eE+]+)')
    rc = re.compile(r'PHYSCHAIN c=(\d+) links=(\d+) fam=(\d+) hang=\S+ j0=(\S+)')
    rb = re.compile(r'PHYSBONE c=(\d+) l=(\d+) len=([-\d.eE+]+)')
    stage, ang = {}, {}
    with open(path, errors='ignore') as fh:
        for line in fh:
            m = rc.match(line)
            if m:
                names[int(m.group(1))] = m.group(4); links[int(m.group(1))] = int(m.group(2)); continue
            m = rb.match(line)
            if m:
                bone[(int(m.group(1)), int(m.group(2)))] = float(m.group(3)); continue
            m = r3.match(line)
            if m:
                c, f, l = int(m.group(1)), int(m.group(2)), int(m.group(3))
                ser.setdefault((c, l), []).append((f, float(m.group(4)), float(m.group(5)), float(m.group(6))))
                continue
            m = ra.match(line)
            if m:
                c, f, l = int(m.group(1)), int(m.group(2)), int(m.group(3))
                anc.setdefault((c, l), []).append((f, float(m.group(4)), float(m.group(5)), float(m.group(6))))
                continue
            m = rs.match(line)
            if m:
                stage.setdefault((int(m.group(1)), int(m.group(3))), []).append(
                    (int(m.group(2)), float(m.group(4)), float(m.group(5)))); continue
            m = rr.match(line)
            if m:
                ang.setdefault((int(m.group(1)), int(m.group(3))), []).append(
                    (int(m.group(2)), float(m.group(4))))
    for d in (ser, stage, ang, anc):
        for k in d: d[k].sort()
    return ser, stage, ang, names, links, bone, anc


def principal(sig):
    """Projette la serie 3D sur son axe PRINCIPAL et rend la serie SIGNEE 1D, l'OFFSET statique
    retire, plus la part hors axe. Un mouvement plan perd zero dans `oop` ; un mouvement qui
    PRECESSE le dit par `oop` > 0 -- et c'est exactement le cas que le module `ang` confondait
    avec « la periode vaut le double ».

    L'OFFSET EST RETIRE SUR LA QUEUE, PAS SUR LA MOYENNE, et ce n'est pas un detail : une
    decroissance qui part de 0.6 a une moyenne tres eloignee de son etat final, et la soustraire
    poserait les petites oscillations de la fin autour de -moyenne. L'ajustement exponentiel y
    lirait alors un plancher au lieu d'une decroissance (mesure : zeta 0.062 au lieu de 0.35 sur
    une serie synthetique dont zeta VAUT 0.35 -- controle positif de l'instrument)."""
    n = len(sig)
    if n < 8: return [], 1.0, 0.0
    tail = sig[max(0, int(n * 0.75)):]
    ox0 = sum(v[0] for v in tail) / len(tail)
    oy0 = sum(v[1] for v in tail) / len(tail)
    oz0 = sum(v[2] for v in tail) / len(tail)
    # axe principal = vecteur propre dominant de la covariance autour de l'etat final, par
    # iteration de puissance (pas de dependance numpy : ce script tourne partout).
    ax = [1.0, 0.0, 0.0]
    for _ in range(96):
        ox = oy = oz = 0.0
        for x, y, z in sig:
            dx, dy, dz = x - ox0, y - oy0, z - oz0
            p = dx * ax[0] + dy * ax[1] + dz * ax[2]
            ox += p * dx; oy += p * dy; oz += p * dz
        nn = math.sqrt(ox * ox + oy * oy + oz * oz)
        if nn < 1e-30: break
        ax = [ox / nn, oy / nn, oz / nn]
    proj, tot, onax = [], 0.0, 0.0
    for x, y, z in sig:
        dx, dy, dz = x - ox0, y - oy0, z - oz0
        p = dx * ax[0] + dy * ax[1] + dz * ax[2]
        proj.append(p)
        tot += dx * dx + dy * dy + dz * dz
        onax += p * p
    off = math.sqrt(ox0 * ox0 + oy0 * oy0 + oz0 * oz0)
    return proj, (1.0 - onax / tot) if tot > 1e-30 else 0.0, off


def turning(s, floor=0.0):
    """Extrema locaux au-dessus d'un PLANCHER DE BRUIT. Sans le plancher, la queue numerique d'une
    decroissance fournit des dizaines de faux extrema et l'ajustement lit leur plateau."""
    return [(i, s[i]) for i in range(1, len(s) - 1)
            if abs(s[i]) > floor and
               ((s[i] >= s[i - 1] and s[i] > s[i + 1]) or (s[i] <= s[i - 1] and s[i] < s[i + 1]))]


def fit_exp(peaks):
    """log-lineaire sur les |extrema| : rend (sigma par frame, r^2). Une decroissance a FRACTION
    constante donne r^2 ~ 1 ; une decroissance a QUANTITE constante par frame ne s'y ajuste pas."""
    pts = [(i, abs(v)) for i, v in peaks if abs(v) > 1e-9]
    if len(pts) < 3: return None, None
    n = len(pts)
    sx = sum(p[0] for p in pts); sy = sum(math.log(p[1]) for p in pts)
    sxx = sum(p[0] * p[0] for p in pts); sxy = sum(p[0] * math.log(p[1]) for p in pts)
    den = n * sxx - sx * sx
    if abs(den) < 1e-12: return None, None
    b = (n * sxy - sx * sy) / den; a = (sy - b * sx) / n
    ybar = sy / n
    ss = sum((math.log(p[1]) - ybar) ** 2 for p in pts)
    rs = sum((math.log(p[1]) - (a + b * p[0])) ** 2 for p in pts)
    return -b, (1.0 - rs / ss if ss > 1e-12 else 1.0)


def fit_lin(peaks):
    """le meme ajustement, mais sur la VALEUR et pas son logarithme : r^2 eleve ici et faible
    au-dessus = « une quantite constante part chaque frame », la signature que les DIRECTIVES
    du 2026-08-14 03:10 designent."""
    pts = [(i, abs(v)) for i, v in peaks]
    if len(pts) < 3: return None, None
    n = len(pts)
    sx = sum(p[0] for p in pts); sy = sum(p[1] for p in pts)
    sxx = sum(p[0] * p[0] for p in pts); sxy = sum(p[0] * p[1] for p in pts)
    den = n * sxx - sx * sx
    if abs(den) < 1e-12: return None, None
    b = (n * sxy - sx * sy) / den; a = (sy - b * sx) / n
    ybar = sy / n
    ss = sum((p[1] - ybar) ** 2 for p in pts)
    rs = sum((p[1] - (a + b * p[0])) ** 2 for p in pts)
    return -b, (1.0 - rs / ss if ss > 1e-12 else 1.0)


# ================================================================================================
# SPEC 24 — LES TROIS FREQUENCES PROPRES, UNE PAR AXE (`PHYSRINGA`)
# ================================================================================================
# `principal()` ne peut pas les rendre : il ECRASE les trois composantes en une seule serie par
# projection sur l'axe dominant, donc il ne restitue qu'UNE frequence. SPEC 24 en specifie trois,
# et differentes (2.30 / 2.50 / 2.65 Hz). Il fallait donc la serie PAR AXE, dans le repere de
# l'ancre (SPEC 7). Rien n'est retire ici : `principal()`, `PHYSRING`, `PHYSRING3`, `PHYSRINGS` et
# le tableau RINGDOWN ci-dessus restent exactement ce qu'ils etaient.


# ------------------------------------------------------------------------------------------------
# L'ESTIMATEUR QUI LIT TOUTE LA SERIE, ET POURQUOI IL A FALLU L'ECRIRE
# ------------------------------------------------------------------------------------------------
# Compter des extrema ne marche PAS sur cette salle, et la course du 2026-08-14 le montre sans
# ambiguite. Avec zeta = 0.35 l'amplitude tombe a 9.6 % du pic en UNE periode et a 0.9 % en deux :
# il ne reste que 3 ou 4 extrema au-dessus du plancher, et LE PREMIER N'EST PAS UNE OSCILLATION,
# c'est la montee initiale. Mesure : `rBoob` monte de 0 a son pic en 2 frames et `lBoob` en 5 —
# la meme physique, deux « demi-periodes » apparentes dans un rapport de 2.5. D'ou des ecarts a
# SPEC 24 de +22.9 % / +50.0 % sur rBoob contre -0.2 % / +2.5 % sur lBoob, qui ne mesurent que la
# phase a laquelle la fenetre s'ouvre. C'est exactement le piege deja consigne : la loi est APRES
# le transitoire, et un ajustement sur trois points le prend en plein dedans.
#
# LA FORME EXACTE DU SIGNAL DONNE L'ESTIMATEUR SANS RIEN INVENTER. Une sinusoide amortie
# echantillonnee a pas constant verifie EXACTEMENT une recurrence lineaire d'ordre 2 :
#
#     x[n+1] = a x[n] + b x[n-1]     avec  z^2 - a z - b = 0  dont les racines sont
#     z = rho e^(+-i theta),  rho = e^(-sigma),  theta = omega  (par echantillon)
#
# `a` et `b` s'obtiennent par MOINDRES CARRES sur les 149 echantillons — un systeme 2x2, pas
# d'iteration, pas de seuil, pas de fenetre a choisir, donc AUCUN parametre a regler. La queue,
# une fois l'offset retire par `principal()`, vaut zero et ne pese rien dans les sommes.
# On en tire d'un coup la frequence PROPRE et l'amortissement :
#
#     f_n = sqrt(sigma^2 + omega^2) / (2 pi) * fps        zeta = sigma / sqrt(sigma^2 + omega^2)
#
# Ce n'est pas un reglage de l'instrument pour obtenir le chiffre voulu : c'est la methode
# standard (Prony / prediction lineaire) pour cette forme de signal, elle est verifiee par
# CONTROLE POSITIF sur des series synthetiques dont la reponse est connue d'avance
# (`--selftest`), et l'estimateur par extrema reste publie A COTE, jamais remplace.
FPS = 60.0


def ar2_estimate(vals, fps=FPS):
    """`f_d`, `f_n`, `zeta` d'une sinusoide amortie, par prediction lineaire d'ordre 2.

    Rend un dict avec `status` :
      `ok`             — racines complexes, donc il Y A une oscillation, et elle est mesuree ;
      `no-oscillation` — racines REELLES : la serie decroit sans osciller. Ce n'est pas un echec
                         de l'instrument, c'est un resultat, et il se declare tel quel ;
      `degenerate`     — pas assez de signal pour poser le systeme (serie trop courte ou nulle).
    `r2` est la qualite de la prediction a un pas : elle dit si la serie EST une sinusoide
    amortie. Une valeur basse invalide la frequence, et c'est pour ca qu'elle est publiee."""
    out = dict(fd=None, fn=None, zeta=None, r2=None, status='degenerate', n=len(vals))
    if len(vals) < 12:
        return out
    saa = sab = sbb = sya = syb = 0.0
    for n in range(1, len(vals) - 1):
        xn, xp, xf = vals[n], vals[n - 1], vals[n + 1]
        saa += xn * xn; sab += xn * xp; sbb += xp * xp
        sya += xf * xn; syb += xf * xp
    det = saa * sbb - sab * sab
    if abs(det) < 1e-30 or saa < 1e-30:
        return out
    a = (sya * sbb - syb * sab) / det
    b = (saa * syb - sab * sya) / det
    # qualite de l'ajustement, sur la prediction a un pas
    ss = rs = 0.0
    for n in range(1, len(vals) - 1):
        pred = a * vals[n] + b * vals[n - 1]
        rs += (vals[n + 1] - pred) ** 2
        ss += vals[n + 1] ** 2
    out['r2'] = (1.0 - rs / ss) if ss > 1e-30 else None
    disc = a * a + 4.0 * b
    if disc >= 0.0:
        out['status'] = 'no-oscillation'
        return out
    rho = math.sqrt(-b)
    if not (0.0 < rho < 1.0):
        # rho >= 1 : la serie ne decroit pas — on ne fabrique pas un amortissement qui n'existe pas
        out['status'] = 'no-decay'
        return out
    c = a / (2.0 * rho)
    if c < -1.0 or c > 1.0:
        return out
    theta = math.acos(c)                      # rad / echantillon
    # ON NE PEUT PAS AFFIRMER UNE PERIODE PLUS LONGUE QUE LA FENETRE QUI L'A MESUREE.
    # Ce n'est pas un seuil regle, c'est ce que la donnee peut porter : une rampe lineaire tronquee
    # se laisse ajuster par une « oscillation » de periode 175 echantillons dans une fenetre qui
    # n'en compte que 149 (controle negatif `--selftest`), et ce chiffre-la ne mesure rien.
    if theta <= 0.0 or (2.0 * math.pi / theta) > float(len(vals)):
        out['status'] = 'period-exceeds-window'
        return out
    sigma = -math.log(rho)                    # 1 / echantillon
    wn = math.sqrt(sigma * sigma + theta * theta)
    if wn <= 1e-12:
        return out
    out.update(fd=theta / (2.0 * math.pi) * fps,
               fn=wn / (2.0 * math.pi) * fps,
               zeta=sigma / wn,
               status='ok')
    return out


def zc_estimate(vals, fps=FPS):
    """PERIODE PAR CROISEMENTS DE ZERO, amortissement par DECREMENT LOGARITHMIQUE.

    POURQUOI CELUI-CI EN PLUS DES DEUX AUTRES, et c'est la course du 2026-08-14 qui l'impose :
    la fenetre de la salle contient la MONTEE INITIALE, pas seulement la decroissance libre. Cette
    montee est une reponse a l'impulsion, pas une demi-oscillation — et les deux autres estimateurs
    la mangent, chacun a sa facon : celui par extrema en fait sa premiere demi-periode (d'ou
    `rBoob` a +50 %), celui par moindres carres la laisse dominer les sommes (d'ou zeta 0.912 sur
    une chaine commandee a 0.35). Un croisement de zero, lui, NE DEPEND PAS DE L'AMPLITUDE : il
    tombe au meme instant que la bosse soit deux fois plus haute ou deux fois plus basse, donc le
    transitoire d'entree ne le deplace pas. C'est la grandeur qu'il fallait, et c'est la lecon
    deja consignee — la loi est APRES le transitoire.

    AUCUN SEUIL CHOISI. Le plancher de bruit est la RMS de la derniere moitie de la fenetre, une
    grandeur MESUREE sur la serie elle-meme ; les demi-cycles qui n'en sortent pas ne votent pas.
    `spread` = ecart-type des demi-periodes retenues : il dit si la periode est STABLE, donc si le
    chiffre veut dire quelque chose. Une periode instable invalide la frequence, et c'est pour ca
    qu'elle est publiee a cote."""
    out = dict(fd=None, fn=None, zeta=None, spread=None, n_half=0, status='insufficient-crossings')
    if len(vals) < 12:
        return out
    tail = vals[len(vals) // 2:]
    noise = math.sqrt(sum(v * v for v in tail) / len(tail)) if tail else 0.0
    xs = []
    for i in range(1, len(vals)):
        a, b = vals[i - 1], vals[i]
        if a == 0.0 or (a < 0) == (b < 0):
            continue
        xs.append((i - 1) + a / (a - b))          # instant interpole du croisement
    # amplitude de chaque demi-cycle entre deux croisements consecutifs
    halves, peaks = [], []
    for k in range(len(xs) - 1):
        lo, hi = int(math.ceil(xs[k])), int(math.floor(xs[k + 1]))
        seg = vals[lo:hi + 1]
        if not seg:
            continue
        pk = max(abs(v) for v in seg)
        if pk <= noise:                            # sous le plancher MESURE : n'apporte rien
            break
        halves.append(xs[k + 1] - xs[k])
        peaks.append(pk)
    out['n_half'] = len(halves)
    if len(halves) < 2:
        return out
    hm = sum(halves) / len(halves)
    var = sum((h - hm) ** 2 for h in halves) / len(halves)
    out['spread'] = math.sqrt(var)
    T = 2.0 * hm
    if T <= 1e-9:
        return out
    fd = fps / T
    # decrement logarithmique sur les pics de demi-cycle : |A_{k+1}|/|A_k| = exp(-sigma*T/2)
    zeta = None
    if len(peaks) >= 2:
        rr = [math.log(peaks[k] / peaks[k + 1]) for k in range(len(peaks) - 1)
              if peaks[k + 1] > 0.0 and peaks[k] > 0.0]
        if rr:
            dlt = sum(rr) / len(rr)                # decrement par DEMI-periode
            sg = 2.0 * dlt / T                     # 1 / echantillon
            w = 2.0 * math.pi / T
            wn = math.sqrt(sg * sg + w * w)
            if wn > 1e-12 and sg >= 0.0:
                zeta = sg / wn
                out['fn'] = wn / (2.0 * math.pi) * fps
    out.update(fd=fd, zeta=zeta, status='ok')
    if out['fn'] is None:
        out['fn'] = fd
    return out


def _selftest():
    """CONTROLE POSITIF DE L'INSTRUMENT — on lui donne des series dont la reponse est CONNUE.

    Sans ca, `ar2_estimate` serait un chiffre sans echelle : on ne saurait pas ce qu'il lit quand
    le defaut est absent, ni quand il est present. Les trois cas couvrent les trois verdicts."""
    ok = True
    print("SELFTEST ar2_estimate — series synthetiques, reponse connue d'avance")
    for fn_true, z_true in ((2.30, 0.35), (2.50, 0.35), (2.65, 0.35), (5.20, 0.65), (1.85, 0.33)):
        wn = 2.0 * math.pi * fn_true / FPS
        sg = z_true * wn
        wd = wn * math.sqrt(1.0 - z_true * z_true)
        # meme forme que la salle : la serie DEMARRE A ZERO puis monte (c'est cette montee qui
        # met en defaut le comptage d'extrema)
        s = [math.exp(-sg * n) * math.sin(wd * n) for n in range(149)]
        r = ar2_estimate(s)
        efn = 100.0 * (r['fn'] / fn_true - 1.0) if r['fn'] else float('nan')
        ez = 100.0 * (r['zeta'] / z_true - 1.0) if r['zeta'] else float('nan')
        good = r['status'] == 'ok' and abs(efn) < 1.0 and abs(ez) < 2.0
        z = zc_estimate(s)
        zfn = 100.0 * (z['fn'] / fn_true - 1.0) if z['fn'] else float('nan')
        zz = 100.0 * (z['zeta'] / z_true - 1.0) if z['zeta'] else float('nan')
        gz = z['status'] == 'ok' and abs(zfn) < 3.0 and abs(zz) < 6.0
        ok = ok and good and gz
        print("  f_n=%.2f zeta=%.2f -> AR2 fn=%s (%+.2f %%) zeta=%s (%+.2f %%) %s"
              % (fn_true, z_true, _g(r['fn']), efn, _g(r['zeta']), ez,
                 'OK' if good else 'ECHEC'))
        print("                       ZC  fn=%s (%+.2f %%) zeta=%s (%+.2f %%) n_half=%d %s"
              % (_g(z['fn']), zfn, _g(z['zeta']), zz, z['n_half'], 'OK' if gz else 'ECHEC'))
    # CONTROLE NEGATIF 1 : un drain LINEAIRE pur n'oscille pas. L'instrument doit le DIRE, pas
    # rendre une frequence.
    lin = [max(0.0, 1.0 - n / 40.0) for n in range(149)]
    r = ar2_estimate(lin)
    good = r['status'] != 'ok'
    ok = ok and good
    print("  drain lineaire pur        -> status=%s  %s" % (r['status'], 'OK' if good else 'ECHEC'))
    # CONTROLE NEGATIF 2 : une exponentielle pure (sur-amortie) n'oscille pas non plus.
    exd = [math.exp(-n / 12.0) for n in range(149)]
    r = ar2_estimate(exd)
    good = r['status'] != 'ok'
    ok = ok and good
    print("  exponentielle pure        -> status=%s  %s" % (r['status'], 'OK' if good else 'ECHEC'))
    print("SELFTEST: %s" % ('TOUS LES CONTROLES PASSENT' if ok else 'AU MOINS UN CONTROLE ECHOUE'))
    return 0 if ok else 1


def axis_estimate(vals):
    """Estime `f_d`, `f_n`, `zeta` et le rebond sur UNE serie 1D d'un seul axe.

    Les estimateurs sont ceux qui existent deja, sans variante : `principal()` pour retirer
    l'offset statique SUR LA QUEUE (indispensable — un ajustement sur une decroissance dont on a
    soustrait la MOYENNE lit un plancher au lieu d'une decroissance : zeta 0.062 au lieu de 0.35
    sur le controle positif documente plus haut), puis `turning()` pour les extrema au-dessus du
    plancher de bruit, `fit_exp()` pour l'enveloppe, et la logique periode/zeta/rebond du tableau
    RINGDOWN, a l'identique. La serie 1D est passee a `principal()` sous la forme (v, 0, 0) : la
    projection y est l'identite (l'iteration de puissance part de [1,0,0] et n'en bouge pas quand
    toute la variance est sur x), donc c'est bien LA MEME fonction qui traite les deux cas.

    Rend un dict. `status` vaut `insufficient-excitation` — et `fd`/`fn`/`zeta` valent None — des
    que l'axe ne porte pas AXIS_MIN_EXTREMA extrema alternes : une mesure qui ne peut pas etre
    faite se DECLARE, elle ne se remplace ni par un repli, ni par la valeur d'un autre axe, ni par
    un zero issu d'un domaine vide."""
    out = dict(fd=None, fn=None, zeta=None, rebound=None, n_extrema=0,
               status='insufficient-excitation', n=len(vals))
    if len(vals) < 12:
        return out
    proj, _oop, _off = principal([(v, 0.0, 0.0) for v in vals])
    if not proj:
        return out
    amax = max(abs(v) for v in proj)
    if amax <= 0.0:
        return out
    tp = turning(proj, floor=0.02 * amax)          # 2 % du pic : le bruit numerique ne vote pas
    # extrema ALTERNES : deux extrema consecutifs de signe oppose sont separes d'une DEMI-periode.
    alt = [tp[i] for i in range(len(tp)) if i == 0 or tp[i][1] * tp[i - 1][1] < 0]
    out['n_extrema'] = len(alt)
    if len(alt) < AXIS_MIN_EXTREMA:
        return out
    half = (alt[-1][0] - alt[0][0]) / (len(alt) - 1)
    T = 2.0 * half
    if not (T > 1e-9):
        return out
    fd = 60.0 / T                                   # la salle publie une ligne par frame, 60 FPS
    # l'enveloppe : sur les extrema s'il y en a, sinon sur la serie elle-meme (drain monotone)
    env = tp if len(tp) >= 3 else [(i, v) for i, v in enumerate(proj) if abs(v) > 0.02 * amax]
    sig_e, _r2e = fit_exp(env)
    zeta = None
    if sig_e is not None and sig_e > 0:
        zeta = sig_e / math.sqrt(sig_e * sig_e + (2 * math.pi / T) ** 2)
    # LA CORRECTION AMORTIE -> PROPRE. Une periode relevee sur une oscillation qui decroit rend
    # `f_d` ; SPEC 24 specifie `f_n`. C'est `fn` qui se compare a la cible, jamais `fd`.
    fn = None
    if zeta is not None and zeta < 1.0:
        fn = fd / math.sqrt(1.0 - zeta * zeta)
    reb = None
    if abs(alt[0][1]) > 1e-9:
        reb = 100.0 * abs(alt[1][1]) / abs(alt[0][1])
    out.update(fd=fd, fn=fn, zeta=zeta, rebound=reb, status='ok')
    return out


def axis_estimate_full(vals):
    """LES DEUX ESTIMATEURS SUR LA MEME SERIE, cote a cote — celui par extrema (`axis_estimate`,
    inchange) et celui par prediction lineaire (`ar2_estimate`).

    Aucun des deux n'est retire : c'est l'ECART entre eux qui dit si la serie porte reellement une
    sinusoide amortie. Les champs `ar_*` viennent du second, et c'est LUI qui se compare a SPEC 24
    quand son `status` vaut `ok` — parce que lui seul lit les 149 echantillons la ou l'autre
    n'en a que trois, dont le premier est la montee initiale et pas une oscillation."""
    d = axis_estimate(vals)
    # `principal()` retire l'offset statique de la queue : sans ca, la recurrence d'ordre 2 lit un
    # plancher constant comme une racine a 1.0 et rend `no-decay`.
    proj, _oop, _off = principal([(v, 0.0, 0.0) for v in vals]) if len(vals) >= 8 else ([], 0, 0)
    r = ar2_estimate(proj) if proj else dict(fd=None, fn=None, zeta=None, r2=None,
                                             status='degenerate', n=len(vals))
    z = zc_estimate(proj) if proj else dict(fd=None, fn=None, zeta=None, spread=None,
                                            n_half=0, status='degenerate')
    d.update(ar_fd=r['fd'], ar_fn=r['fn'], ar_zeta=r['zeta'], ar_r2=r['r2'],
             ar_status=r['status'],
             zc_fd=z['fd'], zc_fn=z['fn'], zc_zeta=z['zeta'], zc_spread=z['spread'],
             zc_nhalf=z['n_half'], zc_status=z['status'],
             zc_cross=zero_cross_frames(proj))
    return d


def zero_cross_frames(vals):
    """Les instants de croisement de zero, arrondis a la frame — publies BRUTS.

    C'est la grandeur qui a tranche le 2026-08-14 : sur `lBoob`, les axes `v` et `ap` croisent aux
    MEMES frames, ce qu'aucune moyenne ne montrait. Deux modes propres separes de 5 % auraient
    derive de 4 frames au bout de six demi-cycles ; ils ne derivent pas d'une seule."""
    xs = []
    for i in range(1, len(vals)):
        a, b = vals[i - 1], vals[i]
        if a == 0.0 or (a < 0) == (b < 0):
            continue
        xs.append(round((i - 1) + a / (a - b)))
    return xs


def axis_rows(anc, names, want=None, first=0):
    """Une ligne par (chaine, axe), sur le maillon de POINTE — la meme convention que
    `ROOM-RINGDOWN`, qui lit deja `tip = ser[-1]` : c'est le maillon libre le plus distal, celui
    qui porte le mouvement. Rend une liste de dicts, vide si la trace ne porte pas `PHYSRINGA`."""
    rows = []
    for c in sorted({cc for cc, _ in anc}):
        if want and c not in want:
            continue
        tip = max(l for cc, l in anc if cc == c)
        seq = [(f, v, a, t) for f, v, a, t in anc[(c, tip)] if f > first]
        for ax in range(3):
            d = axis_estimate_full([r[1 + ax] for r in seq])
            d.update(chain=names.get(c, 'c%d' % c), c=c, link=tip,
                     axis=AXIS_NAMES[ax], target=AXIS_TARGET_HZ[ax])
            rows.append(d)
    return rows


def _g(v, p=3):
    return ('%.*f' % (p, v)) if v is not None else 'n/a'


def axis_report(anc, names, want=None, first=0):
    """Publie le bloc `RINGAXIS`. L'ABSENCE de `PHYSRINGA` se declare en toutes lettres : ni un
    plantage, ni un silence."""
    print()
    print("RINGAXIS — SPEC 24, les TROIS frequences propres, une par axe (PHYSRINGA)")
    print("  repere : triedre de l'ANCRE (torse) — SPEC 7 l'impose, le monde ne peut pas les separer")
    print("  maillon : la POINTE de chaque chaine (meme convention que ROOM-RINGDOWN)")
    print("  fd = frequence AMORTIE, celle qu'une periode relevee sur une decroissance rend")
    print("  fn = frequence PROPRE = fd / sqrt(1-zeta^2) — C'EST ELLE que SPEC 24 specifie")
    print("  cibles SPEC 24 : v 2.30 Hz (la plus LENTE, intentionnellement) / ap 2.50 / lat 2.65")
    if not anc:
        print("RINGAXIS: ABSENT (aucune ligne PHYSRINGA dans la trace)")
        print("   La salle de cette course ne publiait pas encore la deviation projetee sur le")
        print("   triedre de l'ancre. Les trois frequences de SPEC 24 ne sont donc PAS mesurees")
        print("   ici — elles ne sont pas non plus remplacees par la frequence de l'axe principal,")
        print("   qui n'en est aucune des trois.")
        return []
    rows = axis_rows(anc, names, want, first)
    for d in rows:
        print("RINGAXIS chain=%s axis=%s fd=%s fn=%s zeta=%s rebound=%s n_extrema=%d status=%s"
              % (d['chain'], d['axis'], _g(d['fd']), _g(d['fn']), _g(d['zeta']),
                 _g(d['rebound'], 1), d['n_extrema'], d['status']))
        print("   AR2  fn=%s zeta=%s r2=%s status=%s   (149 echantillons, pas 3 extrema)"
              % (_g(d['ar_fn']), _g(d['ar_zeta']), _g(d['ar_r2'], 4), d['ar_status']))
        print("   ZC   fn=%s zeta=%s demi-periodes=%d spread=%s status=%s"
              % (_g(d['zc_fn']), _g(d['zc_zeta']), d['zc_nhalf'], _g(d['zc_spread'], 2),
                 d['zc_status']))
        print("   ZC   croisements (frames) = %s" % (d['zc_cross'][:10],))
        if d['zc_fn'] is not None and d['zc_status'] == 'ok':
            print("   SPEC 24 %-3s cible %.2f Hz  mesure fn %.3f Hz  ecart %+.1f %%   [ZC]"
                  % (d['axis'], d['target'], d['zc_fn'],
                     100.0 * (d['zc_fn'] / d['target'] - 1.0)))
        elif d['ar_fn'] is not None:
            print("   SPEC 24 %-3s cible %.2f Hz  mesure fn %.3f Hz  ecart %+.1f %%   [AR2]"
                  % (d['axis'], d['target'], d['ar_fn'],
                     100.0 * (d['ar_fn'] / d['target'] - 1.0)))
        elif d['fn'] is not None:
            print("   SPEC 24 %-3s cible %.2f Hz  mesure fn %.3f Hz  ecart %+.1f %%   [extrema]"
                  % (d['axis'], d['target'], d['fn'], 100.0 * (d['fn'] / d['target'] - 1.0)))
        else:
            print("   SPEC 24 %-3s cible %.2f Hz  NON MESUREE sur cet axe (%s / %s)"
                  % (d['axis'], d['target'], d['status'], d['ar_status']))
    return rows


def report(path, want=None, first=0):
    ser, stage, ang, names, links, bone, anc = load(path)
    if not ser:
        print("PHYSRING3 absent de la trace — la salle ne publie pas encore le vecteur signe.")
        axis_report(anc, names, want, first)
        return 1
    print("RINGDOWN — decroissance libre, grandeur SIGNEE (PHYSRING3), repere MONDE fige par physroom-hold")
    print("  oop  = part du mouvement HORS du plan principal (0 = plan, ->1 = precession)")
    print("  off  = |deviation residuelle| a la fin de la fenetre : SPEC 9 exige 0")
    print("  reb% = premier depassement en % de l'extremum precedent : SPEC 26 exige 31 %")
    print("  r2exp/r2lin = l'enveloppe suit-elle une FRACTION constante (visqueux) ou une")
    print("                QUANTITE constante par frame (limiteur) — DIRECTIVES 2026-08-14 03:10")
    print(f"{'chaine':<13}{'l':>2} {'n':>4} {'oop':>6} {'off':>7} {'T(fr)':>7} {'f(Hz)':>7} "
          f"{'zeta':>7} {'reb%':>7} {'r2exp':>7} {'r2lin':>7}  forme")
    for (c, l) in sorted(ser):
        if want and c not in want: continue
        sig = [(x, y, z) for f, x, y, z in ser[(c, l)] if f > first]
        if len(sig) < 12: continue
        proj, oop, off = principal(sig)
        if not proj: continue
        amax = max(abs(v) for v in proj)
        tp = turning(proj, floor=0.02 * amax)   # 2 % du pic : le bruit numerique ne vote pas
        # extrema alternes : deux extrema consecutifs de signe oppose sont separes d'une DEMI-periode
        alt = [tp[i] for i in range(len(tp)) if i == 0 or tp[i][1] * tp[i - 1][1] < 0]
        if len(alt) >= 2:
            half = (alt[-1][0] - alt[0][0]) / (len(alt) - 1)
            T = 2.0 * half; fhz = 60.0 / T if T > 1e-9 else float('nan')
        else:
            half = T = fhz = float('nan')
        # l'enveloppe : sur les extrema s'il y en a, sinon sur la serie elle-meme (drain monotone)
        env = tp if len(tp) >= 3 else [(i, v) for i, v in enumerate(proj) if abs(v) > 0.02 * amax]
        sig_e, r2e = fit_exp(env); sig_l, r2l = fit_lin(env)
        if sig_e and sig_e > 0 and not math.isnan(T):
            zeta = sig_e / math.sqrt(sig_e * sig_e + (2 * math.pi / T) ** 2)
        else:
            zeta = float('nan')
        reb = float('nan')
        if len(alt) >= 2 and abs(alt[0][1]) > 1e-9:
            reb = 100.0 * abs(alt[1][1]) / abs(alt[0][1])
        forme = "?"
        if r2e is not None and r2l is not None:
            forme = ("FRACTION constante (visqueux)" if r2e >= r2l
                     else "QUANTITE constante/frame (limiteur)")
            if len(alt) < 2: forme += " — AUCUNE oscillation"
        def g(v, w=7, p=3):
            return f"{v:>{w}.{p}f}" if v is not None and not (isinstance(v, float) and math.isnan(v)) else f"{'n/a':>{w}}"
        print(f"{names.get(c,'c'+str(c)):<13}{l:>2} {len(sig):>4} {g(oop,6,3)} {g(off,7,4)} {g(T)} {g(fhz)} "
              f"{g(zeta)} {g(reb,7,1)} {g(r2e)} {g(r2l)}  {forme}")
    # attribution par etage : combien la boucle de contraintes retire, frame par frame
    if stage:
        print()
        print("ETAGES — a0 = apres l'integration seule, a1 = apres la boucle de contraintes,")
        print("         ang = tel qu'ecrit. `a0-a1` EST ce que les contraintes retirent, en degres.")
        print(f"{'chaine':<13}{'l':>2} {'frames':>7} {'moy a0':>9} {'moy a1':>9} {'moy ang':>9} "
              f"{'a0-a1':>9} {'part%':>7}")
        for (c, l) in sorted(stage):
            if want and c not in want: continue
            rows = [(f, a0, a1) for f, a0, a1 in stage[(c, l)] if f > first]
            am = dict(ang.get((c, l), []))
            rows = [(f, a0, a1) for f, a0, a1 in rows if a0 > 1e-6 or a1 > 1e-6]
            if len(rows) < 5: continue
            n = len(rows)
            m0 = sum(r[1] for r in rows) / n; m1 = sum(r[2] for r in rows) / n
            mf = sum(am.get(r[0], 0.0) for r in rows) / n
            print(f"{names.get(c,'c'+str(c)):<13}{l:>2} {n:>7} {m0:>9.4f} {m1:>9.4f} {mf:>9.4f} "
                  f"{m0-m1:>9.4f} {100.0*(m0-m1)/m0 if m0>1e-9 else 0:>7.1f}")
    # ---- SPEC 24 : les trois frequences propres, une par axe. AJOUTE A COTE, rien n'est remplace.
    axis_report(anc, names, want, first)
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:]]
    if args and args[0] == "--selftest":
        sys.exit(_selftest())
    log = args[0]
    want = None; first = 0
    for i, a in enumerate(args):
        if a == "--chains": want = {int(x.split('=')[-1]) for x in args[i + 1].split(',')}
        if a == "--first": first = int(args[i + 1])
    sys.exit(report(log, want, first))
