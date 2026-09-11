#include "mesh_browser_census.h"

#include <atomic>

// Trois atomiques et rien d'autre : le rapport vient du fil UI d'Android (`TouchOverlayView`),
// la lecture du fil GOAL (`pc_autoport_frame`). `relaxed` suffit — aucune donnee n'est publiee
// derriere ces compteurs, ils SONT la donnee.
namespace {
std::atomic<uint32_t> s_overlay_sites{0};
std::atomic<uint32_t> s_overlay_control{0};
std::atomic<uint32_t> s_overlay_reports{0};
}  // namespace

namespace mesh_browser_census {

void report_overlay(uint32_t sites, uint32_t control) {
  s_overlay_sites.store(sites, std::memory_order_relaxed);
  s_overlay_control.store(control, std::memory_order_relaxed);
  s_overlay_reports.fetch_add(1, std::memory_order_relaxed);
}

uint32_t overlay_sites() {
  // INCONNU = DEFAUT. Voir l'en-tete : un rapport absent ne vaut pas un overlay propre.
  if (s_overlay_reports.load(std::memory_order_relaxed) == 0) {
    return kUnreportedPenalty;
  }
  return s_overlay_sites.load(std::memory_order_relaxed);
}

uint32_t overlay_control() {
  return s_overlay_control.load(std::memory_order_relaxed);
}

uint32_t overlay_reported() {
  return s_overlay_reports.load(std::memory_order_relaxed);
}

}  // namespace mesh_browser_census
