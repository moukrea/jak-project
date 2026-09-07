// Standalone build: compile this file and game/system/boot_replay.cpp together
// with c++ -std=c++17 -Wall -Wextra -Werror -I.
#include "game/system/boot_replay.h"

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {
using Bytes = std::vector<unsigned char>;
Bytes read_file(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  return Bytes(std::istreambuf_iterator<char>(file), {});
}
void write_file(const std::string& path, const Bytes& bytes) {
  std::ofstream file(path, std::ios::binary);
  file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  file.close();
  assert(file);
}
enum class Action { Normal, Off, Conflict, BadTag, Big, After, Twice, Limit };
uint64_t run(const std::string& path, bool capture, bool success,
             Action action = Action::Normal) {
  int pipefd[2];
  assert(pipe(pipefd) == 0);
  const pid_t pid = fork();
  assert(pid >= 0);
  if (!pid) {
    close(pipefd[0]);
    unsetenv("OG_BOOT_REPLAY_CAPTURE");
    unsetenv("OG_BOOT_REPLAY_REPLAY");
    if (action != Action::Off) {
      setenv(capture ? "OG_BOOT_REPLAY_CAPTURE" : "OG_BOOT_REPLAY_REPLAY", path.c_str(), 1);
    }
    if (action == Action::Conflict) {
      setenv("OG_BOOT_REPLAY_REPLAY", path.c_str(), 1);
    }
    if (action == Action::Off) {
      assert(!boot_replay::enabled() && !boot_replay::active());
      boot_replay::input(nullptr, nullptr, 100000);
      boot_replay::checkpoint(nullptr, nullptr, 100000);
      boot_replay::finish();
      assert(boot_replay::fingerprint() == 0 && boot_replay::records() == 0);
      _exit(0);
    }
    assert(boot_replay::enabled() && boot_replay::active());
    assert(boot_replay::fingerprint() == 0);
    if (action == Action::BadTag) {
      boot_replay::input(std::string(64, 'x').c_str(), nullptr, 0);
    }
    if (action == Action::Big) {
      boot_replay::input("big", nullptr, 16385);
    }
    if (action == Action::Limit) {
      const int nullfd = open("/dev/null", O_WRONLY);
      assert(nullfd >= 0 && dup2(nullfd, STDERR_FILENO) >= 0);
      close(nullfd);
      for (unsigned i = 0; i <= 65536; ++i) {
        boot_replay::input("z", nullptr, 0);
      }
    }
    unsigned char input[] = {1, 2, 3, 4};
    if (!capture) {
      std::memset(input, 0, sizeof(input));
    }
    boot_replay::input("seed", input, sizeof(input));
    assert(input[0] == 1 && input[1] == 2 && input[2] == 3 && input[3] == 4);
    const unsigned char expected[] = {9, 8};
    boot_replay::checkpoint("check", expected, sizeof(expected));
    assert(expected[0] == 9 && expected[1] == 8);
    Bytes large(16384, capture ? 0x42 : 0);
    boot_replay::input("large", large.data(), large.size());
    assert(large == Bytes(16384, 0x42));
    assert(boot_replay::records() == 3 && boot_replay::fingerprint() == 0);
    boot_replay::finish();
    assert(boot_replay::enabled() && !boot_replay::active());
    if (action == Action::After) {
      boot_replay::checkpoint("late", expected, sizeof(expected));
    }
    if (action == Action::Twice) {
      boot_replay::finish();
    }
    const uint64_t hash = boot_replay::fingerprint();
    assert(hash);
    assert(write(pipefd[1], &hash, sizeof(hash)) == sizeof(hash));
    _exit(0);
  }
  close(pipefd[1]);
  uint64_t hash = 0;
  const ssize_t n = read(pipefd[0], &hash, sizeof(hash));
  assert(n == 0 || n == sizeof(hash));
  close(pipefd[0]);
  int status;
  assert(waitpid(pid, &status, 0) == pid);
  assert(WIFEXITED(status));
  assert(WEXITSTATUS(status) == (success ? 0 : EXIT_FAILURE));
  return hash;
}
}  // namespace

int main() {
  char temp[] = "/tmp/boot-replay-test-XXXXXX";
  assert(mkdtemp(temp));
  const std::string base = std::string(temp) + "/stream";
  run(base, true, true, Action::Off);
  assert(access(base.c_str(), F_OK) != 0);
  const auto capture_hash = run(base, true, true);
  assert(run(base, false, true) == capture_hash);
  const Bytes original = read_file(base);
  uint64_t independent_hash = UINT64_C(14695981039346656037);
  for (auto byte : original) {
    independent_hash = (independent_hash ^ byte) * UINT64_C(1099511628211);
  }
  assert(independent_hash == capture_hash);
  run(base, true, false);
  assert(read_file(base) == original);
  const std::string link = base + "-link";
  assert(symlink(base.c_str(), link.c_str()) == 0);
  run(link, true, false);
  assert(read_file(base) == original);
  assert(unlink(link.c_str()) == 0);
  run(base, true, false, Action::Conflict);
  run(base, false, false, Action::After);
  run(base, false, false, Action::Twice);
  const std::string bad = base + "-bad";
  // Magic/version, record kind/tag size/payload size/tag, checkpoint payload,
  // terminal count. These offsets intentionally describe the public wire format.
  for (size_t offset : {size_t(0), size_t(8), size_t(12), size_t(13), size_t(14),
                        size_t(18), size_t(37), original.size() - 1}) {
    Bytes modified = original;
    modified[offset] ^= 0x80;
    write_file(bad, modified);
    run(bad, false, false);
  }
  for (size_t length : {size_t(0), size_t(11), size_t(25), original.size() - 1}) {
    write_file(bad, Bytes(original.begin(), original.begin() + length));
    run(bad, false, false);
  }
  Bytes trailing = original;
  trailing.push_back(0);
  write_file(bad, trailing);
  run(bad, false, false);
  assert(unlink(bad.c_str()) == 0);
  for (Action action : {Action::BadTag, Action::Big, Action::Limit}) {
    run(bad, true, false, action);
    assert(unlink(bad.c_str()) == 0);
  }
  run(bad, false, false);  // Missing input file.
  assert(unlink(base.c_str()) == 0);
  assert(rmdir(temp) == 0);
  std::printf("BOOTREPLAY standalone tests passed: records=3 fingerprint=%016llx\n",
              static_cast<unsigned long long>(capture_hash));
}
