#include "game/system/npc_flicker.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <unordered_map>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "fmt/core.h"

namespace npc_flicker {
namespace {

// Un episode plus court que ca est publie en `blinks=` et n'entre pas dans `cycles=`. Raison :
// le recensement GOAL et le compteur d'images du rendu sont deux horloges, decalees d'au plus une
// image. Trois images (~50 ms a 60 Hz) mettent le seuil hors de portee de ce decalage.
constexpr int kMinEpisodeFrames = 3;

// Borne haute. Voir la note du header : au-dela, ce n'est plus un clignotement.
//
// DEUX BORNES, ET C'EST L'APPAREIL QUI L'A IMPOSE. La borne en IMAGES seule est fausse des que le
// recensement ne tourne pas a 60 Hz : sur le Redmi, la MEME absence de caisse qui compte 1760
// images sur bureau n'en compte que 111 — mais elle dure 29 462 ms des deux cotes. Une borne en
// images l'aurait classee « clignotement » sur telephone et « longue » sur bureau, pour le meme
// evenement. L'owner ne voit pas des images, il voit une DUREE : on borne les deux.
constexpr uint64_t kMaxEpisodeFrames = 240;
constexpr uint64_t kMaxEpisodeMs = 4000;

// Tolerance de l'appariement des deux horloges : un acteur dessine a l'image de rendu F compte
// comme present tant que le rendu n'a pas depasse F + tolerance.
//
// MESUREE, PAS SUPPOSEE. L'histogramme `ecart0..ecart3` publie sur la ligne NPCSCENE dit ce que
// l'ecart VAUT : course x86 du 2026-09-01, `ecart0=2525 ecart1=10 ecart2=10 ecart3=10`, et les
// trois dizaines sont la rampe de la disparition INJECTEE. Hors injection, les deux horloges sont
// en pas a pas EXACT. La valeur 1 par defaut est donc conservatrice : elle masque les trous d'UNE
// image. `OG_NPCF_TOL=0` la retire — a n'utiliser que la ou l'histogramme montre `ecart1 = 0`,
// sinon on fabrique des trous qui n'existent pas, et un faux rouge coute aussi cher qu'un faux vert.
// Env sur bureau, PROPRIETE sur Android : l'application ne recoit pas l'environnement du shell,
// donc sans ce second chemin le controle positif serait impossible SUR L'APPAREIL — et une course
// appareil a zero cycle serait indistinguable d'un instrument muet.
bool read_knob(const char* env, const char* prop, char* out, size_t out_sz) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, out_sz, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, out_sz, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

uint64_t draw_tolerance() {
  static uint64_t s_tol = 1;
  static bool s_read = false;
  if (!s_read) {
    s_read = true;
    char v[64] = {0};
    if (read_knob("OG_NPCF_TOL", "debug.opengoal.npcf.tol", v, sizeof(v))) {
      s_tol = (uint64_t)strtoull(v, nullptr, 10);
    }
  }
  return s_tol;
}

std::mutex g_mutex;

uint64_t now_ms() {
  return (uint64_t)std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

struct RenderRec {
  uint64_t last_drawn = 0;
  uint64_t last_suppressed = 0;
  uint64_t last_missing = 0;
  bool ever_drawn = false;
  bool ever_suppressed = false;
  bool ever_missing = false;
  bool hd = false;
};

// indexe par pid de DRIVER (l'acteur du jeu), jamais par pid de compagnon HD.
std::unordered_map<uint32_t, RenderRec> g_render;
uint64_t g_render_frame = 0;

struct ActorRec {
  bool hd = false;
  uint64_t frames = 0;       // images de recensement ou l'acteur etait dans l'arbre
  uint64_t shown = 0;        // images ou quelque chose a ete dessine pour lui
  bool ever_shown = false;   // un episode ne s'ouvre qu'apres une PREMIERE presence
  bool in_gap = false;
  uint64_t gap_len = 0;
  Reason gap_reason = kReasonCulled;
  uint64_t cycles = 0;
  uint64_t blinks = 0;
  uint64_t by_reason[8] = {};
  uint64_t coupes = 0;
  uint64_t longues = 0;
  uint64_t max_gap = 0;
  // L'owner ne voit pas des images, il voit une DUREE. Un trou d'une image ne dure pas la meme
  // chose a 60 img/s sur bureau et a 15 sur son telephone : publier les deux est ce qui rend la
  // mesure comparable a ce qu'il decrit.
  uint64_t gap_start_ms = 0;
  uint64_t max_gap_ms = 0;
  uint64_t max_instances = 0;

  // etat de l'image en cours (rempli par census_actor, consomme par end_census). Plusieurs
  // acteurs peuvent partager un meme modele merc : on les FUSIONNE sur « au moins un est
  // dessine ». Ca SOUS-compte le defaut et ne peut jamais le fabriquer.
  uint64_t frame_stamp = 0;
  bool frame_drawn = false;
  uint32_t frame_status = 0;
  uint32_t frame_pid = 0;
  int frame_level = -1;
  int frame_block = 99;  // score de blocage de l'instance la moins bloquee
  uint64_t frame_instances = 0;
};

// 0 = rien ne l'empeche d'etre dessine, 3 = hidden. Sert a choisir, parmi plusieurs instances du
// meme modele, celle dont l'etat explique le mieux ce qui est REELLEMENT a l'ecran.
int block_score(uint32_t status) {
  if (status & 0x2) {
    return 3;  // hidden
  }
  if (status & 0x4) {
    return 2;  // no-anim
  }
  if (!(status & 0x8)) {
    return 1;  // was-drawn absent
  }
  return 0;
}

std::unordered_map<std::string, ActorRec> g_actors;
// Derniere image de recensement ou un clone portant ce modele a echoue a suivre sa source.
std::unordered_map<std::string, uint64_t> g_remap_fail;
// L'ECART DES DEUX HORLOGES, MESURE AU LIEU D'ETRE SUPPOSE. La tolerance est une constante
// choisie ; cet histogramme publie ce que l'ecart VAUT reellement (images de recensement classees
// par `image_de_rendu_courante - derniere_image_dessinee`, pour les acteurs dessines recemment).
// Si tout tombe dans la case 0, la tolerance masque des trous d'une image pour rien.
uint64_t g_skew[4] = {};
std::string g_scene;
uint64_t g_census_frame = 0;
Totals g_totals;

bool is_hd_name(const char* merc_name) {
  return merc_name && std::strstr(merc_name, "-hd-lod") != nullptr;
}

Reason classify(const std::string& key,
                bool in_tree,
                uint32_t status,
                uint32_t pid,
                int level_active) {
  if (!in_tree) {
    return kReasonDead;
  }
  if (status & 0x2) {  // hidden
    // `hidden` recouvre DEUX choses qui portent le meme bit : une decision d'auteur (le jeu cache
    // l'acteur) et l'echec d'un clone a suivre sa source. Seul le producteur peut les separer,
    // et c'est pour ca qu'il le declare lui-meme.
    auto it = g_remap_fail.find(key);
    if (it != g_remap_fail.end() && g_census_frame - it->second <= 2) {
      return kReasonRemap;
    }
    return kReasonHidden;
  }
  if (status & 0x4) {  // no-anim
    return kReasonNoAnim;
  }
  if (!(status & 0x8)) {
    // was-drawn absent => GOAL n'a rien soumis. Deux causes tres differentes, et sans le statut
    // du niveau elles rendent le meme etat : le moteur de dessin de son niveau ne tourne plus
    // (defaut), ou la camera l'a laisse hors du frustum (le moteur qui fonctionne).
    return level_active == 0 ? kReasonLevel : kReasonCulled;
  }
  // was-drawn present : GOAL a soumis, la perte est cote rendu.
  auto it = g_render.find(pid);
  if (it != g_render.end()) {
    if (it->second.ever_suppressed &&
        g_render_frame - it->second.last_suppressed <= draw_tolerance() + 1) {
      return kReasonSuppressed;
    }
    if (it->second.ever_missing &&
        g_render_frame - it->second.last_missing <= draw_tolerance() + 1) {
      return kReasonMissing;
    }
  }
  return kReasonCulled;
}

void close_gap(const std::string& name, ActorRec& rec) {
  if (!rec.in_gap) {
    return;
  }
  if (rec.gap_len > rec.max_gap) {
    rec.max_gap = rec.gap_len;
  }
  const uint64_t ms = now_ms() - rec.gap_start_ms;
  if (ms > rec.max_gap_ms) {
    rec.max_gap_ms = ms;
  }
  if (rec.gap_len >= (uint64_t)kMinEpisodeFrames) {
    rec.by_reason[rec.gap_reason]++;
    if (reason_is_defect(rec.gap_reason) &&
        (rec.gap_len > kMaxEpisodeFrames || ms > kMaxEpisodeMs)) {
      rec.longues++;
      fmt::print("NPCFLICK-LONG scene={} pnj={} images={} ms={} cause={} hd={}\n", g_scene, name,
                 rec.gap_len, ms, reason_name(rec.gap_reason), rec.hd ? 1 : 0);
      fflush(stdout);
    } else if (reason_is_defect(rec.gap_reason)) {
      rec.cycles++;
      fmt::print("NPCFLICK-EV scene={} pnj={} images={} ms={} cause={} hd={}\n", g_scene, name,
                 rec.gap_len, ms, reason_name(rec.gap_reason), rec.hd ? 1 : 0);
      fflush(stdout);
    } else {
      rec.coupes++;
    }
  } else {
    rec.blinks++;
  }
  rec.in_gap = false;
  rec.gap_len = 0;
}

// Instantane periodique. Une course peut etre coupee AVANT la fin d'une cinematique (une prise
// de mesure est bornee en temps) ; sans ca, une scene interrompue ne publierait RIEN et son
// absence se lirait comme un zero. Les lignes portent un prefixe distinct : elles ne sont pas le
// verdict, elles sont l'etat courant.
void snapshot() {
  for (auto& kv : g_actors) {
    ActorRec& r = kv.second;
    if (!r.ever_shown) {
      continue;
    }
    fmt::print(
        "NPCFLICK-P scene={} pnj={} cycles={} hd={} coupes={} longues={} blinks={} mort={} hidden={} "
        "noanim={} culled={} supprime={} modele_absent={} niveau={} clone={} trou_max={} "
        "trou_max_ms={} "
        "images={} "
        "dessine={} inst={}\n",
        g_scene, kv.first, r.cycles, r.hd ? 1 : 0, r.coupes, r.longues, r.blinks,
        r.by_reason[kReasonDead], r.by_reason[kReasonHidden], r.by_reason[kReasonNoAnim],
        r.by_reason[kReasonCulled], r.by_reason[kReasonSuppressed], r.by_reason[kReasonMissing],
        r.by_reason[kReasonLevel], r.by_reason[kReasonRemap], r.max_gap, r.max_gap_ms, r.frames,
        r.shown,
        r.max_instances);
  }
  fflush(stdout);
}

// Publie la scene qui se termine : UNE ligne par acteur suivi, jamais un agregat seul. Un acteur
// qui n'a jamais ete dessine dans cette scene ne produit pas de ligne — il n'y etait pas.
void flush_scene() {
  if (g_scene.empty()) {
    return;
  }
  uint64_t actors = 0;
  uint64_t cycles = 0;
  for (auto& kv : g_actors) {
    ActorRec& r = kv.second;
    if (!r.ever_shown) {
      continue;
    }
    // Un episode encore ouvert a la fin de la scene n'est PAS un cycle : rien ne prouve que
    // l'acteur devait revenir.
    actors++;
    cycles += r.cycles;
    fmt::print(
        "NPCFLICK scene={} pnj={} cycles={} hd={} coupes={} longues={} blinks={} mort={} hidden={} "
        "noanim={} culled={} supprime={} modele_absent={} niveau={} clone={} trou_max={} "
        "trou_max_ms={} "
        "images={} "
        "dessine={} inst={}\n",
        g_scene, kv.first, r.cycles, r.hd ? 1 : 0, r.coupes, r.longues, r.blinks,
        r.by_reason[kReasonDead], r.by_reason[kReasonHidden], r.by_reason[kReasonNoAnim],
        r.by_reason[kReasonCulled], r.by_reason[kReasonSuppressed], r.by_reason[kReasonMissing],
        r.by_reason[kReasonLevel], r.by_reason[kReasonRemap], r.max_gap, r.max_gap_ms, r.frames,
        r.shown,
        r.max_instances);
    g_totals.cycles += r.cycles;
    g_totals.coupes += r.coupes;
    g_totals.longues += r.longues;
    g_totals.blinks += r.blinks;
    g_totals.frames += r.frames;
    for (int i = 0; i < 8; i++) {
      g_totals.by_reason[i] += r.by_reason[i];
    }
  }
  g_totals.scenes++;
  g_totals.actors += actors;
  fmt::print("NPCSCENE scene={} pnj_suivis={} cycles={} images={} ecart0={} ecart1={} ecart2={} "
             "ecart3={} tolerance={}\n",
             g_scene, actors, cycles, g_census_frame, g_skew[0], g_skew[1], g_skew[2], g_skew[3],
             draw_tolerance());
  fflush(stdout);
  g_actors.clear();
  g_remap_fail.clear();
  g_scene.clear();
  g_census_frame = 0;
  for (int i = 0; i < 4; i++) {
    g_skew[i] = 0;
  }
}

}  // namespace

const char* reason_name(Reason r) {
  switch (r) {
    case kReasonDead:
      return "mort";
    case kReasonHidden:
      return "hidden";
    case kReasonNoAnim:
      return "noanim";
    case kReasonCulled:
      return "culled";
    case kReasonSuppressed:
      return "supprime";
    case kReasonMissing:
      return "modele-absent";
    case kReasonLevel:
      return "niveau-inactif";
    case kReasonRemap:
      return "clone-desynchronise";
  }
  return "?";
}

void note_clone_remap_fail(const char* merc_name) {
  if (!merc_name || !merc_name[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_scene.empty()) {
    return;
  }
  g_remap_fail[merc_name] = g_census_frame;
}

bool reason_is_defect(Reason r) {
  // `culled` et `hidden` sont des decisions du jeu, pas des pannes : voir la note du header.
  return r != kReasonCulled && r != kReasonHidden;
}

int min_episode_frames() {
  return kMinEpisodeFrames;
}

int max_episode_frames() {
  return (int)kMaxEpisodeFrames;
}

int max_episode_ms() {
  return (int)kMaxEpisodeMs;
}

void note_draw(uint32_t owner_pid, Outcome outcome, bool is_hd_model) {
  if (owner_pid == 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  RenderRec& r = g_render[owner_pid];
  switch (outcome) {
    case Outcome::kDrawn:
      r.last_drawn = g_render_frame;
      r.ever_drawn = true;
      r.hd = is_hd_model;
      break;
    case Outcome::kSuppressed:
      r.last_suppressed = g_render_frame;
      r.ever_suppressed = true;
      break;
    case Outcome::kMissing:
      r.last_missing = g_render_frame;
      r.ever_missing = true;
      break;
  }
}

void end_render_frame(uint64_t frame_idx) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (frame_idx == g_render_frame) {
    return;  // Merc2::render est appele 16 fois par image : une seule compte.
  }
  g_render_frame = frame_idx;
}

void begin_census(const char* scene) {
  std::lock_guard<std::mutex> lock(g_mutex);
  const bool none = !scene || !scene[0] || std::strcmp(scene, "hors-cinematique") == 0;
  if (none) {
    flush_scene();
    return;
  }
  if (g_scene != scene) {
    flush_scene();
    g_scene = scene;
    g_census_frame = 0;
  }
  g_census_frame++;
  if (g_census_frame % 600 == 0) {
    snapshot();
  }
}

void census_actor(const char* proc_name,
                  const char* merc_name,
                  uint32_t pid,
                  uint32_t draw_status,
                  int level_active) {
  if (!proc_name || !proc_name[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_scene.empty()) {
    return;
  }
  // Le compagnon HD n'est pas un acteur du jeu : il dessine SOUS LE PID DE SON DRIVER (Merc2 fait
  // la traduction). Le recenser separement fabriquerait un acteur jamais dessine sous son propre
  // pid, donc un faux defaut.
  if (is_hd_name(merc_name)) {
    return;
  }
  ActorRec& rec = g_actors[proc_name];
  if (rec.frame_stamp != g_census_frame) {
    rec.frame_stamp = g_census_frame;
    rec.frame_drawn = false;
    rec.frame_block = 99;
    rec.frame_status = 0;
    rec.frame_pid = 0;
    rec.frame_level = -1;
    rec.frame_instances = 0;
    rec.frames++;
  }
  rec.frame_instances++;
  if (rec.frame_instances > rec.max_instances) {
    rec.max_instances = rec.frame_instances;
  }

  auto it = g_render.find(pid);
  if (it != g_render.end() && it->second.ever_drawn) {
    const uint64_t skew = g_render_frame - it->second.last_drawn;
    if (skew < 4) {
      g_skew[skew]++;
    }
  }
  if (it != g_render.end() && it->second.ever_drawn &&
      g_render_frame - it->second.last_drawn <= draw_tolerance()) {
    rec.frame_drawn = true;
    if (it->second.hd) {
      rec.hd = true;
    }
  }
  const int b = block_score(draw_status);
  if (b < rec.frame_block) {
    rec.frame_block = b;
    rec.frame_status = draw_status;
    rec.frame_pid = pid;
    rec.frame_level = level_active;
  }
}

void end_census() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_scene.empty()) {
    return;
  }
  // UNE evaluation par acteur et par image, ici et nulle part ailleurs : `census_actor` ne fait
  // qu'accumuler. Un acteur absent de l'arbre cette image a ete DESACTIVE — c'est la disparition
  // la plus violente et elle ne se lit sur aucun bit de draw-status.
  for (auto& kv : g_actors) {
    ActorRec& rec = kv.second;
    const bool in_tree = (rec.frame_stamp == g_census_frame);
    if (in_tree && rec.frame_drawn) {
      close_gap(kv.first, rec);
      rec.ever_shown = true;
      rec.shown++;
      continue;
    }
    if (!rec.ever_shown) {
      continue;  // jamais vu a l'ecran dans cette scene : rien a compter
    }
    if (!rec.in_gap) {
      rec.in_gap = true;
      rec.gap_len = 0;
      rec.gap_start_ms = now_ms();
      rec.gap_reason =
          classify(kv.first, in_tree, rec.frame_status, rec.frame_pid, rec.frame_level);
    }
    rec.gap_len++;
  }
}

bool inject_drop(const char* merc_name) {
  static bool s_read = false;
  static std::string s_frag;
  static uint64_t s_period = 0;
  static uint64_t s_len = 0;
  if (!s_read) {
    s_read = true;
    char e[160] = {0};
    if (read_knob("OG_NPCF_INJECT", "debug.opengoal.npcf.inject", e, sizeof(e))) {
      char frag[64] = {0};
      unsigned long long per = 0, len = 0;
      if (sscanf(e, "%63[^:]:%llu:%llu", frag, &per, &len) == 3 && per > 0 && len > 0) {
        s_frag = frag;
        s_period = per;
        s_len = len;
        fmt::print("NPCF-INJECT arme fragment={} periode={} duree={}\n", s_frag, s_period, s_len);
        fflush(stdout);
      }
    }
  }
  if (s_frag.empty() || !merc_name) {
    return false;
  }
  if (!std::strstr(merc_name, s_frag.c_str())) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  return (g_render_frame % s_period) < s_len;
}

Totals totals() {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_totals;
}

void reset_for_test() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_render.clear();
  g_actors.clear();
  g_remap_fail.clear();
  g_scene.clear();
  g_render_frame = 0;
  g_census_frame = 0;
  for (int i = 0; i < 4; i++) {
    g_skew[i] = 0;
  }
  g_totals = Totals();
}

}  // namespace npc_flicker
