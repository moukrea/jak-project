#!/usr/bin/env bash
# =====================================================================================
# Grecharged-mesh-browser V2 — FREECAM/RETICLE PROOF (owner redesign 2026-07-30)
#
# Owner: "un bouton (genre L3 ou R3...) qui nous passe en freecam ... R1/R2 pour target
# un modèle ... L1/L2 toggle montrer/cacher ... damier via Square ... Circle gizmos de
# normales ... defocus via triangle". Plus: the two toggles in the previous build were
# DEAD ("marche pas du tout") — each must now prove BOTH directions (on -> off -> on)
# through RUNTIME state, not a menu animation.
#
# Method (same rules as gmb_touch_proof.sh): every action is INJECTED (cpad_inject for
# pad buttons/sticks — the harness the supervisor names — and `input tap/swipe` for the
# overlay), and after each injection the browser's own observable state is read back
# from files/mesh_browser_state.txt. The hide/checker/gizmo proofs use the RENDER-THREAD
# counters (rt_hidden / rt_checker / rt_gizmo_draws / rt_gizmo_faces): monotonic values
# bumped in the actual TFRAG/TIE draw loops — they GROW while a toggle is live and STOP
# when it is off. A menu that animates without touching the renderer cannot move them.
# No screenshot is used; no visual judgement is made (standing owner rule).
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${S:-eae4df44}"
PKG=org.opengoal.gk.jak1
IDX=custom_assets/jak1/mesh_index/mesh_index_village1.txt
OUT=.autoport/reports/Grecharged-mesh-browser/freecam-proof
mkdir -p "$OUT"
LOG="$OUT/proof-log.txt"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }

adb(){ "$ADB" -s "$S" "$@"; }
INJECT="/data/data/$PKG/files/cpad_inject"
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
padb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
# held stick injection: hold the token string for DUR seconds, then release
hold(){ inject "$1"; sleep "$2"; inject ""; sleep 0.8; }

EXT_ROOT="$(adb exec-out run-as $PKG cat files/asset_root.txt 2>/dev/null | tr -d '\r\n')"
STATE=""
snap(){
  STATE="$(adb exec-out run-as $PKG sh -c 'cat files/mesh_browser_state.txt 2>/dev/null')"
  case "$STATE" in *"No such file"*) STATE="";; esac
  if [ -z "$STATE" ] && [ -n "$EXT_ROOT" ]; then
    STATE="$(adb shell "cat '$EXT_ROOT/mesh_browser_state.txt' 2>/dev/null" | tr -d '\r')"
    case "$STATE" in *"No such file"*) STATE="";; esac
  fi
}
rm_state(){
  adb shell run-as $PKG rm -f files/mesh_browser_state.txt >/dev/null 2>&1 || true
  [ -n "$EXT_ROOT" ] && adb shell rm -f "$EXT_ROOT/mesh_browser_state.txt" >/dev/null 2>&1
  true
}
field(){ printf '%s\n' "$STATE" | grep -oE "(^| )$1=[^ ]*" | tail -1 | cut -d= -f2-; }

PASS=0; FAIL=0
check(){ # label field before after mode [expected]
  local label="$1" f="$2" b="$3" a="$4" mode="$5" exp="${6:-}"
  local ok=0
  case "$mode" in
    changed) [ -n "$a" ] && [ "$b" != "$a" ] && ok=1 ;;
    equals)  [ "$a" = "$exp" ] && ok=1 ;;
    grew)    [ -n "$a" ] && [ -n "$b" ] && awk "BEGIN{exit !($a > $b)}" && ok=1 ;;
    same)    [ -n "$a" ] && [ -n "$b" ] && awk "BEGIN{exit !($a == $b)}" && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then PASS=$((PASS+1)); say "  PASS  $label : $f  $b -> $a"
  else FAIL=$((FAIL+1)); say "  FAIL  $label : $f  $b -> $a  (expected $mode ${exp:-})"; fi
}
assert(){
  if awk "BEGIN{exit !($2)}"; then PASS=$((PASS+1)); say "  PASS  $1  [$3]"
  else FAIL=$((FAIL+1)); say "  FAIL  $1  [$3]"; fi
}
# sample an rt_* counter twice, WIN seconds apart (heartbeat writes every 3 s)
delta(){ # field win -> prints "b a"
  snap; local b="$(field $1)"; sleep "$2"; snap; local a="$(field $1)"; echo "$b $a"
}

