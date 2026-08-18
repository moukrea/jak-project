#!/usr/bin/env bash
# c23_reroot_breast_root.sh — GLISSE la racine de chaine de chaque sein a la mediane de masse de
# la chair arriere, et re-cuit tout ce qui en depend.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean. Keira, poitrine seule.
# DIRECTIVES vb249967379
#
# POURQUOI. `StrongRootFraction` (SPEC 30) vaut 0.416 / 0.459 contre 0.30, et le cycle 22 a
# DEMONTRE que le plancher atteignable par un repesage seul est 0.390 / 0.446 : a exposant donne
# la grandeur ne depend plus que de la DISTRIBUTION de `r`, donc de la GEOMETRIE. Un tiers des
# sommets se projette exactement sur le noeud racine.
#
# LE VERBE. Le cycle 22 avait depose `prepend` (inserer un noeud). Deux mesures l'ecartent :
# `chest`/`lBoob`/`lBooc` sont colineaires a 0.00027 deg, donc glisser la racine donne la MEME
# abscisse (|ds| max 8e-6) et le MEME StrongRootFraction ; et un noeud appendu donnerait
# `hd_parent > k`, ce que quatre consommateurs refusent (PARENT-ORDER). Detail :
# recharged_assets/keira-hd-inject-joints.txt, bloc du 2026-08-18 cinquieme passe.
#
# PREDICTION, ECRITE AVANT LA CUISSON : 0.390 -> 0.338 (chestL, DANS 0.28-0.35) et
# 0.446 -> 0.392 (chestR, TOUJOURS AU-DESSUS). Cinq bandes DANS des deux cotes.
set -uo pipefail
cd "$(dirname "$0")/.."

TAG=C23
STAMP=$(date +%Y%m%d-%H%M%S)
BAK=/home/emeric/.autoport-scratch/meshbak-$TAG-$STAMP
LOG=.autoport/reports/Grecharged-secondary-motion/c23-reroot.log
: > "$LOG"
say(){ echo "$@" | tee -a "$LOG"; }

# ---- 0. VERROU DE LIVRAISON, AVEC PID ET NETTOYAGE (convention 2026-08-14 07:10) --------------
LOCK=.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then say "FAIL: $LOCK existe deja :"; cat "$LOCK" | tee -a "$LOG"; exit 1; fi
printf 'c23_reroot_breast_root pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou pose: $(cat "$LOCK")"

# ---- 1. SAUVEGARDE DE L'ETAT IRREPRODUCTIBLE, AVANT DE CUIRE -----------------------------------
#         La cuisson ECRASE out/jak1/fr3/skin/*.glb et enhanced/*.fr3, qui ne se reconstruisent
#         qu'en re-cuisant ; sans cette copie le retrait serait impossible.
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

