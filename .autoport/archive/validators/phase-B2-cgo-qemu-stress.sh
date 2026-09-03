#!/usr/bin/env bash
# Phase B2 validator — decode-stress every arm64 function under qemu.
# Authored by the supervisor 2026-05-21.
#
# Enforces:
#  1. B2-stress.json exists with the documented schema
#  2. summary.sigill == 0 (zero tolerance — any SIGILL is an encoder bug)
#  3. summary.sigsegv_in_prologue == 0
#  4. summary.disasm_clean == summary.total_functions
#  5. summary.total_functions matches B1's counts (sanity)
#  6. Per-CGO breakdown sums correctly
#  7. Harness reproducible (re-run, summary matches)
#  8. No codegen modifications since A4
#  9. Classifier still locked since A1
# 10. Desktop gk smoke test still passes

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

B1_STRUCT=".autoport/reports/B1-cgo-structure.json"
B2_JSON=".autoport/reports/B2-stress.json"
B2_MD=".autoport/reports/B2-stress.md"
DRIVER=".autoport/lib/b2_stress.sh"
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase B2 validator =="

# ---- 1. Required files ----
[ -f "$B1_STRUCT" ] || fail "$B1_STRUCT missing — B1 must have passed"
[ -f "$B2_JSON" ]   || fail "$B2_JSON missing"
[ -f "$B2_MD" ]     || fail "$B2_MD missing"
[ -x "$DRIVER" ]    || fail "$DRIVER missing or not executable"
ok "required files present"

# ---- 2. Schema check ----
python3 <<PYEOF || fail "B2 stress JSON schema invalid"
import json
d = json.load(open("$B2_JSON"))
assert d.get("phase") == "B2-cgo-qemu-stress", "phase tag wrong"
s = d["summary"]
for k in ("total_functions","tested_via_disasm","disasm_clean",
          "executed_under_qemu","exit_clean","sigsegv_post_prologue",
          "sigsegv_in_prologue","sigill","timeout","other"):
    assert k in s, f"summary missing '{k}'"
assert "per_cgo" in d and "failures" in d
print(f"  schema ok ({s['total_functions']} functions)")
PYEOF
ok "stress JSON schema valid"

# ---- 3. SIGILL count is zero ----
python3 <<PYEOF || fail "sigill > 0"
import json
d = json.load(open("$B2_JSON"))
s = d["summary"]
if s["sigill"] != 0:
    print(f"FAIL: sigill = {s['sigill']} (must be zero)")
    print("failures (first 10):")
    for f in d["failures"][:10]:
        if f.get("kind") == "sigill":
            print(" ", f)
    raise SystemExit(1)
PYEOF
ok "no SIGILL across all functions"

# ---- 4. SIGSEGV in prologue is zero ----
python3 <<PYEOF || fail "sigsegv_in_prologue > 0"
import json
d = json.load(open("$B2_JSON"))
s = d["summary"]
if s["sigsegv_in_prologue"] != 0:
    raise SystemExit(f"sigsegv_in_prologue = {s['sigsegv_in_prologue']} (must be zero)")
PYEOF
ok "no SIGSEGV in any prologue"

# ---- 5. disasm_clean == total_functions ----
python3 <<PYEOF || fail "disasm coverage incomplete"
import json
s = json.load(open("$B2_JSON"))["summary"]
if s["disasm_clean"] != s["total_functions"]:
    raise SystemExit(f"disasm_clean {s['disasm_clean']} != total {s['total_functions']}")
PYEOF
ok "every function disasms cleanly"

# ---- 6. total_functions matches B1 within tolerance ----
python3 <<PYEOF || fail "function count mismatch with B1"
import json
b1 = json.load(open("$B1_STRUCT"))
b2 = json.load(open("$B2_JSON"))
b1_total = sum(rec["function_count"] for rec in b1.values())
b2_total = b2["summary"]["total_functions"]
if abs(b1_total - b2_total) > 5:
    raise SystemExit(f"B1 count {b1_total} vs B2 count {b2_total} diverge")
if b2_total < 8000:
    raise SystemExit(f"B2 total {b2_total} < 8000 (too few functions tested)")
print(f"  B1={b1_total} B2={b2_total} ✓")
PYEOF
ok "function counts match B1 baseline"

