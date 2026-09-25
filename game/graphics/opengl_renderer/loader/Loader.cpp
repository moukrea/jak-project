#include "Loader.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/origin_ablate.h"
#include "game/system/water_census.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifdef __ANDROID__
#include <malloc.h>
// Gcutscene-npc-flicker (essai 17) : `debug.opengoal.evict.maxlevels`, le levier de pression.
#include <sys/system_properties.h>
#endif
#include <set>

#include "common/custom_data/LightBake.h"
#include "common/custom_data/LocalLights.h"
#include "common/custom_data/MeshConsolidate.h"
#include "common/goal_constants.h"
#include "common/global_profiler/GlobalProfiler.h"
#include "common/log/log.h"
#include "common/versions/versions.h"
#include "common/util/FileUtil.h"
#include "common/util/Timer.h"
#include "common/util/compress.h"
#include "common/util/rss_census.h"
#include "game/graphics/opengl_renderer/background/foliage_wind.h"

#ifdef __ANDROID__
#include <malloc.h>
#endif

#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#include "game/graphics/opengl_renderer/loader/LoaderStages.h"
#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/runtime.h"
#include "game/system/autoport_proof.h"
#include "game/system/asset_manifest.h"
#include "game/system/load_gate.h"
#include "game/system/npc_flicker.h"

#include "third-party/imgui/imgui.h"
AUTOPORT_FEATURE_SITE("recharged-texture-hotreload");
AUTOPORT_FEATURE_SITE("cutscene-npc-flicker");
AUTOPORT_FEATURE_SITE("mesh-consolidate-without-consumer");

// ============================================================================================
// Gcutscene-npc-flicker — L'AGE D'UN NIVEAU, ET POURQUOI LE MAIRE DISPARAISSAIT
//
// Mesure prise sur le Honor de l'owner le 2026-09-05
// (.autoport/reports/cutscene-npc-flicker/owner-honor/npc_flicker-honor-2026-09-05.txt) :
//   NPCFLICK scene=mayor-introduction pnj=mayor-lod0 cycles=4 modele_absent=8 trou_max=317
//            images=3564 dessine=1624
//   NPCCULL  scene=mayor-introduction pnj=mayor-lod0 npc=1 noir_dans_frustum=1823
//            images_dans_frustum=3448 images=3564
// Le maire est DANS le champ 3448 images sur 3564 et n'est dessine que 1624 fois. Les huit
// episodes durent 3577, 3825, 3920, 3930, 3949, 4033, 4075 et 4127 ms — une periode, pas du
// bruit. `cause=modele-absent` designe UN site : Merc2.cpp:2330, `!model_ref`, c'est-a-dire
// `Loader::get_merc_model("mayor-lod0")` qui rend `nullopt` parce que le niveau qui porte ce
// modele a ete EVINCE (Loader.cpp, `for (auto& model : lev->level->merc_data.models)` : les
// entrees de `m_all_merc_models` partent avec le niveau).
//
// Les quatre correctifs precedents vivaient tous dans Merc2 (couverture HD, TTL par acteur,
// clone, fail-open) — au point de CONSTAT. Le point de PRODUCTION est ici.
// ============================================================================================

// Le seuil d'age au-dela duquel `get_most_unloadable_level` accepte d'evincer. C'etait deux
// litteraux `180` dans cette fonction ; la garde de non-regression a besoin d'UNE definition.
static constexpr int kUnloadAgeFrames = 180;
// Tolerance de la marque merc, en images. Voir le pave de la boucle d'age dans Loader::update.
static constexpr uint64_t kMercKeepaliveFrames = 2;

// L'horloge de la boucle d'age. Une image de `Loader::update` = un pas. Elle n'a pas besoin
// d'etre l'horloge de rendu : les deux tournent sur le meme thread, une fois par image.
static uint64_t s_level_age_frame = 0;
// Images ou un niveau a ete garde resident parce qu'il fournissait un modele merc dessine.
static uint64_t s_npcf_merc_keepalive_frames = 0;
// L'EVENEMENT contrefactuel : le niveau vient de franchir kUnloadAgeFrames dans l'age SANS le
// correctif, alors qu'un de ses modeles merc etait dessine. Une occurrence = une disparition de
// PNJ que l'ancien code produisait et que celui-ci empeche.
static uint64_t s_npcf_evictable_while_drawing = 0;
// Evictions reellement executees, et parmi elles celles qui ont emporte un niveau dont un modele
// merc venait d'etre dessine. LE SECOND DOIT RESTER A ZERO ; le premier est le DENOMINATEUR,
// sans lequel un zero ne dit pas si la situation s'est presentee.
static uint64_t s_npcf_evictions = 0;
static uint64_t s_npcf_evict_with_live_merc = 0;
// Evictions prises par la passe RESCAPE (essai 16) : un niveau que le jeu ne nomme plus, evince
// AVANT qu'on touche a un niveau desire. Chacune est un sacrifice que l'ancien ordre faisait
// porter a un niveau encore demande.
static uint64_t s_npcf_evict_straggler = 0;
// Gcutscene-npc-flicker (essai 17) — LES REFUS. Chaque occurrence est une eviction que l'une des
// trois passes de `get_most_unloadable_level` avait RETENUE et que la garde merc a annulee :
// autrement dit un clignotement de PNJ qui n'a pas eu lieu. C'est le pendant ACTIF de
// `npc_evict_with_live_merc`, qui lui ne faisait que constater la faute une fois commise.
static uint64_t s_npcf_evict_refused_live_merc = 0;
// Delai de grace avant qu'un niveau lache par GOAL devienne evincable. `m_desired_levels` est
// reecrit a chaque image depuis `level-update` ; une image de battement pendant un changement de
// statut ne doit pas suffire a jeter un niveau. 30 images = un demi-quart de la fenetre de 180,
// et deux ordres de grandeur sous le cout d'un rechargement (202-317 images mesurees).
static constexpr int kNotDesiredGraceFrames = 30;

// ============================ L'OCCASION, SANS LAQUELLE LE ZERO NE VAUT RIEN ==================
// Treize essais ont publie `npc_evict_with_live_merc = 0` / `npc_flicker_episodes = 0` pendant que
// l'owner voyait le maire clignoter. La raison n'etait pas que le correctif marchait : c'est que
// la BRANCHE D'EVICTION n'etait jamais atteinte. Elle demande
// `m_loaded_tfrag3_levels.size() >= m_max_levels`, or `m_max_levels` vaut 3 en jak1
// (common/goal_constants.h:46-48, identique x86 et arm64) et la course du harnais n'a jamais tenu
// que DEUX niveaux residents. Un zero sur un mecanisme qui n'a pas tourne est un zero muet, pas un
// verdict. Ces compteurs publient le DENOMINATEUR : si `npc_evict_pressure_frames` vaut 0, la
// course n'a rien mesure et il faut le lire dans le rapport, pas conclure que c'est corrige.
static uint64_t s_npcf_evict_pressure_frames = 0;  // images ou la branche d'eviction est ATTEINTE
static uint64_t s_npcf_loaded_levels_max = 0;      // maximum de niveaux residents dans la course
// Eviction choisie par la SECONDE passe de `get_most_unloadable_level` : un niveau que GOAL veut
// encore (il est dans `m_desired_levels`). C'est celle qui emporte `beach` pendant que le maire
// est a l'ecran ; la premiere passe ne touche que les niveaux dont GOAL s'est deja desinteresse.
static uint64_t s_npcf_evict_pass2 = 0;
// L'ECHEC DE `get_merc_model`, SEPARE EN SES DEUX CAS. Ils n'ont pas la meme cause et les
// confondre a envoye les essais precedents chercher dans le chargement ce qui se passe dans
// l'eviction : la cle ABSENTE = le modele n'a jamais ete charge ; le vecteur VIDE = le niveau qui
// le portait a ete evince (Loader.cpp, boucle `mercs.erase(it)` : elle vide le vecteur et laisse
// la cle en place). `mayor-lod0` n'existe que dans `beach.fr3` : son vecteur a UN element, donc
// une eviction de `beach` le vide entierement.
static uint64_t s_npcf_merc_vec_empty = 0;
static uint64_t s_npcf_merc_key_missing = 0;
// Age maximum atteint par un niveau resident. `kUnloadAgeFrames` = 180 : un maximum qui reste
// sous 180 dit que rien n'etait evincable, un maximum au-dessus dit que la porte avait matiere.
static uint64_t s_npcf_level_age_max = 0;
// Tous ces compteurs sont ecrits depuis le thread graphique — `Loader::update` et
// `Loader::get_merc_model` (appele par `Merc2::render`) y tournent tous les deux, une fois par
// image. Pas d'atomique, comme les quatre compteurs au-dessus.

// LA SOURCE 4 DE LA LIGNE `NPCPLAT` — voir le pave « troisieme source » de npc_flicker.h.
// Ces six cases partent dans `<dossier settings>/npc_flicker.txt`, le SEUL canal par lequel une
// mesure prise sur le Honor de l'owner nous revient. Sans elles, la chaine du maire n'etait
// visible que dans proof.txt, c'est-a-dire seulement sur des courses qui ne la reproduisent pas.
// npc_flicker publie la DIFFERENCE par scene : ces compteurs doivent donc rester monotones.
static void npcf_loader_counters(uint64_t* out, int n) {
  if (n < npc_flicker::kPlatCounterCount) {
    return;
  }
  out[npc_flicker::kPlatEvictPressure] = s_npcf_evict_pressure_frames;
  out[npc_flicker::kPlatEvictions] = s_npcf_evictions;
  out[npc_flicker::kPlatEvictPass2] = s_npcf_evict_pass2;
  out[npc_flicker::kPlatEvictLiveMerc] = s_npcf_evict_with_live_merc;
  out[npc_flicker::kPlatMercVecEmpty] = s_npcf_merc_vec_empty;
  out[npc_flicker::kPlatMercKeyMissing] = s_npcf_merc_key_missing;
  out[npc_flicker::kPlatEvictStraggler] = s_npcf_evict_straggler;
}

// lighting-bake (SPEC-refonte-lumiere §5.5) : relit <niveau>.lightbake a cote du fr3 et VERIFIE que
// la palette B (l'indirect) plus le direct recalcule redonnent la palette A, sur un index sur 64.
// La table de mood est lue dans la memoire GOAL, telle que le jeu la voit : un compagnon cuit contre
// une autre table (mood_hash) est rejete. Rien n'est ecrit dans la palette A ; en version 1 la
// palette B n'est pas encore consommee par le rendu (elle le sera par shade()), elle n'est donc pas
// gardee en memoire apres la verification.
constexpr const char* kLightBakeItem = "lighting-bake";
AUTOPORT_FEATURE_SITE(kLightBakeItem);
static float s_bake_maxdelta = 0.f;
static uint64_t s_bake_levels_verified = 0, s_bake_levels_rejected = 0, s_bake_levels_missing = 0;
static uint64_t s_bake_indices = 0, s_bake_trees_rejected = 0, s_bake_palette_a_changed = 0;

// lighting-local-lights (SPEC-refonte-lumiere §4.9, §5.7.1) : lecture de la section kSecLights du
// compagnon .lightbake, INDEPENDANTE de la porte lighting-bake, plus le recensement vivant du
// lexique light_emitters.txt et des candidats light_candidates.txt.
constexpr const char* kLocalLightsItem = "lighting-local-lights";
AUTOPORT_FEATURE_SITE(kLocalLightsItem);
// Noms de prototype candidats (jeton d'emetteur, §5.3.8) vus dans TOUS les niveaux TIE charges
// depuis le demarrage du processus : l'union grandit, elle ne retombe jamais quand un niveau est
// evince.
static std::set<std::string> s_ll_live_candidates;

static std::string ll_sanitize_level_key(const std::string& level_name) {
  std::string out;
  out.reserve(level_name.size());
  for (char c : level_name) {
    if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') {
      out.push_back(c);
    } else {
      out.push_back('_');
    }
  }
  return out;
}

// Parcours minimal du meme format de section que tfrag3::lightbake::deserialize (LightBake.cpp) :
// on n'a besoin que du corps de la section kSecLights, pas de reconstruire tout `Bake`.
static bool ll_find_lights_section(const std::vector<u8>& bytes, const u8** out_body,
                                    u32* out_size) {
  const u8* p = bytes.data();
  const u8* e = bytes.data() + bytes.size();
  auto need = [&](size_t n) { return (size_t)(e - p) >= n; };
  auto get_u32 = [&]() -> u32 {
    u32 v = 0;
    memcpy(&v, p, 4);
    p += 4;
    return v;
  };
  if (!need(4) || get_u32() != tfrag3::lightbake::kMagic) {
    return false;
  }
  if (!need(4) || get_u32() != tfrag3::lightbake::kVersion) {
    return false;
  }
  if (!need(4)) return false;
  u32 name_len = get_u32();
  if (!need(name_len)) return false;
  p += name_len;
  if (!need(4)) return false;
  get_u32();  // num_verts
  if (!need(4)) return false;
  u32 nt = get_u32();
  if (nt > 100000) return false;
  const size_t tree_hdr_bytes = (size_t)nt * (1 + 1 + 4 + 4 + 8);
  if (!need(tree_hdr_bytes)) return false;
  p += tree_hdr_bytes;
  if (!need(8)) return false;
  get_u32();  // tfrag3_version
  get_u32();  // mood_hash
  while (p < e) {
    if (!need(8)) return false;
    u32 sec = get_u32();
    u32 sz = get_u32();
    if (!need(sz)) return false;
    if (sec == (u32)tfrag3::lightbake::kSecLights) {
      *out_body = p;
      *out_size = sz;
      return true;
    }
    p += sz;
  }
  return false;
}

static std::vector<local_lights::Light> lighting_local_lights_load(const tfrag3::Level& lev) {
  std::vector<local_lights::Light> out;
  namespace lb = tfrag3::lightbake;
  const auto name = lb::lightbake_name(lev.level_name);
  const auto route = file_util::resolve_fr3_asset(g_game_version, name);
  if (!fs::exists(route.path)) {
    lg::info("[lighting-local-lights] level={} pas de compagnon ({})", lev.level_name,
             route.path.string());
    autoport_proof::publish(("lights_extracted_" + ll_sanitize_level_key(lev.level_name)).c_str(),
                            0);
    return out;
  }
  const auto bytes = file_util::read_binary_file(route.path);
  const u8* body = nullptr;
  u32 size = 0;
  if (!ll_find_lights_section(bytes, &body, &size)) {
    lg::warn("[lighting-local-lights] level={} section LIGHTS introuvable/corrompue",
             lev.level_name);
  } else if (!local_lights::deserialize(body, size, out)) {
    lg::warn("[lighting-local-lights] level={} enregistrements LIGHTS corrompus", lev.level_name);
    out.clear();
  }
  autoport_proof::publish(("lights_extracted_" + ll_sanitize_level_key(lev.level_name)).c_str(),
                          (uint64_t)out.size());
  autoport_proof::note_hit_for(kLocalLightsItem, out.size() + 1);
  return out;
}

// Recensement vivant : relu a CHAQUE chargement (SPEC §5.7.1) — le lexique et le fichier de
// candidats peuvent changer sans reconstruction du binaire.
static void lighting_local_lights_census(const tfrag3::Level& lev) {
  namespace ll = local_lights;
  if (!lev.tie_trees.empty()) {
    for (const auto& t : lev.tie_trees[0]) {
      for (const auto& proto : t.proto_names) {
        if (ll::is_candidate(proto)) {
          s_ll_live_candidates.insert(proto);
        }
      }
    }
  }

  ll::Lexicon lex = ll::load_lexicon(ll::default_lexicon_path());
  const auto route = file_util::resolve_fr3_asset(g_game_version, "light_candidates.txt");
  bool cand_ok = false;
  auto candidates = ll::load_candidates(route.path.string(), &cand_ok);
  autoport_proof::publish("lights_candidates_file", cand_ok ? 1 : 0);

  if (!lex.loaded) {
    autoport_proof::publish_text("lights_unjudged", "lexique_absent");
    return;
  }
  if (!cand_ok) {
    autoport_proof::publish_text("lights_unjudged", "candidats_absents");
    return;
  }

  std::set<std::string> U;
  uint64_t instances_sum = 0;
  for (const auto& c : candidates) {
    U.insert(c.proto);
    instances_sum += (uint64_t)c.instances;
  }
  for (const auto& p : s_ll_live_candidates) {
    U.insert(p);
  }

  std::vector<std::string> unjudged;
  for (const auto& p : U) {
    if (!lex.judged(p)) {
      unjudged.push_back(p);
    }
  }

  autoport_proof::publish("lights_unjudged", (uint64_t)unjudged.size());
  autoport_proof::publish("lights_candidates", (uint64_t)U.size());
  autoport_proof::publish("lights_candidate_instances", instances_sum);
  autoport_proof::publish("lights_lexicon_bad_lines", (uint64_t)lex.bad_lines);
  autoport_proof::publish("lights_lexicon_rules",
                          (uint64_t)(lex.lights.size() + lex.excluded.size()));
  if (unjudged.empty()) {
    autoport_proof::publish_text("lights_unjudged_list", "-");
  } else {
    std::string joined;
    for (size_t i = 0; i < unjudged.size(); i++) {
      if (i) joined += ",";
      joined += unjudged[i];
    }
    autoport_proof::publish_text("lights_unjudged_list", joined.c_str());
  }
  autoport_proof::note_hit_for(kLocalLightsItem, 1);
}

