#!/usr/bin/env python3
"""probe_body_volume_inflation.py — UN VOLUME DE CORPS EST-IL GROSSI PAR LA CHAINE QU'IL DOIT REPOUSSER ?

Ce script ne genere rien et ne modifie rien.

LA QUESTION, ET POURQUOI ELLE SE POSE MAINTENANT. Le moteur tolere qu'un maillon repose DEJA dans un
volume : `floor0` est la profondeur du maillon a sa POSE D'AUTEUR, et seul ce qui va PLUS PROFOND est
repousse (`jak-hd-physics.gc:1880-1884`, `:1978-1979`, `:2020`). Un volume qui deborde de `d` sur un
maillon lui accorde donc `d` de LAISSEZ-PASSER : sur cette profondeur, le volume ne protege rien.

Mesure du 2026-08-13 (`probe_rest_containment.py`, sur le fichier LIVRE) : 31 couples (maillon,
volume) etrangers se recouvrent au repos, les pires etant

    backhair/backHair2 <- head->neck            -688 u = -16.8 cm
    pantflapR          <- Rankle->Rknee         -620 u
    topstrapL          <- Lshoulder->chest      -322 u

L'HYPOTHESE QUI A FAIT ECRIRE CE SCRIPT — ET QUI EST FAUSSE. `head` porte 27 % du poids de peau de
`backhair` (`ROOM-SKINCOV: chain=backhair cov=0.7259 lost=head 100%`), et le rayon de la capsule
`head->neck` est ajuste sur les sommets de `head`. Le volume cense repousser les cheveux serait donc
ajuste SUR LES CHEVEUX — circulaire, et ca expliquerait que trois cycles de reglage de rayon n'aient
rien change.

RESULTAT MESURE (2026-08-13) : NON. En retirant tout sommet qu'un joint de chaine influence, le bout
`head` passe de 915 a 922 u — il GROSSIT de 7 u. Les sommets de cheveux sont plus PRES de l'axe que
la moyenne de la tete : ils ne gonflent pas ce volume, ils l'amincissent legerement. Les 915 u sont
de la vraie geometrie de tete. Cette piste est donc FERMEE par la mesure, et le prochain cycle n'a
pas a la rouvrir.

Ce que la meme mesure montre en revanche : les bouts `chest` sont grossis de 7 a 10 % par la
geometrie de poitrine et de bretelle (769->694, 782->712, 671->621), et 1581 des 1699 sommets de
`head` n'ont AUCUNE influence de chaine — la masse de cheveux est majoritairement soudee a `head`,
ce qui est le defaut `hair-skinning` que l'owner decrit, pas un probleme de volume.

CE QUE CE SCRIPT MESURE. Pour chaque extremite de capsule de corps, le rayon ajuste par la MEME
fonction que le generateur (`iq_perp_radius`, moyenne inter-quartile de la distance perpendiculaire
a l'axe de l'os), calcule trois fois :
    (a) sur TOUS les sommets du joint       -> ce qui est livre aujourd'hui
    (b) sommets dont le joint DOMINANT n'est pas une chaine   (filtre FAIBLE, garde pour memoire)
    (c) sommets qu'AUCUN joint de chaine n'influence au-dela de INFL_GATE  (le vrai filtre)
L'ecart (a)-(c) est la part du volume qui vient de la geometrie qu'il doit repousser.

LES TROIS QUESTIONS DE LA SPEC 7 :
  NATURE  : une EPAISSEUR (longueur, unites de jeu), pas une amplitude ni une variance. Le defaut
            vise est statique : la taille d'un volume dans la pose de bind.
  REPERE  : l'espace bind du joint, distance PERPENDICULAIRE a son propre axe d'os — exactement le
            repere du generateur, pour que (a) soit comparable au nombre livre.
  ABSENT  : si aucun sommet de chaine ne pese sur ce joint, (a) et (b) sont EGAUX et l'ecart est 0.
            Les joints de membres (Lknee, Rankle...) doivent donc lire 0 : ce sont eux le controle
            negatif interne, et ils sont publies pour qu'on le verifie.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402
from probe_rest_containment import parse_chains, CHAINS  # noqa: E402

UNITS = G.UNITS


def iq_perp_radius_masked(geo, j, a_world, b_world, thr, keep):
    """`iq_perp_radius` du generateur, mais restreint aux sommets `keep` (masque booleen global)."""
    _n, _w, idx = G.influence(geo, j, thr)
    idx = np.array([i for i in idx if keep[i]], dtype=int)
    if len(idx) == 0:
        return None, 0
    ibm = geo['ibms'][j]
    pts = G.to_bone_local(ibm, geo['V'][idx])
    a = G.to_bone_local(ibm, a_world[None, :])[0]
    b = G.to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    u = axis / n
    rel = pts - a
    rel = rel - np.outer(rel @ u, u)
    d = np.linalg.norm(rel, axis=1)
    lo, hi = np.percentile(d, [G.IQ_LO, G.IQ_HI])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    return float(inner.mean()), len(idx)


def main():
    names, parent, _ = G.load_rig(os.path.join(REPO, G.RIG_REL))
    geo = G.load_mesh(G.MODEL)
    P, J, W = geo['P'], geo['J'], geo['W']
    idx = {n: k for k, n in enumerate(geo['names'])}

    chains, capsules, _spheres = parse_chains(CHAINS)
    chain_joints = set()
    for c in chains:
        chain_joints.update(c['joints'])
    chain_ids = {idx[n] for n in chain_joints if n in idx}

    # DEUX FILTRES, PARCE QU'UN SEUL AURAIT MENTI.
    #  (b) joint DOMINANT : un sommet est « de chaine » si son poids le plus fort est sur une chaine.
    #      Ce filtre est FAIBLE : un sommet a 0.6 sur `head` et 0.4 sur `backHair1` est de la
    #      geometrie de MECHE, et ce filtre le compte comme du corps. Il a d'abord rendu 0 partout,
    #      ce qui se lisait comme « aucun volume n'est grossi par une chaine » — a tort.
    #  (c) TOUTE influence : un sommet est « de chaine » des qu'un joint de chaine porte plus de
    #      INFL_GATE (le seuil du generateur lui-meme pour dire qu'un joint « a de la geometrie »).
    #      C'est le filtre qui repond vraiment a la question posee.
    dom = J[np.arange(len(J)), np.argmax(W, axis=1)]
    keep = ~np.isin(dom, list(chain_ids))     # True = ce sommet est du CORPS, pas d'une chaine
    anych = np.zeros(len(J), dtype=bool)
    for c in range(J.shape[1]):
        anych |= np.isin(J[:, c], list(chain_ids)) & (W[:, c] > G.INFL_GATE)
    keep2 = ~anych

    out = []
    def say(s=''):
        out.append(s)
        print(s)

    say(f"CHAINES SIMULEES: {len(chain_joints)} joints. Sommets du mesh: {len(J)} — "
        f"{int((~keep).sum())} appartiennent a une chaine, {int(keep.sum())} au corps.")
    say()
    say("INFLATION: rayon ajuste par la fonction DU GENERATEUR, sur tous les sommets du joint (a)")
    say("           puis sur ses seuls sommets de CORPS (b). L'ecart est la part du volume qui")
    say("           vient de la geometrie que ce volume doit repousser.")
    say()
    say(f"{'capsule':<26}{'bout':<12}{'livre':>7}{'(a) tous':>10}{'(b) corps':>11}"
        f"{'(c) sans chaine':>16}{'ecart':>8}{'%':>7}   n a/b/c")
    say('-' * 100)

    rows = []
    for cp in capsules:
        for end, other in ((cp['a'], cp['b']), (cp['b'], cp['a'])):
            if end not in idx or other not in idx:
                continue
            j = idx[end]
            if j in chain_ids:
                continue                      # volume de chaine: hors sujet ici
            a, b = P[j], P[idx[other]]
            for thr in G.FIT_STEPS:
                ra, na = G.iq_perp_radius(geo, j, a, b, thr)
                if ra is not None and na >= G.FIT_MIN_VERTS:
                    break
            if ra is None:
                continue
            rb, nb = iq_perp_radius_masked(geo, j, a, b, thr, keep)
            rc, ncv = iq_perp_radius_masked(geo, j, a, b, thr, keep2)
            shipped = cp['ra'] if end == cp['a'] else cp['rb']
            if rb is None or rc is None:
                say(f"{cp['a'] + '->' + cp['b']:<26}{end:<12}{shipped:>7.0f}{ra:>10.0f}"
                    f"{'—':>11}{'':>8}{'':>7}   {na}/0  (aucun sommet de corps)")
                continue
            rows.append((f"{cp['a']}->{cp['b']}", end, shipped, ra, rb, rc, ra - rc, na, nb, ncv))

    for (vol, end, shipped, ra, rb, rc, d, na, nb, ncv) in sorted(rows, key=lambda r: -r[6]):
        pct = (100.0 * d / ra) if ra > 0 else 0.0
        say(f"{vol:<26}{end:<12}{shipped:>7.0f}{ra:>10.0f}{rb:>11.0f}{rc:>11.0f}"
            f"{d:>8.0f}{pct:>6.1f}%   {na}/{nb}/{ncv}")

    say()
    big = [r for r in rows if r[6] > 20.0]
    say(f"BILAN: {len(big)} bout(s) de capsule sur {len(rows)} sont grossis de plus de 20 u par la")
    say("       geometrie d'une chaine simulee.")
    zero = [r for r in rows if abs(r[6]) < 1e-6]
    say(f"CONTROLE NEGATIF INTERNE: {len(zero)} bout(s) lisent un ecart EXACTEMENT nul — ce sont les")
    say("       joints sur lesquels aucune chaine ne pese. Une mesure qui bougerait partout serait")
    say("       un artefact de la methode, pas une propriete du rig.")
    if zero:
        say("       " + ' · '.join(f"{r[0]}@{r[1]}" for r in zero[:12]))

    dest = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion',
                        'body-volume-inflation.txt')
    open(dest, 'w').write('\n'.join(out) + '\n')
    print(f"\n[ecrit] {os.path.relpath(dest, REPO)}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
