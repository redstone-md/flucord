#include "flucord_audio.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <future>
#include <thread>

#include <windows.h>

#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "mmdevapi.lib")

using Microsoft::WRL::ComPtr;

struct FlucordAudioCapture {
  FlucordAudioCallback callback = nullptr;
  void* user_data = nullptr;
  std::thread worker;
  std::atomic<bool> running{false};
  std::atomic<bool> excludes_own_process{false};
};

namespace {

// What the worker opened: the client, its capture service, the format the
// packets come in, and the event the client signals when one is ready (the
// process path only; the device path polls).
struct Endpoint {
  ComPtr<IAudioClient> client;
  ComPtr<IAudioCaptureClient> capture;
  WAVEFORMATEX* format = nullptr;
  HANDLE ready = nullptr;
  bool excludes_own_process = false;
};

// Float samples are what a shared-mode endpoint almost always hands back, and
// the transport wants 16-bit. Clamped rather than wrapped: a sample past full
// scale is loud, and wrapping turns loud into a click.
int16_t ToPcm16(float value) {
  const float scaled = value * 32767.0f;
  if (scaled > 32767.0f) return 32767;
  if (scaled < -32768.0f) return -32768;
  return static_cast<int16_t>(scaled);
}

// Waits for ActivateAudioInterfaceAsync, which answers on a thread of its
// own. Free-threaded so the answer needs no apartment to be marshalled into.
class Activation final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          Microsoft::WRL::FtmBase,
          IActivateAudioInterfaceCompletionHandler> {
 public:
  Activation() : done_(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
  ~Activation() override {
    if (done_ != nullptr) CloseHandle(done_);
  }

  STDMETHOD(ActivateCompleted)
  (IActivateAudioInterfaceAsyncOperation* operation) override {
    HRESULT result = E_FAIL;
    ComPtr<IUnknown> unknown;
    if (SUCCEEDED(operation->GetActivateResult(&result, &unknown)) &&
        SUCCEEDED(result) && unknown) {
      unknown.As(&client_);
    }
    if (done_ != nullptr) SetEvent(done_);
    return S_OK;
  }

  ComPtr<IAudioClient> Wait() {
    if (done_ == nullptr || WaitForSingleObject(done_, 5000) != WAIT_OBJECT_0) {
      return nullptr;
    }
    return client_;
  }

 private:
  HANDLE done_;
  ComPtr<IAudioClient> client_;
};

// Everything the machine plays except what this process plays.
//
// The room's voices come out of this process: a viewer who is also in the
// room would hear themselves come back through the share otherwise. Discord's
// own client leaves itself out the same way. Windows 10 build 20348 and later;
// an older build fails here and the caller falls back to the whole endpoint.
bool OpenProcessLoopback(Endpoint* out) {
  AUDIOCLIENT_ACTIVATION_PARAMS params = {};
  params.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
  params.ProcessLoopbackParams.ProcessLoopbackMode =
      PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE;
  params.ProcessLoopbackParams.TargetProcessId = GetCurrentProcessId();
  PROPVARIANT activate = {};
  activate.vt = VT_BLOB;
  activate.blob.cbSize = sizeof(params);
  activate.blob.pBlobData = reinterpret_cast<BYTE*>(&params);

  auto handler = Microsoft::WRL::Make<Activation>();
  ComPtr<IActivateAudioInterfaceAsyncOperation> operation;
  if (FAILED(ActivateAudioInterfaceAsync(
          VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
          &activate, handler.Get(), &operation))) {
    return false;
  }
  ComPtr<IAudioClient> client = handler->Wait();
  if (!client) return false;

  // The virtual device has no mix format of its own; it converts to whatever
  // is asked, so what the transport wants is asked for directly.
  auto* format =
      static_cast<WAVEFORMATEX*>(CoTaskMemAlloc(sizeof(WAVEFORMATEX)));
  if (format == nullptr) return false;
  *format = {};
  format->wFormatTag = WAVE_FORMAT_PCM;
  format->nChannels = 2;
  format->nSamplesPerSec = 48000;
  format->wBitsPerSample = 16;
  format->nBlockAlign = format->nChannels * format->wBitsPerSample / 8;
  format->nAvgBytesPerSec = format->nSamplesPerSec * format->nBlockAlign;

  HANDLE ready = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  ComPtr<IAudioCaptureClient> capture;
  if (ready == nullptr ||
      FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                AUDCLNT_STREAMFLAGS_LOOPBACK |
                                    AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                                    AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
                                0, 0, format, nullptr)) ||
      FAILED(client->SetEventHandle(ready)) ||
      FAILED(client->GetService(IID_PPV_ARGS(&capture)))) {
    if (ready != nullptr) CloseHandle(ready);
    CoTaskMemFree(format);
    return false;
  }
  out->client = client;
  out->capture = capture;
  out->format = format;
  out->ready = ready;
  out->excludes_own_process = true;
  return true;
}

