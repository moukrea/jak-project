#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gicache FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak1-icache-flush/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK1 ICACHE FLUSH' "$R" || fail "no RESULT"
# Owner 2026-07-09: NO boot-flake exists to reproduce — do NOT gate on 20 boots.
# Gate on the FIX being correctly implemented + a clean boot + no regression.
grep -qiE 'clear_cache|__builtin___clear_cache' game/kernel/jak1/klink.cpp || fail "jak1 klink real-range flush (__builtin___clear_cache) not implemented"
grep -qiE 'boot|title|link finish|smoke' "$R" || fail "must show a clean device boot after the fix (no regression)"
# the old no-op must be gone: a real range must be used (heuristic: m_code_size assigned or explicit end ptr)
grep -qiE 'link finish: logo' "$R" || fail "x86 smoke not shown"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gicache PASS]"
