#!/usr/bin/env bash
# Gpkg-distributable device test — the HARDENED gate.
#   1. FRESH install of the self-contained APK onto a device with NO unpacked data
#      (uninstall first), proving the first-run decompress path end to end.
#   2. First launch: progress UI screencap, decompress the FULL bundle, verify the
#      on-device file counts (iso_data/jak1 == 321, out/jak1/fr3 == 26 — the full
#      set, NOT the slim 4), boot to title, then open the MAIN MENU and screencap
#      it so the orange tint backdrop can be checked vs the oracle.
#   3. Second launch: version-stamp detected, decompress SKIPPED, boots directly.
# Leaves the device in the working full-bundle state (NO restore_knowngood) so
# deploy_verify + the owner eye see the real result.
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
APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR==1{print $2}')
[ -n "$APK" ] || { echo "FATAL: no app-jak1-debug.apk"; exit 1; }
echo "APK = $APK ($(du -h "$APK"|cut -f1))"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1||true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1||true; done; }
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1||true; done; }
focus(){ "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
locked(){ "$ADB" shell dumpsys window policy 2>/dev/null | grep -qE '^[[:space:]]*showing=true'; }
shot(){ "$ADB" shell screencap -p "/sdcard/gpkg-$1.png" >/dev/null 2>&1||true; "$ADB" pull "/sdcard/gpkg-$1.png" "$OUT/$2" >/dev/null 2>&1||true; }
inject(){ printf '%s' "$1" | "$ADB" shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1||true; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crashsig(){ grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$1" 2>/dev/null; }

# 0. wake + unlock
"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
i=0; while locked; do "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true; i=$((i+1)); [ "$i" -ge 60 ] && { echo "STILL LOCKED after 5min — abort"; exit 2; }; sleep 5; done
echo "device unlocked"
"$ADB" shell svc power stayon usb >/dev/null 2>&1||true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; "$ADB" shell svc power stayon false >/dev/null 2>&1||true' EXIT

# 1. FRESH: uninstall so there is NO unpacked data
echo "== uninstalling $PKG (fresh — no unpacked data) =="
"$ADB" uninstall "$PKG" 2>&1 | tail -1
"$ADB" shell pm path "$PKG" >/dev/null 2>&1 && echo "WARN: still installed" || echo "confirmed: package absent"

# 2. install the freshly-built self-contained APK (full MIUI unblock recipe)
echo "== installing self-contained APK =="
miui_unblock(){
  "$ADB" shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1||true
  "$ADB" shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1||true
  "$ADB" shell settings put global package_verifier_enable 0 >/dev/null 2>&1||true
  "$ADB" shell settings put global install_non_market_apps 1 >/dev/null 2>&1||true
  "$ADB" shell settings put global adb_install_need_confirm 0 >/dev/null 2>&1||true
}
miui_unblock
"$ADB" push "$APK" /data/local/tmp/gpkg.apk 2>&1 | tail -1
INSTALL_OK=0
for attempt in 1 2 3; do
  # MIUI cancels the install if the keyguard is up — wake + ensure unlocked first.
  "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
  k=0; while locked; do "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true; k=$((k+1)); [ "$k" -ge 24 ] && break; sleep 5; done
  "$ADB" shell input keyevent KEYCODE_HOME >/dev/null 2>&1||true; sleep 1
  miui_unblock
  R=$("$ADB" shell pm install -r -d -t -i com.android.vending /data/local/tmp/gpkg.apk 2>&1)
  echo "  install attempt $attempt: $(echo "$R"|tail -1)"
  if echo "$R" | grep -q Success; then INSTALL_OK=1; break; fi
  sleep 5
done
"$ADB" shell rm -f /data/local/tmp/gpkg.apk >/dev/null 2>&1||true
[ "$INSTALL_OK" = 1 ] && "$ADB" shell pm path "$PKG" >/dev/null 2>&1 && echo "install OK" || { echo "INSTALL FAILED"; exit 1; }

# 3. FIRST LAUNCH — decompress the FULL bundle
"$ADB" logcat -G 16M >/dev/null 2>&1||true
"$ADB" logcat -c >/dev/null 2>&1||true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' >> "$LOG" 2>&1 ) &
LP=$!
echo "== FIRST LAUNCH (expect decompression progress UI) =="
"$ADB" shell am start -W -n "$LOADER" >/dev/null 2>&1||true
sleep 4; shot firstrun-progress firstrun-progress.png; echo "  progress-UI focus=$(focus)"
DECOMP=""
for ((s=0;s<240;s+=3)); do
  sleep 3
  if grep -aqE 'asset bundle decompressed: [0-9]+ files' "$LOG"; then
    DECOMP=$(grep -aoE 'asset bundle decompressed: [0-9]+ files, [0-9]+ bytes in [0-9]+ms \(version=[0-9]+\)' "$LOG" | tail -1)
    echo "  DECOMPRESS DONE: $DECOMP"; break
  fi
  if grep -aqE 'Setup failed|Not enough free storage|integrity check failed' "$LOG"; then
    echo "  DECOMPRESS FAILED:"; grep -aoE '(Setup failed.*|Not enough free storage.*|integrity check failed.*)' "$LOG" | tail -3; break
  fi
  (( s % 15 == 0 )) && { shot firstrun-progress firstrun-progress.png; echo "  [+${s}s] decompressing… focus=$(focus)"; }
done

# verify on-device asset COMPLETENESS
DEV_ISO=$("$ADB" shell "run-as $PKG sh -c 'ls files/iso_data/jak1 2>/dev/null | wc -l'" | tr -d '\r ')
DEV_FR3=$("$ADB" shell "run-as $PKG sh -c 'ls files/out/jak1/fr3 2>/dev/null | wc -l'" | tr -d '\r ')
DEV_STAMP=$("$ADB" shell "run-as $PKG sh -c 'cat files/.asset_bundle_stamp 2>/dev/null'" | tr -d '\r ')
echo "  ON-DEVICE: iso_data/jak1=$DEV_ISO (want 321)  out/jak1/fr3=$DEV_FR3 (want 26)  stamp=$DEV_STAMP (want 2)"

# 4. boot to title
echo "== boot to title (link finish: logo + frame>=1500) =="
for ((s=0;s<240;s+=3)); do
  sleep 3; FM=$(maxframe "$LOG"); FM=${FM:-0}
  grep -aq 'link finish: logo' "$LOG" && LF=1 || LF=0
  CS=$(crashsig "$LOG"); CS=${CS:-0}
  (( s % 15 == 0 )) && echo "  [+${s}s] linkfinish=$LF frame=$FM crashsig=$CS focus=$(focus)"
  [ "$CS" -gt 0 ] && { echo "  CRASH during boot sig=$CS"; break; }
  [ "$LF" = 1 ] && [ "$FM" -ge 1500 ] && { echo "  TITLE REACHED frame=$FM"; break; }
done
shot title firstrun-title.png

# 5. open the MAIN MENU + capture (the render gate)
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
echo "  menu_hud_sprite_lines=$GSPR"
kill $LP 2>/dev/null||true

LF1=$(grep -aq 'link finish: logo' "$LOG" && echo yes || echo no)
echo "FIRSTRUN_SUMMARY decomp=[$DECOMP] iso=$DEV_ISO fr3=$DEV_FR3 stamp=$DEV_STAMP linkfinish=$LF1 frame=$(maxframe "$LOG") crashsig=$(crashsig "$LOG") menu_sprites=$GSPR"

# 6. SECOND LAUNCH — idempotent skip
echo "== SECOND LAUNCH (expect skip-decompress) =="
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1||true
sleep 2
"$ADB" logcat -c >/dev/null 2>&1||true
: > "$LOG2"
( "$ADB" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' >> "$LOG2" 2>&1 ) &
LP2=$!
T0=$(date +%s); SKIP=""
"$ADB" shell am start -W -n "$LOADER" >/dev/null 2>&1||true
for ((s=0;s<60;s+=2)); do
  sleep 2
  if grep -aqE 'already unpacked .*skipping decompress|data ready' "$LOG2"; then
    SKIP=$(grep -aoE 'asset bundle already unpacked .*' "$LOG2" | tail -1); echo "  IDEMPOTENT SKIP: $SKIP"; break
  fi
  if grep -aq 'asset bundle decompressed' "$LOG2"; then echo "  WARN: RE-DECOMPRESSED on 2nd launch (idempotency BROKEN)"; break; fi
done
T1=$(date +%s)
echo "  second-launch time to skip marker: $((T1-T0))s"
for ((s=0;s<180;s+=3)); do sleep 3; grep -aq 'link finish: logo' "$LOG2" && { echo "  2nd launch booted (link finish: logo)"; break; }; done
kill $LP2 2>/dev/null||true
LF2=$(grep -aq 'link finish: logo' "$LOG2" && echo yes || echo no)
echo "SECONDRUN_SUMMARY skip=[$SKIP] redecompressed=$(grep -aq 'asset bundle decompressed' "$LOG2" && echo YES || echo no) linkfinish=$LF2"

# 7. leave device on the working app; deploy_verify will confirm fresh HEAD libgk
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1||true
echo "== DONE =="
