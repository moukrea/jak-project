#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gsubtitle-style-2/report.txt
[ -f "$R" ] || { echo "[Gss2 FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gss2 FAIL] "+m,file=sys.stderr); sys.exit(1)
d=[kv(l) for l in re.findall(r'^SUBDUP .*$',t,re.M)]
if not d or int(d[0].get('passes_de_texte',9))!=1: F("le texte duplique est toujours dessine (l'owner le VOIT)")
s=[kv(l) for l in re.findall(r'^SUBSHADOW .*$',t,re.M)]
if not s: F("SUBSHADOW absent")
for ax in ('offset_x','offset_y'):
    if abs(float(s[0].get(ax,99)))>0.01: F(f"ombre decalee ({ax}={s[0].get(ax)}) — elle doit etre PILE sous le texte")
print("[Gss2 ok] un seul passage de texte, ombre centree")
PY
