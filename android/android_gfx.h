// Phase A35 (autoport): Android graphics pipeline glue.
//
// The Android mirror of game/graphics/pipelines/opengl.cpp's gl_* surface:
// the game (dispatcher) thread hands DMA chains / texture uploads / vsync
// waits in through gRendererAndroid (returned by Gfx::GetCurrentRenderer()
// on Android), and the SDL/GL thread consumes them once per swap via
// render_frame_on_gl_thread(). Same mutex/cv handshake as desktop:
//
//   game thread:  send_chain → has_data_to_render=1 → sync_path waits for 0
//                 syncv waits for frame_idx to advance
//   GL thread:    waits ≤40 ms for has_data_to_render, renders the chain,
//                 clears the flag, swaps, frame_idx++
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>

#include "common/common_types.h"

struct GfxRendererModule;

namespace android_gfx {

// Gspeed: stable-grid engine game-clock published by the GL render loop and read
// by the EE frame-clock timer (a35_read_ee_timer). See definitions/notes in
// android_gfx.cpp. g_gspeed_clock_ticks is in bus-ticks (get-bus-clock/256
// units), advanced by (step-0.5)*9765 per rendered frame; active once the
// renderer's stable-rate lock is running.
extern std::atomic<unsigned long long> g_gspeed_clock_ticks;
extern std::atomic<bool> g_gspeed_clock_active;

// GL-thread side ------------------------------------------------------------
// Called once after SDL_GL_MakeCurrent succeeded. Loads GL entry points via
// SDL_GL_GetProcAddress (glad), builds TexturePool + Loader +
// AndroidOpenGLRenderer. Returns false (and logs why) if any step fails —
// the caller then keeps the bare clear/swap loop.
bool init_renderer_on_gl_thread(int win_w, int win_h);
bool renderer_ready();

// One frame: waits up to 40 ms for a chain from the game thread and renders
// it. Returns true when a chain was rendered into the window framebuffer;
// false when no chain arrived (caller then draws its own idle clear). The
// caller swaps either way.
bool render_frame_on_gl_thread(int win_w, int win_h);

// After SDL_GL_SwapWindow: advance frame_idx and wake syncv waiters.
void post_swap_tick();

// game-thread side ----------------------------------------------------------
// A42: desktop Gfx::vsync() (gfx.cpp:119) invokes a registered callback
// before pacing so the IOP kernel gets a vblank every frame — runtime.cpp
// wires it to IOP_Kernel::signal_vblank → overlord VBlank_Handler →
// SoundIopInfo DMA, the str-pos / fake-VAG-clock source that paces every
// spooled anim. Android's Gfx::register_vsync_callback shim used to
// DISCARD the callback: *sound-iop-info* strpos stayed -1 and every spool
// aborted at the 4 s str-pos<=0 timeout (the title course collapsed before
// village1 could stay displayed). Storage lives here; the Gfx:: shims in
// android_runtime_compat.cpp forward.
void set_vsync_callback(std::function<void()> f);
u32 vsync();
u32 sync_path();
void send_chain(const void* data, u32 offset);
void texture_upload_now(const u8* tpage, int mode, u32 s7_ptr);
void texture_relocate(u32 dst, u32 src, u32 format);
void set_pmode_alp(float val);

// Window/display facts for the pc-* GOAL helpers (kmachine surface).
// Both return false when the GL thread hasn't measured them yet —
// callers then skip the write, desktop "no display" semantics.
bool get_window_size(int* w, int* h);
int get_refresh_rate();  // 0 when unknown

// The renderer module Gfx::GetCurrentRenderer() returns on Android.
const GfxRendererModule* renderer_module();

}  // namespace android_gfx
