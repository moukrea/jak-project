// Phase A7 — emitter encoding test runner.
//
// Tests register themselves via TestRegistrar (static-init) and this main()
// walks the registry, invokes each, and reports pass/fail counts. Exit 0
// iff every assertion passed. No external test framework — fast cold-start.

#include <cstdio>
#include <cstdlib>

#include "test_helpers.h"

int g_passed = 0;
int g_failed = 0;
int g_total = 0;

std::vector<TestCase>& tests() {
    static std::vector<TestCase> v;
    return v;
}

int main() {
    auto& all = tests();
    std::fprintf(stderr, "Phase A7 encoding tests: %zu test cases\n", all.size());
    for (auto& t : all) {
        t.fn();
    }
    std::fprintf(stderr,
        "encoding tests: %d assertions, %d passed, %d failed across %zu cases\n",
        g_total, g_passed, g_failed, all.size());
    return g_failed ? 1 : 0;
}
