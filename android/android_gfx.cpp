// Phase A35 (autoport): Android graphics pipeline glue. See android_gfx.h.

#include "android_gfx.h"

#include <android/log.h>
#include <dlfcn.h>

#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>

#include <SDL3/SDL.h>

#include "common/dma/dma_copy.h"
#include "common/goal_constants.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/loader/Loader.h"
#include "game/graphics/texture/TexturePool.h"
#include "game/runtime.h"

#include "android_opengl_renderer.h"

#include "third-party/glad/include/glad/glad.h"

// A38 float-spray tripwire arm/rearm (gk_android_main.cpp). One relaxed
// atomic load per frame when the debug property is unset. chain_phase=1
// when called with a rendered chain (the property-"1" arm point).
extern "C" void gk_a38_tripwire_frame_hook(int chain_phase);

namespace android_gfx {
namespace {
constexpr const char* kLogTag = "opengoal-gk";

struct AndroidGfxData {
  // ONE mutex for the whole game-thread<->GL-thread handshake. A37: the
  // previous split (sync_mutex for vsync/post_swap_tick, dma_mutex for
  // send_chain/sync_path) had sync_cv waited under dma_mutex in
  // sync_path() but notified under sync_mutex — a condition_variable
  // used with two different mutexes is UB and loses wakeups; on-device
  // the GOAL thread parked forever in sync_path's cond_wait the moment
  // frame contents got heavier (real mips2c joints), and the desynced
  // frame pacing corrupted the in-flight chain. One mutex, two cvs.
  std::mutex dma_mutex;
  std::condition_variable sync_cv;
  u64 frame_idx = 0;
  u64 frame_idx_of_input_data = 0;

  // dma chain hand-off (same mutex)
  std::condition_variable dma_cv;
  bool has_data_to_render = false;
  const void* chain_data = nullptr;
  u32 chain_offset = 0;

  // A42: upstream's run_dma_copy mode, always-on for Android. Zero-copy
  // hand-off let concurrent writers (run-3: bucket tags walking to 0x0
  // mid-frame, 40 A37-BUCKET-MALFORMED skips, then a renderer drain hang +
  // OOM kill) mutate the chain under the GL thread. The copy is taken on
  // the game thread inside send_chain — the builder is idle there, so the
  // tag stream is complete and stable — and is immutable afterwards, which
  // makes the GL-side A37 probe decisive instead of racy.
  FixedChunkDmaCopier dma_copier{EE_MAIN_MEM_SIZE};

  std::shared_ptr<TexturePool> texture_pool;
  std::shared_ptr<Loader> loader;
  std::unique_ptr<AndroidOpenGLRenderer> renderer;

