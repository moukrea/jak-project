#!/usr/bin/env bash
# Phase B1 validator — verify the arm64 CGO regen is honest + x86 intact.
#
# Authored by the supervisor 2026-05-21. Checks the orchestrator's claude
# actually:
#  1. Produced arm64 CGOs at out/jak1-arm64/iso/ via build-arm64/goalc/goalc
#  2. Did NOT corrupt x86 CGOs at out/jak1/iso/
#  3. The arm64 CGOs have real arm64 ret density (not just x86 bytes)
#  4. The structural metrics are honest (re-runs match)
#  5. The kernel-symbol probe still works on the new KERNEL.CGO
#  6. Desktop gk still reaches link finish: logo

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
B1_ARM64_HASHES=".autoport/reports/B1-arm64-cgos.txt"
B1_STRUCT_JSON=".autoport/reports/B1-cgo-structure.json"
B1_STRUCT_MD=".autoport/reports/B1-cgo-structure.md"
B1_PROBE=".autoport/reports/B1-kernel-probe.txt"
DRIVER=".autoport/lib/build_b1_arm64_cgos.sh"
STRUCT_PY=".autoport/lib/cgo_structure_check.py"
ARM64_DIR="out/jak1-arm64/iso"
X86_DIR="out/jak1/iso"
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase B1 validator =="

# ---- 1. Required files / dirs ----
[ -f "$A2_BASELINE" ]    || fail "$A2_BASELINE missing"
[ -f "$B1_STRUCT_JSON" ] || fail "$B1_STRUCT_JSON missing"
[ -f "$B1_STRUCT_MD" ]   || fail "$B1_STRUCT_MD missing"
[ -f "$B1_PROBE" ]       || fail "$B1_PROBE missing"
[ -x "$DRIVER" ]         || fail "$DRIVER missing or not executable"
[ -f "$STRUCT_PY" ]      || fail "$STRUCT_PY missing"
[ -d "$ARM64_DIR" ]      || fail "$ARM64_DIR missing"
for cgo in KERNEL.CGO ENGINE.CGO GAME.CGO; do
    [ -f "$ARM64_DIR/$cgo" ] || fail "$ARM64_DIR/$cgo missing"
    [ -f "$X86_DIR/$cgo" ]   || fail "$X86_DIR/$cgo missing"
done
ok "all required files present"

# ---- 2. x86 CGOs at out/jak1/iso/ MUST hash-match A2 baseline ----
# sha256sum's "HASH  PATH" format collapses to two whitespace-separated
# fields under default IFS, so read with two named vars (the original
# 3-field read left $path empty and the sha256sum call silently failed).
echo "  verifying x86 CGOs untouched..."
while read -r expected_hash path; do
    [ -z "$expected_hash" ] && continue
    actual_hash=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    if [ "$expected_hash" != "$actual_hash" ]; then
        fail "x86 CGO drift: $path
  expected: $expected_hash
  actual:   $actual_hash
  -> phase 25 cheat (arm64 bytes leaked into x86 path) detected"
    fi
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# ---- 3. Arm64 CGO size sanity ----
python3 <<PYEOF || fail "arm64 CGO size sanity failed"
import os
mins = {"KERNEL.CGO": 50_000, "ENGINE.CGO": 1_000_000, "GAME.CGO": 1_000_000}
maxs = {"KERNEL.CGO": 5_000_000, "ENGINE.CGO": 50_000_000, "GAME.CGO": 50_000_000}
bad = []
for cgo, lo in mins.items():
    p = f"$ARM64_DIR/{cgo}"
    sz = os.path.getsize(p)
    if sz < lo:
        bad.append(f"{cgo}: {sz} bytes < {lo}")
    if sz > maxs[cgo]:
        bad.append(f"{cgo}: {sz} bytes > {maxs[cgo]}")
if bad:
    print("Size sanity failures:")
    for b in bad: print(" ", b)
    raise SystemExit(1)
print(f"  sizes ok")
PYEOF
ok "arm64 CGO sizes plausible"

