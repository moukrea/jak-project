#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Ggrass-crash/report.txt
[ -f "$R" ] || { echo "[Ggc FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*GRASS NO CRASH[[:space:]]*$' "$R" || { echo "[Ggc FAIL] RESULT: GRASS NO CRASH absent" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Ggc FAIL] "+m,file=sys.stderr); sys.exit(1)
rep=[kv(l) for l in re.findall(r'^GRASSREPRO .*$',t,re.M)]
if not rep: F("GRASSREPRO absent")
on=[d for d in rep if d.get('herbe')=='on']
off=[d for d in rep if d.get('herbe')=='off']
if not any(int(d.get('plantages',0))>=1 for d in on):
    F("le plantage n'a pas ete reproduit AVEC l'herbe activee : c'est la condition que l'owner a isolee par bissection")
if not off: F("controle negatif manquant : une course herbe=off doit etre publiee, sinon l'herbe n'est pas discriminee")
if any(int(d.get('plantages',0))>=1 for d in off):
    F("la course herbe=off plante AUSSI : l'herbe n'est alors pas la cause, revoir le diagnostic")
if not re.search(r'^GRASSFALLBACK .*raison=\S+',t,re.M): F("GRASSFALLBACK absent : la RAISON du repli en direct nomme la cause")
if not re.search(r'^GRASSTRACE .*signal=\S+',t,re.M): F("GRASSTRACE absent : trace du plantage exigee")
ok=[kv(l) for l in re.findall(r'^GRASSOK .*$',t,re.M)]
if not any(d.get('plateforme')=='x86' for d in ok): F("aucune preuve GRASSOK sur x86")
for d in ok:
    if int(d.get('plantages',1))!=0: F(f"{d.get('plateforme')} : {d['plantages']} plantage(s) apres correction")
    if int(d.get('cycles',0))<10: F(f"{d.get('plateforme')} : {d.get('cycles')} cycles, il en faut >= 10")
print("[Ggc ok] plantage reproduit herbe=on, controle negatif herbe=off propre, repli nomme, >=10 cycles sans plantage")
PY
