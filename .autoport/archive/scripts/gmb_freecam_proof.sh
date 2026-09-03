#!/usr/bin/env bash
# =====================================================================================
# Grecharged-mesh-browser V2.1 — FREECAM/RETICLE PROOF (owner reopen 2026-07-30)
#
# V2.1 additions (owner: 4 axes inverted; hide/checker/gizmos/relief ALL dead):
#   * PER-AXIS SIGN proofs, both directions, against the documented FPS convention
#     (run 5's axis checks were sign-blind: 'changed' passes on a mirrored rig);
#   * PER-FRAME renderer counters rtf_target/rtf_checker/rtf_gizmo/rtf_relief — hide is
#     now proven by the target's SUBMITTED draw count hitting ZERO, checker by per-frame
#     material binds, gizmos by line prims drawn, relief by the value at the shader
#     uniform push site (variables that flip while the renderer ignores them cannot pass);
#   * SURFACE-FIRST pick metric (first-press hits) — run 5 needed up to 13 R1 presses to
#     escape the camera-enclosing junk AABBs, which is why the owner's single press always
#     targeted an invisible mesh and every toggle then acted off-screen.
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
# The state file is dumped on SIGNATURE change (>=8 frames apart) or every 180 FRAMES — and the
# monotonic rt_* counters are NOT in the signature. At the tess-crushed beach vantage the Redmi
# runs ~10-15 fps, so the idle heartbeat stretches to 12-18 s: two fixed-seconds samples can read
# the SAME dump and a live counter looks frozen (runs 10/11: "360 -> 360" while the per-frame
# counters were >0). Sample on DUMP BOUNDARIES instead: b from the first dump, a from the NEXT
# DISTINCT dump (content-hashed), waiting up to 36 s for it. No dump at all in 36 s = the a==b
# verdict stands on its own merits.
snap_next(){ # wait (up to 36 s) for a state dump DIFFERENT from the current $STATE, then snap
  local h0 t=0
  h0="$(printf '%s' "$STATE" | md5sum)"
  while [ $t -lt 36 ]; do
    sleep 3; t=$((t+3)); snap
    [ "$(printf '%s' "$STATE" | md5sum)" != "$h0" ] && return 0
  done
  return 1
}
delta(){ # field win(kept for call compat, unused) -> prints "b a" from two DISTINCT dumps
  sleep 2.0   # let the press-triggered signature dump land
  snap; local b="$(field $1)"
  snap_next || true
  local a="$(field $1)"; echo "$b $a"
}
# fresh per-frame counter value: the NEXT dump generated after this call (>= one new heartbeat)
rtf(){ sleep 2.0; snap; snap_next || true; field "$1"; }

say "=== 0. DEVICE ==="
adb devices -l | tee -a "$LOG" | grep -q "$S" || { say "device $S absent"; exit 1; }
adb logcat -G 16M 2>/dev/null || true   # overlay-map layout lines must survive minutes of GK spam
say "model: $(adb shell getprop ro.product.model | tr -d '\r')"
say "focus: $(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
# Injection space is sampled AFTER the game is foreground (see sample_space below): `cur=`
# follows the CURRENT display orientation, and at script start the foreground app can be the
# MIUI launcher (portrait 1080x2400) — run 4 sampled that and every normalized tap of a
# landscape game missed. The game manifest is landscape-locked, so post-open sampling is stable.
VW=""; VH=""
sample_space(){
  local cur
  cur="$(adb shell dumpsys window displays 2>/dev/null | grep -oE 'cur=[0-9]+x[0-9]+' | head -1 | cut -d= -f2)"
  [ -n "$cur" ] || cur="$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
  VW="${cur%x*}"; VH="${cur#*x}"
  say "injection coordinate space (game foreground): ${VW}x${VH}"
}
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

# Harvest the overlay layout map NOW: TouchOverlayView.logOverlayMap logs at layout and on
# every browser-mode change, and by section 9 early lines can rotate out of the logcat ring
# buffer (~20 min of GK spam) — run 1 silently SKIPPED the whole touch-button battery that way.
adb logcat -d 2>/dev/null | grep -a 'overlay-map:' > "$OUT/overlay-map.txt" || true
say "overlay-map lines harvested at open: $(wc -l < "$OUT/overlay-map.txt")"
sample_space   # game is foreground now — the display orientation is the game's landscape

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
  # closed or lost: reopen through the menu, then pick village1. If the walk fails (run 8: a
  # mid-run desync left the browser stuck CLOSED and every later section cascaded on empty
  # state), fall back to a COLD APP RESTART — expensive but deterministic.
  if ! reopen_browser; then
    say "  (reopen via menu failed — cold app restart fallback)"
    app_restart || return 1
    rm_state
    reopen_browser || return 1
  fi
  tap_n 0.30 0.20 4.0; snap
  [ "$(field mode)" = "LIST" ]
}

# Deterministic LIST row navigation — defined here so section 4 can use it too. Facts measured
# ON THE DEVICE (manual probes, 2026-07-30): (1) scrollbar drags are ABSOLUTE on the END y and
# move `scroll` ONLY — `sel` never follows a handle jump, it changes only via pad steps or row
# taps; (2) the real track maps scroll ~= 11.477*y_px - 2135 in the 1080-px landscape space
# (track 0.172..0.938 — NOT the 0.20..0.88 the old fraction math assumed, hence 400-row landing
# errors); (3) x=0.985 dodges a right-edge overlay region that silently consumes touches at
# x=0.97 around y~0.27. Flow: feedback-corrected absolute jump -> tap a visible row to plant
# sel -> exact pad-stepping (each step re-read from the state, dropped edges self-correct).
goto_row_once(){ # ROW: leave the LIST with sel == ROW. Bounded; says WHERE it gave up.
  local ROW="$1" i j cur diff step tgt y err
  ensure_list || { say "  (goto_row $ROW: ensure_list failed)"; return 1; }
  tgt=$(( ROW > 6 ? ROW - 6 : 0 ))
  # Error-corrected jumps: run 12 pegged ~150 rows short near the list END because it re-issued
  # the SAME global-fit y four times (the fit was measured at the top; the track is not perfectly
  # linear at the extremes). After the first jump, correct the NEXT y from the MEASURED error.
  local ypx=""
  for i in 1 2 3 4 5; do
    snap; cur="$(field scroll)"; case "$cur" in ''|*[!0-9]*) say "  (goto_row $ROW: scroll='$cur')"; return 1;; esac
    err=$((tgt - cur))
    [ "${err#-}" -le 25 ] && break
    if [ -z "$ypx" ]; then
      ypx="$(awk "BEGIN{printf \"%d\", (($tgt)+2135)/11.477}")"
    else
      ypx="$(awk "BEGIN{printf \"%d\", ($ypx) + ($err)/11.477}")"
    fi
    y="$(awk "BEGIN{v=($ypx)/1080.0; if(v<0.175)v=0.175; if(v>0.945)v=0.945; printf \"%.4f\", v}")"
    swipe_n 0.985 0.20 0.985 "$y" 1200 1.5
  done
  tap_n 0.40 0.45 1.5
  snap
  if [ "$(field mode)" = "OBSERVE" ]; then  # tapped the already-selected row -> it opened
    [ "$(field row)" = "$ROW" ] && return 0
    tap_n 0.76 0.92 1.5; snap
    [ "$(field mode)" = "LIST" ] || { say "  (goto_row $ROW: stuck in $(field mode) after LIST tap)"; return 1; }
  fi
  for i in $(seq 1 12); do
    snap; cur="$(field sel)"; case "$cur" in ''|*[!0-9]*) say "  (goto_row $ROW: sel='$cur')"; return 1;; esac
    diff=$((ROW - cur))
    [ "$diff" -eq 0 ] && return 0
    if [ "$diff" -gt 0 ]; then step="down"; else step="up"; diff=$((-diff)); fi
    [ "$diff" -gt 12 ] && diff=12
    for j in $(seq 1 "$diff"); do padb "$step" 0.25; done
  done
  say "  (goto_row $ROW: pad-stepping did not converge, sel=$(field sel))"
  return 1
}
goto_row(){ # one full retry from scratch: a single dropped tap/swipe must not fail a section
  goto_row_once "$1" && return 0
  say "  (goto_row $1: retrying from scratch)"
  goto_row_once "$1"
}

