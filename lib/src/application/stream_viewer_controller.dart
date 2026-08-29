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
    void Function(GoLiveStreamKey key)? onWatchRequested,
  }) : _repositoryProvider = repositoryProvider,
       _decoderFactory = decoderFactory,
       _ownKeyProvider = ownKeyProvider,
       _onWatchRequested = onWatchRequested;

  final GoLiveRepository? Function() _repositoryProvider;
  final VideoDecoderService Function() _decoderFactory;
  final void Function(GoLiveStreamKey key)? _onWatchRequested;

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

  /// Asks Discord to send [key]'s stream to this client.
  ///
  /// Nothing is decoded yet: this is the ask, and the endpoint it is answered
  /// with is what opens the connection the pictures cross.
  Future<bool> requestWatch(GoLiveStreamKey key) async {
    if (_disposed) return false;
    final repository = _repositoryProvider();
    if (repository == null || !isSupported) return false;
    // Already held: asking again would open a second connection for one
    // stream.
    if (isOpen(key)) return true;
    if (!_canHold(key)) {
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
  }) async {
    if (_disposed) return false;
    if (_cancelled.remove(key)) return false;
    if (!isSupported) return false;
    if (!_canHold(key)) {
      _refused = key;
      _notify();
      return false;
    }
    _errors.remove(key);
    // A connection reopened for a key already being read replaces it.
    await _teardown(key);
    final decoder = _decoderFactory();
    try {
      await decoder.start();
    } on Object catch (error) {
      _errors[key] = error;
      _notify();
      return false;
    }
    // Those awaits are crossings, and each leaves this decoder with nothing
    // to decode for: the ask may have been withdrawn while it was opening,
    // the controller may have been disposed, or Discord may have reopened the
    // connection and another attach may already be reading it. A decoder
    // nobody wants is handed back rather than left running, and a session
    // installed over one already reading would splice this connection's
    // packets into the other's picture.
    if (_disposed || _cancelled.contains(key) || _sessions.containsKey(key)) {
      await decoder.stop();
      return false;
    }
    // Arrival is not an ask, so it does not move this key: the stage shows
    // whichever was asked for last, and an endpoint Discord was slow to
    // answer must not overtake a newer one on its way in.
    _admitted(key);
    final session = _WatchedSession(decoder);
    // In the map before it is listened to: a stream that already has a
    // packet in it delivers on subscription.
    _sessions[key] = session;
    session.packets = packets.listen(
      (packet) => _accept(key, packet),
      onError: (Object error, StackTrace stackTrace) =>
          _acceptError(key, error),
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
    }
    // Once for the whole stop, not once per session: the room is rebuilt
    // either way, and it cannot be drawn between the two.
    _notify();
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

  void _acceptError(GoLiveStreamKey key, Object error) {
    _errors[key] = error;
    _diagnose('watch failed ${key.userId}: $error');
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// One stream being watched: its own depacketiser, decoder and subscription.
final class _WatchedSession {
  _WatchedSession(this.decoder) : depacketizer = DiscordH264Depacketizer();

  final VideoDecoderService decoder;
  final DiscordH264Depacketizer depacketizer;
  StreamSubscription<IncomingVideoPacket>? packets;
  int receivedPackets = 0;
  int decodedUnits = 0;
}
