#!/usr/bin/env python3
# scripts/shell/hd_check_joint_tables.py — LES TABLES DE RETARGETING COMPILEES DANS LE JEU DOIVENT
# ETRE CELLES QUE LA CHAINE VIENT DE FABRIQUER.
#
# POURQUOI (Gbuild-from-scratch, owner 2026-08-29) ----------------------------------------------
# Le rig HD d'un personnage existe en DEUX exemplaires qui doivent dire la meme chose :
#   * `recharged_assets/hd_anim/<char>-k2e.gc-snippet`, REGENERE a chaque bake depuis le donneur
#     (scripts/shell/retarget_fill_table.py) — et gitignore, donc invisible a `git status` ;
#   * les memes `(define *<char>-...*)` recopies dans `goal_src/jak1/pc/jak-hd.gc`, qui est SUIVI
#     par git et COMPILE dans le jeu. C'est cette copie-la que le moteur lit.
# La recopie se fait par `.autoport/hd_splice_joint_tables.py`, appele UNIQUEMENT par des scripts
# de cycle (.autoport/c20_*, c23_*, c24_*) qui n'ont eux-memes aucun appelant. Autrement dit : le
# rig est refabrique a chaque build, sa transcription GOAL ne l'est pas, et RIEN ne comparait les
# deux. Un changement de rig — un joint retire par `<char>-drop-joints.txt`, un joint injecte par
# `<char>-inject-joints.txt` — produit alors un maillage a N joints et une boucle de retargeting
# bornee sur l'ancien N. Ca s'est deja paye : le 2026-08-13 keira-hd est passee a 100 joints
# partout SAUF dans `*hd-joint-counts*`, les joints 95..99 n'ont jamais ete ecrits, leurs matrices
# d'os sont restees non initialisees et le moteur publiait `PHYSBONE len=NaN`, `amp=0.0000`.
# `.autoport/hd_check_joint_counts.py` couvre la coherence INTERNE du .gc (les tailles de tableaux
# contre `*hd-joint-counts*`). Il ne pouvait pas voir ce cas-ci : un .gc parfaitement coherent avec
# lui-meme, et perime par rapport au rig. C'est la comparaison que personne ne faisait.
#
# CRITERE : chaque bloc `(define *…*)` du snippet fraichement produit doit apparaitre OCTET POUR
# OCTET dans goal_src/jak1/pc/jak-hd.gc. Le splice recopie le bloc verbatim, donc l'egalite exacte
# est la bonne exigence — pas une comparaison « a peu pres ».
#
# Sortie : une ligne par personnage, puis PASS/FAIL. exit 1 sur toute divergence.
import argparse
import glob
import os
import re
import sys

GC = 'goal_src/jak1/pc/jak-hd.gc'
SNIPPET_GLOB = 'recharged_assets/hd_anim/*-k2e.gc-snippet'


def blocks_of(text):
    """Les blocs `(define *nom* …)` du snippet, ancres en debut de ligne.

    L'ancre `^` compte : un `(define …)` en COMMENTAIRE n'est pas une definition, et un controle
    aveugle au commentaire est un faux vert sur exactement le mode de panne qu'il couvre (deja
    paye le 2026-08-17 sur hd_check_joint_counts.py).
    """
    out = []
    for m in re.finditer(r'^\(define (\*[^\s*]+\*)[^\n]*\n(?:[^\n]*\n)*?[^\n]*\)\)\n', text, re.M):
        out.append((m.group(1), m.group(0)))
    return out


def main():
    # --gc / --snippets existent pour le CONTROLE POSITIF : un garde-fou qu'on n'a jamais vu
    # echouer n'est pas un garde-fou. Ils permettent de le pointer sur une copie perturbee et de
    # verifier qu'il TIRE, sans toucher a l'arbre. Le bake les laisse a leur defaut.
    ap = argparse.ArgumentParser()
    ap.add_argument('--gc', default=GC)
    ap.add_argument('--snippets', default=SNIPPET_GLOB)
    args = ap.parse_args()
    globals()['GC'] = args.gc
    globals()['SNIPPET_GLOB'] = args.snippets
    if not os.path.exists(GC):
        print(f'[hd-joint-tables FAIL] {GC} absent')
        return 1
    gc = open(GC, errors='ignore').read()
    snippets = sorted(glob.glob(SNIPPET_GLOB))
    if not snippets:
        print(f'[hd-joint-tables FAIL] aucun snippet sous {SNIPPET_GLOB} — la chaine n a fabrique '
              'aucun rig, il n y a rien a comparer (et un controle sans sujet passerait a vide)')
        return 1
    bad, n_blocks = [], 0
    for sn in snippets:
        char = os.path.basename(sn).replace('-k2e.gc-snippet', '')
        blks = blocks_of(open(sn, errors='ignore').read())
        if not blks:
            bad.append(f'{char}: le snippet ne contient AUCUN bloc (define *…*)')
            print(f'!! {char:<10} 0 bloc dans {sn}')
            continue
        missing = [name for name, body in blks if body not in gc]
        n_blocks += len(blks)
        flag = 'OK ' if not missing else '!! '
        print(f'{flag}{char:<10} {len(blks)} bloc(s) du rig fraichement produit, '
              f'{len(blks) - len(missing)} present(s) au bit dans {GC}')
        if missing:
            bad.append(f'{char}: {", ".join(missing)} differe(nt) de la copie compilee')
    if bad:
        print('\n[hd-joint-tables FAIL]')
        for b in bad:
            print('  ' + b)
        print(f'  Le rig que la chaine vient de fabriquer et la table que {GC} compile ne disent')
        print('  PAS la meme chose. Le moteur retargette avec la table COMPILEE : la difference')
        print('  est silencieuse a l ecran et se lit en joints non ecrits (PHYSBONE len=NaN).')
        print('  Recopie : python3 .autoport/hd_splice_joint_tables.py --snippet '
              '<char>-k2e.gc-snippet --gc goal_src/jak1/pc/jak-hd.gc --entry <n> --apply')
        print('  puis relance le bake, et n oublie pas .autoport/hd_check_joint_counts.py.')
        return 1
    print(f'\n[hd-joint-tables PASS] {len(snippets)} personnage(s), {n_blocks} bloc(s) — la table '
          f'compilee dans {GC} est celle du rig produit par cette course')
    return 0


if __name__ == '__main__':
    sys.exit(main())
