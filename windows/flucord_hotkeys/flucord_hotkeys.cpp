#include "flucord_hotkeys.h"

#include <atomic>
#include <mutex>
#include <thread>

#include <windows.h>

namespace {

std::mutex g_lock;
std::thread g_worker;
HHOOK g_hook = nullptr;
DWORD g_thread_id = 0;
std::atomic<bool> g_running{false};
FlucordHotkeysCallback g_callback = nullptr;
void* g_user_data = nullptr;

int32_t CurrentModifiers() {
  int32_t modifiers = 0;
  // GetAsyncKeyState rather than a tracked set: a modifier held down while
  // another application had focus produced no event this process ever saw, so
  // anything tracked here would be wrong exactly when it matters.
  if (GetAsyncKeyState(VK_CONTROL) & 0x8000) modifiers |= 1;
  if (GetAsyncKeyState(VK_SHIFT) & 0x8000) modifiers |= 2;
  if (GetAsyncKeyState(VK_MENU) & 0x8000) modifiers |= 4;
  if ((GetAsyncKeyState(VK_LWIN) & 0x8000) ||
      (GetAsyncKeyState(VK_RWIN) & 0x8000)) {
    modifiers |= 8;
  }
  return modifiers;
}

LRESULT CALLBACK HookProc(int code, WPARAM wParam, LPARAM lParam) {
  if (code == HC_ACTION && g_callback != nullptr) {
    const auto* event = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lParam);
    const bool down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
    const bool up = wParam == WM_KEYUP || wParam == WM_SYSKEYUP;
    // An injected event is another program's synthetic keystroke. Acting on
    // one would let anything on the machine work this client's microphone.
    if ((down || up) && (event->flags & LLKHF_INJECTED) == 0) {
      g_callback(g_user_data, static_cast<int32_t>(event->vkCode),
                 CurrentModifiers(), down ? 1 : 0);
    }
  }
  // Always passed on: a global binding that swallowed the key would take it
  // from whatever the user was typing into.
  return CallNextHookEx(nullptr, code, wParam, lParam);
}

void Pump() {
  g_thread_id = GetCurrentThreadId();
  g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, HookProc, GetModuleHandleW(nullptr),
                             0);
  if (g_hook == nullptr) {
    g_running.store(false);
    return;
  }
  g_running.store(true);

  MSG message;
  // The hook needs a message loop on its own thread: without one the system
  // times the callback out and quietly removes the hook.
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  UnhookWindowsHookEx(g_hook);
  g_hook = nullptr;
  g_running.store(false);
}

}  // namespace

extern "C" {

FLUCORD_HOTKEYS_EXPORT FlucordHotkeysStatus
flucord_hotkeys_start(FlucordHotkeysCallback callback, void* user_data) {
  if (callback == nullptr) return FLUCORD_HOTKEYS_ERROR_STATE;
  std::lock_guard<std::mutex> guard(g_lock);
  if (g_worker.joinable()) return FLUCORD_HOTKEYS_OK;

  g_callback = callback;
  g_user_data = user_data;
  g_worker = std::thread(Pump);

  // The hook either installs within a few scheduler slices or not at all, and
  // the caller has to be told which before it promises anybody a global key.
  for (int attempt = 0; attempt < 100 && !g_running.load(); ++attempt) {
    Sleep(2);
  }
  if (!g_running.load()) {
    if (g_worker.joinable()) g_worker.join();
    g_callback = nullptr;
    return FLUCORD_HOTKEYS_ERROR_HOOK;
  }
  return FLUCORD_HOTKEYS_OK;
}

FLUCORD_HOTKEYS_EXPORT void flucord_hotkeys_stop(void) {
  std::lock_guard<std::mutex> guard(g_lock);
  if (!g_worker.joinable()) return;
  PostThreadMessageW(g_thread_id, WM_QUIT, 0, 0);
  g_worker.join();
  g_callback = nullptr;
  g_user_data = nullptr;
}

FLUCORD_HOTKEYS_EXPORT int32_t flucord_hotkeys_is_running(void) {
  return g_running.load() ? 1 : 0;
}

}  // extern "C"
