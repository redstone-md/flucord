import 'dart:async';

import '../domain/go_live_stream.dart';
import '../domain/voice_audio.dart';
import '../app_log.dart';
import 'voice_audio_receiver.dart';

/// The sound of the streams this client is watching.
///
/// One receiver per watched session, because an Opus decoder holds the state
/// of one sender's stream and two senders sharing one is silence with extra
/// steps. A stream nobody opened has no receiver at all, so it stays silent:
/// what gives a stream's sound somewhere to play is watching it, and the
/// sound ends when the session does (ADR-0004).
final class WatchedStreamAudio {
  WatchedStreamAudio({required VoiceOpusDecoderFactory decoderFactory})
    : _decoderFactory = decoderFactory;

  final VoiceOpusDecoderFactory _decoderFactory;
  final StreamController<VoiceRemotePcmFrame> _pcm =
      StreamController<VoiceRemotePcmFrame>.broadcast();
  final Map<GoLiveStreamKey, _SessionAudio> _byKey = {};

  /// Every attach and detach runs in the order it was asked for.
  ///
  /// A session can be stopped while the next one is opening, and two of them
  /// interleaved would otherwise leave a receiver nobody holds.
  Future<void> _pending = Future<void>.value();

  bool _disposed = false;

  /// Sound from every stream being watched, tagged with its sender.
  Stream<VoiceRemotePcmFrame> get pcm => _pcm.stream;

  /// Starts turning [audio] into sound for [key]'s session.
  ///
  /// A session that is already receiving is rebound: the connection under it
  /// was replaced, and the decoder for the old one is not the decoder for the
  /// new.
  Future<void> attach(GoLiveStreamKey key, Stream<VoiceRemoteOpusFrame> audio) =>
      _enqueue(() => _attachNow(key, audio));

  /// Ends [key]'s sound, which is what stopping a watch does.
  Future<void> detach(GoLiveStreamKey key) =>
      _enqueue(() => _detachNow(key));

  Future<void> dispose() => _enqueue(() async {
    if (_disposed) return;
    _disposed = true;
    for (final key in _byKey.keys.toList()) {
      await _detachNow(key);
    }
    await _pcm.close();
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final queued = _pending.then<void>((_) => operation());
    _pending = queued.then<void>(
      (_) {},
      // A stream's sound failing is not a reason to stop the next session
      // from being bound; each operation is awaited where it was asked for.
      onError: (Object _, StackTrace _) {},
    );
    return queued;
  }

  Future<void> _attachNow(
    GoLiveStreamKey key,
    Stream<VoiceRemoteOpusFrame> audio,
  ) async {
    if (_disposed) return;
    await _detachNow(key);
    if (_disposed) return;
    final session = _SessionAudio(
      receiver: VoiceAudioReceiver(decoderFactory: _decoderFactory),
      transport: _StreamAudioTransport(audio),
    );
    _byKey[key] = session;
    session.pcm = session.receiver.remotePcm.listen(_emit);
    session.errors = session.receiver.errors.listen(_diagnose);
    await session.receiver.bindTransport(session.transport);
  }

  Future<void> _detachNow(GoLiveStreamKey key) async {
    final session = _byKey.remove(key);
    if (session == null) return;
    await session.close();
  }

  void _emit(VoiceRemotePcmFrame frame) {
    if (_pcm.isClosed) return;
    _pcm.add(frame);
  }

  void _diagnose(Object error) {
    AppLog.warning('stream', 'screen-share audio: $error');
  }
}

/// One watched session's sound: the decoder and the connection feeding it.
final class _SessionAudio {
  _SessionAudio({required this.receiver, required this.transport});

  final VoiceAudioReceiver receiver;
  final _StreamAudioTransport transport;
  StreamSubscription<VoiceRemotePcmFrame>? pcm;
  StreamSubscription<Object>? errors;

  Future<void> close() async {
    // Ours first: the receiver closes the very streams these are listening to.
    await pcm?.cancel();
    await errors?.cancel();
    pcm = null;
    errors = null;
    await receiver.dispose();
  }
}

/// Presents one connection's arriving sound as a transport, which is what the
/// receiving half of the call's audio pipeline already consumes.
final class _StreamAudioTransport implements VoiceAudioReceiverTransport {
  const _StreamAudioTransport(this.remoteAudio);

  @override
  final Stream<VoiceRemoteOpusFrame> remoteAudio;
}
