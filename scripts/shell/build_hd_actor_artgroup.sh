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
# M5 BONUS looks (donors; each inherits its sibling character's retarget flags + driver GLB):
#   jak2-hd    decompiler_out/jak2/levels/ljakdax/jak-highres-lod0.glb        (sibling jak-hd)
#   jak3-hd    decompiler_out/jak3/levels/ljakc/jakc-highres-lod0.glb         (sibling jak-hd)
#   daxp-hd    decompiler_out/jak3/levels/loutro2/ottsel-daxpants-lod0.glb    (sibling dax-hd)
#   keira3-hd  decompiler_out/jak3/levels/lkeira/keira-highres-lod0.glb       (sibling keira-hd)
#   ysamos-hd  decompiler_out/jak2/levels/lysamsam/youngsamos-highres-lod0.glb (sibling samos-hd)
#
# Driver GLB (3rd arg) — the SAME driver GLB the sibling character uses:
#   jak-hd / jak2-hd / jak3-hd   decompiler_out/jak1/levels/common/eichar-lod0.glb
#   dax-hd / daxp-hd             decompiler_out/jak1/levels/common/sidekick-lod0.glb
#   keira-hd / keira3-hd         decompiler_out/jak1/levels/village1/assistant-lod0.glb
#   samos-hd / ysamos-hd         decompiler_out/jak1/levels/village1/sage-lod0.glb
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
#    i.e. the character name must be <= 9 chars (jak-hd/dax-hd=6, jak2-hd/jak3-hd/daxp-hd=7,
#    keira-hd/samos-hd=8, keira3-hd/ysamos-hd=9 — all M5 bonus stems pass).
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

# a-bis. PHYSICS JOINT INJECTION, at the point of production (secondary-motion, 2026-08-13).
# A hair chain only articulates the geometry it has joints for, and Keira's ran out halfway
# down every strand: measured on the shipped mesh, 95% of a strand's skinned mass sat at
# s=1.8..2.2 bone lengths while the articulated part reached 1.0, so the whole distal half was
# carried RIGIDLY by the last joint. That is the owner's most-repeated defect ("les pointes sont
# ancrées au même titre que les racines"), and it is also why no root->tip gradient was
# representable: with rootlock=1 a 2-joint chain has exactly ONE free link.
#
# The injection runs HERE, on the donor, and identically in build_enhanced_models.sh — the art
# group, the k->e table and the baked mesh must agree on the joint list or the physics resolves
# its joints by name against a rig the mesh does not have. Driving both from ONE committed spec
# is what makes disagreement impossible, rather than detectable later (owner: "quand une perte
# se répète, on la rend impossible au point de production").
#
# No spec for a character => untouched donor, byte-identical passthrough.
#
# The augmented donor goes to a STABLE path, not the scratch dir: retarget_fill_table.py records
# the donor path it read into <char>-k2e.json's `hd_glb`, and every later reader resolves the mesh
# through it (physics_c6_volumes.load_geometry, hence physics_keira_gen2). A temp path there
# produces a k2e that points at a directory deleted on exit — measured: gen2 died with "could not
# load geometry for keira-hd" immediately after the first regeneration.
INJ_SPEC="recharged_assets/$CHAR-inject-joints.txt"
if [ -f "$INJ_SPEC" ]; then
  INJ_OUT="out/jak1/fr3/skin/$CHAR-donor-injected.glb"
  mkdir -p "$(dirname "$INJ_OUT")"
  log "0/3 inject physics joints from $INJ_SPEC -> $INJ_OUT"
  python3 .autoport/physics_inject_joints.py --in "$HD" --out "$INJ_OUT" \
      --spec "$INJ_SPEC" --report "$TMP/$CHAR-inject.txt" \
    || { log "FATAL: joint injection for $CHAR failed"; exit 1; }
  HD="$INJ_OUT"
fi

log "1/3 prep rip GLB -> build_actor-ready (keep HD skeleton, drop align, u32->u8, compact)"
python3 "$PREP" --in "$HD" --out "$TMP/$CHAR.glb" --report "$TMP/$CHAR-prep.txt"

# c. fabricate the art-group with the existing build_actor emitter
log "2/3 fabricate art-group -> $OUT/$CHAR-ag.go (merc model name: $CHAR-lod0)"
"$BA" -g jak1 "$TMP/$CHAR.glb" "$OUT/$CHAR-ag.go"

