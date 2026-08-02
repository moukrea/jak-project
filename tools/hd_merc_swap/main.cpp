// Grecharged-hd-models3 BRICK 2: offline SURGICAL merc swap + integrity diff + per-draw
// texture-page audit for the enhanced HD character models.
//
// Motivation: round-2's enhanced bake re-decompiled the WHOLE level FR3 from the ISO
// (restricted DGO set) to swap the character merc models. That regenerated every
// non-character draw and dropped level-wide texture references -> the owner's "tout violet"
// magenta ground. This tool instead loads the STOCK <level>.fr3 and swaps ONLY the named
// merc model(s) in memory (via the existing decompiler::replace_model), then re-serializes.
// Every non-character draw is therefore byte-identical to stock BY CONSTRUCTION, and the
// `diff` mode PROVES it (serialize everything except merc_data + the appended merc textures,
// byte-compare stock vs enhanced).
//
// Modes:
//   swap  <in.fr3> <out.fr3> name1=glb1 [name2=glb2 ...]
//   diff  <stock.fr3> <enhanced.fr3>          (non-character byte-identity proof)
//   audit <fr3> [name ...]                    (per-model, per-draw texture-page table)
//   add   <stock.fr3> <name>-lod0.glb <out.fr3>  (BRICK 4: APPEND a NEW named merc model)
//
// Read-only on inputs; only `swap` and `add` write (to <out.fr3>).
//
// Grecharged-hd-models3 (BRICK 4): the HD character ANIMATION-RETARGET feature needs a NEW
// named MercModel (jak-highres-lod0, the HD Jak skin with its own 74-joint skeleton + authored
// weights) present in a stock fr3 so Merc2::handle_pc_model's by-name lookup resolves it. The
// decompiler only had replace_model (SWAP an existing model) and build_actor does not emit fr3
// data. `add` closes that gap: it loads the stock fr3 and APPENDS the new model via the strictly
// append-only decompiler::add_named_merc_model_to_level, keeping the brick-2 integrity guarantee
// (every pre-existing model + non-character draw/texture byte-identical to stock; only a new
// model appended). The model name is taken from the GLB filename stem (jak-highres-lod0.glb ->
// "jak-highres-lod0").

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "common/custom_data/Tfrag3Data.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"

// replace_model lives in decompiler/level_extractor/extract_merc.cpp (part of the `decomp`
// library) and has no public header declaration; forward-declare the exact signature.
namespace decompiler {
void replace_model(tfrag3::Level& lvl, tfrag3::MercModel& model, const fs::path& mdl_path);
size_t add_named_merc_model_to_level(tfrag3::Level& lvl,
                                     const std::string& name,
                                     const fs::path& mdl_path);
}

namespace {

void load_fr3(const fs::path& path, tfrag3::Level& lev) {
  auto data = file_util::read_binary_file(path);
  auto decomp = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp.data(), decomp.size());
  lev.serialize(ser);
}

void write_fr3(const fs::path& path, tfrag3::Level& lev) {
  Serializer ser;
  lev.serialize(ser);
  auto compressed =
      compression::compress_zstd(ser.get_save_result().first, ser.get_save_result().second);
  file_util::write_binary_file(path, compressed.data(), compressed.size());
}

// Serialize everything EXCEPT the merc model group and the merc-appended textures. Truncating
// textures/index_textures to the stock counts drops the merc-appended entries; clearing
// merc_data drops the swapped model + its vertices/indices. What remains is exactly the
// non-character world (tfrag/tie/shrub/hfrag/collision + all pre-existing textures).
std::vector<u8> serialize_non_merc(const tfrag3::Level& src, size_t tex_count, size_t idxtex_count) {
  tfrag3::Level copy = src;  // deep copy (all std::vector)
  if (copy.textures.size() > tex_count) {
    copy.textures.resize(tex_count);
  }
  if (copy.index_textures.size() > idxtex_count) {
    copy.index_textures.resize(idxtex_count);
  }
  copy.merc_data = tfrag3::MercModelGroup{};  // clear all merc models/vertices/indices
  Serializer ser;
  copy.serialize(ser);
  auto res = ser.get_save_result();
  return std::vector<u8>((const u8*)res.first, (const u8*)res.first + res.second);
}

void print_merc_summary(const char* tag, const tfrag3::Level& lev) {
  fmt::print("  [{}] textures={} index_textures={} merc_models={} merc_verts={} merc_indices={}\n",
             tag, lev.textures.size(), lev.index_textures.size(), lev.merc_data.models.size(),
             lev.merc_data.vertices.size(), lev.merc_data.indices.size());
}

std::string tex_label(const tfrag3::Level& lev, s32 id) {
  if (id < 0) {
    return fmt::format("<anim-slot {}>", id);
  }
  if ((size_t)id >= lev.textures.size()) {
    return fmt::format("<OOB id {}>", id);
  }
  const auto& t = lev.textures[id];
  return fmt::format("{} [tpage={} {}x{} combo={:#x}]", t.debug_name, t.debug_tpage_name, t.w, t.h,
                     t.combo_id);
}

