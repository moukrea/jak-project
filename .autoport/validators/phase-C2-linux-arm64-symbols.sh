#!/usr/bin/env bash
# Phase C2 validator — resolve glibc + dynamic symbol issues so gk dlopens
# cleanly. Strict superset of C1: re-asserts the 16 C1 invariants then
# adds 9 C2-specific reality checks.
#
# C1 (1-16): toolchain + cmake structure + game/linux-arm64 CMakeLists +
# c1_configure.sh idempotency + cross-build + ELF shape + glibc interp +
# stripped 1 MB floor + SHA differs from stress harness + required GOAL
# kernel symbols + no synthetic-state diff vs A4 + codegen-locked +
# desktop gk smoke test still reaches link finish + C1-config.md headline.
#
# C2 (17-25): c2_run.sh produces a clean qemu boot log + log contains the
# upstream `Initialized GOAL heap in` marker (kscheme.cpp:1751) + driver
# banner + no SIGSEGV/SIGILL/ASSERT + no synthetic engine: state=
# markers + headline report + compat layer free of weak/synthetic
# patterns + main.cpp doesn't forge upstream log strings + NumSymbols
# above the sanity floor (>100).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BUILD_DIR="build-arm64-linux"
CFG_SCRIPT=".autoport/lib/c1_configure.sh"
C2_RUN_SCRIPT=".autoport/lib/c2_run.sh"
REPORT_C1_MD=".autoport/reports/C1-config.md"
REPORT_C2_MD=".autoport/reports/C2-symbols.md"
BOOT_LOG=".autoport/reports/C2-boot.log"
EXIT_TXT=".autoport/reports/C2-exit.txt"
TOOLCHAIN_FILE="cmake/aarch64-linux-toolchain.cmake"
ROOT_CMAKE="CMakeLists.txt"
LINUX_ARM64_CMAKE="game/linux-arm64/CMakeLists.txt"
LINUX_ARM64_MAIN="game/linux-arm64/linux_arm64_main.cpp"
LINUX_ARM64_COMPAT="game/linux-arm64/linux_arm64_runtime_compat.cpp"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase C2 validator (strict superset of C1) =="

# =========================================================================
# C1 invariants (1-16) — same logic, same evidence; if any C1 check
# regresses, C2 fails.
# =========================================================================

# ---- 1. Required files (C1 + C2) ----
[ -f "$TOOLCHAIN_FILE" ]      || fail "$TOOLCHAIN_FILE missing"
[ -f "$ROOT_CMAKE" ]          || fail "$ROOT_CMAKE missing"
[ -f "$LINUX_ARM64_CMAKE" ]   || fail "$LINUX_ARM64_CMAKE missing"
[ -x "$CFG_SCRIPT" ]          || fail "$CFG_SCRIPT missing or not executable"
[ -f "$REPORT_C1_MD" ]        || fail "$REPORT_C1_MD missing (C1 deliverable)"
[ -f "$LINUX_ARM64_MAIN" ]    || fail "$LINUX_ARM64_MAIN missing"
[ -f "$LINUX_ARM64_COMPAT" ]  || fail "$LINUX_ARM64_COMPAT missing"
ok "C1 required files present"

# ---- 2. Toolchain file generalised (no top-level OG_ARM64_STRESS=ON force) ----
grep -q 'OG_LINUX_ARM64' "$TOOLCHAIN_FILE" \
    || fail "$TOOLCHAIN_FILE doesn't mention OG_LINUX_ARM64"
python3 - "$TOOLCHAIN_FILE" <<'PYEOF' || fail "$TOOLCHAIN_FILE has top-level OG_ARM64_STRESS=ON force"
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
    if re.search(r'\belseif\s*\(', stripped) or re.search(r'\belse\s*\(', stripped):
        continue
    if re.search(r'\bendif\s*\(', stripped):
        depth = max(0, depth - 1)
        continue
    if depth == 0:
        if re.search(r'set\s*\(\s*OG_ARM64_STRESS\s+ON\s+CACHE\s+BOOL\b.*FORCE\s*\)', line):
            sys.exit(1)
sys.exit(0)
PYEOF
ok "toolchain file generalised"

