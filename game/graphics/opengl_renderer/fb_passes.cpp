#include "fb_passes.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>

#include "game/system/autoport_proof.h"

namespace fb_passes {

const char* const kItemId = "perf-fbo-passes";

// Ce binaire PORTE un site de l'item. Enregistre au chargement : c'est ce qui separe
// `absent` (aucun site compile) de `declared_unreached` (site compile, jamais atteint).
AUTOPORT_FEATURE_SITE(kItemId);

namespace {

// --- seaux de l'image en cours (fil graphique) --------------------------------------------
std::atomic<uint64_t> g_copies{0};
std::atomic<uint64_t> g_pass_ends{0};
std::atomic<uint64_t> g_pass_ends_no_inval{0};
std::atomic<uint64_t> g_window_clears{0};
std::atomic<uint64_t> g_window_clears_covered{0};
std::atomic<uint64_t> g_window_clear_sites{0};
std::atomic<uint64_t> g_msaa_resolves{0};
std::atomic<uint64_t> g_msaa_resolves_max{0};
std::atomic<uint64_t> g_window_covered_sites{0};

// --- cumuls de la course ------------------------------------------------------------------
std::atomic<uint64_t> g_frames{0};
std::atomic<uint64_t> g_frames_measured{0};
std::atomic<uint64_t> g_nonzero_frames{0};
std::atomic<uint64_t> g_conforming_frames{0};
std::atomic<uint64_t> g_invalidates{0};
std::atomic<uint64_t> g_window_clears_total{0};
std::atomic<uint64_t> g_split_frames{0};
std::atomic<uint64_t> g_window_clear_sites_total{0};
std::atomic<uint64_t> g_window_covered_sites_total{0};
std::atomic<uint64_t> g_direct_frames{0};

// --- maxima par image (la grandeur de la porte en est un) ---------------------------------
std::atomic<uint64_t> g_extra_max{0};
std::atomic<uint64_t> g_extra_boot{0};
std::atomic<uint64_t> g_copies_max{0};
std::atomic<uint64_t> g_copies_min{UINT64_MAX};
std::atomic<uint64_t> g_pass_ends_max{0};
std::atomic<uint64_t> g_no_inval_max{0};
std::atomic<uint64_t> g_covered_clear_max{0};

// --- geometrie et regime ------------------------------------------------------------------
std::mutex g_text_mutex;
constexpr int kMaxSites = 10;
char g_sites[kMaxSites][40];
int g_site_count = 0;
char g_block_reason[40] = "-";
int g_geom[8] = {0, 0, 0, 0, 0, 0, 0, 0};

void bump_max(std::atomic<uint64_t>& slot, uint64_t v) {
  uint64_t prev = slot.load(std::memory_order_relaxed);
  while (v > prev && !slot.compare_exchange_weak(prev, v, std::memory_order_relaxed)) {
  }
}

void bump_min(std::atomic<uint64_t>& slot, uint64_t v) {
  uint64_t prev = slot.load(std::memory_order_relaxed);
  while (v < prev && !slot.compare_exchange_weak(prev, v, std::memory_order_relaxed)) {
  }
}

// La preuve n'est ecrite que quand un MAXIMUM bouge, plus une fois toutes les 60 images.
// Publier a chaque image ferait de l'item de PERF un cout par image ; ne publier qu'a la fin
// perdrait la mesure si la course est tuee. Un maximum qui bouge est publie TOUT DE SUITE :
// c'est ce qui garantit qu'aucune image fautive ne peut disparaitre entre deux emissions
// (la porte lit un `==0`, un defaut perdu serait un faux vert).
void publish_now() {
  autoport_proof::publish("fb_extra_passes_per_frame", g_extra_max.load());
  autoport_proof::publish("fb_extra_passes_boot_frame", g_extra_boot.load());
  autoport_proof::publish("fb_frames_measured", g_frames_measured.load());
  autoport_proof::publish("fb_frames_with_extra_pass", g_nonzero_frames.load());
  autoport_proof::publish("fb_frames_conforming", g_conforming_frames.load());
  const uint64_t cmin = g_copies_min.load();
  autoport_proof::publish("fb_fullscreen_copies_max", g_copies_max.load());
  autoport_proof::publish("fb_fullscreen_copies_min", cmin == UINT64_MAX ? 0 : cmin);
  autoport_proof::publish("fb_pass_ends_max", g_pass_ends_max.load());
  autoport_proof::publish("fb_pass_ends_no_invalidate_max", g_no_inval_max.load());
  autoport_proof::publish("fb_invalidate_calls_total", g_invalidates.load());
  autoport_proof::publish("fb_window_clears_total", g_window_clears_total.load());
  autoport_proof::publish("fb_window_clears_covered_max", g_covered_clear_max.load());
  // Les DEUX denominateurs du clear : combien de fois par course le point de clear a ete
  // atteint, et combien de fois la fenetre y etait integralement recouverte. Un
  // `covered_max=0` avec `covered_sites=0` ne dit rien ; avec `covered_sites=9000` il dit tout.
  autoport_proof::publish("fb_window_clear_sites_total", g_window_clear_sites_total.load());
  autoport_proof::publish("fb_window_covered_sites_total", g_window_covered_sites_total.load());
  autoport_proof::publish("fb_msaa_resolves_max", g_msaa_resolves_max.load());
  autoport_proof::publish("fb_ui_split_frames", g_split_frames.load());
  autoport_proof::publish("fb_ui_direct_frames", g_direct_frames.load());
  autoport_proof::publish("fb_fix_armed", fix_armed() ? 1 : 0);

  std::lock_guard<std::mutex> lock(g_text_mutex);
  autoport_proof::publish("fb_window_w", (uint64_t)(g_geom[0] < 0 ? 0 : g_geom[0]));
  autoport_proof::publish("fb_window_h", (uint64_t)(g_geom[1] < 0 ? 0 : g_geom[1]));
  autoport_proof::publish("fb_draw_region_w", (uint64_t)(g_geom[2] < 0 ? 0 : g_geom[2]));
  autoport_proof::publish("fb_draw_region_h", (uint64_t)(g_geom[3] < 0 ? 0 : g_geom[3]));
  autoport_proof::publish("fb_draw_offset_x", (uint64_t)(g_geom[4] < 0 ? 0 : g_geom[4]));
  autoport_proof::publish("fb_draw_offset_y", (uint64_t)(g_geom[5] < 0 ? 0 : g_geom[5]));
  autoport_proof::publish("fb_scene_w", (uint64_t)(g_geom[6] < 0 ? 0 : g_geom[6]));
  autoport_proof::publish("fb_scene_h", (uint64_t)(g_geom[7] < 0 ? 0 : g_geom[7]));
  // `publish_text` d'une chaine VIDE est ignoree et la cle garde sa valeur d'AVANT : on
  // publie toujours un litteral non vide (publish_text_key_never_clears).
  char joined[kMaxSites * 41 + 2];
  joined[0] = 0;
  if (g_site_count == 0) {
    std::snprintf(joined, sizeof(joined), "-");
  } else {
    size_t at = 0;
    for (int i = 0; i < g_site_count; i++) {
      at +=
          (size_t)std::snprintf(joined + at, sizeof(joined) - at, "%s%s", i ? "," : "", g_sites[i]);
      if (at >= sizeof(joined) - 1) {
        break;
      }
    }
  }
  autoport_proof::publish_text("fb_copy_sites", joined);
  autoport_proof::publish_text("fb_ui_direct_blocked", g_block_reason[0] ? g_block_reason : "-");
}

void remember_site(const char* site) {
  if (!site || !*site) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_text_mutex);
  for (int i = 0; i < g_site_count; i++) {
    if (std::strcmp(g_sites[i], site) == 0) {
      return;
    }
  }
  if (g_site_count < kMaxSites) {
    std::snprintf(g_sites[g_site_count], sizeof(g_sites[0]), "%s", site);
    g_site_count++;
  }
}

}  // namespace

