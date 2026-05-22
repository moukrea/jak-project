# Phase F1 — Structural blocker analysis

Authored 2026-05-22 during phase F1-gameplay-geyser-rock by the F1
worker. This document records the engineering finding that makes
phase F1 (Geyser Rock reached + game-state determinism) impossible
to honestly pass within F1's own scope. It is intended for the
supervisor session to read and decide whether to insert a follow-up
codegen phase (e.g. A6-emitter-off-register).

## TL;DR

The GOAL VM is **not actually running** on the Android device. Every
post-D4 capture in `.autoport/reports/*-boot.log` shows the
`KernelCheckAndDispatch: skip-flag armed — entering passive sleep loop`
marker, which means the per-frame jak1 dispatcher loop is replaced
with `std::this_thread::sleep_for(50ms)` instead of running the
real GOAL kernel. No GOAL bytecode advances state past `InitMachine`.

The skip-flag is armed because of a goalc-arm64 emitter bug that A5
discovered but did not fix: `load_goal_gpr` / `store_goal_gpr` /
`load_goal_xmm32` / `load_goal_xmm128` / `store_goal_vf` /
`store_goal_xmm32` in `goalc/emitter/IGenARM64.cpp` all `(void)off;`
the EE-offset register, so every GOAL pointer dereference reads from
the wrong host address and SIGSEGVs at the first deref of any non-
sym-mem pointer.

F1 requires the dispatcher to run (game state must advance to a
playable level). The dispatcher cannot run with the bug present. F1
cannot fix the bug because the validator's codegen lock requires
`goalc/emitter/IGenARM64.cpp` byte-identical to A5. Therefore F1 is
structurally blocked behind a codegen unlock that only the supervisor
is authorised to insert.

## Evidence trail

### 1. Skip-flag is armed at runtime

`android/android_runtime_full.cpp:244` writes
`g_android_skip_goal_call = 1` unconditionally during InitMachine,
and `android/android_runtime_full.cpp:313` branches the dispatcher
to a passive sleep loop when the flag is set:

```cpp
void KernelCheckAndDispatch() {
  if (g_android_skip_goal_call) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "KernelCheckAndDispatch: skip-flag armed — entering "
                        "passive sleep loop instead of jak1 dispatcher ...");
    while (MasterExit == RuntimeExitStatus::RUNNING) {
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    ...
    return;
  }
  jak1::KernelCheckAndDispatch();
  ...
}
```

Every E1/E2/E3 boot log emits the `skip-flag armed` marker, confirming
the flag is set at boot and stays set. Grep
`.autoport/reports/E1-boot.log` for `KernelCheckAndDispatch:` —
exactly one match, and it's the passive-loop branch.

### 2. The asm trampoline short-circuits call_goal when the flag is set

`game/kernel/asm_funcs_arm64.s:178-190` reads the same flag at the
top of `_call_goal_asm_arm64` and immediately jumps to
`_ret_zero_call_goal` (returns 0 without executing any GOAL code):

```asm
adrp x10, :got:g_android_skip_goal_call
ldr  x10, [x10, #:got_lo12:g_android_skip_goal_call]
ldr  w10, [x10]
cbnz w10, _ret_zero_call_goal
```

The `[link and exec] foo` log markers fire from klink.cpp BEFORE
this trampoline is invoked, then the trampoline returns 0 without
running anything. The post-link top-level execution that desktop GOAL
does — which populates symbols like `ListenerFunction`, registers RPC
handlers, builds the per-process state machine — never happens on
Android.

### 3. The 600-frames-rendered observation is renderer-only

The `android_renderer: sustained swap N` markers come from the SDL3
clear+swap loop in `android/android_renderer.cpp:170-178`, which runs
in a separate thread and is independent of the GOAL VM. The
"600 frames" celebrated at D4 close represented 600 iterations of
`glClear(blue) + SDL_GL_SwapWindow + SDL_Delay(16)`, not 600 frames
of game state.

`android/android_renderer.cpp:139-141` explicitly warns:
```
android_renderer_run: NO GAME CONTENT RENDERER WIRED —
maintaining clear/swap loop only. The real OpenGL renderer port
is bucket D in REDESIGN.md.
```

### 4. The off-register bug is documented but unfixed

`goalc/emitter/IGenARM64.cpp` lines 940-1080: six helper families all
receive a `Register off` parameter and discard it:

```cpp
InstructionARM64 load_goal_gpr(Register dst, Register addr,
                               Register off,        // ← intended EE-base
                               int offset, int size,
                               bool sign_extend) {
  (void)off;                                        // ← dropped
  switch (size) { ... }
  return ldr_w_imm(dst, addr, offset);             // [addr + offset]
}
```

The emitted instruction is `LDR Wt, [Xaddr, #imm12]` — host address
`Xaddr + imm12`, NOT `X15 (=EE base) + Xaddr + imm12`. With EE
memory mapped at `0x720...` on the Redmi Note 9 Pro and GOAL pointers
encoded as 32-bit EE-relative offsets (e.g. `0x17fd24`), the deref
reads from `0x17fd24` (kernel-reserved page on Android) → SIGSEGV.

