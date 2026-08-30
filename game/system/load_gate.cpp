#include "game/system/load_gate.h"

#include <atomic>
#include <chrono>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <algorithm>
#include <cstdio>
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

// « L'ecran couvre-t-il cette image ? » (voir load_gate.h). Declare ICI parce que
// `loading_screen_tick`, qui l'incremente, est definie bien avant les deux accesseurs.
// Le compteur est ecrit par le thread GOAL et lu par le thread de rendu : atomique.
// Les deux autres n'appartiennent qu'au thread de rendu.
std::atomic<uint64_t> g_ls_cover_tick{0};
uint64_t g_ls_cover_seen = 0;
bool g_ls_covering = false;

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
  // GOAL peint l'ecran a cette image (main.gc:1529, juste avant `loading-screen-draw`). Un masque
  // non nul = l'ecran est TENU, donc opaque par-dessus le monde. Hors du verrou : ce compteur ne
  // participe a aucune des grandeurs protegees par `g_ls_mutex`.
  if (hold_mask != 0) {
    g_ls_cover_tick.fetch_add(1, std::memory_order_relaxed);
  }
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

// ================================================================================================
// Gloading-screen-window — L'ENCADREMENT (voir load_gate.h pour le defaut que ceci mesure).
// ================================================================================================
namespace {

std::mutex g_win_mutex;

// Un instant NON MARQUE reste `absent` : voir load_gate.h, un nombre manquant qui se lit comme un
// nombre passerait la comparaison d'ordre par accident.
struct LsMark {
  bool set = false;
  double ms = 0.0;
  void first(double v) {
    if (!set) {
      set = true;
      ms = v;
    }
  }
  void last(double v) {
    set = true;
    ms = v;
  }
};

struct LsWindow {
  bool open = false;
  std::string label;
  std::chrono::steady_clock::time_point t0{};
  std::chrono::steady_clock::time_point last_frame{};
  bool have_last_frame = false;
  // L'ensemble de reference : les niveaux DESSINABLES a l'instant de l'ouverture. Il se remplit
  // pendant la premiere image, puis se fige.
  bool baseline_open = true;
  std::unordered_set<std::string> baseline;
  std::unordered_set<std::string> incoming;
  LsMark up, first_draw_in, last_active, down, actors_settled;
  // « il reste des acteurs a faire naitre » a ete VU au moins une fois dans cette fenetre. Sans
  // ce temoin, un balayage complet des la premiere image (le cas normal hors transition) serait
  // lu comme « la naissance vient de se terminer » -- un instant fabrique.
  bool actors_pending_seen = false;
  // Diagnostic BRUT du temoin d'acteurs : sans lui, un `t_last_active` qui n'inclut pas les
  // acteurs est indistinguable de « il n'y avait rien a faire naitre » et de « le temoin est
  // casse ». Deux comptes, publies a la fermeture.
  int frames_spawn_on = 0;
  int frames_sweep_complete = 0;
  bool was_held = false;
  // Images ou le monde ENTRANT est dessine sans que RIEN ne le couvre : ni l'ecran de chargement,
  // ni le noir du moteur. C'est, litteralement, le defaut D4/D7 de l'owner (« on voit directement
  // l'interieur de la hutte »). Comptees sur [t_first_draw_in, t_last_active], c'est-a-dire
  // pendant que la scene entrante est APPARUE mais pas encore COMPLETE.
  // Un niveau ENTRANT a-t-il emis de la geometrie a l'image en cours ? Pose par les rapports de
  // niveau, consomme et remis a zero par le rapport d'image.
  bool frame_incoming_drawn = false;
  int frames = 0;
  int held_frames = 0;
  // Les instants de TOUTES les images de la fenetre. On ne peut pas calculer le pire ecart au vol :
  // la fenetre reste ouverte apres la transition (le harnais la ferme), et des images de jeu
  // ordinaire y entreraient. Le pire ecart se calcule donc A LA FERMETURE, borne a la PARTIE
  // ACTIVE de la fenetre — jusqu'au dernier evenement marque. Les deux chiffres sont publies :
  // celui qui porte le verdict, et celui de la fenetre entiere.
  std::vector<double> frame_t;
  // Un octet d'etat par image : bit 0 = ecran de chargement pose, bit 1 = image noire (par l'un
  // OU l'autre des deux mecanismes), bit 2 = un niveau ENTRANT a emis de la geometrie.
  // Le compte d'images DECOUVERTES ne peut pas se faire au vol : sa borne haute est
  // `t_last_active`, qui n'est connue qu'a la fermeture -- l'accumuler en direct comptait les
  // dizaines de secondes de jeu ordinaire qui suivent la transition (mesure : 1 613 images sur
  // `teleport-sagehut`, dont la quasi-totalite est du jeu normal apres coup).
  std::vector<unsigned char> frame_flag;
};
LsWindow g_win;
constexpr size_t kMaxFrameStamps = 40000;

double ls_now_ms() {
  return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - g_win.t0)
      .count();
}

