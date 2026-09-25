#include "flip_census.h"

#ifndef __ANDROID__
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <set>
#include <unordered_map>
#include <vector>
#include "game/system/autoport_proof.h"
#include "game/system/load_gate.h"
#include "common/log/log.h"
#include "third-party/glad/include/glad/glad.h"
#endif

namespace flip_census {

#ifndef __ANDROID__
namespace {
constexpr const char* kItem = "lighting-flipped-faces-everywhere";
AUTOPORT_FEATURE_SITE(kItem);

const char* kFamNames[kFamilies] = {"tfrag", "tie", "tiewind", "shrub", "grass", "ocean", "merc"};

bool is_decor_family(Family f) {
  return f == TFRAG || f == TIE || f == TIE_WIND || f == SHRUB;
}

struct Step {
  const char* continue_name;
  const char* level;
};

// Tournee en dur : 21 etapes (continuation de warp, niveau attendu).
const Step kSteps[21] = {
    {"training-start", "training"},       {"village1-hut", "village1"},
    {"beach-start", "beach"},             {"jungle-start", "jungle"},
    {"jungle-tower", "jungleb"},          {"misty-start", "misty"},
    {"firecanyon-start", "firecanyon"},   {"village2-start", "village2"},
    {"sunken-start", "sunken"},           {"sunkenb-start", "sunkenb"},
    {"swamp-start", "swamp"},             {"rolling-start", "rolling"},
    {"ogre-start", "ogre"},               {"village3-start", "village3"},
    {"snow-start", "snow"},               {"maincave-start", "maincave"},
    {"darkcave-start", "darkcave"},       {"robocave-start", "robocave"},
    {"lavatube-start", "lavatube"},       {"citadel-start", "citadel"},
    {"finalboss-start", "finalboss"},
};
constexpr int kNumSteps = 21;
constexpr uint64_t kBootFrame = 900;
constexpr int kReadyStreakNeeded = 120;
constexpr uint64_t kRequestTimeout = 3600;
constexpr int kWindowFrames = 300;

enum class State { BOOT, REQUEST, WAIT_READY, WINDOW, DONE };

// Etat de la tournee (fil GL uniquement, pas de verrou requis en dehors de la demande de warp).
State g_state = State::BOOT;
int g_step = 0;
int g_attempt = 0;
uint64_t g_request_frame = 0;
int g_ready_streak = 0;
int g_window_idx = 0;  // 0..kWindowFrames-1

// Niveaux vus par les tirages, doubles-buffer (image precedente / image en cours).
std::set<std::string> g_levels_cur;
std::set<std::string> g_levels_prev;

bool g_this_frame_is_probe = false;
// L'attache se fait au PREMIER tirage sonde de l'image : c'est la que le FBO de rendu est lie.
bool g_attach_tried = false;
uint64_t g_cur_frame_idx = 0;

// Demande de teleport en attente pour le fil GOAL.
std::mutex g_warp_mutex;
bool g_warp_pending = false;
char g_warp_name[128] = {0};

struct Acc {
  uint64_t px = 0, px_no_rt = 0, flip_px = 0, defect_px = 0, dim_px = 0, latent_px = 0;
  uint64_t draws = 0;
};
Acc g_step_acc[kFamilies];

// Totaux cumules sur toute la tournee, par famille.
Acc g_fam_totals[kFamilies];

uint64_t g_levels_visited = 0;
uint64_t g_levels_missing = 0;
std::vector<std::string> g_missing_list;
uint64_t g_couples_seen = 0;
uint64_t g_couples_measured = 0;
uint64_t g_couples_dark = 0;
uint64_t g_couples_unmeasured = 0;
std::vector<std::string> g_dark_list;
std::vector<std::string> g_unmeasured_list;

uint64_t g_probe_frames = 0;
uint64_t g_refused = 0;
uint64_t g_draws_other_fbo = 0;
uint64_t g_uniform_missing[kFamilies] = {};
uint64_t g_px_badcode = 0;
uint64_t g_px_nan = 0;
uint64_t g_px_black = 0;

// Attache / lecture de la texture RGBA32F, calquees sur floor_probe.cpp.
GLuint g_probe_tex = 0;
int g_tex_w = 0, g_tex_h = 0;
GLint g_target_fbo = 0;
bool g_attached = false;

bool g_pending = false;
GLuint g_pending_tex = 0;
int g_pending_w = 0, g_pending_h = 0;
GLint g_pending_fbo = 0;

GLuint g_reader_fbo = 0;

GLint g_saved_draw_bufs[4] = {};
GLint g_saved_program = 0;
GLuint g_active_program = 0;
Family g_active_family = TFRAG;
bool g_draw_active = false;

std::unordered_map<GLuint, GLint> g_uniform_loc_cache;

std::string join(const std::vector<std::string>& v) {
  if (v.empty()) return "-";
  std::string out;
  for (size_t i = 0; i < v.size(); ++i) {
    if (i) out += ",";
    out += v[i];
  }
  return out;
}

void refused(const char* why) {
  ++g_refused;
  autoport_proof::publish("flipped_probe_refused", g_refused);
  autoport_proof::publish_text("flipped_probe_refused_why", why);
}

GLint uniform_loc(GLuint program) {
  auto it = g_uniform_loc_cache.find(program);
  if (it != g_uniform_loc_cache.end()) return it->second;
  GLint loc = glGetUniformLocation(program, "u_floor_probe");
  g_uniform_loc_cache.emplace(program, loc);
  return loc;
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

void decode_and_accumulate(const std::vector<float>& pix, int w, int h) {
  const size_t count = (size_t)w * (size_t)h;
  for (size_t i = 0; i < count; ++i) {
    const float* p = &pix[i * 4];
    float x = p[0], y = p[1], z = p[2], wv = p[3];
    if (wv == 0.0f) continue;
    int v = (int)std::lround(wv) - 1;
    bool flip = (v & 1) != 0;
    bool rt = (v & 2) != 0;
    int code = v >> 2;
    int fam_i = code - 2;
    if (fam_i < 0 || fam_i >= kFamilies) {
      ++g_px_badcode;
      continue;
    }
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) {
      ++g_px_nan;
      continue;
    }
    if (z < 0.02f) {
      ++g_px_black;
      continue;
    }
    Family fam = (Family)fam_i;
    Acc& a = g_step_acc[fam];
    a.px++;
    if (is_decor_family(fam) && !rt) a.px_no_rt++;
    if (flip) a.flip_px++;
    if (flip && x < 0.5f && y >= 0.5f) a.defect_px++;
    if (flip && x < 0.8f * y) a.dim_px++;
    if (!flip && y < 0.5f && x >= 0.5f) a.latent_px++;
  }
  autoport_proof::publish("flipped_px_badcode", g_px_badcode);
  autoport_proof::publish("flipped_px_nan", g_px_nan);
  autoport_proof::publish("flipped_px_black", g_px_black);
}

void do_read_and_detach() {
  GLint old_draw, old_read;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &old_draw);
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
  if (g_reader_fbo == 0) glGenFramebuffers(1, &g_reader_fbo);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_reader_fbo);
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_pending_tex, 0);
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
  ++g_probe_frames;
  autoport_proof::publish("flipped_probe_frames", g_probe_frames);
  decode_and_accumulate(pix, g_pending_w, g_pending_h);
  autoport_proof::note_hit_for(kItem, 1);
}

