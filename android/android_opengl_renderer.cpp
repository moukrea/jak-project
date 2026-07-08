// Phase A35 (autoport): Android GLES 3.2 bucket-dispatch renderer.
// See android_opengl_renderer.h for the design note. The dispatch loop,
// default-regs parse, FBO setup and pcrtc blit mirror
// game/graphics/opengl_renderer/OpenGLRenderer.cpp (jak1 paths) so the
// Android renderer is a true subset of the desktop one, not a rewrite.

#include "android_opengl_renderer.h"

#include <android/log.h>
#include <sys/system_properties.h>

#include "common/goal_constants.h"
#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/DirectRenderer.h"
#include "game/graphics/opengl_renderer/EyeRenderer.h"
#include "game/graphics/opengl_renderer/ProgressRenderer.h"
#include "game/graphics/opengl_renderer/SkyRenderer.h"
#include "game/graphics/opengl_renderer/TextureAnimator.h"
#include "game/graphics/opengl_renderer/VisDataHandler.h"
#include "game/graphics/opengl_renderer/background/Shrub.h"
#include "game/graphics/opengl_renderer/background/TFragment.h"
#include "game/graphics/opengl_renderer/background/Tie3.h"
#include "game/graphics/opengl_renderer/foreground/Generic2BucketRenderer.h"
#include "game/graphics/opengl_renderer/foreground/Merc2BucketRenderer.h"
#include "game/graphics/opengl_renderer/ocean/OceanMidAndFar.h"
#include "game/graphics/opengl_renderer/ocean/OceanNear.h"
#include "game/graphics/opengl_renderer/sprite/Sprite3.h"
#include "game/graphics/opengl_renderer/TextureUploadHandler.h"
#include "game/graphics/pipelines/opengl.h"
#include "game/kernel/common/kmachine.h"
#include "game/mips2c/spart_prof.h"
#include "game/runtime.h"

#include "fmt/format.h"

namespace {
constexpr const char* kLogTag = "opengoal-gk";

// Identical to the desktop make_fbo (OpenGLRenderer.cpp), msaa stripped:
// the Android skeleton always renders single-sampled.
Fbo a35_make_fbo(int w, int h) {
  Fbo result;
  glGenFramebuffers(1, &result.fbo_id);
  glBindFramebuffer(GL_FRAMEBUFFER, result.fbo_id);
  result.valid = true;

  GLuint tex;
  glGenTextures(1, &tex);
  result.tex_id = tex;
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);

  GLuint zbuf;
  glGenRenderbuffers(1, &zbuf);
  result.zbuf_stencil_id = zbuf;
  glBindRenderbuffer(GL_RENDERBUFFER, zbuf);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, zbuf);

  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);

  GLenum render_targets[1] = {GL_COLOR_ATTACHMENT0};
  glDrawBuffers(1, render_targets);
  auto status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "A35-RENDER fbo setup failed: %dx%d status=0x%x", w, h, (unsigned)status);
    ASSERT(false);
  }

  result.multisample_count = 1;
  result.multisampled = false;
  result.is_window = false;
  result.width = w;
  result.height = h;
  return result;
}

// True when the bucket carries content beyond the empty 4-tag shape
// (NEXT qwc=0 → CALL qwc=0 into the default-regs chain). Peeks a COPY of
// the follower; the real follower is untouched.
bool bucket_has_data(DmaFollower dma, u32 next_bucket) {
  auto t0 = dma.current_tag();
  if (!(t0.kind == DmaTag::Kind::NEXT && t0.qwc == 0)) {
    return true;
  }
  dma.read_and_advance();
  if (dma.current_tag_offset() == next_bucket) {
    return false;
  }
  auto t1 = dma.current_tag();
  return !(t1.kind == DmaTag::Kind::CALL && t1.qwc == 0);
}
}  // namespace

AndroidOpenGLRenderer::AndroidOpenGLRenderer(std::shared_ptr<TexturePool> texture_pool,
                                             std::shared_ptr<Loader> loader)
    : m_render_state(texture_pool, loader, g_game_version) {
  lg::info("A35-RENDER AndroidOpenGLRenderer init: game={} GL_VERSION={} GL_RENDERER={}",
           (int)g_game_version, (const char*)glGetString(GL_VERSION),
           (const char*)glGetString(GL_RENDERER));

  // screen-space quad for the pcrtc window blit (desktop ctor parity).
  glGenVertexArrays(1, &m_screen_vao);
  glGenBuffers(1, &m_screen_vbo);
  struct Vertex {
    float x, y;
  };
  constexpr std::array<Vertex, 4> vertices = {
      Vertex{-1, -1},
      Vertex{-1, 1},
      Vertex{1, -1},
      Vertex{1, 1},
  };
  glBindVertexArray(m_screen_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_screen_vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Vertex) * 4, vertices.data(), GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_TRUE, sizeof(Vertex), nullptr);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);

  // Common (GAME.fr3) textures: font, hud, common sprites. Without this
  // every slot the game links resolves to the checkerboard placeholder.
  if (m_render_state.loader) {
    m_common_level = &m_render_state.loader->load_common(*m_render_state.texture_pool, "GAME");
    lg::info("A35-RENDER common level (GAME.fr3) loaded");
  } else {
    __android_log_print(ANDROID_LOG_WARN, kLogTag,
                        "A35-RENDER no loader — textures will be placeholders");
  }

  if (g_game_version == GameVersion::Jak2) {
    init_bucket_renderers_jak2();
  } else {
    init_bucket_renderers_jak1();
  }
}

// Defaulted here (not in the header) so the unique_ptr<EyeRenderer> member is
// destroyed where EyeRenderer is complete (EyeRenderer.h is included above).
AndroidOpenGLRenderer::~AndroidOpenGLRenderer() = default;

