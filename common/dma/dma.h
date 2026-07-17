#pragma once

/*!
 * @file dma.h
 * PS2 DMA and VIF types.
 */

#include <cstring>
#include <string>

#include "common/common_types.h"
#include "common/util/Assert.h"

#include "fmt/format.h"

struct DmaStats {
  double sync_time_ms = 0;
  int num_tags = 0;
  int num_data_bytes = 0;
  int num_chunks = 0;
  int num_copied_bytes = 0;
  int num_fixups = 0;
};

struct DmaTag {
  enum class Kind : u8 {
    REFE = 0,
    CNT = 1,
    NEXT = 2,
    REF = 3,
    REFS = 4,
    CALL = 5,
    RET = 6,
    END = 7
  };

  DmaTag(u64 value) {
    spr = (value >> 63);
    addr = (value >> 32) & 0x7fffffff;
    qwc = value & 0xffff;
    kind = Kind((value >> 28) & 0b111);
  }

  u16 qwc = 0;
  u32 addr = 0;
  bool spr = false;
  Kind kind;

  bool operator==(const DmaTag& other) const {
    return qwc == other.qwc && addr == other.addr && spr == other.spr && kind == other.kind;
  }

  bool operator!=(const DmaTag& other) const { return !((*this) == other); }

  std::string print() const;
};

#ifdef __aarch64__
#ifdef __APPLE__
// the reporter lives in an android-only TU (mips2c_table_jak1_arm64.cpp);
// macOS-arm64 compiles the aarch64 path but must not require that symbol.
static inline void gnd_oob_report(char, unsigned int, unsigned long long, unsigned long long, int) {
}
#else
extern void gnd_oob_report(char kind, unsigned int target, unsigned long long lo,
                           unsigned long long hi, int nbytes);
#endif
static inline bool gnd_in_band(unsigned long long goff, unsigned long long nbytes) {
  return goff < 0x80000ull || (goff < 0x51c000ull && goff + nbytes > 0x514000ull);
}
#endif
inline void emulate_dma(const void* source_base, void* dest_base, u32 tadr, u32 dadr) {
  const u8* src = (const u8*)source_base;
  u8* dst = (u8*)dest_base;

  u32 dest_offset = dadr;
  while (true) {
    u64 tag_data;
    memcpy(&tag_data, src + tadr, 8);
    DmaTag tag(tag_data);

    switch (tag.kind) {
      case DmaTag::Kind::CNT:
#ifdef __aarch64__
        { unsigned long long _g = (unsigned long long)((const unsigned char*)((u8*)dst + dest_offset) - (const unsigned char*)source_base);
          unsigned long long _n = (unsigned long long)((1u + tag.qwc) * 16);
          if (gnd_in_band(_g, _n)) gnd_oob_report('C', (unsigned int)_g, _n, (unsigned long long)tadr, (int)tag.qwc); }
#endif
        memcpy(dst + dest_offset, src + tadr, (1 + tag.qwc) * 16);
        dest_offset += (1 + tag.qwc) * 16;
        tadr += 16 + tag.qwc * 16;
        break;
      case DmaTag::Kind::NEXT:
#ifdef __aarch64__
        { unsigned long long _g = (unsigned long long)((const unsigned char*)((u8*)dst + dest_offset) - (const unsigned char*)source_base);
          unsigned long long _n = (unsigned long long)((1u + tag.qwc) * 16);
          if (gnd_in_band(_g, _n)) gnd_oob_report('N', (unsigned int)_g, _n, (unsigned long long)tadr, (int)tag.qwc); }
#endif
        memcpy(dst + dest_offset, src + tadr, (1 + tag.qwc) * 16);
        dest_offset += (1 + tag.qwc) * 16;
        tadr = tag.addr;
        break;
      case DmaTag::Kind::REF: {
        // tte
#ifdef __aarch64__
        { unsigned long long _g = (unsigned long long)((const unsigned char*)((u8*)dst + dest_offset) - (const unsigned char*)source_base);
          unsigned long long _n = (unsigned long long)(16);
          if (gnd_in_band(_g, _n)) gnd_oob_report('r', (unsigned int)_g, _n, (unsigned long long)tadr, (int)tag.qwc); }
#endif
        memcpy(dst + dest_offset, src + tadr, 16);
        dest_offset += 16;

#ifdef __aarch64__
        { unsigned long long _g = (unsigned long long)((const unsigned char*)((u8*)dst + dest_offset) - (const unsigned char*)source_base);
          unsigned long long _n = (unsigned long long)(tag.qwc * 16u);
          if (gnd_in_band(_g, _n)) gnd_oob_report('R', (unsigned int)_g, _n, (unsigned long long)tadr, (int)tag.qwc); }
#endif
        memcpy(dst + dest_offset, src + tag.addr, tag.qwc * 16);
        dest_offset += tag.qwc * 16;
        tadr += 16;
      } break;
      case DmaTag::Kind::REFE: {
        // tte
#ifdef __aarch64__
        { unsigned long long _g = (unsigned long long)((const unsigned char*)((u8*)dst + dest_offset) - (const unsigned char*)source_base);
          unsigned long long _n = (unsigned long long)(16);
          if (gnd_in_band(_g, _n)) gnd_oob_report('e', (unsigned int)_g, _n, (unsigned long long)tadr, (int)tag.qwc); }
#endif
        memcpy(dst + dest_offset, src + tadr, 16);
        dest_offset += 16;

#ifdef __aarch64__
        { unsigned long long _g = (unsigned long long)((const unsigned char*)((u8*)dst + dest_offset) - (const unsigned char*)source_base);
          unsigned long long _n = (unsigned long long)(tag.qwc * 16u);
          if (gnd_in_band(_g, _n)) gnd_oob_report('F', (unsigned int)_g, _n, (unsigned long long)tadr, (int)tag.qwc); }
#endif
        memcpy(dst + dest_offset, src + tag.addr, tag.qwc * 16);
        dest_offset += tag.qwc * 16;
        tadr += 16;
        return;
      } break;
      case DmaTag::Kind::END:
        // does this transfer anything in TTE???
        return;
      default:
        ASSERT_MSG(false, fmt::format("bad tag: {}", (int)tag.kind));
    }
  }
}

