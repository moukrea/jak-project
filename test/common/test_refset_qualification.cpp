// Standalone: c++ -std=c++17 -Wall -Wextra -Werror -I. this-file.cpp -o /tmp/test-qualification
#include "game/graphics/refset_qualification.h"

#include <cassert>
#include <cstdio>
#include <iterator>
#include <unistd.h>

namespace {
using namespace refset_qualification;
uint64_t hash_file(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return 0;
  uint64_t hash = UINT64_C(14695981039346656037);
  char byte;
  while (in.get(byte)) hash = (hash ^ uint8_t(byte)) * UINT64_C(1099511628211);
  return in.eof() ? hash : 0;
}
void write(const fs::path& path, const std::string& bytes) {
  fs::create_directories(path.parent_path());
  std::ofstream out(path, std::ios::binary);
  out << bytes;
  out.close();
  assert(out);
}
std::string hex(uint64_t n) {
  char text[17];
  std::snprintf(text, sizeof(text), "%016llx", static_cast<unsigned long long>(n));
  return text;
}
struct Fixture {
  fs::path root, candidate, manifest;
  std::vector<Expected> expected;
  uint64_t current_bin;
  uint64_t current_data = 11;
  explicit Fixture(const fs::path& dir) : root(dir), candidate(dir / "candidate"), manifest(dir / "manifest.json") {
    for (int view = 0; view < 28; ++view) {
      const auto vantage = "view" + std::to_string(view);
      const auto level = "level" + std::to_string(view < 21 ? view : view - 17);
      for (int phase = 2; phase <= 3; ++phase) for (int hour = 0; hour < 24; hour += 3) {
        const auto key = (view >= 26 ? "supplement-v1/" : "") + vantage + "/p" +
                         std::to_string(phase) + "-h" + std::to_string(hour) + ".png";
        expected.push_back({key, vantage, level, phase, hour});
      }
    }
    make_capture(candidate);
    current_bin = detail::json(candidate / "qualification-capture.json").at("bin").get<uint64_t>();
    write(manifest, Json({{"version", 2}, {"roots", {candidate.string()}}}).dump());
  }
  void make_capture(const fs::path& path) {
    write(path / "binary", "candidate-binary");
    write(path / "renderer.cpp", "candidate-renderer");
    const uint64_t bin = hash_file((path / "binary").string());
    Json source = {{"version", 1}, {"bin", bin}, {"role", "candidate"},
                   {"binary_path", (path / "binary").string()},
                   {"files", {{(path / "renderer.cpp").string(), hash_file((path / "renderer.cpp").string())}}}};
    write(path / "source.json", source.dump());
    // SHA256 fixture: empty asset payload and a structurally valid checkpoint.
    write(path / "assets.tsv", "version=1\nasset\ttest\t61\t0\t0\t"
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n"
          "checkpoint\t61\t1\t"
          "c6ae71da4542799231ae28578897dc6eedb1b2371f328550b31aa1f119e4a93f\n");
    Json capture = {{"version", 1}, {"kind", "capture"}, {"execution", path.string() + "-capture"},
                    {"bin", bin}, {"data", uint64_t(11)}, {"input", uint64_t(12)},
                    {"settings", uint64_t(13)}, {"config", uint64_t(15)},
                    {"bootstrap", uint64_t(16)}, {"source_path", (path / "source.json").string()},
                    {"source_fp", hash_file((path / "source.json").string())}, {"clean", true},
                    {"reconstructed", true}, {"calibrated", false},
                    {"assets_path", (path / "assets.tsv").string()},
                    {"assets_fp", hash_file((path / "assets.tsv").string())}, {"cases", Json::array()}};
    for (const auto& e : expected) {
      const auto png = path / e.key;
      write(png, "decoded-RGB-fixture:" + e.key);
      write(png.string() + ".state.bin", "state-v1:" + e.vantage + ":" + std::to_string(e.hour));
      write(png.string() + ".provenance.txt",
            "version=2\ncase=" + detail::case_name(e.key) + "\nconfig=" +
            hex(capture["config"].get<uint64_t>()) + "\nbin=" + hex(bin) +
            "\nflavour=normal\npng=" + hex(hash_file(png.string())) +
            "\ncapture_lf=100\ndata=" + hex(11) + "\ninput=" + hex(12) + "\n");
      const int level = std::stoi(e.level.substr(5));
      capture["cases"].push_back({{"key", e.key}, {"vantage", e.vantage}, {"level", e.level},
          {"phase", e.phase}, {"hour", e.hour}, {"lf", 100}, {"state_lf", 99},
          {"png", hash_file(png.string())}, {"sidecar", hash_file(png.string() + ".provenance.txt")},
          {"state", hash_file(png.string() + ".state.bin")}, {"bg", level < 4 ? 1 : 200},
          {"px", 1000}, {"level_ok", true}, {"has_sky", level < 4 ? 0 : 1},
          {"maxdiff", 0}, {"diffpx", 0},
          {"effective_options", {{"master", true}, {"lighting", e.phase == 2},
                                  {"rt_light", e.phase == 2}, {"hdr", e.phase == 2}, {"others", {{"grass", true}}}}}});
    }
    for (const char* prefix : {"", "supplement-v1"})
      for (const char* set : {"origine", "recharged", "origine-lumiere"})
        write(path / prefix / set / "captured-by.txt", hex(bin) + "\nflavour=normal\n");
    write(path / "refset-format.txt", "version=2\n");
    write(path / "qualification-capture.json", capture.dump());
    replays(path);
  }
  void replays(const fs::path& path) {
    const auto capture_path = path / "qualification-capture.json";
    const auto capture = detail::json(capture_path);
    for (int run = 0; run < 1; ++run) {
      Json replay = capture;
      replay["kind"] = "replay";
      replay["execution"] = path.string() + "-replay-" + std::to_string(run);
      replay["capture_fp"] = hash_file(capture_path.string());
      write(path / "qualification-replays" / (std::to_string(run) + ".json"), replay.dump());
    }
  }
  template <typename F> void capture_mutation(F action, uint64_t gate) {
    const auto path = candidate / "qualification-capture.json";
    const auto before = detail::read(path);
    auto capture = Json::parse(before);
    action(capture);
    write(path, capture.dump()); replays(candidate);
    const auto result = evaluate();
    if (result.gate != gate)
      for (const auto& why : result.missing) std::fprintf(stderr, "%s\n", why.c_str());
    assert(result.gate == gate);
    write(path, before); replays(candidate);
  }
  Result evaluate() {
    return refset_qualification::evaluate(manifest, current_bin, current_data, hash_file,
        [](const std::string&, const std::string&) { assert(false && "ON/OFF image comparison forbidden"); return false; }, expected);
  }
  template <typename F> void mutation(const fs::path& path, F action, uint64_t gate) {
    const auto before = detail::read(path);
    action();
    const auto result = evaluate();
    if (result.gate != gate) {
      std::fprintf(stderr, "expected gate=%llu actual=%llu status=%s\n", (unsigned long long)gate,
                   (unsigned long long)result.gate, result.status.c_str());
      for (const auto& failure : result.missing) std::fprintf(stderr, "%s\n", failure.c_str());
    }
    assert(result.gate == gate);
    write(path, before);
  }
};
}  // namespace

