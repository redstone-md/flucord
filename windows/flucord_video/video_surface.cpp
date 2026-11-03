#include "video_surface.h"

#include <d3d11_4.h>
#include <dxgi.h>

#include <chrono>
#include <thread>

using Microsoft::WRL::ComPtr;

namespace {

// How long a picture may take the GPU to finish before the surface gives up
// on it. A frame lasts 16 ms at 60 a second; a driver that takes longer than
// this is hung, and waiting on it would stall the decode thread for good.
constexpr auto kFinishTimeout = std::chrono::milliseconds(100);

HRESULT FindAdapter(const LUID& luid, ComPtr<IDXGIAdapter1>* out) {
  ComPtr<IDXGIFactory1> factory;
  HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(hr)) return hr;
  ComPtr<IDXGIAdapter1> adapter;
  for (UINT index = 0;
       factory->EnumAdapters1(index, &adapter) != DXGI_ERROR_NOT_FOUND;
       ++index) {
    DXGI_ADAPTER_DESC1 desc{};
    if (SUCCEEDED(adapter->GetDesc1(&desc)) &&
        desc.AdapterLuid.LowPart == luid.LowPart &&
        desc.AdapterLuid.HighPart == luid.HighPart) {
      *out = adapter;
      return S_OK;
    }
    adapter.Reset();
  }
  return DXGI_ERROR_NOT_FOUND;
}

}  // namespace

HRESULT CreateSharedDevice(IDXGIAdapter* adapter,
                           UINT flags,
                           ComPtr<ID3D11Device>* device,
                           ComPtr<ID3D11DeviceContext>* context) {
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                      D3D_FEATURE_LEVEL_11_0,
                                      D3D_FEATURE_LEVEL_10_1};
  ComPtr<ID3D11Device> created;
  ComPtr<ID3D11DeviceContext> immediate;
  // An explicit adapter needs the unknown driver type; the default one is
  // asked for as hardware.
  HRESULT hr = D3D11CreateDevice(
      adapter,
      adapter != nullptr ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE,
      nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT | flags, levels,
      ARRAYSIZE(levels), D3D11_SDK_VERSION, &created, nullptr, &immediate);
  if (FAILED(hr)) return hr;
  ComPtr<ID3D11Multithread> multithread;
  hr = created.As(&multithread);
  if (FAILED(hr)) return hr;
  multithread->SetMultithreadProtected(TRUE);
  *device = created;
  *context = immediate;
  return S_OK;
}

HRESULT FlucordVideoSurface::Create(const LUID& adapter_luid,
                                    FlucordVideoSurfaceCallback on_picture,
                                    void* context,
                                    FlucordVideoSurface** out) {
  ComPtr<IDXGIAdapter1> adapter;
  HRESULT hr = FindAdapter(adapter_luid, &adapter);
  if (FAILED(hr)) return hr;
  auto* surface = new FlucordVideoSurface();
  // Video support is asked for first, so a decoder can decode on this very
  // device. An adapter without it still shows pictures a CPU decode
  // uploads, and video_status says why the decode is not on the GPU.
  surface->video_status_ =
      CreateSharedDevice(adapter.Get(), D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
                         &surface->device_, &surface->context_);
  if (FAILED(surface->video_status_)) {
    hr = CreateSharedDevice(adapter.Get(), 0, &surface->device_,
                            &surface->context_);
  }
  if (SUCCEEDED(hr)) {
    D3D11_QUERY_DESC query{};
    query.Query = D3D11_QUERY_EVENT;
    hr = surface->device_->CreateQuery(&query, &surface->finished_);
  }
  if (FAILED(hr)) {
    surface->Release();
    return hr;
  }
  surface->on_picture_ = on_picture;
  surface->on_picture_context_ = context;
  *out = surface;
  return S_OK;
}

void FlucordVideoSurface::AddRef() {
  refs_.fetch_add(1);
}

void FlucordVideoSurface::Release() {
  if (refs_.fetch_sub(1) == 1) delete this;
}

HRESULT FlucordVideoSurface::Show(ID3D11Texture2D* picture) {
  D3D11_TEXTURE2D_DESC desc{};
  picture->GetDesc(&desc);
  HRESULT hr = Target(static_cast<int32_t>(desc.Width),
                      static_cast<int32_t>(desc.Height));
  if (FAILED(hr)) return hr;
  context_->CopyResource(drawing_.texture.Get(), picture);
  return Present();
}

