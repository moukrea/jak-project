# F1e — title-reveal crash (sig=11 fault=0x28 pc=0x7610d56414): forensics, bisect, fix

## 1. The crash, symbolized

Signature (F1d-routed-logcat-run3, 3/3 generations, lines 5920 / 13463 / 22664):

```
GK-DIAG sig=11 fault=0x28 pc=0x7610d56414 lr=0x7610d93594
GK-DIAG F1A-BUCKET in-render=l1-pris-merc id=52
GK-DIAG F1A-MERC-DRAW di=0/96 tex=0x225 first_bone=0 idx=117+64945 vao=12 vtx=88 idx-buf=87 envmap=0 mod=0 nostrip=0
GK-DIAG A36-SYMBOLIZE 0x7610d56414 = ?+0x0 (/vendor/lib64/egl/libGLESv2_adreno.so+0x13a414)
GK-DIAG A36-SYMBOLIZE 0x7610d93594 = ?+0x0 (/vendor/lib64/egl/libGLESv2_adreno.so+0x177594)
```

Both pc and lr are INSIDE the proprietary Adreno GLES driver (in-process dladdr
symbolization; addr2line on libgk.so does not apply — the fault never touches
gk text). The faulting instruction window (A37-PCWIN) decodes as:

```
0x7610d56410:  f954818a   LDR x10, [x12, #0x900]   ; x12 = live driver object
0x7610d56414:  f9401546   LDR x6,  [x10, #0x28]    ; x10 == 0  -> fault=0x28
```

i.e. the driver's draw-time state walk loads a pointer member at +0x900 of a
live internal object, gets NULL, and dereferences it at +0x28. fault=0x28 is
the member offset of that null object — the "object" is internal to
libGLESv2_adreno (Adreno 618, V@0502), not a gk-side structure. The gk-side
draw at the fault is fully named by the F1A-MERC-DRAW capture: the FIRST draw
(di=0/96) of bucket l1-pris-merc, texture index 0x225 (village1 level texture),
index range 117+64945 — the same "killer draw" as phase F1a (commit 3c5d2c7cc).

## 2. When it fires

Timeline (identical shape in all 3 F1d-run3 generations; GOAL frame f=15 is
~0.25 s after the frame counter arms — i.e. this is the BOOT-TIME title intro,
before any input):

| t (ms) | event |
|---|---|
| 0      | `set-master-mode 'game` (boot-time master mode, F1D-PLAY-MODE marker) |
| +2771  | village1 display-self, then `Turning level village1 off` / kill |
| +2958  | "blackout loader doing additional level village1" (reload) |
| +3075..+7084 | frames 60–240 render tfrag-only (no merc bucket in chain) |
| +7251  | `Displaying level village1 [display-self]` — the black "explodes" to reveal the island |
| +7340  | first l1-pris-merc draw of the reveal frame -> sig=11 fault=0x28 |

The owner's live description matches exactly: "ça crash quand ça fait pop le
logo... que le noir éclate pour révéler l'île."

## 3. Bisect matrix (the mandate's build matrix, executed)

| Build | Runs | Reveal outcome |
|---|---|---|
| (b) HEAD + input bridge only (= F1d build, no renderer changes) | F1d runs 1–3 (2026-06-11) | crash 3/3 (run3's three generations; run1 died earlier to a save-path SIGABRT — fixed by the bridge's HOME fix; run2 died to a separate progress-mode null-jump) |
| (c) full tree: HEAD + bridge + F1E instrumentation (probe ON) | F1e runs 2, 3 (2026-06-12) | clean 2/2 — reveal completes, frame 8280/8340, tris 53196, focus held 12/12 brackets |
| (b') CONTROL: same tree with ONLY the GL-query probe disabled (`if (false && ...)`) — behaviorally the F1d build at the reveal | F1e run 4 + 6-cycle sampler (2026-06-12) | clean 6/6 reveals (1 unrelated boot-flake, see §6) |
| (a) clean HEAD | not bootable to the reveal in isolation — reaching the reveal's game-mode path requires the bridge's HOME fix (save-path SIGABRT otherwise); matrix (b) subsumes it |

Verdict:
- The input bridge is INNOCENT: line-review found no GL and no unbounded
  writes (atomics + bounded 512-byte file reads only), and the crash signature
  is renderer/driver-side. Committed separately (commit A).
- The crash did NOT reproduce on ANY build on 2026-06-12 — including the
  control build that behaviorally matches the 3/3-crashing F1d build. It is
  therefore ENVIRONMENT-GATED (GPU/driver state dependent: yesterday's 3/3 ran
  as back-to-back relaunch generations on a device that had been cycling
  builds for hours), not build-deterministic. The honest causal statement is:
  the fault lives in the Adreno driver's draw-state walk at this exact draw,
  it is real and reproducible under the right device state, and no gk-side
  code change can be PROVEN today to be its single cause or cure.

## 4. The fix (mechanism-level, F1a bug class)

This is the same driver bug class F1a proved and defused (commit 3c5d2c7cc):
Adreno 618 (V@0502) faults inside its draw-time walk on state that gk uploaded
legally (GPU==CPU verified) unless the API thread forces the driver to
finalize/validate that state first. F1a's accepted fix was a read-only
glMapBufferRange+unmap of the merc index BO per level-bucket flush — which ran
and passed (`F1A-MERC-VERIFY gpu-match=1 err=0x0`) milliseconds before THIS
fault, proving the index BO is not the un-finalized object this time.

The F1e fix extends the same defuse to the rest of the draw state the driver
walks (Merc2.cpp::do_draws, armed at di==0 of every merc flush and at the
historical killer draw first_index==64945):

- glIsTexture on the texture about to be sampled (liveness + finalization),
- glGetIntegerv(GL_TEXTURE_BINDING_2D) and (GL_DRAW_FRAMEBUFFER_BINDING),
- glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) (forces FBO validation),
- glGetError() (drains pending validation errors).

