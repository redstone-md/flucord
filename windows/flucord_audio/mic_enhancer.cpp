// The microphone enhancer: echo cancellation and automatic gain control,
// through WebRTC Audio Processing, the stages Discord's own client runs.
//
// The `record` package's capture hands the microphone straight from the
// device with no voice DSP, and its echo, gain and suppression flags are
// parsed and dropped on Windows. So the stages run here, on the frames the
// capture already produces. They live in flucord_apm.dll
// (windows/third_party/webrtc_apm), loaded from beside this module when an
// enhancer opens; a missing one fails the open with its own step rather than
// leaving the switches on and doing nothing.
//
// The library works at the pipeline's own 48 kHz in 10 ms chunks, so a 20 ms
// frame is two chunks processed in place: nothing is resampled, nothing is
// held back, and the whole band of the voice is kept. The Windows voice
// capture DMO this replaced worked at 22 kHz at most, and at the 16 kHz it
// ran at it cut every voice down to a telephone's.
//
// The echo stage needs what the room is played on, so that output is looped
// back and handed over, at its own rate and width, before each microphone
// frame. The echo stage finds the delay between the two itself. The output
// is the one the playback picked, by the name its device list shows (the
// endpoint's friendly name, which is what miniaudio lists), or the system
// default until one is picked; a default that moves is followed within a
// second, as playback follows it.
//
// Everything runs on the thread that opens it, the same thread the record
// package's frames arrive on. The loopback needs COM; when the thread has no
// apartment, one is brought up here and taken down on close.

#include "flucord_audio.h"
#include "flucord_apm.h"

#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <vector>
#include <windows.h>

#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "mmdevapi.lib")

using Microsoft::WRL::ComPtr;

namespace {

// The pipeline's rate: VoicePcmFramer refuses any other.
constexpr int kCaptureRate = 48000;

// One chunk of the library's: 10 ms at the pipeline's rate.
constexpr int kCaptureChunk = kCaptureRate / 100;

constexpr wchar_t kApmLibrary[] = L"flucord_apm.dll";

// How often a loopback of the default output checks that it still is one.
constexpr ULONGLONG kDefaultCheckMs = 1000;

// Float samples are what a shared-mode endpoint almost always hands back.
// Clamped rather than wrapped: a sample past full scale is loud, and
// wrapping turns loud into a click.
int16_t ToPcm16(float value) {
  const float scaled = value * 32767.0f;
  if (scaled > 32767.0f) return 32767;
  if (scaled < -32768.0f) return -32768;
  return static_cast<int16_t>(scaled);
}

// The functions of flucord_apm.dll, and the module that holds them.
struct ApmLibrary {
  HMODULE module = nullptr;
  decltype(&flucord_apm_create) create = nullptr;
  decltype(&flucord_apm_process_render) process_render = nullptr;
  decltype(&flucord_apm_process_capture) process_capture = nullptr;
  decltype(&flucord_apm_destroy) destroy = nullptr;
};

// The folder this module was loaded from, with a trailing separator. The
// bundle puts flucord_apm.dll beside it, and so does a build folder a test
// loads this module from.
HRESULT ModuleFolder(std::wstring* out) {
  HMODULE self = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(&ModuleFolder), &self)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = GetModuleFileNameW(self, path.data(),
                                            static_cast<DWORD>(path.size()));
    if (length == 0) return HRESULT_FROM_WIN32(GetLastError());
    if (length < path.size()) {
      path.resize(length);
      break;
    }
    path.resize(path.size() * 2);
  }
  path.resize(path.find_last_of(L"\\/") + 1);
  *out = path;
  return S_OK;
}

template <typename Function>
bool Find(HMODULE module, const char* name, Function* out) {
  *out = reinterpret_cast<Function>(
      reinterpret_cast<void*>(GetProcAddress(module, name)));
  return *out != nullptr;
}

