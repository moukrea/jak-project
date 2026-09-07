#include <fstream>
#include <iostream>
#include <iterator>
#include "common/custom_data/Tfrag3Data.h"
#include "common/util/compress.h"
int main(int argc,char**argv) {
  if(argc!=2) return 2;
  std::ifstream in(argv[1],std::ios::binary);
  std::vector<u8> compressed((std::istreambuf_iterator<char>(in)),{});
  auto raw=compression::decompress_zstd(compressed.data(),compressed.size());
  Serializer read(raw.data(),raw.size()); tfrag3::Level l{}; l.serialize(read);
  size_t tfrag=0,tie=0,verts=0;
  for(auto& geo:l.tfrag_trees) for(auto& tree:geo) {++tfrag; verts+=tree.packed_vertices.vertices.size();}
  for(auto& geo:l.tie_trees) for(auto& tree:geo) {++tie; verts+=tree.packed_vertices.vertices.size();}
  std::cout<<"file="<<argv[1]<<" version="<<l.version<<" version2="<<l.version2<<" bytes="<<raw.size()<<" load_finished="<<read.get_load_finished()<<" tfrag="<<tfrag<<" tie="<<tie<<" vertices="<<verts<<" textures="<<l.textures.size()<<std::endl;
  return read.get_load_finished()?0:1;
}
