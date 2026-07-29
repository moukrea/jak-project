#!/usr/bin/env bash
# Pre-flight for EVERY APK delivery. Exit non-zero = do not upload.
#
# Written 2026-07-29 after six delivery traps in 24h, each producing an artifact that LOOKED fine:
#   1. android/CMakeLists.txt missing a new .cpp -> desktop green, Android link broken
#   2. --summary-only silently suppressing the CSVs the mesh index is built from (26 sweeps, 0 output)
#   3. a fix left behind a non-default flag, so the shipped default was the WORSE measured variant
#   4. the pack carrying ZERO mesh_index entries -> the browser ships without its catalogue
#   5. 28 CGO/DGO four days stale -> the shipped menu did not contain the feature at all
#   6. build.sh run without --pbr -> flag marker e3b0c442 (empty), Loader.cpp does not even compile
# Every one was invisible to "the script exited 0". Hence: check the ARTIFACT, not the run.
set -uo pipefail
cd "$(dirname "$0")/.."
CHK=".autoport/dist/app-jak1-CHECKER-DEBUG.apk"
NRM=".autoport/dist/app-jak1-NORMAL-recharged.apk"
fail(){ echo "[preflight FAIL] $*" >&2; exit 1; }
ok(){ echo "  ✓ $*"; }

[ -f "$CHK" ] || fail "missing $CHK"
[ -f "$NRM" ] || fail "missing $NRM"

# 1. the two builds must be genuinely different binaries
a=$(unzip -p "$CHK" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -c1-16)
b=$(unzip -p "$NRM" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -c1-16)
[ -n "$a" ] && [ -n "$b" ] || fail "could not read libgk.so from one of the APKs"
[ "$a" != "$b" ] || fail "checker and normal ship the SAME libgk ($a) — the define did not take"
ok "libgk distinct: checker $a / normal $b"

# 2. the checker APK must carry the binary built WITH the define
if [ -f build-android-checker/lib/arm64-v8a/libgk.so ]; then
  c=$(sha256sum build-android-checker/lib/arm64-v8a/libgk.so | cut -c1-16)
  [ "$a" = "$c" ] || fail "checker APK libgk ($a) is not build-android-checker's ($c)"
  ok "checker APK carries the checker build"
fi

# 3. no engine source newer than the APK (the stale-artifact class, hit 4x)
newer=$(find game common android -newer "$CHK" \( -name '*.cpp' -o -name '*.h' -o -name '*.java' \
        -o -name '*.frag' -o -name '*.glsl' -o -name '*.tese' \) 2>/dev/null | head -3)
[ -z "$newer" ] || fail "engine sources are NEWER than the APK:
$newer"
ok "no engine source newer than the APK"

# 4. CGOs must postdate goal_src, and carry the features we claim
newer_gc=$(find goal_src -name '*.gc' -newer out/jak1-arm64-full/iso/GAME.CGO 2>/dev/null | head -3)
[ -z "$newer_gc" ] || fail "goal_src is NEWER than the built CGOs (the shipped game code is stale):
$newer_gc"
ok "CGOs postdate goal_src"

# 5. the packs must actually contain the derived data (browser index, sidecars, CGOs)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
unzip -p "$CHK" assets/bundle/jak1_cgo.zip > "$tmp/cgo.zip" 2>/dev/null || fail "no CGO pack in the APK"
n=$(unzip -Z1 "$tmp/cgo.zip" 2>/dev/null | wc -l); [ "$n" -ge 28 ] || fail "only $n CGO/DGO in the pack"
ok "$n CGO/DGO in the pack"
unzip -p "$tmp/cgo.zip" GAME.CGO 2>/dev/null | strings | grep -qi 'mesh-browser' \
  || fail "GAME.CGO does not contain the mesh browser — the shipped menu lacks the feature"
ok "mesh-browser present in the shipped GAME.CGO"
unzip -p "$CHK" assets/bundle/jak1_custom.zip > "$tmp/cus.zip" 2>/dev/null || fail "no custom pack"
idx=$(unzip -Z1 "$tmp/cus.zip" 2>/dev/null | grep -c 'mesh_index'); [ "$idx" -ge 25 ] \
  || fail "only $idx mesh_index entries in the pack — the browser would ship without its catalogue"
ok "$idx mesh_index entries"
mw=$(unzip -p "$tmp/cus.zip" fr3/village1.meshweld 2>/dev/null | md5sum | cut -c1-16)
dk=$(md5sum out/jak1/fr3/village1.meshweld 2>/dev/null | cut -c1-16)
[ "$mw" = "$dk" ] || fail "shipped sidecar ($mw) != on-disk corrected sidecar ($dk)"
ok "sidecar in APK == corrected sidecar on disk"

echo "[preflight PASS] both APKs are safe to upload"
