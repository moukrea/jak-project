#include "Sprite3.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"

#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/dma_helpers.h"
#include "game/mips2c/spart_prof.h"
#include "game/graphics/refset.h"
#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/fire_red_census.h"
#include "game/system/autoport_proof.h"
#include "third-party/json.hpp"

#include "fmt/format.h"
#include "third-party/imgui/imgui.h"

// Geco-spheres TEMPORARY diagnostic gate — env OG_SPART_DUMP / Android prop
// debug.opengoal.spart.dump; value 1 arms now, N>1 arms N seconds after first
// check (same convention as the mips2c SPART probes).
static bool geco_spr3_dump_armed() {
  static long s_delay = -2;
  if (s_delay == -2) {
    s_delay = -1;
    const char* v = std::getenv("OG_SPART_DUMP");
#if defined(__ANDROID__)
    char pbuf[92] = {0};
    if (!v && __system_property_get("debug.opengoal.spart.dump", pbuf) > 0 && pbuf[0]) {
      v = pbuf;
    }
#endif
    if (v && v[0]) {
      long n = std::atol(v);
      if (n == 1) {
        s_delay = 0;
      } else if (n > 1) {
        s_delay = (long)time(nullptr) + n;
      }
    }
  }
  if (s_delay > 0 && (long)time(nullptr) >= s_delay) {
    s_delay = 0;
  }
  return s_delay == 0;
}

namespace {

// Diagnostic only: no proof publication or artistic changes.
bool owner_sprite_probe() {
  return autoport_proof::feature_is("lighting-hdr") && refset::wants_scene_probe();
}

int64_t owner_sprite_lf() {
  return refset::capture_logic_frame();
}

// Two native-resolution snapshots around the complete world-sprite group. This is
// diagnostic memory only; it neither changes the scene nor publishes proof keys.
struct OwnerCompositionImage {
  std::array<GLint, 4> viewport{};
  GLint framebuffer = 0;
  GLenum error = GL_NO_ERROR;
  std::string status = "not_captured", format = "unknown";
  std::vector<float> rgba;
};
struct OwnerCompositionRoi {
  int actor = 0;
  std::string case_name, layer;
  nlohmann::json attribution;
  std::array<int, 4> bounds{320, 180, 0, 0};
  int candidates = 0, projected = 0, visible = 0, passed = 0, passed_unknown = 0;
};
struct OwnerComposition {
  bool collecting = false;
  int64_t lf = -1;
  std::array<OwnerCompositionRoi, 5> rois{};
  OwnerCompositionImage before;
} owner_composition, owner_cloud_composition;

float owner_half_float(uint16_t h) {
  const int exponent = (h >> 10) & 31;
  const int fraction = h & 1023;
  const float value = exponent == 0    ? std::ldexp(float(fraction), -24)
                      : exponent == 31 ? (fraction ? NAN : INFINITY)
                                       : std::ldexp(float(1024 + fraction), exponent - 25);
  return (h & 0x8000) ? -value : value;
}

OwnerCompositionImage owner_composition_read() {
  gl_query_census::Armed _ap("sprite-owner-probe");
  OwnerCompositionImage image;
  image.error = glGetError();
  if (image.error != GL_NO_ERROR) {
    image.status = "preexisting_gl_error";
    return image;
  }
  glGetIntegerv(GL_VIEWPORT, image.viewport.data());
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &image.framebuffer);
  GLint samples = 0, draw_buffer = 0;
  glGetIntegerv(GL_SAMPLES, &samples);
  glGetIntegerv(GL_DRAW_BUFFER0, &draw_buffer);
  const auto& v = image.viewport;
  if (samples > 0 || !image.framebuffer || draw_buffer == GL_NONE || v[0] < 0 || v[1] < 0 ||
      v[2] <= 0 || v[3] <= 0 || int64_t(v[2]) * v[3] > 1920 * 1080) {
    image.status = samples > 0 ? "multisample_not_measured" : "unsupported_framebuffer_or_size";
    return image;
  }
  // Restore both FBOs' read selectors: GL_READ_BUFFER belongs to its FBO.
  GLint saved_read = 0, saved_selector = 0, target_selector = 0, pack_buffer = 0;
  const GLenum pack_names[] = {GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH, GL_PACK_SKIP_ROWS,
                               GL_PACK_SKIP_PIXELS};
  GLint pack[4] = {};
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saved_read);
  glGetIntegerv(GL_READ_BUFFER, &saved_selector);
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack_buffer);
  for (int i = 0; i < 4; ++i)
    glGetIntegerv(pack_names[i], &pack[i]);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, image.framebuffer);
  glGetIntegerv(GL_READ_BUFFER, &target_selector);
  glReadBuffer(draw_buffer);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  for (int i = 1; i < 4; ++i)
    glPixelStorei(pack_names[i], 0);
  auto read = [&]() {
    if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      image.status = "incomplete_framebuffer";
      return;
    }
    GLint object_type = 0, object = 0, width = 0, height = 0, component = 0, bits[4] = {};
    glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, draw_buffer,
                                          GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &object_type);
    glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, draw_buffer,
                                          GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &object);
    if (object_type == GL_RENDERBUFFER) {
      GLint saved = 0;
      glGetIntegerv(GL_RENDERBUFFER_BINDING, &saved);
      glBindRenderbuffer(GL_RENDERBUFFER, object);
      glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
      glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
      glBindRenderbuffer(GL_RENDERBUFFER, saved);
    } else if (object_type == GL_TEXTURE) {
      GLint saved = 0, level = 0;
      glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, draw_buffer,
                                            GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL, &level);
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved);
      glBindTexture(GL_TEXTURE_2D, object);
      // Other texture targets fail closed at the GL error check below.
      glGetTexLevelParameteriv(GL_TEXTURE_2D, level, GL_TEXTURE_WIDTH, &width);
      glGetTexLevelParameteriv(GL_TEXTURE_2D, level, GL_TEXTURE_HEIGHT, &height);
      glBindTexture(GL_TEXTURE_2D, saved);
    }
    glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, draw_buffer,
                                          GL_FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE, &component);
    const GLenum bit_names[] = {
        GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE, GL_FRAMEBUFFER_ATTACHMENT_GREEN_SIZE,
        GL_FRAMEBUFFER_ATTACHMENT_BLUE_SIZE, GL_FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE};
    for (int i = 0; i < 4; ++i)
      glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, draw_buffer, bit_names[i],
                                            &bits[i]);
    GLint type = GL_FLOAT, format = GL_RGBA;
#ifdef __ANDROID__
    glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &type);
    glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &format);
#endif
    if (component == GL_UNSIGNED_NORMALIZED && bits[0] == 8 && bits[1] == 8 && bits[2] == 8 &&
        bits[3] == 8) {
      type = GL_UNSIGNED_BYTE;
      format = GL_RGBA;
      image.format = "RGBA8/UNSIGNED_BYTE";
    } else if (component == GL_FLOAT && format == GL_RGBA &&
               (type == GL_FLOAT || type == GL_HALF_FLOAT)) {
      image.format = type == GL_FLOAT ? "RGBA/FLOAT" : "RGBA/HALF_FLOAT";
    } else {
      image.status = "unsupported_read_format";
      return;
    }
    image.error = glGetError();
    if (image.error != GL_NO_ERROR) {
      image.status = "query_gl_error";
      return;
    }
    if (int64_t(v[0]) + v[2] > width || int64_t(v[1]) + v[3] > height) {
      image.status = "viewport_outside_attachment";
      return;
    }
    const size_t count = size_t(v[2]) * v[3] * 4;
    image.rgba.resize(count);
    if (type == GL_FLOAT) {
      glReadPixels(v[0], v[1], v[2], v[3], GL_RGBA, GL_FLOAT, image.rgba.data());
    } else if (type == GL_HALF_FLOAT) {
      std::vector<uint16_t> raw(count);
      glReadPixels(v[0], v[1], v[2], v[3], GL_RGBA, GL_HALF_FLOAT, raw.data());
      std::transform(raw.begin(), raw.end(), image.rgba.begin(), owner_half_float);
    } else {
      std::vector<uint8_t> raw(count);
      glReadPixels(v[0], v[1], v[2], v[3], GL_RGBA, GL_UNSIGNED_BYTE, raw.data());
      std::transform(raw.begin(), raw.end(), image.rgba.begin(),
                     [](uint8_t value) { return float(value) / 255.f; });
    }
    image.error = glGetError();
    image.status = image.error == GL_NO_ERROR ? "ok" : "read_gl_error";
  };
  read();
  glReadBuffer(target_selector);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, saved_read);
  glReadBuffer(saved_selector);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, pack_buffer);
  for (int i = 0; i < 4; ++i)
    glPixelStorei(pack_names[i], pack[i]);
  const GLenum error = glGetError();
  if (error != GL_NO_ERROR) {
    image.error = error;
    image.status = "gl_error";
  }
  if (image.status != "ok")
    image.rgba.clear();
  return image;
}

void owner_composition_accumulate(OwnerCompositionRoi& roi, const nlohmann::json& event) {
  roi.actor = event.at("actor").get<int>();
  ++roi.candidates;
  if (event.at("passed").is_null())
    ++roi.passed_unknown;
  else if (event.at("passed").get<bool>())
    ++roi.passed;
  if (event.at("roi").is_null())
    return;
  ++roi.projected;
  const auto b = event.at("roi").get<std::array<int, 4>>();
  if (b[0] >= b[2] || b[1] >= b[3])
    return;
  ++roi.visible;
  for (int k = 0; k < 2; ++k) {
    roi.bounds[k] = std::min(roi.bounds[k], b[k]);
    roi.bounds[k + 2] = std::max(roi.bounds[k + 2], b[k + 2]);
  }
}

void owner_composition_roi(OwnerComposition& composition, const nlohmann::json& event) {
  if (!composition.collecting || composition.lf != owner_sprite_lf())
    return;
  const int actor = event.at("actor").get<int>();
  const auto case_name = event.value("case", std::string{});
  const int index = actor == 10012             ? 0
                    : actor == 10013           ? 1
                    : actor == 1395            ? 2
                    : case_name == "sunset-sun" ? 3
                    : case_name == "clouds"     ? 0
                                               : -1;
  if (index < 0)
    return;
  owner_composition_accumulate(composition.rois[index], event);
  if (actor == 1395 && event.value("layer", std::string{}) == "portal_disc" &&
      event.value("texture", std::string{}) == "effects/harddot" &&
      event.value("render_mode", -1) == 3 && event.value("supported", false) &&
      event.at("passed") == true) {
    auto& disc = composition.rois[4];
    disc.case_name = "warp-gate";
    disc.layer = "portal_disc";
    disc.attribution = {{"association", "actor_layer_texture_render_mode_passed_supported"},
                        {"actor", actor}, {"layer", "portal_disc"},
                        {"texture", "effects/harddot"}, {"render_mode", 3},
                        {"passed", true}, {"supported", true}};
    owner_composition_accumulate(disc, event);
  }
}

// Keep Android log records below its truncation boundary. Event fields live in a
// separate object so their names cannot collide with the transport envelope.
void owner_composition_log(const nlohmann::json& event) {
  static uint64_t next_event_id = 0;  // Distinguishes repeated lf/actor/stage in this process.
  constexpr size_t max_bytes = 800;
  nlohmann::json envelope = {{"event_id", next_event_id++},       {"lf", event.at("lf")},
                             {"actor", event.at("actor")},        {"stage", event.at("stage")},
                             {"part_index", event.size()},        {"part_count", event.size()},
                             {"fields", nlohmann::json::object()}};
  std::vector<nlohmann::json> parts;
  auto fields = nlohmann::json::object();
  for (auto it = event.begin(); it != event.end(); ++it) {
    envelope["fields"] = fields;
    envelope["fields"][it.key()] = it.value();
    if (envelope.dump().size() > max_bytes && !fields.empty()) {
      parts.push_back(std::move(fields));
      fields = nlohmann::json::object();
      envelope["fields"] = {{it.key(), it.value()}};
    }
    if (envelope.dump().size() > max_bytes) {
      envelope["fields"] = nlohmann::json::object();
      envelope["part_index"] = 0;
      envelope["part_count"] = 1;
      envelope["status"] = "field_exceeds_chunk_limit_not_emitted";
      lg::info("HDR-OWNER-COMPOSITION {}", envelope.dump());
      return;  // Emit no partial measurement on a field that cannot fit.
    }
    fields[it.key()] = it.value();
  }
  if (!fields.empty())
    parts.push_back(std::move(fields));
  for (size_t i = 0; i < parts.size(); ++i) {
    envelope["part_index"] = i;
    envelope["part_count"] = parts.size();
    envelope["fields"] = std::move(parts[i]);
    lg::info("HDR-OWNER-COMPOSITION {}", envelope.dump());
  }
}

