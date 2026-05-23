# A15 attempt-1 — regalloc X8 implicit-clobber fix landed (boot 166 → 212), next-blocker is `pc-get-active-display-refresh-rate!` unbound

Authored 2026-05-23 (post-A15 attempt-1, post-commit of the regalloc
X8 implicit-clobber awareness + m_func saved-first in IDIV functions).

## Engineering deliverable summary

- `goalc/regalloc/Allocator_v2.cpp` extended with three narrow,
  `#ifdef GOALC_BACKEND_ARM64`-gated additions:
  1. `a15_arm64_idiv_class(instr)` — detects IDIV/UDIV-class instructions
     via the unique `exclude={RDX}` signature (verified: IR.cpp:816 is
     the SOLE `rai.exclude.emplace_back` site in the tree).
  2. `a15_arm64_implicit_x8_clobber(instr, reg)` — used inside
     `check_register_assign{,_at}` to treat X8 as implicitly clobbered
     across IDIV-class instructions, since `idiv_gpr32` /
     `unsigned_div_gpr32` hardcode `SDIV/UDIV X8, X8, Xn` regardless
     of `m_dest`'s allocated register.
  3. `var_indices_of_function_crossers_large_to_small` extension —
     in any function that contains at least one IDIV-class instruction,
     prepend every `IR_FunctionCall::m_func` vreg to the function-
     crossers list so it gets `prefer_saved = true` allocation. Keeps
     the BLR target off X8 in IDIV-heavy code while leaving the kernel
     dispatcher in gkernel.gc (no IDIVs) at its A11-baseline byte image.

x86 backend is bit-for-bit unchanged (all additions gated on
`GOALC_BACKEND_ARM64`).

## qemu_repro yield: 166 → 212 link-finishes

```
== Phase A15 validator (regalloc fn-ptr live-through) ==
  ok: goalc/regalloc/ has 155 lines diff from A14
  ok: all locked files unchanged since A14
  ok: no dodge in source
  ok: anti-cheat checks all pass
  ok: arm64 CGOs byte-changed vs A11 baseline (regalloc fix landed)
  ok: A15 arm64 CGO baseline saved
  ok: x86 CGOs byte-identical to A2 baseline
  ok: no CBZ-around-call cheat-fingerprint (7)
  ok: no SDIV-X8 → BLR-X8 same-reg pattern in ENGINE.CGO
  ok: qemu repro link-finish count 212 (>166 — advanced past A14)
  ok: fix summary present
FAIL: process crashed during D4 capture (broader detection: narrow F DEBUG, libc Fatal, libsigchain, FATAL EXCEPTION, or GK-DIAG signal handler firing ≥ 10x)
FAIL: D4 device validator failed on A15 fix
```

All A15-specific checks pass. Boot advances 46 CGOs past `debug-sphere`
to `pckernel`. Last 10 link-finishes:

```
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
```

The remaining D4 failure is the new blocker described below.

## The new ceiling — sig=4 SIGILL at unbound `pc-get-active-display-refresh-rate!`

### Crash register dump

```
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x2124d50c58
GK-DIAG x0=0x0
GK-DIAG x1=0x18fe0c
GK-DIAG x2=0x18fe04
GK-DIAG x3=0x3c
GK-DIAG x4=0x2124d50b54
GK-DIAG x5=0x1d6ca34
GK-DIAG x6=0x212afffff0
GK-DIAG x7=0x20d27f
GK-DIAG x8=0x18fe04
GK-DIAG x9=0x2123000000      ←← BLR target = ee_base
GK-DIAG x15=0x2123000000     ←← ee_base
GK-DIAG x16=0x21231972c4     ←← A5 sym-MEM ADRP target
```

PC = X15 = X9 = ee_base. BLR jumped to ee_base, which is the zero word
at the start of the GOAL heap → UDF #0 → SIGILL.

### A11 triplet-scan attribution