static bool read_live_mood_table(const std::string& level, tfrag3::lightbake::MoodTable& out) {
  if (g_game_version != GameVersion::Jak1 || !g_ee_main_mem) {
    return false;
  }
  const std::string name = "*" + level + "-mood-lights-table*";
  auto sym = jak1::find_symbol_from_c(name.c_str());
  if (sym.offset == 0) {
    return false;
  }
  const u32 addr = sym->value;
  // mood-lights-table : 8 × mood-lights, chacun 5 vecteurs de 16 octets
  // (direction, lgt-color, prt-color, amb-color, shadow)
  if (addr < 16 || (u64)addr + 8 * 80 > (u64)EE_MAIN_MEM_SIZE) {
    return false;
  }
  const u8* base = g_ee_main_mem + addr;
  for (int s = 0; s < tfrag3::lightbake::kSlots; s++) {
    const float* f = (const float*)(base + s * 80);
    auto& m = out.slot[s];
    for (int i = 0; i < 3; i++) {
      m.direction[i] = f[0 + i];
      m.lgt[i] = f[4 + i];
      m.amb[i] = f[12 + i];
      m.shadow[i] = f[16 + i];
    }
  }
  return true;
}

static void lighting_bake_verify_level(const tfrag3::Level& lev) {
  namespace lb = tfrag3::lightbake;
  const auto name = lb::lightbake_name(lev.level_name);
  const auto route = file_util::resolve_fr3_asset(g_game_version, name);
  if (!fs::exists(route.path)) {
    s_bake_levels_missing++;
    autoport_proof::publish("bake_levels_missing", s_bake_levels_missing);
    lg::info("[lighting-bake] level={} pas de compagnon ({})", lev.level_name, route.path.string());
    return;
  }
  auto reject = [&](const std::string& why) {
    s_bake_levels_rejected++;
    autoport_proof::publish("bake_levels_rejected", s_bake_levels_rejected);
    autoport_proof::publish_text("bake_last_reject", (lev.level_name + ":" + why).c_str());
    lg::warn("[lighting-bake] level={} compagnon REJETE : {}", lev.level_name, why);
  };
  lb::Bake bake;
  std::string err;
  const auto bytes = file_util::read_binary_file(route.path);
  if (!lb::deserialize(bytes, bake, &err)) {
    reject(err);
    return;
  }
  lb::MoodTable live;
  if (!read_live_mood_table(lev.level_name, live)) {
    reject("mood-table-introuvable");
    return;
  }
  // la palette A avant / apres : la verification n'y ecrit rien, et ca se compte
  const auto refs = lb::collect_trees(lev);
  std::vector<std::vector<u8>> before;
  before.reserve(refs.size());
  for (const auto& r : refs) {
    before.push_back(r.colors->data);
  }
  const auto res = lb::verify(lev, bake, live, 64, 1u << 20);
  for (size_t i = 0; i < refs.size(); i++) {
    const auto& now = refs[i].colors->data;
    for (size_t k = 0; k < now.size() && k < before[i].size(); k++) {
      s_bake_palette_a_changed += now[k] != before[i][k];
    }
  }
  autoport_proof::publish("palette_a_bytes_changed", s_bake_palette_a_changed);
  if (!res.accepted) {
    reject(res.reject_reason);
    return;
  }
  s_bake_trees_rejected += res.trees_rejected;
  autoport_proof::publish("bake_trees_rejected", s_bake_trees_rejected);
  if (res.indices_checked == 0) {
    reject("aucun-index-verifie");
    return;
  }
  s_bake_levels_verified++;
  s_bake_indices += res.indices_checked;
  s_bake_maxdelta = std::max(s_bake_maxdelta, std::max(res.maxdelta, res.maxdelta_b));
  autoport_proof::note_hit_for(kLightBakeItem, res.indices_checked);
  autoport_proof::publish("bake_levels_verified", s_bake_levels_verified);
  autoport_proof::publish("bake_verified_indices", s_bake_indices);
  // arrondi VERS LE HAUT : la porte ne voit jamais moins que l'ecart reel
  autoport_proof::publish("bake_reconstruction_maxdelta", (uint64_t)std::ceil(s_bake_maxdelta));
  autoport_proof::publish("bake_reconstruction_maxdelta_milli",
                          (uint64_t)std::lround(s_bake_maxdelta * 1000.f));
  autoport_proof::publish_text("bake_last_level", lev.level_name.c_str());
  lg::info(
      "[lighting-bake] level={} trees={} trees_rejected={} indices={} values={} clamped={} "
      "maxdelta={:.4f} maxdelta_b={:.4f} mood_hash={:08x} bytes={}",
      lev.level_name, res.trees_checked, res.trees_rejected, res.indices_checked,
      res.values_checked, res.clamped_checked, res.maxdelta, res.maxdelta_b, bake.mood_hash,
      bytes.size());
}

static void publish_level_age_counters() {
  autoport_proof::publish("npc_merc_keepalive_frames", s_npcf_merc_keepalive_frames);
  autoport_proof::publish("npc_evictable_while_drawing", s_npcf_evictable_while_drawing);
  autoport_proof::publish("npc_level_evictions", s_npcf_evictions);
  autoport_proof::publish("npc_evict_with_live_merc", s_npcf_evict_with_live_merc);
  autoport_proof::publish("npc_evict_straggler", s_npcf_evict_straggler);
  autoport_proof::publish("npc_evict_refused_live_merc", s_npcf_evict_refused_live_merc);
  autoport_proof::publish("npc_evict_pressure_frames", s_npcf_evict_pressure_frames);
  autoport_proof::publish("npc_loaded_levels_max", s_npcf_loaded_levels_max);
  autoport_proof::publish("npc_evict_pass2", s_npcf_evict_pass2);
  autoport_proof::publish("npc_merc_vec_empty", s_npcf_merc_vec_empty);
  autoport_proof::publish("npc_merc_key_missing", s_npcf_merc_key_missing);
  autoport_proof::publish("npc_level_age_max", s_npcf_level_age_max);
  // mesh-consolidate-without-consumer : le temps de chargement paye pour une sortie sans lecteur.
  // LE DENOMINATEUR D'ABORD — sans chargement consolide, un zero de temps ne mesure rien, et la
  // grandeur publiee est une SENTINELLE qui fait rougir la porte au lieu de la laisser verte par
  // inaction.
  const uint64_t mc_loads = tfrag3::mesh_consolidate_loads();
  autoport_proof::publish("mesh_consolidate_loads", mc_loads);
  autoport_proof::publish("mesh_consolidate_sidecar_loads", tfrag3::mesh_consolidate_sidecar_loads());
  autoport_proof::publish("mesh_consolidate_live_loads", tfrag3::mesh_consolidate_live_loads());
  autoport_proof::publish("mesh_consolidate_total_ms_x100",
                          (tfrag3::mesh_consolidate_total_ns() + 5000) / 10000);
  autoport_proof::publish("mesh_unconsumed_verts_skipped", tfrag3::mesh_unconsumed_skipped());
  autoport_proof::publish("mesh_consolidate_waste_ms_x100",
                          mc_loads == 0 ? (uint64_t)999999
                                        : (tfrag3::mesh_unconsumed_ns() + 5000) / 10000);
  // La ligne que BRAS 2 de la garde (.autoport/lib/npcf_dead_counter_gate.py) inspecte : un
  // compteur imprime ici doit avoir un site d'ecriture ailleurs, sinon la garde mord.
  static uint64_t s_beat = 0;
  if (s_beat++ % 1800 == 0) {
    lg::info("[npc-flicker/loader] keepalive={} evincable_en_dessinant={} evictions={} "
             "eviction_avec_merc_vivant={} refus_merc_vivant={} pression={} niveaux_max={} "
             "passe2={} vecteur_vide={} cle_absente={} age_max={}",
             s_npcf_merc_keepalive_frames, s_npcf_evictable_while_drawing, s_npcf_evictions,
             s_npcf_evict_with_live_merc, s_npcf_evict_refused_live_merc,
             s_npcf_evict_pressure_frames, s_npcf_loaded_levels_max, s_npcf_evict_pass2,
             s_npcf_merc_vec_empty, s_npcf_merc_key_missing, s_npcf_level_age_max);
  }
}

// ==============================================================================================
// Gcutscene-npc-flicker (essai 17) — LE LEVIER QUI REND LA COURSE FALSIFIABLE.
//
// La branche d'eviction demande `m_loaded_tfrag3_levels.size() >= m_max_levels`, soit TROIS
// niveaux residents en jak1. La course du harnais warpe directement sur `village1-hut` et n'en
// tient que DEUX : la branche n'est jamais atteinte, `npc_evict_pressure_frames` vaut 1 sur
// 24903 images, et le `npc_flicker_episodes = 0` qui en sort est un zero MUET — le mecanisme n'a
// pas tourne, il n'a pas ete repare. Treize verdicts verts sont sortis de la pendant que l'owner
// voyait le maire clignoter.
//
// Ce reglage abaisse le plafond pour la duree d'une course de preuve, ce qui met la pression a
// CHAQUE image et fait passer les trois passes de `get_most_unloadable_level` sur des niveaux qui
// dessinent reellement le maire. Il ne change RIEN au binaire livre : sans la propriete, la
// valeur reste celle que `opengl.cpp` calcule (`fr3_level_count`).
static int npcf_max_levels_override(int fallback) {
  char buf[32] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get("debug.opengoal.evict.maxlevels", buf) > 0 && buf[0]) {
    have = true;
  }
#else
  const char* e = std::getenv("OG_EVICT_MAXLEVELS");
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  if (!have) {
    return fallback;
  }
  const int v = std::atoi(buf);
  // Un plafond sous 2 empecherait le niveau courant ET le niveau streame de coexister : ce
  // n'est plus un test de pression, c'est un jeu casse. On refuse en le disant.
  if (v < 2 || v > 16) {
    lg::warn("[npc-flicker/loader] plafond de niveaux '{}' hors de [2,16] : ignore, on garde {}",
             buf, fallback);
    return fallback;
  }
  lg::warn("[npc-flicker/loader] PLAFOND DE NIVEAUX FORCE a {} (defaut {}) : la branche "
           "d'eviction est armee pour cette course.",
           v, fallback);
  return v;
}

Loader::Loader(const fs::path& base_path, int max_levels)
    : m_base_path(base_path), m_max_levels(npcf_max_levels_override(max_levels)) {
#ifdef __ANDROID__
  // autoport 2026-08-25: Android's Scudo allocator caches freed blocks rather
  // than returning them. Harmless with 8 GB, fatal with 3 GB. Decay 0 = release
  // as soon as a block is free.
  mallopt(M_DECAY_TIME, 0);
#endif
  // Enregistre le chargeur comme source 4 des compteurs de scene. Fait ici et pas plus tard :
  // `platform_sources()` doit valoir 4 des la premiere scene, sinon un zero sur `evict_pression`
  // se lirait « rien ne s'est passe » alors qu'il veut dire « personne ne compte ».
  npc_flicker::set_loader_counters_fn(&npcf_loader_counters);
  m_loader_thread = std::thread(&Loader::loader_thread, this);
  m_loader_stages = make_loader_stages();
}

Loader::~Loader() {
  {
    std::lock_guard<std::mutex> lk(m_loader_mutex);
    m_want_shutdown = true;
    m_loader_cv.notify_all();
  }
  m_loader_thread.join();
}

/*!
 * Try to get a loaded level by name. It may fail and return nullptr.
 * Getting a level will reset the counter for the level and prevent it from being kicked out
 * for a little while.
 *
 * This is safe to call from the graphics thread
 */
bool Loader::tfrag3_level_is_current(const std::string& level_name, u64 load_id) {
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  const auto& existing = m_loaded_tfrag3_levels.find(level_name);
  return existing != m_loaded_tfrag3_levels.end() && existing->second->load_id == load_id;
}

const LevelData* Loader::get_tfrag3_level(const std::string& level_name) {
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  const auto& existing = m_loaded_tfrag3_levels.find(level_name);
  if (existing == m_loaded_tfrag3_levels.end()) {
    return nullptr;
  } else {
    existing->second->frames_since_last_used = 0;
    // Gcutscene-npc-flicker : l'age CONTREFACTUEL suit le meme geste, sinon il compterait comme
    // « sauve par le correctif » un niveau dont le FOND est dessine — ce que l'ancien code
    // rafraichissait deja. Un instrument qui ne remet pas a zero la ou le vrai compteur le fait
    // ne mesure pas la difference entre les deux, il mesure autre chose.
    existing->second->frames_since_last_used_no_merc = 0;
    return existing->second.get();
  }
}

void Loader::debug_print_loaded_levels() {
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  for (const auto& [name, _] : m_loaded_tfrag3_levels) {
    fmt::print("{}\n", name);
  }
}

/*!
 * The game calls this to give the loader a hint on which levels we want.
 * If the loader is not busy, it will begin loading the level.
 * This should be called on every frame.
 */
void Loader::set_want_levels(const std::vector<std::string>& levels) {
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  m_desired_levels = levels;
  if (!m_level_to_load.empty()) {
    // can't do anything, we're loading a level right now
    return;
  }

  if (!m_initializing_tfrag3_levels.empty()) {
    // can't do anything, we're initializing a level right now
    return;
  }

  // loader isn't busy, try to load one of the requested levels.
  for (auto& lev : levels) {
    auto it = m_loaded_tfrag3_levels.find(lev);
    if (it == m_loaded_tfrag3_levels.end()) {
      // we haven't loaded it yet. Request this level to load and wake up the thread.
      m_level_to_load = lev;
      lk.unlock();
      m_loader_cv.notify_all();
      return;
    }
  }
}

/*!
 * The game calls this to tell the loader that we absolutely want these levels active.
 * This will NOT trigger a load!
 */
void Loader::set_active_levels(const std::vector<std::string>& levels) {
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  m_active_levels = levels;
}

/*!
 * Get all levels that are in memory and used very recently.
 */
std::vector<LevelData*> Loader::get_in_use_levels() {
  std::vector<LevelData*> result;
  std::unique_lock<std::mutex> lk(m_loader_mutex);

  for (auto& [name, lev] : m_loaded_tfrag3_levels) {
    if (lev->frames_since_last_used < 5) {
      result.push_back(lev.get());
    }
  }
  return result;
}

void Loader::draw_debug_window() {
  ImGui::Begin("Loader");
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  ImVec4 blue(0.3, 0.3, 0.8, 1.0);
  ImVec4 red(0.8, 0.3, 0.3, 1.0);
  ImVec4 green(0.3, 0.8, 0.3, 1.0);

  if (!m_desired_levels.empty()) {
    ImGui::Text("desired levels");
    for (auto& lev : m_desired_levels) {
      auto lev_color = red;
      if (m_initializing_tfrag3_levels.find(lev) != m_initializing_tfrag3_levels.end()) {
        lev_color = blue;
      }
      if (m_loaded_tfrag3_levels.find(lev) != m_loaded_tfrag3_levels.end()) {
        lev_color = green;
      }
      ImGui::TextColored(lev_color, "%s", lev.c_str());
      ImGui::SameLine();
    }
    ImGui::NewLine();
    ImGui::Separator();
  }

  if (!m_initializing_tfrag3_levels.empty()) {
    ImGui::Text("init levels");
    for (auto& lev : m_initializing_tfrag3_levels) {
      ImGui::TextColored(blue, "%s", lev.first.c_str());
      ImGui::SameLine();
    }
    ImGui::NewLine();
    ImGui::Separator();
  }

  if (!m_loaded_tfrag3_levels.empty()) {
    ImGui::Text("loaded levels");
    for (auto& lev : m_loaded_tfrag3_levels) {
      auto lev_color = green;
      if (lev.second->frames_since_last_used > 0) {
        lev_color = blue;
      }
      if (lev.second->frames_since_last_used > 180) {
        lev_color = red;
      }
      ImGui::TextColored(lev_color, "%20s : %3d", lev.first.c_str(),
                         lev.second->frames_since_last_used);
      ImGui::Text("  %d textures", (int)lev.second->textures.size());
      ImGui::Text("  %d merc", (int)lev.second->merc_model_lookup.size());
    }
    ImGui::NewLine();
    ImGui::Separator();
  }

  ImGui::End();
}

// Grecharged-master-toggle: the settings.ini seeds below must agree with what the GOAL side
// will conclude from the SAME file. GOAL's read-from-file (goal_src/jak1/pc/pckernel-common.gc)
// DISCARDS the whole file when its version's major.minor differs from the compiled
// PC_KERNEL_VERSION and resets every setting to its default — so a raw substring seed would
// diverge from the runtime state for exactly one stale-versioned boot (observed on device:
// seed=OFF from an old file, GOAL reset to default ON mid-boot). Mirror the guard here.
// These constants mirror goal_src/jak1/pc/pckernel-impl.gc (static-pckernel-version MAJOR
// MINOR rev build); gmt_build_deploy.sh greps both files and dies on drift.
static constexpr int kGoalPckernelVersionMajor = 1;
static constexpr int kGoalPckernelVersionMinor = 11;

// True when settings.ini's `version = #x...` line (layout major<<48|minor<<32|rev<<16|build)
// matches the compiled GOAL pckernel major.minor — i.e. GOAL will actually LOAD this file
// instead of resetting to defaults.
static bool settings_ini_version_current(const std::string& txt) {
  auto pos = txt.find("version = #x");
  if (pos == std::string::npos) {
    return false;
  }
  u64 v = strtoull(txt.c_str() + pos + strlen("version = #x"), nullptr, 16);
  return (int)((v >> 48) & 0xffff) == kGoalPckernelVersionMajor &&
         (int)((v >> 32) & 0xffff) == kGoalPckernelVersionMinor;
}

