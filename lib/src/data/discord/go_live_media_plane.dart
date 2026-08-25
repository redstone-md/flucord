import 'dart:async';
import 'dart:typed_data';

import '../../domain/go_live_media.dart';
import '../../domain/go_live_stream.dart';
import '../../domain/video_encoder.dart';
import '../../domain/voice_connection.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_socket_factory.dart';
import 'go_live_sending_client.dart';

/// Where this account's share is sent from.
///
/// The share's connection is opened through here rather than through the
/// socket factory directly, because where it runs is the plane's decision:
/// the app runs it on an isolate of its own ([GoLiveMediaIsolate]), and the
/// tests run it in-process. Either way the encoder, which stays on the main
/// isolate, is steered through the same three streams.
abstract interface class GoLiveMediaPlane {
  /// A native address the encoder can deliver frames to directly, or null
  /// when frames should stay in-process and reach the plane as a stream.
  Future<int?> get nativeFrameSink;

  /// What the far end's feedback asks of the encoder.
  Stream<GoLiveEncoderCommand> get encoderCommands;

  /// One line every few seconds about what the share is sending.
  Stream<String> get paceLines;

  /// The share's frames, echoed back for whoever on the main isolate wants
  /// them too (the clip buffer). Empty when frames never left it.
  Stream<EncodedVideoFrame> get relayedFrames;

  /// Opens the share's connection. Dialled by the caller, like any other.
  DiscordVoiceClient openSender({
    required DiscordVoiceSocketFactory factory,
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  });

  /// Declares a new shape for the running share.
  void announce(VideoEncoderSettings settings);

  /// A new bitrate target for the running share.
  void retarget(int bitrate);

  /// One 20 ms Opus frame of the shared sound.
  void sendAudio(Uint8List opus);
}

/// The plane with everything on the calling isolate.
///
/// What the tests use, and what a sender looks like with no isolate between
/// the encoder and the socket: [frames] are the encoder's own stream.
final class InProcessGoLiveMediaPlane implements GoLiveMediaPlane {
  InProcessGoLiveMediaPlane({
    required Stream<EncodedVideoFrame> frames,
    Duration paceInterval = const Duration(seconds: 5),
  }) : _frames = frames,
       _paceInterval = paceInterval;

  final Stream<EncodedVideoFrame> _frames;
  final Duration _paceInterval;
  final StreamController<GoLiveEncoderCommand> _commands =
      StreamController.broadcast();
  final StreamController<String> _paceLines = StreamController.broadcast();

  GoLiveSendingClient? _current;
  Timer? _pace;

  @override
  Future<int?> get nativeFrameSink => Future.value(null);

  @override
  Stream<GoLiveEncoderCommand> get encoderCommands => _commands.stream;

  @override
  Stream<String> get paceLines => _paceLines.stream;

  @override
  Stream<EncodedVideoFrame> get relayedFrames =>
      const Stream<EncodedVideoFrame>.empty();

  @override
  DiscordVoiceClient openSender({
    required DiscordVoiceSocketFactory factory,
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) {
    late final GoLiveSendingClient client;
    client = GoLiveSendingClient(
      inner: factory.streamSocket(
        credentials: credentials,
        streamKey: streamKey,
      ),
      frames: _frames,
      onEncoderCommand: _commands.add,
      onClosed: () {
        if (!identical(_current, client)) return;
        _current = null;
        _pace?.cancel();
        _pace = null;
      },
    );
    _current = client;
    _pace?.cancel();
    _pace = Timer.periodic(_paceInterval, (_) {
      final line = client.takePaceLine();
      if (line != null) _paceLines.add(line);
    });
    return client;
  }

  @override
  void announce(VideoEncoderSettings settings) =>
      _current?.announceVideo(enabled: true, settings: settings);

  @override
  void retarget(int bitrate) => _current?.retarget(bitrate);

  @override
  void sendAudio(Uint8List opus) => _current?.sendOpusFrame(opus);
}

/// The socket factory the stream plane dials through, with this account's
/// own share handed to the media plane and everybody else's dialled as
/// before.
///
/// A share is the one connection that sends, so it is the one whose sending
/// must not share a thread with the UI; a stream being watched is decoded on
/// the main isolate as it always was.
final class GoLiveMediaSocketFactory implements DiscordVoiceSocketFactory {
  GoLiveMediaSocketFactory({
    required DiscordVoiceSocketFactory inner,
    required GoLiveMediaPlane plane,
  }) : _inner = inner,
       _plane = plane;

  final DiscordVoiceSocketFactory _inner;
  final GoLiveMediaPlane _plane;

  @override
  int get maxDaveProtocolVersion => _inner.maxDaveProtocolVersion;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      _inner.callSocket(credentials);

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) {
    if (streamKey.userId != credentials.userId) {
      return _inner.streamSocket(
        credentials: credentials,
        streamKey: streamKey,
      );
    }
    return _plane.openSender(
      factory: _inner,
      credentials: credentials,
      streamKey: streamKey,
    );
  }
}
