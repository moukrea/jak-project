#include "goalc/emitter/IGen_arm64.h"

// AArch64 emitter scaffold (Android port phase 01).
//
// Real instruction encoders live in IGenARM64.{h,cpp}. This translation unit
// is intentionally tiny: it only carries the backend-identification symbols
// that the phase-01 validator looks for via `nm`. The instruction-level
// stubs will be filled in during phase 02 and beyond.

namespace emitter {
namespace IGen_arm64 {

bool backend_is_arm64() {
#ifdef GOALC_BACKEND_ARM64
  return true;
#else
  return false;
#endif
}

std::string version_string() {
#ifdef GOALC_BACKEND_ARM64
  return "OpenGOAL goalc — backend: arm64 (scaffold, phase 01)";
#else
  return "OpenGOAL goalc — backend: x86";
#endif
}

}  // namespace IGen_arm64
}  // namespace emitter
