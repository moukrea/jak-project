#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gcutscene-skip-polish/report.txt
[ -f "$R" ] || { echo "[Gcsp FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gcsp FAIL] "+m,file=sys.stderr); sys.exit(1)
f=[kv(l) for l in re.findall(r'^CUTFILL .*$',t,re.M)]
if not f: F("CUTFILL absent")
ms=float(f[0].get('duree_ms',0))
if not 1350<=ms<=1650: F(f"remplissage {ms:.0f} ms — l'owner veut un quart de moins que 2000, soit ~1500")
sm=[kv(l) for l in re.findall(r'^CUTSMOOTH .*$',t,re.M)]
if not sm or float(sm[0].get('marches_par_coin',99))>1: F("coins toujours pixelises (« on est pas dans un jeu en pixel art »)")
c=[kv(l) for l in re.findall(r'^CUTCENTER .*$',t,re.M)]
if not c or abs(float(c[0].get('marge_g',0))-float(c[0].get('marge_d',9)))>1 \
   or abs(float(c[0].get('marge_h',0))-float(c[0].get('marge_b',9)))>1: F("texte non centre dans la cartouche")
fit=[kv(l) for l in re.findall(r'^CUTFIT .*$',t,re.M)]
if len({x.get('largeur_cartouche') for x in fit})<2: F("la cartouche ne s'adapte pas a la longueur du texte")
print("[Gcsp ok] 1,5 s, coins lisses, texte centre, cartouche adaptative")
PY
