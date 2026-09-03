#!/usr/bin/env bash
# =====================================================================================
# Grecharged-mesh-browser V2.6 — DEVICE PROOF: NO 256-MARK CAP (owner hit it, silently).
#
# Owner (2026-07-31 ~10:20): "Je sais pas pourquoi je peux pas aller au-dela de 256
# polygones marques... C'est pas bon !" Cause: gfx.h MB_MARKS_MAX=256, fixed-size store,
# and pc_mb_mark_poly refused the 257th mark WITHOUT ANY MESSAGE.
# Fix under test: the store is a dynamic std::vector (MB_MARKS_MAX removed; only a 1M
# sanity bound, announced on screen via the STORE FULL HUD line) and the persistent
# highlight batches ALL marks into ONE VBO rebuilt only when the store changes.
#
# Battery (all injected input + state read-back, no visual judgement — standing rule):
#   SEED : 1099 valid village1 marks pushed to EXT_ROOT/mesh_marks.jsonl (spec allows
#          JSONL seeding for the >1000 volume; distinct tris, small beach triangles).
#   A. open browser -> freecam+target on village1: reload gives marks==1099 AND the
#      RENDERER counter rtf_marked==1099 (drawn == active, way past the old 256 cap).
#   B. l3 marks the hovered polygon -> 1100 ACCEPTED (mark #1100 > 256; total > 1000).
#   C. l3 again -> UNMARK at store index 1099 (>256) works: 1099, JSONL back too.
#   D. l3 again -> re-mark 1100 (both directions), pull JSONL == 1100 lines.
#   E. force-stop + relaunch + reopen -> resume: marks==rtf_marked==1100 (>1000).
#   F. force-stop (kill-app-after-test rule).
# Helper block below is copied verbatim from gmb_freecam_proof.sh (proven on-device).
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${S:-eae4df44}"
PKG=org.opengoal.gk.jak1
IDX=custom_assets/jak1/mesh_index/mesh_index_village1.txt
OUT=.autoport/reports/Grecharged-mesh-browser/v26-proof
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


