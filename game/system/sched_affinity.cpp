#include "game/system/sched_affinity.h"

#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(__linux__) || defined(__ANDROID__)
#include <sched.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#endif

#include "game/system/autoport_proof.h"

namespace sched_affinity {
namespace {

constexpr const char* kItemId = "perf-thread-build";
AUTOPORT_FEATURE_SITE(kItemId);

// La priorite visee. -8 est `THREAD_PRIORITY_URGENT_DISPLAY` d'Android : c'est le cran que le
// systeme reserve a ce qui doit sortir avant la prochaine image, et un processus d'application
// y a droit sur ses propres fils (RLIMIT_NICE = 40 pour les applications). On ne descend pas
// plus bas : -16/-19 sont les crans audio, et voler l'audio ferait un defaut a la place d'un gain.
constexpr int kTargetNice = -8;

// Le plancher de la porte, en pour-cent d'images.
constexpr uint64_t kPctBigFloor = 95;
// La duree que l'item exige du releve thermique.
constexpr uint64_t kThermalSpanRequiredS = 600;

// ── lectures sysfs bornees ──────────────────────────────────────────────────────────────────
#if defined(__linux__) || defined(__ANDROID__)
bool read_u64_file(const char* path, uint64_t* out) {
  FILE* f = std::fopen(path, "re");
  if (!f) {
    return false;
  }
  char buf[64] = {0};
  const size_t n = std::fread(buf, 1, sizeof(buf) - 1, f);
  std::fclose(f);
  if (n == 0) {
    return false;
  }
  char* end = nullptr;
  const unsigned long long v = std::strtoull(buf, &end, 10);
  if (end == buf) {
    return false;
  }
  *out = (uint64_t)v;
  return true;
}

int64_t now_ms() {
  struct timespec ts = {};
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

pid_t this_tid() {
  return (pid_t)syscall(SYS_gettid);
}
#endif

// ── topologie ───────────────────────────────────────────────────────────────────────────────
// Detectee UNE fois, jamais ecrite en dur : le meme libgk.so tourne sur le Redmi (2xA76 en
// cpu6/cpu7) et sur le Honor de l'owner, dont la carte des coeurs est differente.
std::atomic<bool> g_topo_done{false};
// LE VERROU N'EST PAS DECORATIF. `detect_topology()` est appele par le fil GOAL (au demarrage du
// dispatcher) ET par le fil GL (a l'init SDL), qui vivent en parallele : sans lui, deux fils
// ecrivaient `g_big_list` — un std::string — en meme temps. Le drapeau atomique seul ne ferme
// rien, il laisse juste les deux entrer.
std::mutex g_topo_mutex;
uint64_t g_big_mask = 0;
uint64_t g_cpu_count = 0;
uint64_t g_big_nominal_khz = 0;
bool g_heterogeneous = false;
std::string g_big_list = "-";

void detect_topology() {
  if (g_topo_done.load(std::memory_order_acquire)) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_topo_mutex);
  if (g_topo_done.load(std::memory_order_relaxed)) {
    return;
  }
#if defined(__linux__) || defined(__ANDROID__)
  uint64_t freqs[64] = {0};
  uint64_t seen = 0;
  uint64_t maxf = 0, minf = 0;
  for (int c = 0; c < 64; c++) {
    char path[128];
    std::snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq", c);
    uint64_t v = 0;
    if (!read_u64_file(path, &v) || v == 0) {
      continue;
    }
    freqs[c] = v;
    seen++;
    g_cpu_count = (uint64_t)c + 1;
    if (v > maxf) {
      maxf = v;
    }
    if (minf == 0 || v < minf) {
      minf = v;
    }
  }
  if (seen >= 2 && maxf > minf) {
    g_heterogeneous = true;
    g_big_nominal_khz = maxf;
    std::string list;
    for (int c = 0; c < 64; c++) {
      if (freqs[c] == maxf) {
        g_big_mask |= (uint64_t)1 << c;
        if (!list.empty()) {
          list += ",";
        }
        list += std::to_string(c);
      }
    }
    g_big_list = list.empty() ? "-" : list;
  }
#endif
  g_topo_done.store(true, std::memory_order_release);
}

// ── ce que la pose a rendu, par role ────────────────────────────────────────────────────────
struct PinResult {
  std::atomic<int> attempted{0};
  std::atomic<int> affinity_ok{0};
  std::atomic<int> affinity_errno{0};
  std::atomic<uint64_t> affinity_effective_mask{0};
  std::atomic<int> nice_before{99};
  std::atomic<int> nice_after{99};
  std::atomic<int> nice_ok{0};
};
PinResult g_pin_goal;
PinResult g_pin_gl;

// ── comptage par image ──────────────────────────────────────────────────────────────────────
std::atomic<uint64_t> g_goal_frames{0};
std::atomic<uint64_t> g_goal_frames_big{0};
std::atomic<uint64_t> g_goal_core_mask{0};
std::atomic<uint64_t> g_gl_frames{0};
std::atomic<uint64_t> g_gl_frames_big{0};
std::atomic<uint64_t> g_gl_core_mask{0};
uint64_t g_hits_reported = 0;

// ── releve thermique (fil GOAL uniquement) ──────────────────────────────────────────────────
uint64_t g_therm_samples = 0;
uint64_t g_therm_capped_samples = 0;  // au moins un gros coeur sous son nominal
uint64_t g_therm_maxfreq_min_khz = 0;
uint64_t g_therm_read_failures = 0;
int64_t g_therm_first_ms = 0;
int64_t g_therm_last_ms = 0;
int64_t g_therm_next_ms = 0;
uint64_t g_temp_first_mc = 0;
uint64_t g_temp_max_mc = 0;
uint64_t g_cooling_max_state = 0;

#if defined(__linux__) || defined(__ANDROID__)
// Les zones a lire pour « la chauffe » : celles dont le type nomme un coeur. Resolues une fois,
// bornees a 8 zones pour que l'echantillon reste a cout negligeable.
std::vector<std::string> g_temp_paths;
std::vector<std::string> g_cooling_paths;
bool g_zones_resolved = false;

void resolve_thermal_zones() {
  if (g_zones_resolved) {
    return;
  }
  g_zones_resolved = true;
  for (int z = 0; z < 128 && g_temp_paths.size() < 8; z++) {
    char tp[128];
    std::snprintf(tp, sizeof(tp), "/sys/class/thermal/thermal_zone%d/type", z);
    FILE* f = std::fopen(tp, "re");
    if (!f) {
      continue;
    }
    char ty[64] = {0};
    const size_t n = std::fread(ty, 1, sizeof(ty) - 1, f);
    std::fclose(f);
    if (n == 0) {
      continue;
    }
    if (std::strstr(ty, "cpu") == nullptr) {
      continue;
    }
    char vp[128];
    std::snprintf(vp, sizeof(vp), "/sys/class/thermal/thermal_zone%d/temp", z);
    uint64_t probe = 0;
    if (read_u64_file(vp, &probe)) {
      g_temp_paths.push_back(vp);
    }
  }
  for (int d = 0; d < 128 && g_cooling_paths.size() < 8; d++) {
    char tp[128];
    std::snprintf(tp, sizeof(tp), "/sys/class/thermal/cooling_device%d/type", d);
    FILE* f = std::fopen(tp, "re");
    if (!f) {
      continue;
    }
    char ty[64] = {0};
    const size_t n = std::fread(ty, 1, sizeof(ty) - 1, f);
    std::fclose(f);
    if (n == 0 || std::strstr(ty, "cpufreq") == nullptr) {
      continue;
    }
    char vp[128];
    std::snprintf(vp, sizeof(vp), "/sys/class/thermal/cooling_device%d/cur_state", d);
    uint64_t probe = 0;
    if (read_u64_file(vp, &probe)) {
      g_cooling_paths.push_back(vp);
    }
  }
}

void thermal_sample() {
  resolve_thermal_zones();
  const int64_t t = now_ms();
  bool read_one = false;
  bool capped = false;
  uint64_t worst = 0;
  for (int c = 0; c < 64; c++) {
    if (!(g_big_mask & ((uint64_t)1 << c))) {
      continue;
    }
    char path[128];
    std::snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_max_freq", c);
    uint64_t v = 0;
    if (!read_u64_file(path, &v) || v == 0) {
      g_therm_read_failures++;
      continue;
    }
    read_one = true;
    if (worst == 0 || v < worst) {
      worst = v;
    }
    if (v < g_big_nominal_khz) {
      capped = true;
    }
  }
  if (!read_one) {
    return;
  }
  g_therm_samples++;
  if (capped) {
    g_therm_capped_samples++;
  }
  if (g_therm_maxfreq_min_khz == 0 || worst < g_therm_maxfreq_min_khz) {
    g_therm_maxfreq_min_khz = worst;
  }
  if (g_therm_first_ms == 0) {
    g_therm_first_ms = t;
  }
  g_therm_last_ms = t;

  uint64_t hottest = 0;
  for (const auto& p : g_temp_paths) {
    uint64_t v = 0;
    if (read_u64_file(p.c_str(), &v) && v > hottest) {
      hottest = v;
    }
  }
  if (hottest > 0) {
    if (g_temp_first_mc == 0) {
      g_temp_first_mc = hottest;
    }
    if (hottest > g_temp_max_mc) {
      g_temp_max_mc = hottest;
    }
  }
  for (const auto& p : g_cooling_paths) {
    uint64_t v = 0;
    if (read_u64_file(p.c_str(), &v) && v > g_cooling_max_state) {
      g_cooling_max_state = v;
    }
  }
}
#endif

#if defined(__linux__) || defined(__ANDROID__)
uint64_t pct(uint64_t part, uint64_t whole) {
  if (whole == 0) {
    return 0;
  }
  return part * 100 / whole;  // plancher : 94,9 % rend 94, jamais 95
}

void publish_role(const char* prefix, const PinResult& r) {
  char key[64];
  auto k = [&](const char* suffix) {
    std::snprintf(key, sizeof(key), "sched_%s_%s", prefix, suffix);
    return key;
  };
  autoport_proof::publish(k("pin_attempted"), (uint64_t)r.attempted.load());
  autoport_proof::publish(k("affinity_applied"), (uint64_t)r.affinity_ok.load());
  autoport_proof::publish(k("affinity_errno"), (uint64_t)r.affinity_errno.load());
  autoport_proof::publish(k("affinity_mask"), r.affinity_effective_mask.load());
  autoport_proof::publish(k("nice_applied"), (uint64_t)r.nice_ok.load());
  // Un `nice` est negatif : il ne rentre pas dans un uint64_t sans mentir. On publie le decalage
  // +100, et le nom de la cle le dit — jamais une valeur qu'un lecteur devrait deviner signee.
  autoport_proof::publish(k("nice_before_plus100"), (uint64_t)(r.nice_before.load() + 100));
  autoport_proof::publish(k("nice_after_plus100"), (uint64_t)(r.nice_after.load() + 100));
}

void publish_now() {
  detect_topology();

  autoport_proof::publish_text("sched_topology", g_heterogeneous ? "heterogene" : "homogene");
  autoport_proof::publish_text("sched_big_cpu_list", g_big_list.c_str());
  autoport_proof::publish("sched_big_cpu_mask", g_big_mask);
  autoport_proof::publish("sched_cpu_count", g_cpu_count);
  autoport_proof::publish("sched_big_maxfreq_nominal_khz", g_big_nominal_khz);

  const uint64_t gf = g_goal_frames.load();
  const uint64_t gfb = g_goal_frames_big.load();
  const uint64_t lf = g_gl_frames.load();
  const uint64_t lfb = g_gl_frames_big.load();

  autoport_proof::publish("sched_goal_frames_sampled", gf);
  autoport_proof::publish("sched_goal_frames_big", gfb);
  autoport_proof::publish("sched_goal_core_mask", g_goal_core_mask.load());
  autoport_proof::publish("sched_gl_frames_sampled", lf);
  autoport_proof::publish("sched_gl_frames_big", lfb);
  autoport_proof::publish("sched_gl_core_mask", g_gl_core_mask.load());

  const uint64_t goal_pct = pct(gfb, gf);
  const uint64_t gl_pct = pct(lfb, lf);
  autoport_proof::publish("cpu_core_goal_pct_big", goal_pct);
  autoport_proof::publish("cpu_core_gl_pct_big", gl_pct);

  publish_role("goal", g_pin_goal);
  publish_role("gl", g_pin_gl);

  const uint64_t span_s =
      (g_therm_last_ms > g_therm_first_ms) ? (uint64_t)((g_therm_last_ms - g_therm_first_ms) / 1000)
                                           : 0;
  autoport_proof::publish("sched_thermal_samples", g_therm_samples);
  autoport_proof::publish("sched_thermal_read_failures", g_therm_read_failures);
  autoport_proof::publish("sched_thermal_capped_samples", g_therm_capped_samples);
  autoport_proof::publish("sched_thermal_span_s", span_s);
  autoport_proof::publish("sched_big_maxfreq_min_khz", g_therm_maxfreq_min_khz);
  autoport_proof::publish("sched_temp_start_mc", g_temp_first_mc);
  autoport_proof::publish("sched_temp_max_mc", g_temp_max_mc);
  autoport_proof::publish("sched_temp_rise_mc",
                          g_temp_max_mc > g_temp_first_mc ? g_temp_max_mc - g_temp_first_mc : 0);
  autoport_proof::publish("sched_cooling_max_state", g_cooling_max_state);

  // Le binaire est-il celui que l'item demande ? `OG_ANDROID_RELEASE_BUILD` est pose par le
  // CMakeLists racine EN MEME TEMPS que `-O3 -g0` : c'est le seul temoin honnete, a l'execution,
  // du niveau d'optimisation avec lequel ce .so a ete compile.
#if defined(OG_ANDROID_RELEASE_BUILD)
  const uint64_t release_build = 1;
#else
  const uint64_t release_build = 0;
#endif
#if defined(NDEBUG)
  const uint64_t ndebug = 1;
#else
  const uint64_t ndebug = 0;
#endif
  autoport_proof::publish("sched_release_build", release_build);
  autoport_proof::publish("sched_ndebug", ndebug);

#if defined(__ANDROID__)
  // ── LE VERDICT. Trois termes, chacun publie a cote pour que le total ne cache rien. Chaque
  // terme compte le DEFAUT *et* l'absence de mesure : une grandeur qu'on n'a pas pu lire n'est
  // pas un zero, c'est un trou, et un trou ne doit pas se lire comme un succes.
  const uint64_t d_goal = (gf == 0 || goal_pct < kPctBigFloor) ? 1 : 0;
  const uint64_t d_gl = (lf == 0 || gl_pct < kPctBigFloor) ? 1 : 0;
  const uint64_t thermal_readable = (g_therm_samples > 0 && g_big_nominal_khz > 0) ? 1 : 0;
  const uint64_t d_thermal =
      (!thermal_readable || g_therm_capped_samples > 0 || span_s < kThermalSpanRequiredS) ? 1 : 0;
  autoport_proof::publish("sched_thermal_readable", thermal_readable);
  autoport_proof::publish("sched_defect_goal_small_core", d_goal);
  autoport_proof::publish("sched_defect_gl_small_core", d_gl);
  autoport_proof::publish("sched_defect_thermal", d_thermal);
  autoport_proof::publish("sched_defects", d_goal + d_gl + d_thermal);
#else
  // Hors Android il n'y a ni gros coeur ni mitigation a lire : publier `sched_defects` ici
  // ferait porter a TOUTES les preuves x86 des autres items un verdict qui ne les concerne pas,
  // et il vaudrait 3 sur une machine homogene parfaitement saine.
  autoport_proof::publish("sched_thermal_readable", 0);
#endif

  // `hits_means: images GOAL sur gros coeur`. On ne compte que le DELTA : `note_hit_for` cumule.
  if (gfb > g_hits_reported) {
    autoport_proof::note_hit_for(kItemId, gfb - g_hits_reported);
    g_hits_reported = gfb;
  }
}
#endif  // __linux__ || __ANDROID__

}  // namespace

void pin_current_thread(Role role) {
  PinResult& r = (role == Role::Goal) ? g_pin_goal : g_pin_gl;
  r.attempted.store(1);
  detect_topology();

  // LE BRAS D'ABLATION, ET LUI SEUL. `armed_for` ne rend faux que si le harnais nomme CET item
  // avec armed=0 : le binaire de l'owner, lui, est toujours arme.
  if (!autoport_proof::armed_for(kItemId)) {
    r.attempted.store(2);  // 2 = desarme par le harnais, rien n'a ete pose
    return;
  }

#if defined(__linux__) || defined(__ANDROID__)
  if (g_heterogeneous && g_big_mask != 0) {
    cpu_set_t set;
    CPU_ZERO(&set);
    for (int c = 0; c < 64 && c < CPU_SETSIZE; c++) {
      if (g_big_mask & ((uint64_t)1 << c)) {
        CPU_SET(c, &set);
      }
    }
    errno = 0;
    if (sched_setaffinity(0, sizeof(set), &set) == 0) {
      r.affinity_ok.store(1);
    } else {
      r.affinity_errno.store(errno);
    }
    // Ce que le NOYAU rend, pas ce qu'on croit avoir pose : un cpuset d'application peut avoir
    // rogne l'ensemble demande sans que l'appel echoue.
    cpu_set_t got;
    CPU_ZERO(&got);
    uint64_t eff = 0;
    if (sched_getaffinity(0, sizeof(got), &got) == 0) {
      for (int c = 0; c < 64 && c < CPU_SETSIZE; c++) {
        if (CPU_ISSET(c, &got)) {
          eff |= (uint64_t)1 << c;
        }
      }
    }
    r.affinity_effective_mask.store(eff);
  }

  const pid_t tid = this_tid();
  errno = 0;
  const int before = getpriority(PRIO_PROCESS, tid);
  r.nice_before.store(errno == 0 ? before : 99);
  errno = 0;
  if (setpriority(PRIO_PROCESS, tid, kTargetNice) == 0) {
    r.nice_ok.store(1);
  }
  errno = 0;
  const int after = getpriority(PRIO_PROCESS, tid);
  r.nice_after.store(errno == 0 ? after : 99);
#endif
}

void goal_frame() {
#if defined(__linux__) || defined(__ANDROID__)
  detect_topology();
  const int c = sched_getcpu();
  if (c >= 0 && c < 64) {
    g_goal_core_mask.fetch_or((uint64_t)1 << c, std::memory_order_relaxed);
    g_goal_frames.fetch_add(1, std::memory_order_relaxed);
    if (g_big_mask & ((uint64_t)1 << c)) {
      g_goal_frames_big.fetch_add(1, std::memory_order_relaxed);
    }
  }
  // Le releve thermique n'a de sens que sur une machine heterogene, et il ne coute que deux
  // lectures de fichier toutes les cinq secondes — jamais par image.
  if (g_heterogeneous) {
    const int64_t t = now_ms();
    if (t >= g_therm_next_ms) {
      g_therm_next_ms = t + 5000;
      thermal_sample();
    }
  }
  static uint64_t s_since_publish = 0;
  if (++s_since_publish >= 60) {
    s_since_publish = 0;
    publish_now();
  }
#endif
}

void gl_frame() {
#if defined(__linux__) || defined(__ANDROID__)
  const int c = sched_getcpu();
  if (c >= 0 && c < 64) {
    g_gl_core_mask.fetch_or((uint64_t)1 << c, std::memory_order_relaxed);
    g_gl_frames.fetch_add(1, std::memory_order_relaxed);
    if (g_big_mask & ((uint64_t)1 << c)) {
      g_gl_frames_big.fetch_add(1, std::memory_order_relaxed);
    }
  }
#endif
}

void raise_pc_thread_priority(const char* thread_name) {
#if defined(__linux__) && !defined(__ANDROID__)
  if (!autoport_proof::armed_for(kItemId)) {
    return;
  }
  const pid_t tid = this_tid();
  errno = 0;
  if (setpriority(PRIO_PROCESS, tid, kTargetNice) == 0) {
    autoport_proof::publish("sched_pc_nice_applied", 1);
  } else {
    // Un bureau ordinaire refuse un nice negatif (RLIMIT_NICE). L'echec est PUBLIE : un
    // « applique » suppose vaudrait un faux vert sur une machine ou rien n'a change.
    autoport_proof::publish("sched_pc_nice_applied", 0);
    autoport_proof::publish("sched_pc_nice_errno", (uint64_t)errno);
  }
  errno = 0;
  const int after = getpriority(PRIO_PROCESS, tid);
  autoport_proof::publish("sched_pc_nice_after_plus100", (uint64_t)((errno == 0 ? after : 99) + 100));
  autoport_proof::publish_text("sched_pc_nice_thread", thread_name ? thread_name : "-");
#else
  (void)thread_name;
#endif
}

}  // namespace sched_affinity
