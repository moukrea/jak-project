#include "Merc2BucketRenderer.h"

#include "game/graphics/gfx.h"

Merc2BucketRenderer::Merc2BucketRenderer(const std::string& name,
                                         int my_id,
                                         std::shared_ptr<Merc2> merc)
    : BucketRenderer(name, my_id), m_renderer(merc) {}

void Merc2BucketRenderer::render(DmaFollower& dma,
                                 SharedRenderState* render_state,
                                 ScopedProfilerNode& prof) {
  // skip if disabled
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  // lighting-shadows (partie B) : Merc2 est partage par les 16 Merc2BucketRenderer ; lui dire
  // dans quel seau on est lui permet de refuser de projeter une ombre pour un seau qui n'est pas
  // un seau MONDE (voir Merc2::shadow_cast_allowed_bucket, ex. le seau debug du HUD 3D).
  m_renderer->set_current_bucket(m_my_id);
  m_renderer->render(dma, render_state, prof, &m_debug_stats);

  m_empty = m_debug_stats.num_predicted_draws == 0;
}

void Merc2BucketRenderer::draw_debug_window() {
  m_renderer->draw_debug_window(&m_debug_stats);
}

bool Merc2BucketRenderer::empty() const {
  return m_empty;
}