#!/usr/bin/env bash
# Phase A1 validator — verify the IR inventory is honest.
#
# Authored by the supervisor 2026-05-21 (see SUPERVISOR_JOURNAL.md).
# Checks the orchestrator's claude actually:
#  1. Produced a well-formed inventory JSON + Markdown
#  2. Counted ALL IR_* classes from IR.h (not a subset)
#  3. Classified each as real/stub/missing under honest definitions
#  4. Ran goalc with the new --ir-emit-stats flag (numbers match)
#  5. Didn't break the x86 desktop build (gk still reaches link finish: logo)

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

INVENTORY_JSON=".autoport/reports/A1-ir-inventory.json"
INVENTORY_MD=".autoport/reports/A1-ir-inventory.md"
IR_H="goalc/compiler/IR.h"
IR_CPP="goalc/compiler/IR.cpp"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A1 validator =="

# ---- 1. Files exist ----
[ -f "$INVENTORY_JSON" ] || fail "$INVENTORY_JSON missing"
[ -f "$INVENTORY_MD" ]   || fail "$INVENTORY_MD missing"
ok "inventory files present"

# ---- 2. JSON parses ----
python3 -c "import json,sys; json.load(open('$INVENTORY_JSON'))" \
    || fail "$INVENTORY_JSON does not parse"
ok "inventory JSON parses"

# ---- 3. Schema check ----
python3 <<PYEOF || fail "schema check failed"
import json, sys
d = json.load(open("$INVENTORY_JSON"))
assert "summary" in d, "missing 'summary'"
assert "by_form" in d, "missing 'by_form'"
s = d["summary"]
required_summary = {
    "total_ir_classes_declared", "arm64_real", "arm64_stub", "arm64_missing",
    "jak1_uses_at_least_one_emit", "jak1_blockers"
}
missing = required_summary - set(s.keys())
assert not missing, f"summary missing keys: {missing}"
assert isinstance(s["jak1_blockers"], list), "jak1_blockers must be a list"
for name, rec in d["by_form"].items():
    assert "arm64" in rec, f"{name} missing 'arm64' tag"
    assert rec["arm64"] in {"real", "stub", "missing"}, \
        f"{name}.arm64 invalid: {rec['arm64']}"
    assert "x86_emits_in_jak1" in rec, f"{name} missing 'x86_emits_in_jak1'"
    assert isinstance(rec["x86_emits_in_jak1"], int), \
        f"{name}.x86_emits_in_jak1 must be int"
    assert rec["x86_emits_in_jak1"] >= 0, \
        f"{name}.x86_emits_in_jak1 must be non-negative"
print(f"  schema ok ({len(d['by_form'])} forms)")
PYEOF

# ---- 4. Independent IR.h grep count must match summary.total_ir_classes_declared ----
INDEP_COUNT=$(grep -cE "^class IR_[A-Za-z0-9_]+ " "$IR_H")
DECL_COUNT=$(python3 -c "import json; print(json.load(open('$INVENTORY_JSON'))['summary']['total_ir_classes_declared'])")
if [ "$INDEP_COUNT" != "$DECL_COUNT" ]; then
    fail "total_ir_classes_declared=$DECL_COUNT but $IR_H has $INDEP_COUNT (^class IR_*)"
fi
ok "declared count matches IR.h ($INDEP_COUNT)"

