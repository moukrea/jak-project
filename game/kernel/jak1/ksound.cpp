#include "ksound.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>

#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/ksound.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/system/boot_replay.h"

namespace jak1 {
namespace {
u32 boot_replay_rpc_busy(s32 channel) {
  const char* boundary = std::getenv("OG_BOOT_REPLAY_BOUNDARY");
  if (!boundary || std::strcmp(boundary, "actors-sweep") || !boot_replay::active()) {
    return RpcBusy(channel);
  }

  boot_replay::checkpoint("rpc-busy-channel", &channel, sizeof(channel));
  u32 actual_busy = RpcBusy(channel);
  const auto check_busy = [channel](u32 busy, const char* source) {
    if (busy > 1) {
      std::fprintf(stderr, "[boot-replay] invalid rpc-busy=%u channel=%d source=%s\n", busy,
                   channel, source);
      std::fflush(stderr);
      std::abort();
    }
  };
  check_busy(actual_busy, "live");
  u32 busy = actual_busy;
  boot_replay::input("rpc-busy", &busy, sizeof(busy));
  check_busy(busy, "stream");

  // Recorded readiness cannot expose a receive buffer still being written by the IOP.
  // These live polls do not consume replay records or change the recorded decision.
  if (!busy && actual_busy) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (actual_busy) {
      if (std::chrono::steady_clock::now() >= deadline) {
        std::fprintf(stderr,
                     "[boot-replay] rpc-busy readiness timeout channel=%d after 5000ms\n",
                     channel);
        std::fflush(stderr);
        std::abort();
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
      actual_busy = RpcBusy(channel);
      check_busy(actual_busy, "live-wait");
    }
  }
  return busy;
}
}  // namespace

/*!
 * Set up some functions which are somewhat related to sound.
 */
void InitSoundScheme() {
  make_function_symbol_from_c("rpc-call", (void*)RpcCall_wrapper);
  make_function_symbol_from_c("rpc-busy?", (void*)boot_replay_rpc_busy);
  make_function_symbol_from_c("test-load-dgo-c", (void*)LoadDGOTest);
  make_stack_arg_function_symbol_from_c("rpc-call", (void*)RpcCall_wrapper);

  // PC port interns
  make_function_symbol_from_c("pc-sound-set-flava-hack", (void*)set_flava_hack);
  make_function_symbol_from_c("pc-sound-set-fade-hack", (void*)set_fade_hack);
}
}  // namespace jak1