# d. retarget k->driver table + the offline do-joint-math! numeric proof.
#    Cycle 2 (owner DoD): the generator runs the FACE-FINGER-GATE and exits 2 on any face/
#    finger/beard joint left on ancestor glue. Per-character justifications live HERE so a
#    regeneration reproduces the owner-approved decisions verbatim.
TABLE_FLAGS=()
case "$CHAR" in
  jak-hd)
    # CYCLE 3, authored --map (clothing clip, blue/white tunic-vs-pants interpenetration):
    #   jak1's shirt* joints ride the cloth-sim curves (2.8-9.1cm swing vs the thigh at walk/run)
    #   while the HD tunic overlaps the HD pants with only 1-3cm clearance; the stock coat is only
    #   ~8% shirt*-weighted and tolerates it, the HD tunic is ~35% -> guaranteed interpenetration.
    #   Remap to the raw thighs: the HD pivots for shirtL/Rthigh are bit-identical to Lthigh/Rthigh
    #   (0.1400, 1.3020, 0) and both parent to hips, so the retarget stays exact and the relative
    #   motion tunic-vs-pants becomes 0.
    #   NOT done for Lknee/Rknee -> pantsL/Rknee: those HD joints also carry skin+belt geometry
    #   that must not inherit the 9.86cm pant flare.
    TABLE_FLAGS=(--map 'shirtLthigh=Lthigh,shirtRthigh=Rthigh') ;;
  # M5 bonus looks jak2-hd (jak2 ljakdax jak-highres) and jak3-hd (jak3 ljakc jakc-highres) are
  # Jak donors on the SAME eichar-lod0 driver rig as jak-hd, but they do NOT inherit jak-hd's
  # flags: jak-hd's --map is jak1-TUNIC-specific (the jakone-highres donor wears the jak1 outfit
  # and carries shirtLthigh/shirtRthigh cloth-sim joints). These donors wear the jak2/jak3
  # outfits, which have no shirt* joints at all — the map would name joints that don't exist and
  # hard-fail the gate. No flags: the default STRICT gate applies (no unmapped face/finger/beard
  # joints tolerated).
  # CYCLE 4 owner item 3: jakm-hd (Jak 3 MASQUE BAISSÉ) is the SAME jakc-highres donor as jak3-hd
  # (there is no separate masked art-group in jak3 — the lowered goggles are a blerc blend target,
  # baked into the merc verts at append time by hd_merc_swap --bake-blerc-target). Same driver,
  # same strict gate, no flags — identical to jak3-hd here.
  # CYCLE 5 item 3 (owner 11:05 "il me les FAUT TOUS", cinematic-only): the exhaustive scan of the
  # jak2+jak3 dumps found one cinematic Jak geometry we had never shipped —
  #   jakp-hd = jak2 ldjakbrn jak-highres-prison-lod0 (the prison / dark-eco EXPERIMENTS look the
  #             owner named; 63 joints, the same rig size as jak2-hd)
  # (A second candidate, jakf-hd = jak3 ljkfeet jakc-feet-lod0, was removed completely on the
  # owner's 2026-08-05 19:30 verdict — buggy and useless; do not re-add it.)
  # It rides the SAME eichar-lod0 driver rig with the jak2/jak3 outfits (no jak1 shirt* cloth-sim
  # joints), so like jak2-hd/jak3-hd it takes NO flags and runs under the default STRICT
  # FACE-FINGER-GATE (no unmapped face/finger joint tolerated).
  jak2-hd|jak3-hd|jakm-hd|jakp-hd)
    TABLE_FLAGS=() ;;
  # M5: daxp-hd (jak3 loutro2 ottsel-daxpants) is a Daxter donor on the SAME sidekick-lod0 rig ->
  # inherits dax-hd's --accept-unmapped set verbatim.
  dax-hd|daxp-hd)
    TABLE_FLAGS=(--accept-unmapped 'tongue=jak1 sidekick rig has no tongue chain; tongue rides the head via mode-2 glue, mouth-interior animation comes from blerc (class B);uvula=jak1 sidekick rig has no uvula joint; rides the head via mode-2 glue;pinky=jak1 sidekick rig has index/middle/thumb only; pinky rides the hand via mode-2 glue (curls with the hand, no independent articulation in ANY jak1 daxter anim);ring[A-Z]=jak1 sidekick rig has index/middle/thumb only; ring finger rides the hand via mode-2 glue') ;;
  # M5: ysamos-hd (jak2 lysamsam youngsamos-highres) is a Samos donor on the SAME sage-lod0 rig ->
  # inherits samos-hd's --accept-unmapped set verbatim.
  # M5: keira3-hd (jak3 lkeira keira-highres) inherits keira-hd, which carries NO flags — so, like
  # keira-hd, it has no case entry and runs the table generator with the default (strict) gate.
  samos-hd|ysamos-hd)
    TABLE_FLAGS=(--accept-unmapped 'beardDriver=jak3-only sim-helper bone; the ANIMATED beard chain below it (beard_lip, beard) is name-mapped mode-1 to sage beard joints, so the beard follows sage swings at HD pivots; beardDriver itself rides the head via mode-2 glue (mapping it too would double-apply the delta);Birdjaw=jak1 sage rig has no bird-jaw joint (BIRDhead1 is the deepest bird head bone); the beak rides BIRDhead via mode-2 glue') ;;
esac
log "3/3 emit retarget k->driver table + run the offline do-joint-math! numeric proof"
python3 "$TABLE" --name "$CHAR" --hd "$HD" --driver "$DRIVER" --emit-dir "$OUT" "${TABLE_FLAGS[@]}"

# e. report the produced files + sizes, and sanity-check the art-group
AG="$OUT/$CHAR-ag.go"
[ -f "$AG" ] || { log "FATAL: $AG was not produced"; exit 1; }
AG_SZ="$(stat -c %s "$AG")"
[ "$AG_SZ" -gt 4096 ] || { log "FATAL: $AG is only $AG_SZ bytes (<= 4096) — art-group fabrication looks empty"; exit 1; }

log "DONE:"
ls -la "$AG" "$OUT/$CHAR-k2e.json" "$OUT/$CHAR-k2e.gc-snippet" 2>/dev/null | sed 's/^/[hd-actor-ag]   /'
