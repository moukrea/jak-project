#!/usr/bin/env python3
"""c149_compare.py — CONTROLE DE PURETE L1 : la course de la jambe 1 doit etre IDENTIQUE AU
CHIFFRE a la course livree du cycle 148 sur toute grandeur SOLVEUR. Les seules lignes autorisees
a differer sont l'empreinte de la course et le bloc neuf `ROOM-SATD` / `PHYSSATD`.

CORRECTION DU CYCLE 149 — LA PREMIERE VERSION A RENDU UN FAUX ROUGE, ET C'EST LE MEME DEFAUT QUE
CELUI QU'ELLE EST CENSEE ATTRAPER. Elle excluait les lignes CONTENANT la chaine `ROOM-SATD` ;
or le bloc neuf tient en 3 lignes d'en-tete et 22 lignes de DETAIL INDENTEES qui ne portent pas
ce mot. Les 22 lignes de detail etaient donc comptees comme « grandeurs solveur qui ont bouge » et
le verdict imprime etait « IMPURE — LE LOT EST RETIRE » sur un lot dont la purete est exacte.
Un faux rouge coute autant qu'un faux vert (DIRECTIVES 2026-08-19 23:50) : il aurait fait retirer
un lot sain et perdre la mesure du cycle.
L'attribution se fait donc par BLOC — de l'en-tete `ROOM-SATD` jusqu'a la premiere ligne qui
recommence en colonne 0 — et jamais par sous-chaine. Les lignes vides sont ignorees des deux
cotes : elles bougent quand un bloc s'insere, sans qu'aucune grandeur ne change.
Usage : c149_compare.py <table_avant> <table_apres>"""
import difflib, re, sys

NEWHDR = ('ROOM-SATD', 'PHYSSATD')

def strip_new_blocks(path):
    """Retire les blocs NEUFS en entier (en-tete + detail indente) et les lignes vides."""
    out, inblk = [], False
    for ln in open(path, encoding='utf-8', errors='replace').read().splitlines():
        if any(ln.startswith(h) for h in NEWHDR):
            inblk = True
            continue
        if inblk:
            if ln[:1] in (' ', '\t') or ln.strip() == '':
                continue                       # detail du bloc neuf
            inblk = False
        if ln.strip() == '':
            continue
        out.append(ln)
    return out

a, b = sys.argv[1], sys.argv[2]
sa, sb = strip_new_blocks(a), strip_new_blocks(b)
diff = [l for l in difflib.unified_diff(sa, sb, lineterm='', n=0)
        if l[:1] in '+-' and l[:3] not in ('+++', '---')]
# une empreinte de course est un md5 : 32 hexa. C'est la SEULE ligne qui a le droit de bouger.
stamp = [l for l in diff if re.search(r'[0-9a-f]{32}', l)]
real  = [l for l in diff if l not in stamp]

print("lignes comparees (hors blocs neufs et lignes vides) : %d avant / %d apres" % (len(sa), len(sb)))
print("--- differences : %d, dont %d d'empreinte de course ---" % (len(diff), len(stamp)))
for l in stamp:
    print("   [empreinte] %s" % l[:160])
for l in real[:80]:
    print("   [SOLVEUR]   %s" % l[:200])
print()
print("VERDICT L1 : %s" % ("PURE — l'instrument ne deplace pas ce qu'il compte (%d lignes "
                           "identiques au caractere)" % len(sa)
                           if not real else
                           "IMPURE — %d ligne(s) solveur ont bouge, LE LOT EST RETIRE" % len(real)))
sys.exit(0 if not real else 1)
