# WebRTC Audio Processing Windows binary

`flucord_apm.dll` is WebRTC Audio Processing (the echo canceller AEC3 and the
gain control AGC2), linked statically behind the small C API in `src/`.
`windows/flucord_audio`'s microphone enhancer loads it at run time.

- Upstream: <https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing>,
  v2.1 (commit `846fe90a289f58b7c9303a635142aa2c7caa93e5`), which packages the
  audio processing module of the WebRTC project
- Dependencies: abseil-cpp 20240722.0, through the library's own meson wrap,
  linked statically
- License: BSD-3-Clause, reproduced in `LICENSE`
- Target: Windows x64, Release
- MSVC runtime: static (`/MT`)

Run `powershell -ExecutionPolicy Bypass -File tool/build_webrtc_apm.ps1` from
the repository root to rebuild and replace the binary. It needs the MSVC build
tools and Python with meson and ninja (`py -m pip install meson ninja`). The
script prints the binary's SHA-256; record it here with the binary.
