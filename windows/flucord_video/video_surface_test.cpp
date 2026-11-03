// Draws pictures on a surface and opens them the way Flutter's engine does:
// by the shared handle, from a device of its own.

#include "video_surface.h"

#include <dxgi.h>

#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

int Fail(const char* what, HRESULT hr = S_OK) {
  std::cerr << what;
  if (hr != S_OK) std::cerr << " (0x" << std::hex << hr << ")";
  std::cerr << "\n";
  return 1;
}

std::vector<uint8_t> Picture(int32_t width, int32_t height, uint8_t seed) {
  std::vector<uint8_t> bgra(static_cast<size_t>(width) * height * 4);
  for (size_t index = 0; index < bgra.size(); ++index) {
    bgra[index] = static_cast<uint8_t>(seed + index);
  }
  return bgra;
}

// Reads what a second device sees through the handle.
HRESULT ReadShared(ID3D11Device* device,
                   ID3D11DeviceContext* context,
                   HANDLE handle,
                   std::vector<uint8_t>* out) {
  ComPtr<ID3D11Texture2D> shared;
  HRESULT hr = device->OpenSharedResource(handle, IID_PPV_ARGS(&shared));
  if (FAILED(hr)) return hr;
  D3D11_TEXTURE2D_DESC desc{};
  shared->GetDesc(&desc);
  desc.Usage = D3D11_USAGE_STAGING;
  desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  desc.MiscFlags = 0;
  ComPtr<ID3D11Texture2D> staging;
  hr = device->CreateTexture2D(&desc, nullptr, &staging);
  if (FAILED(hr)) return hr;
  context->CopyResource(staging.Get(), shared.Get());
  D3D11_MAPPED_SUBRESOURCE mapped{};
  hr = context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) return hr;
  const size_t row = static_cast<size_t>(desc.Width) * 4;
  out->resize(row * desc.Height);
  for (UINT y = 0; y < desc.Height; ++y) {
    memcpy(out->data() + y * row,
           static_cast<const uint8_t*>(mapped.pData) + y * mapped.RowPitch,
           row);
  }
  context->Unmap(staging.Get(), 0);
  return S_OK;
}

}  // namespace

int main() {
  ComPtr<IDXGIFactory1> factory;
  ComPtr<IDXGIAdapter1> adapter;
  DXGI_ADAPTER_DESC1 desc{};
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) ||
      FAILED(factory->EnumAdapters1(0, &adapter)) ||
      FAILED(adapter->GetDesc1(&desc))) {
    return Fail("no graphics adapter");
  }

  int pictures = 0;
  FlucordVideoSurface* surface = nullptr;
  HRESULT hr = FlucordVideoSurface::Create(
      desc.AdapterLuid,
      [](void* context) { ++*static_cast<int*>(context); }, &pictures,
      &surface);
  if (FAILED(hr)) return Fail("the surface did not open", hr);

  HANDLE handle = nullptr;
  int32_t width = 0;
  int32_t height = 0;
  if (surface->Describe(&handle, &width, &height)) {
    return Fail("a surface described a picture before it had one");
  }

  // The engine's side: another device on the same adapter.
  ComPtr<ID3D11Device> engine;
  ComPtr<ID3D11DeviceContext> engine_context;
  hr = CreateSharedDevice(adapter.Get(), 0, &engine, &engine_context);
  if (FAILED(hr)) return Fail("the engine's device did not open", hr);

  const std::vector<uint8_t> first = Picture(4, 2, 1);
  hr = surface->Upload(first.data(), 4, 2);
  if (FAILED(hr)) return Fail("the first picture was not shown", hr);
  if (pictures != 1) return Fail("the first picture was not announced");
  if (!surface->Describe(&handle, &width, &height) || width != 4 ||
      height != 2) {
    return Fail("the first picture was described wrong");
  }
  std::vector<uint8_t> seen;
  hr = ReadShared(engine.Get(), engine_context.Get(), handle, &seen);
  if (FAILED(hr)) return Fail("the shared picture did not open", hr);
  if (seen != first) return Fail("the engine saw another picture");

  // A new size is a new texture, and the engine is handed its handle.
  const std::vector<uint8_t> second = Picture(8, 4, 7);
  hr = surface->Upload(second.data(), 8, 4);
  if (FAILED(hr)) return Fail("the resized picture was not shown", hr);
  HANDLE resized = nullptr;
  if (!surface->Describe(&resized, &width, &height) || width != 8 ||
      height != 4 || resized == handle) {
    return Fail("the resized picture was described wrong");
  }
  hr = ReadShared(engine.Get(), engine_context.Get(), resized, &seen);
  if (FAILED(hr) || seen != second) {
    return Fail("the engine did not see the resized picture", hr);
  }

  // Detached, the surface draws on and tells nobody.
  surface->Detach();
  hr = surface->Upload(second.data(), 8, 4);
  if (FAILED(hr)) return Fail("a detached surface stopped drawing", hr);
  if (pictures != 2) return Fail("a detached surface still announced");

  surface->Release();
  return 0;
}