HRESULT LoadApm(ApmLibrary* library) {
  std::wstring path;
  HRESULT hr = ModuleFolder(&path);
  if (FAILED(hr)) return hr;
  path += kApmLibrary;
  library->module = LoadLibraryExW(
      path.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (library->module == nullptr) return HRESULT_FROM_WIN32(GetLastError());
  const HMODULE module = library->module;
  if (!Find(module, "flucord_apm_create", &library->create) ||
      !Find(module, "flucord_apm_process_render", &library->process_render) ||
      !Find(module, "flucord_apm_process_capture",
            &library->process_capture) ||
      !Find(module, "flucord_apm_destroy", &library->destroy)) {
    return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
  }
  return S_OK;
}

// Everything the enhancer holds: the library's processor, and the speaker
// line that feeds its echo stage. Whatever was opened, of a whole open or a
// refused one, is let go of with the state.
struct EnhancerState {
  EnhancerState(bool echo_cancellation, bool automatic_gain_control)
      : echo_cancellation(echo_cancellation),
        automatic_gain_control(automatic_gain_control) {}
  ~EnhancerState();
  EnhancerState(const EnhancerState&) = delete;
  EnhancerState& operator=(const EnhancerState&) = delete;

  const bool echo_cancellation;
  const bool automatic_gain_control;
  bool com_up = false;
  ApmLibrary library;
  FlucordApm* apm = nullptr;

  // The output to loop back, by friendly name; empty follows the default.
  std::wstring speakers_name;
  // The endpoint the open loopback reads, and when the default was last
  // checked against it.
  std::wstring loopback_id;
  ULONGLONG default_checked_at = 0;

  ComPtr<IAudioClient> loopback_client;
  ComPtr<IAudioCaptureClient> loopback_capture;
  WAVEFORMATEX* loopback_format = nullptr;
  bool loopback_float = false;

  // The speaker line as 16-bit samples at its own rate and width, not yet a
  // whole chunk of it.
  std::vector<int16_t> speaker;
};

void CloseLoopback(EnhancerState* state) {
  if (state->loopback_client != nullptr) state->loopback_client->Stop();
  state->loopback_capture.Reset();
  state->loopback_client.Reset();
  CoTaskMemFree(state->loopback_format);
  state->loopback_format = nullptr;
  state->loopback_id.clear();
  state->speaker.clear();
}

EnhancerState::~EnhancerState() {
  CloseLoopback(this);
  if (apm != nullptr) library.destroy(apm);
  if (library.module != nullptr) FreeLibrary(library.module);
  // The apartment this module brought up, if it brought one up.
  if (com_up) CoUninitialize();
}

// Starts the loopback of the default speakers: what the machine is playing,
// which a microphone in front of those speakers hears again. On a refusal,
// [failed_stage] says which step.
HRESULT EndpointId(IMMDevice* device, std::wstring* out) {
  LPWSTR id = nullptr;
  const HRESULT hr = device->GetId(&id);
  if (SUCCEEDED(hr)) *out = id;
  CoTaskMemFree(id);
  return hr;
}

// The active output whose friendly name is [name].
HRESULT FindSpeakers(IMMDeviceEnumerator* enumerator,
                     const std::wstring& name,
                     ComPtr<IMMDevice>* out) {
  ComPtr<IMMDeviceCollection> outputs;
  HRESULT hr = enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE,
                                              &outputs);
  UINT count = 0;
  if (SUCCEEDED(hr)) hr = outputs->GetCount(&count);
  for (UINT i = 0; SUCCEEDED(hr) && i < count; i++) {
    ComPtr<IMMDevice> device;
    ComPtr<IPropertyStore> properties;
    PROPVARIANT friendly;
    PropVariantInit(&friendly);
    if (SUCCEEDED(outputs->Item(i, &device)) &&
        SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties)) &&
        SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &friendly)) &&
        friendly.vt == VT_LPWSTR && name == friendly.pwszVal) {
      PropVariantClear(&friendly);
      *out = device;
      return S_OK;
    }
    PropVariantClear(&friendly);
  }
  return FAILED(hr) ? hr : HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
}

