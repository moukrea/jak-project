#!/usr/bin/env bash
# capture_device_beat.sh — snapshot an Android-device frame at an intro/title
# "beat" and (optionally) gate it against a pristine desktop golden via
# frame_compare.py. Foundation helper for the chronological pixel-match phases.
#
# WHY a separate device anchor than the golden:
#   The desktop golden is anchored to a DETERMINISTIC frame counter
#   (g_gfx_data->frame_idx from boot). The phone's slow loader desyncs both
#   wall-clock AND frame counts, so on-device we anchor by EVENT: the phase
#   runner drives gk to the beat (a logged state transition, or a fixed wait
#   after a known marker) and then calls this script to snapshot + compare.
#   This script is the capture+compare PRIMITIVE; the per-beat trigger lives in
#   each phase's runner.
#
# The Redmi (eae4df44) is SHARED with a parallel x86 emulator, so we HARD-PIN
# the serial and refuse to run against anything else — a stray screencap of the
# wrong device (or the wrong app in the foreground) would silently corrupt a
# pixel-match result.
#
# Usage:
#   capture_device_beat.sh OUT.png [GOLDEN.png] [-- <extra frame_compare args>]
#
# Exit code:
#   - no golden: 0 on a successful capture, nonzero on capture/precondition error
#   - with golden: propagates frame_compare.py's verdict (0=MATCH, 1=MISMATCH)

set -uo pipefail

SERIAL="eae4df44"                                   # Redmi Note 9 Pro (arm64) — ONLY
PKG="org.opengoal.gk.jak1"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$SCRIPT_DIR/frame_compare.py"

die() { echo "capture_device_beat: ERROR: $*" >&2; exit 2; }

# --- parse args ---
OUT=""; GOLDEN=""; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; EXTRA=("$@"); break ;;
    *) if [ -z "$OUT" ]; then OUT="$1"; elif [ -z "$GOLDEN" ]; then GOLDEN="$1"; else die "unexpected arg: $1"; fi ;;
  esac
  shift
done
[ -n "$OUT" ] || die "usage: capture_device_beat.sh OUT.png [GOLDEN.png] [-- frame_compare args]"

# --- refuse the wrong device ---
if [ -n "${ANDROID_SERIAL:-}" ] && [ "$ANDROID_SERIAL" != "$SERIAL" ]; then
  die "ANDROID_SERIAL=$ANDROID_SERIAL but this helper is pinned to $SERIAL (shared-emulator safety)"
fi
[ -x "$ADB" ] || command -v "$ADB" >/dev/null 2>&1 || die "adb not found/executable at '$ADB' (set ADB=...)"

# --- device present & authorized ---
state="$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)"
[ "$state" = "device" ] || die "device $SERIAL not in 'device' state (got '${state:-none}'). Plug phone, accept USB-debugging."

# --- verify the FOREGROUND really is jak1 (shared device may show another app) ---
focus="$("$ADB" -s "$SERIAL" shell dumpsys window 2>/dev/null | grep -m1 -E 'mCurrentFocus|mFocusedApp' || true)"
case "$focus" in
  *"$PKG"*) : ;;  # ok
  *) die "foreground is NOT $PKG — refusing to capture. focus line: ${focus:-<none>}" ;;
esac

# --- capture (exec-out keeps the PNG byte-exact; no CRLF mangling) ---
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
"$ADB" -s "$SERIAL" exec-out screencap -p > "$OUT" 2>/dev/null || die "screencap failed"
[ -s "$OUT" ] || die "screencap produced an empty file"
dims="$(identify -format '%wx%h' "$OUT" 2>/dev/null || true)"
[ -n "$dims" ] || die "captured file is not a readable image: $OUT"
echo "capture_device_beat: captured $OUT ($dims) from $SERIAL"

# --- optional gate against a golden ---
if [ -n "$GOLDEN" ]; then
  [ -f "$GOLDEN" ] || die "golden not found: $GOLDEN"
  [ -f "$FC" ] || die "frame_compare.py not found at $FC"
  echo "capture_device_beat: gating against golden $GOLDEN"
  python3 "$FC" "$GOLDEN" "$OUT" "${EXTRA[@]}"
  exit $?
fi
exit 0
