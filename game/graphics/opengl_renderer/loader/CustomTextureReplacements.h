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
};

// Register (overwrite) the PBR maps for a texture. Returns the PREVIOUS entry by
// value (all-zero if none) so the caller can glDeleteTextures the old GL ids on a
// level-reload path.
PbrMaterialMaps register_pbr_material(const std::string& tex_debug_name,
                                      const PbrMaterialMaps& maps);

// Look up the registered PBR maps for a texture, or nullptr if none.
const PbrMaterialMaps* find_pbr_material(const std::string& tex_debug_name);
#endif

// Force a rescan of the replacements directory on the next lookup().
void invalidate();

// Key-dump helper: when the marker file <root>/custom_assets/dump_keys exists,
// append the "tpage/name" key for every texture seen to texture_keys_dump.txt
// (deduped). No-op otherwise.
void dump_key(const std::string& tpage_name, const std::string& tex_name);

}  // namespace custom_tex
