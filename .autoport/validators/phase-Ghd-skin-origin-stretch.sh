#!/usr/bin/env bash
# PORTE REFONDUE le 2026-09-02 : on mesure la CAUSE (matrice periment consommee par le
# reciblage), pas le SYMPTOME (etirement d'une fraction de seconde a guetter a l'ecran).
# Trois tentatives et 2 h 30 sans une seule mesure sous l'ancien protocole.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Ghd-skin-origin-stretch/report.txt
[ -f "$R" ] || { echo "[Ghso FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Ghso FAIL] "+m,file=sys.stderr); sys.exit(1)
st=[kv(l) for l in re.findall(r'^HDSTALE .*$',t,re.M)]
if not st: F("HDSTALE absent : compter, PAR IMAGE, les joints servis par une matrice perimee — pas guetter l'etirement a l'ecran")
avant=[d for d in st if int(d.get('images_avec_matrice_perimee',0))>=1]
if not avant: F("aucune reproduction : il faut au moins une mesure AVANT correction avec des images servies par une matrice perimee")
apres=[d for d in st if int(d.get('images_avec_matrice_perimee',-1))==0 and float(d.get('minutes',0))>=5]
if not apres: F("aucune mesure APRES a zero sur >= 5 minutes de jeu")
if not re.search(r'^HDCAUSE .*nommee=\S+',t,re.M): F("HDCAUSE absent : la cause doit etre nommee")
print("[Ghso ok] matrice perimee reproduite puis ramenee a zero sur >=5 min")
PY
