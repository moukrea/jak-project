# Gcine-crash3 — fix summary (the RESIDUAL Gol/Maia-scene cinematic crash)

## 1. The bug (owner symptom + objective repro)
After Gcine-crash2 (target-racer-h / wheel) and Gcine-pose (NaN bone matrices,
60ba2f477), the NEW GAME intro cinematic plays FURTHER but **still crashes** a few
beats into the **Gol/Maia pinkish-halo portal villain scene**, kicking the app back
to the Android launcher (com.miui.home) — a native crash. Plays correctly on x86 ⇒
arm64-specific.

This phase closed the truncated-log blind spot that false-passed the prior two:
their runs stopped at ~frame 9420-9960 (`GAMEPLAY: enter misty`). A LONG capture
(break at frame ≥ 11200, foreground recorded at end) was run on the pose-fixed HEAD.

**Repro (run 1, deterministic):** highest frame **10020**, then
`GK-DIAG sig=4 fault=0x7f00191278 pc=0x7f00191278 lr=0x7f00191154`, process 17143
died (`Zygote: Process 17143 exited due to signal 4 (Illegal instruction)`),
`mCurrentFocus` dropped to `com.miui.home/...Launcher` (the owner's exact symptom).
Harness: `.autoport/Gcine3_run.sh` (cpad_inject NEW GAME nav, long watch loop,
records `Gcine3/foreground-at-end.txt`). Repro log: `Gcine3/crash-logcat.log`.

## 2. The Gol/Maia portal scene
The portal beat is `sequenceB` in `goal_src/jak1/levels/misty/sidekick-human.gc`:
- `evilbro` = **Gol**, `evilsis` = **Maia** (`levels/intro/evilbro.gc`), spawned via
  `manipy-spawn` (sidekick-human.gc:1323/1339) and sent `'blend-shape #t` +
  `'anim-mode 'clone-anim` + `'center-joint 3` — the merc blend-shape/joint path.
- These live in INT.DGO; the scene mass-spawns AND mass-kills the misty `lurker-army`
  (`babak`/`bonelurker`, all merc-skinned) right at `enter misty` (frame ~9960+).
- They draw through the **`l0-pris-merc` (prismatic/envmap merc) bucket id=49** —
  the exact lead flagged in Gcine-crash2.

The forensic GK-DIAG immediately before the fault:
```
GK-DIAG F1A-BUCKET in-render=l0-pris-merc id=49
GK-DIAG F1A-MERC-DRAW di=10/11 tex=0x17e first_bone=2240 idx=509+32534 ... envmap=1 ...
GK-DIAG sig=4 fault=0x7f00191278 pc=0x7f00191278 lr=0x7f00191154
```

## 3. Forensics — the crashing function is `process::deactivate`
The byte-matcher (`/tmp/a34_match_frames.py`) placed the fault code in
KERNEL.CGO object `gkernel`. cgo_inspect + a disasm of the arm64 vs x86 KERNEL.CGO
(autoport-researcher) identified it as **`deactivate` (method 10 of `process`),
gkernel.gc:1903**. The fault is the `b.ne 0x7f78` at the cond tail (gkernel.gc:1946,
the **normal** "process killed by another" path) branching to GOAL **0x191278** and
executing a non-instruction → SIGILL. The crashing process is the **`display`**
process (A40-DPROC `name=display`) running the portal-scene frame.

The built-in A18 diag decoded the area as a `dead-pool-heap` (type 0x189144)
method-15 (`return-process`) virtual dispatch at gkernel.gc:1940
`(return-process (-> this pool) this)` — i.e. the scene's mass-kill is deactivating
processes when the crash lands a few instructions later in the same function.

## 4. ROOT CAUSE — a runtime stomp of deactivate's CODE (not a bad dispatch)
Decisive comparison: the device's APK `KERNEL.CGO` is **byte-identical** to
`out/jak1-arm64/iso/KERNEL.CGO` (sha 63d7707c…). On disk, GOAL 0x191260-0x1912a4 is
deactivate's valid arm64 instructions (ldp restores, the `b.ne` branches, the final
`ret`). **On the device at crash time those same addresses hold host/native
pointers + floats**, e.g.:
```
0x191260: 0x7f001912c0  0x7f004d0d94      ; GOAL host code pointers
0x191270: 0x42888889(68.266f)  0x0
0x191278: 0x6f6618bc0c                    ; a NATIVE (libgk.so/C++) pointer  <-- crash pc
0x191280: 0x5149c4  0x7f004d0b84  ...  0xc5800000(-4096f)
```
A CGO cannot contain a runtime native pointer, so deactivate's code was overwritten
**at runtime** (~0x40 bytes at GOAL 0x191260). The `b.ne 0x7f78` then executed
`0x6618bc0c` (the low half of native ptr 0x6f6618bc0c) → SIGILL.

**Why it's the normal deactivate path, and only the portal scene crashes:** the
`b.ne 0x7f78` is taken on EVERY ordinary process deactivation (neither the running
process nor an init-time kill). The title + village flythrough deactivate processes
constantly without crashing, so the bytes are **clean** through the whole title —
the corruption appears at runtime, during the Gol/Maia portal beat, then the next
ordinary deactivation (the mass-kill) trips it. Hence the long-window blind spot.

