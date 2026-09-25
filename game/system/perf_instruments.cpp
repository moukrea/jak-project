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
#include <utility>
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
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/mips2c/mips2c_census.h"
#include "game/mips2c/spart_prof.h"
#include "game/mips2c/vu_simd_state.h"
#include "game/runtime.h"
#include "game/system/autoport_proof.h"
#include "game/system/codegen_arm64_calls.h"
#include "game/system/codegen_arm64_regs.h"
#include "game/system/codegen_arm64_scalar.h"

namespace Mips2C::vu_simd {
namespace {
constexpr const char* kItem = "perf-mips2c-neon";
AUTOPORT_FEATURE_SITE(kItem);
// All counters are owned by the GOAL thread, like the VU contexts themselves.
uint64_t compared[3] = {}, defects[3] = {}, active_frames[3] = {}, nonfinite[3] = {};
uint64_t previous[3] = {}, frames = 0, warmup_frames = 0, ticks = 0;
// ── LA FENETRE DE COUT ────────────────────────────────────────────────────────────────
// Le contrat demande `mips2c_gain_us`, « meme scene, meme binaire sauf le noyau, >= 300
// images chaque bras ». Deux COURSES ne peuvent pas tenir « meme scene » : la scene derive.
// On alterne donc le regime DANS LA MEME COURSE, par blocs de 30 images, une fois la
// fenetre de parite epuisee (l'oracle est alors eteint : contrat, point 2).
//
// CE QU'ON NE MESURE PAS, ET POURQUOI. `goal_busy_ms` vaut 14,957 ms dont 12,824 de
// `swap-display` : c'est une attente d'affichage qui ABSORBE toute avance du fil GOAL. Un
// gain de quelques dizaines de microsecondes y serait invisible par construction. La
// grandeur mesuree est donc le temps passe DANS les noyaux raccordes, chronometre par le
// recensement mips2c qui les enveloppe deja — le surcout de son horloge est identique dans
// les deux regimes et se SOUSTRAIT dans l'ecart.
constexpr uint64_t kCostBlock = 30;
uint64_t cost_frames[2] = {};
uint64_t cost_ticks = 0;
bool vector_now = true;   // la phase de parite tourne toujours en vectoriel
int cost_slot_now = -1;   // -1 : cette image n'est comptee par personne
constexpr const char* names[] = {"collide", "joints", "particles"};
bool measuring() {
  static const bool value = autoport_proof::feature_is(kItem);
  return value;
}
}  // namespace

// ── L'ARBITRAGE DE L'ESSAI 13 : LE CHEMIN VECTORIEL N'EST PLUS LIVRE ────────────────────
// L'essai 12 a MESURE le cout de ce chemin sur l'appareil, par alternance des deux regimes
// dans la MEME course : 1026 ns/appel scalaire contre 1250 vectoriel (+21,8 %), soit
// +66 134 ns par image. Le contrat de l'item ordonne alors, point 2 : « Retirer des seuls
// noyaux de cet item les ajouts speculatifs qui n ont aucun benefice etabli ». Le benefice
// est etabli NEGATIF, donc le retrait est du.
//
// `armed_for(kItem)` rendait VRAI partout ou le harnais ne nomme pas CET item : dans le
// binaire de l'owner, et dans la course de preuve de TOUS LES AUTRES items. Le surcout etait
// donc paye par l'owner ET melange a chaque mesure de perf du backlog. `measuring()`
// (`feature_is(kItem)`) le confine a la course de preuve de cet item seul.
//
// CE QUI EST CONSERVE, ET POURQUOI. La condition garde `armed_for` : sans elle les deux bras
// de l'ablation seraient identiques et la course ne mesurerait plus rien. Sous la course de
// cet item, le bras arme allume le chemin vectoriel — la parite bit a bit et la fenetre de
// cout restent donc reproductibles a l'identique. Ce qui disparait, c'est la facture.
Settings settings(Kernel) {
#if defined(__aarch64__) || defined(__SSE2__) || defined(_M_X64)
  static const bool on = autoport_proof::armed_for(kItem);
  // `vector_now` ne vaut faux que pendant un bloc scalaire de la fenetre de cout, et cette
  // fenetre n'existe que sous `measuring()`.
  return {on && measuring() && vector_now, on && measuring() && frames < 600};
#else
  return {false, false};
#endif
}

int cost_slot() {
  return cost_slot_now;
}

uint64_t cost_frames_in(int slot) {
  return (slot == 0 || slot == 1) ? cost_frames[slot] : 0;
}

void record(Kernel kernel, uint64_t count, uint64_t mismatches) {
  const auto index = static_cast<unsigned>(kernel);
  compared[index] += count;
  defects[index] += mismatches;
}

void record_nonfinite(Kernel kernel, uint64_t count) {
  nonfinite[static_cast<unsigned>(kernel)] += count;
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
  // L'image qui vient de finir a tourne sous `cost_slot_now` : on la compte, puis on choisit
  // le regime de la SUIVANTE. La premiere image de chaque bloc est jetee (`-1`) : c'est celle
  // qui porte la transition de regime, pas un etat stable.
  if (frames >= 600) {
    if (cost_slot_now >= 0) {
      ++cost_frames[cost_slot_now];
    }
    const uint64_t block = cost_ticks / kCostBlock;
    const bool first_of_block = (cost_ticks % kCostBlock) == 0;
    vector_now = (block & 1) != 0;
    cost_slot_now = first_of_block ? -1 : (vector_now ? 1 : 0);
    ++cost_ticks;
  }
  if (++ticks % 60 != 0) {
    return;
  }
  uint64_t bit_defects = 0, missing_kernels = 0, total_nonfinite = 0;
  for (unsigned i = 0; i < 3; ++i) {
    const std::string prefix = std::string("mips2c_") + names[i];
    autoport_proof::publish((prefix + "_compared_ops").c_str(), compared[i]);
    autoport_proof::publish((prefix + "_bit_defects").c_str(), defects[i]);
    autoport_proof::publish((prefix + "_frames").c_str(), active_frames[i]);
    autoport_proof::publish((prefix + "_nonfinite_ops").c_str(), nonfinite[i]);
    bit_defects += defects[i];
    missing_kernels += compared[i] == 0;
    total_nonfinite += nonfinite[i];
  }
  uint64_t refset_diff = 0;
  const bool refset_present = autoport_proof::read_uint("refset_replay_maxdiff", refset_diff);
  autoport_proof::publish("mips2c_parity_frames", frames);
  autoport_proof::publish("mips2c_warmup_frames", warmup_frames);
  autoport_proof::publish("mips2c_bit_defects", bit_defects);
  // COMBIEN D'OPERATIONS N'ONT PAS PRIS LE BRAS VECTORIEL. Un operande infini ou NaN part au
  // repli scalaire avant toute comparaison : ces operations-la ne sont ni comparees ni
  // comptees en defaut. Publie a cote de `compared_ops`, son denominateur, pour qu'un lecteur
  // sache sur quelle fraction du trafic le zero de `bit_defects` a ete etabli.
  autoport_proof::publish("mips2c_nonfinite_ops", total_nonfinite);
  autoport_proof::publish("mips2c_missing_kernels", missing_kernels);
  autoport_proof::publish("mips2c_refset_present", refset_present);
  autoport_proof::publish("mips2c_parity_incomplete", frames < 600 || missing_kernels || !refset_present);
  // An absent replay or an unexercised kernel must never produce a green zero.
  autoport_proof::publish("mips2c_parity_defects", bit_defects + missing_kernels +
                             (frames < 600) + (!refset_present || refset_diff != 0));
}
}  // namespace Mips2C::vu_simd

