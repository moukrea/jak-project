#include "soft_baseline.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <vector>

#include "game/system/autoport_proof.h"

#include "third-party/glad/include/glad/glad.h"

namespace soft_baseline {
namespace {
constexpr const char* kItem = "soft-baseline";
constexpr int kIterations = 16;
using Clock = std::chrono::steady_clock;

// Only these states are changed. Texture bindings refer to the original active unit.
struct State {
  GLint draw_fb, read_fb, texture, unpack_buffer, program, vao, viewport[4];
  GLint unpack[4];
  GLboolean color[4], blend;
  static constexpr GLenum caps[] = {GL_DEPTH_TEST,
                                    GL_STENCIL_TEST,
                                    GL_SCISSOR_TEST,
                                    GL_CULL_FACE,
                                    GL_RASTERIZER_DISCARD,
                                    GL_DITHER,
                                    GL_SAMPLE_ALPHA_TO_COVERAGE,
                                    GL_SAMPLE_COVERAGE,
                                    GL_SAMPLE_MASK
#ifndef __ANDROID__
                                    ,
                                    GL_COLOR_LOGIC_OP
#endif
  };
  GLboolean enabled[sizeof(caps) / sizeof(caps[0])];
#ifndef __ANDROID__
  GLint polygon[2];
  std::vector<GLboolean> clip_enabled;
#endif
  State() {
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw_fb);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_fb);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
    glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpack_buffer);
    glGetIntegerv(GL_CURRENT_PROGRAM, &program);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
    glGetIntegerv(GL_VIEWPORT, viewport);
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpack[0]);
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &unpack[1]);
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &unpack[2]);
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &unpack[3]);
    glGetBooleani_v(GL_COLOR_WRITEMASK, 0, color);
    blend = glIsEnabledi(GL_BLEND, 0);
    glDisablei(GL_BLEND, 0);
    glColorMaski(0, GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    for (size_t i = 0; i < sizeof(caps) / sizeof(caps[0]); ++i) {
      enabled[i] = glIsEnabled(caps[i]);
      glDisable(caps[i]);
    }
#ifndef __ANDROID__
    glGetIntegerv(GL_POLYGON_MODE, polygon);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    GLint clip_count = 0;
    glGetIntegerv(GL_MAX_CLIP_DISTANCES, &clip_count);
    for (GLint i = 0; i < clip_count; ++i) {
      clip_enabled.push_back(glIsEnabled(GL_CLIP_DISTANCE0 + i));
      glDisable(GL_CLIP_DISTANCE0 + i);
    }
#endif
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  }
  ~State() {
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw_fb);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fb);
    glBindTexture(GL_TEXTURE_2D, texture);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack_buffer);
    glUseProgram(program);
    glBindVertexArray(vao);
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
    glPixelStorei(GL_UNPACK_ALIGNMENT, unpack[0]);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, unpack[1]);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, unpack[2]);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, unpack[3]);
    glColorMaski(0, color[0], color[1], color[2], color[3]);
    if (blend)
      glEnablei(GL_BLEND, 0);
    else
      glDisablei(GL_BLEND, 0);
    for (size_t i = 0; i < sizeof(caps) / sizeof(caps[0]); ++i) {
      if (enabled[i])
        glEnable(caps[i]);
      else
        glDisable(caps[i]);
    }
#ifndef __ANDROID__
    glPolygonMode(GL_FRONT_AND_BACK, polygon[0]);
    for (size_t i = 0; i < clip_enabled.size(); ++i) {
      if (clip_enabled[i])
        glEnable(GL_CLIP_DISTANCE0 + i);
      else
        glDisable(GL_CLIP_DISTANCE0 + i);
    }
#endif
  }
};

GLuint shader(GLenum kind, const char* body) {
#ifdef __ANDROID__
  const char* version = "#version 320 es\nprecision highp float;\n";
#else
  const char* version = "#version 410 core\n";
#endif
  const char* source[] = {version, body};
  GLuint result = glCreateShader(kind);
  glShaderSource(result, 2, source, nullptr);
  glCompileShader(result);
  GLint ok = 0;
  glGetShaderiv(result, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    glDeleteShader(result);
    return 0;
  }
  return result;
}

void publish_results(const TileBenchmark& result) {
  using namespace autoport_proof;
#ifdef __ANDROID__
  publish_text("soft_tile_target", "android_usb");
#else
  publish_text("soft_tile_target", "x86");
#endif
  publish_text("soft_tile_timer", "cpu_submission_plus_glFinish_completion");
  publish_text("soft_tile_format", "R16_UNORM");
  publish("soft_tile_r16_supported", result.r16_supported);
  publish("soft_tile_cost_gaps", result.gaps);
  for (const auto& tile : result.tiles) {
    if (!tile.measured)
      continue;
    char key[96], value[64];
    std::snprintf(key, sizeof(key), "soft_tile_%d_iterations", tile.side);
    publish(key, tile.iterations);
    std::snprintf(key, sizeof(key), "soft_tile_%d_upload_completion_ms", tile.side);
    std::snprintf(value, sizeof(value), "%.9f", tile.upload_completion_ms);
    publish_text(key, value);
    std::snprintf(key, sizeof(key), "soft_tile_%d_raster_completion_ms", tile.side);
    std::snprintf(value, sizeof(value), "%.9f", tile.raster_completion_ms);
    publish_text(key, value);
  }
}
}  // namespace

