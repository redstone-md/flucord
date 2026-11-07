// Windows.Graphics.Capture through C++/WinRT, kept to this file so the rest
// of the module needs no WinRT headers.
#ifndef NOMINMAX
#define NOMINMAX
#endif

// Classic COM support in C++/WinRT needs IUnknown declared first.
#include <unknwn.h>

#include "window_capture.h"

#include <d3d11_4.h>
#include <dxgi.h>
#include <inspectable.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.h>

#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <algorithm>
#include <string>

#pragma comment(lib, "runtimeobject.lib")

namespace flucord_video {

namespace {

namespace capture = winrt::Windows::Graphics::Capture;
namespace direct3d = winrt::Windows::Graphics::DirectX::Direct3D11;
using Microsoft::WRL::ComPtr;

constexpr auto kPixelFormat =
    winrt::Windows::Graphics::DirectX::DirectXPixelFormat::
        B8G8R8A8UIntNormalized;

// One buffer the capture draws into while this thread converts the other.
constexpr int32_t kBuffers = 2;

HRESULT ToHresult(const winrt::hresult_error& error) {
  return static_cast<HRESULT>(error.code());
}

// A refusal the capture carries on after, written where a debugger sees it.
void NoteRefusal(const wchar_t* what, const winrt::hresult_error& error) {
  const std::wstring line = std::wstring(L"flucord_video: ") + what + L": " +
                            std::wstring(error.message()) + L"\n";
  OutputDebugStringW(line.c_str());
}

}  // namespace

struct WindowCapture::Session {
  direct3d::IDirect3DDevice device{nullptr};
  capture::GraphicsCaptureItem item{nullptr};
  capture::Direct3D11CaptureFramePool pool{nullptr};
  capture::GraphicsCaptureSession session{nullptr};

  // The picture handed out by Next, held until ReleaseFrame: closing a frame
  // gives its buffer back to the pool, which draws into it again.
  capture::Direct3D11CaptureFrame current{nullptr};

  // The size the pool draws at. A window that changed size is noted here,
  // and the pool is rebuilt once the picture in hand is released.
  winrt::Windows::Graphics::SizeInt32 size{};
  bool resize_pending = false;
};

bool WindowCapture::IsSupported() {
  try {
    // CreateForWindow came with Windows 10 version 1903, which is contract 8.
    return winrt::Windows::Foundation::Metadata::ApiInformation::
               IsApiContractPresent(L"Windows.Foundation.UniversalApiContract",
                                    8) &&
           capture::GraphicsCaptureSession::IsSupported();
  } catch (...) {
    return false;
  }
}

WindowCapture::WindowCapture(HWND window) : window_(window) {}

WindowCapture::~WindowCapture() { Stop(); }

HRESULT WindowCapture::Start(ID3D11Device* device) {
  Stop();
  if (!IsWindow(window_)) return HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE);
  try {
    auto session = std::make_unique<Session>();

    // The capture copies into the pool's buffers from threads of its own, on
    // this device: the device is guarded against two users at once.
    ComPtr<ID3D11DeviceContext> context;
    device->GetImmediateContext(&context);
    ComPtr<ID3D11Multithread> multithread;
    if (context && SUCCEEDED(context.As(&multithread))) {
      multithread->SetMultithreadProtected(TRUE);
    }

    ComPtr<IDXGIDevice> dxgi;
    HRESULT hr = device->QueryInterface(IID_PPV_ARGS(&dxgi));
    if (FAILED(hr)) return hr;
    winrt::com_ptr<::IInspectable> inspectable;
    hr = CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(), inspectable.put());
    if (FAILED(hr)) return hr;
    session->device = inspectable.as<direct3d::IDirect3DDevice>();

    auto interop = winrt::get_activation_factory<capture::GraphicsCaptureItem,
                                                 IGraphicsCaptureItemInterop>();
    hr = interop->CreateForWindow(
        window_, __uuidof(ABI::Windows::Graphics::Capture::IGraphicsCaptureItem),
        winrt::put_abi(session->item));
    if (FAILED(hr)) return hr;

