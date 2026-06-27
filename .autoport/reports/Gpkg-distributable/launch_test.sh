#!/usr/bin/env bash
# Gpkg-distributable LAUNCH test (app already freshly installed, no data):
# first-run decompress of the FULL bundle + completeness counts + boot +
# MAIN MENU screencap, then second-launch idempotency. No restore_knowngood.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="/home/emeric/Android/platform-tools/adb"
PKG="org.opengoal.gk.jak1"
LOADER="$PKG/.LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=".autoport/reports/Gpkg-distributable"
LOG="$OUT/device-firstrun.log"
LOG2="$OUT/device-secondrun.log"
mkdir -p "$OUT"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1||true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1||true; done; }
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1||true; done; }
focus(){ "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
locked(){ "$ADB" shell dumpsys window policy 2>/dev/null | grep -qE '^[[:space:]]*showing=true'; }
shot(){ "$ADB" shell screencap -p "/sdcard/gpkg-$1.png" >/dev/null 2>&1||true; "$ADB" pull "/sdcard/gpkg-$1.png" "$OUT/$2" >/dev/null 2>&1||true; }
inject(){ printf '%s' "$1" | "$ADB" shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1||true; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crashsig(){ grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$1" 2>/dev/null; }

"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
i=0; while locked; do "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true; i=$((i+1)); [ "$i" -ge 60 ] && { echo "STILL LOCKED"; exit 2; }; sleep 5; done
echo "device unlocked"
"$ADB" shell svc power stayon usb >/dev/null 2>&1||true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; "$ADB" shell svc power stayon false >/dev/null 2>&1||true' EXIT

"$ADB" shell pm path "$PKG" >/dev/null 2>&1 || { echo "FATAL: $PKG not installed"; exit 1; }
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1||true

# 1. FIRST LAUNCH — decompress the FULL bundle
"$ADB" logcat -G 16M >/dev/null 2>&1||true
"$ADB" logcat -c >/dev/null 2>&1||true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' >> "$LOG" 2>&1 ) &
LP=$!
echo "== FIRST LAUNCH (decompression progress UI) =="
"$ADB" shell am start -W -n "$LOADER" >/dev/null 2>&1||true
sleep 4; shot firstrun-progress firstrun-progress.png; echo "  progress-UI focus=$(focus)"
DECOMP=""
for ((s=0;s<300;s+=3)); do
  sleep 3
  if grep -aqE 'asset bundle decompressed: [0-9]+ files' "$LOG"; then
    DECOMP=$(grep -aoE 'asset bundle decompressed: [0-9]+ files, [0-9]+ bytes in [0-9]+ms \(version=[0-9]+\)' "$LOG" | tail -1)
    echo "  DECOMPRESS DONE: $DECOMP"; break
  fi
  if grep -aqE 'Setup failed|Not enough free storage|integrity check failed' "$LOG"; then
    echo "  DECOMPRESS FAILED:"; grep -aoE '(Setup failed.*|Not enough free storage.*|integrity check failed.*)' "$LOG" | tail -3; break
  fi
  if (( s % 12 == 0 )); then shot firstrun-progress firstrun-progress.png; echo "  [+${s}s] decompressing… focus=$(focus)"; fi
done

DEV_ISO=$("$ADB" shell "run-as $PKG sh -c 'ls files/iso_data/jak1 2>/dev/null | wc -l'" | tr -d '\r ')
DEV_FR3=$("$ADB" shell "run-as $PKG sh -c 'ls files/out/jak1/fr3 2>/dev/null | wc -l'" | tr -d '\r ')
DEV_STAMP=$("$ADB" shell "run-as $PKG sh -c 'cat files/.asset_bundle_stamp 2>/dev/null'" | tr -d '\r ')
echo "  ON-DEVICE: iso_data/jak1=$DEV_ISO (want 321)  out/jak1/fr3=$DEV_FR3 (want 26)  stamp=$DEV_STAMP (want 2)"

echo "== boot to title =="
for ((s=0;s<240;s+=3)); do
  sleep 3; FM=$(maxframe "$LOG"); FM=${FM:-0}
  grep -aq 'link finish: logo' "$LOG" && LF=1 || LF=0
  CS=$(crashsig "$LOG"); CS=${CS:-0}
  (( s % 15 == 0 )) && echo "  [+${s}s] linkfinish=$LF frame=$FM crashsig=$CS focus=$(focus)"
  [ "$CS" -gt 0 ] && { echo "  CRASH during boot sig=$CS"; break; }
  [ "$LF" = 1 ] && [ "$FM" -ge 1500 ] && { echo "  TITLE REACHED frame=$FM"; break; }
done
shot title firstrun-title.png

echo "== open MAIN MENU (inject start) + screencap =="
inject "start"; sleep 2; inject ""; sleep 2
shot menu1 device-menu-firstrun.png; echo "  menu focus=$(focus)"
for try in 1 2 3; do
  GSPR=$(grep -acE 'GK-SPR3 mode=2' "$LOG" 2>/dev/null); GSPR=${GSPR:-0}
  [ "$GSPR" -gt 0 ] && break
  echo "  (no menu HUD sprites yet — re-press start, try $try)"; inject "start"; sleep 1.5; inject ""; sleep 1.5
done
inject "down"; sleep 0.5; inject "up"; sleep 0.5; inject ""; sleep 1
shot menu2 device-menu-firstrun-2.png
GSPR=$(grep -acE 'GK-SPR3 mode=2' "$LOG" 2>/dev/null); GSPR=${GSPR:-0}
kill $LP 2>/dev/null||true
LF1=$(grep -aq 'link finish: logo' "$LOG" && echo yes || echo no)
echo "FIRSTRUN_SUMMARY decomp=[$DECOMP] iso=$DEV_ISO fr3=$DEV_FR3 stamp=$DEV_STAMP linkfinish=$LF1 frame=$(maxframe "$LOG") crashsig=$(crashsig "$LOG") menu_sprites=$GSPR"

# 2. SECOND LAUNCH — idempotent skip
echo "== SECOND LAUNCH (expect skip-decompress) =="
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 2
"$ADB" logcat -c >/dev/null 2>&1||true
: > "$LOG2"
( "$ADB" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' >> "$LOG2" 2>&1 ) &
LP2=$!
T0=$(date +%s); SKIP=""
"$ADB" shell am start -W -n "$LOADER" >/dev/null 2>&1||true
for ((s=0;s<60;s+=2)); do
  sleep 2
  if grep -aqE 'already unpacked .*skipping decompress|data ready' "$LOG2"; then SKIP=$(grep -aoE 'asset bundle already unpacked .*' "$LOG2" | tail -1); echo "  IDEMPOTENT SKIP: $SKIP"; break; fi
  grep -aq 'asset bundle decompressed' "$LOG2" && { echo "  WARN: RE-DECOMPRESSED on 2nd launch"; break; }
done
T1=$(date +%s)
echo "  second-launch time to skip marker: $((T1-T0))s"
for ((s=0;s<180;s+=3)); do sleep 3; grep -aq 'link finish: logo' "$LOG2" && { echo "  2nd launch booted (link finish: logo)"; break; }; done
kill $LP2 2>/dev/null||true
LF2=$(grep -aq 'link finish: logo' "$LOG2" && echo yes || echo no)
echo "SECONDRUN_SUMMARY skip=[$SKIP] redecompressed=$(grep -aq 'asset bundle decompressed' "$LOG2" && echo YES || echo no) linkfinish=$LF2"
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1||true
echo "== DONE =="
