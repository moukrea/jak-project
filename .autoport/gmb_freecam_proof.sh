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
# sample an rt_* counter twice, WIN seconds apart (heartbeat writes every 3 s)
delta(){ # field win -> prints "b a"
  snap; local b="$(field $1)"; sleep "$2"; snap; local a="$(field $1)"; echo "$b $a"
}

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
# V2.1 surface-first ordering: the mesh under the reticle must now be the FIRST pick in the
# common case (>=3/5 first-press; occluders legitimately in front may cost a cycle elsewhere).
assert "surface-first pick: >=3/5 meshes acquired on the FIRST R1 press" "($FIRSTHIT) >= 3" "first-press $FIRSTHIT/5, total $PRESS_TOTAL"

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
# fresh per-frame value (heartbeat rewrites the file every 3 s at 60 fps, ~6 s at the title's
# 30 fps; 7 s covers one for sure)
rtf(){ sleep 7.0; snap; field "$1"; }
# The battery target must be SOLIDLY visible: run 2 landed on a barely-vis environment shell
# (rtf_target=1, blinking) and every delta check then sampled zeros — a sampling artifact, not
# a dead toggle. Keep the current target if it shows >=2 submitted draws per frame; otherwise
# re-aim through the deterministic LIST->OBSERVE->R3->R1 flow on other rows until one does.
V0="$(rtf rtf_target)"
if ! awk "BEGIN{exit !(($V0) >= 2)}"; then
  for BFRAC in 0.50 0.03 0.72; do
    say "  (battery target too thin: rtf_target=$V0 — re-aiming at list fraction $BFRAC)"
    ensure_list || continue
    swipe_n 0.97 0.20 0.97 "$(awk "BEGIN{printf \"%.4f\", 0.20 + $BFRAC*0.68}")" 800 1.5
    tap_n 0.40 0.45 1.5
    tap_n 0.40 0.45 7.0
    snap; [ "$(field mode)" = "OBSERVE" ] || continue
    padb "r3" 2.0; snap; [ "$(field mode)" = "FREECAM" ] || continue
    padb "r1" 1.5; snap
    [ -n "$(field target)" ] && [ "$(field target)" != "-1" ] || continue
    V0="$(rtf rtf_target)"
    awk "BEGIN{exit !(($V0) >= 2)}" && break
  done
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
TFOK=0
for BFRAC in 0.50 0.03 0.28 0.72 0.96; do
  ensure_list || continue
  swipe_n 0.97 0.20 0.97 "$(awk "BEGIN{printf \"%.4f\", 0.20 + $BFRAC*0.68}")" 800 1.5
  tap_n 0.40 0.45 1.5
  tap_n 0.40 0.45 7.0
  snap; [ "$(field mode)" = "OBSERVE" ] || continue
  [ "$(field system)" = "TFRAG" ] || { say "  (fraction $BFRAC is $(field system) — need TFRAG)"; continue; }
  for d in 1 2 3; do
    snap; [ "$(field disp)" = "TESSELLATION" ] && break
    tap_n 0.32 0.78 1.5
  done
  snap; [ "$(field disp)" = "TESSELLATION" ] || continue
  padb "r3" 2.0; snap; [ "$(field mode)" = "FREECAM" ] || continue
  padb "r1" 1.5; snap
  [ -n "$(field target)" ] && [ "$(field target)" != "-1" ] && [ "$(field system)" = "TFRAG" ] || continue
  TV="$(rtf rtf_target)"
  awk "BEGIN{exit !(($TV) >= 1)}" || continue
  # the row must live in a tess-ELIGIBLE tree (normal kind): rtf_tess counts target draws on the
  # TESS program with checker OFF too — a LOWRES/special-tree row would zero the Square assert
  # for tree-kind reasons, not checker reasons. Staging condition, not a loosened check.
  TSPRE="$(rtf rtf_tess)"
  awk "BEGIN{exit !(($TSPRE) >= 1)}" || { say "  (fraction $BFRAC: TFRAG row not on the tess program — trying another)"; continue; }
  TFOK=1; break
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

# ---- 7. TRIANGLE defocus makes the toggles inert --------------------------------------
say ""
say "=== 7. TRIANGLE: defocus (toggles become inert) ==="
padb "l1" 1.0             # hide the target...
padb "triangle" 1.0; snap  # ...then defocus: C++ clears the flags with the target
check "defocus clears the target" "target" "x" "$(field target)" equals "-1"
check "defocus resets hide (no orphaned hidden mesh)" "hide" "1" "$(field hide)" equals "0"
read db da <<< "$(delta rt_hidden 7.0)"
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
  local co
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
tap_ctl(){ local c; c="$(ctl $1)"; [ -n "$c" ] && { adb shell input swipe $c $c 280; sleep "${2:-1.2}"; return 0; }; FAIL=$((FAIL+1)); say "  FAIL  no overlay-map entry for $1 (touch test cannot run)"; return 1; }
# 9a. R1 by finger -> target. The re-entry camera continues from wherever the title
# flythrough left it, which may point at empty sky: sweep the look a few times until the
# ray finds candidates (each attempt is a REAL finger tap; the sweep is aiming, not a
# loosened check).
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

# ---- 10. alive ------------------------------------------------------------------------
say ""
say "=== 10. STILL ALIVE ==="
say "focus: $(adb shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')"
adb shell dumpsys activity exit-info $PKG 2>/dev/null | grep -iE 'reason|signal' | tail -6 | tee -a "$LOG"

say ""
say "================ RESULT: $PASS passed, $FAIL failed ================"
[ "$FAIL" = 0 ]
