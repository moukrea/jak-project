#include "touch_screen.h"

#include <atomic>

namespace touch_screen {
namespace {
std::atomic<bool> g_present{false};
std::atomic<int> g_source{kNone};
std::atomic<int> g_input_devices{-1};
}  // namespace

void set_present(bool present, Source source, int input_devices) {
  g_input_devices.store(input_devices, std::memory_order_relaxed);
  g_present.store(present, std::memory_order_relaxed);
  // La source en DERNIER : un lecteur qui voit une source posee voit aussi le fait.
  g_source.store((int)source, std::memory_order_release);
}

bool present() {
  return g_present.load(std::memory_order_acquire);
}

Source source() {
  return (Source)g_source.load(std::memory_order_acquire);
}

const char* source_name() {
  switch (source()) {
    case kAndroidPackageManager:
      return "android_package_manager";
    case kSdl:
      return "sdl";
    default:
      return "aucune";
  }
}

int input_devices() {
  return g_input_devices.load(std::memory_order_relaxed);
}

}  // namespace touch_screen
