#include <cstdio>
#include <cstring>
#include <string>
#include "game/system/shrub_proof_inputs.h"
int64_t frame = -1;
namespace autoport_proof {
bool feature_is(const char*) { return true; }
void publish(const char* k, uint64_t v) { std::printf("%s=%llu\n", k, (unsigned long long)v); }
void flush() { std::fflush(stdout); }
}
namespace pad_replay { int64_t current_frame() { return frame; } }
int main(int argc, char** argv) {
  std::string mode = argc > 1 ? argv[1] : "record";
  if (mode == "vector-record") { uint64_t n = 1048577; shrub_proof_inputs::exchange("v/count", &n, 8); return 0; }
  if (mode == "vector-read") { std::vector<int> v; shrub_proof_inputs::vector("v", v); return 0; }
  int pre = 11;
  shrub_proof_inputs::exchange("pre", &pre, sizeof(pre));
  if (mode == "preanchor-mismatch") shrub_proof_inputs::exchange("pre", &pre, sizeof(pre));
  frame = 0;
  int a = 21, b = 22;
  if (mode == "missing") shrub_proof_inputs::exchange_key("source", 999, &a, sizeof(a));
  if (mode == "replay") {
    a = b = 0;
    shrub_proof_inputs::exchange_key("source", 2, &b, sizeof(b));
    shrub_proof_inputs::exchange_key("source", 1, &a, sizeof(a));
  } else {
    shrub_proof_inputs::exchange_key("source", 1, &a, sizeof(a));
    shrub_proof_inputs::exchange_key("source", 2, &b, sizeof(b));
  }
  if (mode == "bad-duplicate") a = 8;
  shrub_proof_inputs::exchange_key("source", 1, &a, sizeof(a));
  frame = 60;
  int x = mode == "replay" ? 0 : 55;
  shrub_proof_inputs::exchange("frame-value", &x, sizeof(x));
  if (pre != 11 || a != 21 || b != 22 || x != 55) return 9;
  std::puts("values_ok=1");
}