const TileBenchmark& measure_tiles_once() {
  static TileBenchmark result;
  if (result.attempted || !autoport_proof::feature_is(kItem) || !autoport_proof::armed_for(kItem))
    return result;
  result.attempted = true;
  auto finish = [&]() -> const TileBenchmark& {
    publish_results(result);
    return result;
  };
  auto fail = [&](const char* reason) -> const TileBenchmark& {
    autoport_proof::publish_text("soft_tile_failure", reason);
    return finish();
  };
  // Establish the error boundary BEFORE any benchmark GL call. Startup may leave
  // renderer errors pending; retain every observed code without attributing them
  // to this measurement. Only a bounded, demonstrably empty queue admits the run.
  // Errors after this boundary belong to setup/measurement and still fail it.
  unsigned prior_errors = 0;
  bool error_boundary_empty = false;
  for (unsigned query = 0; query < 16; ++query) {
    const GLenum error = glGetError();
    if (error == GL_NO_ERROR) {
      error_boundary_empty = true;
      break;
    }
    if (prior_errors == 0)
      autoport_proof::publish("soft_tile_prior_gl_error", error);
    char key[64];
    std::snprintf(key, sizeof(key), "soft_tile_prior_gl_error_%u", prior_errors);
    autoport_proof::publish(key, error);
    ++prior_errors;
  }
  autoport_proof::publish("soft_tile_prior_gl_error_count", prior_errors);
  autoport_proof::publish("soft_tile_error_boundary_empty", error_boundary_empty);
  if (!error_boundary_empty)
    return fail("prior_GL_error_queue_not_drained");

  const auto* renderer = glGetString(GL_RENDERER);
  autoport_proof::publish_text("soft_tile_renderer", renderer ? (const char*)renderer : "unknown");
#ifdef __ANDROID__
  GLint count = 0;
  glGetIntegerv(GL_NUM_EXTENSIONS, &count);
  for (GLint i = 0; i < count; ++i) {
    const auto* ext = glGetStringi(GL_EXTENSIONS, i);
    if (ext && std::strcmp((const char*)ext, "GL_EXT_texture_norm16") == 0)
      result.r16_supported = true;
  }
#else
  result.r16_supported = true;  // R16 is core in the required desktop GL context.
#endif
  if (!result.r16_supported)
    return fail("R16_UNORM_unsupported");
  if (!glColorMaski || !glGetBooleani_v || !glIsEnabledi || !glDisablei || !glEnablei)
    return fail("indexed_state_entrypoint_missing");
  const GLenum capability_error = glGetError();
  if (capability_error != GL_NO_ERROR) {
    autoport_proof::publish("soft_tile_gl_error", capability_error);
    return fail("capability_query_GL_error");
  }
  State state;
  GLuint vs = shader(GL_VERTEX_SHADER,
                     "void main(){vec2 p=vec2(float(gl_VertexID&1),float((gl_VertexID>>1)&1));"
                     "gl_Position=vec4(p*2.0-1.0,0.0,1.0);}\n");
  GLuint fs =
      shader(GL_FRAGMENT_SHADER,
             "layout(location=0) out vec4 color;void main(){color=vec4(0.5,0.0,0.0,1.0);}\n");
  GLuint program = glCreateProgram();
  if (vs)
    glAttachShader(program, vs);
  if (fs)
    glAttachShader(program, fs);
  glLinkProgram(program);
  GLint linked = 0;
  glGetProgramiv(program, GL_LINK_STATUS, &linked);
  if (vs)
    glDeleteShader(vs);
  if (fs)
    glDeleteShader(fs);
  if (!linked) {
    glDeleteProgram(program);
    return fail("shader_link_failed");
  }
  GLuint texture = 0, framebuffer = 0, vao = 0;
  glGenTextures(1, &texture);
  glGenFramebuffers(1, &framebuffer);
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glUseProgram(program);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, framebuffer);
  const GLenum attachment = GL_COLOR_ATTACHMENT0;
  glDrawBuffers(1, &attachment);
  for (int i = 0; i < 2; ++i) {
    auto& tile = result.tiles[i];
    tile.side = i == 0 ? 64 : 128;
    std::vector<uint16_t> data(tile.side * tile.side, 32768);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R16, tile.side, tile.side, 0, GL_RED, GL_UNSIGNED_SHORT,
                 data.data());
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    GLenum status = glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER);
    GLenum error = glGetError();
    if (status != GL_FRAMEBUFFER_COMPLETE || error != GL_NO_ERROR) {
      autoport_proof::publish("soft_tile_framebuffer_status", status);
      autoport_proof::publish("soft_tile_gl_error", error);
      autoport_proof::publish_text("soft_tile_failure", "R16_allocation_or_framebuffer_failed");
      break;
    }
    glViewport(0, 0, tile.side, tile.side);
    // Warm both paths before timing, including shader compilation deferred by the driver.
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tile.side, tile.side, GL_RED, GL_UNSIGNED_SHORT,
                    data.data());
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glFinish();
    auto start = Clock::now();
    for (int n = 0; n < kIterations; ++n) {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tile.side, tile.side, GL_RED, GL_UNSIGNED_SHORT,
                      data.data());
      glFinish();
    }
    tile.upload_completion_ms =
        std::chrono::duration<double, std::milli>(Clock::now() - start).count() / kIterations;
    start = Clock::now();
    for (int n = 0; n < kIterations; ++n) {
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      glFinish();
    }
    tile.raster_completion_ms =
        std::chrono::duration<double, std::milli>(Clock::now() - start).count() / kIterations;
    error = glGetError();
    if (error != GL_NO_ERROR) {
      autoport_proof::publish("soft_tile_gl_error", error);
      autoport_proof::publish_text("soft_tile_failure", "measurement_GL_error");
      break;
    }
    tile.iterations = kIterations;
    tile.measured = true;
    --result.gaps;
  }
  glDeleteFramebuffers(1, &framebuffer);
  glDeleteTextures(1, &texture);
  glDeleteVertexArrays(1, &vao);
  glDeleteProgram(program);
  return finish();
}
}  // namespace soft_baseline
