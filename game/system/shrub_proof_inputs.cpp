#include "game/system/shrub_proof_inputs.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <map>
#include <tuple>

#include "game/system/autoport_proof.h"
#include "game/system/pad_replay.h"
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace shrub_proof_inputs {
namespace {
std::string setting(const char* env, const char* prop) {
#ifdef __ANDROID__
  char buf[PROP_VALUE_MAX] = {};
  __system_property_get(prop, buf);
  return buf;
#else
  (void)prop;
  const char* p = std::getenv(env);
  return p ? p : "";
#endif
}
[[noreturn]] void fail(const char* why) {
  autoport_proof::publish("shrub_input_tape_errors", 1);
  std::fprintf(stderr, "[shrub-input-tape] %s\n", why);
  autoport_proof::flush();
  std::abort();
}
struct Tape {
  std::mutex mutex;
  FILE* file = nullptr;
  bool replay = false;
  uint64_t sequence = 0;
  uint64_t preanchor = 0;
  using Key = std::tuple<int64_t, std::string, uint64_t>;
  std::map<Key, std::vector<unsigned char>> records;
  std::map<std::pair<int64_t, std::string>, uint64_t> ordinals;
  Tape() {
    if (!autoport_proof::feature_is("shrub-trunk-contact")) return;
    const auto mode = setting("AUTOPORT_SHRUB_INPUT_MODE", "debug.opengoal.shrub.inputs_mode");
    if (mode.empty()) return;
    if (mode != "record" && mode != "replay") fail("mode must be record or replay");
    replay = mode == "replay";
    const auto path = setting("AUTOPORT_SHRUB_INPUT_PATH", "debug.opengoal.shrub.inputs_path");
    if (path.empty()) fail("explicit tape path required");
    file = std::fopen(path.c_str(), replay ? "rb" : "wbx");
    if (!file) fail("cannot open tape (record requires new file)");
    char magic[8] = {'S','H','R','I','N','P','0','2'};
    if (replay) {
      char got[8];
      if (std::fread(got, 1, 8, file) != 8 || std::memcmp(got, magic, 8)) fail("bad tape header");
      size_t total = 0;
      while (true) {
        int64_t frame; uint64_t key, bytes; uint32_t names;
        const size_t n = std::fread(&frame, 1, sizeof(frame), file);
        if (!n && std::feof(file)) break;
        if (n != sizeof(frame) || std::fread(&key, 1, 8, file) != 8 ||
            std::fread(&names, 1, 4, file) != 4 || std::fread(&bytes, 1, 8, file) != 8)
          fail("truncated event header");
        if (names > 4096 || bytes > 16 * 1024 * 1024 || total + bytes > 512 * 1024 * 1024)
          fail("tape size bound exceeded");
        std::string name(names, '\0'); std::vector<unsigned char> payload(bytes);
        if (std::fread(name.data(), 1, names, file) != names ||
            std::fread(payload.data(), 1, bytes, file) != bytes) fail("truncated event payload");
        if (!records.emplace(Key{frame, name, key}, std::move(payload)).second)
          fail("duplicate tape key");
        total += bytes;
      }
    } else if (std::fwrite(magic, 1, 8, file) != 8) fail("header write failed");
  }
  ~Tape() { if (file) std::fclose(file); }
};
Tape& tape() { static Tape t; return t; }
}  // namespace
bool enabled() { return tape().file != nullptr; }
[[noreturn]] void invalid_input(const char* reason) { fail(reason); }
namespace {
void exchange_impl(const char* channel, uint64_t logical_key, bool explicit_key,
                   void* data, size_t bytes) {
  auto& t = tape();
  if (!t.file) return;
  std::lock_guard<std::mutex> lock(t.mutex);
  // Explicit source keys (e.g. wind-time) are independent of rendered-frame counts.
  // Ordinary events retain the full pre-anchor history with per-channel ordinals.
  const int64_t observed_frame = pad_replay::current_frame();
  int64_t frame = explicit_key ? INT64_MIN : observed_frame;
  uint64_t key = explicit_key ? logical_key : t.ordinals[{frame, channel}]++;
  const Tape::Key identity{frame, channel, key};
  const auto found = t.records.find(identity);
  if (t.replay) {
    if (found == t.records.end() || found->second.size() != bytes)
      fail("missing frame/channel/source key or payload size mismatch");
    if (bytes) std::memcpy(data, found->second.data(), bytes);
  } else if (found != t.records.end()) {
    if (found->second.size() != bytes || (bytes && std::memcmp(found->second.data(), data, bytes)))
      fail("source key reused with different exogenous bytes");
  } else {
    uint32_t names = std::strlen(channel); uint64_t length = bytes;
    auto write = [&](const void* p, size_t n) {
      if (std::fwrite(p, 1, n, t.file) != n) fail("input write failed");
    };
    write(&frame, 8); write(&key, 8); write(&names, 4); write(&length, 8);
    write(channel, names); write(data, bytes);
    std::vector<unsigned char> payload(bytes);
    if (bytes) std::memcpy(payload.data(), data, bytes);
    t.records.emplace(identity, std::move(payload));
    if (std::fflush(t.file)) fail("input flush failed");
  }
  ++t.sequence;
  if (observed_frame < 0) ++t.preanchor;
  if ((t.sequence & 255) == 1) {
    autoport_proof::publish("shrub_input_tape_events", t.sequence);
    autoport_proof::publish("shrub_input_tape_preanchor_events", t.preanchor);
    autoport_proof::publish("shrub_input_tape_errors", 0);
  }
}
// Do not silently accept a shorter pre-anchor accumulator history in a replay.
// Counts describe consumed inputs only; no derived simulation state is serialized.
void check_preanchor_history() {
  auto& t = tape();
  static bool checked = false;
  if (!t.file || checked || pad_replay::current_frame() < 0) return;
  checked = true;
  std::string counts;
  for (const auto& entry : t.ordinals) if (entry.first.first < 0) {
    counts += entry.first.second + "=" + std::to_string(entry.second) + "\n";
  }
  const std::string actual = counts;
  exchange_impl("preanchor/consumed-channel-counts", 0, true, counts.data(), counts.size());
  if (counts != actual) fail("pre-anchor input history cardinality differs");
}
}  // namespace
void exchange(const char* channel, void* data, size_t bytes) {
  check_preanchor_history();
  exchange_impl(channel, 0, false, data, bytes);
}
void exchange_key(const char* channel, uint64_t key, void* data, size_t bytes) {
  check_preanchor_history();
  exchange_impl(channel, key, true, data, bytes);
}
}  // namespace shrub_proof_inputs
