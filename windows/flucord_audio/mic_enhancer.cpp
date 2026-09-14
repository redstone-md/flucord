// The microphone enhancer: echo cancellation and automatic gain control,
// through the Windows voice capture stages.
//
// The `record` package's capture hands the microphone straight from the
// device with no voice DSP, and its echo, gain and suppression flags are
// parsed and dropped on Windows. The stages that know how to take a room's
// own sound back out of a microphone and keep a level steady live in the
// voice capture DMO the operating system ships, so they run here, on the
// frames the capture already produces.
//
// The DMO in filter mode takes the microphone on stream 0 and what the
// machine is playing on stream 1, and answers the microphone with the room
// taken out. It works at 8 to 22 kHz, so this module keeps both directions
// of conversion: the pipeline's 48 kHz frames go in as 16 kHz mono, and
// the answer is held back until a whole frame of it has arrived, so the
// pipeline's own timing and frame length are unchanged. The cost is a few
// frames at the start that pass through as captured, while the stages fill.
//
// Everything runs on the thread that opens it, the same thread the record
// package's frames arrive on. The DMO is in-process and takes whatever
// apartment the thread already has; when the thread has none, one is
// brought up here and taken down on close.

#include "flucord_audio.h"

#include <algorithm>
#include <cstring>
#include <mutex>
#include <new>
#include <vector>
#include <windows.h>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>


#include <mediaobj.h>
#include <propsys.h>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "mmdevapi.lib")

using Microsoft::WRL::ComPtr;

namespace {

// The DMO's internal rate: high enough for a voice, low enough that the
// stages stay cheap, and one of the four the DMO answers at.
constexpr int kInternalRate = 16000;

// One 20 ms frame at the internal rate, mono. The pipeline's frames are
// 20 ms too, so one frame in answers one frame out, once the stages fill.
constexpr int kInternalFrame = kInternalRate / 50;

// The DMO answers less than one internal frame per call while its buffers
// fill. Enough output buffer for four internal frames keeps the drain loop
// to one pass a call.
constexpr int kOutputSamples = kInternalFrame * 4;

// How much of the speaker line may pile up before the oldest is dropped:
// a quarter second is many frames of drift between the two clocks, and the
// reference that old matches nothing the microphone is hearing.
constexpr size_t kSpeakerBacklog = kInternalRate / 4;

// The voice capture DMO's class, pinned here rather than taken from
// Wmcodecdsp.h so the module builds wherever the header is thin. The value
// is the SDK's own, CLSID_CWMAudioAEC.
constexpr CLSID kVoiceCaptureClsid = {0x745057c7,
                                      0xf353,
                                      0x4f2d,
                                      {0xa7, 0xee, 0x58, 0x43, 0x44, 0x77,
                                       0x73, 0x0e}};

// Every property of the voice capture DMO shares one format id; the pids
// below are the SDK's own values, with the names each belongs to beside it.
constexpr GUID kWmaaecmaFmtid = {0x6f52c567,
                                 0x0360,
                                 0x4bd2,
                                 {0x96, 0x17, 0xcc, 0xbf, 0x14, 0x21, 0xc9,
                                  0x39}};

// MFPKEY_WMAAECMA_SYSTEM_MODE, pid 2. Zero takes the room out of the
// microphone; five is noise and gain without the echo stage.
constexpr PROPERTYKEY kSystemMode = {kWmaaecmaFmtid, 2};

// MFPKEY_WMAAECMA_DMO_SOURCE_MODE, pid 3. False is filter mode: the
// samples are handed in rather than the DMO owning the devices, which are
// the record package's to own.
constexpr PROPERTYKEY kSourceMode = {kWmaaecmaFmtid, 3};

// MFPKEY_WMAAECMA_FEATURE_MODE, pid 5. True lets the stages be set.
constexpr PROPERTYKEY kFeatureMode = {kWmaaecmaFmtid, 5};

// MFPKEY_WMAAECMA_FEATR_NS, pid 8. Stays off: DeepFilterNet already owns
// noise at the same place in the pipeline, and two noise stages would
// charge the CPU twice for the same clean.
constexpr PROPERTYKEY kFeatureNoiseSuppression = {kWmaaecmaFmtid, 8};

// MFPKEY_WMAAECMA_FEATR_AGC, pid 9.
constexpr PROPERTYKEY kFeatureAutomaticGain = {kWmaaecmaFmtid, 9};

// AEC_SYSTEM_MODE: SINGLE_CHANNEL_AEC, then SINGLE_CHANNEL_NSAGC.
constexpr int kModeEchoCancellation = 0;
constexpr int kModeNoiseAndGain = 5;

// The DMO media type's pinned GUIDs: the major type, the PCM subtype and
// the WAVEFORMATEX format block. The values are the SDK's own.
constexpr GUID kMediaTypeAudio = {0x73647561,
                                  0x0000,
                                  0x0010,
                                  {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b,
                                   0x71}};
constexpr GUID kMediaSubtypePcm = {0x00000001,
                                    0x0000,
                                    0x0010,
                                    {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b,
                                     0x71}};
constexpr GUID kFormatWaveFormatEx = {0x05589f81,
                                      0xc356,
                                      0x11ce,
                                      {0xbf, 0x01, 0x00, 0xaa, 0x00, 0x55,
                                       0x59, 0x5a}};

// One IMediaBuffer over one buffer of bytes: the DMO asks for its data by
// pointer and length, and says how much it wrote with SetLength. Plain COM
// rather than a template, so the module builds with any compiler that has
// the Windows headers.
class MediaBuffer final : public IMediaBuffer {
 public:
  static MediaBuffer* Create(size_t bytes) {
    return new (std::nothrow) MediaBuffer(bytes);
  }

