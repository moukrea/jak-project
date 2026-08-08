#!/usr/bin/env bash
# rhud5_device.sh — Grecharged-hud-jak1 ROUND 5, ARM64 DEVICE leg (eae4df44 only).
#
# Owner methodology (2026-07-09, FIRM): x86 judges LOOKS, the device judges the
# render-scale-INDEPENDENT arm64 BEHAVIOUR. So this script asks only structural questions:
#   1. does the fresh flag-set (recharged-hud ON) actually land and boot?           [freshness]
#   2. does the Recharged Settings > RECHARGED HUD row exist and toggle+persist?    [menu]
#   3. OFF == stock, ON == recharged, no crash                                      [gate]
#   4. does a HUD particle leak into WORLD space near Jak (owner round-4 item 5)?   [leak]
#   5. do the 3D icons (fuel-cell body, scout fly) render at all?                   [icons]
# Every device visual capture forces render-scale 100 first (a dynamically downscaled frame
# is not evidence).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
ACT=org.opengoal.gk.LoaderActivity   # the ONLY exported activity; <pkg>/.MainActivity does not resolve
SKIP_INSTALL="${SKIP_INSTALL:-0}"
OUT=.autoport/reports/Grecharged-hud-jak1/round5/device; mkdir -p "$OUT"
LOG="$OUT/device.log"; : > "$LOG"
MARKER="ogflags:37b4745dfd43:android-arm64"
SETF=/storage/emulated/0/OpenGOAL/jak1/settings.ini
INJECT="/data/data/$PKG/files/cpad_inject"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[rhud5-device FAIL] $*"; exit 1; }
adbs(){ "$ADB" -s "$S" "$@"; }
fg(){ adbs shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adbs exec-out screencap -p > "$OUT/device-$1.png" 2>/dev/null
        say "  shot device-$1.png ($(stat -c%s "$OUT/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
launch_fg(){ # launch_fg <settle-seconds> — start the game and WAIT until jak1 owns the window
  local secs="$1" tries=0
  while [ $tries -lt 3 ]; do
    adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
    local t=0
    while [ $t -lt 40 ]; do
      case "$(fg)" in *org.opengoal.gk.jak1*) sleep "$secs"; return 0;; esac
      sleep 5; t=$((t+5))
    done
    tries=$((tries+1)); say "  (launch attempt $tries did not reach the foreground, retrying)"
  done
  die "game never reached the foreground — every frame would be the launcher"
}
inject(){ printf '%s' "$1" | adbs shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }

# ---------------------------------------------------------------- 0. install the fresh APK
APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$APK" ] || die "no APK"
say "APK: $APK ($(stat -c%s "$APK") bytes, $(date -d @$(stat -c%Y "$APK") +%H:%M:%S))"
MARK=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | strings | grep -m1 '^ogflags:' || true)
say "APK libgk marker: $MARK (expect $MARKER = hd-models,pbr,physics,recharged-hud)"
[ "$MARK" = "$MARKER" ] || die "APK marker mismatch — wrong flag set (recharged-hud not compiled in?)"
NSYM=$(unzip -p "$APK" lib/arm64-v8a/libgk.so > /tmp/rhud5-libgk.so && nm -C /tmp/rhud5-libgk.so 2>/dev/null | grep -ci load_recharged_hud_textures || true)
say "APK libgk load_recharged_hud_textures symbols: $NSYM (must be >=1)"
[ "${NSYM:-0}" -ge 1 ] || die "the shipped libgk has NO recharged-hud loader — flag did not reach the packaged .so"

adbs devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected"
adbs shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adbs shell svc power stayon true >/dev/null 2>&1 || true
if adbs shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for the owner"; fi
adbs shell am force-stop $PKG >/dev/null 2>&1 || true
if [ "$SKIP_INSTALL" = 1 ]; then say "SKIP_INSTALL=1 — reusing the installed APK"; else
say "installing (~2 min)..."
adbs install -r -d "$APK" >> "$LOG" 2>&1 || die "adb install failed"
say "install ok"; fi