# ---- 7. Per-CGO breakdown sums ----
python3 <<PYEOF || fail "per_cgo doesn't sum to summary"
import json
d = json.load(open("$B2_JSON"))
s = d["summary"]
for key in ("total_functions","disasm_clean","executed_under_qemu","sigill"):
    s_val = s[key]
    p_val = sum(d["per_cgo"][cgo].get(key, 0) for cgo in d["per_cgo"])
    if s_val != p_val:
        raise SystemExit(f"summary.{key}={s_val} != sum(per_cgo)={p_val}")
PYEOF
ok "per-CGO totals reconcile"

# ---- 8. Executed_under_qemu == total ----
python3 <<PYEOF || fail "not every function attempted under qemu"
import json
s = json.load(open("$B2_JSON"))["summary"]
if s["executed_under_qemu"] != s["total_functions"]:
    raise SystemExit(f"executed {s['executed_under_qemu']} != total {s['total_functions']}")
PYEOF
ok "every function attempted under qemu"

# ---- 9. Harness reproducibility (re-run, compare summary) ----
echo "  re-running harness for reproducibility..."
SPOT_JSON=$(mktemp --suffix=.json)
trap "rm -f $SPOT_JSON" EXIT
B2_OUT_JSON="$SPOT_JSON" "$DRIVER" > /tmp/B2-spot.log 2>&1 \
    || fail "harness re-run failed; tail:
$(tail -25 /tmp/B2-spot.log)"
[ -s "$SPOT_JSON" ] || fail "harness did not produce JSON at B2_OUT_JSON"

python3 <<PYEOF || fail "summary drift between original and spot run"
import json
o = json.load(open("$B2_JSON"))["summary"]
s = json.load(open("$SPOT_JSON"))["summary"]
diffs = []
for k in ("total_functions","disasm_clean","sigill",
          "sigsegv_in_prologue","executed_under_qemu"):
    if o[k] != s[k]:
        diffs.append(f"{k}: orig={o[k]} spot={s[k]}")
if diffs:
    print("Summary drift:")
    for d in diffs: print(" ", d)
    raise SystemExit(1)
PYEOF
ok "harness reproducible"

# ---- 10. Anti-cheat: codegen unchanged since A4 ----
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
[ -n "$A4_COMMIT" ] || fail "could not locate A4 commit"
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.cpp \
         goalc/emitter/IGenARM64.h goalc/emitter/ObjectGenerator.cpp \
         goalc/emitter/ObjectGenerator.h; do
    if [ -f "$f" ]; then
        DIFF=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF" -eq 0 ] || fail "$f modified since A4 (B2 must not touch codegen)"
    fi
done
ok "codegen files unchanged since A4"

# ---- 11. Classifier locked since A1 ----
A1_COMMIT=$(git log --format=%H --all --grep="\[autoport/A1-emitter-enumerate\] enumerate" | head -1)
CLF_DIFF=$(git diff "$A1_COMMIT" -- "$CLASSIFIER" 2>/dev/null | wc -l)
[ "$CLF_DIFF" -eq 0 ] || fail "$CLASSIFIER modified since A1"
ok "classifier still locked"

# ---- 12. Desktop gk smoke test ----
echo "  smoke-testing desktop gk..."
GK="build-x86/game/gk"
[ -x "$GK" ] || fail "$GK missing"
SMOKE_LOG=$(mktemp); trap "rm -f $SMOKE_LOG $SPOT_JSON" EXIT
timeout 60 "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data out/jak1/iso \
    -- -boot -debug-mem > "$SMOKE_LOG" 2>&1 || true
if ! grep -q "link finish: logo$" "$SMOKE_LOG"; then
    echo "smoke log tail:"
    tail -25 "$SMOKE_LOG"
    fail "desktop gk did not reach 'link finish: logo'"
fi
ok "desktop smoke test passed"

# ---- 13. Markdown headline ----
grep -qE "Decode-stressed [0-9]+ functions|SIGILL=0" "$B2_MD" \
    || fail "$B2_MD missing the required headline"
ok "Markdown headline present"

echo ""
echo "PASS: Phase B2 decode-stress complete; all arm64 functions execute under qemu."
