#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gsubtitle-style-2/report.txt
[ -f "$R" ] || { echo "[Gss FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*SUBTITLE STYLE DONE[[:space:]]*$' "$R" \
  || { echo "[Gss FAIL] RESULT: SUBTITLE STYLE DONE absent (cle ENTIERE)" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gss FAIL] "+m,file=sys.stderr); sys.exit(1)
c=[kv(l) for l in re.findall(r'^SUBCOLOR .*$',t,re.M)]
if not c: F("SUBCOLOR absent : couleurs du nom et de la ligne exigees")
d=c[0]
if d.get('ligne_rgb','').upper()!='FFFFFF':
    F(f"le corps de la ligne est en {d.get('ligne_rgb')} au lieu de FFFFFF — l'owner demande du blanc plein")
if d.get('nom_degrade')!='1':
    F("le degrade du NOM a disparu : l'owner a dit « on peut laisser le texte colore (avec un leger degrade) »")
d2=[kv(l) for l in re.findall(r'^SUBDUP .*$',t,re.M)]
if not d2: F("SUBDUP absent : l'owner voit ENCORE le texte duplique alors que le rapport precedent publiait dup_alpha=0 — publier le NOMBRE DE PASSES DE TEXTE reellement dessinees")
if int(d2[0].get('passes_de_texte',9))!=1: F(f"{d2[0].get('passes_de_texte')} passes de texte dessinees, il en faut 1 : la copie en dur est toujours la")
s=[kv(l) for l in re.findall(r'^SUBSHADOW .*$',t,re.M)]
if not s: F("SUBSHADOW absent")
if s[0].get('type')!='ombre-floue':
    F(f"l'ombre est encore de type {s[0].get('type')} : l'owner veut une drop shadow avec un leger flou, pas le texte duplique")
if float(s[0].get('rayon_flou',0))<=0: F("rayon de flou nul : ce n'est pas une ombre floue")
for ax in ('offset_x','offset_y'):
    if abs(float(s[0].get(ax,99)))>0.01: F(f"{ax}={s[0].get(ax)} : l'ombre doit etre PILE sous le texte, pas decalee comme l'ancienne")
sc=[kv(l) for l in re.findall(r'^SUBSCOPE .*$',t,re.M)]
if not sc: F("SUBSCOPE absent : il faut prouver que le RESTE des textes n'a pas bouge")
if int(sc[0].get('textes_hors_sous_titres_modifies',1))!=0:
    F(f"{sc[0]['textes_hors_sous_titres_modifies']} texte(s) hors sous-titres modifie(s) — l'owner : « faut pas que ca change le reste des textes »")
print("[Gss ok] corps blanc plein, degrade du nom conserve, ombre floue, aucun autre texte touche")
PY
