#!/usr/bin/env bash
# physics_device_leg.sh — Grecharged-secondary-motion DEVICE proof (Redmi eae4df44), title screen:
#   LEG D-MAX: physics?=#t quality=2, looks 1111 -> [hd-phys] params loaded (>=8 models),
#              [HD-PHYS] init chains>0, window state dumps: nan-resets=0 everywhere, maxdev<5000
#              (bounded), no native crash.
#   LEG D-OFF: physics?=#f -> ZERO [HD-PHYS] window lines (full in-game disable; init-only OK).
# Counters + state dumps only (renderer-counter-gates rule) — no capture campaigns.
# Owner settings.ini byte-restored; app killed after the test.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
LOG="$OUT/device_leg.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
INI_BAK="$OUT/.settings.ini.owner-backup-phys"
INI_TMP=$(mktemp)
WATCH="${WATCH:-150}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[device-leg FAIL] $*"; exit 1; }

say "===== secondary-motion device leg — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
$ADB -s "$S" pull "$PCS_DEV" "$INI_BAK" >/dev/null 2>&1 || die "cannot pull owner settings.ini"
say "owner settings.ini backed up ($(stat -c%s "$INI_BAK") bytes)"

set_ini_dev(){ # [music]-trap-aware: existing key in place, new keys top-level after enhanced-models
  local key="$1" val="$2"
  if grep -q "^$key = " "$INI_TMP"; then sed -i "s|^$key = .*|$key = $val|" "$INI_TMP"
  else sed -i "/^recharged-enhanced-models? = /a $key = $val" "$INI_TMP"
       grep -q "^$key = $val$" "$INI_TMP" || die "could not insert $key"
  fi
}

LCP=0
cleanup(){
  # QUOTE-STRIPPING: the local shell ate the '' before adb ever saw it, so this sent
  # `setprop debug.opengoal.level.warp` with NO value — a no-op. The props survived the run and the
  # OWNER's next launch went straight into whatever leg ran last (measured: warp=intro-start,
  # pos=-130.50 34.50 202.41 still set after a clean exit). Quote the whole command so the empty
  # string reaches the DEVICE shell, and prove it cleared rather than assuming it.
  $ADB -s "$S" shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1 </dev/null || true
  # (C14) the locomotion driver must never survive the run — a held stick on the OWNER's next
  # launch would walk Jak off a cliff on his own phone. Same quote-the-whole-command rule as warp.
  $ADB -s "$S" shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1 </dev/null || true
  local WLEFT
  WLEFT=$($ADB -s "$S" shell "getprop debug.opengoal.level.warp; getprop debug.opengoal.level.warp.pos" 2>/dev/null | tr -d '\r\n ')
  [ -z "$WLEFT" ] || say "cleanup WARNING: warp props NOT cleared (left: $WLEFT) — the owner's next launch would warp"

  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  if [ -f "$INI_BAK" ]; then
    $ADB -s "$S" push "$INI_BAK" "$PCS_DEV" >/dev/null 2>&1 \
      && say "cleanup: owner settings.ini byte-restored, app stopped" \
      || say "cleanup WARNING: could not restore owner settings.ini"
  fi
  rm -f "$INI_TMP" 2>/dev/null || true
  [ "${LCP:-0}" -gt 0 ] && kill "$LCP" 2>/dev/null || true
}
trap cleanup EXIT

