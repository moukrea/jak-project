#include "game/graphics/opengl_renderer/ao_contact_draws.h"
#include "shrub_contact_measurement.h"
#include "Tie3.h"
#include "game/graphics/opengl_renderer/ao_tie_alpha_probe.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"

#include <array>
#include <chrono>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <unordered_map>

#include "common/global_profiler/GlobalProfiler.h"
#include "common/log/log.h"
#include "common/util/Assert.h"

#include "common/custom_data/FoliageWindLaw.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/graphics/opengl_renderer/background/foliage_wind.h"
#include "game/mips2c/spart_prof.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"
#include "game/graphics/opengl_renderer/hdr.h"

#include "third-party/imgui/imgui.h"

namespace {
std::atomic<uint64_t> contact_uploads{0}, contact_binding_failures{0};
std::atomic<uint64_t> contact_mapped_trees{0}, contact_mapping_failures{0};
std::atomic<uint64_t> contact_eligible_instances{0}, contact_eligible_vertices{0};
std::atomic<uint64_t> contact_jak_samples{0}, contact_object_samples{0};
}
TieContactStats tie_contact_stats() {
  return {contact_uploads.load(std::memory_order_relaxed),
          contact_binding_failures.load(std::memory_order_relaxed),
          contact_mapped_trees.load(std::memory_order_relaxed),
          contact_mapping_failures.load(std::memory_order_relaxed),
          contact_eligible_instances.load(std::memory_order_relaxed),
          contact_eligible_vertices.load(std::memory_order_relaxed),
          contact_jak_samples.load(std::memory_order_relaxed),
          contact_object_samples.load(std::memory_order_relaxed)};
}

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace {
// ---------------------------------------------------------------------------------------------
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D1) — LA BRISE NATIVE, OPTION ETEINTE.
//
// Verbatim : « les arbres qui sont sensés être animés par défaut font de légers twitchs sans
// animations ». Ce n'est pas une amplitude, c'est une CADENCE, et le defaut a deux moities qui se
// tiennent :
//
//   (a) COTE PRODUCTEUR (GOAL). `update-wind` remplit un anneau de 64 vecteurs, un slot par
//       appel. La version « high fps » multipliait l'INDEX D'ECRITURE et l'amplitude par
//       `time-adjust-ratio` en gardant UN appel par image dessinee, alors que l'index de LECTURE
//       est le compteur BRUT chez tous les consommateurs. A 15 images/s le ratio vaut 4, le pas
//       d'ecriture vaut 4 slots, et `64 - 64/pgcd(4,64)` = 48 slots ne sont JAMAIS ecrits : le
//       ressort lit du vide trois fois sur quatre puis un coup multiplie par 4. Corrige a la
//       source dans goal_src/jak1/engine/gfx/background/wind.gc : l'arithmetique de ND est
//       restauree et c'est le NOMBRE D'APPELS qui porte la cadence.
//
//   (b) COTE RESSORT (ici). `do_wind_math` integre avec un pas CODE EN DUR de 1/60 s (`cz`, et
//       `wind-const.z` dans goal_src/jak1/engine/gfx/tie/tie-work.gc:15) et tournait UNE fois par
//       image DESSINEE. A 15 images/s la brise de ND avancait donc a un quart de sa vitesse.
//
// LE NOMBRE DE PAS SE LIT SUR `wind-time`, PAS SUR UNE HORLOGE A NOUS. Le compteur avance
// d'exactement un cran par appel a `update-wind`, et `update-wind` est desormais appelee une fois
// par pas de 1/60 s. `wind_time - m_wind_last_time` EST donc le nombre de pas que cette image
// porte — exact, partage avec le producteur, et sans second generateur aleatoire. Le round 3
// avait construit une COPIE du vent avancee a l'horloge murale ; elle est supprimee, parce que
// deux horloges peuvent diverger et que celle-ci ne le peut pas. A 60 images/s le delta vaut 1 et
// tout ce fichier fait exactement ce qu'il faisait avant : la correction n'agit que la ou le
// defaut existe.
//
// CE N'EST PAS UNE OPTION « RECHARGED ». L'owner demande que la brise native marche « par défaut
// sans notre modification » : le correctif vit donc HORS du basculement, et son ablation est
// `*wind-native-rate*` (OG_WIND_NATIVE_RATE / debug.opengoal.wind.native_rate), qui remet GOAL
// sur son ancien chemin — le delta retombe alors a 1 tout seul et cette moitie-ci se desarme avec
// lui, sans qu'aucun drapeau ait a etre lu deux fois.
//
// NON corrige, et deliberement : le ressort persiste sa sortie DEJA MULTIPLIEE PAR `stiffness`
// dans le slot de position (`my_vector[0] = vf27.x()` apres `vf27 *= stiffness`). Le listing EE
// brut (docs/progress-notes/jak1/scratch/tie_ee.asm:486-522), la transcription mips2c
// (game/mips2c/jak1_functions/tie_methods.cpp:633,647) et le programme VU SHRUB INDEPENDANT
// (docs/progress-notes/jak1/scratch/shrub_asm.md:1028-1054) font tous le meme choix. Le vent TIE
// de ND est donc un appui lent, pas un balancement ; « restituer l'intention ND » veut dire
// restituer sa CADENCE, pas inventer l'oscillateur qu'il n'a jamais eu.
//
// Combien de pas de 1/60 s cette image porte. Borne haute a 8 pour qu'un a-coup de chargement ne
// fasse pas defiler la brise d'un huitieme de seconde d'un coup ; 0 est autorise et signifie
// « aucun tick de logique sur cette image » (pas fixe arme, image de rendu seul) — dans ce cas le
// cisaillement DEJA calcule est reapplique tel quel, sans integrer.
static int fw_wind_ticks(u32 now, u32& last, bool& seeded, bool paused) {
  // Essai 11 : UNE definition, partagee avec Shrub.cpp (le vent natif des buissons integre le meme
  // ressort au meme pas) — foliage_wind::wind_ticks_for porte exactement la regle ci-dessus.
  return foliage_wind::wind_ticks_for(now, last, seeded, paused);
}

// ---------------------------------------------------------------------------------------------
// Grecharged-foliage-wind2 SHEAR AUDIT. The permanent renderer-side counter that replaces round
// 1's capture-derived motion statistic (owner banned that class of proof, 2026-07-26/2026-08-04).
// Every wind instance reports the stock shear and the shear this build actually applied; once per
// window we print peak + RMS of both and their ratio.
//
// How to read the numbers: the shear is dimensionless and displaces a vertex by
// `shear * (its height above the instance origin)`, so
//     crown sway in metres = shear * prototype height in metres
// with the heights coming from the offline census in tie-census.txt. ratio_peak == 1.000000 with
// the toggle OFF is a RUNTIME proof that OFF is the untouched stock arithmetic.
struct FwAudit {
  std::string level;
  double stock_sq = 0.0, appl_sq = 0.0;
  float stock_peak = 0.f, appl_peak = 0.f;
  // MOTION, i.e. how far the shear travels from one frame to the next. This is the field the owner
  // is actually complaining about; the peak/RMS above only say how far the palm is BENT.
  double dstock_sq = 0.0, dappl_sq = 0.0;
  float dstock_peak = 0.f, dappl_peak = 0.f;
  // Grecharged-foliage-wind3 : l'ETAT BRUT du ressort, AVANT la multiplication par `stiffness`,
  // et sa part de temps passee sur la butee +/-1 (`vector_min_in_place` / `vector_max` dans
  // do_wind_math). `stock_rms` ne pouvait pas repondre a la question « le ressort est-il sature ? »
  // parce qu'il porte deja `stiffness`, qui vaut 0,1 a la plage et 0,25 sur le poisson de
  // Sandover : deux denominateurs dans une meme moyenne. `raw` a le meme sens partout.
  double raw_sq = 0.0;
  float raw_peak = 0.f;
  u64 sat_hits = 0;
  u64 dsamples = 0;
  u64 samples = 0;
  u64 frames = 0;
  u64 last_frame = (u64)-1;
  u64 draws = 0;
  std::chrono::steady_clock::time_point t0 = std::chrono::steady_clock::now();
};

// Grecharged-foliage-wind3 — UN ACCUMULATEUR PAR NIVEAU, ET C'EST UN CORRECTIF D'INSTRUMENT.
// L'accumulateur etait un GLOBAL UNIQUE partage par tous les `Tie3` residents, et son champ
// `level` prenait le nom du DERNIER appelant : a la plage, ou `beach` (stiffness 0,1) et
// `village1` (0,1 ET 0,25) sont residents en meme temps, les lignes `lev=beach` melangeaient les
// deux niveaux. La preuve arithmetique que c'etait faux etait deja dans les journaux du round 3 :
// `stock_peak = 0,152` et `0,177` depassent `sqrt(2) x 0,1 = 0,1414`, ce qui est IMPOSSIBLE pour
// une instance de stiffness 0,1 sous la butee. Toute conversion « shear -> metres » faite sur ces
// lignes portait donc deux hauteurs et deux raideurs a la fois.
static std::unordered_map<std::string, FwAudit>& fw_audits() {
  static std::unordered_map<std::string, FwAudit> s;
  return s;
}

static void fw_audit_accum(const std::string& level,
                           float stock,
                           float applied,
                           bool have_delta,
                           float dstock,
                           float dappl,
                           float raw,
                           bool saturated) {
  FwAudit& a = fw_audits()[level];
  a.level = level;
  a.stock_peak = std::max(a.stock_peak, stock);
  a.appl_peak = std::max(a.appl_peak, applied);
  a.stock_sq += (double)stock * stock;
  a.appl_sq += (double)applied * applied;
  a.raw_peak = std::max(a.raw_peak, raw);
  a.raw_sq += (double)raw * raw;
  if (saturated) {
    a.sat_hits++;
  }
  // Essai 11 : le verdict (1) lit la meme grandeur, tous niveaux et les deux systemes confondus.
  foliage_wind::note_native_sample(raw, saturated);
  a.samples++;
  if (have_delta) {
    a.dstock_peak = std::max(a.dstock_peak, dstock);
    a.dappl_peak = std::max(a.dappl_peak, dappl);
    a.dstock_sq += (double)dstock * dstock;
    a.dappl_sq += (double)dappl * dappl;
    a.dsamples++;
  }
}

static void fw_audit_tick(const std::string& level,
                          u64 frame_idx,
                          bool on,
                          float frond,
                          size_t wind_draws,
                          u32 paused,
                          u32 wind_time,
                          // Grecharged-foliage-wind3 : pas de 1/60 s portes par cette image.
                          // 1 == ce que rend un affichage a 60 images/s, donc la correction de
                          // cadence y est un no-op par construction ; 4 a 15 images/s, et c'est
                          // le facteur par lequel le port faisait tourner la brise de ND LENTE.
                          int rate_ticks) {
  FwAudit& a = fw_audits()[level];
  if (frame_idx != a.last_frame) {
    a.last_frame = frame_idx;
    a.frames++;
  }
  a.draws += wind_draws;
  if (a.frames < 300 || !a.samples) {
    return;
  }
  const double n = (double)a.samples;
  const double dn = (double)std::max<u64>(a.dsamples, 1);
  const double s_rms = std::sqrt(a.stock_sq / n);
  const double a_rms = std::sqrt(a.appl_sq / n);
  const double ds_rms = std::sqrt(a.dstock_sq / dn);
  const double da_rms = std::sqrt(a.dappl_sq / dn);
  const double raw_rms = std::sqrt(a.raw_sq / n);
  const double sat = (double)a.sat_hits / n;
  const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - a.t0).count();
  const double fps = secs > 0.0 ? (double)a.frames / secs : 0.0;
  // BEND (peak/rms) says how far the palm is pushed over. MOTION (dpeak/drms) says how far the
  // shear travels between consecutive frames — a frozen lean scores high on the first and ~0 on
  // the second, and only the second is what an eye can see.
  // Grecharged-foliage-wind3 ajoute les trois grandeurs qui repondent a D1, et elles sont
  // INDEPENDANTES de `stiffness` (donc comparables d'un niveau a l'autre) :
  //   raw_rms  : |vf17| AVANT la multiplication par stiffness. Une brise saine reste bien sous 1.
  //   satfrac  : part des echantillons colles a la butee +/-1. Un arbre fige sur un plein appui.
  //   fps      : la cadence de la fenetre, mesuree ici et pas deduite des horodatages du journal.
  // `dmotion_per_s = dstock_rms * fps` est la grandeur qui doit etre INDEPENDANTE de la cadence
  // quand la brise est une fonction du TEMPS et non des IMAGES : c'est le verdict de D1.
  lg::info(
      "[foliage-wind] shear-audit lev={} on={} rate_ticks={} paused={} wind_time={} frames={} "
      "fps={:.2f} samples={} "
      "wind_draws_submitted={} frond={:.4f} raw_rms={:.4f} raw_peak={:.4f} satfrac={:.4f} "
      "stock_peak={:.6f} stock_rms={:.6f} "
      "applied_peak={:.6f} applied_rms={:.6f} ratio_peak={:.3f} ratio_rms={:.3f} "
      "dstock_peak={:.6f} dstock_rms={:.6f} dapplied_peak={:.6f} dapplied_rms={:.6f} "
      "dratio_peak={:.3f} dratio_rms={:.3f} dmotion_per_s={:.6f}",
      a.level, on ? 1 : 0, rate_ticks, paused, wind_time, a.frames, fps, a.samples,
      a.draws, frond, raw_rms, a.raw_peak, sat, a.stock_peak, s_rms, a.appl_peak, a_rms,
      a.stock_peak > 0.f ? a.appl_peak / a.stock_peak : -1.f,
      s_rms > 0.0 ? a_rms / s_rms : -1.0, a.dstock_peak, ds_rms, a.dappl_peak,
      da_rms, a.dstock_peak > 0.f ? a.dappl_peak / a.dstock_peak : -1.f,
      ds_rms > 0.0 ? da_rms / ds_rms : -1.0, ds_rms * fps);
  a = FwAudit{};
  a.level = level;
}
}  // namespace

Tie3::Tie3(const std::string& name,
           int my_id,
           int level_id,
           const std::vector<GLuint>* anim_slot_array,
           tfrag3::TieCategory category)
    : BucketRenderer(name, my_id),
      m_level_id(level_id),
      m_default_category(category),
      m_anim_slot_array(anim_slot_array) {
  // regardless of how many we use some fixed max
  // we won't actually interp or upload to gpu the unused ones, but we need a fixed maximum so
  // indexing works properly.
  m_color_result.resize(TIME_OF_DAY_COLOR_COUNT);

  m_wind_data.paused = 0;
  math::Vector4f ones(1, 1, 1, 1);
  m_wind_data.wind_normal = ones;
  m_wind_data.wind_temp = ones;
  for (auto& wv : m_wind_data.wind_array) {
    wv = ones;
  }
  for (auto& wf : m_wind_data.wind_force) {
    wf = 1.f;
  }
}

Tie3::~Tie3() {
  discard_tree_cache();
}

void Tie3::init_shaders(ShaderLibrary& shaders) {
  m_uniforms.decal = glu::loc(shaders[ShaderId::TFRAG3].id(), "decal");

  m_etie_uniforms.persp0 = glu::loc(shaders[ShaderId::ETIE].id(), "persp0");
  m_etie_uniforms.persp1 = glu::loc(shaders[ShaderId::ETIE].id(), "persp1");
  m_etie_uniforms.cam_no_persp = glu::loc(shaders[ShaderId::ETIE].id(), "cam_no_persp");
  m_etie_uniforms.envmap_tod_tint =
      glu::loc(shaders[ShaderId::ETIE].id(), "envmap_tod_tint");

  m_etie_base_uniforms.decal = glu::loc(shaders[ShaderId::ETIE_BASE].id(), "decal");
  m_etie_base_uniforms.persp0 = glu::loc(shaders[ShaderId::ETIE_BASE].id(), "persp0");
  m_etie_base_uniforms.persp1 = glu::loc(shaders[ShaderId::ETIE_BASE].id(), "persp1");
  m_etie_base_uniforms.cam_no_persp =
      glu::loc(shaders[ShaderId::ETIE_BASE].id(), "cam_no_persp");
}

/*!
 * Load a TIE tree from FR3 data.
 * This often causes stutters, so as much as possible, we move stuff to the loader,
 * and this function just updates things to reference loader data.
 */