// Grecharged-hd-models: read the persisted ENHANCED MODELS choice straight from settings.ini. The
// common FR3 (HD Jak+Daxter) loads in the renderer ctor (via load_common) BEFORE GOAL's per-frame push,
// so we seed the flag here to respect the toggle on relaunch. Shared by desktop + Android (both call
// Loader::load_common). Missing file / stale version / #f -> false -> stock (GOAL's reset default).
#ifdef OG_FEAT_HD_MODELS
static bool read_persisted_enhanced_models() {
  try {
    auto p = file_util::get_user_settings_dir(GameVersion::Jak1) / "settings.ini";
    if (!file_util::file_exists(p.string())) {
      return false;
    }
    auto txt = file_util::read_text_file(p);
    if (!settings_ini_version_current(txt)) {
      return false;
    }
    // INI line format: `recharged-enhanced-models? = #t`.
    return txt.find("recharged-enhanced-models? = #t") != std::string::npos;
  } catch (...) {
    return false;
  }
}
#endif

// Grecharged-master-toggle: read the persisted GLOBAL master straight from settings.ini.
// load_common runs in the renderer ctor BEFORE GOAL's per-frame push, and the early loader
// gates (enhanced FR3 select, custom texture replacements) go through Gfx::recharged_active,
// which consults the master — so seed it here or a saved master-OFF would still load
// recharged assets for the first frames. Missing file / stale version / missing key -> ON
// (GOAL's reset default); only an explicit `recharged-master? = #f` line in a
// version-current file disables.
static bool read_persisted_recharged_master() {
  try {
    auto p = file_util::get_user_settings_dir(GameVersion::Jak1) / "settings.ini";
    if (!file_util::file_exists(p.string())) {
      return true;
    }
    auto txt = file_util::read_text_file(p);
    if (!settings_ini_version_current(txt)) {
      return true;
    }
    return txt.find("recharged-master? = #f") == std::string::npos;
  } catch (...) {
    return true;
  }
}

// Grecharged-bundled-textures: read the persisted RECHARGED TEXTURES base-swap toggle straight
// from settings.ini — the common FR3 textures upload in the renderer ctor BEFORE GOAL's first
// per-frame push, and add_texture consults the flag then. Missing file / stale version /
// missing key -> ON (GOAL's reset default); only an explicit `recharged-textures? = #f` line
// in a version-current file disables. NO pckernel version bump was needed for this key: an
// absent key falls through to the same default on both sides.
static bool read_persisted_recharged_textures() {
  try {
    auto p = file_util::get_user_settings_dir(GameVersion::Jak1) / "settings.ini";
    if (!file_util::file_exists(p.string())) {
      return true;
    }
    auto txt = file_util::read_text_file(p);
    if (!settings_ini_version_current(txt)) {
      return true;
    }
    return txt.find("recharged-textures? = #f") == std::string::npos;
  } catch (...) {
    return true;
  }
}

// Grecharged-hd-models: resolve a level's FR3 path, preferring an enhanced (Jak2 HD) variant under
// fr3/enhanced/ when the ENHANCED MODELS toggle is on AND that file exists. Off / missing -> stock
// path, so OFF is byte-identical to stock.
//
// ARCHITECTURE IP (owner 2026-08-02): the enhanced fr3 embed the HD character merc models, which are
// derived from the user's Jak2/Jak3 dumps = Naughty Dog IP. They must NEVER ship inside the APK /
// custom pack (that would distribute ND IP). They are generated LOCALLY from the dump and ship ONLY
// in the EXTERNAL asset pack (scripts/package_hd_assets.sh -> <game>_hd_assets.zip, extracted to
// <external root>/assets/fr3/enhanced/). `base` here is Loader's m_base_path == get_fr3_dir(), which
// IS that external dir on device (android_gfx.cpp) and out/<game>/fr3 on desktop — so we resolve the
// enhanced fr3 STRICTLY from base/enhanced/ and deliberately do NOT consult the APK custom pack
// (get_custom_fr3_dir()): a hit there would mean ND IP had leaked into the binary. The custom pack
// build (android/build_custom_pack.sh) has a matching guard that refuses to stage any enhanced/ member.
// Gmemory-ceiling-and-crash (2026-08-26) — RENDRE LES PAGES LIBEREES A L'OS.
// Mesure sur le Redmi au maximum de la course : l'arene du tas fait 846 MiB mappes pour
// 696 Mo RESIDENTS. Les ~150 Mo d'ecart sont deja LIBRES cote allocateur, mais bionic les
// garde en cache : un `free()` ne fait pas baisser le RSS, et c'est le RSS que le tueur de
// memoire regarde. `mallopt(M_PURGE_ALL)` (bionic, <malloc.h>) rend ces pages tout de suite.
// A n'appeler qu'apres une GROSSE liberation nommee, jamais par frame.
// Hors Android : sans effet, la fonction n'existe pas — le code compile et ne fait rien.
static void heap_purge(const char* pourquoi) {
#if defined(__ANDROID__)
  // PIEGE, mesure : les DEUX macros sont definies INCONDITIONNELLEMENT par le <malloc.h> du
  // NDK r27c (:212 et :221), quel que soit le niveau d'API vise. Un `#if defined(M_PURGE_ALL)`
  // ne dit donc RIEN du systeme qui executera : `M_PURGE_ALL` n'est servi qu'a partir de
  // l'API 34, et le Redmi de test est en API 31 — bionic rend 0 et ne purge rien, pendant
  // qu'un `#elif` laisse `M_PURGE` (servi depuis l'API 28, minSdk du projet 29) en code MORT.
  // Seule la VALEUR DE RETOUR arbitre (malloc.h:363 : 1 = succes, 0 = erreur). On essaie donc
  // les deux, dans l'ordre, et on PUBLIE lequel a pris.
  int ok = 0;
  const char* voie = "aucune";
#if defined(M_PURGE_ALL)
  ok = mallopt(M_PURGE_ALL, 0);
  if (ok) {
    voie = "M_PURGE_ALL";
  }
#endif
#if defined(M_PURGE)
  if (!ok) {
    ok = mallopt(M_PURGE, 0);
    if (ok) {
      voie = "M_PURGE";
    }
  }
#endif
  fmt::print("A59-PURGE ou={} voie={} ok={}\n", pourquoi, voie, ok);
  rss_census::mark(pourquoi);
#else
  (void)pourquoi;
#endif
}

// autoport 2026-08-26 (Gmemory-ceiling-and-crash) — le niveau COMMUN n'avait AUCUN bilan
// memoire. Mesure sur le Redmi : `Loader::load_common` fait passer le RSS de 327 a 1067 Mo,
// soit 740 Mo pour UN fichier de 25,4 Mo compresse — plus que tous les niveaux de jeu reunis.
// `measure_level_ram` existait deja et n'etait appelee que pour les niveaux NORMAUX.
// Declarees ici parce que leur definition vit dans le namespace anonyme plus bas ; c'est le
// meme namespace, donc la declaration et la definition se lient.
namespace {
void report_level_ram(const std::string& name, const tfrag3::Level& lev, const char* moment);
void report_merc_detail(const std::string& name, const tfrag3::Level& lev, const char* moment);
void release_uploaded_merc_vertices(tfrag3::Level& lev);
void compact_merc_vertex_pool(tfrag3::Level& lev);
void release_uploaded_vertices(tfrag3::Level& lev, int systeme);
}  // namespace

static fs::path hd_fr3_path(const fs::path& base, const std::string& name) {
#ifdef OG_FEAT_HD_MODELS
  if (recharged_gating::on(recharged_gating::kEnhancedModels)) {
    // EXTERNAL asset-pack path ONLY (never the APK custom pack — ND IP must stay external).
    auto enhanced = base / "enhanced" / fmt::format("{}.fr3", name);
    if (file_util::file_exists(enhanced.string())) {
      // lg (not raw stdout): on Android only lg::* routes to logcat.
      lg::info("HD-MODELS fr3-select {}: ENHANCED (external) {}", name, enhanced.string());
      // TEMOIN DE LA COURSE D'AMORCAGE (item `refset-replay-stable`). Ce choix est pris UNE
      // fois par niveau et ne se refait jamais. Mesure du 2026-09-06 : `GAME.fr3` — le niveau
      // commun, jamais evince, dessine dans les 16 etapes des DEUX jeux — etait choisi ENHANCED
      // 3,9 s AVANT que `[recharged-master] override -> 0` ne soit vu, parce que
      // `refset::enabled()` ne pose `OG_RECHARGED=0` qu'a la premiere image GOAL, alors que le
      // fil de chargement, lui, avait deja decide. La course est fermee au POINT DE PRODUCTION
      // (l'environnement est pose par le lanceur, lib/refset.sh et `proof_env`), et ces deux
      // compteurs le disent : sous `OG_REFSET` avec le master eteint, `hd_fr3_enhanced` doit
      // valoir 0. Un compteur qui vaut 0 sans qu'aucun niveau n'ait ete choisi ne prouverait
      // rien : `hd_fr3_stock` publie le denominateur.
      static u64 s_hd_enh = 0;
      autoport_proof::publish("hd_fr3_enhanced", ++s_hd_enh);
      return enhanced;
    }
  }
  lg::info("HD-MODELS fr3-select {}: STOCK (enhanced-toggle={})", name,
           Gfx::settings().recharged_enhanced_models);
  {
    static u64 s_hd_stock = 0;
    autoport_proof::publish("hd_fr3_stock", ++s_hd_stock);
  }
#endif
  // OG_FEAT_HD_MODELS OFF (default): always the stock fr3 path.
  // Round 30 (delivery): the package copy wins for the stock fr3 too, file by file. The .fr3 are
  // DERIVED — our extractor builds them and they carry the weld, the normals, the orientation and the
  // pre-subdivision — so under the owner's structural rule they now ship inside the APK's custom pack
  // (android/build_custom_pack.sh) and the 1.44 GB external base pack keeps only the untouched dump.
  // Device-verified: village1.fr3 resolves to the packaged copy. That is what lets a geometry fix
  // reach a phone by installing an APK, instead of a base-pack re-extraction the owner has no adb for.
  return file_util::resolve_fr3_asset(base, fmt::format("{}.fr3", name)).path;
}

// Ghonor-boot-crash : les DEUX candidats que `hd_fr3_path` peut rendre, testes sans dependre du
// bascule « modeles ameliores ». On ne peut pas simplement appeler `hd_fr3_path` : c'est
// `load_common` qui seme `recharged_enhanced_models` a son PREMIER appel, donc un test pose avant
// lirait un bascule perime et pourrait rater le fichier enhanced. On teste donc les deux.
bool Loader::common_level_exists(const std::string& name) const {
#ifdef OG_FEAT_HD_MODELS
  if (file_util::file_exists((m_base_path / "enhanced" / fmt::format("{}.fr3", name)).string())) {
    return true;
  }
#endif
  return file_util::file_exists(
      file_util::resolve_fr3_asset(m_base_path, fmt::format("{}.fr3", name)).path.string());
}

// Grecharged-hd-models2: objective loaded-model discriminator. The bake-time "Replacing" line
// (extract_merc.cpp) never appears at runtime, so a capture alone can't prove WHICH mesh (stock vs
// HD) was loaded under a merc name. Log per-model triangle/draw counts at fr3 load so every run
// carries the proof (HD meshes are several x the stock tri count under the same name).
static void log_merc_models(const std::string& lev, const tfrag3::Level& data) {
  for (const auto& model : data.merc_data.models) {
    u32 tris = 0, draws = 0;
    for (const auto& e : model.effects) {
      for (const auto& d : e.all_draws) {
        tris += d.num_triangles;
        draws++;
      }
    }
    lg::info("HD-MODELS merc-load lvl={} model={} tris={} draws={} effects={}", lev, model.name,
             tris, draws, model.effects.size());
    // Grecharged-hd-models2 (owner hint: prove the HD mesh binds its OWN texture set, not stock
    // jak1 pages): for the 4 replaced characters, log the texture debug-names their draws bind.
    if (model.name == "eichar-lod0" || model.name == "sidekick-lod0" || model.name == "sage-lod0" ||
        model.name == "assistant-lod0") {
      std::set<std::string> tex_names;
      for (const auto& e : model.effects) {
        for (const auto& d : e.all_draws) {
          if (d.tree_tex_id >= 0 && (size_t)d.tree_tex_id < data.textures.size()) {
            tex_names.insert(data.textures[d.tree_tex_id].debug_name);
          }
        }
      }
      std::string tex_list;
      for (const auto& t : tex_names) {
        if (!tex_list.empty()) {
          tex_list += ",";
        }
        tex_list += t;
      }
      lg::info("HD-MODELS merc-tex lvl={} model={} textures=[{}]", lev, model.name, tex_list);
    }
  }
}

/*!
 * Loader function that runs in a completely separate thread.
 * This is used for file I/O and unpacking.
 */