# ---- 2. R3 -> FREECAM (pad entry) -----------------------------------------------------
say ""
say "=== 2. GAMEPAD: injected r3 enters FREECAM from the browser ==="
b_mode="$(field mode)"
padb "r3" 2.0; snap; a_mode="$(field mode)"
check "cpad_inject r3 -> FREECAM (first-person reticle mode)" "mode" "$b_mode" "$a_mode" equals "FREECAM"
say "--- freecam state ---"; printf '%s\n' "$STATE" | tee -a "$LOG"

# ---- 3. FLIGHT + V2.1 PER-AXIS SIGN PROOF ---------------------------------------------
# Owner (v2.1): "Left/Right Up/Down/Pan left/Pan Right sont inversés". Run 5 only checked
# that values CHANGED — sign-blind, so a mirrored rig passed. Now each of the 4 axes is
# proven against the documented convention, in BOTH directions (8 signed checks):
#   move X : stick right (lx=255) -> camera translates along SCREEN-RIGHT
#   move Y : stick up    (ly=0)   -> camera advances along the LOOK vector
#   look X : stick right (rx=255) -> the view turns RIGHT = yaw DECREASES
#   look Y : stick up    (ry=0)   -> the view tilts UP    = pitch INCREASES
# Engine ground truth (geometry.gc:255 row0 = fwd x down; math-camera.gc:142 negative X
# scale): SCREEN-RIGHT for fwd=(sin yaw, 0, cos yaw) is (-cos yaw, 0, sin yaw), and cam-eye
# (cam-states.gc:287-319), the original game's own first-person look, decreases the angle
# for stick right. fwd = (sin yaw*cos p, sin p, cos yaw*cos p).
say ""
say "=== 3. GAMEPAD FLIGHT + PER-AXIS SIGN PROOF (4 axes, both directions) ==="
# signed yaw difference with [0,2pi) wrap: d = a-b pulled into (-pi, pi]
yawd(){ awk "BEGIN{d=$2-$1; pi=3.14159265; while(d> pi)d-=2*pi; while(d<=-pi)d+=2*pi; printf \"%.6f\", d}"; }
# dot of the fc position delta with screen-right(yaw) / fwd(yaw,pitch), all from PRE state
dot_right(){ # b_fc a_fc yaw
  awk "BEGIN{split(\"$1\",b,\",\"); split(\"$2\",a,\",\");
             dx=a[1]-b[1]; dz=a[3]-b[3];
             printf \"%.6f\", dx*(-cos($3)) + dz*(sin($3))}"
}
dot_fwd(){ # b_fc a_fc yaw pitch
  awk "BEGIN{split(\"$1\",b,\",\"); split(\"$2\",a,\",\");
             dx=a[1]-b[1]; dy=a[2]-b[2]; dz=a[3]-b[3];
             cp=cos($4);
             printf \"%.6f\", dx*sin($3)*cp + dy*sin($4) + dz*cos($3)*cp}"
}
# --- look X (pan): both directions
snap; b_yaw="$(field yaw)"
hold "rx=255" 0.8
snap; a_yaw="$(field yaw)"; D="$(yawd "$b_yaw" "$a_yaw")"
assert "AXIS look-X: pan right (rx=255) turns the view RIGHT (yaw delta < 0)" "($D) < 0" "yaw $b_yaw -> $a_yaw d=$D"
b_yaw="$a_yaw"
hold "rx=0" 0.8
snap; a_yaw="$(field yaw)"; D="$(yawd "$b_yaw" "$a_yaw")"
assert "AXIS look-X: pan left (rx=0) turns the view LEFT (yaw delta > 0)" "($D) > 0" "yaw $b_yaw -> $a_yaw d=$D"
# --- look Y (pitch): both directions
snap; b_p="$(field pitch)"
hold "ry=0" 0.7
snap; a_p="$(field pitch)"
assert "AXIS look-Y: stick up (ry=0) looks UP (pitch delta > 0)" "($a_p) - ($b_p) > 0" "pitch $b_p -> $a_p"
b_p="$a_p"
hold "ry=255" 0.5
snap; a_p="$(field pitch)"
assert "AXIS look-Y: stick down (ry=255) looks DOWN (pitch delta < 0)" "($a_p) - ($b_p) < 0" "pitch $b_p -> $a_p"
# --- move Y (fly along the look): both directions
snap; b_fc="$(field fc)"; YW="$(field yaw)"; PT="$(field pitch)"
hold "ly=0" 1.2
snap; a_fc="$(field fc)"; D="$(dot_fwd "$b_fc" "$a_fc" "$YW" "$PT")"
assert "AXIS move-Y: stick up (ly=0) flies FORWARD along the look (dot fwd > 0)" "($D) > 0" "fc $b_fc -> $a_fc dot=$D"
check "stick forward moves the camera" "fc" "$b_fc" "$a_fc" changed
snap; b_fc="$(field fc)"; YW="$(field yaw)"; PT="$(field pitch)"
hold "ly=255" 0.9
snap; a_fc="$(field fc)"; D="$(dot_fwd "$b_fc" "$a_fc" "$YW" "$PT")"
assert "AXIS move-Y: stick down (ly=255) flies BACKWARD (dot fwd < 0)" "($D) < 0" "fc $b_fc -> $a_fc dot=$D"
# --- move X (strafe): both directions
snap; b_fc="$(field fc)"; YW="$(field yaw)"
hold "lx=255" 1.0
snap; a_fc="$(field fc)"; D="$(dot_right "$b_fc" "$a_fc" "$YW")"
assert "AXIS move-X: stick right (lx=255) strafes SCREEN-RIGHT (dot right > 0)" "($D) > 0" "fc $b_fc -> $a_fc dot=$D"
snap; b_fc="$(field fc)"; YW="$(field yaw)"
hold "lx=0" 1.0
snap; a_fc="$(field fc)"; D="$(dot_right "$b_fc" "$a_fc" "$YW")"
assert "AXIS move-X: stick left (lx=0) strafes SCREEN-LEFT (dot right < 0)" "($D) < 0" "fc $b_fc -> $a_fc dot=$D"
# --- vertical flight (the "in the air" requirement): pitch up then fly forward
hold "ry=0" 0.9            # look up
snap; m_y="$(echo "$(field fc)" | cut -d, -f2)"
hold "ly=0" 1.2
snap; v_fc="$(field fc)"; v_y="$(echo "$v_fc" | cut -d, -f2)"
check "pitched-up flight gains ALTITUDE (fly in the air)" "fc.y" "$m_y" "$v_y" grew
hold "ry=255" 0.7          # level back out for the pick section

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
# V2.1: the pick now sorts SURFACE-first (an origin-enclosing AABB ranks by where the ray
# LEAVES it, and near-ties go to the smaller box) — in run 5 the wanted row took up to 13 R1
# presses because giant camera-enclosing boxes all sorted at t=0; the owner pressing R1 once
# therefore always targeted an invisible enclosing mesh, which is exactly why every toggle
# looked dead to him. Track how many presses each mesh needs now.
PICKOK=0; NPICK=0; FIRSTHIT=0; PRESS_TOTAL=0
LASTMESH=""
# DETERMINISTIC compact rows (run 8: fraction sampling landed on SCATTERED tex populations —
# VIL3-LORES-TREESIDE2, a far-LOD shell, and an endcap population whose shared centroid sits in
# EMPTY SPACE. Under v2.2 nearest-hit semantics a ray through an empty centroid legitimately
# carries no triangle of that row, so it is unacquirable BY DESIGN — correct pick behaviour, bad
# test-mesh choice. Five compact rows spread across the village: roof / dock plank / single
# beach rock / lamp (tiny) / hut wall.)
# (2156 vil-beach-01 was tried as mesh #5 and is WRONG for this section: its 460 m bbox makes
# the auto-framing park the camera ~540 m out and the ray finds zero candidates — keep the
# battery on compact rows; 2156 stays the staging row for sections 5/6c where R1-cycling from
# a close-up vantage is what matters.)
# V2.3 row refresh (run 1 measured): 4626 vil-hut-wood-01endcap is a scattered population whose
# shared centroid sits in EMPTY SPACE — under the v2.3 triangle-exact pick the centroid ray hits
# 4 other meshes' real triangles and never the endcap's (runtime == CPU reference 20/20, so this
# is CORRECT pick behaviour, bad test-mesh choice — the same class run 8 documented). 6470 never
# reached the pick at all: LIST pad-stepping refused to converge around row ~6500 twice (8645,
# FARTHER in the list, converges fine — flaky stepping zone, and 8645 keeps far-list navigation
# covered). Replaced by compact SOLID rows whose centroid lies inside their own geometry:
# 897 vil-plankwood (dock corner, diag 3.0 m) + 938 vil-beachrock (single rock, diag 2.8 m).
# (857 plankwood was tried first and is the SAME class as 4626: run-2 on-device + the offline
# pre-flight both show its centroid ray hitting a NEIGHBOURING plank/the beach first — the row's
# own triangles never on the ray. The pre-flight below is now the rule: every battery row was
# ray-cast OFFLINE against mb_pick_ref (exact same auto-framing math: az=0.6 el=0.45
# d=max(8192,0.9*diag)) and 585/897/2786/8645 are FIRST-hit on their own triangles; 938 is on
# the ray but behind the beach surface — acquired by R1 cycling, 2 presses measured on device.)
# Centroid spread of the five: (-62,28,-25) roof / (66,2,-142) dock / (45,1,-59) beach rock /
# (-109,40,212) tiny lamp / (-129,36,205) hut wall. Pick CORRECTNESS is proven by 11c's
# 20-ray exact-equivalence + 4c occlusion/out-of-view — this battery proves the acquire FLOW.
for TROW4 in 585 897 938 2786 8645; do
  NPICK=$((NPICK+1))
  goto_row "$TROW4" || { say "  FAIL mesh #$NPICK: could not reach row $TROW4 in the LIST"; FAIL=$((FAIL+1)); continue; }
  padb "x" 7.0
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
  # up to 20 R1 presses: a dense village vantage puts up to 16 AABBs on the ray (run 2:
  # pick_n=16 with the old 8-press cap — the right mesh sat beyond the cap).
  for c in $(seq 1 20); do
    padb "r1" 1.2; snap
    [ "$(field target)" = "$ROW" ] && { hit="$c"; break; }
    [ "$(field pick_n)" = "0" ] && break
  done
  if [ -n "$hit" ]; then
    PASS=$((PASS+1)); PICKOK=$((PICKOK+1)); PRESS_TOTAL=$((PRESS_TOTAL+hit))
    [ "$hit" = 1 ] && FIRSTHIT=$((FIRSTHIT+1))
    say "  PASS  mesh #$NPICK reticle pick acquired row=$ROW ($MAT) after $hit R1 press(es), pick_n=$(field pick_n)"
    LASTMESH="$ROW"
  else
    FAIL=$((FAIL+1))
    say "  FAIL  mesh #$NPICK reticle pick never acquired row=$ROW ($MAT); target=$(field target) pick_n=$(field pick_n)"
  fi
  # stay in FREECAM after the LAST mesh: sections 5-7 run the toggle battery on it