// ════════════════════════════════════════════════════════════════════════════════════════════
// RECENSEMENT MIPS2C — LE PLAFOND DU GAIN, MESURE (perf-mips2c-neon, essai 10)
// ════════════════════════════════════════════════════════════════════════════════════════════
// Voir l'en-tete de `game/mips2c/mips2c_census.h` pour le pourquoi. Ici : le comment.
//
// UN SHIM PAR INDICE, PAS UN SHIM PAR FONCTION. Le stub GOAL grave un pointeur nu
// `u64(*)(void*)` : il ne transporte aucun contexte, donc un shim unique ne saurait pas QUELLE
// fonction il enveloppe. On instancie donc un gabarit sur un indice entier, 128 fois ; chaque
// instance connait sa ligne de table a la compilation. 94 fonctions jak1 sont enregistrees au
// 16/09 — le depassement est COMPTE et publie, jamais silencieux.
//
// DEUX TEMPS, ET C'EST VOULU. `ns` par fonction est le temps INCLUSIF : un noyau qui rappelle
// GOAL, qui rappelle un autre noyau mips2c, porte le temps de son appele. Additionner la
// colonne compterait donc deux fois. `g_union_ns` n'accumule qu'a la PROFONDEUR ZERO : c'est
// lui, et lui seul, qui est le plafond du gain. `mips2c_census_reentrant` dit combien d'appels
// etaient imbriques, pour que l'ecart entre les deux soit lisible au lieu d'etre devine.
//
// L'INSTRUMENT PUBLIE SON PROPRE COUT. Deux lectures d'horloge par appel. Leur prix est MESURE
// au demarrage (`mips2c_census_clock_ns_x1000`) et le surcout par image est publie a cote de la
// mesure : un lecteur peut soustraire. Sans ce chiffre, un plafond gonfle par l'instrument
// ressemblerait a un gisement.
namespace Mips2C {
namespace census {
namespace {

constexpr const char* kItem = "perf-mips2c-neon";
constexpr int kMax = 128;

struct Entry {
  u64 (*exec)(void*) = nullptr;
  char key[64] = {};
  u64 calls = 0;
  u64 ns = 0;  // temps INCLUSIF (voir l'en-tete de section)
  bool wired = false;  // raccorde au comparateur VuSimd : compte dans la fenetre de cout
};

// LES NOYAUX RACCORDES, NOMMES. Ce sont les seules fonctions dont le temps entre dans
// `mips2c_gain_us` : elles, et rien d'autre. Un nom qui ne s'apparie plus fait tomber
// `mips2c_cost_wired_fns` a zero, et la mesure se lit alors « aveugle », pas « nulle ».
// Noms assainis par `make_key`, comme les cles publiees.
constexpr const char* kWired[] = {
    "cspace__parented_transformq_joint_",  // joint.cpp        — Kernel::Joints
    "_method_32_collide_cache_",           // collide_cache.cpp — Kernel::Collide
    "_method_29_collide_cache_",           // collide_cache.cpp — Kernel::Collide
    "sp_launch_particles_var",             // sparticle_launcher.cpp — Kernel::Particles
};
u64 g_wired_ns[2] = {}, g_wired_calls[2] = {};
int g_wired_fns = 0;

Entry g_entries[kMax];
int g_count = 0;
int g_overflow = 0;
int g_depth = 0;
u64 g_union_ns = 0;
u64 g_calls = 0;
u64 g_reentrant = 0;
u64 g_frames = 0;
u64 g_clock_ns_x1000 = 0;
bool g_started = false;

inline u64 mono_ns() {
  return (u64)std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// Le prix d'une lecture d'horloge, sur CETTE machine, mesure et non suppose.
void calibrate() {
  constexpr int kReads = 20000;
  const u64 t0 = mono_ns();
  u64 sink = 0;
  for (int i = 0; i < kReads; ++i) {
    sink += mono_ns();
  }
  const u64 t1 = mono_ns();
  // `sink` empeche l'elimination de la boucle sans rien publier de faux.
  g_clock_ns_x1000 = sink ? (t1 - t0) * 1000ull / (u64)kReads : 0;
}

template <int I>
u64 shim(void* ctxt) {
  Entry& e = g_entries[I];
  ++e.calls;
  ++g_calls;
  const int depth = g_depth++;
  const u64 t0 = mono_ns();
  const u64 result = e.exec(ctxt);
  const u64 dt = mono_ns() - t0;
  --g_depth;
  e.ns += dt;
  if (depth == 0) {
    g_union_ns += dt;
    if (e.wired) {
      const int slot = Mips2C::vu_simd::cost_slot();
      if (slot >= 0) {
        g_wired_ns[slot] += dt;
        ++g_wired_calls[slot];
      }
    }
  } else {
    ++g_reentrant;
  }
  return result;
}

using Shim = u64 (*)(void*);

template <int... I>
constexpr void fill_shims(Shim* out, std::integer_sequence<int, I...>) {
  ((out[I] = &shim<I>), ...);
}

const Shim* shims() {
  static Shim table[kMax];
  static const bool once = [] {
    fill_shims(table, std::make_integer_sequence<int, kMax>{});
    return true;
  }();
  (void)once;
  return table;
}

// `mips2c_fn_` + le nom GOAL rendu publiable. Le moissonneur de proof_run.sh n'accepte que
// `[A-Za-z_][A-Za-z0-9_]*` : « (method 12 collide-mesh) » deviendrait une ligne ignoree, donc
// une fonction chaude INVISIBLE. On substitue, on ne tronque pas en silence : un nom trop long
// pour la cle serait deux fonctions confondues sous la meme etiquette.
void make_key(const char* prefix, const char* name, char* out, size_t cap) {
  size_t i = 0;
  for (const char* p = prefix; *p && i + 1 < cap; ++p) {
    out[i++] = *p;
  }
  for (const char* p = name; *p && i + 1 < cap; ++p) {
    const char c = *p;
    const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
    out[i++] = ok ? c : '_';
  }
  out[i] = 0;
}

}  // namespace

u64 (*wrap(const char* name, u64 (*exec)(void*)))(void*) {
  static const bool on = autoport_proof::feature_is(kItem);
  if (!on) {
    return exec;
  }
  if (!g_started) {
    g_started = true;
    calibrate();
  }
  if (g_count >= kMax) {
    ++g_overflow;
    return exec;
  }
  Entry& e = g_entries[g_count];
  e.exec = exec;
  make_key("", name, e.key, sizeof(e.key));
  for (const char* wired : kWired) {
    if (std::strcmp(wired, e.key) == 0) {
      e.wired = true;
      ++g_wired_fns;
      break;
    }
  }
  return shims()[g_count++];
}

void frame_boundary() {
  static const bool on = autoport_proof::feature_is(kItem);
  if (!on) {
    return;
  }
  ++g_frames;
  if (g_frames % 60 != 0) {
    return;
  }
  const u64 f = g_frames;
  int active = 0;
  int hot[3] = {-1, -1, -1};
  char key[96];
  for (int i = 0; i < g_count; ++i) {
    const Entry& e = g_entries[i];
    if (e.calls == 0) {
      continue;
    }
    ++active;
    make_key("mips2c_fn_calls_", e.key, key, sizeof(key));
    autoport_proof::publish(key, e.calls);
    make_key("mips2c_fn_ns_", e.key, key, sizeof(key));
    autoport_proof::publish(key, e.ns);
    for (int r = 0; r < 3; ++r) {
      if (hot[r] < 0 || e.ns > g_entries[hot[r]].ns) {
        for (int k = 2; k > r; --k) {
          hot[k] = hot[k - 1];
        }
        hot[r] = i;
        break;
      }
    }
  }
  autoport_proof::publish("mips2c_census_on", 1);
  autoport_proof::publish("mips2c_census_funcs", (u64)g_count);
  autoport_proof::publish("mips2c_census_active", (u64)active);
  autoport_proof::publish("mips2c_census_overflow", (u64)g_overflow);
  autoport_proof::publish("mips2c_census_frames", f);
  autoport_proof::publish("mips2c_census_calls", g_calls);
  autoport_proof::publish("mips2c_census_reentrant", g_reentrant);
  autoport_proof::publish("mips2c_census_ns", g_union_ns);
  // LE PLAFOND : ce qu'une vectorisation PARFAITE de tout mips2c pourrait rendre, par image.
  autoport_proof::publish("mips2c_census_ns_frame", g_union_ns / f);
  autoport_proof::publish("mips2c_census_calls_frame", g_calls / f);
  autoport_proof::publish("mips2c_census_clock_ns_x1000", g_clock_ns_x1000);
  const u64 overhead_ns_frame = (g_calls / f) * 2ull * g_clock_ns_x1000 / 1000ull;
  autoport_proof::publish("mips2c_census_overhead_ns_frame", overhead_ns_frame);
  // LE PLAFOND DU GAIN, SOUSTRACTION FAITE (essai 11). L'union brute et le cout de
  // l'instrument etaient publies cote a cote depuis l'essai 10, et personne — moi
  // compris, au premier coup d'oeil — ne les a soustraits : sur ce Redmi une lecture
  // d'horloge coute 454 ns (pas de vDSO pour CLOCK_MONOTONIC), l'instrument prend donc
  // 480 des 822 us/image publiees. Lire l'union brute comme un gisement la surestime
  // d'un facteur 2,4. On publie la difference, et non le lecteur qui l'oublie.
  autoport_proof::publish("mips2c_census_net_ns_frame",
                          g_union_ns / f > overhead_ns_frame ? g_union_ns / f - overhead_ns_frame
                                                             : 0);

  // ════════════════════════════════════════════════════════════════════════════════════
  // LE GAIN, MESURE — `mips2c_gain_us` (contrat, point N)
  // ════════════════════════════════════════════════════════════════════════════════════
  // Les deux bras vivent dans LA MEME COURSE et alternent par blocs de 30 images
  // (`Mips2C::vu_simd`), donc : meme binaire, meme appareil, meme scene a la derive pres,
  // que l'alternance moyenne. La grandeur comparee est le temps passe DANS les quatre
  // fonctions raccordees, chronometre par le meme shim des deux cotes : le surcout de
  // l'horloge est le meme par appel dans les deux bras et disparait dans l'ecart.
  //
  // TROIS ETATS NOMMES, JAMAIS UN ZERO MUET. `mips2c_gain_measured` ne vaut 1 que si les
  // quatre fonctions ont ete appariees ET que chaque bras porte au moins 300 images. Un
  // gain nul ou negatif est un DEFAUT, pas une absence : `mips2c_gain_negative` le dit.
  {
    const u64 fr_sca = Mips2C::vu_simd::cost_frames_in(0);
    const u64 fr_vec = Mips2C::vu_simd::cost_frames_in(1);
    autoport_proof::publish("mips2c_cost_wired_fns", (u64)g_wired_fns);
    autoport_proof::publish("mips2c_cost_frames_sca", fr_sca);
    autoport_proof::publish("mips2c_cost_frames_vec", fr_vec);
    autoport_proof::publish("mips2c_cost_calls_sca", g_wired_calls[0]);
    autoport_proof::publish("mips2c_cost_calls_vec", g_wired_calls[1]);
    autoport_proof::publish("mips2c_cost_ns_sca", g_wired_ns[0]);
    autoport_proof::publish("mips2c_cost_ns_vec", g_wired_ns[1]);
    const u64 per_frame_sca = fr_sca ? g_wired_ns[0] / fr_sca : 0;
    const u64 per_frame_vec = fr_vec ? g_wired_ns[1] / fr_vec : 0;
    autoport_proof::publish("mips2c_cost_ns_frame_sca", per_frame_sca);
    autoport_proof::publish("mips2c_cost_ns_frame_vec", per_frame_vec);
    autoport_proof::publish("mips2c_cost_ns_call_sca",
                            g_wired_calls[0] ? g_wired_ns[0] / g_wired_calls[0] : 0);
    autoport_proof::publish("mips2c_cost_ns_call_vec",
                            g_wired_calls[1] ? g_wired_ns[1] / g_wired_calls[1] : 0);
    const bool measured = g_wired_fns == (int)(sizeof(kWired) / sizeof(kWired[0])) &&
                          fr_sca >= 300 && fr_vec >= 300;
    const bool slower = per_frame_vec > per_frame_sca;
    autoport_proof::publish("mips2c_gain_measured", measured ? 1 : 0);
    autoport_proof::publish("mips2c_gain_negative", measured && slower ? 1 : 0);
    autoport_proof::publish("mips2c_gain_ns_frame",
                            measured && !slower ? per_frame_sca - per_frame_vec : 0);
    autoport_proof::publish(
        "mips2c_gain_us", measured && !slower ? (per_frame_sca - per_frame_vec) / 1000 : 0);
    // LA PERTE EST UN NOMBRE, PAS UN ZERO. `mips2c_gain_us` est plancher a zero quand le bras
    // vectoriel est le plus lent : un lecteur y lit « aucun effet » la ou la mesure dit
    // « pire ». La grandeur signee est donc publiee sous son propre nom, des deux cotes de
    // l'ecart, pour que l'ampleur du refus soit lisible sans relire un rapport.
    autoport_proof::publish("mips2c_loss_ns_frame",
                            measured && slower ? per_frame_vec - per_frame_sca : 0);
    const u64 call_sca = g_wired_calls[0] ? g_wired_ns[0] / g_wired_calls[0] : 0;
    const u64 call_vec = g_wired_calls[1] ? g_wired_ns[1] / g_wired_calls[1] : 0;
    autoport_proof::publish("mips2c_loss_ns_call",
                            measured && call_vec > call_sca ? call_vec - call_sca : 0);
    autoport_proof::publish("mips2c_loss_pct_x100",
                            measured && slower && per_frame_sca
                                ? ((per_frame_vec - per_frame_sca) * 10000) / per_frame_sca
                                : 0);
    autoport_proof::publish_text("mips2c_gain_state",
                                 !g_wired_fns              ? "aucune-fonction-appariee"
                                 : !measured               ? "bras-trop-courts"
                                 : slower                  ? "vectoriel-plus-lent"
                                                           : "vectoriel-plus-rapide");
  }
  // L'INSTRUMENT DE CET ITEM VIENT DE TOURNER, ET IL LE DIT SOUS SON PROPRE NOM.
  // Le recensement est l'instrument de `perf-mips2c-neon` : il porte son `kItem`, il
  // enveloppe ses 94 fonctions, il publie ses 90 cles — et il n'a JAMAIS attribue une
  // seule prise. Le validateur de l'essai 10 a donc refuse pour « un site moteur nomme
  // perf-mips2c-neon est bien compile dans ce binaire, mais il n'a JAMAIS tire » alors
  // que le recensement avait mesure 18 499 022 appels. Un compteur publie sans site
  // d'ecriture ne prouve rien : la prise se compte en APPELS MESURES, par delta, pour
  // qu'un zero signifie « le recensement n'a vu passer aucun noyau » et rien d'autre.
  static u64 s_calls_attributed = 0;
  if (g_calls > s_calls_attributed) {
    autoport_proof::note_hit_for(kItem, g_calls - s_calls_attributed);
    s_calls_attributed = g_calls;
  }
  // Les trois premieres lignes de la table, nommees : c'est la « table fonction/preuve
  // d'activite » que le contrat reclame, lisible sans depiler 90 cles.
  static const char* const kRank[3] = {"mips2c_hot1", "mips2c_hot2", "mips2c_hot3"};
  for (int r = 0; r < 3; ++r) {
    const std::string base(kRank[r]);
    if (hot[r] < 0) {
      autoport_proof::publish_text((base + "_name").c_str(), "-");
      autoport_proof::publish((base + "_ns_frame").c_str(), 0);
      autoport_proof::publish((base + "_calls").c_str(), 0);
      continue;
    }
    const Entry& e = g_entries[hot[r]];
    autoport_proof::publish_text((base + "_name").c_str(), e.key[0] ? e.key : "-");
    autoport_proof::publish((base + "_ns_frame").c_str(), e.ns / f);
    autoport_proof::publish((base + "_calls").c_str(), e.calls);
  }
  // LES QUATRE NOYAUX SPARTICLE DEJA CHRONOMETRES, ENFIN PUBLIES. `g_spart_prof` accumule ces
  // nanosecondes depuis Gperf-particles et AUCUN lecteur n'existait dans l'arbre : un instrument
  // qui mesure sans publier ne prouve rien. Ils ne coutent rien de plus ici.
  autoport_proof::publish("mips2c_spart_ns_3d", g_spart_prof.ns_3d.load(std::memory_order_relaxed));
  autoport_proof::publish("mips2c_spart_ns_2d", g_spart_prof.ns_2d.load(std::memory_order_relaxed));
  autoport_proof::publish("mips2c_spart_ns_launch",
                          g_spart_prof.ns_launch.load(std::memory_order_relaxed));
  autoport_proof::publish("mips2c_spart_ns_adgif",
                          g_spart_prof.ns_adgif.load(std::memory_order_relaxed));
  autoport_proof::publish("mips2c_spart_calls_3d",
                          g_spart_prof.calls_3d.load(std::memory_order_relaxed));
  autoport_proof::publish("mips2c_spart_calls_2d",
                          g_spart_prof.calls_2d.load(std::memory_order_relaxed));
  autoport_proof::publish("mips2c_spart_calls_launch",
                          g_spart_prof.calls_launch.load(std::memory_order_relaxed));
  autoport_proof::publish("mips2c_spart_calls_adgif",
                          g_spart_prof.calls_adgif.load(std::memory_order_relaxed));
}

}  // namespace census
}  // namespace Mips2C

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

// Accumulateurs de COURSE (pas de fenetre) : la fenetre de 60 images publiee
// dans `goal_busy_ms` est une PHOTO, pas la course — sur l'essai 6, la derniere
// fenetre valait 19,477 ms quand la moyenne des 80 fenetres valait 16,746 ms.
// Le contrat de `codegen_gain_us` exige >= 300 images par bras, donc la moyenne
// se prend depuis le debut de la course, et le DENOMINATEUR se publie a cote
// d'elle (`codegen_busy_frames`) : une moyenne sans son denominateur ne se lit
// pas. Le min et le max de fenetre disent le bruit de l'instrument.
uint64_t g_run_busy_ns = 0;
uint64_t g_run_busy_frames = 0;
uint64_t g_run_busy_windows = 0;
uint64_t g_run_busy_win_min_us = 0;
uint64_t g_run_busy_win_max_us = 0;
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
  // ── LE TERME PIXELS SE JUGE CONTRE SON TEMOIN, PAS CONTRE UN ZERO INATTEIGNABLE ───────────
  // `refset_replay_maxdiff != 0` demandait un rejeu bit-exact sur appareil. Le registre de
  // rejeux dit qu'il n'existe pas : deux courses a bin, refs, data, config et input IDENTIQUES
  // ont rendu 61 puis 57 (notes/a9/replay-ledger-a8.txt:1-2), et a CGO constants le seul
  // changement de libgk.so a deplace le maximum de 59 a 19 (lignes 3 et 5 du meme registre).
  // La porte mesurait donc le plancher de son instrument, pas l'enrobage d'appel : elle etait
  // rouge pour TOUT binaire, y compris celui d'AVANT l'item.
  //
  // Ce qu'elle demande maintenant : que le code livre ne deplace pas plus de pixels que le
  // code SANS le changement, juge contre la MEME reference, par le MEME instrument, sur le
  // MEME appareil, dans la MEME campagne. `refset_control_maxdiff` est ce temoin, lu du
  // registre par `refset.cpp/publish_flaky` sur les lignes qui ne different que par les
  // donnees. Falsifiable : un enrobage qui ecraserait un registre vivant rendrait un maximum
  // AU-DESSUS du temoin, et 255 si l'image ne se compare plus du tout.
  //
  // Polarite. Pas de rejeu, pas de temoin, ou une sentinelle (254 = plan interrompu,
  // 255 = reference absente) => defaut. Rien ici ne peut rendre un vert par inaction.
  uint64_t control_diff = 0, control_runs = 0;
  const bool control_present =
      autoport_proof::read_uint("refset_control_maxdiff", control_diff) &&
      autoport_proof::read_uint("refset_control_runs", control_runs) && control_runs > 0;
  const uint64_t defect_refset = (!refset_present || !control_present || refset_diff >= 254 ||
                                  control_diff >= 254 || refset_diff > control_diff)
                                     ? 1u
                                     : 0u;
  const uint64_t defect_boot = g_frames_total < 600 ? 1u : 0u;
  const uint64_t defect_calls = (complete != 5 || max_instructions > 2) ? 1u : 0u;
  autoport_proof::publish("codegen_markers_complete", complete);
  autoport_proof::publish("codegen_call_sites", sites);
  autoport_proof::publish("codegen_reduced_call_sites", reduced);
  autoport_proof::publish("codegen_call_max_instructions", max_instructions);
  autoport_proof::publish("codegen_boot_frames", g_frames_total);
  autoport_proof::publish("codegen_refset_present", refset_present);
  autoport_proof::publish("codegen_refset_maxdiff_seen", refset_present ? refset_diff : 255);
  autoport_proof::publish("codegen_refset_control_seen", control_present ? control_diff : 255);
  autoport_proof::publish("codegen_defect_refset", defect_refset);
  autoport_proof::publish("codegen_defect_boot", defect_boot);
  autoport_proof::publish("codegen_defect_calls", defect_calls);
  // Le terme de GAIN (livrable N : « un gain nul ou negatif est un defaut ») ne peut pas se
  // calculer ici : un seul processus `gk` ne voit qu'un bras. `lib/census/<id>.sh` REPUBLIE
  // `codegen_lot_defects` en y ajoutant `codegen_defect_gain`, et c'est sa valeur, derniere
  // ecrite, que porte proof.txt. La valeur ci-dessous est celle des trois termes du moteur.
  autoport_proof::publish("codegen_lot_defects", defect_refset + defect_boot + defect_calls);
  // Hits identify the reduced sites observed in the running process. The
  // separate frame counter proves survival; this is not a dynamic call count.
  autoport_proof::note_hit_for(kCodegenItem, reduced);
}

