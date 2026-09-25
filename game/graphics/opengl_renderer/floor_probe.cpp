#include "floor_probe.h"

#ifndef __ANDROID__
#include <cmath>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>
#include "game/graphics/opengl_renderer/flip_census.h"
#include "game/system/autoport_proof.h"
#include "common/log/log.h"
#include "third-party/glad/include/glad/glad.h"
#endif

namespace floor_probe {

#ifndef __ANDROID__
namespace {
constexpr const char* kItem = "lighting-regimes";
AUTOPORT_FEATURE_SITE(kItem);

// Etat de l'image en cours.
bool g_last_frame_valid = false;
uint64_t g_last_frame_idx = 0;
bool g_this_frame_probing = false;
bool g_attached = false;    // texture de sonde attachee au FBO de rendu pour cette image
bool g_draw_active = false; // entre before_tfrag_draw et after_tfrag_draw courants
std::string g_this_frame_level;

GLuint g_probe_tex = 0;
int g_tex_w = 0, g_tex_h = 0;
GLint g_target_fbo = 0;  // FBO de rendu auquel g_probe_tex est attachee

// Capture de l'image sondee precedente, en attente de lecture.
bool g_pending = false;
GLuint g_pending_tex = 0;
int g_pending_w = 0, g_pending_h = 0;
GLint g_pending_fbo = 0;
std::string g_pending_level;

GLuint g_reader_fbo = 0;

GLint g_saved_draw_bufs[4] = {};
GLint g_saved_program = 0;
GLuint g_active_program = 0;

std::unordered_map<GLuint, GLint> g_uniform_loc_cache;

struct Acc {
  uint64_t n = 0, dark = 0, flip_n = 0, lit_n = 0;
  double sum_ratio = 0, sum_shadow_sun = 0;
};
std::map<std::string, Acc> g_acc;

uint64_t g_frames_read = 0;
uint64_t g_refused = 0;
uint64_t g_uniform_missing = 0;
uint64_t g_black_tex = 0;
uint64_t g_nan_px = 0;  // sol dont le rapport n'est pas un nombre : compte, jamais somme

std::string sanitize(const std::string& s) {
  std::string out = s.empty() ? std::string("unknown") : s;
  for (auto& c : out) {
    if (!isalnum((unsigned char)c) && c != '_') c = '_';
  }
  if (!isalpha((unsigned char)out[0]) && out[0] != '_') out = "l_" + out;
  return out;
}

void refused(const char* why) {
  ++g_refused;
  autoport_proof::publish("floor_probe_refused", g_refused);
  autoport_proof::publish_text("floor_probe_refused_why", why);
}

GLint uniform_loc(GLuint program) {
  auto it = g_uniform_loc_cache.find(program);
  if (it != g_uniform_loc_cache.end()) return it->second;
  GLint loc = glGetUniformLocation(program, "u_floor_probe");
  g_uniform_loc_cache.emplace(program, loc);
  return loc;
}

void publish_level(const std::string& lvl, const Acc& a) {
  if (a.n == 0) return;
  autoport_proof::publish(("floor_px_" + lvl).c_str(), a.n);
  autoport_proof::publish(("floor_on_off_x1000_" + lvl).c_str(),
                          (uint64_t)std::lround(1000.0 * a.sum_ratio / (double)a.n));
  autoport_proof::publish(("floor_dark_px_ppm_" + lvl).c_str(),
                          (uint64_t)std::lround(1e6 * (double)a.dark / (double)a.n));
  autoport_proof::publish(("floor_normal_flipped_ppm_" + lvl).c_str(),
                          (uint64_t)std::lround(1e6 * (double)a.flip_n / (double)a.n));
  autoport_proof::publish(("floor_sunlit_px_ppm_" + lvl).c_str(),
                          (uint64_t)std::lround(1e6 * (double)a.lit_n / (double)a.n));
  if (a.lit_n > 0) {
    double shadow_sun = 1000.0 * a.sum_shadow_sun / (double)a.lit_n;
    autoport_proof::publish(("floor_shadow_sun_x1000_" + lvl).c_str(),
                            (uint64_t)std::lround(shadow_sun));
    double direct_share = 1000.0 - shadow_sun;
    if (direct_share < 0) direct_share = 0;
    autoport_proof::publish(("floor_direct_share_x1000_" + lvl).c_str(),
                            (uint64_t)std::lround(direct_share));
  }
  lg::info(
      "[floor-probe] lvl={} n={} on_off={:.3f} dark={:.4f} flip={:.4f} lit={:.4f} "
      "shadow_sun={:.3f}",
      lvl, a.n, a.sum_ratio / (double)a.n, (double)a.dark / (double)a.n,
      (double)a.flip_n / (double)a.n, (double)a.lit_n / (double)a.n,
      a.lit_n > 0 ? a.sum_shadow_sun / (double)a.lit_n : 0.0);
}

void publish_summary() {
  uint64_t dark_levels = 0, measured_levels = 0;
  for (auto& kv : g_acc) {
    if (kv.second.n >= 1000) {
      ++measured_levels;
      double mean = kv.second.sum_ratio / (double)kv.second.n;
      if (mean < 0.5) ++dark_levels;
    }
  }
  autoport_proof::publish("floor_dark_levels", dark_levels);
  autoport_proof::publish("floor_levels_measured", measured_levels);
}

void accumulate(const std::string& level, const std::vector<float>& pix, int w, int h) {
  Acc& acc = g_acc[sanitize(level)];
  const size_t count = (size_t)w * (size_t)h;
  for (size_t i = 0; i < count; ++i) {
    const float* p = &pix[i * 4];
    float x = p[0], y = p[1], z = p[2], wv = p[3];
    if (wv == 0.0f) continue;         // aucun decor
    if (wv < 0.75f) continue;         // decor non-sol
    int bits = (int)std::lround(wv) - 1;
    bool flip = (bits & 2) != 0;
    bool lit = (bits & 4) != 0;
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) {
      ++g_nan_px;
      continue;
    }
    if (z < 0.02f) {
      ++g_black_tex;
      continue;
    }
    acc.n++;
    acc.sum_ratio += x;
    if (x < 0.5f) acc.dark++;
    if (flip) acc.flip_n++;
    if (lit) {
      acc.lit_n++;
      float sy = y;
      if (sy < 0.0f) sy = 0.0f;
      if (sy > 2.0f) sy = 2.0f;
      acc.sum_shadow_sun += sy;
    }
  }
  autoport_proof::publish("floor_px_black_tex", g_black_tex);
  autoport_proof::publish("floor_px_nan", g_nan_px);
  publish_level(sanitize(level), acc);
  publish_summary();
}

void do_read_and_detach() {
  GLint old_draw, old_read;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &old_draw);
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
  if (g_reader_fbo == 0) glGenFramebuffers(1, &g_reader_fbo);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_reader_fbo);
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_pending_tex,
                         0);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  const bool ready = glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  std::vector<float> pix;
  bool ok = false;
  if (ready) {
    GLint pack, align, row, skipx, skipy;
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack);
    glGetIntegerv(GL_PACK_ALIGNMENT, &align);
    glGetIntegerv(GL_PACK_ROW_LENGTH, &row);
    glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipx);
    glGetIntegerv(GL_PACK_SKIP_ROWS, &skipy);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    pix.resize((size_t)g_pending_w * (size_t)g_pending_h * 4);
    const GLenum prior_error = glGetError();
    if (prior_error == GL_NO_ERROR) {
      glReadPixels(0, 0, g_pending_w, g_pending_h, GL_RGBA, GL_FLOAT, pix.data());
    }
    const GLenum read_error = glGetError();
    ok = prior_error == GL_NO_ERROR && read_error == GL_NO_ERROR;
    glBindBuffer(GL_PIXEL_PACK_BUFFER, pack);
    glPixelStorei(GL_PACK_ALIGNMENT, align);
    glPixelStorei(GL_PACK_ROW_LENGTH, row);
    glPixelStorei(GL_PACK_SKIP_PIXELS, skipx);
    glPixelStorei(GL_PACK_SKIP_ROWS, skipy);
  }
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
  glBindFramebuffer(GL_FRAMEBUFFER, g_pending_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT4, GL_TEXTURE_2D, 0, 0);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, old_draw);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
  if (!ready || !ok) {
    refused("float_readback_failed_or_prior_gl_error");
    return;
  }
  ++g_frames_read;
  autoport_proof::publish("floor_probe_frames", g_frames_read);
  accumulate(g_pending_level, pix, g_pending_w, g_pending_h);
}

