#include <cassert>
#include <iostream>

#include "game/graphics/opengl_renderer/background/shrub_contact_archive.h"
using namespace shrub_contact_archive;
int main() {
  CaptureWindow window;
  assert(!CaptureWindow::planned(-1) && !CaptureWindow::planned(0) && !CaptureWindow::planned(60));
  assert(CaptureWindow::planned(120) && CaptureWindow::planned(600));
  assert(!CaptureWindow::planned(121) && !CaptureWindow::planned(660));
  for (int64_t frame = 120; frame <= 600; frame += 60)
    assert(window.close(frame));
  assert(!window.close(600) && !window.close(660));
  assert(window.count() == 9 && window.observed == 511 && !window.complete());
  window.tick(600);
  assert(!window.complete());
  window.tick(601);
  assert(window.complete());
  CaptureWindow absent;
  absent.close(120);
  absent.tick(601);
  assert(!absent.complete() && CaptureWindow::expected - absent.count() == 8);

  Records a{{"shrub", {{1, 2}, {3, 4}, {5, 6}, 0}}};
  auto bytes = encode(60, a);
  Records b;
  assert(decode(bytes, 60, b));
  assert(!decode(bytes, 120, b));
  assert(decode(bytes, 60, b));
  auto equal = compare(a, b, true);
  assert(!equal.missing && !equal.inputs && !equal.pre && !equal.post && equal.populations == 1);
  b["shrub"].inputs[0]++;
  assert(compare(a, b, true).inputs == 1);
  assert(decode(bytes, 60, b));
  b["shrub"].pre[0]++;
  assert(compare(a, b, false).pre == 1);
  assert(decode(bytes, 60, b));
  b["shrub"].post[0]++;
  assert(compare(a, b, true).post == 1);
  assert(compare(a, b, false).post == 0);
  b.clear();
  assert(compare(a, b, true).missing);
  assert(compare(b, b, true).missing);
  bytes[30] ^= 1;
  assert(!decode(bytes, 60, b));
  bytes.pop_back();
  assert(!decode(bytes, 60, b));
  Records current = a, reference = a;
  current["attachment"] = {{0, 0, 0, 0}, {}, {}, 2};
  assert(!compare(current, reference, true).inputs);
  current["attachment"].inputs[1] = 1;
  assert(compare(current, reference, true).inputs == 1);
  assert(!compare(current, reference, false).inputs);
  current["contact"] = {{2}, {}, {}, 1};
  reference["contact"] = {{1}, {}, {}, 1};
  assert(compare(current, reference, true).inputs == 2);
  assert(!compare(current, reference, false).inputs);
  reference["shrub"].mapped = 3;
  assert(compare(current, reference, false).missing);
  Bytes identity_bytes;
  field(identity_bytes, std::string("shrub"));
  field(identity_bytes, std::string("training"));
  number(identity_bytes, uint64_t(-1));
  number(identity_bytes, 0);
  field(identity_bytes, std::string("capture"));
  number(identity_bytes, 0);
  std::string identity_key(identity_bytes.begin(), identity_bytes.end());
  Records schema{{identity_key, {{1}, {2}, {3}, 0}}};
  assert(valid_mappings(schema));
  auto grass_key = [](const std::string& name) {
    Bytes id;
    field(id, std::string("grass"));
    field(id, std::string("training"));
    number(id, 0);
    number(id, 0);
    field(id, name);
    number(id, 0);
    return std::string(id.begin(), id.end());
  };
  for (const auto& name : {"attribute-0", "attribute-light", "uniform-u_grass_time"}) {
    Records grass_schema{{grass_key(name), {{1}, {}, {}, 0}}};
    assert(valid_mappings(grass_schema));
    grass_schema.begin()->second.mapped = 3;
    assert(!valid_mappings(grass_schema));
  }
  schema[identity_key].mapped = 3;
  assert(!valid_mappings(schema));
  const auto dir =
      std::filesystem::temp_directory_path() / ("shrub-codec-" + std::to_string(getpid()));
  std::filesystem::create_directory(dir);
  auto file = (dir / "60.shrub").string();
  assert(write(file, encode(60, a)));
  Records replacement = a;
  replacement["shrub"].inputs[0]++;
  assert(!write(file, encode(60, replacement)));
  assert(read(file, 60, b));
  assert(encode(60, b) == encode(60, a));
  assert(!std::filesystem::exists(file + ".partial"));
  assert(!read((dir / "missing").string(), 60, b));
  std::filesystem::remove(file);
  std::filesystem::remove(dir);
  std::cout << "archive_codec equality=1 corruption_rejected=1 missing_rejected=1 "
               "differences_detected=1 mappings_checked=1 atomic_no_overwrite=1 planned_window=1 "
               "grass_schema=1 overwrite_content_intact=1 partial_cleaned=1\n";
}
