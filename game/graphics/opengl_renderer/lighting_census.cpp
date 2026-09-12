#include "game/graphics/opengl_renderer/lighting_census.h"

#include <algorithm>
#include <atomic>
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

#include "game/graphics/pipelines/opengl.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/refset.h"
#include "game/graphics/opengl_renderer/shade_proof.h"
#include "game/system/autoport_proof.h"
#include "game/system/perf_instruments.h"

#if defined(__ANDROID__)
#include <EGL/egl.h>
#endif

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

// ── lighting-legacy-purge : LES UNIFORMES DE L'ANCIEN MONDE, SONDES SUR LE PROGRAMME LIE ────
// L'owner a fait retirer dix reglages d'eclairage anterieurs a la refonte. Retirer la rangee de
// menu et le champ de reglage ne prouve RIEN sur ce que la carte dessine : un uniforme reste
// dans le programme lie tant que le texte du shader le declare, et un shader Android est fige
// dans un blob que personne ne relit a la main. La seule grandeur qui repond vraiment est
// `glGetUniformLocation` sur le programme REELLEMENT LIE : >= 0 = l'ancien monde est encore
// compile dans ce binaire, < 0 = il n'y est pas.
//
// LE ZERO DOIT ETRE FALSIFIABLE. Un tableau de dix noms qui rend zero, c'est aussi ce que
// rendrait une sonde branchee sur rien. On sonde donc, DANS LE MEME APPEL et sur le MEME
// programme, deux noms qui doivent SURVIVRE a la purge (`u_pbr_mode`, `u_rt_light_on` : les
// deux portes du chemin unique de la refonte). `lighting_legacy_uniform_control` compte les
// programmes ou au moins l'un des deux repond. Un controle a zero rend la porte MUETTE, pas
// verte.
const char* const kLegacyUniformNames[] = {
    // ── les onze deja recenses : reglages d'eclairage retires avant l'essai 8 ───────────────
    "u_rt_ambient_on",        // ex AMBIANTE on/off          (realtime-ambient?)
    "u_rt_ambient_model",     // ex MODELE D'AMBIANCE        (realtime-ambient-model)
    "u_rt_ambient_contrast",  // ex CONTRASTE D'AMBIANCE     (knob mort : pousse, jamais lu)
    "u_rt_shadow_range",      // ex DISTANCE DES OMBRES      (realtime-shadow-dist)
    "u_rt_shadow_res",        // ex QUALITE DES OMBRES       (realtime-shadow-quality)
    "u_rt_shadow_residual",   // ex FORCE DES OMBRES         (realtime-shadow-strength)
    "u_pbr_displacement",     // ex PROFONDEUR DE SURFACE    (pbr-displacement)
    "u_pbr_bisect",           // ex PBR ISOLATE              (outil de bisection)
    "u_pbr_bisect2",          // ex PBR ISOLATE              (second masque)
    "u_mm_flags",             // ex MATERIAUX AVANCES        (modern-materials?)
    // Il restait DECLARE et LU apres le retrait de son etage : un drapeau a zero, pas une
    // absence. Le livrable exige l'inverse, il est donc supprime des shaders ET cherche ici.
    "u_pbr_tess_active",      // ex PROFONDEUR DE SURFACE, palier TESSELLATION
    // ── essai 8 : LA PILE DE MATIERE ELLE-MEME ─────────────────────────────────────────────
    // Owner du 11/09 : « faut supprimer le code ! On en veut plus ». Tant que ces noms
    // n'etaient pas cherches, `lighting_legacy_sites == 0` n'accusait RIEN : la porte etait
    // verte avec la pile PBR entiere encore compilee dans le programme lie.
    "u_pbr_mode",             // maitre de la branche PBR (choix du modele d'ombrage)
    "u_pbr_mat",              // parametres de materiau, paquet 1 (rugosite/metal/ao)
    "u_pbr_mat2",             // parametres de materiau, paquet 2
    "u_pbr_normal_strength",  // force de la carte de normales
    "u_pbr_normal_dc",        // composante continue retiree a la carte de normales
    "u_pbr_height_scale",     // amplitude du parallaxe/relief
    "u_pbr_height_lambda",    // pas de la marche du parallaxe
    "u_pbr_height_stat",      // statistique de hauteur du bake, poussee au shader
    "u_pbr_spec_intensity",   // intensite speculaire
    "u_pbr_ambient",          // terme ambiant de la pile PBR
    "u_pbr_exposure",         // exposition de la pile PBR
    "u_pbr_direct",           // poids de l'eclairage direct
    "u_pbr_indirect",         // poids de l'eclairage indirect
    "u_pbr_baked_weight",     // melange entre lumiere cuite et lumiere calculee
    "u_pbr_emissive_str",     // force de l'emissif
    "u_pbr_uv_tile",          // repetition des UV de materiau
    "u_pbr_uv_per_m",         // densite d'UV par metre monde
    "u_pbr_light_dir",        // direction de la lumiere principale du chemin PBR
    "u_pbr_light_color",      // couleur de la lumiere principale du chemin PBR
    "u_pbr_sun_dir",          // direction du soleil (relight monde)
    "u_pbr_sun_color",        // couleur du soleil (relight monde)
    "u_pbr_world_relight",    // interrupteur du relight monde
    "u_pbr_wr_direct",        // part directe du relight monde
    "u_pbr_wr_indirect",      // part indirecte du relight monde
    "u_pbr_legacy_shadow",    // repli d'ombre de l'ancien chemin PBR
    "tex_PBR_N",              // echantillonneur : normales
    "tex_PBR_R",              // echantillonneur : rugosite
    "tex_PBR_M",              // echantillonneur : metal
    "tex_PBR_AO",             // echantillonneur : occlusion ambiante
    "tex_PBR_H",              // echantillonneur : hauteur
    "tex_PBR_S",              // echantillonneur : speculaire
    "tex_PBR_E",              // echantillonneur : emissif
};
constexpr int kLegacyUniformCount = (int)(sizeof(kLegacyUniformNames) / sizeof(char*));
// Le masque porte UN BIT PAR NOM. Un `1u << i` sur un `uint32_t` avec i >= 32 est un decalage
// au-dela de la largeur du type : comportement INDEFINI, et les noms de queue jamais comptes —
// un faux vert silencieux. Le masque est donc un `uint64_t`, et cette assertion casse le build
// le jour ou la table depasse 64 noms plutot que de laisser la sonde mentir.
static_assert(kLegacyUniformCount <= 64,
              "kLegacyUniformNames depasse la largeur de s_legacy_uniform_mask (64 bits)");