void owner_composition_report(const OwnerComposition& composition,
                              const OwnerCompositionImage& after,
                              const char* before_stage = "before_world_sprites",
                              const char* after_stage = "after_world_sprites") {
  const float e = Gfx::g_global_settings.recharged_pbr_exposure;
  const float exposure =
      (e > 0.f ? std::pow(e, 1.f / 2.2f) : 1.f) * Gfx::g_global_settings.recharged_hdr_exposure;
  const float knee = Gfx::g_global_settings.recharged_hdr_knee;
  const bool shoulder = Gfx::g_global_settings.recharged_hdr_curve == 0 && std::isfinite(knee) &&
                        std::isfinite(exposure);
  for (const auto& roi : composition.rois) {
    if (!roi.actor && roi.case_name.empty())
      continue;
    for (int stage = 0; stage < 2; ++stage) {
      const auto& image = stage ? after : composition.before;
      nlohmann::json event = {
          {"lf", composition.lf},
          {"actor", roi.actor},
          {"stage", stage ? after_stage : before_stage},
          {"roi_exclusive", roi.visible ? nlohmann::json(roi.bounds) : nlohmann::json(nullptr)},
          {"roi_space", "top_left_320x180"},
          {"viewport_native", image.viewport},
          {"framebuffer", image.framebuffer},
          {"format", image.format},
          {"status", image.status},
          {"error", image.error},
          {"pixels", 0},
          {"candidates", roi.candidates},
          {"projected", roi.projected},
          {"visible_roi", roi.visible},
          {"passed", roi.passed},
          {"passed_unknown", roi.passed_unknown},
          {"caveat", "bounding_union_includes_background_and_all_layers_not_actor_coverage"},
          {"effective_exposure", exposure},
          {"knee", Gfx::g_global_settings.recharged_hdr_knee},
          {"curve", Gfx::g_global_settings.recharged_hdr_curve},
          {"tonemap_stats",
           shoulder ? "not_measured" : "curve_or_parameters_not_supported"},
          {"quantization",
           "round(clamp(rgb,0,1)*255); white=all255; nearwhite=all>=245; clipped=any255"}};
      if (!roi.case_name.empty()) {
        event["case"] = roi.case_name;
        event["layer"] = roi.layer;
        if (!roi.attribution.is_null())
          event["attribution"] = roi.attribution;
      }
      if (image.status == "ok" && roi.visible) {
        const auto& v = image.viewport;
        const int x0 = int(std::floor(double(roi.bounds[0]) * v[2] / 320));
        const int x1 = int(std::ceil(double(roi.bounds[2]) * v[2] / 320));
        const int y0 = int(std::floor(double(roi.bounds[1]) * v[3] / 180));
        const int y1 = int(std::ceil(double(roi.bounds[3]) * v[3] / 180));
        std::array<double, 4> lo{INFINITY, INFINITY, INFINITY, INFINITY};
        std::array<double, 4> hi{-INFINITY, -INFINITY, -INFINITY, -INFINITY}, sum{};
        std::array<int, 4> negative{}, above_one{};
        int pixels = 0, nonfinite = 0, white = 0, nearwhite = 0, clipped = 0;
        int tone_white = 0, tone_nearwhite = 0, tone_clipped = 0, tone_nonfinite = 0;
        const auto& before = composition.before;
        const bool paired = stage && before.status == "ok" &&
                            before.framebuffer == image.framebuffer &&
                            before.viewport == image.viewport && before.format == image.format;
        std::array<double, 4> delta_lo{INFINITY, INFINITY, INFINITY, INFINITY};
        std::array<double, 4> delta_hi{-INFINITY, -INFINITY, -INFINITY, -INFINITY}, delta_sum{};
        std::array<int, 4> delta_negative{}, delta_positive{};
        int delta_nonfinite = 0;
        for (int y = y0; y < y1; ++y) {
          for (int x = x0; x < x1; ++x) {
            const float* p = &image.rgba[(size_t(v[3] - 1 - y) * v[2] + x) * 4];
            if (!std::all_of(p, p + 4, [](float c) { return std::isfinite(c); })) {
              ++nonfinite;
              continue;
            }
            ++pixels;
            for (int c = 0; c < 4; ++c) {
              lo[c] = std::min(lo[c], double(p[c]));
              hi[c] = std::max(hi[c], double(p[c]));
              sum[c] += p[c];
              negative[c] += p[c] < 0.f;
              above_one[c] += p[c] > 1.f;
            }
            int q[3];
            for (int c = 0; c < 3; ++c)
              q[c] = int(std::lround(std::clamp(p[c], 0.f, 1.f) * 255.f));
            white += q[0] == 255 && q[1] == 255 && q[2] == 255;
            nearwhite += q[0] >= 245 && q[1] >= 245 && q[2] >= 245;
            clipped += q[0] == 255 || q[1] == 255 || q[2] == 255;
            if (shoulder) {
              bool finite = true;
              for (int c = 0; c < 3; ++c) {
                // Mirror tonemap.frag main + hdr_shoulder, in display encoding.
                float value = std::max(p[c] * exposure, 0.f);
                const float w = std::max(1.f - knee, 1e-4f);
                if (value > knee) {
                  const float above = value - knee;
                  value = above >= 2.f * w ? 1.f : knee + above - above * above / (4.f * w);
                }
                value = std::min(value, 1.f);
                finite &= std::isfinite(value);
                q[c] = std::isfinite(value) ? int(std::lround(std::clamp(value, 0.f, 1.f) * 255.f))
                                            : 0;
              }
              tone_nonfinite += !finite;
              tone_white += finite && q[0] == 255 && q[1] == 255 && q[2] == 255;
              tone_nearwhite += finite && q[0] >= 245 && q[1] >= 245 && q[2] >= 245;
              tone_clipped += finite && (q[0] == 255 || q[1] == 255 || q[2] == 255);
            }
            if (paired) {
              const float* pre = &before.rgba[(size_t(v[3] - 1 - y) * v[2] + x) * 4];
              if (!std::all_of(pre, pre + 4, [](float c) { return std::isfinite(c); })) {
                ++delta_nonfinite;
              } else {
                for (int c = 0; c < 4; ++c) {
                  const double d = double(p[c]) - pre[c];
                  delta_lo[c] = std::min(delta_lo[c], d);
                  delta_hi[c] = std::max(delta_hi[c], d);
                  delta_sum[c] += d;
                  delta_negative[c] += d < 0;
                  delta_positive[c] += d > 0;
                }
              }
            }
          }
        }
        event["roi_native_exclusive_top_left"] = {x0, y0, x1, y1};
        event["pixels"] = pixels;
        event["nonfinite_pixels"] = nonfinite;
        if (nonfinite) {
          event["status"] = "nonfinite_not_measured";
          event["tonemap_stats"] = "nonfinite_not_measured";
          if (stage)
            event["delta_status"] = "nonfinite_not_measured";
        } else if (pixels) {
          for (auto& c : sum)
            c /= pixels;
          event["min_rgba"] = lo;
          event["max_rgba"] = hi;
          event["mean_rgba"] = sum;
          event["negative_channels"] = negative;
          event["above_one_channels"] = above_one;
          event["white"] = white;
          event["nearwhite"] = nearwhite;
          event["clipped"] = clipped;
          if (shoulder) {
            event["tonemap_stats"] =
                tone_nonfinite ? "nonfinite_not_measured" : "simulated_shoulder";
            if (!tone_nonfinite) {
              event["tonemap_white"] = tone_white;
              event["tonemap_nearwhite"] = tone_nearwhite;
              event["tonemap_clipped"] = tone_clipped;
            }
          }
          if (stage) {
            event["delta_status"] = !paired           ? "incompatible_snapshots"
                                    : delta_nonfinite ? "nonfinite_not_measured"
                                                      : "ok";
            event["delta_nonfinite_pixels"] = delta_nonfinite;
            if (paired && !delta_nonfinite) {
              event["delta_min_rgba"] = delta_lo;
              event["delta_max_rgba"] = delta_hi;
              event["delta_sum_rgba"] = delta_sum;
              event["delta_negative_channels"] = delta_negative;
              event["delta_positive_channels"] = delta_positive;
            }
          }
        }
      } else if (image.status == "ok") {
        event["status"] = "no_visible_roi";
      }
      owner_composition_log(event);
    }
  }
}

/*!
 * Does the next DMA transfer look like it could be the start of a 2D group?
 */
bool looks_like_2d_chunk_start(const DmaFollower& dma) {
  return dma.current_tag().qwc == 1 && dma.current_tag().kind == DmaTag::Kind::CNT;
}

/*!
 * Read the header. Asserts if it's bad.
 * Returns the number of sprites.
 * Advances 1 dma transfer
 */
u32 process_sprite_chunk_header(DmaFollower& dma) {
  auto transfer = dma.read_and_advance();
  // note that flg = true, this should use double buffering
  bool ok = verify_unpack_with_stcycl(transfer, VifCode::Kind::UNPACK_V4_32, 4, 4, 1,
                                      SpriteDataMem::Header, false, true);
  ASSERT(ok);
  u32 header[4];
  memcpy(header, transfer.data, 16);
  ASSERT(header[0] <= Sprite3::SPRITES_PER_CHUNK);
  return header[0];
}

constexpr int SPRITE_RENDERER_MAX_SPRITES = 1920 * 12;
}  // namespace

void hdr_owner_cloud_before() {
  owner_cloud_composition = {};
  if (!owner_sprite_probe())
    return;
  owner_cloud_composition.lf = owner_sprite_lf();
  owner_cloud_composition.rois[0].case_name = "clouds";
  owner_cloud_composition.rois[0].layer = "clouds";
  owner_cloud_composition.before = owner_composition_read();
  owner_cloud_composition.collecting = true;
}

void hdr_owner_cloud_after(const nlohmann::json& event) {
  if (!owner_cloud_composition.collecting)
    return;
  owner_composition_roi(owner_cloud_composition, event);
  owner_cloud_composition.collecting = false;
  owner_cloud_composition.rois[0].attribution = event;
  auto after = owner_composition_read();
  if (owner_cloud_composition.lf != owner_sprite_lf() ||
      after.framebuffer != owner_cloud_composition.before.framebuffer ||
      after.viewport != owner_cloud_composition.before.viewport) {
    after.status = "frame_or_target_changed_not_comparable";
    after.rgba.clear();
  }
  owner_composition_report(owner_cloud_composition, after, "before_cloud_draw", "after_cloud_draw");
  owner_cloud_composition.before.rgba.clear();
}

Sprite3::Sprite3(const std::string& name, int my_id)
    : BucketRenderer(name, my_id), m_direct(name, my_id, 1024) {
  opengl_setup();
}

void Sprite3::opengl_setup() {
  // Set up OpenGL for 'normal' sprites
  opengl_setup_normal();

  // Gperf-particles round 2: set up the per-instance VAO/buffer (jak1 Android).
  opengl_setup_instanced();

  // Set up OpenGL for distort sprites
  opengl_setup_distort();
}