void reset_step_acc() {
  for (int i = 0; i < kFamilies; ++i) g_step_acc[i] = Acc{};
}

void publish_step(int step) {
  const std::string lvl = kSteps[step].level;
  for (int f = 0; f < kFamilies; ++f) {
    const Acc& a = g_step_acc[f];
    if (a.draws == 0 && a.px == 0) continue;
    const std::string key = lvl + "_" + kFamNames[f];
    autoport_proof::publish(("flip_px_" + key).c_str(), a.px);
    autoport_proof::publish(("flip_draws_" + key).c_str(), a.draws);
    uint64_t flipped_ppm = a.px ? (uint64_t)std::lround(1e6 * (double)a.flip_px / (double)a.px) : 0;
    autoport_proof::publish(("flip_flipped_ppm_" + key).c_str(), flipped_ppm);
    autoport_proof::publish(("flip_defect_px_" + key).c_str(), a.defect_px);
    uint64_t dim_ppm = a.px ? (uint64_t)std::lround(1e6 * (double)a.dim_px / (double)a.px) : 0;
    autoport_proof::publish(("flip_dim_ppm_" + key).c_str(), dim_ppm);
    autoport_proof::publish(("flip_latent_px_" + key).c_str(), a.latent_px);
    autoport_proof::publish(("flip_nort_px_" + key).c_str(), a.px_no_rt);
    lg::info(
        "[flip-census] lvl={} fam={} px={} draws={} flipped_ppm={} defect={} dim_ppm={} "
        "latent={} nort={}",
        lvl, kFamNames[f], a.px, a.draws, flipped_ppm, a.defect_px, dim_ppm, a.latent_px,
        a.px_no_rt);

    g_fam_totals[f].px += a.px;
    g_fam_totals[f].flip_px += a.flip_px;
    g_fam_totals[f].defect_px += a.defect_px;
    g_fam_totals[f].dim_px += a.dim_px;
    g_fam_totals[f].latent_px += a.latent_px;

    bool seen = true;
    bool measured = a.px >= 500 && (!is_decor_family((Family)f) || a.px_no_rt * 100 <= a.px);
    if (seen) ++g_couples_seen;
    const std::string couple = lvl + ":" + kFamNames[f];
    if (measured) {
      ++g_couples_measured;
      if (a.defect_px > 0) {
        ++g_couples_dark;
        g_dark_list.push_back(couple);
      }
    } else {
      ++g_couples_unmeasured;
      g_unmeasured_list.push_back(couple);
    }
  }
}

