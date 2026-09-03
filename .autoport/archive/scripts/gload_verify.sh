#!/usr/bin/env bash
# Grecharged-loader-packfix — device close-gate on the OWNER's Honor.
#
# Proves, in one uninterrupted run on AREE026206000788:
#   1. the APK installs and LoaderActivity (the REAL launcher entry point — MainActivity
#      bypasses it and extracts nothing) unpacks both packs;
#   2. the 74 CGOs + the custom pack land in files/;
#   3. the process SURVIVES past the point where the 28-29/07 builds died (fn-ptr=0
#      SIGILL at the first (update *pc-settings*) frame, ~3 s in);
#   4. no crash record was written (files/gk_crash.txt absent == no fatal signal);
#   5. the MESH BROWSER row is REALLY ON SCREEN in RECHARGED SETTINGS.
#
# Row 23 of that page is MESH BROWSER and row 24 is Back, but several rows above it are
# conditionally hidden (flag-gated / recall-gated), so counting downs is fragile. We use
# the cursor WRAP instead: two UPs from row 0 land on row 23.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SER=AREE026206000788                     # never name this S: `local S=` shadowing has
PKG=org.opengoal.gk.jak1                 # silently broken adb -s in this tree before
ACT="$PKG/org.opengoal.gk.LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
APK=${1:-android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk}
OUT=${2:-.autoport/reports/Grecharged-loader-packfix/device}
mkdir -p "$OUT"
a(){ "$ADB" -s "$SER" "$@"; }
inject(){ printf '%s' "$1" | a shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
shot(){ a exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "   shot $1.png $(stat -c%s "$OUT/$1.png" 2>/dev/null) bytes"; }
LOG="$OUT/verify.txt"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }

say "===== Grecharged-loader-packfix device verify ====="
say "device : $(a shell getprop ro.product.model | tr -d '\r') / serial $SER"
say "apk    : $APK  ($(stat -c%s "$APK") bytes, sha256 $(sha256sum "$APK" | cut -c1-16))"
say "libgk  : $(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)"

say ""
say "-- 1. install + clear any previous crash record --"
a shell "am force-stop $PKG"
a install -r -d "$APK" 2>&1 | tail -2 | tee -a "$LOG"
a shell "run-as $PKG rm -f files/gk_crash.txt" >/dev/null 2>&1

say ""
say "-- 2. launch through LoaderActivity --"
a shell "am start -W -n $ACT" 2>&1 | grep -E "Status|TotalTime" | tee -a "$LOG"

say ""
say "-- 3. liveness + extraction (120 s) --"
ALIVE=0; DIED=0
for i in $(seq 1 120); do
  P=$(a shell "pidof $PKG" 2>/dev/null | tr -d '\r')
  if [ -n "$P" ]; then
    ALIVE=$i
    if [ $((i % 15)) -eq 0 ]; then
      ST=$(a shell "run-as $PKG sh -c 'echo cgo=\$(ls files/cgo/jak1 2>/dev/null|wc -l) customdirs=\$(ls files/custom/jak1 2>/dev/null|wc -l)'" 2>/dev/null | tr -d '\r')
      say "   t=${i}s pid=$P $ST"
    fi
  else
    [ $ALIVE -gt 0 ] && { DIED=$i; say "   !! DIED at t=${i}s"; break; }
  fi
  sleep 1
done
say "   last-alive=${ALIVE}s died=${DIED}"

say ""
say "-- 4. extraction result + crash record --"
say "$(a shell "run-as $PKG sh -c 'echo CGO_FILE_COUNT=\$(ls files/cgo/jak1 2>/dev/null|wc -l); echo CUSTOM_FR3=\$(ls files/custom/jak1/fr3 2>/dev/null|wc -l); echo CUSTOM_MESH_INDEX=\$(ls files/custom/jak1/mesh_index 2>/dev/null|wc -l); echo CUSTOM_KB=\$(du -sk files/custom/jak1 2>/dev/null|cut -f1)'" 2>/dev/null | tr -d '\r')"
CR=$(a shell "run-as $PKG cat files/gk_crash.txt" 2>/dev/null | tr -d '\r')
if [ -n "$CR" ]; then say "   GK-CRASH RECORD PRESENT (fatal signal):"; echo "$CR" | tee -a "$LOG"; else say "   gk_crash.txt ABSENT — no fatal signal reached the handler"; fi
say "   exit-info: $(a shell "dumpsys activity exit-info $PKG" 2>/dev/null | grep -m1 'reason=' | tr -d '\r')"

say ""
say "-- 5. MESH BROWSER row on screen --"
shot 00-boot
say "   start -> OPTIONS -> GRAPHIC OPTIONS -> RECHARGED SETTINGS"
tapb "start" 2.5
tapb "down" 0.7; tapb "down" 0.7; tapb "x" 2.0
tapb "down" 0.8; tapb "x" 2.0
# RECHARGED SETTINGS is android row index 8 of GRAPHIC OPTIONS (menu-tree.md §2 — the
# desktop-only Display mode / Display / Frame rate rows do not exist on Android, so the
# ambient-occlusion-era "7 downs" landed on MSAA instead).
for i in $(seq 1 8); do tapb "down" 0.55; done
shot 01-recharged-settings-row
tapb "x" 2.0
shot 02-recharged-settings-page
# MESH BROWSER is row 23 and Back is row 24, with several rows above conditionally
# hidden — reach it by cursor WRAP (two UPs from row 0) rather than counting downs.
say "   two UPs (wrap) -> row 24 Back, then row 23 MESH BROWSER"
tapb "up" 1.0; shot 03-row-back
tapb "up" 1.0; shot 04-MESH-BROWSER-row
say "   focus: $(a shell 'dumpsys window | grep -m1 mCurrentFocus' | tr -d '\r')"
say "   alive after menu nav: pid=$(a shell "pidof $PKG" | tr -d '\r')"
say ""
say "===== done; artifacts in $OUT ====="
