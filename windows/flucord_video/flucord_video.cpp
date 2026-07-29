#include "flucord_video.h"

#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#include <windows.h>

#include <codecapi.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mftransform.h>
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

bool IsKeyframe(IMFSample* sample) {
  UINT32 value = 0;
  return SUCCEEDED(sample->GetUINT32(MFSampleExtension_CleanPoint, &value)) &&
         value != 0;
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

  std::thread worker;
  std::atomic<bool> running{false};
  std::atomic<bool> paused{false};
  std::atomic<bool> keyframe_requested{true};
  std::mutex encoder_lock;

  std::vector<uint8_t> nv12;
};

namespace {

HRESULT ConfigureEncoder(FlucordVideoEncoder* state) {
  ComPtr<IMFTransform> transform;
  HRESULT hr = CoCreateInstance(CLSID_MSH264EncoderMFT, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&transform));
  if (FAILED(hr)) return hr;

  // Output first: the H.264 MFT refuses an input type until it knows what it
  // is producing.
  ComPtr<IMFMediaType> output;
  hr = MFCreateMediaType(&output);
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

  transform->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  transform->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  state->encoder = transform;
  return S_OK;
}

HRESULT OpenDuplication(FlucordVideoEncoder* state) {
  ComPtr<IDXGIDevice> dxgi_device;
  HRESULT hr = state->device.As(&dxgi_device);
  if (FAILED(hr)) return hr;

  ComPtr<IDXGIAdapter> adapter;
  hr = dxgi_device->GetAdapter(&adapter);
  if (FAILED(hr)) return hr;

  ComPtr<IDXGIOutput> output;
  hr = adapter->EnumOutputs(static_cast<UINT>(state->config.display_index),
                            &output);
  if (FAILED(hr)) return hr;

  ComPtr<IDXGIOutput1> output1;
  hr = output.As(&output1);
  if (FAILED(hr)) return hr;

  return output1->DuplicateOutput(state->device.Get(), &state->duplication);
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

    ComPtr<IMFSample> produced = allocates ? out.pSample : sample;
    if (allocates && out.pSample != nullptr) out.pSample->AddRef();
    if (out.pEvents != nullptr) out.pEvents->Release();
    if (!produced) return;

    ComPtr<IMFMediaBuffer> contiguous;
    if (SUCCEEDED(produced->ConvertToContiguousBuffer(&contiguous))) {
      BYTE* data = nullptr;
      DWORD length = 0;
      if (SUCCEEDED(contiguous->Lock(&data, nullptr, &length))) {
        LONGLONG timestamp = 0;
        produced->GetSampleTime(&timestamp);
        // Ownership is handed over: the callee may be a Dart listener that
        // runs long after this buffer would have been unlocked.
        auto* owned = static_cast<uint8_t*>(malloc(length));
        if (owned != nullptr) {
          memcpy(owned, data, length);
          state->callback(state->user_data, owned, static_cast<int32_t>(length),
                          timestamp / 10,  // 100ns units to microseconds.
                          IsKeyframe(produced.Get()) ? 1 : 0);
        }
        contiguous->Unlock();
      }
    }
    if (allocates && out.pSample != nullptr) out.pSample->Release();
  }
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
  if (state->keyframe_requested.exchange(false)) {
    // A viewer who joined midway decodes nothing until one of these.
    sample->SetUINT32(MFSampleExtension_CleanPoint, 1);
  }
  if (SUCCEEDED(state->encoder->ProcessInput(0, sample.Get(), 0))) {
    DrainEncoder(state);
  }
}

void EncodeFrame(FlucordVideoEncoder* state,
                 const uint8_t* bgra,
                 int stride,
                 int64_t timestamp_us) {
  const size_t nv12_size =
      static_cast<size_t>(state->config.width) * state->config.height * 3 / 2;
  if (state->nv12.size() != nv12_size) state->nv12.resize(nv12_size);
  BgraToNv12(bgra, stride, state->config.width, state->config.height,
             state->nv12.data());
  EncodeNv12(state, state->nv12.data(), nv12_size, timestamp_us);
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

void CaptureLoop(FlucordVideoEncoder* state) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const int frame_interval_ms = 1000 / state->config.frames_per_second;
  auto started = GetTickCount64();

  while (state->running.load()) {
    if (state->paused.load()) {
      Sleep(static_cast<DWORD>(frame_interval_ms));
      continue;
    }
    DXGI_OUTDUPL_FRAME_INFO info{};
    ComPtr<IDXGIResource> resource;
    HRESULT hr = state->duplication->AcquireNextFrame(
        static_cast<UINT>(frame_interval_ms), &info, &resource);
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
      // Nothing changed on screen. Discord expects frames anyway, so the last
      // one is re-sent rather than the stream stalling.
      continue;
    }
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
      if (SUCCEEDED(state->device->CreateTexture2D(&desc, nullptr, &staging))) {
        state->context->CopyResource(staging.Get(), texture.Get());
        D3D11_MAPPED_SUBRESOURCE mapped{};
        if (SUCCEEDED(state->context->Map(staging.Get(), 0, D3D11_MAP_READ, 0,
                                          &mapped))) {
          EncodeFrame(state, static_cast<const uint8_t*>(mapped.pData),
                      static_cast<int>(mapped.RowPitch),
                      static_cast<int64_t>(GetTickCount64() - started) * 1000);
          state->context->Unmap(staging.Get(), 0);
        }
      }
    }
    state->duplication->ReleaseFrame();
  }
  CoUninitialize();
}

}  // namespace


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
    encoder->encoder->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
    encoder->encoder->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
  }
  encoder->duplication.Reset();
  encoder->reader.Reset();
  encoder->encoder.Reset();
  encoder->context.Reset();
  encoder->device.Reset();
  delete encoder;
  MFShutdown();
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

FLUCORD_VIDEO_EXPORT void flucord_video_release_frame(uint8_t* data) {
  free(data);
}

FLUCORD_VIDEO_EXPORT int32_t flucord_video_display_count(void) {
  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return 0;
  ComPtr<IDXGIAdapter1> adapter;
  if (FAILED(factory->EnumAdapters1(0, &adapter))) return 0;
  int32_t count = 0;
  ComPtr<IDXGIOutput> output;
  while (SUCCEEDED(adapter->EnumOutputs(static_cast<UINT>(count), &output))) {
    ++count;
    output.Reset();
  }
  return count;
}

}  // extern "C"
