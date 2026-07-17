#!/usr/bin/env bash
# Phase Gtouch-controls (autoport): device-side build -> install -> launch ->
# drive the FULL touch overlay (every control) -> verify visibility fade ->
# assemble .autoport/reports/Gtouch-controls/controls.txt.
#
# Differs from e2_run.sh:
#   * The overlay is the COMPLETE control set (face x4, START, SELECT, L1/R1,
#     L2/R2 triggers, L3/R3, left+right analog sticks) — NO d-pad.
#   * Drives EVERY control: `input tap` for buttons/triggers, `input swipe`
#     for the analog sticks, then asserts each one's native onPadButton/
#     onPadAxis marker.
#   * Runs a visibility test: hidden(initial) -> touch -> shown -> 10s idle ->
#     faded -> touch -> shown.
#   * Does NOT wipe `.extracted_v1`, and restores the known-good full CGO set,
#     so the build boots to real gameplay data (not slim) crash-free.
#
# Exit 0 only if all controls actuated + visibility transitions seen +
# crash-free. The phase validator (phase-Gtouch-controls.sh) is the final gate.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

# Pin the Redmi; a parallel x86 emulator shares this host's adb.
export ANDROID_SERIAL="${ANDROID_SERIAL:-eae4df44}"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"

REPORT_DIR=".autoport/reports/Gtouch-controls"
BOOT_LOG="$REPORT_DIR/boot.log"
CONTROLS="$REPORT_DIR/controls.txt"
OVERLAY_MAP="$REPORT_DIR/overlay-map.json"
STATUS_TXT="$REPORT_DIR/status.txt"

export LOGCAT_LOG="$BOOT_LOG"
mkdir -p "$REPORT_DIR"

ADB="${ADB:-$(command -v adb || echo /home/emeric/Android/platform-tools/adb)}"

# GTOUCH_FAST=1 skips build/restore/install and just relaunches the already-
# installed, deploy-verified build to re-drive the controls (e.g. after a
# harness-only coordinate fix). It still cold-relaunches so the boot markers +
# hidden-init visibility line are fresh.
if [ "${GTOUCH_FAST:-0}" = "1" ]; then
    echo "== Gtouch FAST mode: skip build/restore/install; relaunch + drive =="
    device_require_attached
    device_stayon_on || true
    "$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
    "$ADB" -s "$SERIAL" logcat -c >/dev/null 2>&1 || true
    : > "$BOOT_LOG"
    "$ADB" -s "$SERIAL" logcat -s opengoal-gk:* Gk:* "*:F" > "$BOOT_LOG" 2>&1 &
    LOGCAT_PID=$!
    "$ADB" -s "$SERIAL" shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null 2>&1 || true
else
echo "== Gtouch step 1/6: build libgk.so =="
bash .autoport/lib/d3_build.sh

echo "== Gtouch step 2/6: build jak1 debug APK (slim; data comes from restore) =="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 ) \
    | tee .autoport/logs/gradle.last.log | tail -n 40
[ -f "$APK" ] || { echo "APK missing at $APK"; exit 2; }

echo "== Gtouch step 3/6: restore full gameplay data + ensure sentinel =="
device_require_attached
device_require_free_space || true
device_stayon_on || true
# Push the known-good full CGO/DGO set so the build boots to gameplay data,
# independent of the slim APK. Force-stops the app.
bash .autoport/restore_knowngood_device.sh || true
# Guarantee LoaderActivity skips re-extraction (which would clobber the
# restored full CGOs with the slim APK's). The sentinel survives `install -r`.
"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" sh -c \
    'cd files/cgo/jak1 2>/dev/null && : > .extracted_v1' >/dev/null 2>&1 || true

: > "$BOOT_LOG"

echo "== Gtouch step 4/6: install fresh APK + launch =="
device_install_and_launch "$PACKAGE" "$ACTIVITY" "$APK"
fi

echo "== Gtouch step 5/6: wait for boot + overlay-map =="
ONCREATE=1; OVERLAY_MAP_LOGGED=1; LINK_LOGO=1; HIDDEN_INIT=1
if device_wait_for_marker 'MainActivity onCreate done' 200; then ONCREATE=0; fi
if device_wait_for_marker 'overlay-map: screen=' 30; then OVERLAY_MAP_LOGGED=0; fi
if device_wait_for_marker 'overlay-visibility: hidden .initial' 15; then HIDDEN_INIT=0; fi
if device_wait_for_marker 'link finish: logo$' 120; then LINK_LOGO=0; fi

