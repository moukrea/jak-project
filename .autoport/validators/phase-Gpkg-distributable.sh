#!/usr/bin/env bash
# Validator — Gpkg-distributable: self-contained APK (engine+extractor, NO bundled copyrighted assets);
# first-launch ISO picker + on-device extraction; idempotent data-ready gate. goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpkg-dist FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gpkg-dist ok] $*"; }

R=.autoport/reports/Gpkg-distributable/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*SELF-?CONTAINED[[:space:]]+APK.*ISO[[:space:]]+ONBOARDING.*EXTRACTION[[:space:]]+OK' "$R" \
  || fail "report lacks RESULT: SELF-CONTAINED APK — ISO ONBOARDING + ON-DEVICE EXTRACTION OK"
# clean APK has NO pre-bundled copyrighted game assets
grep -qiE 'no.*(bundled|copyrighted).*asset|CGO.*absent|DGO.*absent|assets.*not.*bundled|clean.*apk' "$R" \
  || fail "must prove the clean APK ships WITHOUT pre-bundled CGO/DGO/texture assets"
# first-launch flow exercised end-to-end + idempotent
grep -qiE 'first.?launch|onboard|SAF|file.?picker|ISO.*(select|pick)' "$R" || fail "must document the first-launch ISO-picker onboarding"
grep -qiE 'extract' "$R" || fail "must document the on-device extraction run"
grep -qiE 'second.?launch|idempot|skip.*extract|data.?ready|already.*extracted' "$R" || fail "must show extraction is skipped on subsequent launches (idempotent)"
grep -qiE 'link finish: logo|in-?game|boots' "$R" || fail "must show the game boots after extraction"
grep -qiE 'invalid|wrong|corrupt|low.*storage|error' "$R" || fail "must document error handling (bad ISO / low storage)"
ok "self-contained APK: no bundled assets; ISO onboarding -> on-device extraction -> boot; idempotent; errors handled"

SRC=$(git diff --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gpkg-distributable-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "goal_src 1-to-1; fix-summary >=60 lines; golden pristine"
echo "[Gpkg-dist PASS] self-contained distributable APK: user ISO -> on-device extraction -> play; no bundled copyrighted assets."
