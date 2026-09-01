import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_video_picture_receiver.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_decoder.dart';
import '../domain/voice_audio.dart';
import '../app_log.dart';
import 'watched_session_pipeline.dart';

/// How many streams this client holds at once.
///
/// Ours and not Discord's: nothing is documented on their side, and every
/// session costs a decoder and a connection of its own.
const int maxWatchedStreams = 4;

/// Watches several Go Live streams at once, one session apiece.
///
/// Room policy only: which streams are asked for, the cap, the own key's
/// reserved slot, the stage, withdrawn and refused asks, and telling the
/// connection layer when a watch stops. What happens between a packet and a
/// picture is each session's [WatchedSessionPipeline], because two senders
/// interleaved on a single receiver splice one picture into another's, and a
/// single decoder has nowhere to put a second stream's.
final class StreamViewerController extends ChangeNotifier {
  StreamViewerController({
    required GoLiveRepository? Function() repositoryProvider,
    required VideoDecoderService Function() decoderFactory,
    GoLiveStreamKey? Function()? ownKeyProvider,
    void Function(GoLiveStreamKey key)? onWatchRequested,
    void Function(GoLiveStreamKey key)? onWatchStopped,

    /// Decodes screen-share audio for watched sessions, when the build can.
    VoiceOpusDecoderFactory? audioDecoderFactory,
  }) : _repositoryProvider = repositoryProvider,
       _decoderFactory = decoderFactory,
       _ownKeyProvider = ownKeyProvider,
       _onWatchRequested = onWatchRequested,
       _onWatchStopped = onWatchStopped,
       _audioDecoderFactory = audioDecoderFactory;

  final GoLiveRepository? Function() _repositoryProvider;
  final VideoDecoderService Function() _decoderFactory;
  final void Function(GoLiveStreamKey key)? _onWatchRequested;

  /// Told which key was stopped, so whoever holds the connection drops it.
  ///
  /// Closing the session leaves the connection up: the media server goes on
  /// sending, and the client goes on decrypting, reordering and asking for
  /// retransmissions of pictures nobody draws. The connection is not this
  /// controller's to close, so it says which key, the way
  /// [_onWatchRequested] does for the ask.
  final void Function(GoLiveStreamKey key)? _onWatchStopped;

  /// One audio receiver per watched session (ADR-0004).
  final VoiceOpusDecoderFactory? _audioDecoderFactory;

  /// This account's own share. A session like any other once the sender asks
  /// for it back, and counted towards the cap either way (ADR-0002).
  final GoLiveStreamKey? Function()? _ownKeyProvider;

  /// Every key this client is holding, in the order it asked for them: the
  /// stage shows whichever of them was asked for last.
  final List<GoLiveStreamKey> _order = [];

  /// Sessions whose pictures are arriving.
  final Map<GoLiveStreamKey, _WatchedSession> _sessions = {};

  /// Asks withdrawn before Discord answered them.
  ///
  /// Discord opens the connection whether this client still wants it or not,
  /// and the router hands every connection here. Without this a stream would
  /// take the stage right after its control said it was closed. Held per key:
  /// withdrawing one ask must not clear another's withdrawal.
  final Set<GoLiveStreamKey> _cancelled = {};

  /// The ask turned down for want of room, if that is what happened last.
  GoLiveStreamKey? _refused;

  /// Why each key could not be opened, for as long as that is the last thing
  /// that happened to it. Per key, because several sessions share this one
  /// controller and a failure on one says nothing about another.
  final Map<GoLiveStreamKey, Object?> _errors = {};

  /// The sessions' sound, merged for the room's output (ADR-0004).
  final StreamController<VoiceRemotePcmFrame> _pcm =
      StreamController<VoiceRemotePcmFrame>.broadcast();
  final StreamController<String> _audioEnded =
      StreamController<String>.broadcast();
  int _audioSources = 0;

  /// Whether anything of this client's window is on screen, which is this
  /// client's own business alone: sessions go on receiving and draw nothing
  /// (ADR-0003).
  bool _suspended = false;

  bool _disposed = false;

  /// Whether this build can decode at all, which is a property of the build
  /// rather than of any one session: one decoder is made to ask, and never
  /// started.
  ///
  /// Cached, but a false answer is retried through the factory: a load that
  /// failed once (a build racing the app's first ask, say) must not poison
  /// the whole run, while a supported build asks the factory exactly once.
  bool? _supported;
  bool get isSupported {
    if (_supported != true) _supported = _decoderFactory().isSupported;
    return _supported ?? false;
  }

