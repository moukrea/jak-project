#include "shrub_contact_probe.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

#include "common/log/log.h"
#include "game/system/autoport_proof.h"

namespace shrub_contact_probe {
namespace {
static_assert(sizeof(Sample) == 7 * sizeof(u32), "transform feedback packing");
constexpr size_t kMaxBytes = 32 * 1024 * 1024;
SampleCallback s_callback = nullptr;
u64 s_errors = 0;
u64 s_captures = 0;
u64 s_vertices = 0;
u64 s_microseconds = 0;
u64 s_peak_bytes = 0;
void publish_stats() {
  autoport_proof::publish("shrub_contact_gpu_errors", s_errors);
  autoport_proof::publish("shrub_contact_gpu_captures", s_captures);
  autoport_proof::publish("shrub_contact_gpu_vertices", s_vertices);
  autoport_proof::publish("shrub_contact_gpu_cpu_us", s_microseconds);
  autoport_proof::publish("shrub_contact_gpu_peak_buffer_bytes", s_peak_bytes);
}

void fail(const char* reason) {
  ++s_errors;
  publish_stats();
  lg::error("SHRUB-CONTACT-GPU error={} errors={} captures={}", reason, s_errors, s_captures);
}

// A private TF object holds all indexed bindings we change. The prior object's indexed
// bindings remain untouched; restore the generic buffer binding separately.
struct State {
  GLint feedback = 0;
  GLint buffer = 0;
  bool discard = false;
  GLuint own_feedback = 0;
  GLuint own_buffer = 0;
  GLuint query = 0;
  State() {
    glGetIntegerv(GL_TRANSFORM_FEEDBACK_BINDING, &feedback);
    glGetIntegerv(GL_TRANSFORM_FEEDBACK_BUFFER_BINDING, &buffer);
    discard = glIsEnabled(GL_RASTERIZER_DISCARD);
    glGenTransformFeedbacks(1, &own_feedback);
    glGenBuffers(1, &own_buffer);
    glGenQueries(1, &query);
  }
  ~State() {
    glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, feedback);
    glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER, buffer);
    if (!discard) {
      glDisable(GL_RASTERIZER_DISCARD);
    }
    glDeleteQueries(1, &query);
    glDeleteBuffers(1, &own_buffer);
    glDeleteTransformFeedbacks(1, &own_feedback);
  }
};
}  // namespace

void set_sample_callback(SampleCallback callback) {
  s_callback = callback;
}
u64 errors() {
  return s_errors;
}

