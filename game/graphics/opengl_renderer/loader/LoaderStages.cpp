#include "LoaderStages.h"

#include "CustomTextureReplacements.h"
#include "Loader.h"

#include "common/global_profiler/GlobalProfiler.h"

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials: add_texture reads the custom-assets toggle directly.
#include <algorithm>
#include <cmath>
#include <vector>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/loader/PbrTestPattern.h"
#endif

constexpr float LOAD_BUDGET = 4.5f;

#ifdef __ANDROID__
// GLES has no GL_UNSIGNED_INT_8_8_8_8_REV — glTexImage2D rejects it, the
// texture never gets storage, and every fr3 texture (font + level) samples
// BLACK as an incomplete texture (A41 run-3: zero pool misses yet a black
// frame). On little-endian, RGBA + UNSIGNED_BYTE is byte-identical — the
// same substitution as TexturePool::upload_to_gpu / FramebufferTexturePair.
constexpr GLenum kRgbaTexType = GL_UNSIGNED_BYTE;
#else
constexpr GLenum kRgbaTexType = GL_UNSIGNED_INT_8_8_8_8_REV;
#endif

#ifdef OG_FEAT_PBR
/*!
 * ROUND 20 — characteristic feature WAVELENGTH of a height map, in TILES (1 tile = the whole
 * texture), from the map's own mip-energy spectrum.
 *
 * The tessellation amplitude used to be a constant fraction of "relief", which is wrong: the
 * owner's checkerboard test showed the authored UV density is 2.28 m/tile (wallplaster) to
 * 7.90 m/tile (leafyground), so one amplitude means wildly different feature sizes on screen.
 * Scaling the amplitude by the FEATURE size needs that feature size, and this is where it comes
 * from: box-downsample the field until its variance has halved. The box size at that point is the
 * scale that carries the median energy; the wavelength is twice it.
 */
static float measure_height_lambda_tiles(const custom_tex::ReplacementImage* hi) {
  if (!hi || hi->w <= 0 || hi->h <= 0 || hi->rgba.size() < (size_t)hi->w * (size_t)hi->h * 4u) {
    return 0.25f;
  }
  // (a) R channel / 255, SUBSAMPLED so neither dimension exceeds 1024. Working entirely in the
  // subsampled domain is exact for the result, because lambda_tiles is a wavelength divided by the
  // width in the SAME domain.
  const int step = std::max(1, std::max(hi->w, hi->h) / 1024);
  const int cw0 = std::max(1, (hi->w + step - 1) / step);
  const int ch0 = std::max(1, (hi->h + step - 1) / step);
  std::vector<float> buf((size_t)cw0 * (size_t)ch0);
  for (int y = 0; y < ch0; y++) {
    for (int x = 0; x < cw0; x++) {
      const size_t src = ((size_t)(y * step) * (size_t)hi->w + (size_t)(x * step)) * 4u;
      buf[(size_t)y * (size_t)cw0 + (size_t)x] = hi->rgba[src] * (1.f / 255.f);
    }
  }
  auto variance = [](const std::vector<float>& v) -> double {
    if (v.empty()) {
      return 0.0;
    }
    double s = 0.0, s2 = 0.0;
    for (float f : v) {
      s += (double)f;
      s2 += (double)f * (double)f;
    }
    const double n = (double)v.size();
    const double mean = s / n;
    return std::max(s2 / n - mean * mean, 0.0);
  };
  // (b) a flat map has no feature scale at all.
  const double var0 = variance(buf);
  if (var0 < 1e-8) {
    return 0.25f;
  }
  // (c) halve the resolution until the variance has halved.
  const double target = 0.5 * var0;
  double var_prev = var0;
  int cw = cw0, ch = ch0;
  int l_last = 0;
  float l_star = 0.f;
  bool crossed = false;
  for (int l = 1; cw >= 2 && ch >= 2 && l <= 12; l++) {
    const int nw = cw / 2, nh = ch / 2;  // truncate odd dims
    std::vector<float> down((size_t)nw * (size_t)nh);
    for (int y = 0; y < nh; y++) {
      for (int x = 0; x < nw; x++) {
        const size_t r0 = (size_t)(2 * y) * (size_t)cw + (size_t)(2 * x);
        const size_t r1 = (size_t)(2 * y + 1) * (size_t)cw + (size_t)(2 * x);
        down[(size_t)y * (size_t)nw + (size_t)x] =
            0.25f * (buf[r0] + buf[r0 + 1] + buf[r1] + buf[r1 + 1]);
      }
    }
    buf.swap(down);
    cw = nw;
    ch = nh;
    l_last = l;
    const double var_l = variance(buf);
    if (var_l <= target) {
      // Interpolate the crossing in LOG variance, not linear. The spectrum between two mip levels
      // is geometric, and the linear form is biased by up to sqrt(2): on a perfect checker (the
      // owner's own reference pattern, whose answer is known exactly = 2 cells) the variance holds
      // flat and then collapses to 0, and a linear crossing lands mid-octave => 1.41x too long.
      // The log form returns the last full-energy level there, i.e. exactly 2 cells.
      double t = 0.0;
      if (var_prev > 0.0 && var_l > 0.0) {
        const double denom = std::log(var_prev) - std::log(var_l);
        t = (std::log(var_prev) - std::log(target)) / std::max(denom, 1e-12);
      }
      l_star = (float)((double)(l - 1) + std::clamp(t, 0.0, 1.0));
      crossed = true;
      break;
    }
    var_prev = var_l;
  }
  if (!crossed) {
    l_star = (float)l_last;
  }
  // (d) the wavelength is twice the box size at the median-energy scale.
  const float lambda_texels = std::exp2(l_star + 1.0f);
  const float lambda_tiles = lambda_texels / (float)std::max(cw0, ch0);
  // (e)
  return std::clamp(lambda_tiles, 1.0f / 1024.0f, 1.0f);
}
#endif

/*!
 * Upload a texture to the GPU, and give it to the pool.
 */
