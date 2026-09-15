#include "game/graphics/opengl_renderer/ao_contact_profile.h"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <vector>

namespace profile = ao_contact_profile;
using profile::Surface;

static void check(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAIL " << description << '\n';
    std::exit(1);
  }
}

struct Fixture {
  std::vector<uint8_t> ao = std::vector<uint8_t>(20, 100);
  std::vector<float> depth = std::vector<float>(20, .5f);
  std::vector<Surface> surface = std::vector<Surface>(20, Surface::wall);
  std::vector<uint64_t> identity = std::vector<uint64_t>(20, 1);
  std::vector<uint8_t> right = std::vector<uint8_t>(20, 0);
  std::vector<uint8_t> down = std::vector<uint8_t>(20, 0);
  Fixture() {
    for (int i = 10; i < 20; ++i) {
      surface[i] = Surface::roof;
      identity[i] = 2;
    }
    right[9] = 1;
  }
  profile::Image image() const {
    return {20, 1, ao.size(), ao.data(), depth.data(), surface.data(), right.data(), down.data(),
            identity.data()};
  }
  void band(int width, int difference = 20, bool both = true) {
    for (int i = 0; i < width; ++i) {
      ao[9 - i] = uint8_t(100 + difference);
      if (both) ao[10 + i] = uint8_t(100 + difference);
    }
  }
};