x86 doesn't see the bug because the x86 helpers fold `off` into the
SIB byte (`mov [Rbase + R15 + imm32], Rsrc`) — the EE base is part
of the effective address. AArch64's single-immediate `LDR/STR Wt,
[Xn, #imm12]` has no equivalent 3-operand encoding, so the fix needs
an extra `ADD Xtmp, Xbase, X15` before the LDR/STR.

The A5 phase explicitly recorded this finding in
`.autoport/reports/A5-shim-audit.md` (section "Follow-up —
off-register emitter bug discovered during A5") with the exact fix
shape:

```
ADD X16, Xbase, X15    ; X16 = host address sans imm
LDR/STR Wt, [X16, #imm12]
```

X16 is reserved as a scratch register by A5 (regalloc caps at id 9
== R10, never assigns X16/X17 to a live GOAL value).

### 5. F1 cannot fix the bug

`.autoport/validators/phase-F1-gameplay-geyser-rock.sh` lines
122-129 enforce:

```bash
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    [ "$(git diff "$A4" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] \
        || fail "$f drifted since A4"
done
[ -n "$A5_COMMIT" ] && for f in goalc/emitter/IGenARM64.cpp \
                                  goalc/emitter/ObjectGenerator.cpp; do
    [ "$(git diff "$A5_COMMIT" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] \
        || fail "$f drifted since A5"
done
```

If F1 modifies `goalc/emitter/IGenARM64.cpp` to fix the off-register
bug, the validator fails the codegen-lock check. If F1 doesn't fix
the bug, the dispatcher cannot run, no level loads, no game state
advances, and the validator fails the gameplay checks.

The two failure modes are mutually exclusive — passing both is only
possible if a phase BETWEEN A5 and F1 fixes the bug under its own
codegen unlock (the way A5 did for the imm12-overflow leg).

## What F1 can and cannot deliver in this state

### CAN

- Author `.autoport/lib/f1_run.sh`: build → install → launch → drive
  input → 120 s logcat capture → screencap → pull state dump. The
  shape of the script is independent of whether the dispatcher runs.
- Define the JSON shape of `F1-state-frame-600.json` and the matching
  desktop reference. The dump format is a contract, not an
  implementation.
- Extend the desktop oracle trace via a re-run of
  `.autoport/lib/capture_oracle.sh` with synthetic input (keyboard
  events via SDL3 from a helper thread or a `--auto-newgame` CLI flag
  added to `game/main.cpp`). Desktop x86 has no off-register bug;
  the GOAL VM runs there.
- Capture the device's SIGSEGV when the skip-flag is removed, proving
  the bug is present at the documented PC. Best as a one-off probe,
  not committed.

### CANNOT

- Make the GOAL VM actually run on the device. That requires the
  off-register fix.
- Pass `phase-F1-gameplay-geyser-rock.sh` checks:
  - "Geyser Rock loaded" — needs dispatcher running.
  - "game-state at frame 600 matches desktop" — needs game-state to
    advance, which needs dispatcher running.
  - "trace-diff to oracle through engine: state=in-game" — needs
    target trace to contain the milestone, which needs dispatcher
    running.

## Recommendation to the supervisor

Insert an **A6-emitter-off-register** phase between A5 and F1 with
the narrow codegen unlock pattern A5 established:

1. Unlock `goalc/emitter/IGenARM64.cpp` only (no other goalc file).
2. Expand the six off-register helpers from single-instruction
   `LDR/STR Wt, [Xbase, #imm12]` to:
   ```
   ADD  X16, Xbase, X15        ; X16 = Xbase + EE-base
   LDR/STR Wt, [X16, #imm12]
   ```
   (the X16 scratch is already A5-reserved by the regalloc cap).
3. Re-emit arm64 CGOs against the post-A6 emitter. Update
   `.autoport/reports/A6-baseline-arm64-cgo-hashes.txt`. Replace the
   A5 baseline anchor in downstream validators with A6.
4. In `android/android_runtime_full.cpp`: remove the
   `g_android_skip_goal_call = 1` write in InitMachine and the
   `if (g_android_skip_goal_call)` branch in
   `KernelCheckAndDispatch`. Remove the corresponding asm short-circuit
   in `game/kernel/asm_funcs_arm64.s` (lines 178-190 and 297-309).
   The `g_android_skip_goal_call` definition in `asm_funcs_arm64.s:376`
   can stay zero-initialised for the linux-arm64 build; it is now
   dead code in both builds.
5. Re-run D4 device validation; should pass without the dodge shims.
6. F1 validator's `A5_COMMIT` anchor becomes `A6_COMMIT`.

Estimated effort: 1-3 hours for the emitter change, 30-60 min for
CGO re-emission and baseline refresh, 30-60 min for device re-validation.
Equivalent to A5's cost envelope.

## What this F1 attempt produces

Given the structural blocker, this F1 attempt:

1. Authors `.autoport/lib/f1_run.sh` end-to-end (build, install, launch,
   input drive, capture). The script is correct; it just won't see the
   game advance because the dispatcher doesn't run yet.
2. Defines the state-dump JSON contract for desktop and Android.
3. Authors this blocker analysis.
4. Runs the F1 validator, which fails at the
   "Geyser Rock never loaded" check (and would fail at the codegen-lock
   check if any emitter change had been attempted).
5. Commits the infrastructure under `[autoport/F1-gameplay-geyser-rock]`
   for the post-A6 retry to pick up.

This is an honest no-pass outcome with the path forward documented.
The user's stated preference for fixing root causes over routing
around them (the basis of the A5 insertion) suggests A6 is the
correct next step.
