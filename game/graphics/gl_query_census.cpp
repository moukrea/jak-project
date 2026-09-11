#include "game/graphics/gl_query_census.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <map>
#include <mutex>
#include <string>

#include "game/system/autoport_proof.h"
#include "third-party/glad/include/glad/glad.h"

namespace gl_query_census {
namespace {

// Les familles comptees. L'ordre sert aux cles publiees : une somme sans ses termes est
// invérifiable, donc chaque famille sort aussi sous son propre nom.
enum Family {
  kGetError = 0,
  kGetIntegerv,
  kReadPixels,
  kFinish,
  kMapBufferRange,
  kFamilyCount,
};
const char* const kFamilyKey[kFamilyCount] = {
    "gl_unarmed_q_geterror", "gl_unarmed_q_getintegerv", "gl_unarmed_q_readpixels",
    "gl_unarmed_q_finish",   "gl_unarmed_q_mapbufferrange",
};

// La profondeur de declaration est PAR FIL : le fil de chargement et le fil de rendu partagent
// le contexte mais pas leurs intentions.
thread_local int t_declared_depth = 0;

std::atomic<uint64_t> g_frame_unarmed[kFamilyCount];   // seau de l'image en cours
std::atomic<uint64_t> g_total_unarmed[kFamilyCount];   // depuis le debut de la course
std::atomic<uint64_t> g_total_declared{0};
std::atomic<uint64_t> g_selftest{0};
std::atomic<uint64_t> g_hooked{0};
std::atomic<uint64_t> g_reinstalls{0};
std::atomic<uint64_t> g_max_unarmed{0};
std::atomic<uint64_t> g_frames{0};
// Le seau que l'on n'attribue a aucune image : tout ce qui precede la PREMIERE frontiere
// d'image, c'est-a-dire l'initialisation du contexte (limites du pilote, extensions). L'item
// parle des sondes « en production » ; ce chiffre est publie a part, jamais efface.
std::atomic<uint64_t> g_boot_unarmed{0};
std::atomic<uint64_t> g_write_maps{0};

std::mutex g_sites_mutex;
std::map<std::string, uint64_t> g_declared_sites;

// Les vrais pointeurs, sauves au moment de l'installation.
PFNGLGETERRORPROC s_real_getError = nullptr;
PFNGLGETINTEGERVPROC s_real_getIntegerv = nullptr;
PFNGLGETINTEGER64VPROC s_real_getInteger64v = nullptr;
PFNGLREADPIXELSPROC s_real_readPixels = nullptr;
PFNGLFINISHPROC s_real_finish = nullptr;
PFNGLMAPBUFFERRANGEPROC s_real_mapBufferRange = nullptr;

inline void note(Family f) {
  if (t_declared_depth > 0) {
    g_total_declared.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  g_frame_unarmed[f].fetch_add(1, std::memory_order_relaxed);
  g_total_unarmed[f].fetch_add(1, std::memory_order_relaxed);
}

GLenum APIENTRY relay_getError(void) {
  note(kGetError);
  return s_real_getError();
}
void APIENTRY relay_getIntegerv(GLenum pname, GLint* data) {
  note(kGetIntegerv);
  s_real_getIntegerv(pname, data);
}
void APIENTRY relay_getInteger64v(GLenum pname, GLint64* data) {
  note(kGetIntegerv);
  s_real_getInteger64v(pname, data);
}
void APIENTRY relay_readPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum fmt, GLenum type,
                               void* pixels) {
  note(kReadPixels);
  s_real_readPixels(x, y, w, h, fmt, type, pixels);
}
void APIENTRY relay_finish(void) {
  note(kFinish);
  s_real_finish();
}
void* APIENTRY relay_mapBufferRange(GLenum target, GLintptr offset, GLsizeiptr length,
                                    GLbitfield access) {
  // Seule la LECTURE fait attendre : le pilote doit avoir fini d'ecrire pour rendre le pointeur.
  // Un mappage d'ECRITURE avec INVALIDATE / UNSYNCHRONIZED est un televersement ordinaire, et le
  // compter rendrait la porte inatteignable sans toucher au chemin de rendu — donc faux.
  // Le compte des mappages d'ecriture est publie a cote pour que l'exclusion soit VISIBLE.
  if (access & GL_MAP_READ_BIT) {
    note(kMapBufferRange);
  } else {
    g_write_maps.fetch_add(1, std::memory_order_relaxed);
  }
  return s_real_mapBufferRange(target, offset, length, access);
}

// Vrai quand les relais sont en place. glad recharge ses pointeurs quand le contexte Android est
// recree : sans cette verification, les requetes redeviendraient invisibles en silence.
bool relays_in_place() {
  return glad_glGetError == relay_getError && glad_glGetIntegerv == relay_getIntegerv &&
         glad_glReadPixels == relay_readPixels && glad_glFinish == relay_finish &&
         glad_glMapBufferRange == relay_mapBufferRange;
}

void publish_now() {
  uint64_t total = 0;
  for (int f = 0; f < kFamilyCount; f++) {
    const uint64_t v = g_total_unarmed[f].load(std::memory_order_relaxed);
    autoport_proof::publish(kFamilyKey[f], v);
    total += v;
  }
  // LA PORTE. Le PIRE seau d'image retenu sur la course, pas une moyenne : une moyenne sur des
  // centaines d'images ecraserait une sonde qui ne tire qu'une image sur 300 (la sonde A42 en
  // est exactement une).
  autoport_proof::publish("gl_unarmed_driver_queries_per_frame",
                          g_max_unarmed.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_unarmed_driver_queries_total", total);
  autoport_proof::publish("gl_unarmed_driver_queries_boot",
                          g_boot_unarmed.load(std::memory_order_relaxed));
  // L'EXCLUSION, ECRITE. Les mappages d'ECRITURE ne font pas attendre et ne sont pas comptes a
  // la porte : leur nombre est publie pour que l'exclusion soit lisible et non silencieuse.
  autoport_proof::publish("gl_mapbuffer_write_only_calls",
                          g_write_maps.load(std::memory_order_relaxed));
  // LES TEMOINS. Un zero a la porte ne vaut que si l'instrument compte : `hooked` dit que les
  // pointeurs sont remplaces, `selftest` qu'un relais s'est reellement execute, et
  // `armed_total` que les sondes declarees (spec, contournement F1a) passent bien par lui.
  autoport_proof::publish("gl_query_census_hooked", g_hooked.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_query_census_selftest", g_selftest.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_query_census_reinstalls",
                          g_reinstalls.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_query_census_frames", g_frames.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_armed_driver_queries_total",
                          g_total_declared.load(std::memory_order_relaxed));
  std::string list;
  {
    std::lock_guard<std::mutex> lock(g_sites_mutex);
    for (const auto& kv : g_declared_sites) {
      if (list.size() >= 160) {
        break;
      }
      if (!list.empty()) {
        list += ',';
      }
      list += kv.first;
    }
  }
  // Une cle de TEXTE ne se vide jamais toute seule : liste vide => "-".
  autoport_proof::publish_text("gl_query_declared_sites", list.empty() ? "-" : list.c_str());
}

}  // namespace

Armed::Armed(const char* site) : m_site(site && site[0] ? site : "__unnamed") {
  t_declared_depth++;
  if (t_declared_depth == 1) {
    std::lock_guard<std::mutex> lock(g_sites_mutex);
    g_declared_sites[m_site]++;
  }
}

Armed::~Armed() {
  t_declared_depth--;
}

void install() {
  if (relays_in_place()) {
    return;
  }
  static bool s_was_installed = false;
  if (s_was_installed) {
    g_reinstalls.fetch_add(1, std::memory_order_relaxed);
  }
  uint64_t hooked = 0;
  // On ne remplace QUE ce que glad a resolu : ecraser un pointeur nul par un relais qui
  // dereferencerait un nul transformerait une entree absente en plantage.
  // Le pointeur courant peut deja etre l'un de nos relais (rechargement partiel) : dans ce cas
  // le vrai pointeur deja sauve reste le bon.
  if (glad_glGetError && glad_glGetError != relay_getError) {
    s_real_getError = glad_glGetError;
  }
  if (s_real_getError) {
    glad_glGetError = relay_getError;
    hooked++;
  }
  if (glad_glGetIntegerv && glad_glGetIntegerv != relay_getIntegerv) {
    s_real_getIntegerv = glad_glGetIntegerv;
  }
  if (s_real_getIntegerv) {
    glad_glGetIntegerv = relay_getIntegerv;
    hooked++;
  }
  if (glad_glGetInteger64v && glad_glGetInteger64v != relay_getInteger64v) {
    s_real_getInteger64v = glad_glGetInteger64v;
  }
  if (s_real_getInteger64v) {
    glad_glGetInteger64v = relay_getInteger64v;
    hooked++;
  }
  if (glad_glReadPixels && glad_glReadPixels != relay_readPixels) {
    s_real_readPixels = glad_glReadPixels;
  }
  if (s_real_readPixels) {
    glad_glReadPixels = relay_readPixels;
    hooked++;
  }
  if (glad_glFinish && glad_glFinish != relay_finish) {
    s_real_finish = glad_glFinish;
  }
  if (s_real_finish) {
    glad_glFinish = relay_finish;
    hooked++;
  }
  if (glad_glMapBufferRange && glad_glMapBufferRange != relay_mapBufferRange) {
    s_real_mapBufferRange = glad_glMapBufferRange;
  }
  if (s_real_mapBufferRange) {
    glad_glMapBufferRange = relay_mapBufferRange;
    hooked++;
  }
  g_hooked.store(hooked, std::memory_order_relaxed);
  s_was_installed = true;

  // AUTO-TEST. Un appel deliberé, DANS un bloc declare, a travers la macro glad : si le relais
  // n'etait pas en place, `gl_query_census_selftest` resterait a zero et le zero de la porte
  // serait celui d'un instrument mort. C'est le seul appel pilote que ce module emet lui-meme,
  // et il a lieu une fois, a l'initialisation du contexte.
  if (s_real_getError) {
    const uint64_t before = g_total_declared.load(std::memory_order_relaxed);
    {
      Armed scope("gl-query-census-selftest");
      (void)glGetError();
    }
    if (g_total_declared.load(std::memory_order_relaxed) > before) {
      g_selftest.fetch_add(1, std::memory_order_relaxed);
    }
  }
  publish_now();
}

void frame_boundary() {
  // Un rechargement de contexte remet les vrais pointeurs : on le voit ici et on repose les
  // relais dans l'image qui suit, en le DISANT (`gl_query_census_reinstalls`).
  if (!relays_in_place()) {
    install();
  }
  const uint64_t n = g_frames.fetch_add(1, std::memory_order_relaxed) + 1;
  uint64_t bucket = 0;
  for (int f = 0; f < kFamilyCount; f++) {
    bucket += g_frame_unarmed[f].exchange(0, std::memory_order_relaxed);
  }
  if (n == 1) {
    // Tout ce qui precede la premiere image est de l'INITIALISATION de contexte. Publie a part
    // sous `gl_unarmed_driver_queries_boot` : rien n'est efface, seulement range ailleurs.
    g_boot_unarmed.store(bucket, std::memory_order_relaxed);
  } else {
    uint64_t prev = g_max_unarmed.load(std::memory_order_relaxed);
    while (bucket > prev &&
           !g_max_unarmed.compare_exchange_weak(prev, bucket, std::memory_order_relaxed)) {
    }
  }
  if ((n % 60) == 0) {
    publish_now();
  }
}

uint64_t max_unarmed_per_frame() {
  return g_max_unarmed.load(std::memory_order_relaxed);
}

uint64_t total_unarmed() {
  uint64_t total = 0;
  for (int f = 0; f < kFamilyCount; f++) {
    total += g_total_unarmed[f].load(std::memory_order_relaxed);
  }
  return total;
}

}  // namespace gl_query_census