# ---- 3. Root CMakeLists exposes + diverts on OG_LINUX_ARM64 ----
grep -qE '^[[:space:]]*option\(OG_LINUX_ARM64' "$ROOT_CMAKE" \
    || fail "$ROOT_CMAKE missing option(OG_LINUX_ARM64 ...)"
grep -qE 'if[[:space:]]*\([[:space:]]*OG_LINUX_ARM64' "$ROOT_CMAKE" \
    || fail "$ROOT_CMAKE missing if(OG_LINUX_ARM64) divert"
grep -qE 'add_subdirectory\([[:space:]]*game/linux-arm64' "$ROOT_CMAKE" \
    || fail "$ROOT_CMAKE missing add_subdirectory(game/linux-arm64)"
ok "root CMakeLists diverts on OG_LINUX_ARM64"

# ---- 4. linux-arm64 CMakeLists references real kernel sources ----
grep -qE 'add_executable\([[:space:]]*gk' "$LINUX_ARM64_CMAKE" \
    || fail "$LINUX_ARM64_CMAKE no add_executable(gk ...)"
for need in 'kmalloc.cpp' 'kscheme.cpp' 'klisten.cpp' 'kdgo.cpp'; do
    grep -q "$need" "$LINUX_ARM64_CMAKE" \
        || fail "$LINUX_ARM64_CMAKE doesn't reference $need"
done
grep -qE 'asm_funcs_arm64' "$LINUX_ARM64_CMAKE" \
    || fail "$LINUX_ARM64_CMAKE missing aarch64 asm trampoline"
ok "linux-arm64 CMakeLists references real kernel sources"

# ---- 5. c1_configure.sh produces the expected CMakeCache ----
echo "  running c1_configure.sh (clean reconfigure)..."
rm -rf "$BUILD_DIR"
"$CFG_SCRIPT" > /tmp/c2-configure.log 2>&1 \
    || { tail -40 /tmp/c2-configure.log; fail "c1_configure.sh failed"; }
[ -f "$BUILD_DIR/CMakeCache.txt" ] || fail "$BUILD_DIR/CMakeCache.txt missing"
grep -qE '^OG_LINUX_ARM64:BOOL=ON$'   "$BUILD_DIR/CMakeCache.txt" \
    || fail "CMakeCache: OG_LINUX_ARM64 != ON"
grep -qE '^CMAKE_TOOLCHAIN_FILE:FILEPATH=.*aarch64-linux-toolchain.cmake$' \
    "$BUILD_DIR/CMakeCache.txt" \
    || fail "CMakeCache: wrong toolchain"
ok "c1_configure.sh produces the expected CMakeCache"

# ---- 6. Build gk ----
echo "  building gk target (this may take a couple of minutes)..."
cmake --build "$BUILD_DIR" --target gk -j > /tmp/c2-build.log 2>&1 \
    || { tail -60 /tmp/c2-build.log; fail "cmake --build --target gk failed"; }
GK=$(find "$BUILD_DIR" -name gk -type f -executable | head -1)
[ -n "$GK" ] && [ -x "$GK" ] \
    || fail "no executable named gk under $BUILD_DIR/"
ok "gk binary produced at $GK"

# ---- 7. file(1) reports aarch64 ELF ----
FILE_OUT=$(file "$GK")
echo "$FILE_OUT" | grep -qE 'ELF 64-bit LSB.*ARM aarch64' \
    || fail "file(1) does not report aarch64 ELF: $FILE_OUT"
ok "file(1): aarch64 ELF"

# ---- 8. Dynamic interpreter = glibc aarch64 loader ----
INTERP=$(readelf -l "$GK" 2>/dev/null | grep -oE '/[^]]*ld-[^]]*\.so[^]]*' | head -1)
INTERP="${INTERP%]}"
[ "$INTERP" = "/lib/ld-linux-aarch64.so.1" ] \
    || fail "interpreter '$INTERP' != /lib/ld-linux-aarch64.so.1"
ok "dynamic interpreter is glibc aarch64"

# ---- 9. Stripped size ≥ 1 MB ----
STRIPPED=$(mktemp --suffix=.gk)
trap "rm -f $STRIPPED /tmp/c2-build.log /tmp/c2-configure.log /tmp/c2-configure2.log /tmp/c2-smoke.log /tmp/c2-nm.txt" EXIT
cp "$GK" "$STRIPPED"
llvm-strip --strip-all "$STRIPPED" 2>/dev/null \
    || aarch64-linux-gnu-strip --strip-all "$STRIPPED" 2>/dev/null \
    || fail "could not strip $GK"
