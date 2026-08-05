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
//   blerc-stats <fr3> <model-name>            (per-(effect,target) blend-shape displacement stats)
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
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <tuple>
#include <vector>

#include "common/custom_data/Tfrag3Data.h"
#include "common/log/log.h"
#include "common/texture/texture_slots.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"
#include "third-party/tiny_gltf/tiny_gltf.h"

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
      // blerc/mod summary (defect class B): does this effect carry facial blend-shape data?
      // int_data is per-vertex [tgt0_idx, ..., terminator, dest]: targets are before each
      // terminator, the following word is a vertex index and must be skipped.
      u32 max_target = 0;
      size_t blerc_verts = 0;
      for (size_t bi = 0; bi < e.mod.blerc.int_data.size(); bi++) {
        u32 v = e.mod.blerc.int_data[bi];
        if (v == tfrag3::Blerc::kTargetIdxTerminator) {
          bi++;  // skip dest
          blerc_verts++;
        } else if (v > max_target) {
          max_target = v;
        }
      }
      fmt::print(
          "  effect[{}] has_envmap={} envmap_texture={} envmap_mode={:#x} draws={} "
          "has_mod_draw={} mod_draws={} fix_draws={} mod_verts={} blerc_verts={} "
          "blerc_floats={} max_blerc_target={}\n",
          ei, e.has_envmap, e.envmap_texture, e.envmap_mode.as_int(), e.all_draws.size(),
          e.has_mod_draw, e.mod.mod_draw.size(), e.mod.fix_draw.size(), e.mod.vertices.size(),
          blerc_verts, e.mod.blerc.float_data.size(), max_target);
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

// STAMP mode (defect classes C/E/A, cycle 2): back-annotate a ripped donor GLB with the donor
// fr3's EXACT per-draw GS draw mode, eye slot, and effect index as GLB extras
// (goal_draw_mode / goal_eye_id on the material, goal_effect_idx on the prim). The GLB
// alphaMode/sampler reconstruction is lossy (BLEND loses depth-write -> see-through fur/jaw/
// hair; eye_id is unrepresentable -> white eyes); these extras let the importer restore the
// donor look verbatim. Relies on (and loudly ASSERTS) the exporter invariant that GLB prim
// order == donor (effect, draw) order with matching triangle counts.
int do_stamp(const fs::path& donor_fr3,
             const std::string& model_name,
             const fs::path& in_glb,
             const fs::path& out_glb) {
  tfrag3::Level lev;
  load_fr3(donor_fr3, lev);
  auto it = std::find_if(lev.merc_data.models.begin(), lev.merc_data.models.end(),
                         [&](const auto& m) { return m.name == model_name; });
  if (it == lev.merc_data.models.end()) {
    fmt::print("  STAMP FAIL: model '{}' not in {}\n", model_name, donor_fr3.string());
    return 2;
  }
  struct Ref {
    int effect;
    const tfrag3::MercDraw* d;
  };
  std::vector<Ref> flat;
  for (size_t ei = 0; ei < it->effects.size(); ei++) {
    for (const auto& d : it->effects[ei].all_draws) {
      flat.push_back({(int)ei, &d});
    }
  }

  tinygltf::Model model;
  tinygltf::TinyGLTF loader;
  std::string err, warn;
  if (!loader.LoadBinaryFromFile(&model, &err, &warn, in_glb.string())) {
    fmt::print("  STAMP FAIL: cannot load {}: {}\n", in_glb.string(), err);
    return 2;
  }
  if (model.meshes.size() != 1) {
    fmt::print("  STAMP FAIL: expected 1 mesh in the rip GLB, got {}\n", model.meshes.size());
    return 2;
  }
  auto& mesh = model.meshes[0];
  if (mesh.primitives.size() != flat.size()) {
    fmt::print("  STAMP FAIL: prim count {} != donor draw count {} — prim/draw order invariant "
               "broken, refusing to stamp\n",
               mesh.primitives.size(), flat.size());
    return 2;
  }
  // (original material, draw mode, eye_id) -> material index carrying that stamp. A single GLB
  // material can legitimately back draws with DIFFERENT GS modes: the rip merges materials by
  // texture, while the donor fr3 can draw that one texture with several modes (e.g. opaque +
  // alpha-blended passes) or several eye slots. Instead of failing, CLONE the material per
  // variant so every draw keeps its exact donor mode/eye slot.
  std::map<std::tuple<int, u32, int>, int> mat_variant;
  int eye_stamps = 0;
  int split_count = 0;
  for (size_t i = 0; i < mesh.primitives.size(); i++) {
    auto& prim = mesh.primitives[i];
    const auto& ref = flat[i];
    u32 prim_tris = (u32)model.accessors.at(prim.indices).count / 3;
    if (prim_tris != ref.d->num_triangles) {
      fmt::print("  STAMP FAIL: prim[{}] has {} tris but donor draw has {} — order invariant "
                 "broken, refusing to stamp\n",
                 i, prim_tris, ref.d->num_triangles);
      return 2;
    }
    tinygltf::Value::Object pex;
    pex["goal_effect_idx"] = tinygltf::Value(ref.effect);
    prim.extras = tinygltf::Value(pex);

    if (prim.material < 0) {
      fmt::print("  STAMP FAIL: prim[{}] has no material (anim-slot draw?) — unsupported\n", i);
      return 2;
    }
    const int orig_mat = prim.material;
    const u32 mode = ref.d->mode.as_int();
    const int eye = (int)ref.d->eye_id;
    const auto key = std::make_tuple(orig_mat, mode, eye);
    auto found = mat_variant.find(key);
    if (found != mat_variant.end()) {
      // identical (material, mode, eye) already stamped — reuse it (possibly a clone)
      prim.material = found->second;
      continue;
    }

    tinygltf::Value::Object mex;
    mex["goal_draw_mode"] = tinygltf::Value((int)mode);
    if (ref.d->eye_id != 0xff) {
      mex["goal_eye_id"] = tinygltf::Value(eye);
      eye_stamps++;
    }

    bool orig_taken = false;
    for (const auto& kv : mat_variant) {
      if (std::get<0>(kv.first) == orig_mat) {
        orig_taken = true;
        break;
      }
    }
    int target;
    if (!orig_taken) {
      target = orig_mat;
    } else {
      tinygltf::Material clone = model.materials[orig_mat];
      target = (int)model.materials.size();
      model.materials.push_back(clone);
      split_count++;
      fmt::print("  STAMP SPLIT: material {} -> {} mode {:#x} (one texture, multiple donor "
                 "modes)\n",
                 orig_mat, target, mode);
    }
    model.materials[target].extras = tinygltf::Value(mex);
    prim.material = target;
    mat_variant[key] = target;
  }

  tinygltf::TinyGLTF gltf;
  if (!gltf.WriteGltfSceneToFile(&model, out_glb.string(), true /*embedImages*/,
                                 true /*embedBuffers*/, false /*pretty*/, true /*binary*/)) {
    fmt::print("  STAMP FAIL: cannot write {}\n", out_glb.string());
    return 2;
  }
  fmt::print("  STAMPED {} prims / {} materials ({} eye draws, {} splits) from '{}' -> {}\n",
             mesh.primitives.size(), mat_variant.size(), eye_stamps, split_count, model_name,
             out_glb.string());
  return 0;
}

// defect class A (white eyes): donor eye draws carry jak2/jak3 eye slots (e.g. 0x80/0x81),
// meaningless to jak1's EyeRenderer (lookup is slot % 40 into the jak1 eye array). The HD model
// must sample the DRIVER's composited eye texture, whose slot is static in the driver's stock
// merc model in this same fr3. Remap left->left, right->right (low bit = is_right).
// the driver ("stock") model's eye slots: shared by the all_draws remap below and by the
// blerc port (which re-emits fix/mod draws carrying donor eye ids).
int find_stock_eye_slots(const tfrag3::Level& lev,
                         const std::string& eye_from,
                         int& stock_left,
                         int& stock_right) {
  stock_left = -1;
  stock_right = -1;
  auto stock = std::find_if(lev.merc_data.models.begin(), lev.merc_data.models.end(),
                            [&](const auto& m) { return m.name == eye_from; });
  if (stock == lev.merc_data.models.end()) {
    fmt::print("  EYE-REMAP FAIL: stock model '{}' not in this fr3\n", eye_from);
    return 5;
  }
  for (const auto& e : stock->effects) {
    for (const auto& d : e.all_draws) {
      if (d.eye_id != 0xff) {
        ((d.eye_id & 1) ? stock_right : stock_left) = d.eye_id;
      }
    }
  }
  if (stock_left < 0 && stock_right < 0) {
    fmt::print("  EYE-REMAP FAIL: stock model '{}' has no eye draws (no eye slot to inherit)\n",
               eye_from);
    return 5;
  }
  return 0;
}

