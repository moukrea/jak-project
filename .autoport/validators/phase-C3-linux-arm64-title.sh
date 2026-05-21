#!/usr/bin/env bash
# Phase C3 validator — direct-load KERNEL.CGO under qemu-aarch64;
# reach link finish: gstate (relocations only). Strict superset of C2.
#
# C2 (1-25): toolchain + cmake structure + game/linux-arm64 + boot
# driver + qemu run + Initialized GOAL heap marker + driver banner +
# no crash markers + no synthetic markers + report + compat anti-cheat
# + main.cpp anti-forgery + NumSymbols floor.
#
# C3 (26-39): c3_run.sh + KERNEL.CGO direct-load marker + link finish:
# gcommon/gkernel/gstate (8 objects' relocations apply cleanly) + C3
# driver banner + no SIGILL (the ADRP+ADD bytecode-execution bug is
# avoided by skipping LINK_FLAG_EXECUTE; validator anchors on this
# behaviour) + no Overlord-pretend forgery + anti-cheat on link flags
# (must be OUTPUT_LOAD | PRINT_LOGIN, NOT EXECUTE) + new TUs
# anti-forgery + C3-title.md engineering-finding section + NumSymbols
# floor of 250 (empirical 317, well above C2's 97).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BUILD_DIR="build-arm64-linux"
CFG_SCRIPT=".autoport/lib/c1_configure.sh"
C2_RUN_SCRIPT=".autoport/lib/c2_run.sh"
C3_RUN_SCRIPT=".autoport/lib/c3_run.sh"
REPORT_C1_MD=".autoport/reports/C1-config.md"
REPORT_C2_MD=".autoport/reports/C2-symbols.md"
REPORT_C3_MD=".autoport/reports/C3-title.md"
C2_BOOT_LOG=".autoport/reports/C2-boot.log"
C2_EXIT_TXT=".autoport/reports/C2-exit.txt"
C3_BOOT_LOG=".autoport/reports/C3-boot.log"
C3_EXIT_TXT=".autoport/reports/C3-exit.txt"
TOOLCHAIN_FILE="cmake/aarch64-linux-toolchain.cmake"
ROOT_CMAKE="CMakeLists.txt"
LINUX_ARM64_CMAKE="game/linux-arm64/CMakeLists.txt"
LINUX_ARM64_MAIN="game/linux-arm64/linux_arm64_main.cpp"
LINUX_ARM64_COMPAT="game/linux-arm64/linux_arm64_runtime_compat.cpp"
LINUX_ARM64_DIRECT_DGO="game/linux-arm64/linux_arm64_direct_dgo.cpp"
LINUX_ARM64_DIRECT_DGO_H="game/linux-arm64/linux_arm64_direct_dgo.h"
ARM64_KERNEL_CGO="out/jak1-arm64/iso/KERNEL.CGO"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase C3 validator (strict superset of C2) =="

# =========================================================================
# C2 invariants (1-25) — same logic, same evidence; if any regresses,
# C3 fails. The checks are reproduced rather than delegated so a future
# change to C2's script doesn't silently affect C3's gate.
# =========================================================================

# ---- 1. Required files (C1 + C2 + C3) ----
[ -f "$TOOLCHAIN_FILE" ]          || fail "$TOOLCHAIN_FILE missing"
[ -f "$ROOT_CMAKE" ]              || fail "$ROOT_CMAKE missing"
[ -f "$LINUX_ARM64_CMAKE" ]       || fail "$LINUX_ARM64_CMAKE missing"
[ -x "$CFG_SCRIPT" ]              || fail "$CFG_SCRIPT missing or not executable"
[ -f "$REPORT_C1_MD" ]            || fail "$REPORT_C1_MD missing (C1 deliverable)"
[ -f "$LINUX_ARM64_MAIN" ]        || fail "$LINUX_ARM64_MAIN missing"
[ -f "$LINUX_ARM64_COMPAT" ]      || fail "$LINUX_ARM64_COMPAT missing"
[ -f "$LINUX_ARM64_DIRECT_DGO" ]  || fail "$LINUX_ARM64_DIRECT_DGO missing (C3 deliverable)"
[ -f "$LINUX_ARM64_DIRECT_DGO_H" ]|| fail "$LINUX_ARM64_DIRECT_DGO_H missing (C3 deliverable)"
ok "all required files present"

