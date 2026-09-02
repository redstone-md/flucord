import 'dart:async';

import '../domain/voice_connection.dart';
import 'go_live_controller.dart';
import 'remote_camera_controller.dart';
import 'room_focus.dart';
import 'stream_viewer_controller.dart';
import 'streamer_mode_controller.dart';
import 'voice_controller.dart';
import 'voice_overlay_controller.dart';

/// Keeps the room's side effects following the room.
///
/// Remote cameras are read only while a connection is actually up, the
/// in-game overlay is redrawn on every roster change and whenever streamer
/// mode moves it, streamer mode's automatic switch follows this client's own
/// share, watched streams end with the room, and the stage's focus follows
/// its participant out of it. These rules used to sit in the app widget,
/// where no test could reach them without pumping the whole client.
final class VoiceRoomCoordination {
  VoiceRoomCoordination({
    required VoiceController voice,
    required RemoteCameraController remoteCameras,
    required VoiceOverlayController overlay,
    required StreamerModeController streamerMode,
    required GoLiveController goLive,
    required StreamViewerController streamViewer,
    required RoomFocus focus,
  }) : _voice = voice,
       _remoteCameras = remoteCameras,
       _overlay = overlay,
       _streamerMode = streamerMode,
       _goLive = goLive,
       _streamViewer = streamViewer,
       _focus = focus {
    _voice.addListener(_syncRemoteCameras);
    _voice.addListener(_endWatchesWithRoom);
    _voice.addListener(_keepFocusInRoom);
    _voice.addListener(_refreshOverlay);
    _streamerMode.addListener(_refreshOverlay);
    _goLive.addListener(_syncStreamerMode);
  }

  final VoiceController _voice;
  final RemoteCameraController _remoteCameras;
  final VoiceOverlayController _overlay;
  final StreamerModeController _streamerMode;
  final GoLiveController _goLive;
  final StreamViewerController _streamViewer;
  final RoomFocus _focus;

  void dispose() {
    _voice.removeListener(_syncRemoteCameras);
    _voice.removeListener(_endWatchesWithRoom);
    _voice.removeListener(_keepFocusInRoom);
    _voice.removeListener(_refreshOverlay);
    _streamerMode.removeListener(_refreshOverlay);
    _goLive.removeListener(_syncStreamerMode);
  }

  /// Reads everybody else's cameras only while a room is actually connected.
  ///
  /// Bound on ready rather than on join: the SSRC map the packets are matched
  /// against is filled from the voice socket, and a listener attached before
  /// it would be reading a socket that has not finished opening.
  void _syncRemoteCameras() {
    final connected = _voice.connectionStatus == VoiceConnectionStatus.ready;
    if (connected == _remoteCameras.isListening) return;
    if (connected) {
      _remoteCameras.listen();
    } else {
      _remoteCameras.stop();
    }
  }

  /// Discord forgets a room's watchers with the room. A viewer that kept its
  /// asks would offer "Stop watching" on streams it no longer holds, and
  /// carry withdrawals into the next room.
  void _endWatchesWithRoom() {
    if (_voice.connectionStatus != VoiceConnectionStatus.disconnected) return;
    unawaited(_streamViewer.stop());
  }

  /// A stage showing somebody who left, or a room this client left, is a
  /// stage showing nothing.
  void _keepFocusInRoom() {
    if (_voice.connectionStatus == VoiceConnectionStatus.disconnected) {
      _focus.clear();
      return;
    }
    _focus.keepAmong(_voice.participants.map((p) => p.userId));
  }

  /// Redrawn on every roster change and whenever streamer mode moves: an
  /// overlay showing who was in the room a minute ago is worse than none.
  void _refreshOverlay() => unawaited(_overlay.refresh());

  /// Going live is the only streaming this client knows about, so it is
  /// what the automatic switch follows.
  void _syncStreamerMode() =>
      _streamerMode.reconcileStreaming(isStreaming: _goLive.isStreaming);
}
