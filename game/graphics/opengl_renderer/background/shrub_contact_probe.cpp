#include "shrub_contact_probe.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <vector>

#include "shrub_contact_archive.h"

#include "game/system/pad_replay.h"
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

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

using namespace shrub_contact_archive;
std::string setting(const char* env, const char* property) {
#ifdef __ANDROID__
  char value[PROP_VALUE_MAX] = {};
  if (__system_property_get(property, value) > 0)
    return value;
#else
  (void)property;
#endif
  const char* value_env = std::getenv(env);
  return value_env ? value_env : "";
}
struct Archive {
  std::string output = setting("OG_SHRUB_ARCHIVE", "debug.opengoal.shrub.archive");
  std::string reference = setting("OG_SHRUB_REFERENCE", "debug.opengoal.shrub.reference");
  std::string off_reference =
      setting("OG_SHRUB_OFF_REFERENCE", "debug.opengoal.shrub.off_reference");
  uint64_t shrub_pairs = 0, tie_pairs = 0, grass_pairs = 0;
  uint64_t off_pairs = 0, off_missing = 0, off_inputs = 0, off_pre = 0, off_post = 0;
  int64_t frame = -1;
  Records records;
  std::map<std::string, uint64_t> ordinals;
  uint64_t bytes = 0, run_bytes = 0, frames = 0, missing = 0, input_diff = 0, pre_diff = 0,
           post_diff = 0;
  CaptureWindow window;
  bool broken = false;
  int64_t selected_logic = -1;
  int64_t published_logic = -2;
  u64 selected_render = 0;
  void close() {
    if (frame < 0)
      return;
    if (broken) {
      fail("archive-frame-incomplete");
      records.clear();
      frame = -1;
      return;
    }
    bool acquired = !records.empty();
    if (records.empty()) {
      ++missing;
      fail("archive-empty-population");
    }
    const auto file = std::to_string(frame) + ".shrub";
    if (!output.empty()) {
      std::error_code ec;
      std::filesystem::create_directories(output, ec);
      auto packed = encode(frame, records);
      run_bytes += packed.size();
      if (ec || run_bytes > max_run || !write(output + "/" + file, packed)) {
        acquired = false;
        fail("archive-write-failed-or-bound");
      }
    }
    if (!reference.empty()) {
      Records ref;
      if (!read(reference + "/" + file, frame, ref) || !valid_mappings(ref) ||
          !valid_mappings(records)) {
        ++missing;
        fail("archive-reference-missing-or-corrupt");
      } else {
        auto c = compare(records, ref, !autoport_proof::armed());
        // Grass contact is invariant in both arms; shrub ON only compares pre-contact.
        for (const auto& [key, r] : records)
          if (!r.pre.empty()) {
            std::string domain, name;
            int64_t record_geo;
            auto it = ref.find(key);
            if (identity(key, domain, name, record_geo) && it != ref.end() &&
                !it->second.pre.empty()) {
              if (domain == "shrub")
                ++shrub_pairs;
              if (domain == "tie")
                ++tie_pairs;
              if (domain == "grass") {
                ++grass_pairs;
                if (autoport_proof::armed())
                  c.post += r.post != it->second.post;
              }
            }
          }
        missing += c.missing;
        input_diff += c.inputs;
        pre_diff += c.pre;
        post_diff += c.post;
        if (!off_reference.empty() && autoport_proof::armed()) {
          Records off;
          if (!read(off_reference + "/" + file, frame, off) || !valid_mappings(off)) {
            ++off_missing;
            fail("archive-off-reference-missing-or-corrupt");
          } else {
            auto oc = compare(off, ref, true);
            off_missing += oc.missing;
            off_inputs += oc.inputs;
            off_pre += oc.pre;
            off_post += oc.post;
            ++off_pairs;
          }
        }
      }
    }
    ++frames;
    if (acquired && !window.close(frame))
      fail("archive-unplanned-or-duplicate-frame");
    autoport_proof::publish("shrub_archive_closed_frames", frames);
    autoport_proof::publish("shrub_archive_population_errors", missing);
    autoport_proof::publish("shrub_archive_input_differences", input_diff);
    autoport_proof::publish("shrub_archive_pre_differences", pre_diff);
    autoport_proof::publish("shrub_archive_post_differences", post_diff);
    autoport_proof::publish("shrub_archive_reference_enabled", !reference.empty());
    autoport_proof::publish("shrub_archive_shrub_pairs", shrub_pairs);
    autoport_proof::publish("shrub_archive_tie_pairs", tie_pairs);
    autoport_proof::publish("shrub_archive_grass_pairs", grass_pairs);
    autoport_proof::publish("shrub_archive_off_pairs", off_pairs);
    autoport_proof::publish("shrub_archive_off_missing", off_missing);
    autoport_proof::publish("shrub_archive_off_input_differences", off_inputs);
    autoport_proof::publish("shrub_archive_off_pre_differences", off_pre);
    autoport_proof::publish("shrub_archive_off_post_differences", off_post);
    autoport_proof::publish("shrub_archive_off_reference_enabled", !off_reference.empty());
    records.clear();
    ordinals.clear();
    bytes = 0;
    frame = -1;
  }
  bool tick() {
    if (!autoport_proof::feature_is("shrub-trunk-contact"))
      return false;
    const auto now = pad_replay::current_frame();
    if (frame >= 0 && now != frame)
      close();
    window.tick(now);
    if (now != published_logic) {
      published_logic = now;
      autoport_proof::publish("shrub_archive_expected_frames", CaptureWindow::expected);
      autoport_proof::publish("shrub_archive_observed_frame_mask", window.observed);
      autoport_proof::publish("shrub_archive_observed_frames", window.count());
      autoport_proof::publish("shrub_archive_complete", window.complete());
      if (window.passed)
        autoport_proof::publish("shrub_archive_missing_planned_frames",
                                CaptureWindow::expected - window.count());
    }
    if (!CaptureWindow::planned(now) || window.contains(now))
      return false;
    frame = now;
    return !broken;
  }
  void add(const std::string& domain,
           const std::string& level,
           int geo,
           size_t tree,
           const std::string& name,
           Record r) {
    if (!tick())
      return;
    Bytes identity;
    field(identity, domain);
    field(identity, level);
    number(identity, geo);
    number(identity, tree);
    field(identity, name);
    std::string key(identity.begin(), identity.end());
    auto ordinal = ordinals[key]++;
    number(identity, ordinal);
    key.assign(identity.begin(), identity.end());
    size_t size = key.size() + r.inputs.size() + r.pre.size() + r.post.size() + 40;
    if (size > max_record || bytes + size > max_frame - 32) {
      broken = true;
      fail("archive-memory-bound");
      return;
    }
    bytes += size;
    records.emplace(std::move(key), std::move(r));
  }
};
struct CachedBlob {
  std::string domain, level, name;
  int geo;
  size_t tree;
  Record record;
};
std::map<std::string, CachedBlob> s_blobs;
size_t s_blob_bytes = 0;
Archive& archive() {
  static Archive a;
  return a;
}

