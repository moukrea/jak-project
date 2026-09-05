// Phase A35 (autoport): Android graphics pipeline glue. See android_gfx.h.

#include "android_gfx.h"

#include <android/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/system_properties.h>

#include <chrono>
#include <condition_variable>
#include <cstdio>  // supervisor-diag: snprintf for jak2 breadcrumb line
#include <cstdlib>
#include <cstring>  // A36-GLGATED: strlen when building the still-NULL list
#include <functional>
#include <memory>
#include <mutex>
#include <thread>

#include <SDL3/SDL.h>

#include "common/dma/dma_copy.h"
#include "common/goal_constants.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/util/rss_census.h"

#include "game/mips2c/spart_prof.h"

#include "game/graphics/gfx.h"
#include "game/graphics/render_pace.h"
#include "game/graphics/opengl_renderer/GpuCaps.h"
#include "game/graphics/opengl_renderer/loader/ManagedAssets.h"
#include "game/graphics/opengl_renderer/loader/Loader.h"
#include "game/graphics/texture/TexturePool.h"
#include "game/runtime.h"

#include "android_opengl_renderer.h"

#include "third-party/glad/include/glad/glad.h"

// A38 float-spray tripwire arm/rearm (gk_android_main.cpp). One relaxed
// atomic load per frame when the debug property is unset. chain_phase=1
// when called with a rendered chain (the property-"1" arm point).
extern "C" void gk_a38_tripwire_frame_hook(int chain_phase);
// Gcine-pose joint-sanity tripwire: per-frame bucket of cspace joint skips /
// bad bone matrices (defined in game/mips2c/jak1_functions/joint.cpp).
extern "C" void gpose_joint_frame_tick(unsigned long long frame_idx);

// supervisor-diag: jak2 remote-diagnostic breadcrumb (defined in gk_android_main.cpp).
// No-op unless the running game is jak2 and the ext files dir is known; used here to
// record A35-RENDER frame stats into the owner's no-adb jak2_diag.txt.
extern "C" void gk_jak2_diag_line(const char* text);

// Default internal 3D render scale (% of the 640x480 GOAL game_res, 4:3) when
// debug.opengoal.render.scale is unset. 120% = 768x576: the on-device sweet
// spot from the fps-vs-resolution sweep — the HIGHEST 4:3 internal resolution
// that holds the baseline stable 30fps (time-ratio 2) on BOTH measured scenes
// (Geyser Rock, the tighter/heavier-fill case, and village1). It is a modest
// (1.2x linear / 1.44x pixels) but real sharpness gain with no fps regression
// and no broken effects. Higher is genuinely NOT free here: Geyser Rock is
// already at the 2-vblank boundary at 640x480 (render ~21ms of a 33ms budget),
// so fill-rate bites immediately above ~120% — 200% (1280x960) drops to ~20fps
// (ratio 3). Owners who prefer maximum crispness over framerate can raise the
// prop (e.g. 200 for 1280x960 @ ~20fps); owners who hit a heavier untested
// scene that regresses can drop to 100 (the original 640x480). Range 25..400.
// DEFAULT = 100 (original 640x480, neutral). The 120%/768x576 "sweet spot" above
// is device-SPECIFIC (Adreno 618) — per the owner, internal resolution must be a
// user-facing OPTION (graphics-options backlog: native-detect + a per-aspect-ratio
// resolution ladder + a render-scale %), NOT a hardcoded per-device default.
//
// BATCH 2 (autoport): the user-facing RENDER SCALE menu option is now the real
// control. It scales the GOAL game_res in update-to-os (pckernel-common.gc), which
// flows into Gfx::g_global_settings.game_res_w/h (options.game_res_w/h below). With
// the default (100) prop, render_scale_pct stays 100 here so the menu setting is
// applied EXACTLY ONCE (no double-scaling). debug.opengoal.render.scale remains a
// DEV-ONLY override that multiplies ON TOP of the menu setting (25..400).
#ifndef RENDER_SCALE_DEFAULT
#define RENDER_SCALE_DEFAULT 100
#endif

// Gmatch: known-good snapshot of the GOAL kernel asm-func return-from-thread-dead
// (the per-process return trampoline at GOAL 0x18aee4). Published here by the
// render-thread content canary (below) and CONSUMED by gk_android_main.cpp's
// SIGILL handler, which repairs-and-resumes when the kernel-dispatch thread RETs
// into a (re-)stomped trampoline — a race the per-frame canary alone cannot win.
// Set exactly once (malloc'd, never freed); a plain pointer read in the handler
// is safe (null until armed, valid forever after).
extern "C" {
unsigned char* g_gmatch_rftd_good = nullptr;     // known-good bytes, or null
// Widened from the original return-from-thread-dead point (0x18aee4/0x80) to the
// whole kernel asm-func code band [0x18ae84, 0x1912b4): the merc blend-shape
// stomp's residual kernel-code hits scatter across this region (observed
// victims: 0x18ae84 return-from-thread, 0x191210/0x191218/0x191240
// process::deactivate). The bounded blerc emulate (common/dma/dma.h) stops the
// PRIMARY high-heap scatter; this band canary + the gk_android_main.cpp SIGILL
// resume handler (which derives its window from these two constants) catch any
// residual kernel-code stomp so the cutscene plays through. Pure code region, so
// snapshot+restore-each-frame is safe. x86 unaffected (#ifdef __aarch64__).
unsigned int g_gmatch_rftd_goal = 0x18ae84;       // GOAL addr of protected region
unsigned int g_gmatch_rftd_len = 0x6430;          // length in bytes -> [0x18ae84,0x1912b4)
}

// Gcine-camfov: the Gintro DMA chain-walk dump (GINTRO-CHAINWALK / GND-PRECOPY-RAW)
// is a per-frame ~14-line render-thread debug flood that has outlived its purpose.
// It runs latency-heavy __android_log_print calls every frame during the new-game
// intro's complex DMA chains — exactly the window where the (separate) blend-shape
// joint OOB stomp races the render thread — so it widens that race AND floods long
// captures. Gate it OFF by default; re-arm with `setprop debug.opengoal.gintro.dbg 1`.
static bool gintro_chainwalk_dbg() {
  static const bool s_on = [] {
    char buf[PROP_VALUE_MAX] = {0};
    return __system_property_get("debug.opengoal.gintro.dbg", buf) > 0 && buf[0] == '1';
  }();
  return s_on;
}

#if defined(__aarch64__) && defined(__ANDROID__)
// GND-HWWP: one-shot arm of the arm64 HARDWARE data watchpoint on the two
// global-buf base fields (gk_android_main.cpp). Called from the GOAL thread.
extern "C" void gnd_hwwp_arm_once();
#endif

namespace android_gfx {
namespace {
constexpr const char* kLogTag = "opengoal-gk";

// Gperf-particles (round 2): GOAL/GL overlap mode. When ON (default), the GOAL
// kernel thread is released to build frame N+1 as soon as the GL thread PICKS UP
// chain N (chains_picked_up >= chains_sent), instead of waiting for the
// post-swap frame_idx bump — restoring the EE/GS overlap the original hardware
// had. sync_path also returns immediately: its "renderer consumed the chain"
// meaning only mattered for buffer reuse, and send_chain deep-copies the chain
// (dma_copier), so the engine's builder buffers are free the moment send_chain
// returns. The GOAL thread then builds frame N+1 during the GL render of N and
// blocks in send_chain's gate (wait !has_data_to_render, i.e. render N done)
// before overwriting chain_data — that gate is UNCONDITIONAL so a live kill-
// switch flip mid-render can never overwrite a chain the consumer still reads.
// Polled from a system property on the GL thread (same cadence as render.scale).
// Kill switch: `setprop debug.opengoal.perf.nooverlap 1` -> ON=false -> original
// serialized post-swap predicate + blocking sync_path.
std::atomic<bool> g_perf_overlap{true};

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
  // Gperf-particles overlap accounting (same mutex): chains handed to
  // send_chain vs chains the GL thread has picked up for rendering. vsync()
  // in overlap mode waits picked_up >= sent — i.e. "my last chain has started
  // rendering" — which is the moment GOAL may safely build the next frame.
  u64 chains_sent = 0;
  u64 chains_picked_up = 0;

