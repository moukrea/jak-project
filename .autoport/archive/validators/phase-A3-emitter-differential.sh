#!/usr/bin/env bash
# Phase A3 validator — per-cluster arm64 differential vs x86 must pass.
#
# Authored by the supervisor 2026-05-21 (see SUPERVISOR_JOURNAL.md).
# Checks the orchestrator's claude actually:
#  1. Produced a complete A3-coverage.json covering every real IR
#  2. Has disasm_clean=true for every real IR (no exceptions)
#  3. Has qemu_executed=true + matches_x86=true for every non-skipped IR
#  4. The reloc_skipped list is bounded by A2's documented linker_followup
#  5. The harness is reproducible (re-running produces matching JSON)
#  6. Did NOT modify any codegen files (IR.cpp / IGenARM64.cpp /
#     CodeGenerator.cpp) since A2 landed
#  7. Desktop x86 build still works (gk reaches link finish: logo)

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A2_JSON=".autoport/reports/A2-inventory-after.json"
A2_CARVE=".autoport/reports/A2-carve-outs.json"
COV_JSON=".autoport/reports/A3-coverage.json"
COV_MD=".autoport/reports/A3-coverage.md"
HARNESS=".autoport/lib/build_a3_diff.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A3 validator =="

# ---- 1. Prereqs from A2 ----
[ -f "$A2_JSON" ]   || fail "$A2_JSON missing — A2 must pass before A3"
[ -f "$A2_CARVE" ]  || fail "$A2_CARVE missing"
[ -f "$COV_JSON" ]  || fail "$COV_JSON missing"
[ -f "$COV_MD" ]    || fail "$COV_MD missing"
[ -x "$HARNESS" ]   || fail "$HARNESS missing or not executable"
ok "A2 inputs + A3 outputs present"

# ---- 2. Schema check on coverage JSON ----
python3 <<PYEOF || fail "schema check failed"
import json
cov = json.load(open("$COV_JSON"))
assert "phase" in cov and cov["phase"] == "A3-emitter-differential", "wrong phase tag"
assert "summary" in cov and "by_ir" in cov, "missing summary/by_ir"
s = cov["summary"]
for k in ("real_ir_count", "tested_via_disasm", "qemu_executed",
          "matches_x86", "reloc_skipped", "other_skipped", "test_files"):
    assert k in s, f"summary missing '{k}'"
assert isinstance(s["reloc_skipped"], list)
assert isinstance(s["other_skipped"], list)
for name, rec in cov["by_ir"].items():
    for k in ("cluster", "test_file", "disasm_clean",
              "expected_mnemonics_present"):
        assert k in rec, f"{name} missing '{k}'"
    if rec.get("qemu_executed"):
        for k in ("matches_x86", "x86_result", "arm64_result"):
            assert k in rec, f"{name} executed but missing '{k}'"
    else:
        assert "skipped_reason" in rec, f"{name} not executed but no skipped_reason"
        assert "skipped_ref" in rec, f"{name} skipped but no skipped_ref"
print(f"  schema ok ({len(cov['by_ir'])} IR entries)")
PYEOF
ok "coverage JSON schema valid"

# ---- 3. Every real IR from A2 inventory has an entry ----
python3 <<PYEOF || fail "missing IR coverage"
import json
a2 = json.load(open("$A2_JSON"))
cov = json.load(open("$COV_JSON"))
real_irs = [ir for ir, st in a2["by_form"].items() if st == "real"]
missing = sorted(set(real_irs) - set(cov["by_ir"].keys()))
if missing:
    print("Missing from coverage:")
    for m in missing[:15]:
        print(" ", m)
    raise SystemExit(1)
print(f"  all {len(real_irs)} real IRs covered")
PYEOF
ok "every real IR covered"

# ---- 4. disasm_clean = true everywhere ----
python3 <<PYEOF || fail "disasm_clean must be true for every IR"
import json
cov = json.load(open("$COV_JSON"))
bad = [n for n, r in cov["by_ir"].items() if not r.get("disasm_clean")]
if bad:
    print("Disasm-dirty IRs (must all be true):")
    for b in bad[:15]:
        print(" ", b)
    raise SystemExit(1)
PYEOF
ok "all IRs have clean arm64 disasm"

# ---- 5. reloc_skipped subset of A2 linker_followup list ----
python3 <<PYEOF || fail "reloc_skipped violates A2's documented bound"
import json
cov = json.load(open("$COV_JSON"))
allowed = {
    "IR_GetSymbolValue", "IR_SetSymbolValue", "IR_LoadSymbolPointer",
    "IR_GetSymbolValueAsm", "IR_StaticVarLoad", "IR_StaticVarAddr",
    "IR_FunctionAddr",
}
skipped = set(cov["summary"]["reloc_skipped"])
extra = skipped - allowed
if extra:
    print("reloc_skipped contains IRs A2 did not document:")
    for e in sorted(extra):
        print(" ", e)
    raise SystemExit(1)
