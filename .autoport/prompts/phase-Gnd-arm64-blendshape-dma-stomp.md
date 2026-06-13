# Phase Gnd — fix the arm64 blend-shape/joint OOB stomp that corrupts the DMA chain, so the ND/Daxter logo RENDERS

## Where we are (Gintro re-localized this precisely — build on it, don't re-derive)

Gintro (chronological step 1) proved the pre-title intro **executes** but the **ND/Daxter logo renders black**. Its 3-tier oracle diff (pristine x86 → our x86 → our Android) localized the cause with a smoking gun:

- During the `ndi-intro` frames (the ND logo geometry), the per-frame DMA **bucket-NEXT** pointer — which on x86/pristine is always a valid high heap pointer (e.g. `0xce7cc0`, `0xcca510`) — is **corrupted on Android to a LOW value `0x1a50`** (sometimes `0x2070`). The chain breaks there → the ndi geometry's DMA is dropped → black screen.
- **`0x1a50 == 0x501a50 & 0xffff`** — the low 16 bits of the **`*default-regs-buffer*` RET tag**. The bucket-NEXT store itself (dma-bucket.gc) is a clean 32-bit store with no truncation — so the corruption is an **OOB WRITE from elsewhere** stomping the bucket-NEXT word with low bits of a default-regs-buffer address.
- Gintro's root-cause call: an **arm64 blend-shape / joint-decompress OOB write** (the long-standing F1a/A37 "joint-decompress" blocker) — the ndi logo geometry uses blend-shapes/joints; the arm64 decompress writes past its bounds and clobbers the adjacent DMA bucket-NEXT. x86 is immune (zero-copy, different memory layout / correct bounds).
- Gintro's pacing/re-present fixes are landed (the ndi anim now plays at real-time, frame advances 5→60→120). The ONLY remaining blocker is this stomp.

The catch: `FixedChunkDmaCopier` (dma_copy.cpp:110-111) `ASSERT(addr > EE_MAIN_MEM_LOW_PROTECT=0x80000)` and the send_chain precopy walk are where `0x1a50` gets caught — use them as the **repro/tripwire** (they fire on the corrupt ndi frames).

## Mandate (in order)

1. **Catch the OOB write at its source.** The bucket-NEXT word holding the high pointer gets overwritten with `(low16 of a *default-regs-buffer* address)`. Find the arm64 code that writes out of bounds onto that memory: the blend-shape / joint-decompress path used by the ndi logo geometry (merc/blend-shape/`*default-regs-buffer*` usage). Techniques: a write-watch / guard page on the bucket-NEXT region, or instrument the blend-shape/joint decompress to bounds-check its destination, or oracle-diff the compiled blend-shape/joint-decompress arm64 vs x86 (the bug is almost certainly an arm64 codegen or asm OOB — wrong element count, stride, or a 128-bit store overrunning). The `0x501a50` default-regs-buffer signature points straight at the clobbering writer.
2. **Fix at the mechanism** (arm64 blend-shape/joint decompress bounds / codegen). goal_src is LOCKED (the .gc is pristine-correct — confirmed x86-identical by Gref). The defect is arm64 codegen (`goalc/...arm64...`, `IGenARM64.cpp`) or kernel/merc asm. No widening buffers to mask the overrun; fix the write to stay in bounds, matching x86 semantics.
3. **Verify the ND/Daxter logo RENDERS.** The bucket-NEXT must stay a valid high pointer through the ndi frames (no `0x1a50`/`0x2070`, no `FixedChunkDmaCopier` low-addr trip on ndi frames), the ndi window must draw real geometry (tris > 0), and device frames at the `ndi` window (t04-t08s per Gintro's spool-tagged captures) must VISIBLY show the Naughty Dog logo + Daxter — not black, not blue. Capture spool-tagged frames like Gintro did.
4. **Title-regression gate**: the title must still boot crash-free and fly (G1). Broad payoff expected — this stomp likely affects other joint-anim renders too; verify the title flythrough + (if reachable) the cinematic don't regress.
5. **`Gnd-fix-summary.md`** (≥80 lines): the OOB writer found (file:line), why it overruns on arm64 vs x86, the fix, the bucket-NEXT-stays-valid evidence, and the ND-logo-renders frame evidence.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**` (pristine-correct), `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/gold/**` (read-only reference), `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, other phase prompts. You MAY edit arm64 codegen (`goalc/...arm64`, `IGenARM64.cpp`), merc/blend-shape runtime, kernel asm. No buffer-widening masks, no hardcoded ND logo, no faking the render. x86 byte-identical; x86 boots to `link finish: logo`; qemu ≥ 675. `export ANDROID_SERIAL=eae4df44`; keyguard; reversible app disables + RE-ENABLE; pgrep leftover runs. The supervisor pixel-judges whether the ND logo + Daxter actually render.

## Validator (`phase-Gnd-arm64-blendshape-dma-stomp.sh`) — STRICT

PASS requires: a real **`Gnd-fix-summary.md`** (≥80 lines, must reference the bucket-NEXT/`0x1a50`/`0x501a50`/`*default-regs-buffer*` stomp AND the blend-shape/joint OOB writer it found) PLUS the newest `Gnd-routed-logcat-*.log` showing ZERO `sig=11`, the `ndi` markers present, **no `0x1a50`/low-addr DMA-corruption trip on the ndi frames** (a corruption-absence signal the fix produces), tris > 0, frame ≥ 300, PLUS newest `Gnd-focus-*.txt` ending on `org.opengoal.gk.jak1` PLUS ≥ 1 `Gnd-device-*.png`. Whether the ND logo + Daxter actually RENDER (vs black) is judged by the supervisor's own eyes on the ndi-window frames — a clean title alone does NOT pass.

## Max settings

`max_turns: 1500`, `max_retries: 3`.

## Strategic note

Gintro handed you the smoking gun: a low-address `0x1a50` (default-regs-buffer low bits) stomping the DMA bucket-NEXT during the ndi logo's blend-shape/joint decompress, with the x86 oracle proving it's arm64 corruption. Find the overrunning writer, bound it to match x86, and the ND/Daxter logo lights up — and very likely a whole class of joint-anim renders with it (the F1a/A37 blocker, finally). Then Gtitle (title polish) is next.
