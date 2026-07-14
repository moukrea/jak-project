#!/usr/bin/env bash
# scripts/shell/build_enhanced_models.sh
#
# CONDITIONAL "enhanced HD models" asset-bake for jak1 (autoport Grecharged-hd-models).
#
# The 4 skinless HD character GLBs staged in recharged_assets/hd_models/ are dropped
# into the merc-replacement importer's discovery dir (custom_assets/jak1/merc_replacements/)
# under their EXACT merc-ctrl names (<name>-lod0.glb — NO -mg suffix, or the swap
# silently no-ops), then a RESTRICTED decompile regenerates only the 3 affected level
# FR3 (GAME/village1/village2) with the swapped meshes. Those 3 enhanced FR3 are moved
# into out/jak1/fr3/enhanced/; the stock FR3 are restored byte-identical so the BASE
# set stays stock. The Android packaging ships enhanced/ as an OPTIONAL overlay, so the
# on-device runtime's get_fr3_dir()/enhanced/ lookup can pick it up behind a toggle.
#
# CONDITIONAL: if the jak2 assets are absent, this is a NO-OP success (exit 0) — the
# enhanced HD bake is gated on jak2 being present; jak1 then simply builds STOCK and the
# in-game toggle stays hidden.
#
# IDEMPOTENT: safe to re-run — out/jak1/fr3/enhanced/ is recreated fresh each run, the
# merc_replacements drop-in dir is populated and removed within the run, and the stock
# FR3 are always restored (via an EXIT trap) even on error.
#
# This script does NOT touch goal_src / game / decompiler source — it only orchestrates
# the existing decompiler binary and shuffles build-output FR3 files.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

log(){ echo "[enhanced-models] $*"; }

# ---------------------------------------------------------------------------
# 1. The 4 staged HD GLBs and their REQUIRED drop-in names (merc-ctrl name,
#    i.e. <name>-lod0 WITHOUT the -mg suffix — proven empirically: with -mg the
#    swap silently no-ops; stripping -mg fires "Replacing <name>-lod0 …").
#      eichar-lod0    = Jak       -> COMMON  -> out/jak1/fr3/GAME.fr3
#      sidekick-lod0  = Daxter    -> COMMON  -> out/jak1/fr3/GAME.fr3
#      geologist-lod0 = Samos     -> village2 -> out/jak1/fr3/village2.fr3
#      assistant-lod0 = Keira     -> village1 -> out/jak1/fr3/village1.fr3
# ---------------------------------------------------------------------------
STAGE_DIR="recharged_assets/hd_models"
# "<source-basename-in-stage>:<drop-in-name>" (both keep the .glb extension)
GLBS=(
  "eichar-lod0.glb:eichar-lod0.glb"
  "sidekick-lod0.glb:sidekick-lod0.glb"
  "geologist-lod0.glb:geologist-lod0.glb"
  "assistant-lod0.glb:assistant-lod0.glb"
)
# The merc-ctrl names whose "Replacing <name> for <lvl>" line MUST appear in the log.
REPLACE_NAMES=(eichar-lod0 sidekick-lod0 geologist-lod0 assistant-lod0)

# The 3 FR3 that the swaps regenerate (stock ones get backed up + restored).
ENHANCED_FR3=(GAME.fr3 village1.fr3 village2.fr3)

FR3_DIR="out/jak1/fr3"
ENHANCED_OUT="$FR3_DIR/enhanced"
MERC_DIR="custom_assets/jak1/merc_replacements"
DECOMP_BIN="build/decompiler/decompiler"

# ---------------------------------------------------------------------------
# 2. jak2 gate — absence is a VALID state, not an error.
# ---------------------------------------------------------------------------
if [ ! -f "iso_data/jak2/DGO/LJAKDAX.DGO" ] || [ ! -f "iso_data/jak2/DGO/LINTCSTB.DGO" ]; then
  log "jak2 assets absent — skipping enhanced HD bake (jak1 builds stock, toggle stays hidden)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Require the stock FR3 to already exist (the enhanced bake is an OVERLAY
