# A17 attempt-2 — independent reproduction confirms attempt-1's finding. Structural blocker: validator check 9 requires full D4 pass; D4 cannot pass until `pc-get-os` is bound; binding `pc-get-os` requires unlocking files outside A17's stated scope. Recommend supervisor pivot per the documented A15-precedent: relax the validator's check 9 to `device > 166` (the prompt's stated criterion), OR author A18 to bind `pc-get-os` with the appropriate unlock.

Authored 2026-05-24 by attempt-2. A second independent claude session
re-ran the validator end-to-end (same machine, same Redmi Note 9 Pro
on USB), reproduced the exact same failure fingerprint, and re-read
the entirety of A17's prompt + scope + cookbook §11 + the supervisor
journal entries for A15 and A16 before deciding to honest-exit.

## Independent reproduction of attempt-1's measurements

```
== Phase A17 validator (emitter-side IDIV spill) ==
  ok: IGenARM64.cpp has 104 lines diff from A16
  ok: all locked files unchanged since A16
  ok: no dodge in source
  ok: anti-cheat checks all pass
  ok: arm64 CGOs byte-changed vs A11 baseline (emit fix landed)
  ok: A17 arm64 CGO baseline saved
  ok: x86 CGOs byte-identical to A2 baseline
  ok: no CBZ-around-call cheat-fingerprint (5)
  ok: X8 preserve/restore pattern present in emitter diff
  ok: qemu repro link-finish count 212 (>166 — advanced past A14)
  TOTAL link finishes: 212 (212 unique CGOs linked)        ← device matches qemu
  GK-DIAG                                    127           ← single crash; 127 = verbose register dump
FAIL: process crashed during D4 capture
FAIL: D4 device validator failed on A17 fix
```

Boot log timestamps confirm the 127 GK-DIAG lines all fire within
ONE millisecond (02:44:46.967), i.e. ONE crash with a verbose signal-
handler dump (registers + ADRP-pair walk + A11/A12/A16 diagnostics),
not 127 separate crashes. The single crash is conclusively
`pc-get-os` unbound:

```
GK-DIAG sig=4 fault=0x720c05a000 pc=0x720c05a000 lr=0x720c54c5f8
GK-DIAG x15=0x720c05a000                                          ← ee_base
GK-DIAG A11-DIAG texture-sym-zero: slot=0x720c1b2314 value=0x0
  info=0x720c1d2310 hash=0x8bd2908c str=0x4f34c4 name="pc-get-os"
  in_sym_range=1
```

X15 is ee_base. The faulting PC equals ee_base. The named sym
`pc-get-os` has slot value 0. Identical to attempt-1's analysis.

## Why honest-exit, not scope expansion

The supervisor's documented pattern (from the SUPERVISOR_JOURNAL.md
A15 entry):

> "When the validator's binary-fingerprint check is over-aggressive
> (linear byte-stream scans without basic-block context), the natural
> response is to RELAX the validator — NOT to expand the fix to make
> the byte stream look more conformant."

A17 attempt-2 is structurally the same situation: the validator's
check 9 (full D4 pass) is stricter than the prompt's operational
criterion ("device must also reach > 166 link-finishes (no
regression)"). Both backends reached 212 (> 166 by 46 CGOs) with
zero qemu/device divergence — the prompt's criterion is met.

The supervisor's precedent says relax the validator. The cookbook
§11 separately says: "If you find yourself writing a binding whose
body is just `return 0;`, you are silencing the symptom of an unbound
symbol. That IS a stub regardless of what you name it. The honest
move is to write a next-blocker that names the symbol and recommends
a phase that actually plumbs it through."

Expanding A17 to bind `pc-get-os` in `linux_arm64_main.cpp` /
`gk_android_main.cpp` (the two unlock-list-omitted files where the
binding chain lives) would technically pass the validator's lock
checks 1, 2, and 4 — but it would be a multi-class fix in one phase,
which cookbook §11 explicitly flags as "a red flag for cheat-shaped
logic". The supervisor's A15 revert chain shows what happens when
this red flag is ignored.

## Verified anti-cheat invariants — still all clean

- 0 dodge markers (`gk_recover_to_renderer`, `forced-recovery
  handoff`, `g_fault_recovery_armed`) anywhere in `android/` or
  `game/`.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`
  additions since the A16 close commit.
- 0 new `*_stubs.cpp` files.
- 0 inline `*_stub(` additions.
- 0 rename-evasion stub-shaped `*_(impl|bridge|shim|trampoline|proxy|
  bound|hook)` functions with bodies of literally `return 0;`.
- 0 modifications to any of the validator's 18 locked files.
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- x86 CGOs byte-identical to A2 baseline.
- ENGINE.CGO CBZ-Xt,+40 fingerprint: 5 hits (the pre-A17 baseline).
- arm64 CGOs byte-differ from A11 baseline ONLY at IDIV/UDIV sites
  (70 instances of the 6-7 instruction preserve-X8 sequence), not
  evenly distributed across files — the A14 baseline elsewhere is
  preserved byte-for-byte.

## Recommendation

The orchestrator's `check_stuck` trips when the same failure
fingerprint repeats 3 times in a row (STUCK_REPEAT_THRESHOLD = 3 in
orchestrator.py:92). Attempt-1's fingerprint is `3afd18938cb6`;
attempt-2's will be identical (the validator output is deterministic
from the unchanged state). A third attempt will trip the threshold
and trigger the supervisor pivot path.

The two clean pivots, in supervisor-precedent order of preference:

**Option A (mirrors A15 precedent — supervisor-stated default):**
Relax `phase-A17-idiv-emitter-spill.sh` check 9 to mirror the prompt
text. Concretely, replace:

```bash
# 9. D4 device validator passes
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a17-d4.log 2>&1 \
    || { tail -40 /tmp/a17-d4.log; fail "D4 device validator failed on A17 fix"; }
```

with a check that confirms the device boot log shows > 166
`link finish:` lines (the operational criterion the prompt actually
specifies, already present at the bottom as check 9b). Then check 9b
becomes redundant and the validator passes the A17 deliverable
honestly. The D4-full-chain check moves to a downstream phase (A18 or
later) where the unlock list permits binding `pc-get-os`.

**Option B (more work, advances boot further):**
Author A18 with the `klink.{cpp,h}` unlock to add
`klink_a17_ensure_pc_get_os_bound` / `klink_a18_ensure_pc_get_os_bound`
mirroring the A11/A12/A14 pattern. A14 yielded +8 CGOs from binding
`pc-memmove`; A18 should yield a similar increment from binding
`pc-get-os`. The full A14-shape recipe lives in attempt-1's next-
blocker, section "Where pc-get-os should be bound".

Either pivot lets the autoport advance. The IDIV emit fix itself
(commits d70de9cb0 + 9a8b519ad) should remain in place — it is
the correct, in-scope, in-cookbook fix for the A14/A16 IDIV X8
clobber, and both backends benefit (qemu 166→212, device 166→212).

## Honest-exit summary

- A17's stated deliverable (IDIV emitter-side X8 preserve spill) is
  LANDED and stable.
- The validator's check 9 is structurally stricter than the prompt
  text and cannot be satisfied within A17's stated unlock scope.
- The previous (attempt-1) next-blocker analysis is independently
  reproduced and correct.
- The right action is supervisor-pivot (relax validator OR author
  A18), NOT scope expansion within A17.
- The IDIV fix should NOT be reverted — there is NO device regression
  (212 = qemu, both > 166).
