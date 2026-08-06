#pragma once

// Grecharged-managed-assets: minimal KTX2 reader for the SUBSET the
// recharged-assets pipeline produces — plain block-compressed 2D textures,
// full mip chain, no supercompression, no BasisU, single layer/face.
// The subset contract is enforced at pack build time (`ktx validate` gate in
// the assets repo CI); anything outside it is rejected here, loudly.
// Deliberately not libktx: ~200 lines instead of a large vendored dependency
// in the Android build.

#include <cstddef>
#include <string>
#include <vector>

#include "common/common_types.h"

namespace ktx2 {

// VkFormat values (verified against pipeline-produced files).
enum class VkFormat : u32 {
  R8G8B8A8_UNORM = 37,
  BC1_RGB_UNORM = 131,
  BC4_UNORM = 139,
  BC5_UNORM = 141,
  BC7_UNORM = 145,
  ETC2_R8G8B8_UNORM = 147,
  EAC_R11_UNORM = 153,
  EAC_R11G11_UNORM = 155,
  ASTC_4x4_UNORM = 157,
  ASTC_6x6_UNORM = 165,
};

struct LevelInfo {
  u64 byte_offset = 0;  // relative to the start of the KTX2 payload
  u64 byte_length = 0;
};

struct Texture {
  u32 vk_format = 0;
  u32 width = 0;
  u32 height = 0;
  u32 level_count = 0;
  std::vector<LevelInfo> levels;  // level 0 = largest
};

// Parse a KTX2 payload header + level index (no pixel data copies).
// Returns false and fills err on anything outside the supported subset.
bool parse(const u8* data, size_t size, Texture* out, std::string* err);

// Format helpers for the supported subset.
bool is_supported_format(u32 vk_format);
bool is_compressed(u32 vk_format);
// Block geometry (1x1x(4 bytes) for RGBA8).
void block_info(u32 vk_format, u32* block_w, u32* block_h, u32* block_bytes);
// The byte size level (w,h) must have — used to validate payloads.
u64 expected_level_size(u32 vk_format, u32 w, u32 h);

}  // namespace ktx2
