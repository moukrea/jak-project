#include "ao_tie_alpha_probe.h"
#include "game/system/autoport_proof.h"
#include "third-party/glad/include/glad/glad.h"
#include <array>
#include <cmath>
#include <sstream>
#include <string>
#include <unordered_map>
#include <map>
#include <iomanip>

namespace ao_tie_alpha_probe {
namespace {
constexpr const char* kItem = "ao-prepass-tie-alpha";
AUTOPORT_FEATURE_SITE(kItem);
bool enabled = false, attached = false, pre = false, color_cleared = false;
int width = 0, height = 0;
unsigned populated_frames = 0;
uint64_t total_observed = 0, total_missing = 0;
std::unordered_map<std::string, uint64_t> total_causes;
GLuint targets[2] = {}, reader = 0;
GLint attached_fbo = 0;
std::vector<GLenum> buffers;
GLboolean blend1 = false, mask1[4] = {};
std::map<std::pair<uintptr_t, uint32_t>, uint32_t> ids;
struct Meta {
  float alpha = 0;
  GLint tex = 0, sampler = 0, samples = 0;
  std::array<GLint, 6> params{};
  std::array<GLfloat, 2> lod{};
  GLboolean depth = false, blend = false, coverage = false;
};
std::unordered_map<uint32_t, Meta> color_meta, pre_meta;
void unsupported(const char* why) {
  autoport_proof::publish_text("ao_tie_alpha_state", "unsupported");
  autoport_proof::publish_text("ao_tie_alpha_missing", why);
  enabled = false;
}
void restore() {
  if (!attached) return;
  GLint old;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &old);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, attached_fbo);
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, 0, 0);
  glDrawBuffers(buffers.size(), buffers.data());
  glColorMaski(1, mask1[0], mask1[1], mask1[2], mask1[3]);
  if (blend1) glEnablei(GL_BLEND, 1); else glDisablei(GL_BLEND, 1);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, old);
  attached = false;
}
void attach(bool is_pre) {
  if (!enabled || attached) return;
  GLint samples, fbo, kind, maxbuf;
  glGetIntegerv(GL_SAMPLES, &samples);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &fbo);
  if (samples != 0 || !fbo) { unsupported("msaa_or_default_fbo"); return; }
  if (!glDisablei || !glColorMaski || !glGetBooleani_v) {
    unsupported("indexed_state_unavailable"); return;
  }
  glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT1,
                                       GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &kind);
  if (kind != GL_NONE) { unsupported("attachment1_occupied"); return; }
  glGetIntegerv(GL_MAX_DRAW_BUFFERS, &maxbuf);
  if (maxbuf < 2) { unsupported("mrt_unavailable"); return; }
  buffers.resize(maxbuf);
  for (int i = 0; i < maxbuf; ++i) {
    GLint value; glGetIntegerv(GL_DRAW_BUFFER0 + i, &value); buffers[i] = value;
    if (i > 0 && value != GL_NONE) { unsupported("other_draw_buffers_active"); return; }
  }
  attached_fbo = fbo;
  blend1 = glIsEnabledi(GL_BLEND, 1);
  glGetBooleani_v(GL_COLOR_WRITEMASK, 1, mask1);
  attached = true; pre = is_pre;
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D,
                         targets[is_pre ? 0 : 1], 0);
  GLenum mrt[2] = {buffers[0], GL_COLOR_ATTACHMENT1};
  glDrawBuffers(2, mrt);
  if (glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    restore(); unsupported("rgba32f_fbo_incomplete"); return;
  }
  glColorMaski(1, GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  if (is_pre || !color_cleared) {
    GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
    glDisable(GL_SCISSOR_TEST);
    const float zero[4] = {}; glClearBufferfv(GL_COLOR, 1, zero);
    if (scissor) glEnable(GL_SCISSOR_TEST);
    if (!is_pre) color_cleared = true;
  }
}
Meta metadata(GLuint program, bool is_pre) {
  Meta m;
  GLint loc = glGetUniformLocation(program, is_pre ? "u_cut_aref" : "alpha_min");
  if (loc >= 0) glGetUniformfv(program, loc, &m.alpha);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &m.depth);
  m.blend = glIsEnabledi(GL_BLEND, 0);
  m.coverage = glIsEnabled(GL_SAMPLE_ALPHA_TO_COVERAGE);
  glGetIntegerv(GL_SAMPLES, &m.samples);
  GLint active_tex, unit = 0;
  loc = glGetUniformLocation(program, "tex_T0");
  if (loc >= 0) glGetUniformiv(program, loc, &unit);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &active_tex);
  glActiveTexture(GL_TEXTURE0 + unit);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &m.tex);
  glGetIntegerv(GL_SAMPLER_BINDING, &m.sampler);
  const GLenum names[] = {GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER, GL_TEXTURE_WRAP_S,
                          GL_TEXTURE_WRAP_T, GL_TEXTURE_BASE_LEVEL, GL_TEXTURE_MAX_LEVEL};
  if (m.tex) for (int i = 0; i < 6; ++i) {
    if (m.sampler && i < 4) glGetSamplerParameteriv(m.sampler, names[i], &m.params[i]);
    else glGetTexParameteriv(GL_TEXTURE_2D, names[i], &m.params[i]);
  }
  if (m.tex) for (int i = 0; i < 2; ++i) {
    GLenum name = i ? GL_TEXTURE_MAX_LOD : GL_TEXTURE_MIN_LOD;
    if (m.sampler) glGetSamplerParameterfv(m.sampler, name, &m.lod[i]);
    else glGetTexParameterfv(GL_TEXTURE_2D, name, &m.lod[i]);
  }
  glActiveTexture(active_tex);
  return m;
}
std::string describe(const Meta& m) {
  std::ostringstream o;
  o << std::setprecision(9) << "tex:" << m.tex << ",sampler:" << m.sampler << ",alpha:" << m.alpha
    << ",depthwrite:" << int(m.depth) << ",blend:" << int(m.blend)
    << ",coverage:" << int(m.coverage) << ",samples:" << m.samples << ",texparams:";
  for (auto v : m.params) o << v << ':';
  o << ",lod:" << m.lod[0] << ":" << m.lod[1];
  return o.str();
}
std::vector<float> read(GLuint texture) {
  GLint old, pack, align, row, skipx, skipy;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old);
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack);
  glGetIntegerv(GL_PACK_ALIGNMENT, &align); glGetIntegerv(GL_PACK_ROW_LENGTH, &row);
  glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipx); glGetIntegerv(GL_PACK_SKIP_ROWS, &skipy);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1); glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0); glPixelStorei(GL_PACK_SKIP_ROWS, 0);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, reader);
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  std::vector<float> result(size_t(width) * height * 4);
  const bool ready = glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  const GLenum prior_error = glGetError();
  if (ready && prior_error == GL_NO_ERROR)
    glReadPixels(0, 0, width, height, GL_RGBA, GL_FLOAT, result.data());
  const GLenum read_error = glGetError();
  if (!ready || prior_error != GL_NO_ERROR || read_error != GL_NO_ERROR) {
    result.clear(); unsupported("float_readback_failed_or_prior_gl_error");
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, old);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, pack);
  glPixelStorei(GL_PACK_ALIGNMENT, align); glPixelStorei(GL_PACK_ROW_LENGTH, row);
  glPixelStorei(GL_PACK_SKIP_PIXELS, skipx); glPixelStorei(GL_PACK_SKIP_ROWS, skipy);
  return result;
}
}  // namespace
bool active() { return enabled; }
uint32_t draw_id(const void* source_draws, uint32_t source_index) {
  const auto key = std::make_pair(reinterpret_cast<uintptr_t>(source_draws), source_index);
  auto it = ids.find(key);
  if (it != ids.end()) return it->second;
  const uint32_t id = uint32_t(ids.size() + 1);
  ids.emplace(key, id); return id;
}
void begin_frame(bool on, int w, int h) {
  restore();
  enabled = on && populated_frames < 4 && autoport_proof::feature_is(kItem) && autoport_proof::armed_for(kItem);
  color_cleared = false; color_meta.clear(); pre_meta.clear();
  if (!enabled) return;
  autoport_proof::publish_text("ao_tie_alpha_state", "collecting");
  autoport_proof::publish_text("ao_tie_alpha_missing", "cause_not_yet_observed");
  if (w <= 0 || h <= 0) { unsupported("invalid_dimensions"); return; }
  if (!reader) glGenFramebuffers(1, &reader);
  if (!targets[0] || w != width || h != height) {
    width = w; height = h;
    GLint old, unpack; glGetIntegerv(GL_TEXTURE_BINDING_2D, &old);
    glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpack);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    if (!targets[0]) glGenTextures(2, targets);
    for (auto t : targets) {
      glBindTexture(GL_TEXTURE_2D, t);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, w, h, 0, GL_RGBA, GL_FLOAT, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    glBindTexture(GL_TEXTURE_2D, old);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack);
  }
}
void pre_capture_begin(bool nocut) { if (nocut) attach(true); }
void pre_capture_end() { if (attached && pre) restore(); }
void color_begin() { attach(false); }
void color_end() { if (attached && !pre) restore(); }
void before_pre_draw(unsigned program, uint32_t id) {
  if (!enabled || !attached || !pre) return;
  glUniform1i(glGetUniformLocation(program, "u_tie_alpha_probe_id"), id);
  if (id) pre_meta[id] = metadata(program, true);
  glDisablei(GL_BLEND, 1);
}
void before_color_draw(unsigned program, uint32_t id) {
  if (!enabled || !attached || pre) return;
  glUniform1i(glGetUniformLocation(program, "u_tie_alpha_probe_id"), id);
  if (id) color_meta[id] = metadata(program, false);
  glDisablei(GL_BLEND, 1);
}
void finish_frame(const std::vector<float>& delivered_depth,
                  const std::vector<float>& scene_depth,
                  const std::vector<uint8_t>& resolved_rgba) {
  restore();
  if (!enabled) return;
  if (!color_cleared || pre_meta.empty() || delivered_depth.size() != size_t(width) * height ||
      scene_depth.size() != delivered_depth.size() || resolved_rgba.size() != delivered_depth.size() * 4) {
    unsupported("color_pre_or_delivered_depth_missing"); return;
  }
  const auto c = read(targets[1]), p = read(targets[0]);
  if (!enabled || c.empty() || p.empty()) return;
  uint64_t observed = 0, missing = 0, samples = 0;
  std::unordered_map<std::string, uint64_t> causes;
  for (const char* name : {"identity_or_depth_mismatch", "metadata_missing", "texture_state_difference",
                         "alpha_sampling_difference", "pre_alpha_passes_unknown", "alpha_rejection_other",
                         "color_depthwrite_off", "scene_depth_mismatch", "render_state_difference"})
    causes[name] = 0;
  for (size_t i = 0; i < delivered_depth.size(); ++i) {
    const size_t j = i * 4;
    if (resolved_rgba[j + 3] != 2) continue;
    if (!std::isfinite(c[j+3]) || !std::isfinite(p[j+3]) || c[j+3] < 0 || p[j+3] < 0 ||
        c[j+3] > ids.size() || p[j+3] > ids.size()) {
      unsupported("invalid_float_draw_identity"); return;
    }
    const uint32_t ci = uint32_t(c[j + 3]), pi = uint32_t(p[j + 3]);
    if (!ci) continue;
    ++observed;
    if (delivered_depth[i] > 1e-6f) continue;
    ++missing;
    std::string cause;
    const auto cm = color_meta.find(ci), pm = pre_meta.find(pi);
    if (cm != color_meta.end() && !cm->second.depth) cause = "color_depthwrite_off";
    else if (std::abs(c[j+2] - scene_depth[i]) > 64.f / 16777215.f) cause = "scene_depth_mismatch";
    else if (ci != pi || std::abs(c[j + 2] - p[j + 2]) > 64.f / 16777215.f)
      cause = "identity_or_depth_mismatch";
    else if (cm == color_meta.end() || pm == pre_meta.end()) cause = "metadata_missing";
    else if (p[j] >= p[j + 1]) cause = "pre_alpha_passes_unknown";
    else if (cm->second.tex != pm->second.tex || cm->second.sampler != pm->second.sampler ||
             cm->second.params != pm->second.params || cm->second.lod != pm->second.lod) cause = "texture_state_difference";
    else if (cm->second.coverage != pm->second.coverage ||
             cm->second.samples != pm->second.samples) cause = "render_state_difference";
    else if (c[j] != p[j]) cause = "alpha_sampling_difference";
    else cause = "alpha_rejection_other";
    ++causes[cause];
    if (samples < 32) {
      std::ostringstream row;
      row << std::setprecision(9) << "frame:" << populated_frames + 1 << ",xy:" << i % width << ':' << i / width << ",color_id:" << ci << ",pre_id:" << pi
          << ",color_raw:" << c[j] << ",color_test:" << c[j+1] << ",pre_raw:" << p[j]
          << ",pre_threshold:" << p[j+1] << ",color_z:" << c[j+2] << ",pre_z:" << p[j+2]
          << ",cause:" << cause;
      if (cm != color_meta.end()) row << ",color_state:" << describe(cm->second);
      if (pm != pre_meta.end()) row << ",pre_state_classification:" << describe(pm->second);
      const auto key = "ao_tie_alpha_sample_" + std::to_string(samples++);
      autoport_proof::publish_text(key.c_str(), row.str().c_str());
    }
  }
  if (observed) ++populated_frames;
  autoport_proof::note_hit_for(kItem, observed);
  total_observed += observed; total_missing += missing;
  autoport_proof::publish("ao_tie_alpha_frames", populated_frames);
  autoport_proof::publish("ao_tie_alpha_observed_px", total_observed);
  autoport_proof::publish("ao_tie_alpha_missing_px", total_missing);
  autoport_proof::publish("ao_tie_alpha_sample_rows", samples);
  for (const auto& kv : causes) {
    total_causes[kv.first] += kv.second;
    autoport_proof::publish(("ao_tie_alpha_" + kv.first + "_px").c_str(), total_causes[kv.first]);
  }
  autoport_proof::publish_text("ao_tie_alpha_state", "diagnostic_only");
  autoport_proof::publish_text("ao_tie_alpha_missing", samples >= 16 ? "correction_and_contract_checks_pending" : "fewer_than_16_missing_pixels");
  enabled = false;
}
}  // namespace ao_tie_alpha_probe
