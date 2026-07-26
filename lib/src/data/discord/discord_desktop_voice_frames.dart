import 'discord_desktop_gateway_protocol.dart';

/// Builds the voice frames a desktop session sends, and remembers the ones it
/// has to send again.
///
/// Both kinds of voice state die with the socket: the server forgets which
/// channel the session was in and which private channels it had subscribed to,
/// so a reconnect that does not replay them leaves the user silently outside
/// the room they are still looking at. Keeping the intent here rather than in
/// the socket owner is what makes the replay set testable without a websocket.
final class DiscordDesktopVoiceFrames {
  final Map<String, Map<String, Object?>> _desiredVoiceStates = {};
  final Set<String> _watchedCallChannels = <String>{};

  /// Records a voice-state intent and returns the frame that carries it.
  ///
  /// R08: the desktop renderer always sends all six fields. `self_video` and
  /// `flags` are not optional — a body missing them is a tell that the session
  /// is not the client it claims to be — and `flags` is legitimately `0`, since
  /// it only carries clips and Go Live bits, neither of which Flucord has.
  /// `preferred_region`/`preferred_regions` stay absent rather than null: the
  /// renderer omits the keys until a latency test has ranked regions, and
  /// Flucord has never run one.
  ///
  /// [sessionKey] is the guild for guild voice and the channel for a private
  /// call, so a move between two channels of one guild replaces a single
  /// desired state rather than accumulating a second.
  DiscordDesktopGatewayFrame voiceState({
    required String sessionKey,
    required String? guildId,
    required String? channelId,
    required bool selfMute,
    required bool selfDeaf,
  }) {
    final body = <String, Object?>{
      'guild_id': guildId,
      'channel_id': channelId,
      'self_mute': selfMute,
      'self_deaf': selfDeaf,
      'self_video': false,
      'flags': 0,
    };
    if (channelId == null) {
      _desiredVoiceStates.remove(sessionKey);
    } else {
      _desiredVoiceStates[sessionKey] = body;
    }
    return DiscordDesktopGatewayFrame(
      DiscordDesktopGatewayOpcode.voiceStateUpdate,
      body,
    );
  }

  /// Records a call subscription and returns its opcode 13 frame, or null when
  /// the channel id is not one.
  DiscordDesktopGatewayFrame? callConnect(String channelId) {
    if (channelId.isEmpty) return null;
    _watchedCallChannels.add(channelId);
    return _callConnectFrame(channelId);
  }

  /// Opcode 5, whose payload is the literal null rather than an empty object.
  DiscordDesktopGatewayFrame get voiceServerPing =>
      const DiscordDesktopGatewayFrame(
        DiscordDesktopGatewayOpcode.voiceServerPing,
        null,
      );

  /// Everything a fresh session has to be told again.
  Iterable<DiscordDesktopGatewayFrame> get replay => [
    for (final body in _desiredVoiceStates.values)
      DiscordDesktopGatewayFrame(
        DiscordDesktopGatewayOpcode.voiceStateUpdate,
        body,
      ),
    for (final channelId in _watchedCallChannels) _callConnectFrame(channelId),
  ];

  void clear() {
    _desiredVoiceStates.clear();
    _watchedCallChannels.clear();
  }

  static DiscordDesktopGatewayFrame _callConnectFrame(String channelId) =>
      DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.callConnect, {
        'channel_id': channelId,
      });
}
