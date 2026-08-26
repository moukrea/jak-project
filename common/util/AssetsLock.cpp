#include "AssetsLock.h"

#include "fmt/core.h"
#include "third-party/json.hpp"

namespace assets_lock {

namespace {
bool is_sha256_hex(const std::string& s) {
  if (s.size() != 64) {
    return false;
  }
  for (char c : s) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
      return false;
    }
  }
  return true;
}
}  // namespace

fs::path default_path() {
  return file_util::get_jak_project_dir() / "assets.lock.json";
}

std::optional<Lock> load(const fs::path& path, std::string* err) {
  if (err) {
    err->clear();
  }
  if (!fs::exists(path)) {
    return std::nullopt;  // dormant, not an error
  }
  nlohmann::json j;
  try {
    j = nlohmann::json::parse(file_util::read_text_file(path));
  } catch (const std::exception& e) {
    if (err) {
      *err = fmt::format("assets.lock.json: parse error: {}", e.what());
    }
    return std::nullopt;
  }

  Lock lock;
  try {
    lock.schema_version = j.at("schema_version").get<u32>();
    lock.asset_version = j.at("asset_version").get<std::string>();
    lock.manifest_url = j.at("manifest_url").get<std::string>();
    lock.manifest_sha256 = j.at("manifest_sha256").get<std::string>();
    lock.required = j.at("required").get<bool>();
  } catch (const std::exception& e) {
    if (err) {
      *err = fmt::format("assets.lock.json: missing/!bad field: {}", e.what());
    }
    return std::nullopt;
  }

  if (lock.schema_version != kSupportedSchemaVersion) {
    if (err) {
      *err = fmt::format("assets.lock.json: schema_version {} unsupported (this build reads {})",
                         lock.schema_version, kSupportedSchemaVersion);
    }
    return std::nullopt;
  }
  if (lock.asset_version.rfind("assets-v", 0) != 0) {
    if (err) {
      *err = fmt::format("assets.lock.json: bad asset_version '{}'", lock.asset_version);
    }
    return std::nullopt;
  }
  if (!is_sha256_hex(lock.manifest_sha256)) {
    if (err) {
      *err = "assets.lock.json: manifest_sha256 is not 64 lowercase hex chars";
    }
    return std::nullopt;
  }
  // A lock that points at a mutable "latest" URL defeats the whole point.
  if (lock.manifest_url.find("/latest/") != std::string::npos) {
    if (err) {
      *err = "assets.lock.json: manifest_url must name an immutable release, not 'latest'";
    }
    return std::nullopt;
  }
  return lock;
}

}  // namespace assets_lock
