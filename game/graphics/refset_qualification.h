#pragma once

#include <algorithm>
#include <charconv>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

#include "third-party/json.hpp"

// Offline policy over engine-produced receipts. Hashes bind files to receipts;
// exact replay receipts and complete paired state bytes provide the independent check.
namespace refset_qualification {
using Json = nlohmann::json;
namespace fs = std::filesystem;
struct Expected {
  std::string key, vantage, level;
  int phase = 0, hour = 0;
};
struct Result {
  uint64_t gate = 254, replay_runs = 0;
  std::string status = "incomplete";
  std::vector<std::string> missing;
  uint64_t identity = 0;
};
namespace detail {
struct Invalid : std::runtime_error { using std::runtime_error::runtime_error; };
inline void require(bool ok, const std::string& reason) {
  if (!ok) throw Invalid(reason);
}
inline uint64_t number(const Json& j, const char* key, bool nonzero = true) {
  const auto& v = j.at(key);
  require(v.is_number_unsigned() || (v.is_number_integer() && v.get<int64_t>() >= 0),
          std::string("unsigned:") + key);
  const auto result = v.get<uint64_t>();
  require(!nonzero || result, std::string("zero:") + key);
  return result;
}
inline int64_t frame(const Json& j, const char* key) {
  const auto v = number(j, key, false);
  require(v <= uint64_t(std::numeric_limits<int64_t>::max()), "frame-range");
  return int64_t(v);
}
inline bool safe_key(const std::string& key) {
  const fs::path path(key);
  if (key.empty() || path.is_absolute() || path.extension() != ".png" ||
      key.find('\\') != std::string::npos) return false;
  for (const auto& part : path) if (part == "." || part == ".." || part.empty()) return false;
  return path.generic_string() == key;
}
inline std::string read(const fs::path& path, size_t limit = 8 * 1024 * 1024) {
  std::error_code ec;
  const auto size = fs::file_size(path, ec);
  require(!ec && size <= limit, "file-size:" + path.string());
  std::ifstream in(path, std::ios::binary);
  require(bool(in), "file-read:" + path.string());
  std::string bytes(size, '\0');
  if (size) in.read(bytes.data(), std::streamsize(size));
  require(bool(in), "file-read:" + path.string());
  return bytes;
}
inline Json json(const fs::path& path) {
  return Json::parse(read(path));
}
inline std::string case_name(std::string key) {
  if (key.compare(0, 14, "supplement-v1/") == 0) key.erase(0, 14);
  key.resize(key.size() - 4);
  return key;
}
inline uint64_t parse_number(const std::string& value, int base) {
  uint64_t number = 0;
  const auto parsed = std::from_chars(value.data(), value.data() + value.size(), number, base);
  require(!value.empty() && parsed.ec == std::errc{} && parsed.ptr == value.data() + value.size(),
          "sidecar-number");
  return number;
}
inline std::string sidecar(const fs::path& path, const Json& capture, const Json& item) {
  std::map<std::string, std::string> fields;
  const auto bytes = read(path, 16384);
  size_t begin = 0;
  while (begin < bytes.size()) {
    const auto end = bytes.find('\n', begin);
    require(end != std::string::npos, "sidecar-newline");
    const auto line = bytes.substr(begin, end - begin);
    const auto equal = line.find('=');
    require(equal != std::string::npos &&
                fields.emplace(line.substr(0, equal), line.substr(equal + 1)).second,
            "sidecar-fields");
    begin = end + 1;
  }
  require(fields.size() == 9 && fields.at("version") == "2" &&
              fields.at("case") == case_name(item.at("key").get<std::string>()) &&
              (fields.at("flavour") == "normal" || fields.at("flavour") == "ablate"),
          "sidecar-metadata");
  for (const char* key : {"config", "bin", "data", "input", "png"}) {
    const auto& value = fields.at(key);
    require(value.size() == 16 && parse_number(value, 16) ==
                number(std::string(key) == "png" ? item : capture, key), "sidecar-hash");
  }
  require(parse_number(fields.at("capture_lf"), 10) == uint64_t(frame(item, "lf")),
          "sidecar-lf");
  return fields.at("flavour");
}
inline uint64_t permille(uint64_t bg, uint64_t px) {
  require(px && px <= 1000000000 && bg <= px, "pixel-count-range");
  return bg * 1000 / px;
}
inline std::set<std::string> assets(const fs::path& path) {
  const auto bytes = read(path, 16 * 1024 * 1024);
  require(bytes.compare(0, 10, "version=1\n") == 0, "assets-version");
  const auto hex = [](const std::string& value) {
    return !value.empty() && value.size() % 2 == 0 &&
        value.find_first_not_of("0123456789abcdef") == std::string::npos;
  };
  std::set<std::string> records;
  size_t begin = 10, checkpoints = 0;
  while (begin < bytes.size()) {
    const auto end = bytes.find('\n', begin);
    require(end != std::string::npos, "assets-newline");
    const auto line = bytes.substr(begin, end - begin);
    std::vector<std::string> fields;
    size_t field_begin = 0;
    for (;;) {
      const auto tab = line.find('\t', field_begin);
      fields.push_back(line.substr(field_begin, tab == std::string::npos ? tab : tab - field_begin));
      if (tab == std::string::npos) break;
      field_begin = tab + 1;
    }
    if (fields.at(0) == "asset") {
      require(fields.size() == 6 && !fields[1].empty() &&
                  fields[1].find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-") == std::string::npos &&
                  hex(fields[2]) && fields[5].size() == 64 && hex(fields[5]) &&
                  records.insert(line).second, "assets-record");
      parse_number(fields[3], 10); parse_number(fields[4], 10);
    } else {
      require(fields.size() == 4 && fields[0] == "checkpoint" && hex(fields[1]) &&
                  parse_number(fields[2], 10) == records.size() &&
                  fields[3].size() == 64 && hex(fields[3]), "assets-checkpoint");
      ++checkpoints;
    }
    begin = end + 1;
  }
  require(!records.empty() && checkpoints, "assets-empty");
  return records;
}
struct Root {
  fs::path path;
  Json capture;
  std::map<std::string, Json> cases;
  std::set<std::string> assets;
  size_t runs = 0;
};
}  // namespace detail

template <typename Hash, typename Compare>
Result evaluate(const fs::path& manifest_path, uint64_t current_bin, uint64_t current_data,
                Hash hash, Compare compare,
                const std::vector<Expected>& expected_cases) {
  (void)compare;  // ON/OFF images are intentionally never compared.
  Result result;
  uint64_t identity = UINT64_C(14695981039346656037);
  const auto missing = [&](const std::string& reason) { result.missing.push_back(reason); };
  const auto mix = [&](const std::string& value) {
    for (unsigned char c : value) identity = (identity ^ c) * UINT64_C(1099511628211);
    identity = (identity ^ 0xff) * UINT64_C(1099511628211);
  };
  const auto checked_hash = [&](const fs::path& path) {
    const uint64_t fp = hash(path.string());
    detail::require(fp != 0, "hash:" + path.string());
    mix(path.string()); mix(std::to_string(fp));
    return fp;
  };
  const auto check_assets = [&](const Json& receipt) {
    const fs::path path(receipt.at("assets_path").get<std::string>());
    detail::require(path.is_absolute() && checked_hash(path) == detail::number(receipt, "assets_fp"),
                    "assets-stale");
    return detail::assets(path);
  };
  try {
    using detail::require;
    using detail::number;
    using detail::frame;
    if (!fs::exists(manifest_path)) {
      missing("manifest:" + manifest_path.string());
      return result;
    }
    require(current_bin != 0 && current_data != 0 && expected_cases.size() <= 8192, "qualification-input");
    checked_hash(manifest_path);
    const Json manifest = detail::json(manifest_path);
    require(number(manifest, "version") == 2 && manifest.at("roots").is_array() &&
                manifest.at("roots").size() <= 256, "manifest-schema");
    std::map<std::string, Expected> expected;
    for (const auto& item : expected_cases) {
      require((item.phase == 2 || item.phase == 3) && detail::safe_key(item.key) &&
                  expected.emplace(item.key, item).second,
              "expected-key:" + item.key);
    }
    if (expected.empty()) missing("expected-universe-empty");
    std::map<std::string, detail::Root> roots;
    std::set<std::string> unavailable;
    std::set<std::string> executions;
    std::map<std::string, int> observed_sky;
    size_t receipt_count = 0;
    const auto load_root = [&](const fs::path& raw) -> detail::Root* {
      require(raw.is_absolute(), "root-not-absolute");
      if (!fs::is_directory(raw)) { missing("root:" + raw.string()); return nullptr; }
      const auto path = fs::canonical(raw);
      if (unavailable.count(path.string())) return nullptr;
      const auto cached = roots.find(path.string());
      if (cached != roots.end()) {
        return &cached->second;
      }
      const auto capture_path = path / "qualification-capture.json";
      if (!fs::exists(capture_path)) { missing("capture:" + path.string()); return nullptr; }
      require(detail::read(path / "refset-format.txt", 64) == "version=2\n", "root-format");
      checked_hash(path / "refset-format.txt");
      const uint64_t capture_fp = checked_hash(capture_path);
      Json capture = detail::json(capture_path);
      require(number(capture, "version") == 1 && capture.at("kind") == "capture" &&
                  capture.at("clean") == true && capture.at("reconstructed") == true &&
                  capture.at("calibrated") == false, "capture-status");
      const auto capture_assets = check_assets(capture);
      for (const char* key : {"bin", "data", "input", "settings", "config", "bootstrap", "source_fp"})
        number(capture, key);
      require(number(capture, "bin") == current_bin, "capture-bin");
      require(number(capture, "data") == current_data, "capture-data");
      const auto execution = capture.at("execution").get<std::string>();
      require(!execution.empty() && executions.insert(execution).second, "duplicate-execution");
      const fs::path source_path(capture.at("source_path").get<std::string>());
      require(source_path.is_absolute(), "source-not-absolute");
      if (!fs::exists(source_path)) {
        missing("source:" + source_path.string()); unavailable.insert(path.string()); return nullptr;
      }
      require(checked_hash(source_path) == number(capture, "source_fp"), "source-stale");
      const Json source = detail::json(source_path);
      require(number(source, "version") == 1 && number(source, "bin") == number(capture, "bin") &&
                  source.at("role") == "candidate", "source-schema");
      const fs::path binary(source.at("binary_path").get<std::string>());
      require(binary.is_absolute() && checked_hash(binary) == number(capture, "bin"), "binary-stale");
      require(source.at("files").is_object() && !source.at("files").empty() &&
                  source.at("files").size() <= 32768, "source-files");
      for (const auto& entry : source.at("files").items()) {
        require(fs::path(entry.key()).is_absolute(), "source-file-not-absolute");
        Json value = {{"fp", entry.value()}};
        require(checked_hash(entry.key()) == number(value, "fp"), "source-file-stale:" + entry.key());
      }
      detail::Root root{path, capture, {}, capture_assets, 0};
      require(capture.at("cases").is_array() && !capture.at("cases").empty() &&
                  capture.at("cases").size() <= 8192, "capture-cases");
      for (const auto& item : capture.at("cases")) {
        const auto key = item.at("key").get<std::string>();
        require(detail::safe_key(key) && root.cases.emplace(key, item).second, "case-key:" + key);
        const auto descriptor = expected.find(key);
        require(descriptor != expected.end() && item.at("vantage") == descriptor->second.vantage &&
                    item.at("level") == descriptor->second.level &&
                    item.at("phase") == descriptor->second.phase &&
                    item.at("hour") == descriptor->second.hour, "case-descriptor:" + key);
        const auto px = number(item, "px", false), bg = number(item, "bg", false);
        require(bg <= px && item.at("level_ok").is_boolean() &&
                    item.at("has_sky").is_number_integer() &&
                    item.at("has_sky") >= -1 && item.at("has_sky") <= 1, "case-coverage:" + key);
        if (!px || item.at("level_ok") != true || item.at("has_sky") == -1)
          missing("coverage:" + path.string() + ":" + key);
        if (item.at("has_sky") != -1) {
          const int classification = item.at("has_sky").get<int>();
          const auto observed = observed_sky.emplace(descriptor->second.level, classification);
          require(observed.second || observed.first->second == classification,
                  "sky-inconsistent:" + descriptor->second.level);
        }
        require(frame(item, "state_lf") <= frame(item, "lf") &&
                    frame(item, "lf") - frame(item, "state_lf") <= 1, "state-lag:" + key);
        require(number(item, "maxdiff", false) == 0 && number(item, "diffpx", false) == 0,
                "capture-diff:" + key);
        for (const auto& file : {std::make_pair("png", ""),
                                std::make_pair("sidecar", ".provenance.txt"),
                                std::make_pair("state", ".state.bin")}) {
          const auto local = path / (key + file.second);
          const auto relative = fs::canonical(local).lexically_relative(path);
          require(!relative.empty() && *relative.begin() != ".." &&
                      checked_hash(local) == number(item, file.first), "case-file-stale:" + key);
        }
        require(!detail::read(path / (key + ".state.bin"), 16 * 1024 * 1024).empty(), "state-empty");
        const auto flavour = detail::sidecar(path / (key + ".provenance.txt"), capture, item);
        const auto phase = item.at("phase").get<int>();
        require(phase == 2 || phase == 3, "case-phase");
        const auto& options = item.at("effective_options");
        require(options.is_object() && options.size() == 5 &&
                    options.at("master").is_boolean() && options.at("master") == true &&
                    options.at("lighting").is_boolean() && options.at("lighting") == (phase == 2) &&
                    options.at("rt_light").is_boolean() && options.at("rt_light") == (phase == 2) &&
                    options.at("hdr").is_boolean() && options.at("hdr") == (phase == 2) &&
                    options.at("others").is_object(), "case-effective-options:" + key);
        const auto prefix = key.compare(0, 14, "supplement-v1/") == 0 ? "supplement-v1/" : "";
        const auto witness = path / prefix /
            (phase == 2 ? "recharged" : "origine-lumiere") / "captured-by.txt";
        checked_hash(witness);
        const auto witness_bytes = detail::read(witness, 128);
        require(witness_bytes.size() == 16 + 1 + 8 + flavour.size() + 1 &&
                    witness_bytes.substr(16) == "\nflavour=" + flavour + "\n" &&
                    detail::parse_number(witness_bytes.substr(0, 16), 16) == number(capture, "bin"),
                "capture-witness");
      }
      const auto replay_dir = path / "qualification-replays";
      if (fs::is_directory(replay_dir)) {
        std::vector<fs::path> receipts;
        for (const auto& entry : fs::directory_iterator(replay_dir)) {
          if (entry.path().extension() == ".json") receipts.push_back(entry.path());
        }
        std::sort(receipts.begin(), receipts.end());
        for (const auto& receipt : receipts) {
          require(++receipt_count <= 4096, "too-many-receipts");
          checked_hash(receipt);
          const Json replay = detail::json(receipt);
          require(check_assets(replay) == capture_assets, "replay-assets");
          require(number(replay, "version") == 1 && replay.at("kind") == "replay" &&
                      number(replay, "capture_fp") == capture_fp, "replay-capture");
          for (const char* key : {"bin", "data", "input", "settings", "config", "bootstrap", "source_fp",
                                  "source_path", "clean", "reconstructed", "calibrated"})
            require(replay.at(key) == capture.at(key), std::string("replay-identity:") + key);
          const auto run = replay.at("execution").get<std::string>();
          require(!run.empty() && executions.insert(run).second, "duplicate-execution");
          require(replay.at("cases").is_array() && replay.at("cases").size() == root.cases.size(),
                  "replay-cases");
          std::set<std::string> seen;
          for (const auto& item : replay.at("cases")) {
            const auto key = item.at("key").get<std::string>();
            require(seen.insert(key).second && root.cases.count(key) && item == root.cases.at(key) &&
                        number(item, "maxdiff", false) == 0 && number(item, "diffpx", false) == 0,
                    "replay-case:" + key);
          }
          ++root.runs;
        }
      }
      if (root.runs < 1) missing("replays:" + path.string() + ":" + std::to_string(root.runs) + "/1");
      return &roots.emplace(path.string(), std::move(root)).first->second;
    };
    std::map<std::string, Json> candidates;
    std::map<std::string, detail::Root*> case_roots;
    std::map<std::pair<std::string, int>, std::map<int, std::string>> pairs;
    for (const auto& root_path : manifest.at("roots")) {
      detail::Root* root = load_root(fs::path(root_path.get<std::string>()));
      if (!root) continue;
      for (const auto& entry : root->cases) {
        const auto& key = entry.first;
        const auto& item = entry.second;
        require(candidates.emplace(key, item).second, "duplicate-candidate:" + key);
        case_roots.emplace(key, root);
        auto& pair = pairs[{item.at("vantage").get<std::string>(), item.at("hour").get<int>()}];
        require(pair.emplace(item.at("phase").get<int>(), key).second, "duplicate-arm:" + key);
      }
    }
    for (const auto& entry : pairs) {
      const auto& pair = entry.second;
      if (pair.size() != 2) {
        missing("paired-arm:" + entry.first.first + ":hour=" + std::to_string(entry.first.second));
        continue;
      }
      const auto& on_key = pair.at(2);
      const auto& off_key = pair.at(3);
      const auto& on = candidates.at(on_key);
      const auto& off = candidates.at(off_key);
      const auto* on_root = case_roots.at(on_key);
      const auto* off_root = case_roots.at(off_key);
      require(on_root->assets == off_root->assets, "pair-assets");
      for (const char* field : {"bin", "data", "input", "settings", "bootstrap", "source_fp"})
        require(on_root->capture.at(field) == off_root->capture.at(field),
                std::string("pair-identity:") + field);
      for (const char* field : {"vantage", "level", "hour", "lf", "state_lf"})
        require(on.at(field) == off.at(field), "pair-case-identity:" + on_key);
      require(on.at("effective_options").at("others") == off.at("effective_options").at("others"),
              "pair-effective-options:" + on_key);
      require(detail::read(on_root->path / (on_key + ".state.bin"), 16 * 1024 * 1024) ==
                  detail::read(off_root->path / (off_key + ".state.bin"), 16 * 1024 * 1024),
              "pair-state-diff:" + on_key);
    }
    std::set<std::string> levels, interior;
    std::map<std::string, int> sky;
    std::map<std::string, std::set<std::pair<int, int>>> sky_slots;
    std::map<std::string, std::pair<size_t, bool>> vantages;
    std::set<std::pair<int, int>> slots;
    for (const auto& entry : expected) {
      const auto& e = entry.second;
      slots.emplace(e.phase, e.hour);
      if (!candidates.count(entry.first)) missing("case:" + entry.first);
    }
    for (const auto& entry : candidates) {
      const auto& item = entry.second;
      const auto level = item.at("level").get<std::string>();
      const auto vantage = item.at("vantage").get<std::string>();
      const auto bg = number(item, "bg", false), px = number(item, "px", false);
      require(bg <= px && item.at("has_sky").is_number_integer(), "coverage-metadata:" + entry.first);
      const int has_sky = item.at("has_sky").get<int>();
      require(has_sky >= -1 && has_sky <= 1, "sky-classification:" + level);
      if (!item.at("level_ok").is_boolean() || item.at("level_ok") != true || !px || has_sky < 0) {
        missing("coverage:" + entry.first); continue;
      }
      const auto classification = sky.emplace(level, has_sky);
      require(classification.second || classification.first->second == has_sky, "sky-inconsistent:" + level);
      levels.insert(level);
      auto inserted = vantages.emplace(vantage, std::make_pair(size_t(0), true));
      auto& view = inserted.first->second;
      ++view.first;
      const auto pm = detail::permille(bg, px);
      view.second = view.second && pm <= 10;
      if (has_sky && pm >= 150 && pm <= 900)
        sky_slots[level].emplace(item.at("phase").get<int>(), item.at("hour").get<int>());
    }
    if (levels.size() < 21) missing("levels:" + std::to_string(levels.size()) + "/21");
    for (const auto& view : vantages)
      if (view.second.first >= 16 && view.second.second) interior.insert(view.first);
    if (interior.size() < 4) missing("interior-vantages:" + std::to_string(interior.size()) + "/4");
    for (const auto& level : sky) if (level.second == 1) for (const auto& slot : slots) {
      if (!sky_slots[level.first].count(slot))
        missing("sky:" + level.first + ":phase=" + std::to_string(slot.first) + ":hour=" + std::to_string(slot.second));
    }
    result.replay_runs = roots.empty() ? 0 : std::numeric_limits<uint64_t>::max();
    for (const auto& root : roots) result.replay_runs = std::min<uint64_t>(result.replay_runs, root.second.runs);
    result.identity = identity;
    if (result.missing.empty()) { result.gate = 0; result.status = "qualified"; }
  } catch (const std::exception& error) {
    result.gate = 255;
    result.status = "invalid";
    result.missing.push_back(error.what());
    result.identity = identity;
  }
  return result;
}
}  // namespace refset_qualification