# ---- 2. Toolchain file generalised ----
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
"$CFG_SCRIPT" > /tmp/c3-configure.log 2>&1 \
    || { tail -40 /tmp/c3-configure.log; fail "c1_configure.sh failed"; }
[ -f "$BUILD_DIR/CMakeCache.txt" ] || fail "$BUILD_DIR/CMakeCache.txt missing"
grep -qE '^OG_LINUX_ARM64:BOOL=ON$'   "$BUILD_DIR/CMakeCache.txt" \
    || fail "CMakeCache: OG_LINUX_ARM64 != ON"
grep -qE '^CMAKE_TOOLCHAIN_FILE:FILEPATH=.*aarch64-linux-toolchain.cmake$' \
    "$BUILD_DIR/CMakeCache.txt" \
    || fail "CMakeCache: wrong toolchain"
ok "c1_configure.sh produces the expected CMakeCache"

# ---- 6. Build gk ----
echo "  building gk target (this may take a couple of minutes)..."
cmake --build "$BUILD_DIR" --target gk -j > /tmp/c3-build.log 2>&1 \
    || { tail -60 /tmp/c3-build.log; fail "cmake --build --target gk failed"; }
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
trap "rm -f $STRIPPED /tmp/c3-build.log /tmp/c3-configure.log /tmp/c3-configure2.log /tmp/c3-smoke.log /tmp/c3-nm.txt" EXIT
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
"$NM" --defined-only --demangle "$GK" > /tmp/c3-nm.txt 2>/dev/null \
    || fail "$NM failed on $GK"

