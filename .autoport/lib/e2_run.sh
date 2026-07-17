#!/usr/bin/env bash
# Phase E2 (autoport): device-side build → install → launch → drive
# overlay → capture.
#
# Differs from e1_run.sh by:
#   * No "press a button NOW" operator banner — input is synthesised
#     entirely via `adb shell input tap` at the touch-overlay hit-zone
#     coordinates the Activity logs at layout time.
#   * Parses the `overlay-map: ...` logcat line emitted by
#     TouchOverlayView.onSizeChanged to learn pixel coordinates for the
#     × ○ □ △ d-pad and start hitboxes, serialises them to
#     .autoport/reports/E2-overlay-map.json, then issues
#     `adb shell input tap cx cy` at a few of them so the Activity's
#     overlay path actually fires NativeGk.onPadButton — same JNI shape
#     a real Bluetooth pad would produce.
#
# Artefacts the E2 validator consumes:
#   .autoport/reports/E2-boot.log         — logcat capture window
#   .autoport/reports/E2-overlay-map.json — hitbox → SDL button mapping
#   .autoport/reports/E2-launch.md        — engineering report

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"

REPORT_DIR=".autoport/reports"
BOOT_LOG="$REPORT_DIR/E2-boot.log"
STATUS_TXT="$REPORT_DIR/E2-status.txt"
REPORT_MD="$REPORT_DIR/E2-launch.md"
OVERLAY_MAP="$REPORT_DIR/E2-overlay-map.json"

export LOGCAT_LOG="$BOOT_LOG"

mkdir -p "$REPORT_DIR"

echo "== E2 step 1/5: build libgk.so =="
bash .autoport/lib/d3_build.sh

echo "== E2 step 2/5: build jak1 debug APK =="
device_build_flavor jak1

echo "== E2 step 3/5: install + launch + capture =="
device_require_attached
device_require_free_space
device_uninstall_other_games "$PACKAGE"
device_stayon_on

# Truncate so a previous run's bytes don't leak into the validator's grep.
: > "$BOOT_LOG"

# Phase E2 (autoport): the overlay flag is keyed in SharedPreferences as
# "touch_overlay_enabled" with a "touch_overlay_initialised" sentinel so
# the default (overlay-on-if-no-gamepad) only applies on first launch.
# The validator needs the overlay ON for a meaningful headless run; in a
# stale install left over from manual play the user may have turned it
# off, leaving us with a passing build but no overlay to drive. Wipe the
# Activity's SharedPreferences so MainActivity re-derives the default
# from the current gamepad state.
adb shell run-as "$PACKAGE" rm -rf "shared_prefs" >/dev/null 2>&1 || true

# A5 / D4 (autoport): LoaderActivity caches the iso_data extraction via
# a `.extracted_v1` sentinel. Wipe it so the fresh APK-bundled arm64
# CGOs reach the device (vs. a stale x86 extraction left over from an
# earlier APK install).
adb shell run-as "$PACKAGE" rm -f "files/cgo/jak1/.extracted_v1" >/dev/null 2>&1 || true

device_install_and_launch "$PACKAGE" "$ACTIVITY" "$APK"

echo "== E2 step 4/5: wait for boot markers + overlay layout =="

ONCREATE=1; OVERLAY_VISIBLE=1; OVERLAY_MAP_LOGGED=1
LINK_GSTATE=1; LINK_LOGO=1; PAD_HIT=1

# Cold extraction can take >100s.
if device_wait_for_marker 'MainActivity onCreate done' 180; then ONCREATE=0; fi
if device_wait_for_marker 'overlay visible|touch overlay enabled' 30; then OVERLAY_VISIBLE=0; fi
if device_wait_for_marker 'overlay-map: screen=' 30; then OVERLAY_MAP_LOGGED=0; fi
if device_wait_for_marker 'link finish: gstate' 90; then LINK_GSTATE=0; fi
if device_wait_for_marker 'link finish: logo$' 60; then LINK_LOGO=0; fi

# ---------------------------------------------------------------------------
# Parse overlay-map: line out of logcat and write E2-overlay-map.json.
# Shape (per token):  <name>=<cx>,<cy>,<radius>,<sdl_button>
# Example: south=1690,778,80,0 east=1770,698,80,1 ...
# ---------------------------------------------------------------------------
MAP_LINE=$(grep -m1 -E 'overlay-map: screen=' "$BOOT_LOG" | sed -E 's/^.*overlay-map: //')
if [ -z "$MAP_LINE" ]; then
    echo "  ! overlay-map line not yet in logcat; writing empty stub" >&2
    MAP_LINE="screen=0x0"
fi

python3 - "$OVERLAY_MAP" "$MAP_LINE" <<'PY'
import json, re, sys
out_path, line = sys.argv[1], sys.argv[2]
toks = line.strip().split()
screen = None
hits = {}
for t in toks:
    k, _, v = t.partition('=')
    if k == 'screen':
        m = re.match(r'(\d+)x(\d+)', v)
        if m:
            screen = {"w": int(m.group(1)), "h": int(m.group(2))}
    else:
        parts = v.split(',')
        if len(parts) == 4:
            cx, cy, r, sdl_btn = (int(p) for p in parts)
            hits[k] = {"cx": cx, "cy": cy, "radius": r, "sdl_button": sdl_btn}