  /// Whose stream is on the stage: the one asked for most recently of those
  /// whose pictures are arriving.
  ///
  /// An ask is not on the stage: the endpoint it is answered with may never
  /// come, and a request Discord never answered must not take the room away.
  ///
  /// This account's own stream is not on the stage either, however recently it
  /// was asked for: a sender's own pictures are drawn on their tile, because
  /// somebody sharing is watching who is in the room rather than themselves
  /// full screen (ADR-0001).
  GoLiveStreamKey? get watching =>
      _lastWhere((key) => isWatching(key) && !_isOwn(key));

  /// Whose stream was asked for most recently and has not started arriving.
  ///
  /// Separate from [watching] because the two are seconds apart: the ask goes
  /// out on the main gateway, Discord answers with an endpoint, and only the
  /// connection that answer opens produces pictures. A button that waited for
  /// [watching] would look dead for the whole handshake.
  GoLiveStreamKey? get requested => _lastWhere(isRequested);

  /// The ask turned down because this client is holding all it will hold.
  GoLiveStreamKey? get refused => _refused;

  /// Whether anything of this client's window is on screen: what is on the
  /// stage is still a stream that is arriving, and nothing is being drawn for
  /// it until the window is back (ADR-0003).
  bool get isSuspended => _suspended;

  /// Pictures from [key]'s stream.
  ///
  /// Per key rather than one stream for the room: the stage draws one session,
  /// and which one changes.
  Stream<DecodedVideoFrame> framesFor(GoLiveStreamKey key) =>
      _sessions[key]?.pipeline.frames ??
      const Stream<DecodedVideoFrame>.empty();

  /// Audio from watched sessions, for the room output (ADR-0004).
  Stream<VoiceRemotePcmFrame> get audio => _pcm.stream;

  /// Source ids released with watched sessions.
  Stream<String> get audioEnded => _audioEnded.stream;

  /// Whether this client is holding [key]: asked for, or arriving.
  bool isOpen(GoLiveStreamKey key) => _order.contains(key);

  /// Whether [key]'s pictures are arriving.
  bool isWatching(GoLiveStreamKey key) => _sessions.containsKey(key);

  /// Whether [key] has been asked for but has not started arriving.
  bool isRequested(GoLiveStreamKey key) =>
      _order.contains(key) && !_sessions.containsKey(key);

  /// Whether there is room for one more session.
  bool get isFull => _held >= maxWatchedStreams;

  /// How many packets [key] has received, which is what separates "Discord
  /// was asked" from "something is arriving".
  int receivedPacketsFor(GoLiveStreamKey key) =>
      _sessions[key]?.pipeline.stats.receivedPackets ?? 0;

  /// How many complete pictures [key] has produced, which separates
  /// "packets are arriving" from "pictures are arriving". Read on demand:
  /// listeners are not told about each one.
  int decodedUnitsFor(GoLiveStreamKey key) =>
      _sessions[key]?.pipeline.stats.pictures ?? 0;

  /// How many packets the stream on the stage has received.
  int get receivedPackets => switch (watching) {
    null => 0,
    final key => receivedPacketsFor(key),
  };

  /// How many pictures the stream on the stage has produced.
  int get decodedUnits => switch (watching) {
    null => 0,
    final key => decodedUnitsFor(key),
  };

  /// The most recent failure, whichever session it was. [errorFor] is the
  /// precise answer, and the one a caller acting on a single stream wants.
  Object? get error => _errors.values.lastOrNull;

  /// Why [key] could not be opened, or null when it was, or has been since.
  Object? errorFor(GoLiveStreamKey key) => _errors[key];

  /// Records a refusal from the RTC side, which can happen after the watch ask
  /// itself already succeeded. The tile keeps this error while the next ask
  /// gets a clean attempt.
  void reportError(GoLiveStreamKey key, Object error) {
    if (_disposed) return;
    _errors[key] = error;
    _diagnose('watch failed ${key.userId}: $error');
    _order.remove(key);
    _cancelled.add(key);
    unawaited(_teardown(key));
    _notify();
  }