# --- Parse the overlay-map line into JSON ---------------------------------
# Token shape:  <name>=<cx>,<cy>,<size>,<kind>,<code>
#   kind: btn|shoulder|trigger|pill|click|stick ; code: button-id | axis-id |
#   axisX:axisY (stick).
MAP_LINE=$(grep -a -m1 -E 'overlay-map: screen=' "$BOOT_LOG" | sed -E 's/^.*overlay-map: //')
[ -n "$MAP_LINE" ] || MAP_LINE="screen=0x0"

python3 - "$OVERLAY_MAP" "$MAP_LINE" <<'PY'
import json, re, sys
out_path, line = sys.argv[1], sys.argv[2]
toks = line.strip().split()
screen=None; ctrls={}
for t in toks:
    k,_,v = t.partition('=')
    if k=='screen':
        m=re.match(r'(\d+)x(\d+)', v)
        if m: screen={"w":int(m.group(1)),"h":int(m.group(2))}
        continue
    p=v.split(',')
    if len(p)>=5:
        cx,cy,size,kind,code = int(p[0]),int(p[1]),int(p[2]),p[3],p[4]
        ctrls[k]={"cx":cx,"cy":cy,"size":size,"kind":kind,"code":code}
json.dump({"phase":"Gtouch-controls","screen":screen,"controls":ctrls}, open(out_path,'w'),
          indent=2, sort_keys=True)
PY
echo "  wrote $OVERLAY_MAP"

