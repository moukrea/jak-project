#!/usr/bin/env bash
# Phase A4 validator — verify arm64 link-time fix-ups land + re-run A3 cleanly.
#
# Authored by the supervisor 2026-05-21. Checks the orchestrator's claude
# actually:
#  1. Produced A4-coverage.json with empty reloc_skipped and full IR coverage
#  2. The 7 previously-skipped IR bodies now call link_instruction_*
#  3. ObjectGenerator widened with arm64 fix-up handling (new code visible)
#  4. Classifier still byte-identical (anti-cheat)
#  5. do_codegen_x86 bodies still untouched (anti-cheat)
#  6. kernel-symbol probe produces a stable nonzero value
#  7. Desktop x86 oracle still reaches link finish: logo

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A2_JSON=".autoport/reports/A2-inventory-after.json"
A3_JSON=".autoport/reports/A3-coverage.json"
A4_JSON=".autoport/reports/A4-coverage.json"
A4_MD=".autoport/reports/A4-coverage.md"
A4_PROBE=".autoport/reports/A4-kernel-probe.txt"
IR_CPP="goalc/compiler/IR.cpp"
OBJ_GEN_CPP="goalc/emitter/ObjectGenerator.cpp"
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A4 validator =="

# ---- 1. Prereqs ----
[ -f "$A2_JSON" ]  || fail "$A2_JSON missing — A2 must have passed"
[ -f "$A3_JSON" ]  || fail "$A3_JSON missing — A3 must have passed"
[ -f "$A4_JSON" ]  || fail "$A4_JSON missing — A4 must produce it"
[ -f "$A4_MD" ]    || fail "$A4_MD missing"
[ -f "$A4_PROBE" ] || fail "$A4_PROBE missing — kernel-symbol probe required"
ok "all required input/output files present"

# ---- 2. Schema check — A4 coverage matches A3's shape ----
python3 <<PYEOF || fail "A4 schema invalid"
import json
cov = json.load(open("$A4_JSON"))
assert cov.get("phase") == "A4-linker-fixups", "phase tag must be A4-linker-fixups"
assert "summary" in cov and "by_ir" in cov, "missing summary or by_ir"
s = cov["summary"]
for k in ("real_ir_count", "tested_via_disasm", "qemu_executed",
          "matches_x86", "reloc_skipped", "other_skipped", "test_files"):
    assert k in s, f"summary missing '{k}'"
for n, r in cov["by_ir"].items():
    assert "disasm_clean" in r and "qemu_executed" in r, f"{n} schema bad"
print(f"  schema ok ({len(cov['by_ir'])} entries)")
PYEOF
ok "coverage JSON schema valid"

# ---- 3. reloc_skipped and other_skipped both empty ----
python3 <<PYEOF || fail "skip lists must be empty after A4"
import json
cov = json.load(open("$A4_JSON"))
rs = cov["summary"]["reloc_skipped"]
os_ = cov["summary"]["other_skipped"]
if rs:
    print(f"reloc_skipped not empty: {rs}")
    raise SystemExit(1)
if os_:
    print(f"other_skipped not empty: {os_}")
    raise SystemExit(1)
PYEOF
ok "reloc_skipped and other_skipped both empty"

# ---- 4. Every real IR from A2 inventory qemu-executes + matches ----
python3 <<PYEOF || fail "not every real IR qemu-executes and matches"
import json
a2 = json.load(open("$A2_JSON"))
cov = json.load(open("$A4_JSON"))
real_irs = [ir for ir, st in a2["by_form"].items() if st == "real"]
bad = []
for ir in real_irs:
    r = cov["by_ir"].get(ir)
    if r is None:
        bad.append((ir, "missing from coverage"))
        continue
    if not r.get("disasm_clean"):
        bad.append((ir, "disasm not clean"))
        continue
    if not r.get("qemu_executed"):
        bad.append((ir, "not qemu-executed"))
        continue
    if not r.get("matches_x86"):
        bad.append((ir, f"x86={r.get('x86_result')} vs arm64={r.get('arm64_result')}"))
