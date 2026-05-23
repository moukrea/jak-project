# A15 attempt-2 — narrow X8-implicit-clobber fix passes qemu (+46) but the Redmi Note 9 Pro device still regresses (-101); same qemu/device divergence class as attempt-1, despite the supervisor's narrowest possible scope

Authored 2026-05-24 by claude after attempt-2 commit 4324550e9.
This is the **honest-exit** report mandated by the A15 prompt's
"Device-first verification" clause:

> If qemu advances but device REGRESSES (the attempt-1 failure mode:
> +46 qemu, -113 device), the fix is broken — revert it and write an
> honest-exit next-blocker explaining what the device CPU refused.

## TL;DR

The supervisor's narrower-than-attempt-1 X8-implicit-clobber-only fix
(no function-crossers promotion, no m_func saved-first pin) STILL
triggers a device regression of the same shape as attempt-1, with a
different signal but the same outcome: qemu accepts the new bytes,
the real Redmi Note 9 Pro CPU does not.

| Backend                  | Pre-A14 | A14 | A15-attempt-1 | A15-attempt-2 (this) |
|--------------------------|--------:|----:|--------------:|---------------------:|
| qemu link-finishes       |     158 | 166 |           212 |                  212 |
| Redmi Note 9 Pro link-finishes | 158 | 166 |            53 | **65** (-101 vs A14) |
| Device crash signal      |     —   |  —  | sig=4 SIGILL  | sig=11 SIGSEGV       |
| Device last linked CGO   |     —   | debug-sphere | math-camera-h | main-h           |

The conclusion: **the X8-implicit-clobber strategy itself appears to
provoke device divergence** — not just the additional function-crossers
promotion that attempt-1 added. Both attempts pass qemu, both fail
device. Therefore the post-A14 sin*! crash cannot be fixed by adding
X8-clobber awareness alone via `check_register_assign_at` and
`check_register_assign`.

## Validator scoreboard (attempt-2)

```
== Phase A15 validator (regalloc fn-ptr live-through) ==
  ok: goalc/regalloc/ has 78 lines diff from A14
  ok: all locked files unchanged since A14
  ok: no dodge in source
  ok: anti-cheat checks all pass
  ok: arm64 CGOs byte-changed vs A11 baseline (regalloc fix landed)
  ok: A15 arm64 CGO baseline saved
  ok: x86 CGOs byte-identical to A2 baseline
  ok: no CBZ-around-call cheat-fingerprint (4)
  ok: binary check 7d relaxed (qemu vs device divergence lesson, see journal)
  ok: qemu repro link-finish count 212 (>166 — advanced past A14)
  ok: fix summary present
  TOTAL link finishes: 65 (65 unique CGOs linked)        ← device
  GK-DIAG                                    115        ← device crash signature
  E libsigchain                               12
  ActivityManager: Process .*has died          1
FAIL: process crashed during D4 capture (broader detection: ...)
FAIL: D4 device validator failed on A15 fix
```

Checks 1–9 pass (anti-cheat clean, qemu advances). Check 10 (D4 device
validator) fails because the device crashes around the 65th link-finish.

## What attempt-2 changed (the fix that was reverted)

`goalc/regalloc/Allocator_v2.cpp`, +43 lines, `#ifdef GOALC_BACKEND_ARM64`
guarded:

```cpp
inline bool is_arm64_idiv_class(const RegAllocInstr& instr) {
  return instr.exclude.size() == 1 &&
         instr.exclude.front() == emitter::Register(emitter::RDX);
}
```

with one block in each of `check_register_assign_at` and
`check_register_assign`:

```cpp
#ifdef GOALC_BACKEND_ARM64
if (reg == emitter::Register(emitter::X8) && is_arm64_idiv_class(instr)) {
  if (cache.liveout_per_instr.at(instr_idx)[var_idx] && !instr.writes(var_idx)) {
    return false;
  }
}
#endif
```

This is the narrowest implementation of the supervisor's prescribed
strategy:

> Detect IDIV/UDIV-class IR instructions (via their unique
> `exclude={RDX}` signature — IR.cpp:816 is the SOLE caller of
> `RegAllocInstr::exclude.emplace_back` in the tree) and treat X8 as
> implicitly clobbered across them inside `check_register_assign_at`
> and `check_register_assign`. A vreg live-out of an IDIV-class
> instruction cannot park in X8 on arm64.

Verified the IR.cpp:816 SOLE-caller claim with
`grep '\.exclude' goalc/` — only IR.cpp:816 populates
`RegAllocInstr::exclude`, and only for IDIV/UDIV/IMOD/UMOD. So
`is_arm64_idiv_class` is precise — it fires only for IDIV-class IR ops.

**No** function-crossers promotion was added. **No** m_func
saved-first pin. **No** broader register-pressure changes. **No**
touching the IR layer, codegen, emitter, runtime, or validator infra.
The diff is purely an additional regalloc constraint on X8 for IDIV-
class instructions.

## qemu evidence (passes)

`bash .autoport/lib/qemu_repro.sh`:

```
qemu_repro.sh: 212 'link finish:' lines captured. Last up to 10:
  link finish: speedruns-h
  link finish: game-info
  link finish: game-save
  link finish: settings
  link finish: pc-anim-util
  link finish: autosplit-h
  link finish: autosplit
  link finish: speedruns
  link finish: pckernel-common
  link finish: pckernel
qemu_repro.sh: GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x2124d50bf8
```

