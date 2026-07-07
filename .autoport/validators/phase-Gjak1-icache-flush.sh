#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gicache FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak1-icache-flush/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK1 ICACHE FLUSH' "$R" || fail "no RESULT"
grep -qiE '(2[0-9]|[3-9][0-9])/(2[0-9]|[3-9][0-9])|20/20' "$R" || fail "need >=20 clean cold boots evidence"
grep -qE 'clear_cache|CacheFlush' game/kernel/jak1/klink.cpp || fail "jak1 klink flush not fixed"
# the old no-op must be gone: a real range must be used (heuristic: m_code_size assigned or explicit end ptr)
grep -qiE 'link finish: logo' "$R" || fail "x86 smoke not shown"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gicache PASS]"
