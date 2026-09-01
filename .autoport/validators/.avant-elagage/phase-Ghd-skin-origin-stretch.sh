#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Ghd-skin-origin-stretch/report.txt
[ -f "$R" ] || { echo "[Ghso FAIL] pas de report.txt" >&2; exit 1; }
grep -qE '^RESULT:[[:space:]]*HD STRETCH FIXED[[:space:]]*$' "$R" || { echo "[Ghso FAIL] RESULT: HD STRETCH FIXED absent" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Ghso FAIL] "+m,file=sys.stderr); sys.exit(1)
s=[kv(l) for l in re.findall(r'^HDSTRETCH .*$',t,re.M)]
if not s: F("HDSTRETCH absent : il faut PROUVER vers quel point les sommets partent avant de corriger")
if s[0].get('est_origine') not in ('0','1'): F("est_origine doit etre tranche (0 ou 1)")
ep=[kv(l) for l in re.findall(r'^HDEPISODE .*$',t,re.M)]
if len(ep)<20: F(f"{len(ep)} episodes mesures, il en faut >= 20 (defaut intermittent)")
if len({d.get('modele') for d in ep})<2: F("un seul modele mesure : l'owner demande aussi Samos et Keira")
c=[kv(l) for l in re.findall(r'^HDCORREL .*$',t,re.M)]
if not c: F("HDCORREL absent : la longueur d'etirement doit suivre la distance a l'origine")
if float(c[0].get('r2',0))<0.8: F(f"correlation r2={c[0].get('r2')} < 0,8 : le lien distance/longueur n'est pas etabli")
if not re.search(r'^HDANIM ',t,re.M):
    F("HDANIM absent : le reciblage consomme M_eichar_anim[e], seul terme variable de la formule — publier, sur l'image d'un episode, quels joints pilotes ont une matrice nulle/identite/non remplie")
if not re.search(r'^HDMAPFLIP joints_bascules=0\b',t,re.M):
    F("HDMAPFLIP joints_bascules=0 exige : aucun joint ne doit basculer entre mappe et non mappe d'une image a l'autre")
if not re.search(r'^HDCAUSE .*nommee=\S+',t,re.M): F("HDCAUSE absent : la cause doit etre NOMMEE")
ok=[kv(l) for l in re.findall(r'^HDOK .*$',t,re.M)]
if not ok: F("HDOK absent")
if float(ok[0].get('minutes_de_jeu',0))<10: F(f"{ok[0].get('minutes_de_jeu')} min de jeu, il en faut >= 10")
if int(ok[0].get('episodes',1))!=0: F(f"{ok[0]['episodes']} episode(s) subsistent")
print("[Ghso ok] cible prouvee, >=20 episodes sur >=2 modeles, correlation etablie, cause nommee, 0 episode sur >=10 min")
PY