void draw_elements(const std::string& level, int geo, size_t tree_index, u64 frame,
                   GLenum mode, GLsizei count, GLenum type, const void* offset) {
  if (!autoport_proof::feature_is("shrub-trunk-contact") || frame % 60 != 0 || count == 0) {
    return;
  }
  if (count < 0 || (mode != GL_TRIANGLES && mode != GL_TRIANGLE_STRIP) || type != GL_UNSIGNED_INT) {
    fail("unsupported-draw");
    return;
  }
  if (!s_callback) {
    fail("missing-consumer");
    return;
  }
  if (!glGenTransformFeedbacks || !glBindTransformFeedback || !glBeginTransformFeedback ||
      !glEndTransformFeedback || !glMapBufferRange || !glGetQueryiv || !glGetQueryObjectuiv ||
      !glGetBufferParameteri64v || !glGetTransformFeedbackVarying) {
    fail("missing-gl-api");
    return;
  }
  GLint current_query = 0;
  GLboolean active = GL_FALSE;
  glGetQueryiv(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN, GL_CURRENT_QUERY, &current_query);
  glGetBooleanv(GL_TRANSFORM_FEEDBACK_ACTIVE, &active);
  if (current_query || active) {
    fail("external-feedback-or-query-active");
    return;
  }
  GLint program = 0;
  GLint varying_count = 0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &program);
  if (program) {
    glGetProgramiv(program, GL_TRANSFORM_FEEDBACK_VARYINGS, &varying_count);
  }
  if (varying_count != 3) {
    fail("program-not-instrumented");
    return;
  }
  const char* expected_names[] = {"probe_pre_contact", "probe_post_contact", "probe_vertex_index"};
  for (GLuint i = 0; i < 3; ++i) {
    char name[64] = {};
    GLsizei length = 0;
    GLsizei size = 0;
    GLenum varying_type = 0;
    glGetTransformFeedbackVarying(program, i, sizeof(name), &length, &size, &varying_type, name);
    if (std::strcmp(name, expected_names[i]) || size != 1 ||
        varying_type != (i == 2 ? GL_UNSIGNED_INT : GL_FLOAT_VEC3)) {
      fail("program-varying-layout-mismatch");
      return;
    }
  }
  if (glGetError() != GL_NO_ERROR) {
    fail("preexisting-gl-error");
    return;
  }
  const auto start = std::chrono::steady_clock::now();
  const size_t index_bytes = size_t(count) * sizeof(u32);
  if (index_bytes > kMaxBytes) {
    fail("index-memory-bound-exceeded");
    return;
  }
  GLint ebo = 0;
  GLint64 ebo_bytes = 0;
  glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &ebo);
  if (!ebo) {
    fail("missing-element-buffer");
    return;
  }
  glGetBufferParameteri64v(GL_ELEMENT_ARRAY_BUFFER, GL_BUFFER_SIZE, &ebo_bytes);
  const uintptr_t index_offset = reinterpret_cast<uintptr_t>(offset);
  if (ebo_bytes < 0 || index_offset % sizeof(u32) || index_offset > u64(ebo_bytes) ||
      index_bytes > u64(ebo_bytes) - index_offset) {
    fail("element-buffer-range-invalid");
    return;
  }
  bool restart = glIsEnabled(GL_PRIMITIVE_RESTART_FIXED_INDEX);
  u32 restart_index = std::numeric_limits<u32>::max();
#ifndef __ANDROID__
  if (!restart && glIsEnabled(GL_PRIMITIVE_RESTART)) {
    restart = true;
    GLint configured_restart = 0;
    glGetIntegerv(GL_PRIMITIVE_RESTART_INDEX, &configured_restart);
    restart_index = u32(configured_restart);
  }
