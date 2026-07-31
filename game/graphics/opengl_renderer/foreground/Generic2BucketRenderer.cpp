#include "Generic2BucketRenderer.h"

#include "game/graphics/gfx.h"

#include <cstdlib>
#include <cstdio>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

// Gecho-pool probe (TEMPORARY): per-generic-bucket vert/tri census to localize the
// missing dark-eco-pool draw in the intro cinematic. Armed via env OG_GECHO_GEN
// (x86) or prop debug.opengoal.gecho.gen=1 (Android). OFF by default. Diagnostic only.
static bool gecho_gen_on() {
  static const bool s_on = [] {
    if (std::getenv("OG_GECHO_GEN")) return true;
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.gecho.gen", buf) > 0 && buf[0] == '1') return true;
#endif
    return false;
  }();
  return s_on;
}

Generic2BucketRenderer::Generic2BucketRenderer(const std::string& name,
                                               int id,
                                               std::shared_ptr<Generic2> renderer,
                                               Generic2::Mode mode)
    : BucketRenderer(name, id), m_generic(renderer), m_mode(mode) {}

void Generic2BucketRenderer::draw_debug_window() {
  m_generic->draw_debug_window();
}

void Generic2BucketRenderer::render(DmaFollower& dma,
                                    SharedRenderState* render_state,
                                    ScopedProfilerNode& prof) {
  // if the user has asked to disable the renderer, just advance the dma follower to the next
  // bucket and return immediately.
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }
  // Grecharged-mesh-browser V2.6-bis isolation: only the targeted mesh renders — drain the
  // bucket exactly like the disabled path.
  if (Gfx::g_global_settings.mb_isolation_on()) {
    Gfx::g_global_settings.mb_cur_isolated_skips++;
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }
  m_generic->render_in_mode(dma, render_state, prof, m_mode);
  if (gecho_gen_on()) {
    u32 v = m_generic->dbg_vert_count();
    u32 f = m_generic->dbg_frag_count();
    u32 a = m_generic->dbg_adgif_count();
    if (v > 0 || f > 0 || a > 0) {
      printf("GECHO-GEN bucket=%s id=%d verts=%u frags=%u adgifs=%u idx=%u tris=%u\n", name().c_str(),
             m_my_id, v, f, a, m_generic->dbg_idx_count(), m_generic->dbg_tri_count());
      fflush(stdout);
      if (v > 0) m_generic->dbg_dump_draws(name().c_str(), m_my_id, render_state);
    }
  }
  m_empty = m_generic->empty();
}

bool Generic2BucketRenderer::empty() const {
  return m_empty;
}
