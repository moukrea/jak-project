#pragma once
#include <cstdint>
#include <vector>
#include <string>
namespace ao_tie_alpha_probe {
void begin_frame(bool enabled, int width, int height);
bool active();
void finish_hut(uint64_t render_frame);
bool color_frame();
void note_color_binding(bool ao_off, bool proof_off);
void shader_variant(const std::string& name, std::string& source);
void finish_color(unsigned framebuffer, unsigned format, const std::vector<float>& scene_depth);
uint32_t draw_id(const void* source_draws, uint32_t source_index);
void pre_capture_begin(bool nocut);
void pre_capture_end();
void color_begin();
void color_end();
void before_color_draw(unsigned program, uint32_t id);
void before_pre_draw(unsigned program, uint32_t id);
void finish_frame(const std::vector<float>& delivered_depth,
                  const std::vector<float>& scene_depth,
                  const std::vector<uint8_t>& resolved_rgba);
}
