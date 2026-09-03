#!/usr/bin/env bash
# Phase C1 validator — configure build-arm64-linux with cross-toolchain;
# gk builds. Authored by the orchestrator session 2026-05-21 (no
# supervisor available in headless mode); see SUPERVISOR_JOURNAL.md for
# the rationale and supervisor-equivalent commit.
#
# Enforces (in roughly increasing strictness):
#   1. Required files present.
#   2. Toolchain file generalised (no forced OG_ARM64_STRESS=ON).
#   3. Root CMakeLists.txt exposes OG_LINUX_ARM64 + diverts on it.
#   4. game/linux-arm64/CMakeLists.txt has the documented structure.
#   5. .autoport/lib/c1_configure.sh exists, executable, succeeds.
#   6. After --build --target gk, an aarch64 ELF gk exists.
#   7. file(1) reports ELF 64-bit LSB ARM aarch64.
#   8. readelf shows /lib/ld-linux-aarch64.so.1 interpreter (glibc, not
#      Bionic, not statically linked).
#   9. Stripped size ≥ 1 MB.
#  10. Stripped SHA-256 ≠ goal_stress_arm64 (if it exists).
#  11. nm --defined-only contains the required GOAL kernel symbols.
#  12. No synthetic-state / weak_jak1_ / kStateSeq patterns in diff vs A4.
#  13. Codegen files byte-identical to A4.
#  14. Desktop x86 gk smoke test still reaches "link finish: logo".
#  15. C1-config.md headline present.
#  16. Reconfigure idempotent — running c1_configure.sh twice yields the
#      same key CMakeCache values.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BUILD_DIR="build-arm64-linux"
CFG_SCRIPT=".autoport/lib/c1_configure.sh"
REPORT_MD=".autoport/reports/C1-config.md"
TOOLCHAIN_FILE="cmake/aarch64-linux-toolchain.cmake"
ROOT_CMAKE="CMakeLists.txt"
LINUX_ARM64_CMAKE="game/linux-arm64/CMakeLists.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase C1 validator =="

# ---- 1. Required files ----
[ -f "$TOOLCHAIN_FILE" ]      || fail "$TOOLCHAIN_FILE missing"
[ -f "$ROOT_CMAKE" ]          || fail "$ROOT_CMAKE missing"
[ -f "$LINUX_ARM64_CMAKE" ]   || fail "$LINUX_ARM64_CMAKE missing — C1 deliverable"
[ -x "$CFG_SCRIPT" ]          || fail "$CFG_SCRIPT missing or not executable"
[ -f "$REPORT_MD" ]           || fail "$REPORT_MD missing"
ok "required files present"

# ---- 2. Toolchain file generalised ----
# The file must no longer force OG_ARM64_STRESS=ON unconditionally. The
# pre-C1 toolchain set it at top-level scope (no if-guard, no conditional),
# defeating any -DOG_LINUX_ARM64=ON the caller passed. The fix can take
# two shapes:
#   (a) Remove the cache-force entirely (caller must pass one of
#       -DOG_LINUX_ARM64=ON / -DOG_ARM64_STRESS=ON), OR
#   (b) Guard it behind a conditional that respects OG_LINUX_ARM64.
# Either is valid. We enforce semantically: the toolchain file must
# mention OG_LINUX_ARM64 somewhere (comment is fine — proves the author
# knew about the option) AND must NOT contain a top-level
# unconditional `set(OG_ARM64_STRESS ON CACHE BOOL "" FORCE)`.
grep -q 'OG_LINUX_ARM64' "$TOOLCHAIN_FILE" \
    || fail "$TOOLCHAIN_FILE doesn't mention OG_LINUX_ARM64 — toolchain not C1-aware"
