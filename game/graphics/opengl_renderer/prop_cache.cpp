#include "prop_cache.h"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unordered_map>

#include "game/system/autoport_proof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace prop_cache {
namespace {

constexpr double kPeriodS = 0.25;

struct Entry {
  std::string text;   // le nom, pour verifier l'adresse du litteral
  std::string value;  // la derniere valeur lue
  bool present = false;
  double last_read_s = -1.0;
};

std::unordered_map<const void*, Entry> g_entries;
uint64_t g_reads_frame = 0, g_served_frame = 0, g_reads_total = 0, g_served_total = 0;
uint64_t g_frames = 0;

double now_s() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

Entry& refresh(const char* name, bool is_env) {
  Entry& e = g_entries[(const void*)name];
  if (e.text.empty() || std::strcmp(e.text.c_str(), name) != 0) {
    e.text = name;
    e.last_read_s = -1.0;
  }
  const double t = now_s();
  if (e.last_read_s < 0.0 || t - e.last_read_s >= kPeriodS) {
    e.last_read_s = t;
    g_reads_frame++;
    if (is_env) {
      const char* v = std::getenv(name);
      e.present = (v != nullptr);
      e.value = v ? v : "";
    } else {
#ifdef __ANDROID__
      char buf[PROP_VALUE_MAX];
      const int n = __system_property_get(name, buf);
      e.present = n > 0;
      e.value = (n > 0) ? std::string(buf, (size_t)n) : std::string();
#else
      e.present = false;
      e.value.clear();
#endif
    }
  } else {
    g_served_frame++;
  }
  return e;
}

}  // namespace

int property_get(const char* name, char* value) {
  const Entry& e = refresh(name, false);
  if (!e.present) {
    if (value) {
      value[0] = '\0';
    }
    return 0;
  }
  if (value) {
    // PROP_VALUE_MAX == 92 sur Android ; la valeur cachee vient d'un tampon de cette taille.
    std::strncpy(value, e.value.c_str(), 91);
    value[91] = '\0';
  }
  return (int)e.value.size();
}

const char* env_get(const char* name) {
  const Entry& e = refresh(name, true);
  return e.present ? e.value.c_str() : nullptr;
}

void frame_begin() {
  if (g_frames > 0) {
    g_reads_total += g_reads_frame;
    g_served_total += g_served_frame;
    autoport_proof::publish("prop_reads_per_frame", g_reads_frame);
    autoport_proof::publish("prop_reads_served_per_frame", g_served_frame);
    autoport_proof::publish("prop_reads_total", g_reads_total);
    autoport_proof::publish("prop_reads_served_total", g_served_total);
    autoport_proof::publish("prop_reads_frames", g_frames);
  }
  g_frames++;
  g_reads_frame = 0;
  g_served_frame = 0;
}

}  // namespace prop_cache
