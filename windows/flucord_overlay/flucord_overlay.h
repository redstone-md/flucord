// A click-through window that floats above everything else.
//
// Not an injected overlay. Discord's own draws inside another process by
// hooking its presentation, which is the same technique anti-cheat systems
// watch for and refuse; a layered, transparent, topmost window of our own
// shows the same thing over any windowed or borderless-fullscreen game
// without touching that game's process at all. Exclusive fullscreen is the
// case it cannot cover, and the client says so rather than pretending.
//
// The picture is rendered in Dart and handed here as premultiplied BGRA: the
// overlay should look like the rest of the client, and a second drawing stack
// in C++ would be a second one to keep in step.

#ifndef FLUCORD_OVERLAY_H_
#define FLUCORD_OVERLAY_H_

#include <stdint.h>

#if defined(_WIN32)
#define FLUCORD_OVERLAY_EXPORT __declspec(dllexport)
#else
#define FLUCORD_OVERLAY_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  FLUCORD_OVERLAY_OK = 0,
  FLUCORD_OVERLAY_ERROR_STATE = 1,
  FLUCORD_OVERLAY_ERROR_WINDOW = 2,
} FlucordOverlayStatus;

// Creates the window if it is not there yet. Nothing is drawn until the first
// update, so an empty overlay is invisible rather than a blank rectangle.
FLUCORD_OVERLAY_EXPORT FlucordOverlayStatus flucord_overlay_show(int32_t x,
                                                                 int32_t y);

// Replaces what the overlay shows. `bgra` is premultiplied, top row first.
FLUCORD_OVERLAY_EXPORT FlucordOverlayStatus
flucord_overlay_update(const uint8_t* bgra, int32_t width, int32_t height);

// Hides the window without destroying it: showing it again is then immediate.
FLUCORD_OVERLAY_EXPORT void flucord_overlay_hide(void);

// Destroys it.
FLUCORD_OVERLAY_EXPORT void flucord_overlay_close(void);

FLUCORD_OVERLAY_EXPORT int32_t flucord_overlay_is_visible(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUCORD_OVERLAY_H_
