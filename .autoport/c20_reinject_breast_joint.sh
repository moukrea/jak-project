#!/usr/bin/env bash
# c20_reinject_breast_joint.sh — REPOSE le 2e os par sein (etat du cycle 18), pour mesurer.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean. Keira, poitrine seule.
# DIRECTIVES vee00ab7404
#
# POURQUOI. Le cycle 19 a conclu « aucun rayon de capsule ne peut heberger le 2e os, donc le
# bloquant est le TYPE de primitive de collision ». Ce verdict est calcule sur la course du cycle
# 18 — et la chaine que cette course mesurait portait des parametres dynamiques IDENTIQUES a la
# chaine a 1 os (`stiffness` 2.7696, `damping` 0.1686, `mass` 1.45, `couple` 1.85), sans
# `maxangle` (donc `phys-bend-chain` inerte, :1405) et avec 36.5 % de portee en plus
# (`bones_m` 0.2386 -> 0.2386,0.0871). Elle a atteint 126.4 deg de deviation sur le maillon
# distal la ou l'organe entier a 1 os en fait 15.6-17.5.
#
# Ce script REPRODUIT cet etat pour pouvoir mesurer DEUX courses sur LA MEME cuisson :
#   A = parametres du cycle 18, tels quels     (reproduction de la ligne de base)
#   B = idem + une borne d'angle de CONTROLE   (l'experience)
# Une comparaison contre `keira-room-table.C18-n2.txt` serait fausse : les deux cuissons du cycle
# 18 ont produit des GAME.fr3 de tailles differentes (25438440 / 25438592), donc la cuisson n'est
# pas bit-a-bit reproductible et la ligne de base doit etre re-mesuree sur CETTE cuisson-ci.
#
# RETRAIT. Aucune sauvegarde nouvelle n'est prise : `/home/emeric/.autoport-scratch/
# meshbak-C18-20260817-081133` est DEJA l'etat pre-injection et ses md5 correspondent au disque
# (verifie ce cycle). `.autoport/c18_retract_breast_joint.sh <ce dossier>` reste le retrait, sans
# modification. Le script le VERIFIE avant de toucher quoi que ce soit : si la sauvegarde ne
# correspond plus au disque, il refuse de commencer plutot que de rendre le retrait impossible.
set -uo pipefail
cd "$(dirname "$0")/.."

BAK=/home/emeric/.autoport-scratch/meshbak-C18-20260817-081133
LOG=.autoport/reports/Grecharged-secondary-motion/c20-reinject.log
: > "$LOG"
say(){ echo "$@" | tee -a "$LOG"; }

# ---- 0. LE VERROU DE LIVRAISON, AVEC SON PID ET SON NETTOYAGE (convention 2026-08-14 07:10).
#         Le demon d'APK (pid dans .auto_build_apk.pid) est VIVANT : sans ce verrou il emporterait
#         un `physics_chains.txt` experimental dans un build que l'owner testerait.
LOCK=.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then
  say "FAIL: $LOCK existe deja :"; cat "$LOCK" | tee -a "$LOG"; exit 1
fi
printf 'c20_reinject_breast_joint pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou pose: $(cat "$LOCK")"