void AndroidOpenGLRenderer::init_bucket_renderers_jak1() {
  using namespace jak1;
  m_bucket_renderers.resize((int)BucketId::MAX_BUCKETS);
  m_bucket_ported.resize((int)BucketId::MAX_BUCKETS, false);
  m_skip_logged.resize((int)BucketId::MAX_BUCKETS, false);

  auto set_renderer = [&](std::unique_ptr<BucketRenderer> r, BucketId id, bool ported) {
    m_bucket_ported.at((int)id) = ported;
    m_bucket_renderers.at((int)id) = std::move(r);
  };

  // Texture upload buckets — the same eleven slots the desktop jak1 table
  // fills with TextureUploadHandler. No TextureAnimator on jak1 (desktop
  // passes the null shared_ptr too).
  std::shared_ptr<TextureAnimator> no_animator;
  for (auto id : {BucketId::TFRAG_TEX_LEVEL0, BucketId::TFRAG_TEX_LEVEL1,
                  BucketId::SHRUB_TEX_LEVEL0, BucketId::SHRUB_TEX_LEVEL1,
                  BucketId::ALPHA_TEX_LEVEL0, BucketId::ALPHA_TEX_LEVEL1,
                  BucketId::PRIS_TEX_LEVEL0, BucketId::PRIS_TEX_LEVEL1,
                  BucketId::WATER_TEX_LEVEL0, BucketId::WATER_TEX_LEVEL1,
                  BucketId::PRE_SPRITE_TEX}) {
    set_renderer(std::make_unique<TextureUploadHandler>(fmt::format("tex-{}", (int)id), (int)id,
                                                        no_animator),
                 id, true);
  }

  // Eye renderer — both a bucket renderer and the handler the tex buckets
  // hand eye-dma to via render_state->eye_renderer.
  {
    auto eye = std::make_unique<EyeRenderer>("common-pris-eyes", (int)BucketId::MERC_EYES_AFTER_PRIS);
    m_render_state.eye_renderer = eye.get();
    set_renderer(std::move(eye), BucketId::MERC_EYES_AFTER_PRIS, true);
  }

  // A36 — sky + terrain: the first REAL visible content of the boot (the
  // logo/title camera flythrough over village1). Mirrors the desktop jak1
  // table: SkyRenderer at SKY_DRAW, SkyBlendHandler at the two
  // sky-blend/tfrag-trans buckets, TFragment (normal+lowres / dirt / ice /
  // trans kinds) at the tfrag buckets. anim-slot array: jak1 has no
  // TextureAnimator (desktop passes the null animator), so an empty static
  // slot vector mirrors the no-animator state.
  // GLES has no glMultiDrawElements — take the renderers' single-draw path
  // (plain glDrawElements per draw), same switch the desktop exposes for
  // drivers without multidraw.
  m_render_state.no_multidraw = true;
  // Gperf-batching: merge state-identical contiguous draws into one
  // glDrawElements (the device is draw-call-submission bound — 571 draws
  // ~20ms buckets_ms on Geyser Rock). Live A/B kill switch:
  // adb shell setprop debug.opengoal.perf.nobatch 1
  m_render_state.batch_singledraw = true;
  // Gperf-particles: lean the fire-heavy sprite path + cache per-draw GL state
  // in the tfrag-family loops (device is CPU/submission bound). Live A/B kill
  // switches: adb shell setprop debug.opengoal.perf.nospritelean 1 /
  // debug.opengoal.perf.nostatecache 1.
  m_render_state.perf_sprite_lean = true;
  m_render_state.perf_state_cache = true;
  // Gperf-particles (round 2): per-instance sprite path (jak1 only). Live A/B
  // kill switch: adb shell setprop debug.opengoal.perf.noinstance 1.
  m_render_state.perf_sprite_instance = true;
  // Gperf-particles2: cache Shrub's static single-draw index list across frames
  // (image-invariant, KEPT). The TOD ping-pong is DROPPED (flicker under a moving
  // clock) — init it OFF; the per-frame gate (perf_opt_in '2') keeps it off unless
  // explicitly reproducing the known-bad control. Kill switch for shrub idx:
  // adb shell setprop debug.opengoal.perf.noshrubidx 1.
  m_render_state.perf_tod_pingpong = false;
  m_render_state.perf_shrub_static_idx = true;
  std::shared_ptr<SkyBlendGPU> sky_gpu_blender;
  std::shared_ptr<SkyBlendCPU> sky_cpu_blender;
  {
    static const std::vector<GLuint> s_no_anim_slots;
    sky_gpu_blender = std::make_shared<SkyBlendGPU>();
    sky_cpu_blender = std::make_shared<SkyBlendCPU>();
    std::vector<tfrag3::TFragmentTreeKind> normal_tfrags = {tfrag3::TFragmentTreeKind::NORMAL,
                                                            tfrag3::TFragmentTreeKind::LOWRES};
    std::vector<tfrag3::TFragmentTreeKind> dirt_tfrags = {tfrag3::TFragmentTreeKind::DIRT};
    std::vector<tfrag3::TFragmentTreeKind> ice_tfrags = {tfrag3::TFragmentTreeKind::ICE};
    std::vector<tfrag3::TFragmentTreeKind> trans_tfrags = {tfrag3::TFragmentTreeKind::TRANS};

    set_renderer(std::make_unique<SkyRenderer>("sky", (int)BucketId::SKY_DRAW), BucketId::SKY_DRAW,
                 true);
    set_renderer(std::make_unique<TFragment>("l0-tfrag", (int)BucketId::TFRAG_LEVEL0,
                                             normal_tfrags, false, 0, &s_no_anim_slots),
                 BucketId::TFRAG_LEVEL0, true);
    set_renderer(std::make_unique<TFragment>("l1-tfrag", (int)BucketId::TFRAG_LEVEL1,
                                             normal_tfrags, false, 1, &s_no_anim_slots),
                 BucketId::TFRAG_LEVEL1, true);
    set_renderer(
        std::make_unique<SkyBlendHandler>("l0-sky-blend", (int)BucketId::TFRAG_TRANS0_AND_SKY_BLEND_LEVEL0,
                                          0, sky_gpu_blender, sky_cpu_blender, &s_no_anim_slots),
        BucketId::TFRAG_TRANS0_AND_SKY_BLEND_LEVEL0, true);
    set_renderer(
        std::make_unique<SkyBlendHandler>("l1-sky-blend", (int)BucketId::TFRAG_TRANS1_AND_SKY_BLEND_LEVEL1,
                                          1, sky_gpu_blender, sky_cpu_blender, &s_no_anim_slots),
        BucketId::TFRAG_TRANS1_AND_SKY_BLEND_LEVEL1, true);
    set_renderer(std::make_unique<TFragment>("l0-tfrag-dirt", (int)BucketId::TFRAG_DIRT_LEVEL0,
                                             dirt_tfrags, false, 0, &s_no_anim_slots),
                 BucketId::TFRAG_DIRT_LEVEL0, true);
    set_renderer(std::make_unique<TFragment>("l1-tfrag-dirt", (int)BucketId::TFRAG_DIRT_LEVEL1,
                                             dirt_tfrags, false, 1, &s_no_anim_slots),
                 BucketId::TFRAG_DIRT_LEVEL1, true);
    set_renderer(std::make_unique<TFragment>("l0-tfrag-ice", (int)BucketId::TFRAG_ICE_LEVEL0,
                                             ice_tfrags, false, 0, &s_no_anim_slots),
                 BucketId::TFRAG_ICE_LEVEL0, true);
    set_renderer(std::make_unique<TFragment>("l1-tfrag-ice", (int)BucketId::TFRAG_ICE_LEVEL1,
                                             ice_tfrags, false, 1, &s_no_anim_slots),
                 BucketId::TFRAG_ICE_LEVEL1, true);
  }

  // village-tie — instanced TIE (the dense built detail of Sandover village:
  // huts, fences, props, wooden platforms drawn through the TIE instance
  // system). The jak1 desktop table backs TIE_LEVEL0/1 with a single
  // Tie3WithEnvmapJak1 renderer per level (TIE + TIE-envmap in one); the level
  // index (0/1) selects the per-level TIE tree the loader filled. These buckets
  // were wired as SkipRenderer (unported) and Tie3.cpp was never compiled into
  // the Android build, so the populated TIE_LEVEL0/1 buckets were dropped every
  // frame (A35-RENDER skip bucket=l1-tie id=16, fired only when the bucket has
  // data). The time-of-day LUT is already a Wx1 2D texture matching the shared
  // TFRAG3 shader (commit 9fe0be120); the only remaining GLES blocker was the
  // glPrimitiveRestartIndex calls, now gated to GL_PRIMITIVE_RESTART_FIXED_INDEX
  // under __ANDROID__ in Tie3.cpp (same fix as TFragment/Shrub). Desktop jak1
  // parity (OpenGLRenderer.cpp init_bucket_renderers_jak1: Tie3WithEnvmapJak1).
  set_renderer(std::make_unique<Tie3WithEnvmapJak1>("l0-tie", (int)BucketId::TIE_LEVEL0, 0),
               BucketId::TIE_LEVEL0, true);
  set_renderer(std::make_unique<Tie3WithEnvmapJak1>("l1-tie", (int)BucketId::TIE_LEVEL1, 1),
               BucketId::TIE_LEVEL1, true);

  // village-missing — shrub (the dense foliage class: palm trees, plants,
  // bushes, ground grass over Sandover village). The shrub DMA is built by
  // pure GOAL code (shrubbery.gc draw-drawable-tree-instance-shrub ->
  // add-pc-tfrag3-data; no mips2c builder, "completely rewritten for PC"), so
  // the only thing missing was the Shrub bucket renderer itself — it was
  // wired as a SkipRenderer (unported) and the populated SHRUB_NORMAL_LEVEL0/1
  // buckets were dropped every frame (A35-RENDER skip bucket=l0-shrub/l1-shrub).
  // Its single GLES blocker (the GL_TEXTURE_1D time-of-day LUT) is fixed in
  // Shrub.cpp (Wx1 2D, matching TFragment/TIE). Desktop jak1-table parity
  // (OpenGLRenderer.cpp init_bucket_renderers_jak1: init_bucket_renderer<Shrub>).
  set_renderer(std::make_unique<Shrub>("l0-shrub", (int)BucketId::SHRUB_NORMAL_LEVEL0),
               BucketId::SHRUB_NORMAL_LEVEL0, true);
  set_renderer(std::make_unique<Shrub>("l1-shrub", (int)BucketId::SHRUB_NORMAL_LEVEL1),
               BucketId::SHRUB_NORMAL_LEVEL1, true);

  // F1a — foreground: Merc2 (village actors + the floating JAK AND DAXTER
  // logo, a merc model) at the eight jak1 merc buckets, Generic2 at the ten
  // generic buckets — the same shared-core + per-bucket-renderer shape as
  // the desktop jak1 table. Ownership: the bucket renderers' shared_ptrs.
  {
    static const std::vector<GLuint> s_fg_no_anim_slots;
    auto merc2 = std::make_shared<Merc2>(m_render_state.shaders, &s_fg_no_anim_slots);
    auto generic2 = std::make_shared<Generic2>(m_render_state.shaders);
    m_generic2 = generic2;
    const std::pair<BucketId, const char*> merc_buckets[] = {
        {BucketId::MERC_TFRAG_TEX_LEVEL0, "l0-tfrag-merc"},
        {BucketId::MERC_TFRAG_TEX_LEVEL1, "l1-tfrag-merc"},
        {BucketId::MERC_AFTER_ALPHA, "common-alpha-merc"},
        {BucketId::MERC_PRIS_LEVEL0, "l0-pris-merc"},
        {BucketId::MERC_PRIS_LEVEL1, "l1-pris-merc"},
        {BucketId::MERC_AFTER_PRIS, "common-pris-merc"},
        {BucketId::MERC_WATER_LEVEL0, "l0-water-merc"},
        {BucketId::MERC_WATER_LEVEL1, "l1-water-merc"},
    };
    for (auto& [id, name] : merc_buckets) {
      set_renderer(std::make_unique<Merc2BucketRenderer>(name, (int)id, merc2), id, true);
    }
    const std::pair<BucketId, const char*> generic_buckets[] = {
        {BucketId::GENERIC_TFRAG_TEX_LEVEL0, "l0-tfrag-generic"},
        {BucketId::GENERIC_TFRAG_TEX_LEVEL1, "l1-tfrag-generic"},
        {BucketId::SHRUB_GENERIC_LEVEL0, "l0-shrub-generic"},
        {BucketId::SHRUB_GENERIC_LEVEL1, "l1-shrub-generic"},
        {BucketId::GENERIC_ALPHA, "common-alpha-generic"},
        {BucketId::GENERIC_PRIS_LEVEL0, "l0-pris-generic"},
        {BucketId::GENERIC_PRIS_LEVEL1, "l1-pris-generic"},
        {BucketId::GENERIC_PRIS, "common-pris-generic"},
        {BucketId::GENERIC_WATER_LEVEL0, "l0-water-generic"},
        {BucketId::GENERIC_WATER_LEVEL1, "l1-water-generic"},
    };
    for (auto& [id, name] : generic_buckets) {
      set_renderer(std::make_unique<Generic2BucketRenderer>(name, (int)id, generic2,
                                                            Generic2::Mode::NORMAL),
                   id, true);
    }
    lg::info("A35-RENDER F1a foreground wired: merc buckets=8 generic buckets=10");
  }

  // F1a — sprite (particles): desktop jak1 table line 865 parity.
  set_renderer(std::make_unique<Sprite3>("sprite", (int)BucketId::SPRITE), BucketId::SPRITE, true);

  // Gwater — ocean/water: the title flythrough flies over village1, which
  // carries the ocean. OceanMidAndFar handles the ocean-mid-far bucket (it owns
  // the OceanTexture render-to-texture + OceanMid mesh + the simple ocean-far
  // quad); OceanNear handles the ocean-near bucket. Both consume the ocean DMA
  // built by the now-enabled ocean mips2c builders (init-ocean-far-regs /
  // render-ocean-quad / ocean-interp-wave / ocean-generate-verts). Desktop jak1
  // table parity (OpenGLRenderer.cpp init_bucket_renderers_jak1).
  set_renderer(std::make_unique<OceanMidAndFar>("ocean-mid-far", (int)BucketId::OCEAN_MID_AND_FAR),
               BucketId::OCEAN_MID_AND_FAR, true);
  set_renderer(std::make_unique<OceanNear>("ocean-near", (int)BucketId::OCEAN_NEAR),
               BucketId::OCEAN_NEAR, true);

  // DirectRenderer — the desktop jak1 direct buckets, same batch sizes.
  set_renderer(std::make_unique<DirectRenderer>("debug", (int)BucketId::DEBUG, 0x20000),
               BucketId::DEBUG, true);
  set_renderer(
      std::make_unique<DirectRenderer>("debug-no-zbuf", (int)BucketId::DEBUG_NO_ZBUF, 0x8000),
      BucketId::DEBUG_NO_ZBUF, true);
  set_renderer(std::make_unique<DirectRenderer>("subtitle", (int)BucketId::SUBTITLE, 6000),
               BucketId::SUBTITLE, true);

  // Everything else: skip with a one-time named log (handled in dispatch).
  // Desktop names kept so the skip logs name the real renderer that's missing.
  const std::pair<BucketId, const char*> unported[] = {
      // TIE_LEVEL0/1 are now ported (Tie3WithEnvmapJak1 wired above).
      // SHRUB_NORMAL_LEVEL0/1 are now ported (Shrub renderer wired above).
      {BucketId::SHADOW, "shadow"},
      {BucketId::DEPTH_CUE, "depth-cue"},
  };
  for (auto& [id, name] : unported) {
    set_renderer(std::make_unique<SkipRenderer>(name, (int)id), id, false);
  }

  // remaining slots (0,1,2 + the unused gaps): desktop uses
  // EmptyBucketRenderer, which ASSERTs emptiness — keep that, it's a real
  // chain-shape check.
  for (size_t i = 0; i < m_bucket_renderers.size(); i++) {
    if (!m_bucket_renderers[i]) {
      m_bucket_renderers[i] =
          std::make_unique<EmptyBucketRenderer>(fmt::format("bucket-{}", i), (int)i);
      m_bucket_ported[i] = true;  // empty buckets are fully handled
    }
    m_bucket_renderers[i]->init_shaders(m_render_state.shaders);
    m_bucket_renderers[i]->init_textures(*m_render_state.texture_pool, GameVersion::Jak1);
  }
  // The sky blenders are not bucket renderers — desktop inits their VRAM
  // textures explicitly after the bucket loop (OpenGLRenderer.cpp:883).
  // Without this, SkyBlendCPU::do_sky_blends hands a null GpuTexture to
  // move_existing_to_vram (A36 run-23 crash).
  sky_cpu_blender->init_textures(*m_render_state.texture_pool, GameVersion::Jak1);
  sky_gpu_blender->init_textures(*m_render_state.texture_pool, GameVersion::Jak1);
  lg::info("A35-RENDER jak1 bucket table ready: {} buckets, direct=3 tex=11 eye=1 skip={}",
           m_bucket_renderers.size(), sizeof(unported) / sizeof(unported[0]));
}