    session->size = session->item.Size();
    session->pool = capture::Direct3D11CaptureFramePool::CreateFreeThreaded(
        session->device, kPixelFormat, kBuffers, session->size);
    session->session = session->pool.CreateCaptureSession(session->item);
    // Windows 11 lets an application drop the yellow frame it draws around a
    // captured window; older versions refuse, and keep it.
    try {
      session->session.IsBorderRequired(false);
    } catch (const winrt::hresult_error& error) {
      NoteRefusal(L"capture border kept", error);
    }
    session->session.StartCapture();
    session_ = std::move(session);
    return S_OK;
  } catch (const winrt::hresult_error& error) {
    return ToHresult(error);
  } catch (...) {
    return E_FAIL;
  }
}

WindowCapture::Grab WindowCapture::Next(ComPtr<ID3D11Texture2D>* texture,
                                        RECT* visible,
                                        HRESULT* error) {
  *error = S_OK;
  if (!session_) {
    *error = E_UNEXPECTED;
    return Grab::kFailed;
  }
  // The handle stops being a window the moment the window is destroyed.
  if (!IsWindow(window_)) return Grab::kClosed;
  ReleaseFrame();
  try {
    // Only the newest picture is wanted; older ones go back to the pool.
    capture::Direct3D11CaptureFrame latest{nullptr};
    for (auto frame = session_->pool.TryGetNextFrame(); frame;
         frame = session_->pool.TryGetNextFrame()) {
      if (latest) latest.Close();
      latest = frame;
    }
    if (!latest) return Grab::kUnchanged;

    const auto content = latest.ContentSize();
    if (content.Width <= 0 || content.Height <= 0) {
      latest.Close();
      return Grab::kUnchanged;
    }
    if (content.Width != session_->size.Width ||
        content.Height != session_->size.Height) {
      session_->size = content;
      session_->resize_pending = true;
    }

    auto access = latest.Surface()
                      .as<::Windows::Graphics::DirectX::Direct3D11::
                              IDirect3DDxgiInterfaceAccess>();
    ComPtr<ID3D11Texture2D> picture;
    const HRESULT hr = access->GetInterface(IID_PPV_ARGS(&picture));
    if (FAILED(hr)) {
      latest.Close();
      *error = hr;
      return Grab::kFailed;
    }
    D3D11_TEXTURE2D_DESC desc{};
    picture->GetDesc(&desc);
    *visible = RECT{0, 0,
                    std::min<LONG>(content.Width, static_cast<LONG>(desc.Width)),
                    std::min<LONG>(content.Height,
                                   static_cast<LONG>(desc.Height))};
    *texture = picture;
    session_->current = latest;
    return Grab::kFrame;
  } catch (const winrt::hresult_error& failure) {
    *error = ToHresult(failure);
    return Grab::kFailed;
  } catch (...) {
    *error = E_FAIL;
    return Grab::kFailed;
  }
}

void WindowCapture::ReleaseFrame() {
  if (!session_) return;
  try {
    if (session_->current) {
      session_->current.Close();
      session_->current = nullptr;
    }
    if (session_->resize_pending) {
      session_->resize_pending = false;
      session_->pool.Recreate(session_->device, kPixelFormat, kBuffers,
                              session_->size);
    }
  } catch (const winrt::hresult_error& error) {
    // A pool that would not rebuild keeps its old size: the picture is
    // scaled from what it delivers, and the next poll says if it failed.
    NoteRefusal(L"frame pool kept its size", error);
  }
}

void WindowCapture::Stop() {
  if (!session_) return;
  try {
    if (session_->current) session_->current.Close();
    if (session_->session) session_->session.Close();
    if (session_->pool) session_->pool.Close();
  } catch (const winrt::hresult_error& error) {
    // Dropping the last reference below closes whatever refused.
    NoteRefusal(L"capture close refused", error);
  }
  session_.reset();
}

}  // namespace flucord_video