bool fix_armed() {
  // `armed_for` et non `armed()` : l'armement global est celui de l'item que le harnais
  // mesure. Un correctif qui consulterait `armed()` se desarmerait des qu'un AUTRE item
  // passe son ablation (instrument_armed_by_identity_makes_ablation_measurable).
  return autoport_proof::armed_for(kItemId);
}

void note_fullscreen_copy(const char* site) {
  g_copies.fetch_add(1, std::memory_order_relaxed);
  remember_site(site);
}

void note_window_clear(bool issued, bool fully_covered) {
  // La POPULATION, c'est le point de l'image ou le clear se pose — elle est comptee meme
  // quand plus aucun clear n'est emis. Le NUMERATEUR, c'est le clear emis sur une fenetre
  // integralement recouverte.
  g_window_clear_sites.fetch_add(1, std::memory_order_relaxed);
  if (issued) {
    g_window_clears.fetch_add(1, std::memory_order_relaxed);
    g_window_clears_total.fetch_add(1, std::memory_order_relaxed);
    if (fully_covered) {
      g_window_clears_covered.fetch_add(1, std::memory_order_relaxed);
    }
  }
  if (fully_covered) {
    g_window_covered_sites.fetch_add(1, std::memory_order_relaxed);
  }
}

void note_pass_end(const char* site, bool invalidated) {
  (void)site;
  g_pass_ends.fetch_add(1, std::memory_order_relaxed);
  if (!invalidated) {
    g_pass_ends_no_inval.fetch_add(1, std::memory_order_relaxed);
  }
}

