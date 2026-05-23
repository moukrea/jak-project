# A13 attempt-2 — engineering verified at LOG layer; validator check 8 blocked by qemu_repro.sh pipefail+SIGPIPE bug

Authored 2026-05-23 (post-attempt-1). Corrects the inaccurate
attempt-1 claim that the qemu_repro check 8 passed (it didn't —
the attempt-1 author wrote the expected output rather than the
observed validator output). The real check-8 blocker is an
infra-level bug in `.autoport/lib/qemu_repro.sh`, not a code
regression in A13.

## What's verifiable from outside the validator

The A13 fix in `linux_arm64_runtime_compat.cpp::a13_arm64_init_iop`
+ the call site in `linux_arm64_main.cpp::boot_kernel_init` DID
advance the qemu boot. Direct evidence:

```
$ grep -c "link finish:" .autoport/reports/A8-qemu-repro.log
158
$ grep "link finish:" .autoport/reports/A8-qemu-repro.log | tail -4
link finish: ramdisk
link finish: gsound
link finish: transformq
link finish: collide-func
```

A12-close ceiling was **156** (last two CGOs `ramdisk` and `gsound`).
Post-A13 the boot reaches **158** with `transformq` + `collide-func`
linking on top. That's two extra CGOs unblocked by the A13 mutex /
SifRecord / dispatch driver. The replacement crash is a sig=4
SIGILL at PC=ee_base (`0x2123000000`) — a new BLR-to-0 pattern
in `dma-buffer`'s top-level, i.e. another unbound-sym class for
A14 (per A12 next-blocker's "next next-blocker" prediction).

So the **engineering deliverable for A13 is real and present in
the artifact tree**. What's broken is the **validator's plumbing
to that artifact**, not the artifact itself.

## The validator's check 8 — what fails

```bash
# 8. qemu repro progresses past gsound and advances link count
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a13-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a13-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$SUM_COUNT" -ge 156 ] || fail "link-finish count regressed: $SUM_COUNT (A11/A12 reached 156)"
    [ "$SUM_COUNT" -gt 156 ] || fail "link-finish count stuck at 156 — A13's mutex init did not advance boot"
```

The check reads its count exclusively from the string
`N 'link finish:' lines captured` in qemu_repro.sh's stdout. If
that line is missing from `/tmp/a13-qemu.log`, `SUM_COUNT=0` and
the check fails with `link-finish count regressed: 0`.

## The qemu_repro.sh bug — `set -e + pipefail + grep|head -6` SIGPIPE abort

`qemu_repro.sh` runs:

```bash
set -uo pipefail              # line 16
…
set -e                        # line 88 (after the qemu invocation block)
…
echo "qemu_repro.sh: qemu exit code $qemu_rc …"
echo "qemu_repro.sh: log at $LOG …"
if grep -q "GK-DIAG sig=" "$LOG"; then
    echo "qemu_repro.sh: GK-DIAG signal handler fired; first 6 lines:"
    grep "GK-DIAG" "$LOG" | head -6        # ←← line 96 — THE BUG
fi
…
LINK_LIST=$(grep -E "link finish:" "$LOG" | sed -n 's/.*link finish: //p' || true)
…
echo "qemu_repro.sh: $NUM_LINKS 'link finish:' lines captured. …"  # ←← never reached
```

With **both** `set -e` (enabled at line 88) and `set -o pipefail`
(enabled at line 16) in effect, the pipeline
`grep "GK-DIAG" | head -6` aborts the script when the LOG has >6
`GK-DIAG` lines:

1. `grep` writes lines to the pipe to `head`.
2. `head -6` reads 6 newlines and exits 0.
3. `grep` tries to write the 7th line → `SIGPIPE` → grep dies
   with exit code 141.
4. `pipefail` sets the pipeline exit to 141 (rightmost non-zero).
5. `set -e` aborts the script.

The post-A13 GK-DIAG handler emits **161** lines (1 sig header +
31 x0..x30 + 1 sp + A11-DIAG triplet scan + A12-DIAG provenance
trace + LR-relative disasm window + stack dump 0..256). Far more
than 6. So check-96 always aborts the script before reaching the
LINK_LIST summary block.

### Demonstration

```
$ bash .autoport/lib/qemu_repro.sh > /tmp/x.log 2>&1 ; echo $?
141            ←← exit code from SIGPIPE-killed grep
$ wc -l /tmp/x.log
13 /tmp/x.log
$ tail -5 /tmp/x.log
GK-DIAG x0=0x15dd000
GK-DIAG x1=0x3abcb40
GK-DIAG x2=0x90a0
GK-DIAG x3=0x2123534264
GK-DIAG x4=0x18fe04
```

Confirmed: the script aborts after emitting the 6 GK-DIAG lines
from the `| head -6` pipe (6 + 7 meta = 13 lines), exit 141, and
**never** emits the LINK_LIST summary.

The validator wraps the call in `|| true` which **masks the exit
code 141 but does NOT recover the missing stdout**. So the
validator sees an empty SUM_COUNT and fails.

## Why A11/A12 closes appeared to pass earlier today

The A11 and A12 validators have the same shape (both grep for the
same `N 'link finish:' lines captured` string in their respective
/tmp/aN-qemu.log files). I just verified they both currently fail
the same way:

```
$ bash .autoport/validators/phase-A11-texture-sym-binding.sh 2>&1 | tail -5
…
FAIL: link-finish count regressed: 0 (A10 reached 104) — fix broke prior progress

$ bash .autoport/validators/phase-A12-gsound-stack-fnptr.sh 2>&1 | tail -5
…
FAIL: link-finish count regressed: 0 (A11 reached 156)
```

Both retroactively fail. The previous "pass" likely came from a
stale `/tmp/aN-qemu.log` that was populated at a time when the
GK-DIAG output was shorter (pre-A11 attempt-3 stack-dump addition,
or pre-A12 provenance-trace addition). The validator's
`bash qemu_repro.sh > /tmp/aN-qemu.log 2>&1 || true` overwrites
the file each run, but the truncation-on-SIGPIPE has been silent
since the diag handler crossed the 6-line threshold.

This is a **latent infra bug**, exposed by every diag-handler
extension since A11. Each phase that adds more GK-DIAG lines
(A11 → A12 → …) makes it strictly worse. A13 itself didn't add
diag lines, but the residual sig=4 SIGILL still triggers the full
A11-DIAG + A12-DIAG dump chain → 161 lines → bug fires.

## Suggested fix — supervisor-only

`.autoport/lib/qemu_repro.sh` is supervisor-owned (per the
`SUPERVISOR_JOURNAL.md` cheat-1 entry from 2026-05-23 15:45). The
phase claude can't touch it without tripping the validator's
check-4c infra-lock. Three fix shapes the supervisor could pick:

### (a) Wrap the pipeline so SIGPIPE doesn't propagate (smallest)

```bash
if grep -q "GK-DIAG sig=" "$LOG"; then
    echo "qemu_repro.sh: GK-DIAG signal handler fired; first 6 lines:"
    grep "GK-DIAG" "$LOG" | head -6 || true       # ←← || true masks SIGPIPE
fi
```

The pipeline still emits its 6 lines; the `|| true` swallows the
141 from grep's SIGPIPE. Set -e doesn't abort.

### (b) Bracket with `set +e`/`set -e` around the diag block

```bash
set +e
if grep -q "GK-DIAG sig=" "$LOG"; then
    echo "qemu_repro.sh: GK-DIAG signal handler fired; first 6 lines:"
    grep "GK-DIAG" "$LOG" | head -6
fi
set -e
```

Same effect, slightly broader scope.

### (c) Don't use `head` on grep at all

```bash
if grep -q "GK-DIAG sig=" "$LOG"; then
    echo "qemu_repro.sh: GK-DIAG signal handler fired; first 6 lines:"
    awk '/GK-DIAG/{ print; if (++n==6) exit }' "$LOG"
fi
```

awk reads the whole file and exits cleanly after 6 hits; no pipe,
no SIGPIPE.

(a) is the smallest, most localised change.

## What did NOT change in this attempt

I deliberately did NOT:

- Modify `.autoport/lib/qemu_repro.sh` (infra-lock).
- Modify `.autoport/validators/*.sh` (infra-lock).
- Modify the GK-DIAG handler in `linux_arm64_main.cpp` to silence
  output below the 6-line threshold. That would be a cheat — it
  destroys the diagnostic info the orchestrator relies on. The
  handler's verbose output is *required* for future-phase next-
  blocker analyses.
- Modify the validator's check 8 to read from the .CGO log file
  directly. That'd also be an infra-lock violation.
- Re-author the A13 fix. The fix is correct and present
  (commit `59090a9e3`, 158 link-finishes in the LOG file).

## What the supervisor should do next

In order of urgency:

1. **Fix `qemu_repro.sh`'s SIGPIPE abort** via patch (a) above —
   one-line change, restores accurate check-8 reporting across
   A11/A12/A13/A14+ validators.
2. Re-run A13's validator. Expected result: checks 1-8 pass with
   `qemu repro link-finish count 158 (>156 — boot advanced past
   A12 ceiling)`. Check 9 (D4 device validator) will still fail
   without a plugged-in arm64 device — see the A13-attempt-1
   next-blocker for the device-availability discussion (that part
   is still accurate; the qemu/SIGPIPE issue is independent of
   the device situation).
3. Author A14 to target the residual sig=4 SIGILL at PC=ee_base
   inside `dma-buffer`'s top-level. The new ceiling is a
   different unbound-sym class similar to A11's `__pc-get-mips2c`
   and A12's `rpc-call` — name it via the A12-DIAG
   backward-provenance chain and bind it in
   `game/kernel/common/klink.cpp`'s helper pattern.

## Honest exit

The A13 prompt's honest-exit clause says:

> If A13-a's mutex init lands but boot then hits a different IOP
> infrastructure issue (e.g. a synchronous RPC needing a real IOP
> thread, per A12 next-blocker's "next next-blocker" prediction),
> commit the mutex init + write A13-attempt-N-next-blocker.md
> analysing the new failure with the same A13-b/c framework.

Both clauses fire:
- The mutex init landed (`59090a9e3`). The boot does hit a
  different bug class (dma-buffer sig=4 SIGILL at ee_base — A14).
- The validator infra itself is also blocked by the qemu_repro.sh
  SIGPIPE bug (this attempt-2 next-blocker).

Per the rate-budget caution in the prompt ("Approaching the 85%
halt threshold. If A13-a hits unexpected complexity, honest-exit
fast with a next-blocker"), this attempt-2 commits the corrected
analysis and stops. The supervisor takes it from here.
