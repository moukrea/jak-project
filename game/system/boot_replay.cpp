#include "boot_replay.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include <fcntl.h>
#ifdef _WIN32
#include <io.h>
#include <sys/stat.h>
#else
#include <unistd.h>
#endif

namespace boot_replay {
namespace {
enum class Mode { Off, Capture, Replay };
struct State {
  bool initialized = false;
  bool finished = false;
  Mode mode = Mode::Off;
  int fd = -1;
  uint64_t count = 0;
  uint64_t hash = UINT64_C(14695981039346656037);
  const char* tag = "init";
};
State state;
constexpr size_t kMaxTag = 63;
constexpr size_t kMaxSize = 16384;
constexpr uint64_t kMaxRecords = 65536;
// Magic followed by version 1, little-endian. Record: kind u8, tag length
// u8, payload length u32 LE, tag bytes, payload bytes. End: 0xff, count u64 LE.
constexpr unsigned char kHeader[] = {'O', 'G', 'B', 'O', 'O', 'T', 'R', 'P', 1, 0, 0, 0};

int open_stream(const char* path, bool capture) {
#ifdef _WIN32
  const int flags = _O_BINARY | _O_NOINHERIT;
  return capture ? ::_open(path, _O_WRONLY | _O_CREAT | _O_EXCL | flags, _S_IREAD | _S_IWRITE)
                 : ::_open(path, _O_RDONLY | flags);
#else
  return capture ? ::open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600)
                 : ::open(path, O_RDONLY | O_CLOEXEC);
#endif
}

std::ptrdiff_t read_stream(void* bytes, size_t size) {
#ifdef _WIN32
  return ::_read(state.fd, bytes, static_cast<unsigned int>(size));
#else
  return ::read(state.fd, bytes, size);
#endif
}

std::ptrdiff_t write_stream(const void* bytes, size_t size) {
#ifdef _WIN32
  return ::_write(state.fd, bytes, static_cast<unsigned int>(size));
#else
  return ::write(state.fd, bytes, size);
#endif
}

int close_stream() {
#ifdef _WIN32
  return ::_close(state.fd);
#else
  return ::close(state.fd);
#endif
}

const char* mode_name() {
  return state.mode == Mode::Capture ? "capture" : state.mode == Mode::Replay ? "replay" : "off";
}

[[noreturn]] void fail(const char* reason) {
  std::fprintf(stderr, "BOOTREPLAY error mode=%s tag=%s index=%llu count=%llu: %s\n",
               mode_name(), state.tag, static_cast<unsigned long long>(state.count),
               static_cast<unsigned long long>(state.count), reason);
  std::fflush(stderr);
  std::exit(EXIT_FAILURE);
}

[[noreturn]] void io_fail(const char* operation) {
  char message[256];
  std::snprintf(message, sizeof(message), "%s: %s", operation, std::strerror(errno));
  fail(message);
}

void transfer(void* data, size_t size) {
  auto* bytes = static_cast<unsigned char*>(data);
  while (size) {
    const std::ptrdiff_t n = state.mode == Mode::Capture ? write_stream(bytes, size)
                                                       : read_stream(bytes, size);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      io_fail(state.mode == Mode::Capture ? "write" : "read");
    }
    if (!n) {
      fail(state.mode == Mode::Capture ? "zero-length write" : "truncated stream");
    }
    for (std::ptrdiff_t i = 0; i < n; ++i) {
      state.hash ^= bytes[i];
      state.hash *= UINT64_C(1099511628211);
    }
    bytes += n;
    size -= static_cast<size_t>(n);
  }
}

void fixed(const void* expected, size_t size) {
  if (size > kMaxSize) {
    fail("internal fixed size limit");
  }
  std::vector<unsigned char> buffer(size);
  std::memcpy(buffer.data(), expected, size);
  transfer(buffer.data(), size);
  if (std::memcmp(buffer.data(), expected, size)) {
    fail("stream format, tag, size, count or checkpoint mismatch");
  }
}

