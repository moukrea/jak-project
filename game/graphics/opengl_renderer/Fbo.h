#pragma once

#include <cstdio>
#include <optional>

#include "game/graphics/pipelines/opengl.h"

struct Fbo {
  bool valid = false;  // do we have an OpenGL fbo_id?
  GLuint fbo_id = -1;

  // optional rgba/zbuffer/stencil data.
  std::optional<GLuint> tex_id;
  std::optional<GLuint> zbuf_stencil_id;

  bool multisampled = false;
  int multisample_count = 0;  // Should be 1 if multisampled is disabled

  // Grecharged-ambient-occlusion: when set, zbuf_stencil_id names a GL_TEXTURE_2D
  // (DEPTH24_STENCIL8) instead of a renderbuffer, so the AO pass can sample scene
  // depth. Only ever true on the non-multisampled render FBO with AO enabled;
  // OFF == the stock renderbuffer path (clear() deletes it as a renderbuffer).
  bool zbuf_is_texture = false;

  bool is_window = false;
  int width = 640;
  int height = 480;

  // Does this fbo match the given format? MSAA = 1 will accept a normal buffer, or a multisample 1x
  bool matches(int w, int h, int msaa) const {
    int effective_msaa = multisampled ? multisample_count : 1;
    return valid && width == w && height == h && effective_msaa == msaa;
  }

  bool matches(const Fbo& other) const {
    return matches(other.width, other.height, other.multisample_count);
  }

  // Free opengl resources, if we have any.
  void clear() {
    if (valid) {
      glDeleteFramebuffers(1, &fbo_id);
      fbo_id = -1;

      if (tex_id) {
#ifdef __ANDROID__
        fprintf(stderr, "F1E-DELTEX site=fbo tex=%u\n", (unsigned)tex_id.value());
#endif
        glDeleteTextures(1, &tex_id.value());
        tex_id.reset();
      }

      if (zbuf_stencil_id) {
        // Grecharged-ambient-occlusion: the depth attachment is a texture when AO is
        // on (so it can be sampled), a renderbuffer otherwise (stock path).
        if (zbuf_is_texture) {
          glDeleteTextures(1, &zbuf_stencil_id.value());
        } else {
          glDeleteRenderbuffers(1, &zbuf_stencil_id.value());
        }
        zbuf_stencil_id.reset();
        zbuf_is_texture = false;
      }

      valid = false;
    }
  }
};
