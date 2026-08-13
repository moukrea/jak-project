#!/usr/bin/env python3
"""PART DE MASSE PESEE PORTEE PAR CHAQUE SEGMENT LIBRE D'UNE CHAINE.

POURQUOI CET INSTRUMENT EXISTE (2026-08-13). Les DIRECTIVES du 19:40 posent la cible qui remplace
le retard de phase (retire comme artefact de fenetre) :

    « part de masse du segment le plus lourd ramenee de 60-93 % vers 35-37 %, et duree de
      ballottement dans 84-96 frames »

et c'est LA grandeur qui discrimine le bon echantillon du mauvais : les trois grosses meches que
l'owner REJETTE portent 60 a 93 % de leur masse pesee sur UN SEUL segment libre, contre 35-37 % sur
`lbang`/`rbang` qu'il APPROUVE. Un segment libre unique qui porte l'essentiel de la masse est un
BLOC par construction — il n'y a rien derriere lui pour etre en retard, et aucune valeur de raideur,
d'amortissement ou de masse ne peut y creer une propagation racine->pointe.

ELLE N'AVAIT AUCUN INSTRUMENT, et c'est le defaut que ce fichier corrige. Le chiffre circulait dans
des COMMENTAIRES (`.autoport/physics_keira_gen2.py:266-283` — a l'interieur du litteral
`EXPECTED_GROUPS`, donc du texte pur ; idem `.autoport/physics_inject_joints.py:24-28` et
`recharged_assets/keira-hd-inject-joints.txt:42-52`) et dans les rapports de cycle, mesure a la main
a chaque fois. Un commentaire n'est pas une preuve (DIRECTIVES regle 0) et une grandeur qu'on
remesure a la main derive : elle est ici, avec sa definition, reproductible.

LES TROIS QUESTIONS DE LA SPEC 7, repondues AVANT de publier le nombre :

  NATURE  : une REPARTITION de masse le long de la chaine — une part, sans dimension. Ni une
            amplitude, ni une frequence, ni une forme de reponse. Le defaut decrit (« ca part en
            bloc ») est l'ABSENCE de degre de liberte, et c'est la concentration de la masse sur un
            seul segment qui la mesure. Un scalaire par chaine suffit ICI parce que la grandeur EST
            un maximum sur les segments — mais on publie AUSSI la repartition complete, sans quoi on
            ne saurait pas OU la masse est concentree.
  REPERE  : le JOINT. La masse d'un segment est le poids de peau brut que son joint detient, somme
            sur tous les sommets. Pas de repere monde, pas de deplacement : on mesure une
            APPARTENANCE, pas un mouvement. Le maillon 0 est exclu du numerateur ET du denominateur
            parce que `rootlock=1` le verrouille (`goal_src/jak1/pc/jak-hd-physics.gc:1540`, `1740`,
            `1777`, `2061`, `2332` sautent tous `l < rlk`) : compter la masse d'un maillon epingle
            comme de la masse mobile compterait un immobile comme moteur.
  ABSENT  : `lbang`/`rbang`, mesurees sur LE MEME mesh dans LA MEME course. L'owner approuve les
            meches fines et rejette les grosses : le bon et le mauvais echantillon sont cote a cote,
            donc la cible est une valeur MESUREE et jamais un nombre choisi. C'est le controle
            apparie que les DIRECTIVES imposent depuis le 14:45.

POURQUOI LE POIDS BRUT ET PAS UNE MAJORITE. Deux definitions voisines ont ete essayees et elles ne
rendent PAS la meme chose (mesure sur le mesh livre, `lbang`) : majorite `w>0.5` ponderee par la
masse donne 11.4/17.8/70.8, et le simple COMPTAGE de sommets majoritaires donne 16.4/18.2/65.5, la
ou le poids brut donne 36.3/25.8/37.8. Un sommet partage entre deux maillons appartient un peu aux
deux — c'est exactement ce qu'un solveur voit — et un seuil de majorite le donnerait en entier au
plus fort, ce qui EXAGERE la concentration qu'on cherche a mesurer. On somme donc le poids tel quel.

CE QUE CE SCRIPT NE FAIT PAS : il ne genere rien, n'ecrit rien, ne regenere aucune chaine. Il lit
`recharged_assets/physics_chains.txt` (le fichier LIVRE) et un ou deux GLB.

Usage:
    python3 .autoport/probe_chain_mass_share.py [<glb-apres>] [<glb-avant>]

Sans argument il lit le mesh livre. Avec deux, il publie la course AVANT -> APRES.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
CHAINS_FILE = os.path.join(ROOT, 'recharged_assets', 'physics_chains.txt')
SHIPPED = os.path.join(ROOT, 'out', 'jak1', 'fr3', 'skin', 'keira-hd-lod0.glb')

# Les chaines que l'owner a nommement APPROUVEES (« les meches fines sont vraiment pas mal »).
# Elles ne sont pas une cible : elles sont la LIGNE DE BASE contre laquelle les autres se lisent.
APPROVED = ('lbang', 'rbang')


def parse_chains(path):
    """(nom -> (joints, rootlock)) depuis le fichier LIVRE, jamais une liste ecrite a la main.

    Meme parseur que `probe_skin_ownership.py:parse_chains`, augmente du `rootlock=` porte par la
    ligne `chain` : sans lui on ne sait pas quel maillon est epingle, donc lesquels sont LIBRES.
    """
    out, cur = {}, None
    for ln in open(path, errors='ignore'):
        ln = ln.split('#', 1)[0].strip()
        if ln.startswith('chain '):
            f = ln.split()
            cur = f[1]
            kv = dict(x.split('=', 1) for x in f[2:] if '=' in x)
            out[cur] = ([], int(kv.get('rootlock', '0')))
        elif ln.startswith('j ') and cur:
            out[cur][0].append(ln.split()[1])
        elif not ln:
            cur = None
    return {k: v for k, v in out.items() if v[0]}


def joint_weight(path):
    """Poids de peau BRUT par joint, somme sur tous les sommets. -> (dict nom->masse, J, W, idx)."""
    js, bufs = read_glb(path)
    binc = consolidate_buffers(js, bufs)
    names, _, _ = skin_info(js, binc)
    idx = {n: i for i, n in enumerate(names)}

    # DE-DOUBLONNAGE PAR TRIPLET D'ACCESSEURS. Les primitives d'un mesh cuit partagent le meme jeu
    # de sommets (28 primitives, un seul triplet sur le mesh livre) : sommer par primitive
    # compterait chaque sommet 28 fois. Le motif est celui de `probe_hair_joint_deficit.py:70-84`,
    # qui existe precisement parce que le donneur comptait 28 fois chaque sommet.
    seen, tot = set(), {}
    for mesh in js.get('meshes', []):
        for pr in mesh.get('primitives', []):
            at = pr['attributes']
            key = (at['JOINTS_0'], at['WEIGHTS_0'])
            if key in seen:
                continue
            seen.add(key)
            J = read_accessor(js, binc, at['JOINTS_0'])
            W = read_accessor(js, binc, at['WEIGHTS_0']).astype(np.float64)
            # garde-fou de normalisation (motif probe_hair_joint_deficit.py:88) : sur le mesh livre
            # les lignes somment a 1.0 et il est inerte, mais un GLB brut peut porter des entiers.
            if W.max() > 1.5:
                W = W / W.max()
            for c in range(J.shape[1]):
                for ji in np.unique(J[:, c]):
                    m = J[:, c] == ji
                    tot[int(ji)] = tot.get(int(ji), 0.0) + float(W[m, c].sum())
    return {n: tot.get(i, 0.0) for n, i in idx.items()}, idx


def shares(wmap, joints, rootlock):
    """Part (%) de la masse LIBRE portee par chaque segment libre, racine->pointe."""
    n = len(joints)
    rlk = max(0, min(rootlock, n - 1))
    free = [j for j in joints[rlk:] if j in wmap]
    if not free:
        return None, None, rlk
    w = np.array([wmap[j] for j in free], dtype=np.float64)
    s = w.sum()
    if s <= 0:
        return None, None, rlk
    frac = 100.0 * w / s
    return frac, free, rlk


def report(path, label):
    chains = parse_chains(CHAINS_FILE)
    wmap, idx = joint_weight(path)
    print("MESH %s  (%s)" % (label, path))
    print("%-12s %6s   %s" % ("chaine", "pire", "repartition des segments LIBRES (%, racine->pointe)"))
    out = {}
    for cname in sorted(chains):
        joints, rlk_decl = chains[cname]
        frac, free, rlk = shares(wmap, joints, rlk_decl)
        if frac is None:
            continue
        if len(free) < 2:
            continue                       # un seul segment libre : la part vaut 100 % par
            # construction, la grandeur n'a rien a dire (cf. « zero from an EMPTY domain »)
        tag = "  <- APPROUVE" if cname in APPROVED else ""
        out[cname] = float(frac.max())
        print("%-12s %5.1f%%   %s%s" % (cname, frac.max(),
                                        "  ".join("%5.1f" % x for x in frac), tag))
    return out


def control(path):
    """CONTROLE POSITIF : on INJECTE le defaut et le compteur doit MONTER.

    Le defaut est « toute la masse sur un seul segment libre ». On le fabrique en versant la masse
    de tous les segments libres sur le plus lourd d'entre eux, et la part doit monter a 100 %. Si
    elle ne monte pas, la mesure ne lit pas ce qu'elle annonce et le reste du fichier ne vaut rien.
    """
    chains = parse_chains(CHAINS_FILE)
    wmap, _ = joint_weight(path)
    print()
    print("CONTROLE POSITIF : masse des segments libres versee sur le plus lourd. Doit MONTER.")
    print("%-12s %8s %8s %8s" % ("chaine", "avant", "arme", "delta"))
    fired = tested = 0
    for cname in sorted(chains):
        joints, rlk_decl = chains[cname]
        frac, free, rlk = shares(wmap, joints, rlk_decl)
        if frac is None or len(free) < 2:
            continue
        tested += 1
        inj = dict(wmap)
        heavy = free[int(np.argmax(frac))]
        for j in free:
            if j != heavy:
                inj[heavy] += inj[j]
                inj[j] = 0.0
        f2, _, _ = shares(inj, joints, rlk_decl)
        before, after = float(frac.max()), float(f2.max())
        if after > before + 1e-9:
            fired += 1
        print("%-12s %7.1f%% %7.1f%% %+7.1f" % (cname, before, after, after - before))
    print("CONTROLE: %d chaine(s) sur %d ont vu la mesure MONTER." % (fired, tested))
    return fired, tested


def main():
    after = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    before = sys.argv[2] if len(sys.argv) > 2 else None
    a = report(after, "APRES" if before else "LIVRE")
    if before:
        print()
        b = report(before, "AVANT")
        print()
        print("COURSE AVANT -> APRES (pire segment libre)")
        print("%-12s %8s %8s %8s" % ("chaine", "avant", "apres", "delta"))
        for c in sorted(set(a) & set(b)):
            tag = "  <- APPROUVE, doit rester identique" if c in APPROVED else ""
            print("%-12s %7.1f%% %7.1f%% %+7.1f%s" % (c, b[c], a[c], a[c] - b[c], tag))
    control(after)


if __name__ == '__main__':
    main()