// Gjak2-render: jak2 bucket table. The jak2 DMA chain starts at bucket 0
// directly (no initial default-regs CALL like jak1), so the renderers ONLY
// need to consume their bucket segment. Mirrors the desktop
// OpenGLRenderer::init_bucket_renderers_jak2 for the classes actually compiled
// into the Android build (TextureUploadHandler + DirectRenderer are the
// game-agnostic first-content workhorses). Every other bucket defaults to a
// SkipRenderer, which consumes its segment exactly like the jak1 android skip
// path (walk read_and_advance until next_bucket), keeping next_bucket in sync.
// Classes upstream jak2 uses that are NOT in the Android CMake TU list
// (VisDataHandler, BlitDisplays, Shadow2, Warp, ProgressRenderer) stay as skip
// this round — no new TUs are pulled into CMake here.
void AndroidOpenGLRenderer::init_bucket_renderers_jak2() {
  using namespace jak2;
  m_bucket_renderers.resize((int)BucketId::MAX_BUCKETS);
  m_bucket_ported.assign((int)BucketId::MAX_BUCKETS, false);
  m_skip_logged.assign((int)BucketId::MAX_BUCKETS, false);

  // GLES single-draw + the perf paths the jak1 table also opts into. These are
  // renderer-behavior switches, not game-specific, so keep parity.
  m_render_state.no_multidraw = true;
  m_render_state.batch_singledraw = true;
  m_render_state.perf_state_cache = true;

  auto set_renderer = [&](std::unique_ptr<BucketRenderer> r, BucketId id, bool ported) {
    m_bucket_ported.at((int)id) = ported;
    m_bucket_renderers.at((int)id) = std::move(r);
  };

  // Gjak2-vis: construct the jak2 TextureAnimator (mirrors desktop
  // OpenGLRenderer.cpp). It reads the common (GAME.fr3) level textures by name.
  // Kill-switch: debug.opengoal.texanim=0 leaves it null (the previously
  // proven-safe "no animator" state) so the null path can be restored on device
  // without a rebuild. Every JAK2 TextureUploadHandler below gets this animator.
  {
    char ta[PROP_VALUE_MAX] = {0};
    __system_property_get("debug.opengoal.texanim", ta);
    if (ta[0] == '0') {
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "GJ2VIS texanim DISABLED by prop");
    } else if (m_common_level) {
      m_texture_animator = std::make_shared<TextureAnimator>(
          m_render_state.shaders, m_common_level, GameVersion::Jak2);
      __android_log_print(ANDROID_LOG_INFO, kLogTag, "GJ2VIS texanim LIVE (jak2)");
    } else {
      __android_log_print(ANDROID_LOG_WARN, kLogTag,
                          "GJ2VIS texanim NULL — no common level");
    }
  }
  // The animator (or a null shared_ptr) is passed to every jak2
  // TextureUploadHandler, mirroring upstream jak2's m_texture_animator.
  std::shared_ptr<TextureAnimator>& no_animator = m_texture_animator;

  // Gjak2-vis: the anim-slot array. Upstream jak2 passes
  // m_texture_animator->slots() (== nullptr when there is no animator). When the
  // animator is live we forward its real slots; otherwise fall back to a static
  // empty vector — the same null-animator shape the jak1 android table proves
  // safe on this device.
  static const std::vector<GLuint> s_no_anim_slots;
  const std::vector<GLuint>* anim_slots =
      m_texture_animator ? m_texture_animator->slots() : &s_no_anim_slots;

  // Gjak2-render (3D): shared foreground cores, mirroring upstream jak2's
  // m_merc2 / m_generic2. Merc2 takes the anim-slot array (nullptr-equivalent
  // here). Generic2 owns the translucent-merc path. Both are proven on the jak1
  // android table.
  auto merc2 = std::make_shared<Merc2>(m_render_state.shaders, anim_slots);
  auto generic2 = std::make_shared<Generic2>(m_render_state.shaders);
  m_generic2 = generic2;

  // Helper: register a renderer AND return its raw pointer (upstream's
  // init_bucket_renderer returns the owned pointer so the Tie3AnotherCategory
  // variants can share the base Tie3's loaded per-level data).
  auto set_renderer_ret = [&](auto r, BucketId id, bool ported) {
    auto* raw = r.get();
    set_renderer(std::move(r), id, ported);
    return raw;
  };

  // --- TextureUploadHandler + the 3D background/foreground families: every
  // jak2 bucket upstream registers, mirroring init_bucket_renderers_jak2
  // names/ids/ctor-args for the classes compiled into the Android build
  // (TextureUploadHandler, DirectRenderer, TFragment, Tie3/Tie3AnotherCategory,
  // Shrub, Merc2, Generic2, OceanMidAndFar/OceanNear, Sprite3, EyeRenderer). ---
  set_renderer(std::make_unique<TextureUploadHandler>("tex-lcom-sky-pre",
                                                      (int)BucketId::TEX_LCOM_SKY_PRE, no_animator),
               BucketId::TEX_LCOM_SKY_PRE, true);