void attach_for_frame() {
  GLint fbo, samples, maxbuf;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &fbo);
  glGetIntegerv(GL_SAMPLES, &samples);
  if (!fbo || samples != 0) {
    refused("msaa_or_default_fbo");
    return;
  }
  glGetIntegerv(GL_MAX_DRAW_BUFFERS, &maxbuf);
  if (maxbuf < 5) {
    refused("mrt_unavailable");
    return;
  }
  GLint kind = GL_NONE;
  glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                       GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &kind);
  int w = 0, h = 0;
  if (kind == GL_TEXTURE) {
    GLint name = 0;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                         GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &name);
    GLint prev_tex;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex);
    glBindTexture(GL_TEXTURE_2D, name);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &w);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &h);
    glBindTexture(GL_TEXTURE_2D, prev_tex);
  } else if (kind == GL_RENDERBUFFER) {
    GLint name = 0;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                         GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &name);
    GLint prev_rb;
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &prev_rb);
    glBindRenderbuffer(GL_RENDERBUFFER, name);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &w);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &h);
    glBindRenderbuffer(GL_RENDERBUFFER, prev_rb);
  } else {
    refused("attachment0_missing");
    return;
  }
  if (w <= 0 || h <= 0) {
    refused("bad_size");
    return;
  }
  if (g_probe_tex == 0 || g_tex_w != w || g_tex_h != h) {
    if (g_probe_tex) glDeleteTextures(1, &g_probe_tex);
    glGenTextures(1, &g_probe_tex);
    glBindTexture(GL_TEXTURE_2D, g_probe_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, w, h, 0, GL_RGBA, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    g_tex_w = w;
    g_tex_h = h;
  }
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT4, GL_TEXTURE_2D, g_probe_tex, 0);
  if (glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT4, GL_TEXTURE_2D, 0, 0);
    refused("rgba32f_fbo_incomplete");
    return;
  }
  GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
  glDisable(GL_SCISSOR_TEST);
  const float zero[4] = {};
  glClearBufferfv(GL_COLOR, 4, zero);
  if (scissor) glEnable(GL_SCISSOR_TEST);
  g_target_fbo = fbo;
  g_attached = true;
}

}  // namespace
#endif  // !__ANDROID__