void Loader::loader_thread() {
  try {
    while (!m_want_shutdown) {
      prof().root_event();
      std::unique_lock<std::mutex> lk(m_loader_mutex);

      // this will keep us asleep until we've got a level to load.
      m_loader_cv.wait(lk, [&] { return !m_level_to_load.empty() || m_want_shutdown; });
      if (m_want_shutdown) {
        return;
      }
      std::string lev = m_level_to_load;
      // don't hold the lock while reading the file.
      lk.unlock();

      // simulate slower hard drive (so that the loader thread can lose to the game loads)
      // std::this_thread::sleep_for(std::chrono::milliseconds(1500));

      // load the fr3 file
      prof().begin_event("read-file");
      Timer disk_timer;
      auto data = file_util::read_binary_file(hd_fr3_path(m_base_path, lev));
      asset_manifest::record("fr3", lev, 0, data.data(), data.size());
      double disk_load_time = disk_timer.getSeconds();
      prof().end_event();

      // the FR3 files are compressed
      prof().begin_event("decompress-file");
      Timer decomp_timer;
      auto decomp_data = compression::decompress_zstd(data.data(), data.size());
      double decomp_time = decomp_timer.getSeconds();
      prof().end_event();
      // autoport 2026-08-26: two 150 MB anonymous blocks dominate the RSS on the
      // Shield; print what this path actually holds so the owner gets a number
      // instead of a hypothesis.
      fmt::print("A51-FR3 lev={} compresse={:.1f}MB decompresse={:.1f}MB disque={:.2f}s zstd={:.2f}s\n",
                 lev, data.size() / 1048576.0, decomp_data.size() / 1048576.0, disk_load_time,
                 decomp_time);
      rss_census::mark("fr3-decomp");

      // Read back into the tfrag3::Level structure
      prof().begin_event("deserialize");
      Timer import_timer;
      auto result = std::make_unique<tfrag3::Level>();
      {
        // EMPRUNT, pas copie : le constructeur historique dupliquait `decomp_data` (35,0 Mo
        // pour village1, 174,5 Mo pour GAME) le temps de la deserialisation. Et les deux
        // tampons vivaient jusqu'a la fin du bloc, donc pendant TOUTE la passe d'unpack
        // (subdivision + tangentes), la plus gourmande : ils partent des que la structure
        // est batie.
        Serializer ser(Serializer::Borrowed{}, decomp_data.data(), decomp_data.size());
        result->serialize(ser);
      }
      rss_census::mark("fr3-serialize");
      compact_merc_vertex_pool(*result);
      {
        std::vector<u8>().swap(data);
        std::vector<u8>().swap(decomp_data);
      }
      heap_purge("fr3-tampons-rendus");
      double import_time = import_timer.getSeconds();
      prof().end_event();
      log_merc_models(lev, *result);

      // and finally "unpack", which creates the vertex data we'll upload to the GPU

      Timer unpack_timer;
      const u64 tan_ns0 = tfrag3::baked_tangent_expand_ns();
      const u64 tan_v0 = tfrag3::baked_tangent_expand_verts();
      {
        auto p = scoped_prof("tie-unpack");
        for (auto& tie_tree : result->tie_trees) {
          for (auto& tree : tie_tree) {
            tree.unpack();
          }
        }
      }

      {
        auto p = scoped_prof("tfrag-unpack");
        for (auto& t_tree : result->tfrag_trees) {
          for (auto& tree : t_tree) {
            tree.unpack();
          }
        }
      }

      {
        auto p = scoped_prof("shrub-unpack");
        for (auto& shrub_tree : result->shrub_trees) {
          shrub_tree.unpack();
        }
      }

      // foliage-wind (essai 11) : le SOL sous chaque buisson (pivot du balancement) et son vent
      // NATIF (sidecar de raideur). Ici et pas plus tard : les sommets sont depaquetes, pas encore
      // soudes ni televerses — LoaderStages lit `unpacked.sway` a l'etape shrub.
#if !AUTOPORT_ORIGIN_ABLATE
      {
        auto p = scoped_prof("foliage-wind-finalize");
        tfrag3::foliage_wind_finalize_level(*result);
        // shrub-trunk-contact : la classe tronc/feuillage se pose ICI, sur le niveau ENTIER et
        // juste apres le sidecar (sans lui aucune instance SHRUB n'a de prototype), donc avant
        // que Shrub.cpp et LoaderStages.cpp ne construisent leurs tables d'ancres de contact.
        foliage_wind::classify_load_bearing(*result);
      }
#endif

      // OWNER REOPEN #13 (2026-07-24) + INSIGHT #2: after every tfrag/tie/shrub tree is unpacked, run
      // the GLOBAL cross-chunk/bucket/system weld — one spatial hash over the WHOLE level stitches
      // coincident positions across bucket AND system boundaries (the per-tree weld only stitched WITHIN
      // each tree => the owner's remaining long seam LINES were chunk boundaries), orients inward normals
      // outward via the walkable collision mesh, then averages across the welded seams with the crease
      // threshold. Only cross-tree seam verts change (single-tree verts keep the accepted per-tree normal).
      // Gated on the PBR / realtime-lighting features that actually consume the reconstructed normal: a
      // STOCK player (recharged master off) pays zero added load cost and stays byte-identical. Runs on
      // this loader thread (not the GL/main thread) behind the load screen, so no ANR.
      if (recharged_gating::on(recharged_gating::kLighting) ||
          recharged_gating::on(recharged_gating::kRtLight)) {
        auto p = scoped_prof("global-weld");
        tfrag3::reconstruct_level_global_weld(*result);
      }

      // Grecharged-mesh-consolidation (owner 2026-07-24): the EXHAUSTIVE pass, run after the weld
      // above. The owner's requirement is "TOUT COUVRIR SANS OUBLIS", so this one both FIXES and
      // MEASURES: an order-independent union-find weld across every tree/bucket/system (tfrag + tie
      // + shrub — shrub was previously skipped entirely for lack of a normal field), a boundary-only
      // wide re-weld that stitches the coincident-but-unshared edges the 3 cm tolerance missed,
      // position snapping so coincident verts are bit-identical, orientation flood-fill with the
      // walkable collision mesh as authority, geometry-derived crease-aware shared normals, baked
      // time-of-day colour blending across welded groups (the seam that survives at relief 0), and
      // per-vertex seam weights that stop the tessellator from tearing at boundaries that cannot
      // displace identically. Its per-level audit numbers are appended to files/mesh_audit.txt so
      // the coverage claim is checkable off-device on a phone whose logcat is obscured.
      if (recharged_gating::on(recharged_gating::kLighting) ||
          recharged_gating::on(recharged_gating::kRtLight)) {
        const auto cfg = tfrag3::mesh_consolidate_config_from_env();
        const bool do_shrub = (cfg.bits & tfrag3::kMeshBitNoShrub) == 0;
        // Le jeu ne lit NI le cadre tangent par sommet NI `seam_w` : mesure, pas suppose — aucun
        // programme lie ne porte d'etage de tessellation et aucun n'a d'attribut actif a la
        // location ou ces VAO branchent `seam_w` (cles `mesh_tess_stage_programs`,
        // `mesh_seam_attrib_readers`). Il demande donc qu'ils ne soient pas produits. Le bit
        // RESTAURE l'ancien comportement pour mesurer, sur ce meme binaire, ce qu'ils coutaient.
        const bool mesh_unconsumed = (cfg.bits & tfrag3::kMeshBitKeepUnconsumed) != 0;
        autoport_proof::note_hit_for("mesh-consolidate-without-consumer");
        // PRECOMPUTE FIRST (the owner's standing preference, and a hard requirement here: measured
        // on the Redmi the live pass costs 45.8 s of village1's load). The sidecar is baked offline
        // by tools/mesh_audit --bake and validated against the fr3's structure, so a rebuilt or
        // modded level falls through to the live pass instead of being corrupted.
        bool from_bake = false;
        std::string bake_route_path;
        if ((cfg.bits & tfrag3::kMeshBitForceLive) == 0) {
          auto p = scoped_prof("mesh-consolidate-sidecar");
          // Round 30 (delivery): ONE resolver, package-copy-wins, and the decision plus the
          // fingerprint of the bytes actually read land in files/asset_route.txt. The corrected
          // sidecars ride to the owner's phone inside the APK's custom pack — the 1.44 GB base pack
          // cannot — so this precedence IS the delivery route for every geometry fix.
          const auto name = tfrag3::mesh_consolidate_bake_name(result->level_name);
          const auto route = file_util::resolve_fr3_asset(g_game_version, name);
          bake_route_path = route.path.string();
          from_bake = tfrag3::mesh_consolidate_apply_bake(*result, bake_route_path, do_shrub,
                                                       mesh_unconsumed);
        }
        if (!from_bake) {
          auto p = scoped_prof("mesh-consolidate");
          tfrag3::MeshAuditReport audit;
          tfrag3::mesh_consolidate(*result, cfg, &audit, nullptr, mesh_unconsumed);
          audit.game_name = version_to_game_name(g_game_version);
          const std::string text = tfrag3::format_mesh_audit(audit, cfg);
          lg::info("[mesh-consolidate] {}", text);
          tfrag3::mesh_audit_append_file(text);
        }
      }

      // lighting-bake : la verification du compagnon juge la palette que le rendu lit, donc APRES la
      // soudure et le .meshweld qui la retouchent. Refonte lumiere OFF : rien n'est lu.
      if (recharged_gating::on(recharged_gating::kLighting) &&
          autoport_proof::armed_for(kLightBakeItem)) {
        auto p = scoped_prof("lighting-bake-verify");
        lighting_bake_verify_level(*result);
      }

      // lighting-local-lights (SPEC §4.9) : relit la section kSecLights du meme compagnon,
      // INDEPENDAMMENT de la porte lighting-bake — la grille de clusters a besoin des lumieres
      // meme quand la verification de palette n'est pas armee.
      std::vector<local_lights::Light> ll_loaded_lights;
      {
        auto p = scoped_prof("local-lights-load");
        ll_loaded_lights = lighting_local_lights_load(*result);
        lighting_local_lights_census(*result);
      }

#if !AUTOPORT_ORIGIN_ABLATE
      {
        auto p = scoped_prof("foliage-contact-final-geometry");
        foliage_wind::finalize_contact_geometry(*result);
      }
#endif

      // lighting-legacy-purge (2026-09-11) : la PRE-SUBDIVISION de maillage est SUPPRIMEE. Elle
      // n'etait atteignable que sous DISPLACEMENT = 2 (TESSELLATION) — `want` exigeait ce mode — et
      // ce mode n'a jamais ete livre : il disparait avec cet item, comme les shaders du programme tesselle.
      // Le nombre de tours (`mesh-subdiv`) ne pouvait donc rien changer a l'image livree.

      fmt::print(
          "------------> Load from file: {:.3f}s, import {:.3f}s, decomp {:.3f}s unpack {:.3f}s\n",
          disk_load_time, import_time, decomp_time, unpack_timer.getSeconds());
      // Gprecompute-deterministic-bake — what the per-vertex tangents still cost on THIS machine now
      // that the fr3 carries them. Compare against the [tangent-bake] line the fr3 extractor printed
      // for the SAME level: that is the derivation this replaces, and it used to sit inside the
      // `unpack` figure above, on every load, on every target.
      fmt::print("A55-TANGENT lev={} expand={:.1f}ms verts={}\n", lev,
                 (tfrag3::baked_tangent_expand_ns() - tan_ns0) / 1e6,
                 tfrag3::baked_tangent_expand_verts() - tan_v0);
      rss_census::mark("fr3-unpack");

      // grab the lock again
      lk.lock();
      // move this level to "initializing" state.
      m_initializing_tfrag3_levels[lev] = std::make_unique<LevelData>();  // reset load state
      m_initializing_tfrag3_levels[lev]->level = std::move(result);
      m_initializing_tfrag3_levels[lev]->local_lights = std::move(ll_loaded_lights);
      m_level_to_load = "";
      m_file_load_done_cv.notify_all();
    }
  } catch (std::exception& e) {
    ASSERT_MSG(false, fmt::format("Exception {} encountered in loader_thread", e.what()));
  }
}

/*!
 * Load a "common" FR3 file that has non-level textures.
 * This should be called during initialization, before any threaded loading goes on.
 */
const tfrag3::Level& Loader::load_common(TexturePool& tex_pool, const std::string& name) {
  rss_census::mark("common-debut");
  // Grecharged-master-toggle: seed the GLOBAL master before the first fr3-path resolution.
  // recharged-gating-real : l'amorcage passe par le module de portes comme tout le reste. Ecrire
  // le champ a la main ici ferait exactement ce que `gating_ungated_sites` compte — un ecrivain
  // qui court-circuite la porte — et le module le SIGNALERAIT a la premiere image. C'est voulu :
  // la seule facon de ne pas etre compte est d'entrer par la porte.
  recharged_gating::set(recharged_gating::kMaster, read_persisted_recharged_master() ? 1 : 0);
  // Grecharged-bundled-textures: seed the base-swap toggle before the first add_texture.
  recharged_gating::set(recharged_gating::kTextures, read_persisted_recharged_textures() ? 1 : 0);
#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-models: seed the enhanced-models flag before the common FR3 (HD Jak+Daxter) is read,
  // since this runs in the renderer ctor before GOAL's per-frame push. Shared by desktop + Android.
  recharged_gating::set(recharged_gating::kEnhancedModels, read_persisted_enhanced_models() ? 1 : 0);
  // Grecharged-hd-models3/4: the anim-retarget HD art-groups (<char>-ag.go) are ND-derived — they
  // ship ONLY in the EXTERNAL asset pack (assets/hd/), never the APK/binary. loado resolves loose
  // .go from <jak_project_dir>/out/<game>/obj/, so stage them there from the external game root at
  // boot. Local copy only; the origin stays external and dumps-gated, so no ND IP is ever
  // bundled/distributed. M4: fixed name list (never glob — a stale >=16-char name would trip the
  // fake-iso assert) and REFRESH on content mismatch (the M1 skip-if-exists left owner devices on
  // stale art-groups forever).
  {
    auto ext = file_util::get_external_game_root();
    if (ext) {
      for (const char* ag : {"jak-hd-ag.go", "dax-hd-ag.go", "keira-hd-ag.go", "samos-hd-ag.go",
                             "jak2-hd-ag.go", "jak3-hd-ag.go", "daxp-hd-ag.go", "keira3-hd-ag.go",
                             "ysamos-hd-ag.go", "jakm-hd-ag.go", "jakp-hd-ag.go"}) {
        auto src = *ext / "assets" / "hd" / ag;
        auto dst = file_util::get_jak_project_dir() / "out" / "jak1" / "obj" / ag;
        if (!file_util::file_exists(src.string())) {
          continue;
        }
        auto bytes = file_util::read_binary_file(src);
        if (file_util::file_exists(dst.string())) {
          auto have = file_util::read_binary_file(dst.string());
          if (have == bytes) {
            continue;
          }
        }
        file_util::create_dir_if_needed_for_file(dst);
        file_util::write_binary_file(dst, bytes.data(), bytes.size());
        lg::info("[hd-models] staged external HD art-group -> {} ({} bytes)", dst.string(),
                 bytes.size());
      }
    }
  }
#endif
  auto data = file_util::read_binary_file(hd_fr3_path(m_base_path, name));
  asset_manifest::record("fr3", name, 0, data.data(), data.size());
  rss_census::mark("common-lu");

  auto decomp_data = compression::decompress_zstd(data.data(), data.size());
  rss_census::mark("common-decomp");
  m_common_level.level = std::make_unique<tfrag3::Level>();
  {
    // EMPRUNT, pas copie (cf. Serializer::Borrowed). Ici le poste est le plus gros du jeu :
    // GAME.fr3 des modeles HD decompresse a 174,5 Mo, donc l'ancien constructeur tenait
    // 174,5 Mo de tampon + 174,5 Mo de copie interne PENDANT la construction du niveau, et
    // la copie interne survivait ensuite jusqu'a la fin de la fonction — donc pendant tout
    // le televersement des textures et des personnages.
    Serializer ser(Serializer::Borrowed{}, decomp_data.data(), decomp_data.size());
    m_common_level.level->serialize(ser);
  }
  rss_census::mark("common-serialize");
  compact_merc_vertex_pool(*m_common_level.level);
  {
    // Les deux tampons sont morts des que la structure est batie : les rendre AVANT le
    // televersement, pas a la sortie de la fonction.
    std::vector<u8>().swap(data);
    std::vector<u8>().swap(decomp_data);
  }
  heap_purge("common-tampons-rendus");
  log_merc_models(name, *m_common_level.level);
  // Grecharged-texture-hotreload : estampiller le regime AVANT la boucle. GAME.fr3 n'est jamais
  // evince : sans cette estampille et la passe qu'elle autorise, ses textures restaient celles du
  // reglage lu dans settings.ini au boot jusqu'a la fin de la partie, quoi que fasse le menu.
  m_common_level.tex_regime = custom_tex::hotreload_regime();
  for (auto& tex : m_common_level.level->textures) {
    m_common_level.textures.push_back(add_texture(tex_pool, tex, true));
    m_common_level.tex_upload_fp.push_back(g_last_add_texture_fp);
  }
  rss_census::mark("common-textures");

  Timer tim;
  MercLoaderStage mls;
  LoaderInput input;
  input.tex_pool = &tex_pool;
  input.mercs = &m_all_merc_models;
  input.lev_data = &m_common_level;
  bool done = false;
  while (!done) {
    done = mls.run(tim, input);
  }
  rss_census::mark("common-fin");
  report_level_ram(name, *m_common_level.level, "charge");
  report_merc_detail(name, *m_common_level.level, "charge");
  release_uploaded_merc_vertices(*m_common_level.level);
  report_level_ram(name, *m_common_level.level, "apres-liberations");
  heap_purge("common-fin-purge");
  return *m_common_level.level;
}

bool Loader::upload_textures(Timer& timer, LevelData& data, TexturePool& texture_pool) {
  // try to move level from initializing to initialized:

  auto evt = scoped_prof("upload-textures");
  constexpr int MAX_TEX_BYTES_PER_FRAME = 1024 * 128;

  int bytes_this_run = 0;
  int tex_this_run = 0;
  if (data.textures.size() < data.level->textures.size()) {
    std::unique_lock<std::mutex> tpool_lock(texture_pool.mutex());
    while (data.textures.size() < data.level->textures.size()) {
      auto& tex = data.level->textures[data.textures.size()];
      if (data.textures.empty()) {
        data.tex_regime = custom_tex::hotreload_regime();
      }
      data.textures.push_back(add_texture(texture_pool, tex, false));
      data.tex_upload_fp.push_back(g_last_add_texture_fp);
      // real uploaded bytes (see LoaderStages.h g_last_add_texture_bytes)
      bytes_this_run += (int)g_last_add_texture_bytes;
      tex_this_run++;
      if (tex_this_run > 20) {
        break;
      }
      if (bytes_this_run > MAX_TEX_BYTES_PER_FRAME || timer.getMs() > SHARED_TEXTURE_LOAD_BUDGET) {
        break;
      }
    }
  }
  return data.textures.size() == data.level->textures.size();
}