  // dma chain hand-off (same mutex)
  std::condition_variable dma_cv;
  bool has_data_to_render = false;
  const void* chain_data = nullptr;
  u32 chain_offset = 0;
  // Gintro: set once the first chain has been copied, so a corrupt frame can
  // re-present the last good copy (chain_data/chain_offset persist between
  // frames — they point into dma_copier's buffer, overwritten only by run()).
  bool ever_copied = false;

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
// cutscene-npc-flicker (essai 11) : les deux rejets de chaine DMA que le thread GL ne peut pas
// dessiner — tous les modeles de l'image disparaissent une image (re-presentation A42) ou le
// GOAL attend une image de plus (A37). Cumuls non plafonnes, lus par scene par le recensement
// (gk_npc_chain_health_counters, en bas de ce fichier) ; les `static` locaux plafonnes a 8/40
// lignes de journal restent ce qu'ils etaient.
std::atomic<u32> g_a42_precopy_total{0};
std::atomic<u32> g_a37_chain_loops_total{0};
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
  rss_census::mark("gl-contexte");

    // Grecharged-managed-assets: with a live context, record which compressed
    // formats this GPU really supports so the asset manager can pick (and the
    // next launch can upgrade) the right pack profile.
    gpu_caps::detect();
    managed_assets::record_detected_profile(gpu_caps::preferred_profile());

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
    // Grecharged-managed-assets — LE CORRECTIF EST POSE AU PRODUCTEUR, PLUS
    // FONCTION PAR FONCTION.
    // Ce defaut a ete paye TROIS FOIS, une entree a la fois : glClearDepthf /
    // glDepthRangef (A36), glVertexAttribDivisor (F1a), et glTexStorage2D
    // (fusion de la branche des assets geres — premier appelant de l'arbre,
    // mort a la premiere texture geree). La cause est unique et ne bouge pas :
    // glad range chaque entree par VERSION DE GL DE BUREAU, lit
    // "OpenGL ES 3.2" comme 3.2, et saute integralement toutes ses listes
    // au-dessus. Une entree qui est CORE en GLES mais rangee par glad dans une
    // liste > 3.2 reste donc NULL, et son premier appel est un BLR vers 0.
    //
    // La table ci-dessous n'est pas une liste choisie a la main : c'est la
    // sortie EXHAUSTIVE de `.autoport/gl_entrypoint_audit.py`, qui croise tous
    // les symboles gl* references sous game/, common/ et android/ avec la
    // liste de chargement de glad. Toute entree qui apparait dans cette sortie
    // et pas ici est un crash qui attend son premier appelant : relancer le
    // script quand du code GL neuf atterrit.
    struct GatedEntry {
      void** slot;
      const char* name;
    };
    const GatedEntry gated[] = {
        // liste glad 3.3 — ES 3.0 core (instanciation du renderer de sprites)
        {(void**)&glad_glVertexAttribDivisor, "glVertexAttribDivisor"},
        // liste glad 4.0 — ES 3.2 core (tessellation ; Shader.cpp tente en plus
        // les suffixes EXT/OES si le pilote n'exporte pas le nom nu)
        {(void**)&glad_glPatchParameteri, "glPatchParameteri"},
        // liste glad 4.1 — ES 2.0 core
        {(void**)&glad_glClearDepthf, "glClearDepthf"},
        {(void**)&glad_glDepthRangef, "glDepthRangef"},
        {(void**)&glad_glGetShaderPrecisionFormat, "glGetShaderPrecisionFormat"},
        // liste glad 4.2 — ES 3.0 core (stockage immuable ; les textures KTX2
        // du pack gere passent par la, et c'est CE slot qui valait 0)
        {(void**)&glad_glTexStorage2D, "glTexStorage2D"},
        // liste glad 4.3 — ES 3.2 core (KHR_debug)
        {(void**)&glad_glDebugMessageCallback, "glDebugMessageCallback"},
        {(void**)&glad_glDebugMessageControl, "glDebugMessageControl"},
    };
    char still_null[256] = {0};
    int n_resolved = 0;
    for (const auto& g : gated) {
      if (!*g.slot) {
        *g.slot = resolve(g.name);
        if (*g.slot) {
          n_resolved++;
        }
      }
      if (!*g.slot) {
        size_t used = strlen(still_null);
        snprintf(still_null + used, sizeof(still_null) - used, " %s", g.name);
      }
    }
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "A36-GLGATED sweep: %d/%d gated entry points checked, %d resolved here, "
                        "still NULL:%s",
                        (int)(sizeof(gated) / sizeof(gated[0])),
                        (int)(sizeof(gated) / sizeof(gated[0])), n_resolved,
                        still_null[0] ? still_null : " (none)");
    // F1a: KHR_debug is core in ES 3.2 — let the driver narrate its own
    // errors (runs 4-6 crash INSIDE libGLESv2_adreno on the first village
    // merc draw with apparently-valid bound state; the message stream is
    // the driver's side of the story). Synchronous so the message lands
    // before the faulting call returns. Capped to keep logcat sane.
    {
      auto p_cb = (void (*)(void (*)(GLenum, GLenum, GLuint, GLenum, GLsizei, const GLchar*,
                                     const void*),
                            const void*))resolve("glDebugMessageCallback");
      if (p_cb) {
        glEnable(0x92E0 /* GL_DEBUG_OUTPUT */);
        glEnable(0x8242 /* GL_DEBUG_OUTPUT_SYNCHRONOUS */);
        p_cb(
            [](GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei,
               const GLchar* message, const void*) {
              static int s_count = 0;
              if (s_count++ < 200) {
                __android_log_print(ANDROID_LOG_WARN, kLogTag,
                                    "F1A-GLDBG src=0x%x type=0x%x id=%u sev=0x%x %s", source, type,
                                    id, severity, message ? message : "");
              }
            },
            nullptr);
        __android_log_print(ANDROID_LOG_INFO, kLogTag, "F1A-GLDBG KHR_debug callback armed");
      }
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
  // Gjak2-render: game-aware (was hardcoded Jak1 — on jak2 the pool/loader
  // looked in out/jak1/fr3, found nothing, and the first real
  // handle_upload_precomputed crashed on unbacked texture-pool state).
  // Mirrors the desktop GraphicsData ctor (pipelines/opengl.cpp:88-94).
  data->texture_pool = std::make_shared<TexturePool>(g_game_version);
  rss_census::mark("texpool");

  // fr3 dir: <project>/out/<game>/fr3 — LoaderActivity extracts the APK's
  // fr3/ assets (GAME.fr3 + level packs) there. Loader handles a missing
  // level file by logging; a missing GAME.fr3 would fail load_common, so
  // probe first and run textureless (placeholders) instead of aborting.
  // External-asset-root feature (autoport 2026-07): get_fr3_dir returns
  // <game-root>/assets/fr3 in external mode, else the legacy
  // <project>/out/<game>/fr3 — so internal mode is byte-identical and external
  // mode follows the user's on-storage root automatically.
  auto fr3_dir = file_util::get_fr3_dir(g_game_version);
  const int fr3_levels =
      g_game_version == GameVersion::Jak2 ? jak2::LEVEL_TOTAL : jak1::LEVEL_TOTAL;
  if (fs::exists(fr3_dir / "GAME.fr3")) {
    data->loader = std::make_shared<Loader>(fr3_dir, fr3_levels);
  } else {
    __android_log_print(ANDROID_LOG_WARN, kLogTag,
                        "A35-RENDER %s/GAME.fr3 missing — common textures will be "
                        "checkerboard placeholders",
                        fr3_dir.string().c_str());
  }

  rss_census::mark("loader-cree");
  data->renderer = std::make_unique<AndroidOpenGLRenderer>(data->texture_pool, data->loader);

  g_data = data;
  g_renderer_ready.store(true);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "A35-RENDER renderer ready (window %dx%d) — game DMA chains will "
                      "now be consumed",
                      win_w, win_h);
  rss_census::mark("renderer-pret");
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
    if (got_chain) {
      // Gperf-particles overlap: signal pickup — the GOAL thread may build the
      // next frame from here on (chain_data itself stays protected until the
      // post-render has_data_to_render clear releases send_chain's gate).
      d->chains_picked_up++;
      d->sync_cv.notify_all();
    }
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
      g_a37_chain_loops_total.fetch_add(1, std::memory_order_relaxed);
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

