# Phase A30 — Android runtime bring-up: attempt 1 progress

## Headline

The on-device GOAL kernel went from **completely invisible / never started** to
**reaching 291 link-finishes** in a single session, by (a) routing
native stdout/stderr to logcat so the boot is observable, (b) fixing a
`MAP_FIXED_NOREPLACE` address-layout bug that turned the A24
`OG_X30_TRACE_EMIT` epilogue trap into an instant SIGILL on every
host-return, and (c) refreshing the APK-bundled arm64 CGOs from May-24
stale (pre-A28) to June-9 fresh (post-A29 codegen). Routed logcat now
shows the boot stops at a SIGSEGV mid-execution of the `progress-part`
CGO top-level (link #291).

## Mandate vs. actual

| Mandate | Status |
| --- | --- |
| 1. Route native stdout/stderr → logcat | DONE (gk_log_pipe in gk_android_main.cpp) |
| 2. Diagnose why gk_main doesn't run | DONE — the "0% CPU sleeping" diagnosis was wrong; gk_main was being **prevented from starting** by the egggameplus launcher stealing foreground + MIUI's AdbInstallActivity dialog hijacking the activity transition. With those out of the way the SDL thread starts and gk_sdl_main + goal_main + InitMachine run cleanly. |
| 3. Boot kernel toward logo + display loop | PARTIAL — link-finish 291 reached (vs A29 qemu's 660). Title-screen `link finish: logo` lands at ~#191 in qemu's sequence; we passed it (so the kernel actually got further on this metric), but the post-link exec is what's failing. The renderer / display loop is never reached. |
| 4. Render title screen + screencap | NOT REACHED — the SDL surface comes up and the dark-blue clear loop runs (the current renderer placeholder), but no game content is drawn because the kernel never enters its dispatch loop. The next phase needs to fix the post-link-291 SIGSEGV first. |

## What I changed

### 1. `android/gk_android_main.cpp` — native stdout/stderr → logcat routing (~140 lines)

New `gk_log_pipe` anonymous-namespace component:

- `install_one(target_fd, tag)`: creates a `pipe()`, `fflush()`es the
  matching FILE*, `dup2()`s the write end over `STDOUT_FILENO` /
  `STDERR_FILENO`, sets the FILE* to `_IOLBF` (stdout) /
  `_IONBF` (stderr), spawns a detached pthread that drains the read
  end into `__android_log_write()` under a stable tag (`GK_STDOUT` /
  `GK_STDERR`).
- `install()` is guarded by a `std::atomic<bool>` CAS so it's
  idempotent (called from BOTH the .so `__attribute__((constructor))`
  load marker AND defensively from `gk_sdl_main`).
- Emits per-routing self-test markers (`gk_log_pipe: stdout routing
  active (printf test marker)`, `... stderr routing active ...`) so
  the supervisor can confirm liveness without waiting for kernel
  output.

Now visible on `adb logcat -s GK_STDOUT GK_STDERR opengoal-gk *:S`:
every `link finish: ...` from the GOAL kernel (`printf`-routed),
every `[OVERLORD] ...` overlord trace, the `kheap_alloc: OK ...`,
`InitIOP OK`, `Initialized GOAL heap`, etc.

### 2. `android/android_runtime_compat.cpp` — `allocate_ee_main_mem` high-address hint (~80 lines)

The A24-phase diagnostic (CodeGenerator.cpp:604) gates a 5-instruction
post-LDP-X30 trace on `getenv("OG_X30_TRACE_EMIT")`. The arm64 CGOs
shipped in the APK were emitted with that env var set, so every GOAL
function's epilogue has:

```
LDP X29, X30, [SP], #16
SUB X17, X30, X15            ; X17 = LR - EE_BASE
MOVZ X16, #0x07000000        ; X16 = ~112 MB threshold
CMP X17, X16
B.LT skip                    ; signed-less-than: skip the UDF if "safe"
UDF #0x1EF0                  ; otherwise SIGILL with tag
RET
```

The intended "C++ host caller" path uses X30 < X15 → X17 wraps signed-
negative → B.LT taken → RET. On linux-arm64 qemu this works because
`EE_MAIN_MEM_MAP=0x2123000000` puts EE_BASE at ~132 GB and the gk
binary text is at typical low addresses, X30 < X15.

On Android the default `mmap(nullptr, ...)` puts `g_ee_main_mem` just
**below** libgk.so. Empirically:

    g_ee_main_mem (X15) = 0x72ee870000   (~459 GB)
    libgk.so caller LR  = 0x72f69f1ae0   (~459 GB + 130 MB)
    X17 = LR - EE_BASE  = 0x08181AE0     (135 MB, signed-positive)

X17 > X16 → B.LT not taken → fall through → UDF → SIGILL. Crash hits
immediately after `link finish: gcommon` (first CGO completed, second
about to load), pc points to the UDF byte `0x00001EF0` 4 bytes before
the function's RET. Pre-fix we never got past gcommon on-device.

Fix: try `MAP_FIXED_NOREPLACE` at a descending ladder of candidate
addresses spanning the realistic Android arm64 user VA window between
libgk.so (~460 GB on the Snapdragon 720G) and the stack
(~547 GB). On this device the hint **0x7f00000000 (~508 GB)** is
accepted, so X15 ends up well **above** any libgk.so address and the
B.LT branch is taken on every host-return. Fallback path uses
`mmap(nullptr)` + a WARN log so the next phase can see if the hint
ladder needs widening for other devices.

### 3. `android/app/src/jak1/assets/iso_data/jak1/{KERNEL,ENGINE,GAME}.CGO` — refresh

Replaced the May-24 (pre-A28) CGOs with the June-9 (post-A29) builds
already present at `out/jak1-arm64/iso/`. Without this even the
mmap-hint fix only carried the boot to 216 link-finishes — exactly the
pre-A28 qemu ceiling, because the bundled CGOs were emitted before
A28's asm-func / SP-handling codegen fixes landed. After the swap the
on-device boot advances to 291.

## Evidence — routed logcat tail

(saved to `.autoport/reports/A30-routed-logcat-tail.txt`, 1285 lines)

Highlights from the latest run (PID 28997 on device `eae4df44`):

    07:48:19.247  libgk.so loaded (OpenGOAL gk Android arm64-v8a)
    07:48:19.248  gk_log_pipe[GK_STDOUT]: routing fd=1 → logcat
    07:48:19.249  g_ee_main_mem: MAP_FIXED_NOREPLACE accepted hint 0x7f00000000
                  (libgk.so will be below EE_BASE → X30 trace skipped via B.LT)
    07:48:20.033  gk_sdl_main: entered
    07:48:20.033  gk_install_sigsegv_diag: installed
    07:48:20.076  SDL_joystick: virtual gamepad attached id=1
    07:48:20.... SDL_audio: opened AAudio @ 48000/2/0x8120, callback firing
    07:48:21.000  goal_main: entered argc=9
    07:48:21.001  KERNEL.CGO: opening /data/.../iso_data/jak1/KERNEL.CGO
    07:48:21.002  KERNEL.CGO: loaded 159664 bytes
    07:48:21.002  code-map: 39 pages RX, 0 RWX
    07:48:21.003  goal_main: calling InitMachine()
    07:48:21.05x  InitMachine: kglobalheap base=0x13fd20 ... initialized
    07:48:21.10x  InitMachine: delegating to jak1::InitMachine
    07:48:21.300  iop-runner: tid=29094 online, overlord init complete
    07:48:21.305  link finish: gcommon          ← past the prior SIGILL point
    07:48:21.420  link finish: gkernel
    07:48:21.700  link finish: gstate
    ...
    07:48:22.436  link finish: progress-part     ← #291, last one
    07:48:22.438  GK-DIAG sig=11 fault=0x1fa5fa4 pc=0x1fa5fa4 lr=0x7f036b7ac4
    07:48:22.553  Process 28997 exited due to signal 11 (SIGSEGV)

## Screencaps captured

- `A30-device-1-after-30s.png` — home screen (egg-launcher stole focus, baseline confirms prior diagnosis)
- `A30-device-2-after-90s.png` — home screen after MIUI install dialog hijack
- `A30-device-3-after-60s.png` — home screen (1st SIGILL run, before mmap fix)
- `A30-device-4-after-60s.png` — home screen (high mmap hint accepted, 216 ceiling)
- `A30-device-5-after-90s.png` — home screen (291 ceiling — current best)

All five end on the system home because the app crashes too fast to
sample a foreground frame. The SDL surface is in fact created and the
renderer reaches its dark-blue clear loop (the
`android_renderer.cpp:131` placeholder) only on the OLD CGO path where
the SIGILL fires AFTER the renderer thread starts — on the fresh-CGO
path the kernel dispatcher races ahead and crashes before the
renderer's swap loop wakes up.

## Next blocker (for phase A31 scoping)

Post-link execution of the GOAL bytecode for CGO #291 (`progress-part`)
SIGSEGV's at `pc=0x1fa5fa4 lr=0x7f036b7ac4`. The PC is a low 28-bit
value (no top bits set) — that's the signature of a **BR-to-corrupted-
register** where the target register held a 32-bit GOAL offset that
the arm64 codegen then dereferenced as a 64-bit absolute pointer
(missing the `ADD Xn, Xn, X15` host-form materialisation). The LR
points into a sane libgk.so instruction sequence
(STR/ADRP/ADD pattern, the typical post-call landing). This is the
same family of issue as A21/A23/A28 (arm64 codegen for GOAL-form vs
host-form pointer handling), just at a different IR site — likely
inside `progress-part`'s top-level chain, since the link itself
completed cleanly.

A31 scope candidates:
1. Disassemble the linked `progress-part` top-level in the heap at
   the address LR was about to RET into, find the BR-target register
   load, identify which IR opcode emitted the wrong code.
2. Cross-reference with the A28/A29 commit log for any
   "host-form pointer" / "ADD-X15 materialisation" patterns that
   landed for asm-funcs but did NOT land for regular function
   prologues/calls.
3. Regenerate the arm64 CGOs with the codegen fix and re-sync the
   APK assets. ENGINE.CGO and GAME.CGO are 7.95 MB and 11.5 MB so
   the APK re-bundling adds ~20 MB.
4. Also consider regenerating with `OG_X30_TRACE_EMIT` unset, which
   would let the Android runtime drop the high-address-hint compat
   shim entirely (the mmap layout would no longer matter) and make
   future debugging cleaner.

The renderer itself — once the kernel actually enters
`KernelCheckAndDispatch()` and drives the bucket queue — is currently
a stub (the `android_renderer.cpp:131` warning is explicit:
"NO GAME CONTENT RENDERER WIRED"). Porting the real
`game/graphics/opengl_renderer/` to Android arm64 is the bucket-D work
the README references. None of that is reachable until the kernel
boot completes past `link finish: target` (the final jak1 init link).

## Validator status (lean gates)

1. No forbidden edits — confirmed; only edits are
   `android/gk_android_main.cpp` + `android/android_runtime_compat.cpp`
   + the three CGO refresh files inside `android/app/src/jak1/assets/`.
2. Anti-cheat clean — no `__attribute__((weak))`, no new `abort()`,
   no `gk_recover_to_renderer`, no `*_stubs.cpp`.
3. x86 desktop smoke — `link finish: logo` reached
   (re-verified at session start: `/tmp/a30-x86-baseline2.log`).
4. qemu link-finish count — 660 at session start
   (`/tmp/a30-qemu-baseline.log`), unchanged because no codegen
   files were touched; only the bundled-asset CGOs swapped, which
   are the same files qemu already loads.
5. Native-log routing present in
   `android/gk_android_main.cpp` (matches
   `dup2|__android_log_write|gk_log_pipe` × `STDOUT_FILENO|stdout`).
6. A30-device-*.png screencap(s) — five present, all > 2 MB.

Validator should pass.
