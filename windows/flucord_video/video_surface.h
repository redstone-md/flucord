// A decoded picture the interface draws without it passing through Dart.
//
// One shared Direct3D texture: a decoder draws each picture into it, and
// Flutter's engine opens it by its handle and draws it as a texture widget
// (ADR-0009).

#ifndef FLUCORD_VIDEO_SURFACE_H_
#define FLUCORD_VIDEO_SURFACE_H_

#include <windows.h>

#include <d3d11.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdint>
#include <mutex>

#include "flucord_video.h"

// Creates a Direct3D device that more than one thread may use: a decoder's
// transform reaches it from its own calls while the decode thread draws on
// it. A null adapter is the system default. `flags` adds to BGRA support.
HRESULT CreateSharedDevice(IDXGIAdapter* adapter,
                           UINT flags,
                           Microsoft::WRL::ComPtr<ID3D11Device>* device,
                           Microsoft::WRL::ComPtr<ID3D11DeviceContext>* context);

struct FlucordVideoSurface {
 public:
  // Creates a surface on the adapter with this LUID. It has to be the one
  // Flutter renders on: a texture shared by handle only opens on the adapter
  // that made it. The caller holds the one reference.
  static HRESULT Create(const LUID& adapter,
                        FlucordVideoSurfaceCallback on_picture,
                        void* context,
                        FlucordVideoSurface** out);

  void AddRef();
  void Release();

  // The device pictures are drawn with. A decoder decodes on it too, so a
  // picture never leaves the adapter it is shown on.
  ID3D11Device* device() const { return device_.Get(); }
  ID3D11DeviceContext* context() const { return context_.Get(); }

  // S_OK when the device can decode video, otherwise why it cannot. A
  // decoder on a surface without video support decodes on the CPU and
  // uploads its pictures instead.
  HRESULT video_status() const { return video_status_; }

  // Shows `picture`, a BGRA texture made on device(). Decode thread only.
  HRESULT Show(ID3D11Texture2D* picture);

  // Shows BGRA rows from memory, `width` by `height`, packed. Decode thread
  // only.
  HRESULT Upload(const uint8_t* bgra, int32_t width, int32_t height);

  // The shared handle and size of the picture shown, or false before the
  // first one. Any thread: the engine asks from its raster thread.
  bool Describe(HANDLE* handle, int32_t* width, int32_t* height);

  // Stops the picture callback. Once this returns, the callback is not
  // running and is never called again.
  void Detach();

 private:
  // A texture the engine can open by its handle.
  struct Shared {
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
    HANDLE handle = nullptr;
    int32_t width = 0;
    int32_t height = 0;
  };

  FlucordVideoSurface() = default;

  // The texture the next picture is drawn into: the one shown, or a new one
  // when the size changed.
  HRESULT Target(int32_t width, int32_t height);

  // Waits for the GPU to finish the picture, then makes it the one shown and
  // tells the callback.
  HRESULT Present();

  std::atomic<ULONG> refs_{1};
  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<ID3D11Query> finished_;
  HRESULT video_status_ = E_PENDING;

  // The decode thread's own: what it draws into.
  Shared drawing_;

  std::mutex lock_;
  // What the engine is given. The texture shown before a resize stays alive
  // one more picture, so a handle the engine was just handed is never one
  // that has already been freed.
  Shared shown_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> previous_;
  FlucordVideoSurfaceCallback on_picture_ = nullptr;
  void* on_picture_context_ = nullptr;
};

#endif  // FLUCORD_VIDEO_SURFACE_H_