    // Render-scaling knob (debug.opengoal.render.scale = 25..400, default
    // RENDER_SCALE_DEFAULT). Sizes the offscreen 3D FBO as game_res*(scale/100)
    // keeping the GOAL 4:3 aspect; the blit to the native window then up- or
    // down-samples it to the on-screen draw region, so the image stays full-
    // size and correctly placed at any scale. <100 trades sharpness for fill-
    // rate (a pure GPU lever); >100 SUPERSAMPLES the 3D for crispness, which is
    // ~free here because Geyser Rock is draw-call-bound, not fill-bound (proven:
    // fps pinned at 30 from 640x480 down to 160x120). UI/HUD/text are drawn by
    // the game into this same FBO so they supersample too at >100. Cached +
    // polled every 30 frames; a setprop takes effect live. Host/runtime only —
    // GOAL game_res and the render logic are untouched.
    {
      // Default chosen after the on-device fps-vs-resolution sweep: the highest
      // 4:3 internal res with no fps regression and no broken effects.
      static const int kRenderScaleDefault = RENDER_SCALE_DEFAULT;
      static int s_render_scale = kRenderScaleDefault;
      static unsigned s_scale_poll = 0;
      if ((s_scale_poll++ % 30) == 0) {
        char pv[16] = {0};
        if (__system_property_get("debug.opengoal.render.scale", pv) > 0) {
          int v = atoi(pv);
          if (v >= 25 && v <= 400 && v != s_render_scale) {
            s_render_scale = v;
            __android_log_print(ANDROID_LOG_INFO, kLogTag,
                                "RENDER-SCALE set to %d%% (offscreen 3D FBO scale; "
                                "blit resamples to native window)",
                                s_render_scale);
          } else if ((v < 25 || v > 400) && s_render_scale != kRenderScaleDefault) {
            // out-of-range / cleared prop -> back to the chosen default
            s_render_scale = kRenderScaleDefault;
            __android_log_print(ANDROID_LOG_INFO, kLogTag,
                                "RENDER-SCALE reset to default %d%% (prop cleared/invalid)",
                                kRenderScaleDefault);
          }
        }
        // Gperf-particles GOAL/GL overlap — STOPGAP (supervisor 2026-07-04): this
        // overlap races the GL renderer against the GOAL DMA-chain build, so geometry
        // pops in/out in real play (the v5 owner regression). DEFAULT OFF (serialized,
        // v4-parity) until Gperf-particles is reopened + fixed under real gameplay.
        // Opt back in with the prop set to '2' for the reopened phase's A/B.
        {
          char ov[16] = {0};
          bool want =
              __system_property_get("debug.opengoal.perf.nooverlap", ov) > 0 && ov[0] == '2';
          if (g_perf_overlap.load(std::memory_order_relaxed) != want) {
            g_perf_overlap.store(want, std::memory_order_relaxed);
            __android_log_print(ANDROID_LOG_INFO, kLogTag,
                                "GPERF-OVERLAP GOAL/GL overlap mode %s",
                                want ? "ON (build N+1 during GL render N)" : "OFF (serialized)");
          }
        }
      }
      options.render_scale_pct = s_render_scale;
    }

    d->renderer->render(DmaFollower(d->chain_data, d->chain_offset), options);

    const auto& st = d->renderer->stats();
    gpose_joint_frame_tick((unsigned long long)st.frame_idx);

    // Gdynamic-renderscale: publish the smoothed render WORK time (CPU wall-clock of the
    // renderer render() above — st.render_cpu_s — which EXCLUDES the vsync()/framelimiter
    // sleep on the EE thread and the SwapWindow vsync wait in the outer present loop).
    // The GOAL adaptive render-scale controller reads this via pc-get-frame-busy-us as a
    // FRAME-TIME headroom signal that, unlike measured_fps, does NOT saturate at the
    // vsync cap — so it can raise the scale back toward 100% even at a capped target.
    {
      static float s_busy_ms_ema = 1000.f / 60.f;
      float busy_ms = (float)(st.render_cpu_s * 1000.0);
      if (busy_ms > 0.f) {
        s_busy_ms_ema = (0.9f * s_busy_ms_ema) + (0.1f * busy_ms);
        Gfx::g_global_settings.measured_frame_busy_ms = s_busy_ms_ema;
      }
    }

