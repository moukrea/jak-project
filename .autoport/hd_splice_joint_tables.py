#!/usr/bin/env python3
"""Splice the regenerated keira k2e joint tables into `goal_src/jak1/pc/jak-hd.gc`.

WHY THIS EXISTS, AND WHY IT REFUSES RATHER THAN REPAIRS (2026-08-17, cycle 16).
`jak-hd.gc` itself carries the tombstone (`:303-311`): on 2026-08-13 the four arrays were taken
to 100 entries while `*hd-joint-counts*` stayed at 95. That counter BOUNDS the retargeting loop,
so joints 95..99 were never written — the solver read uninitialised bones and published
`PHYSBONE c=2 l=2 len=NaN`, `amp=0.0000`. Four tables agreed and the fifth silently disagreed.
**There are FIVE places, not four**, and that is the entire reason this script exists.

THE INVARIANT IT ENFORCES — append-only, checked programmatically and not by eye:
every new array must START with the old one, element for element. An injection may only ADD
joints at the end; if any existing index moved, every parent reference elsewhere in the rig is
silently wrong, and nothing downstream would catch it.

It writes NOTHING unless all five places agree on the new count and all four arrays extend their
predecessor. On any mismatch it prints what disagreed and exits non-zero.

    python3 .autoport/hd_splice_joint_tables.py \
        --snippet recharged_assets/hd_anim/keira-hd-k2e.gc-snippet \
        --gc goal_src/jak1/pc/jak-hd.gc --entry 2 [--apply]

Without `--apply` it is a DRY RUN: it reports what it would do and touches nothing.
"""
import argparse
import re
import sys

ARRAYS = ['*keira-hd->driver-joint*', '*keira-hd-mode*',
          '*keira-hd-hd-parent*', '*keira-hd-drv-parent*']


def parse_arrays(text):
    """-> {name: (declared_count, [values])}. Tolerates any line wrapping."""
    out = {}
    for name in ARRAYS:
        m = re.search(r'\(define\s+' + re.escape(name) +
                      r'\s+\(new\s+\'static\s+\'array\s+uint8\s+(\d+)\s+(.*?)\)\s*\)',
                      text, re.S)
        if not m:
            continue
        vals = [int(x) for x in m.group(2).split()]
        out[name] = (int(m.group(1)), vals, m.span())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--snippet', required=True)
    ap.add_argument('--gc', required=True)
    ap.add_argument('--entry', type=int, required=True,
                    help='index into *hd-joint-counts* for this character')
    ap.add_argument('--apply', action='store_true')
    a = ap.parse_args()

    gc_text = open(a.gc, encoding='utf-8').read()
    sn_text = open(a.snippet, encoding='utf-8').read()
    old = parse_arrays(gc_text)
    new = parse_arrays(sn_text)

    bad = []
    for name in ARRAYS:
        if name not in old:
            bad.append("%s absent de %s" % (name, a.gc))
        if name not in new:
            bad.append("%s absent de %s" % (name, a.snippet))
    if bad:
        print("\n".join("!! " + b for b in bad))
        return 1

    counts = set()
    for name in ARRAYS:
        oc, ov, _ = old[name]
        nc, nv, _ = new[name]
        if oc != len(ov):
            bad.append("%s: ancien compte declare %d mais %d valeurs" % (name, oc, len(ov)))
        if nc != len(nv):
            bad.append("%s: nouveau compte declare %d mais %d valeurs" % (name, nc, len(nv)))
        if nc < oc:
            bad.append("%s: le nouveau tableau RETRECIT (%d -> %d) — ce n'est pas un append"
                       % (name, oc, nc))
        # THE invariant: the new array must extend the old one exactly.
        elif nv[:oc] != ov:
            first = next((i for i in range(min(len(ov), len(nv))) if ov[i] != nv[i]), None)
            bad.append("%s: PAS APPEND-ONLY — l'indice %s change (%s -> %s). Un indice qui bouge "
                       "invalide toutes les references de parent du rig."
                       % (name, first,
                          ov[first] if first is not None else '?',
                          nv[first] if first is not None else '?'))
        counts.add(nc)
        print("%-26s %3d -> %3d   append-only %s"
              % (name, oc, nc, "OK" if (nc >= oc and nv[:oc] == ov) else "NON"))

    if len(counts) != 1:
        bad.append("les quatre tableaux ne s'accordent pas sur le nouveau compte : %s"
                   % sorted(counts))
    if bad:
        print("\n".join("!! " + b for b in bad))
        return 1
    newc = counts.pop()

    # ---- the FIFTH place, the one that was forgotten and produced len=NaN ------------------
    m = re.search(r"\(define\s+\*hd-joint-counts\*\s+\(new\s+'static\s+'array\s+int32\s+(\d+)\s+(.*?)\)\s*\)",
                  gc_text, re.S)
    if not m:
        print("!! *hd-joint-counts* introuvable — c'est LE tableau dont l'oubli a produit len=NaN")
        return 1
    jc = [int(x) for x in m.group(2).split()]
    if len(jc) != int(m.group(1)):
        print("!! *hd-joint-counts* declare %s entrees pour %d valeurs" % (m.group(1), len(jc)))
        return 1
    if not (0 <= a.entry < len(jc)):
        print("!! entry %d hors bornes (%d entrees)" % (a.entry, len(jc)))
        return 1
    print("%-26s %3d -> %3d   (*hd-joint-counts* entree %d — LE CINQUIEME ENDROIT)"
          % ('*hd-joint-counts*', jc[a.entry], newc, a.entry))

    if not a.apply:
        print("\nDRY RUN — rien n'a ete ecrit. Relance avec --apply.")
        return 0

    # Replace from the LAST span to the first so earlier spans stay valid.
    for name in sorted(ARRAYS, key=lambda n: old[n][2][0], reverse=True):
        s, e = old[name][2]
        gc_text = gc_text[:s] + sn_text[new[name][2][0]:new[name][2][1]] + gc_text[e:]

    # RE-CHERCHER `*hd-joint-counts*` MAINTENANT, ET NON REUTILISER `m`.
    # Le 2026-08-17 cette ligne a corrompu `jak-hd.gc` : `m` avait ete calcule sur le texte
    # d'ORIGINE, puis les quatre tableaux (situes PLUS HAUT dans le fichier) ont ete rallonges de
    # 105 a 107 entrees — ce qui decale tous les offsets suivants. Le decoupage a donc mordu au
    # milieu du COMMENTAIRE precedent, avalant sa fin et son saut de ligne : le `(define ...)` s'est
    # retrouve DERRIERE `;;`, donc jamais evalue, et `(mi)` a echoue avec « The symbol
    # *hd-joint-counts* was looked up as a global variable, but it does not exist ».
    # Des offsets calcules avant une reecriture ne survivent pas a cette reecriture.
    m2 = re.search(r"^\(define\s+\*hd-joint-counts\*\s+\(new\s+'static\s+'array\s+int32\s+(\d+)\s+([^)]*)\)\s*\)",
                   gc_text, re.M)
    if not m2:
        print("!! *hd-joint-counts* introuvable APRES le remplacement des tableaux — rien ecrit")
        return 1
    jc[a.entry] = newc
    gc_text = (gc_text[:m2.start()] +
               "(define *hd-joint-counts* (new 'static 'array int32 %d %s))"
               % (len(jc), " ".join(str(x) for x in jc)) +
               gc_text[m2.end():])
    open(a.gc, 'w', encoding='utf-8').write(gc_text)
    print("\nECRIT. Verifie maintenant avec : python3 .autoport/hd_check_joint_counts.py")
    return 0


if __name__ == '__main__':
    sys.exit(main())