HRESULT OpenLoopback(EnhancerState* state, int32_t* failed_stage) {
  *failed_stage = FLUCORD_AUDIO_ENHANCER_STAGE_SPEAKERS;
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDevice> device;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (SUCCEEDED(hr)) {
    hr = state->speakers_name.empty()
             ? enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)
             : FindSpeakers(enumerator.Get(), state->speakers_name, &device);
  }
  if (SUCCEEDED(hr)) hr = EndpointId(device.Get(), &state->loopback_id);
  if (SUCCEEDED(hr)) {
    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          &state->loopback_client);
  }
  if (SUCCEEDED(hr)) hr = state->loopback_client->GetMixFormat(&state->loopback_format);
  if (FAILED(hr)) return hr;
  const WAVEFORMATEX* format = state->loopback_format;
  state->loopback_float =
      format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
      (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
       reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format)->SubFormat ==
           KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
  // A shared-mode mix is 32-bit float in practice. Anything else that is
  // not 16-bit would be read as noise, so it is refused here instead.
  const bool readable = state->loopback_float
                            ? format->wBitsPerSample == 32
                            : format->wBitsPerSample == 16;
  if (format->nSamplesPerSec < 100 || format->nChannels == 0 || !readable) {
    return AUDCLNT_E_UNSUPPORTED_FORMAT;
  }

  *failed_stage = FLUCORD_AUDIO_ENHANCER_STAGE_LOOPBACK;
  hr = state->loopback_client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                          AUDCLNT_STREAMFLAGS_LOOPBACK,
                                          10000000, 0, format, nullptr);
  if (SUCCEEDED(hr)) {
    hr = state->loopback_client->GetService(
        IID_PPV_ARGS(&state->loopback_capture));
  }
  if (SUCCEEDED(hr)) hr = state->loopback_client->Start();
  return hr;
}

// Takes in whatever the speakers have played since the last call, as 16-bit
// samples at the speakers' own rate and width.
HRESULT PullSpeakers(EnhancerState* state) {
  IAudioCaptureClient* capture = state->loopback_capture.Get();
  const WAVEFORMATEX* format = state->loopback_format;
  for (;;) {
    UINT32 available = 0;
    HRESULT hr = capture->GetNextPacketSize(&available);
    if (FAILED(hr)) return hr;
    if (available == 0) return S_OK;
    BYTE* data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    hr = capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
    if (FAILED(hr)) return hr;
    const size_t samples = static_cast<size_t>(frames) * format->nChannels;
    const size_t was = state->speaker.size();
    state->speaker.resize(was + samples, 0);
    if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0) {
      int16_t* out = state->speaker.data() + was;
      if (state->loopback_float) {
        const auto* in = reinterpret_cast<const float*>(data);
        for (size_t i = 0; i < samples; i++) out[i] = ToPcm16(in[i]);
      } else {
        CopyMemory(out, data, samples * sizeof(int16_t));
      }
    }
    capture->ReleaseBuffer(frames);
  }
}

// Whether the loopback follows the default output and the default has moved
// to another endpoint since it opened. Checked once a second.
bool DefaultMoved(EnhancerState* state) {
  if (!state->speakers_name.empty()) return false;
  const ULONGLONG now = GetTickCount64();
  if (now - state->default_checked_at < kDefaultCheckMs) return false;
  state->default_checked_at = now;
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDevice> device;
  std::wstring id;
  return SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                    CLSCTX_ALL, IID_PPV_ARGS(&enumerator))) &&
         SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole,
                                                       &device)) &&
         SUCCEEDED(EndpointId(device.Get(), &id)) && id != state->loopback_id;
}

