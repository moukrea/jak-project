#include "disassemble.h"

#include <cctype>

#include "common/goos/Reader.h"

#include "Zydis/Decoder.h"
#include "Zydis/Formatter.h"

#ifndef _WIN32
#include "capstone/capstone.h"
#endif
#include "fmt/color.h"
#include "fmt/format.h"

std::string disassemble_x86(u8* data, int len, u64 base_addr) {
  std::string result;
  ZydisDecoder decoder;
  ZydisDecoderInit(&decoder, ZYDIS_MACHINE_MODE_LONG_64, ZYDIS_STACK_WIDTH_64);
  ZydisFormatter formatter;
  ZydisFormatterInit(&formatter, ZYDIS_FORMATTER_STYLE_INTEL);
  ZydisDecodedInstruction instr;
  ZydisDecodedOperand op[ZYDIS_MAX_OPERAND_COUNT];

  constexpr int print_buff_size = 512;
  char print_buff[print_buff_size];
  int offset = 0;
  while (ZYAN_SUCCESS(ZydisDecoderDecodeFull(&decoder, data + offset, len - offset, &instr, op))) {
    result += fmt::format("[0x{:x}] ", base_addr);
    ZydisFormatterFormatInstruction(&formatter, &instr, op, instr.operand_count_visible, print_buff,
                                    print_buff_size, base_addr, ZYAN_NULL);
    result += print_buff;
    result += "\n";

    offset += instr.length;
    base_addr += instr.length;
  }

  return result;
}

std::string disassemble_x86(u8* data, int len, u64 base_addr, u64 highlight_addr) {
  std::string result;
  ZydisDecoder decoder;
  ZydisDecoderInit(&decoder, ZYDIS_MACHINE_MODE_LONG_64, ZYDIS_STACK_WIDTH_64);
  ZydisFormatter formatter;
  ZydisFormatterInit(&formatter, ZYDIS_FORMATTER_STYLE_INTEL);
  ZydisDecodedInstruction instr;
  ZydisDecodedOperand op[ZYDIS_MAX_OPERAND_COUNT];

  constexpr int print_buff_size = 512;
  char print_buff[print_buff_size];
  int offset = 0;

  ASSERT(highlight_addr >= base_addr);
  int mark_offset = int(highlight_addr - base_addr);
  while (offset < len) {
    char prefix = (offset == mark_offset) ? '-' : ' ';
    if (ZYAN_SUCCESS(ZydisDecoderDecodeFull(&decoder, data + offset, len - offset, &instr, op))) {
      result += fmt::format("{:c} [0x{:x}] ", prefix, base_addr);
      ZydisFormatterFormatInstruction(&formatter, &instr, op, instr.operand_count_visible,
                                      print_buff, print_buff_size, base_addr, ZYAN_NULL);
      result += print_buff;
      result += "\n";
      offset += instr.length;
      base_addr += instr.length;
    } else {
      result += fmt::format("{:c} [0x{:x}] INVALID (0x{:02x})\n", prefix, base_addr, data[offset]);
      offset++;
    }
  }

  return result;
}

// how many "forms" to look at ahead of / behind rip when stopping
static constexpr int FORM_DUMP_SIZE_REV = 4;
static constexpr int FORM_DUMP_SIZE_FWD = 4;
// how long the bytecode part of the disassembly is, IR comes after this
static constexpr int DISASM_LINE_LEN = 60;

