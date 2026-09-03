#!/usr/bin/env bash
# c24_place_breast_nodes.sh — REPLACE LES DEUX MAILLONS LIBRES DE LA POITRINE LA OU ILS PILOTENT
# LA CHAIR QUE LA 30 LEUR ASSIGNE, ET LIT LE PROFIL D'ANCRAGE SUR LA CHAIR (31) AU LIEU DU RIG.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean. Keira, poitrine seule.
# DIRECTIVES vb249967379
#
# POURQUOI. Directive du 2026-08-18 08:55, troisieme rappel : un os injecte n'existe que si le
# repesage l'accompagne, et la preuve est la REPARTITION. Etat livre : `lBooc` majoritaire sur
# 21/77 (27.3 %) et `rBooc` sur 17/75 (22.7 %), SOUS la barre de 30 %.
# Le banc a balaye toute la boite de la spec : le nombre de sommets pilotes y est PLAT et les
# seules cases >= 30 % retrecissent le denominateur. Cause mesuree : le `r` de la regle n'etait pas
# celui de la 31, et le maillon proximal vivait a r=0.216, dans la bande que la 30 reserve au
# thorax.
#
# PREDICTION, ECRITE AVANT LA CUISSON (banc bit-exact : a parametres livres il reproduit le md5 du
# mesh livre) :
#   part du NOUVEL os      chestL 27.1 % -> 43.5 %     chestR 23.8 % -> 37.5 %   (barre 30 %)
#   os proximal            chestL 10 -> 8 sommets      chestR 10 -> 10 sommets
#   StrongRootFraction     chestL 0.338 -> 0.294       chestR 0.413 -> 0.312     (bande 0.28-0.35)
#   les CINQ bandes de la 30 DANS des deux cotes (etaient 4/5)
#   tear                   chestL 18 -> 15             chestR 29 -> 22
set -uo pipefail
cd "$(dirname "$0")/.."

TAG=C24
STAMP=$(date +%Y%m%d-%H%M%S)
BAK=/home/emeric/.autoport-scratch/meshbak-$TAG-$STAMP
RPT=.autoport/reports/Grecharged-secondary-motion
LOG=$RPT/c24-place-nodes.log
: > "$LOG"
say(){ echo "$@" | tee -a "$LOG"; }

LOCK=.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then say "FAIL: $LOCK existe deja :"; cat "$LOCK" | tee -a "$LOG"; exit 1; fi
printf 'c24_place_breast_nodes pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou pose: $(cat "$LOCK")"

say; say "1/7 sauvegarde -> $BAK"
mkdir -p "$BAK/skin" "$BAK/enhanced" "$BAK/hd_anim" || exit 1
cp -f out/jak1/fr3/skin/keira-hd-lod0.glb            "$BAK/skin/"      || exit 1
cp -f out/jak1/fr3/skin/keira-hd-donor-injected.glb  "$BAK/skin/"      || exit 1
cp -f out/jak1/fr3/skin/keira3-hd-lod0.glb           "$BAK/skin/"      || exit 1
cp -f out/jak1/fr3/enhanced/GAME.fr3                 "$BAK/enhanced/"  || exit 1
cp -f out/jak1/fr3/enhanced/village1.fr3             "$BAK/enhanced/"  || exit 1
cp -f out/jak1/fr3/enhanced/village2.fr3             "$BAK/enhanced/"  || exit 1
cp -f recharged_assets/hd_anim/keira-hd-ag.go        "$BAK/hd_anim/"   || exit 1
cp -f recharged_assets/hd_anim/keira-hd-k2e.json     "$BAK/hd_anim/"   || exit 1
cp -f recharged_assets/hd_anim/keira-hd-k2e.gc-snippet "$BAK/hd_anim/" || exit 1
cp -f goal_src/jak1/pc/jak-hd.gc                     "$BAK/jak-hd.gc"  || exit 1
cp -f recharged_assets/physics_chains.txt            "$BAK/"           || exit 1
cp -f recharged_assets/physics_mesh.txt              "$BAK/"           || exit 1
cp -f recharged_assets/keira-hd-inject-joints.txt    "$BAK/"           || exit 1
cp -f recharged_assets/physics_reskin.txt            "$BAK/"           || exit 1
( cd "$BAK" && find . -type f -printf '%s  %p\n' | sort > MANIFEST.txt \
  && echo '--- md5 ---' >> MANIFEST.txt \
  && find . -type f ! -name MANIFEST.txt -exec md5sum {} \; | sort -k2 >> MANIFEST.txt ) || exit 1
say "  $(grep -c . "$BAK/MANIFEST.txt") lignes de manifeste, $(du -sh "$BAK" | cut -f1)"

say; say "2/7 etat AVANT"
say "  md5 keira-hd-lod0.glb        $(md5sum out/jak1/fr3/skin/keira-hd-lod0.glb | cut -d' ' -f1)"
say "  md5 GAME.CGO                 $(md5sum out/jak1/iso/GAME.CGO 2>/dev/null | cut -d' ' -f1)"
grep '^chain chest' recharged_assets/physics_chains.txt | tee -a "$LOG"

say; say "3/7 art-group"
scripts/shell/build_hd_actor_artgroup.sh keira-hd \
  decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb \
  decompiler_out/jak1/levels/village1/assistant-lod0.glb >> "$LOG" 2>&1 \
  || { say "FAIL: build_hd_actor_artgroup.sh"; exit 1; }