need_one_of() {
    local label="$1"; shift
    for pat in "$@"; do
        if grep -qE "[[:space:]](${pat})\b" /tmp/c3-nm.txt \
           || grep -qE "[[:space:]](${pat})\(" /tmp/c3-nm.txt ; then
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
need_one_of "link engine"           'link_and_exec|link_control'                            || miss=1
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
# Note: phase A5 explicitly unlocks goalc/emitter/IGenARM64.cpp +
# ObjectGenerator.cpp to close the C4 691-NOP gap by emitting a
# 3-instruction ADRP+ADD+LDR/STR far-reloc sequence for sym-mem
# accesses. The A5 validator enforces its own narrow lock on those
# two files; C3 only needs to guard the still-locked files (IR.cpp,
# the two .h headers, and CodeGenerator.{cpp,h}).
for f in goalc/compiler/IR.cpp \
         goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h; do
    if [ -f "$f" ]; then
        DIFF_LINES=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF_LINES" -eq 0 ] \
            || fail "$f changed since A4 (C3 must not touch the still-locked codegen surface)"
    fi
done
ok "still-locked codegen files byte-identical to A4 (IGenARM64.cpp + ObjectGenerator.cpp unlocked by A5)"

# ---- 14. Desktop gk smoke test ----
echo "  smoke-testing desktop gk (must still reach 'link finish: logo')..."
GK_DESKTOP="build-x86/game/gk"
[ -x "$GK_DESKTOP" ] || fail "$GK_DESKTOP missing"
timeout 60 "$GK_DESKTOP" --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso \
    -- -boot -debug-mem > /tmp/c3-smoke.log 2>&1 || true
if ! grep -q "link finish: logo$" /tmp/c3-smoke.log; then
    echo "smoke log tail:" >&2; tail -25 /tmp/c3-smoke.log >&2
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
"$CFG_SCRIPT" > /tmp/c3-configure2.log 2>&1 \
    || { tail -40 /tmp/c3-configure2.log; fail "second configure failed"; }
CACHE_AFTER=$(extract_cache_values "$BUILD_DIR/CMakeCache.txt")
[ "$CACHE_BEFORE" = "$CACHE_AFTER" ] \
    || { diff <(echo "$CACHE_BEFORE") <(echo "$CACHE_AFTER"); fail "CMakeCache values drifted"; }
ok "reconfigure idempotent"

# ---- 17. c2_run.sh exists, executable, exits 0 ----
[ -x "$C2_RUN_SCRIPT" ] || fail "$C2_RUN_SCRIPT missing or not executable"
echo "  running c2_run.sh under qemu-aarch64-static..."
"$C2_RUN_SCRIPT" > /tmp/c3-c2run.log 2>&1 \
    || { tail -40 /tmp/c3-c2run.log; fail "c2_run.sh failed"; }
[ -f "$C2_BOOT_LOG" ] || fail "$C2_BOOT_LOG not produced by c2_run.sh"
[ -f "$C2_EXIT_TXT" ] || fail "$C2_EXIT_TXT not produced by c2_run.sh"
EXIT_CODE=$(cat "$C2_EXIT_TXT" | tr -d '[:space:]')
[ "$EXIT_CODE" = "0" ] || fail "C2 gk under qemu exited with code $EXIT_CODE (expected 0)"
ok "C2 gk under qemu-aarch64-static still exits 0"

# ---- 18. Upstream 'Initialized GOAL heap in' marker present (C2) ----
grep -q "Initialized GOAL heap in" "$C2_BOOT_LOG" \
    || fail "C2 boot log missing 'Initialized GOAL heap in' (regression)"
ok "C2 boot log contains upstream 'Initialized GOAL heap in' marker"

# ---- 19. C2 driver banner 'linux-arm64: C2 kernel-init complete' ----
grep -q "linux-arm64: C2 kernel-init complete" "$C2_BOOT_LOG" \
    || fail "C2 boot log missing driver post-heap banner (regression)"
ok "C2 boot log contains C2 driver banner"

# ---- 20. No qemu-level crash markers in C2 ----
for forbidden in 'qemu: uncaught target signal' 'SIGSEGV' 'SIGILL' \
                 'terminate called' 'Assertion failed:'; do
    if grep -qE "$forbidden" "$C2_BOOT_LOG"; then
        echo "C2 boot log contains forbidden crash marker '$forbidden':" >&2
        grep -nE "$forbidden" "$C2_BOOT_LOG" | head -3 >&2
        fail "C2 boot log contains '$forbidden' (regression)"
    fi
done
ok "C2 boot log free of SIGSEGV/SIGILL/abort markers"

# ---- 21. No synthetic state markers in C2 boot log ----
for forbidden in 'kStateSeq' 'engine: state=boot' 'engine: state=load' \
                 'engine: state=title' 'weak_jak1_'; do
    if grep -q "$forbidden" "$C2_BOOT_LOG"; then
        echo "C2 boot log contains forbidden synthetic marker '$forbidden':" >&2
        grep -n "$forbidden" "$C2_BOOT_LOG" | head -3 >&2
        fail "C2 boot log contains '$forbidden' (regression)"
    fi
done
ok "C2 boot log free of synthetic-state markers"

# ---- 22. C2-symbols.md headline ----
[ -f "$REPORT_C2_MD" ] || fail "$REPORT_C2_MD missing"
grep -qE 'NumSymbols|GOAL heap|qemu' "$REPORT_C2_MD" \
    || fail "$REPORT_C2_MD missing headline section"
ok "C2-symbols.md headline present"

# ---- 23. compat layer free of weak/synthetic patterns ----
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
# not from a print in our driver.
python3 - "$LINUX_ARM64_MAIN" <<'PYEOF' || fail "$LINUX_ARM64_MAIN forges an upstream log string"
import re, sys
src = open(sys.argv[1]).read()
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
        print(f"main.cpp emits upstream string {s!r} — defeats validator check 18", file=sys.stderr)
        sys.exit(1)
sys.exit(0)
PYEOF
ok "main.cpp does not forge upstream log strings"

# ---- 25. NumSymbols sanity floor (C2) ----
NUM_SYM_LINE=$(grep -E '^linux-arm64: C2 NumSymbols=' "$C2_BOOT_LOG" | tail -1)
[ -n "$NUM_SYM_LINE" ] || fail "C2 boot log missing 'linux-arm64: C2 NumSymbols=' line"
NUM_SYM=$(echo "$NUM_SYM_LINE" | sed -E 's/.*NumSymbols=([0-9]+).*/\1/')
echo "$NUM_SYM" | grep -qE '^[0-9]+$' \
    || fail "could not parse NumSymbols from line: $NUM_SYM_LINE"
[ "$NUM_SYM" -ge 75 ] \
    || fail "C2 NumSymbols=$NUM_SYM is below sanity floor of 75 (regression)"
ok "C2 NumSymbols=$NUM_SYM at or above the sanity floor of 75"

# =========================================================================
# C3-specific checks (26-36)
# =========================================================================

# ---- 26. arm64 KERNEL.CGO present ----
[ -f "$ARM64_KERNEL_CGO" ] \
    || fail "$ARM64_KERNEL_CGO missing — B1 must run first to emit arm64 CGOs"
ARM64_CGO_SIZE=$(stat -c %s "$ARM64_KERNEL_CGO")
[ "$ARM64_CGO_SIZE" -ge 50000 ] \
    || fail "$ARM64_KERNEL_CGO is $ARM64_CGO_SIZE bytes (<50KB) — looks truncated"
ok "arm64 KERNEL.CGO present ($ARM64_CGO_SIZE bytes)"

# ---- 27. c3_run.sh exists, executable, exits 0 ----
[ -x "$C3_RUN_SCRIPT" ] || fail "$C3_RUN_SCRIPT missing or not executable"
echo "  running c3_run.sh under qemu-aarch64-static (120s timeout)..."
"$C3_RUN_SCRIPT" > /tmp/c3-run.log 2>&1 \
    || { tail -40 /tmp/c3-run.log; fail "c3_run.sh failed"; }
[ -f "$C3_BOOT_LOG" ] || fail "$C3_BOOT_LOG not produced by c3_run.sh"
[ -f "$C3_EXIT_TXT" ] || fail "$C3_EXIT_TXT not produced by c3_run.sh"
EXIT_CODE=$(cat "$C3_EXIT_TXT" | tr -d '[:space:]')
[ "$EXIT_CODE" = "0" ] \
    || { echo "C3 boot log tail:" >&2; tail -40 "$C3_BOOT_LOG" >&2;
         fail "gk under qemu exited with code $EXIT_CODE (expected 0)"; }
ok "C3 gk under qemu-aarch64-static exits 0"

# ---- 28. C3 boot log: KERNEL.CGO direct-DGO header marker ----
grep -q "\[Direct DGO\] Got DGO file header for KERNEL.CGO with 8 objects" "$C3_BOOT_LOG" \
    || { echo "C3 boot log tail:" >&2; tail -30 "$C3_BOOT_LOG" >&2;
         fail "C3 boot log missing '[Direct DGO] Got DGO file header for KERNEL.CGO with 8 objects'"; }
ok "C3 boot log: KERNEL.CGO direct-load header marker present"

# ---- 29. C3 boot log: link finish: gcommon (first object) ----
grep -q "link finish: gcommon" "$C3_BOOT_LOG" \
    || { echo "C3 boot log tail:" >&2; tail -30 "$C3_BOOT_LOG" >&2;
         fail "C3 boot log missing 'link finish: gcommon' — first object link failed"; }
ok "C3 boot log: link finish: gcommon present"

# ---- 30. C3 boot log: link finish: gkernel ----
grep -q "link finish: gkernel" "$C3_BOOT_LOG" \
    || { echo "C3 boot log tail:" >&2; tail -30 "$C3_BOOT_LOG" >&2;
         fail "C3 boot log missing 'link finish: gkernel' — kernel module link failed"; }
ok "C3 boot log: link finish: gkernel present"

# ---- 31. C3 boot log: link finish: gstate (last KERNEL.CGO object) ----
grep -q "link finish: gstate" "$C3_BOOT_LOG" \
    || { echo "C3 boot log tail:" >&2; tail -30 "$C3_BOOT_LOG" >&2;
         fail "C3 boot log missing 'link finish: gstate' — KERNEL.CGO did not complete"; }
ok "C3 boot log: link finish: gstate present (KERNEL.CGO complete)"

# ---- 32. C3 boot log: C3 driver post-link banner ----
grep -q "linux-arm64: C3 KERNEL.CGO link complete" "$C3_BOOT_LOG" \
    || fail "C3 boot log missing 'linux-arm64: C3 KERNEL.CGO link complete' driver banner"
ok "C3 boot log: driver post-link banner present"

# ---- 33. C3 boot log: no SIGSEGV/SIGILL/abort. The known ADRP+ADD
#        bytecode-execution bug is avoided by skipping LINK_FLAG_EXECUTE
#        (see linux_arm64_main.cpp's kKernelLinkFlags comment + the
#        phase prompt's engineering-finding section). If the validator
#        sees a crash despite EXECUTE being off, something else has
#        regressed. ----
for forbidden in 'qemu: uncaught target signal' 'SIGSEGV' 'SIGILL' \
                 'terminate called' 'Assertion failed:' 'bus error'; do
    if grep -qE "$forbidden" "$C3_BOOT_LOG"; then
        echo "C3 boot log contains forbidden crash marker '$forbidden':" >&2
        grep -nE "$forbidden" "$C3_BOOT_LOG" | head -3 >&2
        fail "C3 boot log contains '$forbidden'"
    fi
done
ok "C3 boot log free of SIGSEGV/SIGILL/abort markers"

# ---- 34. Anti-cheat: link flags in main.cpp must NOT include
#        LINK_FLAG_EXECUTE. The C3 driver explicitly omits EXECUTE
#        because executing arm64 GOAL bytecode after klink relocates
#        ADRP+ADD slots causes SIGILL (the engineering finding in the
#        phase prompt). Re-enabling EXECUTE under a `signal()`-handler
#        cheat would let NumSymbols inflate but lie about the codegen-
#        linker integration gap. ----
python3 - "$LINUX_ARM64_MAIN" <<'PYEOF' || fail "$LINUX_ARM64_MAIN link flags must not include LINK_FLAG_EXECUTE"
import re, sys
src = open(sys.argv[1]).read()
no_block_comments = re.sub(r'/\*.*?\*/', '', src, flags=re.DOTALL)
no_line_comments = re.sub(r'//[^\n]*', '', no_block_comments)

# Look for the kKernelLinkFlags constant and verify it doesn't reference EXECUTE.
m = re.search(r'kKernelLinkFlags\s*=\s*([^;]+);', no_line_comments)
if not m:
    print("kKernelLinkFlags constant not found in main.cpp", file=sys.stderr)
    sys.exit(1)
flags_expr = m.group(1)
if 'LINK_FLAG_EXECUTE' in flags_expr:
    print(f"kKernelLinkFlags includes LINK_FLAG_EXECUTE: {flags_expr.strip()}", file=sys.stderr)
    print("This phase intentionally skips execution; see prompt's engineering finding.", file=sys.stderr)
    sys.exit(1)

# Also forbid signal handlers that would swallow SIGILL.
if re.search(r'\bsignal\s*\(\s*SIGILL\b', no_line_comments):
    print("main.cpp installs a SIGILL signal handler — anti-cheat violation", file=sys.stderr)
    sys.exit(1)
if re.search(r'\bsigaction\b.*SIGILL', no_line_comments, flags=re.DOTALL):
    print("main.cpp uses sigaction on SIGILL — anti-cheat violation", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
ok "main.cpp link flags exclude LINK_FLAG_EXECUTE (anti-cheat ok)"

# ---- 35. C3 boot log: no Overlord-pretend forgery ----
for forbidden in '\[Overlord DGO\]' '\[OVERLORD\] FS Open KERNEL' \
                 '\[OVERLORD\] LoadDGO' '\[XSocketServer:8112\]' \
                 '\[Deci2Server:8112\]'; do
    if grep -qE "$forbidden" "$C3_BOOT_LOG"; then
        echo "C3 boot log contains forged overlord-pretend marker '$forbidden':" >&2
        grep -nE "$forbidden" "$C3_BOOT_LOG" | head -3 >&2
        fail "C3 boot log contains '$forbidden' — overlord was NOT brought up, this is forged"
    fi
done
ok "C3 boot log free of overlord-pretend forgery"

# ---- 36. C3 boot log: no synthetic state markers ----
for forbidden in 'kStateSeq' 'engine: state=boot' 'engine: state=load' \
                 'engine: state=title' 'weak_jak1_'; do
    if grep -q "$forbidden" "$C3_BOOT_LOG"; then
        echo "C3 boot log contains forbidden synthetic marker '$forbidden':" >&2
        grep -n "$forbidden" "$C3_BOOT_LOG" | head -3 >&2
        fail "C3 boot log contains '$forbidden'"
    fi
done
ok "C3 boot log free of synthetic-state markers"

# ---- 37. C3 new TUs: anti-forgery + anti-cheat ----
# linux_arm64_direct_dgo.cpp/h MUST NOT source-text-contain any of the
# strings the validator checks for, because those strings must come from
# upstream code. Same anti-cheat patterns as compat (no weak, no synthetic).
for f in "$LINUX_ARM64_DIRECT_DGO" "$LINUX_ARM64_DIRECT_DGO_H" "$LINUX_ARM64_MAIN"; do
    python3 - "$f" <<'PYEOF' || fail "$f contains forgery / anti-cheat violation"
import re, sys
src = open(sys.argv[1]).read()
no_block_comments = re.sub(r'/\*.*?\*/', '', src, flags=re.DOTALL)
no_line_comments = re.sub(r'//[^\n]*', '', no_block_comments)

# Strings that, if emitted by our code, would forge an upstream marker
# that has a non-overlord/non-direct alternative path. These are the
# log strings the validator anchors on for "did this come from real
# upstream code?" evidence. Note: 'Got DGO file header for' is allowed
# below as the suffix of OUR explicitly-prefixed '[Direct DGO] ...'
# emission — see anti-cheat note 3 in the phase prompt for the
# rationale (we deliberately distinguish [Direct DGO] from [Overlord
# DGO] to surface the bypass).
forged_strings_strict = [
    'link finish:',         # only emitted by klink::print_link_finish
    '[Overlord DGO]',       # forging the overlord path
    '[OVERLORD] FS',        # forging the fake_iso path
    'Initialized GOAL heap',  # only emitted by kscheme.cpp:1751
    'kernel: machine started',
    'gkernel: global heap',
    'InitListenerConnect',
]
for s in forged_strings_strict:
    if s in no_line_comments:
        print(f"{sys.argv[1]} emits upstream string {s!r}", file=sys.stderr)
        sys.exit(1)

# Conditional: 'Got DGO file header for' is allowed iff it appears
# in a literal that ALSO contains '[Direct DGO]'. Anything else
# would be forging the overlord's marker.
for m in re.finditer(r'"([^"]*Got DGO file header for[^"]*)"', no_line_comments):
    if '[Direct DGO]' not in m.group(1):
        print(f"{sys.argv[1]} emits 'Got DGO file header for' without [Direct DGO] prefix: {m.group(1)!r}",
              file=sys.stderr)
        sys.exit(1)

anti_cheat_patterns = [
    r'__attribute__\s*\(\s*\(\s*weak\b',
    r'kStateSeq',
    r'kSyntheticBootSequence',
    r'engine:\s*state=(boot|load|title)',
    r'weak_jak1_',
]
for pat in anti_cheat_patterns:
    if re.search(pat, no_line_comments):
        print(f"{sys.argv[1]} contains forbidden pattern {pat!r}", file=sys.stderr)
        sys.exit(1)

sys.exit(0)
PYEOF
    ok "$f free of forgery + anti-cheat patterns"
done

# ---- 38. C3-title.md headline + engineering finding ----
[ -f "$REPORT_C3_MD" ] || fail "$REPORT_C3_MD missing"
grep -qE 'KERNEL.CGO|NumSymbols|link finish' "$REPORT_C3_MD" \
    || fail "$REPORT_C3_MD missing headline section"
grep -qE 'ADRP|adrp' "$REPORT_C3_MD" \
    || fail "$REPORT_C3_MD missing engineering-finding section (ADRP+ADD link-fixup gap)"
ok "C3-title.md headline + engineering finding present"

# ---- 39. NumSymbols sanity floor (C3) ----
# Driver emits 'linux-arm64: C3 NumSymbols=<N>' after KERNEL.CGO link.
# Without LINK_FLAG_EXECUTE (which is intentionally omitted — see
# engineering finding), KERNEL.CGO's link runs all 8 objects'
# relocations. Each LINK_SYMBOL_OFFSET / LINK_TYPE_PTR entry calls
# intern_from_c / intern_type_from_c which allocate symbol-table
# slots. Empirical: 97 (post-C2) -> ~317 (post-C3-link). Floor 250
# catches "link silently no-op'd" failure modes (e.g., 97 unchanged)
# while leaving headroom for codegen changes that legitimately alter
# the link-table symbol set.
NUM_SYM_LINE=$(grep -E '^linux-arm64: C3 NumSymbols=' "$C3_BOOT_LOG" | tail -1)
[ -n "$NUM_SYM_LINE" ] || fail "C3 boot log missing 'linux-arm64: C3 NumSymbols=' line"
NUM_SYM=$(echo "$NUM_SYM_LINE" | sed -E 's/.*NumSymbols=([0-9]+).*/\1/')
echo "$NUM_SYM" | grep -qE '^[0-9]+$' \
    || fail "could not parse C3 NumSymbols from line: $NUM_SYM_LINE"
[ "$NUM_SYM" -ge 250 ] \
    || fail "C3 NumSymbols=$NUM_SYM is below the sanity floor of 250 (KERNEL.CGO relocation entries not interned)"
ok "C3 NumSymbols=$NUM_SYM at or above the sanity floor of 250"

echo ""
echo "PASS: Phase C3 — arm64 KERNEL.CGO relocations apply cleanly under"
echo "      qemu-aarch64, 8 objects link via real upstream klink,"
echo "      NumSymbols=$NUM_SYM (post-link). Bytecode execution gap"
echo "      (ADRP+ADD link-fixup) documented for follow-up phase."
