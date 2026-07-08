// A37 (autoport) — real Mips2C table backend for the arm64 builds
// (Android + linux-arm64/qemu). Serves BOTH jak1 and jak2 (Gjak2-render):
// each game gets its own trampoline arena, allowlist, and shared noop,
// sliced with that game's own symbol-read idiom (jak2 reads fixed-syms via
// u32_in_fixed_sym / Symbol4::value(), jak1 via a raw *(s7+off) deref).
//
// Upstream, game/mips2c/mips2c_table.cpp owns gMips2CLinkCallbacks +
// gLinkedFunctionTable, but its jak1+jak2+jak3 callback map pulls every
// game's mips2c TU (~300 functions); the arm64 builds only compile the
// jak1 set. Until A37 both arm64 builds replaced the table with stubs
// (LinkedFunctionTable::get() -> 0), which silently bound EVERY jak1
// `def-mips2c` symbol to 0: calc-animation-from-spr and
// cspace<-parented-transformq-joint! (joint.gc) never ran, so no bone
// transform was ever computed; the title screen's othercam process
// copied a zero joint matrix into *camera-other-matrix*/-trans and a
// garbage bone scale into *camera-other-fov*; update-camera then built
// *math-camera* camera-temp from those zeros and every vertex
// degenerated -> black frames with 64k submitted tris (A36's named
// blocker, root-caused by the A37-CAM field probe).
//
// This TU mirrors mips2c_table.cpp for the jak1 subset:
//  - the jak1 gMips2CLinkCallbacks map, byte-for-byte (jak2/3 empty),
//  - the real LinkedFunctionTable::reg()/get(), with the dynamically
//    emitted GOAL-heap trampoline in AArch64 instead of x86-64. The
//    trampoline loads the C++ body + GOAL stack size into x9/x10 and
//    branches to _mips2c_call_arm64 (game/kernel/asm_funcs_arm64.s),
//    which builds the ExecutionContext exactly like the x86
//    _mips2c_call_systemv and returns the context's v0 in x0.

#include "mips2c_table.h"

#include "common/log/log.h"
#include "common/symbols.h"

#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/kernel/jak2/kscheme.h"
#include "game/runtime.h"

extern "C" {
void _mips2c_call_arm64();
}

#ifdef __aarch64__
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <string>
#include <unwind.h>
#include <vector>
#ifdef __ANDROID__
#include <android/log.h>
#include <sys/system_properties.h>
#endif
// Gnd OOB write-watch globals + reporter. Defined in this arm64-only TU
// because it is linked into android libgk.so via --whole-archive (the desktop
// mips2c_table.cpp is not part of the android android_kernel archive). The
// mips2c store helpers in mips2c_private.h call gnd_oob_check -> gnd_oob_report.
// Glogo-garble: disarmed (see gnd_oob_report below) -- all flagged writes proved benign.
std::atomic<bool> g_gnd_oob_armed{false};

// Gecho-pool probe: TEMPORARY arm64-only diagnostic. When the watched code
// bands (see gnd_oob_check in mips2c_private.h) take a mips2c store, dump a
// libgk-relative host backtrace so the offending mips2c execute() body can be
// named offline (addr2line). Gated OFF by default (g_gnd_oob_armed). Removed
// after the scattering builder is identified.
namespace {
struct GndUnwindState {
  uintptr_t* frames;
  int cap;
  int count;
};
_Unwind_Reason_Code gnd_unwind_cb(_Unwind_Context* ctx, void* arg) {
  auto* st = static_cast<GndUnwindState*>(arg);
  if (st->count >= st->cap) {
    return _URC_END_OF_STACK;
  }
  uintptr_t ip = _Unwind_GetIP(ctx);
  if (ip) {
    st->frames[st->count++] = ip;
  }
  return _URC_NO_REASON;
}
}  // namespace

__attribute__((noinline)) void gnd_oob_report(char kind, unsigned int target,
                                              unsigned long long lo, unsigned long long /*hi*/,
                                              int nbytes) {
  static std::atomic<int> s_count{0};
  int n = s_count.fetch_add(1, std::memory_order_relaxed);
  if (n >= 80) {
    return;
  }

  constexpr int kMaxFrames = 10;
  uintptr_t frames[kMaxFrames] = {0};
  GndUnwindState st{frames, kMaxFrames, 0};
  _Unwind_Backtrace(gnd_unwind_cb, &st);

  uintptr_t base = 0;
  Dl_info di;
  if (dladdr((void*)&gnd_oob_report, &di)) {
    base = (uintptr_t)di.dli_fbase;
  }

  char line[512];
  int off = 0;
  int w = snprintf(line + off, sizeof(line) - off,
                   "GECHO-OOB #%d kind=%c target=0x%x val=0x%llx nb=%d frames:", n, kind, target,
                   lo, nbytes);
  if (w > 0) {
    off += (w < (int)sizeof(line) - off) ? w : (int)sizeof(line) - off - 1;
  }
  for (int i = 0; i < st.count && off < (int)sizeof(line) - 1; i++) {
    uintptr_t rel = (frames[i] >= base) ? (frames[i] - base) : frames[i];
    w = snprintf(line + off, sizeof(line) - off, " 0x%lx", (unsigned long)rel);
    if (w > 0) {
      off += (w < (int)sizeof(line) - off) ? w : (int)sizeof(line) - off - 1;
    }
  }
  fprintf(stderr, "%s\n", line);
}
#endif

