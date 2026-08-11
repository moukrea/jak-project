#!/usr/bin/env bash
# keira_room_device.sh — LA MEME SALLE DE TEST, SUR LE REDMI eae4df44.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean.
# x86 ne prouve pas arm64 : ce script rejoue la course de .autoport/keira_room_x86.sh sur le
# device, sans rien cliquer (prop debug.opengoal.phys.room), et ramene la trace. Il ne juge RIEN —
# c'est .autoport/physics_room_table.py qui en fait un tableau, et lui seul a le droit de refuser
# une ligne que la trace ne soutient pas.
#
# Prealable : APK installe + jeu de CGO arm64 coherent pousse + physics_chains.txt pousse
# (.autoport/physics_deploy_fresh.sh s'en charge et le prouve).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-device.log"
mkdir -p "$OUT"
say(){ echo "$*"; }
die(){ echo "[room-device FAIL] $*"; exit 1; }

$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S absent"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
# le trap Honor/MIUI : dumpsys trust liste plusieurs users, seul '(current)' compte
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
  die "device PIN-LOCKED — attendre l'owner"
fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s "$S" shell setprop debug.opengoal.phys.room 1 || die "setprop failed"
$ADB -s "$S" shell setprop debug.opengoal.phys.room.delay "${ROOM_DELAY:-900}" >/dev/null 2>&1 || true
say "prop debug.opengoal.phys.room = $($ADB -s "$S" shell getprop debug.opengoal.phys.room)"

$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
# PID exact du sous-shell de capture : jamais de kill par motif (DIRECTIVES 8)
$ADB -s "$S" logcat -v time >> "$LOG" 2>&1 &
CAP=$!
say "logcat capture pid=$CAP -> $LOG"

$ADB -s "$S" shell am start -n "$PKG/$ACT" >/dev/null 2>&1 || die "am start failed"
say "lance $PKG/$ACT"

DEADLINE="${ROOM_TIMEOUT:-1800}"
ok=0
for i in $(seq 1 "$DEADLINE"); do
  if grep -aq 'PHYSEND' "$LOG" 2>/dev/null; then ok=1; say "PHYSEND vu apres ${i}s"; break; fi
  if grep -aq 'PHYSFAIL reason=' "$LOG" 2>/dev/null; then say "PHYSFAIL vu"; break; fi
  sleep 1
done

kill "$CAP" 2>/dev/null
$ADB -s "$S" shell setprop debug.opengoal.phys.room 0 >/dev/null 2>&1 || true
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
say "app arretee, prop remise a 0"

# la trace GOAL arrive sous le tag opengoal-gk : on la deroute vers un fichier au meme format que
# la course x86, pour que le MEME script en fasse le tableau (un seul instrument, pas deux).
sed -e 's/^.*opengoal-gk: //' -e 's/^.*GK_STDOUT: //' "$LOG" > "$OUT/keira-room-device.trace"
say "---- marqueurs ----"
for m in PHYSROOM-START PHYSFAIL PHYSSUBJECT PHYSANIM PHYSCHAIN PHYSROW PHYSIDLE PHYSAUTH PHYSNOPLAY PHYSCOUNTS PHYSPC PHYSLIM PHYSEND 'HD-PHYS'; do
  printf '%-16s %s\n' "$m" "$(grep -ac "$m" "$OUT/keira-room-device.trace" 2>/dev/null || echo 0)"
done
grep -aE 'signal|SIGSEGV|SIGILL|FATAL|abort' "$LOG" | head -5
[ "$ok" = 1 ] || die "PHYSEND jamais atteint"
say "OK"