done
say "reticle pick acquired on $PICKOK/5 meshes; first-press hits: $FIRSTHIT/5; total presses: $PRESS_TOTAL (run 5: 31)"
[ "$PICKOK" -ge 5 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); say "  FAIL  pick accuracy below 5/5"; }
# V2.1 had a ">=3/5 first-press" assert here. V2.2 made it semantically OBSOLETE, not merely
# flaky (run 6: 3/5, run 7: 2/5): the pick is now REQUIRED to return the nearest surface impact
# on the ray, so when a lamp/fence legitimately sits between the OBSERVE vantage and the mesh
# being re-acquired, first press MUST select the occluder — the old assert punished exactly the
# behaviour the owner demanded. Pick CORRECTNESS is asserted by the sharper 4c cases (single-R1
# == first candidate, occlusion A-over-B, out-of-view exclusion). The rate stays logged.
say "  (info) first-press acquisition rate: $FIRSTHIT/5 (total presses $PRESS_TOTAL; occluders in front legitimately cost a cycle under v2.2 nearest-hit)"

# ---- 4c. V2.2 PICK CORRECTNESS: occlusion case + behind-camera exclusion ---------------
say ""
say "=== 4c. V2.2 nearest-hit pick: occlusion (A in front of B -> A) + out-of-view exclusion ==="
say "The pick is the FIRST IMPACT along the reticle ray: the renderers ray-test each candidate's"
say "REAL triangles, the list is sorted nearest-surface-first, and candidates whose actual"
say "geometry never crosses the ray (fat AABB, mesh elsewhere — the owner's 'prend des trucs"
say "derriere ou pas en vue') are DROPPED. pickc= exports the survivors as row:slot:surface_cm."
# OCCLUSION: single R1 from defocus -> target must equal the FIRST (nearest) candidate, with a
# farther candidate B on the SAME ray left unselected. Re-aim across list fractions until a
# vantage with >=2 surviving candidates is found (aiming, not loosening: each attempt is a real
# defocus + one real R1).
OCC_DONE=0
for OFRAC in KEEP 0.50 0.03 0.72 0.28; do
  if [ "$OFRAC" != "KEEP" ]; then
    ensure_list || continue
    swipe_n 0.97 0.20 0.97 "$(awk "BEGIN{printf \"%.4f\", 0.20 + $OFRAC*0.68}")" 800 1.5
    tap_n 0.40 0.45 1.5
    tap_n 0.40 0.45 7.0
    snap; [ "$(field mode)" = "OBSERVE" ] || continue
    padb "r3" 2.0; snap; [ "$(field mode)" = "FREECAM" ] || continue
  fi
  padb "triangle" 1.2
  padb "r1" 2.5; snap
  PICKC="$(field pickc)"; T1="$(field target)"; PN="$(field pick_n)"
  C0R="$(echo "$PICKC" | cut -d'|' -f1 | cut -d: -f1)"
  C0T="$(echo "$PICKC" | cut -d'|' -f1 | cut -d: -f3)"
  C1R="$(echo "$PICKC" | cut -d'|' -f2 | cut -d: -f1)"
  C1T="$(echo "$PICKC" | cut -d'|' -f2 | cut -d: -f3)"
  [ -n "$C1R" ] && [ "$C1R" != "$C0R" ] || continue
  say "occlusion vantage: candidates (row:slot:surface_cm) $PICKC target=$T1 pick_n=$PN"
  assert "V2.2 single R1 selects the NEAREST surface hit along the ray (target == first candidate)" "($T1) == ($C0R)" "target=$T1 c0=$C0R"
  assert "V2.2 OCCLUSION: farther mesh B on the SAME ray is NOT selected (A in front of B -> always A)" "($C0T) <= ($C1T) && ($T1) != ($C1R)" "A row=$C0R at ${C0T}cm, B row=$C1R at ${C1T}cm behind"
  OCC_DONE=1; break
done
[ "$OCC_DONE" = 1 ] || { FAIL=$((FAIL+1)); say "  FAIL  no vantage produced >=2 surviving ray candidates (occlusion case unproven)"; }
# OUT-OF-VIEW: remember the targeted mesh A, turn the camera ~180 deg (measured on the state
# yaw), defocus, R1 again. A is now behind the camera: it must never appear as candidate or
# target — 'un mesh hors vue ne doit JAMAIS etre candidat'.
snap; AROW="$(field target)"; Y0="$(field yaw)"
if [ -n "$AROW" ] && [ "$AROW" != "-1" ]; then
  for i in $(seq 1 14); do
    hold "rx=255" 0.8
    snap; YN="$(field yaw)"
    DD="$(awk "BEGIN{d=($YN)-($Y0)-3.14159265; while(d>3.14159265)d-=6.2832; while(d<=-3.14159265)d+=6.2832; if(d<0)d=-d; printf \"%.4f\", d}")"
    awk "BEGIN{exit !(($DD) < 0.5)}" && break
  done
  padb "triangle" 1.2
  padb "r1" 2.5; snap
  PICKC2="$(field pickc)"; T2="$(field target)"; T2="${T2:--1}"
  say "after ~180deg turn: yaw $Y0 -> $(field yaw); candidates: ${PICKC2:-none} target=${T2:-none}"
  BEHIND_ABSENT=1
  case "$PICKC2" in "$AROW:"*) BEHIND_ABSENT=0;; *"|$AROW:"*) BEHIND_ABSENT=0;; esac
  assert "V2.2 OUT-OF-VIEW: the mesh now BEHIND the camera is never a candidate (excluded, never selected)" "($BEHIND_ABSENT) == 1 && ($T2) != ($AROW)" "row $AROW absent from candidates after the turn"
