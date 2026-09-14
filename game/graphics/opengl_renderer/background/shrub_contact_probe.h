#pragma once

#include <cstddef>
#include <string>

#include "common/common_types.h"
#include "game/graphics/pipelines/opengl.h"

namespace shrub_contact_probe {
struct Sample {
  float pre[3];
  float post[3];
  u32 vertex_index;
};
using SampleCallback = void (*)(const std::string&, int, size_t, u64, const Sample*, size_t);
// Callback runs synchronously; samples are valid only until it returns. The consumer must
// check vertex_index against the matching final CPU geometry and reject missing identities.
void set_sample_callback(SampleCallback callback);
u64 errors();
// Reads the actual EBO range, then evaluates its referenced vertices as GL_POINTS.
// Captures the vertex shader only; no claim is made about rasterization equivalence.
void draw_elements(const std::string& level, int geo, size_t tree_index, u64 frame,
                   GLenum mode, GLsizei count, GLenum type, const void* offset);
void multi_draw_elements(const std::string& level, int geo, size_t tree_index, u64 frame,
                         GLenum mode, const GLsizei* counts, GLenum type,
                         const void* const* offsets, GLsizei drawcount);
}  // namespace shrub_contact_probe
