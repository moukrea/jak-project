#!/usr/bin/env python3
"""probe_skin_blendband.py — LA LARGEUR DE LA BANDE DE MELANGE, ET NON SA MOYENNE.

Ce script ne genere rien, ne modifie rien, n'ecrit aucun fichier. Il lit
`recharged_assets/physics_chains.txt` (le fichier LIVRE) et un mesh (le mesh LIVRE par defaut),
et repond a la question que `probe_skin_profile` ne peut pas poser.

POURQUOI UN INSTRUMENT DE PLUS.

Defaut PRIORITE 1 de l'owner (`hair-anchored-geo`) : « une partie de la geometrie reste ancree et ca
casse ». `probe_skin_profile` publie, par decile d'abscisse, la MOYENNE de la part de poids portee
par la chaine. Cette moyenne ne tranche pas, et c'est mecanique : une meme moyenne sur un decile est
produite AUSSI BIEN par tous les sommets a la meme valeur intermediaire (transition progressive,
saine) que par un melange de sommets purs a 1.0 et de sommets purs a 0.0 (frontiere binaire, un
polygone mobile colle a un polygone fige — exactement le defaut decrit). C'est la DISTRIBUTION qu'il
faut lire, pas sa moyenne, et c'est le seul ecart entre ce fichier et `probe_skin_profile` : les
deux publient la meme colonne `moy`, calculee sur la meme selection de sommets et la meme abscisse,
pour que les deux tables se lisent cote a cote.

LES TROIS QUESTIONS DE LA SPEC 7, REPONDUES AVANT D'ECRIRE LA MESURE :

  NATURE : une DISTRIBUTION par abscisse, jamais une moyenne. Le defaut decrit est une frontiere
           BINAIRE entre voisins ; une moyenne ne distingue pas une valeur intermediaire uniforme
           d'un melange de purs 1.0 et de purs 0.0 qui rend la meme moyenne.
  REPERE : abscisse curviligne de la polyligne des joints de la chaine, pose de bind, racine=0
           pointe=1 (la fonction est celle de `probe_skin_profile`, importee, pas reecrite — les
           deux tables se lisent donc dans le meme repere). La grandeur pesee est `ws` = somme des
           poids du sommet sur TOUS les joints de la chaine, maillon racine verrouille COMPRIS :
           c'est le partage crane <-> meche, sans dimension, dans [0,1]. A ne pas confondre avec la
           somme MOBILE de `probe_skin_tear_moving`, qui exclut le maillon verrouille parce qu'elle
           mesure autre chose (la frontiere fige/mobile, pas la largeur de la bande).
  ABSENT : le controle APPARIE donne par l'owner — `lbang`/`rbang`, qu'il APPROUVE, mesures dans le
           MEME fichier, sur le meme mesh, avec le meme code. Aucun seuil invente : la cible est
           leur profil, lu ici et pas ailleurs.

CE QUE LA VUE PAR ARETES AJOUTE. Un decile peut etre mixte « en moyenne » sans qu'aucun VOISIN ne
saute : la cassure est un saut de poids entre deux sommets CONNECTES, donc la grandeur fidele porte
sur les aretes. Le seuil haut de comptage est importe de `probe_skin_tear_moving` (`JUMP`, voir la
constante ci-dessous, valeur imprimee a l'execution) pour que les deux comptes soient directement
comparables ; le seuil bas est propre a cette sonde.

CONTROLE POSITIF INTEGRE, ET IL DOIT TIRER (SPEC 7 : « tout zero exige un controle qui a MONTE »).
On prend `lbang` — le controle APPROUVE — et on BINARISE ses poids en memoire : chaque sommet passe
a 0 ou a 1 selon le cote ou il se trouve, la repartition etant rebouclee de facon coherente (le
poids retire va a `head`, le poids ajoute est pris a `head` puis au prorata des joints hors chaine).
C'est le defaut lui-meme, injecte sur la chaine que l'owner approuve. Si `mixte` ne s'effondre pas,
si `bin` ne monte pas, si la SEVERITE des aretes ne monte pas (p99, max, et le compte au seuil haut
partage avec probe_skin_tear_moving — voir le commentaire du critere, qui dit pourquoi le compte au
seuil BAS baisse et pourquoi ce n'est pas un controle casse), la sonde ne mesure pas ce qu'elle
annonce : elle imprime CONTROLE ECHOUE et sort en code non nul.

USAGE : python3 .autoport/probe_skin_blendband.py [chemin.glb]
        (defaut : le mesh du pack livre, chemin importe de probe_skin_profile)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_c6_volumes as c6            # noqa: E402
import probe_skin_profile as PSP           # noqa: E402  parse_chain_joints, arc_param, GATE, NBIN
import probe_skin_tear_moving as PST       # noqa: E402  edge_set, JUMP

CHAINS = PSP.CHAINS          # le fichier LIVRE, meme lecture que probe_skin_profile
SHIPPED = PSP.SHIPPED        # le mesh LIVRE, meme defaut que les deux sondes modeles
GATE = PSP.GATE              # meme seuil d'appartenance que probe_skin_profile
NBIN = PSP.NBIN              # memes deciles d'abscisse
JUMP = PST.JUMP              # IMPORTE de probe_skin_tear_moving : les deux comptes sont comparables
JUMP_SOFT = 0.25             # seuil bas, propre a cette sonde
PUR_LO, PUR_HI = 0.05, 0.95  # un sommet est PUR en dessous / au-dessus
TRANS_LO, TRANS_HI = 0.15, 0.85  # bande de moyenne ou `bin` a un sens (une transition a lieu)
BIN_SPLIT = 0.5              # cote du sommet pour la binarisation du controle positif


# ------------------------------------------------------------------------------------------------
# la mesure
# ------------------------------------------------------------------------------------------------
def ws_of(J, W, cols):
    """`ws` par sommet : part du poids du sommet portee par les joints `cols`, racine COMPRISE.

    Normalisee par le poids total du sommet, comme `probe_skin_profile.profile`, pour que la colonne
    `moy` des deux fichiers soit la meme grandeur et pas seulement le meme nom."""
    wtot = W.sum(axis=1)
    wtot = np.where(wtot < 1e-9, 1.0, wtot)
    arr = np.asarray(sorted(set(int(c) for c in cols)), dtype=np.int64)
    acc = np.zeros(len(W), dtype=np.float64)
    for c in range(J.shape[1]):
        m = np.isin(J[:, c], arr)
        acc += np.where(m, W[:, c], 0.0)
    return acc / wtot


def select(J, W, cols):
    """L'ensemble de sommets de la chaine — memes regles que `probe_skin_profile.profile`."""
    sel = np.zeros(len(W), dtype=bool)
    for c in range(J.shape[1]):
        for j in cols:
            sel |= (J[:, c] == j) & (W[:, c] > GATE)
    return np.flatnonzero(sel)


