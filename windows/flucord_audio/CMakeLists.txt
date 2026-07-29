cmake_minimum_required(VERSION 3.14)
project(flucord_audio LANGUAGES CXX)

add_library(flucord_audio SHARED
  "flucord_audio.cpp"
)

target_include_directories(flucord_audio PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(flucord_audio PRIVATE cxx_std_17)
target_compile_definitions(flucord_audio PRIVATE UNICODE _UNICODE)

set_target_properties(flucord_audio PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)
