#pragma once

#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>

namespace refset_file {

inline uint64_t hash_file(const std::string& path) {
  // Called from GOAL's 32 KiB process stack: keep the 64 KiB read buffer on the heap.
  constexpr size_t kBufferSize = 1 << 16;
  std::unique_ptr<unsigned char[]> buf(new unsigned char[kBufferSize]);
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    return 0;
  }
  // Preserve the existing offset (not the standard FNV-1a 64 offset basis).
  uint64_t h = 1469598103934665603ull;
  size_t n;
  while ((n = std::fread(buf.get(), 1, kBufferSize, f)) > 0) {
    for (size_t i = 0; i < n; i++) {
      h ^= buf[i];
      h *= 1099511628211ull;
    }
  }
  const bool readable = !std::ferror(f);
  const bool closed = std::fclose(f) == 0;
  if (!readable || !closed) {
    return 0;
  }
  return h ? h : 1;  // 0 is reserved for an unreadable file.
}

}  // namespace refset_file
