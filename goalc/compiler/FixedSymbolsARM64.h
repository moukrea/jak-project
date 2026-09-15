#pragma once

#include <optional>
#include <string_view>

#include "common/symbols.h"

namespace emitter::arm64 {
struct FixedSymbol {
  std::string_view name;
  int offset;
};

// Names must match Jak1 InitHeapAndSymbol exactly, including "nothing" and
// "uintger". The two slots called "asize-of-basic-func" are ambiguous and
// deliberately retain the runtime linker lookup.
inline constexpr FixedSymbol kJak1FixedSymbols[] = {
    {"#f", jak1_symbols::FIX_SYM_FALSE},
    {"#t", jak1_symbols::FIX_SYM_TRUE},
    {"nothing", jak1_symbols::FIX_SYM_NOTHING_FUNC},
    {"zero-func", jak1_symbols::FIX_SYM_ZERO_FUNC},
    {"delete-basic", jak1_symbols::FIX_SYM_DEL_BASIC_FUNC},
    {"global", jak1_symbols::FIX_SYM_GLOBAL_HEAP},
    {"debug", jak1_symbols::FIX_SYM_DEBUG_HEAP},
    {"static", jak1_symbols::FIX_SYM_STATIC},
    {"loading-level", jak1_symbols::FIX_SYM_LOADING_LEVEL},
    {"loading-package", jak1_symbols::FIX_SYM_LOADING_PACKAGE},
    {"process-level-heap", jak1_symbols::FIX_SYM_PROCESS_LEVEL_HEAP},
    {"stack", jak1_symbols::FIX_SYM_STACK},
    {"scratch", jak1_symbols::FIX_SYM_SCRATCH},
    {"*scratch-top*", jak1_symbols::FIX_SYM_SCRATCH_TOP},
    {"level", jak1_symbols::FIX_SYM_LEVEL},
    {"art-group", jak1_symbols::FIX_SYM_ART_GROUP},
    {"texture-page-dir", jak1_symbols::FIX_SYM_TX_PAGE_DIR},
    {"texture-page", jak1_symbols::FIX_SYM_TX_PAGE},
    {"sound", jak1_symbols::FIX_SYM_SOUND},
    {"dgo", jak1_symbols::FIX_SYM_DGO},
    {"top-level", jak1_symbols::FIX_SYM_TOP_LEVEL},
    {"object", jak1_symbols::FIX_SYM_OBJECT_TYPE},
    {"structure", jak1_symbols::FIX_SYM_STRUCTURE_TYPE},
    {"basic", jak1_symbols::FIX_SYM_BASIC_TYPE},
    {"symbol", jak1_symbols::FIX_SYM_SYMBOL_TYPE},
    {"type", jak1_symbols::FIX_SYM_TYPE_TYPE},
    {"string", jak1_symbols::FIX_SYM_STRING_TYPE},
    {"function", jak1_symbols::FIX_SYM_FUNCTION_TYPE},
    {"vu-function", jak1_symbols::FIX_SYM_VU_FUNCTION_TYPE},
    {"link-block", jak1_symbols::FIX_SYM_LINK_BLOCK},
    {"kheap", jak1_symbols::FIX_SYM_KHEAP},
    {"array", jak1_symbols::FIX_SYM_ARRAY_TYPE},
    {"pair", jak1_symbols::FIX_SYM_PAIR_TYPE},
    {"process-tree", jak1_symbols::FIX_SYM_PROCESS_TREE_TYPE},
    {"process", jak1_symbols::FIX_SYM_PROCESS_TYPE},
    {"thread", jak1_symbols::FIX_SYM_THREAD_TYPE},
    {"connectable", jak1_symbols::FIX_SYM_CONNECTABLE_TYPE},
    {"stack-frame", jak1_symbols::FIX_SYM_STACK_FRAME_TYPE},
    {"file-stream", jak1_symbols::FIX_SYM_FILE_STREAM_TYPE},
    {"pointer", jak1_symbols::FIX_SYM_POINTER_TYPE},
    {"number", jak1_symbols::FIX_SYM_NUMBER_TYPE},
    {"float", jak1_symbols::FIX_SYM_FLOAT_TYPE},
    {"integer", jak1_symbols::FIX_SYM_INTEGER_TYPE},
    {"binteger", jak1_symbols::FIX_SYM_BINTEGER_TYPE},
    {"sinteger", jak1_symbols::FIX_SYM_SINTEGER_TYPE},
    {"int8", jak1_symbols::FIX_SYM_INT8_TYPE},
    {"int16", jak1_symbols::FIX_SYM_INT16_TYPE},
    {"int32", jak1_symbols::FIX_SYM_INT32_TYPE},
    {"int64", jak1_symbols::FIX_SYM_INT64_TYPE},
    {"int128", jak1_symbols::FIX_SYM_INT128_TYPE},
    {"uintger", jak1_symbols::FIX_SYM_UINTEGER_TYPE},
    {"uint8", jak1_symbols::FIX_SYM_UINT8_TYPE},
    {"uint16", jak1_symbols::FIX_SYM_UINT16_TYPE},
    {"uint32", jak1_symbols::FIX_SYM_UINT32_TYPE},
    {"uint64", jak1_symbols::FIX_SYM_UINT64_TYPE},
    {"uint128", jak1_symbols::FIX_SYM_UINT128_TYPE},
};

constexpr std::optional<int> fixed_symbol_offset(GameVersion version, std::string_view name) {
  if (version == GameVersion::Jak1) {
    for (const auto& symbol : kJak1FixedSymbols) {
      if (symbol.name == name && symbol.offset >= 0 && symbol.offset <= 16380 &&
          (symbol.offset & 3) == 0) {
        return symbol.offset;
      }
    }
  }
  return std::nullopt;
}

enum class SymbolAccess { LoadUnsigned, LoadSigned, Store };

// X14 is the host symbol-table base. No relocation may be attached to this
// instruction: its immediate already names the fixed slot.
constexpr u32 fixed_symbol_instruction(SymbolAccess access, int reg, int offset) {
  const u32 opcode = access == SymbolAccess::Store        ? 0xB9000000u
                     : access == SymbolAccess::LoadSigned ? 0xB9800000u
                                                          : 0xB9400000u;
  return opcode | (u32(offset / 4) << 10) | (14u << 5) | u32(reg);
}
}  // namespace emitter::arm64
