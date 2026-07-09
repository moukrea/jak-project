#!/usr/bin/env bash
# deploy_verify_assets.sh — PROVE the device is running the freshly-built GOAL
# code (CGO/DGO assets), not just the native libgk.so. Companion to
# deploy_verify.sh, which only covers libgk.so.
#
# WHY THIS EXISTS (2026-07-09): the HUD/menu/gameplay logic lives in GOAL code
# that compiles into out/<game>/iso/*.CGO|*.DGO. On the dev Redmi these are
# adb-pushed to  run-as <pkg> files/iso_data/<game>/  (the APK-bundled copy is
# stale by design). deploy_verify.sh passed while the device ran an INTERMEDIATE
# round-3 GAME.CGO — a fix "committed + built + libgk-deployed" but the GOAL
# CGOs never re-pushed => the owner saw stale HUD behavior. This guard catches it.
#
# Checks (all must pass):
#   1. FRESHNESS: newest out/<game>/iso/*.CGO|*.DGO is NEWER than the newest
#      goal_src/<game> source mtime (catches "edited GOAL but didn't rebuild").
#   2. FULL-SET MATCH: every *.CGO|*.DGO in out/<game>/iso/ has a byte-identical
#      (md5) counterpart at files/iso_data/<game>/ on the device (catches a
#      partial/stale/never-pushed asset set).
#
# Usage: deploy_verify_assets.sh [SERIAL] [GAME]   (defaults: eae4df44 jak1)
# Exit 0 = device provably runs the fresh GOAL CGO/DGO set; nonzero = NOT.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SERIAL="${1:-eae4df44}"
GAME="${2:-jak1}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.${GAME}"
ISO_DIR="out/${GAME}/iso"
DEV_DIR="files/iso_data/${GAME}"
die() { echo "DEPLOY-ASSETS FAIL: $*" >&2; exit 1; }

[ -d "$ISO_DIR" ] || die "no build dir $ISO_DIR"
LOCAL_FILES=$(cd "$ISO_DIR" && ls *.CGO *.DGO 2>/dev/null)
[ -n "$LOCAL_FILES" ] || die "no CGO/DGO in $ISO_DIR"
N_LOCAL=$(echo "$LOCAL_FILES" | wc -l)

# 1. Freshness: newest built asset vs newest GOAL source.
NEWEST_BUILT=$(find "$ISO_DIR" -type f \( -name '*.CGO' -o -name '*.DGO' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
NEWEST_SRC=$(find "goal_src/${GAME}" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
if [ -n "$NEWEST_SRC" ] && [ -n "$NEWEST_BUILT" ] && [ "$NEWEST_BUILT" -lt "$NEWEST_SRC" ]; then
  die "built CGO/DGO ($(date -d @$NEWEST_BUILT +%H:%M)) OLDER than newest goal_src/$GAME ($(date -d @$NEWEST_SRC +%H:%M)) — rebuild the GOAL chain before deploy"
fi
echo "  ok: $N_LOCAL built CGO/DGO newer than newest goal_src/$GAME"

# 2. Full-set md5 match: local build vs device (one adb round-trip).
DEV_MD5=$("$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'cd $DEV_DIR 2>/dev/null && md5sum *.CGO *.DGO 2>/dev/null'" 2>/dev/null | tr -d '\r')
[ -n "$DEV_MD5" ] || die "no CGO/DGO on device at $DEV_DIR (run-as $PKG) — assets never pushed?"
# Build an associative map basename->md5 from device output.
declare -A DMAP
while read -r h f; do [ -n "$h" ] && DMAP["$(basename "$f")"]="$h"; done <<< "$DEV_MD5"

MISMATCH=0; MISSING=0
while read -r f; do
  [ -z "$f" ] && continue
  L=$(md5sum "$ISO_DIR/$f" | cut -d' ' -f1)
  D="${DMAP[$f]:-}"
  if [ -z "$D" ]; then echo "  MISSING on device: $f"; MISSING=$((MISSING+1));
  elif [ "$L" != "$D" ]; then echo "  STALE on device: $f (build=$L dev=$D)"; MISMATCH=$((MISMATCH+1)); fi
done <<< "$LOCAL_FILES"

[ "$MISSING" -eq 0 ] || die "$MISSING asset(s) missing on device — push the full set to $DEV_DIR"
[ "$MISMATCH" -eq 0 ] || die "$MISMATCH asset(s) STALE on device — device runs OLD GOAL code (re-push out/$GAME/iso/ to $DEV_DIR)"
echo "DEPLOY-ASSETS PASS: device $SERIAL runs the fresh GOAL set ($N_LOCAL/$N_LOCAL CGO/DGO byte-identical to $ISO_DIR)."
