# Builds flucord_apm.dll: the C API in flucord_apm.h with WebRTC Audio
# Processing linked in statically, so the DLL stands alone.
# tool/build_webrtc_apm.ps1 puts the library's source in subprojects/ and
# runs this.
project('flucord_apm', 'cpp',
  default_options: [
    'cpp_std=c++17',
    'buildtype=release',
    'default_library=static',
    'b_vscrt=mt',
  ],
)

# The library asks for C++17 but uses designated initializers. GCC allows
# them there as an extension; MSVC needs /std:c++20.
apm_dep = dependency('webrtc-audio-processing-2',
  fallback: ['webrtc-audio-processing', 'audio_processing_dep'],
  default_options: ['cpp_std=c++20'],
)

# MinGW links its own C++ runtime statically, as MSVC does with b_vscrt=mt:
# the DLL must not depend on a runtime the machine may lack.
link_args = []
if meson.get_compiler('cpp').get_id() == 'gcc'
  link_args = ['-static']
endif

shared_library('flucord_apm', 'flucord_apm.cc',
  cpp_args: ['-DFLUCORD_APM_BUILD', '-DWEBRTC_WIN', '-DNOMINMAX'],
  link_args: link_args,
  dependencies: apm_dep,
  name_prefix: '',
)
