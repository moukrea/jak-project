#pragma once

// Grecharged-managed-assets: the MANAGED (downloaded) texture-pack source
// tier. Packs are RPACK shards of KTX2 payloads produced by the
// recharged-assets pipeline and installed under
// <project dir>/managed_assets/<game>/ by the asset manager (state.json
// lists the verified shards). Precedence (owner): user drop dir > managed >
// bundled > stock — the caller (add_texture) enforces it via
// custom_tex::base_source() + managed::lookup_base().
//
// M1/PR1 scope: BASE (albedo) swaps only. Suffixed PBR maps ship in the
// packs too but need the normal-XY shader mode; they activate in PR2.

#include <optional>
#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/util/Ktx2Subset.h"
#include "common/util/RPack.h"

namespace managed_assets {

struct CompressedTex {
  ktx2::Texture info;      // parsed header + level table
  std::vector<u8> payload; // whole KTX2 payload (levels reference into it)
  std::string wrap_mode;   // from the pack entry metadata
};

// Scan/refresh the installed state. Cheap when nothing changed; call once
// per level-load batch (add_texture callers are on the GL thread).
void ensure_loaded();

// Drop all state (settings toggle, pack re-install).
void invalidate();

// True when a verified pack is installed and the gate is on.
bool active();

// Look up the managed BASE texture for a replacement key. Returns nullopt
// when disabled, not installed, or no entry exists.
std::optional<CompressedTex> lookup_base(const std::string& tpage_name,
                                         const std::string& tex_name);

// Existence-only probe (no payload read).
bool has_base(const std::string& tpage_name, const std::string& tex_name);

// Upload a parsed KTX2 to the currently-bound GL_TEXTURE_2D via
// glTexStorage2D + glCompressedTexSubImage2D (or glTexSubImage2D for the
// RGBA8 fallback format). All mip levels are uploaded; the caller must NOT
// call glGenerateMipmap. Returns false (with a log) on unsupported format
// or GL error; caller falls back to the stock path.
bool upload_bound_texture(const CompressedTex& tex);

}  // namespace managed_assets