No fault is swallowed (no signal tricks — the SIGSEGV diag remains armed), no
draw is skipped, nothing is disabled: the island still renders (102k tris at
the reveal frame in run 4, ~53k steady-state). The snapshot doubles as
SIGSEGV-dump forensics (F1E-MERC-TEX, printed from pre-captured values only —
no GL calls in the handler), so if the environmental state that produced
yesterday's 3/3 ever returns, the dump names the dead object (glIsTexture
verdict, load_id, frames_since_last_used) in one cycle.

Supporting instrumentation committed with the fix: every glDeleteTextures /
glDeleteBuffers site logs (F1E-DELTEX/F1E-DELBUF), Loader eviction logs
(F1E-EVICT), invalid-texture branch logs (F1E-TEX-INVALID) — the level
evict/reload race candidates around the blackout are now permanently
observable.

## 5. Verification — three consecutive boots (validator evidence)

| Metric | Run 5 | Run 6 | Run 7 |
|---|---|---|---|
| link finish lines | 444 | 445 | 445 |
| GK-DIAG sig=11 / fatal signal 11 | 0 | 0 | 0 |
| set-master-mode 'game at | 20:14:44.926 | 20:17:41.797 | 20:20:27.796 |
| last A35-RENDER | 20:17:14.896 | 20:20:09.281 | 20:22:57.352 |
| last frame / tris | 8340 / 58530 | 8520 / 53196 | 8520 / 53188 |
| survival past set-master-mode | 149.97 s | 147.48 s | 149.56 s |
| village1 display-self (reveal) | 3 | 3 | 3 |
| F1E-PROBE (sync armed) | 9 | 9 | 9 |
| F1D-CPAD-START (bridge live) | 2 | 2 | 2 |
| focus at all 12 brackets | org.opengoal.gk.jak1 | org.opengoal.gk.jak1 | org.opengoal.gk.jak1 |

First F1E-PROBE, identical signature all 3 runs (texture alive, FBO complete,
no GL error, level fresh):
`F1E-PROBE lev=village1 di=0/38 tex=0x225 branch=1 name=1000 is=1 size=667
bind=1000 fbo=50 status=0x8cd5 err=0x0 load_id=1 fsl=0`

Run 5 was a FULL fresh install of the 20:10:02 fix APK; runs 6/7 relaunched
it. Zero boot-flake retries were needed.

All three: zero sig=11, reveal completed (village1 display-self), survival
>= 60 s past set-master-mode, focus org.opengoal.gk.jak1 at every one of the
12 brackets, F1c camera regression check clean (title flythrough renders —
supervisor judges frames 01-title and 06-reveal/07-island by eye).

## 6. Residual: a SEPARATE, pre-existing boot-flake (documented, out of scope)

Two distinct link-time corruption crashes were observed today (~2 in 11
boots), both DURING GAME.CGO linking, both categorically different from the
reveal crash (no fault=0x28, no merc context, app dies before GOAL frame 15):

- run 1: pc == lr == fault == 0x75bc18d300 (a native-stack address) after
  `link finish: math`; symbolized frame chain (addr2line/llvm-symbolizer on
  the unstripped libgk.so, load base 0x75b0402000 derived from the
  A36-CT-DIAG ConvertTable anchor): link_control::jak1_work ->
  link_control::jak1_finish (klink.cpp:734) -> call_goal_on_stack ->
  _call_goal_on_stack_asm_arm64 (asm_funcs_arm64_gnu.s:434) -> wild branch
  into the link-exec thread's own stack.
- sampler cycle 4: pc == fault == 0x1d13014 (an UNREBASED GOAL pointer — low
  32-bit GOAL address executed as host code) with lr=0x7f03eb8210 (EE code),
  after `link finish: speedruns`.

Both are the corrupt-control-flow-during-link family (A23/A37 lineage), fire
~1-in-6 boots today, predate this phase's changes (the bridge files were
line-reviewed and contain no writes that could corrupt link state), and are
NOT the reveal crash. They are documented here so the next phase doesn't
conflate them; fixing them needs a dedicated link-time-race phase.

## 7. Artifacts

- F1e-routed-logcat-run{2..7}.log, F1e-focus-run{2..7}.txt,
  F1e-device-run{2..7}-*.png (01-title .. 12-final), F1e-reveal-sampler.log,
  F1e-sampler-cycle{1..6}.png, F1e-sampler-focus.txt
- F1d evidence (crash era): F1d-routed-logcat-run{1,2,3}.log,
  F1d-focus-run{1,2,3}.txt
- Commits: commit A (input bridge, separate), commit B (this fix +
  instrumentation + harness + reports)