// driver_lev is the level the DRIVER (eye_from) model is looked up in — usually the target level
// itself, but for models whose driver only exists in another level fr3 (e.g. assistant-lod0 /
// sage-lod0, which live in village1.fr3) the caller passes that fr3's level instead.
int remap_eye_ids(tfrag3::Level& lev,
                  tfrag3::MercModel& appended,
                  const std::string& eye_from,
                  const tfrag3::Level& driver_lev) {
  (void)lev;
  int stock_left = -1, stock_right = -1;
  int erc = find_stock_eye_slots(driver_lev, eye_from, stock_left, stock_right);
  if (erc != 0) {
    return erc;
  }
  int remapped = 0;
  for (auto& e : appended.effects) {
    for (auto& d : e.all_draws) {
      if (d.eye_id == 0xff) {
        continue;
      }
      int want = (d.eye_id & 1) ? stock_right : stock_left;
      if (want < 0) {
        fmt::print("  EYE-REMAP FAIL: appended draw is a {} eye but stock '{}' has none\n",
                   (d.eye_id & 1) ? "RIGHT" : "LEFT", eye_from);
        return 5;
      }
      fmt::print("  EYE-REMAP: draw eye_id {:#x} (donor) -> {:#x} (driver slot {})\n", d.eye_id,
                 want, want >> 1);
      d.eye_id = (u8)want;
      remapped++;
    }
  }
  fmt::print("  EYE-REMAP: {} eye draws now bound to '{}' slots (L={:#x} R={:#x})\n", remapped,
             eye_from, stock_left, stock_right);
  return 0;
}

// ---------------------------------------------------------------------------------------------
// defect class B (hd-models4): BLERC PORT — carry the donor model's facial blend-shape data onto
// the appended HD model, with the donor's target indices remapped to the jak1 DRIVER's blerc
// channels (the GOAL side sends the driver's weight vector; donor target ids are meaningless).
//
// Render semantics (Merc2.cpp:353-405, 1205-1241): when blerc weights arrive, an effect with
// has_mod_draw renders mod.fix_draw (index values are LEVEL vertex indices) + mod.mod_draw (index
// values are MOD-LOCAL indices into effect.mod.vertices, drawn from a dynamic VBO built by copying
// mod.vertices and applying blerc). All draws' first_index points into lev.merc_data.indices.
// ---------------------------------------------------------------------------------------------

constexpr int MAX_MOD_VTX_LIMIT = 65535;  // Merc2.h MAX_MOD_VTX == UINT16_MAX

struct BlercVert {
  std::vector<u32> tgts;  // target indices, in order
  size_t float_base = 0;  // index of the base BlercFloatData; deltas follow in tgts order
  u32 dest = 0;
};

// walk the [tgt..., terminator, dest] / [base, tgt-deltas...] pair of arrays.
bool parse_blerc(const tfrag3::Blerc& b, std::vector<BlercVert>& out) {
  out.clear();
  size_t fi = 0, ii = 0;
  while (ii < b.int_data.size()) {
    BlercVert v;
    v.float_base = fi;
    if (fi >= b.float_data.size()) {
      return false;
    }
    fi++;
    while (ii < b.int_data.size() && b.int_data[ii] != tfrag3::Blerc::kTargetIdxTerminator) {
      v.tgts.push_back(b.int_data[ii]);
      ii++;
      fi++;
    }
    if (ii + 1 >= b.int_data.size()) {
      return false;  // missing terminator or dest
    }
    v.dest = b.int_data[ii + 1];
    ii += 2;
    if (fi > b.float_data.size()) {
      return false;
    }
    out.push_back(std::move(v));
  }
  return fi == b.float_data.size();
}

// hd-models4 cycle-4: BLERC BAKE — fold ONE donor blerc target into the donor's BASE geometry at
// weight 1.0 and strip that target, so the appended model ships the displaced pose statically and
// the target can never reach the runtime channel remap.
//
// Mirrors blerc_avx (Merc2.cpp:302-347) exactly: per blerc vertex the runtime starts from
// float_data[float_base] (v[0..3] = pos+pad, v[4..7] = normal+pad), adds every target delta scaled
// by its channel weight, and STORES the result into mod.vertices[dest].pos / .normal (a full 4-wide
// store, so pad0/pad1 come from the float data too). Baking channel N at weight 1.0 is therefore:
//   base.v[i] += delta_N.v[i]   (all 8 lanes)
//   mod.vertices[dest].pos/normal := the new base   (what the static mod VBO renders)
// and then dropping delta_N from the [tgt..., terminator, dest] / [base, deltas...] pair of arrays.
int bake_blerc_target(tfrag3::MercModel& donor, int target) {
  size_t effects_touched = 0, verts_moved = 0;
  double max_disp = 0;
  for (size_t ei = 0; ei < donor.effects.size(); ei++) {
    auto& mod = donor.effects[ei].mod;
    if (mod.blerc.int_data.empty()) {
      continue;
    }
    std::vector<BlercVert> bverts;
    if (!parse_blerc(mod.blerc, bverts)) {
      fmt::print("  BLERC-BAKE FAIL: effect[{}] donor blerc data is malformed\n", ei);
      return 7;
    }
    tfrag3::Blerc nb;
    size_t moved_here = 0;
    for (const auto& v : bverts) {
      tfrag3::BlercFloatData base = mod.blerc.float_data[v.float_base];
      bool baked = false;
      std::vector<u32> keep_t;
      std::vector<tfrag3::BlercFloatData> keep_d;
      for (size_t k = 0; k < v.tgts.size(); k++) {
        const auto& d = mod.blerc.float_data[v.float_base + 1 + k];
        if ((int)v.tgts[k] == target) {
          for (int c = 0; c < 8; c++) {
            base.v[c] += d.v[c];
          }
          double m = std::sqrt((double)d.v[0] * d.v[0] + (double)d.v[1] * d.v[1] +
                               (double)d.v[2] * d.v[2]);
          if (m > 0) {
            moved_here++;
            verts_moved++;
            max_disp = std::max(max_disp, m);
          }
          baked = true;
        } else {
          keep_t.push_back(v.tgts[k]);
          keep_d.push_back(d);
        }
      }
      nb.float_data.push_back(base);
      for (size_t k = 0; k < keep_t.size(); k++) {
        nb.int_data.push_back(keep_t[k]);
        nb.float_data.push_back(keep_d[k]);
      }
      nb.int_data.push_back(tfrag3::Blerc::kTargetIdxTerminator);
      nb.int_data.push_back(v.dest);
      if (baked && v.dest < mod.vertices.size()) {
        auto& mv = mod.vertices[v.dest];
        mv.pos[0] = base.v[0];
        mv.pos[1] = base.v[1];
        mv.pos[2] = base.v[2];
        mv.pad0 = base.v[3];
        mv.normal[0] = base.v[4];
        mv.normal[1] = base.v[5];
        mv.normal[2] = base.v[6];
        mv.pad1 = base.v[7];
      }
    }
    mod.blerc = nb;
    if (moved_here) {
      effects_touched++;
    }
  }
  if (verts_moved == 0) {
    fmt::print("  BLERC-BAKE FAIL: target={} moves no vertices\n", target);
    return 7;
  }
  fmt::print("  BLERC-BAKE: target={} effects_touched={} verts_moved={} max_disp={:.6g}\n", target,
             effects_touched, verts_moved, max_disp);
  return 0;
}