HRESULT FlucordVideoSurface::Upload(const uint8_t* bgra,
                                    int32_t width,
                                    int32_t height) {
  HRESULT hr = Target(width, height);
  if (FAILED(hr)) return hr;
  context_->UpdateSubresource(drawing_.texture.Get(), 0, nullptr, bgra,
                              static_cast<UINT>(width) * 4, 0);
  return Present();
}

bool FlucordVideoSurface::Describe(HANDLE* handle,
                                   int32_t* width,
                                   int32_t* height) {
  std::lock_guard<std::mutex> guard(lock_);
  if (shown_.handle == nullptr) return false;
  *handle = shown_.handle;
  *width = shown_.width;
  *height = shown_.height;
  return true;
}

void FlucordVideoSurface::Detach() {
  std::lock_guard<std::mutex> guard(lock_);
  on_picture_ = nullptr;
  on_picture_context_ = nullptr;
}

HRESULT FlucordVideoSurface::Target(int32_t width, int32_t height) {
  if (width <= 0 || height <= 0) return E_INVALIDARG;
  if (drawing_.texture && drawing_.width == width &&
      drawing_.height == height) {
    return S_OK;
  }
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = static_cast<UINT>(width);
  desc.Height = static_cast<UINT>(height);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  // A legacy shared handle: the kind the engine's DXGI shared handle
  // texture opens.
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  Shared next;
  HRESULT hr = device_->CreateTexture2D(&desc, nullptr, &next.texture);
  ComPtr<IDXGIResource> resource;
  if (SUCCEEDED(hr)) hr = next.texture.As(&resource);
  if (SUCCEEDED(hr)) hr = resource->GetSharedHandle(&next.handle);
  if (FAILED(hr)) return hr;
  next.width = width;
  next.height = height;
  drawing_ = next;
  return S_OK;
}

HRESULT FlucordVideoSurface::Present() {
  // The engine draws from its own device the moment it is told, so the
  // picture has to be finished on the GPU first, not merely queued.
  context_->End(finished_.Get());
  context_->Flush();
  const auto deadline = std::chrono::steady_clock::now() + kFinishTimeout;
  while (true) {
    BOOL done = FALSE;
    const HRESULT hr =
        context_->GetData(finished_.Get(), &done, sizeof(done), 0);
    if (FAILED(hr)) return hr;
    if (hr == S_OK && done) break;
    if (std::chrono::steady_clock::now() > deadline) {
      return DXGI_ERROR_WAS_STILL_DRAWING;
    }
    std::this_thread::yield();
  }

  std::lock_guard<std::mutex> guard(lock_);
  if (shown_.texture != drawing_.texture) {
    previous_ = shown_.texture;
    shown_ = drawing_;
  }
  // Called under the lock, so Detach cannot return while a call is running.
  // The callback only marks a frame available, which the engine queues
  // without calling back in here.
  if (on_picture_ != nullptr) on_picture_(on_picture_context_);
  return S_OK;
}

extern "C" {

FLUCORD_VIDEO_EXPORT int32_t
flucord_video_surface_create(uint32_t adapter_low,
                             int32_t adapter_high,
                             FlucordVideoSurfaceCallback on_picture,
                             void* context,
                             FlucordVideoSurface** out_surface) {
  if (out_surface == nullptr) return E_POINTER;
  LUID adapter{};
  adapter.LowPart = adapter_low;
  adapter.HighPart = adapter_high;
  return FlucordVideoSurface::Create(adapter, on_picture, context,
                                     out_surface);
}

FLUCORD_VIDEO_EXPORT void flucord_video_surface_detach(
    FlucordVideoSurface* surface) {
  if (surface != nullptr) surface->Detach();
}

FLUCORD_VIDEO_EXPORT void flucord_video_surface_release(
    FlucordVideoSurface* surface) {
  if (surface != nullptr) surface->Release();
}

FLUCORD_VIDEO_EXPORT int32_t
flucord_video_surface_describe(FlucordVideoSurface* surface,
                               void** handle,
                               int32_t* width,
                               int32_t* height) {
  if (surface == nullptr || handle == nullptr || width == nullptr ||
      height == nullptr) {
    return 0;
  }
  HANDLE shared = nullptr;
  if (!surface->Describe(&shared, width, height)) return 0;
  *handle = shared;
  return 1;
}

}  // extern "C"