// clang-format off
namespace Mips2C {

namespace jak1 {
namespace draw_string { extern void link(); }
namespace particle_adgif { extern void link(); }
namespace sp_launch_particles_var { extern void link(); }
namespace sp_process_block_3d { extern void link(); }
namespace sp_process_block_2d { extern void link(); }
namespace draw_large_polygon { extern void link(); }
namespace init_sky_regs { extern void link(); }
namespace clip_polygon_against_positive_hyperplane { extern void link(); }
namespace render_sky_quad { extern void link(); }
namespace render_sky_tri { extern void link(); }
namespace set_tex_offset { extern void link(); }
namespace set_sky_vf27 { extern void link(); }
namespace set_sky_vf23_value { extern void link(); }
namespace adgif_shader_texture_with_update { extern void link(); }
namespace init_boundary_regs { extern void link(); }
namespace render_boundary_quad { extern void link(); }
namespace render_boundary_tri { extern void link(); }
namespace draw_boundary_polygon { extern void link(); }
namespace draw_inline_array_tfrag { extern void link(); }
namespace stats_tfrag_asm { extern void link(); }
namespace time_of_day_interp_colors_scratch { extern void link(); }
namespace collide_do_primitives { extern void link(); }
namespace moving_sphere_triangle_intersect { extern void link(); }
namespace method_12_collide_mesh { extern void link(); }
namespace method_11_collide_mesh { extern void link(); }
namespace collide_probe_node { extern void link(); }
namespace collide_probe_instance_tie { extern void link(); }
namespace method_26_collide_cache { extern void link(); }
namespace method_32_collide_cache { extern void link(); }
namespace pc_upload_collide_frag { extern void link(); }
namespace method_28_collide_cache { extern void link(); }
namespace method_27_collide_cache { extern void link(); }
namespace method_29_collide_cache { extern void link(); }
namespace method_12_collide_shape_prim_mesh { extern void link(); }
namespace method_14_collide_shape_prim_mesh { extern void link(); }
namespace method_13_collide_shape_prim_mesh { extern void link(); }
namespace method_30_collide_cache { extern void link(); }
namespace method_9_collide_cache_prim { extern void link(); }
namespace method_10_collide_cache_prim { extern void link(); }
namespace method_10_collide_puss_work { extern void link(); }
namespace method_9_collide_puss_work { extern void link(); }
namespace method_15_collide_mesh { extern void link(); }
namespace method_14_collide_mesh { extern void link(); }
namespace method_16_collide_edge_work { extern void link(); }
namespace method_15_collide_edge_work { extern void link(); }
namespace method_10_collide_edge_hold_list { extern void link(); }
namespace method_18_collide_edge_work { extern void link(); }
namespace calc_animation_from_spr { extern void link(); }
namespace bones_mtx_calc { extern void link(); }
namespace cspace_parented_transformq_joint { extern void link(); }
namespace draw_bones_merc { extern void link(); }
namespace draw_bones_check_longest_edge_asm { extern void link(); }
namespace blerc_execute { extern void link(); }
namespace setup_blerc_chains_for_one_fragment { extern void link(); }
namespace generic_merc_init_asm { extern void link(); }
namespace generic_merc_execute_asm { extern void link(); }
namespace mercneric_convert { extern void link(); }
namespace generic_prepare_dma_double { extern void link(); }
namespace generic_light_proc { extern void link(); }
namespace generic_envmap_proc { extern void link(); }
namespace high_speed_reject { extern void link(); }
namespace generic_prepare_dma_single { extern void link(); }
namespace ripple_create_wave_table { extern void link(); }
namespace ripple_execute_init { extern void link(); }
namespace ripple_apply_wave_table { extern void link(); }
namespace ripple_matrix_scale { extern void link(); }
namespace init_ocean_far_regs { extern void link(); }
namespace render_ocean_quad { extern void link(); }
namespace draw_large_polygon_ocean { extern void link(); }
namespace ocean_interp_wave { extern void link(); }
namespace ocean_generate_verts { extern void link(); }
namespace shadow_execute { extern void link(); }
namespace shadow_add_double_edges { extern void link(); }
namespace shadow_add_double_tris { extern void link(); }
namespace shadow_add_single_edges { extern void link(); }
namespace shadow_add_facing_single_tris { extern void link(); }
namespace shadow_add_verts { extern void link(); }
namespace shadow_find_double_edges { extern void link(); }
namespace shadow_find_facing_double_tris { extern void link(); }
namespace shadow_find_single_edges { extern void link(); }
namespace shadow_find_facing_single_tris { extern void link(); }
namespace shadow_init_vars { extern void link(); }
namespace shadow_scissor_top { extern void link(); }
namespace shadow_scissor_edges { extern void link(); }
namespace shadow_calc_dual_verts { extern void link(); }
namespace shadow_xform_verts { extern void link(); }
namespace draw_inline_array_instance_tie { extern void link(); }
namespace draw_inline_array_prototype_tie_generic_asm { extern void link(); }
namespace generic_tie_dma_to_spad_sync { extern void link(); }
namespace generic_envmap_dproc { extern void link(); }
namespace generic_interp_dproc { extern void link(); }
namespace generic_no_light_dproc { extern void link(); }
namespace generic_tie_convert { extern void link(); }
}  // namespace jak1

namespace jak2 {
namespace collide_do_primitives { extern void link(); }
namespace moving_sphere_triangle_intersect { extern void link(); }
namespace calc_animation_from_spr { extern void link(); }
namespace cspace_parented_transformq_joint { extern void link(); }
namespace draw_string_asm { extern void link(); }
namespace get_string_length { extern void link(); }
namespace adgif_shader_texture_with_update { extern void link(); }
namespace debug_line_clip { extern void link(); }
namespace init_boundary_regs { extern void link(); }
namespace render_boundary_tri { extern void link(); }
namespace render_boundary_quad { extern void link(); }
namespace set_sky_vf27 { extern void link(); }
namespace set_sky_vf23_value { extern void link(); }
namespace draw_boundary_polygon { extern void link(); }
namespace particle_adgif { extern void link(); }
namespace sp_launch_particles_var { extern void link(); }
namespace sparticle_motion_blur { extern void link(); }
namespace sp_process_block_2d { extern void link(); }
namespace sp_process_block_3d { extern void link(); }
namespace set_tex_offset { extern void link(); }
namespace draw_large_polygon { extern void link(); }
namespace render_sky_quad { extern void link(); }
namespace render_sky_tri { extern void link(); }
namespace method_16_sky_work { extern void link(); }
namespace method_17_sky_work { extern void link(); }
namespace method_32_sky_work { extern void link(); }
namespace method_33_sky_work { extern void link(); }
namespace method_28_sky_work { extern void link(); }
namespace method_29_sky_work { extern void link(); }
namespace method_30_sky_work { extern void link(); }
namespace method_11_collide_hash { extern void link(); }
namespace method_12_collide_hash { extern void link(); }
namespace fill_bg_using_box_new { extern void link(); }
namespace fill_bg_using_line_sphere_new { extern void link(); }
namespace method_12_collide_mesh { extern void link(); }
namespace method_14_collide_mesh { extern void link(); }
namespace method_15_collide_mesh { extern void link(); }
namespace method_10_collide_edge_hold_list { extern void link(); }
namespace method_19_collide_edge_work { extern void link(); }
namespace method_9_edge_grab_info { extern void link(); }
namespace method_16_collide_edge_work { extern void link(); }
namespace method_17_collide_edge_work { extern void link(); }
namespace method_18_collide_edge_work { extern void link(); }
namespace init_ocean_far_regs { extern void link(); }
namespace draw_large_polygon_ocean { extern void link(); }
namespace render_ocean_quad { extern void link(); }
namespace method_16_ocean { extern void link(); }
namespace method_15_ocean { extern void link(); }
namespace method_14_ocean { extern void link(); }
namespace method_18_grid_hash { extern void link(); }
namespace method_19_grid_hash { extern void link(); }
namespace method_20_grid_hash { extern void link(); }
namespace method_22_grid_hash { extern void link(); }
namespace method_28_sphere_hash { extern void link(); }
namespace method_33_sphere_hash { extern void link(); }
namespace method_29_sphere_hash { extern void link(); }
namespace method_30_sphere_hash { extern void link(); }
namespace method_31_sphere_hash { extern void link(); }
namespace method_32_sphere_hash { extern void link(); }
namespace method_33_spatial_hash { extern void link(); }
namespace method_39_spatial_hash { extern void link(); }
namespace method_36_spatial_hash { extern void link(); }
namespace method_37_spatial_hash { extern void link(); }
namespace method_35_spatial_hash { extern void link(); }
namespace method_10_collide_shape_prim_mesh { extern void link(); }
namespace method_10_collide_shape_prim_sphere { extern void link(); }
namespace method_10_collide_shape_prim_group { extern void link(); }
namespace method_11_collide_shape_prim_mesh { extern void link(); }
namespace method_11_collide_shape_prim_sphere { extern void link(); }
namespace method_11_collide_shape_prim_group { extern void link(); }
namespace method_9_collide_cache_prim { extern void link(); }
namespace method_10_collide_cache_prim { extern void link(); }
namespace method_17_collide_cache { extern void link(); }
namespace method_9_collide_puss_work { extern void link(); }
namespace method_10_collide_puss_work { extern void link(); }
namespace bones_mtx_calc { extern void link(); }
namespace foreground_check_longest_edge_asm { extern void link(); }
namespace foreground_merc { extern void link(); }
namespace add_light_sphere_to_light_group { extern void link(); }
namespace light_hash_add_items { extern void link(); }
namespace light_hash_count_items { extern void link(); }
namespace light_hash_get_bucket_index { extern void link(); }
namespace nav_state_patch_pointers { extern void link(); }
namespace method_45_nav_mesh { extern void link(); }
namespace method_20_nav_engine { extern void link(); }
namespace method_43_nav_mesh { extern void link(); }
namespace nav_dma_send_to_spr_no_flush { extern void link(); }
namespace nav_dma_send_from_spr_no_flush { extern void link(); }
namespace method_17_nav_engine { extern void link(); }
namespace method_39_nav_state { extern void link(); }
namespace method_18_nav_engine { extern void link(); }
namespace method_21_nav_engine { extern void link(); }
namespace setup_blerc_chains_for_one_fragment { extern void link(); }
namespace blerc_execute { extern void link(); }
namespace ripple_execute_init { extern void link(); }
namespace ripple_create_wave_table { extern void link(); }
namespace ripple_apply_wave_table { extern void link(); }
namespace ripple_matrix_scale { extern void link(); }
namespace method_53_squid { extern void link(); }
namespace init_vortex_regs { extern void link(); }
namespace draw_large_polygon_vortex { extern void link(); }
namespace render_vortex_quad { extern void link(); }
namespace foreground_generic_merc { extern void link(); }
namespace generic_merc_init_asm { extern void link(); }
namespace mercneric_convert { extern void link(); }
namespace high_speed_reject { extern void link(); }
namespace generic_translucent { extern void link(); }
namespace generic_merc_query { extern void link(); }
namespace generic_merc_death { extern void link(); }
namespace generic_merc_execute_asm { extern void link(); }
namespace generic_merc_do_chain { extern void link(); }
namespace generic_light_proc { extern void link(); }
namespace generic_envmap_proc { extern void link(); }
namespace generic_prepare_dma_double { extern void link(); }
namespace generic_prepare_dma_single { extern void link(); }
namespace generic_warp_source_proc { extern void link(); }
namespace generic_warp_dest_proc { extern void link(); }
namespace generic_warp_dest { extern void link(); }
namespace generic_warp_envmap_dest { extern void link(); }
namespace generic_no_light_proc { extern void link(); }
namespace foreground_draw_hud { extern void link(); }
namespace shadow_execute { extern void link(); }
namespace shadow_add_double_edges { extern void link(); }
namespace shadow_add_double_tris { extern void link(); }
namespace shadow_add_single_tris { extern void link(); }
namespace shadow_add_single_edges { extern void link(); }
namespace shadow_add_facing_single_tris { extern void link(); }
namespace shadow_add_verts { extern void link(); }
namespace shadow_find_double_edges { extern void link(); }
namespace shadow_find_facing_double_tris { extern void link(); }
namespace shadow_find_single_edges { extern void link(); }
namespace shadow_find_facing_single_tris { extern void link(); }
namespace shadow_init_vars { extern void link(); }
namespace shadow_scissor_top { extern void link(); }
namespace shadow_scissor_edges { extern void link(); }
namespace shadow_calc_dual_verts { extern void link(); }
namespace shadow_xform_verts { extern void link(); }
}

LinkedFunctionTable gLinkedFunctionTable;
Rng gRng;
// jak1+jak2 maps mirrored from mips2c_table.cpp (Gjak2-render); jak3/jakx
// empty (their function TUs are not compiled on arm64).
PerGameVersion<std::unordered_map<std::string, std::vector<void (*)()>>> gMips2CLinkCallbacks = {
    //////// JAK 1
    {{"font", {jak1::draw_string::link}},
     {"sparticle-launcher", {jak1::particle_adgif::link, jak1::sp_launch_particles_var::link}},
     {"sparticle", {jak1::sp_process_block_3d::link, jak1::sp_process_block_2d::link}},
     {"texture", {jak1::adgif_shader_texture_with_update::link}},
     {"sky-tng",
      {jak1::draw_large_polygon::link, jak1::init_sky_regs::link,
       jak1::clip_polygon_against_positive_hyperplane::link, jak1::render_sky_quad::link,
       jak1::render_sky_tri::link, jak1::set_tex_offset::link, jak1::set_sky_vf27::link,
       jak1::set_sky_vf23_value::link}},
     {"load-boundary",
      {jak1::init_boundary_regs::link, jak1::render_boundary_quad::link,
       jak1::render_boundary_tri::link, jak1::draw_boundary_polygon::link}},
     {"tfrag", {jak1::draw_inline_array_tfrag::link, jak1::stats_tfrag_asm::link}},
     {"time-of-day", {jak1::time_of_day_interp_colors_scratch::link}},
     {"collide-func",
      {jak1::collide_do_primitives::link, jak1::moving_sphere_triangle_intersect::link}},
     {"collide-probe", {jak1::collide_probe_node::link, jak1::collide_probe_instance_tie::link}},
     {"collide-mesh",
      {jak1::method_12_collide_mesh::link, jak1::method_11_collide_mesh::link,
       jak1::method_15_collide_mesh::link, jak1::method_14_collide_mesh::link}},
     {"collide-cache",
      {jak1::method_26_collide_cache::link, jak1::method_32_collide_cache::link,
       jak1::pc_upload_collide_frag::link, jak1::method_28_collide_cache::link,
       jak1::method_27_collide_cache::link, jak1::method_29_collide_cache::link,
       jak1::method_12_collide_shape_prim_mesh::link, jak1::method_14_collide_shape_prim_mesh::link,
       jak1::method_13_collide_shape_prim_mesh::link, jak1::method_30_collide_cache::link,
       jak1::method_9_collide_cache_prim::link, jak1::method_10_collide_cache_prim::link,
       jak1::method_10_collide_puss_work::link, jak1::method_9_collide_puss_work::link}},
     {"collide-edge-grab",
      {jak1::method_16_collide_edge_work::link, jak1::method_15_collide_edge_work::link,
       jak1::method_10_collide_edge_hold_list::link, jak1::method_18_collide_edge_work::link}},
     {"joint", {jak1::calc_animation_from_spr::link, jak1::cspace_parented_transformq_joint::link}},
     {"bones",
      {jak1::bones_mtx_calc::link, jak1::draw_bones_merc::link,
       jak1::draw_bones_check_longest_edge_asm::link}},
     {"merc-blend-shape",
      {jak1::blerc_execute::link, jak1::setup_blerc_chains_for_one_fragment::link}},
     {"generic-merc",
      {jak1::generic_merc_init_asm::link, jak1::generic_merc_execute_asm::link,
       jak1::mercneric_convert::link, jak1::high_speed_reject::link}},
     {"generic-effect",
      {jak1::generic_prepare_dma_double::link, jak1::generic_light_proc::link,
       jak1::generic_envmap_proc::link, jak1::generic_prepare_dma_single::link,
       jak1::generic_envmap_dproc::link, jak1::generic_interp_dproc::link,
       jak1::generic_no_light_dproc::link}},
     {"ripple",
      {jak1::ripple_execute_init::link, jak1::ripple_create_wave_table::link,
       jak1::ripple_apply_wave_table::link, jak1::ripple_matrix_scale::link}},
     {"ocean",
      {jak1::init_ocean_far_regs::link, jak1::render_ocean_quad::link,
       jak1::draw_large_polygon_ocean::link}},
     {"ocean-vu0", {jak1::ocean_interp_wave::link, jak1::ocean_generate_verts::link}},
     {"shadow-cpu",
      {jak1::shadow_execute::link, jak1::shadow_add_double_edges::link,
       jak1::shadow_add_double_tris::link, jak1::shadow_add_single_edges::link,
       jak1::shadow_add_facing_single_tris::link, jak1::shadow_add_verts::link,
       jak1::shadow_find_double_edges::link, jak1::shadow_find_facing_double_tris::link,
       jak1::shadow_find_single_edges::link, jak1::shadow_find_facing_single_tris::link,
       jak1::shadow_init_vars::link, jak1::shadow_scissor_top::link,
       jak1::shadow_scissor_edges::link, jak1::shadow_calc_dual_verts::link,
       jak1::shadow_xform_verts::link}},
     {"tie-methods",
      {jak1::draw_inline_array_instance_tie::link,
       jak1::draw_inline_array_prototype_tie_generic_asm::link}},
     {"generic-tie", {jak1::generic_tie_dma_to_spad_sync::link, jak1::generic_tie_convert::link}}},
    /////////// JAK 2
    {{"collide-func",
      {jak2::collide_do_primitives::link, jak2::moving_sphere_triangle_intersect::link}},
     {"joint", {jak2::calc_animation_from_spr::link, jak2::cspace_parented_transformq_joint::link}},
     {"font", {jak2::get_string_length::link, jak2::draw_string_asm::link}},
     {"texture", {jak2::adgif_shader_texture_with_update::link}},
     {"debug",
      {jak2::debug_line_clip::link, jak2::init_boundary_regs::link,
       jak2::render_boundary_quad::link, jak2::render_boundary_tri::link, jak2::set_sky_vf27::link,
       jak2::draw_boundary_polygon::link}},
     {"sparticle-launcher",
      {jak2::particle_adgif::link, jak2::sp_launch_particles_var::link,
       jak2::sparticle_motion_blur::link}},
     {"sparticle", {jak2::sp_process_block_2d::link, jak2::sp_process_block_3d::link}},
     {"sky-tng",
      {jak2::set_tex_offset::link, jak2::draw_large_polygon::link, jak2::render_sky_quad::link,
       jak2::render_sky_tri::link, jak2::method_16_sky_work::link, jak2::method_17_sky_work::link,
       jak2::method_32_sky_work::link, jak2::method_33_sky_work::link,
       jak2::method_28_sky_work::link, jak2::method_29_sky_work::link,
       jak2::method_30_sky_work::link, jak2::set_sky_vf23_value::link}},
     {"collide-hash",
      {jak2::method_11_collide_hash::link, jak2::method_12_collide_hash::link,
       jak2::fill_bg_using_box_new::link, jak2::fill_bg_using_line_sphere_new::link}},
     {"collide-mesh",
      {jak2::method_12_collide_mesh::link, jak2::method_14_collide_mesh::link,
       jak2::method_15_collide_mesh::link}},
     {"collide-edge-grab",
      {jak2::method_10_collide_edge_hold_list::link, jak2::method_19_collide_edge_work::link,
       jak2::method_9_edge_grab_info::link, jak2::method_16_collide_edge_work::link,
       jak2::method_17_collide_edge_work::link, jak2::method_18_collide_edge_work::link}},
     {"ocean-vu0",
      {jak2::method_16_ocean::link, jak2::method_15_ocean::link, jak2::method_14_ocean::link}},
     {"ocean",
      {jak2::init_ocean_far_regs::link, jak2::draw_large_polygon_ocean::link,
       jak2::render_ocean_quad::link}},
     {"spatial-hash",
      {jak2::method_18_grid_hash::link, jak2::method_19_grid_hash::link,
       jak2::method_20_grid_hash::link, jak2::method_22_grid_hash::link,
       jak2::method_28_sphere_hash::link, jak2::method_33_sky_work::link,
       jak2::method_29_sphere_hash::link, jak2::method_30_sphere_hash::link,
       jak2::method_31_sphere_hash::link, jak2::method_32_sphere_hash::link,
       jak2::method_33_spatial_hash::link, jak2::method_39_spatial_hash::link,
       jak2::method_36_spatial_hash::link, jak2::method_37_spatial_hash::link,
       jak2::method_35_spatial_hash::link, jak2::method_33_sphere_hash::link}},
     {"collide-cache",
      {jak2::method_10_collide_shape_prim_mesh::link,
       jak2::method_10_collide_shape_prim_sphere::link,
       jak2::method_10_collide_shape_prim_group::link,
       jak2::method_11_collide_shape_prim_mesh::link,
       jak2::method_11_collide_shape_prim_sphere::link,
       jak2::method_11_collide_shape_prim_group::link, jak2::method_9_collide_cache_prim::link,
       jak2::method_10_collide_cache_prim::link, jak2::method_17_collide_cache::link,
       jak2::method_9_collide_puss_work::link, jak2::method_10_collide_puss_work::link}},
     {"bones", {jak2::bones_mtx_calc::link}},
     {"foreground",
      {jak2::foreground_check_longest_edge_asm::link, jak2::foreground_merc::link,
       jak2::foreground_generic_merc::link, jak2::foreground_draw_hud::link}},
     {"lights",
      {jak2::add_light_sphere_to_light_group::link, jak2::light_hash_add_items::link,
       jak2::light_hash_count_items::link, jak2::light_hash_get_bucket_index::link}},
     {"nav-control", {jak2::method_39_nav_state::link}},
     {"nav-mesh",
      {jak2::nav_state_patch_pointers::link, jak2::method_45_nav_mesh::link,
       jak2::method_20_nav_engine::link, jak2::method_43_nav_mesh::link,
       jak2::nav_dma_send_to_spr_no_flush::link, jak2::nav_dma_send_from_spr_no_flush::link,
       jak2::method_17_nav_engine::link, jak2::method_18_nav_engine::link,
       jak2::method_21_nav_engine::link}},
     {"merc-blend-shape",
      {jak2::setup_blerc_chains_for_one_fragment::link, jak2::blerc_execute::link}},
     {"ripple",
      {jak2::ripple_execute_init::link, jak2::ripple_create_wave_table::link,
       jak2::ripple_apply_wave_table::link, jak2::ripple_matrix_scale::link}},
     {"squid-setup", {jak2::method_53_squid::link}},
     {"vortex",
      {jak2::init_vortex_regs::link, jak2::draw_large_polygon_vortex::link,
       jak2::render_vortex_quad::link}},
     {"generic-merc",
      {jak2::generic_merc_init_asm::link, jak2::mercneric_convert::link,
       jak2::high_speed_reject::link, jak2::generic_translucent::link,
       jak2::generic_merc_query::link, jak2::generic_merc_death::link,
       jak2::generic_merc_execute_asm::link, jak2::generic_merc_do_chain::link}},
     {"generic-effect",
      {jak2::generic_light_proc::link, jak2::generic_envmap_proc::link,
       jak2::generic_prepare_dma_double::link, jak2::generic_prepare_dma_single::link,
       jak2::generic_warp_source_proc::link, jak2::generic_warp_dest_proc::link,
       jak2::generic_warp_dest::link, jak2::generic_warp_envmap_dest::link,
       jak2::generic_no_light_proc::link}},
     {"shadow-cpu",
      {jak2::shadow_execute::link, jak2::shadow_add_double_edges::link,
       jak2::shadow_add_double_tris::link, jak2::shadow_add_single_tris::link,
       jak2::shadow_add_single_edges::link, jak2::shadow_add_facing_single_tris::link,
       jak2::shadow_add_verts::link, jak2::shadow_find_double_edges::link,
       jak2::shadow_find_facing_double_tris::link, jak2::shadow_find_single_edges::link,
       jak2::shadow_find_facing_single_tris::link, jak2::shadow_init_vars::link,
       jak2::shadow_scissor_top::link, jak2::shadow_scissor_edges::link,
       jak2::shadow_calc_dual_verts::link, jak2::shadow_xform_verts::link}}},
    /////////// JAK 3
    {},
    /////////// JAK X
    {}};
// clang-format on

// A37 trampoline arena. reg() runs from klink's per-object callbacks,
// i.e. in the MIDDLE of a DGO link — and on the Android/qemu DGO path a
// global-heap alloc made at that point gets reused by later heap traffic
// (run-9 forensics: the lazily-created noop trampoline emitted at font's
// link was later overwritten by per-frame DMA bucket tags
// 0x20000000/next — BLR into it SIGILLed with fault==pc at 0x190axxx).
// Early-boot allocations (the ~80 a17 FFI trampolines at 0x4dxxxx) are
// proven stable, so the arena (+ the shared noop) is created ONCE at the
// same early point (klink_a11_ensure_pc_mips2c_bound, pre-version-check,
// before any DGO links) and reg() only slices from it.
namespace {
u32 s_a37_arena = 0;
u32 s_a37_arena_used = 0;
u32 s_a37_arena_jak2 = 0;
u32 s_a37_arena_jak2_used = 0;
constexpr u32 kA37TrampSlot = 0x40;
// Gjak2-render: 128 -> 192. jak2 now registers more real builders (sky/
// sparticle/foreground/font/joint families) than the 128-slot arena held
// ('arena exhausted' warnings). This is the same constant for jak1 and jak2,
// so the jak1 arena allocation also grows 128*0x40+16 -> 192*0x40+16 (8KB ->
// 12KB) — harmless headroom, no behavior change for jak1.
constexpr u32 kA37TrampSlots = 192;
u32 a37_shared_noop_offset();
u32 a37_shared_noop_offset_jak2();
}  // namespace

extern "C" void a37_mips2c_prealloc_arena() {
#ifdef __aarch64__
  // Gecho-pool probe arming. TEMPORARY diagnostic, OFF by default. Runs once
  // regardless of the early-return below (env / system property opt-in).
  {
    static bool s_arm_checked = false;
    if (!s_arm_checked) {
      s_arm_checked = true;
      bool arm = false;
      if (std::getenv("OG_ECHO_OOB"))
        arm = true;
#ifdef __ANDROID__
      {
        char b[PROP_VALUE_MAX] = {0};
        if (__system_property_get("debug.opengoal.echo.oob", b) > 0 && b[0] == '1')
          arm = true;
      }
#endif
      if (arm) {
        g_gnd_oob_armed.store(true, std::memory_order_relaxed);
        fprintf(stderr, "GECHO-OOB armed (code-band write watch)\n");
      }
    }
  }
#endif
  if (s_a37_arena || SymbolTable2.offset == 0) {
    return;
  }
  s_a37_arena = ::jak1::alloc_heap_object(s7.offset + jak1_symbols::FIX_SYM_GLOBAL_HEAP,
                                          *(s7 + jak1_symbols::FIX_SYM_FUNCTION_TYPE),
                                          kA37TrampSlot * kA37TrampSlots + 16, UNKNOWN_PP);
  s_a37_arena = (s_a37_arena + 15) & ~15u;
  s_a37_arena_used = 0;
  u32 noop = a37_shared_noop_offset();
  fprintf(stderr, "A37-MIPS2C arena=0x%x (%u slots) noop=0x%x\n", s_a37_arena, kA37TrampSlots,
          noop);
}

extern "C" void a37_mips2c_prealloc_arena_jak2() {
  if (s_a37_arena_jak2 || SymbolTable2.offset == 0) {
    return;
  }
  // jak2 fixed-symbol read idiom: values live at sym_addr-1 (Symbol4::value()),
  // resolved via u32_in_fixed_sym(). Use jak2's own alloc_heap_object with the
  // jak2 FIX_SYM offsets so the -1 adjustment applies (a raw *(s7+off) deref
  // would straddle into the next symbol slot -> garbage type ptr -> SIGSEGV).
  s_a37_arena_jak2 = ::jak2::alloc_heap_object(
      s7.offset + jak2_symbols::FIX_SYM_GLOBAL_HEAP,
      ::jak2::u32_in_fixed_sym(jak2_symbols::FIX_SYM_FUNCTION_TYPE),
      kA37TrampSlot * kA37TrampSlots + 16, UNKNOWN_PP);
  s_a37_arena_jak2 = (s_a37_arena_jak2 + 15) & ~15u;
  s_a37_arena_jak2_used = 0;
  u32 noop = a37_shared_noop_offset_jak2();
  fprintf(stderr, "A37-MIPS2C jak2 arena=0x%x (%u slots) noop=0x%x\n", s_a37_arena_jak2,
          kA37TrampSlots, noop);
}

void LinkedFunctionTable::reg(const std::string& name, u64 (*exec)(void*), u32 stack_size) {
  const auto& it = m_executes.insert({name, {exec, Ptr<u8>()}});
  if (!it.second) {
    lg::error("MIPS2C Function {} is registered multiple times, ignoring later registrations.",
              name);
  }

  // Short GOAL-space stub that jumps into the C++ body via the arm64
  // mips2c helper. Sliced from the early-allocated arena (mid-link heap
  // allocs get reused by later heap traffic on this DGO path — see the
  // arena note above). Per-game (Gjak2-render): each game has its own arena,
  // used-counter, and fallback alloc idiom.
  Ptr<u8> jump_to_asm;
  if (g_game_version == GameVersion::Jak2) {
    if (s_a37_arena_jak2 && s_a37_arena_jak2_used < kA37TrampSlots) {
      jump_to_asm = Ptr<u8>(s_a37_arena_jak2 + s_a37_arena_jak2_used * kA37TrampSlot);
      s_a37_arena_jak2_used++;
    } else {
      fprintf(stderr,
              "A37-MIPS2C WARNING [jak2]: arena %s for %s — falling back to a live heap alloc\n",
              s_a37_arena_jak2 ? "exhausted" : "missing", name.c_str());
      jump_to_asm = Ptr<u8>(::jak2::alloc_heap_object(
          s7.offset + jak2_symbols::FIX_SYM_GLOBAL_HEAP,
          ::jak2::u32_in_fixed_sym(jak2_symbols::FIX_SYM_FUNCTION_TYPE), 0x40, UNKNOWN_PP));
    }
  } else {
    ASSERT(g_game_version == GameVersion::Jak1);
    if (s_a37_arena && s_a37_arena_used < kA37TrampSlots) {
      jump_to_asm = Ptr<u8>(s_a37_arena + s_a37_arena_used * kA37TrampSlot);
      s_a37_arena_used++;
    } else {
      fprintf(stderr, "A37-MIPS2C WARNING: arena %s for %s — falling back to a live heap alloc\n",
              s_a37_arena ? "exhausted" : "missing", name.c_str());
      jump_to_asm = Ptr<u8>(::jak1::alloc_heap_object(
          s7.offset + jak1_symbols::FIX_SYM_GLOBAL_HEAP, *(s7 + jak1_symbols::FIX_SYM_FUNCTION_TYPE),
          0x40, UNKNOWN_PP));
    }
  }
  it.first->second.goal_trampoline = jump_to_asm;

  u8* ptr = jump_to_asm.c();

  {
    // arm64 (contract shared with _mips2c_call_arm64). GOAL passes args in
    // the x86-id registers X7,X6,X2,X1,X8,X9,X10,X11 (see the A6 FFI
    // shuffle comment in game/kernel/jak1/kscheme.cpp), so the trampoline
    // may only touch X12 (caller-saved, never regalloc'd, and saved by
    // call_r64 anyway) and the AAPCS intra-call scratches X16/X17:
    //   0:  ldr x16, +16   ; the C++ exec body
    //   4:  ldr x12, +20   ; the GOAL fake-stack size
    //   8:  ldr x17, +24   ; _mips2c_call_arm64
    //   12: br  x17        ; x30 still holds the GOAL caller's return
    //   16: .quad exec
    //   24: .quad stack_size
    //   32: .quad _mips2c_call_arm64
    const u32 insns[4] = {
        0x58000090,  // ldr x16, pc+16
        0x580000ac,  // ldr x12, pc+20
        0x580000d1,  // ldr x17, pc+24
        0xd61f0220,  // br  x17
    };
    memcpy(ptr, insns, sizeof(insns));
    const u64 lits[3] = {reinterpret_cast<u64>(exec), static_cast<u64>(stack_size),
                         reinterpret_cast<u64>(&_mips2c_call_arm64)};
    memcpy(ptr + 16, lits, sizeof(lits));
    __builtin___clear_cache(reinterpret_cast<char*>(ptr), reinterpret_cast<char*>(ptr) + 0x40);
  }
}

// A37 graded enablement. Flipping the whole jak1 mips2c surface from
// no-ops to real bodies in one step corrupted the kernel heap by frame 1
// (smashed type tags on *temp-string* + the text-name string — the
// A37-FMT-DIAG "~D~S.TXT unknown dest" abort), so real trampolines are
// handed out per-name: names on the allowlist get the real body, the
// rest keep the previous shared-noop behavior (the A29/A32 contract)
// with a loud one-time A37-MIPS2C-FALLBACK log so every still-stubbed
// name is visible in the boot log. Widen the list as bodies are
// validated on-device; the camera chain (A37's goal frame) needs only
// the joint pair.
namespace {
const char* const kA37RealMips2c[] = {
    // A37: the camera-critical joint pair (cspace builds the bone
    // transform othercam copies; calc-animation decompresses the joint
    // animation incl. the bone scale that feeds othercam-calc's fov)...
    "cspace<-parented-transformq-joint!",
    "calc-animation-from-spr",
    // ...plus their direct consumers: with real joints the foreground
    // draw path engages, and noop'd bones bodies fed garbage into the
    // bucket-link math (run-23: GL thread infinite-walking a cyclic
    // chain in SkyRenderer's DmaFollower). The bones triple keeps the
    // foreground DMA well-formed; the A35 renderer name-skips merc
    // buckets it hasn't ported.
    "bones-mtx-calc",
    "draw-bones-merc",
    "draw-bones-check-longest-edge-asm",
    // ...and the sky set: with a REAL camera matrix the sky code leaves
    // the degenerate-camera shallow path (which is all A36 ever
    // exercised) and enters its mips2c leg; noops there feed 0 into the
    // sky chain links and SkyRenderer walks a cyclic chain forever
    // (run-24, same DmaFollower spin with bones enabled).
    "draw-large-polygon",
    "init-sky-regs",
    "clip-polygon-against-positive-hyperplane",
    "render-sky-quad",
    "render-sky-tri",
    "set-tex-offset",
    "set-sky-vf27",
    "set-sky-vf23-value",
    // time-of-day palette interp feeds the sky/tfrag colors each frame.
    "time-of-day-interp-colors-scratch",
};

bool a37_name_is_real(const std::string& name) {
  // A37: the WHOLE registered jak1 surface is real — partial enablement
  // is structurally unsound (with a real camera every still-noop'd body
  // that feeds chain-building returns 0 into DMA links; run-27:
  // sky/tex-5/l0-tfrag buckets all wander to offset 0).
  // Run-28 bisect: all-real reproduces the frame-1 type-tag corruption
  // (*temp-string* + text strings smashed -> "~D~S.TXT unknown dest"
  // abort). Excluding the frame-1 writer below to bisect.
  (void)kA37RealMips2c;
  // Additive bisect base: run-25 set (boots past frame 1) + background
  // half. If the frame-1 abort returns, the corrupter is in this half;
  // else it's in the actor half (collide/shadow/merc/effects/text).
  static const char* const kSet[] = {
      // run-25 base
      "cspace<-parented-transformq-joint!", "calc-animation-from-spr", "bones-mtx-calc",
      "draw-bones-merc", "draw-bones-check-longest-edge-asm", "init-sky-regs", "render-sky-quad",
      "render-sky-tri", "set-sky-vf23-value", "set-sky-vf27", "set-tex-offset",
      "time-of-day-interp-colors-scratch",
      // background quarter (water/boundary excluded this run)
      "draw-inline-array-tfrag", "stats-tfrag-asm", "draw-inline-array-instance-tie",
      "draw-inline-array-prototype-tie-generic-asm", "generic-tie-dma-to-spad-sync",
      "generic-tie-convert", "draw-large-polygon", "clip-polygon-against-positive-hyperplane",
      // A38: the blerc pair. setup-blerc-chains stores the RETURN VALUE of
      // setup-blerc-chains-for-one-fragment into (-> global-buf base); the
      // shared noop returns 0, so the frame dma cursor reset to ZERO every
      // frame and every subsequent append swept GOAL memory from 0 upward
      // at chain rate (~152KB/frame) — the A37-named "float-spray": symbol
      // slots, *temp-string*, the engine-object band and draw-string's
      // code all sat in the walk (font SIGILL at level-hint; l0-tfrag
      // poisoned per frame). Caught by the A38 base-cell trace:
      // pre=0xce6dc0 post=0x0 pc=setup-blerc-chains+0x458 (run-10).
      "blerc-execute", "setup-blerc-chains-for-one-fragment",
      // A41: the texture-path writer. adgif-shader<-texture-with-update!
      // packs tex0/tex1/miptbp (incl. tbp0, the PC texture-pool lookup
      // key) from a texture object into an adgif-shader; every
      // adgif-shader-login* call funnels through it. The shared noop left
      // shaders with tex0=0 — DirectRenderer looked textures up at tbp 0
      // (A40 run-1: "Failed to find texture at 0 ... sky-direct") and
      // every adgif-driven draw went out untextured. Pure GOAL-memory
      // math (no DMA cursor return, unlike the blerc disease) — callers
      // discard the return value.
      "adgif-shader<-texture-with-update!",
      // Gnd: shadow-execute's return is stored into (-> global-buf base) by
      // shadow-execute-all (shadow-cpu.gc:419); the shared no-op returned 0,
      // collapsing the foreground DMA cursor -> bucket-NEXT=0x1a50 -> the ndi
      // ND/Daxter logo's chain is rejected (black) + low-mem stomp. Route it to
      // the real trampoline; its arm64 body is a cursor pass-through (returns
      // a1 unchanged) since the shadow geometry port is incomplete.
      "shadow-execute",
      // Gsprite: the sparticle sprite-DMA builders. The boot SCE "presents"
      // static-screen draws three screen-space sparticle sprites (defpart
      // 2966/2967/2968 -> group-part-screen1); each frame the sparticle system
      // launches them via sp-launch-particles-var and builds their 2D sprite
      // DMA + adgif shaders via sp-process-block-2d / particle-adgif. All four
      // were noop-bound on arm64 (not on this allowlist) -> the sprite bucket
      // stayed empty -> the SCE screen rendered BLACK (Gsce: A35-RENDER
      // draws=1-2 tris=2-4 in the SCE window; x86 has no noop allowlist so it
      // binds the real code and renders). The SCE screen is SCREEN-SPACE 2D, so
      // it needs only the 2D launch path: sp-launch-particles-var (launcher) +
      // sp-process-block-2d (per-frame 2D sprite-DMA builder) + particle-adgif
      // (adgif shader). With the _call_goal8_asm_arm64 C->GOAL arg-shuffle fix
      // these three build the SCE sprites correctly (SCE-window tris 4 -> 354,
      // GSCE-SCE-RENDER fires) and the only mips2c->mips2c edge
      // (sp-launch-particles-var -> particle-adgif) stays inside the set.
      //
      // Gd2: sp-process-block-3d (the 3D WORLD-particle processor) is now ENABLED.
      // It builds the 3D ambient particles / stars AND the group-sun corona/glow
      // (defpart 1950/1951/1952, weather-part.gc:482) — without it the device sun
      // is a bare additive sky-quad "halo" and the 3D particles/stars are absent.
      // It was noop'd because re-enabling it SIGSEGV'd ~frame 190; the documented
      // "wild launcher pointer in block_31" framing was a conflation with the
      // separately-fixed enter-state crash (Gspark-enterstate). The REAL arm64
      // defect is the recurring mips2c `beq reg,s7` #f-guard misfire: this builder
      // skips an INVALID particle via `(-> cpuinfo valid) == #f`, but on arm64 the
      // full-64 compare missed #f (s7=host 0x7f0014fd24 vs the bare-offset field
      // 0x14fd24, proven on-device full=0 lo=1), so invalid slots were processed
      // and their stale `func` (+112) jalr'd = the wild callback. Fixed at the two
      // #f-checks in sparticle.cpp sp_process_block_3d (gpr_addr/low32 compare,
      // arm64-gated). Callees (sp-relaunch-particle-3d / sp-free-particle /
      // quaternion*!) are plain GOAL defun, so no extra mips2c builders are pulled.
      "sp-launch-particles-var", "sp-process-block-2d", "particle-adgif",
      "sp-process-block-3d",
      // Gwater: the ocean DMA builders. The title flythrough flies over
      // Sandover village (village1 has :ocean *ocean-map-village1*,
      // level-info.gc:25); draw-ocean runs every frame (drawable.gc:855) and
      // the PC renderers OceanMidAndFar/OceanNear/CommonOceanRenderer +
      // OceanTexture are registered unconditionally for jak1
      // (OpenGLRenderer.cpp:674/852). But the GOAL ocean code that BUILDS the
      // DMA those renderers consume calls five mips2c builders, all noop-bound
      // on arm64 (logcat: A37-MIPS2C-FALLBACK init-ocean-far-regs /
      // render-ocean-quad / ocean-interp-wave / ocean-generate-verts ->
      // shared noop) -> empty ocean buckets -> wrong/missing water. x86 has no
      // allowlist so it binds the real bodies and the water renders. Same
      // arm64-only divergence class as Gsprite (sparticle), Gnd (shadow), A41
      // (adgif). Enabling, with these properties verified:
      //   * init-ocean-far-regs sets the shared ocean_regs_vfs that
      //     render-ocean-quad reads via copy_vfs_from_other -> they must be
      //     enabled TOGETHER (this is why the family is enabled as a unit).
      //   * none of the five use integer idiv/mod -> no X8/R8 hazard
      //     ([[Gsprite residual]]); ocean-interp-wave is pure bit/VU math,
      //     render path uses VU vdiv / float Q only.
      //   * ocean-generate-verts makes 6 mips2c->GOAL calls (upload-vu0-program,
      //     vu-lights<-light-group!, vector*!) via ExecutionContext::jalr ->
      //     _call_goal8_asm_systemv -> _call_goal8_asm_arm64, the exact
      //     arg-shuffle trampoline Gsprite fixed (asm_funcs_arm64.s:288) -> the
      //     args land in the right GOAL regs. NOT the sp-process-block-3d
      //     failure mode (that was a wild launch-control pointer, not FFI).
      //   * the noop returns are used as a visibility boolean (ocean.gc:103) or
      //     discarded -> the noop only emptied geometry, never corrupted a DMA
      //     cursor (unlike blerc/shadow), so enabling is downside-free.
      // draw-large-polygon-ocean is reached only internally from
      // render-ocean-quad's body (a direct C++ execute() call, not the
      // trampoline), but it is listed for family completeness.
      "init-ocean-far-regs", "render-ocean-quad", "draw-large-polygon-ocean",
      "ocean-interp-wave", "ocean-generate-verts",
      // F1 (Geyser Rock gameplay): the collision query + collide-cache
      // background-mesh-import family. On arm64 these mips2c bodies were
      // noop-bound (logcat: 26x A37-MIPS2C-FALLBACK collide-* /
      // moving-sphere-triangle-intersect -> shared noop, ZERO A37-MIPS2C-REAL).
      // fill-using-bounding-box -> fill-from-background dispatches to the noop'd
      // import methods (load-mesh-from-spad-in-box = (method 26 collide-cache),
      // unpack-background-collide-mesh = m32, puyp-mesh = m30, cache builders
      // m27/m28/m29) -> the collide-cache is filled with ZERO ground triangles ->
      // moving-sphere-triangle-intersect finds no surface -> *target* gets no
      // pat-surface ground and FREE-FALLS through the Geyser Rock floor (device Y
      // 28259 -> -3.5M). x86 has no allowlist, binds the real bodies, and Jak
      // lands + settles (Y 28259 -> 28317). Same arm64-only divergence class as
      // Gsprite (sparticle) / Gwater (ocean). Enabled as a UNIT (cache fill +
      // mesh intersect + probe + edge-grab) since the cache must be both
      // populated AND queried — partial enablement leaves a populated-but-
      // unqueried or queried-but-empty cache.
      "(method 26 collide-cache)", "(method 27 collide-cache)",
      "(method 28 collide-cache)", "(method 29 collide-cache)",
      "(method 30 collide-cache)", "(method 32 collide-cache)",
      "(method 9 collide-cache-prim)", "(method 10 collide-cache-prim)",
      "(method 9 collide-puss-work)", "(method 10 collide-puss-work)",
      "(method 11 collide-mesh)", "(method 12 collide-mesh)",
      "(method 14 collide-mesh)", "(method 15 collide-mesh)",
      "(method 12 collide-shape-prim-mesh)", "(method 13 collide-shape-prim-mesh)",
      "(method 14 collide-shape-prim-mesh)", "(method 15 collide-edge-work)",
      "(method 16 collide-edge-work)", "(method 18 collide-edge-work)",
      "(method 10 collide-edge-hold-list)", "collide-do-primitives",
      "moving-sphere-triangle-intersect", "collide-probe-node",
      "collide-probe-instance-tie", "__pc-upload-collide-frag",
      // Gorb-icon: the generic-merc / generic-effect family. The Precursor ORB
      // HUD/menu icon (money skelgroup) is drawn as a HUD object: its
      // dma-add-func is dma-add-process-drawable-hud, so draw-bones-hud
      // (bones.gc:1408) forces use-mercneric=1 and calls draw-bones-generic-merc
      // (bones.gc:1494) for EVERY HUD merc model. That routes the orb through the
      // generic-merc pipeline, whose 11 mips2c builders were ALL noop-bound on
      // arm64 (absent from this kSet) -> the shared noop returns 0. The
      // generic-merc.gc:88-93 caller round-trips global-buf base through the
      // scratchpad `saves basep`: it stores base to SPAD, calls
      // generic-merc-execute-asm (which must WRITE the advanced cursor back into
      // SPAD), then restores base FROM SPAD. With execute-asm noop'd, SPAD basep
      // stayed 0 -> the orb's generic DMA bucket was never built -> the orb HUD
      // draw never reached the C++ Generic2 do_hud_draws (device BEFORE:
      // GORB HUD count=0 with the FX armed) -> the orb icon is white/missing on
      // device while the world orb (Merc2, not generic-merc) renders fine. x86 has
      // no allowlist so it binds the real bodies and the orb HUD renders. Same
      // arm64-only divergence class as Gsprite/Gwater/Gd2/F1-collision. The C++
      // bodies already exist (generic_merc.cpp / generic_effect.cpp /
      // generic_effect2.cpp, all in CMakeLists). Enabled as a UNIT (the family is
      // self-contained: execute-asm directly ::execute()'s the other 10, and the
      // only external callees are 3 plain GOAL defuns — upload-vu0-program,
      // vector-matrix*!, merc-death-spawn — reached via the proven
      // _call_goal8_asm_arm64 FFI arg-shuffle trampoline that Gsprite/Gwater
      // already exercise). Verified hazard-free: none of the 11 use integer
      // idiv/mod (no X8/R8 drop) and all s7 compares in execute-asm are the
      // self-relative `daddiu reg,s7,8; beq` #t/boolean idiom (operands share s7's
      // upper-32, so the mips2c #f-guard upper-32 misfire class cannot occur).
      "generic-merc-init-asm", "generic-merc-execute-asm", "mercneric-convert",
      "high-speed-reject", "generic-prepare-dma-double", "generic-light-proc",
      "generic-envmap-proc", "generic-prepare-dma-single", "generic-envmap-dproc",
      "generic-interp-dproc", "generic-no-light-dproc",
  };
  for (auto* n : kSet) {
    if (name == n) return true;
  }
  return false;
}

u32 a37_shared_noop_offset() {
  // One no-op GOAL function shared by every still-stubbed name (same
  // shape as the removed a29/a32 noop): returns 0 / #f-as-0.
  static u32 s_cached = 0;
  if (!s_cached) {
    s_cached = ::jak1::make_function_symbol_from_c("__a37-mips2c-noop",
                                                   (void*)+[]() -> u64 { return 0; })
                   .offset;
  }
  return s_cached;
}

bool a37_name_is_real_jak2(const std::string& name) {
  // Gjak2-render graded enablement (jak1 A37 precedent): everything starts
  // on the shared noop; names proven needed+safe get the real trampoline.
  // adgif-shader<-texture-with-update! is the A41-proven texture-shader
  // packer: pure GOAL-memory math, callers discard the return value.
  static const char* const kSetJak2[] = {
      "adgif-shader<-texture-with-update!",
      // Gjak2-render: the render-critical jak2 builders, mirroring the jak1
      // kSet families PROVEN on this device (same arm64-only noop divergence
      // class). Exact registered-name strings from game/mips2c/jak2_functions/
      // *.cpp (.reg("...") calls).
      // --- sky (jak2_functions/sky.cpp) — jak1 precedent: render-sky-quad/tri,
      //     set-sky-vf23-value/vf27, set-tex-offset, draw-large-polygon. Plus
      //     the jak2 sky-work methods that build the sky DMA. ---
      "set-tex-offset", "draw-large-polygon", "render-sky-quad", "render-sky-tri",
      "set-sky-vf23-value", "set-sky-vf27",
      "(method 16 sky-work)", "(method 17 sky-work)", "(method 28 sky-work)",
      "(method 29 sky-work)", "(method 30 sky-work)", "(method 32 sky-work)",
      "(method 33 sky-work)",
      // --- sparticle (jak2_functions/sparticle*.cpp) — jak1 precedent:
      //     Gsprite/Gd2 (2D screen + 3D world particles + sun corona). ---
      "sp-launch-particles-var", "sp-process-block-2d", "sp-process-block-3d",
      "particle-adgif",
      // --- foreground / bones (merc path) (jak2_functions/foreground.cpp,
      //     bones.cpp) — jak1 precedent: draw-bones-* + bones-mtx-calc. HUD
      //     draw (foreground-draw-hud) added too, as jak1's HUD needed it. ---
      "foreground-check-longest-edge-asm", "foreground-merc", "foreground-generic-merc",
      "foreground-draw-hud", "bones-mtx-calc",
      // --- font (jak2_functions/font.cpp) — text (jak1 precedent:
      //     draw-string-asm / get-string-length). ---
      "get-string-length", "get-string-length-asm", "draw-string-asm",
      // --- joint (jak2_functions/joint.cpp) — camera/bones (jak1-proven
      //     family: calc-animation-from-spr + cspace<-parented-transformq-joint!). ---
      "calc-animation-from-spr", "cspace<-parented-transformq-joint!",
      // --- Gjak2-visuals: generic-merc / generic-effect (enable TOGETHER as a
      //     unit; jak1 Gorb-icon precedent). Audited (see phase report): zero
      //     integer div/mod (no X8/R8 hazard); every s7 compare is the
      //     self-relative daddiu reg,s7,4 boolean idiom (no upper-32 #f-guard
      //     misfire); external callees (upload-vu0-program, vector-matrix*!,
      //     merc-death-spawn, dma-bucket-insert-tag, generic-work-init,
      //     generic-warp-source) are plain GOAL defuns via the proven
      //     _call_goal8_asm_arm64 FFI. generic-merc-do-chain ->
      //     generic-merc-execute-asm reaches the rest via direct ::execute().
      //     jak2's SPAD round-trip stores only profiling counters (generic-
      //     merc.gc:87-113), unlike jak1's basep cursor — the old noop only
      //     emptied geometry. Warp names stay in: do-chain jalr's them every
      //     frame (generic-merc.gc:105); the android Warp BUCKET is skipped,
      //     which drops the draws cleanly, but the builders must be real so
      //     the chain's cursor math stays consistent. ---
      "generic-merc-init-asm", "mercneric-convert", "high-speed-reject",
      "generic-translucent", "generic-merc-query", "generic-merc-death",
      "generic-merc-execute-asm", "generic-merc-do-chain",
      "generic-light-proc", "generic-envmap-proc", "generic-prepare-dma-double",
      "generic-prepare-dma-single", "generic-no-light-proc",
      "generic-warp-source-proc", "generic-warp-dest-proc", "generic-warp-dest",
      "generic-warp-envmap-dest",
      // --- Gjak2-visuals: ocean (enable TOGETHER as a unit; jak1 Gwater
      //     precedent). init-ocean-far-regs writes the shared ocean_regs_vfs
      //     that render-ocean-quad reads via copy_vfs_from_other; methods
      //     14/15/16 build the verts/waves the quads consume. Audited: no
      //     integer div/mod; the one mem-loaded #f-guard (ocean.cpp:34,
      //     tod-context sky field) is fixed per-site with the 32-bit gpr_addr
      //     compare; external callees (upload-vu0-program,
      //     vu-lights<-light-group!, (method 52 level), clip-polygon-*) are
      //     plain GOAL via the proven FFI. The former x86-oracle title crash
      //     that held this family back was root-caused to an unrelated
      //     unbound draw-pc-fps-counter call (fixed in jak2 kmachine.cpp). ---
      "init-ocean-far-regs", "draw-large-polygon-ocean", "render-ocean-quad",
      "(method 14 ocean)", "(method 15 ocean)", "(method 16 ocean)",
      // NOTE: jak2 registers no time-of-day mips2c builder (no jak2_functions/
      // time_of_day.cpp) — nothing to add for that family.
      // --- Gjak2-visuals: shadow-cpu (enable ALL 16 TOGETHER — shadow-execute
      //     jalr's every sibling via gLinkedFunctionTable name lookups,
      //     shadow.cpp:2604-2737, so a partial set re-noops the geometry).
      //     ROOT-CAUSE fix, not just a family port: shadow-cpu.gc:704 does
      //     (set! (-> global-buf base) (shadow-execute ...)) — the shared noop
      //     returns 0, so every later packet that frame (vis/fog, camera, sky
      //     input) was appended at ee 0x12c0-band low memory and the chain's
      //     bucket-NEXT went low, which the A42 low-addr quarantine skips =>
      //     ~83% of title frames re-presented STALE chains (frozen clouds
      //     t=990, stale searchlight emissive = the white wash). Proven by the
      //     lowprot tripwire: STR of the shadow-dma-end qwc=6 cnt tag to ee+0,
      //     byte-matched to GAME.CGO object #205 'shadow-cpu'. Audited: zero
      //     integer div/mod; all three s7 compares are symbol/boolean idioms
      //     (no upper-32 gpr_addr misfire); scratchpad via the proven
      //     fake_scratchpad_data idiom; blerc DMA already bounds-guarded
      //     (emulate_dma_bounded); external callees are plain GOAL defuns via
      //     the proven FFI. jak1 precedent covers shadow-execute's cursor
      //     contract; the 15 siblings are first-enabled here (static-audit
      //     clean). SHADOW/SHADOW2 buckets stay SkipRenderer'd on Android for
      //     now — the DMA is built and consumed, nothing draws yet. ---
      "shadow-execute", "shadow-xform-verts", "shadow-calc-dual-verts",
      "shadow-scissor-edges", "shadow-scissor-top", "shadow-init-vars",
      "shadow-find-facing-single-tris", "shadow-find-single-edges",
      "shadow-find-facing-double-tris", "shadow-find-double-edges",
      "shadow-add-verts", "shadow-add-facing-single-tris", "shadow-add-single-edges",
      "shadow-add-single-tris", "shadow-add-double-tris", "shadow-add-double-edges",
      // --- Gjak2-ingame: the collide + spatial-hash query families (enable
      //     TOGETHER as a unit; jak1 F1-collision precedent — same arm64-only
      //     noop divergence class). With these noop'd the collide-cache fills
      //     with ZERO ground triangles -> *target* gets no pat-surface ground
      //     and free-falls through every floor (owner: falls through
      //     everywhere incl. the Fortress spawn). Data-load ruled out:
      //     collide-hash is DGO/bsp-resident (bsp-h.gc:81, linked by
      //     level.gc:207), identical source both arches; fr3 collision is
      //     debug-viz only. Audited (see phase report): zero integer div/mod
      //     (only float div.s in spatial_hash.cpp); scratchpad via the proven
      //     fake_scratchpad_data idiom; the 11 mem-loaded s7 #f-guard compares
      //     in collide_cache/collide_hash/collide_edge_grab fixed per-site
      //     with the 32-bit gpr_addr compare (ocean.cpp:39 idiom); the only
      //     mips2c->mips2c edges (collide-cache -> moving-sphere-triangle-
      //     intersect, collide-func -> collide-do-primitives) stay in-set;
      //     all other callees are plain GOAL defuns via the proven FFI. ---
      "(method 11 collide-hash)", "(method 12 collide-hash)",
      "fill-bg-using-box-new", "fill-bg-using-line-sphere-new",
      "(method 12 collide-mesh)", "(method 14 collide-mesh)", "(method 15 collide-mesh)",
      "moving-sphere-triangle-intersect", "collide-do-primitives",
      "(method 10 collide-edge-hold-list)", "(method 19 collide-edge-work)",
      "(method 9 edge-grab-info)", "(method 16 collide-edge-work)",
      "(method 17 collide-edge-work)", "(method 18 collide-edge-work)",
      "(method 10 collide-shape-prim-mesh)", "(method 10 collide-shape-prim-sphere)",
      "(method 10 collide-shape-prim-group)", "(method 11 collide-shape-prim-mesh)",
      "(method 11 collide-shape-prim-sphere)", "(method 11 collide-shape-prim-group)",
      "(method 9 collide-puss-work)", "(method 10 collide-puss-work)",
      "(method 18 grid-hash)", "(method 19 grid-hash)", "(method 20 grid-hash)",
      "(method 22 grid-hash)",
      // --- Gjak2-ingame attempt 2: these 3 sub-families remain DEFAULT-OFF. With them
      // enabled the device SIGSEGVs at boot right after title-disk-intro links
      // (GK-DIAG sig=11 EE pc 0x1fc2864 / pre-title 0x1c77f40): a GOAL-side consumer
      // reads a garbage offset, and A11-DIAG shows a zeroed symbol slot (0x18d7dc) —
      // an arm64-only OOB WRITE by these bodies (not the #f-guard compare class; those
      // sites are fixed). Ground collision is fully functional without them (prison
      // gameplay verified: find-ground solid, no fall-through). Re-enable for A/B via
      // setprop debug.opengoal.jak2.enable_names (below) once the stomp is fixed. ---
      // "(method 17 collide-cache)",
      // "(method 9 collide-cache-prim)", "(method 10 collide-cache-prim)",
      // "(method 28 sphere-hash)", "(method 29 sphere-hash)", "(method 30 sphere-hash)",
      // "(method 31 sphere-hash)", "(method 32 sphere-hash)", "(method 33 sphere-hash)",
      // "(method 33 spatial-hash)", "(method 35 spatial-hash)", "(method 36 spatial-hash)",
      // "(method 37 spatial-hash)", "(method 39 spatial-hash)",
  };
  // Kill-switch (relaunch-toggleable, no rebuild): setprop
  // debug.opengoal.jak2.noshadowcpu 1 re-noops the shadow-cpu family only.
  // NOTE: with the family noop'd the global-buf base=0 corruption RETURNS —
  // this exists purely for A/B fault isolation.
  static const bool s_no_shadowcpu = []() {
    bool off = false;
#ifdef __ANDROID__
    char b[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.jak2.noshadowcpu", b) > 0 && b[0] == '1') {
      off = true;
    }
#endif
    if (off) {
      fprintf(stderr, "GJ2VIS shadow-cpu mips2c family DISABLED via prop\n");
    }
    return off;
  }();
  if (s_no_shadowcpu && name.rfind("shadow-", 0) == 0) {
    return false;
  }
  // Gjak2-ingame: rebuild-free A/B bisect — setprop debug.opengoal.jak2.noop_names
  // "<tok1>,<tok2>" re-noops every registered name CONTAINING a token (substring
  // match, so "spatial-hash" covers all its methods within PROP_VALUE_MAX's 92
  // bytes; comma-separated).
  static const std::vector<std::string> s_noop_names = []() {
    std::vector<std::string> names;
#ifdef __ANDROID__
    // PROP_VALUE_MAX (92 bytes) caps the comma-separated list — fine for a handful of names.
    char b[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.jak2.noop_names", b) > 0 && b[0] != '\0') {
      fprintf(stderr, "GJ2ING mips2c noop-exclude: %s\n", b);
      std::string raw(b);
      size_t start = 0;
      while (start <= raw.size()) {
        size_t comma = raw.find(',', start);
        if (comma == std::string::npos) {
          names.push_back(raw.substr(start));
          break;
        }
        names.push_back(raw.substr(start, comma - start));
        start = comma + 1;
      }
    }
#endif
    return names;
  }();
  for (const auto& nn : s_noop_names) {
    if (!nn.empty() && name.find(nn) != std::string::npos) {
      return false;
    }
  }
  // Gjak2-ingame attempt 2: inverse of noop_names — setprop
  // debug.opengoal.jak2.enable_names "<tok1>,<tok2>" FORCE-ENABLES every name
  // CONTAINING a token (substring match, comma-separated, PROP_VALUE_MAX capped),
  // even if it is NOT in kSetJak2. Used to re-enable the 3 DEFAULT-OFF sub-families
  // above for on-device A/B isolation once the OOB stomp is fixed. noop_names still
  // takes precedence (it returned false earlier).
  static const std::vector<std::string> s_enable_names = []() {
    std::vector<std::string> names;
#ifdef __ANDROID__
    // PROP_VALUE_MAX (92 bytes) caps the comma-separated list — fine for a handful of names.
    char b[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.jak2.enable_names", b) > 0 && b[0] != '\0') {
      fprintf(stderr, "GJ2ING mips2c force-enable: %s\n", b);
      std::string raw(b);
      size_t start = 0;
      while (start <= raw.size()) {
        size_t comma = raw.find(',', start);
        if (comma == std::string::npos) {
          names.push_back(raw.substr(start));
          break;
        }
        names.push_back(raw.substr(start, comma - start));
        start = comma + 1;
      }
    }
#endif
    return names;
  }();
  for (auto* n : kSetJak2) { if (name == n) return true; }
  for (const auto& en : s_enable_names) {
    if (!en.empty() && name.find(en) != std::string::npos) {
      return true;
    }
  }
  return false;
}

u32 a37_shared_noop_offset_jak2() {
  static u32 s_cached = 0;
  if (!s_cached) {
    s_cached = ::jak2::make_function_symbol_from_c("__a37-mips2c-noop",
                                                   (void*)+[]() -> u64 { return 0; })
                   .offset;
  }
  return s_cached;
}
}  // namespace

u32 LinkedFunctionTable::get(const std::string& name) {
  auto it = m_executes.find(name);
  const bool is_jak2 = (g_game_version == GameVersion::Jak2);
  const bool is_real = is_jak2 ? a37_name_is_real_jak2(name) : a37_name_is_real(name);
  const u32 noop = is_jak2 ? a37_shared_noop_offset_jak2() : a37_shared_noop_offset();
  if (it == m_executes.end() || !is_real) {
    static std::unordered_map<std::string, bool> s_logged;
    if (!s_logged[name]) {
      s_logged[name] = true;
      if (is_jak2) {
        fprintf(stderr, "A37-MIPS2C-FALLBACK [jak2] %s -> shared noop (%s)\n", name.c_str(),
                it == m_executes.end() ? "not registered" : "not on allowlist yet");
      } else {
        fprintf(stderr, "A37-MIPS2C-FALLBACK %s -> shared noop (%s)\n", name.c_str(),
                it == m_executes.end() ? "not registered" : "not on allowlist yet");
      }
    }
    return noop;
  }
  static std::unordered_map<std::string, bool> s_logged_real;
  if (!s_logged_real[name]) {
    s_logged_real[name] = true;
    if (is_jak2) {
      fprintf(stderr, "A37-MIPS2C-REAL [jak2] %s -> arm64 trampoline 0x%x\n", name.c_str(),
              it->second.goal_trampoline.offset);
    } else {
      fprintf(stderr, "A37-MIPS2C-REAL %s -> arm64 trampoline 0x%x\n", name.c_str(),
              it->second.goal_trampoline.offset);
    }
  }
  return it->second.goal_trampoline.offset;
}
}  // namespace Mips2C