void Tie3::load_from_fr3_data(const LevelData* loader_data) {
  auto ul = scoped_prof("update-load");
  const tfrag3::Level* lev_data = loader_data->level.get();
  // Grecharged-grass-overhang2: resolve the fringe alpha textures the near droop replaces.
  // Grecharged-grass-overhang7: gate widened from "training" to the grass allowlist — the owner
  // plays at Sentinel Beach, which uses the same bch-* textures and now gets the droop/fall tail.
  m_fringe_tex_a = m_fringe_tex_b = -1;
  if (grass_level_enabled(lev_data->level_name)) {
    for (size_t ti = 0; ti < lev_data->textures.size(); ++ti) {
      const auto& tn = lev_data->textures[ti].debug_name;
      if (tn == "bch-grassfringe") {
        m_fringe_tex_a = (s32)ti;
      } else if (tn == "bch-leafyground-hang-2x1") {
        m_fringe_tex_b = (s32)ti;
      }
    }
  }
  m_wind_vectors.clear();

  // We changed level! free opengl resources allocated for the previous
  discard_tree_cache();

  // resize for the number of trees in this level.
  for (int geo = 0; geo < 4; ++geo) {
    m_trees[geo].resize(lev_data->tie_trees[geo].size());
  }

  u16 max_wind_idx = 0;
  // loop over all "geos" (level of details)
  for (u32 l_geo = 0; l_geo < tfrag3::TIE_GEOS; l_geo++) {
    // loop over all trees
    for (u32 l_tree = 0; l_tree < lev_data->tie_trees[l_geo].size(); l_tree++) {
      auto ul = scoped_prof("load-tree");
      size_t wind_idx_buffer_len = 0;
      size_t num_grps = 0;
      const auto& tree = lev_data->tie_trees[l_geo][l_tree];

      // compute maximum number of vis groups (leaf in the bvh)
      for (auto& draw : tree.static_draws) {
        num_grps += draw.vis_groups.size();
      }

      // compute wind buffer sizes
      for (auto& draw : tree.instanced_wind_draws) {
        wind_idx_buffer_len += draw.vertex_index_stream.size();
      }
      for (auto& inst : tree.wind_instance_info) {
        max_wind_idx = std::max(max_wind_idx, inst.wind_idx);
      }

      // vertex buffer max
      auto& lod_tree = m_trees.at(l_geo);

      // set up resources: create a VAO
      glGenVertexArrays(1, &lod_tree[l_tree].vao);
      glBindVertexArray(lod_tree[l_tree].vao);
      // openGL vertex buffer from loader
      lod_tree[l_tree].vertex_buffer = loader_data->tie_data[l_geo][l_tree].vertex_buffer;
      lod_tree[l_tree].contact_texture = loader_data->tie_data[l_geo][l_tree].contact_texture;
      const auto& contact_data = loader_data->tie_data[l_geo][l_tree];
      contact_mapping_failures.fetch_add(!contact_data.contact_mapping_ok, std::memory_order_relaxed);
      if (contact_data.contact_texture) {
        contact_mapped_trees.fetch_add(1, std::memory_order_relaxed);
        contact_eligible_instances.fetch_add(contact_data.contact_instances, std::memory_order_relaxed);
        contact_eligible_vertices.fetch_add(contact_data.contact_vertices, std::memory_order_relaxed);
      }
      const GLuint contact_buffer = contact_data.contact_buffer;
      if (contact_buffer) {
        glBindBuffer(GL_ARRAY_BUFFER, contact_buffer);
        glEnableVertexAttribArray(10);
        glVertexAttribIPointer(10, 1, GL_UNSIGNED_INT, sizeof(u32), nullptr);
      }
      // draw array from FR3 data
      lod_tree[l_tree].draws = &tree.static_draws;
      // base TOD colors from FR3
      lod_tree[l_tree].colors = &tree.colors;
      // visibility BVH from FR3
      lod_tree[l_tree].vis = &tree.bvh;
      // indices from FR3 (needed on CPU for culling)
      lod_tree[l_tree].index_data = tree.unpacked.indices.data();
      // wind metadata
      lod_tree[l_tree].instance_info = &tree.wind_instance_info;
      lod_tree[l_tree].wind_draws = &tree.instanced_wind_draws;
      // Grecharged-foliage-wind: one-shot census so a device log can PROVE whether this level's
      // TIE protos are wind-enabled (stiffness != 0 => instances here). If instances == 0 the
      // wind pass early-returns and the sway boost is a silent no-op — this line makes that
      // failure mode visible instead of invisible.
      if (l_geo == 0) {
        // Grecharged-foliage-wind2: the census now also reports the authored STIFFNESS spread and
        // the static-draw count. That is the whole round-1 post-mortem in one line: the stock shear
        // is stiffness * (drive/100), so a tiny max stiffness proves arithmetically why multiplying
        // it could never be visible — and static_draws vs wind_draws shows how much of the level's
        // TIE geometry is baked static (no per-instance matrix at all => unreachable from here).
        float st_min = 0.f, st_max = 0.f, st_sum = 0.f;
        bool st_first = true;
        for (const auto& wi : tree.wind_instance_info) {
          if (st_first) {
            st_min = st_max = wi.stiffness;
            st_first = false;
          } else {
            st_min = std::min(st_min, wi.stiffness);
            st_max = std::max(st_max, wi.stiffness);
          }
          st_sum += wi.stiffness;
        }
        const float st_mean =
            tree.wind_instance_info.empty() ? 0.f : st_sum / (float)tree.wind_instance_info.size();
        lg::info(
            "[foliage-wind] TIE census lev={} tree={} wind_draws={} wind_instances={} "
            "static_draws={} stiffness_min={} stiffness_max={} stiffness_mean={}",
            lev_data->level_name, l_tree, tree.instanced_wind_draws.size(),
            tree.wind_instance_info.size(), tree.static_draws.size(), st_min, st_max, st_mean);
      }
      // ----------------------------------------------------------------------------------------
      // Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas
      // impactés ») — LA LIGNE QUI PORTE LE VERDICT DE D2, une par arbre TIE et par LOD.
      //
      // Elle est imprimee ICI et pas dans `TieTree::unpack()` parce que c'est le seul endroit ou
      // le NOM DU NIVEAU existe ; les compteurs, eux, ne peuvent etre calcules que dans `unpack()`
      // (apres, les sommets CPU sont rendus — Loader.cpp:1550-1553) et ils y survivent parce que
      // ce ne sont que des entiers.
      //
      // POURQUOI `proto_names_size` EST SUR CETTE LIGNE : les fr3 « enhanced » HD
      // (out/jak1/fr3/enhanced/, dont village1) sortent d'une chaine SEPAREE
      // (scripts/shell/build_enhanced_models.sh). S'ils ne sont pas regeneres, Loader.cpp:358-371
      // les fait GAGNER quand le basculement HD est actif, et le niveau chargerait un fr3 SANS
      // `proto_names` : zero balancement, en silence, exactement le symptome que l'owner decrit.
      // `proto_names_size=0` rend ce cas VISIBLE au lieu de le laisser passer pour un defaut de
      // rendu.
      //
      // POURQUOI LES NOMS NON CLASSES SONT PUBLIES : sans eux, retirer une ligne du lexique
      // retrecirait le denominateur en silence et la couverture monterait toute seule.
      {
        const auto& c = tree.sway_census;
        std::string noms;
        for (size_t ni = 0; ni < c.noms_non_classes.size(); ni++) {
          if (ni) {
            noms += ",";
          }
          noms += c.noms_non_classes[ni];
        }
        if (c.non_classes > c.noms_non_classes.size()) {
          noms += fmt::format(",+{}", c.non_classes - c.noms_non_classes.size());
        }
        lg::info(
            "[foliage-wind] TIE sway-cover lev={} tree={} geo={} lexique={} proto_names_size={} "
            "protos={} veg_protos={} non_classes={} inst_total={} inst_veg={} inst_swayed={} "
            "verts={} v_sway={} v_neutre={} v_windpath={} v_sansproto={} vconflit={} "
            "vg_desync={} plain_inds={} noms_non_classes={}",
            lev_data->level_name, l_tree, l_geo, c.lexicon_loaded ? 1 : 0, tree.proto_names.size(),
            c.protos, c.veg_protos, c.non_classes, c.inst_total, c.inst_veg, c.inst_swayed,
            c.verts, c.v_sway, c.v_neutre, c.v_windpath, c.v_sansproto, c.v_conflit, c.vg_desync,
            c.plain_inds, noms.empty() ? "-" : noms);
        foliage_wind::note_unclassified(lev_data->level_name, l_tree, c.non_classes);
      }
      // foliage-wind (owner 2026-09-03) : LA POPULATION DU RECENSEMENT, les deux chemins TIE.
      //   * chemin STATIQUE : une entree par instance vegetale posee, poids de couronne = celui que
      //     le VBO d'attribut 7 porte reellement ;
      //   * chemin VENT : une entree par instance animee par ND, poids de couronne = le facteur de
      //     taille que le CPU multipliera (la meme table que le depaqueteur).
      // `wind_inst_local_ymax` reste pointe pour le rendu : c'est lui qui convertit la flexion de
      // couronne en cisaillement d'instance.
      lod_tree[l_tree].wind_local_ymax = &tree.wind_inst_local_ymax;
      lod_tree[l_tree].wind_local_rmin = &tree.wind_inst_local_rmin;
      lod_tree[l_tree].wind_local_rspan = &tree.wind_inst_local_rspan;
      lod_tree[l_tree].wind_local_wmax = &tree.wind_inst_local_wmax;
      lod_tree[l_tree].fw_inst_flutter_amp.assign(tree.wind_instance_info.size(), 0.f);
      {
        std::vector<foliage_wind::Instance> pop;
        pop.reserve(tree.sway_instances.size());
        for (const auto& si : tree.sway_instances) {
          if (!si.valid) {
            continue;
          }
          foliage_wind::Instance in;
          in.anchor_x = si.x;
          in.anchor_z = si.z;
          in.height_m = (si.ymax - si.base_y) / 4096.f;
          in.peak_w = si.peak_w;
          in.low_w = si.low_w;
          in.base_w = si.base_w;
          in.att_w = si.att_w;
          in.tip_w = si.tip_w;
          in.shrub = false;
          pop.push_back(in);
        }
        foliage_wind::set_tree(lev_data->level_name, foliage_wind::kSystemTieStatic, (int)l_tree,
                               (int)l_geo, std::move(pop));
        std::vector<foliage_wind::Instance> wpop;
        wpop.reserve(tree.wind_instance_info.size());
        for (size_t wi = 0; wi < tree.wind_instance_info.size(); wi++) {
          const auto& m = tree.wind_instance_info[wi].matrix;
          const float ys = std::sqrt(m[1].x() * m[1].x() + m[1].y() * m[1].y() + m[1].z() * m[1].z());
          const float h_loc = wi < tree.wind_inst_local_ymax.size() ? tree.wind_inst_local_ymax[wi] : 0.f;
          foliage_wind::Instance in;
          in.anchor_x = m[3].x();
          in.anchor_z = m[3].z();
          in.height_m = h_loc * ys / 4096.f;
          in.peak_w = in.height_m > 0.f ? foliage_law::size_factor(in.height_m) : 0.f;
          // le chemin vent applique la flexion ajoutee par le poids de hauteur de tie_wind.vert
          // (nul sous 30 % de la plante) : ses 10 % du bas ne recoivent rien de la brise
          in.low_w = 0.f;
          in.base_w = 0.f;
          // ESSAI 16 : les moyennes de bande de `q` calculees au depaquetage sur la MEME forme que
          // le shader evalue (hauteur x rampe d'extremite), ramenees a l'echelle du poids ecrit.
          in.att_w = wi < tree.wind_inst_att_w.size() ? tree.wind_inst_att_w[wi] : -1.f;
          in.tip_w = wi < tree.wind_inst_tip_w.size() ? tree.wind_inst_tip_w[wi] : -1.f;
          in.shrub = false;
          wpop.push_back(in);
        }
        foliage_wind::set_tree(lev_data->level_name, foliage_wind::kSystemTieWind, (int)l_tree,
                               (int)l_geo, std::move(wpop));
      }
      // OpenGL index buffer (fixed index buffer for multidraw system)
      lod_tree[l_tree].index_buffer = loader_data->tie_data[l_geo][l_tree].index_buffer;
      lod_tree[l_tree].category_draw_indices = tree.category_draw_indices;
      lod_tree[l_tree].draw_mode = tree.use_strips ? GL_TRIANGLE_STRIP : GL_TRIANGLES;
#ifdef OG_FEAT_PBR
      // New level data invalidates the cached full-caster ranges (round-5 shadow fix).
      lod_tree[l_tree].pbr_full_ranges.clear();
      lod_tree[l_tree].pbr_full_ranges_built = false;
      // lighting-ao-indirect (terme 3, defaut D) : LES DEUX AUTRES JEUX AUSSI. L'objet `Tree`
      // est REUTILISE d'un niveau a l'autre (la ligne ci-dessus lui reassigne un NOUVEAU
      // `index_buffer`) : un drapeau `built` laisse a vrai fige des offsets d'indices qui
      // appartiennent a un AUTRE tampon, et `ensure_tie_full_ranges` retourne immediatement
      // (:1115-1117) sans jamais reconstruire. La prepasse dessinait alors les mauvais triangles
      // pour les TIE envmappes apres un echange de niveau. `prepass_ranges*` et
      // `prepass_noz_ranges*` n'ont PAS besoin d'etre effaces ici : `ensure_tie_full_ranges` les
      // vide lui-meme des qu'il reconstruit.
      lod_tree[l_tree].pbr_full_ranges_env.clear();
      lod_tree[l_tree].pbr_full_ranges_env_built = false;
      lod_tree[l_tree].pbr_full_ranges_env2.clear();
      lod_tree[l_tree].pbr_full_ranges_env2_built = false;
#endif

      // set up vertex attributes
      glBindBuffer(GL_ARRAY_BUFFER, lod_tree[l_tree].vertex_buffer);
      glEnableVertexAttribArray(0);
      glEnableVertexAttribArray(1);
      glEnableVertexAttribArray(2);
      glEnableVertexAttribArray(3);
      glEnableVertexAttribArray(4);

      glVertexAttribPointer(0,                                           // location 0 in the shader
                            3,                                           // 3 values per vert
                            GL_FLOAT,                                    // floats
                            GL_FALSE,                                    // normalized
                            sizeof(tfrag3::PreloadedVertex),             // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, x)  // offset (0)
      );

      glVertexAttribPointer(1,                                           // location 1 in the shader
                            3,                                           // 3 values per vert
                            GL_FLOAT,                                    // floats
                            GL_FALSE,                                    // normalized
                            sizeof(tfrag3::PreloadedVertex),             // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, s)  // offset (0)
      );

      glVertexAttribIPointer(2,                                // location 2 in the shader
                             2,                                // 1 values per vert
                             GL_UNSIGNED_SHORT,                // u16
                             sizeof(tfrag3::PreloadedVertex),  // stride
                             (void*)offsetof(tfrag3::PreloadedVertex, color_index)  // offset (0)
      );

      glVertexAttribPointer(3,                                // location 1 in the shader
                            4,                                // 3 values per vert
                            GL_INT_2_10_10_10_REV,            // floats
                            GL_TRUE,                          // normalized
                            sizeof(tfrag3::PreloadedVertex),  // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, nor)  // offset (0)
      );

      glVertexAttribPointer(4,                                           // location 1 in the shader
                            4,                                           // 3 values per vert
                            GL_UNSIGNED_BYTE,                            // floats
                            GL_TRUE,                                     // normalized
                            sizeof(tfrag3::PreloadedVertex),             // stride
                            (void*)offsetof(tfrag3::PreloadedVertex, r)  // offset (0)
      );

      // Grecharged-mesh-consolidation: per-vertex SEAM WEIGHT (1 = displace normally, 0 = do not
      // displace). mesh_consolidate() zeroes it at boundaries whose two sides cannot displace
      // identically, so the tessellation evaluation shader can fade displacement to exactly zero
      // along a shared edge on BOTH sides — that is what closes the see-through slits.
      glEnableVertexAttribArray(6);
      glVertexAttribPointer(6, 1, GL_UNSIGNED_SHORT, GL_TRUE, sizeof(tfrag3::PreloadedVertex),
                            (void*)offsetof(tfrag3::PreloadedVertex, seam_w));

      // lighting-legacy-purge (essai 8) : la TANGENTE par sommet (ancienne location 5) n'est plus
      // liee — plus aucun `.vert` ne declare cet attribut.

      // Grecharged-foliage-wind3 (defaut D2) : poids + phase de balancement, DEUX octets par
      // sommet, sur la LOCATION 7. Elle est libre et c'est verifie et non suppose : les shaders de
      // cet arbre declarent 0,1,2,3,4,5 (`grep "location = 7" shaders/*.vert` rendait ZERO avant
      // ce chunk), le VAO TIE ci-dessus active 0..6, et le VAO TFRAG (TFragment.cpp:443-494)
      // n'active ni 4 ni 7. Normalise : l'octet 0..255 arrive dans le shader en 0..1.
      // Essai 11 : SwayRecord de 8 octets (FoliageWindLaw.h) — 7 = poids SIGNE (GL_SHORT normalise),
      // 8 = phase (GL_UNSIGNED_BYTE normalise). L'attribut 9 (index d'instance) n'est lu que par shrub.
      glBindBuffer(GL_ARRAY_BUFFER, loader_data->tie_data[l_geo][l_tree].sway_buffer);
      glEnableVertexAttribArray(7);
      glVertexAttribPointer(7, 1, GL_SHORT, GL_TRUE, (GLsizei)foliage_law::kSwayRecordBytes,
                            (void*)offsetof(foliage_law::SwayRecord, w));
      glEnableVertexAttribArray(8);
      glVertexAttribPointer(8, 1, GL_UNSIGNED_BYTE, GL_TRUE, (GLsizei)foliage_law::kSwayRecordBytes,
                            (void*)offsetof(foliage_law::SwayRecord, ph));

      // allocate dynamic index buffer for the fallback "not multidraw" mode.
      glGenBuffers(1, &lod_tree[l_tree].single_draw_index_buffer);

      // set up wind
      if (wind_idx_buffer_len > 0) {
        lod_tree[l_tree].wind_matrix_cache.resize(tree.wind_instance_info.size());
        // Grecharged-foliage-wind2: 4 floats per instance for the motion half of the shear audit.
        lod_tree[l_tree].fw_prev_shear.assign(tree.wind_instance_info.size() * 4, 0.f);
        lod_tree[l_tree].fw_prev_valid = false;
        lod_tree[l_tree].wind_vertex_index_buffer =
            loader_data->tie_data[l_geo][l_tree].wind_indices;
        u32 off = 0;
        for (auto& draw : tree.instanced_wind_draws) {
          lod_tree[l_tree].wind_vertex_index_offsets.push_back(off);
          off += draw.vertex_index_stream.size();
        }
      }

      // set up per-proto visibility. Jak 2 needs to enable/disable individual protos.
      lod_tree[l_tree].has_proto_visibility = tree.has_per_proto_visibility_toggle;
      if (tree.has_per_proto_visibility_toggle) {
        lod_tree[l_tree].proto_visibility.init(tree.proto_names);
      }

      // set up time of day texture.
      // A36: Wx1 2D LUT instead of 1D. The non-envmap TIE draws share the
      // TFRAG3 shader (see draw_matching_draws_for_tree), and tfrag3.vert was
      // converted to `sampler2D tex_T10` with texelFetch(ivec2(i,0)). Sampling
      // a sampler2D from a unit that only has a 1D texture bound returns black,
      // which made every non-envmap TIE structure render as a black silhouette.
      // Match TFragment.cpp's Wx1 GL_TEXTURE_2D upload so the shared shader
      // reads real colors. (Also unblocks GLES, which has no glTexImage1D.)
      glActiveTexture(GL_TEXTURE10);
      glGenTextures(1, &lod_tree[l_tree].time_of_day_texture);
      glBindTexture(GL_TEXTURE_2D, lod_tree[l_tree].time_of_day_texture);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, nullptr);
      // hdr-plan : recensement des entrees 8 bits du chemin de scene. N'a aucun effet sur le rendu.
      hdr::note_input_source_indexed("tod-palette-tie", 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

      // Gperf-particles round 3: second (ping-pong) TOD texture, identical.
      glGenTextures(1, &lod_tree[l_tree].time_of_day_texture_pp);
      glBindTexture(GL_TEXTURE_2D, lod_tree[l_tree].time_of_day_texture_pp);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, nullptr);
      // hdr-plan : recensement des entrees 8 bits du chemin de scene. N'a aucun effet sur le rendu.
      hdr::note_input_source_indexed("tod-palette-tie", 1, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      lod_tree[l_tree].tod_flip = 0;
      lod_tree[l_tree].tod_current = lod_tree[l_tree].time_of_day_texture;
      lod_tree[l_tree].tod_cache_valid = false;  // Gperf-particles: fresh level re-interpolates

      glBindVertexArray(0);

      lod_tree[l_tree].vis_temp.resize(tree.bvh.vis_nodes.size());

      lod_tree[l_tree].draw_idx_temp.resize(tree.static_draws.size());
      lod_tree[l_tree].index_temp.resize(tree.unpacked.indices.size());
      lod_tree[l_tree].multidraw_offset_per_stripdraw.resize(tree.static_draws.size());
      lod_tree[l_tree].multidraw_count_buffer.resize(num_grps);
      lod_tree[l_tree].multidraw_index_offset_buffer.resize(num_grps);
    }
  }

  // set up temporary caches. These are just temporary, so they don't need per-tree versions.

  m_wind_vectors.resize(4 * max_wind_idx + 4);  // 4x u32's per wind.

  // ASSERT(time_of_day_count <= TIME_OF_DAY_COLOR_COUNT);
}