  std::atomic<float> pmode_alp{1.f};
  std::atomic<u64> frames_rendered{0};
};

AndroidGfxData* g_data = nullptr;
void flush_pending_texture_calls_on_ready();  // A41 queue, defined below
std::atomic<bool> g_renderer_ready{false};
// A42: the IOP vblank hook (desktop gfx.cpp's file-static vsync_callback).
// Set once by make_iop_thread (EE thread, during InitMachine — strictly
// before the dispatcher thread that calls vsync() exists), invoked from
// vsync() on the dispatcher thread. Same lock-free shape as desktop.
std::function<void()> g_vsync_callback;
std::atomic<u32> g_chains_received{0};
std::atomic<u32> g_chains_dropped_pre_init{0};
std::atomic<int> g_window_w{0};
std::atomic<int> g_window_h{0};
std::atomic<int> g_refresh_rate{0};

}  // namespace

bool get_window_size(int* w, int* h) {
  int ww = g_window_w.load();
  int hh = g_window_h.load();
  if (ww <= 0 || hh <= 0) {
    return false;
  }
  if (w) {
    *w = ww;
  }
  if (h) {
    *h = hh;
  }
  return true;
}

int get_refresh_rate() {
  return g_refresh_rate.load();
}

bool init_renderer_on_gl_thread(int win_w, int win_h) {
  if (g_renderer_ready.load()) {
    return true;
  }

  // Resolve every GL entry point through SDL (EGL/dlsym on Android). The
  // desktop renderer code calls gl* through glad's pointers; GLES 3.2
  // provides the full surface the ported subset uses (verified: no
  // glPolygonMode/glLogicOp/glClipControl on Android paths).
  if (!gladLoadGLLoader((GLADloadproc)SDL_GL_GetProcAddress)) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "A35-RENDER gladLoadGLLoader failed — no GL entry points; "
                        "staying on clear/swap loop");
    return false;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "A35-RENDER glad loaded GL entry points via SDL_GL_GetProcAddress "
                      "(GL_VERSION=%s)",
                      (const char*)glGetString(GL_VERSION));

  // A36: the desktop-profile glad parses "OpenGL ES 3.2" as version 3.2 and
  // skips its GL_VERSION_4_1 load list — which is where the ES2-core
  // functions (glClearDepthf, glDepthRangef, ...) live in desktop GL. They
  // stay NULL and the first call is a BLR-to-0 (run-19/20: SIGSEGV pc=0 from
  // android_renderer_run's clear). Resolve that family directly; dlsym
  // fallback for drivers whose eglGetProcAddress skips core names.
  {
    auto resolve = [](const char* name) -> void* {
      void* p = (void*)SDL_GL_GetProcAddress(name);
      if (!p) {
        static void* libgles = dlopen("libGLESv2.so", RTLD_NOW | RTLD_GLOBAL);
        if (libgles) {
          p = dlsym(libgles, name);
        }
      }
      return p;
    };
    if (!glad_glClearDepthf) {
      glad_glClearDepthf = (PFNGLCLEARDEPTHFPROC)resolve("glClearDepthf");
    }
    if (!glad_glDepthRangef) {
      glad_glDepthRangef = (PFNGLDEPTHRANGEFPROC)resolve("glDepthRangef");
    }
    if (!glad_glGetShaderPrecisionFormat) {
      glad_glGetShaderPrecisionFormat =
          (PFNGLGETSHADERPRECISIONFORMATPROC)resolve("glGetShaderPrecisionFormat");
    }
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "A36-RENDER GL4.1-list ES core fns resolved: glClearDepthf=%p "
                        "glDepthRangef=%p",
                        (void*)glad_glClearDepthf, (void*)glad_glDepthRangef);
    if (!glad_glClearDepthf || !glad_glDepthRangef) {
      __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                          "A36-RENDER missing core GLES entry points after fallback");
      return false;
    }
  }

  g_window_w.store(win_w);
  g_window_h.store(win_h);
  {
    auto display = SDL_GetPrimaryDisplay();
    const SDL_DisplayMode* mode = display ? SDL_GetCurrentDisplayMode(display) : nullptr;
    g_refresh_rate.store(mode && mode->refresh_rate > 0 ? (int)mode->refresh_rate : 60);
  }

  auto* data = new AndroidGfxData();
  data->texture_pool = std::make_shared<TexturePool>(GameVersion::Jak1);

  // fr3 dir: <project>/out/jak1/fr3 — LoaderActivity extracts the APK's
  // fr3/ assets (GAME.fr3 + intro/title) there. Loader handles a missing
  // level file by logging; a missing GAME.fr3 would fail load_common, so
  // probe first and run textureless (placeholders) instead of aborting.
  auto fr3_dir = file_util::get_jak_project_dir() / "out" / "jak1" / "fr3";
  if (fs::exists(fr3_dir / "GAME.fr3")) {
    data->loader = std::make_shared<Loader>(fr3_dir, jak1::LEVEL_TOTAL);
  } else {
    __android_log_print(ANDROID_LOG_WARN, kLogTag,
                        "A35-RENDER %s/GAME.fr3 missing — common textures will be "
                        "checkerboard placeholders",
                        fr3_dir.string().c_str());
  }

  data->renderer = std::make_unique<AndroidOpenGLRenderer>(data->texture_pool, data->loader);

  g_data = data;
  g_renderer_ready.store(true);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "A35-RENDER renderer ready (window %dx%d) — game DMA chains will "
                      "now be consumed",
                      win_w, win_h);
  // A41: land the boot-time tpage uploads + font relocates that were
  // queued while the renderer was coming up (see the queue note above).
  flush_pending_texture_calls_on_ready();
  return true;
}