const char* ls_fmt(const LsMark& m, char* buf, size_t n) {
  if (!m.set) {
    snprintf(buf, n, "absent");
  } else {
    snprintf(buf, n, "%.1f", m.ms);
  }
  return buf;
}

// caller holds g_win_mutex
void ls_window_close_locked(const char* why) {
  if (!g_win.open) {
    return;
  }
  char a[32], b[32], c[32], d[32];
  const double dur = ls_now_ms();
  // Fin de la PARTIE ACTIVE : le dernier instant marque. Au-dela, ce sont des images de jeu
  // ordinaire et elles n'ont rien a faire dans un verdict sur un chargement.
  // LES ACTEURS SONT DES ELEMENTS ENTRANTS EUX AUSSI, et ce sont EUX que l'owner voit apparaitre
  // apres coup (D3 : « il disparait avant que tous les elements de la scene soient affiches [...]
  // on a du pop-in »). Un niveau passe 'active bien avant que ses acteurs existent : s'arreter au
  // niveau rendrait le defaut invisible. `t_last_active` est donc le PLUS TARD des deux.
  if (g_win.actors_settled.set) {
    g_win.last_active.last(std::max(g_win.last_active.set ? g_win.last_active.ms : 0.0,
                                    g_win.actors_settled.ms));
  }
  double t_end = 0.0;
  for (const LsMark* m : {&g_win.up, &g_win.first_draw_in, &g_win.last_active, &g_win.down}) {
    if (m->set && m->ms > t_end) {
      t_end = m->ms;
    }
  }
  double worst = 0.0, worst_at = 0.0, worst_tot = 0.0, worst_tot_at = 0.0;
  int frames_actifs = 0;
  // LE COMPTE QUI PORTE D4/D7, borne a la periode ou la scene entrante est APPARUE mais pas encore
  // COMPLETE : [t_first_draw_in, t_last_active]. Hors de cette periode, une image decouverte est
  // du jeu ordinaire et n'a rien a faire dans un verdict sur un chargement.
  int decouvertes = 0, noir_seul = 0, couvertes = 0;
  const double t_a = g_win.first_draw_in.set ? g_win.first_draw_in.ms : 0.0;
  const double t_b = g_win.last_active.set ? g_win.last_active.ms : -1.0;
  for (size_t i = 0; i < g_win.frame_t.size() && i < g_win.frame_flag.size(); i++) {
    const double ft = g_win.frame_t[i];
    if (ft < t_a || ft > t_b) {
      continue;
    }
    const unsigned char f = g_win.frame_flag[i];
    if (!(f & 4)) {
      continue;  // aucun entrant dessine a cette image : rien a couvrir
    }
    if (f & 1) {
      couvertes++;
    } else if (f & 2) {
      noir_seul++;
    } else {
      decouvertes++;
    }
  }
  for (size_t i = 1; i < g_win.frame_t.size(); i++) {
    const double gap = g_win.frame_t[i] - g_win.frame_t[i - 1];
    if (gap > worst_tot) {
      worst_tot = gap;
      worst_tot_at = g_win.frame_t[i];
    }
    if (g_win.frame_t[i] <= t_end) {
      frames_actifs++;
      if (gap > worst) {
        worst = gap;
        worst_at = g_win.frame_t[i];
      }
    }
  }
  fmt::print(
      "LSWIN transition={} t_up={} t_first_draw_in={} t_last_active={} t_down={} images={} "
      "images_couvertes={} duree_ms={:.1f} raison={}\n",
      g_win.label, ls_fmt(g_win.up, a, sizeof(a)), ls_fmt(g_win.first_draw_in, b, sizeof(b)),
      ls_fmt(g_win.last_active, c, sizeof(c)), ls_fmt(g_win.down, d, sizeof(d)), g_win.frames,
      g_win.held_frames, dur, why ? why : "-");
  // Les deux ECARTS SIGNES, publies a part : c'est leur SIGNE qui porte le verdict, et un lecteur
  // ne doit pas avoir a soustraire deux colonnes a la main pour le voir.
  if (g_win.up.set && g_win.first_draw_in.set) {
    fmt::print("LSWIN-MARGE transition={} pose_ms={:.1f} (>=0 : l'ecran est pose AVANT le premier "
               "dessin entrant)\n",
               g_win.label, g_win.first_draw_in.ms - g_win.up.ms);
  }
  if (g_win.down.set && g_win.last_active.set) {
    fmt::print("LSWIN-MARGE transition={} levee_ms={:.1f} (>=0 : l'ecran se leve APRES le dernier "
               "entrant dessinable)\n",
               g_win.label, g_win.down.ms - g_win.last_active.ms);
  }
  fmt::print("LSWIN-ACTEURS-BRUT transition={} images_spawn_on={} images_balayage_complet={} "
             "attente_vue={} marque={}\n",
             g_win.label, g_win.frames_spawn_on, g_win.frames_sweep_complete,
             g_win.actors_pending_seen ? 1 : 0, g_win.actors_settled.set ? 1 : 0);
  fmt::print("LSWIN-DECOUVERT transition={} fenetre_ms=[{:.1f},{:.1f}] images_entrantes={} "
             "couvertes_ecran={} noir_seul={} DECOUVERTES={}\n",
             g_win.label, t_a, t_b, decouvertes + noir_seul + couvertes, couvertes, noir_seul,
             decouvertes);
  if (g_win.actors_settled.set) {
    fmt::print("LSWIN-ACTEURS-FIN transition={} t_ms={:.1f} apres_levee_ms={:.1f} (>0 : des acteurs "
               "naissent APRES la levee -- c'est le pop-in D3)\n",
               g_win.label, g_win.actors_settled.ms,
               g_win.down.set ? (g_win.actors_settled.ms - g_win.down.ms) : 0.0);
  }
  fmt::print("LSFRAME-BRUT transition={} worst_gap_ms={:.1f} worst_at_ms={:.1f} images={} "
             "t_fin_actif_ms={:.1f} worst_gap_fenetre_ms={:.1f} a_ms={:.1f} images_total={} "
             "duree_ms={:.1f}\n",
             g_win.label, worst, worst_at, frames_actifs + 1, t_end, worst_tot, worst_tot_at,
             g_win.frames, dur);
  g_win.open = false;
  g_win.baseline.clear();
  g_win.incoming.clear();
  g_win.frame_t.clear();
  g_win.frame_t.shrink_to_fit();
  g_win.frame_flag.clear();
  g_win.frame_flag.shrink_to_fit();
}

}  // namespace

