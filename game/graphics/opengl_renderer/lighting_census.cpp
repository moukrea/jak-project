#include "game/graphics/opengl_renderer/lighting_census.h"

#include <array>
#include <cstdio>
#include <cstring>
#include <unordered_map>
#include <vector>

#include "game/graphics/pipelines/opengl.h"
#include "game/graphics/opengl_renderer/shade_proof.h"
#include "game/system/autoport_proof.h"

namespace lighting_census {
namespace {

constexpr const char* kItemId = "lighting-census";

// Les cinq chemins du §2.3, dans l'ordre du tableau de la spec. L'ordre COMPTE : `rt && pbr`
// (B) est teste avant `rt && probe` (D), exactement comme la spec les enumere.
enum Path { kA = 0, kB, kC, kD, kE, kUnaccounted, kPathCount };

// Les quatre portes. Une seule valeur par porte : elles sont poussees sur le programme
// COURANT, toujours avant les draws du renderer qui vient de les pousser.
int s_gate_rt_light = 0;
int s_gate_pbr_mode = 0;
int s_gate_probe = 0;
int s_gate_shadow = 0;
bool s_host_shade = false;
bool s_host_legacy = false;
int s_gate_no_tex = 0;

// Compteurs. Le total est compte a part : `total - somme(A..E) - non-classes` doit rendre 0,
// et ce residu est publie plutot que suppose.
uint64_t s_count[kPathCount] = {};
uint64_t s_count_phase[4][kPathCount] = {};
uint64_t s_total = 0;
uint64_t s_un_hfrag = 0;
uint64_t s_un_depth = 0;
uint64_t s_un_stock = 0;

int s_phase = 0;  // 0 libre, 1 ORIGINE, 2 RECHARGED, 3 ORIGINE-LUMIERE

// ── relecture de l'etat REEL du programme lie ───────────────────────────────────────────────
uint64_t s_rb_checks = 0;
uint64_t s_rb_mismatch = 0;
uint64_t s_rb_noloc = 0;
uint64_t s_rb_mismatch_by_gate[4] = {};
uint64_t s_draw_idx_in_frame = 0;
uint64_t s_verify_slot = 0;

// Emplacements par programme, resolus une fois. -1 = l'uniforme n'existe pas dans ce programme
// (le cas de hfrag), ce qui n'est PAS une erreur mais se compte.
std::unordered_map<unsigned, std::array<int, 4>> s_locs;

const char* const kGateNames[4] = {"u_rt_light_on", "u_pbr_mode", "u_rt_probe_on",
                                   "u_pbr_shadow_on"};

// ── temps GPU ───────────────────────────────────────────────────────────────────────────────
enum Pass {
  kPassHfrag = 0,
  kPassTfrag,
  kPassTie,
  kPassEtie,
  kPassShrub,
  kPassMerc,
  kPassGeneric,
  kPassSprite,
  kPassOcean,
  kPassOther,
  kPassBuckets,
  kPassCount
};
const char* const kPassNames[kPassCount] = {"hfrag", "tfrag",  "tie",   "etie",
                                            "shrub", "merc",   "generic", "sprite",
                                            "ocean", "other",  "buckets"};

struct Sample {
  int pass;
  unsigned q_start;
  unsigned q_end;
};

constexpr int kRing = 4;          // profondeur du differe : on moissonne l'image N-3
constexpr int kMaxSamplesFrame = 192;
std::vector<Sample> s_ring[kRing];
std::vector<unsigned> s_query_pool;
int s_ring_slot = 0;
uint64_t s_pass_ns[kPassCount] = {};
uint64_t s_timed_frames = 0;
int s_timer_state = -1;  // -1 inconnu, 0 indisponible, 1 disponible
std::vector<int> s_open_stack;

uint64_t s_frames = 0;

bool timer_ok() {
  if (s_timer_state < 0) {
    // glad laisse le pointeur nul quand l'extension manque (GLES sans
    // EXT_disjoint_timer_query). On ne publie alors AUCUNE cle `gpu_ms_*`.
    s_timer_state = (glQueryCounter && glGetQueryObjectui64v && glGenQueries) ? 1 : 0;
  }
  return s_timer_state == 1;
}

unsigned take_query() {
  if (!s_query_pool.empty()) {
    unsigned q = s_query_pool.back();
    s_query_pool.pop_back();
    return q;
  }
  unsigned q = 0;
  glGenQueries(1, &q);
  return q;
}

int pass_of(const char* name) {
  if (!name) {
    return kPassOther;
  }
  // La borne de l'image entiere est posee sous un nom RESERVE, compare en entier : aucun
  // bucket du jeu ne peut tomber dedans par accident (`renderer-buckets` porte le jeton
  // « buckets » et polluerait le total si on le cherchait comme jeton).
  if (std::strcmp(name, "__buckets") == 0) {
    return kPassBuckets;
  }
  // `BucketRenderer::name_and_id()` rend « [26] l0-tfrag-tie » : il faut sauter le prefixe
  // entre crochets, mais cela ne suffit pas.
  if (name[0] == '[') {
    const char* p = std::strchr(name, ']');
    if (p) {
      name = p + 1;
      while (*name == ' ') {
        name++;
      }
    }
  }
  // POURQUOI PAR JETONS, ET PAS PAR PREFIXE. Les 53 buckets de jak1 nomment le NIVEAU en
  // premier et le renderer en DERNIER : `l0-tfrag-tie`, `l0-shrub-generic`, `common-pris-merc`.
  // Un `strncmp` ancre au debut ne peut donc matcher que `sprite`, `ocean-*` et `sky` — et
  // c'est exactement ce que la course du 2026-09-06 a mesure : gpu_ms_ocean=0,1008,
  // gpu_ms_sprite=0,3503, et tfrag/tie/shrub/merc/generic a 0,0000 pile sur 14517 images,
  // 7,9561 ms des 8,4333 ms de l'image entiere echoues dans `other`. Cinq fausses constantes
  // sur un vantage ou tfrag et tie dessinent a coup sur.
  struct Entry {
    const char* token;
    int pass;
  };
  // Jetons compares EN ENTIER : « tie » ne peut plus etre mange par « etie », ni « tfrag »
  // masquer « tie ». `tex` et `sky` sont listes vers `other` a dessein : ce sont de vraies
  // passes, et les reconnaitre EMPECHE `l0-tfrag-tex` d'etre compte comme du tfrag.
  static const Entry table[] = {
      {"hfrag", kPassHfrag},     {"tfrag", kPassTfrag},   {"etie", kPassEtie},
      {"tie", kPassTie},         {"shrub", kPassShrub},   {"merc", kPassMerc},
      {"gmerc", kPassMerc},      {"gmerc2", kPassMerc},   {"generic", kPassGeneric},
      {"sprite", kPassSprite},   {"ocean", kPassOcean},   {"tex", kPassOther},
      {"sky", kPassOther},
  };
  auto lookup = [](const char* tok, size_t len) -> int {
    for (const auto& e : table) {
      if (std::strlen(e.token) == len && std::strncmp(tok, e.token, len) == 0) {
        return e.pass;
      }
    }
    return -1;
  };
  // Un nom de style « lcom » porte le renderer EN TETE (`merc-lcom-tfrag`, `tex-lcom-shrub`,
  // `ocean-mid-far`) : le premier jeton gagne. Sinon c'est un nom de niveau et le DERNIER
  // jeton connu est le renderer (`l0-alpha-tfrag-ice` -> tfrag, `ice` etant inconnu).
  const char* first_end = std::strchr(name, '-');
  const int head = lookup(name, first_end ? (size_t)(first_end - name) : std::strlen(name));
  if (head >= 0) {
    return head;
  }
  int found = kPassOther;
  const char* tok = name;
  while (*tok) {
    const char* end = std::strchr(tok, '-');
    const size_t len = end ? (size_t)(end - tok) : std::strlen(tok);
    const int p = lookup(tok, len);
    if (p >= 0) {
      found = p;
    }
    if (!end) {
      break;
    }
    tok = end + 1;
  }
  return found;
}

void harvest(int slot) {
  auto& v = s_ring[slot];
  if (v.empty()) {
    return;
  }
  bool all_ready = true;
  for (const auto& s : v) {
    unsigned avail = 0;
    glGetQueryObjectuiv(s.q_end, GL_QUERY_RESULT_AVAILABLE, &avail);
    if (!avail) {
      all_ready = false;
      break;
    }
  }
  if (!all_ready) {
    // Pas encore pretes : on les laisse pour le tour suivant plutot que de bloquer le GPU.
    return;
  }
  for (const auto& s : v) {
    uint64_t t0 = 0, t1 = 0;
    glGetQueryObjectui64v(s.q_start, GL_QUERY_RESULT, &t0);
    glGetQueryObjectui64v(s.q_end, GL_QUERY_RESULT, &t1);
    if (t1 > t0) {
      s_pass_ns[s.pass] += (t1 - t0);
    }
    s_query_pool.push_back(s.q_start);
    s_query_pool.push_back(s.q_end);
  }
  v.clear();
  s_timed_frames++;
}

void publish_locked() {
  autoport_proof::publish("light_census_A", s_count[kA]);
  autoport_proof::publish("light_census_B", s_count[kB]);
  autoport_proof::publish("light_census_C", s_count[kC]);
  autoport_proof::publish("light_census_D", s_count[kD]);
  autoport_proof::publish("light_census_E", s_count[kE]);
  autoport_proof::publish("light_census_unaccounted", s_count[kUnaccounted]);
  autoport_proof::publish("light_census_total", s_total);
  autoport_proof::publish("light_census_classified",
                          s_count[kA] + s_count[kB] + s_count[kC] + s_count[kD] + s_count[kE]);
  // La somme DOIT egaler le total : on publie le residu, on ne l'affirme pas.
  uint64_t sum = 0;
  for (int i = 0; i < kPathCount; i++) {
    sum += s_count[i];
  }
  autoport_proof::publish("light_census_residual", s_total - sum);
  // Le detail du seau non classe : un seau « exclu » n'est pas un seau « correct ».
  autoport_proof::publish("light_census_un_hfrag", s_un_hfrag);
  autoport_proof::publish("light_census_un_depth", s_un_depth);
  autoport_proof::publish("light_census_un_stock", s_un_stock);
  // Les trois references, separement.
  static const char* kPhasePrefix[4] = {"lc_free_", "lc_orig_", "lc_rech_", "lc_orig_light_"};
  static const char* kPathSuffix[kPathCount] = {"A", "B", "C", "D", "E", "un"};
  for (int p = 1; p <= 3; p++) {
    for (int i = 0; i < kPathCount; i++) {
      char key[64];
      std::snprintf(key, sizeof(key), "%s%s", kPhasePrefix[p], kPathSuffix[i]);
      autoport_proof::publish(key, s_count_phase[p][i]);
    }
  }
  // La relecture qui rend le recensement falsifiable.
  autoport_proof::publish("light_census_rb_checks", s_rb_checks);
  autoport_proof::publish("light_census_rb_mismatch", s_rb_mismatch);
  autoport_proof::publish("light_census_rb_noloc", s_rb_noloc);
  for (int i = 0; i < 4; i++) {
    char key[64];
    std::snprintf(key, sizeof(key), "light_census_rb_bad_%d", i);
    autoport_proof::publish(key, s_rb_mismatch_by_gate[i]);
  }
  autoport_proof::publish("light_census_frames", s_frames);

  autoport_proof::publish("gpu_timer_supported", timer_ok() ? 1 : 0);
  if (timer_ok() && s_timed_frames > 0) {
    autoport_proof::publish("gpu_ms_frames", s_timed_frames);
    for (int i = 0; i < kPassCount; i++) {
      char key[64];
      char val[32];
      std::snprintf(key, sizeof(key), "gpu_ms_%s", kPassNames[i]);
      const double ms = (double)s_pass_ns[i] / (double)s_timed_frames / 1.0e6;
      std::snprintf(val, sizeof(val), "%.4f", ms);
      autoport_proof::publish_text(key, val);
    }
  }
}

}  // namespace

bool active() {
  static int s_cached = -1;
  if (s_cached < 0) {
    s_cached = autoport_proof::armed_for(kItemId) ? 1 : 0;
  }
  return s_cached == 1;
}

void gate_rt_light(int v) {
  s_gate_rt_light = v;
}
void gate_pbr_mode(int v) {
  s_gate_pbr_mode = v;
}
void gate_probe(int v) {
  s_gate_probe = v;
}
void gate_shadow(int v) {
  s_gate_shadow = v;
}
void host_paths(bool shade, bool legacy) {
  s_host_shade = shade;
  s_host_legacy = legacy;
}
void gate_no_tex(int v) {
  s_gate_no_tex = v;
}

void set_phase(int phase) {
  s_phase = (phase >= 0 && phase <= 3) ? phase : 0;
}

void note_world_draw(Kind k) {
  // lighting-unify partage CE site, et le partage AVANT la garde de l'item 0 : les deux items
  // s'arment separement (`armed_for`), et un `lighting-census` desarme ne doit pas rendre muet
  // le compteur d'un autre item. Les passes de profondeur sont exclues : elles ne produisent
  // aucune radiance, donc ne passent par aucun modele d'ombrage.
  if (k != Kind::DepthOnly) {
    shade_proof::note_world_draw();
  }
  if (!active()) {
    return;
  }
  s_total++;

  int path;
  if (k == Kind::Hfrag) {
    // Le programme hfrag ne declare aucun des quatre uniformes : ce draw ne PEUT pas tomber
    // dans un des cinq chemins. Ce n'est pas une lacune du recensement, c'est un fait du
    // shader, et c'est la moitie du seau non classe.
    s_un_hfrag++;
    path = kUnaccounted;
  } else if (k == Kind::DepthOnly) {
    s_un_depth++;
    path = kUnaccounted;
  } else if (!s_host_shade || s_gate_no_tex != 0) {
    // ETIE envmap ne porte pas shade() ; les hotes le contournent aussi sans textures.
    s_un_stock++;
    path = kUnaccounted;
  } else if (s_gate_rt_light != 0 && s_gate_pbr_mode != 0) {
    path = kB;
  } else if (s_gate_rt_light != 0 && s_gate_probe == 0) {
    path = kA;
  } else if (s_gate_rt_light != 0) {
    path = kD;
  } else if (s_host_legacy && s_gate_pbr_mode != 0) {
    path = kC;
  } else if (s_host_legacy && s_gate_shadow != 0) {
    path = kE;
  } else {
    // Aucune branche applicable a cet hote : le draw garde le rendu d'ORIGINE.
    s_un_stock++;
    path = kUnaccounted;
  }
  s_count[path]++;
  s_count_phase[s_phase][path]++;
  if (path != kUnaccounted) {
    // `hits` = draws monde CLASSES dans un des cinq chemins (le denominateur nomme au §7.2).
    autoport_proof::note_hit();
  }

  // ── un draw par image : relire ce que le PROGRAMME contient vraiment ──────────────────────
  // Sans ca le recensement n'est qu'un miroir de ses propres variables. `glGetUniformiv` est
  // une requete synchrone : une seule par image, sur un indice de draw qui tourne, balaie tous
  // les renderers en quelques secondes sans peser sur la cadence.
  if (s_draw_idx_in_frame == s_verify_slot) {
    int prog = 0;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prog);
    if (prog > 0) {
      auto it = s_locs.find((unsigned)prog);
      if (it == s_locs.end()) {
        std::array<int, 4> locs{};
        for (int i = 0; i < 4; i++) {
          locs[i] = glGetUniformLocation((unsigned)prog, kGateNames[i]);
        }
        it = s_locs.emplace((unsigned)prog, locs).first;
      }
      const int shadow[4] = {s_gate_rt_light, s_gate_pbr_mode, s_gate_probe, s_gate_shadow};
      for (int i = 0; i < 4; i++) {
        if (it->second[i] < 0) {
          s_rb_noloc++;
          continue;
        }
        int real = 0;
        glGetUniformiv((unsigned)prog, it->second[i], &real);
        s_rb_checks++;
        if (real != shadow[i]) {
          s_rb_mismatch++;
          s_rb_mismatch_by_gate[i]++;
        }
      }
    }
  }
  s_draw_idx_in_frame++;
}

