#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gcutscene-skip-polish/report.txt
[ -f "$R" ] || { echo "[Gcsp FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gcsp FAIL] "+m,file=sys.stderr); sys.exit(1)
f=[kv(l) for l in re.findall(r'^CUTFILL .*$',t,re.M)]
if not f: F("CUTFILL absent")
ms=float(f[0].get('duree_ms',0))
if not 1350<=ms<=1650: F(f"remplissage {ms:.0f} ms — l'owner veut un quart de moins que 2000, soit ~1500")
# D1 CAPSULE : rayon == hauteur/2, demi-cercle complet de chaque cote (owner 2026-09-01)
sh=[kv(l) for l in re.findall(r'^CUTSHAPE .*$',t,re.M)]
if not sh: F("CUTSHAPE absent : publier rayon et hauteur — l'owner veut une CAPSULE (« demi cercles de chaque côté »), pas un rectangle a coins arrondis")
r,h=float(sh[0].get('rayon_px',0)),float(sh[0].get('hauteur_px',1))
if abs(r-h/2)>1: F(f"rayon {r} px pour une hauteur {h} px : il faut rayon = hauteur/2 = {h/2:.1f} pour un demi-cercle complet")
# D3 : la cartouche ne doit exister QUE pendant une cinematique
hc=[kv(l) for l in re.findall(r'^CUTHORS .*$',t,re.M)]
if not hc: F("CUTHORS absent : l'owner voit la cartouche DANS LE MENU PRINCIPAL — publier le compte d'images ou elle est dessinee hors cinematique")
if int(hc[0].get('images_hors_cinematique',9))!=0: F(f"cartouche dessinee sur {hc[0]['images_hors_cinematique']} image(s) hors cinematique")
sm=[kv(l) for l in re.findall(r'^CUTSMOOTH .*$',t,re.M)]
if not sm or float(sm[0].get('marches_par_coin',99))>1: F("coins toujours pixelises (« on est pas dans un jeu en pixel art »)")
c=[kv(l) for l in re.findall(r'^CUTCENTER .*$',t,re.M)]
if c and float(c[0].get('marge_g',0))>=11.4: F(f"marge laterale {c[0]['marge_g']} px : l'owner veut la cartouche « bien plus pres » du texte, resserrer")
if not c or abs(float(c[0].get('marge_g',0))-float(c[0].get('marge_d',9)))>1 \
   or abs(float(c[0].get('marge_h',0))-float(c[0].get('marge_b',9)))>1: F("texte non centre dans la cartouche")
fit=[kv(l) for l in re.findall(r'^CUTFIT .*$',t,re.M)]
if len({x.get('largeur_cartouche') for x in fit})<2: F("la cartouche ne s'adapte pas a la longueur du texte")
n=[kv(l) for l in re.findall(r'^CUTNATIVE .*$',t,re.M)]
if not n: F("CUTNATIVE absent : l'owner veut le saut instantane d'OpenGOAL (triangle) RETIRE, il collide avec le maintien de cercle")
if int(n[0].get('sites_skip_instantane',9))!=0 or n[0].get('touche_triangle_saute')!='0':
    F(f"saut instantane encore actif ({n[0].get('sites_skip_instantane')} site(s), triangle={n[0].get('touche_triangle_saute')}) — un seul oubli et le comportement wacky revient")
print("[Gcsp ok] 1,5 s, coins lisses, texte centre, cartouche adaptative, saut natif retire")
PY
