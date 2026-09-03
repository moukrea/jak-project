#!/usr/bin/env python3
"""c124_negctl.py — CONTROLE NEGATIF DU LOT B : l'emission neuve est-elle un INSTRUMENT PUR ?

L'emission `PHYSORIM` du cycle 124 ne doit ecrire aucun etat du solveur. Si c'est vrai, la course
neuve reproduit la course archivee enregistrement pour enregistrement, a l'exception des lignes
NEUVES. Si une seule ligne preexistante bouge, l'attribution de tout le lot tombe et le lot est
retire AVANT d'etre lu — c'est la prediction P5, avec son falsificateur, ecrite avant la course.

Meme methode que le controle du cycle 109 (« sur 88 190 enregistrements compares : 1 seule ligne
differente, et c'est une ADRESSE DE TAS »), y compris le masquage des adresses : une adresse de tas
change a chaque demarrage et n'a rien a voir avec la physique. Le nombre d'adresses masquees est
PUBLIE, jamais silencieux — masquer sans compter permettrait de masquer un vrai ecart.
"""
import re
import sys

NEW = ('PHYSORIM ', 'PHYSORIMN ', 'PHYSORIMMISS ')
ADDR = re.compile(r'#x[0-9a-fA-F]{4,}|0x[0-9a-fA-F]{4,}')


def load(p):
    keep, masked = [], 0
    for line in open(p, 'r', errors='replace'):
        if not line.startswith('PHYS'):
            continue
        if line.startswith(NEW):
            continue
        s, n = ADDR.subn('#xADDR', line.rstrip('\n'))
        masked += 1 if n else 0
        keep.append(s)
    return keep, masked


START = re.compile(r'^PHYSROOM-START .*?:state ([a-z-]+)', re.M)
SPAWN = re.compile(r'^PHYSPOSED joint0=\d+ dist-from-origin=([0-9.]+)', re.M)


def start_state(p):
    """L'ETAT DE DEPART DE LA COURSE — la precondition que ce controle ne verifiait pas.

    CYCLE 125. Ce controle comparait deux traces enregistrement pour enregistrement sans jamais
    regarder DANS QUEL ETAT la salle avait demarre. Mesure sur les 8 courses archivees : 7
    attrapent la cible en `target-title` et font spawner le sujet a 1061328.6250 unites de
    l'origine — le MEME chiffre jusqu'a la derniere decimale ; la 8e l'attrape en
    `target-title-wait` et spawne a 1230225.1250. L'integration se fait en float32 en repere
    MONDE (registre : `spec9-residual-is-float32-ulp-floor`), donc une position de depart
    differente fait diverger 79 % des enregistrements QUEL QUE SOIT le changement teste.
    Le controle etait donc CONDITIONNE A UN ETAT QU'IL NE REGARDAIT PAS : selon le cote ou tombe
    la course avec la sequence de titre, il rend « tout differe » ou « rien ne differe », et dans
    les deux cas ca ne parle pas du lot qu'on teste. Il REFUSE desormais de comparer une paire
    qui ne partage pas ses conditions initiales, au lieu de rendre un chiffre ininterpretable."""
    txt = open(p, 'r', errors='replace').read()
    st = START.search(txt)
    sp = SPAWN.search(txt)
    return (st.group(1) if st else None), (sp.group(1) if sp else None)


def main():
    a, b = sys.argv[1], sys.argv[2]
    sa, sb = start_state(a), start_state(b)
    print('C124-NEGCTL: conditions initiales — archive %s / spawn %s  ·  course %s / spawn %s'
          % (sa[0], sa[1], sb[0], sb[1]))
    if sa != sb:
        print('C124-NEGCTL: *** COMPARAISON REFUSEE — les deux courses ne partagent pas leurs')
        print('C124-NEGCTL:     conditions initiales. Une position de depart differente fait')
        print('C124-NEGCTL:     diverger ~79 % des enregistrements QUEL QUE SOIT le lot teste')
        print('C124-NEGCTL:     (float32 en repere MONDE). Un chiffre rendu ici ne dirait rien')
        print('C124-NEGCTL:     du changement qu\'on veut attribuer. Relancer la course.')
        return 2
    A, ma = load(a)
    B, mb = load(b)
    print('C124-NEGCTL: archive %s : %d enregistrements PHYS* (adresses masquees %d)'
          % (a, len(A), ma))
    print('C124-NEGCTL: course   %s : %d enregistrements PHYS* (adresses masquees %d)'
          % (b, len(B), mb))
    if len(A) != len(B):
        print('C124-NEGCTL: *** LE COMPTE DIFFERE de %d ***' % (len(B) - len(A)))
    n = min(len(A), len(B))
    diff = [(i, A[i], B[i]) for i in range(n) if A[i] != B[i]]
    print('C124-NEGCTL: lignes preexistantes DIFFERENTES : %d  (seuil declare avant la course : 0)'
          % len(diff))
    for i, x, y in diff[:12]:
        print('C124-NEGCTL:   #%d\n      archive : %s\n      course  : %s' % (i, x[:150], y[:150]))
    if len(diff) > 12:
        print('C124-NEGCTL:   ... et %d autres' % (len(diff) - 12))
    # ce que le lot AJOUTE, compte a part
    for p, tag in ((a, 'archive'), (b, 'course ')):
        c = {k.strip(): 0 for k in NEW}
        for line in open(p, 'r', errors='replace'):
            for k in NEW:
                if line.startswith(k):
                    c[k.strip()] += 1
        print('C124-NEGCTL: %s lignes NEUVES : %s'
              % (tag, ' '.join('%s=%d' % (k, v) for k, v in c.items())))
    return 0 if (not diff and len(A) == len(B)) else 1


if __name__ == '__main__':
    sys.exit(main())
