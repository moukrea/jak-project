// Standalone: c++ -std=c++17 -O2 -Wall -Wextra -Werror -pthread -I. this-file.cpp -o /tmp/test-refset-file
#include "game/graphics/refset_file.h"

#include <array>
#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <pthread.h>
#include <unistd.h>
#include <vector>

namespace {
struct Case {
  std::string path;
  uint64_t expected;
  uint64_t actual = 0;
};

uint64_t reference(const std::vector<unsigned char>& bytes) {
  uint64_t hash = UINT64_C(1469598103934665603);
  for (unsigned char byte : bytes) {
    hash = (hash ^ byte) * UINT64_C(1099511628211);
  }
  return hash == 0 ? 1 : hash;
}

void write_file(const std::string& path, const std::vector<unsigned char>& bytes) {
  FILE* file = std::fopen(path.c_str(), "wb");
  assert(file);
  if (!bytes.empty()) {
    assert(std::fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size());
  }
  assert(std::fclose(file) == 0);
}

void* hash_on_small_stack(void* argument) {
  auto& cases = *static_cast<std::array<Case, 5>*>(argument);
  for (auto& test : cases) {
    test.actual = refset_file::hash_file(test.path);
  }
  return nullptr;
}
}  // namespace

int main() {
  char pattern[] = "/tmp/refset-file-XXXXXX";
  char* directory = mkdtemp(pattern);
  assert(directory);
  const std::string root(directory);
  std::vector<unsigned char> bytes(3 * 65536 + 17);
  for (size_t i = 0; i < bytes.size(); ++i) {
    bytes[i] = static_cast<unsigned char>((i * 37 + i / 251) & 255);
  }
  const uint64_t original_hash = reference(bytes);
  write_file(root + "/chunks", bytes);
  bytes[65536] ^= 0x5a;
  const uint64_t modified_hash = reference(bytes);
  assert(modified_hash != original_hash);
  write_file(root + "/modified", bytes);
  write_file(root + "/empty", {});

  // On this host a directory opens, then fails on read: exercise ferror, not just fopen.
  FILE* unreadable = std::fopen(root.c_str(), "rb");
  assert(unreadable);
  unsigned char byte;
  assert(std::fread(&byte, 1, 1, unreadable) == 0);
  assert(std::ferror(unreadable));
  assert(std::fclose(unreadable) == 0);

  std::array<Case, 5> cases{{
      {root + "/chunks", original_hash},
      {root + "/empty", UINT64_C(1469598103934665603)},
      {root + "/absent", 0},
      {root, 0},
      {root + "/modified", modified_hash},
  }};
  pthread_attr_t attributes;
  assert(pthread_attr_init(&attributes) == 0);
  constexpr size_t stack_size = 32768;
  assert(pthread_attr_setstacksize(&attributes, stack_size) == 0);
  size_t configured_stack = 0, guard_size = 0;
  assert(pthread_attr_getstacksize(&attributes, &configured_stack) == 0);
  assert(configured_stack == stack_size);
  assert(pthread_attr_getguardsize(&attributes, &guard_size) == 0);
  assert(guard_size > 0);  // Keep the default guard enabled.
  pthread_t thread;
  assert(pthread_create(&thread, &attributes, hash_on_small_stack, &cases) == 0);
  assert(pthread_attr_destroy(&attributes) == 0);
  assert(pthread_join(thread, nullptr) == 0);
  for (const auto& test : cases) {
    std::printf("hash=%016llx expected=%016llx path=%s\n",
                static_cast<unsigned long long>(test.actual),
                static_cast<unsigned long long>(test.expected), test.path.c_str());
    assert(test.actual == test.expected);
  }
  std::filesystem::remove_all(root);
  std::printf("PASS cases=%zu stack=%zu guard=%zu bytes=%zu\n", cases.size(),
              configured_stack, guard_size, bytes.size());
}