// LES DEUX TEMOINS, ET POURQUOI CEUX-LA. Un temoin doit SURVIVRE a la purge qu'il atteste :
// `u_pbr_mode` etait temoin jusqu'a l'essai 7, mais l'essai 8 le SUPPRIME — il est desormais une
// CIBLE (kLegacyUniformNames). Un temoin qui meurt avec la cible rend un vrai zero indistinguable
// d'une sonde debranchee. Restent deux noms declares dans les programmes MONDE et conserves par
// la refonte : `u_pbr_shadow_on` (la carte d'ombres, chemin unique) et `u_rt_light_on` (le maitre
// de la refonte). Aucun autre uniforme ne remplit les deux conditions.
const char* const kLegacyControlNames[2] = {"u_pbr_shadow_on", "u_rt_light_on"};

// Un bit par nom de `kLegacyUniformNames`, cumule sur toute la course : un nom trouve une seule
// fois, sur un seul programme, suffit a dire que l'ancien monde est encore la. Le PIRE cas est
// donc conserve, jamais lave par un programme propre.
// Ecrits sur le fil GL, lus sur le fil GOAL (kmachine.cpp) : atomiques relaches. Le compteur
// n'a qu'un ecrivain, il n'y a donc rien a serialiser, seulement une lecture a rendre definie.
std::atomic<uint64_t> s_legacy_uniform_mask{0};
std::atomic<uint64_t> s_legacy_uniform_programs{0};  // denominateur : programmes distincts sondes
std::atomic<uint64_t> s_legacy_uniform_control{0};   // temoin : programmes ou un nom SURVIVANT repond
std::unordered_map<unsigned, char> s_legacy_probed;