if bad:
    print("IRs failing post-A4 execute-and-match:")
    for n, why in bad[:15]:
        print(f"  {n}: {why}")
    raise SystemExit(1)
print(f"  all {len(real_irs)} real IRs qemu-execute and match")
PYEOF
ok "every real IR now passes full differential"

# ---- 5. The 7 previously-skipped IRs now call link_instruction_* ----
python3 <<'PYEOF' || fail "7 reloc-IRs must now call link_instruction_*"
import re, sys
targets = [
    "IR_GetSymbolValue", "IR_SetSymbolValue", "IR_LoadSymbolPointer",
    "IR_GetSymbolValueAsm", "IR_StaticVarLoad", "IR_StaticVarAddr",
    "IR_FunctionAddr",
]
src = open("goalc/compiler/IR.cpp").read()
missing = []
for t in targets:
    # Find the do_codegen_arm64 body (between '{' after fn header and the
    # matching '}' at depth 0). Take a generous slice and look for
    # link_instruction_ inside it — but exclude comment lines.
    m = re.search(r"^void\s+" + re.escape(t) + r"::do_codegen_arm64[^{]*\{",
                  src, re.M)
    if not m:
        missing.append(f"{t} (no arm64 body)")
        continue
    # Bracket-match
    i = m.end()
    depth = 1
    while i < len(src) and depth > 0:
        c = src[i]
        if c == '{': depth += 1
        elif c == '}': depth -= 1
        i += 1
    body = src[m.end():i]
    # Strip C++ // and /* */ comments before searching.
    body_nocomments = re.sub(r"//[^\n]*", "", body)
    body_nocomments = re.sub(r"/\*.*?\*/", "", body_nocomments, flags=re.S)
    if "link_instruction_" not in body_nocomments:
        missing.append(t)
if missing:
    print("IR bodies still missing link_instruction_* call:")
    for m in missing: print(f"  {m}")
    sys.exit(1)
print(f"  all 7 reloc-needing IRs now register their fix-ups")
PYEOF
ok "7 reloc-IR bodies now call link_instruction_*"

# ---- 6. ObjectGenerator widened — arm64 fix-up handling present ----
# Look for new switch cases / arm64-specific enum tags / bit-manipulation
# of imm12/imm21 fields.
A3_COMMIT=$(git log --format=%H --all --grep="autoport/A3-emitter-differential" | head -1)
[ -n "$A3_COMMIT" ] || fail "could not locate A3 landing commit"
OG_DIFF=$(git diff "$A3_COMMIT" -- "$OBJ_GEN_CPP" 2>/dev/null | wc -l)
if [ "$OG_DIFF" -le 5 ]; then
    fail "$OBJ_GEN_CPP diff vs A3 is only $OG_DIFF lines — too small to be a real arm64 fix-up widening"
fi
# Sanity grep
if ! grep -qE "imm12|imm21|arm64.*fixup|fixup.*arm64|LDR.*imm|ADRP|adrp" "$OBJ_GEN_CPP" 2>/dev/null; then
    fail "$OBJ_GEN_CPP doesn't reference arm64 immediate fix-up kinds — A4 work missing"
fi
ok "ObjectGenerator widened with arm64 fix-up handling"

