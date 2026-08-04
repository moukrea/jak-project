#!/usr/bin/env bash
# STALE — superseded by build_hd_actor_artgroup.sh (M4)
#
# scripts/shell/build_hd_jak_artgroup.sh
#
# It writes recharged_assets/hd_anim/jak-highres-ag.go — a 17-char art-group name that trips the
# fake-iso <16 assert. Use:  scripts/shell/build_hd_actor_artgroup.sh <char> <donor_glb> <driver_glb>
echo "[hd-jak-ag] STALE — superseded by scripts/shell/build_hd_actor_artgroup.sh (M4)" >&2
exit 1
#
# HD character ANIMATION-RETARGET pipeline — MILESTONE 1 (Jak only), OFFLINE fabrication step.
#
# Fabricates the HD Jak art-group .go (its OWN 75-joint skeleton + merc-ctrl shell + identity
# art-joint-anim) from the ripped jak2 highres young-Jak GLB, WITHOUT re-rigging, and emits the
# retarget k->e joint table used by the (goal_src) companion's do-joint-math!.
#
# It reuses the EXISTING art-group emitter goalc/build_actor (build/goalc/build_actor), which
# already fabricates a valid jak1 *-ag.go from a GLB skin (this is what `(build-actor ...)` in
# goal_src/jak1/game.gp uses for custom actors). The only missing piece was feeding it a
# rip-format GLB; scripts/shell/prep_hd_actor_glb.py bridges that.
#
# INPUTS (gitignored decompiler rips; present after decomp of jak1+jak2 with the merc-NORMAL
# exporting decompiler):
#   HD donor : decompiler_out/jak2/levels/introcst/jakone-highres-lod0.glb
#   eichar   : decompiler_out/jak1/levels/common/eichar-lod0.glb   (for the k->e table)
#
# OUTPUTS:
#   recharged_assets/hd_anim/jak-highres-ag.go   (the fabricated art-group)
#   recharged_assets/hd_anim/jak-hd-k2e.json     (retarget table, machine-readable)
#   recharged_assets/hd_anim/jak-hd-k2e.gc-snippet (retarget table, GOAL static form)
#
# This step does NOT touch goal_src / game / decompiler source and does NOT build/ship.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

log(){ echo "[hd-jak-ag] $*"; }

HD="decompiler_out/jak2/levels/introcst/jakone-highres-lod0.glb"
EICHAR="decompiler_out/jak1/levels/common/eichar-lod0.glb"
OUT="recharged_assets/hd_anim"
BA="build/goalc/build_actor"
PREP="scripts/shell/prep_hd_actor_glb.py"
TABLE="scripts/shell/retarget_fill_table.py"

[ -f "$HD" ]     || { log "MISSING HD donor $HD (decomp jak2 introcst first)"; exit 1; }
[ -f "$EICHAR" ] || { log "MISSING eichar $EICHAR (decomp jak1 common first)"; exit 1; }
if [ ! -x "$BA" ]; then
  log "building build_actor…"
  cmake --build build --target build_actor -j"$(nproc)" || { log "configure the desktop 'build' tree first"; exit 1; }
fi

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "1/3 prep rip GLB -> build_actor-ready (keep HD skeleton, drop align, u32->u8, compact)"
# NOTE: build_actor derives the art-element / merc-ctrl NAME from the input GLB basename
# (name = stem + "-lod0"), and that name is what pc-merc-draw-request emits and Merc2 looks
# up. So the prepped GLB MUST be named jak-highres.glb -> merc name "jak-highres-lod0".
python3 "$PREP" --in "$HD" --out "$TMP/jak-highres.glb"

log "2/3 fabricate art-group .go with the existing build_actor emitter"
"$BA" -g jak1 "$TMP/jak-highres.glb" "$OUT/jak-highres-ag.go"

log "3/3 emit retarget k->e table + run the offline do-joint-math! numeric proof"
python3 "$TABLE" --hd "$HD" --eichar "$EICHAR" --emit-dir "$OUT"

log "DONE:"
ls -la "$OUT"/jak-highres-ag.go "$OUT"/jak-hd-k2e.* 2>/dev/null | sed 's/^/[hd-jak-ag]   /'