// Sonde un programme une seule fois. Appelee depuis la relecture d'un draw par image, donc sur
// le programme que le renderer vient de lier : on sonde ce qui DESSINE, pas une table de source.
void legacy_probe_program(unsigned prog) {
  if (s_legacy_probed.count(prog)) {
    return;
  }
  s_legacy_probed.emplace(prog, 1);
  s_legacy_uniform_programs.fetch_add(1, std::memory_order_relaxed);
  for (int i = 0; i < kLegacyUniformCount; i++) {
    if (glGetUniformLocation(prog, kLegacyUniformNames[i]) >= 0) {
      s_legacy_uniform_mask.fetch_or(1ull << i, std::memory_order_relaxed);
    }
  }
  for (int i = 0; i < 2; i++) {
    if (glGetUniformLocation(prog, kLegacyControlNames[i]) >= 0) {
      s_legacy_uniform_control.fetch_add(1, std::memory_order_relaxed);
      break;
    }
  }
}

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
  int bucket;  // indice du bucket jak1 (-1 : borne d'image ou passe sans indice)
  unsigned q_start;
  unsigned q_end;
};

// perf-instruments : temps GPU PAR BUCKET (les 70 de jak1), en plus des passes ci-dessus. La cle
// est `gpu_ms_<id>_<nom>` (`[26] l0-tfrag-tie` -> `gpu_ms_26_l0_tfrag_tie`) : un chiffre en tete
// la separe des passes, et chaque bucket est DECLARE a perf_instruments des sa premiere vue,
// pour qu'un timer absent se lise comme des cles manquantes et non comme un silence.
constexpr int kMaxBuckets = 96;
uint64_t s_bucket_ns[kMaxBuckets] = {};
std::string s_bucket_key[kMaxBuckets];
bool s_bucket_seen[kMaxBuckets] = {};

// Points d'entree du timer. Sur GLES le pilote n'exporte que les variantes `EXT`
// (EXT_disjoint_timer_query) et glad laisse les noms de bureau a NULL : sans ce repli, aucune
// cle `gpu_ms_*` ne sort jamais sur l'appareil.
typedef void (*FnQueryCounter)(unsigned, unsigned);
typedef void (*FnGetQueryU64)(unsigned, unsigned, uint64_t*);
typedef void (*FnGetQueryUiv)(unsigned, unsigned, unsigned*);
typedef void (*FnGenQueries)(int, unsigned*);
FnQueryCounter s_fn_query_counter = nullptr;
FnGetQueryU64 s_fn_get_u64 = nullptr;
FnGetQueryUiv s_fn_get_uiv = nullptr;
FnGenQueries s_fn_gen = nullptr;

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
    s_fn_query_counter = (FnQueryCounter)glQueryCounter;
    s_fn_get_u64 = (FnGetQueryU64)glGetQueryObjectui64v;
    s_fn_get_uiv = (FnGetQueryUiv)glGetQueryObjectuiv;
    s_fn_gen = (FnGenQueries)glGenQueries;
#if defined(__ANDROID__)
    if (!s_fn_query_counter) {
      s_fn_query_counter = (FnQueryCounter)eglGetProcAddress("glQueryCounterEXT");
    }
    if (!s_fn_get_u64) {
      s_fn_get_u64 = (FnGetQueryU64)eglGetProcAddress("glGetQueryObjectui64vEXT");
    }
    if (!s_fn_get_uiv) {
      s_fn_get_uiv = (FnGetQueryUiv)eglGetProcAddress("glGetQueryObjectuivEXT");
    }
    if (!s_fn_gen) {
      s_fn_gen = (FnGenQueries)eglGetProcAddress("glGenQueriesEXT");
    }
