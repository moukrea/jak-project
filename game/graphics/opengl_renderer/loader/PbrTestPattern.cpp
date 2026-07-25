#include "PbrTestPattern.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"

#include "third-party/glad/include/glad/glad.h"

namespace pbr_testpattern {

namespace {

// The shared N/R/H maps are generated at this resolution. The BASE swap picks its own dim
// (see add_texture): 256 in mode 1, 128 in mode 2 where every texture in the level is swapped.
constexpr int kMapDim = 256;

// Cached-once property/env reads, same idiom as pbr_killswitch() in background_common.cpp.
int read_cached(int& cached, int def, int lo, int hi, const char* prop, const char* env) {
  if (cached < 0) {
    cached = def;
#ifdef __ANDROID__
    char v[PROP_VALUE_MAX];
    if (__system_property_get(prop, v) > 0) {
      cached = atoi(v);
    }
    (void)env;
#else
    if (const char* e = std::getenv(env)) {
      cached = atoi(e);
    }
    (void)prop;
#endif
    cached = std::clamp(cached, lo, hi);
  }
  return cached;
}

// Size in texels of one checker square, for a texture of side `dim`.
int cell_size(int dim) {
  const int sq = squares_per_tile();
  const int c = dim / sq;  // integer: if squares > dim, one texel per square
  return c < 1 ? 1 : c;
}

// checker(cx, cy) = ((cx + cy) & 1), cx = px/cell, cy = py/cell.
inline int checker_at(int px, int py, int cell) {
  return ((px / cell) + (py / cell)) & 1;
}

inline void put(std::vector<u8>& out, int dim, int px, int py, u8 r, u8 g, u8 b) {
  const size_t i = ((size_t)py * (size_t)dim + (size_t)px) * 4;
  out[i + 0] = r;
  out[i + 1] = g;
  out[i + 2] = b;
  out[i + 3] = 255;
}

// A flat grey/black checker in R=G=B, so a per-platform RGBA channel swap (kRgbaTexType differs
// between GL and GLES) cannot change it. Only the three ORIENTATION MARKERS are coloured, so a
// swapped build would merely re-colour them — the geometry of the test is unaffected.
void make_height_rgba(std::vector<u8>& out, int dim) {
  const int cell = cell_size(dim);
  out.assign((size_t)dim * (size_t)dim * 4, 255);
  for (int py = 0; py < dim; py++) {
    for (int px = 0; px < dim; px++) {
      // HARD step on purpose: that is exactly what the test measures.
      const u8 v = checker_at(px, py, cell) ? 255 : 0;
      put(out, dim, px, py, v, v, v);
    }
  }
}

void make_rough_rgba(std::vector<u8>& out, int dim) {
  const int cell = cell_size(dim);
  out.assign((size_t)dim * (size_t)dim * 4, 255);
  for (int py = 0; py < dim; py++) {
    for (int px = 0; px < dim; px++) {
      const u8 v = checker_at(px, py, cell) ? 230 : 64;  // rough square / smooth square
      put(out, dim, px, py, v, v, v);
    }
  }
}

// Derived from the HEIGHT field by central differences with WRAP-AROUND at the borders, so the
// map tiles seamlessly. The interior of a square is flat (128,128,255); only the square EDGES
// carry a slope — if the shading does not show a ridge exactly on the painted square edges, the
// normal path is mis-oriented.
void make_normal_rgba(std::vector<u8>& out, int dim) {
  const int cell = cell_size(dim);
  constexpr float K = 4.0f;
  out.assign((size_t)dim * (size_t)dim * 4, 255);
  auto h = [&](int x, int y) -> float {
    const int xx = ((x % dim) + dim) % dim;
    const int yy = ((y % dim) + dim) % dim;
    return checker_at(xx, yy, cell) ? 1.f : 0.f;
  };
  auto enc = [](float v) -> u8 {
    return (u8)std::lround(std::clamp(v * 0.5f + 0.5f, 0.f, 1.f) * 255.f);
  };
  for (int py = 0; py < dim; py++) {
    for (int px = 0; px < dim; px++) {
      const float gx = (h(px + 1, py) - h(px - 1, py)) * K;
      const float gy = (h(px, py + 1) - h(px, py - 1)) * K;
      float nx = -gx;
      float ny = -gy;
      float nz = 1.f;
      const float len = std::sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 0.f) {
        nx /= len;
        ny /= len;
        nz /= len;
      }
      put(out, dim, px, py, enc(nx), enc(ny), enc(nz));
    }
  }
}

// EXACTLY the parameters make_map() uses in LoaderStages.cpp for the real PBR maps.
u32 upload_map(const std::vector<u8>& rgba, int dim) {
  GLuint id = 0;
  glGenTextures(1, &id);
  glBindTexture(GL_TEXTURE_2D, id);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, dim, dim, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
  glGenerateMipmap(GL_TEXTURE_2D);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
  return id;
}

// Read directly by owns(), which must NOT trigger generation (it runs on every level load, with
// the pattern off, from the loader's stale-id free loop).
SharedMaps g_shared;
bool g_shared_init = false;

}  // namespace