constexpr const char* kCodegenScalarItem = "perf-codegen-arm64-scalar";
AUTOPORT_FEATURE_SITE(kCodegenScalarItem);

// perf-codegen-arm64-scalar — what the device actually runs. The scan reads the
// LINKED code of the global heap (ENGINE + GAME), once, after 600 drawn frames:
// a CGO that still carries a legacy float->int / divide / swizzle sequence was
// not rebuilt by this item's goalc, and a family with no new sequence never
// reached the device. The results are republished every 60 frames with the
// boot count, like `publish_codegen_calls`. The numeric parity of the sequences
// is not judged here: .autoport/tests/codegen_scalar executes them on the same
// device and lib/census/perf-codegen-arm64-scalar.sh adds its verdict.
struct ScalarScan {
  bool done = false;
  bool hits_noted = false;
  uint64_t words = 0;
  codegen_arm64::ScalarStats stats;
};
ScalarScan g_scalar_scan;

void publish_codegen_scalar() {
  if (!autoport_proof::feature_is(kCodegenScalarItem) || g_frames_total % 60 != 0) {
    return;
  }
#if defined(__aarch64__)
  if (!g_scalar_scan.done && g_frames_total >= 600 && g_game_version == GameVersion::Jak1 &&
      g_ee_main_mem && kglobalheap.offset) {
    const uint32_t base = kglobalheap->base.offset;
    const uint32_t current = kglobalheap->current.offset;
    if (base && current > base && (base & 3u) == 0) {
      const auto* w = reinterpret_cast<const uint32_t*>(g_ee_main_mem + base);
      g_scalar_scan.words = (current - base) / 4;
      g_scalar_scan.stats = codegen_arm64::inspect_scalar(w, g_scalar_scan.words);
      g_scalar_scan.done = true;
    }
  }
#endif
  const auto& st = g_scalar_scan.stats;
  const uint64_t div_old = st.div_total - st.div_new;
  // A family counts as a defect when its new form is absent, or when any legacy
  // form of it is still linked. No scan (x86, or before frame 600) is a defect.
  const uint64_t defect_sites =
      (!g_scalar_scan.done || g_scalar_scan.words == 0) ? 1u
      : (st.f2i_new == 0 || st.div_new == 0 || st.swz_cross_new == 0 || st.f2i_old ||
         div_old || st.swz_old || st.pshuf_old)
          ? 1u
          : 0u;
  const uint64_t defect_boot = g_frames_total < 600 ? 1u : 0u;
  autoport_proof::publish("codegen_scalar_scanned", g_scalar_scan.done);
  autoport_proof::publish("codegen_scalar_scanned_words", g_scalar_scan.words);
  autoport_proof::publish("codegen_scalar_f2i_new", st.f2i_new);
  autoport_proof::publish("codegen_scalar_f2i_old", st.f2i_old);
  autoport_proof::publish("codegen_scalar_div_new", st.div_new);
  autoport_proof::publish("codegen_scalar_div_old", div_old);
  autoport_proof::publish("codegen_scalar_swz_cross_new", st.swz_cross_new);
  autoport_proof::publish("codegen_scalar_swz_old", st.swz_old);
  autoport_proof::publish("codegen_scalar_pshuf_old", st.pshuf_old);
  autoport_proof::publish("codegen_boot_frames", g_frames_total);
  autoport_proof::publish("codegen_defect_boot", defect_boot);
  autoport_proof::publish("codegen_defect_sites", defect_sites);
  // The census hook republishes `codegen_lot_defects` with the parity term added;
  // proof.txt keeps the last value written.
  autoport_proof::publish("codegen_lot_defects", defect_boot + defect_sites);
  // Hits = re-emitted sites found linked on the device, counted once.
  if (g_scalar_scan.done && !g_scalar_scan.hits_noted) {
    autoport_proof::note_hit_for(kCodegenScalarItem,
                                 st.f2i_new + st.div_new + st.swz_cross_new);
    g_scalar_scan.hits_noted = true;
  }
}

