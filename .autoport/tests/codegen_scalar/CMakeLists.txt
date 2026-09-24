cmake_minimum_required(VERSION 3.16)
project(codegen_scalar_gen CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# REPO_ROOT is passed in by run.sh. The real goalc/emitter/IGenARM64.cpp is
# compiled directly into the test binary — no forked copy.
if(NOT DEFINED REPO_ROOT)
    get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
endif()

set(IGEN_ARM64_SRC "${REPO_ROOT}/goalc/emitter/IGenARM64.cpp")
set(REG_STUBS "${REPO_ROOT}/.autoport/tests/emitter/encoding/register_stubs.cpp")
if(NOT EXISTS "${IGEN_ARM64_SRC}")
    message(FATAL_ERROR "Missing real source: ${IGEN_ARM64_SRC}")
endif()
if(NOT EXISTS "${REG_STUBS}")
    message(FATAL_ERROR "Missing real source: ${REG_STUBS}")
endif()

add_executable(gen
    gen.cpp
    ${IGEN_ARM64_SRC}
    ${REG_STUBS}
)

target_compile_definitions(gen PRIVATE NO_ASSERT)
target_include_directories(gen PRIVATE ${REPO_ROOT} ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(gen PRIVATE
    -O2
    -msse2
    -Wno-unused-parameter
    -Wno-unused-variable
    -Wno-unused-but-set-variable
    -Wno-unused-function
)
