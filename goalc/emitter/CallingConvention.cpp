#include "CallingConvention.h"

#include "common/util/Assert.h"

CallingConvention get_function_calling_convention(const TypeSpec& function_type,
                                                  const TypeSystem& type_system) {
  ASSERT(function_type.base_type() == "function");
  ASSERT(function_type.arg_count() > 0);
  ASSERT(function_type.arg_count() <= 9);

  int gpr_idx = 0;
  int xmm_idx = 0;

  CallingConvention cc;

#ifdef GOALC_BACKEND_ARM64
  // A33: on the arm64 backend, EVERY argument and return value uses a GPR
  // slot, including 128-bit value types (truncated to 64 bits, like every
  // other 128-bit-through-GPR path on this backend). The x86 convention's
  // XMM ids (16..24) would otherwise become regalloc CONSTRAINTS that map
  // onto AArch64 X16/X17 (the emitter's addressing scratch), X18 (platform
  // register) and X20-X22 (pp/st/offset) via the id & 0x1f encode-time
  // mapping — clobbering live values. This was the root cause of the
  // hud-classes-pc heap corruption (low32 of a host address stored through
  // (-> draw sink-group) in initialize-skeleton).
  (void)xmm_idx;
  if (function_type.arg_count() == 2 && function_type.get_arg(0).print() == "_varargs_") {
    for (int i = 0; i < 8; i++) {
      cc.arg_regs.push_back(emitter::gRegInfo.get_gpr_arg_reg(gpr_idx++));
    }
  } else {
    for (int i = 0; i < (int)function_type.arg_count() - 1; i++) {
      cc.arg_regs.push_back(emitter::gRegInfo.get_gpr_arg_reg(gpr_idx++));
    }
  }
  if (function_type.last_arg() != TypeSpec("none")) {
    cc.return_reg = emitter::gRegInfo.get_gpr_ret_reg();
  }
#else
  if (function_type.arg_count() == 2 && function_type.get_arg(0).print() == "_varargs_") {
    for (int i = 0; i < 8; i++) {
      cc.arg_regs.push_back(emitter::gRegInfo.get_gpr_arg_reg(gpr_idx++));
    }
  } else {
    for (int i = 0; i < (int)function_type.arg_count() - 1; i++) {
      auto info = type_system.lookup_type_allow_partial_def(function_type.get_arg(i));
      auto load_size = type_system.get_load_size_allow_partial_def(function_type.get_arg(i));
      if (dynamic_cast<const ValueType*>(info) && load_size == 16) {
        cc.arg_regs.push_back(emitter::gRegInfo.get_xmm_arg_reg(xmm_idx++));
      } else {
        cc.arg_regs.push_back(emitter::gRegInfo.get_gpr_arg_reg(gpr_idx++));
      }
    }
  }

  if (function_type.last_arg() != TypeSpec("none")) {
    if (type_system.get_load_size_allow_partial_def(function_type.last_arg()) == 16) {
      cc.return_reg = emitter::gRegInfo.get_xmm_ret_reg();
    } else {
      cc.return_reg = emitter::gRegInfo.get_gpr_ret_reg();
    }
  }
#endif

  return cc;
}

std::vector<emitter::Register> get_arg_registers(const TypeSystem& type_system,
                                                 const std::vector<TypeSpec>& arg_types) {
  std::vector<emitter::Register> result;
  int gpr_idx = 0;
#ifdef GOALC_BACKEND_ARM64
  // A33: all-GPR argument binding; must stay symmetric with
  // get_function_calling_convention above (caller and callee sides).
  (void)type_system;
  for (size_t i = 0; i < arg_types.size(); i++) {
    result.push_back(emitter::gRegInfo.get_gpr_arg_reg(gpr_idx++));
  }
#else
  int xmm_idx = 0;
  for (auto& type : arg_types) {
    auto load_size = type_system.get_load_size_allow_partial_def(type);
    if (load_size == 16) {
      result.push_back(emitter::gRegInfo.get_xmm_arg_reg(xmm_idx++));
    } else {
      result.push_back(emitter::gRegInfo.get_gpr_arg_reg(gpr_idx++));
    }
  }
#endif
  return result;
}
