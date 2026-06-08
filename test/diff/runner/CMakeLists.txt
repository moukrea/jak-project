# goalc-diff-runner: CLI harness used by the goalc-diff ctest suite.
#
# Phase A2: links the compiler (to compile inputs for both backends) and the
# runtime (to execute x86 inputs on an in-process gk and capture output).

add_executable(goalc-diff-runner runner.cpp)
target_link_libraries(goalc-diff-runner compiler runtime)
set_target_properties(goalc-diff-runner PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
)