    // === Gcine-crash3: process::deactivate code-stomp guard (the fix, arm64) ====
    // In the new-game intro's Gol/Maia portal scene the arm64 envmap merc draw
    // (l0-pris-merc bucket, the villains spawned with 'blend-shape) writes ~0x40
    // bytes -- a miscalculated base in the render/DMA path -- over the GOAL kernel
    // `process::deactivate` method's code in KERNEL.CGO at GOAL 0x191260. The next
    // ORDINARY process deactivation then takes gkernel.gc:1946's `b.ne` into the
    // corrupted bytes (GOAL 0x191278) and executes a non-instruction -> SIGILL
    // (sig 4) -> the app dies and Android returns to the launcher. Confirmed a
    // RUNTIME stomp: the APK's KERNEL.CGO is byte-identical to out/jak1-arm64/iso
    // yet device memory at 0x191260 holds host/native pointers + floats, not
    // deactivate's instructions. The write is a DMA/SIMD-class store the A38
    // mprotect tripwire cannot see (a content canary catches it). KERNEL.CGO is a
    // boot CGO that cannot be standalone-rebuilt/pushed on this device, and the
    // writer lives in the render path, so -- exactly like the Gcine-pose NaN bone
    // repair -- we snapshot deactivate's known-good code once (it is clean for the
    // whole title/flythrough; the title would crash on its first deactivation
    // otherwise) and restore it after every rendered frame, before the GOAL thread
    // runs the next frame's deactivations. The I-cache is flushed so the corrected
    // instructions are re-fetched. x86 is unaffected (#ifdef __aarch64__).
#ifdef __aarch64__
    // Gjak2-render: BOTH per-frame code-repair canaries below snapshot jak1
    // KERNEL.CGO addresses. On jak2, 0x18aee4 lands in the SYMBOL TABLE and
    // 0x191240 in unrelated data, so "repair" = reverting live jak2 memory to a
    // frame-old snapshot every frame (run2: RFTD "repaired" a legit symbol write
    // 0x187e05 -> 0x187e01, then new_type aborted). jak1-only.
    if (g_game_version == GameVersion::Jak1) {
      constexpr u32 kDeactLo = 0x191240, kDeactLen = 0x74;  // [0x191240, 0x1912b4)
      static u8* s_deact_good = nullptr;
      static bool s_deact_reported = false;
      u8* live = g_ee_main_mem + kDeactLo;
      if (!s_deact_good) {
        // Arm only if this really is deactivate's code: the call-trampoline
        // `stp x3,x5,[sp,#-16]!` at GOAL 0x191250 == 0xa9bf17e3. Guards against a
        // future KERNEL.CGO relayout silently repairing the wrong bytes.
        u32 sig = 0;
        memcpy(&sig, g_ee_main_mem + 0x191250, 4);
        if (sig == 0xa9bf17e3u) {
          s_deact_good = (u8*)malloc(kDeactLen);
          memcpy(s_deact_good, live, kDeactLen);
        }
      } else if (memcmp(s_deact_good, live, kDeactLen) != 0) {
        if (!s_deact_reported) {
          s_deact_reported = true;
          u32 off = 0;
          while (off < kDeactLen && s_deact_good[off] == live[off]) off++;
          u32 wasw = 0, noww = 0;
          memcpy(&wasw, s_deact_good + (off & ~3u), 4);
          memcpy(&noww, live + (off & ~3u), 4);
          __android_log_print(
              ANDROID_LOG_FATAL, kLogTag,
              "GCINE3-DEACT-STOMP frame=%llu first=goal:0x%x was=0x%08x now=0x%08x "
              "(envmap merc l0-pris-merc draw stomped process::deactivate code; repaired)",
              (unsigned long long)st.frame_idx, kDeactLo + off, wasw, noww);
        }
        memcpy(live, s_deact_good, kDeactLen);
        __builtin___clear_cache((char*)live, (char*)live + kDeactLen);
      }
    }
#endif

    // === Gmatch: return-from-thread-dead code-stomp guard (arm64) =============
    // The NEW GAME sage-intro cutscene's arm64 blend-shape merc draw uses a
    // corrupted low base pointer (the recurring Gnd/Gcine3 "global-buf.base goes
    // high->low" class) and writes vertex data over the GOAL kernel asm-func
    // `return-from-thread-dead` (gkernel.gc:451) at GOAL 0x18aee4 -- the per-
    // process RETURN TRAMPOLINE that set-to-run-bootstrap (gkernel.gc:1849)
    // pushes onto every process's fake stack. When any process's main thread
    // then RETURNS, control lands at this trampoline; if it has been stomped the
    // CPU executes the overwritten bytes -> SIGILL (sig 4, pc=lr=0x7f0018aee4) ->
    // app death -> Android launcher. Verified: the live symbol-table walk
    // resolves crash target 0x18aee4 == "return-from-thread-dead", and the A37
    // PC-window shows it overwritten (00000000) where its code should be. This is
    // the SAME stomp mechanism the Gcine3 canary above repairs for a DIFFERENT
    // target (process::deactivate @ 0x191240); the sage-intro scene corrupts the
    // base to a different low address. KERNEL.CGO is an un-rebuildable boot CGO
    // and the writer is in the render path, so -- like the deactivate canary --
    // we snapshot the trampoline's clean code once (clean from boot until the
    // cutscene at ~frame 7080) and restore it after every rendered frame, before
    // the GOAL thread runs the next process return. x86 unaffected.
#ifdef __aarch64__
    // Gjak2-render: jak1-only (see the deactivate-canary gate note above; on jak2
    // this address range is the live symbol table).
    if (g_game_version == GameVersion::Jak1) {
      const u32 kRftdLo = g_gmatch_rftd_goal, kRftdLen = g_gmatch_rftd_len;  // 0x18aee4 / 0x80
      static bool s_rftd_reported = false;
      u8* rlive = g_ee_main_mem + kRftdLo;
      if (!g_gmatch_rftd_good) {
        // Snapshot once, while clean: a non-zero first word means the kernel code
        // is linked and not (yet) stomped; the frame gate keeps the snapshot
        // strictly before the cutscene stomp at ~frame 7080. Publishing the
        // pointer LAST makes the SIGILL handler's null-check race-safe.
        u32 w0 = 0;
        memcpy(&w0, rlive, 4);
        if (w0 != 0 && st.frame_idx < 6000) {
          u8* good = (u8*)malloc(kRftdLen);
          memcpy(good, rlive, kRftdLen);
          g_gmatch_rftd_good = good;
          __android_log_print(ANDROID_LOG_INFO, kLogTag,
                              "GMATCH-RFTD-CANARY armed goal:0x%x len=0x%x sig=0x%08x frame=%llu",
                              kRftdLo, kRftdLen, w0, (unsigned long long)st.frame_idx);
        }
      } else if (memcmp(g_gmatch_rftd_good, rlive, kRftdLen) != 0) {
        if (!s_rftd_reported) {
          s_rftd_reported = true;
          u32 off = 0;
          while (off < kRftdLen && g_gmatch_rftd_good[off] == rlive[off]) off++;
          u32 wasw = 0, noww = 0;
          memcpy(&wasw, g_gmatch_rftd_good + (off & ~3u), 4);
          memcpy(&noww, rlive + (off & ~3u), 4);
          __android_log_print(
              ANDROID_LOG_FATAL, kLogTag,
              "GMATCH-RFTD-STOMP frame=%llu first=goal:0x%x was=0x%08x now=0x%08x "
              "(merc blend-shape draw stomped return-from-thread-dead; repaired)",
              (unsigned long long)st.frame_idx, kRftdLo + off, wasw, noww);
        }
        memcpy(rlive, g_gmatch_rftd_good, kRftdLen);
        __builtin___clear_cache((char*)rlive, (char*)rlive + kRftdLen);
      }
    }
#endif