else
  FAIL=$((FAIL+1)); say "  FAIL  no target to run the behind-camera exclusion case on"
fi

# Deterministic LIST row targeting (run 7: blind fraction sampling landed on thin/culled rows
# 4x in a row, the battery ran against a dead target and 8 checks cascaded to 0->0). The state
# file exports the exact selected row (`sel`), so converge on a CHOSEN row: coarse fast-scroll
# jump, then exact pad-stepping. Row 2156 vil-beach-01 is the staging row of choice: TFRAG,
# displacement-graded (b_disp 95.74 -> tess-capable material), 8304 faces of beach GROUND at the
# village centre — the OBSERVE camera parks at its centroid, so it is always solidly rendered
# (the desktop gizmo repro measured 49824 line prims/frame on this very row).
# (goto_row is defined next to ensure_list, above section 4.)
# From the LIST, put the freecam on a solidly-visible target near ROW: select it (OBSERVE
# centres the camera on its centroid), R3 continues that camera into FREECAM, then R1-cycle
# until a candidate with >= MIN submitted draws/frame holds the target slot.
stage_visible_target(){ # ROW MIN -> 0 with target armed and rtf_target >= MIN
  local ROW="$1" MIN="${2:-2}" c v
  goto_row "$ROW" || return 1
  padb "x" 6.0; snap
  [ "$(field mode)" = "OBSERVE" ] || return 1
  padb "r3" 2.0; snap
  [ "$(field mode)" = "FREECAM" ] || return 1
  for c in 1 2 3 4 5 6; do
    padb "r1" 1.5; snap
    [ -n "$(field target)" ] && [ "$(field target)" != "-1" ] || continue
    v="$(rtf rtf_target)"
    awk "BEGIN{exit !(($v) >= ($MIN))}" && return 0
  done
  return 1
}

# ---- 5. THE TWO PREVIOUSLY-DEAD TOGGLES: on -> off -> on via RENDER counters ----------
say ""
say "=== 5. L1/L2 HIDE + SQUARE CHECKER: both directions, runtime draw counters ==="
say "rt_hidden / rt_checker are bumped INSIDE the TFRAG/TIE draw loops (render thread)."
say "They grow while the toggle is live and freeze when it is off — a dead toggle (the"
say "owner's exact complaint) cannot move them."
snap
[ "$(field target)" != "-1" ] && [ -n "$(field target)" ] || { padb "r1" 1.5; snap; }
say "V2.1: rtf_* are PER-FRAME counters published by the render thread at end of frame —"
say "rtf_target = draws SUBMITTED for the target last frame. Hide is proven by that count"
say "hitting ZERO (supervisor: variable flips prove nothing; the submit count is the render)."
# (rtf is defined next to delta/snap_next at the top: dump-boundary sampling, not fixed seconds.)
# The battery target must be SOLIDLY visible: run 2 landed on a barely-vis environment shell
# (rtf_target=1, blinking) and every delta check then sampled zeros — a sampling artifact, not
# a dead toggle. Keep the current target if it shows >=2 submitted draws per frame; otherwise
# re-aim through the deterministic LIST->OBSERVE->R3->R1 flow on other rows until one does.
V0="$(rtf rtf_target)"
if ! awk "BEGIN{exit !(($V0) >= 2)}"; then
  # run 7: three blind re-aims all failed and the battery ran on a DEAD target. Deterministic
  # staging instead: park the camera on the beach-ground row (2156) and R1-cycle to a fat target.
  say "  (battery target too thin: rtf_target=$V0 — deterministic re-stage on the beach row)"
  if stage_visible_target 2156 2; then
    V0="$(rtf rtf_target)"
  else
    say "  (beach re-stage failed; falling back to rock row 1908)"
    stage_visible_target 1908 2 && V0="$(rtf rtf_target)"
  fi
fi
say "target for the toggle battery: target=$(field target) $(field material)"
b_h="$(field hide)"
assert "V2.1 target VISIBLE: per-frame submitted draw count > 0" "($V0) > 0" "rtf_target=$V0"
# HIDE: on
padb "l1" 1.0; snap
check "L1 sets hide" "hide" "$b_h" "$(field hide)" equals "1"
read hb ha <<< "$(delta rt_hidden 7.0)"
check "hide ON: hidden-draw counter GROWS (draws really skipped)" "rt_hidden" "$hb" "$ha" grew
V1="$(rtf rtf_target)"
assert "V2.1 hide ON: submitted draws for the target hit ZERO" "($V1) == 0" "rtf_target $V0 -> $V1"
# HIDE: off (L2 = show, the explicit other direction)
padb "l2" 1.0; snap
check "L2 clears hide (mesh shown again)" "hide" "1" "$(field hide)" equals "0"
read hb2 ha2 <<< "$(delta rt_hidden 7.0)"
check "hide OFF: hidden-draw counter FREEZES" "rt_hidden" "$hb2" "$ha2" same
V2="$(rtf rtf_target)"
assert "V2.1 hide OFF: submitted draws return (> 0)" "($V2) > 0" "rtf_target $V1 -> $V2"
# HIDE: on again (the full on -> off -> on the supervisor demands)
padb "l1" 1.0; snap
read hb3 ha3 <<< "$(delta rt_hidden 7.0)"
check "hide ON again: counter grows again (on->off->on)" "rt_hidden" "$hb3" "$ha3" grew
V3="$(rtf rtf_target)"
assert "V2.1 hide ON again: submitted draws back to ZERO (on->off->on at the renderer)" "($V3) == 0" "rtf_target $V2 -> $V3"
padb "l2" 1.0   # leave shown
# CHECKER: on -> off -> on — per-frame BIND count on the targeted mesh (v2.1: "checker not
# proven by material BINDS" is a gate fail)
C0="$(rtf rtf_checker)"
assert "V2.1 checker OFF baseline: zero checker binds per frame" "($C0) == 0" "rtf_checker=$C0"
padb "square" 1.0; snap
check "SQUARE sets the per-mesh checker" "checker2" "0" "$(field checker2)" equals "1"
read cb ca <<< "$(delta rt_checker 7.0)"
check "checker ON: checker-draw counter GROWS (real material override)" "rt_checker" "$cb" "$ca" grew
C1="$(rtf rtf_checker)"
assert "V2.1 checker ON: checker-material BINDS on the target's draws (> 0 per frame)" "($C1) > 0" "rtf_checker $C0 -> $C1"
padb "square" 1.0; snap
check "SQUARE clears the checker" "checker2" "1" "$(field checker2)" equals "0"
read cb2 ca2 <<< "$(delta rt_checker 7.0)"
check "checker OFF: counter FREEZES" "rt_checker" "$cb2" "$ca2" same
C2="$(rtf rtf_checker)"
assert "V2.1 checker OFF: binds back to ZERO per frame" "($C2) == 0" "rtf_checker $C1 -> $C2"
padb "square" 1.0; snap
read cb3 ca3 <<< "$(delta rt_checker 7.0)"
check "checker ON again: grows again (on->off->on)" "rt_checker" "$cb3" "$ca3" grew
padb "square" 1.0   # leave real texture

