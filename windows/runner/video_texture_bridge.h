#ifndef RUNNER_VIDEO_TEXTURE_BRIDGE_H_
#define RUNNER_VIDEO_TEXTURE_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <map>
#include <memory>

// Shows decoded video in texture widgets without the pixels passing through
// Dart (ADR-0009).
//
// Dart asks for a texture over the `flucord/video_texture` channel. The
// bridge makes a surface in flucord_video.dll on the adapter Flutter renders
// with, registers it with the engine as a DXGI shared handle texture, and
// answers with the texture id and the surface's address, which Dart hands to
// the decoder it opens. Each picture the decoder draws marks a frame
// available, and the engine opens the surface's texture by its handle.
//
// flucord_video.dll is loaded at runtime, not linked: Windows editions
// without Media Foundation cannot load it, and the app must still start
// there. A texture asked for on such a machine is refused with the reason.
class VideoTextureBridge {
 public:
  explicit VideoTextureBridge(flutter::FlutterEngine* engine);
  ~VideoTextureBridge();

  VideoTextureBridge(const VideoTextureBridge&) = delete;
  VideoTextureBridge& operator=(const VideoTextureBridge&) = delete;

 private:
  class Texture;
  struct Module;

  void Create(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result);
  void Dispose(int64_t texture_id);

  flutter::FlutterEngine* engine_;
  FlutterDesktopTextureRegistrarRef registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<Module> module_;
  std::map<int64_t, std::unique_ptr<Texture>> textures_;
};

#endif  // RUNNER_VIDEO_TEXTURE_BRIDGE_H_