void encode_le(unsigned char* out, uint64_t value, size_t size) {
  for (size_t i = 0; i < size; ++i) {
    out[i] = static_cast<unsigned char>(value >> (8 * i));
  }
}

void record(unsigned char kind, const char* tag, const void* bytes, size_t size,
            void* replay_destination) {
  if (!enabled()) {
    return;
  }
  state.tag = "invalid-tag";
  size_t tag_size = 0;
  if (tag) {
    while (tag_size <= kMaxTag && tag[tag_size]) {
      ++tag_size;
    }
  }
  if (!tag_size || tag_size > kMaxTag) {
    fail("tag must contain 1..63 bytes");
  }
  state.tag = tag;
  if (state.finished) {
    fail("record after finish");
  }
  if (size > kMaxSize || (size && !bytes)) {
    fail("payload exceeds 16384 bytes or null payload");
  }
  if (state.count >= kMaxRecords) {
    fail("record limit exceeded");
  }
  unsigned char header[6] = {kind, static_cast<unsigned char>(tag_size), 0, 0, 0, 0};
  encode_le(header + 2, size, 4);
  fixed(header, sizeof(header));
  fixed(tag, tag_size);
  if (size) {
    if (kind == 1 && state.mode == Mode::Replay) {
      transfer(replay_destination, size);
    } else {
      fixed(bytes, size);
    }
  }
  ++state.count;
  std::fprintf(stderr, "BOOTREPLAY record mode=%s tag=%s index=%llu count=%llu\n",
               mode_name(), state.tag, static_cast<unsigned long long>(state.count - 1),
               static_cast<unsigned long long>(state.count));
  state.tag = "idle";
}
}  // namespace

bool enabled() {
  if (!state.initialized) {
    state.initialized = true;
    const char* capture = std::getenv("OG_BOOT_REPLAY_CAPTURE");
    const char* replay = std::getenv("OG_BOOT_REPLAY_REPLAY");
    if (capture && replay) {
      fail("capture and replay modes are mutually exclusive");
    }
    if (capture || replay) {
      state.mode = capture ? Mode::Capture : Mode::Replay;
      const char* path = capture ? capture : replay;
      if (!*path) {
        fail("empty stream path");
      }
      state.fd = open_stream(path, capture != nullptr);
      if (state.fd < 0) {
        io_fail("open");
      }
      fixed(kHeader, sizeof(kHeader));
      std::fprintf(stderr, "BOOTREPLAY begin mode=%s tag=init index=0 count=0\n", mode_name());
      state.tag = "idle";
    }
  }
  return state.mode != Mode::Off;
}

bool active() {
  return enabled() && !state.finished;
}

void input(const char* tag, void* bytes, size_t size) {
  record(1, tag, bytes, size, bytes);
}

void checkpoint(const char* tag, const void* bytes, size_t size) {
  record(2, tag, bytes, size, nullptr);
}

void finish() {
  if (!enabled()) {
    return;
  }
  state.tag = "finish";
  if (state.finished) {
    fail("duplicate finish");
  }
  unsigned char end[9] = {0xff};
  encode_le(end + 1, state.count, 8);
  fixed(end, sizeof(end));
  if (state.mode == Mode::Replay) {
    unsigned char extra;
    std::ptrdiff_t n;
    do {
      n = read_stream(&extra, 1);
    } while (n < 0 && errno == EINTR);
    if (n < 0) {
      io_fail("EOF read");
    }
    if (n != 0) {
      fail("trailing bytes after final marker");
    }
  }
  if (close_stream() != 0) {
    io_fail("close");
  }
  state.fd = -1;
  state.finished = true;
  std::fprintf(stderr, "BOOTREPLAY finish mode=%s tag=finish index=%llu count=%llu fingerprint=%016llx\n",
               mode_name(), static_cast<unsigned long long>(state.count),
               static_cast<unsigned long long>(state.count),
               static_cast<unsigned long long>(state.hash));
}

uint64_t fingerprint() {
  return state.finished ? state.hash : 0;
}

bool replay_verified() {
  return state.mode == Mode::Replay && state.finished;
}

uint64_t records() {
  return state.count;
}
}  // namespace boot_replay
