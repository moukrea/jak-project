#include "PbrTestPattern.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "third-party/glad/include/glad/glad.h"

namespace pbr_testpattern {

namespace {

// The shared N/R/H maps are generated at this resolution. The BASE swap picks its own dim
// (see add_texture): 256 in mode 1, 128 in mode 2 where every texture in the level is swapped.
constexpr int kMapDim = 256;

// Cached-once property/env reads, same idiom as pbr_killswitch() in background_common.cpp.
// `present` (optional) reports, on the FIRST read only, whether the prop/env was explicitly set —
// the mesh-browser fallback needs to tell "no override" apart from "overridden to 0".
int read_cached(int& cached, int def, int lo, int hi, const char* prop, const char* env,
                bool* present = nullptr) {
  if (cached < 0) {
    cached = def;
    bool found = false;
#ifdef __ANDROID__
    char v[PROP_VALUE_MAX];
    if (__system_property_get(prop, v) > 0) {
      cached = atoi(v);
      found = true;
    }
    (void)env;
#else
    if (const char* e = std::getenv(env)) {
      cached = atoi(e);
      found = true;
    }
    (void)prop;
#endif
    cached = std::clamp(cached, lo, hi);
    if (present) {
      *present = found;
    }
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

int grain() {
  // ===== ROUND 24: A UNIFORM SQUARE CANNOT SHOW THAT IT MOVED ===================================
  // Measured on device, after the tier cross-fade and the far-field fix: the pixels that STILL did
  // not change when displacement was switched off were, at 84-99%, the INTERIORS of checker cells,
  // while the cell boundaries changed. That is not the pipeline: the parallax tier shifts the UV by
  // ~10 cm of world (7.6 screen px at 30 m) and the tessellation tier moves the vertices, but a
  // shift of a REGION OF CONSTANT COLOUR maps every interior pixel onto another pixel of the same
  // colour. The instrument was blind in exactly the place the owner is looking ("la plupart des
  // endroits n'ont pas de displacement") — and so was his eye, for the same reason.
  // The fix is to give the checker what every real material has: fine GRAIN. Three octaves, +-15%
  // around the cell's own value, so the black square stays black and the white square stays white
  // (alignment and polarity, the two things the checker is for, are untouched) but every texel now
  // differs from its neighbours and a shift of any size becomes visible — to the metric and to the
  // owner. Octaves 3/9/27 cycles per cell mean one of them survives at any viewing distance instead
  // of the whole grain mipping away in the middle field.
  // debug.opengoal.pbr.testgrain=0 restores the flat squares.
  static int cached = -1;
  return read_cached(cached, 1, 0, 1, "debug.opengoal.pbr.testgrain", "OG_PBR_TESTGRAIN");
}

// +-1, three octaves, deterministic, tiling exactly with the cell grid.
float grain_at(int px, int py, int cell) {
  if (grain() == 0) {
    return 0.f;
  }
  constexpr float kPi = 3.14159265358979323846f;
  const float u = ((float)px + 0.5f) / (float)cell;
  const float v = ((float)py + 0.5f) / (float)cell;
  const float g = 0.55f * std::sin(2.f * kPi * 3.f * u) * std::sin(2.f * kPi * 3.f * v) +
                  0.30f * std::sin(2.f * kPi * 9.f * u + 1.7f) * std::sin(2.f * kPi * 9.f * v) +
                  0.15f * std::sin(2.f * kPi * 27.f * u) * std::sin(2.f * kPi * 27.f * v + 0.9f);
  return g;
}

int height_profile() {
  // ===== ROUND 24: THE HARD CHECKER CANNOT SHOW RELIEF INSIDE A SQUARE, BY CONSTRUCTION =========
  // Measured at the owner's vantage with the hard 0/255 height (device/r24): switching displacement
  // off changed 45.1% of the pixels that sit ON an albedo edge and 1.0% of the pixels more than
  // 8 px away from one. That is not a pipeline result, it is arithmetic: inside a square the height
  // is CONSTANT, so the surface there is a flat plateau that displacement translates rigidly along
  // its own normal — the albedo is constant too, so no pixel in the interior can change. The owner
  // is looking at a test material that is flat everywhere except on its square boundaries, and
  // reporting that most of the surface looks flat.
  //   0 = the original HARD step (DEFAULT again as of round 26 — see below)
  //   1 = SMOOTH profile, h = 0.5 - 0.5*sin(pi*u)*sin(pi*v) in cell units. Same squares,
  //       same alignment, same polarity — white square centres at 1.0, black at 0.0, exactly 0.5 on
  //       every square boundary — but now the field has a gradient at every texel, so displacement
  //       is legible across the whole square instead of only on its edges.
  //
  // ===== ROUND 26, DEFECT D1 — THIS DEFAULT *WAS* THE REGRESSION ==============================
  // Owner, on the 6438b50e checker build: "c'est normal que le displacement ne soit plus strict
  // genre carré blanc = élévation max, carré noir = élévation minimale? Là il semblerait que tout
  // soit... Arrondi, genre SEUL LE CENTRE du carré blanc est au max et SEUL LE CENTRE du carré noir
  // est au minimum".
  // That is a verbatim description of `0.5 - 0.5*sin(pi*u)*sin(pi*v)`: the extreme is reached at
  // exactly ONE POINT per cell (the centre), the field is 0.5 on every cell boundary, and the mean
  // over a cell is (2/pi)^2 = 0.4053 of the extreme. Only 6.53% of a cell's area lies within 10% of
  // the extreme. There is NO PLATEAU IN THE DATA — no amount of vertex density or mip sharpness can
  // produce a step from a field that is a dome. The defect was never in the pipeline.
  // It was introduced today (ac4daa6688, 2026-07-26 15:29) to make the ON-vs-OFF image delta legible
  // inside a square; the owner is judging RELIEF, not a delta metric, and a checkerboard height map
  // is by definition a SQUARE WAVE. Flat plateaus reading "no interior change" is the CORRECT answer
  // for a step function, not a coverage hole. The delta-metric motivation is retired with it.
  // The smooth profile stays reachable (=1) as the A/B, and nothing else about the pattern moves:
  // same squares, same size, same alignment, same polarity.
  static int cached = -1;
  return read_cached(cached, 0, 0, 1, "debug.opengoal.pbr.testprofile", "OG_PBR_TESTPROFILE");
}

// The height field the pattern displaces with, in 0..1. Shared by the height map AND the normal
// map so the two can never disagree about the surface they describe.
float profile_h(int px, int py, int cell) {
  if (height_profile() == 0) {
    return checker_at(px, py, cell) ? 1.f : 0.f;  // HARD step (round-23 material)
  }
  const float u = ((float)px + 0.5f) / (float)cell;
  const float v = ((float)py + 0.5f) / (float)cell;
  // -sin(pi u)*sin(pi v) is +1 at the centre of every cell where (cx+cy) is ODD -- which is exactly
  // the cell checker_at() paints WHITE -- and -1 at the centre of the black ones, crossing zero on
  // every cell boundary. So the raised blocks still coincide with the white squares to the texel.
  constexpr float kPi = 3.14159265358979323846f;
  const float g = -std::sin(kPi * u) * std::sin(kPi * v);
  return 0.5f + 0.5f * g;
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
      const u8 v = (u8)std::lround(255.f * std::clamp(profile_h(px, py, cell), 0.f, 1.f));
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
  // ROUND 24: the gain has to follow the PROFILE, because the two fields have wildly different
  // slopes. The hard step moves a full unit across one texel, so K=4 on a central difference gives
  // a strong ridge exactly on the square boundary. The smooth profile spreads that same unit over
  // half a cell, so its peak slope is pi/(2*cell) per texel — with K=4 the normal map would come
  // out almost flat. 0.64*cell puts the smooth profile's PEAK tilt at ~45 degrees, i.e. the same
  // order as the hard step's ridge, so switching profile changes WHERE the relief is legible, not
  // how strong the normal path is.
  const float K = (height_profile() == 0) ? 4.0f : 0.64f * (float)cell;
  out.assign((size_t)dim * (size_t)dim * 4, 255);
  auto h = [&](int x, int y) -> float {
    const int xx = ((x % dim) + dim) % dim;
    const int yy = ((y % dim) + dim) % dim;
    return profile_h(xx, yy, cell);
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
  // OWNER STANDING RULE: the checkerboard is the acceptance test, and the owner has no adb — so
  // every owner build ships alongside a CHECKER-DEBUG variant with the pattern already on. Only
  // the DEFAULT moves: the prop/env still override it in either direction (set it to 0 in a
  // CHECKER-DEBUG build to turn the pattern off), so headless A/B keeps working unchanged.
#ifdef OG_PBR_CHECKER_DEBUG
  constexpr int kDefaultMode = 1;  // CHECKER-DEBUG build: pattern ON out of the box (no adb)
#else
  constexpr int kDefaultMode = 0;
#endif
  static int cached = -1;
  static bool prop_present = false;
  int prop_mode = read_cached(cached, kDefaultMode, 0, 4, "debug.opengoal.pbr.testpattern",
                              "OG_PBR_TESTPATTERN", &prop_present);
#ifdef OG_PBR_CHECKER_DEBUG
  // SUPERVISOR 2026-07-29: a CHECKER-DEBUG build must NEVER ship with the pattern off. The owner
  // reported "le build debug n'a pas le damier active" on a binary that was verifiably built with
  // the define — because a leftover `setprop debug.opengoal.pbr.testpattern 0`, set during a
  // supervisor debug session hours earlier, still overrode the default (props survive until
  // reboot). A debug build whose whole purpose is the pattern must not be silently disarmed by a
  // stale property, and the owner has no adb to clear it. So in this build the prop may still
  // SELECT a variant (1..4) but can no longer turn the pattern OFF.
  if (prop_mode == 0) {
    prop_mode = kDefaultMode;
    prop_present = false;
  }
#endif
  // Grecharged-mesh-browser: with NO prop/env override, the debug mesh browser's menu toggle owns
  // the pattern (the owner has no adb). This is read fresh on every call (hence at every level
  // load) so a menu flip + re-warp takes effect. When the prop/env IS set, it still wins in either
  // direction — the supervisor's headless A/B is byte-for-byte unchanged.
  if (!prop_present) {
    return std::clamp(Gfx::g_global_settings.recharged_mesh_browser_checker, 0, 4);
  }
  return prop_mode;
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
      const float base = checker_at(px, py, cell) ? 215.f : 55.f;
      // GRAIN: +-15% of this cell's own value. The two cells stay unambiguously light and dark.
      const float g = base * (1.f + 0.15f * grain_at(px, py, cell));
      const u8 v = (u8)std::lround(std::clamp(g, 0.f, 255.f));
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

u32 checker_base_gl() {
  // Grecharged-mesh-browser V2: lazily-created shared checker BASE texture for the freecam's
  // per-draw checker override (see header). Same pattern data as the substitution path
  // (make_base_rgba at kMapDim) and the same upload parameters as the shared N/R/H maps.
  static u32 s_checker_base = 0;
  if (s_checker_base == 0) {
    std::vector<u8> buf;
    make_base_rgba(buf, kMapDim);
    s_checker_base = upload_map(buf, kMapDim);
    lg::info("pbr TESTPATTERN: generated shared checker BASE dim={} (gl id {})", kMapDim,
             s_checker_base);
  }
  return s_checker_base;
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
