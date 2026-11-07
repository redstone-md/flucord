import 'dart:async';

import '../domain/voice_connection.dart';
import 'go_live_controller.dart';
import 'remote_camera_controller.dart';
import 'room_focus.dart';
import 'self_video_controller.dart';
import 'stream_viewer_controller.dart';
import 'streamer_mode_controller.dart';
import 'voice_controller.dart';
import 'voice_overlay_controller.dart';
import 'workspace_controller.dart';

/// Keeps the room's side effects following the room.
///
/// Remote cameras are read only while a connection is actually up, the
/// in-game overlay is redrawn on every roster change and whenever streamer
/// mode moves it, streamer mode's automatic switch follows this client's own
/// stream, watched streams and this client's own stream end with the room, the
/// camera goes off with it, and the stage's focus follows its participant out
/// of it. When the room moves to another channel, its screen goes along.
/// These rules used to sit in the app widget, where no test could reach
/// them without pumping the whole client.
final class VoiceRoomCoordination {
  VoiceRoomCoordination({
    required VoiceController voice,
    required RemoteCameraController remoteCameras,
    required VoiceOverlayController overlay,
    required StreamerModeController streamerMode,
    required GoLiveController goLive,
    required StreamViewerController streamViewer,
    required SelfVideoController selfVideo,
    required RoomFocus focus,
    required WorkspaceController workspace,
  }) : _voice = voice,
       _remoteCameras = remoteCameras,
       _overlay = overlay,
       _streamerMode = streamerMode,
       _goLive = goLive,
       _streamViewer = streamViewer,
       _selfVideo = selfVideo,
       _focus = focus,
       _workspace = workspace,
       _room = voice.connectedChannelId {
    _voice.addListener(_followRoom);
    _voice.addListener(_syncRemoteCameras);
    _voice.addListener(_endShareWithRoom);
    _voice.addListener(_endCameraWithRoom);
    _voice.addListener(_keepCameraOnConnection);
    _voice.addListener(_keepFocusInRoom);
    _voice.addListener(_refreshOverlay);
    _streamerMode.addListener(_refreshOverlay);
    _goLive.addListener(_syncStreamerMode);
    _camerasGoneSubscription = voice.camerasGone.listen(_remoteCameras.forget);
    _pictureAsksSubscription = voice.pictureAsks.listen(selfVideo.answer);
  }

  final VoiceController _voice;
  final RemoteCameraController _remoteCameras;
  final VoiceOverlayController _overlay;
  final StreamerModeController _streamerMode;
  final GoLiveController _goLive;
  final StreamViewerController _streamViewer;
  final SelfVideoController _selfVideo;
  final RoomFocus _focus;
  final WorkspaceController _workspace;

  /// The channel the room was in when the voice controller last changed.
  String? _room;
  StreamSubscription<String>? _camerasGoneSubscription;
  StreamSubscription<VoicePictureAsk>? _pictureAsksSubscription;

  void dispose() {
    _voice.removeListener(_followRoom);
    _voice.removeListener(_syncRemoteCameras);
    _voice.removeListener(_endShareWithRoom);
    _voice.removeListener(_endCameraWithRoom);
    _voice.removeListener(_keepCameraOnConnection);
    _voice.removeListener(_keepFocusInRoom);
    _voice.removeListener(_refreshOverlay);
    _streamerMode.removeListener(_refreshOverlay);
    _goLive.removeListener(_syncStreamerMode);
    unawaited(_camerasGoneSubscription?.cancel());
    unawaited(_pictureAsksSubscription?.cancel());
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

  /// Watches end when the room goes down or to another channel, by a
  /// moderator move or the person's own. Discord forgets a room's watchers
  /// with the room, and a viewer that kept its asks would offer "Stop
  /// watching" on streams it no longer holds. On a move, the screen showing
  /// the old room shows the new one.
  void _followRoom() {
    final previous = _room;
    final current = _voice.connectedChannelId;
    _room = current;
    final moved = previous != null && current != null && current != previous;
    if (!_roomIsUp || moved) unawaited(_streamViewer.stop());
    if (moved && _workspace.selectedChannelId == previous) {
      _workspace.selectChannel(current);
    }
  }

  /// The stream ends with the room, and the capture behind it is released.
  /// The only control that stops a stream is drawn in its room, so a stream
  /// that outlived the room would keep the screen captured with nothing on
  /// screen to end it.
  ///
  /// A reconnect is not the room ending: the status stays up through it.
  void _endShareWithRoom() {
    if (!_goLive.isSharing) return;
    if (_roomIsUp && _shareIsInThisSession) return;
    unawaited(_goLive.stop());
  }

  /// Whether the running stream was sent into the channel this client is in
  /// now. Its key names the channel, and a move changes the channel without
  /// the status going down. A stream still being created has no key yet.
  bool get _shareIsInThisSession => switch (_goLive.streamKey) {
    null => true,
    final key => key.channelId == _voice.connectedChannelId,
  };

  /// The camera goes off with the room, without announcing it: the voice
  /// state that said the camera was on dies with the socket, and the socket
  /// that would carry the withdrawal is the one that dropped. A camera kept
  /// on across a full disconnect would be re-announced into the next room
  /// while sending on the old session's SSRC.
  ///
  /// Moving to another Room changes the session without the status ever saying
  /// the Room went down. The voice flag says it instead: it clears on a move,
  /// and a camera still on with no flag is sending into a Room that was not
  /// told.
  void _endCameraWithRoom() {
    if (_roomIsUp && (_voice.isCameraOn || !_selfVideo.isOn)) return;
    unawaited(_selfVideo.forget());
  }

  /// A camera that outlived a reconnect follows the connection to its new
  /// SSRC, once the connection is up again.
  void _keepCameraOnConnection() {
    if (_voice.connectionStatus != VoiceConnectionStatus.ready) return;
    _selfVideo.followVoiceSession();
  }

  /// A connection that failed ends the room the same as one that was left:
  /// the voice controller drops its roster and transport on both.
  bool get _roomIsUp => switch (_voice.connectionStatus) {
    VoiceConnectionStatus.disconnected ||
    VoiceConnectionStatus.failure => false,
    _ => true,
  };

  /// A stage showing somebody who left, or a room this client left, is a
  /// stage showing nothing.
  void _keepFocusInRoom() {
    if (!_roomIsUp) {
      _focus.clear();
      return;
    }
    if (_focus.userId == null) return;
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