/*!
 * Try loading a level. Hopefully it has been preloaded and this is fast.
 */
bool Tie3::try_loading_level(const std::string& level, SharedRenderState* render_state) {
  // make sure we have the level data.
  Timer tfrag3_setup_timer;
  auto lev_data = render_state->loader->get_tfrag3_level(level);

  if (!lev_data) {
    // not loaded
    m_has_level = false;
    m_textures = nullptr;
    foliage_wind::forget(m_level_name, foliage_wind::kSystemTieStatic);
    foliage_wind::forget(m_level_name, foliage_wind::kSystemTieWind);
    m_level_name = "";
    discard_tree_cache();
    return false;
  }

  if (m_has_level && lev_data->load_id != m_load_id) {
    m_has_level = false;
    m_textures = nullptr;
    foliage_wind::forget(m_level_name, foliage_wind::kSystemTieStatic);
    foliage_wind::forget(m_level_name, foliage_wind::kSystemTieWind);
    m_level_name = "";
    discard_tree_cache();
    return try_loading_level(level, render_state);
  }

  // loading was successful. Link textures/load ID.
  m_textures = &lev_data->textures;
  m_load_id = lev_data->load_id;

  // see if this is the first time we've gotten the level
  if (m_level_name != level) {
    // it is! do the one time load.
    // foliage-wind : le niveau que ce renderer lachait sort de la population du recensement.
    foliage_wind::forget(m_level_name, foliage_wind::kSystemTieStatic);
    foliage_wind::forget(m_level_name, foliage_wind::kSystemTieWind);
    load_from_fr3_data(lev_data);
    m_has_level = true;
    m_level_name = level;
  } else {
    m_has_level = true;
  }

  if (tfrag3_setup_timer.getMs() > 5) {
    lg::info("TIE setup: {:.1f}ms", tfrag3_setup_timer.getMs());
  }

  return m_has_level;
}

void Tie3::discard_tree_cache() {
  for (int geo = 0; geo < 4; ++geo) {
    for (auto& tree : m_trees[geo]) {
      glBindTexture(GL_TEXTURE_2D, tree.time_of_day_texture);
#ifdef __ANDROID__
      fprintf(stderr, "F1E-DELTEX site=tie-tod tex=%u\n", (unsigned)tree.time_of_day_texture);
#endif
      glDeleteTextures(1, &tree.time_of_day_texture);
      // Gperf-particles round 3: delete the ping-pong TOD texture too.
      glDeleteTextures(1, &tree.time_of_day_texture_pp);
      // glDeleteBuffers(1, &tree.index_buffer);
      glDeleteBuffers(1, &tree.single_draw_index_buffer);
      glDeleteVertexArrays(1, &tree.vao);
    }

    m_trees[geo].clear();
  }
}

bool Tie3::set_up_common_data_from_dma(DmaFollower& dma, SharedRenderState* render_state) {
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0 || data0.vifcode1().kind == VifCode::Kind::NOP);
  ASSERT(data0.vif0() == 0 || data0.vifcode0().kind == VifCode::Kind::NOP ||
         data0.vifcode0().kind == VifCode::Kind::MARK);
  ASSERT(data0.size_bytes == 0);

  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return false;
  }

  if (dma.current_tag_offset() == render_state->next_bucket) {
    return false;
  }

  auto gs_test = dma.read_and_advance();
  if (gs_test.size_bytes == 160) {
  } else {
    ASSERT(gs_test.size_bytes == 32);

    auto tie_consts = dma.read_and_advance();
    ASSERT(tie_consts.size_bytes == 9 * 16);
  }

  auto mscalf = dma.read_and_advance();
  ASSERT(mscalf.size_bytes == 0);

  auto row = dma.read_and_advance();
  ASSERT(row.size_bytes == 32);

  auto next = dma.read_and_advance();
  if (next.size_bytes == 32) {
    next = dma.read_and_advance();
  }
  ASSERT(next.size_bytes == 0);

  auto pc_port_data = dma.read_and_advance();
  ASSERT(pc_port_data.size_bytes == sizeof(TfragPcPortData));
  memcpy(&m_pc_port_data, pc_port_data.data, sizeof(TfragPcPortData));
  m_pc_port_data.level_name[11] = '\0';

  if (render_state->version == GameVersion::Jak1) {
    auto wind_data = dma.read_and_advance();
    ASSERT(wind_data.size_bytes == sizeof(WindWork));
    memcpy(&m_wind_data, wind_data.data, sizeof(WindWork));
  }

  if (render_state->version >= GameVersion::Jak2) {
    // jak 2 proto visibility
    auto proto_mask_data = dma.read_and_advance();
    m_common_data.proto_vis_data = proto_mask_data.data;
    m_common_data.proto_vis_data_size = proto_mask_data.size_bytes;
  }

  // envmap color
  auto envmap_color = dma.read_and_advance();
  ASSERT(envmap_color.size_bytes == 16);
  memcpy(m_common_data.envmap_color.data(), envmap_color.data, 16);
  m_common_data.envmap_color /= 128.f;
  if (render_state->version == GameVersion::Jak1) {
    m_common_data.envmap_color *= 2;
  }
  m_common_data.envmap_color *= m_envmap_strength;

  m_common_data.frame_idx = render_state->frame_idx;

  while (dma.current_tag_offset() != render_state->next_bucket) {
    dma.read_and_advance();
  }

  m_common_data.settings.camera = m_pc_port_data.camera;

  m_common_data.settings.tree_idx = 0;

  if (render_state->occlusion_vis[m_level_id].valid) {
    m_common_data.settings.occlusion_culling = render_state->occlusion_vis[m_level_id].data;
  } else {
    m_common_data.settings.occlusion_culling = 0;
  }

  update_render_state_from_pc_settings(render_state, m_pc_port_data);

  m_has_level = try_loading_level(m_pc_port_data.level_name, render_state);
  return true;
}
/*!
 * Render method called from bucket render system.
 * Does common setup for all category, but only renderers default_category.
 */
void Tie3::render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) {
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  if (set_up_common_data_from_dma(dma, render_state)) {
    // foliage-wind : l'etat du vent du JEU (cap, pause), recopie pour les quatre programmes, et
    // l'image comptee pour le recensement (une seule fois par frame_idx, quel que soit le renderer).
    foliage_wind::set_wind_state(m_wind_data.wind_normal.x(), m_wind_data.wind_normal.z(),
                                 m_wind_data.paused != 0);
    // Essai 11 : la copie du vent du JEU pour le verdict (1) — slots de l'anneau, cadence.
    foliage_wind::note_game_wind(m_wind_data.wind_force, m_wind_data.wind_time,
                                 m_wind_data.paused != 0, render_state->frame_idx);
    foliage_wind::set_game_wind_copy(&m_wind_data, sizeof(m_wind_data));
    foliage_wind::frame(render_state->frame_idx);
    // Gperf-particles: attribute per-tree TOD/cull/index-build setup vs draw
    // submission separately so A35-PERF can steer the batching work (mirrors
    // TFragment's "t3" child idiom).
    {
      auto setup_prof = prof.make_scoped_child("setup");
      setup_all_trees(lod(), m_common_data.settings, m_common_data.proto_vis_data,
                      m_common_data.proto_vis_data_size, !render_state->no_multidraw,
                      render_state->perf_tod_pingpong, render_state->perf_tod_skip, setup_prof);
    }

    {
      auto draws_prof = prof.make_scoped_child("draws");
      draw_matching_draws_for_all_trees(lod(), m_common_data.settings, render_state, draws_prof,
                                        m_default_category);
    }
  }
}

void Tie3::render_from_another(SharedRenderState* render_state,
                               ScopedProfilerNode& prof,
                               tfrag3::TieCategory category) {
  if (render_state->frame_idx != m_common_data.frame_idx) {
    return;
  }
  draw_matching_draws_for_all_trees(lod(), m_common_data.settings, render_state, prof, category);
}

void Tie3::draw_matching_draws_for_all_trees(int geom,
                                             const TfragRenderSettings& settings,
                                             SharedRenderState* render_state,
                                             ScopedProfilerNode& prof,
                                             tfrag3::TieCategory category) {
  for (u32 i = 0; i < m_trees[geom].size(); i++) {
    draw_matching_draws_for_tree(i, geom, settings, render_state, prof, category);
  }
}

void Tie3::setup_all_trees(int geom,
                           const TfragRenderSettings& settings,
                           const u8* proto_vis_data,
                           size_t proto_vis_data_size,
                           bool use_multidraw,
                           bool tod_pingpong,
                           bool tod_skip,
                           ScopedProfilerNode& prof) {
  for (u32 i = 0; i < m_trees[geom].size(); i++) {
    setup_tree(i, geom, settings, proto_vis_data, proto_vis_data_size, use_multidraw, tod_pingpong,
               tod_skip, prof);
  }
}

void Tie3::setup_tree(int idx,
                      int geom,
                      const TfragRenderSettings& settings,
                      const u8* proto_vis_data,
                      size_t proto_vis_data_size,
                      bool use_multidraw,
                      bool tod_pingpong,
                      bool tod_skip,
                      ScopedProfilerNode& prof) {
  // reset perf
  auto& tree = m_trees.at(geom).at(idx);
  // don't render if we haven't loaded
  if (!m_has_level) {
    return;
  }

  // update time of day
  if (m_color_result.size() < tree.colors->color_count) {
    m_color_result.resize(tree.colors->color_count);
  }

  {
    // Gperf-particles: memoize the TOD interp+upload — when itimes is unchanged
    // vs the last cached value, tod_current already holds the correct palette,
    // so skip both the interpolation and the glTexSubImage2D upload (night
    // hot-path). Behind the perf_tod_skip kill switch; result is byte-identical.
    bool tod_same = tree.tod_cache_valid &&
        memcmp(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32)) == 0;
    if (tod_skip && tod_same) {
      // Gperf-particles: itimes unchanged -> skip interp + palette upload;
      // tod_current retains last frame's palette (byte-identical result).
    } else {
      {
        // Gperf-particles: time-of-day color interpolation (per-tree, accumulate).
        SpartScopedNs _interp(g_spart_prof.tie_interp);
        interp_time_of_day(settings.camera.itimes, *tree.colors, m_color_result.data());
      }

      {
        // Gperf-particles: time-of-day texture upload (bind pair + sub-image).
        // Round 3: ping-pong the target texture (flag ON) so the upload does not
        // touch the texture last frame's draws are still sampling on Adreno, then
        // publish it via tod_current so every later bind uses the same texture.
        // Flag OFF => tod_current == time_of_day_texture (byte-identical old path).
        SpartScopedNs _texsub(g_spart_prof.tie_texsub);
        if (tod_pingpong) {
          tree.tod_flip ^= 1;
          tree.tod_current = tree.tod_flip ? tree.time_of_day_texture_pp : tree.time_of_day_texture;
        } else {
          tree.tod_current = tree.time_of_day_texture;
        }
        glActiveTexture(GL_TEXTURE10);
        glBindTexture(GL_TEXTURE_2D, tree.tod_current);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tree.colors->color_count, 1, GL_RGBA,
                        GL_UNSIGNED_BYTE, m_color_result.data());
      }
      memcpy(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32));
      tree.tod_cache_valid = true;
    }
  }

  // update proto vis mask
  if (proto_vis_data) {
    tree.proto_visibility.update(proto_vis_data, proto_vis_data_size);
  }

  if (!m_debug_all_visible) {
    // Gperf-particles: slow (per-node) frustum/occlusion cull check.
    SpartScopedNs _cull(g_spart_prof.tie_cull);
    // need culling data
    cull_check_all_slow(settings.camera.planes, tree.vis->vis_nodes, settings.occlusion_culling,
                        tree.vis_temp.data());
  }

  // Gperf-particles: index-list build + index-buffer upload (per-tree).
  SpartScopedNs _index(g_spart_prof.tie_index);
  u32 num_tris = 0;
  if (use_multidraw) {
    if (m_debug_all_visible) {
      num_tris = make_all_visible_multidraws(
          tree.multidraw_offset_per_stripdraw.data(), tree.multidraw_count_buffer.data(),
          tree.multidraw_index_offset_buffer.data(), *tree.draws);
    } else {
      Timer index_timer;
      if (tree.has_proto_visibility) {
        num_tris = make_multidraws_from_vis_and_proto_string(
            tree.multidraw_offset_per_stripdraw.data(), tree.multidraw_count_buffer.data(),
            tree.multidraw_index_offset_buffer.data(), *tree.draws, tree.vis_temp,
            tree.proto_visibility.vis_flags);
      } else {
        num_tris = make_multidraws_from_vis_string(
            tree.multidraw_offset_per_stripdraw.data(), tree.multidraw_count_buffer.data(),
            tree.multidraw_index_offset_buffer.data(), *tree.draws, tree.vis_temp);
      }
    }
  } else {
    u32 idx_buffer_size;
    if (m_debug_all_visible) {
      idx_buffer_size =
          make_all_visible_index_list(tree.draw_idx_temp.data(), tree.index_temp.data(),
                                      *tree.draws, tree.index_data, &num_tris);
    } else {
      if (tree.has_proto_visibility) {
        idx_buffer_size = make_index_list_from_vis_and_proto_string(
            tree.draw_idx_temp.data(), tree.index_temp.data(), *tree.draws, tree.vis_temp,
            tree.proto_visibility.vis_flags, tree.index_data, &num_tris);
      } else {
        idx_buffer_size =
            make_index_list_from_vis_string(tree.draw_idx_temp.data(), tree.index_temp.data(),
                                            *tree.draws, tree.vis_temp, tree.index_data, &num_tris);
      }
    }

    if (ao_contact_draws::active(m_level_name)) {
      ao_contact_draws::compact(tree.contact_source_offsets, tree.index_temp.size(),
          tree.draw_idx_temp, idx_buffer_size, [&](auto* ranges, auto* out, const auto* source) {
            u32 tris = 0;
            if (m_debug_all_visible)
              return make_all_visible_index_list(ranges, out, *tree.draws, source, &tris);
            if (tree.has_proto_visibility)
              return make_index_list_from_vis_and_proto_string(ranges, out, *tree.draws,
                  tree.vis_temp, tree.proto_visibility.vis_flags, source, &tris);
            return make_index_list_from_vis_string(ranges, out, *tree.draws, tree.vis_temp,
                                                   source, &tris);
          });
    }
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.single_draw_index_buffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_buffer_size * sizeof(u32), tree.index_temp.data(),
                 GL_STREAM_DRAW);
  }

  prof.add_tri(num_tris);
}

namespace {
void set_uniform(GLuint uniform, const math::Vector4f& val) {
  glUniform4f(uniform, val.x(), val.y(), val.z(), val.w());
}
}  // namespace

void init_etie_cam_uniforms(const EtieUniforms& uniforms, const GoalBackgroundCameraData& data) {
  glUniformMatrix4fv(uniforms.cam_no_persp, 1, GL_FALSE, data.rot[0].data());

  math::Vector4f perspective[2];
  float inv_fog = 1.f / data.fog[0];
  auto& hvdf_off = data.hvdf_off;
  float pxx = data.perspective[0].x();
  float pyy = data.perspective[1].y();
  float pzz = data.perspective[2].z();
  float pzw = data.perspective[2].w();
  float pwz = data.perspective[3].z();
  float scale = pzw * inv_fog;
  perspective[0].x() = scale * hvdf_off.x();
  perspective[0].y() = scale * hvdf_off.y();
  perspective[0].z() = scale * hvdf_off.z() + pzz;
  perspective[0].w() = scale;

  perspective[1].x() = pxx;
  perspective[1].y() = pyy;
  perspective[1].z() = pwz;
  perspective[1].w() = 0;

  set_uniform(uniforms.persp0, perspective[0]);
  set_uniform(uniforms.persp1, perspective[1]);
}

