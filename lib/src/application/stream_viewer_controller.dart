import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_h264_depacketizer.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_decoder.dart';
import '../app_log.dart';

/// One RTP payload as it arrives from a stream connection.
final class IncomingVideoPacket {
  const IncomingVideoPacket({required this.payload, required this.marker});

  final Uint8List payload;

  /// Whether this payload ends a picture.
  final bool marker;
}

/// How many streams this client holds at once.
///
/// Ours and not Discord's: nothing is documented on their side, and every
/// session costs a decoder and a connection of its own.
const int maxWatchedStreams = 4;

/// Watches several Go Live streams at once, one session apiece.
///
/// Three things in a row that were each built and none of which were joined:
/// packets arrive, the depacketiser turns them back into access units, and the
/// decoder turns those into pictures. Each session owns one of each, because
/// two senders interleaved on a single depacketiser splice one picture into
/// another's, and a single decoder has nowhere to put a second stream's.
final class StreamViewerController extends ChangeNotifier {
  StreamViewerController({
    required GoLiveRepository? Function() repositoryProvider,
    required VideoDecoderService Function() decoderFactory,
    GoLiveStreamKey? Function()? ownKeyProvider,
  }) : _repositoryProvider = repositoryProvider,
       _decoderFactory = decoderFactory,
       _ownKeyProvider = ownKeyProvider;

  final GoLiveRepository? Function() _repositoryProvider;
  final VideoDecoderService Function() _decoderFactory;

  /// This account's own share. Not watched here — it is the capture that
  /// feeds it — but it is a session like any other and counts towards the cap
  /// (ADR-0002).
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
  Object? _error;
  bool _disposed = false;

  /// Whether this build can decode at all, which is a property of the build
  /// rather than of any one session: one decoder is made to ask, and never
  /// started.
  late final bool isSupported = _decoderFactory().isSupported;

  /// Whose stream is on the stage: the one asked for most recently of those
  /// whose pictures are arriving.
  ///
  /// An ask is not on the stage: the endpoint it is answered with may never
  /// come, and a request Discord never answered must not take the room away.
  GoLiveStreamKey? get watching => _lastWhere(isWatching);

  /// Whose stream was asked for most recently and has not started arriving.
  ///
  /// Separate from [watching] because the two are seconds apart: the ask goes
  /// out on the main gateway, Discord answers with an endpoint, and only the
  /// connection that answer opens produces pictures. A button that waited for
  /// [watching] would look dead for the whole handshake.
  GoLiveStreamKey? get requested => _lastWhere(isRequested);

  /// The ask turned down because this client is holding all it will hold.
  GoLiveStreamKey? get refused => _refused;

  /// Pictures from [key]'s stream.
  ///
  /// Per key rather than one stream for the room: the stage draws one session,
  /// and which one changes.
  Stream<DecodedVideoFrame> framesFor(GoLiveStreamKey key) =>
      _sessions[key]?.decoder.frames ?? const Stream<DecodedVideoFrame>.empty();

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
      _sessions[key]?.receivedPackets ?? 0;

  /// How many access units came back out of [key]'s depacketiser, which is
  /// what separates "packets are arriving" from "pictures are arriving".
  int decodedUnitsFor(GoLiveStreamKey key) => _sessions[key]?.decodedUnits ?? 0;

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

  Object? get error => _error;

  /// Asks Discord to send [key]'s stream to this client.
  ///
  /// Nothing is decoded yet: this is the ask, and the endpoint it is answered
  /// with is what opens the connection the pictures cross.
  Future<bool> requestWatch(GoLiveStreamKey key) async {
    final repository = _repositoryProvider();
    if (repository == null || !isSupported) return false;
    // Already held: asking again would open a second connection for one
    // stream.
    if (isOpen(key)) return true;
    if (isFull) {
      _refused = key;
      _notify();
      return false;
    }
    _error = null;
    // Asking again overrides a withdrawal: the key is only held against the
    // connection that was already on its way.
    _cancelled.remove(key);
    _requested(key);
    _notify();
    return _ask(repository, key);
  }

