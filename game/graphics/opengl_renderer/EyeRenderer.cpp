#include "EyeRenderer.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <sstream>

#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/opengl_renderer/AdgifHandler.h"
#include "game/graphics/opengl_renderer/foreground/Merc2.h"

#include "third-party/imgui/imgui.h"

#ifdef OG_FEAT_HD_MODELS
// CYCLE-4 [hd-blink] renderer-side blink proof (per eye slot, render thread only): counts donor
// lid paints vs skips on HD-covered slots and tracks the driver's lid-value excursion within a
// heartbeat window — a visible blink = lid_min dips low while lid_max stays near 1. These
// counters (not captures) are the validation instrument for the cycle-4 blink bar.
namespace {
struct HdBlinkStats {
  u32 donor_paints = 0;
  u32 skips_no_donor = 0;
  u32 stock_covered_paints = 0;  // must stay 0 — stock lid on HD eyes was the black-eye bug
  float lid_min = 1e9f;
  float lid_max = -1e9f;
};
HdBlinkStats s_hd_blink_stats[256];
u64 s_hd_blink_frames = 0;

// Grecharged-hd-eye-scale (owner 2026-08-06, "yeux trop globuleux" on exaggerated anims).
//
// THE CHANNEL. jak1 changes eye size by scaling the iris/pupil sprite inside the character's
// 32x32 eye tile, and that scale is ABSOLUTE IN TILE SPACE: render-eyes sizes the sprite as
// half-extent = 256 * <scale> GS subpixels (eye.gc:163/214 iris, :309/362 pupil) of a tile that
// spans 512, so `raw` below IS the GOAL-side iris-scale / pupil-scale.  merc-eye-anim (eye.gc:905)
// lerps it out of the frame-group's eye-anim-data, one UNSIGNED byte per channel per frame,
// dequantised by convert-eye-data (eye.gc:886-903, zero-extend then vitof12) as byte/64 — so the
// authored values are exact multiples of 1/64 in [0, 3.984] and the per-slot histogram below
// recovers the byte the artist actually keyed.
//
// ROOT CAUSE — measured, and NOT what the first attempt assumed.  The excursion is absolute in
// tile space, i.e. it is not relative to the eye it lands on; and the HD eye is NOT bigger at the
// bind, so nothing rescales it back down.  Measured on the shipped artifacts (plane fit over the
// eye primitive of decompiler_out/jak1/levels/common/sidekick-lod0.glb vs
// decompiler_out/jak3/levels/ldax/daxter-highres-lod0.glb, the pair carrying the
// programmer_eye_left/right textures):
//     bbox largest span   HD/stock = 0.984      (same size)
//     UV footprint        u=[0.0156,0.9844] on BOTH   (same share of the tile)
//     out-of-plane RMS / largest span   0.0367 stock -> 0.0645 HD   = 1.76x
//     vertex-normal spread              16.0 deg    -> 36.1 deg     = 2.25x
// Same size, same UVs, MUCH rounder surface (13 verts -> 126, and 1.76x more domed even after
// subsampling the HD cloud back to 13 verts).  So one and the same tile-space zoom paints a flat
// decal on the stock eye and inflates a bulging ball on the HD one — which is exactly the word the
// owner used.  Keira is the same way (RMS/L 1.37x, normals 2.12x); Jak's HD eye is measurably
// FLATTER than stock (0.40x) and Samos is ambiguous, which is why the defect reads on Daxter.
//
// FIX. Keep only a fraction of the excursion ABOVE the channel's AUTHORED REST value, on
// HD-covered slots only — a stock jak1 model always keeps jak1's exact channel, and below rest
// (eyes shrinking, never globuleux) jak1 is untouched too.  Because the curve can then only ever
// SHRINK a sprite relative to jak1, "HD <= stock" holds BY CONSTRUCTION, and a mis-specified rest
// can never inflate an eye.
//
// The rest is PER CHARACTER and PER CHANNEL — measured offline over the whole game by
// .autoport/hdeye_anim_scan.py (40 DGO art-groups + 2581 spooled-cutscene animations; the channel
// is one unsigned byte per frame, dequantised as byte/64):
//     Jak      eichar     iris 0.8906 flat        pupil 0.4375  (0.0938 .. 0.6406)
//     Daxter   sidekick   iris 0.3750 (0.1875 .. 0.6719)        pupil 0.0 in ALL 783 anims
//     Samos    sage       iris 1.0000 flat        pupil 1.0000  (0.6875 .. 1.0)
//     Keira    assistant  iris 1.0938 flat        pupil 0.5000  (0.5 .. 1.0)
// The first attempt anchored everything on a flat 1.0.  That is only the no-eye-anim-data fallback
// (eye.gc:952-959) and it is nobody's rest: it inflated every HD pupil by 30% at all times, and on
// Daxter — the character the owner actually reported — it would have pivoted 2.9x above his rest
// and conjured a pupil sprite onto a model that has none.  Hence: no global anchor, ever.
//
// gain_up 0.45 is not a magic number: it is below the tightest stock/HD doming ratio of the four HD
// characters (Daxter 0.0367/0.0645 = 0.569), so the bulge an HD eye can reach under the cartoon
// zoom stays under what the ORIGINAL model reaches.  Params are DATA (hd_eye_scale_load_once) so a
// retune is a text push, never a build.
constexpr int kEyeScaleSlots = 256;  // one per eye_id = (eye-slot << 1) | is_right
constexpr int kIris = 0, kPupil = 1;

struct HdEyeScaleParams {
  bool on = true;
  float gain_up = 0.45f;  // kept fraction of the ABOVE-rest excursion (the globuleux one)
  // ROUND 2 (owner 2026-08-08, "aucune différence, les deux yeux se TOUCHENT"): the tile-space
  // iris zoom above is a real channel but it is NOT the one that makes the eyeball big — see the
  // long block in Merc2.cpp.  These three bound the blerc displacement of an HD EYEBALL:
  //   blerc_gain      blunt multiplier on the whole thing (1.0 = no blanket cut)
  //   blerc_grow_cap  ceiling on the eye's fractional radius change
  //   blerc_close_cap ceiling on the fraction of the bind inter-eye distance that may be closed
  // The two caps are jak1's OWN measured worst case for Daxter, so an HD eye is allowed exactly
  // as much exaggeration as the original model reaches and no more.
  float blerc_gain = 1.00f;
  float blerc_grow_cap = 0.2629f;
  float blerc_close_cap = 0.198f;
};
// Per slot (= per eye_id). rest < 0 means "unknown": such a slot is MEASURED but never rewritten,
// because compressing towards a rest we do not know is how you shift a character's base look.
struct HdEyeScaleSlot {
  float rest[2] = {-1.f, -1.f};
  float gain_up = -1.f;          // < 0 = inherit the global
  float blerc_gain = -1.f;       // < 0 = inherit the global
  float blerc_grow_cap = -1.f;   // < 0 = inherit the global
  float blerc_close_cap = -1.f;  // < 0 = inherit the global
};
// eye_id -> {iris rest, pupil rest} for the four jak1 drivers every HD look retargets onto
// (hd_merc_swap --eye-from: jak 0/1, daxter 2/3, samos 4/5, keira 6/7). Compiled defaults, so a
// missing or stale physics_chains.txt falls back to the MEASURED values rather than to a guess.
struct HdEyeRestDefault {
  float iris, pupil;
};
constexpr HdEyeRestDefault kEyeRestDefault[8] = {
    {0.890625f, 0.437500f}, {0.890625f, 0.437500f},  // 0/1 eichar    = Jak
    {0.375000f, 0.000000f}, {0.375000f, 0.000000f},  // 2/3 sidekick  = Daxter (ottsel: no pupil)
    {1.000000f, 1.000000f}, {1.000000f, 1.000000f},  // 4/5 sage      = Samos
    {1.093750f, 0.500000f}, {1.093750f, 0.500000f},  // 6/7 assistant = Keira
};
HdEyeScaleParams s_eye_scale;
HdEyeScaleSlot s_eye_scale_slot[kEyeScaleSlots];
bool s_eye_scale_loaded = false;
bool s_eye_scale_warned_unknown[kEyeScaleSlots] = {};

float eye_gain_up_of(u8 slot) {
  const float o = s_eye_scale_slot[slot].gain_up;
  return o >= 0.f ? o : s_eye_scale.gain_up;
}

// Per eye slot, per sprite (kIris / kPupil), cumulative over the whole run; never reset, so the
// last heartbeat is the run summary. `raw` is the unmodified jak1 channel — exactly what the
// ORIGINAL model applies — and `cout` is what an HD-covered eye actually gets.
//
// raw_* spans EVERY draw (that is the stock measurement, and it is the only one a stock run can
// produce), while cov_raw_* and cov_out_* span the COVERED draws only, so the stock-vs-HD pair is
// read off the very same frames. The first attempt tracked out_* over all draws, which silently
// mixed rewritten and untouched frames and made the comparison meaningless.
//
// hist bins round(raw*64), i.e. the exact unsigned byte convert-eye-data dequantised, so the mode
// recovers the artist's authored REST value per character with no guessing.
struct HdEyeScaleStats {
  u32 draws = 0;
  u32 covered = 0;
  u32 changed = 0;
  float raw_min = 1e9f, raw_max = -1e9f;
  float cov_raw_min = 1e9f, cov_raw_max = -1e9f;
  float cov_out_min = 1e9f, cov_out_max = -1e9f;
  u32 hist[256] = {};
};
HdEyeScaleStats s_eye_scale_stats[2][kEyeScaleSlots];
u64 s_eye_scale_frames = 0;

float eye_scale_f(const std::string& v) {
  try {
    return std::stof(v);
  } catch (...) {
    return 0.f;
  }
}

// The [eyescale] block of recharged_assets/physics_chains.txt — the same shared HD tuning file,
// with the same external-pack-overrides-package precedence as the physics params
// (kmachine.cpp pc_physics_parse_file), so the owner retunes this with an adb push of one text
// file. PARAMSRC is logged so a gate can prove which copy was live.
void hd_eye_scale_load_once() {
  if (s_eye_scale_loaded) {
    return;
  }
  s_eye_scale_loaded = true;
  for (int s = 0; s < 8; s++) {
    s_eye_scale_slot[s].rest[kIris] = kEyeRestDefault[s].iris;
    s_eye_scale_slot[s].rest[kPupil] = kEyeRestDefault[s].pupil;
  }
  const char* src = "package";
  auto path = file_util::get_recharged_assets_dir() / "physics_chains.txt";
  auto ext_dir = file_util::get_external_recharged_assets_dir();
  if (ext_dir) {
    auto ext_path = *ext_dir / "physics_chains.txt";
    if (file_util::file_exists(ext_path.string())) {
      path = ext_path;
      src = "external-override";
    }
  }
  if (!file_util::file_exists(path.string())) {
    lg::info("[eyescale] PARAMSRC=none path={} (compiled defaults)", path.string());
    return;
  }
  std::string text;
  try {
    text = file_util::read_text_file(path);
  } catch (...) {
    lg::warn("[eyescale] could not read {}", path.string());
    return;
  }

  bool in_section = false;
  int n_slot_lines = 0;
  std::stringstream lines(text);
  std::string raw;
  while (std::getline(lines, raw)) {
    auto hash = raw.find('#');
    if (hash != std::string::npos) {
      raw = raw.substr(0, hash);
    }
    std::stringstream toks(raw);
    std::string tok;
    // A line may open with `slot N` (N = eye_id): the rest of THAT line then overrides only that
    // slot. Scoping the override to the line keeps the parser order-free, unlike a sticky context.
    int line_slot = -1;
    bool first = true;
    while (toks >> tok) {
      if (!tok.empty() && tok[0] == '[') {
        in_section = (tok == "[eyescale]");
        first = false;
        continue;
      }
      if (!in_section) {
        continue;
      }
      if (first && tok == "slot") {
        first = false;
        std::string idx;
        if (toks >> idx) {
          const int s = (int)eye_scale_f(idx);
          if (s >= 0 && s < kEyeScaleSlots) {
            line_slot = s;
            n_slot_lines++;
          } else {
            lg::warn("[eyescale] slot {} out of range (line ignored)", idx);
            break;
          }
        }
        continue;
      }
      first = false;
      auto eq = tok.find('=');
      if (eq == std::string::npos) {
        continue;
      }
      const std::string k = tok.substr(0, eq), v = tok.substr(eq + 1);
      const float f = eye_scale_f(v);
      if (k == "on") {
        if (line_slot < 0) {
          s_eye_scale.on = f != 0.f;
        }
      } else if (k == "rest_iris") {
        if (line_slot >= 0) {
          s_eye_scale_slot[line_slot].rest[kIris] = f;
        } else {
          lg::warn("[eyescale] rest_iris is per-slot only (prefix the line with `slot N`)");
        }
      } else if (k == "rest_pupil") {
        if (line_slot >= 0) {
          s_eye_scale_slot[line_slot].rest[kPupil] = f;
        } else {
          lg::warn("[eyescale] rest_pupil is per-slot only (prefix the line with `slot N`)");
        }
      } else if (k == "gainup") {
        (line_slot < 0 ? s_eye_scale.gain_up : s_eye_scale_slot[line_slot].gain_up) = f;
      } else if (k == "blerc_gain") {
        (line_slot < 0 ? s_eye_scale.blerc_gain : s_eye_scale_slot[line_slot].blerc_gain) = f;
      } else if (k == "blerc_grow_cap") {
        (line_slot < 0 ? s_eye_scale.blerc_grow_cap
                       : s_eye_scale_slot[line_slot].blerc_grow_cap) = f;
      } else if (k == "blerc_close_cap") {
        (line_slot < 0 ? s_eye_scale.blerc_close_cap
                       : s_eye_scale_slot[line_slot].blerc_close_cap) = f;
      } else if (k == "neutral" || k == "neutral_iris" || k == "neutral_pupil" || k == "gaindown") {
        // Deliberately IGNORED, not silently honoured: an owner still holding the first attempt's
        // external pack would otherwise re-apply `neutral=1.0` — nobody's authored rest — on top of
        // a fixed binary. Falling back to the compiled measured rests is the safe direction.
        lg::warn("[eyescale] legacy key '{}' IGNORED (superseded by per-slot rest_iris/rest_pupil)",
                 k);
      } else {
        lg::warn("[eyescale] unknown key '{}' in the [eyescale] block (skipped)", k);
      }
    }
  }
  lg::info(
      "[eyescale] PARAMSRC={} on={} gainup={:.3f} blerc_gain={:.3f} blerc_grow_cap={:.4f} "
      "blerc_close_cap={:.4f} slot_lines={} path={}",
      src, (int)s_eye_scale.on, s_eye_scale.gain_up, s_eye_scale.blerc_gain,
      s_eye_scale.blerc_grow_cap, s_eye_scale.blerc_close_cap, n_slot_lines, path.string());
  for (int s = 0; s < 8; s++) {
    const auto c = hd_eye_blerc_caps((u8)s);
    lg::info("[eyescale] anchor slot={} rest_iris={:.5f} rest_pupil={:.5f} gainup={:.3f} "
             "blerc_gain={:.3f} blerc_grow_cap={:.4f} blerc_close_cap={:.4f}",
             s, s_eye_scale_slot[s].rest[kIris], s_eye_scale_slot[s].rest[kPupil],
             eye_gain_up_of((u8)s), c.gain, c.grow, c.close);
  }
}

// Monotone, continuous, an EXACT identity at and BELOW the authored rest — so the eye at rest is
// bit-identical to jak1, the effect never pops, and the result can only ever be <= jak1's own
// value. "HD never more exaggerated than stock" is therefore a property of the curve, not of a
// lucky tuning.
float hd_eye_scale_curve(float s, float rest, float gain_up) {
  const float out = (s > rest) ? rest + gain_up * (s - rest) : s;
  return out < 0.f ? 0.f : out;
}

// Rewrites one iris/pupil sprite in place (about its own centre, so the eye's look direction is
// untouched) and records the raw-vs-applied scale. `tile_span` is how many GS subpixels of the
// sprite's extent make up one full tile, i.e. scale 1.0. Uncovered slots are measured but NEVER
// rewritten: a stock jak1 model keeps jak1's exact channel.
void hd_eye_scale_sprite(EyeRenderer::SpriteInfo& sp, float tile_span, u8 slot, int which,
                         bool covered) {
  auto& st = s_eye_scale_stats[which][slot];
  const float sx = ((float)sp.xyz1[0] - (float)sp.xyz0[0]) / tile_span;
  const float sy = ((float)sp.xyz1[1] - (float)sp.xyz0[1]) / tile_span;
  const float raw = 0.5f * (sx + sy);
  st.draws++;
  st.raw_min = std::min(st.raw_min, raw);
  st.raw_max = std::max(st.raw_max, raw);
  {  // the authored byte, exactly as convert-eye-data dequantised it (UNSIGNED, value = byte/64)
    const int bin = (int)std::lround(raw * 64.f);
    if (bin >= 0 && bin < 256) {
      st.hist[bin]++;
    }
  }

  if (!(covered && s_eye_scale.on)) {
    return;  // stock model: measured, never rewritten, and never mixed into the HD numbers
  }
  const float rest = s_eye_scale_slot[slot].rest[which];
  if (rest < 0.f) {
    // Fail-safe: an HD-covered slot whose authored rest was never measured is left exactly as jak1
    // emitted it. Shifting a base look we cannot anchor would be worse than the defect.
    if (!s_eye_scale_warned_unknown[slot]) {
      s_eye_scale_warned_unknown[slot] = true;
      lg::warn("[eyescale] slot={} is HD-covered but has no measured rest — left untouched", slot);
    }
    return;
  }
  st.covered++;
  const float gu = eye_gain_up_of(slot);
  const float ox = hd_eye_scale_curve(sx, rest, gu), oy = hd_eye_scale_curve(sy, rest, gu);
  const float cx = 0.5f * ((float)sp.xyz0[0] + (float)sp.xyz1[0]);
  const float cy = 0.5f * ((float)sp.xyz0[1] + (float)sp.xyz1[1]);
  const float hx = 0.5f * ox * tile_span, hy = 0.5f * oy * tile_span;
  sp.xyz0[0] = (u32)std::max(0.f, std::round(cx - hx));
  sp.xyz1[0] = (u32)std::max(0.f, std::round(cx + hx));
  sp.xyz0[1] = (u32)std::max(0.f, std::round(cy - hy));
  sp.xyz1[1] = (u32)std::max(0.f, std::round(cy + hy));
  const float out = 0.5f * (ox + oy);
  if (std::abs(out - raw) > 1e-4f) {
    st.changed++;
  }
  st.cov_raw_min = std::min(st.cov_raw_min, raw);
  st.cov_raw_max = std::max(st.cov_raw_max, raw);
  st.cov_out_min = std::min(st.cov_out_min, out);
  st.cov_out_max = std::max(st.cov_out_max, out);
}

void hd_eye_scale_heartbeat() {
  if (++s_eye_scale_frames % 240) {
    return;
  }
  static const char* kKindName[2] = {"iris", "pupil"};
  for (int slot = 0; slot < kEyeScaleSlots; slot++) {
    for (int which = 0; which < 2; which++) {
      const auto& st = s_eye_scale_stats[which][slot];
      if (!st.draws) {
        continue;
      }
      int mode = 0;
      u32 mode_n = 0;
      for (int b = 0; b < 256; b++) {
        if (st.hist[b] > mode_n) {
          mode_n = st.hist[b];
          mode = b;
        }
      }
      lg::info(
          "[eyescale] slot={} kind={} draws={} covered={} changed={} raw_min={:.4f} raw_max={:.4f} "
          "cov_raw_min={:.4f} cov_raw_max={:.4f} cov_out_min={:.4f} cov_out_max={:.4f} "
          "rest={:.5f} restshare={:.3f} anchor={:.5f}",
          slot, kKindName[which], st.draws, st.covered, st.changed, st.raw_min, st.raw_max,
          st.cov_raw_min, st.cov_raw_max, st.cov_out_min, st.cov_out_max, mode / 64.f,
          (float)mode_n / (float)st.draws, s_eye_scale_slot[slot].rest[which]);
    }
  }
}
}  // namespace

