#!/usr/bin/env bash
# Gtouch-fix VERIFICATION — every menu option type driven by REAL `adb input tap`
# only (NO D-pad in the tap sequence; cpad_inject is used ONLY for the menu-OPEN
# START press fallback and the final D-pad-still-works check).
# Row map (2400x1080, cy=0.00478*oy):
#   title:   NEWGAME 206 / LOADGAME 335 / OPTIONS 464 / SECRETS 593 / QUIT 722 / BACK 851
#   options: GAME 335 / GRAPHIC 464 / SOUND 593 / BACK 723
#   graphic: ASPECT 207 / RESOLUTION 336 / DYNRS 464 / MINRS 592 / MINFPS 721 / FPSCNT 850
#   scrolled(start=4): ... VSYNC(6)@464->; with start=2: VSYNC@723, MSAA@850
#   quit dialog yes-no row @568 (YES left / NO right)
#   load/save slots @198/396/593/791, load BACK @981, save-title CONTINUE @950
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gtouch-fix/shots; mkdir -p "$OUT"
LOG=.autoport/reports/Gtouch-fix/verify.log
FULLLOG=.autoport/reports/Gtouch-fix/verify-logcat.log
adb(){ "$ADB" -s "$S" "$@"; }
inj(){ adb shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
rel(){ inj neutral; }
press(){ inj "$1"; sleep 0.4; rel; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 fg=$(adb shell dumpsys window 2>/dev/null|grep -m1 mCurrentFocus|tr -d '\r')" | tee -a "$LOG"; }
tap(){ echo ">> input tap $1 $2   ($3)" | tee -a "$LOG"; adb shell input tap "$1" "$2"; sleep "${4:-1.6}"; grep -a 'Gtm-tap' "$FULLLOG" 2>/dev/null | tail -2 | tee -a "$LOG"; }
tapcount(){ grep -ac 'Gtm-tap' "$FULLLOG" 2>/dev/null || echo 0; }

echo "== Gtouch-fix verify $(date -Is) ==" | tee "$LOG"
rel
adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$FULLLOG" 2>&1 &
LCPID=$!
trap 'kill $LCPID 2>/dev/null||true; rel' EXIT
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
sleep 46; rel
shot 00-attract

# ---- open title menu (cpad START press = menu OPEN only; every menu
# interaction below is a real input tap). Detect via Gtm-tap count in the
# accumulating logcat file. ----
opened=0
for a in 1 2 3; do
  echo "== open attempt $a: inj START, probe-tap OPTIONS ==" | tee -a "$LOG"
  before=$(tapcount)
  press start 2.6
  tap 1200 464 "OPTIONS row" 2.4
  if [ "$(tapcount)" -gt "$before" ]; then opened=1; break; fi
done
echo "menu opened=$opened" | tee -a "$LOG"
[ "$opened" -eq 1 ] || { echo "FAILED to open menu" | tee -a "$LOG"; exit 1; }
shot 01-options

# ---- Graphic Options ----
tap 1200 464 "Graphic Options row" 2.0
shot 02-graphic-baseline

echo "== A. TOGGLE: FPS Counter, 3 CENTER taps (flip regardless of half) ==" | tee -a "$LOG"
tap 1200 850 "FPS Counter center #1"; shot t1-fps
tap 1200 850 "FPS Counter center #2"; shot t2-fps
tap 1200 850 "FPS Counter center #3"; shot t3-fps

echo "== B. SLIDER: Min Render Scale, left/left/right half taps ==" | tee -a "$LOG"
shot s0-slider-base
tap 850 592  "MinRS LEFT #1"; shot s1-slider-down1
tap 850 592  "MinRS LEFT #2"; shot s2-slider-down2
tap 1560 592 "MinRS RIGHT #1"; shot s3-slider-up1

echo "== C. SCROLL-TAP + V-SYNC toggle + BACK row ==" | tee -a "$LOG"
tap 1200 1020 "scroll-down #1" 1.0
tap 1200 1020 "scroll-down #2" 1.0
tap 1200 1020 "scroll-down #3" 1.0
tap 1200 1020 "scroll-down #4" 1.0
shot c0-scrolled
tap 1200 723 "V-Sync center #1"; shot c1-vsync-flip
tap 1200 723 "V-Sync center #2"; shot c2-vsync-restore
tap 1200 1020 "scroll-down #5" 1.0
tap 1200 1020 "scroll-down #6" 1.0
tap 1200 1020 "scroll-down #7" 1.0
shot c3-scrolled-bottom
tap 1200 850 "BACK row (graphic)" 2.0
shot c4-back-to-options

echo "== D. CAROUSEL: aspect-ratio submenu tap 4X3, then restore FIT TO SCREEN ==" | tee -a "$LOG"
tap 1200 464 "Graphic Options row" 2.0
tap 1200 207 "Aspect Ratio row" 2.0
shot d0-aspect-menu
tap 1200 336 "4X3 row" 2.5
shot d1-aspect-4x3-applied
# aspect-new apply pops back to the Graphic screen (menu still open): restore
tap 1200 207 "Aspect Ratio row (again)" 2.0
tap 1200 207 "FIT TO SCREEN row" 2.5
shot d2-aspect-restored
# back out of graphic (scrollable): scroll to the Back row and tap it
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 850 "BACK row (graphic)" 2.0
shot d3-back-to-options

echo "== E. LANGUAGE carousel by half-taps (visible value) ==" | tee -a "$LOG"
tap 1200 335 "Game Options row" 2.0
shot e0-gameopts
tap 1560 721 "LANGUAGE right half"; shot e1-lang-next
tap 850 721  "LANGUAGE left half";  shot e2-lang-restored
# back out (scrollable screen -> use Back row after scroll)
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 1020 "scroll-down" 1.0
tap 1200 850 "BACK row (game options)" 2.0
tap 1200 1020 "tap-outside back (options)" 2.0
shot e3-back-to-title

echo "== F. YES-NO dialog: QUIT GAME -> tap NO ==" | tee -a "$LOG"
tap 1200 722 "QUIT GAME row" 2.0
shot f0-quit-dialog
tap 1350 568 "NO (right half of yes-no)" 2.0
shot f1-after-no

echo "== G. D-pad still works (cpad down moves cursor; menu already open) ==" | tee -a "$LOG"
shot g0-dpad-before
press down 1.2
shot g1-dpad-after

echo "== H. SAVE/LOAD screens: slot focus + save-row ACTIVATION ==" | tee -a "$LOG"
tap 1200 335 "LOAD GAME row" 2.4
shot h0-load-screen
tap 1200 396 "load slot 2" 1.8
shot h1-slot2-focus
tap 1200 198 "load slot 1" 1.8
shot h2-slot1-focus
tap 1200 981 "BACK row (load)" 2.2
shot h3-back-to-title
tap 1200 206 "NEW GAME row" 2.6
shot h4-savetitle-screen
tap 1200 950 "CONTINUE WITHOUT SAVING" 3.0
shot h5-continue-activated
sleep 10
shot h6-intro-running
grep -aE "link finish|spool|intro|Fatal signal" "$FULLLOG" 2>/dev/null | tail -8 | tee -a "$LOG"

rel
adb shell am force-stop $PKG >/dev/null 2>&1 || true
kill $LCPID 2>/dev/null || true
echo "== DONE ==" | tee -a "$LOG"
