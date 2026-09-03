#!/usr/bin/env bash
# hd4_regen_tables_cycle4.sh — CYCLE-4 regeneration of ALL 9 k->e retarget tables under the
# fixed mode1_or_3 (pairwise local-bind scale agreement; Keira *Strap2 -> mode 1) and the new
# PROOF-E real-animation replay gate. Tables ONLY (ag.go files untouched — they do not depend
# on the table and carry the device-proven shell-frag page-bit fix).
# Emits to a staging dir; installation into recharged_assets/hd_anim is the caller's decision
# after reviewing gates + diffs.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TABLE=scripts/shell/retarget_fill_table.py
STAGE=.autoport/tmp/k2e_cycle4
mkdir -p "$STAGE"
D1=decompiler_out/jak1/levels
D2=decompiler_out/jak2/levels
D3=decompiler_out/jak3/levels

DAX_ACCEPT='tongue=jak1 sidekick rig has no tongue chain; tongue rides the head via mode-2 glue, mouth-interior animation comes from blerc (class B);uvula=jak1 sidekick rig has no uvula joint; rides the head via mode-2 glue;pinky=jak1 sidekick rig has index/middle/thumb only; pinky rides the hand via mode-2 glue (curls with the hand, no independent articulation in ANY jak1 daxter anim);ring[A-Z]=jak1 sidekick rig has index/middle/thumb only; ring finger rides the hand via mode-2 glue'
SAMOS_ACCEPT='beardDriver=jak3-only sim-helper bone; the ANIMATED beard chain below it (beard_lip, beard) is name-mapped mode-1 to sage beard joints, so the beard follows sage swings at HD pivots; beardDriver itself rides the head via mode-2 glue (mapping it too would double-apply the delta);Birdjaw=jak1 sage rig has no bird-jaw joint (BIRDhead1 is the deepest bird head bone); the beak rides BIRDhead via mode-2 glue'

run(){ # char hd driver [flags...]
  local char="$1" hd="$2" driver="$3"; shift 3
  echo "################ $char"
  echo "== $char : python3 $TABLE --name $char --hd $hd --driver $driver --emit-dir $STAGE $*"
  python3 "$TABLE" --name "$char" --hd "$hd" --driver "$driver" --emit-dir "$STAGE" "$@"
  local rc=$?
  echo "exit=$rc"
  [ $rc -eq 0 ] || FAILED="$FAILED $char"
}

FAILED=""
run jak-hd    "$D2/introcst/jakone-highres-lod0.glb"    "$D1/common/eichar-lod0.glb"      --map 'shirtLthigh=Lthigh,shirtRthigh=Rthigh'
run dax-hd    "$D3/ldax/daxter-highres-lod0.glb"        "$D1/common/sidekick-lod0.glb"    --accept-unmapped "$DAX_ACCEPT"
run keira-hd  "$D2/lintcstb/keira-highres-lod0.glb"     "$D1/village1/assistant-lod0.glb"
run samos-hd  "$D3/lsamos/samos-highres-lod0.glb"       "$D1/village1/sage-lod0.glb"      --accept-unmapped "$SAMOS_ACCEPT"
run jak2-hd   "$D2/ljakdax/jak-highres-lod0.glb"        "$D1/common/eichar-lod0.glb"
run jak3-hd   "$D3/ljakc/jakc-highres-lod0.glb"         "$D1/common/eichar-lod0.glb"
run daxp-hd   "$D3/loutro2/ottsel-daxpants-lod0.glb"    "$D1/common/sidekick-lod0.glb"    --accept-unmapped "$DAX_ACCEPT"
run keira3-hd "$D3/lkeira/keira-highres-lod0.glb"       "$D1/village1/assistant-lod0.glb"
run jakm-hd   "$D3/ljakc/jakc-highres-lod0.glb"         "$D1/common/eichar-lod0.glb"
run ysamos-hd "$D2/lysamsam/youngsamos-highres-lod0.glb" "$D1/village1/sage-lod0.glb"     --accept-unmapped "$SAMOS_ACCEPT"

if [ -n "$FAILED" ]; then
  echo "REGEN-CYCLE4 FAIL:$FAILED"
  exit 1
fi
echo "REGEN-CYCLE4 PASS: all 9 tables staged in $STAGE"
