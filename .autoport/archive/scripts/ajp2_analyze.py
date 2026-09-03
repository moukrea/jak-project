#!/usr/bin/env python3
"""Gfixed-tick-anim-interp-2 — depouillement des legs x86.

CE QUI CHANGE PAR RAPPORT AU CYCLE 1, ET POURQUOI.

1. LE VERDICT SE PREND AUX DEUX BOUTS. Le cycle 1 exigeait une cadence > 60 img/s et
   reléguait les cadences basses en « hors verdict ». L'owner joue vers 20 img/s : la
   porte regardait ailleurs.

2. LA CONDITION EST DECLAREE, PAS SUPPOSEE. A 30 img/s PARFAITEMENT VERROUILLEES,
   l'horloge se verrouille aussi, alpha vaut 1,0 et il n'y a rien a interpoler : les
   deux bras publient la meme ligne. Ce n'est pas « pas d'amelioration », c'est une
   CONDITION ABSENTE, et une ablation sur une condition absente ne prouve rien. Chaque
   ligne porte donc `verrou_pct` et `dev_median` : si `verrou_pct` vaut 100, la ligne
   est un TEMOIN, jamais un verdict.

3. DEUX DERIVATIONS INDEPENDANTES DE LA MEME GRANDEUR.
   - `ANIMJIT` : ecart image-a-image de la position MONDE d'un joint, mesure sur la pose
     REELLEMENT DESSINEE (sonde AJP, posee apres `(*draw-hook*)`) ;
   - `ANIMAVANCE` : avance de la pose en TICKS, reconstruite depuis la seule horloge
     (sonde GFT), par l'identite  rendu(n) = ticks_cumules(n) - 1 + alpha(n).
     Elle ne partage avec la premiere ni la sonde, ni la fenetre, ni la quantification
     flottante. Les directives exigent ce contre-controle des qu'une famille de verdicts
     repose sur une seule chaine de mesure.

AXE. La composante VERTICALE porte le verdict, et c'est une limite d'INSTRUMENT : sur
Geyser Rock, x ~ -5,39e6 et z ~ 4,36e6 unites, ou le pas d'un flottant 32 bits vaut
0,5 unite — la quantification y ecrase le signal. y vaut ~3,3e4, pas 0,0039. Les trois
axes sont publies avec la preuve que deux sont satures (`ANIMAXE`).

FENETRE. Images de queue ou la RACINE est immobile (Jak debout, attente qui boucle). La
regle est la MEME pour les deux bras et ne regarde que la racine, jamais la grandeur
jugee.
"""
import re, os, sys, statistics, argparse

AJP = re.compile(r'^AJP n=(\d+) arm=(\d+) skip=(\d+) alpha=([-\d.]+) ni=(\d+) ag=(-?\d+) fn=([-\d.]+) (.*)$')
GFT = re.compile(r'^GFT n=\d+ lf=(-?\d+) armed=(\d+) skip=(\d+) k=(\d+) alpha=(\d+) dt_ms=([\d.]+)'
                 r'.*?lock=(\d+) dev=([\d.]+) cl=(\d+) cc=(\d+) ticklock=(\d+)')
VEC = re.compile(r'(\w+)=(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)')

# fps, gigue %, role de la ligne
CONDITIONS = [
    (20, 12, 'verdict'),   # LE REGIME DE L'OWNER : ~20 img/s, duree d'image variable
    (30, 12, 'verdict'),   # la cadence ou le cycle 1 publiait « legerement pire »
    (25,  0, 'verdict'),   # cadence basse a dither NATUREL (60/25 = 2,4), sans stimulus
    (120, 0, 'verdict'),   # haute cadence
    (180, 0, 'verdict'),   # haute cadence
    (30,  0, 'temoin'),    # CADENCE VERROUILLEE : la condition est ABSENTE, par construction
    (60,  0, 'hors'),      # la reference, ni basse ni haute
]

# Memes cadences, HORLOGE LIVREE (`OG_TICK_LOCK=0`) : l'avant/apres sur LE MEME binaire,
# la MEME course et la MEME suite de durees d'image.
LIVRE = [
    (20, 12, 'livre'),
    (30, 12, 'livre'),
]


