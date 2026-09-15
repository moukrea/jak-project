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
inline Result read(GLuint fbo, int w, int h) {
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
    pixels.resize(n);
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
      glReadPixels(0, 0, w, h, GL_RED, GL_UNSIGNED_BYTE, pixels.data());
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
