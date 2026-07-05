#!/usr/bin/env bash
# Gswamp-fstore device-independent round-trip proof (A/B).
# Builds the tiny harness against the REAL asm_funcs_arm64.s trampolines, twice:
#   FIX = working-tree asm (gpr s7 <- x14-x15, GOAL offset)  -> expect PASS
#   BUG = git HEAD asm     (gpr s7 <- raw x14, host address) -> expect FAIL
# Proves the fix works AND that the test is sensitive (rejects the bug).
set -o pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/gsf
CC=aarch64-linux-gnu-gcc
QEMU="qemu-aarch64 -L /usr/aarch64-linux-gnu"
# Same sed the project uses (build.ninja C1 custom command): ;;->// and " ; "->" // "
sedcmd(){ sed -e 's|;;|//|g' -e 's|[[:space:]];[[:space:]]|  // |g'; }

build_and_run(){
  tag="$1"
  asmfile="$2"
  out="$D/gsf_$tag"
  sedcmd < "$asmfile" > "$D/asm_${tag}_gnu.s"
  if ! $CC -O2 -static -no-pie -fsigned-char \
      "$D/gsf_test.c" "$D/gsf_driver.S" "$D/asm_${tag}_gnu.s" -o "$out" 2> "$D/build_$tag.log"; then
    echo "[$tag] static link failed, retrying without -static:"; tail -6 "$D/build_$tag.log"
    if ! $CC -O2 -no-pie -fsigned-char \
        "$D/gsf_test.c" "$D/gsf_driver.S" "$D/asm_${tag}_gnu.s" -o "$out" 2> "$D/build_$tag.log"; then
      echo "[$tag] BUILD FAILED:"; tail -25 "$D/build_$tag.log"; return 2
    fi
  fi
  echo "===== [$tag] run ====="
  $QEMU "$out"; rc=$?
  echo "[$tag] exit=$rc"
  return $rc
}

cp game/kernel/asm_funcs_arm64.s "$D/asm_fix_src.s"
git show HEAD:game/kernel/asm_funcs_arm64.s > "$D/asm_bug_src.s"

echo "### FIX variant (working tree — the applied fix) ###"
build_and_run fix "$D/asm_fix_src.s"; FIX_RC=$?
echo
echo "### BUG variant (git HEAD — pre-fix baseline) ###"
build_and_run bug "$D/asm_bug_src.s"; BUG_RC=$?
echo
echo "======================= VERDICT ======================="
echo "FIX exit=$FIX_RC (expect 0 = PASS)   BUG exit=$BUG_RC (expect 1 = FAIL)"
if [ "$FIX_RC" = "0" ] && [ "$BUG_RC" = "1" ]; then
  echo "GSF-PROOF: OK  (fix binds #f correctly; test proven sensitive — rejects the pre-fix bug)"
  exit 0
else
  echo "GSF-PROOF: INCONCLUSIVE (see logs in $D)"
  exit 1
fi