// Exported for Merc2 (see EyeRenderer.h). Same [eyescale] block, same load-once, same
// external-pack-overrides-package precedence — one tuning file for the whole eye feature.
// `on=0` disables the whole thing: gain 1 with both ceilings effectively infinite = jak1 exactly.
HdEyeBlercCaps hd_eye_blerc_caps(unsigned char eye_id) {
  hd_eye_scale_load_once();
  HdEyeBlercCaps c{1.f, 1e9f, 1e9f};
  if (!s_eye_scale.on) {
    return c;
  }
  const auto& sl = s_eye_scale_slot[eye_id];
  c.gain = sl.blerc_gain >= 0.f ? sl.blerc_gain : s_eye_scale.blerc_gain;
  c.grow = sl.blerc_grow_cap >= 0.f ? sl.blerc_grow_cap : s_eye_scale.blerc_grow_cap;
  c.close = sl.blerc_close_cap >= 0.f ? sl.blerc_close_cap : s_eye_scale.blerc_close_cap;
  if (c.gain < 0.f || c.gain > 1.f) {
    c.gain = 1.f;
  }
  if (c.grow < 0.f) {
    c.grow = 1e9f;
  }
  if (c.close < 0.f || c.close > 1.f) {
    c.close = 1.f;
  }
  return c;
}
#endif