// per-(effect, target) displacement statistics of a model's blerc data. mean_vec (the AVERAGE delta
// vector, not the average magnitude) separates a rigid translation of a part — e.g. a goggle
// sliding down, where every vertex shares one direction so |mean_vec| ~= mean_abs — from a
// scattered facial morph, where opposing deltas cancel and |mean_vec| << mean_abs.
int do_blerc_stats(const fs::path& fr3, const std::string& name) {
  tfrag3::Level lev;
  load_fr3(fr3, lev);
  auto it = std::find_if(lev.merc_data.models.begin(), lev.merc_data.models.end(),
                         [&](const auto& m) { return m.name == name; });
  if (it == lev.merc_data.models.end()) {
    fmt::print("  model '{}' not in {}\n", name, fr3.string());
    return 2;
  }
  const auto& model = *it;
  fmt::print("== BLERC-STATS {} {} ==\n", fr3.string(), model.name);
  for (size_t ei = 0; ei < model.effects.size(); ei++) {
    const auto& b = model.effects[ei].mod.blerc;
    if (b.int_data.empty()) {
      continue;
    }
    std::vector<BlercVert> bverts;
    if (!parse_blerc(b, bverts)) {
      fmt::print("  BLERC-STATS FAIL: effect[{}] blerc int/float data is malformed\n", ei);
      return 2;
    }
    std::string draw0 = "<no-draws>";
    if (!model.effects[ei].all_draws.empty()) {
      s32 id = model.effects[ei].all_draws[0].tree_tex_id;
      draw0 = (id >= 0 && (size_t)id < lev.textures.size()) ? lev.textures[id].debug_name
                                                            : tex_label(lev, id);
    }
    struct Acc {
      size_t n = 0;
      double sum_abs = 0, max_abs = 0;
      double sum[3] = {0, 0, 0};
    };
    std::map<u32, Acc> acc;
    for (const auto& v : bverts) {
      for (size_t k = 0; k < v.tgts.size(); k++) {
        const auto& d = b.float_data[v.float_base + 1 + k];
        double m =
            std::sqrt((double)d.v[0] * d.v[0] + (double)d.v[1] * d.v[1] + (double)d.v[2] * d.v[2]);
        if (m <= 0) {
          continue;
        }
        auto& a = acc[v.tgts[k]];
        a.n++;
        a.sum_abs += m;
        a.max_abs = std::max(a.max_abs, m);
        a.sum[0] += d.v[0];
        a.sum[1] += d.v[1];
        a.sum[2] += d.v[2];
      }
    }
    for (const auto& [t, a] : acc) {
      fmt::print("BLERC-STATS effect={} draw0={} target={} verts={} mean_abs={:.6g} max_abs={:.6g} "
                 "mean_vec=({:.6g},{:.6g},{:.6g})\n",
                 ei, draw0, t, a.n, a.sum_abs / (double)a.n, a.max_abs, a.sum[0] / (double)a.n,
                 a.sum[1] / (double)a.n, a.sum[2] / (double)a.n);
    }
  }
  return 0;
}

struct ChanSample {
  float p[3];  // normalized base position
  float d[3];  // target delta (raw)
};

// all blerc samples of a model, grouped by target/channel index. positions are normalized
// (centroid-subtracted, RMS-radius-divided) so rigs of different proportions can be matched.
bool collect_blerc_samples(const tfrag3::MercModel& m,
                           std::map<u32, std::vector<ChanSample>>& out,
                           u32& max_idx,
                           std::string& err) {
  out.clear();
  max_idx = 0;
  std::vector<std::array<float, 3>> bases;
  struct Raw {
    size_t base_slot;
    float d[3];
    u32 chan;
  };
  std::vector<Raw> raws;
  for (size_t ei = 0; ei < m.effects.size(); ei++) {
    const auto& b = m.effects[ei].mod.blerc;
    if (b.int_data.empty()) {
      continue;
    }
    std::vector<BlercVert> verts;
    if (!parse_blerc(b, verts)) {
      err = fmt::format("model '{}' effect[{}] blerc int/float data is malformed", m.name, ei);
      return false;
    }
    for (const auto& v : verts) {
      size_t slot = bases.size();
      const auto& bf = b.float_data[v.float_base];
      bases.push_back({bf.v[0], bf.v[1], bf.v[2]});
      for (size_t k = 0; k < v.tgts.size(); k++) {
        const auto& df = b.float_data[v.float_base + 1 + k];
        Raw r;
        r.base_slot = slot;
        r.d[0] = df.v[0];
        r.d[1] = df.v[1];
        r.d[2] = df.v[2];
        r.chan = v.tgts[k];
        max_idx = std::max(max_idx, r.chan);
        raws.push_back(r);
      }
    }
  }
  if (bases.empty()) {
    err = fmt::format("model '{}' has no blerc data", m.name);
    return false;
  }
  double cx = 0, cy = 0, cz = 0;
  for (const auto& b : bases) {
    cx += b[0];
    cy += b[1];
    cz += b[2];
  }
  cx /= bases.size();
  cy /= bases.size();
  cz /= bases.size();
  double r2 = 0;
  for (const auto& b : bases) {
    double dx = b[0] - cx, dy = b[1] - cy, dz = b[2] - cz;
    r2 += dx * dx + dy * dy + dz * dz;
  }
  double rms = std::sqrt(r2 / bases.size());
  if (rms <= 0) {
    err = fmt::format("model '{}' blerc base positions are degenerate (rms radius 0)", m.name);
    return false;
  }
  for (const auto& r : raws) {
    ChanSample s;
    s.p[0] = (float)((bases[r.base_slot][0] - cx) / rms);
    s.p[1] = (float)((bases[r.base_slot][1] - cy) / rms);
    s.p[2] = (float)((bases[r.base_slot][2] - cz) / rms);
    s.d[0] = r.d[0];
    s.d[1] = r.d[1];
    s.d[2] = r.d[2];
    out[r.chan].push_back(s);
  }
  return true;
}

// donor target index -> driver channel index (-1 = unmapped).
bool build_channel_map(const tfrag3::MercModel& donor,
                       const tfrag3::MercModel& driver,
                       std::vector<int>& channel_map,
                       std::string& err) {
  std::map<u32, std::vector<ChanSample>> dsamp, ksamp;
  u32 dmax = 0, kmax = 0;
  if (!collect_blerc_samples(donor, dsamp, dmax, err)) {
    return false;
  }
  if (!collect_blerc_samples(driver, ksamp, kmax, err)) {
    return false;
  }
  const size_t nt = dmax + 1, nc = kmax + 1;
  std::vector<double> score(nt * nc, 0.0);
  for (const auto& [t, dvec] : dsamp) {
    for (const auto& [c, kvec] : ksamp) {
      double s = 0;
      for (const auto& dv : dvec) {
        // nearest driver blerc vert having a delta for c
        double best = 1e30;
        const ChanSample* bw = nullptr;
        for (const auto& kv : kvec) {
          double dx = dv.p[0] - kv.p[0], dy = dv.p[1] - kv.p[1], dz = dv.p[2] - kv.p[2];
          double d2 = dx * dx + dy * dy + dz * dz;
          if (d2 < best) {
            best = d2;
            bw = &kv;
          }
        }
        if (!bw || std::sqrt(best) > 0.35) {
          continue;
        }
        double ma = std::sqrt((double)dv.d[0] * dv.d[0] + (double)dv.d[1] * dv.d[1] +
                              (double)dv.d[2] * dv.d[2]);
        double mb = std::sqrt((double)bw->d[0] * bw->d[0] + (double)bw->d[1] * bw->d[1] +
                              (double)bw->d[2] * bw->d[2]);
        if (ma <= 0 || mb <= 0) {
          continue;
        }
        double dot = (double)dv.d[0] * bw->d[0] + (double)dv.d[1] * bw->d[1] +
                     (double)dv.d[2] * bw->d[2];
        double cos_sim = dot / (ma * mb);
        s += cos_sim * ma * mb;
      }
      score[t * nc + c] = s;
    }
  }

  channel_map.assign(nt, -1);
  std::vector<char> row_used(nt, 0), col_used(nc, 0);
  std::vector<double> best_score(nt, 0.0), second_score(nt, 0.0);
  std::vector<int> second_chan(nt, -1);
  while (true) {
    double best = 0;
    int bt = -1, bc = -1;
    for (size_t t = 0; t < nt; t++) {
      if (row_used[t]) {
        continue;
      }
      for (size_t c = 0; c < nc; c++) {
        if (col_used[c]) {
          continue;
        }
        if (score[t * nc + c] > best) {
          best = score[t * nc + c];
          bt = (int)t;
          bc = (int)c;
        }
      }
    }
    if (bt < 0 || best <= 0) {
      break;
    }
    channel_map[bt] = bc;
    best_score[bt] = best;
    // 2nd best channel for this target among channels still free at assignment time
    double s2 = 0;
    int c2 = -1;
    for (size_t c = 0; c < nc; c++) {
      if (col_used[c] || (int)c == bc) {
        continue;
      }
      if (score[bt * nc + c] > s2) {
        s2 = score[bt * nc + c];
        c2 = (int)c;
      }
    }
    second_score[bt] = s2;
    second_chan[bt] = c2;
    row_used[bt] = 1;
    col_used[bc] = 1;
  }

  int mapped = 0, identity = 0, donor_targets = 0;
  for (size_t t = 0; t < nt; t++) {
    if (dsamp.find((u32)t) == dsamp.end()) {
      continue;  // donor never uses this target index
    }
    donor_targets++;
    fmt::print("  BLERC-MAP t={} -> c={} score={:.4g} (2nd best c'={} s2={:.4g})\n", t,
               channel_map[t], best_score[t], second_chan[t], second_score[t]);
    if (channel_map[t] >= 0) {
      mapped++;
      if ((int)t == channel_map[t]) {
        identity++;
      }
    }
  }
  fmt::print("  BLERC-MAP {} of {} donor targets mapped to driver channels (driver has {} "
             "channels)\n",
             mapped, donor_targets, (int)ksamp.size());
  fmt::print("  BLERC-MAP identity-agreement: {} of {} mapped pairs have t==c\n", identity, mapped);
  return true;
}