void Sprite3::opengl_setup_normal() {
  glGenBuffers(1, &m_ogl.vertex_buffer);
  glGenVertexArrays(1, &m_ogl.vao);
  glBindVertexArray(m_ogl.vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_ogl.vertex_buffer);
  auto verts = SPRITE_RENDERER_MAX_SPRITES * 4;
  auto bytes = verts * sizeof(SpriteVertex3D);
  glBufferData(GL_ARRAY_BUFFER, bytes, nullptr, GL_STREAM_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(
      0,                                       // location 0 in the shader
      4,                                       // 4 floats per vert (w unused)
      GL_FLOAT,                                // floats
      GL_TRUE,                                 // normalized, ignored,
      sizeof(SpriteVertex3D),                  //
      (void*)offsetof(SpriteVertex3D, xyz_sx)  // offset in array (why is this a pointer...)
  );

  glEnableVertexAttribArray(1);
  glVertexAttribPointer(
      1,                                        // location 1 in the shader
      4,                                        // 4 color components
      GL_FLOAT,                                 // floats
      GL_TRUE,                                  // normalized, ignored,
      sizeof(SpriteVertex3D),                   //
      (void*)offsetof(SpriteVertex3D, quat_sy)  // offset in array (why is this a pointer...)
  );

  glEnableVertexAttribArray(2);
  glVertexAttribPointer(
      2,                                     // location 2 in the shader
      4,                                     // 4 color components
      GL_FLOAT,                              // floats
      GL_TRUE,                               // normalized, ignored,
      sizeof(SpriteVertex3D),                //
      (void*)offsetof(SpriteVertex3D, rgba)  // offset in array (why is this a pointer...)
  );

  glEnableVertexAttribArray(3);
  glVertexAttribIPointer(
      3,                                             // location 3 in the shader
      2,                                             // 4 color components
      GL_UNSIGNED_SHORT,                             // floats
      sizeof(SpriteVertex3D),                        //
      (void*)offsetof(SpriteVertex3D, flags_matrix)  // offset in array (why is this a pointer...)
  );

  glEnableVertexAttribArray(4);
  glVertexAttribIPointer(
      4,                                     // location 4 in the shader
      4,                                     // 3 floats per vert
      GL_UNSIGNED_SHORT,                     // floats
      sizeof(SpriteVertex3D),                //
      (void*)offsetof(SpriteVertex3D, info)  // offset in array (why is this a pointer...)
  );
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  u32 idx_buffer_len = SPRITE_RENDERER_MAX_SPRITES * 5;
  glGenBuffers(1, &m_ogl.index_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_ogl.index_buffer);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_buffer_len * sizeof(u32), nullptr, GL_STREAM_DRAW);

  glBindVertexArray(0);

  m_vertices_3d.resize(verts);
  m_index_buffer_data.resize(idx_buffer_len);

  m_default_mode.disable_depth_write();
  m_default_mode.set_depth_test(GsTest::ZTest::GEQUAL);
  m_default_mode.set_alpha_blend(DrawMode::AlphaBlend::SRC_DST_SRC_DST);
  m_default_mode.set_aref(38);
  m_default_mode.set_alpha_test(DrawMode::AlphaTest::GEQUAL);
  m_default_mode.set_alpha_fail(GsTest::AlphaFail::FB_ONLY);
  m_default_mode.set_at(true);
  m_default_mode.set_zt(true);
  m_default_mode.set_ab(true);

  m_current_mode = m_default_mode;
}

void Sprite3::opengl_setup_instanced() {
  // Gperf-particles round 2: per-instance sprite path. A second VAO over a NEW
  // instance buffer, with the SAME 5 attributes/offsets/stride 64 as
  // opengl_setup_normal, but each attribute advanced ONCE PER INSTANCE
  // (glVertexAttribDivisor == 1). One 64B SpriteVertex3D record per sprite; the
  // 4 corners come from gl_VertexID in the sprite3_3d_inst shader. No index
  // buffer (glDrawArraysInstanced with a 4-vertex triangle strip). Reserve the
  // same worst-case sprite count as the vertex path so the buffer never grows.
  glGenBuffers(1, &m_ogl.instance_buffer);
  glGenVertexArrays(1, &m_ogl.instance_vao);
  glBindVertexArray(m_ogl.instance_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_ogl.instance_buffer);
  glBufferData(GL_ARRAY_BUFFER, SPRITE_RENDERER_MAX_SPRITES * sizeof(SpriteVertex3D), nullptr,
               GL_STREAM_DRAW);

  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 4, GL_FLOAT, GL_TRUE, sizeof(SpriteVertex3D),
                        (void*)offsetof(SpriteVertex3D, xyz_sx));
  glVertexAttribDivisor(0, 1);

  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_TRUE, sizeof(SpriteVertex3D),
                        (void*)offsetof(SpriteVertex3D, quat_sy));
  glVertexAttribDivisor(1, 1);

  glEnableVertexAttribArray(2);
  glVertexAttribPointer(2, 4, GL_FLOAT, GL_TRUE, sizeof(SpriteVertex3D),
                        (void*)offsetof(SpriteVertex3D, rgba));
  glVertexAttribDivisor(2, 1);

  glEnableVertexAttribArray(3);
  glVertexAttribIPointer(3, 2, GL_UNSIGNED_SHORT, sizeof(SpriteVertex3D),
                         (void*)offsetof(SpriteVertex3D, flags_matrix));
  glVertexAttribDivisor(3, 1);

  glEnableVertexAttribArray(4);
  glVertexAttribIPointer(4, 4, GL_UNSIGNED_SHORT, sizeof(SpriteVertex3D),
                         (void*)offsetof(SpriteVertex3D, info));
  glVertexAttribDivisor(4, 1);

  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);

  m_instance_scratch.reserve(SPRITE_RENDERER_MAX_SPRITES);
}

/*!
 * Handle DMA data that does the per-frame setup.
 * This should get the dma chain immediately after the call to sprite-draw-distorters.
 * It ends right before the sprite-add-matrix-data for the 3d's
 */
void Sprite3::handle_sprite_frame_setup(DmaFollower& dma,
                                        GameVersion version,
                                        SharedRenderState* render_state,
                                        ScopedProfilerNode& /*prof*/) {
  // first is some direct data
  auto direct_data = dma.read_and_advance();
  ASSERT(direct_data.size_bytes == 3 * 16);
  memcpy(m_sprite_direct_setup, direct_data.data, 3 * 16);
  ASSERT(m_sprite_direct_setup[0] == 0x2000000000008001);
  ASSERT(m_sprite_direct_setup[1] == 0xEEEEEEEEEEEEEEEE);
  ASSERT(m_sprite_direct_setup[2] == 0x000000000005126B);
  ASSERT(m_sprite_direct_setup[3] == 0x0000000000000047);
  ASSERT(m_sprite_direct_setup[4] == 0x0000000000000005);
  ASSERT(m_sprite_direct_setup[5] == 0x0000000000000008);

  // next would be the program, but it's 0 size on the PC and isn't sent.

  // next is the "frame data"
  switch (version) {
    case GameVersion::Jak1: {
      render_state->shaders[ShaderId::SPRITE3].activate();
      auto frame_data = dma.read_and_advance();
      ASSERT(frame_data.size_bytes == (int)sizeof(SpriteFrameDataJak1));  // very cool
      ASSERT(frame_data.vifcode0().kind == VifCode::Kind::STCYCL);
      VifCodeStcycl frame_data_stcycl(frame_data.vifcode0());
      ASSERT(frame_data_stcycl.cl == 4);
      ASSERT(frame_data_stcycl.wl == 4);
      ASSERT(frame_data.vifcode1().kind == VifCode::Kind::UNPACK_V4_32);
      VifCodeUnpack frame_data_unpack(frame_data.vifcode1());
      ASSERT(frame_data_unpack.addr_qw == SpriteDataMem::FrameData);
      ASSERT(frame_data_unpack.use_tops_flag == false);
      SpriteFrameDataJak1 jak1_data;
      memcpy(&jak1_data, frame_data.data, sizeof(SpriteFrameDataJak1));
      m_frame_data.from_jak1(jak1_data);
    } break;
    case GameVersion::Jak2:
    case GameVersion::Jak3:
    case GameVersion::JakX: {
      render_state->shaders[ShaderId::SPRITE3].activate();
      auto frame_data = dma.read_and_advance();
      ASSERT(frame_data.size_bytes == (int)sizeof(SpriteFrameData));  // very cool
      ASSERT(frame_data.vifcode0().kind == VifCode::Kind::STCYCL);
      VifCodeStcycl frame_data_stcycl(frame_data.vifcode0());
      ASSERT(frame_data_stcycl.cl == 4);
      ASSERT(frame_data_stcycl.wl == 4);
      ASSERT(frame_data.vifcode1().kind == VifCode::Kind::UNPACK_V4_32);
      VifCodeUnpack frame_data_unpack(frame_data.vifcode1());
      ASSERT(frame_data_unpack.addr_qw == SpriteDataMem::FrameData);
      ASSERT(frame_data_unpack.use_tops_flag == false);
      memcpy(&m_frame_data, frame_data.data, sizeof(SpriteFrameData));
    } break;
    default:
      ASSERT_NOT_REACHED();
  }

  // next, a MSCALF.
  auto mscalf = dma.read_and_advance();
  ASSERT(mscalf.size_bytes == 0);
  ASSERT(mscalf.vifcode0().kind == VifCode::Kind::MSCALF);
  ASSERT(mscalf.vifcode0().immediate == SpriteProgMem::Init);
  ASSERT(mscalf.vifcode1().kind == VifCode::Kind::FLUSHE);

  // next base and offset
  auto base_offset = dma.read_and_advance();
  ASSERT(base_offset.size_bytes == 0);
  ASSERT(base_offset.vifcode0().kind == VifCode::Kind::BASE);
  ASSERT(base_offset.vifcode0().immediate == SpriteDataMem::Buffer0);
  ASSERT(base_offset.vifcode1().kind == VifCode::Kind::OFFSET);
  ASSERT(base_offset.vifcode1().immediate == SpriteDataMem::Buffer1);
}

void Sprite3::render_3d(DmaFollower& dma) {
  // one time matrix data
  auto matrix_data = dma.read_and_advance();
  ASSERT(matrix_data.size_bytes == sizeof(Sprite3DMatrixData));

  bool unpack_ok = verify_unpack_with_stcycl(matrix_data, VifCode::Kind::UNPACK_V4_32, 4, 4, 5,
                                             SpriteDataMem::Matrix, false, false);
  ASSERT(unpack_ok);
  static_assert(sizeof(m_3d_matrix_data) == 5 * 16);
  memcpy(&m_3d_matrix_data, matrix_data.data, sizeof(m_3d_matrix_data));
  // TODO
}

void Sprite3::set_group0_uniforms(GLuint shid, Sprite3dUniformCache& u3) {
  // Gperf-particles: cache these per-frame uniform locations (stable per linked
  // program), refreshed only on program change. The caller must have made `shid`
  // the active program.
  if (shid != u3.prog) {
    u3.prog = shid;
    u3.hvdf_offset = glGetUniformLocation(shid, "hvdf_offset");
    u3.pfog0 = glGetUniformLocation(shid, "pfog0");
    u3.min_scale = glGetUniformLocation(shid, "min_scale");
    u3.max_scale = glGetUniformLocation(shid, "max_scale");
    u3.fog_min = glGetUniformLocation(shid, "fog_min");
    u3.fog_max = glGetUniformLocation(shid, "fog_max");
    u3.deg_to_rad = glGetUniformLocation(shid, "deg_to_rad");
    u3.inv_area = glGetUniformLocation(shid, "inv_area");
    u3.camera = glGetUniformLocation(shid, "camera");
    u3.xy_array = glGetUniformLocation(shid, "xy_array");
    u3.xyz_array = glGetUniformLocation(shid, "xyz_array");
    u3.st_array = glGetUniformLocation(shid, "st_array");
    u3.basis_x = glGetUniformLocation(shid, "basis_x");
    u3.basis_y = glGetUniformLocation(shid, "basis_y");
  }
  glUniform4fv(u3.hvdf_offset, 1, m_3d_matrix_data.hvdf_offset.data());
  glUniform1f(u3.pfog0, m_frame_data.pfog0);
  glUniform1f(u3.min_scale, m_frame_data.min_scale);
  glUniform1f(u3.max_scale, m_frame_data.max_scale);
  glUniform1f(u3.fog_min, m_frame_data.fog_min);
  glUniform1f(u3.fog_max, m_frame_data.fog_max);
  // glUniform1f(glGetUniformLocation(shid, "bonus"), m_frame_data.bonus);
  // glUniform4fv(glGetUniformLocation(shid, "hmge_scale"), 1, m_frame_data.hmge_scale.data());
  glUniform1f(u3.deg_to_rad, m_frame_data.deg_to_rad);
  glUniform1f(u3.inv_area, m_frame_data.inv_area);
  glUniformMatrix4fv(u3.camera, 1, GL_FALSE, m_3d_matrix_data.camera.data());
  glUniform4fv(u3.xy_array, 8, m_frame_data.xy_array[0].data());
  glUniform4fv(u3.xyz_array, 4, m_frame_data.xyz_array[0].data());
  glUniform4fv(u3.st_array, 4, m_frame_data.st_array[0].data());
  glUniform4fv(u3.basis_x, 1, m_frame_data.basis_x.data());
  glUniform4fv(u3.basis_y, 1, m_frame_data.basis_y.data());
}