bool renderer_ready() {
  return g_renderer_ready.load();
}

bool render_frame_on_gl_thread(int win_w, int win_h) {
  if (!g_renderer_ready.load()) {
    return false;
  }
  auto* d = g_data;

  g_window_w.store(win_w);
  g_window_h.store(win_h);

  bool got_chain = false;
  {
    std::unique_lock<std::mutex> lock(d->dma_mutex);
    got_chain = d->dma_cv.wait_for(lock, std::chrono::milliseconds(40),
                                   [=] { return d->has_data_to_render; });
  }

  // A37 chain validator: a malformed (cyclic / never-ending) chain makes
  // bucket renderers spin forever in read_and_advance (run-23/24/25: GL
  // thread stuck in SkyRenderer, GOAL parked in sync_path, app frozen).
  // Walk the whole chain with a step cap first; on cap, log a tag window
  // and SKIP the frame — the run keeps producing evidence and pacing.
  if (got_chain) {
    DmaFollower probe(d->chain_data, d->chain_offset);
    constexpr int kMaxSteps = 400000;
    int steps = 0;
    u32 last_offsets[8] = {0};
    while (!probe.ended() && steps < kMaxSteps) {
      last_offsets[steps & 7] = probe.current_tag_offset();
      probe.read_and_advance();
      steps++;
    }
    if (!probe.ended()) {
      static u32 s_loops_logged = 0;
      if (s_loops_logged < 8) {
        s_loops_logged++;
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A37-CHAIN-LOOP frame chain did not end after %d steps; recent tag "
                            "offsets: 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x",
                            kMaxSteps, last_offsets[(steps + 0) & 7], last_offsets[(steps + 1) & 7],
                            last_offsets[(steps + 2) & 7], last_offsets[(steps + 3) & 7],
                            last_offsets[(steps + 4) & 7], last_offsets[(steps + 5) & 7],
                            last_offsets[(steps + 6) & 7], last_offsets[(steps + 7) & 7]);
        for (int k = 0; k < 4; k++) {
          u32 off = last_offsets[(steps + 7 - k) & 7];
          u64 tag = 0, tag2 = 0;
          memcpy(&tag, (const u8*)d->chain_data + off, 8);
          memcpy(&tag2, (const u8*)d->chain_data + off + 8, 8);
          __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                              "A37-CHAIN-LOOP tag@0x%x = %016llx %016llx", off,
                              (unsigned long long)tag, (unsigned long long)tag2);
        }
      }
      std::unique_lock<std::mutex> lock(d->dma_mutex);
      d->has_data_to_render = false;
      d->sync_cv.notify_all();
      return false;
    }
  }

  // A38: property "2" arms at the first GL tick (boot-time writers).
  gk_a38_tripwire_frame_hook(0);

  if (got_chain) {
    // A38: arm (first chain, property-gated) / rearm (per frame) the
    // float-spray tripwire on the engine-object band. Arming at the first
    // RENDERED chain (not the first GL tick) keeps the boot-link phase
    // unwatched — DGO linking writes the band legitimately.
    gk_a38_tripwire_frame_hook(1);
    {
      std::unique_lock<std::mutex> lock(d->dma_mutex);
      d->frame_idx_of_input_data = d->frame_idx;
    }
    AndroidRenderOptions options;
    options.game_res_w = Gfx::g_global_settings.game_res_w;
    options.game_res_h = Gfx::g_global_settings.game_res_h;
    if (options.game_res_w <= 0 || options.game_res_h <= 0) {
      options.game_res_w = 640;
      options.game_res_h = 480;
    }
    options.window_fb_w = win_w;
    options.window_fb_h = win_h;
    // lbox dims come from GOAL via pc-set-letterbox; left at defaults they
    // letterbox the 640x480 game into the window center. If GOAL never set
    // them, scale the draw region to fit the window while keeping aspect.
    options.draw_region_w = Gfx::g_global_settings.lbox_w;
    options.draw_region_h = Gfx::g_global_settings.lbox_h;
    if (options.draw_region_w <= 640 && options.draw_region_h <= 480 && win_h > 0) {
      // GOAL still on defaults — fit 4:3 into the window honestly.
      int fit_h = win_h;
      int fit_w = (fit_h * 4) / 3;
      if (fit_w > win_w) {
        fit_w = win_w;
        fit_h = (fit_w * 3) / 4;
      }
      options.draw_region_w = fit_w;
      options.draw_region_h = fit_h;
    }
    options.pmode_alp_register = d->pmode_alp.load();

    d->renderer->render(DmaFollower(d->chain_data, d->chain_offset), options);

    const auto& st = d->renderer->stats();
    const u64 n = d->frames_rendered.fetch_add(1) + 1;
    if (n <= 5 || (n % 60) == 0 || st.buckets_skipped > 0) {
      static u32 s_last_logged_skips = 0;
      if (n <= 5 || (n % 60) == 0 || st.buckets_skipped != s_last_logged_skips) {
        s_last_logged_skips = st.buckets_skipped;
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "A35-RENDER frame=%llu chain_bytes=%u buckets_drawn=%u skipped=%u "
                            "draws=%u tris=%u",
                            (unsigned long long)st.frame_idx, st.chain_bytes, st.buckets_drawn,
                            st.buckets_skipped, st.draw_calls, st.triangles);
      }
    }
  }

  // mark the chain rendered (desktop render_game_frame parity).
  {
    std::unique_lock<std::mutex> lock(d->dma_mutex);
    d->has_data_to_render = false;
    d->sync_cv.notify_all();
  }
  return got_chain;
}

