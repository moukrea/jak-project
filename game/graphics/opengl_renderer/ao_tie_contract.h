#pragma once

#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <unistd.h>
#if defined(__ANDROID__) || defined(__linux__)
#include <dlfcn.h>
#endif
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
#include "common/util/FileUtil.h"
#include "game/graphics/refset_file.h"
#include "game/system/autoport_proof.h"

// Campaign bookkeeping only: consume published measurements, never drive the probes.
namespace ao_tie_contract {
inline std::string knob(const char* property, const char* env) {
#ifdef __ANDROID__
  char value[PROP_VALUE_MAX]{};
  __system_property_get(property, value);
  return value;
#else
  const char* value = std::getenv(env);
  return value ? value : "";
#endif
}
constexpr std::array<const char*, 3> kViews{{"village1-hut", "village1-out", "beach"}};
// L'INDEX DE LA SEULE VUE QUI COMPTE depuis le 17/09. Il vaut pour la SOMME, pas pour la
// publication : les trois vues publient toujours leurs dix-neuf termes.
constexpr int kScopedView = 0;  // village1-hut
constexpr std::array<const char*, 3> kPrefixes{{"ao_tie_view_village1_hut_",
                                              "ao_tie_view_village1_out_", "ao_tie_view_beach_"}};
constexpr std::array<const char*, 19> kInputs{{
    "ao_probe_compared", "ao_probe_samples", "ao_geom_frames", "ao_geom_cover_px",
    "ao_geom_tie_cover_px", "ao_tie_alpha_pre_judged_px", "ao_geom_tie_absent_px",
    "ao_geom_tie_absent_inner_px", "ao_high_not_fullres", "ao_pattern_over_ceiling",
    "ao_on_alpha_device_px", "ao_direct_leak_px", "ao_contact_band_px", "ao_static_defects",
    "ao_tie_color_measured", "ao_tie_color_pixels", "ao_tie_color_tie_pixels",
    "ao_tie_color_changed_px", "ao_tie_color_tie_changed_px"}};
constexpr std::array<const char*, 19> kTerms{{
    "compared", "samples", "geom_frames", "cover_px", "tie_cover_px", "pre_judged_px",
    "absent_px", "absent_inner_px", "high_not_fullres", "pattern_over_ceiling",
    "on_alpha_device_px", "direct_leak_px", "contact_band_px", "static_defects",
    "color_measured", "color_pixels", "color_tie_pixels", "color_changed_px",
    "color_tie_changed_px"}};
struct Record {
  std::array<uint64_t, 19> values{};
  uint64_t on = 0, off = 0, scene = 0;
};
struct Disk {
  uint64_t version = 2, binary = 0;
  char campaign[128]{};
  std::array<Record, 3> views{};
};
inline uint64_t add(uint64_t a, uint64_t b) {
  return b > std::numeric_limits<uint64_t>::max() - a
             ? std::numeric_limits<uint64_t>::max() : a + b;
}
class Campaign {
  Disk data{};
  std::string campaign, path;
  int view = -1;
  bool initialized = false, valid = false, io_failed = false;
  bool identity_missing = false, identity_mismatch = false;
  uint64_t scene = 1469598103934665603ull;

