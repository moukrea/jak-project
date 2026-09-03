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

# LES QUATRE NOMS SONT DERIVES DU SNIPPET, PAS ECRITS EN DUR (Gkeira-visor-deliver 2026-08-29).
# Ils l'etaient pour keira-hd seule, donc l'outil ne pouvait pas episser keira3-hd — le MEME
# personnage sur l'autre entree du carrousel LOOK — et le cinquieme endroit serait reparti a la
# main, ce que ce fichier existe precisement pour interdire.
def snippet_array_names(text):
    names = re.findall(r"\(define\s+(\*[^\s*]+\*)\s+\(new\s+'static\s+'array\s+uint8\s+\d+",
                       text)
    seen, out = set(), []
    for n in names:
        if n not in seen:
            seen.add(n)
            out.append(n)
    return out
# LES TABLES QUI PORTENT DES INDICES. Pour elles, « append-only » veut dire ce que le docstring
# dit : une valeur qui change A UN INDICE EXISTANT invalide silencieusement des references.
# `*keira-hd-mode*` ne porte PAS d'indice — ses valeurs sont des MODES DE RETARGET (0..3) — donc
# une valeur qui y change ne deplace aucun indice et n'invalide aucune reference de parent.
# 2026-08-18, cycle 24 : la garde traitait les quatre tables pareil et refusait un changement de
# mode legitime. Deplacer `lBoob`/`rBoob` de 0.0159 m a fait passer leur `pivot_err` sous le seuil
# du selecteur (`retarget_fill_table.py:224`, `thr = max(0.02, 0.25*bone)`), qui bascule alors du
# repli mode 3 (orient-copy, choisi PARCE QUE les pivots ne s'accordaient pas) vers le mode 0
# (world-delta, « exact driver-skin follow »). C'est le selecteur qui fait son travail sur une
# geometrie qui le permet enfin — pas une table qui derive.
# CE QUI REMPLACE LA GARDE, ET ELLE EST PLUS STRICTE, PAS PLUS LACHE : un changement de mode doit
# etre DECLARE index par index avec son ancienne et sa nouvelle valeur. Il ne peut donc plus
# arriver en silence — ce que le tombeau de `jak-hd.gc` reproche precisement au cycle du 08-13
# (« quatre tables d'accord et la cinquieme en desaccord silencieux ») — et aucun drapeau
# d'autorisation generale n'existe.
def classify(names):
    """-> (mode_array, hd_parent_array). The other two carry DRIVER indices, untouched by an
    HD-side renumbering."""
    mode = next((n for n in names if n.endswith('-mode*')), None)
    hdpar = next((n for n in names if n.endswith('-hd-parent*')), None)
    return mode, hdpar


