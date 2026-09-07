#!/usr/bin/env python3
# Compile the actual two CPU-only functions; no replacement implementation.
from pathlib import Path
import subprocess
import tempfile
src = Path('game/graphics/refset.cpp').read_text()
def function(name):
    start = src.index('uint64_t ' + name + '(')
    end = src.index('\n}\n', start) + 3
    return src[start:end]
preamble = r'''
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <string>
namespace fs = std::filesystem;
enum class GameVersion { Jak1 };
namespace file_util {
fs::path iso, fr3;
std::optional<fs::path> overlay, custom;
fs::path get_iso_out_dir(GameVersion) { return iso; }
fs::path get_fr3_dir(GameVersion) { return fr3; }
std::optional<fs::path> get_iso_overlay_dir() { return overlay; }
std::optional<fs::path> get_custom_fr3_dir() { return custom; }
}
'''
tests = r'''
int main(int argc, char** argv) {
  assert(argc == 2);
  fs::path root = argv[1];
  using namespace file_util;
  iso = root / "iso"; fr3 = root / "fr3";
  fs::create_directories(iso); fs::create_directories(fr3);
  auto put = [](fs::path p, const char* data) { std::ofstream f(p); f << data; assert(f.good()); };
  unsigned checks = 0;
  auto check = [&](bool ok) { assert(ok); ++checks; };
  put(iso/"GAME.CGO", "game"); put(iso/"VIL.DGO", "vil"); put(fr3/"village.fr3", "fr3");
  auto baseline = data_fingerprint();
  check(baseline == BASELINE);
  overlay = root/"absent-overlay"; custom = root/"absent-custom";
  check(data_fingerprint() == baseline);
  fs::create_directories(*overlay); fs::create_directories(*custom);
  check(data_fingerprint() == baseline);
  put(*overlay/"GAME.CGO", "game"); put(*custom/"village.fr3", "fr3");
  check(data_fingerprint() == baseline);
  put(*overlay/"GAME.CGO", "override");
  auto selected = data_fingerprint(); check(selected != baseline && selected);
  put(iso/"GAME.CGO", "hidden"); check(data_fingerprint() == selected);
  put(*custom/"village.fr3", "custom");
  auto custom_selected = data_fingerprint(); check(custom_selected != selected && custom_selected);
  put(fr3/"village.fr3", "hidden"); check(data_fingerprint() == custom_selected);
  fs::remove(iso/"GAME.CGO"); fs::remove(fr3/"village.fr3");
  check(data_fingerprint() == custom_selected);
  fs::create_directories(*custom/"enhanced"); put(*custom/"enhanced"/"village.fr3", "ignored");
  check(data_fingerprint() == custom_selected);
  fs::create_directories(fr3/"enhanced"); put(fr3/"enhanced"/"village.fr3", "enhanced");
  auto enhanced = data_fingerprint(); check(enhanced != custom_selected && enhanced);
  put(fr3/"enhanced"/"village.fr3", "enhanced-changed"); check(data_fingerprint() != enhanced);
  fs::remove(fr3/"enhanced"/"village.fr3"); fs::remove(fr3/"enhanced");
  put(fr3/"enhanced", "not-a-directory"); check(data_fingerprint() == 0); fs::remove(fr3/"enhanced");
  auto valid_custom = custom; custom = root/"bad-custom"; put(*custom, "file");
  check(data_fingerprint() == 0); custom = valid_custom;
  auto valid_overlay = overlay; overlay = root/"bad-overlay"; put(*overlay, "file");
  check(data_fingerprint() == 0); overlay = valid_overlay;
  fs::create_symlink(root/"missing", *overlay/"BROKEN.CGO"); check(data_fingerprint() == 0);
  fs::remove(*overlay/"BROKEN.CGO"); fs::remove(iso/"VIL.DGO"); check(data_fingerprint() == 0);
  put(*overlay/"VIL.DGO", "vil"); check(data_fingerprint() == custom_selected);
  std::cout << "data_fingerprint checks=" << checks << " baseline=" << std::hex << baseline << '\n';
}
'''
# Legacy sorted-name FNV formula, evaluated independently on fixed fixture contents.
mask = (1 << 64) - 1
def fnv(data, h=1469598103934665603):
    for c in data:
        h = ((h ^ c) * 1099511628211) & mask
    return h or 1
h = 1469598103934665603
for name, contents in [('fr3/village.fr3', b'fr3'), ('iso/GAME.CGO', b'game'), ('iso/VIL.DGO', b'vil')]:
    h = fnv(name.encode() + b'\xff' + fnv(contents).to_bytes(8, 'little'), h)
with tempfile.TemporaryDirectory(prefix='data-fingerprint-essai16-') as tmp:
    cpp = Path(tmp)/'test.cpp'
    cpp.write_text(preamble + function('hash_file') + function('data_fingerprint') + tests.replace('BASELINE', str(h)+'ull'))
    subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror', str(cpp), '-o', tmp+'/test'], check=True)
    subprocess.run([tmp+'/test', tmp+'/data'], check=True)