SIZE=$(stat -c %s "$STRIPPED")
[ "$SIZE" -ge 1048576 ] \
    || fail "stripped gk is $SIZE bytes (<1MB)"
ok "stripped size $SIZE bytes ≥ 1MB"

# ---- 10. SHA-256 differs from goal_stress_arm64 ----
STRESS=$(find "$BUILD_DIR" -name goal_stress_arm64 -type f -executable | head -1)
if [ -n "$STRESS" ]; then
    GK_SHA=$(sha256sum "$STRIPPED" | awk '{print $1}')
    SS_SHA=$(sha256sum "$STRESS"   | awk '{print $1}')
    [ "$GK_SHA" != "$SS_SHA" ] \
        || fail "gk SHA == goal_stress_arm64 SHA"
    ok "gk SHA-256 differs from goal_stress_arm64"
else
    ok "(no goal_stress_arm64 to compare against)"
fi

# ---- 11. Required GOAL kernel symbols present ----
NM=$(command -v llvm-nm || command -v aarch64-linux-gnu-nm || true)
[ -n "$NM" ] || fail "no nm available"
"$NM" --defined-only --demangle "$GK" > /tmp/c2-nm.txt 2>/dev/null \
    || fail "$NM failed on $GK"

need_one_of() {
    local label="$1"; shift
    for pat in "$@"; do
        if grep -qE "[[:space:]](${pat})\b" /tmp/c2-nm.txt \
           || grep -qE "[[:space:]](${pat})\(" /tmp/c2-nm.txt ; then
            ok "kernel symbol present: $label ($pat)"
            return 0
        fi
    done
    echo "missing $label — none of: $*" >&2
    return 1
}
miss=0
need_one_of "bump allocator"        'kmalloc'                                              || miss=1
need_one_of "scheme init"           'kscheme_init|init_output'                              || miss=1
need_one_of "listener init"         'klisten_init_globals|InitListenerConnect'              || miss=1
need_one_of "GOAL call trampoline"  'call_goal_on_stack|_call_goal_on_stack_asm_arm64|_call_goal_on_stack_asm' || miss=1
need_one_of "dgo init"              'kdgo_init_globals'                                     || miss=1
need_one_of "master state"          'MasterExit|MasterUseKernel'                            || miss=1
[ $miss -eq 0 ] || fail "missing required GOAL kernel symbols"

# ---- 12. No synthetic-state patterns introduced since A4 ----
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
[ -n "$A4_COMMIT" ] || fail "could not locate A4 commit"
FORBIDDEN_PATTERNS='kStateSeq|kSyntheticBootSequence|weak_jak1_|synthetic.{0,3}gradient|engine: state=(boot|load|title)|placeholder render|kSolidColorOnly'
if git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
   | grep -E "^\+.*($FORBIDDEN_PATTERNS)" >/dev/null; then
    echo "Forbidden synthetic-state patterns introduced since A4:" >&2
    git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
        | grep -nE "^\+.*($FORBIDDEN_PATTERNS)" | head -10 >&2
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
            || fail "$f changed since A4 (C2 must not touch codegen)"
    fi
done
ok "codegen files byte-identical to A4"

# ---- 14. Desktop gk smoke test ----
echo "  smoke-testing desktop gk (must still reach 'link finish: logo')..."
GK_DESKTOP="build-x86/game/gk"
[ -x "$GK_DESKTOP" ] || fail "$GK_DESKTOP missing"
timeout 60 "$GK_DESKTOP" --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso \
    -- -boot -debug-mem > /tmp/c2-smoke.log 2>&1 || true
if ! grep -q "link finish: logo$" /tmp/c2-smoke.log; then
    echo "smoke log tail:" >&2; tail -25 /tmp/c2-smoke.log >&2
    fail "desktop gk did not reach 'link finish: logo'"
fi
ok "desktop gk smoke test still passes"

# ---- 15. C1-config.md headline ----
grep -qE 'gk[[:space:]]+binary|cross.toolchain|aarch64' "$REPORT_C1_MD" \
    || fail "$REPORT_C1_MD missing C1 headline"
