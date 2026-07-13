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

// Force a rescan of the replacements directory on the next lookup().
void invalidate();

// Key-dump helper: when the marker file <root>/custom_assets/dump_keys exists,
// append the "tpage/name" key for every texture seen to texture_keys_dump.txt
// (deduped). No-op otherwise.
void dump_key(const std::string& tpage_name, const std::string& tex_name);

}  // namespace custom_tex
