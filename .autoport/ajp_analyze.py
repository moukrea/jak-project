#!/usr/bin/env python3
"""Gfixed-tick-anim-interp — depouillement des legs x86 en lignes ANIMJIT.

GRANDEUR. Ecart image a image de la position d'un joint, mesure PAR IMAGE DESSINEE.
C'est la definition du contrat, et c'est la seule qui puisse voir le defaut : le nombre
de ticks de logique par image varie, donc sans retimage la pose dessinee est TENUE puis
SAUTE. Une mesure par TICK ne verrait rien du tout.

AXE. La composante VERTICALE porte le verdict, et c'est une limite d'INSTRUMENT, pas un
choix de confort. Sur Geyser Rock, Jak est a x ~ -5,39e6 et z ~ 4,36e6 unites ; le pas
d'un flottant 32 bits y vaut 2^-1 = 0,5 unite exactement, et TOUTES les valeurs
mesurees sur x et z sont des multiples de 0,5 (publie ci-dessous). La quantification
n'est PAS divisee par deux quand la pose est retimee : elle ecrase le signal. y vaut
~3,3e4, ou le pas vaut 0,0039 unite -- 128 fois plus fin. Les trois axes sont publies,
avec la preuve que deux d'entre eux sont satures par l'instrument.

FENETRE. Les images de queue ou la RACINE est immobile : Jak debout, animation d'attente
qui boucle. Le debut d'une course porte le warp F1 et la chute d'apparition (jusqu'a
6,9 millions d'unites en UNE image), present a l'identique dans les deux bras, qui
ecraserait `ecart_max` des deux cotes et rendrait la comparaison vide. La regle est la
MEME pour les deux bras et elle ne regarde que la racine, jamais la grandeur jugee.

MOYENNE ET MAXIMUM ENSEMBLE. La moyenne est la meme des deux cotes (meme distance
totale, meme nombre d'images) : c'est leur RAPPORT qui porte le verdict. Publier le seul
maximum laisserait croire a une perte d'amplitude.
"""
import re, os, sys, statistics, argparse

AJP = re.compile(r'^AJP n=(\d+) arm=(\d+) skip=(\d+) alpha=([-\d.]+) ni=(\d+) (.*)$')
GFT = re.compile(r'^GFT n=\d+ lf=(-?\d+) armed=(\d+) skip=(\d+) k=(\d+) alpha=(\d+) dt_ms=([\d.]+)')
VEC = re.compile(r'(\w+)=(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)')


def read(path):
    a, g = [], []
    for raw in open(path, 'rb'):
        l = raw.decode('utf-8', 'replace')
        m = AJP.match(l)
        if m:
            p = {k: (float(x), float(y), float(z)) for k, x, y, z in VEC.findall(m.group(6))}
            if 'j40' in p:
                a.append(dict(skip=int(m.group(3)), alpha=float(m.group(4)), ni=int(m.group(5)), pts=p))
            continue
        m = GFT.match(l)
        if m:
            g.append(dict(armed=int(m.group(2)), skip=int(m.group(3)), k=int(m.group(4)),
                          alpha=int(m.group(5)), dt=float(m.group(6))))
    return a, g


def stable_tail(a, w):
    """Les images de queue ou la racine ne bouge pas (regime stable)."""
    i = len(a) - 1
    while i > 0:
        p, q = a[i]['pts']['r'], a[i - 1]['pts']['r']
        if max(abs(p[k] - q[k]) for k in range(3)) > 1e-6:
            break
        i -= 1
    seg = a[i:]
    return seg[-w:] if len(seg) > w else seg


def axis(win, key, k):
    s = [f['pts'][key][k] for f in win]
    return sorted(abs(s[i] - s[i - 1]) for i in range(1, len(s)))


def norm3(win, key):
    s = [f['pts'][key] for f in win]
    return sorted(sum((s[i][k] - s[i - 1][k]) ** 2 for k in range(3)) ** 0.5 for i in range(1, len(s)))