#define GET_BUCKET_ID_FOR_LIST(bkt1, bkt2, idx) \
  ((int)(bkt1) + ((int)(bkt2) - (int)(bkt1)) * (idx))
  int tfrag_count = 0, tie_count = 0, shrub_count = 0, merc_count = 0, generic_count = 0;
  for (int i = 0; i < LEVEL_MAX; ++i) {
    auto bkt = [&](BucketId b0, BucketId b1) {
      return (BucketId)GET_BUCKET_ID_FOR_LIST(b0, b1, i);
    };

    // --- tfrag band ---
    set_renderer(std::make_unique<TextureUploadHandler>(
                     fmt::format("tex-l{}-tfrag", i),
                     (int)bkt(BucketId::TEX_L0_TFRAG, BucketId::TEX_L1_TFRAG), no_animator),
                 bkt(BucketId::TEX_L0_TFRAG, BucketId::TEX_L1_TFRAG), true);
    set_renderer(std::make_unique<TFragment>(
                     fmt::format("tfrag-l{}-tfrag", i),
                     (int)bkt(BucketId::TFRAG_L0_TFRAG, BucketId::TFRAG_L1_TFRAG),
                     std::vector{tfrag3::TFragmentTreeKind::NORMAL}, false, i, anim_slots),
                 bkt(BucketId::TFRAG_L0_TFRAG, BucketId::TFRAG_L1_TFRAG), true);
    tfrag_count++;
    // Base Tie3 owns this level's TIE tree; the Tie3AnotherCategory variants
    // (envmap/trans/water) reference it via the raw pointer, exactly as upstream.
    Tie3* tie = set_renderer_ret(
        std::make_unique<Tie3>(fmt::format("tie-l{}-tfrag", i),
                               (int)bkt(BucketId::TIE_L0_TFRAG, BucketId::TIE_L1_TFRAG), i,
                               anim_slots),
        bkt(BucketId::TIE_L0_TFRAG, BucketId::TIE_L1_TFRAG), true);
    tie_count++;
    set_renderer(std::make_unique<Tie3AnotherCategory>(
                     fmt::format("etie-l{}-tfrag", i),
                     (int)bkt(BucketId::ETIE_L0_TFRAG, BucketId::ETIE_L1_TFRAG), tie,
                     tfrag3::TieCategory::NORMAL_ENVMAP),
                 bkt(BucketId::ETIE_L0_TFRAG, BucketId::ETIE_L1_TFRAG), true);
    set_renderer(std::make_unique<Merc2BucketRenderer>(
                     fmt::format("merc-l{}-tfrag", i),
                     (int)bkt(BucketId::MERC_L0_TFRAG, BucketId::MERC_L1_TFRAG), merc2),
                 bkt(BucketId::MERC_L0_TFRAG, BucketId::MERC_L1_TFRAG), true);
    merc_count++;
    set_renderer(std::make_unique<Generic2BucketRenderer>(
                     fmt::format("gmerc-l{}-tfrag", i),
                     (int)bkt(BucketId::GMERC_L0_TFRAG, BucketId::GMERC_L1_TFRAG), generic2,
                     Generic2::Mode::NORMAL),
                 bkt(BucketId::GMERC_L0_TFRAG, BucketId::GMERC_L1_TFRAG), true);
    generic_count++;

    // --- shrub band ---
    set_renderer(std::make_unique<TextureUploadHandler>(
                     fmt::format("tex-l{}-shrub", i),
                     (int)bkt(BucketId::TEX_L0_SHRUB, BucketId::TEX_L1_SHRUB), no_animator),
                 bkt(BucketId::TEX_L0_SHRUB, BucketId::TEX_L1_SHRUB), true);
    set_renderer(std::make_unique<Shrub>(
                     fmt::format("shrub-l{}-shrub", i),
                     (int)bkt(BucketId::SHRUB_L0_SHRUB, BucketId::SHRUB_L1_SHRUB)),
                 bkt(BucketId::SHRUB_L0_SHRUB, BucketId::SHRUB_L1_SHRUB), true);
    shrub_count++;
    set_renderer(std::make_unique<Merc2BucketRenderer>(
                     fmt::format("merc-l{}-shrub", i),
                     (int)bkt(BucketId::MERC_L0_SHRUB, BucketId::MERC_L1_SHRUB), merc2),
                 bkt(BucketId::MERC_L0_SHRUB, BucketId::MERC_L1_SHRUB), true);
    set_renderer(std::make_unique<Generic2BucketRenderer>(
                     fmt::format("gmerc-l{}-shrub", i),
                     (int)bkt(BucketId::GMERC_L0_SHRUB, BucketId::GMERC_L1_SHRUB), generic2,
                     Generic2::Mode::NORMAL),
                 bkt(BucketId::GMERC_L0_SHRUB, BucketId::GMERC_L1_SHRUB), true);

    // --- alpha band ---
    set_renderer(std::make_unique<TextureUploadHandler>(
                     fmt::format("tex-l{}-alpha", i),
                     (int)bkt(BucketId::TEX_L0_ALPHA, BucketId::TEX_L1_ALPHA), no_animator),
                 bkt(BucketId::TEX_L0_ALPHA, BucketId::TEX_L1_ALPHA), true);
    set_renderer(std::make_unique<TFragment>(
                     fmt::format("tfrag-t-l{}-alpha", i),
                     (int)bkt(BucketId::TFRAG_T_L0_ALPHA, BucketId::TFRAG_T_L1_ALPHA),
                     std::vector{tfrag3::TFragmentTreeKind::TRANS}, false, i, anim_slots),
                 bkt(BucketId::TFRAG_T_L0_ALPHA, BucketId::TFRAG_T_L1_ALPHA), true);
    set_renderer(std::make_unique<Tie3AnotherCategory>(
                     fmt::format("tie-t-l{}-alpha", i),
                     (int)bkt(BucketId::TIE_T_L0_ALPHA, BucketId::TIE_T_L1_ALPHA), tie,
                     tfrag3::TieCategory::TRANS),
                 bkt(BucketId::TIE_T_L0_ALPHA, BucketId::TIE_T_L1_ALPHA), true);
    set_renderer(std::make_unique<Tie3AnotherCategory>(
                     fmt::format("etie-t-l{}-alpha", i),
                     (int)bkt(BucketId::ETIE_T_L0_ALPHA, BucketId::ETIE_T_L1_ALPHA), tie,
                     tfrag3::TieCategory::TRANS_ENVMAP),
                 bkt(BucketId::ETIE_T_L0_ALPHA, BucketId::ETIE_T_L1_ALPHA), true);
    set_renderer(std::make_unique<Merc2BucketRenderer>(
                     fmt::format("merc-l{}-alpha", i),
                     (int)bkt(BucketId::MERC_L0_ALPHA, BucketId::MERC_L1_ALPHA), merc2),
                 bkt(BucketId::MERC_L0_ALPHA, BucketId::MERC_L1_ALPHA), true);
    set_renderer(std::make_unique<Generic2BucketRenderer>(
                     fmt::format("gmerc-l{}-alpha", i),
                     (int)bkt(BucketId::GMERC_L0_ALPHA, BucketId::GMERC_L1_ALPHA), generic2,
                     Generic2::Mode::NORMAL),
                 bkt(BucketId::GMERC_L0_ALPHA, BucketId::GMERC_L1_ALPHA), true);

    // --- pris band ---
    set_renderer(std::make_unique<TextureUploadHandler>(
                     fmt::format("tex-l{}-pris", i),
                     (int)bkt(BucketId::TEX_L0_PRIS, BucketId::TEX_L1_PRIS), no_animator),
                 bkt(BucketId::TEX_L0_PRIS, BucketId::TEX_L1_PRIS), true);
    set_renderer(std::make_unique<Merc2BucketRenderer>(
                     fmt::format("merc-l{}-pris", i),
                     (int)bkt(BucketId::MERC_L0_PRIS, BucketId::MERC_L1_PRIS), merc2),
                 bkt(BucketId::MERC_L0_PRIS, BucketId::MERC_L1_PRIS), true);
    set_renderer(std::make_unique<Generic2BucketRenderer>(
                     fmt::format("gmerc-l{}-pris", i),
                     (int)bkt(BucketId::GMERC_L0_PRIS, BucketId::GMERC_L1_PRIS), generic2,
                     Generic2::Mode::NORMAL),
                 bkt(BucketId::GMERC_L0_PRIS, BucketId::GMERC_L1_PRIS), true);

    // --- pris2 band ---
    set_renderer(std::make_unique<TextureUploadHandler>(
                     fmt::format("tex-l{}-pris2", i),
                     (int)bkt(BucketId::TEX_L0_PRIS2, BucketId::TEX_L1_PRIS2), no_animator),
                 bkt(BucketId::TEX_L0_PRIS2, BucketId::TEX_L1_PRIS2), true);
    set_renderer(std::make_unique<Merc2BucketRenderer>(
                     fmt::format("merc-l{}-pris2", i),
                     (int)bkt(BucketId::MERC_L0_PRIS2, BucketId::MERC_L1_PRIS2), merc2),
                 bkt(BucketId::MERC_L0_PRIS2, BucketId::MERC_L1_PRIS2), true);
    set_renderer(std::make_unique<Generic2BucketRenderer>(
                     fmt::format("gmerc-l{}-pris2", i),
                     (int)bkt(BucketId::GMERC_L0_PRIS2, BucketId::GMERC_L1_PRIS2), generic2,
                     Generic2::Mode::NORMAL),
                 bkt(BucketId::GMERC_L0_PRIS2, BucketId::GMERC_L1_PRIS2), true);

    // --- water band ---
    set_renderer(std::make_unique<TextureUploadHandler>(
                     fmt::format("tex-l{}-water", i),
                     (int)bkt(BucketId::TEX_L0_WATER, BucketId::TEX_L1_WATER), no_animator),
                 bkt(BucketId::TEX_L0_WATER, BucketId::TEX_L1_WATER), true);
    set_renderer(std::make_unique<Merc2BucketRenderer>(
                     fmt::format("merc-l{}-water", i),
                     (int)bkt(BucketId::MERC_L0_WATER, BucketId::MERC_L1_WATER), merc2),
                 bkt(BucketId::MERC_L0_WATER, BucketId::MERC_L1_WATER), true);
    set_renderer(std::make_unique<Generic2BucketRenderer>(
                     fmt::format("gmerc-l{}-water", i),
                     (int)bkt(BucketId::GMERC_L0_WATER, BucketId::GMERC_L1_WATER), generic2,
                     Generic2::Mode::NORMAL),
                 bkt(BucketId::GMERC_L0_WATER, BucketId::GMERC_L1_WATER), true);
    set_renderer(std::make_unique<TFragment>(
                     fmt::format("tfrag-w-l{}-alpha", i),
                     (int)bkt(BucketId::TFRAG_W_L0_WATER, BucketId::TFRAG_W_L1_WATER),
                     std::vector{tfrag3::TFragmentTreeKind::WATER}, false, i, anim_slots),
                 bkt(BucketId::TFRAG_W_L0_WATER, BucketId::TFRAG_W_L1_WATER), true);
    set_renderer(std::make_unique<Tie3AnotherCategory>(
                     fmt::format("tie-w-l{}-water", i),
                     (int)bkt(BucketId::TIE_W_L0_WATER, BucketId::TIE_W_L1_WATER), tie,
                     tfrag3::TieCategory::WATER),
                 bkt(BucketId::TIE_W_L0_WATER, BucketId::TIE_W_L1_WATER), true);
    set_renderer(std::make_unique<Tie3AnotherCategory>(
                     fmt::format("etie-w-l{}-water", i),
                     (int)bkt(BucketId::ETIE_W_L0_WATER, BucketId::ETIE_W_L1_WATER), tie,
                     tfrag3::TieCategory::WATER_ENVMAP),
                 bkt(BucketId::ETIE_W_L0_WATER, BucketId::ETIE_W_L1_WATER), true);
  }
