#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gpbr-props-reach-draw/report.txt
[ -f "$R" ] || { echo "[Gprd FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gprd FAIL] "+m,file=sys.stderr); sys.exit(1)
rc=[kv(l) for l in re.findall(r'^PBRREACH .*$',t,re.M)]
if not rc: F("PBRREACH absent : publier, par matiere rencontree, si ses parametres sont DEPOSES et CONSOMMES par un draw")
if not any(d.get('plateforme')=='redmi' for d in rc): F("aucune mesure sur l'appareil")
for d in rc:
    m,p,c=int(d.get('matieres_rencontrees',0)),int(d.get('params_deposes',0)),int(d.get('draws_consommes',0))
    if p<m: F(f"{p} matieres ont leurs parametres deposes sur {m} rencontrees — c'est le defaut que l'owner voit")
    if c<1: F("aucun draw n'a consomme ces parametres : ils sont poses et jamais lus")
v=[kv(l) for l in re.findall(r'^PBRVAL .*$',t,re.M)]
if len(v)<20: F(f"{len(v)} matieres detaillees, il en faut >= 20")
nd=[x for x in v if x.get('atteint_draw')=='1' and any(float(x.get(k,0))>0 for k in ('clearcoat','aniso','reflectance','metallic'))]
if len(nd)<5: F(f"{len(nd)} matieres avec des proprietes NON par defaut atteignant le draw — l'owner dit que seules les anciennes textures sont traitees")
print("[Gprd ok] proprietes deposees pour toutes les matieres rencontrees et consommees au draw")
PY