    const u64 n = d->frames_rendered.fetch_add(1) + 1;
    if (n <= 5 || (n % 60) == 0 || st.buckets_skipped > 0) {
      static u32 s_last_logged_skips = 0;
      if (n <= 5 || (n % 60) == 0 || st.buckets_skipped != s_last_logged_skips) {
        s_last_logged_skips = st.buckets_skipped;
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "A35-RENDER frame=%llu chain_bytes=%u buckets_drawn=%u skipped=%u "
                            "draws=%u tris=%u fbo=%dx%d render_ms=%.2f buckets_ms=%.2f "
                            "pcrtc_ms=%.2f",
                            (unsigned long long)st.frame_idx, st.chain_bytes, st.buckets_drawn,
                            st.buckets_skipped, st.draw_calls, st.triangles, st.fbo_w, st.fbo_h,
                            st.render_cpu_s * 1000.0, st.buckets_cpu_s * 1000.0,
                            st.pcrtc_cpu_s * 1000.0);
      }
    }
    // supervisor-diag: mirror the render stats into the jak2 breadcrumb every ~300
    // frames (and the first) so a HONOR owner with logcat suppressed can see whether
    // the renderer is drawing anything (draws/tris/buckets) or stuck at 0.
    if (n == 1 || (n % 300) == 0) {
      char diag[192];
      std::snprintf(diag, sizeof(diag),
                    "A35-RENDER frame=%llu draws=%u tris=%u buckets_drawn=%u skipped=%u",
                    (unsigned long long)st.frame_idx, st.draw_calls, st.triangles,
                    st.buckets_drawn, st.buckets_skipped);
      gk_jak2_diag_line(diag);
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

namespace {
// ===== Gd1-cutscene-clock: wall-clock 60 Hz IOP/overlord VBlank pacer =======
// The jak1 overlord VBlank_Handler (game/overlord/jak1/srpc.cpp:446) advances
// the fake-VAG stream clock — `gFakeVAGClock += 1024/target_fps` per vblank —
// that paces EVERY spooled cutscene. On real PS2 hardware the IOP receives the
// VBlank interrupt at the display rate (60 Hz NTSC) REGARDLESS of how fast the
// EE renders, so with target_fps==60 (gfx.h) the clock advances 1024 units/sec
// = real time. The desktop oracle reproduces this for free: Gfx::vsync() (and
// thus the signal_vblank callback) is fired once per display-refresh swap at a
// flat 60 Hz because the desktop GPU holds 60 fps.
//
// On the Adreno 618 the render rate collapses on heavy content (new-game
// cutscene ~15 fps, village flythrough ~20 fps). The previous code fired the
// IOP vblank exactly once per vsync() call (= once per RENDERED+swapped frame),
// so the vblank — and therefore the cutscene stream clock — ticked at the
// render rate (~15 Hz) instead of 60 Hz. gFakeVAGClock then advanced at
// 15*(1024/60) ~= 0.27x real-time, so cinematics played in fluid slow-motion
// (~3.7x too slow; camera/joints still interpolate per game-frame so it looked
// smooth). Measured deterministically: Grender-audit D1.
//
// Fix: drive signal_vblank() from a dedicated wall-clock 60 Hz thread,
// decoupled from the render-swap cadence, exactly as the desktop's 60 Hz
// display loop does. The consume side (IOP_Kernel::dispatch, which runs the
// handler once per set of the atomic `vblank_recieved` bool) is shared,
// platform-identical code — only the SET rate diverged on Android, so restoring
// a 60 Hz set rate makes Android match desktop. signal_vblank only stores an
// atomic bool, so calling it from this thread is safe; the registered callback
// (android_runtime_full.cpp) also wakes the iop-runner so its <=1 ms idle
// dispatch sleep can't swallow a vblank edge under scheduler jitter. vsync() no
// longer fires the vblank at all — it is purely the game-chain frame-pacing
// barrier now. x86/desktop is untouched (this is an android/ TU).
std::mutex g_pacer_mutex;
std::condition_variable g_pacer_cv;
std::thread g_pacer_thread;
bool g_pacer_should_run = false;

void iop_vblank_pacer_loop() {
  pthread_setname_np(pthread_self(), "iopvbl-pacer");
  using namespace std::chrono;
  // Gframerate-variable: pace the IOP/overlord VBlank at the engine's target-fps
  // (wired to the panel refresh in reset-gfx), NOT a hardcoded 60 Hz. The overlord
  // VBlank_Handler advances the fake-VAG cutscene/stream clock by
  // (1024 / Gfx::g_global_settings.target_fps) per fired vblank, so a real-time
  // cutscene clock requires pacer_Hz == target_fps. Track target_fps LIVE (it can
  // change via the fps menu) so the cutscene clock stays real-time at any refresh,
  // not just 60. (On the 60 Hz Redmi this is exactly the previous 16667 us.)
  auto fps_period = [] {
    double fps = (double)Gfx::g_global_settings.target_fps;
    if (fps < 1.0) {
      fps = 60.0;
    }
    return microseconds((long long)(1000000.0 / fps + 0.5));
  };
  auto period = fps_period();
  auto next = steady_clock::now() + period;
  bool logged = false;
  // Phase F3: when debug.opengoal.f3.measure=1, log one "display tick" per
  // fired vblank. This callback IS the IOP/overlord vblank that advances the
  // game's *display* frame-counter / time at a true wall-clock 60 Hz, decoupled
  // from render swap (the whole point of the Gd1 pacer). Logging it is an
  // honest measurement of the SIMULATION rate for the F3 validator — it stays
  // 60 Hz even when the renderer is capped to 30 FPS. OFF by default (one
  // cached property read every 8 ticks); zero spam for normal runs.
  uint64_t f3_ticks = 0;
  unsigned f3_poll = 0;
  bool f3_on = false;
  for (;;) {
    std::function<void()> cb;
    {
      std::unique_lock<std::mutex> lk(g_pacer_mutex);
      g_pacer_cv.wait_until(lk, next, [] { return !g_pacer_should_run; });
      if (!g_pacer_should_run) {
        return;
      }
      cb = g_vsync_callback;  // copy under lock (set_vsync_callback writes it here)
    }
    if (cb && MasterExit == RuntimeExitStatus::RUNNING) {
      if (!logged) {
        logged = true;
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "Gd1-VBLANK IOP/overlord vblank paced at wall-clock target-fps "
                            "(%.1f Hz; decoupled from render swap; cutscene clock = real-time)",
                            (double)Gfx::g_global_settings.target_fps);
      }
      cb();
      if ((f3_poll++ & 7) == 0) {
        char pv[8] = {0};
        f3_on =
            __system_property_get("debug.opengoal.f3.measure", pv) > 0 && pv[0] == '1';
      }
      if (f3_on) {
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "Gd1-VBLANK display tick %llu (simulation 60 Hz; "
                            "render rate decoupled)",
                            (unsigned long long)(++f3_ticks));
      }
    }
    period = fps_period();  // re-read live: target-fps can change at runtime
    next += period;
    auto now = steady_clock::now();
    if (next < now) {
      // Fell behind (a long stall): resync to now instead of bursting a backlog
      // of zero-sleep ticks. signal_vblank coalesces a backlog into one handler
      // run anyway, so bursting would not advance the clock faster — resyncing
      // just keeps the long-run average at target-fps.
      next = now + period;
    }
  }
}
}  // namespace

void set_vsync_callback(std::function<void()> f) {
  bool start = false, stop = false;
  {
    std::unique_lock<std::mutex> lk(g_pacer_mutex);
    g_vsync_callback = std::move(f);
    if (g_vsync_callback && !g_pacer_should_run) {
      g_pacer_should_run = true;
      start = true;
    } else if (!g_vsync_callback && g_pacer_should_run) {
      g_pacer_should_run = false;
      stop = true;
    }
  }
  // Start/stop the pacer OUTSIDE the lock — join() would deadlock against the
  // pacer's own acquisition of g_pacer_mutex.
  if (stop) {
    g_pacer_cv.notify_all();
    if (g_pacer_thread.joinable()) {
      g_pacer_thread.join();
    }
  }
  if (start) {
    g_pacer_thread = std::thread(iop_vblank_pacer_loop);
  }
}

