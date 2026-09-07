// Standalone POSIX test: each subprocess starts with fresh manifest configuration.
// c++ -std=c++17 -O0 -pthread -DFMT_HEADER_ONLY -I. -Ithird-party/fmt/include \
//   test/common/test_asset_manifest.cpp game/system/asset_manifest.cpp \
//   common/util/RPack.cpp -o /tmp/test_asset_manifest && /tmp/test_asset_manifest
#include <algorithm>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

#include "common/util/RPack.h"

#include "game/system/asset_manifest.h"
#include <sys/resource.h>
#include <sys/wait.h>

namespace {
void check(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::string read(const std::filesystem::path& path) {
  std::ifstream file(path, std::ios::binary);
  check(file.good(), "manifest not readable");
  return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}

void run(const std::filesystem::path& path,
         const std::function<void()>& work,
         bool success = true,
         const char* mode = "capture") {
  const pid_t pid = fork();
  check(pid >= 0, "fork failed");
  if (pid == 0) {
    setenv("OG_REFSET_ASSET_MANIFEST", path.c_str(), 1);
    if (mode) {
      setenv("OG_REFSET", mode, 1);
    } else {
      unsetenv("OG_REFSET");
    }
    try {
      work();
      std::exit(EXIT_SUCCESS);
    } catch (const std::exception& e) {
      std::fprintf(stderr, "test child error: %s\n", e.what());
      std::_Exit(2);
    }
  }
  int status = 0;
  check(waitpid(pid, &status, 0) == pid, "waitpid failed");
  check(WIFEXITED(status), "child did not exit normally");
  check(WEXITSTATUS(status) == (success ? EXIT_SUCCESS : EXIT_FAILURE),
        "unexpected subprocess exit status");
}

std::string last_checkpoint(const std::string& contents) {
  const auto pos = contents.rfind("checkpoint\t");
  check(pos != std::string::npos, "checkpoint missing");
  return contents.substr(pos);
}

struct TempDirectory {
  std::filesystem::path path;
  TempDirectory() {
    char pattern[] = "/tmp/asset-manifest-test-XXXXXX";
    const char* dir = mkdtemp(pattern);
    check(dir != nullptr, "mkdtemp failed");
    path = dir;
  }
  ~TempDirectory() {
    for (const auto& file : std::filesystem::directory_iterator(path)) {
      std::filesystem::remove(file.path());
    }
    std::filesystem::remove(path);
  }
};
}  // namespace

int main() {
  try {
    TempDirectory temp;
    const auto path = [&](const char* name) { return temp.path / name; };
    run(path("disabled"), [] {
      unsetenv("OG_REFSET_ASSET_MANIFEST");
      check(!asset_manifest::enabled(), "absent path enabled manifest");
      asset_manifest::record(nullptr, "", 0, nullptr, 1);
      asset_manifest::checkpoint("");
    });
    check(!std::filesystem::exists(path("disabled")), "disabled wrote a file");
    run(path("empty-path"), [] {
      setenv("OG_REFSET_ASSET_MANIFEST", "", 1);
      check(!asset_manifest::enabled(), "empty path enabled manifest");
      asset_manifest::record(nullptr, "", 0, nullptr, 1);
    });
    run(path("empty"), [] {
      check(asset_manifest::enabled(), "capture disabled manifest");
      asset_manifest::checkpoint("empty");
    });
    check(read(path("empty")) ==
              "version=1\ncheckpoint\t656d707479\t0\t"
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n",
          "empty checkpoint differs from SHA256 empty input");

    const auto records = [](bool reverse) {
      const std::string a = "payload A", b = "payload B";
      const auto first = [&] { asset_manifest::record("loose", "a", 0, a.data(), a.size()); };
      const auto second = [&] { asset_manifest::record("dgo", "b", 32768, b.data(), b.size()); };
      if (reverse) {
        second();
        first();
      } else {
        first();
        second();
      }
      asset_manifest::checkpoint("same");
      std::vector<std::thread> workers;
      for (int i = 0; i < 8; ++i) {
        workers.emplace_back([&] {
          for (int j = 0; j < 16; ++j) {
            first();
            second();
          }
        });
      }
      for (auto& worker : workers) {
        worker.join();
      }
      asset_manifest::checkpoint("same");
    };
    run(path("forward"), [&] { records(false); });
    run(path("reverse"), [&] { records(true); }, true, "replay");
    const std::string forward = read(path("forward"));
    const auto checkpoint = last_checkpoint(forward);
    check(checkpoint == last_checkpoint(read(path("reverse"))), "record order changed digest");
    const size_t first_checkpoint = forward.find("checkpoint\t");
    check(forward.substr(first_checkpoint) == checkpoint + checkpoint,
          "duplicate records changed cumulative set");
    check(std::count(forward.begin(), forward.end(), '\n') == 5,
          "duplicate/threaded records leaked into manifest");

    const auto payload = [](bool mutate) {
      std::vector<u8> bytes(20000, 42);
      if (mutate) {
        bytes[17000] ^= 1;
      }
      asset_manifest::record("texture", std::string("a\t\n\0\xff", 5), UINT64_MAX, bytes.data(),
                             bytes.size());
      asset_manifest::checkpoint("full");
    };
    run(path("original"), [&] { payload(false); });
    run(path("mutated"), [&] { payload(true); });
    const std::string original = read(path("original"));
    check(original.find("asset\ttexture\t61090a00ff\t18446744073709551615\t20000\t") !=
              std::string::npos,
          "special name/large offset encoding wrong");
    check(last_checkpoint(original) != last_checkpoint(read(path("mutated"))),
          "mutation after byte 4096 did not change digest");
    const std::vector<u8> bytes(20000, 42);
    check(original.find(rpack::sha256_hex(bytes.data(), bytes.size())) != std::string::npos,
          "asset hash does not match full supplied buffer");

    {
      std::ofstream existing(path("existing"));
      existing << "keep me\n";
    }
    const auto enable = [] { asset_manifest::enabled(); };
    run(path("existing"), enable, false);
    check(read(path("existing")) == "keep me\n", "existing file was changed");
    std::filesystem::create_symlink(path("existing"), path("symlink"));
    run(path("symlink"), enable, false);
    check(std::filesystem::is_symlink(path("symlink")), "symlink was replaced");
    check(read(path("existing")) == "keep me\n", "symlink target was changed");
    run(path("missing-mode"), enable, false, nullptr);
    check(!std::filesystem::exists(path("missing-mode")), "missing mode created manifest");
    run(path("invalid-mode"), enable, false, "off");
    run(path("invalid-kind"), [] { asset_manifest::record("bad\n", "ok", 0, nullptr, 0); }, false);
    run(path("null-kind"), [] { asset_manifest::record(nullptr, "ok", 0, nullptr, 0); }, false);
    run(path("empty-name"), [] { asset_manifest::record("ok", "", 0, nullptr, 0); }, false);
    run(path("null-payload"), [] { asset_manifest::record("ok", "ok", 0, nullptr, 1); }, false);
    run(path("empty-label"), [] { asset_manifest::checkpoint(""); }, false);
    run(
        path("write-error"),
        [] {
          std::signal(SIGXFSZ, SIG_IGN);
          const rlimit limit{16, 16};
          check(setrlimit(RLIMIT_FSIZE, &limit) == 0, "setrlimit failed");
          asset_manifest::record("ok", "ok", 0, nullptr, 0);
        },
        false);
    std::puts(
        "ASSET_MANIFEST_TEST PASS: full-buffer SHA256, canonical set, concurrent duplicates, "
        "empty checkpoint, encoding, exclusive files/symlinks, disabled no-op, invalid input, "
        "write error");
    return EXIT_SUCCESS;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "ASSET_MANIFEST_TEST FAIL: %s\n", e.what());
    return EXIT_FAILURE;
  }
}
