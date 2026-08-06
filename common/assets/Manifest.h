#pragma once

// Grecharged-managed-assets: the release manifest published by
// github.com/moukrea/recharged-assets (schemas/manifest.schema.json).
// One manifest describes the COMPLETE state of an asset version, even when
// its shards live in several older immutable releases — so a client only
// ever downloads what its own installed state is missing.

#include <optional>
#include <string>
#include <vector>

#include "common/common_types.h"

namespace assets {

constexpr u32 kManifestSchemaVersion = 1;

struct Shard {
  std::string name;
  std::string game;
  std::string profile;   // pc-bc | pc-bc-legacy | android-etc2 | android-astc | rgba8-fallback
  std::string preset;    // low | default | bonkers
  std::string group;     // albedo | material
  std::string cluster;
  std::string sha256;
  u64 size = 0;
  std::string url;
  std::string release_tag;
  u32 entry_count = 0;
  std::vector<std::string> requires_features;  // e.g. {"pbr"} on material shards
};

struct EngineCompat {
  std::string min_recharged_version;
  std::string max_recharged_version;  // empty = open-ended
  u32 min_loader_version = 1;
  std::vector<std::string> required_features;
};

struct Manifest {
  u32 schema_version = 0;
  std::string asset_version;
  std::vector<std::string> games;
  EngineCompat engine_compat;
  std::vector<std::string> profiles;
  std::vector<std::string> presets;
  std::vector<Shard> shards;
};

// Parse + validate. Returns nullopt with a reason in err on anything this
// build cannot safely consume (unknown schema, loader too old, bad fields).
std::optional<Manifest> parse_manifest(const std::string& json_text,
                                       u32 loader_version,
                                       std::string* err);

}  // namespace assets
