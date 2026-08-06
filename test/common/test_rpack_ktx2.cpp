// Grecharged-managed-assets: RPACK + KTX2-subset reader tests against a
// fixture produced by the recharged-assets pipeline's Python writer — a
// cross-language conformance check of the RPACK v1 contract.

#include "common/util/AssetsLock.h"
#include "common/util/FileUtil.h"
#include "common/util/Ktx2Subset.h"
#include "common/util/RPack.h"

#include "gtest/gtest.h"

namespace {
std::string fixture_path() {
  return (file_util::get_jak_project_dir() / "test" / "test_data" / "recharged" /
          "fixture.rpack")
      .string();
}
}  // namespace

TEST(RPack, ParsesFixture) {
  rpack::Reader r(fixture_path());
  ASSERT_TRUE(r.ok()) << r.error();
  EXPECT_EQ(r.game(), "jak1");
  EXPECT_EQ(r.profile(), "pc-bc");
  EXPECT_EQ(r.preset(), "default");
  EXPECT_EQ(r.cluster(), "c1-village1-beach");
  ASSERT_EQ(r.entries().size(), 2u);

  const auto* alb = r.find("test-vis-tfrag/fixture", "albedo");
  ASSERT_NE(alb, nullptr);
  EXPECT_EQ(alb->format, "VK_FORMAT_BC7_UNORM_BLOCK");
  EXPECT_EQ(alb->width, 8u);
  EXPECT_EQ(alb->mip_levels, 4u);
  EXPECT_EQ(alb->colorspace, "srgb-encoded");
  EXPECT_FALSE(alb->stats.has_height);

  const auto* hgt = r.find("test-vis-tfrag/fixture", "height");
  ASSERT_NE(hgt, nullptr);
  EXPECT_TRUE(hgt->stats.has_height);
  EXPECT_NEAR(hgt->stats.height_mean, 0.512345f, 1e-6f);
  EXPECT_NEAR(hgt->stats.height_norm, 1.25f, 1e-6f);
  EXPECT_NEAR(hgt->stats.height_lambda_tiles, 0.5f, 1e-6f);

  EXPECT_EQ(r.find("test-vis-tfrag/fixture", "normal"), nullptr);
  EXPECT_EQ(r.find("nope/nope", "albedo"), nullptr);
}

TEST(RPack, PayloadVerifiesAgainstPythonSha256) {
  rpack::Reader r(fixture_path());
  ASSERT_TRUE(r.ok()) << r.error();
  const auto* alb = r.find("test-vis-tfrag/fixture", "albedo");
  ASSERT_NE(alb, nullptr);
  // hash recorded by the Python writer at fixture-generation time
  EXPECT_EQ(alb->sha256, "ee1425e894b1ae201424f61151633d6840a93afe8280f533bb78bb063ff05f59");
  auto payload = r.read_payload(*alb, /*verify=*/true);
  ASSERT_TRUE(payload.has_value());
  EXPECT_EQ(payload->size(), alb->size);
  // our own sha256 agrees with Python's
  EXPECT_EQ(rpack::sha256_hex(payload->data(), payload->size()), alb->sha256);
}