others = cov["summary"]["other_skipped"]
if others:
    print(f"other_skipped must be empty; got: {others}")
    raise SystemExit(1)
PYEOF
ok "reloc_skipped bounded by A2's linker_followup"

# ---- 6. Every non-skipped IR was qemu-executed AND matches x86 ----
python3 <<PYEOF || fail "qemu execute + match required for non-skipped IRs"
import json
cov = json.load(open("$COV_JSON"))
skipped = set(cov["summary"]["reloc_skipped"]) | set(cov["summary"]["other_skipped"])
bad = []
for n, r in cov["by_ir"].items():
    if n in skipped:
        continue
    if not r.get("qemu_executed"):
        bad.append((n, "not executed"))
    elif not r.get("matches_x86"):
        bad.append((n, f"x86={r.get('x86_result')} vs arm64={r.get('arm64_result')}"))
if bad:
    print("Non-skipped IRs failing execute-and-match:")
    for n, why in bad[:15]:
        print(f"  {n}: {why}")
    raise SystemExit(1)
PYEOF
ok "every non-skipped IR qemu-executes to the x86 result"

# ---- 7. Anti-cheat: no codegen edits since A2 ----
# Locate the A2 commit
A2_COMMIT=$(git log --format=%H --all --grep="autoport/A2-emitter-implement" | head -1)
[ -n "$A2_COMMIT" ] || fail "could not locate A2 landing commit"
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.cpp \
         goalc/emitter/IGenARM64.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/CodeGenerator.h; do
    if [ -f "$f" ]; then
        DIFF=$(git diff "$A2_COMMIT" -- "$f" 2>/dev/null | wc -l)
        if [ "$DIFF" -gt 0 ]; then
            echo "Codegen file modified since A2: $f"
            git diff --stat "$A2_COMMIT" -- "$f" | head -5
            fail "A3 must verify A2's codegen, not modify it"
        fi
    fi
done
ok "codegen files unchanged since A2"

# ---- 8. Harness reproducibility — re-run and diff key fields ----
echo "  re-running harness for reproducibility check..."
SPOT_JSON=$(mktemp --suffix=.json)
trap "rm -f $SPOT_JSON" EXIT
OUT_OVERRIDE_JSON="$SPOT_JSON" "$HARNESS" > /tmp/A3-harness-spot.log 2>&1 \
    || fail "harness re-run failed; tail:
$(tail -20 /tmp/A3-harness-spot.log)"
[ -s "$SPOT_JSON" ] || fail "harness did not produce JSON at OUT_OVERRIDE_JSON"

python3 <<PYEOF || fail "harness spot-check found drift"
import json
orig = json.load(open("$COV_JSON"))
spot = json.load(open("$SPOT_JSON"))
# Compare the by_ir disasm_clean + matches_x86 fields only — timestamps/log
# paths may legitimately differ.
diffs = []
for n in orig["by_ir"]:
    if n not in spot.get("by_ir", {}):
        diffs.append(f"{n}: missing in spot run")
        continue
    o, s = orig["by_ir"][n], spot["by_ir"][n]
    for k in ("disasm_clean", "qemu_executed", "matches_x86",
              "x86_result", "arm64_result"):
        if k in o and o.get(k) != s.get(k):
            diffs.append(f"{n}.{k}: orig={o.get(k)} spot={s.get(k)}")
if diffs:
    print("Drift between original and spot run:")
    for d in diffs[:15]:
        print(" ", d)
    raise SystemExit(1)
print(f"  spot run matches original ({len(orig['by_ir'])} IRs)")
PYEOF
ok "harness reproducible"

# ---- 9. Markdown headline ----
grep -qE "(real|of [0-9]+) IR forms.*disasm.*qemu.*x86" "$COV_MD" \
    || grep -qE "Of [0-9]+ real IR forms.*disasm-clean" "$COV_MD" \
    || fail "$COV_MD missing the required headline"
ok "Markdown headline present"

# ---- 10. Desktop gk smoke test still works ----
echo "  smoke-testing desktop gk (must reach 'link finish: logo' within 60s)..."
GK="build-x86/game/gk"
[ -x "$GK" ] || fail "$GK missing"
SMOKE_LOG=$(mktemp); trap "rm -f $SMOKE_LOG $SPOT_JSON" EXIT
ISO_DIR="out/jak1/iso"
timeout 60 "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO_DIR" \
    -- -boot -debug-mem > "$SMOKE_LOG" 2>&1 || true
if ! grep -q "link finish: logo$" "$SMOKE_LOG"; then
    echo "smoke log tail:"
    tail -30 "$SMOKE_LOG"
    fail "desktop gk did not reach 'link finish: logo' — A3 work broke x86"
fi
if grep -qE "Instruction non permise|Illegal" "$SMOKE_LOG"; then
    fail "desktop gk SIGILLed — A3 broke x86 emit"
fi
ok "desktop smoke test passed"

echo ""
echo "PASS: Phase A3 differential validation complete."