  // IUnknown:
  STDMETHOD(QueryInterface)(REFIID id, void** out) override {
    if (out == nullptr) return E_POINTER;
    if (id == IID_IUnknown || id == IID_IMediaBuffer) {
      *out = static_cast<IMediaBuffer*>(this);
      AddRef();
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }

  STDMETHOD_(ULONG, AddRef)() override { return ++refs_; }

  STDMETHOD_(ULONG, Release)() override {
    const ULONG refs = --refs_;
    if (refs == 0) delete this;
    return refs;
  }

  // IMediaBuffer:
  STDMETHOD(GetBufferAndLength)(BYTE** buffer, DWORD* length) override {
    if (buffer != nullptr) *buffer = storage_.data();
    if (length != nullptr) *length = static_cast<DWORD>(filled_);
    return S_OK;
  }

  STDMETHOD(GetMaxLength)(DWORD* length) override {
    if (length == nullptr) return E_POINTER;
    *length = static_cast<DWORD>(storage_.size());
    return S_OK;
  }

  STDMETHOD(SetLength)(DWORD length) override {
    if (length > storage_.size()) return E_INVALIDARG;
    filled_ = length;
    return S_OK;
  }

  // The samples the DMO reads and writes, at the length last set.
  int16_t* samples() { return reinterpret_cast<int16_t*>(storage_.data()); }

 private:
  explicit MediaBuffer(size_t bytes) : storage_(bytes) {}

  std::vector<BYTE> storage_;
  size_t filled_ = 0;
  ULONG refs_ = 1;
};

// A DMO media type holding one WAVEFORMATEX, so the streams can be given
// their formats without a heap of plumbing.
class PcmMediaType {
 public:
  PcmMediaType(int rate, int channels) {
    ZeroMemory(&type_, sizeof(type_));
    wave_ = {};
    wave_.wFormatTag = WAVE_FORMAT_PCM;
    wave_.nSamplesPerSec = rate;
    wave_.nChannels = channels;
    wave_.wBitsPerSample = 16;
    wave_.nBlockAlign = wave_.nChannels * wave_.wBitsPerSample / 8;
    wave_.nAvgBytesPerSec = wave_.nSamplesPerSec * wave_.nBlockAlign;
    type_.majortype = kMediaTypeAudio;
    type_.subtype = kMediaSubtypePcm;
    type_.formattype = kFormatWaveFormatEx;
    type_.bFixedSizeSamples = TRUE;
    type_.lSampleSize = static_cast<ULONG>(wave_.nBlockAlign);
    type_.cbFormat = sizeof(wave_);
    type_.pbFormat = reinterpret_cast<BYTE*>(&wave_);
  }

  const DMO_MEDIA_TYPE* get() const { return &type_; }