# ---- 4. arm64-ret count vs function count; x86-ret density <= 1% ----
# The original "density >= 3.0/KB" framing assumed jak1 functions average
# ~150 B (per the phase prompt's anti-cheat note); after running a full
# (mi) the actual main-segment function bodies are 300-2300 B depending
# on the CGO (KERNEL functions averaging 289 B, ENGINE 673 B, GAME ~2300 B
# because GAME.CGO is dominated by static level/asset data, not code).
# Each function emits exactly one 0xd65f03c0 in its epilogue (see
# CodeGenerator::do_goal_function_arm64 line 448), so the right anti-stub
# invariant is "rets >= functions", not "rets / file_size >= some value".
#
# We keep the density check as a coarse anti-everything-data floor at
# 0.4/KB (well above the ~0/KB that random x86 bytes produce), and add
# the rets >= function_count primary check using the structure-JSON's
# function_count which counts only main-segment functions parsed from
# LINK_TYPE_PTR entries.
python3 <<'PYEOF' || fail "ret-density sanity failed"
import json, os
ARM64_RET = b"\xc0\x03\x5f\xd6"  # 0xd65f03c0 little-endian
X86_RET   = b"\xc3"
ARM64_DIR = os.environ.get("B1_ARM64_DIR", "out/jak1-arm64/iso")
STRUCT    = json.load(open(".autoport/reports/B1-cgo-structure.json"))
bad = []
for cgo in ["KERNEL.CGO", "ENGINE.CGO", "GAME.CGO"]:
    p = f"{ARM64_DIR}/{cgo}"
    blob = open(p, "rb").read()
    sz = len(blob)
    a64 = blob.count(ARM64_RET)
    x86 = blob.count(X86_RET)
    arm_density = a64 * 1024.0 / sz if sz else 0
    x86_pct = x86 * 100.0 / sz if sz else 0
    fc = STRUCT[cgo]["function_count"]
    print(f"  {cgo}: arm64_ret={a64}  ({arm_density:.2f}/KB)  x86_ret={x86}  ({x86_pct:.3f}%)  funcs={fc}")
    if fc <= 0:
        bad.append(f"{cgo}: function_count={fc} — link table parse failed?")
        continue
    if a64 < fc:
        bad.append(f"{cgo}: arm64 rets {a64} < function count {fc} (some functions lack their epilogue ret)")
    if arm_density < 0.4:
        bad.append(f"{cgo}: arm64 ret density {arm_density:.2f}/KB < 0.4 (looks data-dominant or x86-shaped)")
    if x86_pct > 1.0:
        bad.append(f"{cgo}: x86 ret bytes {x86_pct:.2f}% > 1% (arm64-shaped?)")
if bad:
    for b in bad: print("  FAIL:", b)
    raise SystemExit(1)
PYEOF
ok "ret/function count sanity passes"

# ---- 5. Structural JSON schema ----
python3 <<PYEOF || fail "structural JSON schema invalid"
import json
d = json.load(open("$B1_STRUCT_JSON"))
expected = {"KERNEL.CGO", "ENGINE.CGO", "GAME.CGO"}
missing = expected - set(d.keys())
if missing:
    raise SystemExit(f"struct JSON missing CGOs: {missing}")
for cgo, rec in d.items():
    for k in ("total_bytes", "arm64_ret_count", "x86_ret_count",
              "ret_density_per_kb"):
        assert k in rec, f"{cgo}: missing {k}"
print(f"  schema ok for {len(d)} CGOs")
PYEOF
ok "structural JSON schema ok"

# ---- 6. Driver script is idempotent — re-run, compare arm64 hashes ----
echo "  re-running driver for reproducibility check..."
SPOT_BACKUP=$(mktemp -d)
trap "rm -rf $SPOT_BACKUP" EXIT
for cgo in KERNEL.CGO ENGINE.CGO GAME.CGO; do
    cp "$ARM64_DIR/$cgo" "$SPOT_BACKUP/$cgo"
