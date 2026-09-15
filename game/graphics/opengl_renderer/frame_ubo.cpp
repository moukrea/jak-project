#include "frame_ubo.h"

#include <array>
#include <chrono>
#include <cstddef>
#include <cstring>
#include <set>

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/system/autoport_proof.h"
#include "game/graphics/opengl_renderer/ao_contact_archive.h"
#include "game/graphics/opengl_renderer/ao_static_probe.h"

// Definie dans background_common.cpp (liaison externe) : LA matrice que tfrag3.vert consomme
// sous le nom `pc_camera`. PrePass.cpp la declare de la meme facon.
std::array<math::Vector4f, 4> make_new_cam_mat(const math::Vector4f cam_T_w[4],
                                               const math::Vector4f persp[4],
                                               float fog_constant,
                                               float hvdf_z);

namespace frame_ubo {
namespace {

// Miroir OCTET POUR OCTET de `layout(std140) uniform ub_frame` (shaders/frame_ubo.glsl).
struct Data {
  float pc_camera[16];
  float camera[16];
  float hvdf_offset[4];
  float cam_trans[4];
  float fog_color[4];
  float fog_constant;
  float fog_min;
  float fog_max;
  float exposure;   // SPEC §4.5 : defaut 1,0 ; consommateur a venir (lighting-hdr)
  float screen[4];  // w, h, 1/w, 1/h du FBO de rendu
  float misc[4];    // temps (s, horloge stable), palier (0), 0, 0
};
static_assert(sizeof(Data) == 224, "ub_frame : le miroir C++ ne fait pas 224 octets std140");

GLuint g_ubo = 0;
Data g_last{};
bool g_valid = false;
uint64_t g_uploads_frame = 0, g_uploads_total = 0, g_frames = 0, g_bound_programs = 0;
double g_t0 = -1.0;

double now_s() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

}  // namespace

void update_and_bind(const GoalBackgroundCameraData& cam, const SharedRenderState* rs) {
  Data d{};
  const auto newcam = make_new_cam_mat(cam.rot, cam.perspective, cam.fog.x(), cam.hvdf_off.z());
  for (int i = 0; i < 4; i++) {
    std::memcpy(&d.pc_camera[i * 4], newcam[i].data(), 16);
    std::memcpy(&d.camera[i * 4], cam.camera[i].data(), 16);
  }
  std::memcpy(d.hvdf_offset, cam.hvdf_off.data(), 16);
  std::memcpy(d.cam_trans, cam.trans.data(), 16);
  d.fog_color[0] = rs->fog_color[0] / 255.f;
  d.fog_color[1] = rs->fog_color[1] / 255.f;
  d.fog_color[2] = rs->fog_color[2] / 255.f;
  d.fog_color[3] = rs->fog_intensity / 255;
  d.fog_constant = cam.fog.x();
  d.fog_min = cam.fog.y();
  d.fog_max = cam.fog.z();
  d.exposure = 1.0f;
  const float w = (float)rs->render_fb_w, h = (float)rs->render_fb_h;
  d.screen[0] = w;
  d.screen[1] = h;
  d.screen[2] = w > 0.f ? 1.f / w : 0.f;
  d.screen[3] = h > 0.f ? 1.f / h : 0.f;
  // Le temps n'entre PAS dans la comparaison : il changerait a chaque appel et forcerait un
  // televersement par draw. Il est rafraichi avec le reste, au premier changement de l'image.
  if (g_t0 < 0.0) {
    g_t0 = now_s();
  }
  if (!g_ubo) {
    glGenBuffers(1, &g_ubo);
    glBindBuffer(GL_UNIFORM_BUFFER, g_ubo);
    glBufferData(GL_UNIFORM_BUFFER, sizeof(Data), nullptr, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
  }
  const bool same = g_valid && std::memcmp(&d, &g_last, offsetof(Data, misc)) == 0;
  if (!same) {
    d.misc[0] = (float)(now_s() - g_t0);
    g_last = d;
    g_valid = true;
    glBindBuffer(GL_UNIFORM_BUFFER, g_ubo);
    glBufferSubData(GL_UNIFORM_BUFFER, 0, sizeof(Data), &g_last);
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
    g_uploads_frame++;
  }
  glBindBufferBase(GL_UNIFORM_BUFFER, kBindingPoint, g_ubo);
  if (ao_contact_archive::requested() && ao_static_probe::logic_frame() == 1400) {
    // Archive the exact bytes just bound, including cached misc, not a recomputed camera.
    static std::set<std::pair<uint64_t, uint64_t>> seen;
    static uint64_t errors = 0;
    const uint64_t hash = ao_contact_archive::hash(&g_last, sizeof(g_last));
    const auto identity = std::make_pair(uint64_t(rs->frame_idx), hash);
    if (!seen.count(identity) && seen.size() >= 64) {
      autoport_proof::publish("ao_hut_frame_ubo_overflow", 1);
    } else if (seen.insert(identity).second) {
      const auto& dir = ao_contact_archive::directory();
      const bool ok = !dir.empty() && ao_contact_archive::write_exclusive(
          dir + "/frame-ubo-" + std::to_string(rs->frame_idx) + "-" + std::to_string(hash) + ".bin",
          &g_last, sizeof(g_last));
      errors += !ok;
      autoport_proof::publish("ao_hut_frame_ubo_write_error", errors);
      autoport_proof::publish("ao_hut_frame_ubo_count", seen.size());
    }
  }
}

uint64_t contact_bound_hash() {
  GLint bound = 0;
  glGetIntegeri_v(GL_UNIFORM_BUFFER_BINDING, kBindingPoint, &bound);
  return g_valid && GLuint(bound) == g_ubo ? ao_contact_archive::hash(&g_last, sizeof(g_last)) : 0;
}

void bind_program(GLuint program) {
  const GLint idx = glGetUniformBlockIndex(program, "ub_frame");
  if (idx != -1) {
    glUniformBlockBinding(program, (GLuint)idx, kBindingPoint);
    g_bound_programs++;
  }
}

void frame_begin() {
  if (g_frames > 0) {
    g_uploads_total += g_uploads_frame;
    autoport_proof::publish("frame_ubo_uploads_per_frame", g_uploads_frame);
    autoport_proof::publish("frame_ubo_uploads_total", g_uploads_total);
    autoport_proof::publish("frame_ubo_frames", g_frames);
    autoport_proof::publish("frame_ubo_bound_programs", g_bound_programs);
  }
  g_frames++;
  g_uploads_frame = 0;
}

}  // namespace frame_ubo