u64 add_texture(TexturePool& pool, const tfrag3::Texture& tex, bool is_common) {
  // External-asset-root: record every texture key (for the optional dump_keys
  // marker) and look up a user PNG replacement.
  custom_tex::dump_key(tex.debug_tpage_name, tex.debug_name);
  auto rep = custom_tex::lookup(tex.debug_tpage_name, tex.debug_name);

  GLuint gl_tex;
  glActiveTexture(GL_TEXTURE0);
  glGenTextures(1, &gl_tex);
  glBindTexture(GL_TEXTURE_2D, gl_tex);
#ifdef OG_FEAT_PBR
  // ROUND 20: the owner's CHECKERBOARD verification method, in-build. When the test pattern is on,
  // the BASE colour is replaced by a checker whose squares are a known fraction of one texture
  // TILE, so the painted square size and the displaced block size can be compared on screen.
  std::vector<u8> tp_base;
  const int tp_mode = pbr_testpattern::mode();
  const bool tp_any = tp_mode != 0 && Gfx::recharged_master_active();
  // Whether the pattern applies to THIS texture must be known BEFORE the base upload, but in mode 1
  // it depends on this material having PBR maps — which the block below only discovers much later.
  // has_suffixed() is the index-only existence probe (no file read, no PNG decode), so answer here.
  bool tp_apply = false;
  if (tp_any) {
    if (tp_mode == 2 || tp_mode == 4) {
      tp_apply = true;
    } else {
      const auto tp_bsrc = custom_tex::base_source(tex.debug_tpage_name, tex.debug_name);
      tp_apply =
          custom_tex::has_suffixed(tex.debug_tpage_name, tex.debug_name, "_normal", tp_bsrc) ||
          custom_tex::has_suffixed(tex.debug_tpage_name, tex.debug_name, "_roughness", tp_bsrc) ||
          custom_tex::has_suffixed(tex.debug_tpage_name, tex.debug_name, "_height", tp_bsrc);
    }
  }
  if (tp_apply) {
    // Mode 2 swaps EVERY texture in the level, so it uses a smaller map to bound VRAM.
    const int tp_dim = (tp_mode == 2 || tp_mode == 4) ? 128 : 256;
    // The buffer is written in RGBA byte order. kRgbaTexType is GL_UNSIGNED_BYTE on GLES and
    // GL_UNSIGNED_INT_8_8_8_8_REV on desktop, so a channel swap is possible per platform — the
    // checker itself is grey (R=G=B) and only the three orientation markers are coloured, so at
    // worst the marker colours permute. The test geometry is identical either way.
    pbr_testpattern::make_base_rgba(tp_base, tp_dim);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, tp_dim, tp_dim, 0, GL_RGBA, kRgbaTexType,
                 tp_base.data());
  } else
