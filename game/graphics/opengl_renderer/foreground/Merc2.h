#pragma once
#include <array>
#include <utility>

#include "game/graphics/opengl_renderer/BucketRenderer.h"

#ifdef OG_FEAT_HD_MODELS
// Grecharged-hd-models4 per-actor coverage registry (defined in Merc2.cpp, called from the GOAL
// builtins pc-hd-cover!/pc-hd-uncover! registered in jak1/kmachine.cpp). An HD companion process
// declares which driver actor (by pid) its submissions replace; Merc2 suppresses that driver's
// stock draw only while the companion's model is actually being processed and found.
void merc2_hd_cover(u32 companion_pid, u32 driver_pid);
void merc2_hd_uncover(u32 companion_pid);
// CYCLE-3 (Keira black-eyes-on-blink): true while an HD companion model referencing this dynamic
// eye slot (the merc draw eye_id byte, == EyeRenderer SingleEyeDraws::tex_slot()) is actively
// submitting. jak1 blinks by PAINTING the eyelid over the whole eye tile (EyeRenderer lid pass,
// blend off) — correct on the stock flat eyelid-patch mesh, garbage wrapped around the HD donor
// EYEBALL geometry. EyeRenderer skips the lid blit for covered slots. Render-thread only.
bool merc2_hd_eye_slot_covered(u8 slot);
// CYCLE-4 (visible blink): donor eyelid GL texture for a covered slot, 0 when unknown. The donor
// games blink exactly like jak1 — a lid texture painted across the eye tile with the same
// blink-table math — so the correct blink for an HD model paints the DONOR's own lid texture
// (ported into enhanced GAME.fr3 by hd_merc_swap as "<model>-lid", resolved from the model's
// level at slot arming) at the driver's lid position. When this returns 0 the EyeRenderer keeps
// the cycle-3 behavior (skip the blit — never the stock jak1 lid on donor eye UVs, that was the
// black-eye bug).
u64 merc2_hd_eye_slot_lid_gl(u8 slot);
#endif

struct MercDebugStats {
  int num_models = 0;
  int num_missing_models = 0;
  int num_chains = 0;
  int num_effects = 0;
  int num_predicted_draws = 0;
  int num_predicted_tris = 0;
  int num_bones_uploaded = 0;
  int num_lights = 0;
  int num_draw_flush = 0;

  int num_envmap_effects = 0;
  int num_envmap_tris = 0;

  int num_upload_bytes = 0;
  int num_uploads = 0;

  struct DrawDebug {
    DrawMode mode;
    int num_tris;
  };
  struct EffectDebug {
    bool envmap = false;
    DrawMode envmap_mode;
    std::vector<DrawDebug> draws;
  };
  struct ModelDebug {
    std::string name;
    std::string level;
    std::vector<EffectDebug> effects;
  };

  std::vector<ModelDebug> model_list;

  bool collect_debug_model_list = false;
};

class Merc2 {
 public:
  Merc2(ShaderLibrary& shaders, const std::vector<GLuint>* anim_slot_array);
  ~Merc2();
  void draw_debug_window(MercDebugStats* stats);
  void render(DmaFollower& dma,
              SharedRenderState* render_state,
              ScopedProfilerNode& prof,
              MercDebugStats* stats);
  static constexpr int kMaxBlerc = 40;

  // Grecharged-title-logo-fullres: the title-screen logo family (the JAK AND DAXTER logo, its
  // volumetric shafts + black card, and the ND boot logo) are camera-anchored 3D overlays that
  // the stock pipeline draws into the render-SCALED scene FBO, so a low RENDER SCALE pixelates
  // them. When the Grender-split UI pass is armed, flush_draw_buckets() stashes those models'
  // draws instead of drawing them, and the frame orchestrator replays them here at NATIVE
  // resolution from inside begin_ui_pass() — the same deferral Generic2 already does for the
  // HUD 3D icons (draw_deferred_hud_draws). Gated by
  // Gfx::recharged_active(recharged_crisp_title_logo) AND by the split being active, so with the
  // toggle OFF (or at RENDER SCALE 100%) nothing is ever stashed and the stock path is unchanged.
  bool has_deferred_native_draws() const { return !m_deferred_native.empty(); }
  void clear_deferred_native_draws() { m_deferred_native.clear(); }
  void draw_deferred_native_draws(SharedRenderState* render_state);

 private:
  const std::vector<GLuint>* m_anim_slot_array;
  enum MercDataMemory {
    LOW_MEMORY = 0,
    BUFFER_BASE = 442,
    // this negative offset is what broke jak graphics in Dobiestation for a long time.
    BUFFER_OFFSET = -442
  };

