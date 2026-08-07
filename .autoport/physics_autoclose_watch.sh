#!/usr/bin/env bash
# physics_autoclose_watch.sh — Grecharged-secondary-motion.
#
# The phase is complete except for one physical act: the Redmi left the USB bus at 13:41:07
# ("usb 1-6: USB disconnect, device number 22") and every remaining gate needs it. Rather than
# depend on somebody noticing the moment it comes back, this waits for it and runs the close
# pass itself. A lockfile keeps it from ever racing a campaign started by hand — an overlapping
# device run is how a leg ends up with 4 windows instead of 20.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOG=.autoport/reports/Grecharged-secondary-motion/autoclose.log
LOCK=/tmp/physics_device_campaign.lock
say(){ echo "$(date -Is) $*" >> "$LOG"; }

# PRESENCE IS NOT READINESS. The first arming of this watcher fired at 15:11 the moment the serial
# reappeared and the close pass died on its first command: the phone had REBOOTED (uptime 363 s) and
# user 0 was RUNNING_LOCKED, so credential-encrypted storage was not mounted and
# /storage/emulated/0/OpenGOAL did not exist at all. Every step of the pass — restoring the owner's
# settings.ini, pushing the asset pack, reading the game's own settings — lives on that volume. So
# the trigger is the UNLOCK, not the enumeration; a locked phone is waited on, never worked on.
ready(){ # $1 = serial
  adb devices 2>/dev/null | grep -qE "^${1}[[:space:]]+device$" || return 1
  timeout 20 adb -s "$1" shell 'dumpsys user 2>/dev/null | grep -c RUNNING_UNLOCKED' 2>/dev/null \
    | tr -d '\r' | grep -qE '^[1-9]' || return 1
  timeout 20 adb -s "$1" shell 'ls -d /storage/emulated/0/OpenGOAL' >/dev/null 2>&1 || return 1
  return 0
}

say "watcher armed — waiting for eae4df44 / AREE026206000788 to be present AND unlocked"
for i in $(seq 1 2160); do            # 6 h at 10 s
  for S in eae4df44 AREE026206000788; do
    if ready "$S"; then
      if ! mkdir "$LOCK" 2>/dev/null; then
        say "device $S back but a campaign already holds $LOCK — standing down"; exit 0
      fi
      trap 'rmdir "$LOCK" 2>/dev/null' EXIT
      say "DEVICE BACK: $S — running physics_c8_close.sh"
      S="$S" bash .autoport/physics_c8_close.sh >> "$LOG" 2>&1
      say "close pass exit=$?"
      exit 0
    fi
  done
  # surface the states that are NOT 'device' — unauthorized after a reboot is the usual one,
  # and it needs a tap on the phone, not more waiting.
  # distinguish "absent" from "present but locked" — they need different human actions
  if adb devices 2>/dev/null | grep -qE "^eae4df44[[:space:]]+device$"; then
    [ $((i % 30)) -eq 1 ] && say "eae4df44 present but NOT READY (locked / storage not mounted) — needs the PIN"
  else
    OTH=$(adb devices 2>/dev/null | sed -n '2,$p' | grep -vE '^[[:space:]]*$' | grep -vE "device$")
    [ -n "$OTH" ] && say "present but not usable: $OTH"
  fi
  sleep 10
done
say "TIMEOUT — 6 h with no device"
