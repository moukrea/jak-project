#!/usr/bin/env bash
# gsr_ownercap.sh — Gcrash-swamp-real OWNER-CAPTURE handoff (the faithful repro the
# blind headless navigator cannot achieve). Uses the built-in pad_replay harness
# (game/system/pad_replay.cpp, flush-per-tick) so the OWNER records his real skilled
# pontoon crossing ONCE (his input survives the crash-to-home), then we REPLAY it
# byte-identically to reproduce the crash headless, capture forensics, fix, and verify.
# NO target.drive — the movement is the owner's real controller/touch input.
#
#   gsr_ownercap.sh arm      # set record props + warp village2-dock + raise pontoons, launch.
#                            #   -> OWNER then walks the pontoons toward the swamp until it
#                            #      crashes. Input is saved flush-per-tick to pad_demo.inputs.
#   gsr_ownercap.sh pull [dst]   # pull the recording to .autoport/reports/Gcrash-swamp-real/
#   gsr_ownercap.sh replay [tag] # push a recording + replay it, capture the crash forensics
#   gsr_ownercap.sh status   # show whether a recording exists + its frame count
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
OUT=.autoport/reports/Gcrash-swamp-real; mkdir -p "$OUT"
REC=/data/data/$PKG/files/pad_demo.inputs
A(){ "$ADB" -s "$SERIAL" "$@"; }
cmd="${1:-status}"

case "$cmd" in
  arm)
    A shell svc power stayon true >/dev/null 2>&1 || true
    A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    A shell setprop debug.opengoal.pad_replay record >/dev/null 2>&1
    A shell setprop debug.opengoal.level.warp village2-dock >/dev/null 2>&1
    A shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1
    A shell "setprop debug.opengoal.task.close '33'" >/dev/null 2>&1
    A shell "run-as $PKG sh -c 'rm -f $REC'" 2>/dev/null || true
    A shell am force-stop $PKG >/dev/null 2>&1
    A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    echo "ARMED. Owner: once Jak spawns at the Rock Village dock (pontoons raised),"
    echo "walk/run across the pontoons toward Boggy Swamp until it crashes to home."
    echo "Your input is recorded flush-per-tick to pad_demo.inputs. Then run: gsr_ownercap.sh pull"
    ;;
  pull)
    DST="${2:-$OUT/pad_demo.inputs}"
    A shell "run-as $PKG sh -c 'cat $REC'" > "$DST" 2>/dev/null || { echo "no recording"; exit 1; }
    SZ=$(stat -c %s "$DST" 2>/dev/null || echo 0); echo "pulled $DST ($SZ bytes, ~$((SZ/6)) frames)"
    ;;
  replay)
    TAG="${2:-replay1}"; SRC="${3:-$OUT/pad_demo.inputs}"
    [ -f "$SRC" ] || { echo "no recording at $SRC — run 'pull' first"; exit 1; }
    LOG="$OUT/$TAG-logcat.log"
    A shell svc power stayon true >/dev/null 2>&1 || true
    # push the recording, set replay + the SAME warp/task so the world state matches the record
    A push "$SRC" /sdcard/pad_demo.inputs >/dev/null 2>&1
    A shell "run-as $PKG sh -c 'cp /sdcard/pad_demo.inputs $REC'" 2>/dev/null
    A shell setprop debug.opengoal.pad_replay replay >/dev/null 2>&1
    A shell setprop debug.opengoal.level.warp village2-dock >/dev/null 2>&1
    A shell "setprop debug.opengoal.task.close '33'" >/dev/null 2>&1
    A shell am force-stop $PKG >/dev/null 2>&1
    A logcat -c >/dev/null 2>&1; : > "$LOG"
    A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
    LP=$!; trap 'kill $LP 2>/dev/null' EXIT
    A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    echo "replaying $SRC (tag=$TAG); watching for crash..."
    for i in $(seq 1 200); do grep -qaE 'GK-DIAG sig=|Fatal signal' "$LOG" && { echo "CRASH ~${i}s"; break; }; sleep 1; done
    sleep 2
    { echo "=== replay $TAG $(date -Is) ==="
      grep -aoE 'GK-DIAG sig=[0-9]+ fault=0x[0-9a-f]+ pc=0x[0-9a-f]+ lr=0x[0-9a-f]+' "$LOG" | tail -3
      grep -aE "A38-TRIPWIRE.*nearest-fn|A34-DIAG (fp-walk|lr-)|Adding level swamp|display swamp" "$LOG" | tail -25
    } | tee "$OUT/$TAG-result.txt"
    kill $LP 2>/dev/null || true; trap - EXIT
    for p in pad_replay level.warp task.close; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1; done
    ;;
  status)
    A shell "run-as $PKG sh -c 'ls -la $REC 2>/dev/null'" 2>/dev/null || echo "no recording on device"
    ;;
  *) echo "usage: gsr_ownercap.sh {arm|pull [dst]|replay [tag] [src]|status}"; exit 2;;
esac
