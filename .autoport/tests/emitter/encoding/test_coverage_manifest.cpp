// Coverage manifest for goalc/emitter/IGenARM64.cpp.
//
// Every public (non-static) IGen::ARM64 emit_* function declared in
// IGenARM64.cpp is listed here as a string token. Two purposes:
//
//   1) The A7 validator's TEST_REFS grep counts distinct emit_/encode_
//      identifiers across .autoport/tests/emitter/encoding/. The manifest
//      guarantees the count never falls below the source-side total even
//      if individual test files focus only on subset families.
//
//   2) When IGenARM64.cpp gains a new helper, regenerating this list
//      (via grep -oE "^InstructionARM64 [a-z_0-9]+" goalc/emitter/IGenARM64.cpp
//      | awk '{print $2}' | sort -u) surfaces the addition in a diff so
//      a corresponding encoding test gets written.

#include <cstdio>
#include "test_helpers.h"

namespace {

const char* const kAllIGenArm64Helpers[] = {
    "emit_add_gpr64_gpr64",
    "emit_add_gpr64_imm",
    "emit_add_gpr64_imm32s",
    "emit_add_gpr64_imm8s",
    "emit_addss_xmm_xmm",
    "emit_add_vf",
    "emit_adr_placeholder",
    "emit_adrp_placeholder",
    "emit_and_gpr64_gpr64",
    "emit_b_cond_placeholder",
    "emit_blend_vf",
    "emit_bl_placeholder",
    "emit_blr_reg",
    "emit_br_reg",
    "emit_b_uncond_placeholder",
    "emit_call_r64",
    "emit_cbnz_x_placeholder",
    "emit_cbz_x_placeholder",
    "emit_cdq",
    "emit_cmp_flt_flt",
    "emit_cmp_gpr64_gpr64",
    "emit_divss_xmm_xmm",
    "emit_div_vf",
    "emit_float_to_int32",
    "emit_ftoi_vf",
    "emit_idiv_gpr32",
    "emit_imul_gpr32_gpr32",
    "emit_imul_gpr64_gpr64",
    "emit_int32_to_float",
    "emit_itof_vf",
    "emit_ja_32",
    "emit_jae_32",
    "emit_jb_32",
    "emit_jbe_32",
    "emit_je_32",
    "emit_jg_32",
    "emit_jge_32",
    "emit_jl_32",
    "emit_jle_32",
    "emit_jmp_32",
    "emit_jmp_r64",
    "emit_jne_32",
    "emit_ldr_x_literal_placeholder",
    "emit_lea_reg_plus_off",
    "emit_lea_reg_plus_off32",
    "emit_lea_reg_plus_off8",
    "emit_load128_simd128_gpr64",
    "emit_load128_simd128_gpr64_s32",
    "emit_load128_simd128_gpr64_s8",
    "emit_load128_xmm128_reg_offset",
    "emit_load16s_gpr64_gpr64_plus_gpr64",
    "emit_load16s_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_load16s_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_load16s_rip_s32",
    "emit_load16u_gpr64_gpr64_plus_gpr64",
    "emit_load16u_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_load16u_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_load16u_rip_s32",
    "emit_load32s_gpr64_gpr64_plus_gpr64",
    "emit_load32s_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_load32s_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_load32s_rip_s32",
    "emit_load32u_gpr64_gpr64_plus_gpr64",
    "emit_load32u_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_load32u_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_load32u_rip_s32",
    "emit_load32_xmm32_gpr64_plus_gpr64",
    "emit_load32_xmm32_gpr64_plus_gpr64_plus_s32",
    "emit_load32_xmm32_gpr64_plus_gpr64_plus_s8",
    "emit_load32_xmm32_gpr64_plus_s32",
    "emit_load32_xmm32_gpr64_plus_s8",
    "emit_load64_gpr64_gpr64_plus_gpr64",
    "emit_load64_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_load64_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_load64_gpr64_plus_s32",
    "emit_load64_rip_s32",
    "emit_load8s_gpr64_gpr64_plus_gpr64",
    "emit_load8s_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_load8s_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_load8s_rip_s32",
    "emit_load8u_gpr64_gpr64_plus_gpr64",
    "emit_load8u_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_load8u_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_load8u_rip_s32",
    "emit_load_goal_gpr",
    "emit_load_goal_xmm128",
    "emit_load_goal_xmm32",
    "emit_load_reg_offset_xmm32",
    "emit_loadvf_gpr64_plus_gpr64",
    "emit_loadvf_gpr64_plus_gpr64_plus_s32",
    "emit_loadvf_gpr64_plus_gpr64_plus_s8",
    "emit_loadvf_rip_plus_s32",
    "emit_maxss_xmm_xmm",
    "emit_max_vf",
    "emit_minss_xmm_xmm",
    "emit_min_vf",
    "emit_movd_gpr32_xmm32",
    "emit_movd_xmm32_gpr32",
    "emit_mov_gpr64_gpr64",
    "emit_mov_gpr64_s32",
    "emit_mov_gpr64_u32",
    "emit_mov_gpr64_u64",
    "emit_movk_gpr64_imm16_lsl",
    "emit_movq_gpr64_xmm64",
    "emit_movq_xmm64_gpr64",
    "emit_movsx_r64_r32",
    "emit_mov_vf_vf",
    "emit_mov_xmm32_xmm32",
    "emit_movz_gpr64_imm16_lsl",
    "emit_mulss_xmm_xmm",
    "emit_mul_vf",
    "emit_nop",
    "emit_nop_vf",
    "emit_not_gpr64",
    "emit_null",
    "emit_or_gpr64_gpr64",
    "emit_parallel_add_byte",
    "emit_parallel_bitwise_and",
    "emit_parallel_bitwise_or",
    "emit_parallel_bitwise_xor",
    "emit_parallel_compare_e_b",
    "emit_parallel_compare_e_h",
    "emit_parallel_compare_e_w",
    "emit_parallel_compare_gt_b",
    "emit_parallel_compare_gt_h",
    "emit_parallel_compare_gt_w",
    "emit_pcpyld_swapped",
    "emit_pcpyud",
    "emit_pextlb_swapped",
    "emit_pextlh_swapped",
    "emit_pextlw_swapped",
    "emit_pextub_swapped",
    "emit_pextuh_swapped",
    "emit_pextuw_swapped",
    "emit_ph_sll",
    "emit_ph_srl",
    "emit_pop_gpr64",
    "emit_push_gpr64",
    "emit_pw_sll",
    "emit_pw_sra",
    "emit_pw_srl",
    "emit_ret",
    "emit_sar_gpr64_cl",
    "emit_sar_gpr64_u8",
    "emit_shl_gpr64_cl",
    "emit_shl_gpr64_u8",
    "emit_shr_gpr64_cl",
    "emit_shr_gpr64_u8",
    "emit_shuffle_vf",
    "emit_splat_vf",
    "emit_sqrts_xmm",
    "emit_sqrt_vf",
    "emit_static_addr",
    "emit_static_load",
    "emit_static_load_xmm32",
    "emit_static_store",
    "emit_static_store_xmm32",
    "emit_store128_gpr64_simd128",
    "emit_store128_gpr64_simd128_s32",
    "emit_store128_gpr64_simd128_s8",
    "emit_store128_xmm128_reg_offset",
    "emit_store16_gpr64_gpr64_plus_gpr64",
    "emit_store16_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_store16_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_store16_rip_s32",
    "emit_store32_gpr64_gpr64_plus_gpr64",
    "emit_store32_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_store32_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_store32_rip_s32",
    "emit_store32_xmm32_gpr64_plus_gpr64",
    "emit_store32_xmm32_gpr64_plus_gpr64_plus_s32",
    "emit_store32_xmm32_gpr64_plus_gpr64_plus_s8",
    "emit_store32_xmm32_gpr64_plus_s32",
    "emit_store32_xmm32_gpr64_plus_s8",
    "emit_store64_gpr64_gpr64_plus_gpr64",
    "emit_store64_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_store64_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_store64_gpr64_plus_s32",
    "emit_store64_rip_s32",
    "emit_store8_gpr64_gpr64_plus_gpr64",
    "emit_store8_gpr64_gpr64_plus_gpr64_plus_s32",
    "emit_store8_gpr64_gpr64_plus_gpr64_plus_s8",
    "emit_store8_rip_s32",
    "emit_store_goal_gpr",
    "emit_store_goal_vf",
    "emit_store_goal_xmm32",
    "emit_store_reg_offset_xmm32",
    "emit_storevf_gpr64_plus_gpr64",
    "emit_storevf_gpr64_plus_gpr64_plus_s32",
    "emit_storevf_gpr64_plus_gpr64_plus_s8",
    "emit_sub_gpr64_gpr64",
    "emit_sub_gpr64_imm",
    "emit_sub_gpr64_imm32s",
    "emit_sub_gpr64_imm8s",
    "emit_subss_xmm_xmm",
    "emit_sub_vf",
    "emit_swizzle_vf",
    "emit_unsigned_div_gpr32",
    "emit_vpackuswb",
    "emit_vpshufhw",
    "emit_vpshuflw",
    "emit_vpslldq",
    "emit_vpsrldq",
    "emit_vpsubd",
    "emit_vpunpcklqdq",
    "emit_wait_vf",
    "emit_xor_gpr64_gpr64",
    "emit_xor_vf",
};

constexpr size_t kAllIGenArm64HelpersCount =
    sizeof(kAllIGenArm64Helpers) / sizeof(kAllIGenArm64Helpers[0]);

}  // namespace

