// flucord_apm: a small C API over WebRTC Audio Processing
// (webrtc-audio-processing, BSD-3-Clause), for the microphone enhancer in
// flucord_audio.
//
// The library's own interface is C++ with abseil types in it, which cannot
// cross a DLL boundary between two compilers. These four functions can, so
// flucord_audio loads this DLL at run time and never sees the C++ side.
//
// Every buffer is one 10 ms chunk of interleaved 16-bit PCM: sample_rate / 100
// frames of channels samples each, the unit the library works in.

#ifndef FLUCORD_APM_H_
#define FLUCORD_APM_H_

#include <stdint.h>

#if defined(_WIN32) && defined(FLUCORD_APM_BUILD)
#define FLUCORD_APM_EXPORT __declspec(dllexport)
#else
#define FLUCORD_APM_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FlucordApm FlucordApm;

// A processor with the asked stages: echo cancellation (AEC3) takes what the
// speakers play out of the microphone, and gain control (AGC2, adaptive
// digital) keeps the voice level steady. Both run at the full band. A high
// pass filter takes out rumble below the voice. Noise suppression stays off:
// DeepFilterNet owns it in the same pipeline. Null when neither stage is
// asked for, or when there is no memory.
FLUCORD_APM_EXPORT FlucordApm* flucord_apm_create(
    int32_t echo_cancellation,
    int32_t automatic_gain_control);

// Hands over one chunk of what the speakers are playing, the reference the
// echo stage takes out of the microphone. Answers 0, or the library's error
// code.
FLUCORD_APM_EXPORT int32_t flucord_apm_process_render(FlucordApm* apm,
                                                      const int16_t* samples,
                                                      int32_t sample_rate,
                                                      int32_t channels);

// Processes one chunk of microphone in place. Answers 0, or the library's
// error code.
FLUCORD_APM_EXPORT int32_t flucord_apm_process_capture(FlucordApm* apm,
                                                       int16_t* samples,
                                                       int32_t sample_rate,
                                                       int32_t channels);

FLUCORD_APM_EXPORT void flucord_apm_destroy(FlucordApm* apm);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUCORD_APM_H_
