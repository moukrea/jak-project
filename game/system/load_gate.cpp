#include "game/system/load_gate.h"

#include <chrono>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <cstdlib>

#include "fmt/core.h"

namespace load_gate {
namespace {

std::mutex g_mutex;

// Levels the renderer says are drawable right now.
std::unordered_set<std::string> g_resident;

// True once the renderer has published ANY level. Until then the gate has no
// way to tell "not loaded yet" from "nobody is feeding me", so it opens.
// This is what makes the barrier fail-open on a build where the feed is
// missing: it can slow a scene down only on a runtime that actually reports
// residency.
bool g_feed_alive = false;

struct ArmedScene {
  std::chrono::steady_clock::time_point armed_at;
  int timeout_ms = 0;
};
std::unordered_map<std::string, ArmedScene> g_armed;

bool is_real_level_name(const char* n) {
  if (!n || !*n) {
    return false;
  }
  const std::string s(n);
  return s != "none" && s != "#f" && s != "#<symbol #f>";
}

// caller holds g_mutex
bool resident_locked(const std::string& n) {
  return g_resident.find(n) != g_resident.end();
}

int elapsed_ms(const std::chrono::steady_clock::time_point& t0) {
  return (int)std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now() - t0)
      .count();
}

}  // namespace

void mark_level_resident(const std::string& level_name) {
  if (level_name.empty()) {
    return;
  }
  std::lock_guard<std::mutex> lk(g_mutex);
  g_feed_alive = true;
  g_resident.insert(level_name);
}

void mark_level_evicted(const std::string& level_name) {
  std::lock_guard<std::mutex> lk(g_mutex);
  g_resident.erase(level_name);
}

bool level_is_resident(const char* level_name) {
  if (!is_real_level_name(level_name)) {
    return true;  // nothing asked for -> nothing to wait on
  }
  std::lock_guard<std::mutex> lk(g_mutex);
  if (!g_feed_alive) {
    return true;  // fail-open
  }
  return resident_locked(level_name);
}

bool wants_blocking_loads() {
  std::lock_guard<std::mutex> lk(g_mutex);
  // Prune barriers nobody came back for. A scene can be killed (state change,
  // process death) while it is suspended inside the wait loop, and then GOAL
  // never polls scene_ready again. Without this, one aborted cutscene would
  // leave the renderer on the blocking load path for the rest of the session.
  // Expiring here — on the C++ side, on the deadline the arm already carries —
  // means the cleanup cannot depend on GOAL cooperating.
  for (auto it = g_armed.begin(); it != g_armed.end();) {
    if (elapsed_ms(it->second.armed_at) >= it->second.timeout_ms) {
      fmt::print("LOADGATE expire scene={} (barrier abandoned, arm dropped)\n", it->first);
      it = g_armed.erase(it);
    } else {
      ++it;
    }
  }
  return !g_armed.empty();
}

int scene_ready(const char* scene, const char* level0, const char* level1, int timeout_ms) {
  const std::string scene_name = scene ? scene : "(unnamed)";
  const bool want0 = is_real_level_name(level0);
  const bool want1 = is_real_level_name(level1);
  const std::string l0 = want0 ? level0 : "";
  const std::string l1 = want1 ? level1 : "";

  // Clamp to something a human would accept staring at a black screen, and
  // never accept a non-positive deadline (that would be a barrier that can
  // never open on its own).
  if (timeout_ms < 250) {
    timeout_ms = 250;
  }
  if (timeout_ms > 30000) {
    timeout_ms = 30000;
  }

  std::lock_guard<std::mutex> lk(g_mutex);

  if (!want0 && !want1) {
    g_armed.erase(scene_name);
    return 1;
  }

  if (!g_feed_alive) {
    // Nobody publishes residency on this runtime. Do not hold the scene.
    g_armed.erase(scene_name);
    return 1;
  }

  auto it = g_armed.find(scene_name);
  if (it == g_armed.end()) {
    ArmedScene a;
    a.armed_at = std::chrono::steady_clock::now();
    a.timeout_ms = timeout_ms;
    it = g_armed.emplace(scene_name, a).first;
    fmt::print("LOADGATE arm scene={} levels={}{}{} timeout={}ms\n", scene_name, want0 ? l0 : "-",
               (want0 && want1) ? "," : "", want1 ? l1 : "", timeout_ms);
  }

  const bool have0 = !want0 || resident_locked(l0);
  const bool have1 = !want1 || resident_locked(l1);
  const int waited = elapsed_ms(it->second.armed_at);

  if (have0 && have1) {
    fmt::print("LOADGATE open scene={} waited={}ms reason=resident\n", scene_name, waited);
    g_armed.erase(it);
    return 1;
  }

  if (waited >= it->second.timeout_ms) {
    std::string missing;
    if (want0 && !have0) {
      missing += l0;
    }
    if (want1 && !have1) {
      if (!missing.empty()) {
        missing += ",";
      }
      missing += l1;
    }
    fmt::print("LOADGATE open scene={} waited={}ms reason=timeout missing={}\n", scene_name, waited,
               missing);
    g_armed.erase(it);
    return 1;
  }

  return 0;
}