void post_swap_tick() {
  if (!g_renderer_ready.load()) {
    return;
  }
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  d->frame_idx++;
  d->sync_cv.notify_all();
}

// A40: entry/exit counters for the GOAL-thread-facing shims. The A40-DPROC
// probe prints them at 1 Hz — they discriminate "display-loop iterates but
// aborts between syncv and the send" from "display-loop is never resumed"
// without any GOAL-side instrumentation. Plain atomics; zero cost when the
// probe property is off (nothing reads them).
std::atomic<u64> g_a40_vsync_entry{0};
std::atomic<u64> g_a40_vsync_exit{0};
std::atomic<u64> g_a40_syncpath_entry{0};
std::atomic<u64> g_a40_syncpath_exit{0};

void set_vsync_callback(std::function<void()> f) {
  g_vsync_callback = std::move(f);
}

u32 vsync() {
  g_a40_vsync_entry.fetch_add(1, std::memory_order_relaxed);
  // A42, desktop gfx.cpp:119-124 parity: tell the IOP kernel we're vsyncing
  // so it dispatches the overlord's VBlank_Handler (SoundIopInfo DMA →
  // *sound-iop-info* strpos / fake VAG clock — the pacing source for every
  // spooled cutscene). Fires before the renderer-ready gate: desktop fires
  // it on every Gfx::vsync() call regardless of renderer state.
  if (g_vsync_callback) {
    static bool s_a42_logged = false;
    if (!s_a42_logged) {
      s_a42_logged = true;
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "A42-VBLANK vsync->IOP vblank callback live (overlord "
                          "VBlank_Handler will pace str-pos from here on)");
    }
    // Pre-renderer-ready there is no swap chain to block on and the GOAL
    // syncv path free-runs (~270 Hz observed) — clamp vblank delivery to
    // 60 Hz there so the IOP fake VAG clock (1024/target_fps per vblank)
    // stays real-time. Post-ready, vsync() blocks on the swap chain and
    // every call is a real frame, desktop cadence.
    bool fire = true;
    if (!g_renderer_ready.load()) {
      static std::chrono::steady_clock::time_point s_last_vblank{};
      auto now = std::chrono::steady_clock::now();
      if (s_last_vblank.time_since_epoch().count() != 0 &&
          now - s_last_vblank < std::chrono::microseconds(16600)) {
        fire = false;
      } else {
        s_last_vblank = now;
      }
    }
    if (fire) {
      g_vsync_callback();
    }
  }
  if (!g_renderer_ready.load()) {
    g_a40_vsync_exit.fetch_add(1, std::memory_order_relaxed);
    return 0;
  }
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  auto init_frame = d->frame_idx_of_input_data;
  d->sync_cv.wait(lock, [=] {
    return (MasterExit != RuntimeExitStatus::RUNNING) || d->frame_idx > init_frame;
  });
  g_a40_vsync_exit.fetch_add(1, std::memory_order_relaxed);
  return d->frame_idx & 1;
}

