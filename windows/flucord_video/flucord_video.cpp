#include "flucord_video.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <windows.h>

#include <codecapi.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfobjects.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mftransform.h>
#include <strmif.h>
#include <wrl/client.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "wmcodecdspuuid.lib")

using Microsoft::WRL::ComPtr;

namespace {

// Desktop Duplication hands out BGRA; the H.264 MFT wants NV12, and nothing in
// between will convert for us, so the conversion is done here rather than
// hoping a colour-space negotiation picks it up.
void BgraToNv12(const uint8_t* source,
                int source_stride,
                int width,
                int height,
                uint8_t* destination) {
  uint8_t* luma = destination;
  uint8_t* chroma = destination + static_cast<size_t>(width) * height;
  for (int y = 0; y < height; ++y) {
    const uint8_t* row = source + static_cast<size_t>(y) * source_stride;
    for (int x = 0; x < width; ++x) {
      const uint8_t b = row[x * 4 + 0];
      const uint8_t g = row[x * 4 + 1];
      const uint8_t r = row[x * 4 + 2];
      luma[static_cast<size_t>(y) * width + x] = static_cast<uint8_t>(
          ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
    }
  }
  // Chroma is sampled at half resolution in both directions, averaged over the
  // 2x2 block so a downscaled edge does not shimmer.
  for (int y = 0; y + 1 < height; y += 2) {
    for (int x = 0; x + 1 < width; x += 2) {
      int sum_b = 0;
      int sum_g = 0;
      int sum_r = 0;
      for (int dy = 0; dy < 2; ++dy) {
        const uint8_t* row = source + static_cast<size_t>(y + dy) * source_stride;
        for (int dx = 0; dx < 2; ++dx) {
          sum_b += row[(x + dx) * 4 + 0];
          sum_g += row[(x + dx) * 4 + 1];
          sum_r += row[(x + dx) * 4 + 2];
        }
      }
      const int b = sum_b / 4;
      const int g = sum_g / 4;
      const int r = sum_r / 4;
      const size_t index =
          static_cast<size_t>(y / 2) * width + static_cast<size_t>(x);
      chroma[index] = static_cast<uint8_t>(
          ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
      chroma[index + 1] = static_cast<uint8_t>(
          ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
    }
  }
}

// Converts and scales in one pass. The capture is the display's own
// resolution and the encoder wants its configured size, and nothing between
// the desktop and this loop will do the resize: handing the encoder a
// top-left crop of a larger desktop is what this replaced.
//
// Bilinear, with 8-bit fixed point weights. A screen is text and edges, and a
// nearest-neighbour downscale of those shimmers; a proper area average would
// be sharper still, but at these sizes bilinear is the quality-per-line that
// keeps a 30 fps capture loop inside its frame budget.
void BgraToNv12Scaled(const uint8_t* source,
                      int source_stride,
                      int source_width,
                      int source_height,
                      int width,
                      int height,
                      uint8_t* destination) {
  uint8_t* luma = destination;
  uint8_t* chroma = destination + static_cast<size_t>(width) * height;

  // Source coordinates and weights, precomputed per destination line and
  // column: the sampling grid is the same for every row of the plane.
  std::vector<int> x0(width), x1(width), wx(width);
  for (int x = 0; x < width; ++x) {
    const double sx = (x + 0.5) * source_width / width - 0.5;
    int ix0 = static_cast<int>(sx);
    double frac = sx - ix0;
    if (ix0 < 0) {
      ix0 = 0;
      frac = 0;
    } else if (ix0 >= source_width - 1) {
      ix0 = source_width - 1;
      frac = 0;
    }
    x0[x] = ix0 * 4;
    x1[x] = (ix0 + 1 < source_width ? ix0 + 1 : ix0) * 4;
    wx[x] = static_cast<int>(frac * 256.0);
  }
  std::vector<int> y0(height), y1(height), wy(height);
  for (int y = 0; y < height; ++y) {
    const double sy = (y + 0.5) * source_height / height - 0.5;
    int iy0 = static_cast<int>(sy);
    double frac = sy - iy0;
    if (iy0 < 0) {
      iy0 = 0;
      frac = 0;
    } else if (iy0 >= source_height - 1) {
      iy0 = source_height - 1;
      frac = 0;
    }
    y0[y] = iy0 * source_stride;
    y1[y] = (iy0 + 1 < source_height ? iy0 + 1 : iy0) * source_stride;
    wy[y] = static_cast<int>(frac * 256.0);
  }

  for (int y = 0; y < height; ++y) {
    const uint8_t* row0 = source + y0[y];
    const uint8_t* row1 = source + y1[y];
    const int weight_y = 256 - wy[y];
    uint8_t* out = luma + static_cast<size_t>(y) * width;
    for (int x = 0; x < width; ++x) {
      const int weight_x = 256 - wx[x];
      const int top = weight_x * weight_y;
      const int bottom = wx[x] * weight_y;
      const int left = weight_x * wy[y];
      const int right = wx[x] * wy[y];
      const int b = (row0[x0[x] + 0] * top + row0[x1[x] + 0] * bottom +
                     row1[x0[x] + 0] * left + row1[x1[x] + 0] * right) >> 16;
      const int g = (row0[x0[x] + 1] * top + row0[x1[x] + 1] * bottom +
                     row1[x0[x] + 1] * left + row1[x1[x] + 1] * right) >> 16;
      const int r = (row0[x0[x] + 2] * top + row0[x1[x] + 2] * bottom +
                     row1[x0[x] + 2] * left + row1[x1[x] + 2] * right) >> 16;
      out[x] = static_cast<uint8_t>(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
    }
  }

  // Chroma at half resolution, sampled at the centre of each destination
  // 2x2 block rather than its top-left corner, so the colour of a one-pixel
  // source line does not fall between the samples.
  const int chroma_width = width / 2;
  const int chroma_height = height / 2;
  std::vector<int> cx0(chroma_width), cx1(chroma_width), cwx(chroma_width);
  for (int x = 0; x < chroma_width; ++x) {
    const double sx = (x + 0.5) * source_width / chroma_width - 0.5;
    int ix0 = static_cast<int>(sx);
    double frac = sx - ix0;
    if (ix0 < 0) {
      ix0 = 0;
      frac = 0;
    } else if (ix0 >= source_width - 1) {
      ix0 = source_width - 1;
      frac = 0;
    }
    cx0[x] = ix0 * 4;
    cx1[x] = (ix0 + 1 < source_width ? ix0 + 1 : ix0) * 4;
    cwx[x] = static_cast<int>(frac * 256.0);
  }
  for (int y = 0; y < chroma_height; ++y) {
    const double sy = (y + 0.5) * source_height / chroma_height - 0.5;
    int iy0 = static_cast<int>(sy);
    double frac = sy - iy0;
    if (iy0 < 0) {
      iy0 = 0;
      frac = 0;
    } else if (iy0 >= source_height - 1) {
      iy0 = source_height - 1;
      frac = 0;
    }
    const uint8_t* row0 = source + iy0 * source_stride;
    const uint8_t* row1 =
        source + (iy0 + 1 < source_height ? iy0 + 1 : iy0) * source_stride;
    const int wy_ = static_cast<int>(frac * 256.0);
    const int weight_y = 256 - wy_;
    uint8_t* out = chroma + static_cast<size_t>(y) * width;
    for (int x = 0; x < chroma_width; ++x) {
      const int weight_x = 256 - cwx[x];
      const int top = weight_x * weight_y;
      const int bottom = cwx[x] * weight_y;
      const int left = weight_x * wy_;
      const int right = cwx[x] * wy_;
      const int b = (row0[cx0[x] + 0] * top + row0[cx1[x] + 0] * bottom +
                     row1[cx0[x] + 0] * left + row1[cx1[x] + 0] * right) >> 16;
      const int g = (row0[cx0[x] + 1] * top + row0[cx1[x] + 1] * bottom +
                     row1[cx0[x] + 1] * left + row1[cx1[x] + 1] * right) >> 16;
      const int r = (row0[cx0[x] + 2] * top + row0[cx1[x] + 2] * bottom +
                     row1[cx0[x] + 2] * left + row1[cx1[x] + 2] * right) >> 16;
      out[x * 2] = static_cast<uint8_t>(
          ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
      out[x * 2 + 1] = static_cast<uint8_t>(
          ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
    }
  }
}

bool IsKeyframe(IMFSample* sample) {
  UINT32 value = 0;
  return SUCCEEDED(sample->GetUINT32(MFSampleExtension_CleanPoint, &value)) &&
         value != 0;
}

// A monotonic clock with sub-millisecond resolution, for timing the stages of
// a frame. GetTickCount64 steps in ~15 ms chunks, which is most of a frame's
// whole budget.
int64_t NowNs() {
  static const int64_t frequency = [] {
    LARGE_INTEGER value;
    QueryPerformanceFrequency(&value);
    return value.QuadPart;
  }();
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return now.QuadPart * 1000000000 / frequency;
}

}  // namespace

struct FlucordVideoEncoder {
  FlucordVideoConfig config{};
  FlucordVideoFrameCallback callback = nullptr;
  void* user_data = nullptr;

  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<IDXGIOutputDuplication> duplication;
  // Set instead of `duplication` when the source is a camera. Which of the two
  // is held is what the capture thread branches on, so a pipeline can only
  // ever have one source and cannot silently read from both.
  ComPtr<IMFSourceReader> reader;
  ComPtr<IMFTransform> encoder;

  // A hardware encoder MFT is driven differently: it asks for input through
  // events (METransformNeedInput) instead of accepting it whenever offered,
  // and answers with METransformHaveOutput. Null on the software encoder,
  // which takes ProcessInput whenever the caller has a frame.
  ComPtr<ICodecAPI> codec;
  ComPtr<IMFMediaEventGenerator> encoder_events;
  bool encoder_is_async = false;
  bool encoder_accepts_input = true;
  // A hardware encoder that failed mid-stream is swapped for the software one
  // exactly once; after that a second failure is reported, not retried.
  bool encoder_rebuilt_as_software = false;
  std::string encoder_name;

  // Where a frame's time went, written on the capture thread and read by the
  // pace log. Totals rather than averages: the reader divides by the deltas.
  std::atomic<int64_t> capture_wait_ns{0};
  std::atomic<int64_t> convert_ns{0};
  std::atomic<int64_t> encode_ns{0};
  std::atomic<int64_t> timed_frames{0};

  std::thread worker;
  std::atomic<bool> running{false};
  std::atomic<bool> paused{false};
  std::atomic<bool> keyframe_requested{true};
  std::mutex encoder_lock;

  std::vector<uint8_t> nv12;
};

namespace {

std::string ToHex(HRESULT hr) {
  char text[16];
  snprintf(text, sizeof(text), "%08x", static_cast<unsigned>(hr));
  return text;
}

// Sets the shared contract on one encoder transform: codec knobs, output and
// input types, the streaming start. Appends what the encoder accepted to
// `knobs` ("gop=ok force=ok"), because an encoder that silently ignores the
// GOP looks identical to one that honours it until a viewer joins midway.
HRESULT SetupEncoderTransform(FlucordVideoEncoder* state,
                              IMFTransform* transform,
                              bool hardware,
                              bool* is_async,
                              std::string* knobs) {
  *is_async = false;
  ComPtr<IMFAttributes> attributes;
  if (SUCCEEDED(transform->GetAttributes(&attributes))) {
    UINT32 async = 0;
    if (SUCCEEDED(attributes->GetUINT32(MF_TRANSFORM_ASYNC, &async)) &&
        async != 0) {
      *is_async = true;
      // The gate an asynchronous MFT waits behind before it will raise
      // events at all.
      attributes->SetUINT32(MF_TRANSFORM_ASYNC_UNLOCK, 1);
    }
  }

  ComPtr<ICodecAPI> codec;
  const bool has_codec =
      SUCCEEDED(transform->QueryInterface(IID_PPV_ARGS(&codec)));

  // Real-time playback: a viewer decodes each picture as it arrives, so the
  // encoder must not hold frames back for reordering. Other clients force
  // max_num_reorder_frames = 0 in the SPS for this; low-latency mode is the
  // platform's own switch for the same thing. Set before the media types:
  // a hardware encoder may lock its codec API once types are negotiated, and
  // best-effort because refusing it still leaves a watchable stream.
  if (has_codec) {
    VARIANT low_latency;
    VariantInit(&low_latency);
    low_latency.vt = VT_BOOL;
    low_latency.boolVal = VARIANT_TRUE;
    codec->SetValue(&CODECAPI_AVLowLatencyMode, &low_latency);
    VariantClear(&low_latency);

    // A keyframe every two seconds. Nothing retransmits a lost packet here,
    // so a viewer's picture freezes until the next keyframe, and the
    // encoder's own spacing is measured in scenes and seconds, not in
    // anything a live viewer would call recovery.
    VARIANT gop;
    VariantInit(&gop);
    gop.vt = VT_UI4;
    gop.ulVal = static_cast<UINT32>(state->config.frames_per_second) * 2;
    const HRESULT gop_result =
        codec->SetValue(&CODECAPI_AVEncMPVGOPSize, &gop);
    VariantClear(&gop);
    *knobs += " gop=";
    *knobs += SUCCEEDED(gop_result) ? "ok" : ToHex(gop_result);

    // Vendor encoders take their bitrate from the rate control pair rather
    // than the media type, and default to peak-constrained modes that swing
    // harder than a live stream wants.
    if (hardware) {
      VARIANT rate_control;
      VariantInit(&rate_control);
      rate_control.vt = VT_UI4;
      rate_control.ulVal = eAVEncCommonRateControlMode_CBR;
      *knobs += codec->SetValue(&CODECAPI_AVEncCommonRateControlMode,
                                &rate_control) == S_OK
                    ? " cbr=ok"
                    : " cbr=no";
      VariantClear(&rate_control);
      VARIANT mean_bit_rate;
      VariantInit(&mean_bit_rate);
      mean_bit_rate.vt = VT_UI4;
      mean_bit_rate.ulVal =
          static_cast<UINT32>(state->config.bitrate_bits_per_second);
      codec->SetValue(&CODECAPI_AVEncCommonMeanBitRate, &mean_bit_rate);
      VariantClear(&mean_bit_rate);
    }
  }

  // Output first: the H.264 MFT refuses an input type until it knows what it
  // is producing.
  ComPtr<IMFMediaType> output;
  HRESULT hr = MFCreateMediaType(&output);
  if (FAILED(hr)) return hr;
  output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  output->SetUINT32(MF_MT_AVG_BITRATE,
                    static_cast<UINT32>(state->config.bitrate_bits_per_second));
  MFSetAttributeSize(output.Get(), MF_MT_FRAME_SIZE,
                     static_cast<UINT32>(state->config.width),
                     static_cast<UINT32>(state->config.height));
  MFSetAttributeRatio(output.Get(), MF_MT_FRAME_RATE,
                      static_cast<UINT32>(state->config.frames_per_second), 1);
  MFSetAttributeRatio(output.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  output->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  // Baseline: every Discord client decodes it, and the constrained profiles
  // are what a screen share is expected to carry.
  output->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Base);
  hr = transform->SetOutputType(0, output.Get(), 0);
  if (FAILED(hr)) return hr;

  ComPtr<IMFMediaType> input;
  hr = MFCreateMediaType(&input);
  if (FAILED(hr)) return hr;
  input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  input->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
  MFSetAttributeSize(input.Get(), MF_MT_FRAME_SIZE,
                     static_cast<UINT32>(state->config.width),
                     static_cast<UINT32>(state->config.height));
  MFSetAttributeRatio(input.Get(), MF_MT_FRAME_RATE,
                      static_cast<UINT32>(state->config.frames_per_second), 1);
  input->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  hr = transform->SetInputType(0, input.Get(), 0);
  if (FAILED(hr)) return hr;

  if (*is_async) {
    ComPtr<IMFMediaEventGenerator> events;
    hr = transform->QueryInterface(IID_PPV_ARGS(&events));
    if (FAILED(hr)) return hr;
    state->encoder_events = events;
  }

  transform->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  transform->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  state->encoder = transform;
  if (has_codec) state->codec = codec;
  return S_OK;
}

std::string ToUtf8(const WCHAR* text) {
  const int length =
      WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (length <= 1) return std::string();
  std::string converted(static_cast<size_t>(length) - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, converted.data(), length, nullptr,
                      nullptr);
  return converted;
}

// True when an encoder MFT's friendly name is NVIDIA's. The vendor string,
// not a GUID: the enumeration is what tells us what this machine has, and the
// name is the only part of it that says whose silicon that is.
bool IsNvidiaEncoder(const std::string& name) {
  std::string lower = name;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return lower.find("nvidia") != std::string::npos;
}

// The vendor encoders a GPU driver registers (NVIDIA's NVENC, AMD's and
// Intel's equivalents), all as Media Foundation transforms speaking the same
// NV12-in, H.264-out contract as the software one. Picked by enumeration
// rather than by vendor GUID, so the same code path runs on every machine.
//
// NVIDIA first when present: a machine can carry two drivers' encoders (AMD's
// registers itself even when no display hangs off that silicon), the
// enumeration order is registration order rather than any quality ranking,
// and a stream meant to replace Discord wants the better encoder at a given
// bitrate.
HRESULT TryConfigureHardwareEncoder(FlucordVideoEncoder* state) {
  MFT_REGISTER_TYPE_INFO output{};
  output.guidMajorType = MFMediaType_Video;
  output.guidSubtype = MFVideoFormat_H264;
  IMFActivate** activates = nullptr;
  UINT32 count = 0;
  HRESULT hr = MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER,
                         MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER,
                         nullptr, &output, &activates, &count);
  if (FAILED(hr)) return hr;
  if (count == 0) {
    CoTaskMemFree(activates);
    return MF_E_NOT_FOUND;
  }

  std::vector<std::string> names(count);
  for (UINT32 index = 0; index < count; ++index) {
    WCHAR* friendly = nullptr;
    UINT32 friendly_length = 0;
    if (SUCCEEDED(activates[index]->GetAllocatedString(
            MFT_FRIENDLY_NAME_Attribute, &friendly, &friendly_length)) &&
        friendly != nullptr) {
      names[index] = ToUtf8(friendly);
      CoTaskMemFree(friendly);
    }
  }
  const bool has_nvidia =
      std::any_of(names.begin(), names.end(), IsNvidiaEncoder);

  std::vector<UINT32> order(count);
  for (UINT32 index = 0; index < count; ++index) order[index] = index;
  std::stable_sort(order.begin(), order.end(),
                   [&](UINT32 a, UINT32 b) {
                     return IsNvidiaEncoder(names[a]) && !IsNvidiaEncoder(names[b]);
                   });

  hr = MF_E_NOT_FOUND;
  for (UINT32 step = 0; step < count; ++step) {
    const UINT32 index = order[step];
    ComPtr<IMFTransform> transform;
    if (FAILED(activates[index]->ActivateObject(IID_PPV_ARGS(&transform)))) {
      continue;
    }
    std::string knobs;
    bool is_async = false;
    if (SUCCEEDED(SetupEncoderTransform(state, transform.Get(), true,
                                        &is_async, &knobs))) {
      state->encoder_is_async = is_async;
      state->encoder_accepts_input = !is_async;
      state->encoder_name = "hardware: " + names[index] + knobs;
      if (has_nvidia && !IsNvidiaEncoder(names[index])) {
        // The one case this can print is an NVIDIA encoder that enumerated
        // but refused to configure: worth a line in the log, because "why
        // not NVENC" is the first question about a slower stream.
        state->encoder_name += " (nvidia present)";
      }
      hr = S_OK;
    } else {
      state->encoder_events.Reset();
      transform.Reset();
    }
    if (SUCCEEDED(hr)) break;
  }
  for (UINT32 index = 0; index < count; ++index) activates[index]->Release();
  CoTaskMemFree(activates);
  return hr;
}

HRESULT ConfigureSoftwareEncoder(FlucordVideoEncoder* state) {
  ComPtr<IMFTransform> transform;
  HRESULT hr = CoCreateInstance(CLSID_MSH264EncoderMFT, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&transform));
  if (FAILED(hr)) return hr;
  std::string knobs;
  bool is_async = false;
  hr = SetupEncoderTransform(state, transform.Get(), false, &is_async, &knobs);
  if (FAILED(hr)) return hr;
  state->encoder_is_async = false;
  state->encoder_accepts_input = true;
  state->encoder_name = "software: Microsoft H.264" + knobs;
  return S_OK;
}

// Hardware when the machine has it, software when it does not. The choice and
// what each encoder accepted end up in `encoder_name`, which is the whole
// difference between "NVENC is slow" and "there is no NVENC here".
HRESULT ConfigureEncoder(FlucordVideoEncoder* state) {
  if (SUCCEEDED(TryConfigureHardwareEncoder(state))) return S_OK;
  return ConfigureSoftwareEncoder(state);
}

// Finds the display at `index` across every adapter, and the adapter it
// hangs off.
//
// Not `device->GetAdapter()->EnumOutputs(index)`, which is what this used to
// do: on a laptop with switchable graphics the D3D device lands on the
// discrete GPU while the panel is wired to the integrated one, and that
// adapter reports no outputs at all. Every share failed with "that display is
// no longer attached" on exactly the machines that have two GPUs.
HRESULT FindOutput(int index, ComPtr<IDXGIAdapter1>* out_adapter,
                   ComPtr<IDXGIOutput1>* out_output) {
  ComPtr<IDXGIFactory1> factory;
  HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(hr)) return hr;

  int seen = 0;
  for (UINT adapter_index = 0;; ++adapter_index) {
    ComPtr<IDXGIAdapter1> adapter;
    if (factory->EnumAdapters1(adapter_index, &adapter) ==
        DXGI_ERROR_NOT_FOUND) {
      break;
    }
    for (UINT output_index = 0;; ++output_index) {
      ComPtr<IDXGIOutput> output;
      if (adapter->EnumOutputs(output_index, &output) ==
          DXGI_ERROR_NOT_FOUND) {
        break;
      }
      DXGI_OUTPUT_DESC desc{};
      if (FAILED(output->GetDesc(&desc)) || !desc.AttachedToDesktop) continue;
      if (seen++ != index) continue;
      ComPtr<IDXGIOutput1> output1;
      hr = output.As(&output1);
      if (FAILED(hr)) return hr;
      *out_adapter = adapter;
      *out_output = output1;
      return S_OK;
    }
  }
  return DXGI_ERROR_NOT_FOUND;
}

// The platform's own answer to whatever failed last, for diagnostics only,
// paired with the call that produced it. One HRESULT with no idea which of
// four calls returned it is a guess, and two rounds have been spent guessing.
std::atomic<int32_t> g_last_error{0};
std::atomic<int32_t> g_last_error_stage{0};

// The *first* refusal in an attempt, not the last. The fallback path refuses
// on the machines the fallback exists for, so recording every step meant the
// only one ever reported was the one that says the least.
void RecordFailure(int32_t stage, HRESULT hr) {
  int32_t expected = 0;
  if (!g_last_error_stage.compare_exchange_strong(expected, stage)) return;
  g_last_error.store(static_cast<int32_t>(hr));
}

void ClearFailure() {
  g_last_error_stage.store(0);
  g_last_error.store(0);
}

// Which call refused, reported alongside its HRESULT.
enum DuplicationStage {
  kStageFindOutput = 1,
  kStageCreateDevice = 2,
  kStageDuplicate = 3,
  kStageDuplicateOnOriginalDevice = 4,
  kStageEncodeInput = 5,
  kStageEncoderEvent = 6,
};

HRESULT OpenDuplication(FlucordVideoEncoder* state) {
  ClearFailure();
  ComPtr<IDXGIAdapter1> adapter;
  ComPtr<IDXGIOutput1> output;
  HRESULT hr = FindOutput(state->config.display_index, &adapter, &output);
  // A display index that is no longer there — a monitor unplugged between the
  // picker and the share — falls back to the primary rather than refusing.
  if (FAILED(hr) && state->config.display_index != 0) {
    hr = FindOutput(0, &adapter, &output);
  }
  if (FAILED(hr)) {
    RecordFailure(kStageFindOutput, hr);
    return hr;
  }

  // The device is rebuilt on the adapter that actually owns the display:
  // DuplicateOutput refuses a device from any other one.
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0,
                                      D3D_FEATURE_LEVEL_10_1};
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  hr = D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, 0,
                         levels, ARRAYSIZE(levels), D3D11_SDK_VERSION, &device,
                         nullptr, &context);
  if (SUCCEEDED(hr)) {
    hr = output->DuplicateOutput(device.Get(), &state->duplication);
    if (SUCCEEDED(hr)) {
      state->device = device;
      state->context = context;
      return S_OK;
    }
    RecordFailure(kStageDuplicate, hr);
  } else {
    RecordFailure(kStageCreateDevice, hr);
  }

  // The device this encoder was opened with is tried too. On a single-GPU
  // machine it is the same adapter, and a driver that refuses a second device
  // will still duplicate onto the first.
  HRESULT fallback = output->DuplicateOutput(state->device.Get(),
                                             &state->duplication);
  if (SUCCEEDED(fallback)) return S_OK;
  RecordFailure(kStageDuplicateOnOriginalDevice, fallback);
  return fallback;
}

// Hands one encoded sample to Dart. Ownership crosses over: the callee may be
// a Dart listener that runs long after this buffer would have been unlocked.
void DeliverEncodedSample(FlucordVideoEncoder* state, IMFSample* produced) {
  ComPtr<IMFMediaBuffer> contiguous;
  if (FAILED(produced->ConvertToContiguousBuffer(&contiguous))) return;
  BYTE* data = nullptr;
  DWORD length = 0;
  if (FAILED(contiguous->Lock(&data, nullptr, &length))) return;
  LONGLONG timestamp = 0;
  produced->GetSampleTime(&timestamp);
  auto* owned = static_cast<uint8_t*>(malloc(length));
  if (owned != nullptr) {
    memcpy(owned, data, length);
    state->callback(state->user_data, owned, static_cast<int32_t>(length),
                    timestamp / 10,  // 100ns units to microseconds.
                    IsKeyframe(produced) ? 1 : 0);
  }
  contiguous->Unlock();
}

// Takes one output from an asynchronous encoder, which it only produces in
// response to METransformHaveOutput and always allocates itself.
void ConsumeEncoderOutput(FlucordVideoEncoder* state) {
  MFT_OUTPUT_DATA_BUFFER out{};
  out.dwStreamID = 0;
  DWORD status = 0;
  const HRESULT hr = state->encoder->ProcessOutput(0, 1, &out, &status);
  if (out.pEvents != nullptr) out.pEvents->Release();
  if (FAILED(hr)) return;
  if (out.pSample != nullptr) {
    // The reference ProcessOutput handed over is adopted here and released
    // when the ComPtr goes away: anything else is a leak per frame.
    ComPtr<IMFSample> produced;
    produced = out.pSample;
    DeliverEncodedSample(state, produced.Get());
  }
}

// Moves an asynchronous encoder's events forward: everything it is holding is
// delivered, and its next request for input is remembered rather than
// answered, because the answer is the caller's next frame.
void PumpEncoderEvents(FlucordVideoEncoder* state) {
  if (!state->encoder_is_async) return;
  while (true) {
    ComPtr<IMFMediaEvent> event;
    if (FAILED(state->encoder_events->GetEvent(MF_EVENT_FLAG_NO_WAIT, &event))) {
      return;  // No events waiting; real errors surface the same way.
    }
    MediaEventType type = MEUnknown;
    event->GetType(&type);
    if (type == METransformNeedInput) {
      state->encoder_accepts_input = true;
      return;
    }
    if (type == METransformHaveOutput) {
      ConsumeEncoderOutput(state);
      continue;
    }
    // Drain and marker events need no answer from a one-way encode.
  }
}

// Waits until an asynchronous encoder asks for input. The generator has no
// timed wait, so the wait is a poll; a hardware encoder takes single-digit
// milliseconds per 720p frame, and a deadline stops a wedged driver from
// freezing the capture.
bool AwaitEncoderInput(FlucordVideoEncoder* state, int64_t deadline_ns) {
  while (!state->encoder_accepts_input) {
    if (NowNs() >= deadline_ns) return false;
    ComPtr<IMFMediaEvent> event;
    if (SUCCEEDED(state->encoder_events->GetEvent(MF_EVENT_FLAG_NO_WAIT,
                                                  &event))) {
      MediaEventType type = MEUnknown;
      event->GetType(&type);
      if (type == METransformNeedInput) {
        state->encoder_accepts_input = true;
      } else if (type == METransformHaveOutput) {
        ConsumeEncoderOutput(state);
      }
    } else {
      Sleep(1);
    }
  }
  return true;
}

// A hardware encoder that failed mid-stream is replaced by the software one,
// once. The alternative is a frozen share over a driver hiccup.
void RecoverEncoder(FlucordVideoEncoder* state) {
  if (state->encoder_rebuilt_as_software) return;
  state->encoder_rebuilt_as_software = true;
  state->encoder.Reset();
  state->encoder_events.Reset();
  state->codec.Reset();
  state->encoder_is_async = false;
  state->encoder_accepts_input = true;
  if (SUCCEEDED(ConfigureSoftwareEncoder(state))) {
    state->encoder_name += " (fell back mid-stream)";
    state->keyframe_requested.store(true);
  }
}

void DrainEncoder(FlucordVideoEncoder* state) {
  MFT_OUTPUT_STREAM_INFO info{};
  if (FAILED(state->encoder->GetOutputStreamInfo(0, &info))) return;

  while (true) {
    ComPtr<IMFSample> sample;
    ComPtr<IMFMediaBuffer> buffer;
    const bool allocates =
        (info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES |
                         MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;
    if (!allocates) {
      if (FAILED(MFCreateSample(&sample))) return;
      if (FAILED(MFCreateMemoryBuffer(info.cbSize, &buffer))) return;
      sample->AddBuffer(buffer.Get());
    }

    MFT_OUTPUT_DATA_BUFFER out{};
    out.dwStreamID = 0;
    out.pSample = allocates ? nullptr : sample.Get();
    DWORD status = 0;
    const HRESULT hr = state->encoder->ProcessOutput(0, 1, &out, &status);
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) return;
    if (FAILED(hr)) return;

    ComPtr<IMFSample> produced;
    if (allocates) {
      // The reference ProcessOutput handed over is adopted here; the ComPtr
      // releases it. An explicit pair around it is one leak per frame.
      produced = out.pSample;
    } else {
      produced = sample;
    }
    if (out.pEvents != nullptr) out.pEvents->Release();
    if (produced) {
      DeliverEncodedSample(state, produced.Get());
    }
  }
}

// The platform's one-shot "make the next picture an IDR". One side of the
// pair around ProcessInput: a value left set is, on some vendors, a request
// for every picture after it as well.
void RequestKeyframeBegin(FlucordVideoEncoder* state) {
  ICodecAPI* codec = state->codec.Get();
  if (codec == nullptr) return;
  VARIANT value;
  VariantInit(&value);
  value.vt = VT_UI4;
  value.ulVal = 1;
  codec->SetValue(&CODECAPI_AVEncVideoForceKeyFrame, &value);
  VariantClear(&value);
}

void RequestKeyframeEnd(FlucordVideoEncoder* state) {
  ICodecAPI* codec = state->codec.Get();
  if (codec == nullptr) return;
  VARIANT value;
  VariantInit(&value);
  value.vt = VT_UI4;
  value.ulVal = 0;
  codec->SetValue(&CODECAPI_AVEncVideoForceKeyFrame, &value);
  VariantClear(&value);
}

void EncodeNv12(FlucordVideoEncoder* state,
                const uint8_t* nv12,
                size_t nv12_size,
                int64_t timestamp_us) {
  ComPtr<IMFMediaBuffer> buffer;
  if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(nv12_size), &buffer))) {
    return;
  }
  BYTE* target = nullptr;
  if (FAILED(buffer->Lock(&target, nullptr, nullptr))) return;
  memcpy(target, nv12, nv12_size);
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(nv12_size));

  ComPtr<IMFSample> sample;
  if (FAILED(MFCreateSample(&sample))) return;
  sample->AddBuffer(buffer.Get());
  sample->SetSampleTime(timestamp_us * 10);
  sample->SetSampleDuration(10000000 / state->config.frames_per_second);

  std::lock_guard<std::mutex> guard(state->encoder_lock);
  if (state->encoder_is_async) {
    // Deliver what the last submission produced before offering more.
    PumpEncoderEvents(state);
    if (!state->encoder_accepts_input &&
        !AwaitEncoderInput(state, NowNs() + 50000000)) {
      return;  // Still busy after 50 ms: the frame is dropped, not queued.
    }
    state->encoder_accepts_input = false;
  }
  const bool force_keyframe = state->keyframe_requested.exchange(false);
  if (force_keyframe) {
    // A viewer who joined midway decodes nothing until one of these.
    RequestKeyframeBegin(state);
    sample->SetUINT32(MFSampleExtension_CleanPoint, 1);
  }
  const HRESULT hr = state->encoder->ProcessInput(0, sample.Get(), 0);
  if (force_keyframe) RequestKeyframeEnd(state);
  if (FAILED(hr)) {
    RecordFailure(kStageEncodeInput, hr);
    RecoverEncoder(state);
    return;
  }
  if (state->encoder_is_async) {
    PumpEncoderEvents(state);
  } else {
    DrainEncoder(state);
  }
}

