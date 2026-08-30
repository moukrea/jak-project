#pragma once

#include <array>
#include <list>
#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/global_profiler/GlobalProfiler.h"
#include "common/util/Timer.h"

#include "game/graphics/opengl_renderer/buckets.h"

enum class ProfilerSort { NONE = 0, TIME = 1, DRAW_CALLS = 2, TRIANGLES = 3 };

struct ProfilerStats {
  float duration = 0;  // seconds
  u32 draw_calls = 0;
  u32 triangles = 0;

  void add_draw_stats(const ProfilerStats& other) {
    draw_calls += other.draw_calls;
    triangles += other.triangles;
  }
};

class ScopedProfilerNode;

class ProfilerNode {
 public:
  ProfilerNode(const std::string& name);
  ProfilerNode* make_child(const std::string& name);
  ScopedProfilerNode make_scoped_child(const std::string& name);
  void sort(ProfilerSort mode);
  void finish();
  void dump_stats_helper(std::string& str, int depth, float min_ms) const;

  bool finished() const { return m_finished; }
  const std::string& name() const { return m_name; }

  void add_draw_call(int count = 1) { m_stats.draw_calls += count; }
  void add_tri(int count = 1) { m_stats.triangles += count; }
  float get_elapsed_time() const { return m_timer.getSeconds(); }
  const ProfilerStats& stats() const { return m_stats; }

 private:
  friend class Profiler;
  void to_string_helper(std::string& str, int depth) const;

  std::string m_name;
  ProfilerStats m_stats;
  // Ggrass-crash (owner 2026-08-30) : `std::deque`, ET C'EST LE CORRECTIF DU PLANTAGE APPAREIL.
  //
  // `ProfilerNode::make_child` rend `&m_children.back()` — UN POINTEUR DANS LE CONTENEUR — et
  // `ScopedProfilerNode` le garde brut jusqu'a son destructeur. Avec un `std::vector`, tout
  // `emplace_back` ULTERIEUR sur le MEME parent REALLOUE et invalide tous les pointeurs deja
  // rendus. Or `dispatch_buckets_jak1` en tient un VIVANT pendant toute l'iteration
  // (`bucket_prof`, android_opengl_renderer.cpp:1332) et en cree DEUX AUTRES sur le meme parent
  // dans la meme iteration : « ao-draw » (:1445) et « grass-draw » (:1461).
  //
  // D'OU LE DEFAUT QUE L'OWNER A ISOLE PAR BISSECTION. Herbe eteinte, il n'y a qu'un enfant par
  // iteration et le pointeur reste valide. Herbe allumee, le second `emplace_back` reallouait et
  // `bucket_prof.m_node` DEVENAIT PENDANT ; son destructeur appelait `finish()` sur de la memoire
  // liberee, dont `m_name` (un `std::string`) et `m_children` sont alors des ordures — et le
  // formatage de ce nom demandait une allocation de la taille lue dans les ordures.
  // MESURE, Redmi, 12 courses sur 12 : `malloc(8027506242768285312) failed`, soit
  // `0x6f676e65706f2e80`, octets `80 2e 6f 70 65 6e 67 6f` = « \x80.opengo » — un morceau du
  // chemin `/data/user/0/org.opengoal.gk.jak1/...` laisse dans le bloc libere. La taille demandee
  // ETAIT le contenu de la memoire liberee.
  // ET C'EST POURQUOI AUCUN `try/catch` NE POUVAIT AIDER : `~ScopedProfilerNode` est implicitement
  // `noexcept`, donc l'exception y appelle `std::terminate` SANS CHERCHER DE HANDLER. Deux gardes
  // presents dans le binaire installe n'ont jamais tire, et `libc++abi` disait « uncaught ».
  //
  // `std::list` garantit que l'insertion N'INVALIDE AUCUNE reference aux elements deja presents
  // (contrairement a `vector`). Les pointeurs rendus par `make_child` restent donc valides pour
  // toute la duree de vie du parent. `std::deque` aurait suffi aussi, mais la libc++ du NDK exige
  // un type COMPLET pour l'instancier, et `ProfilerNode` se contient lui-meme : `std::list` est
  // explicitement autorisee avec un type incomplet, `std::deque` non.
  // Le tri passe de `std::sort` a `list::sort` (pas d'iterateurs a acces aleatoire) ; il ne tourne
  // qu'en FIN d'image, quand plus aucun `ScopedProfilerNode` n'est vivant.
  std::list<ProfilerNode> m_children;
  Timer m_timer;
  bool m_finished = false;
};

class ScopedProfilerNode {
 public:
  ScopedProfilerNode(ProfilerNode* node)
      : m_node(node), m_global_event(scoped_prof(node->name().c_str())) {}
  ScopedProfilerNode(const ScopedProfilerNode& other) = delete;
  ScopedProfilerNode& operator=(const ScopedProfilerNode& other) = delete;
  ProfilerNode* make_child(const std::string& name) { return m_node->make_child(name); }
  ScopedProfilerNode make_scoped_child(const std::string& name) {
    return m_node->make_scoped_child(name);
  }
  ~ScopedProfilerNode() { m_node->finish(); }

  void add_draw_call(int count = 1) { m_node->add_draw_call(count); }
  void add_tri(int count = 1) { m_node->add_tri(count); }
  float get_elapsed_time() const { return m_node->get_elapsed_time(); }

 private:
  ProfilerNode* m_node;
  ScopedEvent m_global_event;
};

class Profiler {
 public:
  Profiler();
  void clear();
  void draw();
  void finish();

  float root_time() const { return m_root.m_stats.duration; }

  std::string to_string();
  // per-node "ms draws tris name" dump, skipping nodes under min_ms with no draws
  std::string dump_stats(float min_ms);
  ProfilerNode* root() { return &m_root; }

 private:
  void draw_node(ProfilerNode& node, bool expand, int depth, float start_time);

  struct BarEntry {
    float duration;
    float rgba[4];
  };

  int m_mode_selector = 0;
  ProfilerNode m_root;
};

class FramePlot {
 public:
  void push(float val);
  void draw(float max);

 private:
  static constexpr int SIZE = 60 * 5;
  float m_buffer[SIZE] = {};
  int m_idx = 0;
};

struct SmallProfilerStats {
  int triangles, draw_calls;
  float time_per_category[(int)BucketCategory::MAX_CATEGORIES];
};

class SmallProfiler {
 public:
  void draw(const std::string& load_status, const SmallProfilerStats& stats);

 private:
  std::array<FramePlot, (int)BucketCategory::MAX_CATEGORIES> m_plots;
};