#pragma once
// The standalone EGL test uses system GLES3; the engine uses its existing glad loader.
#ifdef AO_CONTACT_READBACK_GLES3
#include <GLES3/gl3.h>
#else
#include "third-party/glad/include/glad/glad.h"
#endif
// This helper changes only read-framebuffer/read-buffer and pixel-pack state.
// Existing GL errors are consumed, reported, and cause failure before any mutation.
#include <cstddef>
#include <cstdint>
#include <exception>
#include <vector>
namespace ao_contact_readback {
struct Error {
  const char* reason;
  GLenum code;
};
struct Result {
  std::vector<uint8_t> pixels;
  std::vector<Error> errors;
  bool ok() const { return errors.empty(); }
};
inline bool dimensions(int w, int h, size_t& bytes) {
  constexpr size_t limit = 64u * 1024u * 1024u;
  if (w <= 0 || h <= 0 || size_t(w) > limit / size_t(h))
    return false;
  bytes = size_t(w) * size_t(h);
  return true;
}
// Covers export_depth initialization as well as the fullscreen draw. Restore is explicit
// so restoration errors participate in the result; destructor also covers early exits.
class ExportState {
 public:
  std::vector<Error> errors;
  bool collect(const char* stage) {
    for (GLenum e; (e = glGetError()) != GL_NO_ERROR;) errors.push_back({stage, e});
    return errors.empty();
  }
  ExportState() {
    if (!collect("export-prior-error")) return;
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) glGetIntegerv(keys[i], &values[i]);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &active_texture);
    glGetIntegerv(GL_VIEWPORT, viewport);
    glGetBooleanv(GL_COLOR_WRITEMASK, color);
    glGetBooleanv(GL_DEPTH_WRITEMASK, &depth);
    for (size_t i = 0; i < sizeof(caps) / sizeof(caps[0]); ++i) enabled[i] = glIsEnabled(caps[i]);
    for (int i = 0; i < 2; ++i) {
      glActiveTexture(GL_TEXTURE0 + i);
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &textures[i]);
      glGetIntegerv(GL_SAMPLER_BINDING, &samplers[i]);
    }
    glActiveTexture(values[5]);
    captured = true;
    if (!collect("export-snapshot-error")) return;
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    for (size_t i = 8; i < sizeof(keys) / sizeof(keys[0]); ++i)
      glPixelStorei(keys[i], (keys[i] == GL_PACK_ALIGNMENT || keys[i] == GL_UNPACK_ALIGNMENT) ? 1 : 0);
    glBindSampler(0, 0); glBindSampler(1, 0);
    glDisable(GL_RASTERIZER_DISCARD);
    glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE);
    glDisable(GL_SAMPLE_COVERAGE);
    glDisable(GL_DITHER);
    collect("export-neutralize-error");
  }
  bool restore() {
    if (!captured) return errors.empty();
    captured = false;
    glUseProgram(values[0]);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, values[1]);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, values[2]);
    glBindVertexArray(values[3]);
    glBindBuffer(GL_ARRAY_BUFFER, values[4]);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, values[6]);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, values[7]);
    for (size_t i = 8; i < sizeof(keys) / sizeof(keys[0]); ++i) glPixelStorei(keys[i], values[i]);
    for (int i = 0; i < 2; ++i) {
      glActiveTexture(GL_TEXTURE0 + i); glBindTexture(GL_TEXTURE_2D, textures[i]);
      glBindSampler(i, samplers[i]);
    }
    // Initialization may bind a texture on the originally active unit, too.
    glActiveTexture(values[5]);
    glBindTexture(GL_TEXTURE_2D, active_texture);
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
    glColorMask(color[0], color[1], color[2], color[3]); glDepthMask(depth);
    for (size_t i = 0; i < sizeof(caps) / sizeof(caps[0]); ++i)
      if (enabled[i]) glEnable(caps[i]); else glDisable(caps[i]);
    return collect("export-restore-error");
  }
  ~ExportState() { restore(); }
 private:
  const GLenum keys[16] = {GL_CURRENT_PROGRAM, GL_DRAW_FRAMEBUFFER_BINDING,
    GL_READ_FRAMEBUFFER_BINDING, GL_VERTEX_ARRAY_BINDING, GL_ARRAY_BUFFER_BINDING,
    GL_ACTIVE_TEXTURE, GL_PIXEL_PACK_BUFFER_BINDING, GL_PIXEL_UNPACK_BUFFER_BINDING,
    GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH, GL_PACK_SKIP_ROWS, GL_PACK_SKIP_PIXELS,
    GL_UNPACK_ALIGNMENT, GL_UNPACK_ROW_LENGTH, GL_UNPACK_SKIP_ROWS, GL_UNPACK_SKIP_PIXELS};
  const GLenum caps[9] = {GL_BLEND, GL_DEPTH_TEST, GL_STENCIL_TEST, GL_SCISSOR_TEST,
    GL_CULL_FACE, GL_RASTERIZER_DISCARD, GL_SAMPLE_ALPHA_TO_COVERAGE, GL_SAMPLE_COVERAGE, GL_DITHER};
  GLint values[16] = {}, viewport[4] = {}, textures[2] = {}, samplers[2] = {};
  GLint active_texture = 0;
  GLboolean color[4] = {}, depth = GL_FALSE, enabled[9] = {};
  bool captured = false;
};
inline Result read(GLuint fbo, int w, int h, bool rgba = false) {
  Result result;
  auto& pixels = result.pixels;
  auto fail = [&](const char* reason) { result.errors.push_back({reason, GL_NO_ERROR}); };
  auto errors = [&](const char* reason) {
    for (GLenum e; (e = glGetError()) != GL_NO_ERROR;)
      result.errors.push_back({reason, e});
  };
  size_t n = 0;
  if (!dimensions(w, h, n)) {
    fail("invalid-dimensions");
    return result;
  }
  try {
    pixels.resize(n * (rgba ? 4 : 1));
  } catch (const std::exception&) {
    fail("allocation");
    return result;
  }
  errors("prior-gl-error");
  if (!result.ok())
    return result;
  GLint read_fbo = 0, read_buffer = 0, target_buffer = 0, pack_buffer = 0;
  GLint alignment = 0, row_length = 0, skip_rows = 0, skip_pixels = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_fbo);
  glGetIntegerv(GL_READ_BUFFER, &read_buffer);
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack_buffer);
  glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
  glGetIntegerv(GL_PACK_ROW_LENGTH, &row_length);
  glGetIntegerv(GL_PACK_SKIP_ROWS, &skip_rows);
  glGetIntegerv(GL_PACK_SKIP_PIXELS, &skip_pixels);
  errors("snapshot-gl-error");
  if (!result.ok())
    return result;
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
  glGetIntegerv(GL_READ_BUFFER, &target_buffer);
  errors("target-snapshot-gl-error");
  if (result.ok()) {
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
      fail("incomplete-read-framebuffer");
    if (result.ok())
      glReadPixels(0, 0, w, h, rgba ? GL_RGBA : GL_RED, GL_UNSIGNED_BYTE, pixels.data());
    errors("readback-gl-error");
    glReadBuffer(target_buffer);
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fbo);
  glReadBuffer(read_buffer);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, pack_buffer);
  glPixelStorei(GL_PACK_ALIGNMENT, alignment);
  glPixelStorei(GL_PACK_ROW_LENGTH, row_length);
  glPixelStorei(GL_PACK_SKIP_ROWS, skip_rows);
  glPixelStorei(GL_PACK_SKIP_PIXELS, skip_pixels);
  errors("restore-gl-error");
  if (!result.ok())
    return result;
  return result;
}
}  // namespace ao_contact_readback
