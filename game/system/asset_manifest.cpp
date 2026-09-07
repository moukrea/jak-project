#include "asset_manifest.h"

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <mutex>
#include <set>
#ifdef _WIN32
#include <io.h>

#include <sys/stat.h>
#else
#include <unistd.h>
#endif

#include "common/util/RPack.h"

namespace asset_manifest {
namespace {
[[noreturn]] void fail(const char* message) {
  std::fprintf(stderr, "ASSET_MANIFEST error: %s\n", message);
  std::fflush(stderr);
  std::exit(EXIT_FAILURE);
}

[[noreturn]] void io_fail(const char* operation) {
  char message[256];
  std::snprintf(message, sizeof(message), "%s: %s", operation, std::strerror(errno));
  fail(message);
}

int close_stream(int fd) {
#ifdef _WIN32
  return ::_close(fd);
#else
  return ::close(fd);
#endif
}

void append(int fd, const std::string& line) {
  size_t done = 0;
  while (done < line.size()) {
    const size_t count = std::min(line.size() - done, static_cast<size_t>(INT_MAX));
#ifdef _WIN32
    const auto written = ::_write(fd, line.data() + done, static_cast<unsigned int>(count));
#else
    const auto written = ::write(fd, line.data() + done, count);
#endif
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      io_fail("write");
    }
    if (written == 0) {
      fail("write made no progress");
    }
    done += static_cast<size_t>(written);
  }
}

struct State {
  std::mutex mutex;
  std::set<std::string> assets;
  int fd = -1;

  State() {
    const char* path = std::getenv("OG_REFSET_ASSET_MANIFEST");
    if (!path || !*path) {
      return;
    }
    const char* mode = std::getenv("OG_REFSET");
    if (!mode || (std::strcmp(mode, "capture") && std::strcmp(mode, "replay"))) {
      fail("OG_REFSET_ASSET_MANIFEST requires OG_REFSET=capture or replay");
    }
#ifdef _WIN32
    fd = ::_open(path, _O_WRONLY | _O_CREAT | _O_EXCL | _O_APPEND | _O_BINARY | _O_NOINHERIT,
                 _S_IREAD | _S_IWRITE);
#else
    fd = ::open(path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_CLOEXEC, 0600);
#endif
    if (fd < 0) {
      io_fail("exclusive create");
    }
    append(fd, "version=1\n");
  }

  ~State() {
    if (fd >= 0 && close_stream(fd) != 0) {
      // exit() here would re-enter static destruction.
      std::fprintf(stderr, "ASSET_MANIFEST error: close: %s\n", std::strerror(errno));
      std::fflush(stderr);
      std::_Exit(EXIT_FAILURE);
    }
  }
};

State& state() {
  static State value;
  return value;
}

std::string hex_name(const std::string& value) {
  if (value.empty()) {
    fail("empty logical name or checkpoint label");
  }
  constexpr char digits[] = "0123456789abcdef";
  std::string result;
  for (unsigned char c : value) {
    result += digits[c >> 4];
    result += digits[c & 15];
  }
  return result;
}

bool valid_kind(const char* kind) {
  if (!kind || !*kind) {
    return false;
  }
  for (; *kind; ++kind) {
    const unsigned char c = *kind;
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' ||
          c == '.' || c == '-')) {
      return false;
    }
  }
  return true;
}
}  // namespace

bool enabled() {
  return state().fd >= 0;
}

void record(const char* kind,
            const std::string& logical_name,
            uint64_t offset,
            const void* bytes,
            size_t size) {
  auto& s = state();
  if (s.fd < 0) {
    return;
  }
  if (!valid_kind(kind)) {
    fail("invalid asset category");
  }
  if (!bytes && size) {
    fail("null payload with nonzero size");
  }
  const std::string line = "asset\t" + std::string(kind) + "\t" + hex_name(logical_name) + "\t" +
                           std::to_string(offset) + "\t" + std::to_string(size) + "\t" +
                           rpack::sha256_hex(static_cast<const u8*>(bytes), size) + "\n";
  std::lock_guard<std::mutex> lock(s.mutex);
  if (s.assets.insert(line).second) {
    append(s.fd, line);
  }
}

void checkpoint(const std::string& label) {
  auto& s = state();
  if (s.fd < 0) {
    return;
  }
  const std::string encoded_label = hex_name(label);
  std::lock_guard<std::mutex> lock(s.mutex);
  std::string canonical;
  for (const auto& line : s.assets) {
    canonical += line;
  }
  append(s.fd,
         "checkpoint\t" + encoded_label + "\t" + std::to_string(s.assets.size()) + "\t" +
             rpack::sha256_hex(reinterpret_cast<const u8*>(canonical.data()), canonical.size()) +
             "\n");
}
}  // namespace asset_manifest