  /// Suspends or resumes every watched session: what turns packets into
  /// pictures is let go, and nothing else moves.
  ///
  /// Suspending is not pausing. A pause is a sender holding pictures back, and
  /// everybody watching them loses them; suspension is this client's window
  /// having nothing on screen, which is nobody's business but its own. The
  /// connection is kept and read, so coming back does not wait on a handshake
  /// or on Discord being asked again, and a stream this account is sending is
  /// not touched at all (ADR-0003).
  void setSuspended(bool value) {
    if (_disposed || _suspended == value) return;
    _suspended = value;
    _diagnose(value ? 'suspended' : 'resumed');
    unawaited(_applySuspension());
    _notify();
  }

  /// Asks Discord to send [key]'s stream to this client.
  ///
  /// Nothing is decoded yet: this is the ask, and the endpoint it is answered
  /// with is what opens the connection the pictures cross.
  Future<bool> requestWatch(GoLiveStreamKey key) async {
    if (_disposed) return false;
    final repository = _repositoryProvider();
    if (repository == null || !isSupported) {
      // A silent false here is a button that looks dead. Say which of the
      // two preconditions failed, because the answer changes the fix: a
      // missing repository is the voice connection, and a missing decoder
      // is the build.
      _diagnose(
        'watch not asked ${key.userId}: repository ${repository != null}, '
        'supported $isSupported',
      );
      return false;
    }
    // Already held: asking again would open a second connection for one
    // stream.
    if (isOpen(key)) {
      _diagnose('watch already held ${key.userId}, not asking again');
      return true;
    }
    if (!_canHold(key)) {
      _diagnose('watch refused, every seat is held ($maxWatchedStreams)');
      _refused = key;
      _notify();
      return false;
    }
    _errors.remove(key);
    // Asking again overrides a withdrawal: the key is only held against the
    // connection that was already on its way.
    _cancelled.remove(key);
    _requested(key);
    _notify();
    final asked = await _ask(repository, key);
    if (asked) _onWatchRequested?.call(key);
    return asked;
  }

  /// Starts decoding [packets] as [key], without asking Discord again.
  ///
  /// Used once the stream connection is up: the ask already went out, and
  /// repeating it would open a second one.
  Future<bool> attach(
    GoLiveStreamKey key, {
    required Stream<IncomingVideoPacket> packets,
    Stream<VoiceRemoteOpusFrame>? audio,

    /// Decrypts one whole picture for this stream's group, bound to whoever
    /// is sending it. Per session rather than per controller because each
    /// stream has a connection of its own, and its group with it.
    VideoPictureGroupDecryptor? groupDecryptor,

    /// Asked when the stream's references are broken: the session's
    /// connection is what can ask the sender for a keyframe.
    void Function()? requestKeyframe,
  }) async {
    if (_disposed) return false;
    // A ready endpoint is not proof that this client still wants the stream.
    // Discord can answer a withdrawn or stale request after the room changed.
    if (!isOpen(key)) return false;
    if (_cancelled.remove(key)) return false;
    if (!isSupported) return false;
    if (!_canHold(key)) {
      _refused = key;
      _notify();
      return false;
    }
    _errors.remove(key);
    // A connection reopened for a key already being read replaces it. That
    // await is a crossing: the ask may have been withdrawn meanwhile, or
    // another reopened connection may already have been installed, and a
    // session put over that one would leave it reading with nobody holding
    // it. Only awaited when there is something to replace, so the plain case
    // installs without a gap.
    if (_sessions.containsKey(key)) {
      await _teardown(key);
      if (_disposed || !isOpen(key) || _sessions.containsKey(key)) {
        return false;
      }
    }
    final session = _install(
      key,
      packets,
      audio,
      groupDecryptor,
      requestKeyframe,
    );
    _notify();
    // Suspended: the connection is read and counted, and nothing decodes it
    // until the window is back. The session is installed either way, so the
    // room goes on showing the stream it was holding (ADR-0003), and no
    // decoder is opened for a window that is not looking at it.
    if (_suspended) return true;
    try {
      await session.pipeline.setDecoding(true);
    } on Object catch (error) {
      if (identical(_sessions[key], session)) {
        _errors[key] = error;
        await _teardown(key);
        _notify();
      }
      return false;
    }
    // That await is a crossing: the ask may have been withdrawn, the
    // controller disposed, or the connection reopened and another session
    // installed over this one. The pipeline handed its decoder back in each
    // case; this only answers whether the session is still the one held.
    return identical(_sessions[key], session);
  }