#ifdef __aarch64__
// Bounded variant of emulate_dma for the arm64 merc blend-shape (blerc)
// scratchpad transfer.
//
// On arm64 the blerc path (spad_to_dma_blerc_chain) passes a SOURCE chain
// address `tadr` that is read from a scratchpad slot the preceding hardware DMA
// is supposed to have populated; in the PC emulation that read-after-write
// ordering does not always hold, so `tadr` can be garbage (see the in-source
// note at game/mips2c/jak1_functions/merc_blend_shape.cpp:172). A garbage chain
// makes the stock emulate_dma follow malformed tags (huge qwc / wild next-addr)
// and run the destination cursor far past the 16 KB scratchpad and the source
// cursor past the end of EE RAM -> writes scatter over the heap and past
// g_ee_main_mem (SIGSEGV) while a derailed kernel returns into freed code
// (SIGILL). This is the recurring "merc DMA stomp" that Gnd/Gmatch/Gcine3 only
// mitigated downstream with code canaries; the new-game cutscene's correct
// camera CUTs reveal the misty villains (pris/envmap blend-shape merc) and
// trigger it.
//
// This variant enforces exactly the invariant that every sibling spad builder
// already ASSERTs (writes stay inside the scratchpad, reads stay inside EE RAM)
// and ABORTS the transfer the instant a malformed chain would violate it,
// confining the damage. On a well-formed chain (x86, and the non-corrupted
// arm64 case) it is byte-for-byte identical to emulate_dma. Returns true iff it
// aborted a malformed chain early. `dest_limit` is the scratchpad size (0x4000);
// `ee_size` is EE_MAIN_MEM_SIZE.
inline bool emulate_dma_bounded(const void* source_base,
                                void* dest_base,
                                u32 tadr,
                                u32 dadr,
                                u32 dest_limit,
                                u64 ee_size) {
  const u8* src = (const u8*)source_base;
  u8* dst = (u8*)dest_base;
  u32 dest_offset = dadr;
  int guard = 0;
  auto bail = [&](char why, u64 nb) -> bool {
    gnd_oob_report(why, dest_offset, nb, (u64)tadr, guard);
    return true;
  };
  while (true) {
    if (++guard > 8192) {
      return bail('L', 0);  // runaway / self-referential chain
    }
    if ((u64)tadr + 8 > ee_size) {
      return bail('t', 8);  // DMA tag read past end of EE RAM
    }
    u64 tag_data;
    memcpy(&tag_data, src + tadr, 8);
    DmaTag tag(tag_data);
    switch (tag.kind) {
      case DmaTag::Kind::CNT: {
        const u64 nb = (u64)(1 + tag.qwc) * 16;
        if ((u64)dest_offset + nb > dest_limit) {
          return bail('D', nb);  // write would leave the scratchpad
        }
        if ((u64)tadr + nb > ee_size) {
          return bail('s', nb);  // read would leave EE RAM
        }
        memcpy(dst + dest_offset, src + tadr, nb);
        dest_offset += (u32)nb;
        tadr += (u32)nb;
      } break;
      case DmaTag::Kind::NEXT: {
        const u64 nb = (u64)(1 + tag.qwc) * 16;
        if ((u64)dest_offset + nb > dest_limit) {
          return bail('D', nb);
        }
        if ((u64)tadr + nb > ee_size) {
          return bail('s', nb);
        }
        memcpy(dst + dest_offset, src + tadr, nb);
        dest_offset += (u32)nb;
        tadr = tag.addr;
      } break;
      case DmaTag::Kind::REF: {
        if ((u64)dest_offset + 16 > dest_limit || (u64)tadr + 16 > ee_size) {
          return bail('D', 16);
        }
        memcpy(dst + dest_offset, src + tadr, 16);
        dest_offset += 16;
        const u64 nb = (u64)tag.qwc * 16;
        if ((u64)dest_offset + nb > dest_limit || (u64)tag.addr + nb > ee_size) {
          return bail('R', nb);
        }
        memcpy(dst + dest_offset, src + tag.addr, nb);
        dest_offset += (u32)nb;
        tadr += 16;
      } break;
      case DmaTag::Kind::REFE: {
        if ((u64)dest_offset + 16 > dest_limit || (u64)tadr + 16 > ee_size) {
          return bail('D', 16);
        }
        memcpy(dst + dest_offset, src + tadr, 16);
        dest_offset += 16;
        const u64 nb = (u64)tag.qwc * 16;
        if ((u64)dest_offset + nb > dest_limit || (u64)tag.addr + nb > ee_size) {
          return bail('F', nb);
        }
        memcpy(dst + dest_offset, src + tag.addr, nb);
        dest_offset += (u32)nb;
        tadr += 16;
        return false;
      }
      case DmaTag::Kind::END:
        return false;
      default:
        return bail('k', 0);  // malformed tag kind -> abort (stock code ASSERTs)
    }
  }
}
#endif

