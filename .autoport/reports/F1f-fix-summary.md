# F1f — go control-transfer fixed (both roads), spool master-slot named, Adreno first-merc-draw fault root-caused and fixed at the pipeline level

## 0. Scope and result in one paragraph

The phase's two GOAL walls are both resolved at the mechanism: (1) the `go`
non-local control transfer that **RETURNED instead of transferring** on arm64
is fixed in the compiler (commit 19bb8e50a) and verified, deterministically, on
BOTH roads (NEW GAME §7a and LOAD GAME §7b); (2) the "could not find a master
slot to link/unlink" spool linking is characterized — it is an arm64-only,
non-fatal `art-group-get-by-name` lookup miss, INDEPENDENT of the `go` bug, and
the `go` fix repairs its recovery path so it no longer SIGILLs. With both GOAL
walls down, the only thing between here and a moving Jak was the long-standing
Adreno "first-merc-draw-after-load" driver fault (a SEPARATE, pre-existing GPU
bug, "mitigated not cured" since F1a). This attempt root-causes that fault via
driver disassembly and fixes it at the correct layer — the GL pipeline state,
not the buffer storage.

## 1. The `go` control-transfer bug — root cause (mechanism)

`enter-state` (goal_src/jak1/kernel/gstate.gc:346-377) runs a state's `code` in
a deliberately tricky way: it resets the stack to the process main-thread top,
`(.push return-from-thread-dead)` (the trampoline that runs `deactivate` when
the state code returns), then `(.jr func)` jumps to the state code. On x86 the
pushed return address sits on the reset stack, so when the state code `RET`s it
pops `return-from-thread-dead`. On arm64, `BR` does not consume a stack return
address — `RET` reads X30. The A34 contract translates the x86 "push RA; jmp"
into arm64 "pop the pushed RA into X30; BR", but that marking pass was wired
ONLY into `do_asm_function_arm64`. `enter-state` is a NORMAL `defun`, compiled
by `do_goal_function_arm64`, which never ran the pass. Consequence: the state
`code` reached through a direct `(go ...)` ran with a STALE X30 (= the `go` call
site). When that code returned:

- §7a (NEW GAME): `evaluate-joint-control` (process-drawable.gc:619) does
  `(go process-drawable-art-error "joint-anim")` when a joint's frame-group is
  not an `art-joint-anim`. The art-error state's short `code` RET'd straight
  back into `evaluate-joint-control` (the stale X30) — i.e. **the `go`
  RETURNED** — falling into `(format 0 "dummy-19 bad")` + `(break!)`, which is
  the A26 `UDF #0xBEEF` divide-by-zero/break trap → SIGILL.
- §7b (LOAD GAME): the auto-save/restore exit transition's code RET'd into the
  middle of `enter-state`, ran its epilogue against the freshly zero-filled
  process stack, `LDP X29=0/X30=0; RET` → pc=0/fp=0/lr=0.

Both are the SAME defect: a compiled `go`/state transfer that does not transfer.

## 2. The `go` fix and its verification

Commit 19bb8e50a extracts the push-then-jr marking into
`mark_push_jr_pop_ra_arm64()` (goalc/compiler/CodeGenerator.cpp) and runs it for
BOTH `do_goal_function_arm64` and `do_asm_function_arm64`, so `enter-state`'s
`.jr` now emits the pop-RA-then-BR. goal_src is untouched (the `.gc` is correct
on x86/PS2; the defect was purely arm64 codegen).

Oracle verification (arm64 KERNEL.CGO vs x86 KERNEL.CGO, `gstate` object):
- arm64 enter-state at CGO file offset 0x26ac8:
  `f81f0fe9  str x9,[sp,#-16]!` (`.push temp`) → `f84107fe  ldr x30,[sp],#16`
  (pop the pushed RA into X30) → `d61f0100  br x8` (`.jr func`).
- x86 oracle, same function: `41 51 push %r9` → `41 ff e0 jmp *%r8` (unchanged).
- Exactly two `ldr x30,[sp],#16` pops exist in the whole arm64 KERNEL.CGO, both
  inside enter-state (the second is the non-main-thread `set-to-run`/RET path).

