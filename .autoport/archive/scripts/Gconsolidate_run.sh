#!/usr/bin/env bash
# Gconsolidate_run.sh — drive the CONSOLIDATED current-HEAD build (all fixes) on the
# device and capture the deterministic per-fix signals in ONE routed logcat.
# Based on the proven Gd1_run.sh title->NEW GAME->cinematic->gameplay driver.
#
# Env:
#   RUN_NAME    output base name (default consolidated)
#   CENSUS      1 = arm debug.opengoal.gd3.census (GD3-MERC visible= for Jak); 0 = off (default 0)
#   WATCH_MIN   max watch minutes (default 22)
#   BREAK_FRAME stop once A35-RENDER frame >= this (default 11000)
#   TITLE_HOLD  extra seconds to hold at title before NEW GAME (default 0)
#
# Outputs under .autoport/reports/Gconsolidate/:
#   ${RUN_NAME}-routed-logcat.log   (A35-RENDER frame + A42-STRCLK + A37-MIPS2C + GD3-MERC + crash sigs)
#   ${RUN_NAME}-foreground.txt      (mCurrentFocus at end)
# Does NOT restore known-good (this phase LEAVES the consolidated build on the device).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
RUN_NAME="${RUN_NAME:-consolidated}"
CENSUS="${CENSUS:-0}"
WATCH_MIN="${WATCH_MIN:-22}"; BREAK_FRAME="${BREAK_FRAME:-11000}"; TITLE_HOLD="${TITLE_HOLD:-0}"
OUT=".autoport/reports/Gconsolidate"; mkdir -p "$OUT"
LOG="$OUT/${RUN_NAME}-routed-logcat.log"
FG="$OUT/${RUN_NAME}-foreground.txt"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject(){ inject ""; }
read_focus(){ adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
cur_frame(){ grep -a 'A35-RENDER frame=' "$LOG" 2>/dev/null | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1; }
is_fg(){ case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }

echo "== Gconsolidate run '$RUN_NAME' (census=$CENSUS watch=${WATCH_MIN}min break>=${BREAK_FRAME}) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LCP:-0} 2>/dev/null; adb shell setprop debug.opengoal.gd3.census 0 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

adb shell am force-stop "$PKG" 2>/dev/null || true
if [ "$CENSUS" = "1" ]; then adb shell setprop debug.opengoal.gd3.census 1 2>/dev/null || true; else adb shell setprop debug.opengoal.gd3.census 0 2>/dev/null || true; fi
echo "  gd3.census=$(adb shell getprop debug.opengoal.gd3.census | tr -d '\r')"
clear_inject
adb logcat -G 64M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
# SINGLE filtered logcat reader (proven minimal footprint). Union of all per-fix markers.
( adb logcat -v threadtime \
    | grep --line-buffered -aE 'A35-RENDER frame=|A42-STRCLK|A37-MIPS2C|GD3-MERC|Mode3D|3d_tris|3d_sprites|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:|has died' \
    > "$LOG" ) &
LCP=$!

echo "  launch $PKG/$ACT"; adb shell am start -W -n "$PKG/$ACT" >/tmp/gcons-amstart.out 2>&1 || true
echo "== warmup (title attract: sun/particles + A37/A42 boot markers) =="; sleep 40
if [ "$TITLE_HOLD" -gt 0 ]; then echo "== title hold ${TITLE_HOLD}s =="; sleep "$TITLE_HOLD"; fi
echo "== START (progress menu) =="; inject "start"; sleep 1.2; clear_inject; sleep 4
echo "== nav to NEW GAME =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
echo "== X (NEW GAME) =="; inject "x"; sleep 0.6; clear_inject; sleep 3
echo "== CONTINUE WITHOUT SAVING =="
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x";    sleep 0.6; clear_inject; sleep 4

echo "== watch (poll 3s) =="
LASTFOC=""; GONE=0; CRASHED=""
ITERS=$(( WATCH_MIN * 60 / 3 ))
for ((i=1;i<=ITERS;i++)); do
  sleep 3
  FM=$(cur_frame); FM=${FM:-0}
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  FG_OK=0; is_fg && FG_OK=1; LASTFOC=$(read_focus)
  if (( i % 5 == 0 )); then
    VIS=$(grep -a 'GD3-MERC' "$LOG" 2>/dev/null | grep -aoE 'visible=[0-9]+' | tail -1)
    STR=$(grep -a 'A42-STRCLK vblank=' "$LOG" 2>/dev/null | tail -1 | grep -oE 'vblank=[0-9]+')
    echo "   [${i}/${ITERS}] render=${FM} ${VIS:-} ${STR:-} fg=${FG_OK} pid='${PID:-gone}'"
  fi
  CR=$(grep -acE "GK-DIAG sig=(4|6|11)|Fatal signal (11|6|4)|signal (4|6|11) \(SIG" "$LOG" 2>/dev/null || true)
  if [ "${CR:-0}" -ge 1 ]; then echo "   >>> CRASH SIGNATURE"; CRASHED="crash"; sleep 2; break; fi
  if [ -z "$PID" ] && [ "$FG_OK" = "0" ]; then GONE=$((GONE+1)); else GONE=0; fi
  if [ "$GONE" -ge 4 ]; then echo "   >>> app GONE x4"; CRASHED="procgone"; break; fi
  if [ "${FM:-0}" -ge "$BREAK_FRAME" ]; then echo "   >>> reached BREAK_FRAME $FM"; break; fi
done

sleep 1; ENDFOC=$(read_focus); [ -z "$ENDFOC" ] && ENDFOC="$LASTFOC"
ENDPID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
{ echo "# Gconsolidate run '$RUN_NAME' end ($(date -Is))"; echo "mCurrentFocus_at_end: $ENDFOC"; echo "app_pid_at_end: ${ENDPID:-gone}"; echo "crashed: ${CRASHED:-no}"; echo "highest_render_frame: $(cur_frame)"; } > "$FG"

echo "== teardown =="
kill ${LCP:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell setprop debug.opengoal.gd3.census 0 2>/dev/null || true
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== scoreboard ($RUN_NAME) =="
echo "  highest render   : $(cur_frame)"
echo "  A37 sp-proc-3d   : $(grep -a 'A37-MIPS2C' "$LOG" 2>/dev/null | grep -i 'sp-process-block-3d' | head -2)"
echo "  A42-STRCLK lines : $(grep -ac 'A42-STRCLK vblank=' "$LOG" 2>/dev/null || echo 0)"
echo "  GD3-MERC visible : $(grep -a 'GD3-MERC' "$LOG" 2>/dev/null | grep -aoE 'visible=[0-9]+' | sort -t= -k2 -n | tail -1)"
echo "  3D sprite/tris   : $(grep -aoE '3d_(sprites|tris)=[0-9]+' "$LOG" 2>/dev/null | sort -u | tr '\n' ' ')"
echo "  crash sigs       : $(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (4|6|11) \(SIG|backtrace:' "$LOG" 2>/dev/null || echo 0)"
echo "  foreground end   : $ENDFOC  pid=${ENDPID:-gone}  crashed=${CRASHED:-no}"
echo "  routed-logcat    : $LOG"
