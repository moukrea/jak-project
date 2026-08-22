#!/usr/bin/env python3
"""c77_migrate_notes.py — LIBERER DES LIGNES DANS LE MOTEUR SANS TOUCHER A UNE SEULE LIGNE DE CODE.

Le plafond CLEAN du validateur est 4800 lignes et le cycle 77 le depasse de 1 en ajoutant le latch a portee de fenetre. La regle du registre
(`never-spend-the-bit-identity-control-on-line-count`) est explicite : on paie en DEPLACANT DES
COMMENTAIRES vers jak-hd-physics-NOTES.md, VERBATIM, avec un pointeur d'une ligne a leur place —
jamais en refactorisant du code flottant, ce qui decalerait un ULP et detruirait le controle de
bit-identite qui autorise a lire le reste du cycle.

Ce script est ecrit plutot qu'une edition a la main parce qu'il PROUVE ce qu'il fait : il verifie,
avant d'ecrire, que chaque ligne retiree commence par `;;`. Une edition manuelle de 30 sites ne
peut pas le prouver.
"""
import re, sys, hashlib

GC    = "goal_src/jak1/pc/jak-hd-physics.gc"
NOTES = "goal_src/jak1/pc/jak-hd-physics-NOTES.md"
NEED  = int(sys.argv[1]) if len(sys.argv) > 1 else 4

src = open(GC, encoding='utf-8').read().split('\n')

# --- 1. reperer les blocs de commentaire INLINE (ceux qui ne sont pas deja des pointeurs) -------
runs, cur = [], []
for i, l in enumerate(src, 1):
    s = l.strip()
    if s.startswith(';;') and '-> jak-hd-physics-NOTES.md' not in s:
        cur.append(i)
    else:
        if cur: runs.append((cur[0], cur[-1]))
        cur = []
if cur: runs.append((cur[0], cur[-1]))

# on ne touche NI l'en-tete du fichier NI les blocs de moins de 3 lignes (le pointeur en coute 1,
# migrer un bloc de 2 n'economise qu'une ligne pour une perte de lisibilite locale).
cand = [(a, b) for (a, b) in runs if a > 20 and (b - a + 1) >= 2]
cand.sort(key=lambda r: -(r[1] - r[0]))          # les plus gros d'abord : moins de sites touches

chosen, saved = [], 0
for a, b in cand:
    if saved >= NEED: break
    chosen.append((a, b)); saved += (b - a)      # n lignes -> 1 pointeur => n-1 economisees
chosen.sort()

# --- 2. le numero de NOTE libre suivant ---------------------------------------------------------
nmax = max(int(m) for m in re.findall(r'NOTE-(\d+)', open(NOTES, encoding='utf-8').read()))
nxt  = nmax + 1

# --- 3. construire les remplacements, et REFUSER si une ligne de code est dans le lot ------------
out_notes = []
repl = {}
for idx, (a, b) in enumerate(chosen):
    body = src[a-1:b]
    for l in body:
        if not l.strip().startswith(';;'):
            sys.exit(f"REFUS: {GC}:{a}-{b} contient une ligne qui n'est pas un commentaire: {l!r}")
    num    = nxt + idx
    indent = re.match(r'\s*', src[a-1]).group(0)
    # le titre du pointeur est le TEXTE de la premiere ligne du bloc, tronque — pas une invention.
    head   = re.sub(r'^;+\s*', '', body[0].strip())
    head   = re.sub(r'^\[NOTE-\d+\]\s*', '', head)
    head   = re.sub(r'^-+\s*$', 'suite', head) or 'suite'
    short  = (head[:96]).rstrip()
    repl[(a, b)] = f"{indent};; [NOTE-{num}] {short} -> jak-hd-physics-NOTES.md"
    out_notes.append(
        f"\n---\n## NOTE-{num} — {short}\n\n"
        f"Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 91) pour tenir le plafond de 4800 lignes\n"
        f"de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.\n\n"
        "```\n" + '\n'.join(body) + "\n```\n")

# --- 4. appliquer, du bas vers le haut (les numeros de ligne au-dessus ne bougent pas) -----------
for (a, b) in sorted(chosen, reverse=True):
    src[a-1:b] = [repl[(a, b)]]

open(GC, 'w', encoding='utf-8').write('\n'.join(src))
with open(NOTES, 'a', encoding='utf-8') as f:
    f.write('\n' + ''.join(out_notes))

print(f"blocs migres : {len(chosen)}   lignes economisees : {saved}   NOTE-{nxt}..NOTE-{nxt+len(chosen)-1}")
print(f"{GC} : {len(src)} lignes")