bool observe_draw(const std::string& level,
                  int geo,
                  size_t tree,
                  GLint program,
                  const std::vector<u32>& vertices) {
  GLint old_array = 0;
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &old_array);
  struct Restore {
    GLint buffer;
    ~Restore() { glBindBuffer(GL_ARRAY_BUFFER, buffer); }
  } restore{old_array};
  GLint attributes = 0;
  glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, &attributes);
  for (GLint a = 0; a < attributes; ++a) {
    GLint enabled = 0;
    glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &enabled);
    if (!enabled && a != 0 && a != 7 && a != 8 && a != 9 && a != 10)
      continue;
    Record r;
    number(r.inputs, enabled);
    r.mapped = (a == 0 || a == 7 || a == 8 || (a == 9 && geo < 0)) ? 0 : 3;
    if (a == 10 && geo >= 0)
      r.mapped = 1;
    if (!enabled) {
      GLfloat values[4];
      glGetVertexAttribfv(a, GL_CURRENT_VERTEX_ATTRIB, values);
      append(r.inputs, values, sizeof(values));
    } else {
      GLint size, type, stride, normalized, integer, divisor, buffer;
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_SIZE, &size);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_TYPE, &type);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_STRIDE, &stride);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_NORMALIZED, &normalized);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_INTEGER, &integer);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_DIVISOR, &divisor);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &buffer);
      void* pointer = nullptr;
      glGetVertexAttribPointerv(a, GL_VERTEX_ATTRIB_ARRAY_POINTER, &pointer);
      size_t scalar = (type == GL_BYTE || type == GL_UNSIGNED_BYTE) ? 1
                      : (type == GL_SHORT || type == GL_UNSIGNED_SHORT || type == GL_HALF_FLOAT)
                          ? 2
                          : 4;
      size_t width = (type == GL_INT_2_10_10_10_REV || type == GL_UNSIGNED_INT_2_10_10_10_REV)
                         ? 4
                         : size * scalar;
      if (!buffer || divisor || size < 1 || size > 4 || stride < 0)
        return false;
      number(r.inputs, size);
      number(r.inputs, type);
      number(r.inputs, normalized);
      number(r.inputs, integer);
      glBindBuffer(GL_ARRAY_BUFFER, buffer);
      GLint64 length = 0;
      glGetBufferParameteri64v(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &length);
      const uint64_t offset = reinterpret_cast<uintptr_t>(pointer);
      const uint64_t last = offset + uint64_t(vertices.back()) * (stride ? stride : width) + width;
      if (length <= 0 || uint64_t(length) > max_record || last > uint64_t(length))
        return false;
      const auto* data = static_cast<const uint8_t*>(
          glMapBufferRange(GL_ARRAY_BUFFER, 0, length, GL_MAP_READ_BIT));
      if (!data)
        return false;
      for (auto vertex : vertices)
        append(r.inputs, data + offset + uint64_t(vertex) * (stride ? stride : width), width);
      if (!glUnmapBuffer(GL_ARRAY_BUFFER))
        return false;
    }
    archive().add(geo < 0 ? "shrub" : "tie", level, geo, tree, "attribute-" + std::to_string(a),
                  std::move(r));
  }
  GLint uniforms = 0;
  glGetProgramiv(program, GL_ACTIVE_UNIFORMS, &uniforms);
  for (GLint u = 0; u < uniforms; ++u) {
    char name[256] = {};
    GLsizei length;
    GLint count;
    GLenum type;
    glGetActiveUniform(program, u, sizeof(name), &length, &count, &type, name);
    GLint location = glGetUniformLocation(program, name);
    if (location < 0)
      continue;  // UBO, no deformation inputs
    std::string label(name);
    bool floating = true;
    int components = 0;
    switch (type) {
      case GL_FLOAT:
        components = 1;
        break;
      case GL_FLOAT_VEC2:
        components = 2;
        break;
      case GL_FLOAT_VEC3:
        components = 3;
        break;
      case GL_FLOAT_VEC4:
        components = 4;
        break;
      case GL_FLOAT_MAT3:
        components = 9;
        break;
      case GL_FLOAT_MAT4:
        components = 16;
        break;
      case GL_INT:
      case GL_BOOL:
      case GL_SAMPLER_2D:
      case GL_SAMPLER_2D_ARRAY:
      case GL_SAMPLER_CUBE:
        components = 1;
        floating = false;
        break;
      case GL_INT_VEC2:
        components = 2;
        floating = false;
        break;
      case GL_INT_VEC3:
        components = 3;
        floating = false;
        break;
      case GL_INT_VEC4:
        components = 4;
        floating = false;
        break;
      default:
        return false;
    }
    if (count < 1 || count > 4096)
      return false;
    Record r;
    r.mapped = (label.find("u_tie_sway_") == 0 || label == "u_shrub_native_on" ||
                label.find("u_jak_") == 0 || label.find("u_trample") == 0)
                   ? 0
                   : 3;
    if (label == "u_shrub_contact_on" || label == "u_tie_contact_on")
      r.mapped = 1;
    number(r.inputs, type);
    number(r.inputs, count);
    const auto bracket = label.find("[0]");
    for (int i = 0; i < count; ++i) {
      std::string element = bracket == std::string::npos
                                ? label
                                : label.substr(0, bracket) + "[" + std::to_string(i) + "]";
      GLint loc = glGetUniformLocation(program, element.c_str());
      if (loc < 0)
        return false;
      if (floating) {
        GLfloat values[16] = {};
        glGetUniformfv(program, loc, values);
        append(r.inputs, values, components * 4);
      } else {
        GLint values[16] = {};
        glGetUniformiv(program, loc, values);
        append(r.inputs, values, components * 4);
      }
    }
    archive().add(geo < 0 ? "shrub" : "tie", level, geo, tree, "uniform-" + label, std::move(r));
  }
  GLint blocks = 0, old_uniform = 0;
  glGetProgramiv(program, GL_ACTIVE_UNIFORM_BLOCKS, &blocks);
  glGetIntegerv(GL_UNIFORM_BUFFER_BINDING, &old_uniform);
  struct RestoreUniform {
    GLint buffer;
    ~RestoreUniform() { glBindBuffer(GL_UNIFORM_BUFFER, buffer); }
  } restore_uniform{old_uniform};
  for (GLint block = 0; block < blocks; ++block) {
    GLint binding = 0, size = 0, buffer = 0;
    GLint64 offset = 0, buffer_size = 0;
    char name[256] = {};
    GLsizei name_length = 0;
    glGetActiveUniformBlockName(program, block, sizeof(name), &name_length, name);
    glGetActiveUniformBlockiv(program, block, GL_UNIFORM_BLOCK_BINDING, &binding);
    glGetActiveUniformBlockiv(program, block, GL_UNIFORM_BLOCK_DATA_SIZE, &size);
    glGetIntegeri_v(GL_UNIFORM_BUFFER_BINDING, binding, &buffer);
    glGetInteger64i_v(GL_UNIFORM_BUFFER_START, binding, &offset);
    if (!buffer || size <= 0 || size_t(size) > max_record || offset < 0)
      return false;
    glBindBuffer(GL_UNIFORM_BUFFER, buffer);
    glGetBufferParameteri64v(GL_UNIFORM_BUFFER, GL_BUFFER_SIZE, &buffer_size);
    if (offset > buffer_size || size > buffer_size - offset)
      return false;
    const auto* data = glMapBufferRange(GL_UNIFORM_BUFFER, offset, size, GL_MAP_READ_BIT);
    if (!data)
      return false;
    Record r;
    r.mapped = 3;
    append(r.inputs, data, size);
    if (!glUnmapBuffer(GL_UNIFORM_BUFFER))
      return false;
    archive().add(geo < 0 ? "shrub" : "tie", level, geo, tree, "uniform-block-" + std::string(name),
                  std::move(r));
  }
  return glGetError() == GL_NO_ERROR;
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