python3 -c "
import json;d=json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json'))
assert d['num_hd_joints']==107 and len(d['rows'])==107, d['num_hd_joints']
print('  rig: 107 joints')" | tee -a "$LOG" || { say "FAIL: le rig n'est pas a 107 joints"; exit 1; }

say; say "4/7 tables GOAL"
# LES DEUX CHANGEMENTS DE MODE SONT DECLARES, PAS SUBIS. `lBoob` (k=45) et `rBoob` (k=44) avancent
# de 0.0159 m : leur `pivot_err` passe sous le seuil du selecteur (`retarget_fill_table.py:224`,
# `thr = max(0.02, 0.25*bone)`, et l'os chest->lBoob passe de 0.2266 a 0.2544 m), qui quitte alors
# le repli mode 3 (orient-copy — choisi PARCE QUE les pivots ne s'accordaient pas, ancienne raison
# « pivot_err=0.0678 > thr=0.0566 ») pour le mode 0 (world-delta, « exact driver-skin follow »,
# nouvelle raison « name-matched, pivots agree »). Le danger documente du mode 0 (« tears chains
# whose bind pivots differ ») est precisement celui que l'accord des pivots retire, et PROOF-E
# revalide le rig neuf (7 anims, 82 frames, 0 violation).
python3 .autoport/hd_splice_joint_tables.py \
  --snippet recharged_assets/hd_anim/keira-hd-k2e.gc-snippet \
  --gc goal_src/jak1/pc/jak-hd.gc --entry 2 --apply \
  --expect-mode-change '44:3->0,45:3->0' >> "$LOG" 2>&1 \
  || { say "FAIL: hd_splice_joint_tables.py"; exit 1; }
python3 .autoport/hd_check_joint_counts.py 2>&1 | tail -3 | tee -a "$LOG"
python3 .autoport/hd_check_joint_counts.py >/dev/null 2>&1 \
  || { say "FAIL: comptes de joints incoherents"; exit 1; }
if git diff --quiet goal_src/jak1/pc/jak-hd.gc; then
  say "  jak-hd.gc INCHANGE — aucun index, aucun parent, aucun mode touche (attendu)"
else
  say "  jak-hd.gc A CHANGE :"; git diff --stat goal_src/jak1/pc/jak-hd.gc | tee -a "$LOG"
fi

say; say "5/7 cuisson (build_enhanced_models.sh)"
t0=$(date +%s)
scripts/shell/build_enhanced_models.sh >> "$LOG" 2>&1 \
  || { say "FAIL: build_enhanced_models.sh"; exit 1; }
say "  cuisson: $(( $(date +%s) - t0 )) s ; GAME.fr3 = $(stat -c%s out/jak1/fr3/enhanced/GAME.fr3) octets"
say "  md5 keira-hd-lod0.glb APRES  $(md5sum out/jak1/fr3/skin/keira-hd-lod0.glb | cut -d' ' -f1)"
grep -E '^  (chestL|chestR) +anchor30|^ +ancrage mesure APRES|^ +sommets MAJORITAIRES' "$LOG" | tail -8 | tee -a /dev/null

say; say "6/7 chaines + echantillons de peau"
python3 .autoport/physics_keira_gen2.py --stamp "$(date +%F)" >> "$LOG" 2>&1 \
  || { say "FAIL: physics_keira_gen2.py"; exit 1; }
say "  chaines: $(grep -c '^chain ' recharged_assets/physics_chains.txt) emises"
grep '^chain chest' recharged_assets/physics_chains.txt | tee -a "$LOG"
# LES ECHANTILLONS DE PEAU SONT REGENERES PAR LE PRODUCTEUR LUI-MEME depuis le cycle 24
# (`physics_keira_gen2.py` appelle `physics_c14_meshsamples.py` a la fin quand il ecrit le fichier
# livre). On le VERIFIE ici au lieu de le supposer : `physics_mesh.txt` doit etre plus recent que
# le mesh cuit, sinon la collision de la poitrine lit une peau attachee a des os qui ont bouge —
# ce qui a ete livre aux cycles 23 ET 24 avant d'etre trouve.
if [ recharged_assets/physics_mesh.txt -nt out/jak1/fr3/skin/keira-hd-lod0.glb ]; then
  say "  echantillons de peau: FRAIS ($(grep -c '^ms ' recharged_assets/physics_mesh.txt) lignes ms,"\
      "$(grep -c '^bs ' recharged_assets/physics_mesh.txt) lignes bs)"
  grep '^ms chest' recharged_assets/physics_mesh.txt | tee -a "$LOG"
else
  say "FAIL: recharged_assets/physics_mesh.txt est PLUS ANCIEN que le mesh cuit — la collision"
  say "      de la poitrine lirait une peau attachee a des os qui ont bouge."
  exit 1
fi

say; say "7/7 (mi)"
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' >> "$LOG" 2>&1 \
  || { say "FAIL: (mi)"; exit 1; }
say "  md5 GAME.CGO APRES           $(md5sum out/jak1/iso/GAME.CGO 2>/dev/null | cut -d' ' -f1)"
say; say "sauvegarde: $BAK"
