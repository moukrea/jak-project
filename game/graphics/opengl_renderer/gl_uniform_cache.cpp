#include "gl_uniform_cache.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

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
// LE RECENSEMENT PAR NOM (gl-uniforms-dead-seven). Une entree par nom d'uniforme VU, quel que
// soit le programme vise. `readers` est le nombre de programmes lies qui rendent un emplacement
// pour ce nom : c'est le compilateur GLSL qui repond, pas nous. `readers == 0` = personne ne le
// lit dans tout l'arbre.
struct NameStat {
  uint64_t pushes = 0;        // depuis le debut de la course, toutes images confondues
  uint64_t pushes_frame = 0;  // image en cours
  int readers = -1;           // -1 = pas encore classe
  uint32_t epoch = 0;         // version du parc de programmes au moment du classement
};

struct Entry {
  GLint loc;
  std::string text;  // le contenu du litteral, pour verifier l'adresse
  NameStat* stat;    // le recensement du NOM (partage entre tous les programmes)
};

std::unordered_map<Key, Entry, KeyHash> g_cache;

// `unordered_map` ne deplace pas ses noeuds : un `NameStat*` reste valide apres rehachage.
std::unordered_map<std::string, NameStat> g_names;
std::vector<GLuint> g_programs;
uint32_t g_prog_epoch = 1;

// Compteurs : image courante (en cours d'accumulation) et image precedente (publiee).
uint64_t g_misses_frame = 0, g_hits_frame = 0;
uint64_t g_misses_total = 0, g_hits_total = 0;
uint64_t g_frames = 0, g_frames_with_miss = 0, g_last_frame_with_miss = 0;

// --------------------------------------------------------------- gl-uniforms-dead-seven ----
constexpr const char* kItemId = "gl-uniforms-dead-seven";
AUTOPORT_FEATURE_SITE(kItemId);

// Les sept nommes par l'item, recenses PAR LEUR NOM meme quand plus personne ne les pousse : un
// recensement qui ne porterait que sur ce qui est encore pousse serait vide apres la correction,
// et la porte passerait au vert par INACTION. Ils sont donc inscrits d'office, avec zero poussee,
// et le pilote repond pour chacun combien de programmes le lisent.
const char* const kSeven[] = {"u_pbr_sun_dir",    "u_pbr_sun_color",       "u_rt_ambient_key",
                              "u_rt_ambient_contrast", "u_rt_shadow_mul",  "u_rt_tint_shadow",
                              "u_pbr_uv_tile"};

// TEMOIN MORT SEME. Un nom qu'aucun shader ne declare, pousse par le MEME `loc()` que tout le
// reste : il est mort ET pousse. Sans lui, `dead_uniform_pushes=0` ne separerait pas « il n'y a
// plus rien a compter » de « le compteur ne tourne pas ». Il est exclu de la porte par son nom,
// et sa poussee est publiee a part.
// LES POUSSEES GARDEES, NOMMEES, JAMAIS SILENCIEUSEMENT EXCLUES.
// Un uniforme que le pilote dit sans lecteur ne se retire pas quand son lecteur EXISTE ailleurs :
// le retirer cimenterait une perte au lieu de nettoyer une dette. `u_rt_sh[0]` — l'ambiante
// directionnelle SH (L2), validee par l'owner — est lu par `rt_sh_ambient()`.
// MISE A JOUR lighting-legacy-purge, 2026-09-12. Ses deux appelants d'alors, `pbr_fused.glsl:726`
// et `pbr_helpers.glsl:221`, ont QUITTE L'ARBRE avec la pile de matiere. La fonction n'est pas
// morte avec eux : elle est appelee par le composite SURVIVANT de `shade.glsl` (le bras OMBRE de
// la modulation du cuit), et `lighting_legacy_sh_readers` compte les programmes LIES qui la
// lisent — 4 sur la course x86 du 12/09. Cette entree reste donc ce qu'elle etait : une garde
// contre un retrait par confusion, pas le constat d'une perte.
// La preuve publie le compte ET la liste (`kept_uniform_pushes`, `kept_uniform_list`) : ce qui
// est garde se lit, il ne disparait pas du denominateur.
const char* const kKept[] = {"u_rt_sh[0]"};

bool is_kept(const std::string& name) {
  for (const char* k : kKept) {
    if (name == k) {
      return true;
    }
  }
  return false;
}

constexpr const char* kSentinelDead = "u_autoport_dead_sentinel";
// TEMOIN VIVANT SEME : l'echantillonneur de base, lu par tous les shaders textures. S'il tombait
// a zero lecteur, c'est le classement qui serait casse, pas le decor.
constexpr const char* kSentinelLive = "tex_T0";

int readers_of(const char* name) {
  int n = 0;
  for (GLuint p : g_programs) {
    if (glGetUniformLocation(p, name) != -1) {
      n++;
    }
  }
  return n;
}

// Publie `<prefixe><nom><suffixe>=<valeur>`.
void publish_named(const char* prefix, const char* name, const char* suffix, uint64_t v) {
  char key[160];
  std::snprintf(key, sizeof(key), "%s%s%s", prefix, name, suffix);
  autoport_proof::publish(key, v);
}