#endif
      if (rep) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, rep->w, rep->h, 0, GL_RGBA, kRgbaTexType,
                 rep->rgba.data());
  } else {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, tex.w, tex.h, 0, GL_RGBA, kRgbaTexType,
                 tex.data.data());
  }
  glGenerateMipmap(GL_TEXTURE_2D);
  float aniso = 0.0f;
  glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY, &aniso);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY, aniso);
  if (tex.load_to_pool) {
    TextureInput in;
    in.debug_page_name = tex.debug_tpage_name;
    in.debug_name = tex.debug_name;
    // Logical dims must stay the ORIGINAL texture's: src_data below points at the
    // baked buffer, and pool consumers read w*h*4 from it — replacement-sized dims
    // over the original buffer are an OOB crash when the user PNG is larger. The
    // GL object holds the (possibly higher-res) replacement; sampling is normalized.
    in.w = tex.w;
    in.h = tex.h;
    in.gpu_texture = gl_tex;
    in.common = is_common;
    in.id = PcTextureId::from_combo_id(tex.combo_id);
    // src_data is stored as a long-lived pointer by the pool (used for texture
    // animation source comparison). The replacement's rgba buffer is local, so
    // keep src_data pointing at the baked level data even when the GPU texture
    // was swapped for a user PNG.
    in.src_data = (const u8*)tex.data.data();
    pool.give_texture(in);
  }

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: create the companion PBR maps for this texture from
  // suffixed PNGs (user dir or the package-bundled set; see lookup_suffixed for source gating).
  // Grecharged-bundled-textures: PBR maps may come from the USER dir (load_custom_assets-
  // gated inside lookup_suffixed) or the package-BUNDLED set (master-gated) — probe whenever
  // the master is up; lookup_suffixed applies the per-source gates.
  if (Gfx::recharged_master_active()) {
    const auto bsrc = custom_tex::base_source(tex.debug_tpage_name, tex.debug_name);
    // NOTE: lookup_suffixed returns a pointer into a single per-call thread-local
    // buffer, reused on the next call — so capture each map's source string
    // immediately after its probe, before the next lookup_suffixed() call.
    const auto* n =
        custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_normal", bsrc);
    const char* n_src = n ? n->src : "-";
    const auto* r =
        custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_roughness", bsrc);
    const char* r_src = r ? r->src : "-";
    const auto* m =
        custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_metallic", bsrc);
    const char* m_src = m ? m->src : "-";
    const auto* a =
        custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_ao", bsrc);
    const char* a_src = a ? a->src : "-";
    const auto* h =
        custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_height", bsrc);
    const char* h_src = h ? h->src : "-";
    const auto* s =
        custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_specular", bsrc);
    const char* s_src = s ? s->src : "-";
    const auto* e =
        custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_emissive", bsrc);
    const char* e_src = e ? e->src : "-";
    // NOTE: lookup_suffixed returns a pointer into a single per-call thread-local
    // buffer, so it must be consumed (uploaded) before the next call. Below we
    // re-fetch each map immediately before its upload to keep that contract.
    const char* bsrc_str = bsrc == custom_tex::BaseSource::User      ? "user"
                           : bsrc == custom_tex::BaseSource::Bundled ? "bundled"
                                                                     : "stock";
    // ROUND 20: with the test pattern on, register the material EVEN IF it has no real maps —
    // in mode 2 that is the whole point (every surface gets the checker N/R/H).
    if (n || r || m || h || s || e || tp_apply) {
      auto make_map = [&](const custom_tex::ReplacementImage* img) -> u32 {
        if (!img) {
          return 0;
        }
        GLuint id = 0;
        glGenTextures(1, &id);
        glBindTexture(GL_TEXTURE_2D, id);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img->w, img->h, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                     img->rgba.data());
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        return id;
      };
      custom_tex::PbrMaterialMaps maps;
      // Re-fetch each present map immediately before upload (thread-local buffer reuse).
      if (n) {
        const auto* ni =
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_normal", bsrc);
        if (ni && !ni->rgba.empty()) {
          // NORMAL-MAP DC (owner A/B relief 0 vs 2.5, 2026-07-24). Mean tangent-space surface
          // gradient over the decoded bytes, exactly as the shader decodes them (linear GL_RGBA,
          // no sRGB): g = clamp(n.xy / max(n.z, 0.05), +-4). A non-zero mean is a CONSTANT TILT of
          // the whole material — not relief. The relief slider multiplies it (x7.5 at relief 2.5),
          // so it re-aims entire mapped regions away from the sun => the hard dark/light plates
          // that scale with relief and vanish at relief 0, exactly as the owner's A/B measured.
          // The shader subtracts this so the perturbation is zero-mean: relief, no plate.
          double sx = 0.0, sy = 0.0;
          u64 np = 0;
          for (size_t i = 0; i + 3 < ni->rgba.size(); i += 4) {
            float nx = ni->rgba[i] * (2.f / 255.f) - 1.f;
            float ny = ni->rgba[i + 1] * (2.f / 255.f) - 1.f;
            float nz = std::max(ni->rgba[i + 2] * (2.f / 255.f) - 1.f, 0.05f);
            sx += std::clamp(nx / nz, -4.f, 4.f);
            sy += std::clamp(ny / nz, -4.f, 4.f);
            np++;
          }
          if (np) {
            maps.normal_dc_x = (float)(sx / (double)np);
            maps.normal_dc_y = (float)(sy / (double)np);
          }
          lg::info(
              "pbr normal DC: {} src={} {}x{} mean_gradient=({:.4f}, {:.4f}) tilt={:.2f}deg "
              "(subtracted in-shader => zero-mean relief, no brightness plate)",
              tex.debug_name, ni->src, ni->w, ni->h, maps.normal_dc_x, maps.normal_dc_y,
              (float)(std::atan(std::sqrt(maps.normal_dc_x * maps.normal_dc_x +
                                          maps.normal_dc_y * maps.normal_dc_y)) *
                      180.0 / 3.14159265358979));
        }
        maps.normal_tex = make_map(ni);
      }
      if (r) {
        const auto* ri =
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_roughness", bsrc);
        if (ri && !ri->rgba.empty()) {
          // Device-truth roughness audit (owner REOPEN #2): stats of the DECODED bytes
          // exactly as uploaded — internalformat GL_RGBA (linear, NO sRGB decode), the
          // shader samples channel R as PERCEPTUAL roughness (alpha = r^2, floor 0.045).
          u32 mn = 255, mx = 0;
          u64 sum = 0, npx = 0;
          for (size_t i = 0; i + 3 < ri->rgba.size(); i += 4) {
            u32 v = ri->rgba[i];
            mn = std::min(mn, v);
            mx = std::max(mx, v);
            sum += v;
            npx++;
          }
          lg::info(
              "pbr roughness data: {} src={} {}x{} upload=GL_RGBA(linear,no-sRGB) chan=R "
              "min={:.3f} mean={:.3f} max={:.3f} (perceptual; shader alpha=r^2 floor=0.045)",
              tex.debug_name, ri->src, ri->w, ri->h, mn / 255.f,
              npx ? (float)(sum / (double)npx / 255.0) : 0.f, mx / 255.f);
        }
        maps.rough_tex = make_map(ri);
      }
      if (m) {
        maps.metal_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_metallic", bsrc));
      }
      if (a) {
        maps.ao_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_ao", bsrc));
      }
      if (h) {
        const auto* hi =
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_height", bsrc);
        if (hi && hi->rgba.size() >= 4) {
          // HEIGHT-MAP STATISTICS (owner playtest #17 "glorified bump"). The shader's naive
          // (h - 0.5) assumes every height map is mean-centred and spans the full 0..1 — the
          // shipped maps are neither (leafyground 0.063..0.463 mean 0.322; wallplaster mean
          // 0.807; strawroof 0.298..0.478). That both displaces whole materials net-inward /
          // net-outward and uses only 18-75% of the nominal amplitude. Measure the mean and a
          // robust (2nd..98th percentile, outlier-proof) half-range here, exactly as the shader
          // decodes them (linear GL_RGBA, no sRGB, channel R), and push them as a uniform so the
          // shader can recentre + rescale per material.
          u64 hist[256] = {};
          u64 sum = 0, npx = 0;
          for (size_t i = 0; i + 3 < hi->rgba.size(); i += 4) {
            u32 v = hi->rgba[i];
            hist[v]++;
            sum += v;
            npx++;
          }
          if (npx) {
            float mean = (float)(sum / (double)npx / 255.0);
            // 2nd / 98th percentile from the histogram's cumulative counts.
            u64 lo_target = (u64)(npx * 0.02);
            u64 hi_target = (u64)(npx * 0.98);
            u64 cum = 0;
            int p2_b = 0, p98_b = 255;
            bool got_p2 = false, got_p98 = false;
            for (int b = 0; b < 256; b++) {
              cum += hist[b];
              if (!got_p2 && cum >= lo_target) {
                p2_b = b;
                got_p2 = true;
              }
              if (!got_p98 && cum >= hi_target) {
                p98_b = b;
                got_p98 = true;
              }
            }
            float p2 = p2_b / 255.f;
            float p98 = p98_b / 255.f;
            float half = std::max(p98 - mean, mean - p2);
            // A constant (or near-constant) map must not divide by ~0.
            half = std::max(half, 2.f / 255.f);
            maps.height_mean = mean;
            maps.height_norm = std::clamp(0.5f / half, 0.5f, 16.0f);
            // ROUND 20: the map's own feature scale, so the tessellation amplitude can follow the
            // FEATURE size instead of a constant (the authored UV density varies 2.28..7.90 m/tile
            // across this level, so a constant amplitude means a different look per material).
            maps.height_lambda_tiles = measure_height_lambda_tiles(hi);
            lg::info(
                "pbr height stat: {} src={} {}x{} mean={:.4f} p2={:.4f} p98={:.4f} half={:.4f} "
                "norm={:.3f} (shader: (h-mean)*norm+0.5 => mean-centred, amplitude refilled) "
                "lambda_tiles={:.4f} (feature wavelength; x tile_m = feature world size)",
                tex.debug_name, hi->src, hi->w, hi->h, mean, p2, p98, half, maps.height_norm,
                maps.height_lambda_tiles);
          }
        }
        maps.height_tex = make_map(hi);
      }
      if (s) {
        maps.specular_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_specular", bsrc));
      }
      if (e) {
        maps.emissive_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_emissive", bsrc));
      }
      if (tp_apply) {
        // Checker N/R/H replace whatever this material had; metal/ao/spec/emissive are dropped so
        // the test isolates displacement + normal orientation + roughness response.
        const auto& sm = pbr_testpattern::shared_maps();
        for (GLuint own : {maps.normal_tex, maps.rough_tex, maps.metal_tex, maps.ao_tex,
                           maps.height_tex, maps.specular_tex, maps.emissive_tex}) {
          if (own && !pbr_testpattern::owns(own)) {
            glDeleteTextures(1, &own);
          }
        }
        maps = custom_tex::PbrMaterialMaps{};
        maps.normal_tex = sm.normal_tex;
        maps.rough_tex = sm.rough_tex;
        maps.height_tex = sm.height_tex;
        maps.height_mean = 0.5f;  // the checker IS mean-centred and full-range
        maps.height_norm = 1.0f;
        maps.normal_dc_x = 0.f;  // and symmetric => zero DC
        maps.normal_dc_y = 0.f;
        // A checker's feature wavelength is exactly TWO cells, and there are squares_per_tile()
        // cells per tile — so it is known analytically, no measurement needed. (The estimator
        // returns this exact value on a checker, which is how it was calibrated.)
        maps.height_lambda_tiles = 2.0f / (float)pbr_testpattern::squares_per_tile();
        lg::info("pbr TESTPATTERN: {} base=CHECKER maps=CHECKER(N,R,H) squares/tile={} mode={}",
                 tex.debug_name, pbr_testpattern::squares_per_tile(), tp_mode);
      }
      // Overwrite registry; free any stale GL ids from a prior level load of the same name.
      auto prev = custom_tex::register_pbr_material(tex.debug_name, maps);
      GLuint old_ids[7] = {prev.normal_tex, prev.rough_tex,    prev.metal_tex,   prev.ao_tex,
                           prev.height_tex, prev.specular_tex, prev.emissive_tex};
      for (GLuint oid : old_ids) {
        // NEVER delete the shared checker ids: every material points at the same three.
        if (oid && !pbr_testpattern::owns(oid)) {
          glDeleteTextures(1, &oid);
        }
      }
      // Restore the base texture binding on unit 0 (what the surrounding loader
      // flow left bound before this block).
      glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_2D, gl_tex);
      // Per-texture binding log (owner REOPEN #2) — correlates base source, per-map
      // source, and the shader defaults so mixed provenance / missing maps are visible.
      lg::info(
          "pbr binding: {} base={} N={} R={} M={} AO={} H={} S={} E={} defaults[rough=0.9 "
          "metal=0 ao=1]",
          tex.debug_name, bsrc_str, n_src, r ? r_src : "-", m ? m_src : "-", a ? a_src : "-",
          h ? h_src : "-", s ? s_src : "-", e ? e_src : "-");
    } else {
      // Maps existed but same-source pairing / absence yielded NONE — make the
      // mixed-provenance suppression visible per texture.
      lg::info("pbr binding: {} base={} maps=NONE (same-source pairing / no maps)",
               tex.debug_name, bsrc_str);
    }
  }
