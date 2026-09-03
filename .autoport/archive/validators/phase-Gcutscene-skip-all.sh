#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gcutscene-skip-all/report.txt
[ -f "$R" ] || { echo "[Gcsa FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*CUTSCENE SKIP ALL[[:space:]]*$' "$R" \
  || { echo "[Gcsa FAIL] RESULT: CUTSCENE SKIP ALL absent (cle ENTIERE)" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gcsa FAIL] "+m,file=sys.stderr); sys.exit(1)
p=[kv(l) for l in re.findall(r'^CUTPATHS .*$',t,re.M)]
if not p: F("CUTPATHS absent : le RECENSEMENT de tous les chemins de cinematique est le premier livrable")
d=p[0]
if int(d.get('couverts_apres',0))!=int(d.get('total',-1)):
    F(f"{d.get('couverts_apres')} chemins couverts sur {d.get('total')} — le trou sera juste deplace ailleurs")
sk=[kv(l) for l in re.findall(r'^CUTSKIP .*$',t,re.M)]
if not any(x.get('type')=='contextuelle' and x.get('saut')=='ok' for x in sk):
    F("aucune cinematique CONTEXTUELLE sautee : c'est precisement le cas que l'owner cite (Geyser Rock)")
h=[kv(l) for l in re.findall(r'^CUTHINT .*$',t,re.M)]
if not h: F("CUTHINT absent")
if h[0].get('apparait_sur_bouton')!='1': F("l'indice n'apparait pas des qu'on touche un bouton")
if h[0].get('position')!='bas-droite': F(f"indice en {h[0].get('position')} au lieu de bas-droite")
if int(h[0].get('localise',0))<2: F("l'indice n'est pas localise (au moins 2 langues attendues)")
f=[kv(l) for l in re.findall(r'^CUTFILL .*$',t,re.M)]
if not f: F("CUTFILL absent : la cartouche qui se remplit doit etre mesuree")
ms=float(f[0].get('duree_ms',0))
if not 1350<=ms<=1650: F(f"remplissage en {ms:.0f} ms : l'owner demande UN QUART DE MOINS que les 2000 ms livres, soit ~1500 ms")
if abs(float(f[0].get('duree_saut_ms',0))-ms)>50: F("le saut et le remplissage doivent etre synchronises : cartouche pleine = saut declenche")
# D2 : la douceur se MESURE, un booleen « coins arrondis » ne dit rien de la qualite percue
sm=[kv(l) for l in re.findall(r'^CUTSMOOTH .*$',t,re.M)]
if not sm: F("CUTSMOOTH absent : l'owner trouve les coins « pixelises », il faut MESURER la douceur du bord, pas cocher une case")
if float(sm[0].get('marches_par_coin',99))>1: F(f"{sm[0].get('marches_par_coin')} marches d'escalier par coin : « on est pas dans un jeu en pixel art »")
# D3 : centrage
ct=[kv(l) for l in re.findall(r'^CUTCENTER .*$',t,re.M)]
if not ct: F("CUTCENTER absent : publier les marges des quatre cotes")
g=ct[0]
if abs(float(g.get('marge_g',0))-float(g.get('marge_d',9)))>1: F("texte non centre horizontalement dans la cartouche")
if abs(float(g.get('marge_h',0))-float(g.get('marge_b',9)))>1: F("texte non centre verticalement dans la cartouche")
# D4 : la cartouche s'adapte au contenu
fit=[kv(l) for l in re.findall(r'^CUTFIT .*$',t,re.M)]
if len(fit)<2: F("CUTFIT absent ou sur une seule langue : « Skip » et « Passer » n'ont pas la meme largeur, il faut prouver que la cartouche s'ADAPTE")
if len({x.get('largeur_cartouche') for x in fit})<2: F("la cartouche a la MEME largeur pour des textes de longueurs differentes : elle ne s'adapte pas a son contenu")
print("[Gcsa ok] tous les chemins couverts, contextuelle sautee, indice localise en bas a droite, cartouche 2 s a coins arrondis")
PY