u32 sync_path() {
  g_a40_syncpath_entry.fetch_add(1, std::memory_order_relaxed);
  if (!g_renderer_ready.load()) {
    g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
    return 0;
  }
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  if (!d->has_data_to_render) {
    g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
    return 0;
  }
  d->sync_cv.wait(lock, [=] { return !d->has_data_to_render; });
  g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
  return 0;
}

void send_chain(const void* data, u32 offset) {
  const u32 n = g_chains_received.fetch_add(1) + 1;
  if (!g_renderer_ready.load()) {
    const u32 dropped = g_chains_dropped_pre_init.fetch_add(1) + 1;
    if (dropped == 1) {
      __android_log_print(ANDROID_LOG_WARN, kLogTag,
                          "A35-RENDER send_chain before renderer init — dropping until the GL "
                          "thread finishes bring-up (counted, not silent)");
    }
    return;
  }
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  if (d->has_data_to_render) {
    lg::error("A35-RENDER send_chain called with pending data (frame pacing bug?)");
    return;
  }
  if (n == 1 || (n % 600) == 0) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag, "A35-RENDER send_chain #%u offset=0x%x", n,
                        offset);
  }
  // A42: bounded pre-probe of the live chain, then copy (see dma_copier
  // field note). FixedChunkDmaCopier::run has an unbounded walk + a
  // LOW_PROTECT assert, so a malformed live chain must be caught here —
  // skip the frame instead of hanging/aborting the game thread.
  {
    DmaFollower probe(data, offset);
    constexpr int kMaxSteps = 400000;
    int steps = 0;
    bool low_tag = false;
    while (!probe.ended() && steps < kMaxSteps) {
      auto tag = probe.current_tag();
      if (tag.addr != 0 && tag.addr <= EE_MAIN_MEM_LOW_PROTECT) {
        low_tag = true;
        break;
      }
      probe.read_and_advance();
      steps++;
    }
    if (!probe.ended() || low_tag) {
      static u32 s_precopy_logged = 0;
      if (s_precopy_logged < 8) {
        s_precopy_logged++;
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A42-CHAIN-PRECOPY malformed live chain at send (steps=%d low_tag=%d "
                            "off=0x%x) — frame skipped before copy",
                            steps, (int)low_tag, probe.current_tag_offset());
      }
      return;
    }
  }
  const auto& chain_copy = d->dma_copier.run(data, offset);
  d->chain_data = chain_copy.data.data();
  d->chain_offset = chain_copy.start_offset;
  d->has_data_to_render = true;
  d->dma_cv.notify_all();
}

