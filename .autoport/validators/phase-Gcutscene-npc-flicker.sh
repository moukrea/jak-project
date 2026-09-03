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
# SCENE IMPOSEE (owner 2026-09-01) : la porte precedente a ete satisfaite sur 3 scenes qui
# n'etaient PAS celle qui echoue. Un compte de scenes ne vaut rien sans le cas nomme.
if not re.search(r'^NPC(FLICK|OK) .*plateforme=redmi',t,re.M):
    F("aucune mesure SUR L'APPAREIL : la porte du 02/09 s'est ouverte sur une preuve PC pendant que l'owner voyait le defaut — preuve Redmi exigee, modeles HD installes")
if not re.search(r'(?i)^NPCFLICK .*scene=\S*mayor\S* .*pnj=mayor',t,re.M):
    F("le MAIRE lui-meme n'est pas suivi dans sa propre cinematique (les lignes precedentes listaient Daxter, la lampe et les engrenages)")
if not re.search(r'^NPCCULL .*dans_frustum_et_culled=0\b',t,re.M):
    F("NPCCULL : le maire portait culled=1 dans sa scene avec cycles=0 — un PNJ ecarte du rendu PENDANT qu'il est dans le champ EST un clignotement, pas une exclusion justifiee ; attendu 0 sur l'appareil")
if not re.search(r'(?i)^NPC(FLICK|OK) .*(maire|mayor)',t,re.M):
    F("la premiere cinematique du MAIRE n'est pas couverte — c'est le pire cas nomme par l'owner, une preuve sans elle est refusee")
if int(ok[0].get('cycles',1))!=0: F(f"{ok[0]['cycles']} clignotement(s) subsistent")
print("[Gcnf ok] 0 clignotement sur >=3 scenes, garde de non-regression posee")
PY
