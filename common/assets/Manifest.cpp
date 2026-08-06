#include "Manifest.h"

#include "fmt/core.h"
#include "third-party/json.hpp"

namespace assets {

std::optional<Manifest> parse_manifest(const std::string& json_text,
                                       u32 loader_version,
                                       std::string* err) {
  auto fail = [&](const std::string& msg) -> std::optional<Manifest> {
    if (err) {
      *err = msg;
    }
    return std::nullopt;
  };

  nlohmann::json j;
  try {
    j = nlohmann::json::parse(json_text);
  } catch (const std::exception& e) {
    return fail(fmt::format("manifest: parse error: {}", e.what()));
  }

  Manifest m;
  try {
    m.schema_version = j.at("schema_version").get<u32>();
    if (m.schema_version != kManifestSchemaVersion) {
      return fail(fmt::format("manifest: schema_version {} unsupported (this build reads {})",
                              m.schema_version, kManifestSchemaVersion));
    }
    m.asset_version = j.at("asset_version").get<std::string>();
    m.games = j.at("games").get<std::vector<std::string>>();

    const auto& ec = j.at("engine_compat");
    m.engine_compat.min_recharged_version = ec.value("min_recharged_version", "");
    if (ec.contains("max_recharged_version") && !ec["max_recharged_version"].is_null()) {
      m.engine_compat.max_recharged_version = ec["max_recharged_version"].get<std::string>();
    }
    m.engine_compat.min_loader_version = ec.value("min_loader_version", 1u);
    m.engine_compat.required_features =
        ec.value("required_features", std::vector<std::string>{});
    // Refuse a manifest that needs a newer loader than this binary implements:
    // a new schema could change RPACK or the KTX2 subset under us.
    if (m.engine_compat.min_loader_version > loader_version) {
      return fail(fmt::format("manifest: needs loader version {}, this build has {}",
                              m.engine_compat.min_loader_version, loader_version));
    }

    m.profiles = j.at("profiles").get<std::vector<std::string>>();
    m.presets = j.at("presets").get<std::vector<std::string>>();

    for (const auto& s : j.at("shards")) {
      Shard sh;
      sh.name = s.at("name").get<std::string>();
      sh.game = s.at("game").get<std::string>();
      sh.profile = s.at("profile").get<std::string>();
      sh.preset = s.at("preset").get<std::string>();
      sh.group = s.at("group").get<std::string>();
      sh.cluster = s.at("cluster").get<std::string>();
      sh.sha256 = s.at("sha256").get<std::string>();
      sh.size = s.at("size").get<u64>();
      sh.url = s.at("url").get<std::string>();
      sh.release_tag = s.value("release_tag", "");
      sh.entry_count = s.at("entry_count").get<u32>();
      sh.requires_features = s.value("requires_features", std::vector<std::string>{});
      if (sh.sha256.size() != 64 || sh.size == 0 || sh.name.empty() || sh.url.empty()) {
        return fail(fmt::format("manifest: shard '{}' has bad fields", sh.name));
      }
      // A shard name must not escape the install directory.
      if (sh.name.find('/') != std::string::npos || sh.name.find('\\') != std::string::npos ||
          sh.name.find("..") != std::string::npos) {
        return fail(fmt::format("manifest: unsafe shard name '{}'", sh.name));
      }
      m.shards.push_back(std::move(sh));
    }
  } catch (const std::exception& e) {
    return fail(fmt::format("manifest: missing/bad field: {}", e.what()));
  }
  if (m.shards.empty()) {
    return fail("manifest: no shards");
  }
  return m;
}

}  // namespace assets