```
GK-DIAG A11-DIAG texture-sym-zero: slot=0x21231972c4 value=0x0
  info=0x21231b72c0 hash=0x8d9e8b9a str=0x1d5ab24
  name="pc-get-active-display-refresh-rate!" in_sym_range=1
```

The sym slot is in range, has a valid name string, and **value=0x0** —
classic unbound pc-* helper, same shape as A11 (`gsound-set-flava-bank`),
A12 (`rpc-call`/`rpc-busy?`/`test-load-dgo-c`), and A14 (`__mem-move`).

`hash=0x8d9e8b9a` is the symbol hash for `pc-get-active-display-refresh-rate!`.

## Where the boot is

The CGO that triggered the crash is the one after `pckernel` (which
linked cleanly). Looking at the post-pckernel CGO order, the likely
culprit is `pckernel-impl` or one of the immediately-following PC kernel
helpers. The unbound `pc-get-active-display-refresh-rate!` is a
display/timing helper — consistent with PC kernel runtime init code
needing to read the host's refresh rate.

## Diagnosis — pc-* helper cascade resumed

This is the **same bug class** as A11/A12/A14: a `pc-*` symbol that the
GOAL kernel expects to find bound to a C-side runtime helper, but no
binding exists. The kernel uses these to query/mutate host state
(refresh rate, frame rate, display mode, mem-move, RPC, DGO test load,
etc.).

