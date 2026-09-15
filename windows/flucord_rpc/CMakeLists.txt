cmake_minimum_required(VERSION 3.14)
project(flucord_rpc LANGUAGES CXX)

# The Rich Presence pipe server, beside the runner like every other native
# module: named pipes cannot be reached from Dart's socket API, and a client
# that publishes what a game sent needs this end of the pipe.
add_library(flucord_rpc SHARED
  "flucord_rpc.cpp"
)

target_include_directories(flucord_rpc PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(flucord_rpc PRIVATE cxx_std_17)
target_compile_definitions(flucord_rpc PRIVATE UNICODE _UNICODE)

set_target_properties(flucord_rpc PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)