TEST(RPack, Sha256KnownVectors) {
  EXPECT_EQ(rpack::sha256_hex(nullptr, 0),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  const char* abc = "abc";
  EXPECT_EQ(rpack::sha256_hex(reinterpret_cast<const u8*>(abc), 3),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

TEST(RPack, RejectsCorruptedIndex) {
  auto data = file_util::read_binary_file(fixture_path());
  // flip one byte inside the JSON index (index starts after the payloads;
  // locate it from the trailer)
  u64 index_offset;
  memcpy(&index_offset, data.data() + data.size() - 24, 8);
  data[index_offset + 3] ^= 0xFF;
  const auto tmp = file_util::get_jak_project_dir() / "test" / "test_data" / "recharged" /
                   "corrupt.tmp.rpack";
  file_util::write_binary_file(tmp, data.data(), data.size());
  rpack::Reader r(tmp.string());
  EXPECT_FALSE(r.ok());
  EXPECT_NE(r.error().find("integrity"), std::string::npos) << r.error();
  fs::remove(tmp);
}

TEST(RPack, DetectsCorruptedPayloadOnVerify) {
  auto data = file_util::read_binary_file(fixture_path());
  rpack::Reader clean(fixture_path());
  ASSERT_TRUE(clean.ok());
  const auto* e = clean.find("test-vis-tfrag/fixture", "albedo");
  data[e->offset] ^= 0xFF;
  const auto tmp = file_util::get_jak_project_dir() / "test" / "test_data" / "recharged" /
                   "corrupt2.tmp.rpack";
  file_util::write_binary_file(tmp, data.data(), data.size());
  rpack::Reader r(tmp.string());
  ASSERT_TRUE(r.ok()) << r.error();  // index untouched
  const auto* e2 = r.find("test-vis-tfrag/fixture", "albedo");
  EXPECT_FALSE(r.read_payload(*e2, /*verify=*/true).has_value());
  EXPECT_TRUE(r.read_payload(*e2, /*verify=*/false).has_value());
  fs::remove(tmp);
}

TEST(Ktx2Subset, ParsesRealPayloads) {
  rpack::Reader r(fixture_path());
  ASSERT_TRUE(r.ok()) << r.error();
  for (const auto& e : r.entries()) {
    auto payload = r.read_payload(e, true);
    ASSERT_TRUE(payload.has_value());
    ktx2::Texture tex;
    std::string err;
    ASSERT_TRUE(ktx2::parse(payload->data(), payload->size(), &tex, &err)) << e.map << ": " << err;
    EXPECT_EQ(tex.width, e.width);
    EXPECT_EQ(tex.height, e.height);
    EXPECT_EQ(tex.level_count, e.mip_levels);
    // level sizes were validated by parse(); check the mip-0 geometry too
    u64 expect0 = ktx2::expected_level_size(tex.vk_format, tex.width, tex.height);
    EXPECT_EQ(tex.levels[0].byte_length, expect0);
  }
}

TEST(Ktx2Subset, RejectsGarbage) {
  ktx2::Texture tex;
  std::string err;
  std::vector<u8> junk(256, 0xCD);
  EXPECT_FALSE(ktx2::parse(junk.data(), junk.size(), &tex, &err));
  EXPECT_FALSE(ktx2::parse(nullptr, 0, &tex, &err));
}

namespace {
fs::path write_lock(const std::string& body, const char* name) {
  const auto p = file_util::get_jak_project_dir() / "test" / "test_data" / "recharged" / name;
  file_util::write_text_file(p, body);
  return p;
}
constexpr const char* kGoodLock = R"({
  "schema_version": 1,
  "asset_version": "assets-v0.1.1",
  "manifest_url": "https://github.com/moukrea/recharged-assets/releases/download/assets-v0.1.1/manifest.json",
  "manifest_sha256": "b371909044e02b270cc6720be26af8aa6bcd88ca9684988f2fa1db3bc0ddf528",
  "required": false
})";
}  // namespace

TEST(AssetsLock, ParsesValidLock) {
  const auto p = write_lock(kGoodLock, "lock_ok.tmp.json");
  std::string err;
  auto lock = assets_lock::load(p, &err);
  ASSERT_TRUE(lock.has_value()) << err;
  EXPECT_EQ(lock->asset_version, "assets-v0.1.1");
  EXPECT_EQ(lock->manifest_sha256.size(), 64u);
  EXPECT_FALSE(lock->required);
  EXPECT_TRUE(err.empty());
  fs::remove(p);
}

TEST(AssetsLock, AbsentFileIsDormantNotAnError) {
  std::string err = "sentinel";
  auto lock = assets_lock::load(
      file_util::get_jak_project_dir() / "test" / "test_data" / "recharged" / "nope.json", &err);
  EXPECT_FALSE(lock.has_value());
  EXPECT_TRUE(err.empty());
}

TEST(AssetsLock, RejectsBadSchemaHashAndLatest) {
  struct Case {
    const char* name;
    std::string body;
    const char* expect;
  };
  std::string latest = kGoodLock;
  latest.replace(latest.find("/download/assets-v0.1.1/"), std::strlen("/download/assets-v0.1.1/"),
                 "/latest/");
  std::string bad_hash = kGoodLock;
  bad_hash.replace(bad_hash.find("b371909044"), 10, "ZZZZZZZZZZ");
  std::string bad_schema = kGoodLock;
  bad_schema.replace(bad_schema.find("\"schema_version\": 1"), 19, "\"schema_version\": 9");

  const Case cases[] = {
      {"lock_latest.tmp.json", latest, "latest"},
      {"lock_hash.tmp.json", bad_hash, "hex"},
      {"lock_schema.tmp.json", bad_schema, "unsupported"},
      {"lock_trash.tmp.json", "{ not json", "parse"},
      {"lock_missing.tmp.json", "{\"schema_version\": 1}", "field"},
  };
  for (const auto& c : cases) {
    const auto p = write_lock(c.body, c.name);
    std::string err;
    EXPECT_FALSE(assets_lock::load(p, &err).has_value()) << c.name;
    EXPECT_NE(err.find(c.expect), std::string::npos) << c.name << ": " << err;
    fs::remove(p);
  }
}

TEST(Ktx2Subset, FormatTable) {
  EXPECT_TRUE(ktx2::is_supported_format(145));   // BC7
  EXPECT_TRUE(ktx2::is_supported_format(153));   // EAC R11
  EXPECT_FALSE(ktx2::is_supported_format(146));  // BC7_SRGB — not in subset
  EXPECT_EQ(ktx2::expected_level_size(145, 8, 8), 4u * 16u);
  EXPECT_EQ(ktx2::expected_level_size(153, 8, 8), 4u * 8u);
  EXPECT_EQ(ktx2::expected_level_size(165, 8, 8), 4u * 16u);   // ASTC 6x6: 2x2 blocks
  EXPECT_EQ(ktx2::expected_level_size(145, 1, 1), 16u);
  EXPECT_EQ(ktx2::expected_level_size(37, 8, 8), 8u * 8u * 4u);  // RGBA8
}
