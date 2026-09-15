// Reproducer of the two operand orders observed in the archived sample13 code.
// Laboratory only: no NaN normalization and no engine/proof instrumentation.
#include <cstdint>
#include <cstdio>
#include <cstring>

__attribute__((noinline)) float ordered_mul(float first, float second) {
  float result;
#if defined(__aarch64__)
  asm("fmul %s0, %s1, %s2" : "=w"(result) : "w"(first), "w"(second));
#elif defined(__x86_64__)
  asm("vmulss %2, %1, %0" : "=x"(result) : "x"(first), "x"(second));
#else
#error Unsupported laboratory architecture
#endif
  return result;
}

static float value(uint32_t bits) {
  float result;
  std::memcpy(&result, &bits, sizeof(result));
  return result;
}
static uint32_t bits(float value) {
  uint32_t result;
  std::memcpy(&result, &value, sizeof(result));
  return result;
}

int main() {
#if defined(__aarch64__)
  constexpr uint32_t invalid_nan = 0x7fc00000;
#else
  constexpr uint32_t invalid_nan = 0xffc00000;
#endif
  constexpr uint32_t inputs[][2] = {
      {invalid_nan, 0x7fc12345}, {invalid_nan, 0xffc54321},
      {0x7fc12345, 0xffc54321}, {0x7fc12345, 0xff854321},
      {0x7f812345, 0xffc54321}, {0x3f800000, 0x3f000000}};
  unsigned differences = 0;
  for (const auto& input : inputs) {
    const auto before = bits(ordered_mul(value(input[0]), value(input[1])));
    const auto after = bits(ordered_mul(value(input[1]), value(input[0])));
    differences += before != after;
    std::printf("MUL velocity=%08x damping=%08x before_order=%08x after_order=%08x different=%u\n",
                input[0], input[1], before, after, before != after);
  }
  std::printf("REPRO cases=6 order_differences=%u\n", differences);
  return 0;
}
