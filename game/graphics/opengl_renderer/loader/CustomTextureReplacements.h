#pragma once

// Runtime PNG texture replacements from TWO sources.
//
// Textures uploaded by the loader are looked up against two PNG indexes and, on a
// hit, the PNG is uploaded in place of the baked fr3 texture:
//   1. the USER drop dir (get_custom_assets_replacements_dir), gated by
//      Gfx::g_global_settings.load_custom_assets, and
//   2. the package-BUNDLED first-party set under
//      custom_assets/<game>/recharged_textures (get_bundled_recharged_textures_dir):
//      base swaps gated by Gfx::g_global_settings.recharged_textures, the bundle's
//      _height/_normal/_roughness PBR maps gated by the PBR path instead.
// Precedence is user > bundled > stock, and every gate is composed with the Recharged
// master via Gfx::recharged_active().

#include <optional>
#include <string>
#include <vector>

#include "common/common_types.h"

namespace custom_tex {

struct ReplacementImage {
  std::vector<u8> rgba;
  int w = 0;
  int h = 0;
  const char* src = "";  // which index the file came from: "user"/"bundled"
};

// Which source won the base texture (deterministic mirror of lookup()).
enum class BaseSource { Stock, User, Bundled };

// Look up a replacement for a given texture. Returns nullopt when custom
// assets are disabled or no matching PNG exists.
std::optional<ReplacementImage> lookup(const std::string& tpage_name, const std::string& tex_name);

// Report which source would win the BASE texture for this key, without loading pixels.
BaseSource base_source(const std::string& tpage_name, const std::string& tex_name);

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials: look up a replacement PNG whose NAME part carries a
// suffix (e.g. "_normal"), reusing the same index/scan as lookup(). The returned
// pointer is backed by a per-call thread-local buffer; it is valid only until the
// next lookup_suffixed() call on this thread (add_texture consumes it immediately).
const ReplacementImage* lookup_suffixed(const std::string& tpage_name,
                                        const std::string& tex_name,
                                        const char* suffix,
                                        BaseSource base_src);

// Existence-only probe for a suffixed map. Same key construction, same source gating and
// same-source pairing rule as lookup_suffixed(), but it stops at the index: no file read, no
// PNG decode. Used by the pre-subdivision pass to bound itself to surfaces that actually have
// a displacement source.
bool has_suffixed(const std::string& tpage_name,
                  const std::string& tex_name,
                  const char* suffix,
                  BaseSource base_src);

// Grecharged-pbr-materials: registry mapping a texture debug-name to its extra
// PBR material GL textures. GL ids, 0 = absent.
struct PbrMaterialMaps {
  u32 normal_tex = 0;
  u32 rough_tex = 0;
  u32 metal_tex = 0;
  u32 ao_tex = 0;
  u32 height_tex = 0;  // <tex>_height.png — drives parallax occlusion mapping
  // Grecharged-pbr-realtime-fusion (owner: "faut câbler specular et emissive aussi"):
  u32 specular_tex = 0;  // <tex>_specular.png — F0 / specular color (specular workflow)
  u32 emissive_tex = 0;  // <tex>_emissive.png — unlit self-illumination, added on top
  // MEAN tangent-space surface gradient (n.xy / n.z, per-texel clamp +-4) of <tex>_normal.png,
  // measured over every texel when the map is decoded. Non-zero means the map carries a constant
  // TILT rather than pure relief; the shader subtracts it so the perturbation is zero-mean (see
  // tfrag3.frag u_pbr_normal_dc — a non-zero DC was the owner's hard brightness-plate defect).
  float normal_dc_x = 0.f;
  float normal_dc_y = 0.f;
  // HEIGHT-MAP STATISTICS of <tex>_height.png's red channel, measured over every texel when the
  // map is decoded. The shipped height maps are NEITHER normalised NOR mean-centred: measured on
  // the 7 bundled maps, vil1-jng-leafyground spans 0.0627..0.4627 (mean 0.3225), vil-wallplaster
  // means 0.8068, vil1-sages-strawroof-01 spans only 0.298..0.478. So the naive (h - 0.5) both
  // OFFSETS the whole material (net-inward for a dark map, net-outward for a bright one) and
  // wastes most of the nominal amplitude (only 18-75% of it is ever used). These two numbers let
  // the shader recentre and rescale per material: (h - height_mean) * height_norm + 0.5 refills
  // 0..1 around the material's own mid. The defaults (0.5, 1.0) are the IDENTITY transform.
  float height_mean = 0.5f;  // mean of <tex>_height.png's red channel, 0..1
  float height_norm = 1.0f;  // 0.5 / robust half-range; (h-mean)*norm+0.5 refills 0..1
  // ROUND 20: characteristic feature WAVELENGTH of the height field, in TILES (1 tile = the whole
  // texture). Measured at load from the map's own mip-energy spectrum. x the material's world tile
  // size = the feature's world size, which is what the tessellation amplitude is scaled by.
  float height_lambda_tiles = 0.25f;
};

// Register (overwrite) the PBR maps for a texture. Returns the PREVIOUS entry by
// value (all-zero if none) so the caller can glDeleteTextures the old GL ids on a
// level-reload path.
PbrMaterialMaps register_pbr_material(const std::string& tex_debug_name,
                                      const PbrMaterialMaps& maps);

// Look up the registered PBR maps for a texture, or nullptr if none.
const PbrMaterialMaps* find_pbr_material(const std::string& tex_debug_name);

// Grecharged-pbr-realtime-fusion 2026-07-26, [pom] DEVICE DIAGNOSTIC. The owner and the
// supervisor both asked the same question about the flat parallax — "is the POM branch even
// executed on this draw, and what is the FINAL offset after every cap, in UV and in world cm?".
// The shader cannot answer it (no printf on GLES), so the CPU mirrors the exact same amplitude law
// per material and dumps it into the pullable pbr_tan_diag.txt. The renderers call
// pbr_pom_diag_note() as they resolve a level's materials (they own the measured UV density,
// which is geometry-derived and therefore not part of PbrMaterialMaps); the kernel's diag writer
// calls pbr_pom_diag_section() to render the block. This is diagnostics only — nothing here is
// read by the render path.
void pbr_pom_diag_note(const std::string& tex_debug_name,
                       const PbrMaterialMaps& maps,
                       float uv_per_m);
// Bumped every time a note() actually changes the recorded set, so the diag writer can tell that
// a level load brought new materials in and re-emit the file (it is otherwise only written when
// the isolate carousel moves, which happens before any level is loaded).
u32 pbr_pom_diag_generation();
// The rendered "[pom]" block, one line per PBR-bound material plus a summary line. Empty string
// when nothing has been noted yet.
std::string pbr_pom_diag_section();

// Grecharged-pbr-realtime-fusion ROUND 21, [cover] DISPLACEMENT COVERAGE counters. The owner's
// bug B is "des chunks entiers (LA PLUPART) sont juste PLATS": the question is not whether the POM
// law is right, it is WHICH PBR-bound draws receive ANY displacement at all. These counters answer
// it with numbers instead of eyeballs: every draw that binds a PBR material is classified, once,
// at the bind site (PbrDrawBinder::set) into exactly one displacement bucket. Counted per frame and
// snapshotted at the frame boundary, so the dump always reports one complete frame.
//   frame_idx  : SharedRenderState::frame_idx — used to detect the frame boundary.
//   renderer   : the renderer that owns the draw, a STRING LITERAL ("tfrag"/"tie"); the pointer is
//                stored, so it must have static storage duration.
//   tree_kind  : optional sub-label with the same lifetime rule (tfrag3::tfrag_tree_names[kind]);
//                nullptr when the caller has no cheap tree kind.
//   has_height : this draw has a height map bound (u_pbr_mode bit 16).
//   disp_tess  : the draw is rendered by the TFRAG3_TESS program AND the tess-eval displacement
//                gate is open (real vertex displacement).
//   disp_pom   : the draw is rendered by a non-tess program AND the fragment POM gate is open.
// Both false with has_height = the "flat chunk" bucket. Callers own the gate mirroring (the
// effective height scale / bisect / debug values live on the GL side).
void pbr_coverage_note_draw(u64 frame_idx,
                            const char* renderer,
                            const char* tree_kind,
                            bool has_height,
                            bool disp_tess,
                            bool disp_pom);
// Advances every ~300 completed frames once counting has started, so the diag writer re-emits the
// file with live coverage numbers without doing per-frame disk I/O.
u32 pbr_coverage_generation();
// The rendered "[cover]" block. Empty string until one full frame has been counted.
std::string pbr_coverage_section();
#endif

// Force a rescan of the replacements directory on the next lookup().
void invalidate();

// Key-dump helper: when the marker file <root>/custom_assets/dump_keys exists,
// append the "tpage/name" key for every texture seen to texture_keys_dump.txt
// (deduped). No-op otherwise.
void dump_key(const std::string& tpage_name, const std::string& tex_name);

}  // namespace custom_tex
