#!/usr/bin/env bash
# =====================================================================================
# Grecharged-mesh-browser — INJECTED-GESTURE PROOF + FREE-CAMERA / CENTROID PROOF
#
# Two owner corrections, both proven here on the real device, both falsifiable.
#
# (1) 2026-07-29: "C'est impossible a parcourir via le tactile (le mesh browser)".
#     The previous gate accepted the WORD "touch" in a report, which proves nothing.
#     Every gesture below is injected with `input tap` / `input swipe` (and, for the
#     two-finger pinch, monkey's pinch-zoom generator, because `input` is single-pointer
#     and `sendevent` on the touchscreen node is SELinux-denied to shell here). Those go
#     through the ordinary Android input pipeline into TouchOverlayView.onTouchEvent,
#     exactly like the owner's finger. After each gesture the browser's OWN observable
#     state is read back from files/mesh_browser_state.txt via run-as. A test passes only
#     if the state MOVED in the expected field. No screenshot is used and no visual
#     judgement is made: the agent is not allowed to judge the visual, and a screenshot
#     could not prove causation anyway.
#
# (2) 2026-07-29: "le warp to model warp toujours au meme endroit, et warp le joueur...
#     je voulais pouvoir tourner en free cam autour dudit mesh (origine au centre du
#     modele)". Section 12 opens FIVE meshes with very different centroids and checks,
#     for each, that the CAMERA landed on that mesh's centroid (compared against the
#     shipped index file, not against our own intention) and that the PLAYER did not
#     move at all. A fixed point would show up as five identical cam= values.
#
# Gamepad is used for ONE thing only: walking the option menu to reach the browser
# (that row is pre-existing and the owner already reaches it). Everything under test
# after that point is touch.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${S:-eae4df44}"
PKG=org.opengoal.gk.jak1
IDX=custom_assets/jak1/mesh_index/mesh_index_village1.txt
OUT=.autoport/reports/Grecharged-mesh-browser/touch-proof
mkdir -p "$OUT"
LOG="$OUT/proof-log.txt"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }

adb(){ "$ADB" -s "$S" "$@"; }
INJECT="/data/data/$PKG/files/cpad_inject"
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
padb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }

# ---- state readback ------------------------------------------------------------------
# The state file lands at file_util::get_jak_project_dir()/mesh_browser_state.txt. In INTERNAL
# asset-root mode that is files/; in EXTERNAL mode (files/asset_root.txt present, e.g.
# /storage/emulated/0/OpenGOAL/jak1) it is that external root. Read both; take whichever answers.
# (memory: run-as output must be judged by CONTENT, its exit code lies for missing files.)
EXT_ROOT="$(adb exec-out run-as $PKG cat files/asset_root.txt 2>/dev/null | tr -d '\r\n')"
STATE=""
snap(){
  STATE="$(adb exec-out run-as $PKG cat files/mesh_browser_state.txt 2>/dev/null)"
  if [ -z "$STATE" ] && [ -n "$EXT_ROOT" ]; then
    STATE="$(adb shell cat "$EXT_ROOT/mesh_browser_state.txt" 2>/dev/null | tr -d '\r')"
  fi
}
rm_state(){
  adb shell run-as $PKG rm -f files/mesh_browser_state.txt >/dev/null 2>&1 || true
  [ -n "$EXT_ROOT" ] && adb shell rm -f "$EXT_ROOT/mesh_browser_state.txt" >/dev/null 2>&1
  true
}
# field <name> -> value ("" if absent). Read from the last snap().
field(){ printf '%s\n' "$STATE" | grep -oE "(^| )$1=[^ ]*" | tail -1 | cut -d= -f2-; }

