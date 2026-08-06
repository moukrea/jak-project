#include "Ktx2Subset.h"

#include <cstring>

#include "common/util/Assert.h"

#include "fmt/core.h"

namespace ktx2 {

namespace {
constexpr u8 kIdentifier[12] = {0xAB, 'K', 'T', 'X', ' ', '2',
                                '0',  0xBB, 0x0D, 0x0A, 0x1A, 0x0A};

template <typename T>
T read_le(const u8* p) {
  T v;
  memcpy(&v, p, sizeof(T));
  return v;  // engine targets are all little-endian
}
}  // namespace

bool is_supported_format(u32 vk_format) {
  switch (static_cast<VkFormat>(vk_format)) {
    case VkFormat::R8G8B8A8_UNORM:
    case VkFormat::BC1_RGB_UNORM:
    case VkFormat::BC4_UNORM:
    case VkFormat::BC5_UNORM:
    case VkFormat::BC7_UNORM:
    case VkFormat::ETC2_R8G8B8_UNORM:
    case VkFormat::EAC_R11_UNORM:
    case VkFormat::EAC_R11G11_UNORM:
    case VkFormat::ASTC_4x4_UNORM:
    case VkFormat::ASTC_6x6_UNORM:
      return true;
    default:
      return false;
  }
}

bool is_compressed(u32 vk_format) {
  return static_cast<VkFormat>(vk_format) != VkFormat::R8G8B8A8_UNORM;
}

void block_info(u32 vk_format, u32* block_w, u32* block_h, u32* block_bytes) {
  switch (static_cast<VkFormat>(vk_format)) {
    case VkFormat::R8G8B8A8_UNORM:
      *block_w = 1, *block_h = 1, *block_bytes = 4;
      return;
    case VkFormat::BC1_RGB_UNORM:
    case VkFormat::BC4_UNORM:
    case VkFormat::ETC2_R8G8B8_UNORM:
    case VkFormat::EAC_R11_UNORM:
      *block_w = 4, *block_h = 4, *block_bytes = 8;
      return;
    case VkFormat::BC5_UNORM:
    case VkFormat::BC7_UNORM:
    case VkFormat::EAC_R11G11_UNORM:
    case VkFormat::ASTC_4x4_UNORM:
      *block_w = 4, *block_h = 4, *block_bytes = 16;
      return;
    case VkFormat::ASTC_6x6_UNORM:
      *block_w = 6, *block_h = 6, *block_bytes = 16;
      return;
    default:
      ASSERT_MSG(false, fmt::format("block_info on unsupported vkFormat {}", vk_format));
  }
}

u64 expected_level_size(u32 vk_format, u32 w, u32 h) {
  u32 bw, bh, bb;
  block_info(vk_format, &bw, &bh, &bb);
  const u64 blocks_x = (w + bw - 1) / bw;
  const u64 blocks_y = (h + bh - 1) / bh;
  return blocks_x * blocks_y * bb;
}

bool parse(const u8* data, size_t size, Texture* out, std::string* err) {
  // 12-byte identifier + 9 u32 header + 6-field index (4x u32 + 2x u64)
  constexpr size_t kHeaderEnd = 12 + 9 * 4 + 4 * 4 + 2 * 8;
  if (size < kHeaderEnd) {
    *err = "ktx2: file too small";
    return false;
  }
  if (memcmp(data, kIdentifier, sizeof(kIdentifier)) != 0) {
    *err = "ktx2: bad identifier";
    return false;
  }
  const u8* p = data + 12;
  const u32 vk_format = read_le<u32>(p + 0);
  // typeSize at +4 (unused: 1 for block formats)
  const u32 width = read_le<u32>(p + 8);
  const u32 height = read_le<u32>(p + 12);
  const u32 depth = read_le<u32>(p + 16);
  const u32 layer_count = read_le<u32>(p + 20);
  const u32 face_count = read_le<u32>(p + 24);
  const u32 level_count = read_le<u32>(p + 28);
  const u32 scheme = read_le<u32>(p + 32);

  if (!is_supported_format(vk_format)) {
    *err = fmt::format("ktx2: unsupported vkFormat {}", vk_format);
    return false;
  }
  if (scheme != 0) {
    *err = fmt::format("ktx2: supercompression {} not in subset", scheme);
    return false;
  }
  if (depth > 1 || layer_count > 1 || face_count != 1) {
    *err = "ktx2: only plain 2D textures are in the subset";
    return false;
  }
  if (width == 0 || height == 0 || level_count == 0 || level_count > 16) {
    *err = "ktx2: bad dimensions/levels";
    return false;
  }

  const size_t level_index_off = kHeaderEnd;
  const size_t level_index_size = size_t(level_count) * 3 * 8;
  if (size < level_index_off + level_index_size) {
    *err = "ktx2: truncated level index";
    return false;
  }

  out->vk_format = vk_format;
  out->width = width;
  out->height = height;
  out->level_count = level_count;
  out->levels.clear();
  out->levels.reserve(level_count);
  u32 w = width, h = height;
  for (u32 i = 0; i < level_count; i++) {
    const u8* lp = data + level_index_off + size_t(i) * 24;
    LevelInfo li;
    li.byte_offset = read_le<u64>(lp + 0);
    li.byte_length = read_le<u64>(lp + 8);
    // uncompressedByteLength at +16 (equals byte_length with scheme 0)
    if (li.byte_offset + li.byte_length > size) {
      *err = fmt::format("ktx2: level {} out of bounds", i);
      return false;
    }
    if (li.byte_length != expected_level_size(vk_format, w, h)) {
      *err = fmt::format("ktx2: level {} size {} != expected {} for {}x{}", i, li.byte_length,
                         expected_level_size(vk_format, w, h), w, h);
      return false;
    }
    out->levels.push_back(li);
    w = w > 1 ? w / 2 : 1;
    h = h > 1 ? h / 2 : 1;
  }
  return true;
}

}  // namespace ktx2
