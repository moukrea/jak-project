#pragma once

#include <optional>

#include "common/util/FilteredValue.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/PrePass.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/pipelines/opengl.h"

class Shrub : public BucketRenderer, public prepass::DepthContributor {
 public:
  Shrub(const std::string& name, int my_id);
  ~Shrub();
  void init_shaders(ShaderLibrary& shaders) override;

  bool setup_for_level(const std::string& level, SharedRenderState* render_state);
  void render_all_trees(const TfragRenderSettings& settings,
                        SharedRenderState* render_state,
                        ScopedProfilerNode& prof);
  void render_tree(int idx,
                   const TfragRenderSettings& settings,
                   SharedRenderState* render_state,
                   ScopedProfilerNode& prof);
  void render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) override;
  void draw_debug_window() override;

  // lighting-ao-indirect : contributeur de la prepasse de profondeur (PrePass.h). Dessine le
  // caster_index_buffer (GL_TRIANGLES assainis) de chaque arbre — le draw de la passe soleil.
  const char* prepass_kind() const override { return "shrub"; }
  const std::string& prepass_level_name() const override { return m_level_name; }
  uint64_t draw_depth_prepass(SharedRenderState* rs) override;

 private:
  void update_load(const LevelData* loader_data);
  void discard_tree_cache();
  struct Tree;
  void update_native_wind(Tree& tree,
                          const TfragRenderSettings& settings,
                          SharedRenderState* render_state);
  // lighting-ao-indirect (i), essai 15 — LE TELEVERSEMENT DU RESSORT, SORTI DE L'INTEGRATION.
  // `update_native_wind` integrait ET televersait, au debut de la passe COULEUR : la prepasse,
  // qui vient AVANT, echantillonnait donc l'etat de l'image n-1 pendant que la couleur
  // echantillonnait celui de l'image n. Un seul televersement par image, pose par le PREMIER
  // des deux passages (la prepasse quand elle tourne, la couleur sinon) : les deux passes lisent
  // alors les MEMES texels, au bit pres. Mesure : `ao_geom_shrub_gap4q_px` = 1312 px sur 5440
  // couverts, la ou le tfrag rend 8 sur 2 127 376 et le TIE 0.
  static void upload_native_wind(Tree& tree, uint64_t frame_idx);

  struct Tree {
    GLuint vertex_buffer;
    GLuint index_buffer;
    u32 index_count = 0;  // Grecharged-realtime-lighting round-3: full static strip index count, for the shadow caster pass
    // Owner #4 phantom-lines fix: sanitized GL_TRIANGLES caster buffer for the sun shadow
    // depth pass. The static strip stream knits some consecutive instance-groups together
    // (the extractor omits the restart at those boundaries), creating hundreds-of-meters
    // sliver triangles that cast the long straight phantom shadow lines (the owner's X).
    // Same triangles minus any with an edge above the sanity threshold; main draws untouched.
    GLuint caster_index_buffer = 0;
    u32 caster_index_count = 0;
    std::vector<u32> soft_caster_indices;
    // lighting-ao-indirect : la MEME liste de triangles, partitionnee par draw (donc par
    // texture), pour que la prepasse de profondeur puisse rejouer l'alpha-test du feuillage —
    // sans quoi l'AO occulte au travers des trous des brins d'herbe (owner 2026-09-10, defaut
    // b). `tex_id` s'indexe dans `m_textures`. Vide => aucune partition connue, la prepasse
    // retombe sur le draw unique.
    struct CasterGroup {
      u32 tex_id = 0;
      float alpha_min = 0.f;
      u32 first = 0;
      u32 count = 0;
      // lighting-ao-indirect (c)/(g) : VRAI quand la passe principale coupe le z-write de ce
      // draw (`prepass_writes_depth` faux). La prepasse LIVREE ne dessine pas ces groupes ;
      // seule la passe de mesure « occluder fantome » les rejoue.
      bool noz = false;
      // lighting-ao-indirect (terme 3) : le MODE d'echantillonnage du draw
      // (`prepass_tex_mode`), pour que la prepasse POSE l'etat de la texture au lieu de
      // l'heriter du dernier consommateur de l'image precedente (background_common.h).
      u8 tex_mode = 0xff;
    };
    std::vector<CasterGroup> caster_groups;
    GLuint single_draw_index_buffer;
    GLuint time_of_day_texture;
    // Gperf-particles round 3: second TOD texture for the ping-pong path, plus
    // the per-frame flip bit. tod_current is set at TOD-update time to whichever
    // texture this frame's draws should sample, so every subsequent bind uses
    // the same texture (no stale bind). perf_tod_pingpong OFF => tod_current is
    // always time_of_day_texture (identical to the old single-texture path).
    GLuint time_of_day_texture_pp = 0;
    u8 tod_flip = 0;
    GLuint tod_current = 0;
    s32 tod_cache_itimes[16] = {0};   // Gperf-particles: last itimes (4x Vector<s32,4>) for memoize
    bool tod_cache_valid = false;
    GLuint vao;
    u32 vert_count;
    const std::vector<tfrag3::ShrubDraw>* draws = nullptr;
    const std::vector<tfrag3::TieWindInstance>* instance_info = nullptr;
    const tfrag3::PackedTimeOfDay* colors = nullptr;
    // foliage-wind (essai 11) — LE VENT NATIF DES BUISSONS (ressort de ND par instance, shrub_asm.md
    // :957-1057). `src` = l'arbre du fr3 (pivot, couronne, raideur et wind-index par instance, poses
    // par foliage_wind_finalize_level). `wind_state` = 4 flottants par emplacement de ressort
    // (position x/z, vitesse x/z, comme Tie3::m_wind_vectors). `wind_texels` = (s.x, s.z, k, on) par
    // matrix_idx, televerse chaque image dans `wind_tex` (RGBA32F, largeur = nombre de matrices),
    // que shrub.vert lit par l'attribut 9.
    const tfrag3::ShrubTree* src = nullptr;
    GLuint wind_tex = 0;
    bool contact_active = false;
    uint64_t contact_instances = 0;
    std::vector<float> wind_state;
    std::vector<float> wind_texels;
    u32 wind_last_time = 0;
    // lighting-ao-indirect (i) : l'image dont les texels sont DANS la texture, et celle dont
    // l'integration les a produits. `wind_upload_frame` interdit deux televersements dans la
    // meme image — la prepasse tourne plusieurs fois par image sondee (bras livre, bras sans
    // deplacement, bras sans decoupe) et chacune passe par le meme appel.
    uint64_t wind_upload_frame = (uint64_t)-1;
    bool wind_seeded = false;
    bool wind_active = false;  // sidecar valide ET au moins une instance a raideur > 0
    bool wind_logged = false;
    const u32* index_data = nullptr;
    std::vector<bool> proto_vis_mask;
    std::unordered_map<std::string, std::vector<u32>> proto_name_to_idx;
    // Gperf-particles round 3: level-static single-draw index cache. When
    // perf_shrub_static_idx is on, the index list (built once by
    // make_all_visible_index_list) and its GPU upload are done a single time at
    // level load; per-frame the build+upload are skipped and the draw loop reads
    // cached_draw_idx instead of m_cache.draw_idx_temp.
    std::vector<std::pair<int, int>> cached_draw_idx;
    bool idx_cached = false;
    u32 cached_idx_count = 0;
    std::vector<u32> soft_cached_indices;

    struct {
      u32 draws = 0;
      u32 wind_draws = 0;
      Filtered<float> cull_time;
      Filtered<float> index_time;
      Filtered<float> tod_time;
      Filtered<float> setup_time;
      Filtered<float> draw_time;
      Filtered<float> tree_time;
    } perf;
  };

  struct {
    GLuint decal;
  } m_uniforms;

  std::vector<Tree> m_trees;
  std::string m_level_name;
  const std::vector<GLuint>* m_textures;
  u64 m_load_id = -1;

  std::vector<math::Vector<u8, 4>> m_color_result;

  static constexpr int TIME_OF_DAY_COLOR_COUNT = 8192;
  bool m_has_level = false;

  struct Cache {
    std::vector<std::pair<int, int>> draw_idx_temp;
    std::vector<u32> index_temp;
    std::vector<std::pair<int, int>> multidraw_offset_per_stripdraw;
    std::vector<GLsizei> multidraw_count_buffer;
    std::vector<void*> multidraw_index_offset_buffer;
  } m_cache;
  TfragPcPortData m_pc_port_data;
  const u8* m_proto_vis_data = nullptr;
  int m_proto_vis_data_size = 0;

};

// Successful linked contact-uniform upload batches, not a GPU displacement verdict.
uint64_t shrub_contact_uniform_batches();

struct ShrubContactStats {
  uint64_t uploads = 0;
  uint64_t binding_failures = 0;
  uint64_t shrub_instances = 0;
  uint64_t jak_samples = 0;
  uint64_t object_samples = 0;
};
// Cumulative linked batches and their eligible population/source counts; no overlap/GPU claim.
ShrubContactStats shrub_contact_stats();
