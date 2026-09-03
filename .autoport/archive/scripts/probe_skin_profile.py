#!/usr/bin/env python3
"""probe_skin_profile.py — OU, LE LONG D'UNE MECHE, LA PEAU CESSE-T-ELLE D'ETRE PILOTEE ?

Ce script ne genere rien et ne modifie rien. Il lit `recharged_assets/physics_chains.txt` (le fichier
LIVRE) et un mesh (le mesh LIVRE par defaut), et repond a UNE question que `ROOM-SKINCOV` ne peut
pas poser.

POURQUOI UN INSTRUMENT DE PLUS, ET POURQUOI CELUI-LA.

L'owner, 13e passe : « la physique ne s'applique pas a toute la geometrie de ces deux meches mais a
seulement une partie, donc on a des polygones qui bougent et des polygones voisins parfaitement
statiques, causant la geometrie qui casse ».

`ROOM-SKINCOV` publie UN SCALAIRE par chaine :

    backhair cov=0.7259   lmidhair cov=0.7814   rmidhair cov=0.7750   earL/R cov=0.843

et ce scalaire NE PEUT PAS trancher, parce que deux etats radicalement differents le produisent :

  (a) les 27 % non pilotes sont a la RACINE — c'est CORRECT et meme exige : la SPEC 2 dit que la
      racine est soudee a l'os porteur, donc la peau du cuir chevelu DOIT suivre `head` ;
  (b) les 27 % non pilotes sont a la POINTE — c'est le defaut exact que l'owner decrit, un sommet
      soude a `head` colle a un sommet pilote par la meche.

Un scalaire de 0.73 est le meme dans les deux cas. C'est la troisieme fois du dossier qu'un SCALAIRE
est publie pour une FORME (apres `tipvar` pour un degrade et une variance pour un affaissement), et
la SPEC 7 exige desormais de repondre a trois questions AVANT d'ecrire la mesure :

  NATURE  : un PROFIL — une fonction de la position LE LONG de la meche, pas un nombre. Le defaut
            decrit est une DISCONTINUITE SPATIALE (voisins mobiles / voisins figes) ; aucune moyenne
            ne la distingue d'une attenuation douce.
  REPERE  : l'abscisse curviligne de la polyligne des joints DE LA CHAINE ELLE-MEME, en pose de bind
            du modele, normalisee racine=0 -> dernier joint=1. Ni le monde, ni le repere d'un os :
            « le long de la meche » n'a de sens que dans la meche.
  ABSENT  : le profil MONTE, de ~0 a la racine (le cuir chevelu suit le crane, c'est la SPEC 2) vers
            ~1 a la pointe. Le defaut est une fraction pilotee BASSE a une abscisse HAUTE.

CONTROLE POSITIF INTEGRE, ET IL DOIT TIRER (SPEC 7 : « tout zero exige un controle qui a monte »).
On recalcule le meme profil en declarant le VOLEUR (le joint hors chaine qui detient le poids) comme
s'il etait simule. Si la mesure lit bien le poids vole, chaque profil doit remonter ; s'il ne bouge
pas, la mesure ne mesure pas ce qu'elle annonce et le reste du fichier ne vaut rien.

CE QUE CE SCRIPT NE DIT PAS. Il ne dit rien de ce que le MOTEUR fait des descendants rigides d'un
maillon : il publie la lecture STRICTE (poids porte par les joints de la chaine). Pour les cheveux
la distinction ne change rien — le poids perdu part vers `head`, qui est un ANCETRE et jamais un
descendant — et le tableau des voleurs le montre ligne par ligne plutot que de l'affirmer.

USAGE : python3 .autoport/probe_skin_profile.py [chemin.glb]
        (defaut : out/jak1/fr3/skin/keira-hd-lod0.glb, le mesh du pack livre)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G          # noqa: E402
import physics_c6_volumes as c6         # noqa: E402

CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
SHIPPED = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
GATE = G.INFL_GATE          # meme seuil d'appartenance que le generateur : 0.05
NBIN = 10                   # deciles d'abscisse curviligne


def parse_chain_joints(path):
    """(nom de chaine -> (liste ORDONNEE de ses joints, rootlock)), lue dans le fichier LIVRE."""
    out, cur = {}, None
    for raw in open(path, errors='ignore'):
        tok = raw.strip().split()
        if not tok or tok[0].startswith('#') or tok[0].startswith('['):
            continue
        if tok[0] == 'chain':
            kv = dict(t.split('=', 1) for t in tok[2:] if '=' in t)
            cur = tok[1]
            out[cur] = dict(joints=[], rootlock=int(kv.get('rootlock', 0)))
        elif tok[0] == 'j' and cur is not None:
            out[cur]['joints'].append(tok[1])
    return out


def arc_param(P, verts):
    """Abscisse curviligne NORMALISEE de chaque sommet sur la polyligne `P` (racine -> pointe), et
    son depassement au-dela du dernier joint.

    Rend (s, beyond) : `s` dans [0,1] (0 = racine, 1 = dernier joint), `beyond` = distance en unites
    de jeu au-dela du dernier joint, 0 si le sommet se projette dans la polyligne. Un sommet AU-DELA
    du dernier joint n'a aucun joint pour le piloter, quel que soit le reglage : c'est la meme cause
    que « 100 % de la languette etait au-dela de son unique joint »."""
    seg = P[1:] - P[:-1]
    L2 = (seg * seg).sum(axis=1)
    L2 = np.where(L2 < 1e-9, 1e-9, L2)
    cum = np.concatenate([[0.0], np.cumsum(np.sqrt(L2))])
    total = cum[-1] if cum[-1] > 1e-9 else 1.0

    best_d = np.full(len(verts), np.inf)
    best_t = np.zeros(len(verts))
    for i in range(len(seg)):
        w = verts - P[i]
        t = np.clip((w @ seg[i]) / L2[i], 0.0, 1.0)
        q = P[i] + t[:, None] * seg[i]
        d = np.linalg.norm(verts - q, axis=1)
        upd = d < best_d
        best_d[upd] = d[upd]
        best_t[upd] = cum[i] + t[upd] * np.sqrt(L2[i])

    u = seg[-1] / np.sqrt(L2[-1])
    over = (verts - P[-1]) @ u
    return best_t / total, np.where(over > 0.0, over, 0.0)


def profile(jn_list, names, idx_of, P, V, J, W, sim_extra=(), drop_root=False):
    """Le profil d'une chaine. `sim_extra` = joints declares simules EN PLUS (controle positif).

    `drop_root` — LA CORRECTION D'INSTRUMENT DU 2026-08-13, et elle change la conclusion.
    `rootlock=1` veut dire que le maillon 0 chevauche son os porteur RIGIDEMENT : la course publie
    `link0=0.0000` sur les cinq pilotages (keira-room-table.txt:461-483). Un sommet pese sur ce
    joint est donc SOUDE AU CRANE — aussi immobile que s'il etait pese sur `head`. Compter son poids
    comme « pilote », ce que font `ROOM-SKINCOV` et la premiere version de ce script, rend
    `lbang cov=0.9791` pour une meche dont 51.6 % du poids ne bouge pas d'un micron.
    Avec `drop_root`, seuls les maillons qui BOUGENT comptent."""
    jidx = [idx_of[n] for n in jn_list if n in idx_of]
    if len(jidx) < 2:
        return None
    mov = jidx[1:] if drop_root else jidx
    sim = set(mov) | {idx_of[n] for n in sim_extra if n in idx_of}

    sel = np.zeros(len(W), dtype=bool)
    for c in range(J.shape[1]):
        for j in jidx:
            sel |= (J[:, c] == j) & (W[:, c] > GATE)
    idx = np.flatnonzero(sel)
    if idx.size == 0:
        return None

    wtot = W[idx].sum(axis=1)
    wtot = np.where(wtot < 1e-9, 1.0, wtot)
    simarr = np.array(sorted(sim))
    drv = np.zeros(idx.size)
    for c in range(J.shape[1]):
        m = np.isin(J[idx, c], simarr)
        drv += np.where(m, W[idx, c], 0.0)
    drv = drv / wtot

    s, beyond = arc_param(np.asarray([P[j] for j in jidx], dtype=float),
                          np.asarray(V[idx], dtype=float))

    bins = []
    for b in range(NBIN):
        lo, hi = b / NBIN, (b + 1) / NBIN
        m = (s >= lo) & (s < hi) if b < NBIN - 1 else (s >= lo)
        bins.append((int(m.sum()), float(drv[m].mean()) if m.any() else float('nan')))

    far = (s >= 0.5) & (drv < 0.5)
    thief = {}
    if far.any():
        fi = idx[far]
        for c in range(J.shape[1]):
            for jj, ww in zip(J[fi, c], W[fi, c]):
                if int(jj) not in sim and ww > GATE:
                    thief[names[int(jj)]] = thief.get(names[int(jj)], 0.0) + float(ww)
    return dict(n=int(idx.size), bins=bins, mean=float(drv.mean()),
                far=int(far.sum()), farfrac=float(far.mean()),
                thief=sorted(thief.items(), key=lambda x: -x[1])[:3],
                beyond=int((beyond > 0).sum()), overmax=float(beyond.max()))


def main():
    rel = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    geo = c6.load_geometry(G.MODEL, glb=rel)
    if geo is None:
        raise SystemExit("mesh introuvable ou illisible : %s" % rel)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx_of = {n: i for i, n in enumerate(names)}

    chains = parse_chain_joints(CHAINS)
    print("PROFIL DE COUVERTURE DE PEAU — mesh : %s" % rel)
    print("NATURE profil le long de la meche · REPERE abscisse curviligne de la polyligne des joints")
    print("de la chaine, pose de bind, racine=0 pointe=1 · ABSENT le profil MONTE vers 1.0")
    print("%d sommets, %d joints dans le mesh, seuil d'appartenance w>%.2f\n"
          % (len(V), len(names), GATE))
    print("%-13s %5s %6s  %s" % ("chaine", "n", "moy", "  ".join("d%d" % (i + 1) for i in range(NBIN))))

    rows = []
    for cname, spec in sorted(chains.items()):
        jn_list, rl = spec['joints'], spec['rootlock']
        r = profile(jn_list, names, idx_of, P, V, J, W)
        if r is None:
            print("%-13s   -- moins de 2 joints presents dans ce mesh (%s)"
                  % (cname, ",".join(jn_list)))
            continue
        rows.append((cname, jn_list, r, rl))
        cells = "  ".join(("  .  " if np.isnan(v) else "%.2f " % v) for _n, v in r['bins'])
        print("%-13s %5d %6.3f  %s" % (cname, r['n'], r['mean'], cells))

    # -------------------------------------------------------------------------------------------
    # LA MEME MESURE, MAIS LE MAILLON VERROUILLE NE COMPTE PLUS COMME PILOTE.
    print("\nMAILLON RACINE VERROUILLE EXCLU — un joint `rootlock=1` publie link0=0.0000 sur les cinq")
    print("pilotages : la peau qu'il porte est SOUDEE au crane, pas pilotee.")
    print("%-13s %5s %6s  %s" % ("chaine", "n", "moy", "  ".join("d%d" % (i + 1) for i in range(NBIN))))
    movrows = []
    for cname, jn_list, r, rl in rows:
        if not rl:
            continue
        r2 = profile(jn_list, names, idx_of, P, V, J, W, drop_root=True)
        if r2 is None:
            continue
        movrows.append((cname, r, r2))
        cells = "  ".join(("  .  " if np.isnan(v) else "%.2f " % v) for _n, v in r2['bins'])
        print("%-13s %5d %6.3f  %s   (etait %.3f)" % (cname, r2['n'], r2['mean'], cells, r['mean']))
    if movrows:
        print("\n%-13s %9s %9s %9s   %s"
              % ("chaine", "publie", "reel", "ecart", "sommets a >=90 % sur la racine"))
        for cname, r, r2 in sorted(movrows, key=lambda x: x[1]['mean'] - x[2]['mean'], reverse=True):
            welded = sum(1 for _n, v in r2['bins'] if not np.isnan(v) and v < 0.10)
            print("%-13s %9.4f %9.4f %+9.4f   %d decile(s) sous 10 %% de pilotage"
                  % (cname, r['mean'], r2['mean'], r2['mean'] - r['mean'], welded))

    print("\nSOMMETS PILOTES A MOINS DE 50 %% AU-DELA DE LA MI-MECHE — le defaut decrit par l'owner")
    print("%-13s %6s %7s   %s" % ("chaine", "n", "part", "qui detient le poids"))
    any_far = False
    for cname, _jl, r, _rl in sorted(rows, key=lambda x: -x[2]["farfrac"]):
        if r['far'] == 0:
            continue
        any_far = True
        who = " · ".join("%s %.0f" % (a, b) for a, b in r['thief'])
        print("%-13s %6d %6.1f%%   %s" % (cname, r['far'], 100 * r['farfrac'], who))
    if not any_far:
        print("  (aucune)")

    print("\nGEOMETRIE AU-DELA DU DERNIER JOINT — aucun joint ne peut la piloter, a tout reglage")
    any_beyond = False
    for cname, _jl, r, _rl in sorted(rows, key=lambda x: -x[2]["overmax"]):
        if r['beyond'] == 0:
            continue
        any_beyond = True
        print("%-13s %6d sommets   depassement max %7.1f u = %5.1f cm"
              % (cname, r['beyond'], r['overmax'], 100 * r['overmax'] / G.UNITS))
    if not any_beyond:
        print("  (aucune)")

    # -------------------------------------------------------------------------------------------
    # CONTROLE POSITIF — il doit TIRER, sinon rien de ce qui precede n'a de valeur.
    print("\nCONTROLE POSITIF : le voleur declare simule. La mesure doit MONTER.")
    print("%-13s %8s %8s %9s   %s" % ("chaine", "avant", "apres", "delta", "voleur injecte"))
    fired = tested = 0
    for cname, jn_list, r, _rl in rows:
        if not r['thief']:
            continue
        tested += 1
        extra = [r['thief'][0][0]]
        r2 = profile(jn_list, names, idx_of, P, V, J, W, sim_extra=extra)
        if r2 is None:
            continue
        d = r2['mean'] - r['mean']
        if d > 0.01:
            fired += 1
        print("%-13s %8.4f %8.4f %+9.4f   +%s" % (cname, r['mean'], r2['mean'], d, extra[0]))
    print("\nCONTROLE: %d chaine(s) sur %d testees ont vu la mesure MONTER." % (fired, tested))
    if tested and fired == 0:
        print("  ECHEC DU CONTROLE : la mesure ne reagit pas a l'injection, tout le fichier est nul.")


if __name__ == '__main__':
    main()
