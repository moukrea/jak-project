#include "game/system/autoport_proof.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <string>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "fmt/core.h"

namespace autoport_proof {
namespace {

std::mutex g_mutex;

// Env sur bureau, PROPRIETE sur Android : l'application ne recoit pas l'environnement du shell
// qui l'a lancee, donc sans le second chemin le harnais ne pourrait rien armer sur l'appareil —
// et une course appareil sans ligne FEATURE serait indistinguable d'une feature qui ne tire pas.
bool read_knob(const char* env, const char* prop, char* out, size_t out_sz) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, out_sz, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, out_sz, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

const std::string& feature_str() {
  static std::string s_id;
  static bool s_read = false;
  if (!s_read) {
    s_read = true;
    char v[128] = {0};
    if (read_knob("AUTOPORT_FEATURE", "debug.opengoal.feature", v, sizeof(v))) {
      s_id = v;
    }
  }
  return s_id;
}

uint64_t g_hits = 0;
uint64_t g_frames = 0;
std::map<std::string, uint64_t> g_keys;

// Cadence de publication. Assez souvent pour qu'une course coupee en plein vol porte quand meme
// ses chiffres, assez rare pour ne pas noyer la trace : 60 images, c'est une seconde sur bureau
// et trois sur le telephone.
constexpr uint64_t kEmitEveryFrames = 60;

bool valid_key(const char* key) {
  if (!key || !key[0]) {
    return false;
  }
  if (!((key[0] >= 'A' && key[0] <= 'Z') || (key[0] >= 'a' && key[0] <= 'z') || key[0] == '_')) {
    return false;
  }
  for (const char* p = key + 1; *p; p++) {
    const char c = *p;
    if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) {
      return false;
    }
  }
  return true;
}

// Ecrit sur stdout, la seule sortie que `proof_run.sh` moissonne des deux cotes : sur bureau elle
// part dans le journal du process, sur Android le lanceur la redirige vers logcat (tag
// GK_STDOUT). `norm()` de proof_run.sh retire les prefixes des deux formats avant d'ancrer sur ^.
void emit_locked() {
  fmt::print("AUTOPORT-FRAMES n={}\n", g_frames);
  const std::string& id = feature_str();
  if (!id.empty()) {
    fmt::print("FEATURE {} armed={} hits={}\n", id, armed() ? 1 : 0, g_hits);
  }
  for (const auto& kv : g_keys) {
    fmt::print("{}={}\n", kv.first, kv.second);
  }
  std::fflush(stdout);
}

}  // namespace

const char* feature_id() {
  return feature_str().c_str();
}

bool feature_is(const char* id) {
  return id && id[0] && feature_str() == id;
}

bool armed() {
  static bool s_armed = true;
  static bool s_read = false;
  if (!s_read) {
    s_read = true;
    // Sans item nomme, il n'y a pas d'ablation possible : le binaire est celui de l'owner, donc
    // ARME. C'est la regle « pas d'acquis sous drapeau optionnel ».
    if (feature_str().empty()) {
      s_armed = true;
    } else {
      char v[32] = {0};
      if (read_knob("AUTOPORT_FEATURE_ARMED", "debug.opengoal.feature.armed", v, sizeof(v))) {
        s_armed = !(v[0] == '0' && v[1] == 0);
      }
    }
  }
  return s_armed;
}

bool armed_for(const char* id) {
  // Sans item nomme : rien n'est sous ablation, tout est arme (le binaire de l'owner).
  // Item nomme mais different du notre : ce n'est pas notre bras d'ablation, on reste arme.
  if (feature_str().empty() || !id || !id[0] || feature_str() != id) {
    return true;
  }
  return armed();
}

void note_hit(uint64_t n) {
  if (!armed()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_hits += n;
}

void publish(const char* key, uint64_t value) {
  if (!valid_key(key)) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_keys[key] = value;
}

void frame_tick() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_frames++;
  if (g_frames % kEmitEveryFrames == 0) {
    emit_locked();
  }
}

void flush() {
  std::lock_guard<std::mutex> lock(g_mutex);
  emit_locked();
}

}  // namespace autoport_proof
