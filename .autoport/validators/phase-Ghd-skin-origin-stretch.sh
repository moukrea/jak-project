#!/usr/bin/env bash
# PORTE AJUSTEE le 2026-09-02 08:10. J'avais impose un format de mesure (HDSTALE) DEUX
# MINUTES APRES que le worker eut produit la preuve sous une autre forme, meilleure :
# correlation parfaite entre distance a l'origine et longueur d'etirement (r2=1,000000
# sur 42 points), barycentre des os en fuite a l'origine, et cause nommee. Faire refaire
# ce travail pour satisfaire un format que j'ai choisi apres coup serait du gaspillage.
# La porte accepte donc l'UNE OU L'AUTRE preuve de reproduction, et exige dans tous les
# cas la cause nommee et un compte a ZERO apres correction.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Ghd-skin-origin-stretch/report.txt
[ -f "$R" ] || { echo "[Ghso FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Ghso FAIL] "+m,file=sys.stderr); sys.exit(1)
# --- reproduction : soit le compte de matrices perimees, soit la correlation distance/longueur
stale=[kv(l) for l in re.findall(r'^HDSTALE .*$',t,re.M)]
corr =[kv(l) for l in re.findall(r'^HDCORREL .*$',t,re.M)]
repro_stale = any(int(d.get('images_avec_matrice_perimee',0))>=1 for d in stale)
repro_corr  = any(float(d.get('r2',0))>=0.8 and int(d.get('n',0))>=20 for d in corr)
if not (repro_stale or repro_corr):
    F("aucune reproduction : il faut soit des images servies par une matrice perimee, soit la correlation distance/longueur (n>=20, r2>=0,8)")
if not re.search(r'^HDCAUSE .*nommee=\S+',t,re.M): F("HDCAUSE absent : la cause doit etre nommee")
# --- apres correction : plus rien, sous l'une ou l'autre metrique
ok_stale = any(int(d.get('images_avec_matrice_perimee',-1))==0 and float(d.get('minutes',0))>=5 for d in stale)
hdok=[kv(l) for l in re.findall(r'^HDOK .*$',t,re.M)]
ok_ep = any(int(d.get('episodes',-1))==0 and float(d.get('minutes_de_jeu',0))>=5 for d in hdok)
if not re.search(r'^HD(OK|STALE) .*plateforme=redmi',t,re.M):
    F("la preuve APRES correction doit etre prise sur l'APPAREIL avec les modeles HD installes — l'owner voit encore le defaut, une preuve x86 ne vaut rien ici")
if not (ok_stale or ok_ep):
    F("aucune preuve APRES correction : zero image a matrice perimee, ou zero etirement, sur >= 5 minutes de jeu")
print("[Ghso ok] defaut reproduit et mesure, cause nommee, zero apres correction sur >=5 min")
PY
