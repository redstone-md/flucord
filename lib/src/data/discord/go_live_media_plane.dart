import '../../domain/go_live_stream.dart';
import '../../domain/video_capture_hub.dart';
import '../../domain/video_encoder.dart';
import '../../domain/voice_connection.dart';
import 'discord_voice_socket_factory.dart';
import 'go_live_sender.dart';

/// Where this account's stream is sent from.
///
/// The Sender factory: where a Sender runs is the plane's decision. The app
/// runs it on an isolate of its own ([GoLiveMediaIsolate]), and the tests
/// run it in-process. As the capture hub's share destination, the plane says
/// where the encoder delivers a stream's frames and echoes them back for the
/// clip buffer.
abstract interface class GoLiveMediaPlane implements ShareFrameDestination {
  /// Opens a Sender on the endpoint Discord handed out, which dials at once
  /// and announces [settings] when its connection is ready.
  GoLiveSender openSender({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
    required VideoEncoderSettings settings,
  });
}

/// The plane with everything on the calling isolate.
///
/// What the tests use, and what a sender looks like with no isolate between
/// the encoder and the socket: [frames] are the encoder's own stream.
final class InProcessGoLiveMediaPlane implements GoLiveMediaPlane {
  InProcessGoLiveMediaPlane({
    required Stream<EncodedVideoFrame> frames,
    DiscordVoiceSocketFactory? socketFactory,
  }) : _frames = frames,
       _socketFactory = socketFactory ?? DiscordVoiceGatewaySocketFactory();

  final Stream<EncodedVideoFrame> _frames;
  final DiscordVoiceSocketFactory _socketFactory;

  @override
  Future<int?> get nativeFrameSink => Future.value(null);

  @override
  Stream<EncodedVideoFrame> get relayedFrames =>
      const Stream<EncodedVideoFrame>.empty();

  @override
  GoLiveSender openSender({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
    required VideoEncoderSettings settings,
  }) => GoLiveWireSender(
    client: _socketFactory.streamSocket(
      credentials: credentials,
      streamKey: streamKey,
    ),
    frames: _frames,
    settings: settings,
  );
}