// =================================================================================================
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas impactés »)
// LE BALANCEMENT DU TIE **STATIQUE** — pose des uniformes.
//
// Le chemin VENT (`render_tree_wind`) ne touche QUE les instances que l'extracteur a basculees en
// `instanced_wind_draws`, c'est-a-dire celles dont le prototype porte une raideur non nulle. Tout
// le reste de la vegetation TIE est de la geometrie STATIQUE fondue dans un seul maillage, sans
// matrice d'instance a l'execution : aucun bouton de ce fichier ne pouvait la faire bouger. C'est
// ca, « tous les arbres ne sont pas impactés », et c'est ce chemin-ci qui le ferme.
//
// OFF == STOCK, ET C'EST LA SEULE CHOSE QUE CETTE FONCTION GARANTIT : quand l'option est eteinte
// elle ecrit 0, le `if` du chunk saute le bloc et le sommet ressort a l'identique. Elle n'ecrit
// RIEN d'autre sur le chemin statique.
static void push_tie_contact(GLuint program, GLuint texture) {
  const bool on = texture && foliage_wind::enabled();
  glUniform1i(glu::loc(program, "u_tie_contact_on"), on ? 1 : 0);
  if (on) {
    const bool bound = grass_occ::push_contact_uniforms(program, true);
    const GLint sampler = glu::loc(program, "u_tie_contact_tex");
    glUniform1i(sampler, 18);
    glActiveTexture(GL_TEXTURE18);
    glBindTexture(GL_TEXTURE_2D, texture);
    glActiveTexture(GL_TEXTURE0);
    if (bound && sampler >= 0 && glu::loc(program, "u_tie_contact_on") >= 0) {
      const auto sources = grass_occ::contact_sources(true);
      contact_jak_samples.fetch_add(sources.jak_samples, std::memory_order_relaxed);
      contact_object_samples.fetch_add(sources.object_samples, std::memory_order_relaxed);
      const auto batches = contact_uploads.fetch_add(1, std::memory_order_relaxed) + 1;
      if (batches == 1 || batches % 600 == 0) {
        lg::info("[foliage-contact] TIE uniform_batches={} binding_failures={} (not GPU effect)",
                 batches, contact_binding_failures.load(std::memory_order_relaxed));
      }
    } else {
      contact_binding_failures.fetch_add(1, std::memory_order_relaxed);
    }
  }
}

void Tie3::push_tie_sway_uniforms(GLuint program, u64 frame_idx, const char* pass) {
  // foliage-wind (owner 2026-09-03) : une seule loi, une seule amplitude, une seule horloge pour
  // les quatre programmes (TIE statique x3 et shrub) — poussees d'un seul endroit.
  foliage_wind::push_uniforms(program, frame_idx, pass);
}

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials round-5 / ROUND 2 : plages d'indices statiques COMPLETES d'une
// categorie dans tree.index_buffer, construites une fois par arbre et par categorie. Chaque
// StripDraw a ses vis_groups qui pavent son intervalle du buffer complet : le total d'indices
// du draw est la somme des num_inds de ses groupes ; les draws adjacents sont coalesces.
// Keye par categorie : NORMAL et NORMAL_ENVMAP occupent des intervalles distincts du meme
// buffer et ont chacun leur cache (pas d'ecrasement, pas de double dessin).
void Tie3::ensure_tie_full_ranges(Tree& tree, tfrag3::TieCategory category) {
  const int cast_cat = (int)category;
  // lighting-ao-indirect (terme 3, correctif C) : TROIS jeux, un par categorie dessinee — et
  // pas un booleen. `NORMAL_ENVMAP_SECOND_DRAW` passe par le troisieme ; toute autre categorie
  // sort sans rien effacer, au lieu d'ecraser le jeu `NORMAL` (les casteurs de l'ombre solaire).
  int jeu;
  switch (category) {
    case tfrag3::TieCategory::NORMAL:
      jeu = 0;
      break;
    case tfrag3::TieCategory::NORMAL_ENVMAP:
      jeu = 1;
      break;
    case tfrag3::TieCategory::NORMAL_ENVMAP_SECOND_DRAW:
      jeu = 2;
      break;
    default:
      return;
  }
  auto& ranges = jeu == 2 ? tree.pbr_full_ranges_env2
                          : (jeu == 1 ? tree.pbr_full_ranges_env : tree.pbr_full_ranges);
  bool& ranges_built =
      jeu == 2 ? tree.pbr_full_ranges_env2_built
               : (jeu == 1 ? tree.pbr_full_ranges_env_built : tree.pbr_full_ranges_built);
  // lighting-ao-indirect : la prepasse de profondeur a besoin des MEMES draws, mais avec leur
  // texture — une coalescence qui traverse une frontiere de texture efface l'identite dont
  // l'alpha-test du feuillage depend. On construit donc les deux jeux dans la MEME boucle : la
  // passe soleil garde ses plages fusionnees a fond, la prepasse les siennes.
  auto& pre_ranges = jeu == 2 ? tree.prepass_ranges_env2
                              : (jeu == 1 ? tree.prepass_ranges_env : tree.prepass_ranges);
  auto& pre_noz = jeu == 2 ? tree.prepass_noz_ranges_env2
                           : (jeu == 1 ? tree.prepass_noz_ranges_env : tree.prepass_noz_ranges);
  if (ranges_built) {
    return;
  }
  ranges.clear();
  pre_ranges.clear();
  pre_noz.clear();
  for (size_t di = tree.category_draw_indices[cast_cat];
       di < tree.category_draw_indices[cast_cat + 1]; di++) {
    const auto& draw = (*tree.draws)[di];
    u32 count = 0;
    for (const auto& vg : draw.vis_groups) {
      count += vg.num_inds;
    }
    if (count == 0) {
      continue;
    }
    u32 first = draw.unpacked.idx_of_first_idx_in_full_buffer;
    if (!ranges.empty() && ranges.back().first + ranges.back().second == first) {
      ranges.back().second += count;  // coalesce adjacent draws
    } else {
      ranges.emplace_back(first, count);
    }
    // lighting-ao-indirect (c)/(g) : la passe principale coupe le z-write pour ce draw ;
    // l'ecrire dans la prepasse ferait de son quad un occluder d'AO que l'image ne dessine pas.
    // La coalescence de `ranges` (passe SOLEIL, ci-dessus) reste INCHANGEE : le `continue` est
    // pose APRES elle et n'ecarte que `pre_ranges`.
    if (!prepass_writes_depth(draw.mode)) {
      pre_noz.push_back(prepass::DepthRange{0, 0.f, 0.f, first, count});
      prepass::note_noz_range(count);
      continue;
    }
    const float am = prepass_alpha_min(draw.mode);
    // tree_tex_id negatif = emplacement de texture animee : aucun nom GL stable, on le traite
    // comme opaque plutot que de lier n'importe quoi.
    if (am <= 0.f || draw.tree_tex_id < 0) {
      if (!pre_ranges.empty() && pre_ranges.back().cut_aref <= 0.f &&
          pre_ranges.back().first + pre_ranges.back().count == first) {
        pre_ranges.back().count += count;
      } else {
        pre_ranges.push_back(prepass::DepthRange{0, 0.f, 0.f, first, count});
      }
    } else {
      // (terme 3) Le MODE d'echantillonnage du draw voyage avec la plage : la prepasse POSE
      // l'etat de la texture au lieu de l'heriter (background_common.h, `prepass_tex_mode`).
      pre_ranges.push_back(prepass::DepthRange{(uint32_t)draw.tree_tex_id, am, am, first,
                                               count, prepass_tex_mode(draw.mode),
                                               ao_tie_alpha_probe::draw_id(tree.draws, di)});
    }
  }
  ranges_built = true;
}
#endif

// lighting-ao-indirect : LE CHEMIN VENT DANS LA PREPASSE DE PROFONDEUR.
//
// LE DEFAUT MESURE : `ao_geom_tie_cover_px=785265` pour `ao_geom_tie_absent_px=2918` — des pixels
// dont la COULEUR vient d'un bucket TIE et sous lesquels la prepasse n'avait AUCUNE geometrie.
// Ils sont le chemin VENT : sommets PROTOTYPE-LOCAUX transformes par une matrice d'instance
// (`wind_matrix_cache`), dessines depuis `wind_vertex_index_buffer` / `wind_draws` — ni l'un ni
// l'autre n'appartient aux `prepass_ranges`, qui vivent dans `index_buffer`.
//
// LA METHODE : on REJOUE LE MEME DESSIN AVEC LE MEME PROGRAMME, couleur masquee. Aucun shader de
// prepasse n'est ecrit pour lui et aucune arithmetique n'est dupliquee : deux arithmetiques
// censees rendre le meme z finissent toujours par diverger. Le `discard` d'alpha de
// tie_wind.frag continue de tourner — c'est lui qui empeche l'AO de se poser sur le vide entre
// les palmes.
uint64_t Tie3::draw_wind_depth_prepass(SharedRenderState* rs) {
#ifdef OG_FEAT_PBR
  if (!rs || m_hide_wind) {
    return 0;
  }
  // NE REJOUER LE VENT QUE DANS LA PASSE QUI ECRIT LA PROFONDEUR LIVREE. `draw_all_contributors`
  // est appele trois fois par image sondee : la passe livree (FBO de profondeur, z-write ON), la
  // CLASSIFICATION (autre FBO, GL_EQUAL, z-write OFF, couleur ouverte) et la mesure « occluder
  // fantome » (meme FBO, z-write OFF, requetes d'occlusion). Les deux dernieres comptent des
  // fragments du programme PREPASS_WORLD : y glisser un AUTRE programme fausserait leurs
  // grandeurs. La condition est lue sur l'etat GL reel, pas sur une supposition d'ordre.
  GLint cur_fbo = 0;
  GLboolean depth_mask = GL_FALSE;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &cur_fbo);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &depth_mask);
  if (prepass::depth_fbo() == 0 || (GLuint)cur_fbo != prepass::depth_fbo() ||
      depth_mask != GL_TRUE || prepass::noz_pass_active()) {
    return 0;  // 0 == le FBO par defaut : jamais dessiner l'ecran depuis ici
  }
  const int geom = lod();
  bool any = false;
  for (auto& tree : m_trees[geom]) {
    if (tree.wind_draws && !tree.wind_draws->empty()) {
      any = true;
      break;
    }
  }
  if (!any) {
    return 0;
  }

  // Etat d'entree, relu (jamais suppose) : le chemin couleur pose blend / face / profondeur par
  // mode de draw et lie une texture sur l'unite 0 — or `prepass::draw_depth_range` MEMOISE la
  // texture qu'elle a liee. Tout ce qu'on touche est rendu tel qu'on l'a trouve.
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  GLint prev_program = 0, prev_depth_func = GL_GEQUAL, prev_tex0 = 0, prev_active_tex = GL_TEXTURE0;
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active_tex);
  glActiveTexture(GL_TEXTURE0);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0);
  const GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);

  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

  uint64_t total = 0;
  for (u32 i = 0; i < m_trees[geom].size(); i++) {
    auto& tree = m_trees[geom][i];
    if (!tree.wind_draws || tree.wind_draws->empty()) {
      continue;
    }
    // La camera de CETTE image : `rs->camera_matrix` est la copie octet pour octet de
    // `data.camera.camera`, posee par update_render_state_from_pc_settings juste avant la
    // prepasse. C'est la meme que celle que la passe couleur passera a `update_wind_instances`,
    // qui ne recalculera donc rien.
    update_wind_instances(tree, rs->camera_matrix, rs);
    total += draw_tree_wind((int)i, geom, nullptr, rs, nullptr, /*depth_only=*/true);
  }

  // ---- restauration : l'etat que `run_prepass` a pose pour les contributeurs ----
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  glUseProgram((GLuint)prev_program);
  glDepthFunc(prev_depth_func);
  glDepthMask(GL_TRUE);
  glEnable(GL_DEPTH_TEST);
  if (prev_cull) {
    glEnable(GL_CULL_FACE);
  } else {
    glDisable(GL_CULL_FACE);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  } else {
    glDisable(GL_BLEND);
  }
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex0);
  glActiveTexture((GLenum)prev_active_tex);
  return total;
#else
  (void)rs;
  return 0;
#endif
}

// lighting-ao-indirect : prepasse de profondeur vue camera. Programme PREPASS_WORLD actif,
// FBO / viewport / etat de profondeur poses par prepass::on_first_camera ; on ne fait que lier
// et dessiner les plages statiques completes NORMAL + NORMAL_ENVMAP. Le chemin VENT n'est plus
// exclu : il est rejoue juste apres par `draw_wind_depth_prepass`, avec SON programme.
uint64_t Tie3::draw_depth_prepass(SharedRenderState* rs) {
#ifdef OG_FEAT_PBR
  // La prepasse tourne AVANT le premier draw_matching_draws_for_tree de l'image : le restart
  // de strip (UINT32_MAX) doit etre arme ici, comme la-bas.
#ifdef __ANDROID__
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif
  uint64_t total = 0;
  for (auto& tree : m_trees[lod()]) {
    if (tree.draws == nullptr) {
      continue;
    }
    ensure_tie_full_ranges(tree, tfrag3::TieCategory::NORMAL);
    ensure_tie_full_ranges(tree, tfrag3::TieCategory::NORMAL_ENVMAP);
    // lighting-ao-indirect (terme 3, LE CORRECTIF) : LA TROISIEME CATEGORIE. La couche additive
    // de brillance des TIE envmappes ECRIT LA PROFONDEUR et n'a AUCUN test d'alpha
    // (`process_envmap_draw_mode` appelle `process_draw_mode(info, use_tra=false, ...)`,
    // extract_tie.cpp:2317 ; `mode.disable_at()` :2268 et `enable_depth_write()/enable_zt()`
    // :2271-2273 — d'ou `prepass_alpha_min` = 0, background_common.cpp:177, et
    // `prepass_writes_depth` VRAI, :197). La prepasse ne dessinait que deux categories sur
    // trois : sur un TIE envmappe a texture DECOUPEE, la passe de base et la prepasse jettent
    // les memes texels transparents, puis le second draw REMPLIT le trou et y ecrit la
    // profondeur de scene — la prepasse n'y a rien, `pl == 0` exactement, et les huit voisins
    // sont vides aussi parce qu'un trou de decoupe est une surface. C'est la signature mesuree
    // (`_absent_zero_px == _absent_px`, `_absent_inner_px` majoritaire).
    // CE QUE LA PREUVE DOIT MONTRER : `ao_geom_tie_env2_absent_inner_px` TOMBE, et
    // `ao_geom_tie_absent_edge_px` ne bouge PAS — c'est le controle gratuit du correctif.
    ensure_tie_full_ranges(tree, tfrag3::TieCategory::NORMAL_ENVMAP_SECOND_DRAW);
    glBindVertexArray(tree.vao);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.index_buffer);
    // lighting-ao-indirect (i) : le MEME deplacement de sommet que la passe couleur
    // (:1244-1246). Sans lui, la profondeur d'un arbre qui balance reste a sa place de repos et
    // l'AO avec elle. Le VAO qu'on vient de lier est celui de la passe couleur : les attributs 7,
    // 8 (et 10 si l'arbre porte une carte de contact) y sont deja actifs.
    prepass::sway_tie(rs ? rs->frame_idx : 0, tree.contact_texture);
    const std::array<const std::vector<prepass::DepthRange>*, 3> pre_lists =
        prepass::noz_pass_active()
            ? std::array<const std::vector<prepass::DepthRange>*, 3>{&tree.prepass_noz_ranges,
                                                                     &tree.prepass_noz_ranges_env,
                                                                     &tree.prepass_noz_ranges_env2}
            : std::array<const std::vector<prepass::DepthRange>*, 3>{
                  &tree.prepass_ranges, &tree.prepass_ranges_env, &tree.prepass_ranges_env2};
    // lighting-ao-indirect (A4) : LA PROJECTION `etie` POUR LES PLAGES NORMAL_ENVMAP (indice 1).
    // La passe COULEUR de ces draws passe par `etie_base.vert` et son pipeline (:1187-1190, « use
    // the envmap-style math for the base draw to avoid rounding issue ») ; la prepasse dessinait
    // les MEMES plages avec `pc_camera` + `cam_trans`. Deux arithmetiques censees rendre le meme z
    // ne donnent pas le meme bit : `ao_geom_tie_gap64_px=192`, IDENTIQUE dans les deux bras (donc
    // etranger au deplacement de sommet). On pose le mode ET les trois uniformes par LISTE, avec
    // la MEME fonction que la passe couleur (`init_etie_cam_uniforms`, :1027) — aucune
    // arithmetique dupliquee — et sur la camera de la PREPASSE : la notre (`m_common_data`) n'est
    // pas encore lue quand la prepasse tire.
    const GLuint pre_id = prepass::world_program();
    const GoalBackgroundCameraData* pre_cam = prepass::prepass_cam();
    EtieUniforms pre_etie{};
    pre_etie.persp0 = glu::loc(pre_id, "persp0");
    pre_etie.persp1 = glu::loc(pre_id, "persp1");
    pre_etie.cam_no_persp = glu::loc(pre_id, "cam_no_persp");
    pre_etie.envmap_tod_tint = 0;
    pre_etie.decal = 0;
    for (size_t li = 0; li < pre_lists.size(); li++) {
      const auto* ranges = pre_lists[li];
      // Les indices 1 ET 2 sont de l'arithmetique `etie` : `etie.vert:42-45` et `:105-108`
      // construisent `vf17` et `p_proj` avec EXACTEMENT les memes `cam_no_persp` / `persp0` /
      // `persp1` que `etie_base.vert:55-66`, que `prepass_world.vert` recopie deja.
      const bool env_list = (li >= 1);
      if (env_list && pre_cam && pre_id != 0) {
        init_etie_cam_uniforms(pre_etie, *pre_cam);
        prepass::etie_mode(1);
      } else {
        prepass::etie_mode(0);
      }
      for (const auto& r : *ranges) {
        const GLuint gltex = (r.cut_aref > 0.f && m_textures && r.tex < m_textures->size())
                                 ? m_textures->at(r.tex)
                                 : 0;
        auto range = prepass::make_depth_range(gltex, r.cut_aref, r.first, r.count, r.tex_mode);
        range.tie_probe_id = r.tie_probe_id;
        const auto submitted = prepass::draw_depth_range(tree.draw_mode, range);
        total += submitted;
        if (submitted && ao_contact_draws::active(m_level_name)) ao_contact_draws::record(m_level_name, "tie", prepass::noz_pass_active() ? "prepass_noz" : "prepass",
            rs ? rs->frame_idx : 0, lod(), &tree - m_trees[lod()].data(), 0, tree.draws->size(),
            tree.vertex_buffer, tree.draw_mode, r.first, r.count, tree.index_data,
            ao_contact_draws::full_count(*tree.draws));
      }
    }
    // Un uniforme laisse a 1 par un voisin est un defaut : l'arbre suivant, le chemin VENT et le
    // contributeur suivant repartent tous de la projection ordinaire.
    prepass::etie_mode(0);
  }
  // Le chemin VENT, APRES le statique : il change de programme, donc il ne doit pas s'intercaler
  // entre deux plages du chemin statique.
  const uint64_t wind_inds = draw_wind_depth_prepass(rs);
  prepass::note_wind_prepass((uint32_t)wind_inds);
  total += wind_inds;
  return total;
