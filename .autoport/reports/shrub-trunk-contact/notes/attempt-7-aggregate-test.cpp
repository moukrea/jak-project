#include <cassert>
#include <iostream>
#include <limits>
#include "game/graphics/opengl_renderer/background/shrub_contact_measurement.h"
std::map<std::string, u64> metrics;
std::map<std::string, double> maxima;
std::shared_ptr<foliage_wind::ContactGeometrySnapshot> fixture;
namespace autoport_proof {
void publish(const char* k, uint64_t v) { metrics[k] = v; }
void publish_text(const char* k, const char* v) { maxima[k] = std::stod(v); }
}
namespace foliage_wind {
std::shared_ptr<const ContactGeometrySnapshot> contact_geometry_snapshot(const std::string&) {
  return fixture;
}
}
using namespace shrub_contact_measurement;
void reset(bool empty = false) {
  levels.clear(); metrics.clear(); maxima.clear(); missing_snapshots = 0;
  fixture = std::make_shared<foliage_wind::ContactGeometrySnapshot>();
  fixture->level_name = "test";
  fixture->trees = {{0,0,1},{-1,0,2}};
  if (!empty) {
    fixture->vertices = {{{0,0,0},true,0,0,0},
                         {{0,0,0},false,-1,0,0,true},
                         {{0,1,0},false,-1,0,1,true}};
    fixture->exact_pairs = {{0,1}};
  }
}
void feed(float trunk, float junction, float tip) {
  shrub_contact_probe::Sample t{{0,0,0},{trunk,0,0},0};
  shrub_contact_probe::Sample f[2] = {{{0,0,0},{junction,0,0},0},
                                     {{0,1,0},{tip,1,0},1}};
  consume("test",0,0,1,&t,1);
  consume("test",-1,0,1,f,2);
  end_frame(1);
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
  end_frame(1);
  assert(metric("invalid_samples")==1);
  std::cout << "case=outside_vbo expected=1 observed=" << metric("invalid_samples") << "\n";

  reset();
  shrub_contact_probe::Sample fixed{{0,0,0},{0,0,0},0};
  consume("test",0,0,1,&fixed,1); consume("test",0,0,1,&fixed,1);
  end_frame(1);
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

  reset();
  fixture->trees[1].vertex_count = 3;
  fixture->vertices.push_back({{2,1,0},false,-1,0,2,false});
  shrub_contact_probe::Sample unrelated{{2,1,0},{5,1,0},2};
  consume("test",-1,0,1,&unrelated,1);
  feed(0,0,0);
  assert(metric("immobile_foliage_defect")==0);
  assert(metric("immobile_carried_foliage_defect")==1);
  assert(metric("carried_foliage_vertex_samples")==2);
  assert(maxima.at("shrub_contact_gpu_test_foliage_max_units")==3);
  assert(maxima.at("shrub_contact_gpu_test_carried_foliage_max_units")==0);
  std::cout << "case=unrelated_mobile_crown_immobile global_max=3 crown_max=0 crown_defect="
            << metric("immobile_carried_foliage_defect") << "\n";
  reset(); feed(0,0,2);
  assert(metric("immobile_carried_foliage_defect")==0);
  assert(metric("empty_carried_foliage_defect")==0);
  assert(maxima.at("shrub_contact_gpu_test_carried_foliage_max_units")==2);
  std::cout << "case=crown_mobile samples=" << metric("carried_foliage_vertex_samples")
            << " max=2 defect=" << metric("immobile_carried_foliage_defect") << "\n";
  reset();
  for (auto& v : fixture->vertices) v.carried = false;
  feed(0,0,2);
  assert(metric("empty_carried_foliage_defect")==1);
  std::cout << "case=empty_crown expected=1 observed=" << metric("empty_carried_foliage_defect") << "\n";
  reset();
  consume("test",0,0,1,&fixed,1);
  assert(metrics.empty());
  end_frame(1);
  assert(metric("completed_frames")==1 && !levels.at("test").started);
  end_frame(1); end_frame(2);
  assert(metric("completed_frames")==1);
  std::cout << "case=last_frame_without_next_draw completed_frames=" << metric("completed_frames") << "\n";
  reset();
  consume("test",0,0,1,&fixed,1);
  shrub_contact_probe::Sample changed{{0,0,0},{1,0,0},0};
  consume("test",0,0,1,&changed,1); end_frame(1);
  assert(metric("inconsistent_samples")==1);
  assert(metric("missing_pair_endpoints")==1);
  std::cout << "case=inconsistent_and_missing inconsistent=" << metric("inconsistent_samples")
            << " missing=" << metric("missing_pair_endpoints") << "\n";
  reset();
  shrub_contact_probe::Sample nonfinite{{0,0,0},{std::numeric_limits<float>::infinity(),0,0},0};
  consume("test",0,0,1,&nonfinite,1); end_frame(1);
  assert(metric("invalid_samples")==1);
  std::cout << "case=nonfinite expected=1 observed=" << metric("invalid_samples") << "\n";
  reset(); fixture->exact_pairs.push_back({0,100}); feed(0,0,1);
  assert(metric("invalid_samples")==1);
  std::cout << "case=invalid_pair expected=1 observed=" << metric("invalid_samples") << "\n";
  reset(); fixture.reset(); consume("test",0,0,1,&fixed,1);
  assert(missing_snapshots==1);
  std::cout << "case=missing_snapshot expected=1 observed=" << missing_snapshots << "\n";
  reset(); feed(0,0,0);
  fixture=std::make_shared<foliage_wind::ContactGeometrySnapshot>(*fixture);
  feed(0,0,2);
  assert(metric("prior_generation_defects")==2);
  std::cout << "case=prior_immobile_crown expected=2 observed=" << metric("prior_generation_defects") << "\n";
}
