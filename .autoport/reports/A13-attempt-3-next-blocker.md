# A13 attempt-3 — validator checks 1-8 pass post-SIGPIPE-fix; check 9 names `__mem-move` as the next unbound-sym blocker (A14 scope)

Authored 2026-05-23 (post-A13 attempts 1+2, post-supervisor SIGPIPE
fix in commit `a596e5798`). The engineering A13 deliverable (mutex
pre-init + RPC-drain cothread + dispatch driver in
`a13_arm64_init_iop`) is in place since commit `59090a9e3` and the
qemu repro now correctly emits its summary line — checks 1-8 of
`phase-A13-iop-kernel-mutex-init.sh` pass end-to-end. The remaining
failure is check 9 (D4 device sub-validator), which fails because
the post-A13 on-device boot crashes on the next bug class — exactly
the situation A13's prompt anticipated under "Honest exit condition"
(A12's "next next-blocker" prediction). This attempt-3 names that
next blocker concretely so the supervisor can author A14.

## Validator output (end-to-end, real run)

Run with the user's Redmi Note 9 Pro (`eae4df44`) attached on USB
and the supervisor's qemu_repro SIGPIPE fix in place:

```
== Phase A13 validator (IOP_Kernel mutex init) ==
  ok: A13-unlocked files have 299 total lines diff from A12
  ok: codegen + asm + kscheme + klink.h + IOP_Kernel locks intact since A12
  ok: no dodge in source
  ok: anti-cheat checks all pass
  ok: pthread_mutex_init() call present (4)
  ok: fix summary present
  ok: x86 CGOs byte-identical to A2 baseline
  ok: arm64 CGOs byte-identical to A11-baseline-arm64-cgo-hashes.txt
  ok: no CBZ-around-call cheat-fingerprint in ENGINE.CGO (4)
  ok: qemu repro link-finish count 158 (>156 — boot advanced past A12 ceiling)
  …
  TOTAL link finishes: 158 (158 unique CGOs linked)
  ActivityManager: Process .*has died        1
  GK-DIAG                                    118
FAIL: process crashed during D4 capture (broader detection: narrow F DEBUG, libc Fatal, libsigchain, FATAL EXCEPTION, or GK-DIAG signal handler firing ≥ 10x)
FAIL: D4 device validator failed on A13 fix
```

The SIGPIPE fix did exactly what attempt-2's analysis predicted:
qemu_repro emits `158 'link finish:' lines captured.` and check 8
passes. Check 9's D4 invocation reaches the device, builds + installs
+ launches the APK, captures logcat, and trips
`boot_log_scan.sh::boot_log_crashed` on the GK-DIAG line count being
≥10. One crash dump now emits ~118 GK-DIAG lines (header + 31 GPR +
SP + A11-DIAG triplet scan + A12-DIAG provenance + LR-relative disasm
+ stack dump), so even a single crash always trips the threshold.

## The new ceiling — sig=4 SIGILL at PC=ee_base inside dma-buffer's top-level

Identical bug class to A11's `__pc-get-mips2c`: a sym slot loaded 0,
`X9 = W9 + X15` made the BLR target equal to ee_base, BLR jumped to
the EE main-mem's first word (a UDF #0) → SIGILL.

### Device crash registers (from `.autoport/reports/D4-boot.log`)

```
GK-DIAG sig=4 fault=0x720c05a000 pc=0x720c05a000 lr=0x720c54b37c
GK-DIAG x9=0x720c05a000    ←← x9 = ee_base (was loaded 0, +X15 → ee_base)
GK-DIAG x15=0x720c05a000   ←← ee_base on device
GK-DIAG x16=0x720c1aea1c   ←← ADRP/ADD target = the unbound sym slot
GK-DIAG A12-DIAG stack-fnptr-zero: no LDR X9,[SP,#?] in lr-240..lr-4
  (BLR target X9, push_bytes=48) — non-call_r64 shape
GK-DIAG A11-DIAG texture-sym-zero: slot=0x720c1aea1c value=0x0
  info=0x720c1cea18 hash=0x9290899a str=0x4f14e4 name="__mem-move"
  in_sym_range=1
```

### qemu crash registers (matching pattern, different addresses)

```
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x21235342ac
GK-DIAG x9=0x2123000000     ←← same: x9 = ee_base
GK-DIAG x15=0x2123000000    ←← ee_base on qemu (different from device's)
GK-DIAG A11-DIAG texture-sym-zero: slot=0x2123194b04 value=0x0
  info=0x21231b4b00 hash=0x9290899a str=0x534414 name="__mem-move_B="
  in_sym_range=1
```

The hash `0x9290899a` matches on both — same unbound symbol. The
displayed name differs slightly between binaries (qemu shows
`__mem-move_B=`, device shows `__mem-move`) because the A11
triplet-scan's str-pointer dereference reads from the on-binary
.rodata copy, which has slightly different padding/neighbour bytes
in the two builds. The hash is authoritative; the canonical name in
the GOAL kernel is **`__mem-move`**.

### What dma-buffer needs `__mem-move` for

`__mem-move` is the GOAL kernel's fast-memcpy entry point. dma-buffer
sets up the rendering DMA-chain buffers and copies templates into
them at top-level init time. The first CGO past A11/A12's ceiling
that uses `__mem-move` in its top-level is the one that crashes:

```
link finish: gsound
link finish: transformq
link finish: collide-func          ← last CGO that linked + ran top-level
                                     (collide-func.gc doesn't call __mem-move)
GK-DIAG sig=4 …                    ← dma-buffer.gc's top-level fired
                                     `(__mem-move …)` against the unbound slot
```

## Why it's unbound on linux-arm64 / Android

`__mem-move` has a C implementation already wired upstream:

```
game/kernel/common/kmachine.cpp:1095
  make_func_symbol_func("__mem-move", (void*)pc_memmove);
```

This registration happens inside `init_common_pc_port_functions`,
which is called from each game's `kmachine.cpp` (jak1/jak2/jak3/jakx).
On Android (and linux-arm64 by inheritance through the same compat
layer) the override at `android/android_runtime_compat.cpp:714`
**deliberately skips the pc-* helper registration**:

```cpp
void init_common_pc_port_functions(…) {
  …
  // We deliberately do NOT register the 100+ pc-* helper functions.
  // Most of them route through Display::GetMainDisplay() / Gfx::*
  // which aren't wired on Android yet. GOAL bytecode that references
  // them will see unresolved symbols and the linker will log a
  // warning; that's the honest "Android port pending" signal rather
  // than a silent fake.
  __android_log_print(…, "init_common_pc_port_functions: skipped pc-* registration …");
}
```

A11 worked around this for `__pc-get-mips2c` specifically by adding
`klink_a11_ensure_pc_mips2c_bound` to the pre-version-check hook. A12
followed the same pattern for the IOP RPC syms
(`klink_a12_ensure_sound_rpc_bound`). Neither added `__mem-move`
because gsound/dma-buffer's top-level weren't reachable until A13
unblocked them via the IOP_Kernel mutex init.

The Android override's comment ("GOAL bytecode that references them
will see unresolved symbols and the linker will log a warning")
under-states the impact: the GOAL linker doesn't fault on missing
syms — it leaves the sym slot at 0, and the first BLR-via-slot fires
a SIGILL via the ee_base trampoline. That's the bug class A11, A12,
and now A14 all clean up site-by-site.

## Recommended A14 scope

Three candidates with increasing scope, mirroring A11/A12 framing:

### A14-a — bind `__mem-move` alone (smallest, mirrors A11)

Add `klink_a14_ensure_pc_memmove_bound` to `game/kernel/common/klink.cpp`
that does exactly what A11 did for `__pc-get-mips2c`:

```cpp
void klink_a14_ensure_pc_memmove_bound() {
  // Idempotent: bail if slot already non-zero.
  auto sym = find_symbol_from_c("__mem-move");
  if (sym && /* slot has value */) return;
  auto fn = jak1::make_function_symbol_from_c("__mem-move", (void*)pc_memmove);
  printf("A14-DIAG sym-bind-trace: bound __mem-move to pc_memmove (value …)\n");
}
```

Chain it onto the pre-version-check hook the same way A11 + A12 do.
Cost: ~10 LoC + helper invocation.

**Pros**: smallest scope, honest exactly to the named symbol. Will
expose the *next* unbound sym, allowing iterative A15/A16/… discovery.

**Cons**: dma-buffer's top-level probably uses other pc-* helpers
(`__send-gfx-dma-chain`, `__pc-texture-upload-now`, ...). A14-a may
unlock 1-2 more CGOs before hitting the next one. That's fine —
each iteration narrows the surface honestly.

### A14-b — bind every pc-* helper that has a non-graphics C impl (medium)

Walk `init_common_pc_port_functions`'s body in
`game/kernel/common/kmachine.cpp` (lines ~1090-1180), and bind every
helper whose C implementation does NOT depend on `Display::*` or
`Gfx::*`. Examples likely safe:

- `__mem-move` → `pc_memmove` (string.h-based)
- `__read-ee-timer` → `read_ee_timer` (clock_gettime-based)

Skip the graphics ones (`__send-gfx-dma-chain`, `__pc-texture-upload-now`,
etc.) — those are still pending the Android renderer port and
binding them now would silently fail differently.

**Pros**: unblocks more CGOs per phase. Lines up with the existing
Android override's intent.

**Cons**: needs careful audit of each helper's dependencies. Slight
risk of binding something that needs Display::Get*() and tripping
a different crash class.

### A14-c — fix `init_common_pc_port_functions` itself (largest)

Edit the Android override so it DOES call
`make_func_symbol_func(…)` for the non-graphics helpers (replicate
the upstream body for the safe subset), and only skip the graphics
ones.

**Pros**: structurally cleanest. No klink-helper accretion.

**Cons**: requires unlocking `android_runtime_compat.cpp` for a
non-trivial rewrite. Higher review surface. Same anti-cheat risk
(must not stub-shape any helper).

## Recommendation

**A14-a** (smallest). Follows the A11 + A12 precedent, lets us see
the next failure honestly, keeps the unlock narrow. The pattern is
mechanical at this point — each A-phase names one (or a handful) of
unbound pc-* helpers and binds them via klink helper.

## What changed since attempt-1 + attempt-2

| Layer                           | attempt-1            | attempt-2            | attempt-3 (this)         |
|---------------------------------|----------------------|----------------------|---------------------------|
| A13 engineering (mutex init)    | landed (`59090a9e3`) | landed              | landed (unchanged)        |
| qemu_repro 158 link-finishes    | claimed pass         | identified SIGPIPE  | confirmed (raw log)       |
| qemu_repro.sh SIGPIPE fix       | not yet              | next-blocker only   | landed (`a596e5798`)      |
| Validator check 8 passes        | aspirational         | NO (SIGPIPE)        | YES                       |
| Device attached for check 9     | NO                   | NO                  | YES (Redmi Note 9 Pro)    |
| Check 9 D4 sub-validator        | not reached          | not reached         | reached, fails on `__mem-move` |
| Named next-blocker              | new dma-buffer SIGILL| same                | `__mem-move` (hash 0x9290899a) |

The full validation chain now runs end-to-end. The only remaining
failure is the next bug-class crash, which is A14's scope.

## Anti-cheat invariants — A13 status (unchanged from attempt-2)

- 0 dodges, 0 abort/weak additions, 0 new `_stubs.cpp`, 0 inline
  `_stub(` additions, 0 rename-evasion stub-shaped functions.
- 0 modifications to `.autoport/lib/*` / `.autoport/validators/*`
  in this attempt (the SIGPIPE fix to `qemu_repro.sh` was supervisor-
  authored in `a596e5798`, NOT a phase-claude edit).
- 0 modifications to codegen (IGenARM64, ObjectGenerator,
  CodeGenerator, IR), asm trampoline (`asm_funcs_arm64.s`),
  `kscheme.cpp`, `klink.h`, or `IOP_Kernel.{cpp,h}`.
- x86 CGOs byte-identical to A2 baseline (check 7 passes).
- arm64 CGOs byte-identical to A11 baseline (check 7b passes).
- ENGINE.CGO has 4 CBZ-Xt,+40 occurrences (well below the 10-cheat
  threshold; consistent with A11+A12 baseline).
- Boot reaches 158 link-finishes (matches qemu) on both qemu and
  device — no regression vs A11/A12's 156 ceiling.

## Honest exit

A13 prompt:

> If A13-a's mutex init lands but boot then hits a different IOP
> infrastructure issue (e.g. a synchronous RPC needing a real IOP
> thread, per A12 next-blocker's "next next-blocker" prediction),
> commit the mutex init + write A13-attempt-N-next-blocker.md
> analysing the new failure with the same A13-b/c framework. The
> supervisor will author A14.

This attempt-3 fires exactly that clause:
- The mutex init landed (`59090a9e3`).
- The boot hits a different bug class — not an IOP infrastructure
  issue per se but a related unbound-sym class (`__mem-move`,
  registered via `init_common_pc_port_functions` whose Android
  override skips it).
- The next blocker is named (`__mem-move`, hash `0x9290899a`) with
  cross-reference to its existing C impl (`pc_memmove` at
  `kmachine.cpp:1095`).
- The A14-a/b/c framework above gives the supervisor a clean
  pick-and-author choice.

Rate-budget: the prompt's "85% halt threshold" caution applies.
This attempt-3 commits the next-blocker + the D4 boot evidence and
stops, rather than spinning a fourth retry against an
A13-out-of-scope bug class.
