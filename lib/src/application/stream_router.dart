import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_stream_rtc_session.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_capture_hub.dart';
import '../domain/voice_connection.dart';
import 'go_live_controller.dart';
import 'stream_viewer_controller.dart';

/// Routes each stream connection to the end of it this client is.
///
/// A connection knows whose stream it carries from the moment Discord hands
/// out the endpoint, but only once the endpoint has answered does it have an
/// SSRC (the source id Discord routes a sender's packets by) to send with, so
/// the fork waits for ready. Our own stream is declared, and its connection
/// sends the encoder's pictures from then on by itself; anybody else's is
/// handed to the viewer. This used to live in a widget callback, where the
/// riskiest wiring in the stream plane had no coverage at all.
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

  /// The receiver connection currently feeding each watched key. A sender's
  /// own key has two connections, so the key alone is not enough to decide
  /// which one to attach.
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
          _route(session);
          return;
        }
        if (event is VoiceSignalingStatusEvent &&
            event.status == VoiceConnectionStatus.failure &&
            !session.sending) {
          _viewer.reportError(
            session.key,
            event.error ?? StateError('Discord refused the stream connection'),
          );
        }
      },
      // The session closes its events with itself; the entry must not outlive
      // the connection it was keyed by. A sender ending also withdraws the
      // self-watch, otherwise its stale decoder could keep the tile claiming
      // to be live after the share stopped.
      onDone: () {
        _waiting.remove(session)?.cancel();
        if (session.sending) {
          _receiving.remove(session.key);
          unawaited(_viewer.stop(session.key));
        } else if (identical(_receiving[session.key], session)) {
          _receiving.remove(session.key);
          unawaited(_viewer.stop(session.key));
        }
      },
    );
    _waiting[session] = subscription;
  }

  void _route(DiscordStreamRtcSession session) {
    if (session.sending) {
      // The role is attached to the connection, not inferred from its key:
      // the self-preview creates a second connection with the same key, and
      // announcing on that one would turn the receiver into a second sender.
      // A stale sender endpoint after the share stopped must not announce
      // either.
      if (session.key != _goLive.streamKey) return;
      // Declared before the first packet, with what the capture is actually
      // running at: a packet whose SSRC was never announced is dropped on
      // Discord's side, and a share declared at numbers of this caller's own
      // inventing is a share nobody can decode. The connection, opened by the
      // media plane, starts sending on the announce.
      session.announceVideo(
        enabled: true,
        settings: _capture.settings ?? _capture.shareSettings,
      );
      // Once the sending connection is ready, ask Discord for the same key on
      // a receiving connection. That round trip is the sender's preview.
      unawaited(_viewer.requestWatch(session.key));
      return;
    }

    // Anything else, including the second connection for this account's own
    // key, is a receiving connection. Its pictures come in here. Do not
    // replace a decoder when the same connection announces ready again during
    // a reconnect: the packet stream subscription already follows it.
    if (identical(_receiving[session.key], session)) return;
    _receiving[session.key] = session;
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
