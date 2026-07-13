#include "klink.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifdef __ANDROID__
#include <android/log.h>
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"
#include "common/symbols.h"

#include "game/kernel/common/fileio.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kmachine.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/memory_layout.h"
#include "game/kernel/jak1/kboot.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/mips2c/mips2c_table.h"

#include "fmt/format.h"

static constexpr bool link_debug_printfs = false;
/*!
 * Make progress on linking.
 */
uint32_t link_control::jak1_work() {
  auto old_debug_segment = DebugSegment;
  if (m_keep_debug) {
    DebugSegment = s7.offset + true_symbol_offset(g_game_version);
  }

  // set type tag of link block
  *((m_link_block_ptr - 4).cast<u32>()) = *((s7 + jak1_symbols::FIX_SYM_LINK_BLOCK).cast<u32>());

  uint32_t rv;

  if (m_version == 3) {
    ASSERT(m_opengoal);
    rv = jak1_work_v3();
  } else if (m_version == 2 || m_version == 4) {
    ASSERT(!m_opengoal);
    rv = jak1_work_v2();
  } else {
    ASSERT_MSG(false, fmt::format("UNHANDLED OBJECT FILE VERSION {} IN WORK!", m_version));
    return 0;
  }

  DebugSegment = old_debug_segment;
  return rv;
}
namespace {
/*!
 * Link a single relative offset (used for RIP)
 */
uint32_t cross_seg_dist_link_v3(Ptr<uint8_t> link,
                                ObjectFileHeader* ofh,
                                int current_seg,
                                int size) {
  // target seg, dist into mine, dist into target, patch loc in mine
  uint8_t target_seg = *link;
  ASSERT(target_seg < ofh->segment_count);

  uint32_t* link_data = (link + 1).cast<uint32_t>().c();
  int32_t mine = link_data[0] + ofh->code_infos[current_seg].offset;
  int32_t tgt = link_data[1] + ofh->code_infos[target_seg].offset;
  int32_t diff = tgt - mine;
  uint32_t offset_of_patch = link_data[2] + ofh->code_infos[current_seg].offset;

  if (!ofh->code_infos[target_seg].offset) {
    // we want to address GOAL 0. In the case where this is a rip-relative load or store, this
    // will crash, which is what we want. If it's an lea and just getting an address, this will get
    // us a nullptr. If you do a method-set! with a null pointer it does nothing, so it's safe to
    // method-set! to things that are in unloaded segments and it'll just keep the old method.
    diff = -mine;
  }
  // printf("link object in seg %d diff %d at %d (%d + %d)\n", target_seg, diff, offset_of_patch,
  // link_data[2], ofh->code_infos[current_seg].offset);

  // both 32-bit and 64-bit pointer links are supported, though 64-bit ones are no longer in use.
  // we still support it just in case we want to run ancient code.
  if (size == 4) {
    int32_t* slot_addr = Ptr<int32_t>(offset_of_patch).c();
    // arm64 may have an ADRP / ADD / LDR / STR imm-carrying instruction at this
    // patch slot — the runtime dispatcher rewrites only the immediate bits
    // (computing page-delta from the slot PC and the target host address).
    // For x86 (and arm64 data slots), the dispatcher returns kNotInstr and we
    // fall back to the raw int32 store of `diff` below.
    uintptr_t target_host =
        reinterpret_cast<uintptr_t>(Ptr<int32_t>(tgt).c());
    auto rc = klink_arm64_patch_pc_rel(reinterpret_cast<uint32_t*>(slot_addr),
                                       target_host);
    if (rc == KlinkArm64PatchResult::kNotInstr) {
      *slot_addr = diff;
    }
  } else if (size == 8) {
    *Ptr<int64_t>(offset_of_patch).c() = diff;
  } else {
    ASSERT(false);
  }

  return 1 + 3 * 4;
}

uint32_t ptr_link_v3(Ptr<u8> link, ObjectFileHeader* ofh, int current_seg) {
  auto* link_data = link.cast<u32>().c();
  u32 patch_loc = link_data[0] + ofh->code_infos[current_seg].offset;
  u32 patch_value = link_data[1] + ofh->code_infos[current_seg].offset;
  // arm64 ptr-link slots may be an ADRP/ADD pair materialising the target
  // address into a GPR. The dispatcher patches the imm field; on x86 (or
  // an arm64 data-segment ptr slot) it returns kNotInstr and we fall
  // back to the raw u32 store.
  uintptr_t target_host = reinterpret_cast<uintptr_t>(Ptr<u8>(patch_value).c());
  auto rc = klink_arm64_patch_pc_rel(
      reinterpret_cast<uint32_t*>(Ptr<u32>(patch_loc).c()), target_host);
  if (rc == KlinkArm64PatchResult::kNotInstr) {
    *Ptr<u32>(patch_loc).c() = patch_value;
  }
  return 8;
}

/*!
 * Link type pointers for a single type in "v3 equivalent" link data
 * Returns a pointer to the link table data after the typelinking data.
 */
uint32_t typelink_v3(Ptr<uint8_t> link, Ptr<uint8_t> data) {
  // get the name of the type
  uint32_t seek = 0;
  char sym_name[256];
  while (link.c()[seek]) {
    sym_name[seek] = link.c()[seek];
    seek++;
    ASSERT(seek < 256);
  }
  sym_name[seek] = 0;
  seek++;

  // determine the number of methods
  uint8_t method_count = link.c()[seek++];

  // intern the GOAL type, creating the vtable if it doesn't exist.
  auto type_ptr = jak1::intern_type_from_c(sym_name, method_count);

  // B1 — structured boot-link trace (gated by OG_KLINK_TRACE; zero output
  // when unset). Records the type alloc/intern with its (zero-initialized)
  // method-table size — the heart of the slot-22 method-bind bug.
  static const bool s_klink_trace = (std::getenv("OG_KLINK_TRACE") != nullptr);
  if (s_klink_trace) {
    std::fprintf(stderr, "KLINKTRACE type name=%s num_methods=%u addr=0x%lx\n",
                 sym_name, (unsigned)method_count,
                 (unsigned long)Ptr<u8>(type_ptr.offset).c());
  }

  // prepare to read the locations of the type pointers
  Ptr<uint32_t> offsets = link.cast<uint32_t>() + seek;
  uint32_t offset_count = *offsets;
  offsets = offsets + 4;
  seek += 4;

  // write the type pointers into memory
  for (uint32_t i = 0; i < offset_count; i++) {
    auto data_ptr = (data + offsets.c()[i]).cast<int32_t>();
    // arm64 type-pointer references materialise via ADRP+ADD (host
    // address of the type-vtable). The dispatcher rewrites only the
    // imm field; arm64 data slots and the entire x86 path fall through
    // to the raw 32-bit type-offset store below.
    uintptr_t target_host =
        reinterpret_cast<uintptr_t>(Ptr<u8>(type_ptr.offset).c());
    auto rc = klink_arm64_patch_pc_rel(reinterpret_cast<uint32_t*>(data_ptr.c()),
                                       target_host);
    if (rc == KlinkArm64PatchResult::kNotInstr) {
      *data_ptr = type_ptr.offset;
    }
    seek += 4;
  }

  return seek;
}

/*!
 * Link symbols (both offsets and pointers) in "v3 equivalent" link data.
 * Returns a pointer to the link table data after the linking data for this symbol.
 */
uint32_t symlink_v3(Ptr<uint8_t> link, Ptr<uint8_t> data) {
  // get the symbol name
  uint32_t seek = 0;
  char sym_name[256];
  while (link.c()[seek]) {
    sym_name[seek] = link.c()[seek];
    seek++;
    ASSERT(seek < 256);
  }
  sym_name[seek] = 0;
  seek++;

  // intern
  auto sym = jak1::intern_from_c(sym_name);
  int32_t sym_offset = sym.cast<u32>() - s7;
  uint32_t sym_addr = sym.cast<u32>().offset;

  // prepare to read locations of symbol links
  Ptr<uint32_t> offsets = link.cast<uint32_t>() + seek;
  uint32_t offset_count = *offsets;
  offsets = offsets + 4;
  seek += 4;

  // A8 — qemu repro diagnostic. When OG_KLINK_TRACE env var is set,
  // print the symbol name + every patched slot's address. This lets
  // us correlate a GK-DIAG crash dump (which shows the failing host
  // address) back to the symbol that wasn't installed at runtime.
  // No-op in normal device builds (no env var → no log noise).
  static const bool s_klink_trace = (std::getenv("OG_KLINK_TRACE") != nullptr);

  for (uint32_t i = 0; i < offset_count; i++) {
    uint32_t offset = offsets.c()[i];
    seek += 4;
    auto data_ptr = (data + offset).cast<int32_t>();
    int32_t pre = *data_ptr;

    // arm64 sym-load slots are ADRP / ADD / LDR / STR with the imm
    // field carrying the symbol's host address. The dispatcher patches
    // only the imm bits, leaving the opcode intact. A x86 patch slot
    // (or an arm64 GOAL data word) returns kNotInstr — fall through
    // to the existing sentinel-based logic: -1 → store sym_addr (full
    // address), anything else → store sym_offset (offset from s7).
    uintptr_t target_host = reinterpret_cast<uintptr_t>(Ptr<u8>(sym_addr).c());
    auto rc = klink_arm64_patch_pc_rel(reinterpret_cast<uint32_t*>(data_ptr.c()),
                                       target_host);
    if (rc == KlinkArm64PatchResult::kNotInstr) {
      if (pre == -1) {
        // a "-1" indicates that we should store the address.
        *(data + offset).cast<int32_t>() = sym_addr;
      } else {
        // otherwise store the offset to st.  Eventually this should become an s16 instead.
        *(data + offset).cast<int32_t>() = sym_offset;
      }
    }

    if (s_klink_trace) {
      // Read the symbol's value at *patch time*. A '0' means no defun
      // /defmethod /InitMachineScheme entry has populated this symbol's
      // value cell yet — which is normal until that file links, but
      // becomes the bug if a caller invokes the symbol before its
      // value is set.
      const auto sym_val = *Ptr<u32>(sym_addr).c();
      std::fprintf(stderr,
                   "[A8 symlink] sym='%s' sym_addr=0x%lx sym_val=0x%x "
                   "slot=0x%lx target_host=0x%lx pre=0x%x\n",
                   sym_name, (unsigned long)target_host, (unsigned)sym_val,
                   (unsigned long)data_ptr.c(), (unsigned long)target_host,
                   (unsigned)pre);
    }
  }

  // B1 — structured boot-link trace: one bind event per symbol (gated by
  // OG_KLINK_TRACE; zero output when unset). val is the symbol's value cell
  // at link time (0 = not yet populated by a defun/defmethod).
  if (s_klink_trace) {
    const auto sym_val = *Ptr<u32>(sym_addr).c();
    std::fprintf(stderr, "KLINKTRACE sym name=%s addr=0x%lx val=0x%x\n", sym_name,
                 (unsigned long)Ptr<u8>(sym_addr).c(), (unsigned)sym_val);
  }

  return seek;
}

}  // namespace
/*!
 * Run the linker. For now, all linking is done in two runs.  If this turns out to be too slow,
 * this should be modified to do incremental linking over multiple runs.
 */
