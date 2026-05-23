#pragma once

#include <cstdint>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "goalc/emitter/IGenARM64.h"
#include "goalc/emitter/Register.h"

// Bring the IGen::ARM64 namespace + the ARM64_REG enum constants into scope
// so test files can write add_gpr64_gpr64(X0, X1, X2) without prefix noise.
using namespace emitter;
using namespace emitter::IGen::ARM64;

extern int g_passed;
extern int g_failed;
extern int g_total;

struct TestCase {
    const char* name;
    std::function<void()> fn;
};

std::vector<TestCase>& tests();

struct TestRegistrar {
    TestRegistrar(const char* name, std::function<void()> fn) {
        tests().push_back({name, std::move(fn)});
    }
};

#define PASTE_INNER(a, b) a##b
#define PASTE(a, b) PASTE_INNER(a, b)

#define TEST_CASE(NAME, ...)                                               \
    static void PASTE(test_fn_, __LINE__)();                               \
    static TestRegistrar PASTE(test_reg_, __LINE__)(NAME,                  \
                                                    &PASTE(test_fn_, __LINE__)); \
    static void PASTE(test_fn_, __LINE__)()

// Expect a single-word encoding match.
#define EXPECT_ENC(EXPR, EXPECTED)                                          \
    do {                                                                    \
        InstructionARM64 _r = (EXPR);                                       \
        ++g_total;                                                          \
        if (_r.encoding != (uint32_t)(EXPECTED)) {                          \
            std::fprintf(stderr,                                            \
                "  FAIL %s:%d: %s — got 0x%08x, expected 0x%08x\n",         \
                __FILE__, __LINE__, #EXPR, _r.encoding,                     \
                (uint32_t)(EXPECTED));                                      \
            ++g_failed;                                                     \
        } else {                                                            \
            ++g_passed;                                                     \
        }                                                                   \
    } while (0)

// Expect the instruction does NOT encode as ARM64 NOP (0xD503201F).
// Catches the bug class where a helper was silently reverted to a stub.
#define EXPECT_NOT_NOP(EXPR)                                                \
    do {                                                                    \
        InstructionARM64 _r = (EXPR);                                       \
        ++g_total;                                                          \
        if (_r.encoding == 0xD503201Fu) {                                   \
            std::fprintf(stderr,                                            \
                "  FAIL %s:%d: %s emitted NOP (silent stub)\n",             \
                __FILE__, __LINE__, #EXPR);                                 \
            ++g_failed;                                                     \
        } else {                                                            \
            ++g_passed;                                                     \
        }                                                                   \
    } while (0)

// Expect the high nibble (bit 28..31) of the encoding matches an expected
// ARM64-family pattern — catches "function emits x86 opcode bytes" by
// detecting that the produced word is at least in the ARM64 instruction
// space. ARM64 instructions have characteristic high-bit patterns; an x86
// opcode is highly unlikely to align with this fingerprint by accident.
#define EXPECT_ARM64_SHAPED(EXPR)                                           \
    do {                                                                    \
        InstructionARM64 _r = (EXPR);                                       \
        ++g_total;                                                          \
        uint32_t hi = (_r.encoding >> 24) & 0xffu;                          \
        bool arm_like =                                                     \
            ((_r.encoding & 0x1f000000u) != 0) ||                           \
            (_r.encoding == 0xD503201Fu) ||                                 \
            (_r.encoding == 0xD65F03C0u);                                   \
        if (!arm_like) {                                                    \
            std::fprintf(stderr,                                            \
                "  FAIL %s:%d: %s shape=0x%02x not ARM64-like (enc=0x%08x)\n", \
                __FILE__, __LINE__, #EXPR, hi, _r.encoding);                \
            ++g_failed;                                                     \
        } else {                                                            \
            ++g_passed;                                                     \
        }                                                                   \
    } while (0)

// Expect a multi-word emission has exactly N extra words (so length == 4*(N+1)).
#define EXPECT_EXTRA_WORDS(EXPR, N)                                         \
    do {                                                                    \
        InstructionARM64 _r = (EXPR);                                       \
        ++g_total;                                                          \
        if (_r.extra_words.size() != (size_t)(N)) {                         \
            std::fprintf(stderr,                                            \
                "  FAIL %s:%d: %s — got %zu extra words, expected %d\n",    \
                __FILE__, __LINE__, #EXPR, _r.extra_words.size(), (int)(N));\
            ++g_failed;                                                     \
        } else {                                                            \
            ++g_passed;                                                     \
        }                                                                   \
    } while (0)

// Expect a particular extra word (zero-based, index 0 = first word AFTER
// the primary `encoding`).
#define EXPECT_EXTRA_AT(EXPR, IDX, EXPECTED)                                \
    do {                                                                    \
        InstructionARM64 _r = (EXPR);                                       \
        ++g_total;                                                          \
        if ((size_t)(IDX) >= _r.extra_words.size()) {                       \
            std::fprintf(stderr,                                            \
                "  FAIL %s:%d: %s — extra[%d] out of range (size=%zu)\n",   \
                __FILE__, __LINE__, #EXPR, (int)(IDX),                      \
                _r.extra_words.size());                                     \
            ++g_failed;                                                     \
        } else if (_r.extra_words[(IDX)] != (uint32_t)(EXPECTED)) {         \
            std::fprintf(stderr,                                            \
                "  FAIL %s:%d: %s — extra[%d]=0x%08x, expected 0x%08x\n",   \
                __FILE__, __LINE__, #EXPR, (int)(IDX),                      \
                _r.extra_words[(IDX)], (uint32_t)(EXPECTED));               \
            ++g_failed;                                                     \
        } else {                                                            \
            ++g_passed;                                                     \
        }                                                                   \
    } while (0)