 private:
  DMO_MEDIA_TYPE type_;
  WAVEFORMATEX wave_;
};

// Float samples are what a shared-mode endpoint almost always hands back.
// Clamped rather than wrapped: a sample past full scale is loud, and
// wrapping turns loud into a click.
int16_t ToPcm16(float value) {
  const float scaled = value * 32767.0f;
  if (scaled > 32767.0f) return 32767;
  if (scaled < -32768.0f) return -32768;
  return static_cast<int16_t>(scaled);
}

// Everything the enhancer holds: the DMO, the speaker line that feeds it,
// and the conversion state that keeps the pipeline's own frame length.
struct EnhancerState {
  EnhancerState(bool echo_cancellation, bool automatic_gain_control)
      : echo_cancellation(echo_cancellation),
        automatic_gain_control(automatic_gain_control) {}

  const bool echo_cancellation;
  const bool automatic_gain_control;
  bool com_up = false;
  ComPtr<IMediaObject> dmo;
  ComPtr<IPropertyStore> properties;
  ComPtr<IAudioClient> loopback_client;
  ComPtr<IAudioCaptureClient> loopback_capture;
  WAVEFORMATEX* loopback_format = nullptr;

  // The speaker line at its own rate, mono, and where the next internal
  // sample of it is taken from. Fractional, so the two clocks never drift
  // apart by a whole sample a packet.
  std::vector<int16_t> speaker;
  double speaker_at = 0;
  double speaker_step = 0;  // Internal samples per speaker sample.

  // The speaker line converted to the internal rate, waiting to be handed
  // to the DMO one frame at a time.
  std::vector<int16_t> speaker_internal;

  // The DMO's answer, at the internal rate, not yet a whole frame of it.
  std::vector<int16_t> answered;
};

// Takes in whatever the speaker line has produced, folds it down to mono,
// and converts it to the internal rate.
void PullSpeaker(EnhancerState* state) {
  auto* capture = state->loopback_capture.Get();
  if (capture == nullptr) return;
  for (;;) {
    UINT32 available = 0;
    if (FAILED(capture->GetNextPacketSize(&available)) || available == 0) {
      break;
    }
    BYTE* data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) {
      break;
    }
    const WAVEFORMATEX* format = state->loopback_format;
    if (frames > 0 && format != nullptr && data != nullptr) {
      const int channels = format->nChannels > 0 ? format->nChannels : 1;
      const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
      const bool is_float =
          format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
          (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
           reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format)->SubFormat ==
               KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
      const size_t was = state->speaker.size();
      state->speaker.resize(was + frames);
      for (UINT32 frame = 0; frame < frames; frame++) {
        if (silent) {
          state->speaker[was + frame] = 0;
          continue;
        }
        const BYTE* at = data + frame * format->nBlockAlign;
        int32_t sum = 0;
        if (is_float) {
          const auto* floats = reinterpret_cast<const float*>(at);
          for (int channel = 0; channel < channels; channel++) {
            sum += ToPcm16(floats[channel]);
          }
        } else if (format->wBitsPerSample == 16) {
          const auto* pcm = reinterpret_cast<const int16_t*>(at);
          for (int channel = 0; channel < channels; channel++) {
            sum += pcm[channel];
          }
        }
        state->speaker[was + frame] = static_cast<int16_t>(sum / channels);
      }
    }
    capture->ReleaseBuffer(frames);
  }

