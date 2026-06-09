add_executable(goalc-codegen-diff main.cpp)
target_link_libraries(goalc-codegen-diff common Zydis capstone-static compiler)
