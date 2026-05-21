# Phase D4 — Wire jak1 kmachine.cpp; APK boots past the D3 abort on device

## What this phase delivers

The **android/ libgk.so** linked against the **real upstream
`game/kernel/jak1/kmachine.cpp` + `game/kernel/jak1/kboot.cpp`**,
packaged into an APK, installed on the user's Redmi Note 9 Pro, and
verified on-device:

1. `jak1::InitMachine ABORT` no longer appears in logcat (D3's
   abort-stub is gone).
2. `android_jak1_kernel_stubs.cpp` is **deleted** (no replacement
   abort-stub allowed).
3. `goal_main → InitMachine` runs all the way through real
   `jak1::InitMachine`, then control returns to `goal_main` and the
   render loop entry `android_renderer_run: entered` fires.
4. `android_renderer: sustained swap 60` (or higher count) appears
   in logcat — D3's frame counter proves the render loop runs.
5. Real upstream kmachine logs appear in logcat (`InitIOP OK`,
   `InitSound`, `InitRPC`, `Initialized GOAL heap`, `Got DGO file
   header for KERNEL.CGO`, `link finish: gcommon` — the same
   markers the desktop oracle emits, which D4 must demonstrably
   reach on Android).
6. The process does NOT crash with SIGABRT/SIGSEGV/SIGILL during
   the validation window (60-90 s).

D4 does **not** require pixel-perfect title rendering — that's a
follow-up phase. The bar is "real kmachine.cpp runs on the phone,
the render loop turns frames, no fatal in 60 s of capture."

## Why this matters

D3's structural validator passed because it checked symbol tables,
not behavior. The device proved D3's renderer never enters — the
D3 abort-stub fires first inside InitMachine. **D4 is the first
phase whose deliverable is verified on the actual device by the
validator script.** No more validator wishful thinking.

## Engineering background

Upstream `game/kernel/jak1/kmachine.cpp` is large (~1000 lines) and
pulls these transitive headers / deps:

- `game/external/discord_jak1.h` — Discord-RPC integration; the
  desktop build links the Discord library. Android: already
  abort-stubbed in `android_runtime_compat.cpp` (look for
  `discord_*` symbols).
- `game/graphics/gfx.h` (and `gfx.cpp`) — the gfx subsystem entry
  points (`Gfx::Init`, `Gfx::CompleteCurrentFrame`, etc.). The
  desktop wires these to OpenGL+ImGui. Android compromise: stub
  them in `android_runtime_compat.cpp` with **real bodies** that
  log via `__android_log_print` and return sensible values
  (`Gfx::Init() -> 0`, `Gfx::CompleteCurrentFrame() -> {}`,
  `Gfx::set_main_thread_id(x) -> {}`).
- `game/system/Deci2Server.h` — debugger socket. Already exists in
  android_kernel via the upstream `Deci2Server.cpp`.
- `game/sce/libpad.h` / `game/sce/libgraph.h` — PS2 SCE library
  headers. Already android-stubbed in `android_runtime_compat.cpp`.
- A few CLI11-style argv-parsing helpers that go through
  `game/main.cpp` — Android's `goal_main` already reproduces the
  argv it needs in `android_goal_main.cpp`, so kmachine's argv
  parsers can be exercised lightly (they handle missing args
  gracefully).

`kboot.cpp` pulls similar deps + ee_loop / ee_runner / overlord IPC
which the existing android_kernel already provides.

## Concrete deliverables

### 1. Delete the D3 abort-stub

`android/android_jak1_kernel_stubs.cpp` must be **deleted** from
the source tree AND removed from `android/CMakeLists.txt`'s
`android_kernel` sources. The strong-symbol abort-bodies that
substituted for `jak1::InitMachine` and `jak1::KernelCheckAndDispatch`
go away; the real definitions from kmachine.cpp take their place.

### 2. Add jak1 kmachine + kboot to the kernel archive

In `android/CMakeLists.txt`, the `android_kernel` source list (the
file currently has `game/kernel/jak1/{fileio,kdgo,klink,klisten,
kprint,kscheme,ksound}.cpp`) **adds**:

- `game/kernel/jak1/kmachine.cpp`
- `game/kernel/jak1/kboot.cpp`

If these files fail to compile on Bionic out of the box, fix the
specific issues in `android_runtime_compat.cpp` (real shim bodies,
no weak/abort tricks). Common likely issues:

- `<sys/user.h>` — Bionic API < 33 doesn't expose it. xdbg's
  thread-id helper already has an Android variant in compat.
- `pthread_setname_np` arity (already handled in compat).
- `mallinfo()` shape difference (already handled).
- Any `<execinfo.h>` (backtrace) usage — Bionic-safe wrapper in
  compat already exists.

If kmachine has truly intractable platform requirements (e.g.,
direct discord_rpc_init from the c-side discord-rpc library which
isn't on Android), the **single legitimate pattern** is: add a
**real-body** stub in `android_runtime_compat.cpp` that
log-and-no-ops, and document why in a `__android_log_print(ANDROID_LOG_INFO,
...)` at the start of the body. No new files with `_stubs` in the
name. No abort() bodies (the runtime must continue past).

### 3. Build + install + run validation flow

Add `.autoport/lib/d4_run.sh` that:

1. Builds libgk.so (`bash .autoport/lib/d3_build.sh`).
2. Builds the APK (`cd android && ./gradlew assembleJak1Debug`).
3. Installs via `device_install_and_launch` from
   `.autoport/lib/device-validate.sh` (handles MIUI install
   quirks).
4. Captures logcat to `.autoport/reports/D4-boot.log` for 60 s
   (uses `device_wait_for_marker` from device-validate.sh).
5. Writes the exit determination to `.autoport/reports/D4-status.txt`.

### 4. Markdown report

`.autoport/reports/D4-launch.md` — what was wired, what shims were
added, what markers were observed, what's the next blocker (if
any).

## Anti-cheat constraints

1. **`android/android_jak1_kernel_stubs.cpp` must not exist** at
   end of phase. The validator greps for it.
2. **No new `*_stubs.cpp` files** added to the build. Shims go in
   `android_runtime_compat.cpp` as real-body functions (existing
   pattern).
3. **No `abort()` / `std::abort()` introduced** in any new code
   paths since D3's commit. The runtime must run, not crash.
4. **No weak symbols introduced.** The codegen-lock and the
   D1/D2/D3 lock pattern still apply: `goalc/compiler/IR.cpp`,
   `goalc/emitter/IGenARM64.{cpp,h}`, `goalc/emitter/ObjectGenerator.{cpp,h}`,
   `goalc/compiler/CodeGenerator.{cpp,h}` byte-identical to A4.
5. **`classify_ir_arm64.py` byte-identical to A1.**
6. **`out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO`** byte-identical to
   A2 baseline.
7. **Desktop gk smoke test still reaches `link finish: logo`** —
   we never break the desktop path.
8. **D3's libgk.so symbol-table invariants still pass** — SDL3
   Android driver + JNI bridge symbols still present.
9. **The on-device validation MUST capture real logcat from a real
   install**. The validator's grep for the required markers runs
   against the captured logcat file, not synthesised text.
10. **`jak1::InitMachine ABORT` MUST NOT appear** in the captured
    logcat. (The whole point of D4 is to remove the D3 abort.)

## Files you will create / modify

| Path | Purpose |
|---|---|
| `android/android_jak1_kernel_stubs.cpp` | **DELETE** |
| `android/CMakeLists.txt` | remove the stub TU; add kmachine.cpp + kboot.cpp |
| `android/android_runtime_compat.cpp` | extend with real-body shims for kmachine deps as needed |
| `.autoport/lib/d4_run.sh` | build + install + launch + logcat capture |
| `.autoport/reports/D4-boot.log` | captured logcat |
| `.autoport/reports/D4-status.txt` | pass/fail marker for the validator |
| `.autoport/reports/D4-launch.md` | engineering report |

## Pitfalls

- **The 691 out-of-range NOPs from C4** are still in the arm64
  CGOs at `out/jak1-arm64/iso/`. The Android APK loads the *same*
  arm64 KERNEL.CGO (the iso_data extraction lives at
  `/data/user/0/org.opengoal.gk.jak1/files/iso_data/jak1/`). Those
  NOPs may bite when real kmachine runs more bytecode than
  qemu-validated. If you hit `udf #N` / `SIGILL` in logcat, the
  cause is the far-reloc gap, not D4's wiring. Document and stop;
  the fix is a follow-up emitter phase, not D4's job.