void publish_summary() {
  autoport_proof::publish("flipped_levels_expected", (uint64_t)kNumSteps);
  autoport_proof::publish("flipped_levels_visited", g_levels_visited);
  autoport_proof::publish("flipped_levels_missing", g_levels_missing);
  autoport_proof::publish_text("flipped_levels_missing_list", join(g_missing_list).c_str());
  autoport_proof::publish("flipped_couples_seen", g_couples_seen);
  autoport_proof::publish("flipped_couples_measured", g_couples_measured);
  autoport_proof::publish("flipped_couples_dark", g_couples_dark);
  autoport_proof::publish("flipped_couples_unmeasured", g_couples_unmeasured);
  autoport_proof::publish_text("flipped_couples_dark_list", join(g_dark_list).c_str());
  autoport_proof::publish_text("flipped_couples_unmeasured_list", join(g_unmeasured_list).c_str());
  for (int f = 0; f < kFamilies; ++f) {
    const std::string suf = kFamNames[f];
    autoport_proof::publish(("flipped_fam_px_" + suf).c_str(), g_fam_totals[f].px);
    uint64_t ppm = g_fam_totals[f].px
                       ? (uint64_t)std::lround(1e6 * (double)g_fam_totals[f].flip_px /
                                               (double)g_fam_totals[f].px)
                       : 0;
    autoport_proof::publish(("flipped_fam_flipped_ppm_" + suf).c_str(), ppm);
    autoport_proof::publish(("flipped_fam_defect_px_" + suf).c_str(), g_fam_totals[f].defect_px);
    autoport_proof::publish(("flipped_fam_dim_px_" + suf).c_str(), g_fam_totals[f].dim_px);
    autoport_proof::publish(("flipped_fam_latent_px_" + suf).c_str(), g_fam_totals[f].latent_px);
  }
  autoport_proof::publish("flipped_probe_frames", g_probe_frames);
  const bool done = g_state == State::DONE;
  autoport_proof::publish("flipped_tour_done", done ? uint64_t(1) : uint64_t(0));

  if (done) {
    uint64_t visited_plus_missing = g_levels_visited + g_levels_missing;
    uint64_t incoherence = visited_plus_missing < (uint64_t)kNumSteps
                              ? (uint64_t)kNumSteps - visited_plus_missing
                              : 0;
    uint64_t value = g_couples_dark + g_couples_unmeasured + g_levels_missing + incoherence;
    autoport_proof::publish("flipped_faces_dark", value);
  } else {
    autoport_proof::publish("flipped_faces_dark", (uint64_t)999);
  }
}

void request_warp(int step) {
  std::lock_guard<std::mutex> lk(g_warp_mutex);
  std::strncpy(g_warp_name, kSteps[step].continue_name, sizeof(g_warp_name) - 1);
  g_warp_name[sizeof(g_warp_name) - 1] = 0;
  g_warp_pending = true;
}

void log_transition(const char* state) {
  printf("FLIP-CENSUS step=%d/%d cont=%s level=%s state=%s\n", g_step + 1, kNumSteps,
        kSteps[g_step].continue_name, kSteps[g_step].level, state);
  fflush(stdout);
}

}  // namespace
#endif  // !__ANDROID__

bool active() {
#ifndef __ANDROID__
  static bool checked = false;
  static bool value = false;
  if (!checked) {
    checked = true;
    const char* e = getenv("OG_FLIP_TOUR");
    value = e && std::string(e) == "1" && autoport_proof::armed_for(kItem);
  }
  return value;
#else
  return false;
#endif
}

