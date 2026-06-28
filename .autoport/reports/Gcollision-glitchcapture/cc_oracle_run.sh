#!/usr/bin/env bash
# cc_oracle_run.sh — compile cc_oracle.cpp for the x86 host AND the arm64 device, run BOTH on
# a captured collision_glitch.txt dump (the owner-play operands), and diff the two outputs. Any
# row that differs is a collision-reaction op that diverges x86-vs-arm64 on those EXACT real
# operands — the divergent op the phase must name + fix. Also surfaces non-unit normals (divergent
# normalize/length) and cov!=dump (reaction op path mismatch) from the per-arch summaries.
# Usage: bash .autoport/reports/Gcollision-glitchcapture/cc_oracle_run.sh [dump.txt]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
D=.autoport/reports/Gcollision-glitchcapture
DUMP="${1:-$D/collision_glitch.txt}"
NDK_CXX=/home/emeric/Android/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang++
[ -f "$DUMP" ] || { echo "no dump: $DUMP (run cc_pull_dump.sh after the owner triggers a glitch)"; exit 3; }

echo "== build x86 oracle =="
g++ -O2 -ffp-contract=off -o "$D/cc_oracle_x86" "$D/cc_oracle.cpp" || { echo "x86 build FAILED"; exit 1; }
echo "== build arm64 oracle =="
"$NDK_CXX" -O2 -ffp-contract=off -static-libstdc++ -o "$D/cc_oracle_arm" "$D/cc_oracle.cpp" || { echo "arm64 build FAILED"; exit 1; }

echo "== run x86 oracle on the dump =="
"$D/cc_oracle_x86" "$DUMP" > "$D/oracle_x86.txt"
tail -1 "$D/oracle_x86.txt"

echo "== run arm64 oracle on the dump (on device) =="
$ADB -s "$S" push "$D/cc_oracle_arm" /data/local/tmp/cc_oracle_arm >/dev/null
$ADB -s "$S" push "$DUMP" /data/local/tmp/cc_dump_in.txt >/dev/null
$ADB -s "$S" shell "chmod 755 /data/local/tmp/cc_oracle_arm" >/dev/null
$ADB -s "$S" shell "/data/local/tmp/cc_oracle_arm /data/local/tmp/cc_dump_in.txt" > "$D/oracle_arm.txt"
$ADB -s "$S" shell "rm -f /data/local/tmp/cc_oracle_arm /data/local/tmp/cc_dump_in.txt" >/dev/null 2>&1
tail -1 "$D/oracle_arm.txt"

echo "== DIFF x86 vs arm64 (op-level, on real operands) =="
# strip the arch header line so only data rows are compared
diff <(grep '^F ' "$D/oracle_x86.txt") <(grep '^F ' "$D/oracle_arm.txt") > "$D/oracle_diff.txt" && \
  echo "IDENTICAL: every reaction op gives arm64 == x86 on the captured operands (divergence is UPSTREAM in detection)" || \
  { echo "DIVERGENCE FOUND — differing rows (left=x86, right=arm64):"; head -40 "$D/oracle_diff.txt"; }
echo "(full: $D/oracle_diff.txt ; per-arch: oracle_x86.txt / oracle_arm.txt)"
