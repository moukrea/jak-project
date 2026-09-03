#!/usr/bin/env bash
# Phase A5 validator — emitter far-relocs implementation closes the C4
# 691-NOP gap. After this phase: 0 NOPs in the post-emit patcher report,
# CGOs regenerated with a far-reloc sequence (movz/movk chain or literal
# pool LDR), all cross-bucket validators (B1/B2/C2/C3/C4/D4) re-pass on
# the new bytecode, and the dodge-only C++ shims added in D4 are
# removed from android/android_runtime_compat.cpp.
#
# Authored by the supervisor 2026-05-21 23:35 after the user explicitly
# rejected the "route around" approach D4 used to reach the title
# milestone. The unlock is narrow: ONLY goalc/emitter/IGenARM64.cpp and
# goalc/emitter/ObjectGenerator.cpp may change in goalc/. All other
# codegen files (IR.cpp, IGenARM64.h, ObjectGenerator.h, CodeGenerator.*,
# classifier) must stay byte-identical to their respective lock anchors.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1_COMMIT=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
D3_COMMIT=$(git log --format=%H --all --grep='\[autoport/D3-android-sdl3-surface\] sustained swap loop' | head -1)
D4_COMMIT=$(git log --format=%H --all --grep='\[autoport/D4-android-apk-title\] wire real jak1 kmachine' | head -1)

A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A5_BASELINE=".autoport/reports/A5-baseline-arm64-cgo-hashes.txt"
SHIM_AUDIT=".autoport/reports/A5-shim-audit.md"
NOP_REPORT=".autoport/reports/A5-nop-report.txt"
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A5 validator (emitter far-relocs) =="

