#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gfixed-tick-anim-interp/report.txt
[ -f "$R" ] || { echo "[Gfta FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gfta FAIL] "+m,file=sys.stderr); sys.exit(1)
j=[kv(l) for l in re.findall(r'^ANIMJIT .*$',t,re.M)]
hi=[d for d in j if float(d.get('fps',0))>60]
if not hi: F("aucune mesure au-dessus de 60 img/s : c'est la que le jitter se voit")
for f in {d['fps'] for d in hi}:
    on=[d for d in hi if d['fps']==f and d.get('arme')=='1']; off=[d for d in hi if d['fps']==f and d.get('arme')=='0']
    if on and off and float(on[0]['ecart_max'])*2 > float(off[0]['ecart_max']):
        F(f"a {f} img/s le jitter n'est pas divise par 2 ({on[0]['ecart_max']} contre {off[0]['ecart_max']})")
b=[kv(l) for l in re.findall(r'^ANIM60 .*$',t,re.M)]
if not b or b[0].get('identique_au_bit')!='1': F("a 60 img/s le comportement doit rester identique au bit")
print("[Gfta ok] jitter divise par >=2 en haute cadence, 60 fps inchange")
PY
