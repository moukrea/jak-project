#!/usr/bin/env bash
# Gd1-cutscene-clock AFTER measurement (arm64 eae4df44).
# Deterministically measures the IOP/overlord VBlank fire rate (Hz) vs the render
# rate (Hz) on the FIXED build, at the heavy title-attract village flythrough
# (no input) and, best-effort, the new-game cutscene. Uses the pre-existing
# A42-STRCLK (gFrameNum, srpc.cpp) + A35-RENDER (android_gfx.cpp) log lines — NO
# temporary instrumentation. Exits 2 immediately if the device is PIN-locked.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=".autoport/reports/Gd1-cutscene-clock"
GREP='A42-STRCLK|A35-RENDER frame=|Gd1-VBLANK|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:'
mkdir -p "$OUT"

device_locked() { "$ADB" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
inject() { printf '%s' "$1" | "$ADB" shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }
read_focus() { "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }

"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if device_locked; then echo "DEVICE_LOCKED"; exit 2; fi
echo "== device unlocked — running AFTER measurement =="
device_stayon_on || true

# ---- install fixed build + verify it is the one running ----
device_install_and_launch "$PKG" "$ACT" "$APK"
echo "== deploy_verify =="
if bash .autoport/lib/deploy_verify.sh eae4df44; then echo "DEPLOY_VERIFY=0"; else echo "DEPLOY_VERIFY=NONZERO"; fi

capture() {  # $1=outfile  $2=seconds
  "$ADB" logcat -G 64M >/dev/null 2>&1 || true
  "$ADB" logcat -c >/dev/null 2>&1 || true
  : > "$1"
  ( "$ADB" logcat -v threadtime GK_STDOUT:I opengoal-gk:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE "$GREP" >> "$1" ) &
  local cap=$!
  sleep "$2"
  pkill -f "logcat -v threadtime GK_STDOUT" >/dev/null 2>&1 || true
  kill "$cap" >/dev/null 2>&1 || true
}

# ---- BEAT 1: heavy village flythrough (attract, no input) ----
echo "== flythrough capture (no input, 135s) =="
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
sleep 8
capture "$OUT/after-flythrough.log" 135

# ---- BEAT 2: new-game cutscene (best-effort input drive) ----
if [ "${CUTSCENE:-1}" = "1" ]; then
echo "== cutscene reach (best-effort) =="
"$ADB" logcat -G 64M >/dev/null 2>&1 || true; "$ADB" logcat -c >/dev/null 2>&1 || true
: > "$OUT/after-cutscene.log"
( "$ADB" logcat -v threadtime GK_STDOUT:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$OUT/after-cutscene.log" ) &
CCAP=$!
clear_inject; sleep 2
inject "start"; sleep 1.2; clear_inject; sleep 4
inject "down"; sleep .4; clear_inject; sleep 1.5
inject "down"; sleep .4; clear_inject; sleep 1.5
inject "up";   sleep .4; clear_inject; sleep 1
inject "up";   sleep .4; clear_inject; sleep 1.5
inject "x";    sleep .6; clear_inject; sleep 3
inject "down"; sleep .4; clear_inject; sleep 1
inject "down"; sleep .4; clear_inject; sleep 1
inject "down"; sleep .4; clear_inject; sleep 1
inject "down"; sleep .4; clear_inject; sleep 1
inject "x";    sleep .6; clear_inject; sleep 4
# watch up to ~10 min for the heavy cutscene (tris>400000) then grab 70s of it
for i in $(seq 1 200); do
  sleep 3
  HV=$(grep -aoE 'tris=[0-9]+' "$OUT/after-cutscene.log" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
  CS=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$OUT/after-cutscene.log" 2>/dev/null || echo 0)
  [ "${CS:-0}" -gt 0 ] && { echo "  cutscene crash sig=$CS — stop"; break; }
  if [ "${HV:-0}" -ge 400000 ]; then echo "  heavy cutscene reached (tris=$HV) — sampling 70s"; sleep 70; break; fi
done
pkill -f "logcat -v threadtime GK_STDOUT" >/dev/null 2>&1 || true
kill "$CCAP" >/dev/null 2>&1 || true
fi  # CUTSCENE

ENDFOC=$(read_focus)
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true

# ---- compute Hz ----
hz_report() {  # $1=log $2=label
  local f="$1"
  [ -s "$f" ] || { echo "  [$2] (no log)"; return; }
  echo "  --- $2 ($f) ---"
  echo "  A42-STRCLK vblank samples + per-pair Hz (=300/dt):"
  grep -aE 'A42-STRCLK' "$f" | awk '
    {split($2,a,":"); t=a[1]*3600+a[2]*60+a[3];
     for(i=1;i<=NF;i++) if($i ~ /vblank=/){split($i,b,"="); v=b[2]}
     if(pt!=""){dt=t-pt; if(dt>0) printf "    vblank=%s t=%s  +%dvbl/%.3fs = %.2f Hz\n",v,$2,v-pv,dt,(v-pv)/dt}
     pt=t; pv=v}'
  echo "  A35-RENDER render Hz over heavy window (tris>400000):"
  grep -aE 'A35-RENDER frame=' "$f" | awk '
    {split($2,a,":"); t=a[1]*3600+a[2]*60+a[3];
     for(i=1;i<=NF;i++){if($i ~ /frame=/){split($i,b,"="); fr=b[2]} if($i ~ /tris=/){split($i,c,"="); tr=c[2]}}
     if(tr>400000){if(ft==""){ft=t; ff=fr} lt=t; lf=fr; if(mintr==""||tr<mintr)mintr=tr; if(tr>maxtr)maxtr=tr}}
    END{if(lt>ft) printf "    frame %d->%d over %.3fs = %.2f fps (tris %d..%d)\n",ff,lf,lt-ft,(lf-ff)/(lt-ft),mintr,maxtr; else print "    (no sustained heavy window)"}'
  local cs; cs=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$f" 2>/dev/null || echo 0)
  echo "  crash_sigs=$cs"
}
echo "============ Gd1 AFTER RESULTS ============"
grep -aqE 'Gd1-VBLANK' "$OUT/after-flythrough.log" "$OUT/after-cutscene.log" && echo "Gd1-VBLANK pacer line: PRESENT" || echo "Gd1-VBLANK pacer line: MISSING"
hz_report "$OUT/after-flythrough.log" "FLYTHROUGH (attract)"
hz_report "$OUT/after-cutscene.log" "CUTSCENE (new game)"
echo "mCurrentFocus_at_end: $ENDFOC"
echo "==========================================="
