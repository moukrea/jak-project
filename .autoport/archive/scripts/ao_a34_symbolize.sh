#!/usr/bin/env bash
# ao_a34_symbolize.sh — A34 crash-forensics loop for a title-gate combo death.
# Usage: ao_a34_symbolize.sh <crash-dir>   (e.g. .autoport/reports/Grecharged-ambient-occlusion/title-gate/crash-gtao-high)
# Inputs: crash-dir/dropbox.txt + logcat-crash.txt (harvested by ao_title_gate.sh) and the
# archived .autoport/reports/Grecharged-ambient-occlusion/title-gate/libgk-under-test.so.
# Output: symbolized frames (function + file:line) for every libgk.so PC/LR in the backtrace,
# after verifying the tombstone's Build ID matches the archived .so (A38 fiction check).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
D="${1:?usage: ao_a34_symbolize.sh <crash-dir>}"
SO=.autoport/reports/Grecharged-ambient-occlusion/title-gate/libgk-under-test.so
A2L=/home/emeric/Android/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-addr2line
die(){ echo "[a34 FAIL] $*" >&2; exit 1; }
[ -f "$SO" ] || die "no archived libgk-under-test.so"
[ -d "$D" ] || die "no crash dir $D"

WANT_BID=$(LANG=C readelf -n "$SO" | grep -oE 'Build ID: [0-9a-f]+' | awk '{print $3}')
echo "archived .so Build ID: $WANT_BID"

SRC=""
for f in "$D"/dropbox.txt "$D"/logcat-crash.txt "$D"/combo-tail.txt; do
  [ -f "$f" ] && grep -qaE 'backtrace|#[0-9]+ pc ' "$f" && { SRC="$f"; break; }
done
[ -n "$SRC" ] || die "no backtrace found in $D (dropbox/logcat-crash/combo-tail)"
echo "backtrace source: $SRC"

TB_BID=$(grep -aoE 'BuildId: [0-9a-f]+' "$SRC" | head -1 | awk '{print $2}')
if [ -n "$TB_BID" ] && [ "$TB_BID" != "$WANT_BID" ]; then
  echo "WARNING: tombstone BuildId $TB_BID != archived $WANT_BID — symbolization would LIE; aborting"
  exit 2
fi

grep -aE 'signal [0-9]+ \(SIG|Abort message|fault addr' "$SRC" | head -5

# every "#NN pc <hex>  <path>libgk.so" frame -> function + file:line
grep -aE '#[0-9]+ pc [0-9a-f]+.*libgk\.so' "$SRC" | while read -r line; do
  PC=$(echo "$line" | grep -oE 'pc [0-9a-f]+' | awk '{print $2}')
  SYM=$("$A2L" -e "$SO" -f -C -i "0x$PC" 2>/dev/null | paste -sd' @ ')
  echo "  pc 0x$PC -> $SYM"
done
echo "[a34] done — cross-check the faulting frame's disassembly with llvm-objdump -d --start-address if the line looks optimized-away"
