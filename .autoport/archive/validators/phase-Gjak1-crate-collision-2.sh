#!/usr/bin/env bash
# ELAGUE le 2026-09-01. L'owner : « t'as mis tellement de blockers que le moindre truc prend
# des journées ». Il avait 17 conditions, heritees de la phase d'ENQUETE. La cause est
# nommee (sphere de collision NaN) : il ne reste a prouver QUE le resultat.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gjak1-crate-collision-2/report.txt
[ -f "$R" ] || { echo "[Gjcc2 FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gjcc2 FAIL] "+m,file=sys.stderr); sys.exit(1)
pr=[kv(l) for l in re.findall(r'^CRATEPROBE .*$',t,re.M)]
if not pr: F("CRATEPROBE absent : sonder les 31 caisses par le code (sphere finie + contact)")
dev=[d for d in pr if d.get('plateforme')=='redmi' and float(d.get('fps',999))<=30]
if not dev: F("aucune sonde sur l'appareil a cadence <= 30 img/s")
for d in dev:
    n=int(d.get('caisses',0))
    if n<31 or int(d.get('spheres_finies',0))!=n or int(d.get('contacts_ok',0))!=n:
        F(f"{d.get('spheres_finies')}/{n} spheres finies, {d.get('contacts_ok')}/{n} contacts — attendu 31/31/31")
print("[Gjcc2 ok] 31 caisses solides sur l'appareil a cadence basse")
PY
