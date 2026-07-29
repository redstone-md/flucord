// A system-wide keyboard hook, so a keybind reaches the client while another
// window has focus.
//
// Not RegisterHotKey: that delivers WM_HOTKEY to a thread's message queue, and
// the Dart isolate has no Windows message loop to drain one from. A low-level
// hook needs a loop of its own either way, so this owns a thread that installs
// WH_KEYBOARD_LL and pumps it.
//
// The hook reports; it never swallows. A global binding that ate the key would
// take it from whatever the user was actually typing into.

#ifndef FLUCORD_HOTKEYS_H_
#define FLUCORD_HOTKEYS_H_

#include <stdint.h>

#if defined(_WIN32)
#define FLUCORD_HOTKEYS_EXPORT __declspec(dllexport)
#else
#define FLUCORD_HOTKEYS_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  FLUCORD_HOTKEYS_OK = 0,
  FLUCORD_HOTKEYS_ERROR_STATE = 1,
  FLUCORD_HOTKEYS_ERROR_HOOK = 2,
} FlucordHotkeysStatus;

// One key event, as the system saw it.
//
// `modifiers` is a bit set: 1 control, 2 shift, 4 alt, 8 meta. Read at the
// moment of the event rather than tracked in Dart, because a modifier pressed
// while another window had focus never reached this process at all.
typedef void (*FlucordHotkeysCallback)(void* user_data,
                                       int32_t virtual_key,
                                       int32_t modifiers,
                                       int32_t is_down);

// Installs the hook and starts pumping. Safe to call twice; the second is a
// no-op that answers OK.
FLUCORD_HOTKEYS_EXPORT FlucordHotkeysStatus
flucord_hotkeys_start(FlucordHotkeysCallback callback, void* user_data);

// Removes the hook and stops the thread. Safe to call when not started.
FLUCORD_HOTKEYS_EXPORT void flucord_hotkeys_stop(void);

// Whether the hook is installed right now.
FLUCORD_HOTKEYS_EXPORT int32_t flucord_hotkeys_is_running(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUCORD_HOTKEYS_H_