bool window_has_depth_stencil() {
  static int s_state = -1;  // -1 = pas encore lu
  if (s_state >= 0) {
    return s_state > 0;
  }
  GLint d_type = GL_NONE, s_type = GL_NONE, d_bits = 0, s_bits = 0;
  glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_DEPTH,
                                        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &d_type);
  glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_STENCIL,
                                        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &s_type);
  if (d_type != GL_NONE) {
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_DEPTH,
                                          GL_FRAMEBUFFER_ATTACHMENT_DEPTH_SIZE, &d_bits);
  }
  if (s_type != GL_NONE) {
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_STENCIL,
                                          GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE, &s_bits);
  }
  // Une requete qui echoue laisse ses sorties intactes : on part d'un etat NEUTRE (GL_NONE, 0)
  // et on ne conclut « oui » que sur une reponse positive. Un pilote muet donne donc « non »,
  // c'est-a-dire la chaine d'origine, jamais un dessin dans un tampon qui n'existe pas.
  s_state = (d_type != GL_NONE && s_type != GL_NONE && d_bits > 0 && s_bits > 0) ? 1 : 0;
  autoport_proof::publish("fb_window_depth_bits", (uint64_t)(d_bits < 0 ? 0 : d_bits));
  autoport_proof::publish("fb_window_stencil_bits", (uint64_t)(s_bits < 0 ? 0 : s_bits));
  return s_state > 0;
}

PresentStateGuard::PresentStateGuard() {
  glGetIntegerv(GL_CURRENT_PROGRAM, &m_program);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &m_vao);
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &m_array_buffer);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &m_active_texture);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &m_texture_2d);
  glGetIntegerv(GL_VIEWPORT, m_viewport);
  m_depth_test = glIsEnabled(GL_DEPTH_TEST);
  m_blend = glIsEnabled(GL_BLEND);
}

PresentStateGuard::~PresentStateGuard() {
  // La liaison de texture se restaure sur l'unite qui etait ACTIVE a l'entree : c'est elle que
  // le quad a ecrasee (il lie, PUIS passe a l'unite 0).
  glActiveTexture((GLenum)m_active_texture);
  glBindTexture(GL_TEXTURE_2D, (GLuint)m_texture_2d);
  glBindBuffer(GL_ARRAY_BUFFER, (GLuint)m_array_buffer);
  glBindVertexArray((GLuint)m_vao);
  glUseProgram((GLuint)m_program);
  glViewport(m_viewport[0], m_viewport[1], m_viewport[2], m_viewport[3]);
  if (m_depth_test) {
    glEnable(GL_DEPTH_TEST);
  } else {
    glDisable(GL_DEPTH_TEST);
  }
  if (m_blend) {
    glEnable(GL_BLEND);
  } else {
    glDisable(GL_BLEND);
  }
}

void note_msaa_resolve() {
  g_msaa_resolves.fetch_add(1, std::memory_order_relaxed);
}

void end_pass_discarding_depth(const char* site, GLenum target, bool is_window, bool has_depth) {
  if (!has_depth) {
    // Pas de depth/stencil attache : il n'y a rien a abandonner, donc pas de fin de passe a
    // reprocher. Compter cette cible gonflerait la population d'un cas que le correctif ne
    // peut pas traiter.
    return;
  }
  if (!fix_armed()) {
    note_pass_end(site, false);
    return;
  }
  // L'ENTREE PEUT NE PAS EXISTER, ET ALORS ON NE L'APPELLE PAS.
  // glad range chaque pointeur par version de GL de BUREAU et saute ses listes au-dessus de la
  // version qu'il deduit du contexte ; « OpenGL ES 3.2 » lui fait sauter la liste 4.3, ou vit
  // glInvalidateFramebuffer — pourtant CORE en ES 3.0. Le pointeur reste NULL et l'appel est un
  // saut vers 0. C'est arrive : course du 14/09 sur eae4df44, SIGSEGV pc=0, frames=0.
  // `android_gfx.cpp` resout desormais l'entree au PRODUCTEUR (c'est la le correctif durable),
  // et ce test-ci fait que le meme oubli, sur une autre plateforme ou une autre entree, rende
  // une porte ROUGE NOMMEE au lieu d'un plantage : la fin de passe est declaree NON invalidee.
  if (!glInvalidateFramebuffer) {
    autoport_proof::publish("fb_invalidate_entrypoint_missing", 1);
    note_pass_end(site, false);
    return;
  }
  // Le framebuffer par defaut ne porte PAS de noms d'attachement : GL_DEPTH/GL_STENCIL. Un
  // GL_DEPTH_ATTACHMENT sur FB0 rend GL_INVALID_ENUM et l'appel ne fait rien — sans bruit.
  const GLenum att_fbo[2] = {GL_DEPTH_ATTACHMENT, GL_STENCIL_ATTACHMENT};
  const GLenum att_win[2] = {GL_DEPTH, GL_STENCIL};
  glInvalidateFramebuffer(target, 2, is_window ? att_win : att_fbo);
  g_invalidates.fetch_add(1, std::memory_order_relaxed);
  note_pass_end(site, true);
}

