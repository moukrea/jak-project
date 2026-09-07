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
  fs::path root, baseline, candidate, manifest;
  std::vector<Expected> expected;
  uint64_t current_bin;
  uint64_t current_data = 11;
  explicit Fixture(const fs::path& dir) : root(dir), baseline(dir / "baseline"),
      candidate(dir / "candidate"), manifest(dir / "manifest.json") {
    for (int view = 0; view < 28; ++view) {
      const auto vantage = "view" + std::to_string(view);
      const auto level = "level" + std::to_string(view < 21 ? view : view - 17);
      for (int phase = 1; phase <= 3; ++phase) for (int hour = 0; hour < 24; hour += 3) {
        const auto key = (view >= 26 ? "supplement-v1/" : "") + vantage + "/p" +
                         std::to_string(phase) + "-h" + std::to_string(hour) + ".png";
        expected.push_back({key, vantage, level, phase, hour});
      }
    }
    make_capture(baseline, true);
    make_capture(candidate, false);
    current_bin = detail::json(candidate / "qualification-capture.json").at("bin").get<uint64_t>();
    write(manifest, Json({{"version", 1}, {"pairs", {{{"baseline", baseline.string()},
                                                   {"candidate", candidate.string()}}}}}).dump());
  }
  void make_capture(const fs::path& path, bool base) {
    write(path / "binary", base ? "baseline-binary" : "candidate-binary");
    write(path / "renderer.cpp", base ? "baseline-renderer" : "candidate-renderer");
    const uint64_t bin = hash_file((path / "binary").string());
    Json source = {{"version", 1}, {"bin", bin}, {"role", base ? "baseline" : "candidate"},
                   {"binary_path", (path / "binary").string()},
                   {"files", {{(path / "renderer.cpp").string(), hash_file((path / "renderer.cpp").string())}}}};
    if (base) {
      source["baseline_anchor"] = "a9ea15a69062a57335278db7680cd647df3c1e1d";
      source["baseline_renderer_verified"] = true;
    }
    write(path / "source.json", source.dump());
    // SHA256 fixture: empty asset payload and a structurally valid checkpoint.
    write(path / "assets.tsv", "version=1\nasset\ttest\t61\t0\t0\t"
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n"
          "checkpoint\t61\t1\t"
          "c6ae71da4542799231ae28578897dc6eedb1b2371f328550b31aa1f119e4a93f\n");
    Json capture = {{"version", 1}, {"kind", "capture"}, {"execution", path.string() + "-capture"},
                    {"bin", bin}, {"data", uint64_t(11)}, {"input", uint64_t(12)},
                    {"settings", uint64_t(13)}, {"config", uint64_t(base ? 14 : 15)},
                    {"bootstrap", uint64_t(16)}, {"source_path", (path / "source.json").string()},
                    {"source_fp", hash_file((path / "source.json").string())}, {"clean", true},
                    {"reconstructed", true}, {"calibrated", false},
                    {"assets_path", (path / "assets.tsv").string()},
                    {"assets_fp", hash_file((path / "assets.tsv").string())}, {"cases", Json::array()}};
    for (const auto& e : expected) {
      if (base && e.phase != 1) continue;
      const auto png = path / e.key;
      write(png, "decoded-RGB-fixture:" + e.key);
      write(png.string() + ".state.bin", "state-v1:" + e.key);
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
          {"maxdiff", 0}, {"diffpx", 0}});
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
    for (int run = 0; run < 5; ++run) {
      Json replay = capture;
      replay["kind"] = "replay";
      replay["execution"] = path.string() + "-replay-" + std::to_string(run);
      replay["capture_fp"] = hash_file(capture_path.string());
      write(path / "qualification-replays" / (std::to_string(run) + ".json"), replay.dump());
    }
  }
  Result evaluate() {
    return refset_qualification::evaluate(manifest, current_bin, current_data, hash_file,
        [](const std::string& a, const std::string& b) { return detail::read(a) == detail::read(b); }, expected);
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
  assert(valid.gate == 0 && valid.replay_runs == 5 && valid.identity != 0);
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
  f.mutation(f.manifest, [&] { write(f.manifest, Json({{"version", 1}, {"pairs", Json::array()}}).dump()); }, 254);
  f.mutation(capture_path, [&] {
    Json capture = detail::json(capture_path); capture["clean"] = false; write(capture_path, capture.dump());
  }, 255);
  f.mutation(f.candidate / "assets.tsv", [&] { write(f.candidate / "assets.tsv", "version=1\n"); }, 255);
  f.mutation(f.candidate / "source.json", [&] { write(f.candidate / "source.json", "{}"); }, 255);
  f.mutation(f.candidate / "renderer.cpp", [&] { write(f.candidate / "renderer.cpp", "stale"); }, 255);
  f.mutation(f.candidate / "binary", [&] { write(f.candidate / "binary", "stale"); }, 255);
  f.mutation(f.candidate / "origine/captured-by.txt", [&] {
    write(f.candidate / "origine/captured-by.txt", hex(f.current_bin) + "\nflavour=ablate\n");
  }, 255);
  f.mutation(png, [&] { write(png, "stale"); }, 255);
  f.mutation(png.string() + ".state.bin", [&] { write(png.string() + ".state.bin", "stale"); }, 255);
  f.mutation(png.string() + ".provenance.txt", [&] { write(png.string() + ".provenance.txt", "version=2\n"); }, 255);
  f.mutation(replay_path, [&] {
    const auto receipt = detail::read(replay_path); fs::remove(replay_path);
    assert(f.evaluate().gate == 254); write(replay_path, receipt);
  }, 0);
  // Snapshot paths and checkpoint names may differ; the asset record set must match.
  for (const auto& path : {f.baseline, f.candidate}) {
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
    Json replay = detail::json(replay_path); replay["cases"][0]["diffpx"] = 1; write(replay_path, replay.dump());
  }, 255);
  f.mutation(replay_path, [&] { write(replay_path, "{incomplete"); }, 255);
  f.mutation(replay_path, [&] {
    Json replay = detail::json(replay_path);
    replay["execution"] = detail::json(f.candidate / "qualification-replays/1.json")["execution"];
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
  // Updating hashes and receipts cannot make a real phase-1 image/state difference pass.
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
  assert(f.evaluate().gate == 255);
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
  fs::remove_all(f.root);  // Only this test's unique mkdtemp fixture.
  std::puts("REFSET qualification tests passed: cases=672 levels=21 replays=5 gate=0; negative gates checked");
}
