#!/usr/bin/env bash
# REFONDUE 2026-09-03 apres « tres tres mauvais ». La precedente s'ouvrait sur joue=1 et
# arbres_avec_vent==total : une animation qui joue FAUX et un recensement faux passaient.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-foliage-wind3/report.txt
[ -f "$R" ] || { echo "[Gfw3 FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gfw3 FAIL] "+m,file=sys.stderr); sys.exit(1)
# D1 : natif compare a la REFERENCE stock, pas juste « ca joue »
n=[kv(l) for l in re.findall(r'^WINDNATIVEREF .*$',t,re.M)]
if not n: F("WINDNATIVEREF absent : comparer le natif (option OFF) au chemin STOCK du moteur — amplitude, frequence, forme — pas seulement verifier qu'il joue")
if float(n[0].get('ecart_pct',99))>1.0: F(f"natif a {n[0].get('ecart_pct')} % du stock : « toujours pas carré comparé à la PS2 »")
# D5 : pivot a la base
pv=[kv(l) for l in re.findall(r'^WINDPIVOT .*$',t,re.M)]
if not pv or float(pv[0].get('deplacement_base_max_cm',99))>0.5: F("les shrubs GLISSENT : le pivot doit etre la base de la plante, deplacement de la base = 0")
# D2/D3 : couverture par instance dessinee, exclus nommes, paires identiques expliquees
c=[kv(l) for l in re.findall(r'^WINDCOVER .*$',t,re.M)]
if not c: F("WINDCOVER absent")
for d in c:
    if d.get('instances_avec_vent')!=d.get('instances_dessinees'): F(f"{d.get('lev')} : {d.get('instances_avec_vent')}/{d.get('instances_dessinees')} instances DESSINEES recoivent du vent (compte par instance, pas par modele)")
if not re.search(r'^WINDPAIRS .*paires_identiques_divergentes=0\b',t,re.M):
    F("WINDPAIRS : « deux identiques côté à côte, un pris l'autre non » — publier chaque paire divergente et la cause, attendu 0")
# D4 : forme = brise, pas sinusoide
sp=[kv(l) for l in re.findall(r'^WINDSPECTRUM .*$',t,re.M)]
if not sp: F("WINDSPECTRUM absent : le spectre du deplacement d'un sommet distingue une brise (large, enveloppe variable) d'une ondulation sous-marine (une frequence)")
if float(sp[0].get('part_pic_dominant_pct',100))>40: F(f"{sp[0].get('part_pic_dominant_pct')} % de l'energie sur UNE frequence : c'est l'« ondulation sous l'eau », pas une brise")
print("[Gfw3 ok] natif conforme au stock, pivot a la base, couverture par instance complete, paires identiques coherentes, spectre de brise")
PY