#undef GET_BUCKET_ID_FOR_LIST

  // lcom (level-common) band: upstream jak2 registers tex + merc + gmerc per
  // family, plus the ocean/sky-post/sprite tex. Mirror the classes compiled in.
  set_renderer(std::make_unique<TextureUploadHandler>("tex-lcom-tfrag",
                                                      (int)BucketId::TEX_LCOM_TFRAG, no_animator),
               BucketId::TEX_LCOM_TFRAG, true);
  set_renderer(std::make_unique<Merc2BucketRenderer>("merc-lcom-tfrag",
                                                     (int)BucketId::MERC_LCOM_TFRAG, merc2),
               BucketId::MERC_LCOM_TFRAG, true);
  set_renderer(std::make_unique<TextureUploadHandler>("tex-lcom-shrub",
                                                      (int)BucketId::TEX_LCOM_SHRUB, no_animator),
               BucketId::TEX_LCOM_SHRUB, true);
  set_renderer(std::make_unique<Merc2BucketRenderer>("merc-lcom-shrub",
                                                     (int)BucketId::MERC_LCOM_SHRUB, merc2),
               BucketId::MERC_LCOM_SHRUB, true);
  set_renderer(std::make_unique<Generic2BucketRenderer>("gmerc-lcom-tfrag",
                                                        (int)BucketId::GMERC_LCOM_TFRAG, generic2,
                                                        Generic2::Mode::NORMAL),
               BucketId::GMERC_LCOM_TFRAG, true);
  // SHADOW (Shadow2) is NOT compiled into the Android build — leave SkipRenderer.
  set_renderer(std::make_unique<TextureUploadHandler>("tex-lcom-pris",
                                                      (int)BucketId::TEX_LCOM_PRIS, no_animator),
               BucketId::TEX_LCOM_PRIS, true);
  set_renderer(std::make_unique<Merc2BucketRenderer>("merc-lcom-pris",
                                                     (int)BucketId::MERC_LCOM_PRIS, merc2),
               BucketId::MERC_LCOM_PRIS, true);
  set_renderer(std::make_unique<Generic2BucketRenderer>("gmerc-lcom-pris",
                                                        (int)BucketId::GMERC_LCOM_PRIS, generic2,
                                                        Generic2::Mode::NORMAL),
               BucketId::GMERC_LCOM_PRIS, true);
  set_renderer(std::make_unique<TextureUploadHandler>("tex-lcom-water",
                                                      (int)BucketId::TEX_LCOM_WATER, no_animator),
               BucketId::TEX_LCOM_WATER, true);
  set_renderer(std::make_unique<Merc2BucketRenderer>("merc-lcom-water",
                                                     (int)BucketId::MERC_LCOM_WATER, merc2),
               BucketId::MERC_LCOM_WATER, true);
  set_renderer(std::make_unique<TextureUploadHandler>("tex-lcom-sky-post",
                                                      (int)BucketId::TEX_LCOM_SKY_POST, no_animator),
               BucketId::TEX_LCOM_SKY_POST, true);

  // --- ocean: OceanMidAndFar (bucket right after SKY_DRAW) + OceanNear (310).
  // Both classes + CommonOceanRenderer are compiled into the Android build and
  // are proven on the jak1 android title flythrough. ---
  set_renderer(std::make_unique<OceanMidAndFar>("ocean-mid-far", (int)BucketId::OCEAN_MID_FAR),
               BucketId::OCEAN_MID_FAR, true);
  set_renderer(std::make_unique<OceanNear>("ocean-near", (int)BucketId::OCEAN_NEAR),
               BucketId::OCEAN_NEAR, true);

  // --- sprite / particles: Sprite3 (jak2 uses the (name,id) ctor, same as the
  // jak1 android SPRITE bucket). tex-all-sprite feeds it. ---
  set_renderer(std::make_unique<TextureUploadHandler>("tex-all-sprite",
                                                      (int)BucketId::TEX_ALL_SPRITE, no_animator),
               BucketId::TEX_ALL_SPRITE, true);
  set_renderer(std::make_unique<Sprite3>("particles", (int)BucketId::PARTICLES),
               BucketId::PARTICLES, true);
  // SHADOW2 (Shadow2) NOT compiled — SkipRenderer.
  // EFFECTS: upstream backs it with Generic2 in LIGHTNING mode (shared generic2).
  set_renderer(std::make_unique<Generic2BucketRenderer>("effects", (int)BucketId::EFFECTS, generic2,
                                                        Generic2::Mode::LIGHTNING),
               BucketId::EFFECTS, true);
  set_renderer(std::make_unique<TextureUploadHandler>("tex-all-warp",
                                                      (int)BucketId::TEX_ALL_WARP, no_animator),
               BucketId::TEX_ALL_WARP, true);
  // GMERC_WARP: upstream uses the Warp renderer (NOT compiled into the Android
  // build) — leave SkipRenderer.

  // These three upstream pass add_direct=true (DEBUG_NO_ZBUF1, TEX_ALL_MAP,
  // SUBTITLE are texture-upload buckets that also carry direct GIF data).
  const std::pair<BucketId, const char*> lcom_tex_direct[] = {
      {BucketId::DEBUG_NO_ZBUF1, "debug-no-zbuf1"},
      {BucketId::TEX_ALL_MAP, "tex-all-map"},
      {BucketId::SUBTITLE, "subtitle"},
  };
  for (auto& [id, name] : lcom_tex_direct) {
    set_renderer(std::make_unique<TextureUploadHandler>(name, (int)id, no_animator, true), id, true);
  }
  // PROGRESS: upstream's ProgressRenderer (DirectRenderer subclass, minimap
  // offscreen fb). Gjak2-visuals: the jak2 title "Press the Start Button" /
  // title menu text prints into this bucket (title-obs.gc print-game-text →
  // (bucket-id progress)); without it the title text never draws. The font
  // mips2c builders (draw-string-asm) are already live. GLES: no direct GL
  // calls; the 8_8_8_8_REV fb format is shimmed in opengl_utils.cpp.
  set_renderer(std::make_unique<ProgressRenderer>("progress", (int)BucketId::PROGRESS, 0x1000),
               BucketId::PROGRESS, true);

  // --- DirectRenderer: the jak2 buckets upstream backs with DirectRenderer,
  // same names/ids/batch sizes. SKY_DRAW is DirectRenderer on jak2 (not
  // SkyRenderer), so mirror that. ---
  const struct {
    BucketId id;
    const char* name;
    int batch;
  } direct_regs[] = {
      {BucketId::SKY_DRAW, "sky-draw", 1024},
      {BucketId::SCREEN_FILTER, "screen-filter", 256},
      {BucketId::DEBUG2, "debug2", 0x8000},
      {BucketId::DEBUG_NO_ZBUF2, "debug-no-zbuf2", 0x8000},
      {BucketId::DEBUG3, "debug3", 0x2000},
  };
  for (auto& d : direct_regs) {
    set_renderer(std::make_unique<DirectRenderer>(d.name, (int)d.id, d.batch), d.id, true);
  }
  int direct_count = (int)(sizeof(direct_regs) / sizeof(direct_regs[0]));

  // --- EyeRenderer: android has it for jak1; register it at upstream's jak2
  // bucket 0 slot (upstream constructs "eyes" with id 0 and stores it as
  // m_jak2_eye_renderer, wiring render_state.eye_renderer). Mirror that so the
  // merc eye-dma path resolves. ---
  {
    auto eye = std::make_unique<EyeRenderer>("eyes", 0);
    m_render_state.eye_renderer = eye.get();
    // The eye renderer is held as the eye handler only (its render() is invoked
    // via render_state->eye_renderer, not as a bucket). Store it so it isn't
    // destroyed.
    m_jak2_eye_renderer = std::move(eye);
    m_jak2_eye_renderer->init_shaders(m_render_state.shaders);
    m_jak2_eye_renderer->init_textures(*m_render_state.texture_pool, GameVersion::Jak2);
  }

  // Gjak2-visuals: the REAL VisDataHandler at BUCKET_2 (upstream jak2 slot).
  // Beyond the per-level vis strings (occlusion culling), its vif0 memcpy is
  // the ONLY writer of render_state->fog_color on the jak2 path — the earlier
  // SkipRenderer left fog_color {0,0,0,0}, zeroing every fog uniform (tfrag/
  // tie/shrub/merc/generic/ocean/sky) and white-washing the scene (proven by
  // the GJ2VIS-TOD x86-vs-device state dump: itimes/tod identical, fogcol
  // 00133300 vs 00000000). Data-only renderer, no GL calls.
  set_renderer(std::make_unique<VisDataHandler>("vis", (int)BucketId::BUCKET_2),
               BucketId::BUCKET_2, true);

  // Everything else: SkipRenderer. Its render() walks read_and_advance until
  // render_state->next_bucket, consuming the segment and keeping the dispatch
  // in sync regardless of the bucket's content — the same consume-the-segment
  // mechanism the jak1 android skip path uses. Buckets upstream jak2 renders
  // with classes NOT compiled into the Android build fall here this round:
  //   BUCKET_3 (BlitDisplays), SHADOW/SHADOW2
  //   (Shadow2), GMERC_WARP (Warp), PROGRESS (ProgressRenderer), and the
  //   EMERC_* buckets (upstream jak2 has no EMERC registration — they are
  //   EmptyBucketRenderer'd there too). The dispatch logs each ONE the first
  //   time it carries data.
  int skip_count = 0;
  for (size_t i = 0; i < m_bucket_renderers.size(); i++) {
    if (!m_bucket_renderers[i]) {
      m_bucket_renderers[i] =
          std::make_unique<SkipRenderer>(fmt::format("skip-bucket-{}", i), (int)i);
      m_bucket_ported[i] = false;  // counts as a skip in the stats/logs
      skip_count++;
    }
    m_bucket_renderers[i]->init_shaders(m_render_state.shaders);
    m_bucket_renderers[i]->init_textures(*m_render_state.texture_pool, GameVersion::Jak2);
  }

  lg::info(
      "A35-RENDER jak2 bucket table ready: {} buckets, tfrag={} tie={} shrub={} merc-cores={} "
      "generic-cores={} direct={} eye=1 skip={} (unported classes SkipRenderer'd)",
      m_bucket_renderers.size(), tfrag_count, tie_count, shrub_count, merc_count, generic_count,
      direct_count, skip_count);
}

u32 AndroidOpenGLRenderer::count_chain_bytes(DmaFollower dma) {
  // read_and_advance only computes offsets (no copies) — a counting walk
  // over the whole chain is cheap and gives an honest chain_bytes figure.
  u32 total = 0;
  u32 guard = 0;
  while (!dma.ended() && guard++ < 1000000) {
    total += dma.read_and_advance().size_bytes;
  }
  return total;
}

