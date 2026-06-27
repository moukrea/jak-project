// Phase Ginput-replay / Ginput-replay-determinism (autoport): implementation of
// the host-side input record/replay harness. See pad_replay.h for the design.

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
// Fixed seed forced into every RNG stream at the gameplay anchor. A replay forces
// the SAME value at its own anchor, so the gameplay simulation is bit-identical
// from the anchor onward regardless of the (variable) boot/load RNG consumption.
constexpr uint32_t kDefaultSeed = 0x0AD12345u;

// 64-byte demo header. version 2 = game-logic-frame-anchored format.
#pragma pack(push, 1)
struct Header {
  char magic[8];         // "OGPADRP1"
  uint32_t version;      // 2 (anchored, logic-frame indexed)
  uint32_t record_size;  // sizeof(PadRecord) == 6
  uint32_t seed;         // rng seed forced at the anchor
  uint32_t reserved0;
  int64_t anchor_frame;  // record run's anchor logic frame (informational)
  uint8_t fingerprint[32];
};
#pragma pack(pop)
static_assert(sizeof(Header) == 64, "Header must be 64 bytes");

struct State {
  Mode mode = Mode::Off;
  std::string path;
  FILE* f = nullptr;  // record: append handle
  uint32_t seed = kDefaultSeed;

  // ── determinism providers / rng reseed ──
  int64_t (*logic_frame_fn)() = nullptr;
  bool (*anchor_fn)() = nullptr;
  void (*timestep_fn)() = nullptr;
  void (*state_dump_fn)() = nullptr;
  void (*reseed_fns[8])(uint32_t) = {};
  int n_reseed = 0;

  // ── deterministic (anchored) state ──
  bool anchored = false;
  int64_t anchor_frame = 0;
  int64_t records_written = 0;  // record: next idx not yet written to disk
  int64_t cur_frame = -1;       // logic frame since anchor for the current read
  int64_t last_dump_frame = -1; // last logic frame the state dump fired on

  // ── legacy / self-test state (no providers registered) ──
  uint64_t read_count = 0;     // controller-read counter
  uint64_t legacy_tick = 0;    // legacy logic-tick (post idle-skip)
  bool header_done = false;    // record: header written?
  bool legacy_seeded = false;  // replay: legacy one-shot reseed done?

  std::vector<PadRecord> records;  // replay: full demo
  FILE* trace = nullptr;           // state-trace handle
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
  h.version = 2;
  h.record_size = sizeof(PadRecord);
  h.seed = g.seed;
  h.anchor_frame = g.anchor_frame;
  std::fwrite(&h, sizeof(h), 1, g.f);
  std::fflush(g.f);
}

bool have_providers() {
  return g.logic_frame_fn != nullptr || g.anchor_fn != nullptr;
}

void fire_reseed() {
  for (int i = 0; i < g.n_reseed; ++i) {
    if (g.reseed_fns[i]) {
      g.reseed_fns[i](g.seed);
    }
  }
}

// ── legacy controller-read path (run_selftest, no providers) ────────────────────
void legacy_on_cpad_read(uint16_t* button0, uint8_t* leftx, uint8_t* lefty,
                         uint8_t* rightx, uint8_t* righty) {
  if (g.mode == Mode::Record) {
    if (!g.f) {
      return;
    }
    PadRecord rec{*button0, *leftx, *lefty, *rightx, *righty};
    if (!g.header_done) {
      if (is_neutral(rec)) {  // idle-until-first-input
        return;
      }
      g.anchor_frame = 0;
      write_header();
      g.header_done = true;
    }
    std::fwrite(&rec, sizeof(rec), 1, g.f);
    std::fflush(g.f);
    g.cur_frame = (int64_t)g.legacy_tick;
    g.legacy_tick++;
  } else if (g.mode == Mode::Replay) {
    if (!g.legacy_seeded) {
      fire_reseed();
      g.legacy_seeded = true;
    }
    if (g.legacy_tick < g.records.size()) {
      const PadRecord& rec = g.records[g.legacy_tick];
      *button0 = rec.button0;
      *leftx = rec.leftx;
      *lefty = rec.lefty;
      *rightx = rec.rightx;
      *righty = rec.righty;
    }
    g.cur_frame = (int64_t)g.legacy_tick;
    g.legacy_tick++;
  }
}

}  // namespace

