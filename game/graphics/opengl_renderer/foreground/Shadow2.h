#pragma once

#include "common/math/Vector.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"

class Shadow2 : public BucketRenderer {
 public:
  static constexpr int kMaxVerts = 8192 * 3 * 2;
  static constexpr int kMaxInds = kMaxVerts;
  Shadow2(const std::string& name, int my_id);
  ~Shadow2();
  void render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) override;
  void draw_debug_window() override;
  void init_shaders(ShaderLibrary& shaders) override;

 private:
  struct ShadowVu1Constants {
    math::Vector4f hmgescale;
    math::Vector4f invhscale;
    math::Vector4f texoffset;
    math::Vector4f texscale;
    math::Vector4f hvdfoff;
    math::Vector4f fog;
    math::Vector4f clrs[2];
  };
  static_assert(sizeof(ShadowVu1Constants) == 128);

  struct MysteryData {
    u8 data[4 * 16];
  };

  struct CameraMatrix {
    math::Vector4f v[4];
  };

  struct FrameConstants {
    ShadowVu1Constants constants;  // 880, 0x370
    MysteryData mystery;           // 940, 0x3ac
    CameraMatrix camera;           // 0
  };

  static constexpr int kTopVertexDataAddr = 4;
  static constexpr int kBottomVertexDataAddr = 174;
  static constexpr int kCapIndexDataAddr = 344;
  static constexpr int kWallIndexDataAddr = 600;

  struct InputData {
    const u8* top_vertex_data = nullptr;     // always 115
    const u8* bottom_vertex_data = nullptr;  // always 115
    const u8* cap_index_data = nullptr;
    size_t cap_index_data_size = 0;
    const u8* wall_index_data = nullptr;
    size_t wall_index_data_size = 0;
  };

  struct ShadowVertex {
    math::Vector3f pos;
    u32 pad = 0;
  };
  static_assert(sizeof(ShadowVertex) == 16);

  struct {
    GLuint vertex_buffer;
    GLuint index_buffer[2];
    GLuint vao;
    struct {
      GLuint hvdf_offset;
      GLuint perspective[4];
      GLuint fog;
      GLuint color;
      GLuint clear_mode;
    } uniforms;
  } m_ogl;

  std::vector<ShadowVertex> m_vertex_buffer;
  std::vector<u32> m_front_index_buffer;
  std::vector<u32> m_back_index_buffer;
  size_t m_vertex_buffer_used = 0;
  size_t m_front_index_buffer_used = 0;
  size_t m_back_index_buffer_used = 0;
  bool m_debug_draw_volume = false;

  // lighting-shadows (SPEC-refonte-lumiere §1.2 decision 2, §4.1, §6.1, §6.2) : « Jak n'a jamais
  // deux ombres a la fois ». Le decalque PS2 (aplat) d'un acteur est saute quand sa VRAIE ombre
  // (l'atlas PBR) est active et le couvre. La decision est prise UNE fois par acteur, sur le
  // pointeur `top_vertex_data` de son upload (constant entre le/les appel(s) mscal2/mscal6 des
  // capuchons et l'appel mscal4 des murs QUI SUIVENT, tant que l'acteur suivant n'a pas
  // reuploade de nouveaux sommets) : un acteur ne peut donc jamais avoir ses capuchons dessines
  // et ses murs sautes, ou l'inverse.
  const u8* m_shadow_skip_key = nullptr;
  bool m_shadow_skip_valid = false;
  bool m_shadow_skip = false;
  uint64_t m_blob_drawn = 0;
  uint64_t m_blob_skipped = 0;
  // Vrai si le volume dont `top_vertex_data == in.top_vertex_data` doit etre SAUTE (l'ombre
  // reelle de cet acteur est dans l'atlas et le couvre). Calcule une fois par acteur, memoise
  // par identite de pointeur, et compte dans `m_blob_drawn` / `m_blob_skipped`.
  bool actor_shadow_should_skip(const InputData& in);

  void reset_buffers();
  void buffer_from_mscal2(const InputData& input);
  void buffer_from_mscal4(const InputData& input);
  void buffer_from_mscal6(const InputData& input);
  const u8* add_cap_tris(const u8* byte_data, const u8* vertex_data, bool flip);
  const u8* add_wall_quads(const u8* byte_data, const u8* vertex_data_0, const u8* vertex_data_1);
  const u8* add_flippable_tris(const u8* byte_data, const u8* vertex_data, bool flip);
  ShadowVertex* alloc_verts(int n);
  u32* alloc_inds(int n, bool front);
  void draw_buffers(SharedRenderState* render_state,
                    ScopedProfilerNode& prof,
                    const FrameConstants& constants);
  u8 m_color[4] = {0, 0, 0, 0};
};