# ---- SEED: 1099 valid village1 marks on the external asset root ------------------------
say ""
say "=== SEED: 1099 valid village1 marks -> EXT_ROOT/mesh_marks.jsonl (before any browser open) ==="
[ -n "$EXT_ROOT" ] || { say "no EXT_ROOT (files/asset_root.txt unreadable) — abort"; exit 1; }
say "EXT_ROOT=$EXT_ROOT"
NSEED=1099
SEEDF=/tmp/gmbv26_seed.jsonl
python3 - "$SEEDF" $NSEED <<'PY'
import sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path, "w") as f:
    for i in range(n):
        x = 8.0 + 0.25 * (i % 64)
        z = -30.0 - 0.25 * (i // 64)
        f.write('{"game":"jak1","level":"village1","system":"TFRAG","row":2156,'
                f'"shell":7,"material":"vil-beach-01","tex_id":123,"tri":{500000+i},'
                f'"v0_m":[{x:.4f},3.0000,{z:.4f}],"v1_m":[{x+0.2:.4f},3.0000,{z:.4f}],'
                f'"v2_m":[{x:.4f},3.0000,{z-0.2:.4f}],"face_normal":[0.000000,1.000000,0.000000],'
                '"offline_verdict":{"graded":1,"a_sign_x100":100,"b_disp_x100":0},'
                f'"centroid_m":[{x+0.07:.4f},3.0000,{z-0.07:.4f}],'
                f'"aabb_m":[[{x:.4f},3.0000,{z-0.2:.4f}],[{x+0.2:.4f},3.0000,{z:.4f}]]}}\n')
PY
adb shell rm -f "$EXT_ROOT/mesh_marks.jsonl"
adb shell run-as $PKG rm -f files/mesh_marks.jsonl >/dev/null 2>&1 || true
adb push "$SEEDF" "$EXT_ROOT/mesh_marks.jsonl" >/dev/null || { say "seed push failed"; exit 1; }
SL="$(adb shell wc -l "$EXT_ROOT/mesh_marks.jsonl" | awk '{print $1}')"
say "seeded lines on device: $SL"
[ "$SL" = "$NSEED" ] || { say "seed line count mismatch"; exit 1; }
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

# ---- A. reload volume: marks == rtf_marked == 1099 (drawn == active, > old 256 cap) ----
say ""
say "=== A. RELOAD VOLUME: freecam+target -> marks==1099 AND renderer rtf_marked==1099 ==="
ensure_freecam_target || { say "FATAL: could not establish FREECAM + target"; adb shell am force-stop $PKG; exit 1; }
snap
MA="$(field marks)"
RA="$(rtf rtf_marked)"
assert "V2.6 reload: ACTIVE marks == $NSEED (store holds all seeded marks, no 256 cap)" "(${MA:-0}) == $NSEED" "marks=$MA"
assert "V2.6 reload: RENDERER marks-drawn-per-frame == $NSEED (batched highlight draws them all)" "(${RA:-0}) == $NSEED" "rtf_marked=$RA"
assert "V2.6 reload: drawn == active (renderer counter equals the store, >1000)" "(${RA:-0}) == (${MA:-1})" "rtf_marked=$RA marks=$MA"

# ---- B. mark #1100 accepted (far beyond the old 256 refusal point) ---------------------
say ""
say "=== B. MARK #1100: l3 on the hovered polygon must be ACCEPTED (old build refused >256) ==="
snap; [ "$(field gizmos)" = "1" ] || { padb "circle" 1.5; snap; }
HOV="$(rtf hover)"
assert "reticle hovers a polygon (mark target exists)" "(${HOV:--1}) >= 0" "hover=$HOV"
padb "l3" 1.5; snap
M1="$(field marks)"
R1="$(rtf rtf_marked)"
assert "V2.6 mark #1100 ACCEPTED: active marks == $((NSEED+1))" "(${M1:-0}) == $((NSEED+1))" "marks=$M1"
assert "V2.6 mark #1100 DRAWN: rtf_marked == $((NSEED+1))" "(${R1:-0}) == $((NSEED+1))" "rtf_marked=$R1"

# ---- C. unmark at store index >= 1099 (way beyond the old 256 threshold) ---------------
say ""
say "=== C. UNMARK BEYOND THE OLD THRESHOLD: l3 again on the same polygon ==="
padb "l3" 1.5; snap
M2="$(field marks)"
R2="$(rtf rtf_marked)"
assert "V2.6 unmark at index >255 works: active marks back to $NSEED" "(${M2:-0}) == $NSEED" "marks=$M2"
assert "V2.6 unmark: rtf_marked back to $NSEED" "(${R2:-0}) == $NSEED" "rtf_marked=$R2"
FL2="$(adb shell wc -l "$EXT_ROOT/mesh_marks.jsonl" | awk '{print $1}')"
assert "V2.6 unmark removed its JSONL line (file back to $NSEED lines)" "(${FL2:-0}) == $NSEED" "file_lines=$FL2"

# ---- D. re-mark (both directions) + pull the JSONL -------------------------------------
say ""
say "=== D. RE-MARK: l3 again -> 1100 (accept/remove/accept, both directions) ==="
padb "l3" 1.5; snap
M3="$(field marks)"
assert "V2.6 re-mark: active marks == $((NSEED+1))" "(${M3:-0}) == $((NSEED+1))" "marks=$M3"
MARKS_FILE="$OUT/mesh_marks_v26.jsonl"; rm -f "$MARKS_FILE"
adb pull "$EXT_ROOT/mesh_marks.jsonl" "$MARKS_FILE" >/dev/null 2>&1
FL3="$(wc -l < "$MARKS_FILE" 2>/dev/null || echo 0)"
assert "V2.6 pulled JSONL holds $((NSEED+1)) lines (1099 seeded + the injected mark)" "(${FL3:-0}) == $((NSEED+1))" "pulled_lines=$FL3"

# ---- E. RELAUNCH: resume with the same >1000 count -------------------------------------
say ""
say "=== E. RELAUNCH (force-stop + cold start): marks must RESUME at 1100 ==="
adb shell am force-stop $PKG; sleep 3
app_restart || { say "FATAL: relaunch failed"; exit 1; }
rm_state
ensure_freecam_target || { say "FATAL: could not re-establish FREECAM after relaunch"; adb shell am force-stop $PKG; exit 1; }
snap
M4="$(field marks)"
R4="$(rtf rtf_marked)"
assert "V2.6 resume: ACTIVE marks == $((NSEED+1)) after app relaunch" "(${M4:-0}) == $((NSEED+1))" "marks=$M4"
assert "V2.6 resume: RENDERER rtf_marked == $((NSEED+1)) after app relaunch" "(${R4:-0}) == $((NSEED+1))" "rtf_marked=$R4"

# ---- F. verdict + kill the app (standing rule) -----------------------------------------
say ""
say "=== VERDICT ==="
say "PASS=$PASS FAIL=$FAIL"
adb shell am force-stop $PKG
if [ "$FAIL" -eq 0 ] && [ "$PASS" -ge 12 ]; then say "V26-DEVICE-PROOF PASS"; else say "V26-DEVICE-PROOF FAIL"; exit 1; fi
