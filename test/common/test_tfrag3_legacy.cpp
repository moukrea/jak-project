// Standalone compatibility test; link against the existing common library.
// Usage: test_tfrag3_legacy --raw pristine-fixture.raw [pristine-level.fr3 ...]
// The raw fixture must be emitted by an independently compiled pristine writer.
#include <cstdio>
#include <csignal>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/compress.h"

namespace {
void require(bool condition, const char* reason) {
  if (!condition) {
    throw std::runtime_error(reason);
  }
}

void load(tfrag3::Level& level, const std::vector<u8>& bytes) {
  Serializer reader(Serializer::Borrowed{}, bytes.data(), bytes.size());
  level.serialize(reader);
  require(reader.get_load_finished(), "unconsumed input bytes");
}

std::vector<u8> save(tfrag3::Level& level) {
  Serializer writer;
  level.serialize(writer);
  const auto [data, size] = writer.get_save_result();
  return {data, data + size};
}

void reject_version(std::vector<u8> bytes, size_t offset, u16 version) {
  std::memcpy(bytes.data() + offset, &version, sizeof(version));
  std::fflush(nullptr);
  const pid_t pid = fork();
  require(pid >= 0, "fork failed");
  if (pid == 0) {
    const rlimit no_core = {0, 0};
    setrlimit(RLIMIT_CORE, &no_core);
    tfrag3::Level level;
    load(level, bytes);
    _exit(0);
  }
  int status = 0;
  require(waitpid(pid, &status, 0) == pid, "waitpid failed");
  require(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT,
          "invalid version was not rejected by assertion");
  std::printf("fr3-compat rejected offset=%zu version=%u signal=%d\n", offset, version,
              WTERMSIG(status));
}

void check(const char* path, bool raw) {
  auto bytes = file_util::read_binary_file(std::string(path));
  if (!raw) {
    bytes = compression::decompress_zstd(bytes.data(), bytes.size());
  }
  tfrag3::Level level;
  load(level, bytes);
  require(level.version == 43 && level.version2 == 43, "fixture must be pristine v43");
  size_t tfrag_count = 0, tie_count = 0;
  for (auto& group : level.tfrag_trees) {
    for (auto& tree : group) {
      ++tfrag_count;
      require(tree.baked_tangents.empty(), "v43 tfrag has tangents");
      tree.baked_tangents = {123, 456};
    }
  }
  for (auto& group : level.tie_trees) {
    for (auto& tree : group) {
      ++tie_count;
      require(tree.baked_tangents.empty(), "v43 tie has tangents");
      tree.baked_tangents = {789};
    }
  }
  load(level, bytes);  // reuse live objects: legacy input must clear stale v44 fields
  for (const auto& group : level.tfrag_trees) {
    for (const auto& tree : group) {
      require(tree.baked_tangents.empty(), "reused v43 tfrag kept tangents");
    }
  }
  for (const auto& group : level.tie_trees) {
    for (const auto& tree : group) {
      require(tree.baked_tangents.empty(), "reused v43 tie kept tangents");
    }
  }
  const std::string name = level.level_name;
  auto current = save(level);
  u16 header = 0, footer = 0;
  std::memcpy(&header, current.data(), sizeof(header));
  std::memcpy(&footer, current.data() + current.size() - sizeof(footer), sizeof(footer));
  require(header == 44 && footer == 44, "save did not promote both versions to v44");
  tfrag3::Level reread;
  load(reread, current);
  require(reread.level_name == name, "level name changed");
  require(save(reread) == current, "v44 roundtrip changed serialized fields/vectors");

  if (raw) {
    require(tfrag_count > 0 && tie_count > 0, "fixture must exercise both tree layouts");
    require(reread.level_name == "legacy43-independent-sentinels" &&
                reread.tfrag_trees[0].size() == 2 && reread.tie_trees[0].size() == 2,
            "independent fixture identity mismatch");
    for (int i = 0; i < 2; ++i) {
      const auto& t = reread.tfrag_trees[0][i];
      const auto& z = reread.tie_trees[0][i];
      require(t.kind == tfrag3::TFragmentTreeKind::NORMAL && t.use_strips == (i == 0) &&
                  t.bvh.first_leaf_node == 101 + i && t.bvh.last_leaf_node == 111 + i &&
                  t.colors.color_count == 4 && t.colors.data == std::vector<u8>(128, 31 + i) &&
                  t.packed_vertices.vertices.size() == 1 &&
                  t.packed_vertices.vertices[0].xoff == 11 &&
                  t.packed_vertices.vertices[0].t == 55 &&
                  t.packed_vertices.cluster_origins.size() == 1 &&
                  t.packed_vertices.cluster_origins[0].z() == 88,
              "pristine tfrag sentinels changed");
      require(z.use_strips == (i == 1) && z.bvh.first_leaf_node == 201 + i &&
                  z.colors.color_count == 4 && z.colors.data == std::vector<u8>(128, 61 + i) &&
                  z.packed_vertices.color_indices == std::vector<u16>({1, 2, 3}) &&
                  z.packed_vertices.vertices.size() == 1 &&
                  z.packed_vertices.vertices[0].x == 123.5f + i &&
                  z.packed_vertices.vertices[0].a == 104 && z.has_per_proto_visibility_toggle &&
                  z.proto_names == std::vector<std::string>({"sentinel-proto-" + std::to_string(i)}),
              "pristine tie sentinels changed");
    }
    for (auto& group : reread.tfrag_trees) {
      for (auto& tree : group) {
        tree.baked_tangents = {0x1234, 0xabcd};
      }
    }
    for (auto& group : reread.tie_trees) {
      for (auto& tree : group) {
        tree.baked_tangents = {0x5678};
      }
    }
    auto baked = save(reread);
    tfrag3::Level baked_reread;
    load(baked_reread, baked);
    require(save(baked_reread) == baked, "v44 lost populated tangent vectors");
    reject_version(bytes, 0, 42);
    reject_version(bytes, 0, 45);
    reject_version(bytes, bytes.size() - sizeof(u16), 44);
    reject_version(current, current.size() - sizeof(u16), 43);
  }
  std::printf("fr3-compat file=%s name=%s v43_bytes=%zu v44_bytes=%zu tfrag=%zu tie=%zu "
              "reused_clear=1 roundtrip_exact=1\n", path, name.c_str(), bytes.size(), current.size(),
              tfrag_count, tie_count);
}
}  // namespace

int main(int argc, char** argv) {
  try {
    require(argc >= 3 && std::string(argv[1]) == "--raw", "usage: --raw fixture [fr3 ...]");
    check(argv[2], true);
    for (int i = 3; i < argc; ++i) {
      check(argv[i], false);
    }
    std::printf("fr3-compat PASS inputs=%d\n", argc - 2);
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "fr3-compat FAIL %s\n", error.what());
    return 1;
  }
}
