#!/usr/bin/env bash
# Phase A2 validator — verify real arm64 codegen for every jak1 blocker.
#
# Authored by the supervisor 2026-05-21 (see SUPERVISOR_JOURNAL.md).
# Checks the orchestrator's claude actually:
#  1. Captured pre-A2 baseline so we can detect x86 CGO drift
#  2. Did NOT modify any do_codegen_x86 bodies (anti-cheat)
#  3. Did NOT modify the classifier script (anti-cheat)
#  4. Re-ran classifier; every A1 blocker is now `real` or in carve-outs
#  5. Documented carve-out exceptions in .autoport/reports/A2-carve-outs.json
#  6. Desktop x86 build still works (goalc compiles, (mi) succeeds, gk
#     reaches link finish: logo with no SIGILL)
#  7. Spot-checked at least one new real implementation via aarch64
#     disasm of a smoke binary

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A1_JSON=".autoport/reports/A1-ir-inventory.json"
A2_INV_AFTER=".autoport/reports/A2-inventory-after.json"
A2_CARVE=".autoport/reports/A2-carve-outs.json"
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
IR_CPP="goalc/compiler/IR.cpp"
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"
BUILDER=".autoport/lib/build_a1_inventory.py"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A2 validator =="

# ---- 1. A1 inventory is present (this is our baseline + work list) ----
[ -f "$A1_JSON" ] || fail "$A1_JSON missing — A1 must pass before A2"
ok "A1 inventory available"

# ---- 2. A2 carve-outs JSON exists and only lists allowed exceptions ----
[ -f "$A2_CARVE" ] || fail "$A2_CARVE missing — every exception must be documented"
python3 <<PYEOF || fail "carve-outs schema invalid"
import json
allowed = {"IR_Null", "IR_ValueReset", "IR_Nop", "IR_AsmFNop", "IR_AsmFWait"}
d = json.load(open("$A2_CARVE"))
assert isinstance(d, dict), "A2-carve-outs.json must be an object"
assert "exceptions" in d, "missing 'exceptions' key"
exc = d["exceptions"]
assert isinstance(exc, list), "'exceptions' must be a list"
disallowed = []
for e in exc:
    assert isinstance(e, dict), f"each exception must be an object: {e}"
    assert "ir" in e and "reason" in e, f"each exception needs 'ir' and 'reason': {e}"
    if e["ir"] not in allowed:
        disallowed.append(e["ir"])
    if len(e["reason"]) < 20:
        disallowed.append(f"{e['ir']} (reason too short)")
if disallowed:
    raise SystemExit(f"disallowed or under-justified exceptions: {disallowed}")
print(f"  carve-outs: {len(exc)} exceptions, all allowed")
PYEOF
ok "carve-outs documented"

# ---- 3. Anti-cheat: do_codegen_x86 bodies untouched ----
# Diff from A1's commit landing onward; allow new functions but no edits
# inside any "::do_codegen_x86(" body.
A1_COMMIT=$(git log --format=%H --all --grep="\[autoport/A1-emitter-enumerate\] enumerate" | head -1)
[ -n "$A1_COMMIT" ] || A1_COMMIT=$(git log --format=%H --all --grep="A1-emitter-enumerate" | head -1)
[ -n "$A1_COMMIT" ] || fail "could not locate A1's landing commit for x86-untouched check"
X86_DIFF=$(git diff "$A1_COMMIT" -- "$IR_CPP" 2>/dev/null \
    | awk '/^@@/ {block=""} {block=block"\n"$0} /^-/ && /::do_codegen_x86/ {flag=1} END{if(flag) print "DIRTY"}')