# ---- 6. CIRCLE: normal gizmos --------------------------------------------------------
say ""
say "=== 6. CIRCLE: normal-orientation gizmos on the target ==="
G0="$(rtf rtf_gizmo)"
assert "V2.1 gizmos OFF baseline: zero gizmo prims per frame" "($G0) == 0" "rtf_gizmo=$G0"
padb "circle" 1.5; snap
check "CIRCLE sets gizmos" "gizmos" "0" "$(field gizmos)" equals "1"
read gb ga <<< "$(delta rt_gizmo_draws 7.0)"
check "gizmo pass renders every frame while ON" "rt_gizmo_draws" "$gb" "$ga" grew
G1="$(rtf rtf_gizmo)"
assert "V2.1 gizmos ON: line primitives ACTUALLY DRAWN per frame (> 0)" "($G1) > 0" "rtf_gizmo $G0 -> $G1"
# V2.2 (owner: 'les gizmos ne s'affichent pas' while the prim counter read >0): the renderer now
# reads back a centre band of the framebuffer before and after the gizmo draw and counts the
# pixels the pass CHANGED. Emitted-but-invisible (bad program/FBO/viewport state) reads 0 here.
GPX1="$(rtf rtf_gizmo_px)"
assert "V2.2 gizmos ON SCREEN: the gizmo pass changed framebuffer pixels this frame (readback)" "($GPX1) > 0" "rtf_gizmo_px=$GPX1"
# rt_gizmo_faces is SET by the render-thread rebuild and only reaches the state file at the
# NEXT 3 s heartbeat: reading it in the toggle snap races the rebuild (run 1: file said 0 while
# logcat's '[mb-gizmos] built 110 normal arrows' proved the build). Read it AFTER the 4.5 s
# draw-delta window, when at least one heartbeat has carried the rebuilt value.
snap; GF="$(field rt_gizmo_faces)"
say "gizmo faces built for this mesh: $GF"
assert "gizmo builder produced faces (>0)" "($GF) > 0" "rt_gizmo_faces=$GF"
padb "circle" 1.0; snap
check "CIRCLE clears gizmos" "gizmos" "1" "$(field gizmos)" equals "0"
read gb2 ga2 <<< "$(delta rt_gizmo_draws 7.0)"
check "gizmos OFF: pass counter freezes" "rt_gizmo_draws" "$gb2" "$ga2" same
G2="$(rtf rtf_gizmo)"
assert "V2.1 gizmos OFF: prims back to ZERO per frame (on->off at the renderer)" "($G2) == 0" "rtf_gizmo $G1 -> $G2"
GPX2="$(rtf rtf_gizmo_px)"
assert "V2.2 gizmos OFF: zero framebuffer pixels changed by the gizmo pass" "($GPX2) == 0" "rtf_gizmo_px=$GPX2"

# ---- 6b. RELIEF: the value the SHADER UNIFORMS are pushed with (v2.1) ------------------
# Owner: "activer/desactiver le relief fonctionne pas". rtf_relief is recorded at the exact
# uniform-push site (u_pbr_normal_strength/u_pbr_height_scale relief factor, x100) in
# first_tfrag_draw_setup — the shader-side value, not the menu variable. D-pad down/up are
# the freecam relief buttons.
say ""
say "=== 6b. RELIEF: shader-uniform value follows the freecam relief buttons ==="
R0="$(rtf rtf_relief)"
say "relief uniform at start: rtf_relief=$R0 (menu relief=$(field relief))"
# slider edge: if the saved value sits at the 0 floor, step UP first (down would clamp-noop)
if awk "BEGIN{exit !(($R0) < 25)}"; then padb "up" 1.0; R0="$(rtf rtf_relief)"; fi
assert "relief uniform is being pushed at all (> 0)" "($R0) > 0" "rtf_relief=$R0"
padb "down" 1.0
R1="$(rtf rtf_relief)"
assert "V2.1 relief DOWN: uniform value drops by 25 (x100)" "($R0) - ($R1) == 25" "rtf_relief $R0 -> $R1"
padb "up" 1.0
R2="$(rtf rtf_relief)"
assert "V2.1 relief UP: uniform value returns (+25)" "($R2) - ($R1) == 25" "rtf_relief $R1 -> $R2"

# ---- 6c. V2.2 SQUARE = FULL CHECKER MATERIAL + displacement path ENGAGED ---------------
say ""
say "=== 6c. V2.2 SQUARE binds the FULL checker set + the tess path really runs on the target ==="
say "Standing owner rule: the checker is albedo + height + normal + roughness, AND the current"
say "displacement mode's real path on the target. rtf_cfull = FULL-set binder binds on the"
say "target's draws per frame; rtf_tess = target draws submitted on the TESS program per frame."
# Deterministic setup: a TFRAG-system row (TIE has no tessellation path by design — POM only),
# displacement forced to TESSELLATION via the OBSERVE DISP button, then freecam + acquire.
# Run 6 aimed blind fractions (0.03..0.96) and found TIE all five times: TFRAG is only 1303 of
# village1's 9508 rows and the worst-first sort CLUSTERS them at rows 1500-3000 (measured from
# the shipped index: 75 / 4 / 30 / 398 / 500 / 235 / 8 per 500-row band, then ~0 until 9000).
# Aim INSIDE the dense band, and when the landed row is still TIE, STEP the selection down by
# pad (LIST d-pad+X is deterministic row navigation) instead of blind re-jumps.
# Deterministic staging (runs 6+7 proved blind/nudged fraction scans cannot find this reliably):
# go STRAIGHT to known TFRAG rows with displacement-GRADED materials (the offline grader ran
# B_disp on them, so the material carries height data and is tess-eligible): 2156 vil-beach-01
# (b_disp 95.74, beach ground, always rendered), fallbacks 1908 vil-beachrock / 2090
# vil1-jng-leafyground. Force displacement=TESSELLATION in OBSERVE, then freecam + R1-cycle
# until the TARGET is a TFRAG row actually running on the TESS program.
TFOK=0
for TROW in 2156 1908 2090; do
  goto_row "$TROW" || { say "  (goto_row $TROW failed)"; continue; }
  padb "x" 6.0; snap
  [ "$(field mode)" = "OBSERVE" ] || continue
  [ "$(field system)" = "TFRAG" ] || { say "  (row $TROW reads $(field system)?)"; continue; }
  for d in 1 2 3; do
    snap; [ "$(field disp)" = "TESSELLATION" ] && break
    tap_n 0.32 0.78 1.5
  done
  snap; [ "$(field disp)" = "TESSELLATION" ] || continue
  padb "r3" 2.0; snap; [ "$(field mode)" = "FREECAM" ] || continue
  # R1-cycle: the nearest surface at the beach vantage is normally the beach itself, but a TIE
  # rock can legally sit first on the ray — cycle to a TFRAG target on the tess program.
  for c in 1 2 3 4 5 6; do
    padb "r1" 1.5; snap
    [ -n "$(field target)" ] && [ "$(field target)" != "-1" ] && [ "$(field system)" = "TFRAG" ] || continue
    TV="$(rtf rtf_target)"
    awk "BEGIN{exit !(($TV) >= 1)}" || continue
    # the row must live in a tess-ELIGIBLE tree (normal kind): rtf_tess counts target draws on
    # the TESS program with checker OFF too — a LOWRES/special-tree row would zero the Square
    # assert for tree-kind reasons, not checker reasons. Staging condition, not a loosened check.
    TSPRE="$(rtf rtf_tess)"
    awk "BEGIN{exit !(($TSPRE) >= 1)}" || { say "  (row $TROW candidate $c: not on the tess program)"; continue; }
    TFOK=1; break
  done
  [ "$TFOK" = 1 ] && break
done
if [ "$TFOK" = 1 ]; then
  say "tess-proof target: row=$(field target) $(field material) system=$(field system) disp=$(field disp) rtf_target=$TV"
  CF0="$(rtf rtf_cfull)"
  assert "V2.2 checker OFF baseline: zero FULL-set binds per frame" "($CF0) == 0" "rtf_cfull=$CF0"
  padb "square" 1.2; snap
  CF1="$(rtf rtf_cfull)"; TS1="$(rtf rtf_tess)"; CB1="$(rtf rtf_checker)"
  assert "V2.2 SQUARE binds the FULL checker set (albedo + height + normal + rough maps) on the target's draws" "($CF1) > 0 && ($CB1) > 0" "rtf_cfull=$CF1 rtf_checker=$CB1 per frame"
  assert "V2.2 displacement path ACTIVE on the checkered target: draws ran on the TESS program (height map bound)" "($TS1) > 0" "rtf_tess=$TS1 per frame"
  padb "square" 1.2; snap
  CF2="$(rtf rtf_cfull)"
  assert "V2.2 checker OFF again: FULL-set binds back to ZERO (on->off at the renderer)" "($CF2) == 0" "rtf_cfull=$CF2"