/////////////////////////
// Bucket Renderer
/////////////////////////
EyeRenderer::EyeRenderer(const std::string& name, int id) : BucketRenderer(name, id) {}

void EyeRenderer::init_textures(TexturePool& texture_pool, GameVersion version) {
  // set up eyes
  for (int pair_idx = 0; pair_idx < NUM_EYE_PAIRS; pair_idx++) {
    for (int lr = 0; lr < 2; lr++) {
      u32 tidx = pair_idx * 2 + lr;

      u32 tbp = pair_idx * 2 + lr;
      switch (version) {
        case GameVersion::Jak1:
          tbp += EYE_BASE_BLOCK_JAK1;
          break;
        case GameVersion::Jak2:
          // NOTE: using jak 1's address because jak 2's breaks some ocean stuff.
          // this is a little suspicious, I think we're possibly just getting lucky here.
          tbp += EYE_BASE_BLOCK_JAK1;
          break;
        case GameVersion::Jak3:
        case GameVersion::JakX:
          // for jak 3, go back to using the right TBP.
          tbp += EYE_BASE_BLOCK_JAK3;
          break;
        default:
          ASSERT_NOT_REACHED();
      }
      TextureInput in;
      in.gpu_texture = m_gpu_eye_textures[tidx].fb.texture();
      in.w = 32;
      in.h = 32;
      in.debug_page_name = "PC-EYES";
      in.debug_name = fmt::format("{}-eye-gpu-{}", lr ? "left" : "right", pair_idx);
      in.id = texture_pool.allocate_pc_port_texture(version);
      m_gpu_eye_textures[tidx].gpu_tex = texture_pool.give_texture_and_load_to_vram(in, tbp);
      m_gpu_eye_textures[tidx].tbp = tbp;
    }
  }

  // set up vertices for GPU mode
  glGenVertexArrays(1, &m_vao);
  glBindVertexArray(m_vao);
  glGenBuffers(1, &m_gl_vertex_buffer);
  glBindBuffer(GL_ARRAY_BUFFER, m_gl_vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, VTX_BUFFER_FLOATS * sizeof(float), nullptr, GL_STREAM_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0,                  // location 0 in the shader
                        4,                  // 2 floats per vert
                        GL_FLOAT,           // floats
                        GL_TRUE,            // normalized, ignored,
                        sizeof(float) * 4,  //
                        (void*)0            // offset in array
  );
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
}

