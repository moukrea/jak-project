/*!
 * @file ObjectGenerator.cpp
 * Tool to build GOAL object files.
 *
 * There are 5 steps:
 * 1. The user adds static data / instructions and specifies links.
 * 2. The functions and static data are laid out in memory
 * 3. The user specified links are updated according to the memory layout, and jumps are patched
 * 4. The link table is generated for each segment
 * 5. All segments and link tables are put into a final object file, along with a header.
 *
 * Step 1 can be done with the add_.... and link_... functions
 * Steps 2 - 5 are done in generate_data_vX()
 */

#include "ObjectGenerator.h"

#include "common/goal_constants.h"
#include "common/type_system/TypeSystem.h"
#include "common/versions/versions.h"

#include "goalc/debugger/DebugInfo.h"

namespace emitter {

ObjectGenerator::ObjectGenerator(GameVersion version)
    : m_version(version), m_instruction_set(InstructionSet::X86) {}

ObjectGenerator::ObjectGenerator(GameVersion version, InstructionSet instr_set)
    : m_version(version), m_instruction_set(instr_set) {}

/*!
 * Build an object file with the v3 format.
 */
ObjectFileData ObjectGenerator::generate_data_v3(const TypeSystem* ts) {
  ObjectFileData out;

  // do functions (step 2, part 1)
  for (int seg = N_SEG; seg-- > 0;) {
    auto& data = m_data_by_seg.at(seg);
    // loop over functions in this segment
    for (auto& function : m_function_data_by_seg.at(seg)) {
      // align
      while (data.size() % function.min_align) {
        insert_data<u8>(seg, 0);
      }

      // add a type tag link
      m_type_ptr_links_by_seg.at(seg)["function"].push_back(data.size());

      // add room for a type tag
      for (int i = 0; i < POINTER_SIZE; i++) {
        insert_data<u8>(seg, 0xae);
      }

      // add debug info for the function start
      function.debug->offset_in_seg = m_data_by_seg.at(seg).size();
      function.debug->seg = seg;

      // insert instructions!

      for (size_t instr_idx = 0; instr_idx < function.instructions.size(); instr_idx++) {
        const auto& instr = function.instructions[instr_idx];
        u8 temp[128];
        auto count = instr.emit(temp);
        ASSERT(count < 128);
        function.instruction_to_byte_in_data.push_back(data.size());
        function.debug->instructions.at(instr_idx).offset =
            data.size() - function.debug->offset_in_seg;
        for (int i = 0; i < count; i++) {
          insert_data<u8>(seg, temp[i]);
        }
      }

      function.debug->length = m_data_by_seg.at(seg).size() - function.debug->offset_in_seg;
    }
  }

  // do static data layout (step 2, part 2)
  for (int seg = N_SEG; seg-- > 0;) {
    auto& data = m_data_by_seg.at(seg);
    for (auto& s : m_static_data_by_seg.at(seg)) {
      // align
      while (data.size() % s.min_align) {
        insert_data<u8>(seg, 0);
      }

      s.location = data.size();

      data.insert(data.end(), s.data.begin(), s.data.end());
    }
  }

  // step 3, cleaning up things now that we know the memory layout
  for (int seg = N_SEG; seg-- > 0;) {
    handle_temp_static_type_links(seg);
    handle_temp_static_sym_links(seg);
    handle_temp_jump_links(seg);
    handle_temp_instr_sym_links(seg);
    handle_temp_rip_func_links(seg);
    handle_temp_rip_data_links(seg);
    handle_temp_static_ptr_links(seg);
  }

  // step 4, generate the link table
  for (int seg = N_SEG; seg-- > 0;) {
    emit_link_table(seg, ts);
  }

  // step 4.5, collect final result of code/object generation for compiler debugging disassembly
  for (int seg = 0; seg < N_SEG; seg++) {
    for (auto& function : m_function_data_by_seg.at(seg)) {
      auto start = m_data_by_seg.at(seg).begin() + function.instruction_to_byte_in_data.at(0);
      auto end = start + function.debug->length;
      function.debug->generated_code = {start, end};
    }
  }

  // step 5, build header and combine sections
  out.header = generate_header_v3();
  out.segment_data = std::move(m_data_by_seg);
  out.link_tables = std::move(m_link_by_seg);
  return out;
}

/*!
 * Add a new function to seg, and return a FunctionRecord which can be used to specify this
 * new function.
 */
FunctionRecord ObjectGenerator::add_function_to_seg(int seg,
                                                    FunctionDebugInfo* debug,
                                                    int min_align) {
  FunctionRecord rec;
  rec.seg = seg;
  rec.func_id = int(m_function_data_by_seg.at(seg).size());
  rec.debug = debug;
  m_function_data_by_seg.at(seg).emplace_back();
  m_function_data_by_seg.at(seg).back().min_align = min_align;
  m_function_data_by_seg.at(seg).back().debug = debug;
  m_all_function_records.push_back(rec);
  return rec;
}

FunctionRecord ObjectGenerator::get_existing_function_record(int f_idx) {
  return m_all_function_records.at(f_idx);
}

/*!
 * Add a new IR instruction to the function. An IR instruction may contain 0, 1, or multiple
 * actual Instructions. These Instructions can be added with add_instruction.  The IR_Record
 * can be used as a label for jump targets.
 */
IR_Record ObjectGenerator::add_ir(const FunctionRecord& func) {
  IR_Record rec;
  rec.seg = func.seg;
  rec.func_id = func.func_id;
  auto& func_data = m_function_data_by_seg.at(rec.seg).at(rec.func_id);
  rec.ir_id = int(func_data.ir_to_instruction.size());
  func_data.ir_to_instruction.push_back(int(func_data.instructions.size()));
  return rec;
}

/*!
 * Get an IR Record that points to an IR that hasn't been added yet. This can be used to create
 * jumps forward to things we haven't seen yet.
 */
IR_Record ObjectGenerator::get_future_ir_record(const FunctionRecord& func, int ir_id) {
  ASSERT(func.func_id == int(m_function_data_by_seg.at(func.seg).size()) - 1);
  IR_Record rec;
  rec.seg = func.seg;
  rec.func_id = func.func_id;
  rec.ir_id = ir_id;
  return rec;
}

IR_Record ObjectGenerator::get_future_ir_record_in_same_func(const IR_Record& irec, int ir_id) {
  IR_Record rec;
  rec.seg = irec.seg;
  rec.func_id = irec.func_id;
  rec.ir_id = ir_id;
  return rec;
}

/*!
 * Add a new Instruction for the given IR instruction.
 */
InstructionRecord ObjectGenerator::add_instr(Instruction inst, IR_Record ir) {
  // only this second condition is an actual error.
  ASSERT(ir.ir_id ==
         int(m_function_data_by_seg.at(ir.seg).at(ir.func_id).ir_to_instruction.size()) - 1);

  InstructionRecord rec;
  rec.seg = ir.seg;
  rec.func_id = ir.func_id;
  rec.ir_id = ir.ir_id;
  auto& func_data = m_function_data_by_seg.at(rec.seg).at(rec.func_id);
  rec.instr_id = int(func_data.instructions.size());
  func_data.instructions.emplace_back(inst);
  auto debug = m_function_data_by_seg.at(ir.seg).at(ir.func_id).debug;
  debug->instructions.emplace_back(inst, InstructionInfo::Kind::IR, ir.ir_id);
  return rec;
}

void ObjectGenerator::add_instr_no_ir(FunctionRecord func,
                                      Instruction inst,
                                      InstructionInfo::Kind kind) {
  auto info = InstructionInfo(inst, kind);
  m_function_data_by_seg.at(func.seg).at(func.func_id).instructions.emplace_back(inst);
  func.debug->instructions.push_back(info);
}

/*!
 * Create a new static object in the given segment.
 */
StaticRecord ObjectGenerator::add_static_to_seg(int seg, int min_align) {
  StaticRecord rec;
  rec.seg = seg;
  rec.static_id = m_static_data_by_seg.at(seg).size();
  m_static_data_by_seg.at(seg).emplace_back();
  m_static_data_by_seg.at(seg).back().min_align = min_align;
  return rec;
}

std::vector<u8>& ObjectGenerator::get_static_data(const StaticRecord& rec) {
  return m_static_data_by_seg.at(rec.seg).at(rec.static_id).data;
}

/*!
 * Add linking data to add a type pointer in rec at offset.
 * This will add an entry to the linking data, which will get patched at runtime, during linking.
 */
void ObjectGenerator::link_static_type_ptr(StaticRecord rec,
                                           int offset,
                                           const std::string& type_name) {
  StaticTypeLink link;
  link.offset = offset;
  link.rec = rec;
  m_static_type_temp_links_by_seg.at(rec.seg)[type_name].push_back(link);
}

/*!
 * This will patch the jump_instr to jump to destination. This happens during compile time and
 * doesn't add anything to the link table.  The jump_instr must already be emitted, however the
 * destination can be a future IR. To get a reference to a future IR, you must know the index and
 * use get_future_ir.
 */
void ObjectGenerator::link_instruction_jump(InstructionRecord jump_instr, IR_Record destination) {
  // must jump within our own function.
  ASSERT(jump_instr.seg == destination.seg);
  ASSERT(jump_instr.func_id == destination.func_id);
  m_jump_temp_links_by_seg.at(jump_instr.seg).push_back({jump_instr, destination});
}

/*!
 * Patch a load/store instruction to refer to a symbol. This patching will happen at runtime
 * linking.  The instruction must use 32-bit immediate displacement addressing, relative to the
 * symbol table.
 */
void ObjectGenerator::link_instruction_symbol_mem(const InstructionRecord& rec,
                                                  const std::string& name) {
  m_symbol_instr_temp_links_by_seg.at(rec.seg)[name].push_back({rec, true});
}

/*!
 * Patch an add instruction to generate a pointer to a symbol. This patching will happen during
 * runtime linking. The instruction should be an "add st, imm32".
 */
void ObjectGenerator::link_instruction_symbol_ptr(const InstructionRecord& rec,
                                                  const std::string& name) {
  m_symbol_instr_temp_links_by_seg.at(rec.seg)[name].push_back({rec, false});
}

/*!
 * Insert a GOAL pointer to a symbol inside of static data. This patching will happen during runtime
 * linking.
 */
void ObjectGenerator::link_static_symbol_ptr(StaticRecord rec,
                                             int offset,
                                             const std::string& name) {
  m_static_sym_temp_links_by_seg.at(rec.seg)[name].push_back({rec, offset});
}

/*!
 * Insert a pointer to other static data. This patching will happen during runtime linking.
 * The source and destination must be in the same segment.
 */
void ObjectGenerator::link_static_pointer_to_data(const StaticRecord& source,
                                                  int source_offset,
                                                  const StaticRecord& dest,
                                                  int dest_offset) {
  StaticDataPointerLink link;
  link.source = source;
  link.dest = dest;
  link.offset_in_source = source_offset;
  link.offset_in_dest = dest_offset;
  ASSERT(link.source.seg == link.dest.seg);
  m_static_data_temp_ptr_links_by_seg.at(source.seg).push_back(link);
}

/*!
 * Insert a pointer to a function in static data.
 * The patching will happen during runtime linking.
 */
void ObjectGenerator::link_static_pointer_to_function(const StaticRecord& source,
                                                      int source_offset,
                                                      const FunctionRecord& target_func) {
  StaticFunctionPointerLink link;
  link.source = source;
  link.offset_in_source = source_offset;
  link.dest = target_func;
  ASSERT(target_func.seg == source.seg);
  m_static_function_temp_ptr_links_by_seg.at(source.seg).push_back(link);
}

void ObjectGenerator::link_instruction_static(const InstructionRecord& instr,
                                              const StaticRecord& target_static,
                                              int offset) {
  m_rip_data_temp_links_by_seg.at(instr.seg).push_back({instr, target_static, offset});
}

void ObjectGenerator::link_instruction_to_function(const InstructionRecord& instr,
                                                   const FunctionRecord& target_func) {
  m_rip_func_temp_links_by_seg.at(instr.seg).push_back({instr, target_func});
}

/*!
 * Convert:
 * m_static_type_temp_links_by_seg -> m_type_ptr_links_by_seg
 * after memory layout is done and before link tables are generated
 */
void ObjectGenerator::handle_temp_static_type_links(int seg) {
  for (const auto& type_links : m_static_type_temp_links_by_seg.at(seg)) {
    const auto& type_name = type_links.first;
    for (const auto& link : type_links.second) {
      ASSERT(seg == link.rec.seg);
      const auto& static_object = m_static_data_by_seg.at(seg).at(link.rec.static_id);
      int total_offset = static_object.location + link.offset;
      m_type_ptr_links_by_seg.at(seg)[type_name].push_back(total_offset);
    }
  }
}

/*!
 * Convert:
 * m_static_sym_temp_links_by_seg -> m_sym_links_by_seg
 * after memory layout is done and before link tables are generated
 */
void ObjectGenerator::handle_temp_static_sym_links(int seg) {
  for (const auto& sym_links : m_static_sym_temp_links_by_seg.at(seg)) {
    const auto& sym_name = sym_links.first;
    for (const auto& link : sym_links.second) {
      ASSERT(seg == link.rec.seg);
      const auto& static_object = m_static_data_by_seg.at(seg).at(link.rec.static_id);
      int total_offset = static_object.location + link.offset;
      m_sym_links_by_seg.at(seg)[sym_name].push_back(total_offset);
    }
  }
}

/*!
 * m_static_temp_ptr_links_by_seg -> m_pointer_links_by_seg
 */
void ObjectGenerator::handle_temp_static_ptr_links(int seg) {
  for (const auto& link : m_static_data_temp_ptr_links_by_seg.at(seg)) {
    const auto& source_object = m_static_data_by_seg.at(seg).at(link.source.static_id);
    const auto& dest_object = m_static_data_by_seg.at(seg).at(link.dest.static_id);
    PointerLink result_link;
    result_link.segment = seg;
    result_link.source = source_object.location + link.offset_in_source;
    result_link.dest = dest_object.location + link.offset_in_dest;
    m_pointer_links_by_seg.at(seg).push_back(result_link);
  }

  for (const auto& link : m_static_function_temp_ptr_links_by_seg.at(seg)) {
    const auto& source_object = m_static_data_by_seg.at(seg).at(link.source.static_id);
    const auto& dest_function = m_function_data_by_seg.at(seg).at(link.dest.func_id);
    ASSERT(link.dest.seg == seg);
    int loc = dest_function.instruction_to_byte_in_data.at(0);
    PointerLink result_link;
    result_link.segment = seg;
    result_link.source = source_object.location + link.offset_in_source;
    result_link.dest = loc;
    m_pointer_links_by_seg.at(seg).push_back(result_link);
  }
}

/*!
 * m_jump_temp_links_by_seg patching after memory layout is done
 */
void ObjectGenerator::handle_temp_jump_links(int seg) {
  for (const auto& link : m_jump_temp_links_by_seg.at(seg)) {
    const auto& function = m_function_data_by_seg.at(seg).at(link.jump_instr.func_id);
    ASSERT(link.jump_instr.func_id == link.dest.func_id);
    ASSERT(link.jump_instr.seg == seg);
    ASSERT(link.dest.seg == seg);

    int instr_byte = function.instruction_to_byte_in_data.at(link.jump_instr.instr_id);
    int dest_byte =
        function.instruction_to_byte_in_data.at(function.ir_to_instruction.at(link.dest.ir_id));

    if (m_instruction_set == InstructionSet::ARM64) {
      // AArch64 branches are PC-relative from the branch itself (not the
      // following instruction) and the immediate is a word count, not a
      // byte count. The opcode tells us which encoding to patch:
      //   B   <label>   — bits 31..26 = 000101; imm26 in bits 0..25.
      //   B.cond <label> — bits 31..24 = 01010100; imm19 in bits 5..23.
      uint32_t enc;
      const auto& data = m_data_by_seg.at(seg);
      ASSERT(instr_byte + 4 <= (int)data.size());
      memcpy(&enc, data.data() + instr_byte, 4);

      int32_t disp_words = (dest_byte - instr_byte) / 4;

      if ((enc & 0xFC000000u) == 0x14000000u) {
        // B #imm26
        enc = (enc & 0xFC000000u) | (static_cast<uint32_t>(disp_words) & 0x03FFFFFFu);
      } else if ((enc & 0xFF000010u) == 0x54000000u) {
        // B.cond #imm19 (keeps low cond nibble, bit 4 must remain 0)
        uint32_t imm19 = static_cast<uint32_t>(disp_words) & 0x7FFFFu;
        enc = (enc & 0xFF00001Fu) | (imm19 << 5);
      } else {
        ASSERT_MSG(false, "ARM64 jump-link patch: unrecognized branch opcode");
      }
      patch_data<uint32_t>(seg, instr_byte, enc);
      continue;
    }

    // x86_64: 32-bit signed displacement embedded in the opcode at
    // offset_of_imm(); the reference RIP is the instruction *after* the
    // branch (hence + 1 in the instruction-to-byte lookup below).
    const auto& jump_instr = function.instructions.at(link.jump_instr.instr_id);
    ASSERT(jump_instr.get_imm_size() == 4);
    int patch_location = instr_byte + jump_instr.offset_of_imm();
    int source_rip = function.instruction_to_byte_in_data.at(link.jump_instr.instr_id + 1);
    patch_data<s32>(seg, patch_location, dest_byte - source_rip);
  }
}

// ============================================================================
// ARM64 link-time fix-up helpers (phase A4-linker-fixups).
//
// AArch64 packs link-resolvable immediates inside the 4-byte instruction word
// at non-byte-aligned bit positions. The ObjectGenerator therefore cannot rely
// on the x86 "patch a contiguous 4-byte slot inside the instruction" approach;
// every arm64 fix-up has to (a) classify the opcode, (b) decode the
// pre-existing immediate field, (c) overwrite ONLY the immediate bits, and
// (d) leave the rest of the instruction encoding untouched. The helpers
// below centralise that bit-twiddling. They are intentionally small leaf
// functions so the call sites stay readable.
//
// References: ARM ARM C6.2.93 (LDR imm12), C6.2.181 (STR imm12),
// C6.2.4 (ADD imm), C6.2.10 (ADRP), C6.2.92 (LDR (literal)).
namespace {

constexpr uint32_t kArm64MaskTopByte = 0xFF000000u;
constexpr uint32_t kArm64MaskOpcode10 = 0xFFC00000u;     // bits 31..22 (size + opc)
constexpr uint32_t kArm64MaskADRP = 0x9F000000u;          // bits 31, 28..24

// arm64 unsigned-offset LDR/STR family bases (imm12 in bits 21..10).
constexpr uint32_t kArm64Op_LDR_Wt_imm = 0xB9400000u;
constexpr uint32_t kArm64Op_LDRSW_Xt_imm = 0xB9800000u;
constexpr uint32_t kArm64Op_STR_Wt_imm = 0xB9000000u;
constexpr uint32_t kArm64Op_LDR_Xt_imm = 0xF9400000u;
constexpr uint32_t kArm64Op_STR_Xt_imm = 0xF9000000u;
constexpr uint32_t kArm64Op_LDR_St_imm = 0xBD400000u;
constexpr uint32_t kArm64Op_LDR_Dt_imm = 0xFD400000u;
constexpr uint32_t kArm64Op_LDR_Qt_imm = 0x3DC00000u;
constexpr uint32_t kArm64Op_STR_Qt_imm = 0x3D800000u;
constexpr uint32_t kArm64Op_ADD_Xd_imm = 0x91000000u;     // ADD (immediate), 64-bit, shift 0
constexpr uint32_t kArm64Op_SUB_Xd_imm = 0xD1000000u;
constexpr uint32_t kArm64Op_ADRP = 0x90000000u;           // ADRP (high-page is bit 31..ADRP family)
constexpr uint32_t kArm64Op_LDR_lit_S = 0x1C000000u;       // LDR (literal, 32-bit SIMD)
constexpr uint32_t kArm64Op_LDR_lit_D = 0x5C000000u;
constexpr uint32_t kArm64Op_LDR_lit_Q = 0x9C000000u;
constexpr uint32_t kArm64Op_LDR_lit_W = 0x18000000u;       // LDR (literal, 32-bit GPR)
constexpr uint32_t kArm64Op_LDR_lit_X = 0x58000000u;       // LDR (literal, 64-bit GPR)

// Returns the access-size scale (1/2/4/8/16) for a LDR/STR imm12 opcode, or 0
// if the opcode is not a recognised LDR/STR. Used by the imm12 patcher to
// scale the byte offset down to the encoding's word count.
int arm64_ldr_str_scale(uint32_t enc) {
  uint32_t top = enc & kArm64MaskOpcode10;
  switch (top) {
    case kArm64Op_LDR_Wt_imm:
    case kArm64Op_LDRSW_Xt_imm:
    case kArm64Op_STR_Wt_imm:
    case kArm64Op_LDR_St_imm:
      return 4;
    case kArm64Op_LDR_Xt_imm:
    case kArm64Op_STR_Xt_imm:
    case kArm64Op_LDR_Dt_imm:
      return 8;
    case kArm64Op_LDR_Qt_imm:
    case kArm64Op_STR_Qt_imm:
      return 16;
  }
  // Byte/half-word loads (LDRB/STRB/LDRH/STRH) share a different opcode prefix
  // and are not currently emitted with link-resolvable offsets by goalc.
  return 0;
}

// Rewrites the imm12 bits of an LDR/STR (unsigned-offset) instruction.
// Returns the new 32-bit encoding. `imm_bytes` is the byte-resolved offset;
// caller is responsible for ensuring imm_bytes is a multiple of the scale.
uint32_t arm64_patch_ldr_str_imm12(uint32_t enc, int32_t imm_bytes) {
  int scale = arm64_ldr_str_scale(enc);
  ASSERT_MSG(scale != 0, "arm64_patch_ldr_str_imm12: unrecognised opcode");
  // unsigned imm12: 0..(4095 * scale)
  ASSERT(imm_bytes >= 0);
  ASSERT(imm_bytes <= 4095 * scale);
  uint32_t imm12 = static_cast<uint32_t>(imm_bytes / scale) & 0xFFFu;
  // Clear bits 21..10 then OR in the new imm12.
  return (enc & ~(0xFFFu << 10)) | (imm12 << 10);
}

// Rewrites the imm12 bits of an ADD/SUB (immediate) instruction. The shift
// bit (bit 22) is forced to 0 — goalc never emits the shift-12 variant for a
// link-resolved ADD, so a non-zero shift would mean a bug somewhere.
uint32_t arm64_patch_add_sub_imm12(uint32_t enc, uint32_t imm12) {
  ASSERT(imm12 <= 0xFFFu);
  // Clear bits 21..10 (imm12) AND bit 22 (shift). Then write imm12<<10.
  return (enc & ~((0xFFFu << 10) | (1u << 22))) | (imm12 << 10);
}

// Rewrites the imm21 bits of an ADRP instruction. The 21-bit signed page
// delta is split across immlo[1:0] = bits 30:29 and immhi[18:0] = bits 23:5.
//   ADRP: 1 immlo 10000 immhi Rd → 0x90000000 base
uint32_t arm64_patch_adrp_imm21(uint32_t enc, int32_t page_delta) {
  // Sign-extend / range-check to 21 signed bits: -(2^20) .. (2^20 - 1).
  ASSERT(page_delta >= -(1 << 20));
  ASSERT(page_delta < (1 << 20));
  uint32_t bits21 = static_cast<uint32_t>(page_delta) & 0x1FFFFFu;
  uint32_t immlo = bits21 & 0x3u;          // bits 1..0 of page delta
  uint32_t immhi = (bits21 >> 2) & 0x7FFFFu;  // bits 20..2 of page delta
  // Clear bits 30..29 (immlo) and bits 23..5 (immhi) then write new values.
  uint32_t cleared = enc & ~((0x3u << 29) | (0x7FFFFu << 5));
  return cleared | (immlo << 29) | (immhi << 5);
}

// Rewrites the imm19 bits of an LDR (literal) instruction. imm19 is signed
// and scaled by 4 — the encoded value is the PC-relative byte offset / 4.
//   imm19 sits in bits 23..5.
uint32_t arm64_patch_ldr_literal_imm19(uint32_t enc, int32_t pc_rel_bytes) {
  ASSERT_MSG((pc_rel_bytes & 3) == 0, "arm64 LDR literal: byte offset must be 4-aligned");
  int32_t imm19_signed = pc_rel_bytes / 4;
  ASSERT(imm19_signed >= -(1 << 18));
  ASSERT(imm19_signed < (1 << 18));
  uint32_t imm19 = static_cast<uint32_t>(imm19_signed) & 0x7FFFFu;
  return (enc & ~(0x7FFFFu << 5)) | (imm19 << 5);
}

// Page-aligned address (drops the low 12 bits). Used for ADRP.
inline int32_t arm64_page_of(int32_t byte_offset) {
  return byte_offset & ~0xFFF;
}

}  // namespace

/*!
 * Convert:
 * m_symbol_instr_temp_links_by_seg -> m_sym_links_by_seg
 * after memory layout is done and before link tables are generated
 *
 * x86: a single disp32/imm32 slot inside the patched instruction holds the
 * symbol's value at link time, so the recorded offset points into the middle
 * of the instruction (offset_of_disp / offset_of_imm). The runtime linker
 * writes 32 bits there directly.
 *
 * arm64: the symbol value (or symbol address, in the case of an ADRP+ADD pair)
 * lives in imm12 / imm21 fields embedded in the 32-bit instruction word at
 * various non-byte-aligned positions:
 *   - LDR/STR (Wt, [Xn,#imm]):  imm12 << 10  (scaled by access size)
 *   - LDRSW    (Xt, [Xn,#imm]):  imm12 << 10  (scaled by 4)
 *   - ADD imm12 (Xd, Xn, #imm):  imm12 << 10
 *   - ADRP imm21:                imm_hi19 << 5 | imm_lo2 << 29
 * The arm64-aware runtime linker therefore reads the whole instruction word,
 * decodes the opcode, and rewrites only the immediate bits. To support that
 * we record the *instruction start* (not a sub-byte imm offset) and skip the
 * x86-specific disp/imm size asserts. ObjectGenerator also rewrites the
 * placeholder imm bits in-place at link time so the emitted instructions are
 * well-formed and never carry the unstable 0x0afecafe / 0x0badbeef encoder
 * placeholder out to the link table (which the diff-harness disasm spot-check
 * — and any later arm64 kernel-side patcher — relies on).
 */
void ObjectGenerator::handle_temp_instr_sym_links(int seg) {
  for (const auto& links : m_symbol_instr_temp_links_by_seg.at(seg)) {
    const auto& sym_name = links.first;
    for (const auto& link : links.second) {
      ASSERT(seg == link.rec.seg);
      const auto& function = m_function_data_by_seg.at(seg).at(link.rec.func_id);
      const auto& instruction = function.instructions.at(link.rec.instr_id);
      int offset_of_instruction = function.instruction_to_byte_in_data.at(link.rec.instr_id);
      int offset_in_instruction;
      if (m_instruction_set == InstructionSet::ARM64) {
        // arm64 imm12 / imm21 lives inside the 32-bit instruction word at
        // non-byte-aligned bit positions — record the instruction start and
        // let the runtime linker decode the encoding from the word itself.
        offset_in_instruction = 0;
        // Zero out the placeholder imm bits the encoder emitted (0x0badbeef
        // truncated etc.) so the instruction word is well-formed and the
        // disasm spot-check in the diff harness sees a clean opcode + zeroed
        // imm field. The full symbol-table slot offset is the runtime
        // linker's responsibility — recorded in m_sym_links_by_seg below.
        auto& data = m_data_by_seg.at(seg);
        ASSERT(offset_of_instruction + 4 <= (int)data.size());
        uint32_t enc;
        memcpy(&enc, data.data() + offset_of_instruction, 4);
        if (arm64_ldr_str_scale(enc) != 0) {
          // LDR/STR/LDRSW with imm12 — clear bits 21..10.
          enc = arm64_patch_ldr_str_imm12(enc, 0);
        } else if ((enc & kArm64MaskOpcode10) == kArm64Op_ADD_Xd_imm ||
                   (enc & kArm64MaskOpcode10) == kArm64Op_SUB_Xd_imm) {
          enc = arm64_patch_add_sub_imm12(enc, 0);
        } else if ((enc & kArm64MaskADRP) == kArm64Op_ADRP) {
          enc = arm64_patch_adrp_imm21(enc, 0);
        }
        // Other arm64 opcodes flow through unchanged (e.g. the link records
        // an instruction that doesn't carry an arm64 imm field — currently
        // only the LDR/STR/ADD/ADRP forms above are link-resolvable on arm64).
        patch_data<uint32_t>(seg, offset_of_instruction, enc);
      } else if (link.is_mem_access) {
        ASSERT(instruction.get_disp_size() == 4);
        offset_in_instruction = instruction.offset_of_disp();
      } else {
        ASSERT(instruction.get_imm_size() == 4);
        offset_in_instruction = instruction.offset_of_imm();
      }
      m_sym_links_by_seg.at(seg)[sym_name].push_back(offset_of_instruction + offset_in_instruction);
    }
  }
}

// Helper: applies the ADRP+ADD (or ADRP+LDR-literal) arm64 immediate
// fix-up for a same-segment intra-object cross-reference. byte_of_instr is
// where the patched instruction lives in the segment; target_byte is the
// segment-relative offset of the referenced datum (static or function start).
//
// For ADRP we encode the signed 21-bit page delta; for ADD imm12 we encode
// the low-12 byte offset within the target page; for LDR (literal) imm19 we
// encode the signed 19-bit PC-relative word offset.
//
// The intra-object delta is fully determined at link time (we know both
// byte offsets within the segment), so this is a true compile-time fix-up:
// no runtime patching needed.
void ObjectGenerator::apply_arm64_intra_seg_imm_patch(int seg,
                                                      int byte_of_instr,
                                                      int target_byte) {
  auto& data = m_data_by_seg.at(seg);
  ASSERT(byte_of_instr + 4 <= (int)data.size());
  uint32_t enc;
  memcpy(&enc, data.data() + byte_of_instr, 4);

  if ((enc & kArm64MaskADRP) == kArm64Op_ADRP) {
    // ADRP encodes the page delta. ARM's ADRP rounds the PC of the ADRP
    // instruction down to a page (4 KB) boundary, so the delta is between
    // the two pages — not byte counts.
    int32_t page_delta = (arm64_page_of(target_byte) - arm64_page_of(byte_of_instr)) >> 12;
    enc = arm64_patch_adrp_imm21(enc, page_delta);
  } else if (arm64_ldr_str_scale(enc) != 0) {
    // LDR/STR imm12 — the byte offset is the low 12 bits of the target
    // address (the page is reached via the preceding ADRP). With an
    // intra-object reference the imm12 is just (target_byte mod 4096),
    // assuming the segment is page-aligned at load time. We always patch
    // page-relative bytes (target_byte & 0xFFF) so the encoding is stable.
    int32_t page_off = target_byte & 0xFFF;
    enc = arm64_patch_ldr_str_imm12(enc, page_off);
  } else if ((enc & kArm64MaskOpcode10) == kArm64Op_ADD_Xd_imm ||
             (enc & kArm64MaskOpcode10) == kArm64Op_SUB_Xd_imm) {
    // ADD/SUB imm12 — same as LDR imm12, page-low-12 of target.
    int32_t page_off = target_byte & 0xFFF;
    enc = arm64_patch_add_sub_imm12(enc, page_off & 0xFFF);
  } else if ((enc & 0xFF000000u) == kArm64Op_LDR_lit_S ||
             (enc & 0xFF000000u) == kArm64Op_LDR_lit_D ||
             (enc & 0xFF000000u) == kArm64Op_LDR_lit_Q ||
             (enc & 0xFF000000u) == kArm64Op_LDR_lit_W ||
             (enc & 0xFF000000u) == kArm64Op_LDR_lit_X) {
    // LDR (literal) imm19 — PC-relative word offset (signed).
    int32_t pc_rel = target_byte - byte_of_instr;
    enc = arm64_patch_ldr_literal_imm19(enc, pc_rel);
  }
  // Anything else falls through unchanged. The intent is forward-compat:
  // future encoders that produce a new link-patchable shape will need a
  // matching arm cluster here.
  patch_data<uint32_t>(seg, byte_of_instr, enc);
}

void ObjectGenerator::handle_temp_rip_func_links(int seg) {
  for (const auto& link : m_rip_func_temp_links_by_seg.at(seg)) {
    RipLink result;
    result.instr = link.instr;
    result.target_segment = link.target.seg;
    const auto& target_func = m_function_data_by_seg.at(link.target.seg).at(link.target.func_id);
    result.offset_in_segment = target_func.instruction_to_byte_in_data.at(0);
    m_rip_links_by_seg.at(seg).push_back(result);

    if (m_instruction_set == InstructionSet::ARM64 && link.target.seg == seg) {
      // Intra-segment function-address reference: ADRP / ADD imm12 / LDR
      // literal pair points at the target function. Patch the imm fields
      // at link time so the emitted bytes are correct without any runtime
      // linker pass.
      const auto& src_func = m_function_data_by_seg.at(seg).at(link.instr.func_id);
      int byte_of_instr = src_func.instruction_to_byte_in_data.at(link.instr.instr_id);
      apply_arm64_intra_seg_imm_patch(seg, byte_of_instr, result.offset_in_segment);
    }
  }
}

void ObjectGenerator::handle_temp_rip_data_links(int seg) {
  for (const auto& link : m_rip_data_temp_links_by_seg.at(seg)) {
    RipLink result;
    result.instr = link.instr;
    result.target_segment = link.data.seg;
    const auto& target = m_static_data_by_seg.at(link.data.seg).at(link.data.static_id);
    result.offset_in_segment = target.location + link.offset;
    m_rip_links_by_seg.at(seg).push_back(result);

    if (m_instruction_set == InstructionSet::ARM64 && link.data.seg == seg) {
      // Intra-segment static-data reference: ADRP / LDR-literal / ADD imm12.
      // Same compile-time fix-up as functions.
      const auto& src_func = m_function_data_by_seg.at(seg).at(link.instr.func_id);
      int byte_of_instr = src_func.instruction_to_byte_in_data.at(link.instr.instr_id);
      apply_arm64_intra_seg_imm_patch(seg, byte_of_instr, result.offset_in_segment);
    }
  }
}

namespace {
template <typename T>
uint32_t push_data(const T& data, std::vector<u8>& v) {
  auto insert = v.size();
  v.resize(insert + sizeof(T));
  memcpy(v.data() + insert, &data, sizeof(T));
  return sizeof(T);
}
}  // namespace

void ObjectGenerator::emit_link_type_pointer(int seg, const TypeSystem* ts) {
  auto& out = m_link_by_seg.at(seg);
  for (auto& rec : m_type_ptr_links_by_seg.at(seg)) {
    u32 size = rec.second.size();
    if (!size) {
      continue;
    }

    // start
    out.push_back(LINK_TYPE_PTR);

    // name
    for (char c : rec.first) {
      out.push_back(c);
    }
    out.push_back(0);

    // method count
    switch (m_version) {
      case GameVersion::Jak1:
        out.push_back(ts->get_type_method_count(rec.first));
        break;
      case GameVersion::Jak2:
      case GameVersion::Jak3:  // jak3 opengoal uses same format as jak2 for code.
      case GameVersion::JakX:  // TODO JAK X - hopefully this is the same
        // the linker/intern_type functions do the +3.
        out.push_back(ts->get_type_method_count(rec.first) / 4);
        break;
      default:
        ASSERT(false);
    }

    // number of links
    push_data<u32>(size, out);

    for (auto& r : rec.second) {
      push_data<s32>(r, out);
    }
  }
}

void ObjectGenerator::emit_link_symbol(int seg) {
  auto& out = m_link_by_seg.at(seg);
  for (auto& rec : m_sym_links_by_seg.at(seg)) {
    out.push_back(LINK_SYMBOL_OFFSET);
    for (char c : rec.first) {
      out.push_back(c);
    }
    out.push_back(0);

    // number of links
    push_data<u32>(rec.second.size(), out);

    for (auto& r : rec.second) {
      push_data<s32>(r, out);
    }
  }
}

void ObjectGenerator::emit_link_ptr(int seg) {
  auto& out = m_link_by_seg.at(seg);
  for (auto& rec : m_pointer_links_by_seg.at(seg)) {
    out.push_back(LINK_PTR);
    ASSERT(rec.dest >= 0);
    ASSERT(rec.source >= 0);
    push_data<u32>(rec.source, out);
    push_data<u32>(rec.dest, out);
  }
}

void ObjectGenerator::emit_link_rip(int seg) {
  auto& out = m_link_by_seg.at(seg);
  for (auto& rec : m_rip_links_by_seg.at(seg)) {
    // kind (u8)
    // target segment (u8)
    // offset in current (u32) — the reference PC, computed by the runtime
    //   linker as (mine_offset + this_segment_base). x86 RIP-relative
    //   addressing measures from the byte *after* the patched instruction, so
    //   x86 stores instruction_to_byte[instr_id + 1]. arm64 PC-relative
    //   addressing (ADRP / LDR-literal / B / B.cond) measures from the byte
    //   *of* the patched instruction itself, so arm64 stores
    //   instruction_to_byte[instr_id].
    // offset into target (u32)
    // patch loc (u32) — where the runtime linker rewrites bits. x86 patches a
    //   32-bit displacement field inside the instruction (offset_of_disp).
    //   arm64 imm21 / imm12 / imm19 fields live at non-byte-aligned positions
    //   inside the 32-bit instruction word, so patch_loc records the
    //   instruction start and the runtime linker decodes the encoding and
    //   rewrites only the immediate bits (ADRP, ADD imm12, LDR-literal imm19).

    // kind
    out.push_back(LINK_DISTANCE_TO_OTHER_SEG_32);
    // target segment
    out.push_back(rec.target_segment);
    // offset into current + patch location
    const auto& src_func = m_function_data_by_seg.at(rec.instr.seg).at(rec.instr.func_id);
    u32 source_rip_offset;
    u32 patch_loc_offset;
    if (m_instruction_set == InstructionSet::ARM64) {
      source_rip_offset = src_func.instruction_to_byte_in_data.at(rec.instr.instr_id);
      patch_loc_offset = src_func.instruction_to_byte_in_data.at(rec.instr.instr_id);
    } else {
      source_rip_offset = src_func.instruction_to_byte_in_data.at(rec.instr.instr_id + 1);
      const auto& src_instr = src_func.instructions.at(rec.instr.instr_id);
      ASSERT(src_instr.get_disp_size() == 4);
      patch_loc_offset = src_func.instruction_to_byte_in_data.at(rec.instr.instr_id) +
                         src_instr.offset_of_disp();
    }
    push_data<u32>(source_rip_offset, out);
    // offset into target
    ASSERT(rec.offset_in_segment >= 0);
    push_data<u32>(rec.offset_in_segment, out);
    // patch location
    push_data<u32>(patch_loc_offset, out);
  }
}

void ObjectGenerator::emit_link_table(int seg, const TypeSystem* ts) {
  emit_link_symbol(seg);
  emit_link_type_pointer(seg, ts);
  emit_link_rip(seg);
  emit_link_ptr(seg);
  m_link_by_seg.at(seg).push_back(LINK_TABLE_END);
}

/*!
 * Generate linker header.
 */
std::vector<u8> ObjectGenerator::generate_header_v3() {
  std::vector<u8> result;

  // header starts with a "GOAL" magic word
  result.push_back('G');
  result.push_back('O');
  result.push_back('A');
  result.push_back('L');

  u32 offset = 0;  // the GOAL doesn't count toward the offset, first 4 bytes are killed.
  // then, the version.  todo, bump the version once we use this!
  offset += push_data<u16>(versions::GOAL_VERSION_MAJOR, result);
  offset += push_data<u16>(versions::GOAL_VERSION_MINOR, result);

  // the object file version
  offset += push_data<u32>(3, result);
  // the segment count
  offset += push_data<u32>(N_SEG, result);

  offset += sizeof(u32) * N_SEG * 4;  // 4 u32's per segment
  offset += 4;
  struct SizeOffset {
    uint32_t offset, size;
  };

  struct SizeOffsetTable {
    SizeOffset link_seg[N_SEG];
    SizeOffset code_seg[N_SEG];
  };

  SizeOffsetTable table;
  int total_link_size = 0;

  for (int i = N_SEG; i-- > 0;) {
    table.link_seg[i].offset = offset;                 // start of the link
    table.link_seg[i].size = m_link_by_seg[i].size();  // size of the link data
    offset += m_link_by_seg[i].size();                 // to next link data
    total_link_size += m_link_by_seg[i].size();        // need to track this.
  }

  offset = 0;
  for (int i = N_SEG; i-- > 0;) {
    table.code_seg[i].offset = offset;
    table.code_seg[i].size = m_data_by_seg[i].size();
    offset += m_data_by_seg[i].size();
  }

  push_data<SizeOffsetTable>(table, result);
  push_data<uint32_t>(64 + 4 + total_link_size, result);  // todo, make these numbers less magic.
  return result;
}

ObjectGeneratorStats ObjectGenerator::get_stats() const {
  return m_stats;
}

void ObjectGenerator::count_eliminated_move() {
  m_stats.moves_eliminated++;
}
}  // namespace emitter
