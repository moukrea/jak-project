#pragma once

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/graphics/opengl_renderer/sprite/sprite_common.h"

class GlowRenderer {
 public:
  GlowRenderer();
  bool at_max_capacity();
  SpriteGlowOutput* alloc_sprite();
  void cancel_sprite();

  void flush(SharedRenderState* render_state, ScopedProfilerNode& prof);
  void draw_debug_window();

  // glow-targets-not-built-on-jak1 : CE QUE CETTE INSTANCE A REELLEMENT ALLOUE, compte sur le
  // format que le pilote a ACCEPTE (jamais sur celui demande — voir le repli du constructeur) et
  // sur les dimensions reellement passees a `glTexImage2D`. Un chiffre releve dans le
  // constructeur, pas recalcule ailleurs a partir des memes constantes : deux formules qui
  // derivent ne se verraient jamais.
  uint64_t allocated_bytes() const { return m_alloc_bytes; }
  int stages_created() const { return m_stages_created; }
  int stages_complete() const { return m_stages_complete; }

  // Rend au pilote les noms GL que le constructeur a pris. Retourne le nombre de noms que LE
  // PILOTE reconnaissait comme objets avant l'appel (`glIs*`) et ne reconnait plus apres — pas
  // le nombre de `glDelete*` emis : une suppression qui ne supprimerait rien rendrait zero, et
  // c'est la seule facon de rendre le temoin de reversibilite falsifiable. Un temoin qui
  // construirait sans rendre laisserait exactement la fuite que cet item supprime.
  // Volontairement PAS un destructeur : les autres renderers de ce moteur n'en ont pas, et en
  // ajouter un ferait tourner des `glDelete*` a l'extinction, hors de tout contexte courant.
  int destroy_gl_objects();
  int gl_names_live_before() const { return m_gl_live_before; }

#ifdef __ANDROID__
  // GLES/Adreno: the "new" glow-probe path copies the scene depth by sampling the
  // probe FBO's packed GL_DEPTH24_STENCIL8 texture as a regular sampler2D and
  // re-emitting it via gl_FragDepth (glow_depth_copy.frag). On Adreno this depth
  // round-trip does not work, so every glow probe reads as "fully visible" and the
  // sun-glow flare is drawn at full intensity -> the giant daylight light blob on
  // the title. The "old" path instead draws probes straight into the probe FBO
  // using a real hardware depth test against the blitted depth attachment and only
  // ever samples normal RGBA8 color textures, which is GLES-safe. Use it on Android.
  bool new_mode = false;
#else
  bool new_mode = true;
#endif

  // Vertex can hold all possible values for all passes. The total number of vertices is very small
  // so it ends up a lot faster to do a single upload, even if the size is like 50% larger than it
  // could be.
  struct Vertex {
    float x, y, z, w;
    float r, g, b, a;
    float u, v;
    float uu, vv;
  };

 private:
  struct {
    bool show_probes = false;
    bool show_probe_copies = false;
    bool enable_glow_boost = false;
    int num_sprites = 0;
    float glow_boost = 1.f;
  } m_debug;
  void add_sprite_pass_1(const SpriteGlowOutput& data);
  void add_sprite_pass_2(const SpriteGlowOutput& data, int sprite_idx);
  void add_sprite_pass_3(const SpriteGlowOutput& data, int sprite_idx);

  void add_sprite_new(const SpriteGlowOutput& data, int sprite_idx);

  void probe_and_copy_old(SharedRenderState* render_state, ScopedProfilerNode& prof);
  void probe_and_copy_new(SharedRenderState* render_state, ScopedProfilerNode& prof);

  void blit_depth(SharedRenderState* render_state);

  void setup_buffers_for_draws();

  void draw_probes(SharedRenderState* render_state,
                   ScopedProfilerNode& prof,
                   u32 idx_start,
                   u32 idx_end);

  void debug_draw_probes(SharedRenderState* render_state,
                         ScopedProfilerNode& prof,
                         u32 idx_start,
                         u32 idx_end);

  void draw_probe_copies(SharedRenderState* render_state,
                         ScopedProfilerNode& prof,
                         u32 idx_start,
                         u32 idx_end);

  void debug_draw_probe_copies(SharedRenderState* render_state,
                               ScopedProfilerNode& prof,
                               u32 idx_start,
                               u32 idx_end);
  void downsample_chain(SharedRenderState* render_state, ScopedProfilerNode& prof, u32 num_sprites);

  void draw_sprites(SharedRenderState* render_state, ScopedProfilerNode& prof);

  std::vector<Vertex> m_vertex_buffer;
  std::vector<SpriteGlowOutput> m_sprite_data_buffer;
  u32 m_next_sprite = 0;

  u32 m_next_vertex = 0;
  Vertex* alloc_vtx(int num);

  std::vector<u32> m_index_buffer;
  u32 m_next_index = 0;
  u32* alloc_index(int num);

  struct DsFbo {
    int size = -1;
    GLuint fbo;
    GLuint tex;
  };

  // max sprites should be 128 in simple sprite, plus 256 from aux = 384
  // 20 width = 20 * 20 = 400 sprites > 384.
  static constexpr int kDownsampleBatchWidth = 20;
  static constexpr int kMaxSprites = kDownsampleBatchWidth * kDownsampleBatchWidth;
  static constexpr int kMaxVertices = kMaxSprites * 32;  // check.
  static constexpr int kMaxIndices = kMaxSprites * 32;   // check.
  static constexpr int kDownsampleIterations = 5;
  static constexpr int kFirstDownsampleSize = 32;  // should be power of 2.

  struct {
    GLuint vertex_buffer;
    GLuint vao;
    GLuint index_buffer;

    GLuint probe_fbo;
    GLuint probe_fbo_rgba_tex;
    GLuint probe_fbo_depth_tex;
    GLuint first_ds_depth_rb;
    // GLuint probe_fbo_zbuf_rb;
    int probe_fbo_w = 640;
    int probe_fbo_h = 480;

    GLuint depth_texture;

    DsFbo downsample_fbos[kDownsampleIterations];
    // hdr-source-range : le format RETENU pour la sonde et les cinq reductions. Retenu, pas
    // demande : le pilote a le dernier mot et le redimensionnement doit reprendre le MEME.
    hdr::StageFormat stage_fmt;
  } m_ogl;

  struct {
    GLuint vao;
    GLuint index_buffer;
    GLuint vertex_buffer;
  } m_ogl_downsampler;

  DrawMode m_default_draw_mode;

  // glow-targets-not-built-on-jak1 : releve par le constructeur, lu par le temoin.
  uint64_t m_alloc_bytes = 0;
  int m_stages_created = 0;
  int m_stages_complete = 0;
  int m_gl_live_before = 0;
  bool m_gl_released = false;

  struct SpriteRecord {
    u32 tbp;
    DrawMode draw_mode;
    u32 idx;
  };

  std::array<SpriteRecord, kMaxSprites> m_sprite_records;
};