constexpr const char* kCodegenRegsItem = "perf-codegen-arm64-regs";
AUTOPORT_FEATURE_SITE(kCodegenRegsItem);

// perf-codegen-arm64-regs — what the device actually runs. Before this item goalc
// allocated X0-X15 and V16-V31 only (X16/X17 and V0-V2 are emitter scratch), so a
// count of X19-X28 / V3-V15 references well above the host's own count for the legacy
// build (a few dozen, from the #f-into-vector moves this item also fixes),
// read from the LINKED code of the global heap (ENGINE + GAME) after 600 drawn
// frames, proves the new CGO — the one goalc now emits with the wider register set
// — is the one actually linked on the device. The same header
// (game/system/codegen_arm64_regs.h) is compiled by the host test
// (.autoport/tests/codegen_regs), so it cannot drift from goalc without that test
// going red. The results are republished every 60 frames with the boot count, like
// publish_codegen_scalar.
struct RegsScan {
  bool done = false;
  bool hits_noted = false;
  uint64_t words = 0;
  codegen_arm64::RegsStats stats;
};
RegsScan g_regs_scan;

void publish_codegen_regs() {
  if (!autoport_proof::feature_is(kCodegenRegsItem) || g_frames_total % 60 != 0) {
    return;
  }
#if defined(__aarch64__)
  if (!g_regs_scan.done && g_frames_total >= 600 && g_game_version == GameVersion::Jak1 &&
      g_ee_main_mem && kglobalheap.offset) {
    const uint32_t base = kglobalheap->base.offset;
    const uint32_t current = kglobalheap->current.offset;
    if (base && current > base && (base & 3u) == 0) {
      const auto* w = reinterpret_cast<const uint32_t*>(g_ee_main_mem + base);
      g_regs_scan.words = (current - base) / 4;
      g_regs_scan.stats = codegen_arm64::inspect_regs(w, g_regs_scan.words);
      g_regs_scan.done = true;
    }
  }
#endif
  const auto& st = g_regs_scan.stats;
  // No scan (x86, or before frame 600), an empty scan, or no hit on either new family
  // are defects. x18 is published, not judged here: the heap also holds DATA, and a
  // data word can match a pattern with a field of 18. The host verifier judges X18 on
  // decoded code (lib/census/perf-codegen-arm64-regs.sh), and compares these counts
  // with its own: the device may count more (data), never less.
  const uint64_t defect_sites = (!g_regs_scan.done || g_regs_scan.words == 0 ||
                                  st.gpr_new == 0 || st.v_new == 0)
                                     ? 1u
                                     : 0u;
  const uint64_t defect_boot = g_frames_total < 600 ? 1u : 0u;
  autoport_proof::publish("codegen_regs_scanned", g_regs_scan.done);
  autoport_proof::publish("codegen_regs_scanned_words", g_regs_scan.words);
  autoport_proof::publish("codegen_regs_gpr_new", st.gpr_new);
  autoport_proof::publish("codegen_regs_v_new", st.v_new);
  autoport_proof::publish("codegen_regs_x18", st.x18);
  autoport_proof::publish("codegen_boot_frames", g_frames_total);
  autoport_proof::publish("codegen_defect_boot", defect_boot);
  autoport_proof::publish("codegen_defect_sites", defect_sites);
  // The census hook republishes `codegen_lot_defects` with its own terms added;
  // proof.txt keeps the last value written.
  autoport_proof::publish("codegen_lot_defects", defect_boot + defect_sites);
  // Hits = new-register sites found linked on the device, counted once.
  if (g_regs_scan.done && !g_regs_scan.hits_noted) {
    autoport_proof::note_hit_for(kCodegenRegsItem, st.gpr_new + st.v_new);
    g_regs_scan.hits_noted = true;
  }
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
  // Cumul de COURSE, avant toute remise a zero de la fenetre.
  g_run_busy_ns += busy;
  g_run_busy_frames += g_frames_window;
  ++g_run_busy_windows;
  const uint64_t win_us = (busy / 1000) / frames;
  if (g_run_busy_windows == 1 || win_us < g_run_busy_win_min_us) {
    g_run_busy_win_min_us = win_us;
  }
  if (win_us > g_run_busy_win_max_us) {
    g_run_busy_win_max_us = win_us;
  }
  // Ces cinq cles sortent a CHAQUE fenetre, sans garde de feature : elles
  // doivent exister sur les DEUX bras, y compris celui lance avec --off.
  autoport_proof::publish(
      "codegen_busy_us",
      g_run_busy_frames ? (g_run_busy_ns / 1000) / g_run_busy_frames : (uint64_t)0);
  autoport_proof::publish("codegen_busy_frames", g_run_busy_frames);
  autoport_proof::publish("codegen_busy_windows", g_run_busy_windows);
  autoport_proof::publish("codegen_busy_win_min_us", g_run_busy_win_min_us);
  autoport_proof::publish("codegen_busy_win_max_us", g_run_busy_win_max_us);

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
  Mips2C::census::frame_boundary();
  g_frames_total++;
  publish_codegen_calls();
  publish_codegen_scalar();
  publish_codegen_regs();
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
