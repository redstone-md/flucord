#include "video_texture_bridge.h"

#include <flutter/standard_method_codec.h>
#include <flutter_texture_registrar.h>
#include <windows.h>

#include <dxgi.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdint>
#include <sstream>
#include <string>
#include <utility>
#include <variant>

#include "flucord_video/flucord_video.h"

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

namespace {

std::string Hex(int32_t hr) {
  std::ostringstream text;
  text << "0x" << std::hex << static_cast<uint32_t>(hr);
  return text.str();
}

}  // namespace

// The surface calls of flucord_video.dll, looked up once.
struct VideoTextureBridge::Module {
  // Loads the module, or answers null and why.
  static std::unique_ptr<Module> Load(std::string* why) {
    // Only the application's own directory and System32, where Media
    // Foundation lives: never the working directory.
    HMODULE library = LoadLibraryExW(L"flucord_video.dll", nullptr,
                                     LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (library == nullptr) {
      *why = "flucord_video.dll did not load (" +
             std::to_string(GetLastError()) + ")";
      return nullptr;
    }
    auto module = std::make_unique<Module>();
    module->create = reinterpret_cast<decltype(create)>(
        GetProcAddress(library, "flucord_video_surface_create"));
    module->detach = reinterpret_cast<decltype(detach)>(
        GetProcAddress(library, "flucord_video_surface_detach"));
    module->release = reinterpret_cast<decltype(release)>(
        GetProcAddress(library, "flucord_video_surface_release"));
    module->describe = reinterpret_cast<decltype(describe)>(
        GetProcAddress(library, "flucord_video_surface_describe"));
    if (module->create == nullptr || module->detach == nullptr ||
        module->release == nullptr || module->describe == nullptr) {
      *why = "flucord_video.dll has no video surfaces";
      return nullptr;
    }
    // Kept loaded for the life of the process: a decoder in Dart may still
    // be drawing on a surface it made.
    return module;
  }

  decltype(&flucord_video_surface_create) create = nullptr;
  decltype(&flucord_video_surface_detach) detach = nullptr;
  decltype(&flucord_video_surface_release) release = nullptr;
  decltype(&flucord_video_surface_describe) describe = nullptr;
};

// One registered texture and the surface behind it.
class VideoTextureBridge::Texture {
 public:
  Texture(const Module& module, FlutterDesktopTextureRegistrarRef registrar)
      : module_(module), registrar_(registrar) {}

  ~Texture() {
    if (surface_ != nullptr) module_.release(surface_);
  }

  Texture(const Texture&) = delete;
  Texture& operator=(const Texture&) = delete;

  // Makes the surface on `adapter` and registers it. Answers the texture id,
  // or -1 with why.
  int64_t Open(const LUID& adapter, std::string* why) {
    const int32_t hr = module_.create(adapter.LowPart, adapter.HighPart,
                                      &Texture::OnPicture, this, &surface_);
    if (hr != 0) {
      *why = "the video surface did not open (" + Hex(hr) + ")";
      return -1;
    }
    FlutterDesktopTextureInfo info{};
    info.type = kFlutterDesktopGpuSurfaceTexture;
    info.gpu_surface_config.struct_size =
        sizeof(FlutterDesktopGpuSurfaceTextureConfig);
    info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
    info.gpu_surface_config.callback = &Texture::Describe;
    info.gpu_surface_config.user_data = this;
    const int64_t id =
        FlutterDesktopTextureRegistrarRegisterExternalTexture(registrar_, &info);
    if (id < 0) {
      *why = "the engine refused the video texture";
      return -1;
    }
    id_.store(id);
    return id;
  }

  FlucordVideoSurface* surface() const { return surface_; }

  // Stops marking frames. Called before the texture is unregistered, so no
  // mark names an id the engine no longer has.
  void Detach() { module_.detach(surface_); }

