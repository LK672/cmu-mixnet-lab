# Build the `node` binary from every .c in this directory so that multi-file
# implementations (a node.c plus helper .c files) link automatically. A plain
# single-file node.c still works -- the glob just matches node.c.
file(GLOB NODE_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/*.c)
add_executable(node ${NODE_SOURCES})
target_link_libraries(node
    fragment
)
