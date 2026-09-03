#!/usr/bin/env python3
"""physics_ab_table.py — compare DEUX tableaux de la salle, ligne a ligne, sur les grandeurs
qui decident un cycle. A = reference, B = essai.

Il ne conclut rien : il pose les deux colonnes cote a cote et marque ce qui casse une regle
ecrite du contrat (plancher a 60 %, plancher faible-stimulus a 70 %, allongement d'os a 3 %,
gradient croissant de la racine vers la pointe).

  usage: physics_ab_table.py A.txt B.txt
"""
import re
import sys


def rows(path):
    """tipvar max par chaine (ce que lit la gate FLOOR) et par (chaine, drive)."""
    per, perdrive = {}, {}
    for ln in open(path, errors="ignore"):
        if not ln.startswith("row "):
            continue
        d = dict(re.findall(r"(\w+)=([^\s]+)", ln))
        if "chain" not in d or "tipvar" not in d:
            continue
        v = float(d["tipvar"])
        per[d["chain"]] = max(per.get(d["chain"], 0.0), v)
        k = (d["chain"], d.get("drive", "?"))
        perdrive[k] = max(perdrive.get(k, 0.0), v)
    return per, perdrive


def keyed(path, tag, key, fields):
    """toutes les lignes ROOM-<tag>, indexees par le tuple `key`."""
    out = {}
    for ln in open(path, errors="ignore"):
        if not ln.startswith("ROOM-%s:" % tag):
            continue
        d = dict(re.findall(r"(\w+)=([^\s]+)", ln))
        if all(k in d for k in key):
            out[tuple(d[k] for k in key)] = {f: d.get(f) for f in fields}
    return out


def weak(path):
    """reponse au PLUS FAIBLE stimulus, exactement comme la gate FLOOR-WEAK la lit."""
    cur = {}
    for ln in open(path, errors="ignore"):
        if not ln.startswith("ROOM-RESPONSE"):
            continue
        d = dict(re.findall(r"(\w+)=([^\s]+)", ln))
        if {"chain", "stimulus", "tip"} <= set(d):
            c, st, tp = d["chain"], float(d["stimulus"]), float(d["tip"])
            if c not in cur or st < cur[c][0]:
                cur[c] = (st, tp)
    return {c: v[1] for c, v in cur.items()}


def scalar(path, tag, field):
    m = re.search(r"^ROOM-%s:.*\b%s=([0-9.eE+-]+)" % (tag, field), open(path, errors="ignore").read(), re.M)
    return float(m.group(1)) if m else None


def main():
    A, B = sys.argv[1], sys.argv[2]
    pa, pda = rows(A)
    pb, pdb = rows(B)

    print("== GRADIENT (deviation angulaire RELATIVE AU PARENT, degres ; doit CROITRE) ==")
    ga = keyed(A, "GRADIENT", ("chain", "drive"), ("link0", "link1", "link2"))
    gb = keyed(B, "GRADIENT", ("chain", "drive"), ("link0", "link1", "link2"))
    inv_a = inv_b = tot = 0
    for k in sorted(set(ga) & set(gb)):
        va = [float(ga[k][f]) for f in ("link1", "link2") if ga[k].get(f)]
        vb = [float(gb[k][f]) for f in ("link1", "link2") if gb[k].get(f)]
        if len(va) < 2 or len(vb) < 2:
            continue
        tot += 1
        ia, ib = va[1] < va[0], vb[1] < vb[0]
        inv_a += ia
        inv_b += ib
        print("  %-9s %-10s A %7.2f/%7.2f %s   B %7.2f/%7.2f %s"
              % (k[0], k[1], va[0], va[1], "INVERSE" if ia else "ok   ",
                 vb[0], vb[1], "INVERSE" if ib else "ok"))
    if tot:
        print("  couples inverses : A %d/%d   B %d/%d" % (inv_a, tot, inv_b, tot))

    print("\n== PLANCHER DE MOUVEMENT (tipvar max ; gate FLOOR casse sous 60 %%) ==")
    for c in sorted(set(pa) & set(pb)):
        r = pb[c] / pa[c] if pa[c] else 0.0
        flag = "  <<< SOUS LE PLANCHER" if r < 0.60 else ""
        if abs(r - 1.0) > 0.02 or flag:
            print("  %-11s %.4f -> %.4f   x%.2f%s" % (c, pa[c], pb[c], r, flag))

    print("\n== PLANCHER FAIBLE-STIMULUS (gate FLOOR-WEAK casse sous 70 %%) ==")
    wa, wb = weak(A), weak(B)
    for c in sorted(set(wa) & set(wb)):
        r = wb[c] / wa[c] if wa[c] else 0.0
        flag = "  <<< SOUS LE PLANCHER" if r < 0.70 else ""
        if abs(r - 1.0) > 0.02 or flag:
            print("  %-11s %.4f -> %.4f   x%.2f%s" % (c, wa[c], wb[c], r, flag))

    print("\n== GELEE (periode en frames ; 2 frames = un basculement, pas de la physique) ==")
    ja = keyed(A, "JELLY", ("chain", "drive"), ("ratio", "period"))
    jb = keyed(B, "JELLY", ("chain", "drive"), ("ratio", "period"))
    for k in sorted(set(ja) & set(jb)):
        if ja[k].get("period") in (None, "-") or jb[k].get("period") in (None, "-"):
            continue          # `ratio=-` : la ligne ne permet aucune conclusion, elle le dit
        a_, b_ = float(ja[k]["period"]), float(jb[k]["period"])
        if a_ < 5.0 or b_ < 5.0 or abs(b_ - a_) > 1.0:
            print("  %-9s %-10s periode %6.2f -> %6.2f" % (k[0], k[1], a_, b_))

    print("\n== AFFAISSEMENT GRAVITAIRE (sag, deplacement soutenu a 60 deg) ==")
    sa = keyed(A, "GRAVSAG", ("chain",), ("sag", "sagn"))
    sb = keyed(B, "GRAVSAG", ("chain",), ("sag", "sagn"))
    for k in sorted(set(sa) & set(sb)):
        a_, b_ = float(sa[k]["sag"]), float(sb[k]["sag"])
        if abs(b_ - a_) > 0.002:
            print("  %-11s %.4f -> %.4f  (sagn %s -> %s)"
                  % (k[0], a_, b_, sa[k]["sagn"], sb[k]["sagn"]))

    print("\n== LES DEUX INVARIANTS DURS ==")
    for tag, field, cap in (("STRETCH", "max", 0.03), ("IDLE", "maxdev", 1.0)):
        a_, b_ = scalar(A, tag, field), scalar(B, tag, field)
        if a_ is not None and b_ is not None:
            print("  ROOM-%-8s %.4f -> %.4f   (plafond %.2f)%s"
                  % (tag, a_, b_, cap, "   <<< DEPASSE" if b_ > cap else ""))
    for tag in ("SIDE", "POSCONTROL", "SELFCOL"):
        for p, nm in ((A, "A"), (B, "B")):
            m = re.search(r"^ROOM-%s:.*$" % tag, open(p, errors="ignore").read(), re.M)
            if m:
                print("  %s %s" % (nm, m.group(0)[:104]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