uint32_t link_control::jak1_work_v3() {
  ObjectFileHeader* ofh = m_link_block_ptr.cast<ObjectFileHeader>().c();
  if (m_state == 0) {
    // state 0 <- copying data.
    // the actual game does all copying in one shot. I assume this is ok because v3 files are just
    // code and always small.  Large data which takes too long to copy should use v2.

    // loop over segments
    for (s32 seg_id = ofh->segment_count - 1; seg_id >= 0; seg_id--) {
      // link the infos
      ofh->link_infos[seg_id].offset += m_link_block_ptr.offset;
      ofh->code_infos[seg_id].offset += m_object_data.offset;

      if (seg_id == DEBUG_SEGMENT) {
        if (!DebugSegment) {
          // clear code info if we aren't going to copy the debug segment.
          ofh->code_infos[seg_id].offset = 0;
          ofh->code_infos[seg_id].size = 0;
        } else {
          if (ofh->code_infos[seg_id].size == 0) {
            // not actually present
            ofh->code_infos[seg_id].offset = 0;
          } else {
            Ptr<u8> src(ofh->code_infos[seg_id].offset);
            ofh->code_infos[seg_id].offset =
                kmalloc(kdebugheap, ofh->code_infos[seg_id].size, 0, "debug-segment").offset;
            if (ofh->code_infos[seg_id].offset == 0) {
              MsgErr("dkernel: unable to malloc %d bytes for debug-segment\n",
                     ofh->code_infos[seg_id].size);
              return 1;
            }
            jak1::ultimate_memcpy(Ptr<u8>(ofh->code_infos[seg_id].offset).c(), src.c(),
                                  ofh->code_infos[seg_id].size);
          }
        }
      } else if (seg_id == MAIN_SEGMENT) {
        if (ofh->code_infos[seg_id].size == 0) {
          ofh->code_infos[seg_id].offset = 0;
        } else {
          Ptr<u8> src(ofh->code_infos[seg_id].offset);
          ofh->code_infos[seg_id].offset =
              kmalloc(m_heap, ofh->code_infos[seg_id].size, 0, "main-segment").offset;
          if (ofh->code_infos[seg_id].offset == 0) {
            MsgErr("dkernel: unable to malloc %d bytes for main-segment\n",
                   ofh->code_infos[seg_id].size);
            return 1;
          }
#if defined(__ANDROID__)
          if (m_heap.offset != kglobalheap.offset && m_heap.offset != kdebugheap.offset) {
            jak1::invalidate_part_groups_in_range(ofh->code_infos[seg_id].offset,
                                                  ofh->code_infos[seg_id].size);
          }
#endif
          jak1::ultimate_memcpy(Ptr<u8>(ofh->code_infos[seg_id].offset).c(), src.c(),
                                ofh->code_infos[seg_id].size);
        }
      } else if (seg_id == TOP_LEVEL_SEGMENT) {
        if (ofh->code_infos[seg_id].size == 0) {
          ofh->code_infos[seg_id].offset = 0;
        } else {
          Ptr<u8> src(ofh->code_infos[seg_id].offset);
          ofh->code_infos[seg_id].offset =
              kmalloc(m_heap, ofh->code_infos[seg_id].size, KMALLOC_TOP, "top-level-segment")
                  .offset;
          if (ofh->code_infos[seg_id].offset == 0) {
            MsgErr("dkernel: unable to malloc %d bytes for top-level-segment\n",
                   ofh->code_infos[seg_id].size);
            return 1;
          }
#if defined(__ANDROID__)
          if (m_heap.offset != kglobalheap.offset && m_heap.offset != kdebugheap.offset) {
            jak1::invalidate_part_groups_in_range(ofh->code_infos[seg_id].offset,
                                                  ofh->code_infos[seg_id].size);
          }
#endif
          jak1::ultimate_memcpy(Ptr<u8>(ofh->code_infos[seg_id].offset).c(), src.c(),
                                ofh->code_infos[seg_id].size);
        }
      } else {
        printf("UNHANDLED SEG ID IN WORK V3 STATE 1\n");
      }
    }

    m_state = 1;
    m_segment_process = 0;
    return 0;
  } else if (m_state == 1) {
    // state 1: linking. For now all links are done at once. This is probably going to be fine on a
    // modern computer.  But the game broke this into multiple steps.
    if (m_segment_process < ofh->segment_count) {
      if (ofh->code_infos[m_segment_process].offset) {
        Ptr<u8> lp(ofh->link_infos[m_segment_process].offset);

        while (*lp) {
          switch (*lp) {
            case LINK_TABLE_END:
              break;
            case LINK_SYMBOL_OFFSET:
              lp = lp + 1;
              lp = lp + symlink_v3(lp, Ptr<u8>(ofh->code_infos[m_segment_process].offset));
              break;
            case LINK_TYPE_PTR:
              lp = lp + 1;  // seek past id
              lp = lp + typelink_v3(lp, Ptr<u8>(ofh->code_infos[m_segment_process].offset));
              break;
            case LINK_DISTANCE_TO_OTHER_SEG_64:
              lp = lp + 1;
              lp = lp + cross_seg_dist_link_v3(lp, ofh, m_segment_process, 8);
              break;
            case LINK_DISTANCE_TO_OTHER_SEG_32:
              lp = lp + 1;
              lp = lp + cross_seg_dist_link_v3(lp, ofh, m_segment_process, 4);
              break;
            case LINK_PTR:
              lp = lp + 1;
              lp = lp + ptr_link_v3(lp, ofh, m_segment_process);
              break;
            default:
              ASSERT_MSG(false, fmt::format("unknown link table thing {}", *lp));
              break;
          }
        }
      }

      m_segment_process++;
    } else {
      // all done, can set the entry point to the top-level.
      m_entry = Ptr<u8>(ofh->code_infos[TOP_LEVEL_SEGMENT].offset) + 4;
      return 1;
    }

    return 0;
  }

  else {
    printf("WORK v3 INVALID STATE\n");
    return 1;
  }
}

