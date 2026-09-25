cmake_minimum_required(VERSION 3.16)
project(int_div_parity_gen CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# REPO_ROOT is passed in by run.sh. The real goalc/emitter/IGenARM64.cpp and
# IGenX86.cpp are compiled directly into the test binary — no forked copy.
if(NOT DEFINED REPO_ROOT)
    get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
endif()

set(IGEN_ARM64_SRC "${REPO_ROOT}/goalc/emitter/IGenARM64.cpp")
set(IGEN_X86_SRC "${REPO_ROOT}/goalc/emitter/IGenX86.cpp")
set(REG_STUBS "${REPO_ROOT}/.autoport/tests/emitter/encoding/register_stubs.cpp")
foreach(f IN ITEMS ${IGEN_ARM64_SRC} ${IGEN_X86_SRC} ${REG_STUBS})
    if(NOT EXISTS "${f}")
        message(FATAL_ERROR "Missing real source: ${f}")
    endif()
endforeach()

add_executable(gen
    gen.cpp
    ${IGEN_ARM64_SRC}
    ${IGEN_X86_SRC}
    ${REG_STUBS}
)

target_compile_definitions(gen PRIVATE NO_ASSERT)
target_include_directories(gen PRIVATE ${REPO_ROOT} ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(gen PRIVATE
    -O2
    -Wno-unused-parameter
    -Wno-unused-variable
    -Wno-unused-but-set-variable
    -Wno-unused-function
)
