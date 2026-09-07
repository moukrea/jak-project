#pragma once

#include <cstddef>
#include <cstdint>

// Single GOAL thread only. Replays explicitly supplied bootstrap inputs, not a
// snapshot of actors or game state. Payloads are opaque: callers must provide
// the same byte representation on both hosts (no pointers or native padding).
// Lazy initialization selects OG_BOOT_REPLAY_CAPTURE (exclusive new file) or
// OG_BOOT_REPLAY_REPLAY (existing file). Neither variable means no-op calls.
// Tags: 1..63 bytes; payloads: 0..16384 bytes; at most 65536 records.
// Active input/checkpoint/finish calls after finish terminate with failure.
namespace boot_replay {
bool enabled();
bool active();
void input(const char* tag, void* bytes, size_t size);
void checkpoint(const char* tag, const void* bytes, size_t size);
void finish();
// Passive receipt: true only after successful completion of a replay stream.
bool replay_verified();
// Zero until finish has verified the complete stream and closed it successfully.
uint64_t fingerprint();
uint64_t records();
}  // namespace boot_replay
