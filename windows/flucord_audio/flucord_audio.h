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

// Attenuates every other application's audio, for "attenuate while
// speaking": the volume of each audio session not owned by this process is
// multiplied by (1 - level) and the previous level remembered. level is
// 0.0 to 1.0; 0.0 restores what each session had. Only one level is in
// force at a time: a second call replaces it.
FLUCORD_AUDIO_EXPORT int32_t
flucord_audio_attenuate_others(double level);

// Restores every other application's audio to the level it had before
// attenuation started.
FLUCORD_AUDIO_EXPORT int32_t flucord_audio_restore_others(void);

// The microphone enhancer: takes what the speakers are playing out of the
// microphone and keeps its level steady, through the Windows voice capture
// stages. echo_cancellation and automatic_gain_control say which stages run.
// The stages work a frame behind the microphone: the enhanced frame that
// comes back is the previous one's, and what is left inside comes out with
// the next frames given to flucord_audio_enhance_frame.
typedef struct FlucordAudioEnhancer FlucordAudioEnhancer;

FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_open_mic_enhancer(int32_t echo_cancellation,
                                int32_t automatic_gain_control,
                                FlucordAudioEnhancer** out_enhancer);

// Enhances one frame of interleaved 16-bit PCM in place. samples holds
// sample_count_per_channel samples on each of channels interleaved channels.
FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_enhance_frame(FlucordAudioEnhancer* enhancer,
                            int16_t* samples,
                            int32_t sample_count_per_channel,
                            int32_t channels);

FLUCORD_AUDIO_EXPORT void
flucord_audio_close_mic_enhancer(FlucordAudioEnhancer* enhancer);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUCORD_AUDIO_H_