// autoport 2026-08-26 — WHERE THE RAM ACTUALLY GOES.
// The PS2 ran this game in 32 MB; we measured ~1 GB RSS on a 3 GB device. The
// existing MemoryUsageTracker only sizes the *packed* fr3 payload — it never
// counts `unpacked` (rebuilt at load) or the decoded RGBA texture bytes, so the
// biggest resident buffers were invisible. Report them, per level, once.
namespace {
struct LevelRamReport {
  size_t verts = 0, indices = 0, tangents = 0, textures = 0, merc = 0, collision = 0;
  size_t packed = 0, bvh = 0, tod = 0, draws = 0, hfrag = 0;
  size_t total() const {
    return verts + indices + tangents + textures + merc + collision + packed + bvh + tod + draws +
           hfrag;
  }
};

// autoport 2026-08-26 — the tangent array is uploaded to GL as vertex attribute 5
// and then never read again on the CPU: the only other users are MeshSubdivide,
// which WRITES it, and `redo()`, which recomputes it from positions+indices when a
// setting changes. Measured on village1: 26.3 MB per level, times the three cached
// levels. Hand it back once every loader stage has finished uploading.
void release_uploaded_tangents(tfrag3::Level& lev, int systeme) {
  auto drop = [](std::vector<math::Vector4f>& v) {
    std::vector<math::Vector4f>().swap(v);  // free the storage, not just the size
  };
  if (systeme == 0) {
    for (auto& geo : lev.tfrag_trees) {
      for (auto& t : geo) {
        drop(t.unpacked.tangents);
      }
    }
  } else {
    for (auto& geo : lev.tie_trees) {
      for (auto& t : geo) {
        drop(t.unpacked.tangents);
      }
    }
  }
}

// LIBERATION, PAR SYSTEME ET DES QUE SON ETAPE A TELEVERSE. systeme : 0 = tfrag, 1 = tie.
// Pourquoi par systeme : l'ordre des etapes est tie(0), texture(1), tfrag(2), ... Liberer en
// FIN DE LOT faisait coexister TOUTE la geometrie CPU du niveau (village1 : 57,0 Mo de sommets
// + 26,3 Mo de tangentes) avec les textures GPU qui venaient d'etre televersees — et c'est ce
// recouvrement qui fait le maximum de la course. La geometrie de TIE part donc AVANT meme que
// l'etape de texture commence.
// SHRUB EST EPARGNE : `Shrub::update_load` lit ses sommets DIRECTEMENT (compte, LUT de vent,
// index d'ombre) et le RENDU l'appelle apres le chargement. Les INDEX de tous les systemes
// restent : le rendu les relit chaque frame.
void release_uploaded_vertices(tfrag3::Level& lev, int systeme) {
  // `grass_bake::scan_level` (GrassBakeCore.cpp:506,512) relit tfrag/tie a la DEMANDE DU MENU,
  // des minutes apres le chargement, sur ces deux niveaux uniquement. Liberer y donnerait un
  // champ vide au premier mouvement du curseur de densite.
  if (grass_level_enabled(lev.level_name)) {
    fmt::print("A54-VERTFREE lev={} sys={} SAUTE (niveau a herbe vive)\n", lev.level_name,
               systeme);
    return;
  }
  size_t freed = 0;
  auto drop_pv = [&freed](std::vector<tfrag3::PreloadedVertex>& v) {
    freed += v.size() * sizeof(tfrag3::PreloadedVertex);
    std::vector<tfrag3::PreloadedVertex>().swap(v);
  };
  if (systeme == 0) {
    for (auto& geo : lev.tfrag_trees) {
      for (auto& t : geo) {
        drop_pv(t.unpacked.vertices);
      }
    }
  } else {
    for (auto& geo : lev.tie_trees) {
      for (auto& t : geo) {
        drop_pv(t.unpacked.vertices);
        // Grecharged-foliage-wind3 : le poids de balancement est deja dans le GPU (etape `tie`,
        // qui precede `texture`). Personne ne le relit cote CPU — Tie3 ne lit que le
        // RECENSEMENT (`sway_census`), qui n'est que des compteurs et survit.
        freed += t.unpacked.sway.size();
        std::vector<u8>().swap(t.unpacked.sway);
      }
    }
  }
  release_uploaded_tangents(lev, systeme);
  fmt::print("A54-VERTFREE lev={} sys={} libere={:.1f}MB (sommets ; tangentes rendues aussi)\n",
             lev.level_name, systeme == 0 ? "tfrag" : "tie", freed / 1048576.0);
}

// Gmemory-ceiling-and-crash (2026-08-26) — COMPACTER LE POOL DE SOMMETS MERC.
//
// FAIT MESURE, sur l'appareil : `A57-MERC lev=GAME sommets=150.3MB(n=2462895)`, et le
// recensement montre le MEME nombre d'octets une deuxieme fois cote GPU
// (`A55-RSS merc-bufdata gpu=86Mo` -> `merc-uploade gpu=238Mo`, +152 Mo). Or le GAME.fr3
// STOCK n'a que 9 942 sommets merc : c'est la CUISSON HD qui empile les pools de sommets de
// chaque modele sans jamais les compacter. Balayage de `merc_data.indices` : une petite part
// seulement des sommets alloues est atteignable par un `glDrawElements` — merc ne dessine
// QUE par index (aucun `glDrawArrays` dans Merc2.cpp), donc la borne est DURE.
//
// CE QUI REND LA REECRITURE DELICATE, et pourquoi il y a des gardes : une meme case de
// `merc_data.indices` n'adresse pas toujours le meme tableau. `Merc2::do_draws` lie le MEME
// tampon d'index pour tous les draws, mais bascule le VAO : un draw `MOD_VTX` lit ses sommets
// dans le pool MODIFIABLE DE L'EFFET (`effect.mod.vertices`, quelques milliers de sommets),
// pas dans `merc_data.vertices` (Merc2.cpp:2874-2879). Renumeroter ces cases-la casserait les
// personnages a blend shapes EN SILENCE.
//
// Donc on CLASSE les cases avant de toucher a quoi que ce soit :
//   1 = case lue par un draw du pool PRINCIPAL (`all_draws`, `mod.fix_draw`),
//   2 = case lue par un draw du pool MODIFIABLE (`mod.mod_draw`),
//   3 = case reclamee par les DEUX (contradiction),
//   0 = case qu'aucun draw ne lit.
// et la compaction n'a lieu QUE si : aucune plage de draw ne deborde du tableau d'index,
// aucune case en conflit, tout index principal est < nombre de sommets, et tout index
// modifiable est < taille du pool de SON effet. La derniere condition est le test direct de
// l'hypothese ci-dessus : si elle tombe, on ne compacte pas et on le DIT.
// Les cases 0 et 2 ne sont jamais reecrites.
void compact_merc_vertex_pool(tfrag3::Level& lev) {
  auto& verts = lev.merc_data.vertices;
  auto& idx = lev.merc_data.indices;
  const size_t nv = verts.size();
  const size_t ni = idx.size();
  if (nv == 0 || ni == 0) {
    return;
  }
  constexpr u32 kRestart = UINT32_MAX;

  std::vector<u8> cls(ni, 0);
  bool plage_hors_bornes = false;
  auto claim = [&](const tfrag3::MercDraw& d, u8 quoi) {
    if ((u64)d.first_index + (u64)d.index_count > (u64)ni) {
      plage_hors_bornes = true;
      return;
    }
    for (u32 k = 0; k < d.index_count; k++) {
      u8& c = cls[(size_t)d.first_index + k];
      if (c == 0) {
        c = quoi;
      } else if (c != quoi) {
        c = 3;
      }
    }
  };
  for (const auto& m : lev.merc_data.models) {
    for (const auto& e : m.effects) {
      for (const auto& d : e.all_draws) {
        claim(d, 1);
      }
      for (const auto& d : e.mod.fix_draw) {
        claim(d, 1);
      }
      for (const auto& d : e.mod.mod_draw) {
        claim(d, 2);
      }
    }
  }

  // Le test direct de l'hypothese « un index MOD_VTX adresse le pool de son effet ».
  bool mod_local = true;
  if (!plage_hors_bornes) {
    for (const auto& m : lev.merc_data.models) {
      for (const auto& e : m.effects) {
        const u32 pool = (u32)e.mod.vertices.size();
        for (const auto& d : e.mod.mod_draw) {
          for (u32 k = 0; k < d.index_count && mod_local; k++) {
            const u32 v = idx[(size_t)d.first_index + k];
            if (v != kRestart && v >= pool) {
              mod_local = false;
            }
          }
        }
      }
    }
  }

  size_t n_main = 0, n_mod = 0, n_conflit = 0, n_libre = 0;
  bool index_hors_bornes = false;
  std::vector<u8> utilise(nv, 0);
  size_t n_utilises = 0;
  for (size_t i = 0; i < ni; i++) {
    const u32 v = idx[i];
    switch (cls[i]) {
      case 1:
        n_main++;
        if (v != kRestart) {
          if (v >= nv) {
            index_hors_bornes = true;
          } else if (!utilise[v]) {
            utilise[v] = 1;
            n_utilises++;
          }
        }
        break;
      case 2:
        n_mod++;
        break;
      case 3:
        n_conflit++;
        break;
      default:
        n_libre++;
        break;
    }
  }

  const bool sur = !plage_hors_bornes && !index_hors_bornes && n_conflit == 0 && mod_local;
  const bool utile = n_utilises < nv;
  if (!sur || !utile) {
    fmt::print(
        "A60-MERCPACK lev={} NON COMPACTE sommets={} utilises={} cases(main={} mod={} "
        "conflit={} libre={}) plage_hs={} index_hs={} mod_local={} raison={}\n",
        lev.level_name, nv, n_utilises, n_main, n_mod, n_conflit, n_libre,
        plage_hors_bornes ? 1 : 0, index_hors_bornes ? 1 : 0, mod_local ? 1 : 0,
        !sur ? "garde" : "rien-a-gagner");
    return;
  }

  std::vector<u32> remap(nv, kRestart);
  u32 suivant = 0;
  for (size_t v = 0; v < nv; v++) {
    if (utilise[v]) {
      remap[v] = suivant++;
    }
  }
  std::vector<tfrag3::MercVertex> compacte;
  compacte.reserve(suivant);
  for (size_t v = 0; v < nv; v++) {
    if (utilise[v]) {
      compacte.push_back(verts[v]);
    }
  }
  for (size_t i = 0; i < ni; i++) {
    if (cls[i] == 1) {
      const u32 v = idx[i];
      if (v != kRestart) {
        idx[i] = remap[v];
      }
    }
  }
  verts.swap(compacte);
  std::vector<tfrag3::MercVertex>().swap(compacte);
  const size_t avant = nv * sizeof(tfrag3::MercVertex);
  const size_t apres = verts.size() * sizeof(tfrag3::MercVertex);
  fmt::print(
      "A60-MERCPACK lev={} COMPACTE sommets {} -> {} ({:.1f}MB -> {:.1f}MB, gagne {:.1f}MB "
      "en RAM ET AUTANT dans le tampon GPU) cases(main={} mod={} libre={})\n",
      lev.level_name, nv, verts.size(), avant / 1048576.0, apres / 1048576.0,
      (avant - apres) / 1048576.0, n_main, n_mod, n_libre);
}

// Gmemory-ceiling-and-crash (2026-08-26) — RENDRE LES SOMMETS MERC CPU APRES TELEVERSEMENT.
// `MercLoaderStage` copie `merc_data.vertices` dans un tampon GL (`glBufferData` +
// `glBufferSubData` par tranches), et a partir de la le rendu ne lit plus QUE le tampon GL.
// Recensement des lecteurs de `merc_data.vertices` dans tout le depot, apres chargement :
//   - `Merc2.cpp:3097` (F1A-MERC-VERIFY) : lisait `.size()`, PAS les donnees ; la valeur est
//     desormais conservee dans `LevelData::merc_vertex_count`, donc le diagnostic ne ment pas ;
//   - `tools/hd_merc_swap/main.cpp` : outil HORS LIGNE, pas le jeu.
// Aucun autre. En particulier les BLEND SHAPES ne passent pas par la : `Blerc` travaille sur
// `effect.mod.vertices`, une copie PROPRE A CHAQUE EFFET, qui n'est pas touchee ici.
// LES INDEX RESTENT : `Merc2.cpp:826` (eye_blerc) et la garde F1A-MERC-OOB (`Merc2.cpp:3048`,
// evaluee a CHAQUE draw sur Android) lisent `merc_data.indices` en pleine partie.
// Ghd-skin-origin-stretch (cycle 4) — LES SLOTS D'OS QUE CHAQUE MODELE LIT VRAIMENT, calcules ICI
// parce que c'est le dernier instant ou les sommets CPU existent. La chaine de slots d'un paquet
// merc liste TOUS les os du modele, `align` compris (slot 0, matrice model-space dans un
// emplacement world-space, en-tete de jak-hd.gc l.49-50) ; sans ce masque la sonde HDSKIN prenait
// `align` pour un os en fuite a 2 097 152 m sur chaque image. Meme regle que le shader merc2.vert :
// mats[0] toujours, mats[1]/mats[2] seulement si leur poids est > 0.
static void compute_merc_used_bone_masks(tfrag3::Level& lev) {
  const auto& verts = lev.merc_data.vertices;
  const auto& inds = lev.merc_data.indices;
  for (auto& model : lev.merc_data.models) {
    std::vector<u8> mask(128, 0);
    auto scan = [&](const std::vector<tfrag3::MercDraw>& draws,
                    const std::vector<tfrag3::MercVertex>& vs) {
      for (const auto& d : draws) {
        for (u32 q = d.first_index; q < d.first_index + d.index_count && q < inds.size(); q++) {
          u32 vi = inds[q];
          if (vi >= vs.size()) {
            continue;  // index de redemarrage de bande, ou hors de ce tableau
          }
          const auto& v = vs[vi];
          mask[v.mats[0] & 127] = 1;
          if (v.weights[1] > 0.f) {
            mask[v.mats[1] & 127] = 1;
          }
          if (v.weights[2] > 0.f) {
            mask[v.mats[2] & 127] = 1;
          }
        }
      }
    };
    for (const auto& eff : model.effects) {
      scan(eff.all_draws, verts);
      scan(eff.mod.fix_draw, verts);
      scan(eff.mod.mod_draw, eff.mod.vertices);
    }
    model.used_bone_mask_rt = std::move(mask);
  }
}

void release_uploaded_merc_vertices(tfrag3::Level& lev) {
  compute_merc_used_bone_masks(lev);
  const size_t freed = lev.merc_data.vertices.size() * sizeof(tfrag3::MercVertex);
  std::vector<tfrag3::MercVertex>().swap(lev.merc_data.vertices);
  fmt::print("A58-MERCFREE lev={} libere={:.1f}MB (sommets CPU ; index gardes)\n", lev.level_name,
             freed / 1048576.0);
}

LevelRamReport measure_level_ram(const tfrag3::Level& lev) {
  LevelRamReport r;
  for (const auto& geo : lev.tfrag_trees) {
    for (const auto& t : geo) {
      r.verts += t.unpacked.vertices.size() * sizeof(tfrag3::PreloadedVertex);
      r.indices += t.unpacked.indices.size() * sizeof(u32);
      r.tangents += t.unpacked.tangents.size() * sizeof(math::Vector4f);
    }
  }
  for (const auto& geo : lev.tie_trees) {
    for (const auto& t : geo) {
      r.verts += t.unpacked.vertices.size() * sizeof(tfrag3::PreloadedVertex);
      r.indices += t.unpacked.indices.size() * sizeof(u32);
      r.tangents += t.unpacked.tangents.size() * sizeof(math::Vector4f);
    }
  }
  for (const auto& t : lev.shrub_trees) {
    r.verts += t.unpacked.vertices.size() * sizeof(tfrag3::ShrubGpuVertex);
    r.indices += t.indices.size() * sizeof(u32);  // shrub keeps its indices outside `unpacked`
  }
  for (const auto& t : lev.textures) {
    r.textures += t.data.size() * sizeof(u32);
  }
  // The character (merc) data is ONE contiguous vector per level — the shape that
  // shows up in smaps as a single huge mapping. The HD character models this port
  // ships are far heavier than the PS2 originals, so measure it explicitly.
  r.merc += lev.merc_data.vertices.size() * sizeof(tfrag3::MercVertex);
  r.merc += lev.merc_data.indices.size() * sizeof(u32);
  r.collision += lev.collision.vertices.size() * sizeof(tfrag3::CollisionMesh::Vertex);
  // Reste du compte : sans ces postes, l'accounting manquait ~40 Mo par niveau et les
  // deux blocs residents de 150 Mo (un PAR NIVEAU, apparus a t+18 s quand deux niveaux
  // se chargent) restaient inexpliques.
  for (const auto& geo : lev.tfrag_trees) {
    for (const auto& t : geo) {
      r.packed += t.packed_vertices.vertices.size() * sizeof(tfrag3::PackedTfragVertices::Vertex);
      r.packed += t.packed_vertices.cluster_origins.size() * sizeof(math::Vector<u16, 3>);
      r.tod += t.colors.data.size();
      r.bvh += t.bvh.vis_nodes.size() * sizeof(tfrag3::VisNode);
      for (const auto& d : t.draws) {
        r.draws += d.runs.size() * sizeof(tfrag3::StripDraw::VertexRun);
        r.draws += d.plain_indices.size() * sizeof(u32);
        r.draws += d.vis_groups.size() * sizeof(tfrag3::StripDraw::VisGroup);
      }
    }
  }
  for (const auto& geo : lev.tie_trees) {
    for (const auto& t : geo) {
      r.packed += t.packed_vertices.vertices.size() * sizeof(tfrag3::PackedTieVertices::Vertex);
      r.packed += t.packed_vertices.color_indices.size() * sizeof(u16);
      r.packed += t.packed_vertices.matrices.size() * sizeof(std::array<math::Vector4f, 4>);
      r.tod += t.colors.data.size();
      r.bvh += t.bvh.vis_nodes.size() * sizeof(tfrag3::VisNode);
    }
  }
  r.hfrag += lev.hfrag.vertices.size() * sizeof(tfrag3::HfragmentVertex);
  r.hfrag += lev.hfrag.indices.size() * sizeof(u32);
  r.hfrag += lev.hfrag.corners.size() * sizeof(tfrag3::HfragmentCorner);
  r.hfrag += lev.hfrag.buckets.size() * sizeof(tfrag3::HfragmentBucket);
  r.hfrag += lev.hfrag.time_of_day_colors.data.size();
  return r;
}

// A50-LEVRAM, un seul point d'impression pour TOUS les niveaux (le commun compris).
// NATURE : octets de TAS C++ tenus par la structure `tfrag3::Level` de ce niveau.
// REPERE : la structure du niveau, pas le processus — la memoire GPU n'y est pas.
// LIGNE DE BASE : le meme niveau au moment `charge`, avant les liberations.
void report_level_ram(const std::string& name, const tfrag3::Level& lev, const char* moment) {
  const auto ram = measure_level_ram(lev);
  fmt::print(
      "A50-LEVRAM lev={} moment={} verts={:.1f}MB idx={:.1f}MB tan={:.1f}MB tex={:.1f}MB "
      "merc={:.1f}MB coll={:.1f}MB packed={:.1f}MB bvh={:.1f}MB tod={:.1f}MB "
      "draws={:.1f}MB hfrag={:.1f}MB total={:.1f}MB\n",
      name, moment, ram.verts / 1048576.0, ram.indices / 1048576.0, ram.tangents / 1048576.0,
      ram.textures / 1048576.0, ram.merc / 1048576.0, ram.collision / 1048576.0,
      ram.packed / 1048576.0, ram.bvh / 1048576.0, ram.tod / 1048576.0, ram.draws / 1048576.0,
      ram.hfrag / 1048576.0, ram.total() / 1048576.0);
}

// A57-MERC — le detail du poste `merc`, parce que `measure_level_ram` n'en compte que DEUX
// champs (`merc_data.vertices` et `merc_data.indices`) et que les modeles HD en portent
// quatre autres qui ne sont comptes NULLE PART : la copie de sommets modifiables de chaque
// effet, ses adresses lump4, son masque de fragments, et les deux tableaux de BLEND SHAPE.
// NATURE : octets de tas. REPERE : la structure du niveau.
// sizeof(MercVertex) = 64 (Tfrag3Data.h:565), donc `sommets` en octets / 64 = le nombre exact
// de sommets — c'est ce nombre qu'on compare a la taille du tampon GPU.
void report_merc_detail(const std::string& name, const tfrag3::Level& lev, const char* moment) {
  size_t vtx = lev.merc_data.vertices.size() * sizeof(tfrag3::MercVertex);
  size_t idx = lev.merc_data.indices.size() * sizeof(u32);
  size_t mod_vtx = 0, blerc_f = 0, blerc_i = 0, lump = 0, fragmask = 0, draws = 0;
  size_t n_eff = 0, n_mod = 0;
  for (const auto& m : lev.merc_data.models) {
    for (const auto& e : m.effects) {
      n_eff++;
      draws += e.all_draws.size() * sizeof(tfrag3::MercDraw);
      draws += (e.mod.fix_draw.size() + e.mod.mod_draw.size()) * sizeof(tfrag3::MercDraw);
      if (!e.mod.vertices.empty() || !e.mod.blerc.float_data.empty()) {
        n_mod++;
      }
      mod_vtx += e.mod.vertices.size() * sizeof(tfrag3::MercVertex);
      lump += e.mod.vertex_lump4_addr.size() * sizeof(u16);
      fragmask += e.mod.fragment_mask.size();
      blerc_f += e.mod.blerc.float_data.size() * sizeof(tfrag3::BlercFloatData);
      blerc_i += e.mod.blerc.int_data.size() * sizeof(u32);
    }
  }
  const size_t tot = vtx + idx + mod_vtx + lump + fragmask + blerc_f + blerc_i + draws;
  fmt::print(
      "A57-MERC lev={} moment={} modeles={} effets={} effets_mod={} sommets={:.1f}MB(n={}) "
      "index={:.1f}MB modsommets={:.1f}MB blercf={:.1f}MB blerci={:.1f}MB lump={:.1f}MB "
      "fragmask={:.1f}MB draws={:.1f}MB total={:.1f}MB\n",
      name, moment, lev.merc_data.models.size(), n_eff, n_mod, vtx / 1048576.0,
      lev.merc_data.vertices.size(), idx / 1048576.0, mod_vtx / 1048576.0, blerc_f / 1048576.0,
      blerc_i / 1048576.0, lump / 1048576.0, fragmask / 1048576.0, draws / 1048576.0,
      tot / 1048576.0);
}
}  // namespace

