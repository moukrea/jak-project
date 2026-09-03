#!/usr/bin/env bash
# build_arm64_full_consistent_jak2.sh — Gjak2-boot. Build a FULL, internally-
# consistent arm64 CGO+DGO set for JAK2 from CURRENT goal_src, in ONE pass, then
# restore the x86 oracle tree so out/jak2/iso is x86 again (protects the desktop
# jak2 oracle the validator runs). Staged to out/jak2-arm64-full/iso/.
#
# Mirror of build_arm64_full_consistent.sh (jak1) — parametrized for jak2:
#   * --game jak2, out/jak2/{iso,obj}, stage out/jak2-arm64-full/iso
#   * jak2 has ~151 CGO/DGO (not jak1's 28); the staged count must match the x86
#     oracle count exactly (a consistent full set), not a hardcoded number.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GAME="jak2"
X86_DIR="out/${GAME}/iso"
OBJ_DIR="out/${GAME}/obj"
STAGE="out/${GAME}-arm64-full/iso"
LOG_DIR=".autoport/logs"
X86_GOALC="build/goalc/goalc"
ARM64_GOALC="build-arm64/goalc/goalc"
fail(){ echo "[jak2-full FAIL] $*" >&2; exit 1; }
log(){ echo "[jak2-full] $*"; }

mkdir -p "$STAGE" "$LOG_DIR" "$OBJ_DIR" "$X86_DIR"
[ -x "$X86_GOALC" ]   || fail "$X86_GOALC missing"
[ -x "$ARM64_GOALC" ] || fail "$ARM64_GOALC missing"
"$ARM64_GOALC" --version 2>&1 | grep -q "arm64" || fail "$ARM64_GOALC not arm64 backend"
"$X86_GOALC"   --version 2>&1 | grep -q "x86"   || fail "$X86_GOALC not x86 backend"

# Reference x86 oracle file count (the consistent full set target).
X86_N=$(ls "$X86_DIR"/*.CGO "$X86_DIR"/*.DGO 2>/dev/null | wc -l)
[ "$X86_N" -gt 100 ] || fail "x86 jak2 oracle has only $X86_N CGO/DGO (expected ~151); build the x86 jak2 iso first"
log "x86 jak2 oracle has $X86_N CGO/DGO — target for the arm64 consistent set"

# 1. arm64 full build (all CGOs + DGOs) into out/jak2/iso/
log "wiping obj cache before arm64 build"
find "$OBJ_DIR" -maxdepth 1 -type f \( -name '*.o' -o -name '*.go' \) -delete
log "arm64 (make-group iso :force #t) --game jak2 ... (full build, MANY minutes)"
ARM_LOG="$LOG_DIR/full-arm64-jak2-mi.log"
"$ARM64_GOALC" --user-auto --game "$GAME" --disable-ansi -c '(make-group "iso" :force #t)' > "$ARM_LOG" 2>&1
grep -qE "Successfully built all [0-9]+ targets" "$ARM_LOG" || { tail -80 "$ARM_LOG" >&2; fail "arm64 jak2 build did not finish"; }
log "$(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$ARM_LOG" | head -1)"

# 2. stage ALL arm64 files (consistent set), require count == x86 oracle count
rm -f "$STAGE"/*.CGO "$STAGE"/*.DGO 2>/dev/null || true
cp -f "$X86_DIR"/*.CGO "$X86_DIR"/*.DGO "$STAGE"/
n=$(ls "$STAGE"/*.CGO "$STAGE"/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq "$X86_N" ] || fail "expected $X86_N staged files (x86 parity), got $n"
( cd "$STAGE" && sha256sum *.CGO *.DGO ) > "$LOG_DIR/full-arm64-jak2-hashes.txt"
log "staged $n consistent arm64 jak2 files -> $STAGE"

# 3. restore x86 oracle (so out/jak2/iso is x86 again; protect the desktop oracle)
log "wiping obj cache before x86 restore"
find "$OBJ_DIR" -maxdepth 1 -type f \( -name '*.o' -o -name '*.go' \) -delete
log "x86 (make-group iso :force #t) --game jak2 ... (restore oracle)"
X86_LOG="$LOG_DIR/full-x86-jak2-restore-mi.log"
"$X86_GOALC" --user-auto --game "$GAME" --disable-ansi -c '(make-group "iso" :force #t)' > "$X86_LOG" 2>&1
grep -qE "Successfully built all [0-9]+ targets" "$X86_LOG" || { tail -80 "$X86_LOG" >&2; fail "x86 jak2 restore build did not finish"; }
log "x86 jak2 oracle restored: $(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$X86_LOG" | head -1)"

echo "[jak2-full] DONE — consistent arm64 jak2 set ready at $STAGE ($n files)"
