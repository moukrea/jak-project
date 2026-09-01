#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-foliage-wind3/report.txt
[ -f "$R" ] || { echo "[Gfw3 FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gfw3 FAIL] "+m,file=sys.stderr); sys.exit(1)
n=[kv(l) for l in re.findall(r'^WINDNATIVE .*$',t,re.M)]
if not n or n[0].get('joue')!='1': F("la brise d'ORIGINE ne joue toujours pas (les twitchs viennent de la)")
c=[kv(l) for l in re.findall(r'^WINDCOVER .*$',t,re.M)]
if not c or c[0].get('arbres_avec_vent')!=c[0].get('arbres_total'): F("tous les arbres ne sont pas impactes")
a=[kv(l) for l in re.findall(r'^WINDAMP .*$',t,re.M)]
if not a or float(a[0]['amplitude_apres'])>float(a[0]['cible']): F("toujours une tempete, pas une brise")
print("[Gfw3 ok] brise native jouante, couverture complete, amplitude calmee")
PY