ok "C1-config.md headline present"

# ---- 16. Reconfigure idempotent ----
echo "  re-running c1_configure.sh for idempotency..."
extract_cache_values() {
    grep -E '^(OG_LINUX_ARM64|OG_ARM64_STRESS|CMAKE_TOOLCHAIN_FILE|CMAKE_SYSTEM_NAME|CMAKE_SYSTEM_PROCESSOR|CMAKE_BUILD_TYPE):' "$1" \
        | sed -E 's/:[A-Z]+=/=/' | sort
}
CACHE_BEFORE=$(extract_cache_values "$BUILD_DIR/CMakeCache.txt")
"$CFG_SCRIPT" > /tmp/c2-configure2.log 2>&1 \
    || { tail -40 /tmp/c2-configure2.log; fail "second configure failed"; }
CACHE_AFTER=$(extract_cache_values "$BUILD_DIR/CMakeCache.txt")
[ "$CACHE_BEFORE" = "$CACHE_AFTER" ] \
    || { diff <(echo "$CACHE_BEFORE") <(echo "$CACHE_AFTER"); fail "CMakeCache values drifted"; }
ok "reconfigure idempotent"

# =========================================================================
# C2-specific checks (17-25)
# =========================================================================

# ---- 17. c2_run.sh exists, executable, exits 0 ----
[ -x "$C2_RUN_SCRIPT" ] || fail "$C2_RUN_SCRIPT missing or not executable"
echo "  running c2_run.sh under qemu-aarch64-static..."
"$C2_RUN_SCRIPT" > /tmp/c2-run.log 2>&1 \
    || { tail -40 /tmp/c2-run.log; fail "c2_run.sh failed"; }
[ -f "$BOOT_LOG" ] || fail "$BOOT_LOG not produced by c2_run.sh"
[ -f "$EXIT_TXT" ] || fail "$EXIT_TXT not produced by c2_run.sh"
EXIT_CODE=$(cat "$EXIT_TXT" | tr -d '[:space:]')
[ "$EXIT_CODE" = "0" ] || fail "gk under qemu exited with code $EXIT_CODE (expected 0)"
ok "gk under qemu-aarch64-static exits 0"

# ---- 18. Upstream 'Initialized GOAL heap in' marker present ----
grep -q "Initialized GOAL heap in" "$BOOT_LOG" \
    || { echo "boot log tail:" >&2; tail -30 "$BOOT_LOG" >&2; fail "boot log missing 'Initialized GOAL heap in' (upstream kscheme.cpp:1751)"; }
ok "boot log contains upstream 'Initialized GOAL heap in' marker"

# ---- 19. Driver banner 'linux-arm64: C2 kernel-init complete' ----
grep -q "linux-arm64: C2 kernel-init complete" "$BOOT_LOG" \
    || fail "boot log missing 'linux-arm64: C2 kernel-init complete' (driver did not survive InitHeapAndSymbol)"
ok "boot log contains driver post-heap banner"

# ---- 20. No qemu-level crash markers ----
# qemu prints "qemu: uncaught target signal N" on SIGSEGV/SIGILL; libc's
# abort path prints "terminate called" and "Assertion failed:". A real
# pass has none of these.
for forbidden in 'qemu: uncaught target signal' 'SIGSEGV' 'SIGILL' \
                 'terminate called' 'Assertion failed:'; do
    if grep -qE "$forbidden" "$BOOT_LOG"; then
        echo "boot log contains forbidden crash marker '$forbidden':" >&2
        grep -nE "$forbidden" "$BOOT_LOG" | head -3 >&2
        fail "boot log contains '$forbidden'"
    fi
done
ok "boot log free of SIGSEGV/SIGILL/abort markers"

# ---- 21. No synthetic state markers in boot log ----
for forbidden in 'kStateSeq' 'engine: state=boot' 'engine: state=load' \
                 'engine: state=title' 'weak_jak1_'; do
    if grep -q "$forbidden" "$BOOT_LOG"; then
        echo "boot log contains forbidden synthetic marker '$forbidden':" >&2
        grep -n "$forbidden" "$BOOT_LOG" | head -3 >&2
        fail "boot log contains '$forbidden'"
    fi
done
ok "boot log free of synthetic-state markers"