def measure(jn_list, idx_of, P, V, J, W, E, sel_fixed=None):
    """Table par decile + vue par aretes, pour UNE chaine.

    `sel_fixed` : ensemble de sommets impose (controle positif). La binarisation met a zero le poids
    de chaine des sommets du cote `tete` ; recalculer la selection les ferait sortir du decompte et
    le controle se mesurerait alors sur une AUTRE population que la mesure de base."""
    jidx = [idx_of[n] for n in jn_list if n in idx_of]
    if len(jidx) < 2:
        return None
    ws = ws_of(J, W, jidx)
    idx = select(J, W, jidx) if sel_fixed is None else np.asarray(sel_fixed, dtype=np.int64)
    if idx.size == 0:
        return None

    s, _beyond = PSP.arc_param(np.asarray([P[j] for j in jidx], dtype=float),
                               np.asarray(V[idx], dtype=float))
    wsel = ws[idx]

    bins = []
    for b in range(NBIN):
        lo, hi = b / NBIN, (b + 1) / NBIN
        m = (s >= lo) & (s < hi) if b < NBIN - 1 else (s >= lo)
        n = int(m.sum())
        if n == 0:
            bins.append(dict(n=0, moy=float('nan'), pt=0, mx=0, pm=0, binar=float('nan')))
            continue
        v = wsel[m]
        pt = int((v < PUR_LO).sum())
        pm = int((v > PUR_HI).sum())
        mx = n - pt - pm
        moy = float(v.mean())
        binar = float(pt + pm) / n if (TRANS_LO < moy < TRANS_HI) else float('nan')
        bins.append(dict(n=n, moy=moy, pt=pt, mx=mx, pm=pm, binar=binar))

    # ---- vue par aretes : les DEUX bouts dans l'ensemble de sommets de la chaine ----------------
    own = np.zeros(len(V), dtype=bool)
    own[idx] = True
    ed = dict(n=0)
    if len(E):
        m = own[E[:, 0]] & own[E[:, 1]]
        if m.any():
            u, v2 = E[m, 0], E[m, 1]
            d = np.abs(ws[u] - ws[v2])
            k = int(np.argmax(d))
            sfull = np.full(len(V), np.nan)
            sfull[idx] = s
            smax = 0.5 * (sfull[u[k]] + sfull[v2[k]])
            ed = dict(n=int(d.size),
                      p50=float(np.percentile(d, 50)), p90=float(np.percentile(d, 90)),
                      p99=float(np.percentile(d, 99)), mx=float(d.max()),
                      c_soft=int((d > JUMP_SOFT).sum()), c_hard=int((d > JUMP).sum()),
                      dmax=min(NBIN, int(smax * NBIN) + 1))
    return dict(n=int(idx.size), idx=idx, bins=bins, edge=ed,
                moy=float(wsel.mean()),
                mixte=int(sum(b['mx'] for b in bins)),
                pur=int(sum(b['pt'] + b['pm'] for b in bins)))


