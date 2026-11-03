# Echo and gain run on WebRTC Audio Processing

Echo cancellation and automatic gain control run on WebRTC Audio Processing (AEC3 and AGC2), the module Discord's own client uses. It runs at the pipeline's 48 kHz, on the 20 ms frames the framer already cuts, before noise suppression (ADR-0008). The library is packaged by the webrtc-audio-processing project (BSD-3-Clause) and bundled as `flucord_apm.dll`: a static build of the library behind a four-function C API, which `flucord_audio.dll` loads at run time. The echo stage's reference is a loopback of the default render endpoint.

This replaces the Windows voice capture DMO (`CLSID_CWMAudioAEC`). That DMO works at 22 kHz at most, and at the 16 kHz it ran at it cut every voice down to a telephone's band. The resampling to and from it was plain interpolation with no filter, so the upper half of the voice folded back in as a metallic edge. It went unnoticed until v0.0.17, because before that every open failed and then every frame did. A better resampler was considered and rejected: the voice would still stop at 8 kHz, and the fix would be thrown away anyway.

The library's C++ interface carries abseil types and cannot cross a DLL boundary between compilers. So a C API sits in front of it, and the DLL is loaded with `LoadLibraryExW` from the folder `flucord_audio.dll` was loaded from, not linked. A missing DLL fails the open with its own step, and the pipeline turns both switches off and says so. Nothing falls back to processing nothing.

## Status

Accepted.

## Consequences

- A frame is processed in place and returned in the same call: no frames pass through unprocessed at the start, and no answer is held back.
- AEC3 finds the delay between the speakers and the microphone itself, so no delay is reported to it. The reference is everything the machine plays, the room's voices and a game's sound alike, as before.
- When the default speakers change, the next frame loops back the new default instead of failing.
- Noise suppression in the library stays off: DeepFilterNet owns it.
- `tool/build_webrtc_apm.ps1` builds the DLL with MSVC and meson; it is committed like `df.dll` and `libdave.dll`, and the Windows build stops without it.