say "=== 0. DEVICE ==="
adb devices -l | tee -a "$LOG" | grep -q "$S" || { say "device $S absent"; exit 1; }
say "model: $(adb shell getprop ro.product.model | tr -d '\r')"
say "focus: $(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
CUR="$(adb shell dumpsys window displays 2>/dev/null | grep -oE 'cur=[0-9]+x[0-9]+' | head -1 | cut -d= -f2)"
[ -n "$CUR" ] || CUR="$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
VW="${CUR%x*}"; VH="${CUR#*x}"
say "injection coordinate space: ${VW}x${VH}"
px(){ awk "BEGIN{printf \"%d\", $1*$VW}"; }
py(){ awk "BEGIN{printf \"%d\", $1*$VH}"; }
tap_n(){ adb shell input tap "$(px $1)" "$(py $2)"; sleep "${3:-0.8}"; }
swipe_n(){ adb shell input swipe "$(px $1)" "$(py $2)" "$(px $3)" "$(py $4)" "${5:-500}"; sleep "${6:-0.8}"; }

# ---- 1. open the browser (menu walk, as in gmb_touch_proof.sh) ------------------------
say ""
say "=== 1. OPEN THE BROWSER (menu nav; everything under test comes after) ==="
app_restart(){
  adb shell am force-stop $PKG
  adb logcat -c >/dev/null 2>&1 || true
  adb shell am start -W -n $PKG/.LoaderActivity >/dev/null 2>&1
  local t=0
  until adb logcat -d 2>/dev/null | grep -aq 'master-mode=progress\|A36-TFRAG-CAM-HB lvl='; do
    sleep 15; t=$((t+15)); [ "$t" -ge 600 ] && { say "app_restart: no title after ${t}s"; return 1; }
  done
  sleep 20
}
opened=0
for D in 7 8; do
for K in 21 22 20 23 19; do
  app_restart || continue
  rm_state
  inject "start"; sleep 1.5; inject ""; sleep 2.0
  padb "down" 0.7; padb "down" 0.7; padb "x" 2.0
  padb "down" 0.8; padb "x" 2.0
  for i in $(seq 1 "$D"); do padb "down" 0.5; done
  padb "x" 1.8
  for i in $(seq 1 "$K"); do padb "down" 0.35; done
  padb "x" 2.5
  snap
  if [ "$(field mode)" = "LEVELS" ]; then
    say "browser OPEN after D=$D + K=$K; mode=$(field mode)"; opened=1; break
  fi
  say "  (D=$D K=$K: mode='$(field mode)'; retry)"
done
[ "$opened" = 1 ] && break
done
[ "$opened" = 1 ] || { say "COULD NOT OPEN THE BROWSER — abort"; exit 1; }
GOOD_D="$D"; GOOD_K="$K"   # remember the working walk for reopens

# Reopen the browser LEVELS screen from CLOSED (post-freecam-exit). The browser's menu
# confirm handler left master-mode 'game, so START pulls the progress menu back up at its
# root and the section-1 walk applies verbatim (minus the press-start dismissal).
reopen_browser(){
  rm_state
  inject "start"; sleep 1.5; inject ""; sleep 2.0
  padb "down" 0.7; padb "down" 0.7; padb "x" 2.0
  padb "down" 0.8; padb "x" 2.0
  for i in $(seq 1 "$GOOD_D"); do padb "down" 0.5; done
  padb "x" 1.8
  for i in $(seq 1 "$GOOD_K"); do padb "down" 0.35; done
  padb "x" 2.5
  snap
  [ "$(field mode)" = "LEVELS" ]
}
# Bring the session to the village1 mesh LIST from wherever it is.
ensure_list(){
  snap
  case "$(field mode)" in
    FREECAM) padb "r3" 2.0; snap ;;
  esac
  case "$(field mode)" in
    LIST) return 0 ;;
    OBSERVE) tap_n 0.76 0.92 2.0; snap; [ "$(field mode)" = "LIST" ] && return 0 ;;
    LEVELS) tap_n 0.30 0.20 4.0; snap; [ "$(field mode)" = "LIST" ] && return 0 ;;
  esac
  # closed or lost: reopen through the menu, then pick village1
  reopen_browser || return 1
  tap_n 0.30 0.20 4.0; snap
  [ "$(field mode)" = "LIST" ]
}

