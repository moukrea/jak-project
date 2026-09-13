#include "game/system/overlap_census.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

#include "common/goal_constants.h"

#include "game/graphics/gfx.h"
#include "game/graphics/refset.h"
#include "game/runtime.h"
#include "game/system/autoport_proof.h"

// Le site de l'item, enregistre au CHARGEMENT : c'est ce qui separe « aucun site compile ici »
// de « site compile, jamais atteint ». Au niveau namespace, jamais dans une fonction.
AUTOPORT_FEATURE_SITE("perf-goal-gl-overlap");

namespace overlap_census {
namespace {

constexpr const char* kItemId = "perf-goal-gl-overlap";

// Le plancher de vacuite. La porte de `validators/generic.sh` exige deja 300 images dessinees ;
// en dessous, la course n'a pas de quoi dire si le recouvrement a eu lieu, et `overlap_vacuous`
// resterait un faux rouge sur une course ecourtee. Au-dessus, un `goal_ahead_max` nul veut dire
// que le binaire a SERIALISE : c'est un defaut, pas un succes.
constexpr uint64_t kVacuityFloor = 300;

// Le nombre de plages surveillees qu'une image peut inscrire. Un merc complet inscrit une plage
// par os (<= 128) et par paquet ; 65536 couvre une scene chargee avec de la marge. Le
// depassement n'est PAS silencieux : il monte `overlap_watch_overflow`, que le rapport doit
// lire avant de croire un zero.
constexpr size_t kMaxWatch = 65536;

const char* kKindNames[kKindCount] = {"bones", "merc_mod", "tex_upload", "tex_anim", "ocean"};

uint64_t fnv1a(const uint8_t* p, size_t n) {
  uint64_t h = 1469598103934665603ull;
  size_t i = 0;
  // Huit octets a la fois : l'empreinte doit couter moins que la lecture qu'elle surveille.
  for (; i + 8 <= n; i += 8) {
    uint64_t w;
    std::memcpy(&w, p + i, 8);
    h = (h ^ w) * 1099511628211ull;
  }
  for (; i < n; i++) {
    h = (h ^ p[i]) * 1099511628211ull;
  }
  return h;
}

struct Watch {
  uint32_t addr;
  uint32_t len;
  uint64_t hash;
  uint8_t kind;
};

struct State {
  // ─── partage entre le fil GOAL (publication) et le fil GL (rendu) ────────────────────────
  // Le passage de main est deja serialise par le verrou de la chaine chez l'appelant ; ce mutex
  // ne protege que la poignee de scalaires que ce module garde, et il est pris une fois par
  // image, jamais dans la boucle de lecture.
  std::mutex handoff;
  uint64_t published_hash = 0;
  const void* published_copy = nullptr;
  uint32_t published_bytes = 0;
  int64_t published_lf = -1;

  // ─── fil GL seul ─────────────────────────────────────────────────────────────────────────
  std::vector<Watch> watch;
  bool in_render = false;
  int64_t render_lf = -1;
  uint64_t render_chain_hash = 0;
  const void* render_copy = nullptr;
  uint32_t render_bytes = 0;
  std::thread::id render_thread{};

