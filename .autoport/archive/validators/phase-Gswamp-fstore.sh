#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gsf FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gswamp-fstore/report.txt
[ -f "$R" ] || fail "no report.txt"
if grep -qiE 'RESULT:[[:space:]]*SWAMP[[:space:]]+FSTORE[[:space:]]+ROOT[[:space:]]+NAMED' "$R"; then
  grep -qiE 'x14|trampoline|mips2c|clobber|st.?reg' "$R" || fail "ROOT NAMED must name the x14-clobber path"; echo "[Gsf PASS] root-named"; exit 0; fi
grep -qiE 'RESULT:[[:space:]]*ARM64[[:space:]]+FSTORE[[:space:]]+FIXED' "$R" || fail "needs RESULT: ARM64 FSTORE FIXED (or ROOT NAMED)"
grep -qiE 'effect.*#f|#f.*effect|store.*land' "$R" || fail "must show effect binds #f"
grep -qiE 'repair.*(0|zero)|counter.*0|fault.*eliminat' "$R" || fail "must show repair counter 0 (fault eliminated at source)"
grep -qiE 'x86.*(byte|identical|link finish)' "$R" || fail "x86 must stay byte-identical"
echo "[Gsf PASS] fstore-fixed markers present. (close-gate next)"