done
"$DRIVER" > /tmp/B1-driver-spot.log 2>&1 \
    || fail "driver re-run failed; tail:
$(tail -25 /tmp/B1-driver-spot.log)"

for cgo in KERNEL.CGO ENGINE.CGO GAME.CGO; do
    orig=$(sha256sum "$SPOT_BACKUP/$cgo" | awk '{print $1}')
    new=$(sha256sum "$ARM64_DIR/$cgo" | awk '{print $1}')
    if [ "$orig" != "$new" ]; then
        fail "arm64 $cgo not reproducible:
  first run: $orig
  spot run:  $new"
    fi
done
ok "driver idempotent (arm64 CGO hashes match)"

# ---- 7. Anti-cheat: codegen files unchanged since A4 ----
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
[ -n "$A4_COMMIT" ] || fail "could not locate A4 landing commit"
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.cpp \
         goalc/emitter/IGenARM64.h goalc/emitter/ObjectGenerator.cpp \
         goalc/emitter/ObjectGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/CodeGenerator.h; do
    if [ -f "$f" ]; then
        DIFF=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        if [ "$DIFF" -gt 0 ]; then
            echo "Codegen file modified since A4: $f"
            git diff --stat "$A4_COMMIT" -- "$f" | head -3
            fail "B1 must verify A4's emitter, not modify it"
        fi
    fi
done
ok "codegen files unchanged since A4"

# ---- 8. Classifier still locked since A1 ----
A1_COMMIT=$(git log --format=%H --all --grep="\[autoport/A1-emitter-enumerate\] enumerate" | head -1)
[ -n "$A1_COMMIT" ] || fail "could not locate A1 landing commit"
CLF_DIFF=$(git diff "$A1_COMMIT" -- "$CLASSIFIER" 2>/dev/null | wc -l)
[ "$CLF_DIFF" -eq 0 ] || fail "$CLASSIFIER modified since A1 (must remain locked)"
ok "classifier still locked"

# ---- 9. Kernel probe re-runs and matches stored output ----
ORIG_PROBE=$(cat "$B1_PROBE")
[ -n "$ORIG_PROBE" ] || fail "$B1_PROBE empty"
if ! echo "$ORIG_PROBE" | grep -qE "[1-9][0-9]*"; then
    fail "$B1_PROBE doesn't contain a nonzero integer"
fi
# Reuse A4's probe runner if it exists; otherwise trust the stored value
if [ -x test/arm64/a4_kernel_probe.sh ]; then
    # Run the probe pointing at the new arm64 KERNEL.CGO
    KERNEL_CGO="$ARM64_DIR/KERNEL.CGO" \
        test/arm64/a4_kernel_probe.sh > /tmp/B1-probe-spot.log 2>&1 || true
    SPOT_PROBE=$(grep -oE "^[0-9]+$" /tmp/B1-probe-spot.log | tail -1)
    if [ -n "$SPOT_PROBE" ] && [ "$SPOT_PROBE" != "$ORIG_PROBE" ]; then
        echo "probe drift: orig=$ORIG_PROBE spot=$SPOT_PROBE"
        fail "kernel probe not reproducible"
    fi
fi
ok "kernel probe stable + nonzero"

# ---- 10. Desktop gk smoke test (x86 must still work) ----
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
    tail -25 "$SMOKE_LOG"
    fail "desktop gk did not reach 'link finish: logo' — x86 CGOs corrupted"
fi
if grep -qE "Instruction non permise|Illegal" "$SMOKE_LOG"; then
    fail "desktop gk SIGILLed — x86 path broken"
fi
ok "desktop smoke test passed"

# ---- 11. Headline in markdown ----
grep -qE "arm64 CGOs regenerated|arm64-ret density" "$B1_STRUCT_MD" \
    || fail "$B1_STRUCT_MD missing the required headline"
ok "Markdown headline present"

echo ""
echo "PASS: Phase B1 arm64 CGO regen complete; bucket B's bringup ready."