  /// Starts decoding [packets] as [key], without asking Discord again.
  ///
  /// Used once the stream connection is up: the ask already went out, and
  /// repeating it would open a second one.
  Future<bool> attach(
    GoLiveStreamKey key, {
    required Stream<IncomingVideoPacket> packets,
  }) async {
    if (_cancelled.remove(key)) return false;
    if (!isSupported) return false;
    if (!isOpen(key) && isFull) {
      _refused = key;
      _notify();
      return false;
    }
    _error = null;
    // A connection reopened for a key already being read replaces it.
    await _teardown(key);
    final decoder = _decoderFactory();
    try {
      await decoder.start();
    } on Object catch (error) {
      _error = error;
      _notify();
      return false;
    }
    _requested(key);
    final session = _WatchedSession(key, decoder);
    // In the map before it is listened to: a stream that already has a
    // packet in it delivers on subscription.
    _sessions[key] = session;
    session.packets = packets.listen(
      (packet) => _accept(key, packet),
      onError: _acceptError,
    );
    _notify();
    return true;
  }

  /// Starts watching [key], reading packets from [packets].
  ///
  /// The ask and the decode in one call, for a caller holding the packet
  /// stream already. The router's path splits them, because Discord answers
  /// with an endpoint seconds after the ask.
  Future<bool> watch(
    GoLiveStreamKey key, {
    required Stream<IncomingVideoPacket> packets,
  }) async {
    final repository = _repositoryProvider();
    if (repository == null || !isSupported) return false;
    if (isOpen(key)) await stop(key);
    if (isFull) {
      _refused = key;
      _notify();
      return false;
    }
    _error = null;
    // A fresh ask for a key that was just closed: the withdrawal that closing
    // it recorded is against the connection on its way, not this one.
    _cancelled.remove(key);
    _requested(key);
    _notify();
    if (!await _ask(repository, key)) return false;
    return attach(key, packets: packets);
  }

  /// Ends [key]'s session, or every session there is when no key is given.
  ///
  /// Without a key is what leaving a room needs: everything this client is
  /// holding goes.
  Future<void> stop([GoLiveStreamKey? key]) async {
    for (final each in key == null ? [..._order] : [key]) {
      final wasOpen = _order.remove(each);
      final arrived = _sessions.containsKey(each);
      await _teardown(each);
      if (wasOpen && !arrived) {
        // Withdrawing an ask Discord never answered has to be both announced
        // and remembered: announced so the tile's control goes back to opening
        // the stream, remembered so the connection Discord opens anyway is
        // dropped here instead of taking the stage.
        _cancelled.add(each);
      }
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }

  /// Puts [key] last, which is where the stage reads from.
  void _requested(GoLiveStreamKey key) {
    _order.remove(key);
    _order.add(key);
    if (_refused == key) _refused = null;
  }

  Future<bool> _ask(GoLiveRepository repository, GoLiveStreamKey key) async {
    try {
      await repository.watchStream(key);
      _diagnose('asked to watch ${key.userId}');
      return true;
    } on Object catch (error) {
      _error = error;
      _order.remove(key);
      _notify();
      return false;
    }
  }

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

  /// Ends [key]'s decoder and subscription, leaving its place in the room
  /// alone.
  Future<void> _teardown(GoLiveStreamKey key) async {
    final session = _sessions.remove(key);
    if (session == null) return;
    final packets = session.packets;
    session.packets = null;
    await packets?.cancel();
    await session.decoder.stop();
  }

  void _diagnose(String what) {
    AppLog.warning('stream', what);
  }

  void _accept(GoLiveStreamKey key, IncomingVideoPacket packet) {
    final session = _sessions[key];
    if (session == null) return;
    // The first one is worth saying: it is the difference between a stream
    // that was asked for and one that is arriving.
    if (session.receivedPackets == 0) {
      _diagnose('first packet from ${key.userId}');
    }
    session.receivedPackets++;
    final unit = session.depacketizer.accept(
      packet.payload,
      marker: packet.marker,
    );
    if (unit == null) return;
    session.decodedUnits++;
    unawaited(session.decoder.submit(unit));
    _notify();
  }

  void _acceptError(Object error) {
    _error = error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// One stream being watched: its own depacketiser, decoder and subscription.
final class _WatchedSession {
  _WatchedSession(this.key, this.decoder)
    : depacketizer = DiscordH264Depacketizer();

  final GoLiveStreamKey key;
  final VideoDecoderService decoder;
  final DiscordH264Depacketizer depacketizer;
  StreamSubscription<IncomingVideoPacket>? packets;
  int receivedPackets = 0;
  int decodedUnits = 0;
}
