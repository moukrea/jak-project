#!/usr/bin/env bash
# deploy_verify_assets.sh — PROVE the device is running the freshly-built GOAL
# code (CGO/DGO assets), not just the native libgk.so. Companion to
# deploy_verify.sh, which only covers libgk.so.
#
# WHY THIS EXISTS (2026-07-09): the HUD/menu/gameplay logic lives in GOAL code
# that compiles into out/<game>/iso/*.CGO|*.DGO. On the dev Redmi these are
# delivered via the slim-APK CGO pack unpacked to  run-as <pkg> files/cgo/<game>/
# (fake_iso scans it as an overlay). deploy_verify.sh passed while the device ran an INTERMEDIATE
# round-3 GAME.CGO — a fix "committed + built + libgk-deployed" but the GOAL
# CGOs never re-pushed => the owner saw stale HUD behavior. This guard catches it.
#
# Checks (all must pass):
#   1. FRESHNESS: newest out/<game>/iso/*.CGO|*.DGO is NEWER than the newest
#      goal_src/<game> source mtime (catches "edited GOAL but didn't rebuild").
#   2. FULL-SET MATCH: every *.CGO|*.DGO in out/<game>/iso/ has a byte-identical
#      (md5) counterpart at files/cgo/<game>/ on the device (catches a
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
# CRITICAL: the device is arm64 — it MUST match the ARM64 CGO build tree, NOT the
# x86 tree (out/<game>/iso). Pushing x86 CGOs to the arm64 device SIGILLs at frame 0
# (2026-07-09 incident: pushed out/jak1/iso x86 5958c908 over the device's arm64
# 998b05ce -> illegal instruction). ISO_DIR override wins; else prefer -arm64-full.
if [ -n "${3:-}" ]; then ISO_DIR="$3"
elif [ -d "out/${GAME}-arm64-full/iso" ]; then ISO_DIR="out/${GAME}-arm64-full/iso"
elif [ -d "out/${GAME}-arm64/iso" ]; then ISO_DIR="out/${GAME}-arm64/iso"
else ISO_DIR="out/${GAME}/iso"; fi
die() { echo "DEPLOY-ASSETS FAIL: $*" >&2; exit 1; }

# Phase Grecharged-external-assets (2026-07): the slim APK ships the arm64
# CGO/DGO set as a "CGO pack" that LoaderActivity unpacks to files/cgo/<game>/
# (fake_iso scans it FIRST as an overlay). This is now the ONLY device engine
# location — the legacy adb-pushed engine-overlay path is retired.
DEV_DIR="files/cgo/${GAME}"
"$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'ls files/cgo/${GAME}/*.CGO'" >/dev/null 2>&1 \
  || die "no CGO overlay on device at $DEV_DIR (run-as $PKG) — engine pack never unpacked?"
echo "  device CGO dir: $DEV_DIR"

[ -d "$ISO_DIR" ] || die "no build dir $ISO_DIR"
echo "  ref arm64 build tree: $ISO_DIR"
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

# 3. *COMMON.TXT match (jak1 only). The text banks carry the menu strings (e.g. the
# AO carousell values); they ride the cgo pack overlay (files/cgo/<game>). A stale
# re-extract or a never-pushed bank shows the owner "unknown ID". Match every device
# TXT against the android overlay source:
#   - files/cgo/<game>/*COMMON.TXT  vs  out/<game>-android-text/  (android overlay banks)
# We only assert on TXT files PRESENT on the device: fail on content mismatch, or on
# a device TXT with no local counterpart; do NOT fail on extra local files.
if [ "$GAME" = "jak1" ]; then
  txt_match(){ # $1=device dir  $2=local dir  $3=label
    local ddir="$1" ldir="$2" label="$3"
    "$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'ls $ddir/*COMMON.TXT'" >/dev/null 2>&1 || { echo "  ($label) no device TXT at $ddir — skip"; return 0; }
    [ -d "$ldir" ] || { echo "  ($label) no local dir $ldir — skip"; return 0; }
    local dtxt lmd5 dmd5 tmiss=0 tmis=0 n=0
    dtxt=$("$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'cd $ddir 2>/dev/null && md5sum *COMMON.TXT 2>/dev/null'" 2>/dev/null | tr -d '\r')
    [ -n "$dtxt" ] || { echo "  ($label) no device TXT at $ddir — skip"; return 0; }
    while read -r dmd5 df; do
      [ -n "$dmd5" ] || continue
      df=$(basename "$df"); n=$((n+1))
      if [ ! -f "$ldir/$df" ]; then echo "  ($label) device TXT $df has NO local counterpart in $ldir"; tmiss=$((tmiss+1)); continue; fi
      lmd5=$(md5sum "$ldir/$df" | cut -d' ' -f1)
      if [ "$lmd5" != "$dmd5" ]; then echo "  ($label) STALE TXT on device: $df (build=$lmd5 dev=$dmd5)"; tmis=$((tmis+1)); fi
    done <<< "$dtxt"
    [ "$tmiss" -eq 0 ] || die "$tmiss device TXT($label) lack a local counterpart — text source out of sync"
    [ "$tmis"  -eq 0 ] || die "$tmis device TXT($label) STALE — device shows OLD text (re-push $label banks)"
    echo "  ok ($label): $n device *COMMON.TXT byte-identical to $ldir"
  }
  txt_match "files/cgo/${GAME}"      "out/${GAME}-android-text"  "overlay"
fi