std::string disassemble_x86_function(
    u8* data,
    int len,
    const goos::Reader* reader,
    u64 base_addr,
    u64 highlight_addr,
    const std::vector<InstructionInfo>& x86_instructions,
    const std::vector<std::shared_ptr<goos::HeapObject>>& code_sources,
    const std::vector<std::string>& ir_strings,
    bool* had_failure,
    bool print_whole_function,
    bool omit_ir) {
  std::string result;
  ZydisDecoder decoder;
  ZydisDecoderInit(&decoder, ZYDIS_MACHINE_MODE_LONG_64, ZYDIS_STACK_WIDTH_64);
  ZydisFormatter formatter;
  ZydisFormatterInit(&formatter, ZYDIS_FORMATTER_STYLE_INTEL);
  ZydisDecodedInstruction instr;
  ZydisDecodedOperand op[ZYDIS_MAX_OPERAND_COUNT];

  constexpr int print_buff_size = 512;
  char print_buff[print_buff_size];
  int offset = 0;

  int current_instruction_idx = -1;
  int current_ir_idx = -1;
  int current_src_idx = -1;
  int rip_src_idx = -1;

  std::string current_filename;
  int current_file_line = -1;
  int current_offset_in_line = -1;

  std::vector<std::pair<int, std::string>> lines;

  ASSERT(highlight_addr >= base_addr);
  int mark_offset = int(highlight_addr - base_addr);
  while (offset < len) {
    char prefix = (offset == mark_offset) ? '-' : ' ';
    if (ZYAN_SUCCESS(ZydisDecoderDecodeFull(&decoder, data + offset, len - offset, &instr, op))) {
      bool warn_messed_up = false;
      bool print_ir = false;
      // we should have a next instruction.
      if (current_instruction_idx + 1 >= int(x86_instructions.size())) {
        warn_messed_up = true;
        if (had_failure) {
          *had_failure = true;
        }
      } else {
        // we should line up with the next instruction
        if (x86_instructions.at(current_instruction_idx + 1).offset == offset) {
          // perfect, everything is lined up!
          current_instruction_idx++;
          while (current_instruction_idx + 1 < int(x86_instructions.size()) &&
                 x86_instructions.at(current_instruction_idx + 1).offset == offset) {
            current_instruction_idx++;
          }
        } else {
          printf("offset mess up, at %d, expected %d\n", offset,
                 x86_instructions.at(current_instruction_idx + 1).offset);
          warn_messed_up = true;
          if (had_failure) {
            *had_failure = true;
          }
        }
      }

      if (!omit_ir && current_instruction_idx >= 0 &&
          current_instruction_idx < int(x86_instructions.size())) {
        const auto& debug_instr = x86_instructions.at(current_instruction_idx);
        if (debug_instr.kind == InstructionInfo::Kind::IR && debug_instr.ir_idx != current_ir_idx) {
          current_ir_idx = debug_instr.ir_idx;
          print_ir = true;
        }
      }

      std::string line;
      size_t line_size_offset = 0;

      if (!omit_ir && current_ir_idx >= 0 && current_ir_idx < int(ir_strings.size())) {
        auto source = reader->db.try_get_short_info(code_sources.at(current_ir_idx));
        if (source) {
          if (source->filename != current_filename ||
              source->line_idx_to_display != current_file_line ||
              source->pos_in_line != current_offset_in_line) {
            current_filename = source->filename;
            current_file_line = source->line_idx_to_display;
            current_offset_in_line = source->pos_in_line;
            ++current_src_idx;
            line +=
                fmt::format(fmt::emphasis::bold, "\n{}:{}\n", current_filename, current_file_line);
            line += fmt::format(fg(fmt::color::orange), "-> {}\n", source->line_text);
            std::string pointer(current_offset_in_line + 3, ' ');
            pointer += "^\n";
            line += fmt::format(fmt::emphasis::bold | fg(fmt::color::lime_green), "{}", pointer);
            line_size_offset = line.size();
          }
        }
      }

      if (prefix != ' ') {
        line += fmt::format(fmt::emphasis::bold | fg(fmt::color::red), "{:c} [0x{:X}] ", prefix,
                            base_addr);
        rip_src_idx = current_src_idx;
      } else {
        line += fmt::format("{:c} [0x{:X}] ", prefix, base_addr);
      }

      ZydisFormatterFormatInstruction(&formatter, &instr, op, instr.operand_count_visible,
                                      print_buff, print_buff_size, base_addr, ZYAN_NULL);
      line += print_buff;

      if (print_ir && current_ir_idx >= 0 && current_ir_idx < int(ir_strings.size())) {
        if (line.size() - line_size_offset < DISASM_LINE_LEN) {
          line.append(DISASM_LINE_LEN - (line.size() - line_size_offset), ' ');
        }
        line += " ";
        line += ir_strings.at(current_ir_idx);
      }

      if (warn_messed_up) {
        line += " ;; function's instruction do not align with debug data, something is wrong.";
      }
      line += "\n";
      lines.push_back(std::make_pair(current_src_idx, line));
      offset += instr.length;
      base_addr += instr.length;
    } else {
      lines.push_back(std::make_pair(
          current_src_idx,
          fmt::format("{:c} [0x{:x}] INVALID (0x{:02x})\n", prefix, base_addr, data[offset])));
      offset++;
    }
  }

  for (auto& line : lines) {
    if (print_whole_function || (line.first >= rip_src_idx - FORM_DUMP_SIZE_REV &&
                                 line.first < rip_src_idx + FORM_DUMP_SIZE_FWD)) {
      result.append(line.second);
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// ARM64 disassembly + structured decode (Capstone) for goalc-codegen-diff.
// ---------------------------------------------------------------------------

static std::string normalize_arm64_reg(const char* name) {
  if (!name) {
    return "";
  }
  std::string n = name;
  // Map the 32-bit W view onto the 64-bit X view (same physical register).
  if (n.size() >= 2 && n[0] == 'w' && std::isdigit((unsigned char)n[1])) {
    return "x" + n.substr(1);
  }
  if (n == "wsp") {
    return "sp";
  }
  return n;
}

std::vector<DecodedInstr> decode_arm64(u8* data, int len, u64 base_addr) {
  std::vector<DecodedInstr> out;
#ifdef _WIN32
  // capstone is not built on Windows (its C objects duplicate MSVC intrinsic
  // shims under lld-link); the arm64 codegen-diff tool is a linux-side tool.
  (void)data;
  (void)len;
  (void)base_addr;
  return out;
#else
  csh handle;
  if (cs_open(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, &handle) != CS_ERR_OK) {
    return out;
  }
  cs_option(handle, CS_OPT_DETAIL, CS_OPT_ON);
  cs_insn* insn = cs_malloc(handle);

  const uint8_t* code = data;
  size_t size = (size_t)len;
  uint64_t addr = base_addr;

  while (size >= 4) {
    DecodedInstr di;
    di.offset = (int)(addr - base_addr);
    di.addr = addr;
    const uint8_t* code_before = code;
    uint64_t addr_before = addr;

    if (cs_disasm_iter(handle, &code, &size, &addr, insn)) {
      di.length = (int)insn->size;
      di.text = std::string(insn->mnemonic);
      if (insn->op_str[0]) {
        di.text += " ";
        di.text += insn->op_str;
      }

      cs_regs regs_read, regs_write;
      uint8_t read_count = 0, write_count = 0;
      if (cs_regs_access(handle, insn, regs_read, &read_count, regs_write, &write_count) ==
          CS_ERR_OK) {
        for (uint8_t i = 0; i < write_count; i++) {
          std::string n = normalize_arm64_reg(cs_reg_name(handle, regs_write[i]));
          if (!n.empty() && n != "xzr" && n != "nzcv") {
            di.regs_written.push_back(n);
          }
        }
      }

      const cs_arm64* a = &insn->detail->arm64;
      bool has_mem_sp = false;
      std::vector<std::string> reg_ops;
      for (int i = 0; i < a->op_count; i++) {
        const cs_arm64_op& o = a->operands[i];
        if (o.type == ARM64_OP_REG) {
          std::string nn = normalize_arm64_reg(cs_reg_name(handle, o.reg));
          if (nn == "sp") {
            di.touches_sp = true;
          }
          reg_ops.push_back(nn);
        } else if (o.type == ARM64_OP_MEM) {
          if (o.mem.base == ARM64_REG_SP || o.mem.index == ARM64_REG_SP) {
            has_mem_sp = true;
            di.touches_sp = true;
          }
        }
      }

      std::string mn = insn->mnemonic;
      if (has_mem_sp) {
        if (mn.rfind("st", 0) == 0) {
          di.is_store_to_stack = true;
          di.stack_xfer_regs = reg_ops;
        } else if (mn.rfind("ld", 0) == 0) {
          di.is_load_from_stack = true;
          di.stack_xfer_regs = reg_ops;
        }
      }

      // sp += imm  (add/sub sp, sp, #imm) — used to balance-check spill wrappers.
      if ((mn == "add" || mn == "sub") && a->op_count >= 3 &&
          a->operands[0].type == ARM64_OP_REG &&
          normalize_arm64_reg(cs_reg_name(handle, a->operands[0].reg)) == "sp" &&
          a->operands[2].type == ARM64_OP_IMM) {
        int imm = (int)a->operands[2].imm;
        di.sp_delta = (mn == "sub") ? -imm : imm;
      }
    } else {
      // Undecodable word — e.g. an A5 sym-mem reloc sentinel patched in later.
      uint32_t word = (uint32_t)code_before[0] | ((uint32_t)code_before[1] << 8) |
                      ((uint32_t)code_before[2] << 16) | ((uint32_t)code_before[3] << 24);
      di.valid = false;
      di.length = 4;
      di.text = fmt::format(".word 0x{:08x}", word);
      code = code_before + 4;
      size -= 4;
      addr = addr_before + 4;
    }
    out.push_back(std::move(di));
  }

  cs_free(insn, 1);
  cs_close(&handle);
  return out;
#endif
}

std::string disassemble_arm64(u8* data, int len, u64 base_addr) {
  std::string result;
  for (const auto& di : decode_arm64(data, len, base_addr)) {
    result += fmt::format("[0x{:x}] {}\n", di.addr, di.text);
  }
  return result;
}

std::string disassemble_arm64_function(
    u8* data,
    int len,
    const goos::Reader* reader,
    u64 base_addr,
    const std::vector<InstructionInfo>& instructions,
    const std::vector<std::shared_ptr<goos::HeapObject>>& code_sources,
    const std::vector<std::string>& ir_strings,
    bool* had_failure,
    bool omit_ir) {
  std::string result;
  int current_instruction_idx = -1;
  int current_ir_idx = -1;

  std::string current_filename;
  int current_file_line = -1;
  int current_offset_in_line = -1;

  for (const auto& di : decode_arm64(data, len, base_addr)) {
    bool warn_messed_up = false;
    bool print_ir = false;
    if (current_instruction_idx + 1 >= int(instructions.size())) {
      warn_messed_up = true;
      if (had_failure) {
        *had_failure = true;
      }
    } else if (instructions.at(current_instruction_idx + 1).offset == di.offset) {
      current_instruction_idx++;
      while (current_instruction_idx + 1 < int(instructions.size()) &&
             instructions.at(current_instruction_idx + 1).offset == di.offset) {
        current_instruction_idx++;
      }
    } else {
      warn_messed_up = true;
      if (had_failure) {
        *had_failure = true;
      }
    }

    if (!omit_ir && current_instruction_idx >= 0 &&
        current_instruction_idx < int(instructions.size())) {
      const auto& debug_instr = instructions.at(current_instruction_idx);
      if (debug_instr.kind == InstructionInfo::Kind::IR && debug_instr.ir_idx != current_ir_idx) {
        current_ir_idx = debug_instr.ir_idx;
        print_ir = true;
      }
    }

    std::string line;
    size_t line_size_offset = 0;
    if (!omit_ir && current_ir_idx >= 0 && current_ir_idx < int(ir_strings.size())) {
      auto source = reader->db.try_get_short_info(code_sources.at(current_ir_idx));
      if (source && (source->filename != current_filename ||
                     source->line_idx_to_display != current_file_line ||
                     source->pos_in_line != current_offset_in_line)) {
        current_filename = source->filename;
        current_file_line = source->line_idx_to_display;
        current_offset_in_line = source->pos_in_line;
        line += fmt::format("\n{}:{}\n-> {}\n", current_filename, current_file_line,
                            source->line_text);
        line_size_offset = line.size();
      }
    }

    line += fmt::format("  [0x{:X}] {}", di.addr, di.text);
    if (print_ir && current_ir_idx >= 0 && current_ir_idx < int(ir_strings.size())) {
      if (line.size() - line_size_offset < DISASM_LINE_LEN) {
        line.append(DISASM_LINE_LEN - (line.size() - line_size_offset), ' ');
      }
      line += " ";
      line += ir_strings.at(current_ir_idx);
    }
    if (warn_messed_up) {
      line += " ;; misaligned with debug data";
    }
    line += "\n";
    result += line;
  }
  return result;
}

std::vector<DecodedInstr> decode_x86(u8* data, int len, u64 base_addr) {
  std::vector<DecodedInstr> out;
  ZydisDecoder decoder;
  ZydisDecoderInit(&decoder, ZYDIS_MACHINE_MODE_LONG_64, ZYDIS_STACK_WIDTH_64);
  ZydisFormatter formatter;
  ZydisFormatterInit(&formatter, ZYDIS_FORMATTER_STYLE_INTEL);
  ZydisDecodedInstruction instr;
  ZydisDecodedOperand op[ZYDIS_MAX_OPERAND_COUNT];
  char buff[512];

  int offset = 0;
  while (offset < len) {
    DecodedInstr di;
    di.addr = base_addr + offset;
    di.offset = offset;
    if (ZYAN_SUCCESS(
            ZydisDecoderDecodeFull(&decoder, data + offset, len - offset, &instr, op))) {
      ZydisFormatterFormatInstruction(&formatter, &instr, op, instr.operand_count_visible, buff,
                                      sizeof(buff), di.addr, ZYAN_NULL);
      di.text = buff;
      di.length = instr.length;
      for (int i = 0; i < instr.operand_count; i++) {
        const auto& o = op[i];
        if (o.type == ZYDIS_OPERAND_TYPE_REGISTER) {
          if (o.reg.value == ZYDIS_REGISTER_RSP || o.reg.value == ZYDIS_REGISTER_ESP) {
            di.touches_sp = true;
          }
          if (o.actions & (ZYDIS_OPERAND_ACTION_WRITE | ZYDIS_OPERAND_ACTION_CONDWRITE)) {
            const char* n = ZydisRegisterGetString(o.reg.value);
            if (n) {
              di.regs_written.push_back(n);
            }
          }
        } else if (o.type == ZYDIS_OPERAND_TYPE_MEMORY) {
          if (o.mem.base == ZYDIS_REGISTER_RSP || o.mem.index == ZYDIS_REGISTER_RSP) {
            di.touches_sp = true;
          }
        }
      }
      offset += instr.length;
    } else {
      di.valid = false;
      di.length = 1;
      di.text = fmt::format("INVALID (0x{:02x})", data[offset]);
      offset += 1;
    }
    out.push_back(std::move(di));
  }
  return out;
}