else
  FAIL=$((FAIL+1)); say "  FAIL  could not stage a TFRAG target with displacement=TESSELLATION (tess-engaged proof cannot run)"
fi

# Deterministic FREECAM + solidly-visible target, from ANY session state. Sections 7-9 each
# start here: run 6's 6c staging failure left the session in OBSERVE and every later section
# (written assuming FREECAM) read an empty/stale state file — 12 cascade FAILs that had nothing
# to do with the features under test.
ensure_freecam_target(){
  local f
  snap
  if [ "$(field mode)" = "FREECAM" ] && [ -n "$(field target)" ] && [ "$(field target)" != "-1" ]; then
    f="$(rtf rtf_target)"; awk "BEGIN{exit !(($f) >= 1)}" && return 0
  fi
  for f in 0.50 0.21 0.03 0.72; do
    ensure_list || continue
    swipe_n 0.97 0.20 0.97 "$(awk "BEGIN{printf \"%.4f\", 0.20 + $f*0.68}")" 800 1.5
    tap_n 0.40 0.45 1.5
    tap_n 0.40 0.45 7.0
    snap; [ "$(field mode)" = "OBSERVE" ] || continue
    padb "r3" 2.0; snap; [ "$(field mode)" = "FREECAM" ] || continue
    padb "r1" 1.5; snap
    [ -n "$(field target)" ] && [ "$(field target)" != "-1" ] || continue
    local v; v="$(rtf rtf_target)"
    awk "BEGIN{exit !(($v) >= 1)}" && return 0
  done
  return 1
}

# ---- 7. TRIANGLE defocus makes the toggles inert --------------------------------------
say ""
say "=== 7. TRIANGLE: defocus (toggles become inert) ==="
ensure_freecam_target || { FAIL=$((FAIL+1)); say "  FAIL  section 7: could not re-establish FREECAM + target"; }
padb "l1" 1.0             # hide the target...
padb "triangle" 1.0; snap  # ...then defocus: C++ clears the flags with the target
check "defocus clears the target" "target" "x" "$(field target)" equals "-1"
check "defocus resets hide (no orphaned hidden mesh)" "hide" "1" "$(field hide)" equals "0"
read db da <<< "$(delta rt_hidden 7.0)"
check "after defocus nothing is hidden (counter frozen)" "rt_hidden" "$db" "$da" same

# ---- 8. R3 exits; R3 from CLOSED re-enters (gameplay-side entry) -----------------------
say ""
say "=== 8. R3 exit + R3 entry from CLOSED (the owner's L3/R3 gameplay entry) ==="
# the exit test is only meaningful FROM freecam — re-establish if section 7 left us elsewhere
snap; [ "$(field mode)" = "FREECAM" ] || ensure_freecam_target || say "  (not in FREECAM before the exit test)"
padb "r3" 2.0; snap
if [ -z "$STATE" ] || [ "$(field mode)" = "CLOSED" ]; then
  PASS=$((PASS+1)); say "  PASS  r3 exits freecam (mode=CLOSED, world handed back)"
else
  FAIL=$((FAIL+1)); say "  FAIL  r3 did not exit freecam (mode=$(field mode))"
fi
# same menu-guard as 9e: the entry gate refuses while a menu is up (by design)
MS8="$(adb logcat -d 2>/dev/null | grep -a 'overlay-mode: left-control now' | tail -1)"
case "$MS8" in *MENU*) say "  (stray menu detected — closing it with START first)"; padb "start" 2.0 ;; esac
rm_state
padb "r3" 2.5; snap
check "r3 from CLOSED enters freecam directly (no menu needed)" "mode" "" "$(field mode)" equals "FREECAM"

# ---- 9. TOUCH: overlay drives the freecam (owner has no gamepad) -----------------------
say ""
say "=== 9. TOUCH: overlay buttons drive every freecam action (injected input tap) ==="
say "coords come from the overlay's own 'overlay-map:' dumps. The overlay re-dumps the map on"
say "every browser-mode change (run 3: the view RESIZED 2298x934 -> 2400x1080 mid-session and"
say "the proportional layout moved every circle ~95px off the open-time map — missing the r=57"
say "circles while still inside the wide pills). Prefer the FRESHEST dump in the live buffer;"
say "ctl() takes the LAST match per control. The open-time harvest is only a fallback."
MAP="$(adb logcat -d 2>/dev/null | grep -a 'overlay-map:')"
[ -n "$MAP" ] || MAP="$(cat "$OUT/overlay-map.txt" 2>/dev/null)"
printf '%s\n' "$MAP" | grep -a 'overlay-map: fc' | tail -12 | tee -a "$LOG"
# centre of a mapped control. Two formats (TouchOverlayView.logOverlayMap):
#   rrect: name=left,top,WIDTH,HEIGHT->...   circ: name=cx,cy,radius->...
ctl(){
  # LIVE re-query per call (run 13: the view relaid-out mid-battery and the section-start map
  # missed every small control — square/circle/triangle circles AND the bottom relief pills —
  # while the unmoved wide pills kept working. TouchOverlayView logs a fresh overlay-map at every
  # LAYOUT pass, so the newest logcat dump is the truth; the cached MAP is only the fallback).
  local co live
  live="$(adb logcat -d 2>/dev/null | grep -a 'overlay-map:')"
  [ -n "$live" ] && MAP="$live"
  co="$(printf '%s\n' "$MAP" | grep -aoE "$1=[0-9,-]+" | tail -1 | cut -d= -f2)"
  [ -n "$co" ] || return 0
  local n; n="$(echo "$co" | awk -F, '{print NF}')"
  if [ "$n" = 4 ]; then echo "$co" | awk -F, '{printf "%d %d", $1+$3/2, $2+$4/2}'
  else echo "$co" | awk -F, '{printf "%d %d", $1, $2}'; fi
}
# A control missing from the harvested map is a FAIL, not a skip: run 1 skipped the whole
# touch battery silently and still said "35 passed" — exactly the stub-shaped hole the
# supervisor's validators exist to reject.
# HELD press, not `input tap`: tap's ~10 ms down/up can fall inside one GOAL pad-poll
# interval and the button edge is never seen (run 2: every single-tap fc-* control failed
# while fc-r1 'worked' only because the aim sweep re-tapped it 5x). A 280 ms hold spans
# ~17 frames — the duration of a real finger press.
# SELF-VERIFYING tap: the overlay logs `overlay-actuate: <name> tap` for every control it
# actuates, so a delivered tap is distinguishable from a miss. Runs 13/14: the view flips
# between its TWO layouts (2298x934 inset <-> 2400x1080 fullscreen) WITHOUT re-dumping the map
# (only mode changes/layout passes dump), and the two layouts scale PURELY proportionally
# (measured: fc-circle 2125,438@934 <-> 2220,507@1080, exact ratios both axes). On a verified
# miss, retry ONCE at the alternate-layout scale of the same coords, then fail honestly.
tap_ctl(){
  local name="$1" slp="${2:-1.2}" c n0 n1 try scr sh
  c="$(ctl $name)"
  [ -n "$c" ] || { FAIL=$((FAIL+1)); say "  FAIL  no overlay-map entry for $name (touch test cannot run)"; return 1; }
  for try in 1 2; do
    n0="$(adb logcat -d 2>/dev/null | grep -ac "overlay-actuate: $name tap")"
    adb shell input swipe $c $c 280; sleep "$slp"
    n1="$(adb logcat -d 2>/dev/null | grep -ac "overlay-actuate: $name tap")"
    [ "${n1:-0}" -gt "${n0:-0}" ] && return 0
    [ "$try" = 1 ] || break
    scr="$(printf '%s\n' "$MAP" | grep -aoE 'screen=[0-9]+x[0-9]+' | tail -1 | cut -d= -f2)"
    sh="${scr#*x}"
    if [ "$sh" = "934" ]; then
      c="$(echo "$c" | awk '{printf "%d %d", $1*2400/2298, $2*1080/934}')"
    else
      c="$(echo "$c" | awk '{printf "%d %d", $1*2298/2400, $2*934/1080}')"
    fi
    say "  (tap_ctl $name: no actuate at map coords — retrying at the alternate-layout scale)"
  done
  FAIL=$((FAIL+1)); say "  FAIL  tap_ctl $name: the overlay never actuated the control"; return 1
}
# 9a. R1 by finger -> target. The re-entry camera continues from wherever the title
# flythrough left it, which may point at empty sky: sweep the look a few times until the
# ray finds candidates (each attempt is a REAL finger tap; the sweep is aiming, not a
# loosened check).
# The battery below assumes an OPEN freecam — if section 8's entry check failed, re-establish
# rather than cascading 10 vacuous FAILs (run 6).
snap; [ "$(field mode)" = "FREECAM" ] || ensure_freecam_target || say "  (not in FREECAM before the touch battery)"
snap; b_t="$(field target)"
TV0=0
if tap_ctl fc-r1 1.5; then
  snap
  for sweep in 1 2 3 4; do
    if [ -n "$(field target)" ] && [ "$(field target)" != "-1" ]; then
      # a target alone is not enough for the 9b renderer proof: it must have VISIBLE draws
      # (run 2: a thin blinking environment shell zeroed every delta) — re-aim if not.
      TV0="$(rtf rtf_target)"
      awk "BEGIN{exit !(($TV0) > 0)}" && break
      tap_ctl fc-triangle 1.0
    fi
    swipe_n 0.62 0.45 0.55 0.55 400 1.0     # look around a bit (camera region, off the fc buttons)
    tap_ctl fc-r1 1.5; snap
  done
  check "TOUCH R1 button picks a target" "target" "$b_t" "$(field target)" changed
