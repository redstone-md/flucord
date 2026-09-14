cmake_minimum_required(VERSION 3.14)
project(flucord_video LANGUAGES CXX)

# Built alongside the runner rather than fetched: it is a few hundred lines
# against Media Foundation, and a prebuilt binary in the tree would be one more
# thing to trust and to rebuild by hand.
add_library(flucord_video SHARED
  "flucord_video.cpp"
  "qpc_clock.cpp"
)

target_include_directories(flucord_video PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(flucord_video PRIVATE cxx_std_17)
target_compile_definitions(flucord_video PRIVATE UNICODE _UNICODE)

target_link_libraries(flucord_video PRIVATE
  d3d11
  dxgi
  mf
  mfplat
  mfuuid
  wmcodecdspuuid
)

set_target_properties(flucord_video PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)

option(FLUCORD_VIDEO_BUILD_TESTS "Build the native video tests" OFF)
if(FLUCORD_VIDEO_BUILD_TESTS)
  enable_testing()
  add_executable(flucord_video_clock_test
    "qpc_clock_test.cpp"
    "qpc_clock.cpp"
  )
  target_compile_features(flucord_video_clock_test PRIVATE cxx_std_17)
  add_test(NAME flucord_video_clock_test COMMAND flucord_video_clock_test)
endif()
