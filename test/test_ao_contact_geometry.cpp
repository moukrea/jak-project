#include "game/graphics/opengl_renderer/ao_contact_geometry.h"

#include <cstdlib>
#include <iostream>

namespace geometry = ao_contact_geometry;

static void check(bool condition, const char* label) {
  if (!condition) {
    std::cerr << "FAIL " << label << '\n';
    std::exit(1);
  }
  std::cout << "PASS " << label << '\n';
}

struct Fixture {
  tfrag3::TieTree tree;
  tfrag3::StripDraw draw;
  Fixture() {
    tree.packed_vertices.vertices.resize(10);
    tree.packed_vertices.matrices.resize(2);
    // Both instances reuse source vertices 5..7; VBO ranges are instead 0..2 and 3..5.
    tree.packed_vertices.matrix_groups = {{0, 5, 8, false}, {1, 5, 8, false}};
    tree.unpacked.vertices.resize(6);
    tree.proto_names = {"test-wall", "test-roof"};
    tree.use_strips = true;
    draw.runs = {{0, 3}, {3, 3}};
    draw.vis_groups = {{4, 1, 0, 0}, {4, 1, 0, 1}};
    draw.num_triangles = 2;
    // Second instance is welded onto the first in the effective GPU stream.
    tree.unpacked.indices = {0, 1, 2, UINT32_MAX, 0, 1, 2, UINT32_MAX};
  }
};

int main() {
  std::vector<geometry::SourceVertex> sources;
  std::vector<geometry::Index> indices;
  {
    Fixture f;
    check(geometry::provenance(f.tree, sources) && sources.size() == 6 &&
              sources[0].vertex == 5 && sources[0].matrix == 0 && sources[0].group == 0 &&
              sources[3].vertex == 5 && sources[3].matrix == 1 && sources[3].group == 1 &&
              sources[5].vertex == 7, "source_offsets_are_not_VBO_indices");
    check(geometry::indices(f.tree, f.draw, indices) && indices.size() == 8 &&
              indices[4].original == 3 && indices[4].effective == 0 &&
              indices[4].group == 1 && indices[4].prototype == 1 &&
              sources[indices[4].original].matrix == 1 &&
              sources[indices[4].effective].matrix == 0,
          "welded_index_preserves_original_instance_and_prototype");
    check(indices[3].original == UINT32_MAX && indices[3].effective == UINT32_MAX &&
              indices[7].original == UINT32_MAX && indices[7].effective == UINT32_MAX,
          "run_restarts_preserved");
    f.tree.unpacked.indices.insert(f.tree.unpacked.indices.begin(), 999);
    f.draw.unpacked.idx_of_first_idx_in_full_buffer = 1;
    check(geometry::indices(f.tree, f.draw, indices) && indices[4].original == 3 &&
              indices[4].effective == 0, "nonzero_draw_stream_base");
  }
  {
    Fixture f;
    f.draw.runs.clear();
    f.draw.plain_indices = {0, 1, 2, UINT32_MAX, 3, 4, 5, UINT32_MAX};
    check(geometry::indices(f.tree, f.draw, indices) && indices[4].original == 3 &&
              indices[4].effective == 0, "plain_indices_strips_preserve_original");
    f.tree.use_strips = false;
    f.draw.plain_indices = {0, 1, 2, 3, 4, 5};
    f.draw.vis_groups = {{3, 1, 0, 0}, {3, 1, 0, 1}};
    f.tree.unpacked.indices = {0, 1, 2, 0, 1, 2};
    check(geometry::indices(f.tree, f.draw, indices) && indices.size() == 6 &&
              indices[3].original == 3 && indices[3].effective == 0 &&
              indices[3].prototype == 1, "plain_triangle_list");
    f.draw.vis_groups = {{2, 0, 0, 0}, {4, 2, 0, 1}};
    check(!geometry::indices(f.tree, f.draw, indices), "reject_visgroup_cutting_triangle");
  }
  {
    Fixture f;
    f.draw.vis_groups = {{2, 0, 0, 0}, {6, 2, 0, 1}};
    check(!geometry::indices(f.tree, f.draw, indices), "reject_visgroup_cutting_strip");
  }
  {
    Fixture f;
    f.tree.packed_vertices.matrix_groups[0].matrix_idx = 2;
    check(!geometry::provenance(f.tree, sources), "reject_matrix_out_of_range");
    f.tree.packed_vertices.matrix_groups[0].matrix_idx = -2;
    check(!geometry::provenance(f.tree, sources), "reject_matrix_below_minus_one");
    f.tree.packed_vertices.matrix_groups[0].matrix_idx = -1;
    check(geometry::provenance(f.tree, sources) && sources[0].matrix == -1,
          "local_wind_prototype_remains_minus_one");
    f.tree.packed_vertices.matrix_groups[0].end_vert = 11;
    check(!geometry::provenance(f.tree, sources), "reject_source_range_overflow");
    f.tree.packed_vertices.matrix_groups[0].end_vert = 4;
    check(!geometry::provenance(f.tree, sources), "reject_reversed_source_range");
  }
  {
    Fixture f;
    f.tree.unpacked.vertices.resize(5);
    check(!geometry::provenance(f.tree, sources), "reject_provenance_excess_count");
    f.tree.unpacked.vertices.resize(7);
    check(!geometry::provenance(f.tree, sources), "reject_provenance_missing_count");
  }
  {
    Fixture f;
    f.draw.unpacked.idx_of_first_idx_in_full_buffer = 9;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_stream_base_out_of_range");
    f.draw.unpacked.idx_of_first_idx_in_full_buffer = 1;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_short_effective_stream");
    f.draw.unpacked.idx_of_first_idx_in_full_buffer = 0;
    f.draw.runs[1].length = 4;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_run_vertex_range");
  }
  {
    Fixture f;
    f.tree.unpacked.indices[3] = 0;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_missing_effective_restart");
    f.tree.unpacked.indices[3] = UINT32_MAX;
    f.tree.unpacked.indices[0] = UINT32_MAX;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_spurious_effective_restart");
    f.tree.unpacked.indices[0] = 6;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_effective_vertex_out_of_range");
    f.tree.unpacked.indices[0] = 0;
    f.draw.runs.clear();
    f.draw.plain_indices = {6, 1, 2, UINT32_MAX, 3, 4, 5, UINT32_MAX};
    check(!geometry::indices(f.tree, f.draw, indices), "reject_original_vertex_out_of_range");
  }
  {
    Fixture f;
    f.draw.vis_groups[0].num_inds = 9;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_visgroup_excess_count");
    f.draw.vis_groups[0].num_inds = 3;
    check(!geometry::indices(f.tree, f.draw, indices), "reject_visgroup_missing_count");
    f.draw.vis_groups[0].num_inds = 4;
    f.tree.proto_names.clear();
    check(!geometry::indices(f.tree, f.draw, indices), "reject_absent_prototypes");
    f.tree.proto_names = {"test-wall"};
    check(!geometry::indices(f.tree, f.draw, indices), "reject_prototype_out_of_range");
  }
  {
    tfrag3::TieTree tree;
    tfrag3::StripDraw draw;
    sources.push_back({0, 0, 0});
    indices.push_back({0, 0, 0, 0});
    check(geometry::provenance(tree, sources) && sources.empty(), "empty_provenance_has_no_sources");
    check(geometry::indices(tree, draw, indices) && indices.empty(), "empty_draw_has_no_indices");
  }
  std::cout << "PASS ao_contact_geometry all cases\n";
}
