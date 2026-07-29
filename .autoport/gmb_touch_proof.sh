#!/usr/bin/env bash
# =====================================================================================
# Grecharged-mesh-browser REOPEN — INJECTED-GESTURE PROOF
#
# Owner, 2026-07-29: "C'est impossible a parcourir via le tactile (le mesh browser)".
# The previous gate accepted the WORD "touch" in a report, which proves nothing. This
# script proves the only thing that matters: that a REAL touch event, injected from
# outside the process, CHANGES THE BROWSER'S STATE.
#
# Method. Every gesture below is injected with `input tap` / `input swipe` (and, for the
# two-finger pinch, `monkey --pct-pinchzoom`, because `input` is single-pointer and
# `sendevent` on /dev/input/event3 is SELinux-denied to shell on this device). Those go
# through the ordinary Android input pipeline into TouchOverlayView.onTouchEvent, exactly
# like the owner's finger. After each gesture the browser's OWN observable state is read
# back from files/mesh_browser_state.txt via run-as. A test passes only if the state
# MOVED in the expected field. No screenshot is used and no visual judgement is made:
# the agent is not allowed to judge the visual, and a screenshot could not prove
# causation anyway.
#
# Gamepad is used for ONE thing only: walking the option menu to reach the browser
# (the menu row itself is pre-existing and the owner already reaches it). Everything
# under test after that point is touch.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${S:-eae4df44}"
PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-mesh-browser/touch-proof
mkdir -p "$OUT"
LOG="$OUT/proof-log.txt"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }

adb(){ "$ADB" -s "$S" "$@"; }
INJECT="/data/data/$PKG/files/cpad_inject"
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
padb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }

# ---- state readback ------------------------------------------------------------------
STATE=""
snap(){ STATE="$(adb exec-out run-as $PKG cat files/mesh_browser_state.txt 2>/dev/null)"; }
# field <name> -> value ("" if absent). Read from the last snap().
field(){ printf '%s\n' "$STATE" | grep -oE "(^| )$1=[^ ]*" | tail -1 | cut -d= -f2-; }

PASS=0; FAIL=0
# check <label> <field> <before> <after> <mode:changed|equals> [expected]
check(){
  local label="$1" f="$2" b="$3" a="$4" mode="$5" exp="${6:-}"
  local ok=0
  case "$mode" in
    changed) [ -n "$a" ] && [ "$b" != "$a" ] && ok=1 ;;
    equals)  [ "$a" = "$exp" ] && ok=1 ;;
    grew)    [ -n "$a" ] && [ -n "$b" ] && awk "BEGIN{exit !($a > $b)}" && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then PASS=$((PASS+1)); say "  PASS  $label : $f  $b -> $a"
  else FAIL=$((FAIL+1)); say "  FAIL  $label : $f  $b -> $a  (expected $mode ${exp:-})"; fi
}

# ---- 0. device + coordinate space ----------------------------------------------------
say "=== 0. DEVICE ==="
adb devices -l | tee -a "$LOG" | grep -q "$S" || { say "device $S absent"; exit 1; }
say "model: $(adb shell getprop ro.product.model | tr -d '\r')"
FOCUS="$(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
say "focus: $FOCUS"

# `input` injects in the LOGICAL display space, which follows the current rotation. The
# app is fixed-landscape on a portrait-native panel, so this is 2400x1080, not 1080x2400.
# Read it rather than assume it: guessing the wrong axis would silently invert every test.
CUR="$(adb shell dumpsys window displays 2>/dev/null | grep -oE 'cur=[0-9]+x[0-9]+' | head -1 | cut -d= -f2)"
[ -n "$CUR" ] || CUR="$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
VW="${CUR%x*}"; VH="${CUR#*x}"
say "injection coordinate space: ${VW}x${VH}"

# normalized [0,1] (in the APP's view space) -> injection pixels
px(){ awk "BEGIN{printf \"%d\", $1*$VW}"; }
py(){ awk "BEGIN{printf \"%d\", $1*$VH}"; }
tap_n(){ adb shell input tap "$(px $1)" "$(py $2)"; sleep "${3:-0.8}"; }
swipe_n(){ adb shell input swipe "$(px $1)" "$(py $2)" "$(px $3)" "$(py $4)" "${5:-500}"; sleep "${6:-0.8}"; }