- **The R14/R15 trampoline workaround** survives within one GOAL
  function. Kmachine triggers many cross-function calls. If you
  see "function returned to garbage address" / SIGSEGV right after
  a GOAL `(call ...)`, that's the cross-call ABI gap. Same
  documentation pattern; don't unlock the codegen.
- **MIUI install dance**: device-validate.sh's
  `device_install_and_launch` already handles the appops grant +
  USER_RESTRICTED retries. Use it.
- **The render loop entry**: order in `goal_main` is `kheap →
  KERNEL.CGO open → InitMachine → android_renderer_run`. If
  InitMachine returns 0 from real kmachine, the renderer enters
  next. If kmachine's body asserts/aborts somewhere internal,
  catch the stack with `pthread_setname_np("GameLogic")` so
  Android's tombstone names the thread cleanly.
- **The D3 commit chain is intact** (`7f25d888a`, `45bfe26c9`,
  `e30996c3b`). D4 commits ON TOP, doesn't revert any of them
  except for the specific stub file delete.

## Reading list

- `.autoport/reports/D4-boot.log` (after first attempt) — your
  primary diagnostic
- `game/kernel/jak1/kmachine.cpp` — what you're wiring in
- `game/kernel/jak1/kboot.cpp` — sibling boot logic
- `android/android_runtime_compat.cpp` — the shim layer you may
  extend; **note its real-body pattern** (logged, returns sensible
  values, doesn't abort)
- `.autoport/lib/device-validate.sh` — `device_install_and_launch`
  + `device_wait_for_marker`
- `.autoport/SUPERVISOR_JOURNAL.md` — context on the rollback +
  the C4 691-NOP / R14-R15 known gaps

## Done definition

`.autoport/validators/phase-D4-android-apk-title.sh` exits 0.
Checks (device-first, 18 total):

1. `android/android_jak1_kernel_stubs.cpp` is GONE.
2. `android/CMakeLists.txt` no longer references the stub TU AND
   adds `game/kernel/jak1/kmachine.cpp` to the kernel archive.
3. `.autoport/lib/d4_run.sh` exists + executable.
4. libgk.so builds (`d3_build.sh` succeeds).
5. APK builds (`./gradlew assembleJak1Debug` succeeds).
6. APK installs on the device (via `device_install_and_launch`).
7. App launches without immediate crash (process survives ≥ 5 s).
8. **Logcat does NOT contain `jak1::InitMachine ABORT`**.
9. **Logcat does NOT contain `SIGABRT` / `SIGSEGV` / `SIGILL` /
   `FORTIFY` for our process** in the 60 s capture window.
10. Logcat CONTAINS `android_renderer_run: entered`.
11. Logcat CONTAINS `android_renderer: sustained swap 60` (or
    higher count — at least 1 second of render loop).
12. Logcat CONTAINS at least 3 of: `InitIOP OK`,
    `Initialized GOAL heap`, `Got DGO file header for KERNEL.CGO`,
    `link finish: gcommon`, `link finish: gkernel`,
    `link finish: gstate`. (Real kmachine reaches real DGO load
    + link work.)
13. No new `*_stubs.cpp` files added since D3 commit.
14. No new `abort()` calls in source files since D3 commit.
15. Codegen files (IR.cpp / IGenARM64.{cpp,h} / ObjectGenerator.{cpp,h} /
    CodeGenerator.{cpp,h}) byte-identical to A4 baseline.
16. `classify_ir_arm64.py` byte-identical to A1 baseline.
17. `out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO` byte-identical to A2
    baseline.
18. Desktop gk smoke test still reaches `link finish: logo`.

## Note on cheat avoidance

The supervisor halted D3 because of stub-piling concerns and the
device gave the diagnostic. D4 will be tempting to short-circuit
("just add another abort-stub for some random kmachine dep").
**Resist.** If a kmachine dep is genuinely intractable, the
SUPERVISOR-APPROVED pattern is:

- Real-body shim in `android_runtime_compat.cpp`
- Logs at the start of the body via `__android_log_print`
- Returns sensible values (0 for ints, {} for void)
- Does NOT abort
- Lets the runtime continue and surface the next concrete failure

A discord_jak1::InitDiscord that logs "stub" and returns 0 is
fine. A discord_jak1::ShouldShowPresence that logs and returns
false is fine. A discord_jak1::InitMachine that returns 1 instead
of 0 because "the desktop version returns 1 sometimes" is NOT
fine — match upstream return semantics where possible.
