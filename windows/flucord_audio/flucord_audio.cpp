#include "flucord_audio.h"

#include <atomic>
#include <thread>
#include <vector>

#include <windows.h>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#pragma comment(lib, "ole32.lib")

using Microsoft::WRL::ComPtr;

struct FlucordAudioCapture {
  FlucordAudioCallback callback = nullptr;
  void* user_data = nullptr;
  std::thread worker;
  std::atomic<bool> running{false};
};

namespace {

// Float samples are what a shared-mode endpoint almost always hands back, and
// the transport wants 16-bit. Clamped rather than wrapped: a sample past full
// scale is loud, and wrapping turns loud into a click.
int16_t ToPcm16(float value) {
  const float scaled = value * 32767.0f;
  if (scaled > 32767.0f) return 32767;
  if (scaled < -32768.0f) return -32768;
  return static_cast<int16_t>(scaled);
}

void CaptureLoop(FlucordAudioCapture* state,
                 ComPtr<IAudioClient> client,
                 ComPtr<IAudioCaptureClient> capture,
                 WAVEFORMATEX* format) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const int32_t channels = format->nChannels;
  const int32_t rate = format->nSamplesPerSec;
  const bool is_float =
      format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
      (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
       reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format)->SubFormat ==
           KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
  std::vector<int16_t> pcm;

  client->Start();
  while (state->running.load()) {
    UINT32 available = 0;
    if (FAILED(capture->GetNextPacketSize(&available)) || available == 0) {
      // Nothing playing produces no packet at all, which is silence rather
      // than an end: a loop that gave up here would stop the moment the game
      // did.
      Sleep(5);
      continue;
    }
    BYTE* data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) {
      continue;
    }
    if (frames > 0 && state->callback != nullptr) {
      pcm.resize(static_cast<size_t>(frames) * channels);
      if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0) {
        std::fill(pcm.begin(), pcm.end(), static_cast<int16_t>(0));
      } else if (is_float) {
        const auto* source = reinterpret_cast<const float*>(data);
        for (size_t index = 0; index < pcm.size(); ++index) {
          pcm[index] = ToPcm16(source[index]);
        }
      } else {
        memcpy(pcm.data(), data, pcm.size() * sizeof(int16_t));
      }
      state->callback(state->user_data, pcm.data(),
                      static_cast<int32_t>(frames), channels, rate);
    }
    capture->ReleaseBuffer(frames);
  }
  client->Stop();
  CoTaskMemFree(format);
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
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);

  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }
  ComPtr<IMMDevice> device;
  // The render endpoint, opened for capture: that is what loopback is.
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }
  ComPtr<IAudioClient> client;
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                              &client))) {
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }
  WAVEFORMATEX* format = nullptr;
  if (FAILED(client->GetMixFormat(&format)) || format == nullptr) {
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }
  if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                AUDCLNT_STREAMFLAGS_LOOPBACK, 10000000, 0,
                                format, nullptr))) {
    CoTaskMemFree(format);
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }
  ComPtr<IAudioCaptureClient> capture;
  if (FAILED(client->GetService(IID_PPV_ARGS(&capture)))) {
    CoTaskMemFree(format);
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }

  auto state = new FlucordAudioCapture();
  state->callback = callback;
  state->user_data = user_data;
  state->running.store(true);
  state->worker = std::thread(CaptureLoop, state, client, capture, format);
  *out_capture = state;
  return FLUCORD_AUDIO_OK;
}

FLUCORD_AUDIO_EXPORT void flucord_audio_close(FlucordAudioCapture* capture) {
  if (capture == nullptr) return;
  capture->running.store(false);
  if (capture->worker.joinable()) capture->worker.join();
  delete capture;
}

}  // extern "C"