  struct LowMemory {
    u8 tri_strip_tag[16];
    u8 ad_gif_tag[16];
    math::Vector4f hvdf_offset;
    math::Vector4f perspective[4];
    math::Vector4f fog;
  } m_low_memory;
  static_assert(sizeof(LowMemory) == 0x80);

  struct VuLights {
    math::Vector3f direction0;
    u32 w0;  // 12
    math::Vector3f direction1;
    u32 w1;  // 28
    math::Vector3f direction2;
    u32 w2;  // 44
    math::Vector4f color0;
    math::Vector4f color1;
    math::Vector4f color2;
    math::Vector4f ambient;
  };

  void handle_pc_model(const DmaTransfer& setup,
                       SharedRenderState* render_state,
                       ScopedProfilerNode& prof,
                       MercDebugStats* stats);
  u32 alloc_lights(const VuLights& lights);

  struct ModBuffers {
    GLuint vao, vertex;
  };

  static constexpr int kMaxEffect = 64;
  bool m_effect_debug_mask[kMaxEffect];

  struct MercMat {
    math::Vector4f tmat[4];
    math::Vector4f nmat[3];
  };

  struct ShaderMercMat {
    math::Vector4f tmat[4];
    math::Vector4f nmat[3];
    math::Vector4f pad;
    std::string to_string() const;
  };
  u32 alloc_bones(int count, ShaderMercMat* data);
  static constexpr int MAX_SKEL_BONES = 128;
  static constexpr int BONE_VECTORS_PER_BONE = 7;
  static constexpr int MAX_SHADER_BONE_VECTORS = 1024 * 32;  // ??

  static constexpr int MAX_LEVELS = 3;
  static constexpr int MAX_DRAWS_PER_LEVEL = 2048 * 2;
  static constexpr int MAX_ENVMAP_DRAWS_PER_LEVEL = MAX_DRAWS_PER_LEVEL;

  math::Vector4f m_shader_bone_vector_buffer[MAX_SHADER_BONE_VECTORS];

  struct Uniforms {
    GLuint light_direction[3];
    GLuint light_color[3];
    GLuint light_ambient;

    GLuint hvdf_offset;
    GLuint fog;

    GLuint tbone;
    GLuint nbone;

    GLuint fog_color;
    GLuint perspective_matrix;

    GLuint ignore_alpha;
    GLuint decal;

    GLuint gfx_hack_no_tex;

    GLuint fade;
  };

  Uniforms m_merc_uniforms, m_emerc_uniforms;

  void init_shader_common(Shader& shader, Uniforms* uniforms, bool include_lights);
  void handle_setup_dma(DmaFollower& dma, SharedRenderState* render_state);
  void handle_all_dma(DmaFollower& dma,
                      SharedRenderState* render_state,
                      ScopedProfilerNode& prof,
                      MercDebugStats* stats);
  void handle_merc_chain(DmaFollower& dma,
                         SharedRenderState* render_state,
                         ScopedProfilerNode& prof,
                         MercDebugStats* stats);

  void switch_to_merc2(SharedRenderState* render_state);
  void switch_to_emerc(SharedRenderState* render_state);

  GLuint m_vao;

  void setup_merc_vao();

  // Gperf-batching (render_state->batch_singledraw): the Merc2 core is shared
  // by all merc bucket renderers, so these dedupe the per-flush Adreno
  // BO-defuse maps (driver syncs — needed once per level per FRAME, not per
  // flush) and the m_vao attrib respecification (needed only when the level's
  // vertex buffer changes; load_id guards GL-name reuse after level reload).
  u64 m_defuse_frame = UINT64_MAX;
  std::array<std::pair<const void*, u64>, 8> m_defused_levs;
  int m_num_defused_levs = 0;
  GLuint m_vao_vertex_buffer = 0;
  u64 m_vao_load_id = UINT64_MAX;
  // bone-UBO ring cursor (in bone vectors, always alignment-rounded): each
  // flush uploads at the cursor instead of offset 0 so the write never lands
  // on a window in-flight draws are still reading (implicit-sync elimination)
  u32 m_bones_ring_base = 0;

  std::vector<ModBuffers> m_mod_vtx_buffers;
  u32 m_next_mod_vtx_buffer = 0;

  static constexpr int MAX_MOD_VTX = UINT16_MAX;
  std::vector<tfrag3::MercVertex> m_mod_vtx_temp;

  struct UnpackTempVtx {
    float pos[4];
    float nrm[4];
    float uv[2];
  };
  std::vector<UnpackTempVtx> m_mod_vtx_unpack_temp;

  ModBuffers alloc_mod_vtx_buffer(const LevelData* lev);

  GLuint m_bones_buffer;