int main() {
  for (int width : {1, 3, 8}) {
    Fixture f;
    f.band(width);
    const auto r = profile::analyze(f.image(), .01f);
    check(r.input_valid && r.measured && r.contacts == 1 && r.valid_contacts == 1 &&
              r.valid_sides == 2 && r.missing_contacts == 0 && r.max_width == width &&
              r.band_pixels == size_t(2 * width), "two-sided width");
    std::cout << "PASS width=" << width << " max_width=" << r.max_width
              << " band_pixels=" << r.band_pixels << '\n';
  }
  {
    Fixture f;
    f.band(10);
    const auto r = profile::analyze(f.image(), .01f);
    check(!r.measured && r.censored_sides == 2 && r.valid_contacts == 0 &&
              r.missing_contacts == 1 && r.band_pixels == 0, "uniform plateau censored");
    std::cout << "PASS uniform_plateau measured=0 censored_sides=2\n";
  }
  {
    Fixture f;
    f.band(3, 20, false);
    for (int i = 10; i < 20; ++i) f.depth[i] = .8f;
    const auto r = profile::analyze(f.image(), .01f);
    check(r.measured && r.valid_sides == 1 && r.censored_sides == 1 &&
              r.max_width == 3 && r.band_pixels == 3 && r.depth_discontinuities == 1,
          "unilateral band retained across depth discontinuity");
    auto vertical = f.image();
    vertical.width = 1;
    vertical.height = 20;
    vertical.qualified_right = nullptr;
    vertical.qualified_down = f.right.data();
    const auto v = profile::analyze(vertical, .01f);
    check(v.measured && v.max_width == 3 && v.band_pixels == 3 && v.contacts == 1,
          "vertical edge");
    std::cout << "PASS unilateral horizontal_and_vertical width=3 depth_discontinuities=1\n";
  }
  for (int difference : {4, 5}) {
    Fixture f;
    f.band(1, difference);
    const auto r = profile::analyze(f.image(), .01f);
    check(r.measured && r.valid_sides == 2 && r.max_width == (difference == 5 ? 1 : 0),
          "strict threshold");
    std::cout << "PASS difference=" << difference << " max_width=" << r.max_width << '\n';
  }
  {
    Fixture f;
    f.band(3);
    f.right[9] = 0;
    auto r = profile::analyze(f.image(), .01f);
    check(r.adjacent_wall_roof_edges == 1 && r.contacts == 0 && !r.measured,
          "unqualified adjacency is not a contact");
    auto image = f.image();
    image.qualified_right = nullptr;
    check(!profile::analyze(image, .01f).measured, "absent qualification");
    f.surface.assign(20, Surface::wall);
    r = profile::analyze(f.image(), .01f);
    check(r.input_valid && r.contacts == 0 && !r.measured && r.adjacent_wall_roof_edges == 0,
          "empty population");
    check(!profile::analyze({}, .01f).input_valid, "empty image");
    image = f.image();
    image.ao = nullptr;
    check(!profile::analyze(image, .01f).input_valid, "missing AO array");
    image = f.image();
    image.size = 19;
    check(!profile::analyze(image, .01f).input_valid, "short arrays");
    std::cout << "PASS empty unqualified missing_arrays short_arrays\n";
  }
  for (float invalid : {std::numeric_limits<float>::quiet_NaN(),
                        std::numeric_limits<float>::infinity(), 0.f, 1e-9f, -.1f, 1.01f}) {
    Fixture f;
    f.band(3);
    f.depth[9] = invalid;
    const auto r = profile::analyze(f.image(), .01f);
    check(r.contacts == 1 && !r.measured && r.missing_contacts == 1 && r.missing_sides == 2,
          "invalid endpoint");
  }
  std::cout << "PASS NaN infinity sky_zero sky_1e-9 negative_depth depth_above_one endpoints_missing\n";
  {
    Fixture f;
    f.band(3);
    f.depth.assign(20, 1.f);
    auto r = profile::analyze(f.image(), .01f);
    check(r.measured && r.valid_sides == 2 && r.max_width == 3 && r.band_pixels == 6,
          "reverse-Z depth one is valid");
    f.depth.assign(20, std::nextafter(1e-9f, 1.f));
    r = profile::analyze(f.image(), .01f);
    check(r.measured && r.valid_sides == 2 && r.max_width == 3,
          "reverse-Z depth just above sky threshold is valid");
    std::cout << "PASS reverse_Z depth_one_valid depth_above_sky_threshold_valid\n";
  }
  {
    Fixture f;
    f.band(3);
    f.identity[8] = 3;  // A different wall, despite identical Surface::wall class.
    auto r = profile::analyze(f.image(), .01f);
    check(r.contacts == 1 && r.measured && r.valid_sides == 1 && r.missing_sides == 1 &&
              r.max_width == 3 && r.band_pixels == 3, "stop at another wall identity");
    f.identity[8] = 0;
    r = profile::analyze(f.image(), .01f);
    check(r.valid_sides == 1 && r.missing_sides == 1 && r.band_pixels == 3,
          "stop at unknown interior identity");
    f.identity[9] = 0;
    r = profile::analyze(f.image(), .01f);
    check(!r.measured && r.contacts == 1 && r.missing_sides == 2 && r.missing_contacts == 1,
          "unknown endpoint identity invalidates contact measurement");
    auto image = f.image();
    image.identity = nullptr;
    r = profile::analyze(image, .01f);
    check(r.input_valid && !r.measured && r.contacts == 1 && r.missing_contacts == 1,
          "absent identities cannot produce measurement");
    std::cout << "PASS identity different_wall unknown_interior unknown_endpoint absent_array\n";
  }
  {
    Fixture f;
    f.band(3);
    f.depth[8] = std::numeric_limits<float>::quiet_NaN();
    auto r = profile::analyze(f.image(), .01f);
    check(r.measured && r.valid_sides == 1 && r.missing_sides == 1 && r.band_pixels == 3,
          "stop at NaN interior");
    f.depth[8] = .5f;
    f.surface[8] = Surface::unknown;
    r = profile::analyze(f.image(), .01f);
    check(r.valid_sides == 1 && r.missing_sides == 1 && r.band_pixels == 3,
          "stop at unknown interior");
    f.surface[8] = Surface::roof;
    r = profile::analyze(f.image(), .01f);
    check(r.contacts == 1 && r.valid_sides == 1 && r.missing_sides == 1 && r.band_pixels == 3,
          "stop at changed identity");
    f.surface[9] = Surface::unknown;
    r = profile::analyze(f.image(), .01f);
    check(r.contacts == 0 && !r.measured, "unknown endpoint");
    std::cout << "PASS interior_stop NaN unknown changed_identity unknown_endpoint\n";
  }
  {
    Fixture f;
    f.band(1);
    auto image = f.image();
    image.width = 2;
    image.size = 2;
    image.ao += 9;
    image.depth += 9;
    image.surface += 9;
    image.identity += 9;
    image.qualified_right += 9;
    const auto r = profile::analyze(image, .01f);
    check(r.contacts == 1 && !r.measured && r.missing_sides == 2 && r.missing_contacts == 1,
          "image boundaries do not supply interior reference");
    std::cout << "PASS image_border measured=0 missing_sides=2\n";
  }
  std::cout << "PASS ao_contact_profile all cases\n";
}
