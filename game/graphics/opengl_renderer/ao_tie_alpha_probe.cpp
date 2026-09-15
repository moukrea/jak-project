#include "ao_tie_alpha_probe.h"
#include "ao_static_probe.h"
#include "ao_contact_archive.h"
#include "ao_contact_readback.h"
#include <set>
#include <cstring>
#include <cstdlib>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
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
bool color_done = false;
uint64_t color_bindings = 0, color_binding_bad = 0;
uint64_t shader_hosts = 0, shader_replacements = 0, shader_match_bad = 0;
unsigned shader_host_mask = 0;
bool enabled = false, attached = false, pre = false, color_cleared = false;
int width = 0, height = 0;
unsigned populated_frames = 0;
uint64_t total_observed = 0, total_missing = 0, total_pre_judged = 0;
std::unordered_map<std::string, uint64_t> total_causes;
GLuint targets[2] = {}, reader = 0;
GLuint hut_targets[2] = {};
bool hut_frame = false, hut_attempted = false;
GLboolean hut_blend[2] = {}, hut_masks[2][4] = {};
std::set<GLuint> hut_programs;
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
  if (hut_frame && !pre) {
    GLint program; glGetIntegerv(GL_CURRENT_PROGRAM, &program);
    for (GLuint p : hut_programs) {
      glUseProgram(p); glUniform1i(glGetUniformLocation(p, "u_hut_capture"), 0);
    }
    glUseProgram(program);
    hut_programs.clear();
    for (int i = 0; i < 2; ++i) {
      glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT2 + i, GL_TEXTURE_2D, 0, 0);
      glColorMaski(i + 2, hut_masks[i][0], hut_masks[i][1], hut_masks[i][2], hut_masks[i][3]);
      if (hut_blend[i]) glEnablei(GL_BLEND, i + 2); else glDisablei(GL_BLEND, i + 2);
    }
  }
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
  if (maxbuf < (hut_frame && !is_pre ? 4 : 2)) { unsupported("mrt_unavailable"); return; }
  buffers.resize(maxbuf);
  for (int i = 0; i < maxbuf; ++i) {
    GLint value; glGetIntegerv(GL_DRAW_BUFFER0 + i, &value); buffers[i] = value;
    if (i > 0 && value != GL_NONE) { unsupported("other_draw_buffers_active"); return; }
  }
  if (hut_frame && !is_pre) {
    for (int i = 0; i < 2; ++i) {
      glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT2 + i,
                                           GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &kind);
      if (kind != GL_NONE) { unsupported("hut_attachment_occupied"); return; }
      hut_blend[i] = glIsEnabledi(GL_BLEND, i + 2);
      glGetBooleani_v(GL_COLOR_WRITEMASK, i + 2, hut_masks[i]);
    }
  }
  attached_fbo = fbo;
  blend1 = glIsEnabledi(GL_BLEND, 1);
  glGetBooleani_v(GL_COLOR_WRITEMASK, 1, mask1);
  attached = true; pre = is_pre;
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D,
                         targets[is_pre ? 0 : 1], 0);
  GLenum mrt[4] = {buffers[0], GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2, GL_COLOR_ATTACHMENT3};
  if (hut_frame && !is_pre) for (int i = 0; i < 2; ++i) {
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT2 + i, GL_TEXTURE_2D, hut_targets[i], 0);
    glColorMaski(i + 2, GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glDisablei(GL_BLEND, i + 2);
  }
  glDrawBuffers(hut_frame && !is_pre ? 4 : 2, mrt);
  if (glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    restore(); unsupported("rgba32f_fbo_incomplete"); return;
  }
  glColorMaski(1, GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  if (is_pre || !color_cleared) {
    GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
    glDisable(GL_SCISSOR_TEST);
    const float zero[4] = {}; glClearBufferfv(GL_COLOR, 1, zero);
    if (hut_frame && !is_pre) {
      glClearBufferfv(GL_COLOR, 2, zero); glClearBufferfv(GL_COLOR, 3, zero);
    }
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
  hut_frame = !hut_attempted && ao_contact_archive::requested() && ao_static_probe::logic_frame() == 1400;
  if (hut_frame) hut_attempted = true;
  enabled = hut_frame || color_frame() || (on && populated_frames < 4 && autoport_proof::feature_is(kItem) && autoport_proof::armed_for(kItem));
  color_cleared = false; color_meta.clear(); pre_meta.clear();
  if (!enabled) return;
  if (!color_frame() && !hut_frame) {
    autoport_proof::publish_text("ao_tie_alpha_state", "collecting");
    autoport_proof::publish_text("ao_tie_alpha_missing", "cause_not_yet_observed");
  }
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
  if (hut_frame) {
    ao_contact_readback::ExportState state;
    if (!state.errors.empty()) { unsupported("hut_init_prior_error"); return; }
    if (!hut_targets[0]) glGenTextures(2, hut_targets);
    for (GLuint target : hut_targets) {
      glBindTexture(GL_TEXTURE_2D, target);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, w, h, 0, GL_RGBA, GL_FLOAT, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    state.collect("hut-target-init");
    if (!state.restore()) unsupported("hut_target_init_or_restore_error");
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
  if (hut_frame) {
    glUniform1i(glGetUniformLocation(program, "u_hut_capture"), 1);
    hut_programs.insert(program);
    glDisablei(GL_BLEND, 2); glDisablei(GL_BLEND, 3);
  }
  glDisablei(GL_BLEND, 1);
}
void finish_frame(const std::vector<float>& delivered_depth,
                  const std::vector<float>& scene_depth,
                  const std::vector<uint8_t>& resolved_rgba) {
  restore();
  if (!enabled || hut_frame) return;
  if (!color_cleared || pre_meta.empty() || delivered_depth.size() != size_t(width) * height ||
      scene_depth.size() != delivered_depth.size() || resolved_rgba.size() != delivered_depth.size() * 4) {
    unsupported("color_pre_or_delivered_depth_missing"); return;
  }
  const auto c = read(targets[1]), p = read(targets[0]);
  if (!enabled || c.empty() || p.empty()) return;
  uint64_t observed = 0, missing = 0, samples = 0, pre_judged = 0;
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
    // Count the prepass alpha judgments with a matching static TIE color draw.
    // Envmap and wind families, and color draws missing from the prepass, are excluded.
    if (pi && pi == ci && pre_meta.count(pi)) ++pre_judged;
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
  autoport_proof::note_hit_for(kItem, pre_judged);
  total_pre_judged += pre_judged;
  total_observed += observed; total_missing += missing;
  autoport_proof::publish("ao_tie_alpha_frames", populated_frames);
  autoport_proof::publish("ao_tie_alpha_observed_px", total_observed);
  autoport_proof::publish("ao_tie_alpha_pre_judged_px", total_pre_judged);
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
void finish_hut(uint64_t render_frame) {
  if (!hut_frame) return;
  restore();
  bool ok = enabled && color_cleared && !color_meta.empty();
  std::ostringstream meta;
  meta << "format=ao-hut-color-f32-v2\nlogic_frame=1400\nrender_frame=" << render_frame
       << "\nwidth=" << width << "\nheight=" << height
       << "\norigin=lower-left\nalpha=post-discard\nidentity_r=primitive-id-plus-one\nidentity_g=tested-alpha\nidentity_b=window-depth\nidentity_a=draw-id\ncolor=before-fog-and-framebuffer-blend\n";
  const GLuint textures[] = {targets[1], hut_targets[0], hut_targets[1]};
  const char* names[] = {"color-identity.rgba32f", "color-contribution.rgba32f", "color-normal.rgba32f"};
  for (int i = 0; i < 3 && ok; ++i) {
    const auto data = read(textures[i]);
    const size_t bytes = data.size() * sizeof(float);
    ok = enabled && data.size() == size_t(width) * height * 4 &&
      ao_contact_archive::write_exclusive(ao_contact_archive::directory() + "/" + names[i], data.data(), bytes);
    if (ok) meta << "stage=" << names[i] << " bytes=" << bytes << " fnv1a64="
                 << ao_contact_archive::hash(data.data(), bytes) << '\n';
  }
  for (const auto& entry : color_meta) meta << "draw_id=" << entry.first << " state=" << describe(entry.second) << '\n';
  meta << "status=" << (ok ? "complete" : "failed") << '\n';
  const auto data = meta.str();
  ok = ao_contact_archive::write_exclusive(ao_contact_archive::directory() + "/color.meta", data.data(), data.size()) && ok;
  autoport_proof::publish_text("ao_hut_color_status", ok ? "complete" : "failed");
  autoport_proof::publish("ao_hut_color_draws", color_meta.size());
}
}  // namespace ao_tie_alpha_probe

namespace ao_tie_alpha_probe {
namespace {
std::string color_property(const char* suffix, const char* env) {
#ifdef __ANDROID__
  char value[PROP_VALUE_MAX] = {};
  __system_property_get((std::string("debug.opengoal.ao.tie.") + suffix).c_str(), value);
  return value;
#else
  const char* value = std::getenv(env);
  return value ? value : "";
#endif
}
std::string campaign() { return color_property("campaign", "OG_AO_TIE_CAMPAIGN"); }
std::string view() { return color_property("view", "OG_AO_TIE_VIEW"); }
bool reference() { return color_property("reference", "OG_AO_TIE_REFERENCE") == "1"; }
uint64_t bytes_hash(const void* ptr, size_t n) {
  uint64_t hash = 1469598103934665603ull;
  const auto* bytes = static_cast<const uint8_t*>(ptr);
  for (size_t i = 0; i < n; ++i) { hash ^= bytes[i]; hash *= 1099511628211ull; }
  return hash;
}
void color_missing(const char* reason) {
  autoport_proof::publish("ao_tie_color_measured", 0);
  autoport_proof::publish("ao_tie_color_missing_fields", 1);
  autoport_proof::publish_text("ao_tie_color_missing", reason);
}
}
bool color_frame() {
  return !color_done && autoport_proof::feature_is(kItem) && !campaign().empty() &&
         !view().empty() && ao_static_probe::logic_frame() == 1400;
}
void note_color_binding(bool ao_off, bool proof_off) {
  if (!color_frame()) return;
  ++color_bindings;
  color_binding_bad += !ao_off || !proof_off;
}
void shader_variant(const std::string& name, std::string& source) {
  if (!autoport_proof::feature_is(kItem) || campaign().empty()) return;
  const std::string corrected = "return vec4(leak > 2e-4 ? 1.0 : 0.0, hit, excl, c.a);";
  const size_t pos = source.find(corrected);
  if (pos == std::string::npos) return;
  const bool unique = source.find(corrected, pos + corrected.size()) == std::string::npos;
  const bool legacy = reference();
  const uint64_t before = bytes_hash(source.data(), source.size());
  if (legacy && unique)
    source.replace(pos, corrected.size(), "return vec4(leak > 2e-4 ? 1.0 : 0.0, hit, excl, 1.0);");
  if (name == "tfrag3") shader_host_mask |= 1;
  if (name == "shrub") shader_host_mask |= 2;
  if (name == "tie_wind") shader_host_mask |= 4;
  if (name == "etie_base") shader_host_mask |= 8;
  ++shader_hosts;
  shader_replacements += legacy && unique;
  shader_match_bad += !unique;
  const std::string key = "ao_tie_shader_" + name;
  autoport_proof::publish((key + "_corrected_hash").c_str(), before);
  autoport_proof::publish((key + "_effective_hash").c_str(), bytes_hash(source.data(), source.size()));
  autoport_proof::publish((key + "_replacements").c_str(), legacy && unique ? 1 : 0);
  autoport_proof::publish((key + "_match_defects").c_str(), unique ? 0 : 1);
  autoport_proof::publish_text((key + "_variant").c_str(), legacy ? "legacy-alpha-one" : "corrected-alpha");
}
void finish_color(unsigned framebuffer, unsigned format, const std::vector<float>& scene_depth) {
  if (!color_frame()) return;
  color_done = true;
  restore();
  color_missing("readback_pending");
  autoport_proof::publish("ao_tie_color_bindings", color_bindings);
  autoport_proof::publish("ao_tie_color_binding_bad", color_binding_bad);
  autoport_proof::publish("ao_tie_color_shader_hosts", shader_hosts);
  autoport_proof::publish("ao_tie_color_shader_replacements", shader_replacements);
  if (!color_bindings || color_binding_bad || shader_host_mask != 15 || shader_match_bad ||
      (reference() ? shader_replacements != shader_hosts : shader_replacements != 0)) {
    color_missing("color_bindings_or_shader_variant_missing"); return;
  }
  const size_t pixels = size_t(width) * height;
  autoport_proof::publish("ao_tie_color_tick", ao_static_probe::logic_frame());
  autoport_proof::publish("ao_tie_color_width", width);
  autoport_proof::publish("ao_tie_color_height", height);
  autoport_proof::publish("ao_tie_color_format", format);
  autoport_proof::publish_text("ao_tie_color_population", "final-visible-static-TIE-pixels-depth24-exact-not-overdraw");
  if (!pixels || !framebuffer || (format != GL_RGBA8 && format != GL_RGBA16F)) {
    color_missing("unsupported_color_framebuffer_or_format"); return;
  }
  // GL exposes no operation to restore its error queue. Record prior errors as a failed
  // measurement, and never treat their removal by glGetError as a successful readback.
  if (glGetError() != GL_NO_ERROR) { color_missing("prior_gl_error"); return; }
  GLint old, old_buffer, pack, align, row, skipx, skipy;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old);
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack);
  glGetIntegerv(GL_PACK_ALIGNMENT, &align); glGetIntegerv(GL_PACK_ROW_LENGTH, &row);
  glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipx); glGetIntegerv(GL_PACK_SKIP_ROWS, &skipy);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
  glGetIntegerv(GL_READ_BUFFER, &old_buffer);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1); glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0); glPixelStorei(GL_PACK_SKIP_ROWS, 0);
  const size_t stride = format == GL_RGBA8 ? 4 : 4 * sizeof(float);
  std::vector<uint8_t> rgba(pixels * stride);
  glReadPixels(0, 0, width, height, GL_RGBA,
               format == GL_RGBA8 ? GL_UNSIGNED_BYTE : GL_FLOAT, rgba.data());
  const GLenum error = glGetError();
  glReadBuffer(old_buffer); glBindFramebuffer(GL_READ_FRAMEBUFFER, old);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, pack);
  glPixelStorei(GL_PACK_ALIGNMENT, align); glPixelStorei(GL_PACK_ROW_LENGTH, row);
  glPixelStorei(GL_PACK_SKIP_PIXELS, skipx); glPixelStorei(GL_PACK_SKIP_ROWS, skipy);
  if (error != GL_NO_ERROR) { color_missing("native_color_readback_failed"); return; }
  autoport_proof::publish("ao_tie_color_pixels", pixels);
  autoport_proof::publish("ao_tie_color_image_hash", bytes_hash(rgba.data(), rgba.size()));
  bool tie_valid = enabled && color_cleared && scene_depth.size() == pixels;
  auto metadata_pixels = tie_valid ? read(targets[1]) : std::vector<float>{};
  tie_valid = tie_valid && metadata_pixels.size() == pixels * 4;
  std::vector<uint8_t> mask(pixels);
  uint64_t tie_pixels = 0;
  if (tie_valid) for (size_t i = 0; i < pixels; ++i) {
    const float id = metadata_pixels[4*i+3], z = metadata_pixels[4*i+2];
    if (!std::isfinite(id) || id < 0 || id > ids.size() || id != std::floor(id) ||
        !std::isfinite(z) || !std::isfinite(scene_depth[i])) { tie_valid = false; break; }
    // Both values use the same export_depth quantization, with no epsilon window.
    const float encoded = std::floor(z * 16777215.f + 0.5f) * (1.f / 16777215.f);
    if (id != 0 && encoded == scene_depth[i]) {
      auto meta = color_meta.find(uint32_t(id));
      if (meta == color_meta.end() || !meta->second.depth) { tie_valid = false; break; }
      mask[i] = 1; ++tie_pixels;
    }
  }
  autoport_proof::publish("ao_tie_color_tie_pixels", tie_pixels);
  uint64_t binary = 0;
