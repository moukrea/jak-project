#include "Manifest.h"

#include "common/log/log.h"

#include "fmt/core.h"
#include "third-party/json.hpp"

namespace assets {

namespace {

// Extras this build knows how to consume. Anything else is skipped rather than rejected: the
// manifest describes ONE asset version for every client, and a newer release must not become
// unreadable to an older binary just because it also publishes a file that binary ignores.
bool is_known_extra_kind(const std::string& kind) {
  return kind == "surfaces";
}

}  // namespace

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

    // `extras` is OPTIONAL on purpose: every manifest published so far predates it, and reading it
    // with at() would make all of them fail to parse here.
    for (const auto& e : j.value("extras", nlohmann::json::array())) {
      const auto str = [&e](const char* key) -> std::string {
        return (e.contains(key) && e[key].is_string()) ? e[key].get<std::string>() : std::string();
      };
      Extra ex;
      ex.name = str("name");
      ex.game = str("game");
      ex.kind = str("kind");
      ex.sha256 = str("sha256");
      ex.size = (e.contains("size") && e["size"].is_number_unsigned()) ? e["size"].get<u64>() : 0;
      ex.url = str("url");
      ex.release_tag = str("release_tag");
      if (e.contains("requires_features") && e["requires_features"].is_array()) {
        for (const auto& f : e["requires_features"]) {
          if (f.is_string()) {
            ex.requires_features.push_back(f.get<std::string>());
          }
        }
      }
      // A malformed extra costs one file, not the whole manifest — the shards must still install.
      if (ex.name.empty() || ex.game.empty() || ex.kind.empty() || ex.sha256.size() != 64 ||
          ex.size == 0 || ex.url.empty()) {
        lg::warn("manifest: skipping extra '{}': missing/bad fields", ex.name);
        continue;
      }
      // Same guard as the shards: this name becomes a path inside the install directory.
      if (ex.name.find('/') != std::string::npos || ex.name.find('\\') != std::string::npos ||
          ex.name.find("..") != std::string::npos) {
        lg::warn("manifest: skipping extra with unsafe name '{}'", ex.name);
        continue;
      }
      if (!is_known_extra_kind(ex.kind)) {
        lg::info("manifest: ignoring extra '{}' of kind '{}', unknown to this build", ex.name,
                 ex.kind);
        continue;
      }
      m.extras.push_back(std::move(ex));
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