def parse_arrays(text, ARRAYS):
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
    ap.add_argument('--drop-joints', default='',
                    help="indices HD SUPPRIMES de l'ancien tableau, `k[,k...]`. Bascule la garde "
                         "append-only vers une garde de SUPPRESSION EXACTE, qui est plus stricte : "
                         "elle exige que le nouveau tableau soit l'ancien PRIVE de ces indices, "
                         "avec les references de parent HD renumerotees en consequence, valeur par "
                         "valeur. Une seule autre difference et elle refuse.")
    ap.add_argument('--expect-mode-change', default='',
                    help="changements de mode ATTENDUS, declares un par un : "
                         "`k:ancien->nouveau[,k:ancien->nouveau...]`. Un mode ne deplace aucun "
                         "indice, mais il change comment le joint est retargete : il doit etre "
                         "declare pour ne jamais passer en silence. Aucun drapeau d'autorisation "
                         "generale n'existe volontairement.")
    a = ap.parse_args()
    expect_mode = set()
    for tok in [t for t in a.expect_mode_change.split(',') if t.strip()]:
        try:
            k, ch = tok.split(':', 1)
            o, n = ch.split('->', 1)
            expect_mode.add((int(k), o.strip(), n.strip()))
        except ValueError:
            print("!! --expect-mode-change: `%s` n'est pas `k:ancien->nouveau`" % tok)
            return 1

    gc_text = open(a.gc, encoding='utf-8').read()
    sn_text = open(a.snippet, encoding='utf-8').read()
    ARRAYS = snippet_array_names(sn_text)
    if len(ARRAYS) != 4:
        print("!! le snippet declare %d tableaux uint8, il en faut 4 : %s" % (len(ARRAYS), ARRAYS))
        return 1
    MODE_ARRAY, HD_PARENT_ARRAY = classify(ARRAYS)
    if not MODE_ARRAY or not HD_PARENT_ARRAY:
        print("!! impossible d'identifier *-mode* / *-hd-parent* parmi %s" % ARRAYS)
        return 1
    drops = sorted({int(x) for x in a.drop_joints.split(',') if x.strip()})
    old = parse_arrays(gc_text, ARRAYS)
    new = parse_arrays(sn_text, ARRAYS)

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
    if drops:
        # ---- GARDE DE SUPPRESSION EXACTE (Gkeira-visor-deliver 2026-08-29) -------------------
        # L'invariant append-only du docstring dit vrai pour une INJECTION : un indice qui bouge
        # tout seul invalide en silence les references de parent. Il ne peut pas exprimer une
        # SUPPRESSION, ou tous les indices posterieurs bougent EXPRES et ou les quatre tableaux,
        # l'art-group, la table k2e et le mesh sont regeneres dans la meme passe depuis le meme rig.
        # Ce n'est donc pas un assouplissement : au lieu de « le nouveau commence par l'ancien »,
        # on exige VALEUR PAR VALEUR que le nouveau soit exactement l'ancien prive de `drops`, les
        # references de parent HD renumerotees. Une seule difference de plus et on refuse.
        for name in ARRAYS:
            oc, ov, _ = old[name]
            nc, nv, _ = new[name]
            if oc != len(ov):
                bad.append("%s: ancien compte declare %d mais %d valeurs" % (name, oc, len(ov)))
                continue
            if nc != len(nv):
                bad.append("%s: nouveau compte declare %d mais %d valeurs" % (name, nc, len(nv)))
                continue
            for d in drops:
                if not (0 <= d < oc):
                    bad.append("%s: indice supprime %d hors de l'ancien tableau (%d entrees)"
                               % (name, d, oc))
            if bad:
                continue
            keep = [i for i in range(oc) if i not in set(drops)]
            if nc != len(keep):
                bad.append("%s: %d entrees apres suppression de %d indices sur %d, attendu %d"
                           % (name, nc, len(drops), oc, len(keep)))
                continue
            def _remap(v):
                if v == 255:
                    return 255
                return v - sum(1 for d in drops if d < v)
            exp = [(_remap(ov[i]) if name == HD_PARENT_ARRAY else ov[i]) for i in keep]
            diffs = [j for j in range(nc) if exp[j] != nv[j]]
            if diffs and name == MODE_ARRAY:
                undeclared = [j for j in diffs
                              if (j, str(exp[j]), str(nv[j])) not in expect_mode]
                for j in diffs:
                    print("%-26s   mode a l'indice %-3d : %s -> %s   %s"
                          % (name, j, exp[j], nv[j],
                             "DECLARE" if j not in undeclared else "NON DECLARE"))
                if undeclared:
                    bad.append("%s: %d changement(s) de mode NON DECLARE(S) aux indices %s "
                               "(indices du NOUVEAU tableau) : --expect-mode-change %s"
                               % (name, len(undeclared), undeclared,
                                  ",".join("%d:%s->%s" % (j, exp[j], nv[j]) for j in undeclared)))
                diffs = undeclared
            elif diffs:
                j = diffs[0]
                bad.append("%s: SUPPRESSION NON PURE — au nouvel indice %d on attendait %s "
                           "(ancien indice %d) et on lit %s, +%d autre(s) ecart(s). La regeneration "
                           "a change autre chose que la suppression demandee."
                           % (name, j, exp[j], keep[j], nv[j], len(diffs) - 1))
            print("%-26s %3d -> %3d   suppression exacte de %s : %s"
                  % (name, oc, nc, drops, "OK" if not diffs else "NON"))
            counts.add(nc)
    for name in (() if drops else ARRAYS):
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
            diffs = [i for i in range(oc) if ov[i] != nv[i]]
            if name == MODE_ARRAY:
                undeclared = [i for i in diffs
                              if (i, str(ov[i]), str(nv[i])) not in expect_mode]
                for i in diffs:
                    print("%-26s   mode a l'indice %-3d : %s -> %s   %s"
                          % (name, i, ov[i], nv[i],
                             "DECLARE" if i not in undeclared else "NON DECLARE"))
                if undeclared:
                    bad.append("%s: %d changement(s) de mode NON DECLARE(S) aux indices %s. Un mode "
                               "ne deplace aucun indice, mais il change comment un joint est "
                               "retargete : declare-le avec "
                               "--expect-mode-change %s"
                               % (name, len(undeclared), undeclared,
                                  ",".join("%d:%s->%s" % (i, ov[i], nv[i]) for i in undeclared)))
            else:
                first = diffs[0] if diffs else None
                bad.append("%s: PAS APPEND-ONLY — l'indice %s change (%s -> %s). Un indice qui "
                           "bouge invalide toutes les references de parent du rig."
                           % (name, first,
                              ov[first] if first is not None else '?',
                              nv[first] if first is not None else '?'))
        counts.add(nc)
        ok = (nc >= oc and nv[:oc] == ov)
        if not ok and name == MODE_ARRAY:
            ok = (nc >= oc and all((i, str(ov[i]), str(nv[i])) in expect_mode
                                   for i in range(oc) if ov[i] != nv[i]))
            print("%-26s %3d -> %3d   append-only %s"
                  % (name, oc, nc, "OK (modes declares)" if ok else "NON"))
        else:
            print("%-26s %3d -> %3d   append-only %s" % (name, oc, nc, "OK" if ok else "NON"))

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