u32 vsync() {
  g_a40_vsync_entry.fetch_add(1, std::memory_order_relaxed);
  g_spart_prof.goal_frames.fetch_add(1, std::memory_order_relaxed);

  // Gd1-cutscene-clock: the IOP/overlord VBlank is NO LONGER fired from here.
  // It used to be fired once per vsync() call (= once per rendered frame), which
  // coupled the cutscene/spool stream clock to the render rate and produced
  // fluid slow-motion cinematics whenever the Adreno dropped below 60 fps (see
  // iop_vblank_pacer_loop above). A dedicated wall-clock 60 Hz pacer thread now
  // owns ALL vblank firing, mirroring the desktop's 60 Hz display loop. vsync()
  // is purely the game-chain frame-pacing barrier: it blocks until the next
  // swap so each game chain corresponds to one rendered frame.

  // Gintro: pre-renderer-ready, HOLD the GOAL dispatcher here instead of letting
  // it free-run. The SDL thread is concurrently bringing the renderer up (glad +
  // 43 shaders + GAME.fr3, ~2 s on the Adreno 618). If we returned 0 immediately
  // the dispatcher would free-run at ~270 Hz and fast-forward the entire
  // pre-title intro (SCE screen + ND/Daxter "ndi-intro") in the ~600 frames
  // before the first frame could be drawn, so those beats would never reach the
  // framebuffer (G1 boot: chains received == dropped == 607). Spin at ~60 Hz to
  // throttle the dispatcher until the renderer is up, then fall through to the
  // swap-chain block so the intro renders in chronological order. The overlord /
  // fake-VAG clock is kept real-time during this window by the pacer thread, not
  // here. The hold (~2 s) is far under the A37 hang-watchdog's 6 s threshold (and
  // that watchdog only logs). The renderer bring-up runs on the SDL thread
  // independently of the dispatcher, so this cannot deadlock.
  if (!g_renderer_ready.load()) {
    while (!g_renderer_ready.load() && MasterExit == RuntimeExitStatus::RUNNING) {
      std::this_thread::sleep_for(std::chrono::microseconds(16600));
    }
    if (!g_renderer_ready.load()) {
      // Shutting down before the renderer ever came up.
      g_a40_vsync_exit.fetch_add(1, std::memory_order_relaxed);
      return 0;
    }
    // Renderer just became ready — fall through to the post-ready path.
  }

  // Post-ready: block on the swap chain so each vsync() corresponds to one
  // rendered+swapped frame (game-chain pacing). The vblank that paces spooled
  // cutscenes is fired separately at wall-clock target-fps by the pacer thread.
  // The GAME-CLOCK SPEED is driven by the REAL per-frame dt in a35_read_ee_timer
  // (gk_android_main.cpp) feeding the engine's native variable-fps math, NOT
  // here -- this barrier stays the 1:1 game-chain<->swap pacer it always was.
  auto* d = g_data;
  u64 frame_idx_now;
  {
    std::unique_lock<std::mutex> lock(d->dma_mutex);
    auto init_frame = d->frame_idx_of_input_data;
    // overlap-mode captures: the send counter (wait until OUR last chain has
    // been picked up) and the absolute frame counter (fallback so a chain-less
    // frame still unblocks within one GL cycle, which swaps regardless).
    auto sent_now = d->chains_sent;
    auto init_frame_abs = d->frame_idx;
    const bool overlap = g_perf_overlap.load(std::memory_order_relaxed);
    SpartScopedNs _idle(g_spart_prof.goal_idle);
    d->sync_cv.wait(lock, [=] {
      if (MasterExit != RuntimeExitStatus::RUNNING) {
        return true;
      }
      if (overlap) {
        // Gperf-particles overlap: release the GOAL thread as soon as the GL
        // thread has PICKED UP the last sent chain (render START, ~= the swap
        // boundary of the previous frame) — if it was already picked up before
        // we got here, return immediately. The GOAL thread then builds frame
        // N+1 during the whole GL render of N; send_chain's unconditional
        // !has_data_to_render gate protects chain_data.
        return d->chains_picked_up >= sent_now || d->frame_idx > init_frame_abs;
      }
      // Original serialized predicate (kill switch): block until the GL thread
      // has fully swapped the frame (post_swap_tick bumped frame_idx).
      return d->frame_idx > init_frame;
    });
    frame_idx_now = d->frame_idx;
  }

  // ===== Gframerate-variable: cap the EE game-loop rate at target-fps =========
  // This is THE framerate cap (it replaced the removed 30/60 vblank LOCK and the
  // ineffective GL-thread present cap). The swap-chain barrier above does NOT
  // reliably gate the EE game loop to the GL present rate: frame_idx_of_input_data
  // only advances when the GL thread picks up a NEW chain, so once the GL is one
  // frame ahead the wait predicate is already satisfied and a fast EE returns
  // immediately and SPINS -- advancing display-frame-start (and the a35 game
  // clock) faster than the panel can present, dropping chains. On this device
  // that free-runs the GOAL loop at ~73 fps on a 60 Hz panel -> the game clock
  // over-advances -> "runs fast at light load".
  //
  // So bound the EE loop here: vsync() returns no more than target-fps times per
  // wall-clock second. This is a MAX-rate cap ONLY -- under load the EE runs
  // slower FREELY (no forced 30/60 grid), and the REAL per-frame dt still drives
  // the game clock (a35_read_ee_timer error feedback) so speed stays constant
  // real-time at whatever fps results. target-fps == the active panel mode (60)
  // here, so this is the software vsync the driver's SwapInterval(1) doesn't
  // actually enforce. x86/desktop untouched (android/ TU).
  {
    SpartScopedNs _pace(g_spart_prof.goal_pace);
    using namespace std::chrono;
    static steady_clock::time_point s_next{};
    // anim-interp-low-fps — BALAYAGE DE CADENCE D'AFFICHAGE (`debug.opengoal.frame.limit`).
    // Il deplace la cible du LIMITEUR seul : `Gfx::g_global_settings.target_fps` — donc
    // `*ticks-per-frame*` et le budget de `render_pace` — n'est PAS touche, et c'est
    // precisement l'ecart entre cadence AFFICHEE et cadence CIBLE qui fabrique le defaut que
    // l'owner decrit a 45 img/s. Sans consigne, rend la cible telle quelle : le binaire de
    // l'owner passe ici a chaque image et ne change pas de comportement.
    double tfps = render_pace::stimulus_fps((double)Gfx::g_global_settings.target_fps);
    if (tfps < 1.0) {
      tfps = 60.0;
    }
    const auto period = nanoseconds((long long)(1000000000.0 / tfps));
    auto now = steady_clock::now();
    if (s_next.time_since_epoch().count() == 0 || now > s_next + period) {
      // first call, or we fell behind (a heavy frame): re-anchor, no wait.
      s_next = now + period;
    } else {
      // Pace PRECISELY to the absolute deadline s_next, mirroring the smooth desktop
      // build's FrameLimiter (common/util/FrameLimiter.cpp): coarse-sleep to a ~1.5ms
      // margin, then BUSY-SPIN the final sliver to the exact deadline.
      //
      // Gcamera-smooth: the old code sleep_for()'d the WHOLE remaining time every
      // frame. Android's sleep_for wakeup granularity (~1-2ms, and it OVERSHOOTS) then
      // (a) left each present landing 1-2ms off the target -> UNEVEN present cadence
      // (measured at a held ~60fps: present dt sd 2.85ms, 30% of frames >2ms off, mean
      // pushed to ~18.5ms == only ~54fps), and (b) the overshoot nudged real_dt over
      // the k=1 band often enough that ~11% of frames took a k=2 DOUBLE game-time step
      // -> visible camera "jumps". Because the GL present is 1:1-slaved to this EE
      // cadence (measured: present dt == EE dt), that jitter is exactly the camera-pan
      // judder the owner sees "even when the fps is fine", while Jak's slow local
      // motion hides it. The spin removes the wakeup jitter (present dt sd -> ~0, a
      // clean 16.67ms / k=1), exactly as the smooth desktop reference does.
      //
      // Still a MAX-rate cap ONLY (no forced 30/60 grid, no fps quantization) and the
      // game clock is still driven by REAL dt in a35_read_ee_timer, so constant
      // real-time speed is unchanged (a clean 60fps/k=1 advances game-time at the same
      // real rate the old jittery ~54fps/k-dither did -- the a35 error feedback holds
      // it). EINTR-robust: the loop reaches the deadline even if the SIGILL
      // crash-repair handler cuts a sleep short (it just re-computes and re-sleeps).
      const auto spin_margin = microseconds(1500);
      for (;;) {
        now = steady_clock::now();
        if (now >= s_next || MasterExit != RuntimeExitStatus::RUNNING) {
          break;
        }
        const auto remain = s_next - now;
        if (remain > spin_margin) {
          std::this_thread::sleep_for(remain - spin_margin);
        }
        // else: re-loop without sleeping -> tight busy-spin for the final <=1.5ms.
      }
      s_next += period;
    }
    // gated cadence diagnostic: prove the cap holds (debug.opengoal.gspeed.measure).
    // Log ONCE every 64 vsync() calls with the correct per-call interval.
    static unsigned s_vcount = 0;
    static bool s_vmeas = false;
    static steady_clock::time_point s_vlast{};
    if ((s_vcount++ & 63) == 0) {
      char pv[8] = {0};
      s_vmeas =
          __system_property_get("debug.opengoal.gspeed.measure", pv) > 0 && pv[0] == '1';
      if (s_vmeas) {
        const auto t = steady_clock::now();
        if (s_vlast.time_since_epoch().count() != 0) {
          const double per_call_ms =
              duration_cast<duration<double, std::milli>>(t - s_vlast).count() / 64.0;
          __android_log_print(ANDROID_LOG_INFO, kLogTag,
                              "GFPS-VSYNC per_call_ms=%.2f (=> %.1f vsync/s) target_fps=%.1f",
                              per_call_ms, 1000.0 / per_call_ms, tfps);
        }
        s_vlast = t;
      }
    }
  }

  g_a40_vsync_exit.fetch_add(1, std::memory_order_relaxed);
  return frame_idx_now & 1;
}