# ---- 7. Anti-cheat: do_codegen_x86 untouched (use A2's hunk-walker) ----
DIRTY_HUNKS=$(git diff "$A3_COMMIT" -- "$IR_CPP" 2>/dev/null \
    | python3 -c "
import sys, re
hunks=[]
cur=[]
for line in sys.stdin:
    if line.startswith('@@'):
        if cur: hunks.append(''.join(cur))
        cur=[line]
    else:
        cur.append(line)
if cur: hunks.append(''.join(cur))
func_pat = re.compile(r'void\s+\w+::do_codegen_(x86|arm64)\s*\(')
def modifies_x86(h):
    in_x86 = False; open_braces=0
    for line in h.splitlines():
        if line.startswith('@@'):
            m = func_pat.search(line)
            in_x86 = bool(m and m.group(1)=='x86')
            open_braces = 1 if m else 0
            continue
        if not line: continue
        prefix = line[0]
        body = line[1:] if prefix in ' +-' else line
        m_func = func_pat.search(body)
        is_change = prefix in '+-' and not line.startswith(('+++','---'))
        if is_change and in_x86 and not m_func:
            return True
        if prefix in ' +':
            if m_func:
                in_x86 = (m_func.group(1) == 'x86')
                open_braces = 0
            opens = body.count('{'); closes = body.count('}')
            if opens or closes:
                if open_braces == 0 and opens > 0:
                    open_braces = opens - closes
                else:
                    open_braces += opens - closes
                if open_braces <= 0:
                    open_braces = 0; in_x86 = False
    return False
dirty=[h.splitlines()[0] for h in hunks if modifies_x86(h)]
print('\n'.join(dirty))
")
if [ -n "$DIRTY_HUNKS" ]; then
    echo "Hunks modifying x86 codegen:"
    echo "$DIRTY_HUNKS"
    fail "do_codegen_x86 bodies were modified — desktop oracle would break"
fi
ok "no do_codegen_x86 modifications"

# ---- 8. Classifier still byte-identical to A1's landing ----
A1_COMMIT=$(git log --format=%H --all --grep="\[autoport/A1-emitter-enumerate\] enumerate" | head -1)
[ -n "$A1_COMMIT" ] || fail "could not locate A1 landing commit"
CLF_DIFF=$(git diff "$A1_COMMIT" -- "$CLASSIFIER" 2>/dev/null | wc -l)
[ "$CLF_DIFF" -eq 0 ] || fail "$CLASSIFIER modified since A1 (must remain locked)"
ok "classifier still locked since A1"

# ---- 9. Kernel-symbol probe produces stable nonzero output ----
# Validator re-runs the probe and compares.
PROBE_SCRIPT=$(ls test/arm64/a4_kernel_probe* 2>/dev/null | head -1)
[ -n "$PROBE_SCRIPT" ] || fail "no test/arm64/a4_kernel_probe* found"

# Capture the original probe output
ORIG_PROBE=$(cat "$A4_PROBE")
[ -n "$ORIG_PROBE" ] || fail "$A4_PROBE is empty"
if ! echo "$ORIG_PROBE" | grep -qE "[1-9][0-9]*"; then
    fail "$A4_PROBE doesn't contain a nonzero integer; got:
$ORIG_PROBE"
fi

# The probe is documented in carve-outs/notes or A4-coverage; require its
# rerun script to be at test/arm64/build/a4_kernel_probe* or similar — if
# claude wrote a shell harness for it, run that. Otherwise just trust the
# stored output for now (A4 is the first phase to define this).
if [ -x ".autoport/lib/run_a4_probe.sh" ]; then
    SPOT_PROBE=$(.autoport/lib/run_a4_probe.sh 2>&1 || true)
    if [ "$ORIG_PROBE" != "$SPOT_PROBE" ]; then
        echo "Probe drift:"
        echo "orig: $ORIG_PROBE"
        echo "spot: $SPOT_PROBE"
        fail "kernel probe is not deterministic"
    fi
    ok "kernel probe nonzero + reproducible"
else
    ok "kernel probe nonzero (no rerun script; trusting stored output)"
fi

# ---- 10. Desktop gk smoke test ----
echo "  smoke-testing desktop gk..."
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
    fail "desktop gk did not reach 'link finish: logo' — A4 broke x86 output"
fi
if grep -qE "Instruction non permise|Illegal" "$SMOKE_LOG"; then
    fail "desktop gk SIGILLed — A4 broke x86 emit"
fi
ok "desktop smoke test passed"

echo ""
echo "PASS: Phase A4 linker fix-ups complete; arm64 emitter is now bucket-B ready."
