#include "kboot.h"

#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unordered_map>

#include "common/goal_constants.h"
#include "common/log/log.h"
#include "common/repl/repl_wrapper.h"
#include "common/util/Timer.h"

#include "game/common/game_common_types.h"
#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/Symbol4.h"
#include "game/kernel/common/klisten.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/ksocket.h"
#include "game/kernel/jak2/klisten.h"
#include "game/kernel/jak2/kmachine.h"
#include "game/kernel/jak2/kscheme.h"
#include "game/sce/libscf.h"

namespace jak2 {

char DebugBootUser[64];
char DebugBootArtGroup[64];

void kboot_init_globals() {
  memset(DebugBootUser, 0, sizeof(DebugBootUser));
  memset(DebugBootArtGroup, 0, sizeof(DebugBootArtGroup));
  // strcpy(DebugBootUser, "unknown");
  // CHANGED : let's just try to find the username automatically by default!
  // the default is still "unknown"
  auto username = REPL::find_repl_username();
  strcpy(DebugBootUser, username.c_str());
}

void KernelCheckAndDispatch();

s32 goal_main(int argc, const char* const* argv) {
  // only in PC port
  InitParms(argc, argv);

  init_crc();
  masterConfig.aspect = ee::sceScfGetAspect();
  auto sony_language = ee::sceScfGetLanguage();
  masterConfig.inactive_timeout = 0;
  masterConfig.volume = 100;
  masterConfig.timeout = 0;
  switch (sony_language) {
    case SCE_JAPANESE_LANGUAGE:
      masterConfig.language = (u16)Language::Japanese;
      break;
    case SCE_FRENCH_LANGUAGE:
      masterConfig.language = (u16)Language::French;
      break;
    case SCE_SPANISH_LANGUAGE:
      masterConfig.language = (u16)Language::Spanish;
      break;
    case SCE_GERMAN_LANGUAGE:
      masterConfig.language = (u16)Language::German;
      break;
    case SCE_ITALIAN_LANGUAGE:
      masterConfig.language = (u16)Language::Italian;
      break;
    default:
      masterConfig.language = (u16)Language::English;
      break;
  }
  // Set up aspect ratio override in demo
  if (!strcmp(DebugBootMessage, "demo") || !strcmp(DebugBootMessage, "demo-shared")) {
    masterConfig.aspect = SCE_ASPECT_FULL;
  }
  // removed in PC port
  //  DiskBoot = 1;
  //  MasterDebug = 0;
  //  DebugSegment = 0;

  // Gjak2-render concurrent-GOAL race gate: mark that boot CGO-linking is in
  // progress so the GL/render thread's vif_interrupt_callback skips re-entering
  // GOAL on the single shared GOAL stack while the boot thread links (and runs
  // top-levels via call_goal_on_stack). Cleared once InitMachine completes and
  // the kernel is about to be dispatched. Translation-layer only.
  g_goal_boot_linking.store(true, std::memory_order_seq_cst);

  // Launch GOAL!
  if (InitMachine() >= 0) {    // init kernel
    g_goal_boot_linking.store(false, std::memory_order_seq_cst);
    KernelCheckAndDispatch();  // run kernel
    ShutdownMachine();         // kernel died, we should too.
    // movie playback stuff removed.
  } else {
    g_goal_boot_linking.store(false, std::memory_order_seq_cst);
    fprintf(stderr, "InitMachine failed\n");
    exit(1);
  }
  return 0;
}

void KernelDispatch(u32 dispatcher_func) {
  // place our stack at the end of EE memory
  u64 goal_stack = u64(g_ee_main_mem) + EE_MAIN_MEM_SIZE - 8;

  // try to get a message from the listener, and process it if needed
  Ptr<char> new_message = WaitForMessageAndAck();
  if (new_message.offset) {
    ProcessListenerMessage(new_message);
  }

  // remember the old listener
  auto old_listener_function = ListenerFunction->value();

  // run the kernel!
  Timer dispatch_timer;
  if (MasterUseKernel) {
    call_goal_on_stack(Ptr<Function>(dispatcher_func), goal_stack, s7.offset, g_ee_main_mem);
#ifdef __aarch64__
    // === Gjak2-ingame (arm64): 'Two years later' transition crash tripwire+repair.
    // On arm64 the intro->prison handoff leaves a non-finite/huge position in the
    // live position sources; bigmap set-pos! ftoi-saturates it to INT_MIN and
    // set-enable-from-position! reads layer-mask at a wild index -> SIGSEGV
    // (GAME.CGO map-texture, EE 0x214de84). Repair non-finite/|v|>=2^31 components
    // of the three (target-pos)/(camera-pos) sources at the frame boundary (EE
    // thread, post-dispatch, GOAL quiescent) from a last-finite snapshot, with
    // capped logging so the producer stays attributable. x86 untouched.
    {
      const u32 MX = (u32)(128 * 1024 * 1024 - 64);
      // C++ function-local static init runs exactly once; the symbol table is live
      // at first dispatch and intern_from_c CREATES the symbol if absent, so this
      // cannot fail.
      static Ptr<Symbol4<u32>> s_target = intern_from_c("*target*");
      static Ptr<Symbol4<u32>> s_camcomb = intern_from_c("*camera-combiner*");
      static Ptr<Symbol4<u32>> s_mathcam = intern_from_c("*math-camera*");
      static std::unordered_map<u32, std::array<float, 3>> s_lastgood;
      static int s_log = 0;
      auto repair_vec3 = [&](u32 vec_goal_addr, const char* name) {
        if (vec_goal_addr < 0x1000 || vec_goal_addr >= MX)
          return;
        float* v = reinterpret_cast<float*>(g_ee_main_mem + vec_goal_addr);
        bool bad = false;
        for (int i = 0; i < 3; i++) {
          if (!std::isfinite(v[i]) || std::fabs(v[i]) >= 2147483648.0f) {
            bad = true;
            break;
          }
        }
        if (!bad) {
          s_lastgood[vec_goal_addr] = {v[0], v[1], v[2]};
          return;
        }
        auto it = s_lastgood.find(vec_goal_addr);
        float g0 = 0.f, g1 = 0.f, g2 = 0.f;
        if (it != s_lastgood.end()) {
          g0 = it->second[0];
          g1 = it->second[1];
          g2 = it->second[2];
        }
        if (s_log < 48) {
          fprintf(stderr, "GJ2ING-TRANSNAN #%d %s @0x%x (%g %g %g) -> (%g %g %g)\n", s_log, name,
                  vec_goal_addr, v[0], v[1], v[2], g0, g1, g2);
          s_log++;
        }
        for (int i = 0; i < 3; i++) {
          float gv = (i == 0) ? g0 : ((i == 1) ? g1 : g2);
          if (!std::isfinite(v[i]) || std::fabs(v[i]) >= 2147483648.0f)
            v[i] = gv;
        }
      };
      // 1) *target* -> control(@128, ptr) -> trans(@16, inline vector)
      u32 tv = s_target->value();
      if (tv >= 0x1000 && tv < MX && tv != s7.offset) {
        u32 ctrl = 0;
        memcpy(&ctrl, g_ee_main_mem + tv + 128, 4);
        if (ctrl >= 0x1000 && ctrl < MX)
          repair_vec3(ctrl + 16, "target.control.trans");
      }
      // 2) *camera-combiner* -> trans inline @128
      u32 cc = s_camcomb->value();
      if (cc >= 0x1000 && cc < MX && cc != s7.offset)
        repair_vec3(cc + 128, "camera-combiner.trans");
      // 3) *math-camera* -> trans inline @928
      u32 mc = s_mathcam->value();
      if (mc >= 0x1000 && mc < MX && mc != s7.offset)
        repair_vec3(mc + 928, "math-camera.trans");
    }
#endif
  } else {
    // added, just calls the listener function
    if (ListenerFunction->value() != s7.offset) {
      auto result = call_goal_on_stack(Ptr<Function>(ListenerFunction->value()), goal_stack,
                                       s7.offset, g_ee_main_mem);
#ifdef __linux__
      cprintf("%ld\n", result);
#else
      cprintf("%lld\n", result);
#endif
      ListenerFunction->value() = s7.offset;
    }
  }

  float time_ms = dispatch_timer.getMs();
  if (time_ms > 50) {
    lg::print("Kernel dispatch time: {:.3f} ms\n", time_ms);
  }

  // flush stdout
  ClearPending();

  // now run the extra "kernel function"
  auto bonus_function = KernelFunction->value();
  if (bonus_function != s7.offset) {
    // clear the pending kernel function
    KernelFunction->value() = s7.offset;
    // and run
    call_goal_on_stack(Ptr<Function>(bonus_function), goal_stack, s7.offset, g_ee_main_mem);
  }

  // send ack to indicate that the listener function has been processed and the result printed
  if (MasterDebug && ListenerFunction->value() != old_listener_function) {
    SendAck();
  }

  // prevent crazy spinning if we're not vsyncing (added)
  if (time_ms < 4) {
    std::this_thread::sleep_for(std::chrono::microseconds(1000));
  }
}

void KernelShutdown(u32 reason) {
  MasterExit = (RuntimeExitStatus)reason;
}

void KernelCheckAndDispatch() {
  while (MasterExit == RuntimeExitStatus::RUNNING) {
    KernelDispatch(kernel_dispatcher->value());
  }
}

}  // namespace jak2
