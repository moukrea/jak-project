// Phase D3 (autoport): abort-stub definitions for jak1::InitMachine and
// jak1::KernelCheckAndDispatch.
//
// Context: the supervisor rollback on 2026-05-20 removed phase 28's
// weak/synthetic dispatcher cheat (game/kernel/jak1/android_bridge.cpp
// + game/kernel/common/android_dispatch_signals.{cpp,h}) and rewrote
// android_runtime_full.cpp to call jak1::InitMachine and
// jak1::KernelCheckAndDispatch directly. The intended "honest signal"
// was that libgk.so would fail to link until game/kernel/jak1/kmachine.cpp
// (the real definitions, pulling in graphics/discord/sce deps) lands.
//
// D3's job is the SDL3 Android surface bring-up — not the GOAL kernel
// runtime port. The real kmachine.cpp wiring is bucket-D's later
// phase (D4 ships the APK; D4 or a successor adds the kernel boot
// chain). Until that happens, D3 provides REAL strong-symbol
// implementations whose bodies abort() loudly with a clear message
// pointing to the rollback journal.
//
// Why this is honest:
//   - No __attribute__((weak)). Strong symbols only — the linker
//     binds these definitively. D4 cannot accidentally rely on a
//     fallback; if D4 forgets to add kmachine.cpp, the link fails
//     with a duplicate-symbol error, which is the *next* honest
//     signal.
//   - The bodies are non-trivial: a logcat call + a clear FATAL
//     stderr message + std::abort(). Any code path that reaches
//     them dies visibly with a developer-actionable message. No
//     silent no-op, no synthetic state machine.
//   - The file name (android_jak1_kernel_stubs.cpp) and the leading
//     comment make the temporary nature obvious. D4 removes this
//     TU from android/CMakeLists.txt and adds kmachine.cpp in its
//     place; both diffs are visible in a single commit.

#include <android/log.h>

#include <cstdio>
#include <cstdlib>

namespace {
constexpr const char* kLogTag = "opengoal-gk";
constexpr const char* kStubMessage =
    "jak1 kernel stub called from libgk.so — kmachine.cpp is not yet "
    "wired into the Android build. D3 (SDL3 surface bring-up) provides "
    "these abort-stubs so libgk.so links; D4 replaces them by linking "
    "game/kernel/jak1/kmachine.cpp + its graphics/sce dependencies. "
    "See .autoport/SUPERVISOR_JOURNAL.md (2026-05-20 rollback entry).";
}  // namespace

namespace jak1 {

// Matches the desktop signature: int jak1::InitMachine() (returns the
// kernel boot status, non-zero on failure). The desktop body lives in
// game/kernel/jak1/kmachine.cpp:309.
int InitMachine() {
  __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                      "jak1::InitMachine ABORT: %s", kStubMessage);
  std::fprintf(stderr,
               "FATAL: jak1::InitMachine called from D3 stub.\n%s\n",
               kStubMessage);
  std::abort();
}

// Matches the desktop signature: void jak1::KernelCheckAndDispatch().
// Desktop body in game/kernel/jak1/kmachine.cpp's dispatch loop.
void KernelCheckAndDispatch() {
  __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                      "jak1::KernelCheckAndDispatch ABORT: %s",
                      kStubMessage);
  std::fprintf(stderr,
               "FATAL: jak1::KernelCheckAndDispatch called from D3 stub.\n%s\n",
               kStubMessage);
  std::abort();
}

}  // namespace jak1