// The render endpoint opened for capture: everything the machine plays, this
// process included.
bool OpenDeviceLoopback(Endpoint* out) {
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return false;
  }
  ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
    return false;
  }
  ComPtr<IAudioClient> client;
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                              &client))) {
    return false;
  }
  WAVEFORMATEX* format = nullptr;
  if (FAILED(client->GetMixFormat(&format)) || format == nullptr) {
    return false;
  }
  ComPtr<IAudioCaptureClient> capture;
  if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                AUDCLNT_STREAMFLAGS_LOOPBACK, 10000000, 0,
                                format, nullptr)) ||
      FAILED(client->GetService(IID_PPV_ARGS(&capture)))) {
    CoTaskMemFree(format);
    return false;
  }
  out->client = client;
  out->capture = capture;
  out->format = format;
  return true;
}

void Pump(FlucordAudioCapture* state, const Endpoint& endpoint) {
  const WAVEFORMATEX* format = endpoint.format;
  const int32_t channels = format->nChannels;
  const int32_t rate = format->nSamplesPerSec;
  const bool is_float =
      format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
      (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
       reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format)->SubFormat ==
           KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);

  endpoint.client->Start();
  while (state->running.load()) {
    UINT32 available = 0;
    if (FAILED(endpoint.capture->GetNextPacketSize(&available)) ||
        available == 0) {
      // Nothing playing produces no packet at all, which is silence rather
      // than an end: a loop that gave up here would stop the moment the game
      // did.
      if (endpoint.ready != nullptr) {
        WaitForSingleObject(endpoint.ready, 20);
      } else {
        Sleep(5);
      }
      continue;
    }
    BYTE* data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    if (FAILED(endpoint.capture->GetBuffer(&data, &frames, &flags, nullptr,
                                           nullptr))) {
      continue;
    }
    if (frames > 0 && state->callback != nullptr) {
      // Handed over, not lent: the callback is delivered to Dart after this
      // thread has moved on, so the samples live in a buffer of their own
      // until flucord_audio_release.
      const size_t count = static_cast<size_t>(frames) * channels;
      auto* pcm = static_cast<int16_t*>(malloc(count * sizeof(int16_t)));
      if (pcm != nullptr) {
        if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0) {
          memset(pcm, 0, count * sizeof(int16_t));
        } else if (is_float) {
          const auto* source = reinterpret_cast<const float*>(data);
          for (size_t index = 0; index < count; ++index) {
            pcm[index] = ToPcm16(source[index]);
          }
        } else {
          memcpy(pcm, data, count * sizeof(int16_t));
        }
        state->callback(state->user_data, pcm, static_cast<int32_t>(frames),
                        channels, rate);
      }
    }
    endpoint.capture->ReleaseBuffer(frames);
  }
  endpoint.client->Stop();
}

// The whole life of the endpoint on one thread: opened, pumped and closed
// where it was made, so COM never sees it from two apartments.
void CaptureLoop(FlucordAudioCapture* state, std::promise<bool> opened) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    Endpoint endpoint;
    const bool open =
        OpenProcessLoopback(&endpoint) || OpenDeviceLoopback(&endpoint);
    state->excludes_own_process.store(endpoint.excludes_own_process);
    opened.set_value(open);
    if (open) Pump(state, endpoint);
    if (endpoint.ready != nullptr) CloseHandle(endpoint.ready);
    CoTaskMemFree(endpoint.format);
  }
  CoUninitialize();
}

}  // namespace

extern "C" {

FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_open_loopback(FlucordAudioCallback callback,
                            void* user_data,
                            FlucordAudioCapture** out_capture) {
  if (callback == nullptr || out_capture == nullptr) {
    return FLUCORD_AUDIO_ERROR_STATE;
  }
  auto state = new FlucordAudioCapture();
  state->callback = callback;
  state->user_data = user_data;
  state->running.store(true);
  std::promise<bool> opened;
  std::future<bool> open = opened.get_future();
  state->worker = std::thread(CaptureLoop, state, std::move(opened));
  if (!open.get()) {
    state->worker.join();
    delete state;
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }
  *out_capture = state;
  return FLUCORD_AUDIO_OK;
}

FLUCORD_AUDIO_EXPORT int32_t
flucord_audio_excludes_own_process(FlucordAudioCapture* capture) {
  return capture != nullptr && capture->excludes_own_process.load() ? 1 : 0;
}

FLUCORD_AUDIO_EXPORT void flucord_audio_release(int16_t* frames) {
  free(frames);
}

FLUCORD_AUDIO_EXPORT void flucord_audio_close(FlucordAudioCapture* capture) {
  if (capture == nullptr) return;
  capture->running.store(false);
  if (capture->worker.joinable()) capture->worker.join();
  delete capture;
}

}  // extern "C"