  // ─── comptes publies ─────────────────────────────────────────────────────────────────────
  std::atomic<uint64_t> frames{0};
  std::atomic<uint64_t> frames_overlapped{0};
  std::atomic<uint64_t> chain_mutated{0};
  std::atomic<uint64_t> oob_changed{0};
  std::atomic<uint64_t> stamp_mismatch{0};
  std::atomic<uint64_t> goal_ahead_max{0};
  std::atomic<uint64_t> watch_ranges_total{0};
  std::atomic<uint64_t> watch_ranges_max{0};
  std::atomic<uint64_t> watch_bytes_max{0};
  std::atomic<uint64_t> watch_overflow{0};
  std::atomic<uint64_t> oob_rejected{0};
  std::atomic<uint64_t> foreign_thread{0};
  std::atomic<uint64_t> release_total{0};
  std::atomic<uint64_t> release_in_flight{0};
  std::atomic<uint64_t> settings_stamp_miss{0};
  std::atomic<uint64_t> settings_snapshots{0};
  std::atomic<uint64_t> kind_seen[kKindCount] = {};
  std::atomic<uint64_t> kind_changed[kKindCount] = {};
  std::atomic<bool> overlap_active{false};
};

State& st() {
  static State s;
  return s;
}

// Le nom de la derniere famille prise en faute, ou "-". `publish_text` garde la DERNIERE valeur
// publiee : une famille nommee une fois resterait a l'ecran a cote d'un `overlap_oob_changed=0`
// si on ne republiait pas l'absence.
void publish_worst_kind() {
  const char* worst = "-";
  uint64_t best = 0;
  for (int k = 0; k < kKindCount; k++) {
    const uint64_t v = st().kind_changed[k].load(std::memory_order_relaxed);
    if (v > best) {
      best = v;
      worst = kKindNames[k];
    }
  }
  autoport_proof::publish_text("overlap_worst_kind", worst);
}

}  // namespace

// Compte une estampille de reglages manquee. Le fil de rendu a demande l'image N et aucun des
// deux emplacements ne la portait : les deux ont ete ecrases, donc le fil GOAL a pris plus d'une
// image d'avance sur le rendu. C'est un defaut de la course, pas un aleas de mesure.
void note_goal_release(bool render_in_flight) {
  if (!measuring()) {
    return;
  }
  st().release_total.fetch_add(1, std::memory_order_relaxed);
  if (render_in_flight) {
    st().release_in_flight.fetch_add(1, std::memory_order_relaxed);
  }
}

void note_settings_stamp_miss() {
  st().settings_stamp_miss.fetch_add(1, std::memory_order_relaxed);
}
void note_settings_snapshot() {
  st().settings_snapshots.fetch_add(1, std::memory_order_relaxed);
}

bool measuring() {
  // Lu une fois : `feature_is` interroge l'environnement / une propriete systeme.
  static const bool s_on = autoport_proof::feature_is(kItemId);
  return s_on;
}

void set_overlap_active(bool active) {
  if (!measuring()) {
    return;
  }
  st().overlap_active.store(active, std::memory_order_relaxed);
}

void chain_published(const void* copy, uint32_t bytes, int64_t logic_frame) {
  if (!measuring() || !copy) {
    return;
  }
  const uint64_t h = fnv1a((const uint8_t*)copy, bytes);
  std::lock_guard<std::mutex> lock(st().handoff);
  st().published_hash = h;
  st().published_copy = copy;
  st().published_bytes = bytes;
  st().published_lf = logic_frame;
}

void render_begin(int64_t logic_frame) {
  if (!measuring()) {
    return;
  }
  auto& s = st();
  s.watch.clear();
  s.render_thread = std::this_thread::get_id();
  s.render_lf = logic_frame;
  {
    std::lock_guard<std::mutex> lock(s.handoff);
    s.render_chain_hash = s.published_hash;
    s.render_copy = s.published_copy;
    s.render_bytes = s.published_bytes;
    // L'estampille que le producteur a apposee a la chaine PUBLIEE doit etre celle que le
    // consommateur croit dessiner. Un ecart veut dire que le passage de main a saute une image.
    if (logic_frame >= 0 && s.published_lf >= 0 && logic_frame != s.published_lf) {
      s.stamp_mismatch.fetch_add(1, std::memory_order_relaxed);
    }
  }
  s.in_render = true;
}

void note_read(int kind, uint32_t ee_addr, uint32_t len) {
  auto& s = st();
  if (!measuring() || !s.in_render || len == 0) {
    return;
  }
  if (std::this_thread::get_id() != s.render_thread) {
    // Une lecture faite par un AUTRE fil que celui qui rend n'appartient pas a cette fenetre :
    // la compter fabriquerait un defaut que le recouvrement n'a pas cause. Elle est ecartee ET
    // chiffree — un seau exclu qu'on ne publie pas est un seau qu'on n'a pas mesure.
    s.foreign_thread.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  if (!g_ee_main_mem || (uint64_t)ee_addr + len > (uint64_t)EE_MAIN_MEM_SIZE) {
    s.oob_rejected.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  if (s.watch.size() >= kMaxWatch) {
    s.watch_overflow.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  if (kind < 0 || kind >= kKindCount) {
    s.oob_rejected.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  s.kind_seen[kind].fetch_add(1, std::memory_order_relaxed);
  s.watch.push_back(
      Watch{ee_addr, len, fnv1a(g_ee_main_mem + ee_addr, len), (uint8_t)kind});
}

void render_end() {
  auto& s = st();
  if (!measuring() || !s.in_render) {
    return;
  }
  s.in_render = false;

  // (1) La copie de chaine a-t-elle bouge sous le rendu ?
  if (s.render_copy && s.render_bytes) {
    if (fnv1a((const uint8_t*)s.render_copy, s.render_bytes) != s.render_chain_hash) {
      s.chain_mutated.fetch_add(1, std::memory_order_relaxed);
    }
  }

  // (2) Les plages hors chaine, relues telles qu'elles sont MAINTENANT.
  uint64_t bytes = 0;
  for (const auto& w : s.watch) {
    bytes += w.len;
    if (fnv1a(g_ee_main_mem + w.addr, w.len) != w.hash) {
      s.oob_changed.fetch_add(1, std::memory_order_relaxed);
      s.kind_changed[w.kind].fetch_add(1, std::memory_order_relaxed);
    }
  }
  const uint64_t n = s.watch.size();
  s.watch_ranges_total.fetch_add(n, std::memory_order_relaxed);
  if (n > s.watch_ranges_max.load(std::memory_order_relaxed)) {
    s.watch_ranges_max.store(n, std::memory_order_relaxed);
  }
  if (bytes > s.watch_bytes_max.load(std::memory_order_relaxed)) {
    s.watch_bytes_max.store(bytes, std::memory_order_relaxed);
  }

  // (3) LE TEMOIN QUI REND LE ZERO FALSIFIABLE : de combien d'images de logique le fil GOAL
  // est-il en avance sur ce que le rendu vient de dessiner ? Sous un recouvrement reel il
  // construit deja l'image suivante, donc au moins 1 ; serialise, 0.
  const int64_t goal_now = refset::current_logic_frame();
  if (goal_now >= 0 && s.render_lf >= 0 && goal_now > s.render_lf) {
    const uint64_t ahead = (uint64_t)(goal_now - s.render_lf);
    if (ahead > s.goal_ahead_max.load(std::memory_order_relaxed)) {
      s.goal_ahead_max.store(ahead, std::memory_order_relaxed);
    }
  }

  const uint64_t frames = s.frames.fetch_add(1, std::memory_order_relaxed) + 1;
  const bool active = s.overlap_active.load(std::memory_order_relaxed);
  if (active) {
    s.frames_overlapped.fetch_add(1, std::memory_order_relaxed);
    // `hits_means` de l'item : images rendues en recouvrement. No-op quand le harnais desarme,
    // ce qui donne `hits=0` au bras d'ablation.
    autoport_proof::note_hit_for(kItemId, 1);
  }

  // (4) La vacuite, lue sur le DISCRIMINANT. Une course assez longue qui n'a jamais relache le
  // fil GOAL pendant qu'un rendu etait en vol n'a pas recouvert : son zero de defauts est celui
  // d'un binaire serialise, il ne dit rien de la course corrigee. C'est un defaut.
  const uint64_t release_in_flight = s.release_in_flight.load(std::memory_order_relaxed);
  const uint64_t vacuous = (frames >= kVacuityFloor && release_in_flight == 0) ? 1 : 0;

  const uint64_t chain_mutated = s.chain_mutated.load(std::memory_order_relaxed);
  const uint64_t oob_changed = s.oob_changed.load(std::memory_order_relaxed);
  const uint64_t stamp_mismatch = s.stamp_mismatch.load(std::memory_order_relaxed);

  const uint64_t settings_miss = s.settings_stamp_miss.load(std::memory_order_relaxed);
  autoport_proof::publish("overlap_defects",
                          chain_mutated + oob_changed + stamp_mismatch + settings_miss + vacuous);
  autoport_proof::publish("overlap_settings_stamp_miss", settings_miss);
  autoport_proof::publish("overlap_settings_snapshots",
                          s.settings_snapshots.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_chain_mutated", chain_mutated);
  autoport_proof::publish("overlap_oob_changed", oob_changed);
  autoport_proof::publish("overlap_stamp_mismatch", stamp_mismatch);
  autoport_proof::publish("overlap_vacuous", vacuous);
  autoport_proof::publish("overlap_active", active ? 1 : 0);
  autoport_proof::publish("overlap_frames", frames);
  autoport_proof::publish("overlap_frames_overlapped",
                          s.frames_overlapped.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_release_in_flight", release_in_flight);
  autoport_proof::publish("overlap_release_total", s.release_total.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_goal_ahead_max",
                          s.goal_ahead_max.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_watch_ranges_max",
                          s.watch_ranges_max.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_watch_bytes_max",
                          s.watch_bytes_max.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_watch_ranges_total",
                          s.watch_ranges_total.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_watch_overflow",
                          s.watch_overflow.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_oob_rejected", s.oob_rejected.load(std::memory_order_relaxed));
  autoport_proof::publish("overlap_foreign_thread",
                          s.foreign_thread.load(std::memory_order_relaxed));
  for (int k = 0; k < kKindCount; k++) {
    char key[64];
    std::snprintf(key, sizeof(key), "overlap_seen_%s", kKindNames[k]);
    autoport_proof::publish(key, s.kind_seen[k].load(std::memory_order_relaxed));
    std::snprintf(key, sizeof(key), "overlap_changed_%s", kKindNames[k]);
    autoport_proof::publish(key, s.kind_changed[k].load(std::memory_order_relaxed));
  }
  publish_worst_kind();
}

}  // namespace overlap_census

// ─── perf-goal-gl-overlap — LE SLOT DE REGLAGES (declare dans game/graphics/gfx.h) ────────────
//
// Defini ICI, et pas dans `game/graphics/gfx.cpp` : ce dernier n'est PAS compile dans le build
// Android (android/CMakeLists.txt:233 le dit, `linux_arm64_runtime_compat.cpp` fournit
// `g_global_settings` a sa place). Un slot defini dans gfx.cpp seul manquerait au lien arm64.
namespace Gfx {
namespace {
// Deux emplacements suffisent EXACTEMENT : la garde inconditionnelle de `send_chain` borne le
// fil GOAL a une image d'avance. S'il en prenait deux, l'estampille ne serait plus la, et
// `adopt_settings_for_frame` le DIT au lieu de rendre une valeur perimee en silence.
GfxGlobalSettings g_slot[2];
std::atomic<int64_t> g_slot_stamp[2] = {std::atomic<int64_t>{-1}, std::atomic<int64_t>{-1}};
}  // namespace

void snapshot_settings_for_frame(int64_t logic_frame) {
  const int i = (int)((uint64_t)(logic_frame < 0 ? 0 : logic_frame) & 1u);
  g_slot_stamp[i].store(-1, std::memory_order_relaxed);
  g_slot[i] = g_global_settings;
  g_slot_stamp[i].store(logic_frame, std::memory_order_release);
  overlap_census::note_settings_snapshot();
}

bool adopt_settings_for_frame(int64_t logic_frame) {
  if (logic_frame < 0) {
    // Pas d'horloge de logique (hors refset, hors rejeu) : rien a apparier. On ne bascule PAS le
    // fil sur le cliche — il continue de lire la structure vivante, comme avant cet item.
    return true;
  }
  const int i = (int)((uint64_t)logic_frame & 1u);
  if (g_slot_stamp[i].load(std::memory_order_acquire) != logic_frame) {
    overlap_census::note_settings_stamp_miss();
    return false;
  }
  g_render_settings = g_slot[i];
  t_on_render_thread = true;
  return true;
}

}  // namespace Gfx