EyeRenderer::~EyeRenderer() {
  glDeleteVertexArrays(1, &m_vao);
  glDeleteBuffers(1, &m_gl_vertex_buffer);
}

void EyeRenderer::render(DmaFollower& dma,
                         SharedRenderState* render_state,
                         ScopedProfilerNode& prof) {
  m_debug.clear();

  // skip if disabled
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  // jump to bucket
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0);
  ASSERT(data0.vif0() == 0);
  ASSERT(data0.size_bytes == 0);

  // see if bucket is empty or not
  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return;
  }

  handle_eye_dma2(dma, render_state, prof);

  while (dma.current_tag_offset() != render_state->next_bucket && !dma.ended()) {
    auto data = dma.read_and_advance();
    if (m_debug.size() < 65536) {
      m_debug += fmt::format("dma: {}\n", data.size_bytes);
    }
  }
  if (dma.current_tag_offset() != render_state->next_bucket) {
    // handle_eye_dma2 left the follower outside this bucket. Without the
    // ended() bound above, this drain walks the rest of the frame's chain
    // and never terminates (m_debug grew until the OOM killer fired on the
    // Android bring-up, the first time real eye DMA appeared there).
    // Reseat on the bucket boundary so dispatch's invariant holds.
    static bool s_warned_off_bucket = false;
    if (!s_warned_off_bucket) {
      s_warned_off_bucket = true;
      fmt::print("EyeRenderer: drain ended off-bucket at {} (ended={}), reseating to {}\n",
                 dma.current_tag_offset(), dma.ended(), render_state->next_bucket);
    }
    dma = DmaFollower(dma.base(), render_state->next_bucket);
  }
}

void EyeRenderer::draw_debug_window() {
  ImGui::Text("Time: %.3f ms\n", m_average_time_ms);
  ImGui::Text("Debug:\n%s", m_debug.c_str());
}

//////////////////////
// DMA Decode
//////////////////////