void Sprite3::render_2d_group0(DmaFollower& dma,
                               SharedRenderState* render_state,
                               ScopedProfilerNode& prof) {
  // opengl sprite frame setup. SPRITE3 is already the active program (activated
  // in handle_sprite_frame_setup); set its per-frame group0 uniforms.
  auto shid = render_state->shaders[ShaderId::SPRITE3].id();
  set_group0_uniforms(shid, m_sprite_3d_uniform_cache);

  // Gperf-particles round 2: the instanced path draws with a DIFFERENT program
  // object (SPRITE3_INSTANCED); it needs the same per-frame uniforms. Set them
  // now (switching program, then back) so flush_sprites can just bind + draw.
  if (render_state->perf_sprite_instance && render_state->version == GameVersion::Jak1) {
    auto inst = render_state->shaders[ShaderId::SPRITE3_INSTANCED].id();
    glUseProgram(inst);
    set_group0_uniforms(inst, m_sprite_3d_uniform_cache_inst);
    glUseProgram(shid);
  }

  u16 last_prog = -1;

  while (looks_like_2d_chunk_start(dma)) {
    m_debug_stats.blocks_2d_grp0++;
    // 4 packets per chunk

    // first is the header
    u32 sprite_count = process_sprite_chunk_header(dma);
    m_debug_stats.count_2d_grp0 += sprite_count;

    // second is the vector data
    u32 expected_vec_size = sizeof(SpriteVecData2d) * sprite_count;
    auto vec_data = dma.read_and_advance();
    ASSERT(expected_vec_size <= sizeof(m_vec_data_2d));
    unpack_to_no_stcycl(&m_vec_data_2d, vec_data, VifCode::Kind::UNPACK_V4_32, expected_vec_size,
                        SpriteDataMem::Vector, false, true);

    // third is the adgif data
    u32 expected_adgif_size = sizeof(AdGifData) * sprite_count;
    auto adgif_data = dma.read_and_advance();
    ASSERT(expected_adgif_size <= sizeof(m_adgif));
    unpack_to_no_stcycl(&m_adgif, adgif_data, VifCode::Kind::UNPACK_V4_32, expected_adgif_size,
                        SpriteDataMem::Adgif, false, true);

    // fourth is the actual run!!!!!
    auto run = dma.read_and_advance();
    ASSERT(run.vifcode0().kind == VifCode::Kind::NOP);
    ASSERT(run.vifcode1().kind == VifCode::Kind::MSCAL);

    if (m_enabled) {
      if (run.vifcode1().immediate != last_prog) {
        // one-time setups and flushing
        flush_sprites(render_state, prof, false);
      }

      if (run.vifcode1().immediate == SpriteProgMem::Sprites2dGrp0) {
        if (m_2d_enable) {
          do_block_common(SpriteMode::Mode2D, sprite_count, render_state, prof);
        }
      } else {
        if (m_3d_enable) {
          do_block_common(SpriteMode::Mode3D, sprite_count, render_state, prof);
        }
      }
      last_prog = run.vifcode1().immediate;
    }
  }
}

/*!
 * Run the pre-sprite directrenderer.
 */
bool Sprite3::render_direct(DmaFollower& dma,
                            SharedRenderState* render_state,
                            ScopedProfilerNode& prof) {
  m_direct.reset_state();
  while (dma.current_tag().qwc != 7 && dma.current_tag_offset() != render_state->next_bucket) {
    auto direct_data = dma.read_and_advance();
    m_direct.render_vif(direct_data.vif0(), direct_data.vif1(), direct_data.data,
                        direct_data.size_bytes, render_state, prof);
  }
  m_direct.flush_pending(render_state, prof);

  // if sprites are off, after all the directrenderer dma, there is nothing left and we must exit
  if (dma.current_tag_offset() == render_state->next_bucket) {
    return true;
  }
  return false;
}

void Sprite3::render_fake_shadow(DmaFollower& dma) {
  // TODO
  // nop + flushe
  auto nop_flushe = dma.read_and_advance();
  ASSERT(nop_flushe.vifcode0().kind == VifCode::Kind::NOP);
  ASSERT(nop_flushe.vifcode1().kind == VifCode::Kind::FLUSHE);
}

void Sprite3::set_group1_uniforms(GLuint shid, SpriteHudUniformCache& uh) {
  // Gperf-particles: cache group1 (HUD) per-frame uniform locations (stable per
  // linked program). The caller must have made `shid` the active program.
  if (shid != uh.prog) {
    uh.prog = shid;
    uh.hud_hvdf_offset = glGetUniformLocation(shid, "hud_hvdf_offset");
    uh.hud_hvdf_user = glGetUniformLocation(shid, "hud_hvdf_user");
    uh.hud_matrix = glGetUniformLocation(shid, "hud_matrix");
  }
  glUniform4fv(uh.hud_hvdf_offset, 1, m_hud_matrix_data.hvdf_offset.data());
  glUniform4fv(uh.hud_hvdf_user, 75, m_hud_matrix_data.user_hvdf[0].data());
  glUniformMatrix4fv(uh.hud_matrix, 1, GL_FALSE, m_hud_matrix_data.matrix.data());
}

/*!
 * Handle DMA data for group1 2d's (HUD)
 */
void Sprite3::render_2d_group1(DmaFollower& dma,
                               SharedRenderState* render_state,
                               ScopedProfilerNode& prof) {
  // one time matrix data upload
  auto mat_upload = dma.read_and_advance();
  bool mat_ok = verify_unpack_with_stcycl(mat_upload, VifCode::Kind::UNPACK_V4_32, 4, 4, 80,
                                          SpriteDataMem::Matrix, false, false);
  ASSERT(mat_ok);
  ASSERT(mat_upload.size_bytes == sizeof(m_hud_matrix_data));
  memcpy(&m_hud_matrix_data, mat_upload.data, sizeof(m_hud_matrix_data));

  // opengl sprite frame setup. SPRITE3 is the active program here; set its
  // per-frame group1 (HUD) uniforms.
  GLuint shid = render_state->shaders[ShaderId::SPRITE3].id();
  set_group1_uniforms(shid, m_sprite_hud_uniform_cache);

  // Gperf-particles round 2: mirror the HUD uniforms onto the instanced program.
  if (render_state->perf_sprite_instance && render_state->version == GameVersion::Jak1) {
    auto inst = render_state->shaders[ShaderId::SPRITE3_INSTANCED].id();
    glUseProgram(inst);
    set_group1_uniforms(inst, m_sprite_hud_uniform_cache_inst);
    glUseProgram(shid);
  }

  // loop through chunks.
  while (looks_like_2d_chunk_start(dma)) {
    m_debug_stats.blocks_2d_grp1++;
    // 4 packets per chunk

    // first is the header
    u32 sprite_count = process_sprite_chunk_header(dma);
    m_debug_stats.count_2d_grp1 += sprite_count;

    // second is the vector data
    u32 expected_vec_size = sizeof(SpriteVecData2d) * sprite_count;
    auto vec_data = dma.read_and_advance();
    ASSERT(expected_vec_size <= sizeof(m_vec_data_2d));
    unpack_to_no_stcycl(&m_vec_data_2d, vec_data, VifCode::Kind::UNPACK_V4_32, expected_vec_size,
                        SpriteDataMem::Vector, false, true);

    // third is the adgif data
    u32 expected_adgif_size = sizeof(AdGifData) * sprite_count;
    auto adgif_data = dma.read_and_advance();
    ASSERT(expected_adgif_size <= sizeof(m_adgif));
    unpack_to_no_stcycl(&m_adgif, adgif_data, VifCode::Kind::UNPACK_V4_32, expected_adgif_size,
                        SpriteDataMem::Adgif, false, true);

    // fourth is the actual run!!!!!
    auto run = dma.read_and_advance();
    ASSERT(run.vifcode0().kind == VifCode::Kind::NOP);
    ASSERT(run.vifcode1().kind == VifCode::Kind::MSCAL);

    switch (render_state->version) {
      case GameVersion::Jak1:
        ASSERT(run.vifcode1().immediate == SpriteProgMem::Sprites2dHud_Jak1);
        break;
      case GameVersion::Jak2:
        ASSERT(run.vifcode1().immediate == SpriteProgMem::Sprites2dHud_Jak2);
        break;
      case GameVersion::Jak3:
      case GameVersion::JakX:
        ASSERT_EQ_IMM(run.vifcode1().immediate, (int)SpriteProgMem::Sprites2dHud_Jak3);
        break;
      default:
        ASSERT_NOT_REACHED();
    }
    if (m_enabled && m_2d_enable) {
      do_block_common(SpriteMode::ModeHUD, sprite_count, render_state, prof);
    }
  }
}

void Sprite3::render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) {
  if (owner_sprite_probe()) {
    lg::info("HDR-OWNER-PATH lf={} renderer={} instanced={} supported_2d={} supported_3d=false",
             owner_sprite_lf(), m_name, render_state->perf_sprite_instance,
             render_state->perf_sprite_instance && render_state->version == GameVersion::Jak1);
  }
  switch (render_state->version) {
    case GameVersion::Jak1:
      render_jak1(dma, render_state, prof);
      break;
    case GameVersion::Jak2:
    case GameVersion::Jak3:
    case GameVersion::JakX:
      render_jak2(dma, render_state, prof);
      break;
    default:
      ASSERT_NOT_REACHED();
  }
}

void Sprite3::render_jak2(DmaFollower& dma,
                          SharedRenderState* render_state,
                          ScopedProfilerNode& prof) {
  m_debug_stats = {};
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif0() == 0 || data0.vifcode0().kind == VifCode::Kind::MARK);
  ASSERT(data0.vif1() == 0 || data0.vifcode1().kind == VifCode::Kind::NOP);
  ASSERT(data0.size_bytes == 0);

  if (dma.current_tag_offset() == render_state->next_bucket) {
    return;
  }

  // Before anything else, some directrenderer DMA might have been sent
  {
    auto child = prof.make_scoped_child("direct");
    if (render_direct(dma, render_state, child)) {
      return;
    }
  }

  // First is the distorter
  {
    auto child = prof.make_scoped_child("distorter");
    render_distorter(dma, render_state, child);
  }

  // next, the normal sprite stuff
  handle_sprite_frame_setup(dma, render_state->version, render_state, prof);

  // 3d sprites
  render_3d(dma);

  // 2d draw
  // m_sprite_renderer.reset_state();
  {
    auto child = prof.make_scoped_child("2d-group0");
    render_2d_group0(dma, render_state, child);
    flush_sprites(render_state, prof, false);
  }

  // shadow draw
  render_fake_shadow(dma);

  // 2d draw (HUD)
  {
    auto child = prof.make_scoped_child("2d-group1");
    render_2d_group1(dma, render_state, child);
    flush_sprites(render_state, prof, true);
    auto nop_flushe = dma.read_and_advance();
    ASSERT(nop_flushe.vifcode0().kind == VifCode::Kind::NOP);
    ASSERT(nop_flushe.vifcode1().kind == VifCode::Kind::FLUSHE);
  }

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glBlendEquation(GL_FUNC_ADD);

  {
    auto p = prof.make_scoped_child("glow");
    glow_dma_and_draw(dma, render_state, p);
  }

  // fmt::print("next bucket is 0x{}\n", render_state->next_bucket);
  while (dma.current_tag_offset() != render_state->next_bucket) {
    // auto tag = dma.current_tag();
    auto data = dma.read_and_advance();
    (void)data;
    // VifCode code(data.vif0());
    // fmt::print("@ 0x{:x} tag: {}", dma.current_tag_offset(), tag.print());
    // fmt::print(" vif0: {}\n", code.print());
    // fmt::print(" vif1: {}\n", VifCode(data.vif1()).print());
  }
}

