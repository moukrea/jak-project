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
enum class InputMapping : unsigned char { Common, Contact, NewAttachment, Observation };
// Calls are synchronous. Capture identities use anchored replay frames120..600 sampled modulo60.
// Blobs are cached even before the anchor and emitted with matching level/geo/tree captures.
// name identifies a blob semantically (native-row0, contact-anchor, contact-attachment).
void archive_blob(const std::string& domain,
                  const std::string& level,
                  int geo,
                  size_t tree,
                  const std::string& name,
                  const void* data,
                  size_t bytes,
                  InputMapping mapping = InputMapping::Common);
// Opaque byte arrays must have deterministic packing; include instance/vertex IDs in inputs.
void archive_capture(const std::string& domain,
                     const std::string& level,
                     int geo,
                     size_t tree,
                     const void* inputs,
                     size_t input_bytes,
                     const void* pre,
                     size_t pre_bytes,
                     const void* post,
                     size_t post_bytes);
// Call once on each logical frame, including frames with no vegetation; closes previous sample.
void archive_tick();
// Select exactly one rendered frame for each sampled logical frame, shared by all domains.
bool capture_frame(u64 render_frame);
// Reads the actual EBO range, then evaluates its referenced vertices as GL_POINTS.
// Captures the vertex shader only; no claim is made about rasterization equivalence.
void draw_elements(const std::string& level,
                   int geo,
                   size_t tree_index,
                   u64 frame,
                   GLenum mode,
                   GLsizei count,
                   GLenum type,
                   const void* offset);
void multi_draw_elements(const std::string& level,
                         int geo,
                         size_t tree_index,
                         u64 frame,
                         GLenum mode,
                         const GLsizei* counts,
                         GLenum type,
                         const void* const* offsets,
                         GLsizei drawcount);
}  // namespace shrub_contact_probe