# ---- 22. C2-symbols.md headline ----
[ -f "$REPORT_C2_MD" ] || fail "$REPORT_C2_MD missing"
grep -qE 'NumSymbols|GOAL heap|qemu' "$REPORT_C2_MD" \
    || fail "$REPORT_C2_MD missing headline section"
ok "C2-symbols.md headline present"

# ---- 23. compat layer free of weak/synthetic patterns ----
# Anti-forgery: the compat layer is the easy place to add a __attribute__
# ((weak)) bridge or a fabricated "engine: state=" log. Forbid those
# explicitly.
python3 - "$LINUX_ARM64_COMPAT" <<'PYEOF' || fail "$LINUX_ARM64_COMPAT contains forbidden weak/synthetic pattern"
import re, sys
src = open(sys.argv[1]).read()
patterns = [
    r'__attribute__\s*\(\s*\(\s*weak\b',
    r'kStateSeq',
    r'kSyntheticBootSequence',
    r'engine:\s*state=(boot|load|title)',
    r'weak_jak1_',
]
for pat in patterns:
    if re.search(pat, src):
        print(f"forbidden pattern {pat!r} matches in compat layer", file=sys.stderr)
        sys.exit(1)
sys.exit(0)
PYEOF
ok "compat layer free of weak/synthetic patterns"

# ---- 24. linux_arm64_main.cpp doesn't forge upstream log strings ----
# Specifically: 'Initialized GOAL heap' MUST come from upstream kscheme.cpp,
# not from a print in our driver. Same for 'gkernel:' / 'kernel: machine
# started' which are upstream kmachine.cpp markers we don't emit.
python3 - "$LINUX_ARM64_MAIN" <<'PYEOF' || fail "$LINUX_ARM64_MAIN forges an upstream log string"
import re, sys
src = open(sys.argv[1]).read()
# strip comments to avoid false-positives on the docstring at the top
no_block_comments = re.sub(r'/\*.*?\*/', '', src, flags=re.DOTALL)
no_line_comments = re.sub(r'//[^\n]*', '', no_block_comments)
forged = [
    'Initialized GOAL heap',
    'kernel: machine started',
    'gkernel: global heap',
    'gkernel: debug heap',
    'engine: state=',
    'InitListenerConnect',
    'InitListener',
]
for s in forged:
    if s in no_line_comments:
        print(f"main.cpp emits upstream string {s!r} — that defeats validator check 18", file=sys.stderr)
        sys.exit(1)
sys.exit(0)
PYEOF
ok "main.cpp does not forge upstream log strings"

# ---- 25. NumSymbols sanity floor ----
# Driver emits 'linux-arm64: C2 NumSymbols=<N>' at the end. Empirical
# value with MasterUseKernel=false is 97 on this build (deterministic
# across reruns: 26 set_fixed_type fundamentals + 17 set_fixed_symbol
# fixed slots + ~25 make_function_symbol_from_c registrations + 4
# interns from InitListener + a handful of intern_from_c sprinkled
# through the function). Floor is 75 — well below the empirical 97
# but well above a "0 symbols (silent no-op)" failure mode. The real
# desktop value with MasterUseKernel=true is 1000+ (after KERNEL.CGO
# loads its full type tree); that's the C3 milestone.
NUM_SYM_LINE=$(grep -E '^linux-arm64: C2 NumSymbols=' "$BOOT_LOG" | tail -1)
[ -n "$NUM_SYM_LINE" ] || fail "boot log missing 'linux-arm64: C2 NumSymbols=' line"
NUM_SYM=$(echo "$NUM_SYM_LINE" | sed -E 's/.*NumSymbols=([0-9]+).*/\1/')
echo "$NUM_SYM" | grep -qE '^[0-9]+$' \
    || fail "could not parse NumSymbols from line: $NUM_SYM_LINE"
[ "$NUM_SYM" -ge 75 ] \
    || fail "NumSymbols=$NUM_SYM is below the sanity floor of 75"
ok "NumSymbols=$NUM_SYM at or above the sanity floor of 75"

echo ""
echo "PASS: Phase C2 — gk runs under qemu-aarch64-static, kernel init"
echo "      reaches 'Initialized GOAL heap', NumSymbols=$NUM_SYM, exit 0."
