#include "SkyCapture.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

#include "game/system/autoport_proof.h"

#include "third-party/glad/include/glad/glad.h"

namespace sky_capture {
namespace {

constexpr int kW = 64;     // vignette du ciel
constexpr int kH = 32;
constexpr int kRows = 8;   // elevations, de -90 a +90 degres
constexpr int kCols = 16;  // azimuts
constexpr int kEvery = 4;  // une capture toutes les quatre images : le ciel change lentement
constexpr float kPi = 3.14159265358979f;

struct Bin {
  float rgb[3] = {0.f, 0.f, 0.f};
  bool seen = false;
};

struct State {
  bool init = false;
  bool ok = false;
  bool is_float = false;
  GLuint small_fbo = 0, small_tex = 0;
  GLuint resolve_fbo = 0, resolve_tex = 0;
  int resolve_w = 0, resolve_h = 0;
  GLuint pbo = 0;
  GLsync fence = nullptr;
  bool pending = false;       // une lecture est en vol
  bool pending_cam = false;   // sa camera a ete relevee
  float cam[4][4] = {};       // `pc_camera` de l'image capturee, en colonnes
  u64 issued_frame = 0;
  Bin bins[kRows][kCols];
  int seen = 0;
  u64 captures = 0;           // lectures moissonnees et versees dans la grille
  u64 skipped_busy = 0;       // lectures encore en vol a l'echeance (jamais d'attente)
} g;

void ensure(const SharedRenderState* rs) {
  const bool want_float = rs->render_fb_color_format != GL_RGBA8;
  if (g.init && g.is_float == want_float) {
    return;
  }
  if (g.init) {
    glDeleteFramebuffers(1, &g.small_fbo);
    glDeleteTextures(1, &g.small_tex);
    glDeleteBuffers(1, &g.pbo);
    g.pending = false;
  }
  g.init = true;
  g.is_float = want_float;
  glGenTextures(1, &g.small_tex);
  glBindTexture(GL_TEXTURE_2D, g.small_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, want_float ? GL_RGBA16F : GL_RGBA8, kW, kH, 0, GL_RGBA,
               want_float ? GL_FLOAT : GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glBindTexture(GL_TEXTURE_2D, 0);
  glGenFramebuffers(1, &g.small_fbo);
  GLint prev_draw = 0;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g.small_fbo);
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g.small_tex, 0);
  g.ok = glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)prev_draw);
  glGenBuffers(1, &g.pbo);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, g.pbo);
  glBufferData(GL_PIXEL_PACK_BUFFER, kW * kH * (want_float ? 16 : 4), nullptr, GL_STREAM_READ);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  autoport_proof::publish("sky_capture_fbo_ok", g.ok ? 1 : 0);
}

// Tampon simple de la taille de la scene : un framebuffer multi-echantillonne ne se reduit pas
// d'un seul blit (GL exige alors des rectangles de meme taille).
bool ensure_resolve(int w, int h) {
  if (g.resolve_fbo && g.resolve_w == w && g.resolve_h == h) {
    return true;
  }
  if (g.resolve_fbo) {
    glDeleteFramebuffers(1, &g.resolve_fbo);
    glDeleteTextures(1, &g.resolve_tex);
  }
  glGenTextures(1, &g.resolve_tex);
  glBindTexture(GL_TEXTURE_2D, g.resolve_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, g.is_float ? GL_RGBA16F : GL_RGBA8, w, h, 0, GL_RGBA,
               g.is_float ? GL_FLOAT : GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glBindTexture(GL_TEXTURE_2D, 0);
  glGenFramebuffers(1, &g.resolve_fbo);
  GLint prev_draw = 0;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g.resolve_fbo);
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g.resolve_tex,
                         0);
  const bool ok = glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)prev_draw);
  g.resolve_w = w;
  g.resolve_h = h;
  return ok;
}

void bin_dir(int r, int c, float d[3]) {
  const float el = (-90.f + (r + 0.5f) * (180.f / kRows)) * (kPi / 180.f);
  const float az = ((c + 0.5f) * (360.f / kCols)) * (kPi / 180.f);
  d[0] = std::cos(el) * std::cos(az);
  d[1] = std::sin(el);
  d[2] = std::cos(el) * std::sin(az);
}

