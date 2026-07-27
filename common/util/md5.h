#pragma once

#include <cstddef>
#include <string>

#include "common/common_types.h"

namespace md5 {
// Lowercase-hex MD5 of a byte range, byte-for-byte identical to what coreutils `md5sum` prints for
// the same bytes. Round 30 (delivery): a corrected .meshweld sidecar sat unread inside the APK for
// two rounds while an older external copy was loaded, and no log line named either file. Hashing the
// bytes the runtime ACTUALLY read makes that provable off-device with a one-line `md5sum` on the host.
std::string hex(const u8* data, size_t size);
}  // namespace md5
