#pragma once

// External-asset-root: runtime user PNG texture replacements.
//
// When Gfx::g_global_settings.load_custom_assets is enabled, textures uploaded
// by the loader are looked up against a directory of user-supplied PNGs at
// <root>/custom_assets/texture_replacements and, on a hit, the PNG is uploaded
// in place of the baked fr3 texture.

#include <optional>
#include <string>
#include <vector>

#include "common/common_types.h"

namespace custom_tex {

struct ReplacementImage {
  std::vector<u8> rgba;
  int w = 0;
  int h = 0;
};

// Look up a replacement for a given texture. Returns nullopt when custom
// assets are disabled or no matching PNG exists.
std::optional<ReplacementImage> lookup(const std::string& tpage_name, const std::string& tex_name);

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials: look up a replacement PNG whose NAME part carries a
// suffix (e.g. "_normal"), reusing the same index/scan as lookup(). The returned
// pointer is backed by a per-call thread-local buffer; it is valid only until the
// next lookup_suffixed() call on this thread (add_texture consumes it immediately).
const ReplacementImage* lookup_suffixed(const std::string& tpage_name,
                                        const std::string& tex_name,
                                        const char* suffix);

// Grecharged-pbr-materials: registry mapping a texture debug-name to its extra
// PBR material GL textures. GL ids, 0 = absent.
struct PbrMaterialMaps {
  u32 normal_tex = 0;
  u32 rough_tex = 0;
  u32 metal_tex = 0;
  u32 ao_tex = 0;
  u32 height_tex = 0;  // <tex>_height.png — drives parallax occlusion mapping
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