void loading_window_open(const char* transition) {
  std::lock_guard<std::mutex> lk(g_win_mutex);
  if (g_win.open) {
    ls_window_close_locked("remplacee");
  }
  g_win = LsWindow{};
  g_win.open = true;
  g_win.label = transition ? transition : "(sans-nom)";
  g_win.t0 = std::chrono::steady_clock::now();
  g_win.baseline_open = true;
  fmt::print("LSWIN-OUVRE transition={}\n", g_win.label);
}

void loading_window_level(const char* level_name, int drawable) {
  if (!level_name || !*level_name) {
    return;
  }
  std::lock_guard<std::mutex> lk(g_win_mutex);
  if (!g_win.open || !drawable) {
    return;
  }
  const std::string n(level_name);
  if (g_win.baseline_open) {
    g_win.baseline.insert(n);
    return;
  }
  if (g_win.baseline.count(n)) {
    return;
  }
  // Un entrant DEJA vu reste entrant : c'est ce qui permet de compter, image par image, celles ou
  // le monde entrant est dessine sans etre couvert.
  g_win.frame_incoming_drawn = true;
  if (g_win.incoming.count(n)) {
    return;
  }
  g_win.incoming.insert(n);
  const double t = ls_now_ms();
  g_win.first_draw_in.first(t);
  g_win.last_active.last(t);
  fmt::print("LSWIN-ENTRANT transition={} niveau={} t_ms={:.1f} rang={}\n", g_win.label, n, t,
             (int)g_win.incoming.size());
}

