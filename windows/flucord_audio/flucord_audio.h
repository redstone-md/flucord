// Captures what the machine is playing, for a screen share's own sound.
//
// A share's audio is not the microphone. Discord sends the sound of the shared
// application on the stream connection, so a viewer hears the game rather than
// the person's room; a client that reused the voice uplink for it puts the
// game into the voice channel instead, where everybody hears it whether they
// opened the stream or not.
//
// WASAPI loopback. Everything the machine plays except this process, when
// Windows can do that (build 20348 and later): the room's voices come out of
// this process, and a viewer who is in the room would hear themselves come
// back otherwise. Older builds get the whole render endpoint.

#ifndef FLUCORD_AUDIO_H_
#define FLUCORD_AUDIO_H_

#include <stdint.h>

#if defined(_WIN32)
#define FLUCORD_AUDIO_EXPORT __declspec(dllexport)
#else
#define FLUCORD_AUDIO_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  FLUCORD_AUDIO_OK = 0,
  FLUCORD_AUDIO_ERROR_STATE = 1,
  FLUCORD_AUDIO_ERROR_DEVICE = 2,
} FlucordAudioStatus;

typedef struct FlucordAudioCapture FlucordAudioCapture;

// Interleaved 16-bit PCM. The buffer belongs to the receiver from here and is
// given back with flucord_audio_release: the callback is delivered to Dart
// after the capture thread has moved on.
typedef void (*FlucordAudioCallback)(void* user_data,
                                     const int16_t* frames,
                                     int32_t frame_count,
                                     int32_t channels,
                                     int32_t sample_rate);

// Opens the loopback capture and starts a thread that pumps it.
FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_open_loopback(FlucordAudioCallback callback,
                            void* user_data,
                            FlucordAudioCapture** out_capture);

// 1 when what this process plays is left out of the capture, 0 when the
// whole endpoint is captured.
FLUCORD_AUDIO_EXPORT int32_t
flucord_audio_excludes_own_process(FlucordAudioCapture* capture);

// Releases a buffer handed out by the callback.
FLUCORD_AUDIO_EXPORT void flucord_audio_release(int16_t* frames);

FLUCORD_AUDIO_EXPORT void flucord_audio_close(FlucordAudioCapture* capture);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUCORD_AUDIO_H_