void pass_begin(const char* bucket_name) {
  if (!active() || !timer_ok()) {
    return;
  }
  auto& v = s_ring[s_ring_slot];
  if ((int)v.size() >= kMaxSamplesFrame) {
    s_open_stack.push_back(-1);
    return;
  }
  Sample s;
  s.pass = pass_of(bucket_name);
  s.q_start = take_query();
  s.q_end = take_query();
  glQueryCounter(s.q_start, GL_TIMESTAMP);
  v.push_back(s);
  s_open_stack.push_back((int)v.size() - 1);
}

void pass_end() {
  if (!active() || !timer_ok() || s_open_stack.empty()) {
    return;
  }
  const int idx = s_open_stack.back();
  s_open_stack.pop_back();
  if (idx < 0) {
    return;
  }
  auto& v = s_ring[s_ring_slot];
  if (idx < (int)v.size()) {
    glQueryCounter(v[idx].q_end, GL_TIMESTAMP);
  }
}

void frame_end() {
  if (!active()) {
    return;
  }
  s_frames++;
  s_draw_idx_in_frame = 0;
  // L'indice verifie balaie l'espace des draws : un pas premier evite de retomber toujours sur
  // le meme renderer.
  s_verify_slot = (s_verify_slot + 37) % 1024;
  s_open_stack.clear();
  if (timer_ok()) {
    s_ring_slot = (s_ring_slot + 1) % kRing;
    harvest(s_ring_slot);
    // Le creneau qu'on va reutiliser doit etre vide ; s'il ne l'est pas (requetes jamais
    // pretes), on rend ses requetes au pool plutot que de les perdre.
    auto& v = s_ring[s_ring_slot];
    for (const auto& s : v) {
      s_query_pool.push_back(s.q_start);
      s_query_pool.push_back(s.q_end);
    }
    v.clear();
  }
  // A chaque image, pas toutes les 60 : `hits` de la ligne FEATURE est emis par le fil GOAL et
  // `light_census_*` par le fil graphique. Publier rarement faisait decrire deux instants
  // differents par deux compteurs qui doivent s'additionner (mesure : hits=1058023 contre
  // A=1038620, 19403 draws d'ecart, soit une centaine d'images de retard).
  publish_locked();
}

void publish() {
  if (!active()) {
    return;
  }
  publish_locked();
}

}  // namespace lighting_census
