#define AO_CONTACT_READBACK_GLES3
#include <array>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "game/graphics/opengl_renderer/ao_contact_readback.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#define CHECK(x)                                                                      \
  do {                                                                                \
    if (!(x)) {                                                                       \
      std::fprintf(stderr, "FAIL line=%d expression=%s gl=%x egl=%x\n", __LINE__, #x, \
                   glGetError(), eglGetError());                                      \
      std::exit(1);                                                                   \
    }                                                                                 \
  } while (0)
constexpr int W = 7, H = 5;
const GLenum fields[] = {GL_READ_FRAMEBUFFER_BINDING,
                         GL_READ_BUFFER,
                         GL_DRAW_FRAMEBUFFER_BINDING,
                         GL_DRAW_BUFFER0,
                         GL_PIXEL_PACK_BUFFER_BINDING,
                         GL_PACK_ALIGNMENT,
                         GL_PACK_ROW_LENGTH,
                         GL_PACK_SKIP_ROWS,
                         GL_PACK_SKIP_PIXELS,
                         GL_BLEND_SRC_RGB,
                         GL_BLEND_DST_RGB,
                         GL_BLEND_SRC_ALPHA,
                         GL_BLEND_DST_ALPHA,
                         GL_BLEND_EQUATION_RGB,
                         GL_BLEND_EQUATION_ALPHA,
                         GL_DEPTH_FUNC,
                         GL_DEPTH_WRITEMASK,
                         GL_CURRENT_PROGRAM,
                         GL_VERTEX_ARRAY_BINDING,
                         GL_ACTIVE_TEXTURE,
                         GL_TEXTURE_BINDING_2D,
                         GL_ARRAY_BUFFER_BINDING,
                         GL_PIXEL_UNPACK_BUFFER_BINDING};
