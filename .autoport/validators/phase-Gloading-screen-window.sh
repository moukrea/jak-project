#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gloading-screen-window/report.txt
[ -f "$R" ] || { echo "[Glsw FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*LOADING WINDOW BRACKETED[[:space:]]*$' "$R" \
  || { echo "[Glsw FAIL] RESULT: LOADING WINDOW BRACKETED absent (cle ENTIERE)" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read()
kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
F=lambda m: print("[Glsw FAIL] "+m,file=sys.stderr) or sys.exit(1)
win={}
for l in re.findall(r'^LSWIN .*$',t,re.M):
    d=kv(l); win[d['transition']]=d
need={'save-geyser','teleport-sagehut'}
if not need<=set(win): F(f"transitions manquantes : {sorted(need-set(win))} — l'owner les a NOMMEES toutes les deux")
for k,d in win.items():
    up,fi,la,dn=(float(d[x]) for x in ('t_up','t_first_draw_in','t_last_active','t_down'))
    if up>fi: F(f"{k}: ecran pose {up-fi:.0f} ms APRES le premier dessin de la scene entrante — c'est le defaut D4/D7 (on voit la hutte avant l'ecran)")
    if dn<la: F(f"{k}: ecran leve {la-dn:.0f} ms AVANT le dernier element dessinable — c'est le defaut D3 (pop-in a Geyser Rock)")
fr=[kv(l) for l in re.findall(r'^LSFRAME .*$',t,re.M)]
if not fr: F("aucune ligne LSFRAME — les a-coups (D1/D5) ne sont pas mesures")
for d in fr:
    b,a=float(d['worst_gap_before']),float(d['worst_gap_after'])
    if a>=b: F(f"{d.get('transition')}: pire ecart entre images {a:.0f} ms, pas mieux que les {b:.0f} ms d'avant")
    if a>100: F(f"{d.get('transition')}: pire ecart {a:.0f} ms > plafond 100 ms — l'owner voit encore des freezes")
x=[kv(l) for l in re.findall(r'^LSTEXT .*$',t,re.M)]
if not x: F("LSTEXT absent — la taille du texte (D2) n'est pas mesuree")
d=x[0]; r=float(d['scale_after'])/float(d['scale_before'])
if not 0.45<=r<=0.55: F(f"facteur de taille {r:.3f} hors [0,45;0,55] — l'owner demande MOITIE moins gros")
if float(d['yfrac_after'])<=float(d['yfrac_before']): F("le texte n'est pas descendu (owner : « plus bas »)")
if float(d['xfrac_after'])<=float(d['xfrac_before']): F("le texte n'est pas alle a droite (owner : « a droite »)")
c=[kv(l) for l in re.findall(r'^LSCOLOR .*$',t,re.M)]
if not c: F("LSCOLOR absent — la couleur SOUMISE au rendu doit etre publiee, pas la constante source")
if c[0]['submitted'].upper()!='FFFFFF': F(f"couleur soumise {c[0]['submitted']} != FFFFFF (owner : « en plein white »)")
if c[0].get('gradient')!='0': F("le degrade gris est toujours la")
a=[kv(l) for l in re.findall(r'^LSANIM .*$',t,re.M)]
if not a: F("LSANIM absent — l'animation est VALIDEE par l'owner, il faut prouver qu'elle est intacte")
if a[0].get('unchanged')!='1': F("l'animation validee par l'owner a ete modifiee — regression interdite")
print("[Glsw ok] fenetre encadrante sur 2 transitions, a-coups sous plafond, texte a 0,5 plus bas a droite, blanc plein, animation intacte")
PY