#ifdef __ANDROID__
  Dl_info info{};
  if (dladdr(reinterpret_cast<const void*>(&finish_color), &info) && info.dli_fname)
    binary = refset_file::hash_file(info.dli_fname);
#elif defined(__linux__)
  binary = refset_file::hash_file("/proc/self/exe");
#endif
  autoport_proof::publish("ao_tie_color_binary", binary);
  const std::string identity = "AO_TIE_COLOR_V1 " + campaign() + " " + view() + " " +
      std::to_string(binary) + " 1400 " + std::to_string(width) + " " +
      std::to_string(height) + " " + std::to_string(format) + "\n";
  const auto path = (file_util::get_user_home_dir() /
      ("ao-tie-color-" + std::to_string(bytes_hash(identity.data(), identity.size())) + ".bin")).string();
  autoport_proof::publish_text("ao_tie_color_baseline_path", path.c_str());
  if (!binary) { color_missing("binary_identity_unavailable"); return; }
  if (reference()) {
    if (!tie_valid || !tie_pixels) { color_missing("reference_tie_population_missing"); return; }
    const std::string temporary = path + ".tmp-" + std::to_string(getpid());
    FILE* f = std::fopen(temporary.c_str(), "wbx");
    bool ok = f && std::fwrite(identity.data(), 1, identity.size(), f) == identity.size() &&
        std::fwrite(rgba.data(), 1, rgba.size(), f) == rgba.size() &&
        std::fwrite(mask.data(), 1, mask.size(), f) == mask.size();
    if (f && (std::fflush(f) || fsync(fileno(f)))) ok = false;
    if (f && std::fclose(f)) ok = false;
    if (ok && std::rename(temporary.c_str(), path.c_str())) ok = false;
    if (!ok) std::remove(temporary.c_str());
    autoport_proof::publish("ao_tie_color_reference_saved", ok ? 1 : 0);
    color_missing(ok ? "reference_only_comparison_pending" : "reference_write_failed");
    return;
  }
  FILE* f = std::fopen(path.c_str(), "rb");
  std::string header(identity.size(), '\0');
  std::vector<uint8_t> previous(rgba.size()), previous_mask(mask.size());
  bool ok = f && std::fread(header.data(), 1, header.size(), f) == header.size() &&
      header == identity && std::fread(previous.data(), 1, previous.size(), f) == previous.size() &&
      std::fread(previous_mask.data(), 1, previous_mask.size(), f) == previous_mask.size() &&
      std::fgetc(f) == EOF && !std::ferror(f);
  if (f && std::fclose(f)) ok = false;
  if (!ok) { color_missing("reference_absent_truncated_or_identity_mismatch"); return; }
  uint64_t changed = 0, tie_changed = 0, previous_tie = 0;
  for (size_t i = 0; i < pixels; ++i) {
    const bool diff = std::memcmp(rgba.data()+i*stride, previous.data()+i*stride, stride) != 0;
    changed += diff;
    previous_tie += previous_mask[i] == 1;
    if (previous_mask[i] > 1) tie_valid = false;
    if ((mask[i] || previous_mask[i]) && (diff || mask[i] != previous_mask[i])) ++tie_changed;
  }
  autoport_proof::publish("ao_tie_color_changed_px", changed);
  autoport_proof::publish("ao_tie_color_image_measured", 1);
  if (!tie_valid || !tie_pixels || !previous_tie) { color_missing("tie_population_or_scene_depth_missing"); return; }
  autoport_proof::publish("ao_tie_color_tie_changed_px", tie_changed);
  autoport_proof::publish("ao_tie_color_measured", 1);
  autoport_proof::publish("ao_tie_color_missing_fields", 0);
  autoport_proof::publish_text("ao_tie_color_missing", "none");
  enabled = false;
}
}  // namespace ao_tie_alpha_probe