def read(path):
    a, g = [], []
    for raw in open(path, 'rb'):
        l = raw.decode('utf-8', 'replace')
        m = AJP.match(l)
        if m:
            p = {k: (float(x), float(y), float(z)) for k, x, y, z in VEC.findall(m.group(8))}
            if 'j40' in p:
                a.append(dict(n=int(m.group(1)), skip=int(m.group(3)), alpha=float(m.group(4)),
                              ni=int(m.group(5)), ag=int(m.group(6)), fn=float(m.group(7)),
                              pts=p, raw=m.group(8).strip()))
            continue
        m = GFT.match(l)
        if m:
            g.append(dict(armed=int(m.group(2)), skip=int(m.group(3)), k=int(m.group(4)),
                          alpha=int(m.group(5)), dt=float(m.group(6)), lock=int(m.group(7)),
                          dev=float(m.group(8)), cl=int(m.group(9)), cc=int(m.group(10)),
                          tl=int(m.group(11))))
    return a, g


def root_stable_from(a):
    """Premier indice a partir duquel la RACINE ne bouge plus (Jak debout, attente qui
       boucle). Le debut d'une course porte le warp F1 et la chute d'apparition — jusqu'a
       des millions d'unites en UNE image, presentes a l'identique dans les deux bras.
       La regle ne regarde que la racine, jamais la grandeur jugee."""
    i = len(a) - 1
    while i > 0:
        p, q = a[i]['pts']['r'], a[i - 1]['pts']['r']
        if max(abs(p[k] - q[k]) for k in range(3)) > 1e-6:
            break
        i -= 1
    return i


def game_time_offset(a_on, a_off):
    """DECALAGE DE TEMPS DE JEU ENTRE LES DEUX BRAS, mesure et non suppose.

    `n` (`real-actual-frame-counter`) compte a partir du demarrage du moteur, pas de
    l'ancre du rejeu : deux courses qui n'ont pas passe le meme nombre d'images en
    CHARGEMENT portent le meme instant de jeu sous deux `n` differents. Compare a `n`
    nu, la course a 60 img/s — ou les deux bras sont identiques au bit par construction
    (verrou 100 %, retimes = 0) — ne rendait que 23,3 % d'images identiques.

    L'ancre utilisee est `fn`, le `frame-num` de LOGIQUE du canal 0 : il est une
    fonction deterministe du tick de rejeu et n'est JAMAIS retime (le retimage est
    strictement de rendu). Le decalage est le mode des ecarts de `n` sur les couples
    (`ag`, `fn`) egaux — donc une grandeur mesuree sur le contenu, pas un ajustement."""
    from collections import Counter
    idx = {}
    for x in a_off:
        idx.setdefault((x['ag'], round(x['fn'], 4)), []).append(x['n'])
    c = Counter()
    for x in a_on:
        for n_off in idx.get((x['ag'], round(x['fn'], 4)), ()):
            d = n_off - x['n']
            if abs(d) <= 900:
                c[d] += 1
    return (c.most_common(1)[0] if c else (0, 0))


def common_window(a_on, a_off, span):
    """FENETRE APPARIEE EN TEMPS DE JEU, ET DANS UNE SEULE ANIMATION.

    `n` est `real-actual-frame-counter`, qui avance d'un TICK DE LOGIQUE (mesure : a
    20 img/s il progresse de 3 par image dessinee). C'est donc une horloge de JEU,
    identique dans les deux bras. Sans cet appariement la comparaison est vide : les
    deux courses n'ayant pas la meme duree, elles finissaient a des points DIFFERENTS
    de l'animation d'attente, et a 60 img/s — ou les deux bras sont identiques au bit
    par construction — elles publiaient 527 contre 1877.

    `ag` est l'adresse du `frame-group` joue sur le canal 0. Un CHANGEMENT d'animation
    est une discontinuite de pose REELLE, que le retimage ne peut ni ne doit lisser, et
    elle sature un maximum : sur une fenetre qui en contenait une, les deux bras
    publiaient le MEME 1039,3867. La fenetre est donc le PLUS LONG segment ou `ag` est
    constant dans LES DEUX bras — un critere de CONTENU, jamais la grandeur jugee."""
    d, _ = game_time_offset(a_on, a_off)
    n_stable = max(a_on[root_stable_from(a_on)]['n'],
                   a_off[root_stable_from(a_off)]['n'] - d)
    m_on, m_off = {}, {}
    for x in a_on:
        m_on.setdefault(x['n'], x['ag'])
    for x in a_off:
        m_off.setdefault(x['n'] - d, x['ag'])
    ns = sorted(set(m_on) & set(m_off))
    ns = [n for n in ns if n >= n_stable]
    best = cur = None
    for i, n in enumerate(ns):
        if i and m_on[n] == m_on[ns[i - 1]] and m_off[n] == m_off[ns[i - 1]]:
            cur = (cur[0], n)
        else:
            cur = (n, n)
        if best is None or cur[1] - cur[0] > best[1] - best[0]:
            best = cur
    n_lo, n_hi = best
    if n_hi - n_lo > span:
        n_lo = n_hi - span
    w_on = [x for x in a_on if n_lo <= x['n'] <= n_hi]
    w_off = [x for x in a_off if n_lo <= x['n'] - d <= n_hi]
    return w_on, w_off, n_lo, n_hi, d