int do_audit(const fs::path& fr3, const std::vector<std::string>& names) {
  tfrag3::Level lev;
  load_fr3(fr3, lev);
  fmt::print("== AUDIT {} ==\n", fr3.string());
  print_merc_summary("level", lev);
  for (const auto& model : lev.merc_data.models) {
    if (!names.empty() &&
        std::find(names.begin(), names.end(), model.name) == names.end()) {
      continue;
    }
    u32 tot_tris = 0, tot_draws = 0;
    for (const auto& e : model.effects) {
      for (const auto& d : e.all_draws) {
        tot_tris += d.num_triangles;
        tot_draws++;
      }
    }
    fmt::print("\nMODEL {}  max_bones={} effects={} total_draws={} total_tris={}\n", model.name,
               model.max_bones, model.effects.size(), tot_draws, tot_tris);
    for (size_t ei = 0; ei < model.effects.size(); ei++) {
      const auto& e = model.effects[ei];
      fmt::print("  effect[{}] has_envmap={} envmap_texture={} draws={}\n", ei, e.has_envmap,
                 e.envmap_texture, e.all_draws.size());
      for (size_t di = 0; di < e.all_draws.size(); di++) {
        const auto& d = e.all_draws[di];
        const char* binds = (d.tree_tex_id >= 0) ? "REAL" : "NONE";
        std::string eye = (d.eye_id != 0xff) ? fmt::format(" eye_id={:#x}", d.eye_id) : "";
        fmt::print("    draw[{}] tris={} tex_id={} -> {} [{}]{}\n", di, d.num_triangles,
                   d.tree_tex_id, tex_label(lev, d.tree_tex_id), binds, eye);
      }
    }
  }
  return 0;
}

int do_diff(const fs::path& a, const fs::path& b) {
  tfrag3::Level la, lb;
  load_fr3(a, la);
  load_fr3(b, lb);
  fmt::print("== DIFF (non-character byte-identity) ==\n");
  fmt::print("  stock:    {}\n", a.string());
  print_merc_summary("stock", la);
  fmt::print("  enhanced: {}\n", b.string());
  print_merc_summary("enhanced", lb);

  // reference counts = stock's texture/index-texture counts; enhanced's extra (merc) textures
  // are the appended tail and are excluded from the non-character comparison.
  size_t ref_tex = la.textures.size();
  size_t ref_idxtex = la.index_textures.size();

  if (lb.textures.size() < ref_tex) {
    fmt::print("  FAIL: enhanced has FEWER textures ({}) than stock ({}) -> texture list was "
               "rewritten, not appended\n",
               lb.textures.size(), ref_tex);
    return 2;
  }

  auto na = serialize_non_merc(la, ref_tex, ref_idxtex);
  auto nb = serialize_non_merc(lb, ref_tex, ref_idxtex);

  fmt::print("  non-merc serialized bytes: stock={} enhanced={}\n", na.size(), nb.size());
  if (na.size() != nb.size()) {
    fmt::print("  RESULT: DIFFER (size mismatch) -> non-character data changed. INTEGRITY FAIL\n");
    return 1;
  }
  size_t first_diff = SIZE_MAX;
  for (size_t i = 0; i < na.size(); i++) {
    if (na[i] != nb[i]) {
      first_diff = i;
      break;
    }
  }
  if (first_diff == SIZE_MAX) {
    fmt::print("  RESULT: IDENTICAL — every non-character draw/texture is byte-identical to "
               "stock. INTEGRITY PASS\n");
    fmt::print("  (enhanced adds {} merc textures + {} merc verts + {} merc indices on top)\n",
               lb.textures.size() - ref_tex, lb.merc_data.vertices.size(),
               lb.merc_data.indices.size());
    return 0;
  }
  fmt::print("  RESULT: DIFFER at byte offset {} (stock=0x{:02x} enh=0x{:02x}). INTEGRITY FAIL\n",
             first_diff, na[first_diff], nb[first_diff]);
  return 1;
}

int do_swap(const fs::path& in, const fs::path& out, const std::vector<std::string>& specs) {
  tfrag3::Level lev;
  load_fr3(in, lev);
  fmt::print("== SWAP {} -> {} ==\n", in.string(), out.string());
  print_merc_summary("before", lev);
  int swapped = 0, missing = 0;
  for (const auto& spec : specs) {
    auto eq = spec.find('=');
    if (eq == std::string::npos) {
      fmt::print("  bad spec (need name=glb): {}\n", spec);
      return 2;
    }
    std::string name = spec.substr(0, eq);
    fs::path glb = spec.substr(eq + 1);
    if (!file_util::file_exists(glb.string())) {
      fmt::print("  GLB missing for {}: {}\n", name, glb.string());
      return 2;
    }
    auto it = std::find_if(lev.merc_data.models.begin(), lev.merc_data.models.end(),
                           [&](const auto& m) { return m.name == name; });
    if (it == lev.merc_data.models.end()) {
      fmt::print("  merc model '{}' NOT PRESENT in this fr3 (no swap)\n", name);
      missing++;
      continue;
    }
    // replace_model emits the "Replacing <name> for <lvl>: ..." line (max_bones<100 guard).
    decompiler::replace_model(lev, *it, glb);
    swapped++;
  }
  print_merc_summary("after", lev);
  write_fr3(out, lev);
  fmt::print("  wrote {} ({} swapped, {} missing)\n", out.string(), swapped, missing);
  return missing > 0 ? 3 : 0;
}