void archive_tick() {
  archive().tick();
}
bool capture_frame(u64 render_frame) {
  auto& a = archive();
  if (!a.tick())
    return false;
  if (a.selected_logic != a.frame) {
    a.selected_logic = a.frame;
    a.selected_render = render_frame;
  }
  return a.selected_render == render_frame;
}
void archive_blob(const std::string& domain,
                  const std::string& level,
                  int geo,
                  size_t tree,
                  const std::string& name,
                  const void* data,
                  size_t bytes,
                  InputMapping mapping) {
  if (!autoport_proof::feature_is("shrub-trunk-contact"))
    return;
  if (bytes > max_record || (bytes && !data)) {
    fail("archive-blob-invalid");
    return;
  }
  Record r;
  append(r.inputs, data, bytes);
  r.mapped = static_cast<uint8_t>(mapping);
  Bytes id;
  field(id, domain);
  field(id, level);
  number(id, geo);
  number(id, tree);
  field(id, name);
  std::string key(id.begin(), id.end());
  auto old = s_blobs.find(key);
  size_t prior = old == s_blobs.end() ? 0 : old->second.record.inputs.size();
  if (s_blob_bytes - prior + bytes > max_frame) {
    fail("archive-cache-bound");
    return;
  }
  s_blob_bytes = s_blob_bytes - prior + bytes;
  s_blobs[key] = {domain, level, name, geo, tree, std::move(r)};
}
void archive_capture(const std::string& domain,
                     const std::string& level,
                     int geo,
                     size_t tree,
                     const void* inputs,
                     size_t input_bytes,
                     const void* pre,
                     size_t pre_bytes,
                     const void* post,
                     size_t post_bytes) {
  if (!archive().tick())
    return;
  if (!pre_bytes || !post_bytes || input_bytes > max_record || pre_bytes > max_record ||
      post_bytes > max_record || !pre || !post || (input_bytes && !inputs)) {
    fail("archive-capture-invalid");
    return;
  }
  // The reference has no geometry callback. Validate its actual GPU positions too,
  // so identical NaN payloads can never certify unchanged wind/contact.
  if (pre_bytes != post_bytes || pre_bytes % sizeof(float)) {
    fail("archive-position-layout-invalid");
    return;
  }
  for (size_t offset = 0; offset < pre_bytes; offset += sizeof(float)) {
    float before, after;
    std::memcpy(&before, static_cast<const u8*>(pre) + offset, sizeof(float));
    std::memcpy(&after, static_cast<const u8*>(post) + offset, sizeof(float));
    if (!std::isfinite(before) || !std::isfinite(after)) {
      fail("archive-position-nonfinite");
      return;
    }
  }
  for (const auto& [key, blob] : s_blobs) {
    if (blob.level == level && blob.geo == geo && blob.tree == tree)
      archive().add(blob.domain, level, geo, tree, blob.name, blob.record);
  }
  Record r;
  append(r.inputs, inputs, input_bytes);
  append(r.pre, pre, pre_bytes);
  append(r.post, post, post_bytes);
  archive().add(domain, level, geo, tree, "capture", std::move(r));
}

