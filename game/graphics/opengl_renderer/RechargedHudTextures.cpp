#include "RechargedHudTextures.h"

#include <cstdlib>

#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/pipelines/opengl.h"
#include "third-party/stb_image/stb_image.h"

// Box-downscale by an integer factor with alpha-weighted color averaging
// (plain averaging drags in the RGB of fully-transparent texels and fringes
// the sprite edges). Returns a malloc'd buffer the caller must free.
static u8* downscale_rgba(const u8* src, int w, int h, int f, int* out_w, int* out_h) {
  int nw = w / f, nh = h / f;
  u8* dst = (u8*)malloc((size_t)nw * nh * 4);
  for (int y = 0; y < nh; y++) {
    for (int x = 0; x < nw; x++) {
      u64 r = 0, g = 0, b = 0, a = 0;
      for (int sy = 0; sy < f; sy++) {
        const u8* row = src + (((size_t)(y * f + sy) * w) + (size_t)x * f) * 4;
        for (int sx = 0; sx < f; sx++) {
          u64 al = row[sx * 4 + 3];
          r += row[sx * 4 + 0] * al;
          g += row[sx * 4 + 1] * al;
          b += row[sx * 4 + 2] * al;
          a += al;
        }
      }
      u8* out = dst + (((size_t)y * nw) + x) * 4;
      out[0] = a ? (u8)(r / a) : 0;
      out[1] = a ? (u8)(g / a) : 0;
      out[2] = a ? (u8)(b / a) : 0;
      out[3] = (u8)(a / ((u64)f * f));
    }
  }
  *out_w = nw;
  *out_h = nh;
  return dst;
}

static u64 upload_rhud_texture(const u8* data, int w, int h) {
  GLuint tex_id;
  glGenTextures(1, &tex_id);
  GLint old_tex;
  glGetIntegerv(GL_ACTIVE_TEXTURE, &old_tex);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, tex_id);
  // RGBA byte order is identical on both backends (little-endian).
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
  glGenerateMipmap(GL_TEXTURE_2D);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glActiveTexture(old_tex);
  return tex_id;
}

// Names in slot order, base slot 8300, +1 each.
static const char* kRechargedHudNames[] = {
    "jak_heart_100",         "jak_heart_66",        "jak_heart_33",
    "jak_heart_0",           "jak_gauge_empty",     "jak_gauge_blue_full",
    "jak_gauge_red_full",    "jak_gauge_yellow_full", "jak_gauge_blue_end",
    "jak_gauge_red_end",     "jak_gauge_yellow_end", "loading_jak",
    "loading_precursor",
};

// Per-entry downscale divisor, one for one with kRechargedHudNames.
//   4 : the HUD sprites keep the uniform divisor they have always used (same
//       pixel count per side within each shared canvas family, so overlay
//       alignment between the gauge sprites and their _end tips is preserved
//       exactly).
//   1 : the loading-screen assets are authored at their final size and are
//       uploaded untouched -- dividing the glyph atlas by 4 would destroy it.
static const int kRechargedHudDownscale[] = {
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 1, 1,
};

static_assert(sizeof(kRechargedHudDownscale) / sizeof(int) ==
                  sizeof(kRechargedHudNames) / sizeof(char*),
              "kRechargedHudDownscale must have exactly one entry per kRechargedHudNames entry");

void load_recharged_hud_textures(TexturePool& pool, GameVersion version) {
  if (version != GameVersion::Jak1) {
    return;
  }

  auto dir = file_util::get_recharged_assets_dir();

  for (int i = 0; i < (int)(sizeof(kRechargedHudNames) / sizeof(kRechargedHudNames[0])); i++) {
    const int slot = 8300 + i;
    std::string name = kRechargedHudNames[i];
    auto path = dir / (name + ".png");

    if (!fs::exists(path)) {
      lg::warn("recharged-hud: missing texture {}", path.string());
      continue;
    }

    int w, h;
    auto* data = stbi_load(path.string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
    if (!data) {
      lg::warn("recharged-hud: failed to load texture {}", path.string());
      continue;
    }

    // factor 1 = upload the stbi buffer as-is, no intermediate allocation.
    const int factor = kRechargedHudDownscale[i];
    int dw = w, dh = h;
    u8* small = nullptr;
    const u8* upload = data;
    if (factor > 1) {
      small = downscale_rgba(data, w, h, factor, &dw, &dh);
      upload = small;
    }
    u64 tex_id = upload_rhud_texture(upload, dw, dh);

    TextureInput in;
    in.gpu_texture = tex_id;
    in.w = dw;
    in.h = dh;
    in.debug_page_name = "PC-RHUD";
    in.debug_name = name;
    in.id = pool.allocate_pc_port_texture(GameVersion::Jak1);
    pool.give_texture_and_load_to_vram(in, slot);

    // `upload` aliases one of the two buffers below; both are released here,
    // each with the allocator that produced it.
    if (small) {
      free(small);
    }
    stbi_image_free(data);

    lg::info("recharged-hud: loaded {} ({}x{} -> {}x{}) -> vram slot {}", name, w, h, dw, dh, slot);
  }
}