using PosKey = std::array<s64, 5>;
PosKey vert_key(const tfrag3::MercVertex& v) {
  auto q = [](float f) { return (s64)std::llround((double)f * 8192.0); };
  return PosKey{q(v.pos[0]), q(v.pos[1]), q(v.pos[2]), q(v.st[0]), q(v.st[1])};
}

// donor texture -> target texture, by debug_name + w/h. The `add` appended the donor's merc
// textures at the tail of the target table; prefer a tail match (the actual HD texture) and only
// then fall back to a whole-table search.
bool remap_tex_id(const tfrag3::Level& tgt,
                  const tfrag3::Level& donor,
                  size_t tail_start,
                  s32 donor_id,
                  s32& out_id) {
  if (donor_id < 0) {
    out_id = donor_id;  // anim slot, meaningless to match by name
    return true;
  }
  if ((size_t)donor_id >= donor.textures.size()) {
    return false;
  }
  const auto& dt = donor.textures[donor_id];
  for (size_t pass = 0; pass < 2; pass++) {
    size_t start = (pass == 0) ? tail_start : 0;
    for (size_t i = start; i < tgt.textures.size(); i++) {
      const auto& t = tgt.textures[i];
      if (t.debug_name == dt.debug_name && t.w == dt.w && t.h == dt.h) {
        out_id = (s32)i;
        return true;
      }
    }
  }
  return false;
}