namespace {
// A41: dropping pre-ready texture calls loses them FOREVER — unlike frame
// chains, they are one-shot. On device the GOAL boot races GL bring-up:
// GAME.CGO's tpage logins (InitMachine, which runs on the SDL thread
// BEFORE android_renderer_run can bring the renderer up) and the
// dispatcher thread's setup-font-texture! upload+relocate all fire before
// renderer-ready (A40 run-1: first send_chain dropped at 10.127s, ready at
// 10.782s), so the font texture never entered the pool and DirectRenderer
// missed at slot 14720 (=0xe6000/64, the relocated 24pt font) every frame
// — the untextured text quads. Desktop never sees this because GL init
// precedes the GOAL kernel. Blocking the caller was tried first and
// deadlocks: the link-time calls run ON the SDL thread, upstream of the
// renderer bring-up they would wait for (A41 run-1: boot parked in
// InitMachine, zero A35-RENDER lines). So: queue pre-ready calls in FIFO
// order and flush them the moment the renderer is up. Both pool ops are
// GL-free and pool-mutex'd — safe from any thread. Upload entries keep the
// GOAL tpage pointer; the texture-page objects live in the global heap and
// nothing unloads them in the ~1s window before the flush (each replay is
// logged so a future violation names itself).
struct PendingTexCall {
  bool is_relocate;
  std::vector<TexturePool::PrecomputedUpload> upload_entries;  // parsed at call time
  u32 dst, src, format;
};
std::mutex g_pending_tex_mutex;        // ordering: take BEFORE the pool mutex
std::vector<PendingTexCall> g_pending_tex_calls;
bool g_pending_tex_flushed = false;

// Parse an upload-now call into slot-link entries WHILE the GOAL page is
// alive. Read-side mirror of TexturePool::handle_upload_now (same mode →
// segment rules, same name construction); pure GOAL-memory reads, no pool,
// no GL — callable on the game thread before the renderer exists. Run-2
// proved replay-by-pointer is unsound: setup-font-texture! kicks the font
// page right after relocating it, so by flush time the queued pointer read
// reused heap and the font's source slot (0x2786) was never linked —
// relocate ASSERT'd 'src' and SIGABRT'd the boot.
std::vector<TexturePool::PrecomputedUpload> snapshot_upload(const u8* tpage,
                                                            int mode,
                                                            u32 s7_ptr) {
  std::vector<TexturePool::PrecomputedUpload> out;
  GoalTexturePage texture_page;
  memcpy(&texture_page, tpage, sizeof(GoalTexturePage));

  bool has_segment[3] = {true, true, true};
  if (mode == -1) {
  } else if (mode == 2) {
    has_segment[0] = false;
    has_segment[1] = false;
  } else if (mode == -2) {
    has_segment[2] = false;
  } else if (mode == 0) {
    has_segment[1] = false;
    has_segment[2] = false;
  } else {
    // handle_upload_now logs and skips these modes; mirror that.
    __android_log_print(ANDROID_LOG_WARN, kLogTag, "A41-TEX snapshot skipping mode %d", mode);
    return out;
  }

  auto goal_str = [&](u32 ptr) -> const char* {
    return ptr == 0 ? "" : (const char*)(g_ee_main_mem + ptr + 4);
  };

  for (int tex_idx = 0; tex_idx < texture_page.length; tex_idx++) {
    GoalTexture tex;
    if (texture_page.try_copy_texture_description(&tex, tex_idx, g_ee_main_mem, tpage, s7_ptr)) {
      for (int mip_idx = 0; mip_idx < tex.num_mips; mip_idx++) {
        if (has_segment[tex.segment_of_mip(mip_idx)]) {
          TexturePool::PrecomputedUpload e;
          e.id = PcTextureId(texture_page.id, tex_idx);
          e.name = std::string(goal_str(texture_page.name_ptr)) + goal_str(tex.name_ptr);
          e.dest = tex.dest[mip_idx];
          out.push_back(std::move(e));
        }
      }
    }
  }
  return out;
}

void run_tex_call(const PendingTexCall& c) {
  if (c.is_relocate) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag, "A41-TEX relocate dst=0x%x src=0x%x fmt=%u",
                        c.dst, c.src, c.format);
    g_data->texture_pool->relocate(c.dst, c.src, c.format);
  } else {
    static u32 s_upload_count = 0;
    const u32 n = ++s_upload_count;
    if (n <= 8 || (n % 100) == 0) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag, "A41-TEX upload #%u (%zu slot links)", n,
                          c.upload_entries.size());
    }
    g_data->texture_pool->handle_upload_precomputed(c.upload_entries);
  }
}

// Pre: g_pending_tex_mutex held, g_renderer_ready true.
void drain_pending_tex_calls_locked() {
  if (g_pending_tex_flushed) {
    return;
  }
  g_pending_tex_flushed = true;
  if (!g_pending_tex_calls.empty()) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "A41-TEX flushing %zu queued pre-ready texture calls (boot-order race)",
                        g_pending_tex_calls.size());
    for (const auto& c : g_pending_tex_calls) {
      run_tex_call(c);
    }
    g_pending_tex_calls.clear();
    g_pending_tex_calls.shrink_to_fit();
  }
}

