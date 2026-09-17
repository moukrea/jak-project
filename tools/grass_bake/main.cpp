// Grecharged-grass-precompute-mode: OFFLINE grass baker CLI (desktop only).
//
// Loads a level .fr3, runs the GL-free grass placement scan (grass_bake::scan_level)
// at the slider-max density, and writes a compact <level>.grassbake table file that
// the Android runtime loads instead of doing the (ANR-inducing) live scan.
//
// Usage: grass_bake <level-name> [--fr3-dir <dir>] [--out <path>] [--density <pct>]

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"
#include "common/custom_data/Tfrag3Data.h"

#include "game/graphics/opengl_renderer/GrassBakeCore.h"

#include "fmt/format.h"

// NOTE: FileUtil.h already defines `namespace fs = ghc::filesystem`; reuse it.

static void usage() {
  fmt::print(
      "Usage: grass_bake <level-name> [--fr3-dir <dir>] [--out <path>] [--density <pct>]\n"
      "                   [--preset <slug>]\n"
      "  <level-name>   e.g. training (loads <fr3-dir>/<level>.fr3)\n"
      "  --fr3-dir DIR  fr3 directory (default: <repo>/out/jak1/fr3)\n"
      "  --out PATH     output path (default: <fr3-dir>/<level>[.<preset>].grassbake)\n"
      "  --density PCT  bake candidate density (default: 250 = slider max)\n"
      "  --preset SLUG  Ggrass-density-presets: cuit LE palier nomme (very-low|low|medium|high|\n"
      "                 very-high). Pose la densite du palier ET le nom de sortie\n"
      "                 <fr3-dir>/<level>.<slug>.grassbake. Le moteur ne charge plus que ces\n"
      "                 fichiers-la : un bake sans palier dans le nom ne sera jamais resolu.\n"
      "  --dump PREFIX  write PREFIX_instances.csv + PREFIX_tris.csv of the ship-default\n"
      "                 (slider 150) expansion, for offline placement analysis\n"
      "  --weld-stats   run the GLOBAL cross-chunk/bucket/system vertex weld (REOPEN #13) and print\n"
      "                 its stats (writes <repo>/pbr_tan_diag.txt), then exit without the grass scan\n"
      "  --overlay-census  grass-overlay-meshes : cherche les paires de triangles de sol qui se\n"
      "                 superposent (geometrie) et les croise avec le materiau de collision, puis\n"
      "                 classe chaque superposition. Lecture pure, il n'ecrit rien.\n"
      "  --overlay-selftest  le CONTROLE POSITIF de --overlay-census sur un niveau fabrique.\n"
      "  --edge-census  grass-edge-truth : classe CHAQUE arete de sol dans l'une des huit\n"
      "                 classes de la SPEC, le bord sur le vide etant etabli par une SONDE DE\n"
      "                 PLANCHER geometrique et non par l'absence de voisin. Lecture pure.\n"
      "  --edge-selftest  le banc NOMME de --edge-census : dix cas geometriques, dix-neuf aretes,\n"
      "                 reponses attendues declarees avant la course.\n"
      "  --clump-census  grass-clumps : mesure le regroupement des racines en touffes — voisinage\n"
      "                 moyen des racines livrees CONTRE celui du tirage uniforme sur les memes\n"
      "                 brins, dispersion du compte et du rayon par touffe. Lecture pure.\n"
      "  --clump-nest PCT  rejoue le scan a CE palier et compare : origines de touffe qui bougent,\n"
      "                 et prefixe des candidats. Les deux doivent rendre zero.\n"
      "  --surface-census  grass-surface-truth : croise les DEUX sources de classement d'une\n"
      "                 surface (nom de texture de rendu, materiau de collision `pat` bits 6..11),\n"
      "                 imprime le recensement en `cle=valeur` et sort SANS cuire ni ecrire quoi\n"
      "                 que ce soit. Lecture pure : il ne touche aucun `.grassbake`.\n"
      "  --soft-surface-census  soft-surface-truth : les MEMES deux sources, pour sand/snow/\n"
      "                 deepsnow (SPEC-surfaces-meubles sections 1 et 11). Publie le desaccord,\n"
      "                 le litige avec l'herbe avant arbitrage, et la classe resolue. Lecture\n"
      "                 pure : il sort avant `scan_level` et n'ecrit aucun fichier.\n");
}