int port_blerc(tfrag3::Level& lev,
               size_t appended_idx,
               size_t stock_tex_count,
               const std::string& eye_from,
               const fs::path& donor_fr3,
               const std::string& donor_name,
               const tfrag3::Level& driver_lev,
               const std::string& driver_src,
               int bake_target) {
  tfrag3::Level dlev;
  load_fr3(donor_fr3, dlev);
  auto dit = std::find_if(dlev.merc_data.models.begin(), dlev.merc_data.models.end(),
                          [&](const auto& m) { return m.name == donor_name; });
  if (dit == dlev.merc_data.models.end()) {
    fmt::print("  BLERC-PORT FAIL: donor model '{}' not in {}\n", donor_name, donor_fr3.string());
    return 6;
  }
  tfrag3::MercModel& donor = *dit;

  // bake requested target into the donor's base geometry BEFORE anything reads the blerc data
  // (channel map, per-effect port) — the baked target is stripped here, so it can never be mapped.
  // the bone-index probe (step 1b below) is a MESH-IDENTITY check: it position-matches donor mod
  // vertices against the appended mesh, which is un-baked by construction. Snapshot the donor's
  // pre-bake mod vertices so that probe keeps comparing like with like; everything else (the ported
  // mod.vertices, blerc data, draws) uses the baked donor.
  std::vector<std::vector<tfrag3::MercVertex>> prebake_mod_vertices;
  if (bake_target >= 0) {
    prebake_mod_vertices.reserve(donor.effects.size());
    for (const auto& e : donor.effects) {
      prebake_mod_vertices.push_back(e.mod.vertices);
    }
    int brc = bake_blerc_target(donor, bake_target);
    if (brc != 0) {
      return brc;
    }
  }
  tfrag3::MercModel& appended = lev.merc_data.models.at(appended_idx);

  // ---- structure-mirror assert: appended must mirror the donor 1:1 --------------------------
  if (appended.effects.size() != donor.effects.size()) {
    fmt::print("  BLERC-PORT FAIL: effect count mismatch: appended '{}' has {}, donor '{}' has {}\n",
               appended.name, appended.effects.size(), donor.name, donor.effects.size());
    return 6;
  }
  for (size_t ei = 0; ei < donor.effects.size(); ei++) {
    const auto& de = donor.effects[ei];
    const auto& ae = appended.effects[ei];
    if (de.all_draws.size() != ae.all_draws.size()) {
      fmt::print("  BLERC-PORT FAIL: effect[{}] draw count mismatch: appended {} vs donor {}\n", ei,
                 ae.all_draws.size(), de.all_draws.size());
      return 6;
    }
    for (size_t di = 0; di < de.all_draws.size(); di++) {
      if (de.all_draws[di].num_triangles != ae.all_draws[di].num_triangles) {
        fmt::print("  BLERC-PORT FAIL: effect[{}] draw[{}] tri count mismatch: appended {} vs "
                   "donor {}\n",
                   ei, di, ae.all_draws[di].num_triangles, de.all_draws[di].num_triangles);
        return 6;
      }
    }
  }

  // ---- appended model's vertex range in the TARGET level vertex array ------------------------
  u32 vlo = UINT32_MAX, vhi = 0;
  for (const auto& e : appended.effects) {
    for (const auto& d : e.all_draws) {
      for (u32 i = 0; i < d.index_count; i++) {
        u32 v = lev.merc_data.indices.at(d.first_index + i);
        if (v == UINT32_MAX) {
          continue;  // primitive restart
        }
        vlo = std::min(vlo, v);
        vhi = std::max(vhi, v);
      }
    }
  }
  if (vlo > vhi) {
    fmt::print("  BLERC-PORT FAIL: could not determine appended model vertex range\n");
    return 6;
  }
  fmt::print("  BLERC-PORT appended vertex range: [{}, {}] ({} verts)\n", vlo, vhi, vhi - vlo + 1);

  // position+uv hash over the appended range, for the fix_draw index remap.
  std::map<PosKey, u32> pos_map;
  for (u32 v = vlo; v <= vhi; v++) {
    pos_map.emplace(vert_key(lev.merc_data.vertices.at(v)), v);
  }

  // ---- eye slots -----------------------------------------------------------------------------
  int stock_left = -1, stock_right = -1;
  int erc = find_stock_eye_slots(driver_lev, eye_from, stock_left, stock_right);
  if (erc != 0) {
    return erc;
  }

  // ---- channel map ---------------------------------------------------------------------------
  auto driver = std::find_if(driver_lev.merc_data.models.begin(), driver_lev.merc_data.models.end(),
                             [&](const auto& m) { return m.name == eye_from; });
  if (driver == driver_lev.merc_data.models.end()) {
    fmt::print("  BLERC-PORT FAIL: driver model '{}' not in {}\n", eye_from, driver_src);
    return 6;
  }
  std::vector<int> channel_map;
  std::string cerr;
  if (!build_channel_map(donor, *driver, channel_map, cerr)) {
    fmt::print("  BLERC-PORT FAIL: channel map: {}\n", cerr);
    return 6;
  }
  // explicit: a baked target is never a runtime target on the appended model.
  if (bake_target >= 0 && (size_t)bake_target < channel_map.size()) {
    channel_map[bake_target] = -1;
  }

  // ---- per-effect port -----------------------------------------------------------------------
  std::map<u32, size_t> dropped_by_target;
  size_t total_fix_idx = 0, total_fix_miss = 0;

  auto port_draw_list = [&](const std::vector<tfrag3::MercDraw>& src,
                            std::vector<tfrag3::MercDraw>& dst, bool level_indices,
                            std::string& perr) -> bool {
    for (const auto& d : src) {
      tfrag3::MercDraw nd = d;
      nd.first_index = (u32)lev.merc_data.indices.size();
      for (u32 i = 0; i < d.index_count; i++) {
        u32 v = dlev.merc_data.indices.at(d.first_index + i);
        if (level_indices && v != UINT32_MAX) {
          total_fix_idx++;
          auto key = vert_key(dlev.merc_data.vertices.at(v));
          auto found = pos_map.find(key);
          if (found != pos_map.end()) {
            v = found->second;
          } else {
            total_fix_miss++;
            // nearest-position fallback (offline, linear scan over the appended range)
            const auto& dv = dlev.merc_data.vertices.at(v);
            double best = 1e30;
            u32 bestv = vlo;
            for (u32 cand = vlo; cand <= vhi; cand++) {
              const auto& cv = lev.merc_data.vertices[cand];
              double dx = cv.pos[0] - dv.pos[0], dy = cv.pos[1] - dv.pos[1],
                     dz = cv.pos[2] - dv.pos[2];
              double d2 = dx * dx + dy * dy + dz * dz;
              if (d2 < best) {
                best = d2;
                bestv = cand;
              }
            }
            v = bestv;
          }
        }
        lev.merc_data.indices.push_back(v);
      }
      s32 tex = 0;
      if (!remap_tex_id(lev, dlev, stock_tex_count, d.tree_tex_id, tex)) {
        perr = fmt::format("no target texture matching donor tex id {} ({})", d.tree_tex_id,
                           tex_label(dlev, d.tree_tex_id));
        return false;
      }
      nd.tree_tex_id = tex;
      if (nd.eye_id != 0xff) {
        int want = (nd.eye_id & 1) ? stock_right : stock_left;
        if (want < 0) {
          perr = fmt::format("ported draw is a {} eye but driver '{}' has none",
                             (nd.eye_id & 1) ? "RIGHT" : "LEFT", eye_from);
          return false;
        }
        nd.eye_id = (u8)want;
      }
      dst.push_back(nd);
    }
    return true;
  };

  int ported_effects = 0;
  for (size_t ei = 0; ei < donor.effects.size(); ei++) {
    const auto& de = donor.effects[ei];
    if (de.mod.mod_draw.empty() || de.mod.blerc.int_data.empty()) {
      continue;
    }
    auto& ae = appended.effects[ei];

    // 1. mod vertices, verbatim.
    if (de.mod.vertices.size() >= (size_t)MAX_MOD_VTX_LIMIT) {
      fmt::print("  BLERC-PORT FAIL: effect[{}] has {} mod vertices, >= MAX_MOD_VTX {}\n", ei,
                 de.mod.vertices.size(), MAX_MOD_VTX_LIMIT);
      return 6;
    }
    ae.mod.vertices = de.mod.vertices;

    // 1b. bone-index convention check: probe the first 8 donor mod verts against the appended
    // model's own vertices (same position) and compare mats. The mod VBO is drawn with the
    // appended model's bone matrices, so the joint indices must agree.
    {
      int probes = 0, matched = 0;
      const auto& probe_verts =
          prebake_mod_vertices.empty() ? de.mod.vertices : prebake_mod_vertices[ei];
      size_t n_probe = std::min<size_t>(8, probe_verts.size());
      for (size_t k = 0; k < n_probe; k++) {
        const auto& mv = probe_verts[k];
        probes++;
        const tfrag3::MercVertex* hit = nullptr;
        for (u32 cand = vlo; cand <= vhi; cand++) {
          const auto& cv = lev.merc_data.vertices[cand];
          if (std::fabs(cv.pos[0] - mv.pos[0]) < 1e-4f && std::fabs(cv.pos[1] - mv.pos[1]) < 1e-4f &&
              std::fabs(cv.pos[2] - mv.pos[2]) < 1e-4f) {
            hit = &cv;
            break;
          }
        }
        if (!hit) {
          continue;
        }
        matched++;
        // compare only WEIGHTED lanes: zero-weight lanes are padding and carry arbitrary bone
        // indices (donor pads 0, the GLB round-trip pads differently). Every donor lane with
        // weight must find the same (bone, weight) pair on the appended vertex, any lane order.
        bool lanes_ok = true;
        for (int dl = 0; dl < 3 && lanes_ok; dl++) {
          if (mv.weights[dl] <= 1e-6f) {
            continue;
          }
          bool found = false;
          for (int al = 0; al < 3; al++) {
            if (hit->mats[al] == mv.mats[dl] &&
                std::fabs(hit->weights[al] - mv.weights[dl]) < 1e-3f) {
              found = true;
              break;
            }
          }
          lanes_ok = found;
        }
        if (!lanes_ok) {
          fmt::print("  BLERC-PORT FAIL: effect[{}] mod vertex {} bone-index mismatch: donor mats "
                     "[{},{},{}] w=[{},{},{}] vs appended mats [{},{},{}] w=[{},{},{}] at pos "
                     "({}, {}, {})\n",
                     ei, k, mv.mats[0], mv.mats[1], mv.mats[2], mv.weights[0], mv.weights[1],
                     mv.weights[2], hit->mats[0], hit->mats[1], hit->mats[2], hit->weights[0],
                     hit->weights[1], hit->weights[2], mv.pos[0], mv.pos[1], mv.pos[2]);
          return 6;
        }
      }
      if (probes - matched > 2) {
        fmt::print("  BLERC-PORT FAIL: effect[{}] only {} of {} mod-vertex probes found a "
                   "position match in the appended mesh — donor/appended mesh mismatch\n",
                   ei, matched, probes);
        return 6;
      }
    }

    // 2. mod draws (MOD-LOCAL index values, verbatim) and fix draws (LEVEL index values, remapped)
    ae.mod.mod_draw.clear();
    ae.mod.fix_draw.clear();
    std::string perr;
    if (!port_draw_list(de.mod.mod_draw, ae.mod.mod_draw, false, perr)) {
      fmt::print("  BLERC-PORT FAIL: effect[{}] mod_draw: {}\n", ei, perr);
      return 6;
    }
    if (!port_draw_list(de.mod.fix_draw, ae.mod.fix_draw, true, perr)) {
      fmt::print("  BLERC-PORT FAIL: effect[{}] fix_draw: {}\n", ei, perr);
      return 6;
    }

    // 3. blerc data, targets remapped to driver channels (unmapped targets dropped in lockstep)
    std::vector<BlercVert> bverts;
    if (!parse_blerc(de.mod.blerc, bverts)) {
      fmt::print("  BLERC-PORT FAIL: effect[{}] donor blerc data is malformed\n", ei);
      return 6;
    }
    tfrag3::Blerc nb;
    for (const auto& v : bverts) {
      nb.float_data.push_back(de.mod.blerc.float_data[v.float_base]);
      for (size_t k = 0; k < v.tgts.size(); k++) {
        u32 t = v.tgts[k];
        if (bake_target >= 0 && (int)t == bake_target) {
          continue;  // baked into the base geometry above; never a runtime target
        }
        int c = (t < channel_map.size()) ? channel_map[t] : -1;
        if (c < 0) {
          dropped_by_target[t]++;
          continue;
        }
        nb.int_data.push_back((u32)c);
        nb.float_data.push_back(de.mod.blerc.float_data[v.float_base + 1 + k]);
      }
      nb.int_data.push_back(tfrag3::Blerc::kTargetIdxTerminator);
      nb.int_data.push_back(v.dest);
    }
    ae.mod.blerc = nb;
    ae.mod.vertex_lump4_addr = de.mod.vertex_lump4_addr;
    ae.mod.fragment_mask = de.mod.fragment_mask;
    ae.mod.expect_vidx_end = de.mod.expect_vidx_end;
    ae.has_mod_draw = true;

    size_t dropped_here = 0;
    for (const auto& v : bverts) {
      for (u32 t : v.tgts) {
        if (bake_target >= 0 && (int)t == bake_target) {
          continue;
        }
        int c = (t < channel_map.size()) ? channel_map[t] : -1;
        if (c < 0) {
          dropped_here++;
        }
      }
    }
    fmt::print("  BLERC-PORT effect[{}]: mod_verts={} mod_draws={} fix_draws={} blerc_verts={} "
               "targets_dropped={}\n",
               ei, ae.mod.vertices.size(), ae.mod.mod_draw.size(), ae.mod.fix_draw.size(),
               bverts.size(), dropped_here);
    ported_effects++;
  }

  if (total_fix_idx > 0) {
    double miss_pct = 100.0 * (double)total_fix_miss / (double)total_fix_idx;
    fmt::print("  BLERC-PORT fix_draw index remap: {} indices, {} exact-key misses ({:.3f}%)\n",
               total_fix_idx, total_fix_miss, miss_pct);
    if (miss_pct > 0.5) {
      fmt::print("  BLERC-PORT FAIL: {} of {} fix_draw indices ({:.3f}%) had no position/uv match "
                 "in the appended mesh (>0.5%)\n",
                 total_fix_miss, total_fix_idx, miss_pct);
      return 6;
    }
  }
  if (!dropped_by_target.empty()) {
    std::string s;
    for (const auto& [t, n] : dropped_by_target) {
      s += fmt::format(" t{}={}", t, n);
    }
    fmt::print("  BLERC-PORT dropped (unmapped) target instances:{}\n", s);
  }
  if (ported_effects == 0) {
    fmt::print("  BLERC-PORT FAIL: donor model '{}' has no effect with mod draws + blerc data\n",
               donor.name);
    return 6;
  }
  fmt::print("  BLERC-PORT OK ({} effects ported from '{}')\n", ported_effects, donor.name);
  return 0;
}