# ------------------------------------------------------------------------------------------------
# affichage
# ------------------------------------------------------------------------------------------------
def cell_i(v):
    return "%7d" % v


def cell_f(v, fmt="%7.3f"):
    return "      ." if (v is None or np.isnan(v)) else fmt % v


def print_block(cname, jn_list, r):
    print("%-12s %s   n=%d  moy=%.4f" % (cname, ",".join(jn_list), r['n'], r['moy']))
    print("  %-10s%s" % ("", "".join("%7s" % ("d%d" % (i + 1)) for i in range(NBIN))))
    print("  %-10s%s" % ("n", "".join(cell_i(b['n']) for b in r['bins'])))
    print("  %-10s%s" % ("moy", "".join(cell_f(b['moy']) for b in r['bins'])))
    print("  %-10s%s" % ("pur_tete", "".join(cell_i(b['pt']) for b in r['bins'])))
    print("  %-10s%s" % ("mixte", "".join(cell_i(b['mx']) for b in r['bins'])))
    print("  %-10s%s" % ("pur_meche", "".join(cell_i(b['pm']) for b in r['bins'])))
    print("  %-10s%s" % ("bin", "".join(cell_f(b['binar'], "%7.2f") for b in r['bins'])))


def print_edge_header():
    print("%-12s %8s %7s %7s %7s %7s %8s %8s %6s"
          % ("chaine", "aretes", "p50", "p90", "p99", "max",
             ">%.2f" % JUMP_SOFT, ">%.2f" % JUMP, "ou_max"))


def print_edge_row(cname, ed):
    if not ed or ed.get('n', 0) == 0:
        print("%-12s %8d   (aucune arete dont les deux bouts sont dans la chaine)"
              % (cname, ed.get('n', 0) if ed else 0))
        return
    print("%-12s %8d %7.3f %7.3f %7.3f %7.3f %8d %8d %6s"
          % (cname, ed['n'], ed['p50'], ed['p90'], ed['p99'], ed['mx'],
             ed['c_soft'], ed['c_hard'], "d%d" % ed['dmax']))