void set_logic_frame_provider(int64_t (*fn)()) {
  g.logic_frame_fn = fn;
}
void set_anchor_provider(bool (*fn)()) {
  g.anchor_fn = fn;
}
void add_rng_reseed_callback(void (*fn)(uint32_t)) {
  if (g.n_reseed < (int)(sizeof(g.reseed_fns) / sizeof(g.reseed_fns[0]))) {
    g.reseed_fns[g.n_reseed++] = fn;
  }
}
void set_timestep_force_callback(void (*fn)()) {
  g.timestep_fn = fn;
}
void set_state_dump_callback(void (*fn)()) {
  g.state_dump_fn = fn;
}

void init(Mode mode, const std::string& path) {
  // Preserve registered providers/reseed callbacks across init (they are wired
  // once at machine init, before the harness is armed).
  auto lf = g.logic_frame_fn;
  auto af = g.anchor_fn;
  auto tf = g.timestep_fn;
  decltype(g.reseed_fns) rs;
  std::memcpy(rs, g.reseed_fns, sizeof(rs));
  int nrs = g.n_reseed;

  shutdown();
  g.logic_frame_fn = lf;
  g.anchor_fn = af;
  g.timestep_fn = tf;
  std::memcpy(g.reseed_fns, rs, sizeof(rs));
  g.n_reseed = nrs;

  g.mode = mode;
  g.path = path;
  g.seed = kDefaultSeed;
  g.anchored = false;
  g.anchor_frame = 0;
  g.records_written = 0;
  g.cur_frame = -1;
  g.last_dump_frame = -1;
  g.read_count = 0;
  g.legacy_tick = 0;
  g.header_done = false;
  g.legacy_seeded = false;
  g.records.clear();

  if (mode == Mode::Record) {
    g.f = std::fopen(path.c_str(), "wb");
    if (!g.f) {
      PR_LOG("pad_replay: RECORD open failed: %s", path.c_str());
      g.mode = Mode::Off;
      return;
    }
    PR_LOG("pad_replay: RECORD -> %s (logic-frame anchored, providers=%s)",
           path.c_str(), have_providers() ? "yes" : "no(legacy)");
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
    g.anchor_frame = h.anchor_frame;  // informational; replay uses its own anchor
    PadRecord r;
    while (std::fread(&r, sizeof(r), 1, in) == 1) {
      g.records.push_back(r);
    }
    std::fclose(in);
    PR_LOG("pad_replay: REPLAY <- %s (v%u, %zu logic frames, seed=0x%08x, providers=%s)",
           path.c_str(), h.version, g.records.size(), g.seed,
           have_providers() ? "yes" : "no(legacy)");
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
  // Optional per-logic-frame state trace (collision diff instrumentation).
  const char* tr = std::getenv("OG_PAD_REPLAY_TRACE");
  if (tr && tr[0]) {
    open_state_trace(tr);
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
  g.anchored = false;
  g.anchor_frame = 0;
  g.records_written = 0;
  g.cur_frame = -1;
  g.last_dump_frame = -1;
  g.read_count = 0;
  g.legacy_tick = 0;
  g.header_done = false;
  g.legacy_seeded = false;
  g.records.clear();
}

bool active() {
  return g.mode != Mode::Off;
}
Mode mode() {
  return g.mode;
}
uint64_t current_tick() {
  return g.read_count;
}
int64_t current_frame() {
  return g.cur_frame;
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
  // Only controller 0 anchors the harness. The game polls 4 pads per frame.
  if (controller_number != 0) {
    return;
  }

  // Force a fixed game-logic timestep while armed (record AND replay), so the
  // simulation advances by exactly one 1/60s step per frame regardless of real
  // frame pacing — the prerequisite for a bit-deterministic clip.
  if (g.timestep_fn) {
    g.timestep_fn();
  }

  // Legacy controller-read path (self-test / no game runtime).
  if (!have_providers()) {
    legacy_on_cpad_read(button0, leftx, lefty, rightx, righty);
    return;
  }

  // ── deterministic, game-logic-frame-anchored path ──
  if (!g.anchored) {
    bool at_anchor = g.anchor_fn ? g.anchor_fn() : true;
    if (!at_anchor) {
      // Pre-anchor: boot / title / level-load. Leave the live input untouched
      // (a deterministic boot — e.g. the OG_F1_WARP warp — drives this), record
      // nothing, and do not advance the index. The variable boot/load frame
      // count is thereby fully absorbed.
      g.cur_frame = -1;
      g.read_count++;
      return;
    }
    g.anchored = true;
    g.anchor_frame = g.logic_frame_fn ? g.logic_frame_fn() : 0;
    // Force EVERY RNG stream to the demo seed at the anchor — record and replay
    // alike — so the gameplay simulation is bit-deterministic from here.
    fire_reseed();
    if (g.mode == Mode::Record && !g.header_done) {
      write_header();
      g.header_done = true;
    }
    PR_LOG("pad_replay: ANCHOR reached at logic frame %lld (%s); rng forced to 0x%08x",
           (long long)g.anchor_frame, g.mode == Mode::Record ? "record" : "replay", g.seed);
  }

  int64_t lf = g.logic_frame_fn ? g.logic_frame_fn() : (int64_t)g.read_count;
  int64_t idx = lf - g.anchor_frame;
  if (idx < 0) {
    idx = 0;  // logic frame ran backwards (should not happen) — clamp
  }
  g.cur_frame = idx;

  if (g.mode == Mode::Record) {
    if (!g.f) {
      g.read_count++;
      return;
    }
    PadRecord rec{*button0, *leftx, *lefty, *rightx, *righty};
    if (idx >= g.records_written) {
      // Dense, idx-keyed append. A clean (unpaused, ≥46fps) gameplay frame
      // advances the logic frame by exactly 1, so idx == records_written and we
      // append one record. If the logic frame ever skips (it should not during
      // gameplay), fill the gap with neutral so file position == idx.
      PadRecord neutral{0, kNeutral, kNeutral, kNeutral, kNeutral};
      while (g.records_written < idx) {
        std::fwrite(&neutral, sizeof(neutral), 1, g.f);
        g.records_written++;
      }
      std::fwrite(&rec, sizeof(rec), 1, g.f);
      std::fflush(g.f);  // flush-per-frame: a crash at frame K still has 0..K
      g.records_written = idx + 1;
    }
    // idx < records_written: the logic frame did not advance (paused frame read
    // twice) — already recorded; leave the (drive-applied) input as-is.
  } else {  // Replay
    if (idx >= 0 && (size_t)idx < g.records.size()) {
      const PadRecord& rec = g.records[(size_t)idx];
      *button0 = rec.button0;
      *leftx = rec.leftx;
      *lefty = rec.lefty;
      *rightx = rec.rightx;
      *righty = rec.righty;
    }
    // Past the end of the demo: leave the live input untouched.
  }
  g.read_count++;

  // Per-logic-frame collision-state dump (Gcollision-replay-diff instrumentation).
  // Fires once per NEW logic frame, post-anchor, only when a trace file is open. The
  // jak1 runtime's registered callback reads *target*'s collide-shape-moving fields
  // and writes them via dump_state, keyed by g.cur_frame — identical on x86 and the
  // arm64 device, so the two traces diff byte-for-byte at matching logic frames.
  if (g.trace && g.anchored && g.state_dump_fn && g.cur_frame >= 0 &&
      g.cur_frame != g.last_dump_frame) {
    g.last_dump_frame = g.cur_frame;
    g.state_dump_fn();
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
  // Only dump comparable gameplay frames (skip pre-anchor boot/load frames).
  if (g.cur_frame < 0) {
    return;
  }
  // Keyed by the logic frame since the anchor (NOT a render frame).
  std::fprintf(g.trace, "%s frame=%lld", label, (long long)g.cur_frame);
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

bool trace_active() {
  return g.trace != nullptr;
}

namespace {
// Deterministic, varied scripted input as a function of the logic tick. Touches
// every button bit over 16 ticks and ramps all four analog axes.
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
  // The self-test drives the tap directly with NO game engine and NO providers,
  // so it exercises the legacy controller-read path (pad-byte round-trip only).
  // It is NOT a real-gameplay determinism test — that is proven in-engine.
  auto saved_lf = g.logic_frame_fn;
  auto saved_af = g.anchor_fn;
  g.logic_frame_fn = nullptr;
  g.anchor_fn = nullptr;

  PR_LOG("pad_replay: SELFTEST begin (%d logic ticks) -> %s", n_ticks, out_path.c_str());

  // ---- RECORD through the real tap ------------------------------------------
  init(Mode::Record, out_path);
  if (g.mode != Mode::Record) {
    PR_LOG("pad_replay: SELFTEST FAILED — could not open demo for record");
    g.logic_frame_fn = saved_lf;
    g.anchor_fn = saved_af;
    return 1;
  }
  for (int k = 0; k < 3; ++k) {  // 3 leading NEUTRAL ticks must be skipped
    uint16_t b = 0;
    uint8_t lx = kNeutral, ly = kNeutral, rx = kNeutral, ry = kNeutral;
    on_cpad_read(0, &b, &lx, &ly, &rx, &ry);
  }
  bool idle_ok = (g.legacy_tick == 0);
  std::vector<PadRecord> recorded(n_ticks);
  for (int t = 0; t < n_ticks; ++t) {
    PadRecord s = scripted(t);
    uint16_t b = s.button0;
    uint8_t lx = s.leftx, ly = s.lefty, rx = s.rightx, ry = s.righty;
    on_cpad_read(0, &b, &lx, &ly, &rx, &ry);
    recorded[t] = PadRecord{b, lx, ly, rx, ry};
  }
  uint64_t recorded_ticks = g.legacy_tick;
  shutdown();

  long expect = (long)sizeof(Header) + (long)n_ticks * (long)sizeof(PadRecord);
  long actual = -1;
  if (FILE* fz = std::fopen(out_path.c_str(), "rb")) {
    std::fseek(fz, 0, SEEK_END);
    actual = std::ftell(fz);
    std::fclose(fz);
  }

  // ---- REPLAY #1 through the real tap; dump per-tick state ------------------
  init(Mode::Replay, out_path);
  open_state_trace(out_path + ".statedump.txt");
  std::vector<PadRecord> replay1(n_ticks);
  for (int t = 0; t < n_ticks; ++t) {
    uint16_t b = 0;
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
  int pad_diff = 0;
  int first_div = -1;
  for (int t = 0; t < n_ticks; ++t) {
    if (std::memcmp(&recorded[t], &replay1[t], sizeof(PadRecord)) != 0) {
      pad_diff++;
      if (first_div < 0) {
        first_div = t;
      }
    }
  }
  int det_diff = 0;
  for (int t = 0; t < n_ticks; ++t) {
    if (std::memcmp(&replay1[t], &replay2[t], sizeof(PadRecord)) != 0) {
      det_diff++;
    }
  }

  PR_LOG("pad_replay: idle-until-first-input: 3 neutral ticks skipped (%s)",
         idle_ok ? "OK" : "FAIL");
  PR_LOG("pad_replay: demo size %ld bytes (expected %ld)", actual, expect);
  PR_LOG("PAD DIFF: %d/%d", pad_diff, n_ticks);
  PR_LOG("DETERMINISM: 2 replays differ at %d/%d logic ticks", det_diff, n_ticks);
  if (first_div < 0) {
    PR_LOG("FIRST DIVERGENCE: none — all %d ticks bit-identical (record == replay)", n_ticks);
  } else {
    PR_LOG("FIRST DIVERGENCE: logic tick %d", first_div);
  }

  bool pass = (pad_diff == 0) && (det_diff == 0) && idle_ok &&
              ((uint64_t)n_ticks == recorded_ticks) && (actual == expect);
  PR_LOG("pad_replay: SELFTEST %s", pass ? "PASS" : "FAIL");

  g.logic_frame_fn = saved_lf;
  g.anchor_fn = saved_af;
  return pass ? 0 : 1;
}

}  // namespace pad_replay
