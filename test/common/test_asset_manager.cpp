// Grecharged-managed-assets: asset-manager core tests (plan phase C).
// The Transport is faked with local files, so resume / verification /
// atomic-switch / rollback / orphan-GC are all exercised without a network.

#include "common/assets/AssetManager.h"
#include "common/assets/Manifest.h"
#include "common/util/FileUtil.h"
#include "common/util/RPack.h"

#include "fmt/core.h"
#include "gtest/gtest.h"
#include "third-party/json.hpp"

namespace {

fs::path scratch(const char* name) {
  const auto p = file_util::get_jak_project_dir() / "test" / "test_data" / "recharged" / name;
  std::error_code ec;
  fs::remove_all(p, ec);
  fs::create_directories(p, ec);
  return p;
}

std::vector<u8> blob(u8 fill, size_t n) {
  return std::vector<u8>(n, fill);
}

// A transport serving files from an in-memory "server", able to fail or to
// truncate a response so resume can be exercised.
struct FakeTransport : assets::Transport {
  std::map<std::string, std::vector<u8>> files;
  std::map<std::string, std::string> texts;
  int fail_after = -1;      // fail the Nth download (0-based); -1 = never
  size_t truncate_to = 0;   // if set, the failing download writes this many bytes first
  int downloads = 0;
  int resumed = 0;

  bool fetch(const std::string& url, std::string* out, std::string* err) override {
    auto it = texts.find(url);
    if (it == texts.end()) {
      *err = "404";
      return false;
    }
    *out = it->second;
    return true;
  }

  bool download(const std::string& url,
                const fs::path& dest,
                u64 expected_size,
                std::string* err) override {
    auto it = files.find(url);
    if (it == files.end()) {
      *err = "404";
      return false;
    }
    const int n = downloads++;
    std::error_code ec;
    u64 have = fs::exists(dest) ? (u64)fs::file_size(dest, ec) : 0;
    if (have) {
      resumed++;
    }
    if (n == fail_after) {
      // write a prefix, then fail — exactly what a dropped connection does
      const size_t upto = std::min(truncate_to, it->second.size());
      if (upto > have) {
        file_util::write_binary_file(dest, it->second.data(), upto);
      }
      *err = "connection reset";
      return false;
    }
    // honour the partial prefix: append the remainder
    std::vector<u8> full = it->second;
    file_util::write_binary_file(dest, full.data(), full.size());
    EXPECT_EQ(full.size(), expected_size);
    return true;
  }
};

struct Fixture {
  fs::path dir;
  FakeTransport transport;
  assets::Manifest manifest;
  assets::Selection sel;
};

// Two albedo shards + one material shard (feature-gated on "pbr").
Fixture make_fixture(const char* dirname) {
  Fixture f;
  f.dir = scratch(dirname);
  struct Def {
    const char* name;
    const char* group;
    u8 fill;
    size_t size;
    bool pbr;
  };
  const Def defs[] = {
      {"jak1-pc-bc-default-albedo-shard-c1-village1-beach-aaaaaaaaaaaa.rpack", "albedo", 0xA1,
       4096, false},
      {"jak1-pc-bc-default-albedo-shard-c2-jungle-misty-bbbbbbbbbbbb.rpack", "albedo", 0xB2, 8192,
       false},
      {"jak1-pc-bc-default-material-shard-c1-village1-beach-cccccccccccc.rpack", "material", 0xC3,
       2048, true},
      // a different preset, must never be selected
      {"jak1-pc-bc-low-albedo-shard-c1-village1-beach-dddddddddddd.rpack", "albedo", 0xD4, 512,
       false},
  };
  nlohmann::json shards = nlohmann::json::array();
  for (const auto& d : defs) {
    const auto data = blob(d.fill, d.size);
    const std::string url = std::string("https://fake/") + d.name;
    f.transport.files[url] = data;
    nlohmann::json s;
    s["name"] = d.name;
    s["game"] = "jak1";
    s["profile"] = "pc-bc";
    s["preset"] = std::string(d.name).find("-low-") != std::string::npos ? "low" : "default";
    s["group"] = d.group;
    s["cluster"] = "c1-village1-beach";
    s["sha256"] = rpack::sha256_hex(data.data(), data.size());
    s["size"] = data.size();
    s["url"] = url;
    s["release_tag"] = "assets-v9.9.9";
    s["entry_count"] = 1;
    if (d.pbr) {
      s["requires_features"] = nlohmann::json::array({"pbr"});
    }
    shards.push_back(s);
  }
  nlohmann::json j;
  j["schema_version"] = 1;
  j["asset_version"] = "assets-v9.9.9";
  j["games"] = nlohmann::json::array({"jak1"});
  j["engine_compat"] = {{"min_recharged_version", "0.1.0"},
                        {"max_recharged_version", nullptr},
                        {"min_loader_version", 1}};
  j["profiles"] = nlohmann::json::array({"pc-bc"});
  j["presets"] = nlohmann::json::array({"default", "low"});
  j["shards"] = shards;

  std::string err;
  auto m = assets::parse_manifest(j.dump(), rpack::kLoaderVersion, &err);
  EXPECT_TRUE(m.has_value()) << err;
  f.manifest = *m;
  f.sel.profile = "pc-bc";
  f.sel.preset = "default";
  f.sel.features = {"pbr"};
  return f;
}

}  // namespace

