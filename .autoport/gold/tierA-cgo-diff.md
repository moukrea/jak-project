# Tier-A diff — PRISTINE upstream x86 gold standard vs OUR x86 build

**Tier A** compares the *pristine* CGOs/DGOs (built from the unmodified upstream
merge-base `704972dd6`) against *our* x86 CGOs/DGOs (`out/jak1/iso/`). Because
`goal_src` is **byte-identical across our entire fork** (`git diff 704972dd6 HEAD
-- goal_src/` = 0 files), the only variable between these two builds is the
**compiler (goalc) itself**. Therefore any Tier-A byte-difference would be a
*pure compiler signal* — proof that one of our 46 goalc commits leaked into the
x86 codegen (a bug that would live in BOTH our x86 and our Android output,
invisible to a 2-way diff). Identical bytes prove the opposite: the arm64 work
is fully gated and never touches x86 output.

## Method
- Gold artifacts: `.autoport/gold/cgo/*.CGO`, `.autoport/gold/dgo/*.DGO`,
  produced by the pristine `goalc` (commit 704972dd6) via
  `make-group "iso"` in the worktree `/home/emeric/code/gold-jak-project`.
- Our artifacts: `out/jak1/iso/*.CGO` / `*.DGO` (mtimes 2026-06-13 13:48,
  unchanged by this phase — verified before/after the gold build).
- Comparison: `cmp -s` (byte-exact) + `md5sum` cross-check, per object, all 28.

## VERDICT

> **Our x86 codegen is PRISTINE-IDENTICAL.** All 28 game objects (3 CGOs +
> 25 DGOs) are byte-for-byte identical to the pristine upstream `704972dd6`
> build (matching size AND md5). **0 objects diverge.** The 46 goalc commits
> that add the arm64 backend are confirmed **100 % arm64-gated** — they leak
> nothing into the x86 backend. Our x86 build is therefore a trustworthy
> intermediate reference, and any Android (arm64) divergence observed in later
> phases is attributable to the arm64 backend / runtime (Tier B), **not** to a
> hidden corruption shared by x86 and Android.

## Per-object results (Tier A: gold vs our-x86)

| object | type | gold bytes | our-x86 bytes | md5 match | verdict |
|--------|------|-----------:|--------------:|:---------:|---------|
| KERNEL.CGO | CGO | 92160 | 92160 | yes | IDENTICAL |
| ENGINE.CGO | CGO | 5321488 | 5321488 | yes | IDENTICAL |
| GAME.CGO | CGO | 8758112 | 8758112 | yes | IDENTICAL |
| BEA.DGO | DGO | 10672096 | 10672096 | yes | IDENTICAL |
| CIT.DGO | DGO | 10659536 | 10659536 | yes | IDENTICAL |
| DAR.DGO | DGO | 6677008 | 6677008 | yes | IDENTICAL |
| DEM.DGO | DGO | 5592032 | 5592032 | yes | IDENTICAL |
| FIC.DGO | DGO | 7809808 | 7809808 | yes | IDENTICAL |
| FIN.DGO | DGO | 9384896 | 9384896 | yes | IDENTICAL |
| INT.DGO | DGO | 1653440 | 1653440 | yes | IDENTICAL |
| JUB.DGO | DGO | 4242208 | 4242208 | yes | IDENTICAL |
| JUN.DGO | DGO | 10404112 | 10404112 | yes | IDENTICAL |
| LAV.DGO | DGO | 11329344 | 11329344 | yes | IDENTICAL |
| MAI.DGO | DGO | 10455712 | 10455712 | yes | IDENTICAL |
| MIS.DGO | DGO | 11494912 | 11494912 | yes | IDENTICAL |
| OGR.DGO | DGO | 11089312 | 11089312 | yes | IDENTICAL |
| ROB.DGO | DGO | 10523536 | 10523536 | yes | IDENTICAL |
| ROL.DGO | DGO | 11430496 | 11430496 | yes | IDENTICAL |
| SNO.DGO | DGO | 11353568 | 11353568 | yes | IDENTICAL |
| SUB.DGO | DGO | 4812512 | 4812512 | yes | IDENTICAL |
| SUN.DGO | DGO | 10267744 | 10267744 | yes | IDENTICAL |
| SWA.DGO | DGO | 9556864 | 9556864 | yes | IDENTICAL |
| TIT.DGO | DGO | 1346880 | 1346880 | yes | IDENTICAL |
| TRA.DGO | DGO | 6785552 | 6785552 | yes | IDENTICAL |
| TSZ.DGO | DGO | 2013152 | 2013152 | yes | IDENTICAL |
| VI1.DGO | DGO | 11445808 | 11445808 | yes | IDENTICAL |
| VI2.DGO | DGO | 10989712 | 10989712 | yes | IDENTICAL |
| VI3.DGO | DGO | 10984112 | 10984112 | yes | IDENTICAL |

**Totals: 28 IDENTICAL, 0 DIVERGENT.**

## Why this is the expected (and desired) result
- `goal_src` unchanged across the fork → identical GOAL input.
- The arm64 work lives in a *separate, gated* backend path (`goalc/emitter/
  IGenARM64.*`, `IGen_arm64.*`, the `GOALC_BACKEND=arm64` selection, arm64
  branches in `CodeGenerator.cpp`/`ObjectGenerator.cpp`/`Allocator_v2.cpp`).
  On an x86 build none of those paths execute, so x86 output is unchanged.
- The single `common/` change (`dma_chain_read.h`: a `base()` accessor) is
  consumed only by the *runtime* (renderer/DMA), never by goalc codegen, so it
  cannot perturb object bytes — consistent with the 28/28 identical result.
- The decompiler delta (2 files / 18 lines) did not alter any jak1 extracted
  asset bytes either: the DGOs (which embed art/level data) are also identical.

## Contrast: Tier B (our-x86 vs our-arm64) — for reference, NOT part of this verdict
Tier B is *expected* to diverge (arm64 instructions are wider than x86). Spot
check via the harness, e.g. `KERNEL.CGO`:
- our-x86: 92160 bytes, 8 objects, 197 functions, 260 x86 RET opcodes, 0 arm64 RET.
- our-arm64: 159632 bytes, 8 objects, 197 functions, 233 arm64 RET, 6 x86 RET.
Same object/function counts, different instruction encodings — the legitimate
arm64 porting surface. Use `.autoport/gold/compare-3tier.sh <OBJECT>` to inspect
any object across all three tiers.

## Reproduce
```
.autoport/gold/compare-3tier.sh --cgo     # Tier-A + Tier-B for the 3 CGOs
for o in $(ls .autoport/gold/dgo); do .autoport/gold/compare-3tier.sh "$o"; done
```
