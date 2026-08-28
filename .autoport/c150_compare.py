#!/usr/bin/env python3
"""c150_compare.py — juge les predictions P1..P9 du cycle 150 sur les DEUX tableaux.

NATURE : ce script ne mesure rien lui-meme. Il LIT deux tableaux de salle deja produits et
compare, ligne a ligne, les grandeurs que `.autoport/c150-predictions.txt` a nommees AVANT
l'edition et AVANT la course. Aucun seuil n'est defini ici : ils viennent tous du fichier de
predictions, recopies en tete de ce fichier pour etre lisibles d'un coup d'oeil.

REPERE : celui de chaque ligne du tableau, inchange — on ne reprojette rien.
USAGE : c150_compare.py <table_AVANT> <table_APRES>
"""
import re
import subprocess
import sys

AV, AP = sys.argv[1], sys.argv[2]

# --- les seuils, recopies de .autoport/c150-predictions.txt ------------------------------------
CWS = {"chestL": 0.5720, "chestR": 0.5450}          # PHYSGRADSET, trace :3140 / :3150
TOL_P1 = 0.005                                       # +/- 0,5 % sur le facteur 1/cws
SEUIL_P4 = {"chestL": 0.30, "chestR": 0.60}          # points de % W0, hausse MINIMALE exigee
TOL_P6 = 0.02                                        # B0, clause « vers thorax »
PLAFOND_SKINPEN = 0.0883                             # ligne de base au repos PIRE-DES-DEUX

verdicts = []


def dire(nom, ok, txt):
    verdicts.append((nom, ok))
    print(f"{'TENUE   ' if ok else 'REFUTEE '} {nom} : {txt}")


def lire(p):
    return open(p, encoding="utf-8", errors="replace").read().split("\n")


av, ap = lire(AV), lire(AP)

print("== provenance ==")
for p in (AV, AP):
    print(subprocess.run(["md5sum", p], capture_output=True, text=True).stdout.strip())

# --- P1 + P2 : les 22 lignes OPERATEURS, valeur par valeur -------------------------------------
RE_OP = re.compile(
    r"^ROOM-SPEC10: (chest[LR])\s+OPERATEURS i=(\d+)\s+"
    r"l=0 mur=\s*([+-][\d.]+) u anc=\s*([+-][\d.]+) u grw=([\d.]+)\s+"
    r"l=1 mur=\s*([+-][\d.]+) u anc=\s*([+-][\d.]+) u grw=([\d.]+)")


def ops(lines):
    out = {}
    for l in lines:
        m = RE_OP.match(l)
        if m:
            out[(m.group(1), int(m.group(2)))] = (float(m.group(3)), float(m.group(6)), l)
    return out


oav, oap = ops(av), ops(ap)
if not oav or not oap:
    dire("P1", False, f"lignes OPERATEURS introuvables (avant={len(oav)} apres={len(oap)})")
else:
    ecarts, nnz, bad = [], 0, []
    for k in sorted(set(oav) & set(oap)):
        ch = k[0]
        cible = 1.0 / CWS[ch]
        for li in (0, 1):
            a, b = oav[k][li], oap[k][li]
            if abs(a) > 1e-9:
                nnz += 1
                r = b / a
                ecarts.append((k, li, a, b, r))
                if abs(r / cible - 1.0) > TOL_P1:
                    bad.append((k, li, a, b, r, cible))
    print(f"\n   -- P1 detail ({nnz} valeurs non nulles avant) --")
    for k, li, a, b, r in ecarts:
        print(f"      {k[0]} i={k[1]:<2} l={li}  {a:9.3f} -> {b:9.3f}   x{r:.5f}  "
              f"(cible x{1.0/CWS[k[0]]:.5f})")
    dire("P1", nnz > 0 and not bad,
         f"{nnz - len(bad)}/{nnz} valeurs non nulles au facteur 1/cws a +/-0,5 %"
         + ("" if not bad else f" — HORS : {bad}"))

    # P2 : confinement CAUSAL — les cellules a mur nul sont identiques AU CARACTERE
    zero_keys = [k for k in sorted(set(oav) & set(oap))
                 if abs(oav[k][0]) < 1e-9 and abs(oav[k][1]) < 1e-9]
    diff = [k for k in zero_keys if oav[k][2] != oap[k][2]]
    dire("P2", len(zero_keys) > 0 and not diff,
         f"{len(zero_keys) - len(diff)}/{len(zero_keys)} cellules a mur nul identiques AU CARACTERE"
         + ("" if not diff else f" — ONT BOUGE : {diff}"))

# --- P3 : pose d'auteur ------------------------------------------------------------------------
def prem(lines, pref):
    for l in lines:
        if l.startswith(pref):
            return l
    return None


ia, ib = prem(av, "ROOM-IDLE:"), prem(ap, "ROOM-IDLE:")
dire("P3", ia is not None and ia == ib, f"avant [{ia}] / apres [{ib}]")

# --- P4 + P5 : la clause porteuse de §10 -------------------------------------------------------
RE_LIV = re.compile(r"^ROOM-SPEC10: (chest[LR])\s+sortant\s+ORGANE LIVRE.*?: "
                    r"frontieres ([+-][\d.]+)/([+-][\d.]+)/([+-][\d.]+) % W0 -> (\S+)")


def livre(lines):
    out = {}
    for l in lines:
        m = RE_LIV.match(l)
        if m:
            out[m.group(1)] = ([float(m.group(i)) for i in (2, 3, 4)], m.group(5))
    return out


lav, lap = livre(av), livre(ap)
if len(lav) != 2 or len(lap) != 2:
    dire("P4", False, f"ORGANE LIVRE introuvable (avant={list(lav)} apres={list(lap)})")