int mode() {
  static int cached = -1;
  return read_cached(cached, 0, 0, 4, "debug.opengoal.pbr.testpattern", "OG_PBR_TESTPATTERN");
}

bool flat_base() {
  // Modes 3 and 4 are modes 1 and 2 with a FLAT base colour. They exist because the checker's own
  // albedo is a confound in the one measurement this whole pattern is for: displacing a surface
  // also moves the texture painted on it, so |displaced - flat| carries the PAINTED period whatever
  // the height field does. Take the albedo pattern away and the only thing left that can vary
  // across the ground is the geometry (with the normal map isolated off via bisect bit 64), so the
  // period that is measured IS the displaced feature's period. That is the clean form of the
  // owner's checkerboard test.
  const int m = mode();
  return m == 3 || m == 4;
}

int squares_per_tile() {
  static int cached = -1;
  return read_cached(cached, 8, 1, 64, "debug.opengoal.pbr.testsquares", "OG_PBR_TESTSQUARES");
}

void make_base_rgba(std::vector<u8>& out, int dim) {
  if (dim < 1) {
    dim = 1;
  }
  const int cell = cell_size(dim);
  out.assign((size_t)dim * (size_t)dim * 4, 255);
  if (flat_base()) {
    // Flat mid-grey, no checker and no markers: the albedo carries NO spatial frequency at all, so
    // anything periodic left on screen came from the geometry or the maps, not from the paint.
    for (int py = 0; py < dim; py++) {
      for (int px = 0; px < dim; px++) {
        put(out, dim, px, py, 150, 150, 150);
      }
    }
    return;
  }
  for (int py = 0; py < dim; py++) {
    for (int px = 0; px < dim; px++) {
      const u8 v = checker_at(px, py, cell) ? 215 : 55;
      put(out, dim, px, py, v, v, v);
    }
  }
  // ORIENTATION MARKERS, inside the FIRST cell (cx == 0 && cy == 0) of the tile, over the base
  // colour: a rotated or mirrored UV frame is then instantly visible on screen.
  const int bar = std::max(2, cell / 8);
  const int corner = std::max(3, cell / 6);
  const int bar_w = std::min(bar, dim);
  const int span = std::min(cell, dim);
  const int corner_w = std::min(corner, dim);
  // RED bar along +U (rows py in [0, bar), px spanning the whole first cell).
  for (int py = 0; py < bar_w; py++) {
    for (int px = 0; px < span; px++) {
      put(out, dim, px, py, 230, 30, 30);
    }
  }
  // GREEN bar along +V (cols px in [0, bar), py spanning the whole first cell).
  for (int px = 0; px < bar_w; px++) {
    for (int py = 0; py < span; py++) {
      put(out, dim, px, py, 30, 200, 30);
    }
  }
  // BLUE corner square, drawn LAST so it sits on top of both bars.
  for (int py = 0; py < corner_w; py++) {
    for (int px = 0; px < corner_w; px++) {
      put(out, dim, px, py, 40, 60, 240);
    }
  }
}

const SharedMaps& shared_maps() {
  if (!g_shared_init) {
    g_shared_init = true;
    std::vector<u8> buf;
    make_normal_rgba(buf, kMapDim);
    g_shared.normal_tex = upload_map(buf, kMapDim);
    make_rough_rgba(buf, kMapDim);
    g_shared.rough_tex = upload_map(buf, kMapDim);
    make_height_rgba(buf, kMapDim);
    g_shared.height_tex = upload_map(buf, kMapDim);
    lg::info(
        "pbr TESTPATTERN: generated shared checker maps mode={} squares/tile={} dim=256 "
        "(N={} R={} H={})",
        mode(), squares_per_tile(), g_shared.normal_tex, g_shared.rough_tex, g_shared.height_tex);
  }
  return g_shared;
}

bool owns(u32 gl_id) {
  if (!gl_id) {
    return false;
  }
  return gl_id == g_shared.normal_tex || gl_id == g_shared.rough_tex ||
         gl_id == g_shared.height_tex;
}

}  // namespace pbr_testpattern