# ------------------------------------------------------------------------------------------------
# controle positif : on binarise `lbang` EN MEMOIRE
# ------------------------------------------------------------------------------------------------
def binarize(jn_list, idx_of, J, W, head_col):
    """Copie EN MEMOIRE des poids, avec `ws -> 0.0 si ws < BIN_SPLIT sinon 1.0`.

    La repartition du sommet reste coherente (somme des poids = 1) : le poids retire a la chaine va
    a `head` ; le poids ajoute a la chaine est pris a `head` d'abord, puis au prorata des joints
    hors chaine. Rend (J2, W2, stats) — aucun fichier n'est ecrit."""
    jset = set(idx_of[n] for n in jn_list if n in idx_of)
    J2 = J.copy()
    W2 = W.astype(np.float64).copy()
    wtot = W2.sum(axis=1)
    ws = ws_of(J, W, sorted(jset))
    st = dict(to0=0, to1=0, w_head_recu=0.0, w_head_pris=0.0, w_prorata=0.0, sans_slot=0)

    for v in np.flatnonzero(ws > 0.0):
        tot = wtot[v]
        if tot < 1e-9:
            continue
        w = W2[v] / tot
        jj = J2[v]
        ch = np.isin(jj, np.asarray(sorted(jset), dtype=np.int64))
        cur = float(w[ch].sum())
        if cur <= 0.0:
            continue
        if cur < BIN_SPLIT:
            removed = cur
            w[ch] = 0.0
            slots = np.flatnonzero(jj == head_col)
            if slots.size:
                w[slots[0]] += removed
            else:
                free = np.flatnonzero(w <= 1e-12)
                if free.size:
                    jj[free[0]] = head_col
                    w[free[0]] = removed
                else:
                    st['sans_slot'] += 1
                    continue
            st['w_head_recu'] += removed
            st['to0'] += 1
        else:
            need = 1.0 - cur
            slots = np.flatnonzero(jj == head_col)
            if need > 1e-12 and slots.size:
                take = min(float(w[slots[0]]), need)
                w[slots[0]] -= take
                need -= take
                st['w_head_pris'] += take
            if need > 1e-12:
                other = (~ch) & (jj != head_col) & (w > 0.0)
                pool = float(w[other].sum())
                if pool > 1e-12:
                    cut = min(need, pool)
                    w[other] = w[other] * (1.0 - cut / pool)
                    need -= cut
                    st['w_prorata'] += cut
            w[ch] = w[ch] * (1.0 / cur)
            st['to1'] += 1
        W2[v] = w
        J2[v] = jj
    return J2, W2, st


def agg_bin(bins, keys):
    """`bin` agrege sur un ENSEMBLE IMPOSE de deciles, pondere par le nombre de sommets."""
    n = sum(bins[k]['n'] for k in keys)
    if n == 0:
        return float('nan')
    return sum(bins[k]['pt'] + bins[k]['pm'] for k in keys) / float(n)