def gft_for(a, g, win):
    """Sous-suite de la sonde d'horloge alignee sur la fenetre de poses. AJP et GFT sont
       emises UNE fois par image dessinee ; on repere la fenetre par sa position depuis
       LA FIN, ce qui reste exact meme quand une course a dessine plus d'images."""
    if not win:
        return []
    end_off = len(a) - 1 - a.index(win[-1])
    hi = len(g) - end_off
    return g[max(0, hi - len(win)):hi]


def axis(win, key, k):
    s = [f['pts'][key][k] for f in win]
    return sorted(abs(s[i] - s[i - 1]) for i in range(1, len(s)))


def norm3(win, key):
    s = [f['pts'][key] for f in win]
    return sorted(sum((s[i][k] - s[i - 1][k]) ** 2 for k in range(3)) ** 0.5 for i in range(1, len(s)))


def q(v, p):
    return v[int(p * (len(v) - 1))] if v else 0.0


def advance(gw, armed):
    """Avance de la pose DESSINEE en ticks, reconstruite depuis la seule horloge.
       rendu(n) = ticks_cumules(n) - 1 + alpha(n)  quand la pose est retimee ;
       rendu(n) = ticks_cumules(n)                 quand elle ne l'est pas."""
    tot = 0.0
    r = []
    for x in gw:
        tot += 0 if x['skip'] else x['k']
        r.append(tot - 1.0 + x['alpha'] / 1e6 if armed else tot)
    return [r[i] - r[i - 1] for i in range(1, len(r))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default='.autoport/reports/Gfixed-tick-anim-interp-2')
    ap.add_argument('--joint', default='j40')
    ap.add_argument('--span', type=int, default=900,
                    help='largeur de la fenetre appariee, en TICKS de logique')
    args = ap.parse_args()

    R, lines = {}, []
    print("%-4s %-4s %-5s %-4s %6s %8s %6s %7s %6s %8s %9s %9s %9s %11s %8s" % (
        "fps", "gig", "horl", "anim", "img", "fps_mes", "skip%", "k_moy", "verr%",
        "dev_med", "Y_moy", "Y_p99", "Y_max", "ticks/s_jeu", "retimes"))
    for fps, jit, role in CONDITIONS + LIVRE:
        suf = '_livre' if role == 'livre' else ''
        raw = {}
        for arm in ('on', 'off'):
            p = os.path.join(args.dir, 'f%dj%d_%s%s.log' % (fps, jit, arm, suf))
            if os.path.exists(p):
                a, g = read(p)
                if a and g:
                    raw[arm] = (a, g)
        if len(raw) != 2:
            continue
        w_on, w_off, n_lo, n_hi, dec = common_window(raw['on'][0], raw['off'][0], args.span)
        for arm, win in (('on', w_on), ('off', w_off)):
            a, g = raw[arm]
            gw = gft_for(a, g, win)
            if len(win) < 3 or not gw:
                continue
            dy, dx, dz = (axis(win, args.joint, k) for k in (1, 0, 2))
            d3 = norm3(win, args.joint)
            fm = 1000.0 / statistics.median([x['dt'] for x in gw])
            ks = [0 if x['skip'] else x['k'] for x in gw]
            secs = sum(x['dt'] for x in gw) / 1000.0
            adv = advance(gw, arm == 'on')
            R[(fps, jit, arm, role == 'livre')] = dict(
                tl=statistics.median([x['tl'] for x in gw]),
                kmax=max(ks), kmean=statistics.mean(ks), moy=statistics.mean(dy),
                p99=q(dy, .99), mx=dy[-1], m3=d3[-1], n=len(dy), fm=fm,
                nlo=n_lo, nhi=n_hi, dec=dec,
                sk=100.0 * sum(1 for x in gw if x['skip']) / len(gw),
                lock=100.0 * sum(1 for x in gw if x['lock']) / len(gw),
                dev=statistics.median([x['dev'] for x in gw]),
                cl=gw[-1]['cl'] - gw[0]['cl'], cc=gw[-1]['cc'] - gw[0]['cc'],
                a1=100.0 * sum(1 for x in gw if x['alpha'] == 1000000) / len(gw),
                gps=sum(ks) / secs if secs else 0, ni=win[-1]['ni'] - win[0]['ni'],
                xq=all(abs(v * 2 - round(v * 2)) < 1e-6 for v in dx),
                zq=all(abs(v * 2 - round(v * 2)) < 1e-6 for v in dz),
                xmax=dx[-1], zmax=dz[-1], ag=win[0]['ag'],
                agn=len({x['ag'] for x in win}) - 1,
                amoy=statistics.mean(adv), amax=max(adv), amin=min(adv),
                ap99=q(sorted(adv), .99))
            r = R[(fps, jit, arm, role == 'livre')]
            print("%-4d %-4d %-5s %-4s %6d %8.1f %6.0f %7.3f %6.1f %8.4f %9.4f %9.4f %9.4f %11.2f %8d" % (
                fps, jit, 'livree' if role == 'livre' else 'neuve', arm, r['n'], r['fm'],
                r['sk'], r['kmean'], r['lock'], r['dev'], r['moy'], r['p99'], r['mx'],
                r['gps'], r['ni']))

    print()
    print("%-4s %-4s %-6s %11s %11s %8s %9s %9s %8s" % (
        "fps", "gig", "horl", "max_desarme", "max_arme", "rapport", "rapport99",
        "PREDIT", "accord%"))
    tagmap = {'verdict': 'ANIMJIT', 'temoin': 'ANIMJIT-TEMOIN-CADENCE-VERROUILLEE',
              'hors': 'ANIMJIT-HORS-VERDICT', 'livre': 'ANIMJIT-HORLOGE-LIVREE'}
    for fps, jit, role in CONDITIONS + LIVRE:
        lv = role == 'livre'
        on, off = R.get((fps, jit, 'on', lv)), R.get((fps, jit, 'off', lv))
        if not on or not off:
            continue
        # PREDICTION : sans retimage la pose est TENUE puis SAUTE, donc son plus grand
        # ecart image-a-image vaut le plus grand nombre de ticks qu'une image porte
        # (k_max) ; retimee, elle avance du nombre MOYEN de ticks par image (k_moyen).
        th = off['kmax'] / off['kmean'] if off['kmean'] else 1.0
        rap = off['mx'] / on['mx'] if on['mx'] else 0.0
        print("%-4d %-4d %-6s %11.4f %11.4f %8.3f %9.3f %9.3f %8.1f" % (
            fps, jit, 'livree' if lv else 'neuve', off['mx'], on['mx'], rap,
            off['p99'] / on['p99'] if on['p99'] else 0.0, th, 100.0 * rap / th if th else 0))
        for arm, r in (('1', on), ('0', off)):
            lines.append("%s fps=%d arme=%s gigue_pct=%d horloge_corrigee=%d "
                         "ecart_moyen=%.4f ecart_max=%.4f ecart_p99=%.4f axe=vertical "
                         "joint=%s images=%d ticks_fenetre=%d-%d fps_mesure=%.1f "
                         "skip_pct=%.0f k_moyen=%.3f k_max=%d verrou_pct=%.1f "
                         "dev_median=%.4f ecretages=%d rattrapages_satures=%d "
                         "ticks_jeu_par_s=%.2f alpha1_pct=%.1f retimes=%d "
                         "ecart_max_3D=%.4f predit=%.3f max_sur_moyen=%.2f "
                         "anim_id=%d transitions_fenetre=%d decalage_jeu=%d" % (
                             tagmap[role], fps, arm, jit, int(r['tl']), r['moy'], r['mx'],
                             r['p99'], args.joint, r['n'], r['nlo'], r['nhi'], r['fm'],
                             r['sk'], r['kmean'], r['kmax'], r['lock'], r['dev'], r['cl'],
                             r['cc'], r['gps'], r['a1'], r['ni'], r['m3'], th,
                             r['mx'] / r['moy'] if r['moy'] else 0.0, r['ag'],
                             r['agn'], r['dec']))
        lines.append(("ANIMAVANCE-HORLOGE-LIVREE " if lv else "ANIMAVANCE ") +
                     "fps=%d gigue_pct=%d source=horloge_GFT "
                     "arme_moy=%.4f arme_max=%.4f arme_min=%.4f arme_p99=%.4f "
                     "desarme_moy=%.4f desarme_max=%.4f desarme_min=%.4f "
                     "amplitude_arme_pct=%.1f amplitude_desarme_pct=%.1f" % (
                         fps, jit, on['amoy'], on['amax'], on['amin'], on['ap99'],
                         off['amoy'], off['amax'], off['amin'],
                         100.0 * (on['amax'] - on['amin']) / on['amoy'] if on['amoy'] else 0,
                         100.0 * (off['amax'] - off['amin']) / off['amoy'] if off['amoy'] else 0))
        lines.append(("ANIMAXE-HORLOGE-LIVREE " if lv else "ANIMAXE ") +
                     "fps=%d gigue_pct=%d quantifie_x=%d quantifie_z=%d pas_flottant=0.5 "
                     "x_max_arme=%.4f x_max_desarme=%.4f z_max_arme=%.4f z_max_desarme=%.4f" % (
                         fps, jit, 1 if on['xq'] and off['xq'] else 0,
                         1 if on['zq'] and off['zq'] else 0,
                         on['xmax'], off['xmax'], on['zmax'], off['zmax']))

    # ---- NON-REGRESSION 60 img/s ----
    # DEUX PREUVES, ET LA PREMIERE SE SUFFIT.
    #  1. `retimes_course_entiere` : `*anim-interp-n*` compte CHAQUE appel de
    #     `joint-channel-render-frame` qui a rendu autre chose que `(-> chan frame-num)`.
    #     A zero sur la course ENTIERE, le decompresseur a recu exactement le meme
    #     flottant qu'avant cette phase, a chaque appel. C'est une identite PAR
    #     CONSTRUCTION, elle ne depend d'aucune seconde course.
    #  2. comparaison caractere par caractere des DEUX bras dans la fenetre appariee.
    #
    # Le chiffre sur la course ENTIERE est publie aussi, et il est plus bas. Sa cause est
    # nommee et elle n'est PAS l'interpolation : celle-ci n'a jamais tire (preuve 1).
    # Deux courses en temps reel ne passent pas le meme nombre d'images en chargement, et
    # l'attente de Jak choisit ses animations de remplissage — les deux bras finissent sur
    # des CONTENUS differents hors fenetre. C'est aussi ce qui rendait la mesure du
    # cycle 1 fragile : sa course s'arretait avant la divergence.
    p_on = os.path.join(args.dir, 'f60j0_on.log')
    p_off = os.path.join(args.dir, 'f60j0_off.log')
    if os.path.exists(p_on) and os.path.exists(p_off):
        a_on, g_on = read(p_on)
        a_off, _ = read(p_off)
        w_on, w_off, n_lo, n_hi, dec = common_window(a_on, a_off, args.span)
        m = {}
        for x in a_off:
            m.setdefault(x['n'] - dec, x['raw'])
        comp = [x for x in w_on if x['n'] in m]
        same = sum(1 for x in comp if x['raw'] == m[x['n']])
        tot = [x for x in a_on if x['n'] in m]
        same_tot = sum(1 for x in tot if x['raw'] == m[x['n']])
        ni_tot = (a_on[-1]['ni'] - a_on[0]['ni']) if a_on else -1
        lines.append("ANIM60 identique_au_bit=%d images_comparees=%d identiques=%d pct=%.4f "
                     "retimes_course_entiere=%d verrou_pct=%.1f decalage_jeu=%d "
                     "ticks_fenetre=%d-%d images_course_entiere=%d pct_course_entiere=%.2f" % (
                         1 if (comp and same == len(comp) and ni_tot == 0) else 0,
                         len(comp), same, 100.0 * same / len(comp) if comp else 0.0, ni_tot,
                         100.0 * sum(1 for x in g_on if x['lock']) / len(g_on) if g_on else 0.0,
                         dec, n_lo, n_hi, len(tot),
                         100.0 * same_tot / len(tot) if tot else 0.0))

    print()
    for l in lines:
        print(l)


main()
