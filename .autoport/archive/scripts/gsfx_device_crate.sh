#!/usr/bin/env bash
# gsfx_device_crate.sh — capture the REAL arm64 crate-break + buzzer-pickup SFX
# commands on device. Reuses the gmouche3 warp+teleport+spin path: warp to Geyser
# Rock, teleport Jak onto each fly-crate, spin-attack to break it (-> wcrate-break
# etc.), buzzer flies out + is collected (-> buzzer-pickup). The deployed libgk has
# the SFX-PROBE; lg::warn lands on tag opengoal-gk which logcat captures.
#
# Requires the SFX-PROBE libgk already installed (probe build) + known-good CGOs.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"; export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJ="/data/data/$PKG/files/cpad_inject"
OUTDIR=.autoport/reports/Gsfx-actions; mkdir -p "$OUTDIR"
LOG="$OUTDIR/device-crate-logcat.log"; OUT="$OUTDIR/device-crate-sfxprobe.txt"
SPIN_S="${SPIN_S:-1.5}"; COLLECT_S="${COLLECT_S:-2.6}"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inject(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJ'" >/dev/null 2>&1 || true; }

device_require_attached; device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked

echo "== set probe + warp props =="
A shell setprop debug.opengoal.sfx.probe 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp 1   >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele 1      >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele.idx -1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele.gen 0  >/dev/null 2>&1 || true
echo "  sfx.probe=$(A shell getprop debug.opengoal.sfx.probe | tr -d '\r')"

A shell am force-stop "$PKG" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V opengoal-gk-full:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LCP=$!
cleanup(){ kill "$LCP" 2>/dev/null||true; inject ""; A shell setprop debug.opengoal.tele 0 >/dev/null 2>&1||true; device_stayon_restore 2>/dev/null||true; }
trap cleanup EXIT

A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  warming to title (link finish: logo, up to 120s)..."
for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done
echo "  waiting for warp/spawn (F1-SPAWN, up to 90s)..."
for i in $(seq 1 90); do grep -qa "F1-SPAWN" "$LOG" && { echo "  spawn ~${i}s"; break; }; sleep 1; done
echo "  waiting for training (Geyser Rock) load (up to 8min)..."
for ((i=1;i<=96;i++)); do
  sleep 5
  grep -qaE "Adding level training|link finish: training|TELE-ARM|F1-SPAWN" "$LOG" && { echo "   training active ~$((i*5))s"; break; }
  grep -qaE "Fatal signal|signal (11|6|4) \(SIG" "$LOG" && { echo "   crash before training"; break; }
done
sleep 8

GEN=0
echo "== break crates 0..6 (spin attack) =="
for ((i=0;i<=6;i++)); do
  GEN=$((GEN+1))
  A shell setprop debug.opengoal.tele.idx "$i"  >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.tele.gen "$GEN" >/dev/null 2>&1 || true
  for w in $(seq 1 20); do grep -qaE "TELE-JAK idx=$i " "$LOG" && break; sleep 0.25; done
  sleep 0.4
  inject "circle"; sleep "$SPIN_S"; inject ""
  sleep "$COLLECT_S"
  echo "  crate$i spin done"
done
sleep 3

kill "$LCP" 2>/dev/null || true
FOCUS=$(A shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
grep -a "SFX-PROBE" "$LOG" > "$OUT" 2>/dev/null || true
echo "[gsfx-crate] focus: $FOCUS"
echo "[gsfx-crate] total SFX-PROBE play lines: $(grep -ac 'SFX-PROBE] play' "$OUT" 2>/dev/null || echo 0)"
echo "== crate/orb/cell SFX on device (name -> idx -> handle) =="
for nm in wcrate-break icrate-break scrate-break dcrate-break crate-jump buzzer-pickup cell-prize money-pickup; do
  echo "--- $nm ---"
  grep -a -A2 "play name='${nm}" "$OUT" 2>/dev/null | grep -aE "play name='${nm}|lookup idx=|newplay" | head -6
done
echo "== ALL distinct device names during crate drive (name hex idx not shown) =="
grep -a "SFX-PROBE] play" "$OUT" 2>/dev/null | sed -E "s/.*play name=('[^']*' hex=[0-9a-f]+).*/\1/" | sort | uniq -c | sort -rn | head -40
echo "[gsfx-crate] wrote $OUT and $LOG"