#endif

  return gl_tex;
}

class TextureLoaderStage : public LoaderStage {
 public:
  TextureLoaderStage() : LoaderStage("texture") {}
  bool run(Timer& timer, LoaderInput& data) override {
    constexpr int MAX_TEX_BYTES_PER_FRAME = 1024 * 1024;

    int bytes_this_run = 0;
    int tex_this_run = 0;
    if (data.lev_data->textures.size() < data.lev_data->level->textures.size()) {
      std::unique_lock<std::mutex> tpool_lock(data.tex_pool->mutex());
      while (data.lev_data->textures.size() < data.lev_data->level->textures.size()) {
        auto& tex = data.lev_data->level->textures[data.lev_data->textures.size()];
        data.lev_data->textures.push_back(add_texture(*data.tex_pool, tex, false));
        bytes_this_run += tex.w * tex.h * 4;
        tex_this_run++;
        if (tex_this_run > 20) {
          break;
        }
        if (bytes_this_run > MAX_TEX_BYTES_PER_FRAME || timer.getMs() > LOAD_BUDGET) {
          break;
        }
      }
    }
    return data.lev_data->textures.size() == data.lev_data->level->textures.size();
  }
  void reset() override {}
};

class TfragLoadStage : public LoaderStage {
 public:
  TfragLoadStage() : LoaderStage("tfrag") {}
  bool run(Timer& timer, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (data.lev_data->level->tfrag_trees.front().empty()) {
      m_done = true;
      return true;
    }

    if (!m_opengl_created) {
      for (int geo = 0; geo < tfrag3::TFRAG_GEOS; geo++) {
        auto& in_trees = data.lev_data->level->tfrag_trees[geo];
        for (auto& in_tree : in_trees) {
          GLuint& tree_out = data.lev_data->tfrag_vertex_data[geo].emplace_back();
          glGenBuffers(1, &tree_out);
          glBindBuffer(GL_ARRAY_BUFFER, tree_out);
          glBufferData(GL_ARRAY_BUFFER,
                       in_tree.unpacked.vertices.size() * sizeof(tfrag3::PreloadedVertex), nullptr,
                       GL_STATIC_DRAW);
          // REOPEN#7: parallel per-vertex tangent VBO (vec4 = xyz world tangent + w handedness).
          // Small (16 B/vert), one-shot upload here. emplace_back keeps it 1:1 with
          // tfrag_vertex_data[geo].
          GLuint& tan_out = data.lev_data->tfrag_tangent_data[geo].emplace_back();
          glGenBuffers(1, &tan_out);
          glBindBuffer(GL_ARRAY_BUFFER, tan_out);
          glBufferData(GL_ARRAY_BUFFER,
                       in_tree.unpacked.tangents.size() * sizeof(math::Vector4f),
                       in_tree.unpacked.tangents.data(), GL_STATIC_DRAW);
        }
      }
      m_opengl_created = true;
      return false;
    }

    constexpr u32 CHUNK_SIZE = 32768;
    u32 uploaded_bytes = 0;
    [[maybe_unused]] u32 unique_buffers = 0;

    while (true) {
      bool complete_tree;

      if (data.lev_data->level->tfrag_trees[m_next_geo].empty()) {
        complete_tree = true;
      } else {
        const auto& tree = data.lev_data->level->tfrag_trees[m_next_geo][m_next_tree];
        u32 end_vert_in_tree = tree.unpacked.vertices.size();
        // the number of vertices we'd need to finish the tree right now
        size_t num_verts_left_in_tree = end_vert_in_tree - m_next_vert;
        size_t start_vert_for_chunk;
        size_t end_vert_for_chunk;

        if (num_verts_left_in_tree > CHUNK_SIZE) {
          complete_tree = false;
          // should only do partial
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = start_vert_for_chunk + CHUNK_SIZE;
          m_next_vert += CHUNK_SIZE;
        } else {
          // should do all!
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = end_vert_in_tree;
          complete_tree = true;
        }

        glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->tfrag_vertex_data[m_next_geo][m_next_tree]);
        u32 upload_size =
            (end_vert_for_chunk - start_vert_for_chunk) * sizeof(tfrag3::PreloadedVertex);
        glBufferSubData(GL_ARRAY_BUFFER, start_vert_for_chunk * sizeof(tfrag3::PreloadedVertex),
                        upload_size, tree.unpacked.vertices.data() + start_vert_for_chunk);
        uploaded_bytes += upload_size;
      }

      if (complete_tree) {
        unique_buffers++;
        // and move on to next tree
        m_next_vert = 0;
        m_next_tree++;
        if (m_next_tree >= data.lev_data->level->tfrag_trees[m_next_geo].size()) {
          m_next_tree = 0;
          m_next_geo++;
          if (m_next_geo >= tfrag3::TFRAG_GEOS) {
            m_next_tree = true;
            m_next_tree = 0;
            m_next_geo = 0;
            m_next_vert = 0;
            m_done = true;
            return true;
          }
        }
        return false;
      }

      if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 1024) > 2048) {
        return false;
      }
    }
  }

  void reset() override {
    m_done = false;
    m_opengl_created = false;
    m_next_geo = 0;
    m_next_tree = 0;
    m_next_vert = 0;
  }

 private:
  bool m_done = false;
  bool m_opengl_created = false;
  u32 m_next_geo = 0;
  u32 m_next_tree = 0;
  u32 m_next_vert = 0;
};