// Hands the echo stage every whole chunk the output has played. The loopback
// is opened again, and the line starts over, when it was closed for another
// output, when the default it follows moved, or when its endpoint went away.
HRESULT FeedSpeakers(EnhancerState* state, int32_t* failed_stage) {
  if (state->loopback_capture != nullptr && DefaultMoved(state)) {
    CloseLoopback(state);
  }
  HRESULT hr = S_OK;
  for (int attempt = 0; attempt < 2; attempt++) {
    if (state->loopback_capture == nullptr) {
      hr = OpenLoopback(state, failed_stage);
      if (FAILED(hr)) return hr;
    }
    *failed_stage = FLUCORD_AUDIO_ENHANCER_STAGE_SPEAKER_INPUT;
    hr = PullSpeakers(state);
    if (hr != AUDCLNT_E_DEVICE_INVALIDATED) break;
    CloseLoopback(state);
  }
  if (FAILED(hr)) return hr;

  const int rate = static_cast<int>(state->loopback_format->nSamplesPerSec);
  const int channels = state->loopback_format->nChannels;
  const size_t chunk = static_cast<size_t>(rate / 100) * channels;
  size_t at = 0;
  while (state->speaker.size() - at >= chunk) {
    const int32_t error = state->library.process_render(
        state->apm, state->speaker.data() + at, rate, channels);
    if (error != 0) return error;
    at += chunk;
  }
  state->speaker.erase(state->speaker.begin(),
                       state->speaker.begin() + static_cast<ptrdiff_t>(at));
  return S_OK;
}

// Why the last open or frame of an enhancer failed: the step, and what
// Windows or the library answered. The lock is for the caller reading it
// from another thread than the one that failed.
struct EnhancerFailure {
  std::mutex lock;
  int32_t stage = FLUCORD_AUDIO_ENHANCER_STAGE_NONE;
  int32_t result = 0;
};

EnhancerFailure& LastEnhancerFailure() {
  static EnhancerFailure failure;
  return failure;
}

void RecordEnhancerFailure(int32_t stage, int32_t result) {
  EnhancerFailure& failure = LastEnhancerFailure();
  std::lock_guard<std::mutex> guard(failure.lock);
  failure.stage = stage;
  failure.result = result;
}

}  // namespace

struct FlucordAudioEnhancer {
  std::mutex lock;
  EnhancerState state;
  bool opened = false;

  explicit FlucordAudioEnhancer(bool echo_cancellation,
                                bool automatic_gain_control)
      : state(echo_cancellation, automatic_gain_control) {}
};