  /// Starts watching [key], reading packets from [packets].
  ///
  /// The ask and the decode in one call, for a caller holding the packet
  /// stream already. The router's path splits them, because Discord answers
  /// with an endpoint seconds after the ask.
  Future<bool> watch(
    GoLiveStreamKey key, {
    required Stream<IncomingVideoPacket> packets,
    Stream<VoiceRemoteOpusFrame>? audio,
    VideoPictureGroupDecryptor? groupDecryptor,
  }) async {
    if (_disposed) return false;
    final repository = _repositoryProvider();
    if (repository == null || !isSupported) return false;
    if (isOpen(key)) await stop(key);
    if (!_canHold(key)) {
      _refused = key;
      _notify();
      return false;
    }
    _errors.remove(key);
    // A fresh ask for a key that was just closed: the withdrawal that closing
    // it recorded is against the connection on its way, not this one.
    _cancelled.remove(key);
    _requested(key);
    _notify();
    if (!await _ask(repository, key)) return false;
    _onWatchRequested?.call(key);
    return attach(
      key,
      packets: packets,
      audio: audio,
      groupDecryptor: groupDecryptor,
    );
  }

  /// Ends [key]'s session, or every session there is when no key is given.
  ///
  /// Without a key is what leaving a room needs: everything this client is
  /// holding goes.
  Future<void> stop([GoLiveStreamKey? key]) async {
    for (final each in key == null ? [..._order] : [key]) {
      final wasOpen = _order.remove(each);
      final arrived = _sessions.containsKey(each);
      // A control that answers a press by withdrawing a held ask looks
      // exactly like a button that does nothing. Say so.
      if (key != null) {
        _diagnose(
          'watch stop for ${each.userId}: was held $wasOpen, '
          'arrived $arrived',
        );
      }
      await _teardown(each);
      _onWatchStopped?.call(each);
      if (wasOpen && !arrived) {
        // Withdrawing an ask Discord never answered has to be both announced
        // and remembered: announced so the tile's control goes back to opening
        // the stream, remembered so the connection Discord opens anyway is
        // dropped here instead of taking the stage.
        _cancelled.add(each);
      }
    }
    // Once for the whole stop, not once per session: the room is rebuilt
    // either way, and it cannot be drawn between the two.
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      stop().then((_) async {
        await _pcm.close();
        await _audioEnded.close();
      }),
    );
    super.dispose();
  }

  /// Puts [key] last, which is where the stage reads from.
  void _requested(GoLiveStreamKey key) {
    _order.remove(key);
    _order.add(key);
    if (_refused == key) _refused = null;
  }

  /// Notes that [key] is held, leaving its place alone.
  ///
  /// Split from [_requested] because arriving is not asking: the order is
  /// what the stage reads, and an endpoint Discord took its time over says
  /// nothing about when the stream behind it was wanted.
  void _admitted(GoLiveStreamKey key) {
    if (!_order.contains(key)) _order.add(key);
    if (_refused == key) _refused = null;
  }

  Future<bool> _ask(GoLiveRepository repository, GoLiveStreamKey key) async {
    try {
      await repository.watchStream(key);
      _diagnose('asked to watch ${key.userId}');
      return true;
    } on Object catch (error) {
      _errors[key] = error;
      _diagnose('watch refused ${key.userId}: $error');
      _order.remove(key);
      _notify();
      return false;
    }
  }

  /// Whether [key] is this account's own share.
  ///
  /// It is still a normal watched session: the sender asks Discord for it on a
  /// second connection and gets the same packets a watcher does (ADR-0001).
  bool _isOwn(GoLiveStreamKey key) => _ownKeyProvider?.call() == key;

  /// Whether [key] can take a slot now. The own key is reserved in [_held]
  /// before its watch ask goes out, so it gets to consume that reservation
  /// rather than being rejected for filling it.
  bool _canHold(GoLiveStreamKey key) =>
      isOpen(key) || (_isOwn(key) ? _held <= maxWatchedStreams : !isFull);

  /// How many sessions this client is holding, own share included.
  int get _held {
    final own = _ownKeyProvider?.call();
    return own == null || isOpen(own) ? _order.length : _order.length + 1;
  }

  /// The key asked for most recently of those [test] accepts.
  GoLiveStreamKey? _lastWhere(bool Function(GoLiveStreamKey key) test) {
    for (var index = _order.length - 1; index >= 0; index--) {
      final key = _order[index];
      if (test(key)) return key;
    }
    return null;
  }

  /// Ends [key]'s session, leaving its place in the room alone. Its decoder,
  /// pacer and audio go in one step (ADR-0004).
  Future<void> _teardown(GoLiveStreamKey key) async {
    final session = _sessions.remove(key);
    if (session == null) return;
    await session.close();
  }

  /// Brings every session to what [_suspended] asks of it: decoding let go
  /// when the window is away, and reopened when it is back.
  ///
  /// Nothing here touches Discord, and nothing here touches sending, so a
  /// session comes back with the connection it already had (ADR-0003).
  Future<void> _applySuspension() async {
    // A copy: a session can be stopped while the others are being brought
    // back, and the map is not theirs to hold still.
    for (final entry in _sessions.entries.toList()) {
      final key = entry.key;
      final decoding = !_suspended;
      try {
        await entry.value.pipeline.setDecoding(decoding);
      } on Object catch (error) {
        // The session is not thrown away because a decoder would not open:
        // the connection is still there, and the room is told why there is
        // no picture.
        _errors[key] = error;
        _diagnose('decoder failed for ${key.userId}: $error');
        _notify();
        continue;
      }
      // A decoder that opened clears the failure of one that would not.
      if (decoding && _errors.remove(key) != null) _notify();
    }
  }

  /// Starts reading [packets] as [key], and records the session as held.
  ///
  /// Arrival is not an ask, so it does not move this key: the stage shows
  /// whichever was asked for last, and an endpoint Discord was slow to answer
  /// must not overtake a newer one on its way in.
  _WatchedSession _install(
    GoLiveStreamKey key,
    Stream<IncomingVideoPacket> packets,
    Stream<VoiceRemoteOpusFrame>? audio,
    VideoPictureGroupDecryptor? groupDecryptor,
    void Function()? requestKeyframe,
  ) {
    _admitted(key);
    final audioDecoders = _audioDecoderFactory;
    final pipeline = WatchedSessionPipeline(
      decoderFactory: _decoderFactory,
      groupDecryptor: groupDecryptor,
      requestKeyframe: requestKeyframe,
      audio: audio == null || audioDecoders == null
          ? null
          : (
              frames: audio,
              decoderFactory: audioDecoders,
              sourceId: 'stream:${key.value}:${++_audioSources}',
            ),
      // The first picture is news to the room: the stream went from arriving
      // to showing. Every picture after it is not, and telling the room about
      // each one rebuilt its widget tree at the stream's frame rate. The
      // pictures themselves travel on [framesFor].
      onFirstPicture: () {
        _diagnose('first picture handed to the decoder for ${key.userId}');
        _notify();
      },
    );
    final session = _WatchedSession(pipeline);
    // In the map before it is listened to: a stream that already has a
    // packet in it delivers on subscription.
    _sessions[key] = session;
    session.packets = packets.listen(
      pipeline.accept,
      onError: (Object error, StackTrace stackTrace) =>
          _acceptError(key, error),
    );
    session.pcm = pipeline.pcm.listen((frame) {
      if (!_pcm.isClosed) _pcm.add(frame);
    });
    session.audioEnded = pipeline.audioEnded.listen((sourceId) {
      if (!_audioEnded.isClosed) _audioEnded.add(sourceId);
    });
    return session;
  }

  void _diagnose(String what) {
    AppLog.warning('stream', what);
  }

  void _acceptError(GoLiveStreamKey key, Object error) {
    _errors[key] = error;
    _diagnose('watch failed ${key.userId}: $error');
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// One stream being watched: its pipeline, and the subscriptions that feed
/// it packets and carry its sound into the room's.
final class _WatchedSession {
  _WatchedSession(this.pipeline);

  final WatchedSessionPipeline pipeline;
  StreamSubscription<IncomingVideoPacket>? packets;
  StreamSubscription<VoiceRemotePcmFrame>? pcm;
  StreamSubscription<String>? audioEnded;

  Future<void> close() async {
    await packets?.cancel();
    // Closed before the audio subscriptions go: the ended signal travels on
    // them.
    await pipeline.close();
    await pcm?.cancel();
    await audioEnded?.cancel();
  }
}