// Converts a BGRA frame into the encoder's NV12, in place in `state->nv12`.
// Conversion and encoding are separate steps because a paced capture may
// hold the converted frame for the still repeats that follow.
void ConvertToNv12(FlucordVideoEncoder* state,
                   const uint8_t* bgra,
                   int stride,
                   int source_width,
                   int source_height) {
  const size_t nv12_size =
      static_cast<size_t>(state->config.width) * state->config.height * 3 / 2;
  if (state->nv12.size() != nv12_size) state->nv12.resize(nv12_size);
  if (source_width == state->config.width &&
      source_height == state->config.height) {
    BgraToNv12(bgra, stride, source_width, source_height, state->nv12.data());
  } else {
    BgraToNv12Scaled(bgra, stride, source_width, source_height,
                     state->config.width, state->config.height,
                     state->nv12.data());
  }
}

// Enumerates the attached cameras. The caller owns every activate it takes.
HRESULT EnumerateCameras(IMFActivate*** out_devices, UINT32* out_count) {
  ComPtr<IMFAttributes> attributes;
  HRESULT hr = MFCreateAttributes(&attributes, 1);
  if (FAILED(hr)) return hr;
  hr = attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                           MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr)) return hr;
  return MFEnumDeviceSources(attributes.Get(), out_devices, out_count);
}

