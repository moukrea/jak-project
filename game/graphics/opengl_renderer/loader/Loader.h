#pragma once

#include <condition_variable>
#include <mutex>
#include <thread>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Timer.h"

#include "game/graphics/opengl_renderer/loader/common.h"
#include "game/graphics/texture/TexturePool.h"

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
  void update_blocking(TexturePool& tex_pool, bool announce = true);
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
