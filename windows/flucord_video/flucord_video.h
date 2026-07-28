// Screen capture and H.264 encoding for Discord's Go Live.
//
// Everything above this lives in Dart: the stream key, the gateway frames, the
// RTP sender. What Dart cannot do is turn a desktop into encoded frames —
// flutter_webrtc exposes capture and a renderer but no encoded-frame callback,
// and Go Live carries its own RTP over the voice socket rather than through a
// peer connection, so a peer connection would not help even if one were open.
//
// Media Foundation rather than libwebrtc: the H.264 encoder MFT ships with
// Windows, uses the GPU when one is available, and needs no headers or import
// library that the Flutter plugin does not give us.

#ifndef FLUCORD_VIDEO_H_
#define FLUCORD_VIDEO_H_

#include <stdint.h>

#if defined(_WIN32)
#define FLUCORD_VIDEO_EXPORT __declspec(dllexport)
#else
#define FLUCORD_VIDEO_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Status codes. Anything other than OK leaves the encoder untouched.
typedef enum {
  FLUCORD_VIDEO_OK = 0,
  FLUCORD_VIDEO_ERROR_UNSUPPORTED = 1,
  FLUCORD_VIDEO_ERROR_NO_DISPLAY = 2,
  FLUCORD_VIDEO_ERROR_ENCODER = 3,
  FLUCORD_VIDEO_ERROR_STATE = 4,
} FlucordVideoStatus;

typedef struct FlucordVideoEncoder FlucordVideoEncoder;

// One encoded frame, as an Annex B access unit.
//
// The buffer is heap-allocated by the encoder and handed to the callee, which
// must release it with flucord_video_release_frame once it has copied what it
// needs. It cannot be a borrowed pointer: Dart delivers a native callback
// asynchronously, and the capture thread has released the underlying surface
// long before the listener runs.
typedef void (*FlucordVideoFrameCallback)(void* user_data,
                                          const uint8_t* data,
                                          int32_t length,
                                          int64_t timestamp_us,
                                          int32_t is_keyframe);

typedef struct {
  // Which display to capture. 0 is the primary one.
  int32_t display_index;
  int32_t width;
  int32_t height;
  int32_t frames_per_second;
  int32_t bitrate_bits_per_second;
} FlucordVideoConfig;

// Opens a capture-and-encode pipeline. The callback runs on the capture
// thread, so the caller must not block in it.
FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_open(const FlucordVideoConfig* config,
                   FlucordVideoFrameCallback callback,
                   void* user_data,
                   FlucordVideoEncoder** out_encoder);

// Asks the encoder for a keyframe on the next capture, which is what a viewer
// joining midway needs before anything decodes.
FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_request_keyframe(FlucordVideoEncoder* encoder);

// Stops capturing without tearing the encoder down. Frames stop arriving.
FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_set_paused(FlucordVideoEncoder* encoder, int32_t paused);

// Stops and releases everything. Safe to call twice.
FLUCORD_VIDEO_EXPORT void flucord_video_close(FlucordVideoEncoder* encoder);

// Releases a buffer handed out by the frame callback.
FLUCORD_VIDEO_EXPORT void flucord_video_release_frame(uint8_t* data);

typedef struct FlucordVideoDecoder FlucordVideoDecoder;

// One decoded picture, as BGRA ready for a texture. Valid for the duration of
// the callback only: the decoder reuses its buffer.
typedef void (*FlucordVideoPictureCallback)(void* user_data,
                                            const uint8_t* bgra,
                                            int32_t width,
                                            int32_t height,
                                            int32_t stride,
                                            int64_t timestamp_us);

// Opens a decoder for somebody else's stream. Frames are fed in as Annex B
// access units and come back out as pictures.
FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_decoder_open(FlucordVideoPictureCallback callback,
                           void* user_data,
                           FlucordVideoDecoder** out_decoder);

// Feeds one access unit in. Pictures arrive on the callback, synchronously,
// before this returns.
FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_decoder_submit(FlucordVideoDecoder* decoder,
                             const uint8_t* annex_b,
                             int32_t length,
                             int64_t timestamp_us);

FLUCORD_VIDEO_EXPORT void flucord_video_decoder_close(
    FlucordVideoDecoder* decoder);

// Runs an Annex B stream through the system H.264 decoder and returns how
// many pictures came out, or a negative status on failure.
//
// This is how the client checks its own output without a second account
// watching: the decoder here is the same Media Foundation one a Discord
// client on Windows decodes with, so a stream it accepts is a stream a viewer
// can draw.
FLUCORD_VIDEO_EXPORT int32_t
flucord_video_decode_probe(const uint8_t* annex_b, int32_t length);

// How many displays are available, so a picker has something to list.
FLUCORD_VIDEO_EXPORT int32_t flucord_video_display_count(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUCORD_VIDEO_H_