class ShrubLoadStage : public LoaderStage {
 public:
  ShrubLoadStage() : LoaderStage("shrub") {}
  bool run(Timer& timer, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (data.lev_data->level->shrub_trees.empty()) {
      m_done = true;
      return true;
    }

    if (!m_opengl_created) {
      for (auto& in_tree : data.lev_data->level->shrub_trees) {
        GLuint& tree_out = data.lev_data->shrub_vertex_data.emplace_back();
        glGenBuffers(1, &tree_out);
        glBindBuffer(GL_ARRAY_BUFFER, tree_out);
        glBufferData(GL_ARRAY_BUFFER,
                     in_tree.unpacked.vertices.size() * sizeof(tfrag3::ShrubGpuVertex), nullptr,
                     GL_STATIC_DRAW);
      }
      m_opengl_created = true;
      return false;
    }

    constexpr u32 CHUNK_SIZE = 32768;
    u32 uploaded_bytes = 0;

    while (true) {
      const auto& tree = data.lev_data->level->shrub_trees[m_next_tree];
      u32 end_vert_in_tree = tree.unpacked.vertices.size();
      // the number of vertices we'd need to finish the tree right now
      size_t num_verts_left_in_tree = end_vert_in_tree - m_next_vert;
      size_t start_vert_for_chunk;
      size_t end_vert_for_chunk;

      bool complete_tree;

      if (num_verts_left_in_tree > CHUNK_SIZE) {
        complete_tree = false;
        // should only do partial
        start_vert_for_chunk = m_next_vert;
        end_vert_for_chunk = start_vert_for_chunk + CHUNK_SIZE;
        m_next_vert += CHUNK_SIZE;
      } else {
        // should do all!
        start_vert_for_chunk = m_next_vert;
        end_vert_for_chunk = end_vert_in_tree;
        complete_tree = true;
      }

      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->shrub_vertex_data[m_next_tree]);
      u32 upload_size =
          (end_vert_for_chunk - start_vert_for_chunk) * sizeof(tfrag3::ShrubGpuVertex);
      glBufferSubData(GL_ARRAY_BUFFER, start_vert_for_chunk * sizeof(tfrag3::ShrubGpuVertex),
                      upload_size, tree.unpacked.vertices.data() + start_vert_for_chunk);
      uploaded_bytes += upload_size;

      if (complete_tree) {
        // and move on to next tree
        m_next_vert = 0;
        m_next_tree++;
        if (m_next_tree >= data.lev_data->level->shrub_trees.size()) {
          m_done = true;
          return true;
        }
      }

      if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 128) > 2048) {
        return false;
      }
    }
  }

  void reset() override {
    m_done = false;
    m_opengl_created = false;
    m_next_tree = 0;
    m_next_vert = 0;
  }

 private:
  bool m_done = false;
  bool m_opengl_created = false;
  u32 m_next_tree = 0;
  u32 m_next_vert = 0;
};

