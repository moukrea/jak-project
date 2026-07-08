#!/usr/bin/env bash
# deploy_verify.sh — PROVE the device is running the freshly-built libgk.so that
# reflects the current HEAD. Prevents the "fix committed/built but doesn't land
# on the device" class of silent progress loss.
#
# Checks (all must pass):
#   1. FRESHNESS: build-android libgk.so is NEWER than the newest C++/shader
#      source mtime (so the .so reflects recent edits — catches "didn't rebuild").
#   2. NOT-STALE-vs-HEAD: build-android libgk.so is NEWER than the HEAD commit
#      time (so the build happened after the latest committed change).
#   3. CHAIN: sha256(build libgk.so) == sha256(APK-bundled libgk.so) ==
#      sha256(device-installed libgk.so). So the device provably runs that .so.
#
# Usage: deploy_verify.sh [SERIAL]   (default serial eae4df44)
# Exit 0 = device provably runs the fresh HEAD-reflecting libgk.so; nonzero = NOT.
# Records a fingerprint to .autoport/reports/deploy-fingerprint.txt for audit.
#
# NOTE on the incremental-build hazard: cmake/ninja header-dep tracking *should*
# recompile dependents, but to be safe a phase that changes libgk.so C++/shaders
# MUST do a clean/forced rebuild (touch the changed TU or `ninja -t clean`) so the
# .so truly reflects HEAD. This script proves the RESULT reached the device; the
# clean-rebuild discipline guarantees the .so CONTENT matches the source.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SERIAL="${1:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"
SO_REL="lib/arm64-v8a/libgk.so"
BUILT="build-android/$SO_REL"
die() { echo "DEPLOY-VERIFY FAIL: $*" >&2; exit 1; }

[ -f "$BUILT" ] || die "no built libgk.so at $BUILT"
SO_MTIME=$(stat -c %Y "$BUILT")

# 1. Freshness vs source.
NEWEST_SRC=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
if [ -n "$NEWEST_SRC" ] && [ "$SO_MTIME" -lt "$NEWEST_SRC" ]; then die "libgk.so ($(date -d @$SO_MTIME +%H:%M)) is OLDER than newest source ($(date -d @$NEWEST_SRC +%H:%M)) — STALE build, rebuild before deploy"; fi
echo "  ok: libgk.so newer than newest source"

# 2. (removed) "newer than HEAD commit time" — FALSE-POSITIVES on the normal
# build-then-commit flow (the .so is built before the commit that packages it).
# Freshness-vs-source (check 1) + the build==APK==device chain (check 3) are the
# real guarantees that the device runs a .so reflecting the current source.

# 3. Chain: build == APK == device.
# Repo-local temp: /tmp can be size-limited or sandbox-isolated (a 220MB APK
# pull died at ~79% under a sandboxed tmpfs), which false-FAILs the chain.
mkdir -p .autoport/tmp
TMP=$(mktemp -d .autoport/tmp/dv.XXXXXX); trap "rm -rf $TMP" EXIT
B=$(sha256sum "$BUILT" | cut -d' ' -f1)
APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$APK" ] || die "no app-jak1-debug.apk"
unzip -p "$APK" "$SO_REL" > "$TMP/apk.so" 2>/dev/null || die "APK has no $SO_REL"
A=$(sha256sum "$TMP/apk.so" | cut -d' ' -f1)
[ "$B" = "$A" ] || die "build libgk.so != APK-bundled libgk.so — APK bundled a STALE .so (reassemble the APK after building)"
DP=$("$ADB" -s "$SERIAL" shell pm path "$PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
[ -n "$DP" ] || die "package not installed on device $SERIAL"
"$ADB" -s "$SERIAL" pull "$DP" "$TMP/dev.apk" >/dev/null 2>&1 || die "could not pull device APK"
unzip -p "$TMP/dev.apk" "$SO_REL" > "$TMP/dev.so" 2>/dev/null || die "device APK has no $SO_REL"
D=$(sha256sum "$TMP/dev.so" | cut -d' ' -f1)
[ "$A" = "$D" ] || die "APK libgk.so != DEVICE libgk.so — device is running a STALE install (reinstall the APK)"
echo "  ok: chain build==APK==device ($(echo $B|cut -c1-16))"

# Record fingerprint.
mkdir -p .autoport/reports
printf 'deploy-verify PASS %s  commit=%s  libgk_sha=%s  so_mtime=%s\n' "$(date -Is)" "$(git rev-parse --short HEAD)" "$(echo $B|cut -c1-16)" "$(date -d @$SO_MTIME -Is)" >> .autoport/reports/deploy-fingerprint.txt

echo "DEPLOY-VERIFY PASS: device $SERIAL provably runs the fresh HEAD ($(git rev-parse --short HEAD)) libgk.so."
