cmake_minimum_required(VERSION 3.14)
project(flucord_overlay LANGUAGES CXX)

add_library(flucord_overlay SHARED
  "flucord_overlay.cpp"
)

target_include_directories(flucord_overlay PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(flucord_overlay PRIVATE cxx_std_17)
target_compile_definitions(flucord_overlay PRIVATE UNICODE _UNICODE)

set_target_properties(flucord_overlay PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)