// Gloading-screen (owner 2026-08-29, retour n.4) — POURQUOI CETTE FONCTION REND LA MAIN.
//
// « la silhouette animee ... freeze par moment (quand ca charge des gros trucs je suppose) ca
// devrait etre fluide ! »
//
// LA BARRIERE QUI AFFICHE L'ECRAN DE CHARGEMENT EST CELLE QUI EMPECHE DE LE REDESSINER. Chaine
// complete, verifiee ligne a ligne :
//   1. une barriere armee rend `load_gate::wants_blocking_loads()` vrai (load_gate.cpp:77-94) ;
//   2. le renderer bascule alors sur CE chemin (OpenGLRenderer.cpp:1085-1088 sur bureau,
//      android/android_opengl_renderer.cpp:940-942 sur l'appareil) ;
//   3. la version d'avant attendait le fr3 sur une condition_variable PUIS rejouait `update()`
//      en boucle SANS AUCUN BUDGET, jusqu'a ce que le niveau entier soit televerse ;
//   4. pendant tout ce temps le thread GOAL est PARQUE (android_gfx.cpp:1145-1147 /
//      opengl.cpp:848-858), donc `display-frame-start` n'est pas appele, l'horloge n'avance pas,
//      `loading-screen-draw` n'est pas appele : LA DERNIERE IMAGE RESTE A L'ECRAN.
// Cout d'un seul appel, mesure dans .autoport/reports/Gloading-screen/boot-apres2.log :
// « stage texture took 853.71 ms », contre un budget nominal de 4,5 ms (LoaderStages.cpp:22).
// C'est ca, le gel : ce n'est ni un choix d'horloge ni un defaut de la planche d'images.
//
// CE CHEMIN N'ETAIT PAS UN DEFAUT QUAND IL A ETE ECRIT — c'est le correctif d'hote devenu le
// defaut suivant. Son commentaire d'origine le dit : « a closed scene barrier is the same
// situation as a blackout — the picture is being held back on purpose », mesure a l'appui
// (village1 : 13,4 s budgete contre 4,6 s bloquant). La premisse « l'image est retenue expres »
// etait vraie tant que l'ecran etait NOIR. Elle est fausse depuis qu'il porte une animation.
//
// CE QU'ON GARDE ET CE QU'ON PAIE. Le travail total est INCHANGE : la barriere rappelle cette
// fonction a chaque frame, on decoupe simplement en tranches de `budget_ms`. On paie le rendu
// d'une frame par tranche — un fond noir et quelques quads. `budget_ms = 0` conserve exactement
// le comportement d'avant, et c'est ce que recoit la transition de blackout (`announce`), ou
// aucune animation n'est visible et ou rien ne doit changer.
//
// POURQUOI LE BUDGET N'EST PAS UN GOUT. Sur l'appareil, `__read-ee-timer` est une horloge
// VIRTUELLE dont l'increment est plafonne a k=4 frames par frame rendue et dont le retard est
// JETE (android/gk_android_main.cpp:787-789, :793-799, :833-835). Au-dela de 4 x 16,67 = 66,7 ms
// de frame, le temps ecoule cesse d'etre compte et TOUTE animation pilotee par une horloge de
// jeu passe au ralenti. Le budget doit donc laisser la frame ENTIERE sous ce plafond, rendu
// compris. C'est la valeur choisie dans OpenGLRenderer.cpp / android_opengl_renderer.cpp.
float loading_screen_slice_ms() {
  static float v = []() {
    const char* e = getenv("OG_LOADSCREEN_SLICE_MS");
    return e ? (float)atof(e) : kLoadingScreenSliceMs;
  }();
  return v;
}

// Gloading-screen (owner 2026-08-30) — LA TRANCHE EST CE QUI RESTE DE LA FRAME, PAS UN NOMBRE.
//
// « faut que tu te démerdes pour que ça capture 60 FPS réel que ce soit silky smooth »
//
// La tranche fixe de 40 ms tenait sa promesse (plus de gel de plusieurs secondes) mais imposait sa
// propre cadence : MESURE sur le chargement de `training`, chemin FROID, 22 a 24 images par
// seconde pendant 4 secondes, avec un ecart moyen de 42 ms — c'est-a-dire exactement la tranche.
// Un nombre fixe ne peut pas faire autrement : il decide de la periode de la frame.
//
// On inverse la contrainte. La CIBLE est la periode d'une frame a 60 Hz ; le chargeur recoit ce
// qui en reste une fois payes le rendu et la logique. `outside` est mesure, pas suppose : c'est
// l'ecart entre deux appels MOINS le temps passe dans le chargeur au tour precedent.
//   - si le rendu tient en 8 ms, le chargeur recoit ~8 ms et la cadence est de 60 ;
//   - si le rendu coute deja plus qu'une frame (telephone bas de gamme), le chargeur retombe sur
//     le PLANCHER et la frame est bornee par le rendu, pas par nous — on ne peut pas faire mieux,
//     mais on ne fait pas PIRE.
// Le PLANCHER n'est pas cosmetique : sans lui, une frame lente affamerait le chargeur et le
// chargement n'avancerait plus du tout.
static constexpr float kLoadingScreenTargetFrameMs = 16.67f;
static constexpr float kLoadingScreenMinSliceMs = 4.f;

float adaptive_slice_ms(double gap_ms, double last_work_ms) {
  // Reglage EXPLICITE = on obeit, sans adaptation. C'est ce qui rend l'ablation lisible :
  // OG_LOADSCREEN_SLICE_MS=0 rend le chemin non borne (le gel), =40 rend la tranche fixe du cycle
  // precedent, non pose rend la tranche adaptative livree.
  if (getenv("OG_LOADSCREEN_SLICE_MS")) {
    return loading_screen_slice_ms();
  }
  if (gap_ms <= 0.0) {
    return kLoadingScreenTargetFrameMs - kLoadingScreenMinSliceMs;
  }
  const double outside = std::max(0.0, gap_ms - last_work_ms);
  return (float)std::max((double)kLoadingScreenMinSliceMs,
                         (double)kLoadingScreenTargetFrameMs - outside);
}

void Loader::update_blocking(TexturePool& tex_pool, bool announce, float budget_ms) {
  if (announce) {
    fmt::print("NOTE: coming out of blackout on next frame, doing all loads now...\n");
  }

  // MESURE DU GEL, SUR UNE VRAIE HORLOGE. `m_ls_gap_timer` mesure l'ecart entre deux appels,
  // c'est-a-dire entre deux frames reellement presentees pendant que l'ecran est affiche.
  // NATURE : une duree. REPERE : steady_clock, hote ET appareil. CE QU'ELLE LIT QUAND LE DEFAUT
  // EST ABSENT : la periode d'une frame ordinaire. Quand il est present : la duree du chargement
  // entier sur UN ecart. Publiee une fois par seconde, jamais par frame.
  // Arme sur le CHEMIN DE LA BARRIERE (announce == false), quel que soit le budget : sans ca
  // l'ablation `OG_LOADSCREEN_SLICE_MS=0` ne produirait aucune mesure et il n'y aurait rien a
  // comparer -- un avant/apres dont la moitie « avant » est muette ne prouve rien.
  double gap_for_slice = 0.0;
  if (!announce) {
    if (m_ls_gap_armed) {
      const double gap = m_ls_gap_timer.getMs();
      gap_for_slice = gap;
      m_ls_gap_max_ms = std::max(m_ls_gap_max_ms, gap);
      m_ls_gap_sum_ms += gap;
      m_ls_gap_n++;
    } else {
      m_ls_gap_armed = true;
      m_ls_gap_max_ms = 0.0;
      m_ls_gap_sum_ms = 0.0;
      m_ls_gap_n = 0;
      m_ls_gap_report.start();
    }
    m_ls_gap_timer.start();
    if (m_ls_gap_report.getMs() >= 1000.0 && m_ls_gap_n > 0) {
      fmt::print("LOADSCREEN-GAP images={} ecart_moy_ms={:.1f} ecart_max_ms={:.1f} fps={:.1f} budget_ms={:.1f}\n",
                 m_ls_gap_n, m_ls_gap_sum_ms / m_ls_gap_n, m_ls_gap_max_ms,
                 1000.0 * m_ls_gap_n / std::max(1.0, m_ls_gap_sum_ms), budget_ms);
      m_ls_gap_report.start();
      m_ls_gap_sum_ms = 0.0;
      m_ls_gap_n = 0;
    }
  } else {
    m_ls_gap_armed = false;
  }

  // BUDGET ADAPTATIF. `budget_ms < 0` = « decide pour moi » : c'est ce que passent les deux
  // renderers sur le chemin de la barriere. Une valeur >= 0 est un ordre (0 = non borne, le
  // chemin d'avant ; > 0 = tranche fixe), et sert aux ablations.
  if (!announce && budget_ms < 0.f) {
    budget_ms = adaptive_slice_ms(gap_for_slice, m_ls_last_work_ms);
  } else if (budget_ms < 0.f) {
    budget_ms = 0.f;
  }

  Timer budget_timer;
  const auto out_of_budget = [&]() {
    return budget_ms > 0.f && budget_timer.getMs() >= (double)budget_ms;
  };
  // Le temps REELLEMENT passe ici, quel que soit le chemin de sortie (il y a plusieurs `return`).
  struct WorkScope {
    Timer& t;
    double& out;
    ~WorkScope() { out = t.getMs(); }
  } work_scope{budget_timer, m_ls_last_work_ms};

  bool missing_levels = true;
  while (missing_levels) {
    bool needs_run = true;

    while (needs_run) {
      needs_run = false;
      {
        std::unique_lock<std::mutex> lk(m_loader_mutex);
        if (!m_level_to_load.empty()) {
          if (budget_ms > 0.f) {
            // Attente BORNEE : la lecture disque + zstd + deserialisation du fr3 se fait sur le
            // fil de chargement et peut durer des centaines de ms. L'attendre entierement ici,
            // c'est le gel. On attend ce qui reste du budget, puis on rend la main : la frame
            // suivante reprendra l'attente exactement au meme point.
            const double left = (double)budget_ms - budget_timer.getMs();
            if (left <= 0.0) {
              return;
            }
            m_file_load_done_cv.wait_for(lk, std::chrono::microseconds((long long)(left * 1000.0)),
                                         [&]() { return m_level_to_load.empty(); });
            if (!m_level_to_load.empty()) {
              return;
            }
          } else {
            m_file_load_done_cv.wait(lk, [&]() { return m_level_to_load.empty(); });
          }
        }
      }
    }

    needs_run = true;

    while (needs_run) {
      needs_run = false;
      {
        std::unique_lock<std::mutex> lk(m_loader_mutex);
        if (!m_initializing_tfrag3_levels.empty()) {
          needs_run = true;
        }
      }

      if (needs_run) {
        update(tex_pool);
        if (out_of_budget()) {
          return;
        }
      }
    }

    {
      std::unique_lock<std::mutex> lk(m_loader_mutex);
      missing_levels = false;
      for (auto& des : m_desired_levels) {
        if (m_loaded_tfrag3_levels.find(des) == m_loaded_tfrag3_levels.end()) {
          if (announce) {
            fmt::print("blackout loader doing additional level {}...\n", des);
          }
          missing_levels = true;
        }
      }
    }

    if (missing_levels) {
      set_want_levels(m_desired_levels);
      if (out_of_budget()) {
        return;
      }
    }
  }

  if (announce) {
    fmt::print("Blackout loads done. Current status:");
  }
  // Gmemory-ceiling-and-crash : c'est LE point ou l'appareil du proprietaire mourait — la
  // derniere ligne du moteur avant la mort etait « coming out of blackout ». Tous les
  // chargements du lot viennent de finir, donc c'est aussi le moment ou l'allocateur tient le
  // plus de pages LIBRES mais pas rendues. On les rend ici, et on publie le bilan.
  // Gplayability-input-and-loadgate: the purge stays tied to `announce`, i.e. to
  // the real blackout transition, which is the one the memory work calibrated it
  // on. A closed scene barrier calls update_blocking EVERY frame; purging the
  // arena 100+ times during one hold would spend real time and churn the RSS the
  // owner already validated, for nothing. The per-level purge
  // (heap_purge("niveau-pret")) still runs on the gate's path.
  if (announce) {
    heap_purge("blackout-fin");
  }
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  if (announce) {
    for (auto& ld : m_loaded_tfrag3_levels) {
      fmt::print("  {} is loaded.\n", ld.first);
    }
  }
}

const std::string* Loader::get_most_unloadable_level() {
  // ============================================================================================
  // Gcutscene-npc-flicker (essai 17) — LA REGLE TIENT EN UNE LIGNE, ET ELLE VAUT POUR LES TROIS
  // PASSES : le chargeur n'evince JAMAIS un niveau dont un modele merc vient d'etre dessine.
  //
  // POURQUOI ELLE EST ICI ET PAS DANS LA BOUCLE D'AGE. Le correctif 00e0d9182f tenait
  // `frames_since_last_used` a zero quand un merc etait dessine. Cela protege les passes qui
  // LISENT cet age — la 1re (:age > 180 et non desire) et la 3e (age > 180). Cela ne protege pas
  // la passe RESCAPE ajoutee a l'essai 16, qui decide sur `frames_not_desired > 30` SEUL et ne
  // regarde ni l'age ni la marque merc. Le correctif de l'essai 16 a donc ouvert un chemin
  // d'eviction que le correctif de l'essai 15 ne couvrait pas, et ce chemin mord PLUS TOT que
  // celui qu'il remplaçait : 31 images au lieu de 181. Un niveau que GOAL a lache peut tres bien
  // dessiner encore — `m_desired_levels` ne porte que DEUX noms en jak1, donc des qu'un troisieme
  // niveau a des acteurs a l'ecran il est « non desire » tout en etant visible.
  //
  // La grandeur `npc_evict_with_live_merc` mesurait deja exactement cette faute, au point de
  // production, quelques lignes plus bas — mais elle ne faisait que la CONSTATER. On la rend
  // impossible ici, la ou la victime est CHOISIE : c'est le seul endroit que les trois passes
  // traversent.
  //
  // Le drapeau `armed_for` laisse le bras d'ablation du harnais retrouver l'ancien comportement.
  // Il rend `true` par defaut (aucun item nomme) : le binaire de l'owner est TOUJOURS garde.
  const bool guard_armed = autoport_proof::armed_for("cutscene-npc-flicker");
  // A n'evaluer QUE sur un candidat deja retenu par sa passe : le compteur compte des refus
  // reels, pas des tests. `npc_evictions` et `npc_evict_pressure_frames` restent les
  // denominateurs independants — un zero de refus avec une pression a zero ne prouve rien.
  auto live_merc = [&](const std::unique_ptr<LevelData>& lev) {
    if (!guard_armed) {
      return false;
    }
    if (lev->last_merc_use_frame.load(std::memory_order_relaxed) + kMercKeepaliveFrames >=
        s_level_age_frame) {
      s_npcf_evict_refused_live_merc++;
      return true;
    }
    return false;
  };

  for (auto& [name, lev] : m_loaded_tfrag3_levels) {
    if (lev->frames_since_last_used > kUnloadAgeFrames &&
        std::find(m_desired_levels.begin(), m_desired_levels.end(), name) ==
            m_desired_levels.end() &&
        !live_merc(lev)) {
      return &name;
    }
  }

  // ============================================================================================
  // LA PASSE RESCAPE (Gcutscene-npc-flicker, essai 16). ELLE PASSE AVANT LE SACRIFICE.
  //
  // La passe ci-dessus ne prend un niveau non desire que s'il a AUSSI depasse 180 images sans
  // etre dessine. Un rescape JEUNE — GOAL vient de le lacher, il etait dessine l'image d'avant —
  // ne la declenche pas. La passe suivante, elle, ne regarde que l'age et IGNORE
  // `m_desired_levels` : elle jette alors un niveau que le jeu demande encore, en gardant celui
  // qu'il ne demande plus. C'est l'ordre inverse du bon sens, et c'est la seule facon dont
  // `beach` peut partir pendant `mayor-introduction` — `beach` y est desire (son `status` est
  // 'active, level.gc:1419 le nomme a chaque image) mais jamais dessine en fond
  // (`(0 display-level beach special)`, levels/beach/mayor.gc:147 ; le cas 'special de
  // drawable-tree.gc:15-20 est une branche VIDE), donc c'est le seul dont l'age monte.
  //
  // LA REGLE : le chargeur ne jette jamais ce que le jeu demande tant qu'il tient encore quelque
  // chose que le jeu ne demande plus. Une eviction prise ici est gratuite — GOAL a cesse de
  // nommer ce niveau, plus rien ne le dessine. Une eviction prise plus bas coute un rechargement
  // (202 a 317 images mesurees sur l'appareil de l'owner) PENDANT lequel les acteurs du niveau
  // n'ont plus de modele : c'est exactement le maire qui disparait.
  //
  // Garde-fou : si `m_desired_levels` est VIDE — GOAL n'a pas encore parle, on est avant la
  // premiere image de `level-update` — « non desire » ne veut rien dire et cette passe se tait.
  // Le comportement d'avant est alors rendu a l'identique.
  if (!m_desired_levels.empty()) {
    const std::string* rescape = nullptr;
    int rescape_age = kNotDesiredGraceFrames;
    for (const auto& [name, lev] : m_loaded_tfrag3_levels) {
      // Le plus anciennement lache d'abord : c'est celui dont le retour est le moins probable.
      // `live_merc` en DERNIER : un rescape qui dessine encore n'est pas un rescape, c'est un
      // niveau visible que GOAL a simplement cesse de nommer faute de slot.
      if (lev->frames_not_desired > rescape_age && !live_merc(lev)) {
        rescape_age = lev->frames_not_desired;
        rescape = &name;
      }
    }
    if (rescape) {
      s_npcf_evict_straggler++;
      return rescape;
    }
  }

  // Ce second passage evince un niveau que le jeu VEUT ENCORE (il est dans `m_desired_levels`).
  // Il reste — sans lui, un tas plein de niveaux desires ne se libererait jamais — mais depuis
  // Gcutscene-npc-flicker un niveau qui dessine un acteur ne peut plus atteindre cet age, et
  // depuis la passe RESCAPE ci-dessus il ne peut plus etre sacrifie tant qu'un niveau lache par
  // GOAL est encore resident. Y arriver signifie que TOUS les residents sont desires.
  for (const auto& [name, lev] : m_loaded_tfrag3_levels) {
    if (lev->frames_since_last_used > kUnloadAgeFrames && !live_merc(lev)) {
      // LA PASSE QUI EMPORTAIT LE MAIRE avant l'essai 15. `beach` est le seul fr3 qui porte
      // `mayor-lod0` ; l'empreinte de l'owner (premiere image noire a `image=184`, pour
      // `kUnloadAgeFrames`=180) designe une passe qui lit l'age, donc celle-ci ou la premiere.
      s_npcf_evict_pass2++;
      return &name;
    }
  }
  // Aucune victime : les trois passes ont ete traversees et tout ce qui restait dessinait. On
  // rend `nullptr` — le chargement en attente patiente une image de plus. C'est le bon arbitrage :
  // la marque merc expire en `kMercKeepaliveFrames` (2 images) des que la camera coupe, alors
  // qu'une eviction coute 202 a 317 images de rechargement MESUREES sur l'appareil de l'owner,
  // pendant lesquelles l'acteur n'a plus de modele. On ne bloque donc jamais durablement.
  return nullptr;
}

