#include <cassert>
#include <iostream>
#include "game/graphics/opengl_renderer/background/shrub_contact_measurement.h"
std::map<std::string, u64> metrics;
std::shared_ptr<foliage_wind::ContactGeometrySnapshot> fixture;
namespace autoport_proof {
void publish(const char* k, uint64_t v) { metrics[k] = v; }
void publish_text(const char*, const char*) {}
}
namespace foliage_wind {
std::shared_ptr<const ContactGeometrySnapshot> contact_geometry_snapshot(const std::string&) {
  return fixture;
}
}
using namespace shrub_contact_measurement;
void reset(bool empty = false) {
  levels.clear(); metrics.clear(); missing_snapshots = 0;
  fixture = std::make_shared<foliage_wind::ContactGeometrySnapshot>();
  fixture->level_name = "test";
  fixture->trees = {{0,0,1},{-1,0,2}};
  if (!empty) {
    fixture->vertices = {{{0,0,0},true,0,0,0},
                         {{0,0,0},false,-1,0,0},
                         {{0,1,0},false,-1,0,1}};
    fixture->exact_pairs = {{0,1}};
  }
}
void feed(float trunk, float junction, float tip) {
  shrub_contact_probe::Sample t{{0,0,0},{trunk,0,0},0};
  shrub_contact_probe::Sample f[2] = {{{0,0,0},{junction,0,0},0},
                                     {{0,1,0},{tip,1,0},1}};
  consume("test",0,0,1,&t,1);
  consume("test",-1,0,1,f,2);
  complete_frame("test",levels.at("test"));
}
u64 metric(const char* suffix) { return metrics.at(std::string("shrub_contact_gpu_test_")+suffix); }
int main() {
  reset(); feed(0,0,1);
  assert(metric("trunk_motion_defect")==0 && metric("junction_motion_defect")==0);
  assert(metric("immobile_foliage_defect")==0 && metric("exact_pair_samples")==1);
  std::cout << "case=valid expected=0 observed=" << metric("trunk_motion_defect") << "\n";
  reset(); feed(1,0,1); assert(metric("trunk_motion_defect")==1);
  std::cout << "case=trunk_motion expected=1 observed=" << metric("trunk_motion_defect") << "\n";
  reset(); feed(0,1,1); assert(metric("junction_motion_defect")==1);
  std::cout << "case=junction_motion expected=1 observed=" << metric("junction_motion_defect") << "\n";
  reset(); feed(0,0,0); assert(metric("immobile_foliage_defect")==1);
  std::cout << "case=immobile expected=1 observed=" << metric("immobile_foliage_defect") << "\n";
  reset(true); feed(0,0,0);
  assert(metric("empty_trunk_defect")==1 && metric("empty_foliage_defect")==1 && metric("empty_junction_defect")==1);
  std::cout << "case=empty expected=3 observed=" << metric("empty_trunk_defect")+metric("empty_foliage_defect")+metric("empty_junction_defect") << "\n";
  reset();
  shrub_contact_probe::Sample invalid{{0,0,0},{0,0,0},1};
  consume("test",0,0,1,&invalid,1);
  complete_frame("test",levels.at("test"));
  assert(metric("invalid_samples")==1);
  std::cout << "case=outside_vbo expected=1 observed=" << metric("invalid_samples") << "\n";

  reset();
  shrub_contact_probe::Sample fixed{{0,0,0},{0,0,0},0};
  consume("test",0,0,1,&fixed,1); consume("test",0,0,1,&fixed,1);
  complete_frame("test",levels.at("test"));
  assert(metric("trunk_vertex_samples")==1 && metric("inconsistent_samples")==0);
  std::cout << "case=dedup expected=1 observed=" << metric("trunk_vertex_samples") << "\n";
  reset();
  fixture->trees.push_back({1,0,1});
  fixture->vertices.push_back({{0,0,0},true,1,0,0});
  fixture->exact_pairs.push_back({3,1});
  feed(0,0,1);
  assert(metric("missing_pair_endpoints")==0 && metric("exact_pair_samples")==1);
  std::cout << "case=alternative_lod expected=0 observed=" << metric("missing_pair_endpoints") << "\n";
  reset(); fixture->mapping_errors=2; feed(1,0,1);
  fixture=std::make_shared<foliage_wind::ContactGeometrySnapshot>(*fixture);
  fixture->mapping_errors=0; feed(0,0,1);
  assert(metric("prior_generation_defects")>=3);
  std::cout << "case=prior_generation expected_at_least=3 observed=" << metric("prior_generation_defects") << "\n";
}