HRESULT OpenCameraReader(FlucordVideoEncoder* state) {
  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  HRESULT hr = EnumerateCameras(&devices, &count);
  if (FAILED(hr)) return hr;
  if (state->config.display_index < 0 ||
      static_cast<UINT32>(state->config.display_index) >= count) {
    for (UINT32 index = 0; index < count; ++index) devices[index]->Release();
    CoTaskMemFree(devices);
    return MF_E_NOT_FOUND;
  }

  ComPtr<IMFMediaSource> source;
  hr = devices[state->config.display_index]->ActivateObject(
      IID_PPV_ARGS(&source));
  for (UINT32 index = 0; index < count; ++index) devices[index]->Release();
  CoTaskMemFree(devices);
  if (FAILED(hr)) return hr;

  ComPtr<IMFAttributes> attributes;
  hr = MFCreateAttributes(&attributes, 1);
  if (FAILED(hr)) return hr;
  // Without this the reader will only hand back what the camera natively
  // produces, and a webcam that speaks MJPEG or YUY2 would need a converter
  // written here for every format it might pick.
  attributes->SetUINT32(MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING,
                        TRUE);
  hr = MFCreateSourceReaderFromMediaSource(source.Get(), attributes.Get(),
                                           &state->reader);
  if (FAILED(hr)) return hr;

  ComPtr<IMFMediaType> type;
  hr = MFCreateMediaType(&type);
  if (FAILED(hr)) return hr;
  type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
  MFSetAttributeSize(type.Get(), MF_MT_FRAME_SIZE,
                     static_cast<UINT32>(state->config.width),
                     static_cast<UINT32>(state->config.height));
  MFSetAttributeRatio(type.Get(), MF_MT_FRAME_RATE,
                      static_cast<UINT32>(state->config.frames_per_second), 1);
  hr = state->reader->SetCurrentMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
      type.Get());
  if (FAILED(hr)) {
    // The camera would not take the exact size asked for. NV12 alone is
    // enough — the reader scales — so the size is dropped rather than the
    // whole request.
    ComPtr<IMFMediaType> fallback;
    if (FAILED(MFCreateMediaType(&fallback))) return hr;
    fallback->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    fallback->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    hr = state->reader->SetCurrentMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
        fallback.Get());
    if (FAILED(hr)) return hr;
  }
  return state->reader->SetStreamSelection(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), TRUE);
}