void loading_window_frame(int held, int black) {
  std::lock_guard<std::mutex> lk(g_win_mutex);
  if (!g_win.open) {
    return;
  }
  const auto now = std::chrono::steady_clock::now();
  const double t = std::chrono::duration<double, std::milli>(now - g_win.t0).count();
  g_win.last_frame = now;
  g_win.have_last_frame = true;
  g_win.frames++;
  if (g_win.frame_t.size() < kMaxFrameStamps) {
    g_win.frame_t.push_back(t);
    g_win.frame_flag.push_back((unsigned char)((held ? 1 : 0) | (black ? 2 : 0) |
                                               (g_win.frame_incoming_drawn ? 4 : 0)));
  }
  const bool h = held != 0;
  if (h) {
    g_win.held_frames++;
    g_win.up.first(t);
  } else if (g_win.was_held) {
    // premiere image DECOUVERTE apres une image couverte : c'est l'instant ou le joueur voit a
    // nouveau le monde. On garde la DERNIERE levee de la fenetre.
    g_win.down.last(t);
  }
  // LOCALISER LE GEL DANS LE TEMPS DU LOG. Un maximum publie a la fermeture dit COMBIEN ; il ne
  // dit pas OU regarder dans une trace de 75 secondes. Une ligne par ecart au-dessus du seuil, et
  // rien en regime normal.
  if (g_win.frame_t.size() >= 2) {
    const double gap = t - g_win.frame_t[g_win.frame_t.size() - 2];
    if (gap > 60.0) {
      fmt::print("LSWIN-GEL transition={} t_ms={:.1f} ecart_ms={:.1f} ecran={} noir={}\n",
                 g_win.label, t, gap, h ? 1 : 0, black ? 1 : 0);
    }
  }
  g_win.was_held = h;
  g_win.frame_incoming_drawn = false;
  // La ligne de reference se fige a la fin de la premiere image de la fenetre.
  g_win.baseline_open = false;
}

void loading_window_actors(int spawn_on, int sweep_complete) {
  std::lock_guard<std::mutex> lk(g_win_mutex);
  if (!g_win.open || g_win.baseline_open) {
    return;
  }
  // « IL RESTE DES ACTEURS A FAIRE NAITRE » NE SE LIT PAS SEULEMENT SUR UN BALAYAGE INCOMPLET.
  // Mesure x86 du 2026-08-30 : avec `birth-max` a 1000, tout le niveau nait dans UNE image, le
  // balayage n'est donc JAMAIS incomplet et un temoin base sur lui ne se serait jamais arme --
  // il aurait rendu « pas de pop-in » sur la transition meme ou l'owner en voit. `*spawn-actors*`
  // a #f est l'autre forme, et la plus frequente : pendant tout un chargement de partie
  // (game-info.gc:234) AUCUN acteur ne peut naitre, ce qui est litteralement « il en reste ».
  if (spawn_on) {
    g_win.frames_spawn_on++;
  }
  if (sweep_complete) {
    g_win.frames_sweep_complete++;
  }
  if (!spawn_on || !sweep_complete) {
    g_win.actors_pending_seen = true;
    return;
  }
  if (g_win.actors_pending_seen && !g_win.actors_settled.set) {
    const double t = ls_now_ms();
    g_win.actors_settled.first(t);
    fmt::print("LSWIN-ACTEURS transition={} t_ms={:.1f} (dernier acteur du niveau entrant ne)\n",
               g_win.label, t);
  }
}

void loading_window_note(const char* what, int value) {
  std::lock_guard<std::mutex> lk(g_win_mutex);
  if (!g_win.open) {
    return;
  }
  fmt::print("LSWIN-NOTE transition={} t_ms={:.1f} quoi={} v={}\n", g_win.label, ls_now_ms(),
             what ? what : "-", value);
}

// ---- L'ECRAN COUVRE-T-IL CETTE IMAGE ? (voir load_gate.h) -------------------
// Le compteur est incremente par le thread GOAL (`loading_screen_tick`) et lu par le thread de
// rendu : il est atomique. Le RENDU, lui, ne compare que des valeurs qui lui appartiennent
// (`g_ls_cover_seen`, `g_ls_covering`), toutes deux touchees uniquement dans
// `loading_screen_render_begin`/`loading_screen_is_covering`, donc sur le seul thread de rendu.
void loading_screen_render_begin() {
  const uint64_t cur = g_ls_cover_tick.load(std::memory_order_relaxed);
  // L'ecran couvre cette image SI ET SEULEMENT SI GOAL l'a peint depuis la derniere image rendue.
  // Un compteur, pas un drapeau retenu : un drapeau resterait arme si la fin d'episode n'etait pas
  // signalee, et l'herbe disparaitrait pour de bon. Ici, des que GOAL cesse de peindre l'ecran,
  // le compteur cesse d'avancer et l'image suivante redessine tout.
  g_ls_covering = (cur != g_ls_cover_seen);
  g_ls_cover_seen = cur;
}

bool loading_screen_is_covering() {
  return g_ls_covering;
}

bool loading_window_is_open() {
  std::lock_guard<std::mutex> lk(g_win_mutex);
  return g_win.open;
}

void loading_window_close(const char* why) {
  std::lock_guard<std::mutex> lk(g_win_mutex);
  ls_window_close_locked(why);
}

void reset_for_test() {
  std::lock_guard<std::mutex> lk(g_mutex);
  g_resident.clear();
  g_armed.clear();
  g_feed_alive = false;
}

}  // namespace load_gate