#endif
  const auto* indices = static_cast<const u32*>(glMapBufferRange(
      GL_ELEMENT_ARRAY_BUFFER, index_offset, index_bytes, GL_MAP_READ_BIT));
  if (!indices) {
    fail("element-buffer-map-failed");
    return;
  }
  std::vector<u32> referenced;
  referenced.reserve(count);
  // A restart ends a primitive sequence. Incomplete triangle tails and strips shorter
  // than three indices never produce primitives, hence must not enter this population.
  size_t segment_begin = 0;
  for (size_t end = 0; end <= size_t(count); ++end) {
    if (end != size_t(count) && (!restart || indices[end] != restart_index)) {
      continue;
    }
    const size_t length = end - segment_begin;
    const size_t complete = mode == GL_TRIANGLES ? (length / 3) * 3 : (length >= 3 ? length : 0);
    referenced.insert(referenced.end(), indices + segment_begin, indices + segment_begin + complete);
    segment_begin = end + 1;
  }
  if (!glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER)) {
    fail("element-buffer-unmap-corrupt");
    return;
  }
  if (glGetError() != GL_NO_ERROR) {
    fail("element-buffer-read-gl-error");
    return;
  }
  std::sort(referenced.begin(), referenced.end());
  referenced.erase(std::unique(referenced.begin(), referenced.end()), referenced.end());
  if (referenced.empty()) {
    fail("no-complete-primitive");
    return;
  }
  if (referenced.back() > u32(std::numeric_limits<GLint>::max())) {
    fail("element-vertex-id-out-of-range");
    return;
  }
  const size_t capacity = referenced.size();
  if (capacity > (kMaxBytes - index_bytes) / sizeof(Sample)) {
    fail("capture-memory-bound-exceeded");
    return;
  }
  State state;
  glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, state.own_feedback);
  glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER, state.own_buffer);
  const size_t bytes = capacity * sizeof(Sample);
  glBufferData(GL_TRANSFORM_FEEDBACK_BUFFER, bytes, nullptr, GL_STREAM_READ);
  glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, state.own_buffer);
  if (glGetError() != GL_NO_ERROR) {
    fail("capture-allocation-failed");
    return;
  }
  glEnable(GL_RASTERIZER_DISCARD);
  glBeginQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN, state.query);
  // GLES forbids indexed draws while TF is active. Re-run only the referenced vertex
  // shader invocations as points, preserving VAO, VBOs, uniforms and gl_VertexID. This
  // measures vertex deformation, not primitive assembly or rasterized pixels.
  glBeginTransformFeedback(GL_POINTS);
  for (size_t begin = 0; begin < referenced.size();) {
    size_t end = begin + 1;
    while (end < referenced.size() && referenced[end] == referenced[end - 1] + 1) {
      ++end;
    }
    glDrawArrays(GL_POINTS, GLint(referenced[begin]), GLsizei(end - begin));
    begin = end;
  }
  glEndTransformFeedback();
  glEndQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN);
  GLuint primitives = 0;
  glGetQueryObjectuiv(state.query, GL_QUERY_RESULT, &primitives);
  if (glGetError() != GL_NO_ERROR) {
    fail("capture-gl-error");
    return;
  }
  const size_t sample_count = size_t(primitives);
  if (sample_count != capacity) {
    fail("empty-or-overflow-capture");
    return;
  }
  const auto* samples = static_cast<const Sample*>(
      glMapBufferRange(GL_TRANSFORM_FEEDBACK_BUFFER, 0, sample_count * sizeof(Sample), GL_MAP_READ_BIT));
  if (!samples) {
    fail("map-failed");
    return;
  }
  bool valid = true;
  for (size_t i = 0; i < sample_count; ++i) {
    valid &= samples[i].vertex_index == referenced[i];
    for (int axis = 0; axis < 3; ++axis) {
      valid &= std::isfinite(samples[i].pre[axis]) && std::isfinite(samples[i].post[axis]);
    }
  }
  if (valid) {
    s_callback(level, geo, tree_index, frame, samples, sample_count);
  } else {
    fail("invalid-coordinate-or-id");
  }
  if (!glUnmapBuffer(GL_TRANSFORM_FEEDBACK_BUFFER)) {
    fail("unmap-data-corrupt");
  }
  ++s_captures;
  s_vertices += sample_count;
  s_microseconds += std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now() - start).count();
  s_peak_bytes = std::max(s_peak_bytes, u64(bytes));
  publish_stats();
  lg::info("SHRUB-CONTACT-GPU level={} geo={} tree={} frame={} program={} captures={} "
           "vertices={} errors={} cpu_us={} buffer_bytes={}",
           level, geo, tree_index, frame, program, s_captures, s_vertices, s_errors,
           s_microseconds, bytes);
}

void multi_draw_elements(const std::string& level, int geo, size_t tree_index, u64 frame,
                         GLenum mode, const GLsizei* counts, GLenum type,
                         const void* const* offsets, GLsizei drawcount) {
  if (!autoport_proof::feature_is("shrub-trunk-contact") || frame % 60 != 0) {
    return;
  }
  if (drawcount < 0 || (drawcount && (!counts || !offsets))) {
    fail("invalid-multi-draw");
    return;
  }
  for (GLsizei i = 0; i < drawcount; ++i) {
    draw_elements(level, geo, tree_index, frame, mode, counts[i], type, offsets[i]);
  }
}
}  // namespace shrub_contact_probe