# Stricter check: any context line containing "do_codegen_x86" + a "-" prefix line in same hunk?
DIRTY_HUNKS=$(git diff "$A1_COMMIT" -- "$IR_CPP" 2>/dev/null \
    | python3 -c "
import sys, re
hunks = []
cur = []
for line in sys.stdin:
    if line.startswith('@@'):
        if cur:
            hunks.append(''.join(cur))
        cur = [line]
    else:
        cur.append(line)
if cur:
    hunks.append(''.join(cur))

import re
func_pat = re.compile(r'void\s+\w+::do_codegen_(x86|arm64)\s*\(')

def hunk_modifies_x86(h):
    # Walk the hunk line by line tracking which function each line belongs
    # to. The hunk header's @@ context label only names the closest function
    # ABOVE the hunk's first content line — subsequent function transitions
    # inside the hunk body must be detected from the context (' '-prefixed)
    # and added-content ('+'-prefixed) lines themselves.
    in_x86 = False
    open_braces = 0
    body_started = False
    for line in h.splitlines():
        if line.startswith('@@'):
            m = func_pat.search(line)
            if m:
                in_x86 = (m.group(1) == 'x86')
                # The hunk starts inside a function whose opening brace
                # is already in scope.
                open_braces = 1
            else:
                in_x86 = False
                open_braces = 0
            continue
        if not line:
            continue
        prefix = line[0]
        body = line[1:] if prefix in ' +-' else line
        # Detect function-header transitions in context lines or in
        # added lines (a removed line transitioning a function is
        # unusual and not a case we need to handle here).
        m_func = func_pat.search(body)
        is_change = prefix in '+-' and not line.startswith(('+++', '---'))
        # Decide: did this change touch x86? Test BEFORE updating state on
        # function-header lines so that the header itself isn't classified
        # as "inside the previous function".
        if is_change and in_x86 and not m_func:
            return True
        # State updates from context lines and added lines:
        if prefix in ' +':
            if m_func:
                in_x86 = (m_func.group(1) == 'x86')
                open_braces = 0  # not yet inside the body
            # Track function-scope braces.
            opens = body.count('{')
            closes = body.count('}')
            if opens or closes:
                if open_braces == 0 and opens > 0:
                    open_braces = opens - closes
                else:
                    open_braces += opens - closes
                if open_braces <= 0:
                    open_braces = 0
                    in_x86 = False
    return False

dirty = []
for h in hunks:
    if hunk_modifies_x86(h):
        dirty.append(h.splitlines()[0])
print('\n'.join(dirty))
")
if [ -n "$DIRTY_HUNKS" ]; then
    echo "Hunks modifying x86 codegen:"
    echo "$DIRTY_HUNKS"
    fail "do_codegen_x86 bodies were modified — desktop oracle would break"
fi
ok "no do_codegen_x86 modifications"

# ---- 4. Anti-cheat: classifier script unchanged ----
CLASSIFIER_DIFF=$(git diff "$A1_COMMIT" -- "$CLASSIFIER" 2>/dev/null | wc -l)
if [ "$CLASSIFIER_DIFF" -gt 0 ]; then
    fail "$CLASSIFIER changed since A1 landed — reverting forbidden mid-phase. Diff:
$(git diff "$A1_COMMIT" -- "$CLASSIFIER" | head -30)"
fi
ok "classifier script unchanged"

# ---- 5. Re-run classifier + builder, get the updated inventory ----
[ -f "$BUILDER" ] || fail "$BUILDER missing"
[ -f "$CLASSIFIER" ] || fail "$CLASSIFIER missing"

# Determinism check
RUN1=$(python3 "$CLASSIFIER" "$IR_CPP" 2>/dev/null | sha256sum | awk '{print $1}')
RUN2=$(python3 "$CLASSIFIER" "$IR_CPP" 2>/dev/null | sha256sum | awk '{print $1}')
[ "$RUN1" = "$RUN2" ] || fail "$CLASSIFIER not deterministic"
ok "classifier still deterministic"

# ---- 6. Verify every A1 blocker is now `real` OR carved out ----
python3 <<PYEOF || fail "blocker coverage check failed"
import json, subprocess, sys
a1 = json.load(open("$A1_JSON"))
blockers = set(a1["summary"]["jak1_blockers"])

# Re-run classifier. The classifier emits a JSON object; parse it as JSON so
# keys/values are bare (the previous splitlines()/split() loop produced keys
# like '"IR_Foo":' which never matched the bare blocker names below).
out = subprocess.check_output(["python3", "$CLASSIFIER", "$IR_CPP"]).decode()
status_after = json.loads(out)

carve = json.load(open("$A2_CARVE"))
carved = {e["ir"] for e in carve["exceptions"]}

still_stub = []
for b in blockers:
    s = status_after.get(b, "missing")
    if s != "real" and b not in carved:
        still_stub.append((b, s))

if still_stub:
    print(f"Still-stub blockers ({len(still_stub)}):")
    for b, s in still_stub[:20]:
        print(f"  {b}: {s}")
    raise SystemExit(1)

real_count = sum(1 for s in status_after.values() if s == "real")
print(f"  classifier after A2: {real_count} real total; all {len(blockers)} A1 blockers covered (real or carved)")
PYEOF
ok "all A1 blockers now real or carved"

# ---- 7. Build goalc (x86 backend) ----
echo "  rebuilding goalc (x86 backend)..."
cmake --build build --target goalc -j8 > /tmp/A2-goalc-build.log 2>&1 \
    || fail "goalc x86 rebuild failed; tail:
$(tail -25 /tmp/A2-goalc-build.log)"
ok "goalc x86 built"

# ---- 8. Run (mi) — regenerate CGOs with the new goalc ----
echo "  running (mi) to regenerate CGOs..."
build/goalc/goalc --user-auto --game jak1 --disable-ansi -c "(mi)" > /tmp/A2-mi.log 2>&1 \
    || fail "(mi) regen failed; tail:
$(tail -25 /tmp/A2-mi.log)"
grep -qE "Successfully built all .+ targets" /tmp/A2-mi.log \
    || fail "(mi) completed without the success banner; tail:
$(tail -10 /tmp/A2-mi.log)"
ok "(mi) regen succeeded"

# ---- 9. Desktop gk smoke test ----
echo "  smoke-testing desktop gk (must reach 'link finish: logo' within 60s)..."
GK="build-x86/game/gk"
[ -x "$GK" ] || fail "$GK missing"
SMOKE_LOG=$(mktemp); trap "rm -f $SMOKE_LOG" EXIT
ISO_DIR="out/jak1/iso"
timeout 60 "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO_DIR" \
    -- -boot -debug-mem > "$SMOKE_LOG" 2>&1 || true
if ! grep -q "link finish: logo$" "$SMOKE_LOG"; then
    echo "smoke log tail:"
    tail -30 "$SMOKE_LOG"
    fail "desktop gk did not reach 'link finish: logo' — A2 broke x86 output"
fi
if grep -qE "Instruction non permise|Illegal" "$SMOKE_LOG"; then
    fail "desktop gk SIGILLed — A2 broke x86 emit (a shared-code edit?)"
fi
ok "desktop smoke test passed"

# ---- 10. Disasm spot-check — at least one new arm64 implementation
#         produces the expected real instructions.
#         The smoke file test/arm64/emitter_smoke_A2.gc compiled under
#         arm64 backend should contain LDR (for IR_LoadConstOffset) or
#         BL (for IR_FunctionCall) bytes when disassembled.
echo "  disasm spot-check (need either real LDR or BL in smoke arm64 output)..."
SMOKE_GC="test/arm64/emitter_smoke_A2.gc"
[ -f "$SMOKE_GC" ] || fail "$SMOKE_GC missing — A2 must include a per-cluster smoke file"

OBJDUMP=$(command -v aarch64-linux-gnu-objdump 2>/dev/null)
[ -x "$OBJDUMP" ] || fail "aarch64-linux-gnu-objdump not on PATH; spot-check requires it"

# Look for an aarch64 backend build artifact. Either build-arm64/goalc or
# a per-test .o produced by the phase. Be lenient about the path —
# claude documents it in A2-inventory-after.json or in
# A2-carve-outs.json's notes.
SMOKE_BIN=$(python3 -c "
import json, os
for k in ('A2_smoke_artifact', 'a2_smoke_artifact', 'smoke_artifact'):
    try:
        d = json.load(open('$A2_CARVE'))
        v = d.get('notes', {}).get(k) if isinstance(d.get('notes'), dict) else None
        if v and os.path.exists(v):
            print(v); break
    except Exception:
        pass
" 2>/dev/null)
if [ -z "$SMOKE_BIN" ] || [ ! -f "$SMOKE_BIN" ]; then
    # Fallback: scan likely locations
    for cand in test/arm64/build/emitter_smoke_A2.o test/arm64/out/emitter_smoke_A2.o \
                out/arm64/test/emitter_smoke_A2.o build-arm64/test/arm64/emitter_smoke_A2.o; do
        [ -f "$cand" ] && { SMOKE_BIN="$cand"; break; }
    done
fi
[ -n "$SMOKE_BIN" ] && [ -f "$SMOKE_BIN" ] \
    || fail "no smoke arm64 artifact found; document its path in A2-carve-outs.json's notes.A2_smoke_artifact"

DISASM=$("$OBJDUMP" -d --no-show-raw-insn "$SMOKE_BIN" 2>&1 || true)
[ -n "$DISASM" ] || fail "objdump produced no output on $SMOKE_BIN"

# Need at least one of LDR / STR / BL (real instructions A2 should emit)
if ! echo "$DISASM" | grep -qE "\b(ldr|str|bl|blr|fadd|fmul)\b"; then
    echo "Disassembly (head):"
    echo "$DISASM" | head -30
    fail "no LDR/STR/BL/FADD/FMUL in disasm — A2 didn't emit real arm64 instructions"
fi
ok "disasm spot-check found real arm64 instructions"

echo ""
echo "PASS: Phase A2 emitter implementation honest and complete."