void frame_tick(uint64_t frame_idx) {
#ifndef __ANDROID__
  if (!active()) return;
  g_cur_frame_idx = frame_idx;
  if (g_state == State::BOOT) {
    autoport_proof::publish("flipped_faces_dark", (uint64_t)999);
  }

  // Detacher/relire la sonde attachee a l'image precedente (sonde => WINDOW uniquement).
  if (g_pending) {
    do_read_and_detach();
    g_pending = false;
  }
  if (g_attached) {
    g_pending = true;
    g_pending_tex = g_probe_tex;
    g_pending_w = g_tex_w;
    g_pending_h = g_tex_h;
    g_pending_fbo = g_target_fbo;
    g_attached = false;
  }

  g_levels_prev = g_levels_cur;
  g_levels_cur.clear();
  g_this_frame_is_probe = false;
  g_attach_tried = false;

  switch (g_state) {
    case State::BOOT: {
      if (frame_idx >= kBootFrame) {
        g_attempt = 1;
        request_warp(g_step);
        g_request_frame = frame_idx;
        g_state = State::REQUEST;
        log_transition("REQUEST");
      }
      break;
    }
    case State::REQUEST: {
      g_ready_streak = 0;
      g_state = State::WAIT_READY;
      log_transition("WAIT_READY");
      break;
    }
    case State::WAIT_READY: {
      const bool ready = !load_gate::loading_screen_is_covering() &&
                         g_levels_prev.count(kSteps[g_step].level) != 0;
      if (ready) {
        ++g_ready_streak;
        if (g_ready_streak >= kReadyStreakNeeded) {
          g_window_idx = 0;
          reset_step_acc();
          g_state = State::WINDOW;
          log_transition("WINDOW");
        }
      } else {
        g_ready_streak = 0;
      }
      if (g_state == State::WAIT_READY && frame_idx - g_request_frame >= kRequestTimeout) {
        if (g_attempt < 2) {
          ++g_attempt;
          request_warp(g_step);
          g_request_frame = frame_idx;
          g_ready_streak = 0;
          log_transition("REQUEST_RETRY");
        } else {
          ++g_levels_missing;
          g_missing_list.push_back(kSteps[g_step].level);
          log_transition("MISSING");
          ++g_step;
          if (g_step >= kNumSteps) {
            g_state = State::DONE;
            publish_summary();
            log_transition("DONE");
          } else {
            g_attempt = 1;
            request_warp(g_step);
            g_request_frame = frame_idx;
            g_state = State::REQUEST;
            log_transition("REQUEST");
          }
        }
      }
      break;
    }
    case State::WINDOW: {
      g_this_frame_is_probe = (g_window_idx % 10 == 5);
      ++g_window_idx;
      if (g_window_idx >= kWindowFrames) {
        ++g_levels_visited;
        publish_step(g_step);
        publish_summary();
        log_transition("STEP_DONE");
        ++g_step;
        if (g_step >= kNumSteps) {
          g_state = State::DONE;
          publish_summary();
          log_transition("DONE");
        } else {
          g_attempt = 1;
          request_warp(g_step);
          g_request_frame = frame_idx;
          g_state = State::REQUEST;
          log_transition("REQUEST");
        }
      }
      break;
    }
    case State::DONE:
      break;
  }

#else
  (void)frame_idx;
#endif
}

void before_draw(Family f, unsigned program, uint64_t frame_idx, const std::string& level_name) {
#ifndef __ANDROID__
  if (!active()) return;
  (void)frame_idx;
  if (!level_name.empty()) g_levels_cur.insert(level_name);
  if (g_state != State::WINDOW) return;
  g_step_acc[f].draws++;
  if (!g_this_frame_is_probe) return;
  if (!g_attached && !g_attach_tried) {
    g_attach_tried = true;
    attach_for_frame();
  }
  if (!g_attached) return;

  GLint cur_fbo;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &cur_fbo);
  if (cur_fbo != g_target_fbo) {
    ++g_draws_other_fbo;
    autoport_proof::publish("flipped_draws_other_fbo", g_draws_other_fbo);
    return;
  }
  GLint loc = uniform_loc(program);
  if (loc < 0) {
    ++g_uniform_missing[f];
    autoport_proof::publish(("flipped_uniform_missing_" + std::string(kFamNames[f])).c_str(),
                            g_uniform_missing[f]);
    return;
  }
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
  g_active_family = f;
  glUniform1i(loc, 2 + (int)f);
  g_draw_active = true;
#else
  (void)f;
  (void)program;
  (void)frame_idx;
  (void)level_name;
#endif
}

void after_draw() {
#ifndef __ANDROID__
  if (!active()) return;
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

bool take_warp_request(char* name, size_t cap) {
#ifndef __ANDROID__
  std::lock_guard<std::mutex> lk(g_warp_mutex);
  if (!g_warp_pending) return false;
  g_warp_pending = false;
  std::strncpy(name, g_warp_name, cap - 1);
  name[cap - 1] = 0;
  return true;
#else
  (void)name;
  (void)cap;
  return false;
#endif
}

}  // namespace flip_census