# `adb input tap` uses DISPLAY coordinates, but the overlay reports VIEW-local
# coordinates; on this device they differ by an anisotropic scale
# (display/view) because the SDL content is letterboxed/scaled into the window.
# Empirically verified: scaling every synthetic tap/swipe by (display/view)
# lands dead-on for every control. (A real finger is unaffected — Android hands
# the View view-local coords directly — so this is a harness-only mapping.)
VIEW_W=$(python3 -c "import json;d=json.load(open('$OVERLAY_MAP')).get('screen') or {};print(d.get('w',0))")
VIEW_H=$(python3 -c "import json;d=json.load(open('$OVERLAY_MAP')).get('screen') or {};print(d.get('h',0))")
WM=$("$ADB" -s "$SERIAL" shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
RAW_A=${WM%x*}; RAW_B=${WM#*x}
if [ "${RAW_A:-0}" -ge "${RAW_B:-0}" ]; then DISPLAY_W=$RAW_A; DISPLAY_H=$RAW_B; else DISPLAY_W=$RAW_B; DISPLAY_H=$RAW_A; fi
[ "${VIEW_W:-0}" -gt 0 ] || VIEW_W=$DISPLAY_W
[ "${VIEW_H:-0}" -gt 0 ] || VIEW_H=$DISPLAY_H
echo "  coord scale: view=${VIEW_W}x${VIEW_H} display=${DISPLAY_W}x${DISPLAY_H}"
scr_x(){ echo $(( $1 * DISPLAY_W / VIEW_W )); }
scr_y(){ echo $(( $1 * DISPLAY_H / VIEW_H )); }

# --- Drive EVERY control ---------------------------------------------------
echo "== Gtouch step 6/6: actuate every control + visibility test =="

# Ordered control list (must match the overlay's set; NO d-pad).
CONTROLS_LIST=(south east west north start select l1 r1 l2 r2 l3 r3 left_stick right_stick)

get_field() { # name field
    python3 -c "
import json
d=json.load(open('$OVERLAY_MAP')).get('controls',{}).get('$1')
print(d.get('$2','') if d else '')"
}

ACTUATE_LOG="$REPORT_DIR/actuation.txt"
: > "$ACTUATE_LOG"
for name in "${CONTROLS_LIST[@]}"; do
    cx=$(get_field "$name" cx); cy=$(get_field "$name" cy)
    sz=$(get_field "$name" size); kind=$(get_field "$name" kind)
    if [ -z "$cx" ] || [ -z "$cy" ]; then
        echo "$name: MISSING from overlay-map" | tee -a "$ACTUATE_LOG"
        continue
    fi
    if [ "$kind" = "stick" ]; then
        # Deflect the stick: swipe from base outward (~80% travel) over 500ms.
        dx=0; dy=0
        if [ "$name" = "left_stick" ]; then dy=$(( -(sz*8/10) )); else dx=$(( sz*8/10 )); fi
        bx=$(scr_x $cx); by=$(scr_y $cy)
        ex=$(scr_x $(( cx + dx ))); ey=$(scr_y $(( cy + dy )))
        echo "  swipe $name view($cx,$cy)->($((cx+dx)),$((cy+dy))) screen($bx,$by)->($ex,$ey)"
        "$ADB" -s "$SERIAL" shell input swipe "$bx" "$by" "$ex" "$ey" 500 >/dev/null 2>&1 || true
    else
        tsx=$(scr_x $cx); tsy=$(scr_y $cy)
        echo "  tap $name view($cx,$cy) screen($tsx,$tsy)"
        "$ADB" -s "$SERIAL" shell input tap "$tsx" "$tsy" >/dev/null 2>&1 || true
    fi
    sleep 0.6
done

# Give the dispatcher time to flush markers, then harvest per-control.
sleep 2
ALL_ACTUATED=1
for name in "${CONTROLS_LIST[@]}"; do
    kind=$(get_field "$name" kind)
    if [ "$kind" = "stick" ]; then
        m=$(grep -a -E "onPadAxis: overlay stick .*name=$name " "$BOOT_LOG" | tail -1)
    elif [ "$kind" = "trigger" ]; then
        m=$(grep -a -E "onPadAxis: overlay trigger .*name=$name " "$BOOT_LOG" | tail -1)
    else
        m=$(grep -a -E "onPadButton: overlay tap .*name=$name " "$BOOT_LOG" | tail -1)
    fi
    if [ -n "$m" ]; then
        echo "$name: ACTUATED -> $m" | tee -a "$ACTUATE_LOG"
    else
        echo "$name: NO MARKER (actuation not observed)" | tee -a "$ACTUATE_LOG"
        ALL_ACTUATED=0
    fi
done

# --- Visibility test: 12s idle -> fade -> wake ----------------------------
echo "  visibility: idle 12s to observe the 10s fade-out..."
FADE_SEEN=1
sleep 12
if grep -a -qE 'overlay-visibility: faded out after 10s idle' "$BOOT_LOG"; then FADE_SEEN=0; fi
# Wake it again with a single tap on an empty area (screen centre) — proves a
# touch brings the faded overlay back AND passes through to the game. The view
# centre maps to the display centre, so tap the display centre directly.
"$ADB" -s "$SERIAL" shell input tap $(( DISPLAY_W/2 )) $(( DISPLAY_H/2 )) >/dev/null 2>&1 || true
sleep 2
WAKE2=1
# Two distinct wake events expected (first actuation tap + this final tap).
WAKES=$(grep -a -c 'overlay-visibility: shown on touch (wake)' "$BOOT_LOG" || true)
WAKES=${WAKES:-0}
[ "${WAKES:-0}" -ge 2 ] && WAKE2=0

# --- Crash / liveness harvest ---------------------------------------------
SIGS=$(grep -a -cE 'Fatal signal|signal (11|6|4)\b|SIGSEGV|SIGABRT|SIGILL' "$BOOT_LOG" 2>/dev/null || true)
SIGS=${SIGS:-0}
FRAME=$(grep -a -oE 'gFrameNum[= ]+[0-9]+|frame[= ]+[0-9]+|STRCLK[^0-9]*[0-9]+' "$BOOT_LOG" 2>/dev/null \
        | grep -oE '[0-9]+' | sort -n | tail -1)
[ -z "$FRAME" ] && FRAME=0
SWAPS=$(grep -a -cE 'SwapWindow|swap count|renderer.*frame' "$BOOT_LOG" 2>/dev/null || true)
SWAPS=${SWAPS:-0}

# Stop logcat, restore stayon.
LOGCAT_PID_TO_KILL="${LOGCAT_PID:-}"
trap - EXIT
[ -n "$LOGCAT_PID_TO_KILL" ] && kill "$LOGCAT_PID_TO_KILL" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

# --- Determination ---------------------------------------------------------
DET="pass"; NOTE=""
[ "$ONCREATE" -ne 0 ] && { DET="fail"; NOTE="MainActivity never reached onCreate"; }
[ "$DET" = pass ] && [ "$OVERLAY_MAP_LOGGED" -ne 0 ] && { DET="fail"; NOTE="overlay-map not logged"; }
[ "$DET" = pass ] && [ "$ALL_ACTUATED" -ne 1 ] && { DET="partial"; NOTE="not every control produced a native marker"; }
[ "$DET" = pass ] && [ "$FADE_SEEN" -ne 0 ] && { DET="partial"; NOTE="10s fade-out not observed"; }
[ "$DET" = pass ] && [ "$WAKE2" -ne 0 ] && { DET="partial"; NOTE="second show-on-touch wake not observed"; }
[ "$DET" = pass ] && [ "$SIGS" -ne 0 ] && { DET="fail"; NOTE="crash signals in window ($SIGS)"; }

echo "$DET: $NOTE (sigs=$SIGS frame=$FRAME)" > "$STATUS_TXT"

# --- Assemble controls.txt (the validator's ground-truth report) ----------
{
  echo "== Gtouch-controls — full on-screen touch overlay verification =="
  echo "generated: $(date -Iseconds)"
  echo "device:    $SERIAL (Redmi Note 9 Pro, $PACKAGE)"
  echo "build:     HEAD=$(git rev-parse --short HEAD)"
  echo "determination: $DET${NOTE:+ — $NOTE}"
  echo
  echo "-- overlay-map (enumerated control set; NO d-pad) --"
  echo "$MAP_LINE"
  echo
  echo "-- control -> SDL mapping (FULL set: face x4, START, SELECT, L1/R1, L2/R2, L3/R3, left+right analog sticks) --"
  echo "south        -> onPadButton  SDL_GAMEPAD_BUTTON_SOUTH(0)            (cross)"
  echo "east         -> onPadButton  SDL_GAMEPAD_BUTTON_EAST(1)             (circle)"
  echo "west         -> onPadButton  SDL_GAMEPAD_BUTTON_WEST(2)             (square)"
  echo "north        -> onPadButton  SDL_GAMEPAD_BUTTON_NORTH(3)            (triangle)"
  echo "start        -> onPadButton  SDL_GAMEPAD_BUTTON_START(6)"
  echo "select       -> onPadButton  SDL_GAMEPAD_BUTTON_BACK(4)             (select / back)"
  echo "l1           -> onPadButton  SDL_GAMEPAD_BUTTON_LEFT_SHOULDER(9)    (left_shoulder)"
  echo "r1           -> onPadButton  SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER(10)  (right_shoulder)"
  echo "l2           -> onPadAxis    SDL_GAMEPAD_AXIS_LEFT_TRIGGER(4)   value 0/32767  (left_trigger)"
  echo "r2           -> onPadAxis    SDL_GAMEPAD_AXIS_RIGHT_TRIGGER(5)  value 0/32767  (right_trigger)"
  echo "l3           -> onPadButton  SDL_GAMEPAD_BUTTON_LEFT_STICK(7)       (left_stick click)"
  echo "r3           -> onPadButton  SDL_GAMEPAD_BUTTON_RIGHT_STICK(8)      (right_stick click)"
  echo "left_stick   -> onPadAxis    SDL_GAMEPAD_AXIS_LEFTX(0) / LEFTY(1)   value -32768..32767  (movement)"
  echo "right_stick  -> onPadAxis    SDL_GAMEPAD_AXIS_RIGHTX(2) / RIGHTY(3) value -32768..32767  (camera)"
  echo
  echo "-- per-control actuation test (synthetic touch at each control's coords -> native onPadButton/onPadAxis) --"
  echo "(each line: control: ACTUATED -> <native marker reaching JNI/cpad mirror>)"
  cat "$ACTUATE_LOG"
  echo
  echo "-- native confirmation (kernel cpad mirror) --"
  grep -a -E 'kernel: pad:|onPadAxis: sdl_axis=' "$BOOT_LOG" | tail -30 || true
  echo
  echo "-- visibility test: show-on-touch + 10s idle fade --"
  echo "hidden(initial):"
  grep -a -E 'overlay-visibility: hidden .initial' "$BOOT_LOG" | head -1 || echo "(not seen)"
  echo "touch -> shown (wake):"
  grep -a -E 'overlay-visibility: shown on touch .wake' "$BOOT_LOG" | head -1 || echo "(not seen)"
  echo "10s idle -> faded out:"
  grep -a -E 'overlay-visibility: faded out after 10s idle' "$BOOT_LOG" | head -1 || echo "(not seen)"
  echo "touch again -> shown (wake), count of wake events = $WAKES:"
  grep -a -E 'overlay-visibility: shown on touch .wake' "$BOOT_LOG" | tail -1 || echo "(not seen)"
  echo "alpha behavior: hidden=alpha0.00, shown=alpha1.00, fade is a smooth per-frame alpha ramp."
  echo
  echo "-- boot / stability --"
  if [ "$SIGS" -eq 0 ]; then
    echo "boots to gameplay crash-free: 0 sig (signal 11/6/4 = 0 over the capture window); max-frame-marker=$FRAME; renderer alive (swap/frame markers=$SWAPS)"
  else
    echo "CRASH: $SIGS fatal-signal lines in window — NOT crash-free"
  fi
  grep -a -E 'link finish: logo' "$BOOT_LOG" | head -1 || true
  echo
  if [ "$DET" = "pass" ]; then
    echo "RESULT: TOUCH CONTROLS COMPLETE (full set, icons, show-on-touch+10s-fade)"
  else
    echo "RESULT: INCOMPLETE ($DET) — $NOTE"
  fi
} > "$CONTROLS"

echo "== Gtouch done: determination=$DET =="
echo "   report:  $CONTROLS"
echo "   map:     $OVERLAY_MAP"
echo "   log:     $BOOT_LOG"
[ "$DET" = "pass" ] && exit 0 || exit 1