void scene_release(const char* scene) {
  const std::string scene_name = scene ? scene : "(unnamed)";
  std::lock_guard<std::mutex> lk(g_mutex);
  g_armed.erase(scene_name);
}

// ================================================================================================
// Gloading-screen — CADENCE REELLE DE L'ECRAN DE CHARGEMENT (voir load_gate.h pour le trou que
// ceci bouche) ET DECOUPAGE DU TRAVAIL GOAL.
// ================================================================================================
namespace {

std::mutex g_ls_mutex;

// Un episode s'ouvre au premier tick et se ferme soit sur `loading_screen_end`, soit quand plus
// aucun tick n'est arrive depuis kEpisodeGapMs — ce second cas rattrape un site d'attente tue sans
// relachement, qui sinon garderait l'episode ouvert et melangerait deux chargements.
constexpr double kEpisodeGapMs = 1500.0;

struct LsSecond {
  int frames = 0;
  double worst_ms = 0.0;
};

struct LsEpisode {
  bool open = false;
  int index = 0;
  int hold_mask = 0;
  std::chrono::steady_clock::time_point start{};
  std::chrono::steady_clock::time_point last{};
  int frames = 0;
  double worst_ms = 0.0;
  double worst_at_ms = 0.0;
  std::vector<LsSecond> seconds;
};
LsEpisode g_ls;
int g_ls_next_index = 1;

// caller holds g_ls_mutex
void ls_flush_locked() {
  if (!g_ls.open) {
    return;
  }
  const double dur_ms =
      std::chrono::duration<double, std::milli>(g_ls.last - g_ls.start).count();
  const double fps = dur_ms > 0.0 ? (1000.0 * (g_ls.frames - 1) / dur_ms) : 0.0;
  fmt::print(
      "LOADSCREEN-FRAME episode={} masque={} images={} duree_ms={:.1f} fps_moyen={:.2f} "
      "ecart_max_ms={:.1f} a_t_ms={:.0f}\n",
      g_ls.index, g_ls.hold_mask, g_ls.frames, dur_ms, fps, g_ls.worst_ms, g_ls.worst_at_ms);
  // UNE LIGNE PAR SECONDE. « Une moyenne sur dix secondes noie un gel d'une seconde » — c'est la
  // phrase de l'owner, et c'est pour ca que la moyenne ne suffit pas. La DERNIERE seconde est
  // republiee a part : c'est celle qu'il designe explicitement.
  for (size_t i = 0; i < g_ls.seconds.size(); i++) {
    fmt::print("LOADSCREEN-FRAME-S episode={} s={} images={} fps={} ecart_max_ms={:.1f}\n",
               g_ls.index, (int)i, g_ls.seconds[i].frames, g_ls.seconds[i].frames,
               g_ls.seconds[i].worst_ms);
  }
  if (!g_ls.seconds.empty()) {
    const LsSecond& last = g_ls.seconds.back();
    fmt::print("LOADSCREEN-FRAME-FIN episode={} derniere_seconde_images={} ecart_max_ms={:.1f}\n",
               g_ls.index, last.frames, last.worst_ms);
  }
  g_ls.open = false;
  g_ls.seconds.clear();
}

// ---- tranche de travail GOAL ----
// Budget en millisecondes. 0 = DESARME, comportement d'avant au bit pres. Lu une seule fois, au
// premier appel, pour que l'ablation porte sur toute la course et pas sur une partie.
// UN BUDGET PAR EMPLACEMENT, ET LEURS DEFAUTS NE SONT PAS LES MEMES.
//
//   emplacement 0 — `level-update-after-load` (le LOGIN d'un niveau). Le decoupage y est le
//     mecanisme d'ORIGINE : le code du jeu porte encore l'ancienne garde de temps, en commentaire,
//     avec sa sortie `cfg-78`. La reprise a la frame suivante est donc prevue par construction.
//     DEFAUT : 6 ms, arme.
//
//   emplacement 1 — la boucle `while` sans `suspend` de `update! load-state`. Ce decoupage-la
//     n'existe PAS dans le jeu d'origine : c'est une invention, et la MESURE l'a refutee. Course
//     x86 du 2026-08-30, transition `village1+beach -> snow+village3` (aucun niveau commun, le
//     seul cas qui arme cette boucle) : avec l'emplacement 1 arme, `gk` MEURT en silence ~150 ms
//     apres `Adding level village3`, deux fois sur deux ; desarme, la meme transition passe et
//     publie son episode. Le gel qu'elle porte est reel (1 278,9 ms mesurees) mais le correctif
//     essaye est PIRE que le defaut : « une resolution pire que le clip est pire que rien ».
//     DEFAUT : 0, DESARME. `OG_GOAL_LOOP_SLICE_MS` permet de le rejouer sans changer de binaire.
double goal_slice_budget_ms(int slot) {
  static double v_login = []() {
    if (const char* e = std::getenv("OG_GOAL_SLICE_MS")) {
      return atof(e);
    }
    return 6.0;
  }();
  static double v_loop = []() {
    if (const char* e = std::getenv("OG_GOAL_LOOP_SLICE_MS")) {
      return atof(e);
    }
    return 0.0;
  }();
  return slot == 1 ? v_loop : v_login;
}

constexpr int kSliceSlots = 4;
std::chrono::steady_clock::time_point g_slice_start[kSliceSlots]{};
bool g_slice_started[kSliceSlots] = {false, false, false, false};

}  // namespace

