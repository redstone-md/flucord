import 'package:flutter/services.dart';

/// A texture the runner made for decoded video: the id a `Texture` widget
/// shows, and the address of the native surface behind it, which a decoder
/// opens on.
typedef NativeVideoTexture = ({int id, int surface});

/// Makes and frees the textures decoded video is drawn on.
abstract interface class NativeVideoTextures {
  Future<NativeVideoTexture> create();

  Future<void> dispose(int id);
}

/// The runner's textures, over `flucord/video_texture`
/// (windows/runner/video_texture_bridge.cpp).
final class ChannelVideoTextures implements NativeVideoTextures {
  const ChannelVideoTextures([
    this._channel = const MethodChannel('flucord/video_texture'),
  ]);

  final MethodChannel _channel;

  /// Fails with the runner's reason when it cannot make one: no video
  /// module, no graphics adapter, or a surface the device refused.
  @override
  Future<NativeVideoTexture> create() async {
    final reply = await _channel.invokeMapMethod<String, Object?>('create');
    final id = reply?['textureId'];
    final surface = reply?['surface'];
    if (id is! int || surface is! int) {
      throw StateError('the runner answered no video texture: $reply');
    }
    return (id: id, surface: surface);
  }

  @override
  Future<void> dispose(int id) => _channel.invokeMethod<void>('dispose', id);
}