class TieLoadStage : public LoaderStage {
 public:
  TieLoadStage() : LoaderStage("tie") {}
  bool run(Timer& timer, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (data.lev_data->level->tie_trees.front().empty()) {
      m_done = true;
      return true;
    }

    if (!m_opengl_created) {
      auto evt = scoped_prof("tie-opengl-create");
      for (int geo = 0; geo < tfrag3::TIE_GEOS; geo++) {
        auto& in_trees = data.lev_data->level->tie_trees[geo];
        for (auto& in_tree : in_trees) {
          LevelData::TieOpenGL& tree_out = data.lev_data->tie_data[geo].emplace_back();
          glGenBuffers(1, &tree_out.vertex_buffer);
          glBindBuffer(GL_ARRAY_BUFFER, tree_out.vertex_buffer);
          glBufferData(GL_ARRAY_BUFFER,
                       in_tree.unpacked.vertices.size() * sizeof(tfrag3::PreloadedVertex), nullptr,
                       GL_STATIC_DRAW);

          glGenBuffers(1, &tree_out.index_buffer);
          glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree_out.index_buffer);
          glBufferData(GL_ELEMENT_ARRAY_BUFFER, in_tree.unpacked.indices.size() * sizeof(u32),
                       nullptr, GL_STATIC_DRAW);

          // REOPEN#7: parallel per-vertex tangent VBO for TIE (non-envmap TIE draws use the
          // TFRAG3 shader).
          glGenBuffers(1, &tree_out.tangent_buffer);
          glBindBuffer(GL_ARRAY_BUFFER, tree_out.tangent_buffer);
          glBufferData(GL_ARRAY_BUFFER,
                       in_tree.unpacked.tangents.size() * sizeof(math::Vector4f),
                       in_tree.unpacked.tangents.data(), GL_STATIC_DRAW);
        }
      }
      m_opengl_created = true;
      return false;
    }