TEST(Manifest, RejectsFutureLoaderAndBadFields) {
  std::string err;
  EXPECT_FALSE(assets::parse_manifest("{ nope", 1, &err).has_value());
  EXPECT_NE(err.find("parse"), std::string::npos);

  auto f = make_fixture("am_manifest");
  nlohmann::json j = nlohmann::json::parse(
      R"({"schema_version":1,"asset_version":"assets-v1.0.0","games":["jak1"],
          "engine_compat":{"min_loader_version":99},"profiles":["pc-bc"],
          "presets":["default"],"shards":[]})");
  EXPECT_FALSE(assets::parse_manifest(j.dump(), 1, &err).has_value());
  EXPECT_NE(err.find("loader version"), std::string::npos) << err;
}

TEST(Manifest, RejectsUnsafeShardName) {
  auto f = make_fixture("am_unsafe");
  nlohmann::json j = nlohmann::json::parse(R"({
    "schema_version":1,"asset_version":"assets-v1.0.0","games":["jak1"],
    "engine_compat":{"min_loader_version":1},"profiles":["pc-bc"],"presets":["default"],
    "shards":[{"name":"../escape.rpack","game":"jak1","profile":"pc-bc","preset":"default",
      "group":"albedo","cluster":"c1","sha256":"aa","size":1,"url":"https://x","entry_count":1}]})");
  std::string err;
  EXPECT_FALSE(assets::parse_manifest(j.dump(), 1, &err).has_value());
}

TEST(AssetManager, PlanSelectsProfilePresetAndFeatures) {
  auto f = make_fixture("am_plan");
  auto plan = assets::plan_install(f.manifest, f.sel, f.dir);
  EXPECT_EQ(plan.to_download.size(), 3u);  // 2 albedo + 1 material
  EXPECT_EQ(plan.download_bytes, 4096u + 8192u + 2048u);
  EXPECT_TRUE(plan.keep.empty());
  EXPECT_TRUE(plan.orphans.empty());

  // Without the pbr feature the material shard is skipped, not failed.
  f.sel.features.clear();
  auto plan_nopbr = assets::plan_install(f.manifest, f.sel, f.dir);
  EXPECT_EQ(plan_nopbr.to_download.size(), 2u);
  EXPECT_EQ(plan_nopbr.download_bytes, 4096u + 8192u);
}

TEST(AssetManager, InstallVerifiesAndSwitchesAtomically) {
  auto f = make_fixture("am_install");
  auto plan = assets::plan_install(f.manifest, f.sel, f.dir);
  auto res = assets::apply_install(f.manifest, f.sel, plan, f.dir, f.transport);
  ASSERT_TRUE(res.ok) << res.error;
  EXPECT_EQ(res.downloaded, 3u);

  auto st = assets::read_state(f.dir);
  ASSERT_TRUE(st.has_value());
  EXPECT_TRUE(st->verified);
  EXPECT_EQ(st->asset_version, "assets-v9.9.9");
  EXPECT_EQ(st->shards.size(), 3u);
  for (const auto& name : st->shards) {
    EXPECT_TRUE(fs::exists(f.dir / name)) << name;
  }
  // staging is cleaned up, the wrong-preset shard was never fetched
  EXPECT_FALSE(fs::exists(f.dir / "staging"));
  EXPECT_TRUE(assets::verify_install(f.manifest, f.dir).empty());

  // Re-planning is a no-op: content-addressed names are already right.
  auto plan2 = assets::plan_install(f.manifest, f.sel, f.dir);
  EXPECT_TRUE(plan2.up_to_date());
  EXPECT_EQ(plan2.keep.size(), 3u);
}