void note_frame_geometry(int win_w,
                         int win_h,
                         int draw_w,
                         int draw_h,
                         int off_x,
                         int off_y,
                         int scene_w,
                         int scene_h) {
  std::lock_guard<std::mutex> lock(g_text_mutex);
  g_geom[0] = win_w;
  g_geom[1] = win_h;
  g_geom[2] = draw_w;
  g_geom[3] = draw_h;
  g_geom[4] = off_x;
  g_geom[5] = off_y;
  g_geom[6] = scene_w;
  g_geom[7] = scene_h;
}

void note_ui_regime(bool split_active, bool direct_to_window, const char* block_reason) {
  if (split_active) {
    g_split_frames.fetch_add(1, std::memory_order_relaxed);
  }
  if (direct_to_window) {
    g_direct_frames.fetch_add(1, std::memory_order_relaxed);
  }
  std::lock_guard<std::mutex> lock(g_text_mutex);
  std::snprintf(g_block_reason, sizeof(g_block_reason), "%s",
                block_reason && *block_reason ? block_reason : "-");
}

void note_ui_direct() {
  g_direct_frames.fetch_add(1, std::memory_order_relaxed);
  std::lock_guard<std::mutex> lock(g_text_mutex);
  std::snprintf(g_block_reason, sizeof(g_block_reason), "%s", "-");
}

void frame_boundary() {
  const uint64_t n = g_frames.fetch_add(1, std::memory_order_relaxed) + 1;

  const uint64_t copies = g_copies.exchange(0, std::memory_order_relaxed);
  const uint64_t pass_ends = g_pass_ends.exchange(0, std::memory_order_relaxed);
  const uint64_t no_inval = g_pass_ends_no_inval.exchange(0, std::memory_order_relaxed);
  const uint64_t covered_clears = g_window_clears_covered.exchange(0, std::memory_order_relaxed);
  g_window_clears.exchange(0, std::memory_order_relaxed);
  g_window_clear_sites_total.fetch_add(g_window_clear_sites.exchange(0, std::memory_order_relaxed),
                                       std::memory_order_relaxed);
  g_window_covered_sites_total.fetch_add(
      g_window_covered_sites.exchange(0, std::memory_order_relaxed), std::memory_order_relaxed);
  const uint64_t resolves = g_msaa_resolves.exchange(0, std::memory_order_relaxed);
  bump_max(g_msaa_resolves_max, resolves);

  const uint64_t extra = (copies > 1 ? copies - 1 : 0) + no_inval + covered_clears;

  if (n == 1) {
    // La premiere image est de l'INITIALISATION de contexte (creation des FBO, premiers
    // binds) : elle est publiee A PART, jamais effacee, pour qu'un maximum de course ne
    // raconte pas l'amorcage (le patron de gl_query_census).
    g_extra_boot.store(extra, std::memory_order_relaxed);
    publish_now();
    return;
  }

  const uint64_t before = g_extra_max.load(std::memory_order_relaxed);
  g_frames_measured.fetch_add(1, std::memory_order_relaxed);
  bump_max(g_extra_max, extra);
  bump_max(g_copies_max, copies);
  bump_min(g_copies_min, copies);
  bump_max(g_pass_ends_max, pass_ends);
  bump_max(g_no_inval_max, no_inval);
  bump_max(g_covered_clear_max, covered_clears);

  if (extra > 0) {
    g_nonzero_frames.fetch_add(1, std::memory_order_relaxed);
  } else {
    g_conforming_frames.fetch_add(1, std::memory_order_relaxed);
    // `hits_means` de l'item : « images sans passe superflue ». La prise est ATTRIBUEE, sinon
    // elle remplirait le `hits=` de tous les items a la fois
    // (feature_hits_counter_is_shared_so_the_gate_is_vacuous).
    autoport_proof::note_hit_for(kItemId, 1);
  }

  if (extra > before || (n % 60) == 0) {
    publish_now();
  }
}

}  // namespace fb_passes
