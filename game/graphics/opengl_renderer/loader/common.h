#pragma once

#include <atomic>

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
    // Grecharged-foliage-wind3 (defaut D2) : balancement par sommet, DEUX octets (poids + phase
    // d'instance), VBO parallele a vertex_buffer, attribut 7 du VAO TIE. Meme cycle de vie que
    // vertex_buffer : cree par TieLoadStage, collecte par Loader::update.
    GLuint sway_buffer;
    GLuint index_buffer;
    bool has_wind = false;
    GLuint wind_indices;
  };
  std::array<std::vector<TieOpenGL>, tfrag3::TIE_GEOS> tie_data;
  std::array<std::vector<GLuint>, tfrag3::TIE_GEOS> tfrag_vertex_data;
  // REOPEN#7 per-vertex tangent VBOs (parallel 1:1 to tfrag_vertex_data), attribute location 5.
  std::array<std::vector<GLuint>, tfrag3::TIE_GEOS> tfrag_tangent_data;
  std::vector<GLuint> shrub_vertex_data;
  // foliage-wind (owner 2026-09-03) : poids + phase de balancement par sommet SHRUB, deux octets,
  // VBO parallele a shrub_vertex_data (1:1), attribut 7 du VAO shrub — le meme attribut que le TIE.
  std::vector<GLuint> shrub_sway_data;
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

  // Gcutscene-npc-flicker — L'AGE DU NIVEAU NE VOYAIT QUE LE FOND.
  //
  // `frames_since_last_used` n'est remis a zero qu'a DEUX endroits : `Loader::get_tfrag3_level`
  // (Loader.cpp:76), appelee par les renderers de FOND (TFragment, Tie3, Shrub, Hfrag), et la
  // boucle de `Loader::update` pour les niveaux de `m_active_levels`. Or `set_active_levels`
  // n'existe pas pour jak1 : il n'y a de `pc_set_active_levels` que dans kernel/jak2, jak3 et
  // jakx. `m_active_levels` reste donc VIDE pour toute la partie, et le seul rafraichissement
  // reel est le passage des renderers de fond.
  //
  // Un niveau qui ne fournit que de l'AVANT-PLAN — c'est-a-dire exactement un PNJ de
  // cinematique — vieillit alors d'une image par image pendant qu'il est a l'ecran, franchit
  // les 180 images de `get_most_unloadable_level` et se fait EVINCER. L'eviction efface ses
  // modeles merc de `m_all_merc_models` (Loader.cpp:1824), `get_merc_model` rend `nullopt`, et
  // Merc2.cpp:2330 sort sans rien dessiner : l'acteur disparait jusqu'a la fin du rechargement.
  //
  // `Loader::get_merc_model` avait le geste qu'il fallait, EN COMMENTAIRE :
  //     // it->second.front().parent_level->frames_since_last_used = 0;
  // On le retablit ici, par une marque separee — pour garder UN SEUL ecrivain de
  // `frames_since_last_used` (la boucle de `Loader::update`) et une seule decision d'age.
  //
  // `mutable` : `MercRef::level` est un `const LevelData*` et la marque n'est pas un etat du
  // niveau, c'est une trace de lecture.
  mutable std::atomic<uint64_t> last_merc_use_frame{0};

  // L'AGE CONTREFACTUEL : celui qu'aurait le niveau SANS le maintien ci-dessus. AUCUNE decision
  // ne le lit. Il sert uniquement a chiffrer, sur le binaire LIVRE, combien de fois le correctif
  // a empeche un niveau de devenir evincable pendant qu'il dessinait un acteur. Sans lui, le
  // correctif publierait un zero qu'on ne pourrait pas distinguer d'une course ou la situation
  // ne s'est jamais presentee.
  int frames_since_last_used_no_merc = 0;

  // Gcutscene-npc-flicker (essai 16) — DEPUIS COMBIEN D'IMAGES LE JEU NE VEUT PLUS DE CE NIVEAU.
  //
  // `m_desired_levels` vient de `__pc-set-levels` (goal_src/jak1/engine/level/level.gc:1419 ->
  // game/kernel/jak1/kmachine.cpp:721), qui prend EXACTEMENT deux arguments : `level0` et
  // `level1`. En jak1 la liste porte donc au plus DEUX noms, jamais trois. Un troisieme niveau
  // resident est par construction un RESCAPE — un niveau que GOAL a cesse de nommer et qu'il ne
  // dessine plus.
  //
  // POURQUOI CE COMPTEUR EXISTE. `get_most_unloadable_level` n'avait que deux passes : « pas
  // desire ET age > 180 », puis « age > 180 », cette seconde-la ignorant `m_desired_levels`. Un
  // rescape JEUNE (age <= 180, il vient d'etre lache) echappe donc a la premiere passe, et la
  // seconde sacrifie a sa place un niveau que le jeu VEUT ENCORE. C'est l'ordre inverse du bon
  // sens : on jette ce qui est demande en gardant ce qui ne l'est plus. Le rechargement qui suit
  // coute 202 a 317 images sur l'appareil de l'owner, pendant lesquelles ses PNJ n'existent plus.
  //
  // L'age de dessin (`frames_since_last_used`) ne peut pas repondre a cette question : un rescape
  // vient justement d'etre dessine. Il faut une horloge separee, celle de l'INTENTION du jeu.
  int frames_not_desired = 0;
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