 private:
  // The decode thread, after each picture.
  static void OnPicture(void* context) {
    auto* self = static_cast<Texture*>(context);
    const int64_t id = self->id_.load();
    if (id >= 0) {
      FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
          self->registrar_, id);
    }
  }

  // The engine's raster thread, when it draws the texture. Null before the
  // first picture: the widget draws nothing until there is one.
  static const FlutterDesktopGpuSurfaceDescriptor* Describe(size_t,
                                                            size_t,
                                                            void* user_data) {
    auto* self = static_cast<Texture*>(user_data);
    void* handle = nullptr;
    int32_t width = 0;
    int32_t height = 0;
    if (self->module_.describe(self->surface_, &handle, &width, &height) == 0) {
      return nullptr;
    }
    self->descriptor_ = {};
    self->descriptor_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    self->descriptor_.handle = handle;
    self->descriptor_.width = self->descriptor_.visible_width =
        static_cast<size_t>(width);
    self->descriptor_.height = self->descriptor_.visible_height =
        static_cast<size_t>(height);
    self->descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
    return &self->descriptor_;
  }

  // A copy: the engine may free this texture after the bridge has gone.
  const Module module_;
  FlutterDesktopTextureRegistrarRef registrar_;
  FlucordVideoSurface* surface_ = nullptr;
  std::atomic<int64_t> id_{-1};
  // Read by the engine after Describe returns; only the raster thread
  // touches it.
  FlutterDesktopGpuSurfaceDescriptor descriptor_{};
};

VideoTextureBridge::VideoTextureBridge(flutter::FlutterEngine* engine)
    : engine_(engine),
      registrar_(FlutterDesktopRegistrarGetTextureRegistrar(
          engine->GetRegistrarForPlugin("FlucordVideoTexture"))),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "flucord/video_texture",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "create") {
          Create(std::move(result));
          return;
        }
        if (call.method_name() == "dispose") {
          // The codec sends a small id as 32 bits and a large one as 64.
          const EncodableValue* id = call.arguments();
          if (id != nullptr && (std::holds_alternative<int32_t>(*id) ||
                                std::holds_alternative<int64_t>(*id))) {
            Dispose(id->LongValue());
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

VideoTextureBridge::~VideoTextureBridge() {
  channel_->SetMethodCallHandler(nullptr);
  while (!textures_.empty()) Dispose(textures_.begin()->first);
}

void VideoTextureBridge::Create(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::string why;
  if (!module_) module_ = Module::Load(&why);
  if (!module_) {
    result->Error("unavailable", why);
    return;
  }
  ComPtr<IDXGIAdapter> adapter;
  DXGI_ADAPTER_DESC desc{};
  if (!engine_->GetGraphicsAdapter(&adapter) || !adapter ||
      FAILED(adapter->GetDesc(&desc))) {
    result->Error("unavailable", "the engine named no graphics adapter");
    return;
  }
  auto texture = std::make_unique<Texture>(*module_, registrar_);
  const int64_t id = texture->Open(desc.AdapterLuid, &why);
  if (id < 0) {
    result->Error("unavailable", why);
    return;
  }
  const auto surface =
      static_cast<int64_t>(reinterpret_cast<intptr_t>(texture->surface()));
  textures_[id] = std::move(texture);
  result->Success(EncodableValue(EncodableMap{
      {EncodableValue("textureId"), EncodableValue(id)},
      {EncodableValue("surface"), EncodableValue(surface)},
  }));
}

void VideoTextureBridge::Dispose(int64_t texture_id) {
  auto found = textures_.find(texture_id);
  if (found == textures_.end()) return;
  Texture* texture = found->second.release();
  textures_.erase(found);
  texture->Detach();
  // The engine may be drawing it right now: it is freed once the engine has
  // let go, on whichever thread the engine says so from.
  FlutterDesktopTextureRegistrarUnregisterExternalTexture(
      registrar_, texture_id,
      [](void* user_data) {
        std::unique_ptr<Texture> released(static_cast<Texture*>(user_data));
      },
      texture);
}