#endif
    // Pointeur nul = extension absente (GLES sans EXT_disjoint_timer_query). On ne publie
    // alors AUCUNE cle `gpu_ms_*`, et `gpu_timer_supported=0` le dit.
    s_timer_state = (s_fn_query_counter && s_fn_get_u64 && s_fn_get_uiv && s_fn_gen) ? 1 : 0;
  }
  return s_timer_state == 1;
}

// perf-instruments : les timers tournent aussi hors recensement, sur reglage
// (`debug.opengoal.perf.buckets=1` / `OG_PERF_BUCKETS=1`) ou sous l'item perf-instruments.
bool timers_wanted() {
  return active() || perf_instruments::enabled();
}

unsigned take_query() {
  if (!s_query_pool.empty()) {
    unsigned q = s_query_pool.back();
    s_query_pool.pop_back();
    return q;
  }
  unsigned q = 0;
  s_fn_gen(1, &q);
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
    s_fn_get_uiv(s.q_end, GL_QUERY_RESULT_AVAILABLE, &avail);
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
    s_fn_get_u64(s.q_start, GL_QUERY_RESULT, &t0);
    s_fn_get_u64(s.q_end, GL_QUERY_RESULT, &t1);
    if (t1 > t0) {
      s_pass_ns[s.pass] += (t1 - t0);
      if (s.bucket >= 0 && s.bucket < kMaxBuckets) {
        s_bucket_ns[s.bucket] += (t1 - t0);
      }
    }
    s_query_pool.push_back(s.q_start);
    s_query_pool.push_back(s.q_end);
  }
  v.clear();
  s_timed_frames++;
}

void publish_gpu_locked();

void publish_locked() {
  // ── lighting-legacy-purge ─────────────────────────────────────────────────────────────────
  // LA PART SHADER de `lighting_legacy_sites`. kmachine.cpp y ajoute la part GOAL (symboles) et
  // la part C++ (options de `recharged_gating`) et publie la somme. Ici on publie SA part et
  // TOUS ses denominateurs : un chiffre sans son denominateur n'est pas une mesure.
  {
    const uint64_t mask = s_legacy_uniform_mask.load(std::memory_order_relaxed);
    int found = 0;
    std::string names;
    for (int i = 0; i < kLegacyUniformCount; i++) {
      if (mask & (1ull << i)) {
        found++;
        if (names.size() < 180) {
          if (!names.empty()) {
            names += ',';
          }
          names += kLegacyUniformNames[i];
        }
      }
    }
    autoport_proof::publish("lighting_legacy_uniform_sites", (uint64_t)found);
    // Meme grandeur, sous le nom que le contrat de l'essai 8 nomme : combien de NOMS de la table
    // ont repondu au moins une fois (popcount du masque). Les deux cles sont publiees pour que
    // les portes ecrites avant l'essai 8 continuent de lire la leur.
    autoport_proof::publish("lighting_legacy_uniform_live", (uint64_t)found);
    autoport_proof::publish("lighting_legacy_uniform_censused", (uint64_t)kLegacyUniformCount);
    autoport_proof::publish("lighting_legacy_uniform_programs",
                            s_legacy_uniform_programs.load(std::memory_order_relaxed));
    autoport_proof::publish("lighting_legacy_uniform_control",
                            s_legacy_uniform_control.load(std::memory_order_relaxed));
    // Une cle de TEXTE ne se vide jamais toute seule : liste vide => "-", sinon la derniere
    // liste non vide resterait a cote d'un compte a zero.
    autoport_proof::publish_text("lighting_legacy_uniform_list", names.empty() ? "-" : names.c_str());
  }
  if (!active()) {
    publish_gpu_locked();
    return;
  }
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

  publish_gpu_locked();
}