void CameraLoop(FlucordVideoEncoder* state) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const size_t nv12_size =
      static_cast<size_t>(state->config.width) * state->config.height * 3 / 2;
  const auto started = GetTickCount64();

  while (state->running.load()) {
    DWORD stream_index = 0;
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    ComPtr<IMFSample> sample;
    const HRESULT hr = state->reader->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0,
        &stream_index, &flags, &timestamp, &sample);
    if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0) break;
    // A read with no sample is the reader saying "nothing yet", not an end:
    // dropping out here would stop the camera on the first slow frame.
    if (!sample || state->paused.load()) continue;

    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) continue;
    BYTE* data = nullptr;
    DWORD length = 0;
    if (FAILED(buffer->Lock(&data, nullptr, &length))) continue;
    if (length >= nv12_size) {
      EncodeNv12(state, data, nv12_size,
                 timestamp != 0
                     ? timestamp / 10
                     : static_cast<int64_t>(GetTickCount64() - started) * 1000);
    }
    buffer->Unlock();
  }
  CoUninitialize();
}

// Scales and colour-converts on the GPU with the Direct3D video processor.
//
// The desktop arrives as a full-resolution BGRA texture; converting it on the
// CPU meant reading every byte of it back (14 MB a frame at 1440p), scaling
// pixel by pixel, and only then encoding. This keeps the resize on the GPU
// and brings back the encoder's own NV12, 1.8 MB at 720p.
struct GpuScaler {
  bool Create(ID3D11Device* d3d,
              ID3D11DeviceContext* immediate,
              int source_width,
              int source_height,
              int width,
              int height) {
    Reset();
    // The video interfaces are their own, not bases of the plain ones, so
    // both are held: the video context drives the processor, the immediate
    // one does the copy and the readback map.
    this->immediate = immediate;
    if (FAILED(d3d->QueryInterface(IID_PPV_ARGS(&device))) ||
        FAILED(immediate->QueryInterface(IID_PPV_ARGS(&context)))) {
      Reset();
      return false;
    }

    D3D11_VIDEO_PROCESSOR_CONTENT_DESC content{};
    content.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    content.InputWidth = static_cast<UINT>(source_width);
    content.InputHeight = static_cast<UINT>(source_height);
    content.OutputWidth = static_cast<UINT>(width);
    content.OutputHeight = static_cast<UINT>(height);
    content.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
    if (FAILED(device->CreateVideoProcessorEnumerator(&content, &enumerator)) ||
        FAILED(device->CreateVideoProcessor(enumerator.Get(), 0, &processor))) {
      Reset();
      return false;
    }
    context->VideoProcessorSetStreamFrameFormat(
        processor.Get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);

    // Full-range RGB in (a desktop is 0-255), BT.601 studio out: the same
    // numbers the CPU converter produces, so the colours do not move between
    // the two paths.
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE input{};
    input.Usage = 0;
    input.RGB_Range = 0;
    context->VideoProcessorSetStreamColorSpace(processor.Get(), 0, &input);
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE output{};
    output.Usage = 0;
    output.YCbCr_Matrix = 0;  // BT.601
    output.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
    context->VideoProcessorSetOutputColorSpace(processor.Get(), &output);

    D3D11_TEXTURE2D_DESC nv12{};
    nv12.Width = static_cast<UINT>(width);
    nv12.Height = static_cast<UINT>(height);
    nv12.MipLevels = 1;
    nv12.ArraySize = 1;
    nv12.Format = DXGI_FORMAT_NV12;
    nv12.SampleDesc.Count = 1;
    nv12.Usage = D3D11_USAGE_DEFAULT;
    // What an output view is required to be created from.
    nv12.BindFlags = D3D11_BIND_RENDER_TARGET;
    if (FAILED(d3d->CreateTexture2D(&nv12, nullptr, &target))) {
      Reset();
      return false;
    }
    nv12.Usage = D3D11_USAGE_STAGING;
    nv12.BindFlags = 0;
    nv12.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    nv12.MiscFlags = 0;
    if (FAILED(d3d->CreateTexture2D(&nv12, nullptr, &readback))) {
      Reset();
      return false;
    }

    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC view{};
    view.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
    if (FAILED(device->CreateVideoProcessorOutputView(target.Get(),
                                                      enumerator.Get(), &view,
                                                      &target_view))) {
      Reset();
      return false;
    }

    this->source_width = source_width;
    this->source_height = source_height;
    this->width = width;
    this->height = height;
    return true;
  }