#define LINK_V2_STATE_INIT_COPY 0
#define LINK_V2_STATE_OFFSETS 1
#define LINK_V2_STATE_SYMBOL_TABLE 2
#define OBJ_V2_CLOSE_ENOUGH 0x90
#define OBJ_V2_MAX_TRANSFER 0x80000

uint32_t link_control::jak1_work_v2() {
  //  u32 startCycle = kernel.read_clock(); todo

  if (m_state == LINK_V2_STATE_INIT_COPY) {  // initialization and copying to heap
    // we move the data segment to eliminate gaps
    // very small gaps can be tolerated, as it is not worth the time penalty to move large objects
    // many bytes. if this requires copying a large amount of data, we will do it in smaller chunks,
    // allowing the copy to be spread over multiple game frames

    // state initialization
    if (m_segment_process == 0) {
      m_heap_gap =
          m_object_data - m_heap->current;  // distance between end of heap and start of object
    }

    if (m_heap_gap <
        OBJ_V2_CLOSE_ENOUGH) {  // close enough, don't relocate the object, just expand the heap
      if (link_debug_printfs) {
        printf("[work_v2] close enough, not moving\n");
      }
      m_heap->current = m_object_data + m_code_size;
      if (m_heap->top.offset <= m_heap->current.offset) {
        MsgErr("dkernel: heap overflow\n");  // game has ~% instead of \n :P
        return 1;
      }
    } else {  // not close enough, need to move the object

      // on the first run of this state...
      if (m_segment_process == 0) {
        m_original_object_location = m_object_data;
        // allocate on heap, will have no gap
        m_object_data = kmalloc(m_heap, m_code_size, 0, "data-segment");
        if (link_debug_printfs) {
          printf("[work_v2] moving from 0x%x to 0x%x\n", m_original_object_location.offset,
                 m_object_data.offset);
        }
        if (!m_object_data.offset) {
          MsgErr("dkernel: unable to malloc %d bytes for data-segment\n", m_code_size);
          return 1;
        }
      }

      // the actual copy
      Ptr<u8> source = m_original_object_location + m_segment_process;
      u32 size = m_code_size - m_segment_process;

      if (size > OBJ_V2_MAX_TRANSFER) {  // around .5 MB
        jak1::ultimate_memcpy((m_object_data + m_segment_process).c(), source.c(),
                              OBJ_V2_MAX_TRANSFER);
        m_segment_process += OBJ_V2_MAX_TRANSFER;
        return 0;  // return, don't want to take too long.
      }

      // if we have bytes to copy, but they are less than the max transfer, do it in one shot!
      if (size) {
        jak1::ultimate_memcpy((m_object_data + m_segment_process).c(), source.c(), size);
        if (m_segment_process > 0) {  // if we did a previous copy, we return now....
          m_state = LINK_V2_STATE_OFFSETS;
          m_segment_process = 0;
          return 0;
        }
      }
    }

    // otherwise go straight into the next state.
    m_state = LINK_V2_STATE_OFFSETS;
    m_segment_process = 0;
  }

  // init offset phase
  if (m_state == LINK_V2_STATE_OFFSETS && m_segment_process == 0) {
    m_reloc_ptr = m_link_block_ptr + 8;  // seek to link table
    if (*m_reloc_ptr == 0) {             // do we have pointer links to do?
      m_reloc_ptr.offset++;              // if not, seek past the \0, and go to next state
      m_state = LINK_V2_STATE_SYMBOL_TABLE;
      m_segment_process = 0;
    } else {
      m_base_ptr = m_object_data;  // base address for offsetting.
      m_loc_ptr = m_object_data;   // pointer which seeks thru the code
      m_table_toggle = 0;          // are we seeking or fixing?
      m_segment_process = 1;       // we've done first time setup
    }
  }

  if (m_state == LINK_V2_STATE_OFFSETS) {  // pointer fixup
    // this state reads through a table. Values alternate between "seek amount" and "number of
    // consecutive 4-byte
    //  words to fix up".  The counts are encoded using a variable length encoding scheme.  They use
    //  a very stupid
    // method of encoding values which requires O(n) bytes to store the value n.

    // to avoid dropping a frame, we check every 0x400 relocations to see if 0.5 milliseconds have
    // elapsed.
    u32 relocCounter = 0x400;
    while (true) {    // loop over entire table
      while (true) {  // loop over current mode

        // read and seek table
        u8 count = *m_reloc_ptr;
        m_reloc_ptr.offset++;

        if (!m_table_toggle) {  // seek mode
          m_loc_ptr.offset +=
              4 *
              count;  // perform seek (MIPS instructions are 4 bytes, so we >> 2 the seek amount)
        } else {      // offset mode
          for (u32 i = 0; i < count; i++) {
            if (m_loc_ptr.offset % 4) {
              ASSERT(false);
            }
            u32 code = *(m_loc_ptr.cast<u32>());
            code += m_base_ptr.offset;
            *(m_loc_ptr.cast<u32>()) = code;
            m_loc_ptr.offset += 4;
          }
        }

        if (count != 0xff) {
          break;
        }

        if (*m_reloc_ptr == 0) {
          m_reloc_ptr.offset++;
          m_table_toggle = m_table_toggle ^ 1;
        }
      }

      // reached the end of the tableToggle mode
      m_table_toggle = m_table_toggle ^ 1;
      if (*m_reloc_ptr == 0) {
        break;  // end of the state
      }
      relocCounter--;
      if (relocCounter == 0) {
        //        u32 clock_value = kernel.read_clock();
        //        if(clock_value - startCycle > 150000) { // 0.5 milliseconds
        //          return 0;
        //        }
        relocCounter = 0x400;
      }
    }
    m_reloc_ptr.offset++;
    m_state = 2;
    m_segment_process = 0;
  }

  if (m_state == 2) {  // GOAL object fixup
    if (*m_reloc_ptr == 0) {
      m_state = 3;
      m_segment_process = 0;
    } else {
      while (true) {
        u32 relocation = *m_reloc_ptr;
        m_reloc_ptr.offset++;
        Ptr<u8> goalObj;
        char* name;
        if ((relocation & 0x80) == 0) {
          // symbol!
          if (relocation > 9) {
            m_reloc_ptr.offset--;  // no idea what this is.
          }
          name = m_reloc_ptr.cast<char>().c();
          if (link_debug_printfs) {
            printf("[work_v2] symlink: %s\n", name);
          }
          goalObj = jak1::intern_from_c(name).cast<u8>();
        } else {
          // type!
          u8 nMethods = relocation & 0x7f;
          if (nMethods == 0) {
            nMethods = 1;
          }
          name = m_reloc_ptr.cast<char>().c();
          if (link_debug_printfs) {
            printf("[work_v2] symlink -type: %s\n", name);
          }
          goalObj = jak1::intern_type_from_c(name, nMethods).cast<u8>();
        }
        m_reloc_ptr.offset += strlen(name) + 1;
        // DECOMPILER->hookStartSymlinkV3(_state - 1, _objectData, std::string(name));
        m_reloc_ptr = c_symlink2(m_object_data, goalObj, m_reloc_ptr);
        // DECOMPILER->hookFinishSymlinkV3();
        if (*m_reloc_ptr == 0) {
          break;  // done
        }
        //        u32 currentCycle = kernel.read_clock();
        //        if(currentCycle - startCycle > 150000) {
        //          return 0;
        //        }
      }
      m_state = 3;
      m_segment_process = 0;
    }
  }
  m_entry = m_object_data + 4;
  return 1;
}