EyeRenderer::ScissorInfo decode_scissor(const DmaTransfer& dma) {
  ASSERT(dma.vif0() == 0);
  ASSERT(dma.vifcode1().kind == VifCode::Kind::DIRECT);
  ASSERT(dma.size_bytes == 32);

  GifTag gifTag(dma.data);
  ASSERT(gifTag.nloop() == 1);
  ASSERT(gifTag.eop());
  ASSERT(!gifTag.pre());
  ASSERT(gifTag.flg() == GifTag::Format::PACKED);
  ASSERT(gifTag.nreg() == 1);

  u8 reg_addr;
  memcpy(&reg_addr, dma.data + 24, 1);
  ASSERT((GsRegisterAddress)reg_addr == GsRegisterAddress::SCISSOR_1);
  EyeRenderer::ScissorInfo result;
  u64 val;
  memcpy(&val, dma.data + 16, 8);
  GsScissor reg(val);
  result.x0 = reg.x0();
  result.x1 = reg.x1();
  result.y0 = reg.y0();
  result.y1 = reg.y1();
  return result;
}

EyeRenderer::SpriteInfo decode_sprite(const DmaTransfer& dma) {
  /*
   (new 'static 'dma-gif-packet
        :dma-vif (new 'static 'dma-packet
                      :dma (new 'static 'dma-tag :qwc #x6 :id (dma-tag-id cnt))
                      :vif1 (new 'static 'vif-tag :imm #x6 :cmd (vif-cmd direct) :msk #x1)
                      )
        :gif0 (new 'static 'gif-tag64
                   :nloop #x1
                   :eop #x1
                   :pre #x1
                   :prim (new 'static 'gs-prim :prim (gs-prim-type sprite) :tme #x1 :fst #x1)
                   :nreg #x5
                   )
        :gif1 (new 'static 'gif-tag-regs
                   :regs0 (gif-reg-id rgbaq)
                   :regs1 (gif-reg-id uv)
                   :regs2 (gif-reg-id xyz2)
                   :regs3 (gif-reg-id uv)
                   :regs4 (gif-reg-id xyz2)
                   )
        )
   */

  ASSERT(dma.vif0() == 0);
  ASSERT(dma.vifcode1().kind == VifCode::Kind::DIRECT);
  ASSERT(dma.size_bytes == 6 * 16);

  // note: not checking everything here.
  GifTag gifTag(dma.data);
  ASSERT(gifTag.nloop() == 1);
  ASSERT(gifTag.eop());
  ASSERT(gifTag.pre());
  ASSERT(gifTag.flg() == GifTag::Format::PACKED);
  ASSERT(gifTag.nreg() == 5);

  EyeRenderer::SpriteInfo result;

  // rgba
  ASSERT(dma.data[16] == 128);               // r
  ASSERT(dma.data[16 + 4] == 128);           // r
  ASSERT(dma.data[16 + 8] == 128);           // r
  memcpy(&result.a, dma.data + 16 + 12, 1);  // a

  // uv0
  memcpy(&result.uv0, &dma.data[32], 8);

  // xyz0
  memcpy(&result.xyz0[0], &dma.data[48], 12);
  result.xyz0[2] >>= 4;

  // uv1
  memcpy(&result.uv1[0], &dma.data[64], 8);

  // xyz1
  memcpy(&result.xyz1[0], &dma.data[80], 12);
  result.xyz1[2] >>= 4;

  return result;
}

EyeRenderer::EyeDraw read_eye_draw(DmaFollower& dma) {
  auto scissor = decode_scissor(dma.read_and_advance());
  auto sprite = decode_sprite(dma.read_and_advance());
  return {sprite, scissor};
}