void Sprite3::render_jak1(DmaFollower& dma,
                          SharedRenderState* render_state,
                          ScopedProfilerNode& prof) {
  m_debug_stats = {};
  owner_composition = {};
  // First thing should be a NEXT with two nops. this is a jump from buckets to sprite data
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0);
  ASSERT(data0.vif0() == 0);
  ASSERT(data0.size_bytes == 0);

  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // sprite renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return;
  }

  // Before anything else, some directrenderer DMA might have been sent
  {
    auto child = prof.make_scoped_child("direct");
    if (render_direct(dma, render_state, child)) {
      return;
    }
  }

  // First is the distorter
  {
    auto child = prof.make_scoped_child("distorter");
    render_distorter(dma, render_state, child);
  }

  // next, sprite frame setup.
  handle_sprite_frame_setup(dma, render_state->version, render_state, prof);

  // 3d sprites
  render_3d(dma);

  if (owner_sprite_probe()) {
    owner_composition.lf = owner_sprite_lf();
    owner_composition.rois[0].actor = 10012;
    owner_composition.rois[1].actor = 10013;
    owner_composition.rois[2].actor = 1395;
    owner_composition.rois[3].case_name = "sunset-sun";
    owner_composition.rois[3].layer = "sunset-sun";
    owner_composition.before = owner_composition_read();
    owner_composition.collecting = true;
  }

  // 2d draw
  // m_sprite_renderer.reset_state();
  {
    auto child = prof.make_scoped_child("2d-group0");
    render_2d_group0(dma, render_state, child);
    flush_sprites(render_state, prof, false);
  }

  if (owner_composition.collecting) {
    owner_composition.collecting = false;
    auto after = owner_composition_read();
    if (owner_composition.lf != owner_sprite_lf() ||
        after.framebuffer != owner_composition.before.framebuffer ||
        after.viewport != owner_composition.before.viewport) {
      after.status = "frame_or_target_changed_not_comparable";
      after.rgba.clear();
    }
    owner_composition_report(owner_composition, after);
    owner_composition.before.rgba.clear();
  }

  // shadow draw
  render_fake_shadow(dma);

  // Grender-split: everything above (pre-direct, distort, 3d, world-2d group0,
  // fake-shadow) is the 3D scene and is depth-/framebuffer-coupled to the scaled
  // scene FBO. The HUD group (group1) below is the LAST sprite sub-pass in jak1
  // and is pure 2D screen-space (matrix/hvdf-driven verts, no scene read), so it
  // can be drawn at native resolution. If the orchestrator armed the split, this
  // composites the scaled scene to the native UI FBO and re-targets there, leaving
  // the HUD/menu sprites crisp. No-op when the split is inactive.
  if (render_state->begin_2d_ui_pass) {
    render_state->begin_2d_ui_pass();
  }

  // 2d draw (HUD)
  {
    auto child = prof.make_scoped_child("2d-group1");
    render_2d_group1(dma, render_state, child);
    flush_sprites(render_state, prof, true);
  }

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glBlendEquation(GL_FUNC_ADD);

  // TODO finish this up.
  // fmt::print("next bucket is 0x{}\n", render_state->next_bucket);
  while (dma.current_tag_offset() != render_state->next_bucket) {
    //    auto tag = dma.current_tag();
    // fmt::print("@ 0x{:x} tag: {}", dma.current_tag_offset(), tag.print());
    auto data = dma.read_and_advance();
    VifCode code(data.vif0());
    // fmt::print(" vif0: {}\n", code.print());
    if (code.kind == VifCode::Kind::NOP) {
      // fmt::print(" vif1: {}\n", VifCode(data.vif1()).print());
    }
  }
}

void Sprite3::draw_debug_window() {
  ImGui::Checkbox("Glow", &m_enable_glow);
  ImGui::Checkbox("new glow", &m_glow_renderer.new_mode);
  ImGui::Separator();
  ImGui::Text("Distort sprites: %d", m_distort_stats.total_sprites);
  ImGui::Text("2D Group 0 (World) blocks: %d sprites: %d", m_debug_stats.blocks_2d_grp0,
              m_debug_stats.count_2d_grp0);
  ImGui::Text("2D Group 1 (HUD) blocks: %d sprites: %d", m_debug_stats.blocks_2d_grp1,
              m_debug_stats.count_2d_grp1);
  ImGui::Checkbox("Culling", &m_enable_culling);
  ImGui::Checkbox("2d", &m_2d_enable);
  ImGui::SameLine();
  ImGui::Checkbox("3d", &m_3d_enable);
  ImGui::Checkbox("Distort", &m_distort_enable);
  ImGui::Checkbox("Distort instancing", &m_enable_distort_instancing);
  ImGui::Separator();
  m_glow_renderer.draw_debug_window();
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Render (for real)

void Sprite3::flush_sprites(SharedRenderState* render_state,
                            ScopedProfilerNode& prof,
                            bool double_draw) {
  SpartScopedNs _flush_ns(g_spart_prof.gl_spr_flush);
  // Gperf-particles: submission-shape counters for the A35-SPART dump
  g_spart_prof.sprite_buckets.fetch_add(m_bucket_list.size(), std::memory_order_relaxed);
  g_spart_prof.sprite_quads.fetch_add(m_sprite_idx, std::memory_order_relaxed);

  // Gperf-particles round 2: per-instance draw path (jak1 Android). One 64B
  // record per sprite gathered per-bucket, one glBufferData, then one
  // glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, count) per bucket. The old
  // per-vertex + index-restart path (below) is used for every other version and
  // when the flag is off.
  if (render_state->perf_sprite_instance && render_state->version == GameVersion::Jak1) {
    flush_sprites_instanced(render_state, prof, double_draw);
    return;
  }


  if (owner_sprite_probe()) {
    lg::info("HDR-OWNER-FRAME lf={} instanced=false candidates=unknown supported=false reason=non_instanced",
             owner_sprite_lf());
  }

  // Gperf-particles: refresh cached SPRITE3 uniform locations on program change.
  {
    GLuint sprite_prog = render_state->shaders[ShaderId::SPRITE3].id();
    if (sprite_prog != m_sprite_uniform_cache.prog) {
      m_sprite_uniform_cache.prog = sprite_prog;
      m_sprite_uniform_cache.alpha_min = glGetUniformLocation(sprite_prog, "alpha_min");
      m_sprite_uniform_cache.alpha_max = glGetUniformLocation(sprite_prog, "alpha_max");
      m_sprite_uniform_cache.tex_T0 = glGetUniformLocation(sprite_prog, "tex_T0");
    }
  }
  const auto& su = m_sprite_uniform_cache;

  glBindVertexArray(m_ogl.vao);

#ifdef __ANDROID__
  // GLES: fixed-index restart (== UINT32_MAX for u32 indices); settable
  // restart index does not exist (same gate as TFragment/Merc2).
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif

  // upload vertex buffer
  glBindBuffer(GL_ARRAY_BUFFER, m_ogl.vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, m_sprite_idx * sizeof(SpriteVertex3D) * 4, m_vertices_3d.data(),
               GL_STREAM_DRAW);

  // two passes through the buckets. first to build the index buffer
  u32 idx_offset = 0;
  for (const auto bucket : m_bucket_list) {
    memcpy(&m_index_buffer_data[idx_offset], bucket->ids.data(), bucket->ids.size() * sizeof(u32));
    bucket->offset_in_idx_buffer = idx_offset;
    idx_offset += bucket->ids.size();
  }

  // now upload it
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_ogl.index_buffer);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_offset * sizeof(u32), m_index_buffer_data.data(),
               GL_STREAM_DRAW);

  // now do draws!
  for (const auto bucket : m_bucket_list) {
    u32 tbp = bucket->key >> 32;
    DrawMode mode;
    mode.as_int() = bucket->key & 0xffffffff;

    std::optional<u64> tex;
    tex = render_state->texture_pool->lookup(tbp);

    // fire-red-particles : l'etat de l'echantillonneur de CE dessin, au point de tirage.
    fire_red_census::note_sprite_sampler(tex.has_value());
    if (!tex) {
      lg::warn("Failed to find texture at {}, using random (sprite)", tbp);
      tex = render_state->texture_pool->get_placeholder_texture();
    }
    ASSERT(tex);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, *tex);

    auto settings = setup_opengl_from_draw_mode(mode, GL_TEXTURE0, false);

    glUniform1f(su.alpha_min, double_draw ? settings.aref_first : 0.016);
    glUniform1f(su.alpha_max, 10.f);
    glUniform1i(su.tex_T0, 0);

    // fire-red-particles : LE RECENSEMENT, AU POINT DE TIRAGE. On lit les enregistrements que
    // ce seau va REELLEMENT envoyer, avec le plancher d'alpha et le melange en vigueur pour
    // lui — pas un predicat sur la table source, qui ne dit pas ce qui est dessine.
    if (fire_red_census::armed()) {
      const auto fire_tex = render_state->texture_pool->get_debug_texture_name_from_tbp(tbp);
      const int fire_blend = (int)mode.get_alpha_blend();
      const bool fire_dd = double_draw && settings.kind == DoubleDrawKind::AFAIL_NO_DEPTH_WRITE;
      const float fire_amin = double_draw ? settings.aref_first : 0.016f;
      // Chemin a sommets : 5 identifiants par sprite (4 coins + le redemarrage de bande) ;
      // les 4 coins portent la meme couleur, on ne lit que le premier.
      for (size_t k = 0; k + 4 < bucket->ids.size(); k += 5) {
        const auto& fv = m_vertices_3d[bucket->ids[k]];
        fire_red_census::note_sprite(fire_tex.c_str(), fv.xyz_sx[0], fv.xyz_sx[1], fv.xyz_sx[2],
                                     fv.rgba[0], fv.rgba[1], fv.rgba[2], fv.rgba[3], fire_amin,
                                     fire_blend, fire_dd);
        // La TAILLE du quad, telle qu'elle part au tampon : rien ne la borne par le haut.
        fire_red_census::note_sprite_size(fire_tex.c_str(), fv.xyz_sx[3], fv.quat_sy[3]);
      }
    }

    prof.add_draw_call();
    prof.add_tri(2 * (bucket->ids.size() / 5));

    glDrawElements(GL_TRIANGLE_STRIP, bucket->ids.size(), GL_UNSIGNED_INT,
                   (void*)(bucket->offset_in_idx_buffer * sizeof(u32)));

    if (double_draw) {
      switch (settings.kind) {
        case DoubleDrawKind::NONE:
          break;
        case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE:
          prof.add_draw_call();
          prof.add_tri(2 * (bucket->ids.size() / 5));
          glUniform1f(su.alpha_min, -10.f);
          glUniform1f(su.alpha_max, settings.aref_second);
          glDepthMask(GL_FALSE);
          glDrawElements(GL_TRIANGLE_STRIP, bucket->ids.size(), GL_UNSIGNED_INT,
                         (void*)(bucket->offset_in_idx_buffer * sizeof(u32)));
          break;
        default:
          ASSERT(false);
      }
    }
  }

  if (render_state->perf_sprite_lean) {
    // Gperf-particles: keep the map nodes + each bucket's ids capacity across
    // flushes/frames — only clear the id lists. do_block_common re-lists a
    // bucket the first time it's touched this flush (ids.empty() rule), so the
    // persisted (but emptied) map entries don't leak into m_bucket_list.
    for (auto bucket : m_bucket_list) {
      bucket->ids.clear();
    }
  } else {
    m_sprite_buckets.clear();
  }
  m_bucket_list.clear();
  m_last_bucket_key = UINT64_MAX;
  m_last_bucket = nullptr;
  m_sprite_idx = 0;
  glBindVertexArray(0);
}

