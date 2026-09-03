#!/usr/bin/env python3
"""Gcutscene-npc-flicker — BRAS 2 DE LA GARDE : aucune valeur PUBLIEE n'est morte.

REGLE. Une valeur imprimee dans une ligne de journal doit etre ECRITE quelque part en dehors de
sa declaration. Un compteur s'incremente, un reglage s'affecte ; les deux comptent. Ce qui ne
compte pas, c'est un `static u64 x = 0;` que plus rien ne touche et qu'on imprime quand meme.

POURQUOI CETTE REGLE EXISTE. `s_hd_blackout_events` (Merc2.cpp) etait declare, imprime dans
`[hd-flicker] ... blackouts={}` et jamais ecrit depuis 45b7140ca7, qui avait supprime son unique
site d'increment en passant la suppression en fail-open. TROIS jambes de preuve exigeaient
`blackouts=0` et zero ligne `[hd-flicker] BLACKOUT` — deux conditions qu'aucun chemin de code ne
pouvait violer. Le defaut des PNJ est revenu sans qu'aucune porte ne s'ouvre.

Ce fichier porte son PROPRE controle positif : il s'applique d'abord a un motif de reference qui
reproduit exactement ce cas, et echoue s'il ne le detecte pas.
"""
import re
import sys

FILES = [
    "game/graphics/opengl_renderer/foreground/Merc2.cpp",
    "game/system/npc_flicker.cpp",
    "game/system/load_gate.cpp",
]

DECL = re.compile(r'^\s*static\s+(?:u64|uint64_t|int|u32|uint32_t)\s+(\w+)\s*=', re.M)
PRINT = re.compile(r'(?:lg::(?:warn|info|error)|fmt::print|printf)\s*\((.*?)\);', re.S)


def published_values(src):
    """[(nom, nombre de sites d'ecriture hors declaration)] pour chaque static imprime."""
    out = []
    prints = [pm.group(1) for pm in PRINT.finditer(src)]
    for m in DECL.finditer(src):
        name = m.group(1)
        word = re.compile(r'\b' + re.escape(name) + r'\b')
        if not any(word.search(p) for p in prints):
            continue
        body = src[:m.start()] + src[m.end():]
        sites = re.findall(
            r'\b' + re.escape(name) + r'\s*(?:\+\+|--|\+=|-=|=(?!=))'
            r'|(?:\+\+|--)\s*' + re.escape(name) + r'\b',
            body)
        out.append((name, len(sites)))
    return out


FIXTURE = """
static u64 s_dead_counter = 0;
static u64 s_live_counter = 0;
void tick() { s_live_counter++; }
void beat() { lg::warn("[x] a={} b={}", s_live_counter, s_dead_counter); }
"""


def main():
    fx = dict(published_values(FIXTURE))
    if fx.get('s_dead_counter') != 0 or fx.get('s_live_counter', 0) < 1:
        print("  [GARDE FAIL] controle positif : le motif historique n'est pas detecte " + repr(fx),
              file=sys.stderr)
        return 1
    print("  [ok]   controle positif : `declare, imprime, jamais ecrit` est bien detecte")

    bad = []
    checked = 0
    for f in FILES:
        try:
            src = open(f).read()
        except OSError:
            continue
        for name, n in published_values(src):
            checked += 1
            if n == 0:
                bad.append((f, name))
            else:
                print(f"  [ok]   {name:<28} {n} site(s) d'ecriture  ({f.split('/')[-1]})")
    print(f"\n  {checked} valeur(s) publiee(s) verifiee(s) dans {len(FILES)} fichiers")
    for f, n in bad:
        print(f"  [GARDE FAIL] {n} est PUBLIE et n'est ECRIT NULLE PART hors de sa declaration"
              f" — {f}", file=sys.stderr)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
