#include "game/system/load_gate.h"

#include <chrono>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "fmt/core.h"

namespace load_gate {
namespace {

std::mutex g_mutex;

// Levels the renderer says are drawable right now.
std::unordered_set<std::string> g_resident;

// True once the renderer has published ANY level. Until then the gate has no
// way to tell "not loaded yet" from "nobody is feeding me", so it opens.
// This is what makes the barrier fail-open on a build where the feed is
// missing: it can slow a scene down only on a runtime that actually reports
// residency.
bool g_feed_alive = false;

struct ArmedScene {
  std::chrono::steady_clock::time_point armed_at;
  int timeout_ms = 0;
};
std::unordered_map<std::string, ArmedScene> g_armed;

bool is_real_level_name(const char* n) {
  if (!n || !*n) {
    return false;
  }
  const std::string s(n);
  return s != "none" && s != "#f" && s != "#<symbol #f>";
}

// caller holds g_mutex
bool resident_locked(const std::string& n) {
  return g_resident.find(n) != g_resident.end();
}

int elapsed_ms(const std::chrono::steady_clock::time_point& t0) {
  return (int)std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now() - t0)
      .count();
}

}  // namespace

void mark_level_resident(const std::string& level_name) {
  if (level_name.empty()) {
    return;
  }
  std::lock_guard<std::mutex> lk(g_mutex);
  g_feed_alive = true;
  g_resident.insert(level_name);
}

void mark_level_evicted(const std::string& level_name) {
  std::lock_guard<std::mutex> lk(g_mutex);
  g_resident.erase(level_name);
}

bool level_is_resident(const char* level_name) {
  if (!is_real_level_name(level_name)) {
    return true;  // nothing asked for -> nothing to wait on
  }
  std::lock_guard<std::mutex> lk(g_mutex);
  if (!g_feed_alive) {
    return true;  // fail-open
  }
  return resident_locked(level_name);
}

bool wants_blocking_loads() {
  std::lock_guard<std::mutex> lk(g_mutex);
  // Prune barriers nobody came back for. A scene can be killed (state change,
  // process death) while it is suspended inside the wait loop, and then GOAL
  // never polls scene_ready again. Without this, one aborted cutscene would
  // leave the renderer on the blocking load path for the rest of the session.
  // Expiring here — on the C++ side, on the deadline the arm already carries —
  // means the cleanup cannot depend on GOAL cooperating.
  for (auto it = g_armed.begin(); it != g_armed.end();) {
    if (elapsed_ms(it->second.armed_at) >= it->second.timeout_ms) {
      fmt::print("LOADGATE expire scene={} (barrier abandoned, arm dropped)\n", it->first);
      it = g_armed.erase(it);
    } else {
      ++it;
    }
  }
  return !g_armed.empty();
}

int scene_ready(const char* scene, const char* level0, const char* level1, int timeout_ms) {
  const std::string scene_name = scene ? scene : "(unnamed)";
  const bool want0 = is_real_level_name(level0);
  const bool want1 = is_real_level_name(level1);
  const std::string l0 = want0 ? level0 : "";
  const std::string l1 = want1 ? level1 : "";

  // Clamp to something a human would accept staring at a black screen, and
  // never accept a non-positive deadline (that would be a barrier that can
  // never open on its own).
  if (timeout_ms < 250) {
    timeout_ms = 250;
  }
  if (timeout_ms > 30000) {
    timeout_ms = 30000;
  }

  std::lock_guard<std::mutex> lk(g_mutex);

  if (!want0 && !want1) {
    g_armed.erase(scene_name);
    return 1;
  }

  if (!g_feed_alive) {
    // Nobody publishes residency on this runtime. Do not hold the scene.
    g_armed.erase(scene_name);
    return 1;
  }

  auto it = g_armed.find(scene_name);
  if (it == g_armed.end()) {
    ArmedScene a;
    a.armed_at = std::chrono::steady_clock::now();
    a.timeout_ms = timeout_ms;
    it = g_armed.emplace(scene_name, a).first;
    fmt::print("LOADGATE arm scene={} levels={}{}{} timeout={}ms\n", scene_name, want0 ? l0 : "-",
               (want0 && want1) ? "," : "", want1 ? l1 : "", timeout_ms);
  }

  const bool have0 = !want0 || resident_locked(l0);
  const bool have1 = !want1 || resident_locked(l1);
  const int waited = elapsed_ms(it->second.armed_at);

  if (have0 && have1) {
    fmt::print("LOADGATE open scene={} waited={}ms reason=resident\n", scene_name, waited);
    g_armed.erase(it);
    return 1;
  }

  if (waited >= it->second.timeout_ms) {
    std::string missing;
    if (want0 && !have0) {
      missing += l0;
    }
    if (want1 && !have1) {
      if (!missing.empty()) {
        missing += ",";
      }
      missing += l1;
    }
    fmt::print("LOADGATE open scene={} waited={}ms reason=timeout missing={}\n", scene_name, waited,
               missing);
    g_armed.erase(it);
    return 1;
  }

  return 0;
}

void scene_release(const char* scene) {
  const std::string scene_name = scene ? scene : "(unnamed)";
  std::lock_guard<std::mutex> lk(g_mutex);
  g_armed.erase(scene_name);
}

void reset_for_test() {
  std::lock_guard<std::mutex> lk(g_mutex);
  g_resident.clear();
  g_armed.clear();
  g_feed_alive = false;
}

}  // namespace load_gate