void Sprite3::flush_sprites_instanced(SharedRenderState* render_state,
                                      ScopedProfilerNode& prof,
                                      bool double_draw) {
  // Gperf-particles round 2: refresh cached alpha/tex uniform locations for the
  // SPRITE3_INSTANCED program (its own program object, own locations).
  GLuint inst_prog = render_state->shaders[ShaderId::SPRITE3_INSTANCED].id();
  if (inst_prog != m_sprite_uniform_cache_inst.prog) {
    m_sprite_uniform_cache_inst.prog = inst_prog;
    m_sprite_uniform_cache_inst.alpha_min = glGetUniformLocation(inst_prog, "alpha_min");
    m_sprite_uniform_cache_inst.alpha_max = glGetUniformLocation(inst_prog, "alpha_max");
    m_sprite_uniform_cache_inst.tex_T0 = glGetUniformLocation(inst_prog, "tex_T0");
  }
  const auto& su = m_sprite_uniform_cache_inst;

  glBindVertexArray(m_ogl.instance_vao);

  // gather pass: copy each bucket's sprite records (by id) into contiguous draw
  // order, recording each bucket's [instance_offset, instance_count).
  m_instance_scratch.clear();
  u32 total = 0;
  for (const auto bucket : m_bucket_list) {
    bucket->instance_offset = total;
    bucket->instance_count = (u32)bucket->ids.size();
    for (u32 id : bucket->ids) {
      m_instance_scratch.push_back(m_vertices_3d[id]);
    }
    total += bucket->instance_count;
  }

  // one upload of all instance records for this flush.
  glBindBuffer(GL_ARRAY_BUFFER, m_ogl.instance_buffer);
  glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)total * sizeof(SpriteVertex3D),
               m_instance_scratch.data(), GL_STREAM_DRAW);

  // the SPRITE3_INSTANCED program's per-frame uniforms were already set (with
  // its own cache) by render_2d_group0 / render_2d_group1; make it active.
  glUseProgram(inst_prog);

  const bool probe = owner_sprite_probe();
  u32 candidate_count = 0;
  GLint query_busy = 0;
  if (probe) {
    GLint active = 0;
    glGetQueryiv(GL_ANY_SAMPLES_PASSED, GL_CURRENT_QUERY, &query_busy);
    glGetQueryiv(GL_ANY_SAMPLES_PASSED_CONSERVATIVE, GL_CURRENT_QUERY, &active);
    query_busy |= active;
#ifndef __ANDROID__
    glGetQueryiv(GL_SAMPLES_PASSED, GL_CURRENT_QUERY, &active);
    query_busy |= active;
#endif
  }

  for (const auto bucket : m_bucket_list) {
    u32 tbp = bucket->key >> 32;
    DrawMode mode;
    mode.as_int() = bucket->key & 0xffffffff;

    std::optional<u64> tex;
    tex = render_state->texture_pool->lookup(tbp);

    // fire-red-particles : l'etat de l'echantillonneur de CE dessin, au point de tirage.
    fire_red_census::note_sprite_sampler(tex.has_value());
    if (!tex) {
      lg::warn("Failed to find texture at {}, using random (sprite)", tbp);
      tex = render_state->texture_pool->get_placeholder_texture();
    }
    ASSERT(tex);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, *tex);

    auto settings = setup_opengl_from_draw_mode(mode, GL_TEXTURE0, false);

    glUniform1f(su.alpha_min, double_draw ? settings.aref_first : 0.016);
    glUniform1f(su.alpha_max, 10.f);
    glUniform1i(su.tex_T0, 0);

    // fire-red-particles : LE RECENSEMENT, AU POINT DE TIRAGE. On lit les enregistrements que
    // ce seau va REELLEMENT envoyer, avec le plancher d'alpha et le melange en vigueur pour
    // lui — pas un predicat sur la table source, qui ne dit pas ce qui est dessine.
    if (fire_red_census::armed()) {
      const auto fire_tex = render_state->texture_pool->get_debug_texture_name_from_tbp(tbp);
      const int fire_blend = (int)mode.get_alpha_blend();
      const bool fire_dd = double_draw && settings.kind == DoubleDrawKind::AFAIL_NO_DEPTH_WRITE;
      const float fire_amin = double_draw ? settings.aref_first : 0.016f;
      // Chemin instancie (jak1 Android par defaut) : un enregistrement par sprite, compacte
      // par seau dans m_instance_scratch.
      for (u32 k = bucket->instance_offset; k < bucket->instance_offset + bucket->instance_count;
           ++k) {
        const auto& fv = m_instance_scratch[k];
        fire_red_census::note_sprite(fire_tex.c_str(), fv.xyz_sx[0], fv.xyz_sx[1], fv.xyz_sx[2],
                                     fv.rgba[0], fv.rgba[1], fv.rgba[2], fv.rgba[3], fire_amin,
                                     fire_blend, fire_dd);
        // La TAILLE du quad, telle qu'elle part au tampon : rien ne la borne par le haut.
        fire_red_census::note_sprite_size(fire_tex.c_str(), fv.xyz_sx[3], fv.quat_sy[3]);
      }
    }

    auto draw_range = [&](u32 offset, u32 count) {
      const u8* base = (const u8*)(uintptr_t)(offset * sizeof(SpriteVertex3D));
      glVertexAttribPointer(0, 4, GL_FLOAT, GL_TRUE, sizeof(SpriteVertex3D),
                            base + offsetof(SpriteVertex3D, xyz_sx));
      glVertexAttribPointer(1, 4, GL_FLOAT, GL_TRUE, sizeof(SpriteVertex3D),
                            base + offsetof(SpriteVertex3D, quat_sy));
      glVertexAttribPointer(2, 4, GL_FLOAT, GL_TRUE, sizeof(SpriteVertex3D),
                            base + offsetof(SpriteVertex3D, rgba));
      glVertexAttribIPointer(3, 2, GL_UNSIGNED_SHORT, sizeof(SpriteVertex3D),
                             base + offsetof(SpriteVertex3D, flags_matrix));
      glVertexAttribIPointer(4, 4, GL_UNSIGNED_SHORT, sizeof(SpriteVertex3D),
                             base + offsetof(SpriteVertex3D, info));

      prof.add_draw_call();
      prof.add_tri(2 * count);
      glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, count);
    };

    if (!probe) {
      draw_range(bucket->instance_offset, bucket->instance_count);
    } else {
      const auto texture = render_state->texture_pool->get_debug_texture_name_from_tbp(tbp);
      // Debug names may include the tpage; delimit tokens to avoid matching unrelated names.
      auto has_texture = [&](const std::string& name) {
        auto pos = texture.find(name);
        while (pos != std::string::npos) {
          auto word = [](char c) {
            return std::isalnum(static_cast<unsigned char>(c)) || c == '_';
          };
          if ((!pos || !word(texture[pos - 1])) &&
              (pos + name.size() == texture.size() || !word(texture[pos + name.size()])))
            return true;
          pos = texture.find(name, pos + 1);
        }
        return false;
      };
      const bool eco = has_texture("lightning") || has_texture("lightning2") ||
                       has_texture("lightning3") || has_texture("starflash") ||
                       has_texture("bigpuff") || has_texture("hotdot");
      const bool portal_disc = has_texture("harddot");
      const bool portal = has_texture("bigpuff") || has_texture("middot") ||
                          has_texture("hotdot") || portal_disc;
      const bool sun_texture = has_texture("middot") || has_texture("starflash2");
      const auto camera_m = render_state->camera_pos / 4096.f;
      const auto& sun_direction = Gfx::g_global_settings.recharged_pbr_sky_sun;
      // At the 9950 m sun orbit, 0.05 m covers float rounding (about 0.001 m/ULP)
      // and remains fixed: a temporal mismatch never widens an unmatched region.
      constexpr double sun_tolerance_m = 0.05;
      u32 sun_candidates = 0, sun_matches = 0;
      float nearest_sun_error2 = INFINITY;
      std::array<float, 3> nearest_sun_world{};
      u32 pending = bucket->instance_offset;
      const u32 end = pending + bucket->instance_count;
      for (u32 i = pending; i < end && (eco || portal || sun_texture); ++i) {
        const auto& v = m_instance_scratch[i];
        if (v.info[3] != 1 && v.info[3] != 3)
          continue;  // HUD has no world anchor.
        const math::Vector4f world = v.xyz_sx / 4096.f;
        int actor = 0;
        float distance2 = 0.f;
        const float anchors[3][4] = {{9.3109f, 19.2490f, 11.2525f, 10012.f},
                                     {6.6918f, 19.3725f, 20.4516f, 10013.f},
                                     {-123.10158f, 50.40380f, 214.22531f, 1395.f}};
        for (int a = 0; a < 3; ++a) {
          if ((a < 2 && !eco) || (a == 2 && !portal))
            continue;
          float d2 = 0;
          for (int k = 0; k < 3; ++k) {
            const float delta = world[k] - anchors[a][k];
            d2 += delta * delta;
          }
          const float radius = a < 2 ? 1.73205f : 8.f;
          if (std::isfinite(d2) && d2 <= radius * radius) {
            actor = int(anchors[a][3]);
            distance2 = d2;
            break;
          }
        }
        bool sun = false;
        if (sun_texture) {
          ++sun_candidates;
          float d2 = 0.f;
          for (int k = 0; k < 3; ++k) {
            const float delta = world[k] - (camera_m[k] + sun_direction[k]);
            d2 += delta * delta;
          }
          if (std::isfinite(d2) && d2 < nearest_sun_error2) {
            nearest_sun_error2 = d2;
            nearest_sun_world = {world[0], world[1], world[2]};
          }
          sun = !actor && std::isfinite(d2) && d2 <= sun_tolerance_m * sun_tolerance_m;
          if (sun) {
            distance2 = d2;
            ++sun_matches;
          }
        }
        if (!actor && !sun)
          continue;
        ++candidate_count;
        nlohmann::json event = {{"lf", owner_sprite_lf()},
                                {"actor", actor},
                                {"association", "texture_and_anchor_distance"},
                                {"texture", texture},
                                {"position_m", {world[0], world[1], world[2]}},
                                {"mode_bits", mode.as_int()},
                                // Vertex modulation bounds, before texture and area fade.
                                {"rgba_vertex", {v.rgba[0], v.rgba[1], v.rgba[2], v.rgba[3]}},
                                {"rgb_modulate_max", {2.f * v.rgba[0], 2.f * v.rgba[1],
                                                      2.f * v.rgba[2]}},
                                {"alpha_modulate_max", 4.f * v.rgba[3]},
                                {"render_mode", v.info[3]},
                                {"distance_m", std::sqrt(distance2)},
                                {"group_1m", (actor == 10012 || actor == 10013) && distance2 <= 1.f},
                                {"roi", nullptr},
                                {"roi_bounds", "exclusive_top_left_320x180"},
                                {"passed", nullptr},
                                {"supported", false},
                                {"reason", "unsupported_3d"}};
        if (sun) {
          event["case"] = "sunset-sun";
          event["layer"] = "sunset-sun";
          event["association"] = "texture_and_sun_position";
          event["sun_direction"] = {sun_direction[0], sun_direction[1], sun_direction[2]};
          event["camera_m"] = {camera_m[0], camera_m[1], camera_m[2]};
          event["association_error_m"] = std::sqrt(distance2);
          event["association_tolerance_m"] = sun_tolerance_m;
          event["scale_x_goal"] = v.xyz_sx[3];
          event["scale_y_goal"] = v.quat_sy[3];
          event["rotation_z"] = v.quat_sy[2];
        }
        if (actor == 1395 && portal_disc && v.info[3] == 3)
          event["layer"] = "portal_disc";
        bool projected = false;
        if (v.info[3] == 1) {
          // Mirror sprite3_3d_inst.vert's 2D branch, including its PS2 viewport conversion.
          auto pos = v.xyz_sx;
          pos[3] = 1.f;
          auto transformed = m_3d_matrix_data.camera * pos;
          event["camera_w"] = transformed[3];
          event["pfog0"] = m_frame_data.pfog0;
          // The sprite shader divides by the signed camera w, then adds hvdf
          // and clamps the final w. Its input w is not a clip-space near-plane test.
          if (std::isfinite(transformed[3]) && transformed[3] != 0.f &&
              (v.flags_matrix[0] & 15u) + 3u < 8u) {
            const float q = m_frame_data.pfog0 / transformed[3];
            const float sx =
                std::clamp(v.xyz_sx[3] * q, m_frame_data.min_scale, m_frame_data.max_scale);
            const float sy =
                std::clamp(v.quat_sy[3] * q, m_frame_data.min_scale, m_frame_data.max_scale);
            for (int k = 0; k < 3; ++k)
              transformed[k] *= q;
            transformed += m_3d_matrix_data.hvdf_offset;
            transformed[3] = std::max(transformed[3], m_frame_data.fog_min);
            event["quad_w"] = transformed[3];
            const float angle = v.quat_sy[2] * m_frame_data.deg_to_rad;
            const auto bx =
                (m_frame_data.basis_x * std::cos(angle) - m_frame_data.basis_y * std::sin(angle)) *
                sx;
            const auto by =
                (m_frame_data.basis_x * std::sin(angle) + m_frame_data.basis_y * std::cos(angle)) *
                sy;
            float lo_x = INFINITY, lo_y = INFINITY, hi_x = -INFINITY, hi_y = -INFINITY;
            projected = true;
            for (int corner : {0, 1, 3, 2}) {
              const auto& xy = m_frame_data.xy_array[corner + (v.flags_matrix[0] & 15u)];
              const auto p = transformed + bx * xy[0] + by * xy[1];
              const float x = ((p[0] - 2048.f) / 256.f + 1.f) * 160.f;
              const float y = (1.f + (p[1] - 2048.f) / 128.f * (512.f / 448.f)) * 90.f;
              if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(p[2]) ||
                  !std::isfinite(p[3]) || p[3] <= 0.f) {
                projected = false;
                break;
              }
              lo_x = std::min(lo_x, x);
              lo_y = std::min(lo_y, y);
              hi_x = std::max(hi_x, x);
              hi_y = std::max(hi_y, y);
            }
            if (projected)
              event["roi"] = {int(std::floor(std::clamp(lo_x, 0.f, 320.f))),
                              int(std::floor(std::clamp(lo_y, 0.f, 180.f))),
                              int(std::ceil(std::clamp(hi_x, 0.f, 320.f))),
                              int(std::ceil(std::clamp(hi_y, 0.f, 180.f)))};
          }
          event["reason"] = projected ? "ok" : "invalid_projection";
        } else if (v.info[3] == 3) {
          // Mirror sprite_quat_to_rot / sprite_transform2, including the negated camera
          // transform. Unlike mode 1, mode 3 neither adds hvdf.w nor clamps scale or w.
          const float qx = v.quat_sy[0], qy = v.quat_sy[1], qz = v.quat_sy[2];
          const float qr = std::sqrt(std::abs(1.f - (qx * qx + qy * qy + qz * qz)));
          // GLSL mat3 indexing is column first; these are its three columns.
          const float rot[3][3] = {
              {1.f - 2.f * (qy * qy + qz * qz), 2.f * (qx * qy + qz * qr),
               2.f * (qx * qz - qy * qr)},
              {2.f * (qx * qy - qz * qr), 1.f - 2.f * (qx * qx + qz * qz),
               2.f * (qy * qz + qx * qr)},
              {2.f * (qx * qz + qy * qr), 2.f * (qy * qz - qx * qr),
               1.f - 2.f * (qx * qx + qy * qy)}};
          float lo_x = INFINITY, lo_y = INFINITY, hi_x = -INFINITY, hi_y = -INFINITY;
          projected = true;
          event["corner_w"] = nlohmann::json::array();
          for (int corner : {0, 1, 3, 2}) {
            const auto& off = m_frame_data.xyz_array[corner];
            auto pos = v.xyz_sx;
            pos[3] = 1.f;
            for (int k = 0; k < 3; ++k)
              pos[k] += rot[0][k] * off[0] * v.xyz_sx[3] + rot[1][k] * off[1] +
                        rot[2][k] * off[2] * v.quat_sy[3];
            auto p = (m_3d_matrix_data.camera * pos) * -1.f;
            event["corner_w"].push_back(p[3]);
            // A quad crossing w=0 needs polygon clipping; leave it explicitly unsupported.
            if (!std::isfinite(p[3]) || p[3] <= 0.f) {
              projected = false;
              break;
            }
            const float q = m_frame_data.pfog0 / p[3];
            for (int k = 0; k < 3; ++k)
              p[k] = p[k] * q + m_3d_matrix_data.hvdf_offset[k];
            // The final shader multiplies xyz by w; perspective division cancels it.
            const float x = ((p[0] - 2048.f) / 256.f + 1.f) * 160.f;
            const float y = (1.f + (p[1] - 2048.f) / 128.f * (512.f / 448.f)) * 90.f;
            if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(p[2])) {
              projected = false;
              break;
            }
            lo_x = std::min(lo_x, x);
            lo_y = std::min(lo_y, y);
            hi_x = std::max(hi_x, x);
            hi_y = std::max(hi_y, y);
          }
          if (projected)
            event["roi"] = {int(std::floor(std::clamp(lo_x, 0.f, 320.f))),
                            int(std::floor(std::clamp(lo_y, 0.f, 180.f))),
                            int(std::ceil(std::clamp(hi_x, 0.f, 320.f))),
                            int(std::ceil(std::clamp(hi_y, 0.f, 180.f)))};
          event["reason"] = projected ? "ok" : "invalid_projection";
        }
        if (double_draw)
          event["reason"] = "double_draw";
        else if (query_busy)
          event["reason"] = "query_busy";
        else {
          // Preserve every instance's order; only candidate draws acquire a query.
          if (i > pending)
            draw_range(pending, i - pending);
          GLuint query = 0, passed = 0;
          glGenQueries(1, &query);
          glBeginQuery(GL_ANY_SAMPLES_PASSED, query);
          draw_range(i, 1);
          glEndQuery(GL_ANY_SAMPLES_PASSED);
          glGetQueryObjectuiv(query, GL_QUERY_RESULT, &passed);
          glDeleteQueries(1, &query);
          event["passed"] = passed != 0;
          event["supported"] = projected;
          pending = i + 1;
        }
        owner_composition_roi(owner_composition, event);
        lg::info("HDR-OWNER-SPRITE {}", event.dump());
      }
      if (pending < end)
        draw_range(pending, end - pending);
      if (sun_texture) {
        const nlohmann::json association = {
            {"lf", owner_sprite_lf()},
            {"texture", texture},
            {"tbp", tbp},
            {"candidate_count", sun_candidates},
            {"matched_count", sun_matches},
            {"min_association_error_m", std::isfinite(nearest_sun_error2)
                                            ? nlohmann::json(std::sqrt(nearest_sun_error2))
                                            : nlohmann::json(nullptr)},
            {"nearest_world_m", std::isfinite(nearest_sun_error2)
                                    ? nlohmann::json(nearest_sun_world)
                                    : nlohmann::json(nullptr)},
            {"camera_m", {camera_m[0], camera_m[1], camera_m[2]}},
            {"sun_direction", {sun_direction[0], sun_direction[1], sun_direction[2]}},
            {"association_tolerance_m", sun_tolerance_m}};
        lg::info("HDR-OWNER-SUN-ASSOCIATION {}", association.dump());
      }
    }

    if (double_draw) {
      switch (settings.kind) {
        case DoubleDrawKind::NONE:
          break;
        case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE:
          prof.add_draw_call();
          prof.add_tri(2 * bucket->instance_count);
          glUniform1f(su.alpha_min, -10.f);
          glUniform1f(su.alpha_max, settings.aref_second);
          glDepthMask(GL_FALSE);
          glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, bucket->instance_count);
          break;
        default:
          ASSERT(false);
      }
    }
  }

  if (probe) {
    lg::info("HDR-OWNER-FRAME lf={} instanced=true candidates={} double_draw={}", owner_sprite_lf(),
             candidate_count, double_draw);
  }

  // restore the SPRITE3 program so later passes (that assume it active) are
  // unaffected; the caller re-activates as needed anyway.
  glUseProgram(render_state->shaders[ShaderId::SPRITE3].id());

  if (render_state->perf_sprite_lean) {
    for (auto bucket : m_bucket_list) {
      bucket->ids.clear();
    }
  } else {
    m_sprite_buckets.clear();
  }
  m_bucket_list.clear();
  m_last_bucket_key = UINT64_MAX;
  m_last_bucket = nullptr;
  m_sprite_idx = 0;
  glBindVertexArray(0);
}

