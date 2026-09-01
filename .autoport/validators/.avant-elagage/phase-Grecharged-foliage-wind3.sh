#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-foliage-wind3/report.txt
[ -f "$R" ] || { echo "[Gfw3 FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*FOLIAGE WIND SANE[[:space:]]*$' "$R" || { echo "[Gfw3 FAIL] RESULT: FOLIAGE WIND SANE absent" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gfw3 FAIL] "+m,file=sys.stderr); sys.exit(1)
n=[kv(l) for l in re.findall(r'^WINDNATIVE .*$',t,re.M)]
if not n: F("WINDNATIVE absent : la brise d'ORIGINE, option eteinte, doit etre prouvee saine AVANT tout reglage")
if n[0].get('joue')!='1': F("l'animation native ne JOUE pas (joue=0) : c'est le defaut D1, les twitchs viennent de la")
if float(n[0].get('amplitude_moy',0))<=0: F("amplitude native nulle : l'animation ne bouge pas")
c=[kv(l) for l in re.findall(r'^WINDCOVER .*$',t,re.M)]
if not c: F("WINDCOVER absent")
if c[0].get('arbres_avec_vent')!=c[0].get('arbres_total'):
    F(f"{c[0].get('arbres_avec_vent')} arbres sur {c[0].get('arbres_total')} recoivent du vent — l'owner : « tous les arbres ne sont pas impactés »")
a=[kv(l) for l in re.findall(r'^WINDAMP .*$',t,re.M)]
if not a: F("WINDAMP absent")
av,ap,ci=float(a[0]['amplitude_avant']),float(a[0]['amplitude_apres']),float(a[0]['cible'])
if ap>ci: F(f"amplitude apres {ap} > cible {ci} : toujours une tempete")
if ci>=av: F(f"cible {ci} >= amplitude avant {av} : rien n'a ete calme, l'owner demandait une LEGERE brise")
print("[Gfw3 ok] brise native saine, couverture complete, amplitude ramenee sous la cible")
PY