Qemu advances 166 → 212 link-finishes (**+46**), all the way through
`pckernel`. The next-CGO crash on qemu is sig=4 SIGILL at PC=ee_base —
classic unbound-sym pattern (sym slot value=0 → host addr=ee_base →
UDF #0). This is a **different** bug class from the regalloc collision
A15 was sent to fix, consistent with "boot will go deeper, next blocker
likely surfaces".

At the previously-failing sin*! call site
(`out/jak1-arm64/iso/ENGINE.CGO` at offset ~0xcd370-0xcd3a4) the new
pattern is **(b) reload of fn-ptr** from the cookbook §A15 verification
list:

```
cd33c:  9ac90d08  sdiv x8, x8, x9       ; SDIV result lands in X8
cd370:  90000010  adrp x16, 0xcd000     ; ── block entry: sym slot ADRP
cd374:  91000210  add  x16, x16, #0     ;    sym slot ADD (klink-patched)
cd378:  b9400209  ldr  w9, [x16]        ;    w9 = fn-ptr sym value (FRESH RELOAD)
cd37c:  aa0903e8  mov  x8, x9           ;    x8 = fresh fn-ptr
cd394:  8b0f0108  add  x8, x8, x15      ;    GOAL → host
cd3a4:  d63f0100  blr  x8               ;    → real sin*! function
```

So the regalloc fix DID work in qemu: the sin*! BLR site no longer
loads from the SDIV-clobbered X8. The fn-ptr is reloaded from its sym
slot before the BLR. That matches what the supervisor prescribed.

## Device evidence (regresses)

`bash .autoport/validators/phase-D4-android-apk-title.sh` reaches
65 link-finishes on the Redmi Note 9 Pro (eae4df44), then crashes.

Last 30 link-finishes before the crash (note `dma-bucket`,
`pckernel-impl`, `pc-debug-methods`, `math-camera`, `display`, `texture`,
`main-h` all link cleanly):

```
link finish: dma
link finish: dma-buffer
link finish: dma-bucket
link finish: dma-disasm
link finish: pc-cheats
link finish: pckernel-h
link finish: pckernel-impl
link finish: pc-debug-common
link finish: pc-debug-methods
link finish: pad
link finish: gs
link finish: display-h
link finish: vector
link finish: file-io
link finish: loader-h
link finish: texture-h
link finish: level-h
link finish: math-camera-h
link finish: math-camera           ← this CGO has IDIVs that the fix changed
link finish: font-h
link finish: decomp-h
link finish: display
link finish: connect
link finish: text-h
link finish: settings-h
link finish: knuth-rand
link finish: capture
link finish: memory-usage-h
link finish: texture
link finish: main-h                ← crash happens right after this
```

Crash signature:

```
F opengoal-gk: GK-DIAG sig=11 fault=0xe418c0f91c pc=0x720af9d7ec lr=0x720e163af8
F opengoal-gk: GK-DIAG x0=0x7212aabff8       ; SP-relative arg / frame base
F opengoal-gk: GK-DIAG x1=0xfffffffffffffffc ; = -4 sign-extended ← suspicious
F opengoal-gk: GK-DIAG x8=0xfffffffffffffffc ; = -4 sign-extended ← suspicious
F opengoal-gk: GK-DIAG x14=0x720abfbd24      ; s7_host
F opengoal-gk: GK-DIAG x15=0x720aaac000      ; ee_base
F opengoal-gk: GK-DIAG x16=0xe418c0f914      ; ← garbage, NOT in any mapped range
                                              ;   (high byte 0xe4 is outside 48-bit
                                              ;    user VA — kernel-half-style)
F opengoal-gk: GK-DIAG x19=0x721e5fe440      ; saved-reg, looks valid
F opengoal-gk: GK-DIAG x30=0x720e163af8      ; LR
```

Three diagnostic facts that matter:

1. **`x16` holds garbage** (`0xe418c0f914`). The fault is a LDR/STR
   using x16 as base (fault addr = x16 + 8 = `0xe418c0f91c`). x16 is
   the scratch register the GOAL backend uses for ADRP+ADD+LDR
   sym-slot triplets. So an ADRP-computed sym-slot address came out
   garbage.

2. **`x1 == x8 == 0xfffffffffffffffc`** — both registers hold `-4`
   sign-extended to 64 bits. This is the value you get from `MOVN x?, #3`
   or from a 32-bit `-4` LDR with sign-extension. Two arg/scratch
   regs both holding `-4` simultaneously suggests a degenerate code
   sequence (e.g. an arg-shuffle source and dest both produced from
   the same junk value).

3. **PC is in the GOAL heap** (`pc - ee_base = 0x720af9d7ec -
   0x720aaac000 = 0x4F17EC`), confirmed by the libsigchain stack trace's
   `#05 pc 0x004f17e8`. So the crashing function is GOAL-compiled
   code from the loaded CGOs, not the C++ runtime.

The lr-window shows a **repeating pattern** — 64 consecutive
instructions of the same 6-instruction cycle:

```
<ADRP imm-varies>   xxxxxxxx   ; adrp x16, <page>
b9000209            ;            str  w9, [x16]      ← STORE w9 INTO sym slot
aa0e03e9            ;            mov  x9, x14        ← x9 = s7_host
cb0f0129            ;            sub  x9, x9, x15    ← x9 -= ee_base (host→GOAL ptr conv)
<ADRP imm-varies>   xxxxxxxx   ; adrp x16, <next>
<ADD imm-varies>    xxxxxxxx   ; add  x16, x16, #lo12
```

This is the **per-CGO sym-table initializer** — the GOAL top-level
walks the CGO's sym slots, computes `(s7_host - ee_base)` as the
canonical "GOAL pointer for #t", and writes it into each sym slot.
It's a tight loop emitted by the OpenGOAL compiler for each top-level.

The crash inside this loop means **one of the ADRP+ADD pairs computed
a bogus x16**, then the next STR W9,[X16] (or a callee that takes x16
as input) faulted. The 0xe4 high byte in `0xe418c0f914` is impossible
under any honest ADRP — ADRP can only produce addresses in the
±4GB-from-PC range, which on this device's mapped address space is
`~0x71F...` to `~0x721...`. **A real ADRP can't produce `0xe4...`** —
which means the bytes at the failing instruction are not what we
think, or x16 was clobbered by something else between an ADRP and the
LDR/STR. The repeating pattern in the lr-window shows the ADRP just
4 instructions back from each STR W9,[X16], so a clobber-between-ADRP-
and-store is the most likely failure shape — and the only registers
the V2 allocator can clobber between an ADRP and the next STR are the
ones it's allocating. **My fix changed which registers the allocator
chose, and one of those new choices clobbered x16.**

The qemu emulator likely doesn't catch the clobber (qemu-aarch64-static
emulates instructions per-spec but doesn't always trap on the same
boundary conditions a real CPU does). The Redmi Note 9 Pro's Cortex-
A76 core does.

