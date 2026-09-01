#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gcutscene-npc-flicker/report.txt
[ -f "$R" ] || { echo "[Gcnf FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*NPC STABLE[[:space:]]*$' "$R" || { echo "[Gcnf FAIL] RESULT: NPC STABLE absent" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gcnf FAIL] "+m,file=sys.stderr); sys.exit(1)
fl=[kv(l) for l in re.findall(r'^NPCFLICK .*$',t,re.M)]
if len({d.get('scene') for d in fl})<3: F("moins de 3 scenes couvertes : le defaut doit etre reproduit largement, pas sur une scene")
if not any(int(d.get('cycles',0))>=1 for d in fl): F("aucun cycle apparition/disparition reproduit : sans reproduction rien n'est prouve")
if not re.search(r'^NPCPRIOR .*pourquoi_pas_tenu=\S+',t,re.M):
    F("NPCPRIOR absent : l'owner dit « c'est pas la première fois » — il faut NOMMER les corrections precedentes et dire pourquoi elles n'ont pas tenu")
if not re.search(r'^NPCGUARD .*echoue_si=\S+',t,re.M):
    F("NPCGUARD absent : sans garde de non-regression ce defaut reviendra une troisieme fois")
ok=[kv(l) for l in re.findall(r'^NPCOK .*$',t,re.M)]
if not ok: F("NPCOK absent")
if int(ok[0].get('scenes',0))<3: F(f"{ok[0].get('scenes')} scenes verifiees, il en faut >= 3")
if int(ok[0].get('cycles',1))!=0: F(f"{ok[0]['cycles']} cycle(s) subsistent")
print("[Gcnf ok] >=3 scenes, corrections passees expliquees, garde de non-regression posee, 0 cycle")
PY
