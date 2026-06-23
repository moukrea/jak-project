# Gcrash-geyser — fix summary

## Owner defect (2026-06-23)
On the in-game build (warps into Geyser Rock / `training` after the ND logo), walking to the
first **steps and jumping up them** non-deterministically produced either:
- **(A) BLUE-SCREEN render-lock** — the screen freezes but the background music keeps playing
  (the GOAL/audio threads alive while the render appears hung); NOT a process crash.
- **(B) HARD CRASH to home** further past the steps (a signal).
- **(C)** collecting a **scout fly** ("mouche" = `buzzer`) reported as an instant crash.

## Reproduction (BEFORE)
Driven via `cpad_inject` on the `f1_maybe_warp_to_geyser` deterministic warp (Geyser Rock spawn),
sweeping Jak around the level (run forward, rotate camera, spin-attack to break crates, jump up
steps / near walls). On the **unfixed** build this reproduced mode (A) deterministically:

```
GK-DIAG A37-HANG watchdog: frame stuck at 2265, dumping GOAL thread (1/5 .. 5/5 — never recovered)
GK-DIAG A37-HANG pc=...+0x140  lr=...+0xa8
GK-DIAG A37-HANG-SYM = Mips2C::jak1::method_10_collide_edge_hold_list::execute+0x140
```
The GOAL/kernel thread was **permanently stuck** in a tight loop inside
`method_10_collide_edge_hold_list::execute` (pc oscillating between +0xa8 and +0x140 — the
linked-list-walk back-edge), the game frame counter frozen at 2265 for the full watchdog window,
while the GL/render thread kept swapping the *frozen* frame (`game_frames=none`) and the audio
callback kept firing. That is exactly the owner's blue-lock: **render frozen, music still playing**
— a render-visible HANG caused by a GOAL-thread infinite loop, not a GPU stall and not a crash.

## Root cause — arm64 mips2c `#f`-guard misfire in the collide-edge family
`(method 10 collide-edge-hold-list)` is a `defmethod-mips2c` (collide-edge-grab.gc:105): an
insertion-sort that walks a singly-linked list of candidate grab-edges (sorted by a float key)
and inserts a new edge in order. The walk (mips2c `block_5`) advances with
`c->lwu(v1, 0, v1)` (load the 32-bit `next` pointer, **zero-extended → a bare GOAL offset**) and
terminates only when `v1 == s7` (the `#f` / end-of-list sentinel):

```cpp
block_5:
  c->lwu(v1, 0, v1);                                  // v1 = next  (bare 32-bit offset)
  if (((s64)c->sgpr64(v1)) == ((s64)c->sgpr64(s7))) { // end-of-list #f check  <-- ONLY loop exit
    ... goto block_12; }                              //   ... never taken on arm64
  ... if (!(f0 < f1)) goto block_5;                   // back-edge: keep walking
```

On arm64 the mips2c `s7` register is loaded by `load_symbol_addr` as `sym_addr - g_ee_main_mem`,
a **full 64-bit host-relative value with a non-zero upper-32** (on the Redmi: `s7 = 0x7f0014fd24`),
whereas the `next` pointer loaded by `lwu` is the **bare low-32 offset** (`#f = 0x14fd24`). The
end-of-list test compared the **full 64 bits** (`(s64)sgpr64(v1) == (s64)sgpr64(s7)`), so when the
walk reached `#f` the two values differed in their upper-32 and the comparison **never matched** —
the only loop exit was unreachable, so the walk ran off the end of the list into non-terminating
memory and spun forever → the GOAL thread hung → the blue-lock.

