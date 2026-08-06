#include "RPack.h"

#include <cstdio>
#include <cstring>

#include "fmt/core.h"
#include "third-party/json.hpp"

namespace rpack {

// ---------------------------------------------------------------------------
// Compact SHA-256 (FIPS 180-4), no dependency. Public-domain-style reference
// implementation; validated against the pipeline's Python hashes by the
// cross-language fixture test.
namespace {
struct Sha256 {
  u32 h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  u8 buf[64];
  u64 total = 0;
  size_t fill = 0;

  static u32 rotr(u32 x, int n) { return (x >> n) | (x << (32 - n)); }

  void block(const u8* p) {
    static const u32 K[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
    u32 w[64];
    for (int i = 0; i < 16; i++) {
      w[i] = (u32(p[i * 4]) << 24) | (u32(p[i * 4 + 1]) << 16) | (u32(p[i * 4 + 2]) << 8) |
             u32(p[i * 4 + 3]);
    }
    for (int i = 16; i < 64; i++) {
      const u32 s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      const u32 s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    u32 a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
      const u32 S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const u32 ch = (e & f) ^ (~e & g);
      const u32 t1 = hh + S1 + ch + K[i] + w[i];
      const u32 S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const u32 maj = (a & b) ^ (a & c) ^ (b & c);
      const u32 t2 = S0 + maj;
      hh = g, g = f, f = e, e = d + t1, d = c, c = b, b = a, a = t1 + t2;
    }
    h[0] += a, h[1] += b, h[2] += c, h[3] += d;
    h[4] += e, h[5] += f, h[6] += g, h[7] += hh;
  }

  void update(const u8* p, size_t n) {
    total += n;
    while (n) {
      const size_t take = std::min(n, sizeof(buf) - fill);
      memcpy(buf + fill, p, take);
      fill += take, p += take, n -= take;
      if (fill == sizeof(buf)) {
        block(buf);
        fill = 0;
      }
    }
  }

  std::string finish() {
    const u64 bits = total * 8;
    const u8 one = 0x80;
    update(&one, 1);
    const u8 zero = 0;
    while (fill != 56) {
      update(&zero, 1);
    }
    u8 len[8];
    for (int i = 0; i < 8; i++) {
      len[i] = u8(bits >> (56 - i * 8));
    }
    update(len, 8);
    std::string out;
    for (u32 v : h) {
      out += fmt::format("{:08x}", v);
    }
    return out;
  }
};

constexpr size_t kHeaderSize = 16;
constexpr size_t kTrailerSize = 24;
}  // namespace

std::string sha256_hex(const u8* data, size_t size) {
  Sha256 s;
  s.update(data, size);
  return s.finish();
}

Reader::Reader(const std::string& path) : m_path(path) {
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) {
    m_error = "rpack: cannot open " + path;
    return;
  }
  fseek(f, 0, SEEK_END);
  const long fsize = ftell(f);
  if (fsize < long(kHeaderSize + kTrailerSize)) {
    m_error = "rpack: file too small";
    fclose(f);
    return;
  }

  u8 header[kHeaderSize];
  fseek(f, 0, SEEK_SET);
  if (fread(header, 1, kHeaderSize, f) != kHeaderSize || memcmp(header, "RPK1", 4) != 0) {
    m_error = "rpack: bad header magic";
    fclose(f);
    return;
  }
  u32 schema, entry_count;
  memcpy(&schema, header + 4, 4);
  memcpy(&entry_count, header + 8, 4);
  if (schema != kSchemaVersion) {
    m_error = fmt::format("rpack: unsupported schema_version {}", schema);
    fclose(f);
    return;
  }

  u8 trailer[kTrailerSize];
  fseek(f, fsize - long(kTrailerSize), SEEK_SET);
  if (fread(trailer, 1, kTrailerSize, f) != kTrailerSize ||
      memcmp(trailer + 20, "RIDX", 4) != 0) {
    m_error = "rpack: bad trailer magic";
    fclose(f);
    return;
  }
  u64 index_offset, index_size;
  memcpy(&index_offset, trailer, 8);
  memcpy(&index_size, trailer + 8, 8);
  if (index_offset + index_size > u64(fsize) - kTrailerSize) {
    m_error = "rpack: index range out of bounds";
    fclose(f);
    return;
  }

