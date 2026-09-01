#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Ghd-skin-origin-stretch/report.txt
[ -f "$R" ] || { echo "[Ghso FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Ghso FAIL] "+m,file=sys.stderr); sys.exit(1)
if not re.search(r'^HDCAUSE .*nommee=\S+',t,re.M): F("HDCAUSE absent : la cause doit etre nommee")
ok=[kv(l) for l in re.findall(r'^HDOK .*$',t,re.M)]
if not ok: F("HDOK absent")
if float(ok[0].get('minutes_de_jeu',0))<10: F(f"{ok[0].get('minutes_de_jeu')} min de jeu, il en faut >= 10")
if int(ok[0].get('episodes',1))!=0: F(f"{ok[0]['episodes']} etirement(s) subsistent")
print("[Ghso ok] cause nommee, 0 etirement sur >=10 min de jeu")
PY
