/*!
 * @file vulkan.cpp
 * Gvulkan-option: a minimal, selectable Vulkan renderer backend for the desktop build.
 *
 * SCOPE / HONEST LIMITATION
 * -------------------------
 * This module proves the Vulkan SURFACE + PRESENT path using SDL3's SDL_gpu abstraction (which uses
 * the Vulkan backend on Linux/Android). When the "VULKAN RENDERER" Graphics Options toggle is on, the
 * runtime selects this module instead of OpenGL: it creates a real Vulkan device + swapchain and
 * clears+presents a frame each render iteration, keeping the GOAL engine ticking (so the game boots to
 * "link finish: logo" under Vulkan and the window is a live Vulkan-cleared surface).
 *
 * It does NOT yet render the GAME geometry. The ~47k-line OpenGL bucket-renderer pipeline
 * (game/graphics/opengl_renderer/*) is written directly against OpenGL and has not been ported to
 * Vulkan (which also requires translating every GLSL shader to SPIR-V). Until that port lands, the
 * game's DMA render chain (send_chain) is intentionally not consumed here. So selecting "Vulkan"
 * currently yields a working Vulkan present of a cleared frame, not the scene — this is the deferred
 * bulk of the Vulkan effort, and the report labels it as such.
 *
 * The frame-sync handshake (sync_cv + frame_idx, vk_vsync waiting for render() to bump the counter)
 * mirrors the OpenGL module (game/graphics/pipelines/opengl.cpp) so the engine advances one frame per
 * present. The display subclass supplies a real DisplayManager + InputManager bound to a live SDL
 * window, which is required for Display::GetMainDisplay() to return non-null and drive render().
 */

#include "vulkan.h"

#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "game/graphics/display.h"
#include "game/graphics/gfx.h"
#include "game/runtime.h"

#include "common/log/log.h"
#include "common/util/Timer.h"

#include "third-party/SDL/include/SDL3/SDL.h"
#include "third-party/SDL/include/SDL3/SDL_gpu.h"

namespace {

// Minimal cross-thread frame-sync state shared between the game-thread module functions (vk_vsync)
// and the render-thread present (VkGpuDisplay::render). Mirrors the OpenGL module's sync_cv/frame_idx
// handshake so the engine advances exactly one frame per present.
struct VkGpuData {
  std::mutex sync_mutex;
  std::condition_variable sync_cv;
  u64 frame_idx = 0;
  SDL_GPUDevice* device = nullptr;
};

std::unique_ptr<VkGpuData> g_vk_data;

class VkGpuDisplay : public GfxDisplay {
 public:
  VkGpuDisplay(SDL_Window* window, SDL_GPUDevice* device, bool is_main)
      : m_window(window),
        m_device(device),
        m_display_manager(std::make_shared<DisplayManager>(window)),
        m_input_manager(std::make_shared<InputManager>(window)) {
    m_main = is_main;
    m_display_manager->set_input_manager(m_input_manager);
  }

  ~VkGpuDisplay() override {
    if (m_device && m_window) {
      SDL_ReleaseWindowFromGPUDevice(m_device, m_window);
    }
    // The SDL_GPUDevice itself is owned by the module (destroyed in vk_exit).
    if (m_window) {
      SDL_DestroyWindow(m_window);
      m_window = nullptr;
    }
  }

  std::shared_ptr<DisplayManager> get_display_manager() const override { return m_display_manager; }
  std::shared_ptr<InputManager> get_input_manager() const override { return m_input_manager; }
  void init_splash() override {}
  void draw_splash(int /*fb_w*/, int /*fb_h*/) override {}

  void render() override {
    // Pump SDL events so the window stays responsive and window-close works. (This is the minimum of
    // GLDisplay::process_sdl_events; full controller/keyboard binding is not wired for this
    // clear-only path — gameplay input is not needed to prove the Vulkan present.)
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT ||
          (event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED &&
           event.window.windowID == SDL_GetWindowID(m_window))) {
        m_should_quit = true;
      }
    }
    // Drain the game's EE-side display/input requests so the engine doesn't stall on them.
    m_display_manager->process_ee_events();
    m_input_manager->process_ee_events();

    // Present a Vulkan-cleared frame via SDL_gpu.
    SDL_GPUCommandBuffer* cmdbuf = SDL_AcquireGPUCommandBuffer(m_device);
    if (cmdbuf) {
      SDL_GPUTexture* swapchain_tex = nullptr;
      Uint32 sw = 0, sh = 0;
      if (SDL_WaitAndAcquireGPUSwapchainTexture(cmdbuf, m_window, &swapchain_tex, &sw, &sh) &&
          swapchain_tex) {
        SDL_GPUColorTargetInfo color_target = {};
        color_target.texture = swapchain_tex;
        color_target.clear_color = SDL_FColor{0.08f, 0.02f, 0.16f, 1.0f};  // distinct "Vulkan" tint
        color_target.load_op = SDL_GPU_LOADOP_CLEAR;
        color_target.store_op = SDL_GPU_STOREOP_STORE;
        SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(cmdbuf, &color_target, 1, nullptr);
        // No draw calls yet: the game geometry pipeline is not ported to Vulkan (see file header).
        SDL_EndGPURenderPass(pass);
      }
      SDL_SubmitGPUCommandBuffer(cmdbuf);
    }

