import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_stream_rtc_session.dart';
import '../domain/go_live_stream.dart';
import '../domain/voice_connection.dart';
import 'stream_viewer_controller.dart';
import 'watched_session_pipeline.dart';

/// Attaches each watched stream's connection to the viewer once it is ready.
///
/// A connection knows whose stream it carries from the moment Discord hands
/// out the endpoint, but its pictures only start once the endpoint has
/// answered, so the attach waits for ready. This used to live in a widget
/// callback, where the riskiest wiring in the stream plane had no coverage
/// at all.
final class StreamRouter {
  StreamRouter({
    required Stream<DiscordStreamRtcSession> opened,
    required StreamViewerController viewer,
  }) : _viewer = viewer {
    _openedSubscription = opened.listen(_accept);
  }

  final StreamViewerController _viewer;

  late final StreamSubscription<DiscordStreamRtcSession> _openedSubscription;

  /// Connections still waiting for their endpoint to answer.
  final Map<DiscordStreamRtcSession, StreamSubscription<VoiceSignalingEvent>>
  _waiting = {};

  /// The connection currently feeding each watched key.
  final Map<GoLiveStreamKey, DiscordStreamRtcSession> _receiving = {};

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
    late final StreamSubscription<VoiceSignalingEvent> subscription;
    subscription = session.events.listen(
      (event) {
        if (event is VoiceTransportReadyEvent) {
          _attach(session);
          return;
        }
        if (event is VoiceSignalingStatusEvent &&
            event.status == VoiceConnectionStatus.failure) {
          _viewer.reportError(
            session.key,
            event.error ?? StateError('Discord refused the stream connection'),
          );
        }
      },
      // The session closes its events with itself; the entry must not outlive
      // the connection it was keyed by, and the watched session goes with it.
      onDone: () {
        _waiting.remove(session)?.cancel();
        if (identical(_receiving[session.key], session)) {
          _receiving.remove(session.key);
          unawaited(_viewer.stop(session.key));
        }
      },
    );
    _waiting[session] = subscription;
  }

  /// Do not replace a decoder when the same connection announces ready again
  /// during a reconnect: the packet stream subscription already follows it.
  void _attach(DiscordStreamRtcSession session) {
    if (identical(_receiving[session.key], session)) return;
    _receiving[session.key] = session;
    unawaited(
      _viewer.attach(
        session.key,
        packets: session.video.map(
          (packet) => IncomingVideoPacket(
            payload: Uint8List.fromList(packet.$2.payload),
            marker: packet.$2.header.marker,
            rtpTimestamp: packet.$2.header.timestamp,
          ),
        ),
        // Forward audio from the stream connection (ADR-0004).
        audio: session.audio,
        // A stream connection carries one sender's pictures, so the key names
        // whose group decrypts them. Bound here rather than in the viewer,
        // which holds sessions from several connections at once.
        groupDecryptor: (picture) => session.decryptVideoGroupFrame(
          userId: session.key.userId,
          picture: picture,
        ),
        // The receiver knows when the stream is broken; the session is what
        // can ask the sender for a keyframe over its connection.
        requestKeyframe: session.requestKeyframe,
      ),
    );
  }
}