TEST(AssetManager, CorruptDownloadIsRejectedAndStateUntouched) {
  auto f = make_fixture("am_corrupt");
  // serve wrong bytes for the first shard
  const auto& first = f.manifest.shards.front();
  f.transport.files[first.url] = blob(0xFF, first.size);

  auto plan = assets::plan_install(f.manifest, f.sel, f.dir);
  auto res = assets::apply_install(f.manifest, f.sel, plan, f.dir, f.transport);
  EXPECT_FALSE(res.ok);
  EXPECT_NE(res.error.find("sha256"), std::string::npos) << res.error;
  // nothing installed, and no state written
  EXPECT_FALSE(fs::exists(f.dir / "state.json"));
  EXPECT_FALSE(fs::exists(f.dir / first.name));
}

TEST(AssetManager, InterruptedDownloadResumesOnRetry) {
  auto f = make_fixture("am_resume");
  f.transport.fail_after = 1;   // second shard drops mid-transfer
  f.transport.truncate_to = 3000;

  auto plan = assets::plan_install(f.manifest, f.sel, f.dir);
  auto res = assets::apply_install(f.manifest, f.sel, plan, f.dir, f.transport);
  EXPECT_FALSE(res.ok);
  EXPECT_FALSE(fs::exists(f.dir / "state.json"));  // previous state (none) intact
  // the partial file survives in staging for the retry
  const auto partial = f.dir / "staging" / plan.to_download[1].name;
  ASSERT_TRUE(fs::exists(partial));
  EXPECT_EQ(fs::file_size(partial), 3000u);

  // retry: the transport sees the prefix and reports a resume
  f.transport.fail_after = -1;
  auto plan2 = assets::plan_install(f.manifest, f.sel, f.dir);
  auto res2 = assets::apply_install(f.manifest, f.sel, plan2, f.dir, f.transport);
  ASSERT_TRUE(res2.ok) << res2.error;
  EXPECT_GE(f.transport.resumed, 1);
  EXPECT_TRUE(assets::verify_install(f.manifest, f.dir).empty());
}

TEST(AssetManager, PresetSwitchKeepsSharedShardsAndRemovesOrphans) {
  auto f = make_fixture("am_switch");
  auto plan = assets::plan_install(f.manifest, f.sel, f.dir);
  ASSERT_TRUE(assets::apply_install(f.manifest, f.sel, plan, f.dir, f.transport).ok);

  f.sel.preset = "low";
  auto plan_low = assets::plan_install(f.manifest, f.sel, f.dir);
  EXPECT_EQ(plan_low.to_download.size(), 1u);
  EXPECT_EQ(plan_low.orphans.size(), 3u);  // the three default-preset shards
  auto res = assets::apply_install(f.manifest, f.sel, plan_low, f.dir, f.transport);
  ASSERT_TRUE(res.ok) << res.error;
  EXPECT_EQ(res.removed, 3u);

  auto st = assets::read_state(f.dir);
  ASSERT_TRUE(st.has_value());
  EXPECT_EQ(st->preset, "low");
  EXPECT_EQ(st->shards.size(), 1u);
  // the orphans really are gone
  for (const auto& s : f.manifest.shards) {
    if (s.preset == "default") {
      EXPECT_FALSE(fs::exists(f.dir / s.name)) << s.name;
    }
  }
}

TEST(AssetManager, CancelLeavesPreviousInstallUsable) {
  auto f = make_fixture("am_cancel");
  auto plan = assets::plan_install(f.manifest, f.sel, f.dir);
  ASSERT_TRUE(assets::apply_install(f.manifest, f.sel, plan, f.dir, f.transport).ok);
  const auto before = assets::read_state(f.dir);

  f.sel.preset = "low";
  auto plan_low = assets::plan_install(f.manifest, f.sel, f.dir);
  auto res = assets::apply_install(f.manifest, f.sel, plan_low, f.dir, f.transport, nullptr,
                                   [] { return true; });
  EXPECT_FALSE(res.ok);
  EXPECT_EQ(res.error, "cancelled");
  const auto after = assets::read_state(f.dir);
  ASSERT_TRUE(after.has_value());
  EXPECT_EQ(after->preset, before->preset);
  EXPECT_EQ(after->shards, before->shards);
  EXPECT_TRUE(assets::verify_install(f.manifest, f.dir).empty());
}

TEST(AssetManager, VerifyDetectsTamperedShard) {
  auto f = make_fixture("am_verify");
  auto plan = assets::plan_install(f.manifest, f.sel, f.dir);
  ASSERT_TRUE(assets::apply_install(f.manifest, f.sel, plan, f.dir, f.transport).ok);

  const auto victim = f.dir / f.manifest.shards.front().name;
  auto data = file_util::read_binary_file(victim);
  data[0] ^= 0xFF;
  file_util::write_binary_file(victim, data.data(), data.size());

  const auto bad = assets::verify_install(f.manifest, f.dir);
  ASSERT_EQ(bad.size(), 1u);
  EXPECT_EQ(bad.front(), f.manifest.shards.front().name);
}