    if (!m_verts_done) {
      auto evt = scoped_prof("tie-verts");
      constexpr u32 CHUNK_SIZE = 32768;
      u32 uploaded_bytes = 0;

      while (true) {
        const auto& tree = data.lev_data->level->tie_trees[m_next_geo][m_next_tree];
        u32 end_vert_in_tree = tree.unpacked.vertices.size();
        // the number of vertices we'd need to finish the tree right now
        size_t num_verts_left_in_tree = end_vert_in_tree - m_next_vert;
        size_t start_vert_for_chunk;
        size_t end_vert_for_chunk;

        bool complete_tree;

        if (num_verts_left_in_tree > CHUNK_SIZE) {
          complete_tree = false;
          // should only do partial
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = start_vert_for_chunk + CHUNK_SIZE;
          m_next_vert += CHUNK_SIZE;
        } else {
          // should do all!
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = end_vert_in_tree;
          complete_tree = true;
        }

        glBindBuffer(GL_ARRAY_BUFFER,
                     data.lev_data->tie_data[m_next_geo][m_next_tree].vertex_buffer);
        u32 upload_size =
            (end_vert_for_chunk - start_vert_for_chunk) * sizeof(tfrag3::PreloadedVertex);
        {
          auto bsd = scoped_prof(fmt::format("buffer-{}k", upload_size / 1024).c_str());
          glBufferSubData(GL_ARRAY_BUFFER, start_vert_for_chunk * sizeof(tfrag3::PreloadedVertex),
                          upload_size, tree.unpacked.vertices.data() + start_vert_for_chunk);
        }

        uploaded_bytes += upload_size;

        if (complete_tree) {
          // and move on to next tree
          m_next_vert = 0;
          m_next_tree++;
          if (m_next_tree >= data.lev_data->level->tie_trees[m_next_geo].size()) {
            m_next_tree = 0;
            m_next_geo++;
            while (m_next_geo < tfrag3::TIE_GEOS &&
                   data.lev_data->level->tie_trees[m_next_geo].empty()) {
              m_next_geo++;
            }
            if (m_next_geo >= tfrag3::TIE_GEOS) {
              m_verts_done = true;
              m_next_tree = 0;
              m_next_geo = 0;
              m_next_vert = 0;
              return false;
            }
          }
        }

        if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 1024) > 2048) {
          return false;
        }
      }
    }

    if (!m_wind_indices_done) {
      auto evt = scoped_prof("tie-wind");
      bool abort = false;
      for (; m_next_geo < tfrag3::TIE_GEOS; m_next_geo++) {
        auto& geo_trees = data.lev_data->level->tie_trees[m_next_geo];
        for (; m_next_tree < geo_trees.size(); m_next_tree++) {
          if (abort) {
            return false;
          }
          auto& in_tree = geo_trees[m_next_tree];
          auto& out_tree = data.lev_data->tie_data[m_next_geo][m_next_tree];
          size_t wind_idx_buffer_len = 0;
          for (auto& draw : in_tree.instanced_wind_draws) {
            wind_idx_buffer_len += draw.vertex_index_stream.size();
          }
          if (wind_idx_buffer_len > 0) {
            out_tree.has_wind = true;
            glGenBuffers(1, &out_tree.wind_indices);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, out_tree.wind_indices);
            std::vector<u32> temp;
            temp.resize(wind_idx_buffer_len);
            u32 off = 0;
            for (auto& draw : in_tree.instanced_wind_draws) {
              memcpy(temp.data() + off, draw.vertex_index_stream.data(),
                     draw.vertex_index_stream.size() * sizeof(u32));
              off += draw.vertex_index_stream.size();
            }

            glBufferData(GL_ELEMENT_ARRAY_BUFFER, wind_idx_buffer_len * sizeof(u32), temp.data(),
                         GL_STATIC_DRAW);
            abort = true;
          }
        }
        m_next_tree = 0;
      }

      m_wind_indices_done = true;
      m_next_geo = 0;
      m_next_vert = 0;
      m_next_tree = 0;

      if (timer.getMs() > LOAD_BUDGET) {
        return false;
      }
    }

    if (!m_indices_done) {
      auto evt = scoped_prof("tie-ind");
      constexpr u32 CHUNK_SIZE = 32768 * 8;
      u32 uploaded_bytes = 0;

      while (true) {
        const auto& tree = data.lev_data->level->tie_trees[m_next_geo][m_next_tree];
        u32 end_ind_in_tree = tree.unpacked.indices.size();
        // the number of indices we'd need to finish the tree right now
        size_t num_inds_left_in_tree = end_ind_in_tree - m_next_vert;
        size_t start_ind_for_chunk;
        size_t end_ind_for_chunk;

        bool complete_tree;

        if (num_inds_left_in_tree > CHUNK_SIZE) {
          complete_tree = false;
          // should only do partial
          start_ind_for_chunk = m_next_vert;
          end_ind_for_chunk = start_ind_for_chunk + CHUNK_SIZE;
          m_next_vert += CHUNK_SIZE;
        } else {
          // should do all!
          start_ind_for_chunk = m_next_vert;
          end_ind_for_chunk = end_ind_in_tree;
          complete_tree = true;
        }

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
                     data.lev_data->tie_data[m_next_geo][m_next_tree].index_buffer);
        u32 upload_size = (end_ind_for_chunk - start_ind_for_chunk) * sizeof(u32);
        glBufferSubData(GL_ELEMENT_ARRAY_BUFFER, start_ind_for_chunk * sizeof(u32), upload_size,
                        tree.unpacked.indices.data() + start_ind_for_chunk);
        uploaded_bytes += upload_size;

        if (complete_tree) {
          // and move on to next tree
          m_next_vert = 0;
          m_next_tree++;
          if (m_next_tree >= data.lev_data->level->tie_trees[m_next_geo].size()) {
            m_next_tree = 0;
            m_next_geo++;
            while (m_next_geo < tfrag3::TIE_GEOS &&
                   data.lev_data->level->tie_trees[m_next_geo].empty()) {
              m_next_geo++;
            }
            if (m_next_geo >= tfrag3::TIE_GEOS) {
              m_indices_done = true;
              m_next_tree = 0;
              m_next_geo = 0;
              m_next_vert = 0;
              m_done = true;
              return true;
            }
          }
        }

        if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 1024) > 2048) {
          return false;
        }
      }
    }

    return false;
  }

  void reset() override {
    m_done = false;
    m_opengl_created = false;
    m_next_geo = 0;
    m_next_tree = 0;
    m_next_vert = 0;
    m_verts_done = false;
    m_indices_done = false;
    m_wind_indices_done = false;
  }

 private:
  bool m_done = false;
  bool m_opengl_created = false;
  bool m_verts_done = false;
  bool m_indices_done = false;
  bool m_wind_indices_done = false;
  u32 m_next_geo = 0;
  u32 m_next_tree = 0;
  u32 m_next_vert = 0;
};

class CollideLoaderStage : public LoaderStage {
 public:
  CollideLoaderStage() : LoaderStage("collide") {}
  bool run(Timer& /*timer*/, LoaderInput& data) override {
    if (m_done) {
      return true;
    }
    if (!m_opengl_created) {
      glGenBuffers(1, &data.lev_data->collide_vertices);
      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->collide_vertices);
      glBufferData(
          GL_ARRAY_BUFFER,
          data.lev_data->level->collision.vertices.size() * sizeof(tfrag3::CollisionMesh::Vertex),
          nullptr, GL_STATIC_DRAW);
      m_opengl_created = true;
      return false;
    }

    u32 start = m_vtx;
    u32 end = std::min((u32)data.lev_data->level->collision.vertices.size(), start + 32768);
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->collide_vertices);
    glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(tfrag3::CollisionMesh::Vertex),
                    (end - start) * sizeof(tfrag3::CollisionMesh::Vertex),
                    data.lev_data->level->collision.vertices.data() + start);
    m_vtx = end;

    if (m_vtx == data.lev_data->level->collision.vertices.size()) {
      m_done = true;
      return true;
    } else {
      return false;
    }
  }
  void reset() override {
    m_opengl_created = false;
    m_vtx = 0;
    m_done = false;
  }

 private:
  bool m_opengl_created = false;
  u32 m_vtx = 0;
  bool m_done = false;
};

class StallLoaderStage : public LoaderStage {
 public:
  StallLoaderStage() : LoaderStage("stall") {}
  bool run(Timer&, LoaderInput& /*data*/) override {
    m_count++;
    if (m_count > 10) {
      return true;
    }
    return false;
  }

  void reset() override { m_count = 0; }

 private:
  int m_count = 0;
};

class HfragLoaderStage : public LoaderStage {
 public:
  HfragLoaderStage() : LoaderStage("hfrag") {}
  void reset() override {
    m_done = false;
    m_opengl = false;
    m_vtx_uploaded = false;
    m_idx = 0;
  }

  bool run(Timer&, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (!m_opengl) {
      glGenBuffers(1, &data.lev_data->hfrag_indices);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, data.lev_data->hfrag_indices);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                   data.lev_data->level->hfrag.indices.size() * sizeof(u32), nullptr,
                   GL_STATIC_DRAW);