// ===== Grecharged-texture-hotreload ============================================================
namespace {
// LE MEME BOUTON QUE `refset::enabled()`, LU SANS EFFET DE BORD. `refset::enabled()` construit
// tout son etat au premier appel (repertoires, plan des 16 etapes) derriere une garde `static
// int` qui n'est pas atomique ; l'appeler depuis ce chemin de chargement ajouterait un appelant
// a une initialisation deja partagee entre deux fils. Ici on ne lit que le bouton, une seule
// fois, par une initialisation de static locale — thread-safe depuis C++11 et sans ecriture.
// Le jeu de references est un instrument x86 (refset.h, « portee honnete ») : pas de propriete.
bool refset_deterministic() {
  static const bool s_on = [] {
    const char* e = std::getenv("OG_REFSET");
    return e && (std::strcmp(e, "capture") == 0 || std::strcmp(e, "replay") == 0);
  }();
  return s_on;
}
// Compteurs de la passe. Publies a chaque image ; le harnais ne lit que la DERNIERE valeur.
u64 s_htr_passes = 0;          // passes de re-resolution commencees (une par niveau et bascule)
u64 s_htr_reuploaded = 0;      // textures re-resolues ET re-liees dans le pool
u64 s_htr_pixels_changed = 0;  // ... dont l'image envoyee au GPU differe de la precedente
// LA CLAUSE DE NEUTRALISATION, MESUREE. Sous `OG_REFSET` la borne en MILLISECONDES REELLES est
// retiree (voir le pave dans la boucle) ; ce compteur dit combien de fois elle AURAIT coupe la
// passe pendant la meme course. A zero, la borne n'etait pas vivante et la neutralisation
// n'expliquerait rien : c'est le meme controle que `refset_raw_alpha_min/max` pour l'alpha du
// retimeur. Ce compteur ne change AUCUN comportement, il ne fait que lire l'horloge.
u64 s_htr_rt_bound_hits = 0;
// LA MEME CLAUSE, POUR LA BORNE QUI SE COMPTE EN IMAGES. Elle a ete gardee a l'essai precedent
// parce qu'on la croyait « la meme valeur sur toute machine » : ceil(N/20) IMAGES. C'est faux des
// que le plan qui photographie se compte en frames de LOGIQUE. Mesure du 2026-09-06 sur eae4df44,
// relue dans `proof-engine.log` : `hotreload_reuploaded` monte encore a CHAQUE photo des 24
// etapes (911 -> 1123 -> 1311 entre `origine/h00` et `recharged/h00`, et ainsi de suite jusqu'a
// 14270) — AUCUNE passe ne s'est terminee avant sa photo. L'appareil dessine ~22 images par
// seconde la ou x86 en dessine 60 : le curseur de la passe est donc a une place differente au
// meme instant du plan, et ce qui est photographie n'est pas le meme jeu de textures.
// `s_htr_frame_bound_hits` dit combien de fois cette borne AURAIT coupe la passe sous `OG_REFSET`
// pendant la course : a zero, la neutralisation serait une clause vide.
u64 s_htr_frame_bound_hits = 0;
// Nombre de couples (niveau, image) ou une passe etait active a la fin de l'appel sous
// `OG_REFSET` : c'est-a-dire ou une photo prise a cette image aurait vu un jeu de textures a
// moitie resolu. Sous la neutralisation, il vaut ZERO — la passe commence et finit dans le meme
// appel, donc l'etat des textures est une fonction du REGIME et de rien d'autre.
u64 s_htr_partial_frames = 0;
}  // namespace

void Loader::refresh_recharged_textures(TexturePool& texture_pool) {
  const u32 regime = custom_tex::hotreload_regime();
  autoport_proof::publish("hotreload_regime", regime);

  // Les niveaux RESIDENTS, GAME.fr3 compris. `m_initializing_tfrag3_levels` appartient au thread
  // de chargement et n'est pas touche ici : un niveau dont la passe initiale se termine sous un
  // regime perime porte son estampille de DEBUT de passe, donc il est repris ici a l'image qui
  // suit son entree dans `m_loaded_tfrag3_levels`.
  std::vector<LevelData*> levels;
  levels.push_back(&m_common_level);
  for (auto& [name, lev] : m_loaded_tfrag3_levels) {
    levels.push_back(lev.get());
  }

  Timer budget;
  for (auto* lev : levels) {
    if (!lev->level || lev->tex_regime == UINT32_MAX || lev->tex_regime == regime) {
      continue;
    }
    // Une passe initiale encore en cours : la laisser finir, elle televerse deja sous le regime
    // courant pour ce qui lui reste, et son prefixe sera repris a l'image d'apres.
    if (lev->textures.size() != lev->level->textures.size()) {
      continue;
    }
    if (!lev->tex_refresh_active) {
      lev->tex_refresh_active = true;
      lev->tex_refresh_cursor = 0;
      s_htr_passes++;
    }
    if (lev->tex_upload_fp.size() != lev->textures.size()) {
      lev->tex_upload_fp.resize(lev->textures.size(), 0);
    }
    const bool is_common = (lev == &m_common_level);
    std::unique_lock<std::mutex> tpool_lock(texture_pool.mutex());
    int tex_this_run = 0;
    while (lev->tex_refresh_cursor < lev->textures.size()) {
      const size_t i = lev->tex_refresh_cursor++;
      const auto& tex = lev->level->textures[i];
      const GLuint old_gl = lev->textures[i];
      const u64 old_fp = lev->tex_upload_fp[i];
      const GLuint new_gl = (GLuint)add_texture(texture_pool, tex, is_common, old_gl);
      if (g_last_add_texture_swapped && new_gl != old_gl) {
        lev->textures[i] = new_gl;
        // Differee : l'ancien objet peut encore etre lie par la frame en cours.
        m_garbage_textures.push_back(old_gl);
        s_htr_reuploaded++;
        if (g_last_add_texture_fp != old_fp) {
          s_htr_pixels_changed++;
          autoport_proof::note_hit_for("recharged-texture-hotreload");
        }
        lev->tex_upload_fp[i] = g_last_add_texture_fp;
      }
      // LE JEU DE REFERENCES NE PEUT PAS DEPENDRE DE LA MONTRE MURALE. Cette passe est amortie
      // sur deux bornes de nature differente : `tex_this_run > 20`, qui se compte en IMAGES, et
      // `budget.getMs()`, qui se compte en MILLISECONDES REELLES. La seconde est une entree de
      // montre murale dans l'image DESSINEE, exactement comme l'alpha de `render_pace` que
      // `refset.h` neutralise deja : le jeu de references bascule `recharged-master?` a chaque
      // etape, `hotreload_regime()` passe de 6 a 0 et retour, et 2761 textures sont re-resolues
      // pendant les 180 images de stabilisation qui precedent la photo. Selon la charge de la
      // machine, la photo tombe avant ou apres la fin de la passe.
      //
      // MESURE DU 2026-09-06, deux rejeux consecutifs du MEME binaire (sha 9c1250937fa915c8)
      // contre les MEMES 16 references : maxdiff 211 / diffpx 291355, puis maxdiff 184 /
      // diffpx 289129 — les 16 images des DEUX jeux touchees, avec hotreload_reuploaded=2761 et
      // hotreload_pixels_changed=62 dans les deux courses.
      //
      // Sous `OG_REFSET` on retire LA SEULE BORNE EN TEMPS REEL et on garde celle qui se compte
      // en images : la passe dure alors exactement ceil(N/20) images, la meme valeur sur toute
      // machine. On ne draine PAS tout d'un coup — ce serait plusieurs secondes de verrou sur le
      // pool de textures pendant un chargement, donc un autre defaut a la place de celui-ci.
      const bool rt_over = budget.getMs() > SHARED_TEXTURE_LOAD_BUDGET;
      if (rt_over && refset_deterministic()) {
        s_htr_rt_bound_hits++;
      }
      // LES DEUX BORNES SONT DE LA MEME NATURE, ET LA SECONDE A SURVECU A TORT. `tex_this_run`
      // se compte en IMAGES DESSINEES ; le plan du jeu de references se compte en frames de
      // LOGIQUE. Tant que les deux ne sont pas dans le meme rapport sur toutes les machines, la
      // photo tombe a une place differente de la passe. Sous `OG_REFSET` on draine donc le
      // niveau ENTIER dans l'appel : le jeu de textures redevient une fonction du seul regime.
      // Hors de ce mode rien ne change — c'est la meme borne qu'avant, au meme endroit.
      const bool frame_over = (++tex_this_run > 20);
      if (frame_over && refset_deterministic()) {
        s_htr_frame_bound_hits++;
      }
      if (!refset_deterministic() && (frame_over || rt_over)) {
        break;
      }
    }
    if (lev->tex_refresh_cursor >= lev->textures.size()) {
      lev->tex_refresh_active = false;
      lev->tex_regime = regime;
    } else if (refset_deterministic()) {
      s_htr_partial_frames++;
    }
    const bool rt_over_outer = budget.getMs() > SHARED_TEXTURE_LOAD_BUDGET;
    if (rt_over_outer && refset_deterministic()) {
      s_htr_rt_bound_hits++;
    }
    if (!refset_deterministic() && rt_over_outer) {
      break;
    }
  }

  autoport_proof::publish("hotreload_passes", s_htr_passes);
  autoport_proof::publish("hotreload_reuploaded", s_htr_reuploaded);
  autoport_proof::publish("hotreload_pixels_changed", s_htr_pixels_changed);
  autoport_proof::publish("hotreload_rt_bound_hits", s_htr_rt_bound_hits);
  autoport_proof::publish("hotreload_frame_bound_hits", s_htr_frame_bound_hits);
  autoport_proof::publish("hotreload_partial_frames", s_htr_partial_frames);
}

