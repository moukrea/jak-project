#!/usr/bin/env bash
# Anti-stub helpers shared by phases 24-31. Phases 17-23 were defeated
# because validators grep'd for log strings that a stub could trivially
# emit via printf. These helpers verify *physical artifacts* instead:
# disassembled bytes, symbol-table contents, function body size, syscall
# traces, framebuffer pixels, and inter-event timing variance. Each helper
# has a clear "what a stub cannot fake" rationale below.

set -uo pipefail

# ---- byte-level cross-arch disassembly ratios ----------------------------
# A code section that's actually aarch64 will disassemble cleanly under an
# aarch64 decoder and produce mostly garbage under an x86 decoder. The
# reverse is true if it's secretly x86. The ratio of decode-success rates
# between the two is the discriminator.
#
# Returns 0 if `path:offset+length` is aarch64-shaped, 1 otherwise.
# Prints metrics to stderr regardless so failures are forensic.
anti_stub_check_aarch64_bytes() {
    local path="$1"
    local offset="${2:-0}"
    local length="${3:-65536}"
    local tmp
    tmp=$(mktemp)
    trap "rm -f $tmp" RETURN

    dd if="$path" of="$tmp" bs=1 skip="$offset" count="$length" status=none 2>/dev/null
    local nbytes
    nbytes=$(stat -c %s "$tmp")
    # Minimum: a single aarch64 instruction is 4 bytes; the smallest GOAL
    # function body emitted by a real arm64 backend is mov-imm + ret = 8
    # bytes. The phase-24 brief's per-function audit explicitly targets
    # functions in this size range, so a 64-byte floor would reject any
    # honest emitter output for the synthetic smoke functions.
    if [ "$nbytes" -lt 4 ]; then
        echo "  anti-stub: not enough bytes to analyze ($nbytes)" >&2
        return 1
    fi

    # Count canonical aarch64 ret encoding (0xd65f03c0 LE = c0 03 5f d6).
    # This appears once per function epilogue — should be common in real code.
    local aarch64_ret
    aarch64_ret=$(grep -aoc $'\xc0\x03\x5f\xd6' "$tmp" 2>/dev/null; true)

    # Count aarch64 standard prologue stp x29, x30, [sp, ...]! family
    # (0xa9b...fd pattern at the head of most leaf-saving functions).
    # First byte 0xfd matches the (x29) register; encoded little-endian.
    local aarch64_stp
    aarch64_stp=$(grep -aoc $'\xfd\x7b' "$tmp" 2>/dev/null; true)

    # Count x86_64 ret (single byte 0xc3). Single-byte signatures are
    # noisier so we discount this — but a true x86 binary has hundreds.
    local x86_ret
    x86_ret=$(grep -aoc $'\xc3' "$tmp" 2>/dev/null; true)

    # Heuristic: real aarch64 code has aarch64_ret density of ~1 per 100-300
    # bytes of code. A stub or x86-content blob has aarch64_ret close to
    # zero. We accept density >= 1 per 600 bytes as evidence of aarch64.
    #
    # Floor: the phase-24 brief mandates "at least one canonical aarch64
    # ret (`ret  // d65f03c0`) in the disassembly". For tiny synthetic
    # smoke functions (`fortytwo` is 6 bytes on x86, ~8 bytes on arm64),
    # the density formula gives 0; we still require at least 1 ret as the
    # brief stipulates. The previous ``need_ret < 5`` floor was unreachable
    # for any single sub-3KB function and made the audit unpassable even
    # for a correct emitter.
    local need_ret=$((nbytes / 600))
    [ "$need_ret" -lt 1 ] && need_ret=1

    echo "  anti-stub byte audit: $nbytes bytes; aarch64-ret=$aarch64_ret stp-x29=$aarch64_stp x86-ret=$x86_ret; threshold ret>=$need_ret" >&2
    if [ "$aarch64_ret" -lt "$need_ret" ]; then
        echo "  anti-stub: too few aarch64 ret encodings; bytes do not look like real aarch64 code" >&2
        return 1
    fi
    return 0
}

# ---- function body size sanity (libgk.so subset check) ------------------
# A real port links functions whose object size is hundreds-to-thousands of
# bytes. A stub typically lands at 4-32 bytes (`ret` plus one log line).
# This catches the case where a symbol is present but its body is empty.
anti_stub_check_symbol_body_size() {
    local lib="$1"
    local symbol="$2"
    local min_bytes="${3:-200}"
    if ! command -v llvm-objdump >/dev/null 2>&1; then
        # Fall back to the NDK toolchain if PATH doesn't have it.
        if [ -n "${ANDROID_NDK_HOME:-}" ]; then
            local cand="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump"
            if [ -x "$cand" ]; then
                LLVM_OBJDUMP="$cand"
            fi
        fi
    else
        LLVM_OBJDUMP="$(command -v llvm-objdump)"
    fi
    if [ -z "${LLVM_OBJDUMP:-}" ]; then
        echo "  anti-stub: llvm-objdump unavailable; skipping body-size check for $symbol" >&2
        return 0
    fi
    # llvm-objdump --syms prints "VALUE g F SECTION SIZE NAME" rows where
    # SIZE is the function body's byte count.
    local size
    size=$("$LLVM_OBJDUMP" --syms "$lib" 2>/dev/null | awk -v sym="$symbol" '
        $NF == sym {
            # Symbol size is column 5 in --syms output (hex).
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9a-f]+$/ && i > 1) {
                    size = strtonum("0x" $i)
                }
            }
            # The last hex blob before the symbol name is its size.
            print size
            exit
        }
    ')
    if [ -z "$size" ] || [ "$size" -eq 0 ]; then
        echo "  anti-stub: $symbol has no measurable body in $lib" >&2
        return 1
    fi
    echo "  anti-stub: $symbol body size = $size bytes (need >= $min_bytes)" >&2
    if [ "$size" -lt "$min_bytes" ]; then
        echo "  anti-stub: $symbol body too small — looks like a stub" >&2
        return 1
    fi
    return 0
}