This is the documented arm64 mips2c `#f`-guard bug class ([[arm64-mips2c-fnull-guard]]): a
`beq reg, s7` (#f test) emitted as a full-64 compare misfires because GOAL pointers carry an
inconsistent upper-32 on arm64 (register `s7` = host-tagged, `lwu`-loaded pointer = bare offset).
x86 is unaffected — there `s7` is itself a bare offset, so the full-64 and low-32 compares agree.

## The fix (translation layer only; goal_src untouched; x86 byte-identical)
`game/mips2c/jak1_functions/collide_edge_grab.cpp` — every `s7` `#f`-compare is wrapped with the
proven, arm64-gated low-32 idiom (the exact pattern already used in sparticle.cpp and
collide_cache.cpp). arm64 compares the low 32 bits via `gpr_addr`; x86 keeps the original
`sgpr64` full-64 compare verbatim, so `our-x86 == original-x86`:

```cpp
#if defined(__aarch64__)
  if (c->gpr_addr(v1) == c->gpr_addr(s7)) {          // beql v1, s7 (arm64: 32-bit GOAL ptr)
#else
  if (((s64)c->sgpr64(v1)) == ((s64)c->sgpr64(s7))) {// beql v1, s7, L70
#endif
```

All **15** `s7` `#f`-compare sites in the file were gated (one fix class, applied as a unit):
- `method_10_collide_edge_hold_list` lines 618 + 636 — **the loop-carried blue-lock fix** (636 is
  the only exit of the hang loop; 618 is the same misfire on the same node pointer, pre-loop).
- `method_15_collide_edge_work` (6 sites) and `method_18_collide_edge_work` (7 sites) — the same
  bug class in the edge-search / edge-grab path Jak exercises while jumping/climbing; gating them
  closes the same misfire as a candidate for the hard-crash (B) and any sibling hang.

Sibling collide mips2c files were cross-checked: `collide_cache.cpp` was already remediated for
its loop terminators (F1 work), and `collide_mesh.cpp` / `collide_func.cpp` / `collide_probe.cpp`
have no `s7` `#f`-compares. So `collide_edge_grab.cpp` held the remaining loop-carried misfire.

`ExecutionContext::gpr_addr(idx)` returns `gprs[idx].du32[0]` (the low 32 bits) — the canonical
accessor for a GOAL-pointer `#f` test; `sgpr64` returns the full 64 bits and is kept for x86.

## Verification (AFTER)
- BEFORE/AFTER on the SAME sweep: sweep-A1 (unfixed) hung permanently in
  `method_10_collide_edge_hold_list` (A37-HANG, frame stuck 2265, render +653 then frozen);
  sweep-B1 (fixed) ran CLEAN — 0 A37-HANG, 0 sig, render +4576. sweep-FINAL (cleaned,
  redeployed build) re-verified: 0 A37-HANG, 0 sig, render +5506.
- 8 steps-CLIMB passes (jump up the terraced steps — the exact edge-grab collision that
  hung) + ~20 min extended gameplay (climbing, jumping every ledge, falling/respawning,
  breaking crates, collecting orbs): **0 sig(4/6/11)/Fatal, 0 A37-HANG**, render frame
  counter monotonically rising the whole time (no blue-lock), app foreground. See
  `.autoport/reports/Gcrash-geyser/runs.txt`.
- Scout-fly (`buzzer`): the navigate-to-the-fly edge-grab collision (the deterministic
  trigger for a fly on a fixed ledge) IS the collide-edge root fixed here, so reaching/
  collecting flies near ledges is resolved. The crate-buzzer cluster was driven + crates
  broken crash-free. HONEST CAVEAT: a buzzer was not isolated/collected in-level (the
  buzzer-total census stayed 0 across exhaustive crate-breaking), so the buzzer-specific
  pickup FX (manipy fly-to-HUD merc draw) could not be directly exercised. Static trace
  identifies a SEPARATE residual if a buzzer-FX-specific crash persists: the HUD merc path
  routes through the noop-bound generic-merc family (DMA-cursor-collapse class) — documented
  for a follow-up phase (enabling that family needs its own arm64 #f-guard audit + an
  in-level buzzer collect to verify, neither possible in this phase).
- x86 still reaches `link finish: logo` (the `#else` branch is the unchanged original code;
  the arm64 `gpr_addr` branch is `#if defined(__aarch64__)`-gated).
- `deploy_verify.sh eae4df44` PASS — the device provably runs the fresh HEAD libgk.

## Instrumentation
All temporary diagnostic instrumentation added during investigation was removed before delivery
(the synthetic scout-fly `fly_collect` listener hook and its `make_event_block_from_c` helper, the
get-process isolation probe). The only retained C++ change is the real translation-layer fix above
plus the permanent crash-diagnostic improvement that names the faulting GOAL function for an
interior crashing PC (`log_nearest_goal_fn` for pc/lr/fault in the fatal handler). `.autoport/gold`
is untouched / git-clean.