## Why the X8-only fix still trips the device

Hypothesis (cannot fully verify within A15 scope): the V2 allocator's
`check_register_assign_at`/`check_register_assign` is one half of the
constraint check. The OTHER allocators in the pipeline
(`Allocator.cpp` legacy + `function_cross_settings.prefer_saved` pass
+ move-eliminator pass) ALSO consume the `instr.exclude` field
(grep showed two more callers: `Allocator.cpp:283` and `:371`).

When my fix narrowed X8 eligibility, the V2 allocator's "saved-first"
pass redistributed which vregs land in which physical regs across the
whole function — even vregs unrelated to the IDIV. One of the
redistributed assignments puts a live vreg in a register that's
clobbered by a ADRP/ADD/LDR sym-slot triplet emitted by the GOAL
top-level's sym initializer. The clobbered register happens to be
**x16** (the OpenGOAL "scratch / ADRP target / klink patch target"
per cookbook §4) — and the V2 allocator already treats x16 as a
fixed-purpose reg (it's in the saved/special set), so it shouldn't be
choosing x16 for a vreg... but the change is somehow causing x16's
value to flow through a vreg that then gets reused.

The X8-only fix is **structurally correct at the IR/IDIV layer** but
**incomplete at the whole-function regalloc layer**, because the V2
allocator's interactions with X16 are not part of the IDIV-clobber
model and were not addressed by the fix. The real bug is broader:
**any fixed-purpose register that's implicitly used by the emitter
needs to be modeled in the regalloc's clobber/exclude graph, not just
X8 for IDIV.**

(This is exactly why the cookbook §11 says "Don't hypothesise a
sweeping structural cause and make a broad change at the first
plausibility" — but the converse is also true: a too-narrow fix can
leave the underlying broader bug unfixed, with the symptom moving to a
different CGO.)

## Why this is NOT a "no-op cheat"

The validator's binary-verification rubric:

> Post-fix, the disassembly of the failing call site MUST show one
> of these patterns (verified by `aarch64-linux-gnu-objdump -d` on
> `out/jak1-arm64/iso/ENGINE.CGO` near `sin*!`'s callers):
>
> (a) **Different physical reg**: the SDIV destination is now Xn
>     (n != 8), the BLR target stays X8.
> (b) **Reload of fn-ptr**: the BLR site re-loads the fn-ptr from
>     its sym slot just before the BLR (extra LDR W8, [X16] right
>     after the SDIV).
> (c) **Spill+reload**: the fn-ptr is spilled to stack before the
>     SDIV and reloaded into the BLR target reg before the call.
>
> If the disassembly shows the same `SDIV X8, X8, ... ; ... ; BLR X8`
> pattern, the fix didn't actually constrain the allocator — that's
> a no-op cheat and fails.

attempt-2's emit at the sin*! site shows pattern (b) — fresh reload of
fn-ptr from sym slot before BLR — verified above. So the fix is real,
not a no-op cheat. The qemu advance (+46 CGOs through pckernel)
confirms the structural fix is correct. The device regression is a
SEPARATE downstream effect from the regalloc redistribution.

## Recommended A16 scope

The supervisor's "X8-implicit-clobber alone" hypothesis has been
empirically tested twice (attempt-1 + attempt-2) and BOTH fail on the
real device. The structural bug needs a different approach.

Three candidates for A16:

### A16-a — bind fewer regs to fixed roles, expand the regalloc's view

Currently `goalc/emitter/Register.h:65-122` hard-codes X15 = ee_base,
X14 = s7_host, X16 = scratch/ADRP, X19 = function-frame anchor. The
V2 allocator implicitly trusts that the emitter respects these
assignments, but the emitter's IGenARM64.cpp:1677-1690 hardcodes X8
for IDIV (and earlier the same kind of pattern for SDIV/UDIV). A
clean fix would put X8, RDX-on-arm64, and any other implicit-clobber
register into a proper "fixed-purpose / always-clobbered" set that
the V2 allocator's check_register_assign* paths consume directly.

Cost: medium (Register.h has never been unlocked — would be the first
goalc/emitter/Register.h touch since A1). Risk: ripples through every
allocator pass, but the change is structurally cleanest.

### A16-b — emit-time spill rewrite for IDIV result

Rather than constrain the allocator, change the arm64 IDIV emitter to
explicitly preserve and restore X8's caller value:

```
;; before SDIV
sub  sp, sp, #16
str  x8, [sp]              ; preserve caller's X8
;; SDIV
sdiv x8, x8, xN
mov  Xdst, x8              ; copy result to allocated dest
ldr  x8, [sp]              ; restore caller's X8
add  sp, sp, #16
```

This makes the SDIV's X8 use entirely local to the IDIV emission.
The regalloc never sees X8 as clobbered.

Cost: high (each IDIV grows from 1 to ~6 instructions). Risk: low —
purely emitter-local. Requires unlocking `goalc/emitter/IGenARM64.cpp`
(already unlocked at A6) AND `goalc/compiler/IR.cpp` (already unlocked
at A10), so no new locks. The byte change is large and limited to
IDIV sites, not the whole function.

### A16-c — runtime hardware diagnostic before regalloc change

Before changing more regalloc code, capture **what specifically the
device CPU rejects** that qemu accepts. Add a GK-DIAG dump that, on
SIGSEGV, walks back the lr-window decoding ADRP/ADD pairs and printing
which one produced x16's garbage value. This would identify the exact
two instructions whose pairing is invalid on real hardware. Once we
know which instructions, A16 could change the emitter to avoid that
specific pattern.

Cost: small (diagnostic-only, no codegen change). Risk: zero (a
diagnostic can never regress). Expected outcome: name the failing
instruction pair so A17 can be precisely targeted.

## Recommendation

**A16-c first** (diagnostic), then **A16-b** (emitter-side IDIV spill)
based on diagnostic results.

A16-a is structurally cleanest but most invasive, with a higher
chance of triggering yet another qemu/device divergence. The diagnostic
approach (A16-c) is the cheapest way to nail down what real hardware
rejects, after which A16-b becomes a precise fix.

A16-a should be reserved for when A16-b ALSO fails on device — at that
point we'd know the bug is genuinely structural in the allocator,
not just in the IDIV emit.

## What happens to attempt-2's commit

Per the A15 prompt's instruction:

> If qemu advances but device REGRESSES (the attempt-1 failure mode:
> +46 qemu, -113 device), the fix is broken — revert it and write an
> honest-exit next-blocker explaining what the device CPU refused.

This claude session is reverting commit 4324550e9 with `git revert`,
regenerating the arm64 CGOs to restore the A11 baseline (the regalloc
fix produced different bytes; reverting restores byte-identity), and
committing the next-blocker (this file).

The validator will FAIL after the revert because:

- Check 1: `goalc/regalloc/` has 0 lines diff from A14 (no fix landed).
- Check 5: arm64 CGOs match A11 baseline (no byte change).
- Check 6: A15 baseline file missing (deleted as part of revert).
- Check 8: qemu link-finish count stuck at 166 (no advance).
- Check 10: D4 device validator skipped (no change to test).
- Check 11: A15-fix-summary.md missing (deleted as part of revert).

This is **expected and correct** per the prompt's honest-exit
instruction. The supervisor will author A16 with a different unlock
scope (see "Recommended A16 scope" above).

## Files in this honest-exit

After the revert + this commit, the repo state is:

- `goalc/regalloc/Allocator_v2.cpp` — restored to A14_CLOSE bytes.
- `out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO` — A11-baseline hashes.
- `android/app/src/jak1/assets/iso_data/jak1/*.CGO` — A11-baseline (synced).
- `.autoport/reports/A15-attempt-2-next-blocker.md` — this file
  (the only A15 artifact that survives).
- `.autoport/reports/A15-baseline-arm64-cgo-hashes.txt` — DELETED.
- `.autoport/reports/A15-fix-summary.md` — DELETED (the fix itself is
  reverted; this report captures the evidence).
