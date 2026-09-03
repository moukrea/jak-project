#!/usr/bin/env bash
# Grecharged-hd-models2 — ROUND 2 validator.
# Round 1 failed the owner play-test: WRONG source (jak2 in-game look, not the
# intro/first-cutscene jak1-look set), GARBLED weight-borrow retarget, only 2/4
# visibly swapped. This validator gates the round-2 mandate:
#   correct intro-cutscene source (proven vs the jak2 intro), name-based joint
#   remap (no garbled geometry shipped), all-4-or-honest-partial, and
#   verification through the OWNER'S REAL INSTALL FLOW (slim APK + external
#   archive via scripts/package_game_assets.sh — NOT adb-pushed assets).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Ghdmodels2 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models2/report.txt
[ -f "$R" ] || fail "no report"

grep -qiE 'RESULT:.*HD MODELS [0-9]/4' "$R" || fail "no RESULT: HD MODELS <landed>/4"
for c in jak daxter samos keira; do
  grep -qiE "$c" "$R" || fail "missing per-character verdict: $c"
done

# 1. CORRECT SOURCE — jak2 intro / first cutscene (pre-rift, jak1-look), proven visually.
grep -qiE 'intro cutscene|first cutscene|pre.?rift|before the rift' "$R" || fail "must identify the jak2 INTRO/first-cutscene source"
grep -qiE 'source proof|rip.*vs.*intro|still.*vs.*(cutscene|intro)|compared.*jak2 intro' "$R" || fail "must PROVE the source with a rip-vs-jak2-intro still"

# 2. PROPER RETARGET — name-based joint remap, no garbled geometry shipped.
grep -qiE 'name.?based joint remap|joint name remap|name.?matched joints' "$R" || fail "must use a NAME-BASED joint remap (no find_closest weight-borrow)"
grep -qiE 'skin|weight' "$R" || fail "must document the skin/weight work"
grep -qiE 'not garbled|no garbl|garbl.*(none|zero|clean|fixed)|clean geometry' "$R" || fail "must give an honest garbling verdict"

# 3. COVERAGE — 4/4 or explicit honest partial (never silent).
grep -qiE 'coverage|swapped|landed' "$R" || fail "must state per-character coverage"

# MANDATORY: the OWNER'S REAL INSTALL FLOW, not adb-push shortcuts.
grep -qiE 'slim apk' "$R" || fail "must install the SLIM APK (owner flow)"
grep -qiE 'package_game_assets|external archive' "$R" || fail "must build+deploy the external archive (owner flow)"
grep -qiE 'no adb.?push|not adb.?push|without adb.?push' "$R" || fail "must state assets were NOT adb-pushed"
grep -qiE 'kill.*relaunch|relaunch|reload' "$R" || fail "must kill+relaunch so models load"

# Toggle semantics.
grep -qiE 'enhanced models' "$R" || fail "ENHANCED MODELS toggle evidence"
grep -qiE 'off.*(stock|identical|unchanged)|stock.*off' "$R" || fail "OFF must == stock"

# Device + desktop evidence.
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 foreground evidence"
grep -qiE 'link finish: logo' "$R" || fail "x86 smoke missing"

# Per-character visual evidence via the real flow (at least 4 stills/videos).
FRAMES=$(find .autoport/reports/Grecharged-hd-models2 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' \) 2>/dev/null | wc -l)
[ "$FRAMES" -ge 4 ] || fail "need per-character capture evidence (>=4 images/videos, found $FRAMES)"

bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL (device must run fresh HEAD)"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Ghdmodels2 PASS]"
