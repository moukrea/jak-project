#!/usr/bin/env bash
# Validator — Gpkg-distributable: self-contained APK that bundles the PC-built runtime assets COMPRESSED
# and DECOMPRESSES them at first run (idempotent). No ISO picker / no on-device extractor. goal_src 1-to-1.
# HARDENED 2026-06-27 after a false-green: a bundle built from the SLIM/incomplete asset set booted but
# DROPPED assets -> the menu orange tint backdrop rendered broken on device. Now gates on asset
# COMPLETENESS (== full build) AND in-game rendering (menu), not just boot/decompress/idempotent.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpkg-dist FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gpkg-dist ok] $*"; }

R=.autoport/reports/Gpkg-distributable/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*SELF-?CONTAINED[[:space:]]+APK.*BUNDLED[[:space:]]+COMPRESSED[[:space:]]+ASSETS[[:space:]]+DECOMPRESS' "$R" \
  || fail "report lacks RESULT: SELF-CONTAINED APK — BUNDLED COMPRESSED ASSETS DECOMPRESS AT FIRST RUN"
# compressed bundle in the APK (format + sizes)
grep -qiE 'compress|zstd|zip|deflate|xz|gzip|archive' "$R" || fail "must document the compressed asset bundle format"
grep -qiE 'size|MB|GiB|GB|bytes|compressed.*raw|raw.*compressed' "$R" || fail "must document compressed vs raw size"
# first-run decompress + boot + idempotent
grep -qiE 'first.?run|first.?launch|setup|decompress|unpack' "$R" || fail "must document first-run decompression"
grep -qiE 'progress' "$R" || fail "must document the first-run progress UI"
grep -qiE 'link finish: logo|in-?game|boots' "$R" || fail "must show the game boots after first-run decompression"
grep -qiE 'second.?launch|idempot|skip.*decompress|version.?stamp|already.*unpack|data.?ready' "$R" || fail "must show second launch skips decompression (idempotent)"
grep -qiE 'storage|corrupt|integrity|hash|verify|error' "$R" || fail "must document integrity + low-storage error handling"
# --- HARDENED: asset COMPLETENESS (the bundle must equal the FULL build, not slim) ---
grep -qiE 'complete|full[- ]asset|all[- ]asset|no[- ]?missing|matches.*full|== *full|321|file[- ]count|diff.*(out/jak1|full)' "$R" \
  || fail "must prove the decompressed asset set is COMPLETE (file-count/list == the full PC build out/jak1), not slim/partial"
if grep -qiE 'slim|assets-slim|slimIso|fr3[- ]only|assets-light' "$R"; then
  grep -qiE 'NOT.*slim|full.*not.*slim|bundle.*full' "$R" || fail "report mentions SLIM assets — the shipped bundle must be the FULL set, not slim"
fi
# --- HARDENED: in-game RENDERING verified (the false-green broke the menu tint) ---
grep -qiE 'menu|tint|backdrop|render|orange|oracle|frame.?compare|graphics_analyze|screenshot.*menu' "$R" \
  || fail "must verify in-game RENDERING is intact (esp. the menu tint backdrop) — boot alone is NOT enough (it false-greened on a broken menu)"
grep -qiE 'menu.*(render|ok|match|intact|correct)|tint.*(render|ok|correct)|no.*render.*regress' "$R" \
  || fail "must assert the menu (orange tint backdrop) renders correctly on the bundled-APK device run"
# NOT the old ISO/extractor approach
grep -qiE 'ISO[[:space:]]+picker|on-?device[[:space:]]+extract|SAF' "$R" && fail "report describes the SCRAPPED ISO/on-device-extractor approach"
ok "compressed bundle; first-run decompress+boot; idempotent; COMPLETE assets (==full); menu renders; errors handled"

SRC=$(git diff --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gpkg-distributable-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "goal_src 1-to-1; fix-summary >=60 lines; golden pristine; device runs fresh HEAD"
echo "[Gpkg-dist PASS] self-contained APK: FULL assets bundled compressed, decompressed at first run; menu renders; idempotent."