# ---- 2. R3 -> FREECAM (pad entry) -----------------------------------------------------
say ""
say "=== 2. GAMEPAD: injected r3 enters FREECAM from the browser ==="
b_mode="$(field mode)"
padb "r3" 2.0; snap; a_mode="$(field mode)"
check "cpad_inject r3 -> FREECAM (first-person reticle mode)" "mode" "$b_mode" "$a_mode" equals "FREECAM"
say "--- freecam state ---"; printf '%s\n' "$STATE" | tee -a "$LOG"

# ---- 3. FLIGHT: left stick moves in all directions incl. air --------------------------
say ""
say "=== 3. GAMEPAD: left stick FLIES the camera (all directions incl. vertical) ==="
snap; b_fc="$(field fc)"; b_yaw="$(field yaw)"
hold "ly=0" 1.2            # stick full up = fly forward along the look vector
snap; a_fc="$(field fc)"
check "stick forward moves the camera" "fc" "$b_fc" "$a_fc" changed
# vertical: pitch up with the right stick, then fly forward -> altitude (fc y) must rise
hold "ry=0" 0.9            # look up
snap; m_yaw="$(field yaw)"; m_pitch="$(field pitch)"; m_y="$(echo "$a_fc" | cut -d, -f2)"
hold "ly=0" 1.2
snap; v_fc="$(field fc)"; v_y="$(echo "$v_fc" | cut -d, -f2)"
check "pitched-up flight gains ALTITUDE (fly in the air)" "fc.y" "$m_y" "$v_y" grew
b_yaw2="$(field yaw)"
hold "rx=255" 0.8          # right stick right = turn
snap; a_yaw2="$(field yaw)"
check "right stick turns the camera (yaw)" "yaw" "$b_yaw2" "$a_yaw2" changed
say "pitch after look-up: $m_pitch (from $(field pitch) now)"