#else
  (void)rs;
  return 0;
#endif
}

void Tie3::draw_matching_draws_for_tree(int idx,
                                        int geom,
                                        const TfragRenderSettings& settings,
                                        SharedRenderState* render_state,
                                        ScopedProfilerNode& prof,
                                        tfrag3::TieCategory category) {
  auto& tree = m_trees.at(geom).at(idx);

  // don't render if we haven't loaded
  if (!m_has_level) {
    return;
  }
  bool use_envmap = tfrag3::is_envmap_first_draw_category(category);
  auto shader_id = use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3;

  // setup OpenGL shader
  first_tfrag_draw_setup(settings.camera, render_state, shader_id);

  // mesh-consolidate-without-consumer : location 6 = `seam_w` pour ce VAO (bind ~570).
  mesh_unconsumed_census::probe_bound_attrib(render_state->shaders[shader_id].id(), 6);

  if (use_envmap) {
    // if we use envmap, use the envmap-style math for the base draw to avoid rounding issue.
    init_etie_cam_uniforms(m_etie_base_uniforms, m_common_data.settings.camera);
  }

  glBindVertexArray(tree.vao);
  // lighting-ao-indirect (terme 3) : NOMME le sous-chemin TIE de ces draws pour le recensement
  // (stencil de preuve seul, aucune couleur ecrite, inerte hors image sondee).
  prepass::proof_stencil_family(use_envmap ? prepass::kProofFamTieEnv : prepass::kProofFamTie);
  glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
               render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);

  // Grecharged-foliage-wind3 (defaut D2) : APRES `first_tfrag_draw_setup`, qui vient d'ecrire 0
  // pour tout le monde (le terrain TFRAG partage ce vertex shader), et APRES le bind du VAO pour
  // que la ligne de preuve puisse interroger l'etat REEL de l'attribut 7.
  push_tie_sway_uniforms(render_state->shaders[shader_id].id(), render_state->frame_idx,
                         use_envmap ? "etie_base" : "tfrag3");
  push_tie_contact(render_state->shaders[shader_id].id(), tree.contact_texture);
  foliage_wind::mark_drawn(m_level_name, foliage_wind::kSystemTieStatic, idx, geom);

  glActiveTexture(GL_TEXTURE10);
  // Gperf-particles round 3: bind the TOD texture selected at update time (the
  // ping-pong current, or the single texture when the flag is off).
  glBindTexture(GL_TEXTURE_2D, tree.tod_current);

  glActiveTexture(GL_TEXTURE0);
#ifdef __ANDROID__
  // GLES has no settable restart index (glPrimitiveRestartIndex is NULL in the
  // arm64 loader — calling it is BLR-to-0 / sig=11 fault=0x0, the same class as
  // the A36 tfrag/shrub crashes). The fixed-index mode restarts on the all-ones
  // index, which IS UINT32_MAX for our u32 index buffers — identical semantics.
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4, owner clarification 2026-07-18 (WORLD-scale
  // shadows): TIE geometry — the sage hut, bridges, buildings — must CAST into the sun
  // shadow map, else the owner's acceptance image (hut shadow on the ground) is
  // impossible. Depth-only pass over this tree's NORMAL-category draws into the
  // double-buffered write map; receivers sample last frame's completed map, so bucket
  // order (tfrag before tie) does not matter. Same GL-state dance as the TFragment
  // caster pass. Vertex layout is compatible: TIE draws with the TFRAG3 program, so
  // attribute 0 is the world position pbr_depth.vert consumes.
  // Round-5 addendum 2 (mandate F): la passe de profondeur est mondiale, sans condition de matiere.
  // ROUND 2 (owner defect #3): the envmap TIE geometry (shiny huts, metal props, bridges)
  // must ALSO cast — its opaque base draw is the NORMAL_ENVMAP category. Cast for both the
  // plain NORMAL and the NORMAL_ENVMAP base draws (never the TRANS/WATER or *_SECOND_DRAW
  // shiny-overlay categories, which would double-cast the same geometry).
  if (((!use_envmap && category == tfrag3::TieCategory::NORMAL) ||
       (use_envmap && category == tfrag3::TieCategory::NORMAL_ENVMAP)) &&
      (recharged_gating::on(recharged_gating::kLighting) ||
       recharged_gating::on(recharged_gating::kRtLight)) &&
      (pbr_shadow_caster_mask(render_state->frame_idx) & 2) &&
      pbr_shadow_begin_frame(render_state->frame_idx, settings.camera.trans.data())) {
    auto& sh_st = pbr_shadow_state();
    GLint prev_program = 0, prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_depth_func = GL_LEQUAL;
    GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
    GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
    GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
    // DEPTH_TEST is per-DrawMode state — force it on for the depth-only pass (depth
    // writes only happen when the test is enabled; the device chain reaches here with
    // it off → empty map). Same fix as the TFragment caster pass.
    GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
    GLboolean prev_depth_mask = GL_TRUE;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
    glGetIntegerv(GL_VIEWPORT, prev_vp);
    glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
    glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);

    glBindFramebuffer(GL_FRAMEBUFFER, sh_st.fbo[sh_st.write]);
    glViewport(0, 0, sh_st.size, sh_st.size);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_DEPTH_TEST);
    glDepthMask(GL_TRUE);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(2.0f, 4.0f);

    const auto& depth_sh = render_state->shaders[ShaderId::PBR_DEPTH];
    depth_sh.activate();
    GLuint depth_id = depth_sh.id();
    glUniformMatrix4fv(glu::loc(depth_id, "u_smvp"), 1, GL_FALSE, sh_st.mvp);
    const auto& ct = settings.camera.trans;
    glUniform4f(glu::loc(depth_id, "cam_trans"), ct[0], ct[1], ct[2], ct[3]);

    if (sh_st.cast_full) {
      // Round-5 owner bug fix (same as TFragment): the caster set must IGNORE camera
      // visibility — an off-screen hut must keep casting its on-screen shadow, else
      // shadows pop in/out on camera rotation. Draw the current category's FULL static
      // index ranges from tree.index_buffer (already the bound EBO in multidraw mode;
      // rebind for no_multidraw and restore after). Ranges are built lazily per tree:
      // each StripDraw's vis_groups tile its span in the full buffer, so the draw's
      // total index count is the sum of its groups' num_inds. ROUND 2: keyed by category
      // so NORMAL and NORMAL_ENVMAP each get their own cached ranges (no clobber, no
      // double-cast — the two categories occupy distinct index spans in the same buffer).
      const bool env_cat = (category == tfrag3::TieCategory::NORMAL_ENVMAP);
      // lighting-ao-indirect : le constructeur paresseux vit dans ensure_tie_full_ranges,
      // partage avec la prepasse de profondeur d'AO.
      ensure_tie_full_ranges(tree, category);
      const auto& ranges = env_cat ? tree.pbr_full_ranges_env : tree.pbr_full_ranges;
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.index_buffer);
      for (const auto& r : ranges) {
        lighting_census::note_world_draw(lighting_census::Kind::DepthOnly);
        glDrawElements(tree.draw_mode, r.second, GL_UNSIGNED_INT,
                       (void*)((size_t)r.first * sizeof(u32)));
        sh_st.cast_indices += (u64)r.second;
      }
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, render_state->no_multidraw
                                                ? tree.single_draw_index_buffer
                                                : tree.index_buffer);
    } else {
      // Old camera-vis-culled caster set (prop castfull=0), kept as the perf/repro A/B.
      for (size_t di = tree.category_draw_indices[(int)category];
           di < tree.category_draw_indices[(int)category + 1]; di++) {
        if (render_state->no_multidraw) {
          const auto& sd = tree.draw_idx_temp[di];
          if (sd.second == 0) {
            continue;
          }
          lighting_census::note_world_draw(lighting_census::Kind::DepthOnly);
          glDrawElements(tree.draw_mode, sd.second, GL_UNSIGNED_INT,
                         (void*)(sd.first * sizeof(u32)));
          sh_st.cast_indices += (u64)sd.second;
        } else {
          const auto& md = tree.multidraw_offset_per_stripdraw[di];
          if (md.second == 0) {
            continue;
          }
          lighting_census::note_world_draw(lighting_census::Kind::DepthOnly);
          glMultiDrawElements(tree.draw_mode, &tree.multidraw_count_buffer[md.first],
                              GL_UNSIGNED_INT, &tree.multidraw_index_offset_buffer[md.first],
                              md.second);
          for (int mdi = 0; mdi < md.second; mdi++) {
            sh_st.cast_indices += (u64)tree.multidraw_count_buffer[md.first + mdi];
          }
        }
      }
    }
    if (sh_st.debug) {
      GLenum dbg_err = glGetError();
      if (dbg_err != GL_NO_ERROR) {
        lg::warn("PBR-SHADOW-DBG tie depth pass glerr=0x{:x}", (u32)dbg_err);
      }
    }

    glUseProgram((GLuint)prev_program);
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
    glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
    if (prev_scissor) {
      glEnable(GL_SCISSOR_TEST);
    } else {
      glDisable(GL_SCISSOR_TEST);
    }
    if (prev_cull) {
      glEnable(GL_CULL_FACE);
    } else {
      glDisable(GL_CULL_FACE);
    }
    if (prev_poly_off) {
      glEnable(GL_POLYGON_OFFSET_FILL);
    } else {
      glDisable(GL_POLYGON_OFFSET_FILL);
    }
    glPolygonOffset(0.0f, 0.0f);
    if (!prev_depth_test) {
      glDisable(GL_DEPTH_TEST);
    }
    glDepthMask(prev_depth_mask);
    glDepthFunc(prev_depth_func);
  }
#endif

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;

  // Grecharged-grass-overhang2: per-draw fringe near-fade uniform. Non-envmap TFRAG3 only (the
  // painted fringe strips are not envmapped); the envmap paths use ETIE_BASE and are left untouched.
  // ALWAYS left at 0 so other TFRAG3 users are unaffected; 0 = stock shader path.
  const GrassFringeFade fringe_fade = grass_fringe_fade_params();
  const bool fringe_active = fringe_fade.on && !use_envmap;
  GLint fringe_loc = -2;  // -2 = not queried yet
  bool fringe_on_state = false;
  auto set_fringe = [&](bool want) {
    if (want == fringe_on_state) {
      return;
    }
    if (fringe_loc == -2) {
      fringe_loc = glu::loc(render_state->shaders[shader_id].id(), "u_fringe_fade");
    }
    if (fringe_loc >= 0) {
      glUniform4f(fringe_loc, want ? 1.f : 0.f, fringe_fade.start_m, fringe_fade.end_m,
                  fringe_fade.dbg);
    }
    fringe_on_state = want;
  };

#ifdef OG_FEAT_PBR
  const ShaderId pbr_program = use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3;
  // Round-4 mandate B: bind the sun shadow matrix + sampler on the program that is actually
  // active so a replaced TIE surface receives the same shadowed direct term as tfrag. The depth
  // pass itself is driven by TFragment (tfrag NORMAL casters); Tie3 is receiver-only.
  // (Round-3 defect A/B: the envmap base needs this too, and always did.)
  if ((recharged_gating::on(recharged_gating::kLighting) ||
       recharged_gating::on(recharged_gating::kRtLight)) &&
      pbr_shadow_state().valid) {
    pbr_shadow_bind_receiver(render_state->shaders[pbr_program].id(),
                             settings.camera.trans.data());
  }
#endif

  const bool alpha_probe = category == tfrag3::TieCategory::NORMAL && ao_tie_alpha_probe::active();
  if (alpha_probe) ao_tie_alpha_probe::color_begin();
  auto contact_record = [&](size_t begin, size_t end, size_t first, size_t count) {
    if (!ao_contact_draws::active(m_level_name)) return;
    ao_contact_draws::record(m_level_name, "tie", "color", render_state->frame_idx, geom, idx,
        begin, end, tree.vertex_buffer, tree.draw_mode, first, count,
        render_state->no_multidraw ? tree.index_temp.data() : tree.index_data,
        render_state->no_multidraw ? tree.index_temp.size() : ao_contact_draws::full_count(*tree.draws),
        render_state->no_multidraw ? &tree.contact_source_offsets : nullptr,
        ao_tie_alpha_probe::draw_id(tree.draws, begin));
  };
  int last_texture = -1;
  if (render_state->no_multidraw && render_state->batch_singledraw && !alpha_probe) {
    // Gperf-batching: merge consecutive draws sharing texture+mode into one
    // glDrawElements (see TFragment.cpp — same contiguity + trailing-restart
    // guarantees; TieTree::unpack ends every run with UINT32_MAX). Tie base
    // draws never double-draw (the AFAIL arm below is ASSERT(false)).
    const auto shader_id2 = use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3;
    size_t draw_idx = tree.category_draw_indices[(int)category];
    const size_t end_idx = tree.category_draw_indices[(int)category + 1];
    while (draw_idx < end_idx) {
      const auto& draw = tree.draws->operator[](draw_idx);
      const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];
      if (singledraw_indices.second == 0) {
        draw_idx++;
        continue;
      }

      if (draw.tree_tex_id != last_texture) {
        if (draw.tree_tex_id >= 0) {
          bound_tex = m_textures->at(draw.tree_tex_id);
        } else {
          bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
          gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
        }
        glBindTexture(GL_TEXTURE_2D, bound_tex);
        last_texture = draw.tree_tex_id;
      }

      auto double_draw =
          setup_tfrag_shader_cached(render_state, draw.mode, shader_id2, bound_tex, draw_state_cache);
      glUniform1i(use_envmap ? m_etie_base_uniforms.decal : m_uniforms.decal,
                  draw.mode.get_decal() ? 1 : 0);
      set_fringe(fringe_active && draw.tree_tex_id >= 0 &&
                 (draw.tree_tex_id == m_fringe_tex_a || draw.tree_tex_id == m_fringe_tex_b));

      int first = singledraw_indices.first;
      int count = singledraw_indices.second;
      size_t next = draw_idx + 1;
      if (double_draw.kind == DoubleDrawKind::NONE) {
        while (next < end_idx) {
          const auto& d2 = tree.draws->operator[](next);
          const auto& sd2 = tree.draw_idx_temp[next];
          if (sd2.second == 0) {
            next++;
            continue;
          }
          if (d2.tree_tex_id != draw.tree_tex_id || d2.mode.as_int() != draw.mode.as_int() ||
              sd2.first != first + count) {
            break;
          }
          count += sd2.second;
          next++;
        }
      } else {
        ASSERT(false);
      }

      prof.add_draw_call();
      lighting_census::note_world_draw(lighting_census::Kind::Tie);
      if (alpha_probe) ao_tie_alpha_probe::before_color_draw(
          render_state->shaders[shader_id].id(), ao_tie_alpha_probe::draw_id(tree.draws, draw_idx));
      glDrawElements(tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      contact_record(draw_idx, next, first, count);
      shrub_contact_measurement::draw_elements(m_level_name, geom, idx, render_state->frame_idx, tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      draw_idx = next;
    }
  } else {
  for (size_t draw_idx = tree.category_draw_indices[(int)category];
       draw_idx < tree.category_draw_indices[(int)category + 1]; draw_idx++) {
    const auto& draw = tree.draws->operator[](draw_idx);
    const auto& multidraw_indices = tree.multidraw_offset_per_stripdraw[draw_idx];
    const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];

    if (render_state->no_multidraw) {
      if (singledraw_indices.second == 0) {
        continue;
      }
    } else {
      if (multidraw_indices.second == 0) {
        continue;
      }
    }

    if (draw.tree_tex_id != last_texture) {
      if (draw.tree_tex_id >= 0) {
        bound_tex = m_textures->at(draw.tree_tex_id);
      } else {
        bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
        gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      last_texture = draw.tree_tex_id;
    }

    auto double_draw = setup_tfrag_shader_cached(
        render_state, draw.mode, use_envmap ? ShaderId::ETIE_BASE : ShaderId::TFRAG3, bound_tex,
        draw_state_cache);

    glUniform1i(use_envmap ? m_etie_base_uniforms.decal : m_uniforms.decal,
                draw.mode.get_decal() ? 1 : 0);
    set_fringe(fringe_active && draw.tree_tex_id >= 0 &&
               (draw.tree_tex_id == m_fringe_tex_a || draw.tree_tex_id == m_fringe_tex_b));

    prof.add_draw_call();

    if (render_state->no_multidraw) {
      lighting_census::note_world_draw(lighting_census::Kind::Tie);
      if (alpha_probe) ao_tie_alpha_probe::before_color_draw(
          render_state->shaders[shader_id].id(), ao_tie_alpha_probe::draw_id(tree.draws, draw_idx));
      glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
      contact_record(draw_idx, draw_idx + 1, singledraw_indices.first, singledraw_indices.second);
      shrub_contact_measurement::draw_elements(m_level_name, geom, idx, render_state->frame_idx, tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
    } else {
      lighting_census::note_world_draw(lighting_census::Kind::Tie);
      if (alpha_probe) ao_tie_alpha_probe::before_color_draw(
          render_state->shaders[shader_id].id(), ao_tie_alpha_probe::draw_id(tree.draws, draw_idx));
      glMultiDrawElements(
          tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first], GL_UNSIGNED_INT,
          &tree.multidraw_index_offset_buffer[multidraw_indices.first], multidraw_indices.second);
      for (int contact_i = 0; contact_i < multidraw_indices.second; ++contact_i) {
        const auto contact_slot = multidraw_indices.first + contact_i;
        contact_record(draw_idx, draw_idx + 1,
            uintptr_t(tree.multidraw_index_offset_buffer[contact_slot]) / sizeof(u32),
            tree.multidraw_count_buffer[contact_slot]);
      }
      shrub_contact_measurement::multi_draw_elements(m_level_name, geom, idx, render_state->frame_idx,
          tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first], GL_UNSIGNED_INT,
          &tree.multidraw_index_offset_buffer[multidraw_indices.first], multidraw_indices.second);
    }

    switch (double_draw.kind) {
      case DoubleDrawKind::NONE:
        break;
      case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE: {
        ASSERT(false);
        prof.add_draw_call();
        const auto& afail_u = tfrag_alpha_uniforms(render_state->shaders[ShaderId::TFRAG3].id());
        if (afail_u.alpha_min != -1) {
          glUniform1f(afail_u.alpha_min, -10.f);
        }
        if (afail_u.alpha_max != -1) {
          glUniform1f(afail_u.alpha_max, double_draw.aref_second);
        }
        glDepthMask(GL_FALSE);
        // depth-mask toggled: cached mode's depth state is now stale.
        draw_state_cache.valid = false;
        if (render_state->no_multidraw) {
          lighting_census::note_world_draw(lighting_census::Kind::Tie);
          if (alpha_probe) ao_tie_alpha_probe::before_color_draw(
              render_state->shaders[shader_id].id(), ao_tie_alpha_probe::draw_id(tree.draws, draw_idx));
          glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                         (void*)(singledraw_indices.first * sizeof(u32)));
      contact_record(draw_idx, draw_idx + 1, singledraw_indices.first, singledraw_indices.second);
          shrub_contact_measurement::draw_elements(m_level_name, geom, idx, render_state->frame_idx, tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                         (void*)(singledraw_indices.first * sizeof(u32)));
        } else {
          lighting_census::note_world_draw(lighting_census::Kind::Tie);
          if (alpha_probe) ao_tie_alpha_probe::before_color_draw(
              render_state->shaders[shader_id].id(), ao_tie_alpha_probe::draw_id(tree.draws, draw_idx));
          glMultiDrawElements(tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first],
                              GL_UNSIGNED_INT,
                              &tree.multidraw_index_offset_buffer[multidraw_indices.first],
                              multidraw_indices.second);
      for (int contact_i = 0; contact_i < multidraw_indices.second; ++contact_i) {
        const auto contact_slot = multidraw_indices.first + contact_i;
        contact_record(draw_idx, draw_idx + 1,
            uintptr_t(tree.multidraw_index_offset_buffer[contact_slot]) / sizeof(u32),
            tree.multidraw_count_buffer[contact_slot]);
      }
          shrub_contact_measurement::multi_draw_elements(m_level_name, geom, idx, render_state->frame_idx, tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first],
                              GL_UNSIGNED_INT,
                              &tree.multidraw_index_offset_buffer[multidraw_indices.first],
                              multidraw_indices.second);
        }
        break;
      } // AFAIL_NO_DEPTH_WRITE
      default:
        ASSERT(false);
    }
  }
  }
  if (alpha_probe) ao_tie_alpha_probe::color_end();
  // Grecharged-grass-overhang2: leave the fringe fade off for any subsequent TFRAG3 user.
  set_fringe(false);

  if (!m_hide_wind && category == tfrag3::TieCategory::NORMAL) {
    auto wind_prof = prof.make_scoped_child("wind");
    render_tree_wind(idx, geom, settings, render_state, wind_prof);
  }

  glBindVertexArray(0);

  if (use_envmap && m_draw_envmap_second_draw) {
    envmap_second_pass_draw(tree, geom, idx, settings, render_state, prof,
                            tfrag3::get_second_draw_category(category));
  }
}

