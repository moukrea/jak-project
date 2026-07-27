#include "Loader.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>

#include "common/custom_data/MeshConsolidate.h"
#include "common/custom_data/MeshSubdivide.h"
#include "common/global_profiler/GlobalProfiler.h"
#include "common/log/log.h"
#include "common/versions/versions.h"
#include "common/util/FileUtil.h"
#include "common/util/Timer.h"
#include "common/util/compress.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#include "game/graphics/opengl_renderer/loader/LoaderStages.h"
#include "game/runtime.h"

#include "third-party/imgui/imgui.h"

Loader::Loader(const fs::path& base_path, int max_levels)
    : m_base_path(base_path), m_max_levels(max_levels) {
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

// Grecharged-hd-models: resolve a level's FR3 path, preferring an enhanced (jak2 HD) variant under
// fr3/enhanced/ when the ENHANCED MODELS toggle is on AND that file exists. Off / missing -> stock
// path, so OFF is byte-identical to stock.
static fs::path hd_fr3_path(const fs::path& base, const std::string& name) {
#ifdef OG_FEAT_HD_MODELS
  if (Gfx::recharged_active(Gfx::g_global_settings.recharged_enhanced_models)) {
    // Prefer the package-shipped custom fr3/enhanced/ when the custom root is set.
    if (auto custom_fr3 = file_util::get_custom_fr3_dir()) {
      auto custom_enhanced = *custom_fr3 / "enhanced" / fmt::format("{}.fr3", name);
      if (file_util::file_exists(custom_enhanced.string())) {
        // lg (not raw stdout): on Android only lg::* routes to logcat.
        lg::info("HD-MODELS fr3-select {}: ENHANCED (custom) {}", name, custom_enhanced.string());
        return custom_enhanced;
      }
    }
    auto enhanced = base / "enhanced" / fmt::format("{}.fr3", name);
    if (file_util::file_exists(enhanced.string())) {
      // lg (not raw stdout): on Android only lg::* routes to logcat.
      lg::info("HD-MODELS fr3-select {}: ENHANCED {}", name, enhanced.string());
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

      // Read back into the tfrag3::Level structure
      prof().begin_event("deserialize");
      Timer import_timer;
      auto result = std::make_unique<tfrag3::Level>();
      Serializer ser(decomp_data.data(), decomp_data.size());
      result->serialize(ser);
      double import_time = import_timer.getSeconds();
      prof().end_event();
      log_merc_models(lev, *result);

      // and finally "unpack", which creates the vertex data we'll upload to the GPU

      Timer unpack_timer;
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
  // Grecharged-master-toggle: seed the GLOBAL master before the first fr3-path resolution.
  Gfx::g_global_settings.recharged_master = read_persisted_recharged_master();
  // Grecharged-bundled-textures: seed the base-swap toggle before the first add_texture.
  Gfx::g_global_settings.recharged_textures = read_persisted_recharged_textures();
#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-models: seed the enhanced-models flag before the common FR3 (HD Jak+Daxter) is read,
  // since this runs in the renderer ctor before GOAL's per-frame push. Shared by desktop + Android.
  Gfx::g_global_settings.recharged_enhanced_models = read_persisted_enhanced_models();
#endif
  auto data = file_util::read_binary_file(hd_fr3_path(m_base_path, name));

  auto decomp_data = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp_data.data(), decomp_data.size());
  m_common_level.level = std::make_unique<tfrag3::Level>();
  m_common_level.level->serialize(ser);
  log_merc_models(name, *m_common_level.level);
  for (auto& tex : m_common_level.level->textures) {
    m_common_level.textures.push_back(add_texture(tex_pool, tex, true));
  }

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
      bytes_this_run += tex.w * tex.h * 4;
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

void Loader::update_blocking(TexturePool& tex_pool) {
  fmt::print("NOTE: coming out of blackout on next frame, doing all loads now...\n");

  bool missing_levels = true;
  while (missing_levels) {
    bool needs_run = true;

    while (needs_run) {
      needs_run = false;
      {
        std::unique_lock<std::mutex> lk(m_loader_mutex);
        if (!m_level_to_load.empty()) {
          m_file_load_done_cv.wait(lk, [&]() { return m_level_to_load.empty(); });
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
      }
    }

    {
      std::unique_lock<std::mutex> lk(m_loader_mutex);
      missing_levels = false;
      for (auto& des : m_desired_levels) {
        if (m_loaded_tfrag3_levels.find(des) == m_loaded_tfrag3_levels.end()) {
          fmt::print("blackout loader doing additional level {}...\n", des);
          missing_levels = true;
        }
      }
    }

    if (missing_levels) {
      set_want_levels(m_desired_levels);
    }
  }

  fmt::print("Blackout loads done. Current status:");
  std::unique_lock<std::mutex> lk(m_loader_mutex);
  for (auto& ld : m_loaded_tfrag3_levels) {
    fmt::print("  {} is loaded.\n", ld.first);
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
        lk.lock();
        m_loaded_tfrag3_levels[name] = std::move(lev);
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
