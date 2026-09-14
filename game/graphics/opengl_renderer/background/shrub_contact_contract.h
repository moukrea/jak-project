#pragma once

#include "shrub_contact_measurement.h"

// The delivered arm reads both machine-produced comparison archives. A reference-only
// run, a partial window, or absent terms cannot publish the contract total.
namespace shrub_contact_measurement {
inline void publish_contract() {
  if (!autoport_proof::feature_is("shrub-trunk-contact") || !autoport_proof::armed()) return;
  const char* required[] = {
      "shrub_archive_complete", "shrub_archive_reference_enabled",
      "shrub_archive_off_reference_enabled", "shrub_archive_expected_frames",
      "shrub_archive_closed_frames", "shrub_archive_off_pairs",
      "shrub_archive_shrub_pairs", "shrub_archive_tie_pairs", "shrub_archive_grass_pairs",
      "shrub_archive_population_errors", "shrub_archive_input_differences",
      "shrub_archive_pre_differences", "shrub_archive_post_differences",
      "shrub_archive_off_missing", "shrub_archive_off_input_differences",
      "shrub_archive_off_pre_differences", "shrub_archive_off_post_differences",
      "shrub_contact_gpu_errors", "shrub_input_tape_errors", "shrub_input_tape_events",
      "shrub_grass_capture_errors", "shrub_grass_sampled_contact_vertices",
      "shrub_trunk_classes_count", "shrub_trunk_protos_count"};
  std::map<std::string, u64> values;
  u64 pending = 0;
  for (const char* key : required) {
    u64 value = 0;
    if (!autoport_proof::read_uint(key, value)) ++pending;
    else values[key] = value;
  }
  autoport_proof::publish("shrub_contract_pending_terms", pending);
  if (pending || values["shrub_archive_complete"] != 1 ||
      values["shrub_archive_reference_enabled"] != 1 ||
      values["shrub_archive_off_reference_enabled"] != 1) return;

  u64 motion = 0, populations = levels.empty(), geometry = missing_snapshots;
  for (const auto& [name, s] : levels) {
    motion += (s.trunk_max != 0) + (s.joint_max != 0);
    populations += (s.trunk_samples == 0) + (s.foliage_samples == 0) +
        (s.joint_samples == 0) + (s.foliage_max == 0) +
        (s.carried_foliage_samples == 0) + (s.carried_foliage_max == 0);
    geometry += s.prior_generation_defects + s.missing_endpoints + s.invalid_samples +
        s.inconsistent_samples;
    if (s.geometry) geometry += s.geometry->mapping_errors + s.geometry->nonfinite_positions +
        s.geometry->unclassified_contact_vertices;
    else ++geometry;
  }
  populations += !values["shrub_archive_shrub_pairs"] + !values["shrub_archive_tie_pairs"] +
      !values["shrub_archive_grass_pairs"] + !values["shrub_grass_sampled_contact_vertices"] +
      !values["shrub_trunk_classes_count"] + !values["shrub_trunk_protos_count"];
  const u64 expected = values["shrub_archive_expected_frames"];
  const u64 coverage = !expected + (values["shrub_archive_closed_frames"] != expected) +
      (values["shrub_archive_off_pairs"] != expected) + values["shrub_archive_population_errors"];
  const u64 wind_grass = values["shrub_archive_input_differences"] +
      values["shrub_archive_pre_differences"] + values["shrub_archive_post_differences"];
  const u64 off = values["shrub_archive_off_missing"] + values["shrub_archive_off_input_differences"] +
      values["shrub_archive_off_pre_differences"] + values["shrub_archive_off_post_differences"];
  const u64 instrument = values["shrub_contact_gpu_errors"] + values["shrub_input_tape_errors"] +
      values["shrub_grass_capture_errors"] + !values["shrub_input_tape_events"];
  autoport_proof::publish("shrub_contract_motion_defects", motion);
  autoport_proof::publish("shrub_contract_population_defects", populations);
  autoport_proof::publish("shrub_contract_geometry_defects", geometry);
  autoport_proof::publish("shrub_contract_coverage_defects", coverage);
  autoport_proof::publish("shrub_contract_wind_grass_defects", wind_grass);
  autoport_proof::publish("shrub_contract_off_defects", off);
  autoport_proof::publish("shrub_contract_instrument_defects", instrument);
  autoport_proof::publish("shrub_trunk_squash_defects",
      motion + populations + geometry + coverage + wind_grass + off + instrument);
}
}  // namespace shrub_contact_measurement
