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
# GUARD, learned the hard way on 2026-08-07: the refill reads device_leg.log and rewrites every
# sentence it can match. Run against a PARTIAL leg log it does not fail — it cheerfully writes
# "n/a (not measured)" over numbers that were correct, and it re-transcribes the aborted run's
# restdevA into the headline, which is the value the ratchet reads. The aborted attempt-3 log
# (D-MAX + D-OFF only, the phone left the USB bus during D-OFF) does exactly that. So the refill
# only runs on a log that carries all four legs.
for LEG in D-MAX D-OFF D-RIDER D-INTRO; do
  grep -q "=== LEG $LEG:" "$OUT/device_leg.log" \
    || die "device_leg.log has no $LEG section — refusing to refill the report from a partial run (it would overwrite good numbers with 'n/a')"
done
say "leg log carries all four legs — safe to refill"
cp "$OUT/report.txt" "$OUT/report.pre-refill.bak"
# RE-RUNNABILITY. Both insert scripts are idempotent BY MARKER: once a block is in the report they
# skip it, numbers and all. That is right for a single pass and wrong for a second one — a block
# inserted from an earlier run's logcat would survive a fresh leg and keep quoting the run that is
# no longer on the phone, which is the exact defect this phase has lost cycles to. So every pass
# starts from the pristine cycle-7 baseline: the refill then updates its sentences from THIS run's
# leg log, and the inserts regenerate their blocks from THIS run's logcats.
if [ -f "$OUT/report.baseline-c8.txt" ]; then
  cp "$OUT/report.baseline-c8.txt" "$OUT/report.txt"
  say "report reset to the pristine baseline — every number below comes from this run"
else
  say "WARNING: no baseline snapshot; inserted blocks may carry numbers from an earlier run"
fi
say "=== report refill + inserts ==="
python3 .autoport/physics_c7_refill.py || die "refill failed"
python3 .autoport/physics_c7_insert.py || die "c7 insert failed"
python3 .autoport/physics_c8_insert.py || die "c8 insert failed"

# ---- 6. the ground truth -----------------------------------------------------------------------
say "=== validator ==="
bash .autoport/validators/phase-Grecharged-secondary-motion.sh
exit $?
