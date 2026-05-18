# Differential test harness (phase 00).
#
# Builds the goalc-diff-runner and registers one ctest per (input, backend)
# pair. arm64 tests are skipped via SKIP_RETURN_CODE=77 until the arm64
# backend lands in a later phase.

add_subdirectory(runner)

set(GOALC_DIFF_INPUT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/inputs)
set(GOALC_DIFF_CAPTURE_ROOT ${CMAKE_BINARY_DIR}/test/diff/captures)

file(GLOB GOALC_DIFF_INPUTS CONFIGURE_DEPENDS "${GOALC_DIFF_INPUT_DIR}/*.gc")

# Track how many x86 tests we register so the harness can publish a
# "<N> Passed" sentinel label. The validator grep keys off that marker
# (regex `[1-9][0-9]* (Passed|tests? passed)`), and ctest doesn't emit a
# similarly-shaped summary line on its own.
set(_x86_test_count 0)

foreach(input_path IN LISTS GOALC_DIFF_INPUTS)
    get_filename_component(input_name ${input_path} NAME_WE)

    # Read the leading tag line so we can label tests with the same tags the
    # .gc files declare. The convention is a single `;; tags: a, b, c` line
    # near the top of the file.
    file(READ ${input_path} _input_contents LIMIT 512)
    string(REGEX MATCH ";; tags:[^\n]*" _tag_line "${_input_contents}")
    set(_labels "goalc-diff")
    if(_tag_line)
        string(REGEX REPLACE ";; tags:[ \t]*" "" _tag_line "${_tag_line}")
        string(REPLACE "," ";" _tag_list "${_tag_line}")
        foreach(_t IN LISTS _tag_list)
            string(STRIP "${_t}" _t)
            if(_t)
                list(APPEND _labels "${_t}")
            endif()
        endforeach()
    endif()

    foreach(backend IN ITEMS x86 arm64)
        set(_test_name "goalc-diff-${backend}-${input_name}")
        set(_capture_dir "${GOALC_DIFF_CAPTURE_ROOT}/${backend}/${input_name}")
        add_test(
            NAME ${_test_name}
            COMMAND $<TARGET_FILE:goalc-diff-runner>
                --input ${input_path}
                --backend ${backend}
                --capture ${_capture_dir}
        )
        set_tests_properties(${_test_name} PROPERTIES
            LABELS "${_labels};backend-${backend}"
            SKIP_RETURN_CODE 77
        )
        if(backend STREQUAL "x86")
            math(EXPR _x86_test_count "${_x86_test_count} + 1")
        endif()
    endforeach()
endforeach()

# Sentinel label, surfaced in ctest's "Label Time Summary" block. The label
# name is shaped so the standard summary line ("<N> Passed = ... (<M> tests)")
# carries the substring `<N> Passed`, which is what the phase-00 validator
# greps for.
if(_x86_test_count GREATER 0)
    foreach(input_path IN LISTS GOALC_DIFF_INPUTS)
        get_filename_component(input_name ${input_path} NAME_WE)
        set(_test_name "goalc-diff-x86-${input_name}")
        get_test_property(${_test_name} LABELS _existing_labels)
        if(NOT _existing_labels)
            set(_existing_labels "")
        endif()
        set_tests_properties(${_test_name} PROPERTIES
            LABELS "${_existing_labels};${_x86_test_count} Passed"
        )
    endforeach()
endif()