# ---- 1. Codegen unlock is narrow: only IGenARM64.cpp + ObjectGenerator.cpp ----
#
# Other goalc/ files must remain byte-identical to A4. The classifier
# must remain byte-identical to A1.
GOALC_CHANGED=$(git diff "$A4_COMMIT" HEAD --name-only -- goalc/ | sort -u)
EXPECTED_CHANGES="goalc/emitter/IGenARM64.cpp
goalc/emitter/ObjectGenerator.cpp"
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    DIFF=$(git diff "$A4_COMMIT" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A4 (codegen-lock violation)"
done
ok "locked goalc files byte-identical to A4 (only IGenARM64.cpp + ObjectGenerator.cpp permitted to change)"

CLF_DIFF=$(git diff "$A1_COMMIT" HEAD -- "$CLASSIFIER" 2>/dev/null | wc -l)
[ "$CLF_DIFF" -eq 0 ] || fail "$CLASSIFIER modified since A1 (classifier lock violation)"
ok "classifier byte-identical to A1"

# ---- 2. The two unlocked files MUST have changed (otherwise no work
#         was actually done) ----
IGEN_DIFF=$(git diff "$A4_COMMIT" HEAD -- goalc/emitter/IGenARM64.cpp 2>/dev/null | wc -l)
OBJG_DIFF=$(git diff "$A4_COMMIT" HEAD -- goalc/emitter/ObjectGenerator.cpp 2>/dev/null | wc -l)
[ "$IGEN_DIFF" -gt 0 ] || fail "goalc/emitter/IGenARM64.cpp not modified (the whole point of A5)"
[ "$OBJG_DIFF" -gt 0 ] || fail "goalc/emitter/ObjectGenerator.cpp not modified"
ok "IGenARM64.cpp and ObjectGenerator.cpp both have real diffs (IGen=$IGEN_DIFF lines, ObjG=$OBJG_DIFF lines)"

# ---- 3. CGOs regenerated; new arm64 baseline saved ----
[ -f "$A5_BASELINE" ] || fail "$A5_BASELINE missing (A5 must save the regenerated CGO hashes)"
ok "A5 arm64 CGO baseline file present"

# ---- 4. x86 CGOs remain byte-identical to A2 baseline ----
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == /* || "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO baseline drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline (the unlock only affects arm64 emission)"

# ---- 5. ZERO NOPs in the post-emit patcher report ----
[ -f "$NOP_REPORT" ] || fail "$NOP_REPORT missing (A5 must produce a per-CGO NOP count report)"
NOPS=$(awk '/^TOTAL_NOPS:/ {print $2}' "$NOP_REPORT")
[ -z "$NOPS" ] && fail "$NOP_REPORT format unrecognised; expected 'TOTAL_NOPS: <n>' line"
[ "$NOPS" -eq 0 ] || fail "still $NOPS NOPs in the patcher report (A5 goal: 0)"
ok "0 NOPs in patcher report across all CGOs"

# ---- 6. B1/B2/C2/C3/C4 still pass on the regenerated CGOs ----
for v in B1-cgo-regen B2-cgo-stress C2-runtime-build C3-runtime-link C4-klink-arm64-execute; do
    SCRIPT=".autoport/validators/phase-${v}.sh"
    [ -x "$SCRIPT" ] || { echo "  skip: $SCRIPT not present"; continue; }
    echo "  re-running $v validator..."
    "$SCRIPT" > "/tmp/a5-${v}.log" 2>&1 \
        || { tail -30 "/tmp/a5-${v}.log"; fail "$v validator failed on A5-regenerated CGOs"; }
    ok "$v re-validated on new bytecode"
done

# ---- 7. D4 re-runs (twice — before and after shim audit) ----
#
# First pass: D4 must still pass with the dodge-only shims still present
# (proves the new bytecode is at least as good as the old).
#
# After shim audit (step 8 below): D4 must still pass with the dodge
# shims removed (proves the bytecode actually does the work).
D4_VALIDATOR=".autoport/validators/phase-D4-android-apk-title.sh"
[ -x "$D4_VALIDATOR" ] || fail "$D4_VALIDATOR missing"

# Note: D4's existing validator does its own build+install+capture via
# .autoport/lib/d4_run.sh. We just invoke it here.
echo "  re-running D4 validator (pre-audit) on new bytecode..."
"$D4_VALIDATOR" > /tmp/a5-d4-pre.log 2>&1 \
    || { tail -50 /tmp/a5-d4-pre.log; fail "D4 validator failed on A5-regenerated CGOs (pre-audit) — new bytecode regressed"; }
ok "D4 still passes on A5-regenerated CGOs (pre-shim-audit)"

# ---- 8. Shim audit report present + lists dispositions ----
[ -f "$SHIM_AUDIT" ] || fail "$SHIM_AUDIT missing (A5 must produce a shim disposition report)"
grep -qE "^## " "$SHIM_AUDIT" || fail "$SHIM_AUDIT empty or malformed (no section headers)"
DELETED_SHIMS=$(grep -cE "^- DELETE:" "$SHIM_AUDIT" || true)
KEPT_SHIMS=$(grep -cE "^- KEEP:" "$SHIM_AUDIT" || true)
[ "$((DELETED_SHIMS + KEPT_SHIMS))" -gt 0 ] || fail "$SHIM_AUDIT contains no DELETE/KEEP entries"
ok "shim audit present: deleted=$DELETED_SHIMS kept=$KEPT_SHIMS"

# ---- 9. Compat shim file actually shrunk (dodge-only shims removed) ----
COMPAT_LINES_NOW=$(wc -l < android/android_runtime_compat.cpp)
COMPAT_LINES_D4=$(git show "$D4_COMMIT":android/android_runtime_compat.cpp 2>/dev/null | wc -l)
[ "$COMPAT_LINES_NOW" -lt "$COMPAT_LINES_D4" ] \
    || fail "android_runtime_compat.cpp did not shrink ($COMPAT_LINES_NOW now vs $COMPAT_LINES_D4 at D4 close — no dodge shims removed)"
ok "android_runtime_compat.cpp shrunk from $COMPAT_LINES_D4 to $COMPAT_LINES_NOW lines"

# ---- 10. D4 re-runs post-shim-audit ----
echo "  re-running D4 validator (post-audit) with trimmed compat layer..."
"$D4_VALIDATOR" > /tmp/a5-d4-post.log 2>&1 \
    || { tail -50 /tmp/a5-d4-post.log; fail "D4 validator failed after shim audit — bytecode does NOT actually cover the removed shims; A5 must restore them with documented justification or implement the missing emission"; }
ok "D4 still passes with trimmed compat layer (real bytecode covers what shims used to)"

# ---- 11. Anti-cheat: no new *_stubs.cpp, no abort, no weak since D3 ----
NEW_STUBS=$(git diff --name-only --diff-filter=A "$D3_COMMIT" HEAD | grep -E '_stubs\.cpp$' || true)
[ -z "$NEW_STUBS" ] || fail "new *_stubs.cpp files added since D3: $NEW_STUBS"
ok "no new *_stubs.cpp files since D3"

ABORTS_ADDED=$(git diff "$D3_COMMIT" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null \
    | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABORTS_ADDED" -eq 0 ] || fail "abort() additions in source since D3: $ABORTS_ADDED"
ok "no abort() additions in source since D3"

WEAK_ADDED=$(git diff "$D3_COMMIT" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null \
    | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK_ADDED" -eq 0 ] || fail "weak attribute additions since D3: $WEAK_ADDED"
ok "no weak attribute additions since D3"

# ---- 12. Desktop x86 smoke still works ----
echo "  desktop gk smoke (link finish: logo)..."
SMOKE_LOG=$(mktemp); trap "rm -f $SMOKE_LOG" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE_LOG" 2>&1 || true
if ! grep -q "link finish: logo$" "$SMOKE_LOG"; then
    tail -25 "$SMOKE_LOG"
    fail "desktop gk did not reach 'link finish: logo' on A5-regenerated CGOs"
fi
ok "desktop smoke test passes"

# ---- 13. asm_funcs_arm64.s SP-alignment fix from D4 preserved ----
grep -qE "and x10, x0, #-16" game/kernel/asm_funcs_arm64.s \
    || fail "D4's SP-alignment fix in asm_funcs_arm64.s is missing"
ok "D4's asm_funcs SP-alignment fix preserved"

echo ""
echo "PASS: Phase A5 — emitter emits real far-reloc sequences, 0 NOPs"
echo "      remaining, D4 boot path works on real bytecode without"
echo "      dodge shims, all cross-bucket validators re-passed."