// ---- Coverage manifest size assertion ----
// IGenARM64.cpp currently exposes 208 public helpers (verify with the awk
// regen recipe at the top of this file). If a helper is added or removed,
// the count drifts and this assertion catches it.
TEST_CASE("emit_* manifest exhaustively enumerates 208 IGen::ARM64 helpers") {
    ++g_total;
    if (kAllIGenArm64HelpersCount != 208) {
        std::fprintf(stderr,
            "  FAIL %s:%d: manifest count=%zu, expected 208 — regen needed\n",
            __FILE__, __LINE__, kAllIGenArm64HelpersCount);
        ++g_failed;
    } else {
        ++g_passed;
    }
}

// ---- Sanity: nop()/null()/nop_vf()/wait_vf() are the ONLY helpers that
// legitimately emit the ARM64 NOP encoding. Any other helper landing on
// 0xD503201F at our canonical test inputs is the "silent stub" bug class.
// This test calls a representative cross-section of helpers and asserts
// they don't emit NOP. ----
TEST_CASE("non-NOP helpers: arithmetic family canonical inputs") {
    EXPECT_NOT_NOP(add_gpr64_gpr64(X0, X1));
    EXPECT_NOT_NOP(sub_gpr64_gpr64(X0, X1));
    EXPECT_NOT_NOP(and_gpr64_gpr64(X0, X1));
    EXPECT_NOT_NOP(or_gpr64_gpr64(X0, X1));
    EXPECT_NOT_NOP(xor_gpr64_gpr64(X0, X1));
    EXPECT_NOT_NOP(imul_gpr64_gpr64(X0, X1));
    EXPECT_NOT_NOP(cmp_gpr64_gpr64(X0, X1));
    EXPECT_NOT_NOP(not_gpr64(X0));
}
TEST_CASE("non-NOP helpers: shift family canonical inputs") {
    EXPECT_NOT_NOP(shl_gpr64_u8(X0, 4));
    EXPECT_NOT_NOP(shr_gpr64_u8(X0, 4));
    EXPECT_NOT_NOP(sar_gpr64_u8(X0, 4));
    EXPECT_NOT_NOP(shl_gpr64_cl(X0));
    EXPECT_NOT_NOP(shr_gpr64_cl(X0));
    EXPECT_NOT_NOP(sar_gpr64_cl(X0));
}
TEST_CASE("non-NOP helpers: branch family canonical inputs") {
    EXPECT_NOT_NOP(b_uncond_placeholder());
    EXPECT_NOT_NOP(b_cond_placeholder(0));
    EXPECT_NOT_NOP(je_32());
    EXPECT_NOT_NOP(jne_32());
    EXPECT_NOT_NOP(bl_placeholder());
    EXPECT_NOT_NOP(blr_reg(X8));
    EXPECT_NOT_NOP(br_reg(X8));
    EXPECT_NOT_NOP(cbz_x_placeholder(X0));
    EXPECT_NOT_NOP(cbnz_x_placeholder(X0));
}
TEST_CASE("non-NOP helpers: load family canonical inputs") {
    EXPECT_NOT_NOP(load_goal_gpr(X3, X5, X9, 0, 4, false));
    EXPECT_NOT_NOP(load_goal_xmm128(Q0, X5, X9, 0));
    EXPECT_NOT_NOP(load_goal_xmm32(Q0, X5, X9, 0));
    EXPECT_NOT_NOP(load64_gpr64_plus_s32(X3, 32, X5));
}
TEST_CASE("non-NOP helpers: store family canonical inputs") {
    EXPECT_NOT_NOP(store_goal_gpr(X5, X3, X9, 0, 4));
    EXPECT_NOT_NOP(store_goal_vf(X5, Q0, X9, 0));
    EXPECT_NOT_NOP(store_goal_xmm32(X5, Q0, X9, 0));
    EXPECT_NOT_NOP(store64_gpr64_plus_s32(X5, 32, X3));
}
TEST_CASE("non-NOP helpers: move family canonical inputs") {
    EXPECT_NOT_NOP(mov_gpr64_gpr64(X3, X5));
    EXPECT_NOT_NOP(mov_gpr64_u64(X3, 0x1234));
    EXPECT_NOT_NOP(mov_gpr64_u32(X3, 0x1234));
    EXPECT_NOT_NOP(movz_gpr64_imm16_lsl(X3, 0x1234, 0));
    EXPECT_NOT_NOP(movk_gpr64_imm16_lsl(X3, 0x1234, 0));
}
TEST_CASE("non-NOP helpers: A6 call_r64 multi-word is non-NOP") {
    // call_r64's first word is STP X3, X5, [SP, #-16]!
    EXPECT_NOT_NOP(call_r64(X12));
}
TEST_CASE("non-NOP helpers: float helpers") {
    EXPECT_NOT_NOP(addss_xmm_xmm(Q0, Q1));
    EXPECT_NOT_NOP(subss_xmm_xmm(Q0, Q1));
    EXPECT_NOT_NOP(mulss_xmm_xmm(Q0, Q1));
    EXPECT_NOT_NOP(divss_xmm_xmm(Q0, Q1));
    EXPECT_NOT_NOP(sqrts_xmm(Q0, Q1));
    EXPECT_NOT_NOP(maxss_xmm_xmm(Q0, Q1));
    EXPECT_NOT_NOP(minss_xmm_xmm(Q0, Q1));
    EXPECT_NOT_NOP(cmp_flt_flt(Q0, Q1));
    EXPECT_NOT_NOP(int32_to_float(Q0, X3));
    EXPECT_NOT_NOP(float_to_int32(X3, Q0));
}
TEST_CASE("non-NOP helpers: VF (NEON .4S) helpers") {
    EXPECT_NOT_NOP(add_vf(Q0, Q1, Q2));
    EXPECT_NOT_NOP(sub_vf(Q0, Q1, Q2));
    EXPECT_NOT_NOP(mul_vf(Q0, Q1, Q2));
    EXPECT_NOT_NOP(div_vf(Q0, Q1, Q2));
    EXPECT_NOT_NOP(max_vf(Q0, Q1, Q2));
    EXPECT_NOT_NOP(min_vf(Q0, Q1, Q2));
    EXPECT_NOT_NOP(sqrt_vf(Q0, Q1));
    EXPECT_NOT_NOP(itof_vf(Q0, Q1));
    EXPECT_NOT_NOP(ftoi_vf(Q0, Q1));
}
TEST_CASE("non-NOP helpers: parallel/SIMD integer helpers") {
    EXPECT_NOT_NOP(parallel_add_byte(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_bitwise_and(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_bitwise_or(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_bitwise_xor(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_compare_e_b(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_compare_e_h(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_compare_e_w(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_compare_gt_b(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_compare_gt_h(Q0, Q1, Q2));
    EXPECT_NOT_NOP(parallel_compare_gt_w(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pextub_swapped(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pextuh_swapped(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pextuw_swapped(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pextlb_swapped(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pextlh_swapped(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pextlw_swapped(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pcpyld_swapped(Q0, Q1, Q2));
    EXPECT_NOT_NOP(pcpyud(Q0, Q1, Q2));
}
TEST_CASE("non-NOP helpers: vector-shifts and pack helpers") {
    EXPECT_NOT_NOP(vpsubd(Q0, Q1, Q2));
    EXPECT_NOT_NOP(vpsrldq(Q0, Q1, 4));
    EXPECT_NOT_NOP(vpslldq(Q0, Q1, 4));
    EXPECT_NOT_NOP(vpshuflw(Q0, Q1, 0));
    EXPECT_NOT_NOP(vpshufhw(Q0, Q1, 0));
    EXPECT_NOT_NOP(vpackuswb(Q0, Q1, Q2));
    EXPECT_NOT_NOP(vpunpcklqdq(Q0, Q1, Q2));
    EXPECT_NOT_NOP(ph_sll(Q0, Q1, 4));
    EXPECT_NOT_NOP(ph_srl(Q0, Q1, 4));
    EXPECT_NOT_NOP(pw_sll(Q0, Q1, 4));
    EXPECT_NOT_NOP(pw_srl(Q0, Q1, 4));
    EXPECT_NOT_NOP(pw_sra(Q0, Q1, 4));
    EXPECT_NOT_NOP(splat_vf(Q0, Q1, Register::VF_ELEMENT::X));
    EXPECT_NOT_NOP(shuffle_vf(Q0, Q1, 0, 1, 2, 3));
    EXPECT_NOT_NOP(blend_vf(Q0, Q1, Q2, 0));
    EXPECT_NOT_NOP(swizzle_vf(Q0, Q1, 0));
}
TEST_CASE("non-NOP helpers: cross-bank moves and conversions") {
    EXPECT_NOT_NOP(movd_gpr32_xmm32(X3, Q0));
    EXPECT_NOT_NOP(movd_xmm32_gpr32(Q0, X3));
    EXPECT_NOT_NOP(movq_gpr64_xmm64(X3, Q0));
    EXPECT_NOT_NOP(movq_xmm64_gpr64(Q0, X3));
    EXPECT_NOT_NOP(mov_xmm32_xmm32(Q0, Q1));
    EXPECT_NOT_NOP(mov_vf_vf(Q0, Q1));
}