python3 - "$TOOLCHAIN_FILE" <<'PYEOF' || fail "$TOOLCHAIN_FILE: 'set(OG_ARM64_STRESS ON ... FORCE)' still at top-level scope"
import re, sys
src = open(sys.argv[1]).read().splitlines()
depth = 0
for line in src:
    stripped = line.strip()
    if stripped.startswith("#"):
        continue
    if re.search(r'\bif\s*\(', stripped) and not re.search(r'\bendif\s*\(', stripped):
        depth += 1
        continue
    if re.search(r'\belseif\s*\(', stripped):
        continue
    if re.search(r'\belse\s*\(', stripped):
        continue
    if re.search(r'\bendif\s*\(', stripped):
        depth = max(0, depth - 1)
        continue
    if depth == 0:
        if re.search(r'set\s*\(\s*OG_ARM64_STRESS\s+ON\s+CACHE\s+BOOL\b.*FORCE\s*\)', line):
            print(f"top-level forcing: {line!r}")
            sys.exit(1)
sys.exit(0)
PYEOF
ok "toolchain file generalised — mentions OG_LINUX_ARM64, no top-level OG_ARM64_STRESS force"

# ---- 3. Root CMakeLists.txt exposes + diverts on OG_LINUX_ARM64 ----
grep -qE '^[[:space:]]*option\(OG_LINUX_ARM64' "$ROOT_CMAKE" \
    || fail "$ROOT_CMAKE does not define option(OG_LINUX_ARM64 ...)"
grep -qE 'if[[:space:]]*\([[:space:]]*OG_LINUX_ARM64' "$ROOT_CMAKE" \
    || fail "$ROOT_CMAKE has no if(OG_LINUX_ARM64) divert branch"
grep -qE 'add_subdirectory\([[:space:]]*game/linux-arm64' "$ROOT_CMAKE" \
    || fail "$ROOT_CMAKE does not add_subdirectory(game/linux-arm64) under OG_LINUX_ARM64"
ok "root CMakeLists exposes OG_LINUX_ARM64 and diverts on it"

# ---- 4. game/linux-arm64/CMakeLists.txt structure ----
grep -qE 'add_executable\([[:space:]]*gk' "$LINUX_ARM64_CMAKE" \
    || fail "$LINUX_ARM64_CMAKE has no add_executable(gk ...)"
# Must compile real upstream kernel files (not synthesised TUs).
for need in 'kmalloc.cpp' 'kscheme.cpp' 'klisten.cpp' 'kdgo.cpp'; do
    grep -q "$need" "$LINUX_ARM64_CMAKE" \
        || fail "$LINUX_ARM64_CMAKE does not reference $need"
done
# Must include the asm trampoline.
grep -qE 'asm_funcs_arm64' "$LINUX_ARM64_CMAKE" \
    || fail "$LINUX_ARM64_CMAKE does not include the aarch64 asm trampoline"
ok "linux-arm64 CMakeLists references real upstream kernel sources"

# ---- 5. c1_configure.sh works and is honest ----
echo "  running c1_configure.sh (clean reconfigure)..."
rm -rf "$BUILD_DIR"
"$CFG_SCRIPT" > /tmp/c1-configure.log 2>&1 \
    || { tail -40 /tmp/c1-configure.log; fail "c1_configure.sh failed"; }
[ -f "$BUILD_DIR/CMakeCache.txt" ] || fail "$BUILD_DIR/CMakeCache.txt not produced"
# Sanity-check the cache values.
grep -qE '^OG_LINUX_ARM64:BOOL=ON$'   "$BUILD_DIR/CMakeCache.txt" \
    || fail "CMakeCache: OG_LINUX_ARM64 != ON"
grep -qE '^CMAKE_TOOLCHAIN_FILE:FILEPATH=.*aarch64-linux-toolchain.cmake$' \
    "$BUILD_DIR/CMakeCache.txt" \
    || fail "CMakeCache: toolchain file not the aarch64 one"
ok "c1_configure.sh produces the expected CMakeCache"

# ---- 6. Build gk ----
echo "  building gk target (this may take a couple of minutes)..."
cmake --build "$BUILD_DIR" --target gk -j > /tmp/c1-build.log 2>&1 \
    || { tail -60 /tmp/c1-build.log; fail "cmake --build --target gk failed"; }
