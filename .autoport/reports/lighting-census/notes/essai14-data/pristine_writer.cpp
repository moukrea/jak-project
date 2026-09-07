#include <fstream>
#include <iostream>
#include "common/custom_data/Tfrag3Data.h"
int main(int argc,char**argv) {
  if(argc!=2) return 2;
  tfrag3::Level l{}; l.level_name="legacy43-independent-sentinels";
  for(int i=0;i<2;i++) {
    tfrag3::TfragTree t{}; t.kind=tfrag3::TFragmentTreeKind::NORMAL;
    t.use_strips=(i==0); t.bvh.first_leaf_node=101+i; t.bvh.last_leaf_node=111+i;
    t.colors.color_count=4; t.colors.data.assign(128,31+i);
    t.packed_vertices.vertices.push_back({11,22,33,0,44,55,1});
    t.packed_vertices.cluster_origins.emplace_back(66,77,88);
    l.tfrag_trees[0].push_back(t);
    tfrag3::TieTree z{}; z.use_strips=(i==1); z.bvh.first_leaf_node=201+i;
    z.colors.color_count=4; z.colors.data.assign(128,61+i);
    z.packed_vertices.color_indices={1,2,3};
    tfrag3::PackedTieVertices::Vertex v{}; v.x=123.5f+i; v.y=234.5f; v.z=345.5f;
    v.s=0.25f; v.t=0.75f; v.r=101; v.g=102; v.b=103; v.a=104;
    z.packed_vertices.vertices.push_back(v);
    z.has_per_proto_visibility_toggle=true; z.proto_names={"sentinel-proto-"+std::to_string(i)};
    l.tie_trees[0].push_back(z);
  }
  Serializer save; l.serialize(save); auto raw=save.get_save_result();
  std::ofstream out(argv[1],std::ios::binary); out.write((const char*)raw.first,raw.second); out.close();
  Serializer read(raw.first,raw.second); tfrag3::Level check{}; check.serialize(read);
  std::cout<<"writer_version="<<tfrag3::TFRAG3_VERSION<<" bytes="<<raw.second<<" load_finished="<<read.get_load_finished()<<" tfrag="<<check.tfrag_trees[0].size()<<" tie="<<check.tie_trees[0].size()<<" tfrag_leaf="<<check.tfrag_trees[0][1].bvh.first_leaf_node<<" tie_leaf="<<check.tie_trees[0][1].bvh.first_leaf_node<<" tie_x="<<check.tie_trees[0][1].packed_vertices.vertices[0].x<<" proto="<<check.tie_trees[0][1].proto_names[0]<<std::endl;
  return read.get_load_finished() && out.good() ? 0:1;
}
