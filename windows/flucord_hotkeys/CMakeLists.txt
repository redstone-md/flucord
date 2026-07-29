cmake_minimum_required(VERSION 3.14)
project(flucord_hotkeys LANGUAGES CXX)

# A hundred lines against user32, built beside the runner for the same reason
# the video module is: a prebuilt binary in the tree would be one more thing to
# trust and to rebuild by hand.
add_library(flucord_hotkeys SHARED
  "flucord_hotkeys.cpp"
)

target_include_directories(flucord_hotkeys PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(flucord_hotkeys PRIVATE cxx_std_17)
target_compile_definitions(flucord_hotkeys PRIVATE UNICODE _UNICODE)

set_target_properties(flucord_hotkeys PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)