GK=$(find "$BUILD_DIR" -name gk -type f -executable | head -1)
[ -n "$GK" ] && [ -x "$GK" ] \
    || fail "no executable named gk found under $BUILD_DIR/"
ok "gk binary produced at $GK"

# ---- 7. file(1) reports aarch64 ELF ----
FILE_OUT=$(file "$GK")
echo "$FILE_OUT" | grep -qE 'ELF 64-bit LSB.*ARM aarch64' \
    || fail "file(1) does not report aarch64 ELF: $FILE_OUT"
ok "file(1): aarch64 ELF"

# ---- 8. Dynamic interpreter is glibc, not Bionic ----
# readelf prints e.g. `[Requesting program interpreter: /lib/ld-linux-aarch64.so.1]`
# — strip the trailing `]` before comparing.
INTERP=$(readelf -l "$GK" 2>/dev/null | grep -oE '/[^]]*ld-[^]]*\.so[^]]*' | head -1)
INTERP="${INTERP%]}"
[ "$INTERP" = "/lib/ld-linux-aarch64.so.1" ] \
    || fail "interpreter is '$INTERP', expected /lib/ld-linux-aarch64.so.1"
ok "dynamic interpreter is /lib/ld-linux-aarch64.so.1 (glibc)"

# ---- 9. Stripped size ≥ 1 MB ----
STRIPPED=$(mktemp --suffix=.gk)
trap "rm -f $STRIPPED /tmp/c1-build.log /tmp/c1-configure.log /tmp/c1-configure2.log /tmp/c1-smoke.log" EXIT
cp "$GK" "$STRIPPED"
llvm-strip --strip-all "$STRIPPED" 2>/dev/null \
    || aarch64-linux-gnu-strip --strip-all "$STRIPPED" 2>/dev/null \
    || fail "could not strip $GK"
SIZE=$(stat -c %s "$STRIPPED")
[ "$SIZE" -ge 1048576 ] \
    || fail "stripped gk is $SIZE bytes (<1MB); cannot be a real kernel"
ok "stripped size $SIZE bytes ≥ 1MB"

# ---- 10. SHA-256 differs from goal_stress_arm64 ----
STRESS=$(find "$BUILD_DIR" -name goal_stress_arm64 -type f -executable | head -1)
if [ -n "$STRESS" ]; then
    GK_SHA=$(sha256sum "$STRIPPED"   | awk '{print $1}')
    SS_SHA=$(sha256sum "$STRESS"     | awk '{print $1}')
    [ "$GK_SHA" != "$SS_SHA" ] \
        || fail "gk SHA-256 == goal_stress_arm64 SHA-256 — gk is the stress harness renamed"
    ok "gk SHA-256 differs from goal_stress_arm64"
else
    ok "(no goal_stress_arm64 to compare against in this build dir)"
fi

# ---- 11. Required GOAL kernel symbols present ----
NM=$(command -v llvm-nm || command -v aarch64-linux-gnu-nm || true)
[ -n "$NM" ] || fail "neither llvm-nm nor aarch64-linux-gnu-nm available"
NM_TXT=$(mktemp); trap "rm -f $STRIPPED $NM_TXT /tmp/c1-*.log" EXIT
"$NM" --defined-only --demangle "$GK" > "$NM_TXT" 2>/dev/null \
    || fail "$NM failed on $GK"

# Require AT LEAST ONE symbol from each of these alternation groups.
need_one_of() {
    local label="$1"; shift
    for pat in "$@"; do
        if grep -qE "[[:space:]](${pat})\b" "$NM_TXT" \
           || grep -qE "[[:space:]](${pat})\(" "$NM_TXT" ; then
            ok "kernel symbol present: $label ($pat)"
            return 0
        fi
    done
    echo "missing $label — none of: $*" >&2
    return 1
}
miss=0
need_one_of "bump allocator"        'kmalloc'                                       || miss=1
need_one_of "scheme init"           'kscheme_init|init_output'                       || miss=1
need_one_of "listener init"         'klisten_init_globals|InitListenerConnect'       || miss=1
need_one_of "GOAL call trampoline"  'call_goal_on_stack|_call_goal_on_stack_asm_arm64|_call_goal_on_stack_asm' || miss=1
need_one_of "dgo init"              'kdgo_init_globals'                              || miss=1
need_one_of "master state"          'MasterExit|MasterUseKernel'                     || miss=1
[ $miss -eq 0 ] || fail "missing required GOAL kernel symbols (see above)"