void publish_gpu_locked() {
  if (!timers_wanted()) {
    return;
  }
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
    // perf-instruments : un bucket = une cle, denominateur commun `gpu_ms_frames`.
    uint64_t n = 0;
    for (int b = 0; b < kMaxBuckets; b++) {
      if (!s_bucket_seen[b]) {
        continue;
      }
      n++;
      char val[32];
      const double ms = (double)s_bucket_ns[b] / (double)s_timed_frames / 1.0e6;
      std::snprintf(val, sizeof(val), "%.4f", ms);
      autoport_proof::publish_text(s_bucket_key[b].c_str(), val);
    }
    autoport_proof::publish("gpu_ms_bucket_count", n);
  }
}

}  // namespace

namespace {
unsigned s_roi_capture = 0;
bool s_roi_frame = false;

struct RoiConfig {
  bool enabled = false;
  int rect[4] = {285, 13, 315, 72};
};

const RoiConfig& roi_config() {
  static const RoiConfig config = [] {
    RoiConfig out;
    const char* enabled = std::getenv("OG_REFSET_TRACE_ROI");
    out.enabled = enabled && std::strcmp(enabled, "1") == 0;
    const char* rect = std::getenv("OG_REFSET_TRACE_ROI_RECT");
    if (!rect)
      return out;
    const char* cursor = rect;
    bool valid = true;
    for (int i = 0; i < 4 && valid; ++i) {
      const int limit = i % 2 == 0 ? 319 : 179;
      int value = 0;
      valid = *cursor >= '0' && *cursor <= '9';
      while (valid && *cursor >= '0' && *cursor <= '9') {
        value = value * 10 + (*cursor++ - '0');
        valid = value <= limit;
      }
      out.rect[i] = value;
      if (valid) {
        valid = *cursor == (i < 3 ? ',' : '\0');
        if (valid && i < 3)
          ++cursor;
      }
    }
    valid = valid && out.rect[0] <= out.rect[2] && out.rect[1] <= out.rect[3];
    if (!valid) {
      std::fprintf(stderr,
                   "REFSET-ROI status=disabled invalid OG_REFSET_TRACE_ROI_RECT='%s': "
                   "expected x0,y0,x1,y1 (inclusive, 0<=x0<=x1<320, 0<=y0<=y1<180)\n",
                   rect);
      out.enabled = false;
    }
    return out;
  }();
  return config;
}

// Read the current draw target without changing its read-buffer selection or pack state.
// Renderer color attachments are 2D textures or renderbuffers; reject other targets.
bool roi_read(RoiSnapshot& out) {
  gl_query_census::Armed _ap("lighting-roi-read");
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &out.framebuffer);
  glGetIntegerv(GL_VIEWPORT, out.viewport);
  int samples = 0;
  glGetIntegerv(GL_SAMPLES, &samples);
  if (!out.framebuffer || samples > 0 || out.viewport[2] <= 0 || out.viewport[3] <= 0 ||
      glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    return false;
  }
  int kind = 0, object = 0;
  glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &kind);
  glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &object);
  if (kind == GL_RENDERBUFFER) {
    int old = 0;
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &old);
    glBindRenderbuffer(GL_RENDERBUFFER, object);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &out.width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &out.height);
    glBindRenderbuffer(GL_RENDERBUFFER, old);
  } else if (kind == GL_TEXTURE && glGetTexLevelParameteriv) {
    int old = 0, level = 0, face = 0, layer = 0;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                          GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL, &level);
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                          GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE, &face);
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                          GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LAYER, &layer);
    if (face || layer)
      return false;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &old);
    glBindTexture(GL_TEXTURE_2D, object);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, level, GL_TEXTURE_WIDTH, &out.width);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, level, GL_TEXTURE_HEIGHT, &out.height);
    glBindTexture(GL_TEXTURE_2D, old);
  } else {
    return false;
  }
  if (out.width <= 0 || out.height <= 0 || out.viewport[0] < 0 || out.viewport[1] < 0 ||
      out.viewport[0] + out.viewport[2] > out.width ||
      out.viewport[1] + out.viewport[3] > out.height)
    return false;
  // Inclusive capture ROI, capture origin at top left.
  const auto& rect = roi_config().rect;
  out.x = out.viewport[0] + out.viewport[2] * rect[0] / 320;
  out.y = out.viewport[1] + out.viewport[3] * (180 - (rect[3] + 1)) / 180;
  out.w = out.viewport[0] + (out.viewport[2] * (rect[2] + 1) + 319) / 320 - out.x;
  out.h = out.viewport[1] + (out.viewport[3] * (180 - rect[1]) + 179) / 180 - out.y;
  int old_read = 0, old_buffer = 0, pack[4] = {}, pbo = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, out.framebuffer);
  glGetIntegerv(GL_READ_BUFFER, &old_buffer);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  // Preserve HDR differences rather than clamping them to 8-bit color.
  int component = 0;
  glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                        GL_FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE, &component);
  unsigned pixel_type = GL_UNSIGNED_BYTE;
