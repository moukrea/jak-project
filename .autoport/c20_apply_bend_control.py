#!/usr/bin/env python3
"""c20_apply_bend_control.py — pose (ou retire) la BUTEE D'ANGLE DE CONTROLE sur la poitrine.

Phase Grecharged-secondary-motion, branche physics-keira-clean. Keira, poitrine seule.
DIRECTIVES vee00ab7404

CE QUE C'EST, ET CE QUE CE N'EST PAS.
C'est un CONTROLE d'experience, pas une correction a livrer. L'owner a exclu l'attenuation d'angle
sur les seins (2026-08-11 22:35, « c'est juste sur les meches, pas le reste, encore moins les
seins »). Ce script existe pour repondre a UNE question et rien d'autre : le bloquant du 2e os
est-il la PRIMITIVE de collision (verdict du cycle 19) ou l'excursion NON BORNEE du maillon
distal ? Il est applique, mesure, puis RETIRE — et le fichier livre est verifie par md5.

LA VALEUR N'EST PAS CHOISIE, ELLE EST DERIVEE.
    §22 HardMaxCOMDisplacement = 0.40 * B0, B0 = 602 u (la CHAIR, §6)  ->  240.8 u
    corde d'un maillon de longueur L flechi de theta : 2*L*sin(theta/2)
    theta = 2 * asin( 240.8 / (2*L) ),  L = la longueur d'os du maillon DISTAL relevee par le
    moteur lui-meme (`bones_m` du tableau de la course), convertie en unites (4096 u = 1 m).
Elle varie donc par chaine (regle 7) et sort de la geometrie, jamais d'un ajustement sur le
resultat (`never-fit-a-parameter-to-the-instrument`).

`phys-bend-chain` (jak-hd-physics.gc:1404) l'applique par `phys-softmin` : transition douce,
jamais un ecretage — c'est ce que l'owner avait exige pour les meches.
"""
import argparse
import hashlib
import math
import re
import sys

CHAINS = 'recharged_assets/physics_chains.txt'
B0_U = 602.0          # SPEC 6 : la CHAIR, pas l'os (directive 2026-08-14 09:45)
CAP = 0.40            # SPEC 22 : HardMaxCOMDisplacement
U_PER_M = 4096.0


def md5(p):
    return hashlib.md5(open(p, 'rb').read()).hexdigest()


def theta_deg(bone_m):
    """Angle dont la corde vaut exactement le plafond §22, pour un os de `bone_m` metres."""
    half = (CAP * B0_U) / (2.0 * bone_m * U_PER_M)
    if half >= 1.0:
        return None                      # l'os est trop court : le plafond est inatteignable
    return 2.0 * math.degrees(math.asin(half))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--distal-bone', action='append', default=[], metavar='CHAIN=METRES',
                    help='longueur d os du maillon DISTAL, relevee par le moteur (bones_m)')
    ap.add_argument('--remove', action='store_true', help='retire toute butee posee par ce script')
    ap.add_argument('--deg', action='append', default=[], metavar='CHAIN=DEGRES',
                    help='second point de mesure : angle impose directement, quand il est derive '
                         'd une autre reference que la §22 (p.ex. le point de fonctionnement '
                         'mesure de l organe a UN os). La derivation doit etre ecrite dans le '
                         'rapport, ce script ne la devine pas.')
    args = ap.parse_args()

    src = open(CHAINS).read()
    before = md5(CHAINS)
    out, touched = [], []

    for line in src.splitlines(True):
        m = re.match(r'^chain (chestL|chestR) ', line)
        if not m:
            out.append(line)
            continue
        name = m.group(1)
        # on retire TOUJOURS une butee precedente avant d'en poser une : sinon deux passes
        # laisseraient deux `maxangle=` sur la meme ligne et le parseur lirait le premier.
        line = re.sub(r' maxangle=[0-9.]+', '', line)
        if not args.remove:
            th, bone = None, 0.0
            for kv in args.deg:
                k, _, v = kv.partition('=')
                if k == name:
                    th = float(v)
            if th is None:
                for kv in args.distal_bone:
                    k, _, v = kv.partition('=')
                    if k == name:
                        bone = float(v)
                if not bone:
                    sys.exit(f'FAIL: ni --deg ni --distal-bone pour {name}')
                th = theta_deg(bone)
                if th is None:
                    sys.exit(f'FAIL: {name} os distal {bone} m trop court pour le plafond §22')
            # insere juste avant le commentaire de fin de ligne, sinon la cle serait commentee.
            head, sep, tail = line.partition('   #')
            line = f'{head.rstrip()} maxangle={th:.2f}{sep}{tail}'
            touched.append((name, bone, th))
        out.append(line)

    open(CHAINS, 'w').write(''.join(out))
    after = md5(CHAINS)
    if args.remove:
        print(f'butee RETIREE   md5 {before} -> {after}')
    else:
        for n, b, t in touched:
            print(f'butee POSEE     {n}  os distal {b:.4f} m ({b*U_PER_M:.1f} u)  '
                  f'-> maxangle={t:.2f} deg')
        print(f'md5 {before} -> {after}')
    for line in open(CHAINS):
        if line.startswith('chain chest'):
            print('  ' + line.rstrip())


if __name__ == '__main__':
    main()