  bool Matches(int source_width, int source_height) const {
    return device != nullptr && this->source_width == source_width &&
           this->source_height == source_height;
  }

  // Converts one desktop texture into `nv12` (width * height * 3 / 2 bytes,
  // tightly packed). Blocking: the readback map waits for the GPU.
  bool Convert(ID3D11Texture2D* desktop, uint8_t* nv12) {
    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC input{};
    input.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
    ComPtr<ID3D11VideoProcessorInputView> desktop_view;
    if (FAILED(device->CreateVideoProcessorInputView(
            desktop, enumerator.Get(), &input, &desktop_view))) {
      return false;
    }

    D3D11_VIDEO_PROCESSOR_STREAM stream{};
    stream.Enable = TRUE;
    stream.pInputSurface = desktop_view.Get();
    if (FAILED(context->VideoProcessorBlt(processor.Get(), target_view.Get(),
                                          0, 1, &stream))) {
      return false;
    }
    immediate->CopyResource(readback.Get(), target.Get());

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(immediate->Map(readback.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
      return false;
    }
    const uint8_t* luma = static_cast<const uint8_t*>(mapped.pData);
    const uint8_t* chroma =
        luma + static_cast<size_t>(mapped.RowPitch) * height;
    uint8_t* out_luma = nv12;
    uint8_t* out_chroma = nv12 + static_cast<size_t>(width) * height;
    for (int y = 0; y < height; ++y) {
      memcpy(out_luma + static_cast<size_t>(y) * width,
             luma + static_cast<size_t>(y) * mapped.RowPitch, width);
    }
    for (int y = 0; y < height / 2; ++y) {
      memcpy(out_chroma + static_cast<size_t>(y) * width,
             chroma + static_cast<size_t>(y) * mapped.RowPitch, width);
    }
    immediate->Unmap(readback.Get(), 0);
    return true;
  }

  void Reset() {
    device.Reset();
    context.Reset();
    immediate.Reset();
    enumerator.Reset();
    processor.Reset();
    target.Reset();
    readback.Reset();
    target_view.Reset();
    source_width = 0;
    source_height = 0;
  }

  ComPtr<ID3D11VideoDevice> device;
  ComPtr<ID3D11VideoContext> context;
  ComPtr<ID3D11DeviceContext> immediate;
  ComPtr<ID3D11VideoProcessorEnumerator> enumerator;
  ComPtr<ID3D11VideoProcessor> processor;
  ComPtr<ID3D11Texture2D> target;
  ComPtr<ID3D11Texture2D> readback;
  ComPtr<ID3D11VideoProcessorOutputView> target_view;
  int source_width = 0;
  int source_height = 0;
  int width = 0;
  int height = 0;
};

void CaptureLoop(FlucordVideoEncoder* state) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const int frame_interval_ms = 1000 / state->config.frames_per_second;
  const int64_t frame_interval_ns =
      1000000000 / state->config.frames_per_second;
  const int64_t started_ns = NowNs();
  const int width = state->config.width;
  const int height = state->config.height;
  const size_t nv12_size =
      static_cast<size_t>(width) * height * 3 / 2;

  // Encoding is capped at the configured frame rate. A desktop can change far
  // faster than a share carries — 60 Hz, 144 Hz — and spending the encoder
  // and the bitrate on frames the viewers will never see only starves the
  // ones they would. The same gate holds back the conversion: reading a
  // desktop back that nobody will encode is pure waste.
  //
  // Measured on the performance counter: the tick counter steps in ~15 ms
  // chunks, and on a 60 Hz display "32 ms since the last encode" rounds into
  // "not yet 33", skipping a whole extra frame. That was 20 frames/s at a
  // configured 30.
  int64_t last_encode_ns = 0;
  const auto encode_due = [&](int64_t now) {
    if (last_encode_ns != 0 && now - last_encode_ns < frame_interval_ns) {
      return false;
    }
    last_encode_ns = now;
    return true;
  };

  // The GPU path, taken unless the driver has no video processor to offer.
  // `gpu_available` is sticky: one refusal moves the capture to the CPU
  // converter for good, because a scaler that works every other frame is
  // worse than either path alone.
  GpuScaler gpu;
  bool gpu_available = true;
  bool have_nv12 = false;

  // The CPU path's readback surface, rebuilt only when the desktop resizes
  // rather than per frame.
  ComPtr<ID3D11Texture2D> staging;
  int staging_width = 0;
  int staging_height = 0;

  while (state->running.load()) {
    if (state->paused.load()) {
      Sleep(static_cast<DWORD>(frame_interval_ms));
      continue;
    }
    const int64_t wait_started = NowNs();
    DXGI_OUTDUPL_FRAME_INFO info{};
    ComPtr<IDXGIResource> resource;
    HRESULT hr = state->duplication->AcquireNextFrame(
        static_cast<UINT>(frame_interval_ms), &info, &resource);
    state->capture_wait_ns.fetch_add(NowNs() - wait_started);
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
      // Nothing changed on screen — which is most of the time, because a
      // desktop only produces a frame when a pixel moves. Discord expects a
      // stream regardless: a viewer who joins a still screen and is sent
      // nothing sees black until somebody wiggles a window. The last
      // converted picture goes out again instead, and the encoder's skip
      // frames for it cost almost nothing.
      if (have_nv12 && !state->nv12.empty() && encode_due(NowNs())) {
        const int64_t encode_started = NowNs();
        EncodeNv12(state, state->nv12.data(), nv12_size,
                   (NowNs() - started_ns) / 1000);
        state->encode_ns.fetch_add(NowNs() - encode_started);
        state->timed_frames.fetch_add(1);
      }
      continue;
    }
    if (FAILED(hr)) break;

    ComPtr<ID3D11Texture2D> texture;
    if (SUCCEEDED(resource.As(&texture)) && encode_due(NowNs())) {
      D3D11_TEXTURE2D_DESC desc{};
      texture->GetDesc(&desc);

      const int64_t convert_started = NowNs();
      bool converted = false;
      if (gpu_available) {
        if (!gpu.Matches(static_cast<int>(desc.Width),
                         static_cast<int>(desc.Height))) {
          gpu_available = gpu.Create(state->device.Get(), state->context.Get(),
                                     static_cast<int>(desc.Width),
                                     static_cast<int>(desc.Height), width,
                                     height);
          if (!gpu_available) gpu.Reset();
        }
        if (gpu_available) {
          if (state->nv12.size() != nv12_size) {
            state->nv12.resize(nv12_size);
          }
          converted = gpu.Convert(texture.Get(), state->nv12.data());
          if (!converted) {
            gpu_available = false;
            gpu.Reset();
          }
        }
      }
      if (!converted) {
        // The CPU path: read the desktop back whole and convert it here.
        if (staging == nullptr || staging_width != static_cast<int>(desc.Width) ||
            staging_height != static_cast<int>(desc.Height)) {
          D3D11_TEXTURE2D_DESC staging_desc = desc;
          staging_desc.Usage = D3D11_USAGE_STAGING;
          staging_desc.BindFlags = 0;
          staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
          staging_desc.MiscFlags = 0;
          staging.Reset();
          if (SUCCEEDED(state->device->CreateTexture2D(&staging_desc, nullptr,
                                                       &staging))) {
            staging_width = static_cast<int>(desc.Width);
            staging_height = static_cast<int>(desc.Height);
          } else {
            staging.Reset();
          }
        }
        if (staging != nullptr) {
          state->context->CopyResource(staging.Get(), texture.Get());
          D3D11_MAPPED_SUBRESOURCE mapped{};
          if (SUCCEEDED(state->context->Map(staging.Get(), 0, D3D11_MAP_READ, 0,
                                            &mapped))) {
            ConvertToNv12(state, static_cast<const uint8_t*>(mapped.pData),
                          static_cast<int>(mapped.RowPitch),
                          static_cast<int>(desc.Width),
                          static_cast<int>(desc.Height));
            converted = true;
            state->context->Unmap(staging.Get(), 0);
          }
        }
      }
      state->convert_ns.fetch_add(NowNs() - convert_started);

      if (converted) {
        have_nv12 = true;
        const int64_t encode_started = NowNs();
        EncodeNv12(state, state->nv12.data(), nv12_size,
                   (NowNs() - started_ns) / 1000);
        state->encode_ns.fetch_add(NowNs() - encode_started);
        state->timed_frames.fetch_add(1);
      }
    }
    state->duplication->ReleaseFrame();
  }
  CoUninitialize();
}

}  // namespace


