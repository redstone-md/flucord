import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_stream_rtc_session.dart';
import '../domain/video_capture_hub.dart';
import '../domain/voice_connection.dart';
import 'go_live_controller.dart';
import 'stream_viewer_controller.dart';

/// Routes each stream connection to the end of it this client is.
///
/// A connection knows whose stream it carries from the moment Discord hands
/// out the endpoint, but only once the endpoint has answered does it have an
/// SSRC (the source id Discord routes a sender's packets by) to send with, so
/// the fork waits for ready. Our own stream is declared
/// and pointed at the encoder; anybody else's is handed to the viewer. This
/// used to live in a widget callback, where the riskiest wiring in the stream
/// plane had no coverage at all.
final class StreamRouter {
  StreamRouter({
    required Stream<DiscordStreamRtcSession> opened,
    required GoLiveController goLive,
    required StreamViewerController viewer,
    required VideoCaptureHub capture,
  }) : _goLive = goLive,
       _viewer = viewer,
       _capture = capture {
    _openedSubscription = opened.listen(_accept);
  }

  final GoLiveController _goLive;
  final StreamViewerController _viewer;

  /// The share is announced with the capture's own profile, so the router
  /// reads it from the capture rather than choosing numbers itself.
  final VideoCaptureHub _capture;

  late final StreamSubscription<DiscordStreamRtcSession> _openedSubscription;

  /// Connections still waiting for their endpoint to answer.
  final Map<DiscordStreamRtcSession, StreamSubscription<VoiceSignalingEvent>>
  _waiting = {};

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_openedSubscription.cancel());
    for (final subscription in _waiting.values) {
      unawaited(subscription.cancel());
    }
    _waiting.clear();
  }

  void _accept(DiscordStreamRtcSession session) {
    if (_disposed) return;
    _waiting[session] = session.events.listen((event) {
      if (event is! VoiceTransportReadyEvent) return;
      unawaited(_waiting.remove(session)?.cancel());
      _route(session, event);
    });
  }

  void _route(DiscordStreamRtcSession session, VoiceTransportReadyEvent event) {
    if (session.key == _goLive.streamKey) {
      // Declared before the first packet, with what the capture is actually
      // running at: a packet whose SSRC was never announced is dropped on
      // Discord's side, and a share declared at numbers of this caller's own
      // inventing is a share nobody can decode.
      session.announceVideo(
        enabled: true,
        settings: _capture.settings ?? VideoCaptureHub.shareSettings,
      );
      _goLive.bindTransport(
        ssrc: event.session.ssrc,
        sink: session.sendVideoFrame,
      );
      return;
    }
    // Anything else is somebody else's stream, and its pictures come in here.
    unawaited(
      _viewer.attach(
        session.key,
        packets: session.video.map(
          (packet) => IncomingVideoPacket(
            payload: Uint8List.fromList(packet.$2.payload),
            marker: packet.$2.header.marker,
          ),
        ),
      ),
    );
  }
}