// Copy a donor texture into the target level's texture array, deduping through `cache`
// (donor texture idx -> target level texture idx). Shared by ENVMAP-PORT and ANIMSLOT-PORT.
u32 port_texture(tfrag3::Level& lev,
                 const tfrag3::Level& dlev,
                 u32 donor_tex_idx,
                 std::map<u32, u32>& cache) {
  auto cached = cache.find(donor_tex_idx);
  if (cached != cache.end()) {
    return cached->second;
  }
  u32 nt = (u32)lev.textures.size();
  lev.textures.push_back(dlev.textures[donor_tex_idx]);
  // cycle-4 latent-bug fix: ported donor textures are referenced by fr3 index (merc draws) or by
  // the hd-lid debug_name side channel, NEVER via the TexturePool. The donor's combo_id names a
  // page in the DONOR game's tpage dir; jak1's dir has only 1611 entries, so donor combo pages are
  // either out of bounds (UB read) or alias a legitimate jak1 texture slot. LoaderStages.cpp
  // registers any load_to_pool texture into the pool by combo page/idx — so shipping the donor's
  // load_to_pool=1 verbatim was silently corrupting jak1 pool slots.
  lev.textures.back().load_to_pool = false;
  cache.emplace(donor_tex_idx, nt);
  return nt;
}

// jak1's texture page directory size — a combo page >= this is out of bounds for jak1's pool.
constexpr u32 kJak1TexturePageCount = 1611;

// LID-PORT (cycle 4): the HD eyelid fix needs the donor's eyelid texture available to the renderer
// even though NO merc draw references it (the lid is drawn by EyeRenderer, not by a merc draw).
// Merc2 resolves it from the model's level texture list by debug_name "<model-base>-lid", so we
// copy the named donor texture into the target level and rename the COPY. The copy is always
// fresh (own cache) so a texture already ported for envmap/animslot purposes keeps its own name.
int port_lid(tfrag3::Level& lev,
             const fs::path& donor_fr3,
             const std::string& donor_tex_name,
             const std::string& model_name) {
  tfrag3::Level dlev;
  load_fr3(donor_fr3, dlev);
  std::vector<u32> matches;
  for (size_t i = 0; i < dlev.textures.size(); i++) {
    if (dlev.textures[i].debug_name == donor_tex_name) {
      matches.push_back((u32)i);
    }
  }
  if (matches.size() != 1) {
    fmt::print("  LID-PORT FAIL: donor texture '{}' matched {} times in {} (need exactly 1)\n",
               donor_tex_name, matches.size(), donor_fr3.string());
    fmt::print("  candidates containing 'lid'/'eye':\n");
    for (size_t i = 0; i < dlev.textures.size(); i++) {
      const auto& n = dlev.textures[i].debug_name;
      if (n.find("lid") != std::string::npos || n.find("eye") != std::string::npos) {
        fmt::print("    [{}] '{}' {}x{}\n", i, n, dlev.textures[i].w, dlev.textures[i].h);
      }
    }
    return 8;
  }
  // base name: strip the trailing "-lod0" from the appended model name.
  std::string base = model_name;
  const std::string kLod0 = "-lod0";
  if (base.size() > kLod0.size() && base.compare(base.size() - kLod0.size(), kLod0.size(), kLod0) == 0) {
    base = base.substr(0, base.size() - kLod0.size());
  }
  const std::string lid_name = base + "-lid";
  // fresh local cache => always appends a NEW copy, never renames a draw-referenced shared copy.
  std::map<u32, u32> lid_cache;
  u32 nt = port_texture(lev, dlev, matches[0], lid_cache);
  auto& t = lev.textures[nt];
  t.debug_name = lid_name;
  fmt::print("LID-PORT: '{}' {}x{} combo=0x{:x} -> idx={} name='{}' load_to_pool=0\n",
             donor_tex_name, t.w, t.h, t.combo_id, nt, t.debug_name);
  return 0;
}

// LID-GATE (cycle 4): no texture in the shipped level may register into jak1's TexturePool with a
// combo page outside jak1's tpage dir. Stock jak1 textures (page < 1611) are legitimate.
int assert_pool_safe(const tfrag3::Level& lev, size_t before_textures) {
  for (const auto& t : lev.textures) {
    if (t.load_to_pool && (t.combo_id >> 16) >= kJak1TexturePageCount) {
      fmt::print("LID-GATE FAIL: texture '{}' combo=0x{:x} load_to_pool=1 donor page OOB\n",
                 t.debug_name, t.combo_id);
      return 9;
    }
  }
  size_t n = 0;
  for (size_t i = before_textures; i < lev.textures.size(); i++) {
    if (!lev.textures[i].load_to_pool) {
      n++;
    }
  }
  fmt::print("LID-GATE: donor-ported textures pool-safe count={} PASS\n", n);
  return 0;
}

// ENVMAP-PORT (cycle 3, defect classes C/E): the GLB round-trip loses has_envmap (rip GLB
// materials carry no valid envmap extension), so appended models rendered envmap-effect
// textures as plain alpha-tested color — but PS2 TCC envmap-effect texture alpha is a SHEEN
// MASK, not opacity (daxter head: 51% of texels alpha<8 => merc2.frag discarded half the head).
// Copy the donor's per-effect envmap config onto the appended model (effect order proven 1:1
// by port_blerc's structure-mirror assert, which runs first) and bring the donor's envmap
// texture(s) into the target level's texture array.
int port_envmap(tfrag3::Level& lev,
                size_t appended_idx,
                const fs::path& donor_fr3,
                const std::string& donor_name) {
  tfrag3::Level dlev;
  load_fr3(donor_fr3, dlev);
  auto dit = std::find_if(dlev.merc_data.models.begin(), dlev.merc_data.models.end(),
                          [&](const auto& m) { return m.name == donor_name; });
  if (dit == dlev.merc_data.models.end()) {
    fmt::print("  ENVMAP-PORT FAIL: donor model '{}' not in {}\n", donor_name,
               donor_fr3.string());
    return 7;
  }
  const tfrag3::MercModel& donor = *dit;
  tfrag3::MercModel& appended = lev.merc_data.models.at(appended_idx);
  if (appended.effects.size() != donor.effects.size()) {
    fmt::print("  ENVMAP-PORT FAIL: effect count mismatch: appended '{}' has {}, donor '{}' "
               "has {}\n",
               appended.name, appended.effects.size(), donor.name, donor.effects.size());
    return 7;
  }
  std::map<u32, u32> tex_cache;  // donor texture idx -> target level texture idx
  int ported = 0;
  for (size_t ei = 0; ei < donor.effects.size(); ei++) {
    const auto& de = donor.effects[ei];
    if (!de.has_envmap) {
      continue;
    }
    auto& ae = appended.effects[ei];
    u32 dt = de.envmap_texture;
    if (dt >= dlev.textures.size()) {
      fmt::print("  ENVMAP-PORT FAIL: effect[{}] envmap texture idx {} out of range ({} donor "
                 "textures)\n",
                 ei, dt, dlev.textures.size());
      return 7;
    }
    u32 nt = port_texture(lev, dlev, dt, tex_cache);
    ae.has_envmap = true;
    ae.envmap_mode = de.envmap_mode;
    ae.envmap_texture = nt;
    fmt::print("  ENVMAP-PORT effect[{}] mode={:#x} tex '{}' (donor idx {}) -> level tex idx "
               "{}\n",
               ei, de.envmap_mode.as_int(), dlev.textures[dt].debug_name, dt, nt);
    ported++;
  }
  fmt::print("  ENVMAP-PORT {} effect(s) ported from '{}' ({} texture(s) copied)\n", ported,
             donor_name, tex_cache.size());
  return 0;
}