void set_sample_callback(SampleCallback callback) {
  s_callback = callback;
}
u64 errors() {
  return s_errors;
}

void draw_elements(const std::string& level,
                   int geo,
                   size_t tree_index,
                   u64 frame,
                   GLenum mode,
                   GLsizei count,
                   GLenum type,
                   const void* offset) {
  if (!capture_frame(frame) || count == 0) {
    return;
  }
  if (count < 0 || (mode != GL_TRIANGLES && mode != GL_TRIANGLE_STRIP) || type != GL_UNSIGNED_INT) {
    fail("unsupported-draw");
    return;
  }
  frame = u64(pad_replay::current_frame());
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
  const auto* indices = static_cast<const u32*>(
      glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER, index_offset, index_bytes, GL_MAP_READ_BIT));
  if (!indices) {
    fail("element-buffer-map-failed");
    return;
  }
  Bytes observed_inputs;
  number(observed_inputs, mode);
  number(observed_inputs, type);
  number(observed_inputs, restart);
  number(observed_inputs, restart_index);
  field(observed_inputs, indices, index_bytes);
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
    referenced.insert(referenced.end(), indices + segment_begin,
                      indices + segment_begin + complete);
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
  if (!observe_draw(level, geo, tree_index, program, referenced)) {
    fail("draw-input-observation-failed");
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
  const auto* samples = static_cast<const Sample*>(glMapBufferRange(
      GL_TRANSFORM_FEEDBACK_BUFFER, 0, sample_count * sizeof(Sample), GL_MAP_READ_BIT));
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
    Bytes pre, post;
    for (size_t i = 0; i < sample_count; ++i) {
      number(observed_inputs, samples[i].vertex_index);
      append(pre, samples[i].pre, sizeof(samples[i].pre));
      append(post, samples[i].post, sizeof(samples[i].post));
    }
    archive_capture(geo < 0 ? "shrub" : "tie", level, geo, tree_index, observed_inputs.data(),
                    observed_inputs.size(), pre.data(), pre.size(), post.data(), post.size());
    if (s_callback)
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
                        std::chrono::steady_clock::now() - start)
                        .count();
  s_peak_bytes = std::max(s_peak_bytes, u64(bytes));
  publish_stats();
  lg::info(
      "SHRUB-CONTACT-GPU level={} geo={} tree={} frame={} program={} captures={} "
      "vertices={} errors={} cpu_us={} buffer_bytes={}",
      level, geo, tree_index, frame, program, s_captures, s_vertices, s_errors, s_microseconds,
      bytes);
}

void multi_draw_elements(const std::string& level,
                         int geo,
                         size_t tree_index,
                         u64 frame,
                         GLenum mode,
                         const GLsizei* counts,
                         GLenum type,
                         const void* const* offsets,
                         GLsizei drawcount) {
  if (!capture_frame(frame)) {
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