PASS=0; FAIL=0
# check <label> <field> <before> <after> <mode:changed|equals|grew> [expected]
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
# assert <label> <condition-as-awk-expr> <detail>
assert(){
  if awk "BEGIN{exit !($2)}"; then PASS=$((PASS+1)); say "  PASS  $1  [$3]"
  else FAIL=$((FAIL+1)); say "  FAIL  $1  [$3]"; fi
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
rm_state
opened=0
# D = downs from GRAPHIC OPTIONS to the RECHARGED SETTINGS row: 7 when Min Target FPS is hidden
# (Dynamic Render Scale OFF), 8 when visible — the device's persisted setting decides, probe both.
# K = downs inside Recharged Settings to the MESH BROWSER row (23 with all rows present).
for D in 7 8; do
for K in 23 22 24 21 25 20 26; do
  padb "start" 2.5
  padb "down" 0.7; padb "down" 0.7; padb "x" 2.0      # OPTIONS
  padb "down" 0.8; padb "x" 2.0                        # GRAPHIC OPTIONS
  for i in $(seq 1 "$D"); do padb "down" 0.5; done     # RECHARGED SETTINGS row
  padb "x" 1.8
  for i in $(seq 1 "$K"); do padb "down" 0.35; done    # walk to MESH BROWSER
  padb "x" 2.5
  snap
  if [ -n "$STATE" ]; then say "browser OPEN after D=$D downs + K=$K downs; mode=$(field mode)"; opened=1; break; fi
  say "  (D=$D K=$K did not open it; backing out)"
  padb "triangle" 0.8; padb "triangle" 0.8; padb "triangle" 0.8; padb "start" 1.2
done
[ "$opened" = 1 ] && break
done
[ "$opened" = 1 ] || { say "COULD NOT OPEN THE BROWSER — abort"; exit 1; }
say "--- initial state ---"; printf '%s\n' "$STATE" | tee -a "$LOG"

# ---- 2. LEVEL PICKER: tap a level row directly ---------------------------------------
say ""
say "=== 2. TOUCH: tap a level row (direct selection, no cursor) ==="
b_mode="$(field mode)"
tap_n 0.30 0.20 4.0     # first level row band = village1
snap; a_mode="$(field mode)"
check "tap level row -> enters the mesh LIST" "mode" "$b_mode" "$a_mode" changed
say "--- state ---"; printf '%s\n' "$STATE" | tee -a "$LOG"
NTOT="$(field n_filtered)"
say "list holds n_filtered=$NTOT rows (thousands of entries: village1's index is 9508 meshes —"
say "stepping that one row at a time is unusable by construction, which is what the owner hit)"

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
tap_n 0.40 0.45 1.5; snap; a="$(field sel)"; amat="$(field material)"
check "tap a row selects THAT row" "sel" "$b" "$a" changed
say "  material: $bmat -> $amat"
b_mode="$(field mode)"
tap_n 0.40 0.45 6.0      # second tap on the selected row = free cam + OBSERVE
snap; a_mode="$(field mode)"
check "second tap opens the mesh (free camera -> OBSERVE)" "mode" "$b_mode" "$a_mode" equals "OBSERVE"
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
say "  note: 'input' is single-pointer and sendevent on the touchscreen node is SELinux-denied"
say "  to shell on this device, so the two-finger gesture is injected with monkey's"
say "  pinch-zoom generator, which emits real 2-pointer MotionEvents into this package."
snap; b="$(field cam_dist)"; bp="$(printf '%s\n' "$STATE" | grep -oE 'pinches=[0-9]+' | cut -d= -f2)"
adb shell monkey -p $PKG --pct-pinchzoom 100 --pct-touch 0 --pct-motion 0 --pct-trackball 0 \
    --pct-nav 0 --pct-majornav 0 --pct-syskeys 0 --pct-appswitch 0 --pct-flip 0 \
    --pct-anyevent 0 --pct-permission 0 --throttle 120 -v 40 >>"$LOG" 2>&1
sleep 2.0; snap; a="$(field cam_dist)"; ap="$(printf '%s\n' "$STATE" | grep -oE 'pinches=[0-9]+' | cut -d= -f2)"
say "  pinch samples recognised: $bp -> $ap"
check "pinch changes the camera distance" "cam_dist" "$b" "$a" changed
# monkey's pinches are random-positioned; a sub-500ms one can register as a stray TAP and press a
# button (worst case LIST/EXIT). Recover the OBSERVE mode before the button tests if that happened.
if [ "$(field mode)" != "OBSERVE" ]; then
  say "  (stray monkey tap left mode=$(field mode); recovering OBSERVE)"
  tap_n 0.40 0.45 1.5; tap_n 0.40 0.45 6.0; snap
  say "  recovered mode=$(field mode)"
fi

# ---- 10. every toggle by finger -----------------------------------------------------
say ""
say "=== 10. TOUCH: every observation toggle, by finger, no gamepad ==="
snap; b="$(field disp)"; tap_n 0.32 0.78 1.5; snap; a="$(field disp)"
check "tap DISP+ changes displacement" "disp" "$b" "$a" changed
b="$(field relief)"; tap_n 0.61 0.78 1.5; snap; a="$(field relief)"
if [ "$a" = "$b" ]; then
  # relief is a CLAMPED slider (0..3); if the device sat at the max, REL+ is a legitimate no-op —
  # prove the finger drives it with REL- instead.
  say "  (relief already at a bound: REL+ no-op at $b; proving with REL-)"
  tap_n 0.50 0.78 1.5; snap; a="$(field relief)"
fi
check "tap REL+/REL- changes the relief slider" "relief" "$b" "$a" changed
b="$(field spin)"; tap_n 0.90 0.78 1.5; snap; a="$(field spin)"
check "tap SPIN+ rotates the MESH (camera+light together)" "spin" "$b" "$a" changed
b="$(field tod)"; tap_n 0.18 0.92 1.5; snap; a="$(field tod)"
check "tap TOD+ changes the time of day" "tod" "$b" "$a" changed
b="$(field tod)"; tap_n 0.47 0.92 1.5; snap; a="$(field tod)"
check "tap NIGHT jumps the time of day" "tod" "$b" "$a" changed
b="$(field checker)"; tap_n 0.04 0.78 8.0; snap; a="$(field checker)"
check "tap CHECKER swaps texture<->checker" "checker" "$b" "$a" changed
# leave the checker OFF again so section 12 observes the real textures
tap_n 0.04 0.78 8.0; snap
say "  checker back to $(field checker)"

# ---- 11. leave OBSERVE by finger ----------------------------------------------------
say ""
say "=== 11. TOUCH: leave the 3D view with a finger ==="
snap; b_mode="$(field mode)"
tap_n 0.76 0.92 2.0; snap; a_mode="$(field mode)"     # LIST
check "tap LIST returns to the mesh list" "mode" "$b_mode" "$a_mode" changed

# ---- 12. FREE CAMERA: 5 meshes, 5 different centroids, player untouched --------------
say ""
say "=== 12. FREE CAMERA / CENTROID ACCURACY (owner: 'warp toujours au meme endroit') ==="
say "For five meshes at very different places in village1, reached BY FINGER: does the camera"
say "actually centre on THAT mesh's centroid, and does the player stay put? The expected"
say "centroid is read from the shipped index file, not from what the browser told us."
say ""
HOME_XYZ=""; PREV_CAM=""; NCENT=0
CENT_LOG="$OUT/centroids.txt"; : > "$CENT_LOG"
for FRAC in 0.03 0.28 0.50 0.72 0.96; do
  # jump the fast-scroll handle to this fraction of the list, then tap a row twice
  HY=$(awk "BEGIN{printf \"%.4f\", 0.20 + $FRAC*0.68}")
  swipe_n 0.97 0.20 0.97 "$HY" 800 1.5
  tap_n 0.40 0.45 1.5           # select
  tap_n 0.40 0.45 7.0           # open -> free camera + OBSERVE
  snap
  MODE="$(field mode)"; ROW="$(field row)"; MAT="$(field material)"
  FOC="$(field focus)"; CAM="$(field cam)"; CR="$(field cam_r)"; CD="$(field cam_dist)"
  PLR="$(field player)"; PMV="$(field player_moved)"; LVS="$(field lvl_status)"
  say "--- mesh #$((NCENT+1)): row=$ROW material=$MAT mode=$MODE lvl_status=$LVS"
  say "    index centroid (expected) : $(awk -v r="$ROW" 'NR==r+2{printf "%s,%s,%s", $8,$9,$10}' "$IDX")"
  say "    browser focus (centroid)  : $FOC"
  say "    camera world position     : $CAM"
  say "    |cam-centroid|=$CR   orbit radius cam_dist=$CD"
  say "    player=$PLR  player_moved=$PMV m"
  echo "$ROW $MAT $FOC $CAM $CR $CD $PMV" >> "$CENT_LOG"
  if [ "$MODE" = "OBSERVE" ] && [ -n "$FOC" ] && [ -n "$ROW" ]; then
    EXP="$(awk -v r="$ROW" 'NR==r+2{printf "%s,%s,%s", $8,$9,$10}' "$IDX")"
    # the browser's orbit origin must BE the index's centroid for this row
    ex=${EXP%%,*}; er=${EXP#*,}; ey=${er%%,*}; ez=${er##*,}
    fx=${FOC%%,*}; fr=${FOC#*,}; fy=${fr%%,*}; fz=${fr##*,}
    assert "mesh #$((NCENT+1)) orbit origin == the INDEX centroid of row $ROW" \
      "($fx-$ex)^2+($fy-$ey)^2+($fz-$ez)^2 < 0.01" "index=$EXP browser=$FOC"
    # the camera must sit on the orbit sphere around THAT centroid
    assert "mesh #$((NCENT+1)) camera is centred on that centroid" \
      "($CR-$CD)^2 < 4.0" "|cam-centroid|=$CR vs radius=$CD (metres)"
    # and the player must not have moved a millimetre
    assert "mesh #$((NCENT+1)) player did NOT move" "$PMV < 0.001" "player_moved=$PMV m"
    # distinct camera positions: a fixed point would repeat
    if [ -n "$PREV_CAM" ]; then
      pcx=${PREV_CAM%%,*}; pr=${PREV_CAM#*,}; pcy=${pr%%,*}; pcz=${pr##*,}
      cx=${CAM%%,*}; cr2=${CAM#*,}; cy=${cr2%%,*}; cz=${cr2##*,}
      assert "mesh #$((NCENT+1)) camera moved vs the previous mesh (no fixed point)" \
        "($cx-$pcx)^2+($cy-$pcy)^2+($cz-$pcz)^2 > 1.0" "prev=$PREV_CAM now=$CAM"
    fi
    PREV_CAM="$CAM"
    NCENT=$((NCENT+1))
  else
    FAIL=$((FAIL+1)); say "  FAIL  mesh #$((NCENT+1)) did not reach OBSERVE (mode=$MODE)"
  fi
  tap_n 0.76 0.92 2.0    # LIST, by finger
done
say ""
say "meshes checked for camera-vs-centroid accuracy: $NCENT (>=5 required)"
[ "$NCENT" -ge 5 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); say "  FAIL  fewer than 5 meshes checked"; }
# distinct centroids across the five
DISTINCT=$(awk '{print $3}' "$CENT_LOG" | sort -u | wc -l)
say "distinct centroids among them: $DISTINCT"
[ "$DISTINCT" -ge 5 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); say "  FAIL  centroids were not distinct"; }

# ---- 13. leave the browser entirely, by finger --------------------------------------
say ""
say "=== 13. TOUCH: leave the browser with a finger ==="
tap_n 0.40 0.45 1.5; tap_n 0.40 0.45 6.0   # back into OBSERVE so EXIT is on screen
snap; b_mode="$(field mode)"
tap_n 0.93 0.92 2.5                         # EXIT
snap
if [ -z "$STATE" ] || [ "$(field mode)" = "CLOSED" ]; then
  PASS=$((PASS+1)); say "  PASS  tap EXIT closed the browser (mode was $b_mode)"
else
  FAIL=$((FAIL+1)); say "  FAIL  tap EXIT did not close the browser (mode=$(field mode))"
fi

# ---- 14. the raw channel counters ----------------------------------------------------
say ""
say "=== 14. RAW CHANNEL (the Java -> JNI -> GOAL chain actually fired) ==="
CNT="$(printf '%s\n' "$STATE" | grep -oE 'touch_events=[0-9]+ taps=[0-9]+ drags=[0-9]+ pinches=[0-9]+ flings=[0-9]+')"
say "counters: $CNT"
adb logcat -d -v brief 2>/dev/null | grep -a 'overlay-browser:' | tail -8 | tee -a "$LOG"
adb logcat -d -v brief 2>/dev/null | grep -a -c 'overlay-browser:' \
  | sed 's/^/overlay-browser marker lines in logcat: /' | tee -a "$LOG"

# ---- 15. no-crash ---------------------------------------------------------------------
say ""
say "=== 15. STILL ALIVE ==="
say "focus: $(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
adb shell dumpsys activity exit-info $PKG 2>/dev/null | grep -iE 'reason|signal' | tail -6 | tee -a "$LOG"

say ""
say "================ RESULT: $PASS passed, $FAIL failed ================"
[ "$FAIL" = 0 ]
