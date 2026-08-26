#pragma once

// Grecharged-managed-assets: the shared asset-manager core (plan phase C).
// Platform-independent by construction — the network lives behind Transport,
// so PC uses libcurl, Android hands files in from its Kotlin downloader, and
// the tests use a local fake. The install algorithm is the same everywhere,
// and it mirrors tools/install_pack.py in the assets repo (the oracle).
//
// Guarantees:
//   * nothing is installed that fails size + SHA-256 verification;
//   * `state.json` switches by rename, so a kill at any point leaves the
//     previous install intact and usable (spec §15);
//   * downloads resume (Transport reports how many bytes are already on
//     disk and appends);
//   * orphaned shards from older versions are removed only AFTER the switch.

#include <functional>
#include <optional>
#include <string>
#include <vector>

#include "common/assets/Manifest.h"
#include "common/common_types.h"
#include "common/util/FileUtil.h"

namespace assets {

// ---------------------------------------------------------------- transport

struct Transport {
  virtual ~Transport() = default;

  // Small file (the manifest). Returns false and sets err on failure.
  virtual bool fetch(const std::string& url, std::string* out, std::string* err) = 0;

  // Download `url` to `dest`, resuming if `dest` already holds a prefix.
  // Implementations must append rather than truncate when resuming.
  virtual bool download(const std::string& url,
                        const fs::path& dest,
                        u64 expected_size,
                        std::string* err) = 0;
};

// ---------------------------------------------------------------- state

// What is installed on disk right now (managed_assets/<game>/state.json).
struct InstalledState {
  u32 schema_version = 1;
  std::string asset_version;
  std::string profile;
  std::string preset;
  bool verified = false;
  std::vector<std::string> shards;
};

std::optional<InstalledState> read_state(const fs::path& dir, std::string* err = nullptr);

// ---------------------------------------------------------------- plan

struct InstallPlan {
  std::string asset_version;
  std::vector<Shard> to_download;  // missing or size-mismatched
  std::vector<std::string> keep;   // already present, content-addressed
  std::vector<std::string> orphans;  // installed but not in the new set
  u64 download_bytes = 0;
  u64 total_bytes = 0;
  bool up_to_date() const { return to_download.empty() && orphans.empty(); }
};

struct Selection {
  std::string game = "jak1";
  std::string profile;   // from GpuCaps
  std::string preset;    // user setting; "" or "very-low" installs nothing
  std::vector<std::string> features;  // engine features this build has, e.g. {"pbr"}
};

// Resolve the wanted shard set for `sel` and diff it against `dir`.
// Shards whose requires_features are not all present are skipped (an
// albedo-only install on a non-PBR build is a supported configuration).
InstallPlan plan_install(const Manifest& manifest, const Selection& sel, const fs::path& dir);

// ---------------------------------------------------------------- apply

struct Progress {
  size_t shard_index = 0;
  size_t shard_count = 0;
  std::string shard_name;
  u64 bytes_done = 0;
  u64 bytes_total = 0;
};

struct ApplyResult {
  bool ok = false;
  std::string error;
  size_t downloaded = 0;
  size_t kept = 0;
  size_t removed = 0;
};

// Execute a plan: download → verify → atomic state switch → orphan GC.
// `cancel` is polled between shards; a cancelled apply leaves the previous
// install untouched (partial downloads stay in staging/ and resume later).
ApplyResult apply_install(const Manifest& manifest,
                          const Selection& sel,
                          const InstallPlan& plan,
                          const fs::path& dir,
                          Transport& transport,
                          const std::function<void(const Progress&)>& on_progress = nullptr,
                          const std::function<bool()>& cancel = nullptr);

// Re-verify every installed shard against the manifest (menu "re-verify").
// Returns the names that failed; an empty result means the install is sound.
std::vector<std::string> verify_install(const Manifest& manifest, const fs::path& dir);

}  // namespace assets
