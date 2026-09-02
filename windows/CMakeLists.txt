# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(flucord LANGUAGES CXX)

set(FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR
  "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR}" CACHE PATH
  "Directory containing discord_partner_sdk/discordpp.h")
set(FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY
  "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY}" CACHE FILEPATH
  "Exact Discord Social SDK import library path")
set(FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME
  "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME}" CACHE FILEPATH
  "Exact Discord Social SDK runtime library path")

if(NOT FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR AND
   NOT "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR}" STREQUAL "")
  set(FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR
    "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR}" CACHE PATH "" FORCE)
endif()
if(NOT FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY AND
   NOT "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY}" STREQUAL "")
  set(FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY
    "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY}" CACHE FILEPATH "" FORCE)
endif()
if(NOT FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME AND
   NOT "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME}" STREQUAL "")
  set(FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME
    "$ENV{FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME}" CACHE FILEPATH "" FORCE)
endif()

if((FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR AND
    NOT FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY) OR
   (FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY AND
    NOT FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR))
  message(FATAL_ERROR
    "Discord Social SDK requires both FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR and FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY")
endif()

set(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED OFF)
if(FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR AND
   FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY)
  if(NOT IS_DIRECTORY "${FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR}")
    message(FATAL_ERROR
      "Discord Social SDK include directory does not exist: ${FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR}")
  endif()
  if(NOT EXISTS "${FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR}/discord_partner_sdk/discordpp.h")
    message(FATAL_ERROR
      "Discord Social SDK header was not found below the configured include directory")
  endif()
  if(NOT EXISTS "${FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY}")
    message(FATAL_ERROR
      "Discord Social SDK import library does not exist: ${FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY}")
  endif()
  set(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED ON)
endif()

if(FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME AND
   NOT EXISTS "${FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME}")
  message(FATAL_ERROR
    "Discord Social SDK runtime does not exist: ${FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME}")
endif()

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "flucord")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# MSVC 14.51 turns the legacy coroutine header used by webview_windows 0.4.0
# into a hard error. Keep the compatibility define scoped to that plugin.
if(TARGET webview_windows_plugin)
  target_compile_definitions(webview_windows_plugin PRIVATE
    _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
endif()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Screen capture and H.264 encoding for Go Live. Built from source in-tree:
# it is Media Foundation and Desktop Duplication, both of which ship with
# Windows, so there is nothing to fetch.
add_subdirectory("flucord_video")
add_dependencies(${BINARY_NAME} flucord_video)
install(FILES "$<TARGET_FILE:flucord_video>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

# The keyboard hook, so a keybind reaches the client from behind another
# window. Separate from the video module: it shares nothing with it but the
# reason for being native.
add_subdirectory("flucord_hotkeys")
add_dependencies(${BINARY_NAME} flucord_hotkeys)
install(FILES "$<TARGET_FILE:flucord_hotkeys>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

# The overlay window: layered, click-through, above everything else.
add_subdirectory("flucord_overlay")
add_dependencies(${BINARY_NAME} flucord_overlay)
install(FILES "$<TARGET_FILE:flucord_overlay>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

# What the machine is playing, for a share's own sound.
add_subdirectory("flucord_audio")
add_dependencies(${BINARY_NAME} flucord_audio)
install(FILES "$<TARGET_FILE:flucord_audio>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

set(LIBDAVE_DLL "${CMAKE_CURRENT_SOURCE_DIR}/third_party/libdave/libdave.dll")
if(NOT EXISTS "${LIBDAVE_DLL}")
  message(FATAL_ERROR "Missing ${LIBDAVE_DLL}; run tool/build_libdave.ps1")
endif()
install(FILES "${LIBDAVE_DLL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# DeepFilterNet (libDF C API) and its model, for microphone noise suppression.
set(DEEPFILTERNET_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/deepfilternet")
foreach(DEEPFILTERNET_FILE "df.dll" "DeepFilterNet3_onnx.tar.gz")
  if(NOT EXISTS "${DEEPFILTERNET_DIR}/${DEEPFILTERNET_FILE}")
    message(FATAL_ERROR
      "Missing ${DEEPFILTERNET_DIR}/${DEEPFILTERNET_FILE}; run tool/build_deepfilternet.ps1")
  endif()
  install(FILES "${DEEPFILTERNET_DIR}/${DEEPFILTERNET_FILE}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endforeach()

if(FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME)
  install(FILES "${FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endif()

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
