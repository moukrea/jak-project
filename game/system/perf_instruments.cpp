#include "game/system/perf_instruments.h"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#if defined(__linux__) || defined(__ANDROID__)
#include <sched.h>
#include <unistd.h>
#endif
#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "common/goal_constants.h"
#include "common/symbols.h"

#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/mips2c/vu_simd_state.h"
#include "game/runtime.h"
#include "game/system/autoport_proof.h"
#include "game/system/codegen_arm64_calls.h"

namespace Mips2C::vu_simd {
namespace {
constexpr const char* kItem = "perf-mips2c-neon";
AUTOPORT_FEATURE_SITE(kItem);
// All counters are owned by the GOAL thread, like the VU contexts themselves.
uint64_t compared[3] = {}, defects[3] = {}, active_frames[3] = {};
uint64_t previous[3] = {}, frames = 0, warmup_frames = 0, ticks = 0;
constexpr const char* names[] = {"bones", "joints", "particles"};
bool measuring() {
  static const bool value = autoport_proof::feature_is(kItem);
  return value;
}
}  // namespace

Settings settings(Kernel) {
#if defined(__aarch64__) || defined(__SSE2__) || defined(_M_X64)
  static const bool on = autoport_proof::armed_for(kItem);
  return {on, on && measuring() && frames < 600};
#else
  return {false, false};
#endif
}

void record(Kernel kernel, uint64_t count, uint64_t mismatches) {
  const auto index = static_cast<unsigned>(kernel);
  compared[index] += count;
  defects[index] += mismatches;
}

void frame_boundary() {
  if (!measuring()) {
    return;
  }
  bool active = false;
  bool all_active = true;
  for (unsigned i = 0; i < 3; ++i) {
    if (compared[i] != previous[i]) {
      ++active_frames[i];
      active = true;
    } else {
      all_active = false;
    }
    previous[i] = compared[i];
  }
  if (active) {
    autoport_proof::note_hit_for(kItem);
    // Qualify only frames with comparisons from all three kernels in this frame.
    // Partial activity must not exhaust the 600-frame comparison window.
    if (all_active) {
      ++frames;
    } else {
      ++warmup_frames;
    }
  }
  if (++ticks % 60 != 0) {
    return;
  }
  uint64_t bit_defects = 0, missing_kernels = 0;
  for (unsigned i = 0; i < 3; ++i) {
    const std::string prefix = std::string("mips2c_") + names[i];
    autoport_proof::publish((prefix + "_compared_ops").c_str(), compared[i]);
    autoport_proof::publish((prefix + "_bit_defects").c_str(), defects[i]);
    autoport_proof::publish((prefix + "_frames").c_str(), active_frames[i]);
    bit_defects += defects[i];
    missing_kernels += compared[i] == 0;
  }
  uint64_t refset_diff = 0;
  const bool refset_present = autoport_proof::read_uint("refset_replay_maxdiff", refset_diff);
  autoport_proof::publish("mips2c_parity_frames", frames);
  autoport_proof::publish("mips2c_warmup_frames", warmup_frames);
  autoport_proof::publish("mips2c_bit_defects", bit_defects);
  autoport_proof::publish("mips2c_missing_kernels", missing_kernels);
  autoport_proof::publish("mips2c_refset_present", refset_present);
  autoport_proof::publish("mips2c_parity_incomplete", frames < 600 || missing_kernels || !refset_present);
  // An absent replay or an unexercised kernel must never produce a green zero.
  autoport_proof::publish("mips2c_parity_defects", bit_defects + missing_kernels +
                             (frames < 600) + (!refset_present || refset_diff != 0));
}
}  // namespace Mips2C::vu_simd

#if defined(__ANDROID__)
// Repertoire de fichiers externe de l'application (pousse par Java avant le boot,
// gk_android_main.cpp). Repli quand /data/local/tmp refuse l'ecriture a l'application.
extern "C" const char* gk_perf_map_fallback_dir();
#endif