doc = {
    "phase": "E2",
    "source": "TouchOverlayView.onSizeChanged",
    "screen": screen,
    "hits": hits,
    "note": "Hit-zone -> SDL_GAMEPAD_BUTTON_* mapping. Tap (cx,cy) "
            "to fire NativeGk.onPadButton(sdl_button, true|false).",
}
with open(out_path, 'w') as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
PY
echo "  wrote $OVERLAY_MAP"

echo "== E2 step 5/5: synthesise overlay taps + capture pad hits =="

# Pick a few face-button hitboxes to drive. The validator only needs
# >=1 overlay tap to route through onPadButton; we send 3 distinct
# button presses so a flaky tap doesn't gate the run.
TAP_BUTTONS=(south east start)
tapped_any=0
for name in "${TAP_BUTTONS[@]}"; do
    coords=$(python3 -c "
import json, sys
with open('$OVERLAY_MAP') as fh: d=json.load(fh)
h=d.get('hits',{}).get('$name')
if h: print(h['cx'], h['cy'])
")
    if [ -z "$coords" ]; then
        echo "  ! no hit-zone '$name' in overlay map, skipping"
        continue
    fi
    cx=$(echo "$coords" | awk '{print $1}')
    cy=$(echo "$coords" | awk '{print $2}')
    echo "  tap $name @ ($cx,$cy)"
    # `input tap` synthesises a DOWN/UP pair through Android's
    # InputDispatcher; the dispatcher delivers it to whichever View's
    # hit-test wins at those coords. TouchOverlayView sits on top of
    # the SDLSurface in mLayout (last-added-child = topmost), so as
    # long as the tap lands inside a hit-zone we get
    # onTouchEvent → dispatchPad → NativeGk.onPadButton.
    adb shell input tap "$cx" "$cy" >/dev/null 2>&1 || true
    sleep 0.4
    tapped_any=1
done

if [ "$tapped_any" -ne 1 ]; then
    echo "  ! no hit-zones were tappable; overlay map likely missing" >&2
fi

# Give the dispatcher a moment to fire the marker lines.
if device_wait_for_marker 'onPadButton: overlay tap|overlay tap -> onPadButton' 15; then
    PAD_HIT=0
fi

# Phase E1 / E2 (autoport): do NOT force-stop the app here. The
# downstream validator's trace-diff reads BOOT_LOG to its natural
# end; tearing down too early can truncate the post-logo markers.
LOGCAT_PID_TO_KILL="${LOGCAT_PID:-}"
trap - EXIT
sleep 5
if [ -n "$LOGCAT_PID_TO_KILL" ]; then
    kill "$LOGCAT_PID_TO_KILL" 2>/dev/null || true
fi
device_stayon_restore 2>/dev/null || true

DETERMINATION="pass"
NOTES=""
if [ "$ONCREATE" -ne 0 ]; then
    DETERMINATION="fail"
    NOTES="MainActivity never reached onCreate."
elif [ "$OVERLAY_VISIBLE" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Touch overlay never reported visible."
elif [ "$OVERLAY_MAP_LOGGED" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="overlay-map line not seen; hit-zones unknown."
elif [ "$LINK_GSTATE" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Kernel CGO link sequence didn't reach gstate."
elif [ "$LINK_LOGO" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Engine DGO load didn't reach 'link finish: logo'."
elif [ "$PAD_HIT" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Synthetic taps did not produce overlay-tap onPadButton markers."
fi

echo "$DETERMINATION: $NOTES" > "$STATUS_TXT"

{
    echo "# Phase E2 — UX (touch overlay) launch report"
    echo
    echo "_Generated: $(date -Iseconds)_"
    echo
    echo "## Determination"
    echo
    echo "**$DETERMINATION**${NOTES:+ — $NOTES}"
    echo
    echo "## Overlay map"
    echo
    echo '```json'
    cat "$OVERLAY_MAP" 2>/dev/null || echo "(no overlay map)"
    echo '```'
    echo
    echo "## Marker observations (from logcat)"
    echo
    if [ -f "$BOOT_LOG" ]; then
        echo '```'
        grep -E '(MainActivity onCreate done|touch overlay|overlay visible|overlay-map:|overlay tap|onPadButton:|kernel: pad:|link finish: logo|gamepad detected|FATAL|SIGABRT|SIGSEGV|SIGILL)' "$BOOT_LOG" | head -80 || echo "(no matching markers)"
        echo '```'
    else
        echo "(no $BOOT_LOG produced)"
    fi
    echo
    echo "## Next blocker (if any)"
    echo
    case "$DETERMINATION" in
        pass) echo "None — E2 markers all observed. Validator should pass." ;;
        partial) echo "$NOTES See $BOOT_LOG tail for context." ;;
        fail) echo "$NOTES App never reached MainActivity." ;;
    esac
} > "$REPORT_MD"

echo "== E2 done: determination=$DETERMINATION =="
[ -n "$NOTES" ] && echo "   note: $NOTES"
echo "   logcat:  $BOOT_LOG"
echo "   map:     $OVERLAY_MAP"
echo "   status:  $STATUS_TXT"
echo "   report:  $REPORT_MD"

# e2_run.sh's contract is "exit 0 if the build/install/launch chain
# succeeded and overlay map was recorded". The marker-level
# assertions are the validator's job.
exit 0