struct FlucordVideoClip {
  ComPtr<IMFSinkWriter> writer;
  DWORD stream = 0;
  int32_t frames_per_second = 30;
};

struct FlucordVideoDecoder {
  ComPtr<IMFTransform> transform;
  FlucordVideoPictureCallback callback = nullptr;
  void* user_data = nullptr;
  std::vector<uint8_t> bgra;
  int32_t width = 0;
  int32_t height = 0;
};

namespace {

// NV12 is what the decoder hands back; a texture wants BGRA, and the two are
// far enough apart that nothing downstream would accept the wrong one.
void Nv12ToBgra(const uint8_t* source,
                int source_stride,
                int width,
                int height,
                uint8_t* destination) {
  const uint8_t* luma = source;
  const uint8_t* chroma = source + static_cast<size_t>(source_stride) * height;
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const int c = luma[static_cast<size_t>(y) * source_stride + x] - 16;
      const size_t chroma_index =
          static_cast<size_t>(y / 2) * source_stride + (x & ~1);
      const int u = chroma[chroma_index] - 128;
      const int v = chroma[chroma_index + 1] - 128;
      const int r = (298 * c + 409 * v + 128) >> 8;
      const int g = (298 * c - 100 * u - 208 * v + 128) >> 8;
      const int b = (298 * c + 516 * u + 128) >> 8;
      uint8_t* pixel = destination + (static_cast<size_t>(y) * width + x) * 4;
      pixel[0] = static_cast<uint8_t>(b < 0 ? 0 : (b > 255 ? 255 : b));
      pixel[1] = static_cast<uint8_t>(g < 0 ? 0 : (g > 255 ? 255 : g));
      pixel[2] = static_cast<uint8_t>(r < 0 ? 0 : (r > 255 ? 255 : r));
      pixel[3] = 255;
    }
  }
}

void ReadDecoderSize(FlucordVideoDecoder* decoder) {
  ComPtr<IMFMediaType> type;
  if (FAILED(decoder->transform->GetOutputCurrentType(0, &type))) return;
  UINT32 width = 0;
  UINT32 height = 0;
  if (SUCCEEDED(
          MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &width, &height))) {
    decoder->width = static_cast<int32_t>(width);
    decoder->height = static_cast<int32_t>(height);
  }
}

void TakeAvailableOutputType(FlucordVideoDecoder* decoder) {
  ComPtr<IMFMediaType> type;
  for (DWORD index = 0;
       SUCCEEDED(decoder->transform->GetOutputAvailableType(0, index, &type));
       ++index) {
    if (SUCCEEDED(decoder->transform->SetOutputType(0, type.Get(), 0))) {
      ReadDecoderSize(decoder);
      return;
    }
    type.Reset();
  }
}

void DrainDecoder(FlucordVideoDecoder* decoder, int64_t timestamp_us) {
  while (true) {
    MFT_OUTPUT_STREAM_INFO info{};
    decoder->transform->GetOutputStreamInfo(0, &info);
    const bool allocates =
        (info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES |
                         MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;
    ComPtr<IMFSample> sample;
    ComPtr<IMFMediaBuffer> buffer;
    if (!allocates) {
      if (FAILED(MFCreateSample(&sample))) return;
      if (FAILED(MFCreateMemoryBuffer(info.cbSize, &buffer))) return;
      sample->AddBuffer(buffer.Get());
    }

    MFT_OUTPUT_DATA_BUFFER out{};
    out.pSample = allocates ? nullptr : sample.Get();
    DWORD status = 0;
    const HRESULT hr = decoder->transform->ProcessOutput(0, 1, &out, &status);
    if (out.pEvents != nullptr) out.pEvents->Release();
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) return;
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
      // The decoder has read the parameter sets and is restating its output.
      TakeAvailableOutputType(decoder);
      continue;
    }
    if (FAILED(hr)) return;

    ComPtr<IMFSample> produced = allocates ? out.pSample : sample;
    if (!produced) return;
    if (decoder->width <= 0 || decoder->height <= 0) ReadDecoderSize(decoder);

    ComPtr<IMFMediaBuffer> contiguous;
    if (SUCCEEDED(produced->ConvertToContiguousBuffer(&contiguous)) &&
        decoder->width > 0 && decoder->height > 0) {
      BYTE* data = nullptr;
      DWORD length = 0;
      if (SUCCEEDED(contiguous->Lock(&data, nullptr, &length))) {
        const size_t needed =
            static_cast<size_t>(decoder->width) * decoder->height * 4;
        if (decoder->bgra.size() != needed) decoder->bgra.resize(needed);
        Nv12ToBgra(data, decoder->width, decoder->width, decoder->height,
                   decoder->bgra.data());
        LONGLONG sample_time = 0;
        produced->GetSampleTime(&sample_time);
        decoder->callback(decoder->user_data, decoder->bgra.data(),
                          decoder->width, decoder->height, decoder->width * 4,
                          sample_time != 0 ? sample_time / 10 : timestamp_us);
        contiguous->Unlock();
      }
    }
    if (allocates && out.pSample != nullptr) out.pSample->Release();
  }
}

}  // namespace

extern "C" {

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_decoder_open(FlucordVideoPictureCallback callback,
                           void* user_data,
                           FlucordVideoDecoder** out_decoder) {
  if (callback == nullptr || out_decoder == nullptr) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    return FLUCORD_VIDEO_ERROR_UNSUPPORTED;
  }

  auto decoder = std::make_unique<FlucordVideoDecoder>();
  decoder->callback = callback;
  decoder->user_data = user_data;

  HRESULT hr =
      CoCreateInstance(CLSID_MSH264DecoderMFT, nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(&decoder->transform));
  if (FAILED(hr)) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_UNSUPPORTED;
  }

  ComPtr<IMFMediaType> input;
  MFCreateMediaType(&input);
  input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  input->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  input->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  hr = decoder->transform->SetInputType(0, input.Get(), 0);
  if (FAILED(hr)) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }
  TakeAvailableOutputType(decoder.get());
  decoder->transform->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  *out_decoder = decoder.release();
  return FLUCORD_VIDEO_OK;
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_decoder_submit(FlucordVideoDecoder* decoder,
                             const uint8_t* annex_b,
                             int32_t length,
                             int64_t timestamp_us) {
  if (decoder == nullptr || annex_b == nullptr || length <= 0) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  ComPtr<IMFMediaBuffer> buffer;
  if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(length), &buffer))) {
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }
  BYTE* target = nullptr;
  if (FAILED(buffer->Lock(&target, nullptr, nullptr))) {
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }
  memcpy(target, annex_b, static_cast<size_t>(length));
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(length));

  ComPtr<IMFSample> sample;
  if (FAILED(MFCreateSample(&sample))) return FLUCORD_VIDEO_ERROR_ENCODER;
  sample->AddBuffer(buffer.Get());
  sample->SetSampleTime(timestamp_us * 10);

  const HRESULT hr = decoder->transform->ProcessInput(0, sample.Get(), 0);
  if (FAILED(hr)) return FLUCORD_VIDEO_ERROR_ENCODER;
  DrainDecoder(decoder, timestamp_us);
  return FLUCORD_VIDEO_OK;
}

FLUCORD_VIDEO_EXPORT void flucord_video_decoder_close(
    FlucordVideoDecoder* decoder) {
  if (decoder == nullptr) return;
  if (decoder->transform) {
    decoder->transform->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
    decoder->transform->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
  }
  decoder->transform.Reset();
  delete decoder;
  MFShutdown();
}

}  // extern "C"

extern "C" {

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_open(const FlucordVideoConfig* config,
                   FlucordVideoFrameCallback callback,
                   void* user_data,
                   FlucordVideoEncoder** out_encoder) {
  if (config == nullptr || callback == nullptr || out_encoder == nullptr) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  if (config->width <= 0 || config->height <= 0 ||
      config->frames_per_second <= 0 || config->bitrate_bits_per_second <= 0) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }

  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) &&
      GetLastError() != 0) {
    // Already initialised on this thread is fine; anything else is not.
  }
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    return FLUCORD_VIDEO_ERROR_UNSUPPORTED;
  }

  auto state = std::make_unique<FlucordVideoEncoder>();
  state->config = *config;
  state->callback = callback;
  state->user_data = user_data;

  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0,
                                      D3D_FEATURE_LEVEL_10_1};
  HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
                                 levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                                 &state->device, nullptr, &state->context);
  if (FAILED(hr)) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_UNSUPPORTED;
  }

  hr = OpenDuplication(state.get());
  if (FAILED(hr)) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_NO_DISPLAY;
  }

  hr = ConfigureEncoder(state.get());
  if (FAILED(hr)) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }

  state->running.store(true);
  FlucordVideoEncoder* raw = state.release();
  raw->worker = std::thread(CaptureLoop, raw);
  *out_encoder = raw;
  return FLUCORD_VIDEO_OK;
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_open_camera(const FlucordVideoConfig* config,
                          FlucordVideoFrameCallback callback,
                          void* user_data,
                          FlucordVideoEncoder** out_encoder) {
  if (config == nullptr || callback == nullptr || out_encoder == nullptr) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  if (config->width <= 0 || config->height <= 0 ||
      config->frames_per_second <= 0 || config->bitrate_bits_per_second <= 0) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    return FLUCORD_VIDEO_ERROR_UNSUPPORTED;
  }

  auto state = std::make_unique<FlucordVideoEncoder>();
  state->config = *config;
  state->callback = callback;
  state->user_data = user_data;

  // No Direct3D device here: the camera path never touches the desktop, and
  // demanding a GPU would refuse a machine that can plainly run a webcam.
  if (FAILED(OpenCameraReader(state.get()))) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_NO_CAMERA;
  }
  if (FAILED(ConfigureEncoder(state.get()))) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }

  state->running.store(true);
  FlucordVideoEncoder* raw = state.release();
  raw->worker = std::thread(CameraLoop, raw);
  *out_encoder = raw;
  return FLUCORD_VIDEO_OK;
}