void enqueue_or_run_tex_call(const PendingTexCall& c) {
  std::unique_lock<std::mutex> lk(g_pending_tex_mutex);
  if (!g_renderer_ready.load()) {
    static u32 s_queued_logged = 0;
    if (++s_queued_logged <= 8) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "A41-TEX queueing pre-ready %s #%u (renderer not up yet)",
                          c.is_relocate ? "relocate" : "upload-now", s_queued_logged);
    }
    g_pending_tex_calls.push_back(c);
    return;
  }
  drain_pending_tex_calls_locked();  // FIFO: anything queued runs first
  run_tex_call(c);
}

void flush_pending_texture_calls_on_ready() {
  std::unique_lock<std::mutex> lk(g_pending_tex_mutex);
  drain_pending_tex_calls_locked();
}
}  // namespace

void texture_upload_now(const u8* tpage, int mode, u32 s7_ptr) {
  // TexturePool::handle_upload_now / handle_upload_precomputed do no GL —
  // they link tpage slots to loader-provided textures (or placeholders)
  // under the pool lock. Safe from the game thread, exactly like desktop
  // gl_texture_upload_now. The page walk happens HERE, while the GOAL page
  // object is guaranteed alive (see snapshot_upload).
  PendingTexCall c{};
  c.is_relocate = false;
  c.upload_entries = snapshot_upload(tpage, mode, s7_ptr);
  enqueue_or_run_tex_call(c);
}

void texture_relocate(u32 dst, u32 src, u32 format) {
  // Rare (jak1: the four font planes at boot). Logged on execute — dst is
  // the pool slot DirectRenderer will look up (font: 0x3800/0x3980).
  PendingTexCall c{};
  c.is_relocate = true;
  c.dst = dst;
  c.src = src;
  c.format = format;
  enqueue_or_run_tex_call(c);
}

void set_pmode_alp(float val) {
  if (!g_renderer_ready.load()) {
    return;
  }
  g_data->pmode_alp.store(val);
}

namespace {
void mod_set_levels(const std::vector<std::string>& levels) {
  if (g_renderer_ready.load() && g_data->loader) {
    g_data->loader->set_want_levels(levels);
  }
}

void mod_set_active_levels(const std::vector<std::string>& levels) {
  if (g_renderer_ready.load() && g_data->loader) {
    g_data->loader->set_active_levels(levels);
  }
}

const GfxRendererModule gRendererAndroid = {
    [](GfxGlobalSettings&) -> int { return 0; },  // init (GL init happens on the SDL thread)
    [](int, int, const char*, GfxGlobalSettings&, GameVersion,
       bool) -> std::shared_ptr<GfxDisplay> { return nullptr; },  // make_display (SDL thread owns)
    []() {},                                                      // exit
    vsync,                                                        // vsync
    sync_path,                                                    // sync_path
    send_chain,                                                   // send_chain
    texture_upload_now,                                           // texture_upload_now
    texture_relocate,                                             // texture_relocate
    mod_set_levels,                                               // set_levels
    mod_set_active_levels,                                        // set_active_levels
    set_pmode_alp,                                                // set_pmode_alp
    GfxPipeline::OpenGL,                                          // pipeline
    "Android GLES 3.2"                                            // name
};
}  // namespace

const GfxRendererModule* renderer_module() {
  return &gRendererAndroid;
}

}  // namespace android_gfx

// A40: shim-counter snapshot for the gk_android_main.cpp 1 Hz probe.
// out[0..5] = vsync_entry, vsync_exit, sync_path_entry, sync_path_exit,
// chains_received, chains_dropped_pre_init.
extern "C" void gk_a40_shim_counters(unsigned long long out[6]) {
  using namespace android_gfx;
  out[0] = g_a40_vsync_entry.load(std::memory_order_relaxed);
  out[1] = g_a40_vsync_exit.load(std::memory_order_relaxed);
  out[2] = g_a40_syncpath_entry.load(std::memory_order_relaxed);
  out[3] = g_a40_syncpath_exit.load(std::memory_order_relaxed);
  out[4] = g_chains_received.load(std::memory_order_relaxed);
  out[5] = g_chains_dropped_pre_init.load(std::memory_order_relaxed);
}