struct VifCode {
  enum class Kind : u8 {
    NOP = 0b0,
    STCYCL = 0b1,
    OFFSET = 0b10,
    BASE = 0b11,
    ITOP = 0b100,
    STMOD = 0b101,
    PC_PORT = 0b1000,  // not a valid PS2 VIF code, but we use this to signal PC-PORT specific stuff
    PC_PORT2 = 0b1001,
    MSK3PATH = 0b110,
    MARK = 0b111,
    FLUSHE = 0b10000,
    FLUSH = 0b10001,
    FLUSHA = 0b10011,
    MSCAL = 0b10100,
    MSCNT = 0b10111,
    MSCALF = 0b10101,
    STMASK = 0b100000,
    STROW = 0b110000,
    STCOL = 0b110001,
    MPG = 0b1001010,
    DIRECT = 0b1010000,
    DIRECTHL = 0b1010001,
    UNPACK_MASK = 0b1100000,  // unpack is a bunch of commands.
    UNPACK_V4_32 = 0b1101100,
    UNPACK_V4_16 = 0b1101101,
    UNPACK_V3_32 = 0b1101000,
    UNPACK_V4_8 = 0b1101110,
    UNPACK_V2_16 = 0b1100101,
  };

  VifCode(u32 value) {
    interrupt = (value) & (1 << 31);
    kind = (Kind)((value >> 24) & 0b111'1111);
    num = (value >> 16) & 0xff;
    immediate = value & 0xffff;
  }

  bool interrupt = false;
  Kind kind;
  u16 num;
  u16 immediate;

  std::string print() const;
};

struct VifCodeStcycl {
  explicit VifCodeStcycl(const VifCode& code) {
    cl = code.immediate & 0xff;
    wl = (code.immediate >> 8);
  }

  u16 cl;
  u16 wl;
};

struct VifCodeUnpack {
  explicit VifCodeUnpack(const VifCode& code) {
    addr_qw = code.immediate & 0b1111111111;
    is_unsigned = (code.immediate & (1 << 14));
    use_tops_flag = (code.immediate & (1 << 15));
  }

  u16 addr_qw;
  bool is_unsigned;    // only care for 8/16 bit data.
  bool use_tops_flag;  // uses double buffering
};
