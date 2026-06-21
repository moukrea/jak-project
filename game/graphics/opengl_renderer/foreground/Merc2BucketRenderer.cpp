#include "Merc2BucketRenderer.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "fmt/core.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

// Gd3-jak TEMP census: gated by env OG_GD3_CENSUS (x86) / property
// debug.opengoal.gd3.census (device). Emits per-merc-bucket triangle counts +
// per-model name:tris so we can prove "Jak draws 0 tris in the cinematic" before
// the fix and ">0 matching x86" after. Output goes to stdout, which on Android is
// dup2'd to logcat (tag GK_STDOUT). REMOVE this harness after the AFTER capture.
static bool gd3_census_on() {
  static const bool s_on = [] {
    if (std::getenv("OG_GD3_CENSUS")) {
      return true;
    }
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.gd3.census", buf) > 0 && buf[0] == '1') {
      return true;
    }
#endif
    return false;
  }();
  return s_on;
}

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

  if (gd3_census_on()) {
    m_debug_stats.collect_debug_model_list = true;  // fill model_list (name + per-draw tris)
  }

  m_renderer->render(dma, render_state, prof, &m_debug_stats);

  m_empty = m_debug_stats.num_predicted_draws == 0;

  if (gd3_census_on() && (m_debug_stats.num_predicted_tris > 0 || m_debug_stats.num_envmap_tris > 0)) {
    // throttle: ~ every 12th non-empty render of THIS bucket
    if ((m_gd3_census_tick++ % 12) == 0) {
      int total = m_debug_stats.num_predicted_tris + m_debug_stats.num_envmap_tris;
      int jak_tris = 0;
      std::string models;
      for (const auto& md : m_debug_stats.model_list) {
        int mt = 0;
        for (const auto& e : md.effects) {
          for (const auto& d : e.draws) {
            mt += d.num_tris;
            if (e.envmap) {
              mt += d.num_tris;
            }
          }
        }
        if (mt <= 0) {
          continue;
        }
        // Jak's player model is named "eichar"; Daxter is "sidekick"/"sidekick-human".
        if (md.name.find("eichar") != std::string::npos ||
            md.name.find("jak") != std::string::npos ||
            md.name.find("daxter") != std::string::npos ||
            md.name.find("sidekick") != std::string::npos) {
          jak_tris += mt;
        }
        if (models.size() < 240) {
          models += fmt::format("{}:{} ", md.name, mt);
        }
      }
      fmt::print("GD3-CENSUS bucket={} tris={} jakdax={} nmodels={} [{}]\n", name(), total, jak_tris,
                 (int)m_debug_stats.model_list.size(), models);
      fflush(stdout);
    }
  }
}

void Merc2BucketRenderer::draw_debug_window() {
  m_renderer->draw_debug_window(&m_debug_stats);
}

bool Merc2BucketRenderer::empty() const {
  return m_empty;
}