void Sprite3::handle_tex0(u64 val,
                          SharedRenderState* /*render_state*/,
                          ScopedProfilerNode& /*prof*/) {
  GsTex0 reg(val);

  // update tbp
  m_current_tbp = reg.tbp0();
  m_current_mode.set_tcc(reg.tcc());

  // tbw: assume they got it right
  // psm: assume they got it right
  // tw: assume they got it right
  // th: assume they got it right

  ASSERT(reg.tfx() == GsTex0::TextureFunction::MODULATE);
  ASSERT(reg.psm() != GsTex0::PSM::PSMT4HH);

  // cbp: assume they got it right
  // cpsm: assume they got it right
  // csm: assume they got it right
}

void Sprite3::handle_tex1(u64 val,
                          SharedRenderState* /*render_state*/,
                          ScopedProfilerNode& /*prof*/) {
  GsTex1 reg(val);
  m_current_mode.set_filt_enable(reg.mmag());
}

void Sprite3::handle_zbuf(u64 val,
                          SharedRenderState* /*render_state*/,
                          ScopedProfilerNode& /*prof*/) {
  // note: we can basically ignore this. There's a single z buffer that's always configured the same
  // way - 24-bit, at offset 448.
  GsZbuf x(val);
  ASSERT(x.psm() == TextureFormat::PSMZ24);
  ASSERT(x.zbp() == 448 || x.zbp() == 304);  // 304 for jak 2.

  m_current_mode.set_depth_write_enable(!x.zmsk());
}

void Sprite3::handle_clamp(u64 val,
                           SharedRenderState* /*render_state*/,
                           ScopedProfilerNode& /*prof*/) {
  if (!(val == 0b101 || val == 0 || val == 1 || val == 0b100)) {
    ASSERT_MSG(false, fmt::format("clamp: 0x{:x}", val));
  }

  m_current_mode.set_clamp_s_enable(val & 0b001);
  m_current_mode.set_clamp_t_enable(val & 0b100);
}

void Sprite3::update_mode_from_alpha1(u64 val, DrawMode& mode) {
  GsAlpha reg(val);
  if (reg.a_mode() == GsAlpha::BlendMode::SOURCE && reg.b_mode() == GsAlpha::BlendMode::DEST &&
      reg.c_mode() == GsAlpha::BlendMode::SOURCE && reg.d_mode() == GsAlpha::BlendMode::DEST) {
    // (Cs - Cd) * As + Cd
    // Cs * As  + (1 - As) * Cd
    mode.set_alpha_blend(DrawMode::AlphaBlend::SRC_DST_SRC_DST);

  } else if (reg.a_mode() == GsAlpha::BlendMode::SOURCE &&
             reg.b_mode() == GsAlpha::BlendMode::ZERO_OR_FIXED &&
             reg.c_mode() == GsAlpha::BlendMode::SOURCE &&
             reg.d_mode() == GsAlpha::BlendMode::DEST) {
    // (Cs - 0) * As + Cd
    // Cs * As + (1) * CD
    mode.set_alpha_blend(DrawMode::AlphaBlend::SRC_0_SRC_DST);
  } else if (reg.a_mode() == GsAlpha::BlendMode::SOURCE &&
             reg.b_mode() == GsAlpha::BlendMode::ZERO_OR_FIXED &&
             reg.c_mode() == GsAlpha::BlendMode::ZERO_OR_FIXED &&
             reg.d_mode() == GsAlpha::BlendMode::DEST) {
    ASSERT(reg.fix() == 128);
    // Cv = (Cs - 0) * FIX + Cd
    // if fix = 128, it works out to 1.0
    mode.set_alpha_blend(DrawMode::AlphaBlend::SRC_0_FIX_DST);
    // src plus dest
  } else if (reg.a_mode() == GsAlpha::BlendMode::SOURCE &&
             reg.b_mode() == GsAlpha::BlendMode::DEST &&
             reg.c_mode() == GsAlpha::BlendMode::ZERO_OR_FIXED &&
             reg.d_mode() == GsAlpha::BlendMode::DEST) {
    // Cv = (Cs - Cd) * FIX + Cd
    ASSERT(reg.fix() == 64);
    mode.set_alpha_blend(DrawMode::AlphaBlend::SRC_DST_FIX_DST);
  } else if (reg.a_mode() == GsAlpha::BlendMode::ZERO_OR_FIXED &&
             reg.b_mode() == GsAlpha::BlendMode::SOURCE &&
             reg.c_mode() == GsAlpha::BlendMode::SOURCE &&
             reg.d_mode() == GsAlpha::BlendMode::DEST) {
    // (0 - Cs) * As + Cd
    // Cd - Cs * As
    // s, d
    mode.set_alpha_blend(DrawMode::AlphaBlend::ZERO_SRC_SRC_DST);
  }

  else {
    lg::error("unsupported blend: a {} b {} c {} d {}", (int)reg.a_mode(), (int)reg.b_mode(),
              (int)reg.c_mode(), (int)reg.d_mode());
    mode.set_alpha_blend(DrawMode::AlphaBlend::SRC_DST_SRC_DST);
    ASSERT(false);
  }
}