# ---- 4. exit freecam, reopen the LIST path for deterministic aiming -------------------
# Aiming the reticle by rate-based stick injection is not deterministic over adb timing.
# The deterministic aim is the one the design gives us: LIST -> OBSERVE centres the camera
# on the mesh CENTROID (proven 5/5 in the previous round), and R3 from OBSERVE enters
# freecam CONTINUING that camera — reticle dead-centre on the mesh. Then TRIANGLE clears
# the pre-target (defocus proof) and R1 must RE-ACQUIRE the same mesh through the actual
# camera-ray-vs-index-AABB pick. 5 meshes, very different centroids (roof / bench /
# barrel top / hut wall / beach rock), same rows as the previous round's centroid proof.
say ""
say "=== 4. RETICLE PICK ACCURACY on 5 distinct meshes (+ TRIANGLE defocus each time) ==="
PICKOK=0; NPICK=0
LASTMESH=""
for FRAC in 0.03 0.28 0.50 0.72 0.96; do
  NPICK=$((NPICK+1))
  ensure_list || { say "  FAIL mesh #$NPICK: could not reach the LIST"; FAIL=$((FAIL+1)); continue; }
  # jump the fast-scroll handle to this fraction, tap a row twice -> OBSERVE
  swipe_n 0.97 0.20 0.97 "$(awk "BEGIN{printf \"%.4f\", 0.20 + $FRAC*0.68}")" 800 1.5
  tap_n 0.40 0.45 1.5
  tap_n 0.40 0.45 7.0
  snap
  [ "$(field mode)" = "OBSERVE" ] || { say "  FAIL mesh #$NPICK: no OBSERVE (mode=$(field mode))"; FAIL=$((FAIL+1)); continue; }
  ROW="$(field row)"; MAT="$(field material)"
  padb "r3" 2.0; snap
  [ "$(field mode)" = "FREECAM" ] || { say "  FAIL mesh #$NPICK: r3 from OBSERVE did not enter FREECAM"; FAIL=$((FAIL+1)); continue; }
  # TRIANGLE defocus: the pre-target carried over from OBSERVE must clear
  padb "triangle" 1.5; snap
  check "mesh #$NPICK TRIANGLE defocuses (target cleared)" "target" "$ROW" "$(field target)" equals "-1"
  # R1: ray pick through the reticle must re-acquire THIS mesh. The camera continued from
  # OBSERVE, so the reticle sits dead-centre on this mesh's centroid; cycling is tolerated
  # (several AABBs can legally sit on the same ray; R1 walks them near->far).
  hit=""
  for c in 1 2 3 4 5 6 7 8; do
    padb "r1" 1.2; snap
    [ "$(field target)" = "$ROW" ] && { hit="$c"; break; }
    [ "$(field pick_n)" = "0" ] && break
  done
  if [ -n "$hit" ]; then
    PASS=$((PASS+1)); PICKOK=$((PICKOK+1))
    say "  PASS  mesh #$NPICK reticle pick acquired row=$ROW ($MAT) after $hit R1 press(es), pick_n=$(field pick_n)"
    LASTMESH="$ROW"
  else
    FAIL=$((FAIL+1))
    say "  FAIL  mesh #$NPICK reticle pick never acquired row=$ROW ($MAT); target=$(field target) pick_n=$(field pick_n)"
  fi
  # stay in FREECAM after the LAST mesh: sections 5-7 run the toggle battery on it
done
say "reticle pick acquired on $PICKOK/5 meshes"
[ "$PICKOK" -ge 5 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); say "  FAIL  pick accuracy below 5/5"; }

# ---- 5. THE TWO PREVIOUSLY-DEAD TOGGLES: on -> off -> on via RENDER counters ----------
say ""
say "=== 5. L1/L2 HIDE + SQUARE CHECKER: both directions, runtime draw counters ==="
say "rt_hidden / rt_checker are bumped INSIDE the TFRAG/TIE draw loops (render thread)."
say "They grow while the toggle is live and freeze when it is off — a dead toggle (the"
say "owner's exact complaint) cannot move them."
snap
[ "$(field target)" != "-1" ] && [ -n "$(field target)" ] || { padb "r1" 1.5; snap; }
say "target for the toggle battery: target=$(field target) $(field material)"
b_h="$(field hide)"
# HIDE: on
padb "l1" 1.0; snap
check "L1 sets hide" "hide" "$b_h" "$(field hide)" equals "1"
read hb ha <<< "$(delta rt_hidden 4.5)"
check "hide ON: hidden-draw counter GROWS (draws really skipped)" "rt_hidden" "$hb" "$ha" grew
# HIDE: off (L2 = show, the explicit other direction)
padb "l2" 1.0; snap
check "L2 clears hide (mesh shown again)" "hide" "1" "$(field hide)" equals "0"
read hb2 ha2 <<< "$(delta rt_hidden 4.5)"
check "hide OFF: hidden-draw counter FREEZES" "rt_hidden" "$hb2" "$ha2" same
# HIDE: on again (the full on -> off -> on the supervisor demands)
padb "l1" 1.0; snap
read hb3 ha3 <<< "$(delta rt_hidden 4.5)"
check "hide ON again: counter grows again (on->off->on)" "rt_hidden" "$hb3" "$ha3" grew
padb "l2" 1.0   # leave shown
# CHECKER: on -> off -> on
padb "square" 1.0; snap
check "SQUARE sets the per-mesh checker" "checker2" "0" "$(field checker2)" equals "1"
read cb ca <<< "$(delta rt_checker 4.5)"
check "checker ON: checker-draw counter GROWS (real material override)" "rt_checker" "$cb" "$ca" grew
padb "square" 1.0; snap
check "SQUARE clears the checker" "checker2" "1" "$(field checker2)" equals "0"
read cb2 ca2 <<< "$(delta rt_checker 4.5)"
check "checker OFF: counter FREEZES" "rt_checker" "$cb2" "$ca2" same
padb "square" 1.0; snap
read cb3 ca3 <<< "$(delta rt_checker 4.5)"
check "checker ON again: grows again (on->off->on)" "rt_checker" "$cb3" "$ca3" grew
padb "square" 1.0   # leave real texture

