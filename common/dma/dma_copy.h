#pragma once

#include <functional>
#include <vector>

#include "common/common_types.h"
#include "common/dma/dma_chain_read.h"
#include "common/util/Serializer.h"

struct DmaData {
  u32 start_offset = 0;
  std::vector<u8> data;
  DmaStats stats;
};

using DmaTagObserver = std::function<void(const DmaFollower&, const DmaTag&, u32 steps)>;

struct DmaCopyError {
  u32 steps = 0;
  u32 tag_offset = 0;
  DmaTag tag{0};
  bool low_tag = false;
  bool out_of_bounds = false;
};

/*!
 * The fixed chunk copier considers the game's main memory as an array of fixed sized chunks.
 * Only the chunks that have dma data are included in the copy.
 * The result is cached internally.
 */
class FixedChunkDmaCopier {
 public:
  static constexpr u32 chunk_size = 0x20000;  // 128 kB, gives use 1024 chunks for a 128 MB RAM.
  FixedChunkDmaCopier(u32 main_memory_size);

  void set_input_data(const void* memory, u32 offset, bool run);

  const DmaData& run(const void* memory, u32 offset, bool verify = false);

  bool try_run(const void* memory,
               u32 offset,
               DmaCopyError& error,
               const DmaTagObserver& observer = {});

  void serialize_last_result(Serializer& serializer);

  const DmaData& get_last_result() const { return m_result; }

  const void* get_last_input_data() const { return m_input_data; }
  u32 get_last_input_offset() const { return m_input_offset; }

 private:
  bool plan_copy(const void* memory,
                 u32 offset,
                 DmaStats& stats,
                 DmaCopyError* error,
                 const DmaTagObserver& observer);
  void apply_copy(const void* memory, u32 offset, const DmaStats& stats);

  struct Fixup {
    u32 source_chunk;
    u32 offset_in_source_chunk;
    u32 dest_chunk;
    u32 offset_in_dest_chunk;
  };
  std::vector<Fixup> m_fixups;

  u32 m_main_memory_size = 0;
  u32 m_chunk_count = 0;
  std::vector<u32> m_chunk_mask;
  DmaData m_result;

  u32 m_input_offset = 0;
  const void* m_input_data = nullptr;
};

/*!
 * Convert a DMA chain to an array of bytes that can be directly fed to VIF.
 */
std::vector<u8> flatten_dma(const DmaFollower& in);
