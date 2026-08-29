#include "AssetCli.h"

#include <cstdio>

#include "common/assets/AssetManager.h"
#include "common/log/log.h"
#include "common/util/AssetsLock.h"
#include "common/util/FileUtil.h"
#include "common/util/RPack.h"

#include "game/assets/CurlTransport.h"

#include "fmt/core.h"

namespace assets {

namespace {

fs::path managed_dir(GameVersion v) {
  return file_util::get_jak_project_dir() / "managed_assets" / game_version_names[v];
}

std::string human(u64 bytes) {
  if (bytes >= (1ull << 30)) {
    return fmt::format("{:.2f} GiB", double(bytes) / double(1ull << 30));
  }
  return fmt::format("{:.1f} MiB", double(bytes) / double(1ull << 20));
}

// Features this binary can consume. Material shards are gated on "pbr", so a
// build without OG_FEAT_PBR installs the albedo half and nothing else.
std::vector<std::string> build_features() {
  std::vector<std::string> f;
#ifdef OG_FEAT_PBR
  f.emplace_back("pbr");
#endif
  return f;
}

// Load the lock, fetch its manifest and check the hash it pins.
bool load_manifest(Manifest* out) {
  std::string err;
  const auto lock = assets_lock::load(assets_lock::default_path(), &err);
  if (!lock) {
    fmt::print("no usable assets.lock.json ({})\n",
               err.empty() ? "file absent — managed packs are not configured for this build" : err);
    return false;
  }
  fmt::print("lock: {} ({})\n", lock->asset_version, lock->required ? "required" : "optional");

  CurlTransport transport;
  std::string body;
  if (!transport.fetch(lock->manifest_url, &body, &err)) {
    fmt::print("could not fetch the manifest: {}\n", err);
    return false;
  }
  const auto got = rpack::sha256_hex(reinterpret_cast<const u8*>(body.data()), body.size());
  if (got != lock->manifest_sha256) {
    fmt::print("MANIFEST HASH MISMATCH\n  expected {}\n  got      {}\n", lock->manifest_sha256, got);
    return false;
  }
  auto m = parse_manifest(body, rpack::kLoaderVersion, &err);
  if (!m) {
    fmt::print("{}\n", err);
    return false;
  }
  *out = std::move(*m);
  return true;
}

}  // namespace

int run_cli(const std::string& verb,
            GameVersion game_version,
            const std::string& profile_override,
            const std::string& preset,
            bool assume_yes) {
  const auto dir = managed_dir(game_version);
  const std::string game = game_version_names[game_version];

  // ---- status: works fully offline -------------------------------------
  if (verb == "status") {
    const auto st = read_state(dir);
    if (!st) {
      fmt::print("installed: nothing ({})\n", dir.string());
    } else {
      u64 bytes = 0;
      std::error_code ec;
      for (const auto& s : st->shards) {
        bytes += fs::exists(dir / s) ? (u64)fs::file_size(dir / s, ec) : 0;
      }
      fmt::print("installed: {} profile={} preset={} shards={} extras={} size={} verified={}\n",
                 st->asset_version, st->profile, st->preset, st->shards.size(),
                 st->extras.size(), human(bytes), st->verified);
    }
    std::string err;
    if (const auto lock = assets_lock::load(assets_lock::default_path(), &err)) {
      fmt::print("locked to: {}\n", lock->asset_version);
      const auto st2 = read_state(dir);
      if (st2 && st2->asset_version != lock->asset_version) {
        fmt::print("=> an update is available; run `gk --assets install`\n");
      }
    } else if (!err.empty()) {
      fmt::print("lock: {}\n", err);
    }
    return 0;
  }

  Manifest manifest;
  if (!load_manifest(&manifest)) {
    return 1;
  }

  // ---- verify -----------------------------------------------------------
  if (verb == "verify") {
    const auto bad = verify_install(manifest, dir);
    if (bad.empty()) {
      const auto st = read_state(dir);
      fmt::print("verify: OK ({} shards)\n", st ? st->shards.size() : 0);
      return 0;
    }
    fmt::print("verify: {} SHARD(S) FAILED\n", bad.size());
    for (const auto& b : bad) {
      fmt::print("  {}\n", b);
      std::error_code ec;
      fs::remove(dir / b, ec);  // drop it so the next install re-fetches
    }
    fmt::print("removed; run `gk --assets install` to repair\n");
    return 1;
  }

  // ---- install ----------------------------------------------------------
  if (verb != "install") {
    fmt::print("unknown --assets verb '{}' (expected status | install | verify)\n", verb);
    return 1;
  }

  Selection sel;
  sel.game = game;
  // Profile order: explicit flag > what the renderer detected on a previous run
  // (managed_assets/<game>/gpu_profile.txt, written by GpuCaps) > the desktop
  // BC default. The CLI is headless, so it cannot probe GL itself.
  sel.profile = profile_override;
  if (sel.profile.empty()) {
    const auto detected = dir / "gpu_profile.txt";
    if (fs::exists(detected)) {
      sel.profile = file_util::read_text_file(detected);
      while (!sel.profile.empty() && (sel.profile.back() == '\n' || sel.profile.back() == '\r' ||
                                      sel.profile.back() == ' ')) {
        sel.profile.pop_back();
      }
      if (!sel.profile.empty()) {
        fmt::print("using the profile detected by the renderer: {}\n", sel.profile);
      }
    }
  }
  if (sel.profile.empty()) {
    sel.profile = "pc-bc";
  }
  sel.preset = preset.empty() ? "default" : preset;
  sel.features = build_features();
  if (sel.preset == "very-low" || sel.preset == "off") {
    fmt::print("preset '{}' installs nothing (the game uses its stock textures)\n", sel.preset);
    return 0;
  }

  std::error_code ec;
  fs::create_directories(dir, ec);
  const auto plan = plan_install(manifest, sel, dir);
  // Gpbr-material-props: ask the PLAN whether it is up to date instead of re-deriving it here.
  // The hand-rolled `to_download.empty() && orphans.empty()` missed extras_to_download entirely,
  // and that is the exact shape of this install: every shard already present, one 60 KB
  // surfaces.json missing. The CLI printed "up to date" and returned 0 without ever calling
  // apply_install, so the file the whole phase exists to deliver never landed — a silent skip
  // that looks identical to success.
  if (plan.up_to_date()) {
    fmt::print("up to date: {} {}/{} ({} shards, {} extras, {})\n", manifest.asset_version,
               sel.profile, sel.preset, plan.keep.size(), plan.extras_to_download.size(),
               human(plan.total_bytes));
    return 0;
  }
  fmt::print("{} {}/{}: {} shards to download ({}), {} extras, {} kept, {} to remove\n",
             manifest.asset_version, sel.profile, sel.preset, plan.to_download.size(),
             human(plan.download_bytes), plan.extras_to_download.size(), plan.keep.size(),
             plan.orphans.size());

  // Free-space check before committing to a multi-GiB download.
  const auto space = fs::space(dir, ec);
  if (!ec && space.available < plan.download_bytes + (plan.download_bytes / 10)) {
    fmt::print("not enough free space: {} available, {} needed\n", human(space.available),
               human(plan.download_bytes));
    return 1;
  }
  if (!assume_yes) {
    fmt::print("proceed? [y/N] ");
    std::fflush(stdout);
    const int c = std::getchar();
    if (c != 'y' && c != 'Y') {
      fmt::print("aborted\n");
      return 1;
    }
  }

  CurlTransport transport;
  const auto res = apply_install(
      manifest, sel, plan, dir, transport, [&](const Progress& p) {
        if (!p.shard_name.empty()) {
          fmt::print("  [{}/{}] {} ({})\n", p.shard_index + 1, p.shard_count, p.shard_name,
                     human(p.bytes_total - p.bytes_done));
          std::fflush(stdout);
        }
      });
  if (!res.ok) {
    fmt::print("install FAILED: {}\n(the previous installation is untouched)\n", res.error);
    return 1;
  }
  fmt::print("installed {} ({} downloaded, {} kept, {} removed)\n", manifest.asset_version,
             res.downloaded, res.kept, res.removed);
  return 0;
}

}  // namespace assets