std::vector<EyeRenderer::SingleEyeDraws> EyeRenderer::get_draws(DmaFollower& dma,
                                                                SharedRenderState* render_state) {
  std::vector<SingleEyeDraws> draws;
  // now, loop over eyes. end condition is a 8 qw transfer to restore gs.
  while (dma.current_tag().qwc != 8) {
    draws.emplace_back();
    draws.emplace_back();

    auto& l_draw = draws[draws.size() - 2];
    auto& r_draw = draws[draws.size() - 1];

    l_draw.lr = 0;
    r_draw.lr = 1;

    // eye background setup
    auto adgif0_dma = dma.read_and_advance();
    ASSERT(adgif0_dma.size_bytes == 96);  // 5 adgifs a+d's plus tag
    ASSERT(adgif0_dma.vif0() == 0);
    ASSERT(adgif0_dma.vifcode1().kind == VifCode::Kind::DIRECT);
    AdgifHelper adgif0(adgif0_dma.data + 16);
    auto tex0 = render_state->texture_pool->lookup_gpu_texture(adgif0.tex0().tbp0());

    u32 pair_idx = -1;
    // first draw. this is the background. It reads 0,0 of the texture uses that color everywhere.
    // we'll also figure out the eye index here.
    bool using_64 = false;
    {
      auto draw0 = read_eye_draw(dma);
      // ASSERT(draw0.sprite.uv0[0] == 0);
      // ASSERT(draw0.sprite.uv0[1] == 0);
      // printf("hashed name is 0x%x 0x%x\n", draw0.sprite.uv0[0], draw0.sprite.uv0[1]);
      l_draw.fnv_name_hash = draw0.sprite.uv0;
      r_draw.fnv_name_hash = draw0.sprite.uv0;
      ASSERT(draw0.sprite.uv1[0] == 0);
      ASSERT(draw0.sprite.uv1[1] == 0);
      if (draw0.scissor.y1 - draw0.scissor.y0 == 63) {
        using_64 = true;
        l_draw.using_64 = true;
        r_draw.using_64 = true;
      }
      u32 y0 = (draw0.sprite.xyz0[1] - 512) >> 4;
      if (using_64) {
        y0 = (draw0.sprite.xyz0[1] - 1024) >> 5;
        y0 *= 4;
      }
      pair_idx = y0 / SINGLE_EYE_SIZE;
      l_draw.pair = pair_idx;
      r_draw.pair = pair_idx;
    }

    // up next is the pupil background
    {
      l_draw.iris = read_eye_draw(dma);
      l_draw.iris_tex = tex0;
      l_draw.iris_gl_tex = *render_state->texture_pool->lookup(adgif0.tex0().tbp0());

      if (dma.current_tag().qwc == 6) {
        // change adgif!
        auto r_iris_adgif = dma.read_and_advance();
        ASSERT(r_iris_adgif.size_bytes == 96);  // 5 adgifs a+d's plus tag
        ASSERT(r_iris_adgif.vif0() == 0);
        ASSERT(r_iris_adgif.vifcode1().kind == VifCode::Kind::DIRECT);
        AdgifHelper r_iris_helper(r_iris_adgif.data + 16);
        r_draw.iris = read_eye_draw(dma);
        r_draw.iris_tex =
            render_state->texture_pool->lookup_gpu_texture(r_iris_helper.tex0().tbp0());
        r_draw.iris_gl_tex = *render_state->texture_pool->lookup(r_iris_helper.tex0().tbp0());
      } else {
        // same adgif
        r_draw.iris = read_eye_draw(dma);
        r_draw.iris_tex = tex0;
        r_draw.iris_gl_tex = l_draw.iris_gl_tex;
      }
    }

    // now we'll draw the pupil on top of that
    auto test1 = dma.read_and_advance();
    (void)test1;
    auto adgif1_dma = dma.read_and_advance();
    ASSERT(adgif1_dma.size_bytes == 96);  // 5 adgifs a+d's plus tag
    ASSERT(adgif1_dma.vif0() == 0);
    ASSERT(adgif1_dma.vifcode1().kind == VifCode::Kind::DIRECT);
    AdgifHelper adgif1(adgif1_dma.data + 16);
    auto tex1 = render_state->texture_pool->lookup_gpu_texture(adgif1.tex0().tbp0());

    if (tex1 && tex1->get_data_ptr()) {
      l_draw.pupil = read_eye_draw(dma);
      l_draw.pupil_tex = tex1;
      l_draw.pupil_gl_tex = *render_state->texture_pool->lookup(adgif1.tex0().tbp0());
    }

    if (dma.current_tag().qwc == 6) {
      auto r_pupil_adgif = dma.read_and_advance();
      ASSERT(r_pupil_adgif.size_bytes == 96);  // 5 adgifs a+d's plus tag
      ASSERT(r_pupil_adgif.vif0() == 0);
      ASSERT(r_pupil_adgif.vifcode1().kind == VifCode::Kind::DIRECT);
      AdgifHelper r_pupil_helper(r_pupil_adgif.data + 16);
      r_draw.pupil = read_eye_draw(dma);
      r_draw.pupil_tex =
          render_state->texture_pool->lookup_gpu_texture(r_pupil_helper.tex0().tbp0());
      r_draw.pupil_gl_tex = *render_state->texture_pool->lookup(r_pupil_helper.tex0().tbp0());
    } else {
      if (tex1 && tex1->get_data_ptr()) {
        r_draw.pupil = read_eye_draw(dma);
        r_draw.pupil_tex = tex1;
        r_draw.pupil_gl_tex = l_draw.pupil_gl_tex;
      }
    }

    // and finally the eyelid
    auto test2 = dma.read_and_advance();
    (void)test2;
    auto adgif2_dma = dma.read_and_advance();
    ASSERT(adgif2_dma.size_bytes == 96);  // 5 adgifs a+d's plus tag
    ASSERT(adgif2_dma.vif0() == 0);
    ASSERT(adgif2_dma.vifcode1().kind == VifCode::Kind::DIRECT);
    AdgifHelper adgif2(adgif2_dma.data + 16);
    auto tex2 = render_state->texture_pool->lookup_gpu_texture(adgif2.tex0().tbp0());

    {
      l_draw.lid = read_eye_draw(dma);
      l_draw.lid_tex = tex2;
      l_draw.lid_gl_tex = *render_state->texture_pool->lookup(adgif2.tex0().tbp0());
    }

    if (dma.current_tag().qwc == 6) {
      auto r_lid_adgif = dma.read_and_advance();
      ASSERT(r_lid_adgif.size_bytes == 96);  // 5 adgifs a+d's plus tag
      ASSERT(r_lid_adgif.vif0() == 0);
      ASSERT(r_lid_adgif.vifcode1().kind == VifCode::Kind::DIRECT);
      AdgifHelper r_lid_helper(r_lid_adgif.data + 16);
      r_draw.lid = read_eye_draw(dma);
      r_draw.lid_tex = render_state->texture_pool->lookup_gpu_texture(r_lid_helper.tex0().tbp0());
      r_draw.lid_gl_tex = *render_state->texture_pool->lookup(r_lid_helper.tex0().tbp0());
    } else {
      r_draw.lid = read_eye_draw(dma);
      r_draw.lid_tex = tex2;
      r_draw.lid_gl_tex = l_draw.lid_gl_tex;
    }

    if (render_state->version == GameVersion::Jak1) {
      auto end = dma.read_and_advance();
      ASSERT(end.size_bytes == 0);
      ASSERT(end.vif0() == 0);
      ASSERT(end.vif1() == 0);
    }
  }

#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-eye-scale: tone the cartoon eye-size channel down on HD-covered slots (see the
  // root-cause note at the top of this file). Every slot is MEASURED, only covered ones are
  // rewritten — so this is also the raw-vs-applied instrument, on identical frames.
  hd_eye_scale_load_once();
  for (auto& d : draws) {
    const u8 slot = (u8)d.tex_slot();
    const bool covered = merc2_hd_eye_slot_covered(slot);
    const float tile_span = d.using_64 ? 1024.f : 512.f;
    // .sprite: EyeDraw wraps {SpriteInfo sprite, ScissorInfo scissor} and the rewrite is a sprite
    // operation. The lid is deliberately NOT rescaled: on a covered slot the stock jak1 lid blit is
    // already replaced by the donor's own lid texture (cycle-4, run_gpu below), so lid-scale no
    // longer drives what the HD eye shows.
    hd_eye_scale_sprite(d.iris.sprite, tile_span, slot, kIris, covered);
    hd_eye_scale_sprite(d.pupil.sprite, tile_span, slot, kPupil, covered);
  }
  hd_eye_scale_heartbeat();
#endif
  return draws;
}

void EyeRenderer::handle_eye_dma2(DmaFollower& dma,
                                  SharedRenderState* render_state,
                                  ScopedProfilerNode&) {
  Timer timer;
  m_debug.clear();

  // first should be the gs setup for render to texture
  auto offset_setup = dma.read_and_advance();
  ASSERT(offset_setup.size_bytes == 128);
  ASSERT(offset_setup.vifcode0().kind == VifCode::Kind::FLUSHA);
  ASSERT(offset_setup.vifcode1().kind == VifCode::Kind::DIRECT);

  // next should be alpha setup
  auto alpha_setup = dma.read_and_advance();
  ASSERT(alpha_setup.size_bytes == 32);
  ASSERT(alpha_setup.vifcode0().kind == VifCode::Kind::NOP);
  ASSERT(alpha_setup.vifcode1().kind == VifCode::Kind::DIRECT);

  if (render_state->version == GameVersion::Jak1) {
    // from the add to bucket
    ASSERT(dma.current_tag().kind == DmaTag::Kind::NEXT);
    ASSERT(dma.current_tag().qwc == 0);
    ASSERT(dma.current_tag_vif0() == 0);
    ASSERT(dma.current_tag_vif1() == 0);
    dma.read_and_advance();
  }

  auto draws = get_draws(dma, render_state);
  run_gpu(draws, render_state);

  float time_ms = timer.getMs();
  m_average_time_ms = m_average_time_ms * 0.95 + time_ms * 0.05;
}

