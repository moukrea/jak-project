#pragma once

// Proof-only numerical archive, version 1. Each *.r8 file is width*height bytes,
// GL lower-left origin, rows increasing in y, no padding: AO = byte / 255.
// manifest.txt lists dimensions and FNV-1a-64 (standard offset basis) per file.
// Camera floats are lossless decimal (max_digits10), matrices column-major.
// Stage metadata declares depth and diagnostic encodings. Completion describes I/O only;
// physical contact and source identity require the separate geometry/draw/color joins.
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <limits>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
#include "common/util/FileUtil.h"
#include "game/system/autoport_proof.h"

namespace ao_contact_archive {
// Only the explicit hut capture uses this tick; historical probes keep their schedule.
inline constexpr int64_t kCaptureLogicFrame = 600;
inline bool requested() {
  if (!autoport_proof::feature_is("ao-prepass-tie-alpha") || !autoport_proof::armed()) return false;
#ifdef __ANDROID__
  char value[PROP_VALUE_MAX] = {};
  __system_property_get("debug.opengoal.ao.contact.capture", value);
  return std::strcmp(value, "1") == 0;
#else
  const char* value = std::getenv("OG_AO_CONTACT_CAPTURE");
  return value && std::strcmp(value, "1") == 0;
#endif
}
inline uint64_t hash(const void* data, size_t size) {
  uint64_t result = 14695981039346656037ull;
  const auto* bytes = static_cast<const uint8_t*>(data);
  for (size_t i = 0; i < size; ++i) result = (result ^ bytes[i]) * 1099511628211ull;
  return result;
}
// No overwrite, including partial files from a failed run. Caller records failure.
inline bool write_exclusive(const std::string& path, const void* data, size_t size) {
  const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (fd < 0) return false;
  const auto* bytes = static_cast<const uint8_t*>(data);
  size_t done = 0;
  while (done < size) {
    const ssize_t n = ::write(fd, bytes + done, size - done);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    done += size_t(n);
  }
  const bool synced = ::fsync(fd) == 0;
  const bool closed = ::close(fd) == 0;
  return done == size && synced && closed;
}
// Shared with separately exported geometry. Empty means unavailable. A proof replay ID,
// when supplied by the existing replay launcher, is retained; PID prevents collisions.
inline const std::string& directory() {
  static const std::string unavailable;
  if (!requested()) return unavailable;
  static const std::string path = [] {
    std::string run;
    const char* id = std::getenv("OG_REFSET_RUN_ID");
    if (id && *id && std::strlen(id) <= 100 &&
        std::strspn(id, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") == std::strlen(id))
      run = std::string(id) + "-";
    const auto candidate = (file_util::get_user_home_dir() /
        ("ao-hut-archive-" + run + std::to_string(::getpid()) + "-" + std::to_string(kCaptureLogicFrame))).string();
    if (::mkdir(candidate.c_str(), 0700) != 0) return std::string{};
    return candidate;
  }();
  return path;
}
}  // namespace ao_contact_archive