int main() {
  char temp[] = "/tmp/refset-qualification-test-XXXXXX";
  assert(mkdtemp(temp));
  Fixture f(fs::canonical(temp));
  for (uint64_t pm : {149, 150, 900, 901}) assert(detail::permille(pm, 1000) == pm);
  assert(detail::permille(109, 10000) == 10);
  const auto valid = f.evaluate();
  if (valid.gate) for (const auto& why : valid.missing) std::fprintf(stderr, "%s\n", why.c_str());
  assert(valid.gate == 0 && valid.replay_runs == 1 && valid.identity != 0);
  // Intact dataset-A receipts must not qualify a run over dataset B.
  f.current_data = 22;
  assert(f.evaluate().gate == 255);
  f.current_data = 0;
  assert(f.evaluate().gate == 255);
  f.current_data = 11;
  assert(f.evaluate().gate == 0);
  const auto capture_path = f.candidate / "qualification-capture.json";
  const auto replay_path = f.candidate / "qualification-replays/0.json";
  const auto png = f.candidate / f.expected.front().key;
  f.mutation(f.manifest, [&] { write(f.manifest, Json({{"version", 1}, {"pairs", Json::array()}}).dump()); }, 255);
  f.mutation(f.manifest, [&] {
    write(f.manifest, Json({{"version", 2}, {"roots", Json::array()}}).dump());
  }, 254);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["effective_options"]["master"] = false; }, 255);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["effective_options"]["others"]["grass"] = false; }, 255);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["effective_options"]["lighting"] = false; }, 255);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["effective_options"]["rt_light"] = false; }, 255);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["effective_options"]["hdr"] = false; }, 255);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["effective_options"]["master"] = 1; }, 255);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["effective_options"]["extra"] = true; }, 255);
  f.capture_mutation([](Json& capture) { capture["cases"][0]["phase"] = 1; }, 255);
  f.capture_mutation([](Json& capture) { capture["bin"] = capture["bin"].get<uint64_t>() ^ 1; }, 255);
  f.capture_mutation([](Json& capture) {
    for (auto& item : capture["cases"]) if (item["level"] == "level20") item["level_ok"] = false;
  }, 254);
  f.capture_mutation([](Json& capture) {
    for (auto& item : capture["cases"]) if (item["vantage"] == "view0") item["bg"] = 11;
  }, 254);
  f.mutation(capture_path, [&] {
    Json capture = detail::json(capture_path); capture["clean"] = false; write(capture_path, capture.dump());
  }, 255);
  f.mutation(f.candidate / "assets.tsv", [&] { write(f.candidate / "assets.tsv", "version=1\n"); }, 255);
  f.mutation(f.candidate / "source.json", [&] { write(f.candidate / "source.json", "{}"); }, 255);
  f.mutation(f.candidate / "renderer.cpp", [&] { write(f.candidate / "renderer.cpp", "stale"); }, 255);
  f.mutation(f.candidate / "binary", [&] { write(f.candidate / "binary", "stale"); }, 255);
  f.mutation(f.candidate / "recharged/captured-by.txt", [&] {
    write(f.candidate / "recharged/captured-by.txt", hex(f.current_bin) + "\nflavour=ablate\n");
  }, 255);
  f.mutation(png, [&] { write(png, "stale"); }, 255);
  f.mutation(png.string() + ".state.bin", [&] { write(png.string() + ".state.bin", "stale"); }, 255);
  f.mutation(png.string() + ".provenance.txt", [&] { write(png.string() + ".provenance.txt", "version=2\n"); }, 255);
  f.mutation(replay_path, [&] {
    const auto receipt = detail::read(replay_path); fs::remove(replay_path);
    assert(f.evaluate().gate == 254); write(replay_path, receipt);
  }, 0);
  // Snapshot paths and checkpoint names may differ; the asset record set must match.
  for (const auto& path : {f.candidate}) {
    const auto receipt_path = path / "qualification-replays/0.json";
    const auto snapshot_path = path / "replay-assets.tsv";
    const auto original_receipt = detail::read(receipt_path);
    auto snapshot = detail::read(path / "assets.tsv");
    snapshot.replace(snapshot.find("checkpoint\t61"), std::string("checkpoint\t61").size(),
                     "checkpoint\t62");
    write(snapshot_path, snapshot);
    Json replay = Json::parse(original_receipt);
    replay["assets_path"] = snapshot_path.string();
    replay["assets_fp"] = hash_file(snapshot_path.string());
    write(receipt_path, replay.dump());
    assert(f.evaluate().gate == 0);
    // Valid syntax and refreshed receipt hash cannot hide a changed asset record.
    snapshot.replace(snapshot.find("asset\ttest\t61"), std::string("asset\ttest\t61").size(),
                     "asset\ttest\t62");
    write(snapshot_path, snapshot);
    assert(detail::assets(snapshot_path).size() == 1);
    replay["assets_fp"] = hash_file(snapshot_path.string());
    write(receipt_path, replay.dump());
    const auto stale_assets = f.evaluate();
    assert(stale_assets.gate == 255);
    assert(std::find(stale_assets.missing.begin(), stale_assets.missing.end(), "replay-assets") !=
           stale_assets.missing.end());
    write(receipt_path, original_receipt);
  }
  f.mutation(replay_path, [&] {
    Json replay = detail::json(replay_path);
    replay["cases"][0]["effective_options"]["others"]["grass"] = false;
    write(replay_path, replay.dump());
  }, 255);
  f.mutation(replay_path, [&] {
    Json replay = detail::json(replay_path); replay["cases"][0]["diffpx"] = 1; write(replay_path, replay.dump());
  }, 255);
  f.mutation(replay_path, [&] { write(replay_path, "{incomplete"); }, 255);
  f.mutation(replay_path, [&] {
    Json replay = detail::json(replay_path);
    replay["execution"] = detail::json(capture_path)["execution"];
    write(replay_path, replay.dump());
  }, 255);
  const auto before = detail::read(capture_path);
  Json capture = detail::json(capture_path);
  capture["cases"].erase(capture["cases"].begin());
  write(capture_path, capture.dump()); f.replays(f.candidate);
  assert(f.evaluate().gate == 254);
  write(capture_path, before); f.replays(f.candidate);
  for (int pm : {149, 150, 900, 901}) {
    capture = Json::parse(before);
    for (auto& item : capture["cases"]) if (item["level"] == "level20") item["bg"] = pm;
    write(capture_path, capture.dump()); f.replays(f.candidate);
    const auto threshold = f.evaluate();
    assert(threshold.gate == uint64_t(pm == 149 || pm == 901 ? 254 : 0));
    if (threshold.gate) assert(std::any_of(threshold.missing.begin(), threshold.missing.end(),
        [](const std::string& why) { return why.find("sky:level20:") == 0; }));
  }
  write(capture_path, before); f.replays(f.candidate);
  // ON/OFF images intentionally differ; a valid refreshed receipt must still qualify.
  capture = detail::json(capture_path);
  const auto original_png = detail::read(png);
  write(png, "different-pixels");
  capture["cases"][0]["png"] = hash_file(png.string());
  const auto sidecar = png.string() + ".provenance.txt";
  const auto original_sidecar = detail::read(sidecar);
  auto modified_sidecar = original_sidecar;
  const auto start = modified_sidecar.find("\npng=") + 5;
  modified_sidecar.replace(start, 16, hex(hash_file(png.string())));
  write(sidecar, modified_sidecar);
  capture["cases"][0]["sidecar"] = hash_file(sidecar);
  write(capture_path, capture.dump()); f.replays(f.candidate);
  assert(f.evaluate().gate == 0);
  write(png, original_png); write(sidecar, original_sidecar);
  write(capture_path, before); f.replays(f.candidate);
  const auto state_path = png.string() + ".state.bin";
  const auto original_state = detail::read(state_path);
  write(state_path, "different-state");
  capture = Json::parse(before);
  capture["cases"][0]["state"] = hash_file(state_path);
  write(capture_path, capture.dump()); f.replays(f.candidate);
  assert(f.evaluate().gate == 255);
  write(state_path, original_state);
  write(capture_path, before); f.replays(f.candidate);
  assert(f.evaluate().gate == 0);
  // A collection may hold one arm per root, with the same immutable source receipt.
  const auto off_root = f.root / "off";
  fs::copy(f.candidate, off_root, fs::copy_options::recursive);
  for (const auto& path : {f.candidate, off_root}) {
    Json arm_capture = Json::parse(before);
    arm_capture["execution"] = path.string() + "-capture";
    auto& cases = arm_capture["cases"];
    for (auto it = cases.begin(); it != cases.end();) {
      if ((*it)["phase"] != (path == f.candidate ? 2 : 3)) it = cases.erase(it);
      else ++it;
    }
    write(path / "qualification-capture.json", arm_capture.dump()); f.replays(path);
  }
  write(f.manifest, Json({{"version", 2}, {"roots", {f.candidate.string(), off_root.string()}}}).dump());
  assert(f.evaluate().gate == 0 && f.evaluate().replay_runs == 1);
  // Across arms, snapshot paths and checkpoints may differ, consumed assets may not.
  const auto off_capture_path = off_root / "qualification-capture.json";
  const auto original_off_capture = detail::read(off_capture_path);
  const auto off_assets_path = off_root / "arm-assets.tsv";
  auto off_assets = detail::read(f.candidate / "assets.tsv");
  off_assets.replace(off_assets.find("checkpoint\t61"), std::string("checkpoint\t61").size(),
                     "checkpoint\t62");
  write(off_assets_path, off_assets);
  auto off_capture = Json::parse(original_off_capture);
  off_capture["assets_path"] = off_assets_path.string();
  off_capture["assets_fp"] = hash_file(off_assets_path.string());
  write(off_capture_path, off_capture.dump()); f.replays(off_root);
  assert(f.evaluate().gate == 0);
  // Change the consumed payload hash, then refresh capture and exact replay receipts.
  const auto payload_hash = off_assets.find("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  assert(payload_hash != std::string::npos);
  off_assets[payload_hash] = 'f';
  write(off_assets_path, off_assets);
  off_capture["assets_fp"] = hash_file(off_assets_path.string());
  write(off_capture_path, off_capture.dump()); f.replays(off_root);
  const auto mismatched_assets = f.evaluate();
  assert(mismatched_assets.gate == 255);
  assert(std::find(mismatched_assets.missing.begin(), mismatched_assets.missing.end(), "pair-assets") !=
         mismatched_assets.missing.end());
  write(off_capture_path, original_off_capture); f.replays(off_root);
  assert(f.evaluate().gate == 0);
  for (const char* field : {"settings", "bootstrap"}) {
    f.capture_mutation([&](Json& receipt) { receipt[field] = receipt[field].get<uint64_t>() + 1; }, 255);
  }
  // Each root needs a replay even when its other arm has one.
  const auto off_replay = off_root / "qualification-replays/0.json";
  const auto off_receipt = detail::read(off_replay);
  fs::remove(off_replay);
  assert(f.evaluate().gate == 254);
  write(off_replay, off_receipt);
  f.mutation(f.manifest, [&] {
    write(f.manifest, Json({{"version", 2}, {"roots", {f.candidate.string()}}}).dump());
  }, 254);
  assert(f.evaluate().gate == 0);
  fs::remove_all(f.root);  // Only this test's unique mkdtemp fixture.
  std::puts("REFSET qualification tests passed: cases=448 levels=21 replays=1 gate=0; negative gates checked");
}
