#include "test_helpers.h"

#include "goalc/compiler/FixedSymbolsARM64.h"

namespace {
void expect_lookup(GameVersion version, std::string_view name, std::optional<int> expected) {
  const auto actual = arm64::fixed_symbol_offset(version, name);
  ++g_total;
  if (actual == expected) {
    ++g_passed;
  } else {
    ++g_failed;
    std::fprintf(stderr, "fixed symbol lookup failed: version=%d name=%.*s\n", int(version),
                 int(name.size()), name.data());
  }
}
}  // namespace

TEST_CASE("fixed symbol names and other-version fallback") {
  expect_lookup(GameVersion::Jak1, "#f", 0);
  expect_lookup(GameVersion::Jak1, "nothing", 0x128);
  expect_lookup(GameVersion::Jak1, "uintger", 0x58);
  expect_lookup(GameVersion::Jak1, "nothing-func", std::nullopt);
  expect_lookup(GameVersion::Jak1, "uinteger", std::nullopt);
  expect_lookup(GameVersion::Jak1, "asize-of-basic-func", std::nullopt);
  expect_lookup(GameVersion::Jak1, "*kernel-sp*", std::nullopt);
  expect_lookup(GameVersion::Jak2, "#t", std::nullopt);
  expect_lookup(GameVersion::Jak3, "function", std::nullopt);
}

TEST_CASE("fixed symbol access words have X14 base and no extra instructions") {
  using arm64::fixed_symbol_instruction;
  using arm64::SymbolAccess;
  // ldr w0,[x14]; ldrsw x1,[x14,#0x128]; str w7,[x14,#0x140].
  EXPECT_ENC(InstructionARM64(fixed_symbol_instruction(SymbolAccess::LoadUnsigned, 0, 0)),
             0xB94001C0u);
  EXPECT_ENC(InstructionARM64(fixed_symbol_instruction(SymbolAccess::LoadSigned, 1, 0x128)),
             0xB98129C1u);
  EXPECT_ENC(InstructionARM64(fixed_symbol_instruction(SymbolAccess::Store, 7, 0x140)),
             0xB90141C7u);
  // Boundary of the 12-bit unsigned immediate, scaled by four bytes.
  EXPECT_ENC(InstructionARM64(fixed_symbol_instruction(SymbolAccess::LoadUnsigned, 30, 16380)),
             0xB97FFDDEu);
  for (const auto access :
       {SymbolAccess::LoadUnsigned, SymbolAccess::LoadSigned, SymbolAccess::Store}) {
    EXPECT_EXTRA_WORDS(InstructionARM64(fixed_symbol_instruction(access, 1, 0x128)), 0);
  }
}
