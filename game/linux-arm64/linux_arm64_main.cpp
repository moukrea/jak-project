// Phase C1 (autoport, bucket C): slim entry point for the aarch64-linux
// gk cross-build.
//
// Why a slim entry rather than verbatim game/main.cpp:
//
//   * main.cpp #includes graphics/gfx_test.h and calls
//     tests::run_gpu_test, which would drag the OpenGL renderer chain
//     into the link.
//   * main.cpp's discord/discord-rpc references would force a curl
//     dependency we don't ship here.
//   * The desktop runtime path inside exec_runtime() ALSO pulls in the
//     SDL3/imgui/GL stack. Calling it from C1 doesn't work — it would
//     fail at link time.
//
// Phase C1's contract is the binary BUILDS as a real aarch64 ELF with
// the GOAL kernel + overlord + system layer linked in. Phase C2 will
// wire up the kernel-boot path (KERNEL.CGO load, listener setup); phase
// C3 will land the renderer/audio chain and reach the title screen.
//
// What this entry does, in order:
//
//   1. Records the main thread id (g_main_thread_id is read by
//      common/log/log.cpp's thread-name banner and by Deci2Server).
//   2. Logs the build SHA so the binary self-identifies in `--version`
//      runs without needing the full versions::* machinery.
//   3. Returns 0 if invoked with --version, or non-zero with a clear
//      "C1: gk runtime path not yet wired" message otherwise.
//
// The point: this binary CONTAINS the real kernel + overlord + system
// code (force-linked via --whole-archive). It just doesn't drive them
// yet. C2 replaces this main with a kernel-bootstrapping shape.

#include <cstdio>
#include <cstring>
#include <string>
#include <thread>

#include "common/log/log.h"
#include "common/versions/versions.h"
#include "common/versions/revision.h"
#include "game/runtime.h"

namespace {
constexpr const char* kPhaseTag = "C1";
constexpr const char* kBuildTag = BUILT_TAG;
constexpr const char* kBuildSha = BUILT_SHA;

void print_banner(std::FILE* out) {
    std::fprintf(out,
                 "OpenGOAL gk (linux-arm64 cross-build, phase %s)\n"
                 "  built-tag: %s\n"
                 "  built-sha: %s\n",
                 kPhaseTag,
                 (kBuildTag && *kBuildTag) ? kBuildTag : "(none)",
                 (kBuildSha && *kBuildSha) ? kBuildSha : "(unknown)");
}
}  // namespace

int goal_main(int argc, char** argv) {
    g_main_thread_id = std::this_thread::get_id();

    bool show_version = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--version") == 0 ||
            std::strcmp(argv[i], "-v") == 0) {
            show_version = true;
            break;
        }
    }

    print_banner(stdout);

    if (show_version) {
        return 0;
    }

    // Honest "C1 is just the build" exit. C2 replaces this with the
    // real kernel-boot path (allocate kheap, load KERNEL.CGO, spawn
    // dispatcher, drive listener). For now: exit non-zero so callers
    // can't mistake "binary exists" for "kernel ran."
    std::fprintf(stderr,
                 "gk: phase C1 — binary built, but the kernel-boot path is\n"
                 "    not wired yet. C2 (linux-arm64-symbols) wires the\n"
                 "    runtime; C3 (linux-arm64-title) drives it to title.\n");
    return 2;
}

int main(int argc, char** argv) {
    return goal_main(argc, argv);
}
