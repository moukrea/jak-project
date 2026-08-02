#!/usr/bin/env bash
# scripts/shell/retarget_all_hd_models.sh
#
# Grecharged-hd-models3 — reproducible regeneration of the 4 staged HD character GLBs.
#
# The staged GLBs (recharged_assets/hd_models/<name>.glb) are the jak2 high-res character
# donors re-posed onto the jak1 rigs by scripts/shell/retarget_hd_models.py. Until now the
# exact per-character donor / target / joint-handling args lived only in ad-hoc worker shells,
# so the staged GLBs were not reproducible from the repo. This driver records them.
#
# INPUTS (gitignored decompiler rips — present after `decomp.sh` on both games):
#   jak2 donors:  decompiler_out/jak2/levels/{introcst,lintcstb}/<name>-highres-lod0.glb
#   jak1 targets: decompiler_out/jak1/levels/{common,village1}/<name>-lod0.glb
# Both must be ripped by the merc-NORMAL-exporting decompiler (fr3_to_gltf.cpp add_merc,
# brick 1) — the retarget PRESERVES authored normals and refuses to run without a NORMAL attr.
#
# OUTPUT: recharged_assets/hd_models/{eichar,sidekick,sage,assistant}-lod0.glb
#
# This is a MANUAL regeneration step (donors are not always present); build_enhanced_models.sh
# consumes the already-staged GLBs and does not call this.
#
# PER-CHARACTER JOINT HANDLING
#   eichar   (Jak)    : plain name-based retarget.
#   sidekick (Daxter) : plain name-based retarget.
#   sage     (Samos)  : --drop-joints '(?i)^bird'  — the bird riding jak2 Samos is absent
#                       from jak1 Samos, so its geometry is culled (stays gone by design).
#   assistant(Keira)  : --alias 'mask=head,maskstrap=head'  (BRICK 3). jak2 Keira wears a
#                       welding mask on a strap that has NO joint counterpart on the jak1 rig
#                       (its only matching ancestor is the root `prejoint`). Round 2 DROPPED it
#                       (--drop-joints '(?i)^mask'), which left keira-mask / keira-maskbolt /
#                       part of keira-brownstraps-new as REAL-page draws with tris=0 (dead
#                       geometry). Aliasing the mask joints to the jak1 head joint keeps that
#                       geometry (tris>0) and rides it rigidly with the head instead.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RETARGET="scripts/shell/retarget_hd_models.py"
OUT_DIR="recharged_assets/hd_models"
D2="decompiler_out/jak2/levels"
T1="decompiler_out/jak1/levels"
mkdir -p "$OUT_DIR"

log(){ echo "[retarget-hd] $*"; }

run() {  # name donor target [extra args...]
  local name="$1" donor="$2" target="$3"; shift 3
  [ -f "$donor" ]  || { log "MISSING donor  $donor";  exit 1; }
  [ -f "$target" ] || { log "MISSING target $target"; exit 1; }
  log "retargeting $name  ($*)"
  python3 "$RETARGET" --donor "$donor" --target "$target" \
    --out "$OUT_DIR/$name.glb" "$@"
}

run eichar-lod0    "$D2/introcst/jakone-highres-lod0.glb" "$T1/common/eichar-lod0.glb"
run sidekick-lod0  "$D2/introcst/daxter-highres-lod0.glb" "$T1/common/sidekick-lod0.glb"
run sage-lod0      "$D2/lintcstb/samos-highres-lod0.glb"  "$T1/village1/sage-lod0.glb"      --drop-joints '(?i)^bird'
run assistant-lod0 "$D2/lintcstb/keira-highres-lod0.glb"  "$T1/village1/assistant-lod0.glb" --alias 'mask=head,maskstrap=head'

log "DONE — 4 staged GLBs written to $OUT_DIR/"
