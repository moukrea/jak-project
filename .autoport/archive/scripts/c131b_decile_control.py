#!/usr/bin/env python3
"""c131b_decile_control.py — LE CONTROLE DE REPRODUCTION DU PORTAGE DE LA LECTURE DE DECILES.

POURQUOI CE FICHIER EXISTE. Le cycle 131 a etabli que la ligne de verdict de la clause PORTEUSE de
§11 (« Root-to-apex length ») publiait l'ECART-TYPE PONDERE, que le cycle 126 a REFUTE, au lieu de
la distance racine->apex entre centroides de DECILE, qu'il a ARBITREE. Le portage de cette lecture
dans la chaine du tableau (`c124_delivered_shape.py`) ne vaut RIEN s'il ne retrouve pas les quatre
nombres deja publies : un instrument qui ne reproduit pas son point de depart ne mesure rien.

NATURE   : un RAPPORT sans dimension (longueur a la cellule prone / longueur a la pose debout).
REPERE   : aucun pour le rapport ; les deux longueurs sont des DISTANCES mesurees en MONDE, donc
           la grandeur est invariante par rotation — c'est ce que §11 nomme, et c'est ce qui la
           distingue d'une etendue le long d'un axe fixe.
HORS DEF.: 1,0000 (la cellule i=0 divisee par elle-meme).

REFERENCE : `1.3363 / 1.2734 / 1.3183 / 1.3116` (chestL w>0.00, chestL w>=0.25, chestR w>0.00,
chestR w>=0.25), publiees dans `c128-report.md` section 7 et reproduites independamment par
`.autoport/c131_anchor_dof.py` (SECTION 1) a 0,003 %. SEUIL DECLARE : 1 %.
"""
import sys, os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, '.autoport'))
LOG = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log')
REF = [('chestL', 'w>0.00', 1.3363), ('chestL', 'w>=0.25', 1.2734),
       ('chestR', 'w>0.00', 1.3183), ('chestR', 'w>=0.25', 1.3116)]
SEUIL = 1.0

def main():
    import c124_delivered_shape as shape
    if not os.path.exists(LOG):
        print('C131B: SUSPENDU — trace absente : %s' % LOG)
        return 1
    _lines, rows, rc = shape.measure(open(LOG, errors='ignore').read())
    if rc != 0 or not rows:
        print('C131B: SUSPENDU — `measure()` rend rc=%s et %d lignes.' % (rc, len(rows)))
        return 1
    print('C131B: CONTROLE DE REPRODUCTION DE LA LECTURE DE DECILES (seuil declare %.1f %%)' % SEUIL)
    print('C131B: %-8s %-9s %-10s %-10s %s' % ('chaine', 'frontiere', 'PORTAGE', 'PUBLIEE', 'ecart'))
    ok = True
    for ch, lbl, att in REF:
        k = (ch, lbl, '11', 'fwd')
        if k not in rows:
            print('C131B: %-8s %-9s MANQUANTE' % (ch, lbl)); ok = False; continue
        t = rows[k]
        if len(t) < 5 or t[4] is None:
            print('C131B: %-8s %-9s PAS DE LECTURE DE DECILES (tuple a %d champs)'
                  % (ch, lbl, len(t))); ok = False; continue
        e = (t[4] - att) / att * 100.0
        ok = ok and abs(e) <= SEUIL
        print('C131B: %-8s %-9s %-10.4f %-10.4f %+.3f %%' % (ch, lbl, t[4], att, e))
    print('C131B: -> %s' % ('TIRE — le portage retrouve son point de depart.' if ok else
                            '**ECHOUE** — le portage ne reproduit pas les valeurs publiees ; '
                            'rien de ce qu il calcule n est recevable.'))
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