  std::vector<u8> index_bytes(index_size);
  fseek(f, long(index_offset), SEEK_SET);
  if (fread(index_bytes.data(), 1, index_size, f) != index_size) {
    m_error = "rpack: short index read";
    fclose(f);
    return;
  }
  fclose(f);

  // integrity fast-check: first 4 bytes of the index sha256
  const std::string index_sha = sha256_hex(index_bytes.data(), index_bytes.size());
  for (int i = 0; i < 4; i++) {
    const u32 byte = std::stoul(index_sha.substr(i * 2, 2), nullptr, 16);
    if (u8(byte) != trailer[16 + i]) {
      m_error = "rpack: index integrity check failed";
      return;
    }
  }

  nlohmann::json idx;
  try {
    idx = nlohmann::json::parse(index_bytes.begin(), index_bytes.end());
  } catch (const std::exception& e) {
    m_error = fmt::format("rpack: index parse error: {}", e.what());
    return;
  }

  try {
    if (idx.at("schema_version").get<u32>() != kSchemaVersion) {
      m_error = "rpack: index schema_version mismatch";
      return;
    }
    m_game = idx.at("game").get<std::string>();
    m_profile = idx.at("profile").get<std::string>();
    m_preset = idx.at("preset").get<std::string>();
    m_group = idx.at("group").get<std::string>();
    m_cluster = idx.at("cluster").get<std::string>();
    const auto& ents = idx.at("entries");
    if (ents.size() != entry_count) {
      m_error = "rpack: header/index entry count mismatch";
      return;
    }
    m_entries.reserve(ents.size());
    for (const auto& e : ents) {
      Entry out;
      out.id = e.at("id").get<std::string>();
      out.key = e.at("key").get<std::string>();
      out.map = e.at("map").get<std::string>();
      out.format = e.at("format").get<std::string>();
      out.colorspace = e.at("colorspace").get<std::string>();
      out.alpha_mode = e.value("alpha_mode", "none");
      out.wrap_mode = e.value("wrap_mode", "repeat");
      out.channels = e.value("channels", "");
      out.width = e.at("width").get<u32>();
      out.height = e.at("height").get<u32>();
      out.mip_levels = e.at("mip_levels").get<u32>();
      out.offset = e.at("offset").get<u64>();
      out.size = e.at("size").get<u64>();
      out.sha256 = e.at("sha256").get<std::string>();
      if (out.offset % 16 != 0 || out.offset + out.size > index_offset) {
        m_error = fmt::format("rpack: entry {} payload out of bounds", out.key);
        return;
      }
      if (e.contains("stats")) {
        const auto& st = e["stats"];
        if (st.contains("normal_dc_x")) {
          out.stats.has_normal_dc = true;
          out.stats.normal_dc_x = st["normal_dc_x"].get<float>();
          out.stats.normal_dc_y = st.value("normal_dc_y", 0.f);
        }
        if (st.contains("height_mean")) {
          out.stats.has_height = true;
          out.stats.height_mean = st["height_mean"].get<float>();
          out.stats.height_norm = st.value("height_norm", 1.f);
          out.stats.height_lambda_tiles = st.value("height_lambda_tiles", 0.25f);
        }
      }
      m_by_key[{out.key, out.map}] = m_entries.size();
      m_entries.push_back(std::move(out));
    }
  } catch (const std::exception& e) {
    m_error = fmt::format("rpack: index field error: {}", e.what());
    return;
  }
  m_ok = true;
}

const Entry* Reader::find(const std::string& key, const std::string& map) const {
  const auto it = m_by_key.find({key, map});
  return it == m_by_key.end() ? nullptr : &m_entries[it->second];
}

std::optional<std::vector<u8>> Reader::read_payload(const Entry& entry, bool verify) const {
  FILE* f = fopen(m_path.c_str(), "rb");
  if (!f) {
    return std::nullopt;
  }
  std::vector<u8> data(entry.size);
  fseek(f, long(entry.offset), SEEK_SET);
  const size_t got = fread(data.data(), 1, entry.size, f);
  fclose(f);
  if (got != entry.size) {
    return std::nullopt;
  }
  if (verify && sha256_hex(data.data(), data.size()) != entry.sha256) {
    return std::nullopt;
  }
  return data;
}

}  // namespace rpack
