#!/usr/bin/env bash
# gfxray_build_arm64_tit.sh — build the arm64 TIT.DGO from current goal_src (which
# carries the temporary GFXRAY (format 0 ...) dump in title-obs.gc) and stage it into
# the Android APK asset dir, so the device run captures the per-frame logo-volumes
# (light-rays) lifetime in logcat. The arm64 goalc writes into out/jak1/iso (the x86
# oracle path), so this script does NOT restore x86 — the caller must rebuild x86 after
# (see arm64-diag-overwrites-kernel-cgo). Only TIT.DGO is rebuilt+shipped (a safe level
# DGO; see game-cgo-rebuild-unsafe).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ARM64_GOALC="build-arm64/goalc/goalc"
ANDROID_DGO="android/app/src/jak1/assets/iso_data/jak1"
LOG=".autoport/reports/Gfix-title-rays/arm64-tit-build.log"
mkdir -p "$(dirname "$LOG")" "$ANDROID_DGO"
[ -x "$ARM64_GOALC" ] || { echo "[arm64] missing $ARM64_GOALC"; exit 1; }
"$ARM64_GOALC" --version 2>&1 | grep -q "arm64" || { echo "[arm64] $ARM64_GOALC not arm64"; exit 1; }

echo "[arm64] wiping obj cache (avoid x86/arm64 .o mix)"
find out/jak1/obj -maxdepth 1 -type f \( -name '*.o' -o -name '*.go' \) -delete 2>/dev/null || true
echo "[arm64] make-group iso :force #t (full arm64 build, several minutes) ..."
"$ARM64_GOALC" --user-auto --game jak1 --disable-ansi -c '(make-group "iso" :force #t)' > "$LOG" 2>&1
grep -qE "Successfully built all [0-9]+ targets" "$LOG" || { echo "[arm64] BUILD FAILED"; tail -50 "$LOG"; exit 1; }
echo "[arm64] $(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$LOG" | head -1)"

[ -f out/jak1/iso/TIT.DGO ] || { echo "[arm64] out/jak1/iso/TIT.DGO missing after build"; exit 1; }
cp -f out/jak1/iso/TIT.DGO "$ANDROID_DGO/TIT.DGO"
SZ=$(stat -c %s "$ANDROID_DGO/TIT.DGO")
echo "[arm64] staged arm64 TIT.DGO ($SZ B) -> $ANDROID_DGO/TIT.DGO"
echo "[arm64] NOTE: out/jak1/iso is now ARM64 — caller must rebuild x86 before any x86/validator run."