      glGenBuffers(1, &data.lev_data->hfrag_vertices);
      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->hfrag_vertices);
      glBufferData(GL_ARRAY_BUFFER,
                   data.lev_data->level->hfrag.vertices.size() * sizeof(tfrag3::HfragmentVertex),
                   nullptr, GL_STATIC_DRAW);
      m_opengl = true;
    }

    if (!m_vtx_uploaded) {
      u32 start = m_idx;
      m_idx = std::min(start + 32768, (u32)data.lev_data->level->hfrag.indices.size());
      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->hfrag_indices);
      glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(u32), (m_idx - start) * sizeof(u32),
                      data.lev_data->level->hfrag.indices.data() + start);
      if (m_idx != data.lev_data->level->hfrag.indices.size()) {
        return false;
      } else {
        m_idx = 0;
        m_vtx_uploaded = true;
      }
    }

    u32 start = m_idx;
    m_idx = std::min(start + 32768, (u32)data.lev_data->level->hfrag.vertices.size());
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->hfrag_vertices);
    glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(tfrag3::HfragmentVertex),
                    (m_idx - start) * sizeof(tfrag3::HfragmentVertex),
                    data.lev_data->level->hfrag.vertices.data() + start);

    if (m_idx != data.lev_data->level->hfrag.vertices.size()) {
      return false;
    } else {
      m_done = true;
      return true;
    }
    return true;
  }

 private:
  bool m_done = false;
  bool m_opengl = false;
  bool m_vtx_uploaded = false;
  u32 m_idx = 0;
};

MercLoaderStage::MercLoaderStage() : LoaderStage("merc") {}
void MercLoaderStage::reset() {
  m_done = false;
  m_opengl = false;
  m_vtx_uploaded = false;
  m_idx = 0;
}

bool MercLoaderStage::run(Timer& /*timer*/, LoaderInput& data) {
  if (m_done) {
    return true;
  }

  if (!m_opengl) {
    glGenBuffers(1, &data.lev_data->merc_indices);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, data.lev_data->merc_indices);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                 data.lev_data->level->merc_data.indices.size() * sizeof(u32), nullptr,
                 GL_STATIC_DRAW);

    glGenBuffers(1, &data.lev_data->merc_vertices);
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->merc_vertices);
    glBufferData(GL_ARRAY_BUFFER,
                 data.lev_data->level->merc_data.vertices.size() * sizeof(tfrag3::MercVertex),
                 nullptr, GL_STATIC_DRAW);
    m_opengl = true;
  }

  if (!m_vtx_uploaded) {
    u32 start = m_idx;
    m_idx = std::min(start + 32768, (u32)data.lev_data->level->merc_data.indices.size());
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->merc_indices);
    glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(u32), (m_idx - start) * sizeof(u32),
                    data.lev_data->level->merc_data.indices.data() + start);
    if (m_idx != data.lev_data->level->merc_data.indices.size()) {
      return false;
    } else {
      m_idx = 0;
      m_vtx_uploaded = true;
    }
  }

  u32 start = m_idx;
  m_idx = std::min(start + 32768, (u32)data.lev_data->level->merc_data.vertices.size());
  glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->merc_vertices);
  glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(tfrag3::MercVertex),
                  (m_idx - start) * sizeof(tfrag3::MercVertex),
                  data.lev_data->level->merc_data.vertices.data() + start);

  if (m_idx != data.lev_data->level->merc_data.vertices.size()) {
    return false;
  } else {
#ifdef __ANDROID__
    // F1a: Adreno 618 (V@0502) SIGSEGVs inside the driver (null+0x28) on
    // specific merc glDrawElements after this stage's chunked
    // glBufferSubData uploads — deterministically, with state-legal,
    // GPU==CPU-verified data (F1a runs 4-16). A read-only
    // glMapBufferRange+unmap of the buffer DEFUSES the draw every time
    // (run-16: the killer draw executed exactly while a per-draw map-sync
    // probe was active and faulted on the first frame past the probe's
    // cap). Force the driver to finalize both BOs once at upload
    // completion — one-time per level, read-only, no behavioral change.
    for (GLenum tgt : {(GLenum)GL_ELEMENT_ARRAY_BUFFER, (GLenum)GL_ARRAY_BUFFER}) {
      GLuint buf = (tgt == GL_ELEMENT_ARRAY_BUFFER) ? data.lev_data->merc_indices
                                                    : data.lev_data->merc_vertices;
      glBindBuffer(tgt, buf);
      GLint64 sz = 0;
      glGetBufferParameteri64v(tgt, GL_BUFFER_SIZE, &sz);
      if (sz > 0) {
        void* p = glMapBufferRange(tgt, 0, (GLsizeiptr)sz, GL_MAP_READ_BIT);
        if (p) {
          glUnmapBuffer(tgt);
        }
      }
      glBindBuffer(tgt, 0);
    }
#endif
    m_done = true;
    for (auto& model : data.lev_data->level->merc_data.models) {
      data.lev_data->merc_model_lookup[model.name] = &model;
      (*data.mercs)[model.name].push_back({&model, data.lev_data->load_id, data.lev_data});
    }
    return true;
  }
  return true;
}

std::vector<std::unique_ptr<LoaderStage>> make_loader_stages() {
  std::vector<std::unique_ptr<LoaderStage>> ret;
  ret.push_back(std::make_unique<TieLoadStage>());
  ret.push_back(std::make_unique<TextureLoaderStage>());
  ret.push_back(std::make_unique<TfragLoadStage>());
  ret.push_back(std::make_unique<ShrubLoadStage>());
  ret.push_back(std::make_unique<CollideLoaderStage>());
  ret.push_back(std::make_unique<MercLoaderStage>());
  ret.push_back(std::make_unique<HfragLoaderStage>());
  ret.push_back(std::make_unique<StallLoaderStage>());
  return ret;
}