// Verse la vignette lue dans la grille, avec la camera de l'image ou elle a ete prise.
void harvest(const void* px) {
  const float sy = 512.f / 448.f;
  int front = 0, in_view = 0;
  for (int r = 0; r < kRows; r++) {
    for (int c = 0; c < kCols; c++) {
      float d[3];
      bin_dir(r, c, d);
      float clip[4];
      for (int k = 0; k < 4; k++) {
        clip[k] = -(g.cam[0][k] * d[0] + g.cam[1][k] * d[1] + g.cam[2][k] * d[2]);
      }
      if (clip[3] <= 1e-4f) {
        continue;  // derriere la camera
      }
      front++;
      const float nx = clip[0] / clip[3];
      const float ny = clip[1] * sy / clip[3];
      if (std::fabs(nx) > 0.95f || std::fabs(ny) > 0.95f) {
        continue;
      }
      in_view++;
      const int x = std::min(kW - 1, std::max(0, (int)((nx * 0.5f + 0.5f) * kW)));
      const int y = std::min(kH - 1, std::max(0, (int)((ny * 0.5f + 0.5f) * kH)));
      float s[3];
      if (g.is_float) {
        const float* p = (const float*)px + (y * kW + x) * 4;
        s[0] = p[0];
        s[1] = p[1];
        s[2] = p[2];
      } else {
        const u8* p = (const u8*)px + (y * kW + x) * 4;
        s[0] = p[0] / 255.f;
        s[1] = p[1] / 255.f;
        s[2] = p[2] / 255.f;
      }
      if (!(std::isfinite(s[0]) && std::isfinite(s[1]) && std::isfinite(s[2]))) {
        continue;
      }
      Bin& b = g.bins[r][c];
      if (!b.seen) {
        memcpy(b.rgb, s, sizeof(s));
        b.seen = true;
        g.seen++;
      } else {
        for (int k = 0; k < 3; k++) {
          b.rgb[k] += 0.35f * (s[k] - b.rgb[k]);
        }
      }
    }
  }
  g.captures++;
  autoport_proof::publish("sky_capture_frames", g.captures);
  // Diagnostic de la projection : cases devant la camera / dans le champ a la derniere capture,
  // et la matrice relevee (colonnes, x1000) — une projection fausse se lit ici, pas a l'ecran.
  autoport_proof::publish("sky_capture_last_front", (u64)front);
  autoport_proof::publish("sky_capture_last_in_view", (u64)in_view);
  if (g.captures % 64 == 1) {
    char buf[512];
    int n = 0;
    for (int c = 0; c < 4 && n < (int)sizeof(buf) - 64; c++) {
      n += snprintf(buf + n, sizeof(buf) - n, "%sc%d:%d,%d,%d,%d", c ? "/" : "", c,
                    (int)std::lround(g.cam[c][0] * 1000.f), (int)std::lround(g.cam[c][1] * 1000.f),
                    (int)std::lround(g.cam[c][2] * 1000.f), (int)std::lround(g.cam[c][3] * 1000.f));
    }
    autoport_proof::publish_text("sky_capture_cam", buf);
  }
  autoport_proof::publish("sky_capture_bins_seen", (u64)g.seen);
}

void try_harvest() {
  if (!g.pending || !g.pending_cam) {
    return;
  }
  const GLenum st = glClientWaitSync(g.fence, 0, 0);
  if (st != GL_ALREADY_SIGNALED && st != GL_CONDITION_SATISFIED) {
    g.skipped_busy++;
    autoport_proof::publish("sky_capture_skipped_busy", g.skipped_busy);
    return;
  }
  glDeleteSync(g.fence);
  g.fence = nullptr;
  g.pending = false;
  glBindBuffer(GL_PIXEL_PACK_BUFFER, g.pbo);
  const void* px =
      glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, kW * kH * (g.is_float ? 16 : 4), GL_MAP_READ_BIT);
  if (px) {
    harvest(px);
    glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
  }
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
}