# ---- 1. reach the browser (gamepad nav; the row is pre-existing) ----------------------
say ""
say "=== 1. OPEN THE BROWSER (menu nav only; every later step is touch) ==="
adb shell run-as $PKG rm -f files/mesh_browser_state.txt >/dev/null 2>&1 || true
opened=0
for K in 23 22 24 21 25 20 26; do
  padb "start" 2.5
  padb "down" 0.7; padb "down" 0.7; padb "x" 2.0      # OPTIONS
  padb "down" 0.8; padb "x" 2.0                        # GRAPHIC OPTIONS
  for i in $(seq 1 7); do padb "down" 0.5; done        # RECHARGED SETTINGS row
  padb "x" 1.8
  for i in $(seq 1 "$K"); do padb "down" 0.35; done    # walk to MESH BROWSER
  padb "x" 2.5
  snap
  if [ -n "$STATE" ]; then say "browser OPEN after $K downs; mode=$(field mode)"; opened=1; break; fi
  say "  (K=$K did not open it; backing out)"
  padb "triangle" 0.8; padb "triangle" 0.8; padb "triangle" 0.8; padb "start" 1.2
done
[ "$opened" = 1 ] || { say "COULD NOT OPEN THE BROWSER — abort"; exit 1; }
say "--- initial state ---"; printf '%s\n' "$STATE" | tee -a "$LOG"

# ---- 2. LEVEL PICKER: tap a level row directly ---------------------------------------
say ""
say "=== 2. TOUCH: tap a level row (direct selection, no cursor) ==="
b_mode="$(field mode)"
tap_n 0.30 0.20 3.0     # first level row band
snap; a_mode="$(field mode)"
check "tap level row -> enters the mesh LIST" "mode" "$b_mode" "$a_mode" changed
say "--- state ---"; printf '%s\n' "$STATE" | tee -a "$LOG"
NTOT="$(field n_filtered)"
say "list holds n_filtered=$NTOT rows (village1 is 3613 — a one-row-at-a-time list is unusable by construction)"

# ---- 3. header buttons by tap --------------------------------------------------------
say ""
say "=== 3. TOUCH: header filter buttons ==="
b="$(field filter)"; tap_n 0.89 0.07 1.5; snap; a="$(field filter)"
check "tap TIE filter button" "filter" "$b" "$a" equals "TIE"
b="$a"; tap_n 0.49 0.07 1.5; snap; a="$(field filter)"
check "tap FAILING filter button" "filter" "$b" "$a" equals "FAILING"
b="$a"; tap_n 0.29 0.07 1.5; snap; a="$(field filter)"
check "tap ALL filter button" "filter" "$b" "$a" equals "ALL"

# ---- 4. SWIPE-SCROLL the list --------------------------------------------------------
say ""
say "=== 4. TOUCH: swipe to scroll the list ==="
snap; b="$(field scroll)"
swipe_n 0.45 0.80 0.45 0.30 600 1.2      # finger up -> content scrolls down
snap; a="$(field scroll)"
check "swipe up scrolls the list down" "scroll" "$b" "$a" grew
b="$a"
swipe_n 0.45 0.30 0.45 0.80 600 1.2      # finger down -> back up
snap; a="$(field scroll)"
check "swipe down scrolls the list back up" "scroll" "$a" "$b" grew

# ---- 5. FLING / inertia --------------------------------------------------------------
say ""
say "=== 5. TOUCH: fling -> inertia keeps scrolling after the finger lifts ==="
snap; b="$(field scroll)"
adb shell input swipe "$(px 0.45)" "$(py 0.85)" "$(px 0.45)" "$(py 0.20)" 200
sleep 0.15; snap; mid="$(field scroll)"
sleep 1.5;  snap; a="$(field scroll)"
say "  scroll: before=$b just-after-release=$mid settled=$a"
check "fling carries the list past the release point" "scroll" "$mid" "$a" grew

# ---- 6. FAST-SCROLL HANDLE: thousands of rows in ONE gesture -------------------------
say ""
say "=== 6. TOUCH: drag the right-edge scroll handle across the whole list ==="
snap; b="$(field scroll)"
swipe_n 0.97 0.20 0.97 0.88 900 1.5
snap; a="$(field scroll)"
say "  scroll: $b -> $a  (n_filtered=$(field n_filtered))"
check "one handle drag crosses the entire ${NTOT}-row list" "scroll" "$b" "$a" grew
# and back to the top, so the row taps below are deterministic
swipe_n 0.97 0.88 0.97 0.18 900 1.5; snap
say "  returned to scroll=$(field scroll)"

# ---- 7. tap a row to select, tap again to open --------------------------------------
say ""
say "=== 7. TOUCH: tap a row to select it, tap it again to open it ==="
snap; b="$(field sel)"; bmat="$(field material)"
tap_n 0.40 0.45 1.2; snap; a="$(field sel)"; amat="$(field material)"
check "tap a row selects THAT row" "sel" "$b" "$a" changed
say "  material: $bmat -> $amat"
b_mode="$(field mode)"
tap_n 0.40 0.45 6.0      # second tap on the selected row = warp+observe (level load)
snap; a_mode="$(field mode)"
check "second tap opens the mesh (warp -> OBSERVE)" "mode" "$b_mode" "$a_mode" equals "OBSERVE"
say "--- observe state ---"; printf '%s\n' "$STATE" | tee -a "$LOG"