namespace perf_instruments {
namespace {

constexpr const char* kItemId = "perf-instruments";
AUTOPORT_FEATURE_SITE(kItemId);

// Les 35 seaux `with-profiler` de jak1 (main.gc, drawable.gc, pc-related). L'ordre est celui de
// la publication ; les noms sont ceux passes a `pc-prof`, la cle remplace `-` par `_`.
constexpr int kBuckets = 35;
const char* const kBucketNames[kBuckets] = {
    "foreground-effects", "ambients",     "math-engine",   "debug",          "camera",
    "draw-hook",          "menu",         "dma-sync",      "post-sync-draw", "swap-display",
    "process-particles",  "sound-update", "level-update",  "mc-run",         "update-pc",
    "texture-upload",     "sky",          "time-of-day",   "ocean",          "merc",
    "background",         "stats",        "foreground-engines", "bones",     "gmerc",
    "shadow",             "eyes",         "sprite",        "debug-draw",     "touching",
    "actors-update",      "tie-instance", "tie-generic-protos", "discord-update", "speedrun-update",
};
constexpr int kBucketBones = 23;  // indice de « bones » dans la table ci-dessus

// ── etat d'armement ─────────────────────────────────────────────────────────────────────────
std::atomic<int> g_enabled{-1};  // -1 jamais evalue, 0 eteint, 1 allume

bool knob_set() {
  if (const char* e = std::getenv("OG_PERF_BUCKETS")) {
    if (e[0] == '1' && e[1] == 0) {
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.perf.buckets", buf) > 0 && buf[0] == '1' &&
      buf[1] == 0) {
    return true;
  }
#endif
  return false;
}

void evaluate_enabled() {
  const bool on =
      autoport_proof::armed_for(kItemId) && (autoport_proof::feature_is(kItemId) || knob_set());
  g_enabled.store(on ? 1 : 0, std::memory_order_relaxed);
}

// ── lecture bornee de la memoire GOAL ───────────────────────────────────────────────────────
inline bool rd32(uint32_t goal, uint32_t* out) {
  if (!g_ee_main_mem || goal < 0x1000 || goal >= (uint32_t)EE_MAIN_MEM_SIZE - 4) {
    return false;
  }
  std::memcpy(out, g_ee_main_mem + goal, 4);
  return true;
}
inline bool rd16(uint32_t goal, uint32_t* out) {
  if (!g_ee_main_mem || goal < 0x1000 || goal >= (uint32_t)EE_MAIN_MEM_SIZE - 2) {
    return false;
  }
  uint16_t v = 0;
  std::memcpy(&v, g_ee_main_mem + goal, 2);
  *out = v;
  return true;
}
inline bool heap_ptr(uint32_t v) {
  return v >= (uint32_t)EE_MAIN_MEM_LOW_PROTECT && v < (uint32_t)EE_MAIN_MEM_SIZE - 16 &&
         (v & 3) == 0;
}
// Un pointeur GOAL « vide » est le symbole #f (s7), PAS zero : `brother`/`child` d'une feuille
// valent #f. Mesure x86 du 2026-09-10 : la marche prenait #f pour un noeud, tournait en rond
// sur le contenu du symbole et rendait actors_tree_nodes=8193 (le plafond) pour 2 process.
inline bool goal_null(uint32_t v) {
  return v == 0 || (s7.offset != 0 && v == s7.offset);
}
// Chaine GOAL (`String` : len puis octets) copiee de facon bornee.
bool rd_goal_string(uint32_t str, char* out, size_t cap) {
  uint32_t len = 0;
  if (!rd32(str, &len) || len == 0 || len > 200) {
    return false;
  }
  if ((uint64_t)str + 4 + len >= (uint64_t)EE_MAIN_MEM_SIZE) {
    return false;
  }
  size_t n = std::min<size_t>(len, cap - 1);
  std::memcpy(out, g_ee_main_mem + str + 4, n);
  out[n] = 0;
  // Un nom de symbole ne porte ni blanc ni caractere de controle : on ne laisse rien passer
  // qui casserait une ligne de perf map.
  for (size_t i = 0; i < n; i++) {
    if ((unsigned char)out[i] <= ' ' || (unsigned char)out[i] >= 127) {
      out[i] = '_';
    }
  }
  return true;
}

inline int64_t now_ns() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// ── recepteur du flux pc-prof (fil GOAL, aucun verrou) ──────────────────────────────────────
// Cache pointeur-de-chaine -> indice de seau : les noms des seaux sont des litteraux de l'objet
// GOAL, leur adresse ne bouge pas ; un nom de process (chaine d'entite) rend -1 et compte comme
// un process execute.
struct NameCacheEntry {
  uint32_t ptr = 0;
  int idx = -2;
};
NameCacheEntry g_name_cache[512];

int bucket_of(uint32_t ptr, const char* name) {
  NameCacheEntry& e = g_name_cache[(ptr >> 3) & 511];
  if (e.ptr == ptr && e.idx != -2) {
    return e.idx;
  }
  int idx = -1;
  for (int i = 0; i < kBuckets; i++) {
    if (std::strcmp(name, kBucketNames[i]) == 0) {
      idx = i;
      break;
    }
  }
  e.ptr = ptr;
  e.idx = idx;
  return idx;
}

struct Open {
  int idx;
  int64_t t0;
};
Open g_stack[64];
int g_depth = 0;

// Fenetre de publication (remise a zero toutes les 60 images).
uint64_t g_bucket_ns[kBuckets] = {};
uint64_t g_bucket_calls[kBuckets] = {};
uint64_t g_seen_ever[kBuckets] = {};
uint64_t g_dispatch_ns = 0, g_syncpath_ns = 0, g_vsync_ns = 0;
uint64_t g_dispatches = 0;
uint64_t g_frames_window = 0;
uint64_t g_frames_total = 0;
uint64_t g_dma_bytes_window = 0;
uint64_t g_dma_frames = 0;
bool g_dma_copy_mode = false;
int g_cpu_core = -1;

// Par tour du dispatcher (entre deux `ROOT`).
uint32_t g_ran[4096];
int g_ran_n = 0;
uint64_t g_joints_tour = 0;
bool g_joints_seen_tour = false;
// Dernier tour complet.
uint64_t g_actors_active = 0, g_actors_paused = 0, g_actors_total = 0;
uint64_t g_actors_procs = 0, g_actors_nodes = 0;  // temoins de la marche : « 1 acteur » se lit
                                                   // avec le nombre de process et de noeuds vus
uint64_t g_joints_last = 0;
uint64_t g_tours_measured = 0;

// Symboles GOAL, resolus une fois (jamais crees : `find_symbol_from_c`, pas `intern`).
uint32_t g_sym_entity_pool = 0;
uint32_t g_sym_bone_list = 0;
uint32_t g_sym_process_drawable = 0;  // offset du SYMBOLE `process-drawable` (compare a type->symbol)
uint64_t g_sym_retry_frame = 0;

void resolve_symbols() {
  if (g_game_version != GameVersion::Jak1 || !g_ee_main_mem || SymbolTable2.offset == 0) {
    return;
  }
  if (!g_sym_entity_pool) {
    g_sym_entity_pool = jak1::find_symbol_from_c("*entity-pool*").offset;
  }
  if (!g_sym_bone_list) {
    g_sym_bone_list = jak1::find_symbol_from_c("*bone-calculation-list*").offset;
  }
  if (!g_sym_process_drawable) {
    g_sym_process_drawable = jak1::find_symbol_from_c("process-drawable").offset;
  }
}

std::unordered_map<uint32_t, bool> g_type_is_actor;

constexpr const char* kCodegenItem = "perf-codegen-arm64-calls";
AUTOPORT_FEATURE_SITE(kCodegenItem);

void publish_codegen_calls() {
  if (!autoport_proof::feature_is(kCodegenItem) || g_frames_total % 60 != 0) {
    return;
  }
  // Existing, normally generated functions from the display loop and camera.
  // Inspect the linked code, not compiler claims or an APK build-time constant.
  constexpr const char* markers[] = {"display-frame-start", "display-frame-finish",
                                    "display-sync", "main-draw-hook", "update-math-camera"};
  uint64_t complete = 0, max_instructions = 0, sites = 0, reduced = 0;
#if defined(__aarch64__)
  if (g_game_version == GameVersion::Jak1 && g_ee_main_mem && SymbolTable2.offset) {
    uint32_t function_type = 0;
    rd32(s7.offset + jak1_symbols::FIX_SYM_FUNCTION_TYPE, &function_type);
    for (size_t m = 0; m < 5; ++m) {
      uint32_t address = 0, type = 0;
      const auto symbol = jak1::find_symbol_from_c(markers[m]);
      codegen_arm64::CallStats stats;
      if (symbol.offset && rd32(symbol.offset, &address) && (address & 3u) == 0 &&
          rd32(address - 4, &type) && function_type && type == function_type) {
        std::vector<uint32_t> words;
        // Bound malformed functions; none of these markers is an asm-func or a
        // trampoline. A missing RET or an unfamiliar BLR wrapper is incomplete.
        for (uint32_t offset = 0; offset < 65536; offset += 4) {
          uint32_t word = 0;
          if (!rd32(address + offset, &word)) break;
          words.push_back(word);
          if (word == 0xd65f03c0u) break;
        }
        stats = codegen_arm64::inspect_calls(words.data(), words.size());
      }
      const std::string prefix = "codegen_marker_" + std::to_string(m);
      autoport_proof::publish_text((prefix + "_name").c_str(), markers[m]);
      autoport_proof::publish((prefix + "_address").c_str(), address);
      autoport_proof::publish((prefix + "_calls").c_str(), stats.calls);
      autoport_proof::publish((prefix + "_instructions").c_str(), stats.max_instructions);
      autoport_proof::publish((prefix + "_complete").c_str(), stats.complete);
      complete += stats.complete;
      sites += stats.calls;
      reduced += stats.reduced_calls;
      max_instructions = std::max<uint64_t>(max_instructions, stats.max_instructions);
    }
  }
#endif
  uint64_t refset_diff = 0;
  const bool refset_present = autoport_proof::read_uint("refset_replay_maxdiff", refset_diff);
  autoport_proof::publish("codegen_markers_complete", complete);
  autoport_proof::publish("codegen_call_sites", sites);
  autoport_proof::publish("codegen_reduced_call_sites", reduced);
  autoport_proof::publish("codegen_call_max_instructions", max_instructions);
  autoport_proof::publish("codegen_boot_frames", g_frames_total);
  autoport_proof::publish("codegen_refset_present", refset_present);
  autoport_proof::publish("codegen_lot_defects",
                         (!refset_present || refset_diff != 0) + (g_frames_total < 600) +
                             (complete != 5 || max_instructions > 2));
  // Hits identify the reduced sites observed in the running process. The
  // separate frame counter proves survival; this is not a dynamic call count.
  autoport_proof::note_hit_for(kCodegenItem, reduced);
}

bool type_is_actor(uint32_t type) {
  auto it = g_type_is_actor.find(type);
  if (it != g_type_is_actor.end()) {
    return it->second;
  }
  bool r = false;
  uint32_t t = type;
  for (int depth = 0; depth < 24 && t; depth++) {
    uint32_t sym = 0, parent = 0;
    if (!rd32(t, &sym) || !rd32(t + 4, &parent)) {
      break;
    }
    if (sym == g_sym_process_drawable) {
      r = true;
      break;
    }
    if (parent == t) {
      break;
    }
    t = parent;
  }
  if (g_type_is_actor.size() < 4096) {
    g_type_is_actor[type] = r;
  }
  return r;
}

bool ran_contains(uint32_t name) {
  for (int i = 0; i < g_ran_n; i++) {
    if (g_ran[i] == name) {
      return true;
    }
  }
  return false;
}

// Marche de `*entity-pool*` : process-tree (bit 8 du masque) = noeud, sinon process. Les enfants
// se suivent par `child` -> (pointer process-tree) -> `brother` du fils (gkernel.gc,
// iterate-process-tree).
struct Walk {
  uint64_t active = 0, paused = 0, total = 0;
  uint64_t procs = 0;  // tous les process (non process-tree) rencontres, acteurs ou non
  int nodes = 0;
};

void walk(uint32_t node, int depth, Walk& w) {
  if (depth > 48 || w.nodes > 8192 || goal_null(node) || !heap_ptr(node)) {
    return;
  }
  w.nodes++;
  uint32_t mask = 0, type = 0;
  if (!rd32(node + 4, &mask) || !rd32(node - 4, &type)) {
    return;
  }
  if (!(mask & (1u << 8))) {
    w.procs++;
    if (type_is_actor(type)) {
      uint32_t name = 0;
      rd32(node, &name);
      w.total++;
      if (ran_contains(name)) {
        w.active++;
      } else {
        w.paused++;
      }
    }
  }
  uint32_t pp = 0;
  if (!rd32(node + 16, &pp)) {
    return;
  }
  int siblings = 0;
  while (!goal_null(pp) && heap_ptr(pp) && siblings++ < 4096) {
    uint32_t child = 0;
    if (!rd32(pp, &child) || goal_null(child) || !heap_ptr(child)) {
      break;
    }
    uint32_t next = 0;
    rd32(child + 12, &next);  // brother du fils, lu AVANT la descente (comme le noyau)
    walk(child, depth + 1, w);
    pp = next;
  }
}

void end_of_tour() {
  // Le tour qui vient de finir : croiser « a couru » avec l'arbre des entites.
  if (g_sym_entity_pool && g_sym_process_drawable) {
    uint32_t pool = 0;
    if (rd32(g_sym_entity_pool, &pool) && heap_ptr(pool)) {
      Walk w;
      walk(pool, 0, w);
      g_actors_active = w.active;
      g_actors_paused = w.paused;
      g_actors_total = w.total;
      g_actors_procs = w.procs;
      g_actors_nodes = (uint64_t)w.nodes;
      g_tours_measured++;
    }
  }
  if (g_joints_seen_tour) {
    g_joints_last = g_joints_tour;
  }
  g_ran_n = 0;
  g_joints_tour = 0;
  g_joints_seen_tour = false;
  g_depth = 0;
}

void count_joints() {
  if (!g_sym_bone_list) {
    return;
  }
  uint32_t list = 0, node = 0;
  if (!rd32(g_sym_bone_list, &list) || !heap_ptr(list) || !rd32(list, &node)) {
    return;
  }
  uint64_t n = 0;
  int guard = 0;
  while (!goal_null(node) && heap_ptr(node) && guard++ < 4096) {
    uint32_t nb = 0, next = 0;
    if (!rd16(node + 2, &nb) || !rd32(node + 32, &next)) {
      break;
    }
    n += nb;
    node = next;
  }
  g_joints_tour = n;
  g_joints_seen_tour = true;
}

// ── perf map ────────────────────────────────────────────────────────────────────────────────
std::atomic<int64_t> g_last_link_ns{0};
std::atomic<bool> g_map_dirty{false};
uint64_t g_map_entries = 0;
std::string g_map_path;
int g_map_errno = 0;

struct MapEntry {
  uint32_t addr;
  int prio;  // 0 = symbole global, 1 = methode
  std::string name;
};

void collect_symbol_area(uint32_t start, uint32_t end, uint32_t fn_type, uint32_t type_type,
                         std::vector<MapEntry>& out) {
  char nm[160];
  for (uint32_t i = start; i + 8 <= end; i += 8) {
    uint32_t hash = 0, strp = 0, val = 0;
    const uint32_t info = i + (uint32_t)jak1::SYM_INFO_OFFSET;
    if (!rd32(info, &hash) || !hash || !rd32(info + 4, &strp) || !rd32(i, &val)) {
      continue;
    }
    if (!heap_ptr(val)) {
      continue;
    }
    uint32_t tag = 0;
    if (!rd32(val - 4, &tag)) {
      continue;
    }
    if (tag == fn_type) {
      if (rd_goal_string(strp, nm, sizeof(nm))) {
        out.push_back({val, 0, nm});
      }
    } else if (tag == type_type) {
      uint32_t nmeth = 0;
      if (!rd16(val + 0xe, &nmeth) || nmeth > 256) {
        continue;
      }
      if (!rd_goal_string(strp, nm, sizeof(nm))) {
        continue;
      }
      for (uint32_t m = 0; m < nmeth; m++) {
        uint32_t f = 0, ftag = 0;
        if (!rd32(val + 16 + 4 * m, &f) || !heap_ptr(f) || !rd32(f - 4, &ftag) ||
            ftag != fn_type) {
          continue;
        }
        char full[200];
        std::snprintf(full, sizeof(full), "%s.m%u", nm, (unsigned)m);
        out.push_back({f, 1, full});
      }
    }
  }
}

void write_perf_map() {
  if (g_game_version != GameVersion::Jak1 || !g_ee_main_mem || SymbolTable2.offset == 0 ||
      s7.offset == 0 || LastSymbol.offset == 0) {
    return;
  }
  uint32_t fn_type = 0, type_type = 0;
  if (!rd32(s7.offset + jak1_symbols::FIX_SYM_FUNCTION_TYPE, &fn_type) ||
      !rd32(s7.offset + jak1_symbols::FIX_SYM_TYPE_TYPE, &type_type) || !fn_type || !type_type) {
    return;
  }
  std::vector<MapEntry> entries;
  entries.reserve(16384);
  if (SymbolTable2.offset + 16 < s7.offset) {
    collect_symbol_area(SymbolTable2.offset, s7.offset - 0x10, fn_type, type_type, entries);
  }
  collect_symbol_area(s7.offset, LastSymbol.offset, fn_type, type_type, entries);
  std::stable_sort(entries.begin(), entries.end(), [](const MapEntry& a, const MapEntry& b) {
    if (a.addr != b.addr) {
      return a.addr < b.addr;
    }
    return a.prio < b.prio;
  });
  // Une seule ligne par adresse : la methode heritee apparait dans chaque type fils, le symbole
  // global gagne sur la methode.
  std::vector<MapEntry> uniq;
  uniq.reserve(entries.size());
  for (auto& e : entries) {
    if (uniq.empty() || uniq.back().addr != e.addr) {
      uniq.push_back(std::move(e));
    }
  }
  const int pid = (int)getpid();
  char path[600];
  FILE* f = nullptr;
#if defined(__ANDROID__)
  std::snprintf(path, sizeof(path), "/data/local/tmp/perf-%d.map", pid);
  f = std::fopen(path, "w");
  if (!f) {
    const char* fb = gk_perf_map_fallback_dir();
    if (fb && fb[0]) {
      std::snprintf(path, sizeof(path), "%s/perf-%d.map", fb, pid);
      f = std::fopen(path, "w");
    }
  }
#else
  std::snprintf(path, sizeof(path), "/tmp/perf-%d.map", pid);
  f = std::fopen(path, "w");
#endif
  if (!f) {
    g_map_errno = errno;
    g_map_entries = 0;
    g_map_path = path;
    return;
  }
  for (size_t i = 0; i < uniq.size(); i++) {
    const uint64_t addr = (uint64_t)(uintptr_t)(g_ee_main_mem + uniq[i].addr);
    uint64_t size = 0x1000;
    if (i + 1 < uniq.size()) {
      size = std::min<uint64_t>(uniq[i + 1].addr - uniq[i].addr, 0x100000);
    }
    std::fprintf(f, "%llx %llx %s\n", (unsigned long long)addr, (unsigned long long)size,
                 uniq[i].name.c_str());
  }
  std::fclose(f);
  // Relu : la grandeur publiee est ce que le fichier CONTIENT, pas ce qu'on a voulu ecrire.
  uint64_t lines = 0;
  if (FILE* r = std::fopen(path, "r")) {
    int c;
    while ((c = std::fgetc(r)) != EOF) {
      if (c == '\n') {
        lines++;
      }
    }
    std::fclose(r);
  }
  g_map_entries = lines;
  g_map_path = path;
  g_map_errno = 0;
}

// ── cles attendues ──────────────────────────────────────────────────────────────────────────
std::mutex g_expect_mutex;
std::vector<std::string> g_expected;

void expect_locked(const std::string& k) {
  if (std::find(g_expected.begin(), g_expected.end(), k) == g_expected.end()) {
    g_expected.push_back(k);
  }
}

void init_expected_locked() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  s_done = true;
  expect_locked("goal_busy_ms");
  for (int i = 0; i < kBuckets; i++) {
    std::string k = std::string("goal_bucket_ms_") + kBucketNames[i];
    std::replace(k.begin(), k.end(), '-', '_');
    expect_locked(k);
  }
  expect_locked("dma_chain_bytes_copied");
  expect_locked("actors_active");
  expect_locked("actors_paused");
  expect_locked("joints_evaluated");
  expect_locked("cpu_core_goal");
  expect_locked("perf_map_entries");
  expect_locked("gpu_ms_buckets");
}

std::mutex g_snap_mutex;
Snapshot g_snap;

void publish_window() {
  const uint64_t frames = g_frames_window ? g_frames_window : 1;
  char v[48];
  auto pub_ms = [&](const char* key, uint64_t ns) {
    std::snprintf(v, sizeof(v), "%.3f", (double)ns / (double)frames / 1.0e6);
    autoport_proof::publish_text(key, v);
  };
  const uint64_t waits = g_syncpath_ns + g_vsync_ns;
  const uint64_t busy = g_dispatch_ns > waits ? g_dispatch_ns - waits : 0;
  pub_ms("goal_busy_ms", busy);
  pub_ms("goal_dispatch_ms", g_dispatch_ns);
  pub_ms("goal_syncpath_wait_ms", g_syncpath_ns);
  pub_ms("goal_vsync_wait_ms", g_vsync_ns);
  autoport_proof::publish("goal_dispatch_cycles", g_dispatches);
  autoport_proof::publish("perf_window_frames", g_frames_window);
  autoport_proof::publish("perf_frames_total", g_frames_total);

  std::string unseen;
  for (int i = 0; i < kBuckets; i++) {
    std::string k = std::string("goal_bucket_ms_") + kBucketNames[i];
    std::replace(k.begin(), k.end(), '-', '_');
    pub_ms(k.c_str(), g_bucket_ns[i]);
    if (g_bucket_calls[i] == 0) {
      if (!unseen.empty()) {
        unseen += ",";
      }
      unseen += kBucketNames[i];
    }
  }
  autoport_proof::publish_text("goal_buckets_unseen", unseen.empty() ? "none" : unseen.c_str());

  const uint64_t dma_frames = g_dma_frames ? g_dma_frames : 1;
  autoport_proof::publish("dma_chain_bytes_copied", g_dma_bytes_window / dma_frames);
  autoport_proof::publish("dma_chain_copy_mode", g_dma_copy_mode ? 1 : 0);
  if (g_tours_measured > 0) {
    autoport_proof::publish("actors_active", g_actors_active);
    autoport_proof::publish("actors_paused", g_actors_paused);
    autoport_proof::publish("actors_total", g_actors_total);
    autoport_proof::publish("actors_procs", g_actors_procs);
    autoport_proof::publish("actors_tree_nodes", g_actors_nodes);
  }
  if (g_seen_ever[kBucketBones] > 0) {
    autoport_proof::publish("joints_evaluated", g_joints_last);
  }
  if (g_cpu_core >= 0) {
    autoport_proof::publish("cpu_core_goal", (uint64_t)g_cpu_core);
  }
  if (g_map_entries > 0) {
    autoport_proof::publish("perf_map_entries", g_map_entries);
    autoport_proof::publish_text("perf_map_path", g_map_path.c_str());
  } else if (g_map_errno) {
    autoport_proof::publish("perf_map_errno", (uint64_t)g_map_errno);
    autoport_proof::publish_text("perf_map_path", g_map_path.c_str());
  }

  // Ce qui MANQUE, lu dans la table de publication elle-meme.
  uint64_t missing = 0;
  std::string missing_keys;
  {
    std::lock_guard<std::mutex> lock(g_expect_mutex);
    init_expected_locked();
    for (const auto& k : g_expected) {
      if (!autoport_proof::has_key(k.c_str())) {
        missing++;
        if (missing_keys.size() < 220) {
          if (!missing_keys.empty()) {
            missing_keys += ",";
          }
          missing_keys += k;
        }
      }
    }
    autoport_proof::publish("perf_instruments_expected", g_expected.size());
    autoport_proof::note_hit_for(kItemId, g_expected.size() - missing);
  }
  autoport_proof::publish("perf_instruments_missing", missing);
  autoport_proof::publish_text("perf_instruments_missing_keys",
                               missing_keys.empty() ? "none" : missing_keys.c_str());

  {
    std::lock_guard<std::mutex> lock(g_snap_mutex);
    g_snap.busy_ms = (double)busy / (double)frames / 1.0e6;
    g_snap.dispatch_ms = (double)g_dispatch_ns / (double)frames / 1.0e6;
    g_snap.syncpath_ms = (double)g_syncpath_ns / (double)frames / 1.0e6;
    g_snap.vsync_ms = (double)g_vsync_ns / (double)frames / 1.0e6;
    g_snap.dma_bytes = g_dma_bytes_window / dma_frames;
    g_snap.actors_active = g_actors_active;
    g_snap.actors_paused = g_actors_paused;
    g_snap.joints = g_joints_last;
    g_snap.cpu_core = g_cpu_core;
    g_snap.perf_map_entries = g_map_entries;
    g_snap.missing = missing;
    g_snap.frames = g_frames_total;
  }

  // Nouvelle fenetre.
  for (int i = 0; i < kBuckets; i++) {
    g_bucket_ns[i] = 0;
    g_bucket_calls[i] = 0;
  }
  g_dispatch_ns = g_syncpath_ns = g_vsync_ns = 0;
  g_dispatches = 0;
  g_frames_window = 0;
  g_dma_bytes_window = 0;
  g_dma_frames = 0;
}

}  // namespace

bool enabled() {
  int v = g_enabled.load(std::memory_order_relaxed);
  if (v < 0) {
    evaluate_enabled();
    v = g_enabled.load(std::memory_order_relaxed);
  }
  return v == 1;
}

void note_dispatch_ns(uint64_t ns) {
  if (!enabled()) {
    return;
  }
  g_dispatch_ns += ns;
  g_dispatches++;
}

void note_syncpath_wait_ns(uint64_t ns) {
  if (!enabled()) {
    return;
  }
  g_syncpath_ns += ns;
}

void note_vsync_wait_ns(uint64_t ns) {
  if (!enabled()) {
    return;
  }
  g_vsync_ns += ns;
}

void frame_boundary() {
  Mips2C::vu_simd::frame_boundary();
  g_frames_total++;
  publish_codegen_calls();
  // Le reglage peut etre pose avant le lancement (propriete) : on le relit toutes les 120
  // images, comme le vidage A35-PERF, pour ne pas figer un etat lu trop tot.
  if (g_frames_total % 120 == 1) {
    evaluate_enabled();
  }
  if (!enabled()) {
    return;
  }
  g_frames_window++;
  if (g_frames_total >= g_sym_retry_frame) {
    resolve_symbols();
    g_sym_retry_frame = g_frames_total + 120;
  }
#if defined(__linux__) || defined(__ANDROID__)
  g_cpu_core = sched_getcpu();
#endif
  // Perf map : apres la rafale de liens (500 ms de calme), jamais pendant.
  if (g_map_dirty.load(std::memory_order_relaxed)) {
    const int64_t since = now_ns() - g_last_link_ns.load(std::memory_order_relaxed);
    if (since > 500 * 1000 * 1000) {
      g_map_dirty.store(false, std::memory_order_relaxed);
      write_perf_map();
    }
  }
  if (g_frames_window >= 60) {
    publish_window();
  }
}

void goal_prof_event(uint32_t name_ptr, const char* name, int kind) {
  if (!enabled() || !name) {
    return;
  }
  if (kind == 2) {  // instant
    if (name[0] == 'R' && std::strcmp(name, "ROOT") == 0) {
      end_of_tour();
    }
    return;
  }
  if (kind == 0) {  // begin
    const int idx = bucket_of(name_ptr, name);
    if (idx < 0) {
      if (g_ran_n < 4096) {
        g_ran[g_ran_n++] = name_ptr;
      }
    } else if (idx == kBucketBones) {
      count_joints();
    }
    if (g_depth < 64) {
      g_stack[g_depth] = {idx, now_ns()};
    }
    g_depth++;
    return;
  }
  // end
  if (g_depth <= 0) {
    return;
  }
  g_depth--;
  if (g_depth < 64) {
    const Open& o = g_stack[g_depth];
    if (o.idx >= 0) {
      const int64_t dt = now_ns() - o.t0;
      if (dt > 0) {
        g_bucket_ns[o.idx] += (uint64_t)dt;
      }
      g_bucket_calls[o.idx]++;
      g_seen_ever[o.idx]++;
    }
  }
}

void note_dma_chain_copied(uint64_t bytes, bool copy_mode) {
  if (!enabled()) {
    return;
  }
  g_dma_bytes_window += bytes;
  g_dma_frames++;
  g_dma_copy_mode = copy_mode;
}

void note_link_finish() {
  g_last_link_ns.store(now_ns(), std::memory_order_relaxed);
  g_map_dirty.store(true, std::memory_order_relaxed);
}

void expect_key(const char* key) {
  if (!key || !key[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_expect_mutex);
  init_expected_locked();
  expect_locked(key);
}

Snapshot snapshot() {
  std::lock_guard<std::mutex> lock(g_snap_mutex);
  return g_snap;
}

}  // namespace perf_instruments
