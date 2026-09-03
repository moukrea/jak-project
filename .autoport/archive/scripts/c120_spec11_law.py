#!/usr/bin/env python3
"""c120_spec11_law.py — `HangingTransientLengthMax` EST-ELLE UN BOUTON, OU LA CONSEQUENCE DE DEUX
CLES DEJA CABLEES ?

Le cycle 119 laissait cette cle comme LE DERNIER BOUTON de la file ordonnee par la directive du
2026-08-22 23:00 (« l'ordre de traitement suit les 51 cles qui DIFFERENT entre les deux presets »).
Ce script teste l'hypothese que ce n'en est pas un.

HYPOTHESE : le « transient settling peak » de §11 est le DEPASSEMENT d'un second ordre qui
s'etablit de la pose debout (echelle 1.00) vers la pose pendante (`HangingLengthScale`), au taux
d'amortissement global. Le depassement relatif d'un second ordre est exactement
`exp(-pi.z/sqrt(1-z^2))`, et le document ECRIT lui-meme cette quantite sous le nom
`FirstBounceRatio`. D'ou :

    HangingTransientLengthMax  =  1 + (HangingLengthScale - 1) x (1 + FirstBounceRatio)

Aucune valeur n'est ajustee : les trois cles sont lues telles quelles dans le document.
Le test est FALSIFIABLE — il tourne sur LES DEUX presets, et la prose de chacun donne une bande.
"""
import math, re, sys

DOC = 'SPEC-breast-softbody.md'

def bloc(txt, debut, fin):
    return txt[debut:fin]

def lire(txt, cle, depuis):
    m = re.search(r'^%s\s*=\s*([0-9.]+)' % re.escape(cle), txt[depuis:], re.M)
    return float(m.group(1)) if m else None

def main():
    txt = open(DOC, errors='ignore').read()
    # les deux presets, reperes par leur en-tete de bloc (l.466 et l.938 dans le document livre)
    i_k = txt.index('GlobalDampingRatio')
    i_m = txt.index('GlobalDampingRatio', i_k + 1)
    print("%-7s %-9s %-9s %-9s | %-9s %-9s %-9s" %
          ('preset', 'L', 'FBR', 'z', 'loi', 'ecrit', 'ecart'))
    ok = 0
    for nom, base, bande in (('KEIRA', i_k, None), ('MAIA', i_m, (1.40, 1.45))):
        z   = lire(txt, 'GlobalDampingRatio', base)
        fbr = lire(txt, 'FirstBounceRatio', base)
        L   = lire(txt, 'HangingLengthScale', base)
        M   = lire(txt, 'HangingTransientLengthMax', base)
        loi = 1.0 + (L - 1.0) * (1.0 + fbr)
        # controle : `FirstBounceRatio` est-il bien exp(-pi z / sqrt(1-z^2)) a la precision ecrite ?
        rec = math.exp(-z * math.pi / math.sqrt(1.0 - z * z))
        ecart = (loi - M) / M
        print("%-7s %-9.4f %-9.4f %-9.4f | %-9.4f %-9.4f %+8.3f %%   (FBR recalcule %.4f -> %.2f)"
              % (nom, L, fbr, z, loi, M, 100.0 * ecart, rec, round(rec, 2)))
        if round(loi, 2) == M:
            print("        -> l'arrondi de la loi a la precision du document EST la valeur ecrite")
            ok += 1
        elif bande and bande[0] <= loi <= bande[1]:
            print("        -> la loi tombe DANS la plage que la prose de ce preset ecrit (%.2f-%.2f) ;"
                  " la cle est epinglee au HAUT de cette plage" % bande)
            ok += 1
        else:
            print("        -> HORS : l'hypothese est REFUTEE sur ce preset")
    print()
    print("VERDICT : %d preset(s) sur 2 soutiennent la loi." % ok)
    print("RESERVE, ECRITE PARCE QU'ELLE COMPTE : le critere `P-IDENTITE` du cycle 119 exige")
    print("  l'exactitude sur LES DEUX presets. Elle n'est EXACTE que sur Keira ; sur Maia elle")
    print("  tombe dans la bande ECRITE mais pas sur la valeur epinglee. La cle n'est donc PAS")
    print("  classee `REDONDANTE` — elle est classee : « pas un bouton, une consequence, et la")
    print("  moitie Maia est publiee avec son ecart ».")

if __name__ == '__main__':
    main()
