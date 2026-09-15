// DIRECTIVES v775512c234
// Offline bridge only. The unchanged native profile owns every measurement rule.
#include <cstdio>
#include <cstring>
#include <vector>
#include "game/graphics/opengl_renderer/ao_contact_profile.h"

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  FILE* f = std::fopen(argv[1], "rb");
  if (!f) return 2;
  char magic[8]{};
  uint32_t w = 0, h = 0;
  float jump = 0;
  bool ok = std::fread(magic, 1, 8, f) == 8 && std::memcmp(magic, "AOHPRO01", 8) == 0 &&
      std::fread(&w, 4, 1, f) == 1 && std::fread(&h, 4, 1, f) == 1 &&
      std::fread(&jump, 4, 1, f) == 1 && w && h && uint64_t(w) * h <= 262144;
  if (!ok) { std::fclose(f); return 2; }
  const size_t n = size_t(w)*h;
  std::vector<uint8_t> ao(n), labels(n), right(n), down(n);
  std::vector<float> depth(n);
  std::vector<uint64_t> identity(n);
  std::vector<ao_contact_profile::Surface> surface(n);
  ok = std::fread(ao.data(), 1, n, f) == n && std::fread(depth.data(), 4, n, f) == n &&
      std::fread(labels.data(), 1, n, f) == n && std::fread(right.data(), 1, n, f) == n &&
      std::fread(down.data(), 1, n, f) == n && std::fread(identity.data(), 8, n, f) == n &&
      std::fgetc(f) == EOF && !std::ferror(f);
  std::fclose(f);
  if (!ok) return 2;
  for (size_t i = 0; i < n; ++i) {
    if (labels[i] > 2) return 2;
    surface[i] = static_cast<ao_contact_profile::Surface>(labels[i]);
  }
  ao_contact_profile::Image image{int(w), int(h), n, ao.data(), depth.data(), surface.data(),
                                right.data(), down.data(), identity.data()};
  const auto r = ao_contact_profile::analyze(image, jump);
  std::printf("{\"input_valid\":%s,\"measured\":%s,\"adjacent_wall_roof_edges\":%zu,"
      "\"contacts\":%zu,\"valid_contacts\":%zu,\"missing_contacts\":%zu,\"valid_sides\":%zu,"
      "\"missing_sides\":%zu,\"censored_sides\":%zu,\"depth_discontinuities\":%zu,"
      "\"band_pixels\":%zu,\"max_width\":%d}\n",
      r.input_valid ? "true" : "false", r.measured ? "true" : "false",
      r.adjacent_wall_roof_edges, r.contacts, r.valid_contacts, r.missing_contacts, r.valid_sides,
      r.missing_sides, r.censored_sides, r.depth_discontinuities, r.band_pixels, r.max_width);
  return r.input_valid && r.measured ? 0 : 3;
}
