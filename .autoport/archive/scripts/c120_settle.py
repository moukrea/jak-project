#!/usr/bin/env python3
"""c120_settle.py — LE DEPASSEMENT D'ETABLISSEMENT DU CANAL DE FORME, PAR PAS D'ORIENTATION.

NATURE   : un RAPPORT sans dimension, rho = (pic - tenu_i) / (tenu_i - tenu_{i-1}).
           Ce n'est ni une amplitude ni un maximum : c'est la fraction du PAS d'echelle que le
           canal depasse avant de se poser. C'est la seule forme comparable d'une cellule a
           l'autre, parce que les pas n'ont pas la meme taille.
REPERE   : le triedre de §7 (les trois echelles COMMANDEES a la racine).
FENETRE  : `pic` = les 60 frames d'ETABLISSEMENT de la cellule i (PHYSORI5) ; `tenu` = les 30
           frames de MESURE de la meme cellule (PHYSORI2). Les deux sont emis au meme endroit du
           meme balayage, donc comparables sans hypothese.
LECTURE HORS DEFAUT (canal SANS memoire) : rho = 0 — une fonction sans etat ne depasse pas.
CIBLE    : `FirstBounceRatio` = 0.31 (Keira, l.467), qui est aussi exp(-pi.z/sqrt(1-z^2)) pour
           z = `GlobalDampingRatio` = 0.35.
STATISTIQUE PUBLIEE : la MEDIANE de la population, jamais un maximum
           (`a-maximum-is-not-a-linear-functional`).
GARDE DE VACUITE : un pas dont |tenu_i - tenu_{i-1}| est trop petit ne peut pas porter un
           rapport — il est EXCLU et COMPTE, jamais moyenne.
"""
import re, sys, statistics

SEUIL_PAS = 0.01     # taille minimale du pas d'echelle pour que le rapport ait un sens

def lire(path):
    peak, held = {}, {}
    for ln in open(path, errors='ignore'):
        m = re.match(r'^PHYSORI5 c=(\d+) i=(\d+) sxm=(\S+) sym=(\S+) szm=(\S+)', ln)
        if m:
            c, i = int(m.group(1)), int(m.group(2))
            peak.setdefault((c, i), (float(m.group(3)), float(m.group(4)), float(m.group(5))))
            continue
        m = re.match(r'^PHYSORI2 c=(\d+) i=(\d+) sx=(\S+) sy=(\S+) sz=(\S+) det=(\S+)', ln)
        if m:
            c, i = int(m.group(1)), int(m.group(2))
            held.setdefault((c, i), (float(m.group(3)), float(m.group(4)), float(m.group(5)),
                                     float(m.group(6))))
    return peak, held

def main(path, tag):
    peak, held = lire(path)
    if not peak:
        print("%s: aucune ligne PHYSORI5 — rien a dire (instrument absent, PAS un zero)" % tag)
        return
    noms = ('sx', 'sy', 'sz')
    print("== %s ==  %d cellules PHYSORI5, %d cellules PHYSORI2" % (tag, len(peak), len(held)))
    print("   c  i  axe   tenu_i-1     tenu_i        pas        pic       rho")
    rhos, vac = [], 0
    for (c, i) in sorted(peak):
        if i == 0 or (c, i) not in held or (c, i - 1) not in held:
            continue
        for a in range(3):
            t1, t0 = held[(c, i)][a], held[(c, i - 1)][a]
            pas = t1 - t0
            pk = peak[(c, i)][a]
            if abs(pas) < SEUIL_PAS:
                vac += 1
                continue
            if pas < 0:          # echelle qui DIMINUE : le cliquet ne porte que le MAXIMUM
                vac += 1         # (reserve ecrite dans l'emetteur) -> exclu, pas moyenne
                continue
            rho = (pk - t1) / pas
            rhos.append(rho)
            print("  %2d %2d  %s  %9.4f  %9.4f  %9.4f  %9.4f  %8.4f"
                  % (c, i, noms[a], t0, t1, pas, pk, rho))
    if rhos:
        print("  -> n=%d  mediane rho = %.4f   (min %.4f  max %.4f)   exclus (pas trop petit ou"
              " echelle decroissante) : %d" % (len(rhos), statistics.median(rhos), min(rhos),
                                               max(rhos), vac))
    else:
        print("  -> aucun pas exploitable ; exclus : %d" % vac)
    # LA DERIVATION DEBOUT->PRONE, PUBLIEE COMME DERIVATION ET JAMAIS COMME MESURE.
    for c in (0, 1):
        if (c, 6) in held and rhos:
            tp = held[(c, 6)][2]
            r = statistics.median(rhos)
            print("  DERIVATION (pas non joue par le balayage) c=%d : pic(debout->prone) ="
                  " %.4f + %.4f x (%.4f - 1) = %.4f   contre HangingTransientLengthMax = 1.30"
                  % (c, tp, r, tp, tp + r * (tp - 1.0)))

if __name__ == '__main__':
    for p in sys.argv[1:]:
        main(p, p.split('/')[-1])
        print()