# ---- 1. LE RETRAIT DOIT RESTER POSSIBLE. On le prouve AVANT d'injecter, pas apres.
[ -f "$BAK/MANIFEST.txt" ] || { say "FAIL: sauvegarde pre-injection introuvable ($BAK)"; exit 1; }
say "verification que la sauvegarde pre-injection correspond encore au disque :"
bad=0
while read -r want path; do
  case "$path" in
    ./hd_anim/*)  d="recharged_assets/${path#./}" ;;
    ./skin/*)     d="out/jak1/fr3/${path#./}" ;;
    ./enhanced/*) d="out/jak1/fr3/${path#./}" ;;
    *) continue ;;
  esac
  got=$(md5sum "$d" 2>/dev/null | cut -d' ' -f1)
  if [ "$want" != "$got" ]; then say "  DIVERGE $d ($got != $want)"; bad=1; else say "  ok $d"; fi
done < <(sed -n '/^--- md5 ---$/,$p' "$BAK/MANIFEST.txt" | tail -n +2)
[ "$bad" = 0 ] || { say "FAIL: la sauvegarde ne reflete plus le disque — retrait non garanti, on n'injecte pas"; exit 1; }

# ---- 2. LES FICHIERS SUIVIS PAR GIT — depuis le commit d'injection, jamais a la main.
INJ=d7003fd42f
say; say "restauration de l'etat injecte depuis $INJ"
for f in recharged_assets/keira-hd-inject-joints.txt \
         recharged_assets/physics_reskin.txt \
         goal_src/jak1/pc/jak-hd.gc; do
  git checkout "$INJ" -- "$f" || { say "FAIL: git checkout $f"; exit 1; }
  say "  git: $f -> etat injecte"
done
# `physics_chains.txt` n'est PAS restaure depuis git : il sera REGENERE a l'etape 5, sinon il
# decrirait un rig que la cuisson de ce cycle n'a pas produit.
python3 - <<'PY' || exit 1
import sys
p = '.autoport/physics_keira_gen2.py'
s = open(p).read()
b = "    'chestL':     ['lBoob'],\n    'chestR':     ['rBoob'],"
a = "    'chestL':     ['lBoob', 'lBooc'],\n    'chestR':     ['rBoob', 'rBooc'],"
if a in s:
    print("  gen2: deja a deux maillons"); sys.exit(0)
if b not in s:
    print("  FAIL: gen2 SIMULATED_CHAINS introuvable dans la forme attendue"); sys.exit(1)
open(p, 'w').write(s.replace(b, a, 1))
print("  gen2: SIMULATED_CHAINS -> deux maillons par sein")
PY

# ---- 3. RIG + ART-GROUP + DONNEUR INJECTE (regenere k2e.json a 107 joints).
say; say "3/6 art-group (rig a 107 joints)"
scripts/shell/build_hd_actor_artgroup.sh keira-hd \
  decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb \
  decompiler_out/jak1/levels/village1/assistant-lod0.glb >> "$LOG" 2>&1 \
  || { say "FAIL: build_hd_actor_artgroup.sh"; exit 1; }
python3 -c "
import json;d=json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json'))
assert d['num_hd_joints']==107 and len(d['rows'])==107, d['num_hd_joints']
print('  rig: 107 joints')" | tee -a "$LOG" || { say "FAIL: le rig n'est pas a 107 joints"; exit 1; }

# ---- 4. LES CINQ ENDROITS GOAL (append-only ; refuse plutot que reparer).
say "4/6 tables GOAL"
python3 .autoport/hd_splice_joint_tables.py \
  --snippet recharged_assets/hd_anim/keira-hd-k2e.gc-snippet \
  --gc goal_src/jak1/pc/jak-hd.gc --entry 2 --apply >> "$LOG" 2>&1 \
  || { say "FAIL: hd_splice_joint_tables.py"; exit 1; }
python3 .autoport/hd_check_joint_counts.py 2>&1 | tail -3 | tee -a "$LOG"
python3 .autoport/hd_check_joint_counts.py >/dev/null 2>&1 \
  || { say "FAIL: comptes de joints incoherents (le piege PHYSBONE len=NaN)"; exit 1; }

# ---- 5. LA CUISSON, puis les chaines regenerees DEPUIS le rig cuit.
say "5/6 cuisson du maillage (build_enhanced_models.sh)"
t0=$(date +%s)
scripts/shell/build_enhanced_models.sh >> "$LOG" 2>&1 \
  || { say "FAIL: build_enhanced_models.sh"; exit 1; }
say "  cuisson: $(( $(date +%s) - t0 )) s ; GAME.fr3 = $(stat -c%s out/jak1/fr3/enhanced/GAME.fr3) octets"
python3 .autoport/physics_keira_gen2.py --stamp "$(date +%F)" >> "$LOG" 2>&1 \
  || { say "FAIL: physics_keira_gen2.py"; exit 1; }
say "  chaines: $(grep -c '^chain ' recharged_assets/physics_chains.txt) emises"
grep '^chain chest' recharged_assets/physics_chains.txt | tee -a "$LOG"

# ---- 6. LES TABLES GOAL ONT CHANGE.
say "6/6 (mi)"
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' >> "$LOG" 2>&1 \
  || { say "FAIL: (mi)"; exit 1; }
say
say "INJECTE. Retrait: .autoport/c18_retract_breast_joint.sh $BAK  puis (mi)."