// Gjak1-intermittent-events A/B diag: `setprop debug.opengoal.icache.noflush 1`
// restores the pre-fix no-op-flush behavior (arm64 bug class #14) so the
// stale-icache arm can be measured against the fixed arm on ONE binary
// (no mixed builds). Default (prop absent/0) = flush ON. Android-only; the
// x86 CacheFlush body is a no-op either way, so x86 is unaffected.
static bool gk_icache_noflush_diag() {
#ifdef __ANDROID__
  char v[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.icache.noflush", v) > 0 && v[0] == '1') {
    static bool logged = false;
    if (!logged) {
      logged = true;
      __android_log_print(ANDROID_LOG_FATAL, "opengoal-gk",
                          "GK-DIAG ICACHE-NOFLUSH armed: jak1_finish CacheFlush skipped "
                          "(bug-class-#14 A/B diag)");
    }
    return true;
  }
#endif
  return false;
}

/*!
 * Complete linking. This will execute the top-level code for v3 object files, if requested.
 */
void link_control::jak1_finish(bool jump_from_c_to_goal) {
  // arm64 bug class #14 (stale icache on linked code) — same fix as jak2_finish:
  // m_code_size is never assigned on the opengoal v3 path (jak1_jak2_begin
  // leaves it 0 — "todo, set m_code_size"), so this flush was
  // CacheFlush(base, 0), a no-op. The v3 TOP_LEVEL segment is re-allocated at
  // the SAME reused KMALLOC_TOP address for consecutive objects and executed
  // immediately after being rewritten; without an icache invalidate the CPU
  // can fetch a stale mix of the PREVIOUS object's instructions (memory reads
  // back correct, I-fetch is stale). On the arm64 builds CacheFlush is
  // __builtin___clear_cache(mem, mem+size); the x86 CacheFlush body is a
  // no-op, so x86 behavior is unchanged.
  if (!gk_icache_noflush_diag()) {
    ObjectFileHeader* fofh = m_link_block_ptr.cast<ObjectFileHeader>().c();
    if (fofh->object_file_version == 3) {
      // v3 objects wrote executable code into freshly kmalloc'd segments (MAIN
      // in m_heap, TOP_LEVEL at the reused KMALLOC_TOP address, DEBUG in
      // kdebugheap when DebugSegment is set). code_infos[seg].offset holds the
      // final runtime address and is 0 for any segment that was not copied, so
      // the offset&&size guard naturally skips absent/dropped segments.
      for (int seg : {MAIN_SEGMENT, TOP_LEVEL_SEGMENT, DEBUG_SEGMENT}) {
        if (fofh->code_infos[seg].offset && fofh->code_infos[seg].size) {
          CacheFlush(Ptr<u8>(fofh->code_infos[seg].offset).c(), fofh->code_infos[seg].size);
        }
      }
    } else {
      // v2/v4 objects link code in place at m_object_data; the non-opengoal
      // begin paths set m_code_size (m_object_size - header->length for v2,
      // header_v4->code_size for v4).
      if (m_object_data.offset && m_code_size) {
        CacheFlush(m_object_data.c(), m_code_size);
      }
    }
  }
  auto old_debug_segment = DebugSegment;
  if (m_keep_debug) {
    // note - this probably doesn't work because DebugSegment isn't *debug-segment*.
    DebugSegment = s7.offset + jak1_symbols::FIX_SYM_TRUE;
  }
  if (m_flags & LINK_FLAG_FORCE_FAST_LINK) {
    FastLink = 1;
  }
  *EnableMethodSet = *EnableMethodSet + m_keep_debug;

  ObjectFileHeader* ofh = m_link_block_ptr.cast<ObjectFileHeader>().c();
  lg::debug("link finish: {}", m_object_name);

  // B1 — structured boot-link trace: per-object link-finish with a monotonic
  // sequence number (gated by OG_KLINK_TRACE; zero output when unset). The seq
  // anchors the per-(type,slot) method timeline so Phase B2 can align the x86
  // and ARM64 bind orders.
  {
    static const bool s_klink_trace = (std::getenv("OG_KLINK_TRACE") != nullptr);
    if (s_klink_trace) {
      static u32 s_finish_seq = 0;
      std::fprintf(stderr, "KLINKTRACE finish obj=%s seq=%u\n", m_object_name,
                   (unsigned)(++s_finish_seq));
    }
  }

  // A39 — symbol-table forensics (debug.opengoal.a39.linkscan=1 on Android,
  // OG_A39_LINKSCAN env elsewhere; zero work when unset): after each object
  // link, resolve (a) the slot whose info-name is exactly "draw-string" and
  // (b) the shared-noop value via the "__a37-mips2c-noop" symbol, then list
  // every slot holding that noop value. Prints only when the observed state
  // changes — brackets the writer that replaces font.o's noop bind with the
  // in-band poison (run1 SIGILL: slot 0x159344 := 0x190bb34) to one object.
  {
    static const int s_a39_scan = []() -> int {
#ifdef __ANDROID__
      char b[92] = {0};
      if (__system_property_get("debug.opengoal.a39.linkscan", b) > 0 && b[0] == '1') {
        return 1;
      }
#endif
      return std::getenv("OG_A39_LINKSCAN") ? 1 : 0;
    }();
    if (s_a39_scan && SymbolTable2.offset && LastSymbol.offset) {
      u32 ds_slot = 0, ds_val = 0, noop_val = 0;
      for (u32 slot = SymbolTable2.offset; slot < LastSymbol.offset; slot += 4) {
        auto sym = Ptr<jak1::Symbol>(slot);
        u32 stro = jak1::info(sym)->str.offset;
        if (!stro || stro >= EE_MAIN_MEM_SIZE - 64) {
          continue;
        }
        const char* nm = reinterpret_cast<const char*>(Ptr<u8>(stro + 4).c());
        if (!ds_slot && memcmp(nm, "draw-string", 12) == 0) {
          ds_slot = slot;
          ds_val = sym->value;
        }
        if (!noop_val && memcmp(nm, "__a37-mips2c-noop", 18) == 0) {
          noop_val = sym->value;
        }
        if (ds_slot && noop_val) {
          break;
        }
      }
      int nh = 0;
      u32 noop_holders[4] = {0, 0, 0, 0};
      if (noop_val) {
        for (u32 slot = SymbolTable2.offset; slot < LastSymbol.offset && nh < 4; slot += 4) {
          if (*Ptr<u32>(slot) == noop_val) {
            noop_holders[nh++] = slot;
          }
        }
      }
      static u32 s_prev_ds_slot = 0xffffffffu;
      static u32 s_prev_ds_val = 0xffffffffu;
      static int s_prev_nh = -1;
      // Sample the first 4 code words at the draw-string target: the run1
      // crash executed DMA-tag-looking bytes at the (healthy-on-disk)
      // GOAL draw-string body, so the smash is at runtime — the link after
      // which these words flip names the window.
      u32 code_w[4] = {0, 0, 0, 0};
      if (ds_val >= 0x1000 && ds_val < EE_MAIN_MEM_SIZE - 16) {
        for (int i = 0; i < 4; i++) {
          code_w[i] = *Ptr<u32>(ds_val + 4 * i);
        }
      }
      static u32 s_prev_code0 = 0xffffffffu;
      if (ds_slot != s_prev_ds_slot || ds_val != s_prev_ds_val || nh != s_prev_nh ||
          code_w[0] != s_prev_code0) {
        std::fprintf(stderr,
                     "A39-LINKSCAN obj=%s ds-slot=0x%x ds-val=0x%x code=[%08x %08x %08x %08x] "
                     "noop=0x%x holders=%d [0x%x 0x%x 0x%x 0x%x]\n",
                     m_object_name, ds_slot, ds_val, code_w[0], code_w[1], code_w[2], code_w[3],
                     noop_val, nh, noop_holders[0], noop_holders[1], noop_holders[2],
                     noop_holders[3]);
        s_prev_ds_slot = ds_slot;
        s_prev_ds_val = ds_val;
        s_prev_nh = nh;
        s_prev_code0 = code_w[0];
      }
    }
  }
  if (ofh->object_file_version == 3) {
    // todo check function type of entry

    // setup mips2c functions
    const auto& it = Mips2C::gMips2CLinkCallbacks[GameVersion::Jak1].find(m_object_name);
    if (it != Mips2C::gMips2CLinkCallbacks[GameVersion::Jak1].end()) {
      for (auto& x : it->second) {
        x();
      }
    }

    // execute top level!
    if (m_entry.offset && (m_flags & LINK_FLAG_EXECUTE)) {
      if (jump_from_c_to_goal) {
        u64 goal_stack = u64(g_ee_main_mem) + EE_MAIN_MEM_SIZE - 8;
        call_goal_on_stack(m_entry.cast<Function>(), goal_stack, s7.offset, g_ee_main_mem);
      } else {
        call_goal(m_entry.cast<Function>(), 0, 0, 0, s7.offset, g_ee_main_mem);
      }
    }

    // inform compiler that we loaded.
    if (m_flags & LINK_FLAG_OUTPUT_LOAD) {
      output_segment_load(m_object_name, m_link_block_ptr, m_flags);
    }
  } else {
    // A29 — mirror the v3 path's `m_entry.offset && LINK_FLAG_EXECUTE` guard.
    // The v2/v4 link can leave m_entry == 0 when `m_object_data = kmalloc(...)`
    // in jak1_work_v2's INIT_COPY (else) branch fails: the function MsgErr's
    // "unable to malloc N bytes for data-segment" and returns 1 (done) WITHOUT
    // reaching the trailing `m_entry = m_object_data + 4`, leaving m_entry at
    // the zero set by jak1_jak2_begin. The v3 path already handles this; the
    // v2 path was missing the check and would dereference (entry-4) on the
    // GOAL heap base, computing g_ee_main_mem + 0xfffffffc → segfault.
    // Triggered on linux-arm64 because direct_load_dgo's 4 MB top buffer
    // pushes heap pressure past dir-tpages's data-segment allocation. The
    // buffer-size tuning that prevents the underlying kmalloc failure lives
    // in linux_arm64_main.cpp; this guard is the right fix regardless because
    // ANY future kmalloc exhaustion (or for that matter any v2 link path that
    // doesn't set m_entry) would re-introduce the crash.
    if (m_entry.offset && (m_flags & LINK_FLAG_EXECUTE)) {
      auto entry = m_entry;
      auto name = basename_goal(m_object_name);
      strcpy(Ptr<char>(LINK_CONTROL_NAME_ADDR).c(), name);
      jak1::call_method_of_type_arg2(entry.offset, Ptr<jak1::Type>(*((entry - 4).cast<u32>())),
                                     GOAL_RELOC_METHOD, m_heap.offset,
                                     Ptr<char>(LINK_CONTROL_NAME_ADDR).offset);
    }
  }

  *EnableMethodSet = *EnableMethodSet - m_keep_debug;
  FastLink = 0;  // nested fast links won't work right.
  m_heap->top = m_heap_top;
  DebugSegment = old_debug_segment;
}

