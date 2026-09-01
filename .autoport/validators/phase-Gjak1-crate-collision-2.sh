#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gjak1-crate-collision-2/report.txt
[ -f "$R" ] || { echo "[Gjcc2 FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*CRATES SOLID[[:space:]]*$' "$R" || { echo "[Gjcc2 FAIL] RESULT: CRATES SOLID absent" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gjcc2 FAIL] "+m,file=sys.stderr); sys.exit(1)
rep=[kv(l) for l in re.findall(r'^CRATEREPRO .*$',t,re.M)]
if len([d for d in rep if int(d.get('caisses_sans_collision',0))>=1])<2:
    F("le defaut doit etre reproduit sur AU MOINS 2 courses : « c'est un peu random », une course propre ne prouve rien")
if len([kv(l) for l in re.findall(r'^CRATEBISECT .*$',t,re.M)])<2:
    F("CRATEBISECT sur >= 2 builds exige : il faut ENCADRER l'apparition, les archives datees sont sur jak-builds")
c=[kv(l) for l in re.findall(r'^CRATECAUSE .*$',t,re.M)]
if not c or not c[0].get('nommee'): F("CRATECAUSE absent : la cause doit etre NOMMEE, pas deduite")
if c[0].get('lien_jak2') not in ('oui','non','indetermine'):
    F("le lien avec la regression jak2 deja documentee doit etre tranche (oui/non/indetermine)")
if not re.search(r'^CRATEIDENTVERDICT .*memes_caisses=(oui|non)',t,re.M):
    F("CRATEIDENTVERDICT absent : il faut dire si c'est la MEME caisse a chaque course ou non — c'est le test direct de « c'est pas toujours les mêmes », et les deux reponses menent a des corrections opposees")
if len(re.findall(r'^CRATEIDENT ',t,re.M))<4:
    F("moins de 4 lignes CRATEIDENT : l'identite (aid) de la caisse fautive doit etre publiee pour CHAQUE course")
if not re.search(r'^CRATEALLOC ',t,re.M):
    F("CRATEALLOC absent : l'owner precise que les caisses sont DESSINEES et que ce ne sont pas toujours les memes — il faut publier, par caisse, si sa forme de collision a ete allouee et l'occupation du pool a cet instant")
pr=[kv(l) for l in re.findall(r'^CRATEPROBE .*$',t,re.M)]
if not pr:
    F("CRATEPROBE absent : la preuve finale se fait PAR LE CODE (sphere finie + requete de collision sur CHAQUE caisse), pas en conduisant le personnage — owner 2026-09-01")
dev=[d for d in pr if d.get('plateforme')=='redmi' and float(d.get('fps',999))<=30]
if not dev: F("aucune sonde sur l'appareil a cadence <= 30 img/s")
for d in pr:
    n=int(d.get('caisses',0))
    if n<31: F(f"{n} caisses sondees sur 31 : la sonde programmatique doit TOUTES les couvrir en une passe")
    if int(d.get('spheres_finies',0))!=n: F(f"{n-int(d.get('spheres_finies',0))} sphere(s) non finies (NaN/inf) restantes")
    if int(d.get('contacts_ok',0))!=n: F(f"{n-int(d.get('contacts_ok',0))} caisse(s) sans contact de collision")
ok=[kv(l) for l in re.findall(r'^CRATEOK .*$',t,re.M)]
if not ok: F("CRATEOK absent")
d=ok[0]
if int(d.get('courses',0))<3: F(f"{d.get('courses')} course(s), il en faut >= 3 (defaut intermittent)")
if int(d.get('caisses_testees',0))<20: F(f"{d.get('caisses_testees')} caisses testees, il en faut >= 20")
if int(d.get('caisses_sans_collision',1))!=0: F(f"{d['caisses_sans_collision']} caisse(s) encore traversables")
print("[Gjcc2 ok] defaut reproduit 2x, apparition encadree, cause nommee, 0 caisse traversable sur >=3 courses / >=20 caisses")
PY