fi
# 9b. L1 by finger -> hide: the target's per-frame submitted draws hit ZERO; L2 -> back
if tap_ctl fc-l1 1.0; then snap; check "TOUCH L1 button hides" "hide" "0" "$(field hide)" equals "1"
  TV1="$(rtf rtf_target)"
  assert "TOUCH hide is live in the renderer (submitted draws $TV0 -> 0)" "($TV0) > 0 && ($TV1) == 0" "rtf_target $TV0 -> $TV1"
  tap_ctl fc-l2 1.0; snap; check "TOUCH L2 button shows again" "hide" "1" "$(field hide)" equals "0"; fi
# 9c. Square / Circle / Triangle by finger
if tap_ctl fc-square 1.0; then snap; check "TOUCH SQUARE toggles checker" "checker2" "0" "$(field checker2)" equals "1"; tap_ctl fc-square 1.0; fi
if tap_ctl fc-circle 1.0; then snap; check "TOUCH CIRCLE toggles gizmos" "gizmos" "0" "$(field gizmos)" equals "1"; tap_ctl fc-circle 1.0; fi
if tap_ctl fc-triangle 1.0; then snap; check "TOUCH TRIANGLE defocuses" "target" "x" "$(field target)" equals "-1"; fi
# 9c2. RELIEF by finger (v2.1: the owner has no adb and no pad — the relief buttons must work
# by touch, and the proof is the SHADER-UNIFORM value, same as 6b)
TR0="$(rtf rtf_relief)"
if tap_ctl fc-rel-minus 1.0; then
  TR1="$(rtf rtf_relief)"
  assert "TOUCH relief- moves the shader uniform (-25)" "($TR0) - ($TR1) == 25" "rtf_relief $TR0 -> $TR1"
  if tap_ctl fc-rel-plus 1.0; then
    TR2="$(rtf rtf_relief)"
    assert "TOUCH relief+ moves it back (+25)" "($TR2) - ($TR1) == 25" "rtf_relief $TR1 -> $TR2"
  fi
fi
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
else
  FAIL=$((FAIL+1)); say "  FAIL  no overlay-map entry for left-stick (touch fly test cannot run)"
fi
# 9e. EXIT by finger, FCAM button by finger to re-enter
EXITED=0
if tap_ctl fc-exit 2.0; then snap
  if [ -z "$STATE" ] || [ "$(field mode)" = "CLOSED" ]; then PASS=$((PASS+1)); say "  PASS  TOUCH EXIT closes freecam"; EXITED=1
  else FAIL=$((FAIL+1)); say "  FAIL  TOUCH EXIT: mode=$(field mode)"; fi
fi
# The FCAM entry test is only meaningful from a CONFIRMED-CLOSED state: if EXIT failed we are
# still in freecam and the heartbeat rewrites mode=FREECAM after rm_state — a vacuous pass
# (run 2 did exactly that). Force-close by pad as aim assistance, never as a substitute proof.
if [ "$EXITED" != 1 ]; then padb "r3" 2.0; snap
  [ -z "$STATE" ] || [ "$(field mode)" = "CLOSED" ] || say "  (could not reach CLOSED before the FCAM test)"
fi
# R3-from-CLOSED entry is gated on *master-mode* = 'game BY DESIGN (the freecam must never
# hijack a menu). Run 3: a menu had popped mid-run (environmental focus blip) and the gate
# correctly refused the CAM tap. The overlay heartbeat logs every menu-state change — read the
# LATEST one; if a menu is up, close it with START first. The tap itself must still do the
# genuine CLOSED -> FREECAM transition.
MSTATE="$(adb logcat -d 2>/dev/null | grep -a 'overlay-mode: left-control now' | tail -1)"
case "$MSTATE" in *MENU*)
  say "  (stray menu detected before the FCAM test — closing it with START first)"
  padb "start" 2.0 ;;
esac
rm_state
if tap_ctl fcam 2.5; then snap; check "TOUCH FCAM overlay button enters freecam from gameplay" "mode" "" "$(field mode)" equals "FREECAM"
  padb "r3" 1.5
fi

# ---- 11. V2.3: wireframe counter + polygon hover/mark JSONL + 20-ray pick equivalence --
say ""
say "=== 11a. V2.3 WIREFRAME: renderer edge counter ON>0 / OFF==0 / ON>0 ==="
if ensure_freecam_target; then
  snap; [ "$(field gizmos)" = "1" ] && { padb "circle" 1.5; snap; }   # known-OFF baseline
  WOFF0="$(rtf rtf_wire)"
  assert "V2.3 wireframe OFF baseline: zero edges drawn per frame" "($WOFF0) == 0" "rtf_wire=$WOFF0"
  padb "circle" 1.5; snap
  check "CIRCLE turns gizmos+wireframe ON" "gizmos" "0" "$(field gizmos)" equals "1"
  WON="$(rtf rtf_wire)"
  assert "V2.3 wireframe ON: edge draws > 0 per frame (renderer counter)" "($WON) > 0" "rtf_wire=$WON"
  padb "circle" 1.5
  WOFF="$(rtf rtf_wire)"
  assert "V2.3 wireframe OFF again: edge counter back to ZERO" "($WOFF) == 0" "rtf_wire=$WOFF"
  padb "circle" 1.5; snap   # leave gizmos+wireframe ON for the marking section
else
  FAIL=$((FAIL+1)); say "  FAIL  section 11a: could not establish FREECAM + target"
fi

say ""
say "=== 11b. V2.3 POLYGON MARKING: hover triangle + 3 injected L3 marks + adb pull JSONL ==="
snap
MB_ROW="$(field target)"; MB_LVL_STATE="village1"
HOV0="$(rtf hover)"
assert "V2.3 reticle hovers an individual polygon (triangle ordinal >= 0)" "($HOV0) >= 0" "hover=$HOV0"
# wipe any prior export so the pulled file holds exactly this run's marks
[ -n "$EXT_ROOT" ] && adb shell rm -f "$EXT_ROOT/mesh_marks.jsonl" >/dev/null 2>&1
adb shell run-as $PKG rm -f files/mesh_marks.jsonl >/dev/null 2>&1
M0="$(field marks)"; [ -n "$M0" ] || M0=0
padb "l3" 1.5; snap; M1="$(field marks)"
check "V2.3 L3 marks the hovered polygon (mark 1)" "marks" "$M0" "$M1" grew
hold "ry=170" 0.20; sleep 1.0   # small look-down nudge: a DIFFERENT polygon of the same mesh
padb "l3" 1.5; snap; M2="$(field marks)"
check "V2.3 L3 marks again after an aim nudge (mark 2)" "marks" "$M1" "$M2" grew
hold "rx=170" 0.20; sleep 1.0   # small yaw nudge
padb "l3" 1.5; snap; M3="$(field marks)"
check "V2.3 L3 marks a third polygon (mark 3)" "marks" "$M2" "$M3" grew
MARKS_FILE="$OUT/mesh_marks.jsonl"; rm -f "$MARKS_FILE"
if [ -n "$EXT_ROOT" ]; then
  adb pull "$EXT_ROOT/mesh_marks.jsonl" "$MARKS_FILE" >/dev/null 2>&1
  say "  adb pull $EXT_ROOT/mesh_marks.jsonl -> $MARKS_FILE (external asset root, owner file-manager reachable)"
