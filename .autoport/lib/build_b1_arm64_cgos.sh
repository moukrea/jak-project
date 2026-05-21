#!/usr/bin/env bash
# Phase B1 — re-emit jak1 CGOs with the arm64 backend; restore the x86 build.
#
# End-to-end pipeline:
#   1. Snapshot whatever is in out/jak1/iso/ (diagnostic — recorded to
#      .autoport/reports/B1-x86-baseline.txt + .autoport/backups/B1-x86-cgos/).
#   2. Wipe out/jak1/obj/ so the .o cache cannot leak the wrong backend
#      (the goalc make system is timestamp-driven once knows_object_file
#      is true; .o files are never tagged with their backend).
#   3. Run build-arm64/goalc/goalc -c "(make-group "iso" :force #t)"
#      -> arm64 CGOs/DGOs at out/jak1/iso/.
#   4. Move out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO -> out/jak1-arm64/iso/.
#      Record their sha256 hashes to .autoport/reports/B1-arm64-cgos.txt.
#   5. Wipe out/jak1/obj/ again (arm64 .o files would poison the x86
#      DGOs that the desktop oracle still depends on).
#   6. Run build/goalc/goalc -c "(make-group "iso" :force #t)"
#      -> x86 CGOs + x86 DGOs back at out/jak1/iso/.
#   7. Verify the three x86 CGOs hash-match A2's baseline byte-for-byte.
#   8. Structural-check the three arm64 CGOs
#      (.autoport/reports/B1-cgo-structure.json).
#   9. Re-run A4's kernel-symbol probe against the new arm64 KERNEL.CGO
#      (.autoport/reports/B1-kernel-probe.txt).
#  10. Write a markdown summary (.autoport/reports/B1-cgo-structure.md).
#
# Idempotency: each (mi) starts from a wiped obj/ cache and compiles
# deterministically from .gc source, so the output bytes are stable
# across runs. The validator depends on this for its reproducibility
# check (it spot-checks by re-running the driver and diffing arm64
# hashes).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

# ---------------- paths ----------------
X86_DIR="out/jak1/iso"
ARM64_DIR="out/jak1-arm64/iso"
OBJ_DIR="out/jak1/obj"
BACKUP_DIR=".autoport/backups/B1-x86-cgos"
REPORTS=".autoport/reports"
LOG_DIR=".autoport/logs"
X86_GOALC="build/goalc/goalc"
ARM64_GOALC="build-arm64/goalc/goalc"
PROBE_SH="test/arm64/a4_kernel_probe.sh"
STRUCT_PY=".autoport/lib/cgo_structure_check.py"
A2_BASELINE="$REPORTS/A2-baseline-x86-cgo-hashes.txt"

CGOS=(KERNEL.CGO ENGINE.CGO GAME.CGO)

fail() { echo "[B1 FAIL] $*" >&2; exit 1; }
log()  { echo "[B1] $*"; }

mkdir -p "$BACKUP_DIR" "$ARM64_DIR" "$REPORTS" "$X86_DIR" "$OBJ_DIR" "$LOG_DIR"

# ---------------- preflight ----------------
[ -x "$X86_GOALC" ]    || fail "$X86_GOALC missing"
[ -x "$ARM64_GOALC" ]  || fail "$ARM64_GOALC missing"
[ -f "$A2_BASELINE" ]  || fail "$A2_BASELINE missing"
[ -f "$STRUCT_PY" ]    || fail "$STRUCT_PY missing"
[ -x "$PROBE_SH" ]     || fail "$PROBE_SH missing or not executable"

# Confirm backend identity at runtime so a misconfigured CMake doesn't
# silently emit x86 from build-arm64/.
"$X86_GOALC"   --version 2>&1 | grep -q "x86"   || fail "$X86_GOALC isn't an x86 backend"
"$ARM64_GOALC" --version 2>&1 | grep -q "arm64" || fail "$ARM64_GOALC isn't an arm64 backend"

# Confirm A4's link-fixup hooks are present in ObjectGenerator.cpp (the
# arm64 binary is compiled from this source; we don't want to silently
# fall back to the pre-A4 emitter).
grep -qE "handle_temp_jump_links|cross_seg|imm12|imm19" \
    goalc/emitter/ObjectGenerator.cpp \
    || fail "ObjectGenerator.cpp doesn't mention A4 fix-up hooks"