else:
    ok4, det = True, []
    for ch in ("chestL", "chestR"):
        a, b = lav[ch][0][0], lap[ch][0][0]          # frontiere w>0.00, celle du verdict
        d = b - a
        if d < SEUIL_P4[ch]:
            ok4 = False
        det.append(f"{ch} {a:+.3f} -> {b:+.3f} (delta {d:+.3f}, seuil +{SEUIL_P4[ch]:.2f})")
    dire("P4", ok4, " · ".join(det))
    dire("P5", all(lap[c][1] == "SOUS" for c in lap),
         "verdicts sortant : " + " · ".join(f"{c}={lap[c][1]}" for c in sorted(lap))
         + "  (P5 predisait SOUS sur les deux : aucun changement de statut reclame)")

# --- P6 : orthogonalite ------------------------------------------------------------------------
RE_THX = re.compile(r"^ROOM-SPEC10: (chest[LR])\s+vers thorax bande [\d.-]+ B0\s+"
                    r"AU COMPTE DE SOMMETS \(VERDICT\) frontieres ([\d.]+)/([\d.]+)/([\d.]+)")


def thx(lines):
    out = {}
    for l in lines:
        m = RE_THX.match(l)
        if m:
            out[m.group(1)] = [float(m.group(i)) for i in (2, 3, 4)]
    return out


tav, tap = thx(av), thx(ap)
if len(tav) != 2 or len(tap) != 2:
    dire("P6", False, f"« vers thorax » introuvable (avant={list(tav)} apres={list(tap)})")
else:
    pires = {c: max(abs(x - y) for x, y in zip(tav[c], tap[c])) for c in tav}
    dire("P6", all(v <= TOL_P6 for v in pires.values()),
         " · ".join(f"{c} pire ecart {v:.4f} B0" for c, v in sorted(pires.items()))
         + f"  (seuil {TOL_P6} B0)")

# --- P7 : la gate COLLIDE ----------------------------------------------------------------------
RE_SKIN = re.compile(r"^ROOM-SKINPEN-DETAIL: chain=(chest[LR])\s+skinpen=([\d.]+) m\s+"
                     r"meshpen=([\d.]+) m\s+repos=([\d.]+) m")


def skin(lines):
    out = {}
    for l in lines:
        m = RE_SKIN.match(l)
        if m:
            out[m.group(1)] = (float(m.group(2)), float(m.group(3)), float(m.group(4)))
    return out


sav, sap = skin(av), skin(ap)
if len(sap) != 2:
    dire("P7", False, "ROOM-SKINPEN-DETAIL illisible dans le tableau APRES — a lire a la main")
else:
    det = []
    for c in sorted(sap):
        sk, me, rp = sap[c]
        ska = sav.get(c, (float("nan"),) * 3)[0]
        det.append(f"{c} skinpen {ska:.4f} -> {sk:.4f} (plancher PROPRE {rp:.4f}"
                   f"{'  DEPASSE' if sk > rp else ''}) meshpen {sav.get(c,(0,0,0))[1]:.4f} -> {me:.4f}")
    dire("P7", all(v[0] <= PLAFOND_SKINPEN for v in sap.values()),
         " · ".join(det) + f"  [gate PIRE-DES-DEUX {PLAFOND_SKINPEN}]")

# --- P8 / P9 -----------------------------------------------------------------------------------
n = len(open("goal_src/jak1/pc/jak-hd-physics.gc", encoding="utf-8").readlines())
dire("P8", n <= 4793, f"{n} lignes (predit <= 4793, plafond CLEAN 4800)")
md5 = subprocess.run(["md5sum", "recharged_assets/physics_chains.txt"],
                     capture_output=True, text=True).stdout.split()[0]
dire("P9", md5 == "0bf4d3130392da1252d7bc0743cdf93b", f"physics_chains.txt md5 {md5}")

# --- DIAGNOSTIC (NON PRE-SPECIFIE, ecrit pendant la course, corroboration de P2) ---------------
# Lecon du cycle 148 : une fenetre TEMOIN qui ne recoit aucun pilotage avait vu son apex x5,07.
# Le regime r=0 est debout sans pilotage : `sx = 1` donc `mww = 0`, donc il doit etre IDENTIQUE.
RE_AR = re.compile(r"^ROOM-APEX-REGIME: (chest[LR])\s+r=\s*0 ")
ta = [l for l in av if RE_AR.match(l)]
tb = [l for l in ap if RE_AR.match(l)]
print("\n== DIAGNOSTIC temoin r=0 (non pre-specifie — corroboration de P2) ==")
for x, y in zip(ta, tb):
    print(f"   {'IDENTIQUE' if x == y else 'A BOUGE  '}  avant: {x.strip()[:96]}")
    if x != y:
        print(f"                apres: {y.strip()[:96]}")

# --- rayon d'action : ce qui a bouge dans le tableau, par BLOC (jamais par sous-chaine) ---------
na, nb = len(av), len(ap)
if na == nb:
    ch = [i for i in range(na) if av[i] != ap[i]]
    pref = {}
    for i in ch:
        k = av[i].split(":")[0][:34] if ":" in av[i] else av[i][:34].strip() or "(indentee)"
        pref[k] = pref.get(k, 0) + 1
    print(f"\n== rayon d'action : {len(ch)} lignes differentes sur {na} ==")
    for k, v in sorted(pref.items(), key=lambda x: -x[1])[:25]:
        print(f"   {v:6d}  {k}")
else:
    print(f"\n== tableaux de longueurs differentes : {na} vs {nb} lignes ==")

t = sum(1 for _, o in verdicts if o)
print(f"\n==== {t}/{len(verdicts)} predictions TENUES ====")
for nom, o in verdicts:
    print(f"   {nom} {'TENUE' if o else 'REFUTEE'}")
sys.exit(0)
