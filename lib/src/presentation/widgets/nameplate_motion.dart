import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app_log.dart';

/// Opens moving nameplates. The app's is `MediaKitNameplateVideos`;
/// media_kit cannot run under `flutter test`, so
/// tests hand [NameplateMotion] a fake.
abstract interface class NameplateVideos {
  /// Starts playing [url], muted and looping.
  NameplateVideo open(String url);
}

/// One moving nameplate, playing.
abstract interface class NameplateVideo {
  /// Completes once a picture is ready to show, or fails when the video
  /// cannot play.
  Future<void> get firstFrame;

  /// The playing picture, filling the space it is given.
  Widget view();

  Future<void> dispose();
}

/// The one moving nameplate in the app.
///
/// Discord's clients play a nameplate's `asset.webm` only while its row is
/// under the pointer, and keep the still picture otherwise (the mobile
/// client's Nameplate.tsx in Wumpus-Central/discord-mobile-datamining takes
/// an `animate` flag and the reduced motion setting). Playing one at a time
/// keeps the cost at one decoder however many rows have a nameplate.
///
/// A row asks with [play] when the pointer enters it and gives it back with
/// [stop]. Starting one stops the one before. Listeners hear when a video is
/// ready to show and when one is taken away from a row.
final class NameplateMotion extends ChangeNotifier {
  NameplateMotion(this._videos);

  final NameplateVideos _videos;
  Object? _owner;
  NameplateVideo? _video;
  bool _ready = false;

  /// The video to draw for [owner]: its own, once a picture is ready.
  NameplateVideo? videoFor(Object owner) =>
      owner == _owner && _ready ? _video : null;

  /// Plays [url] for [owner], stopping whatever played before.
  void play(Object owner, String url) {
    if (owner == _owner) return;
    final hadOwner = _owner != null;
    _release();
    final video = _videos.open(url);
    _owner = owner;
    _video = video;
    video.firstFrame.then(
      (_) {
        if (_video != video) return;
        _ready = true;
        notifyListeners();
      },
      onError: (Object error) {
        if (_video != video) return;
        AppLog.warning('nameplates', 'could not play $url', error: error);
        _release();
        notifyListeners();
      },
    );
    if (hadOwner) notifyListeners();
  }

  /// Stops [owner]'s video, if it has one. The row that calls this redraws
  /// itself; nobody else is told.
  void stop(Object owner) {
    if (owner == _owner) _release();
  }

  void _release() {
    final video = _video;
    _owner = null;
    _video = null;
    _ready = false;
    if (video != null) unawaited(video.dispose());
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }
}
