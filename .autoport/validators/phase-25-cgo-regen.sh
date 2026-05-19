#!/usr/bin/env bash
# Phase 25 validator: verify jak1 CGOs were re-emitted with the arm64
# backend AFTER this phase started, and that their bytes look aarch64.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/anti-stub.sh

echo "== Phase 25 validator (jak1 CGO regen, aarch64 verified) =="

# Phase start marker — anything that was already on disk before the
# orchestrator first launched this phase doesn't count. The truth is in
# state.json's `phase_started_at[<id>]` (set once, in the orchestrator,
# *before* claude is spawned).
#
# The previous logic used `ls -t validator-*.txt | head -1` mtime — but
# the orchestrator creates `validator-NN.txt` as its stdout redirect
# target BEFORE invoking this script, so the "latest" file is the one
# we're currently writing, with mtime ≈ now. Every CGO regenerated
# during the attempt (mtime ≈ now - 90s) appeared "stale" by that
# measure, the same fingerprint hit 3× in a row, and STUCK detection
# halted the loop on a phantom failure. See feedback-phase25-freshness
# memory for the post-mortem.
PHASE_START=$(python3 -c "
import json, sys
try:
    s = json.load(open('.autoport/state.json'))
    ts = s.get('phase_started_at', {}).get('25-cgo-regen', 0)
    print(int(ts))
except Exception:
    print(0)
" 2>/dev/null)
if [ "${PHASE_START:-0}" -eq 0 ]; then
    # Fallback: 1 hour ago, generous to absorb a long claude session
    # that may have started before this validator instance.
    PHASE_START=$(($(date +%s) - 3600))
fi
echo "  phase_start_anchor: $PHASE_START ($(date -u -d "@$PHASE_START" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null))"

ISO_DIR=out/jak1/iso
test -d "$ISO_DIR" || { echo "FAIL: $ISO_DIR does not exist; pipeline didn't run"; exit 1; }
CGO_COUNT=$(ls "$ISO_DIR"/*.CGO 2>/dev/null | wc -l)
if [ "$CGO_COUNT" -lt 3 ]; then
    echo "FAIL: only $CGO_COUNT CGOs in $ISO_DIR; expected ≥3 (KERNEL/ENGINE/GAME)"
    exit 1
fi
echo "  found $CGO_COUNT CGO files"

# Freshness check: every CGO must be newer than the phase start.
STALE=0
for cgo in "$ISO_DIR"/*.CGO; do
    mt=$(stat -c %Y "$cgo")
    if [ "$mt" -lt "$PHASE_START" ]; then
        echo "  STALE: $(basename "$cgo") mtime=$mt < phase_start=$PHASE_START"
        STALE=$((STALE + 1))
    fi
done
if [ "$STALE" -gt 0 ]; then
    echo "FAIL: $STALE CGOs predate the phase start — pipeline didn't actually regen"
    exit 1
fi

# Byte-level audit on the three big ones.
MANIFEST=.autoport/logs/phase-25-cgos.tsv
mkdir -p .autoport/logs
: > "$MANIFEST"
FAILED=0
for cgo_name in KERNEL.CGO ENGINE.CGO GAME.CGO; do
    cgo="$ISO_DIR/$cgo_name"
    test -f "$cgo" || { echo "FAIL: $cgo missing"; exit 1; }
    bytes=$(stat -c %s "$cgo")
    mt=$(stat -c %Y "$cgo")
    # Scan the front 50% of each CGO. The v3 object format packs the
    # MAIN code segment at the start of every .o entry, and a CGO is
    # many .o entries concatenated — so code is densest in the front
    # half and static data (level / VU / texture blobs) dominates the
    # tail of CGOs that link in heavy game assets (e.g. GAME.CGO).
    # The previous "middle 50%" heuristic was tuned for single-.o
    # files and undercounted real code in multi-.o CGOs.
    scan_off=0
    scan_len=$((bytes / 2))
    # grep -aoc on binary returns *matching-line count* (not match count),
    # which collapses dozens of aarch64 rets that happen to sit on the
    # same logical "line" of binary into a single tick. We need the
    # actual occurrence count, so do the count in python.
    aarch64_ret=$(python3 -c "
import sys
with open('$cgo','rb') as f:
    f.seek($scan_off); print(f.read($scan_len).count(b'\xc0\x03\x5f\xd6'))")
    x86_ret=$(python3 -c "
import sys
with open('$cgo','rb') as f:
    f.seek($scan_off); print(f.read($scan_len).count(b'\xc3'))")
    printf "%s\t%d\t%d\t%d\t%d\n" "$cgo_name" "$bytes" "$mt" "$aarch64_ret" "$x86_ret" >> "$MANIFEST"

    # Threshold: the middle half should have at least 1 aarch64 ret per
    # 1000 bytes of code (real code averages closer to 1 per 200, so
    # this is a forgiving floor).
    need=$((scan_len / 1000))
    [ "$need" -lt 10 ] && need=10
    echo "  $cgo_name: $bytes bytes, aarch64-ret=$aarch64_ret (need ≥$need), x86-ret=$x86_ret"
    if [ "$aarch64_ret" -lt "$need" ]; then
        echo "  FAIL: $cgo_name has too few aarch64 ret encodings — looks like x86 or stub bytes"
        FAILED=$((FAILED + 1))
    fi
    # x86 ret (single byte 0xc3) is noisy by nature, but if it dominates
    # the aarch64 count by a wide margin AND aarch64 is sparse, that's a
    # clear x86 signal.
    if [ "$aarch64_ret" -lt 50 ] && [ "$x86_ret" -gt $((aarch64_ret * 8)) ]; then
        echo "  FAIL: $cgo_name byte profile dominantly x86 (aarch64=$aarch64_ret  x86=$x86_ret)"
        FAILED=$((FAILED + 1))
    fi
done

if [ "$FAILED" -gt 0 ]; then
    echo "FAIL: $FAILED CGOs failed the aarch64 byte audit"
    exit 1
fi

# APK rebuilt and contains the new CGOs (byte-identical to what's on
# disk). This catches the case where the assets dir was updated but the
# APK build skipped (mtimes line up wrong).
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
if [ ! -f "$APK" ]; then
    echo "FAIL: APK not built at $APK"
    exit 1
fi
APK_MT=$(stat -c %Y "$APK")
if [ "$APK_MT" -lt "$PHASE_START" ]; then
    echo "FAIL: APK predates phase start; gradle assemble didn't run"
    exit 1
fi
HOST_KERNEL_SHA=$(sha256sum "$ISO_DIR/KERNEL.CGO" | awk '{print $1}')
APK_KERNEL_SHA=$(unzip -p "$APK" assets/iso_data/jak1/KERNEL.CGO 2>/dev/null | sha256sum | awk '{print $1}')
if [ "$HOST_KERNEL_SHA" != "$APK_KERNEL_SHA" ]; then
    echo "FAIL: KERNEL.CGO in APK doesn't match $ISO_DIR/KERNEL.CGO"
    echo "  host:  $HOST_KERNEL_SHA"
    echo "  apk:   $APK_KERNEL_SHA"
    exit 1
fi

echo
echo "== Phase 25 validator PASSED =="
echo "   $CGO_COUNT jak1 CGOs re-emitted, three big ones pass aarch64"
echo "   byte audit, APK contains byte-identical copies. Manifest:"
echo "   $MANIFEST"