void census_frame() {
  if (!autoport_proof::feature_is(kItemId) || g_programs.empty()) {
    return;
  }
  // Le temoin mort part par le chemin normal, une poussee par image.
  (void)loc(g_programs[0], kSentinelDead);
  for (const char* n : kSeven) {
    g_names[std::string(n)];  // inscrit sans poussee : il sera classe comme les autres
  }
  g_names[std::string(kSentinelLive)];

  uint64_t names = 0, pushes_total = 0, live_names = 0, dead_names = 0, dead_pushes = 0;
  uint64_t dead_pushes_frame = 0, probe_dead_unpushed = 0, sentinel_pushes = 0;
  uint64_t kept_names = 0, kept_pushes = 0;
  int sentinel_readers = -1;
  std::string dead_list, kept_list;
  for (auto& kv : g_names) {
    NameStat& st = kv.second;
    if (st.epoch != g_prog_epoch) {  // le parc de programmes a bouge : on redemande au pilote
      st.readers = readers_of(kv.first.c_str());
      st.epoch = g_prog_epoch;
    }
    names++;
    pushes_total += st.pushes;
    if (kv.first == kSentinelDead) {
      sentinel_pushes = st.pushes;
      sentinel_readers = st.readers;
      continue;
    }
    if (st.readers > 0) {
      live_names++;
      continue;
    }
    if (st.pushes == 0) {
      probe_dead_unpushed++;  // recense, jamais pousse : les sept apres correction
      continue;
    }
    if (is_kept(kv.first)) {
      kept_names++;
      kept_pushes += st.pushes;
      if (!kept_list.empty()) {
        kept_list += ",";
      }
      kept_list += kv.first;
      continue;
    }
    dead_names++;
    dead_pushes += st.pushes;
    dead_pushes_frame += st.pushes_frame;
    if (dead_list.size() < 300) {
      if (!dead_list.empty()) {
        dead_list += ",";
      }
      dead_list += kv.first;
    }
  }

  autoport_proof::publish("dead_uniform_pushes", dead_pushes);
  autoport_proof::publish("dead_uniform_pushes_frame", dead_pushes_frame);
  autoport_proof::publish("dead_uniform_names", dead_names);
  autoport_proof::publish_text("dead_uniform_list", dead_list.empty() ? "-" : dead_list.c_str());
  autoport_proof::publish("uniform_names_seen", names);
  autoport_proof::publish("uniform_pushes_total", pushes_total);
  autoport_proof::publish("uniform_live_names", live_names);
  autoport_proof::publish("uniform_programs_linked", (uint64_t)g_programs.size());
  autoport_proof::publish("probe_dead_unpushed", probe_dead_unpushed);
  autoport_proof::publish("kept_uniform_names", kept_names);
  autoport_proof::publish("kept_uniform_pushes", kept_pushes);
  autoport_proof::publish_text("kept_uniform_list", kept_list.empty() ? "-" : kept_list.c_str());
  autoport_proof::publish("sentinel_dead_pushes", sentinel_pushes);
  autoport_proof::publish("sentinel_dead_readers", (uint64_t)(sentinel_readers < 0 ? 9999 : sentinel_readers));
  autoport_proof::publish("sentinel_live_readers", (uint64_t)g_names[std::string(kSentinelLive)].readers);

  uint64_t seven_unread = 0, seven_pushes = 0;
  for (const char* n : kSeven) {
    const NameStat& st = g_names[std::string(n)];
    publish_named("dead7_", n, "_readers", (uint64_t)(st.readers < 0 ? 9999 : st.readers));
    publish_named("dead7_", n, "_pushes", st.pushes);
    if (st.readers == 0) {
      seven_unread++;
    }
    seven_pushes += st.pushes;
  }
  autoport_proof::publish("dead7_probed", (uint64_t)(sizeof(kSeven) / sizeof(kSeven[0])));
  autoport_proof::publish("dead7_unread", seven_unread);
  autoport_proof::publish("dead7_pushes", seven_pushes);

  // `hits` est PARTAGE par tout le binaire : ne le remplir que quand le harnais mesure CET item.
  autoport_proof::note_hit_for(kItemId, 1);

  for (auto& kv : g_names) {
    kv.second.pushes_frame = 0;
  }
}

}  // namespace

GLint loc(GLuint program, const char* name) {
  const Key k{program, name};
  auto it = g_cache.find(k);
  if (it != g_cache.end() && std::strcmp(it->second.text.c_str(), name) == 0) {
    g_hits_frame++;
    it->second.stat->pushes++;        // AU POINT D'APPEL : un seul passage oblige, pas une liste
    it->second.stat->pushes_frame++;  // de sites connus.
    return it->second.loc;
  }
  const GLint l = glGetUniformLocation(program, name);
  g_misses_frame++;
  NameStat* stat = &g_names[std::string(name)];
  stat->pushes++;
  stat->pushes_frame++;
  g_cache[k] = Entry{l, std::string(name), stat};
  return l;
}

void note_program(GLuint program) {
  if (program == 0) {
    return;
  }
  for (GLuint p : g_programs) {
    if (p == program) {
      g_prog_epoch++;  // identifiant reutilise apres une re-edition de liens : tout se reclasse
      return;
    }
  }
  g_programs.push_back(program);
  g_prog_epoch++;
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
    census_frame();
  }
  g_frames++;
  g_misses_frame = 0;
  g_hits_frame = 0;
}

}  // namespace glu