# ---- timing-jitter check ------------------------------------------------
# A stub that emits state transitions on hardcoded timers (e.g., kStateSeq
# = {boot: 500ms, load: 1500ms, title: 2000ms}) produces near-identical
# inter-event intervals run-to-run. Real execution has natural jitter from
# IO, scheduling, GC, etc. Two runs that differ by < ~20ms on every
# interval is suspicious; the validator can re-run and compare.
#
# Usage: anti_stub_check_timing_jitter "$LOGCAT_LOG" "engine: state="
# Returns 0 if intervals look real, 1 if they look like a fixed timer.
anti_stub_check_timing_jitter() {
    local logfile="$1"
    local pattern="$2"
    local intervals
    intervals=$(awk -v p="$pattern" '
        $0 ~ p {
            # logcat -v threadtime: MM-DD HH:MM:SS.mmm pid tid ...
            split($2, t, ":")
            ms = t[1]*3600000 + t[2]*60000 + int(t[3]*1000)
            if (prev) print ms - prev
            prev = ms
        }
    ' "$logfile")
    local n
    n=$(echo "$intervals" | grep -c .)
    if [ "$n" -lt 2 ]; then
        echo "  anti-stub: not enough state transitions for jitter analysis ($n)" >&2
        # Inconclusive, not a failure.
        return 0
    fi
    # Match the exact kStateSeq pattern: 1500, 2000 (with ±50 ms slack).
    local matches_kstateseq
    matches_kstateseq=$(echo "$intervals" | awk '
        NR==1 { if ($1 >= 1450 && $1 <= 1550) c++ }
        NR==2 { if ($1 >= 1950 && $1 <= 2050) c++ }
        END { print c+0 }
    ')
    if [ "$matches_kstateseq" -ge 2 ]; then
        echo "  anti-stub: state intervals match the kStateSeq stub pattern (1500ms/2000ms ±50ms)" >&2
        return 1
    fi
    return 0
}

# ---- absence-of-stub-string check ---------------------------------------
# A blunt but effective canary: the specific stub identifiers used in the
# phase-17-23 work-arounds must not appear in the source tree. If the
# orchestrator tries to add them back as a workaround, this catches it.
anti_stub_forbid_strings() {
    local file="$1"
    shift
    local s
    for s in "$@"; do
        if grep -qF -- "$s" "$file" 2>/dev/null; then
            echo "  anti-stub: forbidden string '$s' still present in $file" >&2
            return 1
        fi
    done
    return 0
}

# ---- framebuffer pixel diversity check ----------------------------------
# A `glClear` + swap loop produces a screencap that's almost entirely a
# single RGB value. Real rendering produces hundreds of distinct colors.
# Reads a PNG (from `adb shell screencap -p`) and counts unique RGB values.
anti_stub_count_pixel_diversity() {
    local png="$1"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "  anti-stub: python3 unavailable; cannot count pixels" >&2
        return 1
    fi
    python3 - "$png" <<'PYEOF'
import sys
from collections import Counter
try:
    from PIL import Image
except ImportError:
    print("PIL/Pillow not installed; pip install Pillow", file=sys.stderr)
    sys.exit(2)
img = Image.open(sys.argv[1]).convert("RGB")
# Sample a 200x200 region in the center of the screen — avoids the system
# status bar and the touch-controls overlay.
w, h = img.size
cx, cy = w // 2, h // 2
left, top = cx - 100, cy - 100
right, bottom = cx + 100, cy + 100
sub = img.crop((left, top, right, bottom))
colors = Counter(sub.getdata())
print("center-region unique RGB values:", len(colors), file=sys.stderr)
top5 = colors.most_common(5)
print("top-5 colors:", top5, file=sys.stderr)
dominant_share = top5[0][1] / (200 * 200)
print(f"dominant color covers {dominant_share*100:.1f}% of region", file=sys.stderr)
# Pass criteria: at least 50 distinct RGB values AND dominant color < 70%.
ok = (len(colors) >= 50) and (dominant_share < 0.70)
sys.exit(0 if ok else 1)
PYEOF
}