void loading_screen_tick(int hold_mask) {
  const auto now = std::chrono::steady_clock::now();
  std::lock_guard<std::mutex> lk(g_ls_mutex);
  if (g_ls.open) {
    const double gap = std::chrono::duration<double, std::milli>(now - g_ls.last).count();
    if (gap > kEpisodeGapMs) {
      // Plus personne n'a peint depuis longtemps : l'episode precedent est fini, celui-ci est
      // nouveau. On ne compte SURTOUT pas ce trou comme un ecart de l'episode suivant.
      ls_flush_locked();
    }
  }
  if (!g_ls.open) {
    g_ls.open = true;
    g_ls.index = g_ls_next_index++;
    g_ls.hold_mask = hold_mask;
    g_ls.start = now;
    g_ls.last = now;
    g_ls.frames = 1;
    g_ls.worst_ms = 0.0;
    g_ls.worst_at_ms = 0.0;
    g_ls.seconds.assign(1, LsSecond{1, 0.0});
    return;
  }
  const double gap = std::chrono::duration<double, std::milli>(now - g_ls.last).count();
  const double t = std::chrono::duration<double, std::milli>(now - g_ls.start).count();
  g_ls.hold_mask |= hold_mask;
  g_ls.frames++;
  if (gap > g_ls.worst_ms) {
    g_ls.worst_ms = gap;
    g_ls.worst_at_ms = t;
  }
  const size_t sec = (size_t)(t / 1000.0);
  while (g_ls.seconds.size() <= sec) {
    g_ls.seconds.push_back(LsSecond{});
  }
  g_ls.seconds[sec].frames++;
  if (gap > g_ls.seconds[sec].worst_ms) {
    g_ls.seconds[sec].worst_ms = gap;
  }
  g_ls.last = now;
}

void loading_screen_end() {
  std::lock_guard<std::mutex> lk(g_ls_mutex);
  ls_flush_locked();
}

void goal_slice_begin(int slot) {
  if (slot < 0 || slot >= kSliceSlots) {
    return;
  }
  g_slice_start[slot] = std::chrono::steady_clock::now();
  g_slice_started[slot] = true;
}

int goal_slice_expired(int slot) {
  if (slot < 0 || slot >= kSliceSlots) {
    return 0;
  }
  const double budget = goal_slice_budget_ms(slot);
  if (budget <= 0.0 || !g_slice_started[slot]) {
    return 0;
  }
  const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() -
                                                              g_slice_start[slot])
                        .count();
  return ms >= budget ? 1 : 0;
}

void reset_for_test() {
  std::lock_guard<std::mutex> lk(g_mutex);
  g_resident.clear();
  g_armed.clear();
  g_feed_alive = false;
}

}  // namespace load_gate
