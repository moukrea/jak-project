// CPU-only checks of the real supplemental metadata producer/reader, no game run.
#include "game/graphics/refset.cpp"
#include <cassert>
#include <fstream>
#include <iostream>

int main() {
  using namespace refset;
  char dir[] = "/tmp/refset-provenance-XXXXXX";
  assert(mkdtemp(dir));
  g_dir = dir;
  g_vants = {0};
  g_steps = {Step{1, 0, 0, true}};
  g_inflight_lf = 1081;
  const auto& step = g_steps.front();
  const auto png = image_path(step);
  const auto metadata = png + ".provenance.txt";
  fs::create_directories(fs::path(png).parent_path());
  fs::copy_file(".autoport/refset/origine/h00.png", png);
  auto read = [](const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(f), {});
  };
  auto write = [](const std::string& path, const std::string& bytes) {
    std::ofstream f(path, std::ios::binary);
    f << bytes;
    f.close();
    assert(f.good());
  };
  assert(write_capture_witness(step.phase, true));
  assert(write_supplement_provenance(step, png));
  assert(!check_supplement_provenance(step, png));
  const auto valid = read(metadata);
  const auto witness = read(witness_path(step.phase, true));
  const auto fingerprint = refs_fingerprint();
  assert(fingerprint);
  unsigned rejected = 0;
  auto reject = [&](const char* label) {
    const char* reason = check_supplement_provenance(step, png);
    assert(reason);
    ++rejected;
    std::cout << label << ": " << reason << '\n';
  };
  // Missing and duplicate records must never credit a reference.
  for (const char* field : {"version", "case", "config", "bin", "flavour", "png", "capture_lf"}) {
    const auto start = valid.find(std::string(field) + "=");
    assert(start != std::string::npos);
    const auto count = valid.find('\n', start) - start + 1;
    auto missing = valid;
    missing.erase(start, count);
    write(metadata, missing);
    reject(field);
    write(metadata, valid + valid.substr(start, count));
    reject("duplicate");
  }
  for (const char* value : {"-1", "+1081", "1081junk", "18446744073709551616", ""}) {
    auto bad = valid;
    const auto start = bad.find("capture_lf=") + 11;
    bad.replace(start, bad.find('\n', start) - start, value);
    write(metadata, bad);
    reject("invalid frame");
  }
  for (auto [field, value] : {std::pair{"version", "2"}, {"case", "origine/wrong-h00"},
                             {"config", "000000000000000g"}, {"bin", "0000000000000000"},
                             {"bin", "0000000000000001"}, {"flavour", "invalid"},
                             {"flavour", "ablate"}, {"png", "0000000000000000"}}) {
    auto bad = valid;
    const auto start = bad.find(std::string(field) + "=") + std::strlen(field) + 1;
    bad.replace(start, bad.find('\n', start) - start, value);
    write(metadata, bad);
    reject(field);
  }
  write(metadata, valid);
  ++g_inflight_lf;
  reject("wrong frame");
  --g_inflight_lf;
  ++g_step_settle;
  reject("wrong config");
  --g_step_settle;
  auto changed_png = read(png);
  changed_png.back() ^= 1;
  write(png, changed_png);
  reject("changed PNG");
  assert(refs_fingerprint() != fingerprint);
  fs::copy_file(".autoport/refset/origine/h00.png", png, fs::copy_options::overwrite_existing);
  write(witness_path(step.phase, true), witness + "flavour=normal\n");
  reject("duplicate witness");
  write(witness_path(step.phase, true), witness);
  assert(!check_supplement_provenance(step, png));
  assert(refs_fingerprint() == fingerprint);
  fs::remove(metadata);
  reject("missing sidecar");
  assert(refs_fingerprint() == 0);
  assert(!write_supplement_provenance(step, png + ".absent"));
  fs::remove_all(g_dir);
  std::cout << "valid roundtrip=1 rejected=" << rejected << '\n';
}