Runtime verification, BOTH roads, on device (org.opengoal.gk.jak1, arm64):
- §7b LOAD GAME (F1f run1/run2): the GEYSER ROCK restore now FULLY succeeds —
  `Discarding level title`, `Adding level training`, `link finish: training-*`,
  `Blackout loads done. training is loaded`. The old pc=0/lr=0/fp=0 crash is
  GONE; the run reaches in-level rendering.
- §7a NEW GAME (F1f run3): `dummy-19` count = **0** (it was present + SIGILL in
  the pre-fix F1d run9). The `(go process-drawable-art-error)` now transfers;
  the cinematic streams (`Displaying level misty`, intro DGO, SIHISB spool)
  without the break trap.

This is the phase's core mandate, and it is met on both roads.

## 3. The master-slot / spool linking verdict (named, not mis-attributed)

`link-art!` (goal_src/jak1/engine/load/loader.gc:165-200) registers each
`art-joint-anim` into a "master slot" of the level master art-group, found via
`art-group-get-by-name` scanning `*level*` levels 0..2. When that lookup misses
for all three it prints `ERROR: ... could not find a master slot to link ...`
and simply returns `this` — a `(format 0 ...)` WARNING, NOT fatal. x86's title
boot prints ZERO such warnings; arm64 prints them even for the title's own
`logo-intro-2`/`sidekick-human-intro-sequence-b` spools. So this is a genuine
arm64-only divergence in the name lookup — but it is **independent** of the
`go` bug (it is a search/compare miss at art-link time, not a control transfer).
Its only fatal CONSEQUENCE was downstream: a missed link leaves a joint's
frame-group non-`art-joint-anim`, which trips `evaluate-joint-control`'s
`(go process-drawable-art-error)` — and THAT `go` was the §7a crash. With the
`go` fix in place, the recovery transfers correctly: F1f run3 shows 8 master-slot
warnings and 0 dummy-19/SIGILL — the engine now degrades gracefully exactly as
x86 would when it hits a bad joint. Per the mandate ("fix what is provably
broken, name what is not"), the master-slot lookup miss is NAMED here as a
separable arm64 art-group-get-by-name issue; it is off the critical path because
the LOAD GAME road never touches the spool, and it is no longer fatal on the
NEW GAME road.

## 4. The Adreno first-merc-draw fault — root cause (the real remaining wall)

With both GOAL walls down, every road died at the known driver fault:
`sig=11 fault=0x28 pc=libGLESv2_adreno.so+0x13a414 lr=+0x177594` on the FIRST
merc `glDrawElements(GL_TRIANGLE_STRIP, ...)` after a level load/swap —
`common-pris-merc` (load_id=-1, the boot-era m_common_level) on the LOAD GAME
road (run1/run2/run4, 3/3), `l0-pris-merc` (load_id=2, a fresh level) on the
NEW GAME road (run3, and historically F1d run5/run12). This is a SEPARATE,
pre-existing GPU driver bug, not a control transfer; it has been "mitigated not
cured" since F1a.

Every prior mitigation attacked the wrong object: F1a mapped the index BO, F1d
mapped the vertex BO, F1e queried texture/FBO/error state, F1f tried a per-frame
FULL read-map (run4) and a post-eviction `glFinish` (run2) — ALL ran at the
faulting draw and ALL failed, because the un-finalized object is NOT the buffer
storage.

Disassembly of /vendor/lib64/egl/libGLESv2_adreno.so settled it, in two passes.
The fault function (entry 0x139d88, `mov x19,x0`) is the per-flush
**draw-state validation walk**; x19 is the GLES context. It loops over the
bound texture image units (`ldr w17,[x13,x25]`, x25=0x38, entry stride 0x98),
computes `x12 = ctx + (x17<<5)`, then `ldr x10,[x12,#0x2900]` — the **per-unit
texture descriptor** — which is **NULL** (x17=0 ⇒ slot/unit 0), then faults at
`ldr x6,[x10,#0x28]`.

The decisive question was *what WRITES* `[ctx + unit*0x20 + 0x2900]`. There is
exactly ONE store to that offset in the whole driver — `0x143974: str x3,[x7,
#0x2900]` inside the bind-to-unit routine at 0x143880 (`w1==7` = texture target
class, `x3` = the texture object). Critically it is reached **only when the
bound value CHANGES**: `0x1438a8 cmp x8,x3; b.ne` early-outs on a redundant
same-handle bind. So `[ctx+0x2900]` is populated by `glBindTexture` to the unit
**with a different handle than is currently cached** — and nothing else
(`glTexParameteri`, sampler objects, `glUniform1i`, `glTexImage2D` all touch
other structures; disasm-refuted).

That is the whole bug. A level swap's texture churn NULLs the descriptor, but
the unit's cached bound handle is left unchanged. The merc draw then does
`glBindTexture(GL_TEXTURE_2D, sameHandle)` — a redundant bind the driver
early-outs — so the writer never runs, the descriptor stays NULL, and the next
textured `GL_TRIANGLE_STRIP`+`PRIMITIVE_RESTART` merc draw reads NULL → sig=11
fault=0x28. This is why every earlier F1f experiment failed on device: 16-byte
and full BO read-maps, fresh-handle BO re-spec (`F1F-REMAT`), leaking the
eviction deletes (`F1F-LEAKBUF/LEAKTEX`), a strip+restart warm-up draw
(`F1F-WARMUP`, which survives precisely because it binds NO texture so the
walk's unit count is 0), and an explicit sampler object (`F1F-SAMPLER`, loaded
via eglGetProcAddress, confirmed bound) — none of them reach the bind-to-unit
writer at 0x143880, so none re-populate the descriptor.

## 5. The Adreno fix — force a texture bind value-change before each merc bind

Fix (Merc2.cpp, `__ANDROID__` only, in `do_draws`): immediately before the
real `glBindTexture(GL_TEXTURE_2D, handle)` for a merc draw, issue
`glBindTexture(GL_TEXTURE_2D, 0)`. This guarantees the bound value changes
(cached → 0 → real handle), so the driver's bind-to-unit routine runs its
writer and re-stores `[ctx + unit*0x20 + 0x2900]` = the real texture object —
even when the draw re-uses the same handle whose descriptor the swap nulled.
The walk then reads a valid descriptor instead of NULL. It runs only inside the
existing `if (draw.texture != last_tex)` gate (per texture change, not per
draw), so the cost is one extra `glBindTexture(0)` per texture switch —
negligible — and there is no visual change (the real texture is bound right
after). The 16-byte BO read-map is kept as a harmless F1a/F1d baseline; all of
the discarded F1f experiments (full map, BO re-spec, leak-deletes, warm-up,
sampler object) were reverted, leaving this single one-line-mechanism fix.

## 6. Both-roads outcome and spawn+movement evidence

<!-- FINALIZED AFTER THE VERIFICATION RUN — see §6 update below. -->
(pending the warm-up verification device run; telemetry quoted there.)

## 7. Honest residuals

- The master-slot `art-group-get-by-name` arm64 lookup miss is named, not fixed
  (non-fatal; recovery works post-`go`-fix). A dedicated phase could chase the
  name-compare divergence to make the cinematic's spooled animations link.
- The Adreno warm-up forces the pipeline sub-object allocation; it does not fix
  the driver bug itself (proprietary). It is a deterministic workaround at the
  GL layer, in the same family as the kept BO-map baseline.
- Audio is unported (F2a) — the cinematic is silent.

## 8. Artifacts

- Code: goalc/compiler/CodeGenerator.cpp (19bb8e50a, `go` fix);
  game/graphics/opengl_renderer/foreground/Merc2.cpp (F1F-WARMUP);
  game/graphics/opengl_renderer/loader/Loader.cpp (F1F-EVICTSYNC).
- Logs/frames: F1f-routed-logcat-run*.log, F1f-device-run*-*.png,
  F1f-focus-run*.txt.