namespace jak1 {

/*!
 * Immediately link and execute an object file.
 * DONE, EXACT
 */
Ptr<uint8_t> link_and_exec(Ptr<uint8_t> data,
                           const char* name,
                           int32_t size,
                           Ptr<kheapinfo> heap,
                           uint32_t flags,
                           bool jump_from_c_to_goal) {
  link_control lc;
  lc.jak1_jak2_begin(data, name, size, heap, flags);
  uint32_t done;
  do {
    done = lc.jak1_work();
  } while (!done);
  lc.jak1_finish(jump_from_c_to_goal);
  return lc.m_entry;
}

/*!
 * Wrapper so this can be called from GOAL. Not in original game.
 */
u64 link_and_exec_wrapper(u64* args) {
  // data, name, size, heap, flags
  return link_and_exec(Ptr<u8>(args[0]), Ptr<char>(args[1]).c(), args[2], Ptr<kheapinfo>(args[3]),
                       args[4], false)
      .offset;
}

/*!
 * GOAL exported function for beginning a link with the saved_link_control
 * 47 -> output_load, output_true, execute, 8, force fast
 * 39 -> no 8 (s7)
 */
uint64_t link_begin(u64* args) {
  // object data, name size, heap flags
  saved_link_control.jak1_jak2_begin(Ptr<u8>(args[0]), Ptr<char>(args[1]).c(), args[2],
                                     Ptr<kheapinfo>(args[3]), args[4]);
  auto work_result = saved_link_control.jak1_work();
  // if we managed to finish in one shot, take care of calling finish
  if (work_result) {
    // called from goal
    saved_link_control.jak1_finish(false);
  }

  return work_result != 0;
}

/*!
 * GOAL exported function for doing a small amount of linking work on the saved_link_control
 */
uint64_t link_resume() {
  auto work_result = saved_link_control.jak1_work();
  if (work_result) {
    // called from goal
    saved_link_control.jak1_finish(false);
  }
  return work_result != 0;
}

/*!
 * The ULTIMATE MEMORY COPY
 * IT IS VERY FAST
 * but it may use the scratchpad.  It is implemented in GOAL, and falls back to normal C memcpy
 * if GOAL isn't loaded, or if the alignment isn't good enough.
 */
void ultimate_memcpy(void* dst, void* src, uint32_t size) {
  // only possible if alignment is good.
  if (!(u64(dst) & 0xf) && !(u64(src) & 0xf) && !(u64(size) & 0xf) && size > 0xfff) {
    if (!gfunc_774.offset) {
      // GOAL function is unknown, lets see if its loaded:
      auto sym = jak1::find_symbol_from_c("ultimate-memcpy");
      if (sym->value == 0) {
        memmove(dst, src, size);
        return;
      }
      gfunc_774.offset = sym->value;
    }

    Ptr<u8>(call_goal(gfunc_774, make_u8_ptr(dst).offset, make_u8_ptr(src).offset, size, s7.offset,
                      g_ee_main_mem))
        .c();
  } else {
    memmove(dst, src, size);
  }
}
}  // namespace jak1