#    on top of a normal jak1 decomp, and we restore these afterwards).
# ---------------------------------------------------------------------------
for f in "${ENHANCED_FR3[@]}"; do
  if [ ! -f "$FR3_DIR/$f" ]; then
    log "stock FR3 missing — run the normal jak1 decomp first"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 4. Require the decompiler binary.
# ---------------------------------------------------------------------------
if [ ! -x "$DECOMP_BIN" ]; then
  log "decompiler binary missing ($DECOMP_BIN) — build it first (e.g. cmake --build build --target decompiler)"
  exit 1
fi

# ---------------------------------------------------------------------------
# 5. Back up the stock FR3 to a temp dir so we can always restore them.
# ---------------------------------------------------------------------------
BACKUP_DIR="$(mktemp -d)"
for f in "${ENHANCED_FR3[@]}"; do
  cp -p "$FR3_DIR/$f" "$BACKUP_DIR/$f"
done
log "stock FR3 backed up to $BACKUP_DIR"

# ---------------------------------------------------------------------------
# EXIT trap: ALWAYS restore stock FR3 into out/jak1/fr3/ and remove the
# merc_replacements drop-in dir + the temp backup — so a failed/interrupted run
# leaves the base set STOCK (byte-identical) and a subsequent normal decomp
# stays stock. Runs on success too (stock restore is the intended end state).
# ---------------------------------------------------------------------------
cleanup(){
  local rc=$?
  # Restore stock FR3 (only if the backup copies still exist).
  for bf in "${ENHANCED_FR3[@]}"; do
    if [ -f "$BACKUP_DIR/$bf" ]; then
      cp -p "$BACKUP_DIR/$bf" "$FR3_DIR/$bf" 2>/dev/null || true
    fi
  done
  # Remove the drop-in dir so the next normal decomp stays stock.
  rm -rf "$ROOT/$MERC_DIR" 2>/dev/null || true
  # Remove the temp backup.
  rm -rf "$BACKUP_DIR" 2>/dev/null || true
  if [ "$rc" -ne 0 ]; then
    log "FAILED (rc=$rc) — stock FR3 restored, merc_replacements cleaned up."
  fi
  return "$rc"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 6. Populate custom_assets/jak1/merc_replacements/ by COPYING the 4 GLBs under
#    their correct <name>-lod0.glb drop-in names.
# ---------------------------------------------------------------------------
mkdir -p "$MERC_DIR"
for spec in "${GLBS[@]}"; do
  src="${spec%%:*}"
  dst="${spec##*:}"
  if [ ! -f "$STAGE_DIR/$src" ]; then
    log "staged GLB missing: $STAGE_DIR/$src"
    exit 1
  fi
  cp -p "$STAGE_DIR/$src" "$MERC_DIR/$dst"
done
log "populated $MERC_DIR with ${#GLBS[@]} HD GLB(s)"

# ---------------------------------------------------------------------------
# 7. Restricted decompile to regenerate ONLY the swapped FR3.
#    The importer discovers custom_assets/jak1/merc_replacements/*.glb and swaps
#    each matching merc into the level FR3 during decompilation. We capture the
#    log and REQUIRE all 4 "Replacing <name>-lod0" lines.
# ---------------------------------------------------------------------------
DECOMP_LOG="$(mktemp)"
log "running restricted decompile (KERNEL/GAME/VI1/VI2) — regenerating swapped FR3…"
set +e
./build/decompiler/decompiler decompiler/config/jak1/jak1_config.jsonc iso_data decompiler_out \
  --config-override '{"levels_extract": true, "rip_levels": false, "save_texture_pngs": false, "dgo_names": ["CGO/KERNEL.CGO","CGO/GAME.CGO","DGO/VI1.DGO","DGO/VI2.DGO"]}' \
  2>&1 | tee "$DECOMP_LOG"
DECOMP_RC="${PIPESTATUS[0]}"
set -e
# --- FALLBACK (if the restricted run asserts on some setups) --------------------
# Some setups assert when the DGO set is pared down (missing engine deps). If that
# happens, comment out the restricted run above and use a FULL decomp instead:
#   ./scripts/shell/decomp.sh 2>&1 | tee "$DECOMP_LOG"; DECOMP_RC="${PIPESTATUS[0]}"
# The restricted run is the DEFAULT (far faster); the full decomp is the fallback.

if [ "$DECOMP_RC" -ne 0 ]; then
  rm -f "$DECOMP_LOG"
  log "decompile failed (rc=$DECOMP_RC) — see output above; stock FR3 will be restored."
  exit 1
fi

# VERIFY all 4 swaps fired.
MISSING=()
for name in "${REPLACE_NAMES[@]}"; do
  if ! grep -qE "Replacing ${name}( |:)" "$DECOMP_LOG"; then
    MISSING+=("$name")
  fi
done
rm -f "$DECOMP_LOG"
if [ "${#MISSING[@]}" -ne 0 ]; then
  log "swap verification FAILED — no 'Replacing …' line for: ${MISSING[*]}"
  log "(check the drop-in names match the merc-ctrl NAME <name>-lod0 without -mg)"
  exit 1
fi
log "all ${#REPLACE_NAMES[@]} HD swaps confirmed in the decompile log."

# ---------------------------------------------------------------------------
# 8. Move the 3 now-enhanced FR3 into out/jak1/fr3/enhanced/ (recreate fresh).
# ---------------------------------------------------------------------------
rm -rf "$ENHANCED_OUT"
mkdir -p "$ENHANCED_OUT"
for f in "${ENHANCED_FR3[@]}"; do
  if [ ! -f "$FR3_DIR/$f" ]; then
    log "expected regenerated FR3 missing after decompile: $FR3_DIR/$f"
    exit 1
  fi
  mv "$FR3_DIR/$f" "$ENHANCED_OUT/$f"
done
log "enhanced FR3 moved to $ENHANCED_OUT/"

# ---------------------------------------------------------------------------
# 9. Restore the stock FR3 from the backup into out/jak1/fr3/ so the base set
#    stays stock (byte-identical). (The EXIT trap also does this, but we do it
#    explicitly here so the summary sizes are correct and the state is right
#    even on the happy path.)
# ---------------------------------------------------------------------------
for f in "${ENHANCED_FR3[@]}"; do
  cp -p "$BACKUP_DIR/$f" "$FR3_DIR/$f"
done
log "stock FR3 restored into $FR3_DIR/"

# ---------------------------------------------------------------------------
# 10. Remove the drop-in dir (the trap also does this; explicit for clarity).
# ---------------------------------------------------------------------------
rm -rf "$MERC_DIR"

# ---------------------------------------------------------------------------
# 11. Summary.
# ---------------------------------------------------------------------------
log "DONE — enhanced HD model set written to $ENHANCED_OUT/:"
for f in "${ENHANCED_FR3[@]}"; do
  if [ -f "$ENHANCED_OUT/$f" ]; then
    printf '[enhanced-models]     enhanced/%-14s %s bytes\n' "$f" "$(stat -c %s "$ENHANCED_OUT/$f")"
  fi
done
log "stock (unchanged) FR3 in $FR3_DIR/:"
for f in "${ENHANCED_FR3[@]}"; do
  if [ -f "$FR3_DIR/$f" ]; then
    printf '[enhanced-models]     %-14s          %s bytes\n' "$f" "$(stat -c %s "$FR3_DIR/$f")"
  fi
done
log "base FR3 set stays STOCK; enhanced/ is the OPTIONAL overlay shipped for the toggle."
