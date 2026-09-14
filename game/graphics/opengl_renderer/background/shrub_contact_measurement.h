#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <tuple>
#include <vector>

#include "foliage_wind.h"
#include "shrub_contact_probe.h"
#include "game/system/autoport_proof.h"

// Samples come from a replay of the actual color draw under rasterizer discard. This module
// measures contact only (post minus pre); it does not certify wind or an OFF/reference match.
namespace shrub_contact_measurement {
using Identity = std::tuple<int, size_t, size_t>;
struct Delta {
  std::array<double, 3> value{};
  bool seen = false;
};
struct LevelSamples {
  std::shared_ptr<const foliage_wind::ContactGeometrySnapshot> geometry;
  std::map<Identity, size_t> identities;
  std::map<std::pair<int, size_t>, size_t> tree_sizes;
  std::vector<Delta> deltas;
  std::set<int> captured_geometries;
  u64 frame = 0;
  bool started = false;
  u64 trunk_samples = 0, foliage_samples = 0, joint_samples = 0;
  u64 missing_endpoints = 0, invalid_samples = 0, inconsistent_samples = 0;
  u64 completed_frames = 0;
  u64 prior_generation_defects = 0;
  double trunk_max = 0, foliage_max = 0, joint_max = 0;
};
inline std::map<std::string, LevelSamples> levels;
inline u64 missing_snapshots = 0;

inline double magnitude(const std::array<double, 3>& v) {
  return std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}
inline void publish(const std::string& name, const LevelSamples& state) {
  // Escape each non-alphanumeric byte, preserving distinct level names.
  std::string key = "shrub_contact_gpu_";
  static const char hex[] = "0123456789abcdef";
  for (unsigned char c : name) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) key += c;
    else { key += '_'; key += hex[c >> 4]; key += hex[c & 15]; }
  }
  key += '_';
  const auto number = [&](const char* suffix, u64 value) {
    autoport_proof::publish((key + suffix).c_str(), value);
  };
  const auto real = [&](const char* suffix, double value) {
    autoport_proof::publish_text((key + suffix).c_str(), std::to_string(value).c_str());
  };
  number("completed_frames", state.completed_frames);
  number("prior_generation_defects", state.prior_generation_defects);
  number("trunk_vertex_samples", state.trunk_samples);
  number("foliage_vertex_samples", state.foliage_samples);
  number("exact_pair_samples", state.joint_samples);
  number("missing_pair_endpoints", state.missing_endpoints);
  number("invalid_samples", state.invalid_samples);
  number("inconsistent_samples", state.inconsistent_samples);
  // Positions are GOAL world units (4096/m). Zero is tested exactly in captured float values;
  // the maxima are published independently, without a tolerance hiding a small displacement.
  real("trunk_max_units", state.trunk_max);
  real("foliage_max_units", state.foliage_max);
  real("joint_delta_max_units", state.joint_max);
  number("trunk_motion_defect", state.trunk_max != 0);
  number("junction_motion_defect", state.joint_max != 0);
  number("empty_trunk_defect", state.trunk_samples == 0);
  number("empty_foliage_defect", state.foliage_samples == 0);
  number("empty_junction_defect", state.joint_samples == 0);
  number("immobile_foliage_defect", state.foliage_max == 0);
  number("geometry_errors", state.geometry->mapping_errors + state.geometry->nonfinite_positions +
      state.geometry->unclassified_contact_vertices);
  autoport_proof::publish("shrub_contact_gpu_missing_snapshots", missing_snapshots);
  // Deliberately no shrub_trunk_squash_defects: it additionally requires the independent
  // reference/OFF comparison and the existing wind/grass acquis, not these motion terms alone.
}
inline void complete_frame(const std::string& name, LevelSamples& state) {
  for (const auto& pair : state.geometry->exact_pairs) {
    if (pair[0] >= state.deltas.size() || pair[1] >= state.deltas.size()) {
      ++state.invalid_samples;
      continue;
    }
    // TIE LODs are alternatives; a drawn SHRUB does not imply every TIE LOD was drawn.
    const int trunk_geo = state.geometry->vertices[pair[0]].geo;
    const int leaf_geo = state.geometry->vertices[pair[1]].geo;
    if (!state.captured_geometries.empty() &&
        ((trunk_geo >= 0 && !state.captured_geometries.count(trunk_geo)) ||
         (leaf_geo >= 0 && !state.captured_geometries.count(leaf_geo)))) continue;
    const auto& trunk = state.deltas[pair[0]];
    const auto& leaf = state.deltas[pair[1]];
    if (!trunk.seen && !leaf.seen) continue;  // Neither endpoint was drawn in this frame.
    if (!trunk.seen || !leaf.seen) { ++state.missing_endpoints; continue; }
    std::array<double, 3> difference;
    for (size_t axis = 0; axis < 3; ++axis) difference[axis] = leaf.value[axis] - trunk.value[axis];
    state.joint_max = std::max(state.joint_max, magnitude(difference));
    ++state.joint_samples;
  }
  ++state.completed_frames;
  publish(name, state);
  std::fill(state.deltas.begin(), state.deltas.end(), Delta{});
  state.captured_geometries.clear();
  state.started = false;
}
inline void consume(const std::string& name, int geo, size_t tree, u64 frame,
                    const shrub_contact_probe::Sample* samples, size_t count) {
  auto snapshot = foliage_wind::contact_geometry_snapshot(name);
  if (!snapshot) {
    autoport_proof::publish("shrub_contact_gpu_missing_snapshots", ++missing_snapshots);
    return;
  }
  auto& state = levels[name];
  if (state.geometry != snapshot) {
    if (state.started) complete_frame(name, state);
    const u64 previous_defects = state.prior_generation_defects +
        (state.geometry ? (state.geometry->mapping_errors + state.geometry->nonfinite_positions +
          state.geometry->unclassified_contact_vertices + state.invalid_samples +
          state.inconsistent_samples + state.missing_endpoints + (state.trunk_max != 0) +
          (state.joint_max != 0) + (state.trunk_samples == 0) + (state.foliage_max == 0) +
          (state.joint_samples == 0)) : 0);
    state = LevelSamples{};
    state.prior_generation_defects = previous_defects;
    state.geometry = std::move(snapshot);
    state.identities.clear();
    state.tree_sizes.clear();
    for (const auto& tree : state.geometry->trees)
      state.tree_sizes[{tree.geo, tree.tree_index}] = tree.vertex_count;
    state.deltas.assign(state.geometry->vertices.size(), Delta{});
    state.started = false;
    for (size_t i = 0; i < state.geometry->vertices.size(); ++i) {
      const auto& v = state.geometry->vertices[i];
      if (!state.identities.emplace(Identity{v.geo, v.tree_index, v.vertex_index}, i).second)
        ++state.invalid_samples;
    }
  }
  if (state.started && frame != state.frame) complete_frame(name, state);
  state.frame = frame;
  state.started = true;
  if (geo >= 0) state.captured_geometries.insert(geo);
  const auto tree_size = state.tree_sizes.find({geo, tree});
  if (tree_size == state.tree_sizes.end()) {
    ++state.invalid_samples;
    return;
  }
  for (size_t i = 0; i < count; ++i) {
    if (samples[i].vertex_index >= tree_size->second) { ++state.invalid_samples; continue; }
    const auto found = state.identities.find(Identity{geo, tree, samples[i].vertex_index});
    if (found == state.identities.end()) continue;  // Non-contact geometry in the same draw.
    const size_t index = found->second;
    std::array<double, 3> delta;
    bool finite = true;
    for (size_t axis = 0; axis < 3; ++axis) {
      finite &= std::isfinite(samples[i].pre[axis]) && std::isfinite(samples[i].post[axis]);
      delta[axis] = double(samples[i].post[axis]) - double(samples[i].pre[axis]);
    }
    if (!finite) { ++state.invalid_samples; continue; }
    auto& previous = state.deltas[index];
    if (previous.seen) {
      // Repeated triangles/passes are not new vertices. A changed delta in the same frame
      // signals differing uniforms/passes; never silently choose the convenient value.
      if (previous.value != delta) ++state.inconsistent_samples;
      continue;
    }
    previous = {delta, true};
    const double movement = magnitude(delta);
    if (state.geometry->vertices[index].load_bearing) {
      ++state.trunk_samples;
      state.trunk_max = std::max(state.trunk_max, movement);
    } else {
      ++state.foliage_samples;
      state.foliage_max = std::max(state.foliage_max, movement);
    }
  }
}
inline bool active(u64 frame) {
  if (!autoport_proof::feature_is("shrub-trunk-contact")) return false;
  for (auto& entry : levels) {
    if (entry.second.started && entry.second.frame != frame) complete_frame(entry.first, entry.second);
  }
  shrub_contact_probe::set_sample_callback(consume);
  return true;
}
inline void draw_elements(const std::string& level, int geo, size_t tree, u64 frame,
                          GLenum mode, GLsizei count, GLenum type, const void* offset) {
  if (active(frame)) shrub_contact_probe::draw_elements(level, geo, tree, frame, mode, count, type, offset);
}
inline void multi_draw_elements(const std::string& level, int geo, size_t tree, u64 frame,
                                GLenum mode, const GLsizei* counts, GLenum type,
                                const void* const* offsets, GLsizei drawcount) {
  if (active(frame)) shrub_contact_probe::multi_draw_elements(level, geo, tree, frame, mode, counts,
                                                        type, offsets, drawcount);
}
}  // namespace shrub_contact_measurement