def q(v, p):
    return v[int(p * (len(v) - 1))] if v else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default='.autoport/reports/Gfixed-tick-anim-interp')
    ap.add_argument('--fps', default='30,45,60,90,120,180,240')
    ap.add_argument('--joint', default='j40')
    ap.add_argument('--win', type=int, default=700)
    ap.add_argument('--verdict', default='60,180,240',
                    help="cadences portant une ligne ANIMJIT de verdict")
    args = ap.parse_args()
    cad = [int(x) for x in args.fps.split(',')]
    verdict = set(int(x) for x in args.verdict.split(','))

    R = {}
    print("%-4s %-4s %6s %8s %6s %7s %9s %9s %9s %9s %11s %9s" % (
        "fps", "anim", "img", "fps_mes", "skip%", "k_moy", "Y_moy", "Y_p99", "Y_max",
        "3D_max", "ticks/s_jeu", "retimes"))
    for fps in cad:
        for arm in ('on', 'off'):
            p = os.path.join(args.dir, 'f%d_%s.log' % (fps, arm))
            if not os.path.exists(p):
                continue
            a, g = read(p)
            if not a:
                continue
            win = stable_tail(a, args.win)
            gw = g[-len(win):]
            dy = axis(win, args.joint, 1)
            dx = axis(win, args.joint, 0)
            dz = axis(win, args.joint, 2)
            d3 = norm3(win, args.joint)
            fm = 1000.0 / statistics.median([x['dt'] for x in gw])
            sk = 100.0 * sum(1 for x in gw if x['skip']) / len(gw)
            kmoy = statistics.mean(0 if x['skip'] else x['k'] for x in gw)
            secs = sum(x['dt'] for x in gw) / 1000.0
            ticks = sum(0 if x['skip'] else x['k'] for x in gw)
            a1 = 100.0 * sum(1 for x in gw if x['alpha'] == 1000000) / len(gw)
            ks = [0 if x['skip'] else x['k'] for x in gw]
            R[(fps, arm)] = dict(kmax=max(ks), kmean=statistics.mean(ks),
                                 moy=statistics.mean(dy), p99=q(dy, .99), mx=dy[-1],
                                 m3=d3[-1], n=len(dy), fm=fm, sk=sk, kmoy=kmoy, a1=a1,
                                 gps=ticks / secs if secs else 0,
                                 ni=win[-1]['ni'] - win[0]['ni'],
                                 xq=all(abs(v * 2 - round(v * 2)) < 1e-6 for v in dx),
                                 zq=all(abs(v * 2 - round(v * 2)) < 1e-6 for v in dz),
                                 xmax=dx[-1], zmax=dz[-1])
            r = R[(fps, arm)]
            print("%-4d %-4s %6d %8.1f %6.0f %7.3f %9.4f %9.4f %9.4f %9.4f %11.2f %9d" % (
                fps, arm, r['n'], r['fm'], r['sk'], r['kmoy'], r['moy'], r['p99'], r['mx'],
                r['m3'], r['gps'], r['ni']))

    print()
    print("%-4s %10s %10s %8s %9s %9s %9s" % ("fps", "max_desarme", "max_arme", "rapport",
                                              "rapport99", "PREDIT", "accord%"))
    out = []
    for fps in cad:
        if (fps, 'on') not in R or (fps, 'off') not in R:
            continue
        on, off = R[(fps, 'on')], R[(fps, 'off')]
        # PREDICTION, ET ELLE VAUT A TOUTES LES CADENCES, pas seulement au-dessus de 60 :
        # sans retimage la pose est TENUE puis SAUTE, donc son plus grand ecart image-a-image
        # vaut le plus grand nombre de ticks qu'une image porte (k_max) ; retimee, elle avance
        # du nombre MOYEN de ticks par image (k_moyen). Le rapport attendu est donc
        # k_max / k_moyen -- et `fps/60` n'en est que le cas particulier au-dessus de 60 Hz.
        th = off['kmax'] / off['kmean'] if off['kmean'] else 1.0
        print("%-4d %10.4f %10.4f %8.3f %9.3f %9.3f %9.1f" % (
            fps, off['mx'], on['mx'], off['mx'] / on['mx'], off['p99'] / on['p99'], th,
            100.0 * (off['mx'] / on['mx']) / th))
        for arm, r in (('1', on), ('0', off)):
            line = ("ANIMJIT fps=%d arme=%s ecart_moyen=%.4f ecart_max=%.4f "
                    "axe=vertical joint=%s images=%d fps_mesure=%.1f skip_pct=%.0f "
                    "k_moyen=%.3f k_max=%d ticks_jeu_par_s=%.2f alpha1_pct=%.1f retimes=%d "
                    "ecart_p99=%.4f ecart_max_3D=%.4f predit=%.3f" % (
                        fps, arm, r['moy'], r['mx'], args.joint, r['n'], r['fm'], r['sk'],
                        r['kmoy'], r['kmax'], r['gps'], r['a1'], r['ni'], r['p99'], r['m3'], th))
            out.append((fps, arm, line))
        out.append((fps, 'x', "ANIMAXE fps=%d quantifie_x=%d quantifie_z=%d pas_flottant=0.5 "
                              "x_max_arme=%.4f x_max_desarme=%.4f z_max_arme=%.4f z_max_desarme=%.4f "
                              "rapport_mesure=%.3f rapport_predit=%.3f accord_pct=%.1f" % (
                                  fps, 1 if on['xq'] and off['xq'] else 0,
                                  1 if on['zq'] and off['zq'] else 0,
                                  on['xmax'], off['xmax'], on['zmax'], off['zmax'],
                                  off['mx'] / on['mx'], th, 100.0 * (off['mx'] / on['mx']) / th)))
    print()
    for fps, arm, line in out:
        if arm == 'x' or fps in verdict:
            print(line)
        else:
            print(line.replace("ANIMJIT ", "ANIMJIT-HORS-VERDICT ", 1))


main()
