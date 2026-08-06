#include "ManagedAssets.h"

#include <map>
#include <memory>
#include <mutex>

#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/gfx.h"
#include "game/graphics/pipelines/opengl.h"
#include "game/runtime.h"

#include "third-party/json.hpp"

namespace managed_assets {

namespace {

// GL internal formats for the KTX2 subset (values are core GL/GLES enums;
// the desktop glad header defines them all, and on GLES they are the same
// numeric values from the ES 3.x core + KHR_astc specs).
#ifndef GL_COMPRESSED_RGBA_ASTC_4x4_KHR
#define GL_COMPRESSED_RGBA_ASTC_4x4_KHR 0x93B0
#endif
#ifndef GL_COMPRESSED_RGBA_ASTC_6x6_KHR
#define GL_COMPRESSED_RGBA_ASTC_6x6_KHR 0x93B4
#endif

u32 gl_internal_format(u32 vk_format) {
  switch (static_cast<ktx2::VkFormat>(vk_format)) {
    case ktx2::VkFormat::BC1_RGB_UNORM:
      return 0x83F0;  // GL_COMPRESSED_RGB_S3TC_DXT1_EXT
    case ktx2::VkFormat::BC4_UNORM:
      return 0x8DBB;  // GL_COMPRESSED_RED_RGTC1
    case ktx2::VkFormat::BC5_UNORM:
      return 0x8DBD;  // GL_COMPRESSED_RG_RGTC2
    case ktx2::VkFormat::BC7_UNORM:
      return GL_COMPRESSED_RGBA_BPTC_UNORM;
    case ktx2::VkFormat::ETC2_R8G8B8_UNORM:
      return 0x9274;  // GL_COMPRESSED_RGB8_ETC2
    case ktx2::VkFormat::EAC_R11_UNORM:
      return 0x9270;  // GL_COMPRESSED_R11_EAC
    case ktx2::VkFormat::EAC_R11G11_UNORM:
      return 0x9272;  // GL_COMPRESSED_RG11_EAC
    case ktx2::VkFormat::ASTC_4x4_UNORM:
      return GL_COMPRESSED_RGBA_ASTC_4x4_KHR;
    case ktx2::VkFormat::ASTC_6x6_UNORM:
      return GL_COMPRESSED_RGBA_ASTC_6x6_KHR;
    case ktx2::VkFormat::R8G8B8A8_UNORM:
      return GL_RGBA8;
    default:
      return 0;
  }
}

struct EntryRef {
  size_t shard_idx;
  const rpack::Entry* entry;
};

struct State {
  std::mutex mutex;  // scans can race GL thread vs loader thread — lock it
  bool scanned = false;
  bool last_active = false;
  std::vector<std::unique_ptr<rpack::Reader>> shards;
  // (key, map) -> entry
  std::map<std::pair<std::string, std::string>, EntryRef> index;
} g_state;

fs::path state_dir() {
  return file_util::get_jak_project_dir() / "managed_assets" /
         game_version_names[g_game_version];
}

bool gate_on() {
  // Managed packs are "recharged" content: master-gated. A dedicated user
  // toggle rides in with the asset-manager menu work (PR3); until then the
  // presence of an installed, verified state.json is the opt-in.
  return Gfx::recharged_master_active();
}

void scan_locked() {
  g_state.shards.clear();
  g_state.index.clear();
  const auto state_file = state_dir() / "state.json";
  if (!fs::exists(state_file)) {
    return;
  }
  nlohmann::json st;
  try {
    st = nlohmann::json::parse(file_util::read_text_file(state_file));
  } catch (const std::exception& e) {
    lg::warn("managed_assets: bad state.json: {}", e.what());
    return;
  }
  if (st.value("schema_version", 0) != 1 || !st.value("verified", false)) {
    lg::warn("managed_assets: state.json not verified/supported — ignoring");
    return;
  }
  int entries = 0;
  for (const auto& sh : st.value("shards", nlohmann::json::array())) {
    const auto path = state_dir() / sh.get<std::string>();
    auto reader = std::make_unique<rpack::Reader>(path.string());
    if (!reader->ok()) {
      lg::warn("managed_assets: skipping shard {}: {}", path.string(), reader->error());
      continue;
    }
    const size_t idx = g_state.shards.size();
    for (const auto& e : reader->entries()) {
      g_state.index[{e.key, e.map}] = {idx, &e};
      entries++;
    }
    g_state.shards.push_back(std::move(reader));
  }
  lg::info("managed_assets: {} shards, {} entries from {}", g_state.shards.size(), entries,
           state_file.string());
}

const EntryRef* find_locked(const std::string& key, const std::string& map) {
  const auto it = g_state.index.find({key, map});
  return it == g_state.index.end() ? nullptr : &it->second;
}

}  // namespace

void ensure_loaded() {
  const bool on = gate_on();
  std::lock_guard<std::mutex> lock(g_state.mutex);
  if (g_state.scanned && g_state.last_active == on) {
    return;
  }
  g_state.scanned = true;
  g_state.last_active = on;
  if (on) {
    scan_locked();
  } else {
    g_state.shards.clear();
    g_state.index.clear();
  }
}

void invalidate() {
  std::lock_guard<std::mutex> lock(g_state.mutex);
  g_state.scanned = false;
  g_state.shards.clear();
  g_state.index.clear();
}

bool active() {
  if (!gate_on()) {
    return false;
  }
  ensure_loaded();
  std::lock_guard<std::mutex> lock(g_state.mutex);
  return !g_state.index.empty();
}

bool has_base(const std::string& tpage_name, const std::string& tex_name) {
  if (!gate_on()) {
    return false;
  }
  ensure_loaded();
  std::lock_guard<std::mutex> lock(g_state.mutex);
  return find_locked(tpage_name + "/" + tex_name, "albedo") != nullptr;
}

std::optional<CompressedTex> lookup_base(const std::string& tpage_name,
                                         const std::string& tex_name) {
  if (!gate_on()) {
    return std::nullopt;
  }
  ensure_loaded();
  std::lock_guard<std::mutex> lock(g_state.mutex);
  const auto* ref = find_locked(tpage_name + "/" + tex_name, "albedo");
  if (!ref) {
    return std::nullopt;
  }
  // No per-load hash verify: the installer verified the shard, and the
  // rpack index integrity check ran at open. Corruption after install is
  // caught by the ktx2 subset parse below.
  auto payload = g_state.shards[ref->shard_idx]->read_payload(*ref->entry, /*verify=*/false);
  if (!payload) {
    lg::warn("managed_assets: payload read failed for {}", ref->entry->key);
    return std::nullopt;
  }
  CompressedTex out;
  out.payload = std::move(*payload);
  out.wrap_mode = ref->entry->wrap_mode;
  std::string err;
  if (!ktx2::parse(out.payload.data(), out.payload.size(), &out.info, &err)) {
    lg::warn("managed_assets: bad ktx2 for {}: {}", ref->entry->key, err);
    return std::nullopt;
  }
  return out;
}

bool upload_bound_texture(const CompressedTex& tex) {
  const u32 internal = gl_internal_format(tex.info.vk_format);
  if (!internal) {
    lg::warn("managed_assets: no GL format for vkFormat {}", tex.info.vk_format);
    return false;
  }
  // GL_MAX_TEXTURE_SIZE guard (the audited defect): offline mips make the
  // fix free — skip leading levels until the size fits.
  GLint max_size = 0;
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max_size);
  u32 first = 0;
  u32 w = tex.info.width, h = tex.info.height;
  while (max_size > 0 && (w > u32(max_size) || h > u32(max_size)) &&
         first + 1 < tex.info.level_count) {
    first++;
    w = w > 1 ? w / 2 : 1;
    h = h > 1 ? h / 2 : 1;
  }
  if (first > 0) {
    lg::warn("managed_assets: texture {}x{} exceeds GL_MAX_TEXTURE_SIZE {} — dropping {} mips",
             tex.info.width, tex.info.height, max_size, first);
  }
  const u32 levels = tex.info.level_count - first;
  const bool compressed = ktx2::is_compressed(tex.info.vk_format);
  glTexStorage2D(GL_TEXTURE_2D, levels, internal, w, h);
  u32 lw = w, lh = h;
  for (u32 i = 0; i < levels; i++) {
    const auto& li = tex.info.levels[first + i];
    const u8* src = tex.payload.data() + li.byte_offset;
    if (compressed) {
      glCompressedTexSubImage2D(GL_TEXTURE_2D, i, 0, 0, lw, lh, internal, GLsizei(li.byte_length),
                                src);
    } else {
      glTexSubImage2D(GL_TEXTURE_2D, i, 0, 0, lw, lh, GL_RGBA, GL_UNSIGNED_BYTE, src);
    }
    lw = lw > 1 ? lw / 2 : 1;
    lh = lh > 1 ? lh / 2 : 1;
  }
  const GLenum gl_err = glGetError();
  if (gl_err != GL_NO_ERROR) {
    lg::warn("managed_assets: GL error {:#x} during compressed upload", gl_err);
    return false;
  }
  return true;
}

}  // namespace managed_assets
