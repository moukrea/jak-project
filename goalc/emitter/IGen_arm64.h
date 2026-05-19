#pragma once

// AArch64 emitter scaffold (Android port phase 01).
//
// The full instruction stubs live in IGenARM64.h / IGenARM64.cpp; this file
// holds the small set of symbols that identify the arm64 backend at link
// time and to the user (--version output). They exist deliberately under the
// snake_case `IGen_arm64` namespace so they are easy to grep for in `nm`
// output produced by the phase-01 validator and any future build-bot.

#include <cstdint>
#include <string>

namespace emitter {
namespace IGen_arm64 {

// Returns the banner string printed by `goalc --version`.
// Always mentions the configured backend so an operator can confirm which
// codegen is wired in without re-reading CMakeCache.
std::string version_string();

// Whether this binary was built with -DGOALC_BACKEND=arm64.
bool backend_is_arm64();

// AArch64 BRK #0 (always-trap) encoding. Every real emitter stub will write
// this 4-byte word as its placeholder body in phase 01.
constexpr uint32_t kBrk0Encoding = 0xD4200000u;

}  // namespace IGen_arm64
}  // namespace emitter
