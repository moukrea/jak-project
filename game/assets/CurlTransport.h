#pragma once

// Grecharged-managed-assets: desktop Transport backed by libcurl (already
// vendored and linked into `runtime`). NOT built on Android — that build
// deliberately ships no TLS stack (android/CMakeLists.txt), so the Kotlin
// downloader hands verified files to the shared installer instead.

#include "common/assets/AssetManager.h"

namespace assets {

class CurlTransport : public Transport {
 public:
  bool fetch(const std::string& url, std::string* out, std::string* err) override;
  bool download(const std::string& url,
                const fs::path& dest,
                u64 expected_size,
                std::string* err) override;

  // Seconds before a stalled connection is abandoned (per transfer).
  int timeout_s = 120;
};

}  // namespace assets
