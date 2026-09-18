# CONFIGURE_DEPENDS: re-glob at build time so a newly-added testcase*.cpp (e.g.
# your own testcase_rtt_tree.cpp) is picked up by a plain `make` without needing
# to re-run cmake by hand.
file(GLOB files CONFIGURE_DEPENDS "testcase*.cpp")
foreach(file ${files})
    get_filename_component(testcase ${file} NAME_WE)
    add_executable(${testcase} ${file})

    set_target_properties(${testcase}
        PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/lab"
    )
    target_link_libraries(${testcase} testing)
    if(MATH_LIBRARY)
        target_link_libraries(${testcase} ${MATH_LIBRARY})
    endif()
endforeach()