u32 sync_path() {
  g_a40_syncpath_entry.fetch_add(1, std::memory_order_relaxed);
  if (!g_renderer_ready.load()) {
    g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
    return 0;
  }
  auto* d = g_data;
  // Gperf-particles overlap: return immediately. sync-path's PS2 meaning is
  // "the DMA path is idle, my buffers are reusable" — send_chain deep-copies
  // the chain (dma_copier), so the engine's builder buffers are free the moment
  // send_chain returned; waiting here for the renderer to finish would
  // re-serialize the whole frame (the engine calls sync-path right before
  // syncv at frame end, drawable.gc:1193). chain_data overwrite safety is
  // send_chain's unconditional gate, not this wait.
  if (g_perf_overlap.load(std::memory_order_relaxed)) {
    g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
    return 0;
  }
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
#if defined(__aarch64__) && defined(__ANDROID__)
  // GND-HWWP: arm the arm64 HARDWARE data watchpoint on the global-buf base
  // fields from the GOAL/dispatcher thread (this thread is the writer). Gated
  // behind debug.opengoal.gnd.hwwp=1; one-shot, no-op on every later frame.
  gnd_hwwp_arm_once();
#endif
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  // Gperf-particles overlap: the GOAL thread is released at chain PICKUP, so it
  // can re-enter send_chain while the GL thread is still consuming the previous
  // chain. chain_data must never be overwritten while the GL thread reads it —
  // block here until the GL thread has finished (has_data_to_render cleared
  // after render()). UNCONDITIONAL (not overlap-gated): in serialized mode the
  // vsync predicate already guarantees the flag is clear so this is a no-op,
  // and keeping it always-on means a live kill-switch flip mid-render can never
  // race the copier against the reader. Keeps the MasterExit escape so
  // shutdown/boot mode-flips can't deadlock. sync_cv is the cv notified when
  // has_data_to_render is cleared after render() (and by the chain-loop skip
  // path); wait on it, not dma_cv.
  d->sync_cv.wait(lock, [=] {
    return (MasterExit != RuntimeExitStatus::RUNNING) || !d->has_data_to_render;
  });
  if (MasterExit != RuntimeExitStatus::RUNNING) {
    return;
  }
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
    int low_kind = -1;
    u32 low_addr = 0, low_qwc = 0;
    bool low_spr = false;
    // Gintro: dump the leading tags of the first few flagged chains to
    // characterize the ndi-intro chain that trips the low-addr guard.
    static std::atomic<u32> s_dump_frames{0};
    const bool do_dump = gintro_chainwalk_dbg() && s_dump_frames.load() < 6;
    int dumped = 0;
    while (!probe.ended() && steps < kMaxSteps) {
      auto tag = probe.current_tag();
      if (do_dump && dumped < 14) {
        dumped++;
        __android_log_print(ANDROID_LOG_WARN, kLogTag,
                            "GINTRO-CHAINWALK step=%d off=0x%x kind=%d spr=%d addr=0x%x qwc=%u",
                            steps, probe.current_tag_offset(), (int)tag.kind, (int)tag.spr,
                            tag.addr, tag.qwc);
      }
      if (tag.addr != 0 && tag.addr <= EE_MAIN_MEM_LOW_PROTECT) {
        low_tag = true;
        low_kind = (int)tag.kind;  // 0=REFE 1=CNT 2=NEXT 3=REF 4=REFS 5=CALL 6=RET 7=END
        low_addr = tag.addr;
        low_qwc = tag.qwc;
        low_spr = tag.spr;
        // GND diag: prove whether the LIVE memory really holds this low addr
        // (follower correct -> real corruption) or the follower mis-read
        // (memory fine -> follower/base bug). Read the tag bytes BOTH via the
        // follower's base and directly via g_ee_main_mem, plus a re-read.
        if (do_dump) {
          u32 mt = probe.current_tag_offset();
          u64 raw_data = 0, raw_ee = 0, raw_ee2 = 0;
          if ((u64)mt + 8 <= EE_MAIN_MEM_SIZE) {
            memcpy(&raw_data, (const u8*)data + mt, 8);
            memcpy(&raw_ee, g_ee_main_mem + mt, 8);
            memcpy(&raw_ee2, g_ee_main_mem + mt, 8);
          }
          __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                              "GND-PRECOPY-RAW off=0x%x data_is_ee=%d base_delta=0x%lx "
                              "raw@data=0x%016llx raw@ee=0x%016llx reread=0x%016llx",
                              mt, (int)((const u8*)data == g_ee_main_mem),
                              (unsigned long)((const u8*)data - g_ee_main_mem),
                              (unsigned long long)raw_data, (unsigned long long)raw_ee,
                              (unsigned long long)raw_ee2);
        }
        break;
      }
      probe.read_and_advance();
      steps++;
    }
    if (!probe.ended() || low_tag) {
      // Gintro diagnostic: dump the FLAGGED tag (kind/spr/addr/qwc), the true
      // (uncapped) skip count, and the 16 bytes AT the flagged NEXT/REF
      // destination (data + addr) so we can tell a legit jump from garbage.
      // addr is only dereferenced for REF/REFE/REFS (kind 0/3/4) and
      // NEXT/CALL (kind 2/5); CNT/RET/END (1/6/7) ignore it.
      const u32 ntot = g_a42_precopy_total.fetch_add(1) + 1;
      if (do_dump) {
        s_dump_frames.fetch_add(1);
      }
      if (ntot <= 40 || (ntot % 240) == 0) {
        u64 dst0 = 0, dst1 = 0;
        if (low_addr != 0 && (u64)low_addr + 16 <= EE_MAIN_MEM_SIZE) {
          memcpy(&dst0, (const u8*)data + low_addr, 8);
          memcpy(&dst1, (const u8*)data + low_addr + 8, 8);
        }
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A42-CHAIN-PRECOPY skip #%u (steps=%d low_tag=%d kind=%d spr=%d "
                            "addr=0x%x qwc=%u off=0x%x dst=0x%016llx %016llx) — skipped",
                            ntot, steps, (int)low_tag, low_kind, (int)low_spr, low_addr, low_qwc,
                            probe.current_tag_offset(), (unsigned long long)dst0,
                            (unsigned long long)dst1);
      }
      // Gintro: this corrupt chain is the arm64 blend-shape/joint OOB stomp
      // (the ndi state spawns Jak+Daxter blend-shape skeletons; their joint-
      // decompress intermittently scribbles a low garbage addr into a per-
      // frame DMA bucket-NEXT — confirmed vs the x86 oracle which never
      // produces a low tag; see Gintro-fix-summary). The chain CANNOT go to
      // the copier (its LOW_PROTECT assert would abort) nor to the renderer
      // (it would follow the garbage NEXT). The old behavior dropped it, but
      // dropping breaks the frame pacing: frame_idx_of_input_data freezes
      // while swaps advance, so vsync() free-runs and fast-forwards the ndi
      // spool, AND the ndi logo black-flashes. Instead, RE-PRESENT the last
      // good copied chain: the renderer redraws the previous ndi frame, the
      // consume cadence stays 1:1 (real-time pacing holds), and the logo is
      // held (a brief stutter) rather than dropped. This makes the ND/Daxter
      // logo render in order despite the OOB; the OOB itself is a separate
      // (deeper, goalc-arm64) defect tracked for its own phase.
      if (d->ever_copied && !d->has_data_to_render) {
        d->has_data_to_render = true;
        d->chains_sent++;  // Gperf-particles overlap: re-present counts as sent
        d->dma_cv.notify_all();
      }
      return;
    }
  }
  const auto& chain_copy = d->dma_copier.run(data, offset);
  d->chain_data = chain_copy.data.data();
  d->chain_offset = chain_copy.start_offset;
  d->has_data_to_render = true;
  d->chains_sent++;  // Gperf-particles overlap: vsync waits picked_up >= sent
  d->ever_copied = true;
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