int main(int argc, char** argv) {
  std::string level_name;
  std::string fr3_dir;
  std::string out_path;
  std::string dump_prefix;
  bool weld_stats = false;  // OWNER REOPEN #13: run the GLOBAL cross-chunk weld offline + print its stats
  bool surface_census = false;  // grass-surface-truth : lit et croise les deux sources, n'ecrit rien
  bool soft_surface_census = false;
  bool soft_support_map_on = false;  // soft-surface-truth : les memes deux sources, pour sable/neige
  bool overlay_census = false;  // grass-overlay-meshes : cherche les meshes poses sur l'herbe
  bool overlay_selftest_only = false;  // ... le controle positif seul, sans niveau
  bool edge_census_on = false;    // grass-edge-truth : classe les aretes de sol, n'ecrit rien
  bool edge_selftest_only = false;  // ... le banc nomme seul
  bool trans_census_on = false;  // grass-path-transitions : mesure la transition au bord des chemins
  bool clump_census_on = false;  // grass-clumps : mesure le regroupement des racines en touffes
  float nest_pct = 0.0f;         // grass-clumps : palier de comparaison pour la nidification (0 = off)
  float density = 250.0f;  // slider maximum; runtime slider densities are exact prefixes
  std::string preset_slug;  // Ggrass-density-presets: palier nomme (vide = comportement historique)

  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto need_val = [&](const char* name) -> std::string {
      if (i + 1 >= argc) {
        fmt::print("error: {} requires a value\n", name);
        usage();
        std::exit(2);
      }
      return argv[++i];
    };
    if (a == "--fr3-dir") {
      fr3_dir = need_val("--fr3-dir");
    } else if (a == "--out") {
      out_path = need_val("--out");
    } else if (a == "--dump") {
      dump_prefix = need_val("--dump");
    } else if (a == "--weld-stats") {
      weld_stats = true;
    } else if (a == "--surface-census") {
      surface_census = true;
    } else if (a == "--soft-surface-census") {
      soft_surface_census = true;
    } else if (a == "--soft-support-map") {
      soft_support_map_on = true;
    } else if (a == "--overlay-census") {
      overlay_census = true;
    } else if (a == "--overlay-selftest") {
      overlay_census = true;
      overlay_selftest_only = true;
    } else if (a == "--edge-census") {
      edge_census_on = true;
    } else if (a == "--edge-selftest") {
      edge_census_on = true;
      edge_selftest_only = true;
    } else if (a == "--transition-census") {
      trans_census_on = true;
    } else if (a == "--clump-census") {
      clump_census_on = true;
    } else if (a == "--clump-nest") {
      nest_pct = std::stof(need_val("--clump-nest"));
    } else if (a == "--density") {
      density = std::stof(need_val("--density"));
    } else if (a == "--preset") {
      preset_slug = need_val("--preset");
      int found = -1;
      for (int i2 = 0; i2 < grass_bake::kDensityPresetCount; ++i2) {
        if (preset_slug == grass_bake::kDensityPresets[i2].slug) {
          found = i2;
        }
      }
      if (found < 0) {
        fmt::print("error: palier inconnu '{}' — attendus :", preset_slug);
        for (int i2 = 0; i2 < grass_bake::kDensityPresetCount; ++i2) {
          fmt::print(" {}", grass_bake::kDensityPresets[i2].slug);
        }
        fmt::print("\n");
        return 2;
      }
      density = grass_bake::kDensityPresets[found].pct;
    } else if (a == "-h" || a == "--help") {
      usage();
      return 0;
    } else if (!a.empty() && a[0] == '-') {
      fmt::print("error: unknown option '{}'\n", a);
      usage();
      return 2;
    } else if (level_name.empty()) {
      level_name = a;
    } else {
      fmt::print("error: unexpected extra argument '{}'\n", a);
      usage();
      return 2;
    }
  }

  if (level_name.empty()) {
    fmt::print("error: missing <level-name>\n");
    usage();
    return 2;
  }

  // Resolve the project dir FIRST, and ALWAYS.
  //
  // Ggrass-density-presets : c'etait un defaut, et il n'apparaissait qu'avec `--fr3-dir`. Le
  // chemin du projet n'etait initialise que dans la branche « pas de --fr3-dir » ; or le scan
  // appelle `file_util::get_jak_project_dir()` plus bas (chemin de diagnostic du weld TIE), qui
  // ASSERTE si l'initialisation n'a pas eu lieu — l'outil mourait donc sur
  // « Assertion failed: 'g_file_path_info.initialized' » des qu'on lui donnait un repertoire
  // explicite. On initialise inconditionnellement ; l'echec n'est fatal que si on avait besoin du
  // chemin par defaut.
  const bool have_project = file_util::setup_project_path({});
  if (fr3_dir.empty()) {
    if (!have_project) {
      fmt::print(
          "error: could not resolve the jak-project directory; pass --fr3-dir explicitly.\n");
      return 1;
    }
    fr3_dir = (file_util::get_jak_project_dir() / "out" / "jak1" / "fr3").string();
  }

  fs::path fr3_path = fs::path(fr3_dir) / fmt::format("{}.fr3", level_name);
  if (out_path.empty()) {
    // Ggrass-density-presets : avec --preset, le nom PORTE le palier. C'est ce qui rend
    // « le bake charge est celui du palier demande » verifiable depuis le systeme de fichiers,
    // sans ouvrir le fichier.
    out_path = preset_slug.empty()
                   ? (fs::path(fr3_dir) / fmt::format("{}.grassbake", level_name)).string()
                   : (fs::path(fr3_dir) / fmt::format("{}.{}.grassbake", level_name, preset_slug))
                         .string();
  }

  if (!fs::exists(fr3_path)) {
    fmt::print("error: fr3 not found: {}\n", fr3_path.string());
    return 1;
  }

  // fr3_size MUST be the on-disk (compressed) byte size — the runtime validates the
  // bake against std::filesystem::file_size of the fr3.
  u64 fr3_size = 0;
  try {
    fr3_size = (u64)fs::file_size(fr3_path);
  } catch (const std::exception& e) {
    fmt::print("error: cannot stat fr3 '{}': {}\n", fr3_path.string(), e.what());
    return 1;
  }

  fmt::print("[grass_bake] level='{}' fr3='{}' ({} bytes) out='{}' density={}\n", level_name,
             fr3_path.string(), fr3_size, out_path, density);

  // Load + decompress + deserialize the level (mirror of Loader.cpp:190-206).
  tfrag3::Level lev;
  try {
    auto data = file_util::read_binary_file(fr3_path);
    auto decomp = compression::decompress_zstd(data.data(), data.size());
    Serializer ser(decomp.data(), decomp.size());
    lev.serialize(ser);
    // The scan reads tree.unpacked.{vertices,indices}, which the packed fr3 leaves
    // empty until unpack() runs (mirror of Loader.cpp:213-229). Without this the
    // scan sees zero vertices and matches zero grass draws.
    for (auto& tie_tree : lev.tie_trees) {
      for (auto& tree : tie_tree) {
        tree.unpack();
      }
    }
    for (auto& t_tree : lev.tfrag_trees) {
      for (auto& tree : t_tree) {
        tree.unpack();
      }
    }
    for (auto& shrub_tree : lev.shrub_trees) {
      shrub_tree.unpack();
    }
    // OWNER REOPEN #13 + INSIGHT #2: exercise the GLOBAL cross-chunk/bucket/system weld offline
    // (deterministic, no device) — this is the same call Loader.cpp makes after all trees unpack.
    if (weld_stats) {
      tfrag3::reconstruct_level_global_weld(lev);
    }
  } catch (const std::exception& e) {
    fmt::print("error: failed to load/deserialize fr3: {}\n", e.what());
    return 1;
  }

  // --weld-stats: print the global-weld diagnostics (written to <repo>/pbr_tan_diag.txt) and exit
  // without running the grass scan. The device build writes the SAME file to the app files dir.
  if (weld_stats) {
    fs::path diag = file_util::get_jak_project_dir() / "pbr_tan_diag.txt";
    fmt::print("\n[grass_bake] ===== GLOBAL WELD STATS '{}' (offline) =====\n", level_name);
    try {
      fmt::print("{}\n", file_util::read_text_file(diag));
    } catch (const std::exception& e) {
      fmt::print("(could not read {}: {})\n", diag.string(), e.what());
    }
    fmt::print("[grass_bake] weld-stats DONE.\n");
    return 0;
  }

  // grass-overlay-meshes : LES MESHES POSES PAR-DESSUS. Il sort AVANT `scan_level`, donc aucune
  // table n'est cuite et aucun fichier n'est ecrit. Le controle positif tourne A CHAQUE FOIS :
  // la reponse attendue de cet item peut etre ZERO, et un zero de detecteur mort s'ecrirait
  // exactement comme un zero de donnee propre.
  if (overlay_census) {
    const auto st = grass_bake::overlay_census_selftest();
    fmt::print("overlay_selftest_ok={}\n", st.ok);
    fmt::print("overlay_selftest_pairs_tested={}\n", st.pairs_tested);
    fmt::print("overlay_selftest_method_a={}\n", st.method_a);
    fmt::print("overlay_selftest_method_b={}\n", st.method_b);
    fmt::print("overlay_selftest_intersection={}\n", st.intersection);
    fmt::print("overlay_selftest_found={}\n", st.found);
    fmt::print("overlay_selftest_path={}\n", st.cls_path);
    fmt::print("overlay_selftest_patch={}\n", st.cls_patch);
    fmt::print("overlay_selftest_ambiguous={}\n", st.cls_ambiguous);
    fmt::print("overlay_selftest_unclassified={}\n", st.unclassified);
    if (overlay_selftest_only) {
      fmt::print("[grass_bake] overlay-selftest DONE.\n");
      return 0;
    }
    const auto oc = grass_bake::overlay_census(lev, level_name);
    fmt::print("overlay_census_level={}\n", level_name);
    fmt::print("overlay_census_fr3_bytes={}\n", fr3_size);
    fmt::print("overlay_census_render_up={}\n", oc.render_up_tris);
    fmt::print("overlay_census_render_big={}\n", oc.render_big_tris);
    fmt::print("overlay_census_render_draws={}\n", oc.render_draws);
    fmt::print("overlay_census_collision_declared={}\n", oc.collision_ground_declared);
    fmt::print("overlay_census_collision_indexed={}\n", oc.collision_ground_tris);
    fmt::print("overlay_census_pairs_tested={}\n", oc.pairs_tested);
    fmt::print("overlay_census_pairs_bbox={}\n", oc.pairs_bbox);
    fmt::print("overlay_census_pairs_diff_tex={}\n", oc.pairs_diff_tex);
    fmt::print("overlay_census_pairs_one_grassy={}\n", oc.pairs_one_grassy);
    fmt::print("overlay_census_pairs_overlap_area={}\n", oc.pairs_overlap_area);
    fmt::print("overlay_census_pairs_close_y={}\n", oc.pairs_close_y);
    fmt::print("overlay_census_pairs_far_y={}\n", oc.pairs_far_y);
    fmt::print("overlay_census_pairs_bare_over_grass={}\n", oc.pairs_bare_over_grass);
    fmt::print("overlay_census_pairs_grass_over_bare={}\n", oc.pairs_grass_over_bare);
    fmt::print("overlay_census_pairs_both_grassy={}\n", oc.pairs_both_grassy);
    fmt::print("overlay_census_pairs_coincident={}\n", oc.pairs_coincident);
    fmt::print("overlay_census_method_a={}\n", oc.method_a);
    fmt::print("overlay_census_method_b={}\n", oc.method_b);
    fmt::print("overlay_census_method_b_probed={}\n", oc.method_b_probed);
    fmt::print("overlay_census_method_b_coll_tris={}\n", oc.method_b_coll_tris);
    fmt::print("overlay_census_method_b_rejected_below={}\n", oc.method_b_rejected_below);
    fmt::print("overlay_census_method_b_named_bare={}\n", oc.method_b_named_bare);
    fmt::print("overlay_census_intersection={}\n", oc.intersection);
    fmt::print("overlay_census_found={}\n", oc.found);
    fmt::print("overlay_census_cls_path={}\n", oc.cls_path);
    fmt::print("overlay_census_cls_patch={}\n", oc.cls_patch);
    fmt::print("overlay_census_cls_ambiguous={}\n", oc.cls_ambiguous);
    fmt::print("overlay_census_ambig_no_collision={}\n", oc.ambig_no_collision);
    fmt::print("overlay_census_ambig_material_other={}\n", oc.ambig_material_other);
    fmt::print("overlay_census_ambig_zfight={}\n", oc.ambig_zfight);
    fmt::print("overlay_census_unclassified={}\n", oc.unclassified);
    fmt::print("overlay_census_found_texture_unnamed={}\n", oc.found_texture_unnamed);
    fmt::print("overlay_census_unclass_material_unnamed={}\n", oc.unclass_material_unnamed);
    fmt::print("overlay_census_unclass_no_rule={}\n", oc.unclass_no_rule);
    fmt::print("overlay_census_sum_check={}\n", oc.sum_check);
    fmt::print("overlay_census_pair_tex_top={}\n", oc.pair_tex_top);
    fmt::print("overlay_census_method_b_tex_top={}\n", oc.method_b_tex_top);
    fmt::print("overlay_census_cls_path_tex_top={}\n", oc.cls_path_tex_top);
    fmt::print("overlay_census_cls_patch_tex_top={}\n", oc.cls_patch_tex_top);
    fmt::print("overlay_census_ambiguous_tex_top={}\n", oc.ambiguous_tex_top);
    fmt::print("overlay_census_src_population_top={}\n", oc.src_population_top);
    fmt::print("overlay_census_pair_src_top={}\n", oc.pair_src_top);
    fmt::print("overlay_census_found_src_top={}\n", oc.found_src_top);
    fmt::print("[grass_bake] overlay-census DONE.\n");
    return 0;
  }

  // grass-edge-truth : LE BORD SUR LE VIDE. Il sort AVANT `scan_level`, donc aucune table n'est
  // cuite et aucun fichier n'est ecrit. Le BANC NOMME tourne A CHAQUE FOIS : c'est lui, et non le
  // controle de somme des huit classes, qui peut rendre la sonde FAUSSE.
  if (edge_census_on) {
    const auto st = grass_bake::edge_probe_selftest();
    fmt::print("edge_selftest_ok={}\n", st.ok);
    fmt::print("edge_selftest_cases={}\n", st.cases);
    fmt::print("edge_selftest_agree={}\n", st.agree);
    fmt::print("edge_selftest_disagree={}\n", st.disagree);
    fmt::print("edge_selftest_not_found={}\n", st.not_found);
    fmt::print("edge_selftest_expect_void={}\n", st.expect_void);
    fmt::print("edge_selftest_expect_floor={}\n", st.expect_floor);
    fmt::print("edge_selftest_verdicts={}\n", st.verdict_list);
    fmt::print("edge_selftest_disagreements={}\n", st.disagree_list);
    if (edge_selftest_only) {
      fmt::print("[grass_bake] edge-selftest DONE.\n");
      return 0;
    }
    const auto ec = grass_bake::edge_census(lev, level_name);
    fmt::print("edge_census_level={}\n", level_name);
    fmt::print("edge_census_fr3_bytes={}\n", fr3_size);
    fmt::print("edge_census_collision={}\n", ec.collision_tris);
    fmt::print("edge_census_mode_ground={}\n", ec.mode_ground);
    fmt::print("edge_census_tris_used={}\n", ec.tris_used);
    fmt::print("edge_census_tris_xz_degenerate={}\n", ec.tris_xz_degenerate);
    fmt::print("edge_census_verts_raw={}\n", ec.verts_raw);
    fmt::print("edge_census_verts_welded={}\n", ec.verts_welded);
    fmt::print("edge_census_edges={}\n", ec.edges_total);
    fmt::print("edge_census_edges_zero_length={}\n", ec.edges_zero_length);
    fmt::print("edge_census_edge_slots={}\n", ec.edge_slots);
    fmt::print("edge_census_deg1={}\n", ec.deg1);
    fmt::print("edge_census_deg2={}\n", ec.deg2);
    fmt::print("edge_census_deg3plus={}\n", ec.deg3plus);
    fmt::print("edge_census_cls_triangle={}\n", ec.cls[grass_bake::kEdgeTriangle]);
    fmt::print("edge_census_cls_uv_seam={}\n", ec.cls[grass_bake::kEdgeUvSeam]);
    fmt::print("edge_census_cls_material={}\n", ec.cls[grass_bake::kEdgeMaterial]);
    fmt::print("edge_census_cls_normal_break={}\n", ec.cls[grass_bake::kEdgeNormalBreak]);
    fmt::print("edge_census_cls_chunk={}\n", ec.cls[grass_bake::kEdgeChunk]);
    fmt::print("edge_census_cls_overlay={}\n", ec.cls[grass_bake::kEdgeOverlay]);
    fmt::print("edge_census_cls_path={}\n", ec.cls[grass_bake::kEdgePath]);
    fmt::print("edge_census_cls_void={}\n", ec.cls[grass_bake::kEdgeVoid]);
    fmt::print("edge_census_classified={}\n", ec.classified);
    fmt::print("edge_census_claimed_none={}\n", ec.claimed_none);
    fmt::print("edge_census_claimed_multi={}\n", ec.claimed_multi);
    fmt::print("edge_census_class_sum_check={}\n", ec.class_sum_check);
    fmt::print("edge_census_beyond_found={}\n", ec.beyond_found);
    fmt::print("edge_census_beyond_missing={}\n", ec.beyond_missing);
    fmt::print("edge_census_probe_selfhit={}\n", ec.probe_selfhit);
    fmt::print("edge_census_void_with_far_floor={}\n", ec.void_with_far_floor);
    fmt::print("edge_census_void_no_floor_at_all={}\n", ec.void_no_floor_at_all);
    fmt::print("edge_census_void_out_far={}\n", ec.void_out_far);
    fmt::print("edge_census_void_drop_far={}\n", ec.void_drop_far);
    fmt::print("edge_census_unshared_but_floor={}\n", ec.unshared_but_floor);
    fmt::print("edge_census_shared_but_void={}\n", ec.shared_but_void);
    fmt::print("edge_census_own_unrendered={}\n", ec.own_unrendered);
    fmt::print("edge_census_beyond_unrendered={}\n", ec.beyond_unrendered);
    fmt::print("edge_census_beyond_mat_unnamed={}\n", ec.beyond_mat_unnamed);
    fmt::print("edge_census_legacy_tris={}\n", ec.legacy_tris);
    fmt::print("edge_census_legacy_edges={}\n", ec.legacy_edges);
    fmt::print("edge_census_old_rule_void={}\n", ec.old_rule_void);
    fmt::print("edge_census_geom_void_on_legacy={}\n", ec.geom_void_on_legacy);
    fmt::print("edge_census_old_only={}\n", ec.old_only);
    fmt::print("edge_census_geom_only={}\n", ec.geom_only);
    fmt::print("edge_census_void_both={}\n", ec.void_both);
    fmt::print("edge_census_void_edges_with_wall={}\n", ec.void_edges_with_wall);
    fmt::print("edge_census_terrace_dirt_void={}\n", ec.terrace_dirt_void);
    fmt::print("edge_census_terrace_sand_void={}\n", ec.terrace_sand_void);
    fmt::print("edge_census_terrace_stone_void={}\n", ec.terrace_stone_void);
    fmt::print("edge_census_terrace_dirt_void_old={}\n", ec.terrace_dirt_void_old);
    fmt::print("edge_census_terrace_dirt_on_grass={}\n", ec.terrace_dirt_on_grass);
    fmt::print("edge_census_terrace_nongrass_void={}\n", ec.terrace_nongrass_void);
    fmt::print("edge_census_void_wall_mat_top={}\n", ec.void_wall_mat_top);
    fmt::print("edge_census_material_pair_top={}\n", ec.material_pair_top);
    fmt::print("edge_census_void_tex_top={}\n", ec.void_tex_top);
    fmt::print("edge_census_class_top={}\n", ec.class_top);
    fmt::print("[grass_bake] edge-census DONE.\n");
    return 0;
  }

  // grass-surface-truth : LE RECENSEMENT DES DEUX SOURCES. Il sort AVANT `scan_level`, donc
  // aucune table n'est cuite et aucun fichier n'est ecrit — `.autoport/lib/census/` l'appelle
  // pendant une course de preuve et ne doit pas reecrire la donnee livree sous elle. Les
  // `cle=valeur` partent sur stdout ; c'est le recensement qui les prefixe par niveau.
  if (surface_census) {
    const auto sc = grass_bake::surface_census(lev, level_name);
    fmt::print("surface_census_level={}\n", level_name);
    fmt::print("surface_census_fr3_bytes={}\n", fr3_size);
    fmt::print("surface_census_ground={}\n", sc.ground_tris);
    fmt::print("surface_census_collision={}\n", sc.collision_tris);
    fmt::print("surface_census_mode_ground={}\n", sc.mode_ground);
    fmt::print("surface_census_mode_wall={}\n", sc.mode_wall);
    fmt::print("surface_census_mode_obstacle={}\n", sc.mode_obstacle);
    fmt::print("surface_census_mode_other={}\n", sc.mode_other);
    fmt::print("surface_census_by_material={}\n", sc.by_material);
    fmt::print("surface_census_by_texture={}\n", sc.by_texture);
    fmt::print("surface_census_by_both={}\n", sc.by_both);
    fmt::print("surface_census_classified={}\n", sc.classified);
    fmt::print("surface_census_unclassified={}\n", sc.unclassified);
    fmt::print("surface_census_tex_only_unclassified={}\n", sc.tex_only_unclassified);
    fmt::print("surface_census_mat_only_unclassified={}\n", sc.mat_only_unclassified);
    fmt::print("surface_census_mat_grass={}\n", sc.mat_grass);
    fmt::print("surface_census_mat_sand={}\n", sc.mat_sand);
    fmt::print("surface_census_mat_dirt={}\n", sc.mat_dirt);
    fmt::print("surface_census_mat_stone={}\n", sc.mat_stone);
    fmt::print("surface_census_mat_other={}\n", sc.mat_other);
    fmt::print("surface_census_mat_unnamed={}\n", sc.mat_unnamed);
    fmt::print("surface_census_tex_grass={}\n", sc.tex_grass);
    fmt::print("surface_census_tex_grass_legacy3={}\n", sc.tex_grass_legacy3);
    fmt::print("surface_census_legacy3_unclassified={}\n", sc.legacy3_unclassified);
    fmt::print("surface_census_disagree={}\n", sc.disagree);
    fmt::print("surface_census_disagree_mat_grass_tex_not={}\n", sc.disagree_mat_grass_tex_not);
    fmt::print("surface_census_disagree_tex_grass_mat_not={}\n", sc.disagree_tex_grass_mat_not);
    fmt::print("surface_census_render_ground={}\n", sc.render_ground_tris);
    fmt::print("surface_census_render_draws={}\n", sc.render_draws);
    fmt::print("surface_census_textures={}\n", sc.textures_seen);
    fmt::print("surface_census_disagree_tex_top={}\n", sc.disagree_tex_top);
    fmt::print("surface_census_mat_grass_tex_top={}\n", sc.mat_grass_tex_top);
    fmt::print("surface_census_tex_grass_mat_top={}\n", sc.tex_grass_mat_top);
    fmt::print("[grass_bake] surface-census DONE.\n");
    return 0;
  }

  // soft-surface-truth : LE MEME RECENSEMENT, POUR LE SABLE ET LA NEIGE. Il sort lui aussi AVANT
  // `scan_level` : aucune table n'est cuite, aucun fichier n'est ecrit, la donnee livree ne bouge
  // pas d'un octet sous la course de preuve qui l'appelle.
  if (soft_surface_census) {
    const auto sc = grass_bake::soft_surface_census(lev, level_name);
    fmt::print("soft_census_level={}\n", level_name);
    fmt::print("soft_census_fr3_bytes={}\n", fr3_size);
    fmt::print("soft_census_ground={}\n", sc.ground_tris);
    fmt::print("soft_census_collision={}\n", sc.collision_tris);
    fmt::print("soft_census_mode_ground={}\n", sc.mode_ground);
    fmt::print("soft_census_mode_wall={}\n", sc.mode_wall);
    fmt::print("soft_census_mode_obstacle={}\n", sc.mode_obstacle);
    fmt::print("soft_census_mode_other={}\n", sc.mode_other);
    fmt::print("soft_census_mode_wall_soft={}\n", sc.mode_wall_soft);
    fmt::print("soft_census_mode_obstacle_soft={}\n", sc.mode_obstacle_soft);
    fmt::print("soft_census_mode_other_soft={}\n", sc.mode_other_soft);
    fmt::print("soft_census_by_material={}\n", sc.by_material);
    fmt::print("soft_census_by_texture={}\n", sc.by_texture);
    fmt::print("soft_census_by_both={}\n", sc.by_both);
    fmt::print("soft_census_classified={}\n", sc.classified);
    fmt::print("soft_census_unclassified={}\n", sc.unclassified);
    fmt::print("soft_census_tex_only_unclassified={}\n", sc.tex_only_unclassified);
    fmt::print("soft_census_mat_only_unclassified={}\n", sc.mat_only_unclassified);
    fmt::print("soft_census_mat_sand={}\n", sc.mat_sand);
    fmt::print("soft_census_mat_snow={}\n", sc.mat_snow);
    fmt::print("soft_census_mat_deepsnow={}\n", sc.mat_deepsnow);
    fmt::print("soft_census_mat_soft={}\n", sc.mat_soft);
    fmt::print("soft_census_mat_grass={}\n", sc.mat_grass);
    fmt::print("soft_census_mat_unnamed={}\n", sc.mat_unnamed);
    fmt::print("soft_census_tex_sand={}\n", sc.tex_sand);
    fmt::print("soft_census_tex_snow={}\n", sc.tex_snow);
    fmt::print("soft_census_tex_soft={}\n", sc.tex_soft);
    fmt::print("soft_census_tex_grass={}\n", sc.tex_grass);
    fmt::print("soft_census_tex_reject={}\n", sc.tex_reject);
    fmt::print("soft_census_soft_by_material={}\n", sc.soft_by_material);
    fmt::print("soft_census_soft_by_texture={}\n", sc.soft_by_texture);
    fmt::print("soft_census_soft_by_both={}\n", sc.soft_by_both);
    fmt::print("soft_census_soft_by_either={}\n", sc.soft_by_either);
    fmt::print("soft_census_disagree={}\n", sc.disagree);
    fmt::print("soft_census_disagree_mat_soft_tex_not={}\n", sc.disagree_mat_soft_tex_not);
    fmt::print("soft_census_disagree_tex_soft_mat_not={}\n", sc.disagree_tex_soft_mat_not);
    fmt::print("soft_census_eligible_soft={}\n", sc.eligible_soft);
    fmt::print("soft_census_eligible_grass={}\n", sc.eligible_grass);
    fmt::print("soft_census_cross_eligible={}\n", sc.cross_eligible);
    fmt::print("soft_census_cross_raw={}\n", sc.cross_raw);
    fmt::print("soft_census_overlay_soft_tex_on_grass_mat={}\n", sc.overlay_soft_tex_on_grass_mat);
    fmt::print("soft_census_overlay_grass_tex_on_soft_mat={}\n", sc.overlay_grass_tex_on_soft_mat);
    fmt::print("soft_census_render_ground={}\n", sc.render_ground_tris);
    fmt::print("soft_census_render_draws={}\n", sc.render_draws);
    fmt::print("soft_census_textures={}\n", sc.textures_seen);
    fmt::print("soft_census_mat_soft_tex_top={}\n", sc.mat_soft_tex_top);
    fmt::print("soft_census_tex_soft_mat_top={}\n", sc.tex_soft_mat_top);
    fmt::print("soft_census_disagree_tex_top={}\n", sc.disagree_tex_top);
    fmt::print("soft_census_cross_raw_tex_top={}\n", sc.cross_raw_tex_top);
    fmt::print("soft_census_tex_reject_top={}\n", sc.tex_reject_top);
    fmt::print("[grass_bake] soft-surface-census DONE.\n");
    return 0;
  }

  // soft-support-map : LE SUPPORT ET L'EPAISSEUR, CUITS. Meme regime que les recensements
  // ci-dessus : il sort AVANT `scan_level`, il n'ouvre aucun fichier en ecriture, la donnee
  // livree ne bouge pas d'un octet. Il CUIT en memoire et il PUBLIE ; la serialisation est
  // l'affaire de `soft-bake-format`.
  if (soft_support_map_on) {
    const auto sm = grass_bake::soft_support_map(lev, level_name);
    fmt::print("soft_map_level={}\n", level_name);
    fmt::print("soft_map_fr3_bytes={}\n", fr3_size);
    fmt::print("soft_map_render_draws={}\n", sm.render_draws);
    fmt::print("soft_map_render_offered={}\n", sm.render_tris_offered);
    fmt::print("soft_map_render_indexed={}\n", sm.render_tris_indexed);
    fmt::print("soft_map_collision={}\n", sm.collision_tris);
    fmt::print("soft_map_soft_tris={}\n", sm.soft_tris);
    fmt::print("soft_map_hull_tris={}\n", sm.hull_tris);
    fmt::print("soft_map_hull_tris_sand={}\n", sm.hull_tris_sand);
    fmt::print("soft_map_hull_tris_snow={}\n", sm.hull_tris_snow);
    fmt::print("soft_map_hull_tris_deepsnow={}\n", sm.hull_tris_deepsnow);
    fmt::print("soft_map_hull_verts={}\n", sm.hull_verts);
    fmt::print("soft_map_hull_verts_thick={}\n", sm.hull_verts_thick);
    fmt::print("soft_map_hull_verts_tested={}\n", sm.hull_verts_tested);
    fmt::print("soft_map_hull_verts_sand={}\n", sm.hull_verts_sand);
    fmt::print("soft_map_hull_verts_snow={}\n", sm.hull_verts_snow);
    fmt::print("soft_map_hull_verts_deepsnow={}\n", sm.hull_verts_deepsnow);
    fmt::print("soft_map_boundary_verts={}\n", sm.boundary_verts);
    fmt::print("soft_map_interior_verts={}\n", sm.interior_verts);
    fmt::print("soft_map_bnd_by_other={}\n", sm.bnd_by_other);
    fmt::print("soft_map_bnd_by_dead={}\n", sm.bnd_by_dead);
    fmt::print("soft_map_bnd_by_open_edge={}\n", sm.bnd_by_open_edge);
    fmt::print("soft_map_vert_slots={}\n", sm.vert_slots);
    fmt::print("soft_map_hull_tris_dup={}\n", sm.hull_tris_dup);
    fmt::print("soft_map_rej_degenerate={}\n", sm.rej_degenerate);
    fmt::print("soft_map_rej_wall_render={}\n", sm.rej_wall_render);
    fmt::print("soft_map_rej_backface={}\n", sm.rej_backface);
    fmt::print("soft_map_rej_slope={}\n", sm.rej_slope);
    fmt::print("soft_map_rej_unclassified={}\n", sm.rej_unclassified);
    fmt::print("soft_map_rej_not_soft={}\n", sm.rej_not_soft);
    fmt::print("soft_map_rej_overlay_grass={}\n", sm.rej_overlay_grass);
    fmt::print("soft_map_rej_no_support={}\n", sm.rej_no_support);
    fmt::print("soft_map_rej_support_above={}\n", sm.rej_support_above);
    fmt::print("soft_map_rej_support_wall={}\n", sm.rej_support_wall);
    fmt::print("soft_map_rej_support_obstacle={}\n", sm.rej_support_obstacle);
    fmt::print("soft_map_rej_support_material={}\n", sm.rej_support_material);
    fmt::print("soft_map_rej_seafloor={}\n", sm.rej_seafloor);
    fmt::print("soft_map_rej_no_headroom={}\n", sm.rej_no_headroom);
    fmt::print("soft_map_rej_tie_not_terrain={}\n", sm.rej_tie_not_terrain);
    fmt::print("soft_map_rej_off_island={}\n", sm.rej_off_island);
    fmt::print("soft_map_coll_soft={}\n", sm.coll_soft);
    fmt::print("soft_map_coll_mode_ground={}\n", sm.coll_mode_ground);
    fmt::print("soft_map_coll_mode_wall_soft={}\n", sm.coll_mode_wall_soft);
    fmt::print("soft_map_coll_mode_obstacle_soft={}\n", sm.coll_mode_obstacle_soft);
    fmt::print("soft_map_static_cells={}\n", sm.static_cells);
    fmt::print("soft_map_static_objects={}\n", sm.static_objects);
    fmt::print("soft_map_static_from_collision={}\n", sm.static_from_collision);
    fmt::print("soft_map_static_from_tie={}\n", sm.static_from_tie);
    fmt::print("soft_map_static_skipped_large={}\n", sm.static_skipped_large);
    fmt::print("soft_map_static_area_u2={:.6f}\n", sm.static_area_u2);
    fmt::print("soft_map_static_area_m2={:.6f}\n", sm.static_area_m2);
    fmt::print("soft_map_depression_verts={}\n", sm.depression_verts);
    fmt::print("soft_map_verts_coincident={}\n", sm.verts_coincident);
    fmt::print("soft_map_objdist_min_u={:.6f}\n", sm.objdist_min_u);
    fmt::print("soft_map_objdist_med_u={:.6f}\n", sm.objdist_med_u);
    fmt::print("soft_map_objdist_max_u={:.6f}\n", sm.objdist_max_u);
    fmt::print("soft_map_thick_min_u={:.6f}\n", sm.thick_min_u);
    fmt::print("soft_map_thick_med_u={:.6f}\n", sm.thick_med_u);
    fmt::print("soft_map_thick_max_u={:.6f}\n", sm.thick_max_u);
    fmt::print("soft_map_fixpoint_rounds={}\n", sm.fixpoint_rounds);
    fmt::print("soft_map_population_empty={}\n", sm.population_empty);
    fmt::print("soft_map_deep_islands={}\n", sm.deep_islands);
    fmt::print("soft_map_deep_raw_min_u={:.6f}\n", sm.deep_raw_min_u);
    fmt::print("soft_map_deep_raw_med_u={:.6f}\n", sm.deep_raw_med_u);
    fmt::print("soft_map_deep_raw_max_u={:.6f}\n", sm.deep_raw_max_u);
    fmt::print("soft_map_defect_no_support={}\n", sm.defect_no_support);
    fmt::print("soft_map_defect_below_support={}\n", sm.defect_below_support);
    fmt::print("soft_map_defect_negative={}\n", sm.defect_negative);
    fmt::print("soft_map_defect_boundary={}\n", sm.defect_boundary);
    fmt::print("soft_map_defect_direction={}\n", sm.defect_direction);
    fmt::print("soft_map_reject_tex_top={}\n", sm.reject_tex_top);
    fmt::print("soft_map_support_mat_top={}\n", sm.support_mat_top);
    fmt::print("soft_map_soft_src_top={}\n", sm.soft_src_top);
    fmt::print("soft_map_hull_src_top={}\n", sm.hull_src_top);
    // UNE LIGNE PAR ILOT DEEPSNOW : la decision 4 de la SPEC attend ces nombres.
    for (const auto& is : sm.islands) {
      fmt::print(
          "soft_map_island_{}=tris:{},verts:{},min_u:{:.6f},med_u:{:.6f},max_u:{:.6f},"
          "raw_min_u:{:.6f},raw_med_u:{:.6f},raw_max_u:{:.6f}\n",
          is.id, is.collision_tris, is.hull_verts, is.min_u, is.med_u, is.max_u, is.raw_min_u,
          is.raw_med_u, is.raw_max_u);
    }
    fmt::print("[grass_bake] soft-support-map DONE.\n");
    return 0;
  }

  // Scan (prints the [recharged-grass] instrumentation lines).
  grass_bake::BakeData bake;
  try {
    bake = grass_bake::scan_level(lev, level_name, fr3_size,
                                  {density, grass_bake::FLOOR_GAP_M});
  } catch (const std::exception& e) {
    fmt::print("error: scan_level failed: {}\n", e.what());
    return 1;
  }

  // grass-chunk-cull : LA PARTITION EST CUITE, DONC ELLE SE CALCULE AVANT L'ECRITURE. Elle est
  // celle de l'expansion A LA DENSITE DE CE BAKE — la seule que le moteur demandera, puisque
  // chaque palier porte son propre fichier et que `expand()` y est appelee avec `bake_density_pct`.
  // `want_cand_map` : les deux recensements en ont besoin — sans la carte brin -> candidat, ils
  // apparieraient le premier candidat d'un triangle au premier brin et sauteraient tout ce que
  // `keep` a ecarte. Le jeu, lui, l'appelle a false et ne paie pas les 4 octets par instance.
  const bool want_map = trans_census_on || clump_census_on || nest_pct > 0.0f;
  auto eBake = grass_bake::expand(bake, density, want_map);
  bake.chunks = eBake.chunks;

  // grass-clumps : il MESURE, il n'ecrit rien, et il sort AVANT toute ecriture de fichier.
  if (clump_census_on) {
    const auto cc = grass_bake::clump_census(bake, eBake);
    fmt::print("clump_level={}\n", level_name);
    fmt::print("clump_fr3_bytes={}\n", fr3_size);
    fmt::print("clump_density={:.0f}\n", density);
    fmt::print("clump_blades_total={}\n", cc.blades_total);
    fmt::print("clump_clumps_total={}\n", cc.clumps_total);
    fmt::print("clump_clumps_mounted={}\n", cc.clumps_mounted);
    fmt::print("clump_pairs_clumped={:.4f}\n", cc.pairs_clumped);
    fmt::print("clump_pairs_uniform={:.4f}\n", cc.pairs_uniform);
    fmt::print("clump_pairs_ratio={:.4f}\n", cc.pairs_ratio);
    fmt::print("clump_pairs_sampled={}\n", cc.pairs_sampled);
    fmt::print("clump_size_mean={:.4f}\n", cc.size_mean);
    fmt::print("clump_size_cv={:.4f}\n", cc.size_cv);
    fmt::print("clump_radius_mean_m={:.4f}\n", cc.radius_mean_m);
    fmt::print("clump_radius_cv={:.4f}\n", cc.radius_cv);
    fmt::print("clump_origin_digest={:016x}\n", cc.origin_digest);
    fmt::print("clump_root_outside={}\n", cc.root_outside);
    fmt::print("clump_pos_mismatch={}\n", cc.pos_mismatch);
    fmt::print("clump_clipped={}\n", cc.clipped);
    fmt::print("clump_height_mean_ratio={:.4f}\n", cc.height_mean_ratio);
    fmt::print("clump_terms_measured={}\n", cc.terms_measured);
    // LES SEUILS SONT PUBLIES PAR CE QUI MESURE, jamais recopies dans le juge : un seuil duplique
    // derive du code mesure et rend la porte fausse en silence.
    fmt::print("clump_pair_r_m={:.4f}\n", grass_bake::CLUMP_PAIR_R_M);
    fmt::print("clump_ratio_floor={:.4f}\n", grass_bake::CLUMP_RATIO_FLOOR);
    fmt::print("clump_size_cv_floor={:.4f}\n", grass_bake::CLUMP_SIZE_CV_FLOOR);
    fmt::print("clump_radius_cv_floor={:.4f}\n", grass_bake::CLUMP_RADIUS_CV_FLOOR);
    fmt::print("clump_blades_medium={:.2f}\n", grass_bake::CLUMP_BLADES_MEDIUM);
  }

  // grass-clumps, point 3 : LES PALIERS RESTENT IMBRIQUES. On rejoue le scan a l'autre palier —
  // dans CE processus, sur le MEME .fr3 — et on compare touffe par touffe. Rien n'est ecrit.
  if (nest_pct > 0.0f) {
    grass_bake::BakeData other;
    try {
      other = grass_bake::scan_level(lev, level_name, fr3_size,
                                     {nest_pct, grass_bake::FLOOR_GAP_M});
    } catch (const std::exception& e) {
      fmt::print("clump_nest_error={}\n", e.what());
      return 1;
    }
    auto eOther = grass_bake::expand(other, nest_pct, true);
    const bool cur_is_low = density <= nest_pct;
    const auto& blo = cur_is_low ? bake : other;
    const auto& elo = cur_is_low ? eBake : eOther;
    const auto& bhi = cur_is_low ? other : bake;
    const auto& ehi = cur_is_low ? eOther : eBake;
    const auto nc = grass_bake::clump_nest_census(blo, elo, bhi, ehi);
    fmt::print("clump_nest_low_pct={:.0f}\n", cur_is_low ? density : nest_pct);
    fmt::print("clump_nest_high_pct={:.0f}\n", cur_is_low ? nest_pct : density);
    fmt::print("clump_nest_tris_compared={}\n", nc.tris_compared);
    fmt::print("clump_nest_tris_misaligned={}\n", nc.tris_misaligned);
    fmt::print("clump_nest_clumps_compared={}\n", nc.clumps_compared);
    fmt::print("clump_nest_origin_moved={}\n", nc.origin_moved);
    fmt::print("clump_nest_count_mismatch={}\n", nc.count_mismatch);
    fmt::print("clump_nest_prefix_breaks={}\n", nc.prefix_breaks);
    fmt::print("clump_nest_blades_low={}\n", nc.blades_low);
    fmt::print("clump_nest_blades_high={}\n", nc.blades_high);
  }
  if (clump_census_on || nest_pct > 0.0f) {
    fmt::print("[grass_bake] clump-census DONE.\n");
    return 0;
  }

  // grass-path-transitions : il MESURE, il n'ecrit rien. Il sort AVANT toute ecriture de fichier,
  // exactement comme les trois recensements qui le precedent — la seule difference est qu'il lui
  // faut le scan ET l'expansion, puisque la grandeur qu'il juge porte sur les brins EMIS.
  if (trans_census_on) {
    const auto tc = grass_bake::transition_census(bake, eBake);
    fmt::print("trans_census_level={}\n", level_name);
    fmt::print("trans_census_fr3_bytes={}\n", fr3_size);
    fmt::print("trans_census_density={:.0f}\n", density);
    fmt::print("trans_bare_draws_geom={}\n", tc.bare_draws_geom);
    fmt::print("trans_bare_draws_mat={}\n", tc.bare_draws_mat);
    fmt::print("trans_bare_draws_both={}\n", tc.bare_draws_both);
    fmt::print("trans_bare_draws_disagree={}\n", tc.bare_draws_disagree);
    fmt::print("trans_bare_tris={}\n", tc.bare_tris);
    fmt::print("trans_bare_area_m2={:.2f}\n", tc.bare_area_m2);
    fmt::print("trans_occ_pts_object={}\n", tc.occ_pts_object);
    fmt::print("trans_occ_pts_removed={}\n", tc.occ_pts_removed);
    fmt::print("trans_bare_tex_top={}\n", tc.bare_tex_top);
    fmt::print("trans_bare_rej_top={}\n", tc.bare_rej_top);
    fmt::print("trans_bare_mat_top={}\n", tc.bare_mat_top);
    fmt::print("trans_faces_up={}\n", tc.faces_up);
    fmt::print("trans_faces_bare_mat={}\n", tc.faces_bare_mat);
    fmt::print("trans_faces_affleurantes={}\n", tc.faces_affleurantes);
    fmt::print("trans_faces_lifted={}\n", tc.faces_lifted);
    fmt::print("trans_faces_nofloor={}\n", tc.faces_nofloor);
    fmt::print("trans_blades_total={}\n", tc.blades_total);
    fmt::print("trans_blades_tested={}\n", tc.blades_tested);
    fmt::print("trans_blades_inside={}\n", tc.blades_inside);
    fmt::print("trans_blades_band={}\n", tc.blades_band);
    fmt::print("trans_blades_interior={}\n", tc.blades_interior);
    fmt::print("trans_cand_total={}\n", tc.cand_total);
    fmt::print("trans_cand_inside={}\n", tc.cand_inside);
    fmt::print("trans_cand_limit={}\n", tc.cand_limit);
    fmt::print("trans_pos_mismatch={}\n", tc.pos_mismatch);
    fmt::print("trans_gap_p50={:.4f}\n", tc.gap_p50);
    fmt::print("trans_gap_p90={:.4f}\n", tc.gap_p90);
    fmt::print("trans_gap_p99={:.4f}\n", tc.gap_p99);
    fmt::print("trans_gap_max={:.4f}\n", tc.gap_max);
    fmt::print("trans_gap_over_cap={}\n", tc.gap_over_cap);
    fmt::print("trans_gap_cause_nofloor={}\n", tc.gap_cause_nofloor);
    fmt::print("trans_gap_cause_object={}\n", tc.gap_cause_object);
    fmt::print("trans_gap_cause_nograss={}\n", tc.gap_cause_nograss);
    fmt::print("trans_gap_cause_inside={}\n", tc.gap_cause_inside);
    fmt::print("trans_gap_cause_trans={}\n", tc.gap_cause_trans);
    fmt::print("trans_gap_defect_frac={:.5f}\n", tc.gap_defect_frac);
    fmt::print("trans_gap_defect_max={:.4f}\n", tc.gap_defect_max);
    fmt::print("trans_gap_defect_cands={:.2f}\n", tc.gap_defect_cands);
    fmt::print("trans_gap_defect_thin={:.2f}\n", tc.gap_defect_thin);
    fmt::print("trans_gap_defect_frac_cap={:.4f}\n", grass_bake::TRANS_GAP_DEFECT_FRAC);
    fmt::print("trans_gap_cap={:.3f}\n", grass_bake::TRANS_GAP_CAP_M);
    fmt::print("trans_gap_max_cap={:.3f}\n", grass_bake::TRANS_GAP_MAX_CAP_M);
    fmt::print("trans_front_cells={}\n", tc.front_cells);
    fmt::print("trans_front_median={:.4f}\n", tc.front_median_m);
    fmt::print("trans_edge_follow={:.4f}\n", tc.edge_follow_frac);
    fmt::print("trans_edge_follow_cap={:.3f}\n", grass_bake::TRANS_EDGE_FOLLOW_CAP);
    fmt::print("trans_band_cells={}\n", tc.band_cells);
    fmt::print("trans_graded_frac={:.4f}\n", tc.graded_frac);
    fmt::print("trans_graded_floor={:.3f}\n", grass_bake::TRANS_GRADED_FLOOR);
    for (int b = 0; b < 4; ++b) {
      fmt::print("trans_band_ratio{}={:.4f}\n", b, tc.band_ratio[b]);
      fmt::print("trans_band_elig{}={:.4f}\n", b, tc.band_elig[b]);
      fmt::print("trans_band_dens{}={:.4f}\n", b, tc.band_dens[b]);
      fmt::print("trans_band_height{}={:.4f}\n", b, tc.band_height[b]);
    }
    fmt::print("trans_interior_height={:.1f}\n", tc.interior_height);
    fmt::print("trans_mono_ratio_breaks={}\n", tc.mono_ratio_breaks);
    fmt::print("trans_mono_dens_breaks={}\n", tc.mono_dens_breaks);
    fmt::print("trans_dens_ramp_missing={}\n", tc.dens_ramp_missing);
    fmt::print("trans_height_ramp_missing={}\n", tc.height_ramp_missing);
    fmt::print("trans_ramp_max={:.3f}\n", grass_bake::TRANS_RAMP_MAX);
    fmt::print("trans_mono_height_breaks={}\n", tc.mono_height_breaks);
    fmt::print("trans_population_empty={}\n", tc.population_empty);
    fmt::print("trans_bare_absent={}\n", tc.bare_absent);
    fmt::print("trans_band_absent={}\n", tc.band_absent);
    fmt::print("trans_limit_absent={}\n", tc.limit_absent);
    fmt::print("trans_terms_measured={}\n", tc.terms_measured);
    fmt::print("trans_w_m={:.3f}\n", grass_bake::TRANS_W_M);
    fmt::print("trans_dens_floor={:.3f}\n", grass_bake::TRANS_DENS_FLOOR);
    fmt::print("trans_h_floor={:.3f}\n", grass_bake::TRANS_H_FLOOR);
    fmt::print("trans_noise_amp_m={:.3f}\n", grass_bake::TRANS_NOISE_AMP_M);
    fmt::print("[grass_bake] transition-census DONE.\n");
    return 0;
  }
  {
    u64 cmin = 0, cmax = 0, csum = 0;
    std::vector<u64> counts;
    counts.reserve(bake.chunks.size());
    for (const auto& c : bake.chunks) {
      counts.push_back(c.count);
      csum += c.count;
    }
    std::sort(counts.begin(), counts.end());
    if (!counts.empty()) {
      cmin = counts.front();
      cmax = counts.back();
    }
    fmt::print("[grass_bake] chunks @slider={:.0f}: n={} instances={} min={} p50={} p90={} max={}\n",
               density, (u64)bake.chunks.size(), csum, cmin,
               counts.empty() ? 0 : counts[counts.size() / 2],
               counts.empty() ? 0 : counts[(counts.size() * 9) / 10], cmax);
  }

  // Save.
  if (!grass_bake::save_bake(bake, out_path)) {
    fmt::print("error: save_bake failed to write '{}'\n", out_path);
    return 1;
  }

  u64 out_size = 0;
  try {
    out_size = (u64)fs::file_size(out_path);
  } catch (...) {
  }

  // Self-check expands at the shipping default (150); the bake-density expansion was already
  // computed above (its partition is what got written).
  auto e150 = grass_bake::expand(bake, 150.0f);

  fmt::print("\n[grass_bake] ===== BAKE SUMMARY '{}' =====\n", level_name);
  fmt::print("[grass_bake] scan: considered_draws={} tie_draws={} tris_kept={} giant_tris={} "
             "max_area={:.1f} m2\n",
             bake.stats.considered_draws, bake.stats.tie_draws, bake.stats.tris_kept,
             bake.stats.giant_tris, bake.stats.max_area);
  fmt::print("[grass_bake] scan: total_area={:.1f} m2  floor_gap={:.2f} m  bake_density={:.1f}\n",
             bake.total_area_m2, bake.floor_gap_m, bake.bake_density_pct);
  fmt::print("[grass_bake] tables: ntris={} ncand={} (keep bytes={}, rim_q entries={})\n",
             (u64)bake.tris.size(), (u64)bake.keep.size(), (u64)bake.keep.size(),
             (u64)bake.rim_q.size());
  fmt::print("[grass_bake] expand @slider=150 (ship default): instances={} scatter_kept={} "
             "occ_culled={}\n",
             (u64)e150.instances.size(), e150.scatter_kept, e150.occ_culled);
  fmt::print("[grass_bake] expand @slider={:.0f} (bake density): instances={} scatter_kept={} "
             "occ_culled={}\n",
             density, (u64)eBake.instances.size(), eBake.scatter_kept, eBake.occ_culled);
  fmt::print("[grass_bake] wrote '{}' ({} bytes compressed)\n", out_path, out_size);

  // Grecharged-grass-overhang4: offline placement dump (ship-default expansion) so the banding /
  // seam / tip-violation metrics can be computed by .autoport analysis and compared across
  // placement generations (round-3 rows vs round-4 scatter) with ONE metric implementation.
  if (!dump_prefix.empty()) {
    FILE* fi = std::fopen((dump_prefix + "_instances.csv").c_str(), "w");
    FILE* ft = std::fopen((dump_prefix + "_tris.csv").c_str(), "w");
    if (!fi || !ft) {
      fmt::print("error: --dump cannot open '{}_*.csv'\n", dump_prefix);
      return 1;
    }
    std::fprintf(fi, "idx,px,py,pz,h,yaw,tint,curve,phase,gspare,nx,ny,nz,nspare,tri\n");
    for (size_t i = 0; i < e150.instances.size(); ++i) {
      const auto& g = e150.instances[i];
      std::fprintf(fi, "%zu,%.3f,%.3f,%.3f,%.3f,%.5f,%.5f,%.5f,%.5f,%.3f,%.6f,%.6f,%.6f,%.5f,%u\n",
                   i, g.px, g.py, g.pz, g.h, g.yaw, g.tint, g.curve, g.phase, g.gspare, g.nx, g.ny,
                   g.nz, g.nspare, e150.inst_tri[i]);
    }
    std::fprintf(ft, "idx,p0x,p0y,p0z,e1x,e1y,e1z,e2x,e2y,e2z,nx,ny,nz,flags,area_m2\n");
    for (size_t t = 0; t < bake.tris.size(); ++t) {
      const auto& tr = bake.tris[t];
      std::fprintf(ft, "%zu,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f,%u,%.4f\n",
                   t, tr.p0[0], tr.p0[1], tr.p0[2], tr.e1[0], tr.e1[1], tr.e1[2], tr.e2[0],
                   tr.e2[1], tr.e2[2], tr.nx, tr.ny, tr.nz, tr.flags, tr.area_m2);
    }
    std::fclose(fi);
    std::fclose(ft);
    fmt::print("[grass_bake] dumped {} instances (droop_start={} trans_start={}) + {} tris to "
               "'{}_*.csv'\n",
               (u64)e150.instances.size(), e150.droop_start, e150.trans_start,
               (u64)bake.tris.size(), dump_prefix);
  }

  // Grecharged-grass-overhang: round-trip self-check — load the written bake back and prove the
  // expanded field (walkable + droop tail) is byte-identical to the in-memory scan's expansion.
  {
    grass_bake::BakeData rt;
    if (!grass_bake::load_bake(rt, out_path)) {
      fmt::print("error: round-trip load_bake failed on '{}'\n", out_path);
      return 1;
    }
    auto rtE = grass_bake::expand(rt, 150.0f);
    bool same = rtE.instances.size() == e150.instances.size() &&
                rtE.droop_start == e150.droop_start &&
                (rtE.instances.empty() ||
                 std::memcmp(rtE.instances.data(), e150.instances.data(),
                             rtE.instances.size() * sizeof(grass_bake::GrassInstance)) == 0);
    // grass-chunk-cull : la partition RELUE DU FICHIER doit etre celle que `build_chunks` rend
    // sur les instances du meme palier. Sans cette comparaison, une table cuite a la mauvaise
    // densite passerait la porte et le moteur culerait sur des boites qui ne bornent rien.
    const bool chunks_same =
        rt.chunks.size() == bake.chunks.size() &&
        (rt.chunks.empty() || std::memcmp(rt.chunks.data(), bake.chunks.data(),
                                          rt.chunks.size() * sizeof(grass_bake::GrassChunk)) == 0);
    fmt::print("[grass_bake] round-trip chunks: {} (n={} vs {})\n",
               chunks_same ? "IDENTICAL" : "MISMATCH", (u64)rt.chunks.size(),
               (u64)bake.chunks.size());
    if (!chunks_same) {
      return 1;
    }
    fmt::print("[grass_bake] round-trip @150: {} (instances={} droop_start={} droop_tris={})\n",
               same ? "IDENTICAL" : "MISMATCH", (u64)rtE.instances.size(), rtE.droop_start,
               (u64)rt.droop.size());
    if (!same) {
      return 1;
    }
  }
  fmt::print("[grass_bake] DONE.\n");
  return 0;
}