A14's `klink_a14_ensure_pc_memmove_bound` pattern is the closest
template: bind the sym hash to a C function (defined in
`game/kernel/common/kmachine.cpp` or `klink.cpp`'s helpers) before any
CGO that references it links.

## Recommended A16 scope

Two candidate shapes, both narrow:

### A16-a — bind `pc-get-active-display-refresh-rate!` specifically

Mirror A14's pattern. Add a `klink_a16_ensure_pc_display_refresh_bound`
helper in `game/kernel/common/klink.cpp` that scans the symbol table
for hash `0x8d9e8b9a` and binds it to a thin C function returning a
reasonable default refresh rate (e.g., 60.0 Hz as a fixed `float`,
since the host headless boot has no display). Chain into the linux-arm64
and android-arm64 boot drivers' pre-version-check hooks.

The implementation skeleton (in pseudocode):

```cpp
// kmachine.cpp (locked for A16 unless explicitly scoped)
extern "C" float a16_pc_get_active_display_refresh_rate() {
  return 60.0f;
}

// klink.cpp (the narrow A16 unlock)
void klink_a16_ensure_pc_display_refresh_bound() {
  constexpr uint32_t kHash = 0x8d9e8b9a;
  for (const auto& sym : symbol_table()) {
    if (sym.hash == kHash) {
      bind(sym, &a16_pc_get_active_display_refresh_rate);
      break;
    }
  }
}
```

Cost: ~30 LoC, mirrors A14. Probability of advancing the boot: high.

### A16-b — bind ALL pc-display-rate-class helpers as a small batch

The A11-DIAG triplet scan in the GK-DIAG dump also showed nearby unbound
slots that look like pc-* display helpers:

- `pc-get-active-display-refresh-rate!` — value=0x0 (the immediate crash)
- `pc-set-frame-rate*!` — value=0x0 (in the triplet scan)

Plus likely peers (these will surface one-by-one if A16-a is too
narrow):
- `pc-get-display-mode*!` is already bound (value=0x1c4b84) — so don't
  duplicate.
- Other `pc-*-display-*` / `pc-*-frame-rate-*` symbols may need
  scanning.

A bulk-bind would unlock the entire display/timing sub-cluster at once
instead of cascading three or four more A-phases.

Cost: ~80 LoC. Higher risk (some pc-* helpers may need real runtime
state, not just constants — refresh-rate=60 is fine, but
set-frame-rate is mutator and may need to actually store somewhere).

## Recommendation

**A16-a** (narrow, mirrors A14). Bind just `pc-get-active-display-refresh-rate!`
to a constant-returning C helper. If the cascade continues with another
pc-* unbound at the next CGO past `pckernel-impl`, the supervisor can
pivot to A16-b/A-bulk based on the next-blocker report from A16-attempt-1.

## What changed since A14

| Layer                              | A14 attempt-1            | A15 attempt-1 (this)              |
|------------------------------------|--------------------------|-----------------------------------|
| arm64 IDIV/UDIV X8 awareness       | invisible to regalloc    | implicit-clobber detected         |
| m_func of CALL_R64 in IDIV funcs   | temp-first (often X8)    | saved-first (X3, X5, X12, ...)    |
| qemu_repro link-finish count       | 166                      | 212                               |
| sin*! call-site crash              | sig=7 SIGBUS @ unaligned PC | gone                           |
| Next blocker shape                 | regalloc fn-ptr/SDIV     | unbound pc-* sym                  |
| Next blocker location              | post-debug-sphere CGO    | post-pckernel CGO                 |
| Next blocker sym                   | n/a                      | `pc-get-active-display-refresh-rate!` |
| Validator check 7d (SDIV→BLR)      | n/a (new check)          | 0 hits (no false positive)        |
| Validator check 8 (qemu strict)    | passed (166, >158)       | passed (212, >166)                |
| Validator check 9 (D4 device)      | failed (sin*! crash)     | failed (different bug class)      |
| Validator check 10 (desktop smoke) | passed                   | passed                             |
| Recommended next phase             | A15 (regalloc fix)       | A16 (bind pc-get-active-display-refresh-rate!) |

## Anti-cheat invariants — A15 status

- 0 dodges (gk_recover_to_renderer / forced-recovery handoff /
  g_fault_recovery_armed): clean.
- 0 abort/weak/`_stubs.cpp`/inline-`_stub(` additions.
- 0 rename-evasion stub-shaped functions added.
- 0 modifications to `IGenARM64.{cpp,h}` / `ObjectGenerator.{cpp,h}` /
  `CodeGenerator.{cpp,h}` / `IR.{cpp,h}` / `asm_funcs_arm64.s` /
  `kscheme.cpp` / `kmachine.cpp` / `IOP_Kernel.{cpp,h}` /
  `linux_arm64_runtime_compat.cpp` / `android_runtime_compat.cpp` /
  `klink.{cpp,h}`.
- 0 modifications to `.autoport/lib/*` or `.autoport/validators/*`.
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-changed vs A11 baseline (= regalloc fix produced new
  bytes, as required by validator check 5).
- ENGINE.CGO CBZ-Xt,+40 occurrences = 7 (well below 10-cheat threshold).
- ENGINE.CGO SDIV-X8 → BLR-X8 same-reg pattern = 0 occurrences.
- ENGINE.CGO BLR X8 instances = 929 (each is an honest, fingerprint-
  safe call site — none within 30 words of an SDIV X8,X8,X9 without an
  LDR W8/X8 reload between).
- Boot reaches 212 link-finishes on qemu (up from A14's 166).

## Honest exit

The A15 prompt:

> If the regalloc fix lands but another bug surfaces (likely — the boot
> will go deeper), commit the fix + new baseline + write
> `A15-attempt-N-next-blocker.md`. The supervisor will read it and
> author A16.

This attempt-1 fires that clause cleanly. The X8 implicit-clobber +
m_func saved-first changes landed without regression (KERNEL.CGO
byte-identical to A11 in non-IDIV functions, the kernel dispatcher
still works), arm64 boot advanced 46 CGOs past `debug-sphere`, and the
new blocker is named: unbound `pc-get-active-display-refresh-rate!`
(hash `0x8d9e8b9a`, slot `0x21231972c4`).

Stopping here is the right move. Rate-budget at 85%+ at A15 start —
spinning attempt-2 against an out-of-scope sym-binding gap would
require unlocking `klink.cpp` / `kmachine.cpp` (locked from
A11/A12/A14) and would be the same shape as the inline-stub anti-
patterns the validator already rejects. Let the supervisor author A16
with the right unlock profile (narrow klink helper, A14-template).
