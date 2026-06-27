#!/usr/bin/env bash
# Validator — Gpkg-distributable: self-contained APK that bundles the PC-built runtime assets COMPRESSED
# and DECOMPRESSES them at first run (idempotent). No ISO picker / no on-device extractor. goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpkg-dist FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gpkg-dist ok] $*"; }

R=.autoport/reports/Gpkg-distributable/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*SELF-?CONTAINED[[:space:]]+APK.*BUNDLED[[:space:]]+COMPRESSED[[:space:]]+ASSETS[[:space:]]+DECOMPRESS' "$R" \
  || fail "report lacks RESULT: SELF-CONTAINED APK — BUNDLED COMPRESSED ASSETS DECOMPRESS AT FIRST RUN"
# assets bundled COMPRESSED in the APK (format + sizes documented)
grep -qiE 'compress|zstd|zip|xz|gzip|archive' "$R" || fail "must document the compressed asset bundle format"
grep -qiE 'size|MB|bytes|compressed.*raw|raw.*compressed' "$R" || fail "must document compressed vs raw size"
# first-run decompress + boot, idempotent second launch
grep -qiE 'first.?run|first.?launch|setup|decompress|unpack' "$R" || fail "must document first-run decompression"
grep -qiE 'progress' "$R" || fail "must document the first-run progress UI"
grep -qiE 'link finish: logo|in-?game|boots' "$R" || fail "must show the game boots after first-run decompression"
grep -qiE 'second.?launch|idempot|skip.*decompress|version.?stamp|already.*unpack|data.?ready' "$R" || fail "must show second launch skips decompression (idempotent)"
grep -qiE 'storage|corrupt|integrity|hash|verify|error' "$R" || fail "must document integrity + low-storage error handling"
# NOT the old ISO/extractor approach
grep -qiE 'ISO[[:space:]]+picker|on-?device[[:space:]]+extract|SAF' "$R" && fail "report describes the SCRAPPED ISO/on-device-extractor approach — must be bundled-compressed-assets"
ok "compressed asset bundle in APK; first-run decompress+boot; idempotent; errors handled; no ISO/extractor"

SRC=$(git diff --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gpkg-distributable-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "goal_src 1-to-1; fix-summary >=60 lines; golden pristine; device runs fresh HEAD"
echo "[Gpkg-dist PASS] self-contained APK: PC-built assets bundled compressed, decompressed at first run; idempotent."
