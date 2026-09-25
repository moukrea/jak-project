#include "Register.h"

#include <stdexcept>

#include "fmt/format.h"

namespace emitter {
RegisterInfo RegisterInfo::make_register_info() {
  RegisterInfo info;

  info.m_info[RAX] = {false, false, "rax"};  // return, temp
  info.m_info[RCX] = {false, false, "rcx"};  // gpr arg 3, temp
  info.m_info[RDX] = {false, false, "rdx"};  // gpr arg 2, temp
  info.m_info[RBX] = {true, false, "rbx"};   // saved
  info.m_info[RSP] = {false, true, "rsp"};   // stack pointer
  info.m_info[RBP] = {true, false, "rbp"};   // saved
  info.m_info[RSI] = {false, false, "rsi"};  // gpr arg 1, temp
  info.m_info[RDI] = {false, false, "rdi"};  // gpr arg 0, temp

  info.m_info[R8] = {false, false, "r8"};   // gpr arg 4, temp
  info.m_info[R9] = {false, false, "r9"};   // gpr arg 5, temp
  info.m_info[R10] = {true, false, "r10"};  // gpr arg 6, saved
  info.m_info[R11] = {true, false, "r11"};  // gpr arg 7, saved
  info.m_info[R12] = {true, false, "r12"};  // saved
  info.m_info[R13] = {false, true, "r13"};  // pp
  info.m_info[R14] = {false, true, "r14"};  // st
  info.m_info[R15] = {false, true, "r15"};  // offset.

  info.m_info[XMM0] = {false, false, "xmm0"};
  info.m_info[XMM1] = {false, false, "xmm1"};
  info.m_info[XMM2] = {false, false, "xmm2"};
  info.m_info[XMM3] = {false, false, "xmm3"};
  info.m_info[XMM4] = {false, false, "xmm4"};
  info.m_info[XMM5] = {false, false, "xmm5"};
  info.m_info[XMM6] = {false, false, "xmm6"};
  info.m_info[XMM7] = {false, false, "xmm7"};
  info.m_info[XMM8] = {true, false, "xmm8"};
  info.m_info[XMM9] = {true, false, "xmm9"};
  info.m_info[XMM10] = {true, false, "xmm10"};
  info.m_info[XMM11] = {true, false, "xmm11"};
  info.m_info[XMM12] = {true, false, "xmm12"};
  info.m_info[XMM13] = {true, false, "xmm13"};
  info.m_info[XMM14] = {true, false, "xmm14"};
  info.m_info[XMM15] = {true, false, "xmm15"};

#ifdef GOALC_BACKEND_ARM64
  // perf-codegen-arm64-regs: X19..X28 and V3..V15 as extra GOAL temporaries.
  // Not saved (they are caller-saved GOAL temporaries, clobbered on every
  // GOAL function call, exactly like RAX/RCX/etc. above) and not special.
  info.m_info[AX19] = {false, false, "x19"};
  info.m_info[AX20] = {false, false, "x20"};
  info.m_info[AX21] = {false, false, "x21"};
  info.m_info[AX22] = {false, false, "x22"};
  info.m_info[AX23] = {false, false, "x23"};
  info.m_info[AX24] = {false, false, "x24"};
  info.m_info[AX25] = {false, false, "x25"};
  info.m_info[AX26] = {false, false, "x26"};
  info.m_info[AX27] = {false, false, "x27"};
  info.m_info[AX28] = {false, false, "x28"};
  for (int i = ARM64_UNUSED_42; i <= ARM64_UNUSED_50; i++) {
    info.m_info[i] = {false, true, fmt::format("arm64-unused-{}", i)};
  }
  info.m_info[AV3] = {false, false, "v3"};
  info.m_info[AV4] = {false, false, "v4"};
  info.m_info[AV5] = {false, false, "v5"};
  info.m_info[AV6] = {false, false, "v6"};
  info.m_info[AV7] = {false, false, "v7"};
  info.m_info[AV8] = {false, false, "v8"};
  info.m_info[AV9] = {false, false, "v9"};
  info.m_info[AV10] = {false, false, "v10"};
  info.m_info[AV11] = {false, false, "v11"};
  info.m_info[AV12] = {false, false, "v12"};
  info.m_info[AV13] = {false, false, "v13"};
  info.m_info[AV14] = {false, false, "v14"};
  info.m_info[AV15] = {false, false, "v15"};
#endif

  info.m_gpr_arg_regs = std::array<Register, N_ARGS>({RDI, RSI, RDX, RCX, R8, R9, R10, R11});
  // skip xmm0 so it can be used for return.
  info.m_xmm_arg_regs =
      std::array<Register, N_ARGS>({XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7, XMM8});
  info.m_saved_gprs = std::array<Register, N_SAVED_GPRS>({RBX, RBP, R10, R11, R12});
  info.m_saved_xmms =
      std::array<Register, N_SAVED_XMMS>({XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15});

  for (size_t i = 0; i < N_SAVED_GPRS; i++) {
    info.m_saved_all[i] = info.m_saved_gprs[i];
  }
  for (size_t i = 0; i < N_SAVED_XMMS; i++) {
    info.m_saved_all[i + N_SAVED_GPRS] = info.m_saved_xmms[i];
  }

  // todo - experiment with better orders for allocation.
  info.m_gpr_alloc_order = {RAX, RCX, RDX, RBX, RBP, RSI, RDI, R8, R9, R10};  // arbitrary
  info.m_xmm_alloc_order = {XMM0, XMM1, XMM2, XMM3,  XMM4,  XMM5,  XMM6,
                            XMM7, XMM8, XMM9, XMM10, XMM11, XMM12, XMM13};

  // these should only be temp registers!
  info.m_gpr_temp_only_alloc_order = {RAX, RCX, RDX, RSI, RDI, R8, R9};
  info.m_xmm_temp_only_alloc_order = {XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7};

  info.m_gpr_spill_temp_alloc_order = {RAX, RCX, RDX, RBX, RBP, RSI,
                                       RDI, R8,  R9,  R10, R11, R12};  // arbitrary
  info.m_xmm_spill_temp_alloc_order = {XMM0, XMM1, XMM2,  XMM3,  XMM4,  XMM5,  XMM6,  XMM7,
                                       XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15};
  return info;
}

RegisterInfo gRegInfo = RegisterInfo::make_register_info();

std::string to_string(HWRegKind kind) {
  switch (kind) {
    case HWRegKind::GPR:
      return "gpr";
    case HWRegKind::XMM:
      return "xmm";
    default:
      throw std::runtime_error("Unsupported HWRegKind");
  }
}

HWRegKind reg_class_to_hw(RegClass reg_class) {
  switch (reg_class) {
    case RegClass::VECTOR_FLOAT:
    case RegClass::FLOAT:
    case RegClass::INT_128:
      return HWRegKind::XMM;
    case RegClass::GPR_64:
      return HWRegKind::GPR;
    default:
      ASSERT(false);
      return HWRegKind::INVALID;
  }
}

std::string Register::print() const {
  return gRegInfo.get_info(*this).name;
}

}  // namespace emitter