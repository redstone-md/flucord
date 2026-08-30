import 'dart:async';

import '../domain/go_live_stream.dart';
import '../domain/voice_audio.dart';
import '../app_log.dart';
import 'voice_audio_receiver.dart';

/// Decodes audio for watched streams, one receiver per session (ADR-0004).
final class WatchedStreamAudio {
  WatchedStreamAudio({required VoiceOpusDecoderFactory decoderFactory})
    : _decoderFactory = decoderFactory;

  final VoiceOpusDecoderFactory _decoderFactory;
  final StreamController<VoiceRemotePcmFrame> _pcm =
      StreamController<VoiceRemotePcmFrame>.broadcast();
  final StreamController<String> _ended = StreamController<String>.broadcast();
  final Map<GoLiveStreamKey, _SessionAudio> _byKey = {};

  Future<void> _pending = Future<void>.value();
  int _nextSourceId = 0;

  bool _disposed = false;

  /// Decoded audio from all watched sessions.
  Stream<VoiceRemotePcmFrame> get pcm => _pcm.stream;

  /// Source ids that are no longer active.
  Stream<String> get ended => _ended.stream;

  Future<void> attach(GoLiveStreamKey key, Stream<VoiceRemoteOpusFrame> audio) =>
      _enqueue(() => _attachNow(key, audio));

  Future<void> detach(GoLiveStreamKey key) =>
      _enqueue(() => _detachNow(key));

  Future<void> dispose() => _enqueue(() async {
    if (_disposed) return;
    _disposed = true;
    for (final key in _byKey.keys.toList()) {
      await _detachNow(key);
    }
    await _pcm.close();
    await _ended.close();
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final queued = _pending.then<void>((_) => operation());
    _pending = queued.then<void>(
      (_) {},
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
    final sourceId = 'stream:${key.value}:${++_nextSourceId}';
    final session = _SessionAudio(
      sourceId: sourceId,
      receiver: VoiceAudioReceiver(
        decoderFactory: _decoderFactory,
        sourceId: sourceId,
      ),
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
    if (!_ended.isClosed) _ended.add(session.sourceId);
  }

  void _emit(VoiceRemotePcmFrame frame) {
    if (_pcm.isClosed) return;
    _pcm.add(frame);
  }

  void _diagnose(Object error) {
    AppLog.warning('stream', 'screen-share audio: $error');
  }
}

final class _SessionAudio {
  _SessionAudio({
    required this.sourceId,
    required this.receiver,
    required this.transport,
  });

  final String sourceId;
  final VoiceAudioReceiver receiver;
  final _StreamAudioTransport transport;
  StreamSubscription<VoiceRemotePcmFrame>? pcm;
  StreamSubscription<Object>? errors;

  Future<void> close() async {
    await pcm?.cancel();
    await errors?.cancel();
    pcm = null;
    errors = null;
    await receiver.dispose();
  }
}

final class _StreamAudioTransport implements VoiceAudioReceiverTransport {
  const _StreamAudioTransport(this.remoteAudio);

  @override
  final Stream<VoiceRemoteOpusFrame> remoteAudio;
}