bool run_tex_call(const PendingTexCall& c) {
  if (c.is_relocate) {
    // 2026-08-25 — LA SHIELD PLANTAIT ICI, ET C'ETAIT UNE COURSE D'ORDRE, PAS UNE CORRUPTION.
    // Un `relocate` rejoue depuis la file de demarrage peut designer une fente SOURCE que le
    // chargeur n'a pas encore remplie : elle contient alors un placeholder, et l'assertion de
    // `move_existing_to_vram` (`!is_placeholder`) abattait le processus pendant
    // `init_renderer_on_gl_thread`. Le jeu reemet ses deplacements a chaque frame, donc en
    // sauter UN au boot est sans consequence — l'abattre, non. On le DIT au journal au lieu de
    // le taire : un saut silencieux redeviendrait un defaut invisible.
    if (!g_data->texture_pool->relocate_source_ready(c.src)) {
      static u32 s_deferred = 0;
      if (++s_deferred <= 16 || (s_deferred % 100) == 0) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag,
                            "A41-TEX relocate REPORTE #%u dst=0x%x src=0x%x fmt=%u — source pas "
                            "encore chargee, il repassera au prochain drain",
                            s_deferred, c.dst, c.src, c.format);
      }
      return false;  // PAS consomme : le rappeler plus tard
    }
    __android_log_print(ANDROID_LOG_INFO, kLogTag, "A41-TEX relocate dst=0x%x src=0x%x fmt=%u",
                        c.dst, c.src, c.format);
    g_data->texture_pool->relocate(c.dst, c.src, c.format);
    return true;
  } else {
    static u32 s_upload_count = 0;
    const u32 n = ++s_upload_count;
    if (n <= 8 || (n % 100) == 0) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag, "A41-TEX upload #%u (%zu slot links)", n,
                          c.upload_entries.size());
    }
    g_data->texture_pool->handle_upload_precomputed(c.upload_entries);
    return true;
  }
}

// Pre: g_pending_tex_mutex held, g_renderer_ready true.
void drain_pending_tex_calls_locked() {
  if (g_pending_tex_flushed) {
    return;
  }
  if (!g_pending_tex_calls.empty()) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "A41-TEX flushing %zu queued pre-ready texture calls (boot-order race)",
                        g_pending_tex_calls.size());
    // 2026-08-25 — ON GARDE CE QU'ON N'A PAS PU JOUER. Premiere version : on SAUTAIT un relocate
    // dont la source n'etait pas chargee. Le jeu allait alors plus loin puis mourait ailleurs, a
    // des endroits VARIABLES (fil SDL, fil audio, blocage) — signature d'une fente laissee non
    // liee et dereferencee plus tard. Sauter n'etait donc pas corriger, c'etait deplacer.
    // Ici l'appel reste en file et repasse au prochain drain, quand le chargeur aura fourni la
    // source. L'ORDRE relatif est conserve.
    std::vector<PendingTexCall> retained;
    for (const auto& c : g_pending_tex_calls) {
      if (!run_tex_call(c)) {
        retained.push_back(c);
      }
    }
    g_pending_tex_calls.swap(retained);
    if (g_pending_tex_calls.empty()) {
      g_pending_tex_flushed = true;
      g_pending_tex_calls.shrink_to_fit();
    } else {
      __android_log_print(ANDROID_LOG_WARN, kLogTag,
                          "A41-TEX %zu appel(s) reportes — la file reste ouverte",
                          g_pending_tex_calls.size());
    }
  } else {
    g_pending_tex_flushed = true;
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
  // 2026-08-25 — L'ORDRE RESTE FIFO MEME QUAND UN APPEL EST REPORTE. Si le drain n'a pas pu
  // tout jouer, la file n'est pas vide : jouer CET appel-ci tout de suite le ferait passer
  // devant des appels plus anciens. Il prend donc la queue. Et s'il ne passe pas lui-meme
  // (source pas encore chargee), il est mis en file au lieu d'etre perdu.
  if (!g_pending_tex_calls.empty()) {
    g_pending_tex_calls.push_back(c);
    return;
  }
  if (!run_tex_call(c)) {
    g_pending_tex_calls.push_back(c);
    g_pending_tex_flushed = false;
  }
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
// cutscene-npc-flicker (essai 11) : sante de la chaine DMA pour la ligne NPCPLAT du recensement
// (game/system/npc_flicker.h). out[0] = chaines re-presentees (A42-CHAIN-PRECOPY), out[1] = chaines
// sans fin sautees (A37-CHAIN-LOOP). Le seau malforme (A37-BUCKET-MALFORMED) vit dans
// android_opengl_renderer.cpp : gk_a37_malformed_buckets_total().
extern "C" void gk_npc_chain_health_counters(unsigned long long out[2]) {
  using namespace android_gfx;
  out[0] = g_a42_precopy_total.load(std::memory_order_relaxed);
  out[1] = g_a37_chain_loops_total.load(std::memory_order_relaxed);
}

extern "C" void gk_a40_shim_counters(unsigned long long out[6]) {
  using namespace android_gfx;
  out[0] = g_a40_vsync_entry.load(std::memory_order_relaxed);
  out[1] = g_a40_vsync_exit.load(std::memory_order_relaxed);
  out[2] = g_a40_syncpath_entry.load(std::memory_order_relaxed);
  out[3] = g_a40_syncpath_exit.load(std::memory_order_relaxed);
  out[4] = g_chains_received.load(std::memory_order_relaxed);
  out[5] = g_chains_dropped_pre_init.load(std::memory_order_relaxed);
}