// ANIMSLOT-PORT (cycle 3): the jak2/jak3 Jak donors ship merc draws whose texture id is
// NEGATIVE — that is not a texture index at all but a TextureAnimator OUTPUT SLOT reference
// (slot = -id - 1, see decompiler/level_extractor/extract_merc.cpp). Those slots are
// clut-blender outputs (norm/dark skin blends) that only exist in the donor game's animator;
// jak1 has no such slots, so copying the negative id verbatim into a jak1 fr3 gives the
// runtime an out-of-universe slot reference (crash path) and leaves the appended model's
// all_draws on the bigpuff fallback texture. The correct STATIC substitute is the slot's base
// texture, which IS present in the donor fr3's texture array under the slot's NAME. This step
// resolves each negative id to that name (via the jak2/jak3 slot tables — exactly one table's
// entry may exist in a given donor fr3, which also auto-detects the donor game), ports the
// texture into the target level, and rewrites every negative id on the appended model.
int port_animslots(tfrag3::Level& lev,
                   size_t appended_idx,
                   const fs::path& donor_fr3,
                   const std::string& donor_name) {
  tfrag3::Level dlev;
  load_fr3(donor_fr3, dlev);
  auto dit = std::find_if(dlev.merc_data.models.begin(), dlev.merc_data.models.end(),
                          [&](const auto& m) { return m.name == donor_name; });
  if (dit == dlev.merc_data.models.end()) {
    fmt::print("  ANIMSLOT-PORT FAIL: donor model '{}' not in {}\n", donor_name,
               donor_fr3.string());
    return 2;
  }
  const tfrag3::MercModel& donor = *dit;
  tfrag3::MercModel& appended = lev.merc_data.models.at(appended_idx);
  if (appended.effects.size() != donor.effects.size()) {
    fmt::print("  ANIMSLOT-PORT FAIL: effect count mismatch: appended '{}' has {}, donor '{}' "
               "has {}\n",
               appended.name, appended.effects.size(), donor.name, donor.effects.size());
    return 2;
  }

  const auto& jak2_slots = jak2_animated_texture_slots();
  const auto& jak3_slots = jak3_animated_texture_slots();

  auto find_donor_tex = [&](const std::string& tex_name) -> int {
    for (size_t i = 0; i < dlev.textures.size(); i++) {
      if (dlev.textures[i].debug_name == tex_name) {
        return (int)i;
      }
    }
    return -1;
  };

  struct SlotInfo {
    std::string name;
    u32 tex_idx = 0;
    int draws = 0;
  };
  std::map<int, SlotInfo> slots;    // anim slot -> resolved binding
  std::map<u32, u32> tex_cache;     // donor texture idx -> target level texture idx
  bool failed = false;

  // negative id -> ported target texture index (resolves + ports on first use)
  auto resolve = [&](s32 neg_id) -> int {
    int slot = -neg_id - 1;
    auto it = slots.find(slot);
    if (it != slots.end()) {
      return (int)it->second.tex_idx;
    }
    std::string c2 = (slot >= 0 && (size_t)slot < jak2_slots.size()) ? jak2_slots[slot] : "";
    std::string c3 = (slot >= 0 && (size_t)slot < jak3_slots.size()) ? jak3_slots[slot] : "";
    int i2 = c2.empty() ? -1 : find_donor_tex(c2);
    int i3 = c3.empty() ? -1 : find_donor_tex(c3);
    if ((i2 < 0 && i3 < 0) || (i2 >= 0 && i3 >= 0)) {
      fmt::print("  ANIMSLOT-PORT FAIL: slot {} (tex id {}) — jak2 candidate '{}' {} in donor "
                 "'{}', jak3 candidate '{}' {} in donor; need EXACTLY one\n",
                 slot, neg_id, c2.empty() ? "<out-of-range>" : c2,
                 i2 >= 0 ? "PRESENT" : "absent", donor_fr3.string(),
                 c3.empty() ? "<out-of-range>" : c3, i3 >= 0 ? "PRESENT" : "absent");
      failed = true;
      return -1;
    }
    int donor_idx = (i2 >= 0) ? i2 : i3;
    SlotInfo info;
    info.name = (i2 >= 0) ? c2 : c3;
    info.tex_idx = port_texture(lev, dlev, (u32)donor_idx, tex_cache);
    slots.emplace(slot, info);
    return (int)info.tex_idx;
  };

  int rebound = 0;
  // (a) the appended model's own mod/fix draws carry the donor's negative ids verbatim
  //     (port_blerc copies them through).
  for (auto& ae : appended.effects) {
    for (auto* list : {&ae.mod.fix_draw, &ae.mod.mod_draw}) {
      for (auto& d : *list) {
        if (d.tree_tex_id >= 0) {
          continue;
        }
        int nt = resolve(d.tree_tex_id);
        if (nt < 0) {
          return 2;
        }
        slots[-d.tree_tex_id - 1].draws++;
        d.tree_tex_id = nt;
        rebound++;
      }
    }
  }
  // (b) all_draws of the appended model came from the GLB (bigpuff fallback for these prims);
  //     the DONOR's draw list tells us positionally which ones are anim-slot draws.
  for (size_t ei = 0; ei < donor.effects.size(); ei++) {
    const auto& de = donor.effects[ei];
    auto& ae = appended.effects[ei];
    if (de.all_draws.size() != ae.all_draws.size()) {
      fmt::print("  ANIMSLOT-PORT FAIL: effect[{}] draw count mismatch: appended {} vs donor {}\n",
                 ei, ae.all_draws.size(), de.all_draws.size());
      return 2;
    }
    for (size_t di = 0; di < de.all_draws.size(); di++) {
      s32 did = de.all_draws[di].tree_tex_id;
      if (did >= 0) {
        continue;
      }
      int nt = resolve(did);
      if (nt < 0) {
        return 2;
      }
      slots[-did - 1].draws++;
      ae.all_draws[di].tree_tex_id = nt;
      rebound++;
    }
  }
  if (failed) {
    return 2;
  }

  if (slots.empty()) {
    fmt::print("  ANIMSLOT-PORT: none\n");
    return 0;
  }
  for (const auto& [slot, info] : slots) {
    fmt::print("  ANIMSLOT-PORT: slot {} '{}' -> tex[{}] ({} draws)\n", slot, info.name,
               info.tex_idx, info.draws);
  }
  fmt::print("  ANIMSLOT-PORT OK: {} draws rebound, {} textures ported\n", rebound,
             tex_cache.size());
  return 0;
}

// INVARIANT: a jak1 fr3 must NEVER ship a negative merc texture id (an out-of-universe
// TextureAnimator slot reference). Scan every draw list of the appended model.
int assert_no_negative_tex(const tfrag3::MercModel& m) {
  int bad = 0;
  for (size_t ei = 0; ei < m.effects.size(); ei++) {
    const auto& e = m.effects[ei];
    auto scan = [&](const char* which, const std::vector<tfrag3::MercDraw>& list) {
      for (size_t di = 0; di < list.size(); di++) {
        if (list[di].tree_tex_id < 0) {
          fmt::print("  NEG-TEX-INVARIANT FAIL: model '{}' effect[{}] {}[{}] tex id {} (anim "
                     "slot {}) — jak1 has no TextureAnimator slot universe for it\n",
                     m.name, ei, which, di, list[di].tree_tex_id, -list[di].tree_tex_id - 1);
          bad++;
        }
      }
    };
    scan("all_draws", e.all_draws);
    scan("fix_draw", e.mod.fix_draw);
    scan("mod_draw", e.mod.mod_draw);
  }
  if (bad) {
    fmt::print("  NEG-TEX-INVARIANT FAIL: {} draw(s) still carry a negative texture id\n", bad);
    return 2;
  }
  fmt::print("  NEG-TEX-INVARIANT OK: no negative texture ids in '{}'\n", m.name);
  return 0;
}

