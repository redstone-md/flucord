import '../../domain/go_live_stream.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_websocket.dart';

/// The one construction site for a socket on Discord's voice plane.
///
/// A call's socket and a Go Live stream's socket are the same client
/// underneath. What differs is the configuration, and those differences live
/// here once rather than hand-assembled at each caller:
///
/// - both kinds join an MLS group when the account has DAVE, each its own:
///   a call's group is the voice channel's, and a stream is a separate media
///   session with a separate group of its own (discord/dave-protocol), which
///   the credentials' channel already names: the RTC channel the create
///   assigned the stream to;
/// - a stream socket says at identify that it carries a screen. One that
///   does not is closed with `identifyRefused` as soon as it finishes
///   connecting;
/// - a session without DAVE offers version 0, which is what tells Discord to
///   stay on the transport cipher rather than negotiating a group.
///
/// The DAVE rules follow discord/dave-protocol, Discord's reference for
/// end-to-end encryption of voice and Go Live.
abstract interface class DiscordVoiceSocketFactory {
  /// The DAVE version every socket from here offers; 0 without DAVE.
  int get maxDaveProtocolVersion;

  /// The socket a call runs on.
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials);

  /// The socket a Go Live stream of [streamKey] runs on.
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  });
}

/// Decides DAVE per socket kind and builds gateway clients.
final class DiscordVoiceGatewaySocketFactory
    implements DiscordVoiceSocketFactory {
  DiscordVoiceGatewaySocketFactory({
    VoiceDaveService? daveService,

    /// The websocket seam, which tests substitute to see the wire. Production
    /// leaves it null and dials real sockets.
    DiscordVoiceSocketConnector? socketConnector,
  }) : _daveService = daveService,
       _socketConnector = socketConnector;

  final VoiceDaveService? _daveService;
  final DiscordVoiceSocketConnector? _socketConnector;

  /// What both kinds offer, from one source. A stream of a call has to say
  /// the same thing the call did, so the two cannot drift apart here.
  @override
  int get maxDaveProtocolVersion => _daveService?.maxProtocolVersion ?? 0;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      DiscordVoiceGatewayClient(
        credentials: credentials,
        maxDaveProtocolVersion: maxDaveProtocolVersion,
        daveService: _daveService,
        socketConnector: _socketConnector,
      );

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) => DiscordVoiceGatewayClient(
    credentials: credentials,
    maxDaveProtocolVersion: maxDaveProtocolVersion,
    daveService: _daveService,
    socketConnector: _socketConnector,
    streamKey: streamKey.value,
    carriesVideo: true,
  );
}
