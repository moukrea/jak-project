#pragma once

#include <condition_variable>
#include <mutex>
#include <thread>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Timer.h"

#include "game/graphics/opengl_renderer/loader/common.h"
#include "game/graphics/texture/TexturePool.h"

// Gloading-screen (owner 2026-08-29, retour n.4) : taille d'une TRANCHE de chargement bloquant
// quand une barriere est fermee, donc quand l'ecran de chargement est affiche et doit continuer
// de bouger. Ce n'est pas un gout, c'est un encadrement par deux bornes mesurees :
//   - PLAFOND 66,7 ms : au-dela de 4 frames, l'horloge virtuelle de l'appareil plafonne son
//     increment et JETTE le retard (android/gk_android_main.cpp:787-789, :793-799, :833-835).
//     Une frame plus longue que ca fait passer toute animation pilotee par le temps de jeu au
//     ralenti, sans qu'aucune trace ne le signale. La tranche + le rendu doivent rester dessous.
//   - PLANCHER 16,7 ms : sous la periode d'une frame, le limiteur de frames ajouterait une
//     attente de vsync — du temps machine perdu pour le chargement, en pure perte.
// 40 ms laisse ~25 ms de marge au rendu sous le plafond. Le chargement garde alors ~80 % du temps
// machine, contre 100 % sur le chemin d'avant et 27 % (4,5 ms sur 16,7) sur le chemin budgete.
static constexpr float kLoadingScreenSliceMs = 40.f;

// CONTROLE PAR ABLATION. `OG_LOADSCREEN_SLICE_MS=0` restitue EXACTEMENT le chemin d'avant (une
// tranche non bornee, donc le gel) sur le MEME binaire : c'est ce qui permet de publier un
// avant/apres qui ne differe que par cette valeur, au lieu de comparer deux constructions.
float loading_screen_slice_ms();

class Loader {
 public:
  static constexpr float TIE_LOAD_BUDGET = 1.5f;
  static constexpr float SHARED_TEXTURE_LOAD_BUDGET = 3.f;
  Loader(const fs::path& base_path, int max_levels);
  ~Loader();
  void update(TexturePool& tex_pool);
  // Gplayability-input-and-loadgate: `announce` exists because a closed scene
  // barrier calls this EVERY frame while it holds the picture. The blackout
  // caller keeps its original, load-bearing log lines; the gate's repeat calls
  // stay silent so they cannot flood the device log (their evidence is the
  // LOADGATE lines instead).
  // Gloading-screen (owner 2026-08-29, retour n.4) : `budget_ms > 0` = « avance autant que tu
  // peux en budget_ms, puis RENDS LA MAIN ». La barriere rappelle cette fonction a chaque frame,
  // donc le travail total est identique ; ce qui change est qu'une frame est PRODUITE entre deux
  // tranches. Voir le pave de l'implementation pour pourquoi le defaut vient de la.
  void update_blocking(TexturePool& tex_pool, bool announce = true, float budget_ms = 0.f);
  const LevelData* get_tfrag3_level(const std::string& level_name);
  std::optional<MercRef> get_merc_model(const char* model_name);
  const tfrag3::Level& load_common(TexturePool& tex_pool, const std::string& name);
  void set_want_levels(const std::vector<std::string>& levels);
  void set_active_levels(const std::vector<std::string>& levels);
  std::vector<LevelData*> get_in_use_levels();
  void draw_debug_window();
  void debug_print_loaded_levels();

 private:
  void loader_thread();
  bool upload_textures(Timer& timer, LevelData& data, TexturePool& texture_pool);

  // Gloading-screen : ECART REEL entre deux tranches de chargement bloquant, donc entre deux
  // frames reellement presentees pendant que l'ecran de chargement est affiche. Mesure prise sur
  // une VRAIE horloge (`Timer`, steady_clock) et pas sur celle de GOAL : sur l'appareil
  // `__read-ee-timer` est une horloge VIRTUELLE plafonnee a 4 frames
  // (android/gk_android_main.cpp:793-799), elle SOUS-ESTIME donc structurellement un gel.
  Timer m_ls_gap_timer;
  Timer m_ls_gap_report;
  bool m_ls_gap_armed = false;
  double m_ls_gap_max_ms = 0.0;
  double m_ls_gap_sum_ms = 0.0;
  int m_ls_gap_n = 0;
  // Gloading-screen (owner 2026-08-30, « silky smooth ») : combien de temps le dernier appel a
  // passe DANS le chargeur. Ce qui reste de la frame de 60 Hz une fois le rendu et la logique
  // payes, c'est la tranche qu'on peut donner au chargeur sans faire tomber la cadence.
  double m_ls_last_work_ms = 0.0;

  const std::string* get_most_unloadable_level();

  // used by game and loader thread
  std::unordered_map<std::string, std::unique_ptr<LevelData>> m_initializing_tfrag3_levels;

  LevelData m_common_level;

  std::string m_level_to_load;

  std::thread m_loader_thread;
  std::mutex m_loader_mutex;
  std::condition_variable m_loader_cv;
  std::condition_variable m_file_load_done_cv;
  bool m_want_shutdown = false;
  uint64_t m_id = 0;

  // used only by game thread
  std::unordered_map<std::string, std::unique_ptr<LevelData>> m_loaded_tfrag3_levels;

  std::unordered_map<std::string, std::vector<MercRef>> m_all_merc_models;

  std::vector<std::string> m_desired_levels;
  std::vector<std::string> m_active_levels;
  std::vector<std::unique_ptr<LoaderStage>> m_loader_stages;
  std::vector<GLuint> m_garbage_textures;
  std::vector<GLuint> m_garbage_buffers;

  fs::path m_base_path;
  int m_max_levels = 0;
  // Gmemory-ceiling-and-crash : compte a rebours de frames avant une purge du tas. Les purges
  // posees a la fin d'un chargement tombent AVANT la premiere image ; or le maximum de la course
  // est mesure ~1 s plus tard, quand le rendu a fini de se mettre en route (le RSS monte de
  // 782 a 814 Mo puis redescend a 793). Cette purge-la tombe APRES, une seule fois par
  // chargement. -1 = pas de purge en attente.
  int m_frames_until_purge = -1;
};
