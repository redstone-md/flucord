import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_h264_depacketizer.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_decoder.dart';
import '../domain/voice_audio.dart';
import '../app_log.dart';
import 'watched_stream_audio.dart';

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

    /// Turns a stream's arriving sound into samples, or null in a build with
    /// no Opus decoder, where a watched stream is silent.
    WatchedStreamAudio? audio,
  }) : _repositoryProvider = repositoryProvider,
       _decoderFactory = decoderFactory,
       _ownKeyProvider = ownKeyProvider,
       _onWatchRequested = onWatchRequested,
       _audio = audio;

  final GoLiveRepository? Function() _repositoryProvider;
  final VideoDecoderService Function() _decoderFactory;
  final void Function(GoLiveStreamKey key)? _onWatchRequested;

  /// The sound of what is being watched, held apart from the pictures because
  /// the two are not the same resource and do not end the same way: a decoder
  /// per session, and a receiver per session (ADR-0004).
  final WatchedStreamAudio? _audio;

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

  /// Whether this client's window is out of the foreground, which is this
  /// client's own business alone: sessions go on receiving and draw nothing
  /// (ADR-0003).
  bool _suspended = false;

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

  /// Whether this client's window is out of the foreground: what is on the
  /// stage is still a stream that is arriving, and nothing is being drawn for
  /// it until the window is back (ADR-0003).
  bool get isSuspended => _suspended;

  /// Pictures from [key]'s stream.
  ///
  /// Per key rather than one stream for the room: the stage draws one session,
  /// and which one changes.
  Stream<DecodedVideoFrame> framesFor(GoLiveStreamKey key) =>
      _sessions[key]?.decoder?.frames ??
      const Stream<DecodedVideoFrame>.empty();

  /// The sound of every stream being watched, playable on the room's output.
  ///
  /// Nothing but the streams this client is holding is on it: sound is bound
  /// when a session is, so a stream nobody opened is silent and stopping a
  /// watch ends the sound with the session (ADR-0004).
  Stream<VoiceRemotePcmFrame> get audio =>
      _audio?.pcm ?? const Stream<VoiceRemotePcmFrame>.empty();

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

  /// Suspends or resumes every watched session: what turns packets into
  /// pictures is let go, and nothing else moves.
  ///
  /// Suspending is not pausing. A pause is a sender holding pictures back, and
  /// everybody watching them loses them; suspension is this client's window
  /// not being in the foreground, which is nobody's business but its own. The
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
    Stream<VoiceRemoteOpusFrame>? audio,
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
    // Suspended: the connection is read and counted, and nothing decodes it
    // until the window is back. The session is installed either way, so the
    // room goes on showing the stream it was holding (ADR-0003), and no
    // decoder is opened for a window that is not looking at it.
    if (_suspended) {
      _install(key, packets, audio);
      _notify();
      return true;
    }
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
    final session = _install(key, packets, audio);
    // The window may have gone away while the decoder was opening, which is a
    // crossing the check above cannot see: this key was not in [_sessions]
    // yet, so suspending did not reach it. The connection is kept and read,
    // and a decoder nobody is looking at is handed straight back.
    if (_suspended) {
      await decoder.stop();
      _notify();
      return true;
    }
    session.attachDecoder(decoder);
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
    Stream<VoiceRemoteOpusFrame>? audio,
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
    return attach(key, packets: packets, audio: audio);
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
    // The sound goes with the session, not with the pictures: watching is what
    // gives it somewhere to play, so once this key is gone there is nothing
    // left to play it into (ADR-0004).
    await _audio?.detach(key);
    final session = _sessions.remove(key);
    if (session == null) return;
    final packets = session.packets;
    session.packets = null;
    await packets?.cancel();
    await _releaseDecoder(session);
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
      if (_suspended) {
        await _releaseDecoder(entry.value);
      } else {
        await _openDecoder(entry.key);
      }
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
  ) {
    _admitted(key);
    final session = _WatchedSession();
    // In the map before it is listened to: a stream that already has a
    // packet in it delivers on subscription.
    _sessions[key] = session;
    session.packets = packets.listen(
      (packet) => _accept(key, packet),
      onError: (Object error, StackTrace stackTrace) =>
          _acceptError(key, error),
    );
    // Bound with the session rather than with the decoder: suspension is this
    // client not drawing, and a window nobody is looking at is still being
    // listened to (ADR-0003).
    if (audio != null) _bindAudio(key, audio);
    return session;
  }

  /// Gives [key]'s session its sound, without holding the session up for it.
  ///
  /// The pictures are what a session is for, and a stream with no sound is
  /// still a stream; a failure here is worth saying, not worth failing the
  /// watch over.
  void _bindAudio(GoLiveStreamKey key, Stream<VoiceRemoteOpusFrame> audio) {
    final binding = _audio?.attach(key, audio);
    if (binding == null) return;
    unawaited(
      binding.catchError(
        (Object error) => _diagnose('stream audio for ${key.userId}: $error'),
      ),
    );
  }

  /// Opens [key]'s decoder, and hands the session a depacketiser to feed it
  /// with.
  ///
  /// Also how a suspended session comes back. The depacketiser is made fresh
  /// rather than kept: half a picture from before the window went away is not
  /// the start of one, and the first picture back is a moment behind until
  /// the sender sends a keyframe (ADR-0003).
  Future<bool> _openDecoder(GoLiveStreamKey key) async {
    final session = _sessions[key];
    if (session == null || session.decoder != null) return false;
    final decoder = _decoderFactory();
    try {
      await decoder.start();
    } on Object catch (error) {
      _errors[key] = error;
      _diagnose('decoder failed for ${key.userId}: $error');
      _notify();
      return false;
    }
    // That await is a crossing, and each way across leaves this decoder with
    // nothing to decode for: the window may have gone again, the session may
    // have been stopped, the controller may have been disposed, or another
    // decoder may have been opened for this session while this one was
    // starting, which is what two resumes in a row do. A decoder nobody wants
    // is handed back rather than left running, and one installed over another
    // would leave the first decoding with nobody holding it.
    if (_disposed ||
        _suspended ||
        session.decoder != null ||
        !identical(_sessions[key], session)) {
      await decoder.stop();
      return false;
    }
    session.attachDecoder(decoder);
    _errors.remove(key);
    _notify();
    return true;
  }

  /// Lets go of what turns [session]'s packets into pictures, keeping the
  /// subscription that keeps the connection alive.
  Future<void> _releaseDecoder(_WatchedSession session) async {
    final decoder = session.decoder;
    session.decoder = null;
    session.depacketizer = null;
    if (decoder == null) return;
    await decoder.stop();
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
    final depacketizer = session.depacketizer;
    final decoder = session.decoder;
    // Suspended: the packet is counted, so a stream that is arriving still
    // reads as arriving, and that is all that is done with it (ADR-0003).
    if (depacketizer == null || decoder == null) return;
    final unit = depacketizer.accept(packet.payload, marker: packet.marker);
    if (unit == null) return;
    session.decodedUnits++;
    unawaited(decoder.submit(unit));
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
///
/// The decoder and the depacketiser are absent while this client is suspended,
/// and the subscription is not: the connection stays up and its packets keep
/// being counted, they just stop becoming pictures (ADR-0003).
final class _WatchedSession {
  _WatchedSession();

  VideoDecoderService? decoder;
  DiscordH264Depacketizer? depacketizer;
  StreamSubscription<IncomingVideoPacket>? packets;
  int receivedPackets = 0;
  int decodedUnits = 0;

  /// Gives the session what turns its packets into pictures.
  ///
  /// The depacketiser comes with the decoder rather than outliving it: half a
  /// picture left over from before a gap is not the start of one.
  void attachDecoder(VideoDecoderService opened) {
    decoder = opened;
    depacketizer = DiscordH264Depacketizer();
  }
}