  // Convert what has arrived. One internal sample needs the two speaker
  // samples it falls between, so the loop stops one short of the end and
  // the next packet completes the pair.
  const double step = state->speaker_step;
  while (state->speaker_at + 1.0 <
         static_cast<double>(state->speaker.size())) {
    const size_t whole = static_cast<size_t>(state->speaker_at);
    const double frac = state->speaker_at - whole;
    const int16_t a = state->speaker[whole];
    const int16_t b = state->speaker[whole + 1];
    state->speaker_internal.push_back(
        static_cast<int16_t>(a + (b - a) * frac + 0.5));
    state->speaker_at += step;
  }
  // Keep the buffer bounded and the position it is read from small: the
  // whole samples before the position are spent.
  const size_t spent = static_cast<size_t>(state->speaker_at);
  if (spent > 0) {
    state->speaker.erase(
        state->speaker.begin(),
        state->speaker.begin() + static_cast<ptrdiff_t>(spent));
    state->speaker_at -= spent;
  }
  // The reference that is too old matches nothing the microphone hears.
  if (state->speaker_internal.size() > kSpeakerBacklog) {
    const size_t excess = state->speaker_internal.size() - kSpeakerBacklog;
    state->speaker_internal.erase(
        state->speaker_internal.begin(),
        state->speaker_internal.begin() + static_cast<ptrdiff_t>(excess));
  }
}

// Reads one internal frame of what the machine is playing. Silence when
// nothing new arrived: the speaker stream has to keep moving for the echo
// stage to stay aligned, and the microphone frame it is handed beside is
// from the same moment.
void ReadSpeakerFrame(EnhancerState* state, int16_t* out) {
  PullSpeaker(state);
  const size_t have = std::min(state->speaker_internal.size(),
                               static_cast<size_t>(kInternalFrame));
  for (size_t i = 0; i < have; i++) {
    out[i] = state->speaker_internal[i];
  }
  if (have < static_cast<size_t>(kInternalFrame)) {
    ZeroMemory(out + have,
               (kInternalFrame - have) * sizeof(int16_t));
  }
  if (have > 0) {
    state->speaker_internal.erase(
        state->speaker_internal.begin(),
        state->speaker_internal.begin() + static_cast<ptrdiff_t>(have));
  }
}

// Folds one frame of the pipeline's width down to mono at the internal
// rate, into [out].
void Downmix(const int16_t* samples,
             int sample_count_per_channel,
             int channels,
             int16_t* out) {
  const double step =
      static_cast<double>(sample_count_per_channel) / kInternalFrame;
  for (int i = 0; i < kInternalFrame; i++) {
    const double at = i * step;
    const long whole = static_cast<long>(at);
    long next = whole + 1;
    if (next >= sample_count_per_channel) next = sample_count_per_channel - 1;
    auto sample = [&](long index) {
      int32_t sum = 0;
      for (int channel = 0; channel < channels; channel++) {
        sum += samples[index * channels + channel];
      }
      return static_cast<int16_t>(sum / channels);
    };
    const int16_t a = sample(whole);
    const int16_t b = whole == next ? a : sample(next);
    out[i] = static_cast<int16_t>(a + (b - a) * (at - whole) + 0.5);
  }
}

// Hands the DMO one internal frame of microphone, and one of speaker when
// the echo stage is running. Answers whether the DMO took it.
bool FeedDmo(EnhancerState* state, const int16_t* mono) {
  ComPtr<MediaBuffer> mic(MediaBuffer::Create(
      static_cast<size_t>(kInternalFrame * sizeof(int16_t))));
  if (mic == nullptr) return false;
  CopyMemory(mic->samples(), mono, kInternalFrame * sizeof(int16_t));
  mic->SetLength(kInternalFrame * sizeof(int16_t));
  if (FAILED(state->dmo->ProcessInput(0, mic.Get(), 0, 0, 0))) return false;

  if (state->echo_cancellation) {
    int16_t speaker_frame[kInternalFrame];
    ReadSpeakerFrame(state, speaker_frame);
    ComPtr<MediaBuffer> speaker(MediaBuffer::Create(
        static_cast<size_t>(kInternalFrame * sizeof(int16_t))));
    if (speaker == nullptr) return false;
    CopyMemory(speaker->samples(), speaker_frame,
               kInternalFrame * sizeof(int16_t));
    speaker->SetLength(kInternalFrame * sizeof(int16_t));
    if (FAILED(state->dmo->ProcessInput(1, speaker.Get(), 0, 0, 0))) {
      return false;
    }
  }
  return true;
}

// Pulls whatever the DMO has answered into the pending answer.
bool DrainDmo(EnhancerState* state) {
  for (;;) {
    ComPtr<MediaBuffer> out(MediaBuffer::Create(
        static_cast<size_t>(kOutputSamples * sizeof(int16_t))));
    if (out == nullptr) return false;
    DMO_OUTPUT_DATA_BUFFER buffer = {};
    buffer.pBuffer = out.Get();
    const HRESULT hr = state->dmo->ProcessOutput(0, 1, &buffer, nullptr);
    // S_FALSE is "nothing answered", not a failure.
    if (FAILED(hr)) return false;
    DWORD length = 0;
    out->GetBufferAndLength(nullptr, &length);
    const size_t count = length / sizeof(int16_t);
    if (count > 0) {
      const int16_t* answered = out->samples();
      state->answered.insert(state->answered.end(), answered,
                             answered + count);
    }
    // More is waiting when this buffer says so.
    if ((buffer.dwStatus & DMO_OUTPUT_DATA_BUFFERF_INCOMPLETE) == 0) {
      return true;
    }
  }
}

// Rebuilds one frame of the pipeline's rate and width from the pending
// answer. A frame of the answer is a third the length of the frame asked
// for, so the frame goes out only once a whole frame of it has arrived;
// until then the caller's frame is left as captured, and the gate hangs
// over whatever the stages still hold.
bool FillFrame(EnhancerState* state,
               int16_t* samples,
               int sample_count_per_channel,
               int channels) {
  if (state->answered.size() < static_cast<size_t>(kInternalFrame) + 1) {
    return false;
  }
  const double step =
      static_cast<double>(kInternalFrame) / sample_count_per_channel;
  for (int i = 0; i < sample_count_per_channel; i++) {
    const double at = i * step;
    const size_t whole = static_cast<size_t>(at);
    const double frac = at - whole;
    const int16_t a = state->answered[whole];
    const int16_t b = state->answered[whole + 1];
    const int16_t value = static_cast<int16_t>(a + (b - a) * frac + 0.5);
    for (int channel = 0; channel < channels; channel++) {
      samples[i * channels + channel] = value;
    }
  }
  state->answered.erase(
      state->answered.begin(),
      state->answered.begin() + static_cast<ptrdiff_t>(kInternalFrame));
  return true;
}

// Sets one DMO property, answering whether it took.
bool SetProperty(IPropertyStore* store, REFPROPERTYKEY key, int value) {
  PROPVARIANT held = {};
  held.vt = VT_I4;
  held.lVal = value;
  const HRESULT result = store->SetValue(key, held);
  PropVariantClear(&held);
  return SUCCEEDED(result);
}

bool SetProperty(IPropertyStore* store, REFPROPERTYKEY key, bool value) {
  PROPVARIANT held = {};
  held.vt = VT_BOOL;
  held.boolVal = value ? VARIANT_TRUE : VARIANT_FALSE;
  const HRESULT result = store->SetValue(key, held);
  PropVariantClear(&held);
  return SUCCEEDED(result);
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

// The apartment this module brought up, if it brought one up, and the
// half-opened enhancer with it.
void AbandonEnhancer(FlucordAudioEnhancer* enhancer) {
  CoTaskMemFree(enhancer->state.loopback_format);
  if (enhancer->state.com_up) CoUninitialize();
  delete enhancer;
}

extern "C" {

FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_open_mic_enhancer(int32_t echo_cancellation,
                                int32_t automatic_gain_control,
                                FlucordAudioEnhancer** out_enhancer) {
  if (out_enhancer == nullptr ||
      (echo_cancellation == 0 && automatic_gain_control == 0)) {
    return FLUCORD_AUDIO_ERROR_STATE;
  }
  *out_enhancer = nullptr;

  auto* enhancer = new (std::nothrow) FlucordAudioEnhancer(
      echo_cancellation != 0, automatic_gain_control != 0);
  if (enhancer == nullptr) return FLUCORD_AUDIO_ERROR_STATE;
  EnhancerState* state = &enhancer->state;

  // The thread the record package's frames arrive on has an apartment of
  // the runner's choosing; the DMO is in-process and takes it as it is.
  // Only a thread with none gets one here, and only that one takes it down.
  const HRESULT apartment = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  state->com_up = SUCCEEDED(apartment);
  if (FAILED(apartment) && apartment != RPC_E_CHANGED_MODE) {
    delete enhancer;
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }

  // A machine whose voice stages cannot be created is a machine whose
  // microphone cannot be enhanced: a device answer, not a broken state.
  HRESULT hr = CoCreateInstance(kVoiceCaptureClsid, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&state->dmo));
  if (FAILED(hr) || state->dmo == nullptr) {
    AbandonEnhancer(enhancer);
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }
  hr = state->dmo.As(&state->properties);
  if (FAILED(hr) || state->properties == nullptr) {
    AbandonEnhancer(enhancer);
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }

  // Filter mode, the stages wanted, and nothing else: the DMO's own noise
  // suppression stays off because DeepFilterNet already owns noise at the
  // same place in the pipeline.
  const bool configured =
      SetProperty(state->properties.Get(), kSourceMode, false) &&
      SetProperty(state->properties.Get(), kSystemMode,
                  echo_cancellation ? kModeEchoCancellation
                                    : kModeNoiseAndGain) &&
      SetProperty(state->properties.Get(), kFeatureMode, true) &&
      SetProperty(state->properties.Get(), kFeatureNoiseSuppression, false) &&
      SetProperty(state->properties.Get(), kFeatureAutomaticGain,
                  automatic_gain_control != 0);
  if (!configured) {
    AbandonEnhancer(enhancer);
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }

  // Both streams and the answer are 16 kHz mono 16-bit.
  const PcmMediaType internal(kInternalRate, 1);
  if (FAILED(state->dmo->SetInputType(0, internal.get(), 0)) ||
      FAILED(state->dmo->SetInputType(1, internal.get(), 0)) ||
      FAILED(state->dmo->SetOutputType(0, internal.get(), 0)) ||
      FAILED(state->dmo->AllocateStreamingResources())) {
    AbandonEnhancer(enhancer);
    return FLUCORD_AUDIO_ERROR_DEVICE;
  }

  // The speaker line: what the machine is playing, looped back from the
  // render endpoint. The room's voices come out of this process, and a
  // microphone in front of those speakers hears them twice without one of
  // the two taken out. Only the echo stage needs it.
  if (echo_cancellation) {
    ComPtr<IMMDeviceEnumerator> enumerator;
    ComPtr<IMMDevice> device;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator))) ||
        FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole,
                                                  &device)) ||
        FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                &state->loopback_client))) {
      AbandonEnhancer(enhancer);
      return FLUCORD_AUDIO_ERROR_DEVICE;
    }
    WAVEFORMATEX* format = nullptr;
    if (FAILED(state->loopback_client->GetMixFormat(&format)) ||
        format == nullptr || format->nSamplesPerSec == 0) {
      CoTaskMemFree(format);
      AbandonEnhancer(enhancer);
      return FLUCORD_AUDIO_ERROR_DEVICE;
    }
    hr = state->loopback_client->Initialize(
        AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 10000000, 0,
        format, nullptr);
    if (SUCCEEDED(hr)) {
      hr = state->loopback_client->GetService(
          IID_PPV_ARGS(&state->loopback_capture));
    }
    if (SUCCEEDED(hr)) {
      hr = state->loopback_client->Start();
    }
    if (FAILED(hr)) {
      CoTaskMemFree(format);
      AbandonEnhancer(enhancer);
      return FLUCORD_AUDIO_ERROR_DEVICE;
    }
    state->speaker_step =
        static_cast<double>(kInternalRate) / format->nSamplesPerSec;
    state->loopback_format = format;
  }

  enhancer->opened = true;
  *out_enhancer = enhancer;
  return FLUCORD_AUDIO_OK;
}