# ---- 5. real + stub + missing == total ----
SUM=$(python3 -c "
import json
d = json.load(open('$INVENTORY_JSON'))['summary']
print(d['arm64_real'] + d['arm64_stub'] + d['arm64_missing'])
")
if [ "$SUM" != "$DECL_COUNT" ]; then
    fail "arm64_real+stub+missing=$SUM does not equal total=$DECL_COUNT"
fi
ok "real+stub+missing == total"

# ---- 6. blockers not empty (otherwise the claim is "emitter is done", which is false) ----
BLOCKER_COUNT=$(python3 -c "import json; print(len(json.load(open('$INVENTORY_JSON'))['summary']['jak1_blockers']))")
if [ "$BLOCKER_COUNT" = "0" ]; then
    fail "jak1_blockers is empty; the report claims the emitter is complete (which it isn't)"
fi
ok "blockers populated ($BLOCKER_COUNT)"

# ---- 7. Classifier script exists and runs deterministically ----
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"
[ -f "$CLASSIFIER" ] || fail "$CLASSIFIER missing (anti-cheat: deterministic classifier required)"
RUN1=$(python3 "$CLASSIFIER" "$IR_CPP" 2>/dev/null | sha256sum | awk '{print $1}')
RUN2=$(python3 "$CLASSIFIER" "$IR_CPP" 2>/dev/null | sha256sum | awk '{print $1}')
[ "$RUN1" = "$RUN2" ] || fail "$CLASSIFIER not deterministic across two runs"
[ -n "$RUN1" ] || fail "$CLASSIFIER produced no output"
ok "classifier deterministic"

# ---- 8. Re-run goalc with --ir-emit-stats and compare to JSON x86 counts ----
GOALC="build/goalc/goalc"
[ -x "$GOALC" ] || fail "$GOALC missing — rebuild goalc with your --ir-emit-stats flag first"
SPOTCHECK_JSON=$(mktemp --suffix=.json)
trap "rm -f $SPOTCHECK_JSON" EXIT

echo "  re-running goalc to spot-check usage counts (this takes ~12s)..."
"$GOALC" --user-auto --game jak1 --disable-ansi \
    --ir-emit-stats "$SPOTCHECK_JSON" \
    -c "(mi)" > /tmp/A1-validator-goalc.log 2>&1 \
    || fail "goalc spot-check run failed; tail of log:
$(tail -20 /tmp/A1-validator-goalc.log)"

[ -s "$SPOTCHECK_JSON" ] || fail "goalc did not produce $SPOTCHECK_JSON — --ir-emit-stats not wired"

python3 <<PYEOF || fail "spot-check comparison failed"
import json
inv = json.load(open("$INVENTORY_JSON"))["by_form"]
spot = json.load(open("$SPOTCHECK_JSON"))
# spot is expected to be a flat dict: {"IR_Return": {"x86": 12345, "arm64": 0}, ...}
# Be lenient about the exact spot shape but require comparable x86 counts.
mismatches = []
for name, rec in inv.items():
    expected = rec["x86_emits_in_jak1"]
    if name not in spot:
        # If a form has 0 uses in the spot, we tolerate it being absent.
        if expected != 0:
            mismatches.append(f"{name}: inventory says {expected}, spot has none")
        continue
    sv = spot[name]
    if isinstance(sv, dict):
        actual = sv.get("x86", 0)
    else:
        actual = sv
    # Allow +/-5% non-determinism
    diff = abs(actual - expected)
    tol = max(5, expected // 20)
    if diff > tol:
        mismatches.append(f"{name}: inventory {expected}, spot {actual} (diff {diff} > tol {tol})")
if mismatches:
    print("MISMATCHES:")
    for m in mismatches[:10]:
        print(" ", m)
    raise SystemExit(1)
print(f"  spot-check ok ({len(inv)} forms compared)")
PYEOF

# ---- 9. Markdown headline ----
grep -qE "IR forms used by jak1.*real arm64.*blocked" "$INVENTORY_MD" \
    || grep -qE "Of [0-9]+ IR forms.*[0-9]+ real" "$INVENTORY_MD" \
    || fail "$INVENTORY_MD missing the required headline ('Of N IR forms used by jak1, K have real arm64 codegen...')"
ok "Markdown headline present"

# ---- 10. gk smoke test — desktop did NOT break ----
# Note: gk invocation matches the supervisor's working capture_oracle.sh
# (--portable + -iso-data + `-debug-mem` rather than `-debug`). The
# Taskfile's plain `-v --game jak1 -- -boot -fakeiso -debug` form does
# not reliably reach `link finish: logo` within 60s in a fresh repo —
# `--portable` is required so gk's fakeiso resolves the right config
# dir, and `-debug-mem` is required because `-boot -debug` loads debug
# segments and jumps straight into the demo intro narration (the title
# logo level isn't relinked in that path). Supervisor revision
# 2026-05-21 09:30, refined 2026-05-21 09:35.
echo "  smoke-testing desktop gk (must reach 'link finish: logo' within 60s)..."
GK="build-x86/game/gk"
[ -x "$GK" ] || fail "$GK missing — was the desktop build wiped?"
SMOKE_LOG=$(mktemp); trap "rm -f $SMOKE_LOG $SPOTCHECK_JSON" EXIT

ISO_DIR="out/jak1/iso"
[ -d "$ISO_DIR" ] || fail "$ISO_DIR missing — (mi) regen did not produce CGOs"
timeout 60 "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO_DIR" \
    -- -boot -debug-mem > "$SMOKE_LOG" 2>&1 || true
if ! grep -q "link finish: logo$" "$SMOKE_LOG"; then
    echo "smoke log tail:"
    tail -30 "$SMOKE_LOG"
    fail "desktop gk did not reach 'link finish: logo' — A1 instrumentation broke x86 output"
fi
if grep -qE "Instruction non permise|Illegal" "$SMOKE_LOG"; then
    fail "desktop gk SIGILLed — A1 instrumentation broke x86 emit"
fi
ok "desktop smoke test passed (gk reached title screen logo, no SIGILL)"

echo ""
echo "PASS: Phase A1 inventory honest and complete."
echo "      $BLOCKER_COUNT blockers identified for A2."
