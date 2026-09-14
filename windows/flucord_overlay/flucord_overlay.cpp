#include "flucord_overlay.h"

#include <mutex>
#include <vector>

#include <windows.h>

namespace {

std::mutex g_lock;
HWND g_window = nullptr;
int32_t g_x = 24;
int32_t g_y = 24;
bool g_visible = false;

const wchar_t kClassName[] = L"FlucordOverlayWindow";

LRESULT CALLBACK OverlayProc(HWND window, UINT message, WPARAM wParam,
                             LPARAM lParam) {
  // WM_NCHITTEST is answered as transparent as well as the extended style
  // saying so: a window that only relied on the style still swallowed clicks
  // on some compositors.
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  return DefWindowProcW(window, message, wParam, lParam);
}

bool EnsureWindow() {
  if (g_window != nullptr) return true;

  WNDCLASSEXW description{};
  description.cbSize = sizeof(description);
  description.lpfnWndProc = OverlayProc;
  description.hInstance = GetModuleHandleW(nullptr);
  description.lpszClassName = kClassName;
  RegisterClassExW(&description);

  g_window = CreateWindowExW(
      // Layered for the per-pixel alpha, transparent and no-activate so it
      // never takes focus or a click from the game underneath, toolwindow so
      // it stays out of the task bar and alt-tab.
      WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_NOACTIVATE |
          WS_EX_TOOLWINDOW,
      kClassName, L"Flucord overlay", WS_POPUP, g_x, g_y, 1, 1, nullptr,
      nullptr, description.hInstance, nullptr);
  return g_window != nullptr;
}

}  // namespace

extern "C" {

FLUCORD_OVERLAY_EXPORT FlucordOverlayStatus flucord_overlay_show(int32_t x,
                                                                 int32_t y) {
  std::lock_guard<std::mutex> guard(g_lock);
  g_x = x;
  g_y = y;
  if (!EnsureWindow()) return FLUCORD_OVERLAY_ERROR_WINDOW;
  ShowWindow(g_window, SW_SHOWNOACTIVATE);
  g_visible = true;
  return FLUCORD_OVERLAY_OK;
}

FLUCORD_OVERLAY_EXPORT FlucordOverlayStatus
flucord_overlay_update(const uint8_t* bgra, int32_t width, int32_t height) {
  if (bgra == nullptr || width <= 0 || height <= 0) {
    return FLUCORD_OVERLAY_ERROR_STATE;
  }
  std::lock_guard<std::mutex> guard(g_lock);
  if (!EnsureWindow()) return FLUCORD_OVERLAY_ERROR_WINDOW;

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = width;
  // Negative: the rows arrive top first, and a positive height would draw the
  // overlay upside down.
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  void* pixels = nullptr;
  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP bitmap =
      CreateDIBSection(memory, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  FlucordOverlayStatus status = FLUCORD_OVERLAY_ERROR_WINDOW;
  if (bitmap != nullptr && pixels != nullptr) {
    memcpy(pixels, bgra, static_cast<size_t>(width) * height * 4);
    HGDIOBJ previous = SelectObject(memory, bitmap);

    POINT origin{g_x, g_y};
    SIZE size{width, height};
    POINT source{0, 0};
    BLENDFUNCTION blend{};
    blend.BlendOp = AC_SRC_OVER;
    blend.SourceConstantAlpha = 255;
    blend.AlphaFormat = AC_SRC_ALPHA;

    if (UpdateLayeredWindow(g_window, screen, &origin, &size, memory, &source,
                            0, &blend, ULW_ALPHA)) {
      status = FLUCORD_OVERLAY_OK;
    }
    SelectObject(memory, previous);
  }
  if (bitmap != nullptr) DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return status;
}

FLUCORD_OVERLAY_EXPORT void flucord_overlay_hide(void) {
  std::lock_guard<std::mutex> guard(g_lock);
  if (g_window != nullptr) ShowWindow(g_window, SW_HIDE);
  g_visible = false;
}

FLUCORD_OVERLAY_EXPORT void flucord_overlay_close(void) {
  std::lock_guard<std::mutex> guard(g_lock);
  if (g_window != nullptr) DestroyWindow(g_window);
  g_window = nullptr;
  g_visible = false;
}

FLUCORD_OVERLAY_EXPORT int32_t flucord_overlay_is_visible(void) {
  return g_visible ? 1 : 0;
}

}  // extern "C"
