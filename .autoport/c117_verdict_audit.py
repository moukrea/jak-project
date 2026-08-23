#!/usr/bin/env python3
"""
CYCLE 117 — AUDIT : UNE LIGNE DE VERDICT CONTRE SES PROPRES DONNEES.

DIRECTIVES vd9e8b66782

POURQUOI CE SCRIPT EXISTE. Le cycle 116 a arme la sommation compensee : la queue des series de
§27, qui etait GELEE AU BIT, s'est mise a bouger. Le bloc `ROOM-AXC-SETTLE` du tableau publie ses
COLONNES depuis la donnee courante, mais sa ligne de VERDICT est restee sur la phrase d'avant. La
regle du 2026-08-19 23:50 est explicite : « Un correctif d'instrument s'arrete quand la LIGNE DE
VERDICT lit la nouvelle donnee — pas quand la donnee existe. »

NATURE / REPERE DES GRANDEURS LUES ICI. Toutes viennent des colonnes de `ROOM-AXC-SETTLE`, qui
sont des DEVIATIONS ANGULAIRES du maillon RELATIVEMENT A SON PARENT (repere de l'ancre), lues sur
les fenetres a entree propre de PH-AXC. `a0` est l'amplitude de reference (max des 5 premiers
echantillons — une convention de l'instrument, pas une ligne de la spec) ; `offset` est la moyenne
des 30 dernieres frames ; `sigma30` leur ecart-type. Les quatre durees sont, pour chaque etape de
§27, le DERNIER instant ou |v| depasse le niveau d'entree de l'etape.

CE QUE LE SCRIPT REND. Le recomptage des trois faits que la ligne de verdict affirme, contre les
lignes qu'elle resume. Il ne lit AUCUNE trace : uniquement le tableau, donc il est verifiable par
quiconque relit le meme fichier.
"""
import sys, math

TBL = sys.argv[1] if len(sys.argv) > 1 else \
    ".autoport/reports/Grecharged-secondary-motion/keira-room-table.txt"

F24, Z25 = 2.30, 0.35                      # §24 verticale · §25 zeta — aucun des deux n'est de moi
ZW = Z25 * 2.0 * math.pi * F24
ST = [('reponse visible dominante', 0.3, 0.6), ('mouvement secondaire', 0.6, 1.2),
      ('mostly settled', 1.0, 1.5), ('essentially stationary', 1.3, 1.7)]

rows = []
for l in open(TBL, errors='ignore'):
    if l.startswith('ROOM-AXC-SETTLE: '):
        f = l.split()
        rows.append(dict(ch=f[1], l=int(f[2]), ax=f[3], a0=float(f[4]), mo=float(f[5]),
                         pct=float(f[6].rstrip('%')), sd=float(f[7]), t=f[8:12]))
if not rows:
    print("AUCUNE ligne ROOM-AXC-SETTLE dans", TBL); sys.exit(1)

print("=" * 100)
print("CYCLE 117 — `ROOM-AXC-SETTLE-VERDICT` CONTRE LES LIGNES QU'IL RESUME")
print("=" * 100)
for nm, t0, t1 in ST:
    print(f"   niveau d'entree de « {nm:26s} » ({t0}-{t1} s) = {100*math.exp(-ZW*t0):8.4f} %")
lvl4 = 100.0 * math.exp(-ZW * ST[-1][1])
print()
print(f"{'serie':22s} {'a0':>9s} {'off/a0 %':>9s} {'sd/a0 %':>9s} {'sd<=5%off':>10s} {'etape 4':>10s}")
n_sd0 = n_still = n_reach = n_band = 0
dec, bru, rea = [], [], []
for r in rows:
    sd_a0 = 100 * r['sd'] / r['a0']
    still = (r['sd'] <= 0.05 * abs(r['mo'])) if r['mo'] else (r['sd'] == 0.0)
    t4 = r['t'][3]
    reach = not t4.startswith('>')
    n_sd0 += (r['sd'] == 0.0); n_still += still; n_reach += reach
    key = f"{r['ch']} l={r['l']} {r['ax']}"
    if reach:
        v = float(t4.rstrip('!~')); inb = ST[-1][1] <= v <= ST[-1][2]; n_band += inb
        rea.append((key, v, inb))
    else:
        (dec if r['pct'] > lvl4 else bru).append((key, r['pct'], sd_a0))
    print(f"{key:22s} {r['a0']:9.5f} {r['pct']:9.3f} {sd_a0:9.4f} {str(still):>10s} {t4:>10s}")

n = len(rows)
print()
print("-- CE QUE LA LIGNE DE VERDICT AFFIRMAIT (texte du cycle 113, imprime jusqu'au cycle 116) --")
print(f"   « les {n} series ont un sigma30 NUL AU BIT PRES — aucune ne sonne encore »")
print(f"   « sur ces {n}, 1 porte un decalage SUPERIEUR au niveau ; les {n-1} autres l'atteignent »")
print( "   « ... et elles l'atteignent TOT (1,033 et 1,100 s pour une fenetre 1,3-1,7 s) »")
print()
print("-- CE QUE SES PROPRES COLONNES DISENT --")
print(f"   sigma30 EXACTEMENT nul                       : {n_sd0}/{n}")
print(f"   `sigma30 <= 5 % du decalage` (l'ancienne garde): {n_still}/{n}")
print(f"   decalage final AU-DESSUS du niveau ({lvl4:.4f} %) : {len(dec)}/{n}")
print(f"   etape 4 REELLEMENT atteinte                  : {n_reach}/{n}"
      f"   dont DANS la fenetre 1,3-1,7 s : {n_band}/{n}")
print(f"   jamais atteinte (`>fin`)                     : {n - n_reach}/{n}")
print()
print("-- LES TROIS CATEGORIES, EXCLUSIVES ET EXHAUSTIVES --")
print(f"   (a) INATTEIGNABLE PAR LE DECALAGE  : {len(dec)}  " +
      " · ".join(f"{k} ({p:.3f} %)" for k, p, _ in dec))
print(f"   (b) INATTEIGNABLE PAR LE BRUIT     : {len(bru)}  " +
      " · ".join(f"{k} (off {p:.3f} %, sd {s:.3f} %)" for k, p, s in bru))
print(f"   (c) ATTEINTE                       : {len(rea)}  " +
      " · ".join(f"{k} {v:.3f} s{' DANS' if b else ' HORS'}" for k, v, b in rea))
print()
print("-- LA CAUSE, ET ELLE EST MECANIQUE --")
print("   `_unreach` etait garde par `sigma30 <= 5 % du decalage`. Tant que la queue etait gelee")
print("   au bit (avant le cycle 116) la garde etait vraie PARTOUT et le compte etait juste. Des")
print("   que la sommation compensee a rendu la queue mobile, la garde est tombee a"
      f" {n_still}/{n},")
print(f"   le compte des « inatteignables » est passe a {n_still}, et le bloc a declare ATTEINTES")
print(f"   {n - n_still} series dont {n - n_reach} affichent `>fin` DANS SA PROPRE COLONNE.")
print("   Une precondition de garde qui inverse le SENS d'un verdict quand la donnee change est la")
print("   meme faute que `gate-behind-an-always-failing-gate`.")
