#!/usr/bin/env python3
"""c140_causal_confinement.py — LE TEST DE CONFINEMENT QUI SURVIT A UN OPERATEUR QUI AGIT.

POURQUOI CE FICHIER EXISTE. Le dossier prouve depuis des cycles qu'un operateur est un SCALPEL en
montrant que tout ce qui est publie HORS des fenetres qu'il declenche est IDENTIQUE AU BIT a la
course d'avant. Le cycle 140 mesure que ce test est **structurellement infaillible dans le mauvais
sens** : la salle joue ses 31 animations x 6 pilotages en UNE SEULE simulation continue, sans
remise a zero de l'etat physique entre deux fenetres. Un operateur qui agit UNE fois change donc
l'etat d'entree de TOUTES les fenetres qui suivent, quelles que soient leurs animations.

Mesure qui l'etablit (cycle 140, `PHYSAPEX`, course armee contre `c139-BASELINE`) : premier
declenchement a `a=5 d=0`, **60 fenetres sur 60 ANTERIEURES identiques au bit**, et **312 des 372**
differentes ensuite (2 au pivot, 310 en aval), l'ecart median HORS des fenetres declenchees
(0,0196 B0) etant PLUS GRAND que dans celles ou l'operateur tire (0,0079 B0).

CONSEQUENCE, ET C'EST LA REGLE QUE CE FICHIER ENCODE : « identique au bit hors des fenetres
touchees » ne peut etre satisfait que par un operateur qui **ne tire jamais** — un controle negatif
deguise en preuve de confinement. Le remplacer par la question a laquelle on peut repondre :

    RIEN DE CE QUI PRECEDE CAUSALEMENT LE PREMIER DECLENCHEMENT NE DOIT BOUGER.

C'est un test de CAUSALITE, pas de localite. Il est FALSIFIABLE (une seule fenetre anterieure qui
change le fait echouer), il ne peut pas etre satisfait par inaction (il exige qu'on NOMME la
premiere fenetre declenchee, donc qu'il y en ait une), et il attrape exactement le defaut que
l'ancien test visait : un operateur qui agit la ou sa condition ne le designe pas.

NATURE des grandeurs comparees : ce que l'enregistrement choisi publie, tel quel — le script ne
convertit rien. REPERE : celui de l'enregistrement. Le script ne compare que des fenetres
APPARIEES par la cle (chaine, animation, pilotage) : une fenetre presente d'un seul cote est
comptee a part et jamais confondue avec une fenetre inchangee.

Usage :
    python3 .autoport/c140_causal_confinement.py <AVANT.log> <APRES.log> <TAG> <ordre>
      TAG    l'enregistrement compare, p.ex. PHYSAPEX
      ordre  la cle qui ORDONNE la course, `a` (animation) ou `ad` (animation puis pilotage)
"""
import collections
import re
import sys

KEY = re.compile(r'^(PHYS[A-Z0-9-]*) c=(\d+) a=(\d+) d=(\d+)\s+(.*)$')


def load(path, tag):
    """(chaine, animation, pilotage) -> LA LISTE de toutes les lignes de cette fenetre, verbatim.

    Une LISTE et pas la derniere ligne : plusieurs enregistrements portent la meme cle de fenetre
    (`PHYSSTG` en emet 15 par fenetre). Ecraser dans un dict ne comparerait que la derniere et
    declarerait « inchangee » une fenetre dont les 14 autres lignes ont bouge — un faux vert que
    ce script existe precisement pour ne pas produire."""
    out = collections.defaultdict(list)
    with open(path, 'rb') as fh:
        for raw in fh:
            ln = raw.decode('utf-8', 'replace').rstrip('\n')
            i = ln.find('PHYS')
            if i < 0:
                continue
            m = KEY.match(ln[i:])
            if m and m.group(1) == tag:
                out[(int(m.group(2)), int(m.group(3)), int(m.group(4)))].append(m.group(5))
    return dict(out)


def firings(path):
    """Les fenetres ou le rebase a REELLEMENT deplace un maillon (`rbfix` > 0), par la trace."""
    pat = re.compile(r'^PHYSANROTF c=(\d+) a=(\d+) d=(\d+) rbfix=([-\d.e+]+)')
    hot = set()
    with open(path, 'rb') as fh:
        for raw in fh:
            m = pat.match(raw.decode('utf-8', 'replace'))
            if m and float(m.group(4)) > 0.0:
                hot.add((int(m.group(1)), int(m.group(2)), int(m.group(3))))
    return hot


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    before, after, tag, order = sys.argv[1:5]
    if order not in ('a', 'ad'):
        print("ordre doit valoir 'a' ou 'ad'")
        return 2
    A, B = load(before, tag), load(after, tag)
    if not A or not B:
        print('REFUS: %s absent d\'une des deux traces (avant=%d, apres=%d enregistrements)'
              % (tag, len(A), len(B)))
        return 1

    hot = firings(after)
    if not hot:
        print('REFUS: aucune fenetre declenchee (`PHYSANROTF rbfix > 0`) dans la course APRES.')
        print('       Sans premier declenchement, ce test n\'a pas de frontiere causale et un')
        print('       « rien n\'a bouge » ne prouverait que l\'inaction de l\'operateur.')
        return 1

    def rank(k):
        return (k[1], k[2]) if order == 'ad' else (k[1],)

    first = min(rank(k) for k in hot)
    print('TAG COMPARE           %s   (%d fenetres avant, %d apres)' % (tag, len(A), len(B)))
    print('FENETRES DECLENCHEES  %d  (`PHYSANROTF rbfix > 0`)' % len(hot))
    print('PREMIER DECLENCHEMENT %s = %s' % ('(a,d)' if order == 'ad' else '(a)', first))

    common = sorted(set(A) & set(B))
    orphan = (set(A) ^ set(B))
    seg = collections.Counter()
    amont_changees = []
    for k in common:
        pos = 'AMONT' if rank(k) < first else ('PIVOT' if rank(k) == first else 'AVAL')
        changed = A[k] != B[k]
        seg[(pos, changed)] += 1
        if pos == 'AMONT' and changed:
            amont_changees.append(k)

    print()
    print('%-8s %10s %10s' % ('segment', 'changees', 'inchangees'))
    for pos in ('AMONT', 'PIVOT', 'AVAL'):
        print('%-8s %10d %10d' % (pos, seg[(pos, True)], seg[(pos, False)]))
    if orphan:
        print('FENETRES NON APPARIEES : %d — comptees a part, jamais lues comme inchangees'
              % len(orphan))

    print()
    if amont_changees:
        print('VERDICT: CONFINEMENT CAUSAL REFUTE — %d fenetre(s) ANTERIEURE(S) au premier'
              % len(amont_changees))
        print('         declenchement ont change. L\'operateur agit hors de sa condition.')
        for k in amont_changees[:10]:
            print('   c=%d a=%d d=%d  (%d ligne(s))' % (k + (len(A[k]),)))
            for x, y in zip(A[k], B[k]):
                if x != y:
                    print('     avant: %s\n     apres: %s' % (x[:150], y[:150]))
        return 1
    print('VERDICT: CONFINEMENT CAUSAL TENU — %d fenetre(s) anterieure(s) au premier'
          % seg[('AMONT', False)])
    print('         declenchement, TOUTES identiques. Les %d differences en AVAL sont le report'
          % seg[('AVAL', True)])
    print('         d\'etat d\'une simulation continue, pas une action hors condition.')
    print('         Ce test ne dit RIEN de l\'AMPLITUDE de ce report — la publier a cote.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