// Les categories *_ENVMAP_SECOND_DRAW dessinees ici sont la couche additive de brillance des TIE
// envmappes ; leurs draws portent l'identifiant de texture ENVMAP, pas celui de la texture de base.
void Tie3::envmap_second_pass_draw(const Tree& tree, int geom, int idx,
                                   const TfragRenderSettings& settings,
                                   SharedRenderState* render_state,
                                   ScopedProfilerNode& prof,
                                   tfrag3::TieCategory category) {
  first_tfrag_draw_setup(settings.camera, render_state, ShaderId::ETIE);
  glBindVertexArray(tree.vao);
  // lighting-ao-indirect (terme 3) : NOMME la couche additive d'envmap (sa PROPRE famille, pour
  // que l'effet du correctif C soit attribuable) pour le recensement — stencil de preuve seul,
  // aucune couleur ecrite, inerte hors image sondee.
  prepass::proof_stencil_family(prepass::kProofFamTieEnv2);
  glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
               render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);
  // Grecharged-foliage-wind3 : la passe ADDITIVE de reflet dessine la MEME geometrie que la passe
  // de base. Si elle ne recevait pas exactement les memes uniformes, le reflet se decollerait de
  // l'objet des que le balancement s'allume.
  push_tie_sway_uniforms(render_state->shaders[ShaderId::ETIE].id(), render_state->frame_idx,
                         "etie");
  push_tie_contact(render_state->shaders[ShaderId::ETIE].id(), tree.contact_texture);

  init_etie_cam_uniforms(m_etie_uniforms, m_common_data.settings.camera);
  set_uniform(m_etie_uniforms.envmap_tod_tint, m_common_data.envmap_color);

  // Gjak2-visuals probe: the etie additive-coat tint, the one unmeasured input
  // of the white-wash hypothesis — diffable our-x86 (env GJ2VIS_TFTREE) vs
  // device (always, ~5 s cadence).
  {
#ifdef __ANDROID__
    static const bool s_tint_dump = true;
#else
    static const bool s_tint_dump = getenv("GJ2VIS_TFTREE") != nullptr;
#endif
    if (s_tint_dump) {
      static int s_tint_ctr = 0;
      if ((s_tint_ctr++ % 300) == 0) {
        const auto& ec = m_common_data.envmap_color;
        fprintf(stderr, "GJ2VIS-ETIETINT lvl=%s cat=%d tint=(%.4f %.4f %.4f %.4f) strength=%.3f\n",
                m_level_name.c_str(), (int)category, ec.x(), ec.y(), ec.z(), ec.w(),
                m_envmap_strength);
      }
    }
  }

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;

  auto contact_record = [&](size_t begin, size_t end, size_t first, size_t count) {
    if (!ao_contact_draws::active(m_level_name)) return;
    ao_contact_draws::record(m_level_name, "tie", "color", render_state->frame_idx, geom, idx,
        begin, end, tree.vertex_buffer, tree.draw_mode, first, count,
        render_state->no_multidraw ? tree.index_temp.data() : tree.index_data,
        render_state->no_multidraw ? tree.index_temp.size() : ao_contact_draws::full_count(*tree.draws),
        render_state->no_multidraw ? &tree.contact_source_offsets : nullptr,
        ao_tie_alpha_probe::draw_id(tree.draws, begin));
  };
  int last_texture = -1;
  if (render_state->no_multidraw && render_state->batch_singledraw) {
    // Gperf-batching: merged-draw variant (see render_tree above). Envmap
    // second-pass draws never double-draw (non-NONE asserts below).
    size_t draw_idx = tree.category_draw_indices[(int)category];
    const size_t end_idx = tree.category_draw_indices[(int)category + 1];
    while (draw_idx < end_idx) {
      const auto& draw = tree.draws->operator[](draw_idx);
      const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];
      if (singledraw_indices.second == 0) {
        draw_idx++;
        continue;
      }

      if (draw.tree_tex_id != last_texture) {
        if (draw.tree_tex_id >= 0) {
          bound_tex = m_textures->at(draw.tree_tex_id);
        } else {
          bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
          gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
        }
        glBindTexture(GL_TEXTURE_2D, bound_tex);
        last_texture = draw.tree_tex_id;
      }

      auto double_draw =
          setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::ETIE, bound_tex,
                                    draw_state_cache);
      ASSERT(double_draw.kind == DoubleDrawKind::NONE);

      int first = singledraw_indices.first;
      int count = singledraw_indices.second;
      size_t next = draw_idx + 1;
      while (next < end_idx) {
        const auto& d2 = tree.draws->operator[](next);
        const auto& sd2 = tree.draw_idx_temp[next];
        if (sd2.second == 0) {
          next++;
          continue;
        }
        if (d2.tree_tex_id != draw.tree_tex_id || d2.mode.as_int() != draw.mode.as_int() ||
            sd2.first != first + count) {
          break;
        }
        count += sd2.second;
        next++;
      }

      prof.add_draw_call();
      lighting_census::note_world_draw(lighting_census::Kind::Tie);
      glDrawElements(tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      contact_record(draw_idx, next, first, count);
      shrub_contact_measurement::draw_elements(m_level_name, geom, idx, render_state->frame_idx, tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      draw_idx = next;
    }
    return;
  }

  for (size_t draw_idx = tree.category_draw_indices[(int)category];
       draw_idx < tree.category_draw_indices[(int)category + 1]; draw_idx++) {
    const auto& draw = tree.draws->operator[](draw_idx);
    const auto& multidraw_indices = tree.multidraw_offset_per_stripdraw[draw_idx];
    const auto& singledraw_indices = tree.draw_idx_temp[draw_idx];

    if (render_state->no_multidraw) {
      if (singledraw_indices.second == 0) {
        continue;
      }
    } else {
      if (multidraw_indices.second == 0) {
        continue;
      }
    }

    if (draw.tree_tex_id != last_texture) {
      if (draw.tree_tex_id >= 0) {
        bound_tex = m_textures->at(draw.tree_tex_id);
      } else {
        bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
        gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);

      last_texture = draw.tree_tex_id;
    }

    auto double_draw =
        setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::ETIE, bound_tex,
                                  draw_state_cache);

    prof.add_draw_call();

    if (render_state->no_multidraw) {
      lighting_census::note_world_draw(lighting_census::Kind::Tie);
      glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
      contact_record(draw_idx, draw_idx + 1, singledraw_indices.first, singledraw_indices.second);
      shrub_contact_measurement::draw_elements(m_level_name, geom, idx, render_state->frame_idx, tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
    } else {
      lighting_census::note_world_draw(lighting_census::Kind::Tie);
      glMultiDrawElements(
          tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first], GL_UNSIGNED_INT,
          &tree.multidraw_index_offset_buffer[multidraw_indices.first], multidraw_indices.second);
      for (int contact_i = 0; contact_i < multidraw_indices.second; ++contact_i) {
        const auto contact_slot = multidraw_indices.first + contact_i;
        contact_record(draw_idx, draw_idx + 1,
            uintptr_t(tree.multidraw_index_offset_buffer[contact_slot]) / sizeof(u32),
            tree.multidraw_count_buffer[contact_slot]);
      }
      shrub_contact_measurement::multi_draw_elements(m_level_name, geom, idx, render_state->frame_idx,
          tree.draw_mode, &tree.multidraw_count_buffer[multidraw_indices.first], GL_UNSIGNED_INT,
          &tree.multidraw_index_offset_buffer[multidraw_indices.first], multidraw_indices.second);
    }

    switch (double_draw.kind) {
      case DoubleDrawKind::NONE:
        break;
      default:
        ASSERT(false);
    }
  }
}

void Tie3::draw_debug_window() {
  ImGui::Checkbox("envmap 2nd draw", &m_draw_envmap_second_draw);
  ImGui::SliderFloat("envmap str", &m_envmap_strength, 0, 2);
  ImGui::SameLine();
  ImGui::Checkbox("All Visible", &m_debug_all_visible);
  ImGui::Checkbox("Hide Wind", &m_hide_wind);
  ImGui::SliderFloat("Wind Multiplier", &m_wind_multiplier, 0., 40.f);
  ImGui::Separator();
}

void TieProtoVisibility::init(const std::vector<std::string>& names) {
  vis_flags.resize(names.size());
  for (auto& x : vis_flags) {
    x = 1;
  }
  all_visible = true;
  name_to_idx.clear();
  size_t i = 0;
  for (auto& name : names) {
    name_to_idx[name].push_back(i++);
  }
}

void TieProtoVisibility::update(const u8* data, size_t size) {
  char name_buffer[256];  // ??

  if (!all_visible) {
    for (auto& x : vis_flags) {
      x = 1;
    }
    all_visible = true;
  }

  const u8* end = data + size;

  while (true) {
    int name_idx = 0;
    while (*data) {
      name_buffer[name_idx++] = *data;
      data++;
    }
    if (name_idx) {
      ASSERT(name_idx < 254);
      name_buffer[name_idx] = '\0';
      const auto& it = name_to_idx.find(name_buffer);
      if (it != name_to_idx.end()) {
        all_visible = false;
        for (auto x : name_to_idx.at(name_buffer)) {
          vis_flags[x] = 0;
        }
      }
    }

    while (*data == 0) {
      if (data >= end) {
        return;
      }
      data++;
    }
  }
}

void vector_min_in_place(math::Vector4f& v, float val) {
  for (int i = 0; i < 4; i++) {
    if (v[i] > val) {
      v[i] = val;
    }
  }
}

math::Vector4f vector_max(const math::Vector4f& v, float val) {
  math::Vector4f result;
  for (int i = 0; i < 4; i++) {
    result[i] = std::max(val, v[i]);
  }
  return result;
}

void do_wind_math(u16 wind_idx,
                  float* wind_vector_data,
                  const Tie3::WindWork& wind_work,
                  float stiffness,
                  float shear_boost,
                  // Grecharged-foliage-wind2: additive procedural breeze shear {x, z}, computed per
                  // instance in render_tree_wind. nullptr when the toggle is OFF (stock path).
                  const float* shear_add,
                  // Grecharged-foliage-wind2 ROUND 3: the wind tick to evaluate the drive at. The
                  // stock leg passes wind_work.wind_time (one tick per displayed frame); the
                  // restored 60 Hz leg walks it forward one tick per SUBSTEP, which is what the
                  // game does per frame on a 60 fps console.
                  u32 wind_time_now,
                  std::array<math::Vector4f, 4>& mat,
                  // Grecharged-foliage-wind2 SHEAR AUDIT (round 2). Round 1 shipped an effect the
                  // owner could not see, and the only evidence it had was a capture-derived pixel
                  // statistic — the class of proof he has since banned outright. This is the
                  // replacement, and it is exact: [0] receives |stock shear| (vf27, bit for bit
                  // what the untouched game applies) and [1] |applied shear| (vf27s, what THIS
                  // build applies). The shear is DIMENSIONLESS and, because it lands as
                  // `row.x += s.x * row.y`, it displaces a vertex by  s * (its height above the
                  // instance origin). So these two numbers, multiplied by a prototype's authored
                  // height from tie-census.txt, are the sway in METRES — no pixels involved.
                  // nullptr = no audit. Reading vf27/vf27s cannot change what is rendered.
                  float* audit_out = nullptr) {
  float* my_vector = wind_vector_data + (4 * wind_idx);
  const auto& work_vector = wind_work.wind_array[(wind_time_now + wind_idx) & 63];
  constexpr float cx = 0.5;
  constexpr float cy = 100.0;
  constexpr float cz = 0.0166;
  constexpr float cw = -1.0;

  // ld s1, 8(s5)                    # load wind vector 1
  // pextlw s1, r0, s1               # convert to 2x 64 bits, by shifting left
  // qmtc2.i vf18, s1                # put in vf
  float vf18_x = my_vector[2];
  float vf18_z = my_vector[3];

  // ld s2, 0(s5)                    # load wind vector 0
  // pextlw s3, r0, s2               # convert to 2x 64 bits, by shifting left
  // qmtc2.i vf17, s3                # put in vf
  float vf17_x = my_vector[0];
  float vf17_z = my_vector[1];

  // lqc2 vf16, 12(s3)               # load wind vector
  math::Vector4f vf16 = work_vector;

  // vmula.xyzw acc, vf16, vf1       # acc = vf16
  // vmsubax.xyzw acc, vf18, vf19    # acc = vf16 - vf18 * wind_const.x
  // vmsuby.xyzw vf16, vf17, vf19
  // # vf16 -= (vf18 * wind_const.x) + (vf17 * wind_const.y)
  vf16.x() -= cx * vf18_x + cy * vf17_x;
  vf16.z() -= cx * vf18_z + cy * vf17_z;

  // vmulaz.xyzw acc, vf16, vf19     # acc = vf16 * wind_const.z
  // vmadd.xyzw vf18, vf1, vf18
  // # vf18 += vf16 * wind_const.z
  math::Vector4f vf18(vf18_x, 0.f, vf18_z, 0.f);
  vf18 += vf16 * cz;

  // vmulaz.xyzw acc, vf18, vf19    # acc = vf18 * wind_const.z
  // vmadd.xyzw vf17, vf17, vf1
  // # vf17 += vf18 * wind_const.z
  math::Vector4f vf17(vf17_x, 0.f, vf17_z, 0.f);
  vf17 += vf18 * cz;

  // vitof12.xyzw vf11, vf11 # normal convert
  // vitof12.xyzw vf12, vf12 # normal convert

  // Grecharged-foliage-wind3 : l'etat AVANT la butee, pour que l'audit puisse dire si le ressort
  // est SATURE. `stock_rms` ne le pouvait pas : il porte deja `stiffness`, qui differe par
  // prototype (0,1 pour les palmiers, 0,25 pour le poisson suspendu de Sandover).
  const float rc_pre_x = vf17.x();
  const float rc_pre_z = vf17.z();

  // vminiw.xyzw vf17, vf17, vf0
  vector_min_in_place(vf17, 1.f);

  // qmfc2.i s3, vf18
  // ppacw s3, r0, s3

  // vmaxw.xyzw vf27, vf17, vf19
  auto vf27 = vector_max(vf17, cw);

  // vmulw.xyzw vf27, vf27, vf15
  vf27 *= stiffness;

  // Grecharged-foliage-wind: amplify ONLY the applied matrix shear, never the persisted
  // integrator state (my_vector below keeps the stock vf27). Boosting `stiffness` instead is
  // self-cancelling: vf27 feeds back into next frame's restoring term (cy=100 * vf17), so the
  // spring just stiffens and the visible sway barely changes. shear_boost == 1.0 (toggle OFF)
  // multiplies by the exact literal 1.0f => byte-identical stock arithmetic.
  // Grecharged-foliage-wind2: the additive breeze lands on the SAME applied-shear-only line — the
  // persisted integrator state (my_vector, written below) still stores the stock vf27, so the stock
  // spring keeps running untouched underneath and nothing accumulates or drifts.
  math::Vector4f vf27s = vf27 * shear_boost;
  if (shear_add) {
    vf27s.x() += shear_add[0];
    vf27s.z() += shear_add[1];
  }

  // vmulax.yw acc, vf0, vf0
  // vmulay.xz acc, vf27, vf10
  // vmadd.xyzw vf10, vf1, vf10
  mat[0].x() += vf27s.x() * mat[0].y();
  mat[0].z() += vf27s.z() * mat[0].y();

  // qmfc2.i s2, vf27
  if (!wind_work.paused) {
    my_vector[0] = vf27.x();
    my_vector[1] = vf27.z();
    my_vector[2] = vf18.x();
    my_vector[3] = vf18.z();
  }

  // vmulax.yw acc, vf0, vf0
  // vmulay.xz acc, vf27, vf11
  // vmadd.xyzw vf11, vf1, vf11
  mat[1].x() += vf27s.x() * mat[1].y();
  mat[1].z() += vf27s.z() * mat[1].y();

  // ppacw s2, r0, s2
  // vmulax.yw acc, vf0, vf0
  // vmulay.xz acc, vf27, vf12
  // vmadd.xyzw vf12, vf1, vf12
  mat[2].x() += vf27s.x() * mat[2].y();
  mat[2].z() += vf27s.z() * mat[2].y();

  // Grecharged-foliage-wind2: hand the two shear magnitudes back for the audit (see the parameter
  // comment). With the toggle OFF, shear_boost is the literal 1.0f and shear_add is nullptr, so
  // vf27s IS vf27 and the two values below are bit-identical — which is exactly how the audit line
  // proves OFF == stock at RUNTIME rather than by reading the source.
  if (audit_out) {
    audit_out[0] = std::sqrt(vf27.x() * vf27.x() + vf27.z() * vf27.z());
    audit_out[1] = std::sqrt(vf27s.x() * vf27s.x() + vf27s.z() * vf27s.z());
    audit_out[2] = vf27s.x();
    audit_out[3] = vf27s.z();
    audit_out[4] = vf27.x();
    audit_out[5] = vf27.z();
    // [6] etat brut du ressort AVANT stiffness ; [7] 1.0 si une composante a tape la butee.
    audit_out[6] = std::sqrt(rc_pre_x * rc_pre_x + rc_pre_z * rc_pre_z);
    audit_out[7] = (rc_pre_x > 1.f || rc_pre_x < cw || rc_pre_z > 1.f || rc_pre_z < cw) ? 1.f : 0.f;
  }

  //
  // if not paused
  // sd s3, 8(s5)
  // sd s2, 0(s5)
}