# ---- 8. ORBIT by drag, ELEVATION by the other drag axis ------------------------------
say ""
say "=== 8. TOUCH: drag to orbit (horizontal=azimuth, vertical=elevation) ==="
snap; b="$(field cam_az)"; bel="$(field cam_el)"
swipe_n 0.30 0.45 0.70 0.45 600 1.0
snap; a="$(field cam_az)"
check "horizontal drag orbits the camera" "cam_az" "$b" "$a" changed
swipe_n 0.50 0.30 0.50 0.60 600 1.0
snap; ael="$(field cam_el)"
check "vertical drag changes ELEVATION (a distinct gesture)" "cam_el" "$bel" "$ael" changed

# ---- 9. PINCH to zoom (two real pointers) -------------------------------------------
say ""
say "=== 9. TOUCH: pinch to zoom (genuine 2-pointer MotionEvents) ==="
say "  note: 'input' is single-pointer and sendevent on /dev/input/event3 is SELinux-denied"
say "  to shell on this device, so the two-finger gesture is injected with monkey's"
say "  pinch-zoom generator, which emits real 2-pointer MotionEvents into this package."
snap; b="$(field cam_dist)"; bp="$(printf '%s\n' "$STATE" | grep -oE 'pinches=[0-9]+' | cut -d= -f2)"
adb shell monkey -p $PKG --pct-pinchzoom 100 --pct-touch 0 --pct-motion 0 --pct-trackball 0 \
    --pct-nav 0 --pct-majornav 0 --pct-syskeys 0 --pct-appswitch 0 --pct-flip 0 \
    --pct-anyevent 0 --pct-permission 0 --throttle 120 -v 40 >>"$LOG" 2>&1
sleep 2.0; snap; a="$(field cam_dist)"; ap="$(printf '%s\n' "$STATE" | grep -oE 'pinches=[0-9]+' | cut -d= -f2)"
say "  pinch samples recognised: $bp -> $ap"
check "pinch changes the camera distance" "cam_dist" "$b" "$a" changed

# ---- 10. every toggle by finger -----------------------------------------------------
say ""
say "=== 10. TOUCH: every observation toggle, by finger, no gamepad ==="
snap; b="$(field disp)"; tap_n 0.32 0.78 1.5; snap; a="$(field disp)"
check "tap DISP+ changes displacement" "disp" "$b" "$a" changed
b="$(field relief)"; tap_n 0.61 0.78 1.5; snap; a="$(field relief)"
check "tap REL+ changes the relief slider" "relief" "$b" "$a" changed
b="$(field spin)"; tap_n 0.90 0.78 1.5; snap; a="$(field spin)"
check "tap SPIN+ rotates the MESH (camera+light together)" "spin" "$b" "$a" changed
b="$(field tod)"; tap_n 0.18 0.92 1.5; snap; a="$(field tod)"
check "tap TOD+ changes the time of day" "tod" "$b" "$a" changed
b="$(field tod)"; tap_n 0.47 0.92 1.5; snap; a="$(field tod)"
check "tap NIGHT jumps the time of day" "tod" "$b" "$a" changed
b="$(field checker)"; tap_n 0.04 0.78 6.0; snap; a="$(field checker)"
check "tap CHECKER swaps texture<->checker" "checker" "$b" "$a" changed

# ---- 11. leave by finger -------------------------------------------------------------
say ""
say "=== 11. TOUCH: leave the browser with a finger ==="
snap; b_mode="$(field mode)"
tap_n 0.76 0.92 1.5; snap; a_mode="$(field mode)"     # LIST
check "tap LIST returns to the mesh list" "mode" "$b_mode" "$a_mode" changed

# ---- 12. the raw channel counters ----------------------------------------------------
say ""
say "=== 12. RAW CHANNEL (the Java -> JNI -> GOAL chain actually fired) ==="
snap
printf '%s\n' "$STATE" | tee -a "$LOG"
CNT="$(printf '%s\n' "$STATE" | grep -oE 'touch_events=[0-9]+ taps=[0-9]+ drags=[0-9]+ pinches=[0-9]+ flings=[0-9]+')"
say "counters: $CNT"
adb logcat -d -v brief 2>/dev/null | grep -a 'overlay-browser:' | tail -8 | tee -a "$LOG"
adb logcat -d -v brief 2>/dev/null | grep -a -c 'overlay-browser:' \
  | sed 's/^/overlay-browser marker lines in logcat: /' | tee -a "$LOG"

# ---- 13. no-crash ---------------------------------------------------------------------
say ""
say "=== 13. STILL ALIVE ==="
say "focus: $(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
adb shell dumpsys activity exit-info $PKG 2>/dev/null | grep -iE 'reason|signal' | tail -6 | tee -a "$LOG"

say ""
say "================ RESULT: $PASS passed, $FAIL failed ================"
[ "$FAIL" = 0 ]
