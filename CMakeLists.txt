cmake_minimum_required(VERSION 3.20)
project(AtariGammaForce
    VERSION 0.1.0
    DESCRIPTION "Atari Gamma Force: a vertical shooter for the Atari 7800 (7800basic + assembly)"
    LANGUAGES NONE
)

# The build itself is tools/build.sh, which uses the 7800basic vendored in
# tools/7800basic (needs wasmtime on the PATH). CMake just runs it when a
# source changes, so the usual "cmake --build" works.
file(GLOB_RECURSE GAME_SOURCES CONFIGURE_DEPENDS
    ${CMAKE_SOURCE_DIR}/src/*.bas
    ${CMAKE_SOURCE_DIR}/src/*.asm
    ${CMAKE_SOURCE_DIR}/src/*.png
    ${CMAKE_SOURCE_DIR}/src/music/*.bin
)

add_custom_command(
    OUTPUT ${CMAKE_SOURCE_DIR}/build/gammaforce.a78
    COMMAND sh ${CMAKE_SOURCE_DIR}/tools/build.sh
    DEPENDS ${GAME_SOURCES} ${CMAKE_SOURCE_DIR}/tools/build.sh
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Building gammaforce.a78 with 7800basic"
    VERBATIM
)
add_custom_target(gammaforce ALL DEPENDS ${CMAKE_SOURCE_DIR}/build/gammaforce.a78)

# Regenerate src/gfx, src/gen from assets/ (needs .venv with Pillow+numpy).
add_custom_target(assets
    COMMAND ${CMAKE_SOURCE_DIR}/.venv/bin/python ${CMAKE_SOURCE_DIR}/tools/gen_assets.py
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Converting assets/ to 7800 graphics and data"
)

# Headless scroll-engine regression test (needs the a7800 emulator).
add_custom_target(test-scroll
    COMMAND sh ${CMAKE_SOURCE_DIR}/tools/test_scroll.sh
    DEPENDS gammaforce
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
)