run_leg(){ # run_leg <tag> <physics #t/#f> <quality> <mode expect-phys|expect-off|expect-rider|expect-intro|expect-mayor> [warp] [pos]
  local TAG="$1" PHY="$2" QUAL="$3" MODE="$4" WARP="${5:-village1-hut}" POS="${6:-}"
  local LC="$OUT/device_leg_$TAG.logcat.log"; : > "$LC"
  cp "$INI_BAK" "$INI_TMP"
  set_ini_dev 'recharged-master?' '#t'
  # WAVE 2: expect-rider runs with ENHANCED MODELS OFF on purpose. That is the one configuration in
  # which no HD companion covers the four mains, so the STOCK-actor rider is what has to give them
  # secondary motion — the owner's "physics on every look, including the original ones", proven on
  # the phone rather than argued.
  local ENHSET='#t'; [ "$MODE" = expect-rider ] && ENHSET='#f'
  set_ini_dev 'recharged-enhanced-models?' "$ENHSET"
  set_ini_dev 'hd-look-jak' 1
  set_ini_dev 'hd-look-daxter' 1
  set_ini_dev 'hd-look-keira' 1
  set_ini_dev 'hd-look-samos' 1
  # (C14c-4) D-MAYOR only: birth actors by DISTANCE instead of by visibility octree. The mayor is
  # a beach actor and every continue point that displays beach leaves the camera outside beach's
  # own BSP boxes, so `all-visible?` stays true and entity.gc skips his level's birth loop
  # entirely — his art loads and no process is ever created. This is the existing PC
  # `force-actors?` option, which entity.gc now honours in the birth loop too.
  [ "$MODE" = expect-mayor ] && set_ini_dev 'force-actors?' '#t'
  set_ini_dev 'physics?' "$PHY"
  set_ini_dev 'physics-quality' "$QUAL"
  $ADB -s "$S" push "$INI_TMP" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings.ini"
  say ""
  say "=== LEG $TAG: physics?=$PHY quality=$QUAL ($WARP warp, watch ${WATCH}s) ==="
  $ADB -s "$S" shell setprop debug.opengoal.level.warp "$WARP" >/dev/null 2>&1 </dev/null
  # the village spot is a fixed vantage; the intro cinematic drives its own camera and actors
  # (Maia and Gol exist nowhere else — [[reference_maia_gol_intro_only]]) so it must NOT be posed.
  # (C14) a leg may override the vantage: D-MAYOR poses next to the mayor's hut (he lives in the
  # BEACH level actor table, trans -116.15 10.90 45.91 — nowhere near the default spot).
  if [ -n "$POS" ]; then
    $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
  elif [ "$WARP" = village1-hut ]; then
    $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '-130.50 34.50 202.41'" >/dev/null 2>&1 </dev/null
  else
    $ADB -s "$S" shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1 </dev/null
  fi
  # (C14c-2) VIS NICKNAME OVERRIDE — why the mayor leg needs one. `beach-start` carries
  # `:vis-nick 'bea` (level-info.gc:295-311) while the position override parks Jak on village1
  # ground. level.gc:1269-1273 then sees the vis-nick level (beach) NOT inside its boxes and forces
  # the other level outside too; with neither inside, level.gc:1278 takes the "outside of bsp"
  # branch, no vis-info is ever marked in use, cam-update falls through to all-visible?=#t, and
  # entity.gc:1091-1092 skips actor spawning for that level outright. Measured: in the previous
  # run the rider list FROZE at the exact frame `Displaying level beach` landed and not one beach
  # entity ever birthed. Naming village1 as the vis level keeps it inside-boxes, so beach falls to
  # its village1-adjacency vis string — the vanilla configuration for standing at the hut with
  # beach displayed — and its actor table resumes.
  if [ -n "${VIS:-}" ]; then
    $ADB -s "$S" shell setprop debug.opengoal.want.vis "$VIS" >/dev/null 2>&1 </dev/null
  else
    $ADB -s "$S" shell setprop debug.opengoal.want.vis '' >/dev/null 2>&1 </dev/null
  fi
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  ( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I ActivityManager:W '*:S' >> "$LC" ) 2>/dev/null &
  LCP=$!
  $ADB -s "$S" shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
  local T0 W=0
  T0=$(date +%s)
  while [ $(( $(date +%s)-T0 )) -lt 420 ]; do
    grep -aq 'LEVEL-WARP-SPAWN' "$LC" 2>/dev/null && { W=1; break; }; sleep 8
  done
  [ "$W" = 1 ] || { say "FAIL($TAG): warp never landed"; return 1; }
  say "warp landed ($WARP) — watching ${WATCH}s"
  # ---- (C14-A) LOCOMOTION DRIVE — real running, not a slid transform --------------------------
  # The owner's rejection is "en courant les cheveux de Jak ne bougent PAS": the floor must be
  # measured while Jak RUNS. debug.opengoal.cpad_inject is real pad input (android_input_audio.cpp
  # watcher, 25 ms poll): ly=0 holds the stick full-forward and the run ANIMATION plays — unlike
  # target.drive, which slides the transform in idle. A box path (fwd/left/back/right, 12 s each)
  # keeps him near the vantage instead of running off into water. Settle first, drive, then leave
  # the remaining watch idle so the same execution also carries the calm ceilings (the spec's
  # "sur LA MEME execution device").
  if [ "$MODE" = expect-phys ]; then
    sleep 12
    say "leg $TAG: locomotion drive — cpad_inject box path (4 x 12 s of real running)"
    local DDIR
    for DDIR in "ly=0" "lx=0" "ly=255" "lx=255"; do
      $ADB -s "$S" shell "setprop debug.opengoal.cpad_inject '$DDIR'" >/dev/null 2>&1 </dev/null
      sleep 12
    done
    $ADB -s "$S" shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1 </dev/null
    local ILEFT
    ILEFT=$($ADB -s "$S" shell getprop debug.opengoal.cpad_inject 2>/dev/null | tr -d '\r\n ')
    [ -z "$ILEFT" ] || say "WARNING($TAG): cpad_inject NOT cleared mid-run (left: $ILEFT)"
    sleep $(( WATCH > 60 ? WATCH - 60 : 10 ))
  else
    sleep "$WATCH"
  fi
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  kill "$LCP" 2>/dev/null || true; LCP=0
  local OK=1
  # native crash scan (grep -a: logcat routed through the harness can carry binary).
  # NO bare 'SIGILL' pattern: the jak2 bind-hook INFO line contains the word ("...doesn't
  # SIGILL...") = false positive. 'Fatal signal N (SIGILL)' is still caught by 'Fatal signal'.
  local CRASH; CRASH=$(grep -acE 'Fatal signal|SIGSEGV|SIGBUS' "$LC" || true)
  local NLOAD NINIT NWIN NNAN NREST NCH
  NLOAD=$(grep -ac 'params loaded' "$LC" || true)
  NINIT=$(grep -ac '\[HD-PHYS\] init ag=' "$LC" || true)
  NCH=$(grep -a '\[HD-PHYS\] init ag=' "$LC" | grep -vc 'chains=0 ' || true)
  NWIN=$(grep -ac '\[HD-PHYS\].*window: chains=' "$LC" || true)
  NNAN=$(grep -a 'nan-resets=' "$LC" | grep -cv 'nan-resets=0 ' || true)
  NREST=$(grep -ac 'rest-converged' "$LC" || true)
  say "leg $TAG: params-loaded=$NLOAD init=$NINIT chains-resolving=$NCH windows=$NWIN nan-bad=$NNAN rest=$NREST crash=$CRASH"
  [ "$CRASH" = 0 ] || { say "FAIL($TAG): native crash markers in logcat"; OK=0; }

  # ---- (E) MENU BINDING, on the artifact that actually shipped to the phone ---------------------
  if grep -aq '\[PHYS-MENU\] FATAL' "$LC"; then
    say "FAIL($TAG): [PHYS-MENU] FATAL on device — physics rows not found / mis-ordered"; OK=0
  fi
  local NMENU; NMENU=$(grep -ac '\[PHYS-MENU\].*next-is-meshbrowser=1' "$LC" || true)
  [ "${NMENU:-0}" -ge 1 ] \
    || { say "FAIL($TAG): device log has no '[PHYS-MENU] rows wired ... next-is-meshbrowser=1'"; OK=0; }

  # ---- CYCLE-2 STRUCTURAL GATES ----------------------------------------------------------------
  # These read fields that live on the SAME logcat line as the rest of the window (the window is
  # assembled in a string buffer and emitted with ONE format call — see jak-hd-physics.gc; a
  # multi-call dump splits on device and every one of these greps would silently read as absent).
  if [ "$NWIN" -gt 0 ]; then
    local NROOT NRES NREG
    NROOT=$(grep -a 'rootdev=' "$LC" | grep -cv 'rootdev=0\.0000 ' || true)
    [ "${NROOT:-0}" = 0 ] || { say "FAIL($TAG): $NROOT window(s) with rootdev!=0 — a locked hair root moved"; OK=0; }
    NRES=$(grep -a 'resid=' "$LC" | grep -cv 'resid=0 ' || true)
    [ "${NRES:-0}" = 0 ] || { say "FAIL($TAG): $NRES window(s) with residual penetrations"; OK=0; }
    NREG=$(grep -a 'reglue=' "$LC" | awk '{if (match($0,/reglue=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 0) n++} END {print n+0}')
    [ "${NREG:-0}" -ge 1 ] || { say "FAIL($TAG): no window reports reglue>0 — fake-wind neutralization never ran on device"; OK=0; }
    say "leg $TAG: rootdev-bad=$NROOT resid-bad=$NRES reglue-windows=$NREG"
    # ---- CYCLE-3 WINDOW GATES on the phone ([HD-PHYS2] line) -----------------------------------
    # Same bars as the x86 smoke. [HD-PHYS2] is a SEPARATE format 0 call and therefore its own
    # logcat line on device — which is exactly why it carries no field name the first line owns.
    local N2 NBURST NFRZ NSTUCK AENG AREL ARSD CHEST
    N2=$(grep -ac '\[HD-PHYS2\] ag=' "$LC" || true)
    [ "${N2:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS2] line on device — cycle-3 counters never printed"; OK=0; }
    NBURST=$(grep -a 'burst=' "$LC" | grep -cv 'burst=0 ' || true)
    [ "${NBURST:-0}" = 0 ] || { say "FAIL($TAG): $NBURST device window(s) with burst!=0 — chains go wild at spawn/transition"; OK=0; }
    NFRZ=$(grep -a 'frozen=' "$LC" | grep -cv 'frozen=0 ' || true)
    [ "${NFRZ:-0}" = 0 ] || { say "FAIL($TAG): $NFRZ device window(s) with frozen!=0 — a declared chain never moved while its actor did"; OK=0; }
    # (A) "physics resumes after" — the per-CHAIN unbroken-suspension record. `authhold` counts
    # CHAIN-frames and hits 300 on any actor with a few suspended chains, so it can never answer
    # "was ONE chain never given back": holdmax can, and it is not reset by a window boundary.
    # 900 frames = 15 s of unbroken suspension is not a forced action any more, it is a stuck blend.
    NSTUCK=$(grep -a 'holdmax=' "$LC" | awk '{if (match($0,/holdmax=[0-9]+/) && substr($0,RSTART+8,RLENGTH-8)+0 >= 900) n++} END {print n+0}')
    [ "${NSTUCK:-0}" = 0 ] || { say "FAIL($TAG): $NSTUCK window(s) with holdmax>=900 — a chain was suspended and never handed back"; OK=0; }
    HMAX=$(grep -a 'holdmax=' "$LC" | awk '{if (match($0,/holdmax=[0-9]+/)) {v=substr($0,RSTART+8,RLENGTH-8)+0; if (v>m) m=v}} END {print m+0}')
    AENG=$(grep -a 'autheng=' "$LC" | awk '{if (match($0,/autheng=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    AREL=$(grep -a 'authrel=' "$LC" | awk '{if (match($0,/authrel=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    ARSD=$(grep -a 'reseed=' "$LC" | awk '{if (match($0,/reseed=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    say "leg $TAG: cycle3 lines=$N2 burst-bad=$NBURST frozen-bad=$NFRZ engage=$AENG release=$AREL reseed=$ARSD holdmax=$HMAX stuck-windows=$NSTUCK"
    if [ "${AENG:-0}" -gt 0 ] && [ "${AREL:-0}" = 0 ]; then
      say "FAIL($TAG): the authored suspension ENGAGED $AENG time(s) and never RELEASED — physics does not resume"; OK=0; fi
    # ---- CYCLE-3b/3c/3d GATES ------------------------------------------------------------------
    # (O) an unsatisfiable constraint must SETTLE, never oscillate. jitter counts velocity REVERSALS
    # above a speed floor: a chain buzzing against a collider reverses every frame, and that is the
    # number behind the owner's "jitter comme un fou". `rested` counts the chain-frames the rest
    # state actually held a fighting chain still, so the mechanism is visible even when jitter is 0.
    JIT=$(grep -a 'jitter=' "$LC" | awk '{if (match($0,/jitter=[0-9]+/)) {v=substr($0,RSTART+7,RLENGTH-7)+0; if (v>m) m=v}} END {print m+0}')
    JITW=$(grep -a 'jitter=' "$LC" | awk '{if (match($0,/jitter=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 60) n++} END {print n+0}')
    RST=$(grep -a 'rested=' "$LC" | awk '{if (match($0,/rested=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    CLM=$(grep -a 'clamped=' "$LC" | awk '{if (match($0,/clamped=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    # THE gate is the SUSTAINED fight, not the reversal count. A chain sliding along a moving body
    # reverses occasionally however well it behaves (measured: 73 isolated reversals on a Maia whose
    # rest state never even had to arm); what the owner sees is a chain reversing under contact frame
    # after frame. stickmax is that run length, it is what arms the rest damping at PHYS-STICK=12,
    # and 60 frames (1 s) of unbroken fighting is the point where "settling" stops being true.
    STK=$(grep -a 'stickmax=' "$LC" | awk '{if (match($0,/stickmax=[0-9]+/)) {v=substr($0,RSTART+9,RLENGTH-9)+0; if (v>m) m=v}} END {print m+0}')
    # PERSISTENCE IS NOT THE SIN, OSCILLATION IS. The owner's rule is "si ca ne se conforme pas...
    # ca devrait juste RESTER TRANQUILLE tout en essayant TRANQUILLEMENT de se conformer" — a chain
    # may press against a collider indefinitely, it may not VIBRATE while doing it. So a long run is
    # only a failure when the same window also shows real reversal activity.
    BADW=$(grep -a 'stickmax=' "$LC" | awk '{
        st=0; ji=0;
        if (match($0,/stickmax=[0-9]+/)) st=substr($0,RSTART+9,RLENGTH-9)+0;
        if (match($0,/jitter=[0-9]+/))   ji=substr($0,RSTART+7,RLENGTH-7)+0;
        if (st >= 60 && ji > 30) n++ } END {print n+0}')
    [ "${BADW:-0}" = 0 ] || { say "FAIL($TAG): $BADW window(s) where a chain fought a collider for >=60 frames AND kept reversing — oscillating, not settling"; OK=0; }
    # ...and a hard absurdity bound on the raw count, so a genuinely buzzing rig cannot hide behind
    # a short run length: 2 reversals per frame sustained over a window is not contact, it is noise.
    [ "${JIT:-0}" -lt 600 ] || { say "FAIL($TAG): jitter=$JIT in one window — that is not contact, that is buzzing"; OK=0; }
    # (P) the per-link influence profile must have NO step: that discontinuity IS the "cran" the
    # owner sees at mid-ear. Built bounded by the solver, graded here on what it actually built.
    ISTEP=$(grep -a 'inflstep=' "$LC" | awk '{if (match($0,/inflstep=[0-9.]+/)) {v=substr($0,RSTART+9,RLENGTH-9)+0; if (v>m) m=v}} END {printf "%.4f", m+0}')
    awk -v v="$ISTEP" 'BEGIN{exit !(v+0 <= 0.4501)}' \
      || { say "FAIL($TAG): influence profile step $ISTEP > 0.45 — the per-link transition is discontinuous (owner P)"; OK=0; }
    NPROF=$(grep -ac '\[HD-PHYS-INFL\] ag=' "$LC" || true)
    [ "${NPROF:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS-INFL] profile line — the per-link influence profile is not reported"; OK=0; }
    say "leg $TAG: cycle3bcd jitter-max=$JIT stick-max=$STK rested=$RST clamped=$CLM inflstep-max=$ISTEP profile-lines=$NPROF"
    # ---- CYCLE-4 WINDOW GATES ([HD-PHYS3] line) --------------------------------------------
    # The owner's 14:45 verdict said the cycle-3 metric measured the wrong thing. These are the
    # replacements, and they are graded here rather than restated in prose:
    #   idledrift  the largest motion a chain produced on a frame where NOTHING asked it to move
    #              (no anchor travel AND no target travel). Owner bar: ~0.
    #   idlewin    how many frames were actually scored that way. idledrift=0 over idlewin=0 is the
    #              same empty zero as cycle-3's resid=0 with push=0, and is failed as such.
    #   settletime worst frames-from-still-to-rest; unsettled = idle stretches still ringing at 1 s.
    #   freering   velocity reversals with NO contact — the population cycle 3 excluded, which is
    #              exactly where the owner sees "l'hysteresis est HORRIBLE".
    local N3 IDRIFT IDWIN SLEPT STIME UNSET FRING GBAD NOMK NONC
    N3=$(grep -ac '\[HD-PHYS3\] ag=' "$LC" || true)
    [ "${N3:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS3] line — the cycle-4 instrument never printed"; OK=0; }
    IDRIFT=$(grep -ao 'idledrift=[0-9.]*' "$LC" | sed 's/idledrift=//' | sort -g | tail -1)
    IDWIN=$(grep -a 'idlewin=' "$LC" | awk '{if (match($0,/idlewin=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    SLEPT=$(grep -a 'slept=' "$LC" | awk '{if (match($0,/slept=[0-9]+/)) s+=substr($0,RSTART+6,RLENGTH-6)} END {print s+0}')
    STIME=$(grep -ao 'settletime=[0-9]*' "$LC" | sed 's/settletime=//' | sort -g | tail -1)
    UNSET=$(grep -a 'unsettled=' "$LC" | awk '{if (match($0,/unsettled=[0-9]+/)) s+=substr($0,RSTART+10,RLENGTH-10)} END {print s+0}')
    FRING=$(grep -ao 'freering=[0-9]*' "$LC" | sed 's/freering=//' | sort -g | tail -1)
    # world DOWN with a float tolerance: the vector is renormalised every frame and the phone
    # legitimately prints -0.9999. An exact string match failed 6 windows on a reading that is
    # world-down to four decimals — the gate has to grade the direction, not the rounding.
    GBAD=$(grep -a 'gdir=(' "$LC" | awk '{
        gs=1; if (match($0,/gsamp=[0-9]+/)) gs=substr($0,RSTART+6,RLENGTH-6)+0;
        if (gs == 0) next;                       # not measured this window, not a verdict
        if (match($0,/gdir=\([^)]*\)/)) {
          v=substr($0,RSTART+6,RLENGTH-7); gsub(/[ ]/,"",v); split(v,a,",");
          x=a[1]+0; y=a[2]+0; z=a[3]+0;
          if (x*x + z*z > 0.0001 || y > -0.999) n++ } } END {print n+0}')
    GSAMP=$(grep -a 'gsamp=' "$LC" | awk '{if (match($0,/gsamp=[0-9]+/)) s+=substr($0,RSTART+6,RLENGTH-6)} END {print s+0}')
    NOMK=$(grep -a 'nomask=' "$LC" | awk '{if (match($0,/nomask=[0-9]+/)) {v=substr($0,RSTART+7,RLENGTH-7)+0; if (v>m) m=v}} END {print m+0}')
    NONC=$(grep -a 'noncol=' "$LC" | awk '{if (match($0,/noncol=[0-9]+/)) {v=substr($0,RSTART+7,RLENGTH-7)+0; if (v>m) m=v}} END {print m+0}')
    say "leg $TAG: cycle4 idledrift-max=${IDRIFT:-n/a} idle-frames=$IDWIN slept=$SLEPT settletime-max=${STIME:-n/a} unsettled=$UNSET freering-max=${FRING:-n/a} gdir-not-world=$GBAD gsamp=${GSAMP:-0} nomask-max=$NOMK noncol-max=$NONC"
    [ "${GBAD:-0}" = 0 ] || { say "FAIL($TAG): $GBAD window(s) where the applied gravity was not world (0,-1,0)"; OK=0; }
    # idle-frames=0 is a property of the SCENE, not a defect: a village of walking NPCs never
    # holds every target still for half a second. It is only a failure if NO leg in the whole run
    # ever sampled one, because then no idledrift number in the run means anything — checked once
    # at the end rather than failing a leg for the animation it was given.
    TOTIDLE=$((TOTIDLE + IDWIN))
    [ "${IDWIN:-0}" -ge 1 ] || say "note($TAG): no input-free frame in this leg — idledrift is not measurable here"
    awk -v v="${IDRIFT:-99}" 'BEGIN{exit !(v+0 <= 1.0)}' \
      || { say "FAIL($TAG): idledrift=$IDRIFT — a chain moved with no input at all (owner R/S)"; OK=0; }
    [ "${UNSET:-0}" = 0 ] || { say "FAIL($TAG): $UNSET idle stretch(es) still ringing after 1 s — it does not settle"; OK=0; }
    # ---- CYCLE-5 WINDOW GATES ([HD-PHYS4] line) ---------------------------------------------
    # The owner's 21:10 spec, graded rather than asserted:
    #   unclass    chains simulating with NO family. His rule is that every chain is classified,
    #              so anything but 0 is a data hole — and an unclassified chain does not crash, it
    #              quietly inherits family A, which on a hanging strap is the opposite bug.
    #   restdevA   how far a FAMILY A chain still sat from the MODEL pose AFTER settling, on links
    #              no collider was holding. This is the whole "pas plus haut, pas plus bas". It is
    #              measured post-settle on purpose: grading it instantly would forbid the bounce.
    #   xleg       residual penetrations into a volume belonging to the OTHER side of the body —
    #              the crossed jacket pendants, counted as their own defect.
    #   lenmin     worst simulated/authored chain-length ratio. Below 1 something was crushed
    #              (owner X, "le col de Jak ne doit pas s'ecraser").
    #   extprobe   how many collision tests were displaced onto the skinned cloth below a pendant
    #              bone. The anti-empty-zero counter for xleg: xleg=0 with extprobe=0 would mean
    #              the cloth was never tested, which is precisely the resid=0/push=0 trap again.
    local N4 UNCL RDEV XLEG LMIN EXTP FAMA FAMB TILT
    N4=$(grep -ac '\[HD-PHYS4\] ag=' "$LC" || true)
    [ "${N4:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS4] line — the cycle-5 instrument never printed"; OK=0; }
    UNCL=$(grep -a 'unclass=' "$LC" | awk '{if (match($0,/unclass=[0-9]+/)) {v=substr($0,RSTART+8,RLENGTH-8)+0; if (v>m) m=v}} END {print m+0}')
    FAMA=$(grep -a 'famA=' "$LC" | awk '{if (match($0,/famA=[0-9]+/)) {v=substr($0,RSTART+5,RLENGTH-5)+0; if (v>m) m=v}} END {print m+0}')
    FAMB=$(grep -a 'famB=' "$LC" | awk '{if (match($0,/famB=[0-9]+/)) {v=substr($0,RSTART+5,RLENGTH-5)+0; if (v>m) m=v}} END {print m+0}')
    TILT=$(grep -ao 'tiltmax=[0-9.]*' "$LC" | sed 's/tiltmax=//' | sort -g | tail -1)
    RDEV=$(grep -ao 'restdevA=[0-9.]*' "$LC" | sed 's/restdevA=//' | sort -g | tail -1)
    RWIN=$(grep -a 'restwin=' "$LC" | awk '{if (match($0,/restwin=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    XLEG=$(grep -a 'xleg=' "$LC" | awk '{if (match($0,/xleg=[0-9]+/)) s+=substr($0,RSTART+5,RLENGTH-5)} END {print s+0}')
    # (W/C6c) link-frames exempted from the fidelity sample because ANOTHER CHAIN was holding them
    # — the same exemption a body collider has always had. Reported next to restwin so the size of
    # the exempted population is readable rather than asserted; a restdevA next to xheld with no
    # restwin would be the empty zero this phase has already shipped three times.
    XHELD=$(grep -a 'xheld=' "$LC" | awk '{if (match($0,/xheld=[0-9]+/)) s+=substr($0,RSTART+6,RLENGTH-6)} END {print s+0}')
    # the sentinel (1000000) means "no chain was long enough to measure in this window" — that is
    # not a crush, so it is filtered out rather than graded as a perfect score OR as a failure.
    LMIN=$(grep -ao 'lenmin=[0-9.]*' "$LC" | sed 's/lenmin=//' | awk '{if ($1+0 < 100.0) print}' | sort -g | head -1)
    LSIM=$(grep -ao 'lensim=[0-9.]*' "$LC" | sed 's/lensim=//' | awk '{if ($1+0 < 100.0) print}' | sort -g | head -1)
    EXTP=$(grep -a 'extprobe=' "$LC" | awk '{if (match($0,/extprobe=[0-9]+/)) s+=substr($0,RSTART+9,RLENGTH-9)} END {print s+0}')
    TOTEXT=$((TOTEXT + EXTP))
    say "leg $TAG: cycle5 famA=$FAMA famB=$FAMB unclass=$UNCL tiltmax=${TILT:-n/a} restdevA=${RDEV:-n/a} restwin=$RWIN xheld=$XHELD xleg=$XLEG lenmin=${LMIN:-n/a} lensim=${LSIM:-n/a} extprobe=$EXTP"
    [ "${UNCL:-0}" = 0 ] || { say "FAIL($TAG): $UNCL chain(s) simulating with NO family — the owner's rule is that every chain is classified"; OK=0; }
    TOTREST=$((TOTREST + RWIN))
    awk -v v="${RDEV:-99}" 'BEGIN{exit !(v+0 <= 8.0)}' \
      || { say "FAIL($TAG): restdevA=$RDEV over $RWIN samples — a BODY chain settled away from the model pose (owner W)"; OK=0; }
    [ "${XLEG:-0}" = 0 ] || { say "FAIL($TAG): xleg=$XLEG — a chain ended inside the OPPOSITE side's volume (owner Z)"; OK=0; }
    if [ -n "${LSIM:-}" ]; then
      awk -v v="$LSIM" 'BEGIN{exit !(v+0 >= 0.97)}' \
        || { say "FAIL($TAG): lensim=$LSIM — a chain was CRUSHED to $LSIM of its modelled length (owner X)"; OK=0; }
    fi
    # ---- (G) chest amplitude ON THE PHONE. The chain index is read from the data file, never
    # hardcoded, so reordering physics_chains.txt cannot silently point this at another chain.
    local KM KIDX
    KM=keira-hd; grep -aq 'ag=keira-hd ' "$LC" || KM=assistant-lod0
    KIDX=$(awk -v m="$KM" -v c=chestR '
      /^\[model / { cur=0; h=$0; sub(/^\[model /,"",h); sub(/\]$/,"",h);
                    n=split(h,a," "); for (i=1;i<=n;i++) if (a[i]==m) cur=1; if (cur) k=-1; next }
      /^chain /   { if (cur) { k++; if ($2==c) { print k; exit } } }' recharged_assets/physics_chains.txt)
    if [ -n "$KIDX" ]; then
      CHEST=$(grep -a "ag=$KM .*cdev:" "$LC" | awk -v i="$KIDX" '
        { s=substr($0, index($0,"cdev:"));
          if (match(s, " " i "=[0-9.]+")) { v=substr(s, RSTART+length(i)+2, RLENGTH-length(i)-2)+0; if (v>m) m=v } }
        END { printf "%.4f", m+0 }')
      say "leg $TAG: $KM chest chain (idx $KIDX) max deviation on device = $CHEST units"
    fi
    # ---- CYCLE-13 PERIMETER GATES ([HD-PHYS5] line) ------------------------------------------
    # Owner cycle 12 threw the build out over the PERIMETER, not the counter: 204 of 345 chains
    # carried colskip= and tested nothing at all, and all 2384 volumes carried a chains= filter, so
    # a correct residual counter over a perimeter that excluded half the cast produced a zero that
    # was arithmetically exact and entirely false. Both licences are gone; these three numbers are
    # what makes their absence checkable on the phone instead of asserted in prose.
    #   ccnsum   volumes actually tested, summed over every chain of the actor, per window. This is
    #            the denominator every resid=0 in this file is implicitly divided by: at 0 the
    #            residual audit is vacuous, exactly as resid=0/push=0 was.
    #   cctrunc  chain-frames whose reachable-volume list overflowed PHYS-CCMAX. Each one is a
    #            volume a chain could reach and was not tested against — i.e. a hole. Must be 0.
    #   ccpairs  strand-vs-strand pairs actually link-tested. The owner's "encore pire" half
    #            (bangs through ears, goggles through chest, buckle through strap) can only be
    #            found by a pass that runs, and this says whether it ran.
    local N5 CCNS CCTR CCPR CCC
    N5=$(grep -ac '\[HD-PHYS5\] ag=' "$LC" || true)
    [ "${N5:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS5] line — the perimeter instrument never printed"; OK=0; }
    CCNS=$(grep -a 'ccnsum=' "$LC" | awk '{if (match($0,/ccnsum=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    CCTR=$(grep -a 'cctrunc=' "$LC" | awk '{if (match($0,/cctrunc=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    CCPR=$(grep -a 'ccpairs=' "$LC" | awk '{if (match($0,/ccpairs=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    CCC=$(grep -a 'chainvschain=' "$LC" | awk '{if (match($0,/chainvschain=[0-9]+/)) s+=substr($0,RSTART+13,RLENGTH-13)} END {print s+0}')
    MFS=$(grep -a 'mfsnap=' "$LC" | awk '{if (match($0,/mfsnap=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    MFSX=$(grep -ao 'mfsnapmax=[0-9.]*' "$LC" | sed 's/mfsnapmax=//' | sort -g | tail -1)
    MFH=$(grep -a 'mfhard=' "$LC" | awk '{if (match($0,/mfhard=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    # (C13b) the strand pass's own residual. Until this cycle it reported only the contacts it had
    # HANDLED, never the overlap it left — the same blind spot as a body audit with no perimeter.
    XV=$(grep -a 'xveto=' "$LC" | awk '{if (match($0,/xveto=[0-9]+/)) s+=substr($0,RSTART+6,RLENGTH-6)} END {print s+0}')
    XU=$(grep -a 'xunres=' "$LC" | awk '{if (match($0,/xunres=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    XUX=$(grep -ao 'xunresmax=[0-9.]*' "$LC" | sed 's/xunresmax=//' | sort -g | tail -1)
    say "leg $TAG: cycle13 ccnsum=$CCNS cctrunc=$CCTR ccpairs=$CCPR chainvschain=$CCC nomask-max=${NOMK:-n/a} mfsnap=$MFS mfsnapmax=${MFSX:-0} mfhard=$MFH xveto=$XV xunres=$XU xunresmax=${XUX:-0}"
    # xveto/xunres are DELIBERATE outcomes, not failures: refusing to resolve a strand contact INTO
    # the character is the owner's blocker outranking strand separation. They are reported so he can
    # see two strands still overlapping, and so a future cycle cannot quietly trade one for the other.
    [ "${XU:-0}" = 0 ] || say "OPEN($TAG): xunres=$XU (deepest ${XUX:-0}) — strand-vs-strand contacts left overlapping rather than pushed into the body"
    [ "${XV:-0}" = 0 ] || say "OPEN($TAG): xveto=$XV — strand pushes refused because they would have driven a link deeper into its own character"
    # (C13b) the verdict for a volume RIDING another chain. It is reported, never silently absent:
    # the whole reason `at=` volumes left `resid` is that ONE link cannot fix a two-body contact, and
    # the whole reason that is not a way of hiding it is this line.
    XB=$(grep -a 'xbres=' "$LC" | awk '{if (match($0,/xbres=[0-9]+/)) s+=substr($0,RSTART+6,RLENGTH-6)} END {print s+0}')
    XBX=$(grep -ao 'xbresmax=[0-9.]*' "$LC" | sed 's/xbresmax=//' | sort -g | tail -1)
    say "leg $TAG: cycle13b xbres=$XB xbresmax=${XBX:-0}"
    [ "${XB:-0}" = 0 ] || say "OPEN($TAG): xbres=$XB (deepest ${XBX:-0}) — a link ended inside a volume RIDING another chain (two-body contact; see the chest-collider radius open item)"
    # mfhard = the fallback could not find ANY clear point, not even the model pose. The closed-form
    # guarantee does not cover it (an at= volume riding a partner that has swung), so it is reported
    # rather than failed — but it is reported, because an unreported give-up is how this phase
    # shipped four vacuous zeros.
    [ "${MFH:-0}" = 0 ] || say "OPEN($TAG): mfhard=$MFH — the model-pose fallback found no clear point (at= volume riding a swung partner)"
    TOTCCN=$((TOTCCN + CCNS)); TOTCCP=$((TOTCCP + CCPR)); TOTCCT=$((TOTCCT + CCTR))
    [ "${CCTR:-0}" = 0 ] || { say "FAIL($TAG): cctrunc=$CCTR — a chain could reach more volumes than PHYS-CCMAX and the excess was DROPPED (that is a hole)"; OK=0; }
    [ "${CCNS:-0}" -gt 0 ] || { say "FAIL($TAG): ccnsum=0 — no chain was tested against any volume, so every resid=0 in this leg is vacuous"; OK=0; }
    # nomask changed MEANING this cycle and the gate has to change with it. It used to be "chains no
    # volume named", a property of the data; it is now "chains that reached NO volume in the whole
    # window", a property of the geometry AND of the precision level — the perimeter rebuild applies
    # the tier gate, so at quality 1 only tier-1 volumes exist and a chain whose neighbours are all
    # tier 2 legitimately reaches none. At quality 2 there is no such excuse and it is a hard fail.
    # At quality 1 it is reported, never swallowed: it goes in the report as an open item, because
    # the owner's own rule is that a low level may reduce the collider count but "JAMAIS au point de
    # laisser traverser visiblement".
    if [ "$QUAL" = 2 ]; then
      [ "${NOMK:-0}" = 0 ] || { say "FAIL($TAG): nomask=$NOMK — a live chain reached no volume at all this window at MAX precision"; OK=0; }
    else
      [ "${NOMK:-0}" = 0 ] || say "OPEN($TAG): nomask=$NOMK at quality=$QUAL — chain(s) whose only volumes are tier 2, so they have nothing to hit at this precision level"
    fi
    # ---- CYCLE-14 WINDOW GATES ([HD-PHYS6] line) ---------------------------------------------
    # The mesh-surface audit and the resolution-jerk bound, graded on the phone:
    #   meshpen    residual penetration of the SKINNED MESH surface (extremal-vertex samples,
    #              physics_mesh.txt) into the body volumes AFTER the resolve, authored-floored.
    #              The owner's blocker measured where his eyes are; bone-level resid= produced
    #              five refutable zeros. Bar: 0.
    #   meshtested samples actually tested. A meshpen next to meshtested=0 is the same empty zero
    #              as resid=0/push=0 — failed as such.
    #   mraw/mfix  pre-resolve depth and pushes applied — the positive control's needles.
    #   resjerk    worst single-frame change in a link's offset FROM ITS AUTHORED POSE (C14c). A
    #              resolution the eye reads as a jump is worse than the clip it replaced (owner
    #              C14-D), and the offset is what the eye reads: differencing against the authored
    #              pose divides out the character's own travel, so carrying the hair along while
    #              Jak runs is not scored as a snap while a genuine one-frame jolt is.
    #   respath    the SUPERSEDED ledger (sum of the correction vectors each pass applied) kept
    #              alongside so the change of instrument is visible instead of silent. It read
    #              66389 on jak-hd in the same window that read maxdev=1031 — a claimed 16 m jump
    #              by a bone confined to 25 cm — because the spring that undoes a correction never
    #              wrote to it, so the sum only ever saw one side of the argument. Not gated.
    local N6 MESHP MTEST MRAW MFIX RESJ
    N6=$(grep -ac '\[HD-PHYS6\] ag=' "$LC" || true)
    [ "${N6:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS6] line — the cycle-14 instrument never printed"; OK=0; }
    MESHP=$(grep -ao 'meshpen=[0-9.]*' "$LC" | sed 's/meshpen=//' | sort -g | tail -1)
    MRAW=$(grep -ao 'mraw=[0-9.]*' "$LC" | sed 's/mraw=//' | sort -g | tail -1)
    RESJ=$(grep -ao 'resjerk=[0-9.]*' "$LC" | sed 's/resjerk=//' | sort -g | tail -1)
    RESP=$(grep -ao 'respath=[0-9.]*' "$LC" | sed 's/respath=//' | sort -g | tail -1)
    MTEST=$(grep -a 'meshtested=' "$LC" | awk '{if (match($0,/meshtested=[0-9]+/)) s+=substr($0,RSTART+11,RLENGTH-11)} END {print s+0}')
    MFIX=$(grep -a 'mfix=' "$LC" | awk '{if (match($0,/mfix=[0-9]+/)) s+=substr($0,RSTART+5,RLENGTH-5)} END {print s+0}')
    say "leg $TAG: cycle14 meshpen=${MESHP:-0} mraw=${MRAW:-0} meshtested=$MTEST mfix=$MFIX resjerk=${RESJ:-0} respath=${RESP:-0}"
    [ "${MTEST:-0}" -ge 1 ] || { say "FAIL($TAG): meshtested=0 — the mesh-surface audit never sampled a vertex, so every meshpen in this leg is an empty zero"; OK=0; }
    awk -v v="${MESHP:-0}" 'BEGIN{exit !(v+0 <= 0.0001)}' \
      || { say "FAIL($TAG): meshpen=$MESHP — the skinned mesh surface ended a frame inside a body volume (owner blocker, mesh level)"; OK=0; }
    awk -v v="${RESJ:-0}" 'BEGIN{exit !(v+0 < 1000.0)}' \
      || { say "FAIL($TAG): resjerk=$RESJ — the resolution moved a link a visible jump in one frame"; OK=0; }
    TOTMTEST=$((TOTMTEST + MTEST))
  fi
  case "$MODE" in
    expect-phys)
      [ "$NLOAD" -ge 1 ] || { say "FAIL($TAG): no '[hd-phys] params loaded' line"; OK=0; }
      [ "$NCH" -ge 1 ] || { say "FAIL($TAG): no companion resolved any chain"; OK=0; }
      [ "$NWIN" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS] window state dump"; OK=0; }
      [ "$NNAN" = 0 ] || { say "FAIL($TAG): nan-resets nonzero — sim exploded"; OK=0; }
      local NBIG; NBIG=$(grep -a 'maxdev=' "$LC" | awk -F'maxdev=' '{print $2}' | awk '{if ($1+0 >= 5000.0) n++} END {print n+0}')
      [ "$NBIG" = 0 ] || { say "FAIL($TAG): $NBIG window(s) with maxdev>=5000 — not bounded"; OK=0; }
      # at least one MOVING bounded window (anchor animated + sim deviating) — real-gameplay proof;
      # parked windows (anchmove=0) legitimately read maxdev=0 (self-tracking rest).
      # grep on 'anchmove=' NOT 'window: chains=': the dump is TWO GOAL format calls (8-arg cap)
      # and the device logcat flushes them as TWO lines — maxdev/anchmove live on the second half.
      local NMOVDEV; NMOVDEV=$(grep -a 'anchmove=' "$LC" | awk '{
        am=0; md=0;
        if (match($0, /anchmove=[0-9.]+/)) am=substr($0, RSTART+9, RLENGTH-9)+0;
        if (match($0, /maxdev=[0-9.]+/))   md=substr($0, RSTART+7, RLENGTH-7)+0;
        if (am > 1.0 && md > 0.5 && md < 5000.0) n++ } END {print n+0}')
      [ "$NMOVDEV" -ge 1 ] || { say "FAIL($TAG): no MOVING bounded window"; OK=0; }
      say "leg $TAG: bounded-windows=yes moving-bounded-windows=$NMOVDEV"
      # ---- (C14-A) MOTION FLOORS, measured during the locomotion drive above ------------------
      # crun is the per-chain window max deviation ON LOCOMOTION FRAMES ONLY (own anchor above
      # PHYS-RUN-ANCH), so an idle vantage cannot inflate it and a dead sim cannot hide: static
      # hair while running reads exactly 0. Chain indices come from the data file, never
      # hardcoded, same rule as the (G) chest gate.
      local HIDX HRUN KM2 RIDX2 LIDX2 CRUN
      HIDX=$(awk -v m="jak-hd" -v c=hair '
        /^\[model / { cur=0; h=$0; sub(/^\[model /,"",h); sub(/\]$/,"",h);
                      n=split(h,a," "); for (i=1;i<=n;i++) if (a[i]==m) cur=1; if (cur) k=-1; next }
        /^chain /   { if (cur) { k++; if ($2==c) { print k; exit } } }' recharged_assets/physics_chains.txt)
      HRUN=$(grep -a "\[HD-PHYS6\] ag=jak-hd " "$LC" | awk -v i="$HIDX" '
        { s=substr($0, index($0,"crun:"));
          if (match(s, " " i "=[0-9.]+")) { v=substr(s, RSTART+length(i)+2, RLENGTH-length(i)-2)+0; if (v>m) m=v } }
        END { printf "%.4f", m+0 }')
      KM2=keira-hd; grep -aq "\[HD-PHYS6\] ag=keira-hd " "$LC" || KM2=assistant-lod0
      RIDX2=$(awk -v m="$KM2" -v c=chestR '
        /^\[model / { cur=0; h=$0; sub(/^\[model /,"",h); sub(/\]$/,"",h);
                      n=split(h,a," "); for (i=1;i<=n;i++) if (a[i]==m) cur=1; if (cur) k=-1; next }
        /^chain /   { if (cur) { k++; if ($2==c) { print k; exit } } }' recharged_assets/physics_chains.txt)
      LIDX2=$(awk -v m="$KM2" -v c=chestL '
        /^\[model / { cur=0; h=$0; sub(/^\[model /,"",h); sub(/\]$/,"",h);
                      n=split(h,a," "); for (i=1;i<=n;i++) if (a[i]==m) cur=1; if (cur) k=-1; next }
        /^chain /   { if (cur) { k++; if ($2==c) { print k; exit } } }' recharged_assets/physics_chains.txt)
      CRUN=$(grep -a "\[HD-PHYS6\] ag=$KM2 " "$LC" | awk -v i="$RIDX2" -v j="$LIDX2" '
        { s=substr($0, index($0,"crun:"));
          if (match(s, " " i "=[0-9.]+")) { v=substr(s, RSTART+length(i)+2, RLENGTH-length(i)-2)+0; if (v>m) m=v }
          if (match(s, " " j "=[0-9.]+")) { v=substr(s, RSTART+length(j)+2, RLENGTH-length(j)-2)+0; if (v>m) m=v } }
        END { printf "%.4f", m+0 }')
      say "leg $TAG: motion floors hairrun=$HRUN (jak-hd chain $HIDX 'hair', locomotion frames only) chestrun=$CRUN ($KM2 chestR/chestL in motion)"
      awk -v v="$HRUN" 'BEGIN{exit !(v+0 >= 100.0)}' \
        || { say "FAIL($TAG): hairrun=$HRUN < 100 — Jak's hair does not move while he RUNS (owner C14-A)"; OK=0; }
      awk -v v="$CRUN" 'BEGIN{exit !(v+0 >= 350.0)}' \
        || { say "FAIL($TAG): chestrun=$CRUN < 350 — Keira's chest is static in motion (owner C14-A)"; OK=0; }
      ;;
    expect-off)
      [ "$NWIN" = 0 ] || { say "FAIL($TAG): $NWIN window lines with physics?=#f — OFF is not off"; OK=0; }
      ;;
    expect-intro)
      # Owner M/N/U: Maia and Gol by NAME, chain by chain. They exist in no other level
      # ([[reference_maia_gol_intro_only]]), so village legs can never answer for them, and the
      # aggregate counters that "proved" them green in cycle 3 are exactly what he saw through.
      [ "$NWIN" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS] window in the intro"; OK=0; }
      local A
      for A in evilsis-lod0 evilbro-lod0 eichar-lod0 jak-hd; do
        local NW NACT NNEV PUSH RESB CDEV
        NW=$(grep -ac "ag=$A .*window: chains=" "$LC" || true)
        [ "${NW:-0}" -ge 1 ] && {
          NACT=$(grep -a "ag=$A .*window: chains=" "$LC" | awk '{if (match($0,/act=[0-9]+/)) {v=substr($0,RSTART+4,RLENGTH-4)+0; if (v>m) m=v}} END {print m+0}')
          PUSH=$(grep -a "ag=$A .*push=" "$LC" | awk '{if (match($0,/push=[0-9]+/)) s+=substr($0,RSTART+5,RLENGTH-5)} END {print s+0}')
          RESB=$(grep -a "ag=$A .*resid=" "$LC" | grep -cv 'resid=0 ' || true)
          # per-CHAIN displacement: the owner's "declared is not active" test, chain by chain
          CDEV=$(grep -a "ag=$A .*cdev:" "$LC" | tail -1 | sed 's/.*cdev:/cdev:/')
          NNEV=$(echo "$CDEV" | tr ' ' '\n' | grep -c '=0\.0000$' || true)
          say "leg $TAG: $A windows=$NW chains-active=$NACT never-moved=$NNEV push=$PUSH resid-bad=$RESB"
          say "leg $TAG: $A $CDEV"
          [ "${RESB:-0}" = 0 ] || { say "FAIL($TAG): $A has $RESB window(s) with residual penetration"; OK=0; }
          grep -a "\[HD-PHYS3\] ag=$A" "$LC" | tail -1 | sed "s/.*\[HD-PHYS3\]/leg $TAG: $A [HD-PHYS3]/" >> "$LOG"
          # CYCLE 5: the same by-name treatment for the family line. The owner has twice been shown
          # an aggregate that was green while the actor he was looking at was not, so Maia's and
          # Gol's own famA/restdevA/xleg/lenmin go into the log verbatim, per actor.
          grep -a "\[HD-PHYS4\] ag=$A" "$LC" | tail -1 | sed "s/.*\[HD-PHYS4\]/leg $TAG: $A [HD-PHYS4]/" >> "$LOG"
        } || say "leg $TAG: $A — no window (actor not present in this run)"
      done
      ;;
    expect-rider)
      # WAVE 2 device proof: stock actors, no companions. The bar is the same as everywhere else
      # (bounded, no NaN, rootdev=0, resid=0 — all gated above), plus: riders really bound to
      # shipped rigs, really stepped, and every declared chain resolved.
      local NSEEN NRIDE NRIDE0 RACT RWIN NBADC
      NSEEN=$(grep -ac '\[HD-PHYS-RIDER\] rig ' "$LC" || true)
      [ "${NSEEN:-0}" -ge 1 ] || { say "FAIL($TAG): no '[HD-PHYS-RIDER] rig' line — the post-anim hook never ran on device"; OK=0; }
      NRIDE=$(grep -a '\[HD-PHYS\] init ag=' "$LC" | grep -a 'rider=1' | grep -ac 'ag=[a-z0-9-]*-lod0 ' || true)
      NRIDE0=$(grep -a '\[HD-PHYS\] init ag=' "$LC" | grep -a 'rider=1' | grep -a 'ag=[a-z0-9-]*-lod0 ' | grep -c 'chains=0 ' || true)
      [ "${NRIDE:-0}" -ge 1 ] || { say "FAIL($TAG): no stock actor bound as a physics rider on device"; OK=0; }
      [ "$((NRIDE - NRIDE0))" -ge 1 ] || { say "FAIL($TAG): every device rider resolved chains=0"; OK=0; }
      RACT=$(grep -a '\[HD-PHYS-RIDER\] window:' "$LC" | awk '{if (match($0,/active=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 0) n++} END {print n+0}')
      [ "${RACT:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS-RIDER] window with active>0 on device"; OK=0; }
      RWIN=$(grep -ac 'ag=[a-z0-9-]*-lod0 .*window: chains=' "$LC" || true)
      [ "${RWIN:-0}" -ge 1 ] || { say "FAIL($TAG): no stock-rig [HD-PHYS] window state dump on device"; OK=0; }
      NBADC=$(grep -a '\[HD-PHYS\] ag=' "$LC" | grep -cE 'chain [0-9]+ (invalid|DROPPED)' || true)
      [ "${NBADC:-0}" = 0 ] || { say "FAIL($TAG): $NBADC chain(s) failed to resolve on device"; OK=0; }
      say "leg $TAG: rigs-seen=$NSEEN riders-bound=$NRIDE (chains=0: $NRIDE0) rider-windows=$RWIN rider-active-windows=$RACT bad-chains=$NBADC"
      grep -a '\[HD-PHYS-RIDER\] rig ' "$LC" | sed 's/.*\[HD-PHYS-RIDER\]/[HD-PHYS-RIDER]/' | sort -u >> "$LOG"
      grep -a '\[HD-PHYS\] init ag=' "$LC" | grep -a 'rider=1' | sed 's/.*\[HD-PHYS\]/[HD-PHYS]/' | sort -u >> "$LOG"
      grep -a 'PARAMSRC=' "$LC" | tail -1 >> "$LOG"
      # the external override must be the source the phone actually read (owner-facing retune path)
      grep -aq 'PARAMSRC=external-override' "$LC" \
        || { say "FAIL($TAG): device did not read the EXTERNAL physics_chains.txt override"; OK=0; }
      # (C14) the mesh-sample data must come from the same owner-retunable path
      grep -aq 'MESHSRC=external-override' "$LC" \
        || { say "FAIL($TAG): device did not read the EXTERNAL physics_mesh.txt override"; OK=0; }
      ;;
    expect-mayor)
      # (C14-B/E) THE MAYOR, BY NAME. His bow/tie ("le noeud du maire au travers de son torse")
      # is one of the three actors the owner tests first, and the cycle-14 diagnosis is exactly
      # him: link centers within tolerance while the skinned ribbon — 3.5-6x wider than its link
      # radii, measured — pierced his belly. This leg parks Jak at his hut and grades HIS mesh
      # audit, not an aggregate.
      local NWM MP6 MT6 MR6
      NWM=$(grep -ac 'ag=mayor-lod0 .*window: chains=' "$LC" || true)
      [ "${NWM:-0}" -ge 1 ] || { say "FAIL($TAG): the mayor never bound/emitted a window at his own hut"; OK=0; }
      grep -a '\[HD-PHYS6\] ag=mayor-lod0' "$LC" | tail -1 \
        | sed "s/.*\[HD-PHYS6\]/leg $TAG: mayor-lod0 [HD-PHYS6]/" >> "$LOG"
      MP6=$(grep -a '\[HD-PHYS6\] ag=mayor-lod0' "$LC" | grep -ao 'meshpen=[0-9.]*' | sed 's/meshpen=//' | sort -g | tail -1)
      MR6=$(grep -a '\[HD-PHYS6\] ag=mayor-lod0' "$LC" | grep -ao 'mraw=[0-9.]*' | sed 's/mraw=//' | sort -g | tail -1)
      MT6=$(grep -a '\[HD-PHYS6\] ag=mayor-lod0' "$LC" | awk '{if (match($0,/meshtested=[0-9]+/)) s+=substr($0,RSTART+11,RLENGTH-11)} END {print s+0}')
      say "leg $TAG: mayor bow/tie (chains tieL,tieR) at MESH level: meshpen=${MP6:-n/a} residual vs his torso/belly volumes, mraw=${MR6:-n/a} pre-resolve, over meshtested=$MT6 skinned-vertex samples"
      [ "${MT6:-0}" -ge 1 ] || { say "FAIL($TAG): mayor meshtested=0 — his bow was never sampled at mesh level"; OK=0; }
      awk -v v="${MP6:-9}" 'BEGIN{exit !(v+0 <= 0.0001)}' \
        || { say "FAIL($TAG): mayor meshpen=$MP6 — his bow still ends inside his torso at MESH level"; OK=0; }
      ;;
  esac
  [ "$OK" = 1 ]
}

FAILED=0
TOTIDLE=0
TOTEXT=0
TOTREST=0
TOTCCN=0
TOTCCP=0
TOTCCT=0
TOTMTEST=0
run_leg "D-MAX" '#t' 2 expect-phys || FAILED=1
run_leg "D-OFF" '#f' 1 expect-off  || FAILED=1
run_leg "D-RIDER" '#t' 1 expect-rider || FAILED=1
# owner cycle-3c N + cycle-4 U: Maia's hair through her body, and the collar close-up while Jak
# is lying down. Both live in the intro cinematic and nowhere else.
WATCH=200 run_leg "D-INTRO" '#t' 2 expect-intro intro-start || FAILED=1
# (C14-B/E) the mayor by name: his bow vs his torso, at mesh level, at his own hut.
# (C14c) THE WARP POINT WAS THE BUG, NOT THE PHYSICS. This leg ran `village1-hut` for two cycles
# and reported "the mayor never bound/emitted a window" + "meshtested=0" every time. He is a BEACH
# actor (decompiler_out/jak1/entities/beach-actors.json: etype mayor, trans -116.15 10.90 45.91),
# and the village1-hut continue point loads beach with `:disp1 #f` (level-info.gc:151-166): beach
# stops at status 'loaded, `birth` never runs on its entity table, so no mayor process ever exists.
# Proof in the last run's own log: his ART loaded ("merc-load lvl=beach model=mayor-lod0") while
# `ag=mayor-lod0` appears zero times and no `[HD-PHYS-RIDER] rig mayor-lod0` line is emitted at all
# — and that rider line prints even for a rig that resolves chains=0, so this was absence, not a
# chain-resolution failure (`chain N invalid|DROPPED` count in that log: 0).
# `beach-start` (level-info.gc:295-311) displays BOTH beach and village1, so the mayor births; the
# position override is unchanged and still parks Jak ~7 m from him.
# (C14c-2) position: his OWN vis volume, not village1 ground 6 m off it. beach-actors.json gives
# him visvol [[-492119.75,44632.48,171649.78],[-459351.75,61016.48,204417.78]] units =
# [(-120.1,10.9,41.9),(-112.1,14.9,49.9)] m; the previous override (-113.00 11.50 40.00) sat
# OUTSIDE that box on z and on village1's side of the boundary, which is why beach never became
# inside-boxes? and its whole actor table stayed unborn (level.gc:1269-1281 -> all-visible?=#t ->
# entity.gc:1091-1092 skips actors-update for the level). Standing on his own trans is the
# smallest change that puts the camera where the vanilla game puts it when he is on screen.
VIS=vi1 WATCH=110 run_leg "D-MAYOR" '#t' 2 expect-mayor beach-start '-116.15 11.00 45.91' || FAILED=1

say ""
say "run total: input-free frames sampled across all legs = $TOTIDLE"
[ "$TOTIDLE" -ge 1 ] || { say "FAIL(run): not one input-free frame in the whole run — every idledrift number is an empty zero"; FAILED=1; }
# Same rule for the cross-leg claim: xleg=0 is only worth something if the CLOTH below the pendant
# bones was ever the thing being tested. Checked once for the run, not per leg — a village leg with
# no jacketed actor on screen legitimately reports 0.
say "run total: model-fidelity samples across all legs, measured once each chain settles (restwin) = $TOTREST"
[ "$TOTREST" -ge 1 ] || { say "FAIL(run): restwin=0 in the whole run — restdevA graded nothing, so it is an empty zero"; FAILED=1; }
say "run total: pendant-cloth collision tests across all legs = $TOTEXT"
[ "$TOTEXT" -ge 1 ] || { say "FAIL(run): extprobe=0 in the whole run — the pendant geometry was never tested, so xleg=0 proves nothing"; FAILED=1; }
# ---- CYCLE-13 RUN TOTALS ---------------------------------------------------------------------
# The perimeter is the thing the owner's cycle-12 rejection was about, so it gets run-level totals
# of its own rather than only per-leg ones. A zero here does not mean "clean", it means "nothing
# was measured", and this phase has already shipped four of those.
say "run total: volume-tests across all legs (ccnsum) = $TOTCCN"
[ "$TOTCCN" -ge 1 ] || { say "FAIL(run): ccnsum=0 in the whole run — not one chain was tested against one volume, so every resid=0 is an empty zero"; FAILED=1; }
say "run total: strand-vs-strand pairs link-tested across all legs (ccpairs) = $TOTCCP"
[ "$TOTCCP" -ge 1 ] || { say "FAIL(run): ccpairs=0 in the whole run — the chain-vs-chain pass never ran, so the owner's worse half is unmeasured"; FAILED=1; }
say "run total: truncated perimeters across all legs (cctrunc) = $TOTCCT"
[ "$TOTCCT" = 0 ] || { say "FAIL(run): cctrunc=$TOTCCT — reachable volumes were dropped for want of list space"; FAILED=1; }
# (C14) the mesh audit must have RUN somewhere in this execution, or every meshpen above is empty
say "run total: mesh-surface samples tested across all legs (meshtested) = $TOTMTEST"
[ "$TOTMTEST" -ge 1 ] || { say "FAIL(run): meshtested=0 in the whole run — the mesh-surface audit never sampled one vertex"; FAILED=1; }
if [ "$FAILED" = 0 ]; then say "[physics device leg PASS] D-MAX + D-OFF + D-RIDER + D-INTRO + D-MAYOR green"; else say "[physics device leg FAIL] see legs above"; fi
exit "$FAILED"
