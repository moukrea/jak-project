#!/usr/bin/env bash
# round2_probe.sh — Grecharged-hud-jak1 round2 device HUD probe (eae4df44).
# NO rebuild / NO reinstall. Probes which HUD elements render on the CURRENTLY
# INSTALLED build with recharged-hud? ON vs OFF.
#
# IMPORTANT deviation from the task brief: the installed build (versionName
# 0.1-autoport-phase13-jak1, apk md5 7cb3487d4ae1ca2b102570b475ca29a8) has NO
# `debug.opengoal.cpad_inject` prop and NO `F1D-INJECT` code path — verified by
# grepping every __system_property_get in game/. The only HUD-force mechanism
# this build supports is `debug.opengoal.mouche.buzz=1` (spawns a REAL scout-fly
# buzzer at Jak -> scout-fly/buzzer HUD element) on top of the f1.warp game-start
# (normal in-game HUD: health heart + eco gauge appear on control). So this probe
# uses warp + mouche.buzz instead of a fictional L2-hold. Reported honestly.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SETF="files/.config/OpenGOAL/jak1/settings/pc-settings.gc"
OUT=.autoport/reports/Grecharged-hud-jak1/round2; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
push_appfile(){ # $1 local, $2 device path relative to app home
  local bn want got; bn=$(basename "$1"); want=$(sha256sum "$1" | awk '{print $1}')
  adb push "$1" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; return 1; }
  adb shell run-as $PKG cp "/data/local/tmp/$bn" "$2" || { echo "  CP-FAIL $bn"; return 1; }
  adb shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "$2" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$got" = "$want" ] || { echo "  SHA-MISMATCH $bn want=$want got=$got"; return 1; }
  echo "  push+sha OK $bn -> $2"
}
# wait for a grep -a pattern to appear in a growing logcat file, timeout secs
wait_log(){ # $1 file, $2 pattern, $3 timeout
  local f="$1" pat="$2" to="$3" i=0
  while [ "$i" -lt "$to" ]; do
    if grep -aq "$pat" "$f" 2>/dev/null; then return 0; fi
    sleep 1; i=$((i+1))
  done
  return 1
}
shot(){ # $1 name
  local p="$OUT/$1.png"
  adb exec-out screencap -p > "$p" 2>/dev/null
  echo "    shot $1.png size=$(stat -c%s "$p" 2>/dev/null||echo 0)B fg=$(fg)"
}
run_round(){ # $1 tag(ON/OFF), $2 logfile
  local tag="$1" lf="$2"
  adb shell am force-stop $PKG >/dev/null 2>&1 || true
  sleep 2
  : > "$lf"
  adb logcat -c >/dev/null 2>&1 || true
  ( adb logcat -v time > "$lf" 2>/dev/null ) &
  local lpid=$!
  echo "  [$tag] logcat pid=$lpid -> $lf"
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  echo "  [$tag] launched, waiting for F1-WARP (<=180s)..."
  local t0=$(date +%s)
  if wait_log "$lf" "F1-WARP" 180; then
    local t1=$(date +%s)
    echo "  [$tag] F1-WARP seen after $((t1-t0))s: $(grep -a F1-WARP "$lf" | head -1)"
  else
    echo "  [$tag] FAIL: F1-WARP not seen within 180s"
    kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null
    return 1
  fi
  echo "  [$tag] +10s settle for control..."
  sleep 10
  echo "  [$tag] mouche.buzz already set; waiting for MOUCHE-BUZZ (<=60s)..."
  if wait_log "$lf" "MOUCHE-BUZZ" 60; then
    echo "  [$tag] MOUCHE-BUZZ: $(grep -a MOUCHE-BUZZ "$lf" | head -1)"
  else
    echo "  [$tag] note: no MOUCHE-BUZZ line within 60s (proceeding; heart+eco HUD still captured)"
  fi
  sleep 2
  echo "  [$tag] 8 screencaps @1.2s:"
  for n in 1 2 3 4 5 6 7 8; do
    shot "probe-${tag}-l2-$n"
    sleep 1.2
  done
  kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null
  echo "  [$tag] logcat capture stopped."
}

echo "== preflight =="
adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi
echo "  device ok, unlocked"

echo "== settings: ensure recharged-hud? #t =="
adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r' > "$OUT/probe-settings-before.gc"
grep -a recharged "$OUT/probe-settings-before.gc" || echo "  (no recharged line?)"
if grep -aq '(recharged-hud? #f)' "$OUT/probe-settings-before.gc"; then
  echo "  flipping #f -> #t"
  sed 's/(recharged-hud? #f)/(recharged-hud? #t)/' "$OUT/probe-settings-before.gc" > /tmp/r2-on.gc
  push_appfile /tmp/r2-on.gc "$SETF" || { echo "settings ON push failed"; exit 1; }
else
  cp "$OUT/probe-settings-before.gc" /tmp/r2-on.gc
fi

echo "== arming warp + mouche.buzz props =="
adb shell setprop debug.opengoal.f1.warp 1 || true
adb shell setprop debug.opengoal.mouche.buzz 1 || true

echo "== ON round (recharged-hud? #t) =="
run_round ON "$OUT/probe-ON-logcat.txt" || { echo "ON round failed"; }

echo "== OFF round: flip #t -> #f =="
sed 's/(recharged-hud? #t)/(recharged-hud? #f)/' /tmp/r2-on.gc > /tmp/r2-off.gc
push_appfile /tmp/r2-off.gc "$SETF" || { echo "settings OFF push failed"; exit 1; }
echo "  device flag now: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"
run_round OFF "$OUT/probe-OFF-logcat.txt" || { echo "OFF round failed"; }

echo "== cleanup: restore #t, clear props, stop app =="
push_appfile /tmp/r2-on.gc "$SETF" || echo "  WARN restore failed"
echo "  restored flag: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"
adb shell setprop debug.opengoal.f1.warp '""' || true
adb shell setprop debug.opengoal.mouche.buzz '""' || true
adb shell am force-stop $PKG >/dev/null 2>&1 || true

echo "== log scan =="
for r in ON OFF; do
  f="$OUT/probe-$r-logcat.txt"
  echo "--- $r ($f) ---"
  echo "  recharged-hud loaded lines: $(grep -ac 'recharged-hud: loaded' "$f" 2>/dev/null || echo 0)"
  echo "  F1-WARP lines: $(grep -ac 'F1-WARP' "$f" 2>/dev/null || echo 0)"
  echo "  MOUCHE-BUZZ lines: $(grep -ac 'MOUCHE-BUZZ' "$f" 2>/dev/null || echo 0)"
  echo "  crash sigs (Fatal signal / signal 11|6|4): $(grep -acE 'Fatal signal|signal (11|6|4)' "$f" 2>/dev/null || echo 0)"
done
echo "[round2] DONE"
ls -la "$OUT"/probe-*-l2-*.png 2>/dev/null
