#!/usr/bin/env bash
# c18_retract_breast_joint.sh — REPOSE l'arbre dans l'etat d'AVANT l'injection du cycle 18.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean. Keira, poitrine seule.
#
# POURQUOI CE SCRIPT EXISTE, ECRIT AVANT D'EN AVOIR BESOIN.
# La regle 6 de l'owner ne se negocie pas : « rien ne traverse le mesh de son personnage, quelle
# qu'en soit la raison ». Si la course de salle rend `meshpen` positif, l'injection se RETIRE —
# « pas adoucie, retiree ». Le cycle 16 a du improviser ce retrait ; il lui a manque
# `keira-hd-k2e.json` et `keira-hd-ag.go` dans sa sauvegarde et il a fallu les REGENERER, ce qui a
# laisse un ecart de 51 octets sur le fichier livre que son rapport a classe « NON
# RECONSTRUCTIBLE ». La sauvegarde du cycle 18 les contient ; ce script s'en sert.
#
# Il est ecrit MAINTENANT, pendant que la course tourne, precisement pour ne pas etre ecrit sous
# la pression d'un resultat rouge — c'est a ce moment-la qu'on prend des raccourcis.
#
# IL NE DEVINE RIEN : la sauvegarde est passee en argument, et chaque fichier restaure est
# verifie par md5 contre le MANIFEST qu'elle porte. Un fichier absent ou qui ne retombe pas sur
# son empreinte fait echouer le script au lieu de laisser un arbre a moitie restaure — l'etat
# « moitie 105, moitie 107 » est le seul pire que celui qu'on repare.
set -uo pipefail
cd "$(dirname "$0")/.."

BAK="${1:-$(cat /tmp/c18_bak_path.txt 2>/dev/null)}"
[ -n "$BAK" ] && [ -d "$BAK" ] || { echo "FAIL: sauvegarde introuvable. Usage: $0 <dossier-meshbak>"; exit 1; }
[ -f "$BAK/MANIFEST.txt" ] || { echo "FAIL: $BAK ne porte pas de MANIFEST.txt"; exit 1; }
echo "restauration depuis $BAK"

# 1. LES FICHIERS SUIVIS PAR GIT — on revient au commit d'AVANT l'injection, jamais a la main.
#    `git checkout <commit> -- <path>` et pas `git revert` : le reste du cycle (les correctifs
#    d'instrument, qui sont bons et independants) doit rester.
PRE=$(git log --format=%H --grep='la poitrine a DEUX articulations' -n1)
[ -n "$PRE" ] || { echo "FAIL: commit d'injection introuvable dans l'historique"; exit 1; }
echo "commit d'injection = $PRE ; on restaure ses fichiers depuis son parent"
for f in recharged_assets/keira-hd-inject-joints.txt \
         recharged_assets/physics_reskin.txt \
         recharged_assets/physics_chains.txt \
         goal_src/jak1/pc/jak-hd.gc; do
  git checkout "$PRE^" -- "$f" || { echo "FAIL: git checkout $f"; exit 1; }
  echo "  git: $f -> etat pre-injection"
done
# `SIMULATED_CHAINS` vit dans le generateur, dont le reste du cycle DOIT survivre : on ne
# restaure donc pas le fichier entier, on remet les deux listes a un joint.
python3 - <<'PY' || exit 1
import re, sys
p = '.autoport/physics_keira_gen2.py'
s = open(p).read()
a = "    'chestL':     ['lBoob', 'lBooc'],\n    'chestR':     ['rBoob', 'rBooc'],"
b = "    'chestL':     ['lBoob'],\n    'chestR':     ['rBoob'],"
if a not in s:
    print("  gen2: deja a un maillon (rien a faire)"); sys.exit(0)
open(p, 'w').write(s.replace(a, b, 1))
print("  gen2: SIMULATED_CHAINS -> un maillon par sein")
PY

# 2. LES FICHIERS QUE GIT NE SUIT PAS — depuis la sauvegarde, avec verification d'empreinte.
restore(){ # <src-relatif-au-bak> <dst>
  local s="$BAK/$1" d="$2"
  [ -f "$s" ] || { echo "FAIL: $s absent de la sauvegarde"; return 1; }
  cp -p "$s" "$d" || return 1
  local want got
  want=$(grep -F " ./$1" "$BAK/MANIFEST.txt" | awk '{print $1}' | head -1)
  got=$(md5sum "$d" | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "FAIL: $d restaure mais md5 $got != $want attendu"; return 1; }
  echo "  bak: $d  (md5 $got verifie)"
}
restore hd_anim/keira-hd-k2e.json      recharged_assets/hd_anim/keira-hd-k2e.json      || exit 1
restore hd_anim/keira-hd-k2e.gc-snippet recharged_assets/hd_anim/keira-hd-k2e.gc-snippet || exit 1
restore hd_anim/keira-hd-ag.go         recharged_assets/hd_anim/keira-hd-ag.go         || exit 1
restore skin/keira-hd-donor-injected.glb out/jak1/fr3/skin/keira-hd-donor-injected.glb || exit 1
restore skin/keira-hd-lod0.glb         out/jak1/fr3/skin/keira-hd-lod0.glb             || exit 1
restore skin/keira3-hd-lod0.glb        out/jak1/fr3/skin/keira3-hd-lod0.glb            || exit 1
restore enhanced/GAME.fr3              out/jak1/fr3/enhanced/GAME.fr3                  || exit 1

# 3. LES CINQ ENDROITS DOIVENT REDIRE 105 — c'est le piege qui a produit `PHYSBONE len=NaN`
#    quand quatre tableaux disaient une chose et le cinquieme une autre.
python3 .autoport/hd_check_joint_counts.py || { echo "FAIL: comptes de joints incoherents"; exit 1; }
python3 -c "
import json;d=json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json'))
assert d['num_hd_joints']==105 and len(d['rows'])==105, d['num_hd_joints']
print('rig: 105 joints')"  || exit 1

echo
echo "RESTAURE. Il reste DEUX gestes, et ils ne sont pas automatiques :"
echo "  1. ./build/goalc/goalc --user-auto --game jak1 -c '(mi)'   (les tables GOAL ont change)"
echo "  2. une course de salle de verification, dont le tableau doit retomber sur celui d'avant"
echo "     l'injection — 0 ligne de diff, comme le cycle 16 l'a exige de lui-meme."
