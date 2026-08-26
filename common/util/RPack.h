#pragma once

// Grecharged-managed-assets: reader for RPACK v1 shards produced by the
// recharged-assets pipeline (github.com/moukrea/recharged-assets,
// schemas/rpack-v1.md). Layout: 16-byte header, 16-byte-aligned KTX2
// payloads, canonical-JSON index, 24-byte trailer. Random access without
// extraction; per-entry SHA-256 verification.

#include <map>
#include <optional>
#include <string>
#include <vector>

#include "common/common_types.h"

namespace rpack {

constexpr u32 kSchemaVersion = 1;
// Version of the loader contract this reader implements; compared against
// the manifest's engine_compat.min_loader_version.
constexpr u32 kLoaderVersion = 1;

// Decode-time statistics the PBR shaders need, precomputed by the pipeline
// (mirrors PbrMaterialMaps' measured fields — see CustomTextureReplacements.h).
struct EntryStats {
  bool has_normal_dc = false;
  float normal_dc_x = 0.f;
  float normal_dc_y = 0.f;
  bool has_height = false;
  float height_mean = 0.5f;
  float height_norm = 1.0f;
  float height_lambda_tiles = 0.25f;
};

struct Entry {
  std::string id;         // stable id: jak1/<tpage>/<name>
  std::string key;        // engine replacement key: <tpage>/<name>
  std::string map;        // albedo|normal|roughness|height|metallic|ao|specular|emissive|mask
  std::string format;     // VK_FORMAT_* name (informative; the KTX2 header is authoritative)
  std::string colorspace; // srgb-encoded|linear
  std::string alpha_mode; // none|binary|progressive|premultiplied
  std::string wrap_mode;  // clamp|repeat_x|repeat_y|repeat
  std::string channels;   // rgb|rgba|rg|r ("rg" normals reconstruct Z in-shader)
  u32 width = 0;
  u32 height = 0;
  u32 mip_levels = 0;
  u64 offset = 0;
  u64 size = 0;
  std::string sha256;     // lowercase hex of the payload
  EntryStats stats;
};

class Reader {
 public:
  // Opens and parses header/trailer/index. Throws nothing: check ok().
  explicit Reader(const std::string& path);

  bool ok() const { return m_ok; }
  const std::string& error() const { return m_error; }

  const std::string& game() const { return m_game; }
  const std::string& profile() const { return m_profile; }
  const std::string& preset() const { return m_preset; }
  const std::string& group() const { return m_group; }
  const std::string& cluster() const { return m_cluster; }

  const std::vector<Entry>& entries() const { return m_entries; }
  // Lookup by (replacement key, map kind); nullptr on miss.
  const Entry* find(const std::string& key, const std::string& map) const;

  // Read one payload (seek + read). With verify, the SHA-256 is checked —
  // slower, used at install/verification time; the load path trusts the
  // installer's verified state.
  std::optional<std::vector<u8>> read_payload(const Entry& entry, bool verify) const;

 private:
  bool m_ok = false;
  std::string m_error;
  std::string m_path;
  std::string m_game, m_profile, m_preset, m_group, m_cluster;
  std::vector<Entry> m_entries;
  std::map<std::pair<std::string, std::string>, size_t> m_by_key;
};

// Standalone SHA-256 (also used by the asset-manager installer).
std::string sha256_hex(const u8* data, size_t size);

}  // namespace rpack
