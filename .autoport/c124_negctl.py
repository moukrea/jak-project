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


def main():
    a, b = sys.argv[1], sys.argv[2]
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