fi
[ -s "$MARKS_FILE" ] || adb exec-out run-as $PKG cat files/mesh_marks.jsonl > "$MARKS_FILE" 2>/dev/null
if [ -s "$MARKS_FILE" ]; then
  python3 - "$MARKS_FILE" "$IDX" "$MB_ROW" <<'PYEOF'
import json, math, sys
path, idx_path, row_s = sys.argv[1], sys.argv[2], sys.argv[3]
recs = [json.loads(l) for l in open(path) if l.strip()]
need = ["game","level","system","row","shell","material","tex_id","tri",
        "v0_m","v1_m","v2_m","face_normal","offline_verdict","centroid_m","aabb_m"]
ok = len(recs) >= 3
missing = []
for r in recs:
    for k in need:
        if k not in r: ok = False; missing.append(k)
    v = r.get("offline_verdict", {})
    for k in ("graded","a_sign_x100","b_disp_x100"):
        if k not in v: ok = False; missing.append("offline_verdict."+k)
    n = r.get("face_normal",[0,0,0]); ln = math.sqrt(sum(x*x for x in n))
    if not (0.9 <= ln <= 1.1): ok = False; missing.append("face_normal-not-unit")
# position coherence: every marked vertex inside the record's own mesh AABB (+1 m slack)
for r in recs:
    lo, hi = r["aabb_m"]
    for key in ("v0_m","v1_m","v2_m"):
        p = r[key]
        if not all(lo[a]-1.0 <= p[a] <= hi[a]+1.0 for a in range(3)):
            ok = False; missing.append(key+"-outside-aabb")
print(f"records={len(recs)} fields_ok={ok} missing={sorted(set(missing))}")
sys.exit(0 if ok else 1)
PYEOF
  if [ $? = 0 ]; then PASS=$((PASS+1)); say "  PASS  V2.3 JSONL export: >=3 records, all fields present, positions coherent with the marked mesh"
  else FAIL=$((FAIL+1)); say "  FAIL  V2.3 JSONL export validation (see python output above)"; fi
else
  FAIL=$((FAIL+1)); say "  FAIL  V2.3 mesh_marks.jsonl absent/empty after 3 marks"
fi
padb "circle" 1.5   # gizmos off before the ray battery

say ""
say "=== 11c. V2.3 PICK = RAY-TRIANGLE EXACT: 20 reticle rays, runtime == CPU reference ==="
adb shell run-as $PKG rm -f files/mb_pick_trace.txt >/dev/null 2>&1
# 20 aim variations from the staged vantage: nudge the view, defocus, R1 -> one PICKTRACE line
# per completed pick. Mix of small/large yaw+pitch moves so rays cross different mesh stacks.
NUDGES="rx=180:0.15 ry=180:0.20 rx=60:0.25 ry=90:0.20 rx=220:0.20 ry=200:0.15 rx=40:0.30 ry=60:0.25 rx=200:0.10 ry=160:0.10 rx=90:0.20 ry=110:0.15 rx=170:0.30 ry=70:0.20 rx=140:0.10 ry=190:0.25 rx=70:0.15 ry=130:0.10 rx=210:0.15 ry=100:0.15"
NRAY=0
for nd in $NUDGES; do
  tok="${nd%%:*}"; dur="${nd##*:}"
  hold "$tok" "$dur"
  padb "triangle" 0.8         # defocus so each acquisition is the pick's own work
  padb "r1" 2.0               # fires the pick request; PICKTRACE appended on fold
  NRAY=$((NRAY+1))
done
sleep 3
adb exec-out run-as $PKG cat files/mb_pick_trace.txt > "$OUT/mb_pick_trace.txt" 2>/dev/null
NTRACE="$(grep -c '^PICKTRACE' "$OUT/mb_pick_trace.txt" 2>/dev/null)"; [ -n "$NTRACE" ] || NTRACE=0
say "  pick trace lines harvested: $NTRACE (rays fired: $NRAY)"
if [ "$NTRACE" -ge 20 ]; then
  python3 - "$OUT/mb_pick_trace.txt" "$OUT" <<'PYEOF'
import re, subprocess, sys, os
trace_path, outdir = sys.argv[1], sys.argv[2]
lines = [l for l in open(trace_path) if l.startswith("PICKTRACE")][-20:]
def gv(l, k):
    m = re.search(rf'{k}=([^ ]+)', l)
    return m.group(1) if m else None
rays, runtime, levels = [], [], set()
for l in lines:
    o = gv(l,'o').split(','); d = gv(l,'d').split(',')
    rays.append((o,d))
    runtime.append((gv(l,'row'), float(gv(l,'t'))))
    for lk in ('lvl0','lvl1'):
        lv = gv(l,lk)
        if lv and lv != '-': levels.add(lv)
rays_file = os.path.join(outdir, 'rays.txt')
with open(rays_file,'w') as f:
    for o,d in rays:
        f.write(' '.join(o) + ' ' + ' '.join(d) + '\n')
# CPU reference per level; global winner = min t across levels (what the runtime sweep does)
ref = [dict(row=None, t=None) for _ in rays]
for lv in sorted(levels):
    fr3 = f'out/jak1/fr3/{lv}.fr3'
    idx = f'custom_assets/jak1/mesh_index/mesh_index_{lv}.txt'
    if not (os.path.exists(fr3) and os.path.exists(idx)):
        print(f'reference inputs missing for {lv}: {fr3} / {idx}'); sys.exit(1)
    out = subprocess.run(['build/tools/mb_pick_ref/mb_pick_ref','--fr3',fr3,'--index',idx,'--rays',rays_file],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print('mb_pick_ref failed for', lv, out.stderr[-500:]); sys.exit(1)
    for l in out.stdout.splitlines():
        m = re.match(r'REF i=(\d+) row=(\d+) t=([0-9.eE+-]+)', l)
        if m:
            i, row, t = int(m.group(1)), m.group(2), float(m.group(3))
            if ref[i]['t'] is None or t < ref[i]['t']:
                ref[i] = dict(row=row, t=t)
match = 0; diverge = []
for i,(rt, rf) in enumerate(zip(runtime, ref)):
    r_row, r_t = rt
    e_row = rf['row'] if rf['row'] is not None else '-1'
    if r_row == e_row: match += 1
    else: diverge.append(f'ray {i}: runtime row={r_row} t={r_t:.1f} vs reference row={e_row} t={rf["t"]}')
print(f'{match}/20 runtime-vs-CPU-reference pick matches')
for d in diverge: print('  DIVERGE ' + d)
sys.exit(0 if match == 20 else 1)
PYEOF
  if [ $? = 0 ]; then PASS=$((PASS+1)); say "  PASS  V2.3 ray-triangle exact pick: 20/20 runtime picks == brute-force CPU reference"
  else FAIL=$((FAIL+1)); say "  FAIL  V2.3 pick equivalence not 20/20 (divergences listed above)"; fi
else
  FAIL=$((FAIL+1)); say "  FAIL  V2.3: fewer than 20 PICKTRACE lines harvested ($NTRACE)"
fi

# ---- 10. alive ------------------------------------------------------------------------
say ""
say "=== 10. STILL ALIVE ==="
say "focus: $(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
adb shell dumpsys activity exit-info $PKG 2>/dev/null | grep -iE 'reason|signal' | tail -6 | tee -a "$LOG"

say ""
say "================ RESULT: $PASS passed, $FAIL failed ================"
[ "$FAIL" = 0 ]