// Grecharged-foliage-wind3 : REAPPLIQUER le cisaillement deja calcule, sans integrer.
// Utilise sur une image qui ne porte AUCUN tick de logique (pas fixe arme, affichage au-dessus de
// 60 Hz : `time-adjust-ratio` vaut alors 0 et `wind-time` n'avance pas). Ne rien appliquer ferait
// revenir l'arbre a sa pose droite pour une image — un clignotement d'une image, pire que le
// defaut qu'on corrige. `my_vector[0..1]` porte EXACTEMENT le `vf27` ecrit par le dernier pas
// (do_wind_math ci-dessus), donc il n'y a rien a recalculer.
static void fw_apply_persisted_shear(u16 wind_idx,
                                     const float* wind_vector_data,
                                     float shear_boost,
                                     const float* shear_add,
                                     std::array<math::Vector4f, 4>& mat,
                                     float* audit_out) {
  const float* my_vector = wind_vector_data + (4 * wind_idx);
  const math::Vector4f vf27(my_vector[0], 0.f, my_vector[1], 0.f);
  math::Vector4f vf27s = vf27 * shear_boost;
  if (shear_add) {
    vf27s.x() += shear_add[0];
    vf27s.z() += shear_add[1];
  }
  for (int r = 0; r < 3; r++) {
    mat[r].x() += vf27s.x() * mat[r].y();
    mat[r].z() += vf27s.z() * mat[r].y();
  }
  if (audit_out) {
    audit_out[0] = std::sqrt(vf27.x() * vf27.x() + vf27.z() * vf27.z());
    audit_out[1] = std::sqrt(vf27s.x() * vf27s.x() + vf27s.z() * vf27s.z());
    audit_out[2] = vf27s.x();
    audit_out[3] = vf27s.z();
    audit_out[4] = vf27.x();
    audit_out[5] = vf27.z();
    // Aucune integration n'a eu lieu : il n'y a pas d'etat brut neuf a publier, et surtout pas de
    // NOUVELLE saturation a compter. Publier 0 ici gonflerait l'echantillon sans rien mesurer, donc
    // on republie l'etat persiste et on declare la butee non touchee.
    audit_out[6] = audit_out[0];
    audit_out[7] = 0.f;
  }
}

// lighting-ao-indirect : LE CALCUL D'INSTANCE DU CHEMIN VENT, FACTORISE.
//
// Il etait le debut de `render_tree_wind`, donc il ne tournait QUE dans la passe couleur — et la
// prepasse de profondeur, qui tire AVANT elle dans l'image, n'avait aucune matrice a consommer.
// Le rejouer une seconde fois ne repare rien : `do_wind_math` INTEGRE le ressort de ND dans
// `m_wind_vectors` a chaque appel, deux appels donneraient deux matrices donc deux z, et
// l'ecart que l'item corrige reviendrait par la bande.
//
// Il est donc MEMOISE par (arbre, image) : le PREMIER appelant de l'image calcule (la prepasse
// quand l'AO est armee, la passe couleur sinon), le second consomme EXACTEMENT la meme matrice.
// Consequence assumee, et c'est le seul choix qui tienne : quand la prepasse tire, le DMA TIE de
// l'image n'a pas encore ete lu, donc l'etat de vent (`m_wind_data`) est celui de l'image
// precedente, tandis que la camera est bien celle de CETTE image (SharedRenderState::camera_matrix
// vient d'etre recopiee depuis `data.camera.camera` juste avant `prepass::on_first_camera`). Le
// feuillage retarde d'une image sur le vent ; les deux passes, elles, voient le meme z.
void Tie3::update_wind_instances(Tree& tree,
                                 const math::Vector4f* cam_mat,
                                 SharedRenderState* render_state) {
  if (!tree.wind_draws || tree.wind_draws->empty() || !tree.instance_info) {
    return;
  }
  if (tree.wind_frame == render_state->frame_idx) {
    return;  // deja calcule pour cette image : la seconde passe consomme la MEME matrice
  }
  tree.wind_frame = render_state->frame_idx;

  // note: this isn't the most efficient because we might compute wind matrices for invisible
  // instances. TODO: add vis ids to the instance info to avoid this
  memset(tree.wind_matrix_cache.data(), 0, sizeof(float) * 16 * tree.wind_matrix_cache.size());
  // Grecharged-foliage-wind2: belt-and-braces for the audit's per-instance history. update_load
  // sizes this next to wind_matrix_cache; sizing it here too means no ordering assumption between
  // the two can turn an instrumentation array into an out-of-bounds write.
  if (tree.fw_prev_shear.size() < tree.instance_info->size() * 4) {
    tree.fw_prev_shear.assign(tree.instance_info->size() * 4, 0.f);
    tree.fw_prev_valid = false;
  }
  std::array<math::Vector4f, 4> cam;
  for (int i = 0; i < 4; i++) {
    cam[i] = cam_mat[i];
  }

  // foliage-wind (owner 2026-09-03) : la brise AJOUTEE au chemin VENT est la loi partagee
  // (foliage_wind::breeze_offset, jumelle de breeze.glsl), appliquee en CISAILLEMENT d'instance —
  // le seul terme que ce chemin sait ajouter. `rc_wind_boost` reste le litteral 1.0 : le ressort de
  // ND n'est jamais amplifie. Option ETEINTE => `rc_bend_u` = 0 => le pointeur additif n'est jamais
  // passe a do_wind_math => le chemin stock, au bit pres.
  const float rc_wind_boost = 1.0f;
  float rc_bend_u = 0.0f;    // flexion de couronne d'une plante de reference, unites monde
  float rc_flutter = 0.0f;   // part de fremissement de feuille
  float rc_t = 0.0f;
  float rc_dir_x = 0.7071f, rc_dir_z = 0.7071f;
  // Grecharged-foliage-wind3 (defaut D1) : combien de pas de 1/60 s cette image DESSINEE porte.
  // Lu sur `wind-time`, que GOAL avance d'un cran par pas de 1/60 s depuis cette phase. HORS du
  // basculement Recharged : l'owner demande que la brise NATIVE marche par defaut. A 60 images/s
  // le delta vaut 1 et tout ce qui suit est le chemin d'avant, au bit pres.
  const u32 rc_wt_now = m_wind_data.wind_time;
  if (m_wind_ticks_frame != render_state->frame_idx) {
    m_wind_ticks_frame = render_state->frame_idx;
    m_wind_ticks = fw_wind_ticks(rc_wt_now, m_wind_last_time, m_wind_time_seeded,
                                 m_wind_data.paused != 0);
  }
  const int rc_ticks = m_wind_ticks;
  bool rc_on = false;
  if (foliage_wind::enabled()) {
    rc_on = true;
    rc_bend_u = foliage_wind::bend_metres() * 4096.f;
    rc_flutter = foliage_wind::flutter_fraction();
    rc_t = foliage_wind::clock_seconds(render_state->frame_idx, foliage_wind::paused());
    foliage_wind::direction(&rc_dir_x, &rc_dir_z);
    static bool s_logged = false;
    if (!s_logged) {
      s_logged = true;
      // Renderer-side proof line (no captures): if this never appears the feature did not run.
      lg::info("[foliage-wind] TIE breeze ACTIVE bend={:.4f}m flutter={:.2f} instances={} "
               "local_ymax_known={}",
               rc_bend_u / 4096.f, rc_flutter, tree.instance_info->size(),
               tree.wind_local_ymax ? tree.wind_local_ymax->size() : 0);
    }
  }
  if (tree.fw_inst_flutter_amp.size() < tree.instance_info->size()) {
    tree.fw_inst_flutter_amp.assign(tree.instance_info->size(), 0.f);
  }
  if (tree.fw_inst_bend.size() < tree.instance_info->size() * 2) {
    tree.fw_inst_bend.assign(tree.instance_info->size() * 2, 0.f);
  }
  {
    // Preuve de cablage de D1, une ligne par course : si `ticks` ne monte jamais au-dessus de 1
    // sur un appareil qui rend a 15 images/s, le correctif n'agit pas.
    static bool s_rate_logged = false;
    if (!s_rate_logged && rc_ticks > 1) {
      s_rate_logged = true;
      lg::info("[foliage-wind] NATIVE RATE actif : cette image porte {} pas de 1/60 s "
               "(wind_time={}) — la brise de ND n'avance plus a la cadence de l'affichage",
               rc_ticks, rc_wt_now);
    }
  }

  for (size_t inst_id = 0; inst_id < tree.instance_info->size(); inst_id++) {
    auto& info = tree.instance_info->operator[](inst_id);
    auto& out = tree.wind_matrix_cache[inst_id];
    // auto& mat = tree.instance_info->operator[](inst_id).matrix;
    auto mat = info.matrix;

    ASSERT(info.wind_idx * 4 <= m_wind_vectors.size());
    // foliage-wind : la flexion de couronne de la loi partagee, convertie en cisaillement. Le
    // cisaillement deplace un sommet de `s x (sa hauteur monde au-dessus de l'origine de l'instance)`
    // (do_wind_math : `mat[r].x += s.x * mat[r].y`), donc `s = flexion / hauteur_monde` met la
    // couronne EXACTEMENT a la flexion que le chemin statique donne a une plante de meme taille —
    // c'est ce qui rend `wind_divergent_pairs` tenable entre un palm-02 (vent) et un palm-01
    // (statique) voisins. Le fremissement de feuille, lui, est par sommet (tie_wind.vert) : on lui
    // passe son amplitude en unites LOCALES du prototype, avec le gain de rafale de l'instant.
    // Essai 11 (owner 2026-09-04 : « ça twitch autant côté feuilles que le tronc ») : la flexion de
    // couronne AJOUTEE n'est plus un cisaillement de la matrice (lineaire du pied a la cime). Elle est
    // calculee ici en MONDE par la loi partagee, ramenee dans le repere LOCAL de l'instance (les
    // lignes 0 et 2 de la matrice NON cisaillee sont les axes locaux x et z en monde), et poussee par
    // instance a tie_wind.vert, qui la multiplie par le poids de hauteur (tronc rigide). Le ressort
    // de ND (do_wind_math) ne recoit plus AUCUN terme additif : `rc_add_ptr` reste nul, le chemin
    // natif est le chemin stock au bit pres, option allumee ou non.
    const float* rc_add_ptr = nullptr;
    float rc_flut_local = 0.f;
    float rc_bend_lx = 0.f, rc_bend_lz = 0.f;
    if (rc_bend_u > 0.0f && tree.wind_local_ymax && inst_id < tree.wind_local_ymax->size()) {
      const float h_loc = (*tree.wind_local_ymax)[inst_id];
      const float ys =
          std::sqrt(mat[1].x() * mat[1].x() + mat[1].y() * mat[1].y() + mat[1].z() * mat[1].z());
      const float h_u = h_loc * ys;  // hauteur monde de la plante
      const float xs2 = mat[0].x() * mat[0].x() + mat[0].y() * mat[0].y() + mat[0].z() * mat[0].z();
      const float zs2 = mat[2].x() * mat[2].x() + mat[2].y() * mat[2].y() + mat[2].z() * mat[2].z();
      if (h_u > 1.f && ys > 1e-6f && xs2 > 1e-12f && zs2 > 1e-12f) {
        const float w = foliage_law::size_factor(h_u / 4096.f);
        const float ph01 = (float)foliage_law::phase_u8((u64)inst_id) / 256.f;
        float ox = 0.f, oz = 0.f, gain = 0.f;
        foliage_wind::breeze_offset(mat[3].x(), mat[3].z(), rc_dir_x, rc_dir_z, ph01, rc_t, w,
                                    rc_bend_u, 0.f, &ox, &oz, &gain);
        // monde -> local : composante le long de chaque axe local, divisee par son echelle au carre
        // (le poids de hauteur du shader vaut 1 a la couronne, donc la couronne recoit `ox, oz`)
        rc_bend_lx = (ox * mat[0].x() + oz * mat[0].z()) / xs2;
        rc_bend_lz = (ox * mat[2].x() + oz * mat[2].z()) / zs2;
        rc_flut_local = rc_bend_u * w * rc_flutter * gain / ys;
        // ESSAI 16 : tie_wind.vert multiplie desormais par `hauteur x rampe d'extremite`, dont le
        // maximum sur le prototype est < 1. Sans cette division la POINTE recevrait moins que la
        // flexion de couronne de la loi, la plante bougerait moins qu'une voisine du chemin
        // STATIQUE de meme taille, et `wind_divergent_pairs` virerait au rouge. Un maximum nul
        // (prototype sans couronne) laisse la flexion telle quelle : la loi d'avant.
        const float wmax = (tree.wind_local_wmax && inst_id < tree.wind_local_wmax->size())
                               ? (*tree.wind_local_wmax)[inst_id]
                               : 0.f;
        if (wmax > 1e-4f) {
          rc_bend_lx /= wmax;
          rc_bend_lz /= wmax;
          rc_flut_local /= wmax;
        }
      }
    }
    tree.fw_inst_flutter_amp[inst_id] = rc_flut_local;
    tree.fw_inst_bend[inst_id * 2 + 0] = rc_bend_lx;
    tree.fw_inst_bend[inst_id * 2 + 1] = rc_bend_lz;
    // Grecharged-foliage-wind2: [0]/[1] = stock/applied shear magnitude, [2..5] = the signed
    // components, which is what the frame-to-frame difference below needs.
    float rc_audit[8] = {0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f};
    const float rc_stiff = info.stiffness * m_wind_multiplier;
    if (rc_ticks <= 0) {
      // Aucun tick de logique sur cette image : on reapplique, on n'integre pas.
      fw_apply_persisted_shear(info.wind_idx, m_wind_vectors.data(), rc_wind_boost, rc_add_ptr, mat,
                               rc_audit);
    } else {
      // `do_wind_math` ACCUMULE dans la matrice d'instance (`mat[0].x() += ...`), donc seul le
      // DERNIER pas a le droit d'y ecrire : laisser chaque sous-pas ecrire appliquerait le
      // cisaillement rc_ticks fois et publierait une tempete que personne ne voit. Les pas
      // intermediaires avancent l'integrateur contre une matrice jetable.
      for (int k = 0; k < rc_ticks - 1; k++) {
        std::array<math::Vector4f, 4> rc_scratch = mat;
        do_wind_math(info.wind_idx, m_wind_vectors.data(), m_wind_data, rc_stiff, 1.0f, nullptr,
                     rc_wt_now - (u32)(rc_ticks - 1) + (u32)k, rc_scratch, nullptr);
      }
      do_wind_math(info.wind_idx, m_wind_vectors.data(), m_wind_data, rc_stiff, rc_wind_boost,
                   rc_add_ptr, rc_wt_now, mat, rc_audit);
    }
    {
      float* prev = &tree.fw_prev_shear[inst_id * 4];
      const float dax = rc_audit[2] - prev[0], daz = rc_audit[3] - prev[1];
      const float dsx = rc_audit[4] - prev[2], dsz = rc_audit[5] - prev[3];
      fw_audit_accum(m_level_name, rc_audit[0], rc_audit[1], tree.fw_prev_valid,
                     std::sqrt(dsx * dsx + dsz * dsz), std::sqrt(dax * dax + daz * daz),
                     rc_audit[6], rc_audit[7] > 0.5f);
      prev[0] = rc_audit[2];
      prev[1] = rc_audit[3];
      prev[2] = rc_audit[4];
      prev[3] = rc_audit[5];
    }

    // vmulax.xyzw acc, vf20, vf10
    // vmadday.xyzw acc, vf21, vf10
    // vmaddz.xyzw vf10, vf22, vf10
    out[0] = cam[0] * mat[0].x() + cam[1] * mat[0].y() + cam[2] * mat[0].z();

    // vmulax.xyzw acc, vf20, vf11
    // vmadday.xyzw acc, vf21, vf11
    // vmaddz.xyzw vf11, vf22, vf11
    out[1] = cam[0] * mat[1].x() + cam[1] * mat[1].y() + cam[2] * mat[1].z();

    // vmulax.xyzw acc, vf20, vf12
    // vmadday.xyzw acc, vf21, vf12
    // vmaddz.xyzw vf12, vf22, vf12
    out[2] = cam[0] * mat[2].x() + cam[1] * mat[2].y() + cam[2] * mat[2].z();

    // vmulax.xyzw acc, vf20, vf13
    // vmadday.xyzw acc, vf21, vf13
    // vmaddaz.xyzw acc, vf22, vf13
    // vmaddw.xyzw vf13, vf23, vf0
    out[3] = cam[0] * mat[3].x() + cam[1] * mat[3].y() + cam[2] * mat[3].z() + cam[3];
  }
  tree.fw_prev_valid = true;  // the previous-frame shears are now populated for every instance
  // Le regime de brise de CETTE image, retenu pour la passe qui dessine (les deux le lisent).
  tree.fw_frame_on = rc_on;
  tree.fw_frame_t = rc_t;
  // Grecharged-foliage-wind3 : `on=` porte l'etat REEL du basculement, pas `frond>0 || amp>0`.
  // Le tour precedent avait NOMME ce defaut d'etiquette dans ses « honest gaps » sans le corriger :
  // une course avec le basculement ALLUME et les amplitudes mises a 0 par les proprietes vivantes
  // s'etiquetait `on=0`, donc une ligne qui n'etait PAS le chemin stock se presentait comme telle.
  // Il suit le CALCUL (une fois par arbre et par image), pas le dessin : la prepasse ne le double
  // pas.
  fw_audit_tick(m_level_name, render_state->frame_idx, rc_on, rc_bend_u / 4096.f,
                tree.wind_draws->size(), m_wind_data.paused, m_wind_data.wind_time, rc_ticks);
}

