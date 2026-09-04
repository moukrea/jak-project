#include "extract_level.h"

#include <set>
#include <thread>

#include "extract_anim.h"

#include "common/custom_data/TangentDerive.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/util/SimpleThreadGroup.h"
#include "common/util/compress.h"
#include "common/util/string_util.h"

#include "decompiler/level_extractor/BspHeader.h"
#include "decompiler/level_extractor/extract_actors.h"
#include "decompiler/level_extractor/extract_collide_frags.h"
#include "decompiler/level_extractor/extract_hfrag.h"
#include "decompiler/level_extractor/extract_joint_group.h"
#include "decompiler/level_extractor/extract_merc.h"
#include "decompiler/level_extractor/extract_shrub.h"
#include "decompiler/level_extractor/extract_tfrag.h"
#include "decompiler/level_extractor/extract_tie.h"
#include "decompiler/level_extractor/fr3_to_gltf.h"
#include "goalc/build_actor/jak1/build_actor.h"

namespace decompiler {

/*!
 * Look through files in a DGO and find the bsp-header file (the level)
 */
std::optional<ObjectFileRecord> get_bsp_file(const std::vector<ObjectFileRecord>& records,
                                             const std::string& dgo_name) {
  std::optional<ObjectFileRecord> result;
  if (str_util::ends_with(dgo_name, ".DGO")) {
    // only DGOs are valid levels, and the last file is the bsp file
    result = records.at(records.size() - 1);
  }
  return result;
}

/*!
 * Make sure a file is a valid bsp-header.
 */
bool is_valid_bsp(const decompiler::LinkedObjectFile& file) {
  if (file.segments != 1) {
    lg::error("Got {} segments, but expected 1", file.segments);
    return false;
  }

  auto& first_word = file.words_by_seg.at(0).at(0);
  if (first_word.kind() != decompiler::LinkedWord::TYPE_PTR) {
    lg::error("Expected the first word to be a type pointer, but it wasn't.");
    return false;
  }

  if (first_word.symbol_name() != "bsp-header") {
    lg::error("Expected to get a bsp-header, but got {} instead.", first_word.symbol_name());
    return false;
  }

  return true;
}

tfrag3::Texture make_texture(u32 id,
                             const TextureDB::TextureData& tex,
                             const std::string& tpage_name,
                             bool pool_load) {
  tfrag3::Texture new_tex;
  new_tex.combo_id = id;
  new_tex.w = tex.w;
  new_tex.h = tex.h;
  new_tex.debug_tpage_name = tpage_name;
  new_tex.debug_name = tex.name;
  new_tex.data = tex.rgba_bytes;
  new_tex.combo_id = id;
  new_tex.load_to_pool = pool_load;
  return new_tex;
}

void add_all_textures_from_level(tfrag3::Level& lev,
                                 const std::string& level_name,
                                 const TextureDB& tex_db) {
  const auto& level_it = tex_db.texture_ids_per_level.find(level_name);
  if (level_it != tex_db.texture_ids_per_level.end()) {
    for (auto id : level_it->second) {
      const auto& tex = tex_db.textures.at(id);
      lev.textures.push_back(make_texture(id, tex, tex_db.tpage_names.at(tex.page), true));
    }
  }
}

void confirm_textures_identical(const TextureDB& tex_db) {
  std::unordered_map<std::string, std::vector<u32>> tex_dupl;
  for (auto& tex : tex_db.textures) {
    auto name = tex_db.tpage_names.at(tex.second.page) + tex.second.name;
    auto it = tex_dupl.find(name);
    if (it == tex_dupl.end()) {
      tex_dupl.insert({name, tex.second.rgba_bytes});
    } else {
      bool ok = it->second == tex.second.rgba_bytes;
      if (!ok) {
        ASSERT_MSG(false, fmt::format("BAD duplicate: {} {} vs {}", name,
                                      tex.second.rgba_bytes.size(), it->second.size()));
      }
    }
  }
}

void extract_art_groups_from_level(const ObjectFileDB& db,
                                   const TextureDB& tex_db,
                                   const std::vector<level_tools::TextureRemap>& tex_remap,
                                   const std::string& dgo_name,
                                   tfrag3::Level& level_data,
                                   std::map<std::string, level_tools::ArtData>& art_group_data) {
  if (db.obj_files_by_dgo.count(dgo_name)) {
    const auto& files = db.obj_files_by_dgo.at(dgo_name);
    MercSwapInfo swapped_info;
    // build list of models to replace
    auto merc_replacements_path = file_util::get_jak_project_dir() / "custom_assets" /
                                  game_version_names[db.version()] / "merc_replacements";
    if (file_util::file_exists(merc_replacements_path.string())) {
      auto custom_models =
          file_util::find_files_in_dir(merc_replacements_path, std::regex(".*\\.glb"));
      for (auto& mdl : custom_models) {
        swapped_info.add_to_swap_list(mdl.stem().string());
      }
    }
    for (const auto& file : files) {
      if (file.name.length() > 3 && !file.name.compare(file.name.length() - 3, 3, "-ag")) {
        const auto& ag_file = db.lookup_record(file);
        extract_merc(ag_file, tex_db, db.dts, tex_remap, level_data, false, db.version(),
                     swapped_info);
        extract_joint_group(ag_file, db.dts, db.version(), art_group_data);
        extract_animations(ag_file, db.dts, db.version(), art_group_data);
      }
    }
  }
}

std::vector<level_tools::TextureRemap> extract_tex_remap(const ObjectFileDB& db,
                                                         const std::string& dgo_name) {
  auto bsp_rec = get_bsp_file(db.obj_files_by_dgo.at(dgo_name), dgo_name);
  if (!bsp_rec) {
    lg::warn("Skipping extract for {} because the BSP file was not found", dgo_name);
    return {};
  }
  std::string level_name = bsp_rec->name;

  lg::info("Processing level {} ({})", dgo_name, level_name);
  const auto& bsp_file = db.lookup_record(*bsp_rec);
  bool ok = is_valid_bsp(bsp_file.linked_data);
  ASSERT(ok);

  level_tools::BspHeader bsp_header;
  bsp_header.read_from_file(bsp_file.linked_data, db.dts, db.version(), true);

  return bsp_header.texture_remap_table;
}

level_tools::BspHeader extract_bsp_from_level(const ObjectFileDB& db,
                                              const TextureDB& tex_db,
                                              const std::string& dgo_name,
                                              const Config& config,
                                              tfrag3::Level& level_data) {
  auto hacks = config.hacks;
  auto bsp_rec = get_bsp_file(db.obj_files_by_dgo.at(dgo_name), dgo_name);
  if (!bsp_rec) {
    lg::warn("Skipping extract for {} because the BSP file was not found", dgo_name);
    return {};
  }

  lg::info("Processing {}...", dgo_name);
  const auto& bsp_file = db.lookup_record(*bsp_rec);
  bool ok = is_valid_bsp(bsp_file.linked_data);
  ASSERT(ok);

  level_tools::BspHeader bsp_header;
  bsp_header.read_from_file(bsp_file.linked_data, db.dts, db.version());
  ASSERT((int)bsp_header.drawable_tree_array.trees.size() == bsp_header.drawable_tree_array.length);

  // grrr.....
  if (db.version() == GameVersion::Jak1 && dgo_name == "TIT.DGO" && bsp_header.name == "intro") {
    bsp_header.name = "title";
  } else if (db.version() == GameVersion::Jak1 && dgo_name == "DEM.DGO" &&
             bsp_header.name == "intro") {
    bsp_header.name = "demo";
  }

  /*
  level_tools::PrintSettings settings;
  settings.expand_collide = true;
  lg::print("{}\n", bsp_header.print(settings));
   */

  const std::set<std::string> tfrag_trees = {
      "drawable-tree-tfrag",        "drawable-tree-trans-tfrag",       "drawable-tree-tfrag-trans",
      "drawable-tree-dirt-tfrag",   "drawable-tree-tfrag-water",       "drawable-tree-ice-tfrag",
      "drawable-tree-lowres-tfrag", "drawable-tree-lowres-trans-tfrag"};
  int i = 0;

  std::vector<const level_tools::DrawableTreeInstanceTie*> all_ties;
  for (auto& draw_tree : bsp_header.drawable_tree_array.trees) {
    auto as_tie_tree = dynamic_cast<level_tools::DrawableTreeInstanceTie*>(draw_tree.get());
    if (as_tie_tree) {
      all_ties.push_back(as_tie_tree);
    }
  }

  bool got_collide = false;
  for (auto& draw_tree : bsp_header.drawable_tree_array.trees) {
    if (tfrag_trees.count(draw_tree->my_type())) {
      auto as_tfrag_tree = dynamic_cast<level_tools::DrawableTreeTfrag*>(draw_tree.get());
      ASSERT(as_tfrag_tree);
      std::vector<std::pair<int, int>> expected_missing_textures;
      auto it = hacks.missing_textures_by_level.find(bsp_header.name);
      if (it != hacks.missing_textures_by_level.end()) {
        expected_missing_textures = it->second;
      }
      bool atest_disable_flag = false;
      if (db.version() >= GameVersion::Jak2) {
        if (bsp_header.texture_flags[0] & 1) {
          atest_disable_flag = true;
        }
      }
      extract_tfrag(as_tfrag_tree, fmt::format("{}-{}", dgo_name, i++),
                    bsp_header.texture_remap_table, tex_db, expected_missing_textures, level_data,
                    false, bsp_header.name, atest_disable_flag);
    } else if (draw_tree->my_type() == "drawable-tree-instance-tie") {
      auto as_tie_tree = dynamic_cast<level_tools::DrawableTreeInstanceTie*>(draw_tree.get());
      ASSERT(as_tie_tree);
      extract_tie(as_tie_tree, fmt::format("{}-{}-tie", dgo_name, i++),
                  bsp_header.texture_remap_table, tex_db, level_data, false, db.version());
    } else if (draw_tree->my_type() == "drawable-tree-instance-shrub") {
      auto as_shrub_tree =
          dynamic_cast<level_tools::shrub_types::DrawableTreeInstanceShrub*>(draw_tree.get());
      ASSERT(as_shrub_tree);
      extract_shrub(as_shrub_tree, fmt::format("{}-{}-shrub", dgo_name, i++),
                    bsp_header.texture_remap_table, tex_db, {}, level_data, false, db.version());
    } else if (draw_tree->my_type() == "drawable-tree-collide-fragment" &&
               config.extract_collision) {
      auto as_collide_frags =
          dynamic_cast<level_tools::DrawableTreeCollideFragment*>(draw_tree.get());
      ASSERT(as_collide_frags);
      ASSERT(!got_collide);
      got_collide = true;
      extract_collide_frags(as_collide_frags, all_ties, config,
                            fmt::format("{}-{}-collide", dgo_name, i++), level_data);
    } else {
      lg::print("  unsupported tree {}\n", draw_tree->my_type());
    }
  }

  if (bsp_header.collide_hash.num_items) {
    ASSERT(!got_collide);
    extract_collide_frags(bsp_header.collide_hash, all_ties, config,
                          fmt::format("{}-{}-collide", dgo_name, i++), db.dts, level_data);
  }
  if (bsp_header.hfrag) {
    extract_hfrag(bsp_header, tex_db, &level_data);
  }
  level_data.level_name = bsp_header.name;

  return bsp_header;
}

/*!
 * Extract stuff found in GAME.CGO.
 * Even though GAME.CGO isn't technically a level, the decompiler/loader treat it like one,
 * but the bsp stuff is just empty. It will contain only textures/art groups.
 */
void extract_common(const ObjectFileDB& db,
                    const TextureDB& tex_db,
                    const std::string& dgo_name,
                    const fs::path& output_folder,
                    const Config& config) {
  if (db.obj_files_by_dgo.count(dgo_name) == 0) {
    lg::warn("Skipping common extract for {} because the DGO was not part of the input", dgo_name);
    return;
  }

  if (tex_db.textures.size() == 0) {
    lg::warn("Skipping common extract because there were no textures in the input");
    return;
  }

  confirm_textures_identical(tex_db);

  tfrag3::Level tfrag_level{};
  std::map<std::string, level_tools::ArtData> art_group_data;
  add_all_textures_from_level(tfrag_level, dgo_name, tex_db);
  extract_art_groups_from_level(db, tex_db, {}, dgo_name, tfrag_level, art_group_data);

  add_all_textures_from_level(tfrag_level, "ARTSPOOL", tex_db);
  extract_art_groups_from_level(db, tex_db, {}, "ARTSPOOL", tfrag_level, art_group_data);

  std::set<std::string> textures_we_have;
  std::set<u32> textures_we_have_id;

  // put _all_ index textures in common.
  for (const auto& [id, tex] : tex_db.index_textures_by_combo_id) {
    tfrag_level.index_textures.push_back(tex);
  }

  // remember which textures we already added.
  // textures with the same name or the same ID always have the same data.
  for (const auto& t : tfrag_level.textures) {
    textures_we_have.insert(t.debug_name);
    textures_we_have_id.insert(t.combo_id);
  }

  // for common textures, add if the ID isn't there - common textures are looked up by ID.
  for (const auto& [id, normal_texture] : tex_db.textures) {
    if (config.common_tpages.count(normal_texture.page) && !textures_we_have_id.count(id)) {
      textures_we_have.insert(normal_texture.name);
      textures_we_have_id.insert(id);
      tfrag_level.textures.push_back(
          make_texture(id, normal_texture, tex_db.tpage_names.at(normal_texture.page), true));
    }
  }

  // add animated textures that are missing.
  for (const auto& [id, normal_texture] : tex_db.textures) {
    if (config.animated_textures.count(normal_texture.name) &&
        !textures_we_have.count(normal_texture.name)) {
      textures_we_have.insert(normal_texture.name);
      tfrag_level.textures.push_back(
          make_texture(id, normal_texture, tex_db.tpage_names.at(normal_texture.page), false));
    }
  }

  // Gprecompute-deterministic-bake (owner 2026-08-26): DERIVE THE PER-VERTEX TANGENTS HERE, ONCE.
  // They are a pure function of the packed vertices + draws we just built, and the runtime used to
  // re-derive them on EVERY level load on EVERY machine (26.3 MB of output for village1 alone).
  // Baked into the fr3 at 4 bytes/vertex; TFRAG3_VERSION 44 exists for this.
  {
    tfrag3::TangentBakeStats tb;
    tfrag3::bake_deterministic_tangents(tfrag_level, &tb);
  }
  Serializer ser;
  tfrag_level.serialize(ser);
  auto compressed =
      compression::compress_zstd(ser.get_save_result().first, ser.get_save_result().second);

  lg::info("stats for {}", dgo_name);
  print_memory_usage(tfrag_level, ser.get_save_result().second);
  lg::info("compressed: {} -> {} ({:.2f}%)", ser.get_save_result().second, compressed.size(),
           100.f * compressed.size() / ser.get_save_result().second);
  file_util::write_binary_file(
      output_folder / fmt::format("{}.fr3", dgo_name.substr(0, dgo_name.length() - 4)),
      compressed.data(), compressed.size());

  if (config.rip_levels) {
    auto file_path = file_util::get_jak_project_dir() / "decompiler_out" /
                     game_version_names[config.game_version] / "levels" / "common";
    save_level_foreground_as_gltf(tfrag_level, art_group_data, file_path);
  }
}

/*!
 * Write one row per draw: the texture it binds, and the GS wrap settings it is
 * bound with.  CLAMP = 0 on an axis is the game itself declaring that it repeats
 * that texture on that axis, which is the ground truth an image-based
 * seamlessness test can only approximate.  Texture identity is
 * <debug_tpage_name>/<debug_name>, the same identity the tpage PNG dump uses.
 */
void dump_draw_modes(tfrag3::Level& lev, const fs::path& out_folder) {
  std::string result =
      "level,kind,tpage,texture,repeat_s,repeat_t,filter,tcc,alpha_test,alpha_blend,verts,"
      "s_min,s_max,t_min,t_max,owner\n";
  size_t rows = 0, unresolved = 0;

  struct UvRange {
    float smin = 1e30f, smax = -1e30f, tmin = 1e30f, tmax = -1e30f;
    u32 n = 0;
    void add(float s, float t) {
      smin = std::min(smin, s);
      smax = std::max(smax, s);
      tmin = std::min(tmin, t);
      tmax = std::max(tmax, t);
      n++;
    }
  };

  // What the draw belongs to, by name: the merc model, the tie prototype, the
  // shrub prototype.  These are the game's own words for the object a texture
  // is painted on, which no amount of looking at the image can recover.
  auto join_owners = [](const std::vector<std::string>& names) {
    std::string out;
    for (size_t i = 0; i < names.size() && i < 3; i++) {
      if (i) {
        out += "|";
      }
      out += names[i];
    }
    return out;
  };

  auto emit = [&](const char* kind, const DrawMode& m, s32 tex_id, const UvRange& uv,
                  const std::string& owner) {
    if (tex_id < 0 || (size_t)tex_id >= lev.textures.size()) {
      unresolved++;  // negative ids are animated-texture slots, not entries in this table
      return;
    }
    const auto& t = lev.textures[tex_id];
    result += fmt::format("{},{},{},{},{},{},{},{},{},{},{},{:.4f},{:.4f},{:.4f},{:.4f},{}\n",
                          lev.level_name, kind, t.debug_tpage_name, t.debug_name,
                          m.get_clamp_s_enable() ? 0 : 1, m.get_clamp_t_enable() ? 0 : 1,
                          m.get_filt_enable() ? 1 : 0, m.get_tcc_enable() ? 1 : 0,
                          m.get_at_enable() ? 1 : 0, m.get_ab_enable() ? 1 : 0, uv.n,
                          uv.n ? uv.smin : 0.f, uv.n ? uv.smax : 0.f, uv.n ? uv.tmin : 0.f,
                          uv.n ? uv.tmax : 0.f, owner);
    rows++;
  };

  // tfrag and tie: runs + plain indices point straight at the tree's own vertices
  auto strip_uv = [](const tfrag3::StripDraw& d,
                     const std::vector<tfrag3::PreloadedVertex>& verts) {
    UvRange uv;
    auto take = [&](u32 i) {
      if (i < verts.size()) {
        uv.add(verts[i].s, verts[i].t);
      }
    };
    for (const auto& run : d.runs) {
      for (u32 ri = 0; ri < run.length; ri++) {
        take(run.vertex0 + ri);
      }
    }
    for (u32 i : d.plain_indices) {
      take(i);
    }
    return uv;
  };

  for (auto& geo : lev.tfrag_trees) {
    for (auto& tree : geo) {
      if (tree.unpacked.vertices.empty()) {
        tree.unpack();
      }
      for (const auto& d : tree.draws) {
        emit("tfrag", d.mode, d.tree_tex_id, strip_uv(d, tree.unpacked.vertices), "");
      }
    }
  }
  for (auto& geo : lev.tie_trees) {
    for (auto& tree : geo) {
      if (tree.unpacked.vertices.empty()) {
        tree.unpack();
      }
      for (const auto& d : tree.static_draws) {
        std::vector<std::string> owners;
        for (const auto& vg : d.vis_groups) {
          if (vg.tie_proto_idx < tree.proto_names.size()) {
            const auto& nm = tree.proto_names[vg.tie_proto_idx];
            if (std::find(owners.begin(), owners.end(), nm) == owners.end()) {
              owners.push_back(nm);
            }
          }
        }
        emit("tie", d.mode, d.tree_tex_id, strip_uv(d, tree.unpacked.vertices),
             join_owners(owners));
      }
      for (const auto& d : tree.instanced_wind_draws) {
        UvRange uv;
        for (const auto& run : d.vertex_index_stream) {
          if (run < tree.unpacked.vertices.size()) {
            uv.add(tree.unpacked.vertices[run].s, tree.unpacked.vertices[run].t);
          }
        }
        emit("tie-wind", d.mode, d.tree_tex_id, uv, "");
      }
    }
  }
  for (auto& tree : lev.shrub_trees) {
    if (tree.unpacked.vertices.empty()) {
      tree.unpack();
    }
    for (const auto& d : tree.static_draws) {
      UvRange uv;
      for (u32 k = 0; k < d.num_indices; k++) {
        u32 ii = d.first_index_index + k;
        if (ii < tree.indices.size() && tree.indices[ii] < tree.unpacked.vertices.size()) {
          // shrub.vert divides its incoming tex_coord by 4096, so the packed
          // value is not a UV until it is scaled the same way here
          const auto& v = tree.unpacked.vertices[tree.indices[ii]];
          uv.add(v.s / 4096.f, v.t / 4096.f);
        }
      }
      emit("shrub", d.mode, d.tree_tex_id, uv,
           d.proto_idx < tree.proto_names.size() ? tree.proto_names[d.proto_idx] : "");
    }
  }
  for (const auto& model : lev.merc_data.models) {
    for (const auto& eff : model.effects) {
      for (const auto& d : eff.all_draws) {
        UvRange uv;
        for (u32 k = 0; k < d.index_count; k++) {
          u32 ii = d.first_index + k;
          if (ii < lev.merc_data.indices.size() &&
              lev.merc_data.indices[ii] < lev.merc_data.vertices.size()) {
            const auto& v = lev.merc_data.vertices[lev.merc_data.indices[ii]];
            uv.add(v.st[0], v.st[1]);
          }
        }
        emit("merc", d.mode, d.tree_tex_id, uv, model.name);
      }
    }
  }
  for (auto tex_id : lev.hfrag.wang_tree_tex_id) {
    emit("hfrag", lev.hfrag.draw_mode, tex_id, UvRange{}, "");
  }

  file_util::write_text_file(out_folder / fmt::format("{}-draw-modes.csv", lev.level_name), result);
  lg::info("[draw-modes] {}: {} draws over {} textures ({} draws bound an animated slot)",
           lev.level_name, rows, lev.textures.size(), unresolved);
}

void extract_from_level(const ObjectFileDB& db,
                        const TextureDB& tex_db,
                        const std::string& dgo_name,
                        const Config& config,
                        const fs::path& output_folder,
                        const fs::path& entities_folder) {
  if (db.obj_files_by_dgo.count(dgo_name) == 0) {
    lg::warn("Skipping extract for {} because the DGO was not part of the input", dgo_name);
    return;
  }
  tfrag3::Level level_data{};
  std::map<std::string, level_tools::ArtData> art_group_data;
  add_all_textures_from_level(level_data, dgo_name, tex_db);

  // the bsp header file data
  auto bsp_header = extract_bsp_from_level(db, tex_db, dgo_name, config, level_data);
  extract_art_groups_from_level(db, tex_db, bsp_header.texture_remap_table, dgo_name, level_data,
                                art_group_data);

  // Gprecompute-deterministic-bake (owner 2026-08-26): DERIVE THE PER-VERTEX TANGENTS HERE, ONCE.
  // They are a pure function of the packed vertices + draws we just built, and the runtime used to
  // re-derive them on EVERY level load on EVERY machine (26.3 MB of output for village1 alone).
  // Baked into the fr3 at 4 bytes/vertex; TFRAG3_VERSION 44 exists for this.
  {
    tfrag3::TangentBakeStats tb;
    tfrag3::bake_deterministic_tangents(level_data, &tb);
  }
  Serializer ser;
  level_data.serialize(ser);
  auto compressed =
      compression::compress_zstd(ser.get_save_result().first, ser.get_save_result().second);
  lg::info("stats for {}", level_data.level_name);
  print_memory_usage(level_data, ser.get_save_result().second);
  lg::info("compressed: {} -> {} ({:.2f}%)", ser.get_save_result().second, compressed.size(),
           100.f * compressed.size() / ser.get_save_result().second);
  file_util::write_binary_file(output_folder / fmt::format("{}.fr3", level_data.level_name),
                               compressed.data(), compressed.size());

  if (config.dump_draw_modes) {
    dump_draw_modes(level_data, output_folder);
  }

  if (config.rip_levels) {
    auto back_file_path = file_util::get_jak_project_dir() / "decompiler_out" /
                          game_version_names[config.game_version] / "levels" /
                          level_data.level_name /
                          fmt::format("{}-background.glb", level_data.level_name);
    file_util::create_dir_if_needed_for_file(back_file_path);
    save_level_background_as_gltf(level_data, back_file_path);
    auto fore_file_path = file_util::get_jak_project_dir() / "decompiler_out" /
                          game_version_names[config.game_version] / "levels" /
                          level_data.level_name;
    save_level_foreground_as_gltf(level_data, art_group_data, fore_file_path);
  }
  file_util::write_text_file(entities_folder / fmt::format("{}-actors.json", level_data.level_name),
                             extract_actors_to_json(bsp_header.actors));
  if (config.game_version == GameVersion::Jak1)
    file_util::write_text_file(
        entities_folder / fmt::format("{}-ambients.json", level_data.level_name),
        extract_ambients_to_json(bsp_header.ambients));
}

void extract_all_levels(const ObjectFileDB& db,
                        const TextureDB& tex_db,
                        const std::vector<std::string>& dgo_names,
                        const std::string& common_name,
                        const Config& config,
                        const fs::path& output_path) {
  extract_common(db, tex_db, common_name, output_path, config);
  auto entities_dir = file_util::get_jak_project_dir() / "decompiler_out" /
                      game_version_names[config.game_version] / "entities";
  file_util::create_dir_if_needed(entities_dir);
  SimpleThreadGroup threads;
  threads.run(
      [&](int idx) {
        extract_from_level(db, tex_db, dgo_names[idx], config, output_path, entities_dir);
      },
      dgo_names.size());
  threads.join();
}

}  // namespace decompiler