    // Publish a measured fps so the GOAL on-screen counter reads a sane value on this backend too.
    {
      static Timer s_fps_timer;
      static float s_fps_smoothed_dt = 1.f / 60.f;
      float dt = s_fps_timer.getSeconds();
      s_fps_timer.start();
      if (dt > 0.f) {
        s_fps_smoothed_dt = (0.9f * s_fps_smoothed_dt) + (0.1f * dt);
      }
      Gfx::g_global_settings.measured_fps =
          (s_fps_smoothed_dt > 0.f) ? (1.f / s_fps_smoothed_dt) : 0.f;
    }

    // Toggle even/odd and wake the engine waiting on vk_vsync (mirror opengl.cpp present tail).
    {
      std::unique_lock<std::mutex> lock(g_vk_data->sync_mutex);
      g_vk_data->frame_idx++;
      g_vk_data->sync_cv.notify_all();
    }

    if (m_should_quit) {
      std::unique_lock<std::mutex> lock(g_vk_data->sync_mutex);
      MasterExit = RuntimeExitStatus::EXIT;
      g_vk_data->sync_cv.notify_all();
    }
  }

 private:
  SDL_Window* m_window = nullptr;
  SDL_GPUDevice* m_device = nullptr;
  std::shared_ptr<DisplayManager> m_display_manager;
  std::shared_ptr<InputManager> m_input_manager;
  bool m_should_quit = false;
};

int vk_init(GfxGlobalSettings& /*settings*/) {
  SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");
  if (!SDL_Init(SDL_INIT_VIDEO)) {
    lg::error("[Vulkan] Could not initialize SDL: {}", SDL_GetError());
    return 1;
  }
  lg::info("[Vulkan] SDL video initialized for the Vulkan (SDL_gpu) backend.");
  return 0;
}

std::shared_ptr<GfxDisplay> vk_make_display(int width,
                                            int height,
                                            const char* title,
                                            GfxGlobalSettings& /*settings*/,
                                            GameVersion /*version*/,
                                            bool is_main) {
  SDL_Window* window = SDL_CreateWindow(title, width, height,
                                        SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if (!window) {
    lg::error("[Vulkan] Could not create window: {}", SDL_GetError());
    return nullptr;
  }

  SDL_GPUDevice* device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_SPIRV, /*debug_mode=*/false,
                                              /*name=*/nullptr);
  if (!device) {
    lg::error("[Vulkan] SDL_CreateGPUDevice failed ({}). A Vulkan-capable driver is required.",
              SDL_GetError());
    SDL_DestroyWindow(window);
    return nullptr;
  }
  if (!SDL_ClaimWindowForGPUDevice(device, window)) {
    lg::error("[Vulkan] SDL_ClaimWindowForGPUDevice failed: {}", SDL_GetError());
    SDL_DestroyGPUDevice(device);
    SDL_DestroyWindow(window);
    return nullptr;
  }
  lg::info("[Vulkan] SDL_gpu device up (driver: {}). NOTE: game geometry is not yet ported to Vulkan; "
           "this backend presents a cleared surface only.",
           SDL_GetGPUDeviceDriver(device));

  g_vk_data = std::make_unique<VkGpuData>();
  g_vk_data->device = device;

  auto display = std::make_shared<VkGpuDisplay>(window, device, is_main);
  return std::static_pointer_cast<GfxDisplay>(display);
}

void vk_exit() {
  if (g_vk_data) {
    if (g_vk_data->device) {
      SDL_DestroyGPUDevice(g_vk_data->device);
      g_vk_data->device = nullptr;
    }
    g_vk_data.reset();
  }
}

// Wait for the next present. Returns 0/1 (even/odd frame). Called from the game thread on a GOAL stack.
u32 vk_vsync() {
  if (!g_vk_data) {
    return 0;
  }
  std::unique_lock<std::mutex> lock(g_vk_data->sync_mutex);
  auto init_frame = g_vk_data->frame_idx;
  g_vk_data->sync_cv.wait(lock, [=] {
    return (MasterExit != RuntimeExitStatus::RUNNING) || g_vk_data->frame_idx > init_frame;
  });
  return g_vk_data->frame_idx & 1;
}

u32 vk_sync_path() {
  return 0;
}

// Gvulkan-option: the game's DMA render chain is intentionally NOT consumed — the OpenGL bucket
// renderers are not yet ported to Vulkan, so there is no game geometry to draw. The window still
// presents a cleared Vulkan frame each iteration (see VkGpuDisplay::render).
void vk_send_chain(const void* /*data*/, u32 /*offset*/) {}

void vk_texture_upload_now(const u8* /*tpage*/, int /*mode*/, u32 /*s7_ptr*/) {}
void vk_texture_relocate(u32 /*destination*/, u32 /*source*/, u32 /*format*/) {}
void vk_set_levels(const std::vector<std::string>& /*levels*/) {}
void vk_set_active_levels(const std::vector<std::string>& /*levels*/) {}
void vk_set_pmode_alp(float /*val*/) {}

}  // namespace

const GfxRendererModule gRendererVulkan = {
    vk_init,                // init
    vk_make_display,        // make_display
    vk_exit,                // exit
    vk_vsync,               // vsync
    vk_sync_path,           // sync_path
    vk_send_chain,          // send_chain
    vk_texture_upload_now,  // texture_upload_now
    vk_texture_relocate,    // texture_relocate
    vk_set_levels,          // set_levels
    vk_set_active_levels,   // set_active_levels
    vk_set_pmode_alp,       // set_pmode_alp
    GfxPipeline::Vulkan,    // pipeline
    "Vulkan (SDL_gpu)"      // name
};
