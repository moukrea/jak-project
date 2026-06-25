# Gcollision-wallslide — fix summary

## Symptom (owner, 2026-06-25)
Hitting a too-high ledge right of the Geyser-Rock steps, Jak slow-slides down the
wall, lands, and ends **crouched** — and on the arm64 Android device he stays
**permanently crouched even with no input**, whereas on x86 he stands straight
back up. This is the residual after the Gcollision-arm `-ffp-contract=off` FMA fix
(which cured the *clip-through* half of the owner's collision report).

## One-line root cause
On arm64 a **clear** head-collision probe is misread as **blocked** because the
mips2c collide-puss-work leaves hand GOALC a **host-pointer** `#f`, while
GOALC-arm64 compares `#f` as a **bare low-32 GOAL pointer** — so `can-exit-duck?`
returns `#f` forever and Jak can never stand up.

## How the symptom reduces to one boolean
- `target-duck-stance:trans` stand-up gate (`goal_src/jak1/engine/target/target.gc:751`):
  `(if (and (or (not (cpad-hold? .. l1 r1)) prevent-duck) (and (not roll) (can-exit-duck?))) (go target-stance))`.
- With no buttons held, the gate is exactly `can-exit-duck?`.
- `can-exit-duck?` (`target-util.gc:636`) builds two head spheres at `*target*
  control trans` and returns `#t` iff `fill-and-probe-using-spheres` finds nothing.
- So **stuck crouched ⟺ can-exit-duck? = #f ⟺ the head-probe wrongly says "blocked".**

## x86-first evidence (device diverges → fixed)
The device has no goalc listener, so every device value was read by gated C++
byte-offset hooks in libgk; x86 ground truth came from the goalc REPL running the
identical probe at the device's exact trans.

1. **Not input.** A reliable read of the same button word `CPadGetData`/`cpad-hold?`
   consume showed cpad L1/R1 hold = 0 on all 2541+ stuck frames. (The prior
   attempt's "hold=0" was garbage from a failed GOAL-pointer deref — `cpadn=-1`.)
2. **Probe divergence localized.** x86 `fill-and-probe-using-spheres` at the device's
   exact stuck trans returned `blocked=#f` (CAN stand) at the divergent walls
   (-5417957, -5414453, -5216368), while the device stayed crouched. Control
   genuine overhangs (-5297236, -5371951) returned `blocked=#t` on BOTH, and the
   device's hitting triangle there is byte-identical to one of x86's.
3. **The misread is the #f return.** At the divergent walls the mips2c leaf
   `(method 9 collide-puss-work)` returned CLEAR (`hit=0`) on every probe and
   `(method 10 ...)` was never called — yet `probe-using-spheres`'s
   `(when v1-12 (return #t))` still fired. The raw leaf return was the host pointer
   `0x7f0014fd24` (= host `#f`), but GOALC read it as non-`#f`.

## Why host vs bare (the arm64 #f-guard class)
mips2c returns the GOAL symbol via its `s7` register, which on arm64 carries the
**host pointer** `g_ee_main_mem + offset`. GOALC-arm64 compiles symbol `#f` tests
as a **bare 32-bit GOAL-pointer** compare — the exact low-32 convention already
applied by the `gpr_addr` `beq reg, s7` `#f-guard` fixes that live in this same
`collide_cache.cpp`. `host #f` has `upper32 = 0x7f`; `bare #f` has `upper32 = 0`;
the 64-bit values are unequal, so a clear (`#f`) result reads as "not false". A HIT
(`#t = s7+8`) is non-`#f` under either representation, which is exactly why genuine
overhangs always behaved correctly and only the CLEAR case diverged. x86, whose
GOAL pointers fit a single 32-bit model, is unaffected.

## Why two earlier hypotheses were falsified (recorded so they aren't re-tried)
- **Re-tag the return to host** (the predecessor's `gpuss_canonical_symbol_return`):
  a no-op — the return was *already* host, AND on arm64 `_mips2c_call_arm64`
  (`game/kernel/asm_funcs_arm64.s`) IGNORES the C++ return value and hands GOALC the
  ExecutionContext **v0 slot** (`ldr x0,[sp,#32]`). Verified on device: zero change.
- **goalc-arm64 FMA-fusion of VU0 madd**: goalc-arm64 emits separate `fmul`+`fadd`
  (`IGenARM64.cpp` / `IR.cpp`), no fused-madd path exists — bit-consistent with x86.

## The fix (translation layer; goal_src 1-to-1)
`game/mips2c/jak1_functions/collide_cache.cpp`, in BOTH
`method_9_collide_puss_work::execute` and `method_10_collide_puss_work::execute`, at
`end_of_function` (arm64-only):

```cpp
#if defined(__aarch64__)
  c->gprs[v0].du64[0] = (u32)c->gprs[v0].du64[0];   // bare low-32 GOAL ptr
#endif
  return c->gprs[v0].du64[0];
```

Re-represents the ExecutionContext v0 slot — the value `_mips2c_call_arm64` returns
to GOALC — as the bare low-32 GOAL pointer GOALC's `(when v1-12)` compares against.
`#t` (s7+8) stays non-`#f`, so genuine collisions still block. The x86 path is
byte-for-byte untouched (the whole change is under `#if defined(__aarch64__)`), so
the x86 oracle and every other backend are unaffected. No goal_src edit; this is
the same low-32 `#f-guard` translation already used elsewhere in this file, applied
to the leaf RETURN side rather than the COMPARE side.

## Proof it works (device, fix active)
- `target-duck-stance` frames over the same warp+jump-into-walls drive: **2556 → 97
  (~96% reduction)**.
- The only remaining stable latch (tx=-5371951) is x86 `blocked=#t` — a **genuine
  overhang**, correct (matches x86).
- A wall that latched Jak WITHOUT the fix (-5216368, x86-clear) is now **passed
  through** WITH the fix (target-falling/jump, no latch).
- 0 sig=4/6/11 in the run; app stays foreground; normal gameplay states
  (jump/stance/walk/falling); no fall-through-the-world (collision intact).
- A bare-vs-host A/B build confirmed the BARE representation is the one that clears
  the stuck-crouch; host (idempotent) does not.
- `deploy_verify.sh eae4df44` PASS (device provably runs the fresh HEAD libgk).

So at every x86-CLEAR wall the device now stands up == x86, and at every
x86-BLOCKED overhang it stays crouched == x86. arm64 == x86.

## Instrumentation removed / cleanup
All temporary diagnostics were **removed** before this build — there are **no
leftover** debug hooks. The final source diff is ONLY the two-line arm64 fix in
`game/mips2c/jak1_functions/collide_cache.cpp`; the GWALL2 per-frame hook
(`kmachine.cpp`/`kboot.cpp`/`kboot.h`), the `get_button0_sources` accessor
(`android_input_audio.*`), and the `collide_cache.cpp` GWALL-PUSS/GWALL-HIT logging
+ prop-gated A/B scaffolding were all reverted via `git checkout`. `.autoport/gold`
is pristine. The x86 desktop smoke still reaches `link finish: logo` and the goldens
are unchanged.

## Owner gate
Owner eye/ear is the final gate: the navigation-gated visual confirm of the exact
ledge right of the Geyser steps. Reproduction is trivial (warp +
jump-into-the-walls), so the owner can verify directly.
