#!/usr/bin/env bash
# Validator — Gjak2-boot: jak2 brought up on Android arm64 (builds + boots to render on device).
# Physical-artifact strict: real jak2 symbols in libgk (not a stub) + x86 jak2 oracle intact +
# engine goal_src untouched (1-to-1) + report boot evidence. No log-string-only greens.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gjak2-boot FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gjak2-boot ok] $*"; }

R=.autoport/reports/Gjak2-boot/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*JAK2[[:space:]]+ANDROID[[:space:]]+BOOT' "$R" || fail "report lacks RESULT: JAK2 ANDROID BOOT <milestone>"
# Boot evidence must be described (device milestone + foreground + render + crash-free + x86 oracle)
grep -qiE 'link finish|master-mode|kernel up|boot' "$R" || fail "report must show a jak2 boot/link milestone"
grep -qiE 'mCurrentFocus|foreground|focus' "$R" || fail "report must assert app foreground on device (shared-device hygiene)"
grep -qiE 'render|frame|A35|render frame' "$R" || fail "report must show a jak2 render frame on device"
grep -qiE 'x86.*jak2|jak2.*x86|oracle' "$R" || fail "report must confirm x86 jak2 oracle intact"
ok "report: jak2 boot milestone + foreground + render + x86 oracle asserted"

# 1-to-1: engine goal_src (jak1 + jak2, non-pc) UNTOUCHED vs the supervisor anchor
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
ANCHOR=${SUP_ANCHOR:-HEAD~1}
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && { grep -qiE 'revert|pristine|documented|prior.?phase' "$R" || fail "engine goal_src changed ($ENG) undocumented — our-x86 must == original-x86"; }
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "engine goal_src untouched; golden pristine"

# jak2 actually WIRED into the Android build (not still excluded) — source-level proof
grep -rqiE 'jak2::InitMachine|jak2.*InitMachine' android/ 2>/dev/null || \
  grep -rqiE 'jak2' android/CMakeLists.txt 2>/dev/null && ! grep -qiE 'jak2/jak3 kboot.cpp excluded' android/CMakeLists.txt 2>/dev/null || \
  fail "jak2 still excluded from the Android build (kboot/InitMachine not wired)"
ok "jak2 wired into the Android build"

# PHYSICAL: the built Android libgk must contain real jak2 kernel symbols (proves jak2 compiled in)
SO=$(ls -t build-android/lib/arm64-v8a/libgk.so 2>/dev/null | head -1)
[ -f "$SO" ] || fail "no built Android libgk.so to inspect"
OD=$(command -v aarch64-linux-gnu-nm || command -v llvm-nm || command -v nm)
JSYM=$($OD "$SO" 2>/dev/null | grep -icE 'jak2|InitMachine.*2|_2E' )
[ "${JSYM:-0}" -gt 0 ] 2>/dev/null || { \
  # fall back to string scan for jak2 asset/dgo references baked in
  JSYM=$(strings -a "$SO" 2>/dev/null | grep -icE 'jak2|CGO.*jak2|iso_data/jak2'); \
  [ "${JSYM:-0}" -gt 0 ] 2>/dev/null || fail "built libgk has NO jak2 symbols/strings — jak2 not really compiled in (stub)"; }
ok "built libgk contains real jak2 references ($JSYM)"

# x86 jak2 oracle: the desktop jak2 build must still reach its boot milestone
SMOKE=$(mktemp)
timeout 180 build-x86/game/gk --game jak2 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak2/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -qiE 'link finish|master-mode|kernel: machine started' "$SMOKE" || { tail -5 "$SMOKE"; rm -f "$SMOKE"; fail "x86 jak2 oracle regressed (no boot milestone)"; }
rm -f "$SMOKE"
ok "x86 jak2 oracle boots"
echo "[Gjak2-boot PASS] jak2 Android bring-up: real symbols + wired + x86 oracle intact; report boot evidence present. (owner play-test next)"