FLUCORD_VIDEO_EXPORT int32_t flucord_video_camera_count(void) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return 0;
  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  const HRESULT hr = EnumerateCameras(&devices, &count);
  if (SUCCEEDED(hr)) {
    for (UINT32 index = 0; index < count; ++index) devices[index]->Release();
    CoTaskMemFree(devices);
  }
  MFShutdown();
  return SUCCEEDED(hr) ? static_cast<int32_t>(count) : 0;
}

FLUCORD_VIDEO_EXPORT int32_t flucord_video_camera_name(int32_t index,
                                                       char* buffer,
                                                       int32_t capacity) {
  if (index < 0) return 0;
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return 0;
  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  if (FAILED(EnumerateCameras(&devices, &count))) {
    MFShutdown();
    return 0;
  }
  int32_t needed = 0;
  if (static_cast<UINT32>(index) < count) {
    WCHAR* name = nullptr;
    UINT32 name_length = 0;
    if (SUCCEEDED(devices[index]->GetAllocatedString(
            MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &name, &name_length))) {
      needed = WideCharToMultiByte(CP_UTF8, 0, name, -1, nullptr, 0, nullptr,
                                   nullptr);
      if (buffer != nullptr && capacity >= needed) {
        WideCharToMultiByte(CP_UTF8, 0, name, -1, buffer, capacity, nullptr,
                            nullptr);
      }
      CoTaskMemFree(name);
    }
  }
  for (UINT32 device = 0; device < count; ++device) devices[device]->Release();
  CoTaskMemFree(devices);
  MFShutdown();
  return needed;
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_request_keyframe(FlucordVideoEncoder* encoder) {
  if (encoder == nullptr) return FLUCORD_VIDEO_ERROR_STATE;
  encoder->keyframe_requested.store(true);
  return FLUCORD_VIDEO_OK;
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_set_paused(FlucordVideoEncoder* encoder, int32_t paused) {
  if (encoder == nullptr) return FLUCORD_VIDEO_ERROR_STATE;
  encoder->paused.store(paused != 0);
  // Resuming asks for a keyframe: whatever the viewers were holding is stale.
  if (paused == 0) encoder->keyframe_requested.store(true);
  return FLUCORD_VIDEO_OK;
}

FLUCORD_VIDEO_EXPORT void flucord_video_close(FlucordVideoEncoder* encoder) {
  if (encoder == nullptr) return;
  encoder->running.store(false);
  if (encoder->worker.joinable()) encoder->worker.join();
  if (encoder->encoder) {
    std::lock_guard<std::mutex> guard(encoder->encoder_lock);
    if (encoder->encoder_is_async) {
      // A hardware encoder hands back what it is still holding only once
      // asked to drain, and the last pictures of a stream are worth asking
      // for. Bounded, because a driver that never answers DrainComplete must
      // not hang the close.
      encoder->encoder->ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0);
      const int64_t deadline = NowNs() + 50000000;
      while (NowNs() < deadline) {
        ComPtr<IMFMediaEvent> event;
        if (FAILED(encoder->encoder_events->GetEvent(MF_EVENT_FLAG_NO_WAIT,
                                                     &event))) {
          break;
        }
        MediaEventType type = MEUnknown;
        event->GetType(&type);
        if (type == METransformHaveOutput) {
          ConsumeEncoderOutput(encoder);
        } else if (type == METransformDrainComplete) {
          break;
        }
      }
    }
    encoder->encoder->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
    encoder->encoder->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
  }
  encoder->duplication.Reset();
  encoder->reader.Reset();
  encoder->encoder.Reset();
  encoder->codec.Reset();
  encoder->encoder_events.Reset();
  encoder->context.Reset();
  encoder->device.Reset();
  delete encoder;
  MFShutdown();
}

FLUCORD_VIDEO_EXPORT int32_t flucord_video_encoder_name(
    FlucordVideoEncoder* encoder, char* buffer, int32_t capacity) {
  if (encoder == nullptr || buffer == nullptr || capacity <= 0) return 0;
  std::lock_guard<std::mutex> guard(encoder->encoder_lock);
  const int32_t length = static_cast<int32_t>(encoder->encoder_name.size());
  if (length > capacity - 1) return 0;
  memcpy(buffer, encoder->encoder_name.data(), length);
  buffer[length] = 0;
  return length;
}

FLUCORD_VIDEO_EXPORT void flucord_video_stage_timings(
    FlucordVideoEncoder* encoder, int64_t* out_values) {
  if (encoder == nullptr || out_values == nullptr) return;
  out_values[0] = encoder->capture_wait_ns.load();
  out_values[1] = encoder->convert_ns.load();
  out_values[2] = encoder->encode_ns.load();
  out_values[3] = encoder->timed_frames.load();
}

FLUCORD_VIDEO_EXPORT int32_t
flucord_video_decode_probe(const uint8_t* annex_b, int32_t length) {
  if (annex_b == nullptr || length <= 0) return -1;
  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) {
    // Already initialised on this thread is not a failure.
  }
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return -2;

  int32_t decoded = 0;
  {
    ComPtr<IMFTransform> decoder;
    HRESULT hr = CoCreateInstance(CLSID_MSH264DecoderMFT, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&decoder));
    if (SUCCEEDED(hr)) {
      ComPtr<IMFMediaType> input;
      MFCreateMediaType(&input);
      input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
      input->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
      input->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
      hr = decoder->SetInputType(0, input.Get(), 0);
    }
    if (SUCCEEDED(hr)) {
      // The decoder picks its own output type once it has seen the parameter
      // sets, so the first available one is taken rather than demanded.
      ComPtr<IMFMediaType> output;
      for (DWORD index = 0;
           SUCCEEDED(decoder->GetOutputAvailableType(0, index, &output));
           ++index) {
        if (SUCCEEDED(decoder->SetOutputType(0, output.Get(), 0))) break;
        output.Reset();
      }
      decoder->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);

      ComPtr<IMFMediaBuffer> buffer;
      if (SUCCEEDED(MFCreateMemoryBuffer(static_cast<DWORD>(length),
                                         &buffer))) {
        BYTE* target = nullptr;
        if (SUCCEEDED(buffer->Lock(&target, nullptr, nullptr))) {
          memcpy(target, annex_b, static_cast<size_t>(length));
          buffer->Unlock();
          buffer->SetCurrentLength(static_cast<DWORD>(length));

          ComPtr<IMFSample> sample;
          if (SUCCEEDED(MFCreateSample(&sample))) {
            sample->AddBuffer(buffer.Get());
            sample->SetSampleTime(0);
            if (SUCCEEDED(decoder->ProcessInput(0, sample.Get(), 0))) {
              decoder->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
              decoder->ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0);
              while (true) {
                MFT_OUTPUT_STREAM_INFO info{};
                decoder->GetOutputStreamInfo(0, &info);
                ComPtr<IMFSample> produced;
                ComPtr<IMFMediaBuffer> produced_buffer;
                const bool allocates =
                    (info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES |
                                     MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) !=
                    0;
                if (!allocates) {
                  if (FAILED(MFCreateSample(&produced))) break;
                  if (FAILED(MFCreateMemoryBuffer(info.cbSize,
                                                  &produced_buffer))) {
                    break;
                  }
                  produced->AddBuffer(produced_buffer.Get());
                }
                MFT_OUTPUT_DATA_BUFFER out{};
                out.pSample = allocates ? nullptr : produced.Get();
                DWORD status = 0;
                const HRESULT drained =
                    decoder->ProcessOutput(0, 1, &out, &status);
                if (out.pEvents != nullptr) out.pEvents->Release();
                if (drained == MF_E_TRANSFORM_NEED_MORE_INPUT) break;
                if (drained == MF_E_TRANSFORM_STREAM_CHANGE) {
                  // The decoder has read the parameter sets and wants to
                  // restate its output; taking the new type is what lets the
                  // pictures through.
                  ComPtr<IMFMediaType> changed;
                  for (DWORD index = 0;
                       SUCCEEDED(
                           decoder->GetOutputAvailableType(0, index, &changed));
                       ++index) {
                    if (SUCCEEDED(decoder->SetOutputType(0, changed.Get(), 0))) {
                      break;
                    }
                    changed.Reset();
                  }
                  continue;
                }
                if (FAILED(drained)) break;
                ++decoded;
                if (allocates && out.pSample != nullptr) out.pSample->Release();
              }
            }
          }
        }
      }
      decoder->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
    }
    if (FAILED(hr) && decoded == 0) decoded = -3;
  }

  MFShutdown();
  return decoded;
}

FLUCORD_VIDEO_EXPORT int32_t flucord_video_last_error(void) {
  return g_last_error.load();
}

FLUCORD_VIDEO_EXPORT int32_t flucord_video_last_error_stage(void) {
  return g_last_error_stage.load();
}

