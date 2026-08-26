#pragma once

#include "common/common_types.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/util/Timer.h"

#include "game/graphics/texture/TexturePool.h"

#include "third-party/glad/include/glad/glad.h"

struct LevelData {
  std::unique_ptr<tfrag3::Level> level;
  std::vector<GLuint> textures;
  u64 load_id = UINT64_MAX;

  struct TieOpenGL {
    GLuint vertex_buffer;
    GLuint tangent_buffer;  // REOPEN#7 per-vertex tangent VBO (parallel to vertex_buffer), loc 5
    GLuint index_buffer;
    bool has_wind = false;
    GLuint wind_indices;
  };
  std::array<std::vector<TieOpenGL>, tfrag3::TIE_GEOS> tie_data;
  std::array<std::vector<GLuint>, tfrag3::TIE_GEOS> tfrag_vertex_data;
  // REOPEN#7 per-vertex tangent VBOs (parallel 1:1 to tfrag_vertex_data), attribute location 5.
  std::array<std::vector<GLuint>, tfrag3::TIE_GEOS> tfrag_tangent_data;
  std::vector<GLuint> shrub_vertex_data;
  GLuint collide_vertices;

  GLuint merc_vertices;
  GLuint merc_indices;
  // Gmemory-ceiling-and-crash : le nombre de sommets merc SURVIT a la liberation du tableau
  // CPU (`release_uploaded_merc_vertices`). Un seul lecteur en avait besoin — le diagnostic
  // F1A-MERC-VERIFY de Merc2 — et lire `.size()` d'un vecteur rendu afficherait 0 sans que
  // rien ne le dise.
  size_t merc_vertex_count = 0;
  // Gmemory-ceiling-and-crash : vrai des que les tangentes et les sommets CPU de tfrag/tie de
  // ce niveau ont ete rendus. Le drapeau existe parce que la liberation N'EST PAS idempotente :
  // `precompute_uv_density_then_release_vertices` MESURE la densite UV avant de liberer, donc un
  // second passage la re-mesurerait sur des tableaux vides et ecraserait le cache avec la valeur
  // par defaut — un faux silencieux sur le relief, exactement le defaut que ce cache evite.
  bool cpu_geo_released[2] = {false, false};  // [0] = tfrag, [1] = tie
  std::unordered_map<std::string, const tfrag3::MercModel*> merc_model_lookup;

  GLuint hfrag_vertices;
  GLuint hfrag_indices;

  int frames_since_last_used = 0;
};

struct MercRef {
  const tfrag3::MercModel* model = nullptr;
  u64 load_id = 0;
  const LevelData* level = nullptr;
  bool operator==(const MercRef& other) const {
    return model == other.model && load_id == other.load_id;
  }
};

struct LoaderInput {
  LevelData* lev_data;
  TexturePool* tex_pool;
  std::unordered_map<std::string, std::vector<MercRef>>* mercs;
};

class LoaderStage {
 public:
  LoaderStage(const std::string& name) : m_name(name) {}
  virtual bool run(Timer& timer, LoaderInput& data) = 0;
  virtual void reset() = 0;
  virtual ~LoaderStage() = default;
  const std::string& name() const { return m_name; }

 protected:
  std::string m_name;
};