int add_draw_to_buffer_32(int idx,
                          const EyeRenderer::EyeDraw& draw,
                          float* data,
                          int pair,
                          int lr) {
  int x_off = lr * SINGLE_EYE_SIZE * 16;
  int y_off = pair * SINGLE_EYE_SIZE * 16;

  data[idx++] = draw.sprite.xyz0[0] - x_off;
  data[idx++] = draw.sprite.xyz0[1] - y_off;
  data[idx++] = 0;
  data[idx++] = 0;

  data[idx++] = draw.sprite.xyz1[0] - x_off;
  data[idx++] = draw.sprite.xyz0[1] - y_off;
  data[idx++] = 1;
  data[idx++] = 0;

  data[idx++] = draw.sprite.xyz0[0] - x_off;
  data[idx++] = draw.sprite.xyz1[1] - y_off;
  data[idx++] = 0;
  data[idx++] = 1;

  data[idx++] = draw.sprite.xyz1[0] - x_off;
  data[idx++] = draw.sprite.xyz1[1] - y_off;
  data[idx++] = 1;
  data[idx++] = 1;
  return idx;
}

int add_draw_to_buffer_64(int idx,
                          const EyeRenderer::EyeDraw& draw,
                          float* data,
                          int pair,
                          int lr) {
  int x_off = lr * SINGLE_EYE_SIZE * 32;
  int y_off = (pair / 4) * SINGLE_EYE_SIZE * 32;

  data[idx++] = (draw.sprite.xyz0[0] - x_off) / 2;
  data[idx++] = (draw.sprite.xyz0[1] - y_off) / 2;
  data[idx++] = 0;
  data[idx++] = 0;

  data[idx++] = (draw.sprite.xyz1[0] - x_off) / 2;
  data[idx++] = (draw.sprite.xyz0[1] - y_off) / 2;
  data[idx++] = 1;
  data[idx++] = 0;

  data[idx++] = (draw.sprite.xyz0[0] - x_off) / 2;
  data[idx++] = (draw.sprite.xyz1[1] - y_off) / 2;
  data[idx++] = 0;
  data[idx++] = 1;

  data[idx++] = (draw.sprite.xyz1[0] - x_off) / 2;
  data[idx++] = (draw.sprite.xyz1[1] - y_off) / 2;
  data[idx++] = 1;
  data[idx++] = 1;
  return idx;
}

int add_clear_draw_to_buffer(int idx, float* data) {
  // the entire eye texture is cleared using the 0,0 value from the iris texture
  const float center = 768;
  const float upper = center + 256;
  const float lower = center - 256;
  data[idx++] = lower;
  data[idx++] = lower;
  data[idx++] = 0;
  data[idx++] = 0;

  data[idx++] = upper;
  data[idx++] = lower;
  data[idx++] = 0;
  data[idx++] = 0;

  data[idx++] = lower;
  data[idx++] = upper;
  data[idx++] = 0;
  data[idx++] = 0;

  data[idx++] = upper;
  data[idx++] = upper;
  data[idx++] = 0;
  data[idx++] = 0;
  return idx;
}

