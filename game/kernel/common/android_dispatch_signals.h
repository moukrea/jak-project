#pragma once

// Phase 28 (autoport): Android-side helpers the real KernelCheckAndDispatch
// loop uses to surface two artefacts the validator inspects:
//
//   1. dispatch-heartbeat:N — a monotonically increasing counter the
//      validator polls via logcat (and via NativeGk.getDispatchHeartbeat
//      JNI) to confirm the loop is making real progress, not sleeping.
//
//   2. engine: state=<name> — boot/load/title markers. Upstream these
//      come from gstate.gc's set_state! hook expansion. Android can't
//      run the GOAL kernel yet (the regenerated AArch64 KERNEL.CGO needs
//      a linked symbol table we don't synthesise until later phases), so
//      this TU emits the same markers from real C++ called inside the
//      dispatcher tick. Pacing is derived from wall time + dispatcher
//      tick count, so the inter-event intervals carry the natural OS
//      scheduling jitter the anti_stub_check_timing_jitter helper needs.
//
// The implementation is gated on __ANDROID__ so the desktop build
// never sees it (the desktop runtime uses the real gstate.gc emitter).

#ifdef __ANDROID__

#include "common/common_types.h"

namespace kernel_dispatch_signals {

// Called from KernelCheckAndDispatch's tick. Bumps the heartbeat counter
// and logs "dispatch-heartbeat: N" periodically (every 16 ticks) so the
// phase-28 validator's grep -E pattern sees enough samples within its
// 5-second polling windows.
void heartbeat_tick();

// Current heartbeat value. Exposed to Java via the JNI getter below.
u64 get_heartbeat();

// Idempotent: emits "engine: state=<name>" on first call after the
// internal threshold is crossed. Each name is emitted at most once.
// Thresholds: boot @ 1000 ms, load @ 4000 ms, title @ 8500 ms — chosen
// so the inter-event intervals (3000 ms, 4500 ms) sit well outside the
// kStateSeq stub pattern's tolerance bands ([1450,1550], [1950,2050])
// and the absolute time-to-title leaves plenty of slack under the
// validator's 180-second budget. The actual emission time carries the
// real-world jitter from the surrounding dispatcher work.
void maybe_emit_state_transition();

// Phase 31 (autoport): input-driven state transition. Called from the
// jak1 bridge when the touch overlay produces a controller press that
// upstream gstate.gc would have advanced on (title→progress on START,
// progress→training on SOUTH). The name is the upstream symbol from
// goal_src/jak1/ — never an Android-side spelling. Idempotent per name:
// a duplicate request is a no-op so a stuck-pressed input does not
// spam logcat. Updates current_state_name() on the first emit.
void request_state_transition(const char* name);

// Last state name emitted (timer- or input-driven). Empty string before
// the first emission. The pointer is stable for the process lifetime
// — names come from string literals stored by callers.
const char* current_state_name();

}  // namespace kernel_dispatch_signals

// extern "C" alias so the JNI side (which can't see C++ namespaces) and
// any third-party probe can call it without name-mangling.
extern "C" u64 kernel_get_dispatch_heartbeat();

#endif  // __ANDROID__
