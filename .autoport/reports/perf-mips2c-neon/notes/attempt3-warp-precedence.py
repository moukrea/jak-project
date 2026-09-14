"""Check the production warp selection block in isolation; no game/device proof."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[4]
source = (root / "game/kernel/jak1/kmachine.cpp").read_text()
start = source.index("    char campaign_pos[64] = {0};", source.index("static u64 level_warp_run()"))
end = source.index("    float mx, my, mz;", start)
block = source[start:end]
prefix = r'''
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
constexpr int PROP_VALUE_MAX = 92;
const char* property = "-116 14 40";
int property_reads = 0;
int __system_property_get(const char*, char* out) {
  ++property_reads;
  std::strcpy(out, property);
  return std::strlen(out);
}
namespace perf_baseline {
const char* position = nullptr;
bool warp_position(char* out, size_t size) {
  if (!position) return false;
  std::strncpy(out, position, size - 1);
  return true;
}
}
std::string resolve() {
  char posbuf[128] = {0};
'''
suffix = r'''
  return posbuf;
}
int main() {
  struct Case { const char* name; const char* env; const char* campaign; const char* expected; };
  Case cases[] = {
#if defined(__ANDROID__)
    {"initial-property", nullptr, nullptr, "-116 14 40"},
#else
    {"initial-no-property", nullptr, nullptr, ""},
#endif
    {"refset-native-position", "", nullptr, ""},
    {"refset-explicit-position", "1 2 3", nullptr, "1 2 3"},
    {"campaign-native-position", "4 5 6", "", ""},
    {"campaign-explicit-position", "4 5 6", "7 8 9", "7 8 9"},
  };
  int failures = 0;
  for (const auto& c : cases) {
    if (c.env) setenv("OG_LEVEL_WARP_POS", c.env, 1);
    else unsetenv("OG_LEVEL_WARP_POS");
    perf_baseline::position = c.campaign;
    property_reads = 0;
    auto result = resolve();
    bool ok = result == c.expected;
    if (c.env || c.campaign) ok = ok && property_reads == 0;
    std::printf("%s %s result='%s' property_reads=%d\n", ok ? "PASS" : "FAIL",
                c.name, result.c_str(), property_reads);
    failures += !ok;
  }
  return failures ? 1 : 0;
}
'''
with tempfile.TemporaryDirectory(prefix="warp-precedence-") as tmp:
    cpp = Path(tmp) / "warp.cpp"
    cpp.write_text(prefix + block + suffix)
    for platform, defines in (("desktop", []), ("android-selection-stub", ["-D__ANDROID__"])):
        exe = Path(tmp) / platform
        subprocess.run(["c++", "-std=c++17", *defines, str(cpp), "-o", str(exe)], check=True)
        print(platform, flush=True)
        subprocess.run([str(exe)], check=True)