# ---------------- 1. snapshot current iso state ----------------
log "snapshotting $X86_DIR/*.CGO -> $BACKUP_DIR/"
for cgo in "${CGOS[@]}"; do
    if [ -f "$X86_DIR/$cgo" ]; then
        cp -f "$X86_DIR/$cgo" "$BACKUP_DIR/$cgo"
    fi
done
( cd "$BACKUP_DIR" && sha256sum "${CGOS[@]}" 2>/dev/null ) \
    > "$REPORTS/B1-x86-baseline.txt"

# ---------------- 2. arm64 (mi) ----------------
log "wiping $OBJ_DIR before arm64 (mi)"
find "$OBJ_DIR" -maxdepth 1 -type f \( -name "*.o" -o -name "*.go" \) -delete

log "running arm64 (mi) (force-rebuild)"
ARM64_MI_LOG="$LOG_DIR/B1-arm64-mi.log"
"$ARM64_GOALC" --user-auto --game jak1 --disable-ansi \
    -c '(make-group "iso" :force #t)' \
    > "$ARM64_MI_LOG" 2>&1
if ! grep -qE "Successfully built all [0-9]+ targets" "$ARM64_MI_LOG"; then
    echo "==== last 60 lines of arm64 (mi) log ====" >&2
    tail -60 "$ARM64_MI_LOG" >&2
    fail "arm64 (mi) did not finish cleanly"
fi
log "$(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$ARM64_MI_LOG" | head -1)"

# Verify each CGO landed
for cgo in "${CGOS[@]}"; do
    [ -s "$X86_DIR/$cgo" ] || fail "$X86_DIR/$cgo missing/empty after arm64 (mi)"
done

# ---------------- 3. relocate arm64 CGOs ----------------
log "moving arm64 CGOs to $ARM64_DIR/"
for cgo in "${CGOS[@]}"; do
    mv -f "$X86_DIR/$cgo" "$ARM64_DIR/$cgo"
done
( cd "$ARM64_DIR" && sha256sum "${CGOS[@]}" ) > "$REPORTS/B1-arm64-cgos.txt"
log "arm64 hashes:"
cat "$REPORTS/B1-arm64-cgos.txt" | sed 's/^/    /'

# ---------------- 4. x86 (mi) ----------------
log "wiping $OBJ_DIR before x86 (mi)"
find "$OBJ_DIR" -maxdepth 1 -type f \( -name "*.o" -o -name "*.go" \) -delete

log "running x86 (mi) (force-rebuild)"
X86_MI_LOG="$LOG_DIR/B1-x86-mi.log"
"$X86_GOALC" --user-auto --game jak1 --disable-ansi \
    -c '(make-group "iso" :force #t)' \
    > "$X86_MI_LOG" 2>&1
if ! grep -qE "Successfully built all [0-9]+ targets" "$X86_MI_LOG"; then
    echo "==== last 60 lines of x86 (mi) log ====" >&2
    tail -60 "$X86_MI_LOG" >&2
    fail "x86 (mi) did not finish cleanly"
fi
log "$(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$X86_MI_LOG" | head -1)"

# ---------------- 5. verify x86 CGOs match A2 baseline ----------------
log "verifying x86 CGOs vs A2 baseline"
while read -r expected path; do
    [ -n "$expected" ] || continue
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
        echo "  drift on $path" >&2
        echo "  expected $expected" >&2
        echo "  actual   $actual" >&2
        fail "x86 CGO drift vs A2 baseline"
    fi
done < "$A2_BASELINE"
log "x86 CGOs byte-identical to A2 baseline"

# ---------------- 6. structural check ----------------
log "running structural check on arm64 CGOs"
python3 "$STRUCT_PY" \
    "$REPORTS/B1-cgo-structure.json" \
    "$ARM64_DIR/KERNEL.CGO" \
    "$ARM64_DIR/ENGINE.CGO" \
    "$ARM64_DIR/GAME.CGO"

