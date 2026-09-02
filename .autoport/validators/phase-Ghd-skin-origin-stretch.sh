#!/usr/bin/env bash
# PORTE REFONDUE le 2026-09-02 18:25 — troisieme fausse ouverture. Elle comptait les os
# NaN (une cause) ; l'owner voit encore l'etirement (le symptome). On compte maintenant
# L'ETIREMENT LUI-MEME par le code : longueur d'os / longueur de repos, par image.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Ghd-skin-origin-stretch/report.txt
[ -f "$R" ] || { echo "[Ghso FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Ghso FAIL] "+m,file=sys.stderr); sys.exit(1)
st=[kv(l) for l in re.findall(r'^HDSTRETCHCOUNT .*$',t,re.M)]
if not st: F("HDSTRETCHCOUNT absent : compter l'ETIREMENT lui-meme (longueur d'os / repos) par image et par os, pas les NaN — « zero NaN » n'est pas « zero etirement »")
avant=[d for d in st if int(d.get('os_etires',0))>=1 and d.get('plateforme')=='redmi']
if not avant: F("aucune reproduction de l'etirement SUR L'APPAREIL avant correction : sans reproduction rien n'est prouve")
if not re.search(r'^HDATTRIB .*chemin=\S+',t,re.M): F("HDATTRIB absent : pour chaque etirement, publier l'os, la longueur, le point de fuite et le CHEMIN DE CODE qui a produit la matrice")
apres=[d for d in st if int(d.get('os_etires',-1))==0 and d.get('plateforme')=='redmi' and float(d.get('minutes',0))>=10]
if not apres: F("aucune preuve APRES sur le Redmi a ZERO os etire sur >= 10 minutes")
print("[Ghso ok] etirement compte par le code, reproduit sur appareil, attribue, puis zero sur >=10 min")
PY