void AndroidOpenGLRenderer::render(DmaFollower dma, const AndroidRenderOptions& settings) {
  m_profiler.clear();
  m_render_state.reset();
  m_render_state.ee_main_memory = g_ee_main_mem;
  m_render_state.offset_of_s7 = offset_of_s7();

  m_stats.frame_idx++;

  // Gperf-batching A/B kill switch: debug.opengoal.perf.nobatch=1 restores
  // the exact pre-batching per-draw path (for on-device parity/perf compare).
  if ((m_stats.frame_idx % 120) == 1) {
    char nb[PROP_VALUE_MAX] = {0};
    __system_property_get("debug.opengoal.perf.nobatch", nb);
    m_render_state.batch_singledraw = (nb[0] != '1');
    // Gperf-particles2 (2026-07-05): the Gperf-particles opts were re-earned ONE AT A
    // TIME after the v5 owner regression, validated under REAL moving gameplay with a
    // NATURALLY-advancing clock (video-inspected for geometry pop + TOD flicker vs a
    // known-bad control). Outcome:
    //  KEPT (proven image-invariant / byte-identical to the v4 renderer) — DEFAULT ON,
    //  live kill switch (=1 restores the exact pre-phase v4 path for A/B parity/perf):
    //    sprite-lean, state-cache, sprite-instance, shrub-static-idx, 2d-NEON.
    //  DROPPED (corrupt the image) — DEFAULT OFF; opt-in '2' ONLY reproduces the
    //  KNOWN-BAD control that proves the video inspection actually detects the bug:
    //    tod-pingpong -> samples the previous ping-pong buffer while the clock moves
    //                    => day/night palette FLICKER (owner v5 symptom). See report.
    //    tod-skip     -> byte-identical, but itimes changes every moving-clock frame
    //                    so it ~never fires => no real-gameplay gain (dropped).
    //    GOAL/GL overlap (android_gfx.cpp) -> races merc-mod/texanim LIVE-memory reads
    //                    against the next frame's GOAL build => geometry POP. Stays OFF.
    auto perf_on_kill = [](const char* prop) {  // DEFAULT ON; '1' restores the v4 path
      char v[PROP_VALUE_MAX] = {0};
      __system_property_get(prop, v);
      return v[0] != '1';
    };
    auto perf_opt_in = [](const char* prop) {  // DEFAULT OFF; '2' = known-bad control
      char v[PROP_VALUE_MAX] = {0};
      __system_property_get(prop, v);
      return v[0] == '2';
    };
    m_render_state.perf_sprite_lean      = perf_on_kill("debug.opengoal.perf.nospritelean");
    m_render_state.perf_state_cache      = perf_on_kill("debug.opengoal.perf.nostatecache");
    m_render_state.perf_sprite_instance  = perf_on_kill("debug.opengoal.perf.noinstance");
    m_render_state.perf_shrub_static_idx = perf_on_kill("debug.opengoal.perf.noshrubidx");
    m_render_state.perf_tod_pingpong     = perf_opt_in("debug.opengoal.perf.notodpp");
    m_render_state.perf_tod_skip         = perf_opt_in("debug.opengoal.perf.notodskip");
    // 2d-NEON sparticle fast-path: DEFAULT ON, kill with '1'. g_perf_2dvec_off=true => OFF.
    g_perf_2dvec_off.store(!perf_on_kill("debug.opengoal.perf.no2dvec"), std::memory_order_relaxed);
  }

  m_stats.chain_bytes = count_chain_bytes(dma);
  m_stats.buckets_with_data = 0;
  m_stats.buckets_drawn = 0;
  m_stats.buckets_skipped = 0;

  {
    auto prof = m_profiler.root()->make_scoped_child("frame-setup");
    setup_frame(settings);
  }

  if (m_render_state.loader) {
    auto prof = m_profiler.root()->make_scoped_child("loader");
    if (m_last_pmode_alp == 0 && settings.pmode_alp_register != 0) {
      m_render_state.loader->update_blocking(*m_render_state.texture_pool);
    } else {
      m_render_state.loader->update(*m_render_state.texture_pool);
    }
  }

  {
    auto prof = m_profiler.root()->make_scoped_child("buckets");
    m_render_state.version = g_game_version;
    m_render_state.frame_idx++;
    if (g_game_version == GameVersion::Jak2) {
      dispatch_buckets_jak2(dma, prof);
    } else {
      dispatch_buckets_jak1(dma, prof);
    }
    // Gjak2-vis: per-frame stale-texture sweep (mirrors desktop OpenGLRenderer).
    // If no animation requests were made this frame, assume the level unloaded
    // and reset the animated textures.
    if (m_texture_animator) {
      m_texture_animator->clear_stale_textures(m_render_state.frame_idx);
    }
    m_stats.buckets_cpu_s = prof.get_elapsed_time();
  }

  // A36 probe: the FBO content at frame 100/600 — distinguishes "geometry
  // drew black" from "blit lost it" (run-25: 64k tris/frame, black screen).
  if (m_stats.frame_idx == 100 || m_stats.frame_idx == 600) {
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo_state.render_buffer.fbo_id);
    const int px = m_fbo_state.render_buffer.width / 2;
    const int py = m_fbo_state.render_buffer.height / 2;
    unsigned char c[4 * 4] = {0};
    glReadPixels(px, py, 2, 2, GL_RGBA, GL_UNSIGNED_BYTE, c);
    unsigned char t[4 * 4] = {0};
    glReadPixels(px / 2, py + py / 2, 2, 2, GL_RGBA, GL_UNSIGNED_BYTE, t);
    __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                        "A36-FBO-PROBE frame=%llu center=%02x%02x%02x%02x %02x%02x%02x%02x "
                        "upper=%02x%02x%02x%02x alp=%.3f",
                        (unsigned long long)m_stats.frame_idx, c[0], c[1], c[2], c[3], c[4], c[5],
                        c[6], c[7], t[0], t[1], t[2], t[3], settings.pmode_alp_register);
  }
  {
    auto prof = m_profiler.root()->make_scoped_child("pcrtc");
    do_pcrtc_effects(settings.pmode_alp_register, &m_render_state, prof);
    m_stats.pcrtc_cpu_s = prof.get_elapsed_time();
  }
  m_last_pmode_alp = settings.pmode_alp_register;

  m_profiler.finish();
  m_stats.draw_calls = m_profiler.root()->stats().draw_calls;
  m_stats.triangles = m_profiler.root()->stats().triangles;

  // Gperf-batching: prop-gated per-bucket profile dump (ms/draws/tris per
  // profiler node) — the per-family table the batching work is steered by.
  // Enable: adb shell setprop debug.opengoal.perf.buckets 1
  {
    static bool s_perf_dump = false;
    if ((m_stats.frame_idx % 120) == 1) {
      char buf[PROP_VALUE_MAX] = {0};
      __system_property_get("debug.opengoal.perf.buckets", buf);
      s_perf_dump = buf[0] == '1';
    }
    if (s_perf_dump && (m_stats.frame_idx % 60) == 0) {
      std::string dump = m_profiler.dump_stats(0.10f);
      fprintf(stderr, "A35-PERF frame=%llu\n%s", (unsigned long long)m_stats.frame_idx,
              dump.c_str());
      // Gperf-particles: particle-pipeline counters over the same 60-frame
      // window — GOAL-kernel-thread mips2c sparticle kernel time (invisible to
      // the GL-thread profiler above) + render-thread sprite submission shape.
      auto ms = [](std::atomic<uint64_t>& a) { return a.exchange(0) / 1e6; };
      auto n = [](std::atomic<uint64_t>& a) { return (unsigned long long)a.exchange(0); };
      auto& sp = g_spart_prof;
      fprintf(stderr,
              "A35-SPART win=60f 3d=%.2fms/%lluc/%lluit 2d=%.2fms/%lluc/%lluit "
              "launch=%.2fms/%lluc adgif=%.2fms/%lluc | sprite buckets=%llu quads=%llu "
              "directflush=%llu | glbuild=%.2fms glflush=%.2fms"
              " | goal idle=%.2f pace=%.2f n=%llu | tie i=%.2f ts=%.2f cu=%.2f ix=%.2f"
              " | shrub ts=%.2f ix=%.2f\n",
              ms(sp.ns_3d), n(sp.calls_3d), n(sp.iters_3d), ms(sp.ns_2d), n(sp.calls_2d),
              n(sp.iters_2d), ms(sp.ns_launch), n(sp.calls_launch), ms(sp.ns_adgif),
              n(sp.calls_adgif), n(sp.sprite_buckets), n(sp.sprite_quads),
              n(sp.direct_flushes), ms(sp.gl_spr_build), ms(sp.gl_spr_flush),
              ms(sp.goal_idle), ms(sp.goal_pace), n(sp.goal_frames), ms(sp.tie_interp),
              ms(sp.tie_texsub), ms(sp.tie_cull), ms(sp.tie_index), ms(sp.shrub_texsub),
              ms(sp.shrub_index));
    }
  }

  // Surface the already-measured GL-thread CPU time so a profiling run can
  // attribute the frame budget. render_cpu_s is the whole render() call;
  // buckets_cpu_s / pcrtc_cpu_s are captured at their scoped nodes (below).
  m_stats.render_cpu_s = m_profiler.root_time();
}

