#!/usr/bin/env bash
set -uo pipefail
R=".autoport/reports/Grecharged-loader-packfix/report.txt"
fail(){ echo "[Gloader FAIL] $*" >&2; exit 1; }
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE 'LoaderActivity' "$R" || fail "the loader path is not addressed"
grep -qiE 'root cause|cause racine' "$R" || fail "no stated root cause for the pre-extraction death"
grep -qiE 'meminfo|memory|mémoire|OOM|asset.*limit|watchdog' "$R" || fail "the death mechanism is not evidenced with a measurement"
grep -qiE 'AREE026206000788|honor|eae4df44|redmi' "$R" || fail "no device proof (Honor evidence already acquired; the Redmi is the test device from 2026-07-29)"
grep -qiE 'files/cgo|extracted|extrait' "$R" || fail "extraction on device not proven"
grep -qiE '74|file_count' "$R" || fail "extracted file count not reported"
grep -qiE 'MESH BROWSER|mesh-browser' "$R" || fail "the MESH BROWSER row must be proven VISIBLE on screen, not just present in a file"
grep -qiE 'capture (sweep|campaign)|pixel (statistics|fraction)' "$R" && fail "in-game visual measurement detected — banned"
echo "[Gloader PASS]"