void issue(const SharedRenderState* rs) {
  GLint prev_read = 0, prev_draw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
  const GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
  glDisable(GL_SCISSOR_TEST);
  const int w = rs->render_fb_w, h = rs->render_fb_h;
  glBindFramebuffer(GL_READ_FRAMEBUFFER, rs->render_fb);
  GLint samples = 0;
  glGetIntegerv(GL_SAMPLES, &samples);
  bool ok = true;
  if (samples > 1) {
    ok = ensure_resolve(w, h);
    if (ok) {
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g.resolve_fbo);
      glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
      glBindFramebuffer(GL_READ_FRAMEBUFFER, g.resolve_fbo);
    }
  }
  if (ok) {
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g.small_fbo);
    glBlitFramebuffer(0, 0, w, h, 0, 0, kW, kH, GL_COLOR_BUFFER_BIT, GL_LINEAR);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, g.small_fbo);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, g.pbo);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(0, 0, kW, kH, GL_RGBA, g.is_float ? GL_FLOAT : GL_UNSIGNED_BYTE, nullptr);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    g.fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    g.pending = true;
    g.pending_cam = false;
    g.issued_frame = rs->frame_idx;
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)prev_draw);
  if (scissor) {
    glEnable(GL_SCISSOR_TEST);
  }
}

}  // namespace

void after_bucket(SharedRenderState* rs, bool sky_bucket, bool enabled) {
  if (!enabled) {
    return;
  }
  if (sky_bucket) {
    if (rs->frame_idx % kEvery != 0) {
      return;
    }
    ensure(rs);
    if (!g.ok) {
      return;
    }
    try_harvest();
    if (!g.pending && rs->render_fb_w > 0 && rs->render_fb_h > 0) {
      issue(rs);
    }
    return;
  }
}

void note_pc_camera(const float m[16], u64 frame_idx) {
  if (g.pending && !g.pending_cam && frame_idx == g.issued_frame) {
    for (int c = 0; c < 4; c++) {
      for (int k = 0; k < 4; k++) {
        g.cam[c][k] = m[c * 4 + k];
      }
    }
    g.pending_cam = true;
  }
}

bool sh(float out[9][3]) {
  if (g.seen == 0) {
    return false;
  }
  // Cases jamais vues : la moyenne de leur rangee, sinon celle de la rangee vue la plus proche.
  float row_mean[kRows][3];
  bool row_ok[kRows];
  for (int r = 0; r < kRows; r++) {
    int n = 0;
    float s[3] = {0.f, 0.f, 0.f};
    for (int c = 0; c < kCols; c++) {
      if (g.bins[r][c].seen) {
        n++;
        for (int k = 0; k < 3; k++) s[k] += g.bins[r][c].rgb[k];
      }
    }
    row_ok[r] = n > 0;
    for (int k = 0; k < 3; k++) row_mean[r][k] = n ? s[k] / n : 0.f;
  }
  for (int i = 0; i < 9; i++) {
    out[i][0] = out[i][1] = out[i][2] = 0.f;
  }
  const float daz = 2.f * kPi / kCols;
  for (int r = 0; r < kRows; r++) {
    int rr = r;
    for (int dd = 1; !row_ok[rr] && dd < kRows; dd++) {
      if (r - dd >= 0 && row_ok[r - dd]) {
        rr = r - dd;
      } else if (r + dd < kRows && row_ok[r + dd]) {
        rr = r + dd;
      }
    }
    const float e0 = (-90.f + r * (180.f / kRows)) * (kPi / 180.f);
    const float e1 = (-90.f + (r + 1) * (180.f / kRows)) * (kPi / 180.f);
    const float w = (std::sin(e1) - std::sin(e0)) * daz;  // angle solide de la case
    for (int c = 0; c < kCols; c++) {
      const float* L = g.bins[r][c].seen ? g.bins[r][c].rgb : row_mean[rr];
      float d[3];
      bin_dir(r, c, d);
      const float x = d[0], y = d[1], z = d[2];
      const float Y[9] = {0.282095f,
                          0.488603f * y,
                          0.488603f * z,
                          0.488603f * x,
                          1.092548f * x * y,
                          1.092548f * y * z,
                          0.315392f * (3.f * z * z - 1.f),
                          1.092548f * x * z,
                          0.546274f * (x * x - y * y)};
      for (int i = 0; i < 9; i++) {
        for (int k = 0; k < 3; k++) {
          out[i][k] += L[k] * Y[i] * w;
        }
      }
    }
  }
  const float Al[9] = {1.f, 2.f / 3.f, 2.f / 3.f, 2.f / 3.f, 0.25f, 0.25f, 0.25f, 0.25f, 0.25f};
  for (int i = 0; i < 9; i++) {
    for (int k = 0; k < 3; k++) {
      out[i][k] *= Al[i];
    }
  }
  return true;
}

int bins_seen() {
  return g.seen;
}

}  // namespace sky_capture