void AndroidOpenGLRenderer::setup_frame(const AndroidRenderOptions& settings) {
  auto& window_fb = m_fbo_state.window;
  bool window_resized =
      window_fb.width != settings.window_fb_w || window_fb.height != settings.window_fb_h;
  window_fb.valid = true;
  window_fb.is_window = true;
  window_fb.fbo_id = 0;
  window_fb.width = settings.window_fb_w;
  window_fb.height = settings.window_fb_h;
  window_fb.multisample_count = 1;
  window_fb.multisampled = false;

  // Render-scaling: the 3D scene FBO is game_res * (render_scale_pct/100),
  // keeping the GOAL 4:3 aspect. do_pcrtc_effects resample-blits it to the
  // native draw region, so 100 == original 640x480 behavior, <100 trades
  // sharpness for fill-rate, and >100 SUPERSAMPLES for crispness (e.g. 200 ->
  // 1280x960). Clamp to [25,400] and keep dims >= 1. The whole renderer
  // (viewport, projection, bucket draws, FBO probe) keys off these dims, so
  // nothing downstream needs to know about the scale — GOAL game_res_w/h is
  // never touched, and the GOAL projection is NDC (resolution-independent), so
  // a larger FBO just yields more samples of the same scene.
  int scale = settings.render_scale_pct;
  if (scale < 25) scale = 25;
  if (scale > 400) scale = 400;
  const int scaled_w = (settings.game_res_w * scale + 50) / 100;
  const int scaled_h = (settings.game_res_h * scale + 50) / 100;
  const int fbo_w = scaled_w > 0 ? scaled_w : 1;
  const int fbo_h = scaled_h > 0 ? scaled_h : 1;
  m_stats.fbo_w = fbo_w;
  m_stats.fbo_h = fbo_h;

  if (window_resized || !m_fbo_state.render_fbo ||
      !m_fbo_state.render_fbo->matches(fbo_w, fbo_h, 1)) {
    lg::info("A35-RENDER FBO setup: {}x{} (game_res {}x{} scale {}% window {}x{})", fbo_w, fbo_h,
             settings.game_res_w, settings.game_res_h, scale, settings.window_fb_w,
             settings.window_fb_h);
    m_fbo_state.render_buffer.clear();
    m_fbo_state.render_buffer = a35_make_fbo(fbo_w, fbo_h);
    m_fbo_state.render_fbo = &m_fbo_state.render_buffer;
  }

  ASSERT_MSG(fbo_w > 0 && fbo_h > 0,
             fmt::format("Bad viewport size from game_res: {}x{}\n", fbo_w, fbo_h));

  // jak1 frame clear — desktop setup_frame parity.
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, window_fb.width, window_fb.height);
  glClearColor(0.0, 0.0, 0.0, 0.0);
  glClearDepthf(0.0f);
  glDepthMask(GL_TRUE);
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
  glDisable(GL_BLEND);

  glBindFramebuffer(GL_FRAMEBUFFER, m_fbo_state.render_fbo->fbo_id);
  glClearColor(0.0, 0.0, 0.0, 0.0);
  glClearDepthf(0.0f);
  glClearStencil(0);
  glDepthMask(GL_TRUE);
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
  glDisable(GL_BLEND);
  m_render_state.stencil_dirty = false;
  // A36: desktop setup_frame ends by sizing the viewport to the GAME FBO
  // (OpenGLRenderer.cpp:1290). A35's port left the window-sized viewport
  // active, so every bucket rasterized a 2298x934 projection into the
  // 640x480 FBO — geometry clipped off to a corner, screen stayed black
  // (run-26 FBO probe: all-zero center with 64k tris drawn). With render-
  // scaling the FBO (and thus this viewport) is game_res*scale; the GOAL
  // projection is resolution-independent (NDC), so the scene fills the
  // smaller FBO exactly as it filled the full one, then upscales on blit.
  glViewport(0, 0, fbo_w, fbo_h);

  // draw_region (the letterbox rect inside the native window) is unchanged by
  // render-scaling: the blit always targets the full native draw region, so
  // the upscaled 3D image keeps its on-screen size/aspect.
  m_render_state.draw_region_w = settings.draw_region_w;
  m_render_state.draw_region_h = settings.draw_region_h;
  m_render_state.draw_offset_x = (settings.window_fb_w - m_render_state.draw_region_w) / 2;
  m_render_state.draw_offset_y = (settings.window_fb_h - m_render_state.draw_region_h) / 2;
  m_render_state.render_fb = m_fbo_state.render_fbo->fbo_id;

  if (m_render_state.draw_region_w <= 0 || m_render_state.draw_region_h <= 0) {
    m_render_state.draw_region_w = 320;
    m_render_state.draw_region_h = 240;
  }

  m_render_state.render_fb_x = 0;
  m_render_state.render_fb_y = 0;
  m_render_state.render_fb_w = fbo_w;
  m_render_state.render_fb_h = fbo_h;
  glViewport(0, 0, fbo_w, fbo_h);

  // Grender-split (UI native + 3D scaled): the 3D scene renders into render_buffer
  // at the scaled size (fbo_w x fbo_h = game_res x render_scale). When that is
  // smaller than the native on-screen draw region, the 2D UI/HUD/text is drawn into
  // a separate native-resolution FBO so it stays crisp while only the 3D is
  // upscaled. Inactive (zero-cost) when the scene already fills the display.
  m_ui_pass_active = false;
  // Grender-split: drop any deferred HUD draws left from a frame where the UI
  // pass never ran (defensive; the DEBUG-bucket fallback normally drains them).
  if (m_generic2) {
    m_generic2->clear_deferred_hud_draws();
  }
  const int native_ui_w = m_render_state.draw_region_w;
  const int native_ui_h = m_render_state.draw_region_h;
  const bool split_active =
      (fbo_w < native_ui_w || fbo_h < native_ui_h) && native_ui_w > 0 && native_ui_h > 0;
  if (split_active) {
    if (!m_fbo_state.ui_buffer.matches(native_ui_w, native_ui_h, 1)) {
      m_fbo_state.ui_buffer.clear();
      m_fbo_state.ui_buffer = a35_make_fbo(native_ui_w, native_ui_h);
    }
    m_render_state.begin_2d_ui_pass = [this]() { begin_ui_pass(); };
    // a35_make_fbo bound the new UI fbo; restore the scaled scene target for the 3D pass.
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo_state.render_fbo->fbo_id);
    glViewport(0, 0, fbo_w, fbo_h);
  } else {
    m_render_state.begin_2d_ui_pass = nullptr;
  }
}

void AndroidOpenGLRenderer::begin_ui_pass() {
  if (m_ui_pass_active) {
    return;  // idempotent: only composite+switch once per frame
  }
  m_ui_pass_active = true;

  auto& ui = m_fbo_state.ui_buffer;
  Fbo& scene = m_fbo_state.render_buffer;  // always single-sample on Android

  // Upscale-blit the scaled 3D scene into the native UI FBO ("upscale 3D").
  glBindFramebuffer(GL_READ_FRAMEBUFFER, scene.fbo_id);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, ui.fbo_id);
  glBlitFramebuffer(0, 0, scene.width, scene.height, 0, 0, ui.width, ui.height,
                    GL_COLOR_BUFFER_BIT, GL_LINEAR);

  // Re-target the UI FBO for the native 2D pass. Keep the composited color; clear
  // depth so the always-on-top HUD/menu (GEQUAL vs cleared 0) is not occluded.
  glBindFramebuffer(GL_FRAMEBUFFER, ui.fbo_id);
  glDepthMask(GL_TRUE);
  glClearDepthf(0.0f);
  glClearStencil(0);
  glClear(GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
  glDisable(GL_BLEND);
  glViewport(0, 0, ui.width, ui.height);

  m_render_state.render_fb = ui.fbo_id;
  m_render_state.render_fb_x = 0;
  m_render_state.render_fb_y = 0;
  m_render_state.render_fb_w = ui.width;
  m_render_state.render_fb_h = ui.height;
  m_render_state.stencil_dirty = false;

  // Replay the HUD-flagged Generic2 draws (e.g. the Precursor-orb HUD/menu icon)
  // that were deferred out of the scaled 3D pass: they draw here at native res,
  // BEFORE the HUD sprite group, writing depth into the UI FBO so the orb's
  // hud-egg glow sprite (ztest GEQUAL) is depth-rejected exactly as in the
  // single-FBO pipeline (this was the Gorb-hud-regression white-egg).
  if (m_generic2) {
    m_generic2->draw_deferred_hud_draws(&m_render_state);
  }
}

void AndroidOpenGLRenderer::dispatch_buckets_jak1(DmaFollower dma, ScopedProfilerNode& prof) {
  // Desktop dispatch_buckets_jak1 parity: initial CALL into the default
  // regs chain, then the 70 buckets, vif interrupt after each.
  m_render_state.buckets_base = dma.current_tag_offset() + 16;
  m_render_state.next_bucket = m_render_state.buckets_base;
  m_render_state.bucket_for_vis_copy = (int)jak1::BucketId::TFRAG_LEVEL0;
  m_render_state.num_vis_to_copy = jak1::LEVEL_MAX;

  auto initial_call_tag = dma.current_tag();
  ASSERT(initial_call_tag.kind == DmaTag::Kind::CALL);
  auto initial_call_default_regs = dma.read_and_advance();
  ASSERT(initial_call_default_regs.transferred_tag == 0);  // should be a nop.
  m_render_state.default_regs_buffer = dma.current_tag_offset();
  auto default_regs_tag = dma.current_tag();
  ASSERT(default_regs_tag.kind == DmaTag::Kind::CNT);
  ASSERT(default_regs_tag.qwc == 10);
  auto default_data = dma.read_and_advance();
  ASSERT(default_data.size_bytes > 148);
  memcpy(m_render_state.fog_color.data(), default_data.data + 144, 4);
  auto default_ret_tag = dma.current_tag();
  ASSERT(default_ret_tag.qwc == 0);
  ASSERT(default_ret_tag.kind == DmaTag::Kind::RET);
  dma.read_and_advance();

  ASSERT(dma.current_tag_offset() == m_render_state.next_bucket);
  m_render_state.next_bucket += 16;

  for (size_t bucket_id = 0; bucket_id < m_bucket_renderers.size(); bucket_id++) {
    auto& renderer = m_bucket_renderers[bucket_id];
    auto bucket_prof = prof.make_scoped_child(renderer->name_and_id());

    const bool had_data = bucket_has_data(dma, m_render_state.next_bucket);
    if (had_data) {
      m_stats.buckets_with_data++;
      if (m_bucket_ported[bucket_id]) {
        m_stats.buckets_drawn++;
      } else {
        m_stats.buckets_skipped++;
        if (!m_skip_logged[bucket_id]) {
          m_skip_logged[bucket_id] = true;
          __android_log_print(ANDROID_LOG_WARN, kLogTag,
                              "A35-RENDER skip bucket=%s id=%zu (not ported)",
                              renderer->name().c_str(), bucket_id);
        }
      }
    }

    // A37: pre-validate the bucket's stream structure. A bucket whose tag
    // stream doesn't land exactly on next_bucket traps the GL thread in a
    // renderer tag loop forever (runs 23-26: SkyRenderer's CNT loop ran
    // past the bucket into foreign data once the real camera let the GOAL
    // sky path go deep). Malformed buckets are named, counted, skipped,
    // and the follower is re-seated on the bucket boundary.
    bool bucket_stream_ok = true;
    {
      DmaFollower probe = dma;
      constexpr int kCap = 200000;
      int steps = 0;
      while (probe.current_tag_offset() != m_render_state.next_bucket && !probe.ended() &&
             steps < kCap) {
        probe.read_and_advance();
        steps++;
      }
      if (probe.current_tag_offset() != m_render_state.next_bucket) {
        bucket_stream_ok = false;
        static int s_malformed_logged = 0;
        if (s_malformed_logged < 40) {
          s_malformed_logged++;
          __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                              "A37-BUCKET-MALFORMED bucket=%s id=%zu steps=%d stuck@0x%x "
                              "(ended=%d) next=0x%x — skipping bucket",
                              renderer->name().c_str(), bucket_id, steps,
                              probe.current_tag_offset(), (int)probe.ended(),
                              m_render_state.next_bucket);
        }
      }
    }
    if (!bucket_stream_ok) {
      m_stats.buckets_skipped++;
      dma = DmaFollower(dma.base(), m_render_state.next_bucket);
      m_render_state.next_bucket += 16;
      vif_interrupt_callback(bucket_id);
      continue;
    }

    // A36 canary: the first real content frame zeroes glad's function
    // pointers (run-19: glClearDepthf NULL one loop later → BLR-to-0 with
    // lr in android_renderer_run). Check a glad pointer after every bucket
    // so the smashing bucket names itself.
    static void* s_glad_canary = (void*)glad_glClearDepthf;
    {
      // F1a breadcrumb for the SIGSEGV dump (driver-internal crashes have
      // no walkable caller frame — run-4).
      extern char gk_f1a_current_bucket[64];
      snprintf(gk_f1a_current_bucket, sizeof(gk_f1a_current_bucket), "%s id=%zu",
               renderer->name().c_str(), bucket_id);
    }
    // Grender-split: the DirectRenderer UI buckets (DEBUG/DEBUG_NO_ZBUF/SUBTITLE
    // carry all 2D text/HUD numbers/menu/subtitles) come after the 3D scene. Make
    // sure the native UI pass has begun before them — a fallback for the case where
    // the sprite bucket was empty and didn't trigger it.
    if (bucket_id == (int)jak1::BucketId::DEBUG && m_render_state.begin_2d_ui_pass) {
      m_render_state.begin_2d_ui_pass();
    }
    renderer->render(dma, &m_render_state, bucket_prof);
    {
      extern char gk_f1a_current_bucket[64];
      gk_f1a_current_bucket[0] = 0;
    }
    // A36: name any bucket that exits with a framebuffer other than the
    // game FBO bound (run-27: 64k tris/frame but the FBO stays all-zero).
    {
      GLint cur_fb = -1;
      glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &cur_fb);
      static int s_fb_logged = 0;
      if (cur_fb != (GLint)m_render_state.render_fb && s_fb_logged < 30) {
        s_fb_logged++;
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A36-FB-TRACK after bucket=%s id=%zu draw-fb=%d expected=%u",
                            renderer->name().c_str(), bucket_id, cur_fb,
                            m_render_state.render_fb);
      }
    }
    if ((void*)glad_glClearDepthf != s_glad_canary) {
      __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                          "A36-CANARY glad_glClearDepthf changed %p -> %p after bucket=%s id=%zu "
                          "(host memory smashed by this bucket's render)",
                          s_glad_canary, (void*)glad_glClearDepthf, renderer->name().c_str(),
                          bucket_id);
      s_glad_canary = (void*)glad_glClearDepthf;
    }

    ASSERT(dma.current_tag_offset() == m_render_state.next_bucket);
    m_render_state.next_bucket += 16;
    vif_interrupt_callback(bucket_id);
  }
}

