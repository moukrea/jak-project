// A37 (autoport) — real Mips2C table backend for the arm64 builds
// (Android + linux-arm64/qemu), jak1 only.
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
#include "game/runtime.h"

extern "C" {
void _mips2c_call_arm64();
}

#ifdef __aarch64__
#include <atomic>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#ifdef __ANDROID__
#include <android/log.h>
#endif
// Gnd OOB write-watch globals + reporter. Defined in this arm64-only TU
// because it is linked into android libgk.so via --whole-archive (the desktop
// mips2c_table.cpp is not part of the android android_kernel archive). The
// mips2c store helpers in mips2c_private.h call gnd_oob_check -> gnd_oob_report.
std::atomic<bool> g_gnd_oob_armed{true};
__attribute__((noinline)) void gnd_oob_report(char kind, unsigned int target,
                                              unsigned long long lo, unsigned long long hi,
                                              int nbytes) {
  static std::atomic<int> s_n{0};
  int n = s_n.fetch_add(1);
  if (n >= 400) return;  // cap log flood
  void* ra0 = __builtin_return_address(0);
  void* ra1 = __builtin_return_address(1);
  void* ra2 = __builtin_return_address(2);
  Dl_info info;
  void* base = nullptr;
  if (dladdr(ra0, &info)) base = info.dli_fbase;
  unsigned long o0 = base ? (unsigned long)((char*)ra0 - (char*)base) : (unsigned long)ra0;
  unsigned long o1 = base ? (unsigned long)((char*)ra1 - (char*)base) : (unsigned long)ra1;
  unsigned long o2 = base ? (unsigned long)((char*)ra2 - (char*)base) : (unsigned long)ra2;
#ifdef __ANDROID__
  __android_log_print(ANDROID_LOG_FATAL, "opengoal-gk",
      "GND-OOB-WRITE kind=%c target=0x%x val=0x%016llx%016llx nb=%d ra0=0x%lx ra1=0x%lx ra2=0x%lx base=%p",
      kind, target, hi, lo, nbytes, o0, o1, o2, base);
#else
  fprintf(stderr, "GND-OOB-WRITE kind=%c target=0x%x val=0x%016llx%016llx nb=%d ra0=0x%lx ra1=0x%lx ra2=0x%lx\n",
      kind, target, hi, lo, nbytes, o0, o1, o2);
#endif
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

LinkedFunctionTable gLinkedFunctionTable;
Rng gRng;
// jak1 map mirrored from mips2c_table.cpp; jak2/jak3/jakx empty (their
// function TUs are not compiled on arm64).
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
    {},
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
constexpr u32 kA37TrampSlot = 0x40;
constexpr u32 kA37TrampSlots = 128;
u32 a37_shared_noop_offset();
}  // namespace

extern "C" void a37_mips2c_prealloc_arena() {
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

void LinkedFunctionTable::reg(const std::string& name, u64 (*exec)(void*), u32 stack_size) {
  const auto& it = m_executes.insert({name, {exec, Ptr<u8>()}});
  if (!it.second) {
    lg::error("MIPS2C Function {} is registered multiple times, ignoring later registrations.",
              name);
  }

  // Short GOAL-space stub that jumps into the C++ body via the arm64
  // mips2c helper. Sliced from the early-allocated arena (mid-link heap
  // allocs get reused by later heap traffic on this DGO path — see the
  // arena note above). Only jak1 runs on the arm64 builds.
  ASSERT(g_game_version == GameVersion::Jak1);
  Ptr<u8> jump_to_asm;
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
}  // namespace

u32 LinkedFunctionTable::get(const std::string& name) {
  auto it = m_executes.find(name);
  if (it == m_executes.end() || !a37_name_is_real(name)) {
    static std::unordered_map<std::string, bool> s_logged;
    if (!s_logged[name]) {
      s_logged[name] = true;
      fprintf(stderr, "A37-MIPS2C-FALLBACK %s -> shared noop (%s)\n", name.c_str(),
              it == m_executes.end() ? "not registered" : "not on allowlist yet");
    }
    return a37_shared_noop_offset();
  }
  static std::unordered_map<std::string, bool> s_logged_real;
  if (!s_logged_real[name]) {
    s_logged_real[name] = true;
    fprintf(stderr, "A37-MIPS2C-REAL %s -> arm64 trampoline 0x%x\n", name.c_str(),
            it->second.goal_trampoline.offset);
  }
  return it->second.goal_trampoline.offset;
}
}  // namespace Mips2C
