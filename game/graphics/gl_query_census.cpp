#include "game/graphics/gl_query_census.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <map>
#include <mutex>
#include <string>

#include <cstdlib>
#include <dlfcn.h>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "game/system/autoport_proof.h"
#include "third-party/glad/include/glad/glad.h"

namespace gl_query_census {
namespace {

// Les familles comptees a la porte. Une somme sans ses termes est invérifiable : chaque famille
// sort aussi sous son propre nom.
enum Family {
  kGetError = 0,
  kGetLimit,  // glGetIntegerv d'une valeur CONSTANTE du contexte (limite, alignement, format)
  kReadPixels,
  kFinish,
  kMapBufferRead,
  kFamilyCount,
};
const char* const kFamilyKey[kFamilyCount] = {
    "gl_unarmed_q_geterror", "gl_unarmed_q_getlimit", "gl_unarmed_q_readpixels",
    "gl_unarmed_q_finish",   "gl_unarmed_q_mapbufferread",
};

// LA LISTE BLANCHE DE L'IDIOME SAUVEGARDE/RESTAURATION. Un `pname` absent d'ici est compte a la
// porte : la polarite sure est celle qui fait rougir.
bool is_state_restore_pname(GLenum p) {
  switch (p) {
    // liaisons
    case GL_DRAW_FRAMEBUFFER_BINDING:  // == GL_FRAMEBUFFER_BINDING
    case GL_READ_FRAMEBUFFER_BINDING:
    case GL_RENDERBUFFER_BINDING:
    case GL_CURRENT_PROGRAM:
    case GL_VERTEX_ARRAY_BINDING:
    case GL_ARRAY_BUFFER_BINDING:
    case GL_ELEMENT_ARRAY_BUFFER_BINDING:
    case GL_UNIFORM_BUFFER_BINDING:
    case GL_PIXEL_PACK_BUFFER_BINDING:
    case GL_PIXEL_UNPACK_BUFFER_BINDING:
    case GL_TEXTURE_BINDING_2D:
    case GL_TEXTURE_BINDING_2D_ARRAY:
    case GL_TEXTURE_BINDING_3D:
    case GL_TEXTURE_BINDING_CUBE_MAP:
    case GL_SAMPLER_BINDING:
    case GL_ACTIVE_TEXTURE:
    // cadrage et cible de lecture/ecriture
    case GL_VIEWPORT:
    case GL_SCISSOR_BOX:
    case GL_READ_BUFFER:
    case GL_DRAW_BUFFER0:
    // etat de pixel store
    case GL_PACK_ALIGNMENT:
    case GL_UNPACK_ALIGNMENT:
    case GL_PACK_ROW_LENGTH:
    case GL_PACK_SKIP_ROWS:
    case GL_PACK_SKIP_PIXELS:
    case GL_UNPACK_ROW_LENGTH:
    case GL_UNPACK_SKIP_ROWS:
    case GL_UNPACK_SKIP_PIXELS:
    // etat de melange, de profondeur et de faces
    case GL_DEPTH_FUNC:
    case GL_BLEND_SRC_RGB:
    case GL_BLEND_DST_RGB:
    case GL_BLEND_SRC_ALPHA:
    case GL_BLEND_DST_ALPHA:
    case GL_BLEND_EQUATION_RGB:
    case GL_BLEND_EQUATION_ALPHA:
    case GL_CULL_FACE_MODE:
    case GL_FRONT_FACE:
    case GL_STENCIL_FUNC:
    case GL_STENCIL_REF:
    case GL_STENCIL_VALUE_MASK:
    case GL_STENCIL_WRITEMASK:
      return true;
    default:
      return false;
  }
}

// La profondeur de declaration est PAR FIL : le fil de chargement et le fil de rendu partagent
// le contexte mais pas leurs intentions.
thread_local int t_declared_depth = 0;

std::atomic<uint64_t> g_frame_unarmed[kFamilyCount];  // seau de l'image en cours
std::atomic<uint64_t> g_total_unarmed[kFamilyCount];  // depuis le debut de la course
std::atomic<uint64_t> g_total_declared{0};
std::atomic<uint64_t> g_frame_state_restore{0};
std::atomic<uint64_t> g_total_state_restore{0};
std::atomic<uint64_t> g_max_state_restore{0};
std::atomic<uint64_t> g_write_maps{0};
std::atomic<uint64_t> g_selftest{0};
std::atomic<uint64_t> g_hooked{0};
std::atomic<uint64_t> g_reinstalls{0};
std::atomic<uint64_t> g_max_unarmed{0};
std::atomic<uint64_t> g_frames{0};
// Le seau que l'on n'attribue a aucune image : tout ce qui precede la PREMIERE frontiere
// d'image, c'est-a-dire l'initialisation du contexte (limites du pilote, extensions). L'item
// parle des sondes « en production » ; ce chiffre est publie a part, jamais efface.
std::atomic<uint64_t> g_boot_unarmed{0};

// LES SITES DECLARES, SANS VERROU. `Armed` est pose dans des chemins chauds (une texture geree
// chargee, une image d'AO, chaque appel de `refset_capture_if_step`) : un mutex par entree
// ajouterait, dans un item de PERFORMANCE, exactement le genre de cout qu'il retire. Les noms
// sont des litteraux de chaine, donc comparables par ADRESSE ; deux unites de compilation qui
// porteraient le meme texte prendraient deux places, et la publication les dedoublonne.
constexpr int kMaxSites = 48;
std::atomic<const char*> g_site_names[kMaxSites];
std::atomic<uint64_t> g_site_hits[kMaxSites];

// ATTRIBUTION DES APPELS NON DECLARES. Une porte rouge doit nommer sa cause : on retient
// l'adresse de retour de chaque appel non declare, et on publie la plus frequente.
constexpr int kCallerSlots = 12;
std::mutex g_caller_mutex;
const void* g_caller_addr[kCallerSlots] = {nullptr};
uint64_t g_caller_hits[kCallerSlots] = {0};

void note_caller(const void* ra) {
  std::lock_guard<std::mutex> lock(g_caller_mutex);
  for (int i = 0; i < kCallerSlots; i++) {
    if (g_caller_addr[i] == ra) {
      g_caller_hits[i]++;
      return;
    }
    if (!g_caller_addr[i]) {
      g_caller_addr[i] = ra;
      g_caller_hits[i] = 1;
      return;
    }
  }
  // Toutes les places prises : on remplace la moins frequente, pour que la sortie converge vers
  // les gros contributeurs plutot que vers les premiers arrives.
  int worst = 0;
  for (int i = 1; i < kCallerSlots; i++) {
    if (g_caller_hits[i] < g_caller_hits[worst]) {
      worst = i;
    }
  }
  if (g_caller_hits[worst] <= 1) {
    g_caller_addr[worst] = ra;
    g_caller_hits[worst] = 1;
  }
}

// Les vrais pointeurs, sauves au moment de l'installation.
PFNGLGETERRORPROC s_real_getError = nullptr;
PFNGLGETINTEGERVPROC s_real_getIntegerv = nullptr;
PFNGLGETINTEGER64VPROC s_real_getInteger64v = nullptr;
PFNGLREADPIXELSPROC s_real_readPixels = nullptr;
PFNGLFINISHPROC s_real_finish = nullptr;
PFNGLMAPBUFFERRANGEPROC s_real_mapBufferRange = nullptr;

inline void note(Family f, const void* ra) {
  if (t_declared_depth > 0) {
    g_total_declared.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  g_frame_unarmed[f].fetch_add(1, std::memory_order_relaxed);
  g_total_unarmed[f].fetch_add(1, std::memory_order_relaxed);
  note_caller(ra);
}

inline void note_state_restore() {
  if (t_declared_depth > 0) {
    g_total_declared.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  g_frame_state_restore.fetch_add(1, std::memory_order_relaxed);
  g_total_state_restore.fetch_add(1, std::memory_order_relaxed);
}

GLenum APIENTRY relay_getError(void) {
  note(kGetError, __builtin_return_address(0));
  return s_real_getError();
}
void APIENTRY relay_getIntegerv(GLenum pname, GLint* data) {
  if (is_state_restore_pname(pname)) {
    note_state_restore();
  } else {
    note(kGetLimit, __builtin_return_address(0));
  }
  s_real_getIntegerv(pname, data);
}
void APIENTRY relay_getInteger64v(GLenum pname, GLint64* data) {
  if (is_state_restore_pname(pname)) {
    note_state_restore();
  } else {
    note(kGetLimit, __builtin_return_address(0));
  }
  s_real_getInteger64v(pname, data);
}
void APIENTRY relay_readPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum fmt, GLenum type,
                               void* pixels) {
  note(kReadPixels, __builtin_return_address(0));
  s_real_readPixels(x, y, w, h, fmt, type, pixels);
}
void APIENTRY relay_finish(void) {
  note(kFinish, __builtin_return_address(0));
  s_real_finish();
}
void* APIENTRY relay_mapBufferRange(GLenum target, GLintptr offset, GLsizeiptr length,
                                    GLbitfield access) {
  // Seule la LECTURE fait attendre : le pilote doit avoir fini d'ecrire pour rendre le pointeur.
  // Un mappage d'ECRITURE est un televersement ordinaire. Son compte est publie a cote pour que
  // l'exclusion soit VISIBLE — et il vaut zero dans cet arbre, ou les cinq mappages sont tous
  // des lectures.
  if (access & GL_MAP_READ_BIT) {
    note(kMapBufferRead, __builtin_return_address(0));
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

void publish_top_site() {
  const void* worst_addr = nullptr;
  uint64_t worst_hits = 0;
  {
    std::lock_guard<std::mutex> lock(g_caller_mutex);
    for (int i = 0; i < kCallerSlots; i++) {
      if (g_caller_addr[i] && g_caller_hits[i] > worst_hits) {
        worst_hits = g_caller_hits[i];
        worst_addr = g_caller_addr[i];
      }
    }
  }
  if (!worst_addr) {
    // Une cle de TEXTE ne se vide jamais toute seule : sans coupable, on ECRIT qu'il n'y en a pas.
    autoport_proof::publish_text("gl_unarmed_top_site", "-");
    autoport_proof::publish("gl_unarmed_top_site_hits", 0);
    return;
  }
  char out[192];
  Dl_info info;
  std::memset(&info, 0, sizeof(info));
  if (dladdr(worst_addr, &info) && info.dli_fname) {
    const char* base = std::strrchr(info.dli_fname, '/');
    base = base ? base + 1 : info.dli_fname;
    if (info.dli_sname) {
      std::snprintf(out, sizeof(out), "%s:%s+0x%lx", base, info.dli_sname,
                    (unsigned long)((const char*)worst_addr - (const char*)info.dli_saddr));
    } else {
      std::snprintf(out, sizeof(out), "%s+0x%lx", base,
                    (unsigned long)((const char*)worst_addr - (const char*)info.dli_fbase));
    }
  } else {
    std::snprintf(out, sizeof(out), "addr_%p", worst_addr);
  }
  autoport_proof::publish_text("gl_unarmed_top_site", out);
  autoport_proof::publish("gl_unarmed_top_site_hits", worst_hits);
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
  // L'EXCLUSION, CHIFFREE. L'idiome sauvegarde/restauration n'est pas compte a la porte ; il est
  // publie ici, par image et en total. Un chantier qui le reduit le verra baisser.
  autoport_proof::publish("gl_state_restore_queries_per_frame",
                          g_max_state_restore.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_state_restore_queries_total",
                          g_total_state_restore.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_mapbuffer_write_only_calls",
                          g_write_maps.load(std::memory_order_relaxed));
  // LES TEMOINS. Un zero a la porte ne vaut que si l'instrument compte.
  autoport_proof::publish("gl_query_census_hooked", g_hooked.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_query_census_selftest", g_selftest.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_query_census_reinstalls",
                          g_reinstalls.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_query_census_frames", g_frames.load(std::memory_order_relaxed));
  autoport_proof::publish("gl_armed_driver_queries_total",
                          g_total_declared.load(std::memory_order_relaxed));
  std::string list;
  for (int i = 0; i < kMaxSites && list.size() < 150; i++) {
    const char* name = g_site_names[i].load(std::memory_order_acquire);
    if (!name) {
      break;
    }
    bool already = false;
    for (int j = 0; j < i; j++) {
      const char* prev = g_site_names[j].load(std::memory_order_acquire);
      if (prev && std::strcmp(prev, name) == 0) {
        already = true;
        break;
      }
    }
    if (already) {
      continue;
    }
    if (!list.empty()) {
      list += ',';
    }
    list += name;
  }
  autoport_proof::publish_text("gl_query_declared_sites", list.empty() ? "-" : list.c_str());
  publish_top_site();
}

bool read_knob(const char* env, const char* prop) {
  if (const char* e = std::getenv(env)) {
    return e[0] && !(e[0] == '0' && e[1] == 0);
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    return !(buf[0] == '0' && buf[1] == 0);
  }
#else
  (void)prop;
#endif
  return false;
}

}  // namespace

int limit(unsigned int pname) {
  static std::mutex s_mutex;
  static std::map<unsigned int, int> s_cache;
  {
    std::lock_guard<std::mutex> lock(s_mutex);
    auto it = s_cache.find(pname);
    if (it != s_cache.end()) {
      return it->second;
    }
  }
  GLint v = 0;
  {
    Armed scope("gl-limit-cache");
    glGetIntegerv((GLenum)pname, &v);
  }
  std::lock_guard<std::mutex> lock(s_mutex);
  s_cache[pname] = (int)v;
  return (int)v;
}

bool probes_armed() {
  static const bool s_on = read_knob("OG_GL_PROBE", "debug.opengoal.glprobe");
  return s_on;
}

Armed::Armed(const char* site) : m_site(site && site[0] ? site : "__unnamed") {
  if (t_declared_depth++ != 0) {
    return;  // deja dans un bloc declare : c'est le bloc EXTERIEUR qui porte le nom
  }
  for (int i = 0; i < kMaxSites; i++) {
    const char* cur = g_site_names[i].load(std::memory_order_acquire);
    if (cur == m_site) {
      g_site_hits[i].fetch_add(1, std::memory_order_relaxed);
      return;
    }
    if (!cur) {
      const char* expected = nullptr;
      if (g_site_names[i].compare_exchange_strong(expected, m_site, std::memory_order_acq_rel)) {
        g_site_hits[i].fetch_add(1, std::memory_order_relaxed);
        return;
      }
      i--;  // un autre fil a pris la place : on relit CETTE case avant de passer a la suivante
    }
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
  // dereferencerait un nul transformerait une entree absente en plantage. Le pointeur courant
  // peut deja etre l'un de nos relais (rechargement partiel) : dans ce cas le vrai pointeur
  // deja sauve reste le bon.
#define AP_HOOK(slot, saved, thunk)  \
  if ((slot) && (slot) != (thunk)) { \
    (saved) = (slot);                \
  }                                  \
  if (saved) {                       \
    (slot) = (thunk);                \
    hooked++;                        \
  }
  AP_HOOK(glad_glGetError, s_real_getError, relay_getError)
  AP_HOOK(glad_glGetIntegerv, s_real_getIntegerv, relay_getIntegerv)
  AP_HOOK(glad_glGetInteger64v, s_real_getInteger64v, relay_getInteger64v)
  AP_HOOK(glad_glReadPixels, s_real_readPixels, relay_readPixels)
  AP_HOOK(glad_glFinish, s_real_finish, relay_finish)
  AP_HOOK(glad_glMapBufferRange, s_real_mapBufferRange, relay_mapBufferRange)
#undef AP_HOOK
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
  const uint64_t state_bucket = g_frame_state_restore.exchange(0, std::memory_order_relaxed);
  if (n == 1) {
    // Tout ce qui precede la premiere image est de l'INITIALISATION de contexte. Publie a part
    // sous `gl_unarmed_driver_queries_boot` : rien n'est efface, seulement range ailleurs.
    // Les coupables retenus pendant l'initialisation sont oublies ici, sinon `gl_unarmed_top_site`
    // nommerait pour toujours une fonction d'init au lieu du site qui tire EN PRODUCTION.
    g_boot_unarmed.store(bucket, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(g_caller_mutex);
    for (int i = 0; i < kCallerSlots; i++) {
      g_caller_addr[i] = nullptr;
      g_caller_hits[i] = 0;
    }
  } else {
    uint64_t prev = g_max_unarmed.load(std::memory_order_relaxed);
    while (bucket > prev &&
           !g_max_unarmed.compare_exchange_weak(prev, bucket, std::memory_order_relaxed)) {
    }
    prev = g_max_state_restore.load(std::memory_order_relaxed);
    while (state_bucket > prev &&
           !g_max_state_restore.compare_exchange_weak(prev, state_bucket,
                                                      std::memory_order_relaxed)) {
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
