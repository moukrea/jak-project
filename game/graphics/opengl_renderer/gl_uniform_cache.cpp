#include "gl_uniform_cache.h"

#include <cstring>
#include <string>
#include <unordered_map>

#include "game/system/autoport_proof.h"

namespace glu {
namespace {

struct Key {
  GLuint program;
  const char* name;  // adresse du litteral
  bool operator==(const Key& o) const { return program == o.program && name == o.name; }
};
struct KeyHash {
  size_t operator()(const Key& k) const {
    return std::hash<const void*>()((const void*)k.name) ^
           (size_t)k.program * 0x9E3779B97F4A7C15ull;
  }
};
struct Entry {
  GLint loc;
  std::string text;  // le contenu du litteral, pour verifier l'adresse
};

std::unordered_map<Key, Entry, KeyHash> g_cache;

// Compteurs : image courante (en cours d'accumulation) et image precedente (publiee).
uint64_t g_misses_frame = 0, g_hits_frame = 0;
uint64_t g_misses_total = 0, g_hits_total = 0;
uint64_t g_frames = 0, g_frames_with_miss = 0, g_last_frame_with_miss = 0;

}  // namespace

GLint loc(GLuint program, const char* name) {
  const Key k{program, name};
  auto it = g_cache.find(k);
  if (it != g_cache.end() && std::strcmp(it->second.text.c_str(), name) == 0) {
    g_hits_frame++;
    return it->second.loc;
  }
  const GLint l = glGetUniformLocation(program, name);
  g_misses_frame++;
  g_cache[k] = Entry{l, std::string(name)};
  return l;
}

void invalidate(GLuint program) {
  for (auto it = g_cache.begin(); it != g_cache.end();) {
    if (it->first.program == program) {
      it = g_cache.erase(it);
    } else {
      ++it;
    }
  }
}

void frame_begin() {
  if (g_frames > 0) {
    // L'image qui vient de se terminer.
    g_misses_total += g_misses_frame;
    g_hits_total += g_hits_frame;
    if (g_misses_frame > 0) {
      g_frames_with_miss++;
      g_last_frame_with_miss = g_frames;
    }
    autoport_proof::publish("uniform_lookups_per_frame", g_misses_frame);
    autoport_proof::publish("uniform_lookups_total", g_misses_total);
    autoport_proof::publish("uniform_lookup_hits_per_frame", g_hits_frame);
    autoport_proof::publish("uniform_lookup_hits_total", g_hits_total);
    autoport_proof::publish("uniform_lookup_frames", g_frames);
    autoport_proof::publish("uniform_lookup_frames_with_miss", g_frames_with_miss);
    autoport_proof::publish("uniform_lookup_last_frame_with_miss", g_last_frame_with_miss);
    autoport_proof::publish("uniform_lookup_entries", (uint64_t)g_cache.size());
  }
  g_frames++;
  g_misses_frame = 0;
  g_hits_frame = 0;
}

}  // namespace glu
