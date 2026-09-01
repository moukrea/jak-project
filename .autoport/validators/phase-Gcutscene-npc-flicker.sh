#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gcutscene-npc-flicker/report.txt
[ -f "$R" ] || { echo "[Gcnf FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gcnf FAIL] "+m,file=sys.stderr); sys.exit(1)
if not re.search(r'^NPCGUARD .*echoue_si=\S+',t,re.M):
    F("NPCGUARD absent : ce defaut est DEJA revenu une fois, sans garde il reviendra encore")
ok=[kv(l) for l in re.findall(r'^NPCOK .*$',t,re.M)]
if not ok: F("NPCOK absent")
if int(ok[0].get('scenes',0))<3: F(f"{ok[0].get('scenes')} scenes verifiees, il en faut >= 3")
if int(ok[0].get('cycles',1))!=0: F(f"{ok[0]['cycles']} clignotement(s) subsistent")
print("[Gcnf ok] 0 clignotement sur >=3 scenes, garde de non-regression posee")
PY
