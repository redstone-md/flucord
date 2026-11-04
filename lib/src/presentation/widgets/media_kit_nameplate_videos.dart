import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'nameplate_motion.dart';

/// Plays moving nameplates through media_kit, the engine the chat's inline
/// videos use. A player is made per video and disposed with it;
/// [NameplateMotion] keeps no more than one alive.
final class MediaKitNameplateVideos implements NameplateVideos {
  const MediaKitNameplateVideos();

  @override
  NameplateVideo open(String url) => _MediaKitNameplateVideo(url);
}

final class _MediaKitNameplateVideo implements NameplateVideo {
  _MediaKitNameplateVideo(String url) {
    // The first picture, or the player's first error, whichever comes first.
    firstFrame = Future.any([
      _open(url).then((_) => _controller.waitUntilFirstFrameRendered),
      _player.stream.error.first.then<void>((error) => throw StateError(error)),
    ]);
  }

  final _player = Player(configuration: const PlayerConfiguration(muted: true));
  late final _controller = VideoController(_player);

  @override
  late final Future<void> firstFrame;

  Future<void> _open(String url) async {
    await _player.setPlaylistMode(PlaylistMode.loop);
    await _player.open(Media(url));
  }

  @override
  Widget view() => Video(
    controller: _controller,
    controls: NoVideoControls,
    fit: BoxFit.cover,
    fill: Colors.transparent,
  );

  @override
  Future<void> dispose() => _player.dispose();
}