# ---- 12. No synthetic-state patterns introduced since A4 ----
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
[ -n "$A4_COMMIT" ] || fail "could not locate A4 commit"
FORBIDDEN_PATTERNS='kStateSeq|kSyntheticBootSequence|weak_jak1_|synthetic.{0,3}gradient|engine: state=(boot|load|title)|placeholder render|kSolidColorOnly'
if git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
   | grep -E "^\+.*($FORBIDDEN_PATTERNS)" >/dev/null; then
    echo "Forbidden synthetic-state patterns introduced since A4:"
    git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
        | grep -nE "^\+.*($FORBIDDEN_PATTERNS)" | head -10
    fail "synthetic-state cheat detected"
fi
ok "no synthetic-state patterns introduced since A4"

# ---- 13. Codegen files byte-identical to A4 ----
for f in goalc/compiler/IR.cpp \
         goalc/emitter/IGenARM64.cpp \
         goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.cpp \
         goalc/emitter/ObjectGenerator.h; do
    if [ -f "$f" ]; then
        DIFF_LINES=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF_LINES" -eq 0 ] \
            || fail "$f changed since A4 (C1 must not touch codegen)"
    fi
done
ok "codegen files byte-identical to A4"

# ---- 14. Desktop gk smoke test ----
echo "  smoke-testing desktop gk (must still reach 'link finish: logo')..."
GK_DESKTOP="build-x86/game/gk"
[ -x "$GK_DESKTOP" ] || fail "$GK_DESKTOP missing — desktop oracle gone"
timeout 60 "$GK_DESKTOP" --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso \
    -- -boot -debug-mem > /tmp/c1-smoke.log 2>&1 || true
if ! grep -q "link finish: logo$" /tmp/c1-smoke.log; then
    echo "smoke log tail:"; tail -25 /tmp/c1-smoke.log
    fail "desktop gk did not reach 'link finish: logo'"
fi
ok "desktop gk smoke test still passes"

# ---- 15. C1-config.md headline ----
grep -qE 'gk[[:space:]]+binary|cross.toolchain|aarch64' "$REPORT_MD" \
    || fail "$REPORT_MD missing C1 headline section"
ok "C1-config.md headline present"

# ---- 16. Reconfigure idempotent ----
# CMake intentionally rewrites some cache TYPE tags on the second
# configure (e.g. FILEPATH → UNINITIALIZED when the value was passed in
# via -D and not re-typed). We don't care about the type tag for
# idempotency — only that the key's VALUE matches.
echo "  re-running c1_configure.sh for idempotency check..."
extract_cache_values() {
    grep -E '^(OG_LINUX_ARM64|OG_ARM64_STRESS|CMAKE_TOOLCHAIN_FILE|CMAKE_SYSTEM_NAME|CMAKE_SYSTEM_PROCESSOR|CMAKE_BUILD_TYPE):' "$1" \
        | sed -E 's/:[A-Z]+=/=/' | sort
}
CACHE_BEFORE=$(extract_cache_values "$BUILD_DIR/CMakeCache.txt")
"$CFG_SCRIPT" > /tmp/c1-configure2.log 2>&1 \
    || { tail -40 /tmp/c1-configure2.log; fail "second configure failed"; }
CACHE_AFTER=$(extract_cache_values "$BUILD_DIR/CMakeCache.txt")
[ "$CACHE_BEFORE" = "$CACHE_AFTER" ] \
    || { diff <(echo "$CACHE_BEFORE") <(echo "$CACHE_AFTER"); fail "CMakeCache key values drifted on reconfigure"; }
ok "reconfigure idempotent"

echo ""
echo "PASS: Phase C1 — build-arm64-linux configured, gk cross-built as aarch64 ELF."