# ---- 2. ETAT DE DEPART, MESURE (pour que la comparaison soit attribuable) ----------------------
say; say "2/7 etat AVANT"
say "  md5 keira-hd-lod0.glb        $(md5sum out/jak1/fr3/skin/keira-hd-lod0.glb | cut -d' ' -f1)"
say "  md5 GAME.CGO                 $(md5sum out/jak1/iso/GAME.CGO 2>/dev/null | cut -d' ' -f1)"
say "  k2e num_hd_joints            $(python3 -c "import json;print(json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json'))['num_hd_joints'])")"
python3 - <<'PY' | tee -a "$LOG"
import json
d = json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json'))
for r in d['rows']:
    if r['hd_name'] in ('chest', 'lBoob', 'rBoob', 'lBooc', 'rBooc'):
        print("  k2e AVANT  k=%-4d %-6s e=%-5s mode=%s hd_parent=%s  (%s)"
              % (r['k'], r['hd_name'], r['e'], r['mode'], r['hd_parent'], r.get('mode_reason')))
PY

# ---- 3. RIG + ART-GROUP + DONNEUR INJECTE (regenere k2e.json) ----------------------------------
say; say "3/7 art-group"
scripts/shell/build_hd_actor_artgroup.sh keira-hd \
  decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb \
  decompiler_out/jak1/levels/village1/assistant-lod0.glb >> "$LOG" 2>&1 \
  || { say "FAIL: build_hd_actor_artgroup.sh"; exit 1; }
python3 -c "
import json;d=json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json'))
assert d['num_hd_joints']==107 and len(d['rows'])==107, d['num_hd_joints']
print('  rig: 107 joints')" | tee -a "$LOG" || { say "FAIL: le rig n'est pas a 107 joints"; exit 1; }
python3 - <<'PY' | tee -a "$LOG"
import json
d = json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json'))
for r in d['rows']:
    if r['hd_name'] in ('chest', 'lBoob', 'rBoob', 'lBooc', 'rBooc'):
        print("  k2e APRES  k=%-4d %-6s e=%-5s mode=%s hd_parent=%s  (%s)"
              % (r['k'], r['hd_name'], r['e'], r['mode'], r['hd_parent'], r.get('mode_reason')))
PY

# ---- 4. LES CINQ ENDROITS GOAL (append-only ; refuse plutot que reparer) ------------------------
say; say "4/7 tables GOAL"
python3 .autoport/hd_splice_joint_tables.py \
  --snippet recharged_assets/hd_anim/keira-hd-k2e.gc-snippet \
  --gc goal_src/jak1/pc/jak-hd.gc --entry 2 --apply >> "$LOG" 2>&1 \
  || { say "FAIL: hd_splice_joint_tables.py"; exit 1; }
python3 .autoport/hd_check_joint_counts.py 2>&1 | tail -3 | tee -a "$LOG"
python3 .autoport/hd_check_joint_counts.py >/dev/null 2>&1 \
  || { say "FAIL: comptes de joints incoherents (le piege PHYSBONE len=NaN)"; exit 1; }
if git diff --quiet goal_src/jak1/pc/jak-hd.gc; then
  say "  jak-hd.gc INCHANGE — le reroot ne touche ni index, ni parent, ni mode (attendu)"
else
  say "  jak-hd.gc A CHANGE :"; git diff --stat goal_src/jak1/pc/jak-hd.gc | tee -a "$LOG"
fi

# ---- 5. LA CUISSON ------------------------------------------------------------------------------
say; say "5/7 cuisson (build_enhanced_models.sh)"
t0=$(date +%s)
scripts/shell/build_enhanced_models.sh >> "$LOG" 2>&1 \
  || { say "FAIL: build_enhanced_models.sh"; exit 1; }
say "  cuisson: $(( $(date +%s) - t0 )) s ; GAME.fr3 = $(stat -c%s out/jak1/fr3/enhanced/GAME.fr3) octets"
say "  md5 keira-hd-lod0.glb APRES  $(md5sum out/jak1/fr3/skin/keira-hd-lod0.glb | cut -d' ' -f1)"
grep -E '^  (chestL|chestR) +anchor30|^ +ancrage mesure APRES|^ +sommets MAJORITAIRES' "$LOG" | tail -12 | tee -a /dev/null

# ---- 6. LES CHAINES, REGENEREES DEPUIS LE RIG CUIT ----------------------------------------------
say; say "6/7 chaines + echantillons de peau"
python3 .autoport/physics_keira_gen2.py --stamp "$(date +%F)" >> "$LOG" 2>&1 \
  || { say "FAIL: physics_keira_gen2.py"; exit 1; }
say "  chaines: $(grep -c '^chain ' recharged_assets/physics_chains.txt) emises"
grep '^chain chest' recharged_assets/physics_chains.txt | tee -a "$LOG"

# ---- 7. LES TABLES GOAL ONT PEUT-ETRE CHANGE ----------------------------------------------------
say; say "7/7 (mi)"
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' >> "$LOG" 2>&1 \
  || { say "FAIL: (mi)"; exit 1; }
say "  md5 GAME.CGO APRES           $(md5sum out/jak1/iso/GAME.CGO 2>/dev/null | cut -d' ' -f1)"
say
say "CUIT. Sauvegarde du retrait: $BAK"
