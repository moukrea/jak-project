#!/usr/bin/env bash
# scripts/shell/build_hd_actor_artgroup.sh <char> <donor_glb> <driver_glb>
#
# HD character ANIMATION-RETARGET pipeline — M4 generalization of the (now STALE)
# build_hd_jak_artgroup.sh, which was hardcoded to Jak AND emitted a 17-char art-group name
# (jak-highres-ag.go) that trips the fake-iso <16 name assert.
#
# Fabricates <char>-ag.go (the HD donor's OWN skeleton + merc-ctrl shell + identity
# art-joint-anim) from a ripped HD donor GLB, WITHOUT re-rigging, and emits the retarget
# k->driver joint table used by the (goal_src) companion's do-joint-math!.
#
# The prepped GLB MUST be staged as <char>.glb: build_actor derives the art-element /
# merc-ctrl NAME from the input GLB basename (name = stem + "-lod0"), so <char>.glb yields
# the merc model name <char>-lod0 that pc-merc-draw-request emits and Merc2 looks up.
#
# Canonical characters (donors):
#   jak-hd    decompiler_out/jak2/levels/introcst/jakone-highres-lod0.glb
#   dax-hd    decompiler_out/jak3/levels/ldax/daxter-highres-lod0.glb
#   keira-hd  decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb
#   samos-hd  decompiler_out/jak3/levels/lsamos/samos-highres-lod0.glb
#
# Example:
#   scripts/shell/build_hd_actor_artgroup.sh dax-hd \
#     decompiler_out/jak3/levels/ldax/daxter-highres-lod0.glb \
#     decompiler_out/jak1/levels/common/sidekick-lod0.glb
#
# OUTPUTS (recharged_assets/hd_anim/):
#   <char>-ag.go            the fabricated art-group
#   <char>-k2e.json         retarget table, machine-readable
#   <char>-k2e.gc-snippet   retarget table, GOAL static form
#
# This step does NOT touch goal_src / game / decompiler source and does NOT build/ship.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

log(){ echo "[hd-actor-ag] $*"; }

usage(){ echo "usage: $0 <char> <donor_glb> <driver_glb>" >&2; exit 2; }

CHAR="${1:-}"; HD="${2:-}"; DRIVER="${3:-}"
[ -n "$CHAR" ] && [ -n "$HD" ] && [ -n "$DRIVER" ] || usage

OUT="recharged_assets/hd_anim"
BA="build/goalc/build_actor"
PREP="scripts/shell/prep_hd_actor_glb.py"
TABLE="scripts/shell/retarget_fill_table.py"

# a. NAME LENGTH GATE — "<char>-ag.go" must be < 16 chars (fake-iso file-name assert),
#    i.e. the character name must be <= 9 chars (jak-hd/dax-hd=6, keira-hd/samos-hd=8).
[ ${#CHAR} -lt 10 ] || {
  log "FATAL: char name '$CHAR' is ${#CHAR} chars — '<char>-ag.go' would be $(( ${#CHAR} + 6 )) chars, and the fake-iso name assert requires < 16 (char name <= 9)."
  exit 1
}

[ -f "$HD" ]     || { log "FATAL: missing HD donor GLB $HD (decomp the donor game first)"; exit 1; }
[ -f "$DRIVER" ] || { log "FATAL: missing driver GLB $DRIVER (decomp jak1 first)"; exit 1; }
[ -x "$BA" ]     || { log "FATAL: $BA missing — build goalc first"; exit 1; }

mkdir -p "$OUT"
# b. prep the rip GLB -> build_actor-ready, staged as <char>.glb
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "1/3 prep rip GLB -> build_actor-ready (keep HD skeleton, drop align, u32->u8, compact)"
python3 "$PREP" --in "$HD" --out "$TMP/$CHAR.glb" --report "$TMP/$CHAR-prep.txt"

# c. fabricate the art-group with the existing build_actor emitter
log "2/3 fabricate art-group -> $OUT/$CHAR-ag.go (merc model name: $CHAR-lod0)"
"$BA" -g jak1 "$TMP/$CHAR.glb" "$OUT/$CHAR-ag.go"

# d. retarget k->driver table + the offline do-joint-math! numeric proof
log "3/3 emit retarget k->driver table + run the offline do-joint-math! numeric proof"
python3 "$TABLE" --name "$CHAR" --hd "$HD" --driver "$DRIVER" --emit-dir "$OUT"

# e. report the produced files + sizes, and sanity-check the art-group
AG="$OUT/$CHAR-ag.go"
[ -f "$AG" ] || { log "FATAL: $AG was not produced"; exit 1; }
AG_SZ="$(stat -c %s "$AG")"
[ "$AG_SZ" -gt 4096 ] || { log "FATAL: $AG is only $AG_SZ bytes (<= 4096) — art-group fabrication looks empty"; exit 1; }

log "DONE:"
ls -la "$AG" "$OUT/$CHAR-k2e.json" "$OUT/$CHAR-k2e.gc-snippet" 2>/dev/null | sed 's/^/[hd-actor-ag]   /'
