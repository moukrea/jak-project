#!/usr/bin/env bash
# Phase Gcine-crash3 validator — the RESIDUAL Gol/Maia-scene cinematic crash must
# be gone, proven on a LONG run that goes well PAST the prior ~9960 capture window
# AND shows the app still foreground at end (no return-to-home). Closes the
# truncated-log blind spot that false-passed Gcine-crash2/Gcine-pose.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gcine-crash3 validator =="

# 1. Forbidden edits + anti-grind + disk.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk full (${DFREE}G)"
ok "no forbidden edits; no grind; disk ok (${DFREE}G)"

# 2. Forensics + summary (scene named; fix-or-already-fixed determination).
[ -f .autoport/reports/Gcine3/crash-logcat.log ] || fail "no Gcine3/crash-logcat.log (must run the repro)"
SUM=.autoport/reports/Gcine3-fix-summary.md
[ -f "$SUM" ] || fail "no Gcine3-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary too short"
grep -qiE 'gol|maia|portal|halo|villain|cinematic' "$SUM" || fail "summary doesn't name the Gol/Maia scene"
grep -qiE 'x86|oracle|arm64|hi32|mips2c|noop|idiv|float|field|offset|regalloc|128|nan|already.?fixed|60ba2f477' "$SUM" || fail "summary lacks arm64-mechanism oracle-diff or an evidenced already-fixed determination"
ok "forensics + scene + determination present"

# 3. x86 unbroken.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 4. Deploy lands (device provably runs fresh HEAD).
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "deploy verified"

# 5. THE LONG CLEAN RUN — past the Gol/Maia scene, foreground alive at end.
NEWLOG=$(ls -t .autoport/reports/Gcine3-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gcine3 routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal (11|6|4)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)" "$NEWLOG" 2>/dev/null || true)
[ "${CR:-0}" -eq 0 ] || fail "CRASH still present: $CR native signal events in the long run"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 10500 ] || fail "run did not get past the Gol/Maia scene: frame=$FM (<10500); capture window too short or it crashed"
FG=.autoport/reports/Gcine3/foreground-at-end.txt
[ -f "$FG" ] || fail "no Gcine3/foreground-at-end.txt (must record mCurrentFocus at end-of-run)"
grep -q 'org.opengoal.gk.jak1' "$FG" || { echo "--- foreground-at-end ---"; cat "$FG"; fail "app NOT foreground at end-of-run = returned to home = crash"; }
grep -qi 'com.miui.home' "$FG" && fail "foreground-at-end shows launcher (com.miui.home) = app died"
ok "long run clean: 0 crash sigs, frame=$FM (>=10500), app foreground at end"

echo ""
echo "PASS(data): Gcine-crash3 — residual Gol/Maia-scene crash gone on a LONG run (frame=$FM past enter-misty, app still foreground = no return-to-home, deploy-verified, x86 OK). OWNER eye-confirms full play-through to gameplay."