  enum DrawFlags {
    IGNORE_ALPHA = 1,
    MOD_VTX = 2,
    NO_TEXTURE = 4,
  };

  struct Draw {
    u32 first_index;
    u32 index_count;
    DrawMode mode;
    s32 texture;
    u32 num_triangles;
    u16 first_bone;
    u16 light_idx;
    u8 flags;
    ModBuffers mod_vtx_buffer;
    u8 fade[4];
    // no strip hack for custom models
    u8 no_strip;
    u64 hash;
  };

  // Grecharged-title-logo-fullres: a deferred model contributes at most a handful of draws (the
  // J&D logo is 3 effects / 5 draws), so a small fixed pool is plenty. Fixed-size (never resized
  // after construction) because alloc_normal_draw hands out raw Draw* into it, exactly like the
  // stock draws/envmap_draws pools.
  static constexpr int MAX_NATIVE_DRAWS_PER_LEVEL = 256;

  struct LevelDrawBucket {
    const LevelData* level = nullptr;
    std::vector<Draw> draws;
    std::vector<Draw> envmap_draws;
    u32 next_free_draw = 0;
    u32 next_free_envmap_draw = 0;
    // Grecharged-title-logo-fullres: draws routed out of the scaled 3D pass for native replay.
    std::vector<Draw> native_draws;
    std::vector<Draw> native_envmap_draws;
    u32 next_free_native_draw = 0;
    u32 next_free_native_envmap_draw = 0;

    void reset() {
      level = nullptr;
      next_free_draw = 0;
      next_free_envmap_draw = 0;
      next_free_native_draw = 0;
      next_free_native_envmap_draw = 0;
    }
  };

  // Grecharged-title-logo-fullres: one stashed flush worth of native-overlay draws. The geometry
  // itself lives in the LEVEL's persistent GL buffers (unlike Generic2, whose vertex buffer is
  // rebuilt per bucket call), so only the per-flush state has to be snapshotted: the bone window
  // (m_shader_bone_vector_buffer is re-filled from 0 by every later flush), the lights the draws
  // index, and the low-memory block holding the perspective/hvdf/fog uniforms.
  struct DeferredNativeBatch {
    const LevelData* lev = nullptr;
    LowMemory low_memory;
    std::vector<Draw> draws;
    std::vector<Draw> envmap_draws;
    std::vector<math::Vector4f> bones;  // snapshot of [0, m_next_free_bone_vector)
    std::vector<VuLights> lights;       // only the lights the deferred draws reference
  };
  std::vector<DeferredNativeBatch> m_deferred_native;

  struct DrawArgs {
    LevelDrawBucket* lev_bucket;
    const u8* fade;
    bool jak1_water_mode;
    bool ignore_alpha;
    bool disable_fog;
    bool no_texture;
    u64 hash;
    u32 lights;
    u32 first_bone;
    // Grecharged-title-logo-fullres: route this model's draws into the native-overlay pools
    // instead of the scaled-pass pools. Always false unless the toggle is on AND the split is armed.
    bool defer_native = false;
  };

  Draw* alloc_normal_draw(const tfrag3::MercDraw& mdraw, const DrawArgs& args);

  Draw* try_alloc_envmap_draw(const tfrag3::MercDraw& mdraw,
                              const DrawMode& envmap_mode,
                              u32 envmap_texture,
                              const DrawArgs& args);

  void do_draws(const Draw* draw_array,
                const LevelData* lev,
                u32 num_draws,
                const Uniforms& uniforms,
                ScopedProfilerNode& prof,
                bool set_fade,
                SharedRenderState* render_state,
                u32 bones_base = 0);

  static constexpr int MAX_LIGHTS = 1024;
  VuLights m_lights_buffer[MAX_LIGHTS];
  u32 m_next_free_light = 0;

  std::vector<LevelDrawBucket> m_level_draw_buckets;
  u32 m_next_free_level_bucket = 0;
  u32 m_next_free_bone_vector = 0;
  size_t m_opengl_buffer_alignment = 0;

  void flush_draw_buckets(SharedRenderState* render_state,
                          ScopedProfilerNode& prof,
                          MercDebugStats* stats);
  void model_mod_draws(int num_effects,
                       const tfrag3::MercModel* model,
                       const LevelData* lev,
                       const u8* input_data,
                       const u8* ee_base,
                       ModBuffers* mod_opengl_buffers,
                       MercDebugStats* stats);
  void model_mod_blerc_draws(int num_effects,
                             const tfrag3::MercModel* model,
                             const LevelData* lev,
                             ModBuffers* mod_opengl_buffers,
                             const float* blerc_weights,
                             MercDebugStats* stats);
};
