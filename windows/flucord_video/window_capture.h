#pragma once

#include <windows.h>

#include <d3d11.h>
#include <wrl/client.h>

#include <memory>

namespace flucord_video {

// One top-level window, captured through Windows.Graphics.Capture.
//
// Desktop Duplication can only hand over a whole display, with whatever
// covers the window drawn over it. This capture sends the window alone,
// follows it when it moves to another display, and grows or shrinks with it.
//
// Everything is made and used on the capture thread, and the thread polls:
// there is no frame callback, so nothing runs on a thread of the platform's.
// The WinRT types stay inside window_capture.cpp.
class WindowCapture {
 public:
  // What one poll found.
  enum class Grab {
    // A new picture, in the texture handed back, until ReleaseFrame.
    kFrame,
    // Nothing new since the last poll. A still window draws nothing.
    kUnchanged,
    // The window is gone.
    kClosed,
    // The capture itself failed; the HRESULT says why.
    kFailed,
  };

  // Whether this Windows can capture one window (10 version 1903 or later).
  static bool IsSupported();

  explicit WindowCapture(HWND window);
  ~WindowCapture();
  WindowCapture(const WindowCapture&) = delete;
  WindowCapture& operator=(const WindowCapture&) = delete;

  // Starts capturing on `device`, which must have been made with
  // D3D11_CREATE_DEVICE_BGRA_SUPPORT. Call on the capture thread.
  HRESULT Start(ID3D11Device* device);

  // Takes the newest picture, if any. On kFrame, `texture` is BGRA and
  // `visible` is the part of it the window fills, from its top-left corner:
  // after a resize the texture keeps its old size for one picture.
  Grab Next(Microsoft::WRL::ComPtr<ID3D11Texture2D>* texture,
            RECT* visible,
            HRESULT* error);

  // Hands the last picture back to the capture. Safe when there is none.
  void ReleaseFrame();

  // Stops the capture and drops everything it made. Call on the capture
  // thread. Safe to call twice.
  void Stop();

 private:
  struct Session;

  HWND window_;
  std::unique_ptr<Session> session_;
};

}  // namespace flucord_video