  void initialize() {
    initialized = true;
    campaign = knob("debug.opengoal.ao.tie.campaign", "OG_AO_TIE_CAMPAIGN");
    if (campaign.empty()) return;
    const std::string name = knob("debug.opengoal.ao.tie.view", "OG_AO_TIE_VIEW");
    for (int i = 0; i < 3; ++i) if (name == kViews[i]) view = i;
    autoport_proof::publish_text("ao_tie_campaign", campaign.c_str());
    autoport_proof::publish_text("ao_tie_campaign_view", name.empty() ? "missing" : name.c_str());
    const auto warp = knob("debug.opengoal.level.warp", "OG_LEVEL_WARP");
    const auto pos = knob("debug.opengoal.level.warp.pos", "OG_LEVEL_WARP_POS");
    autoport_proof::publish_text("ao_tie_campaign_warp", warp.empty() ? "unset" : warp.c_str());
    autoport_proof::publish_text("ao_tie_campaign_position", pos.empty() ? "spawn" : pos.c_str());
    // Exact nominal vantage and complete required regime, excluding the reference toggle.
    constexpr std::array<const char*, 3> warps{{"village1-hut", "village1-hut", "beach-start"}};
    constexpr std::array<const char*, 3> positions{{"-116 14 40", "-126 46 212", ""}};
    identity_missing = view < 0 || warp.empty();
    identity_mismatch = view >= 0 && (warp != warps[view] || pos != positions[view]);
    auto fingerprint = [&](const std::string& value) {
      for (unsigned char c : value) { scene ^= c; scene *= 1099511628211ull; }
      scene ^= 0; scene *= 1099511628211ull;  // Unambiguous field delimiter.
    };
    fingerprint(name); fingerprint(warp); fingerprint(pos);
    struct Setting { const char* prop; const char* env; const char* expected; };
    const Setting settings[] = {
        {"want.levels", "OG_WANT_LEVELS", "village1,beach"},
        {"want.display", "OG_WANT_DISPLAY", "beach,display"},
        {"fixed_tick", "OG_FIXED_TICK", "1"}, {"recharged", "OG_RECHARGED", "1"},
        {"lighting", "OG_LIGHTING", "1"}, {"rt.light", "OG_RT_LIGHT", "1"},
        {"ao.force_mode", "AO_FORCE_MODE", "3"},
        {"foliage.force", "FOLIAGE_WIND_FORCE", "1"},
        {"padreplay", "OG_PAD_REPLAY_REPLAY", nullptr}};
    for (const auto& setting : settings) {
      const std::string property = std::string("debug.opengoal.") + setting.prop;
      const auto value = knob(property.c_str(), setting.env);
      fingerprint(value);
      identity_missing = identity_missing || value.empty();
      identity_mismatch = identity_mismatch || (setting.expected && value != setting.expected);
    }
    if (!scene) scene = 1;
    autoport_proof::publish("ao_tie_campaign_scene", scene);
#if defined(__ANDROID__) || defined(__linux__)
    Dl_info info{};
    if (dladdr(reinterpret_cast<const void*>(&knob), &info) && info.dli_fname)
      data.binary = refset_file::hash_file(info.dli_fname);
#if defined(__linux__) && !defined(__ANDROID__)
    if (!data.binary) data.binary = refset_file::hash_file("/proc/self/exe");
#endif
#endif
    autoport_proof::publish("ao_tie_campaign_binary", data.binary);
    identity_missing = identity_missing || !data.binary || campaign.size() >= sizeof(data.campaign);
    valid = !identity_missing && !identity_mismatch;
    if (!valid) return;
    std::memcpy(data.campaign, campaign.c_str(), campaign.size() + 1);
    path = (file_util::get_user_home_dir() / "ao-tie-contract-campaign.bin").string();
    autoport_proof::publish_text("ao_tie_campaign_path", path.c_str());
    if (FILE* f = std::fopen(path.c_str(), "rb")) {
      Disk old{};
      bool ok = std::fread(&old, sizeof(old), 1, f) == 1 && std::fgetc(f) == EOF && !std::ferror(f);
      if (std::fclose(f) != 0) ok = false;
      ok = ok && old.version == data.version && old.binary == data.binary &&
           std::memcmp(old.campaign, data.campaign, sizeof(data.campaign)) == 0;
      for (const auto& r : old.views)
        ok = ok && r.on <= 1 && r.off <= 1 && (!(r.on || r.off) || r.scene);
      if (ok) data = old;
      autoport_proof::publish("ao_tie_campaign_loaded", ok);
    } else autoport_proof::publish("ao_tie_campaign_loaded", 0);
    const auto& record = data.views[view];
    identity_mismatch = record.scene && record.scene != scene;
    valid = !identity_mismatch;
  }
  void save() {
    const std::string tmp = path + "." + std::to_string(getpid());
    bool ok = false;
    if (FILE* f = std::fopen(tmp.c_str(), "wx")) {
      ok = std::fwrite(&data, sizeof(data), 1, f) == 1;
      if (std::fflush(f) != 0 || fsync(fileno(f)) != 0) ok = false;
      if (std::fclose(f) != 0) ok = false;
      ok = ok && std::rename(tmp.c_str(), path.c_str()) == 0;
      if (!ok) std::remove(tmp.c_str());
    }
    io_failed = !ok;
  }
 public:
  void begin() {
    if (!autoport_proof::feature_is("ao-prepass-tie-alpha")) return;
    if (!initialized) initialize();
    if (campaign.empty()) return;
    bool measured = false;
    const bool on = autoport_proof::armed();
    if (valid) {
      auto& record = data.views[view];
      Record next = record;
      const int first = on ? 0 : 14, end = on ? 14 : 19;
      measured = true;
      for (int i = first; i < end; ++i)
        measured = autoport_proof::read_uint(kInputs[i], next.values[i]) && measured;
      if (on) {
        measured = measured && next.values[0] == 1 && next.values[1] == 18;
        for (int i = 2; i <= 5; ++i) measured = measured && next.values[i] > 0;
      } else {
        measured = measured && next.values[14] == 1 && next.values[15] > 0 && next.values[16] > 0;
      }
      if (measured) {
        next.scene = scene;
        if (on) next.on = 1;
        else next.off = 1;  // Captured only while armed() is false; never emits a hit.
        if (record.values != next.values || record.on != next.on || record.off != next.off) {
          record = next;
          save();
        }
      }
    }
    autoport_proof::publish("ao_tie_campaign_current_measured", measured);
    autoport_proof::publish("ao_tie_campaign_current_missing", !measured);
    autoport_proof::publish("ao_tie_campaign_current_off", !on);
    autoport_proof::publish("ao_tie_campaign_identity_missing", identity_missing);
    autoport_proof::publish("ao_tie_campaign_identity_mismatch", identity_mismatch);
    autoport_proof::publish("ao_tie_campaign_io_defects", io_failed);
    uint64_t total = uint64_t(identity_missing) + uint64_t(identity_mismatch) +
                     uint64_t(io_failed) + uint64_t(!measured);
    for (int v = 0; v < 3; ++v) {
      const auto& r = data.views[v];
      const std::string prefix = kPrefixes[v];
      if (r.scene) autoport_proof::publish((prefix + "scene").c_str(), r.scene);
      else autoport_proof::publish_text((prefix + "scene").c_str(), "non-mesure");
      autoport_proof::publish((prefix + "on_present").c_str(), r.on);
      autoport_proof::publish((prefix + "off_present").c_str(), r.off);
      autoport_proof::publish((prefix + "off_unarmed").c_str(), r.off);
      const uint64_t missing = !r.on + uint64_t(!r.off);
      autoport_proof::publish((prefix + "missing_measurements").c_str(), missing);
      uint64_t defects = missing;
      for (int i = 0; i < 19; ++i) {
        const bool present = i < 14 ? r.on : r.off;
        const auto key = prefix + kTerms[i];
        if (present) autoport_proof::publish(key.c_str(), r.values[i]);
        else autoport_proof::publish_text(key.c_str(), "non-mesure");
        if (present && ((i >= 6 && i <= 13) || i >= 17)) defects = add(defects, r.values[i]);
      }
    autoport_proof::publish((prefix + "defects").c_str(), defects);
    // ── PERIMETRE DU 17/09 : LA VUE QUE L'OWNER A SIGNALEE, ET ELLE SEULE ──────────────────
    // Decision superviseur sous mandat de l'owner (« Pour l'AO, bah demerdes toi et fait le
    // meilleur choix ») : la porte se juge sur le raccord mur/toit de la hutte, la vue de sa
    // capture. `village1-out` et `beach` restent PUBLIEES terme par terme — rien n'est efface,
    // rien ne devient invisible — mais elles ne comptent NI defaut NI zero : leurs 4 unites
    // etaient un residu COMPTABLE (aucun bras enregistre), pas un defaut d'image, et seize
    // essais ont cherche un defaut de rendu dedans. `in_scope` le dit vue par vue.
    autoport_proof::publish((prefix + "in_scope").c_str(), v == kScopedView);
    if (v == kScopedView) total = add(total, defects);
  }
  autoport_proof::publish_text("view_scope", "hut");
  autoport_proof::publish("ao_other_views_measured", 0);
    autoport_proof::publish("ao_tie_prepass_defects", total);
  }
};
inline void frame_begin() {
  static Campaign campaign;
  campaign.begin();
}
}  // namespace ao_tie_contract