FLUCORD_AUDIO_EXPORT FlucordAudioStatus
flucord_audio_enhance_frame(FlucordAudioEnhancer* enhancer,
                            int16_t* samples,
                            int32_t sample_count_per_channel,
                            int32_t channels) {
  if (enhancer == nullptr || samples == nullptr ||
      sample_count_per_channel <= 0 || channels <= 0) {
    return FLUCORD_AUDIO_ERROR_STATE;
  }
  std::lock_guard<std::mutex> guard(enhancer->lock);
  if (!enhancer->opened) return FLUCORD_AUDIO_ERROR_STATE;
  EnhancerState* state = &enhancer->state;

  int16_t mono[kInternalFrame];
  Downmix(samples, sample_count_per_channel, channels, mono);
  if (!FeedDmo(state, mono)) return FLUCORD_AUDIO_ERROR_STATE;
  if (!DrainDmo(state)) return FLUCORD_AUDIO_ERROR_STATE;
  // Nothing to say yet: the frame goes out as captured, and the pipeline's
  // gate hangs over the tail of a word the stages still hold.
  FillFrame(state, samples, sample_count_per_channel, channels);
  return FLUCORD_AUDIO_OK;
}

FLUCORD_AUDIO_EXPORT void
flucord_audio_close_mic_enhancer(FlucordAudioEnhancer* enhancer) {
  if (enhancer == nullptr) return;
  std::lock_guard<std::mutex> guard(enhancer->lock);
  if (enhancer->state.loopback_client != nullptr) {
    enhancer->state.loopback_client->Stop();
  }
  if (enhancer->state.dmo != nullptr) {
    enhancer->state.dmo->FreeStreamingResources();
  }
  AbandonEnhancer(enhancer);
}

}  // extern "C"