FLUCORD_VIDEO_EXPORT void flucord_video_release_frame(uint8_t* data) {
  free(data);
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_capture_screen(int32_t display_index,
                             FlucordVideoScreenshotCallback callback,
                             void* user_data) {
  if (callback == nullptr || display_index < 0) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);

  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0,
                                      D3D_FEATURE_LEVEL_10_1};
  if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
                               levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                               &device, nullptr, &context))) {
    return FLUCORD_VIDEO_ERROR_UNSUPPORTED;
  }

  ComPtr<IDXGIDevice> dxgi_device;
  ComPtr<IDXGIAdapter> adapter;
  ComPtr<IDXGIOutput> output;
  ComPtr<IDXGIOutput1> output1;
  ComPtr<IDXGIOutputDuplication> duplication;
  if (FAILED(device.As(&dxgi_device)) ||
      FAILED(dxgi_device->GetAdapter(&adapter)) ||
      FAILED(adapter->EnumOutputs(static_cast<UINT>(display_index), &output)) ||
      FAILED(output.As(&output1)) ||
      FAILED(output1->DuplicateOutput(device.Get(), &duplication))) {
    return FLUCORD_VIDEO_ERROR_NO_DISPLAY;
  }

  // The first frame after DuplicateOutput is often the accumulated difference
  // rather than the screen, so a few attempts are made before giving up: a
  // desktop nobody is touching produces no new frame at all.
  for (int attempt = 0; attempt < 30; ++attempt) {
    DXGI_OUTDUPL_FRAME_INFO info{};
    ComPtr<IDXGIResource> resource;
    const HRESULT hr = duplication->AcquireNextFrame(200, &info, &resource);
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) continue;
    if (FAILED(hr)) break;

    ComPtr<ID3D11Texture2D> texture;
    if (SUCCEEDED(resource.As(&texture))) {
      D3D11_TEXTURE2D_DESC desc{};
      texture->GetDesc(&desc);
      desc.Usage = D3D11_USAGE_STAGING;
      desc.BindFlags = 0;
      desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
      desc.MiscFlags = 0;

      ComPtr<ID3D11Texture2D> staging;
      if (SUCCEEDED(device->CreateTexture2D(&desc, nullptr, &staging))) {
        context->CopyResource(staging.Get(), texture.Get());
        D3D11_MAPPED_SUBRESOURCE mapped{};
        if (SUCCEEDED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0,
                                   &mapped))) {
          callback(user_data, static_cast<const uint8_t*>(mapped.pData),
                   static_cast<int32_t>(desc.Width),
                   static_cast<int32_t>(desc.Height),
                   static_cast<int32_t>(mapped.RowPitch));
          context->Unmap(staging.Get(), 0);
          duplication->ReleaseFrame();
          return FLUCORD_VIDEO_OK;
        }
      }
    }
    duplication->ReleaseFrame();
  }
  return FLUCORD_VIDEO_ERROR_NO_DISPLAY;
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_clip_open(const char* utf8_path,
                        int32_t width,
                        int32_t height,
                        int32_t frames_per_second,
                        int32_t bitrate_bits_per_second,
                        FlucordVideoClip** out_clip) {
  if (utf8_path == nullptr || out_clip == nullptr || width <= 0 ||
      height <= 0 || frames_per_second <= 0) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    return FLUCORD_VIDEO_ERROR_UNSUPPORTED;
  }

  const int wide_length =
      MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, nullptr, 0);
  if (wide_length <= 0) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  std::vector<wchar_t> path(static_cast<size_t>(wide_length));
  MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, path.data(), wide_length);

  auto clip = std::make_unique<FlucordVideoClip>();
  clip->frames_per_second = frames_per_second;
  if (FAILED(MFCreateSinkWriterFromURL(path.data(), nullptr, nullptr,
                                       &clip->writer))) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }

  // Output and input are both H.264: the frames arrive encoded, and the file
  // sink's job here is the container rather than the codec.
  ComPtr<IMFMediaType> type;
  if (FAILED(MFCreateMediaType(&type))) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }
  type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  type->SetUINT32(MF_MT_AVG_BITRATE,
                  static_cast<UINT32>(bitrate_bits_per_second > 0
                                          ? bitrate_bits_per_second
                                          : 2500000));
  MFSetAttributeSize(type.Get(), MF_MT_FRAME_SIZE,
                     static_cast<UINT32>(width),
                     static_cast<UINT32>(height));
  MFSetAttributeRatio(type.Get(), MF_MT_FRAME_RATE,
                      static_cast<UINT32>(frames_per_second), 1);
  MFSetAttributeRatio(type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);

  if (FAILED(clip->writer->AddStream(type.Get(), &clip->stream)) ||
      FAILED(clip->writer->SetInputMediaType(clip->stream, type.Get(),
                                             nullptr)) ||
      FAILED(clip->writer->BeginWriting())) {
    MFShutdown();
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }

  *out_clip = clip.release();
  return FLUCORD_VIDEO_OK;
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_clip_write(FlucordVideoClip* clip,
                         const uint8_t* annex_b,
                         int32_t length,
                         int64_t timestamp_us,
                         int32_t is_keyframe) {
  if (clip == nullptr || annex_b == nullptr || length <= 0) {
    return FLUCORD_VIDEO_ERROR_STATE;
  }
  ComPtr<IMFMediaBuffer> buffer;
  if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(length), &buffer))) {
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }
  BYTE* target = nullptr;
  if (FAILED(buffer->Lock(&target, nullptr, nullptr))) {
    return FLUCORD_VIDEO_ERROR_ENCODER;
  }
  memcpy(target, annex_b, static_cast<size_t>(length));
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(length));

  ComPtr<IMFSample> sample;
  if (FAILED(MFCreateSample(&sample))) return FLUCORD_VIDEO_ERROR_ENCODER;
  sample->AddBuffer(buffer.Get());
  sample->SetSampleTime(timestamp_us * 10);
  sample->SetSampleDuration(10000000 / clip->frames_per_second);
  if (is_keyframe != 0) sample->SetUINT32(MFSampleExtension_CleanPoint, 1);

  return SUCCEEDED(clip->writer->WriteSample(clip->stream, sample.Get()))
             ? FLUCORD_VIDEO_OK
             : FLUCORD_VIDEO_ERROR_ENCODER;
}

FLUCORD_VIDEO_EXPORT FlucordVideoStatus
flucord_video_clip_close(FlucordVideoClip* clip) {
  if (clip == nullptr) return FLUCORD_VIDEO_ERROR_STATE;
  const HRESULT hr = clip->writer ? clip->writer->Finalize() : E_FAIL;
  clip->writer.Reset();
  delete clip;
  MFShutdown();
  return SUCCEEDED(hr) ? FLUCORD_VIDEO_OK : FLUCORD_VIDEO_ERROR_ENCODER;
}

FLUCORD_VIDEO_EXPORT int32_t flucord_video_display_count(void) {
  // Across every adapter, matching what a capture actually enumerates. Only
  // adapter zero was counted before, which reports none at all on a laptop
  // whose panel hangs off the integrated GPU.
  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return 0;
  int32_t count = 0;
  for (UINT adapter_index = 0;; ++adapter_index) {
    ComPtr<IDXGIAdapter1> adapter;
    if (factory->EnumAdapters1(adapter_index, &adapter) ==
        DXGI_ERROR_NOT_FOUND) {
      break;
    }
    for (UINT output_index = 0;; ++output_index) {
      ComPtr<IDXGIOutput> output;
      if (adapter->EnumOutputs(output_index, &output) ==
          DXGI_ERROR_NOT_FOUND) {
        break;
      }
      DXGI_OUTPUT_DESC desc{};
      if (SUCCEEDED(output->GetDesc(&desc)) && desc.AttachedToDesktop) ++count;
    }
  }
  return count;
}

// Writes what DXGI reports about this machine's adapters and displays into
// [buffer], answering how many bytes were written.
//
// Diagnostics, and the only way to tell the ways "no display" can happen
// apart without a person at the keyboard describing their hardware.
FLUCORD_VIDEO_EXPORT int32_t flucord_video_describe_displays(char* buffer,
                                                             int32_t capacity) {
  if (buffer == nullptr || capacity <= 0) return 0;
  std::string text;
  ComPtr<IDXGIFactory1> factory;
  HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    text = "CreateDXGIFactory1 failed: 0x" + ToHex(hr) + "\n";
  } else {
    int display_index = 0;
    for (UINT adapter_index = 0;; ++adapter_index) {
      ComPtr<IDXGIAdapter1> adapter;
      if (factory->EnumAdapters1(adapter_index, &adapter) ==
          DXGI_ERROR_NOT_FOUND) {
        break;
      }
      DXGI_ADAPTER_DESC1 adapter_desc{};
      adapter->GetDesc1(&adapter_desc);
      text += "adapter " + std::to_string(adapter_index) + " luid=" +
              std::to_string(adapter_desc.AdapterLuid.LowPart) + " flags=" +
              std::to_string(adapter_desc.Flags) + "\n";
      for (UINT output_index = 0;; ++output_index) {
        ComPtr<IDXGIOutput> output;
        if (adapter->EnumOutputs(output_index, &output) ==
            DXGI_ERROR_NOT_FOUND) {
          break;
        }
        DXGI_OUTPUT_DESC desc{};
        if (FAILED(output->GetDesc(&desc))) continue;
        text += "  output " + std::to_string(output_index) +
                " attached=" + (desc.AttachedToDesktop ? "yes" : "no");
        if (desc.AttachedToDesktop) {
          text += " index=" + std::to_string(display_index++);
        }
        text += " rect=" + std::to_string(desc.DesktopCoordinates.right -
                                          desc.DesktopCoordinates.left) +
                "x" +
                std::to_string(desc.DesktopCoordinates.bottom -
                               desc.DesktopCoordinates.top);
        ComPtr<IDXGIOutput1> output1;
        text += output.As(&output1) == S_OK ? " output1=yes" : " output1=no";
        text += "\n";
      }
    }
  }
  const int32_t length =
      static_cast<int32_t>(text.size()) < capacity - 1
          ? static_cast<int32_t>(text.size())
          : capacity - 1;
  memcpy(buffer, text.data(), static_cast<size_t>(length));
  buffer[length] = 0;
  return length;
}

}  // extern "C"