# ---- 6. CIRCLE: normal gizmos --------------------------------------------------------
say ""
say "=== 6. CIRCLE: normal-orientation gizmos on the target ==="
padb "circle" 1.5; snap
check "CIRCLE sets gizmos" "gizmos" "0" "$(field gizmos)" equals "1"
GF="$(field rt_gizmo_faces)"
say "gizmo faces built for this mesh: $GF"
assert "gizmo builder produced faces (>0)" "($GF) > 0" "rt_gizmo_faces=$GF"
read gb ga <<< "$(delta rt_gizmo_draws 4.5)"
check "gizmo pass renders every frame while ON" "rt_gizmo_draws" "$gb" "$ga" grew
padb "circle" 1.0; snap
check "CIRCLE clears gizmos" "gizmos" "1" "$(field gizmos)" equals "0"
read gb2 ga2 <<< "$(delta rt_gizmo_draws 4.5)"
check "gizmos OFF: pass counter freezes" "rt_gizmo_draws" "$gb2" "$ga2" same

# ---- 7. TRIANGLE defocus makes the toggles inert --------------------------------------
say ""
say "=== 7. TRIANGLE: defocus (toggles become inert) ==="
padb "l1" 1.0             # hide the target...
padb "triangle" 1.0; snap  # ...then defocus: C++ clears the flags with the target
check "defocus clears the target" "target" "x" "$(field target)" equals "-1"
check "defocus resets hide (no orphaned hidden mesh)" "hide" "1" "$(field hide)" equals "0"
read db da <<< "$(delta rt_hidden 4.5)"
check "after defocus nothing is hidden (counter frozen)" "rt_hidden" "$db" "$da" same

# ---- 8. R3 exits; R3 from CLOSED re-enters (gameplay-side entry) -----------------------
say ""
say "=== 8. R3 exit + R3 entry from CLOSED (the owner's L3/R3 gameplay entry) ==="
padb "r3" 2.0; snap
if [ -z "$STATE" ] || [ "$(field mode)" = "CLOSED" ]; then
  PASS=$((PASS+1)); say "  PASS  r3 exits freecam (mode=CLOSED, world handed back)"
else
  FAIL=$((FAIL+1)); say "  FAIL  r3 did not exit freecam (mode=$(field mode))"
fi
rm_state
padb "r3" 2.5; snap
check "r3 from CLOSED enters freecam directly (no menu needed)" "mode" "" "$(field mode)" equals "FREECAM"

# ---- 9. TOUCH: overlay drives the freecam (owner has no gamepad) -----------------------
say ""
say "=== 9. TOUCH: overlay buttons drive every freecam action (injected input tap) ==="
say "coords come from the overlay's own 'overlay-map:' lines in logcat (drawn = hit)."
adb logcat -d 2>/dev/null | grep -a 'overlay-map: fc' | tail -20 | tee -a "$LOG"
MAP="$(adb logcat -d 2>/dev/null | grep -a 'overlay-map:' | tail -40)"
# centre of a mapped control. Two formats (TouchOverlayView.logOverlayMap):
#   rrect: name=left,top,WIDTH,HEIGHT->...   circ: name=cx,cy,radius->...
ctl(){
  local co
  co="$(printf '%s\n' "$MAP" | grep -aoE "$1=[0-9,-]+" | tail -1 | cut -d= -f2)"
  [ -n "$co" ] || return 0
  local n; n="$(echo "$co" | awk -F, '{print NF}')"
  if [ "$n" = 4 ]; then echo "$co" | awk -F, '{printf "%d %d", $1+$3/2, $2+$4/2}'
  else echo "$co" | awk -F, '{printf "%d %d", $1, $2}'; fi
}
tap_ctl(){ local c; c="$(ctl $1)"; [ -n "$c" ] && { adb shell input tap $c; sleep "${2:-1.2}"; return 0; }; say "  (no overlay-map for $1)"; return 1; }
# 9a. R1 by finger -> target. The re-entry camera continues from wherever the title
# flythrough left it, which may point at empty sky: sweep the look a few times until the
# ray finds candidates (each attempt is a REAL finger tap; the sweep is aiming, not a
# loosened check).
snap; b_t="$(field target)"
if tap_ctl fc-r1 1.5; then
  snap
  for sweep in 1 2 3 4; do
    [ -n "$(field target)" ] && [ "$(field target)" != "-1" ] && break
    swipe_n 0.62 0.45 0.55 0.55 400 1.0     # look around a bit (camera region, off the fc buttons)
    tap_ctl fc-r1 1.5; snap
  done
  check "TOUCH R1 button picks a target" "target" "$b_t" "$(field target)" changed