int do_add(const fs::path& in, const fs::path& glb, const fs::path& out) {
  if (!file_util::file_exists(glb.string())) {
    fmt::print("  GLB missing: {}\n", glb.string());
    return 2;
  }
  // model name := GLB filename stem, e.g. jak-highres-lod0.glb -> "jak-highres-lod0".
  const std::string name = glb.stem().string();

  tfrag3::Level lev;
  load_fr3(in, lev);
  fmt::print("== ADD {} + {} -> {} ==\n", in.string(), glb.string(), out.string());
  fmt::print("  new model name: '{}'\n", name);
  print_merc_summary("before", lev);

  // guard: this is an APPEND, not a replace — refuse if the name already exists in stock.
  auto existing = std::find_if(lev.merc_data.models.begin(), lev.merc_data.models.end(),
                               [&](const auto& m) { return m.name == name; });
  if (existing != lev.merc_data.models.end()) {
    fmt::print("  model '{}' ALREADY present in stock fr3 -> refusing to append a duplicate "
               "(use `swap` to replace it)\n",
               name);
    return 3;
  }

  size_t before_models = lev.merc_data.models.size();
  size_t before_verts = lev.merc_data.vertices.size();
  size_t before_indices = lev.merc_data.indices.size();
  size_t before_textures = lev.textures.size();

  size_t idx = decompiler::add_named_merc_model_to_level(lev, name, glb);
  print_merc_summary("after", lev);

  if (lev.merc_data.models.size() != before_models + 1) {
    fmt::print("  FAIL: expected exactly one new model, got {} -> {}\n", before_models,
               lev.merc_data.models.size());
    return 4;
  }
  const auto& m = lev.merc_data.models.at(idx);
  u32 tot_tris = 0, tot_draws = 0;
  for (const auto& e : m.effects) {
    for (const auto& d : e.all_draws) {
      tot_tris += d.num_triangles;
      tot_draws++;
    }
  }
  fmt::print("  APPENDED model[{}] name='{}' max_bones={} effects={} draws={} tris={}\n", idx,
             m.name, m.max_bones, m.effects.size(), tot_draws, tot_tris);
  fmt::print("  delta: +{} model, +{} merc_verts, +{} merc_indices, +{} textures\n",
             lev.merc_data.models.size() - before_models,
             lev.merc_data.vertices.size() - before_verts,
             lev.merc_data.indices.size() - before_indices, lev.textures.size() - before_textures);

  write_fr3(out, lev);
  fmt::print("  wrote {}\n", out.string());
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  file_util::setup_project_path(std::nullopt);
  lg::set_stdout_level(lg::level::info);
  lg::initialize();

  if (argc < 2) {
    fmt::print("usage:\n"
               "  hd_merc_swap swap  <in.fr3> <out.fr3> name1=glb1 [name2=glb2 ...]\n"
               "  hd_merc_swap diff  <stock.fr3> <enhanced.fr3>\n"
               "  hd_merc_swap audit <fr3> [name ...]\n"
               "  hd_merc_swap add   <stock.fr3> <name>-lod0.glb <out.fr3>\n");
    return 2;
  }
  std::string mode = argv[1];
  if (mode == "audit") {
    if (argc < 3) { fmt::print("audit needs <fr3>\n"); return 2; }
    std::vector<std::string> names;
    for (int i = 3; i < argc; i++) names.push_back(argv[i]);
    return do_audit(argv[2], names);
  }
  if (mode == "diff") {
    if (argc < 4) { fmt::print("diff needs <stock.fr3> <enhanced.fr3>\n"); return 2; }
    return do_diff(argv[2], argv[3]);
  }
  if (mode == "swap") {
    if (argc < 5) { fmt::print("swap needs <in.fr3> <out.fr3> name=glb...\n"); return 2; }
    std::vector<std::string> specs;
    for (int i = 4; i < argc; i++) specs.push_back(argv[i]);
    return do_swap(argv[2], argv[3], specs);
  }
  if (mode == "add") {
    if (argc < 5) { fmt::print("add needs <stock.fr3> <name>-lod0.glb <out.fr3>\n"); return 2; }
    return do_add(argv[2], argv[3], argv[4]);
  }
  fmt::print("unknown mode '{}'\n", mode);
  return 2;
}
