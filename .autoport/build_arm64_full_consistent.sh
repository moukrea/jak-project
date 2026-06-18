#!/usr/bin/env bash
# build_arm64_full_consistent.sh — build a FULL, internally-consistent arm64
# CGO+DGO set (all 28) from CURRENT goal_src, in ONE pass, then restore the x86
# oracle tree. This is what's needed to deploy a fresh set to the device without
# the frame-180 "mixed build" sparticle SIGILL (boot CGOs + TIT.DGO etc. all from
# the same build). Staged to out/jak1-arm64-full/iso/.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

X86_DIR="out/jak1/iso"
OBJ_DIR="out/jak1/obj"
STAGE="out/jak1-arm64-full/iso"
LOG_DIR=".autoport/logs"
X86_GOALC="build/goalc/goalc"
ARM64_GOALC="build-arm64/goalc/goalc"
fail(){ echo "[full FAIL] $*" >&2; exit 1; }
log(){ echo "[full] $*"; }

mkdir -p "$STAGE" "$LOG_DIR" "$OBJ_DIR" "$X86_DIR"
[ -x "$X86_GOALC" ]   || fail "$X86_GOALC missing"
[ -x "$ARM64_GOALC" ] || fail "$ARM64_GOALC missing"
"$ARM64_GOALC" --version 2>&1 | grep -q "arm64" || fail "$ARM64_GOALC not arm64 backend"
"$X86_GOALC"   --version 2>&1 | grep -q "x86"   || fail "$X86_GOALC not x86 backend"

# 1. arm64 full build (all CGOs + DGOs) into out/jak1/iso/
log "wiping obj cache before arm64 build"
find "$OBJ_DIR" -maxdepth 1 -type f \( -name '*.o' -o -name '*.go' \) -delete
log "arm64 (make-group iso :force #t) ... (full build, several minutes)"
ARM_LOG="$LOG_DIR/full-arm64-mi.log"
"$ARM64_GOALC" --user-auto --game jak1 --disable-ansi -c '(make-group "iso" :force #t)' > "$ARM_LOG" 2>&1
grep -qE "Successfully built all [0-9]+ targets" "$ARM_LOG" || { tail -60 "$ARM_LOG" >&2; fail "arm64 build did not finish"; }
log "$(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$ARM_LOG" | head -1)"

# 2. stage ALL 28 arm64 files (consistent set)
rm -f "$STAGE"/*.CGO "$STAGE"/*.DGO 2>/dev/null || true
cp -f "$X86_DIR"/*.CGO "$X86_DIR"/*.DGO "$STAGE"/
n=$(ls "$STAGE"/*.CGO "$STAGE"/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || fail "expected 28 staged files, got $n"
( cd "$STAGE" && sha256sum *.CGO *.DGO ) > "$LOG_DIR/full-arm64-hashes.txt"
log "staged $n consistent arm64 files -> $STAGE (hashes in $LOG_DIR/full-arm64-hashes.txt)"

# 3. restore x86 oracle (so out/jak1/iso is x86 again; protect desktop builds)
log "wiping obj cache before x86 restore"
find "$OBJ_DIR" -maxdepth 1 -type f \( -name '*.o' -o -name '*.go' \) -delete
log "x86 (make-group iso :force #t) ... (restore oracle)"
X86_LOG="$LOG_DIR/full-x86-restore-mi.log"
"$X86_GOALC" --user-auto --game jak1 --disable-ansi -c '(make-group "iso" :force #t)' > "$X86_LOG" 2>&1
grep -qE "Successfully built all [0-9]+ targets" "$X86_LOG" || { tail -60 "$X86_LOG" >&2; fail "x86 restore build did not finish"; }
log "x86 oracle restored: $(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$X86_LOG" | head -1)"

echo "[full] DONE — consistent arm64 set ready at $STAGE ($n files)"