void before_tfrag_draw(unsigned program, uint64_t frame_idx, const std::string& level_name) {
#ifndef __ANDROID__
  if (flip_census::active()) return;
  if (!autoport_proof::armed_for(kItem)) return;
  const bool new_frame = !g_last_frame_valid || frame_idx != g_last_frame_idx;
  if (new_frame) {
    if (g_attached) {
      g_pending = true;
      g_pending_tex = g_probe_tex;
      g_pending_w = g_tex_w;
      g_pending_h = g_tex_h;
      g_pending_fbo = g_target_fbo;
      g_pending_level = g_this_frame_level;
    }
    if (g_pending) {
      do_read_and_detach();
      g_pending = false;
    }
    g_attached = false;
    g_last_frame_valid = true;
    g_last_frame_idx = frame_idx;
    g_this_frame_probing = (frame_idx % 30 == 0) && frame_idx >= 300;
    g_this_frame_level.clear();
    if (g_this_frame_probing) attach_for_frame();
  }
  if (!g_this_frame_probing || !g_attached) return;
  if (g_this_frame_level.empty() && !level_name.empty()) g_this_frame_level = level_name;

  glGetIntegerv(GL_DRAW_BUFFER0, &g_saved_draw_bufs[0]);
  glGetIntegerv(GL_DRAW_BUFFER1, &g_saved_draw_bufs[1]);
  glGetIntegerv(GL_DRAW_BUFFER2, &g_saved_draw_bufs[2]);
  glGetIntegerv(GL_DRAW_BUFFER3, &g_saved_draw_bufs[3]);
  GLenum bufs[5] = {(GLenum)g_saved_draw_bufs[0], (GLenum)g_saved_draw_bufs[1],
                    (GLenum)g_saved_draw_bufs[2], (GLenum)g_saved_draw_bufs[3],
                    GL_COLOR_ATTACHMENT4};
  glDrawBuffers(5, bufs);
  glDisablei(GL_BLEND, 4);
  glGetIntegerv(GL_CURRENT_PROGRAM, &g_saved_program);
  glUseProgram(program);
  g_active_program = program;
  GLint loc = uniform_loc(program);
  if (loc < 0) {
    ++g_uniform_missing;
    autoport_proof::publish("floor_probe_uniform_missing", g_uniform_missing);
  } else {
    glUniform1i(loc, 1);
  }
  g_draw_active = true;
#else
  (void)program;
  (void)frame_idx;
  (void)level_name;
#endif
}

void after_tfrag_draw() {
#ifndef __ANDROID__
  if (!autoport_proof::armed_for(kItem)) return;
  if (!g_draw_active) return;
  g_draw_active = false;
  GLenum bufs[4] = {(GLenum)g_saved_draw_bufs[0], (GLenum)g_saved_draw_bufs[1],
                    (GLenum)g_saved_draw_bufs[2], (GLenum)g_saved_draw_bufs[3]};
  glDrawBuffers(4, bufs);
  GLint loc = uniform_loc(g_active_program);
  if (loc >= 0) glUniform1i(loc, 0);
  glUseProgram(g_saved_program);
#endif
}

}  // namespace floor_probe
