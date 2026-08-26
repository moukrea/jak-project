#pragma once

// Grecharged-managed-assets: reader for `assets.lock.json`, the file that
// pins a build to ONE exact, immutable asset release
// (github.com/moukrea/recharged-assets, schemas/assets-lock.schema.json).
// The game never resolves the release marked "latest": the lock names the
// manifest URL and its SHA-256, and the asset manager refuses anything else.
//
// Absent lock = the managed-pack feature is simply dormant (stock textures),
// which is the state of every build that does not ship one.

#include <optional>
#include <string>

#include "common/common_types.h"
#include "common/util/FileUtil.h"

namespace assets_lock {

// Highest lock schema this build understands.
constexpr u32 kSupportedSchemaVersion = 1;

struct Lock {
  u32 schema_version = 0;
  std::string asset_version;    // "assets-vX.Y.Z"
  std::string manifest_url;
  std::string manifest_sha256;  // 64 lowercase hex chars
  // true = this build expects the pack to be installed; it still must not
  // block launch offline (spec §15) — it only distinguishes "a required
  // asset is missing" from "an optional update exists".
  bool required = false;
};

// Parse and validate. Returns nullopt when the file is absent, malformed, or
// declares a schema this build cannot read; err (optional) gets the reason.
// An absent file is NOT an error: err is left empty.
std::optional<Lock> load(const fs::path& path, std::string* err = nullptr);

// Default location: <project dir>/assets.lock.json
fs::path default_path();

}  // namespace assets_lock
