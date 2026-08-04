#!/usr/bin/env bash
# Grecharged-hd-models3 — ROUND 3 validator (ANIM-RETARGET direction).
#
# INSTRUMENT-REPAIR NOTE (2026-08-03): the file committed by af8ba0da10 was a
# verbatim copy of the grass-overhang validator (it demanded 'RESULT: GRASS
# OVERHANG', droop/crossfade/far-LOD evidence) with only the report path changed
# — a supervisor authoring slip, unsatisfiable for an HD-models phase without
# writing a fictional report. Rewritten to gate the phase's ACTUAL mandate at
# full strictness: the DIRECTION FINALE 2026-08-02 (anim-retarget M1: the HD Jak
# companion must provably render on DEVICE and follow eichar's animation, with
# code-level objective numbers) + the 2026-08-03 handoff + the round-2 carnage
# guards (append-only bake integrity, enhanced-OFF recall discipline).
#
# PROOF DEVICE: the DIRECTION FINALE named the Redmi (eae4df44) but it is
# physically unplugged since 2026-08-03; the handoff designates the owner's
# Honor (AREE026206000788) as the current test device (precedent:
# Grecharged-loader-packfix). Redmi is preferred when present; the Honor is the
# configured fallback. NO other serial is accepted.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Ghdmodels3 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models3/report.txt
[ -f "$R" ] || fail "no report"

# RESULT line specific to THIS mandate (never the round-2 re-rig wording).
grep -qiE 'RESULT:.*HD ANIM-RETARGET' "$R" || fail "no RESULT: HD ANIM-RETARGET"

# M1 pipeline proof on DEVICE — the report must QUOTE the routed-logcat lines:
# companion spawn with the full HD skeleton, the appended merc geometry loaded,
# and the Merc2 submission diagnostic with the model FOUND.
grep -qE '\[JAK-HD\] spawned skel-bones=76' "$R" || fail "companion spawn logcat line (skel-bones=76) missing"
grep -qE 'merc-load .*jak-hd-lod0' "$R" || fail "jak-hd-lod0 merc-load logcat line missing"
grep -qE 'jak-hd-render.*SUBMITTED.*found=1' "$R" || fail "Merc2 SUBMITTED found=1 logcat line missing"

# Objective anim-follow (code-level, not eyeball): retargeted HD bone world
# positions tracking the driver across frames, and unmapped joints at rest.
grep -qiE 'bone.*(follow|track|delta)' "$R" || fail "objective bone-follow evidence missing"
grep -qiE 'unmapped.*(rest|bind)' "$R" || fail "unmapped-joints-at-rest statement missing"

# Round-2 carnage guards: append-only bake with integrity PASS, and the level
# geometry outside the swapped characters untouched.
grep -qiE 'append.?only' "$R" || fail "append-only bake statement missing"
grep -qiE 'integrity.*(pass|identical)' "$R" || fail "level-bake integrity gate missing"

# Toggle semantics + recall discipline: OFF == stock, and no run may leave
# ENHANCED ON on the device afterwards.
grep -qiE 'off.*(stock|identical|byte)|stock.*off' "$R" || fail "OFF==stock statement missing"
grep -qiE 'enhanced.*(off after|left off|restored|force-stop)' "$R" || fail "enhanced-OFF/force-stop after-run discipline missing"

# Device evidence: the game foregrounded on the proof device.
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 foreground evidence missing"

# Visual evidence for the owner (he is the aesthetic judge): captures shipped.
FRAMES=$(find .autoport/reports/Grecharged-hd-models3 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' \) 2>/dev/null | wc -l)
[ "$FRAMES" -ge 2 ] || fail "need capture evidence (>=2 images/videos, found $FRAMES)"

# deploy_verify on the configured proof device (Redmi preferred, Honor fallback).
DEVLIST=$(adb devices 2>/dev/null)
DEV=""
if [[ "$DEVLIST" == *$'\n'"eae4df44"* ]]; then DEV=eae4df44
elif [[ "$DEVLIST" == *$'\n'"AREE026206000788"* ]]; then DEV=AREE026206000788
fi
[ -n "$DEV" ] || fail "no configured proof device connected (eae4df44 / AREE026206000788)"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"

GOLD=$(git status --porcelain .autoport/gold 2>/dev/null)
[ -z "$GOLD" ] || fail "gold not pristine"
echo "[Ghdmodels3 PASS]"
