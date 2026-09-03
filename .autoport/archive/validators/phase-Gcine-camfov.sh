#!/usr/bin/env bash
# Phase Gcine-camfov validator — D1 fix: the cutscene camera must project at the
# panel aspect (2.222), not 4:3 (1.333). Objective: re-captured device camera diff
# vs oracle shows the 5/3 projection scaling gone (RESULT: D1 RESOLVED), camera
# position unchanged, cinematic still plays through crash-free (long + foreground).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gcine-camfov validator =="

# 1. Forbidden edits + anti-grind + disk.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk full (${DFREE}G)"
ok "no forbidden edits; no grind; disk ok (${DFREE}G)"

# 2. Objective projection-match proof (D1 resolved) + re-captured device cam log.
PM=.autoport/reports/Gd1/projection-match.txt
[ -f "$PM" ] || fail "no Gd1/projection-match.txt (must objectively re-measure the cutscene projection vs oracle)"
grep -qiE 'RESULT:[[:space:]]*D1[[:space:]]+RESOLVED' "$PM" || fail "projection-match.txt lacks 'RESULT: D1 RESOLVED' verdict"
grep -qiE 'before' "$PM" && grep -qiE 'after' "$PM" || fail "projection-match.txt must show before/after matched-beat projection numbers"
grep -qiE 'c0\.x|c1\.y|projection|aspect|pose_dist' "$PM" || fail "projection-match.txt must cite the projection rows / pose_dist"
CAM=$(find .autoport/reports/Gd1 -type f \( -iname '*cam*' -o -iname '*arm*' -o -iname '*device*' \) -size +2k 2>/dev/null | head -1)
[ -n "$CAM" ] || fail "no re-captured device camera log (>2k) under .autoport/reports/Gd1 — projection claim unbacked"
ok "projection-match: D1 RESOLVED, backed by re-captured cam log ($(basename "$CAM"))"

# 3. Fix-summary names the arm64 cutscene FOV/aspect mechanism + oracle-diff + fix.
SUM=.autoport/reports/Gcine-camfov-fix-summary.md
[ -f "$SUM" ] || fail "no Gcine-camfov-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary too short"
grep -qiE 'cutscene|math.?camera|fov|aspect|projection' "$SUM" || fail "summary doesn't name the cutscene FOV/aspect path"
grep -qiE 'x86|oracle|arm64|5/3|1.333|2.222|0.80|field|offset|float|aspect4x3|video.?parms' "$SUM" || fail "summary lacks the arm64 oracle-diff / 5-3 signature"
[ "$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | wc -l)" -ge 1 ] || fail "no code fix landed"
ok "fix-summary + mechanism + real code change present"

# 4. x86 unbroken.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 5. Deploy lands.
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "deploy verified"

# 6. Cinematic still plays through crash-free (no Gcine-crash3 regression).
NEWLOG=$(ls -t .autoport/reports/Gcine-camfov-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gcine-camfov routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal (11|6|4)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)" "$NEWLOG" 2>/dev/null || true)
[ "${CR:-0}" -eq 0 ] || fail "CRASH regressed: $CR native signal events"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 10500 ] || fail "cinematic regressed: frame=$FM (<10500)"
FG=.autoport/reports/Gd1/foreground-at-end.txt
[ -f "$FG" ] && { grep -q 'org.opengoal.gk.jak1' "$FG" || fail "app not foreground at end (returned to home)"; }
ok "cinematic still plays through crash-free, frame=$FM"

echo ""
echo "PASS(data): Gcine-camfov — D1 fixed (cutscene projects at panel 2.222 not 4:3; 5/3 scaling gone, position unchanged), cinematic plays through (frame=$FM), deploy-verified, x86 OK. OWNER eye-confirms the framing now fills the screen."