#ifndef __ANDROID__
  if (component == GL_FLOAT) {
    pixel_type = GL_FLOAT;
    out.bytes_per_pixel = 4 * sizeof(float);
  }
#endif
  if (component != GL_UNSIGNED_NORMALIZED && pixel_type != GL_FLOAT) {
    glReadBuffer(old_buffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
    return false;
  }
  const unsigned keys[] = {GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH, GL_PACK_SKIP_PIXELS,
                           GL_PACK_SKIP_ROWS};
  for (int i = 0; i < 4; ++i) {
    glGetIntegerv(keys[i], &pack[i]);
    glPixelStorei(keys[i], i == 0 ? 1 : 0);
  }
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pbo);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  out.rgba.resize(size_t(out.w) * out.h * out.bytes_per_pixel);
  glReadPixels(out.x, out.y, out.w, out.h, GL_RGBA, pixel_type, out.rgba.data());
  glBindBuffer(GL_PIXEL_PACK_BUFFER, pbo);
  for (int i = 0; i < 4; ++i)
    glPixelStorei(keys[i], pack[i]);
  glReadBuffer(old_buffer);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
  return true;
}
}  // namespace

void roi_frame_begin() {
  s_roi_frame = roi_config().enabled && refset::wants_scene_probe() && s_roi_capture < 24;
  if (s_roi_frame)
    ++s_roi_capture;
}

bool roi_active() {
  return s_roi_frame && refset::wants_scene_probe();
}

void roi_model(uint64_t hash, const char* name) {
  if (roi_active()) {
    std::printf("REFSET-ROI type=model capture=%u hash=%016llx name=%s\n", s_roi_capture,
                (unsigned long long)hash, name);
  }
}

RoiSnapshot roi_before() {
  RoiSnapshot out;
  if (roi_active())
    roi_read(out);
  return out;
}