# ------------------------------------------------------------------------------------------------
def main():
    rel = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    geo = c6.load_geometry('keira-hd', glb=rel)
    if geo is None:
        print("mesh introuvable ou illisible : %s" % rel)
        return 1
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx_of = {n: i for i, n in enumerate(names)}
    F = geo.get('F')
    if F is None or len(F) == 0:
        print("ARETES ILLISIBLES — la vue par aretes ne peut pas etre prise, et un zero ne")
        print("voudrait rien dire (meme refus que probe_skin_tear_moving).")
        return 1
    E = np.asarray(sorted(PST.edge_set(F)), dtype=np.int64)

    chains = PSP.parse_chain_joints(CHAINS)
    print("BANDE DE MELANGE — mesh : %s" % rel)
    print("NATURE distribution par abscisse, jamais une moyenne · REPERE abscisse curviligne de la")
    print("polyligne des joints de la chaine, pose de bind, racine=0 pointe=1 ; grandeur ws = part")
    print("du poids du sommet portee par la chaine, maillon racine verrouille COMPRIS · ABSENT le")
    print("profil de lbang/rbang, le controle APPARIE approuve par l'owner, mesure dans ce fichier")
    print("%d sommets, %d joints, %d aretes · appartenance w>%.2f · pur si ws<%.2f ou ws>%.2f"
          % (len(V), len(names), len(E), GATE, PUR_LO, PUR_HI))
    print("bin = part des sommets PURS dans le decile, publie SEULEMENT si %.2f < moy < %.2f"
          % (TRANS_LO, TRANS_HI))
    print("")

    rows = []
    for cname, spec in sorted(chains.items()):
        jn_list = spec['joints']
        r = measure(jn_list, idx_of, P, V, J, W, E)
        if r is None:
            print("%-12s   -- moins de 2 joints presents dans ce mesh (%s)"
                  % (cname, ",".join(jn_list)))
            continue
        rows.append((cname, jn_list, r))
        print_block(cname, jn_list, r)
        print("")

    print("ARETES DONT LES DEUX BOUTS SONT DANS LA CHAINE — |delta ws| entre voisins CONNECTES.")
    print("Le seuil >%.2f est IMPORTE de probe_skin_tear_moving (sa constante JUMP) : les deux"
          % JUMP)
    print("comptes sont donc directement comparables. Le seuil >%.2f est propre a cette sonde."
          % JUMP_SOFT)
    print_edge_header()
    for cname, _jn, r in rows:
        print_edge_row(cname, r['edge'])

    # --------------------------------------------------------------------------------------------
    # CONTROLE POSITIF
    # --------------------------------------------------------------------------------------------
    print("")
    print("CONTROLE POSITIF — on BINARISE les poids de `lbang` (la chaine que l'owner APPROUVE)")
    print("en memoire : ws -> 0.0 si ws < %.2f sinon 1.0, repartition rebouclee (le poids retire va"
          % BIN_SPLIT)
    print("a `head`, le poids ajoute est pris a `head` puis au prorata des joints hors chaine).")
    print("Aucun mesh n'est ecrit. L'ensemble de sommets est GELE sur celui de la mesure de base,")
    print("sinon la binarisation sortirait du decompte les sommets qu'elle vient de mettre a zero.")

    ctl = 'lbang'
    base = next((r for cn, _j, r in rows if cn == ctl), None)
    if base is None:
        print("CONTROLE ECHOUE : `%s` n'est pas mesurable dans ce mesh, il n'y a donc pas de"
              " controle approuve a binariser." % ctl)
        return 2
    head_col = idx_of.get('head')
    if head_col is None:
        print("CONTROLE ECHOUE : le joint `head` est absent du mesh, la repartition ne peut pas")
        print("etre rebouclee de facon coherente.")
        return 2

    jn_ctl = dict(chains)[ctl]['joints']
    J2, W2, st = binarize(jn_ctl, idx_of, J, W, head_col)
    inj = measure(jn_ctl, idx_of, P, V, J2, W2, E, sel_fixed=base['idx'])
    if inj is None:
        print("CONTROLE ECHOUE : la mesure ne rend rien sur la copie binarisee.")
        return 2

    print("")
    print("sommets binarises a 0 : %d · a 1 : %d · poids rendu a `head` : %.3f · pris a `head` :"
          " %.3f · pris au prorata : %.3f · sommets sans slot libre : %d"
          % (st['to0'], st['to1'], st['w_head_recu'], st['w_head_pris'], st['w_prorata'],
             st['sans_slot']))
    print("")
    print("AVANT")
    print_block(ctl, jn_ctl, base)
    print("")
    print("APRES")
    print_block(ctl, jn_ctl, inj)
    print("")
    print_edge_header()
    print_edge_row(ctl + " avant", base['edge'])
    print_edge_row(ctl + " apres", inj['edge'])

    # `bin` compare sur les MEMES deciles : ceux ou la mesure de base publiait une transition.
    keys = [k for k in range(NBIN) if not np.isnan(base['bins'][k]['binar'])]
    if keys:
        b_av, b_ap = agg_bin(base['bins'], keys), agg_bin(inj['bins'], keys)
        klab = ",".join("d%d" % (k + 1) for k in keys)
    else:
        keys = [k for k in range(NBIN) if base['bins'][k]['n'] > 0]
        b_av, b_ap = agg_bin(base['bins'], keys), agg_bin(inj['bins'], keys)
        klab = "aucun decile en transition — agrege sur tous les deciles peuples (%s)" % \
               ",".join("d%d" % (k + 1) for k in keys)
    print("")
    print("bin agrege sur les deciles en transition de la mesure de base (%s) : %.4f -> %.4f"
          % (klab, b_av, b_ap))
    print("mixte (sommets) : %d -> %d · purs : %d -> %d"
          % (base['mixte'], inj['mixte'], base['pur'], inj['pur']))

    # CRITERE D'ACCEPTATION, ET IL PORTE SUR LA SEVERITE, PAS SUR LE NOMBRE D'ARETES TOUCHEES.
    # Mesure faite a l'execution la premiere fois que ce controle a tourne : le compte au seuil BAS
    # (>JUMP_SOFT) BAISSE sous binarisation, alors que p99, max et le compte au seuil HAUT (>JUMP)
    # montent. Ce n'est pas un controle casse, et la sonde le publie au lieu de le cacher : la
    # binarisation SUPPRIME les gradations intermediaires (deux voisins qui differaient d'un cran
    # entre les deux seuils basculent au MEME pole et ne different plus du tout) et CONCENTRE toute
    # la discontinuite sur les aretes qui enjambent la coupure, lesquelles sautent a 1.0. Le nombre
    # d'aretes touchees diminue donc pendant que la marche s'aggrave. Le critere est par consequent
    # : p99 monte, max monte, et le compte au seuil HAUT (celui qui est partage avec
    # probe_skin_tear_moving) monte.
    e_av, e_ap = base['edge'], inj['edge']
    ok_mixte = inj['mixte'] < base['mixte']
    ok_bin = (not np.isnan(b_ap)) and (not np.isnan(b_av)) and b_ap > b_av
    ok_edge = (e_av.get('n', 0) > 0 and e_ap.get('n', 0) > 0
               and e_ap['p99'] > e_av['p99'] and e_ap['mx'] > e_av['mx']
               and e_ap['c_hard'] > e_av['c_hard'])
    print("")
    print("CONTROLE: la binarisation fait monter bin|p99|count>%.2f sur %s : %.4f|%.4f|%d ->"
          " %.4f|%.4f|%d"
          % (JUMP, ctl, b_av, e_av.get('p99', float('nan')), e_av.get('c_hard', 0),
             b_ap, e_ap.get('p99', float('nan')), e_ap.get('c_hard', 0)))
    print("CONTROLE (detail mesure) : max %.4f -> %.4f · count>%.2f %d -> %d · p90 %.4f -> %.4f."
          % (e_av.get('mx', float('nan')), e_ap.get('mx', float('nan')), JUMP_SOFT,
             e_av.get('c_soft', 0), e_ap.get('c_soft', 0),
             e_av.get('p90', float('nan')), e_ap.get('p90', float('nan'))))
    print("Le compte au seuil BAS et p90 BAISSENT : la binarisation supprime les gradations")
    print("intermediaires et concentre la discontinuite sur les aretes qui enjambent la coupure.")
    print("Le critere porte donc sur la SEVERITE (p99, max, compte au seuil haut), pas sur le")
    print("nombre d'aretes touchees.")
    if not (ok_mixte and ok_bin and ok_edge):
        print("CONTROLE ECHOUE : mixte s'effondre=%s · bin monte=%s · severite d'arete monte=%s."
              % (ok_mixte, ok_bin, ok_edge))
        print("Une sonde dont le controle ne tire pas ne mesure pas ce qu'elle annonce ; rien de")
        print("ce qui precede ne vaut.")
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())