void Loader::update(TexturePool& texture_pool) {
  // water-census : le recensement de l'eau, une seule fois. Ici parce que c'est le premier site
  // par image ou les chemins d'assets sont resolus sur les DEUX plateformes ; il ne lit que des
  // fichiers texte et ne touche a aucun etat de rendu.
  water_census::run_once();

  Timer loader_timer;

  // Gmemory-ceiling-and-crash : la purge DIFFEREE. Celle de `niveau-pret` tombe avant la
  // premiere image du niveau ; le maximum de la course est mesure environ une seconde plus tard,
  // quand le rendu a fini de se remettre en route. Une purge de plus, 120 frames apres la fin du
  // chargement, rend au systeme ce que cette remise en route a libere. Une seule fois par
  // chargement, jamais par frame.
  if (m_frames_until_purge > 0 && --m_frames_until_purge == 0) {
    heap_purge("apres-chargement");
  }

  {
    // lock because we're accessing m_active_levels
    std::unique_lock<std::mutex> lk(m_loader_mutex);
    // only main thread can touch this.
    s_level_age_frame++;
    const bool keepalive_armed = autoport_proof::armed_for("cutscene-npc-flicker");
    for (auto& [name, lev] : m_loaded_tfrag3_levels) {
      const bool in_active_list =
          std::find(m_active_levels.begin(), m_active_levels.end(), name) != m_active_levels.end();
      // Gcutscene-npc-flicker — UN NIVEAU QUI DESSINE UN ACTEUR EST UN NIVEAU UTILISE.
      // Voir le pave de `LevelData::last_merc_use_frame` (loader/common.h) : sans ce terme,
      // l'age ne voit que le FOND, et un niveau qui ne fournit que des PNJ de cinematique
      // franchit les 180 images de `get_most_unloadable_level` pendant qu'il est a l'ecran.
      // La tolerance de 2 images absorbe une image ou GOAL n'a rien soumis (coupe de camera
      // d'une image, hoquet de la chaine DMA) sans jamais prolonger un niveau reellement muet.
      const bool merc_live =
          lev->last_merc_use_frame.load(std::memory_order_relaxed) + kMercKeepaliveFrames >=
          s_level_age_frame;

      // Gcutscene-npc-flicker (essai 16) — L'HORLOGE DE L'INTENTION DU JEU, tenue ici parce que
      // c'est le seul endroit qui tourne une fois par image en tenant `m_loader_mutex`. Voir le
      // pave de `LevelData::frames_not_desired` (loader/common.h) : `m_desired_levels` porte au
      // plus DEUX noms en jak1, donc un troisieme resident est toujours un rescape.
      if (std::find(m_desired_levels.begin(), m_desired_levels.end(), name) !=
          m_desired_levels.end()) {
        lev->frames_not_desired = 0;
      } else {
        lev->frames_not_desired++;
      }

      // L'age CONTREFACTUEL, celui d'avant le correctif. Aucune decision ne le lit.
      if (in_active_list) {
        lev->frames_since_last_used_no_merc = 0;
      } else {
        lev->frames_since_last_used_no_merc++;
        // L'EVENEMENT, pas le cumul : l'image EXACTE ou l'ancien code rendait ce niveau
        // evincable alors qu'il fournissait un modele a l'ecran. Chacune de ces occurrences est
        // une disparition de PNJ que le correctif vient d'empecher.
        if (lev->frames_since_last_used_no_merc == kUnloadAgeFrames + 1 && merc_live) {
          s_npcf_evictable_while_drawing++;
        }
      }

      if (in_active_list) {
        lev->frames_since_last_used = 0;
      } else if (merc_live && keepalive_armed) {
        lev->frames_since_last_used = 0;
        s_npcf_merc_keepalive_frames++;
        autoport_proof::note_hit_for("cutscene-npc-flicker");
      } else {
        lev->frames_since_last_used++;
      }
      // L'age le plus haut atteint par un niveau resident, toutes causes. Lu a cote du verdict :
      // un maximum reste sous `kUnloadAgeFrames` dit que rien n'etait evincable pendant la
      // course, et donc qu'un zero sur les evictions ne prouve rien.
      if ((uint64_t)lev->frames_since_last_used > s_npcf_level_age_max) {
        s_npcf_level_age_max = (uint64_t)lev->frames_since_last_used;
      }
    }
    if (m_loaded_tfrag3_levels.size() > s_npcf_loaded_levels_max) {
      s_npcf_loaded_levels_max = m_loaded_tfrag3_levels.size();
    }
  }
  publish_level_age_counters();

  bool did_gpu_stuff = false;

  // work on moving initializing to initialized.
  {
    // accessing initializing, should lock
    std::unique_lock<std::mutex> lk(m_loader_mutex);
    // grab the first initializing level:
    const auto& it = m_initializing_tfrag3_levels.begin();
    if (it != m_initializing_tfrag3_levels.end()) {
      did_gpu_stuff = true;
      std::string name = it->first;
      auto& lev = it->second;
      if (it->second->load_id == UINT64_MAX) {
        it->second->load_id = m_id++;
      }

      // we're the only place that erases, so it's okay to unlock and hold a reference
      lk.unlock();
      bool done = true;
      LoaderInput loader_input;
      loader_input.lev_data = lev.get();
      loader_input.mercs = &m_all_merc_models;
      loader_input.tex_pool = &texture_pool;

      for (auto& stage : m_loader_stages) {
        auto evt = scoped_prof(fmt::format("stage-{}", stage->name()).c_str());
        Timer stage_timer;
        done = stage->run(loader_timer, loader_input);
        if (stage_timer.getMs() > 5.f) {
          fmt::print("stage {} took {:.2f} ms\n", stage->name(), stage_timer.getMs());
        }
        // Gmemory-ceiling-and-crash : RENDRE LA GEOMETRIE CPU DES QU'ELLE EST DANS LE GPU,
        // pas a la fin du lot. L'ordre des etapes est tie(0), texture(1), tfrag(2), shrub,
        // collide, merc, hfrag, stall (make_loader_stages) et chacune finit avant la suivante :
        // quand `tfrag` rend `done`, tie ET tfrag sont televerses, donc leurs 79 Mo de sommets
        // et de tangentes (village1 : 52,6 + 26,3) sont morts. Les garder jusqu'a la fin du lot
        // les faisait coexister avec les textures GPU du niveau, et c'est EXACTEMENT le sommet
        // de la course : `A55-RSS merc-uploade rss=848Mo` contre `fr3-unpack rss=650Mo`.
        // Aucune etape suivante ne lit ces tableaux : shrub lit les siens (epargnes), collide la
        // collision, merc les donnees merc, hfrag le hfrag.
        // ORDRE DES ETAPES : tie(0), texture(1), tfrag(2), shrub, collide, merc, hfrag, stall.
        // ORDRE : la liberation suit immediatement l'etape qui a televerse le systeme.
        //
        if (done && stage->name() == "texture" && !lev->cpu_geo_released[1]) {
          release_uploaded_vertices(*lev->level, 1);
          lev->cpu_geo_released[1] = true;
          heap_purge("geo-tie-rendue");
        }
        if (done && stage->name() == "tfrag" && !lev->cpu_geo_released[0]) {
          release_uploaded_vertices(*lev->level, 0);
          lev->cpu_geo_released[0] = true;
          heap_purge("geo-tfrag-rendue");
        }
        if (!done) {
          break;
        }
      }

      if (done) {
        auto evt = scoped_prof("finish-stages");
#ifdef __ANDROID__
        // F1d Adreno defuse: the first merc draw consuming a freshly-loaded
        // level's GL objects faults inside the driver's draw-state walk
        // (null+0x28 at libGLESv2_adreno+0x13a414) even when every gk-side
        // object is verified legal at the draw (run5/run6 forensics:
        // glIsTexture=1, FBO complete, err=0, index range mapped+memcmp'd
        // 1 ms before the fault). Drain the driver's async work HERE — at
        // load completion on the GL thread, during the blackout, with no
        // flush in flight — so the upload burst is fully finalized before
        // any frame consumes it. (A mid-frame glFinish between merc flushes
        // made things WORSE — run6 crashed at the boot reveal that the same
        // build without it survived.)
        // perf-gl-waits : le drain de fin de chargement etait un `glFinish` — il bloquait le fil
        // GL jusqu'a ce que le pilote ait TOUT fini, y compris le travail de l'image en cours.
        // Une cloture nommee attend uniquement le travail DEJA soumis, et rend la main des qu'il
        // est passe. Le site est DECLARE : c'est une synchronisation deliberee, pas une sonde.
        {
          gl_query_census::Armed _ap("load-completion-fence");
          // Le glad profil-bureau laisse des entrees ES non resolues (defaut A36) : un pointeur
          // nul appele est un BLR-vers-0, pas un echec lisible. On verifie les trois avant.
          GLsync fence = (glad_glFenceSync && glad_glClientWaitSync && glad_glDeleteSync)
                             ? glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
                             : nullptr;
          if (fence) {
            glFlush();
            glClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, 1000000000ull /* 1 s */);
            glDeleteSync(fence);
          } else {
            glFinish();  // le pilote n'a pas donne de cloture : on retombe sur le drain complet
          }
        }
        fprintf(stderr, "F1D-LOADSYNC lev=%s load_id=%llu fence at load completion\n",
                name.c_str(), (unsigned long long)lev->load_id);
#endif
        report_level_ram(name, *lev->level, "charge");
        report_merc_detail(name, *lev->level, "charge");
        // ARME 2026-08-26. Les sommets CPU de TFRAG et TIE partent apres televersement.
        // SHRUB EST EPARGNE : `Shrub::update_load` lit ses sommets DIRECTEMENT (compte, LUT de
        // vent, index d'ombre) et pas seulement pour une mesure — les liberer casse l'herbe et
        // les ombres. Les INDEX de tous les systemes restent : le rendu les relit chaque frame.
        // La fonction s'abstient aussi sur les niveaux a herbe vive (rescan a la demande du menu).
        // REPLI : le cas normal libere DES LA FIN DE L'ETAPE `tfrag` (voir la boucle d'etapes
        // plus haut) ; on ne passe ici que si cette etape n'a pas ete atteinte. Le drapeau
        // garantit UN SEUL passage.
        //
        // Gloading-screen-window : CHRONOMETRER CE BLOC. Il s'execute sur le thread de rendu, SANS
        // BUDGET, exactement a l'image ou le niveau devient resident -- c'est-a-dire a l'image ou
        // la barriere de chargement s'ouvre et ou l'ecran de chargement va se lever. Mesure x86
        // du 2026-08-30 sur `save-geyser` : la derniere image de l'ecran de chargement dure
        // 257,8 ms alors que les 60 precedentes tiennent a 17,3 ms de maximum. Le suspect etait
        // designe par sa POSITION ; ces quatre chiffres disent lequel des quatre etages paie, au
        // lieu de le supposer.
        // NATURE : des durees, en ms. REPERE : `steady_clock` du thread de rendu.
        // CE QUE CA LIT QUAND LE DEFAUT EST ABSENT : quatre valeurs de l'ordre de la ms.
        Timer t_pret;
        double ms_rel = 0.0, ms_merc = 0.0, ms_rap = 0.0;
        {
          Timer t0;
          for (int sys = 0; sys < 2; sys++) {
            if (!lev->cpu_geo_released[sys]) {
              release_uploaded_vertices(*lev->level, sys);
              lev->cpu_geo_released[sys] = true;
            }
          }
          ms_rel = t0.getMs();
        }
        {
          Timer t0;
          release_uploaded_merc_vertices(*lev->level);
          ms_merc = t0.getMs();
        }
        {
          Timer t0;
          report_level_ram(name, *lev->level, "apres-liberations");
          report_merc_detail(name, *lev->level, "apres-liberations");
          ms_rap = t0.getMs();
        }
        heap_purge("niveau-pret");
        fmt::print("LSWIN-COUT niveau={} liberation_ms={:.1f} merc_ms={:.1f} "
                   "rapport_ms={:.1f} total_ms={:.1f}\n",
                   name, ms_rel, ms_merc, ms_rap, t_pret.getMs());
        // ... et une seconde, une fois le rendu relance (cf. Loader.h::m_frames_until_purge).
        m_frames_until_purge = 120;
        lk.lock();
        m_loaded_tfrag3_levels[name] = std::move(lev);
        // Gplayability-input-and-loadgate: THIS is the instant the level becomes
        // drawable — everything before it (the DGO being linked, the fr3 being
        // read) still renders nothing. It is the only honest signal a scene
        // barrier can wait on, so publish it. See game/system/load_gate.h.
        load_gate::mark_level_resident(name);
        m_initializing_tfrag3_levels.erase(it);

        for (auto& stage : m_loader_stages) {
          stage->reset();
        }
      }
    }
  }

  if (!did_gpu_stuff) {
    auto evt = scoped_prof("gpu-unload");
    // try to remove levels.
    Timer unload_timer;
    if ((int)m_loaded_tfrag3_levels.size() >= m_max_levels) {
      // LA PRESSION : l'image ou l'eviction est possible. C'est le denominateur de tout ce qui
      // suit. Il est reste a ZERO sur les courses x86 des essais precedents (deux niveaux
      // residents pour un plafond de trois) — d'ou treize verdicts verts sur un defaut vivant.
      s_npcf_evict_pressure_frames++;
      auto to_unload = get_most_unloadable_level();
      if (to_unload) {
        auto& lev = m_loaded_tfrag3_levels.at(*to_unload);
        // Gcutscene-npc-flicker — LA MESURE AU POINT DE PRODUCTION. Cette eviction va effacer
        // les modeles merc du niveau de `m_all_merc_models` quelques lignes plus bas. Si l'un
        // d'eux vient d'etre dessine, l'acteur correspondant disparait de l'ecran jusqu'a la
        // fin du rechargement — c'est exactement ce que l'owner voit sur le maire. Compte les
        // DEUX : les evictions (le denominateur, sans lequel un zero ne prouve rien) et celles
        // qui emportent un modele vivant (qui doit rester a zero).
        s_npcf_evictions++;
        // LE NOM, pas seulement le compte : `beach` evince pendant `mayor-introduction` est le
        // defaut de l'owner ; `title` evince au demarrage ne l'est pas. Sans ce champ les deux se
        // lisent pareil dans proof.txt.
        autoport_proof::publish_text("npc_evicted_level_last", to_unload->c_str());
        if (lev->last_merc_use_frame.load(std::memory_order_relaxed) + kMercKeepaliveFrames >=
            s_level_age_frame) {
          s_npcf_evict_with_live_merc++;
          lg::warn("[npc-flicker/loader] EVICTION d'un niveau qui dessinait : lev={} age={} "
                   "age_sans_merc={} derniere_image_merc={} image={}",
                   *to_unload, lev->frames_since_last_used, lev->frames_since_last_used_no_merc,
                   lev->last_merc_use_frame.load(std::memory_order_relaxed), s_level_age_frame);
        }
        std::unique_lock<std::mutex> lk(texture_pool.mutex());
        fmt::print("------------------------- PC unloading {}\n", *to_unload);
#ifdef __ANDROID__
        fprintf(stderr, "F1E-EVICT lev=%s ntex=%zu load_id=%llu fsl=%d\n", to_unload->c_str(),
                lev->textures.size(), (unsigned long long)lev->load_id,
                lev->frames_since_last_used);
#endif
        for (size_t i = 0; i < lev->level->textures.size(); i++) {
          auto& tex = lev->level->textures[i];
          if (tex.load_to_pool) {
            texture_pool.unload_texture(PcTextureId::from_combo_id(tex.combo_id),
                                        lev->textures.at(i));
          }
        }
        lk.unlock();
        for (auto tex : lev->textures) {
          if (EXTRA_TEX_DEBUG) {
            for (auto& slot : texture_pool.all_textures()) {
              if (slot.source) {
                ASSERT(slot.gpu_texture != tex);
              } else {
                ASSERT(slot.gpu_texture != tex);
              }
            }
          }
          m_garbage_textures.push_back(tex);
        }

        for (auto& tie_geo : lev->tie_data) {
          for (auto& tie_tree : tie_geo) {
            m_garbage_buffers.push_back(tie_tree.vertex_buffer);
            if (tie_tree.has_wind) {
              m_garbage_buffers.push_back(tie_tree.wind_indices);
            }
            // Grecharged-foliage-wind3 : le VBO du poids de balancement suit le meme cycle de vie
            // que le VBO de sommets ci-dessus. (La fuite du VBO de TANGENTES signalee ici
            // disparait avec le VBO lui-meme : lighting-legacy-purge essai 8.)
            m_garbage_buffers.push_back(tie_tree.sway_buffer);
            if (tie_tree.contact_buffer) m_garbage_buffers.push_back(tie_tree.contact_buffer);
            if (tie_tree.contact_texture) m_garbage_textures.push_back(tie_tree.contact_texture);
            m_garbage_buffers.push_back(tie_tree.index_buffer);
          }
        }

        for (auto& tfrag_geo : lev->tfrag_vertex_data) {
          for (auto& tfrag_buff : tfrag_geo) {
            m_garbage_buffers.push_back(tfrag_buff);
          }
        }
        // foliage-wind : le VBO de balancement SHRUB suit le cycle de vie des autres VBO de
        // niveau. (Note, PAS corrigee ici parce qu'anterieure et hors perimetre :
        // `shrub_vertex_data` lui-meme n'est collecte nulle part.)
        for (auto& shrub_sway : lev->shrub_sway_data) {
          m_garbage_buffers.push_back(shrub_sway);
        }

        m_garbage_buffers.push_back(lev->hfrag_indices);
        m_garbage_buffers.push_back(lev->hfrag_indices);

        m_garbage_buffers.push_back(lev->collide_vertices);
        m_garbage_buffers.push_back(lev->merc_vertices);
        m_garbage_buffers.push_back(lev->merc_indices);

        for (auto& model : lev->level->merc_data.models) {
          auto& mercs = m_all_merc_models.at(model.name);
          MercRef ref{&model, lev->load_id};
          auto it = std::find(mercs.begin(), mercs.end(), ref);
          ASSERT_MSG(it != mercs.end(), fmt::format("missing merc: {}\n", model.name));
          mercs.erase(it);
        }

        m_loaded_tfrag3_levels.erase(*to_unload);
      }
    }

    if (unload_timer.getMs() > 5.f) {
      fmt::print("Unload took {:.2f}ms\n", unload_timer.getMs());
    }

    if (!m_garbage_buffers.empty()) {
      did_gpu_stuff = true;
      for (int i = 0; i < 5 && !m_garbage_buffers.empty(); i++) {
#ifdef __ANDROID__
        fprintf(stderr, "F1E-DELBUF buf=%u left=%zu\n", (unsigned)m_garbage_buffers.back(),
                m_garbage_buffers.size());
#endif
        glDeleteBuffers(1, &m_garbage_buffers.back());
        m_garbage_buffers.pop_back();
      }
    }

    if (!did_gpu_stuff && !m_garbage_textures.empty()) {
      for (int i = 0; i < 20 && !m_garbage_textures.empty(); i++) {
#ifdef __ANDROID__
        fprintf(stderr, "F1E-DELTEX site=loader-garbage tex=%u left=%zu\n",
                (unsigned)m_garbage_textures.back(), m_garbage_textures.size());
#endif
        glDeleteTextures(1, &m_garbage_textures.back());
        m_garbage_textures.pop_back();
      }
    }
  }

  // Grecharged-texture-hotreload : hors du verrou du chargeur (elle prend celui du pool), et
  // apres le travail de chargement — un niveau qui arrive a l'image courante est repris a la
  // suivante, pas a moitie.
  refresh_recharged_textures(texture_pool);

  if (loader_timer.getMs() > 5) {
    fmt::print("Loader::update slow setup: {:.1f}ms\n", loader_timer.getMs());
  }

#ifdef __ANDROID__
  // Measured on the NVIDIA Shield (3 GB, 2026-08-25): 690 MB of native heap for
  // 476 MB actually live — 208 MB retained by the allocator — and lmkd killed
  // the game while ~460 MB was still nominally available. Level loading is where
  // that garbage is produced, so give the pages back here.
  {
    // The transient is what gets the game killed, not the resident set: measured
    // on the Shield, idle sits at ~680 MB and a level load spikes to ~993 MB.
    // Purge often while a load is actually running, rarely when idle — M_PURGE
    // walks the whole heap, so it is not free.
    static Timer purge_timer;
    static bool purge_armed = false;
    const double purge_interval_ms = did_gpu_stuff ? 100.0 : 2000.0;
    if (!purge_armed || purge_timer.getMs() > purge_interval_ms) {
      purge_armed = true;
      purge_timer.start();
      mallopt(M_PURGE, 0);
    }
  }
#endif
}

std::optional<MercRef> Loader::get_merc_model(const char* model_name) {
  // don't think we need to lock here...
  const auto& it = m_all_merc_models.find(model_name);
  if (it != m_all_merc_models.end() && !it->second.empty()) {
    const MercRef& ref = it->second.front();
    // Gcutscene-npc-flicker — LE GESTE QUI MANQUAIT, ET QUI ETAIT DEJA ECRIT EN COMMENTAIRE :
    //     // it->second.front().parent_level->frames_since_last_used = 0;
    // On marque au lieu d'ecrire l'age : `frames_since_last_used` garde UN SEUL ecrivain, la
    // boucle de `Loader::update`, qui lit cette marque et decide. Voir le pave de
    // `LevelData::last_merc_use_frame` (loader/common.h) pour la chaine complete jusqu'au
    // maire qui disparait 8 fois dans `mayor-introduction`.
    //
    // Cet appel a lieu pour un paquet merc que GOAL A SOUMIS : le niveau fournit un acteur que
    // le jeu vient de demander a dessiner. C'est la definition meme d'un niveau en service.
    if (ref.level) {
      ref.level->last_merc_use_frame.store(s_level_age_frame, std::memory_order_relaxed);
    }
    return ref;
  } else {
    // LES DEUX ECHECS QUE CETTE LIGNE CONFONDAIT. `it == end()` = le modele n'a jamais ete
    // charge (mauvais nom, fr3 absent). Vecteur VIDE = la cle est la et le niveau qui portait le
    // modele a ete EVINCE : la boucle `mercs.erase(it)` du bloc d'eviction vide le vecteur et ne
    // retire jamais la cle. C'est le second cas qui produit le maire clignotant, et le publier a
    // part evite d'envoyer l'essai suivant chercher un probleme de chargement.
    if (it == m_all_merc_models.end()) {
      s_npcf_merc_key_missing++;
    } else {
      s_npcf_merc_vec_empty++;
    }
    return std::nullopt;
  }
}