// Gjak2-visuals: live bucket-family mute for wash bisection. Token matches a
// renderer name if equal or a "<token>-" prefix ("tie" mutes tie-l0-tfrag but
// not etie-l0-tfrag; "merc" not emerc/gmerc). Diagnostic-only.
static bool gj2vis_bucket_muted(const char* list, const std::string& name) {
  const char* p = list;
  while (*p) {
    const char* e = p;
    while (*e && *e != ',') {
      e++;
    }
    size_t tok_len = (size_t)(e - p);
    if (tok_len > 0 &&
        ((name.size() == tok_len && name.compare(0, tok_len, p, tok_len) == 0) ||
         (name.size() > tok_len && name.compare(0, tok_len, p, tok_len) == 0 &&
          name[tok_len] == '-'))) {
      return true;
    }
    p = *e ? e + 1 : e;
  }
  return false;
}

void AndroidOpenGLRenderer::dispatch_buckets_jak2(DmaFollower dma, ScopedProfilerNode& prof) {
  // Desktop dispatch_buckets_jak2 parity: UNLIKE jak1, the jak2 chain has NO
  // initial default-regs CALL. Bucket 0 starts at the chain's current offset
  // (0), so buckets_base = current offset, next_bucket = base + 16, and the
  // dispatch drops straight into the per-bucket loop. bucket_for_vis_copy =
  // BUCKET_2, num_vis_to_copy = jak2::LEVEL_MAX (matches OpenGLRenderer.cpp).

  // Gjak2-visuals wash-bisect mute: adb shell setprop debug.opengoal.vis.skip
  // "etie,gmerc,effects,..." (comma list of renderer-name prefixes; live, read
  // once per frame; empty/unset = off).
  char gj2vis_skip[PROP_VALUE_MAX] = {0};
  __system_property_get("debug.opengoal.vis.skip", gj2vis_skip);
  m_render_state.buckets_base = dma.current_tag_offset();
  m_render_state.next_bucket = m_render_state.buckets_base + 16;
  m_render_state.bucket_for_vis_copy = (int)jak2::BucketId::BUCKET_2;
  m_render_state.num_vis_to_copy = jak2::LEVEL_MAX;

  for (size_t bucket_id = 0; bucket_id < m_bucket_renderers.size(); bucket_id++) {
    auto& renderer = m_bucket_renderers[bucket_id];
    auto bucket_prof = prof.make_scoped_child(renderer->name_and_id());

    const bool had_data = bucket_has_data(dma, m_render_state.next_bucket);
    if (had_data) {
      m_stats.buckets_with_data++;
      if (m_bucket_ported[bucket_id]) {
        m_stats.buckets_drawn++;
      } else {
        m_stats.buckets_skipped++;
        if (!m_skip_logged[bucket_id]) {
          m_skip_logged[bucket_id] = true;
          __android_log_print(ANDROID_LOG_WARN, kLogTag,
                              "A35-RENDER jak2 skip bucket=%s id=%zu (not ported)",
                              renderer->name().c_str(), bucket_id);
        }
      }
    }

    // Gjak2-visuals wash-bisect: muted family → consume the bucket without
    // rendering (same re-seat as the malformed-stream skip below).
    if (gj2vis_skip[0] && gj2vis_bucket_muted(gj2vis_skip, renderer->name())) {
      m_stats.buckets_skipped++;
      dma = DmaFollower(dma.base(), m_render_state.next_bucket);
      m_render_state.next_bucket += 16;
      vif_interrupt_callback(bucket_id + 1);
      continue;
    }

    // Same structural pre-validation as the jak1 android dispatcher: a bucket
    // whose tag stream doesn't land exactly on next_bucket would trap the GL
    // thread in a renderer's tag loop. Named, counted, skipped, and the
    // follower re-seated on the bucket boundary.
    bool bucket_stream_ok = true;
    {
      DmaFollower probe = dma;
      constexpr int kCap = 200000;
      int steps = 0;
      while (probe.current_tag_offset() != m_render_state.next_bucket && !probe.ended() &&
             steps < kCap) {
        probe.read_and_advance();
        steps++;
      }
      if (probe.current_tag_offset() != m_render_state.next_bucket) {
        bucket_stream_ok = false;
        static int s_malformed_logged = 0;
        if (s_malformed_logged < 40) {
          s_malformed_logged++;
          __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                              "A37-BUCKET-MALFORMED jak2 bucket=%s id=%zu steps=%d stuck@0x%x "
                              "(ended=%d) next=0x%x — skipping bucket",
                              renderer->name().c_str(), bucket_id, steps,
                              probe.current_tag_offset(), (int)probe.ended(),
                              m_render_state.next_bucket);
        }
      }
    }
    if (!bucket_stream_ok) {
      m_stats.buckets_skipped++;
      dma = DmaFollower(dma.base(), m_render_state.next_bucket);
      m_render_state.next_bucket += 16;
      vif_interrupt_callback(bucket_id + 1);
      continue;
    }

    static void* s_glad_canary = (void*)glad_glClearDepthf;
    {
      extern char gk_f1a_current_bucket[64];
      snprintf(gk_f1a_current_bucket, sizeof(gk_f1a_current_bucket), "%s id=%zu",
               renderer->name().c_str(), bucket_id);
    }
    renderer->render(dma, &m_render_state, bucket_prof);
    {
      extern char gk_f1a_current_bucket[64];
      gk_f1a_current_bucket[0] = 0;
    }
    if ((void*)glad_glClearDepthf != s_glad_canary) {
      __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                          "A36-CANARY glad_glClearDepthf changed %p -> %p after jak2 bucket=%s "
                          "id=%zu (host memory smashed by this bucket's render)",
                          s_glad_canary, (void*)glad_glClearDepthf, renderer->name().c_str(),
                          bucket_id);
      s_glad_canary = (void*)glad_glClearDepthf;
    }

    // Desktop jak2 asserts the follower ended exactly at next_bucket, then
    // advances. vif_interrupt_callback is called with bucket_id + 1 on jak2
    // (jak1 android uses bucket_id — match each game's own convention).
    ASSERT(dma.current_tag_offset() == m_render_state.next_bucket);
    m_render_state.next_bucket += 16;
    vif_interrupt_callback(bucket_id + 1);
  }
  vif_interrupt_callback(m_bucket_renderers.size());
}

void AndroidOpenGLRenderer::do_pcrtc_effects(float alp,
                                             SharedRenderState* render_state,
                                             ScopedProfilerNode& prof) {
  // desktop do_pcrtc_effects, msaa-resolve stripped (always 1 sample) and
  // brightness/contrast left at the neutral defaults.
  // Grender-split: when active, the UI FBO already holds the composited image
  // (upscaled 3D scene + native-resolution 2D UI); blit it straight to the window.
  Fbo* window_blit_src =
      m_ui_pass_active ? &m_fbo_state.ui_buffer : &m_fbo_state.render_buffer;

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glViewport(render_state->draw_offset_x, render_state->draw_offset_y,
             render_state->draw_region_w, render_state->draw_region_h);
  glBindTexture(GL_TEXTURE_2D, *window_blit_src->tex_id);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  glBindVertexArray(m_screen_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_screen_vbo);

  auto& shader = render_state->shaders[ShaderId::POST_PROCESSING];
  shader.activate();
  glUniform1i(glGetUniformLocation(shader.id(), "tex_T0"), 0);
  glUniform4f(glGetUniformLocation(shader.id(), "color_mult"), 1.0f, 1.0f, 1.0f, 1.0f);
  glUniform4f(glGetUniformLocation(shader.id(), "color_add"), 0.0f, 0.0f, 0.0f, 0.0f);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glActiveTexture(GL_TEXTURE0);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);

  glEnable(GL_BLEND);
  if (alp < 1) {
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ZERO);
    glBlendEquation(GL_FUNC_ADD);
    m_blackout_renderer.draw(math::Vector4f(0, 0, 0, 1.f - alp), render_state, prof);
  }
  glEnable(GL_DEPTH_TEST);
}
