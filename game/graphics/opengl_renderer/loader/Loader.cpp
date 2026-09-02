#include "Loader.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifdef __ANDROID__
#include <malloc.h>
#endif
#include <set>

#include "common/custom_data/MeshConsolidate.h"
#include "common/custom_data/MeshSubdivide.h"
#include "common/global_profiler/GlobalProfiler.h"
#include "common/log/log.h"
#include "common/versions/versions.h"
#include "common/util/FileUtil.h"
#include "common/util/Timer.h"
#include "common/util/compress.h"
#include "common/util/rss_census.h"

#ifdef __ANDROID__
#include <malloc.h>
#endif

#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#include "game/graphics/opengl_renderer/loader/LoaderStages.h"
#ifdef OG_FEAT_PBR
#include "game/graphics/opengl_renderer/loader/PbrTestPattern.h"
#endif
#include "game/runtime.h"
#include "game/system/load_gate.h"

#include "third-party/imgui/imgui.h"

Loader::Loader(const fs::path& base_path, int max_levels)
    : m_base_path(base_path), m_max_levels(max_levels) {
#ifdef __ANDROID__
  // autoport 2026-08-25: Android's Scudo allocator caches freed blocks rather
  // than returning them. Harmless with 8 GB, fatal with 3 GB. Decay 0 = release
  // as soon as a block is free.
  mallopt(M_DECAY_TIME, 0);
#endif
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
const LevelData* Loader::get_tfrag3_level(const std::string& level_name) {
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  const auto& existing = m_loaded_tfrag3_levels.find(level_name);
  if (existing == m_loaded_tfrag3_levels.end()) {
    return nullptr;
  } else {
    existing->second->frames_since_last_used = 0;
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
void precompute_uv_density(tfrag3::Level& lev);
void release_uploaded_vertices(tfrag3::Level& lev, int systeme);
}  // namespace

static fs::path hd_fr3_path(const fs::path& base, const std::string& name) {
#ifdef OG_FEAT_HD_MODELS
  if (Gfx::recharged_active(Gfx::g_global_settings.recharged_enhanced_models)) {
    // EXTERNAL asset-pack path ONLY (never the APK custom pack — ND IP must stay external).
    auto enhanced = base / "enhanced" / fmt::format("{}.fr3", name);
    if (file_util::file_exists(enhanced.string())) {
      // lg (not raw stdout): on Android only lg::* routes to logcat.
      lg::info("HD-MODELS fr3-select {}: ENHANCED (external) {}", name, enhanced.string());
      return enhanced;
    }
  }
  lg::info("HD-MODELS fr3-select {}: STOCK (enhanced-toggle={})", name,
           Gfx::g_global_settings.recharged_enhanced_models);
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

      // OWNER REOPEN #13 (2026-07-24) + INSIGHT #2: after every tfrag/tie/shrub tree is unpacked, run
      // the GLOBAL cross-chunk/bucket/system weld — one spatial hash over the WHOLE level stitches
      // coincident positions across bucket AND system boundaries (the per-tree weld only stitched WITHIN
      // each tree => the owner's remaining long seam LINES were chunk boundaries), orients inward normals
      // outward via the walkable collision mesh, then averages across the welded seams with the crease
      // threshold. Only cross-tree seam verts change (single-tree verts keep the accepted per-tree normal).
      // Gated on the PBR / realtime-lighting features that actually consume the reconstructed normal: a
      // STOCK player (recharged master off) pays zero added load cost and stays byte-identical. Runs on
      // this loader thread (not the GL/main thread) behind the load screen, so no ANR.
      if (Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
          Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) {
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
      if (Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
          Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) {
        const auto cfg = tfrag3::mesh_consolidate_config_from_env();
        const bool do_shrub = (cfg.bits & tfrag3::kMeshBitNoShrub) == 0;
        // PRECOMPUTE FIRST (the owner's standing preference, and a hard requirement here: measured
        // on the Redmi the live pass costs 45.8 s of village1's load). The sidecar is baked offline
        // by tools/mesh_audit --bake and validated against the fr3's structure, so a rebuilt or
        // modded level falls through to the live pass instead of being corrupted.
        bool from_bake = false;
        if ((cfg.bits & tfrag3::kMeshBitForceLive) == 0) {
          auto p = scoped_prof("mesh-consolidate-sidecar");
          // Round 30 (delivery): ONE resolver, package-copy-wins, and the decision plus the
          // fingerprint of the bytes actually read land in files/asset_route.txt. The corrected
          // sidecars ride to the owner's phone inside the APK's custom pack — the 1.44 GB base pack
          // cannot — so this precedence IS the delivery route for every geometry fix.
          const auto name = tfrag3::mesh_consolidate_bake_name(result->level_name);
          const auto route = file_util::resolve_fr3_asset(g_game_version, name);
          from_bake = tfrag3::mesh_consolidate_apply_bake(*result, route.path.string(), do_shrub);
        }
        if (!from_bake) {
          auto p = scoped_prof("mesh-consolidate");
          tfrag3::MeshAuditReport audit;
          tfrag3::mesh_consolidate(*result, cfg, &audit);
          audit.game_name = version_to_game_name(g_game_version);
          const std::string text = tfrag3::format_mesh_audit(audit, cfg);
          lg::info("[mesh-consolidate] {}", text);
          tfrag3::mesh_audit_append_file(text);
        }
      }

      // Grecharged-pbr-realtime-fusion round #19 (supervisor device measurement 2026-07-25): the
      // hardware tessellator maxes out at GL_MAX_TESS_GEN_LEVEL (64) PER PATCH, so a 3-5 m tfrag
      // ground triangle cannot be brought anywhere near the ~2.5 cm segment a centimetre-scale
      // height feature needs — measured on the ground band, tessellation moved 0.77/255 of a pixel
      // against displacement-OFF while the parallax it replaces moved 2.27. The industry answer is
      // mesh prep, not shader tuning: hand the tessellator SMALLER PATCHES. This pass splits every
      // tess-eligible tfrag triangle whose longest edge exceeds the threshold, conformally (green
      // closure, no T-vertices), with midpoints that are exact averages of their two parents.
      // It runs AFTER the consolidation on purpose: the .meshweld sidecar's fingerprint is the
      // per-tree vertex/index count of the ORIGINAL geometry, so the owner-validated precompute
      // keeps validating untouched, and every midpoint inherits already-snapped positions, already
      // smoothed normals and already-computed seam weights — which is exactly why a shared edge
      // cannot tear: both sides average identical endpoints and land on identical midpoints.
      // Gated on the tessellation displacement mode, so parallax and stock pay nothing.
      {
        auto scfg = tfrag3::mesh_subdiv_config_from_env();
        const auto& gs = Gfx::g_global_settings;
        bool want = Gfx::recharged_active(gs.recharged_pbr_enable) &&
                    gs.recharged_pbr_displacement == 2;
        if (scfg.forced_max_edge_m >= 0.f) {
          want = scfg.forced_max_edge_m > 0.f;  // prop/env override, for the device A/B
        }
        // Gprecompute-deterministic-bake (owner 2026-08-26: « ca devrait etre une option ajustable et
        // pas un truc qui se fait automatiquement »). The ROUND COUNT is a user setting now, not a
        // constant: 0 turns the refinement off outright, 1 is the shipped default, 2-3 for machines
        // with the budget. The debug prop/env still outranks it so an A/B stays possible.
        if (scfg.forced_max_rounds < 0) {
          scfg.max_rounds = std::max(0, std::min(6, gs.recharged_mesh_subdiv_rounds));
        }
        if (scfg.max_rounds <= 0) {
          want = false;  // explicitly asked for no refinement
        }
        if (want && scfg.max_edge_m > 0.f) {
          auto p = scoped_prof("mesh-presubdivide");
          // Only the geom LOD TFragment actually draws, and only materials that ship a height map:
          // a surface with no displacement SOURCE cannot be displaced at any tessellation level, so
          // refining it would be pure vertex cost (measured on village1's near ground: 62-77% of it).
          scfg.only_geom = Gfx::g_global_settings.lod_tfrag;
          // TIE pass (off unless debug.opengoal.mesh.subdivtie / OG_MESH_SUBDIV_TIE says otherwise;
          // Tie3 has no tessellation program, so TIE relief comes from per-pixel POM and extra
          // triangles buy nothing — see SubdivConfig::include_tie). Same reasoning as lod_tfrag:
          // only the geom LOD Tie3 actually draws is worth refining.
          scfg.only_geom_tie = Gfx::g_global_settings.lod_tie;
          std::function<bool(const tfrag3::Texture&)> has_height;
#ifdef OG_FEAT_PBR
          has_height = [](const tfrag3::Texture& t) {
            return custom_tex::has_suffixed(t.debug_tpage_name, t.debug_name, "_height",
                                            custom_tex::base_source(t.debug_tpage_name,
                                                                    t.debug_name));
          };
#endif
          tfrag3::SubdivStats sst;
          tfrag3::SubdivStats sst_tie;
          tfrag3::mesh_presubdivide_level(*result, scfg, &sst, has_height, &sst_tie);
          // ROUND 32 — the refinement INVENTS vertices AFTER mesh_consolidate's pass 12 / 12c have
          // run, and interpolates their frames: a midpoint normal is the normalized sum of its
          // parents' (MeshSubdivide.cpp:273-282) and its tangent is the summed T carrying parent A's
          // handedness verbatim (MeshSubdivide.cpp:367-380), re-orthogonalised against nothing. On
          // village1 that is roughly a third of every vertex the tessellator touches, created after
          // the only passes that check them. So re-establish both invariants here, on the refined
          // mesh: the displacement-sign one (dot(N_v, outward(f)) > 0 at every corner of every face)
          // and the parallax one (T valid for every face that shares it). Both are per-tree, need no
          // weld and no authority, and cost well under a second on village1. tools/tess_sign makes
          // the SAME call pair in the SAME order after its own subdivision, so what is graded
          // offline is what loads here.
          u64 pr_ok = 0, pr_unsat = 0, pr_den = 0;
          const u64 pr_fix =
              tfrag3::mesh_positivity_repair_level(*result, &pr_ok, &pr_unsat, &pr_den);
          u64 tr_ok = 0, tr_unsat = 0, tr_den = 0;
          const u64 tr_fix =
              tfrag3::retangent_positive_from_final_normals(*result, &tr_ok, &tr_unsat, &tr_den);
          lg::info(
              "[mesh-subdiv] level={} post-subdivision positivity: normals den={} ok={} repaired={} "
              "unsat={} | tangents den={} ok={} repaired={} unsat={}",
              result->level_name, pr_den, pr_ok, pr_fix, pr_unsat, tr_den, tr_ok, tr_fix, tr_unsat);
          std::string text = fmt::format("===== PRE-SUBDIVISION level={} =====\n{}",
                                         result->level_name,
                                         tfrag3::format_subdiv_stats(sst, scfg));
          if (scfg.include_tie) {
            // only when the TIE pass actually ran, so the log is not polluted with a zero block.
            text += tfrag3::format_subdiv_stats(sst_tie, scfg, "tie");
          }
          lg::info("[mesh-subdiv] {}", text);
          tfrag3::mesh_audit_append_file(text);
        }
      }

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
  Gfx::g_global_settings.recharged_master = read_persisted_recharged_master();
  // Grecharged-bundled-textures: seed the base-swap toggle before the first add_texture.
  Gfx::g_global_settings.recharged_textures = read_persisted_recharged_textures();
#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-models: seed the enhanced-models flag before the common FR3 (HD Jak+Daxter) is read,
  // since this runs in the renderer ctor before GOAL's per-frame push. Shared by desktop + Android.
  Gfx::g_global_settings.recharged_enhanced_models = read_persisted_enhanced_models();
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
  for (auto& tex : m_common_level.level->textures) {
    m_common_level.textures.push_back(add_texture(tex_pool, tex, true));
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
      data.textures.push_back(add_texture(texture_pool, tex, false));
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

// autoport 2026-08-26 — LIBERER LES SOMMETS CPU APRES TELEVERSEMENT.
// `unpacked.vertices` = 57,0 Mo par niveau (A50-LEVRAM, village1), le plus gros poste des
// 122,1 Mo qu'un niveau garde en RAM. Ils sont deja dans le GPU. Pour TFRAG et TIE, les seuls
// lecteurs apres chargement sont les trois mesures de densite UV du chemin PBR, appelees une
// fois par niveau DEPUIS LE RENDU — donc trop tard pour liberer. On mesure ici, on memorise,
// on libere.
// SHRUB EST EPARGNE : `Shrub::update_load` (Shrub.cpp:191, :203, :336) lit `unpacked.vertices`
// DIRECTEMENT — compte de sommets, LUT d'ancrage de vent, liste d'index d'ombre — et le RENDU
// l'appelle APRES la fin du chargement. Sa densite UV est mesuree ici sur des sommets vivants.
// Les INDEX restent : TFragment leur passe `unpacked.indices.data()` a chaque frame.
// MESURE SEULE. Elle lit les sommets CPU des TROIS systemes, donc elle doit tourner tant
// qu'AUCUN d'eux n'est rendu. Son appelant est la boucle d'etapes, JUSTE APRES l'etape
// `texture` : c'est `add_texture` qui inscrit les materiaux PBR du niveau au registre que la
// boucle ci-dessous interroge, et a cet instant tfrag n'a pas encore televerse, donc les trois
// systemes portent encore leurs sommets. Les liberations suivent, par systeme.
// Ne mesurer que ce que le rendu mesurerait : les textures portant un materiau PBR.
// MEME CLE QUE LES TROIS CONSOMMATEURS REELS (TFragment.cpp:373, Tie3.cpp:346, Shrub.cpp:140) :
// `pbr_material_key(debug_tpage_name, debug_name)`. Avec la seule `debug_name`, le cache serait
// rempli pour un ENSEMBLE DIFFERENT de textures, le rendu raterait le cache, parcourrait des
// sommets liberes et retomberait sur la densite constante 0.5 — un faux silencieux sur le POM.
void precompute_uv_density(tfrag3::Level& lev) {
  for (size_t ti = 0; ti < lev.textures.size(); ++ti) {
    const auto* mm = custom_tex::find_pbr_material(custom_tex::pbr_material_key(
        lev.textures[ti].debug_tpage_name, lev.textures[ti].debug_name));
    if (!mm) {
      continue;
    }
    // Gpbr-props-reach-draw : une matiere AUTHOREE SANS CARTE est desormais inscrite au registre
    // (c'etait le defaut). Elle n'a rien qui lise la densite UV — trois marches de geometrie pour
    // un nombre que personne ne consulte.
    if (!(mm->normal_tex || mm->rough_tex || mm->metal_tex || mm->ao_tex || mm->height_tex ||
          mm->specular_tex || mm->emissive_tex)) {
      continue;
    }
    u32 n = 0;
    const float d_tfrag = measure_uv_density_tfrag(lev, (s32)ti, &n);
    uv_density_store(lev, 0, (s32)ti, d_tfrag, n);
    n = 0;
    const float d_tie = measure_uv_density_tie(lev, (s32)ti, &n);
    uv_density_store(lev, 1, (s32)ti, d_tie, n);
    n = 0;
    const float d_shrub = measure_uv_density_shrub(lev, (s32)ti, &n);
    uv_density_store(lev, 2, (s32)ti, d_shrub, n);
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
void release_uploaded_merc_vertices(tfrag3::Level& lev) {
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
  for (auto& [name, lev] : m_loaded_tfrag3_levels) {
    if (lev->frames_since_last_used > 180 &&
        std::find(m_desired_levels.begin(), m_desired_levels.end(), name) ==
            m_desired_levels.end()) {
      return &name;
    }
  }

  for (const auto& [name, lev] : m_loaded_tfrag3_levels) {
    if (lev->frames_since_last_used > 180) {
      return &name;
    }
  }
  return nullptr;
}

void Loader::update(TexturePool& texture_pool) {
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
    for (auto& [name, lev] : m_loaded_tfrag3_levels) {
      if (std::find(m_active_levels.begin(), m_active_levels.end(), name) ==
          m_active_levels.end()) {
        lev->frames_since_last_used++;
      } else {
        lev->frames_since_last_used = 0;
      }
    }
  }

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
        // La densite UV se mesure JUSTE APRES `texture` et pas avant : elle ne parcourt que les
        // textures qui portent un materiau PBR, et c'est `add_texture` — donc l'etape `texture`
        // elle-meme — qui INSCRIT les materiaux de ce niveau au registre. La mesurer plus tot
        // (dans le fil de chargement, par exemple) trouverait un registre vide pour ce niveau,
        // n'ecrirait aucun echantillon, et le rendu retomberait en silence sur la densite
        // constante 0,5 : le faux vert exact que ce cache existe pour empecher.
        // A cet instant les sommets des TROIS systemes sont encore la — tfrag n'a pas encore
        // televerse — donc la mesure voit tout ce qu'elle doit voir.
        if (done && stage->name() == "texture" && !lev->cpu_geo_released[1]) {
          precompute_uv_density(*lev->level);
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
        glFinish();
        fprintf(stderr, "F1D-LOADSYNC lev=%s load_id=%llu glFinish at load completion\n",
                name.c_str(), (unsigned long long)lev->load_id);
#endif
        report_level_ram(name, *lev->level, "charge");
        report_merc_detail(name, *lev->level, "charge");
        // ARME 2026-08-26. Les sommets CPU de TFRAG et TIE partent apres televersement.
        // Ce qui rend le geste sur : la densite UV du chemin PBR est MESUREE ET MEMORISEE juste
        // avant la liberation (meme cle que les trois consommateurs :
        // pbr_material_key(debug_tpage_name, debug_name)), donc leurs lectures tardives
        // (`Tie3::load_from_fr3_data`, `TFragment::handle_initialization`, appelees par le RENDU
        // APRES ce point malgre leur nom) trouvent le cache au lieu des sommets.
        // SHRUB EST EPARGNE : `Shrub::update_load` lit ses sommets DIRECTEMENT (compte, LUT de
        // vent, index d'ombre) et pas seulement pour la densite — les liberer casse l'herbe et
        // les ombres. Les INDEX de tous les systemes restent : le rendu les relit chaque frame.
        // La fonction s'abstient aussi sur les niveaux a herbe vive (rescan a la demande du menu).
        // REPLI : le cas normal libere DES LA FIN DE L'ETAPE `tfrag` (voir la boucle d'etapes
        // plus haut) ; on ne passe ici que si cette etape n'a pas ete atteinte. Le drapeau
        // garantit UN SEUL passage — la mesure de densite UV n'est pas rejouable.
        // Repli : une etape n'a pas ete atteinte. La mesure ne se rejoue QUE si RIEN n'est
        // encore parti : relancee apres une liberation partielle, elle reecrirait le cache du
        // systeme deja libere avec zero echantillon, ce qui est pire que de ne rien ecrire.
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
        double ms_uv = 0.0, ms_rel = 0.0, ms_merc = 0.0, ms_rap = 0.0;
        if (!lev->cpu_geo_released[0] && !lev->cpu_geo_released[1]) {
          Timer t0;
          precompute_uv_density(*lev->level);
          ms_uv = t0.getMs();
        }
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
        fmt::print("LSWIN-COUT niveau={} uv_ms={:.1f} liberation_ms={:.1f} merc_ms={:.1f} "
                   "rapport_ms={:.1f} total_ms={:.1f}\n",
                   name, ms_uv, ms_rel, ms_merc, ms_rap, t_pret.getMs());
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
      auto to_unload = get_most_unloadable_level();
      if (to_unload) {
        auto& lev = m_loaded_tfrag3_levels.at(*to_unload);
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
#ifdef OG_FEAT_PBR
          // Grecharged-managed-assets: the companion PBR maps live in their own
          // registry, not in lev->textures, so eviction used to leak them (up to
          // 7 full-resolution textures per material, freed only if a later level
          // happened to re-register the same name). Release them with the level;
          // the ids join the same throttled garbage list as the base textures.
          const auto dead = custom_tex::release_pbr_material(
              custom_tex::pbr_material_key(tex.debug_tpage_name, tex.debug_name));
          // + thickness_tex: our own map, added after this branch's base. Leaving it out
          // would have made the branch's leak fix leak exactly one texture per material.
          for (u32 id : {dead.normal_tex, dead.rough_tex, dead.metal_tex, dead.ao_tex, dead.height_tex,
                         dead.specular_tex, dead.emissive_tex, dead.thickness_tex}) {
            // the shared test-pattern maps are owned by pbr_testpattern, never freed here
            if (id && !pbr_testpattern::owns(id)) {
              m_garbage_textures.push_back(id);
            }
          }
#endif
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
            // que le VBO de sommets ci-dessus. (Note en passant, PAS corrigee ici parce qu'elle
            // est anterieure et hors perimetre : `tangent_buffer` n'est collecte NULLE PART.)
            m_garbage_buffers.push_back(tie_tree.sway_buffer);
            m_garbage_buffers.push_back(tie_tree.index_buffer);
          }
        }

        for (auto& tfrag_geo : lev->tfrag_vertex_data) {
          for (auto& tfrag_buff : tfrag_geo) {
            m_garbage_buffers.push_back(tfrag_buff);
          }
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

        // autoport 2026-08-26 : la cle du cache de densite UV est un `const tfrag3::Level*`.
        // Sans cet oubli, l'allocateur peut reutiliser l'adresse du niveau evince pour le
        // suivant et rendre un FAUX HIT (densite d'un autre niveau, POM faux et silencieux).
        // `lev` est la reference prise plus haut sur `m_loaded_tfrag3_levels.at(*to_unload)`.
        uv_density_forget_level(*lev->level);
        load_gate::mark_level_evicted(*to_unload);
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
    // it->second.front().parent_level->frames_since_last_used = 0;
    return it->second.front();
  } else {
    return std::nullopt;
  }
}