// lighting-ao-indirect : LE DESSIN DU CHEMIN VENT, FACTORISE — un seul corps pour les deux passes.
// `depth_only` = la prepasse de profondeur : MEME programme, MEMES buffers, MEMES uniformes de
// sommet, couleur masquee par l'appelant. Tout ce qui n'a de sens que pour la couleur (setup
// complet du programme, recepteur d'ombre, recensements, second draw d'echec d'alpha qui n'ecrit
// QUE de la couleur) est sous ce drapeau. Rend le nombre d'indices emis.
uint64_t Tie3::draw_tree_wind(int idx,
                              int geom,
                              const TfragRenderSettings* settings,
                              SharedRenderState* render_state,
                              ScopedProfilerNode* prof,
                              bool depth_only) {
  auto& tree = m_trees.at(geom).at(idx);
  if (!tree.wind_draws || tree.wind_draws->empty()) {
    return 0;
  }
  const bool rc_on = tree.fw_frame_on;
  const float rc_t = tree.fw_frame_t;
  uint64_t drawn = 0;

  auto shader_id = ShaderId::TIE_WIND;
  if (depth_only) {
    // Le MEME programme, sans re-televerser le bloc d'image : `ub_frame` porte DEJA la camera de
    // cette image (update_render_state_from_pc_settings l'a mis a jour juste avant la prepasse),
    // et `settings` n'existe pas ici. gl_Position de tie_wind.vert ne lit que `u_inst_camera`,
    // les `u_fw_*` et `hvdf_offset` du bloc : tous les trois sont poses ci-dessous ou deja a jour.
    render_state->shaders[shader_id].activate();
  } else {
    first_tfrag_draw_setup(settings->camera, render_state, shader_id);
  }
  // Grecharged-foliage-wind2: per-vertex FROND FLUTTER uniforms (tie_wind.vert). The matrix shear
  // above swings a palm rigidly; this is what actually makes the leaves move. u_fw_amp == 0 (toggle
  // OFF) makes the shader skip the whole block, so OFF renders the stock vertex path.
  // wind_draws vertices are PROTOTYPE-LOCAL (TieTree::unpack leaves matrix_idx == -1 groups
  // untransformed and this pass supplies the instance matrix as `camera`), which is what lets the
  // shader use distance-from-the-trunk-axis as the flutter weight.
  const GLuint fw_prog = render_state->shaders[shader_id].id();
  const GLint fw_amp_loc = glu::loc(fw_prog, "u_fw_amp");
  const GLint fw_time_loc = glu::loc(fw_prog, "u_fw_time");
  const GLint fw_phase_loc = glu::loc(fw_prog, "u_fw_phase");
  const GLint fw_height_loc = glu::loc(fw_prog, "u_fw_height");
  const GLint fw_bend_loc = glu::loc(fw_prog, "u_fw_bend");
  const GLint fw_reach_loc = glu::loc(fw_prog, "u_fw_reach");
  if (fw_amp_loc >= 0) {
    glUniform1f(fw_amp_loc, 0.f);  // par instance ci-dessous ; 0 = le bloc du shader est saute
  }
  if (fw_bend_loc >= 0) {
    glUniform2f(fw_bend_loc, 0.f, 0.f);
  }
  if (fw_reach_loc >= 0) {
    glUniform2f(fw_reach_loc, 0.f, 0.f);  // par instance ci-dessous ; 0 = `q` nul, rampe au plancher
  }
  if (fw_time_loc >= 0) {
    glUniform1f(fw_time_loc, rc_t);
  }
  if (!depth_only) {
    foliage_wind::mark_drawn(m_level_name, foliage_wind::kSystemTieWind, idx, geom);
  }
  // Grecharged-foliage-wind2: the flutter's one silent-failure mode. If the linked TIE_WIND program
  // does not expose these uniforms (shader blob stale, or the block optimised away), every
  // glUniform1f above is skipped and the leaves simply never deform — with no error anywhere.
  // A location of -1 in this line is that failure, stated out loud.
  {
    static bool s_fw_uni_logged = false;
    if (!s_fw_uni_logged) {
      s_fw_uni_logged = true;
      lg::info("[foliage-wind] TIE flutter uniforms amp_loc={} time_loc={} phase_loc={} "
               "height_loc={} bend_loc={} reach_loc={} (all >= 0 means the per-vertex flutter, "
               "the per-instance crown bend and the essai-16 tip ramp are live in the linked "
               "program)",
               fw_amp_loc, fw_time_loc, fw_phase_loc, fw_height_loc, fw_bend_loc, fw_reach_loc);
    }
  }
#ifdef OG_FEAT_PBR
  // Round-3 defect A/B: wind-tie foliage receives the sun N.L in-shader; bind the shadow
  // receiver so it also RECEIVES cast shadows. TIE_WIND is the active program here.
  if (!depth_only && (recharged_gating::on(recharged_gating::kLighting) ||
                      recharged_gating::on(recharged_gating::kRtLight)) &&
      pbr_shadow_state().valid) {
    pbr_shadow_bind_receiver(render_state->shaders[ShaderId::TIE_WIND].id(),
                             settings->camera.trans.data());
  }
#endif
  glBindVertexArray(tree.vao);
  glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
               render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);

  glActiveTexture(GL_TEXTURE10);
  // Gperf-particles round 3: bind the TOD texture selected at update time (the
  // ping-pong current, or the single texture when the flag is off).
  glBindTexture(GL_TEXTURE_2D, tree.tod_current);

  glActiveTexture(GL_TEXTURE0);
#ifdef __ANDROID__
  // GLES has no settable restart index (see render_tree_category above); the
  // fixed-index mode restarts on all-ones = UINT32_MAX for our u32 buffers.
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;

  int last_texture = -1;
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.wind_vertex_index_buffer);

  for (size_t draw_idx = 0; draw_idx < tree.wind_draws->size(); draw_idx++) {
    const auto& draw = tree.wind_draws->operator[](draw_idx);

    if (draw.tree_tex_id != last_texture) {
      if (draw.tree_tex_id >= 0) {
        bound_tex = m_textures->at(draw.tree_tex_id);
      } else {
        bound_tex = ((size_t)(-(draw.tree_tex_id + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(draw.tree_tex_id + 1)) : 0);
        gj2vis_probe_bg_slot(-(draw.tree_tex_id + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      last_texture = draw.tree_tex_id;
    }
    auto double_draw =
        setup_tfrag_shader_cached(render_state, draw.mode, shader_id, bound_tex, draw_state_cache);

    int off = 0;
    for (auto& grp : draw.instance_groups) {
      const bool vis_gated = m_debug_all_visible || tree.vis_temp.at(grp.vis_idx);
      // lighting-ao-indirect (A3) : LA PREPASSE NE FILTRE PAS PAR `vis_temp`, ET C'EST VOULU.
      // `tree.vis_temp` est rempli par `cull_check_all_slow` dans `setup_all_trees` (:971),
      // appele depuis `Tie3::render` au bucket 9 — APRES la prepasse, qui tire au bucket 6
      // (`prepass::on_first_camera`, background_common.cpp:2846) : en profondeur seule, ce
      // tableau porte la visibilite de l'image PRECEDENTE (:2141-2153 le disait deja).
      // Une prepasse de PROFONDEUR qui SUR-dessine est conservatrice — c'est exactement le choix
      // que le chemin TIE STATIQUE fait deja, lui qui dessine toutes ses `vis_groups` sans aucun
      // filtre de visibilite (`ensure_tie_full_ranges`, :1105-1160), et c'est pour ca qu'il ne
      // peut pas etre `absent`. Une prepasse qui SOUS-dessine, elle, laisse l'AO sans occluder la
      // ou l'image en a un : 3136 px mesures (`ao_geom_tie_absent_px`, sur les 3335 de
      // `ao_sway_gap_px`), identiques dans les deux bras donc etrangers au deplacement de sommet.
      // La passe COULEUR garde son filtre, INTACT.
      if (depth_only) {
        prepass::note_wind_group(vis_gated);
      } else if (!vis_gated) {
        off += grp.num;
        continue;  // invisible, skip.
      }

      glUniformMatrix4fv(glu::loc(render_state->shaders[shader_id].id(), "u_inst_camera"), 1,
                         GL_FALSE, tree.wind_matrix_cache.at(grp.instance_idx)[0].data());
      // foliage-wind : le fremissement de feuille PAR INSTANCE — amplitude locale (portant le gain
      // de rafale de l'instant), phase propre (la meme que le cisaillement CPU) et hauteur locale
      // du prototype. Tout est saute quand l'option est eteinte (amplitude 0).
      if (rc_on && fw_amp_loc >= 0) {
        const float fa = grp.instance_idx < tree.fw_inst_flutter_amp.size()
                             ? tree.fw_inst_flutter_amp[grp.instance_idx]
                             : 0.f;
        glUniform1f(fw_amp_loc, fa);
        if (fw_bend_loc >= 0 && grp.instance_idx * 2 + 1 < tree.fw_inst_bend.size()) {
          glUniform2f(fw_bend_loc, tree.fw_inst_bend[grp.instance_idx * 2 + 0],
                      tree.fw_inst_bend[grp.instance_idx * 2 + 1]);
        }
        if (fw_phase_loc >= 0) {
          glUniform1f(fw_phase_loc, (float)foliage_law::phase_u8((u64)grp.instance_idx) / 256.f);
        }
        if (fw_reach_loc >= 0) {
          const float r0 = (tree.wind_local_rmin && grp.instance_idx < tree.wind_local_rmin->size())
                               ? (*tree.wind_local_rmin)[grp.instance_idx]
                               : 0.f;
          const float rs =
              (tree.wind_local_rspan && grp.instance_idx < tree.wind_local_rspan->size())
                  ? (*tree.wind_local_rspan)[grp.instance_idx]
                  : 0.f;
          glUniform2f(fw_reach_loc, r0, rs);
        }
        if (fw_height_loc >= 0) {
          const float hl = (tree.wind_local_ymax && grp.instance_idx < tree.wind_local_ymax->size())
                               ? (*tree.wind_local_ymax)[grp.instance_idx]
                               : 0.f;
          glUniform1f(fw_height_loc, hl);
        }
      }

      if (prof) {
        prof->add_draw_call();
        prof->add_tri(grp.num);
      }

      if (!depth_only) {
        // Le recensement compte les draws MONDE de la passe couleur : la prepasse n'en est pas
        // une, l'y ajouter changerait le denominateur d'un autre item.
        lighting_census::note_world_draw(lighting_census::Kind::TieWind);
      }
      glDrawElements(tree.draw_mode, grp.num, GL_UNSIGNED_INT,
                     (void*)((off + tree.wind_vertex_index_offsets.at(draw_idx)) * sizeof(u32)));
      drawn += (uint64_t)grp.num;
      off += grp.num;

      // Le second draw d'echec d'alpha n'ecrit QUE de la couleur (glDepthMask(GL_FALSE)) : en
      // profondeur seule il ne peut rien ecrire du tout, et il laisserait le masque de profondeur
      // ferme derriere lui.
      switch (depth_only ? DoubleDrawKind::NONE : double_draw.kind) {
        case DoubleDrawKind::NONE:
          break;
        case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE: {
          if (prof) {
            prof->add_draw_call();
            prof->add_tri(grp.num);
          }
          const auto& afail_u = tfrag_alpha_uniforms(render_state->shaders[shader_id].id());
          if (afail_u.alpha_min != -1) {
            glUniform1f(afail_u.alpha_min, -10.f);
          }
          if (afail_u.alpha_max != -1) {
            glUniform1f(afail_u.alpha_max, double_draw.aref_second);
          }
          glDepthMask(GL_FALSE);
          // depth-mask toggled: cached mode's depth state is now stale.
          draw_state_cache.valid = false;
          lighting_census::note_world_draw(lighting_census::Kind::TieWind);
          glDrawElements(tree.draw_mode, draw.vertex_index_stream.size(), GL_UNSIGNED_INT,
                         (void*)0);
          break;
        }
        default:
          ASSERT(false);
      }
    }
  }
  return drawn;
}

void Tie3::render_tree_wind(int idx,
                            int geom,
                            const TfragRenderSettings& settings,
                            SharedRenderState* render_state,
                            ScopedProfilerNode& prof) {
  auto& tree = m_trees.at(geom).at(idx);
  if (!tree.wind_draws || tree.wind_draws->empty()) {
    return;
  }
  // Si la prepasse a deja calcule les matrices de cette image, cet appel ne fait rien : les deux
  // passes dessinent avec le MEME `u_inst_camera`.
  update_wind_instances(tree, settings.camera.camera, render_state);
  // lighting-ao-indirect (terme 3) : NOMME le sous-chemin VENT pour le recensement (stencil de
  // preuve seul, aucune couleur ecrite, inerte hors image sondee).
  prepass::proof_stencil_family(prepass::kProofFamTieWind);
  draw_tree_wind(idx, geom, &settings, render_state, &prof, /*depth_only=*/false);
}

Tie3AnotherCategory::Tie3AnotherCategory(const std::string& name,
                                         int my_id,
                                         Tie3* parent,
                                         tfrag3::TieCategory category)
    : BucketRenderer(name, my_id), m_parent(parent), m_category(category) {}

void Tie3AnotherCategory::draw_debug_window() {
  ImGui::Text("Child of this renderer:");
  m_parent->draw_debug_window();
}

void Tie3AnotherCategory::render(DmaFollower& dma,
                                 SharedRenderState* render_state,
                                 ScopedProfilerNode& prof) {
  auto first_tag = dma.current_tag();
  dma.read_and_advance();
  if (first_tag.kind != DmaTag::Kind::CNT || first_tag.qwc != 0) {
    fmt::print("Bucket renderer {} ({}) was supposed to be empty, but wasn't\n", m_my_id, m_name);
    ASSERT(false);
  }
  m_parent->render_from_another(render_state, prof, m_category);
}

Tie3WithEnvmapJak1::Tie3WithEnvmapJak1(const std::string& name, int my_id, int level_id)
    : Tie3(name, my_id, level_id, nullptr, tfrag3::TieCategory::NORMAL) {}

void Tie3WithEnvmapJak1::render(DmaFollower& dma,
                                SharedRenderState* render_state,
                                ScopedProfilerNode& prof) {
  Tie3::render(dma, render_state, prof);
  if (m_enable_envmap) {
    render_from_another(render_state, prof, tfrag3::TieCategory::NORMAL_ENVMAP);
  }
}

void Tie3WithEnvmapJak1::draw_debug_window() {
  ImGui::Checkbox("envmap", &m_enable_envmap);
  Tie3::draw_debug_window();
}