void roi_after(const RoiSnapshot& before,
               const char* type,
               int id,
               const char* name,
               uint64_t hash,
               uint32_t first_index,
               int texture) {
  if (before.rgba.empty())
    return;
  RoiSnapshot after;
  if (!roi_read(after) || before.framebuffer != after.framebuffer || before.width != after.width ||
      before.height != after.height || before.bytes_per_pixel != after.bytes_per_pixel ||
      std::memcmp(before.viewport, after.viewport, sizeof(before.viewport)) != 0) {
    std::printf("REFSET-ROI type=%s capture=%u id=%d name=%s status=target-changed-or-invalid\n",
                type, s_roi_capture, id, name);
    return;
  }
  unsigned changed = 0, rgb_changed = 0, alpha_changed = 0, alpha_only = 0;
  double rgb_maxdiff = 0;
  const bool hdr = before.bytes_per_pixel == 4 * sizeof(float);
  const size_t rgb_bytes = 3 * (before.bytes_per_pixel / 4);
  // FNV-1a of RGB readback bytes only, in readback row order (bottom to top).
  uint64_t rgb_before_hash = 14695981039346656037ull;
  uint64_t rgb_after_hash = 14695981039346656037ull;
  int min_x = 320, min_y = 180, max_x = -1, max_y = -1;
  for (int y = 0; y < before.h; ++y) {
    for (int x = 0; x < before.w; ++x) {
      const size_t offset = (size_t(y) * before.w + x) * before.bytes_per_pixel;
      const auto* before_pixel = before.rgba.data() + offset;
      const auto* after_pixel = after.rgba.data() + offset;
      for (size_t i = 0; i < rgb_bytes; ++i) {
        rgb_before_hash = (rgb_before_hash ^ before_pixel[i]) * 1099511628211ull;
        rgb_after_hash = (rgb_after_hash ^ after_pixel[i]) * 1099511628211ull;
      }
      const bool rgb_diff = std::memcmp(before_pixel, after_pixel, rgb_bytes) != 0;
      const bool alpha_diff = std::memcmp(before_pixel + rgb_bytes, after_pixel + rgb_bytes,
                                          before.bytes_per_pixel - rgb_bytes) != 0;
      changed += rgb_diff || alpha_diff;
      alpha_changed += alpha_diff;
      alpha_only += alpha_diff && !rgb_diff;
      if (!rgb_diff)
        continue;
      ++rgb_changed;
      for (int channel = 0; channel < 3; ++channel) {
        double delta;
        if (hdr) {
          float a, b;
          std::memcpy(&a, before_pixel + channel * sizeof(float), sizeof(float));
          std::memcpy(&b, after_pixel + channel * sizeof(float), sizeof(float));
          delta = a == b ? 0 : std::abs(double(a) - double(b));
          // A non-finite difference must not silently report zero amplitude.
          if (std::isnan(delta))
            delta = std::numeric_limits<double>::infinity();
        } else {
          delta = std::abs(int(before_pixel[channel]) - int(after_pixel[channel]));
        }
        rgb_maxdiff = std::max(rgb_maxdiff, delta);
      }
      const int cx = (before.x + x - before.viewport[0]) * 320 / before.viewport[2];
      const int cy = 179 - (before.y + y - before.viewport[1]) * 180 / before.viewport[3];
      min_x = std::min(min_x, cx);
      max_x = std::max(max_x, cx);
      min_y = std::min(min_y, cy);
      max_y = std::max(max_y, cy);
    }
  }
  std::printf(
      "REFSET-ROI type=%s capture=%u id=%d name=%s hash=%016llx first_index=%u "
      "texture=%d fbo=%d dims=%dx%d bpp=%d viewport=%d,%d,%d,%d changed=%u "
      "rgb_changed=%u rgb_maxdiff=%.9g rgb_units=%s alpha_changed=%u alpha_only=%u "
      "rgb_bbox=%d,%d,%d,%d rgb_before_hash=%016llx rgb_after_hash=%016llx\n",
      type, s_roi_capture, id, name, (unsigned long long)hash, first_index, texture,
      before.framebuffer, before.width, before.height, before.bytes_per_pixel, before.viewport[0],
      before.viewport[1], before.viewport[2], before.viewport[3], changed, rgb_changed, rgb_maxdiff,
      hdr ? "hdr_float" : "rgba8_code_value", alpha_changed, alpha_only,
      rgb_changed ? min_x : -1, rgb_changed ? min_y : -1, max_x, max_y,
      (unsigned long long)rgb_before_hash, (unsigned long long)rgb_after_hash);
}

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
  // lighting-legacy-purge : la sonde des uniformes de l'ancien monde vit AVANT la garde
  // `active()`. `active()` est `armed_for("lighting-census")` : laisser la sonde derriere
  // rendrait la porte d'un item MUETTE des que le harnais desarme un AUTRE item — la faute
  // exacte que `armed_for` existe pour empecher. Un draw sur seize suffit : la resolution est
  // memorisee par programme, et tous les programmes du monde passent en quelques images.
  {
    static uint64_t s_legacy_draw_n = 0;
    if ((s_legacy_draw_n++ % 16) == 0) {
      int lprog = 0;
      glGetIntegerv(GL_CURRENT_PROGRAM, &lprog);
      if (lprog > 0) {
        legacy_probe_program((unsigned)lprog);
      }
    }
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

namespace {
void pass_begin_impl(const char* bucket_name, int bucket) {
  if (!timers_wanted() || !timer_ok()) {
    return;
  }
  auto& v = s_ring[s_ring_slot];
  if ((int)v.size() >= kMaxSamplesFrame) {
    s_open_stack.push_back(-1);
    return;
  }
  Sample s;
  s.pass = pass_of(bucket_name);
  s.bucket = bucket;
  s.q_start = take_query();
  s.q_end = take_query();
  s_fn_query_counter(s.q_start, GL_TIMESTAMP);
  v.push_back(s);
  s_open_stack.push_back((int)v.size() - 1);
}
}  // namespace

void pass_begin(const char* bucket_name) {
  pass_begin_impl(bucket_name, -1);
}

void pass_begin_bucket(int bucket_id, const char* name_and_id) {
  if (bucket_id < 0 || bucket_id >= kMaxBuckets || !name_and_id) {
    pass_begin_impl(name_and_id, -1);
    return;
  }
  if (!s_bucket_seen[bucket_id]) {
    // `[26] l0-tfrag-tie` -> `gpu_ms_26_l0_tfrag_tie` ; declare a perf_instruments AVANT toute
    // mesure : une cle attendue qui ne sort jamais compte comme manquante.
    const char* nm = name_and_id;
    if (nm[0] == '[') {
      const char* p = std::strchr(nm, ']');
      if (p) {
        nm = p + 1;
        while (*nm == ' ') {
          nm++;
        }
      }
    }
    std::string key = "gpu_ms_" + std::to_string(bucket_id) + "_";
    for (const char* c = nm; *c; c++) {
      const bool ok = (*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') ||
                      (*c >= '0' && *c <= '9');
      key += ok ? *c : '_';
    }
    s_bucket_key[bucket_id] = key;
    s_bucket_seen[bucket_id] = true;
    perf_instruments::expect_key(key.c_str());
  }
  pass_begin_impl(name_and_id, bucket_id);
}

void pass_end() {
  if (!timers_wanted() || !timer_ok() || s_open_stack.empty()) {
    return;
  }
  const int idx = s_open_stack.back();
  s_open_stack.pop_back();
  if (idx < 0) {
    return;
  }
  auto& v = s_ring[s_ring_slot];
  if (idx < (int)v.size()) {
    s_fn_query_counter(v[idx].q_end, GL_TIMESTAMP);
  }
}

void frame_end() {
  if (!active() && !perf_instruments::enabled()) {
    return;
  }
  if (active()) {
    s_frames++;
    s_draw_idx_in_frame = 0;
    // L'indice verifie balaie l'espace des draws : un pas premier evite de retomber toujours
    // sur le meme renderer.
    s_verify_slot = (s_verify_slot + 37) % 1024;
  }
  s_open_stack.clear();
  if (timers_wanted() && timer_ok()) {
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

// lighting-legacy-purge : la part SHADER du recensement, lue par kmachine.cpp sur le fil GOAL.
uint32_t legacy_uniform_sites() {
  const uint64_t mask = s_legacy_uniform_mask.load(std::memory_order_relaxed);
  uint32_t n = 0;
  for (int i = 0; i < kLegacyUniformCount; i++) {
    if (mask & (1ull << i)) {
      n++;
    }
  }
  return n;
}
uint32_t legacy_uniform_censused() {
  return (uint32_t)kLegacyUniformCount;
}
uint64_t legacy_uniform_programs() {
  return s_legacy_uniform_programs.load(std::memory_order_relaxed);
}
uint64_t legacy_uniform_control() {
  return s_legacy_uniform_control.load(std::memory_order_relaxed);
}

void publish() {
  if (!active() && !perf_instruments::enabled()) {
    return;
  }
  publish_locked();
}

bool gpu_frame_totals(uint64_t* ns, uint64_t* frames) {
  if (!timer_ok()) {
    return false;
  }
  if (ns) {
    *ns = s_pass_ns[kPassBuckets];
  }
  if (frames) {
    *frames = s_timed_frames;
  }
  return true;
}

}  // namespace lighting_census