void EyeRenderer::run_gpu(const std::vector<SingleEyeDraws>& draws,
                          SharedRenderState* render_state) {
  if (draws.empty()) {
    return;
  }

  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_gl_vertex_buffer);

  // the first thing we'll do is prepare the vertices
  int buffer_idx = 0;
  for (const auto& draw : draws) {
    buffer_idx = add_clear_draw_to_buffer(buffer_idx, m_gpu_vertex_buffer);
    if (draw.using_64) {
      buffer_idx =
          add_draw_to_buffer_64(buffer_idx, draw.iris, m_gpu_vertex_buffer, draw.pair, draw.lr);
      buffer_idx =
          add_draw_to_buffer_64(buffer_idx, draw.pupil, m_gpu_vertex_buffer, draw.pair, draw.lr);
      buffer_idx =
          add_draw_to_buffer_64(buffer_idx, draw.lid, m_gpu_vertex_buffer, draw.pair, draw.lr);
    } else {
      buffer_idx =
          add_draw_to_buffer_32(buffer_idx, draw.iris, m_gpu_vertex_buffer, draw.pair, draw.lr);
      buffer_idx =
          add_draw_to_buffer_32(buffer_idx, draw.pupil, m_gpu_vertex_buffer, draw.pair, draw.lr);
      buffer_idx =
          add_draw_to_buffer_32(buffer_idx, draw.lid, m_gpu_vertex_buffer, draw.pair, draw.lr);
    }
  }
  ASSERT(buffer_idx <= VTX_BUFFER_FLOATS);
  int check = buffer_idx;

  // maybe buffer sub data.
  glBufferData(GL_ARRAY_BUFFER, buffer_idx * sizeof(float), m_gpu_vertex_buffer, GL_STREAM_DRAW);

  FramebufferTexturePairContext ctxt(m_gpu_eye_textures[draws.front().tex_slot()].fb);

  // set up common opengl state
  glDisable(GL_DEPTH_TEST);
  render_state->shaders[ShaderId::EYE].activate();
  glUniform1i(glGetUniformLocation(render_state->shaders[ShaderId::EYE].id(), "tex_T0"), 0);
  glActiveTexture(GL_TEXTURE0);

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  buffer_idx = 0;
  for (size_t draw_idx = 0; draw_idx < draws.size(); draw_idx++) {
    const auto& draw = draws[draw_idx];
    auto& out_tex = m_gpu_eye_textures[draw.tex_slot()];
    out_tex.fnv_name_hash = draw.fnv_name_hash;
    out_tex.lr = draw.lr;

    // clear: not really needed, but we do it to help debugging in case all the textures are missing
    float clear[4] = {1.0, 0, 0, 0};
    glClearBufferfv(GL_COLOR, 0, clear);

    // background
    if (draw.iris_tex) {
      glDisable(GL_BLEND);
      glBindTexture(GL_TEXTURE_2D, draw.iris_gl_tex);
      glDrawArrays(GL_TRIANGLE_STRIP, buffer_idx / 4, 4);
    }
    buffer_idx += 4 * 4;

    // iris
    if (draw.iris_tex) {
      // set alpha
      // set Z
      // set texture
      glDisable(GL_BLEND);
      glBindTexture(GL_TEXTURE_2D, draw.iris_gl_tex);
      glDrawArrays(GL_TRIANGLE_STRIP, buffer_idx / 4, 4);
    }
    buffer_idx += 4 * 4;

    if (draw.pupil_tex) {
      glEnable(GL_BLEND);
      glBlendEquation(GL_FUNC_ADD);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glBindTexture(GL_TEXTURE_2D, draw.pupil_gl_tex);
      glDrawArrays(GL_TRIANGLE_STRIP, buffer_idx / 4, 4);
    }
    buffer_idx += 4 * 4;

    // CYCLE-3 (Grecharged-hd-models4, Keira black-eyes-on-blink): jak1 blinks by painting
    // the lid texture over the WHOLE eye tile (blend off). The stock eye mesh is a flat
    // eyelid patch, so that reads as a closing lid — but an HD companion's donor EYEBALL
    // geometry wraps the full tile around the eye and shows the jak1 lid texture as black/
    // weird eyes for the ~10 blink frames.
    // CYCLE-4 (visible blink): the donor games blink the SAME way (same blink-table math,
    // per-eye lid textures), so for a covered slot we paint the DONOR's own lid texture
    // (ported into enhanced GAME.fr3, id recorded by Merc2 at slot arming) at the driver's
    // lid position — the donor's exact blink on the donor's own eye UVs. If the donor lid is
    // not available, keep the cycle-3 skip (fail-safe: never the stock lid on HD eyes).
    bool lid_skip = false;
    GLuint lid_gl_tex = draw.lid_gl_tex;
#ifdef OG_FEAT_HD_MODELS
    const u8 hd_slot = (u8)draw.tex_slot();
    bool hd_covered = merc2_hd_eye_slot_covered(hd_slot);
    bool hd_donor_bound = false;
    if (hd_covered) {
      u64 donor_gl = merc2_hd_eye_slot_lid_gl(hd_slot);
      if (donor_gl) {
        lid_gl_tex = (GLuint)donor_gl;
        hd_donor_bound = true;
      } else {
        lid_skip = true;
      }
    }
    // [hd-blink] proof counters (renderer-side, never captures): the driver's lid value is
    // already encoded in the quad the DMA gave us — tile-local y_top = 512*lid (32px tiles,
    // GS subpixels), 0.0 = fully closed, 1.0 = open/clipped out.
    {
      float y_top = m_gpu_vertex_buffer[buffer_idx + 1];
      float lid_value = std::min(1.f, std::max(0.f, y_top / 512.f));
      auto& bs = s_hd_blink_stats[hd_slot];
      if (hd_covered) {
        bs.lid_min = std::min(bs.lid_min, lid_value);
        bs.lid_max = std::max(bs.lid_max, lid_value);
        if (hd_donor_bound) {
          bs.donor_paints++;
        } else if (lid_skip) {
          bs.skips_no_donor++;
        }
        if (draw.lid_tex && !lid_skip && !hd_donor_bound) {
          // structurally unreachable (covered => donor or skip); counted as an honesty metric
          bs.stock_covered_paints++;
          lg::warn("[hd-blink] STOCKLID slot={}", hd_slot);
        }
      }
    }
#endif
    if (draw.lid_tex && !lid_skip) {
      glDisable(GL_BLEND);
      glBindTexture(GL_TEXTURE_2D, lid_gl_tex);
      glDrawArrays(GL_TRIANGLE_STRIP, buffer_idx / 4, 4);
    }
    buffer_idx += 4 * 4;

    // finally, give to "vram"
    render_state->texture_pool->move_existing_to_vram(out_tex.gpu_tex, out_tex.tbp);

    if (draw_idx != draws.size() - 1) {
      ctxt.switch_to(m_gpu_eye_textures[draws[draw_idx + 1].tex_slot()].fb);
    }
  }

  ASSERT(check == buffer_idx);

#ifdef OG_FEAT_HD_MODELS
  // [hd-blink] heartbeat: one line per slot with HD lid activity, every ~4s of eye frames.
  if (++s_hd_blink_frames % 240 == 0) {
    for (int i = 0; i < 256; i++) {
      auto& bs = s_hd_blink_stats[i];
      if (bs.donor_paints || bs.skips_no_donor || bs.stock_covered_paints) {
        lg::info(
            "[hd-blink] slot={} donor_paints={} skips={} stock_covered={} lid_min={:.3f} "
            "lid_max={:.3f}",
            i, bs.donor_paints, bs.skips_no_donor, bs.stock_covered_paints, bs.lid_min,
            bs.lid_max);
        bs = HdBlinkStats{};
      }
    }
  }
#endif

  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
}

std::optional<u64> EyeRenderer::lookup_eye_texture(u8 eye_id) {
  eye_id = (eye_id % 40);
  if ((s32)eye_id >= NUM_EYE_PAIRS * 2) {
    fmt::print("lookup eye failed for {} (1)\n", eye_id);
    return {};
  }
  auto* gpu_tex = m_gpu_eye_textures[eye_id].gpu_tex;
  if (gpu_tex) {
    return gpu_tex->gpu_textures.at(0).gl;
  } else {
    fmt::print("lookup eye failed for {}\n", eye_id);
    return {};
  }
}

std::optional<u64> EyeRenderer::lookup_eye_texture_hash(u64 hash, bool lr) {
  for (auto& slot : m_gpu_eye_textures) {
    if (slot.fnv_name_hash == hash && slot.lr == lr) {
      auto* gpu_tex = slot.gpu_tex;
      if (gpu_tex) {
        return gpu_tex->gpu_textures.at(0).gl;
      } else {
        fmt::print("lookup eye failed for {} (1)\n", hash);
        return {};
      }
    }
  }
  fmt::print("lookup eye failed for {} (2)\n", hash);
  return {};
}

//////////////////////
// DMA Decode
//////////////////////

std::string EyeRenderer::SpriteInfo::print() const {
  std::string result;
  result += fmt::format("a: {:x} uv: ({}), ({}, {}) xyz: ({}, {}, {}), ({}, {}, {})", a, uv0,
                        uv1[0], uv1[1], xyz0[0], xyz0[1], xyz0[2], xyz1[0], xyz1[1], xyz1[2]);
  return result;
}

std::string EyeRenderer::ScissorInfo::print() const {
  return fmt::format("x : [{}, {}], y : [{}, {}]", x0, x1, y0, y1);
}

std::string EyeRenderer::EyeDraw::print() const {
  return fmt::format("{}\n{}\n", sprite.print(), scissor.print());
}