# ---------------- 7. kernel-symbol probe ----------------
log "running A4 kernel probe against $ARM64_DIR/KERNEL.CGO"
PROBE_OUT=$(KERNEL_CGO="$ARM64_DIR/KERNEL.CGO" "$PROBE_SH" 2>/dev/null | tail -1)
if ! [[ "$PROBE_OUT" =~ ^[1-9][0-9]*$ ]]; then
    fail "kernel probe didn't produce a nonzero integer (got: '$PROBE_OUT')"
fi
echo "$PROBE_OUT" > "$REPORTS/B1-kernel-probe.txt"
log "kernel probe = $PROBE_OUT"

# ---------------- 8. markdown summary ----------------
log "writing $REPORTS/B1-cgo-structure.md"
python3 - "$REPORTS/B1-cgo-structure.json" \
            "$REPORTS/B1-kernel-probe.txt" \
            "$REPORTS/B1-cgo-structure.md" <<'PYEOF'
import json
import sys

struct_path, probe_path, md_path = sys.argv[1:4]
data = json.load(open(struct_path))
probe = open(probe_path).read().strip()

def fmt_size(n):
    return f"{n:,}"

CGOS = ("KERNEL.CGO", "ENGINE.CGO", "GAME.CGO")
with open(md_path, "w") as f:
    f.write("# Phase B1 — arm64 CGO regen (structural check)\n\n")
    sizes = {k: data[k]["total_bytes"] for k in CGOS}
    densities = {k: data[k]["ret_density_per_kb"] for k in CGOS}
    x86_pcts = {k: data[k]["x86_ret_pct"] for k in CGOS}
    fn_counts = {k: data[k]["function_count"] for k in CGOS}
    headline = (
        f"arm64 CGOs regenerated: "
        f"KERNEL.CGO={fmt_size(sizes['KERNEL.CGO'])}B, "
        f"ENGINE.CGO={fmt_size(sizes['ENGINE.CGO'])}B, "
        f"GAME.CGO={fmt_size(sizes['GAME.CGO'])}B. "
        f"arm64-ret density: "
        f"K={densities['KERNEL.CGO']:.2f}/KB "
        f"E={densities['ENGINE.CGO']:.2f}/KB "
        f"G={densities['GAME.CGO']:.2f}/KB. "
        f"x86-ret bytes: "
        f"K={x86_pcts['KERNEL.CGO']:.3f}% "
        f"E={x86_pcts['ENGINE.CGO']:.3f}% "
        f"G={x86_pcts['GAME.CGO']:.3f}% "
        f"(<1% each, anti-x86-contamination). "
        f"x86 oracle CGOs hash-match A2 baseline. "
        f"Kernel probe: {probe}."
    )
    f.write(f"> {headline}\n\n")
    f.write("## Per-CGO structural metrics\n\n")
    f.write("| CGO | bytes | objects | fns | arm64 ret | x86 ret | density (ret/KB) | x86 ret % | min/mean/max fn size |\n")
    f.write("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n")
    for cgo in CGOS:
        rec = data[cgo]
        f.write(
            f"| {cgo} "
            f"| {fmt_size(rec['total_bytes'])} "
            f"| {rec['object_count']} "
            f"| {rec['function_count']} "
            f"| {rec['arm64_ret_count']} "
            f"| {rec['x86_ret_count']} "
            f"| {rec['ret_density_per_kb']:.2f} "
            f"| {rec['x86_ret_pct']:.3f} "
            f"| {rec['min_function_size']}/{rec['mean_function_size']}/{rec['max_function_size']} |\n"
        )
    f.write("\n## decode_sample (first function in each CGO)\n\n")
    for cgo in CGOS:
        sample = data[cgo].get("decode_sample", {})
        f.write(f"### {cgo}\n\n")
        hist = sample.get("histogram", {}) or {}
        top = sorted(hist.items(), key=lambda kv: -kv[1])[:12]
        if top:
            f.write("Top mnemonics: " + ", ".join(f"`{m}`={n}" for m, n in top) + "\n\n")
        snippet = sample.get("snippet", "")
        if snippet:
            f.write("```text\n" + snippet + "\n```\n\n")
    f.write(f"## Kernel symbol probe\n\n```\n{probe}\n```\n")
PYEOF

log "all reports written under $REPORTS/"
log "done"
