#!/usr/bin/env bash
# physics_c8_close.sh — Grecharged-secondary-motion cycle 8: everything that needs the phone,
# in one pass, in the only order that is correct.
#
# WHY THIS EXISTS. Attempt 3 died mid-leg when the Redmi dropped off the USB bus at 13:41:07
# (kernel: "usb 1-6: USB disconnect, device number 22") while the D-OFF leg was running. Two
# things followed from that and both are handled here rather than remembered:
#   * the leg had already pushed physics?=#f quality=1 and its cleanup could not run, so the
#     phone was left with PHYSICS OFF and the owner's settings.ini unrestored. Step 0 restores
#     the byte-exact backup before anything else touches the device.
#   * the report was never refilled, so it still quoted a run that no longer matched the build.
#     Steps 3-5 are the refill pipeline and they run in the same pass as the leg, never later.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"
OUT=.autoport/reports/Grecharged-secondary-motion
INI_BAK="$OUT/.settings.ini.owner-backup-phys"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
say(){ echo "[c8-close] $*"; }
die(){ echo "[c8-close FAIL] $*" >&2; exit 1; }

$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"

# ---- 0. the phone must not be left with the aborted leg's settings ---------------------------
if [ -f "$INI_BAK" ]; then
  CUR=$($ADB -s "$S" shell "grep -c 'physics? *= *#t' $PCS_DEV" 2>/dev/null | tr -d '\r')
  say "owner settings.ini on device before restore: physics?=#t lines = ${CUR:-unreadable}"
  $ADB -s "$S" push "$INI_BAK" "$PCS_DEV" >/dev/null 2>&1 \
    && say "owner settings.ini byte-restored from the backup taken at 13:32" \
    || die "could not restore the owner's settings.ini"
else
  say "WARNING: no settings backup on disk — skipping the restore"
fi

# ---- 1. install the cycle-8 build and prove it landed ----------------------------------------
say "=== deploy ==="
bash .autoport/physics_deploy_fresh.sh || die "deploy_fresh failed"

# ---- 2. the four-leg device proof -------------------------------------------------------------
say "=== device leg (D-MAX, D-OFF, D-RIDER, D-INTRO) ==="
bash .autoport/physics_device_leg.sh
LEGRC=$?
say "device leg exit=$LEGRC (its own gates; the report records what it measured either way)"

# ---- 3-5. the report is re-transcribed from THIS run, never left quoting the last one ---------
say "=== report refill + inserts ==="
python3 .autoport/physics_c7_refill.py || die "refill failed"
python3 .autoport/physics_c7_insert.py || die "c7 insert failed"
python3 .autoport/physics_c8_insert.py || die "c8 insert failed"

# ---- 6. the ground truth -----------------------------------------------------------------------
say "=== validator ==="
bash .autoport/validators/phase-Grecharged-secondary-motion.sh
exit $?
