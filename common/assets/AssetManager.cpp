#include "AssetManager.h"

#include <algorithm>
#include <set>

#include "common/log/log.h"
#include "common/util/RPack.h"

#include "fmt/core.h"
#include "third-party/json.hpp"

namespace assets {

namespace {

fs::path state_path(const fs::path& dir) {
  return dir / "state.json";
}

fs::path staging_dir(const fs::path& dir) {
  return dir / "staging";
}

std::string hash_file(const fs::path& p) {
  const auto data = file_util::read_binary_file(p);
  return rpack::sha256_hex(data.data(), data.size());
}

bool has_all_features(const std::vector<std::string>& needed,
                      const std::vector<std::string>& have) {
  for (const auto& f : needed) {
    if (std::find(have.begin(), have.end(), f) == have.end()) {
      return false;
    }
  }
  return true;
}

}  // namespace

std::optional<InstalledState> read_state(const fs::path& dir, std::string* err) {
  const auto p = state_path(dir);
  if (!fs::exists(p)) {
    return std::nullopt;  // nothing installed: not an error
  }
  try {
    const auto j = nlohmann::json::parse(file_util::read_text_file(p));
    InstalledState s;
    s.schema_version = j.value("schema_version", 0u);
    if (s.schema_version != 1) {
      if (err) {
        *err = fmt::format("state.json: schema_version {} unsupported", s.schema_version);
      }
      return std::nullopt;
    }
    s.asset_version = j.value("asset_version", "");
    s.profile = j.value("profile", "");
    s.preset = j.value("preset", "");
    s.verified = j.value("verified", false);
    s.shards = j.value("shards", std::vector<std::string>{});
    return s;
  } catch (const std::exception& e) {
    if (err) {
      *err = fmt::format("state.json: {}", e.what());
    }
    return std::nullopt;
  }
}

InstallPlan plan_install(const Manifest& manifest, const Selection& sel, const fs::path& dir) {
  InstallPlan plan;
  plan.asset_version = manifest.asset_version;

  std::set<std::string> wanted_names;
  for (const auto& s : manifest.shards) {
    if (s.game != sel.game || s.profile != sel.profile || s.preset != sel.preset) {
      continue;
    }
    if (!has_all_features(s.requires_features, sel.features)) {
      continue;  // e.g. material shards on a build without OG_FEAT_PBR
    }
    wanted_names.insert(s.name);
    plan.total_bytes += s.size;
    // Shard names carry their content hash, so a present file of the right
    // size is the right content — the full hash check happens at install and
    // on demand via verify_install(), not on every boot.
    const auto local = dir / s.name;
    std::error_code ec;
    if (fs::exists(local) && fs::file_size(local, ec) == s.size && !ec) {
      plan.keep.push_back(s.name);
    } else {
      plan.download_bytes += s.size;
      plan.to_download.push_back(s);
    }
  }

  if (const auto st = read_state(dir)) {
    for (const auto& name : st->shards) {
      if (!wanted_names.count(name)) {
        plan.orphans.push_back(name);
      }
    }
  }
  return plan;
}

ApplyResult apply_install(const Manifest& manifest,
                          const Selection& sel,
                          const InstallPlan& plan,
                          const fs::path& dir,
                          Transport& transport,
                          const std::function<void(const Progress&)>& on_progress,
                          const std::function<bool()>& cancel) {
  ApplyResult res;
  res.kept = plan.keep.size();
  std::error_code ec;
  fs::create_directories(staging_dir(dir), ec);
  if (ec) {
    res.error = fmt::format("cannot create {}: {}", staging_dir(dir).string(), ec.message());
    return res;
  }

  u64 done = 0;
  for (size_t i = 0; i < plan.to_download.size(); i++) {
    const auto& s = plan.to_download[i];
    if (cancel && cancel()) {
      res.error = "cancelled";
      return res;  // previous install untouched; staging kept for resume
    }
    if (on_progress) {
      on_progress(Progress{i, plan.to_download.size(), s.name, done, plan.download_bytes});
    }
    const auto tmp = staging_dir(dir) / s.name;
    std::string err;
    if (!transport.download(s.url, tmp, s.size, &err)) {
      res.error = fmt::format("download failed for {}: {}", s.name, err);
      return res;
    }
    // Verify BEFORE the file can ever be seen by the loader.
    if (fs::file_size(tmp, ec) != s.size || ec) {
      fs::remove(tmp, ec);
      res.error = fmt::format("size mismatch for {}", s.name);
      return res;
    }
    if (hash_file(tmp) != s.sha256) {
      fs::remove(tmp, ec);
      res.error = fmt::format("sha256 mismatch for {}", s.name);
      return res;
    }
    fs::rename(tmp, dir / s.name, ec);
    if (ec) {
      res.error = fmt::format("cannot install {}: {}", s.name, ec.message());
      return res;
    }
    done += s.size;
    res.downloaded++;
  }
  if (on_progress) {
    on_progress(Progress{plan.to_download.size(), plan.to_download.size(), "", done,
                         plan.download_bytes});
  }

  // ---- atomic switch: write beside, fsync-by-rename ----------------------
  InstalledState st;
  st.asset_version = manifest.asset_version;
  st.profile = sel.profile;
  st.preset = sel.preset;
  st.verified = true;
  st.shards = plan.keep;
  for (const auto& s : plan.to_download) {
    st.shards.push_back(s.name);
  }
  std::sort(st.shards.begin(), st.shards.end());

  nlohmann::json j;
  j["schema_version"] = st.schema_version;
  j["asset_version"] = st.asset_version;
  j["profile"] = st.profile;
  j["preset"] = st.preset;
  j["verified"] = st.verified;
  j["shards"] = st.shards;
  const auto tmp_state = dir / "state.json.new";
  file_util::write_text_file(tmp_state, j.dump(1));
  fs::rename(tmp_state, state_path(dir), ec);
  if (ec) {
    fs::remove(tmp_state, ec);
    res.error = fmt::format("cannot switch state.json: {}", ec.message());
    return res;  // old install still current — this is the rollback
  }

  // ---- only now are the old shards unreachable ---------------------------
  for (const auto& name : plan.orphans) {
    if (fs::remove(dir / name, ec)) {
      res.removed++;
    }
  }
  fs::remove_all(staging_dir(dir), ec);

  lg::info("managed assets: {} installed ({} downloaded, {} kept, {} removed) profile={} preset={}",
           st.asset_version, res.downloaded, res.kept, res.removed, st.profile, st.preset);
  res.ok = true;
  return res;
}

std::vector<std::string> verify_install(const Manifest& manifest, const fs::path& dir) {
  std::vector<std::string> bad;
  const auto st = read_state(dir);
  if (!st) {
    return bad;
  }
  for (const auto& name : st->shards) {
    const auto it = std::find_if(manifest.shards.begin(), manifest.shards.end(),
                                 [&](const Shard& s) { return s.name == name; });
    const auto p = dir / name;
    std::error_code ec;
    if (it == manifest.shards.end() || !fs::exists(p) || fs::file_size(p, ec) != it->size || ec ||
        hash_file(p) != it->sha256) {
      bad.push_back(name);
    }
  }
  return bad;
}

}  // namespace assets
