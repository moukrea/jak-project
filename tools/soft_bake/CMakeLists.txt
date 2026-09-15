# Optional desktop target; wrapper builds without reconfiguring an existing tree.
add_executable(soft_bake main.cpp)
target_link_libraries(soft_bake common fmt)
target_compile_options(soft_bake PRIVATE -ffp-contract=off)
