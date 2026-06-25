// Phase Ginput-replay (autoport): implementation of the host-side input
// record/replay harness. See pad_replay.h for the design rationale.

#include "pad_replay.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#define PR_LOG(...) __android_log_print(ANDROID_LOG_INFO, "GK_STDOUT", __VA_ARGS__)
#else
#define PR_LOG(...)        \
  do {                     \
    printf(__VA_ARGS__);   \
    printf("\n");          \
    fflush(stdout);        \
  } while (0)
#endif

namespace pad_replay {

namespace {

constexpr char kMagic[8] = {'O', 'G', 'P', 'A', 'D', 'R', 'P', '1'};
constexpr uint8_t kNeutral = 127;
// Fixed default seed used for self-test / record runs so a replay reseeds the
// host RNG to a known value. The mt19937 default-construct seed is 5489; we
// pick a distinct constant so it is obvious in a hex dump that the harness owns
// the seed.
constexpr uint32_t kDefaultSeed = 0x0AD12345u;

// 64-byte demo header. Captures everything a replay needs to reconstruct the
// deterministic start state (frame 0). fingerprint[] is reserved for the crash
// phases to stash the continue-point + Jak's spawn position; it does not affect
// the self-test.
#pragma pack(push, 1)
struct Header {
  char magic[8];          // "OGPADRP1"
  uint32_t version;       // 1
  uint32_t record_size;   // sizeof(PadRecord) == 6
  uint32_t seed;          // rng seed for deterministic replay
  uint32_t reserved0;
  uint64_t start_frame;   // kernel frame counter at frame 0 (first input)
  uint8_t fingerprint[32];
};
#pragma pack(pop)
static_assert(sizeof(Header) == 64, "Header must be 64 bytes");

struct State {
  Mode mode = Mode::Off;
  std::string path;
  FILE* f = nullptr;          // record: append handle
  uint64_t tick = 0;          // logic-tick index (controller-0 reads)
  bool header_done = false;   // record: header written at first input?
  uint32_t seed = kDefaultSeed;
  uint64_t start_frame = 0;
  void (*seed_fn)(uint32_t) = nullptr;
  bool seeded = false;        // replay: reseed performed?
  std::vector<PadRecord> records;  // replay: full demo
  FILE* trace = nullptr;      // state-trace handle
};

State g;

bool is_neutral(const PadRecord& r) {
  return r.button0 == 0 && r.leftx == kNeutral && r.lefty == kNeutral &&
         r.rightx == kNeutral && r.righty == kNeutral;
}

void write_header() {
  Header h;
  std::memset(&h, 0, sizeof(h));
  std::memcpy(h.magic, kMagic, sizeof(kMagic));
  h.version = 1;
  h.record_size = sizeof(PadRecord);
  h.seed = g.seed;
  h.start_frame = g.start_frame;
  std::fwrite(&h, sizeof(h), 1, g.f);
  std::fflush(g.f);
}

}  // namespace

void set_rng_seed_callback(void (*fn)(uint32_t)) {
  g.seed_fn = fn;
}

void init(Mode mode, const std::string& path) {
  shutdown();  // clean any prior session
  g.mode = mode;
  g.path = path;
  g.tick = 0;
  g.header_done = false;
  g.seeded = false;
  g.seed = kDefaultSeed;
  g.start_frame = 0;
  g.records.clear();

  if (mode == Mode::Record) {
    g.f = std::fopen(path.c_str(), "wb");
    if (!g.f) {
      PR_LOG("pad_replay: RECORD open failed: %s", path.c_str());
      g.mode = Mode::Off;
      return;
    }
    PR_LOG("pad_replay: RECORD -> %s (per-logic-tick, flush-per-tick, "
           "idle-until-first-input)",
           path.c_str());
  } else if (mode == Mode::Replay) {
    FILE* in = std::fopen(path.c_str(), "rb");
    if (!in) {
      PR_LOG("pad_replay: REPLAY open failed: %s", path.c_str());
      g.mode = Mode::Off;
      return;
    }
    Header h;
    if (std::fread(&h, sizeof(h), 1, in) != 1 ||
        std::memcmp(h.magic, kMagic, sizeof(kMagic)) != 0 ||
        h.record_size != sizeof(PadRecord)) {
      PR_LOG("pad_replay: REPLAY bad/short header: %s", path.c_str());
      std::fclose(in);
      g.mode = Mode::Off;
      return;
    }
    g.seed = h.seed;
    g.start_frame = h.start_frame;
    PadRecord r;
    while (std::fread(&r, sizeof(r), 1, in) == 1) {
      g.records.push_back(r);
    }
    std::fclose(in);
    PR_LOG("pad_replay: REPLAY <- %s (%zu logic ticks, seed=0x%08x)",
           path.c_str(), g.records.size(), g.seed);
  }
}

void init_from_env() {
  const char* rec = std::getenv("OG_PAD_REPLAY_RECORD");
  const char* rep = std::getenv("OG_PAD_REPLAY_REPLAY");
  if (rep && rep[0]) {
    init(Mode::Replay, rep);
  } else if (rec && rec[0]) {
    init(Mode::Record, rec);
  }
}

void shutdown() {
  if (g.f) {
    std::fflush(g.f);
    std::fclose(g.f);
    g.f = nullptr;
  }
  close_state_trace();
  g.mode = Mode::Off;
  g.tick = 0;
  g.header_done = false;
  g.seeded = false;
  g.records.clear();
}

bool active() {
  return g.mode != Mode::Off;
}
Mode mode() {
  return g.mode;
}
uint64_t current_tick() {
  return g.tick;
}
uint32_t replay_seed() {
  return g.seed;
}

void on_cpad_read(int controller_number,
                  uint16_t* button0,
                  uint8_t* leftx,
                  uint8_t* lefty,
                  uint8_t* rightx,
                  uint8_t* righty) {
  if (g.mode == Mode::Off) {
    return;
  }
  // Only controller 0 anchors the logic tick. The game polls 4 pads per frame;
  // recording all of them would multiply the tick index by 4 and desync replay.
  if (controller_number != 0) {
    return;
  }

  if (g.mode == Mode::Record) {
    if (!g.f) {
      return;
    }
    PadRecord rec{*button0, *leftx, *lefty, *rightx, *righty};
    if (!g.header_done) {
      // Idle-until-first-input: do not start the demo (and do not advance the
      // logic tick) until the first non-neutral pad state. Frame 0 of the demo
      // is the first real input.
      if (is_neutral(rec)) {
        return;
      }
      write_header();
      g.header_done = true;
    }
    std::fwrite(&rec, sizeof(rec), 1, g.f);
    std::fflush(g.f);  // flush-per-tick: a crash at tick K still has 0..K
    g.tick++;
  } else if (g.mode == Mode::Replay) {
    if (!g.seeded) {
      if (g.seed_fn) {
        g.seed_fn(g.seed);  // deterministic start state
      }
      g.seeded = true;
    }
    if (g.tick < g.records.size()) {
      const PadRecord& rec = g.records[g.tick];
      *button0 = rec.button0;
      *leftx = rec.leftx;
      *lefty = rec.lefty;
      *rightx = rec.rightx;
      *righty = rec.righty;
    }
    // Past the end of the demo we leave the live input untouched (the crash the
    // demo reproduces is expected to have already fired).
    g.tick++;
  }
}

void open_state_trace(const std::string& path) {
  close_state_trace();
  g.trace = std::fopen(path.c_str(), "wb");
}

void dump_state(const char* label, const void* data, size_t len) {
  if (!g.trace) {
    return;
  }
  // State-anchored line: keyed by the logic tick, NOT a render frame.
  std::fprintf(g.trace, "%s tick=%llu", label,
               (unsigned long long)g.tick);
  const uint8_t* p = static_cast<const uint8_t*>(data);
  for (size_t i = 0; i < len; ++i) {
    std::fprintf(g.trace, " %02x", p[i]);
  }
  std::fputc('\n', g.trace);
  std::fflush(g.trace);
}

void close_state_trace() {
  if (g.trace) {
    std::fclose(g.trace);
    g.trace = nullptr;
  }
}

namespace {
// Deterministic, varied scripted input as a function of the logic tick. Touches
// every button bit over 16 ticks and ramps all four analog axes, so the demo is
// genuinely non-trivial (not a constant hold).
PadRecord scripted(int t) {
  PadRecord r;
  r.button0 = (uint16_t)(((1u << (t % 16)) | ((uint32_t)(t * 37u) & 0x55AAu)));
  r.leftx = (uint8_t)((t * 7u) & 0xFFu);
  r.lefty = (uint8_t)(255u - ((t * 5u) & 0xFFu));
  r.rightx = (uint8_t)((t * 11u + 3u) & 0xFFu);
  r.righty = (uint8_t)((t * 13u + 9u) & 0xFFu);
  return r;
}
}  // namespace

int run_selftest(const std::string& out_path, int n_ticks) {
  if (n_ticks < 1) {
    n_ticks = 120;
  }
  PR_LOG("pad_replay: SELFTEST begin (%d logic ticks) -> %s", n_ticks,
         out_path.c_str());

  // ---- RECORD through the real tap ------------------------------------------
  init(Mode::Record, out_path);
  if (g.mode != Mode::Record) {
    PR_LOG("pad_replay: SELFTEST FAILED — could not open demo for record");
    return 1;
  }
  // Idle-until-first-input: 3 leading NEUTRAL ticks that MUST be skipped (they
  // must NOT advance the logic tick or land in the demo).
  for (int k = 0; k < 3; ++k) {
    uint16_t b = 0;
    uint8_t lx = kNeutral, ly = kNeutral, rx = kNeutral, ry = kNeutral;
    on_cpad_read(0, &b, &lx, &ly, &rx, &ry);
  }
  bool idle_ok = (current_tick() == 0);
  std::vector<PadRecord> recorded(n_ticks);
  for (int t = 0; t < n_ticks; ++t) {
    PadRecord s = scripted(t);
    uint16_t b = s.button0;
    uint8_t lx = s.leftx, ly = s.lefty, rx = s.rightx, ry = s.righty;
    on_cpad_read(0, &b, &lx, &ly, &rx, &ry);  // record observes & writes
    recorded[t] = PadRecord{b, lx, ly, rx, ry};
  }
  uint64_t recorded_ticks = current_tick();
  shutdown();

  // On-disk size check: header + exactly n_ticks records (no truncation, no
  // stray idle ticks).
  long expect = (long)sizeof(Header) + (long)n_ticks * (long)sizeof(PadRecord);
  long actual = -1;
  if (FILE* fz = std::fopen(out_path.c_str(), "rb")) {
    std::fseek(fz, 0, SEEK_END);
    actual = std::ftell(fz);
    std::fclose(fz);
  }

  // ---- REPLAY #1 through the real tap; dump per-logic-tick state ------------
  init(Mode::Replay, out_path);
  open_state_trace(out_path + ".statedump.txt");
  std::vector<PadRecord> replay1(n_ticks);
  for (int t = 0; t < n_ticks; ++t) {
    uint16_t b = 0;  // neutral "live" input — replay must override it
    uint8_t lx = kNeutral, ly = kNeutral, rx = kNeutral, ry = kNeutral;
    on_cpad_read(0, &b, &lx, &ly, &rx, &ry);
    replay1[t] = PadRecord{b, lx, ly, rx, ry};
    dump_state("pad", &replay1[t], sizeof(PadRecord));
  }
  close_state_trace();
  shutdown();

  // ---- REPLAY #2 (determinism) ----------------------------------------------
  init(Mode::Replay, out_path);
  std::vector<PadRecord> replay2(n_ticks);
  for (int t = 0; t < n_ticks; ++t) {
    uint16_t b = 0;
    uint8_t lx = kNeutral, ly = kNeutral, rx = kNeutral, ry = kNeutral;
    on_cpad_read(0, &b, &lx, &ly, &rx, &ry);
    replay2[t] = PadRecord{b, lx, ly, rx, ry};
  }
  shutdown();

  // ---- compare --------------------------------------------------------------
  int pad_diff = 0;       // fidelity: replay applied != recorded
  int first_div = -1;     // first divergent logic tick
  for (int t = 0; t < n_ticks; ++t) {
    if (std::memcmp(&recorded[t], &replay1[t], sizeof(PadRecord)) != 0) {
      pad_diff++;
      if (first_div < 0) {
        first_div = t;
      }
    }
  }
  int det_diff = 0;       // determinism: replay#1 != replay#2
  for (int t = 0; t < n_ticks; ++t) {
    if (std::memcmp(&replay1[t], &replay2[t], sizeof(PadRecord)) != 0) {
      det_diff++;
    }
  }

  PR_LOG("pad_replay: idle-until-first-input: 3 neutral ticks skipped, "
         "frame 0 = first input (%s)",
         idle_ok ? "OK" : "FAIL");
  PR_LOG("pad_replay: demo size %ld bytes (expected %ld: 64B header + %d*6)",
         actual, expect, n_ticks);
  PR_LOG("PAD DIFF: %d/%d", pad_diff, n_ticks);
  PR_LOG("DETERMINISM: 2 replays differ at %d/%d logic ticks (bit-identical "
         "state dumps expected)",
         det_diff, n_ticks);
  if (first_div < 0) {
    PR_LOG("FIRST DIVERGENCE: none — all %d logic ticks bit-identical "
           "(record == replay)",
           n_ticks);
  } else {
    PR_LOG("FIRST DIVERGENCE: logic tick %d (field-level localizer)", first_div);
  }

  bool pass = (pad_diff == 0) && (det_diff == 0) && idle_ok &&
              ((uint64_t)n_ticks == recorded_ticks) && (actual == expect);
  PR_LOG("pad_replay: SELFTEST %s", pass ? "PASS" : "FAIL");
  return pass ? 0 : 1;
}

}  // namespace pad_replay
