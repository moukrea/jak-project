#include "CurlTransport.h"

#include <cstdio>

#include "common/log/log.h"

#include "curl/curl.h"
#include "fmt/core.h"

namespace assets {

namespace {

size_t write_to_string(void* ptr, size_t size, size_t nmemb, void* userdata) {
  auto* s = static_cast<std::string*>(userdata);
  s->append(static_cast<char*>(ptr), size * nmemb);
  return size * nmemb;
}

size_t write_to_file(void* ptr, size_t size, size_t nmemb, void* userdata) {
  auto* f = static_cast<FILE*>(userdata);
  return fwrite(ptr, size, nmemb, f);
}

struct CurlHandle {
  CURL* h = curl_easy_init();
  ~CurlHandle() {
    if (h) {
      curl_easy_cleanup(h);
    }
  }
};

void common_opts(CURL* h, int timeout_s) {
  curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);  // release assets redirect to a CDN
  curl_easy_setopt(h, CURLOPT_TIMEOUT, (long)timeout_s);
  curl_easy_setopt(h, CURLOPT_CONNECTTIMEOUT, 20L);
  curl_easy_setopt(h, CURLOPT_FAILONERROR, 1L);
  curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(h, CURLOPT_USERAGENT, "recharged-asset-manager/1");
  // Abort a transfer that delivers <1 KB/s for 30 s rather than hanging.
  curl_easy_setopt(h, CURLOPT_LOW_SPEED_LIMIT, 1024L);
  curl_easy_setopt(h, CURLOPT_LOW_SPEED_TIME, 30L);
}

}  // namespace

bool CurlTransport::fetch(const std::string& url, std::string* out, std::string* err) {
  CurlHandle c;
  if (!c.h) {
    *err = "curl init failed";
    return false;
  }
  out->clear();
  curl_easy_setopt(c.h, CURLOPT_URL, url.c_str());
  curl_easy_setopt(c.h, CURLOPT_WRITEFUNCTION, write_to_string);
  curl_easy_setopt(c.h, CURLOPT_WRITEDATA, out);
  common_opts(c.h, timeout_s);
  const CURLcode rc = curl_easy_perform(c.h);
  if (rc != CURLE_OK) {
    *err = fmt::format("{} ({})", curl_easy_strerror(rc), url);
    return false;
  }
  return true;
}

bool CurlTransport::download(const std::string& url,
                             const fs::path& dest,
                             u64 expected_size,
                             std::string* err) {
  std::error_code ec;
  u64 have = fs::exists(dest) ? (u64)fs::file_size(dest, ec) : 0;
  if (ec) {
    have = 0;
  }
  if (have > expected_size) {
    fs::remove(dest, ec);  // stale/corrupt leftover
    have = 0;
  }
  if (have == expected_size) {
    return true;  // fully resumed by a previous run
  }

  FILE* f = fopen(dest.string().c_str(), have ? "ab" : "wb");
  if (!f) {
    *err = fmt::format("cannot open {}", dest.string());
    return false;
  }
  CurlHandle c;
  if (!c.h) {
    fclose(f);
    *err = "curl init failed";
    return false;
  }
  curl_easy_setopt(c.h, CURLOPT_URL, url.c_str());
  curl_easy_setopt(c.h, CURLOPT_WRITEFUNCTION, write_to_file);
  curl_easy_setopt(c.h, CURLOPT_WRITEDATA, f);
  if (have) {
    curl_easy_setopt(c.h, CURLOPT_RESUME_FROM_LARGE, (curl_off_t)have);
    lg::info("managed assets: resuming {} at {} / {} bytes", dest.filename().string(), have,
             expected_size);
  }
  common_opts(c.h, timeout_s);
  const CURLcode rc = curl_easy_perform(c.h);
  fclose(f);
  if (rc != CURLE_OK) {
    // Keep the partial file: the next attempt resumes from it. The caller
    // only promotes a file that passes the size + hash check.
    *err = fmt::format("{} ({})", curl_easy_strerror(rc), url);
    return false;
  }
  return true;
}

}  // namespace assets
