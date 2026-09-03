#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gmenu-census-cleanup/report.txt
[ -f "$R" ] || { echo "[Gmcc FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gmcc FAIL] "+m,file=sys.stderr); sys.exit(1)
c=[kv(l) for l in re.findall(r'^MENUCENSUS .*$',t,re.M)]
if not c: F("MENUCENSUS absent : recenser toutes les lignes du menu Recharged")
rows=[kv(l) for l in re.findall(r'^MENUROW .*$',t,re.M)]
if len(rows)<int(c[0].get('lignes',0)): F(f"{len(rows)} lignes detaillees pour {c[0].get('lignes')} recensees")
d=[kv(l) for l in re.findall(r'^MENUDEBUG .*$',t,re.M)]
if not d or int(d[0].get('restantes',9))!=0:
    F("des outils de mise au point restent dans le menu joueur (PBR TEST PRESET / PBR ISOLATE sont marques DEBUG dans notre source)")
if not re.search(r'^MENUDOUBLON .*verdict=(doublon-fusionne|deux-choses-renommees)',t,re.M):
    F("MENUDOUBLON absent : trancher « Recharged Assets » contre « HD Texture Pack »")
mortes=[r for r in rows if r.get('branchee')=='0' and r.get('place_joueur')=='1']
if mortes: F(f"{len(mortes)} ligne(s) qui ne changent RIEN sont laissees devant le joueur")
print("[Gmcc ok] menu recense, outils de debogage retires, doublon tranche, aucune ligne morte devant le joueur")
PY