void Sprite3::handle_alpha(u64 val,
                           SharedRenderState* /*render_state*/,
                           ScopedProfilerNode& /*prof*/) {
  update_mode_from_alpha1(val, m_current_mode);
}

void Sprite3::do_block_common(SpriteMode mode,
                              u32 count,
                              SharedRenderState* render_state,
                              ScopedProfilerNode& prof) {
  SpartScopedNs _build_ns(g_spart_prof.gl_spr_build);
  m_current_mode = m_default_mode;
  for (u32 sprite_idx = 0; sprite_idx < count; sprite_idx++) {
    if (m_sprite_idx == SPRITE_RENDERER_MAX_SPRITES) {
      flush_sprites(render_state, prof, mode == ModeHUD);
    }

    if (mode == Mode2D && render_state->has_pc_data && m_enable_culling) {
      // we can skip sprites that are out of view
      // it's probably possible to do this for 3D as well.
      auto bsphere = m_vec_data_2d[sprite_idx].xyz_sx;
      bsphere.w() = std::max(bsphere.w(), m_vec_data_2d[sprite_idx].sy());
      if (bsphere.w() == 0 || !sphere_in_view_ref(bsphere, render_state->camera_planes)) {
        // Geco-spheres TEMPORARY diagnostic: log culled eco-signature sprites.
        if (geco_spr3_dump_armed()) {
          static int s_cull = 0;
          auto& col = m_vec_data_2d[sprite_idx].rgba;
          bool eco = col.z() == 0.f && col.y() >= 100.f;
          if (eco && s_cull < 2000) {
            s_cull++;
            printf("SPR3-CULL col=%.0f,%.0f,%.0f,%.0f w=%.1f xyz=%.0f,%.0f,%.0f\n", col.x(),
                   col.y(), col.z(), col.w(), bsphere.w(), bsphere.x(), bsphere.y(), bsphere.z());
            fflush(stdout);
          }
        }
        continue;
      }
    }

    if (render_state->version > GameVersion::Jak1) {
      // glow code sets the matrix to -1,
      // jak 2 adds:
      // ibltz vi08, L4
      // which is set from ilw.y vi08, 1(vi02)
      if (m_vec_data_2d[sprite_idx].matrix() == -1) {
        continue;
      }
    }

    auto& adgif = m_adgif[sprite_idx];
    // GORB-ICON: skip a 2D sprite whose adgif block was stomped by the arm64
    // bone-ref overrun. Drawing the Precursor-orb HUD/menu icon routes through
    // generic-merc (bones.gc draw-bones-hud -> draw-bones-generic-merc); on
    // arm64 the bone-ref dma-tag packing at bones.gc:1124-1128 (`shl (the-as
    // int ptr) 32` — the source itself flags "does this work correctly for the
    // upper 64 bits??") writes low-heap pointer pairs (high32 == a heap
    // pointer, e.g. 0x17fd64) past the bone region into the adjacent
    // *sprite-array-2d* object, stomping one sprite's adgif. A valid CLAMP/ZBUF
    // register's high 32 bits are zero; a stomped one carries a heap pointer
    // (>= HEAP_START). Skipping that single corrupt sprite keeps the 2D chain +
    // the orb's own draw rendering instead of aborting in the GS decoders.
    // (bones.gc is goal_src 1-to-1 locked; this is the translation-layer guard.)
    // The CLAMP/ZBUF register's high 32 bits are ~0 when valid; a stomped adgif
    // carries a heap pointer there. (tex0's high bits can legitimately hold a
    // large clut base, so only the clamp field is a safe tell.)
    constexpr u64 kGorbHeapStart = 0x13fd20;  // game/kernel/common/memory_layout.h HEAP_START
    if ((adgif.clamp_data >> 32) >= kGorbHeapStart) {
      // Geco-spheres TEMPORARY diagnostic: log every sprite the GORB stomp-guard
      // drops (color + clamp high bits + tex0) — are the missing eco clouds here?
      if (geco_spr3_dump_armed()) {
        static int s_skip = 0;
        if (s_skip < 4000) {
          s_skip++;
          auto& col = m_vec_data_2d[sprite_idx].rgba;
          printf("SPR3-GORBSKIP col=%.0f,%.0f,%.0f,%.0f clamphi=%llx tex0=%llx mode=%d\n",
                 col.x(), col.y(), col.z(), col.w(),
                 (unsigned long long)(adgif.clamp_data >> 32),
                 (unsigned long long)adgif.tex0_data, (int)mode);
          fflush(stdout);
        }
      }
      continue;
    }
    handle_tex0(adgif.tex0_data, render_state, prof);
    handle_tex1(adgif.tex1_data, render_state, prof);
    if (GsRegisterAddress(adgif.clamp_addr) == GsRegisterAddress::ZBUF_1) {
      handle_zbuf(adgif.clamp_data, render_state, prof);
    } else {
      handle_clamp(adgif.clamp_data, render_state, prof);
    }
    handle_alpha(adgif.alpha_data, render_state, prof);

    u64 key = (((u64)m_current_tbp) << 32) | m_current_mode.as_int();
    Bucket* bucket;
    if (key == m_last_bucket_key) {
      bucket = m_last_bucket;
    } else {
      auto it = m_sprite_buckets.find(key);
      if (it == m_sprite_buckets.end()) {
        bucket = &m_sprite_buckets[key];
        bucket->key = key;
      } else {
        bucket = &it->second;
      }
    }
    // Gperf-particles: list a bucket the first time it's touched this flush.
    // Flag-off: m_sprite_buckets is cleared each flush, so a fresh map node has
    // empty ids (== push, as before) and any re-hit has >=5 ids (== not pushed,
    // as before). Flag-on: persisted-but-emptied nodes are re-listed here on
    // first touch. First-touch order == m_bucket_list order in both states.
    if (bucket->ids.empty()) {
      m_bucket_list.push_back(bucket);
    }

    // Gperf-particles round 2: per-instance path (jak1 only) writes ONE 64B
    // record per sprite and pushes ONE id (no 4 corners, no UINT32_MAX restart)
    // — the shader derives the corners from gl_VertexID. jak1 has no jak3
    // corner-swap flags, so the corner-swap block below is skipped in this mode.
    const bool instanced =
        render_state->perf_sprite_instance && render_state->version == GameVersion::Jak1;

    SpriteVertex3D* vtx;
    if (instanced) {
      // one record per sprite, id == the sprite index
      bucket->ids.push_back(m_sprite_idx);
      vtx = &m_vertices_3d[m_sprite_idx];
    } else {
      u32 start_vtx_id = m_sprite_idx * 4;
      bucket->ids.push_back(start_vtx_id);
      bucket->ids.push_back(start_vtx_id + 1);
      bucket->ids.push_back(start_vtx_id + 2);
      bucket->ids.push_back(start_vtx_id + 3);
      bucket->ids.push_back(UINT32_MAX);

      // Gperf-particles: the SPRITE_RENDERER_MAX_SPRITES flush check at the top
      // of this loop guarantees m_sprite_idx (== start_vtx_id/4) is in range, so
      // the 4 corner writes are safe without per-access bounds checks.
      vtx = &m_vertices_3d[m_sprite_idx * 4];
    }
    auto& vert1 = vtx[0];

    if (render_state->version == GameVersion::Jak3 || render_state->version == GameVersion::JakX) {
      auto flag = m_vec_data_2d[sprite_idx].flag();

      if ((flag & 0x10) || (flag & 0x20)) {
        // these flags mean we need to swap vertex order around - not yet implemented since it's too
        // hard to get right without this code running.
        // ASSERT_NOT_REACHED();
      }
    }

    vert1.xyz_sx = m_vec_data_2d[sprite_idx].xyz_sx;
    vert1.quat_sy = m_vec_data_2d[sprite_idx].flag_rot_sy;
    // ftoi'd in the original game, and I believe the VIF would discard the upper bits on pack
    vert1.rgba = m_vec_data_2d[sprite_idx].rgba;
    vert1.rgba.x() = (int)vert1.rgba.x() & 0xff;
    vert1.rgba.y() = (int)vert1.rgba.y() & 0xff;
    vert1.rgba.z() = (int)vert1.rgba.z() & 0xff;
    vert1.rgba.w() = (int)vert1.rgba.w() & 0xff;
    // fire-red-particles : L'ORACLE DE LA COULEUR, au point d'empaquetage. On donne au
    // recensement la couleur SOURCE que GOAL a ecrite et les quatre octets REELLEMENT ecrits
    // dans le sommet ; il calcule a part la reference (saturation) et compte les ecarts. Le nom
    // de l'emetteur est memoise par tbp : les sprites arrivent groupes par adgif.
    if (fire_red_census::armed()) {
      if (m_current_tbp != m_fire_pack_tbp) {
        m_fire_pack_tbp = m_current_tbp;
        m_fire_pack_tex =
            render_state->texture_pool->get_debug_texture_name_from_tbp(m_current_tbp);
      }
      const auto& fsrc = m_vec_data_2d[sprite_idx].rgba;
      fire_red_census::note_pack(m_fire_pack_tex.c_str(), mode == ModeHUD, fsrc.x(), fsrc.y(),
                                 fsrc.z(), fsrc.w(),
                                 (int)vert1.rgba.x(), (int)vert1.rgba.y(), (int)vert1.rgba.z(),
                                 (int)vert1.rgba.w());
    }
    vert1.rgba /= 255;
    vert1.flags_matrix[0] = m_vec_data_2d[sprite_idx].flag();
    vert1.flags_matrix[1] = m_vec_data_2d[sprite_idx].matrix();
    vert1.info[0] = 0;  // hack
    vert1.info[1] = m_current_mode.get_tcc_enable();
    vert1.info[2] = 0;
    vert1.info[3] = mode;

    if (instanced) {
      // one record only; corners (info.z) come from gl_VertexID in the shader.
      ++m_sprite_idx;
      continue;
    }

    vtx[1] = vert1;
    vtx[2] = vert1;
    vtx[3] = vert1;

    vtx[1].info[2] = 1;
    vtx[2].info[2] = 3;
    vtx[3].info[2] = 2;

    // note that PC swaps the last two vertices
    if (render_state->version == GameVersion::Jak3) {
      auto flag = m_vec_data_2d[sprite_idx].flag();
      switch (flag & 0x30) {
        case 0x10:
          // FLAG 16: 1, 0, 3, 2
          vtx[0].info[2] = 0;
          vtx[1].info[2] = 1;
          vtx[2].info[2] = 3;
          vtx[3].info[2] = 2;
          break;
        case 0x20:
          // FLAG 32: 3, 2, 1, 0
          vtx[0].info[2] = 3;
          vtx[1].info[2] = 2;
          vtx[2].info[2] = 0;
          vtx[3].info[2] = 1;
          break;
        case 0x30:
          // 2, 3, 0, 1
          vtx[0].info[2] = 2;
          vtx[1].info[2] = 3;
          vtx[2].info[2] = 1;
          vtx[3].info[2] = 0;
          break;
      }
    }

    ++m_sprite_idx;
  }
}