int do_add(const fs::path& in,
           const fs::path& glb,
           const fs::path& out,
           const std::string& eye_from,
           const fs::path& blerc_fr3 = {},
           const std::string& blerc_model = {},
           const fs::path& driver_fr3 = {},
           const std::string& lid_tex = {},
           int bake_target = -1) {
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

  // the DRIVER (eye_from) model is normally in the target fr3, but for models appended to a level
  // they don't natively belong to (keira/samos into GAME.fr3) the driver only exists in another
  // level fr3 — load it separately in that case.
  tfrag3::Level driver_storage;
  const tfrag3::Level* driver_lev = &lev;
  std::string driver_src = in.string();
  if (!driver_fr3.empty()) {
    if (!file_util::file_exists(driver_fr3.string())) {
      fmt::print("  driver fr3 missing: {}\n", driver_fr3.string());
      return 2;
    }
    load_fr3(driver_fr3, driver_storage);
    driver_lev = &driver_storage;
    driver_src = driver_fr3.string();
    fmt::print("  driver model '{}' resolved from {}\n", eye_from, driver_src);
  }

  // eye slot handling: donor slots MUST be remapped to the driver's before shipping. Appending
  // a model that carries eye draws without --eye-from would sample an arbitrary jak1 slot
  // (donor_slot % 40) — refuse instead of shipping broken eyes silently.
  auto& appended = lev.merc_data.models.at(idx);
  bool has_eye_draws = false;
  for (const auto& e : appended.effects) {
    for (const auto& d : e.all_draws) {
      has_eye_draws |= (d.eye_id != 0xff);
    }
  }
  if (!eye_from.empty()) {
    int rc = remap_eye_ids(lev, appended, eye_from, *driver_lev);
    if (rc != 0) {
      return rc;
    }
  } else if (has_eye_draws) {
    fmt::print("  FAIL: appended model has eye draws but no --eye-from <stock-model> given — "
               "donor eye slots are meaningless in jak1\n");
    return 5;
  }

  if (bake_target >= 0 && blerc_model.empty()) {
    fmt::print("  FAIL: --bake-blerc-target needs --blerc-from <donor.fr3>:<donor-model-name> (the "
               "donor model whose blerc target is baked)\n");
    return 6;
  }

  // defect class B: port the donor's blerc (facial blend shapes) onto the appended model.
  if (!blerc_model.empty()) {
    if (eye_from.empty()) {
      fmt::print("  FAIL: --blerc-from needs --eye-from <stock-model> (the DRIVER model whose "
                 "blerc channels the donor targets are remapped to)\n");
      return 6;
    }
    int rc = port_blerc(lev, idx, before_textures, eye_from, blerc_fr3, blerc_model, *driver_lev,
                        driver_src, bake_target);
    if (rc != 0) {
      fmt::print("  (no fr3 written)\n");
      return rc;
    }
    rc = port_envmap(lev, idx, blerc_fr3, blerc_model);
    if (rc != 0) {
      fmt::print("  (no fr3 written)\n");
      return rc;
    }
    rc = port_animslots(lev, idx, blerc_fr3, blerc_model);
    if (rc != 0) {
      fmt::print("  (no fr3 written)\n");
      return rc;
    }
  }

  // cycle 4 (blink): bring the donor's eyelid texture across under the "<base>-lid" debug_name the
  // renderer looks up (Merc2 -> EyeRenderer). No merc draw references it.
  if (!lid_tex.empty()) {
    if (blerc_fr3.empty()) {
      fmt::print("  FAIL: --port-lid needs --blerc-from <donor.fr3>:<model> (the donor level the "
                 "lid texture is taken from)\n");
      return 8;
    }
    int rc = port_lid(lev, blerc_fr3, lid_tex, name);
    if (rc != 0) {
      fmt::print("  (no fr3 written)\n");
      return rc;
    }
  }

  // hard invariant: no negative (TextureAnimator slot) texture id may reach a jak1 fr3.
  {
    int rc = assert_no_negative_tex(lev.merc_data.models.at(idx));
    if (rc != 0) {
      fmt::print("  (no fr3 written)\n");
      return rc;
    }
  }

  // hard invariant: nothing appended may register into jak1's TexturePool with a donor page.
  {
    int rc = assert_pool_safe(lev, before_textures);
    if (rc != 0) {
      fmt::print("  (no fr3 written)\n");
      return rc;
    }
  }

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
               "  hd_merc_swap add   <stock.fr3> <name>-lod0.glb <out.fr3> [--eye-from "
               "<stock-model>] [--blerc-from <donor.fr3>:<donor-model-name>] "
               "[--driver-fr3 <fr3-with-driver-model>] [--port-lid <donor-texture-debug-name>] "
               "[--bake-blerc-target <N>]\n"
               "  hd_merc_swap stamp <donor.fr3> <donor-model-name> <in.glb> <out.glb>\n"
               "  hd_merc_swap blerc-stats <fr3> <model-name>\n");
    return 2;
  }
  std::string mode = argv[1];
  if (mode == "audit") {
    if (argc < 3) { fmt::print("audit needs <fr3>\n"); return 2; }
    std::vector<std::string> names;
    for (int i = 3; i < argc; i++) names.push_back(argv[i]);
    return do_audit(argv[2], names);
  }
  if (mode == "blerc-stats") {
    if (argc < 4) { fmt::print("blerc-stats needs <fr3> <model-name>\n"); return 2; }
    return do_blerc_stats(argv[2], argv[3]);
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
  if (mode == "stamp") {
    if (argc < 6) {
      fmt::print("stamp needs <donor.fr3> <donor-model-name> <in.glb> <out.glb>\n");
      return 2;
    }
    return do_stamp(argv[2], argv[3], argv[4], argv[5]);
  }
  if (mode == "add") {
    if (argc < 5) {
      fmt::print("add needs <stock.fr3> <name>-lod0.glb <out.fr3> [--eye-from <stock-model>]\n");
      return 2;
    }
    std::string eye_from, blerc_spec, driver_fr3, lid_tex;
    int bake_target = -1;
    for (int i = 5; i + 1 < argc; i++) {
      if (std::string(argv[i]) == "--eye-from") {
        eye_from = argv[i + 1];
      } else if (std::string(argv[i]) == "--blerc-from") {
        blerc_spec = argv[i + 1];
      } else if (std::string(argv[i]) == "--driver-fr3") {
        driver_fr3 = argv[i + 1];
      } else if (std::string(argv[i]) == "--port-lid") {
        lid_tex = argv[i + 1];
      } else if (std::string(argv[i]) == "--bake-blerc-target") {
        bake_target = std::atoi(argv[i + 1]);
        if (bake_target < 0) {
          fmt::print("--bake-blerc-target needs a non-negative target index\n");
          return 2;
        }
      }
    }
    std::string blerc_fr3, blerc_model;
    if (!blerc_spec.empty()) {
      auto colon = blerc_spec.rfind(':');
      if (colon == std::string::npos) {
        fmt::print("--blerc-from needs <donor.fr3>:<donor-model-name>\n");
        return 2;
      }
      blerc_fr3 = blerc_spec.substr(0, colon);
      blerc_model = blerc_spec.substr(colon + 1);
      if (blerc_fr3.empty() || blerc_model.empty()) {
        fmt::print("--blerc-from needs <donor.fr3>:<donor-model-name>\n");
        return 2;
      }
    }
    return do_add(argv[2], argv[3], argv[4], eye_from, blerc_fr3, blerc_model, driver_fr3, lid_tex,
                  bake_target);
  }
  fmt::print("unknown mode '{}'\n", mode);
  return 2;
}