fi
# 9b. L1 by finger -> hide, counter grows; L2 by finger -> shown
if tap_ctl fc-l1 1.0; then snap; check "TOUCH L1 button hides" "hide" "0" "$(field hide)" equals "1"
  read tb ta <<< "$(delta rt_hidden 4.5)"
  check "TOUCH hide is live in the renderer" "rt_hidden" "$tb" "$ta" grew
  tap_ctl fc-l2 1.0; snap; check "TOUCH L2 button shows again" "hide" "1" "$(field hide)" equals "0"; fi
# 9c. Square / Circle / Triangle by finger
if tap_ctl fc-square 1.0; then snap; check "TOUCH SQUARE toggles checker" "checker2" "0" "$(field checker2)" equals "1"; tap_ctl fc-square 1.0; fi
if tap_ctl fc-circle 1.0; then snap; check "TOUCH CIRCLE toggles gizmos" "gizmos" "0" "$(field gizmos)" equals "1"; tap_ctl fc-circle 1.0; fi
if tap_ctl fc-triangle 1.0; then snap; check "TOUCH TRIANGLE defocuses" "target" "x" "$(field target)" equals "-1"; fi
# 9d. look by dragging the camera area (floating right stick anchors at touch-down,
# deflection sustained while held: a slow swipe = a held deflection); fly via the
# virtual left stick the same way
snap; b_yaw="$(field yaw)"
swipe_n 0.62 0.45 0.52 0.45 1200 1.2
snap; check "TOUCH camera-area drag turns the camera" "yaw" "$b_yaw" "$(field yaw)" changed
b_fc="$(field fc)"
STK="$(ctl left-stick)"
if [ -n "$STK" ]; then
  SX="${STK% *}"; SY="${STK#* }"
  adb shell input swipe "$SX" "$SY" "$SX" "$((SY-140))" 1400   # hold the stick up ~1.4s
  sleep 1.0; snap
  check "TOUCH virtual stick flies the camera" "fc" "$b_fc" "$(field fc)" changed
fi
# 9e. EXIT by finger, FCAM button by finger to re-enter
if tap_ctl fc-exit 2.0; then snap
  if [ -z "$STATE" ] || [ "$(field mode)" = "CLOSED" ]; then PASS=$((PASS+1)); say "  PASS  TOUCH EXIT closes freecam"
  else FAIL=$((FAIL+1)); say "  FAIL  TOUCH EXIT: mode=$(field mode)"; fi
fi
rm_state
if tap_ctl fcam 2.5; then snap; check "TOUCH FCAM overlay button enters freecam from gameplay" "mode" "" "$(field mode)" equals "FREECAM"
  padb "r3" 1.5
fi

# ---- 10. alive ------------------------------------------------------------------------
say ""
say "=== 10. STILL ALIVE ==="
say "focus: $(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
adb shell dumpsys activity exit-info $PKG 2>/dev/null | grep -iE 'reason|signal' | tail -6 | tee -a "$LOG"

say ""
say "================ RESULT: $PASS passed, $FAIL failed ================"
[ "$FAIL" = 0 ]