extern "C" {

FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_open_mic_enhancer(int32_t echo_cancellation,
                                int32_t automatic_gain_control,
                                FlucordAudioEnhancer** out_enhancer) {
  // Cleared first, so a refusal before any step is never read as the reason
  // an earlier open gave.
  RecordEnhancerFailure(FLUCORD_AUDIO_ENHANCER_STAGE_NONE, S_OK);
  if (out_enhancer == nullptr ||
      (echo_cancellation == 0 && automatic_gain_control == 0)) {
    return FLUCORD_AUDIO_ERROR_STATE;
  }
  *out_enhancer = nullptr;

  std::unique_ptr<FlucordAudioEnhancer> enhancer(
      new (std::nothrow) FlucordAudioEnhancer(echo_cancellation != 0,
                                              automatic_gain_control != 0));
  if (enhancer == nullptr) return FLUCORD_AUDIO_ERROR_STATE;
  EnhancerState* state = &enhancer->state;

  // Every refusal below is a machine answer, not a broken state: the stages
  // cannot run here right now. Which step refused, and with what, is kept
  // for flucord_audio_mic_enhancer_failure.
  // The half-opened enhancer goes with the unique_ptr.
  const auto fail = [](int32_t stage, HRESULT hr) {
    RecordEnhancerFailure(stage, hr);
    return FLUCORD_AUDIO_ERROR_DEVICE;
  };

  HRESULT hr = LoadApm(&state->library);
  if (SUCCEEDED(hr)) {
    state->apm = state->library.create(echo_cancellation,
                                       automatic_gain_control);
    if (state->apm == nullptr) hr = E_OUTOFMEMORY;
  }
  if (FAILED(hr)) return fail(FLUCORD_AUDIO_ENHANCER_STAGE_LIBRARY, hr);

  // Only the echo stage needs the speakers, and only the speakers need COM.
  if (echo_cancellation) {
    // The thread the record package's frames arrive on has an apartment of
    // the runner's choosing, and the loopback takes it as it is. Only a
    // thread with none gets one here, and only that one takes it down.
    const HRESULT apartment = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    state->com_up = SUCCEEDED(apartment);
    if (FAILED(apartment) && apartment != RPC_E_CHANGED_MODE) {
      return fail(FLUCORD_AUDIO_ENHANCER_STAGE_APARTMENT, apartment);
    }
    int32_t stage = FLUCORD_AUDIO_ENHANCER_STAGE_SPEAKERS;
    hr = OpenLoopback(state, &stage);
    if (FAILED(hr)) return fail(stage, hr);
  }

  enhancer->opened = true;
  *out_enhancer = enhancer.release();
  return FLUCORD_AUDIO_OK;
}

FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_enhancer_loop_back(FlucordAudioEnhancer* enhancer,
                                 const char* speakers_utf8) {
  if (enhancer == nullptr) return FLUCORD_AUDIO_ERROR_STATE;
  std::wstring name;
  if (speakers_utf8 != nullptr && speakers_utf8[0] != '\0') {
    const int length =
        MultiByteToWideChar(CP_UTF8, 0, speakers_utf8, -1, nullptr, 0);
    if (length <= 0) return FLUCORD_AUDIO_ERROR_STATE;
    name.resize(static_cast<size_t>(length));
    MultiByteToWideChar(CP_UTF8, 0, speakers_utf8, -1, name.data(), length);
    name.resize(static_cast<size_t>(length) - 1);
  }
  std::lock_guard<std::mutex> guard(enhancer->lock);
  EnhancerState* state = &enhancer->state;
  if (!enhancer->opened || name == state->speakers_name) {
    return enhancer->opened ? FLUCORD_AUDIO_OK : FLUCORD_AUDIO_ERROR_STATE;
  }
  state->speakers_name = name;
  // Opened on the next frame, on the thread the frames arrive on.
  CloseLoopback(state);
  return FLUCORD_AUDIO_OK;
}

FLUCORD_AUDIO_EXPORT void
flucord_audio_mic_enhancer_failure(int32_t* out_stage, int32_t* out_result) {
  EnhancerFailure& failure = LastEnhancerFailure();
  std::lock_guard<std::mutex> guard(failure.lock);
  if (out_stage != nullptr) *out_stage = failure.stage;
  if (out_result != nullptr) *out_result = failure.result;
}

FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_enhance_frame(FlucordAudioEnhancer* enhancer,
                            int16_t* samples,
                            int32_t sample_count_per_channel,
                            int32_t channels) {
  if (enhancer == nullptr || samples == nullptr || channels <= 0 ||
      sample_count_per_channel <= 0 ||
      sample_count_per_channel % kCaptureChunk != 0) {
    return FLUCORD_AUDIO_ERROR_STATE;
  }
  std::lock_guard<std::mutex> guard(enhancer->lock);
  if (!enhancer->opened) return FLUCORD_AUDIO_ERROR_STATE;
  EnhancerState* state = &enhancer->state;

  if (state->echo_cancellation) {
    int32_t stage = FLUCORD_AUDIO_ENHANCER_STAGE_SPEAKER_INPUT;
    const HRESULT hr = FeedSpeakers(state, &stage);
    if (FAILED(hr)) {
      RecordEnhancerFailure(stage, hr);
      return FLUCORD_AUDIO_ERROR_DEVICE;
    }
  }

  for (int32_t at = 0; at < sample_count_per_channel; at += kCaptureChunk) {
    const int32_t error = state->library.process_capture(
        state->apm, samples + static_cast<size_t>(at) * channels,
        kCaptureRate, channels);
    if (error != 0) {
      RecordEnhancerFailure(FLUCORD_AUDIO_ENHANCER_STAGE_MICROPHONE, error);
      return FLUCORD_AUDIO_ERROR_DEVICE;
    }
  }
  return FLUCORD_AUDIO_OK;
}

FLUCORD_AUDIO_EXPORT void
flucord_audio_close_mic_enhancer(FlucordAudioEnhancer* enhancer) {
  // Taken back from the caller, and let go of on the way out.
  const std::unique_ptr<FlucordAudioEnhancer> owned(enhancer);
  if (owned == nullptr) return;
  std::lock_guard<std::mutex> guard(owned->lock);
  owned->opened = false;
}

}  // extern "C"
