#!/usr/bin/env bash
# Validator — Grecharged-foliage-wind: gated wind sway for jak1 palms/shrubs.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gfoliage FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gfoliage ok] $*"; }
R=.autoport/reports/Grecharged-foliage-wind/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:' "$R" || fail "no RESULT line"
grep -qiE 'RESULT:.*(IN-PROGRESS|in progress|underway|not final)' "$R" && fail "RESULT is a living skeleton"
grep -qiE 'toggle|recharged settings|réglages' "$R" || fail "must be a Recharged Settings toggle"
grep -qiE 'off.*(stock|identical|unchanged|byte)|stock.*off' "$R" || fail "OFF must == stock render"
grep -qiE 'wind|sway|wobble|brise|breeze' "$R" || fail "must describe the wind motion"
grep -qiE 'shrub' "$R" || fail "must cover shrubs"
grep -qiE 'palm|palmier|tfrag' "$R" || fail "must cover palm leaves"
grep -qiE 'perf|ms|fps' "$R" || fail "must measure device perf ON vs OFF"
F=$(find .autoport/reports/Grecharged-foliage-wind -type f \( -name '*.png' -o -name '*.mp4' \) -newermt '-2 days' 2>/dev/null | grep -v '/x86/' | grep -icE 'device|jak1focus' || true)
[ "${F:-0}" -ge 2 ] || fail "need OFF and ON device captures (found $F)"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "report + gated toggle + OFF==stock + device OFF/ON evidence"
echo "[Gfoliage PASS] foliage wind gated + evidenced. (owner play-test next)"