**Why the A38 mprotect tripwire is blind to it (oracle-diff vs the CPU-store class):**
the A38 tripwire (proven on Gnewgame's mips2c #f-guard stomp) watched
host band [0x190000,0x194000) with `emulate-via-/proc/self/mem` (no unprotect) and
caught **3395** writes — but **every one** targeted a legitimate kernel global at
GOAL **0x1912b4** (base x16=0x7f001912b4, written by `search-process-tree`,
`change-to-last-brother`, `auto-save`, …), deactivate's *trailing data*. It caught
**zero** writes to the crash region 0x191260-0x191280. Since A38 sees every normal
CPU/mips2c store, the deactivate-code write is **not a CPU store** — it is a
DMA/SIMD-class write from the **arm64 envmap merc render path** (l0-pris-merc,
`blend-shape` villains) with a miscalculated destination base that aliases into the
GOAL code region. This is the recurring merc/blend-shape arm64 class
(Gnd "blendshape DMA stomp", Gcine-pose merc NaN), now corrupting kernel code.

**Oracle-diff vs x86:** the autoport-researcher disassembled `deactivate` in both
`out/jak1-arm64/iso/KERNEL.CGO` and `out/jak1/iso/KERNEL.CGO`. The dispatch chain is
structurally identical (pool=[this+28], type=[pool-4], method=[type+76]; arm64 keeps
`this` correctly in x5 with `stp/ldp x3,x5` save/restore brackets across every BLR —
verified intact at fault: x5=0x21b524 = the correct `this`). So arm64 **codegen of
deactivate is correct**; x86 simply never suffers the render-path stomp, so it never
executes corrupted bytes. The defect is the arm64 render-path write target, the
victim is shared kernel code.

## 5. The fix (libgk.so, always-on, arm64 — Gcine-pose precedent)
KERNEL.CGO is a boot CGO that cannot be standalone-rebuilt/pushed on this device
([[feedback_game_cgo_rebuild_unsafe]]), and the writer is a DMA/SIMD store in the
render path (invisible to the mprotect tripwire, so the exact C++ store is not
single-line-pinned). Exactly as Gcine-pose repaired NaN bone matrices at the
mips2c boundary rather than rebuilding ENGINE.CGO, this fix is an **always-on
content canary + repair** in `android/android_gfx.cpp`, right after the per-frame
`renderer->render(...)` (which processes the DMA chain that contains the stomping
l0-pris-merc draw) and before the GOAL thread runs the next frame's deactivations:

- On the first rendered frame, snapshot deactivate's known-good code bytes
  [GOAL 0x191240, 0x1912b4) — clean for the whole title — guarded by a signature
  check (the call-trampoline `stp x3,x5` == 0xa9bf17e3 at 0x191250) so a future
  KERNEL.CGO relayout cannot silently repair the wrong bytes. The region ends at
  0x1912b4 so the legitimate adjacent kernel global is never touched.
- Each subsequent frame, if those bytes changed, log it once
  (`GCINE3-DEACT-STOMP frame=… first=… was=… now=…`) and **restore** the snapshot,
  then `__builtin___clear_cache` the range so the corrected instructions are
  re-fetched. x86 is unaffected (`#ifdef __aarch64__`).

After the repair, every ordinary process deactivation executes deactivate's correct
code, so the SIGILL cannot occur. This treats the kernel-code corruption robustly
without rebuilding any boot CGO; the residual (the render-path write itself,
harmlessly landing on code we restore each frame) is a separate merc/DMA-base phase.

## 6. Verification
- Clean rebuild: `cmake --build build-android --target gk` recompiled
  `android_gfx.cpp` and relinked libgk.so; APK repackaged; `deploy_verify.sh
  eae4df44` PASS (build==APK==device chain bf3bfab919dbefed, `GCINE3-DEACT-STOMP`
  present in the .so).
- Long NEW-GAME run on the fixed HEAD (`Gcine3_run.sh` run 3, break frame 11200):
  highest frame **11580** (well past enter-misty 9960 and the 10500 gate), **0**
  sig 11/6/4 across the whole routed logcat, `foreground-at-end.txt` =
  `org.opengoal.gk.jak1/...MainActivity` with the app pid still alive (NOT
  com.miui.home).
- The canary fired exactly once and proved the root cause to the byte:
  ```
  GCINE3-DEACT-STOMP frame=10078 first=goal:0x191260 was=0xa8c15fec now=0x001912c0
  ```
  `was=0xa8c15fec` is deactivate's real instruction `ldp x12,x23,[sp],#16` (matches
  out/jak1-arm64/iso/KERNEL.CGO); `now=0x001912c0` is the low half of the stomp
  pointer 0x7f001912c0 (matches the run-1 crash PCWIN). The render-path write
  occurred at frame 10078 (the Gol/Maia portal beat, same place run 1 SIGILL'd at
  10020) and was repaired before any deactivation tripped it.
- Validator `phase-Gcine-crash3.sh` exits 0: no forbidden edits / grind / disk;
  forensics+scene+determination; x86 `link finish: logo`; deploy verified; long
  run clean (frame=11580, 0 crash sigs, app foreground at end).
- Regression: title/intro remain crash-free (the canary is inert until the
  portal-scene stomp at ~frame 10078).
- Owner eye-confirms the full play-through to gameplay.
