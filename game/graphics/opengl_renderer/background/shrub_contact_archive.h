#pragma once
// Standalone binary archive codec; deliberately independent of GL and engine types.
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <map>
#include <string>
#include <unistd.h>
#include <vector>

namespace shrub_contact_archive {
using Bytes = std::vector<uint8_t>;
constexpr size_t max_record = 32 * 1024 * 1024;
constexpr size_t max_frame = 128 * 1024 * 1024;
constexpr uint64_t max_run = 1024ull * 1024 * 1024;
// Prepared replay window: before, during and after the 130-tick walking segment.
struct CaptureWindow {
  static constexpr int64_t first = 120, last = 600, stride = 60;
  static constexpr uint64_t expected = 9, full_mask = (1u << expected) - 1;
  uint64_t observed = 0;
  bool passed = false;
  static bool planned(int64_t frame) {
    return frame >= first && frame <= last && (frame - first) % stride == 0;
  }
  bool contains(int64_t frame) const {
    return planned(frame) && (observed & (uint64_t(1) << ((frame - first) / stride)));
  }
  bool close(int64_t frame) {
    if (!planned(frame) || contains(frame))
      return false;
    observed |= uint64_t(1) << ((frame - first) / stride);
    return true;
  }
  uint64_t count() const {
    uint64_t bits = observed, n = 0;
    while (bits) {
      n += bits & 1;
      bits >>= 1;
    }
    return n;
  }
  void tick(int64_t frame) { passed |= frame > last; }
  bool complete() const { return passed && observed == full_mask; }
};

inline void number(Bytes& b, uint64_t n) {
  for (int i = 0; i < 8; ++i)
    b.push_back(n >> (8 * i));
}
inline void append(Bytes& b, const void* p, size_t n) {
  if (n) {
    const auto* q = static_cast<const uint8_t*>(p);
    b.insert(b.end(), q, q + n);
  }
}
inline void field(Bytes& b, const void* p, size_t n) {
  number(b, n);
  append(b, p, n);
}
inline void field(Bytes& b, const std::string& s) {
  field(b, s.data(), s.size());
}
inline uint64_t hash(const Bytes& b) {
  uint64_t h = 14695981039346656037ull;
  for (auto c : b) {
    h ^= c;
    h *= 1099511628211ull;
  }
  return h;
}
struct Record {
  Bytes inputs, pre, post;
  uint8_t mapped =
      0;  // 0 common, 1 contact (OFF strict), 2 new attachment (OFF zero), 3 observation
};
using Records = std::map<std::string, Record>;
struct Reader {
  const Bytes& b;
  size_t pos = 0;
  bool ok = true;
  uint64_t number() {
    if (b.size() - pos < 8) {
      ok = false;
      return 0;
    }
    uint64_t n = 0;
    for (int i = 0; i < 8; ++i)
      n |= uint64_t(b[pos++]) << (8 * i);
    return n;
  }
  Bytes field() {
    uint64_t n = number();
    if (!ok || n > max_frame || n > b.size() - pos) {
      ok = false;
      return {};
    }
    Bytes out(b.begin() + pos, b.begin() + pos + n);
    pos += n;
    return out;
  }
};
// Decode semantic identity; mappings are derived from names, never trusted from reference bytes.
inline bool identity(const std::string& key, std::string& domain, std::string& name, int64_t& geo) {
  Bytes bytes(key.begin(), key.end());
  Reader r{bytes};
  auto d = r.field();
  r.field();
  geo = static_cast<int64_t>(r.number());
  r.number();
  auto n = r.field();
  r.number();
  domain.assign(d.begin(), d.end());
  name.assign(n.begin(), n.end());
  return r.ok && r.pos == bytes.size();
}
inline int mapping(const std::string& key) {
  std::string domain, name;
  int64_t geo;
  if (!identity(key, domain, name, geo) ||
      (domain != "shrub" && domain != "tie" && domain != "grass"))
    return -1;
  if (domain == "grass" &&
      (name == "attribute-0" || name == "attribute-light" || name.compare(0, 8, "uniform-") == 0))
    return 0;
  if (name == "capture" || name == "native-row0")
    return 0;
  if (name == "contact-anchor")
    return 1;
  if (name == "contact-attachment")
    return 2;
  if (name.compare(0, 10, "attribute-") == 0) {
    const auto a = name.substr(10);
    if (a == "0" || a == "7" || a == "8" || (a == "9" && domain == "shrub"))
      return 0;
    if (a == "10" && domain == "tie")
      return 1;
    return 3;
  }
  if (name.compare(0, 8, "uniform-") == 0) {
    const auto u = name.substr(8);
    if (u == "u_shrub_contact_on" || u == "u_tie_contact_on")
      return 1;
    if (u.find("u_tie_sway_") == 0 || u == "u_shrub_native_on" || u.find("u_jak_") == 0 ||
        u.find("u_trample") == 0)
      return 0;
    return 3;
  }
  return -1;
}
inline bool valid_mappings(const Records& records) {
  for (const auto& [key, r] : records)
    if (mapping(key) != r.mapped)
      return false;
  return true;
}
inline Bytes encode(int64_t frame, const Records& records) {
  Bytes b;
  number(b, 0x3141524847534f);
  number(b, frame);
  number(b, records.size());
  for (const auto& [key, r] : records) {
    field(b, key);
    number(b, r.mapped);
    field(b, r.inputs.data(), r.inputs.size());
    field(b, r.pre.data(), r.pre.size());
    field(b, r.post.data(), r.post.size());
  }
  number(b, hash(b));
  return b;
}
inline bool decode(const Bytes& b, int64_t frame, Records& records) {
  records.clear();
  if (b.size() < 32 || b.size() > max_frame)
    return false;
  Reader rd{b};
  if (rd.number() != 0x3141524847534f || rd.number() != uint64_t(frame))
    return false;
  uint64_t n = rd.number();
  if (!n || n > 100000)
    return false;
  for (uint64_t i = 0; i < n && rd.ok; ++i) {
    auto k = rd.field();
    auto mapped = rd.number();
    Record r;
    r.mapped = mapped;
    r.inputs = rd.field();
    r.pre = rd.field();
    r.post = rd.field();
    if (mapped > 3 || !rd.ok ||
        !records.emplace(std::string(k.begin(), k.end()), std::move(r)).second)
      return false;
  }
  size_t end = rd.pos;
  uint64_t checksum = rd.number();
  return rd.ok && rd.pos == b.size() && checksum == hash(Bytes(b.begin(), b.begin() + end));
}
inline bool read(const std::string& path, int64_t frame, Records& records) {
  std::ifstream in(path, std::ios::binary | std::ios::ate);
  if (!in)
    return false;
  auto size = in.tellg();
  if (size < 0 || uint64_t(size) > max_frame)
    return false;
  Bytes b(static_cast<size_t>(size));
  in.seekg(0);
  in.read(reinterpret_cast<char*>(b.data()), b.size());
  return bool(in) && decode(b, frame, records);
}
inline bool write(const std::string& path, const Bytes& b) {
  if (b.size() > max_frame)
    return false;
  const std::string tmp = path + ".partial";
  int fd = ::open(tmp.c_str(), O_CREAT | O_EXCL | O_WRONLY, 0600);
  if (fd < 0)
    return false;
  size_t pos = 0;
  bool ok = true;
  while (pos < b.size()) {
    ssize_t n = ::write(fd, b.data() + pos, b.size() - pos);
    if (n <= 0) {
      ok = false;
      break;
    }
    pos += n;
  }
  ok = (::fsync(fd) == 0) && ok;
  ok = (::close(fd) == 0) && ok;
  // link is atomic and refuses to overwrite a prior run, unlike rename.
  if (ok)
    ok = ::link(tmp.c_str(), path.c_str()) == 0;
  ::unlink(tmp.c_str());
  if (ok) {
    int dir = ::open(std::filesystem::path(path).parent_path().c_str(), O_RDONLY | O_DIRECTORY);
    if (dir < 0)
      return false;
    ok = ::fsync(dir) == 0;
    ::close(dir);
  }
  return ok;
}
struct Comparison {
  uint64_t missing = 0, inputs = 0, pre = 0, post = 0, populations = 0;
};
inline Comparison compare(const Records& current, const Records& reference, bool off) {
  Comparison c;
  for (const auto& [key, a] : current) {
    if (a.mapped == 3 || (a.mapped == 1 && !off))
      continue;
    if (a.mapped == 2) {
      if (off)
        for (auto v : a.inputs)
          if (v) {
            ++c.inputs;
            break;
          }
      continue;
    }
    auto it = reference.find(key);
    if (it == reference.end() || it->second.mapped != a.mapped) {
      ++c.missing;
      continue;
    }
    const auto& b = it->second;
    c.inputs += a.inputs != b.inputs;
    c.pre += a.pre != b.pre;
    if (off)
      c.post += a.post != b.post;
    if (!a.pre.empty() && !b.pre.empty())
      ++c.populations;
  }
  for (const auto& [key, b] : reference)
    if ((b.mapped == 0 || (off && b.mapped == 1)) && !current.count(key))
      ++c.missing;
  if (!c.populations)
    ++c.missing;
  return c;
}
}  // namespace shrub_contact_archive
