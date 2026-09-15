#include "soft_baseline_report.h"

#include <array>
#include <cmath>
#include <set>
#include <stdexcept>
#include <string>

#include "data/soft-baseline/baseline_json.h"
#ifdef __ANDROID__
#include "data/soft-baseline/x86_tiles_json.h"
#endif
#include "soft_baseline.h"

#include "game/system/autoport_proof.h"

#include "third-party/json.hpp"

namespace soft_baseline {
namespace {
AUTOPORT_FEATURE_SITE("soft-baseline");
constexpr const char* kItem = "soft-baseline";
using Json = nlohmann::json;

uint64_t publish_number(const std::string& key, const Json& value) {
  if (!value.is_number() || !std::isfinite(value.get<double>()))
    throw std::runtime_error("missing or nonfinite baseline measurement: " + key);
  autoport_proof::publish_text(key.c_str(), value.dump().c_str());
  return 1;
}

struct Offline {
  uint64_t census = 1, density = 1, drifts = 1, reference = 1, malformed = 0;
};

Offline publish_offline() {
  Offline out;
  uint64_t quantities = 0;
  try {
    const auto data = Json::parse(soft_baseline_data::json_text);
    autoport_proof::publish_text("soft_baseline_data_sha256", soft_baseline_data::sha256);
    const auto& summary = data.at("summary");
    out.census = summary.at("census_level_gaps").get<uint64_t>();
    out.reference = summary.at("census_reference_gaps").get<uint64_t>();
    out.density = summary.at("density_gaps").get<uint64_t>();
    out.drifts = summary.at("drift_gaps").get<uint64_t>();
    for (auto it = summary.begin(); it != summary.end(); ++it)
      quantities += publish_number("soft_baseline_" + it.key(), it.value());
    const auto& levels = data.at("levels");
    if (levels.size() != summary.at("census_levels").get<size_t>())
      ++out.malformed;
    size_t density_levels = 0, islands = 0;
    uint64_t drift_missing = 0, references_bad = 0;
    std::set<std::string> level_names, density_names;
    for (const auto& level : levels) {
      if (!level_names.insert(level.at("level").get<std::string>()).second)
        ++out.malformed;
    }
    out.census = level_names.size() == 25 ? 0 : 1;
    if (data.at("units_per_metre") != 4096 || data.at("schema_version") != 1)
      ++out.malformed;
    for (const auto& level : levels) {
      const std::string prefix = "soft_baseline_" + level.at("level").get<std::string>();
      autoport_proof::publish_text((prefix + "_source_sha256").c_str(),
                                   level.at("source_sha256").get<std::string>().c_str());
      const auto& census = level.at("census");
      if (census.size() != 64)
        ++out.malformed;
      std::set<int> materials;
      for (const auto& material : census) {
        const int m = material.at("pat_material").get<int>();
        if (m < 0 || m >= 64 || !materials.insert(m).second)
          ++out.malformed;
        for (const char* field : {"triangles", "area_u2", "area_m2"})
          if (!material.at(field).is_number() || !std::isfinite(material.at(field).get<double>()) ||
              material.at(field).get<double>() < 0)
            ++out.malformed;
        const auto name = level.at("level").get<std::string>();
        if ((name == "snow" && (m == 9 || m == 10)) || (name == "beach" && m == 5)) {
          const uint64_t expected_tri = name == "beach" ? 10294 : (m == 9 ? 5968 : 762);
          const long long expected_area = name == "beach" ? 90299 : (m == 9 ? 72181 : 2332);
          if (material.at("triangles").get<uint64_t>() != expected_tri ||
              std::llround(material.at("area_m2").get<double>()) != expected_area)
            ++references_bad;
        }
      }
      // The full 25 x 64 table is in the versioned JSON. Publish the soft materials
      // in the runtime log too, in both unit systems.
      for (const auto& material : census) {
        const auto m = material.at("pat_material").get<int>();
        if (m != 5 && m != 9 && m != 10)
          continue;
        for (const char* field : {"triangles", "area_u2", "area_m2"})
          quantities +=
              publish_number(prefix + "_mat" + std::to_string(m) + "_" + field, material.at(field));
      }
      if (level.contains("density")) {
        ++density_levels;
        density_names.insert(level.at("level").get<std::string>());
        const auto& density = level.at("density");
        for (const char* field :
             {"eligible_triangles", "texture_slope_candidates", "no_support_within_0_5m"})
          quantities += publish_number(prefix + "_" + field, density.at(field));
        if (density.at("eligible_triangles").get<uint64_t>() == 0)
          ++out.malformed;
        if (!density.at("edge").is_object())
          ++out.malformed;
        else
          for (const char* field : {"mean_u", "median_u", "mean_m", "median_m"})
            quantities += publish_number(prefix + "_edge_" + field, density.at("edge").at(field));
      }
      if (level.contains("drifts")) {
        const auto name = level.at("level").get<std::string>();
        const size_t expected = name == "snow" ? 19 : (name == "ogre" ? 18 : 0);
        if (level.at("drifts").size() != expected)
          ++out.malformed;
        std::set<int> island_ids;
        for (const auto& drift : level.at("drifts")) {
          ++islands;
          if (!island_ids.insert(drift.at("island").get<int>()).second)
            ++out.malformed;
          if (!drift.at("attributed").get<bool>())
            ++drift_missing;
          const std::string island =
              prefix + "_island" + std::to_string(drift.at("island").get<int>());
          autoport_proof::publish((island + "_attributed").c_str(),
                                  drift.at("attributed").get<bool>());
          if (!drift.at("attributed").get<bool>())
            continue;
          const auto& candidate = drift.at("candidates").at(0);
          if (drift.contains("absent_surface_samples"))
            quantities += publish_number(island + "_absent_surface_samples",
                                         drift.at("absent_surface_samples"));
          autoport_proof::publish_text((island + "_prototype").c_str(),
                                       candidate.at("prototype").get<std::string>().c_str());
          for (const char* field : {"min_u", "median_u", "max_u", "min_m", "median_m", "max_m"})
            quantities +=
                publish_number(island + "_gap_" + field, candidate.at("vertical_gap").at(field));
        }
      }
    }
    out.reference = references_bad + (!level_names.count("snow")) + (!level_names.count("beach"));
    out.density =
        density_names == std::set<std::string>{"snow", "beach", "training", "village1"} ? 0 : 1;
    out.drifts = drift_missing + (islands == 37 ? 0 : 1);
    if (out.census != summary.at("census_level_gaps").get<uint64_t>() ||
        out.reference != summary.at("census_reference_gaps").get<uint64_t>() ||
        out.density != summary.at("density_gaps").get<uint64_t>() ||
        out.drifts != summary.at("drift_gaps").get<uint64_t>())
      ++out.malformed;
    if (density_levels != summary.at("density_levels").get<size_t>() ||
        islands != summary.at("drift_islands").get<size_t>())
      ++out.malformed;
  } catch (const std::exception& e) {
    ++out.malformed;
    autoport_proof::publish_text("soft_baseline_data_error", e.what());
  }
  autoport_proof::note_hit_for(kItem, quantities);
  return out;
}

uint64_t publish_desktop_reference() {
#ifdef __ANDROID__
  try {
    const auto data = Json::parse(soft_baseline_x86::json_text);
    if (data.at("source") != "x86" || data.at("crash") != 0 || data.at("format") != "R16_UNORM" ||
        data.at("tiles").size() != 2)
      return 1;
    uint64_t quantities = 0;
    std::set<int> sides;
    for (const auto& tile : data.at("tiles")) {
      const int side = tile.at("side").get<int>();
      if ((side != 64 && side != 128) || !sides.insert(side).second ||
          tile.at("iterations").get<int>() <= 0)
        return 1;
      for (const char* field : {"upload_completion_ms", "raster_completion_ms"}) {
        if (!(tile.at(field).get<double>() > 0))
          return 1;
        quantities +=
            publish_number("soft_tile_x86_" + std::to_string(side) + "_" + field, tile.at(field));
      }
    }
    autoport_proof::publish_text("soft_tile_x86_binary_sha256",
                                 data.at("binary_sha256").get<std::string>().c_str());
    autoport_proof::publish_text("soft_tile_x86_renderer",
                                 data.at("renderer").get<std::string>().c_str());
    autoport_proof::publish_text("soft_tile_x86_run_sha256",
                                 data.at("run_sha256").get<std::string>().c_str());
    autoport_proof::note_hit_for(kItem, quantities);
    return quantities == 4 ? 0 : 1;
  } catch (const std::exception&) {
    return 1;
  }
#else
  // This run is the first target's measurement. The USB run consumes it and
  // completes the pair; this desktop run alone cannot establish both targets.
  return 1;
#endif
}
}  // namespace

void baseline_frame_end() {
  if (!autoport_proof::feature_is(kItem) || !autoport_proof::armed_for(kItem))
    return;
  static const Offline offline = publish_offline();
  static const uint64_t pair_gap = publish_desktop_reference();
  const auto& tiles = measure_tiles_once();
  static bool counted_tiles = false;
  if (!counted_tiles && tiles.attempted) {
    uint64_t quantities = 0;
    for (const auto& tile : tiles.tiles)
      if (tile.measured)
        quantities += 2;
    autoport_proof::note_hit_for(kItem, quantities);
    counted_tiles = true;
  }
  uint64_t draw_gaps = 1;
  autoport_proof::read_uint("soft_draw_gaps", draw_gaps);
  autoport_proof::publish("soft_baseline_census_gaps", offline.census + offline.reference);
  autoport_proof::publish("soft_baseline_density_gaps", offline.density);
  autoport_proof::publish("soft_baseline_drift_gaps", offline.drifts);
  autoport_proof::publish("soft_baseline_data_gaps", offline.malformed);
  autoport_proof::publish("soft_baseline_draw_gaps", draw_gaps);
  autoport_proof::publish("soft_baseline_tile_gaps", tiles.gaps);
  autoport_proof::publish("soft_baseline_target_pair_gaps", pair_gap);
  autoport_proof::publish("soft_baseline_gaps",
                          offline.census + offline.reference + offline.density + offline.drifts +
                              offline.malformed + draw_gaps + tiles.gaps + pair_gap);
}
}  // namespace soft_baseline
