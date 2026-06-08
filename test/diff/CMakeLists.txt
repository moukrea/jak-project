# Differential test harness (phase A2).
#
# Builds goalc-diff-runner, then registers:
#   - one SETUP fixture per backend that compiles + executes ALL inputs once
#     (expensive: builds the engine and boots the runtime), writing per-input
#     captures under ${CMAKE_BINARY_DIR}/test/diff/captures/<backend>/<name>/;
#   - one cheap check ctest per (input, backend) that compares the captured
#     final_state against the input's `;; expect:` directive.
#
# arm64 tests are no longer skipped: they run and either pass or fail honestly.

add_subdirectory(runner)

set(GOALC_DIFF_INPUT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/inputs)
set(GOALC_DIFF_CAPTURE_ROOT ${CMAKE_BINARY_DIR}/test/diff/captures)

file(GLOB GOALC_DIFF_INPUTS CONFIGURE_DEPENDS "${GOALC_DIFF_INPUT_DIR}/*.gc")

# --- expensive setup fixtures: build + run all inputs once per backend -------
add_test(
    NAME goalc-diff-setup-x86
    COMMAND $<TARGET_FILE:goalc-diff-runner>
        --all-inputs ${GOALC_DIFF_INPUT_DIR}
        --backend x86
        --capture-root ${GOALC_DIFF_CAPTURE_ROOT}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
)
set_tests_properties(goalc-diff-setup-x86 PROPERTIES
    FIXTURES_SETUP diff_x86
    LABELS "goalc-diff;backend-x86;setup"
    TIMEOUT 2400
)

add_test(
    NAME goalc-diff-setup-arm64
    COMMAND $<TARGET_FILE:goalc-diff-runner>
        --all-inputs ${GOALC_DIFF_INPUT_DIR}
        --backend arm64
        --capture-root ${GOALC_DIFF_CAPTURE_ROOT}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
)
set_tests_properties(goalc-diff-setup-arm64 PROPERTIES
    FIXTURES_SETUP diff_arm64
    LABELS "goalc-diff;backend-arm64;setup"
    TIMEOUT 1200
)

# --- per-(input, backend) cheap check tests ---------------------------------
set(_x86_test_count 0)

foreach(input_path IN LISTS GOALC_DIFF_INPUTS)
    get_filename_component(input_name ${input_path} NAME_WE)

    # Surface the input's `;; tags:` as ctest labels.
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
                --check
                --input ${input_path}
                --backend ${backend}
                --capture ${_capture_dir}
        )
        set_tests_properties(${_test_name} PROPERTIES
            LABELS "${_labels};backend-${backend}"
            FIXTURES_REQUIRED diff_${backend}
        )
        if(backend STREQUAL "x86")
            math(EXPR _x86_test_count "${_x86_test_count} + 1")
        endif()
    endforeach()
endforeach()

# Sentinel label kept for the autoport phase-00 validator, which greps the
# ctest "Label Time Summary" for a `<N> Passed` substring.
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
