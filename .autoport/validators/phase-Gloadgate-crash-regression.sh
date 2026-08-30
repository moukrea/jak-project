#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gloadgate-crash-regression/report.txt
[ -f "$R" ] || { echo "[Glcr FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*LOAD SAVE NO CRASH[[:space:]]*$' "$R" \
  || { echo "[Glcr FAIL] RESULT: LOAD SAVE NO CRASH absent (cle ENTIERE)" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read()
kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Glcr FAIL] "+m,file=sys.stderr); sys.exit(1)
rep=[kv(l) for l in re.findall(r'^CRASHREPRO .*$',t,re.M)]
if not rep: F("CRASHREPRO absent : le plantage doit etre REPRODUIT avant d'etre corrige")
if not any(int(d.get('plantages',0))>=1 for d in rep):
    F("aucune reproduction du plantage (plantages=0 partout) : sans reproduction, la correction n'est pas prouvee")
if not re.search(r'^CRASHTRACE .*signal=\S+',t,re.M): F("CRASHTRACE absent : il faut la trace du plantage, pas un resume")
if not re.search(r'^CRASHCAUSE .*nommee=\S+',t,re.M): F("CRASHCAUSE absent : la cause doit etre NOMMEE")
# le chemin OPTIONS discrimine la cause : il doit avoir ete tente
if not re.search(r'^CRASHREPRO .*chemin=options',t,re.M):
    F("le chemin pause -> OPTIONS n'a pas ete tente (CRASHREPRO ... chemin=options) : c'est la reproduction la moins chere et celle qui dit si la barriere est en cause")
if not re.search(r'^POPULATIONS ',t,re.M):
    F("POPULATIONS absent : il faut publier ce qui distingue les niveaux qui CHARGENT (Sandover, Gol et Maia) de celui qui PLANTE (Geyser Rock)")
ok=[kv(l) for l in re.findall(r'^LOADOK .*$',t,re.M)]
if not ok: F("LOADOK absent : il faut prouver que charger une partie remarche")
x86=[d for d in ok if d.get('plateforme')=='x86']
if not x86: F("aucune preuve LOADOK sur x86")
for d in ok:
    if int(d.get('plantages',1))!=0: F(f"{d.get('plateforme')} : {d['plantages']} plantage(s) apres correction")
    if int(d.get('chargements',0))<10: F(f"{d.get('plateforme')} : seulement {d.get('chargements')} chargements, il en faut >= 10")
w=[kv(l) for l in re.findall(r'^LSWIN .*$',t,re.M)]
if not w: F("LSWIN absent : l'encadrement de la fenetre ne doit pas etre perdu en corrigeant")
for d in w:
    if float(d['t_up'])>float(d['t_first_draw_in']): F("l'ecran se pose de nouveau APRES le premier dessin — l'encadrement est perdu")
    if float(d['t_down'])<float(d['t_last_active']): F("l'ecran se leve de nouveau trop tot — l'encadrement est perdu")
lk=[kv(l) for l in re.findall(r'^LOOKUNCHANGED .*$',t,re.M)]
if not lk: F("LOOKUNCHANGED absent : l'owner a valide le look, il faut prouver qu'il est intact")
if lk[0].get('identique')!='1': F("le look valide par l'owner (« le look est nickel ») a change — interdit")
print("[Glcr ok] plantage reproduit puis elimine (>=10 chargements, 0 plantage), fenetre toujours encadrante, look intact")
PY