# ---------------------------------------------------------------- 1. LoaderActivity boot
# MainActivity BYPASSES pack extraction — the first boot after an install must be LoaderActivity.
adbs logcat -c >/dev/null 2>&1 || true
LC="$OUT/boot.logcat.log"; : > "$LC"
( adbs logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
trap 'kill $LCP 2>/dev/null || true' EXIT
adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
T0=$(date +%s); RF=0
while [ $(( $(date +%s)-T0 )) -lt 600 ]; do
  RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LC" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
  [ "$RF" -gt 600 ] && break; sleep 8
done
[ "$RF" -gt 600 ] || die "title never reached (render-frame=$RF) — extraction stuck?"
say "boot ok: render-frame=$RF at t+$(( $(date +%s)-T0 ))s   fg=$(fg)"

# the 11 recharged sprites must actually load into VRAM on THIS device
NTEX=$(grep -ac 'recharged-hud: loaded' "$LC" || true)
say "recharged-hud textures loaded on device: $NTEX / 11"
grep -a 'recharged-hud:' "$LC" | head -12 >> "$LOG" || true
[ "${NTEX:-0}" -ge 11 ] || say "  WARNING: expected 11 recharged sprite loads, got $NTEX"

# ---------------------------------------------------------------- 2. CGO landing proof
adbs shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
LOCAL_CGO=$(md5sum out/jak1-arm64-full/iso/GAME.CGO | cut -d' ' -f1)
DEV_CGO=$(adbs shell run-as $PKG md5sum files/cgo/jak1/GAME.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
say "GAME.CGO md5: built=$LOCAL_CGO device=$DEV_CGO"
[ "$LOCAL_CGO" = "$DEV_CGO" ] || die "device GAME.CGO is STALE"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 >> "$LOG" 2>&1 || die "deploy_verify_assets FAILED"
say "deploy_verify_assets PASS — the device runs this build's GOAL CGO/DGO set"

# ---------------------------------------------------------------- 3. settings: RS100 + HUD ON
set_key(){ # set_key <key> <value>  (top level, never at EOF: the tail of the file sits in [music])
  adbs shell cat "$SETF" 2>/dev/null | tr -d '\r' > /tmp/rhud5-set.ini || true
  [ -s /tmp/rhud5-set.ini ] || { say "  (no settings.ini yet, skipping $1)"; return; }
  if grep -q "^$1 " /tmp/rhud5-set.ini; then
    sed -i "s|^$1 .*|$1 = $2|" /tmp/rhud5-set.ini
  else
    sed -i "0,/^version /s|^\(version .*\)$|\1\n$1 = $2|" /tmp/rhud5-set.ini
  fi
  adbs push /tmp/rhud5-set.ini /sdcard/rhud5-set.ini >/dev/null 2>&1
  adbs shell cp /sdcard/rhud5-set.ini "$SETF" >/dev/null 2>&1
}
SETF_LIST(){ adbs shell cat "$SETF" 2>/dev/null | tr -d '\r' | grep -aE "^recharged-hud|^render-scale|^dynamic-render-scale|^recharged-master"; }
say "settings before: $(SETF_LIST | tr '\n' ' ')"
set_key "dynamic-render-scale?" "#f"
set_key "render-scale" "100.0"
set_key "recharged-hud?" "#t"
say "settings after : $(SETF_LIST | tr '\n' ' ')"

# ---------------------------------------------------------------- 4. ON run: warp + eco legs
run_leg(){ # run_leg <tag> <ecotype-int> <seconds>
  local tag="$1" eco="$2" secs="$3"
  adbs shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  adbs shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
  adbs shell setprop debug.opengoal.eco.spawn "$eco 45 0.4 0.0 0.4" >/dev/null 2>&1 || true
  launch_fg "$secs"
  say "leg $tag: fg=$(fg)"
  # drift Jak through the spawning eco so he collects it
  for i in 1 2 3 4 5 6; do inject "ly=0.4"; sleep 1.4; clr; inject "ly=-0.4"; sleep 1.4; clr; done
  shot "$tag-a"
  # L2 held forces every hud element on screen (stock hud debug path) -> icons + gauge visible
  inject "l2=1"; sleep 2.5; shot "$tag-l2"; clr
  sleep 2; shot "$tag-b"
}

say "== LEG ON-green (eco type 4) — leak check: any green eco particle in WORLD space near Jak? =="
adbs logcat -c >/dev/null 2>&1 || true
run_leg "ON-green" 4 95
adbs shell screenrecord --time-limit 20 --bit-rate 8000000 /sdcard/rhud5-green.mp4 >/dev/null 2>&1 &
REC=$!
for i in 1 2 3 4 5 6; do inject "ly=0.4"; sleep 1.4; clr; inject "ly=-0.4"; sleep 1.4; clr; done
wait $REC 2>/dev/null || sleep 20
adbs pull /sdcard/rhud5-green.mp4 "$OUT/device-ON-green.mp4" >/dev/null 2>&1 && say "  pulled green video ($(stat -c%s "$OUT/device-ON-green.mp4" 2>/dev/null||echo 0) B)"

say "== LEG ON-blue (eco type 3) — gauge fill + per-type centre particle =="
run_leg "ON-blue" 3 80

say "== LEG ON-cell (fuel cell, type 6) — the cell BODY must render, not just its halo =="
run_leg "ON-cell" 6 80

# ---------------------------------------------------------------- 5. OFF run (stock A/B)
say "== LEG OFF (stock hud) =="
set_key "recharged-hud?" "#f"
say "settings: $(SETF_LIST | tr '\n' ' ')"
run_leg "OFF-blue" 3 80

# ---------------------------------------------------------------- 6. persistence + crash sweep
set_key "recharged-hud?" "#t"
adbs shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
launch_fg 70
say "persistence after relaunch: $(SETF_LIST | tr '\n' ' ')  fg=$(fg)"
shot "ON-persisted"

adbs shell setprop debug.opengoal.eco.spawn "" >/dev/null 2>&1 || true
adbs logcat -d -v threadtime 2>/dev/null | grep -aE 'Fatal signal|signal 11|signal 6|GK-DIAG sig=|recharged-hud' > "$OUT/device-logcat-tail.txt" || true
NCRASH=$(grep -acE 'Fatal signal|signal 11|signal 6|GK-DIAG sig=' "$OUT/device-logcat-tail.txt" || true)
say "crash markers in logcat: ${NCRASH:-0}"
adbs shell am force-stop $PKG >/dev/null 2>&1 || true
say "[rhud5-device DONE] artifacts in $OUT"
ls -la "$OUT" | tail -30