std::vector<GLint> state() {
  std::vector<GLint> v;
  for (auto key : fields) {
    GLint x;
    glGetIntegerv(key, &x);
    v.push_back(x);
  }
  for (auto key : {GL_BLEND, GL_DEPTH_TEST, GL_SCISSOR_TEST, GL_CULL_FACE, GL_DITHER})
    v.push_back(glIsEnabled(key));
  GLint x[4];
  glGetIntegerv(GL_VIEWPORT, x);
  v.insert(v.end(), x, x + 4);
  glGetIntegerv(GL_COLOR_WRITEMASK, x);
  v.insert(v.end(), x, x + 4);
  GLfloat f[4];
  glGetFloatv(GL_BLEND_COLOR, f);
  for (float q : f) {
    GLint bits;
    std::memcpy(&bits, &q, 4);
    v.push_back(bits);
  }
  CHECK(glGetError() == GL_NO_ERROR);
  return v;
}
GLuint shader(GLenum type, const char* src) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, nullptr);
  glCompileShader(s);
  GLint ok;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  CHECK(ok);
  return s;
}
int main() {
  auto getDisplay = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
  CHECK(getDisplay);
  EGLDisplay d = getDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr);
  CHECK(d != EGL_NO_DISPLAY);
  CHECK(eglInitialize(d, nullptr, nullptr));
  CHECK(eglBindAPI(EGL_OPENGL_ES_API));
  EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
                    EGL_NONE};
  EGLConfig cfg;
  EGLint count;
  CHECK(eglChooseConfig(d, attrs, &cfg, 1, &count) && count == 1);
  EGLint ctxAttrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, ctxAttrs);
  CHECK(c != EGL_NO_CONTEXT);
  CHECK(eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, c));
  std::printf("GL_VENDOR=%s\nGL_RENDERER=%s\nGL_VERSION=%s\n", glGetString(GL_VENDOR),
              glGetString(GL_RENDERER), glGetString(GL_VERSION));
  GLuint tex[3], fbo[3];
  glGenTextures(3, tex);
  glGenFramebuffers(3, fbo);
  for (int i = 0; i < 3; ++i) {
    glBindTexture(GL_TEXTURE_2D, tex[i]);
    glTexStorage2D(GL_TEXTURE_2D, 1, GL_R8, W, H);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo[i]);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex[i], 0);
    CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    glClearColor(float(i + 1) / 4, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
  }
  const char* vs =
      "#version 300 es\nvoid main(){vec2 "
      "p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);gl_Position=vec4(p*2.-1.,0.,1.);}";
  const char* fs =
      "#version 300 es\nprecision highp float;out vec4 color;void "
      "main(){color=vec4((gl_FragCoord.x+gl_FragCoord.y*7.)/48.,0.,0.,1.);}";
  GLuint prog = glCreateProgram();
  glAttachShader(prog, shader(GL_VERTEX_SHADER, vs));
  glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs));
  glLinkProgram(prog);
  GLint linked;
  glGetProgramiv(prog, GL_LINK_STATUS, &linked);
  CHECK(linked);
  glUseProgram(prog);
  GLuint vao;
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glViewport(0, 0, W, H);
  glEnable(GL_BLEND);
  glBlendFuncSeparate(GL_ONE, GL_ZERO, GL_ZERO, GL_ONE);
  glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_REVERSE_SUBTRACT);
  glBlendColor(.1, .2, .3, .4);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glDepthMask(GL_FALSE);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo[2]);
  glDrawArrays(GL_TRIANGLES, 0, 3);
  CHECK(glGetError() == GL_NO_ERROR);
  auto baseline = ao_contact_readback::read(fbo[2], W, H);
  CHECK(baseline.ok());
  auto target = ao_contact_readback::read(fbo[0], W, H);
  CHECK(target.ok());
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo[0]);
  glReadBuffer(GL_NONE);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo[1]);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  GLuint pbo;
  glGenBuffers(1, &pbo);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, pbo);
  std::array<unsigned char, 2048> sentinel;
  sentinel.fill(0xA7);
  glBufferData(GL_PIXEL_PACK_BUFFER, sentinel.size(), sentinel.data(), GL_STATIC_READ);
  glPixelStorei(GL_PACK_ALIGNMENT, 8);
  glPixelStorei(GL_PACK_ROW_LENGTH, 19);
  glPixelStorei(GL_PACK_SKIP_ROWS, 3);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 2);
  const auto before = state();
  auto captured = ao_contact_readback::read(fbo[0], W, H);
  CHECK(captured.ok());
  CHECK(captured.pixels == target.pixels);
  CHECK(state() == before);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo[0]);
  GLint rb;
  glGetIntegerv(GL_READ_BUFFER, &rb);
  CHECK(rb == GL_NONE);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo[1]);
  CHECK(state() == before);
  void* mapped = glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, sentinel.size(), GL_MAP_READ_BIT);
  CHECK(mapped);
  CHECK(std::memcmp(mapped, sentinel.data(), sentinel.size()) == 0);
  CHECK(glUnmapBuffer(GL_PIXEL_PACK_BUFFER));
  // Draw again using the untouched state and verify the rendered bytes.
  glDrawArrays(GL_TRIANGLES, 0, 3);
  auto after = ao_contact_readback::read(fbo[2], W, H);
  CHECK(after.ok());
  CHECK(after.pixels == baseline.pixels);
  CHECK(state() == before);
  // Exercise initialization mutations, including a nonzero active texture and unpack PBO.
  glActiveTexture(GL_TEXTURE5); glBindTexture(GL_TEXTURE_2D, tex[1]);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 8); glPixelStorei(GL_UNPACK_ROW_LENGTH, 17);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 2); glPixelStorei(GL_UNPACK_SKIP_PIXELS, 3);
  const auto export_before = state();
  ao_contact_readback::ExportState export_state;
  CHECK(export_state.errors.empty());
  GLint neutral;
  glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &neutral); CHECK(neutral == 0);
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &neutral); CHECK(neutral == 0);
  glBindTexture(GL_TEXTURE_2D, tex[0]); glBindVertexArray(0);
  glBindFramebuffer(GL_FRAMEBUFFER, fbo[0]); glViewport(1, 2, 3, 4);
  glColorMask(GL_FALSE, GL_TRUE, GL_FALSE, GL_TRUE); glDepthMask(GL_TRUE);
  glDisable(GL_BLEND); glDisable(GL_DEPTH_TEST); glUseProgram(0);
  CHECK(export_state.restore()); CHECK(state() == export_before);
  glGetIntegerv(GL_UNPACK_ROW_LENGTH, &neutral); CHECK(neutral == 17);
  glGetIntegerv(GL_UNPACK_SKIP_ROWS, &neutral); CHECK(neutral == 2);
  glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &neutral); CHECK(neutral == 3);
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &neutral); CHECK(neutral == 8);
  glDrawArrays(GL_TRIANGLES, 0, 3);
  auto export_after = ao_contact_readback::read(fbo[2], W, H);
  CHECK(export_after.ok() && export_after.pixels == baseline.pixels);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0); glActiveTexture(GL_TEXTURE0);
  CHECK(state() == before);
  std::printf("PASS export_state_equal=1 export_subsequent_draw_identical=1 unpack_restored=1 active_texture5_restored=1\n");
  for (auto wh : {std::array<int, 2>{0, H}, {W, -1}, {INT_MAX, INT_MAX}}) {
    auto bad = ao_contact_readback::read(fbo[0], wh[0], wh[1]);
    CHECK(!bad.ok());
    CHECK(bad.pixels.empty());
    CHECK(state() == before);
  }
  glEnable(0xFFFFFFFFu);
  auto prior = ao_contact_readback::read(fbo[0], W, H);
  CHECK(!prior.ok());
  CHECK(std::strcmp(prior.errors[0].reason, "prior-gl-error") == 0);
  CHECK(prior.errors[0].code == GL_INVALID_ENUM);
  CHECK(state() == before);
  std::printf(
      "PASS pixels_bit_identical=1 subsequent_draw_bit_identical=1 state_equal=1 "
      "target_read_buffer_none=1 pbo_unchanged=1 invalid_dimensions_rejected=3 "
      "prior_error_rejected=1\n");
  eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroyContext(d, c);
  eglTerminate(d);
  return 0;
}
