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

Usage: physics_ringdown.py <log> [--chains c=7,c=8] [--first N]
"""
import sys, re, math, cmath

def load(path):
    """(c,l) -> [(f, x, y, z)] tries par frame, plus les noms de chaine et les parametres."""
    ser, names, links, bone = {}, {}, {}, {}
    r3 = re.compile(r'PHYSRING3 c=(\d+) f=(\d+) l=(\d+) x=([-\d.eE+]+) y=([-\d.eE+]+) z=([-\d.eE+]+)')
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
            m = rs.match(line)
            if m:
                stage.setdefault((int(m.group(1)), int(m.group(3))), []).append(
                    (int(m.group(2)), float(m.group(4)), float(m.group(5)))); continue
            m = rr.match(line)
            if m:
                ang.setdefault((int(m.group(1)), int(m.group(3))), []).append(
                    (int(m.group(2)), float(m.group(4))))
    for d in (ser, stage, ang):
        for k in d: d[k].sort()
    return ser, stage, ang, names, links, bone


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


def report(path, want=None, first=0):
    ser, stage, ang, names, links, bone = load(path)
    if not ser:
        print("PHYSRING3 absent de la trace — la salle ne publie pas encore le vecteur signe.")
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
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:]]
    log = args[0]
    want = None; first = 0
    for i, a in enumerate(args):
        if a == "--chains": want = {int(x.split('=')[-1]) for x in args[i + 1].split(',')}
        if a == "--first": first = int(args[i + 1])
    sys.exit(report(log, want, first))
